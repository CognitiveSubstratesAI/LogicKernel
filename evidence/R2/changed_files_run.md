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
| core_lang/test_p2b_swipl.jl | 0 | 86/0/0 (1 broken) | 86/0/0 (1 broken) | 86/0/0 (1 broken) | 0 | 0 | 0 | 0 |
| core_lang/test_prof_swipl.jl | 0 | 148/0/0 | 148/0/0 | 148/0/0 | 0 | 0 | 0 | 0 |
| core_lang/test_q10_swipl.jl | 1 | 351/1/0 | 351/1/0 | 351/1/0 | 0 | 120 | 3 | 0 |
| core_lang/test_q10b_swipl.jl | 0 | 139/0/0 | 139/0/0 | 139/0/0 | 0 | 0 | 0 | 0 |
| core_lang/test_zip1_swipl.jl | 0 | 131/0/0 | 131/0/0 | 131/0/0 | 0 | 0 | 0 | 0 |
| core_text/test_char_type_swipl.jl | 0 | 60/0/0 (2 broken) | 60/0/0 (2 broken) | 60/0/0 (2 broken) | 0 | 0 | 0 | 0 |
| core_text/test_ctype_text_swipl.jl | 0 | 50/0/0 | 50/0/0 | 50/0/0 | 0 | 0 | 0 | 0 |
| core_text/test_libtai.jl | 0 | n/a | n/a | n/a | 0 | 0 | 0 | 0 |
| core_text/test_locale_swipl.jl | 1 | 19/0/1 | 19/0/1 | 19/0/1 | 0 | 0 | 0 | 3 |
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

- test_depth_limit_swipl.jl row il05: FIXED by R1 (below).
- test_q10_swipl.jl:614 row cb11 (current_blob/2 over a stream): swipl `yes`, kernel raised existence_error(procedure, open_null_stream/1).
- test_p2b_swipl.jl:290 (the whole q01-q59 program, exception outside any @test): atom_codes/2 on text with the character 0 -> NotPortedError "an atom containing the character 0 (a Symbol cannot hold it)" (src/pl-read.jl:2064 via pl-text.jl:604, pl-prims.jl:2559). The refusal is the settled DIVERGES of src/pl-read.jl:2061-2063 (user 2026-10-10, keep refusing); the rows expect swipl's atoms.
- test_locale_swipl.jl:152: the same NUL-atom NotPortedError, raised in the reader (pl-read.jl:2064 from get_token, pl-read.jl:2317) while consulting the program.
- test_char_type_swipl.jl:168/170 row t1: kernel `notported` where swipl enumerates 43 lines (3 vs 43 lines; the row after the enumerated chr 0 atom). Same NUL-atom refusal.
- test_bisim_swipl.jl:153 (kernel_lines, test:75): AssertionError "dropRecords!: a frame being filled above lTop (normal_call, vmi:1887) must not be dropped" at src/pl-wam.jl:126, reached from restore_after_query (pl-wam.jl:2697) <- _end_query <- _abandon_query (pl-wam.jl:2840) <- PL_next_solution (pl-wam.jl:2821): an exception inside a query is turned into this assertion while abandoning it, so the original exception is hidden. 42 passed, 3 errored (1 per type). The bisim run takes 5m25s warm (alt 2m57s, alt_interned 2m18s).
- test_boot_image_swipl.jl:247, `_BI_KERNEL_MISSING_FOREIGN`: derived constant 320 ("DERIVED, NOT RUN: the gate measures"), measured and printed by the PIN line on all three types: 253. Reported, NOT edited (brief: do not guess; the value is 67 lower than derived). 237 passed, 3 failed (1 per type); every other row passes.

## R3 (audit D-0818 item 2): the three NUL-atom test files, on 0f801aa4 (commits 1c933b99, e7f13112, 0f801aa4 on wip/r2land-s2)

The refusal is the settled DIVERGES of src/pl-read.jl:2061-2064 (`_atom_from_text`: NotPortedError "an atom containing the character 0 (a Symbol cannot hold it)", user 2026-10-10). No engine change. Runner `tools/warm.sh file <f>` (lane-1 daemon, swipl = ~/.local/bin/swipl 10.1.20), grepped: SKIP 0, Warning 0, Test Failed 0.

| file | before (per type: P/F/E) | after (per type) | known difference pinned by name |
|---|---|---|---|
| core_text/test_char_type_swipl.jl | 14/2/0 | 60 pass, 2 broken, 0 fail, 0 error | rows t42, t43 (t1 and t3 for the character 0): the kernel line `tN notported` is asserted, swipl's line (.out) is `@test_broken` |
| core_text/test_locale_swipl.jl | 17/0/1 | 19 pass, 0 fail, 1 error (see below) | row t12 (t10's decimal_point('a\000\b'), now built by atom_codes/2 at run time as the last row): `t12 notported` asserted, swipl's line `@test_broken` |
| core_lang/test_p2b_swipl.jl | 27/0/1 | 86 pass, 1 broken, 0 fail, 0 error | row q17 (`atom_codes(N, [0])`): `t_q17 notported` asserted, swipl's pinned line `@test_broken`; q01-q59 all run again |

How: `kernel_lines_all` / `_p2b_kernel_all` continue after a refused row on a fresh engine (the refusal ends one run: its ld is thrown away), so no row after a refused one is lost. char_type: t1/t3 take `ct_codes_nz` (ct_codes without 0); the code-0 answers are the new last rows t42/t43; the .out is regenerated from swipl 10.1.20 by the file's own driver, two identical runs, and the old t1/t3 solution lists equal the new ones plus the t42/t43 solution (checked by script). locale: t10 loses the R6 element and the new t12 carries it; the .out regenerated the same way, two identical runs; the old t10 line equals the new one plus t12's cons cell (a 50-character span, checked); swipl's t12 answer is `true-a` (swipl cuts the decimal point at the character 0). p2b: no pinned line changed.

OPEN, NOT NUL, NOT FIXED (engine, brief says no engine change): test_locale_swipl.jl still errors once per type, now one step later. With the program loaded, the first row that calls locale_create/3 raises `UndefVarError: nl not defined in local scope` at src/os/pl-locale.jl:725: the line `nl::PL_locale_rec{T}` at the head of pl_locale_create3_va is a bare statement, which Julia evaluates as a type assertion on an unset variable (probe on the daemon: the same statement in a scratch function raises it, `local nl::Int` returns 1). Every call of locale_create/3 raises it. Blame 38c2ad4df (2026-11-11, R2 stack 1). One-line fix: `local nl::PL_locale_rec{T}`. Unknown until it is fixed: what the other locale rows show.

Gates for the three files: `tools/warm.sh fmt` clean (char_type reformatted before its commit), `tools/warm.sh check` PASS (464 s), `tools/pkgtest_way.sh`: char_type passed (peak 2983 MiB of 3G), p2b passed (2055 MiB), locale FAILED (the UndefVarError above; 19 passed, 1 errored on reference).

## R3b (D-0818 item 7a follow-up): `locale_create/3` raised on every call; test_locale_swipl.jl runs its rows

Two defects in src/os/pl-locale.jl, found in sequence (the first hid the second):
1. `nl::PL_locale_rec{T}` at the head of `pl_locale_create3_va` was a bare statement (a type assertion on an unset variable): `UndefVarError: nl not defined in local scope` on every call, every type. Fix: `local nl::PL_locale_rec{T}` (upstream's `PL_locale *def, *new = NULL` declaration; blame 38c2ad4df).
2. With 1 fixed, the alt and alt_interned types raised `MethodError: no method matching _loc_atoms_equal(::AltSym, ::AltRSym)` (`getLocale` -> `_locale_lookup` -> `_locale_table_index`, pl-locale.jl:217): the signature `(a::T, b::T) where {T}` needs ONE concrete type, and a stored alias and a looked-up atom are different concrete subtypes of the term type there. Fix: untyped arguments (the body is unchanged). Not in the brief; it is the next failure of the same call, it blocks the three-type run, so it is in the same commit and can be split off.

Probe on the daemon (tools/warm.sh send, scratch program: a locale made from "C" with alias and the three properties, one made from an existing alias, a nonexistent name, a taken alias, a bad group size), kernel vs the pin swipl 10.1.20 (~/.local/bin/swipl): all five answers equal (blob locale with the four properties read back; the pb/pc properties inherited; existence_error(locale,nonexistent_xyz); permission_error(create,locale,pd); domain_error(digit_group_size,0)); two identical kernel runs, two identical swipl runs.

test/core_text/test_locale_swipl.jl, `tools/warm.sh file` on three types (grepped: SKIP 0, Warning 0, Test Failed 0, Error During 0):
| state | reference | alt | alt_interned |
|---|---|---|---|
| R3 base (204b5825) | 19 pass, 1 error (UndefVarError) | same | same |
| defect 1 fixed only | 35 pass, 1 broken, 0 error | 19 pass, 1 error (the MethodError above) | same |
| both fixed | 35 pass, 1 broken | 35 pass, 1 broken | 35 pass, 1 broken |
The one broken per type is t12 (the NUL decimal_point, the named known difference). Every row t0-t11 equals swipl's line on all three types: no ENGINE answer differs, no TEST/DRIVER red. The file's existing rows already fail if locale_create/3 raises (every row builds its locales through it; the testset errors at the kernel_lines_all call). Mutation at verdict level, reference type: the bare statement put back -> `UndefVarError: nl not defined` in the testset, 19 passed, 1 errored (file FAILS); restored, git diff shows only the two fixes.

Gates: `tools/warm.sh fmt` clean, `tools/warm.sh check` PASS (256 s; the F2 push_template.jl parse Warning is the old formatter noise on a template), test/test_type_discipline.jl 45/45, `tools/pkgtest_way.sh test/core_text/test_locale_swipl.jl` passed (peak 1781 MiB of 3G).

## R1 (audit D-0818 item 2): `call_with_inference_limit(true, infinite, R)` (row il05), wip/r2land-s2

Upstream arithmetic (swipl-devel 18168e62): src/pl-prims.c:5831 `int64_t nlimit = LD->statistics.inferences + limit + INFERENCE_LIMIT_OVERHEAD;`
(`inferences` is `uint64_t`, pl-incl.h:2767, so the sum is an unsigned wrap stored in an int64), :5841 `if ( nlimit < LD->inference_limit.limit )`
(a signed compare: the wrapped negative sum IS installed), and the check, pl-vmi.c:2014 / :6875 / :6942 `if ( LD->statistics.inferences >= LD->inference_limit.limit )`
compares `uint64_t` with `int64_t`, i.e. UNSIGNED: a negative limit is a huge value, never reached. INFERENCE_NO_LIMIT = INT64_MAX (pl-incl.h:2984). No saturation anywhere.
Pin probe (~/.local/bin/swipl, two identical runs): limits 2^63-2 and 2^63-1 answer `!`; 2^63 raises representation_error(int64_t); `'$inference_limit'(2^63-2, O)` then `'$inference_limit'(infinite, O2)` gives O2 = -9223372036854758076 (the wrapped value is stored and printed).
The kernel's sum already wrapped the same way (src/pl-prims.jl pl_inference_limit2_va); the divergence was the check at src/pl-wam.jl (depart_alerted site) comparing SIGNED. Fix: that compare is unsigned (`reinterpret(UInt64, ...)` of both sides); a DIVERGES comment names the representation, and the stale "DIVERGES: the sum wraps" comment in pl-prims.jl now says it wraps as upstream's does. The brief's `pl-prims.jl:4987` line is unchanged (it is faithful).
Rows: il24 (limit 9223372036854775806) and il25 (9223372036854775807), pins from the pin binary through the file's own driver, two identical runs: `!` both.
| state | per type (reference, alt, alt_interned) |
|---|---|
| before (HEAD, 5b1847ae) | 135 pass, 1 fail (il05, `ours inference_limit_exceeded, want !`), on each type; SKIP/Warning 0 |
| after | 140 pass, 0 fail, 0 error on each type; SKIP/Warning/Test Failed/Error During 0 |
| mutation: the old signed compare put back (reference) | 137 pass, 3 fail: il05, il24, il25 (each `ours inference_limit_exceeded, want !`); fix restored |
Gates (R1): `tools/warm.sh fmt` 0 rewritten; the first `check` failed only on INVENTORY-DRIFT of docs/port_inventory.md (source lines moved), `tools/warm.sh inventory` rewrote it (1 line; the landing SHA writes it again after the R4 edits), `check` PASS (507 s); `tools/pkgtest_way.sh test/core_lang/test_depth_limit_swipl.jl` passed (peak 2952 MiB, rc 0). Final file run on the committed tree: 140 pass per type, 0 fail.

## R4 (audit D-0820 item 2, diagnosis A-0599 (1)/(4)): the bisim rows t63/t71 and the unwinding in i_metacall_clause, wip/r2land-s2

Upstream read (swipl-devel 18168e62, pl-comp.c): :978-981 (a compound under a `subclausearg` goal in a local compile is an argvar, `ci->argvars++`), :986-990 (the goal itself with
`fd->arity == 0`: `depth--; goto resume`), :3167-3191 (`compileArgument`: an argvar stores `*k = *arg`, the compound word whole, and emits `B_VAR0+n`/`B_VAR`; no argument of the
compound is looked at, so no variable per argument exists, whatever the arity). The faithful shape for arity 0 is therefore "no variable keys for the placeholder's arguments":
`k = n == 0 ? UInt64(0) : fresh_var_keys!(n)` in `_argvar_placeholder` (src/pl-comp.jl) is the same behaviour (the loop over `1:n` is empty). pl-vmi.c:5536-5575 (`i_metacall_common`):
a compile error is `rc == false` then THROW_EXCEPTION with `lTop = NFR` (nothing unwound, nothing Julia-side raised); the Julia exception out of the compiler is the kernel's own case,
which must leave `lTop` above the frame being filled before `_abandon_query`'s `dropRecords!` runs.

(a) 9b7e9c43, src/pl-comp.jl + test_bisim_swipl.{jl,pl,out}: the guard above; row t74 added (the arity-1 neighbour of t63/t71: `compound_name_arguments(A, automaton, [a]), err(automaton_minimal(A, _), R)`;
pin answer `true`, from the file's own driver run with ~/.local/bin/swipl, two identical runs; the 74 old lines unchanged), names count 74 -> 75.
(b) 00b8c5be, src/pl-wam.jl + test_bisim_swipl.jl: `mc_e isa PrologThrow || setLTop!(ld, argFrameP(mc_nb, 1))` (was `mc_e isa NotPortedError && ...`), then `rethrow()`. The row's injection needs no engine hook: the process-wide key counter
`LK._KERNEL_VAR_COUNTER` is set to typemax after the query is open (so the first key `compileGoalClause` asks for, the argvar of `p(f(a))` under `catch((p(f(a)), true), _, ...)`, raises
the AssertionError "kernel variable keys exhausted") and restored in `finally`; the row checks `PL_next_solution` throws that AssertionError and not the `dropRecords!` one, and that keys are issued again.

| state | reference | alt | alt_interned |
|---|---|---|---|
| before (R4 base-run, A-0599 / bisim_base_run.md; wip/r2land-s2 c305e75d) | 14 pass, 1 error (t63, dropRecords! assertion; original `fresh_var_keys!(0)` chained) | same shape (not re-run) | same shape (not re-run) |
| after (a): 9b7e9c43 | 101 pass | 101 pass | 101 pass |
| after (a)+(b): 00b8c5be | 105 pass | 105 pass | 105 pass |
grep of both full-file logs for `SKIP|Warning|Test Failed|Error During`: 0 lines.

Mutation at verdict level (hand edit, run, restore from a saved copy, `git diff` shows only the fixes afterwards), reference type:
- (a) the old `k = fresh_var_keys!(n)` put back: 14 pass, 1 error: the BISIM testset errors with the `dropRecords!` assertion (caused by `kernel variable keys exhausted`): t63/t71 reach it; file FAILS.
- (b) the old `mc_e isa NotPortedError && setLTop!(...)` put back: 103 pass, 2 FAIL, both in the new testset (the exception is not the compiler's AssertionError / it is the dropRecords! one; test_bisim_swipl.jl:234, :235); file FAILS. The BISIM testset (100 rows) still passes, as (a) is in.

Gates: `tools/warm.sh fmt` 0 rewritten; `tools/warm.sh check` PASS (359 s; no INVENTORY-DRIFT this time, port_check clean over 339 files; the push_template.jl parse Warning is the old formatter noise on a template);
`tools/pkgtest_way.sh test/core_lang/test_bisim_swipl.jl`: the first run was KILLED by its own 3G scope during the fresh precompile of this checkout's cache (the last cache was another checkout's, "REFUSED ... building this checkout's own cache"; peak 3072 MiB, oom_kill 1: no test verdict), the second with `LOGICKERNEL_INERT_MEM_MAX=5G` (the tool's documented knob) passed the way Pkg.test runs it (peak 3134 MiB).
