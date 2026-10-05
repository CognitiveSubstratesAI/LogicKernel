# UPSTREAM: swipl-devel src/pl-alloc.c @ bae881a24a3f
# CLASS: code
# COPYRIGHT: Copyright (c)  1985-2024, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# What the kernel takes from SWI-Prolog's memory management (pl-alloc.c): raising a stack overflow.

"""
    LocalStackOverflow(lTop, lMax, limit)

The local stack cannot grow: `lTop` plus the room asked for is past `limit` positions. Raised by
[`raiseStackOverflow`](@ref) until the VM can raise upstream's
`error(resource_error(stack), stack_overflow{…})` (V5), so runaway recursion stops here rather
than exhausting memory.
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
# DIVERGES: throws `LocalStackOverflow` until V5 ports the exception path (`outOfStack` builds the
# Prolog error term and `PL_raise_exception`s it). Only `LOCAL_OVERFLOW` exists here; `false`
# ("some other error is pending") returns `false`, as upstream.
"Raise the overflow `overflow` reports (pl-alloc.c)."
function raiseStackOverflow(ld::PL_local_data{T}, overflow::boolex_t)::Bool where {T}
    if overflow == LOCAL_OVERFLOW
        throw(LocalStackOverflow(ld.lTop, ld.lMax, ld.stacks_limit))
    end
    @assert overflow == BOOLEX_FALSE "raiseStackOverflow: not an overflow: $overflow"
    return false
end
