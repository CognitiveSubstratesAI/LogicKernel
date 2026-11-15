# E4 BEFORE proof on main 87a88328 (2026-11-15, lane 1 = ~/code/lk-fixa, branch wip/e4-trie, src/ unchanged = main)

## Pin swipl 10.1.20 (~/.local/bin/swipl, md5 443d05d24707a84eaaf73d749270d241), two runs IDENTICAL (cmp), rows t39-t47 of
## test/core_lang/test_trie_gen_swipl.pl (the old rows ok..t38 byte-identical to the committed .out)
t39=[0 x 40]                      (N=1..40: nothing remains after deleting each answer while enumerated)
t40=[k(1)..k(9)]-0-node_count(10)-value_count(0)   (NO pruning under the enumeration: 10 nodes stay)
t41=0-18-[1-1,1-3,1-5,2-1,...,6-5]  (nested f(g(I),h(J)) + f(g(I)): 0 left; even J deleted: 18 deleted, the 18 odd left)
t42=[1,3,5,7,9]-[1,3,5,7,9]       (next sibling deleted)
t43=[1..10]-[10]                  (previous sibling deleted)
t44=[1..12]-[1,3,5,7,9,11]        (every second deleted)
t45=[1..10]-[b-1..b-10]           (pruning query f(a,X), each deleted)
t46=[node_count(1) x 3]           (reference released after once/1, a throw, a complete findall: a later delete prunes)
t47=[k(1)..k(6)]                  (trie_destroy under the enumeration: the enumeration goes on)

## Kernel on main, reference type, MEASURED by a hand-driven trie_gen/3 (scratch snippet diag.jl via tools/warm.sh send)
tr.references = 0 during the enumeration (trie_gen_raw never acquires: src/pl-trie.jl:2320/:2906 say "no acquire_trie/release_trie
(O_PLMT, owner TH1)", but pl-trie.h:231-234 @18168e62 defines them unconditionally, ATOMIC_INC/ATOMIC_DEC + trie_clean).
So trie_delete (:1815 `prune && tr.references == 0`) PRUNES under the enumeration; delete_child(compact=true) -> replace_block moves
the live children into a NEW compacted block once dead*2 > count, while the CH_ENUM branch's child_iter keeps its old position.
N=5:  deletes 1,2 -> block id=3 count=5 dead=2; delete 3 -> block id=4 count=2 (compacted); answer 4; then iter.pos past count -> end. value_count left 1
N=6:  compaction at the 4th delete (dead 4*2>6) -> block id=4 count=2; answer 5; end. left 1
N=8:  compaction at the 5th delete -> block id=4 count=3; answer 6; end. left 2
N=4:  dead 2*2>4 false; dead 3 -> single child; all 4 answered (0 left), matching the 0 for N<=4.
The block has index_bits=0 for N<=8: the earlier "hash node" reading was wrong; the cause is the COMPACTION, not hashing.

## Kernel test run on main: tools/warm.sh file test/core_lang/test_trie_gen_swipl.jl (all three types), 12m24s
225 passed, 6 failed, 15 errored. Per type (reference / alt / alt_interned identical): 75 pass, 2 fail, 5 error.
The 5 errors per type: a BoundsError (node index 5 into a 1-element nodes vector, trie_gen_raw src/pl-trie.jl:2965) on t47 (trie_destroy
under the enumeration empties the nodes the enumeration still walks) aborts the differential, kill, E4-kill, replay and live-state testsets.
The 2 fails per type: the E4 white-box row (:326 references == 1, :329 node_count kept after destroy).
Per-row kernel numbers for t39-t46 on main (the reported 0,0,0,0,1,1,2,2,3,3 N=1..10, 6 at 16, 18 at 40) still to be printed per row
(the t47 error hides them in the differential): the next agent prints them with t47 run separately.

## AFTER the fix (src/pl-trie.jl acquire_trie/release_trie; lane 1, 2026-11-15)
tools/warm.sh file test/core_lang/test_trie_gen_swipl.jl: 600 pass / 600 (reference 200, alt 200, alt_interned 200), 0 fail, 0 error,
0 SKIP/Warning lines. Every row t39-t47 green on all three types (before: 75 pass, 2 fail, 5 error per type).
Other files, all three types, exit 0, 0 SKIP/Warning/Test Failed/Error During lines: test_trie_swipl 1110, test_trie_preds_swipl 552,
test_trie_attvar_swipl 147, test_trie_compiled_swipl 306, test_tabling_answers_swipl 423, test_tabling_min_swipl 456,
test_tabling_tb4rows_swipl 249, test_tabling_tb4rows2_swipl 258, test_tabling_variant_swipl 324, test_tabling_wfs_swipl 207,
test_tabling_worklist_swipl 249, test_type_discipline 45.
tools/warm.sh check: PASS (965 s) after fmt of the test file, `tools/warm.sh inventory` (two new PORT headers), manifest entries.
Mutants (tools/mutate.sh run-in-tree, reference type, target = test_trie_gen_swipl.jl, baseline before and after green): 4 of 4 caught
  E4-A1 (no acquire)             caught: Error During Test, differential testset (test_trie_gen_swipl.jl:165)
  E4-R1 (no release)             caught: Test Failed, differential testset :180 (t46 node_count)
  E4-R2 (release, no trie_clean) caught: Test Failed, white box :334 (node_count == 1 after the release)
  E4-D1 (empty_trie ignores references) caught: Error During Test, differential testset :165 (t47)
Not decided here: stat_trie upstream does acquire_trie/release_trie around its walk (pl-trie.c :2307-2313); the kernel's stat_trie leaves
them out (comment reworded, code unchanged): REPORTED.
