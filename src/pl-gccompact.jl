# UPSTREAM: swipl-devel src/pl-gc.c @ 18168e629eab
# CLASS: code
# COPYRIGHT: Copyright (c)  1985-2024, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
# allow-new-artifact: a port of pl-gc.c at the pin (read via git show 18168e62:src/pl-gc.c; the design is in evidence/G1/g1gc6a_handoff.md)
# G1-GC (G1-6a/6b): the COMPACTION of SWI-Prolog's stack garbage collector (pl-gc.c): `compact_global` (the
# down phase that unwinds the relocation chains and chains the downward references, the up phase that moves
# the marked cells), `downskip_combine_garbage`, `collect_phase`, the `unsweep_*` family, and the three pieces
# that JOIN the trail half (pl-gctrail.jl, G1-4) to the sweep (pl-gcsweep.jl, G1-5): the pass that puts the
# `trailtop` of every mark into the relocation chain of its trail entry, the chain handler `compact_trail`
# calls, and the counter check after it. LEAF file: included after pl-gcsweep.jl. The driver `garbageCollect`
# and `tight`/`shiftTightStacks`/`clear_unused_stack` are G1-6c's.
#
# THE KERNEL ORDER OF ONE COLLECTION (evidence/G1/g1gc4b_handoff.md, INTERFACE CHECK, as extended here):
#   link_attvars, argument_stack_to_term_refs, gvars_to_term_refs, save_grefs      (G1-3, pl-gcmark.jl)
#   mark_phase                                                                      (G1-3, pl-gcwalk.jl)
#   gc_trail_begin!, tag_trail                                                      (G1-4, pl-gctrail.jl)
#   gc_trail_phase = gc_alien_trailtops + compact_trail(gc_trail_chain) + counter check   (THIS FILE)
#   collect_phase = sweep_foreign, sweep_trail, sweep_stacks, [sweep_frozen_bar], compact_global,
#                   unsweep_foreign, unsweep_stacks, the final counter checks       (THIS FILE; G1-5 sweeps)
#   restore_grefs, untag_trail, clean_attvar_chain, gc_trail_end!                   (G1-3, G1-4)
#   term_refs_to_gvars, term_refs_to_argument_stack, restore_attvars                (G1-3)
#
# THE KERNEL'S CELLS (differences to upstream, each repeated at its definition):
#   * positions are 1-BASED and heights, not addresses: the "first free cell" of upstream (`gTop`, `dest`) is
#     here the position of the LAST used cell, so `gTop` itself is a real cell the scans visit, and a mark's
#     height is chained through the last live cell at or below it (G1-5's header). `dest` of the down phase
#     counts the marked cells at or below the cell under the scan: the NEW position of a marked cell, and for
#     any other cell the new height of everything at or below it.
#   * no inline indirects (ruling D1): `offset_cell` is always 0, so every "large cell" arm is dropped; the box
#     of a value-table entry is an ordinary one-cell marked cell, moved like any other, and `ld.vbox[i]` is
#     re-pointed when it moves (`gc_box_index`, G1-5). The table is NOT renumbered (first cut of ruling D1):
#     an entry whose box is not marked is TOMBSTONED (`vbox[i] = 0`) by `gc_tombstone_boxes!`, and
#     `gc_truncate_vtable!` drops the tombstones at its end. HANDOFF to the engine owner: `_truncate_vtable!`
#     (pl-inline.jl:461) and `_check_vbox!` (pl-gc.jl:732) need the tombstone rule (an entry with `vbox[i] == 0`
#     is no box: skip it in the monotonicity check, pop it at the end).
#   * the stacks hold INDICES: marks are heights, held in a "mark field" addressed as in pl-gcsweep.jl; the new
#     height of a field is `valPtr` of the pointer word the chain unwinding left in it (global top: the new
#     position of the last live cell; trail top: the new entry index + 1, so the count is `valPtr - 1`).

# ── the join of the trail half and the sweep ────────────────────────────────────────────────────

# ORIGINAL: the `update_relocation_chain` call of `compact_trail` (pl-gc.c:2720) as a NAMED callable type, so
# that `compact_trail(ld, ts, gc_trail_chain(sw))` is one concrete specialisation (the manifest names it).
# `compact_trail` calls `urc(ld, current, dest)` with plain 1-based trail indexes; the chains are addressed by
# `GC_TRAIL_BASE + index` (pl-gcsweep.jl), and the head's value is restored into `ld.trail[current]`.
"The chain handler of `compact_trail`: unwinds the relocation chain headed at trail entry `current` to `dest`."
struct gc_trail_chain
    sw::gc_sweep_counts
end

function (h::gc_trail_chain)(ld::PL_local_data{T}, current::Int, dest::Int)::Nothing where {T}
    update_relocation_chain(ld, h.sw, GC_TRAIL_BASE + current, GC_TRAIL_BASE + dest)
    return nothing
end

# ORIGINAL: the topmost frame of the frame chain of `fr` and the query it belongs to (upstream's
# `unsweep_environments` body, shared with the walk that finds the choicepoints of a collection).
"The index of the query frame that the frame chain of `fr` ends in (the walk of pl-gc.c `unsweep_environments`)."
function gc_top_query(ld::PL_local_data{T}, fr::Int)::Int where {T}
    while ld.frames[fr].parent != 0
        fr = ld.frames[fr].parent
    end
    return queryOfFrame(ld, fr)
end

# ORIGINAL: the choicepoints a collection visits, in the order `unsweep_stacks` visits them: those of the
# safe point's chain, then those of each parent query. It steps the way `mark_stacks`, `sweep_stacks` and
# `unmark_stacks` do (`q.parent == 0` ends the walk), so the three phases see the same marks.
"The indexes of the choicepoints the collection of the safe point `vm` visits."
function gc_choice_indices(ld::PL_local_data{T}, vm::vm_state)::Vector{Int} where {T}
    out = Int[]
    fr = vm.frame
    ch = vm.choice
    while fr != 0
        qf = gc_top_query(ld, fr)
        while ch != 0
            push!(out, ch)
            ch = ld.choices[ch].parent
        end
        q = ld.queries[qf]
        q.parent == 0 && break
        fr = q.saved_environment
        ch = q.saved_bfr
    end
    return out
end

# ORIGINAL: the `needsRelocation(&mark.trailtop); alien_into_relocation_chain(&mark.trailtop, STG_TRAIL,
# STG_LOCAL)` of `mark_foreign_frame` and `early_reset_choicepoint` (pl-gc.c:1695, :2370), left to the sweep
# by G1-3 (`# G1-5:` comments) and by G1-5 to G1-4: ONE pass over the marks after `tag_trail` and before
# `compact_trail`. It cannot run inside the mark phase (the trail is untagged until `tag_trail`, and bits 5-6
# of an untagged entry are its position). Each field holds the plain entry COUNT: `alien_into_relocation_chain`
# chains the entry at index count + 1 itself. `mark_foreign_frame` already counted `needs_relocation` for the
# foreign frames, so only the choicepoints are counted here.
"Put the `trailtop` of every real foreign-frame mark and of every choicepoint of `vm` into its trail entry's chain."
function gc_alien_trailtops(
    ld::PL_local_data{T}, st::gc_mark_counts, sw::gc_sweep_counts, vm::vm_state
)::Nothing where {T}
    fr = ld.fli_context
    while fr != 0
        f = ld.fliframes[fr]
        if isRealMark(f.mark)
            alien_into_relocation_chain(ld, sw, _gcs_mfield(true, fr, 2), STG_STATIC)
        end
        fr = f.parent
    end
    for ch in gc_choice_indices(ld, vm)
        st.needs_relocation += 1
        alien_into_relocation_chain(ld, sw, _gcs_mfield(false, ch, 2), STG_STATIC)
    end
    return nothing
end

# ORIGINAL: the check at the end of `compact_trail` (pl-gc.c:2748, `relocated_cells != relocation_cells`):
# it needs the sweep's counters, which G1-4 does not have. Only trail chains exist at this point (the global
# chains come in the sweep after it), so none may be left.
"Check that every relocation chain made for a trail entry has been unwound (the check closing `compact_trail`)."
function gc_check_trail_chains(sw::gc_sweep_counts)::Nothing
    sw.relocated_cells == sw.relocation_cells ||
        error("GC: after compact_trail: relocation_cells = $(sw.relocation_cells); relocated_cells = $(sw.relocated_cells)")
    sw.relocation_chains == 0 || error("GC: after compact_trail: relocation chains = $(sw.relocation_chains)")
    return nothing
end

"""
    gc_trail_phase(ld, st, sw, ts, vm) -> Int

The trail step of a collection, between `tag_trail` and `collect_phase`: chain the marks' `trailtop`s, run
`compact_trail` with the relocation-chain handler and check the counters. Returns the new sentinel index.
"""
function gc_trail_phase(
    ld::PL_local_data{T}, st::gc_mark_counts, sw::gc_sweep_counts, ts::gc_trail_state, vm::vm_state
)::Int where {T}
    gc_alien_trailtops(ld, st, sw, vm)
    top = compact_trail(ld, ts, gc_trail_chain(sw))
    gc_check_trail_chains(sw)
    return top
end

# ── the value table (ruling D1, option (b)) ─────────────────────────────────────────────────────

# ORIGINAL: an entry whose box cell is not marked is dead: its box is garbage. The table keeps its indices
# (no cell names an index that is not marked), so the entry is TOMBSTONED: `vbox[i] = 0` (no cell is
# position 0, so `_is_box` answers false for it). The value stays in `vtable` until the entry is truncated
# (the term type has no null to put there). Returns the number of entries tombstoned.
"Tombstone the value-table entries whose box cell is not marked; the count (before the cells move)."
function gc_tombstone_boxes!(ld::PL_local_data{T})::Int where {T}
    n = 0
    for i in eachindex(ld.vbox)
        p = ld.vbox[i]
        p == 0 && continue
        if !is_marked(ld.gstack[p])
            ld.vbox[i] = 0
            n += 1
        end
    end
    return n
end

# ORIGINAL: `_truncate_vtable!` (pl-inline.jl:461) with the tombstone rule: the entries at the end of the
# table whose box is gone (0) or lies above `gTop` are dropped.
"Drop the value-table entries at the end whose box is a tombstone or lies above `gTop`."
function gc_truncate_vtable!(ld::PL_local_data{T})::Nothing where {T}
    while !isempty(ld.vbox) && (ld.vbox[end] == 0 || ld.vbox[end] > ld.gTop)
        pop!(ld.vbox)
        pop!(ld.vtable)
    end
    return nothing
end

# ── the compaction ──────────────────────────────────────────────────────────────────────────────

# PORT: pl-gc.c downskip_combine_garbage
# DIVERGES: `current` is the position of the first (topmost) garbage cell the down scan met and the result the
# position of the BOTTOM of the garbage (the scan then steps below it); no large-cell arm (ruling D1);
# `dest` is the count of marked cells at or below the cell, as in `compact_global`; the bottom of the stack is
# position 1 (upstream's dummy marked cell below it is not needed: the loop stops at 0); the hole is made by
# `make_gc_hole` (G1-5) over `bottom..current` inclusive.
"""
    downskip_combine_garbage(ld, sw, current, dest) -> Int

Skip down from the garbage cell `current` to the bottom of the garbage, unwinding the chain of every unmarked
cell with the FIRST bit met on the way, and make the run a hole; returns the bottom position (pl-gc.c).
"""
function downskip_combine_garbage(
    ld::PL_local_data{T}, sw::gc_sweep_counts, current::Int, dest::Int
)::Int where {T}
    top_gc = current
    cur = current - 1
    while cur >= 1
        w = ld.gstack[cur]
        if (w & (MARK_MASK | FIRST_MASK)) != 0
            is_marked(w) && return make_gc_hole(ld, cur + 1, top_gc)
            update_relocation_chain(ld, sw, cur, dest)          # is_first
        end
        cur -= 1
    end
    return make_gc_hole(ld, 1, top_gc)
end

# PORT: pl-gc.c compact_global
# DIVERGES: heights and 1-based positions (header): the down scan starts at the last used cell `gTop`, `dest`
# starts at `total_marked` and a marked cell has the new position `dest` BEFORE the decrement; the end of the
# down phase must find `dest == 0`; no large cells (ruling D1); a cell that moves and is a value-table box
# re-points `ld.vbox` (`gc_box_index`), and the entries of dead boxes are tombstoned first; the checks are
# errors (`sysError`), the `CHK_SECURE` dumps are not kept; `gTop` becomes the new height and the value table
# is truncated at the end.
"""
    compact_global(ld, st, sw)

Compact the marked cells of the global stack to its bottom, keeping their order (pl-gc.c): the down phase
unwinds the relocation chains and chains the downward references, the up phase moves the cells and chains the
upward ones. Sets `ld.gTop` to `st.total_marked`.
"""
function compact_global(ld::PL_local_data{T}, st::gc_mark_counts, sw::gc_sweep_counts)::Nothing where {T}
    top = ld.gTop
    gc_tombstone_boxes!(ld)
    dest = st.total_marked                                      # the new position of the topmost marked cell
    current = top
    while current >= 1                                          # scanning global stack downwards
        w = ld.gstack[current]
        if is_marked(w)
            is_first(w) && update_relocation_chain(ld, sw, current, dest)
            if is_downward_ref(ld, current)
                into_relocation_chain(ld, sw, current, STG_GLOBAL)
            end
            dest -= 1
        elseif is_first(w)
            update_relocation_chain(ld, sw, current, dest)      # gTop refs from marks
        else
            current = downskip_combine_garbage(ld, sw, current, dest)
        end
        current -= 1
    end
    dest == 0 || error("GC: mismatch in down phase: dest = $(dest), expected 0")
    sw.relocation_cells == sw.relocated_cells ||
        error("GC: after down phase: relocation_cells = $(sw.relocation_cells); relocated_cells = $(sw.relocated_cells)")

    dest = 1                                                    # scanning global stack upwards
    for current in 1:top
        w = ld.gstack[current]
        is_marked(w) || continue                                # garbage: skipped cell by cell
        if is_first(w)
            update_relocation_chain(ld, sw, current, dest)
            w = ld.gstack[current]
        end
        bi = gc_box_index(ld, current)
        ld.gstack[dest] = w
        bi != 0 && (ld.vbox[bi] = dest)
        if is_upward_ref(ld, current)
            into_relocation_chain(ld, sw, dest, STG_GLOBAL)
        end
        ld.gstack[dest] = clear_marked(ld.gstack[dest])
        dest += 1
    end
    dest - 1 == st.total_marked ||
        error("GC: mismatch in up phase: dest = $(dest), total_marked = $(st.total_marked)")
    ld.gTop = dest - 1
    gc_truncate_vtable!(ld)
    return nothing
end

# ── unsweeping the marks ────────────────────────────────────────────────────────────────────────

# PORT: pl-gc.c unsweep_mark
# DIVERGES: the mark is named by (`isfli`, `i`) as in `sweep_mark` (pl-gcsweep.jl); the three fields hold the
# pointer words the chain unwinding left in them (`valPtr`): the global top and the saved bar the new position
# of the last live cell at or below the old height (0: none), the trail top the new entry index + 1 (the
# chain head of a trail height is the entry AFTER the last one, `alien_into_relocation_chain`), so the new
# count is `valPtr - 1`; a field that is no pointer word of a chain is an error.
"Turn the swept fields of the mark of choicepoint (`isfli == false`) or foreign frame `i` back into heights (pl-gc.c)."
function unsweep_mark(ld::PL_local_data{T}, isfli::Bool, i::Int)::Nothing where {T}
    m = isfli ? ld.fliframes[i].mark : ld.choices[i].mark
    tt = Int(valPtr(reinterpret(UInt64, m.trailtop))) - 1
    tt >= 0 || error("GC: unsweep_mark: the trail top of mark $(i) was not relocated (field $(m.trailtop))")
    nm = mark(
        tt,
        Int(valPtr(reinterpret(UInt64, m.globaltop))),
        Int(valPtr(reinterpret(UInt64, m.saved_bar))),
    )
    if isfli
        ld.fliframes[i].mark = nm
    else
        ld.choices[i].mark = nm
    end
    return nothing
end

# PORT: pl-gc.c unsweep_foreign
# DIVERGES: returns the number of marks unswept (upstream's `marks_unswept` global).
"Unsweep the marks of the foreign frames (pl-gc.c); the number of marks unswept."
function unsweep_foreign(ld::PL_local_data{T})::Int where {T}
    n = 0
    fr = ld.fli_context
    while fr != 0
        f = ld.fliframes[fr]
        if isRealMark(f.mark)
            unsweep_mark(ld, true, fr)
            n += 1
        end
        fr = f.parent
    end
    return n
end

# PORT: pl-gc.c unsweep_choicepoints
# DIVERGES: returns the number of marks unswept.
"Unsweep the marks of the choicepoints `ch` (an index) and their parents (pl-gc.c); the number of marks unswept."
function unsweep_choicepoints(ld::PL_local_data{T}, ch::Int)::Int where {T}
    n = 0
    while ch != 0
        unsweep_mark(ld, false, ch)
        n += 1
        ch = ld.choices[ch].parent
    end
    return n
end

# PORT: pl-gc.c unsweep_environments
# DIVERGES: `fr` is a frame index and the result a QUERY index (`queryOfFrame`).
"The query frame the frame chain of `fr` ends in (pl-gc.c)."
function unsweep_environments(ld::PL_local_data{T}, fr::Int)::Int where {T}
    return gc_top_query(ld, fr)
end

# PORT: pl-gc.c unsweep_stacks
# DIVERGES: `vm.frame` and `vm.choice` are indexes; the walk also ends at a query without a parent, where
# `mark_stacks`, `sweep_stacks` and `unmark_stacks` end (upstream ends it at `saved_environment == NULL`,
# which a top query has); returns the number of marks unswept.
"Unsweep the marks of the choicepoints of every query from the safe point `vm` outward (pl-gc.c); the count."
function unsweep_stacks(ld::PL_local_data{T}, vm::vm_state)::Int where {T}
    n = 0
    fr = vm.frame
    ch = vm.choice
    while fr != 0
        qf = unsweep_environments(ld, fr)
        n += unsweep_choicepoints(ld, ch)
        q = ld.queries[qf]
        q.parent == 0 && break
        fr = q.saved_environment
        ch = q.saved_bfr
    end
    return n
end

# ── the collect phase ───────────────────────────────────────────────────────────────────────────

# PORT: pl-gc.c collect_phase
# DIVERGES: the three counters live in `sw` (`marks_swept`, `relocation_chains`, `relocation_cells`,
# `relocated_cells`) and in `st` (`needs_relocation`); `saved_bar_at` is the SLOT POSITION of the saved frozen
# bar `gvars_to_term_refs` returned (0 = NULL), swept by `sweep_frozen_bar`; the trail has been compacted
# before this (`gc_trail_phase`), as upstream's `garbageCollect` does, so the trail chains are gone when the
# sweep starts. The check `relocated_cells == needs_relocation` of upstream is NOT an error here: the mark
# phase counts a reference to a value-table box (ruling D1) in `needs_relocation` and the sweep never chains
# it, so the difference `needs_relocation - relocated_cells` (>= 0) is RETURNED for the caller to compare with
# its own count of vword references; the other two checks are errors, as upstream's `sysError`.
"""
    collect_phase(ld, st, sw, vm; vmi_state_of = nothing, saved_bar_at = 0) -> Int

Sweep the foreign frames, the trail and the local stack, compact the global stack, unsweep the marks and
check the counters (pl-gc.c). Returns `st.needs_relocation - sw.relocated_cells`.
"""
function collect_phase(
    ld::PL_local_data{T}, st::gc_mark_counts, sw::gc_sweep_counts, vm::vm_state;
    vmi_state_of = nothing, saved_bar_at::Int = 0
)::Int where {T}
    sweep_foreign(ld, st, sw)
    sweep_trail(ld, st, sw)
    sweep_stacks(ld, st, sw, vm; vmi_state_of = vmi_state_of)
    saved_bar_at != 0 && sweep_frozen_bar(ld, st, sw, saved_bar_at)
    compact_global(ld, st, sw)
    unswept = unsweep_foreign(ld) + unsweep_stacks(ld, vm)
    unswept == sw.marks_swept ||
        error("GC: marks_swept = $(sw.marks_swept) but marks_unswept = $(unswept)")
    sw.relocation_chains == 0 || error("GC: relocation chains = $(sw.relocation_chains)")
    sw.relocated_cells == sw.relocation_cells ||
        error("GC: relocation cells = $(sw.relocation_cells); relocated_cells = $(sw.relocated_cells)")
    return st.needs_relocation - sw.relocated_cells
end
