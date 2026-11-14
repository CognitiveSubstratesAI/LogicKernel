# ORIGINAL: SYNC-C's mutant list — no swipl-devel counterpart.
# tools/mutants/SYNCC.py — the mutation battery of SYNC-C, the third slice of the sync to swipl-devel cf6960c2 (audit D-0731 B (5), D-0720 (5b)),
# run ONCE, in CI (.github/workflows/mutation.yml; locally: tools/mutate.sh run). Format: tools/mutate_drive.py's (as SYNCA.py): `id`, `file`,
# `old` (must occur EXACTLY once), `new`, optional `equivalent` and `targets`.
# The slice: NEW functions of the target with no struct change: `MurmurHashWide` (pl-hash.c:219-265, both arms: the aligned `UInt32` method and the
# portable `_MurmurHashWide_blocks`, which the `UInt16` method calls) in src/pl-hash.jl.
# SC-1..SC-11 mutate the hash (the length mixed into the seed, the surrogate-pair join and its range edges, the unit count `len` bytes name, the
# little-endian byte order, the `len` the aligned arm hashes).
# KILLS: all in test/core_lang/test_termhash.jl, the only file that calls these functions (`git grep -l` over the tree: no other test file, no src caller):
#        the testset "MurmurHashWide == the target's pl-hash.c" (21 values), the testsets on `len`, on lone surrogates and the range edges
#        (values of the target's C, marker TARGET-ONLY: pin when the oracle moves to cf6960c2).
# TARGETS (D-0238): test/core_lang/test_termhash.jl alone: it is the only file that exercises the mutated code.
# Every `old` was counted EXACTLY once in its file by a python3 -I script when this file was written (no Julia ran).
TH = "test/core_lang/test_termhash.jl"
TARGETS = [TH]
H = "src/pl-hash.jl"


def m(id, old, new, file=H, eq=None):
    d = dict(id=id, file=file, old=old, new=new, targets=TARGETS)
    if eq:
        d["equivalent"] = eq
    return d


MUTANTS = [
    m("SC-1", "    h = seed ⊻ UInt32(n * 4)", "    h = seed ⊻ UInt32(n * 2)"),
    m("SC-2", "            if 0xdc00 <= s[q + 1] < 0xe000\n", "            if false\n"),
    m("SC-3", "            if 0xdc00 <= UInt32(s[p]) < 0xe000\n", "            if false\n"),
    m("SC-4", "(UInt32(s[p]) - 0xdc00)", "(UInt32(s[p]) - 0xdc01)"),
    m("SC-5", "    e = len ÷ sizeof(W) ", "    e = length(s) "),
    m("SC-6", "            if 0xdc00 <= UInt32(s[p]) < 0xe000\n", "            if 0xdc00 < UInt32(s[p]) < 0xe000\n"),
    m("SC-7", "0xd800 <= k < 0xdc00 && p <= e", "0xd800 < k < 0xdc00 && p <= e"),
    m("SC-8", "            if 0xdc00 <= UInt32(s[p]) < 0xe000\n", "            if 0xdc00 <= UInt32(s[p]) <= 0xe000\n"),
    m("SC-9", "0xd800 <= k < 0xdc00 && p <= e", "0xd800 <= k <= 0xdc00 && p <= e"),
    m("SC-10", "(s[(j >> 2) + 1] >> (8 * (j & 3)))", "(s[(j >> 2) + 1] >> (8 * (3 - (j & 3))))"),
    m("SC-11", "    return MurmurHashAligned2(bytes, len, seed)", "    return MurmurHashAligned2(bytes, 4 * length(s), seed)"),
]
