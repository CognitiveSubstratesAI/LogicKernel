# UPSTREAM: swipl-devel src/pl-gc.c @ 18168e629eab
# CLASS: code
# COPYRIGHT: Copyright (c)  1985-2024, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
# allow-new-artifact: a port of pl-gc.c at the pin (read via git show 18168e62:src/pl-gc.c; the design is in evidence/G1/g1gc5_handoff.md)
# G1-GC (G1-5): the SWEEP of SWI-Prolog's stack garbage collector (pl-gc.c) and the RELOCATION CHAINS it
# threads. After the mark phase (pl-gcmark.jl, pl-gcwalk.jl) the sweep walks the trail, the foreign frames
# and the environments / choicepoints of the local stack and puts every REFERRER of a marked global cell
# (a term reference, a frame slot, a trail entry, the global-top of a mark) into the relocation chain of
# the cell it references, by pointer reversal; compaction (G1-6) unwinds each chain with the cell's new
# position (`update_relocation_chain`). The sweep moves and frees nothing.
#
# HOW THE CHAINS ARE ADDRESSED (kernel-only design; the kernel's stacks hold INDICES, never addresses, and
# the global stack never moves while the sweep runs). A cell is addressed by an Int `a`, extending the
# addressing of pl-gcmark.jl (`a > 0` a global position, `a < 0` a slot index `-a`):
#   * `0 < a < GC_TRAIL_BASE`          the global-stack cell `ld.gstack[a]`            (storage STG_GLOBAL)
#   * `a >= GC_TRAIL_BASE`             the trail entry `ld.trail[a - GC_TRAIL_BASE]`   (storage STG_TRAIL = STG_STATIC)
#   * `-GC_MFIELD_BASE < a < 0`        the local-stack slot `ld.slots[-a]`             (storage STG_LOCAL)
#   * `a <= -GC_MFIELD_BASE`           a FIELD of a backtrack mark (the mark of choicepoint `i` or foreign
#     frame `i`; `_gcs_mfield`): `globaltop`, `saved_bar` or `trailtop`; its word is the field's Int
#     reinterpreted (storage STG_LOCAL: upstream's marks lie on the local stack).
# A chain word is `makePtr(a, tag)` = `consPtr(position, tag | storage)` exactly as upstream's: the head
# cell (a marked global cell, FIRST bit set) holds the pointer to the NEWEST referrer, every referrer holds
# the pointer to the previous one (the oldest holds the head's original value), and a referrer's FIRST bit
# says that its value continues the chain. `update_relocation_chain` writes `makePtr(dest, tag)` into each
# referrer: a GLOBAL pointer word carrying the referrer's original tag.
#
# HEIGHTS (DIVERGES): a mark's `globaltop` / `saved_bar` is a HEIGHT (position of the last used cell), and
# the kernel's chain head is the LAST LIVE CELL at or below that height: a marked cell that compaction
# moves like any other, so the new height is the cell's `dest` (upstream chains the first FREE cell above
# it, `gm`, and the new top is `dest + 1`: the same number in 0-based arithmetic). A mark with no live
# cell below it (height 0) joins no chain and stays 0. `trailtop` is a trail height likewise; its chain
# (alien_into_relocation_chain at the sites marked `# G1-5:` in pl-gcmark.jl / pl-gcwalk.jl, and
# compact_trail) is G1-4's: this file only provides the trail band of the addressing.
#
# TRAIL (ruling D2, option (a)): the sweep expects the trail in upstream's TAGGED form (pl-gc.c `tag_trail`,
# G1-4): an address entry is `consPtr(position, STG_GLOBAL)`, a value entry `consPtr(position,
# STG_GLOBAL | TAG_TRAILVAL)`, a deleted entry 0. The kernel's entry word keeps bits 5-6 inside its position
# field, so the re-encoding is the two bits' only home.
#
# INDIRECTS (ruling D1, the box cell is the unit): a float, string or bigint is a value-table word whose
# payload is a TABLE INDEX, not a position: nothing references a box cell by position, so a vword is never
# chained (`_gcs_chainable`), and `is_downward_ref` / `is_upward_ref` answer false for it. The box cell
# itself is an ordinary one-cell marked cell: compaction (G1-6) re-points `ld.vbox[i]` when it moves a cell
# for which `gc_box_index` answers non-zero.

# ---- the counters of one sweep (upstream's `relocation_chains`, `relocation_cells`, `alien_relocations`,
#      `marks_swept` and `relocated_cells` globals of the collector) ----
mutable struct gc_sweep_counts
    relocation_chains::Int
    relocation_cells::Int
    alien_relocations::Int
    marks_swept::Int
    relocated_cells::Int
    gc_sweep_counts() = new(0, 0, 0, 0, 0)
end

# ---- the cell addressing of the chains ----
const GC_TRAIL_BASE = 1 << 41
const GC_MFIELD_BASE = 1 << 41

# the fields of a mark: 0 = globaltop, 1 = saved_bar, 2 = trailtop
"The address of field `f` (0 globaltop, 1 saved_bar, 2 trailtop) of the mark of choicepoint (`isfli == false`) or foreign frame `i`."
@inline _gcs_mfield(isfli::Bool, i::Int, f::Int)::Int = -(GC_MFIELD_BASE + 8 * i + (isfli ? 4 : 0) + f)

@inline _gcs_is_mfield(a::Int)::Bool = a <= -GC_MFIELD_BASE

# the Int a mark field holds
function _gcs_mf_get(ld::PL_local_data{T}, a::Int)::Int where {T}
    k = -a - GC_MFIELD_BASE
    f = k & 3
    m = (k & 4) != 0 ? ld.fliframes[k >> 3].mark : ld.choices[k >> 3].mark
    return f == 0 ? m.globaltop : f == 1 ? m.saved_bar : m.trailtop
end

function _gcs_mf_set!(ld::PL_local_data{T}, a::Int, v::Int)::Nothing where {T}
    k = -a - GC_MFIELD_BASE
    f = k & 3
    isfli = (k & 4) != 0
    i = k >> 3
    m = isfli ? ld.fliframes[i].mark : ld.choices[i].mark
    nm = f == 0 ? mark(m.trailtop, v, m.saved_bar) : f == 1 ? mark(m.trailtop, m.globaltop, v) : mark(v, m.globaltop, m.saved_bar)
    if isfli
        ld.fliframes[i].mark = nm
    else
        ld.choices[i].mark = nm
    end
    return nothing
end

# the word of the cell at address `a` (a mark field: its Int reinterpreted) and its store
@inline function _gcs_get(ld::PL_local_data{T}, a::Int)::word where {T}
    if a > 0
        return a >= GC_TRAIL_BASE ? ld.trail[a - GC_TRAIL_BASE] : ld.gstack[a]
    elseif _gcs_is_mfield(a)
        return reinterpret(UInt64, _gcs_mf_get(ld, a))
    else
        return ld.slots[-a]
    end
end

@inline function _gcs_set!(ld::PL_local_data{T}, a::Int, w::word)::Nothing where {T}
    if a > 0
        if a >= GC_TRAIL_BASE
            ld.trail[a - GC_TRAIL_BASE] = w
        else
            ld.gstack[a] = w
        end
    elseif _gcs_is_mfield(a)
        _gcs_mf_set!(ld, a, reinterpret(Int, w))
    else
        ld.slots[-a] = w
    end
    return nothing
end

# the storage class of the cell at address `a`
@inline _gcs_stg(a::Int)::word = a < 0 ? STG_LOCAL : (a >= GC_TRAIL_BASE ? STG_STATIC : STG_GLOBAL)

# PORT: pl-gc.c makePtr
# DIVERGES: the storage class follows from the ADDRESS (`a` of the scheme above: global cell, slot or mark
# field, trail entry); upstream finds it by asking which stack the pointer lies on.
"The pointer word to the cell at address `a`, with tag `t` (pl-gc.c `makePtr`)."
@inline function makePtr(a::Int, t::word)::word
    return consPtr(a < 0 ? -a : (a >= GC_TRAIL_BASE ? a - GC_TRAIL_BASE : a), t | _gcs_stg(a))
end

# the address a pointer word names (the inverse of makePtr)
@inline function _gcs_unptr(w::word)::Int
    s = storage(w)
    return s == STG_LOCAL ? -valPtr(w) : (s == STG_STATIC ? GC_TRAIL_BASE + valPtr(w) : valPtr(w))
end

# PORT: pl-gc.c offset_word
# DIVERGES: the kernel stores no inline indirect (ruling D1: a value is ONE box cell and its payload lives in
# the value table), so no word is an indirect header and the offset is always 0.
"The number of cells that follow a cell with word `m` and belong to it (0: the kernel has no inline indirects)."
@inline offset_word(m::word)::Int = 0

# PORT: pl-gc.c offset_cell
"`offset_word` of the global cell at position `p` (pl-gc.c)."
@inline offset_cell(ld::PL_local_data, p::Int)::Int = offset_word(ld.gstack[p])

# ORIGINAL: the words a chain can hold. A global reference, an attributed variable or a global compound
# names a CELL (position); a value-table word (D1) names a table entry, and everything else (atom, tagged
# integer, SLOT_VALUE, 0) names nothing.
@inline _gcs_chainable(w::word)::Bool = _gc_is_global_ref(w) && !_is_vword(w)

# ORIGINAL: the table index of the value-table box at position `p`, 0 when `p` is no box (the mark of a box
# cell is the same bit as any other: compaction asks this for each cell it moves and re-points `vbox`).
@inline gc_box_index(ld::PL_local_data, p::Int)::Int = _is_box(ld, p) ? valPtr(ld.gstack[p]) : 0

# ---- the chains ----

# PORT: pl-gc.c update_relocation_chain
# DIVERGES: `head` is the address of the head cell and `dest` the NEW POSITION it moves to (an Int `> 0`);
# the debug statistics are `sw.relocated_cells` and `sw.relocation_chains`.
"""
    update_relocation_chain(ld, sw, head, dest)

Unwind the relocation chain headed at cell `head`: every referrer gets `makePtr(dest, its tag)` and the
head gets its original value back (pl-gc.c).
"""
function update_relocation_chain(ld::PL_local_data{T}, sw::gc_sweep_counts, head::Int, dest::Int)::Nothing where {T}
    current = head
    val = gc_get_value(_gcs_get(ld, current))
    while true
        cell = _gcs_get(ld, current)
        _gcs_set!(ld, current, clear_first(cell))
        current = _gcs_unptr(val)
        t = tag(val)
        cell = _gcs_get(ld, current)
        val = gc_get_value(cell)
        _gcs_set!(ld, current, gc_set_value(cell, makePtr(dest, t)))
        sw.relocated_cells += 1
        is_first(_gcs_get(ld, current)) || break
    end
    cell = _gcs_get(ld, head)
    _gcs_set!(ld, head, gc_set_value(cell, val))
    sw.relocation_chains -= 1
    return nothing
end

# PORT: pl-gc.c into_relocation_chain
# DIVERGES: `current` is an address (see the header); `stg` must be its storage class (upstream passes the
# class of the referrer's stack; here it follows from the address and a mismatch is a bug: an error).
"""
    into_relocation_chain(ld, sw, current, stg)

Insert the referrer at address `current` (its word is a pointer to the head cell) into the relocation
chain of that cell (pl-gc.c).
"""
function into_relocation_chain(ld::PL_local_data{T}, sw::gc_sweep_counts, current::Int, stg::word)::Nothing where {T}
    stg == _gcs_stg(current) || error("GC: into_relocation_chain: storage class does not match the address $(current)")
    cell = _gcs_get(ld, current)
    val = gc_get_value(cell)
    head = _gcs_unptr(val)                         # FIRST/MARK already gone
    head == current && error("GC: into_relocation_chain: a cell references itself")
    hcell = _gcs_get(ld, head)
    _gcs_set!(ld, current, gc_set_value(cell, gc_get_value(hcell)))
    _gcs_set!(ld, head, gc_set_value(hcell, makePtr(current, tag(val))))
    if is_first(_gcs_get(ld, head))
        _gcs_set!(ld, current, set_first(_gcs_get(ld, current)))
    else
        _gcs_set!(ld, head, set_first(_gcs_get(ld, head)))
        sw.relocation_chains += 1
    end
    sw.relocation_cells += 1
    return nothing
end

# PORT: pl-gc.c alien_into_relocation_chain
# DIVERGES: the field at `a` holds a RAW position (a height) that names a cell of storage `orgst`; the
# storage class of the referrer follows from `a`.
"""
    alien_into_relocation_chain(ld, sw, a, orgst)

Convert the raw position in the cell at `a` (a mark field, a slot) to a pointer of storage `orgst` and put
it into the relocation chain of the cell it names (pl-gc.c).
"""
function alien_into_relocation_chain(ld::PL_local_data{T}, sw::gc_sweep_counts, a::Int, orgst::word)::Nothing where {T}
    _gcs_set!(ld, a, consPtr(Int(_gcs_get(ld, a)), orgst))
    into_relocation_chain(ld, sw, a, _gcs_stg(a))
    sw.alien_relocations += 1
    return nothing
end

# PORT: pl-gc.c make_gc_hole
# DIVERGES: a hole is a run of ordinary one-cell variables (word 0): a linear scan steps over it cell by cell
# (ruling D1: no inline indirects, so no header pair `mkIndHdr(wsize, TAG_STRING)` to skip it in one step);
# it spans `bottom..top` INCLUSIVE (upstream writes the two headers at `bottom` and `top`) and is made only
# when `top - bottom > 4`; returns `bottom`.
"Turn the garbage cells `bottom..top` of the global stack into a hole a scan can step over (pl-gc.c)."
function make_gc_hole(ld::PL_local_data{T}, bottom::Int, top::Int)::Int where {T}
    if top - bottom > 4
        for p in bottom:top
            ld.gstack[p] = UInt64(0)
        end
    end
    return bottom
end

# ---- the marks ----

# ORIGINAL: a height held in the cell at address `a` (a mark field, or the slot of the saved frozen bar whose
# word references the bar's cell) and its raw store (a raw position, as `alien_into_relocation_chain` expects).
@inline function _gcs_h_get(ld::PL_local_data{T}, a::Int)::Int where {T}
    return _gcs_is_mfield(a) ? _gcs_mf_get(ld, a) : valPtr(ld.slots[-a])
end

@inline function _gcs_h_set!(ld::PL_local_data{T}, a::Int, h::Int)::Nothing where {T}
    return _gcs_set!(ld, a, UInt64(h))
end

# PORT: pl-gc.c sweep_global_mark
# DIVERGES: `a` is the address of a height field (see the header): the new height is that of the highest
# MARKED cell at or below it (0 when none), and the chain head is that cell; the filler of the skipped region
# is `consVar(height)` in the cells above it, and a cell with a non-zero `TAG_VAR` word is such a filler,
# as upstream's. Upstream's scan also steps over a LARGE cell by its header: the kernel has none (D1).
# The bottom of the stack needs no dummy marked cell: the scan stops at position 0.
"""
    sweep_global_mark(ld, st, sw, a)

Sweep the global-top height held at address `a` to the position of the highest live cell below it and put
it into that cell's relocation chain (pl-gc.c).
"""
function sweep_global_mark(ld::PL_local_data{T}, st::gc_mark_counts, sw::gc_sweep_counts, a::Int)::Nothing where {T}
    m = _gcs_h_get(ld, a)
    gm = 0
    if m < 1
        gm = 0                                          # no cell below the mark: no chain
    elseif is_marked(ld.gstack[m]) || is_first(ld.gstack[m])
        gm = m                                          # quit common easy case
    else
        prev = m
        while prev >= 1
            w = ld.gstack[prev]
            if is_marked(w) || is_first(w)
                gm = prev
                fw = consTagged(gm, TAGEX_VAR)
                for p in (gm + 1):m
                    ld.gstack[p] = fw                   # (*)
                end
                break
            end
            if tag(w) == TAG_VAR && w != 0
                gm = Int(valTagged(w))                  # (*) the filler left by an earlier scan
                break
            end
            prev -= 1
        end
    end
    _gcs_h_set!(ld, a, gm)
    if gm >= 1
        st.needs_relocation += 1
        alien_into_relocation_chain(ld, sw, a, STG_GLOBAL)
    end
    return nothing
end

# PORT: pl-gc.c sweep_mark
# DIVERGES: the mark is named by (`isfli`, `i`): choicepoint `i` of `ld.choices` or foreign frame `i` of
# `ld.fliframes`; `saved_bar` is clamped to `ld.gTop`, a height.
"Sweep the global-top and the saved bar of a backtrack mark (pl-gc.c)."
function sweep_mark(ld::PL_local_data{T}, st::gc_mark_counts, sw::gc_sweep_counts, isfli::Bool, i::Int)::Nothing where {T}
    sw.marks_swept += 1
    sweep_global_mark(ld, st, sw, _gcs_mfield(isfli, i, 0))
    sb = _gcs_mfield(isfli, i, 1)
    _gcs_h_get(ld, sb) > ld.gTop && _gcs_h_set!(ld, sb, ld.gTop)
    sweep_global_mark(ld, st, sw, sb)
    return nothing
end

# ORIGINAL: the saved `frozen_bar` slot of `gvars_to_term_refs` (a raw slot above lTop holding a reference
# to the bar's cell; `sb` is its slot POSITION) is swept as a mark's global-top height: `term_refs_to_gvars`
# reads `valPtr` of the slot after compaction.
"Sweep the saved frozen-bar slot at slot position `sb` (pl-gcmark.jl `gvars_to_term_refs`) like a mark's global top."
function sweep_frozen_bar(ld::PL_local_data{T}, st::gc_mark_counts, sw::gc_sweep_counts, sb::Int)::Nothing where {T}
    sb == 0 && return nothing
    sweep_global_mark(ld, st, sw, -(sb + 1))
    return nothing
end

# ORIGINAL: the part of the sweep of one slot that upstream repeats in sweep_foreign, sweep_frame and
# sweep_new_arguments: a MARKED slot loses its mark; one that references a global cell leaves `local_marked`
# (`processLocal`) and, unless it is a value-table word (D1), joins that cell's chain.
function _gcs_sweep_marked_slot(ld::PL_local_data{T}, st::gc_mark_counts, sw::gc_sweep_counts, idx::Int)::Nothing where {T}
    w = ld.slots[idx]
    ld.slots[idx] = clear_marked(w)
    v = gc_get_value(w)
    if _gc_is_global_ref(v)
        st.local_marked -= 1                           # processLocal(sp)
        _gcs_chainable(v) && into_relocation_chain(ld, sw, -idx, STG_LOCAL)
    end
    return nothing
end

# PORT: pl-gc.c sweep_foreign
"Sweep the marks and the term references of the foreign frames, newest first (pl-gc.c)."
function sweep_foreign(ld::PL_local_data{T}, st::gc_mark_counts, sw::gc_sweep_counts)::Nothing where {T}
    fr = ld.fli_context
    while fr != 0
        f = ld.fliframes[fr]
        isRealMark(f.mark) && sweep_mark(ld, st, sw, true, fr)
        for k in 0:(f.size - 1)
            idx = _gc_fli_slot(f, k)
            is_marked(ld.slots[idx]) && _gcs_sweep_marked_slot(ld, st, sw, idx)
        end
        fr = f.parent
    end
    return nothing
end

# PORT: pl-gc.c sweep_trail
# DIVERGES: the trail is expected in upstream's tagged form (header), walked by INDEX, newest first; there
# are no local-stack trail entries, so the only entries that stay out of a chain are the deleted ones (0).
"Put the trail entries (tagged form) that point into the global stack into the chains of the cells they name (pl-gc.c)."
function sweep_trail(ld::PL_local_data{T}, st::gc_mark_counts, sw::gc_sweep_counts)::Nothing where {T}
    for i in length(ld.trail):-1:1
        w = ld.trail[i]
        w == 0 && continue
        if (w & TAG_TRAILMASK) == TAG_TRAILVAL || storage(w) == STG_GLOBAL
            st.needs_relocation += 1
            into_relocation_chain(ld, sw, GC_TRAIL_BASE + i, STG_STATIC)
        end
    end
    return nothing
end

# PORT: pl-gc.c sweep_frame
# DIVERGES: `fr` is an index into `ld.frames`; there is no atom GC (ruling D5), so no atom is volatile and an
# unmarked slot is replaced only when it references the global stack (by `garbage_collected`).
"Sweep the first `slots` argument/variable slots of frame `fr` (pl-gc.c)."
function sweep_frame(ld::PL_local_data{T}, st::gc_mark_counts, sw::gc_sweep_counts, fr::Int, slots::Int)::Nothing where {T}
    sp = argFrameP(ld.frames[fr].base, 0)
    for i in 0:(slots - 1)
        idx = sp + i + 1
        w = ld.slots[idx]
        if is_marked(w)
            _gcs_sweep_marked_slot(ld, st, sw, idx)
        elseif _gc_is_global_ref(w)
            ld.slots[idx] = _atom_word!(ld, mk_sym(T, :garbage_collected))
        end
    end
    return nothing
end

# PORT: pl-gc.c sweep_environments
# DIVERGES: `pc` is an index into the frame's clause codes (0 = NULL); the result is the QUERY index the walk
# reached (0 = NULL: a frame that was not marked ends it).
"Sweep frame `fr` and its parents while they are marked; return the query the chain ends in, or 0 (pl-gc.c)."
function sweep_environments(ld::PL_local_data{T}, st::gc_mark_counts, sw::gc_sweep_counts, fr::Int, pc::Int)::Int where {T}
    fr == 0 && return 0
    while true
        f = ld.frames[fr]
        (f.flags & FR_MARKED) == 0 && return 0
        f.flags &= ~FR_MARKED
        sweep_frame(ld, st, sw, fr, gc_slots_in_frame(ld, fr, pc))
        if f.parent != 0
            pc = f.programPointer.pc
            fr = f.parent
        else
            return queryOfFrame(ld, fr)
        end
    end
end

# PORT: pl-gc.c sweep_choicepoints
"Sweep the environments and the marks of the choicepoints `ch` (an index) and their parents (pl-gc.c)."
function sweep_choicepoints(ld::PL_local_data{T}, st::gc_mark_counts, sw::gc_sweep_counts, ch::Int)::Nothing where {T}
    while ch != 0
        c = ld.choices[ch]
        sweep_environments(ld, st, sw, c.frame, c.type == CHP_JUMP ? c.value_pc : 0)
        sweep_mark(ld, st, sw, false, ch)
        ch = c.parent
    end
    return nothing
end

# PORT: pl-gc.c sweep_new_arguments
"Sweep the `new_args` argument slots at `lNext` that the VMI had begun to build (pl-gc.c)."
function sweep_new_arguments(ld::PL_local_data{T}, st::gc_mark_counts, sw::gc_sweep_counts, vm::vm_state)::Nothing where {T}
    if vm.lNext != 0
        sp = argFrameP(vm.lNext, 0)
        for i in 0:(vm.new_args - 1)
            idx = sp + i + 1
            is_marked(ld.slots[idx]) || error("GC: sweep_new_arguments: argument slot $(idx) is not marked")
            _gcs_sweep_marked_slot(ld, st, sw, idx)
        end
    end
    return nothing
end

# PORT: pl-gc.c sweep_stacks
# DIVERGES: as `mark_stacks`: a parent query inside the VM needs G1-2's `vmi_state_of(ld, query_index)`
# (`get_vmi_state`, pin pl-gc.c) and without it is a named refusal; `local_marked != 0` at the end is an
# error (upstream's `sysError`), and the `CHK_SECURE` table dump is not kept.
"""
    sweep_stacks(ld, st, sw, vm; vmi_state_of=nothing)

Sweep the local stack from the safe point `vm` outward through the queries, choicepoints and
environments (pl-gc.c); every slot mark cell must be consumed (`st.local_marked == 0`).
"""
function sweep_stacks(
    ld::PL_local_data{T}, st::gc_mark_counts, sw::gc_sweep_counts, vm::vm_state; vmi_state_of = nothing
)::Nothing where {T}
    fr = vm.frame
    ch = vm.choice
    pc = vm.pc_start_vmi
    sweep_new_arguments(ld, st, sw, vm)
    while fr != 0
        qf = sweep_environments(ld, st, sw, fr, pc)
        qf == 0 && error("sweep_stacks: the sweep of frame $(fr) reached no query frame")
        sweep_choicepoints(ld, st, sw, ch)
        q = ld.queries[qf]
        q.parent == 0 && break
        pqf = q.parent
        pq = ld.queries[pqf]
        if pq.registers_fr != 0
            vmi_state_of === nothing && throw(
                NotPortedError(ld.placeholder, "get_vmi_state of a parent query (pl-gc.c sweep_stacks)", "G1-2"),
            )
            sub = vmi_state_of(ld, pqf)::vm_state
            fr = pq.registers_fr
            pc = sub.pc_start_vmi
            sweep_new_arguments(ld, st, sw, sub)
        else
            fr = q.saved_environment
            pc = 0
        end
        ch = q.saved_bfr
    end
    st.local_marked == 0 || error("GC: sweep_stacks: local_marked = $(st.local_marked)")
    return nothing
end

# PORT: pl-gc.c is_downward_ref
# DIVERGES: `p` is a global position; a value-table word names a table entry, not a cell, so it is no
# reference in either direction (ruling D1), and neither is an inline indirect (the kernel has none).
"Whether the cell at position `p` of the global stack references a LOWER cell (pl-gc.c)."
function is_downward_ref(ld::PL_local_data{T}, p::Int)::Bool where {T}
    val = gc_get_value(ld.gstack[p])
    _gcs_chainable(val) || return false
    return valPtr(val) < p
end

# PORT: pl-gc.c is_upward_ref
"Whether the cell at position `p` of the global stack references a HIGHER cell (pl-gc.c)."
function is_upward_ref(ld::PL_local_data{T}, p::Int)::Bool where {T}
    val = gc_get_value(ld.gstack[p])
    _gcs_chainable(val) || return false
    return valPtr(val) > p
end
