# ORIGINAL: NF2's mutant list — no swipl-devel counterpart.
# tools/mutants/NF2.py — the mutation battery of NF2 (retract/1 and clause/2 as non-deterministic foreign predicates; audit
# D-0136), run ONCE, in CI (.github/workflows/mutation.yml; locally: tools/mutate.sh run). The format is tools/mutate_drive.py's:
# `id`, `file`, `old` (must occur EXACTLY once), `new`, optional `equivalent` and `targets`. NF2-0 is the mutant NF1 left to
# NF2 (D-0141 item 2): I_FEXITNDET's FALSE clears the context AFTER the throw check, killed only by an error raised INSIDE a
# redo (test_retract_swipl.jl's occurs-check testset, e01). Then one mutant per decision of retract/1 (NF2-R*) and of
# clause/2 (NF2-C*). EQUIVALENT, with the reason: storing the predicate access reference's generation in the frame
# (`setGenerationFrameVal`, NF2-R6 and NF2-C5): the frame's generation is set to the global generation at the call
# (`setGenerationFrame`, pl-wam.jl depart_or_retry_continue / PL_open_query), and nothing between the call and
# `pushPredicateAccessObj!` creates a generation, so both values are the same. NOT listed: unprotectCRef/protectCRef (no-ops
# upstream without O_DEBUG); the `arity > 0` guard of clause's strip (stripping an atom head's qualifier first gives the same
# answer: unify_head strips both sides anyway).
# The `old` strings were written BEFORE `tools/warm.sh fmt`: re-check them after it (mutate_drive.py refuses a string that does
# not occur exactly once).
TR = ["test/db/test_retract_swipl.jl"]
TC = ["test/db/test_clause_swipl.jl"]
W = "src/pl-wam.jl"
P = "src/pl-proc.jl"
C = "src/pl-comp.jl"
MUTANTS = [
    dict(id="NF2-0 I_FEXITNDET's FALSE clears the context after the throw", file=W, targets=TR,
         old='''        ld.frames[FR].fctx = UInt(0)                # FR->clause = NULL
        ld.exception_term != 0 && @goto b_throw     # THROW_EXCEPTION''',
         new='''        ld.exception_term != 0 && @goto b_throw     # THROW_EXCEPTION
        ld.frames[FR].fctx = UInt(0)                # FR->clause = NULL'''),
    # ---- retract/1 (src/pl-proc.jl pl_retract1_va)
    dict(id="NF2-R1 FRG_CUTTED does not free the context", file=P, targets=TR,
         old='''        free_retract_context!(ld, ctx, k)
        return FTRUE''',
         new='''        return FTRUE'''),
    dict(id="NF2-R2 a redo does not answer a clause erased meanwhile", file=P, targets=TR,
         old='''               PL_foreign_control(PL__ctx) != FRG_FIRST_CALL''',
         new='''               false'''),
    dict(id="NF2-R3 the last candidate keeps a state", file=P, targets=TR,
         old='''                if ctx.chp.cref === nothing             # deterministic last one''',
         new='''                if false                                # deterministic last one'''),
    dict(id="NF2-R4 the first call's buffer is not copied into the pool", file=P, targets=TR,
         old='''                    k = alloc_retract_context!(ld, ctx)''',
         new='''                    k = k'''),
    dict(id="NF2-R5 a failed attempt is not rewound", file=P, targets=TR,
         old='''        PL_rewind_foreign_frame(ld, fid)''',
         new='''        nothing'''),
    dict(id="NF2-R6 the search generation is not stored in the frame", file=P, targets=TR,
         old='''        ld.frames[fr].generation = dref.generation      # setGenerationFrameVal(environment_frame, …)''',
         new='''        nothing                                         # setGenerationFrameVal(environment_frame, …)''',
         equivalent="the frame's generation is the global generation at the call (setGenerationFrame), which "
                    "pushPredicateAccessObj! reads again before any generation is created (src/pl-proc.jl pl_retract1_va)"),
    dict(id="NF2-R7 a pending exception does not stop the scan", file=P, targets=TR,
         old='''        PL_exception(ld, 0) != 0 && break''',
         new='''        nothing'''),
    dict(id="NF2-R8 an undefined procedure is not made dynamic", file=P, targets=TR,
         old='''            setDynamicDefinition!(def, true)            # implicit''',
         new='''            nothing                                     # implicit'''),
    dict(id="NF2-R9 a retry returns true instead of its context", file=P, targets=TR,
         old='''                return PL_retry_address(k)              # ForeignRedoPtr(ctx)''',
         new='''                return FTRUE                            # ForeignRedoPtr(ctx)'''),
    dict(id="NF2-R10 a static predicate with clauses is retracted from", file=P, targets=TR,
         old='''            if isDefinedProcedure(gd, proc)
                return PL_error(ld, ERR_MODIFY_STATIC_PROC, proc) ? FTRUE : FFALSE''',
         new='''            if false
                return PL_error(ld, ERR_MODIFY_STATIC_PROC, proc) ? FTRUE : FFALSE'''),
    # ---- clause/2 (src/pl-comp.jl clause_ndet, unify_head, unify_atom_compound; src/pl-proc.jl get_procedure_find)
    dict(id="NF2-C1 FRG_CUTTED does not pop the predicate access", file=C, targets=TC,
         old='''        popPredicateAccess!(ld, def)
        free_foreign_state!(pool, k)                        # freeForeignState(chp, sizeof(*chp))''',
         new='''        free_foreign_state!(pool, k)                        # freeForeignState(chp, sizeof(*chp))'''),
    dict(id="NF2-C2 FRG_CUTTED does not free the state", file=C, targets=TC,
         old='''        free_foreign_state!(pool, k)                        # freeForeignState(chp, sizeof(*chp))''',
         new='''        nothing'''),
    dict(id="NF2-C3 the last candidate keeps a state", file=C, targets=TC,
         old='''                    if chp.cref === nothing
                        rc = true''',
         new='''                    if false
                        rc = true'''),
    dict(id="NF2-C4 the first call's buffer is not copied into the pool", file=C, targets=TC,
         old='''                        k = alloc_foreign_state!(pool)      # allocForeignState(sizeof(*chp))''',
         new='''                        k = k                               # allocForeignState(sizeof(*chp))'''),
    dict(id="NF2-C5 the search generation is not stored in the frame", file=C, targets=TC,
         old='''        ld.frames[fr].generation = dref.generation          # setGenerationFrameVal(environment_frame, …)''',
         new='''        nothing                                             # setGenerationFrameVal(environment_frame, …)''',
         equivalent="as NF2-R6: the frame's generation is the global generation at the call, which "
                    "pushPredicateAccessObj! reads again before any generation is created (src/pl-comp.jl clause_ndet)"),
    dict(id="NF2-C6 a failed attempt is not rewound", file=C, targets=TC,
         old='''            PL_rewind_foreign_frame(ld, fid)''',
         new='''            nothing'''),
    dict(id="NF2-C7 a foreign predicate's clauses are readable", file=C, targets=TC,
         old='''        protected_predicate(gd, ld, def) && return FFALSE''',
         new='''        nothing'''),
    dict(id="NF2-C8 GP_FIND creates the procedure", file=P, targets=TC,
         old='''    return visibleProcedure(gd, name, arity, m)         # GP_FIND: found -> out; else notfound''',
         new='''    return resolveProcedure(gd, name, arity, m)         # GP_FIND: found -> out; else notfound'''),
    dict(id="NF2-C9 unify_head does not strip the qualifiers", file=C, targets=TC,
         old='''        return unify_atom_compound(ld, h1, d1)''',
         new='''        return false'''),
    dict(id="NF2-C10 an atom does not match a zero-arity compound (second arm)", file=C, targets=TC,
         old='''        elseif k2 == DU_WORD && isAtomW(w2) && k1 == DU_WORD && _is_gcompound(w1)''',
         new='''        elseif false'''),
]
