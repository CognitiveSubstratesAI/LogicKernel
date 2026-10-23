# ORIGINAL: L1d step 1 — the standard order on CELLS (pl-prims.c compareStandard and its chain as
# `compareStandard_cells`, src/pl-prims.jl): `==/2`, `\==/2`, `compare/3`, `PL_compare` and the VM's
# `B_EQ_VV`/`B_NEQ_VV`/`B_EQ_VC`/`B_NEQ_VC` compare LOCATIONS; upstream's own compare units run on terms
# in test_unify.jl/test_sort_swipl.jl unchanged. test/core_lang/test_compare_cells.jl — on every term type:
#   * the ladder against swipl through the rules differential: compare/3, ==, \== and @< over a corpus
#     of pairs — variables (one and two), numbers (`1` vs `1.0`, negative zero), strings, atoms, `[]`
#     vs `'[]'`, compounds by arity, by name and by arguments, nested;
#   * rational trees: `X = f(X), Y = f(Y), X == Y` is true; compare/3 on two different cyclic terms
#     answers as swipl; every functor cell holds its functor word after a walk (no link left);
#   * a DAG pair (shared, equal but distinct subterms: `linked` without a cycle) and a #1529-style
#     mutually cyclic pair (`A = f(B, 0), B = f(A, 1)`) ordered as swipl — `compare_descend` on cells;
#   * two fresh variables: their order is NOT pinned (SWI orders by address and defines no order
#     beyond consistency; ours is by key, a DIVERGES) — only consistency: `X == X`, antisymmetry, and
#     compare/3 agreeing with msort/2 on the same variables (in Prolog, so swipl checks it too);
#   * Q2 (kernel-only, pinned): `$expr/n` before a symbol functor of the same arity;
#   * the meter: `==` between two lists on the stack makes no cold import.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "..", "core_lang", "rules_common.jl"))

# cmp_t(A, B, O) :- compare(O, A, B).   eq_t(A, B) :- A == B.   ne_t(A, B) :- A \== B.
# lt_t(A, B) :- A @< B.   all through clause bodies, so the body compiler's B_EQ_VV family runs too
_cc_clauses() = Tuple{_R, Union{Nothing, _R}}[
    (_rf("cmp_t", _rv(1), _rv(2), _rv(3)), _rf("compare", _rv(3), _rv(1), _rv(2))),
    (_rf("eq_t", _rv(1), _rv(2)), _rf("==", _rv(1), _rv(2))),
    (_rf("ne_t", _rv(1), _rv(2)), _rf("\\==", _rv(1), _rv(2))),
    (_rf("lt_t", _rv(1), _rv(2)), _rf("@<", _rv(1), _rv(2))),
    (_rf("eqc_t", _rv(1)), _rf("==", _rv(1), _rs("a"))),                     # B_EQ_VC
    (_rf("nec_t", _rv(1)), _rf("\\==", _rv(1), _rs("a"))),                   # B_NEQ_VC
    (_rf("same_t", _rv(9)), _rconj(_rf("=", _rv(1), _rv(2)), _rf("==", _rv(1), _rv(2)))),
    (
        _rf("cyc_eq", _rv(9)),
        _rconj(_rf("=", _rv(1), _rf("f", _rv(1))), _rf("=", _rv(2), _rf("f", _rv(2))),
            _rf("==", _rv(1), _rv(2)))
    ),
    (
        _rf("cyc_cmp", _rv(9)),
        _rconj(_rf("=", _rv(1), _rf("f", _rv(1), _rs("a"))),
            _rf("=", _rv(2), _rf("f", _rv(2), _rs("b"))),
            _rf("compare", _rv(9), _rv(1), _rv(2)))
    ),
    # a DAG: P and Q equal and distinct, each shared twice — the second (P, Q) pair follows a link
    (
        _rf("dag_cmp", _rv(9)),
        _rconj(_rf("=", _rv(1), _rf("g", _rg(Int64(1)))),
            _rf("=", _rv(2), _rf("g", _rg(Int64(1)))),
            _rf(
                "compare",
                _rv(9),
                _rf("f", _rv(1), _rv(1), _rs("a")),
                _rf("f", _rv(2), _rv(2), _rs("b"))
            ))
    ),
    # #1529-style: A = f(B, 0), B = f(A, 1) — compare(O1, A, B) and compare(O2, B, A)
    (
        _rf("cyc1529", _rv(8), _rv(9)),
        _rconj(_rf("=", _rv(1), _rf("f", _rv(2), _rg(Int64(0)))),
            _rf("=", _rv(2), _rf("f", _rv(1), _rg(Int64(1)))),
            _rf("compare", _rv(8), _rv(1), _rv(2)),
            _rf("compare", _rv(9), _rv(2), _rv(1)))
    ),
    # two fresh variables: consistency only (no order pinned) — X == X; compare(O, X, Y) and
    # compare(O2, Y, X) opposite; msort([X, Y], L) puts first the one compare/3 calls smaller
    (
        _rf("var_consistent", _rv(9)),
        _rconj(_rf("==", _rv(1), _rv(1)),
            _rf("compare", _rv(3), _rv(1), _rv(2)),
            _rf("compare", _rv(4), _rv(2), _rv(1)), _rf("\\==", _rv(3), _rv(4)),
            _rf("\\==", _rv(3), _rs("=")), _rf("msort", _rlist(_rv(1), _rv(2)), _rv(5)),
            _rf(";",
                _rf(
                    "->",
                    _rf("==", _rv(3), _rs("<")),
                    _rf("==", _rv(5), _rlist(_rv(1), _rv(2)))
                ),
                _rf("==", _rv(5), _rlist(_rv(2), _rv(1)))), _rf("=", _rv(9), _rs("ok")))
    ),
    # variables NOT made in LIFO clause order, ordered as swipl orders them (by address; F3B f3b-2,
    # D-0095 item 2) — functor/3 then unified in another order:
    # functor(T, f, 3), T = f(A, B, C), compare(O1, C, A), msort([C, B, A], L), (L == [A, B, C] -> …)
    (
        _rf("vo_functor", _rv(1), _rv(2)),
        _rconj(_rf("functor", _rv(3), _rs("f"), _rg(Int64(3))),
            _rf("=", _rv(3), _rf("f", _rv(4), _rv(5), _rv(6))),
            _rf("compare", _rv(1), _rv(6), _rv(4)),
            _rf("msort", _rlist(_rv(6), _rv(5), _rv(4)), _rv(7)),
            _rite(_rf("==", _rv(7), _rlist(_rv(4), _rv(5), _rv(6))),
                _rf("=", _rv(2), _rs("sorted")), _rf("=", _rv(2), _rs("other"))))
    ),
    # after backtracking reuses the cells: functor(P, p, 1), (functor(Q, q, 3), Q \== a, fail ; true),
    # functor(R, r, 1), P = p(X), R = r(Y), compare(O, Y, X)
    (
        _rf("vo_bt", _rv(1)),
        _rconj(_rf("functor", _rv(2), _rs("p"), _rg(Int64(1))),
            _ror(
                _rconj(_rf("functor", _rv(3), _rs("q"), _rg(Int64(3))),
                    _rf("\\==", _rv(3), _rs("a")), _rs("fail")),
                _rs("true")
            ),
            _rf("functor", _rv(4), _rs("r"), _rg(Int64(1))),
            _rf("=", _rv(2), _rf("p", _rv(5))), _rf("=", _rv(4), _rf("r", _rv(6))),
            _rf("compare", _rv(1), _rv(6), _rv(5)))
    ),
    # (functor(Q, q, 3), Q = q(Z, Z, Z), fail ; true), functor(R, r, 2), R = r(Y, W),
    # compare(O, W, Y), var(Z) — the reused cells are the second variable's
    (
        _rf("vo_bt2", _rv(1)),
        _rconj(
            _ror(
                _rconj(_rf("functor", _rv(2), _rs("q"), _rg(Int64(3))),
                    _rf("=", _rv(2), _rf("q", _rv(3), _rv(3), _rv(3))), _rs("fail")),
                _rs("true")
            ),
            _rf("functor", _rv(4), _rs("r"), _rg(Int64(2))),
            _rf("=", _rv(4), _rf("r", _rv(5), _rv(6))),
            _rf("compare", _rv(1), _rv(6), _rv(5)), _rf("var", _rv(3)))
    ),
    # copy_term/2 copies: copy_term(g(B0, A0, B0), g(D, C, D2)), compare(O1, D, C),
    # compare(O2, D, D2), var(A0)
    (
        _rf("vo_copy", _rv(1), _rv(2)),
        _rconj(
            _rf(
                "copy_term",
                _rf("g", _rv(3), _rv(4), _rv(3)),
                _rf("g", _rv(5), _rv(6), _rv(7))
            ),
            _rf("compare", _rv(1), _rv(5), _rv(6)),
            _rf("compare", _rv(2), _rv(5), _rv(7)),
            _rf("var", _rv(4)))
    ),
    # T = f(X, Y), copy_term(h(Y, X, T), h(Y1, X1, T1)), compare(O, Y1, X1), T1 \== a
    (
        _rf("vo_copy2", _rv(1)),
        _rconj(_rf("=", _rv(2), _rf("f", _rv(3), _rv(4))),
            _rf(
                "copy_term",
                _rf("h", _rv(4), _rv(3), _rv(2)),
                _rf("h", _rv(5), _rv(6), _rv(7))
            ),
            _rf("compare", _rv(1), _rv(5), _rv(6)), _rf("\\==", _rv(7), _rs("a")))
    ),
    # a nested compound built in the body (the outer first): T = f(g(A), B), compare(O, A, B), T \== a
    (
        _rf("vo_nest", _rv(1)),
        _rconj(_rf("=", _rv(2), _rf("f", _rf("g", _rv(3)), _rv(4))),
            _rf("compare", _rv(1), _rv(3), _rv(4)), _rf("\\==", _rv(2), _rs("a")))
    ),
    # T =.. [f, A, B], functor(T, F, _N), F == f, compare(O, B, A)
    (
        _rf("vo_univ", _rv(1)),
        _rconj(_rf("=..", _rv(2), _rlist(_rs("f"), _rv(3), _rv(4))),
            _rf("functor", _rv(2), _rv(5), _rv(6)), _rf("==", _rv(5), _rs("f")),
            _rf("compare", _rv(1), _rv(4), _rv(3)))
    )
]

const _CC_PAIRS = [
    (_rs("a"), _rs("b")), (_rs("b"), _rs("a")), (_rs("a"), _rs("a")),
    (_rg(Int64(1)), _rg(1.0)), (_rg(1.0), _rg(Int64(1))), (_rg(Int64(1)), _rg(Int64(2))),
    (_rg(-0.0), _rg(0.0)), (_rg("s"), _rg("t")), (_rg("s"), _rs("s")),
    (_rg(Int64(3)), _rs("a")),
    (_rnil(), _rs("[]")), (_rnil(), _rs("")), (_rs("a"), _rf("f", _rs("a"))),
    (_rf("f", _rs("a")), _rf("g", _rs("a"))),
    (_rf("f", _rs("a"), _rs("b")), _rf("g", _rs("a"))),
    (_rf("f", _rs("a"), _rs("b")), _rf("f", _rs("a"), _rs("c"))),
    (_rf("f", _rf("g", _rg(Int64(1)))), _rf("f", _rf("g", _rg(Int64(1))))),
    (_rlist(_rs("a"), _rs("b")), _rlist(_rs("a"), _rs("c"))), (_rlist(_rs("a")), _rnil()),
    (_rv(1), _rs("a")), (_rf("f", _rv(1)), _rf("f", _rs("a")))
]

@testset "the ladder on cells, as swipl: compare/3, ==, \\==, @< and the constant forms" begin
    db = _rdb(_cc_clauses())
    goals = _R[]
    for (a, b) in _CC_PAIRS
        push!(
            goals,
            _rf("cmp_t", a, b, _rv(50)),
            _rf("eq_t", a, b),
            _rf("ne_t", a, b),
            _rf("lt_t", a, b)
        )
    end
    append!(
        goals,
        _R[_rf("eqc_t", _rs("a")), _rf("eqc_t", _rs("b")), _rf("eqc_t", _rv(1)),
            _rf("eqc_t", _rf("a", _rs("x"))), _rf("nec_t", _rs("a")),
            _rf("nec_t", _rg(Int64(1))),
            _rf("same_t", _rv(50)), _rf("cyc_eq", _rv(50)), _rf("cyc_cmp", _rv(50)),
            _rf("dag_cmp", _rv(50)), _rf("cyc1529", _rv(50), _rv(51)),
            _rf("var_consistent", _rv(50)), _rf("vo_functor", _rv(50), _rv(51)),
            _rf("vo_bt", _rv(50)), _rf("vo_bt2", _rv(50)), _rf("vo_copy", _rv(50), _rv(51)),
            _rf("vo_copy2", _rv(50)), _rf("vo_nest", _rv(50)), _rf("vo_univ", _rv(50))]
    )
    ours = _rlines(db, goals)
    # the kernel's side alone (also where swipl is absent: Pkg.test): every goal ends, none raised
    @test count(==("end"), ours) == length(goals)
    @test !any(l -> startswith(l, "exception("), ours)
    @test count(l -> startswith(l, "vo_"), ours) == 7       # every variable-order row answers
    if _R_SWIPL
        theirs = _rswipl(_cc_clauses(), goals)
        @test ours == theirs
        if ours != theirs
            k = findfirst(i -> i > length(theirs) || ours[i] != theirs[i], eachindex(ours))
            @info "first difference" k ours[something(k, 1)] get(
                theirs, something(k, 1), "—"
            )
        end
    elseif _R_SWIPL_REQUIRED
        @test false
    end
end

"An engine with the values of `vs` put into term references; `(ld, t)` (reference `i` is slot `t + i`)."
function _cc_engine(vs::Vector{_R}; pvm=LK.PutVarMap())
    db = _rdb(Tuple{_R, Union{Nothing, _R}}[])
    ld = db.ld
    LK.PL_open_foreign_frame(ld)
    t = LK.PL_new_term_refs(ld, length(vs))
    for (i, v) in enumerate(vs)
        LK.putSlotValue!(ld, t + i, v, pvm)
    end
    return ld, t
end

_cc_functor_cells(ld) =
    Dict(p => ld.gstack[p] for p in 1:(ld.gTop) if LK.isFunctor(ld.gstack[p]))

@testset "rational trees: equal, ordered, every functor cell restored" begin
    X, Y = _rv(1), _rv(2)
    pvm = LK.PutVarMap()
    ld, t = _cc_engine(_R[X, _rf("f", X), Y, _rf("f", Y)]; pvm=pvm)
    @test LK.do_unify_cells(ld, -(t + 1), -(t + 2)) == LK.BOOLEX_TRUE      # X = f(X)
    @test LK.do_unify_cells(ld, -(t + 3), -(t + 4)) == LK.BOOLEX_TRUE      # Y = f(Y)
    before = _cc_functor_cells(ld)
    @test LK.compareStandard_cells(ld, -(t + 1), -(t + 3), true) == LK.CMP_EQUAL
    @test LK.compareStandard_cells(ld, -(t + 1), -(t + 3), false) == LK.CMP_EQUAL
    @test _cc_functor_cells(ld) == before && isempty(ld.cycle_cells)
end

@testset "Q2: \$expr/n before a symbol functor of the same arity (kernel-only)" begin
    # KNOWN DIFFERENCE, pinned (user, 2026-10-04): swipl has no `(X a)`; the term compare's order
    ld, t = _cc_engine(_R[mk_expr(_R, _R[_rv(1), _rs("a")]), _rf("f", _rs("a"), _rs("b"))])
    e = mk_expr(_R, _R[_rv(1), _rs("a")])
    # `(X a)` is `$expr/2`, `f(a, b)` is `f/2`: one arity, so `$expr` first
    @test LK.compareStandard_cells(ld, -(t + 1), -(t + 2), false) == LK.CMP_LESS
    @test LK.compareStandard_cells(ld, -(t + 2), -(t + 1), false) == LK.CMP_GREATER
    @test LK.compareStandard(e, _rf("f", _rs("a"), _rs("b"))) == LK.CMP_LESS      # the term order agrees
end

@testset "the meter: == between two lists on the stack makes no cold import" begin
    l = _rlist((_rg(Int64(i)) for i in 1:20)...)
    ld, t = _cc_engine(_R[l, l])
    c0 = ld.cold_imports                       # (f3-3: the export/variable/pair meters went with the boundary)
    @test LK.compareStandard_cells(ld, -(t + 1), -(t + 2), true) == LK.CMP_EQUAL
    @test LK.compareStandard_cells(ld, -(t + 1), -(t + 2), false) == LK.CMP_EQUAL
    @test ld.cold_imports == c0
end
