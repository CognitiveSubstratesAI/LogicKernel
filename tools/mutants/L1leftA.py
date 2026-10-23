# ORIGINAL: L1leftA's mutant list — no swipl-devel counterpart.
# tools/mutants/L1leftA.py — the mutation battery of the L1 leftovers' first part (audit D-0115, D-0117;
# gate/l1left-a 103ebdd, 2026-10-23), run ONCE, in CI (.github/workflows/mutation.yml; locally:
# tools/mutate.sh run). The format is tools/mutate_drive.py's: `id`, `file`, `old` (must occur EXACTLY
# once), `new`, optional `equivalent` (a mutant that must SURVIVE, with the code reason) and `targets`.
#
# Subject: PL_same_term's equalIndirect over value-table words AND side words (D-0117 (a)), and
# free_variables_loop_cells storing a value root as itself (D-0117 (b)).
TARGETS = [
    "test/core_lang/test_same_term_swipl.jl",
    "test/core_lang/test_walks_cells.jl",
    "test/core_lang/test_bagof_swipl.jl",
]
P = "src/pl-prims.jl"
ST = ["test/core_lang/test_same_term_swipl.jl"]
FV = ["test/core_lang/test_walks_cells.jl", "test/core_lang/test_bagof_swipl.jl"]
MUTANTS = [
    # ── PL_same_term (pl-prims.c:2423) ──
    dict(id="LA1 a side word on the left is no indirect", file=P, targets=ST,
         old='''    if (_is_vword(w1) || _is_side_word(w1)) &&              # isIndirect(*t1) &&''',
         new='''    if _is_vword(w1) &&              # isIndirect(*t1) &&'''),
    dict(id="LA2 a side word on the right is no indirect", file=P, targets=ST,
         old='''        (_is_vword(w2) || _is_side_word(w2))                 # isIndirect(*t2)''',
         new='''        _is_vword(w2)                 # isIndirect(*t2)'''),
    dict(id="LA3 two indirects by identity, not equalIndirect", file=P, targets=ST,
         old='''        return gnd_equal(_value_term(ld, w1), _value_term(ld, w2))   # equalIndirect''',
         new='''        return _value_term(ld, w1) === _value_term(ld, w2)   # equalIndirect'''),
    # ── free_variables_loop_cells (pl-prims.c:3977) ──
    dict(id="LA4 a value root referenced through its (absent) cell", file=P, targets=FV,
         old='''                ld.slots[goal + 1] = w                      # *valTermRef(goal) = *t''',
         new='''                ld.slots[goal + 1] = (k == DU_VALUE && !isTaggedIntW(w)) ? makeRefG(p) : w'''),
    dict(id="LA5 a side word stored as a word", file=P, targets=FV,
         old='''            if _is_side_word(w)                             # (f3-1) a slot's side value: its''',
         new='''            if false                             # (f3-1) a slot's side value: its'''),
    dict(id="LA6 a value root is not the goal", file=P, targets=FV,
         old='''                ld.slots[goal + 1] = w                      # *valTermRef(goal) = *t''',
         new='''                nothing                      # *valTermRef(goal) = *t'''),
]
