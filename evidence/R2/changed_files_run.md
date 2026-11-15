# R2 landing line: the changed test files, one at a time, three term types (audit D-0816 item 3)

Tree: ~/code/lk-r2land, wip/r2land-s2, run on fa43c7d5 for the first pass and on 7c2ee79a (four test-file fixes) for the re-runs.
Runner: `tools/warm.sh file <f>` on the lane-1 daemon (julia 1.13.3, swipl = ~/.local/bin/swipl), reference / alt / alt_interned.
test/test_r2_status.jl was run before this step: 119 passed (not repeated).

## Raw table (final state of each file; P/F/E = passed/failed/errored per term type)

| file | rc | reference P/F/E | alt P/F/E | alt_interned P/F/E | SKIP | Warning | Test Failed | Error During |
|---|---|---|---|---|---|---|---|---|
| core_lang/test_bisim_swipl.jl | 1 | 14/0/1 | 14/0/1 | 14/0/1 | 0 | 0 | 0 | 3 |
| core_lang/test_coverage_swipl.jl | 0 | 78/0/0 | 78/0/0 | 78/0/0 | 0 | 0 | 0 | 0 |
| core_lang/test_cstack.jl | 0 | 20/0/0 | 20/0/0 | 20/0/0 | 0 | 0 | 0 | 0 |
| core_lang/test_depth_limit_swipl.jl | 1 | 135/1/0 | 135/1/0 | 135/1/0 | 0 | 0 | 3 | 0 |
| core_lang/test_htable.jl | 0 | 69/0/0 | 69/0/0 | 69/0/0 | 0 | 0 | 0 | 0 |
| core_lang/test_p2b_swipl.jl | 1 | 27/0/1 | 27/0/1 | 27/0/1 | 0 | 0 | 0 | 3 |
| core_lang/test_prof_swipl.jl | 0 | 148/0/0 | 148/0/0 | 148/0/0 | 0 | 0 | 0 | 0 |
| core_lang/test_q10_swipl.jl | 1 | 351/1/0 | 351/1/0 | 351/1/0 | 0 | 120 | 3 | 0 |
| core_lang/test_q10b_swipl.jl | 0 | 139/0/0 | 139/0/0 | 139/0/0 | 0 | 0 | 0 | 0 |
| core_lang/test_zip1_swipl.jl | 0 | 131/0/0 | 131/0/0 | 131/0/0 | 0 | 0 | 0 | 0 |
| core_text/test_char_type_swipl.jl | 1 | 14/2/0 | 14/2/0 | 14/2/0 | 0 | 0 | 6 | 0 |
| core_text/test_ctype_text_swipl.jl | 0 | 50/0/0 | 50/0/0 | 50/0/0 | 0 | 0 | 0 | 0 |
| core_text/test_libtai.jl | 0 | n/a | n/a | n/a | 0 | 0 | 0 | 0 |
| core_text/test_locale_swipl.jl | 1 | 17/0/1 | 17/0/1 | 17/0/1 | 0 | 0 | 0 | 3 |
| core_text/test_tai_format_swipl.jl | 0 | 60/0/0 | 60/0/0 | 60/0/0 | 0 | 0 | 0 | 0 |
| core_text/test_tai_swipl.jl | 0 | 31/0/0 | 31/0/0 | 31/0/0 | 0 | 0 | 0 | 0 |
| db/test_boot_image_swipl.jl | 1 | 79/1/0 | 79/1/0 | 79/1/0 | 0 | 0 | 3 | 0 |
| db/test_clause_swipl.jl | 0 | 124/0/0 | 124/0/0 | 124/0/0 | 0 | 0 | 0 | 0 |
| test_port_check.jl | 0 | n/a | n/a | n/a | 0 | 0 | 0 | 0 |
| test_type_discipline.jl | 0 | n/a | n/a | n/a | 0 | 0 | 0 | 0 |

libtai, port_check, type_discipline are single-run files (REFERENCE scope; no per-type rows): test_libtai.jl 843 pass; test_port_check.jl 214 pass (3m04s); test_type_discipline.jl 45 pass (rc=0 after the home tree was built; 2 errored before it).
Warning column: all 120 of test_q10_swipl.jl's are the ENGINE's Prolog messages from the test program (`Warning: ... Singleton variables: [...]` on the consulted q10.pl), not Julia warnings. SKIP = 0 everywhere.

## Findings in order

1. FIXTURE (environment, not a commit): the first pass ran with no `home/` tree in the worktree (gitignored, built by tools/build_home.jl; boot_global_data: "home/boot/init.pl is missing"). 18 of 20 files errored on it. Built it (the builder, through the daemon: `home -> vendor/swipl-devel` symlinks), then re-ran all 18. A fresh worktree needs it before any boot-dependent test.
2. TEST fixes, committed 7c2ee79a (FIXED: ...): missing `using Test, LogicKernel` + `const LK` in depth_limit/q10/q10b; depth_limit _DL_KERNEL_DIFF keys "dl19"/"dl20" -> "t_dl19"/"t_dl20" (lookup uses the row name); p2b vacuity guard counted " i" (pinned lines hold "/1(i" and "/1(c[45]/2(i": 29 rows, floor 20 kept); q10b domain_error guard counted an atom, it is a compound ("c" codes; the expected 4 kept). No expectation weakened.

## Reds left, all ENGINE answers or a derived number (named, not fixed, not pinned)

- test_depth_limit_swipl.jl:358 row il05, `call_with_inference_limit(true, infinite, R)`: swipl `!` (a[33]), kernel `inference_limit_exceeded`. Cause at src/pl-prims.jl:4987 (`nlimit = inferences + limit + INFERENCE_LIMIT_OVERHEAD`, limit = INFERENCE_NO_LIMIT = typemax(Int), pl-incl.jl:1804: the sum wraps negative, `nlimit < limit` installs it). The "DIVERGES: the sum wraps" comment at pl-prims.jl:4975 names the wrap for the kernel; at the pin swipl answers `!`.
- test_q10_swipl.jl:614 row cb11 (current_blob/2 over a stream): swipl `yes`, kernel raised existence_error(procedure, open_null_stream/1).
- test_p2b_swipl.jl:290 (the whole q01-q59 program, exception outside any @test): atom_codes/2 on text with the character 0 -> NotPortedError "an atom containing the character 0 (a Symbol cannot hold it)" (src/pl-read.jl:2064 via pl-text.jl:604, pl-prims.jl:2559). The refusal is the settled DIVERGES of src/pl-read.jl:2061-2063 (user 2026-10-10, keep refusing); the rows expect swipl's atoms.
- test_locale_swipl.jl:152: the same NUL-atom NotPortedError, raised in the reader (pl-read.jl:2064 from get_token, pl-read.jl:2317) while consulting the program.
- test_char_type_swipl.jl:168/170 row t1: kernel `notported` where swipl enumerates 43 lines (3 vs 43 lines; the row after the enumerated chr 0 atom). Same NUL-atom refusal.
- test_bisim_swipl.jl:153 (kernel_lines, test:75): AssertionError "dropRecords!: a frame being filled above lTop (normal_call, vmi:1887) must not be dropped" at src/pl-wam.jl:126, reached from restore_after_query (pl-wam.jl:2697) <- _end_query <- _abandon_query (pl-wam.jl:2840) <- PL_next_solution (pl-wam.jl:2821): an exception inside a query is turned into this assertion while abandoning it, so the original exception is hidden. 42 passed, 3 errored (1 per type). The bisim run takes 5m25s warm (alt 2m57s, alt_interned 2m18s).
- test_boot_image_swipl.jl:247, `_BI_KERNEL_MISSING_FOREIGN`: derived constant 320 ("DERIVED, NOT RUN: the gate measures"), measured and printed by the PIN line on all three types: 253. Reported, NOT edited (brief: do not guess; the value is 67 lower than derived). 237 passed, 3 failed (1 per type); every other row passes.
