# UPSTREAM: swipl-devel src/pl-idgset.c @ 18168e629eab
# UPSTREAM: swipl-devel src/pl-idgset.h @ 18168e629eab
# CLASS: code
# COPYRIGHT: Copyright (c)  2026, SWI-Prolog Solutions b.v.
# allow-new-artifact: a 1:1 port of swipl-devel src/pl-idgset.c (766 lines, read at the pin; new at 10.1.20, T1 of evidence/TAB1/decomposition.md; the IDG edges of pl-tabling.c need it, TAB1 TB6)
#
# IDG SETS (pl-idgset.c): the edge sets of the nodes of the incremental dependency graph and the registry of a thread's
# IDG nodes. The structs (`idg_set`, `idg_set_block`, `idg_set_enum`, `idg_registry`) are in src/pl-incl.jl with their
# representation note; the functions are here in the order of pl-idgset.c.
# DIVERGES (the whole file): the single-thread build (`#ifndef O_PLMT`): `lock_set`/`unlock_set` and `REG_LOCK`/`REG_UNLOCK`
# do nothing, `idg_free_or_defer` calls the function at once, `idg_reader_enter`/`idg_reader_exit` do nothing (the
# readers and their deferred list are the threads', TH1). Memory is Julia's: a block, a node and a registry slot block are
# CHARGED to the pool (`alloc_from_pool`, upstream's bytes) and DISCHARGED (`free_to_pool`) where upstream allocates and
# frees them. `COMPARE_AND_SWAP_PTR` and the memory barriers are plain stores. A function that allocates takes `ld` for
# the resource error `alloc_from_pool` raises. Positions are 0-based as upstream's (`entries[pos + 1]`).

# ── the representation helpers (pl-idgset.c:43-66) ───────────────────────────────────────────────────

# PORT: pl-idgset.c sizeof_block
"The bytes of a block with `capacity` entries and an index of `1 << index_bits` slots (pl-idgset.c `sizeof_block`)."
sizeof_block(capacity::Int, index_bits::Int)::Int =
    SIZEOF_IDG_SET_BLOCK + capacity * 8 + (index_bits != 0 ? (1 << index_bits) * 4 : 0)

# PORT: pl-idgset.c hash_slot
# DIVERGES: the pointer is `objectid(p)` (identity, as the address).
"The index slot of `p` in an index of `1 << bits` slots (pl-idgset.c `hash_slot`)."
function hash_slot(p::P, bits::Int)::Int where {P}
    h = (objectid(p) % UInt64) * 0x9e3779b97f4a7c15
    return Int(h >> (64 - bits))
end

# ── BLOCKS (pl-idgset.c:105-258) ─────────────────────────────────────────────────────────────────────

# PORT: pl-idgset.c new_block
# DIVERGES: see the file header; `nothing` if the pool is exhausted (upstream NULL), the resource error raised.
"A new block with room for `capacity` entries, charged to `pool` (pl-idgset.c `new_block`)."
function new_block(
    ld::PL_local_data{T}, ::Type{P}, capacity::Int, pool::Union{Nothing, alloc_pool}
)::Union{Nothing, idg_set_block{P}} where {T, P}
    bits = 0

    if capacity > IDG_SET_LINEAR_MAX
        while (1 << bits) < capacity * 2                # at least two slots
            bits += 1                                   # per entry
        end
    end
    bytes = sizeof_block(capacity, bits)
    alloc_from_pool(ld, pool, bytes) || return nothing
    index = bits != 0 ? zeros(UInt32, 1 << bits) : UInt32[]

    return idg_set_block{P}(
        0, capacity, 0, bits, nothing, Vector{P}(undef, capacity), fill(false, capacity),
        index
    )
end

# PORT: pl-idgset.c free_block_now
"Discharge the bytes of the block `b` from `pool` (pl-idgset.c `free_block_now`)."
function free_block_now(
    b::idg_set_block{P}, pool::Union{Nothing, alloc_pool}
)::Nothing where {P}
    free_to_pool(pool, sizeof_block(b.capacity, b.index_bits))
    return nothing
end

# PORT: pl-idgset.c free_block
"Free the block `b` (pl-idgset.c `free_block`)."
function free_block(
    b::idg_set_block{P}, pool::Union{Nothing, alloc_pool}
)::Nothing where {P}
    idg_free_or_defer(free_block_now, b, pool)
    return nothing
end

# PORT: pl-idgset.c retire_block
# DIVERGES: `lingering` is the node that owns the list (`nothing`: NULL), the CAS loop a store.
"A block was replaced or removed from its set: keep it on `lingering` or free it (pl-idgset.c `retire_block`)."
function retire_block(
    b::idg_set_block{P}, lingering::Union{Nothing, P}, pool::Union{Nothing, alloc_pool}
)::Nothing where {P}
    if lingering !== nothing
        o = lingering.lingering
        b.older = o
        lingering.lingering = b
    else
        free_block(b, pool)
    end

    return nothing
end

# PORT: pl-idgset.c idg_set_free_lingering
# DIVERGES: `lingering` is the node that owns the list.
"Free the blocks on the lingering list of `lingering` (pl-idgset.c `idg_set_free_lingering`)."
function idg_set_free_lingering(
    lingering::P, pool::Union{Nothing, alloc_pool}
)::Nothing where {P}
    b = lingering.lingering

    lingering.lingering = nothing
    while b !== nothing
        o = b.older

        free_block(b, pool)
        b = o
    end

    return nothing
end

# PORT: pl-idgset.c index_insert
"Enter `p` at position `pos` in the index of `b` (pl-idgset.c `index_insert`)."
function index_insert(b::idg_set_block{P}, p::P, pos::Int)::Nothing where {P}
    idx = b.index
    mask = (1 << b.index_bits) - 1
    s = hash_slot(p, b.index_bits)

    while idx[s + 1] != 0
        s = (s + 1) & mask
    end
    idx[s + 1] = UInt32(pos + 1)

    return nothing
end

# PORT: pl-idgset.c find_pos
"The position of `p` in `b`, also if it is dead; -1 if `p` is not in `b` (pl-idgset.c `find_pos`)."
function find_pos(b::idg_set_block{P}, p::P)::Int where {P}
    count = b.count

    if b.index_bits == 0
        for i in 0:(count - 1)
            b.entries[i + 1] === p && return i
        end
    else
        idx = b.index
        mask = (1 << b.index_bits) - 1
        s = hash_slot(p, b.index_bits)

        while (v = idx[s + 1]) != 0
            pos = Int(v) - 1

            b.entries[pos + 1] === p && return pos
            s = (s + 1) & mask
        end
    end

    return -1
end

# PORT: pl-idgset.c append
"Append `p` to `b`, which has room (pl-idgset.c `append`)."
function append(b::idg_set_block{P}, p::P)::Nothing where {P}
    pos = b.count

    b.entries[pos + 1] = p
    b.entry_dead[pos + 1] = false
    if b.index_bits != 0
        index_insert(b, p, pos)
    end
    b.count = pos + 1

    return nothing
end

# PORT: pl-idgset.c grow_block
"A larger copy of `b`, the entries at their positions; `nothing` if the pool is exhausted (pl-idgset.c `grow_block`)."
function grow_block(
    ld::PL_local_data{T}, b::idg_set_block{P}, pool::Union{Nothing, alloc_pool}
)::Union{Nothing, idg_set_block{P}} where {T, P}
    nb = new_block(ld, P, b.capacity * 2, pool)

    nb === nothing && return nothing
    copyto!(nb.entries, 1, b.entries, 1, b.count)
    copyto!(nb.entry_dead, 1, b.entry_dead, 1, b.count)
    nb.dead = b.dead
    if nb.index_bits != 0
        for i in 0:(b.count - 1)
            index_insert(nb, b.entries[i + 1], i)
        end
    end
    nb.count = b.count

    return nb
end

# ── API (pl-idgset.c:261-477) ────────────────────────────────────────────────────────────────────────

# PORT: pl-idgset.c idg_set_add
# DIVERGES: see the file header; `lingering` is the node that owns the list (`nothing`: NULL).
"Add `p` to `set`: 1 if added, 0 if it was in the set, -1 if the pool is exhausted (a resource error) (pl-idgset.c)."
function idg_set_add(
    ld::PL_local_data{T}, set::idg_set{P}, p::P, lingering::Union{Nothing, P},
    pool::Union{Nothing, alloc_pool}
)::Int where {T, P}
    added = 1

    if set.single === nothing && set.block === nothing
        set.single = p
    elseif (sp = set.single) !== nothing
        if sp === p
            added = 0
        else
            b = new_block(ld, P, 4, pool)

            if b !== nothing
                append(b, sp)
                append(b, p)
                set.single = nothing
                set.block = b
            else
                added = -1
            end
        end
    else
        b = set.block::idg_set_block{P}
        pos = find_pos(b, p)

        if pos >= 0
            if b.entry_dead[pos + 1]
                b.entry_dead[pos + 1] = false
                b.dead -= 1
            else
                added = 0
            end
        else
            if b.count == b.capacity
                nb = grow_block(ld, b, pool)

                if nb !== nothing
                    append(nb, p)
                    set.block = nb
                    retire_block(b, lingering, pool)
                else
                    added = -1
                end
            else
                append(b, p)
            end
        end
    end

    return added
end

# PORT: pl-idgset.c idg_set_delete
# DIVERGES: see `idg_set_add`.
"Delete `p` from `set`; true if `p` was in the set (pl-idgset.c `idg_set_delete`)."
function idg_set_delete(
    set::idg_set{P}, p::P, lingering::Union{Nothing, P}, pool::Union{Nothing, alloc_pool}
)::Bool where {P}
    deleted = false

    if (sp = set.single) !== nothing
        if sp === p
            set.single = nothing
            deleted = true
        end
    elseif (b = set.block) !== nothing
        pos = find_pos(b, p)

        if pos >= 0 && !b.entry_dead[pos + 1]
            b.entry_dead[pos + 1] = true
            deleted = true
            if (b.dead += 1) == b.count                 # nothing left
                set.block = nothing
                retire_block(b, lingering, pool)
            end
        end
    end

    return deleted
end

# PORT: pl-idgset.c idg_set_contains
"True if `p` is a live entry of `set` (pl-idgset.c `idg_set_contains`)."
function idg_set_contains(set::idg_set{P}, p::P)::Bool where {P}
    if (sp = set.single) !== nothing
        return sp === p
    elseif (b = set.block) !== nothing
        pos = find_pos(b, p)

        return pos >= 0 && !b.entry_dead[pos + 1]
    end

    return false
end

# PORT: pl-idgset.c idg_set_size
"The number of live entries of `set` (pl-idgset.c `idg_set_size`)."
function idg_set_size(set::idg_set{P})::Int where {P}
    set.single !== nothing && return 1
    if (b = set.block) !== nothing
        return b.count - b.dead
    end

    return 0
end

# PORT: pl-idgset.c idg_set_sizeof
"The bytes of the block of `set` (0: empty or one pointer) (pl-idgset.c `idg_set_sizeof`)."
function idg_set_sizeof(set::idg_set{P})::Int where {P}
    if (b = set.block) !== nothing
        return sizeof_block(b.capacity, b.index_bits)
    end

    return 0
end

# PORT: pl-idgset.c idg_set_lingering_sizeof
"The bytes of the blocks on the lingering list that starts with `b` (pl-idgset.c `idg_set_lingering_sizeof`)."
function idg_set_lingering_sizeof(b::Union{Nothing, idg_set_block{P}})::Int where {P}
    size = 0

    while b !== nothing
        size += sizeof_block(b.capacity, b.index_bits)
        b = b.older
    end

    return size
end

# PORT: pl-idgset.c idg_set_clear
# DIVERGES: `func` is a Julia function `func(p, ctx)` or `nothing` (NULL); see `idg_set_add` for `lingering`.
"Empty `set`, calling `func(p, ctx)` for each pointer it held; the set is detached first (pl-idgset.c `idg_set_clear`)."
function idg_set_clear(
    set::idg_set{P}, func::F, ctx::C, lingering::Union{Nothing, P},
    pool::Union{Nothing, alloc_pool}
)::Nothing where {P, F, C}
    sp = set.single
    b = set.block

    set.single = nothing
    set.block = nothing

    if sp !== nothing
        if func !== nothing
            func(sp, ctx)
        end
    elseif b !== nothing
        if func !== nothing
            for i in 0:(b.count - 1)
                e = b.entries[i + 1]

                b.entry_dead[i + 1] || func(e, ctx)
            end
        end
        retire_block(b, lingering, pool)
    end

    return nothing
end

# PORT: pl-idgset.h idg_set_enum_init
# DIVERGES: returns the new enumeration (upstream fills the caller's `idg_set_enum`).
"Start the enumeration `e` of `set` (pl-idgset.h `idg_set_enum_init`)."
idg_set_enum_init(set::idg_set{P}) where {P} = idg_set_enum{P}(set, 0)

# PORT: pl-idgset.h idg_set_is_empty
"True if `set` has no live entry (pl-idgset.h `idg_set_is_empty`)."
idg_set_is_empty(set::idg_set{P}) where {P} = idg_set_size(set) == 0

# PORT: pl-idgset.c idg_set_next
"The next live pointer of the enumeration `e`, or `nothing`; the set is read again for each step (pl-idgset.c)."
function idg_set_next(e::idg_set_enum{P})::Union{Nothing, P} where {P}
    set = e.set

    if (sp = set.single) !== nothing
        if e.pos == 0
            e.pos = 1
            return sp
        end
    elseif (b = set.block) !== nothing
        count = b.count

        while e.pos < count
            i = e.pos
            e.pos += 1

            b.entry_dead[i + 1] || return b.entries[i + 1]
        end
    end

    return nothing
end

# ── EXTERNAL READERS (pl-idgset.c:480-583, the `#else /*O_PLMT*/` half) ─────────────────────────────

# PORT: pl-idgset.c initIDGReaders
"Initialise the IDG readers: nothing to do without threads (pl-idgset.c `initIDGReaders`)."
initIDGReaders()::Nothing = nothing

# PORT: pl-idgset.c idg_free_or_defer
"Free `ptr` with `func(ptr, ctx)`; without threads at once (pl-idgset.c `idg_free_or_defer`)."
function idg_free_or_defer(func::F, ptr::X, ctx::C)::Nothing where {F, X, C}
    func(ptr, ctx)
    return nothing
end

# PORT: pl-idgset.c idg_reader_enter
"Enter the reader section: nothing to do without threads (pl-idgset.c `idg_reader_enter`)."
idg_reader_enter()::Nothing = nothing

# PORT: pl-idgset.c idg_reader_exit
"Leave the reader section: nothing to do without threads (pl-idgset.c `idg_reader_exit`)."
idg_reader_exit()::Nothing = nothing

# ── REGISTRY (pl-idgset.c:586-766) ───────────────────────────────────────────────────────────────────

# PORT: pl-idgset.c reg_block
# DIVERGES: returns `(k, offset)` (upstream: `k`, `*offset`).
"The block `k` and the offset in it of the slot `index` (pl-idgset.c `reg_block`)."
function reg_block(index::Int)::Tuple{Int, Int}
    v = index + (1 << IDG_REG_BASE_BITS)
    k = MSB64(Int64(v)) - IDG_REG_BASE_BITS

    return (k, v - ((1 << IDG_REG_BASE_BITS) << k))
end

# PORT: pl-idgset.c reg_block_size
"The number of slots of registry block `k` (pl-idgset.c `reg_block_size`)."
reg_block_size(k::Int)::Int = (1 << IDG_REG_BASE_BITS) << k

# PORT: pl-idgset.c idg_registry_new
"A new registry with one reference, the thread's (pl-idgset.c `idg_registry_new`)."
function idg_registry_new(::Type{P})::idg_registry{P} where {P}
    blocks = Vector{Union{Nothing, Vector{Union{Nothing, Int, P}}}}(nothing, IDG_REG_BLOCKS)

    return idg_registry{P}(1, 0, 0, nothing, blocks)
end

# PORT: pl-idgset.c free_registry_now
# DIVERGES: `ctx` is unused, as upstream's; the slot blocks are discharged from the registry's pool.
"Discharge the slot blocks of `reg` (pl-idgset.c `free_registry_now`)."
function free_registry_now(reg::idg_registry{P}, ctx::Nothing)::Nothing where {P}
    for k in 0:(IDG_REG_BLOCKS - 1)
        if reg.blocks[k + 1] !== nothing
            free_to_pool(reg.pool, reg_block_size(k) * 8)
        end
    end

    return nothing
end

# PORT: pl-idgset.c idg_registry_add
# DIVERGES: see the file header; -1 is upstream's `(size_t)-1` (the pool is exhausted, a resource error raised).
"Add `node` to `reg` and return its slot; adds a reference (pl-idgset.c `idg_registry_add`)."
function idg_registry_add(
    ld::PL_local_data{T}, reg::idg_registry{P}, node::P, pool::Union{Nothing, alloc_pool}
)::Int where {T, P}
    if reg.free != 0
        index = reg.free - 1
        k, offset = reg_block(index)
        blk = reg.blocks[k + 1]::Vector{Union{Nothing, Int, P}}
        reg.free = blk[offset + 1]::Int
        blk[offset + 1] = node
    else
        index = reg.count
        k, offset = reg_block(index)
        if reg.blocks[k + 1] === nothing
            bytes = reg_block_size(k) * 8

            @assert reg.pool === nothing || reg.pool === pool
            alloc_from_pool(ld, pool, bytes) || return -1
            reg.pool = pool
            reg.blocks[k + 1] = Vector{Union{Nothing, Int, P}}(nothing, reg_block_size(k))
        end
        (reg.blocks[k + 1]::Vector{Union{Nothing, Int, P}})[offset + 1] = node
        reg.count = index + 1
    end
    reg.references += 1

    return index
end

# PORT: pl-idgset.c idg_registry_delete
"Delete the node in slot `index` of `reg`; drops a reference (pl-idgset.c `idg_registry_delete`)."
function idg_registry_delete(reg::idg_registry{P}, index::Int)::Nothing where {P}
    k, offset = reg_block(index)

    (reg.blocks[k + 1]::Vector{Union{Nothing, Int, P}})[offset + 1] = reg.free
    reg.free = index + 1
    idg_registry_release(reg)

    return nothing
end

# PORT: pl-idgset.c idg_registry_release
"Drop a reference of `reg` (pl-idgset.c `idg_registry_release`)."
idg_registry_release(reg::idg_registry{P}) where {P} = idg_registry_release_n(reg, 1)

# PORT: pl-idgset.c idg_registry_release_n
"Drop `n` references of `reg`, freeing it with the last (pl-idgset.c `idg_registry_release_n`)."
function idg_registry_release_n(reg::idg_registry{P}, n::Int)::Nothing where {P}
    @assert reg.references >= n
    left = reg.references -= n
    if left == 0
        idg_free_or_defer(free_registry_now, reg, nothing)
    end

    return nothing
end

# PORT: pl-idgset.c idg_registry_count
"The slots of `reg` in use, the high water (pl-idgset.c `idg_registry_count`)."
idg_registry_count(reg::idg_registry{P}) where {P} = reg.count

# PORT: pl-idgset.c idg_registry_sizeof
"The bytes of the slot blocks of `reg` (pl-idgset.c `idg_registry_sizeof`)."
function idg_registry_sizeof(reg::idg_registry{P})::Int where {P}
    size = 0

    for k in 0:(IDG_REG_BLOCKS - 1)
        if reg.blocks[k + 1] !== nothing
            size += reg_block_size(k) * 8
        end
    end

    return size
end

# PORT: pl-idgset.c idg_registry_get
"The node in slot `index` of `reg`, or `nothing` if the slot is free (pl-idgset.c `idg_registry_get`)."
function idg_registry_get(reg::idg_registry{P}, index::Int)::Union{Nothing, P} where {P}
    k, offset = reg_block(index)
    b = reg.blocks[k + 1]

    b === nothing && return nothing
    v = b[offset + 1]
    v isa Int && return nothing                         # IS_FREE_SLOT

    return v
end
