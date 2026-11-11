# ORIGINAL: TR1's mutant list — no swipl-devel counterpart.
# tools/mutants/TRIE1.py — the mutation battery of TR1, the trie of pl-trie.c ported into src/pl-trie.jl (the trie and its children blocks, node
# allocation (individual nodes, chunks), the sweep of the chunks, prune/clear/walk/stat, the indirect table, the lookup (ground, indirect,
# variant, abstracted, cyclic, attributed-variable, the flat lookup/insert), the trie blob and its errors, and the eleven predicates TR1
# registers: is_trie/1, trie_new/1, trie_destroy/1, trie_insert/2,3,4, `$trie_insert_abstract`/3, trie_update/3, trie_lookup/3, trie_delete/3,
# trie_term/2) plus the one call that boots it (src/pl-setup.jl). The list pins what is there at the gate of TR1. Run ONCE, in CI
# (.github/workflows/mutation.yml; locally: tools/mutate.sh run). Format: tools/mutate_drive.py's (as PIN1.py, HF1.py): `id`, `file`, `old`
# (must occur EXACTLY once), `new`, optional `equivalent` and `targets`.
# Each id names its KILL, the assertion that must fail (file:line at the commit that counts the lists, see the last line):
#   TW = test/core_lang/test_trie_swipl.jl (white-box rows on LK.* internals), TP = test/core_lang/test_trie_preds_swipl.jl (the predicate rows:
#   the answers are swipl's, from test_trie_preds_swipl.out, and the `row("tN")` kill rows by name), TB = test/db/test_boot_image_swipl.jl.
# TARGETS (audit D-0238): every test file that runs the mutated code and can see its effect: TW and TP for every mutant (the trie code is under
#   both: TW calls the internals, TP the predicates on the booted database); TR1-N3 and TR1-N4 (a dropped registration) also TB, whose
#   boot-module predicate rows count the foreign rows the kernel lacks (`_BI_KERNEL_MISSING_FOREIGN`, TB:161). The `TARGETS` variable is the union
#   (mutate_ci.py plan reads it).
# VERDICTS: the CI mutation battery runs one fresh process per mutant and its verdicts are authoritative. TR1-N1 and TR1-N2 are BOOT-PATH
#   mutants (`initTries!` and its call in src/pl-setup.jl:266 run while the database boots, before any test row; `PL_global_data{T}()` copies a
#   template built once per process, src/gd_template.jl): the warm daemon cannot judge them, only `tools/mutate_ci.py one` (one process per
#   mutant) or the CI battery does (audit D-0451 item 1, as PIN1 part 2).
# TIMEOUT: TR1-L1 is the bounded form of the cyclic check, `(compounds == 1000 && add && is_acyclic_cells(ld, l)) || compounds == 5000`: an acyclic
#   term of depth 1000 is flagged (TW:1038 fails) and the cyclic term still stops, at 5000 compounds, instead of looping. A timeout is NO
#   verdict, never caught: no mutant of this list may run unbounded.
# DEFERRED KILL (audit D-0374 item 2): a row declared `equivalent="DEFERRED KILL: ..."` has no killing assertion yet — no test file reads what
#   the mutant changes (a finding for a test step, not invented here). It must SURVIVE the battery; when a test step adds the row, the declaration goes.
#   * TR1-V6 (trie_new/1 without TRIE_CONCURRENT): owner TR2, or a TR1 row that sets ld.GD (TW cannot call pl_trie_new1_va: `_query_gd(ld)`
#     needs ld.GD from a running query, src/pl-comp.jl:4161).
#   * TR1-V11 (trie_delete/3 does not prune) and TR1-V12 (trie_lookup/3 answers an inner node): owner TR2 ($trie_property / trie_gen read the
#     arena after a delete) or a TW row that sets ld.GD (the foreign is pl_trie_delete3_va, src/pl-trie.jl:1999); V12 alone is unreachable while deletes prune.
#   (C6, S2, P3, V3, V4 were DEFERRED in the draft: the rows added after it kill them, TW:348, 542, 632, 1273/1276; B6 by the row t76, TP:261.)
# EQUIVALENT mutants (declared with their reason, file:line in the `equivalent` text): TR1-A4 (the chunk-size clamp at the maximum), TR1-S4
#   (sweep_at at kept*2 == the minimum), TR1-X1 (the cyclic check one compound later; the bounded TR1-L1 is its kill), TR1-W2b (the tab.wild loop
#   of a keyed value, by the gnd_value_key contract), TR1-K3 (trie_term/2's magic test: the range test refuses a destroyed trie's handle),
#   TR1-D2 (clear_node's CN_ALL chunked branch: clear_nodes resets what it frees),
#   TR1-V22 (unify_value's reserved-value branch: the atom branch reads the same reserved symbol, src/pl-atom.jl:2317-2326).
# Every `old` was counted EXACTLY once in its file by a python3 -I script at f504d2c2 (the last commit of src/pl-trie.jl and src/pl-setup.jl; the 112
#   mutants, no Julia ran); `new` != `old`; no duplicate
#   id. RE-FIT any `old` that `tools/warm.sh fmt` rewraps.
TW = "test/core_lang/test_trie_swipl.jl"
TP = "test/core_lang/test_trie_preds_swipl.jl"
TB = "test/db/test_boot_image_swipl.jl"
TG = "test/core_lang/test_trie_gen_swipl.jl"            # TAB1 stack: trie_gen (TR2) inserts and walks through the code TR1 mutates
TA = "test/core_lang/test_trie_attvar_swipl.jl"         # TAB1 stack: the attvar rows (TR3) insert, look up and enumerate
CR = "test/db/test_clause_ref_swipl.jl"          # the unbooted-database rank testset sees the boot path (initTries!, its call): TR1-N1, TR1-N2
TARGETS = [TW, TP, TB, TG, TA, CR]                       # the union of every mutant's targets (mutate_ci.py plan reads TARGETS)
F = "src/pl-trie.jl"
SETUP = "src/pl-setup.jl"
TT = [TW, TP, TG, TA]


def m(id, old, new, targets=TT, file=F, eq=None, hang=False):
    d = dict(id=id, file=file, old=old, new=new, targets=targets)
    if eq:
        d["equivalent"] = eq
    if hang:
        d["expect"] = "hang"            # a loop inside ONE call that no row can bound: "caught (hang)" past LIMIT_S
    return d


MUTANTS = [
    # ---- children (TW _tr_children_rows 192-299, _tr_compaction_rows 301-401)
    m("TR1-C1 single child coded id<<1 (KILL TW children rows: `root.children == 5`)",
      "single_child_code(id::Int)::Int = (id << 1) | 1", "single_child_code(id::Int)::Int = id << 1"),
    m("TR1-C2 block coded (bid<<1)|1 (KILL TW `root.children == 2`, `root.children == LK.block_code(1)`)",
      "block_code(bid::Int)::Int = bid << 1", "block_code(bid::Int)::Int = (bid << 1) | 1"),
    m("TR1-C3 compact_children: dead*2 >= count (KILL TW:356, 2*2 > 4 is false)",
      "        if b.dead == b.count || b.dead * 2 > b.count\n", "        if b.dead == b.count || b.dead * 2 >= b.count\n"),
    m("TR1-C4 delete_child: dead*2 >= count (KILL TW:306-307, two dead of four keep the block)",
      "            if compact && (empty || b.dead * 2 > b.count)\n", "            if compact && (empty || b.dead * 2 >= b.count)\n"),
    m("TR1-C5 replace_block: a single child only at live == 2 (KILL TW:308-309)",
      "    elseif live == 1\n", "    elseif live == 2\n"),
    m("TR1-C6 replace_block: capacity starts at 4 (KILL TW:348: 5 children, 3 deleted leave 2 live in a block of `capacity == 2`)",
      "        capacity = 2\n        while capacity < live\n", "        capacity = 4\n        while capacity < live\n"),
    m("TR1-C7 new_block: linear up to < TRIE_LINEAR_MAX (KILL TW children rows: capacity 8, index_bits == 0)",
      "    bits = capacity <= TRIE_LINEAR_MAX ? 0 : MSB(capacity) + 1\n", "    bits = capacity < TRIE_LINEAR_MAX ? 0 : MSB(capacity) + 1\n"),
    m("TR1-C8 new_block: index bits MSB(capacity) (KILL TW `index_bits == 5 && length(b.index) == 32`)",
      "    bits = capacity <= TRIE_LINEAR_MAX ? 0 : MSB(capacity) + 1\n", "    bits = capacity <= TRIE_LINEAR_MAX ? 0 : MSB(capacity)\n"),
    m("TR1-C9 add_child: the block grows by 4 (KILL TW children rows: 2 -> 4 -> 8 -> 16)",
      "            nbid = new_block(tr, b.capacity * 2)\n", "            nbid = new_block(tr, b.capacity * 4)\n"),
    m("TR1-C10 add_child: a dead entry is never revived (KILL TW `n15 == ids[15] && b.dead == 0 && b.count == 18`)",
      "        if b.dead != 0 && (pos = block_find(b, key)) > 0\n", "        if false && (pos = block_find(b, key)) > 0\n"),
    m("TR1-C11 block_copy: the variable mask is not copied (KILL TW:382)",
      "        to.var_mask = from.var_mask\n", "        nothing\n"),
    m("TR1-C12 block_copy: the attvar mask is not copied (KILL TW:383)",
      "        to.attvar_mask = from.attvar_mask\n", "        nothing\n"),
    m("TR1-C13 update_var_mask: bit vn, not vn-1 (KILL TW:375, TW:378)",
      "        b.var_mask |= vn < VMASKBITS ? UInt32(1) << (vn - 1) : VMASK_SCAN\n", "        b.var_mask |= vn < VMASKBITS ? UInt32(1) << (vn) : VMASK_SCAN\n"),
    m("TR1-C14 update_var_mask: the attvar bit is vn (KILL TW:383)",
      "        b.attvar_mask |= vn < VMASKBITS ? UInt32(1) << (vn - 1) : VMASK_SCAN\n", "        b.attvar_mask |= vn < VMASKBITS ? UInt32(1) << (vn) : VMASK_SCAN\n"),
    m("TR1-C15 child_hash: shift 63-bits, a slot past the index (KILL TW:260: child_hash(_tk(12345), 6) is 43, 86 under the mutant, not < 64)",
      ">> (64 - bits))", ">> (63 - bits))"),
    m("TR1-C16 block_find: the probe does not wrap (KILL TW:269: keys 36 and 73 share slot 31 of 32, get_child(trw, 1, _tk(73)) probes past the index)",
      "            b.entries[pos].key == key && return pos\n            h = (h + 1) & mask\n",
      "            b.entries[pos].key == key && return pos\n            h = h + 1\n"),
    m("TR1-C17 next_child!: a dead entry is returned (KILL TW `_tr_keys` after a delete, `!(_tk(15) in _tr_keys(tr, 1))`)",
      "            e.child != 0 && return (e.child, e.key)\n", "            return (e.child, e.key)\n"),
    m("TR1-C18 is_leaf_trie_node: count == 0 (KILL TW:364, all entries dead is a leaf)",
      "        return b.count == b.dead\n", "        return b.count == 0\n"),
    m("TR1-C19 get_child: a single child answers whatever the key (KILL TW children rows: `get_child(tr, 1, _tk(11)) == 0`)",
      "        return tr.nodes[child].key == key ? child : 0\n", "        return child\n"),
    # ---- allocation (TW _tr_concurrent_rows 403, _tr_chunk_rows 444, _tr_sweep_rows 506-551)
    m("TR1-A1 retire_block: never lingers (KILL TW:421, `tr.lingering == [1]`)",
      "    if (tr.flags & TRIE_CONCURRENT) != 0\n        push!(tr.lingering, bid)\n", "    if false\n        push!(tr.lingering, bid)\n"),
    m("TR1-A2 free_lingering_blocks: flag test inverted (KILL TW:432-436 and TW:422)",
      "    (tr.flags & TRIE_CONCURRENT) == 0 && return nothing\n    for bid in tr.lingering\n", "    (tr.flags & TRIE_CONCURRENT) != 0 && return nothing\n    for bid in tr.lingering\n"),
    m("TR1-A3 alloc_trie_node: 7 individual nodes, not 8 (KILL TW:451)",
      "    elseif tr.node_count <= TRIE_SINGLE_NODES\n", "    elseif tr.node_count < TRIE_SINGLE_NODES\n"),
    m("TR1-A4 chunk size clamp >= (EQUIVALENT: at bytes == TRIE_CHUNK_MAX the assignment is the identity)",
      "    bytes > TRIE_CHUNK_MAX && (bytes = TRIE_CHUNK_MAX)\n", "    bytes >= TRIE_CHUNK_MAX && (bytes = TRIE_CHUNK_MAX)\n",
      eq="src/pl-trie.jl:644 (alloc_trie_node): `bytes > TRIE_CHUNK_MAX && (bytes = TRIE_CHUNK_MAX)`: at bytes == TRIE_CHUNK_MAX (16384, :87) the assignment gives bytes the value it already has"),
    m("TR1-A5 chunk size grows by +1024 (KILL TW:470-478: 2048, 4096, 8192 expected)",
      "    bytes = c !== nothing ? Int(c.bytes) * 2 : TRIE_CHUNK_MIN\n", "    bytes = c !== nothing ? Int(c.bytes) + 1024 : TRIE_CHUNK_MIN\n"),
    m("TR1-A6 chunk header 64, not 72 (KILL TW:456, c.size == 23)",
      "        UInt32((bytes - OFFSETOF_TRIE_NODE_CHUNK_NODES) ÷ SIZEOF_TRIE_NODE),\n", "        UInt32((bytes - 64) ÷ SIZEOF_TRIE_NODE),\n"),
    m("TR1-A7 a chunk holds size+1 nodes (KILL TW:466/470, the 24th node starts the second chunk)",
      "        if c.used < c.size\n", "        if c.used <= c.size\n"),
    m("TR1-A8 a recycled chunk node does not count live (KILL TW:492, cs[end].live == 22)",
      "            cc.live += 1\n", "            nothing\n"),
    m("TR1-A9 a freed chunk node keeps its key (KILL TW:486, tr.nodes[f1].key == 0)",
      "n.key = 0", "n.key = n.key"),
    m("TR1-A10 a freed chunk node does not lower live (KILL TW:486, cs[end].live == 22)",
      "        c.live -= 1\n", "        nothing\n"),
    m("TR1-A11 a bump node does not count used (KILL TW:461, c.used == 2)",
      "        bump && (c.used = UInt32(idx + 1))\n", "        nothing\n"),
    # ---- sweep
    m("TR1-S1 sweep at nfree > sweep_at (KILL TW:515-524: sweep_at 1234, nfree 1085 after the first sweep at 1024)",
      "        if head.nfree >= head.sweep_at && head.nfree > tr.node_count\n", "        if head.nfree > head.sweep_at && head.nfree > tr.node_count\n"),
    m("TR1-S2 sweep without the nfree > node_count condition (KILL TW:542-543: 3000 leaves, 1024 destroyed, nfree 1024 = sweep_at while node_count is 1977: no sweep, 11 chunks, `isempty(tr.free_ids)`)",
      "        if head.nfree >= head.sweep_at && head.nfree > tr.node_count\n", "        if head.nfree >= head.sweep_at\n"),
    m("TR1-S3 the sweep drops the head chunk's nodes too (KILL TW:523 nfree == 1085, TW:532)",
      "        if c.live == 0 && c !== head\n", "        if c.live == 0\n"),
    m("TR1-S4 sweep_at kept*2 >= MIN (EQUIVALENT: at kept*2 == TRIE_SWEEP_MIN both branches give 1024)",
      "    head.sweep_at = UInt32(kept * 2 > TRIE_SWEEP_MIN ? kept * 2 : TRIE_SWEEP_MIN)\n", "    head.sweep_at = UInt32(kept * 2 >= TRIE_SWEEP_MIN ? kept * 2 : TRIE_SWEEP_MIN)\n",
      eq="src/pl-trie.jl:733 (sweep_node_chunks): at kept*2 == TRIE_SWEEP_MIN (1024, :90) the `>` branch yields TRIE_SWEEP_MIN and the `>=` branch yields kept*2, the same 1024"),
    m("TR1-S5 sweep_at = kept*3 (KILL TW:523, sweep_at == 1234)",
      "    head.sweep_at = UInt32(kept * 2 > TRIE_SWEEP_MIN ? kept * 2 : TRIE_SWEEP_MIN)\n", "    head.sweep_at = UInt32(kept * 3 > TRIE_SWEEP_MIN ? kept * 3 : TRIE_SWEEP_MIN)\n"),
    m("TR1-S6 the chunk list keeps empty chunks (KILL TW:522, length(cs2) == 6)",
      "        if c.live == 0\n            prev.next = next\n", "        if false\n            prev.next = next\n"),
    m("TR1-S7 the nodes of a dropped chunk do not reach free_ids (KILL TW:524, 8 + 407)",
      "push!(tr.free_ids, id)", "nothing"),
    # ---- prune / clear / walk / stat
    m("TR1-P1 prune_node: TN_PINNED does not stop it (KILL TW:563-575, the fl loop)",
      "(n.parent != 0 && (n.flags & (TN_PRIMARY | TN_SECONDARY | TN_PINNED)) == 0) || break", "(n.parent != 0 && (n.flags & (TN_PRIMARY | TN_SECONDARY)) == 0) || break"),
    m("TR1-P2 prune_node: the root is pruned too (KILL TW:586, prune_node(tr, 1))",
      "(n.parent != 0 && (n.flags & (TN_PRIMARY", "(true && (n.flags & (TN_PRIMARY"),
    m("TR1-P3 prune_trie: TN_SECONDARY and TN_PINNED do not stop it (KILL TW:632: root-a-{b SECONDARY, c PINNED}: the leaves b and c are kept, node_count 4)",
      "        while n != root &&\n              (tr.nodes[n].flags & (TN_PRIMARY | TN_SECONDARY | TN_PINNED)) == 0\n", "        while n != root && (tr.nodes[n].flags & TN_PRIMARY) == 0\n"),
    m("TR1-P4 prune_error: prunes nothing (KILL TW:594 and TW:1023, the error key stays)",
      "    prune_node(tr, follow_node(tr, nid, TRIE_ERROR_VAL, true))\n", "    follow_node(tr, nid, TRIE_ERROR_VAL, true)\n"),
    m("TR1-P5 clear_node CN_DEALLOC does not lower node_count (KILL TW:561, node_count == 1 after prune_node)",
      "            tr.node_count -= 1\n", "            nothing\n"),
    m("TR1-D1 empty_trie keeps the discard flags (KILL TW life rows, `tr.flags == LK.TRIE_ISSET`)",
      "        tr.flags &= ~(TRIE_DISCARDABLE | TRIE_DISCARDED)\n", "        nothing\n"),
    m("TR1-D2 clear_node CN_ALL frees every chunked node (EQUIVALENT: clear_nodes resets chunks, free_ids and the node arena right after)",
      "            if (flags & CN_ALL) == 0 || (n.flags & TN_CHUNKED) == 0\n", "            if true\n",
      eq="src/pl-trie.jl:772 (clear_node): clear_nodes (:193-207) calls clear_node(CN_ALL) (:194), then free_node_chunks (:196), `resize!(tr.nodes, 1)` (:198) and `empty!(tr.free_ids)` (:199); the frees the mutant adds (free_trie_node, and a sweep it may trigger) only touch the chunk list, free_ids and node fields that those lines drop, and the walk uses the `children` captured before the free: nothing observable is left"),
    m("TR1-D3 empty_trie keeps value_count (KILL TW:683 value_count == 0)",
      "        tr.value_count = 0\n", "        nothing\n"),
    m("TR1-D4 trie_single_value_node: value_count is not asked (KILL TW:639/643)",
      "    tr.value_count != 1 && return 0\n", "    nothing\n"),
    # TR1-D5 is a DECLARED HANG (audit D-0524 item 1, D-0541 item 4). (a) the kill row is TW:651 (_tr_prune_rows, a block child is not a single child);
    # (b) the spin site is src/pl-trie.jl:367 `while tr.nodes[n].value == 0` in trie_single_value_node, called straight from test_trie_swipl.jl:709
    # (`@test LK.trie_single_value_node(tr2) == 0`): with the guard gone the block code `bid<<1` reads as a single child, `single_child(c)` is node 1,
    # and the walk goes root to root for ever inside ONE Julia call (no allocation, no yield: a row cannot interrupt it). (c) PROGRESS, not a wall
    # limit (the unmutated TW needs 632 s locally, compile included): the unmutated reference prints the testset summary of the prune rows about
    # 35 s after load; the mutant produces no such line by 3 x 35 s, and the SIGQUIT stack at 200 s is ONE frame, constant (trie_single_value_node
    # at :367 under _tr_prune_rows at TW:709, no Prolog engine): evidence/TAB1/timeout_d5_handoff.md, timeout_d5_d5_stack.txt, timeout_d5_ref_tw_timing.txt.
    # (d) the engine stop (a bounded walk that throws) is NOT adopted: fidelity, the pin's loop is the plain `while`.
    m("TR1-D5 trie_single_value_node: a block child is followed (KILL TW:651; HANG at src/pl-trie.jl:367, declared: see the comment above)",
      "        is_single_child(c) || return 0\n", "        nothing\n", hang=True),
    m("TR1-W1 map_trie_node: the stop value is ignored (KILL TW:714)",
      "        rc === nothing || return rc\n        children == 0 && return nothing\n", "        children == 0 && return nothing\n"),
    m("TR1-W2 is_ground_trie_node: an attvar key is ground (KILL TW:726, !is_ground(t1))",
      "        (tx == TAGEX_VAR || tx == TAGEX_TRIE_ATTVAR) && return false\n", "        tx == TAGEX_VAR && return false\n"),
    m("TR1-T1 stat_node: a chunked node counted at 40 as well (KILL TW:752, 760)",
      "(n.flags & TN_CHUNKED) == 0 && (stats.bytes += SIZEOF_TRIE_NODE)", "(n.flags & TN_CHUNKED) != 0 && (stats.bytes += SIZEOF_TRIE_NODE)"),
    m("TR1-T2 stat_trie: the chunk bytes only for a CONCURRENT trie (KILL TW:752 and TW:764)",
      "    if (tr.flags & TRIE_CONCURRENT) == 0\n        c = tr.chunks\n", "    if (tr.flags & TRIE_CONCURRENT) != 0\n        c = tr.chunks\n"),
    m("TR1-T3 stat_node: every value counted (KILL TW:749-751, values == 1)",
      "n.value != 0 && (n.flags & TN_PRIMARY) != 0 && (stats.values += 1)", "n.value != 0 && (stats.values += 1)"),
    m("TR1-T4 trie_table_size: the root is not a node (KILL TW:744, 753)",
      "return SIZEOF_TRIE + tr.node_count * SIZEOF_TRIE_NODE", "return SIZEOF_TRIE + (tr.node_count - 1) * SIZEOF_TRIE_NODE"),
    # ---- the indirect table (TW _tr_indirect_rows 774-818, _tr_wildcard_rows 820-847)
    m("TR1-I1 a float handle is tagged STRING (KILL TW:778)",
      "    k == NUM_FLOAT && return TAGEX_INDIRECT_FLOAT\n", "    k == NUM_FLOAT && return TAGEX_INDIRECT_STRING\n"),
    m("TR1-I2 intern_indirect: a keyed value is never found again (KILL TW:779, one handle for equal values)",
      "            for i in b\n                gnd_equal(tab.values[i], v) && return consTagged(i, indirect_tagex(v))\n",
      "            for i in b\n                false && return consTagged(i, indirect_tagex(v))\n"),
    m("TR1-W2b the tab.wild loop of a keyed value (EQUIVALENT by the key invariant: a keyed value never equals a wildcard one)",
      "        for i in tab.wild\n            gnd_equal(tab.values[i], v) && return consTagged(i, indirect_tagex(v))\n",
      "        for i in Int[]\n            gnd_equal(tab.values[i], v) && return consTagged(i, indirect_tagex(v))\n",
      eq="src/pl-trie.jl:952 (intern_indirect, the branch of a value with a key, :939): `gnd_value_key` (src/default_term.jl:54, contract :44-52) agrees with gnd_equal, so a value with a key is never gnd_equal to a keyless (wildcard) one and the loop over tab.wild finds nothing for it"),
    m("TR1-I3 a wildcard value is not found again (KILL TW:827-828)",
      "            gnd_equal(tab.values[i], v) &&\n                return consTagged(i, indirect_tagex(tab.values[i]))\n",
      "            false &&\n                return consTagged(i, indirect_tagex(tab.values[i]))\n"),
    m("TR1-I4 trie_intern_indirect without add makes a table (KILL TW:807, tr.indirects === nothing)",
      "        add || return word(0)\n        tab = new_indirect_table(T)\n", "        tab = new_indirect_table(T)\n"),
    # ---- lookup (TW _tr_lookup_*_rows 849-1080, _tr_insert_flat_rows 1082, _tr_lookup_flat_rows 1137)
    m("TR1-L1 the cyclic check, bounded: an acyclic term of depth 1000 is flagged (KILL TW:1038, rc2 == 1; the cyclic term still stops at 5000 compounds: no hang)",
      "                if compounds == 1000 && add && !is_acyclic_cells(ld, l)\n", "                if (compounds == 1000 && add && is_acyclic_cells(ld, l)) || compounds == 5000\n"),
    m("TR1-X1 the cyclic check at depth 1001 (EQUIVALENT: an infinite term reaches 1001 too, a finite one is acyclic at either depth: same rc, same pruned trie; the bounded kill of the check is TR1-L1)",
      "                if compounds == 1000 && add && !is_acyclic_cells(ld, l)\n", "                if compounds == 1001 && add && !is_acyclic_cells(ld, l)\n",
      eq="src/pl-trie.jl:1094 (trie_lookup_abstract): the test only moves the depth at which the walk looks; a cyclic term is infinite, so it passes 1001 as well, and prune_error (:1096) removes every node added, an acyclic term is acyclic at either depth: same rc, same trie. TW:1021-1023 (the cyclic rows) cannot see the depth; the kill of the check itself is the bounded TR1-L1"),
    m("TR1-L2 the abstraction budget is not spent (KILL TW:997, h(a) below g is abstracted at (1,1))",
      "                aleft != typemax(Int) && (aleft -= 1)\n", "                nothing\n"),
    m("TR1-L3 the budget is renewed below from_depth (KILL TW:997)",
      "        if compounds == from_depth\n", "        if compounds >= from_depth\n"),
    m("TR1-L4 an abstracted term answers rc 1 (KILL TW:982, 988, 997, 1001)",
      "                rc = TRIE_ABSTRACTED\n", "                rc = 1\n"),
    m("TR1-L5 every variable key is V1 (KILL TW:943, 959: f(P,Q,Q) is [V1,V2,V2])",
      "            w2 = consTagged(var_number, TAGEX_VAR)\n", "            w2 = consTagged(1, TAGEX_VAR)\n"),
    m("TR1-L6 the first variable is not restored (KILL TW:946, 965: ld.gstack[vars[1]] == 0)",
      "    i = v0 + 1 ", "    i = v0 + 2 "),
    m("TR1-L7 a POP key at the top (KILL TW:867 and TW:949: no trailing key)",
      "            if compounds > 0\n                node = follow_node(tr, node, TRIE_KEY_POP(popn), add)\n", "            if compounds >= 0\n                node = follow_node(tr, node, TRIE_KEY_POP(popn), add)\n"),
    m("TR1-L8 a lookup without add interns (KILL TW:920-921, length(tr.indirects.values) == 4)",
      "            i = trie_intern_indirect(tr, _indirect_value(ld, w), add)\n", "            i = trie_intern_indirect(tr, _indirect_value(ld, w), true)\n"),
    m("TR1-F1 trie_lookup_flat: a shared variable is a new one (KILL TW:1170, length(vars) == 1)",
      "                    if vars[j] == p\n", "                    if false\n"),
    m("TR1-F2 trie_lookup_flat: not-flat answers 0 (KILL TW:1179)",
      "                return (TRIE_LOOKUP_NOT_FLAT, start, 0)\n", "                return (0, start, 0)\n"),
    m("TR1-F3 trie_lookup_flat: the functor step is skipped (KILL TW:1154-1155, 1166)",
      "        if arity > 0\n            fw = lookupFunctorDef", "        if false\n            fw = lookupFunctorDef"),
    m("TR1-F4 trie_insert_flat: the 16th argument is not kept (KILL TW:1127, a BoundsError in the second pass)",
      "        i <= FLAT_MAX_ARGS && push!(args, (p, aw))\n", "        i < FLAT_MAX_ARGS && push!(args, (p, aw))\n"),
    m("TR1-F5 trie_insert_flat: 32 variables are not flat (KILL TW:1123)",
      "            (nvars += 1) > FLAT_MAX_VARS && return (TRIE_LOOKUP_NOT_FLAT, 0)\n", "            (nvars += 1) >= FLAT_MAX_VARS && return (TRIE_LOOKUP_NOT_FLAT, 0)\n"),
    m("TR1-F6 trie_insert_flat: the cells are not restored (KILL TW _tr_insert_flat_rows, the raw-cell row after the lookup row: the argument cells are plain unbound variables again. The lookup row after it does not see the mutant: a numbered cell is the key V1 it stands for, the same path)",
      "    for p in vars\n        ld.gstack[p] = word(0)\n    end\n", "    for p in vars\n        nothing\n    end\n"),
    # ---- blobs and errors (TW _tr_blob_rows 1196, _tr_error_rows 1236)
    m("TR1-B1 trie_symbol makes a new blob each time (KILL TW:1203)",
      "    tr.symbol != 0 && return tr.symbol\n", "    nothing\n"),
    m("TR1-B2 symbol_trie names a destroyed trie (KILL TW:1224)",
      "    (t !== nothing && t.magic == TRIE_MAGIC) && return t\n", "    t !== nothing && return t\n"),
    m("TR1-B3 get_trie: a destroyed trie is a type error (KILL TW:1227; TP t4 at TP:211)",
      "        PL_error(ld, ERR_EXISTENCE, mk_sym(T, :trie), t)\n", "        PL_type_error(ld, \"trie\", t)\n"),
    m("TR1-B4 trie_error: attvar and cyclic swapped (KILL TW:1242, 1244 and TW:1028)",
      "        return PL_type_error(ld, \"free_of_attvar\", culprit)\n", "        return PL_type_error(ld, \"acyclic_term\", culprit)\n"),
    m("TR1-B5 trie_error: cyclic reports free_of_attvar (KILL TW:1244, TW:1028, TP:321-325 t70)",
      "        return PL_type_error(ld, \"acyclic_term\", culprit)\n", "        return PL_type_error(ld, \"free_of_attvar\", culprit)\n"),
    m("TR1-B6 the trie blob has another name (KILL TP:t76, test/core_lang/test_trie_preds_swipl.jl:261: blob(T, Type) answers `trie`, swipl's)",
      "const trie_blob = PL_blob_t(PL_BLOB_NOCOPY, \"trie\")", "const trie_blob = PL_blob_t(PL_BLOB_NOCOPY, \"trie2\")"),
    # ---- boot path (judged only by tools/mutate_ci.py one)
    m("TR1-N1 BOOT PATH initTries! registers nothing (KILL CR: the unbooted-database rank testset, `treg !== nothing`; TP:206 runs on the booted template and cannot see it)",
      "    PL_register_blob_type(atoms, trie_blob)\n    return nothing\n", "    return nothing\n", targets=[CR]),
    m("TR1-N2 BOOT PATH the database does not call initTries! (KILL CR: the unbooted-database rank testset, `treg !== nothing`; TP:206 runs on the booted template and cannot see it)",
      "initTries!(atoms)", "nothing", file=SETUP, targets=[CR]),
    m("TR1-N3 trie_term/2 is not registered (KILL TP:262 t47, TB: the foreign-row count)",
      "    PL_extension(\"trie_term\", 2, pl_trie_term2_va, PL_FA_VARARGS),\n", "", targets=TARGETS),
    m("TR1-N4 trie_update/3 is not registered (KILL TP:231-245 t30-t34, TB)",
      "    PL_extension(\"trie_update\", 3, pl_trie_update3_va, PL_FA_VARARGS),\n", "", targets=TARGETS),
    # ---- values and the predicates (TP 166-340; the rows are swipl's answers; TW _tr_value_rows 1264)
    m("TR1-V1 trie_insert: a first value makes a SET (ISMAP/ISSET swapped) (KILL TP:213 t14, TP:220 t16, TP:221 t17)",
      "        tr.flags |= Value != 0 ? TRIE_ISMAP : TRIE_ISSET\n", "        tr.flags |= Value != 0 ? TRIE_ISSET : TRIE_ISMAP\n"),
    m("TR1-V2 trie_insert: the permission_error(insert, trie) is dropped (KILL TP:213 t14, TP:221 t17)",
      "        PL_error(ld, \"\", 0, \"\", ERR_PERMISSION, mk_sym(T, :insert), mk_sym(T, :trie), Trie)\n        return (false, 0)\n", "        nothing\n"),
    m("TR1-V2b a value into a map trie never trips the guard (KILL TP:221 t17 insert/2 into a map)",
      "        (Value == 0 && (tr.flags & TRIE_ISSET) == 0)\n", "        false\n"),
    m("TR1-V2c a value into a set trie never trips the guard (KILL TP:213 t14 insert/3 into a set)",
      "    elseif (Value != 0 && (tr.flags & TRIE_ISMAP) == 0) ||\n", "    elseif false ||\n"),
    m("TR1-V3 trie_insert update: the old record is not released (KILL TW:1276 and TW:1279: tr.free_records == [1] after the update, [1, 2] after the third)",
      "                n.flags |= TN_PRIMARY\n                release_value(tr, old)\n", "                n.flags |= TN_PRIMARY\n"),
    m("TR1-V4 trie_insert: value_count is not counted (KILL TW:1273, 1276, 1279: tr.value_count == 1)",
      "    tr.value_count += 1\n    trie_discard_clause(tr)\n    return (true, nid)\n", "    trie_discard_clause(tr)\n    return (true, nid)\n"),
    m("TR1-V5 trie_insert: a new value does not get TN_PRIMARY (KILL TP:250-252 t38-t40: deleting a key below a value node prunes the value node)",
      "    n.value = val\n    n.flags |= TN_PRIMARY\n    tr.value_count += 1\n", "    n.value = val\n    tr.value_count += 1\n"),
    m("TR1-V6 trie_new/1 without TRIE_CONCURRENT (DEFERRED KILL: TW cannot call pl_trie_new1_va)",
      "    tr.flags |= TRIE_CONCURRENT\n    return unify_trie(gd, ld, PL__t0, tr) ? FTRUE : FFALSE\n", "    return unify_trie(gd, ld, PL__t0, tr) ? FTRUE : FFALSE\n",
      eq="DEFERRED KILL: owner TR2 or a TR1 row that sets ld.GD: the only observable of TRIE_CONCURRENT is allocation (alloc_trie_node :621, retire_block :385), read through gd.tries[end].flags or stat_trie; no TP row sees it, and TW cannot call pl_trie_new1_va (src/pl-trie.jl:1901) because `_query_gd(ld)` needs ld.GD set by a running query (src/pl-comp.jl:4161)"),
    m("TR1-V7 trie_insert: a rc other than 1 does not stop (KILL TP:322-325 t70, a BoundsError on node 0)",
      "    rc == 1 || return (trie_error(ld, rc, Key), 0)\n", "    true || return (trie_error(ld, rc, Key), 0)\n"),
    m("TR1-V8 trie_insert: an equal value is a permission error (KILL TP:220 t16, TP:233-235 t25)",
      "            if !equal_value(tr, n.value, val)\n                PL_error(\n", "            if equal_value(tr, n.value, val)\n                PL_error(\n"),
    m("TR1-V9 trie_update: an equal value is replaced (KILL TP:239 t32, TP:237 t30)",
      "            if !equal_value(tr, n.value, val)\n                old = n.value\n", "            if equal_value(tr, n.value, val)\n                old = n.value\n"),
    m("TR1-V10 trie_insert: an existing key is inserted again (KILL TP:220 t16, TP:222 t17: the second insert fails)",
      "            return (false, nid)\n", "            return (true, nid)\n"),
    m("TR1-V11 trie_delete/3 does not prune (DEFERRED KILL: no row reads the arena after a delete)",
      "            trie_delete(tr, nid, true)\n", "            trie_delete(tr, nid, false)\n",
      eq="DEFERRED KILL: owner TR2 ($trie_property / trie_gen) or a TW row that sets ld.GD: t69/t74 (TP:319-320) only count answers, an unpruned node has value 0 and `v != 0` (src/pl-trie.jl:2033) hides it, reinserting works the same; the call is in pl_trie_delete3_va (:1999, :2011)"),
    # TR1-V12 was declared a deferred kill (src/pl-trie.jl:2033 `v != 0` matters only for a node with value 0); the battery of 61d5e365 (run 43007822749)
    # REFUTED the claim: a program row of test_trie_preds_swipl.jl:174 (the .out answers) is an Error During Test under the mutant. Listed as a kill.
    m("TR1-V12 trie_lookup/3: an inner node answers (KILL TP:174, the program rows; found by the battery of 61d5e365)",
      "        return (v != 0 && unify_value(ld, tr, A3, v)) ? FTRUE : FFALSE\n", "        return unify_value(ld, tr, A3, v) ? FTRUE : FFALSE\n"),
    m("TR1-V13 trie_node_handle shifts 31 (KILL TP:262 t47, TP:263 t48)",
      "(tr.serial << 32) | nid", "(tr.serial << 31) | nid"),
    m("TR1-V14 trie_term/2: the node id is not masked (KILL TP:262 t47)",
      "    nid = h & 0xffffffff\n", "    nid = h\n"),
    m("TR1-V15 trie_term/2: a node id past the arena is not refused (KILL TP:373 kd6, a BoundsError instead of existence_error)",
      "!(1 <= nid <= length(tr.nodes))", "!(0 <= nid)"),
    m("TR1-K3 trie_term/2: a destroyed trie is not refused by its magic (EQUIVALENT: the destroyed trie's arena is reset to the root, a handle fails the range test)",
      "tr === nothing || tr.magic != TRIE_MAGIC || ", "tr === nothing || ",
      eq="src/pl-trie.jl:2053 (pl_trie_term2_va): trie_destroy empties the trie (trie_empty -> empty_trie :216-223 -> clear_nodes :193-207, `resize!(tr.nodes, 1)` at :198; no TR1 code raises tr.references, TB1's), so the handle of a destroyed trie (nid >= 2: trie_insert/4 never hands out the root) fails `1 <= nid <= length(tr.nodes)`; row kd7 (test/core_lang/test_trie_preds_swipl.jl:374) runs it"),
    m("TR1-V16 trie_destroy/1 does not mark (KILL TP:211 t4: the second destroy raises existence_error; TP t3)",
      "    tr.magic = TRIE_CMAGIC\n    trie_empty(tr)\n    return FTRUE\n", "    trie_empty(tr)\n    return FTRUE\n"),
    m("TR1-V17 trie_destroy (the function) does not mark (KILL TW:1224 and TW life rows tr2.magic == TRIE_CMAGIC)",
      "    tr.magic = TRIE_CMAGIC\n    trie_empty(tr)\n    free_lingering_blocks(tr)\n", "    trie_empty(tr)\n    free_lingering_blocks(tr)\n"),
    m("TR1-V18 is_trie/1: a destroyed trie is a trie (KILL TP:208, t3 `no`)",
      "    return (tr !== nothing && tr.magic == TRIE_MAGIC) ? FTRUE : FFALSE\n", "    return tr !== nothing ? FTRUE : FFALSE\n"),
    m("TR1-V19 $trie_insert_abstract: from depth 0 (KILL TP:277 t56)",
      "trie_insert(gd, ld, A1, A3, 0, false, size_abstract(1, sz))", "trie_insert(gd, ld, A1, A3, 0, false, size_abstract(0, sz))"),
    m("TR1-V20 a set's value is word 0 (KILL TP:225 t18: the second insert no longer fails; TP:248 t36)",
      "    return _atom_word!(ld, mk_reserved_symbol(T, :trienode))\n", "    return UInt64(0)\n"),
    m("TR1-V21 equal_value: a record is compared with anything (KILL TW:1279: the update of a record by an atom is no equal value, the record is released)",
      "    if isRecord(v1) && isRecord(v2)\n", "    if isRecord(v1) || isRecord(v2)\n"),
    m("TR1-V22 unify_value: the reserved value is read as a plain atom (EQUIVALENT: `_atom_value` reads the symbol recorded for ATOM_trienode, the reserved symbol itself; probed, booted and unbooted)",
      "        v = if value == ATOM_trienode\n", "        v = if false\n",
      eq="the else branch reads the symbol recorded for ATOM_trienode, the reserved symbol itself (src/pl-atom.jl:2317-2326, src/pl-setup.jl:263, src/pl-trie.jl:1577)"),
    # ---- unify_key (TP t41-t52, t71-t73; TW _tr_unify_rows 1283)
    m("TR1-U1 unify_key: a repeated variable is not unified (KILL TW:1296: f(X, X) against f(1, 2) must answer (false, 0))",
      "                unify_ptrs_cells(ld, p, st.vars[index]) || return BOOLEX_FALSE\n", "                unify_ptrs_cells(ld, p, st.vars[index])\n"),
    m("TR1-U2 unify_key: a POP key pops one too many (KILL TP:263 t48, TP:264 t50)",
      "        resize!(st.astack, length(st.astack) - popn)\n", "        resize!(st.astack, length(st.astack) - popn + 1)\n"),
    m("TR1-U3 unify_key: an indirect key is not compared (KILL TW:1301: the key of g(1.5) against g(2.5) must answer (false, 0))",
      "            _unify_const_loc(ld, p, v) || return BOOLEX_FALSE\n", "            _unify_const_loc(ld, p, v)\n"),
    m("TR1-U4 unify_key: an atom key against an attributed variable is no binding (KILL TP:326-328 t71-t73)",
      "            if isVar(w) || isAttVar(w)\n                bindConst(ld, pp, key)\n", "            if isVar(w)\n                bindConst(ld, pp, key)\n"),
]
