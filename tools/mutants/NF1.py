# ORIGINAL: NF1's mutant list — no swipl-devel counterpart.
# tools/mutants/NF1.py — the mutation battery of NF1 (the non-deterministic foreign calls, between/3 their first user;
# audit D-0136), run ONCE, in CI (.github/workflows/mutation.yml; locally: tools/mutate.sh run). The format is
# tools/mutate_drive.py's: `id`, `file`, `old` (must occur EXACTLY once), `new`, optional `equivalent` and `targets`.
# One mutant per line of the instruction bodies that decides an answer (the design's list, evidence/nf/design.md §6), each
# backtrack site's reload on its own (NF1-7 needs the direct query, NF1-8 a program), the FRG_CUTTED call and the state's
# free. NOT listed, with the reason: the REDO_INT decode of I_FREDO (no REDO_INT user until NF4's repeat/0); the order
# "clear the context, then throw" of I_FEXITNDET's FALSE (H8: only a built-in that raises INSIDE a redo reaches it, and
# between/3 raises on its first call only — NF2's list, with retract/1). The ids skip NF1-4 for that reason.
TARGETS = ["test/core_lang/test_between_swipl.jl"]
T = TARGETS
W = "src/pl-wam.jl"
A = "src/pl-arith.jl"
MUTANTS = [
    dict(id="NF1-1 the jump choice resumes one word early", file=W, targets=T,
         old='''    setJumpChoice!(ld, fr_ch, PC + 3)''',
         new='''    setJumpChoice!(ld, fr_ch, PC + 2)'''),
    dict(id="NF1-2 I_FREDO goes back three words, not four", file=W, targets=T,
         old='''    PC -= 4                                        # Back to I_FCALL*''',
         new='''    PC -= 3                                        # Back to I_FCALL*'''),
    dict(id="NF1-3 a retry context is not stored in the frame", file=W, targets=T,
         old='''    ld.frames[FR].fctx = UInt(fexitndet_rc)         # CL = word2ptr(ClauseRef, rc)''',
         new='''    ld.frames[FR].fctx = UInt(0)                    # CL = word2ptr(ClauseRef, rc)'''),
    dict(id="NF1-5 TRUE keeps the choice point", file=W, targets=T,
         old='''        ld.BFR = ld.choices[ld.BFR].parent
        ld.frames[FR].fctx = UInt(0)                # FR->clause = NULL
        @goto exit_checking_wakeup''',
         new='''        ld.frames[FR].fctx = UInt(0)                # FR->clause = NULL
        @goto exit_checking_wakeup'''),
    dict(id="NF1-6 FALSE keeps the choice point", file=W, targets=T,
         old='''        @assert ld.choices[ld.BFR].value_pc == PC
        ld.BFR = ld.choices[ld.BFR].parent
        @goto deep_backtrack                        # FRAME_FAILED''',
         new='''        @assert ld.choices[ld.BFR].value_pc == PC
        @goto deep_backtrack                        # FRAME_FAILED'''),
    dict(id="NF1-7 shallow_backtrack reloads a clause for a foreign frame", file=W, targets=T,
         old='''            if (sb_def.flags & P_FOREIGN) != 0''',
         new='''            if false'''),
    dict(id="NF1-8 deep_backtrack reloads a clause for a foreign frame", file=W, targets=T,
         old='''        if (DEF.flags & P_FOREIGN) != 0             # (NF1) an index into the supervisor''',
         new='''        if false                                    # (NF1) an index into the supervisor'''),
    dict(id="NF1-9 a discarded frame's built-in is not called with FRG_CUTTED", file=W, targets=T,
         old='''    _fcall_va(func, ld, 0, argc, context)           # (*function)(0, argc, &context)''',
         new='''    nothing                                         # (*function)(0, argc, &context)'''),
    dict(id="NF1-10 the context survives its FRG_CUTTED call", file=W, targets=T,
         old='''            f.fctx = UInt(0)                        # fr->clause = NULL''',
         new='''            nothing                                 # fr->clause = NULL'''),
    dict(id="NF1-11 a retry exit keeps the foreign frame", file=W, targets=T,
         old='''    setLTop!(ld, ld.choices[ld.BFR].base + SIZEOF_CHOICE)   # lTop = (LocalFrame)(BFR+1)''',
         new='''    nothing                                                 # lTop = (LocalFrame)(BFR+1)'''),
    dict(id="NF1-12 a REDO_PTR context is passed as its index", file=W, targets=T,
         old='''        fd_ctx.context = fd_wcl''',
         new='''        fd_ctx.context = fd_wcl >> FRG_REDO_BITS'''),
    dict(id="NF1-13 between/3 does not free its state at FRG_CUTTED", file=A, targets=T,
         old='''        free_foreign_state!(ld.between_states, PL_foreign_context_address(PL__ctx))''',
         new='''        nothing'''),
]
