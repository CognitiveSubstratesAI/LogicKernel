# ORIGINAL: G1-GC piece G1-9 — the stack invariant checker (`check_stacks!`, `stack_violations`, src/pl-gc.jl; upstream's
# `checkStacks`, pl-gc.c, is compiled in debug/maintenance builds only). White-box, no swipl: test/core_lang/test_gc_checker.jl
#   * sound heaps pass: terms put on the global stack (compounds, shared variables, floats and strings in the value table),
#     and the stacks at every answer of a nondeterministic query (choice points, frames, the trail) — and each check
#     LOOKED at something (the cell count is asserted: a checker that examines nothing passes everything);
#   * deliberately corrupted heaps FAIL, each naming the right check: a reference beyond gTop, a compound word at a
#     non-functor cell, a two-cell reference cycle, a MARK bit (accepted with `allow_marks`), a trail entry beyond gTop,
#     a value-table box out of order, a functor whose arguments run past gTop, a stray tag, a broken attributed-variable
#     chain, a choice point whose saved mark lies above the stacks, a frame record out of order;
#   * `check_stacks!` throws `StackInvariantError` carrying the report, and `PL_check_stacks` answers false as the pin does.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "..", "core_lang", "rules_common.jl"))

"An engine with the values of `vs` put on its global stack (one variable map): its local data."
function _ck_engine(vs::Vector{_R})
    db = _rdb(Tuple{_R, Union{Nothing, _R}}[])
    ld = db.ld
    LK.PL_open_foreign_frame(ld)
    t = LK.PL_new_term_refs(ld, length(vs))
    pvm = LK.PutVarMap()
    for (i, v) in enumerate(vs)
        LK.putSlotValue!(ld, t + i, v, pvm)
    end
    return ld
end

"A heap with compounds, a shared variable, a nested compound, two floats and a string."
function _ck_heap()
    X = _rv(1)
    return _ck_engine(
        _R[
            _rf("f", _rs("a"), X, _rf("g", X, _rg(Int64(3))), _rg(1.5), _rg(2.5)),
            _rf("h", _rg("str"), _rints(1:5), X),
        ]
    )
end

"The positions of the functor cells of `ld`'s global stack."
_ck_functors(ld) = [p for p in 1:(ld.gTop) if LK.isFunctor(ld.gstack[p])]

"The violations of `ld`: non-empty, one of them of check `check` (and `check_stacks!` throws)."
function _ck_fails(ld, check::String; kw...)::Bool
    v = LK.stack_violations(ld; kw...)
    return !isempty(v) && any(m -> startswith(m, "[" * check * "]"), v)
end

@testset "sound heaps pass, and the checker looks at them" begin
    ld = _ck_heap()
    @test ld.gTop >= 20                                         # a non-trivial heap: not vacuous
    @test length(_ck_functors(ld)) >= 4
    @test length(ld.vtable) >= 3                                # two floats and a string: value-table boxes
    @test isempty(LK.stack_violations(ld))
    n = LK.check_stacks!(ld)
    @test n >= ld.gTop                                          # every global cell examined
    @test LK.check_stacks!(ld; allow_marks=true) == n

    ld0 = _ck_engine(_R[])                                      # an empty global stack is sound too
    @test isempty(LK.stack_violations(ld0))
    @test LK.check_stacks!(ld0) >= 0

    @test LK.PL_check_stacks(ld) === false                      # pl-gc.c:4306 in a release build
end

@testset "sound stacks at every answer of a nondeterministic query" begin
    X, Y = _rv(1), _rv(2)
    clauses = Tuple{_R, Union{Nothing, _R}}[
        (_rf("n", _rg(Int64(1))), nothing), (_rf("n", _rg(Int64(2))), nothing),
        (_rf("n", _rg(Int64(3))), nothing),
        (_rf("pair", X, _rf("p", X, Y)), _rf("n", X)),
    ]
    db = _rdb(clauses)
    reports = Vector{String}[]
    counts = Int[]
    chains = Int[]
    ans = _rcall(
        db, _rf("pair", _rv(90), _rv(91));
        at=(qid, k) -> begin
            push!(reports, LK.stack_violations(db.ld))
            push!(counts, LK._check_stacks(db.ld, false).cells)
            push!(chains, db.ld.BFR)
        end
    )
    @test length(ans) == 3
    @test length(reports) == 3
    @test all(isempty, reports)
    @test all(>(0), counts)                                     # the checks examined records
    @test chains[1] != 0                                        # a choice point was live at the first answer
end

@testset "a reference beyond gTop is caught" begin
    ld = _ck_heap()
    a = _ck_functors(ld)[1] + 1
    ld.gstack[a] = LK.makeRefG(ld.gTop + 5)
    @test _ck_fails(ld, "gstack-ref-range")
    @test_throws LK.StackInvariantError LK.check_stacks!(ld)
    ld.gstack[a] = LK.makeRefG(0)                               # position 0 names no cell
    @test _ck_fails(ld, "gstack-ref-range")
end

@testset "a compound word at a non-functor cell is caught" begin
    ld = _ck_heap()
    a = _ck_functors(ld)[1] + 1
    ld.gstack[a] = LK.consPtr(a, LK.TAG_COMPOUND | LK.STG_GLOBAL)   # the argument cell itself, not a functor
    @test _ck_fails(ld, "gstack-compound")
    @test_throws LK.StackInvariantError LK.check_stacks!(ld)
    ld.gstack[a] = LK.consPtr(ld.gTop + 9, LK.TAG_COMPOUND | LK.STG_GLOBAL)
    @test _ck_fails(ld, "gstack-compound")
end

@testset "a reference cycle is caught, a self-reference is an unbound variable" begin
    ld = _ck_heap()
    a = _ck_functors(ld)[1] + 1
    b = a + 1
    ld.gstack[a] = LK.makeRefG(b)
    ld.gstack[b] = LK.makeRefG(a)
    @test _ck_fails(ld, "gstack-ref-cycle")
    @test_throws LK.StackInvariantError LK.check_stacks!(ld)
    ld.gstack[a] = LK.makeRefG(a)                               # a one-cell chain: not a cycle
    ld.gstack[b] = UInt64(0)
    @test isempty(LK.stack_violations(ld))
    # a longer chain that ends: a -> b -> c, c unbound
    c = b + 1
    ld.gstack[a] = LK.makeRefG(b)
    ld.gstack[b] = LK.makeRefG(c)
    ld.gstack[c] = UInt64(0)
    @test isempty(LK.stack_violations(ld))
end

@testset "a MARK or FIRST bit outside a collection is caught" begin
    ld = _ck_heap()
    a = _ck_functors(ld)[1] + 1
    ld.gstack[a] |= LK.MARK_MASK
    @test _ck_fails(ld, "gstack-mark")
    @test isempty(LK.stack_violations(ld; allow_marks=true))    # a collection's own marks are accepted
    @test_throws LK.StackInvariantError LK.check_stacks!(ld)
    @test LK.check_stacks!(ld; allow_marks=true) >= ld.gTop
    ld.gstack[a] &= ~LK.MARK_MASK
    ld.gstack[a] |= LK.FIRST_MASK
    @test _ck_fails(ld, "gstack-mark")
    ld.gstack[a] &= ~LK.FIRST_MASK
    @test isempty(LK.stack_violations(ld))
end

@testset "a trail entry beyond gTop is caught" begin
    ld = _ck_heap()
    empty!(ld.trail)                                             # a known trail
    push!(ld.trail, LK._trail_addr(ld.gTop + 3, LK.TRAIL_GLOBAL))
    @test _ck_fails(ld, "trail")
    @test_throws LK.StackInvariantError LK.check_stacks!(ld)
    pop!(ld.trail)
    push!(ld.trail, LK._trail_addr(2, LK.TRAIL_GLOBAL))          # an entry within the stack is sound
    @test isempty(LK.stack_violations(ld))
    push!(ld.trail, LK.tagTrailPtr(ld.gTop + 1))                 # its saved value beyond gTop
    @test _ck_fails(ld, "trail")
    pop!(ld.trail)
    pop!(ld.trail)
    push!(ld.trail, LK.tagTrailPtr(3))                           # a value entry with no address entry below it
    @test _ck_fails(ld, "trail")
end

@testset "a value-table box out of order is caught" begin
    ld = _ck_heap()
    @test length(ld.vbox) >= 2
    ld.vbox[1], ld.vbox[2] = ld.vbox[2], ld.vbox[1]
    @test _ck_fails(ld, "vbox")
    @test_throws LK.StackInvariantError LK.check_stacks!(ld)
    ld.vbox[1], ld.vbox[2] = ld.vbox[2], ld.vbox[1]
    @test isempty(LK.stack_violations(ld))
    ld.vbox[end] = ld.gTop + 1                                   # a box beyond gTop
    @test _ck_fails(ld, "vbox")
end

@testset "a functor whose arguments run past gTop is caught" begin
    ld = _ck_heap()
    top = ld.gTop
    fp = _ck_functors(ld)[end]
    @test LK.arityFunctor(ld.functors, ld.gstack[fp]) >= 1
    ld.gTop = fp                                                 # the newest compound's arguments cut off
    @test _ck_fails(ld, "gstack-functor-arity")
    @test_throws LK.StackInvariantError LK.check_stacks!(ld)
    ld.gTop = top
    @test isempty(LK.stack_violations(ld))
end

@testset "a stray tag and a functor word in an argument cell are caught" begin
    ld = _ck_heap()
    a = _ck_functors(ld)[1] + 1
    ld.gstack[a] = UInt64(LK.TAG_COMPOUND)                       # compound tag, static storage: no cell holds it
    @test _ck_fails(ld, "gstack-tag")
    ld.gstack[a] = ld.gstack[_ck_functors(ld)[end]]              # a functor word where an argument belongs
    @test !isempty(LK.stack_violations(ld))
    @test_throws LK.StackInvariantError LK.check_stacks!(ld)
end

@testset "a broken attributed-variable chain is caught" begin
    ld = _ck_heap()
    ld.attvar_attvars = ld.gTop + 4
    @test _ck_fails(ld, "attvar-chain")
    @test_throws LK.StackInvariantError LK.check_stacks!(ld)
    ld.attvar_attvars = _ck_functors(ld)[1]                      # a link cell holding a functor: neither unbound nor a reference
    @test _ck_fails(ld, "attvar-chain")
    ld.attvar_attvars = 0
    @test isempty(LK.stack_violations(ld))
end

@testset "a choice point whose mark lies above the stacks, and a frame out of order, are caught" begin
    db = _rdb(
        Tuple{_R, Union{Nothing, _R}}[
            (_rf("n", _rg(Int64(1))), nothing), (_rf("n", _rg(Int64(2))), nothing),
            (_rf("n", _rg(Int64(3))), nothing),
            (_rf("q", _rv(1)), _rf("n", _rv(1))),
        ]
    )
    ld = db.ld
    seen = Tuple{Bool, Bool, Bool, Bool, Bool}[]
    _rcall(
        db, _rf("q", _rv(90));
        at=(qid, k) -> begin
            k == 1 || return nothing
            sound = isempty(LK.stack_violations(ld))
            ch = ld.choices[ld.BFR]
            old = ch.mark
            ch.mark = LK.mark(length(ld.trail), ld.gTop + 7, old.saved_bar)
            mark_bad = _ck_fails(ld, "choice-mark")
            thrown = try
                LK.check_stacks!(ld)
                false
            catch e
                e isa LK.StackInvariantError
            end
            ch.mark = LK.mark(length(ld.trail) + 3, old.globaltop, old.saved_bar)
            trail_bad = _ck_fails(ld, "choice-mark")
            ch.mark = old
            fr = ld.frames[ld.nframes]
            oldbase = fr.base
            fr.base = 0
            frame_bad = _ck_fails(ld, "frame")
            fr.base = oldbase
            push!(seen, (sound, mark_bad && thrown, trail_bad, frame_bad, isempty(LK.stack_violations(ld))))
        end
    )
    @test length(seen) == 1
    @test seen[1] == (true, true, true, true, true)
end
