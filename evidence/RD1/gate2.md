# RD1c fix agent 1 (2026-11-03) — hand-back at the 150k cap. Edits + most runs DONE; NOT pushed.

Tip of wip/rd1: 76855a3 (rows rt322/rt323 + mutants RD1c.py), over d7076d2 (gate2 part 1), d70183f (canonical row fix), 807850c, bd38a5c (= gate/rd1b tip).
Nothing pushed. Working tree clean at 76855a3 except this file.

## Step 1 file list (stale-pin grep over test/): see git history of this file (d7076d2). Files that name the blob READ option: test_canonical_readatom_swipl.jl (stale row, fixed), test_read_stream_swipl.jl (rt303-rt323).

## Runs DONE (daemon of ~/code/lk-rd1, unit logickernel-warm-4d22bbd8; first slice; started this session)
- fmt: JuliaFormatter via warm.sh send over test_canonical_readatom_swipl.jl and test_read_stream_swipl.jl: no rewrite of the hand-formatted rows.
- `warm.sh check`: PASS twice (128 s at d70183f, 116 s at 76855a3): format, port_check clean (253 files), manifest 3397, term scopes, meta files, inert guard.
- test_canonical_readatom_swipl.jl (swipl 10.1.19 live): 445/445 on reference, alt, alt_interned. The 8 new hand-goal rows + the "blob(Mode)" testset pass.
- test_read_stream_swipl.jl at 76855a3: 261/261 on all three types (was 259; +rt322, rt323). test_read_term_swipl.jl 66/66 x3, test_read.jl 113/113 x3 (at d70183f; src unchanged since). test_type_discipline.jl 33/33.
- No SKIP / Warning / DIVERGES lines in any of these logs (grep over the logs).

## D-0376 survivors, run IN-TREE (tools/mutate.sh run-in-tree tools/mutants/RD1c.py test/core_text/test_read_stream_swipl.jl -- <ID>, one at a time)
- RD1-A3 (kill rows rt174, rt199): SURVIVED in-tree. Cause: raw_read2 never puts leading layout into its buffer (every blank/comment/NUL branch is gated by
  `something_read`: src/pl-read.jl 779, 804, 822, 834, 924-927, 967-970; pl-read.c ensure_space 1440-1443 and 1672, 1724, 1769, 1785, 1810, 1817, 1839, 1947),
  so pl_raw_read2's skipSpaces (pl-read.c:6691, src/pl-read.jl:4585) has nothing to skip: no row can kill it. Declared `equivalent=` in tools/mutants/RD1c.py with
  this code reason, FOR THE DISPATCHER'S RULING (read, not run, plus the in-tree survival).
- RD1-F2 (rt315): SURVIVED in-tree. Cause: rt311 runs first and leaves `<` a prefix operator in module rtm, so blob_syntax_available is false in rt315 and the
  `!must_be_op` test is never reached. New row rt322 (fresh module rtn, `op(200,xfy,rtn:(>))`, `a <b>(c).` with blob(dead)): kernel = swipl 10.1.19 = a<(b>c);
  F2 now CAUGHT in-tree (by "read/1,2, read_term/2,3 ... rows" testset).
- RD1-F6 (rt316): SURVIVED in-tree. Cause: `X = <a>.` has `>.` as ONE symbol atom, so the raw read ends in end_of_file before the tokeniser runs. New row rt323
  (`X = <a> .` from a file, blob(dead)): swipl 10.1.19 and kernel = syntax_error(operator_expected); F6 now CAUGHT in-tree.
- RD1-F1 control (probe): rt314 DIFFs under F1, so the probe/reload path works.
- Mutants list: RD1-F2/F6 KILL names now rt322/rt323; header says rt300-rt323. checker: 33 mutants, anchors once, ids unique.

## LEFT (the next agent, or the dispatcher), in order
1. `tools/pkgtest_way.sh test/core_text/test_canonical_readatom_swipl.jl` and then `.../test_read_stream_swipl.jl` (ONE at a time; the hook cap stopped me before they ran;
   the earlier `warm.sh check` runs include the Pkg.test-way pass on changed test files, both PASS, but the explicit runs are not done).
2. Crash-term grep (`segment|SIGSEGV|crash|abort|invalid term_t|dies of`) over `git diff origin/main..HEAD` added lines and all messages; author check
   (`git log --format=%an%n%cn origin/main..HEAD` = Shivaji Gadde only); `git fetch`, plain `git rebase origin/main` if main moved.
3. Bare pushes at the SAME SHA: `git push origin <sha>:refs/heads/gate/rd1c` and `git push origin <sha>:refs/heads/mutants/RD1c` (pre-push needs tools/mutants/RD1c.py: present). One ci_status.
4. Copy this file to ~/code/lk-channel/evidence/RD1/gate2.md, stage then commit in two calls, push.
5. Stop MY daemon with `# allow-restart: RD1c done, slot returned`: `cd ~/code/lk-rd1 && tools/warm.sh stop`. IT IS STILL RUNNING (unit logickernel-warm-4d22bbd8, started this session by me).
   The lk-lb4b2-run daemon (logickernel-warm-17790d9d) was never touched.
6. The battery on mutants/RD1c only after Evidence is green on the same SHA.

## RD1c gate finish agent (2026-11-03): LEFT list steps 1-4 results

- tools/pkgtest_way.sh test/core_text/test_canonical_readatom_swipl.jl: passed the way Pkg.test runs it, peak 1260 MiB (cap 3G, oom_kill 0).
- tools/pkgtest_way.sh test/core_text/test_read_stream_swipl.jl: passed the way Pkg.test runs it, peak 1480 MiB (cap 3G, oom_kill 0). Run one at a time, same daemon slice (unit logickernel-warm-4d22bbd8) untouched.
- git fetch: origin/main = dd93b68 (unmoved; merge-base is dd93b68), so no rebase and no re-run of check or the three-type runs. 20 commits ahead of origin/main, all authored and committed by Shivaji Gadde.
- Crash-term grep over the added lines of the diff and over all 20 commit messages: no match in src/, test/, tools/ or any message. The only matches are two lines in this evidence directory that quote the grep pattern itself (gate2.md, the report of the grep). Reading: the pattern text, not a crash.
- RD1-A3 is declared equivalent, pending audit. Cited lines checked against the pin source (swipl-devel-cbf4e189, pl-read.c): 1440-1443 (ensure_space gated by something_read), 1672, 1724, 1769, 1785, 1810, 1817, 1839, 1947 (each `if ( something_read )`), 6691 (`s = skipSpaces(s);` in pl_raw_read2). Kernel side: src/pl-read.jl 779, 804, 822, 834, 924, 967 gate on something_read; 4585 is the skipSpaces call. The in-tree run against rt174/rt199 survived. tools/mutants/RD1c.py unchanged since the 33-mutant anchor check.
- Daemon of ~/code/lk-rd1 left RUNNING (dispatcher hands the slot over).
