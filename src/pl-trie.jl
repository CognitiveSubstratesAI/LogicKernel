# UPSTREAM: swipl-devel src/pl-trie.c @ 18168e629eab
# UPSTREAM: swipl-devel src/pl-trie.h @ 18168e629eab
# UPSTREAM: swipl-devel src/pl-indirect.c @ 18168e629eab
# UPSTREAM: swipl-devel src/pl-tabling.c @ 18168e629eab
# CLASS: code
# COPYRIGHT: Copyright (c)  2016-2025, VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
# allow-new-artifact: a 1:1 port of swipl-devel src/pl-trie.c (the upstream file was read at the pin; the design and the line ranges are in evidence/TAB1/tr1_partA_status.md and tr1_state.md)
# PIN1 ledger (V10.1.20): pl-trie.c at 18168e62 (the first port: no earlier pin).
# TRIES (pl-trie.c), TAB1 step TR1, part A: the trie, its children blocks, its node allocation and its life, the indirect table,
# the lookup and the statistics. This file holds, in the order of pl-trie.c: the reserved keys, `trie_create`, `trie_destroy`,
# `trie_empty`, `trie_empty_take`, `trie_clean`, the children (`get_child`, `next_child!`, `is_leaf_trie_node`,
# `trie_single_value_node`), the blocks (`block_find` ... `delete_child`), the node allocation and the chunks, `clear_node`,
# `prune_node`, `prune_trie`, `insert_child`, `follow_node`, `prune_error`, the indirect table (`new_indirect_table`,
# `intern_indirect`, `trie_intern_indirect`), the lookup (`trie_lookup_abstract`, `trie_lookup_flat`, `trie_insert_flat`), the
# walk and the statistics (`is_ground_trie_node`, `map_trie_node`, `stat_trie`, `trie_table_size`), and the trie blob
# (`trie_blob`, `initTries!`, `trie_symbol`, `symbol_trie`, `get_trie`, `trie_error`). The PRED_IMPLs and the value helpers are part B.
#
# REPRESENTATION (DIVERGES, audit D-0453 Q3, owner TR1): a node, a children block and a node chunk are Julia records; a node
# is named by its id in `trie.nodes` (id 1 is the root; 0 is upstream's NULL), a block by its id in `trie.blocks`, and
# `trie_node.children` holds 0, `(id<<1)|1` (a single child: upstream's TRIE_SINGLE_CHILD tag) or `bid<<1` (a block).
# `trie_node.parent` is a node id. A freed chunk node stays in the arena on the head chunk's free list (linked through
# `parent` as upstream); a freed individual node's id goes on `trie.free_ids`. The positions in a block are 1-based, and
# `block_find` returns 0 where upstream returns -1.
#
# DIVERGES (audit D-0453 Q5, owner TR1): the kernel has no atom reference counts and no atom garbage collector (atoms live
# for ever), so `acquire_key`, `release_key`, `mark_new_key`, `register_chunk_keys`, `release_chunk_keys`, `markAtomsInTries`,
# `freeZombieTrieChunks` and the global chunk list (`link_chunk`, `unlink_chunk`, `gprev`, `gnext`, CHUNK_ZOMBIE handling)
# are left out: the chunk bookkeeping that stays (`used`, `live`, `free`, `nfree`, `sweep_at`, `bytes`) is what the free-list
# discipline and the sizes the oracle observes (`stat_trie`) need. No write locking: `lock_children` and `unlock_children`
# are left out (single-threaded, owner TH1); the TRIE_CONCURRENT flag is kept because it decides how nodes are allocated
# (individually, no chunks: `trie_new/1` sets it) and whether a replaced block lingers (`trie.lingering`).
# Refused by name: `tbl_release_node` (owner TB1), the discarded nodes of a compiled trie (`trie_discard_nodes`,
# `trie_restore_nodes`, `trie_ensure_nodes`, a clause: owner TR4), O_PLMT regions (owner TH1).

# PORT: pl-trie.c RESERVED_TRIE_VAL
"A reserved trie key `n` (pl-trie.c `RESERVED_TRIE_VAL`)."
RESERVED_TRIE_VAL(n::Integer)::word = consTagged(n, TAGEX_TRIE_RESERVED)
# PORT: pl-trie.c TRIE_ERROR_VAL
"The key that marks a node to prune after an error (pl-trie.c)."
const TRIE_ERROR_VAL = RESERVED_TRIE_VAL(1)
# PORT: pl-trie.c TRIE_KEY_ABSENT
"The key of no stored value (pl-trie.c)."
const TRIE_KEY_ABSENT = RESERVED_TRIE_VAL(2)
# PORT: pl-trie.c TRIE_KEY_POP
"The key that pops `n` levels (pl-trie.c `TRIE_KEY_POP`)."
TRIE_KEY_POP(n::Integer)::word = RESERVED_TRIE_VAL(10 + n)
# PORT: pl-trie.c IS_TRIE_KEY_POP
"The number of levels a pop key `w` pops, or 0 when `w` is no pop key (pl-trie.c `IS_TRIE_KEY_POP`)."
IS_TRIE_KEY_POP(w::word)::Int =
    (tagex(w) == TAGEX_TRIE_RESERVED && valTagged(w) > 10) ? Int(valTagged(w)) - 10 : 0
# PORT: pl-trie.c NVARS_FAST
"The number of variables the lookup holds in its fast buffer (pl-trie.c); the lookup grows a vector here."
const NVARS_FAST = 100

# PORT: pl-trie.h CHUNK_ZOMBIE
"`trie_node_chunk.flags`: freed during atom-GC (pl-trie.h); never set here (no atom-GC)."
const CHUNK_ZOMBIE = UInt16(0x1)
# PORT: pl-trie.h CHUNK_REGISTERED
"`trie_node_chunk.flags`: the nodes registered their keys (pl-trie.h); never set here (no atom reference counts)."
const CHUNK_REGISTERED = UInt16(0x2)

# PORT: pl-trie.c CN_DEALLOC
"`clear_node` flag: free the node (pl-trie.c)."
const CN_DEALLOC = 0x1
# PORT: pl-trie.c CN_ALL
"`clear_node` flag: the trie is cleared (pl-trie.c)."
const CN_ALL = 0x2
# PORT: pl-trie.c TRIE_LINEAR_MAX
"Blocks of up to this many entries are searched linearly (pl-trie.c)."
const TRIE_LINEAR_MAX = 8
# PORT: pl-trie.c VMASKBITS
"The bits of a variable mask (pl-trie.c)."
const VMASKBITS = 32
# PORT: pl-trie.c VMASK_SCAN
"The variable-mask bit that stands for every variable number from `VMASKBITS` on (pl-trie.c)."
const VMASK_SCAN = UInt32(1) << (VMASKBITS - 1)
# PORT: pl-trie.c TRIE_SINGLE_NODES
"The first nodes of a trie without chunks are allocated individually (pl-trie.c)."
const TRIE_SINGLE_NODES = 8
# PORT: pl-trie.c TRIE_CHUNK_MIN
"The bytes of the first chunk (pl-trie.c)."
const TRIE_CHUNK_MIN = 1024
# PORT: pl-trie.c TRIE_CHUNK_MAX
"The most bytes of a chunk (pl-trie.c)."
const TRIE_CHUNK_MAX = 16384
# PORT: pl-trie.c TRIE_SWEEP_MIN
"The fewest free nodes at which a sweep of the chunks starts (pl-trie.c)."
const TRIE_SWEEP_MIN = 1024

# ORIGINAL (named refusals of TR1): the error of a function this step leaves to the step that owns it. A refusal is an
# exception of this type naming the function and its owner, never a wrong answer.
"The error of a named refusal: `what` is the function left out and `owner` the step that owns it."
struct TrieRefusal <: Exception
    what::String
    owner::String
end

# PORT: pl-trie.h trie_has_children
"Whether the node `n` has children (pl-trie.h `trie_has_children`)."
trie_has_children(n::trie_node)::Bool = n.children != 0

# ORIGINAL: upstream's `TRIE_SINGLE_CHILD` tag and `single_child` / `children_block` casts (pl-trie.c is_single_child).
"Whether the children code `c` is a single child (pl-trie.c `is_single_child`)."
is_single_child(c::Int)::Bool = (c & 1) != 0
"The node id of the single child coded `c` (pl-trie.c `single_child`)."
single_child(c::Int)::Int = c >> 1
"The children code of the single child `id` (pl-trie.c: `child|TRIE_SINGLE_CHILD`)."
single_child_code(id::Int)::Int = (id << 1) | 1
"The block id of the block coded `c` (pl-trie.c `children_block`)."
children_block_id(c::Int)::Int = c >> 1
"The children code of the block `bid`."
block_code(bid::Int)::Int = bid << 1

# ORIGINAL: the arena accessors (upstream dereferences a pointer).
"The block `bid` of `tr`."
@inline block_at(tr::trie{T}, bid::Int)::trie_children_block where {T} =
    tr.blocks[bid]::trie_children_block

# ---- THE TRIE (trie_create, trie_destroy, trie_empty) ----

# PORT: pl-trie.c trie_create
# DIVERGES: the term type is the argument and there is no allocation pool (`alloc_pool`, TH1); the root is node 1.
"A new, empty trie of terms `T` (pl-trie.c)."
function trie_create(::Type{T})::trie{T} where {T}
    root = trie_node(UInt64(0), UInt64(0), 0, 0, UInt32(0), nothing)
    return trie{T}(
        UInt64(0), TRIE_MAGIC, 0, 1, 0, UInt32(0),             # symbol, magic, references, node_count (the root), value_count, flags
        trie_node[root], Union{Nothing, trie_children_block}[], Int[], Int[],
        nothing, UInt64(0), nothing, Int[],                     # indirects, clause, chunks, lingering
        0, 0, nothing, 0, nothing, nothing, 0,                  # lookups, gen_call, worklist, variant, IDG, predicate, serial
        Union{Nothing, record{T}}[], Int[]                      # records, free_records
    )
end

# PORT: pl-trie.c release_node
# DIVERGES: the node is a node id.
"Release the tabling data of node `nid` of `tr` (pl-trie.c `release_node`)."
function release_node(tr::trie{T}, nid::Int)::Nothing where {T}
    n = tr.nodes[nid]
    if (tr.flags & TRIE_ISTABLE) != 0 ? (n.flags & TN_DELAYINFO) != 0 :
       (tr.flags & TRIE_ISVARIANT) != 0
        tbl_release_node(tr, nid)
    end
    return nothing
end

# PORT: pl-tabling.c tbl_release_node
# DIVERGES: refused by name, owner TB1 (the tabling data of a node: the delay information, the variant table's answer trie).
# Reached only by a trie that is TRIE_ISTABLE (a node with TN_DELAYINFO) or TRIE_ISVARIANT: none exists before TB1.
"Release the tabling data of a node (pl-tabling.c): refused by name, owner TB1."
tbl_release_node(tr::trie{T}, nid::Int) where {T} =
    throw(TrieRefusal("tbl_release_node", "TB1"))

# PORT: pl-trie.c release_value
# DIVERGES: the trie is an argument (a record is a slot of `tr.records`, see `isRecord`); upstream unregisters an atom (no atom
# reference counts here: nothing to do), erases a record (`erase_value!`) and releases the answer trie of a variant table node
# (`isTriePtrValue`: TB1, no such value exists before it).
"Release the value `value` of a node of `tr` (pl-trie.c `release_value`): a record is erased, an atom or integer needs nothing."
function release_value(tr::trie{T}, value::word)::Nothing where {T}
    isRecord(value) && erase_value!(tr, value)
    return nothing
end

# PORT: pl-trie.c trie_discard_clause
# DIVERGES: a trie has no compiled clause before TR4, so `trie.clause` is always 0; a clause is refused by name (owner TR4).
"Discard the clause of a trie (pl-trie.c); refused by name (owner TR4) when there is one."
function trie_discard_clause(tr::trie{T})::Nothing where {T}
    tr.clause == 0 || throw(TrieRefusal("trie_discard_clause (a compiled clause)", "TR4"))
    return nothing
end

# PORT: pl-trie.c trie_discard_nodes
"Discard the nodes of a compiled trie (pl-trie.c): refused by name, owner TR4."
trie_discard_nodes(tr::trie{T}) where {T} = throw(TrieRefusal("trie_discard_nodes", "TR4"))

# PORT: pl-trie.c trie_restore_nodes
"Restore the nodes of a discarded trie from its clause (pl-trie.c): refused by name, owner TR4."
trie_restore_nodes(tr::trie{T}) where {T} = throw(TrieRefusal("trie_restore_nodes", "TR4"))

# PORT: pl-trie.c trie_ensure_nodes
# DIVERGES: a discarded trie cannot exist before TR4 (`TRIE_DISCARDED` is never set); the restore is refused by name.
"Make sure the nodes of `tr` are present (pl-trie.c); a discarded trie is refused by name (owner TR4)."
function trie_ensure_nodes(tr::trie{T})::Bool where {T}
    (tr.flags & TRIE_DISCARDED) != 0 && trie_restore_nodes(tr)
    return true
end

# PORT: pl-trie.c clear_nodes
# DIVERGES: after `clear_node` (CN_ALL) the arenas are reset: the root stays as node 1, the other nodes and the blocks go.
"Clear all nodes of `tr`; `vt` (or `nothing`) takes over the values (pl-trie.c `clear_nodes`)."
function clear_nodes(tr::trie{T}, vt::Union{Nothing, Function})::Nothing where {T}
    clear_node(tr, 1, CN_ALL, vt)
    free_lingering_blocks(tr)
    free_node_chunks(tr)
    tr.indirects = nothing                                      # destroy_indirect_table
    resize!(tr.nodes, 1)                                        # the arenas: nothing of the nodes is kept
    empty!(tr.free_ids)
    empty!(tr.blocks)
    empty!(tr.free_blocks)
    if vt === nothing                                           # (a taker keeps the records of the values it took)
        empty!(tr.records)
        empty!(tr.free_records)
    end
    tr.node_count = 1
    return nothing
end

# PORT: pl-trie.c trie_clear_nodes
"Clear all nodes of `tr` (pl-trie.c)."
trie_clear_nodes(tr::trie{T}) where {T} = clear_nodes(tr, nothing)

# PORT: pl-trie.c empty_trie
"Empty `tr` unless it is in use; whether it was emptied (pl-trie.c `empty_trie`)."
function empty_trie(tr::trie{T}, vt::Union{Nothing, Function})::Bool where {T}
    trie_discard_clause(tr)
    if tr.references == 0
        clear_nodes(tr, vt)
        tr.value_count = 0
        tr.flags &= ~(TRIE_DISCARDABLE | TRIE_DISCARDED)
        return true
    end
    return false
end

# PORT: pl-trie.c trie_empty
"Empty `tr` (pl-trie.c)."
function trie_empty(tr::trie{T})::Nothing where {T}
    empty_trie(tr, nothing)
    return nothing
end

# PORT: pl-trie.c trie_empty_take
# DIVERGES: `take` is a function of the value (upstream: a function and a context pointer).
"As `trie_empty`, but pass each value to `take(value)`, which takes over its reference; false if `tr` is in use (pl-trie.c)."
trie_empty_take(tr::trie{T}, take::Function)::Bool where {T} = empty_trie(tr, take)

# PORT: pl-trie.c trie_destroy
# DIVERGES: nothing frees the record (Julia's garbage collector); the trie stays in `gd.tries` (no atom-GC), marked destroyed.
"Destroy `tr`: mark it destroyed, empty it and free its lingering blocks (pl-trie.c)."
function trie_destroy(tr::trie{T})::Nothing where {T}
    tr.magic = TRIE_CMAGIC
    trie_empty(tr)
    free_lingering_blocks(tr)
    return nothing
end

# PORT: pl-trie.c trie_clean
"Empty `tr` if it is destroyed (pl-trie.c)."
function trie_clean(tr::trie{T})::Nothing where {T}
    tr.magic == TRIE_CMAGIC && trie_empty(tr)
    return nothing
end

# ---- CHILDREN (get_child, next_child!, is_leaf_trie_node) ----

# PORT: pl-trie.c child_hash
"The slot a block with `bits` index bits starts the search for `key` at, 0-based (pl-trie.c)."
@inline child_hash(key::word, bits::Int)::Int = Int((UInt64(key) * 0x9e3779b97f4a7c15) >> (64 - bits))

# PORT: pl-trie.c block_size
"The bytes upstream's block of `capacity` entries and `index_bits` index bits takes (pl-trie.c `block_size`)."
function block_size(capacity::Int, index_bits::Int)::Int
    size = SIZEOF_TRIE_CHILDREN_BLOCK + capacity * SIZEOF_TRIE_CHILD
    index_bits != 0 && (size += (1 << index_bits) * sizeof(UInt32))
    return size
end

# PORT: pl-trie.c sizeof_block
"The bytes upstream's block `b` takes (pl-trie.c `sizeof_block`)."
sizeof_block(b::trie_children_block)::Int = block_size(b.capacity, b.index_bits)

# PORT: pl-trie.c block_find
# DIVERGES: the position is 1-based and 0 stands for upstream's -1.
"The position of the entry for `key` in `b`, or 0 (pl-trie.c)."
function block_find(b::trie_children_block, key::word)::Int
    if b.index_bits == 0
        for i in 1:b.count
            b.entries[i].key == key && return i
        end
    else
        mask = (1 << b.index_bits) - 1
        h = child_hash(key, b.index_bits)
        while true
            pos = Int(b.index[h + 1])
            pos == 0 && break
            b.entries[pos].key == key && return pos
            h = (h + 1) & mask
        end
    end
    return 0
end

# PORT: pl-trie.c get_child
# DIVERGES: the node and the result are node ids (0: none).
"The child of node `nid` with key `key`, or 0 (pl-trie.c)."
function get_child(tr::trie{T}, nid::Int, key::word)::Int where {T}
    c = tr.nodes[nid].children
    c == 0 && return 0
    if is_single_child(c)
        child = single_child(c)
        return tr.nodes[child].key == key ? child : 0
    else
        b = block_at(tr, children_block_id(c))
        pos = block_find(b, key)
        return pos > 0 ? b.entries[pos].child : 0
    end
end

# PORT: pl-trie.c child_iter
"An iterator over the children of a node (pl-trie.c `child_iter`): `pos` is the number of entries it has passed."
mutable struct child_iter
    parent::Int
    pos::Int
end

# PORT: pl-trie.c init_child_iter
"A new iterator over the children of node `parent` (pl-trie.c `init_child_iter`)."
init_child_iter(parent::Int)::child_iter = child_iter(parent, 0)

# PORT: pl-trie.c next_child
# DIVERGES: returns `(child id, key)`, `(0, 0)` at the end (upstream returns the node or NULL and writes `*keyp`).
"The next child of the iterator `it` and its key, `(0, 0)` at the end (pl-trie.c)."
function next_child!(tr::trie{T}, it::child_iter)::Tuple{Int, word} where {T}
    c = tr.nodes[it.parent].children
    c == 0 && return (0, UInt64(0))
    if is_single_child(c)
        p = it.pos
        it.pos += 1
        if p == 0
            child = single_child(c)
            return (child, tr.nodes[child].key)
        end
    else
        b = block_at(tr, children_block_id(c))
        count = b.count
        while it.pos < count
            it.pos += 1
            e = b.entries[it.pos]
            e.child != 0 && return (e.child, e.key)
        end
    end
    return (0, UInt64(0))
end

# PORT: pl-trie.c is_leaf_trie_node
"Whether node `nid` has no live children (pl-trie.c)."
function is_leaf_trie_node(tr::trie{T}, nid::Int)::Bool where {T}
    c = tr.nodes[nid].children
    if c != 0 && !is_single_child(c)
        b = block_at(tr, children_block_id(c))
        return b.count == b.dead
    end
    return c == 0
end

# PORT: pl-trie.c trie_single_value_node
# DIVERGES: returns a node id (0: NULL).
"The node holding the value of a trie with exactly one value, or 0 (pl-trie.c)."
function trie_single_value_node(tr::trie{T})::Int where {T}
    n = 1
    tr.value_count != 1 && return 0
    while tr.nodes[n].value == 0
        c = tr.nodes[n].children
        is_single_child(c) || return 0
        n = single_child(c)
    end
    return n
end

# ---- BLOCKS (new_block, block_append, add_child, delete_child) ----

# PORT: pl-trie.c free_block
"Free the block `bid` (pl-trie.c `free_block`): its slot is reused."
function free_block(tr::trie{T}, bid::Int)::Nothing where {T}
    tr.blocks[bid] = nothing
    push!(tr.free_blocks, bid)
    return nothing
end

# PORT: pl-trie.c retire_block
# DIVERGES: the lingering list is `trie.lingering`, a vector of block ids; no atomics.
"A block was replaced in its node: free it, or keep it lingering in a TRIE_CONCURRENT trie (pl-trie.c)."
function retire_block(tr::trie{T}, bid::Int)::Nothing where {T}
    if (tr.flags & TRIE_CONCURRENT) != 0
        push!(tr.lingering, bid)
    else
        free_block(tr, bid)
    end
    return nothing
end

# PORT: pl-trie.c free_lingering_blocks
"Free the lingering blocks of a TRIE_CONCURRENT trie (pl-trie.c)."
function free_lingering_blocks(tr::trie{T})::Nothing where {T}
    (tr.flags & TRIE_CONCURRENT) == 0 && return nothing
    for bid in tr.lingering
        free_block(tr, bid)
    end
    empty!(tr.lingering)
    return nothing
end

# PORT: pl-trie.c new_block
# DIVERGES: returns the id of the new block in `tr.blocks`.
"A new, empty block of `capacity` entries in `tr`; its id (pl-trie.c)."
function new_block(tr::trie{T}, capacity::Int)::Int where {T}
    bits = capacity <= TRIE_LINEAR_MAX ? 0 : MSB(capacity) + 1
    b = trie_children_block(
        0, capacity, 0, UInt32(0), UInt32(0), bits,
        fill(trie_child(UInt64(0), 0), capacity),
        bits == 0 ? UInt32[] : zeros(UInt32, 1 << bits)
    )
    if isempty(tr.free_blocks)
        push!(tr.blocks, b)
        return length(tr.blocks)
    end
    bid = pop!(tr.free_blocks)
    tr.blocks[bid] = b
    return bid
end

# PORT: pl-trie.c update_var_mask
"Record the variable number of the key `key` in the masks of `b` (pl-trie.c)."
function update_var_mask(b::trie_children_block, key::word)::Nothing
    tx = tagex(key)
    if tx == TAGEX_VAR
        vn = valTagged(key)                                     # 1..
        b.var_mask |= vn < VMASKBITS ? UInt32(1) << (vn - 1) : VMASK_SCAN
    elseif tx == TAGEX_TRIE_ATTVAR
        vn = valTagged(key)
        b.attvar_mask |= vn < VMASKBITS ? UInt32(1) << (vn - 1) : VMASK_SCAN
    end
    return nothing
end

# PORT: pl-trie.c index_entry
# DIVERGES: `pos` is 1-based and the slot holds it as is (0: empty).
"Enter the entry at position `pos` of `b` in its index (pl-trie.c)."
function index_entry(b::trie_children_block, pos::Int)::Nothing
    mask = (1 << b.index_bits) - 1
    h = child_hash(b.entries[pos].key, b.index_bits)
    while b.index[h + 1] != 0
        h = (h + 1) & mask
    end
    b.index[h + 1] = UInt32(pos)
    return nothing
end

# PORT: pl-trie.c block_append
"Append an entry to `b`; the caller ensures there is space (pl-trie.c)."
function block_append(b::trie_children_block, key::word, child::Int)::Nothing
    pos = b.count + 1
    b.entries[pos] = trie_child(key, child)
    update_var_mask(b, key)
    b.index_bits != 0 && index_entry(b, pos)
    b.count = pos
    return nothing
end

# PORT: pl-trie.c block_copy
"Copy the entries of `from` to the new block `to`: with `compact` false they keep their position, else dead ones go (pl-trie.c)."
function block_copy(to::trie_children_block, from::trie_children_block, compact::Bool)::Nothing
    if !compact
        copyto!(to.entries, 1, from.entries, 1, from.count)
        to.count = from.count
        to.dead = from.dead
        to.var_mask = from.var_mask
        to.attvar_mask = from.attvar_mask
        if to.index_bits != 0
            for i in 1:to.count
                index_entry(to, i)
            end
        end
    else
        for i in 1:from.count
            e = from.entries[i]
            e.child != 0 && block_append(to, e.key, e.child)
        end
    end
    return nothing
end

# PORT: pl-trie.c add_child
# DIVERGES: nodes are ids; no write lock; there is no resource error, so it always returns true.
"Add the node `child` to node `nid`, which has no live child with the same key (pl-trie.c)."
function add_child(tr::trie{T}, nid::Int, child::Int)::Bool where {T}
    n = tr.nodes[nid]
    c = n.children
    key = tr.nodes[child].key
    if c == 0
        n.children = single_child_code(child)
    elseif is_single_child(c)
        old = single_child(c)
        bid = new_block(tr, 2)
        b = block_at(tr, bid)
        block_append(b, tr.nodes[old].key, old)
        block_append(b, key, child)
        n.children = block_code(bid)
    else
        bid = children_block_id(c)
        b = block_at(tr, bid)
        pos = 0
        if b.dead != 0 && (pos = block_find(b, key)) > 0
            b.entries[pos] = trie_child(key, child)             # revive the entry
            b.dead -= 1
        elseif b.count == b.capacity
            nbid = new_block(tr, b.capacity * 2)
            nb = block_at(tr, nbid)
            block_copy(nb, b, false)
            block_append(nb, key, child)
            n.children = block_code(nbid)
            retire_block(tr, bid)
        else
            block_append(b, key, child)
        end
    end
    return true
end

# PORT: pl-trie.c replace_block
"Replace the block `bid` of node `nid` by a compacted one, a single child or nothing (pl-trie.c)."
function replace_block(tr::trie{T}, nid::Int, bid::Int)::Nothing where {T}
    n = tr.nodes[nid]
    b = block_at(tr, bid)
    live = b.count - b.dead
    if live == 0
        n.children = 0
    elseif live == 1
        for i in 1:b.count
            if b.entries[i].child != 0
                n.children = single_child_code(b.entries[i].child)
                break
            end
        end
    else
        capacity = 2
        while capacity < live
            capacity *= 2
        end
        nbid = new_block(tr, capacity)
        block_copy(block_at(tr, nbid), b, true)
        n.children = block_code(nbid)
    end
    retire_block(tr, bid)
    return nothing
end

# PORT: pl-trie.c compact_children
# DIVERGES: no write lock.
"Compact the children of node `nid` if many of them are deleted (pl-trie.c)."
function compact_children(tr::trie{T}, nid::Int)::Nothing where {T}
    c = tr.nodes[nid].children
    if c != 0 && !is_single_child(c)
        bid = children_block_id(c)
        b = block_at(tr, bid)
        if b.dead == b.count || b.dead * 2 > b.count
            replace_block(tr, nid, bid)
        end
    end
    return nothing
end

# PORT: pl-trie.c delete_child
# DIVERGES: no write lock; nodes are ids.
"Delete `child` from its parent `pid`, compacting the block if `compact` and many are deleted; true if `pid` has no children left (pl-trie.c)."
function delete_child(tr::trie{T}, pid::Int, child::Int, compact::Bool)::Bool where {T}
    p = tr.nodes[pid]
    c = p.children
    empty = true
    if c != 0
        if is_single_child(c)
            if single_child(c) == child
                p.children = 0
            else
                empty = false
            end
        else
            bid = children_block_id(c)
            b = block_at(tr, bid)
            key = tr.nodes[child].key
            pos = block_find(b, key)
            if pos > 0 && b.entries[pos].child == child
                b.entries[pos] = trie_child(key, 0)
                b.dead += 1
            end
            empty = (b.dead == b.count)
            if compact && (empty || b.dead * 2 > b.count)
                replace_block(tr, pid, bid)
            end
        end
    end
    return empty
end

# ---- NODE ALLOCATION (alloc_trie_node, new_trie_node, free_trie_node, sweep_node_chunks) ----
# Upstream allocates the nodes of a trie without concurrent writers from chunks that grow geometrically, the first
# TRIE_SINGLE_NODES individually; a deleted chunk node is kept on a free list, the chunks of the list that hold no node in
# use are freed by a sweep. A TRIE_CONCURRENT trie allocates every node individually. The model is kept (the sizes the oracle
# observes: `stat_trie`, and the free-list discipline), over the arena: an individual node is a slot of `trie.nodes`
# (a freed one: its id on `trie.free_ids`), a chunk node is a slot too and is recycled through the head chunk's free list.

# ORIGINAL: upstream takes a node from the pool; here a slot of the arena: a freed id, else a new one at the end.
"The id of a new slot of `tr.nodes` holding `n`."
function new_node_slot!(tr::trie{T}, n::trie_node)::Int where {T}
    if isempty(tr.free_ids)
        push!(tr.nodes, n)
        return length(tr.nodes)
    end
    id = pop!(tr.free_ids)
    tr.nodes[id] = n
    return id
end

# PORT: pl-trie.c alloc_trie_node
# DIVERGES: returns `(id, chunk, bump)`: `id` is the id of a recycled chunk node (a slot already of the arena), or 0 for
# "a new slot" (`new_trie_node` makes it); `chunk` is `nothing` for an individual node; `bump` says a new node in `chunk`
# (upstream's out parameters `*cp` and `*bump`).
"Allocate a node of `tr`: `(id or 0, chunk or nothing, bump)` (pl-trie.c `alloc_trie_node`)."
function alloc_trie_node(
    tr::trie{T}
)::Tuple{Int, Union{Nothing, trie_node_chunk}, Bool} where {T}
    (tr.flags & TRIE_CONCURRENT) != 0 && return (0, nothing, false)
    c = tr.chunks
    if c !== nothing
        if c.free != 0
            id = c.free
            n = tr.nodes[id]
            c.free = n.parent
            c.nfree -= 1
            cc = n.chunk::trie_node_chunk                       # node_chunk(n)
            cc.live += 1
            return (id, cc, false)
        end
        if c.used < c.size
            c.live += 1
            return (0, c, true)
        end
    elseif tr.node_count <= TRIE_SINGLE_NODES
        return (0, nothing, false)
    end
    bytes = c !== nothing ? Int(c.bytes) * 2 : TRIE_CHUNK_MIN
    bytes > TRIE_CHUNK_MAX && (bytes = TRIE_CHUNK_MAX)
    nc = trie_node_chunk(
        c, 0, UInt16(0), UInt16(0), UInt32(bytes),
        UInt32((bytes - OFFSETOF_TRIE_NODE_CHUNK_NODES) ÷ SIZEOF_TRIE_NODE),
        UInt32(0), UInt32(1), UInt32(0),                         # used, live, nfree
        c !== nothing ? c.sweep_at : UInt32(TRIE_SWEEP_MIN)
    )
    tr.chunks = nc
    return (0, nc, true)
end

# PORT: pl-trie.c new_trie_node
# DIVERGES: returns the node's id; `acquire_key` and `mark_new_key` are left out (no atom reference counts).
"A new node with key `key` in `tr`; its id (pl-trie.c)."
function new_trie_node(tr::trie{T}, key::word)::Int where {T}
    id, c, bump = alloc_trie_node(tr)
    tr.node_count += 1
    if c === nothing
        n = trie_node(UInt64(0), key, 0, 0, UInt32(0), nothing)
    else
        idx = bump ? Int(c.used) : Int(tr.nodes[id].flags >> TN_CHUNK_INDEX_SHIFT)
        n = trie_node(
            UInt64(0), key, 0, 0, TN_CHUNKED | (UInt32(idx) << TN_CHUNK_INDEX_SHIFT), c
        )
        bump && (c.used = UInt32(idx + 1))
    end
    if id == 0
        id = new_node_slot!(tr, n)
    else
        tr.nodes[id] = n
    end
    return id
end

# PORT: pl-trie.c free_trie_node
# DIVERGES: the node is an id; the key is not released (no atom reference counts); an individual node's id goes on `free_ids`.
"Free the node `nid` of `tr` (pl-trie.c)."
function free_trie_node(tr::trie{T}, nid::Int)::Nothing where {T}
    n = tr.nodes[nid]
    if (n.flags & TN_CHUNKED) != 0
        c = n.chunk::trie_node_chunk
        head = tr.chunks::trie_node_chunk
        n.key = 0                                               # do not mark it
        c.live -= 1
        n.parent = head.free
        head.free = nid
        head.nfree += 1
        if head.nfree >= head.sweep_at && head.nfree > tr.node_count
            sweep_node_chunks(tr)
        end
    else
        push!(tr.free_ids, nid)
    end
    return nothing
end

# PORT: pl-trie.c free_node_chunks
# DIVERGES: nothing is freed (Julia's garbage collector); the chunks are dropped. `clear_nodes` resets the arena.
"Drop the chunks of a trie that is cleared (pl-trie.c `free_node_chunks`)."
function free_node_chunks(tr::trie{T})::Nothing where {T}
    (tr.flags & TRIE_CONCURRENT) != 0 && return nothing
    tr.chunks = nothing
    return nothing
end

# PORT: pl-trie.c sweep_node_chunks
# DIVERGES: `free_chunk_list` is left out (the dropped chunks go to the garbage collector); the ids of the nodes of a dropped
# chunk (every one is on the free list, as its chunk has no live node) go on `trie.free_ids`.
"Drop the chunks of `tr` that have no nodes in use, the newest excepted (pl-trie.c)."
function sweep_node_chunks(tr::trie{T})::Nothing where {T}
    head = tr.chunks::trie_node_chunk
    keep = 0
    kept = 0
    id = head.free
    while id != 0
        n = tr.nodes[id]
        nnext = n.parent
        c = n.chunk::trie_node_chunk
        if c.live == 0 && c !== head
            push!(tr.free_ids, id)                              # its chunk goes
        else
            n.parent = keep
            keep = id
            kept += 1
        end
        id = nnext
    end
    head.free = keep
    head.nfree = UInt32(kept)
    head.sweep_at = UInt32(kept * 2 > TRIE_SWEEP_MIN ? kept * 2 : TRIE_SWEEP_MIN)

    prev = head
    c = head.next
    while c !== nothing
        next = c.next
        if c.live == 0
            prev.next = next
        else
            prev = c
        end
        c = next
    end
    return nothing
end

# ---- CLEARING AND PRUNING (clear_node, destroy_node, prune_node, prune_trie) ----

# PORT: pl-trie.c clear_node
# DIVERGES: `vt` is a function of the value (upstream: a `value_taker`); the node is an id; an iteration where upstream uses
# `goto next`. The keys are not released (no atom reference counts).
"Clear node `nid` and its descendants; with CN_ALL the whole trie is cleared (pl-trie.c)."
function clear_node(
    tr::trie{T}, nid::Int, flags::Int, vt::Union{Nothing, Function}
)::Nothing where {T}
    while true
        n = tr.nodes[nid]
        children = n.children
        if vt !== nothing
            if n.value != 0
                vt(n.value)                                     # takes over the value
                n.value = 0
            end
        else
            release_node(tr, nid)
        end
        n.value != 0 && release_value(tr, n.value)
        if (flags & CN_DEALLOC) != 0
            tr.node_count -= 1
            if (flags & CN_ALL) == 0 || (n.flags & TN_CHUNKED) == 0
                free_trie_node(tr, nid)
            end
        else
            n.children = 0
            n.flags &= ~(TN_PRIMARY | TN_SECONDARY)
        end
        children == 0 && return nothing
        if is_single_child(children)
            nid = single_child(children)
            flags |= CN_DEALLOC
        else
            bid = children_block_id(children)
            b = block_at(tr, bid)
            for i in 1:b.count
                child = b.entries[i].child
                child != 0 && clear_node(tr, child, flags | CN_DEALLOC, vt)
            end
            free_block(tr, bid)
            return nothing
        end
    end
end

# PORT: pl-trie.c destroy_node
"Free node `nid` and its descendants (pl-trie.c)."
destroy_node(tr::trie{T}, nid::Int) where {T} = clear_node(tr, nid, CN_DEALLOC, nothing)

# PORT: pl-trie.c prune_node
# DIVERGES: the trie is an argument and not optional (a node does not know its trie: `get_trie_from_node` is left out).
"Prune the branch of the trie that does not end in a node, from node `nid` up (pl-trie.c)."
function prune_node(tr::trie{T}, nid::Int)::Nothing where {T}
    empty = true
    while empty
        n = tr.nodes[nid]
        (n.parent != 0 && (n.flags & (TN_PRIMARY | TN_SECONDARY | TN_PINNED)) == 0) || break
        p = n.parent
        empty = delete_child(tr, p, nid, true)
        destroy_node(tr, nid)
        nid = p
    end
    return nothing
end

# PORT: pl-trie.c prune_trie
# DIVERGES: the stack is a vector of `(parent, pos, active)` (upstream: a `segstack` of `prune_state`); `free` is a function
# of the node id (upstream: a function and a context pointer); `@goto` stands for upstream's labels `prune` and `next_choice`.
"Prune all branches below `root` that do not end in a value; `free(id)` is called for each removed leaf (pl-trie.c)."
function prune_trie(
    tr::trie{T}, root::Int, free::Union{Nothing, Function}=nothing
)::Nothing where {T}
    stack = Tuple{Int, Int, Bool}[]
    n = root
    ps_it = child_iter(0, 0)
    ps_active = false
    while true
        children = tr.nodes[n].children
        if children != 0
            if is_single_child(children)
                n = single_child(children)
                continue
            else
                it = init_child_iter(n)
                c, _ = next_child!(tr, it)
                if c != 0
                    push!(stack, (ps_it.parent, ps_it.pos, ps_active))
                    ps_it = it
                    ps_active = true
                    n = c
                    continue
                end
            end
        else
            free === nothing || free(n)
        end

        @label prune
        while n != root && (tr.nodes[n].flags & (TN_PRIMARY | TN_SECONDARY | TN_PINNED)) == 0
            p = tr.nodes[n].parent
            pc = tr.nodes[p].children
            choice = (pc != 0 && !is_single_child(pc))          # we are enumerating p
            delete_child(tr, p, n, false)
            destroy_node(tr, n)
            choice && break
            n = p
        end

        @label next_choice
        if ps_active
            c, _ = next_child!(tr, ps_it)
            if c != 0
                n = c
                continue
            else
                n = ps_it.parent
                pp, ppos, pact = pop!(stack)
                ps_it = child_iter(pp, ppos)
                ps_active = pact
                compact_children(tr, n)
                trie_has_children(tr.nodes[n]) || @goto prune
                @goto next_choice
            end
        else
            break
        end
    end
    return nothing
end

# PORT: pl-trie.c insert_child
# DIVERGES: nodes are ids; no write lock.
"Insert a new child with key `key` under node `nid`; its id (pl-trie.c)."
function insert_child(tr::trie{T}, nid::Int, key::word)::Int where {T}
    child = new_trie_node(tr, key)
    tr.nodes[child].parent = nid
    if !add_child(tr, nid, child)
        destroy_node(tr, child)
        return 0
    end
    return child
end

# PORT: pl-trie.c follow_node
"The child of node `nid` with key `value`; if there is none and `add`, a new one; else 0 (pl-trie.c)."
function follow_node(tr::trie{T}, nid::Int, value::word, add::Bool)::Int where {T}
    child = get_child(tr, nid, value)
    child != 0 && return child
    add && return insert_child(tr, nid, value)
    return 0
end

# PORT: pl-trie.c prune_error
"Prune the part of the trie an error leaves: first add a node under `nid`, then prune from it (pl-trie.c)."
function prune_error(tr::trie{T}, nid::Int)::Nothing where {T}
    prune_node(tr, follow_node(tr, nid, TRIE_ERROR_VAL, true))
    return nothing
end

# ---- INDIRECTS (trie_intern_indirect, pl-indirect.c) ----

# PORT: pl-indirect.c new_indirect_table
"A new, empty table of interned indirects of terms `T` (pl-indirect.c)."
new_indirect_table(::Type{T}) where {T} =
    indirect_table{T}(T[], Dict{UInt64, Vector{Int}}(), Int[])

# PORT: pl-indirect.c destroy_indirect_table
# DIVERGES: nothing is freed (Julia's garbage collector): the trie drops the table.
"Drop the table of interned indirects of `tr` (pl-indirect.c `destroy_indirect_table`)."
function destroy_indirect_table(tr::trie{T})::Nothing where {T}
    tr.indirects = nothing
    return nothing
end

# ORIGINAL: upstream's handle takes the `tagex` of the indirect it was created from (pl-indirect.c `create_indirect`: TAGEX_INDIRECT_FLOAT,
# _INT or _STRING); the value is a term-interface value, whose kind says which.
"The extended tag of the handle of the indirect value `v`: float, string, else integer (pl-indirect.c `create_indirect`)."
function indirect_tagex(v::T)::word where {T}
    k = number_kind(v)
    k == NUM_FLOAT && return TAGEX_INDIRECT_FLOAT
    k == NUM_STRING && return TAGEX_INDIRECT_STRING
    return TAGEX_INDIRECT_INT
end

# PORT: pl-indirect.c intern_indirect
# DIVERGES: the table holds the values themselves (see `indirect_table`): found by `gnd_key` and `gnd_equal` where upstream hashes the
# bytes and compares header and data; no reference counts (the handle is the index of the value, 1-based as upstream's).
"The handle of the indirect `v` in `tab`: its index with the extended tag `tx`; a new one if `create`, else 0 when it is not there (pl-indirect.c)."
function intern_indirect(tab::indirect_table{T}, v::T, create::Bool)::word where {T}
    k = gnd_key(v)
    if k === nothing                                            # a wildcard: compare with every value
        for i in eachindex(tab.values)
            gnd_equal(tab.values[i], v) && return consTagged(i, indirect_tagex(tab.values[i]))
        end
    else
        b = get(tab.buckets, k, nothing)
        if b !== nothing
            for i in b
                gnd_equal(tab.values[i], v) && return consTagged(i, indirect_tagex(v))
            end
        end
        for i in tab.wild
            gnd_equal(tab.values[i], v) && return consTagged(i, indirect_tagex(v))
        end
    end
    create || return word(0)
    push!(tab.values, v)
    i = length(tab.values)
    if k === nothing
        push!(tab.wild, i)
    else
        push!(get!(() -> Int[], tab.buckets, k), i)
    end
    return consTagged(i, indirect_tagex(v))
end

# PORT: pl-indirect.c extern_indirect
# DIVERGES: returns the value (upstream builds the indirect on the global stack and returns its word); the caller makes the cell
# from the value (`_vword!`).
"The value the handle `w` of an interned indirect names in `tab` (pl-indirect.c `extern_indirect`)."
extern_indirect(tab::indirect_table{T}, w::word)::T where {T} = tab.values[Int(valTagged(w))]

# PORT: pl-trie.c trie_intern_indirect
# DIVERGES: the value `v` of the indirect (a term-interface value) replaces its word; no compare-and-swap.
"The handle of the indirect `v` in `tr`'s table: made if `add`, else 0 when it is not there (pl-trie.c)."
function trie_intern_indirect(tr::trie{T}, v::T, add::Bool)::word where {T}
    tab = tr.indirects
    if tab === nothing
        add || return word(0)
        tab = new_indirect_table(T)
        tr.indirects = tab
    end
    return intern_indirect(tab, v, add)
end

# ---- LOOKUP (trie_lookup_abstract, trie_lookup_flat, trie_insert_flat) ----

# PORT: pl-trie.h size_abstract
# DIVERGES: `size` is an `Int`; `typemax(Int)` stands for upstream's `(size_t)-1` (no limit).
"The abstraction `trie_lookup_abstract` applies: below depth `from_depth` each term is limited to `size` compounds (pl-trie.h)."
struct size_abstract
    from_depth::Int                                             # start below depth
    size::Int                                                   # limit each term to size
end

# ORIGINAL: upstream's `deRef(p)` on a location (pl-data.h), as pl-rec.jl `compile_term_to_heap` does it: a slot (`loc < 0`) holds
# an atom, a compound, a value word or a reference; a cell that holds a numbered trie variable is a final word like an unbound
# variable (`_deref_loc` would take it for no known kind). The result is `(position, word)`; the position is 0 for a slot that
# holds its word itself (no cell to write).
"The dereferenced `(position, word)` of the location `loc` (a global position, or `-i` for slot `i`)."
@inline function trie_deref(ld::PL_local_data{T}, loc::Int)::Tuple{Int, word} where {T}
    if loc < 0
        w = ld.slots[-loc]
        w == SLOT_VALUE && return (0, _side_word(-loc))
        isRef(w) || return (0, w)
        p = unRef(w)
        w = ld.gstack[p]
    else
        p = loc
        w = ld.gstack[p]
    end
    while isRef(w)
        p = unRef(w)
        w = ld.gstack[p]
    end
    return (p, w)
end

# ORIGINAL: whether `w` is an indirect (pl-data.h `isIndirect`), as the kernel's words keep them (a value-table word or a slot's side word).
"Whether the dereferenced word `w` is an indirect: a value-table word or a side word."
@inline is_indirect_word(w::word)::Bool = _is_vword(w) || _is_side_word(w)

# PORT: pl-trie.c trie_lookup_abstract
# DIVERGES: `k` is a location (a slot `-i` or a global position) and the dereference is `trie_deref`; the result is
# `(rc, node id)` with `rc` 1 (true), 0 (false), TRIE_ABSTRACTED, TRIE_LOOKUP_CYCLIC; `vars` receives the (dereferenced) locations of the
# variables, or is `nothing`; the variable cell of a slot (position 0) is not written (it has none: a slot is never unbound);
# `abstract` is `abstraction`. An ATTRIBUTED VARIABLE is a named refusal, owner TR3 (upstream's O_TRIE_ATTVAR branches are ported
# there): the lookup restores the variables it numbered and prunes what it added, then throws `TrieRefusal`
# (never TRIE_LOOKUP_CONTAINS_ATTVAR, which swipl returns only without O_TRIE_ATTVAR).
"""
    trie_lookup_abstract(ld, tr, node, k, add, abstraction, vars) -> (rc, node)

Look up the term at location `k` in `tr` from node `node` (0: the root) and give the leaf node it is represented by; `add` adds it
when it is not there. Variables are numbered and bound to their number while the lookup runs (pl-trie.c).
"""
function trie_lookup_abstract(
    ld::PL_local_data{T}, tr::trie{T}, node::Int, k::Int, add::Bool,
    abstraction::Union{Nothing, size_abstract}, vars::Union{Nothing, Vector{Int}}
)::Tuple{Int, Int} where {T}
    var_number = 0
    rc = 1
    compounds = 0                                               # nesting depth
    from_depth = 1
    sz = typemax(Int)
    aleft = typemax(Int)
    attvar = false
    vl = vars === nothing ? Int[] : vars
    v0 = length(vl)

    tr.lookups += 1
    node == 0 && (node = 1)
    if abstraction !== nothing
        from_depth = abstraction.from_depth
        sz = abstraction.size
    end

    agenda = initCellAgenda_P(1, k)
    while node != 0
        l, popn = nextCellAgenda_P!(agenda)
        l == 0 && popn == 0 && break
        if popn > 0
            compounds -= popn
            if compounds > 0
                node = follow_node(tr, node, TRIE_KEY_POP(popn), add)
                node == 0 && break
                continue                                        # TR3: the end of an attributed variable
            else
                break                                           # finished toplevel
            end
        end

        if compounds == from_depth
            aleft = sz
        end

        p, w = trie_deref(ld, l)
        isvar = false
        if tag(w) == TAG_VAR
            isvar = isVar(w)
            isvar || (node = follow_node(tr, node, w, add))     # a numbered variable
        elseif isAttVar(w)
            attvar = true                                       # TR3
            break
        elseif _is_gcompound(w)
            if aleft == 0
                rc = TRIE_ABSTRACTED
                isvar = true                                    # goto add_var
            else
                f = valPtr(w)
                fd = ld.gstack[f]
                arity = arityFunctor(ld.functors, fd)
                aleft != typemax(Int) && (aleft -= 1)
                compounds += 1
                if compounds == 1000 && add && !is_acyclic_cells(ld, l)
                    rc = TRIE_LOOKUP_CYCLIC
                    prune_error(tr, node)
                    node = 0
                else
                    node = follow_node(tr, node, fd, add)
                    pushWorkCellAgenda_P!(agenda, arity, f + 1)
                end
            end
        elseif is_indirect_word(w)
            i = trie_intern_indirect(tr, _indirect_value(ld, w), add)
            node = i != 0 ? follow_node(tr, node, i, add) : 0
        else
            node = follow_node(tr, node, w, add)
        end

        if isvar                                                # add_var:
            var_number += 1
            push!(vl, p == 0 ? l : p)
            w2 = consTagged(var_number, TAGEX_VAR)
            tag(w) == TAG_VAR && p > 0 && (ld.gstack[p] = w2)   # otherwise abstracted
            node = follow_node(tr, node, w2, add)
        end
    end
    clearCellAgenda_P!(agenda)

    for i in (v0 + 1):length(vl)                                # restore the variables
        vp = vl[i]
        vp > 0 && tag(ld.gstack[vp]) == TAG_VAR && (ld.gstack[vp] = word(0))
    end
    vars === nothing && empty!(vl)

    if attvar
        add && prune_error(tr, node)
        throw(TrieRefusal("trie_lookup_abstract (an attributed variable)", "TR3"))
    end
    if rc > 0 && node == 0
        rc = 0
    end
    return (rc, node)
end

# PORT: pl-trie.c follow_node_add
"As `follow_node` with `add` true, the lookup first (pl-trie.c)."
@inline function follow_node_add(tr::trie{T}, nid::Int, key::word)::Int where {T}
    child = get_child(tr, nid, key)
    child != 0 && return child
    return insert_child(tr, nid, key)
end

# PORT: pl-trie.c trie_lookup_flat
# DIVERGES: the arguments are the locations `argv` (upstream: a `Word` to the argument array); `start` and the result are node ids
# (0: NULL), the result is `(rc, start node, node)` with `rc` 1 (true), 0 (false) or TRIE_LOOKUP_NOT_FLAT; the database and the
# local data are arguments (the names of the module and of the predicate, the functors); `vars` is the buffer of the dereferenced
# locations of the variables, the numbering is the position in it.
"""
    trie_lookup_flat(gd, ld, tr, start, def, argv, vars) -> (rc, start, node)

Look up `M:Head` of the predicate `def` with the argument locations `argv` in `tr` without creating anything; only flat calls (pl-trie.c).
"""
function trie_lookup_flat(
    gd::PL_global_data{T}, ld::PL_local_data{T}, tr::trie{T}, start::Int,
    def::Definition{T}, argv::Vector{Int}, vars::Vector{Int}
)::Tuple{Int, Int, Int} where {T}
    arity = def.arity
    tr.lookups += 1
    node = start
    if node == 0
        colon = lookupFunctorDef(ld.functors, _atom_word!(ld, mk_sym(T, :(:))), 2)
        mname = _atom_word!(ld, gd.modules[def.module_].atom)
        (node = get_child(tr, 1, colon)) == 0 && return (0, start, 0)
        (node = get_child(tr, node, mname)) == 0 && return (0, start, 0)
        if arity > 0
            fw = lookupFunctorDef(ld.functors, _atom_word!(ld, def.name), arity)
            (node = get_child(tr, node, fw)) == 0 && return (0, start, 0)
        end
        start = node
    end

    if arity == 0
        (node = get_child(tr, node, _atom_word!(ld, def.name))) == 0 && return (0, start, 0)
    else
        for i in 1:arity
            p, w = trie_deref(ld, argv[i])
            if tag(w) == TAG_VAR
                n = 0
                for j in eachindex(vars)
                    if vars[j] == p
                        n = j
                        break
                    end
                end
                if n == 0
                    push!(vars, p)
                    n = length(vars)
                end
                w = consTagged(n, TAGEX_VAR)
            elseif isAttVar(w) || _is_gcompound(w)
                return (TRIE_LOOKUP_NOT_FLAT, start, 0)
            elseif is_indirect_word(w)
                w = trie_intern_indirect(tr, _indirect_value(ld, w), false)
                w == 0 && return (0, start, 0)
            end
            (node = get_child(tr, node, w)) == 0 && return (0, start, 0)
        end
    end
    return (1, start, node)
end

# PORT: pl-trie.c FLAT_MAX_VARS
"The most variables `trie_insert_flat` numbers (pl-trie.c)."
const FLAT_MAX_VARS = 32
# PORT: pl-trie.c FLAT_MAX_ARGS
"The arguments `trie_insert_flat` dereferences once (pl-trie.c)."
const FLAT_MAX_ARGS = 16

# PORT: pl-trie.c trie_insert_flat
# DIVERGES: `k` is a location; the result is `(rc, node)` with `rc` 1 (true), 0 (false) or TRIE_LOOKUP_NOT_FLAT. A cell that holds
# a variable is bound to its number meanwhile and restored at the end, as upstream (the vector of the variables is local).
"""
    trie_insert_flat(ld, tr, k) -> (rc, node)

Insert the flat term at location `k` (an atom, or a compound whose arguments are atomic or plain variables) into `tr` (pl-trie.c).
"""
function trie_insert_flat(
    ld::PL_local_data{T}, tr::trie{T}, k::Int
)::Tuple{Int, Int} where {T}
    _, w = trie_deref(ld, k)
    if isAtomW(w)
        tr.lookups += 1
        node = follow_node_add(tr, 1, w)
        node == 0 && return (0, 0)
        return (1, node)
    end
    _is_gcompound(w) || return (TRIE_LOOKUP_NOT_FLAT, 0)

    f = valPtr(w)
    fd = ld.gstack[f]
    arity = arityFunctor(ld.functors, fd)
    args = Tuple{Int, word}[]                                   # the first FLAT_MAX_ARGS arguments, dereferenced once
    nvars = 0
    for i in 1:arity                                            # verify it is flat
        p, aw = trie_deref(ld, f + i)
        i <= FLAT_MAX_ARGS && push!(args, (p, aw))
        if tag(aw) == TAG_VAR
            (nvars += 1) > FLAT_MAX_VARS && return (TRIE_LOOKUP_NOT_FLAT, 0)
        elseif isAttVar(aw) || _is_gcompound(aw)
            return (TRIE_LOOKUP_NOT_FLAT, 0)
        end
    end

    tr.lookups += 1
    node = follow_node_add(tr, 1, fd)
    vars = Int[]
    i = 1
    while node != 0 && i <= arity
        if i <= FLAT_MAX_ARGS
            p, aw = args[i]
        else
            p, aw = trie_deref(ld, f + i)
        end
        w = p > 0 ? ld.gstack[p] : aw                           # a variable numbered meanwhile
        if tag(w) == TAG_VAR
            if isVar(w)
                push!(vars, p)
                w = consTagged(length(vars), TAGEX_VAR)
                ld.gstack[p] = w
            end
        elseif is_indirect_word(w)
            w = trie_intern_indirect(tr, _indirect_value(ld, w), true)
            if w == 0
                node = 0
                break
            end
        end
        node = follow_node_add(tr, node, w)
        i += 1
    end

    for p in vars
        ld.gstack[p] = word(0)
    end
    node == 0 && return (0, 0)
    return (1, node)
end

# PORT: pl-trie.c is_ground_trie_node
# DIVERGES: the trie is an argument (nodes are ids).
"Whether the path from the root to node `nid` holds no variable key (pl-trie.c)."
function is_ground_trie_node(tr::trie{T}, nid::Int)::Bool where {T}
    while tr.nodes[nid].parent != 0
        tx = tagex(tr.nodes[nid].key)
        (tx == TAGEX_VAR || tx == TAGEX_TRIE_ATTVAR) && return false
        nid = tr.nodes[nid].parent
    end
    return true
end

# PORT: pl-trie.c map_trie_node
# DIVERGES: `map(tr, id)` returns `nothing` to go on, any other value stops and is returned (upstream: a function and a context
# pointer returning NULL or a pointer); nodes are ids.
"Call `map(tr, id)` for node `nid` and its descendants, until it returns a value other than `nothing`, which is returned (pl-trie.c)."
function map_trie_node(tr::trie{T}, nid::Int, map::Function) where {T}
    while true
        children = tr.nodes[nid].children
        rc = map(tr, nid)
        rc === nothing || return rc
        children == 0 && return nothing
        if is_single_child(children)
            nid = single_child(children)
        else
            it = init_child_iter(nid)
            while true
                n2, _ = next_child!(tr, it)
                n2 == 0 && return nothing
                rc = map_trie_node(tr, n2, map)
                rc === nothing || return rc
            end
        end
    end
end

# PORT: pl-trie.c trie_stats
"What `stat_trie` counts (pl-trie.c `trie_stats`): the bytes upstream's trie takes, its nodes, its hashed blocks and its values."
mutable struct trie_stats
    bytes::Int
    nodes::Int
    hashes::Int
    values::Int
end

# PORT: pl-trie.c stat_node
# DIVERGES: a function of the trie and the node id; `stats` is the context; the sizes are upstream's (`SIZEOF_TRIE_NODE`, `sizeof_block`).
"Count node `nid` in `stats` (pl-trie.c `stat_node`); `nothing` (go on)."
function stat_node(stats::trie_stats, tr::trie{T}, nid::Int)::Nothing where {T}
    n = tr.nodes[nid]
    children = n.children
    stats.nodes += 1
    (n.flags & TN_CHUNKED) == 0 && (stats.bytes += SIZEOF_TRIE_NODE)   # chunks are added by stat_trie
    n.value != 0 && (n.flags & TN_PRIMARY) != 0 && (stats.values += 1)
    if children != 0 && !is_single_child(children)
        b = block_at(tr, children_block_id(children))
        stats.bytes += sizeof_block(b)
        b.index_bits != 0 && (stats.hashes += 1)
    end
    return nothing
end

# PORT: pl-trie.c stat_trie
# DIVERGES: the bytes are upstream's, from its sizes (the records here are not that big); `acquire_trie` and `release_trie` are O_PLMT
# (owner TH1); returns the statistics (upstream fills `*stats`).
"The statistics of `tr` (pl-trie.c `stat_trie`): the bytes of upstream's trie, nodes, hashed blocks and values."
function stat_trie(tr::trie{T})::trie_stats where {T}
    stats = trie_stats(SIZEOF_TRIE - SIZEOF_TRIE_NODE, 0, 0, 0)
    map_trie_node(tr, 1, (t, id) -> stat_node(stats, t, id))
    if (tr.flags & TRIE_CONCURRENT) == 0
        c = tr.chunks
        while c !== nothing
            stats.bytes += Int(c.bytes)
            c = c.next
        end
    end
    return stats
end

# PORT: pl-trie.c trie_table_size
"The bytes upstream's answer trie `tr` takes, for an estimate of the memory abolishing it frees (pl-trie.c): no clause before TR4."
trie_table_size(tr::trie{T})::Int where {T} = SIZEOF_TRIE + tr.node_count * SIZEOF_TRIE_NODE

# ---- THE TRIE BLOB (trie_symbol, symbol_trie, get_trie, trie_error) ----

# PORT: pl-trie.c trie_blob
# DIVERGES: no `release`, `write`, `save` or `load` slots (`PL_blob_t` has none): atom-GC does not exist here, so a trie lives
# as long as `gd.tries` (`trie_destroy/1` empties it); the written form `<trie>(0x...)` is the term layer's blob form.
"The blob type of a trie (pl-trie.c `trie_blob`): not unique (one atom per trie, made by `trie_symbol`), non-text, named `trie`."
const trie_blob = PL_blob_t(PL_BLOB_NOCOPY, "trie")

# PORT: pl-trie.c initTries
# DIVERGES: the database's atom table is the argument; called by the database's constructor in pl-setup.c's order. Only the
# blob registration: the mutex stripes are O_PLMT (owner TH1) and the procedure lookups at the end of upstream's function belong
# to the steps that port those predicates (TR2, TB1).
"Register the trie blob type in `atoms` (pl-trie.c `initTries`)."
function initTries!(atoms::atoms_t)::Nothing
    PL_register_blob_type(atoms, trie_blob)
    return nothing
end

# ORIGINAL: the payload of a trie blob (upstream: the pointer to the trie, `PL_BLOB_NOCOPY` data).
"The 8 bytes of a trie blob: the trie's number in `gd.tries`, little-endian."
_trie_bytes(serial::Int)::Vector{UInt8} = collect(reinterpret(UInt8, Int64[serial]))

# ORIGINAL: upstream's `PL_blob_data(symbol, NULL, &type)` of a trie blob with its type test, as `closure_of_word`.
"The trie the blob atom word `w` names, whatever its magic, or `nothing` when `w` is no trie blob."
function trie_of_word(gd::PL_global_data{T}, w::word)::Union{Nothing, trie{T}} where {T}
    at = atomValue(gd.atoms, w)
    at.type === trie_blob || return nothing
    serial = reinterpret(Int64, at.name[1:8])[1]
    return gd.tries[Int(serial)]
end

# PORT: pl-trie.c trie_symbol
# DIVERGES: the database is an argument; the trie gets its number in `gd.tries` with its first symbol; the result is the atom
# WORD (`unify_trie` makes the blob term of it).
"The atom (handle) of `tr`, created on first use (pl-trie.c)."
function trie_symbol(gd::PL_global_data{T}, tr::trie{T})::word where {T}
    tr.symbol != 0 && return tr.symbol
    push!(gd.tries, tr)
    tr.serial = length(gd.tries)
    bytes = _trie_bytes(tr.serial)
    w, _ = lookupBlob(gd.atoms, bytes, length(bytes), trie_blob)
    tr.symbol = w
    return w
end

# PORT: pl-trie.c symbol_trie
# DIVERGES: the atom word is the argument; `nothing` is NULL.
"The live trie the atom word `symbol` names, or `nothing` (pl-trie.c)."
function symbol_trie(gd::PL_global_data{T}, symbol::word)::Union{Nothing, trie{T}} where {T}
    t = trie_of_word(gd, symbol)
    (t !== nothing && t.magic == TRIE_MAGIC) && return t
    return nothing
end

# PORT: pl-trie.c unify_trie
"Unify the term reference `t` with the symbol of `tr` (pl-trie.c)."
function unify_trie(
    gd::PL_global_data{T}, ld::PL_local_data{T}, t::term_t, tr::trie{T}
)::Bool where {T}
    a = _blob_term!(gd.atoms, gd.atom_symbols, T, trie_symbol(gd, tr))
    return PL_unify_atomic(ld, t, a)
end

# PORT: pl-trie.c get_trie
# DIVERGES: returns the trie or `nothing` after the error (upstream: a Bool and `*tp`); the database and the local data
# are arguments.
"The trie in `t`; else raise `type_error(trie, T)`, or `existence_error(trie, T)` for a destroyed one, and `nothing` (pl-trie.c)."
function get_trie(
    gd::PL_global_data{T}, ld::PL_local_data{T}, t::term_t
)::Union{Nothing, trie{T}} where {T}
    a = PL_get_atom(ld, t)
    tr = (a === nothing || !is_blob(a)) ? nothing : trie_of_word(gd, blob_handle(a))
    if tr !== nothing
        tr.magic == TRIE_MAGIC && return tr
        PL_error(ld, ERR_EXISTENCE, mk_sym(T, :trie), t)
    else
        PL_type_error(ld, "trie", t)
    end
    return nothing
end

# PORT: pl-trie.c get_trie_noex
# DIVERGES: returns the trie or `nothing` (upstream: a Bool and `*tp`).
"The trie in `t`, whatever its magic, or `nothing`; no error (pl-trie.c)."
function get_trie_noex(
    gd::PL_global_data{T}, ld::PL_local_data{T}, t::term_t
)::Union{Nothing, trie{T}} where {T}
    a = PL_get_atom(ld, t)
    (a === nothing || !is_blob(a)) && return nothing
    return trie_of_word(gd, blob_handle(a))
end

# PORT: pl-trie.c trie_error
"Raise the error for the lookup result `rc` on `culprit`; false (pl-trie.c)."
function trie_error(ld::PL_local_data{T}, rc::Int, culprit::term_t)::Bool where {T}
    if rc == TRIE_LOOKUP_CONTAINS_ATTVAR
        return PL_type_error(ld, "free_of_attvar", culprit)
    elseif rc == TRIE_LOOKUP_CYCLIC
        return PL_type_error(ld, "acyclic_term", culprit)
    end
    return false
end

# PORT: pl-trie.c trie_trie_error
"As `trie_error` with the symbol of `tr` as the culprit (pl-trie.c)."
function trie_trie_error(
    gd::PL_global_data{T}, ld::PL_local_data{T}, rc::Int, tr::trie{T}
)::Bool where {T}
    t = PL_new_term_ref(ld)
    a = _blob_term!(gd.atoms, gd.atom_symbols, T, trie_symbol(gd, tr))
    PL_put_atom(ld, t, a)
    return trie_error(ld, rc, t)
end

# ---- THE VALUES (isRecord, intern_value, equal_value, unify_value, put_trie_value, set_trie_value, trie_delete) (part B) ----

# PORT: pl-trie.c isRecord
# DIVERGES: upstream tells a record (a pointer) from an atom or a tagged integer by the low two bits of the word being 0 (an atom
# and an integer have a nonzero tag there); a record is a slot of `tr.records` here and its word is `index << 2` (index >= 1), so the
# same test holds. 0 is "no value" and is never asked.
"Whether the node value word `w` is a record (pl-trie.c `isRecord`)."
@inline isRecord(w::word)::Bool = (w & word(0x3)) == 0

# ORIGINAL: the recorded value `r` kept in `tr` (upstream keeps the pointer in the node); its value word.
"Keep the record `r` in `tr`; its value word `index << 2`."
function new_record_value!(tr::trie{T}, r::record{T})::word where {T}
    if isempty(tr.free_records)
        push!(tr.records, r)
        idx = length(tr.records)
    else
        idx = pop!(tr.free_records)
        tr.records[idx] = r
    end
    return word(idx) << 2
end

# ORIGINAL: the record a value word `w` stands for.
"The record of the value word `w` of `tr` (an `isRecord` word)."
function record_of_value(tr::trie{T}, w::word)::record{T} where {T}
    r = tr.records[Int(w >> 2)]
    r === nothing && error("record_of_value: the record of value word $w is erased")
    return r
end

# ORIGINAL: upstream's `PL_erase(word2ptr(record_t, value))` of a node value; the slot is free again.
"Erase the record of the value word `w` of `tr` (`PL_erase`)."
function erase_value!(tr::trie{T}, w::word)::Nothing where {T}
    idx = Int(w >> 2)
    if tr.records[idx] !== nothing
        tr.records[idx] = nothing
        push!(tr.free_records, idx)
    end
    return nothing
end

# PORT: pl-trie.c intern_value
# DIVERGES: the database's `ld` and the trie are arguments (a record lives in `tr.records`); `value` 0 is upstream's NULL (a set: the
# reserved atom `trienode`, the atom word the reserved symbol has in every database); the dereference is `trie_deref`.
"The value word for the term `value` (0: none): an atom or a tagged integer is its own word, anything else a record of `tr` (pl-trie.c)."
function intern_value(ld::PL_local_data{T}, tr::trie{T}, value::term_t)::word where {T}
    if value != 0
        _, w = trie_deref(ld, -(value + 1))
        (isAtomW(w) || isTaggedIntW(w)) && return w
        return new_record_value!(tr, PL_record(ld, value))
    end
    return _atom_word!(ld, mk_reserved_symbol(T, :trienode))
end

# PORT: pl-trie.c equal_value
# DIVERGES: the trie is an argument (it holds the records); `variantRecords` compares the codes.
"Whether the node values `v1` and `v2` of `tr` are equal: the same word, or two variant records (pl-trie.c)."
function equal_value(tr::trie{T}, v1::word, v2::word)::Bool where {T}
    v1 == v2 && return true
    if isRecord(v1) && isRecord(v2)
        return variantRecords(record_of_value(tr, v1), record_of_value(tr, v2))
    end
    return false
end

# PORT: pl-trie.c unify_value
# DIVERGES: the value of a variant table node (`isTriePtrValue`: an answer trie, owner TB1) is not met before TB1 and is not
# handled; the reserved atom `trienode` is the reserved symbol (its symbol is not cached by a database that never made the word).
"Unify the term reference `t` with the node value `value` of `tr` (pl-trie.c)."
function unify_value(ld::PL_local_data{T}, tr::trie{T}, t::term_t, value::word)::Bool where {T}
    if !isRecord(value)
        v = value == ATOM_trienode ? mk_reserved_symbol(T, :trienode) :
            (isAtomW(value) ? _atom_value(ld, value) : _value_term(ld, value))
        return PL_unify_atomic(ld, t, v)
    end
    t2 = PL_new_term_ref(ld)
    return PL_recorded(ld, record_of_value(tr, value), t2) && PL_unify(ld, t, t2)
end

# PORT: pl-trie.c put_trie_value
# DIVERGES: the node is a node id of `tr`; `*valTermRef(t) = node->value` is the slot's word.
"Put the value of node `nid` of `tr` into the term reference `t` (pl-trie.c)."
function put_trie_value(ld::PL_local_data{T}, tr::trie{T}, t::term_t, nid::Int)::Bool where {T}
    v = tr.nodes[nid].value
    if !isRecord(v)
        ld.slots[t + 1] = v
        return true
    end
    return PL_recorded(ld, record_of_value(tr, v), t)
end

# PORT: pl-trie.c set_trie_value_word
# DIVERGES: node id; `acquire_key` (the reference count of an atom) is a no-op, see the file header.
"Give node `nid` of `tr` the value word `val`; whether the value changed (pl-trie.c)."
function set_trie_value_word(tr::trie{T}, nid::Int, val::word)::Bool where {T}
    n = tr.nodes[nid]
    if n.value != 0
        if !equal_value(tr, n.value, val)
            old = n.value
            n.value = val
            n.flags |= TN_PRIMARY
            release_value(tr, old)
            trie_discard_clause(tr)
            return true
        else
            return false
        end
    else
        n.value = val
        n.flags |= TN_PRIMARY
        tr.value_count += 1
        trie_discard_clause(tr)
        return true
    end
end

# PORT: pl-trie.c set_trie_value
# DIVERGES: the local data is an argument and the node a node id; a new record that equals the old value is erased as upstream
# does (`PL_erase`).
"Set the value of node `nid` of `tr` to the term `value`; true (pl-trie.c)."
function set_trie_value(
    ld::PL_local_data{T}, tr::trie{T}, nid::Int, value::term_t
)::Bool where {T}
    val = intern_value(ld, tr, value)
    if !set_trie_value_word(tr, nid, val) && isRecord(val)
        erase_value!(tr, val)
    end
    return true
end

# PORT: pl-trie.c trie_release_value
"Release the value `value` of a node of `tr` (pl-trie.c): see `release_value`."
trie_release_value(tr::trie{T}, value::word) where {T} = release_value(tr, value)

# PORT: pl-trie.c trie_delete
# DIVERGES: node id; `prune_node` takes the trie.
"Delete the value of node `nid` of `tr`: with `prune` the branch leading to it is pruned up to the next node still in use (pl-trie.c)."
function trie_delete(tr::trie{T}, nid::Int, prune::Bool)::Nothing where {T}
    n = tr.nodes[nid]
    if n.value != 0
        (n.flags & TN_PRIMARY) != 0 && (tr.value_count -= 1)
        n.flags &= ~(TN_PRIMARY | TN_SECONDARY)
        if prune && tr.references == 0
            prune_node(tr, nid)
        else
            release_node(tr, nid)
            v = n.value
            if v != 0
                n.value = 0
                release_value(tr, v)
            end
        end
        trie_discard_clause(tr)
    end
    return nothing
end

# PORT: pl-trie.c get_trie_nodes
# DIVERGES: the database and local data are arguments; `trie_restore_nodes` (a discarded trie) is refused by name, owner TR4.
"The trie in `t` with its nodes present, or `nothing` after the error (pl-trie.c)."
function get_trie_nodes(
    gd::PL_global_data{T}, ld::PL_local_data{T}, t::term_t
)::Union{Nothing, trie{T}} where {T}
    tr = get_trie(gd, ld, t)
    tr === nothing && return nothing
    trie_ensure_nodes(tr) || return nothing
    return tr
end

# PORT: pl-trie.h trie_lookup
# DIVERGES: the result is `(rc, node id)`, see `trie_lookup_abstract`.
"As `trie_lookup_abstract` with no abstraction (pl-trie.h)."
trie_lookup(
    ld::PL_local_data{T}, tr::trie{T}, node::Int, k::Int, add::Bool,
    vars::Union{Nothing, Vector{Int}}
) where {T} = trie_lookup_abstract(ld, tr, node, k, add, nothing, vars)

# ---- UNIFYING A TERM WITH THE KEYS OF A NODE (ukey_state, unify_key, unify_trie_term) (part B) ----

# ORIGINAL (pl-trie.c `ukey_state`, `varinfo`): the state `unify_key` steps. Upstream keeps the argument stack on the engine's
# (`pushArgumentStack`, `aTop`, `a_offset`); the state OWNS its stack here (`astack`: the `(next location, write mode)` pairs upstream
# packs into one word with the `uwrite` bit), so no `destroy_ukey_state` is needed. `ptr` is a location: a global position, or `-(t+1)`
# for the slot of the term reference `t`; `vars` holds the location of numbered variable `i` at index `i` (0: not seen yet; upstream's
# `varinfo.address`, the attribute location of `TAGEX_TRIE_ATTVAR` is TR3's).
"The state of unifying a term with a sequence of trie keys: the location in the term, the mode, the argument stack and the variables."
mutable struct ukey_state{T}
    tr::trie{T}
    ptr::Int                                                    # where we are in the term (a location)
    write::Bool                                                 # umode == uwrite
    astack::Vector{Tuple{Int, Bool}}                            # the argument stack: (location, write mode) to return to
    vars::Vector{Int}                                           # the location of the numbered variables, 0: unset
end

# PORT: pl-trie.c init_ukey_state
# DIVERGES: the state is made, not initialised in place; `reinit` belongs to the retry loop `unify_trie_term` does not have.
"A new `ukey_state` for `tr` at location `p`, in read mode (pl-trie.c `init_ukey_state`)."
ukey_state(tr::trie{T}, p::Int) where {T} =
    ukey_state{T}(tr, p, false, Tuple{Int, Bool}[], Int[])

# PORT: pl-trie.c find_var
# DIVERGES: the index is a position in `vars`, grown with 0 (an unseen variable) up to it; returned as the index.
"Make sure the numbered variable `index` (1..) of `st` has an entry (pl-trie.c `find_var`)."
@inline function find_var!(st::ukey_state, index::Int)::Int
    index > length(st.vars) && resize!(st.vars, index)
    return index
end

# PORT: pl-trie.c unify_key
# DIVERGES: the argument stack is the state's (`astack`); a functor key allocates with `allocGlobalNoShift` and returns
# GLOBAL_OVERFLOW when the stack limit is reached (the caller raises it: no `Undo` and no retry, the stacks grow on demand); a
# variable cell is bound with `_bind_const!` (which trails below the mark bar); an attributed variable met where a functor key must
# make a compound, and the keys `TAGEX_TRIE_ATTVAR` and `TAGEX_TRIE_ATTVAR_END` (upstream's O_TRIE_ATTVAR branches), are a named
# refusal, owner TR3 (an attributed variable met by an atom or integer key is bound by `bindConst`, which wakes it as `h_const` does);
# an indirect key is `extern_indirect` of the trie's table, written by `_vword_at!` in write mode and unified by `_unify_const_loc`
# in read mode (upstream compares `equalIndirect`); the first occurrence of a variable in read mode records the dereferenced cell
# where it is one, so that a later write-mode `makeRefG` has a global position.
"""
    unify_key(ld, st, key) -> boolex_t

Take one step in unifying a term with a sequence of trie keys: `st.ptr` is where we are in the term and `key` the key of the next node.
`BOOLEX_TRUE`, `BOOLEX_FALSE` or `GLOBAL_OVERFLOW` (pl-trie.c).
"""
function unify_key(ld::PL_local_data{T}, st::ukey_state{T}, key::word)::boolex_t where {T}
    p = st.ptr
    tx = tagex(key)
    if tx == TAGEX_TRIE_RESERVED                                # a pop key
        popn = IS_TRIE_KEY_POP(key)
        @assert popn > 0 "unify_key: a reserved key that pops nothing"
        e = st.astack[end - popn + 1]
        resize!(st.astack, length(st.astack) - popn)
        st.ptr, st.write = e
        return BOOLEX_TRUE
    elseif isFunctor(key)
        arity = arityFunctor(ld.functors, key)
        push!(st.astack, (p > 0 ? p + 1 : p, st.write))
        if st.write
            t = allocGlobalNoShift(ld, arity + 1)
            t == 0 && return GLOBAL_OVERFLOW
            ld.gstack[t] = key
            ld.gstack[p] = consPtr(t, TAG_COMPOUND | STG_GLOBAL)
            st.ptr = t + 1
            return BOOLEX_TRUE
        end
        pp, w = trie_deref(ld, p)
        if isVar(w)
            st.write = true
            t = allocGlobalNoShift(ld, arity + 1)
            t == 0 && return GLOBAL_OVERFLOW
            ld.gstack[t] = key
            _bind_const!(ld, pp, consPtr(t, TAG_COMPOUND | STG_GLOBAL))
            st.ptr = t + 1
            return BOOLEX_TRUE
        elseif isAttVar(w)
            throw(TrieRefusal("unify_key (an attributed variable)", "TR3"))
        elseif _is_gcompound(w)
            f = valPtr(w)
            if ld.gstack[f] == key
                st.ptr = f + 1
                return BOOLEX_TRUE
            end
        end
        return BOOLEX_FALSE
    elseif tx == TAGEX_VAR                                      # a numbered variable
        index = find_var!(st, Int(valTagged(key)))
        if st.write
            if st.vars[index] == 0
                ld.gstack[p] = word(0)                          # setVar
                st.vars[index] = p
            else
                ld.gstack[p] = makeRefG(st.vars[index])
            end
        else
            pp, _ = trie_deref(ld, p)
            if st.vars[index] == 0
                st.vars[index] = pp > 0 ? pp : p
            else
                unify_ptrs_cells(ld, p, st.vars[index]) || return BOOLEX_FALSE
            end
        end
    elseif tx == TAGEX_INDIRECT_INT || tx == TAGEX_INDIRECT_STRING || tx == TAGEX_INDIRECT_FLOAT
        v = extern_indirect(st.tr.indirects::indirect_table{T}, key)
        if st.write
            _vword_at!(ld, v, p)
        else
            _unify_const_loc(ld, p, v) || return BOOLEX_FALSE
        end
    elseif isAtomW(key) || isTaggedIntW(key)
        if st.write
            ld.gstack[p] = key
        else
            pp, w = trie_deref(ld, p)
            if isVar(w) || isAttVar(w)
                bindConst(ld, pp, key)
            elseif w != key
                return BOOLEX_FALSE
            end
        end
    elseif tx == TAGEX_TRIE_ATTVAR || tx == TAGEX_TRIE_ATTVAR_END
        throw(TrieRefusal("unify_key (an attributed variable key)", "TR3"))
    else
        error("unify_key: not a trie key: $key")
    end
    st.ptr = p > 0 ? p + 1 : p
    return BOOLEX_TRUE
end

# PORT: pl-trie.c unify_trie_term
# DIVERGES: the trie `tr` and the node id `nid` are arguments (upstream finds the trie from the node, `get_trie_from_node`); the
# result is `(rc, parent)` where `parent` is the node the walk stopped at (0: none; upstream's `*parent`); the keys are a `Vector`
# (no 256-word fast buffer); there is no retry loop: a GLOBAL_OVERFLOW is raised by `raiseStackOverflow` (no `Mark`, `Undo` or
# `makeMoreStackSpace`: the stacks grow on demand), and the state owns its argument stack.
"""
    unify_trie_term(ld, tr, nid, term) -> (rc, parent)

Unify the term reference `term` with the term the keys from the root of `tr` to node `nid` represent; for a secondary node
(`TN_SECONDARY`) only the keys up to the nearest primary node, which is `parent` (pl-trie.c).
"""
function unify_trie_term(
    ld::PL_local_data{T}, tr::trie{T}, nid::Int, term::term_t
)::Tuple{Bool, Int} where {T}
    keys = word[]
    parent = 0
    is_secondary = (tr.nodes[nid].flags & TN_SECONDARY) != 0
    n = nid
    while tr.nodes[n].parent != 0
        nd = tr.nodes[n]
        if is_secondary && (nd.flags & TN_PRIMARY) != 0
            parent = n
            break
        end
        push!(keys, nd.key)
        n = nd.parent
    end

    st = ukey_state(tr, -(term + 1))
    for i in length(keys):-1:1
        rcu = unify_key(ld, st, keys[i])
        if rcu != BOOLEX_TRUE
            rcu == BOOLEX_FALSE && return (false, parent)
            return (raiseStackOverflow(ld, rcu), parent)
        end
    end
    return (true, parent)
end

# ---- THE PREDICATES (pl-trie.c PRED_IMPLs of TR1) (part B) ----

# PORT: pl-trie.c trie_insert
# DIVERGES: the database and the local data are arguments; `Value` is a term reference or 0 (upstream's NULL); the result is
# `(inserted, node id)` (upstream: the bool and `*nodep`); `abstraction` is the `size_abstract` or `nothing`; the permission errors
# are `PL_error` with `ERR_PERMISSION`; `acquire_key` (the reference count of an atom) is a no-op, see the file header, and a new
# record that equals the old value is erased as upstream does (`PL_erase`).
"""
    trie_insert(gd, ld, Trie, Key, Value, update, abstraction) -> (inserted, node)

Add the term `Key` with the optional `Value` (0: none) to the trie `Trie` and give the node; with `update` an existing different value
is replaced, else it is a permission error (pl-trie.c).
"""
function trie_insert(
    gd::PL_global_data{T}, ld::PL_local_data{T}, Trie::term_t, Key::term_t, Value::term_t,
    update::Bool, abstraction::Union{Nothing, size_abstract}
)::Tuple{Bool, Int} where {T}
    tr = get_trie_nodes(gd, ld, Trie)
    tr === nothing && return (false, 0)

    if (tr.flags & (TRIE_ISMAP | TRIE_ISSET)) == 0
        tr.flags |= Value != 0 ? TRIE_ISMAP : TRIE_ISSET
    elseif (Value != 0 && (tr.flags & TRIE_ISMAP) == 0) ||
           (Value == 0 && (tr.flags & TRIE_ISSET) == 0)
        PL_error(ld, "", 0, "", ERR_PERMISSION, mk_sym(T, :insert), mk_sym(T, :trie), Trie)
        return (false, 0)
    end

    rc, nid = trie_lookup_abstract(ld, tr, 0, -(Key + 1), true, abstraction, nothing)
    rc == 1 || return (trie_error(ld, rc, Key), 0)

    val = intern_value(ld, tr, Value)
    n = tr.nodes[nid]
    if n.value != 0
        if update
            if !equal_value(tr, n.value, val)
                old = n.value
                n.value = val
                n.flags |= TN_PRIMARY
                release_value(tr, old)
                trie_discard_clause(tr)
            elseif isRecord(val)
                erase_value!(tr, val)
            end
            return (true, nid)
        else
            if !equal_value(tr, n.value, val)
                PL_error(
                    ld, "", 0, "", ERR_PERMISSION, mk_sym(T, :modify), mk_sym(T, :trie_key), Key
                )
            end
            isRecord(val) && erase_value!(tr, val)
            return (false, nid)
        end
    end
    n.value = val
    n.flags |= TN_PRIMARY
    tr.value_count += 1
    trie_discard_clause(tr)
    return (true, nid)
end

# ORIGINAL: the node handle `trie_insert/4` gives and `trie_term/2` takes. Upstream's handle is the node POINTER
# (`PL_unify_pointer`); the kernel has no `PL_unify_pointer` and a node is an id in `tr.nodes`, so the handle is the integer
# `(trie's serial << 32) | node id`.
"The integer handle of node `nid` of `tr` (`trie_insert/4`, `trie_term/2`)."
trie_node_handle(tr::trie{T}, nid::Int)::Int where {T} = (tr.serial << 32) | nid

# PORT: pl-trie.c trie_new as pl_trie_new1_va
# (PRED_IMPL("trie_new", 1, trie_new, 0))
# DIVERGES: the symbol is not registered and unregistered (`PL_unregister_atom`): a trie lives as long as `gd.tries`.
"`trie_new(-Trie)`: create a new trie (pl-trie.c)."
function pl_trie_new1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    gd = _query_gd(ld)
    tr = trie_create(T)
    tr.flags |= TRIE_CONCURRENT
    return unify_trie(gd, ld, PL__t0, tr) ? FTRUE : FFALSE
end

# PORT: pl-trie.c is_trie as pl_is_trie1_va
# (PRED_IMPL("is_trie", 1, is_trie, 0))
# DIVERGES: `get_trie_noex` is `PL_get_blob` with the type test.
"`is_trie(@Trie)`: `Trie` is a trie that was not destroyed (pl-trie.c)."
function pl_is_trie1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    gd = _query_gd(ld)
    tr = get_trie_noex(gd, ld, PL__t0)
    return (tr !== nothing && tr.magic == TRIE_MAGIC) ? FTRUE : FFALSE
end

# PORT: pl-trie.c trie_destroy as pl_trie_destroy1_va
# (PRED_IMPL("trie_destroy", 1, trie_destroy, 0))
"`trie_destroy(+Trie)`: destroy `Trie` and its nodes (pl-trie.c)."
function pl_trie_destroy1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    gd = _query_gd(ld)
    tr = get_trie(gd, ld, PL__t0)
    tr === nothing && return FFALSE
    tr.magic = TRIE_CMAGIC
    trie_empty(tr)
    return FTRUE
end

# PORT: pl-trie.c trie_insert as pl_trie_insert3_va
# (PRED_IMPL("trie_insert", 3, trie_insert, 0))
"`trie_insert(+Trie, +Key, +Value)`: add `Key` with `Value`; fails when it is there with that value, permission error when with another (pl-trie.c)."
function pl_trie_insert3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    gd = _query_gd(ld)
    A1, A2, A3 = PL__t0, PL__t0 + 1, PL__t0 + 2
    rc, _ = trie_insert(gd, ld, A1, A2, A3, false, nothing)
    return rc ? FTRUE : FFALSE
end

# PORT: pl-trie.c trie_insert as pl_trie_insert2_va
# (PRED_IMPL("trie_insert", 2, trie_insert, 0))
"`trie_insert(+Trie, +Key)`: add `Key` to the set; fails when it is there (pl-trie.c)."
function pl_trie_insert2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    gd = _query_gd(ld)
    A1, A2 = PL__t0, PL__t0 + 1
    rc, _ = trie_insert(gd, ld, A1, A2, 0, false, nothing)
    return rc ? FTRUE : FFALSE
end

# PORT: pl-trie.c trie_insert_abstract as pl_trie_insert_abstract3_va
# (PRED_IMPL("$trie_insert_abstract", 3, trie_insert_abstract, 0))
"`'\$trie_insert_abstract'(+Trie, +Size, +Key)`: insert the size-abstracted version of `Key` (pl-trie.c)."
function pl_trie_insert_abstract3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    gd = _query_gd(ld)
    A1, A2, A3 = PL__t0, PL__t0 + 1, PL__t0 + 2
    sz = PL_get_size_ex(ld, A2)
    sz === nothing && return FFALSE
    rc, _ = trie_insert(gd, ld, A1, A3, 0, false, size_abstract(1, sz))
    return rc ? FTRUE : FFALSE
end

# PORT: pl-trie.c trie_update as pl_trie_update3_va
# (PRED_IMPL("trie_update", 3, trie_update, 0))
"`trie_update(+Trie, +Key, +Value)`: as `trie_insert/3` but replace the value of `Key` (pl-trie.c)."
function pl_trie_update3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    gd = _query_gd(ld)
    A1, A2, A3 = PL__t0, PL__t0 + 1, PL__t0 + 2
    rc, _ = trie_insert(gd, ld, A1, A2, A3, true, nothing)
    return rc ? FTRUE : FFALSE
end

# PORT: pl-trie.c trie_insert as pl_trie_insert4_va
# (PRED_IMPL("trie_insert", 4, trie_insert, 0))
# DIVERGES: the handle is the integer `trie_node_handle` (upstream: `PL_unify_pointer`).
"`trie_insert(+Trie, +Term, +Value, -Handle)`: add `Term` and unify `Handle` with a handle of its node (pl-trie.c)."
function pl_trie_insert4_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    gd = _query_gd(ld)
    A1, A2, A3, A4 = PL__t0, PL__t0 + 1, PL__t0 + 2, PL__t0 + 3
    rc, nid = trie_insert(gd, ld, A1, A2, A3, false, nothing)
    rc || return FFALSE
    tr = get_trie_noex(gd, ld, A1)::trie{T}
    return PL_unify_integer(ld, A4, trie_node_handle(tr, nid)) ? FTRUE : FFALSE
end

# PORT: pl-trie.c trie_delete as pl_trie_delete3_va
# (PRED_IMPL("trie_delete", 3, trie_delete, 0))
"`trie_delete(+Trie, +Key, ?Value)`: remove `Key` if its value unifies with `Value` (pl-trie.c)."
function pl_trie_delete3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    gd = _query_gd(ld)
    A1, A2, A3 = PL__t0, PL__t0 + 1, PL__t0 + 2
    tr = get_trie_nodes(gd, ld, A1)
    tr === nothing && return FFALSE

    rc, nid = trie_lookup(ld, tr, 0, -(A2 + 1), false, nothing)
    if rc == 1
        v = tr.nodes[nid].value
        if v != 0 && unify_value(ld, tr, A3, v)
            trie_delete(tr, nid, true)
            return FTRUE
        end
        return FFALSE
    end
    return trie_error(ld, rc, A2) ? FTRUE : FFALSE
end

# PORT: pl-trie.c trie_lookup as pl_trie_lookup3_va
# (PRED_IMPL("trie_lookup", 3, trie_lookup, 0))
"`trie_lookup(+Trie, +Key, -Value)`: `Value` is the value of `Key` in `Trie` (pl-trie.c)."
function pl_trie_lookup3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    gd = _query_gd(ld)
    A1, A2, A3 = PL__t0, PL__t0 + 1, PL__t0 + 2
    tr = get_trie_nodes(gd, ld, A1)
    tr === nothing && return FFALSE

    rc, nid = trie_lookup(ld, tr, 0, -(A2 + 1), false, nothing)
    if rc == 1
        v = tr.nodes[nid].value
        return (v != 0 && unify_value(ld, tr, A3, v)) ? FTRUE : FFALSE
    end
    return trie_error(ld, rc, A2) ? FTRUE : FFALSE
end

# PORT: pl-trie.c trie_term as pl_trie_term2_va
# (PRED_IMPL("trie_term", 2, trie_term, 0))
# DIVERGES: the handle is the integer of `trie_node_handle`, read with `PL_get_int64_ex` (upstream: `PL_get_pointer_ex`); a
# handle naming no live trie or no node is an `existence_error(trie_node, Handle)` (upstream dereferences the pointer).
"`trie_term(+Handle, -Term)`: retrieve the term of a handle `trie_insert/4` returned (pl-trie.c)."
function pl_trie_term2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    gd = _query_gd(ld)
    A1, A2 = PL__t0, PL__t0 + 1
    h = PL_get_int64_ex(ld, A1)
    h === nothing && return FFALSE
    serial = h >> 32
    nid = h & 0xffffffff
    tr = (1 <= serial <= length(gd.tries)) ? gd.tries[serial] : nothing
    if tr === nothing || tr.magic != TRIE_MAGIC || !(1 <= nid <= length(tr.nodes))
        PL_error(ld, ERR_EXISTENCE, mk_sym(T, :trie_node), A1)
        return FFALSE
    end
    rc, _ = unify_trie_term(ld, tr, nid, A2)
    return rc ? FTRUE : FFALSE
end

# PORT: pl-trie.c BeginPredDefs as PL_predicates_from_trie
# DIVERGES: the entries TR1 ports only. `trie_gen/2,3`, `$trie_gen_node/3`, `$trie_property/2`, `trie_insert_insert/lookup_gen/
# lookup_delete` are deferred to TR2, `$trie_compile/2` and `trie_gen_compiled/2,3` to TR4; the registration order of upstream's
# table is kept for the entries here.
"pl-trie.c's registration table (`BeginPredDefs(trie)`): the ported entries."
const PL_predicates_from_trie = (
    PL_extension("is_trie", 1, pl_is_trie1_va, PL_FA_VARARGS),
    PL_extension("trie_new", 1, pl_trie_new1_va, PL_FA_VARARGS),
    PL_extension("trie_destroy", 1, pl_trie_destroy1_va, PL_FA_VARARGS),
    PL_extension("trie_insert", 2, pl_trie_insert2_va, PL_FA_VARARGS),
    PL_extension("trie_insert", 3, pl_trie_insert3_va, PL_FA_VARARGS),
    PL_extension("trie_insert", 4, pl_trie_insert4_va, PL_FA_VARARGS),
    PL_extension("\$trie_insert_abstract", 3, pl_trie_insert_abstract3_va, PL_FA_VARARGS),
    PL_extension("trie_update", 3, pl_trie_update3_va, PL_FA_VARARGS),
    PL_extension("trie_lookup", 3, pl_trie_lookup3_va, PL_FA_VARARGS),
    PL_extension("trie_delete", 3, pl_trie_delete3_va, PL_FA_VARARGS),
    PL_extension("trie_term", 2, pl_trie_term2_va, PL_FA_VARARGS),
)
