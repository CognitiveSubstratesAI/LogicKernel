# UPSTREAM: swipl-devel src/pl-allocpool.c @ 18168e629eab
# CLASS: code
# COPYRIGHT: Copyright (c)  2019, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# allow-new-artifact: a 1:1 port of swipl-devel src/pl-allocpool.c (93 lines, read at the pin; the table_space flag and the trie node allocation of pl-trie.c need it; evidence/TAB1/tb0_state.md 1e, D-0453 TB0 decision 1)
#
# ALLOCATION POOLS (pl-allocpool.c): a counted limit over a kind of allocation. The Prolog flag `table_space` creates one
# (`LD->tabling.node_pool`, src/os/pl-prologflag.jl `set_flag_value`), TR1's trie nodes are charged to it, and
# `statistics(table_space_used, X)` reads its `size`. The struct `alloc_pool` is in src/pl-incl.jl (the local data holds one).
# DIVERGES (the whole file): Julia's collector frees memory, so `alloc_from_pool` and `free_to_pool` only COUNT `bytes`; they
# allocate and free nothing, and `alloc_from_pool` answers whether the bytes were charged (upstream: the memory, NULL for a
# failure). `new_alloc_pool` cannot fail (upstream raises `resource_error(memory)` for a failed `malloc`).

# PORT: pl-allocpool.c new_alloc_pool
# DIVERGES: see the file header; `limit` is an `Int` (`(size_t)`), the caller has range-checked it.
"A new pool with `limit` bytes (pl-allocpool.c)."
new_alloc_pool(name::String, limit::Int)::alloc_pool = alloc_pool(name, limit)

# PORT: pl-allocpool.c free_alloc_pool
# DIVERGES: see the file header; upstream frees the struct when the pool holds nothing, here Julia's collector does.
"Mark the pool freed: it is released with its last allocation (pl-allocpool.c)."
function free_alloc_pool(pool::alloc_pool)::Nothing
    pool.freed = true
    return nothing
end

# PORT: pl-allocpool.c alloc_from_pool
# DIVERGES: see the file header; a `nothing` pool (upstream: NULL, the allocation is not counted) charges nothing; the
# overrun `PL_resource_error(pool->name)` returns false, as upstream returns NULL.
"Charge `bytes` to `pool`, or raise `resource_error(Name)` when that exceeds its limit; false then (pl-allocpool.c)."
function alloc_from_pool(
    ld::PL_local_data{T}, pool::Union{Nothing, alloc_pool}, bytes::Int
)::Bool where {T}
    if pool !== nothing
        if pool.size + bytes <= pool.limit
            pool.size += bytes
        else
            PL_resource_error(ld, pool.name)
            return false
        end
    end

    return true
end

# PORT: pl-allocpool.c free_to_pool
# DIVERGES: see the file header; upstream's `mem` argument (the block it `free`s) is not passed, there is no block; its
# `assert(bytes <= pool->size)` is an `@assert`, and the `free(pool)` of a freed, empty pool is the collector's.
"Return `bytes` charged to `pool` (pl-allocpool.c)."
function free_to_pool(pool::Union{Nothing, alloc_pool}, bytes::Int)::Nothing
    if pool !== nothing
        @assert bytes <= pool.size
        pool.size -= bytes
    end

    return nothing
end
