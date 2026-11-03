# ENG3 re-stack agent — state file (Sonnet; worktree ~/code/lk-eng3, local branch gate/eng3b)

Task: re-stack gate/eng3 (a36f4b6, 9 commits on main 9cc76fa) on origin/main f08167f (EV1d landed), cheap gate, fresh pair.

## Step 1: CI of a36f4b6 (read once, ~13:00Z)
- CI 41638646211: queued; Evidence 41638646159: queued; battery 41638629165 (mutants/ENG3, 128-file baseline): in_progress.
  No verdict to read yet. The old pair stays until the dispatcher deletes it.

## Step 2: cherry-pick onto f08167f (gate/eng3b)
- `git cherry-pick b5e5bb6 340b488 dda47fa 5b722ee d4c76d8 2bb1d81 f17ad0d d3f26cf a36f4b6`, no force, authors kept.
- Conflicts: test/static_analysis_manifest.jl (main appended its EV1 block ending without a comma; kept both, comma added,
  ENG3 entries last) and docs/architecture.md (EV1's block and ENG3's block both appended at the end; kept both). src/pl-wam.jl,
  src/pl-fli.jl: no conflict (the query_answers commit 340b488 applied clean). docs/port_inventory.md auto-merged; regenerated below.
- range-diff 9cc76fa..a36f4b6 vs f08167f..gate/eng3b: b5e5bb6=388715d, 340b488=c06f50e, dda47fa=31b763a, 5b722ee=401c87d,
  d4c76d8=8f61216, d3f26cf=0b4025e all `=`; 2bb1d81 (manifest) and f17ad0d (architecture) differ by the conflict resolutions
  only (the manifest commit shows as `<`/`>` pair f2207a3, its context changed); a36f4b6=452eb30 `!` (port_inventory/gate1 context).
  So the src/test commits are unchanged apart from the base (D-0374 item 3b).
- tools/mutants/ENG3.py -> tools/mutants/ENG3b.py (git mv). Anchor check (python3 -I): 11 mutants, every `old` once, ids unique,
  targets exist. Found 4 test files added on main that call the LD forms directly (test_bootpred3_swipl, test_debug_flag_swipl,
  test_event_swipl, test_halt_swipl): added to TLD (D-0238), TARGETS now 132 files.

## Step 1 result (read ~13:20Z): the a36f4b6 battery 41638629165 is RED AT THE BASELINE (audit D-0388)
- Baseline failed: rules_common.jl `exit noload` (include-helper, no @test, in TARGETS by mistake); ENG3-9 same error; ENG3-8 NO VERDICT
  (module init @assert, src/pl-setup.jl:170). ENG3-11 EQUIVALENT accepted by D-0388. CI/Evidence of a36f4b6 queued/in_progress at the read.
- ENG3b.py fixed: helpers rules_common.jl and db/index_testlib.jl (the only files without @test) dropped from TARGETS and every mutant;
  130 targets; ENG3-8 rewritten load-safe (`ld.exception_cells != 0 && new_term_ref(ld)` before the return). Anchor check: bad 0.
- fmt over the 4 committed .jl files: tree unchanged. ENG3-8 in-tree vs test_query.jl: CAUGHT (test_query.jl:74), baselines exit 0.
- ENG3-9 in-tree (test_query.jl + test_local_stack.jl) STARTED, result unread (scratchpad m9.out).
- NOT DONE: cheap gate (check, 3-type files, pins, pkgtest_way), inventory, branch-gate, the ONE commit, push gate/eng3b.

## ENG3-9 (ensureLocalSpace dropped): SURVIVED in-tree against test_query.jl + test_local_stack.jl, then killed
- First run (test_query.jl, test_local_stack.jl): baseline 0, SURVIVED, final baseline 0. Neither file made a reference at the
  stack's end or at the limit.
- New rows in test/core_lang/test_local_stack.jl "term references" (pl-fli.c:503-508 `if ( !ensureLocalSpace(sizeof(word)) ) return 0;`):
  a reference made at lMax grows the stack (== top, lTop top+1, region 2*LOCAL_INITIAL); at the stack limit PL_new_term_ref == 0 and
  the pending ball is error(resource_error(stack), stack_overflow) (the same ball as the file's limit row, D-0040).
  Reference run: 132/132.
- Re-run in-tree (test_local_stack.jl): baseline 0, CAUGHT (Test Failed at test_local_stack.jl:375, the growth row), final baseline 0,
  "1 of 1 caught; 0 blocking". ENG3b.py's ENG3-8/ENG3-9 texts updated with the kill rows. src diff empty after each run (no sentinel left).
- Because test_local_stack.jl changed, its pin 377 moves (new rows x 3 types): re-read the three-type totals below.

## Cheap gate on gate/eng3b (daemon lk-eng3, restarted cold at 12:55Z on the struct change); `warm.sh inventory`: docs/port_inventory.md unchanged, port_check clean (259 files)
- `warm.sh check`: PASS in 171 s. The only Warnings in its log are "Failed to format file ./evidence/F1B/sf_template.jl, ./evidence/F2/push_template.jl"
  (templates outside this step, pre-existing); no SKIP line. Format of test_local_stack.jl: nothing rewritten.
- Three types (reference/alt/alt_interned), one `warm.sh file` call each, `--summary`, all PASS, 0 SKIP/Warning lines in any log:
  test_query.jl 123+121+121 = 365 (as expected); test_catch_swipl.jl 52x3 = 156; test_meta_predicate_swipl.jl 67x3 = 201;
  test_query_answers.jl 30x3 = 90; test_context_module_swipl.jl 55x3 = 165; test_prolog_flag_swipl.jl 460x3 = 1380;
  test_same_term_swipl.jl 42x3 = 126; test_readme_example.jl 12 (reference only: "not term-generic", the warm lane refuses alt types, rc 2, as for every run);
  test_zero_exports.jl 81+79+79 = 239 (UNCHANGED); test_rules_swipl.jl 145+144+144 = 433 (UNCHANGED);
  test_local_stack.jl 132+127+127 = 386 (377 + the 3 new rows x 3 types: the pin MOVES by +9, rows above).
- Reference only: test_type_discipline.jl 33, test_manifest_entries.jl 9, static_analysis_fast.jl 14.
- `tools/pkgtest_way.sh` test/foreign/test_query.jl and test/core_lang/test_local_stack.jl: both passed the way Pkg.test runs them.
- Full test/test_static_analysis.jl NOT rerun: the src diff is the original one (c06f50e = 340b488 per range-diff, no pl-fli.jl conflict);
  cite 4325/4325 at a36f4b6 (gate1.md). The fast static check (14/14) ran on this tree.
