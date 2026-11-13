# ORIGINAL: G1-6's mutant list — no swipl-devel counterpart.
# tools/mutants/G1GC6A.py — the mutation battery of G1-GC G1-6a/6b, the compaction of the stack collector: src/pl-gccompact.jl (compact_global,
# downskip_combine_garbage, collect_phase and gc_vword_referrers, the unsweep_* family, gc_tombstone_boxes!/gc_truncate_vtable!, the join of the trail
# half and the sweep: gc_trail_chain, gc_alien_trailtops, gc_check_trail_chains, gc_choice_indices). NOTHING was run when it was drafted: the kills below are
# read off the rows, the CI battery is the verdict.
# Run ONCE, in CI (.github/workflows/mutation.yml; locally: tools/mutate.sh run). Format: tools/mutate_drive.py's (as TRIE4.py): `id`, `file`,
# `old` (must occur EXACTLY once), `new`, optional `equivalent` and `targets`.
# Each id names its KILL, the row that must fail, in test/core_lang/test_gc_compact.jl (GC), testsets by their first words:
#   MODEL = "compaction: the cells, slots, trail, value table and marks equal the model" (the model, `_gc6_problems`, the one extractor);
#   NV = "collect_phase returns the references to value-table boxes" (the return value is an independent count);
#   TP = "gc_trail_phase" (the marks' trail counts, one chain per distinct trail height); CK = "gc_check_trail_chains";
#   WB = "compact_global on a hand-marked heap" (run twice: the chain head INSIDE the garbage run, where downskip unwinds it, and ON its top cell, where the
#     main scan does; the `total = 7` row); DS = "downskip_combine_garbage"; VT = "value table: tombstones"; UM = "unsweep_mark";
#   NQ = "nested query: gc_choice_indices and unsweep_stacks continue" (a query opened inside another: the `q.parent == 0` break of gc_choice_indices, hence of
#     gc_alien_trailtops's choice loop, and of unsweep_stacks; their `false && break` form is EQUIVALENT, a top query's saved_environment is 0 and ends the loop itself);
#   LQ = "live query: unsweep_environments" (a running query with choicepoints); AT = "gc_alien_trailtops" (a NoMark frame); CO = "corruptions".
# THE is_first ARMS OF UNMARKED CELLS (compact_global's `elseif is_first(w)` and downskip's `update_relocation_chain(ld, sw, cur, dest)`): in the kernel a relocation
#   chain head is always a LIVE cell (sweep_global_mark chains the highest marked cell at or below a height), so those two arms run only for a chain made by
#   hand: the rows WB (both runs) and DS build one (`alien_into_relocation_chain` with a raw height naming a garbage cell). Their mutants are killed by those rows ONLY.
# TARGETS (audit D-0238): every test file that runs the mutated code. The compaction is reached by test_gc_compact.jl (the whole collection) and by the sweep
#   rows of test_gc_sweep.jl (the chains it builds are the ones compaction unwinds); the mark phase (test_gc_mark.jl) and the trail half (test_gc_trail.jl) run
#   the code that feeds it but never `compact_global`; they are listed because a mutant of the join (gc_trail_chain, gc_alien_trailtops) changes what their
#   rows may see. The `TARGETS` variable is the union (mutate_ci.py plan reads it).
# EQUIVALENT mutants (declared with their reason, file:line in the `equivalent` text): G1GC6A-D2, G1GC6A-R5.
# Every `old` was counted EXACTLY once in its file by a python3 -I script (oldscan.py) at the tip of wip/g1gc-6 when this file was written (no Julia ran);
#   `new` != `old`; no duplicate id. RE-FIT any `old` that `tools/warm.sh fmt` rewraps.
GC = "test/core_lang/test_gc_compact.jl"
GS = "test/core_lang/test_gc_sweep.jl"
GT = "test/core_lang/test_gc_trail.jl"
GM = "test/core_lang/test_gc_mark.jl"
TARGETS = [GC, GS, GT, GM]                   # the union of every mutant's targets (mutate_ci.py plan reads TARGETS)
F = "src/pl-gccompact.jl"
TT = [GC, GS, GM]                            # compaction and its sweep


def m(id, old, new, targets=TT, file=F, eq=None):
    d = dict(id=id, file=file, old=old, new=new, targets=targets)
    if eq:
        d["equivalent"] = eq
    return d


MUTANTS = [
    # ---- compact_global
    m("G1GC6A-D1 compact_global: dest is decremented by 2 (KILL MODEL: the new positions and `dest == 0`; WB)",
      "            dest -= 1\n",
      "            dest -= 2\n"),
    m("G1GC6A-D2 compact_global: the down phase does not check dest == 0",
      "    dest == 0 || error(\"GC: mismatch in down phase",
      "    true || error(\"GC: mismatch in down phase",
      eq="src/pl-gccompact.jl:238 vs :259: the down phase decrements `dest` once per marked cell and the up phase counts the same marked cells, so `dest == 0` "
         "holds exactly when `dest - 1 == st.total_marked` of the up-phase check does; the WB row `total = 7` still throws from the up-phase check (ErrorException)"),
    m("G1GC6A-D3 compact_global: a downward reference is not chained (KILL MODEL: the cells and `relocated_cells == needs_relocation - nvword`; WB: want[5])",
      "            if is_downward_ref(ld, current)\n",
      "            if false\n"),
    m("G1GC6A-D4 compact_global: an upward reference is not chained (KILL MODEL: the cells; WB: want[2])",
      "        if is_upward_ref(ld, current)\n",
      "        if false\n"),
    m("G1GC6A-D5 compact_global: the chain of a MARKED cell is not unwound in the down phase (KILL MODEL: the cells that name a chained live cell; WB: the counters)",
      "            is_first(w) && update_relocation_chain(ld, sw, current, dest)\n",
      "            false && update_relocation_chain(ld, sw, current, dest)\n"),
    m("G1GC6A-D6 compact_global: the chain of a cell reached in the up phase is not unwound (KILL MODEL: the references to a cell chained by an upward reference; WB: want[2])",
      "        if is_first(w)\n            update_relocation_chain(ld, sw, current, dest)\n            w = ld.gstack[current]\n",
      "        if false\n            update_relocation_chain(ld, sw, current, dest)\n            w = ld.gstack[current]\n"),
    m("G1GC6A-D7 compact_global: an UNMARKED chain head meets the main scan as garbage (KILL WB, the head_top run ONLY: the head on cell n - 4, the chain stays open)",
      "        elseif is_first(w)\n            update_relocation_chain(ld, sw, current, dest)      # gTop refs from marks\n",
      "        elseif false\n            update_relocation_chain(ld, sw, current, dest)      # gTop refs from marks\n"),
    m("G1GC6A-D8 compact_global: the mark bit is left on a moved cell (KILL MODEL: `a gc bit is left on the global stack`; WB: `!any(is_marked)`)",
      "        ld.gstack[dest] = clear_marked(ld.gstack[dest])\n",
      "        ld.gstack[dest] = ld.gstack[dest]\n"),
    m("G1GC6A-D9 compact_global: a moved box is not re-pointed at its new position (KILL MODEL: the `vbox` model and `box i is not its own vword`)",
      "        bi != 0 && (ld.vbox[bi] = dest)\n",
      "        bi != 0 && (ld.vbox[bi] = current)\n"),
    m("G1GC6A-D10 compact_global: gTop is one too high after the compaction (KILL MODEL: `ld.gTop == length(live)`; WB: `ld.gTop == 6`)",
      "    ld.gTop = dest - 1\n",
      "    ld.gTop = dest\n"),
    m("G1GC6A-D11 compact_global: a garbage run is stepped over cell by cell, no hole (KILL WB: `all(==(0), gstack[7:n-4])`)",
      "            current = downskip_combine_garbage(ld, sw, current, dest)\n",
      "            current = current\n"),
    # ---- downskip_combine_garbage
    m("G1GC6A-S1 downskip_combine_garbage: the hole covers the marked cell below the run (KILL DS: `gstack[base - 1] == marked_before`)",
      "is_marked(w) && return make_gc_hole(ld, cur + 1, top_gc)",
      "is_marked(w) && return make_gc_hole(ld, cur, top_gc)"),
    m("G1GC6A-S2 downskip_combine_garbage: a run down to the bottom of the stack starts its hole at 2 (KILL DS: the last row, `== 1` and the zeroed cell 1)",
      "    return make_gc_hole(ld, 1, top_gc)\n",
      "    return make_gc_hole(ld, 2, top_gc)\n"),
    m("G1GC6A-S3 downskip_combine_garbage: the top of the hole is one below the first garbage cell (KILL DS: the top cell of the 12-cell run stays non-zero)",
      "    top_gc = current\n",
      "    top_gc = current - 1\n"),
    m("G1GC6A-S4 downskip_combine_garbage: the chain of a first cell inside the run is not unwound (KILL DS ONLY: `relocation_chains == 0 && relocated_cells == 1` and the new height 5)",
      "            update_relocation_chain(ld, sw, cur, dest)          # is_first\n",
      "            nothing          # is_first\n"),
    m("G1GC6A-S5 downskip_combine_garbage: a first cell is not seen (only marked ones end the run) (KILL DS ONLY: the chain stays open; WB, the head_top-less run)",
      "        if (w & (MARK_MASK | FIRST_MASK)) != 0\n",
      "        if (w & MARK_MASK) != 0\n"),
    # ---- the value table
    m("G1GC6A-V1 gc_tombstone_boxes!: the live boxes are tombstoned instead of the dead (KILL VT: `== 1`; MODEL: the vbox model)",
      "        if !is_marked(ld.gstack[p])\n",
      "        if is_marked(ld.gstack[p])\n"),
    m("G1GC6A-V2 gc_tombstone_boxes!: a tombstone is not skipped (KILL VT: the second call reads cell 0, a BoundsError)",
      "        p == 0 && continue\n",
      "        false && continue\n"),
    m("G1GC6A-V3 gc_truncate_vtable!: a tombstone at the end is not dropped (KILL VT: `length(vbox) == n0 + 1`; MODEL: the truncated dead box)",
      "(ld.vbox[end] == 0 || ld.vbox[end] > ld.gTop)",
      "(ld.vbox[end] > ld.gTop)"),
    m("G1GC6A-V4 gc_truncate_vtable!: a box above gTop is not dropped (KILL VT: the last step, `length(vbox) == n0`)",
      "ld.vbox[end] > ld.gTop)",
      "ld.vbox[end] < 0)"),
    # ---- the unsweep family
    m("G1GC6A-U1 unsweep_mark: the trail count keeps the +1 of the chain head (KILL UM: `mark == LK.mark(j, ...)`; TP; MODEL: the marks)",
      "    tt = Int(valPtr(reinterpret(UInt64, m.trailtop))) - 1\n",
      "    tt = Int(valPtr(reinterpret(UInt64, m.trailtop)))\n"),
    m("G1GC6A-U2 unsweep_mark: the global top and the saved bar are swapped (KILL UM: 10 + j against 20 + j; MODEL)",
      "        Int(valPtr(reinterpret(UInt64, m.globaltop))),\n        Int(valPtr(reinterpret(UInt64, m.saved_bar))),\n",
      "        Int(valPtr(reinterpret(UInt64, m.saved_bar))),\n        Int(valPtr(reinterpret(UInt64, m.globaltop))),\n"),
    m("G1GC6A-U3 unsweep_foreign: a NoMark frame is unswept too (KILL UM: the last rows, `== length(frs) - 1`, the NoMark stays)",
      "        if isRealMark(f.mark)\n            unsweep_mark(ld, true, fr)\n",
      "        if true\n            unsweep_mark(ld, true, fr)\n"),
    m("G1GC6A-U4 unsweep_stacks: the choicepoints of the query are not counted (KILL LQ: `unsweep_stacks(ld, vm) == length(chs)`)",
      "        n += unsweep_choicepoints(ld, ch)\n",
      "        n += 0\n"),
    # ---- the join of the trail half and the sweep
    m("G1GC6A-J1 gc_trail_chain: the chain is unwound to the entry's old index (KILL TP, MODEL: the marks' new trail counts)",
      "GC_TRAIL_BASE + current, GC_TRAIL_BASE + dest)",
      "GC_TRAIL_BASE + current, GC_TRAIL_BASE + current)",
      targets=[GC, GS, GT]),
    m("G1GC6A-J2 gc_alien_trailtops: a NoMark foreign frame is chained too (KILL AT: `alien_relocations == nreal - 1`)",
      "        if isRealMark(f.mark)\n            alien_into_relocation_chain(ld, sw, _gcs_mfield(true, fr, 2), STG_STATIC)\n",
      "        if true\n            alien_into_relocation_chain(ld, sw, _gcs_mfield(true, fr, 2), STG_STATIC)\n",
      targets=[GC, GT]),
    m("G1GC6A-J3 gc_check_trail_chains: unbalanced counters pass (KILL CK: `@test_throws` with relocated_cells = 1)",
      "    sw.relocated_cells == sw.relocation_cells ||\n        error(\"GC: after compact_trail",
      "    true ||\n        error(\"GC: after compact_trail",
      targets=[GC, GT]),
    m("G1GC6A-J4 gc_check_trail_chains: an open chain passes (KILL CK: `@test_throws` with relocation_chains = 1)",
      "    sw.relocation_chains == 0 || error(\"GC: after compact_trail",
      "    true || error(\"GC: after compact_trail",
      targets=[GC, GT]),
    # ---- collect_phase and gc_vword_referrers
    m("G1GC6A-R1 collect_phase: the vword references are not subtracted from needs_relocation (KILL MODEL: the check throws on the first collection; NV)",
      "sw.relocated_cells == st.needs_relocation - nvword)",
      "sw.relocated_cells == st.needs_relocation)"),
    m("G1GC6A-R2 gc_vword_referrers: a box cell counts as its own referrer (KILL NV: `R.nv == n`; MODEL: collect_phase throws)",
      "_is_vword(gc_get_value(w)) && !_is_box(ld, p)\n",
      "_is_vword(gc_get_value(w))\n"),
    m("G1GC6A-R3 gc_vword_referrers: the slots are not counted (KILL NV: `R.nv == n`, n counts the slot vwords; MODEL: collect_phase throws)",
      "    for w in ld.slots\n",
      "    for w in ld.slots[1:0]\n"),
    m("G1GC6A-R4 collect_phase: the return value is zero (KILL NV: `R.nv == n`, `n >= 3`)",
      "    return nvword\n",
      "    return 0\n"),
    m("G1GC6A-R5 collect_phase: the marks swept and unswept are not compared",
      "    unswept == sw.marks_swept ||\n",
      "    true ||\n",
      eq="src/pl-gccompact.jl:398-400: `unswept` and `sw.marks_swept` count the marks of the SAME safe point (`vm`) walked by sweep_foreign/sweep_stacks and "
         "unsweep_foreign/unsweep_stacks, which step identically (gc_choice_indices, one walk); no row can make them differ without editing the counter in between, "
         "and collect_phase's own calls leave no gap; the check is a sysError guard (pl-gc.c collect_phase)"),
    # ---- the choicepoint walk
    m("G1GC6A-W1 gc_choice_indices: only the first choicepoint is listed (KILL LQ: `gc_choice_indices == chs`)",
      "            push!(out, ch)\n            ch = ld.choices[ch].parent\n",
      "            push!(out, ch)\n            ch = 0\n"),
    # ---- the walk into a PARENT query (a nested query row: for a top query `saved_environment == 0` ends the loop by itself, so only a nested query sees the break)
    m("G1GC6A-W2 gc_choice_indices: the walk ends at a query that HAS a parent (KILL NQ: `gc_choice_indices == vcat(chs2, chs1)` of \"nested query: gc_choice_indices and unsweep_stacks continue ...\")",
      "        q.parent == 0 && break\n        fr = q.saved_environment\n        ch = q.saved_bfr\n    end\n    return out\n",
      "        q.parent != 0 && break\n        fr = q.saved_environment\n        ch = q.saved_bfr\n    end\n    return out\n"),
    m("G1GC6A-U5 unsweep_stacks: the walk ends at a query that HAS a parent (KILL NQ: `unsweep_stacks(ld, vm) == length(chs2) + length(chs1)`)",
      "        q.parent == 0 && break\n        fr = q.saved_environment\n        ch = q.saved_bfr\n    end\n    return n\n",
      "        q.parent != 0 && break\n        fr = q.saved_environment\n        ch = q.saved_bfr\n    end\n    return n\n"),
]
