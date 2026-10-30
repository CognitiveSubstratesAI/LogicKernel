# ORIGINAL: LB2's mutant list — no swipl-devel counterpart.
# tools/mutants/LB2c.py — the mutation battery of LB2 (R2 loader_boot: the pl-srcfile.c predicates '$source_file'/2,
# '$source_file_predicates'/2, '$time_source_file'/3, '$source_file_property'/3, '$set_source_file'/3, '$start_consult'/2,
# '$end_consult'/1, '$fixup_reconsult'/1; source_location/2; system mode and the P_LOCKED sites; audit D-0244), run ONCE, in CI
# (.github/workflows/mutation.yml; locally: tools/mutate.sh run). The format is tools/mutate_drive.py's: `id`, `file`, `old` (must
# occur EXACTLY once), `new`, optional `equivalent` and `targets`.
# TARGETS (D-0238): the step's own file plus EVERY test file that loads a source file through the mutated sites (the loader, clause
# assert/retract, the module / operator / flag tests that read ReadingSource, SYSTEM_MODE and the source-file table).
# NOT RUN YET (written edit-only, 2026-10-29): the verdict column is what the rows are DESIGNED to kill. Expected survivors, to be
# looked at first:
#   * LB2-26 (associateSource without the P_LOCKED bit): assert_term (pl-comp.c:5015) sets the same bits on a clause-defined
#     predicate, so only a predicate defined by a declaration alone (`dynamic`) in system mode shows it: if it survives, add that row;
#   * LB2-30 (the FRG_CUTTED answer) is observable only if the caller reads the result of the cut call.
T = ["test/db/test_source_file_swipl.jl"]
S = T + [
    "test/files/test_load_swipl.jl",
    "test/db/test_clause_ref_swipl.jl",
    "test/db/test_clause_swipl.jl",
    "test/db/test_retract_swipl.jl",
    "test/core_lang/test_module_swipl.jl",
    "test/core_lang/test_current_op_swipl.jl",
    "test/core_lang/test_prolog_flag_swipl.jl",
    "test/compile/test_compiler_warnings_swipl.jl",
]
N = ["test/db/test_nth_clause_swipl.jl"]
NS = N + S                                                  # the get_procedure family / setDynamicDefinition! are used by the loader too
SF = "src/pl-srcfile.jl"
PR = "src/pl-proc.jl"
TARGETS = NS                                                # the baseline job's list: the union of every mutant's targets
MUTANTS = [
    # ---- '$source_file'/2 and '$source_file_predicates'/2
    dict(id="LB2-1 $source_file_predicates walks the oldest predicate first", file=SF, targets=S,
         old='''Iterators.reverse(sf.procedures)''',
         new='''sf.procedures'''),
    dict(id="LB2-2 $source_file looks an unqualified head up in user", file=SF, targets=S,
         old='''get_procedure_findhere(gd, ld, descr, MODULE_system(gd))''',
         new='''get_procedure_findhere(gd, ld, descr, MODULE_user(gd))'''),
    dict(id="LB2-3 a qualifier naming no module fails the lookup path (nothing) instead of user", file="src/pl-proc.jl", targets=S,
         old='''        m === nothing && (m = MODULE_user(gd))''',
         new='''        m === nothing && return nothing'''),
    dict(id="LB2-4 $source_file_predicates answers for a file nothing has started", file=SF, targets=S,
         old='''        if sf.count > 0
            tail''',
         new='''        if true
            tail'''),
    # ---- '$time_source_file'/3
    dict(id="LB2-5 $time_source_file starts at the second file", file=SF, targets=S,
         old='''        index = 0
''',
         new='''        index = 2
'''),
    dict(id="LB2-6 $time_source_file lists a file nothing has started", file=SF, targets=S,
         old='''if f !== nothing && f.count != 0''',
         new='''if f !== nothing'''),
    dict(id="LB2-7 the time of a real file is 0", file=SF, targets=S,
         old='''    f.isfile && return PL_unify_float(ld, t, f.mtime)''',
         new='''    !f.isfile && return PL_unify_float(ld, t, f.mtime)'''),
    dict(id="LB2-8 the type of a file is swapped", file=SF, targets=S,
         old='''f.system ? :system : :user''',
         new='''f.system ? :user : :system'''),
    dict(id="LB2-9 the redo context is not advanced", file=SF, targets=S,
         old='''                return PL_retry(index + 1)''',
         new='''                return PL_retry(index)'''),
    dict(id="LB2-30 a cut $time_source_file call fails", file=SF, targets=S,
         old='''        return FTRUE                                    # FRG_CUTTED''',
         new='''        return FFALSE                                   # FRG_CUTTED''',
         equivalent="src/pl-wam.jl:1166 — read, not run: discardForeignFrame calls `_fcall_ndet(func, ld, 0, context)` (pl-wam.c CALL_FCUTTED) as a statement and drops the returned foreign_t, so the FRG_CUTTED answer of any non-deterministic foreign predicate is never read; the dispatch (src/pl-ext.jl:990) has no other FRG_CUTTED caller."),
    # ---- '$source_file_property'/3, '$set_source_file'/3
    dict(id="LB2-10 reloading is true", file=SF, targets=S,
         old='''PL_unify_bool(ld, A3, false)''',
         new='''PL_unify_bool(ld, A3, true)'''),
    dict(id="LB2-11 loaded of an unknown file succeeds", file=SF, targets=S,
         old='''rc = (sf === nothing || sf.ltime == 0.0) ? false : PL_unify_float(ld, A3, sf.ltime)''',
         new='''rc = sf === nothing ? true : PL_unify_float(ld, A3, sf.ltime)'''),
    dict(id="LB2-12 loaded of a never-loaded file answers 0.0", file=SF, targets=S,
         old='''rc = (sf === nothing || sf.ltime == 0.0) ? false : PL_unify_float(ld, A3, sf.ltime)''',
         new='''rc = sf === nothing ? false : PL_unify_float(ld, A3, sf.ltime)'''),
    dict(id="LB2-13 $set_source_file stores the negated value", file=SF, targets=S,
         old='''sf.resource = v ''',
         new='''sf.resource = !v '''),
    dict(id="LB2-14 $source_file_property does not release its reference", file=SF, targets=S,
         old='''    sf === nothing || releaseSourceFile(sf)''',
         new='''    nothing'''),
    dict(id="LB2-15 $set_source_file does not release its reference", file=SF, targets=S,
         old='''        releaseSourceFile(sf)
        return rc ? FTRUE : FFALSE''',
         new='''        return rc ? FTRUE : FFALSE'''),
    # ---- '$start_consult'/2, '$end_consult'/1, '$fixup_reconsult'/1
    dict(id="LB2-16 $start_consult treats 0 as a time", file=SF, targets=S,
         old='''if i !== nothing && i == 0''',
         new='''if i !== nothing && i != 0'''),
    dict(id="LB2-17 $start_consult does not record the time", file=SF, targets=S,
         old='''    sf.mtime = mtime''',
         new='''    sf.mtime = 0.0'''),
    dict(id="LB2-18 $end_consult does not release the lookup's reference", file=SF, targets=S,
         old='''            rc = endConsult(sf)
            releaseSourceFile(sf)''',
         new='''            rc = endConsult(sf)'''),
    dict(id="LB2-19 $fixup_reconsult does not release the lookup's reference", file=SF, targets=S,
         old='''            releaseSourceFile(sf)
            sf.current_procedure = nothing''',
         new='''            sf.current_procedure = nothing'''),
    # ---- the source-file table
    dict(id="LB2-20 addModuleSourceFile does not look for the module first", file=SF, targets=S,
         old='''        x === m && return true''',
         new='''        false && return true'''),
    dict(id="LB2-21 addModuleSourceFile adds at the front", file=SF, targets=S,
         old='''    push!(sf.modules, m)''',
         new='''    pushfirst!(sf.modules, m)'''),
    dict(id="LB2-22 highSourceFileIndex is off by one", file=SF, targets=S,
         old='''length(gd.files_array) + 1''',
         new='''length(gd.files_array)'''),
    dict(id="LB2-23 a boot-session file is not a system file", file=SF, targets=S,
         old='''boot = gd.bootsession ''',
         new='''boot = false '''),
    # ---- system mode
    dict(id="LB2-24 SYSTEM_MODE is never on", file="src/pl-global.jl", targets=S,
         old='''    ld.prolog_flag_access_level == ACCESS_LEVEL_SYSTEM''',
         new='''    false'''),
    dict(id="LB2-25 assert_term locks without P_LOCKED", file="src/pl-comp.jl", targets=S,
         old='''(def.flags & P_LOCKED) == 0 && (def.flags |= HIDE_CHILDS | P_LOCKED)''',
         new='''(def.flags & P_LOCKED) == 0 && (def.flags |= HIDE_CHILDS)'''),
    dict(id="LB2-26 associateSource locks without P_LOCKED", file=SF, targets=S,
         old='''def.flags |= P_LOCKED | HIDE_CHILDS''',
         new='''def.flags |= HIDE_CHILDS'''),
    dict(id="LB2-27 isStaticSystemProcedure ignores system mode", file="src/pl-proc.jl", targets=S,
         old='''    SYSTEM_MODE(ld) && return nothing ''',
         new='''    false && return nothing '''),
    dict(id="LB2-28 the access_level flag is swapped", file="src/os/pl-prologflag.jl", targets=S,
         old='''SYSTEM_MODE(ld) ? :system : :user''',
         new='''SYSTEM_MODE(ld) ? :user : :system'''),
    dict(id="LB2-29 op/3 ignores system mode", file="src/pl-op.jl", targets=S,
         old='''if !force && !SYSTEM_MODE(ld::PL_local_data{T})''',
         new='''if !force && SYSTEM_MODE(ld::PL_local_data{T})'''),
    # ---- source_location/2
    # ---- '$start_aux'/2 and '$end_aux'/2 (rows a01-a15)
    dict(id="LB2-33 $start_aux reports a procedure that is not defined", file="src/pl-comp.jl", targets=S,
         old='''proc !== nothing && isDefinedProcedure(gd, proc)''',
         new='''proc !== nothing'''),
    dict(id="LB2-34 $start_aux answers Name/Arity without the module", file="src/pl-comp.jl", targets=S,
         old='''gd, ld, MODULE_user(gd), t, proc.definition, 0, GP_QUALIFY | GP_NAMEARITY''',
         new='''gd, ld, MODULE_user(gd), t, proc.definition, 0, GP_NAMEARITY'''),
    dict(id="LB2-35 $end_aux with [] keeps the current procedure", file="src/pl-comp.jl", targets=S,
         old='''    if PL_get_nil(ld, A2)
        sf.current_procedure = nothing''',
         new='''    if PL_get_nil(ld, A2)
        sf.current_procedure = sf.current_procedure'''),
    dict(id="LB2-36 $end_aux looks an unqualified PI up in user", file="src/pl-comp.jl", targets=S,
         old='''get_procedure_find_namearity(gd, ld, A2, MODULE_system(gd))''',
         new='''get_procedure_find_namearity(gd, ld, A2, MODULE_user(gd))'''),
    dict(id="LB2-37 $end_aux succeeds for a PI that names no procedure", file="src/pl-comp.jl", targets=S,
         old='''        else
            rc = false''',
         new='''        else
            rc = true'''),
    dict(id="LB2-38 get_procedure_namearity does not follow the default import (a15)", file="src/pl-proc.jl", targets=S,
         old='''    else
        visibleProcedure(gd, name, arity, m)
    end
    if p === nothing''',
         new='''    else
        isCurrentProcedure(sym_key(name), arity, m)
    end
    if p === nothing'''),
    dict(id="LB2-31 ReadingSource is false at line 0 again", file="src/pl-modul.jl", targets=S,
         old='''ld.read_source.position.lineno >= 0 && ''',
         new='''ld.read_source.position.lineno > 0 && '''),
    dict(id="LB2-32 source_location/2 answers the line plus one", file="src/os/pl-file.jl", targets=S,
         old='''PL_unify_integer(ld, A2, ld.read_source.position.lineno)''',
         new='''PL_unify_integer(ld, A2, ld.read_source.position.lineno + 1)'''),
    # ---- compile_predicates/1 and the get_procedure family (test/db/test_nth_clause_swipl.jl rows c01-c28; a15/a16 through $end_aux)
    dict(id="LB2-39 compile_predicates stops after the first element", file="src/pl-comp.jl", targets=NS,
         old='''    while PL_get_list(ld, tail, head, tail)
        PL_cons_functor(ld, desc, colon2, modm, head)''',
         new='''    if PL_get_list(ld, tail, head, tail)
        PL_cons_functor(ld, desc, colon2, modm, head)'''),
    dict(id="LB2-40 compile_predicates makes the predicate dynamic instead of static", file="src/pl-comp.jl", targets=NS,
         old='''setDynamicDefinition!(proc.definition, false)''',
         new='''setDynamicDefinition!(proc.definition, true)'''),
    dict(id="LB2-41 compile_predicates looks the predicate up through the imports (GP_FIND)", file="src/pl-comp.jl", targets=NS,
         old='''GP_NAMEARITY | GP_FINDHERE | GP_EXISTENCE_ERROR''',
         new='''GP_NAMEARITY | GP_FIND | GP_EXISTENCE_ERROR'''),
    dict(id="LB2-42 compile_predicates raises no existence error", file="src/pl-comp.jl", targets=NS,
         old='''GP_NAMEARITY | GP_FINDHERE | GP_EXISTENCE_ERROR''',
         new='''GP_NAMEARITY | GP_FINDHERE'''),
    dict(id="LB2-43 compile_predicates qualifies every item with user", file="src/pl-comp.jl", targets=NS,
         old='''PL_put_atom(ld, modm, gd.modules[mi].atom)''',
         new='''PL_put_atom(ld, modm, MODULE_user(gd).atom)'''),
    dict(id="LB2-44 compile_predicates accepts a tail that is no list", file="src/pl-comp.jl", targets=NS,
         old='''return PL_get_nil_ex(ld, tail) ? FTRUE : FFALSE''',
         new='''return FTRUE'''),
    dict(id="LB2-45 Name//Arity does not add 2", file="src/pl-proc.jl", targets=NS,
         old='''arity += dcgpi ? 2 : 0''',
         new='''arity += 0'''),
    dict(id="LB2-46 the arity limit is not checked", file="src/pl-proc.jl", targets=NS,
         old='''arity += dcgpi ? 2 : 0
        if arity > MAXARITY''',
         new='''arity += dcgpi ? 2 : 0
        if false'''),
    dict(id="LB2-47 a non-PI is a callable type error, not predicate_indicator", file="src/pl-proc.jl", targets=NS,
         old='''PL_error(ld, ERR_TYPE, mk_sym(T, :predicate_indicator), head)''',
         new='''PL_error(ld, ERR_TYPE, mk_sym(T, :callable), head)'''),
    dict(id="LB2-48 a negative arity in Name/Arity is accepted", file="src/pl-proc.jl", targets=NS,
         old='''        if arity < 0
            PL_error(ld, ERR_DOMAIN, mk_sym(T, :not_less_than_zero), a)
            return (mk_nil(T), -1)''',
         new='''        if arity < -1
            PL_error(ld, ERR_DOMAIN, mk_sym(T, :not_less_than_zero), a)
            return (mk_nil(T), -1)'''),
    dict(id="LB2-49 nth_clause by reference counts from 0", file="src/pl-comp.jl", targets=N,
         old='''            i = 1
            cref = def.impl_clauses.first_clause
            while cref !== nothing
                if cref.clause === clause''',
         new='''            i = 0
            cref = def.impl_clauses.first_clause
            while cref !== nothing
                if cref.clause === clause'''),
    dict(id="LB2-50 nth_clause by reference counts erased clauses too", file="src/pl-comp.jl", targets=N,
         old='''visibleClauseCNT(cref.clause::Clause{T}, generation) && (i += 1)''',
         new='''(i += 1)'''),
    dict(id="LB2-51 nth_clause accepts an erased reference", file="src/pl-comp.jl", targets=N,
         old='''if rc == 1                                          # PL_get_clref(ref, &clause) == true''',
         new='''if rc != 0'''),
    dict(id="LB2-52 nth_clause does not skip invisible first clauses", file="src/pl-comp.jl", targets=N,
         old='''        while cref !== nothing && !visibleClauseCNT(cref.clause::Clause{T}, generation)
            cref = cref.next
        end
        if cref === nothing
            popPredicateAccess!(ld, def)
            return FFALSE''',
         new='''        if cref === nothing
            popPredicateAccess!(ld, def)
            return FFALSE'''),
    dict(id="LB2-53 nth_clause with an index is not 0-based", file="src/pl-comp.jl", targets=N,
         old='''i -= 1                                          # 0-based''',
         new='''i -= 0'''),
    dict(id="LB2-54 nth_clause with an index stops one clause early", file="src/pl-comp.jl", targets=N,
         old='''while i > 0 && cref !== nothing''',
         new='''while i > 1 && cref !== nothing'''),
    dict(id="LB2-55 nth_clause with an index answers a clause past the end or before the start", file="src/pl-comp.jl", targets=N,
         old='''if i == 0 && cref !== nothing''',
         new='''if cref !== nothing'''),
    dict(id="LB2-56 nth_clause enumeration starts at index 0", file="src/pl-comp.jl", targets=N,
         old='''pool.states[k].key = word(1)                        # cr->index = 1''',
         new='''pool.states[k].key = word(0)'''),
    dict(id="LB2-57 nth_clause enumeration counts by two", file="src/pl-comp.jl", targets=N,
         old='''cr.key = word(Int(cr.key) + 1)                      # cr->index++''',
         new='''cr.key = word(Int(cr.key) + 2)'''),
    dict(id="LB2-58 nth_clause enumeration answers the index minus one", file="src/pl-comp.jl", targets=N,
         old='''PL_unify_integer(ld, n, Int(cr.key))''',
         new='''PL_unify_integer(ld, n, Int(cr.key) - 1)'''),
    dict(id="LB2-59 nth_clause does not free its state after the last answer", file="src/pl-comp.jl", targets=N,
         old='''free_foreign_state!(pool, k)                            # freeForeignState(cr, sizeof(*cr))''',
         new='''nothing'''),
    dict(id="LB2-60 nth_clause does not pop the predicate access after the last answer", file="src/pl-comp.jl", targets=N,
         old='''    free_foreign_state!(pool, k)                            # freeForeignState(cr, sizeof(*cr))
    popPredicateAccess!(ld, def)
    return FTRUE''',
         new='''    free_foreign_state!(pool, k)                            # freeForeignState(cr, sizeof(*cr))
    return FTRUE'''),
    dict(id="LB2-61 nth_clause cut does not pop the predicate access", file="src/pl-comp.jl", targets=N,
         old='''            popPredicateAccess!(ld, def)
            free_foreign_state!(pool, k)
        end
        return FTRUE''',
         new='''            free_foreign_state!(pool, k)
        end
        return FTRUE'''),
    dict(id="LB2-62 nth_clause redo enumerates in the current generation", file="src/pl-comp.jl", targets=N,
         old='''        def = ((pool.states[k].cref::ClauseRef{T}).clause::Clause{T}).predicate
        generation = generationFrame(ld.frames[fr])''',
         new='''        def = ((pool.states[k].cref::ClauseRef{T}).clause::Clause{T}).predicate
        generation = global_generation(gd)'''),
    dict(id="LB2-63 nth_clause does not record the generation in the frame", file="src/pl-comp.jl", targets=N,
         old='''ld.frames[fr].generation = generation               # setGenerationFrameVal(environment_frame, generation)''',
         new='''nothing''',
         equivalent="src/pl-comp.jl:3836 vs src/pl-wam.jl:2040,3258 — read, not run: the foreign frame's generation is already `global_generation(gd)` from setGenerationFrame at the call, and `dref.generation` (pushPredicateAccessObj!, src/pl-thread.jl:41 -> current_generation, src/pl-inline.jl:94) is the same value (no transactions) with no Prolog run and no database change between the two (get_procedure_find GP_FIND creates nothing); the same invariant clause/2 asserts at src/pl-comp.jl:3592 (D-0147/D-0100) on every call. Reading the frame at redo is therefore the same number. Revisit with transactions."),
    dict(id="LB2-64 nth_clause by reference, a module that is no super module is accepted", file="src/pl-comp.jl", targets=N,
         old='''(mm === nothing || !isSuperModule(gd.modules, m, mm)) && return false''',
         new='''mm === nothing && return false'''),
    dict(id="LB2-65 nth_clause by reference, a bound head of another predicate is accepted", file="src/pl-comp.jl", targets=N,
         old='''        unify_functor(ld, h, def, how) || return false
        thehead != 0 && PL_put_term(ld, thehead, h)''',
         new='''        unify_functor(ld, h, def, how)
        thehead != 0 && PL_put_term(ld, thehead, h)'''),
    # ---- '$get_clause_attribute'/3 (src/pl-proc.jl; the predicate is exercised by the one file only)
    dict(id="LB2-66 get_clause_attribute line_count answers 0 for an asserted clause", file=PR, targets=N + T,
         old='''        clause.line_no != 0 &&
            return PL_unify_integer(ld, value, Int(clause.line_no)) ? FTRUE : FFALSE''',
         new='''        return PL_unify_integer(ld, value, Int(clause.line_no)) ? FTRUE : FFALSE'''),
    dict(id="LB2-67 get_clause_attribute file reads the owner's index", file=PR, targets=N + T,
         old='''sf = indexToSourceFile(gd, clause.source_no)''',
         new='''sf = indexToSourceFile(gd, clause.owner_no)'''),
    dict(id="LB2-68 get_clause_attribute owner reads the source's index", file=PR, targets=N + T,
         old='''sf = indexToSourceFile(gd, clause.owner_no)''',
         new='''sf = indexToSourceFile(gd, clause.source_no)'''),
    dict(id="LB2-69 get_clause_attribute size is in words, not bytes", file=PR, targets=N + T,
         old='''8 * sizeofClause(length(clause.codes))''',
         new='''sizeofClause(length(clause.codes))'''),
    dict(id="LB2-70 get_clause_attribute fact is inverted", file=PR, targets=N + T,
         old='''PL_unify_bool(ld, value, (clause.flags & UNIT_CLAUSE) != 0)''',
         new='''PL_unify_bool(ld, value, (clause.flags & UNIT_CLAUSE) == 0)'''),
    dict(id="LB2-71 get_clause_attribute erased is inverted", file=PR, targets=N + T,
         old='''PL_unify_bool(ld, value, !visibleClause(clause, gen))''',
         new='''PL_unify_bool(ld, value, visibleClause(clause, gen))'''),
    dict(id="LB2-72 get_clause_attribute predicate_indicator is not qualified", file=PR, targets=N + T,
         old='''GP_QUALIFY | GP_NAMEARITY
        ) && return FTRUE''',
         new='''GP_NAMEARITY
        ) && return FTRUE'''),
    dict(id="LB2-73 get_clause_attribute predicate_indicator is a head, not Name/Arity", file=PR, targets=N + T,
         old='''GP_QUALIFY | GP_NAMEARITY
        ) && return FTRUE''',
         new='''GP_QUALIFY
        ) && return FTRUE'''),
    dict(id="LB2-74 get_clause_attribute predicate_indicator succeeds when the unification fails", file=PR, targets=N + T,
         old='''GP_QUALIFY | GP_NAMEARITY
        ) && return FTRUE''',
         new='''GP_QUALIFY | GP_NAMEARITY
        ); return FTRUE'''),
    dict(id="LB2-75 get_clause_attribute module is always user", file=PR, targets=N + T,
         old='''PL_unify_atom(ld, value, gd.modules[clause.predicate.module_].atom)''',
         new='''PL_unify_atom(ld, value, MODULE_user(gd).atom)'''),
    dict(id="LB2-76 get_clause_attribute refuses an erased reference", file=PR, targets=N + T,
         old='''rc == 0 && return FFALSE                                # !PL_get_clref(ref, &clause): the error is raised''',
         new='''rc != 1 && return FFALSE'''),
    dict(id="LB2-77 get_clause_attribute succeeds for an unknown attribute", file=PR, targets=N + T,
         old='''            FFALSE
        end
    end
    return FFALSE
end

# PORT: pl-proc.c setThreadLocalDefinition''',
         new='''            FFALSE
        end
    end
    return FTRUE
end

# PORT: pl-proc.c setThreadLocalDefinition'''),
    # ---- thread_local (pl-proc.c:3755 setThreadLocalDefinition; rows t01-t17; the redefine path t16)
    dict(id="LB2-78 thread_local on a predicate WITH clauses is allowed", file=PR, targets=N + ["test/files/test_load_swipl.jl"],
         old='''        def.impl_clauses.first_clause !== nothing &&
            return PL_error(ld, ERR_MODIFY_STATIC_PROC, def, "")''',
         new='''        nothing'''),
    dict(id="LB2-79 thread_local does not make the predicate dynamic", file=PR, targets=N + ["test/files/test_load_swipl.jl"],
         old='''def.flags |= P_DYNAMIC | P_TRANSACT | P_VOLATILE | P_THREAD_LOCAL''',
         new='''def.flags |= P_TRANSACT | P_VOLATILE | P_THREAD_LOCAL'''),
    dict(id="LB2-80 thread_local false on a thread-local predicate succeeds", file=PR, targets=N + ["test/files/test_load_swipl.jl"],
         old='''    return PL_error(ld, ERR_MODIFY_STATIC_PROC, def, "predicate is thread-local")   # local --> static''',
         new='''    return true   # local --> static'''),
    dict(id="LB2-81 thread_local: no early return when the attribute already has the value", file=PR, targets=N + ["test/files/test_load_swipl.jl"],
         old='''    if (val && (def.flags & P_THREAD_LOCAL) != 0) ||
        (!val && (def.flags & P_THREAD_LOCAL) == 0)
        return true
    end
    if val ''',
         new='''    if val '''),
    dict(id="LB2-82 thread_local false: the context message is missing", file=PR, targets=N + ["test/files/test_load_swipl.jl"],
         old='''def, "predicate is thread-local")''',
         new='''def, "")'''),
    dict(id="LB2-83 thread_local false on a predicate that is not thread-local is refused", file=PR, targets=N + ["test/files/test_load_swipl.jl"],
         old='''(!val && (def.flags & P_THREAD_LOCAL) == 0)''',
         new='''false'''),
    dict(id="LB2-84 setAttrDefinition sets the thread_local bit as any other", file=PR, targets=N + ["test/files/test_load_swipl.jl"],
         old='''    attr == P_THREAD_LOCAL && return setThreadLocalDefinition!(ld, def, val)
''',
         new=''''''),
    dict(id="LB2-85 redefineProcedure: a thread-local predicate has no clauses (the local definition is not looked at)", file=PR, targets=N + ["test/files/test_load_swipl.jl"],
         old='''        first = if (def.flags & P_THREAD_LOCAL) != 0
            _hasLocalClausesDefinition(gd, def)
        else
            hasClausesDefinition(gd, def)
        end''',
         new='''        first = hasClausesDefinition(gd, def)'''),
    dict(id="LB2-86 redefineProcedure: a thread-local predicate another file defines is not refused", file=PR, targets=N + ["test/files/test_load_swipl.jl"],
         old='''            (def.flags & P_THREAD_LOCAL) != 0 && return PL_error(
                ld, ERR_PERMISSION_PROC, mk_sym(T, :modify),
                mk_sym(T, :thread_local_procedure), proc
            )
''',
         new=''''''),
    # expected survivor, look first: the error term of t16 goes to stderr (a message), the rows read only the answers; a white-box row on ld.messages
    # (test_load_swipl.jl:554 reads them) would kill it
    dict(id="LB2-87 redefineProcedure: the error names static_procedure, not thread_local_procedure", file=PR, targets=N + ["test/files/test_load_swipl.jl"],
         old='''mk_sym(T, :thread_local_procedure), proc''',
         new='''mk_sym(T, :static_procedure), proc'''),
]
