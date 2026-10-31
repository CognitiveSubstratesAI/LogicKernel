# ORIGINAL: MOD5b's mutant list — no swipl-devel counterpart.
# tools/mutants/MOD5b.py — the mutation battery of MOD5b (declaring and destroying modules: pl-modul.c declareModule,
# declare_module, destroy_module, destroyModule, acquireModule, releaseModule(_unlocked), unallocModule, unlinkSourceFilesModule,
# markSourceFilesProcedure; pl-srcfile.c unlinkSourceFileModule; pl-proc.c abolishProcedure's imported-link branch), run ONCE, in
# CI (.github/workflows/mutation.yml; locally: tools/mutate.sh run).
# Format: tools/mutate_drive.py's (as MOD5a.py): `id`, `file`, `old` (must occur EXACTLY once), `new`, optional `equivalent`
# and `targets`. Killed by test/core_lang/test_declare_destroy_swipl.jl (rows a01-a21, b01-b06, c01-c02, d01-d12, e01-e04, f01-f05
# named in each id's KILL; "H3" is the testset of the destroyed module's record and b06's definitions). Verdicts: written by
# the battery, not yet run.
# The `old` strings are written in the repo's formatted style BEFORE `tools/warm.sh fmt` ran (the coding agent had no
# daemon): RE-FIT any that fmt rewraps (comment alignment after code is the likely one) at the first battery run (mutate_drive.py
# refuses a string that does not occur exactly once). Every `old` was checked to occur exactly once in its file at the commit
# that adds this file (a text count, no Julia).
# TARGETS (audit D-0238): the code mutated here is reached from `'$declare_module'/6` and `'$destroy_module'/1` only (callers of
# declareModule, destroyModule, acquireModule, releaseModule, unlinkSourceFile(s)Module and the abolish branch: the grep over src/
# and test/ found test_declare_destroy_swipl.jl alone; test_export_import_swipl.jl only names '$declare_module' in a comment).
# NOT LISTED (each with its reason):
#   * _text_summary's `maxlen - 6`, the message text "Already loaded from …": it is in the error CONTEXT; the rows compare the
#     formal only, and no row names a path of more than 100 characters.
#   * The `declare_module(M, abolish(PIs))` warning branch of declareModule (rdef, unify_definition, printMessage): unreachable
#     until abolishProcedure is ported fully (Q7); an own procedure with clauses is refused first.
#   * markSourceFilesProcedure's MULTISOURCE test, unlinkSourceFilesModule's loop over the files and unlinkSourceFileModule's
#     filter: no row loads a procedure from a source file that a temporary module was declared in (`sf.procedures` is empty),
#     so a mutant of them would survive. LATER: a white-box with a consulted file that defines a predicate in the module.
#   * addModuleSourceFile's call in declareModule: the module list of a source file is read by no row.
TS = ["test/core_lang/test_declare_destroy_swipl.jl"]
TARGETS = TS                                          # the baseline's (mutate_ci.py plan reads TARGETS)
M = "src/pl-modul.jl"
SF = "src/pl-srcfile.jl"
MUTANTS = [
    # ── acquireModule / acquireModulePtr ──
    dict(id="MOD5b-A1 acquireModule counts no reference: the destroy releases to -1, the module is never freed (KILL d02, d03, H3)",
         file=M, targets=TS,
         old="        m.references += 1\n    end\n    return m\n",
         new="        nothing\n    end\n    return m\n"),
    dict(id="MOD5b-A2 acquireModule counts the references of the modules that are NOT temporary (KILL d02, d03, H3)",
         file=M, targets=TS,
         old="    if m !== nothing && sym_key(m.class) == sym_key(mk_sym(T, :temporary))\n        m.references += 1\n",
         new="    if m !== nothing && sym_key(m.class) != sym_key(mk_sym(T, :temporary))\n        m.references += 1\n"),
    dict(id="MOD5b-A3 acquireModulePtr counts no reference (EQUIVALENT: nothing calls it)", file=M, targets=TS,
         old="        m.references += 1\n    end\n    return nothing\n",
         new="        nothing\n    end\n    return nothing\n",
         equivalent="acquireModulePtr is ported for completeness (pl-modul.c:208) and has no caller in src/ yet (grep over "
                    "src/*.jl); the `getTargetModule!` path that will use it is L-later"),
    # ── unallocModule ──
    dict(id="MOD5b-U1 unallocModule leaves the source module as it is: a destroyed module stays the source module (KILL d02)",
         file=M, targets=TS,
         old="    ld.modules_source == m.index && (ld.modules_source = user.index)\n",
         new="    nothing\n"),
    dict(id="MOD5b-U2 unallocModule leaves the typein module as it is (KILL d03)", file=M, targets=TS,
         old="    ld.modules_typein == m.index && (ld.modules_typein = user.index)\n",
         new="    nothing\n"),
    dict(id="MOD5b-U3 unallocModule puts the destroyed module itself back as the source module (KILL d02)", file=M, targets=TS,
         old="(ld.modules_source = user.index)",
         new="(ld.modules_source = m.index)"),
    # ── markSourceFilesProcedure, unlinkSourceFilesModule, unlinkSourceFileModule ──
    dict(id="MOD5b-L1 unlinkSourceFilesModule releases the file but keeps the module's file index (KILL H3: old.file == 0)",
         file=M, targets=TS,
         old="        m.file = 0\n        releaseSourceFile(sf)\n",
         new="        releaseSourceFile(sf)\n"),
    # ── releaseModule_unlocked, releaseModule ──
    dict(id="MOD5b-R1 releaseModule_unlocked frees at one reference left, not at none (KILL d02, d03, H3)", file=M, targets=TS,
         old="    if m.references == 0 && (m.flags & M_DESTROYED) != 0\n",
         new="    if m.references == 1 && (m.flags & M_DESTROYED) != 0\n"),
    dict(id="MOD5b-R4 releaseModule releases the modules that are NOT temporary, not the temporary ones (KILL d02, H3)", file=M,
         targets=TS,
         old="    if sym_key(m.class) == sym_key(mk_sym(T, :temporary))\n        releaseModule_unlocked(gd, ld, m)\n",
         new="    if sym_key(m.class) != sym_key(mk_sym(T, :temporary))\n        releaseModule_unlocked(gd, ld, m)\n"),
    # ── destroyModule ──
    dict(id="MOD5b-D1 destroyModule leaves the name in the module table (KILL d01, e01, e02)", file=M, targets=TS,
         old="        delete!(gd.modules.names, m.name)\n",
         new="        nothing\n"),
    dict(id="MOD5b-D2 destroyModule does not mark the module destroyed (KILL d02, d03, H3)", file=M, targets=TS,
         old="        m.flags |= M_DESTROYED\n",
         new="        nothing\n"),
    dict(id="MOD5b-D3 destroyModule does not release the reference acquireModule took (KILL d02, d03, H3)", file=M, targets=TS,
         old="    releaseModule(gd, ld, m)\n    return true\n",
         new="    return true\n"),
    dict(id="MOD5b-D4 destroyModule takes the name out only when the table maps it to ANOTHER module (KILL d01, e01)", file=M,
         targets=TS,
         old="    if get(gd.modules.names, m.name, 0) == m.index ",
         new="    if get(gd.modules.names, m.name, 0) != m.index "),
    # ── '$destroy_module'/1 ──
    dict(id="MOD5b-P1 destroy_module destroys the modules that are NOT temporary and refuses the temporary ones (KILL d01, d05-d07, d10, d11)",
         file=M, targets=TS,
         old="        if sym_key(m.class) == sym_key(mk_sym(T, :temporary))\n            return destroyModule",
         new="        if sym_key(m.class) != sym_key(mk_sym(T, :temporary))\n            return destroyModule"),
    dict(id="MOD5b-P2 destroy_module raises a modify permission error, not destroy (KILL d05-d07, d10, d11)", file=M, targets=TS,
         old="mk_sym(T, :destroy)",
         new="mk_sym(T, :modify)"),
    dict(id="MOD5b-P3 destroy_module fails for a name of no module (KILL d04)", file=M, targets=TS,
         old="    return FTRUE                                        # non-existing\n",
         new="    return FFALSE                                       # non-existing\n"),
    dict(id="MOD5b-P4 destroy_module does not release after refusing a module that is not temporary (EQUIVALENT)", file=M,
         targets=TS,
         old="            releaseModule(gd, ld, m)\n            return PL_error(",
         new="            return PL_error(",
         equivalent="that branch is reached only for a module whose class is NOT temporary, and acquireModule counted no "
                    "reference for it; releaseModule tests the same class and does nothing (src/pl-modul.jl releaseModule)"),
    dict(id="MOD5b-P5 '$destroy_module' is registered with arity 2 (KILL every d row, e01, e02, f04)", file=M, targets=TS,
         old='PL_extension("\\$destroy_module", 1, ',
         new='PL_extension("\\$destroy_module", 2, '),
    # ── declareModule ──
    dict(id="MOD5b-C1 declareModule does not set the class (KILL a01, a04, a07, c01, c02, d01)", file=M, targets=TS,
         old="    module_.class = class\n",
         new="    nothing\n"),
    dict(id="MOD5b-C2 declareModule sets the class only when it does not refuse (KILL a06: upstream sets it first)", file=M,
         targets=TS,
         old="    module_.class = class\n",
         new="    (allow_newfile || module_.file == 0 || module_.file == sf.index) ? (module_.class = class) : nothing\n"),
    dict(id="MOD5b-C3 declareModule refuses a module that has no file yet (KILL a01, every first declaration)", file=M, targets=TS,
         old="    if !allow_newfile && module_.file != 0 && module_.file != sf.index\n",
         new="    if !allow_newfile && module_.file != sf.index\n"),
    dict(id="MOD5b-C4 declareModule refuses the SAME file and accepts another (KILL a02, a03)", file=M, targets=TS,
         old="    if !allow_newfile && module_.file != 0 && module_.file != sf.index\n",
         new="    if !allow_newfile && module_.file != 0 && module_.file == sf.index\n"),
    dict(id="MOD5b-C5 declareModule refuses only when Redefine is true (KILL a03, a04, a05)", file=M, targets=TS,
         old="    if !allow_newfile && module_.file != 0 && module_.file != sf.index\n",
         new="    if allow_newfile && module_.file != 0 && module_.file != sf.index\n"),
    dict(id="MOD5b-C6 declareModule always runs the file-change branch (EQUIVALENT)", file=M, targets=TS,
         old="    if module_.file != sf.index\n        module_.file = sf.index\n",
         new="    if true\n        module_.file = sf.index\n",
         equivalent="with the same file the branch stores the same index, and addModuleSourceFile returns at once when the "
                    "module is in the file's list (src/pl-srcfile.jl, the `x === m && return true` loop)"),
    dict(id="MOD5b-C7 declareModule does not record the file (KILL a01, a04, a05)", file=M, targets=TS,
         old="        module_.file = sf.index\n",
         new="        nothing\n"),
    dict(id="MOD5b-C9 declareModule does not make the module the source module (KILL a01)", file=M, targets=TS,
         old="    ld.modules_source = module_.index\n",
         new="    nothing\n"),
    dict(id="MOD5b-C10 declareModule abolishes the dynamic predicates too (KILL a21, b04, b05)", file=M, targets=TS,
         old="        if (def.flags & (P_DYNAMIC | P_MULTIFILE | P_FOREIGN)) == 0\n",
         new="        if (def.flags & (P_MULTIFILE | P_FOREIGN)) == 0\n"),
    dict(id="MOD5b-C11 declareModule does not clear the public table (KILL a19, a20)", file=M, targets=TS,
         old="empty!(module_.public_)",
         new="nothing"),
    dict(id="MOD5b-C12 declareModule does not clear the export order (KILL a19, e03)", file=M, targets=TS,
         old="empty!(module_.public_order)",
         new="nothing"),
    dict(id="MOD5b-C13 declareModule does not set the super module (KILL b02, b05, b06)", file=M, targets=TS,
         old="    rc = setSuperModule(gd.modules, ld, module_, lookupModule(gd, super))\n",
         new="    rc = true\n"),
    # ── '$declare_module'/6 ──
    dict(id="MOD5b-W1 declare_module passes the super where the class goes and the class where the super goes (KILL a01, b02)",
         file=M, targets=TS,
         old="declareModule(gd, ld, mname, cname, sname, sf, line_no, rdef)",
         new="declareModule(gd, ld, mname, sname, cname, sf, line_no, rdef)"),
    dict(id="MOD5b-W2 declare_module negates Redefine (KILL a03, a04, a05)", file=M, targets=TS,
         old="sf, line_no, rdef) ? FTRUE",
         new="sf, line_no, !rdef) ? FTRUE"),
    dict(id="MOD5b-W5 '$declare_module' is registered with arity 5 (KILL every row that declares)", file=M, targets=TS,
         old='PL_extension("\\$declare_module", 6, ',
         new='PL_extension("\\$declare_module", 5, '),
    # ── abolishProcedure's imported-link branch (pl-proc.c:1517-1530) ──
    dict(id="MOD5b-M1 the abolish never removes an imported link: the loop refuses it by name (KILL b06)", file=M, targets=TS,
         old="    if def.module_ != m.index ",
         new="    if false "),
    dict(id="MOD5b-M2 the abolish leaves the old definition shared once too often (KILL H3: ss.definition.shared == 1)", file=M,
         targets=TS,
         old="        proc.definition = ndef\n        unshareDefinition(def)\n",
         new="        proc.definition = ndef\n"),
    dict(id="MOD5b-M4 the fresh definition counts one sharer where upstream's memset leaves 0 (KILL H3: p5.definition.shared == 0)",
         file=M, targets=TS,
         old="cd, 0, m.index, 0 ",
         new="cd, 0, m.index, 1 "),
]
