# ORIGINAL: L1c sub-commit 6 — a variable is its KEY, never its Julia object (src/term_interface.jl: "A
# variable term. Its identity is `var_key`"). Since sub-commit 6 a cell's variable term is made on
# demand, per read, through the counted adapter (`_cell_var`); upstream has no counterpart (a cell
# IS its variable). test/core_lang/test_var_identity.jl — on every term type:
#   * two reads of ONE unbound cell, placed together in one term, behave as ONE variable in every
#     operation that recognises a variable met twice: the term-level unifier (binding one binds the
#     other), the standard order (`==` / `compareStandard`), copy_term (one fresh variable in the
#     copy), the occurs check, numbervars (one `'$VAR'(N)`), the writer's variable name, and the
#     variable collectors of term_variables/2 and bagof/setof (`free_variables_loop`): each sees ONE.
#   * the audit behind it (2026-10-16): every variable comparison in src/ is by `var_key` —
#     `compare_primitives` (after an `===` shortcut that only short-circuits equal objects),
#     `_same_cell` (the occurs check), `unify_simple_ptrs`, the variant check's `Dict{UInt64}`,
#     copy_term's maps, the collectors' `Set{UInt64}`, `varName`; every `IdDict` holds COMPOUNDS.
#   NOTE: under both shipped term types two reads are also `===` (immutable values compare by
#   content: the reference type shares its leaves' empty child vector, the alternative type's
#   variable is a bits value), so this test guards the BEHAVIOUR; a term type with mutable variable
#   nodes is what the key rule protects.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "..", "core_lang", "rules_common.jl"))

"An engine with one fresh cell; two separate reads of its variable term, and the cell's position."
function _vi_two_reads()
    db = _rdb(Tuple{_R, Union{Nothing, _R}}[])
    ld = db.ld
    LK.PL_open_foreign_frame(ld)
    p = LK.allocGlobalCells!(ld, 1)
    r1 = LK._cell_var(ld, p)
    r2 = LK._cell_var(ld, p)
    return ld, p, r1, r2
end

@testset "two reads of one cell are one variable" begin
    ld, p, r1, r2 = _vi_two_reads()
    @test var_key(r1) == var_key(r2)
    # the standard order
    @test LK.compareStandard(r1, r2, true) == 0
    # the term-level unifier: binding through one read binds the other
    m = LK.Mark(ld)
    @test LK.pl_unify!(ld, _rf("f", r1, r2), _rf("f", _rs("a"), _rv(1)))
    @test lk_eq(LK.deRef(ld, r2), _rs("a")) && lk_eq(LK.deRef(ld, _rv(1)), _rs("a"))
    LK.Undo!(ld, m)
    @test kind(LK.deRef(ld, r1)) === VAR
    # f(R1, R2) = f(b, c) fails: one variable cannot be both
    m = LK.Mark(ld)
    @test !LK.pl_unify!(ld, _rf("f", r1, r2), _rf("f", _rs("b"), _rs("c")))
    LK.Undo!(ld, m)
    # copy_term: ONE fresh variable, twice
    c = LK.copy_term(ld, _rf("f", r1, r2), LK.cp_options(false))
    @test kind(child(c, 2)) === VAR && var_key(child(c, 2)) == var_key(child(c, 3))
    @test var_key(child(c, 2)) != var_key(r1)
    # the occurs check: R1 occurs in g(R2)
    @test LK.var_occurs_in(ld, r1, _rf("g", r2))
    # the writer's name (L1d step 7b: varName reads a term reference's location — each read put in its own)
    t1 = LK.PL_new_term_ref(ld)
    LK.setSlotValue!(ld, t1 + 1, r1)
    t2 = LK.PL_new_term_ref(ld)
    LK.setSlotValue!(ld, t2 + 1, r2)
    @test LK.varName(ld, t1) == LK.varName(ld, t2)
    @test LK.varName(ld, t1) == "_" * string(var_key(r1))
end

@testset "numbervars and the variable collectors see one variable" begin
    ld, p, r1, r2 = _vi_two_reads()
    t = LK.PL_new_term_ref(ld)
    LK.setSlotValue!(ld, t + 1, _rf("f", r1, r2))
    # term_variables/2's collector
    n, vars = LK.term_variables_to_termv(ld, t, typemax(Int))
    @test n == 1 && length(vars) == 1 && var_key(vars[1]) == var_key(r1)
    # bagof/setof's free-variable collector
    fv = _R[]
    LK.free_variables_loop(ld, _rf("f", r1, r2), fv)
    @test length(fv) == 1
    # numbervars: one '$VAR'(0), twice
    m = LK.Mark(ld)
    opts = LK.nv_options{_R}(_rs("\$VAR"), 0, LK.AV_SKIP, 0, false)
    @test LK.numberVars(ld, t, opts, 0) == 1
    r = LK.resolve_term(ld, LK.slotValue(ld, t + 1))
    @test lk_eq(child(r, 2), child(r, 3)) && lk_eq(child(r, 2), _rf("\$VAR", _rg(Int64(0))))
    LK.Undo!(ld, m)
end
