# ENG3 gate agent 2 — state file (Sonnet; worktree ~/code/lk-eng3, local branch gate/eng3)

Lost predecessor (afea1397cd6b376d0) recorded nothing: nothing is treated as verified.

## Step 2: re-base onto origin/main 9cc76fa (done)
- Discarded the lost agent's staged docs/port_inventory.md change; regenerate with `warm.sh inventory` later.
- `git rebase origin/main`: 8 commits. Conflicts: test/static_analysis_manifest.jl (main's HALT1/F1c entries ended the list
  without a trailing comma; kept both, added the comma) and docs/architecture.md (two appended blocks: kept HALT1's, then ENG3's).
- range-diff vs a8c9f3d: commits 1-5 and 8 equal (b5e5bb6 340b488 dda47fa 5b722ee d4c76d8 d3f26cf); the manifest commit
  (97cddc1 -> 2bb1d81) and the architecture commit (b2e06b5 -> f17ad0d) differ by the conflict resolutions only.
- New head before gate work: d3f26cf.
- mutants checker (python3 -I, scratchpad chk.py) at d3f26cf, before fmt: 11 mutants, every `old` once, ids unique, old != new,
  all targets exist, module-level TARGETS = 128 files.

## Log
- 08:57Z daemon started (second slice, pid 15126, unit logickernel-warm-e20f7625), cold compile ~10 min.
- test/foreign/test_query.jl reference: PASS 123/123 in 665 s (first compile of the change; no typo-level fix needed). No
  SKIP/Warning lines in the summary log. Probe: `@test_throws ErrorException("A") error("B")` FAILS (Expected/Thrown), so
  an ErrorException instance compares the message: the new rows can fail, no try/catch row needed.
- fmt: `warm.sh fmt` sees no changed file on a committed branch; formatted the four committed .jl files through send:
  0 rewritten, so tools/mutants/ENG3.py anchors stand (python3 -I checker: 11 mutants, all `old` once, 128-file TARGETS, bad 0).
- `warm.sh inventory`: pl-fli.c row 85/71 -> 87/72 (the two new stubs), port_check clean (256 files).
- 09:17Z and 10:00Z host freezes killed the daemons; the first `warm.sh check` also found "DAEMON LEFTOVERS" (the daemon had been
  started before the rebase) and restarted/refused; daemon restarted cold at ~10:25Z (second slice, pid 75482). The commit hook
  refuses a commit on gate/eng3 without the branch-gate marker (BLOCKED: no test evidence for lk-eng3), so gate1.md and
  docs/port_inventory.md are STAGED, committed after branch-gate.
- `warm.sh check` (fresh daemon): PASS in 459 s (format, port_check, manifest, term scopes, meta files, inert guard). An earlier
  check run's log also read "pkgtest_way: test_query.jl peak 2252 MiB (cap 3G, oom_kill 0) ... Pkg.test-way run clean".
- Three-type runs (reference/alt/alt_interned, one `warm.sh file` call per file, `--summary`), all PASS, 0 SKIP/Warning lines:
  test/foreign/test_query.jl 365 (ref 123, alt 121, alt_interned 121; main had 347: +6 rows per type = 4 in the det-last-answer
  testset [_Q_NO_ENV_REFS, LD ref at lTop, LD refs at lTop, r2/lTop] + 2 in the exception testset [environment_frame != 0, stub
  after PL_open_foreign_frame above the query]; 347 + 18 = 365),
  test_meta_predicate_swipl.jl 201, test_catch_swipl.jl 156 (the cp5 row is in the file and passes; no failure to compare with main), test_query_answers.jl 90,
  test_readme_example.jl 12, test_context_module_swipl.jl 165, test_prolog_flag_swipl.jl 1380, test_same_term_swipl.jl 126,
  test_local_stack.jl 377 (pin UNCHANGED), test_type_discipline.jl 33, test_manifest_entries.jl 9, static_analysis_fast.jl 14.
- `tools/pkgtest_way.sh test/foreign/test_query.jl`: passed the way Pkg.test runs it (peak 1254 MiB, cap 3G, oom_kill 0).
- Pins (three types, one `warm.sh file` call each): test_zero_exports.jl 239/239, test_rules_swipl.jl 433/433,
  test_local_stack.jl 377/377: UNCHANGED, as expected (the check is a branch, not an allocation). test_query.jl 347 -> 365
  (+18 = 6 new rows x 3 types, itemised above).
- test/test_static_analysis.jl (JET + Aqua + AllocCheck, reference) started ~11:20Z; result below.
- test/test_static_analysis.jl (JET + Aqua + AllocCheck, reference): 4325/4325 PASS in 67m21s inside the daemon (the client wrapper
  hit its own 3600 s timeout first and printed "TIMEOUT"; the daemon finished at ~12:25Z and out.txt carries the verdict).
  Both daemons were busy (EV1's static run beside it), so the wall time is longer than the ~50 min expected. No AllocCheck alarm
  on the new-term-ref path (the stubs and LD forms are in the manifest, test_manifest_entries 9/9).
