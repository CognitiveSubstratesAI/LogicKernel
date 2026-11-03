# EV1 gate agent 3 — state (forced hand-back at the 150k cap)

Lane ~/code/lk-ev1. Local branch `gate/ev1c` (made from wip/ev1b; the pre-push hook REFUSES a `wip/` ref, so pushes go from gate/ev1c).
HEAD 3ca2a1c0e39e, rebased onto origin/main c4c34fd (was dd93b68; RD1 landed in between; conflicts in docs/architecture.md and
test/static_analysis_manifest.jl resolved keeping both sides, docs/port_inventory.md regenerated). NOTHING PUSHED YET.

## UNCOMMITTED, STAGED (commit first; the test marker is recorded for exactly this tree)
`git status`: M src/pl-event.jl, test/static_analysis_manifest.jl, tools/mutants/EV1c.py (all staged). `tools/warm.sh branch-gate` PASSED
(511s) on this staged tree and recorded the marker itself (marker is ≤30 min old when this file is written; if the commit hook says
"no test evidence" or stale, rerun `tools/warm.sh branch-gate` (about 9 min) and commit; never write a marker). The commit message is
ready in /tmp/claude-1000/-home-shivaji1012-code-CognitiveSubstratesAI/b3da48ca-983a-498f-90ba-39658d0c6276/scratchpad/ev1_msg6.txt
(`git commit -F <file>`, its own call; a call that contains `git commit` must not run anything else). Content of that commit:
the fast static pre-check (JET report_package) found 10 possible errors in the event stack; fixed:
 * REAL DEFECT: the break events' first value was `:true` / `:false`, which Julia reads as the Bool -> `Symbol("true")` / `Symbol("false")`
   (src/pl-event.jl, PL_call_event_hook_va; unreachable until DBG1 raises break events, so no row reached it).
 * `put_fastheap` / `free_fastheap` got `ev.closure` re-read after the Nothing test -> a local (`clo`).
 * `args[i]::X` assertions on the one caller's tuple -> `event_arg(X, args, i)` (isa check, ArgumentError); manifest entries x2.
 JET after the fix: static_analysis_fast 14/14 (8m20s). test_event_swipl 99 x3 and test_bootpred3 130/131/131 after the fix.
EV1c.py: 3 anchors (U3, C2, C6) re-fitted to the new text, C8's cite is src/pl-event.jl:689; both lists pass the anchor check
(EV1c 51, BOOTPREDSUB 35, 0 bad; throwaway checker .warm/ev1chk.py in the lane clone, run `python3 -I .warm/ev1chk.py <list>`).

NOTE: this file itself was rewritten AFTER the branch-gate, so it is an extra unstaged change; `git add` it with the others. If the commit hook
refuses on the tree fingerprint, rerun `tools/warm.sh branch-gate` (about 9 min) and commit; never a marker by hand.

## Committed on gate/ev1c (rebased SHAs; the rebase was done by plain `git rebase origin/main`, no force)
12f2f97-ish bp3v15 shape compare; 5dcc316 port markers (inventory port_check clean, 256 files); 0929c46 EV1c rename + C8/C9/C10; 3ca2a1c bp3v15 cites its
recorded owner (see below) + inventory regenerated after the rebase + this file. Earlier: the staged work of gate agent 2 (NOT LISTED rows
ev1g02/ev1u18/ev1p20 with swipl 10.1.19 pins, mutants EV1-N1..N3, `==` genericity fix with event_atom_is / event_name_is, fmt of 18 files).

## bp3v15 ruling and audit D-0378 item 4 (cite in the gate entry)
Recorded owner of the type dependence: src/pl-termhash.jl file-wide DIVERGES 1 ("ATOMIC DATA": an atom contributes the term type's
`sym_hash`, so the digest VALUES are not swipl's) and the pl-termhash.jl row of docs/architecture.md ("so the digests ... are not SWI's
values"); the `sym_hash` contract is src/term_interface.jl:90 (same in every process, per term type). Honest note for the auditor: DIVERGES 1
said the values are not swipl's but did not literally say they differ BETWEEN term types; this agent added that sentence to DIVERGES 1
(comment only, src/pl-termhash.jl) in 3ca2a1c. The test (test/core_lang/test_bootpred3_swipl.jl `_b3_digest_shape`) cites DIVERGES 1.
Guard able to fail: regex mutated to 39 codes -> 2 failures on alt. If the audit does not accept, revert to a type-keyed pin.

## Test results (three types, SKIP/Warning lines read; none found except the known "left to CI: test_compiler_warnings_swipl.jl" budget line)
test_bootpred3 130/131/131; test_event_swipl 99 x3 (before and after the JET fix); callers x3: test_pr1_swipl 226, test_update_view_gc 6,
test_jit 8043, test_index_swipl 33, test_declare_destroy_swipl 79, test_hash 22. test_type_discipline 33/33 (twice: 3m13s, and inside the
branch-gate). static_analysis_fast 14/14 after the fix (13/14 before: the 10 JET reports). `warm.sh check` PASS (port_check clean 256 files,
manifest 3447 entries). `warm.sh inventory` clean (256 files). branch-gate PASS.

## LEFT TO DO (in order)
1. Commit the staged JET fix (above). Stage/commit in two calls.
2. `tools/warm.sh file test/static_analysis.jl` is NOT run yet (the full JET+Aqua+AllocCheck file; test/test_static_analysis.jl in the brief) and
   `test/test_manifest_entries.jl` NOT run yet; ONE call each (long). static_analysis_fast is green.
3. `tools/pkgtest_way.sh test/core_lang/test_event_swipl.jl`, then test_bootpred3_swipl.jl, ONE at a time, never in `timeout`. NOT run yet.
4. Alloc pins on three types (NOT run yet): test_zero_exports 239, test_local_stack 377, test/foreign/test_query 347, test_rules_swipl 433.
5. Re-check the EV1c.py C8/C9/C10 cites at the FINAL SHA if src/pl-event.jl or src/pl-wam.jl changes again (C8 :689, C9 :164 and :173, C10
   src/pl-wam.jl:1089-1090). The check: `python3 -I .warm/ev1chk.py tools/mutants/EV1c.py`.
6. Crash-term grep (done once over the added lines and messages, before the JET commit: hits only the event name `abort` / `onabort` / `PLEV_ABORT`
   identifiers and evidence notes that describe the grep; author check: all 29 commits Shivaji Gadde). Repeat for the new commit message.
7. `git fetch`; if origin/main moved past c4c34fd: plain `git rebase origin/main` (conflicts: keep both sides; port_inventory.md: take main's side then
   `warm.sh inventory`; mind the WHATS-HERE-UPSTREAM rows of docs/architecture.md for pl-incl.jl and pl-event.jl), then `warm.sh check`.
8. Bare pushes at the SAME SHA from gate/ev1c (redirect output to a log): `git push origin gate/ev1c` then `git push origin gate/ev1c:refs/heads/mutants/EV1c`
   (mutants/EV1c takes tools/mutants/EV1c.py; TARGETS = test_event_swipl.jl and test_bootpred3_swipl.jl). tools/mutants/BOOTPREDSUB.py is a separate list
   (35 mutants); only EV1c.py is pushed by this step's names: the dispatcher decides whether a mutants/BOOTPREDSUB battery is run. ONE ci_status.

## Daemon
lk-ev1 daemon (unit logickernel-warm-e29a7ffc) was restarted by the daemon itself after the rebase (struct change in read_data); now running in
~/code/lk-ev1, idle at hand-back. The other slot (lk-lb4b2-run) untouched. No third daemon. Hook refusals: pre-push (wip/ ref) ->
local branch gate/ev1c; require-tests-before-commit on gate/ev1c until branch-gate recorded its marker; cap-subagent-context at 150k.
