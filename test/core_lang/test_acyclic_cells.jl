# ORIGINAL: L1d step 3 — `is_acyclic` on CELLS (pl-prims.c ph_acyclic_mark/ph_acyclic_unmark/is_acyclic
# as `is_acyclic_cells`, src/pl-prims.jl, with ACYCLIC_TEMP_MASK/ACYCLIC_PERM_MASK on the functor cells
# as upstream); upstream exercises it through acyclic_term/1 and the compare. test/core_lang/
# test_acyclic_cells.jl — white-box, on every term type:
#   * acyclic: an atom, a flat compound, a long list (10^4 cells: the chain walk, no recursion), a DAG
#     (one compound shared by many arguments — permanent marks keep it linear);
#   * cyclic: `X = f(X)`, a cycle through the LAST argument (`L = [a|L]`) and through an inner one
#     (`X = f(X, a)`), a mutual cycle (`A = f(B), B = g(A)`);
#   * after every call no functor cell carries either mark (ph_acyclic_unmark_cells cleared them);
#   * the boundary: a keyed variable bound to a cyclic term is decided on terms, COUNTED;
#   * the compare guard: a DAG pair (acyclic, linked) orders as swipl's (test_compare_cells.jl's
#     corpus) — here: the descent's result and the fast result agree on an acyclic pair.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "..", "core_lang", "rules_common.jl"))

"An engine with the values of `vs` put (one variable map); `(ld, t)` (reference `i` is slot `t + i`)."
function _ac_engine(vs::Vector{_R})
    db = _rdb(Tuple{_R, Union{Nothing, _R}}[])
    ld = db.ld
    LK.PL_open_foreign_frame(ld)
    t = LK.PL_new_term_refs(ld, length(vs))
    pvm = LK.PutVarMap()
    for (i, v) in enumerate(vs)
        LK.putSlotValue!(ld, t + i, v, pvm)
    end
    return ld, t
end

_ac_marks(ld) = count(
    p ->
        LK.isFunctor(ld.gstack[p]) &&
        (ld.gstack[p] & (LK.ACYCLIC_TEMP_MASK | LK.ACYCLIC_PERM_MASK)) != 0, 1:(ld.gTop)
)

@testset "acyclic terms on cells, the marks cleared" begin
    s = _rf("s", _rg(Int64(1)))
    ld, t = _ac_engine(
        _R[_rs("a"), _rf("f", _rs("a"), _rs("b")), _rints(1:10_000),
            _rf("d", s, s, s, _rf("e", s, s))]
    )
    for i in 1:4
        @test LK.is_acyclic_cells(ld, -(t + i))
        @test _ac_marks(ld) == 0
    end
    # a SHARED sub-term, reached through a binding as a program shares it: `d(X, X, X, e(X, X))` with X
    # bound to one `s(1)` on the cells (the walk read the later arguments through the moved `tail`
    # once — upstream's `iter` — and dereferenced a functor cell as an argument; 2026-10-17)
    X = _rv(1)
    ld, t = _ac_engine(_R[_rf("d", X, X, X, _rf("e", X, X)), _rf("s", _rg(Int64(1)))])
    _, w, _ = LK._deref_loc(ld, -(t + 1))
    @test LK.do_unify_cells(ld, LK.valPtr(w) + 1, -(t + 2)) == LK.BOOLEX_TRUE
    @test LK.is_acyclic_cells(ld, -(t + 1))
    @test _ac_marks(ld) == 0
end

@testset "cyclic terms on cells, the marks cleared" begin
    X, L, A, B = _rv(1), _rv(2), _rv(3), _rv(4)
    ld, t = _ac_engine(
        _R[X, _rf("f", X), L, _rcons(_rs("a"), L), _rv(5), _rf("f", _rv(5), _rs("a")),
            A, _rf("f", B), B, _rf("g", A)]
    )
    for (a, b) in ((1, 2), (3, 4), (5, 6), (7, 8), (9, 10))
        @test LK.do_unify_cells(ld, -(t + a), -(t + b)) == LK.BOOLEX_TRUE
    end
    for i in (1, 3, 5, 7, 9)
        @test !LK.is_acyclic_cells(ld, -(t + i))
        @test _ac_marks(ld) == 0
    end
end

@testset "the boundary: a keyed variable bound to a cyclic term, decided on terms, counted" begin
    ld, t = _ac_engine(_R[_rs("x")])
    kv = lk_var(_R, UInt64(4715))
    LK.setSlotValue!(ld, t + 1, kv)
    LK.Trail!(ld, var_key(kv), _rf("f", kv))                     # kv = f(kv): a cycle in the store
    p0 = ld.cold_pairs
    @test !LK.is_acyclic_cells(ld, -(t + 1))
    @test ld.cold_pairs > p0 && _ac_marks(ld) == 0
end

@testset "after a linked compare and its acyclic test, every functor cell is intact" begin
    # the order upstream keeps: do_compare exits its cycle links BEFORE compare_std calls is_acyclic —
    # a cell still linked would hold a reference, and marking it would corrupt the term
    s, u = _rf("g", _rg(Int64(1))), _rf("g", _rg(Int64(1)))
    ld, t = _ac_engine(_R[_rf("f", s, s, _rs("a")), _rf("f", u, u, _rs("b"))])
    before = Dict(p => ld.gstack[p] for p in 1:(ld.gTop) if LK.isFunctor(ld.gstack[p]))
    @test LK.compareStandard_cells(ld, -(t + 1), -(t + 2), false) == LK.CMP_LESS   # linked, then acyclic tests
    after = Dict(p => ld.gstack[p] for p in keys(before))
    @test after == before                                    # no link left, no mark left
    @test isempty(ld.cycle_cells) && _ac_marks(ld) == 0
end

@testset "the compare guard: an acyclic linked pair orders the same with and without the descent" begin
    # `f(X, X, a)` with X bound to ONE `g(1)` on the cells: the second argument pair meets the link the
    # first made (two `g(1)` terms import as two copies — nothing is reached twice, nothing links)
    X, Y = _rv(1), _rv(2)
    ld, t = _ac_engine(
        _R[_rf("f", X, X, _rs("a")), _rf("f", Y, Y, _rs("b")), _rf("g", _rg(Int64(1))),
            _rf("g", _rg(Int64(1)))]
    )
    for (i, j) in ((1, 3), (2, 4))                             # X = g(1), Y = g(1): the first argument cell
        _, w, _ = LK._deref_loc(ld, -(t + i))
        @test LK.do_unify_cells(ld, LK.valPtr(w) + 1, -(t + j)) == LK.BOOLEX_TRUE
    end
    rc_fast, linked = LK.compare_fast_cells(ld, -(t + 1), -(t + 2), LK.CMP_MODE_ORDER)
    @test linked && rc_fast == LK.CMP_LESS
    @test LK.compare_std_cells(ld, -(t + 1), -(t + 2), LK.CMP_MODE_ORDER) == LK.CMP_LESS
    @test first(LK.compare_descend_cells(ld, -(t + 1), -(t + 2), LK.CMP_MODE_ORDER)) ==
        LK.CMP_LESS
end
