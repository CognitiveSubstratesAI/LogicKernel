# ORIGINAL: the small-refusals lane's mutant list — no swipl-devel counterpart.
# tools/mutants/SMALLREF.py — mutation battery of the small R2 rows (SRC2 `$unload_file`/1, PR1 `$foreign_predicate_source`/2; later SSU1b, CONT1, AV10), run ONCE,
# in CI. The format is tools/mutate_drive.py's: `id`, `file`, `old` (must occur EXACTLY once), `new`, optional `equivalent`, `targets`.
# NOT RUN YET (written edit-only, 2026-11-11): the verdict column is what the rows are DESIGNED to kill.
# TARGETS (D-0238): `$unload_file` and its helpers are reached only through test/db/test_source_file_swipl.jl; the loader's own
# test (test/files/test_load_swipl.jl) loads files but never unloads one.
TSF = ["test/db/test_source_file_swipl.jl"]
SF = "src/pl-srcfile.jl"
PR = "src/pl-proc.jl"
TDET = ["test/core_lang/test_det_swipl.jl"]   # SSU1b rows (D-0238: det/1 is reached through the det test only; test_ssu_compile_swipl.jl compiles `$`-less SSU rules, not the P_DET declaration)
TARGETS = TSF
MUTANTS = [
    # ---- SRC2: '$unload_file'/1, unloadFile, delAllModulesSourceFile__unlocked, delModuleSourceFile
    dict(id="SRC2-1 unloadFile removes every clause of a multifile predicate, not only the file's", file=SF, targets=TSF,
         old='''removeClausesPredicate!(gd, def, multifile ? sf.index : 0, true)''',
         new='''removeClausesPredicate!(gd, def, 0, true)'''),
    dict(id="SRC2-2 unloadFile keeps the FILE_ASSIGNED mark of a static predicate", file=SF, targets=TSF,
         old='''            def.flags &= ~FILE_ASSIGNED
            clear_meta_declaration(def)''',
         new='''            clear_meta_declaration(def)'''),
    dict(id="SRC2-3 unloadFile keeps the meta declaration", file=SF, targets=TSF,
         old='''            def.flags &= ~FILE_ASSIGNED
            clear_meta_declaration(def)''',
         new='''            def.flags &= ~FILE_ASSIGNED'''),
    dict(id="SRC2-4 unloadFile leaves the file a real file", file=SF, targets=TSF,
         old='''    sf.isfile = false

    return sendDelayedEvents''',
         new='''    sf.isfile = true

    return sendDelayedEvents'''),
    dict(id="SRC2-5 unloadFile does not take the removed clauses off the file's count", file=SF, targets=TSF,
         old='''    sf.number_of_clauses -= UInt32(deleted)''',
         new='''    sf.number_of_clauses += UInt32(0)'''),
    dict(id="SRC2-6 unloadFile keeps the file's procedure list", file=SF, targets=TSF,
         old='''    empty!(sf.procedures)                           # freeList(&sf->procedures)''',
         new='''    nothing                                         # freeList(&sf->procedures)'''),
    dict(id="SRC2-7 unloadFile removes the clauses of a foreign or thread-local predicate too", file=SF, targets=TSF,
         old='''        if (def.flags & (P_FOREIGN | P_THREAD_LOCAL)) == 0
            multifile =''',
         new='''        if true
            multifile ='''),
    dict(id="SRC2-8 unloadFile fails when no event was sent", file=SF, targets=TSF,
         old='''    return sendDelayedEvents(gd, ld, true) >= 0''',
         new='''    return sendDelayedEvents(gd, ld, true) > 0'''),
    dict(id="SRC2-9 a module keeps its file after the unload", file=SF, targets=TSF,
         old='''        if m.file == sf.index
            m.file = 0                              # m->file = NULL''',
         new='''        if m.file == sf.index
            m.file = m.file                         # m->file = NULL'''),
    dict(id="SRC2-10 a module keeps its line number after the unload", file=SF, targets=TSF,
         old='''            m.file = 0                              # m->file = NULL
            m.line_no = 0
            empty!(m.public_)                       # clearHTableWP(m->public)
            empty!(m.public_order)''',
         new='''            m.file = 0                              # m->file = NULL
            empty!(m.public_)                       # clearHTableWP(m->public)
            empty!(m.public_order)'''),
    dict(id="SRC2-11 a module keeps its public table after the unload", file=SF, targets=TSF,
         old='''            empty!(m.public_)                       # clearHTableWP(m->public)
            empty!(m.public_order)
        end
    end
    return nothing''',
         new='''            empty!(m.public_order)
        end
    end
    return nothing'''),
    dict(id="SRC2-12 the module list of the unloaded file is kept", file=SF, targets=TSF,
         old='''    empty!(sf.modules)                              # sf->modules = NULL''',
         new='''    nothing                                         # sf->modules = NULL'''),
    dict(id="SRC2-13 a system file is unloaded", file=SF, targets=TSF,
         old='''        if sf.system
            rc = PL_error(''',
         new='''        if false
            rc = PL_error('''),
    dict(id="SRC2-14 an unknown file answers false", file=SF, targets=TSF,
         old='''        return rc ? FTRUE : FFALSE
    end

    return FTRUE
end

# PORT: pl-srcfile.c BeginPredDefs''',
         new='''        return rc ? FTRUE : FFALSE
    end

    return FFALSE
end

# PORT: pl-srcfile.c BeginPredDefs'''),
    dict(id="SRC2-15 $unload_file keeps the reference its lookup took", file=SF, targets=TSF,
         old='''        releaseSourceFile(sf)
        return rc ? FTRUE : FFALSE
    end

    return FTRUE''',
         new='''        return rc ? FTRUE : FFALSE
    end

    return FTRUE'''),
    dict(id="SRC2-16 the permission error names another action", file=SF, targets=TSF,
         old='''mk_sym(T, :unload), mk_sym(T, :file), A1''',
         new='''mk_sym(T, :load), mk_sym(T, :file), A1'''),
    # ---- PR1: '$foreign_predicate_source'/2 (a named refusal for a foreign predicate, a failure for any other)
    dict(id="PR1-1 $foreign_predicate_source of a foreign predicate fails instead of the refusal", file=PR, targets=TSF,
         old='''    if (def.flags & P_FOREIGN) != 0
        throw(
            NotPortedError{T}(
                fd[1],
                "foreign_predicate_source of a foreign predicate''',
         new='''    if (def.flags & P_FOREIGN) != 0
        return FFALSE
        throw(
            NotPortedError{T}(
                fd[1],
                "foreign_predicate_source of a foreign predicate'''),
    dict(id="PR1-2 $foreign_predicate_source refuses every predicate, foreign or not", file=PR, targets=TSF,
         old='''    def = proc.definition                           # getProcDefinition(proc)
    if (def.flags & P_FOREIGN) != 0
        throw(''',
         new='''    def = proc.definition                           # getProcDefinition(proc)
    if true
        throw('''),
    dict(id="PR1-4 $foreign_predicate_source answers true for an undefined predicate", file=PR, targets=TSF,
         old='''    proc = visibleProcedure(gd, fd[1], fd[2], gd.modules[mi])
    proc === nothing && return FFALSE

    def = proc.definition                           # getProcDefinition(proc)''',
         new='''    proc = visibleProcedure(gd, fd[1], fd[2], gd.modules[mi])
    proc === nothing && return FTRUE

    def = proc.definition                           # getProcDefinition(proc)'''),
    dict(id="PR1-5 the refusal's step is another owner", file=PR, targets=TSF,
         old='''(pl-proc.c:4199-4202)",
                "PR1"''',
         new='''(pl-proc.c:4199-4202)",
                "PR2"'''),
    # ---- SSU1b: setDetDefinition!
    dict(id="SSU1b-1 setDetDefinition! never sets P_DET", file=PR, targets=TDET,
         old='''        def.flags |= P_DET
        freeCodesDefinition!(def, true)                     # reset to S_VIRGIN''',
         new='''        freeCodesDefinition!(def, true)                     # reset to S_VIRGIN'''),
    dict(id="SSU1b-2 setDetDefinition! never clears P_DET", file=PR, targets=TDET,
         old='''        def.flags &= ~P_DET
        freeCodesDefinition!(def, true)                     # reset to S_VIRGIN''',
         new='''        freeCodesDefinition!(def, true)                     # reset to S_VIRGIN'''),
    dict(id="SSU1b-3 setting P_DET leaves a supervisor already built", file=PR, targets=TDET,
         old='''        def.flags |= P_DET
        freeCodesDefinition!(def, true)                     # reset to S_VIRGIN''',
         new='''        def.flags |= P_DET'''),
    dict(id="SSU1b-4 clearing P_DET leaves a supervisor already built", file=PR, targets=TDET,
         old='''        def.flags &= ~P_DET
        freeCodesDefinition!(def, true)                     # reset to S_VIRGIN''',
         new='''        def.flags &= ~P_DET'''),
    dict(id="SSU1b-5 setAttrDefinition sends P_DET to the plain flag path", file=PR, targets=TDET,
         old='''    attr == P_DET && return setDetDefinition!(def, val)
''',
         new=''''''),
]
