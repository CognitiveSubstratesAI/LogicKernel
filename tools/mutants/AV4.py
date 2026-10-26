# ORIGINAL: AV4's mutant list — no swipl-devel counterpart.
# tools/mutants/AV4.py — the mutation battery of AV4 (pl-wam.c foreignWakeup and its callers: pl-prims.c can_unify
# (\=/2) and pl-wam.c findCatcher (catch/3's catcher), plus audit D-0162 item 3's assert in unify_all_trail_ptrs_cells),
# run ONCE, in CI (.github/workflows/mutation.yml; locally: tools/mutate.sh run). Format: tools/mutate_drive.py's.
# Killed by test/core_lang/test_attvar_wakeup.jl: the AV4 rows at its end (hk10/hk13/hk11 testsets, _WK_AV4_ROWS,
# hk11b, the foreignWakeup white-box) and, for the assert, the unifiable rows (nw08, hk19c: unifiable/3 on a compound
# goes through unify_all_trail_ptrs_cells).
# NOT LISTED (equivalent, with the code reason):
#   * the `PL_put_term(ld, ex, ld.exception_term); return false` after a failed PL_open_foreign_frame (src/pl-wam.jl
#     foreignWakeup): PL_open_foreign_frame grows the local stack and never returns 0 here.
#   * findCatcher's `f = ld.frames[fr]` re-reads: frames are records found by index, which the nested query cannot move.
#   * findCatcher's `cfid == 0` branch (outOfStack!): PL_open_foreign_frame grows the local stack and never returns 0 here.
#   * AV3-X4/AV3-X5 (AV3.py) anchor the refusals AV4 removed: they match only on AV3's tree.
T = ["test/core_lang/test_attvar_wakeup.jl"]
TS = ["test/core_lang/test_attvar_wakeup.jl", "test/core_lang/test_attvar_store.jl"]
TARGETS = T
P = "src/pl-prims.jl"
W = "src/pl-wam.jl"
MUTANTS = [
    # ── foreignWakeup ──
    dict(id="AV4-F1 foreignWakeup never runs the wakeup (returns true)", file=W, targets=T,
         old="    if (ld.alerted & ALERT_WAKEUP) != 0                     # if ( unlikely(LD->alerted & ALERT_WAKEUP) )\n",
         new="    if false\n"),
    dict(id="AV4-F2 foreignWakeup does not clear the bit", file=W, targets=T,
         old="        ld.alerted &= ~ALERT_WAKEUP                         #   LD->alerted &= ~ALERT_WAKEUP\n",
         new="        nothing\n"),
    dict(id="AV4-F3 foreignWakeup does not clear the head (the list runs again at the next check point)", file=W, targets=T,
         old="                    ld.gstack[h] = word(0)                  # setVar(*valTermRef(LD->attvar.head))\n",
         new="                    nothing\n"),
    dict(id="AV4-F4 foreignWakeup does not clear the tail (the next registerWakeup appends to a dead list; fw_tail)", file=W, targets=T,
         old="                    ld.gstack[h + 1] = word(0)              # setVar(*valTermRef(LD->attvar.tail))\n",
         new="                    nothing\n"),
    dict(id="AV4-F5 foreignWakeup answers true whatever the hooks do", file=W, targets=T,
         old="                    rval = PL_next_solution(gd, ld, qid) != 0\n",
         new="                    PL_next_solution(gd, ld, qid); rval = true\n"),
    dict(id="AV4-F6 foreignWakeup loses the hook's exception", file=W, targets=T,
         old="                        t != 0 && PL_put_term(ld, ex, t)\n",
         new="                        nothing\n"),
    # ── can_unify (\=/2) ──
    dict(id="AV4-C1 can_unify ignores the wakeup's answer", file=P, targets=TS,
         old="        if unify_ptrs_cells(ld, l1, l2) && foreignWakeup(ld, ex)   # unify_ptrs(…) && foreignWakeup(ex)\n",
         new="        if unify_ptrs_cells(ld, l1, l2)\n"),
    # ── findCatcher ──
    dict(id="AV4-K1 findCatcher ignores the catcher's wakeup", file=W, targets=T,
         old="                rc = foreignWakeup(ld, ex2)\n",
         new="                nothing\n"),
    dict(id="AV4-K2 findCatcher does not raise the wakeup's exception", file=W, targets=T,
         old="            elseif ex2 != 0 && !PL_is_variable(ld, ex2) # Exception from foreignWakeup()\n",
         new="            elseif false\n"),
    dict(id="AV4-K3 findCatcher keeps the old ball after the wakeup raised", file=W, targets=T,
         old="                PL_raise_exception(ld, ex2)\n                PL_put_term(ld, ex, ld.exception_term)\n",
         new="                PL_raise_exception(ld, ex2)\n"),
    dict(id="AV4-K4 findCatcher keeps a failed catcher's foreign frame (7b9d8ba's discard dropped; hk11c)", file=W, targets=T,
         old="            PL_discard_foreign_frame(ld, cfid)\n",
         new="            nothing\n"),
    # ── audit D-0162 item 3: the assert catches a dropped `mark_bar = NO_MARK_BAR` ──
    dict(id="AV4-M1 unify_all_trail_ptrs leaves the bar on (caught by the D-0162 assert)", file=P, targets=T,
         old="    ld.mark_bar = NO_MARK_BAR                       # every assignment trailed\n",
         new="    nothing\n"),
]
