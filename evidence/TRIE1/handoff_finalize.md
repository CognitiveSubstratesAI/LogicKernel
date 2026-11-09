# TR1 mutation list: FINALIZE, state at the 150k cap (agent 1 of the finalize step)

Lane clone ~/code/lk-tr1, branch wip/tr1. Never pushed. No Julia run.

## Done (commits on wip/tr1)
- 47e71d7f: `git mv evidence/TRIE1/TRIE1_draft.py tools/mutants/TRIE1.py` (CONTENT NOT YET EDITED beyond the move) + TW rows for TR1-C16 and TR1-C6.
- 0a522344: TW rows TR1-S2, TR1-P3, TR1-V4, TR1-V3 (new `_tr_value_rows`).
- 7ddb3509: TW rows TR1-V21 (third update in `_tr_value_rows`), TR1-U1 (new `_tr_unify_rows`).
- 4c4ba736: TW rows TR1-U3 (float key in `_tr_unify_rows`).
All rows written edit-only from the code, NOT RUN: the next gate runs test_trie_swipl.jl on the three term types.

## Verified (python3 -I count script, scratchpad chk.py): 112 mutants, every `old` occurs exactly once in its file, new != old, no duplicate id, 0 failures (at 4c4ba736 for src; the src files were not touched).
The throwaway script is at /tmp/claude-1000/-home-shivaji1012-code-CognitiveSubstratesAI/b1bc52d9-44dc-428a-a9bb-10bf805f9033/scratchpad/chk.py (usage: python3 -I chk.py tools/mutants/TRIE1.py; chdir is done inside). Risky ones checked by reading the code: A9 (src/pl-trie.jl:686 only `n.key = 0`), C15 (:260), L6 (:1120), P1/P2 (:807 vs prune_trie :847), V8/V9 (1870/1859 context lines make them unique), V3/V4/V5 (the 16- and 4-space variants are distinct).

## STILL TO DO in tools/mutants/TRIE1.py (the next agent; the cap hook blocked Edit outside evidence/)
1. LINE REMAP of every `TW:NNN` in ids/eq: the draft's TW line numbers are of ba322bbc. Test lines were inserted: 9 lines after old 260, 9 after old 331, S2 row (11 lines) after the old `@test length(free_listed) == 1085 ...` (old line ~515), P3 row (9 lines) after old line 590, the value/unify functions at the end of file (after old 1221). Best: parse `git diff -U0 ba322bbc HEAD -- test/core_lang/test_trie_swipl.jl` hunks and remap every TW:n (also `TW:a-b`, `TW:a/b`). TP lines are unchanged (TP file not edited). The old file is at the scratchpad TW_old.jl; refs2.py there prints the cited line text per mutant (reads TW_old.jl; run `python3 -I refs2.py TR1-xx ...`).
2. NEW KILLS to cite (current numbering: grep them): TR1-C6 -> the "5 children, 3 deleted" row in _tr_compaction_rows; TR1-C16 -> the keys 36/73 row in _tr_children_rows (after the child_hash `.< 64` line); TR1-S2 -> last row of _tr_sweep_rows ("3000 leaves", nfree 1024, node_count 1977); TR1-P3 -> the root-a-{b SECONDARY, c PINNED} row in _tr_prune_rows; TR1-V3, TR1-V4, TR1-V21 -> _tr_value_rows; TR1-U1, TR1-U3 -> _tr_unify_rows. Remove the `eq="DEFERRED KILL..."` of C6, S2, P3, V3, V4 and the "(NO ROW ...)" text from their ids. Rewrite C15 id: KILL TW:260 (child_hash of keys 1 and 12345 at 6 bits is 86 and 86>=64 under the mutant, computed by python) and the 9-key index (slots past 32: BoundsError). C16: the old claim ("colliding-hash row") was WRONG (that row never wraps: key 1016 collides with 10 at slot 11); the new row kills it.
3. DEFERRED KILL (keep `equivalent="DEFERRED KILL: owner ..."`, list in the hand-back as candidates for new rows):
   - TR1-V6 (trie_new/1 TRIE_CONCURRENT): predicate level; TW cannot call pl_trie_new1_va (`_query_gd(ld)` needs ld.GD set by a running query, src/pl-comp.jl:4161).
   - TR1-V11 (trie_delete/3 does not prune) and TR1-V12 (trie_lookup/3 inner node answers): NO TP row reads the arena after a delete (t69/t74 only count answers: an unpruned node has value 0 and `v != 0` hides it; reinserting works the same; a complete term key is never an inner node). V12 alone is unreachable while deletes prune (a node with value 0 exists only after an unpruned delete). Owner: TR2 ($trie_property / trie_gen) or a TW row that gets ld.GD (the pl_ foreign is `pl_trie_delete3_va` src/pl-trie.jl:1999).
   - TR1-B6 (blob named "trie2"): nothing reads the type name (the TP scrub is by identity, `T == Tr`, test_trie_preds_swipl.pl:24); a TP row `blob(T, trie)` from swipl would kill it (needs a .pl/.out regeneration by the oracle).
   - TR1-V18: kill is TP:208 (t3 `no`) only; drop "probable".
4. EQUIVALENTS, real file:line (src/pl-trie.jl at 4c4ba736, unchanged since ba322bbc):
   - A4: :644 `bytes > TRIE_CHUNK_MAX && (bytes = TRIE_CHUNK_MAX)`: at bytes == MAX the assignment is the identity.
   - S4: :733 `head.sweep_at = UInt32(kept * 2 > TRIE_SWEEP_MIN ? kept * 2 : TRIE_SWEEP_MIN)`: at kept*2 == TRIE_SWEEP_MIN (:90 = 1024) both branches are 1024.
   - X1: :1094 `compounds == 1000 && add && !is_acyclic_cells(ld, l)`: moves only the depth of the check; a cyclic term passes 1001 too and prune_error (:1096) removes what was added, a finite one is acyclic at either depth: same rc, same trie. The bounded kill of the check is TR1-L1.
   - W2b: :952 `for i in tab.wild` in the keyed branch of intern_indirect (:939): a keyed value is never gnd_equal to a wildcard one: `gnd_value_key` src/default_term.jl:54 (contract at :44-52: the key agrees with gnd_equal, so equal values have equal keys and a value with a key never equals a keyless one).
   - K3: :2053 `tr === nothing || tr.magic != TRIE_MAGIC || !(1 <= nid <= length(tr.nodes))`: a destroyed trie was emptied by trie_destroy -> clear_nodes (:193-199, `resize!(tr.nodes, 1)` at :198), so a handle (nid >= 2, trie_insert/4 never hands out the root) fails the range test; row kd7 (TP:374) runs it.
   - D2: :769-773 `if (flags & CN_ALL) == 0 || (n.flags & TN_CHUNKED) == 0` (clear_node): clear_nodes calls free_node_chunks (:196), `resize!(tr.nodes, 1)` (:198) and `empty!(tr.free_ids)` (:199) right after clear_node(CN_ALL) (:194), and clear_node walks `children` captured before the free: the frees leave nothing observable. (Check the exact line of the `CN_ALL` test with grep -n before citing.)
5. TW row of TR1-D1 is TW:140 (`tr.flags == LK.TRIE_ISSET`, before the inserted rows, unchanged number).
6. HEADER of tools/mutants/TRIE1.py as PIN1.py/D1f.py: what the list pins (pl-trie.jl, the trie: children blocks, allocation, sweep, prune, clear, walk, stat, indirect table, lookup, flat lookup, blobs, errors, the TR1 predicates) ; "Run ONCE, in CI (.github/workflows/mutation.yml; locally: tools/mutate.sh run)"; format; TARGETS rule D-0238: TW and TP for every mutant, TR1-N3/N4 also TB (test/db/test_boot_image_swipl.jl); VERDICTS: CI fresh-process verdicts are authoritative; TR1-N1 and TR1-N2 are BOOT-PATH mutants (initTries!, the call in src/pl-setup.jl:266): only `tools/mutate_ci.py one` judges them (D-0451); TIMEOUT: TR1-L1 is bounded `(compounds == 1000 && add && is_acyclic_cells(ld, l)) || compounds == 5000` so a cyclic term stops instead of looping, a timeout is NO verdict, never caught; DEFERRED KILL list with owners (V6, V11, V12, B6); equivalents with their reasons; "# ORIGINAL:" marker present on line 1; "Every `old` counted exactly once by python3 -I at <HEAD sha>". Trim over-long ids (V11, V12 etc. carry the 'probable' prose). Remove the draft's header lines 1-4 (DRAFT notice). Rerun chk.py on the FINAL file until clean, then commit.
7. Fix the `TB` comment in the list (the draft's long comment about ~line 160).

## _BI_KERNEL_MISSING_FOREIGN finding (test/db/test_boot_image_swipl.jl:161, value 389; do NOT edit there)
Derivation read at :200-250: `missing_foreign = count(k -> o1[k][1][2] == '1', lacking)` where `lacking = oracle keys (module:name/arity of swipl's boot-image rows, config applied) minus the kernel's defined rows`. So each foreign (C) row of swipl's boot modules that the kernel newly DEFINES lowers the count by one; a kernel predicate the oracle does not have does not count (it would go into _BI_KERNEL_ONLY, :152, currently empty, which would FAIL `only_k == _BI_KERNEL_ONLY`). So 389 becomes 389 minus (the number of TR1's 11 registered system predicates that swipl's boot image lists as foreign rows). NOT YET COUNTED because the cap hit: next agent: `grep -n 'PL_extension("' src/pl-trie.jl` for the 11 names/arities, then grep each `system:NAME/ARITY` in the oracle file the test reads (`_BI_OUT`, grep -n "_BI_OUT *=" test/db/test_boot_image_swipl.jl for the path) with foreign flag; if all 11 are there as foreign rows the new value is 378, and the comment at :161 gets a "(389 before TR1 registered ...)" entry; any of the 11 absent from the oracle goes into _BI_KERNEL_ONLY (a different edit: report it). The two supervisor rows system:trie_gen_compiled/2,3 (:156-158, _BI_KERNEL_MISSING_PROLOG) stay missing (prolog rows, not touched by TR1; docs/r2_owners.tsv names trie_gen -> TRIE1).

## Daemon status
No daemon was started or used. Not an engine step.

## FINALIZE DONE (agent 2), commits on wip/tr1 (never pushed, no Julia run)
- 23dab189 TW line numbers remapped (hunks +9/+9/+11/+10/+52; 67 lines; 17 read back).
- 164d6219 ids of C6, C15, C16, S2, P3, V3, V4, V21, U1, U3 name their kill rows (C6, S2, P3, V3, V4 no longer DEFERRED).
- 60d1f8e9 TP row t76 (`trie_new(T), blob(T, Ty)`: swipl's answer `trie`, from the pin build 10.1.20 with the DRIVER text) in test_trie_preds_swipl.{pl,out,jl}: kills B6 (TP .jl:261). NOT RUN on the kernel: next gate, three term types.
- 358dcb8b equivalents with real file:line (A4, S4, X1, W2b, K3, D2), V6/V11/V12 DEFERRED, V18 kill TP:208.
- 917730bf PIN1-style header, TARGETS rule, section ranges. List: 112 mutants, 0 failures, 6 equivalents, 3 DEFERRED KILL (V6, V11, V12).
## _BI_KERNEL_MISSING_FOREIGN (test/db/test_boot_image_swipl.jl:161): COUNTED, NOT EDITED
All 11 registrations (src/pl-trie.jl:2067-2077) are foreign rows (flags 01100000) of module `system` in test/db/test_boot_image_swipl_rows.out:
is_trie/1, trie_new/1, trie_destroy/1, trie_insert/2,3,4, $trie_insert_abstract/3, trie_update/3, trie_lookup/3, trie_delete/3, trie_term/2.
So 389 becomes 378 (add "(389 before TR1 registered the eleven trie predicates)" to the comment at :161); _BI_KERNEL_ONLY stays empty;
the foreign rows still lacking are TR2/TR4's (trie_gen/2,3, $trie_gen_node/3, $trie_property/2, $trie_compile/2).
