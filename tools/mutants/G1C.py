# ORIGINAL: G1-C's mutant list (the stack collector wired into the VM, pin 18168e62); G1-C's own.
# tools/mutants/G1C.py — the mutation battery of G1-C: the VM's allocation safe point `@ENSURE_GLOBAL_SPACE` and `hasStackSpace`
# (src/pl-wam.jl, src/pl-alloc.jl), the collector's signals `raiseGcSignal!`/`handleSignals`/`PL_handle_signals`/`gc_handler`/
# `_dispatch_gc_signal` (src/pl-gc.jl, src/pl-setup.jl), the exception points `resumeAfterException`/`_outofstack_gc`/`exceptionUnwindGC`
# (src/pl-wam.jl), `makeMoreStackSpace` (src/pl-gc.jl) and its copy_term caller, the compiler's CHECK_INTERRUPT (src/pl-comp.jl).
# NOT RUN when it was written (edit-only step G1-C6, nothing compiled): the "KILL" text of each id is the assertion EXPECTED to fail, named by
# testset; the CI battery decides (.github/workflows/mutation.yml). Format: tools/mutate_drive.py's (as G1GC2.py): `id`, `file`, `old`
# (EXACTLY once), `new`, optional `equivalent`, `targets`.
# Test files:
#   W = test/core_lang/test_g1c_wiring_swipl.jl: R = the rows w1-w5 (gc_force off/on), V = w2 at the VM sites, S = the signals,
#   X = resumeAfterException/exceptionUnwindGC/_outofstack_gc, M = makeMoreStackSpace.
#   GS = test/core_lang/test_g1gc_safe_points.jl (its rows run under gc_force: a VMI at a full vector records its name).
# TARGETS (audit D-0238): W for every mutant, and every test file that names the mutated function (grep of test/, 2026-11-14) or runs it
#   through the stack-limit, copy_term, collector and meta-call paths: the macro and hasStackSpace run in every clause body, so their
#   targets are the files that FORCE or COUNT a collection (GS, the gc_* files) plus the stack-limit files (the macro's raise path).
#   G1-C7 widened them from a grep of test/ for each mutated name: SIG_GC (test_gc_stats_swipl.jl; considerGC raises it, src/pl-gc.jl:1569, so
#   every collection the VM serves passes the signal path), copy_term_refs (test_slot_indirects.jl, test_var_identity.jl), PL_handle_signals'
#   callers assert_term! (src/pl-comp.jl:4465: test_assert_cells.jl, test/db/test_db.jl) and i_metacall (src/pl-wam.jl:5135: META).
# K1 AND P1, NOT equivalent, were the expected survivors of G1-C7; G1C-KILL's two white-box testsets at the end of W kill them:
#   G1C-K1 (killed by W's testset "G1C-K1: ..."; copy_term_refs' retry, src/pl-copyterm.jl:510). The observable: copy_term/2 of a large term under a
#     stack_limit that the copy alone overflows, with collectable garbage below it on the global stack (and an inference since the last
#     collection, makeMoreStackSpace's gc.inferences test): with ALLOW_GC the retry collects (statistics garbage_collection count +1) and
#     the copy succeeds, as swipl's; the mutant reaches the limit and raises resource_error(global_stack) (or the grown stack succeeds and
#     the count does not move). W's K1 testset builds that state on a bare local data (a Prolog row cannot: the VM's own safe points collect the garbage first).
#   G1C-P1 (killed by W's testset "G1C-P1: ..."; the compiler's CHECK_INTERRUPT, src/pl-comp.jl:993). The observable: raiseGcSignal!(ld, SIG_GC),
#     then assert_term! (from Julia, no query: a query serves the signal at its first call port) of a clause whose compile passes progress
#     32768; right after the assert, before any goal runs, ld.gc.sig_pending == 0 and collections +1 (assert_term!'s PL_handle_signals,
#     src/pl-comp.jl:4465); the mutant leaves SIG_GC pending and the count unchanged.
# Every `old` is counted EXACTLY once in its file by `python3 -I ~/code/lk-t27-scratch/oldscan.py G1C` (G1-C7: 21 mutants, 0 bad; G1-C8: 24, 0 bad); no Julia ran.
#   G1-C8 added A1-A3 (the VM's signal points); the i_metacall CHECK_INTERRUPT arm's mutant (pl-vmi.c:5558-5581) waits for G1-D: its kill row needs
#   a signal raised between the call port and the compiler's test.
#   RE-FIT any `old` that `tools/warm.sh fmt` rewraps.
W = "test/core_lang/test_g1c_wiring_swipl.jl"
GS = "test/core_lang/test_g1gc_safe_points.jl"
GCT = [
    "test/core_lang/test_gc_driver.jl",
    "test/core_lang/test_gc_vmi_state.jl",
    "test/core_lang/test_gc_frames.jl",
    "test/core_lang/test_gc_upstream_swipl.jl",   # D-0238 (chunk 10): whole collections through the VM; it only adds a test that can kill
]
STK = [
    "test/core_lang/test_stack_limit.jl",
    "test/core_lang/test_stack_overflow_swipl.jl",
    "test/core_lang/test_resource_error.jl",
    "test/core_lang/test_local_stack.jl",
    "test/core_lang/test_lb7_swipl.jl",
]
CT = ["test/core_lang/test_copyterm_cells.jl", "test/core_lang/test_copyterm_swipl.jl"]
CTR = CT + ["test/core_lang/test_slot_indirects.jl", "test/core_lang/test_var_identity.jl"]   # copy_term_refs by name (G1C-K1)
EXC = ["test/core_lang/test_local_stack.jl", "test/foreign/test_query.jl", "test/core_lang/test_gc_frames.jl"]
META = ["test/core_lang/test_goal_clause.jl", "test/core_lang/test_metacall_control.jl"]
ASRT = ["test/core_lang/test_assert_cells.jl", "test/db/test_db.jl"]   # assert_term! (the compiler's CHECK_INTERRUPT caller)
VM = [W, GS] + GCT + STK
SIG = [W, GS] + GCT + ["test/core_lang/test_gc_stats_swipl.jl"] + META + ASRT
VMSIG = VM + ["test/core_lang/test_gc_stats_swipl.jl"]   # a SIG_GC pending while a query runs (G1C-A*: considerGC raises it)
TARGETS = sorted(set(VM + SIG + EXC + CTR + META + ASRT))   # the union of every mutant's targets (mutate_ci.py plan reads TARGETS)


def m(id, old, new, targets, file, eq=None):
    d = dict(id=id, file=file, old=old, new=new, targets=targets)
    if eq:
        d["equivalent"] = eq
    return d


WAM = "src/pl-wam.jl"
GC = "src/pl-gc.jl"
SET = "src/pl-setup.jl"
AL = "src/pl-alloc.jl"

MUTANTS = [
    # ---- the VM's safe point (pl-vmi.c:220-235)
    m("G1C-V1 hasStackSpace ignores the vector's end: the macro never enters (KILL W V: no VM site recorded, no collection in w2)",
      "    ld.gTop + g <= length(ld.gstack) &&\n", "    true &&\n",
      VM, AL),
    m("G1C-V2 the macro passes no ALLOW_GC (KILL W V: w2 records no VM site; GS R: nothing changes, may survive there)",
      "egs_rc = ensureGlobalSpace(ld, $n, ALLOW_GC, $site)", "egs_rc = ensureGlobalSpace(ld, $n, 0, $site)",
      VM, WAM),
    m("G1C-V3 the macro passes a wrong site (KILL W R/V: the recorded name is not a SITE line)",
      "egs_rc = ensureGlobalSpace(ld, $n, ALLOW_GC, $site)", "egs_rc = ensureGlobalSpace(ld, $n, ALLOW_GC, :ENSURE_GLOBAL_SPACE)",
      VM, WAM),
    m("G1C-V4 the macro drops its onchange (KILL W R/V: w2's answer under gc_force, a cell read before a collection is stale)",
      "                $(onchange...)                      # onchange;\n", "                nothing\n",
      VM, WAM),
    # ---- the signals (pl-fli.c PL_raise, pl-setup.c handleSignals / PL_handle_signals / gc_handler / dispatch_signal)
    m("G1C-S1 raiseGcSignal! sets no ALERT_SIGNAL (KILL W S: alerted & ALERT_SIGNAL after the raise)",
      "    ld.alerted |= ALERT_SIGNAL                                  # ... alerted|ALERT_SIGNAL\n", "",
      SIG, GC),
    m("G1C-S2 handleSignals serves a signal while an exception is pending (KILL W S: -1 and the signal kept)",
      "    ld.exception_term != 0 && return -1             # if ( exception_term ) return -1;\n", "",
      SIG, SET),
    m("G1C-S3 handleSignals does not recompute alerted (KILL W S: ALERT_SIGNAL cleared after the handler)",
      "    done != 0 && updateAlerted(ld)                  # if ( done ) updateAlerted(LD);\n", "",
      SIG, SET),
    m("G1C-S4 PL_handle_signals never runs the handlers (KILL W S: PL_handle_signals == 1, collections +1)",
      "        return handleSignals(ld)\n", "        return 0\n",
      SIG, SET),
    m("G1C-S5 gc_handler does not collect (KILL W S: collections c0 + 1)",
      "    garbageCollect(ld, 0; vmi_state_of=get_vmi_state)\n", "",
      SIG, SET),
    m("G1C-S6 dispatch sends SIG_GC nowhere (KILL W S: handleSignals throws for SIG_GC)",
      "    if sig == SIG_GC\n        gc_handler(ld, sig)\n", "    if sig == SIG_TUNE_GC\n        gc_handler(ld, sig)\n",
      SIG, SET),
    # ---- the exception points (pl-wam.c:1966-1977, :1990-1999)
    m("G1C-X1 resumeAfterException keeps the gced_sizes of an out-of-stack stack (KILL W X: both 0 after :global)",
      "        ld.gc.global_policy.gced_size = 0\n        ld.gc.trail_policy.gced_size = 0\n    end\n    if !considerGarbageCollect(ld, nothing)\n",
      "    end\n    if !considerGarbageCollect(ld, nothing)\n",
      [W] + EXC, WAM),
    m("G1C-X2 resumeAfterException requests no trim when a collection is due (KILL W X: trim_stack_requested)",
      "            ld.trim_stack_requested = true          # next time with resize\n", "            nothing\n",
      [W] + EXC, WAM),
    m("G1C-X3 _outofstack_gc: the global stack is not collectable (KILL W X: _outofstack_gc(:global), gced_size reset)",
      "        return ld.gc.global_policy.gc\n", "        return false\n",
      [W] + EXC, WAM),
    m("G1C-X4 exceptionUnwindGC requests no trim (KILL W X: trim_stack_requested after both calls)",
      "    ld.trim_stack_requested = true\n    if considerGarbageCollect(ld, nothing)\n", "    if considerGarbageCollect(ld, nothing)\n",
      [W] + EXC, WAM),
    m("G1C-X5 exceptionUnwindGC never collects (KILL W X: collections c0 + 1 with SIG_GC pending)",
      "        garbageCollect(ld, Int(GC_EXCEPTION); vmi_state_of=get_vmi_state)\n", "        nothing\n",
      [W] + EXC, WAM),
    # ---- makeMoreStackSpace (pl-gc.c:4622-4672)
    m("G1C-M1 makeMoreStackSpace ignores the spare while an exception is processed (KILL W M: global_spare 0, no collection)",
      "    if ld.exception_processing &&                   # if ( LD->exception.processing && s && enableSpareStack(s, true) )\n",
      "    if false &&                                     # if ( LD->exception.processing && s && enableSpareStack(s, true) )\n",
      [W] + STK + CT, GC),
    m("G1C-M2 makeMoreStackSpace never collects (KILL W M: collections c0 + 1 with ALLOW_GC)",
      "        (flags & ALLOW_GC) != 0 &&\n        gc_reason != 0 &&\n", "        false &&\n        gc_reason != 0 &&\n",
      [W] + STK + CT, GC),
    m("G1C-M3 makeMoreStackSpace collects with no inference since the last collection (KILL W M: collections c0 in that row)",
      "    if ld.gc.inferences != ld.statistics.inferences &&   # LD->gc.inferences != LD->statistics.inferences\n",
      "    if true &&   # LD->gc.inferences != LD->statistics.inferences\n",
      [W] + STK + CT, GC),
    m("G1C-M4 makeMoreStackSpace does not report the local stack's growth (KILL W M: LOCAL_OVERFLOW with ALLOW_SHIFT is true)",
      "            newsize > oldsize && return true", "            false && return true",
      [W] + STK + CT, GC),
    # ---- the callers
    m("G1C-K1 copy_term_refs' retry passes no ALLOW_GC (KILL W: the testset \"G1C-K1: copy_term_refs collects and retries ...\", the copy refused at the limit with garbage below returns false, no collection)",
      "makeMoreStackSpace(ld, GLOBAL_OVERFLOW, ALLOW_SHIFT | ALLOW_GC) || return false",
      "makeMoreStackSpace(ld, GLOBAL_OVERFLOW, ALLOW_SHIFT) || return false",
      [W] + CTR + STK, "src/pl-copyterm.jl"),
    m("G1C-P1 the compiler never returns CHECK_INTERRUPT (KILL W: the testset \"G1C-P1: assert_term! serves SIG_GC ...\", sig_pending stays 1 and no collection after the assert)",
      "        if ci.progress % 32768 == 0 && (sl = ci.ld) !== nothing && is_signalled(sl)",
      "        if false",
      [W] + META + ASRT, "src/pl-comp.jl"),
    # ---- the VM's signal points (G1-C8; W's testset "G1C-A: ...", one row per point, each the only point between the raise and the answer)
    m("G1C-A1 depart_alerted serves no signal (KILL W A: the a_wrap row raised before the first call keeps SIG_GC pending, no collection)",
      "        if (DEF.flags & P_SIG_ATOMIC) == 0          # isoff(DEF, P_SIG_ATOMIC)",
      "        if false",
      VMSIG, WAM),
    m("G1C-A2 I_FREDO serves no signal (KILL W A: the a_btw row raised before the redo of between/3 keeps SIG_GC pending, no collection)",
      "    if ld.alerted != 0 && is_signalled(ld)",
      "    if false",
      VMSIG, WAM),
    m("G1C-A3 deep_backtrack's clause retry serves no signal (KILL W A: the a_wrap row raised before the retry keeps SIG_GC pending)",
      "            if is_signalled(ld)",
      "            if false",
      VMSIG, WAM),
]
