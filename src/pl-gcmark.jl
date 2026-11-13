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

# ---- cells that hold a global-stack reference ----
# PORT: pl-incl.h isGlobalRef
# DIVERGES: a value-table word (`_is_vword`: a float/string/bigint, storage STG_RESERVED) is a global
# reference too: its box cell lives on the global stack (ruling D1). The kernel's global words are a
# reference, an attributed variable, a compound (`_is_gcompound`) and that vword; everything else (atom,
# tagged integer, SLOT_VALUE, 0) names no global cell.
@inline _gc_is_global_ref(w::word)::Bool =
    (isRef(w) && storage(w) == STG_GLOBAL) || isAttVar(w) || _is_gcompound(w) || _is_vword(w)

# PORT: pl-fli.c PL_new_term_ref_noshift
# DIVERGES: a new term reference holding the WORD `w` and NO fresh global cell: the collector must not
# allocate on the global stack (the kernel's `PL_new_term_ref` makes a variable cell). The caller has
# made room (`ensureLocalSpace`), as upstream's callers rely on `PL_open_foreign_frame`; a full local
# stack is an error here (upstream asserts a non-zero result).
"A term reference holding `w` in the innermost foreign frame, without shifting and without allocating (pl-fli.c)."
function gc_new_term_ref!(ld::PL_local_data, w::word)::Int
    hasLocalSpace(ld, 1) || error("GC: no local space for a term reference (PL_new_term_ref_noshift)")
    t = ld.lTop
    ld.slots[t + 1] = w
    ld.lTop = t + 1
    ld.fliframes[ld.fli_context].size += 1
    return t
end

# the word of term reference `t` / of the k-th reference of the foreign frame `f`
@inline _gc_fli_slot(f, k::Int)::Int = refFliP(f.base, k) + 1

# PORT: pl-gc.c mark_local_variable
# DIVERGES: the kernel stores no local-stack reference (no `isLocalRef` word: a slot holds 0, a global
# reference, an atom, a global compound, a tagged integer, a value-table word or SLOT_VALUE), so
# upstream's `while ( isLocalRef(*p) )` chain is never entered; `a` is a (negative) slot address.
"Mark the local cell at address `a` (a slot): what it references on the global stack, else the slot only (pl-gc.c)."
function mark_local_variable(ld::PL_local_data{T}, st::gc_mark_counts, a::Int)::Nothing where {T}
    w = _gc_get(ld, a)
    if isRef(w) && storage(w) == STG_LOCAL
        throw(NotPortedError(ld.placeholder, "a local-stack reference in mark_local_variable (pl-gc.c:1791; the kernel stores none)", "G1-3"))
    end
    if _gc_is_global_ref(w)
        mark_variable(ld, st, a)
    else
        _gc_set!(ld, a, set_marked(w))                  # ldomark(p)
    end
    return nothing
end

# PORT: pl-gc.c mark_arguments
"Mark the arguments of the frame at index `fi` of `ld.frames` (pl-gc.c)."
function mark_arguments(ld::PL_local_data{T}, st::gc_mark_counts, fi::Int)::Nothing where {T}
    fr = ld.frames[fi]
    for n in 0:(fr.predicate.arity - 1)
        a = -(argFrameP(fr.base, n) + 1)
        is_marked(_gc_get(ld, a)) || mark_local_variable(ld, st, a)
    end
    return nothing
end

# PORT: pl-gc.c mark_new_arguments
# DIVERGES: `lNext` is the POSITION of the frame being built (0 = NULL), arguments at `argFrameP(lNext, n)`.
"Mark the `new_args` arguments of the frame being built at the safe point (pl-gc.c)."
function mark_new_arguments(ld::PL_local_data{T}, st::gc_mark_counts, vm::vm_state)::Nothing where {T}
    if vm.lNext != 0
        for n in 0:(vm.new_args - 1)
            a = -(argFrameP(vm.lNext, n) + 1)
            is_marked(_gc_get(ld, a)) || mark_local_variable(ld, st, a)
        end
    end
    return nothing
end

# PORT: pl-gc.c mark_trie_gen
"Mark the `prolog_vars` variables of the trie-generator frame at index `fi` (pl-gc.c)."
function mark_trie_gen(ld::PL_local_data{T}, st::gc_mark_counts, fi::Int)::Nothing where {T}
    fr = ld.frames[fi]
    for n in 0:(fr.clause.clause.prolog_vars - 1)
        a = -(argFrameP(fr.base, n) + 1)
        is_marked(_gc_get(ld, a)) || mark_local_variable(ld, st, a)
    end
    return nothing
end

# PORT: pl-gc.c mark_term_refs
"Mark every term reference of every foreign frame, innermost first (pl-gc.c)."
function mark_term_refs(ld::PL_local_data{T}, st::gc_mark_counts)::Nothing where {T}
    fr = ld.fli_context
    while fr != 0
        f = ld.fliframes[fr]
        for k in 0:(f.size - 1)
            a = -_gc_fli_slot(f, k)
            w = _gc_get(ld, a)
            if !is_marked(w)
                if _gc_is_global_ref(w)
                    mark_variable(ld, st, a)
                else
                    mark_local_variable(ld, st, a)
                end
            end
        end
        fr = f.parent
    end
    return nothing
end

# PORT: pl-gc.c mark_foreign_frame
# DIVERGES: `fi` indexes `ld.fliframes`, `te` is the trail INDEX early reset has reached (the entry
# upstream's pointer names; the trail grows upwards in `ld.trail`). Upstream then puts the frame's
# `mark.trailtop` into the relocation chain: that is the sweep's (G1-5).
"Early-reset the variables trailed since foreign frame `fi` was opened and count its trail mark (pl-gc.c)."
function mark_foreign_frame(ld::PL_local_data{T}, st::gc_mark_counts, fi::Int, te::Int)::Int where {T}
    f = ld.fliframes[fi]
    if isRealMark(f.mark)
        te = early_reset_vars(ld, st, f.mark, te)       # G1-3b
        st.needs_relocation += 1                        # needsRelocation(&fr->mark.trailtop.as_word)
        # G1-5: alien_into_relocation_chain(&fr->mark.trailtop.as_word, STG_TRAIL, STG_LOCAL)
    end
    return te
end

# ---- the roots the kernel turns into term references for the mark phase ----

# PORT: pl-gc.c save_grefs
# DIVERGES: the kernel has no `LD->attvar.gc_attvars` term reference (PL_local_data carries none): the
# newest attvar link is held in a foreign frame of its own, returned as a handle (0: no attvars).
"Save the newest link of the attvar chain in a term reference of a new foreign frame (pl-gc.c)."
function save_grefs(ld::PL_local_data{T})::Int where {T}
    ld.attvar_attvars == 0 && return 0
    ensureLocalSpace(ld, SIZEOF_FLIFRAME + 3) || error("GC: no local space for save_grefs")
    fid = open_foreign_frame(ld)
    gc_new_term_ref!(ld, makeRefG(ld.attvar_attvars))
    return fid
end

# PORT: pl-gc.c restore_grefs
"Read the (relocated) attvar chain head back from `fid` and close its frame (pl-gc.c); runs before `term_refs_to_gvars`."
function restore_grefs(ld::PL_local_data{T}, fid::Int)::Nothing where {T}
    fid == 0 && return nothing
    f = ld.fliframes[fliFrameOfFid(ld, fid)]
    ld.attvar_attvars = unRef(gc_get_value(ld.slots[_gc_fli_slot(f, 0)]))
    PL_close_foreign_frame(ld, fid)
    return nothing
end

# PORT: pl-gc.c gvars_to_term_refs
# DIVERGES: (1) the table is `ld.gvar_nb_vars`; its keys are collected once in a fixed order (the Dict is
# not modified between the two passes, so `term_refs_to_gvars` sees the same order); (2) the pass does
# not wait for `gvar_grefs > 0` and does not assert `grefs == found`: the count is a hint of the kernel's
# bookkeeping, a value on the global stack is a root whatever it says; (3) the saved `frozen_bar` is a
# raw slot above `lTop` (not counted in the frame's `size`), holding a global reference word; its
# relocation is the sweep's (G1-5). Returns the frame handle and the SLOT POSITION of the saved bar (0: none).
"Turn the global-stack values of the nb_ variables into term references of a new foreign frame; save the frozen bar (pl-gc.c)."
function gvars_to_term_refs(ld::PL_local_data{T})::Tuple{Int, Int} where {T}
    fid = PL_open_foreign_frame(ld)
    fid == 0 && error("GC: no local space for gvars_to_term_refs")
    if !isempty(ld.gvar_nb_vars)
        ks = collect(keys(ld.gvar_nb_vars))
        ensureLocalSpace(ld, length(ks) + 2) || error("GC: no local space for the global variables")
        for k in ks
            w = ld.gvar_nb_vars[k]
            _gc_is_global_ref(w) && gc_new_term_ref!(ld, w)
        end
    end
    sb = 0
    if ld.frozen_bar != 0
        hasLocalSpace(ld, 1) || error("GC: no local space for the frozen bar")
        sb = ld.lTop
        ld.slots[sb + 1] = consPtr(ld.frozen_bar, TAG_REFERENCE | STG_GLOBAL)
        ld.lTop = sb + 1                                # lTop = (LocalFrame)(sb+1)
        # G1-5: the sweep relocates this slot (upstream: a gc_wordptr on top of the local stack)
    end
    return (fid, sb)
end

# PORT: pl-gc.c term_refs_to_gvars
"Write the (relocated) term references back into the nb_ variables, restore the frozen bar, close the frame (pl-gc.c)."
function term_refs_to_gvars(ld::PL_local_data{T}, fid::Int, sb::Int)::Nothing where {T}
    if sb != 0
        ld.lTop == sb + 1 || error("GC: term_refs_to_gvars: the saved bar is not the top of the local stack")
        ld.frozen_bar = valPtr(ld.slots[sb + 1])
        ld.slots[sb + 1] = 0
        lowerLTop!(ld, sb)                              # lTop = saved_bar_at
    end
    if !isempty(ld.gvar_nb_vars)
        f = ld.fliframes[fliFrameOfFid(ld, fid)]
        found = 0
        for k in collect(keys(ld.gvar_nb_vars))
            if _gc_is_global_ref(ld.gvar_nb_vars[k])
                ld.gvar_nb_vars[k] = gc_get_value(ld.slots[_gc_fli_slot(f, found)])
                found += 1
            end
        end
        found == f.size || error("GC: term_refs_to_gvars: $(found) values for a frame of $(f.size)")
    end
    PL_close_foreign_frame(ld, fid)
    return nothing
end

# PORT: pl-gc.c argument_stack_to_term_refs
# DIVERGES: the argument stack holds RECORDS (`argstack_entry`: an `argp_t` of form ARGP_SLOT/ARGP_GLOBAL
# plus the UWRITE flag), not tagged pointers; a slot entry is upstream's LARGP case and needs no tagging
# (its form says it). `LD->query->registers.argp` is `ld.queries[ld.query].registers_argp`.
"Turn the global entries of the argument stack into term references of a new foreign frame (pl-gc.c); 0 when `vm.save_argp` is off."
function argument_stack_to_term_refs(ld::PL_local_data{T}, vm::vm_state)::Int where {T}
    vm.save_argp || return 0
    ensureLocalSpace(ld, SIZEOF_FLIFRAME + ld.aTop + 4) || error("GC: no local space for argument_stack_to_term_refs")
    fid = open_foreign_frame(ld)
    pushArgumentStack(ld, argstack_entry{T}(ld.queries[ld.query].registers_argp, false))
    vm.uwrite_count = 0
    for i in 1:ld.aTop
        e = ld.astack[i]
        if e.argp.form == ARGP_GLOBAL
            if e.uwrite
                gc_new_term_ref!(ld, consPtr(e.argp.pos, TAG_ATTVAR | STG_GLOBAL))      # consAttVar(adr)
                vm.uwrite_count += 1
            else
                gc_new_term_ref!(ld, makeRefG(e.argp.pos))
            end
        end
    end
    return fid
end

# PORT: pl-gc.c term_refs_to_argument_stack
"Write the (relocated) term references back into the argument stack, pop the pushed `registers_argp`, close the frame (pl-gc.c)."
function term_refs_to_argument_stack(ld::PL_local_data{T}, vm::vm_state, fid::Int)::Nothing where {T}
    fid == 0 && return nothing
    f = ld.fliframes[fliFrameOfFid(ld, fid)]
    found = 0
    uwc = 0
    for i in 1:ld.aTop
        e = ld.astack[i]
        if e.argp.form == ARGP_GLOBAL
            w = gc_get_value(ld.slots[_gc_fli_slot(f, found)])
            found += 1
            uw = tag(w) == TAG_ATTVAR
            uw && (uwc += 1)
            ld.astack[i] = argstack_entry{T}(argp_t{T}(ARGP_GLOBAL, valPtr(w), e.argp.term), uw)
        end
    end
    found == f.size || error("GC: term_refs_to_argument_stack: $(found) references for a frame of $(f.size)")
    uwc == vm.uwrite_count || error("GC: term_refs_to_argument_stack: $(uwc) UWRITE entries, saved $(vm.uwrite_count)")
    ld.queries[ld.query].registers_argp = ld.astack[ld.aTop].argp       # registers.argp = *--aTop
    ld.aTop -= 1
    PL_close_foreign_frame(ld, fid)
    return nothing
end

# PORT: pl-gc.c count_need_protection_attvars
"The number of attributed variables on the `attvars` chain (pl-gc.c; call_residue_vars)."
function count_need_protection_attvars(ld::PL_local_data{T})::Int where {T}
    attvars = 0
    p = ld.attvar_attvars
    while p != 0
        avp = p + 1
        nxt = isRef(ld.gstack[p]) ? unRef(ld.gstack[p]) : 0
        isAttVar(ld.gstack[avp]) && (attvars += 1)
        p = nxt
    end
    return attvars
end

# PORT: pl-gc.c link_attvars
"Protect the attributed variables of the `attvars` chain as term references of a new foreign frame (pl-gc.c); 0 when not under call_residue_vars."
function link_attvars(ld::PL_local_data{T})::Int where {T}
    (ld.attvar_call_residue_vars_count != 0 && ld.attvar_attvars != 0) || return 0
    ensureLocalSpace(ld, SIZEOF_FLIFRAME + count_need_protection_attvars(ld) + 2) ||
        error("GC: no local space for link_attvars")
    fid = open_foreign_frame(ld)
    p = ld.attvar_attvars
    while p != 0
        avp = p + 1
        nxt = isRef(ld.gstack[p]) ? unRef(ld.gstack[p]) : 0
        isAttVar(ld.gstack[avp]) && gc_new_term_ref!(ld, makeRefG(avp))
        p = nxt
    end
    return fid
end

# PORT: pl-gc.c restore_attvars
"Close the frame `link_attvars` opened (pl-gc.c)."
function restore_attvars(ld::PL_local_data{T}, fid::Int)::Nothing where {T}
    fid != 0 && PL_close_foreign_frame(ld, fid)
    return nothing
end

# ORIGINAL: clear every gc bit the mark phase set — MARK and FIRST on the global cells and the slots, the
# FR_MARKED / FR_MARKED_PRED flags of the frames. Upstream's sweep clears them as it compacts (G1-5);
# until it exists, and for the tests, this restores the stacks to their unmarked state.
"Clear the MARK/FIRST bits of every live global cell and slot and the frame mark flags (ORIGINAL)."
function gc_clear_marks!(ld::PL_local_data{T})::Nothing where {T}
    for i in 1:ld.gTop
        ld.gstack[i] = ld.gstack[i] & VALUE_MASK
    end
    for i in 1:ld.lTop
        ld.slots[i] = ld.slots[i] & VALUE_MASK
    end
    for i in 1:ld.nframes
        f = ld.frames[i]
        f.flags = f.flags & ~UInt32(FR_MARKED | FR_MARKED_PRED)
    end
    return nothing
end
