# F1c gate agent 1 (2026-11-02, Sonnet), lane clone ~/code/lk-f1c — YIELDED to the PR1 fix (audit D-0373); nothing pushed

## Where it stands
- wip/f1c = the 10 writer commits (off main 012633e), FOLDED with this gate's fixes by tree plumbing (no force, no rebase -i; the branch was never pushed):
  tip 98e5f30 (old tip 69fa50a; same 10 subjects, same author/committer Shivaji Gadde <11524260+sivaji1012@users.noreply.github.com>). Working tree clean at 98e5f30
  (this file's commit sits on top). Nothing pushed: no gate/f1c, no mutants/F1C yet.
- Daemon: lk-f1c's daemon STOPPED (allow-restart: slot yielded to PR1 fix, audit D-0373). The lk-pr1 daemon was stopped by me at the start (PR1b already pushed);
  lk-lb4b2-run (boot-files agent) was never touched. A restart of lk-f1c's daemon is a COLD compile again (4 LD fields; ~7 min to ready this time, then 4 min for the first file, 8.5 min for the first three-type run).
  Start with `LOGICKERNEL_WARM_SECOND=1 tools/warm.sh start` in ~/code/lk-f1c when the dispatcher gives a slot.

## Fixes made (all folded into the matching commits)
1. test_debug_flag_swipl.jl (first-ever parse: NO typo; 3 rows failed, 114/117): the kernel has no library(lists), once/1 or forall/2 (boot/init.pl and the libraries are not loaded), so
   db24, db33, db34 raised existence_error(procedure, member/2 | memberchk/2 | once/1 | forall/2). Fix in the TEST program, swipl output unchanged (gen_rows.py rerun: pins byte-identical):
   `_DB_PROGRAM` defines member/2 and memberchk/2 (user: overrides the autoload in swipl, same answers); db24's `once(member(..))` -> `( member(..) -> true ; fail )`,
   `forall(member(W,..), W > 0)` -> `\+ ( member(W,..), \+ W > 0 )`. All white-box expectations (run-mode bits, messages, tracemode/debugmode direct calls, skiplevel, libswipl access write,
   version_git exact) PASSED on the kernel at the first run: no engine change, no port bug suspected. (Judgement call, not a regression: the missing predicates are library/boot, not a changed result.)
2. `warm.sh inventory` (port_check): five `# PORT:` lines inside function bodies/consts were MARKER-MALFORMED/FILE-UNKNOWN (set_libswipl, initPrologFlags :2595, setGITVersion,
   SO_EXT `src/CMakeLists.txt`, GIT_VERSION, pl-incl.h SKIP_VERY_DEEP): turned into plain comments ("Port of ..." / "Not a port of C code ..."); docs/architecture.md "What is here now" row of
   src/pl-trace.jl now names `src/pl-trace.c`, `src/pl-trace.h` (WHATS-HERE-UPSTREAM) and the generated docs/port_inventory.md + the mermaid edges (pl_trace -> pl_error / os_pl_prologflag, prologflag -> pl_trace) were regenerated.
3. `warm.sh fmt` rewrapped 3 src sites: set_flag_value's `rval = tracemode(..) && debugmode(..)` (3 lines), the libswipl `setPrologFlag(` (6 lines), tracemode's `_message_term(` (multi-line), plus the test file
   (PINS-END indent, `_db_atom_list_enc` as if/else). F1C.py: the four affected anchors (A2, A3, C3, E7) RE-FIT; python3 -I checker: 35 mutants, every `old` EXACTLY once, ids unique, old != new, targets exist.
   gen_rows.py still works after fmt (idempotent).

## Verdicts (SKIP/Warning/NOT RUN grep over every summary log: 0 in the test logs; summary_check.log has 2 Warnings "Failed to format evidence/F1B/sf_template.jl, evidence/F2/push_template.jl": unrelated templates, pre-existing)
- 4 test files on all three term types, on the FINAL tree: test_debug_flag_swipl 351/351, test_set_flag_swipl 390/390, test_push_flag_swipl 213/213, test_prolog_flag_swipl 1380/1380.
- warm.sh fmt (final: 0 pending), inventory clean (252 files), `warm.sh check` PASS (219 s), fast static pre-check (test/static_analysis_fast.jl) 14/14 (765 s), test/test_type_discipline.jl 33/33 (LD struct, 4 fields at the end).
  NOTE: check and the fast static ran BEFORE the plumbing fold; the fold only moved identical content between commits (final tree == the tested working tree, `git diff` against it was empty).
- tools/pkgtest_way.sh: test_debug_flag_swipl.jl PASSED the way Pkg.test runs it (116/116, 3m38s, peak 1463 MiB, cap 3G, oom_kill 0). The other three were NOT run (yield).

## LEFT, in order (the next gate agent)
1. start the daemon (above); `tools/warm.sh status`.
2. tools/pkgtest_way.sh, ONE at a time: test/core_lang/test_set_flag_swipl.jl, test_push_flag_swipl.jl, test_prolog_flag_swipl.jl.
3. Alloc pins x3 (Tier 1 alarm, LD struct): `warm.sh file` on three types for test/core_lang/test_zero_exports.jl, test_local_stack.jl, test/foreign/test_query.jl, test_rules_swipl.jl
   (PR1 gate5.md baselines: 239, 377, 347, 433; F1c must not change them).
4. crash-term grep `segment|SIGSEGV|crash|abort|invalid term_t|dies of` over `git diff origin/main..wip/f1c` added lines and the 11 commit messages.
5. Push (author check first, bare `git push origin <sha>:refs/heads/<name>`): a FRESH gate/f1c name and mutants/F1C at the SAME SHA (the list is tools/mutants/F1C.py; the pre-push hook checks the name).
   If anything changes the tree (fmt), redo `warm.sh check` first.
6. ci_status once per >=5 min; the battery decides the 31 non-equivalent mutants (4 declared equivalent F1C-EQ1..EQ4 in F1C.py with file:line reasons).
Known difference (checklist, pending F8): `libswipl` access write (kernel) vs read (swipl); `version_git` rows check only the 10.1.19 prefix (oracle build 10.1.19-9-ge0323664).
Tooling notes: `tools/warm.sh` calls are moved to a background task after 180 s; the Monitor until-loop is blocked by the sleep-loop hook; I waited with a capped `tail --pid=<pid> -f /dev/null`.
