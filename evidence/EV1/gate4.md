# EV1 gate agent 4 — state and result

Lane ~/code/lk-ev1, local branch `gate/ev1c`. Pushed SHA fe76984bd4bd (30 commits on origin/main c4c34fd; origin/main had not moved at the last fetch).
Pushed at the SAME SHA, bare pushes: `gate/ev1c` and `mutants/EV1c` (tools/mutants/EV1c.py, 51 mutants).
CI run ids at fe76984: CI 41595613592 (in_progress), Evidence 41595613540 (queued), Mutation battery 41595634104 (queued; started by the mutants/EV1c push).
BOOTPREDSUB.py (35 mutants) is a separate list: NO mutants/BOOTPREDSUB branch pushed; the dispatcher decides.

## Commit
fe76984 FIXED: pl-event.jl JET reports (10) — the staged JET fix of agent 3, committed as is (3 files: src/pl-event.jl, test/static_analysis_manifest.jl,
tools/mutants/EV1c.py). The hook refused twice first: (1) "tree CHANGED since the suite passed" and (2) "unstaged changes" — both because agent 3 had
rewritten evidence/EV1/gate3.md after the branch-gate. No marker touched: I set gate3.md aside (copy in scratchpad), restored the committed text, committed
the tested tree, then put the new gate3.md back (it rides in the evidence commit with this file). No branch-gate rerun was needed.

## Results (every run read for SKIP/Warning: none in any log below)
* test/test_static_analysis.jl (JET + Aqua + AllocCheck, reference): 4354/4354, 51m34s. No finding.
* test/test_manifest_entries.jl: 9/9.
* tools/pkgtest_way.sh test_event_swipl.jl: passed (peak 1605 MiB, oom_kill 0); test_bootpred3_swipl.jl: passed (peak 1475 MiB, oom_kill 0).
* Alloc-pin files, three types (reference / alt / alt_interned), all green, no SKIP/Warning:
  test_zero_exports 81/79/79 = 239; test_local_stack 129/124/124 = 377; test/foreign/test_query 117/115/115 = 347; test_rules_swipl 145/144/144 = 433.
  The brief's four numbers are exactly these three-type sums of the passing tests; nothing changed. (The pinned allocation values are inside those tests,
  all passed.)
* Crash-term grep (`segment|SIGSEGV|crash|abort|invalid term_t|dies of`): over the added lines of `git diff origin/main..HEAD` and all 30 commit messages:
  hits are only the event NAME `abort`, the field `onabort`, `PLEV_ABORT` identifiers, the row bp3l20 `prolog_listen(abort, ...)`, mutant ids/anchors
  naming them, and evidence prose that describes the grep. The new commit message (fe76984) has no hit. No crash description anywhere.
* Author check: all 30 commits Shivaji Gadde <11524260+sivaji1012@users.noreply.github.com>, author and committer.
* `git fetch` twice: origin/main stays c4c34fd, so no rebase and no second `warm.sh check` (check passed at agent 3's tree; the commit hook accepted the same tree).
* Pre-push hook: check_coverage_zero OK, 14 changed src/ files.

## For the audit (D-0378 item 4) — said plainly
The bp3v15 shape-compare cites as the recorded owner of the term-type dependence: file-wide DIVERGES 1 ("ATOMIC DATA") in src/pl-termhash.jl and its
row in docs/architecture.md (sym_hash contract at src/term_interface.jl:90). Agent 3 ADDED ONE SENTENCE to DIVERGES 1 (a comment) saying the digests
also differ between term types (the old text said only that the values are not swipl's). The dispatcher puts this to the audit; if not accepted,
revert to a type-keyed pin (test/core_lang/test_bootpred3_swipl.jl `_b3_digest_shape`).

## Daemon
lk-ev1 daemon (unit logickernel-warm-e29a7ffc) running, idle, left running. The other daemon (lk-halt1) untouched. No third. Raw logs: evidence/EV1/g4/.
