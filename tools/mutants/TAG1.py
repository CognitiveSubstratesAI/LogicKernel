# ORIGINAL: TAG1's mutant list — no swipl-devel counterpart.
# tools/mutants/TAG1.py — the mutation battery of TAG1, the 8-bit cell mask of swipl-devel af9e2e7e (bb4ccf71 and its follow-ups): LMASK_BITS 8 with
# `VARIANT_BIT` at bit 5 (pl-data.h), MARK_MASK/FIRST_MASK at bits 6/7, `KIND_MPQ`/`indKind`/`hasTag`, the INDIRECT_BM rational rows, `isTaggedIntW` on a
# pointer integer, the size words (`mpz_size_stack`/`mpz_stack_size` without the rational bit), `isMarkedOrIndHdr`/`nonFunctorKey`, the hashes of
# `hashIndex` (src/pl-index.jl) and `child_hash` (src/pl-trie.jl) over the VALUE (`key >> CELL_VAL_SHIFT`), the int32 round trip of
# `is_portable_constant` (src/pl-comp.jl) and the `ttag` spelling of `gc_trail_tagged_isval` (src/pl-gctrail.jl). Run ONCE, in CI
# (.github/workflows/mutation.yml; locally: tools/mutate.sh run). Format: tools/mutate_drive.py's (as TRIE1.py): `id`, `file`, `old` (must occur
# EXACTLY once), `new`, optional `equivalent` and `targets`.
# Each id names its KILL, the assertion that must fail (file:line at the commit that counts the lists, see the last line):
#   TW = test/core_lang/test_words.jl (white-box rows on the layout; the testset "TAG1: the variant bit ..." at :125-170 and "TAG1: hashIndex and child_hash
#   ..." at :172-193 are TAG1's), TT = test/core_lang/test_trie_swipl.jl (:277-300, the child_hash pins), BC = test/compile/test_body_code_swipl.jl (the
#   is_portable_constant testset :1218-1241 and the `==` cells eb8/eb10/eb16/eb17 :1049-1053).
# TARGETS (audit D-0238): every test file that runs the mutated code and can see its effect. The layout mutants (LMASK_BITS, the mask positions) change
#   every word of the kernel, so L lists the files that pin a word, a range, a mask bit or a slot; the API mutants of pl-incl.jl that NO kernel code calls
#   (`indKind`, `isPtrInt`, `consPtrInt`, `isMarkedOrIndHdr`, `INDHDR_BIT`, `nonFunctorKey`, `mpz_*`: git grep over src at 10a0e54c finds only comments
#   outside pl-incl.jl; the rational kind is read by no kernel path either) have TW as their only target. The `TARGETS` variable is the union
#   (mutate_ci.py plan reads it).
# VERDICTS: the CI mutation battery runs one fresh process per mutant and its verdicts are authoritative. The layout mutants of pl-incl.jl change a
#   `const`: a warm daemon needs the struct-change restart, the CI battery runs one process per mutant.
# EQUIVALENT mutant (declared with its reason): TAG1-G1 (`tag(w) & TAG_TRAILMASK` -> `w & TAG_TRAILMASK`).
# NO KILL BY THE ORACLE: test/db/test_index_swipl.jl compares answers with swipl (allowed difference: hashIndex bucket counts); the hashIndex mutant is
#   killed by the model rows of TW (:185-186), not there.
# Every `old` was counted EXACTLY once in its file by a python3 -I script at 10a0e54c (the last commit of the TAG1 layout; the 24 mutants, no Julia
#   ran); `new` != `old`; no duplicate id. RE-FIT any `old` that `tools/warm.sh fmt` rewraps.
TW = "test/core_lang/test_words.jl"
TT = "test/core_lang/test_trie_swipl.jl"
BC = "test/compile/test_body_code_swipl.jl"
TI = "test/core_lang/test_tagged_ints.jl"
AC = "test/core_lang/test_arith_cells.jl"
NV = "test/core_lang/test_numbervars_cells.jl"
GT = "test/core_lang/test_gc_trail.jl"
GS = "test/core_lang/test_gc_sweep.jl"
GC = "test/core_lang/test_gc_compact.jl"
HT = "test/core_lang/test_htable.jl"
HC = "test/compile/test_head_code_swipl.jl"
RC = "test/db/test_record_swipl.jl"
RU = "test/core_lang/test_rules_swipl.jl"
RD = "test/core_lang/test_read_dict_swipl.jl"
IX = "test/db/test_index_swipl.jl"
TP = "test/core_lang/test_trie_preds_swipl.jl"
TG = "test/core_lang/test_trie_gen_swipl.jl"
TA = "test/core_lang/test_trie_attvar_swipl.jl"
L = [TW, TI, AC, NV, GT, GS, GC, HT, TT, BC, HC, RC, RU, RD]           # the layout mutants
TARGETS = [TW, TI, AC, NV, GT, GS, GC, HT, TT, BC, HC, RC, RU, RD, IX, TP, TG, TA]
INC = "src/pl-incl.jl"


def m(id, file, old, new, targets, eq=None):
    d = dict(id=id, file=file, old=old, new=new, targets=targets)
    if eq:
        d["equivalent"] = eq
    return d


MUTANTS = [
    # ---- C1: src/pl-incl.jl
    m("TAG1-L1 LMASK_BITS 7 (KILL TW:36 `LMASK_BITS == 8`, TW:93 PLMAXTAGGEDINT == 2^55 - 1, TW:169 the mask bits are 0xff)",
      INC, "const LMASK_BITS = 8\n", "const LMASK_BITS = 7\n", L),
    m("TAG1-L2 MARK_MASK at bit 7, the FIRST_MASK's (KILL TW:34 `MARK_MASK == 0x40`, TW:169 `MARK|FIRST|TAGEX == 0xff`)",
      INC, "const MARK_MASK = UInt64(0x1) << 6\n", "const MARK_MASK = UInt64(0x2) << 6\n", L),
    m("TAG1-L3 FIRST_MASK at bit 6, the MARK_MASK's (KILL TW:34 `FIRST_MASK == 0x80`, TW:169)",
      INC, "const FIRST_MASK = UInt64(0x2) << 6\n", "const FIRST_MASK = UInt64(0x1) << 6\n", L),
    m("TAG1-L4 VARIANT_BIT at bit 4, the storage's (KILL TW:35 `VARIANT_BIT == 0x20`, TW:127)",
      INC, "const VARIANT_BIT = UInt64(0x1) << 5\n", "const VARIANT_BIT = UInt64(0x1) << 4\n", L),
    m("TAG1-L5 TAGEX_MASK without the variant bit (KILL TW:35 `TAGEX_MASK == 0x3f`, TW:127, TW:133 tagex(w) == t|s|v)",
      INC, "const TAGEX_MASK = TAG_MASK | STG_MASK | VARIANT_BIT\n", "const TAGEX_MASK = TAG_MASK | STG_MASK\n", [TW]),
    m("TAG1-L6 KIND_MPQ is the integer tag (KILL TW:127 `KIND_MPQ == 0x23`, TW:144 `count_ones(INDIRECT_BM) == 8`: two rows coincide)",
      INC, "const KIND_MPQ = TAG_INTEGER | VARIANT_BIT\n", "const KIND_MPQ = TAG_INTEGER\n", [TW]),
    m("TAG1-L7 TAGEX_COUNT 32 (KILL TW:35 `TAGEX_COUNT == 64`, TW:133 `tagex(w) < TAGEX_COUNT` for a variant-bit word)",
      INC, "const TAGEX_COUNT = 64", "const TAGEX_COUNT = 32", [TW]),
    m("TAG1-L8 CELL_VAL_SHIFT one below LMASK_BITS (KILL TW:37 `CELL_VAL_SHIFT == LMASK_BITS`, TW:185 hashIndex model, TT:300 [39,11,37,40])",
      INC, "const CELL_VAL_SHIFT = LMASK_BITS\n", "const CELL_VAL_SHIFT = LMASK_BITS - 1\n", [TW, TT, IX, TP, TG, TA]),
    m("TAG1-L9 INDIRECT_BM loses both rational rows (KILL TW:142 isIndirect on a KIND_MPQ word on both storages, TW:144 count_ones == 8)",
      INC, "    EXBIT(STG_GLOBAL | KIND_MPQ) | EXBIT(STG_LOCAL | KIND_MPQ) |\n", "", [TW]),
    m("TAG1-L10 INDIRECT_BM loses the local rational row (KILL TW:141-142, the loop's `STG_LOCAL` pass; TW:144)",
      INC, "EXBIT(STG_LOCAL | KIND_MPQ)", "EXBIT(STG_LOCAL | TAG_FLOAT)", [TW]),
    m("TAG1-L11 isTaggedIntW excludes the variant bit (KILL TW:147 `isTaggedIntW(consPtrInt(77))`; upstream's isTaggedInt tests tag and storage only)",
      INC, "(w & (TAG_MASK | STG_MASK)) == (TAG_INTEGER | STG_INLINE)", "tagex(w) == (TAG_INTEGER | STG_INLINE)", [TW]),
    m("TAG1-L12 isPtrInt is true of a plain tagged integer (KILL TW:150 `!isPtrInt(consInt(77))`)",
      INC, "isPtrInt(w::word)::Bool = tagex(w) == TAGEX_PTRINT", "isPtrInt(w::word)::Bool = isTaggedIntW(w)", [TW]),
    m("TAG1-L13 consPtrInt does not set the variant bit (KILL TW:147 `isPtrInt(pw)`, TW:148-149 `pw == consInt | 0x20`)",
      INC, "consInt(i) | VARIANT_BIT", "consInt(i)", [TW]),
    m("TAG1-L14 hasTag compares the extended tag (KILL TW:142 and TW:147 `isRationalW` of a KIND_MPQ / pointer-integer word)",
      INC, "hasTag(w::word, t::word)::Bool = tag(w) == t", "hasTag(w::word, t::word)::Bool = tagex(w) == t", [TW]),
    m("TAG1-L15 indKind is the tag (KILL TW:142 `indKind(w) == KIND_MPQ`, TW:135 `indKind(w) == t | v`, TW:105 the KIND_MPQ header)",
      INC, "indKind(w::word)::word = tagex(w) & ~STG_MASK", "indKind(w::word)::word = tag(w)", [TW]),
    m("TAG1-L16 mpz_stack_size loses the sign (KILL TW:120 `mpz_stack_size(z) == sz` for sz < 0)",
      INC, "w % Int32", "abs(w % Int32)", [TW]),
    m("TAG1-L17 mpz_size_stack loses the sign (KILL TW:119 `z == reinterpret(UInt64, Int64(sz))`, TW:120)",
      INC, "reinterpret(word, Int64(sz))", "word(abs(Int64(sz)))", [TW]),
    m("TAG1-L18 isMarkedOrIndHdr ignores the FIRST bit (KILL TW:165 `isMarkedOrIndHdr(base | FIRST_MASK)`)",
      INC, "(MARK_MASK | FIRST_MASK | INDHDR_BIT)", "(MARK_MASK | INDHDR_BIT)", [TW]),
    m("TAG1-L19 INDHDR_BIT is STG_GLOBAL (KILL TW:162 `INDHDR_BIT == STG_LOCAL`, TW:166 the header's STG_LOCAL is no stop, TW:164 the global reference is a stop)",
      INC, "const INDHDR_BIT = STG_LOCAL", "const INDHDR_BIT = STG_GLOBAL", [TW]),
    m("TAG1-L20 nonFunctorKey is the identity (KILL TW:155 `!isFunctor(nonFunctorKey(fw))`, TW:156)",
      INC, "k & ~consTagged(0, STG_GLOBAL)", "k", [TW]),
    # ---- C2: the hashes over the value
    m("TAG1-H1 child_hash hashes the whole word (KILL TT:298-300 the slots 31/31, 7/3 and [39,11,37,40], TW:190-191; TR1-C15's numbers)",
      "src/pl-trie.jl", "Int((UInt64(key >> CELL_VAL_SHIFT) * 0x9e3779b97f4a7c15) >> (64 - bits))",
      "Int((UInt64(key) * 0x9e3779b97f4a7c15) >> (64 - bits))", [TW, TT, TP, TG, TA]),
    m("TAG1-H2 hashIndex hashes the whole word (KILL TW:185-186 the model rows; no test of IX pins a bucket number, its bucket counts are an allowed difference)",
      "src/pl-index.jl", "    key >>= CELL_VAL_SHIFT                  # consecutive values step by 1 (bb4ccf71: a cell reserves 8 low bits)\n", "", [TW, IX]),
    # ---- C3: is_portable_constant, gc_trail_tagged_isval
    m("TAG1-P1 is_portable_constant keeps the old +-2^24 bound (KILL BC:1229 the rows 2^23, -2^23-1, +-2^24 refused under the flag; BC:1049 eb8, :1051 eb10, :1052 eb16)",
      "src/pl-comp.jl", "            return reinterpret(word, Int64(reinterpret(Int32, c))) == ww   # (word)(sword)(int32_t)c == w\n",
      "            return PLMINTAGGEDINT32 <= Int64(int64_value(w)) <= PLMAXTAGGEDINT32\n", [BC, "test/core_lang/test_attvar_wakeup.jl", "test/compile/test_portable_smallint_swipl.jl"]),
    m("TAG1-G1 gc_trail_tagged_isval reads `w & TAG_TRAILMASK` (EQUIVALENT: `tag(w)` is `w & TAG_MASK` and TAG_TRAILMASK is 0x1, inside TAG_MASK, so both masks give bit 0)",
      "src/pl-gctrail.jl", "(tag(w) & TAG_TRAILMASK) == TAG_TRAILVAL", "(w & TAG_TRAILMASK) == TAG_TRAILVAL", [GT, GC],
      eq="src/pl-incl.jl: tag(w) = w & TAG_MASK (TAG_MASK = 0x7, :391) and TAG_TRAILMASK = 0x1 (:657), so (w & 0x7) & 0x1 == w & 0x1 for every word; src/pl-gctrail.jl:79"),
]
