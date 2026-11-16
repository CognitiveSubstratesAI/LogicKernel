# TAB1-GATE-SHA step 5: three-type run of the gate tree (wip/tab1-gate, tree of 5d2bf005)

Daemon: lane-2 warm daemon (unit logickernel-warm-78a7647c), `LOGICKERNEL_WARM_SECOND=1 WARM_TIMEOUT_S=9000 tools/warm.sh file <f>`, one file at a time, 08:09-08:32 (23 min for 69 files), all rc 0, no daemon death. Raw TSV: evidence/TAB1/gate_sha_run.tsv. Logs kept in the session scratchpad.

Counts are Pass/Fail/Error/Broken per type (ref = reference, alt, ali = alt_interned); the Test Summary shows a column only when non-zero, so Fail=Error=0 everywhere unless stated. Warnings = lines matching `SKIP|Warning|Test Failed|Error During`.

## Rerun (69 files)

| file | rerun | ref P/F/E/B | alt P/F/E/B | ali P/F/E/B | flagged lines | rss |
|---|---|---|---|---|---|---|
| test/core_lang/test_tabling_a1_guard.jl | rerun | 21/0/0/0 | 21/0/0/0 | 21/0/0/0 | 0 | rss 3.2 GB |
| test/core_lang/test_tabling_abolish_bulk_upstream_swipl.jl | rerun | 43/0/0/4 | 43/0/0/4 | 43/0/0/4 | 0 | rss 3.2 GB |
| test/core_lang/test_tabling_abolish_delay_deps_upstream_swipl.jl | rerun | 19/0/0/0 | 19/0/0/0 | 19/0/0/0 | 0 | rss 3.2 GB |
| test/core_lang/test_tabling_abolish_depending_table_upstream_swipl.jl | rerun | 17/0/0/0 | 17/0/0/0 | 17/0/0/0 | 0 | rss 3.2 GB |
| test/core_lang/test_tabling_abolish_swipl.jl | rerun | 266/0/0/0 | 266/0/0/0 | 266/0/0/0 | 0 | rss 3.2 GB |
| test/core_lang/test_tabling_abstract_completion_upstream_swipl.jl | rerun | 35/0/0/0 | 35/0/0/0 | 35/0/0/0 | 0 | rss 3.2 GB |
| test/core_lang/test_tabling_answer_insert_upstream_swipl.jl | rerun | 35/0/0/0 | 35/0/0/0 | 35/0/0/0 | 105 | rss 3.2 GB |
| test/core_lang/test_tabling_answers_swipl.jl | rerun | 141/0/0/0 | 141/0/0/0 | 141/0/0/0 | 0 | rss 3.2 GB |
| test/core_lang/test_tabling_answer_subsumption_upstream_swipl.jl | rerun | 17/0/0/0 | 17/0/0/0 | 17/0/0/0 | 15 | rss 3.2 GB |
| test/core_lang/test_tabling_delay_after_simplify_upstream_swipl.jl | rerun | 17/0/0/0 | 17/0/0/0 | 17/0/0/0 | 0 | rss 3.2 GB |
| test/core_lang/test_tabling_drop_intermediate_upstream_swipl.jl | rerun | 21/0/0/0 | 21/0/0/0 | 21/0/0/0 | 0 | rss 3.2 GB |
| test/core_lang/test_tabling_engine_finding_cleanup_throw_swipl.jl | rerun | 14/0/0/0 | 14/0/0/0 | 14/0/0/0 | 0 | rss 3.2 GB |
| test/core_lang/test_tabling_events_swipl.jl | rerun | 47/0/0/0 | 47/0/0/0 | 47/0/0/0 | 0 | rss 3.2 GB |
| test/core_lang/test_tabling_idg_sets_upstream_swipl.jl | rerun | 76/0/0/7 | 76/0/0/7 | 76/0/0/7 | 0 | rss 3.2 GB |
| test/core_lang/test_tabling_idg_swipl.jl | rerun | 291/0/0/0 | 291/0/0/0 | 291/0/0/0 | 0 | rss 3.2 GB |
| test/core_lang/test_tabling_incr_answer_subsumption_upstream_swipl.jl | rerun | 31/0/0/0 | 31/0/0/0 | 31/0/0/0 | 0 | rss 3.2 GB |
| test/core_lang/test_tabling_incr_dyn_nodes_upstream_swipl.jl | rerun | 21/0/0/0 | 21/0/0/0 | 21/0/0/0 | 0 | rss 3.2 GB |
| test/core_lang/test_tabling_incr_retractall_upstream_swipl.jl | rerun | 23/0/0/0 | 23/0/0/0 | 23/0/0/0 | 0 | rss 3.2 GB |
| test/core_lang/test_tabling_incr_subsumptive_upstream_swipl.jl | rerun | 21/0/0/0 | 21/0/0/0 | 21/0/0/0 | 0 | rss 3.2 GB |
| test/core_lang/test_tabling_min_swipl.jl | rerun | 153/0/0/0 | 153/0/0/0 | 153/0/0/0 | 0 | rss 3.2 GB |
| test/core_lang/test_tabling_mono_reuse_upstream_swipl.jl | rerun | 25/0/0/0 | 25/0/0/0 | 25/0/0/0 | 0 | rss 3.2 GB |
| test/core_lang/test_tabling_mono_subsumptive_upstream_swipl.jl | rerun | 43/0/0/0 | 43/0/0/0 | 43/0/0/0 | 0 | rss 3.2 GB |
| test/core_lang/test_tabling_monotonic_lazy_upstream_swipl.jl | rerun | 47/0/0/0 | 47/0/0/0 | 47/0/0/0 | 0 | rss 3.2 GB |
| test/core_lang/test_tabling_monotonic_upstream_swipl.jl | rerun | 33/0/0/0 | 33/0/0/0 | 33/0/0/0 | 0 | rss 3.3 GB |
| test/core_lang/test_tabling_reeval_exceptions_upstream_swipl.jl | rerun | 15/0/0/0 | 15/0/0/0 | 15/0/0/0 | 0 | rss 3.2 GB |
| test/core_lang/test_tabling_reeval_upstream_swipl.jl | rerun | 29/0/0/0 | 29/0/0/0 | 29/0/0/0 | 51 | rss 3.2 GB |
| test/core_lang/test_tabling_reeval_wfs_upstream_swipl.jl | rerun | 25/0/0/0 | 25/0/0/0 | 25/0/0/0 | 0 | rss 3.2 GB |
| test/core_lang/test_tabling_restraint_wb_swipl.jl | rerun | 55/0/0/0 | 55/0/0/0 | 55/0/0/0 | 0 | rss 3.2 GB |
| test/core_lang/test_tabling_s5_guard.jl | rerun | 5/0/0/0 | 5/0/0/0 | 5/0/0/0 | 0 | rss 3.2 GB |
| test/core_lang/test_tabling_sdg_swipl.jl | rerun | 206/0/0/0 | 206/0/0/0 | 206/0/0/0 | 0 | rss 3.2 GB |
| test/core_lang/test_tabling_simplify_completed_upstream_swipl.jl | rerun | 15/0/0/0 | 15/0/0/0 | 15/0/0/0 | 0 | rss 3.2 GB |
| test/core_lang/test_tabling_state_swipl.jl | rerun | 106/0/0/0 | 106/0/0/0 | 106/0/0/0 | 0 | rss 3.2 GB |
| test/core_lang/test_tabling_tabled_shortest_path_upstream_swipl.jl | rerun | 15/0/0/0 | 15/0/0/0 | 15/0/0/0 | 0 | rss 3.2 GB |
| test/core_lang/test_tabling_tabling_upstream_a_swipl.jl | rerun | 37/0/0/0 | 37/0/0/0 | 37/0/0/0 | 0 | rss 3.2 GB |
| test/core_lang/test_tabling_tabling_upstream_c_swipl.jl | rerun | 37/0/0/0 | 37/0/0/0 | 37/0/0/0 | 0 | rss 3.2 GB |
| test/core_lang/test_tabling_tb4rows2_swipl.jl | rerun | 86/0/0/0 | 86/0/0/0 | 86/0/0/0 | 0 | rss 3.2 GB |
| test/core_lang/test_tabling_tb4rows_swipl.jl | rerun | 83/0/0/0 | 83/0/0/0 | 83/0/0/0 | 0 | rss 3.2 GB |
| test/core_lang/test_tabling_tb4_tb5_guard_swipl.jl | rerun | 25/0/0/0 | 25/0/0/0 | 25/0/0/0 | 0 | rss 3.2 GB |
| test/core_lang/test_tabling_tb4_tb5_swipl.jl | rerun | 73/0/0/0 | 73/0/0/0 | 73/0/0/0 | 0 | rss 3.2 GB |
| test/core_lang/test_tabling_tb5rows_swipl.jl | rerun | 155/0/0/0 | 155/0/0/0 | 155/0/0/0 | 0 | rss 3.2 GB |
| test/core_lang/test_tabling_tb6rows_swipl.jl | rerun | 373/0/0/0 | 373/0/0/0 | 373/0/0/0 | 0 | rss 3.2 GB |
| test/core_lang/test_tabling_tb7rows_swipl.jl | rerun | 211/0/0/0 | 211/0/0/0 | 211/0/0/0 | 0 | rss 3.2 GB |
| test/core_lang/test_tabling_tb8rows_swipl.jl | rerun | 126/0/0/0 | 126/0/0/0 | 126/0/0/0 | 12 | rss 3.2 GB |
| test/core_lang/test_tabling_tb9rows_swipl.jl | rerun | 57/0/0/0 | 57/0/0/0 | 57/0/0/0 | 0 | rss 3.2 GB |
| test/core_lang/test_tabling_tbl_sdg_upstream_swipl.jl | rerun | 48/0/0/0 | 48/0/0/0 | 48/0/0/0 | 0 | rss 3.2 GB |
| test/core_lang/test_tabling_transaction_nested_swipl.jl | rerun | 131/0/0/0 | 131/0/0/0 | 131/0/0/0 | 0 | rss 3.2 GB |
| test/core_lang/test_tabling_transaction_swipl.jl | rerun | 102/0/0/0 | 102/0/0/0 | 102/0/0/0 | 0 | rss 3.2 GB |
| test/core_lang/test_tabling_transaction_wb_swipl.jl | rerun | 139/0/0/0 | 139/0/0/0 | 139/0/0/0 | 0 | rss 3.2 GB |
| test/core_lang/test_tabling_variant_swipl.jl | rerun | 164/0/0/0 | 164/0/0/0 | 164/0/0/0 | 0 | rss 3.2 GB |
| test/core_lang/test_tabling_w2_swipl.jl | rerun | 44/0/0/0 | 44/0/0/0 | 44/0/0/0 | 0 | rss 3.2 GB |
| test/core_lang/test_tabling_wfs_swipl.jl | rerun | 69/0/0/0 | 69/0/0/0 | 69/0/0/0 | 0 | rss 3.2 GB |
| test/core_lang/test_tabling_wfs_upstream_swipl.jl | rerun | 29/0/0/0 | 29/0/0/0 | 29/0/0/0 | 12 | rss 3.2 GB |
| test/core_lang/test_tabling_worklist_swipl.jl | rerun | 83/0/0/0 | 83/0/0/0 | 83/0/0/0 | 0 | rss 3.2 GB |
| test/core_lang/test_trie_attvar_swipl.jl | rerun | 49/0/0/0 | 49/0/0/0 | 49/0/0/0 | 0 | rss 3.2 GB |
| test/core_lang/test_trie_compiled_swipl.jl | rerun | 114/0/0/0 | 114/0/0/0 | 114/0/0/0 | 0 | rss 3.2 GB |
| test/core_lang/test_trie_gen_swipl.jl | rerun | 200/0/0/0 | 200/0/0/0 | 200/0/0/0 | 0 | rss 3.2 GB |
| test/core_lang/test_trie_preds_swipl.jl | rerun | 194/0/0/0 | 194/0/0/0 | 194/0/0/0 | 0 | rss 3.2 GB |
| test/core_lang/test_trie_property_idg_swipl.jl | rerun | 21/0/0/0 | 21/0/0/0 | 21/0/0/0 | 0 | rss 3.2 GB |
| test/core_lang/test_trie_swipl.jl | rerun | 380/0/0/0 | 380/0/0/0 | 380/0/0/0 | 0 | rss 3.2 GB |
| test/core_lang/test_module_path.jl | rerun | 62/0/0/0 | 62/0/0/0 | 62/0/0/0 | 0 | rss 3.2 GB |
| test/core_lang/test_module_swipl.jl | rerun | 96/0/0/0 | 96/0/0/0 | 96/0/0/0 | 0 | rss 3.2 GB |
| test/core_lang/test_numbervars_cells.jl | rerun | 62/0/0/0 | 62/0/0/0 | 62/0/0/0 | 0 | rss 3.2 GB |
| test/db/test_clause_ref_swipl.jl | rerun | 234/0/0/0 | 234/0/0/0 | 234/0/0/0 | 36 | rss 3.2 GB |
| test/db/test_boot_image_swipl.jl | rerun | 80/0/0/0 | 80/0/0/0 | 80/0/0/0 | 0 | rss 3.2 GB |
| test/db/test_boot_clauses_swipl.jl | rerun | 13919/0/0/0 | 13919/0/0/0 | 13919/0/0/0 | 0 | rss 3.3 GB |
| test/files/test_load_swipl.jl | rerun | 103/0/0/0 | 103/0/0/0 | 103/0/0/0 | 6 | rss 3.3 GB |
| test/test_r2_status.jl | rerun | 119/0/0/0 (one type, no impl loop) | - | - | 0 | rss 3.3 GB |
| test/test_type_discipline.jl | rerun | 45/0/0/0 (one type, no impl loop) | - | - | 0 | rss 3.3 GB |
| test/core_lang/test_tabling_monotonic_swipl.jl | rerun | 13/0/0/0 | 13/0/0/0 | 13/0/0/0 | 0 | rss 3.3 GB |

## Reused (15 files; gate blob == ancestor blob, verified by `git rev-parse HEAD:<f>` equals `<sha>:<f>`)

| file | status vs origin/main | ancestor SHA | blob |
|---|---|---|---|
| test/compile/test_body_code_swipl.jl | M | 5bdaa2d9 | c02b698aa479f5b562fdc7f5accbd55e654971db |
| test/core_lang/test_attvar_words.jl | M | 5bdaa2d9 | fc3e2f36e9fbd5f7acda03c74bb4ba3518cc2f4d |
| test/core_lang/test_cont_boot_swipl.jl | M | 5bdaa2d9 | c8f71242c631a69d3908138cd516b382f7ae8cf7 |
| test/core_lang/test_det_ssu_swipl.jl | A | 5bdaa2d9 | 6f1b4d203ddfb89f8532be806eea0e33eb89bbdc |
| test/core_lang/test_format_predicate_swipl.jl | A | 5bdaa2d9 | 0b707567ee934bdbffe954e5642bdd50cd59e559 |
| test/core_lang/test_format_swipl.jl | M | 5bdaa2d9 | 6bd2b378c70eed78544157ea4f59cbc5c8ce8b2c |
| test/core_lang/test_lb7_swipl.jl | M | 5bdaa2d9 | 9af02f5a5e9a9ea16fe95ff805517dedf2dc5e34 |
| test/core_lang/test_local_stack.jl | M | 5bdaa2d9 | d8580d35ca1d923b9a298f2e6c8f8469135088c1 |
| test/core_lang/test_mark_bar.jl | M | 5bdaa2d9 | 5a9c5d190befd99641a4244c936da71302f5daff |
| test/core_lang/test_prolog_flag_swipl.jl | M | 5bdaa2d9 | fa40e62c2a827aeab8498b209f6923ff6e27d018 |
| test/core_lang/test_set_flag_swipl.jl | M | 5bdaa2d9 | 403217d5fe7aea1c6acf7e3290fae746d3947e5f |
| test/core_lang/test_write_cells.jl | M | 5bdaa2d9 | 75df5cf0c0b6be3e86a5162f7b883ac8276613a3 |
| test/db/test_reload_blocks_swipl.jl | M | 5bdaa2d9 | 6ee1954d5e2f137879219a9c236612003af4bc69 |
| test/files/test_expand_user_swipl.jl | A | 5bdaa2d9 | 9aa3a3ba7211d519c5c66eedb229da776e22b50b |
| test/term_under_test.jl | M | 5bdaa2d9 | d63acdfe2552b8c64826aa711f182554c2fcc107 |

## Notes on the rerun table

- Red files: none (69 of 69 rc 0, Fail=0, Error=0 everywhere). Broken (the files' own `@test_broken` pins): test_tabling_abolish_bulk_upstream_swipl.jl 4 per type, test_tabling_idg_sets_upstream_swipl.jl 7 per type; no other file shows a Broken column.
- test_r2_status.jl and test_type_discipline.jl run once (they carry no per-type loop; test_type_discipline.jl checks the three types inside itself).
- test_tabling_monotonic_swipl.jl ran LAST as asked and took 5 s (13 rows per type, no env gate in the file); the "about 21 min" figure of the brief does not apply to the warm run (it is the Pkg.test-way estimate).
- Daemon rss: 3.2 GB before and after every file, 3.3 GB at most (cap 6 GB).
- The 15 reused files below changed over origin/main but their gate blob equals the blob of 5bdaa2d9 (the tree of the 76-green gate_list); src differs from 5bdaa2d9 only in pl-trie.jl (E4) and the '$run_undo' creation point (36f08764: pl-undo.jl, pl-ext.jl, pl-global.jl, pl-setup.jl). None of the 15 names a trie or undo-hook row; this reuse is the step-4 note's judgement, not re-measured here.

## SKIP / Warning grep: every flagged line classified

Julia-side warnings (`┌ Warning`, `┌ Error`) and `SKIP`: none in any of the 69 logs. All flagged lines are Prolog messages printed by the test programs through the kernel's message system:

| file | flagged | class |
|---|---|---|
| test_tabling_answer_insert_upstream_swipl.jl | 105 | Prolog: load warnings of the upstream program (clauses of test/1,2 not together, discontiguous) x3 types |
| test_tabling_answer_subsumption_upstream_swipl.jl | 15 | Prolog: discontiguous warning, pu_answer_subsumption:test/2 |
| test_tabling_reeval_upstream_swipl.jl | 51 | Prolog: singleton variables / singleton in branch, discontiguous pu_tabling_reeval:test/2 |
| test_tabling_tb8rows_swipl.jl | 12 | Prolog: `Trapped tripwire max_table_subgoal_size` (the rows set the tripwire on purpose) |
| test_tabling_wfs_upstream_swipl.jl | 12 | Prolog: library(dialect/xsb) loads print `Goal (directive) failed: use_module(library(filesex))` and `use_module(library(time))` (x3 types each); the file passes 87/87 per type |
| test/db/test_clause_ref_swipl.jl | 36 | Prolog: `Singleton variables` warnings of the loaded program |
| test/files/test_load_swipl.jl | 6 | Prolog: `Redefined static procedure q/1` (the reload rows) |

The wfs_upstream directive failures are the only line class that names a missing library in the kernel; whether earlier runs of the file printed them was not compared here.
