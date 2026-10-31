# G1 — global variables (pl-gvar.c whole), coder 1. Branch wip/g1 off origin/main bf41225.

State: PLAN (group 1). Nothing run; no Julia in this lane yet (edit-only coding).
Design: lk-channel evidence/r2/design/flags_rest.md §4 D7/D8, H6-H9, §6 G1 row. Upstream: pl-gvar.c @ cbf4e1896275.

## Plan: function -> upstream -> Julia site
New file src/pl-gvar.jl (included after pl-bag.jl in src/LogicKernel.jl; table `PL_predicates_from_gvar` appended
to `_PRED_TABLES`/`_FOREIGN_VA` in src/pl-ext.jl, upstream's order: after attvar).

| function | upstream | Julia |
|---|---|---|
| table + `grefs` | LD->gvar.nb_vars / .grefs | `ld.gvar_nb_vars::Dict{UInt64,UInt64}`, `ld.gvar_grefs::Int` (pl-global.jl, D7); `ld.gvar_enums` pool for nb_current |
| new_gvar, lookup_gvar | pl-gvar.c:98-125 | `new_gvar!`, `lookup_gvar` |
| PL_getval | :133-141 | `PL_getval` (a term_t) |
| word_is_attvar, setval_duplicate | :153-189 | same names; `duplicate_term` (pl-copyterm.jl, nshare/share NOT PORTED) |
| setval (SETVAL_BACKTRACKABLE/LINK) | :194-262 | `gvar_setval` ; H7: b_setval moves the value into a fresh global cell, freezeGlobal!, TrailAssignment! |
| auto_define_gvar, gvar_value | :272-343 | `auto_define_gvar` (user:exception/3 via PL_call_predicate, D8), `gvar_value` |
| is_gval, getval | :346-395 | `is_gval`, `gvar_getval` |
| nb_setval/nb_linkval/nb_getval/b_setval/b_getval | :398-430 | `pl_nb_setval2_va` ... |
| nb_delete | :436-460 | `pl_nb_delete1_va` |
| nb_current | :464-520 | `pl_nb_current2_va` (REDO_PTR pool `ld.gvar_enums`, keys snapshotted) |
| destroyGlobalVars | :56-63 | NOT PORTED (no thread end); `freeze` already in pl-inline.jl |
| `user:exception/3` dynamic (D8) | boot/init.pl:945 | `setBuiltinPredicateProperties!` (src/pl-ext.jl) |
| query-end release (D7) | — | `_release_frozen!` returns while `gvar_grefs > 0` (src/pl-inline.jl) |
| get_variable_names | pl-comp.c | reads `gvar_value('$variable_names')` when `ld.variable_names == 0` (field stays until LB4) |
