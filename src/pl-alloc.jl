# UPSTREAM: swipl-devel src/pl-alloc.c @ bae881a24a3f
# CLASS: code
# COPYRIGHT: Copyright (c)  1985-2024, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# What the kernel takes from SWI-Prolog's memory management (pl-alloc.c): raising a stack overflow
# as a Prolog error with the spare stack enabled (since V5d), and growing the argument stack.

# PORT: pl-alloc.c enableSpareStack as enableSpareStack!
# DIVERGES: the local stack's, in positions.
"""
Add the local stack's spare to its `max`, when there is one and its free room is below the spare's
size or `always` (pl-alloc.c); whether it did.
"""
function enableSpareStack!(ld::PL_local_data{T}, always::Bool)::Bool where {T}
    if ld.local_spare != 0 && (ld.lMax - ld.lTop < ld.local_def_spare || always)
        ld.lMax += ld.local_spare                   # s->max = addPointer(s->max, s->spare)
        ld.local_spare = 0
        return true
    end
    return false
end

# PORT: pl-alloc.c enableSpareStacks as enableSpareStacks!
# DIVERGES: the local stack's only: there is no global or trail stack of fixed size.
"Enable the spare stacks where they are needed (pl-alloc.c)."
function enableSpareStacks!(ld::PL_local_data{T})::Nothing where {T}
    enableSpareStack!(ld, false)
    return nothing
end

# PORT: pl-alloc.c push_overflow_context
# DIVERGES: its fallback only — the stack's name atom, `local` (`PL_new_atom(stack->name)`), as
# decided since Q-B, an interim until dicts.
# NOT PORTED: the `stack_overflow{…}` dict (the stack sizes, the depth, the environments and choice
# points, the recursion found by `find_non_terminating_recursion` or the top of the stack): the
# kernel has no dicts.
"The context of a local-stack overflow's error (pl-alloc.c): the stack's name atom."
push_overflow_context(::Type{T}) where {T} = mk_sym(T, :local)

# PORT: pl-alloc.c outOfStack as outOfStack!
# DIVERGES: the local stack's, the only one that overflows here.
#   * A SECOND overflow before the first is recovered from (`LD->outofstack` still set): upstream
#     prints a backtrace and ENDS THE PROCESS (`fatalError`), because it can no longer trust its
#     state. A library must not end its host, so the kernel marks the local data `unusable` —
#     `PL_open_query` refuses every later query on it — and throws a Julia error with upstream's
#     message: nothing runs on a state that cannot be trusted, and the host survives (user,
#     2026-10-07).
#   * The ball is built as a value into `exception_bin` (upstream: raw global cells, then
#     `freezeGlobal`): it holds no variable, so undoing bindings cannot change it.
# NOT PORTED: the backtraces and the low-spare message (the kernel prints nothing, decision 1);
# `trim_stack_requested` (its readers are the stack garbage collector's, G1); the "no room for
# exception term" abort (the ball is a value: there is no global stack to run out of); the longjmp
# of `STACK_OVERFLOW_THROW` — every caller that throws a local-stack overflow sets `LD->outofstack`
# first, so the fatal branch runs before it, and the other stacks do not overflow here.
"""
    outOfStack!(ld, how) -> false

Raise `error(resource_error(stack), local)` for an overflow of the local stack: enable its spare,
mark the exception processed and the stack out of room (pl-alloc.c). A second overflow before the
first is recovered from makes `ld` unusable and throws.
"""
function outOfStack!(ld::PL_local_data{T}, how::stack_overflow_action)::Bool where {T}
    if ld.outofstack                                # LD->outofstack == stack
        ld.unusable = true                          # (see above: no fatalError)
        error("[Thread 1]: failed to recover from local-overflow: Sorry, cannot continue")
    end
    enableSpareStacks!(ld)
    ld.exception_processing = true
    ld.outofstack = true
    ctx = push_overflow_context(T)
    ld.slots[ld.exception_bin + 1] = mk_expr(
        T,
        T[
            mk_sym(T, :error), mk_expr(T, T[mk_sym(T, :resource_error), mk_sym(T, :stack)]),
            ctx
        ]
    )
    ld.exception_term = ld.exception_bin
    return false
end

# PORT: pl-alloc.c raiseStackOverflow
# DIVERGES: only `LOCAL_OVERFLOW` exists here — there is no global, trail, combined or argument stack
# of fixed size, and Julia raises its own `OutOfMemoryError` (`MEMORY_OVERFLOW`); `false` ("some
# other error is pending") returns `false`, as upstream.
"Raise the overflow `overflow` reports (pl-alloc.c)."
function raiseStackOverflow(ld::PL_local_data{T}, overflow::boolex_t)::Bool where {T}
    if overflow == LOCAL_OVERFLOW
        return outOfStack!(ld, STACK_OVERFLOW_RAISE)
    end
    @assert overflow == BOOLEX_FALSE "raiseStackOverflow: not an overflow: $overflow"
    return false
end

# PORT: pl-alloc.c f_pushArgumentStack
# DIVERGES: the stack doubles; nothing is re-based (`aSave` is a height, not a pointer), and there is
# no limit of its own (upstream's `outOfStack` on the argument stack).
"Grow the argument stack and push `e` (pl-alloc.c)."
function f_pushArgumentStack(ld::PL_local_data{T}, e::argstack_entry{T})::Nothing where {T}
    resize!(ld.astack, 2 * length(ld.astack))
    ld.aTop += 1
    ld.astack[ld.aTop] = e
    return nothing
end
