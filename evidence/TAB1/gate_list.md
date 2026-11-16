# TAB1 gate list (D-0820 (4)(e)), lane 2, wip/tab1-mono at 5bdaa2d9 (+ this file), julia 1.13.3, first agent (TAB1-GATELIST-1)

Method: `LOGICKERNEL_WARM_SECOND=1 WARM_TIMEOUT_S=9000 tools/warm.sh file <f>` (reference, alt, alt_interned), ONE file at a time, 80 files
(the 135 of first_run_files.txt minus the 55 the reports list as run: the upstream/tabling files of first_run_report.md, e1_getter.md,
pin1_i1_i2.md). Counts are the warm summary line: PASS / FAIL / BROKEN totals over the THREE types (per type = total / 3; every type agrees
on every file: the per-type rows were read). Logs: session scratchpad `tb1gl/logs/<file>.log` (not committed). `marks` = lines matching
`SKIP|Warning|Test Failed|Error During`: every `Warning` line of a green file is an engine Prolog message of the test program (singleton
variables, redefined static procedure, discontiguous, import/export notices, `Loading module mq abolished`), none a Julia warning, no SKIP.
Note: the lane-2 daemon was down at the start (my first wrapper was killed mid-restart: my mistake); I started it with
`LOGICKERNEL_WARM_SECOND=1 tools/warm.sh start` (unit logickernel-warm-78a7647c, FIRST slice, lane 1's daemon is in lk-warm2.slice). It is still up.

## Result: 79 of 80 GREEN on three types (76 at 5bdaa2d9, the three D-0083 files fixed since: 2933e730 893902f0 b07cc1b1), 1 RED (test_transaction_swipl.jl)

### RED (rc 1) at 5bdaa2d9; the first three rows are fixed since
| file | group | PASS / FAIL (3 types) | class |
|---|---|---|---|
| test/core_lang/test_module_path.jl | TB5 | NOW GREEN: 189 / 0, 63 per type (was 168 / 18) | fixed in 2933e730 (D-0083: unbooted table 3 modules, first created index 4, new row pins modules[3]); pkgtest_way passed |
| test/core_lang/test_module_swipl.jl | LB2c | NOW GREEN: 291 / 0, 97 per type (was 267 / 21; +3 rows: the modules[3] pin) | fixed in 893902f0 (D-0083, same cause); pkgtest_way passed |
| test/db/test_clause_ref_swipl.jl | LB2c | NOW GREEN: 702 / 0, 234 per type (was 699 / 3) | fixed in b07cc1b1 (D-0083: undo blob in the rank chain; zipper entry WAITS-FOR-LINE: zip line); pkgtest_way passed |
| test/core_lang/test_transaction_swipl.jl | TB9 | 567 / 6 (2 rows per type: :757 t_txx11, :827 txx16) | ENGINE / WAITS-FOR-LINE (as first_run_report.md: `$bags:$suspend_findall_bag/0` undefined, owner R2; UNDO_SCHEDULED at the end of `( undo(tx_push(a)), fail ; R = x )`, class (d)) |

Diagnosis already measured (probe on the lane-2 daemon, `LK.setupProlog(DefaultTerm)`):
- module_path / module_swipl: `gd.modules` = `(1, system) (2, user) (3, '$syspreds', flags 0x53, supers [1])`. The third module is made by setupProlog
  (src/pl-ext.jl:228-237, TX1e: the cached procedure `'$run_undo'/1` in `'$syspreds'`; upstream makes the module at the first run_undo_hooks call,
  pl-undo.c:232 `_PL_predicate("$run_undo", 1, "$syspreds", ...)`), so every row that counts the unbooted table (2 modules) or the index of the first
  created module (3) is stale by one. FIX (test only, D-0083 disclosure in the comment, value read off the generator): length 2 -> 3, the first
  created module has index 4 (`m == 4`, `gd.modules[4]`), add a row `modules[3]` is `'$syspreds'` with supers `[system]`; the same shift in
  test_module_swipl.jl :386-394 and :420 (`length(gd.modules) == 6` -> 7; read the file around :380-425 first). I had the python edit of
  test_module_path.jl ready (lines 28-29, 41, 44, 46, 157-159) and the hook cap blocked it: THE TREE IS UNCHANGED.
- test_clause_ref_swipl.jl :539: ranks record -1, clause -2, trie -3, closure -5. Between trie and closure the kernel registers the undo blob
  (src/pl-undo.jl:79, rank -4), as pl-setup.c:146-155 does (initTries, initZip, initUndo, initWrap). The zipper registration (initZip, pl-zip.c:1480)
  is NOT in the kernel at this SHA, so the pin's order is record, clause, trie, zipper, undo, closure and the kernel's is record, clause, trie, undo,
  closure. FIX (test only, D-0083): add `LK.undo_blob` to the chain (`ureg.rank == treg.rank - 1 && wreg.rank == ureg.rank - 1`), a comment that the
  zipper's entry goes between trie and undo when initZip lands (WAITS-FOR-LINE: the zip line, owner ZIP/zipper).

### GREEN (rc 0, no Test Failed, no Error During, no SKIP), PASS total over three types
test_tabling_variant_swipl 492 (18m40s) | test_det_ssu 363 | test_det 786 | test_meta_predicate 201 | test_wrap 387 | test_ssu 354 | test_ssu_compile 174 |
test_assert 114 | test_tabling_state 318 | test_boot_image 240 | test_body_code 2586 | test_call_operands 105 | test_attvar_wakeup 1167 | test_autoload_trap 336 |
test_rules 433 | test_top1_pro 315 | test_top1b 348 | test_procedures 150 | test_reload_blocks 789 | test_cont_boot 234 | test_tabling_worklist 249 |
test_tabling_answers 423 | test_tabling_wfs 207 | test_trie_gen 471 | test_set_flag 351 | test_lb7 894 | test_tabling_a1_guard 63 | test_tabling_s5_guard 15 |
test_tabling_tb4rows2 258 | test_tabling_tb4rows 249 | test_retract 282 | test_retractall 15 | test_clause 213 | test_event 300 | test_update_view_gc 18 |
test_trail_words 45 | test_write_cells 372 + 9 broken (at27 x3 types: `open_null_stream/1`, owner STREAMS-A, the file's own @test_broken) |
test_format_predicate 195 | test_format 474 | test_cont_run 276 | test_metacall_control 351 | test_softcut 138 | test_catch 159 | test_cleanup 3492 | test_metacall 1641 |
test_at_body 282 | test_bagof 669 | test_between 138 | test_colon_body 171 | test_context_module 165 | test_copyterm 174 | test_current_op 498 | test_findall 375 |
test_firstvar 111 | test_sortlist 6168 (8m09s) | test_slot_words 78 | test_builtins 216 | test_query 386 | test_analyse_variables 93 | test_bootpred3 374 |
test_nth_clause 624 | test_source_file 519 | test_load 309 | test_compiler_warnings 87 | test_index_context 21 | test_index 99 | test_declare_destroy 240 |
test_debug_flag 351 | test_firstboot 90 | test_atom_table 1138 | test_export_import 330 | test_pr1 678 | test_jit 24129 | test_top1_prompt 150 | test_lb5b_prompt 102 |
test_trie_attvar 147.
(paths: group order of first_run_files.txt; db/ files test_assert test_boot_image test_procedures test_reload_blocks test_retract* test_clause
test_update_view_gc test_nth_clause test_source_file test_clause_ref test_index* test_jit; compile/ test_ssu_compile test_body_code test_call_operands
test_analyse_variables test_compiler_warnings; foreign/ test_builtins test_query; files/ test_load; the rest core_lang/.)
Slow files: test_tabling_variant 18m40s, test_reload_blocks 8m35s, test_sortlist 8m09s, test_attvar_wakeup 5m53s, test_body_code 5m37s.

## THE GREEN SET at this SHA
Everything of the first_run_report.md "pass on three types" lists + the committed fixes (idg, idg_sets, supervisor excepted: 8 ENGINE rows, transaction_nested,
tb7rows, tb4_tb5*, tb5rows, tb6rows, tb9rows, w2, abolish, events, restraint_wb, sdg, transaction_wb, trie*, tb8rows) + the 76 GREEN files above
+ test_prolog_flag_swipl.jl (pin1_i1_i2.md) + the E1 files (e1_getter.md: monotonic 39/39, mono_subsumptive 129, mono_reuse 75, monotonic_upstream 99).
Not green at this SHA (kept for wip/tab1-late or a fix): the first_run_report.md ENGINE files (trie_attvars, answer_discard, trie_children, trie_index,
incr_dyn_nodes, table_statistics, tabling_upstream_b t_tt22, trie_upstream :616, supervisor 8 rows), test_transaction_swipl.jl (this file's table), (the three D-0083 files are green since their fixes).

## NOT RUN / TO DO (next agent)
1. DONE (2933e730 893902f0 b07cc1b1; fmt clean, check PASS, pkgtest_way passed on the three files). Was: fix the three D-0083 test rows named above (edit one file, run on three types, commit `FIXED: <file>: ...`; stage and commit in separate Bash calls);
   run test_module_path.jl, test_module_swipl.jl, test_clause_ref_swipl.jl on three types and grep logs for `SKIP|Warning|Test Failed|Error During`.
2. `tools/warm.sh fmt`, then `tools/warm.sh check` ONCE, pkgtest_way on each changed test file (`tools/pkgtest_way.sh <file>`, one at a time).
3. Files of the 135 NOT run by this agent: test_tabling_monotonic_swipl.jl (21 min; run by the E1 agent: 39/39 green, e1_getter.md) and nothing else:
   every other name of first_run_files.txt is either in the reports' run lists or in the 80 above. The reports' per-file results were measured at 99e5975c / earlier
   commits of wip/tab1-mono, not re-run at 5bdaa2d9: a re-run of the "green" upstream files at the gate SHA is still owed if the dispatcher wants "green AT the gate SHA".
4. The lane-2 daemon (unit logickernel-warm-78a7647c) is up and idle since ~01:30 UTC 2026-11-16 (exits after 3600 s idle).
