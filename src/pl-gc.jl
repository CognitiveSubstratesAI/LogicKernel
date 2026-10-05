# UPSTREAM: swipl-devel src/pl-gc.c @ bae881a24a3f
# UPSTREAM: swipl-devel src/pl-gc.h @ bae881a24a3f
# CLASS: code
# COPYRIGHT: Copyright (c)  1985-2024, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# What the kernel takes from SWI-Prolog's garbage collector (pl-gc.c, pl-gc.h): finding the
# generations the predicates are being executed in, for clause GC, and growing the local stack.
# Stack garbage collection and stack shifting are not the kernel's.

# PORT: pl-gc.c markPredicatesInEnvironments
# DIVERGES: there is no local stack and there are no transactions, so no frames and no
# transaction start to walk: what remains is upstream's last step, the predicates referenced
# explicitly (`markAccessedPredicates`). Every enumeration over a dynamic predicate references it
# with `pushPredicateAccessObj!` — calls included, where upstream would find their frames.
"Record the generations every predicate is accessed in, for clause GC (pl-gc.c)."
function markPredicatesInEnvironments!(
    ld::PL_local_data{T}, gd::PL_global_data{T}
)::Nothing where {T}
    markAccessedPredicates!(ld, gd)
    return nothing
end

# PORT: pl-gc.c growStacks as growStacks!
# DIVERGES: grows the local stack only — there is no global, trail or argument stack of fixed
# size — and moves nothing: positions are offsets and records are indices, so upstream's work here,
# shifting the stacks and relocating every pointer into them, does not exist. The size doubles until
# the request fits, within `stacks_limit`; past the limit nothing grows, and the caller's re-check
# reports the overflow, as upstream's does when `grow_stacks` refuses.
"Grow the local stack so `l` more positions fit above `lTop` (pl-gc.c `growStacks`)."
function growStacks!(ld::PL_local_data{T}, l::Int)::Nothing where {T}
    need = ld.lTop + l
    need <= ld.lMax && return nothing
    size = max(ld.lMax, 1)
    while size < need
        size *= 2
    end
    size = min(size, ld.stacks_limit)
    size < need && return nothing
    resize!(ld.slots, size)                     # the cells: never read before they are written
    _grow_pool!(ld, ld.frames, cld(size, SIZEOF_LOCALFRAME))
    _grow_pool!(ld, ld.choices, cld(size, SIZEOF_CHOICE))
    _grow_pool!(ld, ld.fliframes, cld(size, SIZEOF_FLIFRAME))
    ld.lMax = size
    return nothing
end

# A record pool holds as many records as fit in the stack's positions: records of one kind never
# overlap, so pushing one never allocates.
function _grow_pool!(
    ld::PL_local_data{T}, pool::Vector{localFrame{T}}, n::Int
)::Nothing where {T}
    while length(pool) < n
        push!(pool, localFrame{T}(0, ld.null_code, 0, nothing, nothing, gen_t(0), 0x0, 0x0))
    end
    return nothing
end
function _grow_pool!(
    ld::PL_local_data{T}, pool::Vector{choice{T}}, n::Int
)::Nothing where {T}
    while length(pool) < n
        push!(
            pool, choice{T}(0, CHP_JUMP, 0, mark(0), 0, ClauseChoice{T}(nothing, word(0)))
        )
    end
    return nothing
end
function _grow_pool!(::PL_local_data, pool::Vector{fliFrame}, n::Int)::Nothing
    while length(pool) < n
        push!(pool, fliFrame(0, 0, 0, 0, mark(0)))
    end
    return nothing
end

# PORT: pl-gc.c growLocalSpace
# DIVERGES: `n` is in positions, where upstream's is in bytes. Not ported: the spare stack enabled
# while an exception is processed or GC runs (neither exists yet).
"Make room for `n` positions above `lTop`, growing the stack if `flags` allows (pl-gc.c)."
function growLocalSpace(ld::PL_local_data{T}, n::Int, flags::Int)::boolex_t where {T}
    if ld.lTop + n <= ld.lMax                   # addPointer(lTop, bytes) <= (void*)lMax
        return BOOLEX_TRUE
    end
    if flags == 0
        @goto nospace
    end
    growStacks!(ld, n)
    if ld.lTop + n <= ld.lMax
        return BOOLEX_TRUE
    end
    @label nospace
    return LOCAL_OVERFLOW
end

# PORT: pl-gc.h ensureLocalSpace_ex as ensureLocalSpace
# DIVERGES: `n` is in positions.
"Make room for `n` positions above `lTop`, or raise the overflow (pl-gc.h)."
function ensureLocalSpace(ld::PL_local_data{T}, n::Int)::Bool where {T}
    if hasLocalSpace(ld, n)
        return true
    end
    if (rc = growLocalSpace(ld, n, ALLOW_SHIFT)) == BOOLEX_TRUE
        return true
    end
    return raiseStackOverflow(ld, rc)
end
