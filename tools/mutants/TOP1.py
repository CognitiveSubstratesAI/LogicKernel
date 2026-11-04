# ORIGINAL: TOP1's mutant list — an LK-only list (the oracle half is the pty transcripts of test_top1_prompt_swipl.jl).
# tools/mutants/TOP1.py — the mutation battery of TOP1 (pl-pro.c resetProlog, restore_after_exception, halt_from_exception, query_loop;
# pl-trace.c resetTracer, enable_debug_on_interrupt; pl-file.c validUserStreams, PrologPrompt, PL_write_prompt; pl-fli.c PL_prompt_next;
# pl-write.c writeAtomToStream). Run ONCE, in CI (.github/workflows/mutation.yml; locally: tools/mutate.sh run). Format:
# tools/mutate_drive.py's (as AUTOLOAD1.py and LB5B.py): `id`, `file`, `old` (must occur EXACTLY once), `new`, optional `equivalent` and
# `targets`. Verdicts: written by the battery, not yet run. Every `old` was counted EXACTLY once in its file at the commit that adds this
# list (a text count, no Julia); the anchors are short single-line substrings, RE-FIT any `old` that `tools/warm.sh fmt` rewraps.
# KILL: test/core_lang/test_top1_pro.jl (LK-only rows, line numbers named in each id) and test/core_lang/test_top1_prompt_swipl.jl (twelve
# swipl-pinned transcripts: rows tp01-tp12 run `PL_write_prompt` and `PrologPrompt` over buffers sharing one position record). The
# resetProlog mutants of the autoloader's chain and loop mark (TOP1-R1, TOP1-R2) are killed by the row that SETS both and READS them after
# the reset (test_top1_pro.jl:213-218), the AUTOLOAD1 A2 DIVERGES.
# TARGETS (audit D-0238): the mutated code is reached by test_top1_pro.jl alone for resetProlog, query_loop, restore_after_exception,
# halt_from_exception, resetTracer, enable_debug_on_interrupt, validUserStreams and PL_prompt_next; the prompt mutants (PrologPrompt,
# PL_write_prompt, writeAtomToStream) add test_top1_prompt_swipl.jl. test/core_lang/test_lb5b_prompt.jl and
# test/core_lang/test_autoload_trap.jl are NOT listed: they read the field `prompt_next` and the fields `autoload_nesting` and
# `autoload_loop` of a fresh local data and call none of the new functions (grep over both files: no call of resetProlog, query_loop,
# PL_write_prompt, PrologPrompt, PL_prompt_next or validUserStreams), so no mutant here is reachable from them. Both listed files hold
# @testset and @test.
# NOT LISTED (each with its reason):
#   * the `Sclearerr(Suser_input(ld))` of query_loop's abort branch (src/pl-pro.jl, `exclass == EXCEPT_ABORT`): no row of test_top1_pro.jl
#     sets an error on user_input between the start of the query and the abort, and the next resetProlog clears the same error
#     (src/pl-pro.jl, `Sferror(in) != 0`); with loop false the function returns first, so the line is not an equivalent in general but
#     has no kill row here. Left to the toplevel step TOP1b, which reads user_input after the abort.
#   * `setPrologRunMode!(ld, RUN_MODE_NORMAL)` in resetTracer (src/pl-trace.jl): no row reads the run mode.
#   * `PL_close_query` / `PL_discard_foreign_frame` at the end of an iteration of query_loop: the next resetProlog with clear_stacks
#     empties the stacks and the frames; a row would need a call with ld.query != 0 (a nested query), the toplevel's.
#   * the `Sflush(s)` of PL_write_prompt: a memory stream has no pending buffer to flush.
TPRO = "test/core_lang/test_top1_pro.jl"
TPR = "test/core_lang/test_top1_prompt_swipl.jl"
TP = [TPRO]
TPP = [TPRO, TPR]
TARGETS = TPP
PP = "src/pl-pro.jl"
F = "src/os/pl-file.jl"
FL = "src/pl-fli.jl"
W = "src/pl-write.jl"
T = "src/pl-trace.jl"
MUTANTS = [
    # ── pl-pro.c resetProlog ──
    dict(id="TOP1-R1 resetProlog does not empty the autoloader's chain (KILL test_top1_pro.jl:217)",
         file=PP, targets=TP,
         old="empty!(ld.autoload_nesting)",
         new="nothing"),
    dict(id="TOP1-R2 resetProlog does not clear the autoloader's loop mark (KILL test_top1_pro.jl:218)",
         file=PP, targets=TP,
         old="ld.autoload_loop = nothing",
         new="nothing"),
    dict(id="TOP1-R3 resetProlog does not clear the error on user_input (KILL test_top1_pro.jl:227)",
         file=PP, targets=TP,
         old="Sclearerr(in)",
         new="nothing"),
    dict(id="TOP1-R4 resetProlog does not arm the prompt after an input error (KILL test_top1_pro.jl:228)",
         file=PP, targets=TP,
         old="ld.prompt_next = true",
         new="nothing"),
    dict(id="TOP1-R5 resetProlog acts on a stream WITHOUT an error: `Sferror(in) == 0` (KILL test_top1_pro.jl:223, :227)",
         file=PP, targets=TP,
         old="Sferror(in) != 0",
         new="Sferror(in) == 0"),
    dict(id="TOP1-R6 resetProlog leaves the current input as it was (KILL test_top1_pro.jl:234)",
         file=PP, targets=TP,
         old="ld.IO_streams[SNO_CURRENT_INPUT + 1] = in",
         new="nothing"),
    dict(id="TOP1-R7 resetProlog does not clear the pending exception (KILL test_top1_pro.jl:243)",
         file=PP, targets=TP,
         old="    PL_clear_exception(ld)\n    resetTracer(ld)\n",
         new="    resetTracer(ld)\n"),
    dict(id="TOP1-R8 resetProlog does not reset the debugger (KILL test_top1_pro.jl:244-245)",
         file=PP, targets=TP,
         old="resetTracer(ld)",
         new="nothing"),
    dict(id="TOP1-R9 resetProlog empties the stacks only WITH a global variable: `!isempty` (KILL test_top1_pro.jl:255-259)",
         file=PP, targets=TP,
         old="isempty(ld.gvar_nb_vars)",
         new="!isempty(ld.gvar_nb_vars)"),
    # ── pl-pro.c restore_after_exception, halt_from_exception ──
    dict(id="TOP1-X1 restore_after_exception does not switch tracing off (KILL test_top1_pro.jl:281)",
         file=PP, targets=TP,
         old="tracemode(ld, false, nothing)",
         new="nothing"),
    dict(id="TOP1-X2 restore_after_exception runs the abort event for every ball but unwind(abort) (KILL test_top1_pro.jl:282, :286)",
         file=PP, targets=TP,
         old="classify_exception(ld, except) == EXCEPT_ABORT",
         new="classify_exception(ld, except) != EXCEPT_ABORT"),
    dict(id="TOP1-X3 halt_from_exception halts with the whole status, not Status & 0xff (KILL test_top1_pro.jl:269: 263 against 7)",
         file=PP, targets=TP,
         old="Int(status & 0xff)",
         new="Int(status)"),
    # ── pl-pro.c query_loop ──
    dict(id="TOP1-Q1 query_loop never empties the stacks first: clear_stacks is false (KILL test_top1_pro.jl:311)",
         file=PP, targets=TP,
         old="clear_stacks = ld.query == 0",
         new="clear_stacks = false"),
    dict(id="TOP1-Q2 query_loop answers 0 after an exception (KILL test_top1_pro.jl:294, :299, :317, :334)",
         file=PP, targets=TP,
         old="restore_after_exception(gd, ld, except)\n            rc = -1\n",
         new="restore_after_exception(gd, ld, except)\n            rc = 0\n"),
    dict(id="TOP1-Q3 query_loop goes on after a halt ball (KILL test_top1_pro.jl:344: a second run answers 1)",
         file=PP, targets=TP,
         old="elseif exclass == EXCEPT_HALT\n                loop = false\n",
         new="elseif exclass == EXCEPT_HALT\n                nothing\n"),
    dict(id="TOP1-Q4 query_loop goes on although a user stream is in error (KILL test_top1_pro.jl:353)",
         file=PP, targets=TP,
         old="validUserStreams(ld) || (loop = false)",
         new="nothing"),
    dict(id="TOP1-Q5 query_loop sets debug_on_interrupt when it does NOT loop: `if !loop` (KILL test_top1_pro.jl:366)",
         file=PP, targets=TP,
         old="    if loop\n        enable_debug_on_interrupt",
         new="    if !loop\n        enable_debug_on_interrupt"),
    # ── pl-trace.c ──
    dict(id="TOP1-T1 resetTracer keeps the skip level (KILL test_top1_pro.jl:194)",
         file=T, targets=TP,
         old="ld.debugstatus_skiplevel = UInt(0)",
         new="nothing"),
    dict(id="TOP1-T2 enable_debug_on_interrupt switches the flag on although the flag `signals` is off (KILL test_top1_pro.jl:202-203)",
         file=T, targets=TP,
         old="truePrologFlag(ld, PLFLAG_SIGNALS) || return false",
         new="nothing"),
    # ── pl-file.c PrologPrompt, PL_write_prompt, validUserStreams ──
    dict(id="TOP1-P1 PrologPrompt gives prompt1/1's atom when it is used up, not when it is armed (KILL test_top1_pro.jl:135-141; tp02, tp09)",
         file=F, targets=TPP,
         old="!ld.prompt_first_used && ld.prompt_first !== nothing",
         new="ld.prompt_first_used && ld.prompt_first !== nothing"),
    dict(id="TOP1-P2 PrologPrompt never marks prompt1/1's atom used: it is written again (KILL test_top1_pro.jl:137; tp02)",
         file=F, targets=TPP,
         old="ld.prompt_first_used = true",
         new="nothing"),
    dict(id="TOP1-P3 PrologPrompt gives prompt/2's atom in mid-line instead of at the start of a line (KILL test_top1_pro.jl:144; tp09)",
         file=F, targets=TPP,
         old="linepos == 0",
         new="linepos != 0"),
    dict(id="TOP1-P4 PL_write_prompt writes nothing where it should (`dowrite` negated) (KILL test_top1_pro.jl:124, :129; tp01)",
         file=F, targets=TPP,
         old="if dowrite",
         new="if !dowrite"),
    dict(id="TOP1-P5 PL_write_prompt computes the prompt and does not write it (KILL test_top1_pro.jl:124; tp01)",
         file=F, targets=TPP,
         old="a === nothing || writeAtomToStream(gd, ld, s, a)",
         new="a === nothing"),
    dict(id="TOP1-P6 PL_write_prompt does not clear the flag prompt.next (KILL test_top1_pro.jl:125, :130)",
         file=F, targets=TP,
         old="ld.prompt_next = false",
         new="nothing"),
    dict(id="TOP1-V1 validUserStreams does not look at user_error (KILL test_top1_pro.jl:182, :353)",
         file=F, targets=TP,
         old="(Suser_input(ld), Suser_output(ld), Suser_error(ld))",
         new="(Suser_input(ld), Suser_output(ld))"),
    # ── pl-fli.c PL_prompt_next, pl-write.c writeAtomToStream ──
    dict(id="TOP1-N1 PL_prompt_next arms the prompt for every stream (KILL test_top1_pro.jl:107, :112)",
         file=FL, targets=TP,
         old="if in === Suser_input(ld)",
         new="if true"),
    dict(id="TOP1-W1 writeAtomToStream answers false although it wrote the atom (KILL test_top1_pro.jl:160, :162)",
         file=W, targets=TPP,
         old="return writeAtom(atom, options) != 0",
         new="return writeAtom(atom, options) == 0"),
]
