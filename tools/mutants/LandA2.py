# ORIGINAL: landing A's mutant list — no swipl-devel counterpart.
# tools/mutants/LandA2.py — the mutation battery of landing A (f3b-4 + f3b-5a + f3b-5b; D-0107 item 3: one small
# battery per landing, its NEW invariants and CHANGED behaviour only): error and message terms laid on the cells
# (PL_cons_functor, pushWordAsTermRef on LD->tmp), the readers on words, the VM's reads on words. Run once, in CI,
# alongside the gate's CI + Evidence (D-0105 item 2; .github/workflows/mutation.yml). Format: tools/mutate_drive.py's.
#
# Not a mutant, with the reason: dropping popTermRef's `ld.gstack[c] = word(0)` is EQUIVALENT by construction —
# a temporary handle is only ever SET (`_slot_link_loc!`: a reference to the culprit's own cell, or a word), so
# its permanent cell is never bound; the slot's reset (LA1) is the check that matters.
TARGETS = [                      # the union of the mutants' targets: the baseline must be green on every one
    "test/foreign/test_exceptions_swipl.jl",
    "test/core_lang/test_head_unify_swipl.jl",
    "test/core_lang/test_occurs_cells.jl",
    "test/core_lang/test_arith_swipl.jl",
    "test/core_lang/test_det_swipl.jl",
    "test/foreign/test_query_answers.jl",
    "test/foreign/test_typetests_swipl.jl",
    "test/core_text/test_read_term_swipl.jl",
    "test/db/test_assert_swipl.jl",
    "test/core_lang/test_cleanup_swipl.jl",
]
FLI, PRIMS, ERR, ARITH, WAM = "src/pl-fli.jl", "src/pl-prims.jl", "src/pl-error.jl", "src/pl-arith.jl", "src/pl-wam.jl"
MUTANTS = [
    # popTermRef (pl-fli.c 416): the handle references its permanent cell again
    dict(id="LA1 popTermRef leaves the handle's slot as it was", file=FLI,
         targets=["test/foreign/test_exceptions_swipl.jl"],
         old="    ld.slots[ld.tmp_h + i + 1] = makeRefG(c)\n",
         new=""),
    # pushWordAsTermRef (pl-fli.c 405): each push its own handle
    dict(id="LA2 pushWordAsTermRef reuses one handle", file=FLI,
         targets=["test/foreign/test_exceptions_swipl.jl", "test/core_lang/test_occurs_cells.jl"],
         old="    ld.tmp_top += 1\n",
         new=""),
    # failed_unify_with_occurs_check (pl-prims.c 676): Var = Term, the variable first
    dict(id="LA3 the occurs-check culprit is not swapped to Var = Term", file=PRIMS,
         targets=["test/core_lang/test_head_unify_swipl.jl", "test/core_lang/test_occurs_cells.jl"],
         old="    if t2[1] == DU_CELL                             # isVar(*t2): try to make Var = Term\n",
         new="    if false                                        # isVar(*t2): try to make Var = Term\n"),
    # cons_functorv (pl-fli.c 1488): the arguments in order
    dict(id="LA4 PL_cons_functor lays the arguments in reverse", file=FLI,
         targets=["test/foreign/test_exceptions_swipl.jl", "test/core_lang/test_arith_swipl.jl"],
         old="        _cell_link!(ld, p + i, a[i] + 1)                        # bindConsVal(++a, valHandleP(r))\n",
         new="        _cell_link!(ld, p + i, a[N - i + 1] + 1)                # bindConsVal(++a, valHandleP(r))\n"),
    # PL_error's context (pl-error.c 808): the caller qualified unless user's (GP_NAMEARITY only)
    dict(id="LA5 the error context hides the system module", file=ERR,
         targets=["test/core_lang/test_arith_swipl.jl", "test/foreign/test_exceptions_swipl.jl"],
         old="            unify_definition(gd, ld, MODULE_user(gd), predterm, caller, 0, GP_NAMEARITY)\n",
         new="            unify_definition(\n                gd, ld, MODULE_user(gd), predterm, caller, 0, GP_NAMEARITY | GP_HIDESYSTEM\n            )\n"),
    # printMessage: the message exported off the cells, once
    dict(id="LA6 printMessage records [] instead of the message", file=ERR,
         targets=["test/core_lang/test_det_swipl.jl"],
         old="    push!(ld.messages, (severity, export_cells(ld, cell_export{T}(), -(msg + 1))))\n",
         new="    push!(ld.messages, (severity, mk_nil(T)))\n"),
    # Q-AR5 `$expr/n` on the cells: the head (argument 1) is not evaluated
    dict(id="LA7 $expr/n evaluates its head", file=ARITH,
         targets=["test/core_lang/test_arith_swipl.jl"],
         old="            for i in arity:-1:2                             # 1), the last first, then not evaluable\n",
         new="            for i in arity:-1:1                             # 1), the last first, then not evaluable\n"),
    # PL_get_functor: a `$expr/n` compound has no functor
    dict(id="LA8 PL_get_functor names $expr/n", file=FLI,
         targets=["test/foreign/test_query_answers.jl"],
         old="            name == ld.atom_dexpr && return nothing\n",
         new=""),
    # I_ATOM (pl-vmi.c TYPE_TEST(isTextAtom))
    dict(id="LA9 I_ATOM tests atomic", file=WAM,
         targets=["test/foreign/test_typetests_swipl.jl"],
         old="    @TYPE_TEST(PL_is_atom)                              # TYPE_TEST(…, isTextAtom)\n",
         new="    @TYPE_TEST(PL_is_atomic)                            # TYPE_TEST(…, isTextAtom)\n"),
    # op_name (pl-read.c 4646): a `[...]` block is named `[]`
    dict(id="LA10 a list block keeps the name '[|]'", file="src/pl-read.jl",
         targets=["test/core_text/test_read_term_swipl.jl"],
         old="    if sym_key(name) == sym_key(mk_sym(T, LIST_CONS_NAME))              # ATOM_dot\n",
         new="    if false                                                            # ATOM_dot\n"),
    # is_neck (pl-comp.c 712): an SSU `=>` clause is refused, not asserted as a fact
    dict(id="LA11 is_neck takes Head => Body for a fact", file="src/pl-comp.jl",
         targets=["test/db/test_assert_swipl.jl"],
         old="        f == lookupFunctorDef(fs, _atom_word!(ld, commit), 2) &&              # FUNCTOR_ssu_commit2\n",
         new="        false &&                                                              # FUNCTOR_ssu_commit2\n"),
    # unify_finished (pl-wam.c 707): exception(Ball) for FINISH_EXCEPT
    dict(id="LA12 unify_finished swaps exception and external_exception", file=WAM,
         targets=["test/core_lang/test_cleanup_swipl.jl"],
         old="        f = reason == FINISH_EXCEPT ? :exception : :external_exception\n",
         new="        f = reason == FINISH_EXCEPT ? :external_exception : :exception\n"),
]
