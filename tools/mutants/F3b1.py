# ORIGINAL: F3b1's mutant list — no swipl-devel counterpart.
# tools/mutants/F3b1.py — the mutation battery of F3B step f3b-1 (writers into words; D-0079 (b), 2026-10-21),
# run ONCE, at the step's close, in CI (.github/workflows/mutation.yml). Format: tools/mutate_drive.py's.
#
# Subject: the code f3b-1 changed that a test can reach — putSlotValue!'s map and layout (pl-inline.jl), the
# ball outOfStack! lays on five global cells (pl-alloc.jl), the ball's restore after discardChoicesAfter
# (pl-wam.jl), the exception clear of _abandon_query (pl-wam.jl) and the counted import of a stale variable
# (pl-inline.jl _import_var!). FB6, FB8 and FB3 are the guards of the three test expectations the step's
# first branch-gate moved (test_catch_swipl.jl's NotPortedError, test_compound_cells.jl's +3,
# test_stack_limit.jl's 5): each must be killed by the changed test, else the change is vacuous.
# FB10–FB17 (D-0088): the ball export and cut, import_origin set/prune, _caller_var, ball_word set/clear.
# What this list does NOT cover: saveWakeup's `_slot_copy!` (no test reaches it until attributed variables are
# ported: its only caller is the wakeup machinery) and the cyclic-term branch of _put_compound! (a mutant of
# it hangs the target: a hang is a kill by the driver's limit, not by an assertion — left out on purpose).
TARGETS = [                      # the union of the mutants' targets: the baseline must be green on every one
    "test/foreign/test_query.jl",
    "test/core_lang/test_zero_exports.jl",
    "test/core_lang/test_stack_limit.jl",
    "test/core_lang/test_catch_swipl.jl",
    "test/core_lang/test_compound_cells.jl",
    "test/db/test_clause_variables.jl",
    "test/core_text/test_write_family_swipl.jl",
    "test/core_lang/test_occurs_check.jl",
]
INL = "src/pl-inline.jl"
ALLOC = "src/pl-alloc.jl"
WAM = "src/pl-wam.jl"
PRM = "src/pl-prims.jl"
TQ = ["test/foreign/test_query.jl", "test/core_lang/test_zero_exports.jl"]
TSL = ["test/core_lang/test_stack_limit.jl", "test/foreign/test_query.jl"]
TCS = ["test/core_lang/test_catch_swipl.jl"]
TCC = ["test/core_lang/test_compound_cells.jl"]
TCV = ["test/db/test_clause_variables.jl"]
TWF = ["test/core_text/test_write_family_swipl.jl"]
TOC = ["test/core_lang/test_occurs_check.jl"]
MUTANTS = [
    # ── putSlotValue!: the variable map and the layout ──
    dict(id="FB1 a variable met again by a later put gets a fresh cell, not the map's", file=INL, targets=TQ,
         old='''        p = get(vm.cells, key, 0)''',
         new='''        p = 0'''),
    dict(id="FB2 a compound's variable already in the map is given a new cell", file=INL, targets=TQ,
         old='''            haskey(vm.cells, key) || (vm.cells[key] = allocGlobalCells!(ld, 1))''',
         new='''            vm.cells[key] = allocGlobalCells!(ld, 1)'''),
    # ── outOfStack!: the ball on five global cells ──
    dict(id="FB3 the ball takes six cells, not five (the changed test_stack_limit row)", file=ALLOC, targets=TSL,
         old='''p = allocGlobalCells!(ld, 5)''',
         new='''p = allocGlobalCells!(ld, 6)'''),
    dict(id="FB4 the ball's resource is `global`, not `stack`", file=ALLOC, targets=TSL,
         old='''ld.gstack[p + 4] = _atom_word!(ld, mk_sym(T, :stack))''',
         new='''ld.gstack[p + 4] = _atom_word!(ld, mk_sym(T, :global))'''),
    dict(id="FB5 the global stack is not frozen over the ball", file=ALLOC, targets=TSL,
         old='''freezeGlobal!(ld)                               # freezeGlobal()''',
         new='''nothing'''),
    # ── the ball across a discard and an abandoned query ──
    dict(id="FB6 an abandoned query leaves the ball in the exception bin (the changed test_catch_swipl row)", file=WAM, targets=TCS,
         old='''PL_clear_exception(ld)                          # (f3b-1) with its `setVar`: the ball is cells now''',
         new='''ld.exception_term = 0'''),
    dict(id="FB7 dbg_discardChoicesAfter does not restore the ball", file=WAM, targets=TCS,
         old='''ld.slots[ld.exception_bin + 1] = w               # *valTermRef(exception_bin) = w''',
         new='''nothing'''),
    # ── the import of a stale variable ──
    dict(id="FB8 the import of a stale variable is not counted (the changed test_compound_cells row)", file=INL, targets=TCC,
         old='''            ld.cold_imports += 1''',
         new='''            nothing'''),
    dict(id="FB9 the fresh cell of an imported stale variable is not trailed", file=INL, targets=TQ + TCC,
         old='''Trail!(ld, var_key(t), mk_var(T, _cell_key(ld, p)))''',
         new='''nothing'''),
    # ── the exception ball read whole, and the caller's variable handed back (D-0087/D-0088; TRANSITIONAL, f3) ──
    dict(id="FB10 the exception ball is exported one level deep, not resolved whole", file=INL, targets=TWF + TOC,
         old='''    return _resolve_term(ld, _compound_term(ld, valPtr(cw)), true)''',
         new='''    return _compound_term(ld, valPtr(cw))'''),
    dict(id="FB11 the cut is off: a ball cyclic through a variable raises instead of keeping the variable", file=PRM, targets=TWF + TOC,
         old='''if cut && kind(c0) === VAR''',
         new='''if false'''),
    dict(id="FB12 the frames on the cycle are not kept as the memoised compound", file=PRM, targets=TWF,
         old='''cyc[j:end] .= true''',
         new='''nothing'''),
    dict(id="FB13 an imported cell's origin is not recorded (import_origin set)", file=INL, targets=TCV + TCC,
         old='''ld.import_origin[ck] = var_key(t) ''',
         new='''nothing; (t) '''),
    dict(id="FB14 the origin of an undone import is not pruned (import_origin prune in _untrail!)", file=INL, targets=TCV + TCC,
         old='''        isempty(ld.import_origin) || kind(v) !== VAR ||
            delete!(ld.import_origin, var_key(v))''',
         new='''        nothing'''),
    dict(id="FB15 the caller's variable is not handed back (_caller_var)", file=PRM, targets=TCV + TCC,
         old='''return o == k ? v : mk_var(T, o)''',
         new='''return v'''),
    dict(id="FB16 the query's ball word is not recorded (ball_word set)", file=WAM, targets=TQ + TWF,
         old='''ld.ball_word = ld.slots[br_q.exception + 1] ''',
         new='''nothing; (br_q) '''),
    dict(id="FB17 the query's ball word is not cleared at its end (ball_word clear)", file=WAM, targets=TQ + TWF,
         old='''q.exception != 0 && (ld.ball_word = UInt64(0))''',
         new='''nothing'''),
]
