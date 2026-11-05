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
# WAITING (pieces E, F, G, H: the stream-handle question, plan section 7 Q1, A-0321): the mutants M21-M23 and M25 ff. of the plan
# (the `ld` reference in a stream handle, the `Sread_terminal` / `Sread_user` prompt, `ResetTty` in `initIO`, `_query_run_at_halt`) are
# written when their code exists; this list covers A-D only.
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
         old="    end\n    ld.break_level = old_level\n\n    ld.debugstatus_skiplevel",
         new="    end\n\n    ld.debugstatus_skiplevel"),
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
]
