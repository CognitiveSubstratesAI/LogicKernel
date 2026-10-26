# UPSTREAM: swipl-devel src/pl-attvar.c @ cbf4e1896275
# UPSTREAM: swipl-devel src/pl-attvar.h @ cbf4e1896275
# CLASS: code
# COPYRIGHT: Copyright (c)  2004-2025, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# PORTED FROM pl-attvar.c, exactly these: `saveWakeup`, `restoreWakeup` and the helper
# `restore_exception` — the SAVE/RESTORE of the pending exception around foreign code that must run
# with none pending. From pl-attvar.h, `varBindConst` (L1c: the VM's `bindConst` of a global cell) and,
# since AV1, `bindConst` itself. Since AV3 the BINDING: `registerWakeup`, `assignAttVar`,
# `bind_attvar_const`, `restore_wakeup`, and the wakeup list in `saveWakeup`/`restoreWakeup` (pl-wam.c
# `updateAlerted`, its wakeup bit: src/pl-wam.jl). Since AV2 the STORE:
# `PL_get_attr`, `link_attvar`, `make_new_attvar`, `put_new_attvar`, `find_attr`, `put_att_value`,
# `put_attr`, `get_attr`, `del_attr` and the predicates attvar/1, put_attr/3, get_attr/3, del_attr/2,
# del_attrs/1, get_attrs/2, put_attrs/2, `$attv_unify/2` (`PL_predicates_from_attvar`).
# `findCatcher` (src/pl-wam.jl) is their first caller: while it unifies a ball with the catchers no
# exception is pending, so an error that unification raises (the occurs check under
# `occurs_check = error`) is raised, and becomes the ball.
#
# Since AV4 pl-wam.c `foreignWakeup` runs the hooks `registerWakeup` queued; it is in src/pl-wam.jl
# (its upstream file's .jl), as `updateAlerted`.
#
# NOT PORTED: the rest of pl-attvar.c, the steps after the binding (since AV3) —
# `freeze/2`'s support (AV7), `when/2`'s (AV8), call_residue_vars (AV9; so `trail_new_attvar` and
# `on_attvar_chain`, its CHK_SECURE check, wait for it), `alloc_attvar` (AV6) and
# `wakeup_state_exception`.

# PORT: pl-attvar.c saveWakeup
# DIVERGES: returns the state, or `nothing` for upstream's false (no space for the foreign frame). The
# ball's slot word is copied as upstream copies the cell (f3b-1: `_slot_copy!`, a side value with it;
# until then the ball was read as a term and stored as a slot's side value). The wakeup list (AV3):
# `*valTermRef(LD->attvar.head)` is the head's PERMANENT cell (`_attvar_head_cell`), `setVar` clears it
# (AV1, audit D-0122 Q1 (a)).
"""
    saveWakeup(ld, forceframe) -> wakeup_state, or nothing

Set the pending exception and the wakeup list aside in a foreign frame of their own and clear them
(pl-attvar.c); with neither pending, and `forceframe` false, no frame is opened. Nested as `PL_open_foreign_frame` is, and ended
by [`restoreWakeup`](@ref).
"""
function saveWakeup(
    ld::PL_local_data{T}, forceframe::Bool
)::Union{Nothing, wakeup_state} where {T}
    outofstack = ld.outofstack
    h = _attvar_head_cell(ld)
    if ld.gstack[h] != 0 || ld.exception_term != 0 || forceframe   # *valTermRef(LD->attvar.head) || …
        fid = PL_open_foreign_frame(ld)
        fid == 0 && return nothing              # no space!
        flags = UInt32(0)
        if ld.exception_term != 0
            flags |= WAKEUP_STATE_EXCEPTION
            s = PL_new_term_ref(ld)
            _slot_copy!(ld, s + 1, ld.exception_term + 1)   # *valTermRef(s) = *valTermRef(exception_term)
            ld.exception_term = 0
        end
        if ld.gstack[h] != 0                    # if ( *(h=valTermRef(LD->attvar.head)) )
            flags |= WAKEUP_STATE_WAKEUP
            s = PL_new_term_refs(ld, 2)
            ld.slots[s + 1] = ld.gstack[h]      # *valTermRef(s+0) = *h
            ld.gstack[h] = word(0)              # setVar(*h)
            ld.slots[s + 2] = ld.gstack[h + 1]  # h = valTermRef(LD->attvar.tail); *valTermRef(s+1) = *h
            ld.gstack[h + 1] = word(0)          # setVar(*h)
        end
        return wakeup_state(fid, outofstack, flags)
    end
    return wakeup_state(0, outofstack, UInt32(0))
end

# PORT: pl-attvar.c restore_exception
# DIVERGES: `p` is a position on the local stack, where upstream's is a pointer.
"Make the ball saved at position `p` the pending exception again (pl-attvar.c)."
function restore_exception(ld::PL_local_data{T}, p::Int)::Nothing where {T}
    _slot_copy!(ld, ld.exception_bin + 1, p + 1)
    ld.exception_term = ld.exception_bin
    return nothing
end

# PORT: pl-attvar.c restore_wakeup
# DIVERGES: `p` is a position on the local stack (term reference `p`, slot `p + 1`), where upstream's is
# a pointer; the head and tail are their PERMANENT cells (see `saveWakeup`).
"Make the wakeup list saved at position `p` the list again (pl-attvar.c)."
function restore_wakeup(ld::PL_local_data{T}, p::Int)::Nothing where {T}
    h = _attvar_head_cell(ld)
    ld.gstack[h] = ld.slots[p + 1]              # *valTermRef(LD->attvar.head) = p[0]
    ld.gstack[h + 1] = ld.slots[p + 2]          # *valTermRef(LD->attvar.tail) = p[1]
    return nothing
end

# PORT: pl-attvar.c restoreWakeup
# DIVERGES: the saved ball is read at the position above the frame's header (`(Word)(fr+1)`), the
# frame found by its handle; that position is a term reference, so its class is
# `classify_exception(ld, p)`, on the words (f3b-5a), as `restore_exception` reads it.
"""
    restoreWakeup(ld, state)

End a [`saveWakeup`](@ref): the saved exception pending again — unless `state.flags` says to skip
it, or to keep the more urgent of it and one raised since — the saved wakeup list the list again, and
the frame discarded, which undoes the bindings made since (pl-attvar.c).
"""
function restoreWakeup(ld::PL_local_data{T}, state::wakeup_state)::Nothing where {T}
    ld.outofstack = state.outofstack

    if state.fid != 0
        if state.flags != 0
            fr = fliFrameOfFid(ld, state.fid)
            @assert fr != 0 "restoreWakeup(): illegal frame: $(state.fid)"
            p = ld.fliframes[fr].base + SIZEOF_FLIFRAME         # (Word)(fr+1)

            if (state.flags & WAKEUP_STATE_EXCEPTION) != 0
                if (state.flags & WAKEUP_KEEP_URGENT_EXCEPTION) != 0
                    @assert p > 0 "restoreWakeup(): no saved ball at $p"   # (0: EXCEPT_NONE)
                    if classify_exception(ld, p) >=                     # classify_exception_p(p)
                        classify_exception(ld, ld.exception_term)
                        restore_exception(ld, p)
                    end
                elseif (state.flags & WAKEUP_STATE_SKIP_EXCEPTION) == 0
                    restore_exception(ld, p)
                end
                p += 1
            end
            if (state.flags & WAKEUP_STATE_WAKEUP) != 0
                restore_wakeup(ld, p)
            end
        end

        PL_discard_foreign_frame(ld, state.fid)
        updateAlerted(ld)
    end
    return nothing
end

# PORT: pl-attvar.h varBindConst as _bind_const!
# DIVERGES: positions, 1-based, and `gTop` the last cell in use, so upstream's `p < mark_bar` is
# `p <= mark_bar` (as `Trail!`); only global cells (a frame slot is never bound: no unbound slot).
"Bind the unbound cell at global position `p` to word `c`, trailed below `mark_bar` (pl-attvar.h)."
@inline function _bind_const!(ld::PL_local_data, p::Int, c::word)::Nothing
    ld.gstack[p] = c                                # *p = (c)
    p <= ld.mark_bar && push!(ld.trail, _trail_addr(p, TRAIL_GLOBAL))   # trail_ptr(p)
    return nothing
end

# PORT: pl-attvar.h bindConst
# DIVERGES: on a global POSITION (as `_bind_const!`); returns nothing, where upstream returns
# `bind_attvar_const`'s false when the global stack cannot grow (no limit on that path here, as
# `_bind_const!`). Its callers since AV1: the `bindConst` sites whose test admits an attributed variable
# (`canBind`) — H_RFUNCTOR, H_RLIST, H_LIST_FF (src/pl-wam.jl), `h_const` (`_unify_const_loc`,
# `_h_const_cell!`) and `PL_unify_atomic`; since AV1b (audit D-0150 item 1) `PL_unify_list`,
# `PL_unify_functor`, `PL_unify_compound`, `unify_int64_ex` (src/pl-fli.jl), `PL_unify_number`'s `canBind`
# branch (src/pl-gmp.jl) and compare/3's order (src/pl-prims.jl). The other `bindConst` sites still call
# `_bind_const!` behind an `isVar`-only test until the step that gives them their attributed-variable
# branch (the census, evidence/av/av1_census.tsv). Since AV3 an attributed variable is bound by
# `bind_attvar_const` (its false, the global overflow, is raised by `ensureGlobalSpace` and not read
# here, as the unbound branch's); until AV3 it was refused (a `NotPortedError` naming AV3, D-0150
# item 3).
"Bind the cell at global position `p` — unbound, or an attributed variable — to word `c` (pl-attvar.h)."
@inline function bindConst(ld::PL_local_data, p::Int, c::word)::Nothing
    if isVar(ld.gstack[p])                          # if ( isVar(*p) )
        _bind_const!(ld, p, c)                      #   return varBindConst(p, c);
    else
        bind_attvar_const(ld, p, c)                 # else return bind_attvar_const(p, c);
    end
    return nothing
end

# ── the binding (AV3): assignment and the wakeup list ───────────────────────────────────────────
# The list (AV1; audit D-0122 Q1 (a)): upstream's `LD->attvar.head`/`tail` are local-stack cells; here
# each term reference points at a PERMANENT global cell — the head's `_attvar_head_cell(ld)`, the tail's
# the cell after it (asserted, src/pl-setup.jl) — so `*valTermRef(head)` is that cell, "empty" is the
# cell unbound (0), `setVar` writes 0, and every `TrailAssignment` of them pushes (the cells lie below
# every `mark_bar`).

# ORIGINAL (AV3): upstream's `valTermRef(LD->attvar.head)` — the head's PERMANENT cell (the tail's +1).
"The global position of the wakeup list's head cell (pl-attvar.c `valTermRef(LD->attvar.head)`)."
@inline _attvar_head_cell(ld::PL_local_data)::Int = unRef(ld.slots[ld.attvar_head + 1])

# ORIGINAL (AV3): pl-attvar.c's `FUNCTOR_wakeup3` — the functor word of `wakeup/3` in the engine's table.
"The functor word of `wakeup/3` (pl-attvar.c `FUNCTOR_wakeup3`)."
@inline _functor_wakeup3(ld::PL_local_data{T}) where {T} =
    lookupFunctorDef(ld.functors, _atom_word!(ld, mk_sym(T, :wakeup)), 3)

# PORT: pl-attvar.c registerWakeup
# DIVERGES: positions; `name` is the attribute-list cell (`valPAttVar(*av)`), `vw` the WORD the value's
# cell gets (`needsRef(*value) ? makeRefG(value) : *value`, computed once by `assignAttVar`: a side word
# becomes ONE value-table entry); the four cells from `allocGlobalCells!` (`gTop += 4`), allocated before
# they are written; no `gMax`/`tMax` assert (the stacks grow on demand); the tail's `deRef2` is
# `_deref_loc` (the tail references the last `wakeup/3`'s closing `[]`).
"Append `wakeup(Attribute, Value, [])` to the wakeup list, a trailed assignment; the first sets `ALERT_WAKEUP` (pl-attvar.c)."
function registerWakeup(ld::PL_local_data{T}, name::Int, vw::word)::Nothing where {T}
    h = _attvar_head_cell(ld)
    tail = h + 1                                            # Word tail = valTermRef(LD->attvar.tail)

    wake = allocGlobalCells!(ld, 4)                         # wake = gTop; gTop += 4
    ld.gstack[wake] = _functor_wakeup3(ld)                  # wake[0] = FUNCTOR_wakeup3
    nw = ld.gstack[name]
    ld.gstack[wake + 1] = needsRef(nw) ? makeRefG(name) : nw    # wake[1] = needsRef(*name) ? … : *name
    ld.gstack[wake + 2] = vw                                # wake[2] = needsRef(*value) ? … : *value
    ld.gstack[wake + 3] = ld.atom_nil_w                     # wake[3] = ATOM_nil

    if ld.gstack[tail] != 0                                 # if ( *tail ): non-empty list
        _, _, t = _deref_loc(ld, tail)                      #   deRef2(tail, t)
        TrailAssignment!(ld, t)                             #   TrailAssignment(t)
        ld.gstack[t] = consPtr(wake, TAG_COMPOUND | STG_GLOBAL)  # *t = consPtr(wake, TAG_COMPOUND|…)
        TrailAssignment!(ld, tail)                          #   TrailAssignment(tail)
        ld.gstack[tail] = makeRefG(wake + 3)                #   *tail = makeRefG(wake+3)
    else                                                    # else: empty list
        @assert isVar(ld.gstack[h]) "registerWakeup: the wakeup list's head is bound, its tail empty"
        TrailAssignment!(ld, h)                             #   TrailAssignment(head)
        ld.gstack[h] = consPtr(wake, TAG_COMPOUND | STG_GLOBAL)  # *head = consPtr(wake, …)
        TrailAssignment!(ld, tail)                          #   TrailAssignment(tail)
        ld.gstack[tail] = makeRefG(wake + 3)                #   *tail = makeRefG(wake+3)
        ld.alerted |= ALERT_WAKEUP                          #   LD->alerted |= ALERT_WAKEUP
    end
    return nothing
end

# PORT: pl-attvar.c assignAttVar
# DIVERGES: positions; `value` the DEREFERENCED location `(k, w, p)` (upstream's `Word`, never a
# reference) — an attributed variable (`DU_ATTVAR`, at `p`), an atom or compound word, or a value word
# (a slot's side word: its value's own word, `_link_val_loc!`). The value's cell word is computed ONCE
# and stored in both `wake[2]` and `*av` (upstream reads `*value` twice; a side word would otherwise
# become two value-table entries). Two attributed variables: the NEWER (higher) is bound to the older,
# as upstream's `value > av` swap (the design's risk 4). No `gMax`/`tMax` assert (see `registerWakeup`);
# no CHK_SECURE `on_attvar_chain` (AV9).
"Bind the attributed variable at global position `av` to `value` and register its wakeup (pl-attvar.c)."
function assignAttVar(
    ld::PL_local_data{T}, av::Int, value::Tuple{UInt8, word, Int}
)::Nothing where {T}
    @assert isAttVar(ld.gstack[av]) "assignAttVar: no attributed variable at global cell $av"
    k, _, vp = value
    @assert k != DU_CELL "assignAttVar: the value is an unbound cell"

    if k == DU_ATTVAR                                       # if ( isAttVar(*value) )
        if vp > av                                          #   if ( value > av ): swap
            av, vp = vp, av
            value = (DU_ATTVAR, ld.gstack[vp], vp)
        elseif av == vp                                     #   else if ( av == value )
            return nothing                                  #     return
        end
    end

    vw = _link_val_loc!(ld, value)                          # (*value, or makeRefG(value) for an attvar)
    a = valPtr(ld.gstack[av])                               # a = valPAttVar(*av)
    registerWakeup(ld, a, vw)                               # registerWakeup(a, value)

    TrailAssignment!(ld, av)                                # TrailAssignment(av)
    ld.gstack[av] = vw                                      # *av = makeRefG(value) (two attvars) or *value
    return nothing
end

# PORT: pl-attvar.c bind_attvar_const
# DIVERGES: `p` a global position; `c` a word a global cell stores, never an attributed variable's;
# `ensureGlobalSpace` raises the overflow itself and nothing moves (no `PushPtr`/`PopPtr`: positions
# survive a growth), so upstream's `hasGlobalSpace(0)` test before it is folded into it.
"Bind the attributed variable at global position `p` to word `c`; false when the global stack is full (pl-attvar.c)."
function bind_attvar_const(ld::PL_local_data, p::Int, c::word)::Bool
    ensureGlobalSpace(ld, 0) || return false                # if ( !hasGlobalSpace(0) ) … ensureGlobalSpace
    @assert !isVar(c) && !isRef(c) && !isAttVar(c) "bind_attvar_const: word $(repr(c)) is not a constant"  # assert(!isRef(*value))
    assignAttVar(ld, p, (isTaggedIntW(c) || _is_vword(c) ? DU_VALUE : DU_WORD, c, 0))  # assignAttVar(p, &c)
    return true
end

# ── the store (AV2): an attributed variable's attribute list ─────────────────────────────────────
# The layout (pl-attvar.c's header comment): a LINK cell on the chain (`register_attvar`), the attvar
# cell `consPtr(&list, TAG_ATTVAR|STG_GLOBAL)`, the attribute-list cell, then `att(Name, Value, Rest)`
# compounds ending in `[]`. The variable made attributed is bound to a reference to the attvar cell, so
# from put_attr/3 on its identity is the NEW, higher cell (the design's risk 4; rows av18, AV5).

# ORIGINAL (AV2): pl-attvar.c's `FUNCTOR_att3` — the functor word of `att/3` in the engine's table.
"The functor word of `att/3` (pl-attvar.c `FUNCTOR_att3`)."
@inline _functor_att3(ld::PL_local_data{T}) where {T} =
    lookupFunctorDef(ld.functors, _atom_word!(ld, mk_sym(T, :att)), 3)

# ORIGINAL (AV2): upstream's `linkValI(p)` for a DEREFERENCED location `(k, w, p)` (`_deref_loc`), as
# `_slot_link_loc!` (src/pl-fli.jl) stores one into a slot: the WORD a global cell stores — a cell that
# `needsRef` (unbound, or an attributed variable) gives its reference `makeRefG(p)`, any other word
# itself, a slot's side word its value's own word (`_value_word!`, f3-1).
"The word a global cell stores for the dereferenced location `(k, w, p)` (pl-inline.h `linkValI`)."
@inline function _link_val_loc!(
    ld::PL_local_data, (k, w, p)::Tuple{UInt8, word, Int}
)::word
    (k == DU_CELL || k == DU_ATTVAR) && return makeRefG(p)  # needsRef(w): makeRefG(p)
    return _value_word!(ld, w)                              # else w
end

# PORT: pl-attvar.c PL_get_attr
# DIVERGES: one function for upstream's two — this LD form and pl-fli.c's API stub, which only validates
# its term references (no `valid_term_t` here); on the WORDS (`_deref_loc`); `a`'s slot gets the
# reference to the attribute-list cell (`valPAttVar`: the attvar word's pointer, `valPtr`).
"Put a reference to the attribute list of the attributed variable `t` holds into `a`; false when `t` holds none (pl-attvar.c)."
function PL_get_attr(ld::PL_local_data{T}, t::term_t, a::term_t)::Bool where {T}
    k, w, _ = _deref_loc(ld, -(t + 1))                      # Word p = valTermRef(t); deRef(p)
    if k == DU_ATTVAR                                       # if ( isAttVar(*p) )
        ld.slots[a + 1] = makeRefG(valPtr(w))               #   *valTermRef(a) = makeRefG(valPAttVar(*p))
        return true
    end
    return false
end

# PORT: pl-attvar.c link_attvar
# DIVERGES: positions; the link cell from `allocGlobalCells!` (upstream's `gTop++`: the stack grows on
# demand, src/pl-alloc.jl); returns the position after it, where the attvar cell goes.
"A new link cell made the newest of the attributed variables' chain; the position after it (pl-attvar.c)."
function link_attvar(ld::PL_local_data)::Int
    gp = allocGlobalCells!(ld, 1)                           # Word gp = gTop++
    register_attvar(ld, gp)                                 # register_attvar(gp)
    return gp + 1                                           # return gp+1
end

# PORT: pl-attvar.c make_new_attvar
# DIVERGES: positions; the two cells from `allocGlobalCells!` (`gTop += 2`, contiguous with the link
# cell), allocated BEFORE they are written (the allocator clears them); no `gMax`/`tMax` assert (the
# stacks grow on demand); `Trail(p, makeRefG(gp))` is `_bind_const!` (`p` an unbound global cell: the
# slot rule). NOT PORTED: `trail_new_attvar` — its test, `call_residue_vars_count`, is 0 until AV9
# (call_residue_vars/2), so it pushes nothing.
"Turn the unbound global cell `p` into a reference to a new attributed variable with no attributes (pl-attvar.c)."
function make_new_attvar(ld::PL_local_data, p::Int)::Nothing
    gp = link_attvar(ld)                                    # gp = link_attvar()
    allocGlobalCells!(ld, 2)                                # gTop += 2
    ld.gstack[gp + 1] = ld.atom_nil_w                       # gp[1] = ATOM_nil
    ld.gstack[gp] = consPtr(gp + 1, TAG_ATTVAR | STG_GLOBAL)    # gp[0] = consPtr(&gp[1], TAG_ATTVAR|…)
    _bind_const!(ld, p, makeRefG(gp))                       # Trail(p, makeRefG(gp)): make_new_attvar
    return nothing
end

# PORT: pl-attvar.c put_new_attvar
# DIVERGES: positions; `name` an atom word; `value` the DEREFERENCED location `(k, w, q)` (upstream's
# `Word`, dereferenced by put_attr/3), so `linkValI(value)` is `_link_val_loc!`; the six cells from
# `allocGlobalCells!` (`gTop += 6`), allocated before they are written; no `gMax`/`tMax` assert;
# `Trail(p, …)` is `_bind_const!`. NOT PORTED: `trail_new_attvar` (AV9, see `make_new_attvar`).
"Turn the unbound global cell `p` into a reference to a new attributed variable whose one attribute is `name` = `value` (pl-attvar.c)."
function put_new_attvar(
    ld::PL_local_data{T}, p::Int, name::word, value::Tuple{UInt8, word, Int}
)::Nothing where {T}
    gp = link_attvar(ld)                                    # gp = link_attvar()
    allocGlobalCells!(ld, 6)                                # gTop += 6
    at = gp + 1                                             # at = &gp[1]; setVar(*at): a fresh cell
    ld.gstack[gp] = consPtr(at, TAG_ATTVAR | STG_GLOBAL)    # gp[0] = consPtr(&gp[1], TAG_ATTVAR|STG_GLOBAL)

    ld.gstack[at + 1] = _functor_att3(ld)                   # at[1] = FUNCTOR_att3
    ld.gstack[at + 2] = name                                # at[2] = name
    ld.gstack[at + 3] = _link_val_loc!(ld, value)           # at[3] = linkValI(value)
    ld.gstack[at + 4] = ld.atom_nil_w                       # at[4] = ATOM_nil
    ld.gstack[at] = consPtr(at + 1, TAG_COMPOUND | STG_GLOBAL)  # at[0] = consPtr(&at[1], TAG_COMPOUND|…)

    _bind_const!(ld, p, makeRefG(gp))                       # Trail(p, makeRefG(gp)): put_new_attvar
    return nothing
end

# PORT: pl-attvar.c find_attr
# DIVERGES: positions; returns `(found, vp)` where upstream returns `found` and writes `vp`: the value's
# cell when found, else the position of the list's closing `[]` — or 0 (upstream's NULL) for a list
# that is not `att/3` cells ending in `[]`. `*n == name` on the dereferenced word (an unbound cell's
# word is 0, never an atom's).
"""
    find_attr(ld, av, name) -> (found, vp)

Find the value cell of attribute `name` (an atom word) of the attributed variable at global position
`av` (pl-attvar.c).
"""
function find_attr(ld::PL_local_data{T}, av::Int, name::word)::Tuple{Bool, Int} where {T}
    k, w, _ = _deref_loc(ld, av)                            # deRef(av)
    @assert k == DU_ATTVAR "find_attr: no attributed variable at global cell $av"   # assert(isAttVar(*av))
    l = valPtr(w)                                           # l = valPAttVar(*av)
    att3 = _functor_att3(ld)

    while true
        kl, wl, l = _deref_loc(ld, l)                       # deRef(l)

        if kl == DU_WORD && wl == ld.atom_nil_w             # if ( isNil(*l) )
            return (false, l)                               #   *vp = l; return false
        elseif kl == DU_WORD && _is_gcompound(wl)           # else if ( isTerm(*l) )
            f = valPtr(wl)                                  #   Functor f = valueTerm(*l)
            if ld.gstack[f] == att3                         #   if ( f->definition == FUNCTOR_att3 )
                if _deref_loc(ld, f + 1)[2] == name         #     deRef2(&f->arguments[0], n); if ( *n == name )
                    return (true, f + 2)                    #       *vp = &f->arguments[1]; return true
                else
                    l = f + 3                               #     else l = &f->arguments[2]
                end
            else
                return (false, 0)                           #   bad attribute list: *vp = NULL
            end
        else
            return (false, 0)                               # bad attribute list: *vp = NULL
        end
    end
end

# PORT: pl-attvar.c put_att_value
# DIVERGES: positions; the four cells from `allocGlobalCells!` (`gTop += 4`), allocated before they are
# written; `value` dereferenced, as `put_new_attvar`'s.
"Append `att(name, value, [])` at the list's closing `[]` cell `vp`, a trailed assignment (pl-attvar.c)."
function put_att_value(
    ld::PL_local_data{T}, vp::Int, name::word, value::Tuple{UInt8, word, Int}
)::Nothing where {T}
    at = allocGlobalCells!(ld, 4)                           # Word at = gTop; gTop += 4
    ld.gstack[at] = _functor_att3(ld)                       # at[0] = FUNCTOR_att3
    ld.gstack[at + 1] = name                                # at[1] = name
    ld.gstack[at + 2] = _link_val_loc!(ld, value)           # at[2] = linkValI(value)
    ld.gstack[at + 3] = ld.atom_nil_w                       # at[3] = ATOM_nil

    TrailAssignment!(ld, vp)                                # TrailAssignment(vp): put_att_value
    ld.gstack[vp] = consPtr(at, TAG_COMPOUND | STG_GLOBAL)  # *vp = consPtr(at, TAG_COMPOUND|STG_GLOBAL)
    return nothing
end

# PORT: pl-attvar.c put_attr
# DIVERGES: positions, `name` an atom word, `value` dereferenced (see `put_new_attvar`); no `gMax`/`tMax`
# assert (the stacks grow on demand).
"Set attribute `name` of the attributed variable at `av` to `value` — replaced in place, trailed, or appended; false for a bad attribute list (pl-attvar.c)."
function put_attr(
    ld::PL_local_data{T}, av::Int, name::word, value::Tuple{UInt8, word, Int}
)::Bool where {T}
    found, vp = find_attr(ld, av, name)
    if found                                                # if ( find_attr(av, name, &vp) )
        TrailAssignment!(ld, vp)                            #   TrailAssignment(vp): put_attr, replaced
        ld.gstack[vp] = _link_val_loc!(ld, value)           #   *vp = linkValI(value)
    elseif vp != 0                                          # else if ( vp )
        put_att_value(ld, vp, name, value)
    else
        return false                                        # Bad attribute list
    end
    return true
end

# PORT: pl-attvar.c get_attr
# DIVERGES: `l` a global position, `name` an atom word; the result a Bool (`unify_ptrs_cells`: no
# `ALLOW_GC|ALLOW_SHIFT`). A list that is not `att/3` cells fails here, as upstream (no nil test: `[]`
# is no term).
"Unify `value` with attribute `name` of the attribute list at `l`; false when there is none (pl-attvar.c)."
function get_attr(ld::PL_local_data{T}, l::Int, name::word, value::term_t)::Bool where {T}
    att3 = _functor_att3(ld)
    while true
        kl, wl, l = _deref_loc(ld, l)                       # deRef(l)

        if kl == DU_WORD && _is_gcompound(wl)               # if ( isTerm(*l) )
            f = valPtr(wl)
            if ld.gstack[f] == att3                         #   if ( f->definition == FUNCTOR_att3 )
                if _deref_loc(ld, f + 1)[2] == name         #     if ( *n == name )
                    return unify_ptrs_cells(ld, -(value + 1), f + 2)   # unify_ptrs(valTermRef(value), &f->arguments[1], …)
                else
                    l = f + 3                               #     else l = &f->arguments[2]
                end
            else
                return false                                #   fail
            end
        else
            return false                                    # fail
        end
    end
end

# PORT: pl-attvar.c del_attr
# DIVERGES: positions, `name` an atom word. `*prev = f->arguments[2]` copies the cell's own word, as
# upstream (a reference, `[]` or the next compound's word).
"Remove attribute `name` from the attributed variable at `av` by a trailed assignment; false when it has none (pl-attvar.c)."
function del_attr(ld::PL_local_data{T}, av::Int, name::word)::Bool where {T}
    k, w, _ = _deref_loc(ld, av)                            # deRef(av)
    @assert k == DU_ATTVAR "del_attr: no attributed variable at global cell $av"    # assert(isAttVar(*av))
    kl, wl, l = _deref_loc(ld, valPtr(w))                   # l = valPAttVar(*av); deRef(l)
    prev = l                                                # prev = l
    att3 = _functor_att3(ld)

    while true
        if kl == DU_WORD && wl == ld.atom_nil_w             # if ( isNil(*l) )
            return false                                    #   fail
        elseif kl == DU_WORD && _is_gcompound(wl)           # else if ( isTerm(*l) )
            f = valPtr(wl)
            if ld.gstack[f] == att3                         #   if ( f->definition == FUNCTOR_att3 )
                if _deref_loc(ld, f + 1)[2] == name         #     if ( *n == name )
                    TrailAssignment!(ld, prev)              #       TrailAssignment(prev): del_attr
                    ld.gstack[prev] = ld.gstack[f + 3]      #       *prev = f->arguments[2]
                    return true                             #       succeed
                else
                    kl, wl, l = _deref_loc(ld, f + 3)       #     l = &f->arguments[2]; deRef(l)
                    prev = l                                #     prev = l
                end
            else
                return false                                #   fail
            end
        else
            return false                                    # fail
        end
    end
end

# ── the predicates (AV2; pl-attvar.c's PRED_IMPLs, the `t0, ac, ctx` convention) ─────────────────

# PORT: pl-attvar.c attvar as pl_attvar1_va
"attvar/1 (pl-attvar.c): the argument is an attributed variable."
function pl_attvar1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    k, _, _ = _deref_loc(ld, -(A1 + 1))                     # Word p = valTermRef(t); deRef(p)
    return k == DU_ATTVAR ? FTRUE : FFALSE                  # if ( isAttVar(*p) ) succeed: attvar/1
end

# PORT: pl-attvar.c get_attrs as pl_get_attrs2_va
"get_attrs/2 (pl-attvar.c): the attribute list `att(Name, Value, More)` of an attributed variable."
function pl_get_attrs2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    al = PL_new_term_ref(ld)                                # term_t al = PL_new_term_ref()

    PL_get_attr(ld, A1, al) || return FFALSE                # if ( !PL_get_attr(A1, al) ) fail
    return PL_unify(ld, al, A2) ? FTRUE : FFALSE            # return PL_unify(al, A2)
end

# PORT: pl-attvar.c get_attr as pl_get_attr3_va
"get_attr/3 (pl-attvar.c): `+Var, +Name, -Value` — the value of attribute `Name`; fails when there is none."
function pl_get_attr3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2, A3 = PL__t0, PL__t0 + 1, PL__t0 + 2
    k, w, _ = _deref_loc(ld, -(A1 + 1))                     # a1 = valTermRef(A1); deRef(a1)
    if k == DU_ATTVAR                                       # if ( isAttVar(*a1) )
        p = valPtr(w)                                       #   Word p = valPAttVar(*a1)
        name = PL_get_atom_ex(ld, A2)                       #   if ( !PL_get_atom_ex(A2, &name) ) fail
        name === nothing && return FFALSE
        return get_attr(ld, p, _atom_word!(ld, name), A3) ? FTRUE : FFALSE
    end
    return FFALSE
end

# PORT: pl-attvar.c put_attr as pl_put_attr3_va
# DIVERGES: `ensureGlobalSpace(1, ALLOW_GC)` is the kernel's limit check (src/pl-alloc.jl: no
# `BIND_GLOBAL_SPACE` margin, the stacks grow on demand). Upstream's `isVar(*vp) && vp >= lBase` branch
# (a value variable on the local stack, globalized with `LTrail`) cannot arise: no unbound variable lives
# on the local stack here (the slot rule, src/pl-prims.jl), so the value is a global cell already.
"put_attr/3 (pl-attvar.c): `+Var, +Name, +Value` — set attribute `Name`, making `Var` attributed."
function pl_put_attr3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2, A3 = PL__t0, PL__t0 + 1, PL__t0 + 2
    ensureGlobalSpace(ld, 1) || return FFALSE               # 0 means enough for attvars

    a = PL_get_atom_ex(ld, A2)                              # if ( !PL_get_atom_ex(A2, &name) ) fail
    a === nothing && return FFALSE
    name = _atom_word!(ld, a)

    vp = _deref_loc(ld, -(A3 + 1))                          # vp = valTermRef(A3); deRef(vp)

    k, _, av = _deref_loc(ld, -(A1 + 1))                    # av = valTermRef(A1); deRef(av)

    if k == DU_CELL                                         # if ( isVar(*av) ): put_attr/3
        put_new_attvar(ld, av, name, vp)
        return FTRUE
    elseif k == DU_ATTVAR                                   # else if ( isAttVar(*av) )
        put_attr(ld, av, name, vp) && return FTRUE
        return if PL_error(
            ld, "put_attr", 3, "invalid attribute structure", ERR_TYPE,
            mk_sym(T, :attributes), A1
        )
            FTRUE
        else
            FFALSE
        end
    else
        return PL_error(ld, "put_attr", 3, "", ERR_UNINSTANTIATION, 1, A1) ? FTRUE : FFALSE
    end
end

# PORT: pl-attvar.c put_attrs as pl_put_attrs2_va
# DIVERGES: `ensureGlobalSpace(0, ALLOW_GC)` as put_attr/3's.
"put_attrs/2 (pl-attvar.c): `+Var, +Atts` — replace the whole attribute list, making `Var` attributed."
function pl_put_attrs2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    ensureGlobalSpace(ld, 0) || return FFALSE               # 0 means enough for attvars

    k, w, av = _deref_loc(ld, -(A1 + 1))                    # av = valTermRef(A1); deRef(av)

    if k == DU_CELL                                         # if ( isVar(*av) ): put_attrs/2
        make_new_attvar(ld, av)                             #   make_new_attvar(av)
        k, w, av = _deref_loc(ld, av)                       #   deRef(av)
    elseif k != DU_ATTVAR                                   # else if ( !isAttVar(*av) )
        return PL_error(ld, "put_attrs", 2, "", ERR_UNINSTANTIATION, 1, A1) ? FTRUE : FFALSE
    end

    vp = valPtr(w)                                          # vp = valPAttVar(*av)
    TrailAssignment!(ld, vp)                                # TrailAssignment(vp): put_attrs
    ld.gstack[vp] = _link_val_loc!(ld, _deref_loc(ld, -(A2 + 1)))   # *vp = linkValI(valTermRef(A2))
    return FTRUE
end

# PORT: pl-attvar.c del_attr2 as pl_del_attr2_va
# DIVERGES: `ensureGlobalSpace(0, ALLOW_GC)` as put_attr/3's.
"del_attr/2 (pl-attvar.c): `+Var, +Name` — remove attribute `Name`; the last one gone, `Var` is a plain variable again. Always true."
function pl_del_attr2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    ensureGlobalSpace(ld, 0) || return FFALSE

    a = PL_get_atom_ex(ld, A2)                              # if ( !PL_get_atom_ex(A2, &name) ) return false
    a === nothing && return FFALSE
    name = _atom_word!(ld, a)

    k, _, av = _deref_loc(ld, -(A1 + 1))                    # av = valTermRef(A1); deRef(av)

    if k == DU_ATTVAR                                       # if ( isAttVar(*av) )
        if del_attr(ld, av, name)                           #   if ( del_attr(av, name) )
            kl, wl, _ = _deref_loc(ld, valPtr(ld.gstack[av]))   # Word l = valPAttVar(*av); deRef(l)
            if kl == DU_WORD && wl == ld.atom_nil_w         #     if ( isNil(*l) )
                TrailAssignment!(ld, av)                    #       TrailAssignment(av): del_attr/2
                ld.gstack[av] = word(0)                     #       setVar(*av): del_attr/2
            end
        end
    end
    return FTRUE
end

# PORT: pl-attvar.c del_attrs as pl_del_attrs1_va
# DIVERGES: `ensureGlobalSpace(0, ALLOW_GC)` as put_attr/3's.
"del_attrs/1 (pl-attvar.c): `+Var` — remove every attribute; `Var` is a plain variable again. Always true."
function pl_del_attrs1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    ensureGlobalSpace(ld, 0) || return FFALSE

    k, _, av = _deref_loc(ld, -(A1 + 1))                    # av = valTermRef(A1); deRef(av)

    if k == DU_ATTVAR                                       # if ( isAttVar(*av) )
        TrailAssignment!(ld, av)                            #   TrailAssignment(av): del_attrs/1
        ld.gstack[av] = word(0)                             #   setVar(*av): del_attrs/1
    end
    return FTRUE
end

# PORT: pl-attvar.c attv_unify as pl_attv_unify2_va
# DIVERGES: at the pin cbf4e189 plus upstream's fix d4621369 (the marker line is port_check's strict form).
# `ensureStackSpace(0, 0)` is `ensureGlobalSpace(ld, 0)` (one limit over the three stacks, src/pl-alloc.jl); `linkValG` is `linkValI` here (`_link_val_loc!`): no unbound variable lives on the
# local stack (the slot rule), so there is nothing to globalize. `PL_unify` of a plain variable with an
# attributed one reaches `unify_simple_cells`, whose attributed-variable branches bind with a wakeup
# (`assignAttVar`, AV3). Upstream d4621369 ("'$attv_unify'(X,X) on an attributed variable created a
# self-reference"): `v == av` returns true before the link, and the link word `w` is computed BEFORE `av` is
# dereferenced again (`linkValG` "may shift the stacks"). Here `_link_val_loc!` only reads cells and may add a
# value-table entry (`_side_value_word!`, src/pl-inline.jl): global-stack positions are indices, so `av`
# cannot be invalidated; the re-dereference is kept in upstream's order all the same.
"`\$attv_unify/2` (pl-attvar.c): bind an attributed variable to a value WITHOUT a wakeup; otherwise plain unification."
function pl_attv_unify2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    ensureGlobalSpace(ld, 0) || return FFALSE

    k, _, av = _deref_loc(ld, -(A1 + 1))                    # Word av = valTermRef(A1); deRef(av)

    if k == DU_ATTVAR                                       # if ( isAttVar(*av) )
        v = _deref_loc(ld, -(A2 + 1))                       #   Word v = valTermRef(A2); deRef(v)
        v[3] == av && return FTRUE                          #   if ( v == av ) return true: '$attv_unify'(X,X)
        w = _link_val_loc!(ld, v)                           #   word w = linkValG(v): may shift the stacks
        _, _, av = _deref_loc(ld, -(A1 + 1))                #   av = valTermRef(A1); deRef(av)
        TrailAssignment!(ld, av)                            #   TrailAssignment(av): $attv_unify
        ld.gstack[av] = w                                   #   *av = w
        return FTRUE
    end
    return PL_unify(ld, A1, A2) ? FTRUE : FFALSE            # return PL_unify(A1, A2)
end

# PORT: pl-attvar.c BeginPredDefs as PL_predicates_from_attvar
# DIVERGES: the entries ported since AV2, in upstream's order; `PRED_DEF` ors in `PL_FA_VARARGS`. NOT PORTED: `$freeze`
# (AV7), `$eval_when_condition` and `$suspend` (AV8), and the O_CALL_RESIDUE entries (AV9).
"pl-attvar.c's registration table (`BeginPredDefs(attvar)`): the ported entries."
const PL_predicates_from_attvar = (
    PL_extension("attvar", 1, pl_attvar1_va, PL_FA_VARARGS),
    PL_extension("put_attr", 3, pl_put_attr3_va, PL_FA_VARARGS),
    PL_extension("get_attr", 3, pl_get_attr3_va, PL_FA_VARARGS),
    PL_extension("del_attr", 2, pl_del_attr2_va, PL_FA_VARARGS),
    PL_extension("del_attrs", 1, pl_del_attrs1_va, PL_FA_VARARGS),
    PL_extension("get_attrs", 2, pl_get_attrs2_va, PL_FA_VARARGS),
    PL_extension("put_attrs", 2, pl_put_attrs2_va, PL_FA_VARARGS),
    PL_extension("\$attv_unify", 2, pl_attv_unify2_va, PL_FA_VARARGS)
)
