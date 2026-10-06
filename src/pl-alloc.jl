# UPSTREAM: swipl-devel src/pl-alloc.c @ bae881a24a3f
# CLASS: code
# COPYRIGHT: Copyright (c)  1985-2024, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# What the kernel takes from SWI-Prolog's memory management (pl-alloc.c): raising a stack overflow,
# and growing the argument stack.

"""
    LocalStackOverflow(lTop, lMax, limit)

The local stack cannot grow: `lTop` plus the room asked for is past `limit` positions. Raised by
[`raiseStackOverflow`](@ref) until the VM can raise upstream's
`error(resource_error(stack), stack_overflow{…})`, whose dict context is the user's question Q-B,
so runaway recursion stops here rather than exhausting memory.
"""
struct LocalStackOverflow <: Exception
    lTop::Int
    lMax::Int
    limit::Int
end
function Base.showerror(io::IO, e::LocalStackOverflow)
    print(io,
        "LocalStackOverflow: the local stack is at $(e.lTop) of $(e.lMax) positions and ",
        "cannot grow past its limit of $(e.limit)")
    return nothing
end

# PORT: pl-alloc.c raiseStackOverflow
# DIVERGES (interim, the user's Q-B): throws `LocalStackOverflow`, a Julia exception (the query
# closes, decision 1), where upstream's `outOfStack` raises `error(resource_error(stack), Ctx)`
# with `PL_raise_exception`. That path is ported since V5b; what is missing is `Ctx`, a
# `stack_overflow{…}` DICT (`push_overflow_context`) — Q-B. Only `LOCAL_OVERFLOW` exists here;
# `false` ("some other error is pending") returns `false`, as upstream.
"Raise the overflow `overflow` reports (pl-alloc.c)."
function raiseStackOverflow(ld::PL_local_data{T}, overflow::boolex_t)::Bool where {T}
    if overflow == LOCAL_OVERFLOW
        throw(LocalStackOverflow(ld.lTop, ld.lMax, ld.stacks_limit))
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
