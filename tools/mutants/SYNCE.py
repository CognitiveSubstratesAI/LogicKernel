# ORIGINAL: SYNC-E's mutant list — no swipl-devel counterpart.
# tools/mutants/SYNCE.py — the mutation battery of SYNC-E (the pl-termhash.c slice of the sync to swipl-devel cf6960c2), run ONCE, in CI
# (.github/workflows/mutation.yml; locally: tools/mutate.sh run). The format is tools/mutate_drive.py's: `id`, `file`, `old` (must
# occur EXACTLY once), `new`, optional `equivalent` and `targets`. Only the behaviour change of the slice has a mutant: the word a
# numbered variable writes into the variant digest (`HASH_VAR`: "V" and the variable's number; see evidence/SYNC/sync_e_handoff.md).
# TARGETS lists every test file that runs the variant digests (D-0238): the row is in test_termhash.jl, the others compare digests of
# variants and non-variants, and the blob and term-type tests compare digests of grounded values.
# The `old` strings were written BEFORE `tools/warm.sh fmt`: re-check them after it (mutate_drive.py refuses a string that does not
# occur exactly once).
TARGETS = [
    "test/core_lang/test_termhash.jl",
    "test/core_lang/test_hash.jl",
    "test/core_lang/test_variant_swipl.jl",
    "test/core_lang/test_bootpred3_swipl.jl",
    "test/core_lang/test_blob.jl",
]
T = TARGETS
P = "src/pl-termhash.jl"
MUTANTS = [
    dict(id="SE-1 a variable is hashed by its marked cell word (the pin's bytes)", file=P, targets=T,
         old='''_HASH_word!(state, UInt64(i))   # HASH_VAR: the variable's number, not its marked cell''',
         new='''_HASH_word!(state, (UInt64(i) << LMASK_BITS) | TAG_VAR | MARK_MASK)'''),
    dict(id="SE-2 the variable numbers start at 1", file=P, targets=T,
         old='''_HASH_word!(state, UInt64(i))   # HASH_VAR: the variable's number, not its marked cell''',
         new='''_HASH_word!(state, UInt64(i + 1))'''),
    dict(id="SE-3 every variable writes the number 0", file=P, targets=T,
         old='''_HASH_word!(state, UInt64(i))   # HASH_VAR: the variable's number, not its marked cell''',
         new='''_HASH_word!(state, UInt64(0))'''),
]
