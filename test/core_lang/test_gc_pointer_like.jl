# ORIGINAL: tests of `is_pointer_like` (pl-gc.c:5871-5881 at swipl-devel 18168e62, `#ifdef O_CLAUSEGC`) and of its one caller `markPredicatesInEnvironments` (pl-gc.c:5915).
# allow-new-artifact: G1-P, the test of src/pl-gc.jl `is_pointer_like`, after test/core_lang/test_gc_frames.jl
# test/core_lang/test_gc_pointer_like.jl:
#   * the `Int` method is the C expression `ptr && ((intptr_t)ptr&mask) == 0` on an address (mask 0x7 on a 64-bit word, 0x3 on a 32-bit one). swipl cannot be
#     asked: it is a `static inline` of the C file with no predicate in front of it, so every expected value below is HAND-WRITTEN from that expression;
#   * the `Union{Nothing, Definition}` method: `nothing` (the NULL `fr->predicate`) is false, a `Definition` is true: a Julia reference has no alignment;
#   * the caller, on the frames of an open query (white box): a frame whose predicate has a dirty entry records its generation, a frame whose predicate is
#     NULL (`nothing`) records nothing and does not throw (the NULL arm of `is_pointer_like(def) && lookupHTablePP(...)`), a frame whose predicate has no dirty
#     entry adds nothing.
# Every comparison reads both sides through ONE extractor, both non-empty; every must-fail arm is a changed premise.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "..", "core_lang", "rules_common.jl"))

# ---- the Int method: the C expression, by hand ----
# (value, expected) for a 64-bit word: mask 0x7, so the low three bits must be clear and the value non-zero.
const _PL_INT_ROWS_64 = Tuple{Int, Bool}[
    (0, false),                      # `ptr &&`: NULL
    (8, true), (16, true), (24, true), (4096, true), (1 << 40, true),
    (-8, true), (-16, true),         # two's complement: the low three bits are clear
    (typemax(Int) - 7, true),        # 0x7ffffffffffffff8
    (1, false), (2, false), (3, false), (4, false), (5, false), (6, false), (7, false),
    (9, false), (12, false),         # 12 = 0b1100: aligned to 4 but not to 8 (the 32-bit mask would say true)
    (15, false), (17, false), (-1, false), (-7, false), (typemax(Int), false),
    (typemin(Int), true)            # 0x8000000000000000: non-zero, the low bits clear
]

@testset "is_pointer_like(::Int): the C expression `ptr && (ptr & mask) == 0`" begin
    if Sys.WORD_SIZE == 64
        got = [LK.is_pointer_like(v) for (v, _) in _PL_INT_ROWS_64]
        want = [e for (_, e) in _PL_INT_ROWS_64]
        @test length(got) == length(want) && !isempty(got)
        @test any(want) && !all(want)                      # both outcomes are in the table
        @test got == want
        for (v, e) in _PL_INT_ROWS_64
            @testset "is_pointer_like($v) == $e" begin
                @test LK.is_pointer_like(v) === e
            end
        end
    else
        # 32-bit word: mask 0x3 (pl-gc.c:5873-5874); the rows above are the 64-bit ones
        @test LK.is_pointer_like(4) === true
        @test LK.is_pointer_like(6) === false
        @test LK.is_pointer_like(0) === false
    end
end

# ---- the NULL / Definition method ----
const _PL_CLAUSES = Tuple{_R, Union{Nothing, _R}}[
    (_rf("n", _rf("p", _rg(Int64(1)), _rg(2.25))), nothing),
    (_rf("n", _rf("p", _rg(Int64(2)), _rg(3.25))), nothing),
    (_rf("n", _rf("p", _rg(Int64(3)), _rg(4.25))), nothing),
    (
        _rf("bd", _rv(1)),
        _rconj(_rf("n", _rv(1)), _rf("=", _rv(1), _rf("p", _rv(2), _rv(3))))
    )
]

@testset "is_pointer_like(::Union{Nothing, Definition}): NULL is false, a Definition is true" begin
    db = _rdb(copy(_PL_CLAUSES))
    ndef = _rproc(db, _rf("n", _rv(1))).definition
    bdef = _rproc(db, _rf("bd", _rv(1))).definition
    xs = Union{Nothing, LK.Definition{_R}}[nothing, ndef, bdef, nothing]
    got = [LK.is_pointer_like(x) for x in xs]
    want = [false, true, true, false]
    @test !isempty(got) && length(got) == length(want)
    @test got == want
    @test LK.is_pointer_like(nothing) === false
    @test LK.is_pointer_like(ndef) === true
end

# ---- the caller on an open query ----
"Run `bd(V)` and call `f(db)` at the first answer (the query open): `(answers, f's result)`."
function _pl_live(f)
    db = _rdb(copy(_PL_CLAUSES))
    res = Ref{Any}(nothing)
    ans = _rcall(
        db, _rf("bd", _rv(90)); at=(qid, k) -> (k == 1 && (res[] = f(db)); nothing)
    )
    return ans, res[]
end

"The live frames whose predicate is `def`, as the walk selects them (`base < lTop`, `isFrame`)."
function _pl_frames_of(ld, def)
    idx = Int[]
    for i in 1:ld.nframes
        fr = ld.frames[i]
        (fr.base < ld.lTop && LK.isFrame(fr) && fr.predicate === def) && push!(idx, i)
    end
    return idx
end

"The checks of `markPredicatesInEnvironments!` on an open query: a vector of `(name, ok)`; everything touched is put back."
function _pl_rows(db)
    gd, ld = db.gd, db.ld
    ndef = _rproc(db, _rf("n", _rv(1))).definition
    bdef = _rproc(db, _rf("bd", _rv(1))).definition
    rows = Tuple{String, Bool}[]
    chk!(name, ok) = push!(rows, (name, ok === true))
    # ONE extractor: the generations a ddi recorded
    recorded(ddi) = Set(ddi.access[1:Int(ddi.count)])
    nfr = _pl_frames_of(ld, ndef)
    chk!("premise: n/1 has a live frame", !isempty(nfr))
    chk!("premise: bd/1 has a live frame", !isempty(_pl_frames_of(ld, bdef)))
    chk!("premise: n/1 starts with no dirty entry", !haskey(gd.procedures_dirty, ndef))
    isempty(nfr) && return rows
    gens = Set(LK.generationFrame(ld.frames[i]) for i in nfr)
    LK.registerDirtyDefinition!(gd, ndef)
    ddi = gd.procedures_dirty[ndef]
    saved = [(i, ld.frames[i].predicate) for i in nfr]
    try
        # (a) a frame with a dirty predicate records its generation
        LK.ddi_reset!(ddi)
        LK.markPredicatesInEnvironments!(ld, gd)
        got = recorded(ddi)
        chk!("dirty predicate: at least one generation recorded", ddi.count >= 1)
        chk!(
            "dirty predicate: every frame's generation is recorded",
            !isempty(gens) && issubset(gens, got)
        )
        chk!(
            "dirty predicate: bd/1 (no dirty entry) is not registered by the walk",
            !haskey(gd.procedures_dirty, bdef)
        )

        # (b) the NULL arm: the same frames with a NULL predicate record nothing and do not throw
        for i in nfr
            ld.frames[i].predicate = nothing
        end
        LK.ddi_reset!(ddi)
        threw = false
        try
            LK.markPredicatesInEnvironments!(ld, gd)
        catch
            threw = true
        end
        chk!("NULL predicate: the walk does not throw", !threw)
        chk!(
            "NULL predicate: nothing is recorded", ddi.count == 0 && isempty(recorded(ddi))
        )
        for (i, p) in saved
            ld.frames[i].predicate = p
        end

        # (c) restored: the generations are recorded again (the arms differ only by the predicate)
        LK.ddi_reset!(ddi)
        LK.markPredicatesInEnvironments!(ld, gd)
        chk!(
            "restored predicate: recorded again",
            ddi.count >= 1 && issubset(gens, recorded(ddi))
        )
    finally
        for (i, p) in saved
            ld.frames[i].predicate = p
        end
        LK.unregisterDirtyDefinition!(gd, ndef)
    end
    return rows
end

@testset "markPredicatesInEnvironments! calls is_pointer_like on every frame's predicate" begin
    base, _ = _pl_live(db -> nothing)
    @test length(base) == 3 && all(a -> !isempty(a[1]), base)
    ans, rows = _pl_live(_pl_rows)
    @test rows !== nothing && length(rows) >= 8
    for (nm, ok) in rows
        @testset "walk: $nm" begin
            @test ok
        end
    end
    @test ans == base                                       # the query was not disturbed
end
