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
GROUP 7 STARTED (coder 2 hit the cap): test/core_lang/test_pr1_swipl.jl is assembled (105 cases pr01-pr105, program, helpers pr_try/pr_cp,
copy of test_style_check_swipl.jl's encoder/driver/kernel runner with sc->pr) and committed UNFINISHED. TO DO for the next coder:
(a) fix the file's header comment (says pr01-pr72 and pr60/pr61: now pr01-pr105; size/last_modified rows are the two `integer(V)` rows near the end),
and the tail still carries style_check text: rename the testset titles, `error(SsuE, _)` -> `error(E, _)` in `_pr_file` (file name pr1.pl),
rewrite the non-vacuity testset (both sides non-empty: `ok` first, count of `raised` lines >= 10, rows pr-abolish bad-arg lines have `raised`,
enumeration rows non-empty); add the `# TERM TYPES PER CHUNK` comment line before `include(term_under_test.jl)`;
(b) write evidence/PR1/gen_rows.py: parse THIS test file (regex `const _PR_PROGRAM = raw"""(.*?)"""`, `_PR_CASES` tuples `("id", raw"goal")`, `_PR_DRIVER`)
-> build the same text `_pr_file` builds -> run `swipl -q drv.pl` TWICE (driver from `_pr_swipl_lines`) -> require byte-identical -> write evidence/PR1/pr_rows.out
and with --fill rewrite the `const _PR_PINNED = [...]` block (one line per output line, double quotes escaped, `$` escaped); check the swipl output has
one line per case; review rows whose swipl answer is an error you did not expect (a row that raises for the wrong reason is rewritten, not pinned);
(c) the generator source in the test is the single extractor; rows were never run, kernel answers are UNVERIFIED (gate decides). The assembler
script lives only in the previous coder's scratchpad: edit the test file directly. Then groups 8-10 below.
NOT YET WRITTEN (groups 8-10; group 7 above): oracle rows test/core_lang/test_pr1_swipl.jl + evidence/PR1 generator/driver/.out; tools/mutants/PR1.py;
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

### Status after coder 3 (groups 7-10 written; the FOLD is NOT done)
Committed on wip/pr1 after 29acfb5: d7591e8 rows finished + evidence/PR1/gen_rows.py (pr01-pr105, pins from two byte-identical swipl 10.1.19 runs);
589f60e rows pr106-pr111 + `live_states(ld) == 0`; 5b77c09 rows pr112-pr117 (118 pinned lines); aaba28e tools/mutants/PR1.py (53 mutants, 1 equivalent
at pl-proc.jl:2244-2245; validated by a python3 -I runpy script: 0 bad); b2ba943 docs/architecture.md PR1 block.
Edits to review: pr03 now abolishes pr_s7 (was pr_s1, which later rows read); pr45/pr62 filter the modules; pr60 is once/1.
UNCOMMITTED at the cap (commit it first): test/static_analysis_manifest.jl, 29 entries added after the `# LB2 ERR_MODIFY_STATIC_PROC` PL_error line
(all new functions of PR1, cur_pred_enum / cur_enum{T} constructors, the two pools' constructors and alloc/free). TO CHECK: the aliases D, CL, PR, GD, LD,
MOD, T are in scope in THAT group (D, C, CL are defined at line 343 inside `_manifest_index(T)`; the group at ~2092-2130 holds `PR` and `D` in older entries:
find its enclosing function and add a missing alias, or move the PR1 entries next to `LK.deleteIndex!` (line 591) / the NF3 block); a constructor entry
for a struct that older steps do not list (op_enum{T}, recorded_state{T}) may be dropped if the gate does not need it.
STILL TO DO: (1) commit the manifest; (2) FOLD into <= 12 commits on `wip/pr1-f` (`git switch -c wip/pr1-f wip/pr1`, a todo file with pick/fixup, run
`GIT_SEQUENCE_EDITOR='cp <todo>' git rebase -i 584476f`; then `git diff --quiet wip/pr1 wip/pr1-f` must exit 0). The stack is 17 commits now
(5bba737 plan, e832a96, 69f0b07, 6477290, 7d3925f handoff, 06ca276, 430b40a, 988e2b1, dee70dd, e6ca400 handoff, 29acfb5 rows WIP, d7591e8, 589f60e,
5b77c09, aaba28e, b2ba943, manifest): fold 7d3925f and e6ca400 into 5bba737 (or drop the in-tree handoff copies), 29acfb5+d7591e8+589f60e+5b77c09 into
one rows commit, keep the four UPSTREAM groups (e832a96, 69f0b07, 6477290, 06ca276+430b40a? one per C function group), docs and manifest last.
(3) Handoff update after the fold. NOTHING compiled or run: the kernel answers of every row are UNVERIFIED; gate order below.

### Gate order (end of step)
fmt (via warm.sh send of committed files), inventory, check, rows on all three term types, type discipline, pkgtest_way test_pr1_swipl.jl, mutants branch
(`mutants/PR1` at the WIP SHA), branch-gate, term grep, alloc pins x3 (Tier-1), gate push on a fresh name.

### Gate agent 1 (2026-11-02): rebased and folded, NOTHING compiled or run
wip/pr1b = wip/pr1 rebased onto origin/main 9e0a983 and folded 17 -> 12 commits (+ one comment-reword commit, to be folded
into the last UPSTREAM commit before the push). One conflict: pl-global.jl (the two pools, placed after recorded_states, before
input_context_stack; ctor positional order matches). The manifest aliases (D, CL, PR, GD, LD, MOD) are all defined at the top of
`_manifest_index(T)` (lines 360-375), where the PR1 group sits: no change needed. Stale-pin hunt: no test names abolish/
current_predicate/get_predicate_attribute in a KNOWN DIFFERENCE/interim/until R2/existence_error line; refusals pinned by MOD5b/LB2 rows stay.
Term grep over `git log -p`: one benign match (the name of a stack structure, a context line). Daemon not started: load average 18-24.
Gate agent 1, later: the first warm start FAILED to precompile: `_tbl_is_predicate_attribute(::Type{T}, k)::Bool where {T} = ...`
left T unbound at load (pl-proc.jl); now a `function ... where {T}` form, folded into the attribute reader commit. wip/pr1b re-rebased
onto origin/main eb700e8 (ARGINL landed meanwhile; clean). The second daemon start was refused: lk-f2 and lk-q10 daemons were up and
vmstat showed 1-2% idle. NEXT: start the daemon (LOGICKERNEL_WARM_THIRD=1 if refused) when idle >= 25%, then the gate order.

### Gate agent 2 (2026-11-02): refolded onto main 2416adb, daemon up
wip/pr1c = the 12-commit refold (the three gate-1 fixes folded into their commits by file and hunk; identical-tree check against adb3811 passed,
then rebased onto origin/main 2416adb: one doc conflict, both blocks kept). Done: inventory (clean, 251 files, no diff), formatter on the 8 changed
.jl files (0 rewritten). The warm daemon had loaded a cache compiled before the rebase (Revise does not see a file that was edited while the
cache compiled): `Revise.revise(LogicKernel)` (242 s) brought it to the current tree. NEXT: check, fast static pre-check, type discipline, rows x3,
pkgtest_way one file, push gate/<new name>, ci_wait, battery on a fresh name, alloc pins x3.

## PR1b (gate agent 3, 2026-11-02): the three abolish refusals re-pointed at abolishProcedure!
Why: boot/load.pl:47,49 run abolish on predicates that have clauses (R2/boot_features.md row 7); the refusals stopped the boot.
Done (wip/pr1f, 12 commits over origin/main 012633e, rebuilt from wip/pr1e 2aa9719 by tree-per-commit plumbing, no force):
- src/pl-proc.jl: overruleImportedProcedure (pl-proc.c:497-540: weak import -> ignored_weak_import warning under the flag, then
  abolishProcedure!), redefineProcedure (pl-proc.c:3979-4040: the foreign and the other-file branches; the explicit thread-local
  check is gone, abolishProcedure! raises it, as measured on swipl). src/pl-modul.jl: declareModule calls abolishProcedure!
  (pl-modul.c:1338); `_abolishProcedure_pristine` and its manifest row removed.
- rows: pr118-pr127 (directive abolish + asserta as load.pl:47-48, weak import overruled, module redeclared) and the two-file
  rows t_rd1-t_rd7 (evidence/PR1/gen_rows.py --rd; two byte-identical swipl runs, LC_ALL=C). Re-pointed existing rows (were
  pinned refusals): Q7 in test_declare_destroy_swipl.jl, F5 in test_export_import_swipl.jl, the two redefinition checks in
  test/files/test_load_swipl.jl. All kernel expectations are UNVERIFIED on the kernel until the gate runs them.
- tools/mutants/PR1c.py: 60 mutants (PR1-R1..R7 new; R7 is a declared-equivalent candidate for the dispatcher to rule).
- Foreign branches (abolishProcedure! foreign, redefineProcedure foreign) have no row (no user-made foreign predicate).

### Gate agents 4 and 5 (2026-11-02): local gate, fold
Agent 4: the unqualified `'$import'` in `user` replaces the `mod:'$import'` directive in the rows program (pr123/pr124 read pr_wq) and in F5 of
test_export_import_swipl.jl (the minimal loader refuses a goal in another module; the swipl pins are unchanged); row pr127 (abolish after
assertz of a rule and two facts, number_of_rules 0 as swipl); a white-box testset (B1: erased_clauses == 2 and the generation order of the
erased clauses; A1: a built index of a static predicate stays with every slot dead after abolish); the PR1c.py anchors and KILL texts.
Agent 5: pkgtest_way over test_pr1_swipl, test_declare_destroy_swipl, test_export_import_swipl, test_load_swipl: all four passed (peak <= 1.5 GiB);
alloc pins x3: test_zero_exports 239, test_local_stack 377, test_query 347 (= the LB3 baseline), test_rules_swipl 433 (the baseline 439 predates
f235b52 in main: -2 x 3 types = -6, S2A/gate.md); the 12 commits were refolded with these edits (tree-per-commit plumbing, no force).
Agent 6 (audit D-0373): battery on 64d481b = 56 caught, 2 declared equivalent, 2 survivors. PR1-A2 is now declared equivalent in tools/mutants/PR1c.py
(src/pl-index.jl:1562-1575 -> replaceIndex! 1508-1527, isSortedIndexes 1477-1489). PR1-B2 survived because num_visible_clauses walks a dynamic predicate's
clauses once the stored count is above 0, so a wrapped number_of_rules read 0 anyway after one fact; row pr127 now also adds a rule and reads
[0, 1] (swipl 10.1.19, two byte-identical runs, LC_ALL=C): the mutant now fails it, the real code passes (reference, alt, alt_interned 678/678).
