# ORIGINAL: PIN1's mutant list — no swipl-devel counterpart.
# tools/mutants/PIN1.py — the mutation battery of the kernel changes of PIN1 (the pin bump to swipl-devel V10.1.20, 18168e62; audit D-0444
# item 2): the `validate_api` flag and its mask bit PLFLAG_VALIDATE_API (src/os/pl-prologflag.c:2695-2700, src/pl-incl.h:2936), the two tabling flag
# pairs of the incomplete-subgoal and SCC tripwires (the `*_action` flags and the sizes) defined by `_init_tabling_flags!` (src/pl-tabling.c:12709-12712 initTabling) and named by
# `tbl_is_restraint_flag` (pl-tabling.c:11693; `_tbl_restraint_unlimited`, pl-prologflag.jl:412, is the kernel's reader-side list), and ATOM_RESERVE_BATCH (src/pl-incl.h:1431). Run ONCE, in CI
# (.github/workflows/mutation.yml; locally: tools/mutate.sh run). Format: tools/mutate_drive.py's (as HF1.py): `id`, `file`, `old` (must occur
# EXACTLY once), `new`, optional `equivalent` and `targets`. The flags are kernel code under test: this list pins what is there at gate/pin1r (36a90cbb).
# Each id names its KILL, the assertion that must fail (file:line at gate/pin1r):
#   TP = test/core_lang/test_prolog_flag_swipl.jl, TS = test/core_lang/test_set_flag_swipl.jl, TL7 = test/core_lang/test_lb7_swipl.jl,
#   TAT = test/core_lang/test_atom_table.jl.
#   TP:260 is the oracle differential (`t_defaults`, `t_enum_*`, `t_missing`, `t_e37`, `t_e38` of test_prolog_flag_swipl.pl against swipl on PATH:
#   the V10.1.20 oracle must be on PATH or the testset is `@test true`); TP:292/294 the key-set differential (oracle too); TP:305 oracle too;
#   TP:534, 545, 547, 637 and TS:599, TL7:369, TAT:208 need no oracle.
# VERDICTS (2026-11-09, audit D-0451 item 1): the 19 kill rows below are FRESH-PROCESS verdicts (`tools/mutate_ci.py one`, one process per mutant, reference type);
# the warm daemon cannot judge a mutant of boot-path code (`PL_global_data{T}()` copies the template built once per process, src/gd_template.jl): V1-V4 survive
# there and I5/T3/T4 are caught there by a template a revised module left poisoned. The CI mutation battery runs fresh processes and decides.
# DEFERRED KILL (audit D-0374 item 2): a row declared `equivalent="DEFERRED KILL: ..."` has no killing assertion yet — no test file reads what the
# mutant changes (a finding for a test step, not invented here). It must SURVIVE the battery; when a test step adds the row, the declaration goes.
#   * PIN1-V5: apply_options_to_flags!'s `validate_api` entry (src/pl-init.jl:659): test_lb7_swipl.jl's `lb7_flagnames` (line 52) lacks `validate_api`,
#     so neither the `-O` row f02 (TL7:402) nor any row reads it after the options are applied.
#   * PIN1-I5: the size flags' -1 default: `unify_prolog_flag_value` (pl-prologflag.jl:486, `_tbl_restraint_unlimited`) answers false before `f.i` is read, and TP:305 only asks `!== nothing`.
#   * PIN1-T3, PIN1-T4: set_prolog_flag/2 on `max_incomplete_subgoals_action` / `max_scc_subgoals_action`: `_SF_REFUSED` (TS:576-585, since TAB1 TB0; run at TS:593-601, the @test_throws at TS:599) names no
#     `*_action` flag, not the three of the old pin either. TB0 (wip/tb0) shifts src/os/pl-prologflag.jl by +17 lines above `tbl_is_restraint_flag` (now :1461, the refusal at :1534-1535); I5's lines (:412, :486, TP:302-305) did not move.
# OWNERS (audit D-0446 item 2, PIN1 step C; D-0451 item 2): the step that gives the flag or constant its consumer. V5 = FLI1 (the validateAPI gate); I5, T3, T4 = TAB1 (restraint
# checks and tripwire actions); the reader of ATOM_RESERVE_BATCH = ATOM1 (R1, R2 are PLAIN mutants of the VALUE, killed by the literal row of test_atom_table.jl; a mutant of a READER of the constant has nothing to mutate until ATOM1 ports `reserveAtomSlots`, fde0211d: that gap is ATOM1's, not a row of this list). None of V5, I5, T3, T4 has a flag: row in docs/r2_owners.tsv (the flags are set, so a row would be R2-OWNER-STALE):
# the owner is named here and in docs/architecture.md (PIN1 step C).
# TARGETS (audit D-0238): every test file that runs the mutated code and can see its effect. The flag rows list the three files of F1c's list
# (HF1.py: TD, TS, TP — each reads or sets flags through the changed tables); the `apply_options_to_flags!` rows list the two files that call it
# (test_lb7_swipl.jl, test_firstboot_swipl.jl); the constant rows list TP (the mask testset) and the table's own file; ATOM_RESERVE_BATCH lists
# test_atom_table.jl, the atom table's file. NOT listed: test_gd_template.jl (digests a template against its copy, both mutated alike),
# test_push_flag_swipl.jl (one non-tabling flag), test_boot_image_swipl.jl (boot-module predicate rows, no flag value).
# Every `old` was counted EXACTLY once in its file at gate/pin1r by a python3 -I script (no Julia ran). RE-FIT any `old` that `tools/warm.sh fmt` rewraps.
TP = "test/core_lang/test_prolog_flag_swipl.jl"
TS = "test/core_lang/test_set_flag_swipl.jl"
TD = "test/core_lang/test_debug_flag_swipl.jl"
TL7 = "test/core_lang/test_lb7_swipl.jl"
TFB = "test/core_lang/test_firstboot_swipl.jl"
TAT = "test/core_lang/test_atom_table.jl"
TF = [TP, TS, TD]
TAB = "src/pl-tabling.jl"
TG = "test/core_lang/test_tabling_sdg_swipl.jl"
TARGETS = TF + [TL7, TFB, TAT]               # the baseline's targets (mutate_ci.py plan reads TARGETS): every file a mutant lists
P = "src/os/pl-prologflag.jl"
INI = "src/pl-init.jl"
INC = "src/pl-incl.jl"
MUTANTS = [
    # ── the validate_api flag (pl-prologflag.c:2695-2700): initPrologFlags! ──
    dict(id="PIN1-V1 validate_api starts false, not `!optimise` (KILL TP:260: t_defaults and t_enum_true read it as swipl's `true`)",
         file=P, targets=TF,
         old='    setPrologFlag(gd, "validate_api", FT_BOOL, !gd.cmdline.optimise, PLFLAG_VALIDATE_API)\n',
         new='    setPrologFlag(gd, "validate_api", FT_BOOL, gd.cmdline.optimise, PLFLAG_VALIDATE_API)\n'),
    dict(id="PIN1-V2 validate_api owns no mask bit (KILL TP:547: the owned bits are the bits less the three atom flags, and bit 37 has no flag)",
         file=P, targets=TF,
         old='    setPrologFlag(gd, "validate_api", FT_BOOL, !gd.cmdline.optimise, PLFLAG_VALIDATE_API)\n',
         new='    setPrologFlag(gd, "validate_api", FT_BOOL, !gd.cmdline.optimise, 0)\n'),
    dict(id="PIN1-V3 validate_api owns the bit of `epilog`, not its own (KILL TP:545: two flags share bit 36; TP:547 too)",
         file=P, targets=TF,
         old='    setPrologFlag(gd, "validate_api", FT_BOOL, !gd.cmdline.optimise, PLFLAG_VALIDATE_API)\n',
         new='    setPrologFlag(gd, "validate_api", FT_BOOL, !gd.cmdline.optimise, PLFLAG_EPILOG)\n'),
    dict(id="PIN1-V4 validate_api is read-only (upstream's `#else` of O_VALIDATE_API has FF_READONLY) (KILL TP:260: t_enum_read, t_enum_write and t_defaults' access column)",
         file=P, targets=TF,
         old='    setPrologFlag(gd, "validate_api", FT_BOOL, !gd.cmdline.optimise, PLFLAG_VALIDATE_API)\n',
         new='    setPrologFlag(gd, "validate_api", FT_BOOL | FF_READONLY, !gd.cmdline.optimise, PLFLAG_VALIDATE_API)\n'),
    # ── the validate_api flag: apply_options_to_flags! (pl-prologflag.c:2695-2698 reads `GD->cmdline.optimise`) ──
    dict(id="PIN1-V5 the options write validate_api as `optimise`, not `!optimise` (no row: DEFERRED KILL, lb7_flagnames lacks validate_api)",
         file=INI, targets=[TL7, TFB],
         equivalent="DEFERRED KILL: owner FLI1 (the validateAPI gate of pl-fli.c is the flag's consumer; docs/r2_owners.tsv has no flag: row for it, FLI1 named by PIN1 step C); no test reads validate_api after the options are applied: test_lb7_swipl.jl:52 (lb7_flagnames) and its -O rows f02/f01 (TL7:402-403, which pin `optimise`) do not name it, and neither test_firstboot_swipl.jl nor test_prolog_flag_swipl.jl names validate_api or optimise (the mutated entry is src/pl-init.jl:659)",
         old='        ("validate_api", PLFLAG_VALIDATE_API, !cmd.optimise)\n',
         new='        ("validate_api", PLFLAG_VALIDATE_API, cmd.optimise)\n'),
    dict(id="PIN1-V6 the options' validate_api entry writes the mask bit of `signals` (KILL TL7:369: rows f05 and f02 pin `signals` as swipl's false/true, the entry sets the local data's bit after the signals entry)",
         file=INI, targets=[TL7, TFB],
         old='        ("validate_api", PLFLAG_VALIDATE_API, !cmd.optimise)\n',
         new='        ("validate_api", PLFLAG_SIGNALS, !cmd.optimise)\n'),
    # ── PLFLAG_VALIDATE_API (pl-incl.h:2936, the 37th of enum plflag) ──
    dict(id="PIN1-C1 PLFLAG_VALIDATE_API is 36, the bit of `epilog` (KILL TP:534: the bits are 1..37; TP:545 too)",
         file=INC, targets=TF,
         old="const PLFLAG_VALIDATE_API = 37\n",
         new="const PLFLAG_VALIDATE_API = 36\n"),
    dict(id="PIN1-C2 PLFLAG_VALIDATE_API is 38 (KILL TP:534: the bits are 1..37, the enum has 37 members)",
         file=INC, targets=TF,
         old="const PLFLAG_VALIDATE_API = 37\n",
         new="const PLFLAG_VALIDATE_API = 38\n"),
    # ── _init_tabling_flags! (pl-tabling.c:12709-12712) ──
    dict(id="PIN1-I1 max_incomplete_subgoals_action starts as `warning`, not `error` (KILL TP:260: t_defaults and t_enum_error read swipl's `error`)",
         file=P, targets=TF,
         old='    setPrologFlag(gd, "max_incomplete_subgoals_action", FT_ATOM, "error")\n',
         new='    setPrologFlag(gd, "max_incomplete_subgoals_action", FT_ATOM, "warning")\n'),
    dict(id="PIN1-I2 max_scc_subgoals_action starts as `warning`, not `error` (KILL TP:260: t_defaults and t_enum_error read swipl's `error`)",
         file=P, targets=TF,
         old='    setPrologFlag(gd, "max_scc_subgoals_action", FT_ATOM, "error")\n',
         new='    setPrologFlag(gd, "max_scc_subgoals_action", FT_ATOM, "warning")\n'),
    dict(id="PIN1-I3 max_incomplete_subgoals is not defined (KILL TP:637: eight defined flags do not answer, seven do; TP:305 too)",
         file=P, targets=TF,
         old='    setPrologFlag(gd, "max_incomplete_subgoals", FT_INTEGER, -1)\n',
         new="    nothing\n"),
    dict(id="PIN1-I4 max_scc_subgoals_action is not defined (KILL TP:292: swipl's keys less the kernel's are no longer the pinned list; TP:260 t_missing, t_count)",
         file=P, targets=TF,
         old='    setPrologFlag(gd, "max_scc_subgoals_action", FT_ATOM, "error")\n',
         new="    nothing\n"),
    dict(id="PIN1-I5 max_scc_subgoals starts as 0, not -1 (no row: DEFERRED KILL, the unlimited reader answers before the value)",
         file=P, targets=TF,
         equivalent="DEFERRED KILL: owner TAB1 (the restraint check of tabling reads the size flags; docs/r2_owners.tsv has no flag: row for max_scc_subgoals, TAB1 named by PIN1 step C); unify_prolog_flag_value answers false for the unlimited sizes at src/os/pl-prologflag.jl:486 (_tbl_restraint_unlimited, defined :412, lists max_scc_subgoals) before it reads f.i, (lines re-read at wip/tb0 6d4bc882: unchanged by TB0) and no test reads the table's `i` of max_scc_subgoals: test_prolog_flag_swipl.jl:302-305 asks only `current_prolog_flag(gd, k) !== nothing` and TP:637 only counts keys",
         old='    setPrologFlag(gd, "max_scc_subgoals", FT_INTEGER, -1)\n',
         new='    setPrologFlag(gd, "max_scc_subgoals", FT_INTEGER, 0)\n'),
    # ── tbl_get_restraint_flag (pl-tabling.c: the sizes answer nothing at (size_t)-1; U1-U4 re-fitted by the TB8 merge, which replaced the
    #    stand-in `_tbl_restraint_unlimited`: the kill claims below are the stand-in's, UNVERIFIED on the new code) ──
    dict(id="PIN1-U1 max_incomplete_subgoals is no longer an unlimited size: it answers -1 (KILL TP:637: keys1 is one longer; TP:260 t_e37; TP:305 and TP:303 oracle)",
         file=TAB, targets=TF + [TG],
         old='    elseif _tbl_is(key, :max_incomplete_subgoals)\n        return unify_restraint(ld, t, r.max_incomplete_subgoals)\n',
         new='    elseif _tbl_is(key, :max_incomplete_subgoals)\n        return PL_unify_int64(ld, t, r.max_incomplete_subgoals)\n'),
    dict(id="PIN1-U2 max_scc_subgoals is no longer an unlimited size: it answers -1 (KILL TP:637: keys1 is one longer; TP:260 t_e38; TP:305 and TP:303 oracle)",
         file=TAB, targets=TF + [TG],
         old='    elseif _tbl_is(key, :max_scc_subgoals)\n        return unify_restraint(ld, t, r.max_scc_subgoals)\n',
         new='    elseif _tbl_is(key, :max_scc_subgoals)\n        return PL_unify_int64(ld, t, r.max_scc_subgoals)\n'),
    dict(id="PIN1-U3 max_scc_subgoals_action is read as an unlimited size: no answer (KILL TP:637: keys1 is one shorter; TP:260 t_defaults, t_missing, t_count)",
         file=TAB, targets=TF + [TG],
         old='        return PL_unify_atom(ld, t, r.max_scc_subgoals_action)\n',
         new='        return false\n'),
    dict(id="PIN1-U4 no flag is an unlimited size: every one of the eight answers its -1 (KILL TP:637: keys1 is eight longer; TP:260 t_e37, t_e38)",
         file=P, targets=TF,
         old="    elseif tbl_is_restraint_flag(key)                   # pl-prologflag.c:2127\n        return tbl_get_restraint_flag(ld, val, key)\n",
         new="    elseif false\n        return tbl_get_restraint_flag(ld, val, key)\n"),
    # ── tbl_is_restraint_flag (pl-tabling.c:11693): set_prolog_flag/2 refuses them as NotPortedError ──
    dict(id="PIN1-T1 max_incomplete_subgoals is no restraint flag: set_prolog_flag/2 is not refused (KILL TS:599: row (max_incomplete_subgoals, 5) of _SF_REFUSED)",
         file=P, targets=[TS, TP],
         old='           name == "max_incomplete_subgoals" ||\n           name == "max_incomplete_subgoals_action" ||\n',
         new='           name == "max_incomplete_subgoals_action" ||\n'),
    dict(id="PIN1-T2 max_scc_subgoals is no restraint flag: set_prolog_flag/2 is not refused (KILL TS:599: row (max_scc_subgoals, 5) of _SF_REFUSED)",
         file=P, targets=[TS, TP],
         old='           name == "max_scc_subgoals" ||\n           name == "max_scc_subgoals_action"\nend\n',
         new='           name == "max_scc_subgoals_action"\nend\n'),
    dict(id="PIN1-T3 max_incomplete_subgoals_action is no restraint flag (no row: DEFERRED KILL, _SF_REFUSED names no *_action flag)",
         file=P, targets=[TS, TP],
         equivalent="DEFERRED KILL: owner TAB1 (the tripwire action of tabling reads max_incomplete_subgoals_action; no flag: row in docs/r2_owners.tsv, TAB1 named by PIN1 step C); test_set_flag_swipl.jl:576-585 (_SF_REFUSED, run at TS:593-601, the @test_throws at TS:599) holds no `*_action` flag, none of the three of the old pin either, and neither TS nor TP sets max_incomplete_subgoals_action: the refusal at src/os/pl-prologflag.jl:1534-1535 (tbl_is_restraint_flag, defined :1461) is never reached for it",
         old='           name == "max_incomplete_subgoals_action" ||\n           name == "max_scc_subgoals" ||\n',
         new='           name == "max_scc_subgoals" ||\n'),
    dict(id="PIN1-T4 max_scc_subgoals_action is no restraint flag (no row: DEFERRED KILL, _SF_REFUSED names no *_action flag)",
         file=P, targets=[TS, TP],
         equivalent="DEFERRED KILL: owner TAB1 (as PIN1-T3); no row sets max_scc_subgoals_action: test_set_flag_swipl.jl:576-585 (_SF_REFUSED, @test_throws at TS:599) names none, so the refusal at src/os/pl-prologflag.jl:1534-1535 is never reached for it",
         old='           name == "max_scc_subgoals" ||\n           name == "max_scc_subgoals_action"\nend\n',
         new='           name == "max_scc_subgoals"\nend\n'),
    # ── ATOM_RESERVE_BATCH (pl-incl.h:1431: 64) ──
    dict(id="PIN1-R1 ATOM_RESERVE_BATCH is 63 (KILL TAT:208: the literal row `LK.ATOM_RESERVE_BATCH == 64`)",
         file=INC, targets=[TAT],
         old="const ATOM_RESERVE_BATCH = 64\n",
         new="const ATOM_RESERVE_BATCH = 63\n"),
    dict(id="PIN1-R2 ATOM_RESERVE_BATCH is 0 (KILL TAT:208: the literal row `LK.ATOM_RESERVE_BATCH == 64`)",
         file=INC, targets=[TAT],
         old="const ATOM_RESERVE_BATCH = 64\n",
         new="const ATOM_RESERVE_BATCH = 0\n"),
]
