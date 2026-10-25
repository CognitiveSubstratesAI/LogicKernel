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
# since AV1, `bindConst` itself (its attributed-variable branch raises until AV3).
# `findCatcher` (src/pl-wam.jl) is their first caller: while it unifies a ball with the catchers no
# exception is pending, so an error that unification raises (the occurs check under
# `occurs_check = error`) is raised, and becomes the ball.
#
# NOT PORTED: the rest of pl-attvar.c, the AV step (since L1, SWI's term layout) — attributed variables
# themselves (`put_attr/3`, `get_attr/3`, `del_attr/2`, the wakeup list and `foreignWakeup`,
# `freeze/2`'s support, `copy_term/3`'s attribute goals) and `wakeup_state_exception`. The wakeup
# list these two functions also save is therefore always empty here.

# PORT: pl-attvar.c saveWakeup
# DIVERGES: returns the state, or `nothing` for upstream's false (no space for the foreign frame). The
# ball's slot word is copied as upstream copies the cell (f3b-1: `_slot_copy!`, a side value with it;
# until then the ball was read as a term and stored as a slot's side value).
# NOT PORTED: the wakeup list (`LD->attvar.head`/`tail`, `WAKEUP_STATE_WAKEUP`): no attributed
# variables, so the list is always empty.
"""
    saveWakeup(ld, forceframe) -> wakeup_state, or nothing

Set the pending exception aside in a foreign frame of its own and clear it (pl-attvar.c); with none
pending, and `forceframe` false, no frame is opened. Nested as `PL_open_foreign_frame` is, and ended
by [`restoreWakeup`](@ref).
"""
function saveWakeup(
    ld::PL_local_data{T}, forceframe::Bool
)::Union{Nothing, wakeup_state} where {T}
    outofstack = ld.outofstack
    if ld.exception_term != 0 || forceframe
        fid = PL_open_foreign_frame(ld)
        fid == 0 && return nothing              # no space!
        flags = UInt32(0)
        if ld.exception_term != 0
            flags |= WAKEUP_STATE_EXCEPTION
            s = PL_new_term_ref(ld)
            _slot_copy!(ld, s + 1, ld.exception_term + 1)   # *valTermRef(s) = *valTermRef(exception_term)
            ld.exception_term = 0
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

# PORT: pl-attvar.c restoreWakeup
# DIVERGES: the saved ball is read at the position above the frame's header (`(Word)(fr+1)`), the
# frame found by its handle; that position is a term reference, so its class is
# `classify_exception(ld, p)`, on the words (f3b-5a), as `restore_exception` reads it. NOT PORTED:
# `restore_wakeup` (see `saveWakeup`) and `updateAlerted` (no `LD->alerted`).
"""
    restoreWakeup(ld, state)

End a [`saveWakeup`](@ref): the saved exception pending again — unless `state.flags` says to skip
it, or to keep the more urgent of it and one raised since — and the frame discarded, which undoes
the bindings made since (pl-attvar.c).
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
            end
        end

        PL_discard_foreign_frame(ld, state.fid)
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
# `_h_const_cell!`) and `PL_unify_atomic`; the other `bindConst` sites still call `_bind_const!` behind
# an `isVar`-only test until the step that gives them their attributed-variable branch.
# NOT PORTED: `bind_attvar_const` (AV3, with `assignAttVar` and the wakeup list): until then an
# attributed variable reaching it is REFUSED — a `NotPortedError` naming AV3 (audit D-0150 item 3), never a
# wrong answer; AV2 creates attributed variables, AV3 binds them.
"Bind the cell at global position `p` — unbound, or an attributed variable — to word `c` (pl-attvar.h)."
@inline function bindConst(ld::PL_local_data, p::Int, c::word)::Nothing
    if isVar(ld.gstack[p])                          # if ( isVar(*p) )
        _bind_const!(ld, p, c)                      #   return varBindConst(p, c);
    else
        throw(_bind_attvar_const_error(p, ld.gstack[p]))   # else return bind_attvar_const(p, c);
    end
    return nothing
end

# ORIGINAL (AV1; audit D-0150 item 3): the refusal `bindConst` raises for an attributed variable until AV3
# — a `NotPortedError` (src/pl-comp.jl), the kernel's refusal pattern, grep-able by its step.
"The refusal of binding the attributed variable at global position `p` (word `w`) before AV3."
@noinline _bind_attvar_const_error(p::Int, w::word)::Exception = NotPortedError{Nothing}(
    nothing,
    "bind_attvar_const (pl-attvar.c): bindConst on global cell $p, word $(repr(w)) " *
    "(an attributed variable)",
    "AV3"
)
