# TAB1 gate list (D-0820 (4)(e)), lane 2, wip/tab1-mono at 5bdaa2d9 (+ this file), julia 1.13.3, first agent (TAB1-GATELIST-1)

Method: `LOGICKERNEL_WARM_SECOND=1 WARM_TIMEOUT_S=9000 tools/warm.sh file <f>` (reference, alt, alt_interned), ONE file at a time, 80 files
(the 135 of first_run_files.txt minus the 55 the reports list as run: the upstream/tabling files of first_run_report.md, e1_getter.md,
pin1_i1_i2.md). Counts are the warm summary line: PASS / FAIL / BROKEN totals over the THREE types (per type = total / 3; every type agrees
on every file: the per-type rows were read). Logs: session scratchpad `tb1gl/logs/<file>.log` (not committed). `marks` = lines matching
`SKIP|Warning|Test Failed|Error During`: every `Warning` line of a green file is an engine Prolog message of the test program (singleton
variables, redefined static procedure, discontiguous, import/export notices, `Loading module mq abolished`), none a Julia warning, no SKIP.
Note: the lane-2 daemon was down at the start (my first wrapper was killed mid-restart: my mistake); I started it with
`LOGICKERNEL_WARM_SECOND=1 tools/warm.sh start` (unit logickernel-warm-78a7647c, FIRST slice, lane 1's daemon is in lk-warm2.slice). It is still up.

## Result: 79 of 80 GREEN on three types (76 at 5bdaa2d9, the three D-0083 files: two re-pins 2933e730 893902f0 REVERTED by 36f08764 (D-0822 (4) ruling a), the rank-chain row b07cc1b1 kept), 1 RED (test_transaction_swipl.jl)

### RED (rc 1) at 5bdaa2d9; the first three rows are fixed since
| file | group | PASS / FAIL (3 types) | class |
|---|---|---|---|
| test/core_lang/test_module_path.jl | TB5 | NOW GREEN: 189 / 0, 63 per type (was 168 / 18) | ORIGINAL expectations again (unbooted table 2 modules, first created index 3): 2933e730 reverted by 36f08764 after the cause was fixed in the kernel (`'$run_undo'/1` is made at the first run_undo_hooks call, pl-undo.c:232); three types green, mutation proof (eager creation back) fails :29 :41 :44 :46; pkgtest_way passed |
| test/core_lang/test_module_swipl.jl | LB2c | NOW GREEN: 291 / 0, 97 per type (was 267 / 21; +3 rows: the modules[3] pin) | ORIGINAL expectations again: 893902f0 reverted by 36f08764, same cause; mutation proof fails :386-:393; pkgtest_way passed |
| test/db/test_clause_ref_swipl.jl | LB2c | NOW GREEN: 702 / 0, 234 per type (was 699 / 3) | KEPT, b07cc1b1 (D-0083: undo blob in the rank chain, a faithful registration: initUndo! sits where pl-setup.c:151 calls initUndo; zipper entry WAITS-FOR-LINE: zip line); mutation proof (initUndo! registers nothing) fails the row; pkgtest_way passed (first run killed in the 3G scope while precompiling after the src edit, rerun passed) |
| test/core_lang/test_transaction_swipl.jl | TB9 | 567 / 6 (2 rows per type: :757 t_txx11, :827 txx16) | ENGINE / WAITS-FOR-LINE (as first_run_report.md: `$bags:$suspend_findall_bag/0` undefined, owner R2; UNDO_SCHEDULED at the end of `( undo(tx_push(a)), fail ; R = x )`, class (d)) |

Diagnosis and fix (TAB1-SYSPREDS, evidence/TAB1/syspreds_probe.md): the module `'$syspreds'` was made by setupProlog through the cached
procedure `'$run_undo'/1` (was src/pl-ext.jl:228-237). Upstream registers the undo blob type at init (pl-setup.c:151 initUndo, pl-undo.c:249) and
makes the procedure and its module at the first run_undo_hooks call (pl-undo.c:232). 36f08764 moves the creation into run_undo_hooks
(arity-0 placeholder check, as findReset does for findall_loop/4): the unbooted table holds system and user, the first created module is index 3,
and the two re-pins are reverted. The pin answers `current_module('$syspreds')` / `current_predicate('$syspreds':'$run_undo'/1)` true after boot;
the unbooted table, a module's index and the blob registration order are not observable in swipl. test_clause_ref_swipl.jl's chain row is not
about `'$syspreds'`: the undo blob registration is upstream's and stays (zipper entry WAITS-FOR-LINE).
Other files run on three types after the change, all green: test_numbervars_cells, test_boot_clauses_swipl, test_boot_image_swipl, test_load_swipl
(test_transaction_swipl, red before for its own two rows, was not re-run). `tools/warm.sh check` after the change: only CODE-GRAPH-DRIFT docs/architecture.md
(run_undo_hooks's callees changed; regenerate once on the merged SHA, not done here).

## NOT RUN / TO DO (next agent)
1. DONE (36f08764 reverting 2933e730 893902f0, b07cc1b1 kept; fmt clean, check: CODE-GRAPH-DRIFT only, pkgtest_way passed on the three files). Was: fix the three D-0083 test rows named above (edit one file, run on three types, commit `FIXED: <file>: ...`; stage and commit in separate Bash calls);
   run test_module_path.jl, test_module_swipl.jl, test_clause_ref_swipl.jl on three types and grep logs for `SKIP|Warning|Test Failed|Error During`.
2. `tools/warm.sh fmt`, then `tools/warm.sh check` ONCE, pkgtest_way on each changed test file (`tools/pkgtest_way.sh <file>`, one at a time).
3. Files of the 135 NOT run by this agent: test_tabling_monotonic_swipl.jl (21 min; run by the E1 agent: 39/39 green, e1_getter.md) and nothing else:
   every other name of first_run_files.txt is either in the reports' run lists or in the 80 above. The reports' per-file results were measured at 99e5975c / earlier
   commits of wip/tab1-mono, not re-run at 5bdaa2d9: a re-run of the "green" upstream files at the gate SHA is still owed if the dispatcher wants "green AT the gate SHA".
4. The lane-2 daemon (unit logickernel-warm-78a7647c) is up and idle since ~01:30 UTC 2026-11-16 (exits after 3600 s idle).
