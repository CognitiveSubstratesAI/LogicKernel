# ORIGINAL: L1f f3a (audit D-0044) — assert_term! compiles a clause EXPORTED OFF ITS CELLS (`export_cells`,
# src/pl-comp.jl): one variable map for head, body and `$variable_names`. test/core_lang/test_assert_cells.jl — on every term type:
#   * a differential against swipl: a variable shared by head and body, a DAG asserted (shared after), a
#     cyclic clause and a cyclic body (representation_error(cyclic_term)), a long list, indirect values;
#   * white-box: the export and its reverse make no cold import and put no variable in the value table; a
#     variable met in head and body is ONE variable of the export; the compiler's warnings come back as the clause's OWN cells (`import_cells!`),
#     so `$variable_names` names them (the load differential, test_load_swipl.jl, compares the messages);
#     the export throws on a cycle.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "..", "core_lang", "rules_common.jl"))

const _AC_PROG = """
:- dynamic p/1, q/2, rr/1, ss/2, lp/1.   % (not r/1: the swipl driver's)
nl_(0, []) :- !.
nl_(N, [N|T]) :- N1 is N - 1, nl_(N1, T).
a_share(A-F) :- assertz((q(X, f(X, Y)) :- rr(Y), ss(Y, X))), assertz(rr(b)), assertz(ss(b, a)), q(A, F).
a_dag(R) :- X = f(Y, Y), Z = g(X, X), assertz(p(Z)), p(R0), R0 = g(f(P, Q), f(S, U)),
    ( P == Q, Q == S, S == U -> R = shared ; R = R0 ).
a_cyc(E) :- T = s(T, _), catch(assertz(T), error(E, _), true).
a_cyc_body(E) :- B = (rr(B), true), catch(assertz((lp(_) :- B)), error(E, _), true).
a_long(N) :- nl_(20000, L), assertz(lp(L)), lp(M), length(M, N).
a_str(R) :- X is 2**60, assertz(p(k("str", 1.5, X))), p(k(S, F, B)), R = [S, F, B].
"""
const _AC_GOALS = ("a_share", "a_dag", "a_cyc", "a_cyc_body", "a_long", "a_str")

"A database holding `_AC_PROG`."
function _ac_db()::_RDB
    db = _RDB()
    f = joinpath(mktempdir(), "ac.pl")
    write(f, _AC_PROG)
    st, _, _ = LK.load_file!(db.gd, db.ld, f)
    @assert st === :ok "test_assert_cells: the program did not load: $st"
    return db
end

@testset "assert from the cells, as swipl" begin
    goals = _R[_rf(n, _rv(60)) for n in _AC_GOALS]
    ours = _rlines(_ac_db(), goals)
    @test count(==("end"), ours) == length(goals)
    # swipl 10.1.18's answers, probed 2026-10-19 (also where swipl is absent)
    @test "a_share(-(a,f(a,b))) det" in ours
    @test "a_dag(shared) det" in ours
    @test "a_cyc(representation_error(cyclic_term)) det" in ours
    @test "a_cyc_body(representation_error(cyclic_term)) det" in ours
    @test "a_long(20000) det" in ours
    if _R_SWIPL
        theirs = _rswipl(Tuple{_R, Union{Nothing, _R}}[], goals; extra=_AC_PROG)
        @test ours == theirs
        ours == theirs || @info "assert-from-cells differential" ours theirs
    elseif _R_SWIPL_REQUIRED
        @test false
    end
end

_ac_fw(ld, name, n) = LK.lookupFunctorDef(ld.functors, LK._atom_word!(ld, _rs(name)), n)
_ac_gw(p) = LK.consPtr(p, LK.TAG_COMPOUND | LK.STG_GLOBAL)
"Lay compound `name/length(args)` out, argument `i` the word `args[i]` (0: unbound); its position."
function _ac_lay!(ld, name, args...)
    p = LK._alloc_compound!(ld, _ac_fw(ld, name, length(args)), length(args))
    for (i, w) in enumerate(args)
        ld.gstack[p + i] = w
    end
    return p
end
# The meters f3a's own code must leave alone: no cold import, no variable in the value table (f3-3: the
# export memo, the cold export/variable meters and the binding store went with the keyed variables).
"The meters f3a's code must leave alone."
_ac_meters(ld) = (ld.cold_imports, count(v -> kind(v) === VAR, ld.vtable))

@testset "white-box: the export — one variable map, nothing of the old machinery, warnings on the cells" begin
    db = _RDB()
    gd, ld = db.gd, db.ld
    LK.PL_open_foreign_frame(ld)
    # h(X, f(X, Y)) :- g(Y, X), on the cells
    t = LK.PL_new_term_ref(ld)
    ph = _ac_lay!(ld, "h", 0, 0)
    pf = _ac_lay!(ld, "f", LK.makeRefG(ph + 1), 0)
    ld.gstack[ph + 2] = _ac_gw(pf)
    pb = _ac_lay!(ld, "g", LK.makeRefG(pf + 2), LK.makeRefG(ph + 1))
    pc = _ac_lay!(ld, ":-", _ac_gw(ph), _ac_gw(pb))
    ld.slots[t + 1] = _ac_gw(pc)
    # the export: X one variable in head and body, Y another; a compound met twice exported once — and
    # nothing of the old machinery made, by the export or by the reverse import
    m0 = _ac_meters(ld)
    ex = LK.cell_export{_R}()
    v = LK.export_cells(ld, ex, -(t + 1))
    @test length(ex.vars) == 2 && length(ex.cells) == 2
    hx, hf = child(child(v, 2), 2), child(child(v, 2), 3)
    bx, by = child(child(v, 3), 3), child(child(v, 3), 2)
    @test var_key(hx) == var_key(bx) == var_key(child(hf, 2)) &&
        var_key(by) == var_key(child(hf, 3))
    @test var_key(hx) != var_key(by)
    @test ex.cells[var_key(hx)] == ph + 1 && ex.cells[var_key(by)] == pf + 2
    # the reverse: a value's variables back to their own cells
    w = LK.import_cells!(ld, ex, child(v, 2))
    q = LK.valPtr(w)
    @test ld.gstack[q + 1] == LK.makeRefG(ph + 1)
    @test _ac_meters(ld) == m0
    # and the clause asserts from its cells
    @test LK.assert_term!(gd, ld, t, LK.CL_END) !== nothing
    # a cycle has no value: the export throws (assert_term! tests is_acyclic_cells first)
    pcy = _ac_lay!(ld, "s", 0)
    ld.gstack[pcy + 1] = _ac_gw(pcy)
    tc = LK.PL_new_term_ref(ld)
    ld.slots[tc + 1] = _ac_gw(pcy)
    @test_throws ArgumentError LK.export_cells(ld, LK.cell_export{_R}(), -(tc + 1))
end
