# ORIGINAL: G1-GC G1-6c's mutant list; the driver of the stack collector is a port of pl-gc.c at the pin, the list itself is the kernel's own.
# tools/mutants/G1GC6C.py — the mutation battery of G1-GC step G1-6c, the DRIVER of the stack collector: src/pl-gcdriver.jl (garbageCollect with its
# mark_bar fix and its finally, gc_get_vmi_state/gc_restore_vmi_state, gc_count_gvar_refs, gcEnsureSpace, clear_unused_stack, tight, growStacks_tight!,
# shiftTightStacks!). NOTHING was run when this list was drafted: the kills below are read off the rows of test/core_lang/test_gc_driver.jl, the CI
# battery is the verdict. Run ONCE, in CI (.github/workflows/mutation.yml). Format: tools/mutate_drive.py's (as G1GC4.py): `id`, `file`, `old` (must
# occur EXACTLY once), `new`, optional `equivalent` and `targets`.
# Each id names its KILL, the testset of test/core_lang/test_gc_driver.jl (GD) that must fail, by the first words of its name:
#   DL = "dead list: gTop shrinks, the live views are identical, one statistics record, the stacks check"
#   NB = "the global variables are roots: an nb_ value survives and is relocated"
#   MB = "mark_bar: NO_MARK_BAR is restored, a bar below the new top is kept, a bar above it is clamped"
#   SG = "signals and counters: SIG_GC is cleared, SIG_TUNE_GC kept, gc.inferences is the inference count"
#   DC = "declines: blocked and the gc flag off leave every word and the statistics ring as they were"
#   LQ = "a live query: the decline without a callback, the VM state, the collection with one"
#   CU = "clear_unused_stack writes nothing (a release build of swipl)"
#   VS = "gc_get_vmi_state and gc_restore_vmi_state: the state of no query, lTop put back"
#   GV = "gc_count_gvar_refs counts the global-stack values of the nb_ variables only"
#   ES = "gcEnsureSpace: the terms of lneeded, the spare arm, the growing arm, the overflow"
#   TG = "tight, growStacks_tight!, shiftTightStacks!: the formula of pl-gc.c tight() in positions"
# TARGETS (audit D-0238): the driver is reached by test/core_lang/test_gc_driver.jl (its own rows) and, through `garbageCollect` and `considerGC`, by
#   test_g1gc_safe_points.jl; the phases it calls are the rows of test_gc_mark.jl, test_gc_sweep.jl, test_gc_trail.jl. A test_gc_compact.jl (G1-6b)
#   is not in this tree: the merge adds it to TARGETS if it exists then.
# NOT COVERED by a kill (read off the rows; a lane may add rows): the `Int(rc) < 0` return and the `rc == BOOLEX_FALSE` reload of `garbageCollect`
#   (the grown/overflow arms are exercised through `gcEnsureSpace` directly, not through the driver), `restore_grefs` (no attributed variable in the
#   heaps), the `saved_bar_at` keyword (frozen_bar is 0 in the heaps), `trimStacks!(ld, false)` (nothing to trim at these sizes).
# VERDICTS: the CI battery runs one fresh process per mutant and its verdicts are authoritative. A mutant that changes a heap walk may fail with an
#   error (a kill) instead of a failed comparison.
# Every `old` is counted EXACTLY once in its file by `python3 -I ~/code/lk-t27-scratch/oldscan.py G1GC6C` from the repository root;
# `new` != `old`; no duplicate id. RE-FIT any `old` that `tools/warm.sh fmt` rewraps.
GD = "test/core_lang/test_gc_driver.jl"
SP = "test/core_lang/test_g1gc_safe_points.jl"
GM = "test/core_lang/test_gc_mark.jl"
GS = "test/core_lang/test_gc_sweep.jl"
GT = "test/core_lang/test_gc_trail.jl"
TARGETS = [GD, SP, GM, GS, GT]
D = "src/pl-gcdriver.jl"

def m(id, old, new, file=D, eq=None):
    d = dict(id=id, file=file, old=old, new=new, targets=TARGETS)
    if eq:
        d["equivalent"] = eq
    return d

MUTANTS = [
    # ---- garbageCollect: the entry checks
    m("G1GC6C-E1 garbageCollect: a blocked collector collects (KILL DC: `blocked = 1` must answer BOOLEX_FALSE with every word as it was)",
      "if ld.gc.status.blocked != 0 || !truePrologFlag(ld, PLFLAG_GC)",
      "if false || !truePrologFlag(ld, PLFLAG_GC)"),
    m("G1GC6C-E2 garbageCollect: the gc flag is not consulted (KILL DC: the flag-off row must answer BOOLEX_FALSE)",
      "if ld.gc.status.blocked != 0 || !truePrologFlag(ld, PLFLAG_GC)",
      "if ld.gc.status.blocked != 0 || false"),
    m("G1GC6C-E3 garbageCollect: the reason word of the statistics record is 0 (KILL DL: `rec.reason == UInt64(GC_USER)`)",
      "gc_stat_start!(ld, ld.gc.stats, UInt64(reason))",
      "gc_stat_start!(ld, ld.gc.stats, UInt64(0))"),
    # ---- garbageCollect: the mark_bar fix and the finally
    m("G1GC6C-B1 garbageCollect: the NO_MARK_BAR case gets a bar below the top (KILL DL, MB: the live views change, the cells cannot all be relocated)",
      "ld.mark_bar = ld.gTop                       # otherwise we cannot relocate",
      "ld.mark_bar = ld.gTop - 1                   # otherwise we cannot relocate"),
    m("G1GC6C-B2 garbageCollect: the finally leaves the temporary bar (KILL MB row 1: `ld.mark_bar == NO_MARK_BAR`; CR: the bar is restored)",
      "        if no_mark_bar\n            ld.mark_bar = NO_MARK_BAR\n        end\n        ld.gc.status.active = false",
      "        ld.gc.status.active = false"),
    m("G1GC6C-B3 garbageCollect: a bar above the new top is not clamped (KILL MB rows 3 and 4; the row of bar 1 expects it kept)",
      "if !no_mark_bar && ld.mark_bar > ld.gTop    # DIVERGES (5)",
      "if !no_mark_bar && false                    # DIVERGES (5)"),
    m("G1GC6C-B4 garbageCollect: every bar is set to the new top (KILL MB row 2: a bar of 1 must stay 1)",
      "if !no_mark_bar && ld.mark_bar > ld.gTop    # DIVERGES (5)",
      "if !no_mark_bar && ld.mark_bar != ld.gTop   # DIVERGES (5)"),
    m("G1GC6C-B5 garbageCollect: the finally leaves the collector active (KILL DL, MB, DC: `!ld.gc.status.active`)",
      "        ld.gc.status.active = false\n        unblockGC(ld, 0)",
      "        unblockGC(ld, 0)"),
    m("G1GC6C-B6 garbageCollect: the finally leaves the collector blocked (KILL DL, MB, CR: `blocked == 0`)",
      "        unblockGC(ld, 0)\n    end",
      "        nothing\n    end"),
    # ---- garbageCollect: the phases of the driver's own order
    m("G1GC6C-P1 garbageCollect: SIG_GC stays pending (KILL SG: `!pendingGcSignal(ld, SIG_GC)`)",
      "clearGcSignal!(ld, SIG_GC)                      # PL_clearsig(SIG_GC)",
      "nothing                                         # PL_clearsig(SIG_GC)"),
    m("G1GC6C-P2 garbageCollect: the global variables' term references are never closed (KILL DL: `(lTop, fli_context, nframes)` as before; NB)",
      "        term_refs_to_gvars(ld, gvar_saves, saved_bar_at)\n",
      "        nothing\n"),
    m("G1GC6C-P3 garbageCollect: the statistics record is never ended (KILL DL: `rec.global_after < rec.global_before`)",
      "    gc_stat_end!(ld, ld.gc.stats)\n",
      "    nothing\n"),
    m("G1GC6C-P4 garbageCollect: the inference count at the end is 0 (KILL SG: `ld.gc.inferences == ld.statistics.inferences == 424242`)",
      "ld.gc.inferences = ld.statistics.inferences",
      "ld.gc.inferences = 0"),
    m("G1GC6C-P5 garbageCollect: the trail's sentinel is left behind (KILL DL: the second collection's `gc_trail_end!` check, `check_stacks!`; uncertain: read off the checker)",
      "        gc_trail_end!(ld, ts)\n",
      "        nothing\n"),
    # ---- gc_get_vmi_state
    m("G1GC6C-V1 gc_get_vmi_state: a query inside the VM without a callback goes on (KILL LQ row 1: `nostate`, the decline)",
      "        vmi_state_of === nothing && return nothing\n",
      "        nothing\n"),
    m("G1GC6C-V2 gc_get_vmi_state: the callback is used when NO query exists (KILL LQ row 1: `other !== sv`; every no-query row: BoundsError)",
      "if qi != 0 && ld.queries[qi].registers_fr != 0",
      "if qi != 0 || ld.queries[qi].registers_fr != 0"),
    m("G1GC6C-V3 gc_get_vmi_state: the else arm saves lTop as 0 (KILL VS: `vm.lSave == ld.lTop`)",
      "    vm.lSave = ld.lTop                              # state->lSave = lTop",
      "    vm.lSave = 0                                    # state->lSave = lTop"),
    m("G1GC6C-V4 gc_get_vmi_state: the else arm has no choice (KILL LQ row 1: `other.choice == ld.BFR` at a live query, where BFR != 0)",
      "    vm.choice = ld.BFR                              # state->choice = LD->choicepoints",
      "    vm.choice = 0                                   # state->choice = LD->choicepoints"),
    m("G1GC6C-V5 gc_get_vmi_state: the else arm saves ARGP (KILL VS: `!vm.save_argp`; LQ row 1: `!other.save_argp`)",
      "    vm.save_argp = false\n",
      "    vm.save_argp = true\n"),
    m("G1GC6C-V6 gc_restore_vmi_state: a saved lTop above the present one is not raised (KILL VS: `ld.lTop == lt0 + 3`)",
      "        ld.lTop = vm.lSave\n",
      "        nothing\n"),
    # ---- gc_count_gvar_refs
    m("G1GC6C-G1 gc_count_gvar_refs: a global value counts twice (KILL GV: 1 and 2 expected; NB: `== 1`)",
      "        _gc_is_global_ref(w) && (n += 1)",
      "        _gc_is_global_ref(w) && (n += 2)"),
    # ---- gcEnsureSpace
    m("G1GC6C-S1 gcEnsureSpace: only the hint counts the global variables (KILL ES: the (hint 0, real 1) and (3, 1) rows)",
      "ngv = max(ld.gvar_grefs, gc_count_gvar_refs(ld))",
      "ngv = ld.gvar_grefs"),
    m("G1GC6C-S2 gcEnsureSpace: only the real count counts the global variables (KILL ES: the (hint 5, real 0) row)",
      "ngv = max(ld.gvar_grefs, gc_count_gvar_refs(ld))",
      "ngv = gc_count_gvar_refs(ld)"),
    m("G1GC6C-S3 gcEnsureSpace: the global variables' frame has one spare slot less (KILL ES: the exact-fit-plus-one rows use the spare)",
      "lneeded += SIZEOF_FLIFRAME + ngv + 2",
      "lneeded += SIZEOF_FLIFRAME + ngv + 1"),
    m("G1GC6C-S4 gcEnsureSpace: the frozen bar needs no position (KILL ES: `frozen_bar = 1` at lMax must use the spare)",
      "        lneeded += 1\n",
      "        lneeded += 0\n"),
    m("G1GC6C-S5 gcEnsureSpace: the saved argument stack misses its header slot (KILL ES: the `save_argp = true` row must use the spare)",
      "lneeded += SIZEOF_FLIFRAME + ld.aTop + 1",
      "lneeded += SIZEOF_FLIFRAME + ld.aTop"),
    m("G1GC6C-S6 gcEnsureSpace: an exact fit uses the spare (KILL ES: `local_spare == 0` is false for every extra = 0 row)",
      "if ld.lTop + lneeded > ld.lMax\n",
      "if ld.lTop + lneeded >= ld.lMax\n"),
    m("G1GC6C-S7 gcEnsureSpace: a growth answers BOOLEX_TRUE, the caller keeps a stale VM state (KILL ES: `== BOOLEX_FALSE` past the spare)",
      "            rc = BOOLEX_FALSE\n",
      "            rc = BOOLEX_TRUE\n"),
    # ---- clear_unused_stack, tight, growStacks_tight!, shiftTightStacks!
    m("G1GC6C-C1 clear_unused_stack: it writes (KILL CU: `_gd_snap(ld) == sn`, lTop moved)",
      "function clear_unused_stack(ld::PL_local_data{T})::Nothing where {T}\n    return nothing",
      "function clear_unused_stack(ld::PL_local_data{T})::Nothing where {T}\n    ld.lTop += 1\n    return nothing"),
    m("G1GC6C-T1 tight: a fourth of the stack is the least room (KILL TG: one position under the boundary must be tight)",
      "min_room = size ÷ 3                             # sizeStackP(s)/3",
      "min_room = size ÷ 4                             # sizeStackP(s)/3"),
    m("G1GC6C-T2 tight: the LOCAL_MARGIN floor never applies (KILL TG: the 300-position stack must be tight)",
      "if min_room < LOCAL_MARGIN                      # s->min_free",
      "if min_room > LOCAL_MARGIN                      # s->min_free"),
    m("G1GC6C-T3 tight: the room equal to the least is tight (KILL TG: `room == min_room + gap` is not tight)",
      "if ld.lMax - ld.lTop < min_room + spare_gap     # roomStackP(s) < min_room + spare_gap",
      "if ld.lMax - ld.lTop <= min_room + spare_gap    # roomStackP(s) < min_room + spare_gap"),
    m("G1GC6C-T4 tight: the spare gap has the wrong sign (KILL TG: the `local_def_spare - 7` row moves the boundary)",
      "spare_gap = ld.local_def_spare - ld.local_spare",
      "spare_gap = ld.local_spare - ld.local_def_spare"),
    m("G1GC6C-T5 growStacks_tight!: a stack that did not grow answers BOOLEX_TRUE (KILL TG: `LOCAL_OVERFLOW` at stacks_limit = 1)",
      "return after > before ? BOOLEX_TRUE : LOCAL_OVERFLOW",
      "return after >= before ? BOOLEX_TRUE : LOCAL_OVERFLOW"),
    m("G1GC6C-T6 growStacks_tight!: a request of 0 grows the stack (KILL TG: `(lMax, local_spare)` unchanged after `growStacks_tight!(ld, 0)`)",
      "    l == 0 && return BOOLEX_TRUE\n",
      "    nothing\n"),
    m("G1GC6C-T7 shiftTightStacks!: a stack that is not tight grows, a tight one does not (KILL TG: the unchanged row and `== 2 * before`)",
      "if (l | g | t) != 0",
      "if (l | g | t) == 0"),
]
