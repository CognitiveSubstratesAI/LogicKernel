# ORIGINAL: HF1's mutant list — no swipl-devel counterpart.
# tools/mutants/HF1.py — the mutation battery of the stacked pair HF1 = HALT1 + F1c, re-stacked on origin/main c4c34fd (audit D-0374 item 3):
# the union of HALT1.py (39 mutants, ids HALT1-*, F9 declared equivalent) and F1C.py (35 mutants, ids F1C-*, EQ1-EQ4 declared equivalent), each
# mutant with the `targets` it had on its own branch. The pair's changes overlap in src/pl-global.jl (the halt fields of PL_global_data, the debugstatus
# fields of PL_local_data) and in the manifest and docs files; no mutant of one step mutates code that the other step's tests run (HALT1's tests
# never set `debug`, F1c's tests never call halt/1 or abort/0), so no target list was widened. The two steps' own headers follow, unchanged.
# The `equivalent` line numbers were re-read at the HF1 tip.
#
# ── HALT1 header ──
# tools/mutants/HALT1.py — the mutation battery of HALT1: halt/1 (pl-prims.c), PL_halt, haltProlog and PL_abort_process (pl-fli.c),
# PL_cleanup (pl-init.c), abort/0, abortProlog and raise_halt_exception (pl-pro.c), handles_unwind (pl-wam.c), PL_get_signum_ex
# and signal_index (pl-setup.c). Run ONCE, in CI (.github/workflows/mutation.yml; locally: tools/mutate.sh run). Format:
# tools/mutate_drive.py's (as BOOTPRED3.py): `id`, `file`, `old` (must occur EXACTLY once), `new`, optional `equivalent` and
# `targets`. Killed by test/core_lang/test_halt_swipl.jl (testsets 1-8: balls and exit statuses, error rows, the seam, the cancel
# limit, signal_index, the gated rows, the direct calls). Verdicts: written by the battery, not yet run.
# The `old` strings were checked to occur exactly once in their file at the commit that adds this list (a text count, no Julia);
# RE-FIT any that `tools/warm.sh fmt` rewraps.
# TARGETS (audit D-0238): test_halt_swipl.jl is the only file that runs halt/1, abort/0 and the halt seam. The registration
# mutants also list the files that walk the dispatch tables (test/foreign/test_builtins_swipl.jl) and the file that runs
# sig_atomic/1, the next entry of pl-pro.c's table (test_cleanup_swipl.jl); the ball mutants list test_catch_swipl.jl (an unwind(_)
# ball reaching a catcher) and test/foreign/test_exceptions_swipl.jl (the classification of unwind(abort) and unwind(halt(_))).
#
# ── F1c header ──
# tools/mutants/F1C.py — the mutation battery of F1c (pl-prologflag.c set_flag_value / unify_prolog_flag_value for `debug` and
# `debugger_show_context`, initPrologFlags set_libswipl / shared_object_extension, pl-version.c setGITVersion; pl-trace.c debugmode,
# tracemode; pl-incl.h RUN_MODE_NORMAL / setPrologRunMode / clearPrologRunMode), run ONCE, in CI (.github/workflows/mutation.yml;
# locally: tools/mutate.sh run).
# Format: tools/mutate_drive.py's (as F2.py and MOD3b.py): `id`, `file`, `old` (must occur EXACTLY once), `new`, optional
# `equivalent` and `targets`. Rows named in each id's KILL: db01-db35 of test/core_lang/test_debug_flag_swipl.jl (the oracle rows) and its
# last testset ("white-box": direct debugmode / tracemode calls, the run-mode bits, the messages, the exact version_git, libswipl's access).
# TARGETS (D-0238), re-grepped at wip/f1c over test/ for debug, debugger_show_context, libswipl, version_git, shared_object_extension,
# debugmode, tracemode, RunMode, debugstatus: test_debug_flag_swipl.jl (every mutant), test_set_flag_swipl.jl (calls set_flag_value
# through other flags, so it runs the changed function), test_prolog_flag_swipl.jl (+ its .pl: reads the flag `debug` as an
# integer/atom value, and its key-set testset expects libswipl, shared_object_extension and version_git DEFINED). NOT listed:
# test_push_flag_swipl.jl (no longer sets `debug`: it names it only in a header comment), test_gate_split.jl (its `version_git` is
# a fake swipl for tools/, not the kernel's flag), test_compiler_warnings_swipl.jl / test_qlf_swipl.jl (`debugstatus_styleCheck`, a field of
# the style checks, none of the mutated code), the libswipl mentions of test_exceptions_swipl.jl, test_builtins_swipl.jl, test_rules_swipl.jl,
# test_query.jl (comments: the C library, not the flag).
# Verdicts: written by the battery, not yet run. Every `old` was counted EXACTLY once in its file at wip/f1c by a throwaway
# python3 -I script (no Julia ran): the count is in the commit message. RE-FIT any `old` that `tools/warm.sh fmt` rewraps.
# EQUIVALENT (four, each with its file:line reason): F1C-EQ1 the `&& rval` mask guard, F1C-EQ2 `return rval`, F1C-EQ3 the DBG_ALL
# value, F1C-EQ4 `updateAlerted` in debugmode.
TH = ["test/core_lang/test_halt_swipl.jl"]
TREG = TH + ["test/foreign/test_builtins_swipl.jl", "test/core_lang/test_cleanup_swipl.jl"]
TBALL = TH + ["test/core_lang/test_catch_swipl.jl", "test/foreign/test_exceptions_swipl.jl"]
TD = "test/core_lang/test_debug_flag_swipl.jl"
TS = "test/core_lang/test_set_flag_swipl.jl"
TP = "test/core_lang/test_prolog_flag_swipl.jl"
TF = [TD, TS, TP]
TARGETS = TH + TF                                   # the baseline's targets (mutate_ci.py plan reads TARGETS): each step's own baseline, joined
PRO = "src/pl-pro.jl"
WAM = "src/pl-wam.jl"
FLI = "src/pl-fli.jl"
INI = "src/pl-init.jl"
SET = "src/pl-setup.jl"
PRIMS = "src/pl-prims.jl"
P = "src/os/pl-prologflag.jl"
TR = "src/pl-trace.jl"
MUTANTS = [
    # ── pl-pro.c raise_halt_exception, abortProlog, abort/0 ──
    dict(id="HALT1-A1 the halt code is masked to 8 bits, not Status & 0xffff (KILL testset 1: halt(-1), halt(256), halt(65536))",
         file=PRO, targets=TBALL,
         old="    code = status & PL_CLEANUP_STATUS_MASK\n",
         new="    code = status & 0xff\n"),
    dict(id="HALT1-A2 force is dropped: a forced halt exception is raised only where a query handles it (KILL testset 8)",
         file=PRO, targets=TH,
         old="    if force || handles_unwind(ld, 0, PL_Q_EXCEPT_HALT)\n",
         new="    if handles_unwind(ld, 0, PL_Q_EXCEPT_HALT)\n"),
    dict(id="HALT1-A3 the halt exception is raised whether or not a query handles it (KILL testset 3: a query without PL_Q_EXCEPT_HALT must reach the seam)",
         file=PRO, targets=TH,
         old="    if force || handles_unwind(ld, 0, PL_Q_EXCEPT_HALT)\n",
         new="    if true\n"),
    dict(id="HALT1-A4 the halt ball has another functor: unwind(hal(Code)) (KILL testset 1, 8)",
         file=PRO, targets=TBALL,
         old="_message_term(ld, :unwind, _message_term(ld, :halt, _err_int(ld, code)))",
         new="_message_term(ld, :unwind, _message_term(ld, :hal, _err_int(ld, code)))"),
    dict(id="HALT1-A5 the abort ball has another argument: unwind(abor) (KILL testset 1, 6)",
         file=PRO, targets=TBALL,
         old="ex = _message_term(ld, :unwind, _err_atom(ld, mk_sym(T, :abort)))",
         new="ex = _message_term(ld, :unwind, _err_atom(ld, mk_sym(T, :abor)))"),
    dict(id="HALT1-A6 abort/0 is registered under another name (KILL testset 1: abort is unknown)",
         file=PRO, targets=TREG,
         old='    PL_extension("abort", 0, pl_abort0_va, PL_FA_VARARGS),\n',
         new='    PL_extension("abortx", 0, pl_abort0_va, PL_FA_VARARGS),\n'),
    # ── pl-wam.c handles_unwind ──
    dict(id="HALT1-W1 handles_unwind tests for the absence of the flag (KILL testset 1, 3)",
         file=WAM, targets=TH,
         old="(q.flags & flags) != 0 && return true",
         new="(q.flags & flags) == 0 && return true"),
    dict(id="HALT1-W2 handles_unwind does not walk to the parent query (KILL testset 1: sig_atomic/1 opens a query without the flag, its parent has it)",
         file=WAM, targets=TH,
         old="        qf = q.parent\n",
         new="        qf = 0\n"),
    # ── pl-fli.c PL_halt, haltProlog, PL_abort_process ──
    dict(id="HALT1-F1 PL_halt raises the halt exception only where the flag is NOT set (KILL testset 1, 3)",
         file=FLI, targets=TH,
         old="if (status & PL_HALT_WITH_EXCEPTION) != 0 && raise_halt_exception(ld, status, false)",
         new="if (status & PL_HALT_WITH_EXCEPTION) == 0 && raise_halt_exception(ld, status, false)"),
    dict(id="HALT1-F2 PL_halt goes ahead when the clean-up was cancelled and cancels when it was not (KILL testset 3, 4)",
         file=FLI, targets=TH,
         old="    if haltProlog(gd, ld, status)\n",
         new="    if !haltProlog(gd, ld, status)\n"),
    dict(id="HALT1-F3 the seam gets the status masked to 8 bits (KILL testset 3: raw & 0xffff == 256 for halt(256))",
         file=FLI, targets=TH,
         old="        _halt_exit!(gd, status) ",
         new="        _halt_exit!(gd, status & 0xff) "),
    dict(id="HALT1-F4 a cancelled halt makes PL_halt return false (halt/1 fails instead of succeeding) (KILL testset 4)",
         file=FLI, targets=TH,
         old="    gd.halt_thread = 0\n\n    return true\n",
         new="    gd.halt_thread = 0\n\n    return false\n"),
    dict(id="HALT1-F5 halt(abort) can be cancelled: PL_abort_process drops PL_CLEANUP_NO_CANCEL (KILL testset 4)",
         file=FLI, targets=TH,
         old="haltProlog(gd, ld, (128 + 6) | PL_CLEANUP_NO_CANCEL)",
         new="haltProlog(gd, ld, 128 + 6)"),
    dict(id="HALT1-F6 halt(abort) ends with status 135 (KILL testset 3: halt_exited == [134])",
         file=FLI, targets=TH,
         old="_halt_exit!(gd, 128 + 6) ",
         new="_halt_exit!(gd, 128 + 7) "),
    dict(id="HALT1-F7 haltProlog treats a recursive clean-up as one that went ahead (KILL testset 8)",
         file=FLI, targets=TH,
         old="if rc == PL_CLEANUP_CANCELED || rc == PL_CLEANUP_RECURSIVE",
         new="if rc == PL_CLEANUP_CANCELED"),
    dict(id="HALT1-F8 haltProlog leaves the state at CLN_DATA, not CLN_ATEXIT (KILL testset 8)",
         file=FLI, targets=TH,
         old="    gd.halt_cleaning = CLN_ATEXIT ",
         new="    gd.halt_cleaning = CLN_DATA "),
    dict(id="HALT1-F9 haltProlog keeps PL_HALT_WITH_EXCEPTION in the status it hands to PL_cleanup",
         file=FLI, targets=TH,
         old="    status &= ~PL_HALT_WITH_EXCEPTION\n",
         new="    status &= ~0\n",
         equivalent="PL_cleanup reads only `status & PL_CLEANUP_STATUS_MASK` (src/pl-init.jl:40) and `status & PL_CLEANUP_NO_CANCEL` "
                    "(src/pl-init.jl:47); PL_HALT_WITH_EXCEPTION (0x40000) is outside the mask and is not NO_CANCEL (0x20000), and "
                    "haltProlog passes the status to nothing else (src/pl-fli.jl:1351-1362)"),
    # ── pl-init.c PL_cleanup, MAX_HALT_CANCELLED, the $run_at_halt query ──
    dict(id="HALT1-I1 MAX_HALT_CANCELLED is 11: the tenth halt is still cancelled (KILL testset 4)",
         file=INI, targets=TH,
         old="const MAX_HALT_CANCELLED = 10\n",
         new="const MAX_HALT_CANCELLED = 11\n"),
    dict(id="HALT1-I2 the cancel counter is compared with <=: the tenth halt is still cancelled (KILL testset 4)",
         file=INI, targets=TH,
         old="if gd.halt_cancelled < MAX_HALT_CANCELLED",
         new="if gd.halt_cancelled <= MAX_HALT_CANCELLED"),
    dict(id="HALT1-I3 PL_CLEANUP_NO_CANCEL is not honoured: a signal name and halt(abort) can be cancelled (KILL testset 4)",
         file=INI, targets=TH,
         old="if !_query_run_at_halt(gd, ld) && (status & PL_CLEANUP_NO_CANCEL) == 0",
         new="if !_query_run_at_halt(gd, ld)"),
    dict(id="HALT1-I4 the exit_status flag is the status masked to 8 bits (KILL testset 3: halt(256) sets 256)",
         file=INI, targets=TH,
         old="    rval = status & PL_CLEANUP_STATUS_MASK\n",
         new="    rval = status & 0xff\n"),
    dict(id="HALT1-I5 a clean-up while one runs reports success, not RECURSIVE (KILL testset 8)",
         file=INI, targets=TH,
         old="gd.halt_cleaning != CLN_NORMAL && return PL_CLEANUP_RECURSIVE",
         new="gd.halt_cleaning != CLN_NORMAL && return PL_CLEANUP_SUCCESS"),
    dict(id="HALT1-I6 the exit_status flag is one too high (KILL testset 3, 8)",
         file=INI, targets=TH,
         old='setPrologFlag(gd, "exit_status", FT_INTEGER, rval)',
         new='setPrologFlag(gd, "exit_status", FT_INTEGER, rval + 1)'),
    dict(id="HALT1-I7 '$run_at_halt' never runs (KILL testset 4: a vetoing hook cancels nothing)",
         file=INI, targets=TH,
         old="    isDefinedProcedure(gd, proc) || return true\n",
         new="    return true\n"),
    dict(id="HALT1-I8 a hook that raises counts as a veto (KILL testset 8)",
         file=INI, targets=TH,
         old="rval = PL_next_solution(gd, ld, qid) != 0 || PL_exception(ld, qid) != 0",
         new="rval = PL_next_solution(gd, ld, qid) != 0"),
    dict(id="HALT1-I9 the '$run_at_halt' query is opened without PL_Q_EXCEPT_HALT (KILL testset 8: a hook that halts, then fails)",
         file=INI, targets=TH,
         old="gd, ld, MODULE_system(gd), PL_Q_NORMAL | PL_Q_EXCEPT_HALT, proc,",
         new="gd, ld, MODULE_system(gd), PL_Q_NORMAL, proc,"),
    # ── pl-setup.c signal_index, PL_get_signum_ex ──
    dict(id="HALT1-S1 the SIG prefix is stripped only in lowercase (KILL testset 1, 5)",
         file=SET, targets=TH,
         old='startswith(name, "SIG") && ncodeunits(name) < 12',
         new='startswith(name, "sig") && ncodeunits(name) < 12'),
    dict(id="HALT1-S2 the name after SIG is not lowercased (KILL testset 1, 5: SIGTERM)",
         file=SET, targets=TH,
         old="name = lowercase(SubString(name, 4))",
         new="name = SubString(name, 4)"),
    dict(id="HALT1-S3 term is signal 14 (KILL testset 1, 3, 5)",
         file=SET, targets=TH,
         old='("term", 15)',
         new='("term", 14)'),
    dict(id="HALT1-S4 signal 0 is accepted (KILL testset 8)",
         file=SET, targets=TH,
         old="if i > 0 && i < 32",
         new="if i >= 0 && i < 32"),
    dict(id="HALT1-S5 signal 32 is accepted (KILL testset 8)",
         file=SET, targets=TH,
         old="if i > 0 && i < 32",
         new="if i > 0 && i <= 32"),
    dict(id="HALT1-S6 a term that is no signal is a domain error, not a type error (KILL testset 2: halt([]))",
         file=SET, targets=TH,
         old="PL_error(ld, ERR_TYPE, mk_sym(T, :signal), sig)",
         new="PL_error(ld, ERR_DOMAIN, mk_sym(T, :signal), sig)"),
    dict(id="HALT1-S7 the reserved symbol [] is taken as a signal name (KILL testset 2: halt([]))",
         file=SET, targets=TH,
         old="a !== nothing && !is_reserved_symbol(a) && !is_blob(a)",
         new="a !== nothing && !is_blob(a)"),
    # ── pl-prims.c halt/1 ──
    dict(id="HALT1-H1 a signal name gives the signal number, not 128 + signal (KILL testset 1, 3)",
         file=PRIMS, targets=TH,
         old="        status = signum + 128\n",
         new="        status = signum\n"),
    dict(id="HALT1-H2 a signal name does not set PL_CLEANUP_NO_CANCEL (KILL testset 3, 4)",
         file=PRIMS, targets=TH,
         old="        status |= PL_CLEANUP_NO_CANCEL\n",
         new="        status |= 0\n"),
    dict(id="HALT1-H3 halt(abort) is a signal-name lookup (KILL testset 3, 4: halt(abort) answers domain_error(signal,abort) or 134)",
         file=PRIMS, targets=TH,
         old="if sym_key(a) == sym_key(mk_sym(T, :abort))",
         new="if sym_key(a) == sym_key(mk_sym(T, :abor))"),
    dict(id="HALT1-H4 halt/1 hands PL_halt no PL_HALT_WITH_EXCEPTION: no ball is raised (KILL testset 1)",
         file=PRIMS, targets=TH,
         old="return PL_halt(gd, ld, status | PL_HALT_WITH_EXCEPTION) ? FTRUE : FFALSE",
         new="return PL_halt(gd, ld, status) ? FTRUE : FFALSE"),
    dict(id="HALT1-H5 halt/1 inverts PL_halt's verdict (KILL testset 3, 4)",
         file=PRIMS, targets=TH,
         old="return PL_halt(gd, ld, status | PL_HALT_WITH_EXCEPTION) ? FTRUE : FFALSE",
         new="return PL_halt(gd, ld, status | PL_HALT_WITH_EXCEPTION) ? FFALSE : FTRUE"),
    dict(id="HALT1-H6 halt/1 is registered under another name (KILL testset 1: halt is unknown)",
         file=PRIMS, targets=TREG,
         old='PL_extension("halt", 1, pl_halt1_va, PL_FA_VARARGS)',
         new='PL_extension("haltx", 1, pl_halt1_va, PL_FA_VARARGS)'),
    # ── the setter and the read side (src/os/pl-prologflag.jl set_flag_value, unify_prolog_flag_value) ──
    dict(id="F1C-A1 debug true does not call debugmode: the mode stays off (KILL db02, db03, db24)", file=P, targets=TF,
         old="                rval = debugmode(ld, true, nothing, DBG_ALL)\n",
         new="                rval = true\n"),
    dict(id="F1C-A2 debug false does not call debugmode: the mode stays on (KILL db02, db03)", file=P, targets=TF,
         old="                rval =\n                    tracemode(ld, false, nothing) &&\n                    debugmode(ld, false, nothing, UInt32(0))\n",
         new="                rval = tracemode(ld, false, nothing)\n"),
    dict(id="F1C-A3 debug false does not end the trace mode (KILL the white-box testset: tracing is on, then the query r_off)", file=P, targets=TF,
         old="                rval =\n                    tracemode(ld, false, nothing) &&\n                    debugmode(ld, false, nothing, UInt32(0))\n",
         new="                rval = debugmode(ld, false, nothing, UInt32(0))\n"),
    dict(id="F1C-A4 debugger_show_context stores the negated value (KILL db04, white-box r_ctx)", file=P, targets=TF,
         old="            ld.debugstatus_showContext = val\n",
         new="            ld.debugstatus_showContext = !val\n"),
    dict(id="F1C-A5 the read of debug is always false (KILL db02, db03, db24)", file=P, targets=TF,
         old="        return PL_unify_bool_ex(ld, val, ld.debugstatus_debugging)\n",
         new="        return PL_unify_bool_ex(ld, val, false)\n"),
    dict(id="F1C-A6 the read of debugger_show_context is always false (KILL db04)", file=P, targets=TF,
         old="        return PL_unify_bool_ex(ld, val, ld.debugstatus_showContext)\n",
         new="        return PL_unify_bool_ex(ld, val, false)\n"),
    # ── debugmode (src/pl-trace.jl) ──
    dict(id="F1C-B1 debugmode on does not reset the skip level (KILL white-box: skiplevel lowered to 0 before debugmode(true))", file=TR, targets=TF,
         old="ld.debugstatus_skiplevel = SKIP_VERY_DEEP       # debugstatus.skiplevel = SKIP_VERY_DEEP\n",
         new="nothing\n"),
    dict(id="F1C-B2 debugmode on does not clear the run-mode bits (KILL white-box: LASTCALL and VMI_BUILTIN still set after r_on; db24, db25 in debug mode)", file=TR, targets=TF,
         old="clearPrologRunMode!(ld, RUN_MODE_NORMAL)        # clearPrologRunMode(RUN_MODE_NORMAL)\n",
         new="nothing\n"),
    dict(id="F1C-B3 debugmode off does not set the run-mode bits back (KILL white-box: LASTCALL clear after r_off)", file=TR, targets=TF,
         old="setPrologRunMode!(ld, RUN_MODE_NORMAL)          # setPrologRunMode(RUN_MODE_NORMAL)\n",
         new="nothing\n"),
    dict(id="F1C-B4 debugmode off while already off does not set the run-mode bits (KILL white-box: last_call_optimisation false, then debug false)", file=TR, targets=TF,
         old="    elseif !doit\n        setPrologRunMode!(ld, RUN_MODE_NORMAL)\n",
         new="    elseif !doit\n        nothing\n"),
    dict(id="F1C-B5 debugmode on stores true whatever it was asked (KILL db02, db03)", file=TR, targets=TF,
         old="ld.debugstatus_debugging = doit                     # debugstatus.debugging = doit\n",
         new="ld.debugstatus_debugging = true                     # debugstatus.debugging = doit\n"),
    dict(id="F1C-B6 debugmode sends no message (KILL white-box: one debug_mode message per change)", file=TR, targets=TF,
         old="        updateAlerted(ld)\n        set = true\n",
         new="        updateAlerted(ld)\n"),
    dict(id="F1C-B7 debugmode writes the new mode to old (KILL white-box: debugmode(false, Ref) answers true)", file=TR, targets=TF,
         old="old === nothing || (old[] = ld.debugstatus_debugging)\n",
         new="old === nothing || (old[] = doit)\n"),
    dict(id="F1C-B8 debugmode sends a trace_mode message (KILL white-box: debug_mode messages counted by name)", file=TR, targets=TF,
         old="                ld, :debug_mode,",
         new="                ld, :trace_mode,"),
    # ── tracemode (src/pl-trace.jl) ──
    dict(id="F1C-C1 tracemode on does not switch the debug mode on (KILL white-box: tracemode(true) leaves debugging off)", file=TR, targets=TF,
         old="debugmode(ld, true, nothing, UInt32(0))             # (the answer",
         new="true             # (the answer"),
    dict(id="F1C-C2 tracemode never stores the trace mode (KILL white-box: debugstatus_tracing after tracemode(true))", file=TR, targets=TF,
         old="        ld.debugstatus_tracing = doit\n",
         new="        ld.debugstatus_tracing = false\n"),
    dict(id="F1C-C3 tracemode sends a debug_mode message (KILL white-box: trace_mode messages counted by name)", file=TR, targets=TF,
         old="                ld,\n                :trace_mode,\n",
         new="                ld,\n                :debug_mode,\n"),
    dict(id="F1C-C4 tracemode on does not reset a lowered skip level (KILL white-box: skiplevel 0, tracemode(true) again)", file=TR, targets=TF,
         old="        ld.debugstatus_skiplevel = SKIP_VERY_DEEP\n    end\n",
         new="        nothing\n    end\n"),
    dict(id="F1C-C5 tracemode writes the new mode to old (KILL white-box: the first tracemode(true, Ref(true)) answers false)", file=TR, targets=TF,
         old="old === nothing || (old[] = ld.debugstatus_tracing)\n",
         new="old === nothing || (old[] = doit)\n"),
    dict(id="F1C-C6 the skip level of no skipping is zero (KILL white-box: skiplevel == typemax(UInt))", file=TR, targets=TF,
         old="const SKIP_VERY_DEEP = typemax(UInt)\n",
         new="const SKIP_VERY_DEEP = UInt(0)\n"),
    # ── the run-mode bits (src/os/pl-prologflag.jl) ──
    dict(id="F1C-D1 the normal run mode lacks LASTCALL (KILL white-box: the LASTCALL bit after r_off, and cleared by r_on)", file=P, targets=TF,
         old="prologFlagMask(PLFLAG_LASTCALL) | prologFlagMask(PLFLAG_VMI_BUILTIN)\n",
         new="prologFlagMask(PLFLAG_VMI_BUILTIN)\n"),
    dict(id="F1C-D2 the normal run mode lacks VMI_BUILTIN (KILL white-box: the VMI_BUILTIN bit after r_off, and cleared by r_on)", file=P, targets=TF,
         old="prologFlagMask(PLFLAG_LASTCALL) | prologFlagMask(PLFLAG_VMI_BUILTIN)\n",
         new="prologFlagMask(PLFLAG_LASTCALL)\n"),
    dict(id="F1C-D3 setPrologRunMode! sets nothing (KILL white-box: LASTCALL after r_off and in the elseif row)", file=P, targets=TF,
         old="    ld.prolog_flag_mask |= mask\n",
         new="    nothing\n"),
    dict(id="F1C-D4 clearPrologRunMode! sets the bits instead of clearing them (KILL white-box: the bits are set after r_on)", file=P, targets=TF,
         old="    ld.prolog_flag_mask &= ~mask\n",
         new="    ld.prolog_flag_mask |= mask\n"),
    # ── the three build flags ──
    dict(id="F1C-E1 shared_object_extension is dll (KILL db15, db19)", file=P, targets=TF,
         old="const SO_EXT = Sys.iswindows() ? \"dll\" : \"so\"\n",
         new="const SO_EXT = \"dll\"\n"),
    dict(id="F1C-E2 shared_object_extension is writable (KILL db16, db31)", file=P, targets=TF,
         old="setPrologFlag(gd, \"shared_object_extension\", FT_ATOM | FF_READONLY, SO_EXT)",
         new="setPrologFlag(gd, \"shared_object_extension\", FT_ATOM, SO_EXT)"),
    dict(id="F1C-E3 version_git names another release (KILL db17)", file=P, targets=TF,
         old="const GIT_VERSION = \"10.1.19-1-gcbf4e189\"\n",
         new="const GIT_VERSION = \"10.1.20-1-gcbf4e189\"\n"),
    dict(id="F1C-E4 version_git names another commit count of the same release (KILL white-box: the exact value of r_git)", file=P, targets=TF,
         old="const GIT_VERSION = \"10.1.19-1-gcbf4e189\"\n",
         new="const GIT_VERSION = \"10.1.19-2-gcbf4e189\"\n"),
    dict(id="F1C-E5 version_git is writable (KILL db18, db32)", file=P, targets=TF,
         old="setPrologFlag(gd, \"version_git\", FT_ATOM | FF_READONLY, GIT_VERSION)",
         new="setPrologFlag(gd, \"version_git\", FT_ATOM, GIT_VERSION)"),
    dict(id="F1C-E6 libswipl does not end in the shared-object extension (KILL db19)", file=P, targets=TF,
         old="\"lib\", \"libswipl.\" * SO_EXT)",
         new="\"lib\", \"libswipl\")"),
    dict(id="F1C-E7 libswipl is read-only, as the oracle's (KILL white-box: access write, the known difference's pin)", file=P, targets=TF,
         old="        \"libswipl\",\n        FT_ATOM,\n",
         new="        \"libswipl\",\n        FT_ATOM | FF_READONLY,\n"),
    # ── equivalent (four) ──
    dict(id="F1C-EQ1 the mask bit is set whatever debugmode answered", file=P, targets=TF,
         old="        if f.index != 0 && rval\n",
         new="        if f.index != 0\n",
         equivalent="src/os/pl-prologflag.jl:1255: `rval` is false only if debugmode or tracemode answered false, and they answer printMessage's result (src/pl-error.jl:1025-1028 always returns true) or true (src/pl-trace.jl debugmode and tracemode returns); and the flag `debug`, the only one whose branch assigns `rval` (:1231, :1233), has index 0 (:1985 `setPrologFlag(gd, \"debug\", FT_BOOL, false, 0)`), so the conjunct is not even reached for it."),
    dict(id="F1C-EQ2 set_flag_value answers true whatever debugmode answered", file=P, targets=TF,
         old="    return rval\n",
         new="    return true\n",
         equivalent="src/os/pl-prologflag.jl:1349: `rval` starts true (:1216) and only :1231 and :1233 assign it, with debugmode's and tracemode's answers, which are always true (src/pl-error.jl:1025-1028 printMessage returns true; src/pl-trace.jl debugmode and tracemode return it or true). No kernel path makes the C `have_space_for_debugging`/`validUserStreams` false (DBG1, comments at the sites)."),
    dict(id="F1C-EQ3 DBG_ALL has another value", file=TR, targets=TF,
         old="const DBG_ALL = UInt32(0x1)\n",
         new="const DBG_ALL = UInt32(0x2)\n",
         equivalent="src/pl-trace.jl:142-172: `flags` is never read by debugmode (upstream reads it for `qf->debugSave`, pl-trace.c:2246-2249, which the kernel's query frame has no slot for: DBG1), and DBG_ALL is used only as the argument at src/os/pl-prologflag.jl:1231."),
    dict(id="F1C-EQ4 debugmode does not recompute the alert mask", file=TR, targets=TF,
         old="        updateAlerted(ld)\n        set = true\n",
         new="        set = true\n",
         equivalent="src/pl-wam.jl:209-216: updateAlerted recomputes `ld.alerted` from the wakeup list alone (ALERT_WAKEUP from attvar_head), and nothing here changes it; the debugger's alert bits are not ported (the comment above the function, :205-207), so the call is a no-op in the kernel."),
]
