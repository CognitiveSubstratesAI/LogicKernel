# UPSTREAM: swipl-devel src/pl-gc.c @ 18168e629eab
# UPSTREAM: swipl-devel src/pl-incl.h @ 18168e629eab
# CLASS: code
# COPYRIGHT: Copyright (c)  1985-2024, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
# allow-new-artifact: a port of pl-gc.c at the pin (read via git show 18168e62:src/pl-gc.c; the design is in evidence/G1/g1gc6c_handoff.md)
# G1-GC (G1-6c): THE DRIVER of SWI-Prolog's stack garbage collector (pl-gc.c): `garbageCollect` (:4413-4568), the
# space check before it (`gcEnsureSpace` :4355), the VM state at the safe point (`get_vmi_state` :3725,
# `restore_vmi_state` :3800) and the tightness check after it (`tight` :5700, `shiftTightStacks` :5724,
# `clear_unused_stack` :5617). LEAF file: included after pl-gccompact.jl; it calls the phases the other G1-GC
# files hold and owns no phase of its own. `pl_garbage_collect` (pl-gc.jl) calls it with `GC_USER`.
#
# THE KERNEL ORDER OF ONE COLLECTION (the table in pl-gccompact.jl's header; evidence/G1/g1gc4b_handoff.md):
#   gc_stat_start!, the VM state, gcEnsureSpace, blockGC, clear SIG_GC, the mark_bar fix,
#   link_attvars, argument_stack_to_term_refs, gvars_to_term_refs, save_grefs,
#   mark_phase, gc_trail_begin!, tag_trail, gc_trail_phase, collect_phase,
#   restore_grefs, untag_trail, clean_attvar_chain, gc_trail_end!,
#   term_refs_to_gvars, term_refs_to_argument_stack, restore_attvars,
#   the mark_bar restore, unblockGC, `gc.inferences`, trimStacks!, gc_stat_end!, shiftTightStacks!.
# Upstream runs `tag_trail` BEFORE `mark_phase` and `compact_trail` as its own call: the kernel marks first (early
# reset reads the untagged trail) and `gc_trail_phase` is the alien pass + `compact_trail` + counter check (see
# pl-gctrail.jl and pl-gccompact.jl).
#
# THE VM STATE (`vmi_state_of`): the state of a query that is INSIDE the VM (`registers.fr != 0`) is built by
# G1-2b (the callback `vmi_state_of(ld, query_index) -> vm_state`, as `mark_stacks` takes it). The state of the
# other case — no query, or one whose registers hold no frame (upstream's `else` arm, :3779-3786) — is built
# here. A collection that needs the callback and has none DECLINES (`BOOLEX_FALSE`, nothing touched, no
# statistics record): the answer the placeholder gave and upstream's own for a blocked collector.

# PORT: pl-incl.h GROW_TIGHT
"The request of `shiftTightStacks` for a stack that is tight: grow it to the next size (pl-incl.h `GROW_TIGHT`)."
const GROW_TIGHT = 1

# PORT: pl-gc.c get_vmi_state as gc_get_vmi_state
# DIVERGES: (1) the registers are positions and indices (`vm_state`, pl-gcmark.jl); (2) the arm of a query inside
# the VM (`qf->registers.fr != 0`, :3735-3789: the frame, the pc, `setStartOfVMI`, the body-mode `lTop`) is G1-2b's
# `vmi_state_of` callback; without one the answer is `nothing` and `garbageCollect` declines; (3) `state->frame
# = environment_frame` and the argument position are the frame's index and its base position.
"The `vm_state` of the safe point, `nothing` when the query is inside the VM and no `vmi_state_of` was given (pl-gc.c `get_vmi_state`)."
function gc_get_vmi_state(
    ld::PL_local_data{T}, qi::Int, vmi_state_of
)::Union{Nothing, vm_state} where {T}
    if qi != 0 && ld.queries[qi].registers_fr != 0
        vmi_state_of === nothing && return nothing
        return vmi_state_of(ld, qi)::vm_state
    end
    vm = vm_state()
    vm.choice = ld.BFR                              # state->choice = LD->choicepoints
    vm.lSave = ld.lTop                              # state->lSave = lTop
    vm.in_body = false
    vm.adepth = 0
    vm.new_args = 0
    vm.lNext = 0                                    # state->lNext = NULL
    vm.frame = ld.environment_frame                 # state->frame = environment_frame
    vm.pc = 0                                       # state->pc = NULL
    vm.pc_start_vmi = 0
    vm.save_argp = false
    if vm.frame != 0
        vm.argp = argFrameP(ld.frames[vm.frame].base, 0)
    end
    return vm
end

# PORT: pl-gc.c restore_vmi_state as gc_restore_vmi_state
# DIVERGES: `lTop = state->lSave`: lowering goes through `lowerLTop!` (it drops the records above), raising
# (a body-mode state that put `lTop` above the saved value) assigns.
"Put `lTop` back to the value the VM state saved (pl-gc.c `restore_vmi_state`)."
function gc_restore_vmi_state(ld::PL_local_data{T}, vm::vm_state)::Nothing where {T}
    if vm.lSave < ld.lTop
        lowerLTop!(ld, vm.lSave)
    elseif vm.lSave > ld.lTop
        ld.lTop = vm.lSave
    end
    return nothing
end

# ORIGINAL: the number of global-stack values of the nb_ variables `gvars_to_term_refs` turns into term references.
"The number of global-stack values in the table of global variables (what `gvars_to_term_refs` protects)."
function gc_count_gvar_refs(ld::PL_local_data{T})::Int where {T}
    n = 0
    for w in values(ld.gvar_nb_vars)
        _gc_is_global_ref(w) && (n += 1)
    end
    return n
end

# PORT: pl-gc.c gcEnsureSpace
# DIVERGES: (1) `lneeded` is in positions; (2) the global variables: upstream counts `LD->gvar.grefs` (a count the
# kernel keeps as a hint, pl-gcmark.jl `gvars_to_term_refs`), here the larger of it and the real number of global
# values plus the two spare slots `gvars_to_term_refs` asks for; (3) the `attvars` frame and the term references of
# the argument stack are counted as upstream does, plus the frame header; (4) a growth never moves anything, so
# the `rc == false` ("shifted") answer only tells the caller to build the VM state again.
"Make room on the local stack for the term references the collection saves; `BOOLEX_TRUE`, `BOOLEX_FALSE` (grown) or an overflow code (pl-gc.c)."
function gcEnsureSpace(ld::PL_local_data{T}, vm::vm_state)::boolex_t where {T}
    rc = BOOLEX_TRUE
    lneeded = 0
    ngv = max(ld.gvar_grefs, gc_count_gvar_refs(ld))
    if ngv != 0
        lneeded += SIZEOF_FLIFRAME + ngv + 2
    end
    if ld.frozen_bar != 0
        lneeded += 1
    end
    if vm.save_argp
        lneeded += SIZEOF_FLIFRAME + ld.aTop + 1
    end
    if ld.attvar_call_residue_vars_count != 0 && ld.attvar_attvars != 0
        lneeded += SIZEOF_FLIFRAME + count_need_protection_attvars(ld) + 2
    end

    if ld.lTop + lneeded > ld.lMax
        if ld.lTop + lneeded > ld.lMax + ld.local_spare
            gc_restore_vmi_state(ld, vm)
            rc2 = growLocalSpace(ld, lneeded, ALLOW_SHIFT)
            rc2 != BOOLEX_TRUE && return rc2
            rc = BOOLEX_FALSE
        else
            enableSpareStack!(ld, true)
        end
    end
    return rc
end

# PORT: pl-gc.c clear_unused_stack
# DIVERGES: the body is `DEBUG(CHK_SECURE, ...)`, which a release build of swipl (the pin) leaves out: it writes
# nothing, and so does this.
"Write illegal values in the unused part of the stacks: a debug-build action, nothing in a release build (pl-gc.c)."
function clear_unused_stack(ld::PL_local_data{T})::Nothing where {T}
    return nothing
end

# PORT: pl-gc.c tight
# DIVERGES: only the local stack can be tight: the global stack and the trail grow on demand, without a size to
# run out of (the one limit is checked where they grow), so `tight` answers 0 for them. For the local stack the
# sizes are in positions: `sizeStackP` = `lMax + local_spare`, `roomStackP` = `lMax - lTop`, `min_free` =
# `LOCAL_MARGIN` (pl-gc.jl `growStacks_trim!`), `def_spare` = `local_def_spare`.
"Is the stack `which` (`:local`, `:global`, `:trail`) too tight after a collection? `GROW_TIGHT` or 0 (pl-gc.c `tight`)."
function tight(ld::PL_local_data{T}, which::Symbol)::Int where {T}
    which === :local || return 0
    size = ld.lMax + ld.local_spare                 # sizeStackP(s)
    min_room = size ÷ 3                             # sizeStackP(s)/3
    spare_gap = ld.local_def_spare - ld.local_spare
    if min_room < LOCAL_MARGIN                      # s->min_free
        min_room = LOCAL_MARGIN
    end
    if ld.lMax - ld.lTop < min_room + spare_gap     # roomStackP(s) < min_room + spare_gap
        return GROW_TIGHT
    end
    return 0
end

# PORT: pl-gc.c growStacks as growStacks_tight!
# DIVERGES: the GROW_TIGHT request of `shiftTightStacks` alone, for the local stack (the others never ask):
# the stack grows to the next size above its present one (`growStacks!` doubles until the request and the spare
# fit, within the one limit). Upstream's answer is the overflow id of the stack when it cannot grow; here it is
# `LOCAL_OVERFLOW` when the size did not change.
"Grow the local stack to its next size when `l` (a `tight` answer) asks for it; `BOOLEX_TRUE` or `LOCAL_OVERFLOW` (pl-gc.c)."
function growStacks_tight!(ld::PL_local_data{T}, l::Int)::boolex_t where {T}
    l == 0 && return BOOLEX_TRUE
    before = ld.lMax + ld.local_spare
    growStacks!(ld, before - ld.lTop + 1)           # one position more than the stack holds: the next size
    after = ld.lMax + ld.local_spare
    return after > before ? BOOLEX_TRUE : LOCAL_OVERFLOW
end

# PORT: pl-gc.c shiftTightStacks as shiftTightStacks!
# DIVERGES: see `tight` and `growStacks_tight!`.
"Grow the stacks that are tight after a collection: `BOOLEX_TRUE` or an overflow code (pl-gc.c `shiftTightStacks`)."
function shiftTightStacks!(ld::PL_local_data{T})::boolex_t where {T}
    l = tight(ld, :local)
    g = tight(ld, :global)
    t = tight(ld, :trail)
    if (l | g | t) != 0
        return growStacks_tight!(ld, l)
    else
        clear_unused_stack(ld)
    end
    return BOOLEX_TRUE
end

# PORT: pl-gc.c garbageCollect
# DIVERGES: (1) the VM state comes from `gc_get_vmi_state` and the callback `vmi_state_of` (G1-2b): a query inside the
# VM without the callback DECLINES (`BOOLEX_FALSE`) before anything is touched, no statistics record is written;
# (2) one thread: `enterGC`/`leaveGC`, `blockSignals`/`unblockSignals` and `save_backtrace` have no body here;
# (3) `setVar(*gTop)` ("always one space") is not needed: a position is a height, the cell above the top is not part of
# the heap; (4) the kernel order of the trail half (`mark_phase` before `tag_trail`, `gc_trail_phase` for the
# `compact_trail` call: see the header); (5) `assert(LD->mark_bar <= gTop)` (:4517, a debug assertion that would fail
# for the `NO_MARK_BAR` case upstream restores right after) is a CLAMP: a bar above the new top is lowered to it (every
# cell above a lowered bar is newer than the choicepoint, so only trailing becomes more eager, never less);
# (6) the flags (`blocked`, `active`, the bar) are restored by a `finally`: a collection that throws (a corrupted
# heap, `error`) leaves the engine unblocked; (7) `trimStacks` takes `false`: `LD->trim_stack_requested` has no
# counterpart (its writers are the overflow exceptions, pl-alloc.jl); (8) the `trace_gc` message (`verbose`) and the
# `CHK_SECURE` checks are not kept; (9) `collect_phase`'s count of references to value-table boxes (ruling D1) is
# non-negative by construction; the driver does not use it.
"""
    garbageCollect(ld, reason; vmi_state_of = nothing) -> boolex_t

Run the stack garbage collector (pl-gc.c): `BOOLEX_TRUE` when it ran and the stacks are not too tight,
`BOOLEX_FALSE` when it is blocked, turned off (`gc` flag) or needs a `vmi_state_of` it was not given, or an
overflow code. `reason` is a `GC_*` word; `vmi_state_of(ld, query_index) -> vm_state` builds the VM state of a
query that is inside the VM (G1-2b), and the state of every parent query the walk meets.
"""
function garbageCollect(
    ld::PL_local_data{T}, reason::Int; vmi_state_of=nothing
)::boolex_t where {T}
    if ld.gc.status.blocked != 0 || !truePrologFlag(ld, PLFLAG_GC)
        return BOOLEX_FALSE
    end
    vm0 = gc_get_vmi_state(ld, ld.query, vmi_state_of)
    vm0 === nothing && return BOOLEX_FALSE          # DIVERGES (1): the callback of G1-2b is missing
    vm = vm0

    gc_stat_start!(ld, ld.gc.stats, UInt64(reason))

    @assert ld.fast_condition == 0

    safeLTop = ld.lTop                              # include ARGP in body mode
    rc = gcEnsureSpace(ld, vm)
    if Int(rc) < 0
        return rc
    elseif rc == BOOLEX_FALSE                       # grown; reload
        vm1 = gc_get_vmi_state(ld, ld.query, vmi_state_of)
        vm1 === nothing && return BOOLEX_FALSE
        vm = vm1
    end

    blockGC(ld, 0)                                  # avoid recursion due to
    clearGcSignal!(ld, SIG_GC)                      # PL_clearsig(SIG_GC)
    ld.gc.status.active = true

    no_mark_bar = ld.mark_bar == NO_MARK_BAR
    if no_mark_bar
        ld.mark_bar = ld.gTop                       # otherwise we cannot relocate
    end

    try
        st = gc_mark_counts()                       # needs_relocation = 0, total_marked = 0, ...
        attvars = link_attvars(ld)
        astack = argument_stack_to_term_refs(ld, vm)
        gvars, saved_bar_at = gvars_to_term_refs(ld)
        grefs = save_grefs(ld)
        mark_phase(ld, st, vm; vmi_state_of=vmi_state_of)

        ts = gc_trail_begin!(ld)                    # tTop->address = 0
        tag_trail(ld, ts)
        sw = gc_sweep_counts()
        gc_trail_phase(ld, st, sw, ts, vm)          # compact_trail()
        collect_phase(ld, st, sw, vm; vmi_state_of=vmi_state_of, saved_bar_at=saved_bar_at)
        restore_grefs(ld, grefs)
        untag_trail(ld, ts)
        clean_attvar_chain(ld)
        gc_trail_end!(ld, ts)

        term_refs_to_gvars(ld, gvars, saved_bar_at)
        term_refs_to_argument_stack(ld, vm, astack)
        restore_attvars(ld, attvars)

        if !no_mark_bar && ld.mark_bar > ld.gTop    # DIVERGES (5): assert(LD->mark_bar <= gTop)
            ld.mark_bar = ld.gTop
        end
        gc_restore_vmi_state(ld, vm)                # restore_vmi_state(&state)
    finally
        if no_mark_bar
            ld.mark_bar = NO_MARK_BAR
        end
        ld.gc.status.active = false
        unblockGC(ld, 0)
    end
    ld.gc.inferences = ld.statistics.inferences

    preShiftLTop = ld.lTop                          # see (*) above: safe over trimStacks() (shift)
    ld.lTop = safeLTop
    trimStacks!(ld, false)                          # trimStacks(LD->trim_stack_requested)
    ld.lTop = preShiftLTop

    gc_stat_end!(ld, ld.gc.stats)

    return shiftTightStacks!(ld)
end
