# ENG3 re-stack agent 2 (Sonnet) — gate4: gate/eng3d = gate/eng3b + f00dc63 re-stacked on RDDICT's main a52a43b

Task: gate/eng3c (f00dc63, 11 commits on f08167f) is not a fast-forward from main a52a43b (30 RDDICT commits over f08167f).
Re-stack once under a fresh name (D-0374 item 3), mutant list renamed to ENG3d.py.

## Step 1: rebase onto origin/main a52a43b (worktree ~/code/lk-eng3, `git checkout -b gate/eng3d; git rebase origin/main`, no force)
- Conflicts, two, both append-only at the end of the file (the RDDICT block on main, the ENG3 block of the step): test/static_analysis_manifest.jl
  (main's last entry `build_labeled_subterm` had no trailing comma: comma added, both sides kept, ENG3's two entries last) and docs/architecture.md
  (RDDICT's BOOTPRED-dict section and ENG3's section: both kept, blank line between). docs/port_inventory.md merged without a conflict;
  `warm.sh inventory` rewrote nothing (261 files, port_check clean). No conflict in src/pl-fli.jl, src/pl-wam.jl, src/pl-global.jl (condition (a) of D-0374 item 3 holds).
- `git range-diff f08167f..f00dc63 a52a43b..gate/eng3d` (condition (b)): every src and test commit is `=` (c06f50e=6411227, 31b763a=235adb8, 401c87d=b8f8a14,
  8f61216=b36d157, 0b4025e=fd22892, 452eb30=b350266, 834a856=77fb5b3, f00dc63=363a2d1, 388715d=0882065); the two append-conflict commits differ by the
  resolutions only: f2207a3 (manifest) -> 9891dd3 (shown as a `<`/`>` pair: its context changed), f96a0f1 (architecture) -> 967cd98 (`!`). Raw: gate4_rangediff.txt next to this file.
  src/pl-fli.jl and src/pl-wam.jl diffs of the step are the unchanged hunks (c06f50e = 6411227).

## Step 2: tools/mutants/ENG3b.py -> tools/mutants/ENG3d.py (git mv, in the commit below)
- Anchor check (throwaway `python3 -I`): 11 mutants, ids unique, every `old` occurs exactly once in its file at the rebased tree (the ENG3-8 `old`
  `    return new_term_ref(ld)` once in src/pl-fli.jl), new != old, every target a real file with an @test, TARGETS 132 files without duplicates. Bad: 0.
- Two files that RDDICT added to main call `PL_new_term_ref(` directly: test/core_lang/test_dict_preds_swipl.jl and test/core_lang/test_read_dict_swipl.jl:
  added to TLD (D-0238). The other main changes under test/ (test_read_swipl.jl, test_read.jl, test_read_positions_swipl.jl, test_read_term_swipl.jl) are
  not new callers beyond files already listed or inert for the mutants (the check was: grep -rlE 'PL_new_term_refs?\(' test, compared with TLD: only the two plus the
  two include-helpers rules_common.jl, db/index_testlib.jl, which stay out as in D-0388).
- ENG3-8 as in f00dc63 (the LD form only where the API stub refuses; caught at test_query.jl:223 in the CI-way run, evidence/ENG3/gate3.md); ENG3-11 declared equivalent.

## Step 3: cheap gate (daemon lk-eng3, LOGICKERNEL_WARM_SECOND=1)
- Daemon: started 19:10Z by the first warm.sh call (the lane was stopped before this agent began: session.log shows `signal 15: Terminated` of the previous daemon);
  "loaded from its last cache and revised to the current source". No restart by this agent, no struct-change restart noted.
  First test file paid the cold Revise/compile cost (test_query.jl 10m49s on three types vs ~1-2 min warm).
- `warm.sh fmt`: no changed .jl file. `warm.sh inventory`: docs/port_inventory.md unchanged, port_check clean (261 files), 4m55s.
  `warm.sh check`: PASS in 258 s (format, port_check, manifest 3506 entries, term scopes, meta files, inert guard); the only Warning is the pre-existing
  "Failed to format file ./evidence/F2/push_template.jl" (and F1B's), a template outside the step.
- Three types (one `warm.sh file` call each, reference+alt+alt_interned), all PASS, no SKIP/Warning/Test Failed/Error During line in any log:
  test_query.jl 123+121+121 = 365 (expected 365); test_local_stack.jl 386 (expected 386); test_catch_swipl.jl 156 (expected 156);
  test_meta_predicate_swipl.jl 201 (expected 201); test_query_answers.jl 90 (3 types); test_context_module_swipl.jl 165; test_same_term_swipl.jl 126;
  test_zero_exports.jl 239 (UNCHANGED: the exact-zero @allocated pins hold on all three types, no pin moved); test_type_discipline.jl 33 (reference only).
- The old pair: Evidence 41697208498 of f00dc63 completed success at the one read (19:34Z); CI 41697208439 and the battery 41697206832 in_progress.
