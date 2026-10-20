# UPSTREAM: swipl-devel src/pl-attvar.c @ 8e1bc1110be4
# UPSTREAM: swipl-devel src/pl-attvar.h @ 8e1bc1110be4
# CLASS: code
# COPYRIGHT: Copyright (c)  2004-2025, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# PORTED FROM pl-attvar.c, exactly these: `saveWakeup`, `restoreWakeup` and the helper
# `restore_exception` — the SAVE/RESTORE of the pending exception around foreign code that must run
# with none pending. From pl-attvar.h, `varBindConst` (L1c: the VM's `bindConst` of a global cell,
# attributed variables not ported).
# `findCatcher` (src/pl-wam.jl) is their first caller: while it unifies a ball with the catchers no
# exception is pending, so an error that unification raises (the occurs check under
# `occurs_check = error`) is raised, and becomes the ball.
#
# NOT PORTED: the rest of pl-attvar.c, after L1 (SWI's term layout) — attributed variables
# themselves (`put_attr/3`, `get_attr/3`, `del_attr/2`, the wakeup list and `foreignWakeup`,
# `freeze/2`'s support, `copy_term/3`'s attribute goals) and `wakeup_state_exception`. The wakeup
# list these two functions also save is therefore always empty here.

# PORT: pl-attvar.c saveWakeup
# DIVERGES: returns the state, or `nothing` for upstream's false (no space for the foreign frame).
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
            _slot_store_value!(ld, s + 1, slotValue(ld, ld.exception_term + 1))   # a value (L1c)
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
# frame found by its handle. NOT PORTED: `restore_wakeup` (see `saveWakeup`) and `updateAlerted`
# (no `LD->alerted`).
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
                    if classify_exception_p(ld, slotValue(ld, p + 1)) >=
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
