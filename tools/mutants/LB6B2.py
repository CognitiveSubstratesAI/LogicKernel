# ORIGINAL: LB6b-2's mutant list - the kernel's live reload (pl-srcfile.c startConsult / endReconsult / delete_old_predicate(s) / delete_pending_clauses /
# end_reconsult_proc / fix_module / registerReloadModule / exportProcedureSource / endConsult, pl-proc.c reconsultFinalizePredicate, pl-modul.c declareModule
# at 18168e62). Format: tools/mutate_drive.py's (as LB6A.py): `id`, `file`, `old` (must occur EXACTLY once), `new`, optional `equivalent` and `targets`.
# Each id names the KILL row of test/db/test_reload_swipl.jl (rl01-rl15) or of a neighbour. Verdicts: written by the battery, not yet run. The `old` strings were
# each checked to occur exactly once in their file at wip/miss-preds (python3 -I count); RE-FIT any that `tools/warm.sh fmt` rewraps.
# TARGETS (audit D-0238) name every file that exercises the mutated code: the reload file first, the white-box reload blocks, the source-file and load files
# (a second `load_file!`, `$start_consult` / `$fixup_reconsult`), the tabling abolish file (the untable calls), test_miss_preds_swipl.jl and test_clause_ref_swipl.jl
# (a reload started by hand, the generation after it); the module-export mutants add the export/declare files.
# NOT COVERED by any row (no mutant is written for them): deleteActiveClauseFromIndexes! and registerDirtyDefinition! in reconsultFinalizePredicate!,
# `def.flags &= ~P_MODIFIED`, `pl_garbage_collect_clauses!` in endReconsult, `sf.procedures` empty!/append! in delete_old_predicates, `delayEvents(ld)`.
# MAY SURVIVE: LB6B2-M1 (declareModule's abolish branch also empties the public table, a first load has nothing to abolish) and LB6B2-A14 (fix_attributes
# in the first arm of end_reconsult_proc; the flags a reload keeps are also set while loading): decide at the battery.
TR = ["test/db/test_reload_swipl.jl"]
TW = ["test/db/test_reload_blocks_swipl.jl"]
TS = ["test/db/test_source_file_swipl.jl", "test/files/test_load_swipl.jl"]
TT = ["test/core_lang/test_tabling_abolish_swipl.jl"]
TM = ["test/core_lang/test_miss_preds_swipl.jl", "test/db/test_clause_ref_swipl.jl"]
TX = ["test/core_lang/test_declare_destroy_swipl.jl", "test/core_lang/test_export_import_swipl.jl", "test/core_lang/test_module_enum_swipl.jl"]
TARGETS = TR + TW + TS + TT + TM
S = "src/pl-srcfile.jl"
P = "src/pl-proc.jl"
M = "src/pl-modul.jl"
MUTANTS = [
    # ── startConsult / delete_old_predicate(s) ──
    dict(id="LB6B2-A1 startConsult: the second load of a file is not a re-consult (count > 2) (KILL rl01, the source_file reload row)", file=S, targets=TARGETS,
         old="    if (sf.count += 1) > 1                          # This is a re-consult\n",
         new="    if (sf.count += 1) > 2                          # This is a re-consult\n"),
    dict(id="LB6B2-A2 delete_old_predicates: a predicate the reload did not touch is kept, one it touched is deleted (KILL rl02)", file=S, targets=TARGETS,
         old="(proc.definition.flags & P_FOREIGN) == 0 && !haskey(rl.procedures, proc)",
         new="(proc.definition.flags & P_FOREIGN) == 0 && haskey(rl.procedures, proc)"),
    dict(id="LB6B2-A3 delete_old_predicate: a multifile predicate loses ALL its clauses, not only this file's (KILL rl13)", file=S, targets=TARGETS,
         old="    removeClausesPredicate!(gd, def, (def.flags & P_MULTIFILE) != 0 ? sf.index : 0, true)\n\n",
         new="    removeClausesPredicate!(gd, def, 0, true)\n\n"),
    dict(id="LB6B2-A4 delete_old_predicate: the FILE_ASSIGNED / meta / code reset runs for a multifile predicate only (KILL rl02, rl13)", file=S, targets=TARGETS,
         old="    if (def.flags & P_MULTIFILE) == 0\n        def.flags &= ~FILE_ASSIGNED\n        clear_meta_declaration(def)\n        freeCodesDefinition!",
         new="    if (def.flags & P_MULTIFILE) != 0\n        def.flags &= ~FILE_ASSIGNED\n        clear_meta_declaration(def)\n        freeCodesDefinition!"),
    dict(id="LB6B2-A5 delete_old_predicate: the untable of a dropped tabled predicate's clauses is not called (KILL rl11, test_tabling_abolish_swipl.jl)", file=S, targets=TARGETS,
         old="    untable_definition_clauses(gd, ld, def)\n\n    removeClausesPredicate!",
         new="    removeClausesPredicate!"),
    # ── delete_pending_clauses ──
    dict(id="LB6B2-A6 delete_pending_clauses: the pending `$tabled` clause is not untabled (KILL rl14)", file=S, targets=TARGETS,
         old="        isdtabled && untable_from_clause(gd, ld, c)\n",
         new="        nothing\n"),
    dict(id="LB6B2-A7 delete_pending_clauses: the `$tabled`/2 test reads the wrong arity (KILL rl14)", file=S, targets=TARGETS,
         old="    isdtabled = def.arity == 2 && def.functor_name",
         new="    isdtabled = def.arity == 3 && def.functor_name"),
    dict(id="LB6B2-A8 delete_pending_clauses: the multifile/dynamic owner test is dropped, another file's clause is marked (KILL rl08)", file=S, targets=TARGETS,
         old="        if (r.predicate.flags & (P_MULTIFILE | P_DYNAMIC)) != 0 && c.owner_no != sf.index\n            continue\n        end\n",
         new=""),
    dict(id="LB6B2-A9 delete_pending_clauses: the clause is erased at the global generation, not the reload's (KILL rl01)", file=S, targets=TARGETS,
         old="        c.generation_erased = rl.reload_gen\n",
         new="        c.generation_erased = global_generation(gd)\n"),
    dict(id="LB6B2-A10 delete_pending_clauses: P_MODIFIED is not set, the finalize is skipped (KILL rl01, rl15)", file=S, targets=TARGETS,
         old="        r.flags |= P_MODIFIED\n        c.generation_erased = rl.reload_gen\n",
         new="        c.generation_erased = rl.reload_gen\n"),
    # ── end_reconsult_proc ──
    dict(id="LB6B2-A11 end_reconsult_proc: the finishing arm runs for a NEW predicate, not for an old one (KILL rl01, rl03)", file=S, targets=TARGETS,
         old="    if (r.flags & (P_NEW | P_NO_CLAUSES)) == 0\n        def = proc.definition\n",
         new="    if (r.flags & (P_NEW | P_NO_CLAUSES)) != 0\n        def = proc.definition\n"),
    dict(id="LB6B2-A12 end_reconsult_proc: the dropped predicate-access reference is not counted (the @assert in endReconsult throws on every reload of a new predicate)", file=S, targets=TARGETS,
         old="        dropped_access += 1\n",
         new="        nothing\n"),
    dict(id="LB6B2-A13 end_reconsult_proc: the P_NO_CLAUSES arm does not fix the attributes (KILL rl10)", file=S, targets=TARGETS,
         old="        if (r.flags & P_NO_CLAUSES) != 0\n            fix_attributes(gd, sf, proc.definition, r)\n        end\n",
         new=""),
    dict(id="LB6B2-A14 end_reconsult_proc: the first arm does not fix the attributes (KILL rl07; MAY SURVIVE)", file=S, targets=TARGETS,
         old="        fix_attributes(gd, sf, def, r)\n        reconsultFinalizePredicate!",
         new="        reconsultFinalizePredicate!"),
    # ── fix_module / registerReloadModule / exportProcedureSource ──
    dict(id="LB6B2-A15 fix_module: the exports the reload made again are deleted, the others kept (KILL rl06)", file=S, targets=TARGETS + TX,
         old="        if !haskey(r.public_, key)\n",
         new="        if haskey(r.public_, key)\n"),
    dict(id="LB6B2-A16 registerReloadModule: the module's reload record is never made (KILL rl06)", file=S, targets=TARGETS + TX,
         old="        haskey(rl.modules, module_) || (\n",
         new="        true || (\n"),
    dict(id="LB6B2-A17 exportProcedureSource: the export is not recorded in the reload's public table (KILL rl06)", file=S, targets=TARGETS + TX,
         old="            r.public_[key] = proc                   # updateHTableWP(r->public, functor, proc)\n",
         new="            nothing\n"),
    # ── endReconsult ──
    dict(id="LB6B2-A18 endReconsult: the reload generation stays set after the outermost reload (white-box gd.reload_generation, rl01-rl15's final check)", file=S, targets=TARGETS,
         old="        if (ld.reload_nesting -= 1) == 0\n",
         new="        if (ld.reload_nesting -= 1) != 0\n"),
    dict(id="LB6B2-A19 endReconsult: the file's clause count is not taken from the reload (KILL rl01 SN, test_load_swipl.jl's number_of_clauses)", file=S, targets=TARGETS,
         old="        sf.number_of_clauses = reload.number_of_clauses\n",
         new=""),
    dict(id="LB6B2-A20 endReconsult: sf.reload is left set (white-box: no reload context left)", file=S, targets=TARGETS,
         old="        sf.reload = nothing\n",
         new=""),
    dict(id="LB6B2-A21 endReconsult: delete_old_predicates is not called (KILL rl02)", file=S, targets=TARGETS,
         old="        delete_old_predicates(gd, ld, sf)\n\n        for (proc, r) in reload.procedures\n",
         new="        for (proc, r) in reload.procedures\n"),
    dict(id="LB6B2-A22 endReconsult: fix_module is not called (KILL rl06)", file=S, targets=TARGETS + TX,
         old="            fix_module(m, r)\n",
         new="            nothing\n"),
    dict(id="LB6B2-A23 endConsult: the reload is not finished (KILL rl01, every reload row)", file=S, targets=TARGETS,
         old="    rc = endReconsult(gd, ld, sf)\n    releaseSourceFile(sf)\n    return rc\n",
         new="    rc = true\n    releaseSourceFile(sf)\n    return rc\n"),
    dict(id="LB6B2-A24 $fixup_reconsult: the reload is not finished (KILL the source_file reload row)", file=S, targets=TS + TW + TM,
         old="            rc = endReconsult(gd, ld, sf)\n            releaseSourceFile(sf)\n",
         new="            rc = true\n            releaseSourceFile(sf)\n"),
    # ── reconsultFinalizePredicate! ──
    dict(id="LB6B2-F1 reconsultFinalizePredicate!: the clauses the reload added keep the reload generation (KILL rl01, rl03)", file=P, targets=TARGETS,
         old="                cl.generation_created = update\n",
         new="                nothing\n"),
    dict(id="LB6B2-F2 reconsultFinalizePredicate!: the global generation is not advanced (KILL rl01)", file=P, targets=TARGETS,
         old="        gd._generation = update\n\n        if added != 0",
         new="        if added != 0"),
    dict(id="LB6B2-F3 reconsultFinalizePredicate!: a predicate that was modified is skipped (KILL rl01)", file=P, targets=TARGETS,
         old="    if (r.flags & P_MODIFIED) != 0\n        deleted = 0\n",
         new="    if (r.flags & P_MODIFIED) == 0\n        deleted = 0\n"),
    dict(id="LB6B2-F4 reconsultFinalizePredicate!: the number of clauses does not fall for an erased clause (KILL rl01 N, rl10)", file=P, targets=TARGETS,
         old="                deleted += 1\n                def.impl_clauses.number_of_clauses -= 0x00000001\n",
         new="                deleted += 1\n"),
    dict(id="LB6B2-F5 reconsultFinalizePredicate!: the number of rules falls for a unit clause, not for a rule (KILL rl15)", file=P, targets=TARGETS,
         old="                if (cl.flags & UNIT_CLAUSE) == 0\n                    def.impl_clauses.number_of_rules",
         new="                if (cl.flags & UNIT_CLAUSE) != 0\n                    def.impl_clauses.number_of_rules"),
    dict(id="LB6B2-F6 reconsultFinalizePredicate!: the erased-at-reload test reads another generation (KILL rl01)", file=P, targets=TARGETS,
         old="            if cl.generation_erased == rl.reload_gen && (cl.flags & CL_ERASED) == 0\n",
         new="            if cl.generation_erased != rl.reload_gen && (cl.flags & CL_ERASED) == 0\n"),
    dict(id="LB6B2-F7 reconsultFinalizePredicate!: the created-at-reload test reads another generation (KILL rl03)", file=P, targets=TARGETS,
         old="            elseif cl.generation_created == rl.reload_gen\n",
         new="            elseif cl.generation_created != rl.reload_gen\n"),
    # ── declareModule ──
    dict(id="LB6B2-M1 declareModule: the reload arm is taken for a first load (KILL rl06; MAY SURVIVE)", file=M, targets=TARGETS + TX,
         old="    if sf.reload !== nothing\n        registerReloadModule(sf, module_)\n",
         new="    if sf.reload === nothing\n        registerReloadModule(sf, module_)\n"),
    # ── equivalent ──
    dict(id="LB6B2-E1 startConsult: a failed startReconsultFile returns true (equivalent)", file=S, targets=TR,
         old="            releaseSourceFile(sf)\n            return false\n        end\n    end\n    sf.current_procedure = nothing\n",
         new="            releaseSourceFile(sf)\n            return true\n        end\n    end\n    sf.current_procedure = nothing\n",
         equivalent="src/pl-srcfile.jl startReconsultFile (:259-290) has no false path: it returns true at its end, so the branch is never taken"),
    dict(id="LB6B2-E2 reconsultFinalizePredicate!: the TWF flag lines are dropped (equivalent)", file=P, targets=TR,
         old="            added != 0 && (flags |= TWF_ASSERT)\n            deleted != 0 && (flags |= TWF_RETRACT)\n",
         new="",
         equivalent="src/pl-proc.jl:552-560 setLastModifiedPredicate!: below GEN_TRANSACTION_BASE (a reload's `update` is a plain generation) `flags` is ignored"),
]
