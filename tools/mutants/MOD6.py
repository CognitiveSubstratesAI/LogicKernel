# ORIGINAL: MOD6's mutant list — no swipl-devel counterpart.
# tools/mutants/MOD6.py — the mutation battery of MOD6 (the module enumerations: pl-modul.c import_module (876-918),
# current_module = '$current_module'/2 (983-1075), get_existing_source_file (952), newModuleEnum (242), advanceModuleEnum (260),
# freeModuleEnum (289); the registration of both predicates; `live_states`' module_enums term), run ONCE, in CI
# (.github/workflows/mutation.yml; locally: tools/mutate.sh run).
# Format: tools/mutate_drive.py's (as MOD5b.py): `id`, `file`, `old` (must occur EXACTLY once), `new`, optional `equivalent`
# and `targets`. Killed by test/core_lang/test_module_enum_swipl.jl (rows s01, i01-i20, c01-c19, d01, d03-d05 and the testsets
# "non-vacuity", "FRG_CUTTED", "H3" named in each id's KILL). Verdicts: written by the battery, not yet run.
# The `old` strings are written in the repo's formatted style BEFORE `tools/warm.sh fmt` ran (the coding agent had no daemon):
# the anchors need a RE-FIT at the first battery run for any that fmt re-flows (a long registration line and a trailing comment
# are the likely ones; mutate_drive.py refuses a string that does not occur exactly once). Every `old` was checked to occur
# exactly once in its file at the commit that adds this file (a text count, no Julia).
# TARGETS (audit D-0238): import_module/2 and '$current_module'/2 are called from test_module_enum_swipl.jl; import_module also
# from test_module_swipl.jl (the file test_module_swipl_rows.pl is its data); no other test file names '$current_module'
# (git grep over test/). The L1 mutant (live_states) is exercised by every file that reads live_states.
# EQUIVALENTS (each with its reason in the entry): the FRG_CUTTED value (discarded by discardForeignFrame, src/pl-wam.jl);
# the dropped `ok || return` (an unknown file name then reaches the enumeration, whose first unify of an unknown file fails and
# ends it by the `break`: the same FFALSE); `break` -> `continue` (a failed unify of a non-atom module or file fails on every
# module: the same FFALSE); the `en.current = 0` of freeModuleEnum (the next newModuleEnum sets it again).
# SURVIVORS TO EXPECT (no row; the gate agent adds one): MOD6-I5 (a BOUND second argument with several supers: rows i11, i12 read the
# answer only, none the determinism: a row `mme_det(import_module(mmx_c2, mmx_u), D)` kills it) and MOD6-C6 (a module argument
# that is the empty list `[]` with a multi-module file: a row `'$current_module'([], '/mmx/g.pl')` kills it).
# NOT LISTED: the registration ORDER (upstream's: import_module first, $current_module after set_module): the order of the
# predicate table is read by no row; SYSTEM_MODE(ld) flipped: the access level cannot be set to `system` yet (no row).
M = "src/pl-modul.jl"
FLI = "src/pl-fli.jl"
E = "test/core_lang/test_module_enum_swipl.jl"
TS = [E, "test/core_lang/test_module_swipl.jl"]                  # import_module/2
TS_C = [E]                                                        # '$current_module'/2 and the module_enum functions
TS_LIVE = [
    E,
    "test/core_lang/test_between_swipl.jl",
    "test/core_lang/test_current_op_swipl.jl",
    "test/core_lang/test_prolog_flag_swipl.jl",
    "test/core_lang/test_repeat_swipl.jl",
    "test/db/test_clause_swipl.jl",
    "test/db/test_retract_swipl.jl",
]
TARGETS = TS_C + ["test/core_lang/test_module_swipl.jl"]          # the baseline's (mutate_ci.py plan reads TARGETS)
MUTANTS = [
    # ── import_module/2 (pl-modul.c:876-918) ──
    dict(id="MOD6-I1 import_module answers with every super at once: `n == i` always true (KILL i01, i05, i09: the first answer is the last super)",
         file=M, targets=TS,
         old="        if n == i\n",
         new="        if true\n"),
    dict(id="MOD6-I3 import_module leaves a choice point after the last super: `n + 1 <= length` (KILL i10: mme_det says nondet for one super)",
         file=M, targets=TS,
         old="ndet = n + 1 < length(supers) && PL_is_variable(ld, A2)",
         new="ndet = n + 1 <= length(supers) && PL_is_variable(ld, A2)"),
    dict(id="MOD6-I4 import_module never leaves a choice point: findall sees the first super only (KILL i09, i19)",
         file=M, targets=TS,
         old="ndet = n + 1 < length(supers) && PL_is_variable(ld, A2)",
         new="ndet = false"),
    dict(id="MOD6-I5 import_module leaves the choice point also for a bound second argument (KILL none yet: needs a determinism row; see header)",
         file=M, targets=TS,
         old="ndet = n + 1 < length(supers) && PL_is_variable(ld, A2)",
         new="ndet = n + 1 < length(supers)"),
    dict(id="MOD6-I6 import_module retries at the wrong index: PL_retry(i + 2) skips a super (KILL i09, i19)",
         file=M, targets=TS,
         old="ndet && return PL_retry(i + 1)",
         new="ndet && return PL_retry(i + 2)"),
    dict(id="MOD6-I7 import_module starts at the second super (KILL i01, i05, i17)",
         file=M, targets=TS,
         old="    if ctl == FRG_FIRST_CALL\n        i = 0\n",
         new="    if ctl == FRG_FIRST_CALL\n        i = 1\n"),
    dict(id="MOD6-I8 import_module does not make a module it has not seen: create flag false (KILL i03)",
         file=M, targets=TS,
         old="    m = get_module(gd, ld, A1, true)\n    m === nothing && return FFALSE\n\n    supers = m.supers",
         new="    m = get_module(gd, ld, A1, false)\n    m === nothing && return FFALSE\n\n    supers = m.supers"),
    dict(id="MOD6-I9 import_module's FRG_CUTTED call fails instead of succeeding (EQUIVALENT: the value is discarded)",
         file=M, targets=TS,
         old="return FTRUE                                    # FRG_CUTTED: succeed",
         new="return FFALSE                                   # FRG_CUTTED: succeed",
         equivalent="discardForeignFrame (src/pl-wam.jl:1142) calls the function and returns `nothing`; the value of a FRG_CUTTED call is never read"),
    # ── '$current_module'/2: module -> file, file -> module(s) ──
    dict(id="MOD6-C1 the file of a module is [] when it has one, the file name when it has none (KILL c01, c02)",
         file=M, targets=TS_C,
         old="f = cm.file == 0 ? mk_nil(T) : gd.files_array[cm.file].name",
         new="f = cm.file != 0 ? mk_nil(T) : gd.files_array[max(cm.file, 1)].name"),
    dict(id="MOD6-C2 the module -> file mode succeeds without unifying the file (KILL c04)",
         file=M, targets=TS_C,
         old="return PL_unify_atom(ld, file, f) ? FTRUE : FFALSE",
         new="return FTRUE"),
    dict(id="MOD6-C4 a file that is no source file goes on to the enumeration (EQUIVALENT: the first unify fails, `break`, FFALSE)",
         file=M, targets=TS_C,
         old="        ok || return FFALSE ",
         new="        ok || nothing ",
         equivalent="with the second argument an unknown file atom the enumeration unifies it with the first module's file (an existing file or []), fails, and ends by the `break`: FFALSE, the same answer; the pool is freed on that path"),
    dict(id="MOD6-C5 a file with one module answers a list (KILL c05, c06)",
         file=M, targets=TS_C,
         old="if length(sf.modules) > 1",
         new="if length(sf.modules) >= 1"),
    dict(id="MOD6-C6 a list that does not unify with the file's modules is not failed (KILL none yet: needs a `[]` module row; see header)",
         file=M, targets=TS_C,
         old="rc = false                  # goto out",
         new="nothing                     # goto out"),
    dict(id="MOD6-C7 the list of modules is left open: no closing of the tail with [] (KILL c06, c07)",
         file=M, targets=TS_C,
         old="rc && (rc = PL_unify_nil(ld, tail))",
         new="rc"),
    # ── '$current_module'/2: the enumeration ──
    dict(id="MOD6-C8 the `system` module is hidden with the other system-class modules (KILL c13)",
         file=M, targets=TS_C,
         old="m.name != system &&",
         new=""),
    dict(id="MOD6-C9 a failed unify of the answer pair goes on to the next module (EQUIVALENT: every module fails alike)",
         file=M, targets=TS_C,
         old="break                                           # must be an error",
         new="continue                                        # must be an error",
         equivalent="the enumeration runs only for a module that is no atom and a file that is no source-file atom or is unbound; a non-atom, non-variable argument unifies with no module atom or file atom, so every module fails and the loop ends in the same FFALSE (the state is freed after the loop)"),
    dict(id="MOD6-C10 the enumeration ends after its first answer: PL_retry_address(k) replaced by success (KILL c11, c12, c15)",
         file=M, targets=TS_C,
         old="return PL_retry_address(k)",
         new="return FTRUE"),
    dict(id="MOD6-C11 FRG_CUTTED does not free the state: a cut leaves the pool record live (KILL c17, c18 live_states, FRG_CUTTED testset)",
         file=M, targets=TS_C,
         old="        freeModuleEnum(gd, ld, k)\n        return FTRUE",
         new="        return FTRUE"),
    dict(id="MOD6-C12 an exhausted enumeration leaves its state live (KILL c11, c19 live_states)",
         file=M, targets=TS_C,
         old="    freeModuleEnum(gd, ld, k)\n    return FFALSE",
         new="    return FFALSE"),
    dict(id="MOD6-C13 the enumeration lists the temporary modules: newModuleEnum(ld, MENUM_TEMP) (KILL c14, d01, d03)",
         file=M, targets=TS_C,
         old="k = newModuleEnum(ld, 0)",
         new="k = newModuleEnum(ld, MENUM_TEMP)"),
    dict(id="MOD6-C14 the enumeration answers every module's file as [] (flips the nil test) (KILL c12)",
         file=M, targets=TS_C,
         old="f = m.file == 0 ? mk_nil(T) : gd.files_array[m.file].name",
         new="f = m.file != 0 ? mk_nil(T) : gd.files_array[max(m.file, 1)].name"),
    dict(id="MOD6-C15 the enumeration does not unify the file of the answer (KILL c10, c12)",
         file=M, targets=TS_C,
         old="PL_unify_atom(ld, module_, m.atom) && PL_unify_atom(ld, file, f)",
         new="PL_unify_atom(ld, module_, m.atom)"),
    # ── get_existing_source_file (pl-modul.c:952) ──
    dict(id="MOD6-G1 a term that is no atom is refused as a source file (KILL c11, c12: the unbound file ends every enumeration)",
         file=M, targets=TS_C,
         old="return (true, nothing)                              # *sfp = NULL",
         new="return (false, nothing)                             # *sfp = NULL"),
    # ── newModuleEnum, advanceModuleEnum, freeModuleEnum ──
    dict(id="MOD6-N1 a new enumeration starts where a freed state stopped: `en.next = 1` dropped (KILL c11, c12 after an earlier enumeration)",
         file=M, targets=TS_C,
         old="    en.next = 1\n",
         new="    nothing\n"),
    dict(id="MOD6-A1 the walk lists a destroyed module's record (KILL d03, d04, d05, H3)",
         file=M, targets=TS_C,
         old="get(table.names, c.name, 0) == c.index && (i = c.index)",
         new="(i = c.index)"),
    dict(id="MOD6-A2 the walk lists a temporary module without MENUM_TEMP (KILL c14, d03, H3)",
         file=M, targets=TS_C,
         old="(en.flags & MENUM_TEMP) == 0 && continue",
         new="(en.flags & MENUM_TEMP) != 0 && continue"),
    dict(id="MOD6-A3 the walk references no temporary module it holds (KILL H3: references == r0 + 1)",
         file=M, targets=TS_C,
         old="            m.references += 1\n            if en.current != 0",
         new="            if en.current != 0"),
    dict(id="MOD6-A4 the walk keeps the previous temporary module's reference (KILL H3: the reference is released when it moves on)",
         file=M, targets=TS_C,
         old="                sym_key(cur.class) == temporary && releaseModule_unlocked(gd, ld, cur)",
         new="                nothing"),
    dict(id="MOD6-F1 freeModuleEnum keeps the held temporary module's reference (KILL H3: t4.references)",
         file=M, targets=TS_C,
         old="        sym_key(cur.class) == sym_key(mk_sym(T, :temporary)) &&\n            releaseModule_unlocked(gd, ld, cur)\n",
         new="        nothing\n"),
    dict(id="MOD6-F2 freeModuleEnum does not return the record to the pool (KILL c11, c17, FRG_CUTTED testset: live_states)",
         file=M, targets=TS_C,
         old="free_foreign_state!(pool, k)",
         new="nothing"),
    dict(id="MOD6-F3 freeModuleEnum leaves `current` set (EQUIVALENT: newModuleEnum sets it again)",
         file=M, targets=TS_C,
         old="        en.current = 0\n    end\n    free_foreign_state!",
         new="    end\n    free_foreign_state!",
         equivalent="a freed record is read again only through newModuleEnum, whose `en.current = 0` resets it before any use"),
    # ── live_states, the registrations ──
    dict(id="MOD6-L1 live_states does not count the module_enums pool (KILL FRG_CUTTED testset: live_states == 1 mid-enumeration)",
         file=FLI, targets=TS_LIVE,
         old="ld.prolog_flag_enums.live + ld.module_enums.live",
         new="ld.prolog_flag_enums.live"),
    dict(id="MOD6-R1 import_module/2 registered deterministic (KILL i09, i19)",
         file=M, targets=TS,
         old='PL_extension("import_module", 2, pl_import_module2_va, PL_FA_NONDETERMINISTIC | PL_FA_VARARGS)',
         new='PL_extension("import_module", 2, pl_import_module2_va, PL_FA_VARARGS)'),
    dict(id="MOD6-R2 '$current_module'/2 registered deterministic (KILL c11, c12)",
         file=M, targets=TS_C,
         old='"\\$current_module", 2, pl_current_module2_va, PL_FA_NONDETERMINISTIC | PL_FA_VARARGS',
         new='"\\$current_module", 2, pl_current_module2_va, PL_FA_VARARGS'),
]
