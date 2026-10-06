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
[`raiseStackOverflow`](@ref) until V5d raises upstream's `error(resource_error(stack), Ctx)` —
`Ctx` the stack's name atom, upstream's own fallback, as decided since Q-B — so runaway recursion
stops here rather than exhausting memory.
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
# DIVERGES (interim, until V5d): throws `LocalStackOverflow`, a Julia exception (the query closes,
# decision 1), where upstream's `outOfStack` builds `error(resource_error(stack), Ctx)` itself and
# makes it the pending exception, not through `PL_raise_exception` (pl-alloc.c:641-656). V5d ports
# it with `Ctx` the stack's name atom (`local`), as decided since Q-B: upstream's fallback when the
# `stack_overflow{…}` dict (`push_overflow_context`) cannot be built, until dicts. Only
# `LOCAL_OVERFLOW` exists here; `false` ("some other error is pending") returns `false`, as
# upstream.
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
