# ORIGINAL: L1c sub-commit 6 — a variable is its KEY, never its Julia object (src/term_interface.jl: "A
# variable term. Its identity is `var_key`"); since L1f f3 a variable is its CELL (upstream: a cell IS its
# variable) and a term's variable is its key only in an export. test/core_lang/test_var_identity.jl — on
# every term type:
#   * one unbound cell met twice in one term (one write: a write-local map, f3's Q3) behaves as ONE
#     variable in every operation that recognises a variable met twice: the unifier (binding one binds
#     the other), the standard order (`PL_compare`), copy_term (one fresh variable in the copy), the
#     occurs check, numbervars (one `'$VAR'(N)`), the writer's variable name, the export (one key), and
#     the variable collectors of term_variables/2 and bagof/setof (`free_variables_loop_cells`): each
#     sees ONE. Two separate writes of one variable term are two variables (SWI's separate puts).
#   * until L1f f3 the same was pinned for two reads of one cell through the counted adapter
#     (`_cell_var`, a variable term per read) on the term-level functions; those went with the keyed
#     variables.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "..", "core_lang", "rules_common.jl"))

"An engine with `f(X, X)` written once: its reference, its two arguments' references and X's cell."
function _vi_shared()
    db = _rdb(Tuple{_R, Union{Nothing, _R}}[])
    ld = db.ld
    LK.PL_open_foreign_frame(ld)
    tf = LK.PL_new_term_ref(ld)
    LK.setSlotValue!(ld, tf + 1, _rf("f", _rv(1), _rv(1)))      # one write: one cell for both
    a1, a2 = LK.PL_new_term_ref(ld), LK.PL_new_term_ref(ld)
    LK._PL_get_arg(ld, 1, tf, a1) && LK._PL_get_arg(ld, 2, tf, a2) || error("f(X, X)")
    k, _, p = LK._deref_loc(ld, -(a1 + 1))
    k == LK.DU_CELL || error("X is no unbound cell")
    return ld, tf, a1, a2, p
end

"A new term reference holding `v` (its own write)."
function _vi_put(ld, v)
    t = LK.PL_new_term_ref(ld)
    LK.setSlotValue!(ld, t + 1, v)
    return t
end

@testset "one cell met twice is one variable" begin
    ld, tf, a1, a2, p = _vi_shared()
    @test LK._deref_loc(ld, -(a2 + 1)) == (LK.DU_CELL, LK.word(0), p)
    # the standard order
    @test LK.PL_compare(ld, a1, a2) == LK.CMP_EQUAL
    # the export: one key for both
    r = lk_answer(ld, tf)
    @test kind(child(r, 2)) === VAR && var_key(child(r, 2)) == var_key(child(r, 3))
    # the unifier: binding through one argument binds the other
    t2 = _vi_put(ld, _rf("f", _rs("a"), _rv(1)))
    m = LK.Mark(ld)
    @test LK.PL_unify(ld, tf, t2)
    @test lk_eq(LK.PL_get_atom(ld, a2), _rs("a"))
    LK.Undo!(ld, m)
    @test LK.PL_is_variable(ld, a1)
    # f(X, X) = f(b, c) fails: one variable cannot be both
    t3 = _vi_put(ld, _rf("f", _rs("b"), _rs("c")))
    m = LK.Mark(ld)
    @test !LK.PL_unify(ld, tf, t3)
    LK.Undo!(ld, m)
    # copy_term: ONE fresh variable, twice
    c, c1, c2 = LK.PL_new_term_ref(ld), LK.PL_new_term_ref(ld), LK.PL_new_term_ref(ld)
    @test LK.copy_term_refs(ld, tf, c, LK.cp_options(LK.COPY_ATTRS))
    @test LK._PL_get_arg(ld, 1, c, c1) && LK._PL_get_arg(ld, 2, c, c2)
    @test LK.PL_is_variable(ld, c1) && LK.PL_compare(ld, c1, c2) == LK.CMP_EQUAL
    @test LK.PL_compare(ld, c1, a1) != LK.CMP_EQUAL
    # the occurs check: X occurs in g(X), both in one write
    th = _vi_put(ld, _rf("h", _rv(1), _rf("g", _rv(1))))
    x, g = LK.PL_new_term_ref(ld), LK.PL_new_term_ref(ld)
    @test LK._PL_get_arg(ld, 1, th, x) && LK._PL_get_arg(ld, 2, th, g)
    @test LK.var_occurs_in_cells(ld, LK._deref_loc(ld, -(x + 1))[3], -(g + 1))
    # the writer's name: one name for both; the name is the cell's offset from the stack base,
    # doubled (pl-write.c var_name_ptr, F3B f3b-2; its key before). swipl 8e1bc111, `functor(T,f,2),
    # arg(1,T,A), arg(2,T,B), format('~w ~w',[A,B])` prints `_420 _428`: the same shape, even for a
    # global cell; its offsets are not this engine's.
    @test LK.varName(ld, a1) == LK.varName(ld, a2) == "_" * string((p - 1) * 2)
    # two SEPARATE writes of one variable term are two variables (each a fresh cell: separate puts,
    # SWI's semantics, f3-2 audit D-0111 Q3/Q5), so their names differ
    t1, t2 = _vi_put(ld, _rv(1)), _vi_put(ld, _rv(1))
    @test LK.varName(ld, t1) != LK.varName(ld, t2)
end

@testset "numbervars and the variable collectors see one variable" begin
    ld, tf, a1, _, _ = _vi_shared()
    # term_variables/2's collector: one variable, X's cell
    n, v0 = LK.term_variables_to_termv_cells(ld, tf, typemax(Int), 0)
    @test n == 1 && LK.PL_compare(ld, v0, a1) == LK.CMP_EQUAL
    # bagof/setof's free-variable collector
    goal = LK.PL_new_term_ref(ld)
    nf, _ = LK.free_variables_loop_cells(ld, -(tf + 1), goal)
    LK.unvisit_cells(ld)
    @test nf == 1
    # numbervars: one '$VAR'(0), twice
    m = LK.Mark(ld)
    opts = LK.nv_options{_R}(_rs("\$VAR"), 0, LK.AV_SKIP, 0, false)
    @test LK.numberVars(ld, tf, opts, 0) == 1
    r = lk_answer(ld, tf)
    @test lk_eq(child(r, 2), child(r, 3)) && lk_eq(child(r, 2), _rf("\$VAR", _rg(Int64(0))))
    LK.Undo!(ld, m)
end
