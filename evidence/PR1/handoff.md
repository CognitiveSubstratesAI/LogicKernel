# PR1 — pl-proc.c remainder (R2 boot C-predicates; audit D-0306 items 2-3)

Branch wip/pr1 off origin/main 584476f. Edit-only writer; nothing run. Lane clone ~/code/lk-pr1.

## Verified predicate list (git grep on origin/main + boot at cbf4e189)

| predicate | upstream | boot caller | state on main | disposition |
|---|---|---|---|---|
| abolish/1 | pl-ext.c:125 FRG META\|ISO -> pl-proc.c:3444 pl_abolish1 | boot/load.pl:47,49 (directive), autoload.pl:981 | NOT REGISTERED; abolishProcedure is only the imported-link branch (`_abolishProcedure_pristine`, pl-modul.jl:1307) | PORT (tier A) |
| abolish/2 | pl-ext.c:126 FRG META -> pl-proc.c:3433 pl_abolish | library only | NOT REGISTERED | PORT (same do_abolish, 3 lines) |
| `$c_current_predicate`/2 | pl-ext.c:132 FRG NDET\|META -> pl-proc.c:803-870 pl_current_predicate | attvar, autoload, expand, init, syspred | NOT REGISTERED | PORT (A2) |
| current_predicate/1 | pl-proc.c:937-1130 PRED_IMPL TRANSPARENT\|NDET\|ISO | 8 boot files | NOT REGISTERED | PORT (A2) |
| `$get_predicate_attribute`/3 | pl-proc.c:3577-3700 PRED_IMPL TRANSPARENT | autoload, expand, init, syspred, tabling | NOT REGISTERED | PORT (A2) |
| garbage_collect_clauses/0 | pl-ext.c:171 FRG -> pl-proc.c:2675 | gc.pl:64, syspred.pl:481 | `pl_garbage_collect_clauses!` exists (pl-proc.jl:836), predicate NOT REGISTERED | register only (1 FRG entry) |
| `$foreign_predicate_source`/2 | pl-proc.c:4137 | syspred.pl:1026 (inside `$addr2line_location` helper, call time) | NOT REGISTERED | R3 (off the load path; needs addr2line) |
| `$addr2line`/2 | pl-proc.c:4173 | none | NOT REGISTERED | R3 |
| `$local_definitions`/2 | pl-proc.c:4190, `#ifdef O_ENGINES` | none | NOT REGISTERED | R3 |
| `$default_predicate`/2, copy_predicate_clauses/2, `$cgc_params`/6 | pl-proc.c table | not in the inventory; no boot file calls them (grep of boot/*.pl) | NOT REGISTERED | R3 |

Not in this landing (listed as follow-ups): re-pointing the NotPortedError refusals that say "abolishProcedure is not
ported" (pl-modul.jl declare_module via `_abolishProcedure_pristine`; pl-proc.jl overruleImportedProcedure /
redefineProcedure) to the new abolishProcedure: each has an existing MOD5b/LB2 row pinning the refusal, so the change is
its own audited step (row edits). Tabling attribute keys of `$get_predicate_attribute/3` (tbl_*) are refused by name
(TAB1 is R3).

## Plan (ordered groups, ~10 commits)
1. plan (this file).
2. pl-index.jl: deleteIndexes (pl-index.c) for resetProcedure. [done/todo below]
3. pl-proc.jl: resetProcedure, removeClausesPredicate, abolishProcedure (all four branches).
4. pl-proc.jl + pl-ext.jl: do_abolish, pl_abolish, pl_abolish1; FRG entries abolish/1,2 + garbage_collect_clauses/0.
5. pl-incl.jl/pl-global.jl: the two state pools; pl-proc.jl: `$c_current_predicate/2` (FRG NDET).
6. pl-proc.jl: current_predicate/1 (NDET PRED_IMPL), `unify_meta_pattern`, `$get_predicate_attribute/3`.
7. test/core_lang/test_pr1_swipl.jl (ids pr01..) + evidence/PR1 generator/driver/.out.
8. tools/mutants/PR1.py.
9. docs/architecture.md block.  10. test/static_analysis_manifest.jl entries.

## Status (kept current; writer 1 ended at the 150k cap)

Committed on wip/pr1 (linear, off 584476f): 5bba737 plan; e832a96 deleteIndexes! (pl-index.jl); 69f0b07 resetProcedure!,
removeClausesPredicate!, abolishProcedure! (pl-proc.jl, all four branches); 6477290 get_arity, do_abolish, pl_abolish,
pl_abolish1, pl_garbage_collect_clauses0 + FRG entries abolish/1,2 (before repeat/0) and garbage_collect_clauses/0
(after `$garbage_collect`) in pl-ext.jl. UNCOMMITTED: nothing (the last python edit was blocked by the cap before it ran).

### Status after coder 2 (groups 5-6 committed)
06ca276 state pools (cur_pred_enum, cur_enum{T}; ld.cur_pred_enums, ld.cur_enums; live_states); 430b40a `$c_current_predicate`/2 +
PL_strip_module_nocreate (pl-proc.jl) + FRG entry before repeat/0; 988e2b1 current_predicate/1 (pl_current_predicate1_va,
_cur_enum_clean!) + table entry after retract; dee70dd `$get_predicate_attribute`/3 + unify_meta_argument/pattern,
num_visible_clauses, sizeof_predicate, _tbl_is_predicate_attribute + table entry after `$set_predicate_attribute`.
NOT YET WRITTEN (groups 7-10): oracle rows test/core_lang/test_pr1_swipl.jl + evidence/PR1 generator/driver/.out; tools/mutants/PR1.py;
docs/architecture.md block; manifest entries. Row ideas are in the list of group 7 above.

### Flags for the audit
- Tier-1 contact: pl-global.jl `PL_local_data` struct gains two pools (group 5, not yet written); pl-proc.jl procedure table
  (`abolishProcedure!` replaces a definition in an imported link and resets flags of others); pl-index.jl `deleteIndexes!`; alloc pins x3 needed at the gate.
- NotPortedError refusals that now could use `abolishProcedure!`, left alone because MOD5b/LB2 rows pin the refusals (own audited step): pl-modul.jl
  `_abolishProcedure_pristine` (declare_module), pl-proc.jl overruleImportedProcedure (~1030) and redefineProcedure (~1120-1145).
- DIVERGES (audit): `$get_predicate_attribute(_, indexed, _)` raises NotPortedError (dict per index); tabling keys FAIL (as an untabled definition; def->tabling NULL); `last_modified_generation` is the module's; `size` the kernel's count; num_visible_clauses ignores reload.
- DIVERGES (behaviour-visible): `resetProcedure!` does not set TRACE_ME (consistent with lookupProcedure; `$get_predicate_attribute(P, trace, V)` differs
  from swipl for abolished predicates, as it already does for fresh ones).
- R3 list: `$foreign_predicate_source/2`, `$addr2line/2`, `$local_definitions/2` (O_ENGINES), `$default_predicate/2`, `copy_predicate_clauses/2`,
  `$cgc_params/6` (no boot file calls them).
- Daemon: none used by this writer (edit-only). Hook note: the cap hook blocks every Bash call but those naming evidence/ at 150k.

### Gate order (end of step)
fmt (via warm.sh send of committed files), inventory, check, rows on all three term types, type discipline, pkgtest_way test_pr1_swipl.jl, mutants branch
(`mutants/PR1` at the WIP SHA), branch-gate, term grep, alloc pins x3 (Tier-1), gate push on a fresh name.
