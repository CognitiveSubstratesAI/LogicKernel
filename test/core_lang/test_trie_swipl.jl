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
    ids = Int[LK.insert_child(tr, 1, _tk(k)) for k in 1:n]
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
_trx(::Type{T}, name::Symbol, args::T...) where {T} =
    mk_expr(T, T[lk_sym(T, name), args...])
"The variable `n` (a caller's)."
_trv(::Type{T}, n::Int) where {T} = lk_var(T, UInt64(n))
"An opaque child key for the number `k`: an atom-tagged word (tagex TAG_ATOM|STG_STATIC), never a variable, attributed-variable or reserved key
(`update_var_mask` / `is_ground_trie_node` read `tagex(key) = key & 0x1f`: a plain small integer such as 32 or 33 would be TAGEX_VAR / TAGEX_TRIE_ATTVAR)."
_tk(k::Integer)::UInt64 = LK.consTagged(k, LK.TAG_ATOM | LK.STG_STATIC)
"The numbered trie variable key `n`."
_trvar(n::Int) = LK.consTagged(n, LK.TAGEX_VAR)

"The formal of the pending exception as `(name of its functor, name of its first argument)`, or `nothing` without one."
function _tr_formal(ld)
    ld.exception_term == 0 && return nothing
    ball = lk_answer(ld, ld.exception_term)                 # error(Formal, Context)
    formal = child(ball, 2)
    return (lk_name(child(formal, 1)), lk_name(child(formal, 2)))
end

# ---- LIFE ----

function _tr_life_rows(::Type{T}) where {T}
    gd = LK.PL_global_data{T}()                 # the database trie_discard_clause takes (TR4)
    tr = LK.trie_create(T)
    @test tr.magic == LK.TRIE_MAGIC
    @test tr.node_count == 1 && length(tr.nodes) == 1 && tr.value_count == 0
    @test tr.flags == 0 && tr.symbol == 0 && tr.serial == 0 && tr.references == 0
    @test tr.chunks === nothing && tr.indirects === nothing && isempty(tr.blocks) &&
        tr.clause == 0
    @test tr.nodes[1].parent == 0 && tr.nodes[1].children == 0 && tr.nodes[1].key == 0 &&
        tr.nodes[1].value == 0

    # a referenced trie is not emptied (pl-trie.c empty_trie: `references == 0`), and trie_empty_take does not call the taker
    LK.insert_child(tr, 1, _tk(5))
    LK.insert_child(tr, 1, _tk(6))
    tr.references = 1
    @test !LK.empty_trie(gd, tr, nothing)
    LK.trie_empty(gd, tr)
    @test !LK.trie_empty_take(gd, tr, v -> error("no value is taken from a trie in use"))
    @test tr.node_count == 3 && length(tr.nodes) == 3
    # an unreferenced one hands every value to the taker, and the arenas are reset
    tr.references = 0
    tr.nodes[3].value = UInt64(9)
    tr.nodes[3].flags |= LK.TN_PRIMARY
    tr.value_count = 1
    taken = UInt64[]
    @test LK.trie_empty_take(gd, tr, v -> push!(taken, v))
    @test taken == [UInt64(9)]
    @test tr.node_count == 1 && length(tr.nodes) == 1 && tr.value_count == 0
    @test isempty(tr.blocks) && isempty(tr.free_ids) && isempty(tr.free_blocks) &&
        tr.nodes[1].children == 0
    # empty_trie clears the discard flags
    tr.flags = LK.TRIE_DISCARDABLE | LK.TRIE_ISSET
    @test LK.empty_trie(gd, tr, nothing)
    @test tr.flags == LK.TRIE_ISSET

    # trie_destroy: marks, empties
    tr2, _ = _tr_fan(T, 3)
    LK.trie_destroy(gd, tr2)
    @test tr2.magic == LK.TRIE_CMAGIC && tr2.node_count == 1 && length(tr2.nodes) == 1
    # a destroyed trie still in use keeps its nodes until it is cleaned up
    tr3, _ = _tr_fan(T, 2)
    tr3.references = 1
    LK.trie_destroy(gd, tr3)
    @test tr3.magic == LK.TRIE_CMAGIC && tr3.node_count == 3
    LK.trie_clean(gd, tr3)
    @test tr3.node_count == 3
    tr3.references = 0
    LK.trie_clean(gd, tr3)
    @test tr3.node_count == 1
    # trie_clean leaves a live trie alone
    tr4, _ = _tr_fan(T, 2)
    LK.trie_clean(gd, tr4)
    @test tr4.magic == LK.TRIE_MAGIC && tr4.node_count == 3
    # trie_discard_clause: no clause, nothing to do; a clause word without a kept reference (as `fail`) is cleared, no retract
    @test LK.trie_discard_clause(gd, tr4) === nothing && tr4.clause == 0
    tr4.clause = UInt64(1)
    @test LK.trie_discard_clause(gd, tr4) === nothing && tr4.clause == 0 &&
        tr4.clause_cref === nothing
    # trie_ensure_nodes: true unless discarded, whose restore is refused by name
    @test LK.trie_ensure_nodes(tr4)
    tr4.flags = LK.TRIE_DISCARDED
    @test_throws LK.TrieRefusal LK.trie_ensure_nodes(tr4)
    # a node of a variant trie reaches tbl_release_node (TB1: release_variant_table_node): no value, nothing to release; a value that
    # is no trie pointer (a symbol: the shared tables) is refused by name (owner TH1)
    tr5, ids = _tr_fan(T, 1)
    tr5.flags = LK.TRIE_ISVARIANT
    @test LK.release_node(tr5, ids[1]) === nothing
    tr5.nodes[ids[1]].value = UInt64(4)
    err = try
        LK.release_node(tr5, ids[1])
        nothing
    catch e
        e
    end
    @test err isa LK.NotPortedError && err.step == "TH1"
    tr5.nodes[ids[1]].value = UInt64(0)
    # an answer trie (TRIE_ISTABLE): a node with TN_DELAYINFO is refused by name (owner TB4)
    tr5.flags = LK.TRIE_ISTABLE
    LK.release_node(tr5, ids[1])                       # TN_DELAYINFO not set: nothing to release
    tr5.nodes[ids[1]].flags |= LK.TN_DELAYINFO
    err = try
        LK.release_node(tr5, ids[1])
        nothing
    catch e
        e
    end
    @test err isa LK.NotPortedError && err.step == "TB4"
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
    @test LK.get_child(tr, 1, _tk(10)) == 0 && _tr_keys(tr, 1) == UInt64[]

    # the first child is a single child: children == (id << 1) | 1
    c1 = LK.insert_child(tr, 1, _tk(10))
    @test c1 == 2 && tr.nodes[c1].parent == 1 && tr.nodes[c1].key == _tk(10)
    @test root.children == 5 && root.children == LK.single_child_code(c1)
    @test LK.is_single_child(root.children) && LK.single_child(root.children) == c1
    @test isempty(tr.blocks)
    @test LK.get_child(tr, 1, _tk(10)) == c1 && LK.get_child(tr, 1, _tk(11)) == 0
    @test !LK.is_leaf_trie_node(tr, 1) && _tr_keys(tr, 1) == [_tk(10)]

    # the second makes a block of capacity 2
    c2 = LK.insert_child(tr, 1, _tk(11))
    @test c2 == 3 && !LK.is_single_child(root.children) && root.children == 2 &&
        root.children == LK.block_code(1)
    b = tr.blocks[1]
    @test b.count == 2 && b.capacity == 2 && b.dead == 0 && b.index_bits == 0 &&
        isempty(b.index)
    @test b.entries == [LK.trie_child(_tk(10), c1), LK.trie_child(_tk(11), c2)]
    @test b.var_mask == 0 && b.attvar_mask == 0
    @test LK.block_find(b, _tk(11)) == 2 && LK.block_find(b, _tk(10)) == 1 &&
        LK.block_find(b, _tk(12)) == 0

    # the third doubles it: the new block is made before the old one is freed, so the old slot is free afterwards
    c3 = LK.insert_child(tr, 1, _tk(12))
    @test root.children == LK.block_code(2) && tr.blocks[1] === nothing &&
        tr.free_blocks == [1]
    b = tr.blocks[2]
    @test b.count == 3 && b.capacity == 4 && b.index_bits == 0
    @test b.entries[1:3] == [
        LK.trie_child(_tk(10), c1), LK.trie_child(_tk(11), c2), LK.trie_child(_tk(12), c3)
    ]
    LK.insert_child(tr, 1, _tk(13))                 # fills it
    @test root.children == LK.block_code(2) && tr.blocks[2].count == 4
    # the fifth: capacity 8, and it reuses the freed slot 1
    LK.insert_child(tr, 1, _tk(14))
    @test root.children == LK.block_code(1) && tr.blocks[2] === nothing &&
        tr.free_blocks == [2]
    @test tr.blocks[1].capacity == 8 && tr.blocks[1].count == 5 &&
        tr.blocks[1].index_bits == 0
    for k in 15:17
        LK.insert_child(tr, 1, _tk(k))
    end
    @test tr.blocks[1].count == 8 && tr.blocks[1].capacity == 8 &&
        root.children == LK.block_code(1)
    # the ninth: capacity 16 > TRIE_LINEAR_MAX, so an index of 1 << (MSB(16) + 1) = 32 slots
    LK.insert_child(tr, 1, _tk(18))
    b = _tr_block(tr, 1)
    @test b.capacity == 16 && b.count == 9 && b.index_bits == 5 && length(b.index) == 32
    @test count(!=(0), b.index) == 9 && sort(Int.(filter(!=(0), b.index))) == collect(1:9)
    @test LK.TRIE_LINEAR_MAX == 8
    # up to 17 children: capacity 32, 64 index slots
    for k in 19:26
        LK.insert_child(tr, 1, _tk(k))
    end
    b = _tr_block(tr, 1)
    @test b.capacity == 32 && b.count == 17 && b.index_bits == 6 && length(b.index) == 64
    @test _tr_keys(tr, 1) == _tk.(10:26)
    ids = Dict(k => LK.get_child(tr, 1, _tk(k)) for k in 10:26)
    @test all(
        k -> ids[k] != 0 && tr.nodes[ids[k]].key == _tk(k) && tr.nodes[ids[k]].parent == 1,
        10:26
    )
    @test LK.get_child(tr, 1, _tk(9)) == 0 && LK.get_child(tr, 1, _tk(27)) == 0

    # a colliding hash: two keys of one slot are both found (open addressing, linear probing)
    h = LK.child_hash(_tk(10), 6)
    n2 = 1000
    while LK.child_hash(_tk(n2), 6) != h || n2 in 10:26
        n2 += 1
    end
    k2 = _tk(n2)
    c27 = LK.insert_child(tr, 1, k2)
    b = _tr_block(tr, 1)
    @test b.count == 18 && LK.get_child(tr, 1, k2) == c27 &&
        LK.get_child(tr, 1, _tk(10)) == ids[10]
    @test LK.block_find(b, k2) == 18 && LK.block_find(b, _tk(10)) == 1
    @test all(0 .<= [LK.child_hash(_tk(k), 6) for k in (1, 10, 77, 12345)] .< 64)

    # a probe that runs off the end of the index wraps to slot 0: keys 36 and 73 both start at slot 31 of a 32-slot index, so the second is
    # stored at slot 0 (index_entry) and a lookup that does not wrap reads past the index (block_find)
    trw = LK.trie_create(T)
    @test LK.child_hash(_tk(36), 5) == 31 && LK.child_hash(_tk(73), 5) == 31
    idw = [LK.insert_child(trw, 1, _tk(k)) for k in (36, 73, 1, 2, 3, 4, 5, 6, 7)]
    bw = _tr_block(trw, 1)
    @test bw.index_bits == 5 && bw.count == 9 && bw.index[32] == 1 && bw.index[1] == 2
    @test LK.get_child(trw, 1, _tk(73)) == idw[2] && LK.get_child(trw, 1, _tk(36)) == idw[1]

    # a dead entry: the key stays in the block, the child is 0, the others are intact
    @test !LK.delete_child(tr, 1, ids[15], false)
    b = _tr_block(tr, 1)
    @test b.dead == 1 && b.count == 18 && LK.block_find(b, _tk(15)) > 0
    @test LK.get_child(tr, 1, _tk(15)) == 0 && LK.get_child(tr, 1, _tk(16)) == ids[16]
    @test !(_tk(15) in _tr_keys(tr, 1)) && length(_tr_keys(tr, 1)) == 17
    @test !LK.is_leaf_trie_node(tr, 1)
    LK.destroy_node(tr, ids[15])
    @test tr.free_ids == [ids[15]]
    # ... which is revived by the same key: no new entry, `dead` back to 0, and the freed node id is reused
    n15 = LK.insert_child(tr, 1, _tk(15))
    b = _tr_block(tr, 1)
    @test n15 == ids[15] && b.dead == 0 && b.count == 18 &&
        LK.get_child(tr, 1, _tk(15)) == n15
    @test b.entries[LK.block_find(b, _tk(15))] == LK.trie_child(_tk(15), n15) &&
        tr.nodes[n15].parent == 1
    @test isempty(tr.free_ids)

    # a single child deleted: no children, the node is a leaf, delete_child says it is empty
    tr1, i1 = _tr_fan(T, 1)
    @test LK.delete_child(tr1, 1, i1[1], true) && tr1.nodes[1].children == 0 &&
        LK.is_leaf_trie_node(tr1, 1)
    # a delete of a node that is not the single child changes nothing and says it is not empty
    tr1, i1 = _tr_fan(T, 1)
    other = LK.new_trie_node(tr1, _tk(99))
    @test !LK.delete_child(tr1, 1, other, true) &&
        tr1.nodes[1].children == LK.single_child_code(i1[1])
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
    @test tr.nodes[1].children == LK.single_child_code(ids[4]) &&
        tr.blocks[bid] === nothing && tr.free_blocks == [1, 2]
    @test LK.get_child(tr, 1, _tk(4)) == ids[4] && LK.get_child(tr, 1, _tk(1)) == 0

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
    @test _tr_keys(tr, 1) == _tk.(6:8) && tr.blocks[bid] === nothing
    @test [LK.get_child(tr, 1, _tk(k)) for k in 6:8] == ids[6:8]

    # 16 children, 9 deleted: 9*2 > 16 gives 7 live in a block of capacity 8 (the next power of two >= live)
    tr, ids = _tr_fan(T, 16)
    for i in 1:8
        LK.delete_child(tr, 1, ids[i], true)
    end
    @test tr.blocks[LK.children_block_id(tr.nodes[1].children)].capacity == 16
    LK.delete_child(tr, 1, ids[9], true)
    b = _tr_block(tr, 1)
    @test b.capacity == 8 && b.count == 7 && b.dead == 0 && b.index_bits == 0 &&
        _tr_keys(tr, 1) == _tk.(10:16)

    # 5 children, 3 deleted: 3*2 > 5 gives 2 live in a block of capacity 2 (the capacity loop starts at 2)
    tr, ids = _tr_fan(T, 5)
    LK.delete_child(tr, 1, ids[1], true)
    LK.delete_child(tr, 1, ids[2], true)
    @test tr.blocks[LK.children_block_id(tr.nodes[1].children)].capacity == 8
    LK.delete_child(tr, 1, ids[3], true)
    b = _tr_block(tr, 1)
    @test b.capacity == 2 && b.count == 2 && b.dead == 0 && _tr_keys(tr, 1) == _tk.(4:5)

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
    @test tr.nodes[1].children != 0 && LK.is_leaf_trie_node(tr, 1) &&
        _tr_keys(tr, 1) == UInt64[]
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
    @test b.var_mask == (UInt32(1) << 2) | (UInt32(1) << 30) | LK.VMASK_SCAN &&
        LK.VMASK_SCAN == UInt32(1) << 31
    LK.insert_child(tr, 1, LK.consTagged(2, LK.TAGEX_TRIE_ATTVAR))
    LK.insert_child(tr, 1, _tk(77))                 # a plain key (grows the block to 8, copying the masks)
    b = _tr_block(tr, 1)
    @test b.capacity == 8 &&
        b.var_mask == (UInt32(1) << 2) | (UInt32(1) << 30) | LK.VMASK_SCAN
    @test b.attvar_mask == UInt32(1) << 1
    @test LK.VMASKBITS == 32
    # 8 children [V3, V31, p1..p6]: delete V31 and 4 plain ones: the new block is built by block_append, so V31's bit is gone
    tr = LK.trie_create(T)
    ids = Int[LK.insert_child(tr, 1, k) for k in (_trvar(3), _trvar(31), _tk.(101:106)...)]
    for i in 2:6
        LK.delete_child(tr, 1, ids[i], true)
    end
    b = _tr_block(tr, 1)
    @test b.count == 3 && b.var_mask == UInt32(1) << 2 &&
        _tr_keys(tr, 1) == [_trvar(3), _tk(105), _tk(106)]
    @test ids[1] == LK.get_child(tr, 1, _trvar(3))
    return nothing
end

@testset "trie children: compaction threshold, replace_block, variable masks" begin
    _tr_compaction_rows(_TT)
end

# ---- ALLOCATION ----

function _tr_concurrent_rows(::Type{T}) where {T}
    gd = LK.PL_global_data{T}()                 # the database trie_destroy takes (TR4)
    # TRIE_CONCURRENT: every node individual (no chunks), a replaced block lingers
    tr = LK.trie_create(T)
    tr.flags = LK.TRIE_CONCURRENT
    for k in 1:40
        LK.new_trie_node(tr, _tk(k))
    end
    @test tr.chunks === nothing && tr.node_count == 41 && length(tr.nodes) == 41
    @test all(n -> n.chunk === nothing && (n.flags & LK.TN_CHUNKED) == 0, tr.nodes)
    LK.free_trie_node(tr, 7)
    @test tr.free_ids == [7]
    nid = LK.new_trie_node(tr, _tk(500))
    @test nid == 7 && isempty(tr.free_ids) && tr.nodes[7].key == _tk(500) &&
        tr.nodes[7].parent == 0 && tr.node_count == 42
    @test LK.alloc_trie_node(tr) == (0, nothing, false)

    tr, ids = _tr_fan(T, 2; flags=LK.TRIE_CONCURRENT)
    @test tr.lingering == [] && tr.free_blocks == []
    LK.insert_child(tr, 1, _tk(3))                  # the block of 2 is replaced by one of 4: it lingers
    @test tr.lingering == [1] && tr.blocks[1] !== nothing && tr.free_blocks == [] &&
        LK.children_block_id(tr.nodes[1].children) == 2
    LK.free_lingering_blocks(tr)
    @test isempty(tr.lingering) && tr.blocks[1] === nothing && tr.free_blocks == [1]
    # compaction retires the block the same way
    for k in 4:8
        LK.insert_child(tr, 1, _tk(k))
    end
    @test LK.children_block_id(tr.nodes[1].children) == 1 && tr.lingering == [2]       # 4 -> 8 took the freed slot 1
    # trie_destroy frees the lingering blocks too
    LK.trie_destroy(gd, tr)
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
        push!(ids, LK.new_trie_node(tr, _tk(k)))
    end
    # the first TRIE_SINGLE_NODES (8) nodes are individual
    @test tr.chunks === nothing && tr.node_count == 9 && ids == collect(2:9) &&
        LK.TRIE_SINGLE_NODES == 8
    @test all(n -> n.chunk === nothing && (n.flags & LK.TN_CHUNKED) == 0, tr.nodes)
    # the ninth starts the first chunk: 1024 bytes, (1024 - 72) / 40 = 23 nodes
    n9 = LK.new_trie_node(tr, _tk(9))
    c = tr.chunks
    @test c !== nothing && c.bytes == 1024 && c.size == 23 && c.used == 1 && c.live == 1 &&
        c.next === nothing
    @test c.free == 0 && c.nfree == 0 && c.sweep_at == 1024 && c.flags == 0
    @test (tr.nodes[n9].flags & LK.TN_CHUNKED) != 0 && tr.nodes[n9].chunk === c &&
        (tr.nodes[n9].flags >> LK.TN_CHUNK_INDEX_SHIFT) == 0
    @test LK.OFFSETOF_TRIE_NODE_CHUNK_NODES == 72 && LK.SIZEOF_TRIE_NODE == 40 &&
        LK.TRIE_CHUNK_MIN == 1024 && LK.TRIE_CHUNK_MAX == 16384
    n10 = LK.new_trie_node(tr, _tk(10))
    @test (tr.nodes[n10].flags >> LK.TN_CHUNK_INDEX_SHIFT) == 1 && c.used == 2 &&
        c.live == 2
    first_chunk_ids = [n9, n10]
    for k in 11:31                                     # the chunk is full at 23 nodes
        push!(first_chunk_ids, LK.new_trie_node(tr, _tk(k)))
    end
    @test length(first_chunk_ids) == 23 && tr.chunks === c && c.used == 23 && c.live == 23
    # the 24th starts the second: 2048 bytes, 49 nodes, the first chunk behind it, the sweep threshold inherited
    LK.new_trie_node(tr, _tk(32))
    c2 = tr.chunks
    @test c2 !== c && c2.bytes == 2048 && c2.size == 49 && c2.next === c && c2.used == 1 &&
        c2.live == 1 && c2.sweep_at == 1024
    @test c.live == 23
    # the node count it gives up to the sixth chunk: 23 + 49 + 100 + 203 + 407 + 1 chunked nodes
    for k in 33:791
        LK.new_trie_node(tr, _tk(k))
    end
    cs = _tr_chunks(tr)
    @test [Int(c.bytes) for c in cs] == [16384, 16384, 8192, 4096, 2048, 1024]
    @test [Int(c.size) for c in cs] == [407, 407, 203, 100, 49, 23]
    @test [Int(c.used) for c in cs] == [1, 407, 203, 100, 49, 23] &&
        [Int(c.live) for c in cs] == [1, 407, 203, 100, 49, 23]
    @test tr.node_count == 1 + 8 + 23 + 49 + 100 + 203 + 407 + 1

    # a freed chunk node: key 0, its chunk's live count down, pushed on the HEAD chunk's free list (linked through `parent`)
    head = tr.chunks
    f1, f2 = first_chunk_ids[1], first_chunk_ids[2]
    LK.free_trie_node(tr, f1)
    @test tr.nodes[f1].key == 0 && cs[end].live == 22 && head.free == f1 &&
        head.nfree == 1 && tr.nodes[f1].parent == 0
    LK.free_trie_node(tr, f2)
    @test head.free == f2 && head.nfree == 2 && tr.nodes[f2].parent == f1 &&
        cs[end].live == 21 && isempty(tr.free_ids)
    # the next new node takes the newest freed id: its chunk and its index in the chunk stay
    used_before = head.used
    r = LK.new_trie_node(tr, _tk(777))
    @test r == f2 && head.free == f1 && head.nfree == 1 && cs[end].live == 22 &&
        head.used == used_before
    @test tr.nodes[r].key == _tk(777) && tr.nodes[r].chunk === cs[end] &&
        (tr.nodes[r].flags & LK.TN_CHUNKED) != 0 &&
        (tr.nodes[r].flags >> LK.TN_CHUNK_INDEX_SHIFT) == 1
    r2 = LK.new_trie_node(tr, _tk(778))
    @test r2 == f1 && head.free == 0 && head.nfree == 0 && cs[end].live == 23 &&
        (tr.nodes[r2].flags >> LK.TN_CHUNK_INDEX_SHIFT) == 0
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
        nid = LK.insert_child(tr, nid, _tk(k))
    end
    @test tr.node_count == 1501
    cs = _tr_chunks(tr)
    @test [Int(c.size) for c in cs] == [407, 407, 407, 203, 100, 49, 23] &&
        [Int(c.used) for c in cs] == [303, 407, 407, 203, 100, 49, 23]
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

    # no sweep while nfree <= node_count: 3000 leaves under the root (the chunks are 23, 49, 100, 203 and 7 of 407, the newest holds 175),
    # the newest 1024 destroyed: nfree reaches sweep_at (1024) while node_count is 1977, so nothing is swept (a sweep would drop the two
    # chunks that are free from end to end)
    tr, ids = _tr_fan(T, 3000)
    @test [Int(c.size) for c in _tr_chunks(tr)] ==
          [407, 407, 407, 407, 407, 407, 407, 203, 100, 49, 23] &&
        Int(tr.chunks.used) == 175
    for k in 3000:-1:1977
        LK.destroy_node(tr, ids[k])
    end
    @test tr.node_count == 3001 - 1024 && Int(tr.chunks.nfree) == 1024 &&
        Int(tr.chunks.sweep_at) == 1024
    @test length(_tr_chunks(tr)) == 11 && isempty(tr.free_ids)
    return nothing
end

@testset "trie nodes: the sweep drops a chunk with no live node" begin
    _tr_sweep_rows(_TT)
end

# ---- CLEAR AND PRUNE ----

function _tr_prune_rows(::Type{T}) where {T}
    # a chain root - a - b - c: pruning from c takes the whole branch
    tr = LK.trie_create(T)
    a = LK.insert_child(tr, 1, _tk(10))
    b = LK.insert_child(tr, a, _tk(20))
    c = LK.insert_child(tr, b, _tk(30))
    @test _tr_path(tr, c) == _tk.([10, 20, 30]) && tr.node_count == 4
    LK.prune_node(tr, c)
    @test tr.node_count == 1 && tr.nodes[1].children == 0 &&
        sort(tr.free_ids) == [a, b, c] && tr.free_ids == [c, b, a]
    # a flag on b stops it: only c goes
    for fl in (LK.TN_PRIMARY, LK.TN_SECONDARY, LK.TN_PINNED)
        tr = LK.trie_create(T)
        a = LK.insert_child(tr, 1, _tk(10))
        b = LK.insert_child(tr, a, _tk(20))
        c = LK.insert_child(tr, b, _tk(30))
        tr.nodes[b].flags |= fl
        LK.prune_node(tr, c)
        @test tr.node_count == 3 && tr.nodes[b].children == 0 &&
            LK.get_child(tr, a, _tk(20)) == b && LK.get_child(tr, b, _tk(30)) == 0
        @test tr.free_ids == [c]
        # the node itself carrying the flag is not pruned at all
        LK.prune_node(tr, b)
        @test tr.node_count == 3
    end
    # a branch point: pruning c leaves b findable; pruning b afterwards takes a as well
    tr = LK.trie_create(T)
    a = LK.insert_child(tr, 1, _tk(10))
    b = LK.insert_child(tr, a, _tk(20))
    c = LK.insert_child(tr, a, _tk(30))
    LK.prune_node(tr, c)
    @test tr.node_count == 3 && LK.get_child(tr, a, _tk(20)) == b &&
        LK.get_child(tr, a, _tk(30)) == 0 && _tr_keys(tr, a) == [_tk(20)]
    LK.prune_node(tr, b)
    @test tr.node_count == 1 && tr.nodes[1].children == 0
    # the root is never pruned
    LK.prune_node(tr, 1)
    @test tr.node_count == 1
    # prune_error: adds the error key under the node and prunes it, so a node with no flags goes too
    tr = LK.trie_create(T)
    a = LK.insert_child(tr, 1, _tk(10))
    tr.nodes[a].flags |= LK.TN_PRIMARY
    b = LK.insert_child(tr, a, _tk(20))
    LK.prune_error(tr, b)
    # upstream's prune_node (pl-trie.c:1460-1471 on the pin) walks up from the error node while the node has no TN_PRIMARY/TN_SECONDARY/TN_PINNED flag: the error node
    # and `b` both go, `a` (TN_PRIMARY) stays: the root and `a` are left
    @test tr.node_count == 2 && LK.get_child(tr, b, LK.TRIE_ERROR_VAL) == 0 &&
        LK.get_child(tr, a, _tk(20)) == 0
    # (the error key is a reserved key, `is_trie_key_pop` of it is 0)
    @test LK.IS_TRIE_KEY_POP(LK.TRIE_ERROR_VAL) == 0 &&
        LK.IS_TRIE_KEY_POP(LK.TRIE_KEY_ABSENT) == 0 &&
        LK.TRIE_ERROR_VAL != LK.TRIE_KEY_ABSENT
    @test LK.IS_TRIE_KEY_POP(LK.TRIE_KEY_POP(1)) == 1 &&
        LK.IS_TRIE_KEY_POP(LK.TRIE_KEY_POP(7)) == 7 &&
        LK.IS_TRIE_KEY_POP(_trvar(11)) == 0 && LK.IS_TRIE_KEY_POP(_tk(5)) == 0

    # prune_trie: the branches that end in no value go, with the callback on each leaf it meets (root - a - {b, c}, c a value)
    tr = LK.trie_create(T)
    a = LK.insert_child(tr, 1, _tk(10))
    b = LK.insert_child(tr, a, _tk(20))
    c = LK.insert_child(tr, a, _tk(30))
    tr.nodes[c].flags |= LK.TN_PRIMARY
    leaves = Int[]
    LK.prune_trie(tr, 1, id -> push!(leaves, id))
    @test sort(leaves) == [b, c] && tr.node_count == 3
    @test LK.get_child(tr, a, _tk(30)) == c && LK.get_child(tr, a, _tk(20)) == 0 &&
        _tr_keys(tr, a) == [_tk(30)]
    # a trie with no value at all is emptied down to the root
    tr, _ = _tr_fan(T, 5)
    LK.prune_trie(tr, 1)
    @test tr.node_count == 1 && tr.nodes[1].children == 0
    # a deeper one: the root has a chain and a fan; the chain (no value) goes, the value branch stays
    tr = LK.trie_create(T)
    x1 = LK.insert_child(tr, 1, _tk(1))
    x2 = LK.insert_child(tr, x1, _tk(2))
    y1 = LK.insert_child(tr, 1, _tk(3))
    y2 = LK.insert_child(tr, y1, _tk(4))
    y3 = LK.insert_child(tr, y1, _tk(5))
    tr.nodes[y3].flags |= LK.TN_PRIMARY
    LK.prune_trie(tr, 1)
    @test tr.node_count == 3 && _tr_keys(tr, 1) == [_tk(3)] && _tr_keys(tr, y1) == [_tk(5)]
    # a leaf with TN_SECONDARY or TN_PINNED is kept as one with TN_PRIMARY is (root - a - {b, c})
    tr = LK.trie_create(T)
    pa = LK.insert_child(tr, 1, _tk(10))
    pb = LK.insert_child(tr, pa, _tk(20))
    pc = LK.insert_child(tr, pa, _tk(30))
    tr.nodes[pb].flags |= LK.TN_SECONDARY
    tr.nodes[pc].flags |= LK.TN_PINNED
    leaves = Int[]
    LK.prune_trie(tr, 1, id -> push!(leaves, id))
    @test sort(leaves) == [pb, pc] && tr.node_count == 4 &&
        _tr_keys(tr, pa) == [_tk(20), _tk(30)]

    # trie_single_value_node: value_count 1 and a chain of single children down to the value
    tr = LK.trie_create(T)
    a = LK.insert_child(tr, 1, _tk(10))
    b = LK.insert_child(tr, a, _tk(20))
    tr.nodes[b].value = UInt64(5)
    @test LK.trie_single_value_node(tr) == 0           # value_count is 0
    tr.value_count = 1
    @test LK.trie_single_value_node(tr) == b
    tr.value_count = 2
    @test LK.trie_single_value_node(tr) == 0
    tr.value_count = 1
    LK.insert_child(tr, a, _tk(21))                 # a branch before the value
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
    gd = LK.PL_global_data{T}()                 # the database empty_trie takes (TR4)
    tr = LK.trie_create(T)
    for k in 1:40
        LK.insert_child(tr, 1, _tk(k))
    end
    deep = LK.get_child(tr, 1, _tk(5))
    for k in 1:12
        deep = LK.insert_child(tr, deep, _tk(100 + k))
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
    @test LK.empty_trie(gd, tr, v -> push!(vals, v))
    @test sort(vals) == UInt64[7, 9, 11]
    @test tr.node_count == 1 && length(tr.nodes) == 1 && tr.chunks === nothing &&
        tr.indirects === nothing && tr.value_count == 0
    @test isempty(tr.blocks) && isempty(tr.free_ids) && isempty(tr.free_blocks) &&
        tr.nodes[1].children == 0
    # the trie is usable again afterwards
    n = LK.insert_child(tr, 1, _tk(1))
    @test n == 2 && tr.node_count == 2 && LK.get_child(tr, 1, _tk(1)) == 2
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
    a = LK.insert_child(tr, 1, _tk(10))
    b = LK.insert_child(tr, 1, _tk(11))
    c = LK.insert_child(tr, a, _tk(12))
    visited = Int[]
    @test LK.map_trie_node(tr, 1, (t, id) -> (push!(visited, id); nothing)) === nothing
    @test visited == [1, a, c, b]                      # pre-order, children in order
    visited = Int[]
    @test LK.map_trie_node(
        tr, 1, (t, id) -> (push!(visited, id); id == c ? id : nothing)
    ) == c
    @test visited == [1, a, c]                         # stopped at the first non-nothing
    @test LK.map_trie_node(tr, b, (t, id) -> id) == b  # a single node

    # is_ground_trie_node: a variable key or an attributed-variable key anywhere on the path
    tr = LK.trie_create(T)
    g1 = LK.insert_child(tr, 1, _tk(5))
    g2 = LK.insert_child(tr, g1, _tk(6))
    v1 = LK.insert_child(tr, g1, _trvar(1))
    v2 = LK.insert_child(tr, v1, _tk(7))
    t1 = LK.insert_child(tr, g1, LK.consTagged(1, LK.TAGEX_TRIE_ATTVAR))
    @test LK.is_ground_trie_node(tr, 1) && LK.is_ground_trie_node(tr, g1) &&
        LK.is_ground_trie_node(tr, g2)
    @test !LK.is_ground_trie_node(tr, v1) && !LK.is_ground_trie_node(tr, v2) &&
        !LK.is_ground_trie_node(tr, t1)
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
    @test (
        LK.SIZEOF_TRIE,
        LK.SIZEOF_TRIE_NODE,
        LK.SIZEOF_TRIE_CHILD,
        LK.SIZEOF_TRIE_CHILDREN_BLOCK
    ) == (152, 40, 16, 32)
    @test LK.block_size(2, 0) == 32 + 2 * 16 && LK.block_size(8, 0) == 32 + 8 * 16 &&
        LK.block_size(16, 5) == 32 + 16 * 16 + 32 * 4
    @test LK.block_size(32, 6) == 32 + 32 * 16 + 64 * 4
    tr = LK.trie_create(T)
    st = LK.stat_trie(tr)                               # the embedded root: 152 - 40 + 40
    @test (st.bytes, st.nodes, st.hashes, st.values) == (152, 1, 0, 0) &&
        LK.trie_table_size(tr) == 152 + 40
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
    a = LK.insert_child(tr, 1, _tk(1))
    LK.insert_child(tr, 1, _tk(2))
    LK.insert_child(tr, a, _tk(3))
    st = LK.stat_trie(tr)
    @test (st.nodes, st.hashes, st.values) == (4, 0, 0) &&
        st.bytes == 112 + 40 * 4 + (32 + 2 * 16)
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
    @test LK.intern_indirect(tab, lk_gnd(T, "hello"), true) == hs &&
        LK.intern_indirect(tab, lk_gnd(T, "hellO"), false) == 0
    big = BigInt(2)^100
    hb = LK.intern_indirect(tab, lk_gnd(T, big), true)
    @test LK.tagex(hb) == LK.TAGEX_INDIRECT_INT && LK.valTagged(hb) == 4
    @test LK.intern_indirect(tab, lk_gnd(T, big + 0), true) == hb && length(tab.values) == 4
    # an integer and a float of one value are two values (SWI's identity: `1 = 1.0` fails)
    hi = LK.intern_indirect(tab, lk_gnd(T, Int64(1)), true)
    hf = LK.intern_indirect(tab, lk_gnd(T, 1.0), true)
    @test hi != hf && LK.tagex(hi) == LK.TAGEX_INDIRECT_INT &&
        LK.tagex(hf) == LK.TAGEX_INDIRECT_FLOAT && length(tab.values) == 6
    @test LK.intern_indirect(tab, lk_gnd(T, 1.0), false) == hf &&
        LK.intern_indirect(tab, lk_gnd(T, Int64(1)), false) == hi
    # -0.0 and 0.0 are two floats
    z1 = LK.intern_indirect(tab, lk_gnd(T, 0.0), true)
    z2 = LK.intern_indirect(tab, lk_gnd(T, -0.0), true)
    @test z1 != z2 && LK.valTagged(z1) == 7 && LK.valTagged(z2) == 8
    # not there, and not created: 0, nothing added
    n0 = length(tab.values)
    @test LK.intern_indirect(tab, lk_gnd(T, 9.25), false) == 0 && length(tab.values) == n0
    # extern_indirect gives the value back
    @test lk_eq(LK.extern_indirect(tab, h1), lk_gnd(T, 3.5)) &&
        lk_eq(LK.extern_indirect(tab, hs), lk_gnd(T, "hello")) &&
        lk_eq(LK.extern_indirect(tab, hb), lk_gnd(T, big))

    # the trie's table: absent until the first add; `add` false on a trie without a table is 0 and makes none
    tr = LK.trie_create(T)
    @test LK.trie_intern_indirect(tr, lk_gnd(T, 2.5), false) == 0 &&
        tr.indirects === nothing
    w = LK.trie_intern_indirect(tr, lk_gnd(T, 2.5), true)
    @test tr.indirects !== nothing && LK.valTagged(w) == 1 &&
        LK.tagex(w) == LK.TAGEX_INDIRECT_FLOAT
    @test LK.trie_intern_indirect(tr, lk_gnd(T, 2.5), false) == w &&
        LK.trie_intern_indirect(tr, lk_gnd(T, 2.75), false) == 0
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
    @test LK.valTagged(h) == 1 && LK.tagex(h) == LK.TAGEX_INDIRECT_INT && tab.wild == [1] &&
        isempty(tab.buckets)
    @test LK.intern_indirect(tab, lk_gnd(T, Int64[1, 2]), true) == h &&
        length(tab.values) == 1       # an equal copy: the same handle
    @test LK.intern_indirect(tab, lk_gnd(T, Int64[1, 2]), false) == h
    @test LK.intern_indirect(tab, lk_gnd(T, Int64[3]), false) == 0 &&
        length(tab.values) == 1
    h2 = LK.intern_indirect(tab, lk_gnd(T, Int64[3]), true)
    @test LK.valTagged(h2) == 2 && tab.wild == [1, 2]
    # a keyed value next to wildcards: in a bucket, and a wildcard does not match it
    hk = LK.intern_indirect(tab, lk_gnd(T, 2.5), true)
    @test LK.valTagged(hk) == 3 && tab.wild == [1, 2] && length(tab.buckets) == 1
    @test LK.intern_indirect(tab, lk_gnd(T, 2.5), true) == hk &&
        LK.intern_indirect(tab, lk_gnd(T, Int64[1, 2]), true) == h
    @test lk_eq(LK.extern_indirect(tab, h2), lk_gnd(T, Int64[3]))
    return nothing
end

@testset "indirect table: a value without a grounded key is a wildcard" begin
    _tr_wildcard_rows(_TW)
end

# ---- LOOKUP (the engine's cells) ----
# Setup: `_tr_engine(T, vs)` puts `vs[i]` into slot `t + i` (term reference `t + i - 1`), whose location is `-(t + i)`.
# Small integers are TAGGED words (`consInt`, never interned); floats, strings and big integers are indirects (a handle
# `consTagged(index, TAGEX_INDIRECT_*)` of the trie's own table, numbered in the order the lookup meets them).

function _tr_lookup_ground_rows(::Type{T}) where {T}
    s(n) = lk_sym(T, n)
    # f(a, g(b, 1), h(x, i(y))): one key per cell in depth-first order; a POP(n) key where a compound's arguments end and the walk goes on;
    # the ends at the top (h and i and f together) give no key
    term = _trx(
        T,
        :f,
        s(:a),
        _trx(T, :g, s(:b), lk_gnd(T, Int64(1))),
        _trx(T, :h, s(:x), _trx(T, :i, s(:y)))
    )
    term2 = _trx(
        T,
        :f,
        s(:a),
        _trx(T, :g, s(:b), lk_gnd(T, Int64(2))),
        _trx(T, :h, s(:x), _trx(T, :i, s(:y)))
    )
    # slots: the term, the atom a, the integer 7, a term differing in one integer, the term again (a separate copy)
    gd, ld, t = _tr_engine(T, T[term, s(:a), lk_gnd(T, Int64(7)), term2, term])
    loc = -(t + 1)
    tr = LK.trie_create(T)
    @test LK.trie_lookup_abstract(ld, tr, 0, loc, false, nothing, nothing) == (0, 0)     # not there, nothing added
    @test tr.node_count == 1 && tr.lookups == 1
    rc, nid = LK.trie_lookup_abstract(ld, tr, 0, loc, true, nothing, nothing)
    @test rc == 1 && nid != 0 && tr.node_count == 11 && tr.lookups == 2
    expected = UInt64[
        _trf(ld, T, :f, 3), _trw(ld, T, :a), _trf(ld, T, :g, 2), _trw(ld, T, :b),
        LK.consInt(1), LK.TRIE_KEY_POP(1),
        _trf(ld, T, :h, 2), _trw(ld, T, :x), _trf(ld, T, :i, 1), _trw(ld, T, :y)
    ]
    @test _tr_path(tr, nid) == expected
    @test LK.is_ground_trie_node(tr, nid)
    @test LK.trie_lookup_abstract(ld, tr, 0, loc, false, nothing, nothing) == (1, nid) &&
        tr.node_count == 11
    # a differing integer in the middle: no node, nothing added
    @test LK.trie_lookup_abstract(ld, tr, 0, -(t + 4), false, nothing, nothing) == (0, 0) &&
        tr.node_count == 11
    # another copy of the term (other cells) finds the same node
    @test LK.trie_lookup_abstract(ld, tr, 0, -(t + 5), false, nothing, nothing) == (1, nid)
    # an atom and a small integer alone: the key is the cell's word
    ra, na = LK.trie_lookup_abstract(ld, tr, 0, -(t + 2), true, nothing, nothing)
    ri, ni = LK.trie_lookup_abstract(ld, tr, 0, -(t + 3), true, nothing, nothing)
    @test ra == 1 && ri == 1 && tr.nodes[na].key == _trw(ld, T, :a) &&
        tr.nodes[ni].key == LK.consInt(7) && na != ni
    @test tr.nodes[na].parent == 1 && tr.nodes[ni].parent == 1 && tr.node_count == 13
    # the variables vector, given or not: a ground term leaves it empty
    vs = Int[]
    @test LK.trie_lookup_abstract(ld, tr, 0, loc, false, nothing, vs) == (1, nid) &&
        isempty(vs)
    return nothing
end

@testset "trie lookup: a ground term, the keys in order, the POP keys, an atom, an integer" begin
    _tr_lookup_ground_rows(_TT)
end

function _tr_lookup_indirect_rows(::Type{T}) where {T}
    s(n) = lk_sym(T, n)
    big = BigInt(2)^100
    mk(f4, f5) = _trx(T, :p, lk_gnd(T, 2.5), lk_gnd(T, "s"), lk_gnd(T, big), f4, f5)
    # slots: the term, 2.5 alone, the term again; then the term with 1.0 in place of 1, with 1 in place of 1.0, and with an unknown float
    gd, ld, t = _tr_engine(
        T,
        T[
            mk(lk_gnd(T, Int64(1)), lk_gnd(T, 1.0)), lk_gnd(T, 2.5),
            mk(lk_gnd(T, Int64(1)), lk_gnd(T, 1.0)),
            mk(lk_gnd(T, 1.0), lk_gnd(T, 1.0)),
            mk(lk_gnd(T, Int64(1)), lk_gnd(T, Int64(1))),
            mk(lk_gnd(T, Int64(1)), lk_gnd(T, 2.0))
        ]
    )
    tr = LK.trie_create(T)
    rc, nid = LK.trie_lookup_abstract(ld, tr, 0, -(t + 1), true, nothing, nothing)
    # the handles are numbered in the order the lookup meets the values; the small integer 1 is no indirect, the float 1.0 is
    h(i, tx) = LK.consTagged(i, tx)
    @test rc == 1 && tr.node_count == 7
    @test _tr_path(tr, nid) == UInt64[
        _trf(ld, T, :p, 5), h(1, LK.TAGEX_INDIRECT_FLOAT), h(2, LK.TAGEX_INDIRECT_STRING),
        h(3, LK.TAGEX_INDIRECT_INT),
        LK.consInt(1), h(4, LK.TAGEX_INDIRECT_FLOAT)
    ]
    @test tr.indirects !== nothing && length(tr.indirects.values) == 4
    @test lk_eq(
        LK.extern_indirect(tr.indirects, h(3, LK.TAGEX_INDIRECT_INT)), lk_gnd(T, big)
    )
    # an indirect alone, and its handle is the one already made
    r2, n2 = LK.trie_lookup_abstract(ld, tr, 0, -(t + 2), true, nothing, nothing)
    @test r2 == 1 && tr.nodes[n2].key == h(1, LK.TAGEX_INDIRECT_FLOAT) &&
        length(tr.indirects.values) == 4
    # another copy of the values: found by value (the handles belong to the trie)
    @test LK.trie_lookup_abstract(ld, tr, 0, -(t + 3), false, nothing, nothing) == (1, nid)
    # 1 is not 1.0 (SWI's identity): the integer in the place of the float, the float in the place of the integer
    nodes = tr.node_count
    @test LK.trie_lookup_abstract(ld, tr, 0, -(t + 4), false, nothing, nothing) == (0, 0)
    @test LK.trie_lookup_abstract(ld, tr, 0, -(t + 5), false, nothing, nothing) == (0, 0)
    @test LK.trie_lookup_abstract(ld, tr, 0, -(t + 6), false, nothing, nothing) == (0, 0)      # a float no table holds: no handle, no node
    @test tr.node_count == nodes && length(tr.indirects.values) == 4                              # a lookup without `add` interns nothing
    return nothing
end

@testset "trie lookup: indirect values by handle, 1 is not 1.0" begin
    _tr_lookup_indirect_rows(_TT)
end

function _tr_lookup_variant_rows(::Type{T}) where {T}
    s(n) = lk_sym(T, n)
    X, Y = _trv(T, 1), _trv(T, 2)
    P, Q = _trv(T, 7), _trv(T, 8)
    # slots 1-2: f(X,X,Y), g(X,h(X)); slots 3-7: f(P,P,Q) (a variant), f(P,Q,Q), f(P,Q,P), f(P,P,P), f(P,P,a); each put has its own variables
    gd, ld, t = _tr_engine(
        T,
        T[
            _trx(T, :f, X, X, Y), _trx(T, :g, X, _trx(T, :h, X)), _trx(T, :f, P, P, Q),
            _trx(T, :f, P, Q, Q), _trx(T, :f, P, Q, P),
            _trx(T, :f, P, P, P), _trx(T, :f, P, P, s(:a))
        ]
    )
    tr = LK.trie_create(T)
    vars = Int[]
    rc, n1 = LK.trie_lookup_abstract(ld, tr, 0, -(t + 1), true, nothing, vars)
    @test rc == 1 &&
        _tr_path(tr, n1) == UInt64[_trf(ld, T, :f, 3), _trvar(1), _trvar(1), _trvar(2)]
    @test !LK.is_ground_trie_node(tr, n1)
    # the variables are numbered by their first occurrence, handed back as their cells, and the cells are restored (unbound)
    @test length(vars) == 2 && vars[1] != vars[2] &&
        all(p -> p > 0 && ld.gstack[p] == 0, vars)
    # g(X, h(X)): the second X is the same variable; the ends of h and of g come together: no POP key
    r2, n2 = LK.trie_lookup_abstract(ld, tr, 0, -(t + 2), true, nothing, nothing)
    @test r2 == 1 &&
        _tr_path(tr, n2) ==
          UInt64[_trf(ld, T, :g, 2), _trvar(1), _trf(ld, T, :h, 1), _trvar(1)]
    # a variant (other variables, other engine) is found; a non-variant is not, and adds nothing
    nodes = tr.node_count
    @test LK.trie_lookup_abstract(ld, tr, 0, -(t + 3), false, nothing, nothing) == (1, n1)
    for i in 4:7
        @test LK.trie_lookup_abstract(ld, tr, 0, -(t + i), false, nothing, nothing) ==
            (0, 0)
    end
    @test tr.node_count == nodes
    # with `add` the other shapes are made: f(P,Q,Q) is [V1, V2, V2]
    r6, n6 = LK.trie_lookup_abstract(ld, tr, 0, -(t + 4), true, nothing, nothing)
    @test r6 == 1 && n6 != n1 &&
        _tr_path(tr, n6) == UInt64[_trf(ld, T, :f, 3), _trvar(1), _trvar(2), _trvar(2)]
    # a bare variable is the key V1 and its cell is restored
    gd3, ld3, t3 = _tr_engine(T, T[X])
    tr3 = LK.trie_create(T)
    vs3 = Int[]
    r7, n7 = LK.trie_lookup_abstract(ld3, tr3, 0, -(t3 + 1), true, nothing, vs3)
    @test r7 == 1 && _tr_path(tr3, n7) == UInt64[_trvar(1)] && length(vs3) == 1 &&
        ld3.gstack[vs3[1]] == 0
    return nothing
end

@testset "trie lookup: variants, the numbering of the variables, the cells restored" begin
    _tr_lookup_variant_rows(_TT)
end

function _tr_lookup_abstract_rows(::Type{T}) where {T}
    s(n) = lk_sym(T, n)
    gd, ld, t = _tr_engine(
        T,
        T[
            _trx(T, :f, _trx(T, :g, s(:a))),
            s(:a),
            _trx(T, :f, s(:a)),
            _trx(T, :f, _trx(T, :g, _trx(T, :h, s(:a)))),
            _trx(T, :f, _trx(T, :g, s(:a)), s(:b))
        ]
    )
    # size_abstract(from_depth, size): the compounds below depth `from_depth` are limited to `size`; the rest becomes a variable and rc is TRIE_ABSTRACTED
    tr = LK.trie_create(T)
    vars = Int[]
    rc, nid = LK.trie_lookup_abstract(
        ld, tr, 0, -(t + 1), true, LK.size_abstract(1, 0), vars
    )
    @test rc == LK.TRIE_ABSTRACTED && LK.TRIE_ABSTRACTED == 2 && nid != 0
    @test _tr_path(tr, nid) == UInt64[_trf(ld, T, :f, 1), _trvar(1)]
    @test length(vars) == 1 && LK._is_gcompound(ld.gstack[vars[1]])          # the compound g(a) itself stays: only a variable cell is overwritten
    # from depth 0 the term itself is abstracted: the key is just V1, the variable "cell" is the slot's location
    tr = LK.trie_create(T)
    vars = Int[]
    rc, nid = LK.trie_lookup_abstract(
        ld, tr, 0, -(t + 3), true, LK.size_abstract(0, 0), vars
    )
    @test rc == LK.TRIE_ABSTRACTED && _tr_path(tr, nid) == UInt64[_trvar(1)] &&
        vars == [-(t + 3)]
    # an atom is no compound: abstraction leaves it, rc 1
    tr = LK.trie_create(T)
    rc, nid = LK.trie_lookup_abstract(
        ld, tr, 0, -(t + 2), true, LK.size_abstract(0, 0), nothing
    )
    @test rc == 1 && _tr_path(tr, nid) == UInt64[_trw(ld, T, :a)]
    # size 1 below depth 1: g is kept, h(a) below it goes (the ends of g and of f come together: no POP key)
    tr = LK.trie_create(T)
    rc, nid = LK.trie_lookup_abstract(
        ld, tr, 0, -(t + 4), true, LK.size_abstract(1, 1), nothing
    )
    @test rc == LK.TRIE_ABSTRACTED &&
        _tr_path(tr, nid) == UInt64[_trf(ld, T, :f, 1), _trf(ld, T, :g, 1), _trvar(1)]
    # atomic arguments are not limited: f(g(a), b) at (1, 0) is [f/2, V1, b]
    tr = LK.trie_create(T)
    rc, nid = LK.trie_lookup_abstract(
        ld, tr, 0, -(t + 5), true, LK.size_abstract(1, 0), nothing
    )
    @test rc == LK.TRIE_ABSTRACTED &&
        _tr_path(tr, nid) == UInt64[_trf(ld, T, :f, 2), _trvar(1), _trw(ld, T, :b)]
    # a term within the limit is not abstracted, and with no abstraction nothing is
    tr = LK.trie_create(T)
    rc, nid = LK.trie_lookup_abstract(
        ld, tr, 0, -(t + 1), true, LK.size_abstract(1, 1), nothing
    )
    @test rc == 1 &&
        _tr_path(tr, nid) ==
          UInt64[_trf(ld, T, :f, 1), _trf(ld, T, :g, 1), _trw(ld, T, :a)]
    return nothing
end

@testset "trie lookup: size_abstract, TRIE_ABSTRACTED" begin
    _tr_lookup_abstract_rows(_TT)
end

function _tr_lookup_cyclic_rows(::Type{T}) where {T}
    s(n) = lk_sym(T, n)
    X = _trv(T, 1)
    # X = f(X): a cyclic term (needs one variable map for the two puts, and the unification that closes the cycle)
    gd, ld, t = _tr_engine(T, T[X, _trx(T, :f, X)]; shared=true)
    @test LK.do_unify_cells(ld, -(t + 1), -(t + 2)) == LK.BOOLEX_TRUE
    tr = LK.trie_create(T)
    rc, nid = LK.trie_lookup_abstract(ld, tr, 0, -(t + 2), true, nothing, nothing)
    @test (rc, nid) == (LK.TRIE_LOOKUP_CYCLIC, 0) && LK.TRIE_LOOKUP_CYCLIC == -11
    # the 999 f/1 nodes made before the check (at the 1000th compound) are pruned again with the error key
    @test tr.node_count == 1 && tr.nodes[1].children == 0
    # trie_error: a type error on the culprit, false
    cul = LK.PL_new_term_ref(ld)
    LK.PL_put_atom(ld, cul, s(:foo))
    @test LK.trie_error(ld, rc, cul) == false
    @test _tr_formal(ld) == (:type_error, :acyclic_term)
    LK.PL_clear_exception(ld)
    # an acyclic term 1001 deep passes the same check: f(f(...f(a)...))
    deep = s(:a)
    for _ in 1:1001
        deep = _trx(T, :f, deep)
    end
    gd2, ld2, t2 = _tr_engine(T, T[deep])
    tr2 = LK.trie_create(T)
    rc2, n2 = LK.trie_lookup_abstract(ld2, tr2, 0, -(t2 + 1), true, nothing, nothing)
    @test rc2 == 1 && n2 != 0 && tr2.node_count == 1 + 1001 + 1 &&
        tr2.nodes[n2].key == _trw(ld2, T, :a)
    return nothing
end

@testset "trie lookup: a cyclic term, trie_error" begin
    _tr_lookup_cyclic_rows(_TT)
end

function _tr_lookup_attvar_rows(::Type{T}) where {T}
    # an attributed variable (O_TRIE_ATTVAR, TR3): numbered, its cell overwritten while the lookup runs, its attribute list walked as a compound
    # that ends with the keys POP and TAGEX_TRIE_ATTVAR_END; `vars` gets the pair (the attvar's location, its attribute list), the cell is restored
    s(n) = lk_sym(T, n)
    Z, Y = _trv(T, 1), _trv(T, 2)
    gd, ld, t = _tr_engine(T, T[_trx(T, :f, Z, Y)])
    w = ld.slots[t + 1]
    zc, _ = LK.trie_deref(ld, LK.valPtr(w) + 1)
    yc, _ = LK.trie_deref(ld, LK.valPtr(w) + 2)
    LK.put_new_attvar(
        ld, yc, LK._atom_word!(ld, s(:a)), (LK.DU_VALUE, LK.consInt(Int64(1)), 0)
    )
    yp, yw = LK.trie_deref(ld, LK.valPtr(w) + 2)
    @test LK.isAttVar(yw)
    tr = LK.trie_create(T)
    vars = Int[]
    rc, nid = LK.trie_lookup_abstract(ld, tr, 0, -(t + 1), true, nothing, vars)
    # f(Z, Y{a = 1}): f/2, V1, ATTVAR 2, att/3, a, 1, [], POP(2) (att/3 and the attribute list), ATTVAR_END 2; f's end is the toplevel's: no key
    @test rc == 1 &&
        _tr_path(tr, nid) == UInt64[
        _trf(ld, T, :f, 2), _trvar(1), LK.consTagged(2, LK.TAGEX_TRIE_ATTVAR),
        LK._functor_att3(ld), _trw(ld, T, :a), LK.consInt(1),
        ld.atom_nil_w, LK.TRIE_KEY_POP(2), LK.consTagged(2, LK.TAGEX_TRIE_ATTVAR_END)
    ]
    @test vars == [zc, yp, LK.valPtr(yw)]
    @test ld.gstack[zc] == 0 && ld.gstack[yp] == yw                 # every cell given back, the attributed variable's too
    @test tr.node_count == 10
    # the same lookup without `add` finds the same node
    @test LK.trie_lookup_abstract(ld, tr, 0, -(t + 1), false, nothing, nothing) ==
          (1, nid) && ld.gstack[yp] == yw
    # a lookup that stops at the ATTVAR key (the trie has f/2, V1 only) gives the overwritten cell back as well
    trc = LK.trie_create(T)
    LK.follow_node_add(trc, LK.follow_node_add(trc, 1, _trf(ld, T, :f, 2)), _trvar(1))
    @test LK.trie_lookup_abstract(ld, trc, 0, -(t + 1), false, nothing, nothing) == (0, 0)
    @test ld.gstack[zc] == 0 && ld.gstack[yp] == yw && trc.node_count == 3
    return nothing
end

function _tr_lookup_attvar_value_rows(::Type{T}) where {T}
    # f(Z, Y{a = 1}) and f(Z, Y{a = 2}) are two keys sequences: the second is not in the first's trie
    s(n) = lk_sym(T, n)
    gd, ld, t = _tr_engine(
        T, T[_trx(T, :f, _trv(T, 1), _trv(T, 2)), _trx(T, :f, _trv(T, 1), _trv(T, 2))]
    )
    ps = Int[]
    for (i, val) in ((1, 1), (2, 2))
        w = ld.slots[t + i]
        yc, _ = LK.trie_deref(ld, LK.valPtr(w) + 2)
        LK.put_new_attvar(
            ld, yc, LK._atom_word!(ld, s(:a)), (LK.DU_VALUE, LK.consInt(Int64(val)), 0)
        )
        push!(ps, LK.trie_deref(ld, LK.valPtr(w) + 2)[1])
    end
    yws = [ld.gstack[p] for p in ps]
    tr = LK.trie_create(T)
    rc1, n1 = LK.trie_lookup_abstract(ld, tr, 0, -(t + 1), true, nothing, nothing)
    @test rc1 == 1 && n1 != 0
    @test LK.trie_lookup_abstract(ld, tr, 0, -(t + 2), false, nothing, nothing) == (0, 0)
    @test [ld.gstack[p] for p in ps] == yws
    rc2, n2 = LK.trie_lookup_abstract(ld, tr, 0, -(t + 2), true, nothing, nothing)
    @test rc2 == 1 && n2 != n1 && [ld.gstack[p] for p in ps] == yws
    @test LK.trie_lookup_abstract(ld, tr, 0, -(t + 1), false, nothing, nothing) == (1, n1)
    return nothing
end

function _tr_lookup_attvar_shared_rows(::Type{T}) where {T}
    # f(Y, Y) with Y attributed: the second occurrence is the attvar's number again (no second attribute walk), the END key comes after the first's POP
    s(n) = lk_sym(T, n)
    Y = _trv(T, 1)
    gd, ld, t = _tr_engine(T, T[_trx(T, :f, Y, Y)])
    w = ld.slots[t + 1]
    yc, _ = LK.trie_deref(ld, LK.valPtr(w) + 1)
    LK.put_new_attvar(
        ld, yc, LK._atom_word!(ld, s(:a)), (LK.DU_VALUE, LK.consInt(Int64(1)), 0)
    )
    yp, yw = LK.trie_deref(ld, LK.valPtr(w) + 1)
    tr = LK.trie_create(T)
    vars = Int[]
    rc, nid = LK.trie_lookup_abstract(ld, tr, 0, -(t + 1), true, nothing, vars)
    k1 = LK.consTagged(1, LK.TAGEX_TRIE_ATTVAR)
    @test rc == 1 &&
        _tr_path(tr, nid) == UInt64[
        _trf(ld, T, :f, 2), k1, LK._functor_att3(ld), _trw(ld, T, :a), LK.consInt(1),
        ld.atom_nil_w, LK.TRIE_KEY_POP(2),
        LK.consTagged(1, LK.TAGEX_TRIE_ATTVAR_END), k1
    ]
    @test vars == [yp, LK.valPtr(yw)] && ld.gstack[yp] == yw
    return nothing
end

function _tr_lookup_attvar_more_rows(::Type{T}) where {T}
    s(n) = lk_sym(T, n)
    k1 = LK.consTagged(1, LK.TAGEX_TRIE_ATTVAR)
    e1 = LK.consTagged(1, LK.TAGEX_TRIE_ATTVAR_END)
    # a term that goes on after the attvar: f(Y{a = 1}, g(b), c): the END key comes once (after the POP of att/3), the later POP(1) of g is plain
    gd, ld, t = _tr_engine(T, T[_trx(T, :f, _trv(T, 1), _trx(T, :g, s(:b)), s(:c))])
    w = ld.slots[t + 1]
    yc, _ = LK.trie_deref(ld, LK.valPtr(w) + 1)
    LK.put_new_attvar(
        ld, yc, LK._atom_word!(ld, s(:a)), (LK.DU_VALUE, LK.consInt(Int64(1)), 0)
    )
    yp, yw = LK.trie_deref(ld, LK.valPtr(w) + 1)
    tr = LK.trie_create(T)
    rc, nid = LK.trie_lookup_abstract(ld, tr, 0, -(t + 1), true, nothing, nothing)
    @test rc == 1 &&
        _tr_path(tr, nid) == UInt64[
        _trf(ld, T, :f, 3), k1, LK._functor_att3(ld), _trw(ld, T, :a), LK.consInt(1),
        ld.atom_nil_w, LK.TRIE_KEY_POP(2), e1,
        _trf(ld, T, :g, 1), _trw(ld, T, :b), LK.TRIE_KEY_POP(1), _trw(ld, T, :c)
    ]
    @test ld.gstack[yp] == yw
    # the attvar itself is the term (at the toplevel): its end is the toplevel's POP, then the END key
    gd, ld, t = _tr_engine(T, T[_trx(T, :f, _trv(T, 1))])
    w = ld.slots[t + 1]
    yc, _ = LK.trie_deref(ld, LK.valPtr(w) + 1)
    LK.put_new_attvar(
        ld, yc, LK._atom_word!(ld, s(:a)), (LK.DU_VALUE, LK.consInt(Int64(1)), 0)
    )
    yp, yw = LK.trie_deref(ld, LK.valPtr(w) + 1)
    tr = LK.trie_create(T)
    rc, nid = LK.trie_lookup_abstract(ld, tr, 0, LK.valPtr(w) + 1, true, nothing, nothing)
    @test rc == 1 &&
        _tr_path(tr, nid) == UInt64[
        k1, LK._functor_att3(ld), _trw(ld, T, :a), LK.consInt(1), ld.atom_nil_w,
        LK.TRIE_KEY_POP(2), e1
    ]
    @test ld.gstack[yp] == yw
    return nothing
end

function _tr_unify_attvar_write_rows(::Type{T}) where {T}
    # f(Y, Y) with Y attributed, unified with a FREE variable (unify_trie_term: write mode, pl-trie.c unify_key under TAG_ATTVAR|STG_STATIC): the first
    # occurrence stores `makeRefG(&gp[1])` (the new attvar's link cell) in its argument cell, a later occurrence in write mode stores `makeRefG(vi->attributes)`,
    # the SAME word - not a reference to the first argument cell (that would chain through it). No Prolog predicate sees the chain: the raw cells are compared.
    s(n) = lk_sym(T, n)
    Y = _trv(T, 1)
    gd, ld, t = _tr_engine(T, T[_trx(T, :f, Y, Y), _trv(T, 2)])
    w = ld.slots[t + 1]
    yc, _ = LK.trie_deref(ld, LK.valPtr(w) + 1)
    LK.put_new_attvar(
        ld, yc, LK._atom_word!(ld, s(:a)), (LK.DU_VALUE, LK.consInt(Int64(1)), 0)
    )
    tr = LK.trie_create(T)
    rc, nid = LK.trie_lookup_abstract(ld, tr, 0, -(t + 1), true, nothing, nothing)
    @test rc == 1
    # (`unify_trie_term` takes a term reference: slot `t + 2` is the reference `t + 1`)
    @test LK.unify_trie_term(ld, tr, nid, t + 1) == (true, 0)
    _, cw = LK.trie_deref(ld, -(t + 2))
    @test LK._is_gcompound(cw)
    c = LK.valPtr(cw)
    p1, w1 = LK.trie_deref(ld, c + 1)
    p2, w2 = LK.trie_deref(ld, c + 2)
    @test LK.isAttVar(w1) && LK.isAttVar(w2) && p1 == p2                  # one attributed variable in both arguments
    @test ld.gstack[c + 1] == ld.gstack[c + 2]                            # both cells hold the same reference (no chain through the first argument)
    return nothing
end

@testset "trie lookup: an attributed variable (TR3): its keys, the pair in vars, the cells restored" begin
    _tr_lookup_attvar_rows(_TT)
    _tr_lookup_attvar_value_rows(_TT)
    _tr_lookup_attvar_shared_rows(_TT)
    _tr_lookup_attvar_more_rows(_TT)
    _tr_unify_attvar_write_rows(_TT)
end

# ---- trie_insert_flat / trie_lookup_flat ----

function _tr_insert_flat_rows(::Type{T}) where {T}
    s(n) = lk_sym(T, n)
    X, Z = _trv(T, 1), _trv(T, 2)
    vs = T[
        _trx(T, :p, s(:a), X, X, lk_gnd(T, Int64(1))), s(:foo), lk_gnd(T, Int64(3)),
        _trx(T, :p, _trx(T, :q, s(:a))), Z,
        _trx(T, :p, lk_gnd(T, 2.5), s(:a)), _trx(T, :p, X)
    ]
    gd, ld, t = _tr_engine(T, vs)
    loc(i) = -(t + i)
    tr = LK.trie_create(T)
    rc, n1 = LK.trie_insert_flat(ld, tr, loc(1))
    @test rc == 1 && tr.node_count == 6 && tr.lookups == 1
    @test _tr_path(tr, n1) ==
        UInt64[_trf(ld, T, :p, 4), _trw(ld, T, :a), _trvar(1), _trvar(1), LK.consInt(1)]
    @test LK.trie_insert_flat(ld, tr, loc(1)) == (1, n1) && tr.node_count == 6          # again: the same node
    # the cells were restored: the general lookup of the same term finds the same node (it numbers the variables itself)
    @test LK.trie_lookup_abstract(ld, tr, 0, loc(1), false, nothing, nothing) == (1, n1)
    # the cells are plain unbound variables again, read raw (swipl cannot answer this: the lookup above gives the same node with
    # numbered cells too, a numbered cell being the key V1 it stands for; pl-trie.c trie_insert_flat's last loop `setVar(*vars[i])`)
    _, cw = LK.trie_deref(ld, loc(1))
    @test all(i -> LK.isVar(LK.trie_deref(ld, LK.valPtr(cw) + i)[2]), (2, 3))
    # an atom
    ra, na = LK.trie_insert_flat(ld, tr, loc(2))
    @test ra == 1 && _tr_path(tr, na) == UInt64[_trw(ld, T, :foo)] && tr.node_count == 7
    # not flat: an integer alone, a compound argument, a variable alone: nothing added
    @test LK.trie_insert_flat(ld, tr, loc(3)) == (LK.TRIE_LOOKUP_NOT_FLAT, 0)
    @test LK.trie_insert_flat(ld, tr, loc(4)) == (LK.TRIE_LOOKUP_NOT_FLAT, 0)
    @test LK.trie_insert_flat(ld, tr, loc(5)) == (LK.TRIE_LOOKUP_NOT_FLAT, 0) &&
        LK.TRIE_LOOKUP_NOT_FLAT == -12
    @test tr.node_count == 7
    # an indirect argument, by handle
    rf, nf = LK.trie_insert_flat(ld, tr, loc(6))
    @test rf == 1 &&
        _tr_path(tr, nf) == UInt64[
        _trf(ld, T, :p, 2), LK.consTagged(1, LK.TAGEX_INDIRECT_FLOAT), _trw(ld, T, :a)
    ]
    @test tr.indirects !== nothing && length(tr.indirects.values) == 1
    @test LK.trie_lookup_abstract(ld, tr, 0, loc(6), false, nothing, nothing) == (1, nf)
    # a single variable
    rv, nv = LK.trie_insert_flat(ld, tr, loc(7))
    @test rv == 1 && _tr_path(tr, nv) == UInt64[_trf(ld, T, :p, 1), _trvar(1)]

    # FLAT_MAX_VARS = 32 distinct variables are flat (arguments past FLAT_MAX_ARGS = 16 are dereferenced in the second pass); 33 are not
    @test LK.FLAT_MAX_VARS == 32 && LK.FLAT_MAX_ARGS == 16
    v32 = T[_trv(T, i) for i in 1:32]
    v33 = T[_trv(T, i) for i in 1:33]
    mixed = T[fill(s(:a), 16)..., _trv(T, 1), lk_gnd(T, 2.5)]
    gd2, ld2, t2 = _tr_engine(
        T, T[_trx(T, :p, v32...), _trx(T, :p, v33...), _trx(T, :p, mixed...)]
    )
    tr2 = LK.trie_create(T)
    r32, n32 = LK.trie_insert_flat(ld2, tr2, -(t2 + 1))
    @test r32 == 1 && tr2.node_count == 1 + 1 + 32
    @test _tr_path(tr2, n32) == UInt64[_trf(ld2, T, :p, 32), (_trvar(i) for i in 1:32)...]
    @test LK.trie_insert_flat(ld2, tr2, -(t2 + 2)) == (LK.TRIE_LOOKUP_NOT_FLAT, 0) &&
        tr2.node_count == 34
    rm, nm = LK.trie_insert_flat(ld2, tr2, -(t2 + 3))
    @test rm == 1 &&
        _tr_path(tr2, nm) == UInt64[
        _trf(ld2, T, :p, 18), fill(_trw(ld2, T, :a), 16)..., _trvar(1),
        LK.consTagged(1, LK.TAGEX_INDIRECT_FLOAT)
    ]
    return nothing
end

@testset "trie insert_flat: flat terms, NOT_FLAT, the argument limits" begin
    _tr_insert_flat_rows(_TT)
end

function _tr_lookup_flat_rows(::Type{T}) where {T}
    s(n) = lk_sym(T, n)
    X = _trv(T, 1)
    # slots: a, X, X, 2.5, g(b), 7, b, 8.5
    gd, ld, t = _tr_engine(
        T,
        T[
            s(:a),
            X,
            X,
            lk_gnd(T, 2.5),
            _trx(T, :g, s(:b)),
            lk_gnd(T, Int64(7)),
            s(:b),
            lk_gnd(T, 8.5)
        ];
        shared=true
    )
    loc(i) = -(t + i)
    user = LK.MODULE_user(gd)
    def = LK.lookupProcedure(s(:p), 2, user).definition
    colon = _trf(ld, T, :(:), 2)
    mname = LK._atom_word!(ld, gd.modules[def.module_].atom)
    pf = _trf(ld, T, :p, 2)
    tr = LK.trie_create(T)
    # no `:`/2 child yet: (0, start 0, node 0)
    @test LK.trie_lookup_flat(gd, ld, tr, 0, def, [loc(1), loc(2)], Int[]) == (0, 0, 0)
    ncol = LK.follow_node_add(tr, 1, colon)
    @test LK.trie_lookup_flat(gd, ld, tr, 0, def, [loc(1), loc(2)], Int[]) == (0, 0, 0)       # no module child
    nmod = LK.follow_node_add(tr, ncol, mname)
    @test LK.trie_lookup_flat(gd, ld, tr, 0, def, [loc(1), loc(2)], Int[]) == (0, 0, 0)       # no p/2 child
    base = LK.follow_node_add(tr, nmod, pf)
    walk(start, keys...) = foldl((n, k) -> LK.follow_node_add(tr, n, k), keys; init=start)
    a, b = _trw(ld, T, :a), _trw(ld, T, :b)
    n1 = walk(base, a, _trvar(1))
    n2 = walk(base, _trvar(1), _trvar(1))
    hf = LK.trie_intern_indirect(tr, lk_gnd(T, 2.5), true)
    n3 = walk(base, hf, b)
    n4 = walk(base, LK.consInt(7), _trvar(1))
    # p(a, X) -> [a, V1]: the variable's cell is handed back in `vars` and stays unbound
    vars = Int[]
    l0 = tr.lookups
    @test LK.trie_lookup_flat(gd, ld, tr, 0, def, [loc(1), loc(2)], vars) == (1, base, n1)
    @test tr.lookups == l0 + 1 && length(vars) == 1 && vars[1] > 0 &&
        ld.gstack[vars[1]] == 0
    # p(X, X) -> [V1, V1]: one variable, the same number twice
    vars = Int[]
    @test LK.trie_lookup_flat(gd, ld, tr, 0, def, [loc(2), loc(3)], vars) ==
          (1, base, n2) && length(vars) == 1
    # an indirect argument is found by value, an unknown one is not (nothing is interned)
    @test LK.trie_lookup_flat(gd, ld, tr, 0, def, [loc(4), loc(7)], Int[]) == (1, base, n3)
    @test LK.trie_lookup_flat(gd, ld, tr, 0, def, [loc(8), loc(7)], Int[]) ==
          (0, base, 0) && length(tr.indirects.values) == 1
    # a tagged integer and a variable
    @test LK.trie_lookup_flat(gd, ld, tr, 0, def, [loc(6), loc(2)], Int[]) == (1, base, n4)
    # missing: a child of a (an integer, no V1 variable path)
    @test LK.trie_lookup_flat(gd, ld, tr, 0, def, [loc(1), loc(6)], Int[]) == (0, base, 0)
    # not flat: a compound argument
    @test LK.trie_lookup_flat(gd, ld, tr, 0, def, [loc(5), loc(1)], Int[]) ==
        (LK.TRIE_LOOKUP_NOT_FLAT, base, 0)
    # from a start node: only the arguments are followed
    @test LK.trie_lookup_flat(gd, ld, tr, base, def, [loc(1), loc(2)], Int[]) ==
        (1, base, n1)
    # arity 0: `:`/2, the module, the name
    def0 = LK.lookupProcedure(s(:q), 0, user).definition
    @test LK.trie_lookup_flat(gd, ld, tr, 0, def0, Int[], Int[]) == (0, nmod, 0)
    nq = LK.follow_node_add(tr, nmod, _trw(ld, T, :q))
    @test LK.trie_lookup_flat(gd, ld, tr, 0, def0, Int[], Int[]) == (1, nmod, nq)
    return nothing
end

@testset "trie lookup_flat: M:Head of a predicate, variables, indirects, NOT_FLAT" begin
    _tr_lookup_flat_rows(_TT)
end

# ---- THE BLOB REGISTRY ----

function _tr_blob_rows(::Type{T}) where {T}
    s(n) = lk_sym(T, n)
    gd, ld, t = _tr_engine(T, T[lk_sym(T, :a)])
    n0 = length(gd.tries)
    tr = LK.trie_create(T)
    w = LK.trie_symbol(gd, tr)
    @test tr.symbol == w && tr.serial == n0 + 1 && gd.tries[tr.serial] === tr &&
        length(gd.tries) == n0 + 1
    @test LK.trie_symbol(gd, tr) == w && length(gd.tries) == n0 + 1                  # created once
    tr2 = LK.trie_create(T)
    w2 = LK.trie_symbol(gd, tr2)
    @test w2 != w && tr2.serial == n0 + 2
    @test LK.symbol_trie(gd, w) === tr && LK.symbol_trie(gd, w2) === tr2
    @test LK.symbol_trie(gd, _trw(ld, T, :foo)) === nothing &&
        LK.trie_of_word(gd, _trw(ld, T, :foo)) === nothing

    # unify_trie / get_trie / get_trie_noex on a term reference
    ref = LK.PL_new_term_ref(ld)
    @test LK.unify_trie(gd, ld, ref, tr)
    @test LK.get_trie(gd, ld, ref) === tr && LK.get_trie_noex(gd, ld, ref) === tr &&
        ld.exception_term == 0
    @test LK.unify_trie(gd, ld, ref, tr) && !LK.unify_trie(gd, ld, ref, tr2)           # the same blob, not the other
    # a term that is no trie: get_trie raises type_error(trie, _), get_trie_noex says nothing and raises nothing
    atm = LK.PL_new_term_ref(ld)
    LK.PL_put_atom(ld, atm, s(:foo))
    @test LK.get_trie_noex(gd, ld, atm) === nothing && ld.exception_term == 0
    @test LK.get_trie(gd, ld, atm) === nothing
    @test _tr_formal(ld) == (:type_error, :trie)
    LK.PL_clear_exception(ld)
    # a destroyed trie: symbol_trie and get_trie refuse it (existence_error(trie, _)); get_trie_noex still names it
    LK.trie_destroy(gd, tr)
    @test tr.magic == LK.TRIE_CMAGIC && LK.symbol_trie(gd, w) === nothing &&
        LK.trie_of_word(gd, w) === tr
    @test LK.get_trie_noex(gd, ld, ref) === tr && ld.exception_term == 0
    @test LK.get_trie(gd, ld, ref) === nothing
    @test _tr_formal(ld) == (:existence_error, :trie)
    LK.PL_clear_exception(ld)
    return nothing
end

@testset "trie blobs: trie_symbol, symbol_trie, get_trie, get_trie_noex" begin
    _tr_blob_rows(_TT)
end

function _tr_error_rows(::Type{T}) where {T}
    s(n) = lk_sym(T, n)
    gd, ld, t = _tr_engine(T, T[lk_sym(T, :a)])
    cul = LK.PL_new_term_ref(ld)
    LK.PL_put_atom(ld, cul, s(:foo))
    # CONTAINS_ATTVAR: type_error(free_of_attvar, Culprit); CYCLIC: type_error(acyclic_term, Culprit); every other rc: false, no exception
    @test !LK.trie_error(ld, LK.TRIE_LOOKUP_CONTAINS_ATTVAR, cul) &&
        _tr_formal(ld) == (:type_error, :free_of_attvar)
    LK.PL_clear_exception(ld)
    @test !LK.trie_error(ld, LK.TRIE_LOOKUP_CYCLIC, cul) &&
        _tr_formal(ld) == (:type_error, :acyclic_term)
    LK.PL_clear_exception(ld)
    for rc in (0, 1, LK.TRIE_ABSTRACTED, LK.TRIE_LOOKUP_NOT_FLAT)
        @test !LK.trie_error(ld, rc, cul) && ld.exception_term == 0
    end
    @test LK.TRIE_LOOKUP_CONTAINS_ATTVAR == -10
    # trie_trie_error: the same with the trie's symbol as the culprit
    tr = LK.trie_create(T)
    @test !LK.trie_trie_error(gd, ld, LK.TRIE_LOOKUP_CYCLIC, tr) &&
        _tr_formal(ld) == (:type_error, :acyclic_term)
    LK.PL_clear_exception(ld)
    @test !LK.trie_trie_error(gd, ld, 1, tr) && ld.exception_term == 0
    return nothing
end

@testset "trie errors: trie_error, trie_trie_error" begin
    _tr_error_rows(_TT)
end

# ---- THE VALUE OF A NODE (trie_insert) ----

function _tr_value_rows(::Type{T}) where {T}
    s(n) = lk_sym(T, n)
    # slots: the key k, the values f(a) and f(b) (a record each: neither an atom nor a tagged integer), the atom z
    # (the term reference of slot `t + i` is `t + i - 1`: `t`, `t + 1`, `t + 2`, `t + 3`)
    gd, ld, t = _tr_engine(T, T[s(:k), _trx(T, :f, s(:a)), _trx(T, :f, s(:b)), s(:z)])
    tr = LK.trie_create(T)
    tref = LK.PL_new_term_ref(ld)
    @test LK.unify_trie(gd, ld, tref, tr)
    # a first value: one value counted, one record kept
    ok, nid = LK.trie_insert(gd, ld, tref, t, t + 1, false, nothing)
    @test ok && nid != 0 && tr.value_count == 1 && length(tr.records) == 1 &&
        isempty(tr.free_records)
    # an update with a different value: the old record is erased and its slot is free again, the count stays
    ok, nid2 = LK.trie_insert(gd, ld, tref, t, t + 2, true, nothing)
    @test ok && nid2 == nid && tr.value_count == 1 && tr.free_records == [1] &&
        tr.records[1] === nothing && tr.records[2] !== nothing
    # an update of a record by an atom: the two are not equal (equal_value compares two records only), the record goes
    ok, nid3 = LK.trie_insert(gd, ld, tref, t, t + 3, true, nothing)
    @test ok && nid3 == nid && tr.value_count == 1 && tr.free_records == [1, 2] &&
        all(isnothing, tr.records)
    return nothing
end

function _tr_unify_rows(::Type{T}) where {T}
    # slots: f(X, X), f(1, 2), f(3, 3): the keys of the node are f/2, V1, V1 (a repeated variable); g(1.5), g(2.5), g(1.5): an indirect key
    gd, ld, t = _tr_engine(
        T,
        T[
            _trx(T, :f, _trv(T, 1), _trv(T, 1)),
            _trx(T, :f, lk_gnd(T, Int64(1)), lk_gnd(T, Int64(2))),
            _trx(T, :f, lk_gnd(T, Int64(3)), lk_gnd(T, Int64(3))),
            _trx(T, :g, lk_gnd(T, 1.5)), _trx(T, :g, lk_gnd(T, 2.5)),
            _trx(T, :g, lk_gnd(T, 1.5))
        ]
    )
    tr = LK.trie_create(T)
    rc, nid = LK.trie_lookup_abstract(ld, tr, 0, -(t + 1), true, nothing, nothing)
    @test rc == 1 && nid != 0
    # (`unify_trie_term` takes a term reference: slot `t + i` is the reference `t + i - 1`)
    # the second occurrence of the variable is unified with the first: 1 and 2 do not unify, 3 and 3 do
    @test LK.unify_trie_term(ld, tr, nid, t + 1) == (false, 0)
    @test LK.unify_trie_term(ld, tr, nid, t + 2) == (true, 0)
    # an indirect key (a float handle) is compared with the float of the term: 1.5 and 2.5 do not unify, 1.5 and 1.5 do
    rc, nid = LK.trie_lookup_abstract(ld, tr, 0, -(t + 4), true, nothing, nothing)
    @test rc == 1 && nid != 0
    @test LK.unify_trie_term(ld, tr, nid, t + 4) == (false, 0)
    @test LK.unify_trie_term(ld, tr, nid, t + 5) == (true, 0)
    return nothing
end

@testset "trie values: trie_insert counts the value, an update releases the old record" begin
    _tr_value_rows(_TT)
end

@testset "trie keys: a repeated variable key is unified with its first occurrence" begin
    _tr_unify_rows(_TT)
end

# ---- THE KEPT CLAUSE REFERENCE (trie_discard_clause) ----

"A set trie with one path (one opaque atom key) and a value, compiled by `compile_trie` into trie_gen_compiled/2: `(trie, kept clause reference)`."
function _tr_compiled_one(gd, ld, ::Type{T}) where {T}
    tr = LK.trie_create(T)
    n = LK.insert_child(tr, 1, _tk(1))
    tr.nodes[n].value = UInt64(5)        # a tagged integer (low bits 101): not a record, not a trie pointer (tag 7: release_value would look it up)
    tr.nodes[n].flags |= LK.TN_PRIMARY
    tr.value_count = 1
    dbref = LK.compile_trie(gd, ld, gd.procedures_trie_gen_compiled2.definition, tr)
    @test dbref != 0 && tr.clause == dbref && tr.clause_cref !== nothing
    return tr, tr.clause_cref
end

# The invariant behind `cl = cref.clause::Clause{T}` in `trie_discard_clause` (src/pl-trie.jl): the reference a trie keeps holds its clause for
# the trie's whole life. swipl-devel 18168e62 src/pl-trie.c:283 reads `cref->value.clause` and dereferences it with no test (only `if (cref)`
# at :282): the pin has no defined behaviour for a reference without a clause, so there is no swipl answer to pin: this row asserts the
# kernel's invariant (a defined-behaviour gap in the pin, an assertion in the kernel). White-box.
function _tr_discard_clause_rows(::Type{T}) where {T}
    gd, ld, _ = _tr_engine(T, T[lk_sym(T, :k)])
    tr, cref = _tr_compiled_one(gd, ld, T)
    cl = cref.clause
    @test cl isa LK.Clause{T} && cref.clauses === nothing     # a clause cell, not an index list cell
    @test (cl.flags & LK.CL_ERASED) == 0                      # live while the trie holds it
    # trie_destroy reaches trie_discard_clause: the clause is retracted, the reference still holds it (no TypeError)
    LK.trie_destroy(gd, tr)
    @test tr.clause == 0 && tr.clause_cref === nothing
    @test (cl.flags & LK.CL_ERASED) != 0                      # the retract ran on that clause (kills TR4-D3, TR4-D4, TR4-D5)
    @test cref.clause === cl                                  # an erased clause stays in its reference, as at the pin
    # a halt in progress (`gd.halt_cleaning` not CLN_NORMAL): the word and the reference are dropped, nothing is retracted
    tr2, cref2 = _tr_compiled_one(gd, ld, T)
    cl2 = cref2.clause
    gd.halt_cleaning = LK.CLN_DATA
    LK.trie_discard_clause(gd, tr2)
    gd.halt_cleaning = LK.CLN_NORMAL
    @test (cl2.flags & LK.CL_ERASED) == 0 && tr2.clause == 0 && tr2.clause_cref === nothing
    return nothing
end

@testset "trie_discard_clause: the kept reference holds a live clause (white-box)" begin
    _tr_discard_clause_rows(_TT)
end
