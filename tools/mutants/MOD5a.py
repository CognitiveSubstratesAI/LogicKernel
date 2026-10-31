# ORIGINAL: MOD5a's mutant list — no swipl-devel counterpart.
# tools/mutants/MOD5a.py — the mutation battery of MOD5a (export and import: pl-modul.c exportProcedure, export_pi1, export_pi,
# fixExport, fixExportModule, atomToImportStrength, import, undefined_export, find_modules_with_defs, def_modules, the registration
# flags of export/1, import/1, '$import'/2; pl-proc.c get_functor, shareDefinition, unshareDefinition, autoImport's share count;
# pl-error.c ERR_IMPORT_PROC), run ONCE, in CI (.github/workflows/mutation.yml; locally: tools/mutate.sh run).
# Format: tools/mutate_drive.py's (as MOD3b.py): `id`, `file`, `old` (must occur EXACTLY once), `new`, optional `equivalent`
# and `targets`. Killed by test/core_lang/test_export_import_swipl.jl (rows e01-e25, u01-u06, d01-d20, i01-i17, w01-w09 named in
# each id's KILL; "sh" is the testset of the definition->shared counts, "F5" the weak-import testset). Verdicts: written by the
# battery, not yet run.
# The `old` strings are written in the repo's formatted style BEFORE `tools/warm.sh fmt` ran (the coding agent had no
# daemon): RE-FIT any that fmt rewraps at the first battery run (mutate_drive.py refuses a string that does not occur exactly
# once). Every `old` was checked to occur exactly once in the source at wip/mod5a 8fb2b57 (a text count, no Julia).
# NOT LISTED (each with its reason):
#   * isPublicModule and the `import_private` warning (`if !isPublicModule(source, proc)`): the warning is printed, not an
#     answer — swipl's goes to stderr and the kernel's to `ld.messages`, which no row reads. A mutant of it would survive.
#     LATER: a white-box on `ld.messages`.
#   * The `ignored_weak_import` warning (`truePrologFlag(ld, PLFLAG_WARN_OVERRIDE_IMPLICIT_IMPORT)`) and the message term of
#     ERR_IMPORT_PROC (`already_from`, `old`): messages in the error CONTEXT; the rows compare the formal only.
#   * export_pi's depth counter (`depth += 1`, `depth == 100`): without it a cyclic comma list (e24) never ends — a HANG, not a
#     verdict, so none is listed.
#   * import_'s `error("Unknown problem importing …")` (upstream's sysError): reached by no input a row can build.
#   * `exportProcedureSource`: the kernel has no `reload`; it is `exportProcedure` (the load-time `:- ma:export(pdir/0).` of the
#     program reaches it through export_pi1's ReadingSource branch when the loader sets it).
# TARGETS (audit D-0238): each mutant lists every test file that exercises its mutated code. export/import/def_modules are named
# only by test_export_import_swipl.jl; shareDefinition/unshareDefinition/autoImport are reached by every file that resolves an
# undefined call through a super module (test_module_path.jl's `autoImport and trapUndefined`, test_module_swipl.jl, and the
# four files that name `autoImport`: test_rules_swipl.jl, test_builtins_swipl.jl, test_typetests_swipl.jl, test_assert_swipl.jl).
TS = ["test/core_lang/test_export_import_swipl.jl"]
TMOD = TS + ["test/core_lang/test_module_swipl.jl", "test/core_lang/test_module_path.jl"]
TAUTO = TMOD + [
    "test/core_lang/test_rules_swipl.jl",
    "test/foreign/test_builtins_swipl.jl",
    "test/foreign/test_typetests_swipl.jl",
    "test/db/test_assert_swipl.jl",
]
TARGETS = TAUTO                                       # the baseline's (mutate_ci.py plan reads TARGETS)
M = "src/pl-modul.jl"
P = "src/pl-proc.jl"
E = "src/pl-error.jl"
MUTANTS = [
    # ── pl-modul.c exportProcedure, isPublicModule's table ──
    dict(id="MOD5a-X1 exportProcedure does not record a new key in public_order: exports/1, '$undefined_export' never see it (KILL e01-e10)",
         file=M, targets=TS,
         old="    haskey(m.public_, key) || push!(m.public_order, key)\n",
         new="    nothing\n"),
    dict(id="MOD5a-X2 exportProcedure does not insert into the public table (KILL e01-e10)", file=M, targets=TS,
         old="    m.public_[key] = proc\n",
         new="    nothing\n"),
    # ── export_pi1 ──
    dict(id="MOD5a-X3 export_pi1 asks get_functor for a head too (no GF_NAMEARITY): export(foo) exports foo/0 (KILL e12, e20)",
         file=M, targets=TS,
         old="name, arity, mi = get_functor(gd, ld, pi, m, 0, GF_PROCEDURE | GF_NAMEARITY)",
         new="name, arity, mi = get_functor(gd, ld, pi, m, 0, GF_PROCEDURE)"),
    dict(id="MOD5a-X4 export_pi1 exports an ISO system predicate too (KILL e22)", file=M, targets=TS,
         old="(sp.definition.flags & P_ISO) != 0",
         new="false"),
    dict(id="MOD5a-X5 export_pi handles one comma pair, not a whole comma list (KILL e25)", file=M, targets=TS,
         old="    while PL_is_functor(ld, pi, mk_sym(T, Symbol(\",\")), 2)",
         new="    if PL_is_functor(ld, pi, mk_sym(T, Symbol(\",\")), 2)"),
    dict(id="MOD5a-X6 export_pi names the wrong type for a cyclic comma list (KILL e24)", file=M, targets=TS,
         old="return PL_error(ld, ERR_TYPE, mk_sym(T, :acyclic_term), pi)",
         new="return PL_error(ld, ERR_TYPE, mk_sym(T, :list), pi)"),
    dict(id="MOD5a-X7 export/1 fails where it succeeds (KILL e01-e10, i14)", file=M, targets=TS,
         old="    return export_pi(gd, ld, PL__t0, 0, 0) ? FTRUE : FFALSE",
         new="    return export_pi(gd, ld, PL__t0, 0, 0) ? FFALSE : FTRUE"),
    # ── '$undefined_export'/2 ──
    dict(id="MOD5a-U1 '$undefined_export' lists an imported export too (KILL u06)", file=M, targets=TS,
         old="def.module_ == module_.index &&",
         new="true &&"),
    dict(id="MOD5a-U2 '$undefined_export' lists an export that a default module defines (KILL e10)", file=M, targets=TS,
         old="autoImport(gd, def.name, def.arity, module_) === nothing",
         new="true"),
    dict(id="MOD5a-U3 '$undefined_export' lists the DEFINED exports and none of the undefined (KILL e06, e07)", file=M, targets=TS,
         old="if !isDefinedProcedure(gd, proc) &&",
         new="if isDefinedProcedure(gd, proc) &&"),
    # ── fixExport, fixExportModule ──
    dict(id="MOD5a-F1 fixExportModule does not re-point the sharing procedure (KILL i15, sh)", file=M, targets=TS,
         old="            proc.definition = new\n",
         new="            nothing\n"),
    dict(id="MOD5a-F2 fixExport also visits a destroyed module (EQUIVALENT: no module is destroyed yet)", file=M, targets=TS,
         old="(m.flags & M_DESTROYED) != 0 && continue",
         new="false && continue",
         equivalent="M_DESTROYED is set by '$destroy_module'/1 (MOD5b), which the kernel does not have: no module of a row is "
                    "destroyed, so the skipped branch never runs (src/pl-modul.jl fixExport)"),
    # ── atomToImportStrength, import/1, '$import'/2 ──
    dict(id="MOD5a-S1 atomToImportStrength maps weak to strong (KILL w02, F5)", file=M, targets=TS,
         old="sym_key(a) == sym_key(mk_sym(T, :weak)) && return Int(PROC_WEAK)",
         new="sym_key(a) == sym_key(mk_sym(T, :weak)) && return 0"),
    dict(id="MOD5a-S2 atomToImportStrength maps strong to weak (KILL w03)", file=M, targets=TS,
         old="sym_key(a) == sym_key(mk_sym(T, :strong)) && return 0",
         new="sym_key(a) == sym_key(mk_sym(T, :strong)) && return Int(PROC_WEAK)"),
    dict(id="MOD5a-S3 the strength error names another domain (KILL w04)", file=M, targets=TS,
         old="mk_sym(T, :import_type), strength)",
         new="mk_sym(T, :import_mode), strength)"),
    dict(id="MOD5a-S4 import_ ignores its strength argument ('$import'/2 imports strongly always) (KILL w02, w04, w05, w06, F5)",
         file=M, targets=TS,
         old="    if strength != 0\n",
         new="    if false\n"),
    dict(id="MOD5a-S5 import_ loses the weak flag of a new import (KILL F5)", file=M, targets=TS,
         old="    nproc = Procedure{T}(proc.definition, pflags, UInt32(0))",
         new="    nproc = Procedure{T}(proc.definition, UInt32(0), UInt32(0))"),
    # ── import_: the old-procedure paths ──
    dict(id="MOD5a-I1 import_ does not recognise an import that is already done (KILL i02, i17)", file=M, targets=TS,
         old="old.definition === proc.definition && return true",
         new="nothing"),
    dict(id="MOD5a-I2 import_ treats an undefined old procedure as defined (KILL i15, i16)", file=M, targets=TS,
         old="        if !isDefinedProcedure(gd, old)\n",
         new="        if false\n"),
    dict(id="MOD5a-I3 import_ fixes up the sharers only when MORE THAN ONE remain (KILL i15)", file=M, targets=TS,
         old="if unshareDefinition(odef) > 0",
         new="if unshareDefinition(odef) > 1"),
    dict(id="MOD5a-I4 the import clash is taken for the already-imported case and the reverse (KILL i04, i05, w03, w09)",
         file=M, targets=TS,
         old="        if old.definition.module_ == desti\n",
         new="        if old.definition.module_ != desti\n"),
    dict(id="MOD5a-I5 a weak import over a local definition is a clash (KILL w02)", file=M, targets=TS,
         old="            if (pflags & PROC_WEAK) != 0\n",
         new="            if (pflags & PROC_WEAK) == 0\n"),
    dict(id="MOD5a-I6 an import from another module than the old one's is not refused (KILL i05, w09)", file=M, targets=TS,
         old="if old.definition.module_ != srci",
         new="if old.definition.module_ == srci"),
    dict(id="MOD5a-I7 import_ does not link an undefined source through its default module (KILL i17)", file=M, targets=TS,
         old="    if !isDefinedProcedure(gd, proc)\n        autoImport(",
         new="    if false\n        autoImport("),
    dict(id="MOD5a-I8 the new procedure shares no definition (KILL sh)", file=M, targets=TS,
         old="    shareDefinition(proc.definition)\n    destination.procedures[",
         new="    nothing\n    destination.procedures["),
    dict(id="MOD5a-I9 import_ does not put the new procedure into the destination (KILL i01, i03, i06, i07, w01)", file=M, targets=TS,
         old="    destination.procedures[(proc.definition.functor_name, proc.definition.arity)] = nproc",
         new="    nothing"),
    # ── '$def_modules'/2, find_modules_with_defs ──
    dict(id="MOD5a-D1 find_modules_with_defs counts an undefined procedure as a definition (KILL d18)", file=M, targets=TS,
         old="        if proc !== nothing && _impl_any_defined(proc.definition)\n",
         new="        if proc !== nothing\n"),
    dict(id="MOD5a-D2 the list of a module's PIs is left open (KILL d02)", file=M, targets=TS,
         old="    found && !PL_unify_nil(ld, plist) && return false",
         new="    nothing"),
    dict(id="MOD5a-D3 the default modules are not searched (KILL d03, d13, d14)", file=M, targets=TS,
         old="    for c in m.supers\n        s = gd.modules[c]\n",
         new="    for c in Int[]\n        s = gd.modules[c]\n"),
    dict(id="MOD5a-D4 more than ten targets are taken (KILL d08)", file=M, targets=TS,
         old="if length(targets) >= MAX_TARGETS",
         new="if length(targets) > MAX_TARGETS"),
    dict(id="MOD5a-D5 MAX_TARGETS is nine (KILL d17)", file=M, targets=TS,
         old="const MAX_TARGETS = 10",
         new="const MAX_TARGETS = 9"),
    dict(id="MOD5a-D6 a `$` qualifier that is no module is taken for a user one (KILL d19)", file=M, targets=TS,
         old="elseif sym_first_byte(nm) == 0x24",
         new="elseif sym_first_byte(nm) == 0x25"),
    dict(id="MOD5a-D7 a qualifier that is no module starts at system, not user (KILL d04)", file=M, targets=TS,
         old="        else\n            m = MODULE_user(gd)\n",
         new="        else\n            m = MODULE_system(gd)\n"),
    dict(id="MOD5a-D8 '$def_modules' starts at user, not the source module (KILL d13)", file=M, targets=TS,
         old="m = gd.modules[ld.modules_source]",
         new="m = MODULE_user(gd)"),
    dict(id="MOD5a-D9 the loop guard counts up (EQUIVALENT: `l` is only read by `l < 0`)", file=M, targets=TS,
         old="find_modules_with_defs(gd, ld, s, targets, tmp, mlist, l - 1)",
         new="find_modules_with_defs(gd, ld, s, targets, tmp, mlist, l + 1)",
         equivalent="`l` starts at 100 and is read only by the `l < 0` guard of a loop in the default modules; no row builds a "
                    "chain of 100 default modules or a loop (src/pl-modul.jl find_modules_with_defs)"),
    # ── registration flags (PL_FA_TRANSPARENT: the destination / source module is the context module) ──
    dict(id="MOD5a-R1 import/1 is not transparent: ma:import(...) imports into user (KILL i01, i03)", file=M, targets=TS,
         old="PL_extension(\"import\", 1, pl_import1_va, PL_FA_TRANSPARENT | PL_FA_VARARGS)",
         new="PL_extension(\"import\", 1, pl_import1_va, PL_FA_VARARGS)"),
    dict(id="MOD5a-R2 '$import'/2 is not transparent (KILL w01, w02, w03, w07, w08)", file=M, targets=TS,
         old="PL_extension(\"\\$import\", 2, pl_import2_va, PL_FA_TRANSPARENT | PL_FA_VARARGS)",
         new="PL_extension(\"\\$import\", 2, pl_import2_va, PL_FA_VARARGS)"),
    dict(id="MOD5a-R3 export/1 is not transparent: ma:export(pb/2) exports from user (KILL e02)", file=M, targets=TS,
         old="PL_extension(\"export\", 1, pl_export1_va, PL_FA_TRANSPARENT | PL_FA_VARARGS)",
         new="PL_extension(\"export\", 1, pl_export1_va, PL_FA_VARARGS)"),
    dict(id="MOD5a-R4 '$def_modules'/2 is not transparent (EQUIVALENT: it reads the source module, not the context)", file=M,
         targets=TS,
         old="\"\\$def_modules\", 2, pl_def_modules2_va, PL_FA_TRANSPARENT | PL_FA_VARARGS",
         new="\"\\$def_modules\", 2, pl_def_modules2_va, PL_FA_VARARGS",
         equivalent="pl_def_modules2_va starts at `ld.modules_source` and never calls contextModule; PL_FA_TRANSPARENT changes only "
                    "the context module of the call (src/pl-modul.jl pl_def_modules2_va)"),
    # ── pl-proc.c get_functor, shareDefinition, unshareDefinition, autoImport ──
    dict(id="MOD5a-G1 get_functor strips the module of a GP_NOT_QUALIFIED element (KILL d20)", file=P, targets=TS,
         old="    if (how & GP_NOT_QUALIFIED) == 0\n",
         new="    if true\n"),
    dict(id="MOD5a-G2 get_functor returns the arity -1 without the early return (EQUIVALENT: the tuple is the same)", file=P,
         targets=TS,
         old="    arity < 0 && return (name, -1, m)\n",
         new="    nothing\n",
         equivalent="the line after it is `h != 0 && PL_put_term(ld, h, head)` and `return (name, arity, m)`; with arity already "
                    "-1 the tuple is the same, and the callers of MOD5a pass h = 0 (src/pl-proc.jl get_functor)"),
    dict(id="MOD5a-H1 shareDefinition adds two (KILL sh, i15)", file=P, targets=TAUTO,
         old="    def.shared += 1\n",
         new="    def.shared += 2\n"),
    dict(id="MOD5a-H2 unshareDefinition takes two off (KILL sh, i15)", file=P, targets=TAUTO,
         old="    def.shared -= 1\n",
         new="    def.shared -= 2\n"),
    dict(id="MOD5a-H3 autoImport links a super's definition without sharing it (KILL sh)", file=P, targets=TAUTO,
         old="        shareDefinition(def)\n        proc.definition = def\n",
         new="        proc.definition = def\n"),
    # ── pl-error.c ERR_IMPORT_PROC ──
    dict(id="MOD5a-E1 the import error names import_from, not import_into (KILL i04, i05, w03, w09)", file=E, targets=TS,
         old="_message_term(ld, :import_into, _err_atom(ld, dest))",
         new="_message_term(ld, :import_from, _err_atom(ld, dest))"),
    dict(id="MOD5a-E2 the import error is a permission error about an existence (KILL i04, i05, w03, w09)", file=E, targets=TS,
         old="_err_functor(ld, :permission_error, 3), into,",
         new="_err_functor(ld, :existence_error, 3), into,"),
]
