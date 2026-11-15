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
]
