# DICT-SET handoff (branch wip/dict-set, from c1c104f4)

Plan: port b_set_dict/3, nb_set_dict/3, nb_link_dict/3 (pl-dict.c setdict) over the kernel's setarg (src/pl-prims.jl).

Committed:
- src: `setdict` + three `pl_*_va` entries in src/pl-dict.jl, registered after put_dict/4 (upstream's PRED_DEF order).

To do: rows (test/core_lang/test_dict_set_swipl.jl/.pl/.out), manifest entries, mutants (tools/mutants/DICTSET.py), cost lines.
Not run: test_type_discipline.jl, warm.sh check, any julia.

Committed (2): test/core_lang/test_dict_set_swipl.{jl,pl,out}: 32 rows t0-t31, .out from ~/.local/bin/swipl 10.1.20, two runs byte-identical.
Rows never run against the kernel (no julia in this step): a red row is a finding for the gate agent.

Committed (3): manifest entries (setdict, three pl_*_va), tools/mutants/DICTSET.py (15 mutants, every old once in src/pl-dict.jl),
cost lines (pkgtest 3.9 copied from test_dict_preds_swipl.jl, unit 9.1 copied from test_det_swipl.jl: estimates).
tools/mutants/DICTREC.py is not in the tree: the format was read from tools/mutants/DICT.py.
test/core_lang/test_dict_preds_swipl.jl line 11 still says these predicates are left to the SETARG follow-up (a comment; not edited here).
Left for the gate agent: fmt, check, the three term types, test_type_discipline.jl, pkgtest_way, push mutants/DICTSET then gate.
