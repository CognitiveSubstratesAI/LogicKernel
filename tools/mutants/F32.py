# ORIGINAL: f3-2's mutant list — no swipl-devel counterpart.
# tools/mutants/F32.py — the mutation battery of f3-2 (audit D-0111 Q3/Q5; D-0107 item 3: the new invariants
# only): a writer maps a term's variables per WRITE (a write-local map, so one write's occurrences share a cell),
# and H_RFUNCTOR/H_RLIST/H_LIST_FF read a stack `$expr` compound's live export on its CELLS, never with a cursor.
# Run once, in CI, alongside the gate's CI + Evidence (D-0105 item 2). Format: tools/mutate_drive.py's.
TARGETS = [                      # the union of the mutants' targets: the baseline must be green on every one
    "test/core_lang/test_expr_functor.jl",
    "test/core_lang/test_compound_cells.jl",
]
MUTANTS = [
    # _write_var_word!: a variable's second occurrence in one write finds the cell its first one got
    dict(id="G1 every occurrence of a variable in one write gets its own cell", file="src/pl-inline.jl",
         targets=["test/core_lang/test_expr_functor.jl", "test/core_lang/test_compound_cells.jl"],
         old="    p = get(vm.cells, key, 0)\n    if p == 0\n        p = allocGlobalCells!(ld, 1)\n",
         new="    p = 0\n    if p == 0\n        p = allocGlobalCells!(ld, 1)\n"),
    # H_RFUNCTOR_cross: f/k against a stack `$expr/(k+1)` binds or compares its head cell with f
    dict(id="G2 the `$expr` head cell is neither bound nor compared (H_RFUNCTOR)", file="src/pl-wam.jl",
         targets=["test/core_lang/test_expr_functor.jl"],
         old="        _unify_const_loc(ld, hf_q + 1, PCl[hf_lit]) || @goto unify_backtrack   # bound, or bindConst\n",
         new=""),
    # H_RLIST_cross: '[|]'/2 against a stack `$expr/3` binds or compares its head cell with '[|]'
    dict(id="G3 the `$expr` head cell is neither bound nor compared (H_RLIST)", file="src/pl-wam.jl",
         targets=["test/core_lang/test_expr_functor.jl"],
         old="    _unify_const_loc(ld, hl_q + 1, gd.atom_dot) || @goto unify_backtrack    # bound, or bindConst\n",
         new=""),
    # _hlistff_cross!: H and T take the `$expr/3`'s two argument cells, in order
    dict(id="G4 H_LIST_FF's head slot takes the tail cell", file="src/pl-wam.jl",
         targets=["test/core_lang/test_expr_functor.jl"],
         old="    _slot_from_cell!(ld, a, q + 2)\n",
         new="    _slot_from_cell!(ld, a, q + 3)\n"),
]
