# ORIGINAL: E4's mutant list - a trie deleted while it is enumerated (no swipl-devel counterpart for the list).
# tools/mutants/E4.py - the mutation battery of the E4 fix (src/pl-trie.jl): trie_gen_raw holds a reference on the trie for the whole
# enumeration (pl-trie.c trie_gen_raw `acquire_trie(trie)` on FRG_FIRST_CALL, clear_trie_state `release_trie(state->trie)`; pl-trie.h
# acquire_trie/release_trie, unconditional macros), so trie_delete under it clears the value and does not prune (pl-trie.c trie_delete
# `prune && trie->references == 0`): a prune compacts the parent's block (delete_child, replace_block) and the enumeration's position
# then skips live children. Run ONCE, in CI (.github/workflows/mutation.yml; locally one mutant by hand).
# Format: tools/mutate_drive.py's (as RECSIZEINT.py): `id`, `file`, `old` (must occur EXACTLY once), `new`, optional `equivalent`, `targets`.
# Rows: test/core_lang/test_trie_gen_swipl.jl t39-t47 (the .pl; answers in the .out, swipl 10.1.20's), the "E4 kill rows" testset and the
# E4 white-box testset.
# `old` was counted EXACTLY once in src/pl-trie.jl (python3 -I script, at the fix). RE-FIT any `old` that `tools/warm.sh fmt` rewraps.
# TARGETS (audit D-0238): every test file that runs trie_gen_raw or trie_delete (the trie predicates, the tabling answer tries, the boot
# image that registers them).
TG = "test/core_lang/test_trie_gen_swipl.jl"
TARGETS = [
    TG,
    "test/core_lang/test_trie_swipl.jl",
    "test/core_lang/test_trie_preds_swipl.jl",
    "test/core_lang/test_trie_attvar_swipl.jl",
    "test/core_lang/test_trie_compiled_swipl.jl",
    "test/core_lang/test_tabling_answers_swipl.jl",
    "test/core_lang/test_tabling_min_swipl.jl",
    "test/core_lang/test_tabling_tb4rows_swipl.jl",
    "test/core_lang/test_tabling_tb4rows2_swipl.jl",
    "test/core_lang/test_tabling_variant_swipl.jl",
    "test/core_lang/test_tabling_wfs_swipl.jl",
    "test/core_lang/test_tabling_worklist_swipl.jl",
]
F = "src/pl-trie.jl"
MUTANTS = [
    dict(id="E4-A1 trie_gen_raw takes no reference on the trie: trie_delete prunes under the enumeration and the compaction skips live children (KILL TG: t39, t40, t42-t44, t47 and the white box references == 1)",
         file=F, targets=TARGETS,
         old="        acquire_trie(trf)\n        k = alloc_foreign_state!(pool)\n",
         new="        k = alloc_foreign_state!(pool)\n"),
    dict(id="E4-R1 clear_trie_state! never releases the reference: the trie stays in use after the enumeration, a later trie_delete does not prune (KILL TG: t46 node_count 3 x 1, the white box references == 0)",
         file=F, targets=TARGETS,
         old="        release_trie(gd, tr)\n    end\n    return nothing\nend\n\n# PORT: pl-trie.c check_epoch\n",
         new="    end\n    return nothing\nend\n\n# PORT: pl-trie.c check_epoch\n"),
    dict(id="E4-R2 release_trie drops the count and never runs trie_clean: a trie destroyed under its enumeration keeps its nodes (KILL TG: the white box node_count == 1 after the release)",
         file=F, targets=TARGETS,
         old="    tr.references == 0 && trie_clean(gd, tr)\n",
         new="    tr.references == 0\n"),
    dict(id="E4-D1 empty_trie empties a trie in use: a trie destroyed under its enumeration loses its nodes while the enumeration walks them (KILL TG: t47 and the white box node_count kept after trie_destroy)",
         file=F, targets=TARGETS,
         old="    if tr.references == 0\n        clear_nodes(gd, tr, vt)\n",
         new="    if tr.references >= 0\n        clear_nodes(gd, tr, vt)\n"),
]
