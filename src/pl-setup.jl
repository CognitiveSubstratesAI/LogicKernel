# UPSTREAM: swipl-devel src/pl-setup.c @ bae881a24a3f
# CLASS: code
# COPYRIGHT: Copyright (c)  1985-2024, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# What the kernel takes from SWI-Prolog's start-up (pl-setup.c): allocating and emptying the stacks
# of a thread, which leaves one foreign frame at the base of the local stack; since V5d the local
# stack's spare — room reserved above its `max` for handling a stack overflow — given back after
# an exception (`trim_stack`, `trimStacks`).

# setup:1631 the local stack's spare: `512*SIZEOF_WORD + LOCAL_MARGIN` bytes, here in positions.
"The spare of a new local stack, in positions (pl-setup.c `allocStacks`)."
const LOCAL_SPARE = 512 + LOCAL_MARGIN

# PORT: pl-setup.c init_stack as init_stack!
# DIVERGES: the local stack's, in positions; there is no name (the overflow's context names it,
# src/pl-alloc.jl), `min_free` (the kernel's growth doubles, src/pl-gc.jl `growStacks!`), `gced_size`
# or GC policy (no stack garbage collector until G1). The cells and the record pools are grown to
# `size` (`_resize_local!`); `stack_malloc` allocated them upstream.
"Set up the local stack: `size` positions, of which `spare` are reserved above its `max` (pl-setup.c)."
function init_stack!(ld::PL_local_data{T}, size::Int, spare::Int)::Nothing where {T}
    ld.lTop = 0                                 # s->top = s->base
    _resize_local!(ld, size)
    ld.local_spare = spare
    ld.local_def_spare = spare
    ld.lMax = size - spare                      # s->max = addPointer(s->base, size - spare)
    return nothing
end

# PORT: pl-setup.c allocStacks as allocStacks!
# DIVERGES: the local stack only — there is no global, trail or argument stack of fixed size — and
# in positions: `minlocal` (4 K words) is `LOCAL_INITIAL`, its spare `LOCAL_SPARE`; nothing is
# allocated that can fail. `stacks.local.min_free` is not kept (see `init_stack!`).
"Allocate the local stack of a new thread (pl-setup.c)."
function allocStacks!(ld::PL_local_data{T})::Bool where {T}
    init_stack!(ld, LOCAL_INITIAL, LOCAL_SPARE)
    return true
end

# PORT: pl-setup.c trim_stack as trim_stack!
# DIVERGES: the local stack's, in positions.
"Reserve the local stack's spare again above its `max`, as far as its free room allows (pl-setup.c)."
function trim_stack!(ld::PL_local_data{T})::Nothing where {T}
    if ld.local_spare < ld.local_def_spare
        reduce = ld.local_def_spare - ld.local_spare
        room = ld.lMax - ld.lTop                # roomStackP(s)
        if room > 0 && room < reduce
            reduce = room
        end
        ld.lMax -= reduce                       # s->max = addPointer(s->max, -reduce)
        ld.local_spare += reduce
    end
    return nothing
end

# PORT: pl-setup.c trimStacks as trimStacks!
# DIVERGES: the stack is never shrunk — `resize` (`growStacks(GROW_TRIM, …)`, which re-reserves the
# spares as it shrinks) is the local stack's `trim_stack!` here, as without it — and only the local
# stack has a spare. `lTop` is raised to the query's saved argument pointer while the spare is
# reserved, as upstream's.
# NOT PORTED: `trim_stack_requested`: its readers are the stack garbage collector's (pl-gc.c
# `garbageCollect`), not ported until G1; SECURE_GC's clearing and the debug checks.
"Reclaim the local stack's spare after an exception (pl-setup.c)."
function trimStacks!(ld::PL_local_data{T}, resize::Bool)::Nothing where {T}
    lsave = ld.lTop
    if ld.query != 0                            # saved registers above lTop
        q = ld.queries[ld.query]
        if q.registers_fr != 0 && q.registers_argp.form == ARGP_SLOT &&
            q.registers_argp.pos > ld.lTop
            ld.lTop = q.registers_argp.pos
        end
    end
    trim_stack!(ld)                             # (resize: growStacks(GROW_TRIM) — see above)
    ld.lTop = lsave
    return nothing
end

# PORT: pl-setup.c emptyStacks as emptyStacks!
# DIVERGES: no global stack to empty; the argument stack is emptied, with the write-mode builder's
# (`bTop`, `nbframes`, the kernel's own), and the trail's bindings go with the trail (`bindings`).
# `BFR` and `LD->query` are cleared with the stack they point into; there is no `mark_bar`, and no
# `lTop && gTop` guard (the stacks always exist). Of the
# engine's permanent term references upstream allocates in the base foreign frame, the exception's
# four are (`exception_bin`, `exception_printed`, `exception.tmp`, `exception.pending`, in
# upstream's order); the others belong to subsystems not ported (`trim.dummy`, attributed
# variables, undo hooks, tabling, `LD->tmp.h[]`; nor `destroyGlobalVars`). So later term references
# lie at other absolute positions than in
# swipl: compare DIFFERENCES between positions with swipl, never absolute ones.
"Empty the local stack and the trail, then open the base foreign frame (pl-setup.c)."
function emptyStacks!(ld::PL_local_data{T})::Nothing where {T}
    ld.environment_frame = 0                    # environment_frame = NULL;
    ld.fli_context = 0                          # fli_context = NULL;
    ld.BFR = 0

    ld.lTop = 0                                 # emptyStack((Stack)&LD->stacks.local);
    ld.nframes = 0
    ld.nchoices = 0
    ld.nfliframes = 0
    ld.nqueries = 0
    ld.query = 0                                # LD->query = NULL;
    ld.aTop = 0                                 # emptyStack((Stack)&LD->stacks.argument);
    ld.bTop = 0
    ld.nbframes = 0
    empty!(ld.trail)                            # emptyStack((Stack)&LD->stacks.trail);
    empty!(ld.bindings)

    PL_open_foreign_frame(ld)
    ld.exception_term = 0
    ld.exception_bin = PL_new_term_ref(ld)
    ld.exception_printed = PL_new_term_ref(ld)
    ld.exception_tmp = PL_new_term_ref(ld)                     # LD->exception.tmp
    ld.exception_pending = PL_new_term_ref(ld)                 # LD->exception.pending
    return nothing
end
