# UPSTREAM: swipl-devel src/os/pl-table.c @ af9e2e7ed0be
# UPSTREAM: swipl-devel src/os/pl-table.h @ 18168e629eab
# UPSTREAM: swipl-devel src/SWI-Prolog.h @ 18168e629eab
# CLASS: code
# COPYRIGHT: Copyright (c)  2011-2024, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
# allow-new-artifact: a port of the pin's src/os/pl-table.c, read in full from the pin (git show 18168e62) for this file
#
# TABLE (pl-table.c), lane F: upstream's hash tables, word -> word, ported as upstream builds them: a closed
# 2^N table with stride-1 reprobing, a chain of key-value maps (KVS) when a table is resized, and the entry states
# <NULL,NULL> / <K,NULL> / <K,V> / <K,TOMBSTONE> / <SENTINEL,NULL> / <K,SENTINEL> that a resize moves through.
# Why it is ported although the kernel keeps its own `Dict`s: a table's ENUMERATION ORDER is its bucket order
# (`pointerHashValue`, src/pl-funct.jl), and `current_op/3`, `current_module/1` and the like show it
# (the DIVERGES of src/pl-op.jl and src/pl-modul.jl name this file as their re-check trigger).
#
# THE KERNEL HAS ONE ENGINE. Upstream's tables are lock-free: every store is a `COMPARE_AND_SWAP`, a table's
# KVS in use by a thread is published in that thread's `access.kvs` (O_PLMT) and `pl_kvs_in_use` reads it. Here a CAS is
# a compare and a store (`htable_cas_*`), the `#else` of `acquire_kvs`/`release_kvs` (no thread info) is the one
# form ported, and no engine but the caller's holds a KVS (`_htable_kvs_in_use` is false). The state machine
# and every branch of it stay, so a thread port (TH1) changes the four CAS helpers and `_htable_kvs_in_use`, nothing else.
#
# NOT PORTED: the typed views `TableWW`/`TablePP`/`TableWP`/`TablePW` and their inline wrappers (pl-table.h: casts of
# `Table`; Julia keys and values are `UInt64` here, the caller converts); `allocHeapOrHalt`/`freeHeap` (the memory is
# the garbage collector's); `FOR_TABLE` (pl-table.h: a macro over `TableEnum`; `advanceTableEnum` is its body).

# PORT: pl-table.h NULL_KEY
const NULL_KEY = UInt64(0)
# PORT: pl-table.h NULL_VALUE
const NULL_VALUE = UInt64(0)
# PORT: pl-table.c HTABLE_NORMAL
const HTABLE_NORMAL = 1
# PORT: pl-table.c HTABLE_RESIZE
const HTABLE_RESIZE = 2
# PORT: pl-table.c HTABLE_PRESERVE
const HTABLE_PRESERVE = 4
# PORT: pl-table.c HTABLE_TOMBSTONE
const HTABLE_TOMBSTONE = typemax(UInt64)             # ((table_value_t)-1)
# PORT: pl-table.c HTABLE_SENTINEL
const HTABLE_SENTINEL = typemax(UInt64) - UInt64(1)  # ((table_key_t)-2)
# PORT: SWI-Prolog.h PL_HT_NEW
const PL_HT_NEW = 1
# PORT: SWI-Prolog.h PL_HT_UPDATE
const PL_HT_UPDATE = 2

# ORIGINAL: the four structs of pl-table.h (`symbol`, `KVS`, `Table`, `TableEnum`) are defined in src/pl-incl.jl (include order:
# `ld_coverage`, a field of the local data, holds a `Table`, and src/pl-global.jl comes before this file); their
# `# PORT: pl-table.h` markers and DIVERGES lines moved with them.

# ORIGINAL: pl-thread.c `pl_kvs_in_use(kvs)`, true when a thread's `access.kvs` is `kvs`. The kernel has one
# engine and no engine holds a map across a call (`acquire_kvs`'s `#else` form): false. TH1 replaces this body.
_htable_kvs_in_use(kvs::KVS)::Bool = false

# PORT: pl-table.c htable_name
"The name of entry `idx` (0-based) of `kvs`."
htable_name(kvs::KVS, idx::Int)::UInt64 = kvs.entries[idx + 1].name

# PORT: pl-table.c htable_value
"The value of entry `idx` (0-based) of `kvs`."
htable_value(kvs::KVS, idx::Int)::UInt64 = kvs.entries[idx + 1].value

# PORT: pl-table.c htable_cas_name
# DIVERGES: one engine: the compare and swap is a compare and a store.
"Set the name of entry `idx` to `name` when it is `exp`; true when it was."
function htable_cas_name(kvs::KVS, idx::Int, exp::UInt64, name::UInt64)::Bool
    s = kvs.entries[idx + 1]
    s.name == exp || return false
    kvs.entries[idx + 1] = symbol(name, s.value)
    return true
end

# PORT: pl-table.c htable_cas_value
# DIVERGES: one engine: the compare and swap is a compare and a store.
"Set the value of entry `idx` to `value` when it is `exp`; true when it was."
function htable_cas_value(kvs::KVS, idx::Int, exp::UInt64, value::UInt64)::Bool
    s = kvs.entries[idx + 1]
    s.value == exp || return false
    kvs.entries[idx + 1] = symbol(s.name, value)
    return true
end

# PORT: pl-table.c htable_cas_new_kvs
# DIVERGES: one engine: the compare and swap is a compare and a store.
"Chain `new_kvs` after `kvs` when it has no next map; true when it was chained."
function htable_cas_new_kvs(kvs::KVS, new_kvs::KVS)::Bool
    kvs.next === nothing || return false
    kvs.next = new_kvs
    return true
end

# PORT: pl-table.c htable_cas_cleanup
# DIVERGES: one engine: the compare and swap is a compare and a store.
"Set the table's `cleanup` flag to `cleanup` when it is `exp`; true when it was."
function htable_cas_cleanup(ht::Table, exp::Bool, cleanup::Bool)::Bool
    ht.cleanup == exp || return false
    ht.cleanup = cleanup
    return true
end

# PORT: pl-table.c htable_alloc_kvs
"A new, empty key-value map of `len` entries."
function htable_alloc_kvs(len::Int)::KVS
    return KVS(
        len, false, false, 0, nothing, nothing, fill(symbol(NULL_KEY, NULL_VALUE), len)
    )
end

# PORT: pl-table.c htable_free_kvs
# DIVERGES: the entries are freed by the garbage collector; only the unlink of the next map is kept.
"Forget `kvs`: its next map no longer points back at it."
function htable_free_kvs(kvs::KVS)::Nothing
    nxt = kvs.next
    nxt === nothing || (nxt.prev = nothing)
    return nothing
end

# PORT: pl-table.c htable_free_all_kvs
"Forget every map of the table's chain, oldest first."
function htable_free_all_kvs(ht::Table)::Nothing
    kvs = ht.kvs
    while kvs.prev !== nothing
        kvs = kvs.prev::KVS
    end
    cur = kvs
    while true
        next = cur.next
        htable_free_kvs(cur)
        next === nothing && break
        cur = next
    end
    return nothing
end

# PORT: pl-table.c htable_maybe_free_kvs
"Forget the old maps of the chain that nothing uses and that are neither the table's map nor its predecessor."
function htable_maybe_free_kvs(ht::Table)::Nothing
    htable_cas_cleanup(ht, false, true) || return nothing
    kvs = ht.kvs
    while kvs.prev !== nothing
        kvs = kvs.prev::KVS
    end
    cur::Union{Nothing, KVS} = kvs
    while cur !== nothing && cur.accesses == 0 && !_htable_kvs_in_use(cur) &&
          cur !== ht.kvs && cur !== ht.kvs.prev
        next = cur.next
        htable_free_kvs(cur)
        cur = next
    end
    htable_cas_cleanup(ht, true, false)
    return nothing
end

# PORT: pl-table.c htable_copy_kvs
"Move every live entry of `old_kvs` into `new_kvs`, marking the old entries dead (SENTINEL) as it goes."
function htable_copy_kvs(ht::Table, old_kvs::KVS, new_kvs::KVS)::Nothing
    idx = 0
    while idx < old_kvs.len
        n = htable_name(old_kvs, idx)
        v = htable_value(old_kvs, idx)

        while true          # while ( !(n = htable_name(old_kvs, idx)) ) { cas NULL -> SENTINEL }
            n = htable_name(old_kvs, idx)
            n != NULL_KEY && break
            htable_cas_name(old_kvs, idx, NULL_KEY, HTABLE_SENTINEL)
        end

        if n == HTABLE_SENTINEL
            idx += 1
            continue
        end

        while true
            if v != NULL_VALUE && v != HTABLE_TOMBSTONE
                htable_put(ht, new_kvs, n, v, HTABLE_RESIZE)
            end

            if v != NULL_VALUE && htable_cas_value(old_kvs, idx, v, HTABLE_SENTINEL)
                break
            end

            v = htable_value(old_kvs, idx)

            if v == HTABLE_TOMBSTONE
                htable_put(ht, new_kvs, n, v, HTABLE_RESIZE)
            end
        end

        idx += 1
    end
    return nothing
end

# PORT: pl-table.c htable_advance_kvs
# DIVERGES: the CAS on `ht->kvs` is a store (one thread; the precedent: `htable_cas_new_kvs`).
"Make `ht.kvs` the first map that is not completely copied to its successor: operations start at `ht.kvs` and only look forward (pl-table.c)."
function htable_advance_kvs(ht::Table)::Nothing
    while true
        kvs = ht.kvs
        kvs.copied || return nothing
        ht.kvs = kvs.next::KVS                      # COMPARE_AND_SWAP_PTR(&ht->kvs, kvs, kvs->next)
    end
end

# PORT: pl-table.c htable_resize
"Resize the table whose map `kvs` is full or reprobed too often: the new map (`kvs.next` when one exists)."
function htable_resize(ht::Table, kvs::KVS)::KVS
    new_len = kvs.len

    if ht.size >= (kvs.len >> 2)
        new_len = kvs.len << 1
        if ht.size >= (kvs.len >> 1)
            new_len = kvs.len << 2
        end
    elseif kvs.resizing
        new_len = kvs.len << 1
    end

    nxt = kvs.next
    nxt === nothing || return nxt

    new_kvs = htable_alloc_kvs(new_len)
    new_kvs.prev = kvs

    if htable_cas_new_kvs(kvs, new_kvs)
        new_kvs.resizing = true
        htable_copy_kvs(ht, kvs, new_kvs)
        new_kvs.resizing = false

        kvs.copied = true
        htable_advance_kvs(ht)

        htable_maybe_free_kvs(ht)
    else
        htable_free_kvs(new_kvs)
        new_kvs = kvs.next::KVS
    end

    return new_kvs
end

# PORT: pl-table.c htable_get
"The value of `name` in the map `kvs0` (and the maps after it), or `NULL_VALUE`."
function htable_get(ht::Table, kvs0::KVS, name::UInt64)::UInt64
    @assert name != NULL_KEY
    kvs = kvs0
    @label redo
    idx = pointerHashValue(name, kvs.len)
    reprobe_count = 0

    while true
        n = htable_name(kvs, idx)
        v = htable_value(kvs, idx)

        n == NULL_KEY && return NULL_VALUE

        if n == name
            if v == HTABLE_TOMBSTONE
                return NULL_VALUE
            elseif v == HTABLE_SENTINEL
                kvs = kvs.next::KVS
                @goto redo
            else
                return v
            end
        end

        reprobe_count += 1
        if reprobe_count >= (10 + (kvs.len >> 2)) || n == HTABLE_SENTINEL
            nxt = kvs.next
            if nxt !== nothing
                kvs = nxt
                @goto redo
            else
                return NULL_VALUE
            end
        end

        idx = (idx + 1) & (kvs.len - 1)
    end
end

# PORT: pl-table.c htable_put
"Store `value` under `name` in the map `kvs0` (or the map a resize leads to); the previous value, or `value` (see `flags`)."
function htable_put(ht::Table, kvs0::KVS, name::UInt64, value::UInt64, flags::Int)::UInt64
    @assert name != NULL_KEY
    @assert value != NULL_VALUE
    kvs = kvs0
    local idx::Int
    local v::UInt64
    @label redo
    idx = pointerHashValue(name, kvs.len)
    reprobe_count = 0

    while true
        n = htable_name(kvs, idx)
        v = htable_value(kvs, idx)

        if n == NULL_KEY
            value == HTABLE_TOMBSTONE && return value
            if htable_cas_name(kvs, idx, NULL_KEY, name)
                n = name
                break
            end
            n = htable_name(kvs, idx)
            @assert n != NULL_KEY
        end

        if n == name
            break
        end

        reprobe_count += 1
        if reprobe_count >= (10 + (kvs.len >> 2)) || n == HTABLE_SENTINEL
            kvs = htable_resize(ht, kvs)
            @goto redo
        end

        idx = (idx + 1) & (kvs.len - 1)
    end

    value == v && return v

    while true
        if v == HTABLE_SENTINEL
            kvs = kvs.next::KVS
            @goto redo
        end

        if v != NULL_VALUE && v != HTABLE_TOMBSTONE && (flags & HTABLE_PRESERVE) != 0
            return v
        end

        htable_cas_value(kvs, idx, v, value) && break

        v = htable_value(kvs, idx)
    end

    if (flags & HTABLE_NORMAL) != 0
        if (v == NULL_VALUE || v == HTABLE_TOMBSTONE) && value != HTABLE_TOMBSTONE
            ht.size += 1                                    # ATOMIC_INC(&ht->size)
        elseif !(v == NULL_VALUE || v == HTABLE_TOMBSTONE) && value == HTABLE_TOMBSTONE
            ht.size -= 1                                    # ATOMIC_DEC(&ht->size)
        end
    end

    return value == HTABLE_TOMBSTONE ? v : value
end

# PORT: pl-table.c htable_iter
# DIVERGES: `index`, `name` and `value` are not pointers: the next index is returned with the entry, as
# `(found, index, name, value)`; a caller that passed NULL for `name` or `value` ignores that element.
"The next live entry of `kvs` from the 0-based `index` on: `(found, next index, name, value)`."
function htable_iter(
    ht::Table, kvs::KVS, index::Int
)::Tuple{Bool, Int, UInt64, UInt64}
    idx = index
    n = NULL_KEY
    v = NULL_VALUE

    while idx < kvs.len
        n = htable_name(kvs, idx)
        v = htable_value(kvs, idx)
        idx += 1

        if n == NULL_KEY || n == HTABLE_SENTINEL
            continue
        end

        if v == HTABLE_SENTINEL
            v = htable_get(ht, kvs.next::KVS, n)
        end

        if v != NULL_VALUE && v != HTABLE_TOMBSTONE
            break
        end
    end

    if n == HTABLE_SENTINEL || v == HTABLE_TOMBSTONE
        n = NULL_KEY
        v = NULL_VALUE
    end

    return (v != NULL_VALUE, idx, n, v)
end

# PORT: pl-table.c newHTable
# DIVERGES: the hooks are arguments (`nothing`: none), fixed for the table's life (see `Table`).
"A new, empty table of `len` buckets (`len` a power of 2), with the hooks `copy_symbol` and `free_symbol`."
function newHTable(
    len::Int, copy_symbol::CS=nothing, free_symbol::FS=nothing
)::Table{CS, FS} where {CS, FS}
    return Table{CS, FS}(0, false, copy_symbol, free_symbol, htable_alloc_kvs(len))
end

# PORT: pl-table.c destroyHTable
"Clear `ht` (running its `free_symbol` on every entry) and forget its maps."
function destroyHTable(ht::Table)::Nothing
    clearHTable(ht)
    htable_free_all_kvs(ht)
    return nothing
end

# PORT: pl-table.c lookupHTable
"The value of `name` in `ht`, or `NULL_VALUE`."
function lookupHTable(ht::Table, name::UInt64)::UInt64
    kvs = ht.kvs                                    # acquire_kvs(ht, kvs)
    return htable_get(ht, kvs, name)
end

# PORT: pl-table.c addHTable
"Add `name` -> `value` unless `name` has a value; the value of `name` after: `value`, or the existing one."
function addHTable(ht::Table, name::UInt64, value::UInt64)::UInt64
    kvs = ht.kvs                                    # acquire_kvs(ht, kvs)
    return htable_put(ht, kvs, name, value, HTABLE_NORMAL | HTABLE_PRESERVE)
end

# PORT: pl-table.c addNewHTable
# DIVERGES: the warning text is collected on the local data's messages as the other `Sdprintf`s are (`_qlf_Sdprintf!`); the C backtrace
# upstream prints after it (`save_backtrace`/`print_backtrace_named`, os/pl-cstack.c) is the fallback of src/os/pl-cstack.jl: no
# backtrace, one message that C-stack dumps are not supported.
"Add `name` -> `value`, a name the table must not have; a name it has is warned about and updated."
function addNewHTable(
    ld::PL_local_data{T}, ht::Table, name::UInt64, value::UInt64
)::UInt64 where {T}
    new = addHTable(ht, name, value)
    if new == value
        return value
    else
        _qlf_Sdprintf!(
            ld,
            "WARNING: Race condition detected.  Please report at:\n" *
            "WARNING:   https://github.com/SWI-Prolog/swipl-devel/issues\n"
        )
        save_backtrace("addNewHTable")
        print_backtrace_named(ld, "addNewHTable")
        return updateHTable(ht, name, value)
    end
end

# PORT: pl-table.c updateHTable
"Set `name` -> `value`; the value now there (`value`, as `htable_put` returns it, pl-table.c:415)."
function updateHTable(ht::Table, name::UInt64, value::UInt64)::UInt64
    kvs = ht.kvs                                    # acquire_kvs(ht, kvs)
    return htable_put(ht, kvs, name, value, HTABLE_NORMAL)
end

# PORT: pl-table.c deleteHTable
"Delete `name`; its value, or `NULL_VALUE` when it had none."
function deleteHTable(ht::Table, name::UInt64)::UInt64
    kvs = ht.kvs                                    # acquire_kvs(ht, kvs)
    v = htable_put(ht, kvs, name, HTABLE_TOMBSTONE, HTABLE_NORMAL)
    return v == HTABLE_TOMBSTONE ? NULL_VALUE : v
end

# PORT: pl-table.c clearHTable
"Delete every entry of `ht`, calling its `free_symbol` on each."
function clearHTable(ht::Table)::Nothing
    kvs = ht.kvs                                    # acquire_kvs(ht, kvs)
    idx = 0

    while idx < kvs.len
        n = htable_name(kvs, idx)
        v = htable_value(kvs, idx)

        if n == NULL_KEY || n == HTABLE_SENTINEL
            idx += 1
            continue
        end

        if v == HTABLE_SENTINEL
            v = htable_get(ht, kvs.next::KVS, n)
        end

        if v != NULL_VALUE && v != HTABLE_TOMBSTONE
            kvs.entries[idx + 1] = symbol(kvs.entries[idx + 1].name, HTABLE_TOMBSTONE)
            fs = ht.free_symbol
            if fs !== nothing
                fs(n, v)
            end
            ht.size -= 1
        end

        idx += 1
    end
    return nothing
end

# PORT: pl-table.c copyHTable
"A copy of `src_ht`: the same hooks, `copy_symbol` applied to each value, a map of the source's size."
function copyHTable(src_ht::Table)::Table
    src_kvs = src_ht.kvs                            # acquire_kvs(src_ht, src_kvs)
    dest_ht = newHTable(src_kvs.len, src_ht.copy_symbol, src_ht.free_symbol)   # the hooks, as `dest_ht->copy_symbol = ...`
    dest_kvs = dest_ht.kvs

    idx = 0
    while idx < src_kvs.len
        n = htable_name(src_kvs, idx)
        v = htable_value(src_kvs, idx)
        idx += 1

        if n == NULL_KEY || n == HTABLE_SENTINEL
            continue
        end

        if v == HTABLE_SENTINEL
            v = htable_get(src_ht, src_kvs.next::KVS, n)
        end

        if v != NULL_VALUE && v != HTABLE_TOMBSTONE
            cs = src_ht.copy_symbol
            if cs !== nothing
                v = cs(n, v)::UInt64
            end

            htable_put(dest_ht, dest_kvs, n, v, HTABLE_NORMAL)
        end
    end

    return dest_ht
end

# PORT: pl-table.c newTableEnum
"A new enumerator over the table's current map."
function newTableEnum(ht::Table{CS, FS})::TableEnum{CS, FS} where {CS, FS}
    kvs = ht.kvs
    kvs.accesses += 1                               # ATOMIC_INC(&kvs->accesses)
    return TableEnum{CS, FS}(ht, kvs, 0)
end

# PORT: pl-table.c freeTableEnum
"Release the enumerator `e` (a `nothing` is ignored, as a NULL is)."
function freeTableEnum(e::Union{Nothing, TableEnum})::Nothing
    if e !== nothing
        e.kvs.accesses -= 1                         # ATOMIC_DEC(&e->kvs->accesses)
        htable_maybe_free_kvs(e.table)
    end
    return nothing
end

# PORT: pl-table.c advanceTableEnum
# DIVERGES: the name and value are returned, not stored through pointers: `(found, name, value)`.
"The next live entry of the enumerator: `(found, name, value)`."
function advanceTableEnum(e::TableEnum)::Tuple{Bool, UInt64, UInt64}
    found, idx, n, v = htable_iter(e.table, e.kvs, e.idx)
    e.idx = idx
    return (found, n, v)
end

# PORT: pl-table.c sizeofTable
# DIVERGES: the sizes of upstream's structs on a 64-bit machine (`SIZEOF_TABLE` 32 bytes, `SIZEOF_KVS` 48, `SIZEOF_SYMBOL` 16,
# src/pl-incl.jl), not Julia's.
"The memory usage of `ht` in bytes, as upstream counts it."
function sizeofTable(ht::Table)::Int
    return SIZEOF_TABLE + SIZEOF_KVS + ht.kvs.len * SIZEOF_SYMBOL
end

# PORT: pl-table.c PL_new_hash_table
# DIVERGES: no `NEED_LD` (a call without an engine returns false): the callers are Julia code that holds one.
"`PL_new_hash_table(size, free_symbol)`: a new table of `size` buckets whose entries `free_symbol(key, value)` releases."
function PL_new_hash_table(size::Int, free_symbol::FS)::Table{Nothing, FS} where {FS}
    return newHTable(size, nothing, free_symbol)
end

# PORT: pl-table.c PL_free_hash_table
"`PL_free_hash_table(table)`: destroy the table."
function PL_free_hash_table(table::Table)::Bool
    destroyHTable(table)
    return true
end

# PORT: pl-table.c PL_lookup_hash_table
"`PL_lookup_hash_table(table, key)`: the value of `key`, or 0."
PL_lookup_hash_table(table::Table, key::UInt64)::UInt64 = lookupHTable(table, key)

# PORT: pl-table.c PL_add_hash_table
"`PL_add_hash_table(table, key, value, flags)`: add (no flag), add a new key (`PL_HT_NEW`) or update (`PL_HT_UPDATE`)."
function PL_add_hash_table(
    ld::PL_local_data{T}, table::Table, key::UInt64, value::UInt64, flags::Int
)::UInt64 where {T}
    if (flags & (PL_HT_NEW | PL_HT_UPDATE)) == 0
        return addHTable(table, key, value)
    elseif (flags & PL_HT_NEW) != 0
        return addNewHTable(ld, table, key, value)
    else
        return updateHTable(table, key, value)
    end
end

# PORT: pl-table.c PL_del_hash_table
"`PL_del_hash_table(table, key)`: delete `key`; its value or 0."
PL_del_hash_table(table::Table, key::UInt64)::UInt64 = deleteHTable(table, key)

# PORT: pl-table.c PL_clear_hash_table
"`PL_clear_hash_table(table)`: delete every entry."
function PL_clear_hash_table(table::Table)::Bool
    clearHTable(table)
    return true
end

# PORT: pl-table.c PL_new_hash_table_enum
"`PL_new_hash_table_enum(table)`: an enumerator."
PL_new_hash_table_enum(table::Table{CS, FS}) where {CS, FS} = newTableEnum(table)

# PORT: pl-table.c PL_free_hash_table_enum
"`PL_free_hash_table_enum(e)`: release an enumerator."
PL_free_hash_table_enum(e::Union{Nothing, TableEnum})::Nothing = freeTableEnum(e)

# PORT: pl-table.c PL_advance_hash_table_enum
# DIVERGES: the key and value are returned: `(found, key, value)` (see `advanceTableEnum`).
"`PL_advance_hash_table_enum(e)`: the next entry, `(found, key, value)`."
PL_advance_hash_table_enum(e::TableEnum)::Tuple{Bool, UInt64, UInt64} = advanceTableEnum(e)
