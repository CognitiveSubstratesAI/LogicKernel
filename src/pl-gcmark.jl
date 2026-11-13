# UPSTREAM: swipl-devel src/pl-gc.c @ 18168e629eab
# UPSTREAM: swipl-devel src/pl-data.h @ 18168e629eab
# CLASS: code
# COPYRIGHT: Copyright (c)  1985-2024, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
# allow-new-artifact: a port of pl-gc.c at the pin (read via git show 18168e62:src/pl-gc.c; the design is in evidence/G1/g1gc3_handoff.md)
# G1-GC (G1-3a): the MARK phase of SWI-Prolog's stack garbage collector (pl-gc.c): the cell-bit
# helpers, `mark_variable` (pointer reversal), the term-reference roots and the per-frame marking
# helpers. The mark phase MOVES and FREES NOTHING: it sets MARK bits (and, for the moment of a walk,
# FIRST bits and reversed pointers, all restored before it returns). The walk, early reset,
# choicepoints and environments (G1-3b) live in pl-gcwalk.jl; the sweep and compaction are G1-5.
#
# CELL ADDRESSING (DIVERGES from upstream's `Word`): a cell is addressed by an Int `a`: `a > 0` is the
# position of a cell of the global stack (`ld.gstack[a]`), `a < 0` is the INDEX of a slot of the local
# stack (`ld.slots[-a]`; the slot at local position `pos` has index `pos + 1`). Upstream stores
# `makeRefLG(current)` / `makePtr(current, tag)` back pointers in cells whose address may lie on the
# local stack (the start cell), so a back pointer carries its storage class: `_gc_ptr`/`_gc_unptr`.

"""
    gc_mark_counts()

The counters of one mark phase (upstream's `LD->gc.*` / `total_marked` / `needs_relocation`
statistics): `total_marked` (cells marked on the global stack; a local start cell nets 0),
`needs_relocation` (references to relocate; consumed by G1-5), `local_marked` (marked local cells),
`trailcells_deleted` (trail entries zeroed by early reset).
"""
mutable struct gc_mark_counts
    total_marked::Int
    needs_relocation::Int
    local_marked::Int
    trailcells_deleted::Int
    gc_mark_counts() = new(0, 0, 0, 0)
end

# PORT: pl-gc.c vm_state
# DIVERGES: the registers are POSITIONS (a slot position, a frame base; 0 = NULL), not pointers; an ARGP
# in write mode on the global stack is stored as 0 (marking never reads it at `adepth > 0`). G1-2 builds
# this at the safe point (get_vmi_state); `frame`/`choice` are indexes into ld.frames/ld.choices (0 = none).
"""
    vm_state()

The state of the VM at the safe point (pin `vm_state`): the frame and choicepoint being run, the program
counter (`pc`, an index into the frame's clause codes), the start of the VMI (`pc_start_vmi`), `argp` and
`argp0` (positions), `adepth`, `lSave`/`lNext` (positions), the `new_args` count, the number of UWRITE
argument-stack entries (`uwrite_count`), `save_argp` and `in_body`.
"""
mutable struct vm_state
    frame::Int
    choice::Int
    pc::Int
    pc_start_vmi::Int
    argp::Int
    argp0::Int
    adepth::Int
    lSave::Int
    lNext::Int
    new_args::Int
    uwrite_count::Int
    save_argp::Bool
    in_body::Bool
    vm_state() = new(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, false, false)
end

# PORT: pl-gc.c mark_state
# DIVERGES: `flictx` is the index of the innermost foreign frame to mark, `reset_entry` the trail index
# early reset has reached (upstream: pointers into the foreign-frame and trail chains).
mutable struct mark_state
    vm::vm_state
    flictx::Int
    reset_entry::Int
    mark_state(vm::vm_state) = new(vm, 0, 0)
end

# ---- the cell-bit helpers (pl-data.h:186-193) ----
const GC_MASK = MARK_MASK | FIRST_MASK
const VALUE_MASK = ~GC_MASK

@inline is_marked(w::word)::Bool = (w & MARK_MASK) != 0
@inline is_first(w::word)::Bool = (w & FIRST_MASK) != 0
@inline set_marked(w::word)::word = w | MARK_MASK
@inline clear_marked(w::word)::word = w & ~MARK_MASK
@inline set_first(w::word)::word = w | FIRST_MASK
@inline clear_first(w::word)::word = w & ~FIRST_MASK
# get_value/set_value of pl-data.h: the value of a cell without the gc bits / a cell with a new value, bits kept.
# (`get_value(ld, p)` of pl-attvar.jl is another function: the word forms carry the prefix `gc_`.)
@inline gc_get_value(w::word)::word = w & VALUE_MASK
@inline gc_set_value(cell::word, w::word)::word = (cell & GC_MASK) | (w & VALUE_MASK)

@inline _gc_get(ld::PL_local_data, a::Int)::word = a > 0 ? ld.gstack[a] : ld.slots[-a]
@inline function _gc_set!(ld::PL_local_data, a::Int, w::word)::Nothing
    if a > 0
        ld.gstack[a] = w
    else
        ld.slots[-a] = w
    end
    return nothing
end
@inline _gc_ptr(a::Int, t::word)::word = consPtr(abs(a), t | (a < 0 ? STG_LOCAL : STG_GLOBAL))
@inline _gc_unptr(w::word)::Int = storage(w) == STG_LOCAL ? -valPtr(w) : valPtr(w)

# PORT: pl-gc.c domark
# DIVERGES: the count goes into the explicit `st` (upstream: the `total_marked` global of the collector).
@inline function domark(ld::PL_local_data, st::gc_mark_counts, a::Int)::Nothing
    w = _gc_get(ld, a)
    is_marked(w) && error("GC: domark of a marked cell $(a)")
    _gc_set!(ld, a, set_marked(w))
    st.total_marked += 1
    return nothing
end

# PORT: pl-gc.c mark_variable
# DIVERGES: (1) cell addressing as above (`start` is an Int address); (2) INDIRECTS (ruling D1): a float,
# string or bigint is a value-table word (`_is_vword`) whose BOX is ONE cell at `ld.vbox[i]`; marking a
# reference to it marks the box cell only and counts 1 (upstream marks the header and counts the whole
# indirect: `total_marked += offset_cell(next)`); an inline indirect (TAG_FLOAT/STRING/INTEGER with global
# storage, which the kernel never builds) is a named refusal; (3) `needsRelocation` is counted in
# `st.needs_relocation` and consumed by G1-5; (4) forward/backward are a `mode` state machine.
"Mark the cell at address `start` and everything reachable from it, by pointer reversal (pl-gc.c)."
function mark_variable(ld::PL_local_data{T}, st::gc_mark_counts, start::Int)::Nothing where {T}
    is_marked(_gc_get(ld, start)) && error("GC: attempt to mark twice")
    if start < 0
        st.local_marked += 1                    # markLocal(start)
        st.total_marked -= 1                    # do not count local stack cell
    end
    current = start
    _gc_set!(ld, current, set_first(_gc_get(ld, current)))
    val = gc_get_value(_gc_get(ld, current))
    mode = 1                                    # 1 = forward, 2 = backward
    while true
        if mode == 1
            # forward: go into the tree
            if is_marked(_gc_get(ld, current))      # have been here
                mode = 2
                continue
            end
            domark(ld, st, current)
            if _is_vword(val)                       # D1: an indirect marks its box cell only
                bp = ld.vbox[valPtr(val)]
                st.needs_relocation += 1
                if !is_marked(ld.gstack[bp])
                    ld.gstack[bp] = set_marked(ld.gstack[bp])
                    st.total_marked += 1
                end
                mode = 2
            elseif isRef(val)
                storage(val) == STG_GLOBAL ||
                    throw(NotPortedError(ld.placeholder, "a local-stack reference in the mark phase (pl-gc.c mark_variable; the kernel stores none)", "G1-3"))
                nxt = unRef(val)                    # address pointing to
                st.needs_relocation += 1
                if is_first(ld.gstack[nxt])         # ref to choice point; we will get there some day anyway
                    mode = 2
                else
                    val = gc_get_value(ld.gstack[nxt])      # invariant
                    ld.gstack[nxt] = gc_set_value(ld.gstack[nxt], _gc_ptr(current, TAG_REFERENCE))
                    current = nxt                   # invariant
                end
            elseif isAttVar(val)
                nxt = valPtr(val)
                st.needs_relocation += 1
                if is_marked(ld.gstack[nxt])        # term has already been marked
                    mode = 2
                else
                    val = gc_get_value(ld.gstack[nxt])      # invariant
                    ld.gstack[nxt] = gc_set_value(ld.gstack[nxt], _gc_ptr(current, TAG_ATTVAR))
                    current = nxt
                end
            elseif _is_gcompound(val)
                nxt = valPtr(val)                   # the FUNCTOR cell
                st.needs_relocation += 1
                if is_marked(ld.gstack[nxt])        # term has already been marked
                    mode = 2
                else
                    args = arityFunctor(ld.functors, ld.gstack[nxt])
                    domark(ld, st, nxt)
                    if args == 0
                        mode = 2
                    else
                        nxt += 2
                        while args > 1
                            is_first(ld.gstack[nxt]) && error("GC: first bit set twice")
                            ld.gstack[nxt] = set_first(ld.gstack[nxt])
                            args -= 1
                            nxt += 1
                        end
                        nxt -= 1                    # last cell of term
                        val = gc_get_value(ld.gstack[nxt])  # invariant
                        # backwards pointer (NO ref!)
                        ld.gstack[nxt] = gc_set_value(ld.gstack[nxt], _gc_ptr(current, TAG_COMPOUND))
                        current = nxt
                    end
                end
            elseif tagex(val) == (TAG_INTEGER | STG_GLOBAL) || tagex(val) == (TAG_STRING | STG_GLOBAL) ||
                   tagex(val) == (TAG_FLOAT | STG_GLOBAL)
                throw(NotPortedError(ld.placeholder, "an inline indirect on the global stack (D1: the kernel boxes values in the value table; pl-gc.c mark_variable)", "G1-3"))
            else
                mode = 2                            # atom, tagged integer, unbound (0)
            end
        else
            # backward: reversing the pointers
            while !is_first(_gc_get(ld, current))
                cell = _gc_get(ld, current)
                w = gc_get_value(cell)
                t = tag(w)
                nxt = _gc_unptr(w)
                _gc_set!(ld, current, gc_set_value(cell, val))
                if t == TAG_REFERENCE
                    val = makeRefG(current)
                elseif t == TAG_COMPOUND
                    val = consPtr(current - 1, TAG_COMPOUND | STG_GLOBAL)
                elseif t == TAG_ATTVAR
                    val = consPtr(current, TAG_ATTVAR | STG_GLOBAL)
                else
                    error("GC: bad back pointer in mark_variable")
                end
                current = nxt
            end
            _gc_set!(ld, current, clear_first(_gc_get(ld, current)))
            current == start && return nothing
            cell = _gc_get(ld, current)
            tmp = gc_get_value(cell)
            _gc_set!(ld, current, gc_set_value(cell, val))      # restore old value
            current -= 1
            cell = _gc_get(ld, current)
            val = gc_get_value(cell)                            # invariant
            _gc_set!(ld, current, gc_set_value(cell, tmp))
            mode = 1
        end
    end
end
