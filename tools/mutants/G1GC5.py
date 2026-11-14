# ORIGINAL: G1-GC G1-5's mutant list; the sweep and the relocation chains are a port of pl-gc.c at the pin, the list itself is the kernel's own.
# tools/mutants/G1GC5.py — the mutation battery of G1-GC step G1-5, the SWEEP of the stack collector: src/pl-gcsweep.jl (the chain
# addressing and makePtr, update_relocation_chain, into_relocation_chain, alien_into_relocation_chain, make_gc_hole, sweep_global_mark
# and its fillers, sweep_mark, _gcs_sweep_marked_slot, sweep_foreign, sweep_trail, sweep_frame, sweep_environments, sweep_choicepoints,
# is_downward_ref / is_upward_ref, gc_box_index, offset_word). The list pins what is there at the gate of G1-5 (NOTHING was run when it was
# drafted: the kills below are read off the rows of test/core_lang/test_gc_sweep.jl, the CI battery is the verdict). Run ONCE, in CI
# (.github/workflows/mutation.yml). Format: tools/mutate_drive.py's (as G1GC3.py): `id`, `file`, `old` (must occur EXACTLY once), `new`,
# optional `equivalent` and `targets`.
# Each id names its KILL, the testset of test/core_lang/test_gc_sweep.jl (GS) that must fail, by the first words of its name:
#   CH = "the chains equal the model, the counters agree ..."        FI = "fillers: the garbage between a mark and the cell below ..."
#   ID = "unwinding with the identity destination restores every word"  NP = "unwinding to a new position: every referrer holds it ..."
#   TT = "the trail height of a mark: the chain starts at the entry after the last one"
#   UT = "unit table: makePtr round trip, offset_word, make_gc_hole ..."   LQ = "a live query: the environments and choicepoints are swept ..."
#   CO = "deliberate corruptions of a chain FAIL the comparison"
# TARGETS (audit D-0238): every test file that runs the mutated code and can see its effect: test_gc_sweep.jl runs all of src/pl-gcsweep.jl;
#   test_gc_mark.jl is listed as well (its mark phase is what the sweep rows run first; a mutant of the sweep cannot be seen there, a bug in
#   the shared helpers could). `git grep` of the names in test/ finds no other file that calls the sweep (G1-6's compaction adds itself later).
# VERDICTS: the CI battery runs one fresh process per mutant and its verdicts are authoritative. A mutant that corrupts a chain (G1GC5-C*, G1GC5-U*)
#   may loop or fail with an error instead of a failed comparison: an error is a kill, a timeout is NO verdict (never caught).
# EQUIVALENT mutants: none declared. Drafted and left out as equivalent or unseen by any row: the easy-case TEST of sweep_global_mark (its scan
#   arm finds the same cell), the TAG_TRAILVAL arm of sweep_trail (a tagged value entry also has STG_GLOBAL storage), the CHP_JUMP pc of
#   sweep_choicepoints and the new-arguments check (no row has a CHP_JUMP choice or a frame under construction): G1-6 / G1-2 add the rows.
# Every `old` is counted EXACTLY once in its file by `python3 -I ~/code/lk-t27-scratch/oldscan.py G1GC5` from the repository root;
# `new` != `old`; no duplicate id. RE-FIT any `old` that `tools/warm.sh fmt` rewraps.
GS = "test/core_lang/test_gc_sweep.jl"
GM = "test/core_lang/test_gc_mark.jl"
TARGETS = [GS, GM]
S = "src/pl-gcsweep.jl"

def m(id, old, new, file=S, eq=None):
    d = dict(id=id, file=file, old=old, new=new, targets=[GS, GM])
    if eq:
        d["equivalent"] = eq
    return d

MUTANTS = [
    # ---- into_relocation_chain
    m("G1GC5-C1 into_relocation_chain: the head of a new chain gets no FIRST bit (KILL CH: `the head lost its FIRST bit`, the FIRST count; CO: the guard)",
      "        _gcs_set!(ld, head, set_first(_gcs_get(ld, head)))\n        sw.relocation_chains += 1\n",
      "        sw.relocation_chains += 1\n"),
    m("G1GC5-C2 into_relocation_chain: the first-referrer test is inverted (KILL CH: the chain of a head with two referrers reads back wrongly)",
      "    if is_first(_gcs_get(ld, head))\n        _gcs_set!(ld, current, set_first",
      "    if !is_first(_gcs_get(ld, head))\n        _gcs_set!(ld, current, set_first"),
    m("G1GC5-C3 into_relocation_chain: a new chain counts twice (KILL CH: relocation_chains == #heads)",
      "sw.relocation_chains += 1", "sw.relocation_chains += 2"),
    m("G1GC5-C4 into_relocation_chain: relocation_cells is not counted (KILL CH: relocation_cells == M.cells; ID: relocated_cells == relocation_cells > 0)",
      "    sw.relocation_cells += 1", "    sw.relocation_cells += 0"),
    # ---- update_relocation_chain
    m("G1GC5-U1 update_relocation_chain: the FIRST bit of the cell left is not cleared (KILL ID: a FIRST bit is left on the stacks; NP: the heads keep FIRST)",
      "_gcs_set!(ld, current, clear_first(cell))", "_gcs_set!(ld, current, cell)"),
    m("G1GC5-U2 update_relocation_chain: a referrer loses its tag (KILL NP: `consPtr(h + 1000, tag | STG_GLOBAL)`; ID: a slot's tag changes)",
      "gc_set_value(cell, makePtr(dest, t))", "gc_set_value(cell, makePtr(dest, UInt64(0)))"),
    m("G1GC5-U3 update_relocation_chain: the unwinding stops after the first referrer (KILL ID: the older referrers keep chain pointers; NP)",
      "is_first(_gcs_get(ld, current)) || break", "false || break"),
    m("G1GC5-U4 update_relocation_chain: the chain count is not lowered (KILL ID: `sw.relocation_chains == 0`; NP; TT)",
      "sw.relocation_chains -= 1", "sw.relocation_chains -= 0"),
    m("G1GC5-U5 update_relocation_chain: the head does not get its original value back (KILL ID: a cell differs; NP: badh; TT: the sentinel is not 0 again)",
      "_gcs_set!(ld, head, gc_set_value(cell, val))", "_gcs_set!(ld, head, cell)"),
    m("G1GC5-U6 update_relocation_chain: relocated_cells counts twice (KILL ID: relocated_cells == relocation_cells)",
      "sw.relocated_cells += 1", "sw.relocated_cells += 2"),
    # ---- alien_into_relocation_chain, makePtr, the small functions
    m("G1GC5-A1 alien_into_relocation_chain: a trail height names the entry at index count, not count + 1 (KILL TT: the head is `ld.trail[c + 1]`)",
      "consPtr(orgst == STG_STATIC ? raw + 1 : raw, orgst)", "consPtr(raw, orgst)"),
    m("G1GC5-A2 alien_into_relocation_chain: alien_relocations is not counted (KILL CH: alien_relocations == M.alien; TT)",
      "    sw.alien_relocations += 1", "    sw.alien_relocations += 0"),
    m("G1GC5-P1 makePtr: the storage class is left out of the pointer (KILL UT: the round trip keeps `storage(w)`; CH: a chain pointer decodes wrongly)",
      "t | _gcs_stg(a)", "t"),
    m("G1GC5-P2 offset_word: a non-zero offset (KILL UT: `offset_word(w) == 0`)",
      "@inline offset_word(m::word)::Int = 0", "@inline offset_word(m::word)::Int = 1"),
    m("G1GC5-P3 gc_box_index: every cell answers its word's index (KILL UT: a plain cell answers 0)",
      "_is_box(ld, p) ? valPtr(ld.gstack[p]) : 0", "valPtr(ld.gstack[p])"),
    m("G1GC5-P4 make_gc_hole: a run of exactly four cells is made a hole (KILL UT: top - bottom = 4 changes nothing)",
      "if top - bottom > 4", "if top - bottom >= 4"),
    m("G1GC5-P5 _gcs_chainable: a value-table word is chained (KILL UT: a vword answers false for both directions; CH: the slot t + 3 is in no chain)",
      "_gc_is_global_ref(w) && !_is_vword(w)", "_gc_is_global_ref(w)"),
    m("G1GC5-P6 is_downward_ref: the comparison is turned round (KILL UT: the downward cells equal the model)",
      "    return valPtr(val) < p", "    return valPtr(val) > p"),
    m("G1GC5-P7 is_upward_ref: the comparison is turned round (KILL UT: the upward cells equal the model)",
      "    return valPtr(val) > p", "    return valPtr(val) < p"),
    # ---- sweep_global_mark, sweep_mark
    m("G1GC5-G1 sweep_global_mark: the easy case names the cell below the height (KILL CH: `newh[F3, globaltop] == p`)",
      "gm = m                                          # quit common easy case",
      "gm = m - 1                                      # quit common easy case"),
    m("G1GC5-G2 sweep_global_mark: the filler overwrites the live cell it names (KILL FI/CH: the head cell loses its value, its chain breaks)",
      "for p in (gm + 1):m", "for p in gm:m"),
    m("G1GC5-G3 sweep_global_mark: a zero cell stops the scan as a filler (KILL CH/FI: the scan takes gm = 0 for a garbage variable cell)",
      "if tag(w) == TAG_VAR && w != 0", "if tag(w) == TAG_VAR"),
    m("G1GC5-G4 sweep_global_mark: the filler found names the wrong cell (KILL FI: the second scan's head is not the model's)",
      "gm = Int(valTagged(w))", "gm = Int(valTagged(w)) - 1"),
    m("G1GC5-G5 sweep_global_mark: no filler is written (KILL FI: every cell of the regions holds `consTagged(gm, TAGEX_VAR)`)",
      "ld.gstack[p] = fw", "ld.gstack[p] = UInt64(0)"),
    m("G1GC5-G6 sweep_global_mark: a height of 0 is scanned (KILL CH: the height-0 field of F0 raises or chains a cell)",
      "    if m < 1\n", "    if m < 0\n"),
    m("G1GC5-G7 sweep_global_mark: needs_relocation is not counted for a mark (KILL CH: the counters)",
      "        st.needs_relocation += 1\n        alien_into_relocation_chain(ld, sw, a, STG_GLOBAL)",
      "        alien_into_relocation_chain(ld, sw, a, STG_GLOBAL)"),
    m("G1GC5-M1 sweep_mark: a saved bar above the top is not clamped (KILL CH/ID: F4's NO_MARK_BAR is read as a cell)",
      "    _gcs_h_get(ld, sb) > ld.gTop && _gcs_h_set!(ld, sb, ld.gTop)\n", "    nothing\n"),
    m("G1GC5-M2 sweep_mark: the saved bar is not swept (KILL CH: the chains and alien_relocations of the saved bars)",
      "    sweep_global_mark(ld, st, sw, sb)\n    return nothing", "    nothing\n    return nothing"),
    m("G1GC5-M3 sweep_mark: marks_swept is not counted (KILL CH: marks_swept == M.marks)",
      "    sw.marks_swept += 1", "    sw.marks_swept += 0"),
    # ---- the sweeps
    m("G1GC5-F1 sweep_foreign: only the frames WITHOUT a real mark are swept (KILL CH: every mark field of the heap)",
      "isRealMark(f.mark) && sweep_mark(ld, st, sw, true, fr)", "!isRealMark(f.mark) && sweep_mark(ld, st, sw, true, fr)"),
    m("G1GC5-F2 sweep_foreign: no marked slot is swept (KILL CH: the chains, MARK bits left on the slots, local_marked)",
      "is_marked(ld.slots[idx]) && _gcs_sweep_marked_slot(ld, st, sw, idx)", "false && _gcs_sweep_marked_slot(ld, st, sw, idx)"),
    m("G1GC5-F3 sweep_foreign: only the innermost foreign frame is swept (KILL CH: the chains of F0..F3)",
      "        fr = f.parent\n    end\n    return nothing\nend\n\n# PORT: pl-gc.c sweep_trail",
      "        fr = 0\n    end\n    return nothing\nend\n\n# PORT: pl-gc.c sweep_trail"),
    m("G1GC5-F4 sweep_foreign: the last term reference of every frame is skipped (KILL CH: a MARK bit stays on a slot, a chain lacks its referrer)",
      "        for k in 0:(f.size - 1)\n            idx = _gc_fli_slot(f, k)", "        for k in 0:(f.size - 2)\n            idx = _gc_fli_slot(f, k)"),
    m("G1GC5-F5 _gcs_sweep_marked_slot: local_marked grows instead of falling (KILL CH: `st.local_marked == 0`; LQ: sweep_stacks raises)",
      "st.local_marked -= 1", "st.local_marked += 1"),
    m("G1GC5-F6 _gcs_sweep_marked_slot: a value-table slot is chained (KILL CH: the slot t + 3 is in no chain; the chain of its table index raises)",
      "        _gcs_chainable(v) && into_relocation_chain(ld, sw, -idx, STG_LOCAL)", "        into_relocation_chain(ld, sw, -idx, STG_LOCAL)"),
    m("G1GC5-T1 sweep_trail: needs_relocation is not counted for a trail entry (KILL CH: the counters)",
      "            st.needs_relocation += 1\n            into_relocation_chain(ld, sw, GC_TRAIL_BASE + i, STG_STATIC)",
      "            into_relocation_chain(ld, sw, GC_TRAIL_BASE + i, STG_STATIC)"),
    m("G1GC5-E1 sweep_frame: an unmarked global argument keeps its word (KILL LQ: the arguments become `garbage_collected`)",
      "            ld.slots[idx] = _atom_word!(ld, mk_sym(T, :garbage_collected))", "            nothing"),
    m("G1GC5-E2 sweep_environments: the frame keeps its FR_MARKED flag (KILL LQ: every flag cleared; the frame is swept twice and its chain is overwritten)",
      "        f.flags &= ~FR_MARKED\n", "        f.flags &= ~UInt32(0)\n"),
    m("G1GC5-E3 sweep_choicepoints: the mark of a choicepoint is not swept (KILL LQ: marks_swept, the chains of the choice marks)",
      "        sweep_mark(ld, st, sw, false, ch)", "        nothing"),
]
