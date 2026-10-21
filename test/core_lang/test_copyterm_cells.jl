# ORIGINAL: L1d step 6 — copy_term/duplicate_term on CELLS (pl-copyterm.c do_copy_term, mark_for_copy,
# mark_for_duplicate, copy_term, exitCyclicCopy, cp_unmark as their `_cells` ports, src/pl-copyterm.jl; the
# workspace's L1_plan/stageL1d_design.md §3f). Upstream marks a VARIABLE cell and a FUNCTOR cell (MARK|FIRST)
# and forwards the originals it copies (`makeRefG(copy)`, restored by exitCyclicCopy); ours keeps the functor
# marks and the forwarding words in place and a variable cell's marks in a side vector (`ld.cp_vmarks`) — a
# representation-only DIVERGES. test/core_lang/test_copyterm_cells.jl — on every term type:
#   * a differential against swipl through clause bodies: copy_term/2 and duplicate_term/2 on atoms,
#     compounds, a variable met twice (one copy, met twice), variables shared between arguments, a DAG built
#     through a binding, cyclic terms (`X = f(X)` and through an inner argument), a long list, the copy
#     independent of the original (binding one leaves the other);
#   * white-box: under copy_term a GROUND argument is SHARED (the copy's argument word is the original's),
#     under duplicate_term it is not; after every copy no functor cell carries MARK/FIRST, the side vector
#     is all zero, every forwarded cell holds its own word again, `ld.cp_lstack` is empty;
#   * the boundary: a keyed variable's binding is copied on terms, COUNTED;
#   * the meter: a copy of a term on the stack makes no cold export, import or variable read.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "..", "core_lang", "rules_common.jl"))

_ki(i) = _rg(Int64(i))

_kc_clauses() = Tuple{_R, Union{Nothing, _R}}[
    (_rf("ct", _rv(1), _rv(2)), _rf("copy_term", _rv(1), _rv(2))),
    (_rf("dt", _rv(1), _rv(2)), _rf("duplicate_term", _rv(1), _rv(2))),
    # the copy is independent: bind the copy's variables, the original's stay unbound
    (
        _rf("indep", _rv(1), _rv(2)),
        _rconj(
            _rf("copy_term", _rv(1), _rv(2)),
            _rf("=", _rv(2), _rf("f", _rs("a"), _rs("b")))
        )
    ),
    # a DAG built by the program: S = s(X, 1) shared three times, then copied
    (
        _rf("dag", _rv(9)),
        _rconj(_rf("=", _rv(1), _rf("s", _rv(2), _ki(1))),
            _rf("copy_term", _rf("d", _rv(1), _rv(1), _rf("e", _rv(2), _rv(1))), _rv(9)))
    ),
    # cyclic: X = f(X), copied, the copy unifies with a fresh f(Y) cycle; through an inner argument
    (
        _rf("cyc1", _rv(9)),
        _rconj(_rf("=", _rv(1), _rf("f", _rv(1))), _rf("copy_term", _rv(1), _rv(2)),
            _rf("=", _rv(3), _rf("f", _rv(3))), _rf("==", _rv(2), _rv(3)),
            _rf("=", _rv(9), _rs("ok")))
    ),
    (
        _rf("cyc2", _rv(9)),
        _rconj(_rf("=", _rv(1), _rf("g", _rs("a"), _rv(1), _rv(4))),
            _rf("copy_term", _rv(1), _rv(2)),
            _rf("=", _rv(2), _rf("g", _rs("a"), _rv(5), _rv(6))),
            _rf("==", _rv(5), _rv(2)),
            _rf("\\==", _rv(6), _rv(4)), _rf("=", _rv(9), _rs("ok")))
    ),
    (
        _rf("dcyc", _rv(9)),
        _rconj(_rf("=", _rv(1), _rf("f", _rv(1), _rv(4))),
            _rf("duplicate_term", _rv(1), _rv(2)),
            _rf("=", _rv(2), _rf("f", _rv(5), _rv(6))), _rf("==", _rv(5), _rv(2)),
            _rf("\\==", _rv(6), _rv(4)), _rf("=", _rv(9), _rs("ok")))
    ),
    (
        _rf("long", _rv(1), _rv(9)),
        _rconj(_rf("length", _rv(2), _rv(1)), _rf("copy_term", _rv(2), _rv(9)))
    )
]

@testset "copy_term/duplicate_term on cells, as swipl" begin
    db = _rdb(_kc_clauses())
    A, B, C = _rv(50), _rv(51), _rv(52)
    goals = _R[
        _rf("ct", _rs("a"), C), _rf("ct", _rf("f", _rs("a"), _ki(1)), C),
        _rf("ct", _rf("f", A, A, B), C),
        _rf("ct", _rf("f", A, _rf("g", B, A), _rlist(B, A)), C),
        _rf("dt", _rf("f", A, A, _rf("g", _rs("x"))), C), _rf("dt", _rs("a"), C),
        _rf("indep", _rf("f", A, B), C), _rf("dag", C), _rf("cyc1", C), _rf("cyc2", C),
        _rf("dcyc", C),
        _rf("long", _ki(2000), C)
    ]
    ours = _rlines(db, goals)
    # the kernel's side alone (also where swipl is absent: Pkg.test)
    @test count(==("end"), ours) == length(goals)
    @test !any(l -> startswith(l, "exception("), ours)
    @test "ct(f(A,A,_),f(B,B,_)) det" in ours
    @test "indep(f(_,_),f(a,b)) det" in ours
    @test "cyc1(ok) det" in ours && "cyc2(ok) det" in ours && "dcyc(ok) det" in ours
    if _R_SWIPL
        theirs = _rswipl(_kc_clauses(), goals)
        @test ours == theirs
        if ours != theirs
            for i in eachindex(ours)
                if i > length(theirs) || ours[i] != theirs[i]
                    @info "first difference" i ours[i] get(theirs, i, "—")
                    break
                end
            end
        end
    elseif _R_SWIPL_REQUIRED
        @test false
    end
end

"An engine with the values of `vs` put into term references; `(ld, t)` (reference `t + i - 1` is slot `t + i`)."
function _kc_engine(vs::Vector{_R}; pvm=LK.PutVarMap())
    db = _rdb(Tuple{_R, Union{Nothing, _R}}[])
    ld = db.ld
    LK.PL_open_foreign_frame(ld)
    t = LK.PL_new_term_refs(ld, length(vs))
    for (i, v) in enumerate(vs)
        LK.putSlotValue!(ld, t + i, v, pvm)
    end
    return ld, t
end
_kc_counts(ld) = (ld.cold_exports, ld.cold_imports, ld.cold_vars, ld.cold_pairs)
"No functor cell marked, the side vector all zero, no forwarded cell left, the cycle stack empty."
_kc_clean(ld) =
    !any(
        p ->
            LK.isFunctor(ld.gstack[p]) &&
            (ld.gstack[p] & (LK.MARK_MASK | LK.FIRST_MASK)) != 0,
        1:(ld.gTop)
    ) && all(iszero, ld.cp_vmarks) && isempty(ld.cp_lstack)
"The word in argument cell `i` of the compound slot `t + 1` dereferences to (`_deref_loc` of the slot)."
function _kc_arg_word(ld, t, i)
    _, w, _ = LK._deref_loc(ld, -(t + 1))
    return LK._deref_loc(ld, LK.valPtr(w) + i)[2]
end

"`copy_term_refs` into a new term reference (L1f f1b: the caller's `to`, as upstream's); the reference."
function _kc_copy(ld, t, options)
    c = LK.PL_new_term_ref(ld)
    @assert LK.copy_term_refs(ld, t, c, options)
    return c
end

@testset "white-box: ground arguments shared by copy_term, copied by duplicate_term; nothing left marked" begin
    X = _rv(1)
    g = _rf("g", _rs("a"), _ki(2))
    ld, t = _kc_engine(_R[_rf("f", g, X, _rf("h", X))])
    gw = _kc_arg_word(ld, t, 1)
    for share in (true, false)
        c = _kc_copy(ld, t, LK.cp_options(share))
        @test _kc_clean(ld)
        cw = _kc_arg_word(ld, c, 1)
        @test (cw == gw) == share                           # COPY_SHARE: the very compound
        # the copy's X (argument 2) and the X inside h(X) are one fresh cell, not the original's
        k2, _, p2 = LK._deref_loc(ld, LK.valPtr(LK._deref_loc(ld, -(c + 1))[2]) + 2)
        _, hw, _ = LK._deref_loc(ld, LK.valPtr(LK._deref_loc(ld, -(c + 1))[2]) + 3)
        k3, _, p3 = LK._deref_loc(ld, LK.valPtr(hw) + 1)
        _, _, px = LK._deref_loc(ld, LK.valPtr(LK._deref_loc(ld, -(t + 1))[2]) + 2)
        @test k2 == LK.DU_CELL && k3 == LK.DU_CELL && p2 == p3 && p2 != px
    end
end

@testset "the boundary: a keyed variable's binding, copied on terms, counted" begin
    ld, t = _kc_engine(_R[_rs("x")])
    kv = lk_var(_R, UInt64(4741))
    # f(kv, a), kv a value-table word holding the keyed variable — laid by hand since L1f f3b-1 (a writer
    # binds a keyed variable to a fresh cell now), as `_word_of!` laid it before
    LK.setSlotValue!(ld, t + 1, _rf("f", _rs("x"), _rs("a")))
    ld.gstack[LK.valPtr(ld.slots[t + 1]) + 1] = lk_boundary_word!(ld, kv)
    LK.Trail!(ld, var_key(kv), _rf("g", _rv(7)))
    p0 = ld.cold_pairs
    c = _kc_copy(ld, t, LK.cp_options(true))
    @test ld.cold_pairs > p0
    @test _kc_clean(ld)
    r = LK.resolve_term(ld, LK.slotValue(ld, c + 1))
    @test kind(r) === EXPR && nchildren(r) == 3
end

@testset "the meter: a copy of a term on the stack makes no cold export, import or variable read" begin
    X, Y = _rv(1), _rv(2)
    ld, t = _kc_engine(
        _R[_rf("f", X, _rlist((_ki(i) for i in 1:50)...), _rf("g", Y, X), _rs("a"))]
    )
    c0 = _kc_counts(ld)
    _kc_copy(ld, t, LK.cp_options(true))
    _kc_copy(ld, t, LK.cp_options(false))
    @test _kc_counts(ld) == c0
end
