# SETARG C1 / C2 kill proof (hand-applied mutants, ONE at a time, 3 term types, 2026-11-01)

Rows: sa84-sa89 (C1), sa90-sa94 (C2), added to test/core_lang/test_setarg_swipl.jl; swipl 10.1.19 pins from two byte-identical runs of setarg_driver.pl (generator gen_rows.py); rows sa01-sa83 pins unchanged. Kernel, unmutated tree: 315/315 (94 rows x3 + 33).

Store path (D-0305 item 3): setarg/nb_setarg/nb_linkarg all end in unify_vp (src/pl-prims.jl, port of pl-prims.c unify_vp), NOT unify_ptrs_cells; the one exception is setarg on an UNBOUND argument (the BACKTRACKABLE branch, 'isVar(*a2)'), which calls unify_ptrs_cells (that is why sa12 cannot kill C1). _cell_link_lower! was not reused: it links a SLOT (term-ref) to a cell, while unify_vp works on a global location vs a location with _deref_loc; the rows pin its observable result (standard order) instead.

## C1: src/pl-prims.jl unify_vp  'if v < vp' -> 'if v > vp'  ("a variable value binds the other way round")
Rows sa84-sa86: W = _, V = _, T = f(a), OP(1,T,V), compare(O1,W,A), compare(O2,A,V): swipl <,= ; mutant <,> (the stored cell is not linked to the older V). Rows sa87-sa89: T = f(a), W = _, X = _, OP(1,T,X), compare(O1,A,W), compare(O2,A,X): swipl <,= ; mutant >,= (identity is the newer X, not the cell).
Result: 18 failures = 6 rows x 3 term types, all sa84-sa89; 297 pass. Failing lines (ours vs swipl, one type):
  ours  t_sa84 c[116,95,115,97,56,52]/1(c[45]/2(a[60],a[62]))
  ours  t_sa85 c[116,95,115,97,56,53]/1(c[45]/2(a[60],a[62]))
  ours  t_sa86 c[116,95,115,97,56,54]/1(c[45]/2(a[60],a[62]))
  ours  t_sa87 c[116,95,115,97,56,55]/1(c[45]/2(a[62],a[61]))
  ours  t_sa88 c[116,95,115,97,56,56]/1(c[45]/2(a[62],a[61]))
  ours  t_sa89 c[116,95,115,97,56,57]/1(c[45]/2(a[62],a[61]))
  swipl t_sa84 c[116,95,115,97,56,52]/1(c[45]/2(a[60],a[61]))
  swipl t_sa85 c[116,95,115,97,56,53]/1(c[45]/2(a[60],a[61]))
  swipl t_sa86 c[116,95,115,97,56,54]/1(c[45]/2(a[60],a[61]))
  swipl t_sa87 c[116,95,115,97,56,55]/1(c[45]/2(a[60],a[61]))
  swipl t_sa88 c[116,95,115,97,56,56]/1(c[45]/2(a[60],a[61]))
  swipl t_sa89 c[116,95,115,97,56,57]/1(c[45]/2(a[60],a[61]))

## C2: unify_vp  'elseif k == DU_ATTVAR' -> 'elseif false'  (attributed variable stored as a plain value word)
Rows sa90/sa91: stored cell vs the variable: swipl same, mutant diff (a copy of the attvar word is a different variable). sa92-sa94: X = 5 / A = 6 / X = 7 after the store wakes the attr_unify_hook of user (sa_log) and the compound or X shows the bound value; mutant: the compound keeps an unbound attributed copy, X stays unbound.
Result: 15 failures = 5 rows x 3 term types, all sa90-sa94; 300 pass. Failing lines (ours vs swipl, one type):
  ours  t_sa90 c[116,95,115,97,57,48]/1(c[45]/2(c[115,97,95,108,111,103]/1(a[115,57,48]),a[100,105,102,102]))
  ours  t_sa91 c[116,95,115,97,57,49]/1(c[45]/2(c[115,97,95,108,111,103]/1(a[115,57,49]),a[100,105,102,102]))
  ours  t_sa92 c[116,95,115,97,57,50]/1(c[45]/2(c[102]/1(V0),c[91,124,93]/2(i5,nil)))
  ours  t_sa93 c[116,95,115,97,57,51]/1(c[45]/2(V0,c[91,124,93]/2(i6,nil)))
  ours  t_sa94 c[116,95,115,97,57,52]/1(c[45]/2(c[102]/1(V0),c[91,124,93]/2(i7,nil)))
  swipl t_sa90 c[116,95,115,97,57,48]/1(c[45]/2(c[115,97,95,108,111,103]/1(a[115,57,48]),a[115,97,109,101]))
  swipl t_sa91 c[116,95,115,97,57,49]/1(c[45]/2(c[115,97,95,108,111,103]/1(a[115,57,49]),a[115,97,109,101]))
  swipl t_sa92 c[116,95,115,97,57,50]/1(c[45]/2(c[102]/1(i5),c[91,124,93]/2(i5,nil)))
  swipl t_sa93 c[116,95,115,97,57,51]/1(c[45]/2(i6,c[91,124,93]/2(i6,nil)))
  swipl t_sa94 c[116,95,115,97,57,52]/1(c[45]/2(c[102]/1(i7),c[91,124,93]/2(i7,nil)))

Both mutants reverted (git status -s src empty).
