# R2 gate rerun on e253a38f (audit D-0825 items 1-3): the files that touch the JET/Aqua fix, three types, peak memory

Tree: ~/code/lk-r2land, wip/r2land-s2 at e253a38f (== ci/r2land), tree clean. Julia 1.13.3, swipl = ~/.local/bin/swipl (the pin).
Runner: `LOGICKERNEL_WARM_SECOND=1 WARM_TIMEOUT_S=9000 tools/warm.sh file <f>` on the lane-1 daemon
(unit logickernel-warm-26b12a00, pid 3189488), one file at a time, reference / alt / alt_interned. The daemon was never
started, stopped or restarted by this step; no "daemon DIED" / "not running" in any run.
Changed by e253a38f: src/os/pl-tai.jl (`_c_strftime`, `_c_asctime_r`, the `%Z` read in format_time), src/pl-bag.jl
(`pl_suspend_findall_bag0_va`, bag position as an Int), src/pl-coverage.jl (`share_coverage_data`).

## Table

Pass / Fail / Error / Broken: the totals line of the run `warm: <file>  | Pass [Broken] Total` and the per-type lines. A column
that the summary does not print was zero (Test.finish prints a column only when it is non-zero); every run exited 0
(Test.finish throws on any Fail or Error), so Fail = 0 and Error = 0 everywhere.
SKIP/Warning grep: `SKIP|Warning|Test Failed|Error During` over the file's warm log (the log of a warm run holds the summary
and Prolog stdout only; see "What the warm log cannot show" below).
rss: `tools/warm.sh status` of the lane-1 daemon right after the file. pkgtest_way peak: `tools/pkgtest_way.sh <file>`, its
own scope, MemoryMax 3G (no cold precompile was killed: LOGICKERNEL_INERT_MEM_MAX was NOT raised), peak = the scope's memory.peak.

| file | type | Pass / Fail / Error / Broken | SKIP/Warning grep | daemon rss | pkgtest_way peak |
|---|---|---|---|---|---|
| core_text/test_tai_format_swipl.jl | reference | 60 / 0 / 0 / 0 | 0 | 4.0 GB | 1911 MiB (1 type: 58/58 passed, swipl-less) |
| | alt | 60 / 0 / 0 / 0 | 0 | | |
| | alt_interned | 60 / 0 / 0 / 0 | 0 | | |
| core_text/test_tai_swipl.jl | reference | 31 / 0 / 0 / 0 | 0 | 4.0 GB | 1763 MiB (30/30) |
| | alt | 31 / 0 / 0 / 0 | 0 | | |
| | alt_interned | 31 / 0 / 0 / 0 | 0 | | |
| core_lang/test_coverage_swipl.jl | reference | 78 / 0 / 0 / 0 | 0 | 4.0 GB | 1878 MiB (77/77) |
| | alt | 78 / 0 / 0 / 0 | 0 | | |
| | alt_interned | 78 / 0 / 0 / 0 | 0 | | |
| core_lang/test_q10b_swipl.jl | reference | 139 / 0 / 0 / 0 | 0 | 4.0 GB | 1767 MiB (138/138) |
| | alt | 139 / 0 / 0 / 0 | 0 | | |
| | alt_interned | 139 / 0 / 0 / 0 | 0 | | |
| core_lang/test_bagof_swipl.jl | reference | 223 / 0 / 0 / 0 | 0 | 4.0 GB | 400 MiB (221/221) |
| | alt | 223 / 0 / 0 / 0 | 0 | | |
| | alt_interned | 223 / 0 / 0 / 0 | 0 | | |
| db/test_boot_image_swipl.jl | reference | 80 / 0 / 0 / 0 | 0 | 4.0 GB | not asked |
| | alt | 80 / 0 / 0 / 0 | 0 | | |
| | alt_interned | 80 / 0 / 0 / 0 | 0 | | |
| core_lang/test_bisim_swipl.jl | reference | 105 / 0 / 0 / 0 | 0 | 4.0 GB | not asked |
| | alt | 105 / 0 / 0 / 0 | 0 | | |
| | alt_interned | 105 / 0 / 0 / 0 | 0 | | |
| core_lang/test_depth_limit_swipl.jl | reference | 140 / 0 / 0 / 0 | 0 | 4.0 GB | not asked |
| | alt | 140 / 0 / 0 / 0 | 0 | | |
| | alt_interned | 140 / 0 / 0 / 0 | 0 | | |
| core_text/test_locale_swipl.jl | reference | 35 / 0 / 0 / 1 | 0 | 4.0 GB | not asked |
| | alt | 35 / 0 / 0 / 1 | 0 | | |
| | alt_interned | 35 / 0 / 0 / 1 | 0 | | |
| test/test_r2_status.jl | one run (not term-generic) | 119 / 0 / 0 / 0 | 0 | 4.0 GB | not asked |
| test/test_type_discipline.jl | one run (not term-generic) | 45 / 0 / 0 / 0 | 0 | 4.1 GB | not asked |

Totals lines quoted (3 types summed): tai_format 180/180, tai 93/93, coverage 234/234, q10b 417/417, bagof 669/669,
boot_image 240/240, bisim 315/315, depth_limit 420/420, locale `105 Pass, 3 Broken, 108 Total`, r2_status 119/119,
type_discipline 45/45 (run time 5m16.9s).

## Named rows

- bisim t63 / t71 / t74: the file compares line i of the kernel's answers with line i of the pin's .out in a loop
  `@test (i, kl[i]) == (i, expected[i])`, one test per row (t63 = i 64, t71 = i 72, t74 = i 75), and asserts 75 rows
  (`names == ["t$i" for i in 0:74]`). 105 of 105 passed on each of the three types, 0 Fail: t63, t71, t74 GREEN on reference,
  alt, alt_interned. (The log names a row only when it fails; none did.)
- depth_limit il05 / il24 / il25: the file's rows (`call_with_inference_limit(true, infinite, R)`, `... 9223372036854775806 ...`,
  `... 9223372036854775807 ...`) are compared per row against the .out; 140 of 140 passed on each type, 0 Fail: il05, il24, il25
  GREEN on reference, alt, alt_interned.
- locale: the one Broken per type is `@test_broken kl[i] == expected[i]` for row t12 (`_LCS_NUL_ROWS = ("t12",)`, a refusal
  pinned by name, test_locale_swipl.jl:203); it is the file's own design, the same on all three types. The paired
  `@test kl[i] == row * " notported"` passed.
- `%Z` (tai_format first .pl one row, tz testset 5 rows), strftime/asctime (tai, tai_format), `'$suspend_findall_bag'/0`
  (q10b findnsols rows, boot_image), coverage rows: all inside the passed counts above.

## What the warm log cannot show (a limit, not a result)

A warm run's log is the daemon's out.txt: the Test Summary plus Prolog stdout ("Loading boot file ..." and two more such
lines are the Prolog side of the program for test_type_discipline). The daemon's Julia stderr (`@warn`, `@info`) is not in it,
so the SKIP/Warning grep over a warm log can only find lines in the summary: it found none. Classified: Prolog-message
Warning lines 0, Julia Warning lines 0 in the logs. For the first five files the pkgtest_way stderr (.warm/pkgtest_way/<f>.err)
is the second source: it holds only `[ Info: ... DIFFERENTIAL NOT RUN LIVE: swipl is not on PATH here` lines (that run is
swipl-less by design; the warm runs above had swipl and ran the live differentials) and one pkgtest-way notice that the last
cache belonged to ANOTHER checkout (lk-tbland2) so this checkout built its own cache in a fresh depot; that is why the first
pkgtest_way runs take 4-6 minutes each (bagof, last, 16.5 s). No `Warning`, no `SKIP`, no `Test Failed`, no `Error During`.

## Reds

None. No row was compared against the pin swipl because none failed.

## Peak memory, in one line

Lane-1 daemon rss 4.0 GB after every file (4.1 GB after test_type_discipline; cap 6 GB); pkgtest_way peaks 1763-1911 MiB for the
four files that compile in the fresh process, 400 MiB for bagof; cap 3G never reached, oom_kill 0 on all five.
