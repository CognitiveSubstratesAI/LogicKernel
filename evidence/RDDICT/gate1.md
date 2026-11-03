# RDDICT gate agent 1 (Sonnet) - hand-back at the 150k cap. Lane clone ~/code/lk-dict, branch gate/rddict (local, NOT pushed)

## State in one paragraph
gate/rddict = origin/main c4c34fd + 27 cherry-picked commits (HEAD dac6bf7, all committed, authors Shivaji Gadde) + UNCOMMITTED edits in the working tree (below).
Nothing pushed. The commit hook refuses `git commit` until a runner writes the marker (warm.sh preflight/branch-gate), so every edit since dac6bf7 is uncommitted:
they fold into the one commit made after `warm.sh branch-gate` passes. Daemon: lk-dict, unit logickernel-warm-4b046b8f, started with LOGICKERNEL_WARM_SECOND=1,
ready 07:33 UTC (Nov 3), STILL RUNNING; every warm.sh call in this clone needs `LOGICKERNEL_WARM_SECOND=1` in front. The EV1 daemon (lk-ev1) was stopped.
lk-eng3 daemon (other slot) untouched.

## Re-stack (done)
- wip/dict (DICT, 14 commits to a772c27) is NOT on main (BOOTPRED's dict set is different: main's src/pl-dict.jl has no del_dict/partial_unify_dict/copy_keys_dict ...), so all
  27 commits of origin/main..wip/rddict were carried: `git cherry-pick origin/main..wip/rddict` on new branch gate/rddict. wip/rddict untouched.
- conflicts, resolved keeping both sides: docs/architecture.md (append vs append), test/static_analysis_manifest.jl (append vs append; one comma added after RD1b's last entry),
  src/pl-read.jl start_pframe DIVERGES comment (main's RD1b blob wording + the dict sentence of 3665757). docs/port_inventory.md did not conflict.
- git range-diff 1286e62b89..wip/rddict origin/main..gate/rddict: 24 "=" (identical), 3 "!" (the three conflicted commits: 140f53c docs, 7e8f730 manifest, 3665757 pl-read.jl).
  Full text: evidence/RDDICT/rangediff.txt (this directory).

## Gate steps done
1. FIRST PARSE: test/core_lang/test_read_dict_swipl.jl on reference: PASS 357/357 in 266 s, no typo-level fix needed, no SKIP/Warning/broken lines in the log
   (.warm/summary_file_test_read_dict_swipl.log: 3 lines). Live swipl 10.1.19 compare ran (swipl on PATH). Not yet run on alt, alt_interned.
2. fmt (`warm.sh fmt`): rewrapped src/pl-read.jl (the S2 anchor line in read_dict_start + one `if` continuation indent), test_read_dict_swipl.jl, test_read_term_swipl.jl.
   tools/mutants/RDDICT.py re-fitted: only S2 was rewrapped (old/new now two lines); python3 -I checker (scratchpad chk.py, copy below): 52 mutants, `old` once each, ids unique, old != new,
   targets exist. TARGETS widened (D-0238): reader mutants TD, test_read_swipl.jl, test_read_term_swipl.jl, test_type_discipline.jl; flag mutants TD, test_prolog_flag_swipl.jl,
   test_set_flag_swipl.jl, test_push_flag_swipl.jl (the last two list var_tag `dict`), TT. Re-run the checker after ANY further fmt.
3. REFUSAL FLIP: removing the dict refusal flipped ONE pin: test/core_text/test_read_term_swipl.jl "the refusals" testset (all of -{a}, a{b}, a{}, X{a:1}, _{a:1}, point{x: 1}
   expected NOTPORTED; now swipl-compared). Rewritten (a REFUSAL flip, not a read-differently regression; same shape as RD1b D-0375): the testset now compares `-{a}`,`a{b}` as whole error balls
   with swipl (colon_expected), checks the four dict texts read as the dict compound `c[100,105,99,116]/..` and that swipl reads each as a dict (own is_dict swipl call, because the file's `enc/1`
   driver raises on a dict: that is why swipl's lines were 3 for 6 texts); the quasi-quotation texts stay NOTPORTED. After the edit: test_read_term_swipl.jl reference PASS 71/71.
   Also removed the unused `"-{a}" => "a dict"` entry of `refused`, and comment-only edits in test_read.jl:27, test_read_positions_swipl.jl (header + the _RP_REFUSED comment),
   test_read_swipl.jl:218. Grep of test/ for other dict-syntax pins (`_{`, `Tag{`, "a dict", PF_DICT, read_dict, NotPortedError+dict) found no other file with a row. Files still to run on 3 types:
   test_read_term_swipl.jl, test_read_positions_swipl.jl, test_read_swipl.jl, test_read.jl (comment-only edits, but listed by the grep), test_read_dict_swipl.jl.
4. Stale comment folded: src/pl-read.jl build_attvar says setVarTagFlag is in src/os/pl-prologflag.jl, only the set_prolog_flag/2 arm is F1b's. Also the three
   "UNVERIFIED on the kernel: gate decides" comments of read_dict_* now say "Run by the gate: test_read_dict_swipl.jl"; test file header line 13 says RUN at the gate;
   tools/mutants/RDDICT.py header "battery has not run"; docs/architecture.md: RDDICT block header (first run, stacked on DICT), TARGETS line, a sentence on the flipped refusal, line ~2965
   (the R1d "Refused" bullet: a dict is read since RDDICT).

## IN PROGRESS when the cap hit: `warm.sh inventory` FAILED port_check, two violations (fix, then re-run inventory)
- `MARKER-FILE-UNKNOWN src/pl-dict.jl:911: SWI-Prolog.h is not one of this file's UPSTREAM files` (the DICT writer's `# PORT: SWI-Prolog.h PL_FOR_DICT_SORTED` marker).
  FIX (one of the two edits below was applied, check each with `git diff -- src/pl-dict.jl docs/architecture.md`):
  (a) docs/architecture.md: the pl-dict.jl row (line ~786) upstream cell `src/pl-dict.c`, `src/pl-dict.h` -> add `src/SWI-Prolog.h` (APPLIED in the working tree, verify);
  (b) src/pl-dict.jl header: add `# UPSTREAM: swipl-devel src/SWI-Prolog.h @ cbf4e1896275` after line 2 (the last command was cut by the cap: probably NOT applied; the second
      violation `WHATS-HERE-UPSTREAM ... row names [pl-dict.c, pl-dict.h, SWI-Prolog.h], the headers [pl-dict.c, pl-dict.h]` is exactly that missing header line).
  Then `LOGICKERNEL_WARM_SECOND=1 tools/warm.sh inventory --summary` until rc=0 (it writes docs/port_inventory.md; keep it with the commit).

## NOT DONE (the next agent, in this order)
1. finish inventory (above), `warm.sh fmt` again if any .jl changed, re-run the anchor checker, `warm.sh check` (includes the Pkg.test-way run of changed test files; read SKIP/Warning).
2. rows on alt and alt_interned for the changed/new test files: test_read_dict_swipl.jl, test_read_term_swipl.jl, test_dict_preds_swipl.jl (DICT's file, never run!), test_read_positions_swipl.jl,
   test_read_swipl.jl, test_read.jl; reference for test_dict_preds_swipl.jl too (it was never run: first parse; its pins are the DICT writer's, UNVERIFIED; a wrong row there = STOP/fix from the kernel line).
   Also test/test_type_discipline.jl, test/test_manifest_entries.jl, test/static_analysis_fast.jl, then test/test_static_analysis.jl last (JET+Aqua+AllocCheck).
   The 13 RDDICT manifest entries and the DICT manifest entries were never run through `check`/manifest tests: a wrong tuple shows there.
3. tools/pkgtest_way.sh on each new/changed test file ONE at a time (test_read_dict_swipl.jl, test_dict_preds_swipl.jl, test_read_term_swipl.jl, ...), never wrapped in timeout.
4. Alloc pins x3 (test_zero_exports 239, test_local_stack 377, test/foreign/test_query 347, test_rules_swipl 433), report actual numbers.
5. crash-term grep `segment|SIGSEGV|crash|abort|invalid term_t|dies of` over added lines + commit message; author check; `git fetch` (origin/main was c4c34fd at start; HF1 / EV1 land on top ->
   plain rebase, keep both sides, then `warm.sh check`). `warm.sh branch-gate` (writes the marker), then ONE commit of the working tree (stage explicit paths, then commit in a second call; message
   subject + 5-10 lines + "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"). Push at the SAME SHA: `git push origin <sha>:refs/heads/mutants/RDDICT` then `...:refs/heads/gate/rddict`
   (redirect to a log, no git pipelines); ONE ci_status; do not wait for CI. The pre-push hook wants tools/mutants/RDDICT.py (exists).
6. evidence/RDDICT/gate1.md final version copied to ~/code/lk-channel/evidence/RDDICT/ (this file is the interim copy).

## Hook facts learned
- `git commit` is refused without the marker even for a one-line comment fix; cherry-pick/rebase pass. So edits stay uncommitted through the gate.
- `grep -rn` with a `{`-pattern over test/ trips require-codemap-before-capability-grep (comment `# allow-grep-search: <reason>` escapes).
- A foreground wait without sleep: `timeout 170 tail --pid=<pid of the warm.sh call> -f /dev/null` (the pid from `pgrep -f "lk-dict/tools/warm.sh <cmd>"`).
- A compound command whose first part is `git status` inside a background Bash trips no-uncapped-background: background only the warm.sh call.

## Anchor checker (python3 -I, throwaway; the scratchpad path is session-local)
Loads tools/mutants/RDDICT.py with runpy, for each mutant: id unique, `old` occurs exactly once in `file`, old != new, every target exists; prints "N mutants, K bad".
