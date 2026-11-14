# ORIGINAL: TOP1b's mutant list — an LK-only list (the oracle half is test_top1b_swipl.jl's pins tb01..tb06b, swipl 10.1.19).
# tools/mutants/TOP1B.py — the mutation battery of TOP1b pieces A-D (pl-pro.c currentBreakLevel, pl_break1, pl_break, prologToplevel;
# pl-fli.c PL_toplevel, PL_ttymode, PL_prompt_is_continuation, PL_prompt_string, PL_dispatch; pl-os.c Sttymode, Sset_ttymode;
# pl-prologflag.c's `break_level` arm; SWI-Stream.h SIO_RAW). Run ONCE, in CI (.github/workflows/mutation.yml; locally: tools/mutate.sh
# run, one mutant at a time under debugging only). Format: tools/mutate_drive.py's (as TOP1.py and CT1A.py): `id`, `file`, `old` (must occur
# EXACTLY once), `new`, optional `equivalent` and `targets`. Verdicts: written by the battery, not yet run. Every `old` was counted EXACTLY
# once in its file at the commit that adds this list (a text count, no Julia, python3 -I); the anchors that span lines
# (`\n` + four-space indent) are RE-FIT if `tools/warm.sh fmt` rewraps them.
# KILL: test/core_lang/test_top1b_swipl.jl (line numbers named in each id): the testsets "break_level" (:135-158), "prologToplevel" (:160-175),
# "PL_toplevel and break/0" (:177-208, pins tb02 and tb03n), "pl_break1 at level -1" (:210-230, pin tb03), "pl_break1: the current
# streams" (:232-258, pin tb04), "pl_break1: the debugger" (:260-279), "a raising goal" (:281-301, pins tb06a and tb06b), "Sttymode"
# (:303-327), "PL_ttymode" (:329-347), "PL_prompt_is_continuation and PL_prompt_string" (:349-374), "PL_dispatch" (:376-385). The flag arm is also
# reached by test_prolog_flag_swipl.jl (row t_e15: the flag FAILS outside a toplevel).
# TARGETS (audit D-0238, the dispatcher's list for this step): test_top1b_swipl.jl; test_top1_pro.jl (query_loop, which pl_break1 and
# prologToplevel call, and resetProlog/resetTracer, whose effect on the streams and the debugger two EQUIVALENT notes below rest on);
# test_top1_prompt_swipl.jl and test_lb5b_prompt.jl (PrologPrompt and the prompt fields that PL_prompt_string and PL_prompt_is_continuation
# read); test_prolog_flag_swipl.jl (the flag arm). Where a grep shows a file calls none of the mutated functions it is listed anyway: a
# survivor of a narrow list proves nothing about dead code, a wider list only costs time. Every listed file holds @testset and @test.
# PIECES E AND F (the stream wrapper and set_prolog_IO/3, appended below: ids TOP1B-P01 ff. and TOP1B-E2): `registerLocalData!`,
# `unregisterLocalData!`, `S_read`, `S_close`, `S_write`, `Sread_user`, `closeWrappedIO`, `wrapIO`, `Swrite_stderr`, `getIOStreams` and
# `pl_set_prolog_IO3_va`. KILL: test/core_lang/test_top1b_wrap_swipl.jl (the line numbers named in each id are that file's at the commit that adds
# the list): the swipl-pinned rows :162-175 (e01-e12, e16, e17), the testsets "the registry of local data" (:186-207), "wrapIO: the record ..."
# (:209-240), "wrapIO twice ..." (:242-259), "closing a wrapped stream ..." (:261-284), "Sread_user driven directly ..." (:286-349: prompt arm
# :299-307, flush arm :309-315, raw tty :317-321, end of file :324-335, ^D :337-348), "a freed registry entry reads -1" (:351-363),
# "set_prolog_IO/3 on the kernel ..." (:365-421) and "Swrite_stderr ..." (:423-442). The rows were never run on the kernel when this list was
# written: a kill is claimed from the row's text, the battery decides.
# TARGETS_EF (audit D-0238): the five files of the step, test/db/test_gd_template.jl (the ld_table policy of the template copy: registerLocalData!
# and the wrapper record), and EVERY test file that reads, writes or closes a stream, because S_read, S_write and S_close are the functions every
# stream goes through and the mutants P21-P24, P46-P49 change them: found by a recursive grep over test/ for `Sclose(`, `Sopen_string`,
# `Sopen_memfile`, `set_standard_stream!`, `Sgetcode`, `Sread_` (20 test files and the static-analysis manifest, which is no test) and for the Prolog-level `open(`/`close(`/`read` users
# among the rest (test_read_stream_swipl.jl); test_prolog_flag_swipl.jl stays from A-D. Files that only name `user_error` or `current_output` and
# call none of the mutated functions are left out (test_rules_swipl.jl reads the alloc pins of the struct, not these functions).
# DROPPED CANDIDATES of pieces E and F (by id, one line each; none is claimed equivalent, none has a killing row):
#   * D7 set_prolog_IO/3 `setStandardStream(ld, SNO_USER_OUTPUT, out)` and `(.., SNO_CURRENT_OUTPUT, out)` removed (src/os/pl-file.jl:3150, :3152): every row
#     passes Out = user_output, so both lines store the stream that is already there; a row with another output stream would kill them (a gap).
#   * D8 closeWrappedIO `s.flags &= ~WRAP_CLEAR_FLAGS` removed (:3048): the flag is cleared by wrapIO and no row sets SIO_FILE while the stream is wrapped
#     with saved_flags 0, so the second clearing is never seen (a gap, not an equivalent).
#   * D9 S_read `&& w.user_read` dropped (src/os/pl-stream.jl:320): wrapIO is only given read = true by set_prolog_IO/3, and the only wrap with
#     read = false (the wrap test's `s3`) is never read; a row reading it would kill it (a gap).
#   * D10 closeWrappedIO `rval = S_close_wrapped(s)` -> `rval = 0` (:3045): Sclose sets the stream's magic itself, so no named row shows that the
#     underlying IO was not closed (the e10 pin reads -1 after the close in both cases): no kill claimed.
#   * D11 Swrite_stderr `Sputc(...) < 0 && break` removed (:3090): a failing write is never driven (the buffers do not fail).
#   * D12 the `io === nothing && return FFALSE` line of pl_set_prolog_IO3_va and the `in/out/err/e === nothing && return nothing` lines of getIOStreams
#     (:3110, :3113, :3118, :3122, :3145): removed they raise a Julia error instead of failing, which e11a/e11d would show as an error row; not worth
#     a battery slot each, the SH_* mutants P38/P39 stand for the error paths.
#   * D13 `Sread_user`'s `PL_write_prompt(gd, ld, true)` argument and `gd = ld.GD` (:3012, :3014): the first is the argument of the prompt function whose
#     own file pins it; the second is the record of ld.GD that wrapIO writes (P14).
# WAITING (pieces G, H): the mutants M21-M23 and M25 ff. of the plan (the `Sread_terminal` prompt, `ResetTty` in `initIO`, `_query_run_at_halt`)
# are written when their code exists.
# DROPPED CANDIDATES (by id, one line each; none is claimed equivalent, none has a killing row):
#   * D1 pl_break1 `ld.IO_streams[SNO_CURRENT_OUTPUT + 1] = Suser_output(ld)` removed (src/pl-pro.jl:497): resetProlog redoes it (:313) but
#     printMessage(begin) runs in between and a hook could print to current_output; no row prints there, so neither a kill nor a proof.
#   * D2 pl_break1 `ld.debugstatus_skiplevel = skipSave` removed (src/pl-pro.jl:518): resetTracer zeroes skiplevel (pl-trace.jl:226) and no
#     row sets a non-zero skiplevel before the break; a row would need `ld.debugstatus_skiplevel = UInt(3)` first (a gap, for the gate agent).
#   * D3 `tracemode(ld, false, traceSave)` / `tracemode(ld, traceSave[], nothing)` (src/pl-pro.jl:493, :519): no row turns tracing on in the
#     kernel, so the restore has nothing to restore (same gap as D2).
#   * D4 the `PL_extension("break", 0, ...)` entry of PL_predicates_from_pro removed: killed by tb02 AND by the registration censuses
#     (test_zero_exports, the R2 status block) that this list does not name; the swapped result of pl_break_va (N09) stands for it.
#   * D5 PL_toplevel's atom `$toplevel` -> `$query_loop`: in tb02 `$toplevel :- '$query_loop'` makes the two calls the same run and in tb06a
#     `$query_loop` is undefined, so a raise would be run again by query_loop(loop) with no end in view: a hang risk, not worth a battery slot.
#   * D6 `pl_break`'s `wstate !== nothing` test (the else branch `return false`): saveWakeup answers nothing only when the foreign frame cannot be
#     opened (src/pl-attvar.jl:51, `no space!`); no row exhausts the stacks there, so no kill row (a gap, not an equivalent).
TB = "test/core_lang/test_top1b_swipl.jl"
TPRO = "test/core_lang/test_top1_pro.jl"
TPR = "test/core_lang/test_top1_prompt_swipl.jl"
LB5 = "test/core_lang/test_lb5b_prompt.jl"
PF = "test/core_lang/test_prolog_flag_swipl.jl"
TARGETS = [TB, TPRO, TPR, LB5, PF]
WR = "test/core_lang/test_top1b_wrap_swipl.jl"
GDT = "test/db/test_gd_template.jl"
# the files that read, write or close a stream (see PIECES E AND F above)
STREAM_TESTS = [
    "test/files/test_open_close_swipl.jl", "test/files/test_stream_swipl.jl", "test/files/test_qlf_swipl.jl",
    "test/core_text/test_read_stream_swipl.jl", "test/core_text/test_read_positions_swipl.jl",
    "test/core_text/test_canonical_readatom_swipl.jl", "test/core_text/test_float_write_swipl.jl",
    "test/core_text/test_write_family_swipl.jl", "test/core_text/test_write_swipl.jl",
    "test/foreign/test_exceptions_swipl.jl", "test/core_lang/test_string_swipl.jl", "test/core_lang/test_read_swipl.jl",
    "test/core_lang/test_blob.jl", "test/core_lang/test_numbervars_cells.jl", "test/core_lang/test_write_cells.jl",
]
TARGETS_EF = [WR, TB, TPR, LB5, TPRO, GDT, PF] + STREAM_TESTS
PFI = "src/os/pl-file.jl"
PP = "src/pl-pro.jl"
FLI = "src/pl-fli.jl"
OS = "src/os/pl-os.jl"
PFL = "src/os/pl-prologflag.jl"
ST = "src/os/pl-stream.jl"
MUTANTS = [
    # ── pl-pro.c prologToplevel ──
    dict(id="TOP1B-M16 prologToplevel counts `$query_loop` AND `$toplevel` at once: no goal is a toplevel (KILL test_top1b_swipl.jl:197 tb02, :168)",
         file=PP, targets=TARGETS,
         old=r'''Symbol("\$query_loop"))) ||''',
         new=r'''Symbol("\$query_loop"))) &&'''),
    dict(id="TOP1B-M17 prologToplevel does not restore the caller's break level (KILL test_top1b_swipl.jl:168, :170, :174, :199)",
         file=PP, targets=TARGETS,
         old="rc = query_loop(gd, ld, goal, loop)\n    ld.break_level = old_level",
         new="rc = query_loop(gd, ld, goal, loop)"),
    dict(id="TOP1B-N01 prologToplevel does not raise the break level for a toplevel goal (KILL test_top1b_swipl.jl:197 tb02 `none`, :289 tb06a)",
         file=PP, targets=TARGETS,
         old="ld.break_level += 1\n        loop = true",
         new="loop = true"),
    dict(id="TOP1B-N02 prologToplevel runs a toplevel goal once: a raise is not restarted (KILL test_top1b_swipl.jl:281-291 tb06a)",
         file=PP, targets=TARGETS,
         old="ld.break_level += 1\n        loop = true",
         new="ld.break_level += 1\n        loop = false"),
    # ── pl-pro.c pl_break1 ──
    dict(id="TOP1B-M18 pl_break1 hands the user's input back as current input, not the saved one (KILL test_top1b_swipl.jl:255 tb04, :257)",
         file=PP, targets=TARGETS,
         old="ld.IO_streams[SNO_CURRENT_INPUT + 1] = inSave",
         new="ld.IO_streams[SNO_CURRENT_INPUT + 1] = Suser_input(ld)"),
    dict(id="TOP1B-N03 pl_break1 hands the user's output back as current output, not the saved one (KILL test_top1b_swipl.jl:255 tb04, :257)",
         file=PP, targets=TARGETS,
         old="ld.IO_streams[SNO_CURRENT_OUTPUT + 1] = outSave",
         new="ld.IO_streams[SNO_CURRENT_OUTPUT + 1] = Suser_output(ld)"),
    dict(id="TOP1B-N04 pl_break1 does not restore the break level (KILL test_top1b_swipl.jl:220, :225, :229, :300)",
         file=PP, targets=TARGETS,
         old="    end\n    ld.break_level = old_level\n\n    restore_tabling_status(ld, tblstat)\n    ld.debugstatus_skiplevel",
         new="    end\n\n    restore_tabling_status(ld, tblstat)\n    ld.debugstatus_skiplevel"),
    dict(id="TOP1B-N05 pl_break1 tells break(begin, 0) at the first level (KILL test_top1b_swipl.jl:219)",
         file=PP, targets=TARGETS,
         old="ld.break_level += 1\n    if ld.break_level > 0",
         new="ld.break_level += 1\n    if ld.break_level >= 0"),
    dict(id="TOP1B-N06 pl_break1 prints break(end, Level) although the goal failed (KILL test_top1b_swipl.jl:227, :228)",
         file=PP, targets=TARGETS,
         old="rc && printMessage(",
         new="printMessage("),
    dict(id="TOP1B-N07 pl_break1 does not save whether the debugger was on (KILL test_top1b_swipl.jl:271 `switched on again`)",
         file=PP, targets=TARGETS,
         old="debugmode(ld, false, debugSave, UInt32(0))",
         new="debugmode(ld, false, nothing, UInt32(0))"),
    dict(id="TOP1B-N08 pl_break1 leaves the debugger off afterwards (KILL test_top1b_swipl.jl:271)",
         file=PP, targets=TARGETS,
         old="debugmode(ld, debugSave[], nothing, UInt32(0))",
         new="debugmode(ld, false, nothing, UInt32(0))"),
    dict(id="TOP1B-E1 pl_break1 does not set the current input to user_input on the way in (EQUIVALENT)",
         file=PP, targets=TARGETS,
         old="ld.IO_streams[SNO_CURRENT_INPUT + 1] = Suser_input(ld)          # Scurin  = Sinput",
         new="nothing",
         equivalent="src/pl-pro.jl:312 — query_loop's first resetProlog (:412) sets Scurin to Suser_input(ld) before the goal runs, and between the line and "
                    "that call only printMessage(begin) (pl-pro.jl:501-504) runs, which reads no current input; inside the break the rows read Scurin only "
                    "after resetProlog (tb04 `inside`), so the line has no observable effect"),
    # ── pl-pro.c pl_break (break/0) ──
    dict(id="TOP1B-N09 break/0 (pl_break_va) answers the opposite of pl_break (KILL test_top1b_swipl.jl:197 tb02: the conjunction `break, lvl(3)` fails)",
         file=PP, targets=TARGETS,
         old="pl_break(_query_gd(ld), ld) ? FTRUE : FFALSE",
         new="pl_break(_query_gd(ld), ld) ? FFALSE : FTRUE"),
    # ── pl-pro.c currentBreakLevel, pl-prologflag.c break_level ──
    dict(id="TOP1B-M19 currentBreakLevel answers one more than the field (KILL test_top1b_swipl.jl:141, :147)",
         file=PP, targets=TARGETS,
         old="currentBreakLevel(ld::PL_local_data)::Int = ld.break_level",
         new="currentBreakLevel(ld::PL_local_data)::Int = ld.break_level + 1"),
    dict(id="TOP1B-M20 the flag break_level fails at level 0 (`bl > 0`) (KILL test_top1b_swipl.jl:148-150 lvl 0; test_prolog_flag_swipl.jl t_e15 stays)",
         file=PFL, targets=TARGETS,
         old="return bl >= 0 && PL_unify_integer(ld, val, bl)",
         new="return bl > 0 && PL_unify_integer(ld, val, bl)"),
    dict(id="TOP1B-N10 the flag break_level unifies one more than the level (KILL test_top1b_swipl.jl:150)",
         file=PFL, targets=TARGETS,
         old="PL_unify_integer(ld, val, bl)",
         new="PL_unify_integer(ld, val, bl + 1)"),
    dict(id="TOP1B-N11 the flag break_level answers outside a toplevel (`bl >= -1`) (KILL test_top1b_swipl.jl:142 `isempty(flag(db))`; test_prolog_flag_swipl.jl t_e15)",
         file=PFL, targets=TARGETS,
         old="return bl >= 0 && PL_unify_integer(ld, val, bl)",
         new="return bl >= -1 && PL_unify_integer(ld, val, bl)"),
    # ── pl-os.c Sttymode, Sset_ttymode; SWI-Stream.h SIO_RAW ──
    dict(id="TOP1B-M24 PL_prompt_is_continuation does not ask whether prompt1/1's atom was handed out (KILL test_top1b_swipl.jl:359 armed, not handed out)",
         file=FLI, targets=TARGETS,
         old="ld.prompt_first !== nothing && ld.prompt_first_used",
         new="ld.prompt_first !== nothing"),
    dict(id="TOP1B-N12 Sttymode answers the opposite mode (KILL test_top1b_swipl.jl:314, :316)",
         file=OS, targets=TARGETS,
         old="? TTY_RAW : TTY_COOKED",
         new="? TTY_COOKED : TTY_RAW"),
    dict(id="TOP1B-N13 Sset_ttymode sets the bit for every mode but TTY_RAW (KILL test_top1b_swipl.jl:316-317, :320, :325)",
         file=OS, targets=TARGETS,
         old="if mode == TTY_RAW",
         new="if mode != TTY_RAW"),
    dict(id="TOP1B-N14 Sset_ttymode never clears the bit (KILL test_top1b_swipl.jl:320-321, :325-326)",
         file=OS, targets=TARGETS,
         old="s.flags &= ~SIO_RAW",
         new="nothing"),
    dict(id="TOP1B-N15 SIO_RAW is bit 26, which is SIO_WARN's (KILL test_top1b_swipl.jl:307, :310)",
         file=ST, targets=TARGETS,
         old="const SIO_RAW = UInt32(1) << 27",
         new="const SIO_RAW = UInt32(1) << 26"),
    # ── pl-fli.c PL_ttymode, PL_prompt_is_continuation, PL_prompt_string, PL_dispatch ──
    dict(id="TOP1B-N16 PL_ttymode ignores `-tty` (the flag tty_control) (KILL test_top1b_swipl.jl:344, :346)",
         file=FLI, targets=TARGETS,
         old="truePrologFlag(ld, PLFLAG_TTY_CONTROL) || return PL_NOTTY",
         new="true"),
    dict(id="TOP1B-N17 PL_ttymode answers the cooked mode for a raw stream (KILL test_top1b_swipl.jl:338)",
         file=FLI, targets=TARGETS,
         old="Sttymode(s) == TTY_RAW && return PL_RAWTTY",
         new="Sttymode(s) != TTY_RAW && return PL_RAWTTY"),
    dict(id="TOP1B-N18 PL_ttymode answers a mode for every stream, not only user_input (KILL test_top1b_swipl.jl:341, :342)",
         file=FLI, targets=TARGETS,
         old="if s === Suser_input(ld)\n        truePrologFlag",
         new="if true\n        truePrologFlag"),
    dict(id="TOP1B-N19 PL_prompt_is_continuation answers for every stream (KILL test_top1b_swipl.jl:362, :363)",
         file=FLI, targets=TARGETS,
         old="return in === Suser_input(ld) && ld.prompt_first !== nothing",
         new="return ld.prompt_first !== nothing"),
    dict(id="TOP1B-N20 PL_prompt_string answers a prompt for every stream (KILL test_top1b_swipl.jl:364)",
         file=FLI, targets=TARGETS,
         old="if in === Suser_input(ld)\n        a = PrologPrompt(ld)",
         new="if true\n        a = PrologPrompt(ld)"),
    dict(id="TOP1B-N21 PL_dispatch answers true for PL_DISPATCH_INSTALLED, false for the rest (KILL test_top1b_swipl.jl:381-384)",
         file=FLI, targets=TARGETS,
         old="wait != PL_DISPATCH_INSTALLED",
         new="wait == PL_DISPATCH_INSTALLED"),
    # ── pieces E and F: pl-file.c Sread_user ──
    dict(id="TOP1B-P01 Sread_user does not clear the eof and error flags of user_input at end of file (KILL test_top1b_wrap_swipl.jl:383-385)",
         file=PFI, targets=TARGETS_EF,
         old="ui === nothing || Sclearerr(ui)",
         new="nothing"),
    dict(id="TOP1B-P02 Sread_user does not arm the prompt again at end of file (KILL test_top1b_wrap_swipl.jl:381-384; e03 `|: <-1>` after the fill)",
         file=PFI, targets=TARGETS_EF,
         old="ui === nothing || Sclearerr(ui)\n        ld.prompt_next = true",
         new="ui === nothing || Sclearerr(ui)"),
    dict(id="TOP1B-P03 Sread_user looks for ^D at index 1 of the buffer, not at `from` (KILL test_top1b_wrap_swipl.jl:387-396: from = 3, the one byte 4 stays a character)",
         file=PFI, targets=TARGETS_EF,
         old="mem[from] == 0x04",
         new="mem[1] == 0x04"),
    dict(id="TOP1B-P04 Sread_user maps ^D to end of file when it begins a longer read (KILL test_top1b_wrap_swipl.jl:387-397 bytes (4,10) must stay 2; e06c)",
         file=PFI, targets=TARGETS_EF,
         old="rc == 1 && mem[from] == 0x04",
         new="rc >= 1 && mem[from] == 0x04"),
    dict(id="TOP1B-P05 Sread_user re-arms the prompt after a carriage return, not a newline (KILL test_top1b_wrap_swipl.jl:352; pins e04 `Q> <-1>`, e02)",
         file=PFI, targets=TARGETS_EF,
         old="mem[from + rc - 1] == UInt8('\\n')",
         new="mem[from + rc - 1] == UInt8('\\r')"),
    dict(id="TOP1B-P06 Sread_user looks at the FIRST byte of the read for the newline, not the last (KILL test_top1b_wrap_swipl.jl:349-352 `ab\\n`)",
         file=PFI, targets=TARGETS_EF,
         old="rc > 0 && mem[from + rc - 1] ==",
         new="rc > 0 && mem[from] =="),
    dict(id="TOP1B-P07 Sread_user prompts on a raw tty and not on a cooked one (KILL test_top1b_wrap_swipl.jl:349-352, :367-371; e01)",
         file=PFI, targets=TARGETS_EF,
         old="if ld.prompt_next && Sttymode(s) != TTY_RAW",
         new="if ld.prompt_next && Sttymode(s) == TTY_RAW"),
    dict(id="TOP1B-P08 Sread_user prompts when `prompt.next` is OR the tty is cooked (KILL test_top1b_wrap_swipl.jl:359-365 `x` only, :317-321 `y` only)",
         file=PFI, targets=TARGETS_EF,
         old="if ld.prompt_next && Sttymode(s) != TTY_RAW",
         new="if ld.prompt_next || Sttymode(s) != TTY_RAW"),
    dict(id="TOP1B-P09 Sread_user does not flush user_output when no prompt is due (KILL test_top1b_wrap_swipl.jl:359-364 `x`, :317-320 `y`)",
         file=PFI, targets=TARGETS_EF,
         old="uo === nothing || Sflush(uo)",
         new="nothing"),
    dict(id="TOP1B-P10 a freed registry entry reads end of file (0) instead of an error (-1) (KILL test_top1b_wrap_swipl.jl:410-411: -1 and SIO_FERR)",
         file=PFI, targets=TARGETS_EF,
         old="::Vector{UInt8}, ::Int, ::Int\n)::Int = -1",
         new="::Vector{UInt8}, ::Int, ::Int\n)::Int = 0"),
    # ── pl-file.c closeWrappedIO ──
    dict(id="TOP1B-P11 closeWrappedIO does not give the cleared flag back (KILL test_top1b_wrap_swipl.jl:322, :333)",
         file=PFI, targets=TARGETS_EF,
         old="s.flags |= wio.saved_flags",
         new="nothing"),
    dict(id="TOP1B-P12 closeWrappedIO keeps the wrapper record on the closed stream (KILL test_top1b_wrap_swipl.jl:321, :333)",
         file=PFI, targets=TARGETS_EF,
         old="    s.wrapped = nothing\n    s.flags &= ~WRAP_CLEAR_FLAGS",
         new="    s.flags &= ~WRAP_CLEAR_FLAGS"),
    dict(id="TOP1B-P13 closeWrappedIO does not free the registry entry (KILL test_top1b_wrap_swipl.jl:323)",
         file=PFI, targets=TARGETS_EF,
         old="unregisterLocalData!(wio.table, wio.ld)\n\n    return rval",
         new="return rval"),
    # ── pl-file.c wrapIO ──
    dict(id="TOP1B-P14 wrapIO records the database in `ld.GD` only when the engine has one (negated) (KILL test_top1b_wrap_swipl.jl:276, :283)",
         file=PFI, targets=TARGETS_EF,
         old="ld.GD === nothing && (ld.GD = gd)",
         new="ld.GD === nothing || (ld.GD = gd)"),
    dict(id="TOP1B-P15 wrapIO does not save the flags it clears (KILL test_top1b_wrap_swipl.jl:271, :322; the close testset)",
         file=PFI, targets=TARGETS_EF,
         old="saved = s.flags & WRAP_CLEAR_FLAGS",
         new="saved = UInt32(0)"),
    dict(id="TOP1B-P16 wrapIO does not clear WRAP_CLEAR_FLAGS on the stream (KILL test_top1b_wrap_swipl.jl:272-273, :289, :308)",
         file=PFI, targets=TARGETS_EF,
         old="    s.flags &= ~WRAP_CLEAR_FLAGS\n    s.wrapped = wrappedIO(",
         new="    s.wrapped = wrappedIO("),
    dict(id="TOP1B-P17 wrapIO of a wrapped stream replaces `user_read` (a later non-user wrap undoes it) (KILL test_top1b_wrap_swipl.jl:307)",
         file=PFI, targets=TARGETS_EF,
         old="old.user_read |= read",
         new="old.user_read = read"),
    dict(id="TOP1B-P18 wrapIO twice leaves the first engine's registry entry in place (KILL test_top1b_wrap_swipl.jl:304)",
         file=PFI, targets=TARGETS_EF,
         old="unregisterLocalData!(old.table, old.ld)\n        old.table",
         new="old.table"),
    dict(id="TOP1B-P19 wrapIO twice keeps the first engine (the record's number is not renewed) (KILL test_top1b_wrap_swipl.jl:304-305)",
         file=PFI, targets=TARGETS_EF,
         old="old.ld = registerLocalData!(gd.ld_table, ld)",
         new="old.ld = old.ld"),
    # ── src/os/pl-stream.jl: the registry and the function sets ──
    dict(id="TOP1B-P20 registerLocalData! never reuses a free entry (KILL test_top1b_wrap_swipl.jl:247-248, :254)",
         file=ST, targets=TARGETS_EF,
         old="i = findfirst(isnothing, tbl)",
         new="i = nothing"),
    dict(id="TOP1B-P21 unregisterLocalData! takes an entry below 1 (KILL test_top1b_wrap_swipl.jl:249: index 0 raises)",
         file=ST, targets=TARGETS_EF,
         old="1 <= i <= length(tbl) &&",
         new="i <= length(tbl) &&"),
    dict(id="TOP1B-P22 unregisterLocalData! takes an entry above the table's length (KILL test_top1b_wrap_swipl.jl:250: index 9 raises)",
         file=ST, targets=TARGETS_EF,
         old="1 <= i <= length(tbl) &&",
         new="1 <= i &&"),
    dict(id="TOP1B-P23 unregisterLocalData! frees nothing (KILL test_top1b_wrap_swipl.jl:246, :323)",
         file=ST, targets=TARGETS_EF,
         old="&& (tbl[i] = nothing)",
         new="&& (tbl[i] = tbl[i])"),
    dict(id="TOP1B-P24 S_read ignores a stream that is wrapped for Sread_user (reads with `!w.user_read`) (KILL test_top1b_wrap_swipl.jl:349-352; e01-e03)",
         file=ST, targets=TARGETS_EF,
         old="if w !== nothing && w.user_read",
         new="if w !== nothing && !w.user_read"),
    dict(id="TOP1B-P25 S_close skips the wrapper's close (KILL test_top1b_wrap_swipl.jl:321-323, :333)",
         file=ST, targets=TARGETS_EF,
         old="w === nothing || return closeWrappedIO(s, w)",
         new="nothing"),
    dict(id="TOP1B-P26 S_write does not dispatch a Sstderrfunctions stream to Swrite_stderr (KILL test_top1b_wrap_swipl.jl:449-450, :505-506; e07 `E1`)",
         file=ST, targets=TARGETS_EF,
         old="s.functions == Sstderrfunctions && h isa IOSTREAM &&",
         new="false && h isa IOSTREAM &&"),
    dict(id="TOP1B-P27 S_close of a Sstderrfunctions stream falls through and closes the stream it copies (NOT equivalent: `h isa IOSTREAM && Sclose_string(h)`) (KILL test_top1b_wrap_swipl.jl:456-457 `uo.bufp == bufp0` + no 0 byte at the next Sflush(uo))",
         file=ST, targets=TARGETS_EF,
         old="s.functions == Sstderrfunctions && return 0",
         new="nothing"),
    # ── pl-file.c Swrite_stderr ──
    dict(id="TOP1B-P28 Swrite_stderr does not flush the stream it copies (KILL test_top1b_wrap_swipl.jl:496-497 `E`, :394-395; e07 `O1E2`)",
         file=PFI, targets=TARGETS_EF,
         old="(rc > 0 && Sflush(org) == 0) ? rc : -1",
         new="rc > 0 ? rc : -1"),
    dict(id="TOP1B-P29 Swrite_stderr answers 0 for no bytes (`rc >= 0`) (KILL test_top1b_wrap_swipl.jl:500)",
         file=PFI, targets=TARGETS_EF,
         old="(rc > 0 && Sflush(org) == 0)",
         new="(rc >= 0 && Sflush(org) == 0)"),
    dict(id="TOP1B-P30 Swrite_stderr counts two for each byte (KILL test_top1b_wrap_swipl.jl:496, :498)",
         file=PFI, targets=TARGETS_EF,
         old="Sputc(Int(mem[i]), org) < 0 && break\n        rc += 1",
         new="Sputc(Int(mem[i]), org) < 0 && break\n        rc += 2"),
    dict(id="TOP1B-P31 Swrite_stderr writes from index 1, not from `from` (KILL test_top1b_wrap_swipl.jl:496-497: `x` instead of `E`)",
         file=PFI, targets=TARGETS_EF,
         old="for i in from:(from + size - 1)\n        Sputc(Int(mem[i]), org)",
         new="for i in 1:size\n        Sputc(Int(mem[i]), org)"),
    # ── pl-file.c getIOStreams ──
    dict(id="TOP1B-P32 getIOStreams makes a separate error stream when Out and Error differ (negated) (KILL test_top1b_wrap_swipl.jl:435-436, :470; e07, e08)",
         file=PFI, targets=TARGETS_EF,
         old="PL_compare(ld, tout, terror) == CMP_EQUAL",
         new="PL_compare(ld, tout, terror) != CMP_EQUAL"),
    dict(id="TOP1B-P33 getIOStreams keeps WRAP_CLEAR_FLAGS on the error stream it makes (KILL test_top1b_wrap_swipl.jl:437)",
         file=PFI, targets=TARGETS_EF,
         old="Snew(out, out.flags & ~WRAP_CLEAR_FLAGS, Sstderrfunctions)",
         new="Snew(out, out.flags, Sstderrfunctions)"),
    dict(id="TOP1B-P34 getIOStreams does not set the error stream unbuffered (KILL test_top1b_wrap_swipl.jl:438, :471; e07 `<buf:line,false>`)",
         file=PFI, targets=TARGETS_EF,
         old="error.flags |= SIO_NBUF",
         new="nothing"),
    dict(id="TOP1B-P35 getIOStreams leaves the other buffering flags on the error stream (KILL test_top1b_wrap_swipl.jl:438, :471)",
         file=PFI, targets=TARGETS_EF,
         old="error.flags &= ~(SIO_FBUF | SIO_LBUF | SIO_NBUF)",
         new="nothing"),
    dict(id="TOP1B-P36 getIOStreams does not make Out line buffered (KILL test_top1b_wrap_swipl.jl:439; e07, e08 `<buf:line,false>`)",
         file=PFI, targets=TARGETS_EF,
         old="out.flags |= SIO_LBUF",
         new="nothing"),
    dict(id="TOP1B-P37 getIOStreams leaves the other buffering flags on Out (KILL test_top1b_wrap_swipl.jl:439: Out was fully buffered)",
         file=PFI, targets=TARGETS_EF,
         old="out.flags &= ~(SIO_FBUF | SIO_LBUF | SIO_NBUF)",
         new="nothing"),
    dict(id="TOP1B-P38 getIOStreams takes In as an output stream (KILL test_top1b_wrap_swipl.jl: pin e11b, user_output as In raises permission_error)",
         file=PFI, targets=TARGETS_EF,
         old="SH_ALIAS | SH_INPUT)\n    in === nothing",
         new="SH_ALIAS | SH_OUTPUT)\n    in === nothing"),
    dict(id="TOP1B-P39 getIOStreams takes Out as an input stream (KILL test_top1b_wrap_swipl.jl: pin e11c, an input stream as Out raises permission_error)",
         file=PFI, targets=TARGETS_EF,
         old="SH_ALIAS | SH_OUTPUT)\n    out === nothing",
         new="SH_ALIAS | SH_INPUT)\n    out === nothing"),
    # ── pl-file.c set_prolog_IO/3 ──
    dict(id="TOP1B-P40 set_prolog_IO/3 wraps In when it IS the user input (`===`) (KILL test_top1b_wrap_swipl.jl:440, :476; e01, e09)",
         file=PFI, targets=TARGETS_EF,
         old="wrapin = Suser_input(ld) !== in",
         new="wrapin = Suser_input(ld) === in"),
    dict(id="TOP1B-P41 set_prolog_IO/3 wraps In for a plain read (user_read false) (KILL test_top1b_wrap_swipl.jl:440; e01 prompt `|: `)",
         file=PFI, targets=TARGETS_EF,
         old="wrapIO(_query_gd(ld), ld, in, true)",
         new="wrapIO(_query_gd(ld), ld, in, false)"),
    dict(id="TOP1B-P42 set_prolog_IO/3 does not wrap In (KILL test_top1b_wrap_swipl.jl:440, :485; e01)",
         file=PFI, targets=TARGETS_EF,
         old="        wrapIO(_query_gd(ld), ld, in, true)\n",
         new=""),
    dict(id="TOP1B-P43 set_prolog_IO/3 does not arm the prompt after wrapping (KILL test_top1b_wrap_swipl.jl:422, :441)",
         file=PFI, targets=TARGETS_EF,
         old="wrapIO(_query_gd(ld), ld, in, true)\n        ld.prompt_next = true",
         new="wrapIO(_query_gd(ld), ld, in, true)"),
    dict(id="TOP1B-P44 set_prolog_IO/3 does not make In the user input (KILL test_top1b_wrap_swipl.jl:440; e01)",
         file=PFI, targets=TARGETS_EF,
         old="        setStandardStream(ld, SNO_USER_INPUT, in)\n",
         new=""),
    dict(id="TOP1B-P45 set_prolog_IO/3 does not make In the current input (KILL test_top1b_wrap_swipl.jl:442)",
         file=PFI, targets=TARGETS_EF,
         old="        setStandardStream(ld, SNO_CURRENT_INPUT, in)\n",
         new=""),
    dict(id="TOP1B-P46 set_prolog_IO/3 does not make the error stream the user error (KILL test_top1b_wrap_swipl.jl:435, :470; e07 `E1`)",
         file=PFI, targets=TARGETS_EF,
         old="    setStandardStream(ld, SNO_USER_ERROR, error)\n",
         new=""),
    dict(id="TOP1B-P47 set_prolog_IO/3 shares the positions from user_output on, not user_input (NOT equivalent: user_input is then left without SIO_RECORDPOS) (KILL test_top1b_wrap_swipl.jl:483 the e09 white-box `SIO_RECORDPOS` of ui3)",
         file=PFI, targets=TARGETS_EF,
         old="for i in SNO_USER_INPUT:SNO_USER_ERROR\n        st = ld.IO_streams[i + 1]::IOSTREAM\n        st.position",
         new="for i in SNO_USER_OUTPUT:SNO_USER_ERROR\n        st = ld.IO_streams[i + 1]::IOSTREAM\n        st.position"),
    dict(id="TOP1B-P48 set_prolog_IO/3 does not set SIO_RECORDPOS on the user streams (KILL test_top1b_wrap_swipl.jl:446, :483)",
         file=PFI, targets=TARGETS_EF,
         old="st.flags |= SIO_RECORDPOS",
         new="nothing"),
    dict(id="TOP1B-P49 set_prolog_IO/3 does not share the position record (KILL test_top1b_wrap_swipl.jl:445, :478-481; e12 `<lc:...>` shared line count)",
         file=PFI, targets=TARGETS_EF,
         old="st.position = posbuf",
         new="nothing"),
    dict(id="TOP1B-E2 Sread_user's third branch tests `rc >= 0` for a newline (EQUIVALENT)",
         file=PFI, targets=TARGETS_EF,
         old="elseif rc > 0 && mem[from + rc - 1]",
         new="elseif rc >= 0 && mem[from + rc - 1]",
         equivalent="src/os/pl-file.jl:3021-3027 — the branch `rc == 0` (end of file) is tested first and returns through the same if-chain, so an `elseif` "
                    "never sees rc == 0; for rc < 0 both tests are false; and for rc > 0 they agree"),
]
