# CISTATUS (audit D-0262) - handoff

State (2026-10-31): wip/cistatus off 09c9f07, edits uncommitted until the gate order below is done.

- tools/ci_status.sh: option (a). A workflow_dispatch run whose job `Plan` concluded `failure` and whose other
  jobs (except `Verdict table`) are all `skipped` is no verdict (printed, marked "dispatch failed at Plan").
  Option (b) rejected: the runs API carries no dispatch inputs. Unreadable jobs, a push-triggered run, a failed
  Baseline/mutant job or a red Verdict table with a green Plan stay RED. `api_get` factored out; `--api-get URL`
  lets the python fetch `jobs_url`.
- tools/mutate_ci.py: `load` names the PATH form when the list is not a file; `collect` says so when COUNT is empty.
- test/test_gate_split.jl: testset "a dispatch that failed at its Plan step is no verdict (CISTATUS)" (10 cases);
  test file is not term-generic, reference run alone: 686/686.

Gate progress (all PASS, on the uncommitted tree, 2026-10-31): fmt; test_gate_split.jl 686/686 (reference, not term-generic);
check; test_type_discipline.jl 33/33; tools/pkgtest_way.sh test/test_gate_split.jl (peak 763 MiB, passed); crash-term grep over the
diff: none; branch-gate PASS in 762s (marker recorded).

STOP (hook block, tools/githooks/commit-msg, exact message):
  commit-msg: REFUSED - CI-Fix names 09c9f0715768c51265b4a2f459a40bcea9a9fb1e, whose CI is not RED (tools/ci_status.sh exit 0:
  0 green, 3 no verdict yet, 2 unreadable) - there is nothing to declare a fix for
Cause: the hook runs the WORKING-TREE tools/ci_status.sh on HEAD (09c9f07); the fixed script ignores the failed-Plan dispatches, so
09c9f07 reads green and the hook refuses the trailer. The hook also wants .warm/CI_FIX == HEAD (LOGICKERNEL_CI_FIX=<sha> during the
gates), which was not set. Nothing committed; the four files are staged on wip/cistatus.

Decision (dispatcher): commit WITHOUT the CI-Fix trailer (the fixed script reads 09c9f07 green; departure from D-0262 item 2 recorded
in the A-entry). Checked: `tools/ci_status.sh 09c9f07...` exit 0 against the real API; the three Plan-failed dispatches
(41124826803, 41124901359, 41124983027) print "(dispatch failed at Plan: no verdict)", the three later batteries are success.
`_ci_gate` (tools/lib_evidence.sh): rc 0 -> "the previous push is green", passes.
