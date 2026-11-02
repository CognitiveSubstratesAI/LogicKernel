# ORIGINAL: F1c's mutant list — no swipl-devel counterpart.
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
TD = "test/core_lang/test_debug_flag_swipl.jl"
TS = "test/core_lang/test_set_flag_swipl.jl"
TP = "test/core_lang/test_prolog_flag_swipl.jl"
TARGETS = [TD, TS, TP]                              # the baseline's targets (mutate_ci.py plan reads TARGETS)
P = "src/os/pl-prologflag.jl"
TR = "src/pl-trace.jl"
MUTANTS = [
    # ── the setter and the read side (src/os/pl-prologflag.jl set_flag_value, unify_prolog_flag_value) ──
    dict(id="F1C-A1 debug true does not call debugmode: the mode stays off (KILL db02, db03, db24)", file=P, targets=TARGETS,
         old="                rval = debugmode(ld, true, nothing, DBG_ALL)\n",
         new="                rval = true\n"),
    dict(id="F1C-A2 debug false does not call debugmode: the mode stays on (KILL db02, db03)", file=P, targets=TARGETS,
         old="                rval =\n                    tracemode(ld, false, nothing) &&\n                    debugmode(ld, false, nothing, UInt32(0))\n",
         new="                rval = tracemode(ld, false, nothing)\n"),
    dict(id="F1C-A3 debug false does not end the trace mode (KILL the white-box testset: tracing is on, then the query r_off)", file=P, targets=TARGETS,
         old="                rval =\n                    tracemode(ld, false, nothing) &&\n                    debugmode(ld, false, nothing, UInt32(0))\n",
         new="                rval = debugmode(ld, false, nothing, UInt32(0))\n"),
    dict(id="F1C-A4 debugger_show_context stores the negated value (KILL db04, white-box r_ctx)", file=P, targets=TARGETS,
         old="            ld.debugstatus_showContext = val\n",
         new="            ld.debugstatus_showContext = !val\n"),
    dict(id="F1C-A5 the read of debug is always false (KILL db02, db03, db24)", file=P, targets=TARGETS,
         old="        return PL_unify_bool_ex(ld, val, ld.debugstatus_debugging)\n",
         new="        return PL_unify_bool_ex(ld, val, false)\n"),
    dict(id="F1C-A6 the read of debugger_show_context is always false (KILL db04)", file=P, targets=TARGETS,
         old="        return PL_unify_bool_ex(ld, val, ld.debugstatus_showContext)\n",
         new="        return PL_unify_bool_ex(ld, val, false)\n"),
    # ── debugmode (src/pl-trace.jl) ──
    dict(id="F1C-B1 debugmode on does not reset the skip level (KILL white-box: skiplevel lowered to 0 before debugmode(true))", file=TR, targets=TARGETS,
         old="ld.debugstatus_skiplevel = SKIP_VERY_DEEP       # debugstatus.skiplevel = SKIP_VERY_DEEP\n",
         new="nothing\n"),
    dict(id="F1C-B2 debugmode on does not clear the run-mode bits (KILL white-box: LASTCALL and VMI_BUILTIN still set after r_on; db24, db25 in debug mode)", file=TR, targets=TARGETS,
         old="clearPrologRunMode!(ld, RUN_MODE_NORMAL)        # clearPrologRunMode(RUN_MODE_NORMAL)\n",
         new="nothing\n"),
    dict(id="F1C-B3 debugmode off does not set the run-mode bits back (KILL white-box: LASTCALL clear after r_off)", file=TR, targets=TARGETS,
         old="setPrologRunMode!(ld, RUN_MODE_NORMAL)          # setPrologRunMode(RUN_MODE_NORMAL)\n",
         new="nothing\n"),
    dict(id="F1C-B4 debugmode off while already off does not set the run-mode bits (KILL white-box: last_call_optimisation false, then debug false)", file=TR, targets=TARGETS,
         old="    elseif !doit\n        setPrologRunMode!(ld, RUN_MODE_NORMAL)\n",
         new="    elseif !doit\n        nothing\n"),
    dict(id="F1C-B5 debugmode on stores true whatever it was asked (KILL db02, db03)", file=TR, targets=TARGETS,
         old="ld.debugstatus_debugging = doit                     # debugstatus.debugging = doit\n",
         new="ld.debugstatus_debugging = true                     # debugstatus.debugging = doit\n"),
    dict(id="F1C-B6 debugmode sends no message (KILL white-box: one debug_mode message per change)", file=TR, targets=TARGETS,
         old="        updateAlerted(ld)\n        set = true\n",
         new="        updateAlerted(ld)\n"),
    dict(id="F1C-B7 debugmode writes the new mode to old (KILL white-box: debugmode(false, Ref) answers true)", file=TR, targets=TARGETS,
         old="old === nothing || (old[] = ld.debugstatus_debugging)\n",
         new="old === nothing || (old[] = doit)\n"),
    dict(id="F1C-B8 debugmode sends a trace_mode message (KILL white-box: debug_mode messages counted by name)", file=TR, targets=TARGETS,
         old="                ld, :debug_mode,",
         new="                ld, :trace_mode,"),
    # ── tracemode (src/pl-trace.jl) ──
    dict(id="F1C-C1 tracemode on does not switch the debug mode on (KILL white-box: tracemode(true) leaves debugging off)", file=TR, targets=TARGETS,
         old="debugmode(ld, true, nothing, UInt32(0))             # (the answer",
         new="true             # (the answer"),
    dict(id="F1C-C2 tracemode never stores the trace mode (KILL white-box: debugstatus_tracing after tracemode(true))", file=TR, targets=TARGETS,
         old="        ld.debugstatus_tracing = doit\n",
         new="        ld.debugstatus_tracing = false\n"),
    dict(id="F1C-C3 tracemode sends a debug_mode message (KILL white-box: trace_mode messages counted by name)", file=TR, targets=TARGETS,
         old="                ld,\n                :trace_mode,\n",
         new="                ld,\n                :debug_mode,\n"),
    dict(id="F1C-C4 tracemode on does not reset a lowered skip level (KILL white-box: skiplevel 0, tracemode(true) again)", file=TR, targets=TARGETS,
         old="        ld.debugstatus_skiplevel = SKIP_VERY_DEEP\n    end\n",
         new="        nothing\n    end\n"),
    dict(id="F1C-C5 tracemode writes the new mode to old (KILL white-box: the first tracemode(true, Ref(true)) answers false)", file=TR, targets=TARGETS,
         old="old === nothing || (old[] = ld.debugstatus_tracing)\n",
         new="old === nothing || (old[] = doit)\n"),
    dict(id="F1C-C6 the skip level of no skipping is zero (KILL white-box: skiplevel == typemax(UInt))", file=TR, targets=TARGETS,
         old="const SKIP_VERY_DEEP = typemax(UInt)\n",
         new="const SKIP_VERY_DEEP = UInt(0)\n"),
    # ── the run-mode bits (src/os/pl-prologflag.jl) ──
    dict(id="F1C-D1 the normal run mode lacks LASTCALL (KILL white-box: the LASTCALL bit after r_off, and cleared by r_on)", file=P, targets=TARGETS,
         old="prologFlagMask(PLFLAG_LASTCALL) | prologFlagMask(PLFLAG_VMI_BUILTIN)\n",
         new="prologFlagMask(PLFLAG_VMI_BUILTIN)\n"),
    dict(id="F1C-D2 the normal run mode lacks VMI_BUILTIN (KILL white-box: the VMI_BUILTIN bit after r_off, and cleared by r_on)", file=P, targets=TARGETS,
         old="prologFlagMask(PLFLAG_LASTCALL) | prologFlagMask(PLFLAG_VMI_BUILTIN)\n",
         new="prologFlagMask(PLFLAG_LASTCALL)\n"),
    dict(id="F1C-D3 setPrologRunMode! sets nothing (KILL white-box: LASTCALL after r_off and in the elseif row)", file=P, targets=TARGETS,
         old="    ld.prolog_flag_mask |= mask\n",
         new="    nothing\n"),
    dict(id="F1C-D4 clearPrologRunMode! sets the bits instead of clearing them (KILL white-box: the bits are set after r_on)", file=P, targets=TARGETS,
         old="    ld.prolog_flag_mask &= ~mask\n",
         new="    ld.prolog_flag_mask |= mask\n"),
    # ── the three build flags ──
    dict(id="F1C-E1 shared_object_extension is dll (KILL db15, db19)", file=P, targets=TARGETS,
         old="const SO_EXT = Sys.iswindows() ? \"dll\" : \"so\"\n",
         new="const SO_EXT = \"dll\"\n"),
    dict(id="F1C-E2 shared_object_extension is writable (KILL db16, db31)", file=P, targets=TARGETS,
         old="setPrologFlag(gd, \"shared_object_extension\", FT_ATOM | FF_READONLY, SO_EXT)",
         new="setPrologFlag(gd, \"shared_object_extension\", FT_ATOM, SO_EXT)"),
    dict(id="F1C-E3 version_git names another release (KILL db17)", file=P, targets=TARGETS,
         old="const GIT_VERSION = \"10.1.19-1-gcbf4e189\"\n",
         new="const GIT_VERSION = \"10.1.20-1-gcbf4e189\"\n"),
    dict(id="F1C-E4 version_git names another commit count of the same release (KILL white-box: the exact value of r_git)", file=P, targets=TARGETS,
         old="const GIT_VERSION = \"10.1.19-1-gcbf4e189\"\n",
         new="const GIT_VERSION = \"10.1.19-2-gcbf4e189\"\n"),
    dict(id="F1C-E5 version_git is writable (KILL db18, db32)", file=P, targets=TARGETS,
         old="setPrologFlag(gd, \"version_git\", FT_ATOM | FF_READONLY, GIT_VERSION)",
         new="setPrologFlag(gd, \"version_git\", FT_ATOM, GIT_VERSION)"),
    dict(id="F1C-E6 libswipl does not end in the shared-object extension (KILL db19)", file=P, targets=TARGETS,
         old="\"lib\", \"libswipl.\" * SO_EXT)",
         new="\"lib\", \"libswipl\")"),
    dict(id="F1C-E7 libswipl is read-only, as the oracle's (KILL white-box: access write, the known difference's pin)", file=P, targets=TARGETS,
         old="        \"libswipl\",\n        FT_ATOM,\n",
         new="        \"libswipl\",\n        FT_ATOM | FF_READONLY,\n"),
    # ── equivalent (four) ──
    dict(id="F1C-EQ1 the mask bit is set whatever debugmode answered", file=P, targets=TARGETS,
         old="        if f.index != 0 && rval\n",
         new="        if f.index != 0\n",
         equivalent="src/os/pl-prologflag.jl:1253: `rval` is false only if debugmode or tracemode answered false, and they answer printMessage's result (src/pl-error.jl:1025-1028 always returns true) or true (src/pl-trace.jl debugmode and tracemode returns); and the flag `debug`, the only one whose branch assigns `rval` (:1231, :1233), has index 0 (:1978 `setPrologFlag(gd, \"debug\", FT_BOOL, false, 0)`), so the conjunct is not even reached for it."),
    dict(id="F1C-EQ2 set_flag_value answers true whatever debugmode answered", file=P, targets=TARGETS,
         old="    return rval\n",
         new="    return true\n",
         equivalent="src/os/pl-prologflag.jl:1347: `rval` starts true (:1216) and only :1231 and :1233 assign it, with debugmode's and tracemode's answers, which are always true (src/pl-error.jl:1025-1028 printMessage returns true; src/pl-trace.jl debugmode and tracemode return it or true). No kernel path makes the C `have_space_for_debugging`/`validUserStreams` false (DBG1, comments at the sites)."),
    dict(id="F1C-EQ3 DBG_ALL has another value", file=TR, targets=TARGETS,
         old="const DBG_ALL = UInt32(0x1)\n",
         new="const DBG_ALL = UInt32(0x2)\n",
         equivalent="src/pl-trace.jl:142-172: `flags` is never read by debugmode (upstream reads it for `qf->debugSave`, pl-trace.c:2246-2249, which the kernel's query frame has no slot for: DBG1), and DBG_ALL is used only as the argument at src/os/pl-prologflag.jl:1231."),
    dict(id="F1C-EQ4 debugmode does not recompute the alert mask", file=TR, targets=TARGETS,
         old="        updateAlerted(ld)\n        set = true\n",
         new="        set = true\n",
         equivalent="src/pl-wam.jl:209-216: updateAlerted recomputes `ld.alerted` from the wakeup list alone (ALERT_WAKEUP from attvar_head), and nothing here changes it; the debugger's alert bits are not ported (the comment above the function, :205-207), so the call is a no-op in the kernel."),
]
