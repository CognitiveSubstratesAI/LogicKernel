# UPSTREAM: swipl-devel src/pl-trie.c @ 18168e629eab
# UPSTREAM: swipl-devel src/pl-trie.h @ 18168e629eab
# CLASS: code
# COPYRIGHT: Copyright (c)  2016-2025, VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
# allow-new-artifact: a 1:1 port of swipl-devel src/pl-trie.c (the upstream file was read at the pin; the design and the line ranges are in evidence/TAB1/tr1_partA_status.md and tr1_state.md)
# PIN1 ledger (V10.1.20): pl-trie.c at 18168e62 (the first port: no earlier pin).
# TRIES (pl-trie.c), TAB1 step TR1, part A2a: the trie, its children blocks, its node allocation and its life. This file holds,
# in the order of pl-trie.c: the reserved keys, the trie blob (`trie_blob`, `initTries!`, `trie_symbol`, `symbol_trie`,
# `get_trie`, `trie_error`), `trie_create`, `trie_destroy`, `trie_empty`, `trie_empty_take`, `trie_clean`, the children
# (`get_child`, `next_child!`, `is_leaf_trie_node`, `trie_single_value_node`), the blocks (`block_find` ... `delete_child`),
# the node allocation and the chunks, `clear_node`, `prune_node`, `prune_trie`, `insert_child`, `follow_node`, `prune_error`.
# Part A2b (the lookup and the indirect table) follows.
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
Base.showerror(io::IO, e::TrieRefusal) =
    print(io, "TrieRefusal: ", e.what, " is refused by name (owner ", e.owner, ")")

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
        0, 0, nothing, 0, nothing, nothing, 0                   # lookups, gen_call, worklist, variant, IDG, predicate, serial
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
# DIVERGES: a no-op. Upstream unregisters an atom (no atom reference counts here), erases a record and releases the answer
# trie of a variant table node; the value helpers (records, `isTriePtrValue`) are part B and TB1's.
"Release the value `value` of a node (pl-trie.c `release_value`); a no-op here, see above."
release_value(value::word)::Nothing = nothing

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
        n.value != 0 && release_value(n.value)
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
