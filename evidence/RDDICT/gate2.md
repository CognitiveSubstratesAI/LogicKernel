# RDDICT gate agent 2 (Sonnet) - state file, updated after each step
Lane clone ~/code/lk-dict, local branch gate/rddict (dac6bf7 + uncommitted working tree). Every warm.sh call needs LOGICKERNEL_WARM_SECOND=1.

## Done
- Step 1: `# UPSTREAM: swipl-devel src/SWI-Prolog.h @ cbf4e1896275` added to src/pl-dict.jl line 3; `warm.sh inventory` rc=0 (port_check clean, 255 files);
  `warm.sh fmt` reformatted src/pl-dict.jl (3 DICT lines wrapped + header); anchor checker: 52 mutants, 0 bad.
- Host rebooted (Windows Update) during the first `inventory` re-run after fmt -> exit 137; daemon killed. EV1 daemon stopped by me (dispatcher order); lk-dict daemon restarted cold.

## Next (order)
daemon up -> inventory re-run -> warm.sh check -> branch-gate (marker) -> ONE commit early -> test rows x3 -> TD/manifest/static -> pkgtest_way -> alloc pins -> crash grep -> rebase on origin/main (9cc76fa) -> push.

## Findings so far
- test_dict_preds_swipl.jl:516 (non-vacuity testset) had a typo: yes-rows end `(a[121,101,115])` (ONE paren), the test wanted `))`. The 12 rows are there (counted in the table). Fixed in the test (never-run DICT file, test typo, not a kernel difference). Also warm.sh fmt rewrote the whole file (never formatted before).
- test_dict_preds_swipl.jl reference: PASS 182/182 (6m31s), live swipl compare ran, no SKIP/Warning.
- Pkg.test-way (via branch-gate preflight) passed: test_read_dict 1380 MiB, test_read 262, test_read_positions 1308, test_read_swipl 524, test_read_term 1224 MiB peaks.
- First branch-gate failed: dict_preds Pkg.test-way (the typo) + "NOT Blue-formatted" same file; both fixed; branch-gate re-run next.
- check PASS after manifest entry for pl_for_dict (LK.pl_for_dict, Tuple{LD,Int,Any,Int}) was added in test/static_analysis_manifest.jl (DICT's pl_for_dict was uncovered).

## Commit + rebase (done)
- branch-gate PASS (4161 s) on the pre-rebase tree; ONE commit 25cb850 (all working-tree fixes). dp rows three types 182x3 PASS (alt 6m14s, alt_interned 6m01s); read_dict 357x3; read_term 71x3; read_positions 47x3; read_swipl 45x3; read.jl 113x3; test_lint_globals 9; test_type_discipline 33 (5m05s). Left to CI by the budget: test_gate_split, test_manifest_entries, test_port_check (I run test_manifest_entries myself).
- Pkg.test-way peaks (MiB): dict_preds 1957, read_dict 1455, read 266, read_positions 1370, read_swipl 524, read_term ~1270 (all clean, no swipl, inert guard).
- origin/main moved to f08167f (EV1 landed). Rebased gate/rddict onto it: conflicts docs/architecture.md (append/append), static_analysis_manifest.jl (comma added), os/pl-prologflag.jl comment (main's F1c wording kept), docs/port_inventory.md (regenerated). range-diff: evidence/RDDICT/rangediff2.txt (23 "=", 4 "!": the architecture block, the manifest entries, pl-read.jl and pl-prologflag.jl commits = exactly the conflicted ones).
- Stale text found after the commit (the absence hook flagged the pre-existing architecture row): pl-dict.jl row and header comment said the reader refuses dict syntax / other dict predicates are not ported; rewritten in the follow-up commit.
