# Evidence red at 01d7a9af (CI 43813910955, Evidence 43813911077): diagnosis

Lane run: `LOGICKERNEL_WARM_SECOND=1 WARM_TIMEOUT_S=9000 tools/warm.sh file <f>`, lane-1 daemon, swipl ~/.local/bin/swipl 10.1.20, Julia 1.13.3, three term types.
Both failing files REPRODUCE on the lane on all three types (reference, alt, alt_interned): the lane and CI agree.

## (1) test/core_lang/test_q10_swipl.jl:614, row t_cb11

- Reproduces: yes, all three types (1 fail per type, 167 pass of 168; 1053 pass / 3 fail in the file).
- Pin (swipl): `t_cb11 yes`. Ours: `raised(existence_error(procedure, open_null_stream/1))`.
- Row text (line 353): `open_null_stream(S), ( current_blob(S2, stream), S2 == S -> R = yes ; R = no ), close(S)`.
- Class: ENGINE gap, not a test error: pl-file.c `open_null_stream/1` (upstream 18168e62 src/os/pl-file.c:4701-4713, `Snew` over `nullFunctions` :4650-4695) has no kernel
  predicate. It is the SAME row already named known-red in evidence/R2/changed_files_run.md (R2 findings list) and ruled in audit D-0623 (3): open_null_stream/1 has
  no owner row; ruling = a `cfile:pl-file.c` row/note naming it and the pl-file.c group's owner, coverage "stays OPEN, not dropped".
- Why main was green: test_q10_swipl.jl does not exist on 87a88328 (`git show 87a88328:test/core_lang/test_q10_swipl.jl` -> not in that tree); lane C's
  commit c52ec2de (current_blob/2, rows cb01-cb20) ADDED the file and the row on the R2 line. Main never ran it.
- Cause (file:line): src/os/pl-stream.jl:203-208 `@enum IOFUNCTIONS` has Smemfunctions, Sstringfunctions, Siofunctions, Sstderrfunctions; there is no null function set, and no
  `open_null_stream` registration anywhere in src/os/pl-file.jl.
- Fix: NOT applied. The faithful fix is not a small function-body change: a new IOFUNCTIONS member (the enum's `_enum_hash` manifest entry), its arms in `S_read`/`S_write`/
  `S_seek64`/`S_close`, the predicate in pl-file.jl, the r2_upstream/r2_owners rows. Status: known-red, owner = the pl-file.c group (dispatcher names it, D-0623 (3)).
- Option NOT applied (the auto-mode classifier refused the edit; the row is a failing row, so it needs the dispatcher's word): D-0623 (3) says "the test row keeps
  `open('/dev/null', write, S)` with its pinned answer"; the row text on the line uses open_null_stream/1, never /dev/null. With the goal
  `open('/dev/null', write, S), ( current_blob(S2, stream), S2 == S -> R = yes ; R = no ), close(S)` swipl 10.1.20 prints `yes` (two identical runs; the same for
  open_null_stream/1). Same property (a stream is enumerated as a stream blob), same pinned answer; the open_null_stream/1 coverage gap stays recorded in the owner row.

## (2) test/files/test_load_swipl.jl:606 and :738

- Reproduces: yes, all three types (2 fails per type: 303 pass / 6 fail in the file).
- Class: TEST (stale pins of DIVERGES the engine closed on the line). The engine answers are swipl's; nothing weakened.
- :606 `'$set_predicate_attribute'(1, dynamic, true)`: swipl `type_error(predicate_indicator, 1)`; ours NOW `type_error(predicate_indicator, 1)` (the failing
  expression `line("callable") in ours` compared against ours = ["ok", "error ...predicate_indicator...", "warning goal_failed(...)"]). The row pinned the old kernel answer
  `callable`. Cause: 3852e280 (UPSTREAM: pl-proc.c get_procedure, every mode: GP_NAMEARITY -> get_functor, src/pl-proc.jl) removed the DIVERGES that read a
  non-indicator head with get_head_functor. Row now asserts `predicate_indicator` in ours (and in swipl).
- :738 `!(isempty(pin)) && dl == pin`, case "initialization": printed `DIVERGES (initialization): []` (an empty list). The pinned difference was line 2
  `existence_error(procedure, $syspreds:'$on_signal'/4)`; Q10's `$on_signal/4` (34183573 / pl_on_signal4_va, src/pl-setup.jl:611) closed it, ours == swipl.
  The "initialization" pin is removed from `_TL_KNOWN_DIFFS`; the case goes through `@test ours == theirs`.
- Why main was green: neither commit was on main (`git log -S set_predicate_attribute 87a88328..HEAD`: 3852e280; `-S on_signal`: afc47fe1, 34183573, 8f8aa07c);
  the TAB1 lane run at 5bdaa2d9 was before them.
- Fix: a76f2035 (`FIXED: test_load_swipl.jl: two pins of closed differences flipped to swipl's own answer`), one commit for both rows (same file, same class). Lane: 309 pass, 0 fail,
  three types (103 each), warm.sh fmt clean. Old lines back (HEAD 01d7a9af, same lane): 6 fail, 2 per type (the mutation proof).

## (3) t_cb11 broken (audit D-0826 (1)(c)), commit 2f4bd05a

- Rule applied: a row that depends on a named missing foreign predicate is a named `@test_broken` with its reason, not a red row.
- Edit: test/core_lang/test_q10_swipl.jl, inside the row loop of the testset "the Q10 built-ins as swipl's": for the row `t_cb11` the kernel's answer is pinned by name (the line holds `raised` and `open_null_stream`), `@test_broken k == want` keeps swipl's `yes` (from the .out) as the expected value, then `continue`. Convention as test/core_text/test_locale_swipl.jl:203 (row t12).
- Reason text: open_null_stream/1, pl-file.c:4701-4713 (`Snew` over `nullFunctions`), owner `cfile:pl-file.c`; the predicate needs a new IOFUNCTIONS member (pl-stream.jl:203-208), arms in S_read / S_write / S_seek64 / S_close, the predicate and inventory rows, so it is not a body change.
- Lane run, three types (warm.sh file): reference 352 pass / 1 broken, alt 352 / 1, alt_interned 352 / 1; file 1056 pass / 3 broken, 0 fail, 0 error. Each type gains one pass over the earlier 351: the new pin on the kernel's answer matched on all three.
- Mutation proof (verdict level): the plain `@test k == want` back makes the row fail at :619 on all three types (rc 1); the @test_broken restored, the file is byte-identical to the edited copy.
- Gates: `warm.sh fmt` rewrote this one file (Blue-clean after), `warm.sh check` PASS in 419 s, `tools/pkgtest_way.sh` passed (peak 1908 MiB, cap 3G, oom_kill 0).
- Warm-log grep: no SKIP, no Test Failed; the Warning lines are the Prolog messages of the generated q10.pl (singleton variables) and set_prolog_stack/2 "limit(Size) sets the combined limit" from the ss rows.

## (4) port_check identity (audit D-0828 (3) 1, D-0831), commit 0dc1775c

- Failure: test/test_port_check.jl:422 testset "an ORIGINAL mix names its upstream files (UPSTREAM-PARTS)", Error During Test at :573: `git commit-tree ... -m other` needs an author and committer identity; the CI runner carries none (Evidence run 43813910955: reference files 1/2; CI run 43813911077: Julia 1 and Julia min files 1/3); the lane has one in the global git configuration. Class TEST/DRIVER, an environment-dependent fixture. The testset arrived on the R2 line (e83213d4, 8a8b3ece, 68b1c6da), so main never ran it.
- Fix: the commit-tree call is wrapped in `withenv` with GIT_AUTHOR_NAME/EMAIL and GIT_COMMITTER_NAME/EMAIL of its own (`lk-fixture`, `lk-fixture@example.invalid`); the other commit-creating calls of the file go through `_pc_git`, which already passes `-c user.name -c user.email`. Every expectation is unchanged.
- Hook: .claude/hooks/no-unescaped-dollar-in-docstring.sh refuses any Edit of the file because fixture lines (99, 109, 110, 121, 159, 170: `$WHATS_HERE_HEADING`, `$GRAPH_BEGIN`, `$GRAPH_END`, `# UPSTREAM: ... @ $sha`) read as an unescaped dollar inside a docstring. Mechanism used, with Shivaji's yes relayed in D-0831: the hook's own per-file marker `# allow-docstring-interp: fixture text, not a docstring (audit D-0831)` in the header of test/test_port_check.jl; no hook, setting or other file is edited. The hook was run by hand on scratch files: an unescaped dollar in a docstring without the marker is refused (exit 2), the same text with the marker passes (exit 0), a clean docstring edited to add a dollar without the marker is refused (exit 2).
- Proof, both sides: identity hidden (GIT_CONFIG_GLOBAL=/dev/null, GIT_CONFIG_NOSYSTEM=1, GIT_AUTHOR_NAME/EMAIL, GIT_COMMITTER_NAME/EMAIL and EMAIL unset) through tools/pkgtest_way.sh test/test_port_check.jl: 205 passed 1 errored before the edit, 214 of 214 after (3m50s, peak 809 MiB, PASS); normal environment on the lane (warm.sh file): 214 of 214 in 3m46s, no SKIP, no Test Failed. `tools/warm.sh fmt` rewrote 0 files; `tools/warm.sh check` PASS in 1040 s.
