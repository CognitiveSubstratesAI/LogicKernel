# PIN1-I1 and PIN1-I2: why TP:260 did not fail, and the row that does (audit D-0810 item 2)

Branch wip/tab1-pin1b, base 99e5975c (cherry-picked onto wip/tab1-mono as 7bf45b4d). Written edit-only; RUN ON LANE 2 2026-11-15, see the last section.

## Why test_prolog_flag_swipl.jl:260 passed on both mutants
The mutants change the value `setPrologFlag(gd, "max_incomplete_subgoals_action" / "max_scc_subgoals_action", FT_ATOM, ...)` stores
in the flag record (`f.a`), src/os/pl-prologflag.jl:1943 and :1945 (`_init_tabling_flags!`).
TP:260 is the testset whose rows t_defaults (.pl:173) and t_enum_error (.pl:240) read the flags through `'$current_prolog_flag'/5`
and `current_prolog_flag/2`. Both go to `unify_prolog_flag_value` (src/os/pl-prologflag.jl:471), which for a restraint flag
(`tbl_is_restraint_flag`, :1446-1458, lists both `*_action` flags) returns `tbl_get_restraint_flag(ld, val, key)` BEFORE the generic
`FT_ATOM` branch that reads `f.a` (:485-486). `tbl_get_restraint_flag` (src/pl-tabling.jl:10147-10166 (`tbl_get_restraint_flag`)) answers from
`ld.tabling.restraint`, which `initTabling!` (src/pl-tabling.jl:153-164) starts at `error` independently of the flag record.
So the row compares the wrong thing (the restraint record, not the stored start value): the mutated `f.a` is never read.
This is the same reader gap PIN1-I5 closed for `f.i` (the DEFKILL3 loop at TP:309-315).
The mutants ARE reached from TARGETS (TP loads the data and the flags exist); the gap is the read path, not TARGETS.
(Note: the .pl rows enumerate by `fk/1`, which does list both flags, .pl:62-70; they are real rows, just on the other path.)

## The row added (test/core_lang/test_prolog_flag_swipl.jl:914-940, appended at the end so no TP:<n> cited by PIN1.py moves)
Testset "the start value of the *_action restraint flags, off the flag, == swipl (PIN1-I1, PIN1-I2)":
- `gd = LK.PL_global_data{_TL}()` (fresh, as the neighbours at TP:281 and TP:487 make one); for each of the five `*_action` flags
  `f = LK.current_prolog_flag(gd, k)` (the flag record itself, not the reader), and `rowline(name, f.a)` (:926) is the kernel's line.
- swipl's line comes from `swipl_lines(prog, names)` on a generated program `t_actN(V) :- current_prolog_flag(<flag>, V).`
  (the extractor of the file: DRIVER `enc`, the same encoding `rowline` builds).
- Guards, both sides non-empty and through one extractor: swipl lines match `^t_actN c[..]/1(a[..])$` and end in `(a[101,114,114,111,114])`
  (= `error`); `@test kl == sw[2:end]` (:939) compares the kernel's `rowline` strings to swipl's.
- Expected value from swipl, not hand-written: the pin binary answered `max_incomplete_subgoals_action=error` and
  `max_scc_subgoals_action=error` twice, identically (also the other three `*_action` flags are in the loop, same gap, no mutant of
  theirs in PIN1).
- `_SWIPL === nothing` only skips the swipl half (`@test true`); the `f !== nothing && FT_ATOM` row still runs.

## Mutation proof by reasoning (verdict level; NOT run: row not yet run on a lane)
- PIN1-I1 (src/os/pl-prologflag.jl:1943 `"error"` -> `"warning"`): `current_prolog_flag(gd, "max_incomplete_subgoals_action").a` is
  the atom `warning`; `rowline` gives `t_act4 c[116,95,97,99,116,52]/1(a[119,97,114,110,105,110,103])`, swipl's is
  `... (a[101,114,114,111,114])`: `@test kl == sw[2:end]` at TP:939 fails.
- PIN1-I2 (:1945, same change): row t_act5 differs the same way; TP:939 fails.
- Baseline (unmutated): `f.a` = `error` on all five, equal to swipl's: passes. Non-vacuity: if the flag were undefined the kernel line
  is the string "undefined" and the first @test (`f !== nothing`) fails.
- PIN1.py: the kill claims of I1 and I2 now name TP:939; TARGETS (TF = TP, TS, TD) already contains TP, unchanged.

## What must run on a lane (not yet run)
1. `tools/warm.sh file test/core_lang/test_prolog_flag_swipl.jl` on all three term types (swipl on PATH: the pin, 10.1.20 at ~/.local/bin/swipl; STATUS names ~/.local/swipl-pin1-18168e62/bin).
2. Format check (`tools/warm.sh fmt`): the file was wrapped by hand to margin 92 (long comments and the testset title string are as elsewhere).
3. `tools/pkgtest_way.sh test/core_lang/test_prolog_flag_swipl.jl` (changed test file, D-0245).
4. PIN1 I1 and I2 hand-run on one lane (one mutant, TARGETS TP) must end FAILED (killed); I3-I5, V1-V6, C1-C2 unaffected by an appended testset.

## RUN ON LANE 2 (wip/tab1-mono 7bf45b4d, 2026-11-15, Julia 1.13.3, swipl 10.1.20)
1. `tools/warm.sh file test/core_lang/test_prolog_flag_swipl.jl`, three types, unmutated: reference 483/483, alt 483/483, alt_interned 483/483
   (1449/1449 total); grep `SKIP|Warning|Test Failed|Error During` = 0 lines. The new row passes unmutated.
2. Hand-run through the WARM DAEMON (`tools/mutate.sh run-in-tree tools/mutants/PIN1.py <TP> -- PIN1-I1 PIN1-I2`, reference): BOTH SURVIVED
   (TP, TS, TD all 483/117/117 pass under each mutant; no revise error). CAUSE: `PL_global_data{T}()` is a COPY of a booted per-process template
   (src/gd_template.jl `PL_global_data_from_template`, `_GD_TEMPLATES`, built once per process and type); `_init_tabling_flags!` runs only
   when the template is booted, and the daemon booted it before the mutant was revised in. So the daemon cannot see a mutant of any
   flag-start line read through a fresh `PL_global_data`. This is a property of the warm daemon, not of the row.
3. Hand-run in a FRESH process, the way CI's battery runs a target (`LOGICKERNEL_TERM=reference julia --project=. test/core_lang/test_prolog_flag_swipl.jl`,
   swipl 10.1.20 on PATH; mutate.sh run-in-tree with a copy of PIN1.py whose `TF` is that `sh:` target, kept outside the tree):
   baseline exit 0; PIN1-I1 caught: `Test Failed at test/core_lang/test_prolog_flag_swipl.jl:939`; PIN1-I2 caught: `Test Failed at test/core_lang/test_prolog_flag_swipl.jl:939`;
   final baseline exit 0; "SUMMARY 2 of 2 caught; 0 blocking". `git diff --stat` empty after both (tree restored).
   The failing testset: `the start value of the *_action restraint flags, off the flag, == swipl (PIN1-I1, PIN1-I2)`.
4. `tools/pkgtest_way.sh test/core_lang/test_prolog_flag_swipl.jl`: passed the way Pkg.test runs it (peak 1984 MiB, oom_kill 0; no swipl there, so the swipl half is `@test true`).
NOTE for any local re-run of I1/I2: use a fresh process (item 3), not the warm file target; CI's battery (tools/mutate_ci.py) runs a fresh process per target.
