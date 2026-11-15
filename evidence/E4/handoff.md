# E4 handoff (agent 1 cut at 150k by the context hook, 2026-11-15)

Tree: ~/code/lk-fixa, branch wip/e4-trie at 87a88328 (= origin/main), NOTHING COMMITTED. Daemon: lane-1 warm daemon running for this tree
(unit logickernel-warm-cc8bf664, SECOND beside lk-tbland2's), idle exit after 3600 s.

Uncommitted in the tree:
- test/core_lang/test_trie_gen_swipl.pl: rows t39-t47 appended (E4).
- test/core_lang/test_trie_gen_swipl.out: regenerated from the pin swipl (two identical runs; old lines byte-identical).
- test/core_lang/test_trie_gen_swipl.jl: testset "E4 kill rows" (t39,t40,t42,t43,t44,t46,t47) and an E4 white-box testset
  (references == 1 during trie_gen, node_count kept after trie_destroy under it, references 0 and node_count 1 after the cut).
- tools/mutants/E4.py: header + TARGETS (trie files + tabling files on main), MUTANTS still empty.
- evidence/E4/before_on_main.md: pin answers, measured cause, BEFORE numbers.

MEASURED CAUSE: trie_gen_raw never takes a reference on the trie (the kernel comments call acquire_trie/release_trie O_PLMT; at
18168e62 pl-trie.h:231-234 they are unconditional). With references 0, trie_delete prunes; delete_child(compact=true) -> replace_block
compacts the enumerated parent's block under the CH_ENUM child_iter (position-based), which then runs past the new block's count.
Also trie_destroy under an enumeration empties the nodes (BoundsError at trie_gen_raw :2965 in t47).

FIX TO APPLY (src/pl-trie.jl, faithful to pl-trie.h:231-234, pl-trie.c trie_gen_raw :4087 `acquire_trie(trie)`, clear_trie_state
:3439 `release_trie(state->trie)`):
1. after trie_clean: `# PORT: pl-trie.h acquire_trie` (`tr.references += 1`, DIVERGES no ATOMIC_INC, single thread) and
   `# PORT: pl-trie.h release_trie` (`tr.references -= 1; tr.references == 0 && trie_clean(gd, tr)`, database an argument).
2. trie_gen_raw FRG_FIRST_CALL: `acquire_trie(trf)` after `trf.gen_call += 1`, before init_trie_state! (upstream order).
3. clear_trie_state!(gd, pool, k): `release_trie(gd, st.tr)` inside the `st.tr !== nothing` branch (idempotent: once); every caller in
   trie_gen_raw passes `_query_gd(ld)` (all callers are foreign predicates inside a query).
4. remove the false "no acquire_trie/release_trie (O_PLMT, owner TH1)" from the comments at :2320 and :2906; stat_trie's comment
   (:1493) says the same: leave its code, correct the comment or report.
5. manifest entries in test/static_analysis_manifest.jl for acquire_trie/release_trie if new methods need them.
Then: mutants (E4-A1 drop the acquire; E4-R1 drop the release; E4-R2 release without trie_clean -> white box), each hand-run once on
the target file; rows on three types; existing trie files + tabling files on main (the TARGETS list); fmt, check, type discipline;
per-row kernel numbers BEFORE (t47 run separately) into before_on_main.md; commits on wip/e4-trie.
