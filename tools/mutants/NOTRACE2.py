# ORIGINAL: DBG1-SMALL's mutant list ('$notrace'/2 and '$restore_trace'/2 of pl-pro.c:311-390); its counterpart is the port itself.
# tools/mutants/NOTRACE2.py — the mutation battery of DBG1-SMALL (audit D-0431 item 2): the debugger status that
# `'$notrace'/2` saves and clears and `'$restore_trace'/2` restores (src/pl-pro.jl `pl_notrace2_va`, `pl_restore_trace2_va`; the
# constant SKIP_REDO_IN_SKIP in src/pl-trace.jl). Run ONCE, in CI (.github/workflows/mutation.yml; locally: tools/mutate.sh run).
# Format: tools/mutate_drive.py's (as CT1A.py): `id`, `file`, `old` (must occur EXACTLY once), `new`, `targets`.
# Killed by test/core_lang/test_notrace_swipl.jl (rows nt01-nt22, named in each id's KILL). Verdicts: written by the battery, not yet run.
# Every `old` was checked to occur exactly once in its file at wip/notrace2 (a python3 -I count over MUTANTS); the lines the
# BOOTPREDSUB mutants BP3-N1..N4 and BP3-R1..R8 use are untouched by this port, so their `old` strings still occur once.
# NOT LISTED (each with its reason):
#   * `updateAlerted(ld)` in the two predicates: the kernel's `ld.alerted` has no debugger bits (src/pl-wam.jl), the call is the same as
#     BOOTPREDSUB's declared-equivalent (tools/mutants/BOOTPREDSUB.py header).
#   * the `@assert ... <= UInt(typemax(Int64))` of the level read: an exception from a foreign predicate would be judged by the
#     driver's error path, not by a failing row; nt07 (2^63-1) pins the largest level that passes.
# TARGETS (audit D-0238): the two predicates run in test_notrace_swipl.jl and test_bootpred3_swipl.jl (rows bp3n01-bp3n19); the booted
# print_message/2 calls them around every message, which test_debug_flag_swipl.jl's `debug_mode` messages exercise.
TS = [
    "test/core_lang/test_notrace_swipl.jl",
    "test/core_lang/test_bootpred3_swipl.jl",
    "test/core_lang/test_debug_flag_swipl.jl",
]
TARGETS = TS
P = "src/pl-pro.jl"
T = "src/pl-trace.jl"
MUTANTS = [
    # ── '$notrace'/2: the status read ──
    dict(id="NT2-A1 the tracing bit is not saved (KILL nt01, nt03, nt08, nt19)",
         file=P, targets=TS,
         old="    ld.debugstatus_tracing && (flags |= NOTRACE_TRACE)\n",
         new="    nothing\n"),
    dict(id="NT2-A2 the debugging bit is not saved (KILL nt02, nt03, nt10, nt12)",
         file=P, targets=TS,
         old="    ld.debugstatus_debugging && (flags |= NOTRACE_DEBUG)\n",
         new="    nothing\n"),
    dict(id="NT2-A3 the redo-in-skip level reads as -1 (KILL nt05, nt22)",
         file=P, targets=TS,
         old="        sl = -2\n    else\n",
         new="        sl = -1\n    else\n"),
    dict(id="NT2-A4 a counted level reads as 0 (KILL nt04, nt06, nt07)",
         file=P, targets=TS,
         old="        sl = Int64(ld.debugstatus_skiplevel)\n",
         new="        sl = Int64(0)\n"),
    # ── '$notrace'/2: the status cleared ──
    dict(id="NT2-B1 tracing stays on after '$notrace'/2 (KILL nt08, nt19)",
         file=P, targets=TS,
         old="        ld.debugstatus_tracing = false\n",
         new="        nothing\n"),
    dict(id="NT2-B2 debugging stays on after '$notrace'/2 (KILL nt08, nt10, nt12)",
         file=P, targets=TS,
         old="        ld.debugstatus_debugging = false\n",
         new="        nothing\n"),
    dict(id="NT2-B3 the skip level is not reset to the very deep one (KILL nt08, nt19)",
         file=P, targets=TS,
         old="        ld.debugstatus_skiplevel = SKIP_VERY_DEEP\n",
         new="        nothing\n"),
    dict(id="NT2-B4 the normal run mode is not set (KILL nt09)",
         file=P, targets=TS,
         old="        ld.debugstatus_skiplevel = SKIP_VERY_DEEP\n        setPrologRunMode!(ld, RUN_MODE_NORMAL)\n",
         new="        ld.debugstatus_skiplevel = SKIP_VERY_DEEP\n"),
    dict(id="NT2-B5 the status is cleared before the unification: a refused call loses it (KILL nt15)",
         file=P, targets=TS,
         old="    if PL_unify_integer(ld, A1, flags) && PL_unify_int64(ld, A2, sl)\n",
         new="    ld.debugstatus_tracing = false\n    ld.debugstatus_debugging = false\n    ld.debugstatus_skiplevel = SKIP_VERY_DEEP\n    if PL_unify_integer(ld, A1, flags) && PL_unify_int64(ld, A2, sl)\n"),
    # ── '$restore_trace'/2 ──
    dict(id="NT2-C1 the tracing bit is restored inverted (KILL nt01, nt03, nt13, nt16)",
         file=P, targets=TS,
         old="    ld.debugstatus_tracing = (flags & NOTRACE_TRACE) != 0\n",
         new="    ld.debugstatus_tracing = (flags & NOTRACE_TRACE) == 0\n"),
    dict(id="NT2-C2 the debugging bit is restored inverted (KILL nt02, nt03, nt10, nt12)",
         file=P, targets=TS,
         old="    ld.debugstatus_debugging = (flags & NOTRACE_DEBUG) != 0\n",
         new="    ld.debugstatus_debugging = (flags & NOTRACE_DEBUG) == 0\n"),
    dict(id="NT2-C3 the level -2 restores the very deep level (KILL nt05, nt22)",
         file=P, targets=TS,
         old="depthi == -2 ? SKIP_REDO_IN_SKIP",
         new="depthi == -2 ? SKIP_VERY_DEEP"),
    dict(id="NT2-C4 the level -1 restores the redo-in-skip level (KILL nt01, nt02, nt03, nt17)",
         file=P, targets=TS,
         old="depthi == -1 ? SKIP_VERY_DEEP",
         new="depthi == -1 ? SKIP_REDO_IN_SKIP"),
    dict(id="NT2-C5 the level is not stored (KILL nt04, nt06, nt07, nt13)",
         file=P, targets=TS,
         old="    ld.debugstatus_skiplevel = depth\n",
         new="    nothing\n"),
    dict(id="NT2-C6 the tracing bit is stored before the level is checked: a refused restore changes the status (KILL nt14)",
         file=P, targets=TS,
         old="    if depthi != -1 && depthi != -2 && depthi < 0\n",
         new="    ld.debugstatus_tracing = (flags & NOTRACE_TRACE) != 0\n    if depthi != -1 && depthi != -2 && depthi < 0\n"),
    # ── the constant ──
    dict(id="NT2-D1 SKIP_REDO_IN_SKIP is two below the very deep level, not one (KILL the white-box testset of test_notrace_swipl.jl)",
         file=T, targets=TS,
         old="const SKIP_REDO_IN_SKIP = SKIP_VERY_DEEP - UInt(1)\n",
         new="const SKIP_REDO_IN_SKIP = SKIP_VERY_DEEP - UInt(2)\n"),
]
