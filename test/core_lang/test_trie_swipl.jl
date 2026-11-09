# ORIGINAL: TAB1 TR1 part A's white-box test: the trie core of src/pl-trie.jl (pl-trie.c, pl-indirect.c, the trie types of pl-incl.jl) against upstream's rules at the pin 18168e62.
# test/core_lang/test_trie_swipl.jl — white-box rows, each with its reason; the swipl-compared rows (the PREDs of the trie) are part B's file:
#   * LIFE: trie_create, trie_destroy, trie_clean, empty_trie / trie_empty_take (a referenced trie is kept; the values go to the taker);
#   * CHILDREN: the three forms of `trie_node.children` (0, a single child `(id<<1)|1`, a block `bid<<1`), the growth 2 -> 4 -> 8 -> 16 -> 32 (the index from
#     capacity > 8: `index_bits` = MSB(capacity)+1), the reuse of the freed block's slot, a colliding hash, the dead entries and their revival, the
#     compaction threshold `dead*2 > count` (replace_block: live 0 -> no children, live 1 -> a single child, else a block of the next power of two >= live), the variable masks;
#   * ALLOCATION: TRIE_CONCURRENT (nodes individual, a replaced block lingers until free_lingering_blocks) and chunks (the first TRIE_SINGLE_NODES = 8 nodes
#     individual, then chunks of 1024 bytes doubling to the clamp 16384: (bytes - 72) / 40 nodes each = 23, 49, 100, 203, 407, 407), the head chunk's free
#     list, the node reuse, the sweep at nfree >= 1024 that drops a chunk with no live node;
#   * CLEAR AND PRUNE: prune_node (TN_PRIMARY / TN_SECONDARY / TN_PINNED stop it), prune_trie with its free callback, trie_clear_nodes, trie_single_value_node;
#   * LOOKUP (the engine's cells): trie_lookup_abstract on ground terms (the keys in order, the POP keys), variants (numbered variables restored), the
#     abstraction, a cyclic term, indirect values; trie_insert_flat; trie_lookup_flat;
#   * THE INDIRECT TABLE: equal values one handle, the tag by number kind, a wildcard `gnd_key` (a payload without a grounded key);
#   * THE BLOB REGISTRY and the errors: trie_symbol / symbol_trie / get_trie / get_trie_noex / trie_error;
#   * the SIZES: stat_trie (upstream's constants 40 / 152 / 16 / 32) and trie_table_size.
# Every expected value is derived from upstream's code (each row names the function it checks); nothing here is compared with swipl (part B).
# Kill rows are @test INSIDE a @testset (a failing top-level @test gives no verdict in CI mode).
# Mutants proposed for tools/mutants/TRIE1.py (a later step): see the STATUS A2d section of evidence/TAB1/tr1_partA_status.md.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TT = lk_term_type(Union{Int64, Float64, String, BigInt})
# a payload that holds a value without a grounded key (`gnd_key` is `nothing`: a WILDCARD, src/default_term.jl `gnd_value_key`)
const _TW = lk_term_type(Union{Int64, Float64, String, BigInt, Vector{Int64}})

# ---- helpers (term-building ones take `::Type{T}`) ----

"The keys of the live children of node `nid`, in order."
function _tr_keys(tr, nid::Int)::Vector{UInt64}
    ks = UInt64[]
    it = LK.init_child_iter(nid)
    while true
        c, k = LK.next_child!(tr, it)
        c == 0 && return ks
        push!(ks, k)
    end
end

"The keys from the root down to node `nid`."
function _tr_path(tr, nid::Int)::Vector{UInt64}
    ks = UInt64[]
    while tr.nodes[nid].parent != 0
        pushfirst!(ks, tr.nodes[nid].key)
        nid = tr.nodes[nid].parent
    end
    return ks
end

"A trie of `T` with `n` children under the root, keys 1..n (opaque); `(trie, ids)`."
function _tr_fan(::Type{T}, n::Int; flags::UInt32=UInt32(0)) where {T}
    tr = LK.trie_create(T)
    tr.flags = flags
    ids = Int[LK.insert_child(tr, 1, UInt64(k)) for k in 1:n]
    return tr, ids
end

"The chain of the chunks of `tr`, newest first."
function _tr_chunks(tr)
    cs = LK.trie_node_chunk[]
    c = tr.chunks
    while c !== nothing
        push!(cs, c)
        c = c.next
    end
    return cs
end

"The block of node `nid`."
_tr_block(tr, nid::Int) = tr.blocks[LK.children_block_id(tr.nodes[nid].children)]

"An engine with the values of `vs` put into consecutive term references (slot `t + i` holds `vs[i]`); `(gd, ld, t)`. `shared`: one variable map."
function _tr_engine(::Type{T}, vs::Vector{T}; shared::Bool=false) where {T}
    gd = LK.PL_global_data{T}()
    ld = LK.PL_local_data{T}(gd)
    LK.PL_open_foreign_frame(ld)
    t = LK.PL_new_term_refs(ld, length(vs))
    pvm = LK.PutVarMap()
    for (i, v) in enumerate(vs)
        LK.putSlotValue!(ld, t + i, v, shared ? pvm : LK.PutVarMap())
    end
    return gd, ld, t
end

"The atom word of the symbol `name`."
_trw(ld, ::Type{T}, name::Symbol) where {T} = LK._atom_word!(ld, lk_sym(T, name))
"The functor word `name/arity`."
_trf(ld, ::Type{T}, name::Symbol, arity::Int) where {T} =
    LK.lookupFunctorDef(ld.functors, _trw(ld, T, name), arity)
"The compound `name(args...)`."
_trx(::Type{T}, name::Symbol, args::T...) where {T} = mk_expr(T, T[lk_sym(T, name), args...])
"The variable `n` (a caller's)."
_trv(::Type{T}, n::Int) where {T} = lk_var(T, UInt64(n))
"The numbered trie variable key `n`."
_trvar(n::Int) = LK.consTagged(n, LK.TAGEX_VAR)

"The formal of the pending exception as `(functor word, name of the first argument)`, or `nothing` without one."
function _tr_formal(ld)
    ld.exception_term == 0 && return nothing
    _, b, _ = LK._deref_loc(ld, -(ld.exception_term + 1))               # error(Formal, _)
    _, f, _ = LK._deref_loc(ld, LK.valPtr(b) + 1)
    _, a1, _ = LK._deref_loc(ld, LK.valPtr(f) + 1)
    return (ld.gstack[LK.valPtr(f)], lk_name(LK._atom_value(ld, a1)))
end

# ---- LIFE ----

function _tr_life_rows(::Type{T}) where {T}
    tr = LK.trie_create(T)
    @test tr.magic == LK.TRIE_MAGIC
    @test tr.node_count == 1 && length(tr.nodes) == 1 && tr.value_count == 0
    @test tr.flags == 0 && tr.symbol == 0 && tr.serial == 0 && tr.references == 0
    @test tr.chunks === nothing && tr.indirects === nothing && isempty(tr.blocks) && tr.clause == 0
    @test tr.nodes[1].parent == 0 && tr.nodes[1].children == 0 && tr.nodes[1].key == 0 && tr.nodes[1].value == 0

    # a referenced trie is not emptied (pl-trie.c empty_trie: `references == 0`), and trie_empty_take does not call the taker
    LK.insert_child(tr, 1, UInt64(5))
    LK.insert_child(tr, 1, UInt64(6))
    tr.references = 1
    @test !LK.empty_trie(tr, nothing)
    LK.trie_empty(tr)
    @test !LK.trie_empty_take(tr, v -> error("no value is taken from a trie in use"))
    @test tr.node_count == 3 && length(tr.nodes) == 3
    # an unreferenced one hands every value to the taker, and the arenas are reset
    tr.references = 0
    tr.nodes[3].value = UInt64(9)
    tr.nodes[3].flags |= LK.TN_PRIMARY
    tr.value_count = 1
    taken = UInt64[]
    @test LK.trie_empty_take(tr, v -> push!(taken, v))
    @test taken == [UInt64(9)]
    @test tr.node_count == 1 && length(tr.nodes) == 1 && tr.value_count == 0
    @test isempty(tr.blocks) && isempty(tr.free_ids) && isempty(tr.free_blocks) && tr.nodes[1].children == 0
    # empty_trie clears the discard flags
    tr.flags = LK.TRIE_DISCARDABLE | LK.TRIE_ISSET
    @test LK.empty_trie(tr, nothing)
    @test tr.flags == LK.TRIE_ISSET

    # trie_destroy: marks, empties
    tr2, _ = _tr_fan(T, 3)
    LK.trie_destroy(tr2)
    @test tr2.magic == LK.TRIE_CMAGIC && tr2.node_count == 1 && length(tr2.nodes) == 1
    # a destroyed trie still in use keeps its nodes until it is cleaned up
    tr3, _ = _tr_fan(T, 2)
    tr3.references = 1
    LK.trie_destroy(tr3)
    @test tr3.magic == LK.TRIE_CMAGIC && tr3.node_count == 3
    LK.trie_clean(tr3)
    @test tr3.node_count == 3
    tr3.references = 0
    LK.trie_clean(tr3)
    @test tr3.node_count == 1
    # trie_clean leaves a live trie alone
    tr4, _ = _tr_fan(T, 2)
    LK.trie_clean(tr4)
    @test tr4.magic == LK.TRIE_MAGIC && tr4.node_count == 3
    # trie_discard_clause: no clause, no refusal; a clause is refused by name (owner TR4)
    @test LK.trie_discard_clause(tr4) === nothing
    tr4.clause = UInt64(1)
    @test_throws LK.TrieRefusal LK.trie_discard_clause(tr4)
    tr4.clause = UInt64(0)
    # trie_ensure_nodes: true unless discarded, whose restore is refused by name
    @test LK.trie_ensure_nodes(tr4)
    tr4.flags = LK.TRIE_DISCARDED
    @test_throws LK.TrieRefusal LK.trie_ensure_nodes(tr4)
    # a node of a table / variant trie that reaches tbl_release_node is refused by name (owner TB1)
    tr5, ids = _tr_fan(T, 1)
    tr5.flags = LK.TRIE_ISVARIANT
    err = try
        LK.release_node(tr5, ids[1])
        nothing
    catch e
        e
    end
    @test err isa LK.TrieRefusal && err.owner == "TB1"
    tr5.flags = LK.TRIE_ISTABLE
    LK.release_node(tr5, ids[1])                       # TN_DELAYINFO not set: nothing to release
    tr5.nodes[ids[1]].flags |= LK.TN_DELAYINFO
    @test_throws LK.TrieRefusal LK.release_node(tr5, ids[1])
    return nothing
end

@testset "trie life: create, empty, destroy, clean" begin
    _tr_life_rows(_TT)
end

# ---- CHILDREN ----

function _tr_children_rows(::Type{T}) where {T}
    tr = LK.trie_create(T)
    root = tr.nodes[1]
    @test LK.is_leaf_trie_node(tr, 1) && !LK.trie_has_children(root)
    @test LK.get_child(tr, 1, UInt64(10)) == 0 && _tr_keys(tr, 1) == UInt64[]

    # the first child is a single child: children == (id << 1) | 1
    c1 = LK.insert_child(tr, 1, UInt64(10))
    @test c1 == 2 && tr.nodes[c1].parent == 1 && tr.nodes[c1].key == 10
    @test root.children == 5 && root.children == LK.single_child_code(c1)
    @test LK.is_single_child(root.children) && LK.single_child(root.children) == c1
    @test isempty(tr.blocks)
    @test LK.get_child(tr, 1, UInt64(10)) == c1 && LK.get_child(tr, 1, UInt64(11)) == 0
    @test !LK.is_leaf_trie_node(tr, 1) && _tr_keys(tr, 1) == [10]

    # the second makes a block of capacity 2
    c2 = LK.insert_child(tr, 1, UInt64(11))
    @test c2 == 3 && !LK.is_single_child(root.children) && root.children == 2 && root.children == LK.block_code(1)
    b = tr.blocks[1]
    @test b.count == 2 && b.capacity == 2 && b.dead == 0 && b.index_bits == 0 && isempty(b.index)
    @test b.entries == [LK.trie_child(UInt64(10), c1), LK.trie_child(UInt64(11), c2)]
    @test b.var_mask == 0 && b.attvar_mask == 0
    @test LK.block_find(b, UInt64(11)) == 2 && LK.block_find(b, UInt64(10)) == 1 && LK.block_find(b, UInt64(12)) == 0

    # the third doubles it: the new block is made before the old one is freed, so the old slot is free afterwards
    c3 = LK.insert_child(tr, 1, UInt64(12))
    @test root.children == LK.block_code(2) && tr.blocks[1] === nothing && tr.free_blocks == [1]
    b = tr.blocks[2]
    @test b.count == 3 && b.capacity == 4 && b.index_bits == 0
    @test b.entries[1:3] == [LK.trie_child(UInt64(10), c1), LK.trie_child(UInt64(11), c2), LK.trie_child(UInt64(12), c3)]
    LK.insert_child(tr, 1, UInt64(13))                 # fills it
    @test root.children == LK.block_code(2) && tr.blocks[2].count == 4
    # the fifth: capacity 8, and it reuses the freed slot 1
    LK.insert_child(tr, 1, UInt64(14))
    @test root.children == LK.block_code(1) && tr.blocks[2] === nothing && tr.free_blocks == [2]
    @test tr.blocks[1].capacity == 8 && tr.blocks[1].count == 5 && tr.blocks[1].index_bits == 0
    for k in 15:17
        LK.insert_child(tr, 1, UInt64(k))
    end
    @test tr.blocks[1].count == 8 && tr.blocks[1].capacity == 8 && root.children == LK.block_code(1)
    # the ninth: capacity 16 > TRIE_LINEAR_MAX, so an index of 1 << (MSB(16) + 1) = 32 slots
    LK.insert_child(tr, 1, UInt64(18))
    b = _tr_block(tr, 1)
    @test b.capacity == 16 && b.count == 9 && b.index_bits == 5 && length(b.index) == 32
    @test count(!=(0), b.index) == 9 && sort(Int.(filter(!=(0), b.index))) == collect(1:9)
    @test LK.TRIE_LINEAR_MAX == 8
    # up to 17 children: capacity 32, 64 index slots
    for k in 19:26
        LK.insert_child(tr, 1, UInt64(k))
    end
    b = _tr_block(tr, 1)
    @test b.capacity == 32 && b.count == 17 && b.index_bits == 6 && length(b.index) == 64
    @test _tr_keys(tr, 1) == UInt64.(10:26)
    ids = Dict(k => LK.get_child(tr, 1, UInt64(k)) for k in 10:26)
    @test all(k -> ids[k] != 0 && tr.nodes[ids[k]].key == k && tr.nodes[ids[k]].parent == 1, 10:26)
    @test LK.get_child(tr, 1, UInt64(9)) == 0 && LK.get_child(tr, 1, UInt64(27)) == 0

    # a colliding hash: two keys of one slot are both found (open addressing, linear probing)
    h = LK.child_hash(UInt64(10), 6)
    k2 = UInt64(1000)
    while LK.child_hash(k2, 6) != h || k2 in UInt64.(10:26)
        k2 += 1
    end
    c27 = LK.insert_child(tr, 1, k2)
    b = _tr_block(tr, 1)
    @test b.count == 18 && LK.get_child(tr, 1, k2) == c27 && LK.get_child(tr, 1, UInt64(10)) == ids[10]
    @test LK.block_find(b, k2) == 18 && LK.block_find(b, UInt64(10)) == 1
    @test all(0 .<= [LK.child_hash(UInt64(k), 6) for k in (1, 10, 77, 12345)] .< 64)

    # a dead entry: the key stays in the block, the child is 0, the others are intact
    @test !LK.delete_child(tr, 1, ids[15], false)
    b = _tr_block(tr, 1)
    @test b.dead == 1 && b.count == 18 && LK.block_find(b, UInt64(15)) > 0
    @test LK.get_child(tr, 1, UInt64(15)) == 0 && LK.get_child(tr, 1, UInt64(16)) == ids[16]
    @test !(UInt64(15) in _tr_keys(tr, 1)) && length(_tr_keys(tr, 1)) == 17
    @test !LK.is_leaf_trie_node(tr, 1)
    LK.destroy_node(tr, ids[15])
    @test tr.free_ids == [ids[15]]
    # ... which is revived by the same key: no new entry, `dead` back to 0, and the freed node id is reused
    n15 = LK.insert_child(tr, 1, UInt64(15))
    b = _tr_block(tr, 1)
    @test n15 == ids[15] && b.dead == 0 && b.count == 18 && LK.get_child(tr, 1, UInt64(15)) == n15
    @test b.entries[LK.block_find(b, UInt64(15))] == LK.trie_child(UInt64(15), n15) && tr.nodes[n15].parent == 1
    @test isempty(tr.free_ids)

    # a single child deleted: no children, the node is a leaf, delete_child says it is empty
    tr1, i1 = _tr_fan(T, 1)
    @test LK.delete_child(tr1, 1, i1[1], true) && tr1.nodes[1].children == 0 && LK.is_leaf_trie_node(tr1, 1)
    # a delete of a node that is not the single child changes nothing and says it is not empty
    tr1, i1 = _tr_fan(T, 1)
    other = LK.new_trie_node(tr1, UInt64(99))
    @test !LK.delete_child(tr1, 1, other, true) && tr1.nodes[1].children == LK.single_child_code(i1[1])
    return nothing
end

@testset "trie children: single child, blocks, the index, dead entries" begin
    _tr_children_rows(_TT)
end

function _tr_compaction_rows(::Type{T}) where {T}
    # 4 children: deleting 2 (dead*2 > count is 4 > 4: no) keeps the block, the third (6 > 4) replaces it by the single child left
    tr, ids = _tr_fan(T, 4)
    bid = LK.children_block_id(tr.nodes[1].children)
    @test bid == 2 && tr.free_blocks == [1]
    @test !LK.delete_child(tr, 1, ids[1], true) && !LK.delete_child(tr, 1, ids[2], true)
    @test tr.nodes[1].children == LK.block_code(bid) && tr.blocks[bid].dead == 2
    @test !LK.delete_child(tr, 1, ids[3], true)
    @test tr.nodes[1].children == LK.single_child_code(ids[4]) && tr.blocks[bid] === nothing && tr.free_blocks == [1, 2]
    @test LK.get_child(tr, 1, UInt64(4)) == ids[4] && LK.get_child(tr, 1, UInt64(1)) == 0

    # 2 children: the second delete makes dead == count: empty, no children
    tr, ids = _tr_fan(T, 2)
    @test !LK.delete_child(tr, 1, ids[1], true)
    @test LK.delete_child(tr, 1, ids[2], true)
    @test tr.nodes[1].children == 0 && LK.is_leaf_trie_node(tr, 1)

    # 8 children: 4 dead is not enough (8 > 8: no), the fifth gives a new block of capacity 4 with the 3 live ones, in order
    tr, ids = _tr_fan(T, 8)
    bid = LK.children_block_id(tr.nodes[1].children)
    for i in 1:4
        LK.delete_child(tr, 1, ids[i], true)
    end
    @test LK.children_block_id(tr.nodes[1].children) == bid && tr.blocks[bid].dead == 4
    LK.delete_child(tr, 1, ids[5], true)
    b = _tr_block(tr, 1)
    @test b.capacity == 4 && b.count == 3 && b.dead == 0 && b.index_bits == 0
    @test _tr_keys(tr, 1) == UInt64.(6:8) && tr.blocks[bid] === nothing
    @test [LK.get_child(tr, 1, UInt64(k)) for k in 6:8] == ids[6:8]

    # 16 children, 9 deleted: 9*2 > 16 gives 7 live in a block of capacity 8 (the next power of two >= live)
    tr, ids = _tr_fan(T, 16)
    for i in 1:8
        LK.delete_child(tr, 1, ids[i], true)
    end
    @test tr.blocks[LK.children_block_id(tr.nodes[1].children)].capacity == 16
    LK.delete_child(tr, 1, ids[9], true)
    b = _tr_block(tr, 1)
    @test b.capacity == 8 && b.count == 7 && b.dead == 0 && b.index_bits == 0 && _tr_keys(tr, 1) == UInt64.(10:16)

    # without `compact`, the delete leaves the block; compact_children applies the same threshold
    tr, ids = _tr_fan(T, 4)
    LK.delete_child(tr, 1, ids[1], false)
    LK.delete_child(tr, 1, ids[2], false)
    bid = LK.children_block_id(tr.nodes[1].children)
    LK.compact_children(tr, 1)
    @test LK.children_block_id(tr.nodes[1].children) == bid && tr.blocks[bid].dead == 2      # 2*2 > 4 is false
    LK.delete_child(tr, 1, ids[3], false)
    LK.compact_children(tr, 1)
    @test tr.nodes[1].children == LK.single_child_code(ids[4])
    # dead == count without `compact`: delete_child says empty, the block stays, compact_children removes it
    tr, ids = _tr_fan(T, 2)
    LK.delete_child(tr, 1, ids[1], false)
    @test LK.delete_child(tr, 1, ids[2], false)
    @test tr.nodes[1].children != 0 && LK.is_leaf_trie_node(tr, 1) && _tr_keys(tr, 1) == UInt64[]
    LK.compact_children(tr, 1)
    @test tr.nodes[1].children == 0
    LK.compact_children(tr, 1)                         # nothing to do, nothing breaks
    @test tr.nodes[1].children == 0

    # the variable masks: bit n-1 for variable n < 32, bit 31 for 32 and up; attributed variables in their own mask; kept when the block grows, rebuilt by a compaction
    tr = LK.trie_create(T)
    v3 = LK.insert_child(tr, 1, _trvar(3))
    LK.insert_child(tr, 1, _trvar(31))
    b = _tr_block(tr, 1)
    @test b.var_mask == (UInt32(1) << 2) | (UInt32(1) << 30) && b.attvar_mask == 0
    LK.insert_child(tr, 1, _trvar(32))
    b = _tr_block(tr, 1)
    @test b.var_mask == (UInt32(1) << 2) | (UInt32(1) << 30) | LK.VMASK_SCAN && LK.VMASK_SCAN == UInt32(1) << 31
    LK.insert_child(tr, 1, LK.consTagged(2, LK.TAGEX_TRIE_ATTVAR))
    LK.insert_child(tr, 1, UInt64(77))                 # a plain key (grows the block to 8, copying the masks)
    b = _tr_block(tr, 1)
    @test b.capacity == 8 && b.var_mask == (UInt32(1) << 2) | (UInt32(1) << 30) | LK.VMASK_SCAN
    @test b.attvar_mask == UInt32(1) << 1
    @test LK.VMASKBITS == 32
    # 8 children [V3, V31, p1..p6]: delete V31 and 4 plain ones: the new block is built by block_append, so V31's bit is gone
    tr = LK.trie_create(T)
    ids = Int[LK.insert_child(tr, 1, k) for k in (_trvar(3), _trvar(31), UInt64.(101:106)...)]
    for i in 2:6
        LK.delete_child(tr, 1, ids[i], true)
    end
    b = _tr_block(tr, 1)
    @test b.count == 3 && b.var_mask == UInt32(1) << 2 && _tr_keys(tr, 1) == [_trvar(3), UInt64(105), UInt64(106)]
    @test ids[1] == LK.get_child(tr, 1, _trvar(3))
    return nothing
end

@testset "trie children: compaction threshold, replace_block, variable masks" begin
    _tr_compaction_rows(_TT)
end

# ---- ALLOCATION ----

function _tr_concurrent_rows(::Type{T}) where {T}
    # TRIE_CONCURRENT: every node individual (no chunks), a replaced block lingers
    tr = LK.trie_create(T)
    tr.flags = LK.TRIE_CONCURRENT
    for k in 1:40
        LK.new_trie_node(tr, UInt64(k))
    end
    @test tr.chunks === nothing && tr.node_count == 41 && length(tr.nodes) == 41
    @test all(n -> n.chunk === nothing && (n.flags & LK.TN_CHUNKED) == 0, tr.nodes)
    LK.free_trie_node(tr, 7)
    @test tr.free_ids == [7]
    nid = LK.new_trie_node(tr, UInt64(500))
    @test nid == 7 && isempty(tr.free_ids) && tr.nodes[7].key == 500 && tr.nodes[7].parent == 0 && tr.node_count == 42
    @test LK.alloc_trie_node(tr) == (0, nothing, false)

    tr, ids = _tr_fan(T, 2; flags=LK.TRIE_CONCURRENT)
    @test tr.lingering == [] && tr.free_blocks == []
    LK.insert_child(tr, 1, UInt64(3))                  # the block of 2 is replaced by one of 4: it lingers
    @test tr.lingering == [1] && tr.blocks[1] !== nothing && tr.free_blocks == [] && LK.children_block_id(tr.nodes[1].children) == 2
    LK.free_lingering_blocks(tr)
    @test isempty(tr.lingering) && tr.blocks[1] === nothing && tr.free_blocks == [1]
    # compaction retires the block the same way
    for k in 4:8
        LK.insert_child(tr, 1, UInt64(k))
    end
    @test LK.children_block_id(tr.nodes[1].children) == 1 && tr.lingering == [2]       # 4 -> 8 took the freed slot 1
    # trie_destroy frees the lingering blocks too
    LK.trie_destroy(tr)
    @test isempty(tr.lingering) && isempty(tr.blocks) && tr.node_count == 1
    # a trie without the flag: free_lingering_blocks does nothing
    tr, _ = _tr_fan(T, 3)
    tr.lingering = [1]
    LK.free_lingering_blocks(tr)
    @test tr.lingering == [1]
    return nothing
end

@testset "trie nodes: TRIE_CONCURRENT allocates individually, blocks linger" begin
    _tr_concurrent_rows(_TT)
end

function _tr_chunk_rows(::Type{T}) where {T}
    tr = LK.trie_create(T)
    ids = Int[]
    for k in 1:8
        push!(ids, LK.new_trie_node(tr, UInt64(k)))
    end
    # the first TRIE_SINGLE_NODES (8) nodes are individual
    @test tr.chunks === nothing && tr.node_count == 9 && ids == collect(2:9) && LK.TRIE_SINGLE_NODES == 8
    @test all(n -> n.chunk === nothing && (n.flags & LK.TN_CHUNKED) == 0, tr.nodes)
    # the ninth starts the first chunk: 1024 bytes, (1024 - 72) / 40 = 23 nodes
    n9 = LK.new_trie_node(tr, UInt64(9))
    c = tr.chunks
    @test c !== nothing && c.bytes == 1024 && c.size == 23 && c.used == 1 && c.live == 1 && c.next === nothing
    @test c.free == 0 && c.nfree == 0 && c.sweep_at == 1024 && c.flags == 0
    @test (tr.nodes[n9].flags & LK.TN_CHUNKED) != 0 && tr.nodes[n9].chunk === c && (tr.nodes[n9].flags >> LK.TN_CHUNK_INDEX_SHIFT) == 0
    @test LK.OFFSETOF_TRIE_NODE_CHUNK_NODES == 72 && LK.SIZEOF_TRIE_NODE == 40 && LK.TRIE_CHUNK_MIN == 1024 && LK.TRIE_CHUNK_MAX == 16384
    n10 = LK.new_trie_node(tr, UInt64(10))
    @test (tr.nodes[n10].flags >> LK.TN_CHUNK_INDEX_SHIFT) == 1 && c.used == 2 && c.live == 2
    first_chunk_ids = [n9, n10]
    for k in 11:31                                     # the chunk is full at 23 nodes
        push!(first_chunk_ids, LK.new_trie_node(tr, UInt64(k)))
    end
    @test length(first_chunk_ids) == 23 && tr.chunks === c && c.used == 23 && c.live == 23
    # the 24th starts the second: 2048 bytes, 49 nodes, the first chunk behind it, the sweep threshold inherited
    LK.new_trie_node(tr, UInt64(32))
    c2 = tr.chunks
    @test c2 !== c && c2.bytes == 2048 && c2.size == 49 && c2.next === c && c2.used == 1 && c2.live == 1 && c2.sweep_at == 1024
    @test c.live == 23
    # the node count it gives up to the sixth chunk: 23 + 49 + 100 + 203 + 407 + 1 chunked nodes
    for k in 33:(31 + 49 + 100 + 203 + 407 + 1 - 24 + 24)
        LK.new_trie_node(tr, UInt64(k))
    end
    cs = _tr_chunks(tr)
    @test [Int(c.bytes) for c in cs] == [16384, 16384, 8192, 4096, 2048, 1024]
    @test [Int(c.size) for c in cs] == [407, 407, 203, 100, 49, 23]
    @test [Int(c.used) for c in cs] == [1, 407, 203, 100, 49, 23] && [Int(c.live) for c in cs] == [1, 407, 203, 100, 49, 23]
    @test tr.node_count == 1 + 8 + 23 + 49 + 100 + 203 + 407 + 1

    # a freed chunk node: key 0, its chunk's live count down, pushed on the HEAD chunk's free list (linked through `parent`)
    head = tr.chunks
    f1, f2 = first_chunk_ids[1], first_chunk_ids[2]
    LK.free_trie_node(tr, f1)
    @test tr.nodes[f1].key == 0 && cs[end].live == 22 && head.free == f1 && head.nfree == 1 && tr.nodes[f1].parent == 0
    LK.free_trie_node(tr, f2)
    @test head.free == f2 && head.nfree == 2 && tr.nodes[f2].parent == f1 && cs[end].live == 21 && isempty(tr.free_ids)
    # the next new node takes the newest freed id: its chunk and its index in the chunk stay
    used_before = head.used
    r = LK.new_trie_node(tr, UInt64(777))
    @test r == f2 && head.free == f1 && head.nfree == 1 && cs[end].live == 22 && head.used == used_before
    @test tr.nodes[r].key == 777 && tr.nodes[r].chunk === cs[end] && (tr.nodes[r].flags & LK.TN_CHUNKED) != 0 && (tr.nodes[r].flags >> LK.TN_CHUNK_INDEX_SHIFT) == 1
    r2 = LK.new_trie_node(tr, UInt64(778))
    @test r2 == f1 && head.free == 0 && head.nfree == 0 && cs[end].live == 23 && (tr.nodes[r2].flags >> LK.TN_CHUNK_INDEX_SHIFT) == 0
    # an individual node freed goes to free_ids, not to the chunk
    LK.free_trie_node(tr, 5)
    @test tr.free_ids == [5] && head.nfree == 0
    return nothing
end

@testset "trie nodes: individual nodes, chunks 1024 doubling to 16384, the free list" begin
    _tr_chunk_rows(_TT)
end

function _tr_sweep_rows(::Type{T}) where {T}
    # a chain of 1500 nodes; chunks 23 + 49 + 100 + 203 + 407 + 407 + 407: the last holds 303 of the 1492 chunked nodes
    tr = LK.trie_create(T)
    nid = 1
    for k in 1:1500
        nid = LK.insert_child(tr, nid, UInt64(k))
    end
    @test tr.node_count == 1501
    cs = _tr_chunks(tr)
    @test [Int(c.size) for c in cs] == [407, 407, 407, 203, 100, 49, 23] && [Int(c.used) for c in cs] == [303, 407, 407, 203, 100, 49, 23]
    @test LK.is_ground_trie_node(tr, nid)
    # pruning from the leaf frees every node. The first sweep comes at nfree == 1024 (and nfree > node_count): then the 303 + 407 + 314 newest
    # chunked nodes are free, the middle chunk (407, no live node) goes, the head and the chunk with live nodes stay
    LK.prune_node(tr, nid)
    @test tr.node_count == 1 && tr.nodes[1].children == 0
    cs2 = _tr_chunks(tr)
    @test length(cs2) == 6 && cs2[1] === cs[1] && cs2[2] === cs[3]          # the chunk cs[2] (live 0 at the sweep) is gone
    @test cs2[1].sweep_at == 1234 && cs2[1].nfree == 1085
    @test length(tr.free_ids) == 8 + 407                                    # the 8 individual nodes, and the nodes of the dropped chunk
    # the nodes of the dropped chunk are the ids of cs[2]'s nodes: none of them is on the free list of the head
    free_listed = Int[]
    id = cs2[1].free
    while id != 0
        push!(free_listed, id)
        id = tr.nodes[id].parent
    end
    @test length(free_listed) == 1085 && isempty(intersect(free_listed, tr.free_ids))
    return nothing
end

@testset "trie nodes: the sweep drops a chunk with no live node" begin
    _tr_sweep_rows(_TT)
end

# ---- CLEAR AND PRUNE ----

function _tr_prune_rows(::Type{T}) where {T}
    # a chain root - a - b - c: pruning from c takes the whole branch
    tr = LK.trie_create(T)
    a = LK.insert_child(tr, 1, UInt64(10))
    b = LK.insert_child(tr, a, UInt64(20))
    c = LK.insert_child(tr, b, UInt64(30))
    @test _tr_path(tr, c) == UInt64[10, 20, 30] && tr.node_count == 4
    LK.prune_node(tr, c)
    @test tr.node_count == 1 && tr.nodes[1].children == 0 && sort(tr.free_ids) == [a, b, c] && tr.free_ids == [c, b, a]
    # a flag on b stops it: only c goes
    for fl in (LK.TN_PRIMARY, LK.TN_SECONDARY, LK.TN_PINNED)
        tr = LK.trie_create(T)
        a = LK.insert_child(tr, 1, UInt64(10))
        b = LK.insert_child(tr, a, UInt64(20))
        c = LK.insert_child(tr, b, UInt64(30))
        tr.nodes[b].flags |= fl
        LK.prune_node(tr, c)
        @test tr.node_count == 3 && tr.nodes[b].children == 0 && LK.get_child(tr, a, UInt64(20)) == b && LK.get_child(tr, b, UInt64(30)) == 0
        @test tr.free_ids == [c]
        # the node itself carrying the flag is not pruned at all
        LK.prune_node(tr, b)
        @test tr.node_count == 3
    end
    # a branch point: pruning c leaves b findable; pruning b afterwards takes a as well
    tr = LK.trie_create(T)
    a = LK.insert_child(tr, 1, UInt64(10))
    b = LK.insert_child(tr, a, UInt64(20))
    c = LK.insert_child(tr, a, UInt64(30))
    LK.prune_node(tr, c)
    @test tr.node_count == 3 && LK.get_child(tr, a, UInt64(20)) == b && LK.get_child(tr, a, UInt64(30)) == 0 && _tr_keys(tr, a) == [20]
    LK.prune_node(tr, b)
    @test tr.node_count == 1 && tr.nodes[1].children == 0
    # the root is never pruned
    LK.prune_node(tr, 1)
    @test tr.node_count == 1
    # prune_error: adds the error key under the node and prunes it, so a node with no flags goes too
    tr = LK.trie_create(T)
    a = LK.insert_child(tr, 1, UInt64(10))
    tr.nodes[a].flags |= LK.TN_PRIMARY
    b = LK.insert_child(tr, a, UInt64(20))
    LK.prune_error(tr, b)
    @test tr.node_count == 3 && LK.get_child(tr, b, LK.TRIE_ERROR_VAL) == 0 && LK.get_child(tr, a, UInt64(20)) == b
    # (the error key is a reserved key, `is_trie_key_pop` of it is 0)
    @test LK.IS_TRIE_KEY_POP(LK.TRIE_ERROR_VAL) == 0 && LK.IS_TRIE_KEY_POP(LK.TRIE_KEY_ABSENT) == 0 && LK.TRIE_ERROR_VAL != LK.TRIE_KEY_ABSENT
    @test LK.IS_TRIE_KEY_POP(LK.TRIE_KEY_POP(1)) == 1 && LK.IS_TRIE_KEY_POP(LK.TRIE_KEY_POP(7)) == 7 && LK.IS_TRIE_KEY_POP(_trvar(11)) == 0 && LK.IS_TRIE_KEY_POP(UInt64(5)) == 0

    # prune_trie: the branches that end in no value go, with the callback on each leaf it meets (root - a - {b, c}, c a value)
    tr = LK.trie_create(T)
    a = LK.insert_child(tr, 1, UInt64(10))
    b = LK.insert_child(tr, a, UInt64(20))
    c = LK.insert_child(tr, a, UInt64(30))
    tr.nodes[c].flags |= LK.TN_PRIMARY
    leaves = Int[]
    LK.prune_trie(tr, 1, id -> push!(leaves, id))
    @test sort(leaves) == [b, c] && tr.node_count == 3
    @test LK.get_child(tr, a, UInt64(30)) == c && LK.get_child(tr, a, UInt64(20)) == 0 && _tr_keys(tr, a) == [30]
    # a trie with no value at all is emptied down to the root
    tr, _ = _tr_fan(T, 5)
    LK.prune_trie(tr, 1)
    @test tr.node_count == 1 && tr.nodes[1].children == 0
    # a deeper one: the root has a chain and a fan; the chain (no value) goes, the value branch stays
    tr = LK.trie_create(T)
    x1 = LK.insert_child(tr, 1, UInt64(1))
    x2 = LK.insert_child(tr, x1, UInt64(2))
    y1 = LK.insert_child(tr, 1, UInt64(3))
    y2 = LK.insert_child(tr, y1, UInt64(4))
    y3 = LK.insert_child(tr, y1, UInt64(5))
    tr.nodes[y3].flags |= LK.TN_PRIMARY
    LK.prune_trie(tr, 1)
    @test tr.node_count == 3 && _tr_keys(tr, 1) == [3] && _tr_keys(tr, y1) == [5]

    # trie_single_value_node: value_count 1 and a chain of single children down to the value
    tr = LK.trie_create(T)
    a = LK.insert_child(tr, 1, UInt64(10))
    b = LK.insert_child(tr, a, UInt64(20))
    tr.nodes[b].value = UInt64(5)
    @test LK.trie_single_value_node(tr) == 0           # value_count is 0
    tr.value_count = 1
    @test LK.trie_single_value_node(tr) == b
    tr.value_count = 2
    @test LK.trie_single_value_node(tr) == 0
    tr.value_count = 1
    LK.insert_child(tr, a, UInt64(21))                 # a branch before the value
    tr.nodes[b].value = UInt64(0)
    tr.nodes[a].value = UInt64(0)
    tr2, ids = _tr_fan(T, 2)
    tr2.nodes[ids[1]].value = UInt64(5)
    tr2.value_count = 1
    @test LK.trie_single_value_node(tr2) == 0          # the root holds a block, not a single child
    tr3 = LK.trie_create(T)
    tr3.nodes[1].value = UInt64(8)
    tr3.value_count = 1
    @test LK.trie_single_value_node(tr3) == 1          # the root itself
    return nothing
end

@testset "trie prune: prune_node, prune_trie, the value node" begin
    _tr_prune_rows(_TT)
end

function _tr_clear_rows(::Type{T}) where {T}
    tr = LK.trie_create(T)
    for k in 1:40
        LK.insert_child(tr, 1, UInt64(k))
    end
    deep = LK.get_child(tr, 1, UInt64(5))
    for k in 1:12
        deep = LK.insert_child(tr, deep, UInt64(100 + k))
    end
    @test tr.node_count == 53 && tr.chunks !== nothing && !isempty(tr.blocks)
    tr.nodes[3].value = UInt64(7)
    tr.nodes[3].flags |= LK.TN_PRIMARY
    tr.nodes[20].value = UInt64(9)
    tr.nodes[20].flags |= LK.TN_PRIMARY
    tr.nodes[deep].value = UInt64(11)
    tr.value_count = 3
    tr.indirects = LK.new_indirect_table(T)
    vals = UInt64[]
    @test LK.empty_trie(tr, v -> push!(vals, v))
    @test sort(vals) == UInt64[7, 9, 11]
    @test tr.node_count == 1 && length(tr.nodes) == 1 && tr.chunks === nothing && tr.indirects === nothing && tr.value_count == 0
    @test isempty(tr.blocks) && isempty(tr.free_ids) && isempty(tr.free_blocks) && tr.nodes[1].children == 0
    # the trie is usable again afterwards
    n = LK.insert_child(tr, 1, UInt64(1))
    @test n == 2 && tr.node_count == 2 && LK.get_child(tr, 1, UInt64(1)) == 2
    # trie_clear_nodes (no taker): the nodes go, the flag-less trie's individual nodes too
    LK.trie_clear_nodes(tr)
    @test tr.node_count == 1 && length(tr.nodes) == 1
    # a CONCURRENT trie clears its lingering blocks
    tr, _ = _tr_fan(T, 20; flags=LK.TRIE_CONCURRENT)
    @test !isempty(tr.lingering)
    LK.trie_clear_nodes(tr)
    @test isempty(tr.lingering) && isempty(tr.blocks) && tr.node_count == 1
    return nothing
end

@testset "trie clear: values to the taker, the arenas reset" begin
    _tr_clear_rows(_TT)
end

# ---- WALK AND SIZES ----

function _tr_walk_rows(::Type{T}) where {T}
    tr = LK.trie_create(T)
    a = LK.insert_child(tr, 1, UInt64(10))
    b = LK.insert_child(tr, 1, UInt64(11))
    c = LK.insert_child(tr, a, UInt64(12))
    visited = Int[]
    @test LK.map_trie_node(tr, 1, (t, id) -> (push!(visited, id); nothing)) === nothing
    @test visited == [1, a, c, b]                      # pre-order, children in order
    visited = Int[]
    @test LK.map_trie_node(tr, 1, (t, id) -> (push!(visited, id); id == c ? id : nothing)) == c
    @test visited == [1, a, c]                         # stopped at the first non-nothing
    @test LK.map_trie_node(tr, b, (t, id) -> id) == b  # a single node

    # is_ground_trie_node: a variable key or an attributed-variable key anywhere on the path
    tr = LK.trie_create(T)
    g1 = LK.insert_child(tr, 1, UInt64(5))
    g2 = LK.insert_child(tr, g1, UInt64(6))
    v1 = LK.insert_child(tr, g1, _trvar(1))
    v2 = LK.insert_child(tr, v1, UInt64(7))
    t1 = LK.insert_child(tr, g1, LK.consTagged(1, LK.TAGEX_TRIE_ATTVAR))
    @test LK.is_ground_trie_node(tr, 1) && LK.is_ground_trie_node(tr, g1) && LK.is_ground_trie_node(tr, g2)
    @test !LK.is_ground_trie_node(tr, v1) && !LK.is_ground_trie_node(tr, v2) && !LK.is_ground_trie_node(tr, t1)
    # a reserved key (an error, a pop) is no variable
    p1 = LK.insert_child(tr, g1, LK.TRIE_KEY_POP(1))
    @test LK.is_ground_trie_node(tr, p1)
    return nothing
end

@testset "trie walk: map_trie_node, is_ground_trie_node" begin
    _tr_walk_rows(_TT)
end

function _tr_stat_rows(::Type{T}) where {T}
    # SIZEOF_TRIE 152, SIZEOF_TRIE_NODE 40, SIZEOF_TRIE_CHILD 16, SIZEOF_TRIE_CHILDREN_BLOCK 32 (checked with a C file at the pin)
    @test (LK.SIZEOF_TRIE, LK.SIZEOF_TRIE_NODE, LK.SIZEOF_TRIE_CHILD, LK.SIZEOF_TRIE_CHILDREN_BLOCK) == (152, 40, 16, 32)
    @test LK.block_size(2, 0) == 32 + 2 * 16 && LK.block_size(8, 0) == 32 + 8 * 16 && LK.block_size(16, 5) == 32 + 16 * 16 + 32 * 4
    @test LK.block_size(32, 6) == 32 + 32 * 16 + 64 * 4
    tr = LK.trie_create(T)
    st = LK.stat_trie(tr)                               # the embedded root: 152 - 40 + 40
    @test (st.bytes, st.nodes, st.hashes, st.values) == (152, 1, 0, 0) && LK.trie_table_size(tr) == 152 + 40
    # 30 children: 31 nodes (the root and 8 individual ones, 22 chunked in one chunk of 1024), a block of 32 entries with a 64-slot index
    tr, ids = _tr_fan(T, 30)
    tr.nodes[ids[3]].value = UInt64(5)
    tr.nodes[ids[3]].flags |= LK.TN_PRIMARY
    tr.nodes[ids[4]].value = UInt64(6)                  # a value without TN_PRIMARY is not counted
    st = LK.stat_trie(tr)
    @test st.nodes == 31 && st.hashes == 1 && st.values == 1
    @test st.bytes == (152 - 40) + 40 * 9 + (32 + 32 * 16 + 64 * 4) + 1024
    @test LK.trie_table_size(tr) == 152 + 31 * 40
    # a block of 2 (not hashed) and a single child are counted as well
    tr = LK.trie_create(T)
    a = LK.insert_child(tr, 1, UInt64(1))
    LK.insert_child(tr, 1, UInt64(2))
    LK.insert_child(tr, a, UInt64(3))
    st = LK.stat_trie(tr)
    @test (st.nodes, st.hashes, st.values) == (4, 0, 0) && st.bytes == 112 + 40 * 4 + (32 + 2 * 16)
    # a TRIE_CONCURRENT trie has no chunks: every node is counted at 40
    tr, ids = _tr_fan(T, 30; flags=LK.TRIE_CONCURRENT)
    st = LK.stat_trie(tr)
    @test st.nodes == 31 && st.bytes == 112 + 40 * 31 + (32 + 32 * 16 + 64 * 4)
    return nothing
end

@testset "trie sizes: stat_trie and trie_table_size, upstream's constants" begin
    _tr_stat_rows(_TT)
end

# ---- THE INDIRECT TABLE ----

function _tr_indirect_rows(::Type{T}) where {T}
    tab = LK.new_indirect_table(T)
    @test isempty(tab.values) && isempty(tab.buckets) && isempty(tab.wild)
    h1 = LK.intern_indirect(tab, lk_gnd(T, 3.5), true)
    @test LK.tagex(h1) == LK.TAGEX_INDIRECT_FLOAT && LK.valTagged(h1) == 1
    @test LK.intern_indirect(tab, lk_gnd(T, 3.5), true) == h1 && length(tab.values) == 1       # one handle for equal values
    @test LK.intern_indirect(tab, lk_gnd(T, 3.5), false) == h1
    h2 = LK.intern_indirect(tab, lk_gnd(T, 4.5), true)
    @test h2 != h1 && LK.valTagged(h2) == 2 && LK.tagex(h2) == LK.TAGEX_INDIRECT_FLOAT
    hs = LK.intern_indirect(tab, lk_gnd(T, "hello"), true)
    @test LK.tagex(hs) == LK.TAGEX_INDIRECT_STRING && LK.valTagged(hs) == 3
    @test LK.intern_indirect(tab, lk_gnd(T, "hello"), true) == hs && LK.intern_indirect(tab, lk_gnd(T, "hellO"), false) == 0
    big = BigInt(2)^100
    hb = LK.intern_indirect(tab, lk_gnd(T, big), true)
    @test LK.tagex(hb) == LK.TAGEX_INDIRECT_INT && LK.valTagged(hb) == 4
    @test LK.intern_indirect(tab, lk_gnd(T, big + 0), true) == hb && length(tab.values) == 4
    # an integer and a float of one value are two values (SWI's identity: `1 = 1.0` fails)
    hi = LK.intern_indirect(tab, lk_gnd(T, Int64(1)), true)
    hf = LK.intern_indirect(tab, lk_gnd(T, 1.0), true)
    @test hi != hf && LK.tagex(hi) == LK.TAGEX_INDIRECT_INT && LK.tagex(hf) == LK.TAGEX_INDIRECT_FLOAT && length(tab.values) == 6
    @test LK.intern_indirect(tab, lk_gnd(T, 1.0), false) == hf && LK.intern_indirect(tab, lk_gnd(T, Int64(1)), false) == hi
    # -0.0 and 0.0 are two floats
    z1 = LK.intern_indirect(tab, lk_gnd(T, 0.0), true)
    z2 = LK.intern_indirect(tab, lk_gnd(T, -0.0), true)
    @test z1 != z2 && LK.valTagged(z1) == 7 && LK.valTagged(z2) == 8
    # not there, and not created: 0, nothing added
    n0 = length(tab.values)
    @test LK.intern_indirect(tab, lk_gnd(T, 9.25), false) == 0 && length(tab.values) == n0
    # extern_indirect gives the value back
    @test lk_eq(LK.extern_indirect(tab, h1), lk_gnd(T, 3.5)) && lk_eq(LK.extern_indirect(tab, hs), lk_gnd(T, "hello")) && lk_eq(LK.extern_indirect(tab, hb), lk_gnd(T, big))

    # the trie's table: absent until the first add; `add` false on a trie without a table is 0 and makes none
    tr = LK.trie_create(T)
    @test LK.trie_intern_indirect(tr, lk_gnd(T, 2.5), false) == 0 && tr.indirects === nothing
    w = LK.trie_intern_indirect(tr, lk_gnd(T, 2.5), true)
    @test tr.indirects !== nothing && LK.valTagged(w) == 1 && LK.tagex(w) == LK.TAGEX_INDIRECT_FLOAT
    @test LK.trie_intern_indirect(tr, lk_gnd(T, 2.5), false) == w && LK.trie_intern_indirect(tr, lk_gnd(T, 2.75), false) == 0
    LK.destroy_indirect_table(tr)
    @test tr.indirects === nothing
    return nothing
end

@testset "indirect table: handles, tags, equal values, the trie's table" begin
    _tr_indirect_rows(_TT)
end

function _tr_wildcard_rows(::Type{T}) where {T}
    # a value without a grounded key (`gnd_key` is nothing) lands in `wild` and is found again by value; keyed values are untouched by it
    v1 = lk_gnd(T, Int64[1, 2])
    @test gnd_key(v1) === nothing
    tab = LK.new_indirect_table(T)
    h = LK.intern_indirect(tab, v1, true)
    @test LK.valTagged(h) == 1 && LK.tagex(h) == LK.TAGEX_INDIRECT_INT && tab.wild == [1] && isempty(tab.buckets)
    @test LK.intern_indirect(tab, lk_gnd(T, Int64[1, 2]), true) == h && length(tab.values) == 1       # an equal copy: the same handle
    @test LK.intern_indirect(tab, lk_gnd(T, Int64[1, 2]), false) == h
    @test LK.intern_indirect(tab, lk_gnd(T, Int64[3]), false) == 0 && length(tab.values) == 1
    h2 = LK.intern_indirect(tab, lk_gnd(T, Int64[3]), true)
    @test LK.valTagged(h2) == 2 && tab.wild == [1, 2]
    # a keyed value next to wildcards: in a bucket, and a wildcard does not match it
    hk = LK.intern_indirect(tab, lk_gnd(T, 2.5), true)
    @test LK.valTagged(hk) == 3 && tab.wild == [1, 2] && length(tab.buckets) == 1
    @test LK.intern_indirect(tab, lk_gnd(T, 2.5), true) == hk && LK.intern_indirect(tab, lk_gnd(T, Int64[1, 2]), true) == h
    @test lk_eq(LK.extern_indirect(tab, h2), lk_gnd(T, Int64[3]))
    return nothing
end

@testset "indirect table: a value without a grounded key is a wildcard" begin
    _tr_wildcard_rows(_TW)
end
