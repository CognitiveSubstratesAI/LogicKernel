# ORIGINAL: pl-data.h's word layout (L1b stage C1: src/pl-incl.jl, src/pl-inline.jl) against its C definitions at the pin; upstream has no unit test of its macros (they are compiled into every test it runs).
# test/core_lang/test_words.jl — white-box, each expected value from the macro's C text at the pin
# (swipl cannot be asked for a macro's value, so these are hand-written; the comment on each case
# quotes the definition it follows):
#   * every tag × storage pair: `tag`, `storage`, `tagex`, and each type test on a word —
#     `isVar` (the word 0 only), `isAtomW` against `isFunctor` (one tag, two storages),
#     `isTaggedIntW`, `isIndirect` (an integer, float or string on the global or local stack),
#     `isRef`, `isAttVar`, `needsRef`, `isConst` (the six tests whose names the kernel's term-level
#     tests hold are `isAtomW` … `isTaggedIntW`, and the term-level ones have no word method);
#   * `consPtr`/`valPtr` round trips at positions 1, 2^27 and the last a word can hold, on both
#     stacks, and `makeRefG`/`makeRefLok`/`unRef`;
#   * `consInt`/`valInt` at the tagged range's edges: the largest and smallest tagged integer round
#     trip, one past each does NOT (put_int64's test: such an integer is an MPZ indirect);
#   * the indirect headers: `mkIndHdr`/`wsizeofInd`, `mkBlobHdr`/`padHdr` for every pad 0-7 (0
#     reads as 8), and pl-gmp.h's size words (sign only: a rational has its own cell kind);
#   * TAG1 (the 8-bit mask: pl-data.h's `VARIANT_BIT` at bit 5, MARK/FIRST at bits 6/7): the
#     variant bit, `KIND_MPQ`, `indKind`, the INDIRECT_BM rational rows, `isTaggedIntW` on a pointer
#     integer, `nonFunctorKey`, `isMarkedOrIndHdr`, `TAGEX_COUNT`.
using Test, LogicKernel
const LK = LogicKernel

const _WD_TAGS = (
    LK.TAG_VAR, LK.TAG_ATTVAR, LK.TAG_FLOAT, LK.TAG_INTEGER, LK.TAG_STRING, LK.TAG_ATOM,
    LK.TAG_COMPOUND, LK.TAG_REFERENCE
)
const _WD_STGS = (LK.STG_STATIC, LK.STG_GLOBAL, LK.STG_LOCAL, LK.STG_RESERVED)

@testset "the tags and storage bits are pl-data.h's" begin
    # #define TAG_VAR 0 … TAG_REFERENCE 7; STG_STATIC (0x0<<3) … STG_RESERVED (0x3<<3)
    @test _WD_TAGS == UInt64.(Tuple(0:7))
    @test _WD_STGS == UInt64.((0, 8, 16, 24))
    # TAG1: #define VARIANT_BIT 0x20, MARK_MASK (0x1<<6) = 0x40, FIRST_MASK (0x2<<6) = 0x80,
    # LMASK_BITS 8 (tag 3 + storage 2 + variant 1 + mark 1 + first 1)
    @test LK.STG_INLINE == LK.STG_STATIC && LK.MARK_MASK == 0x40 && LK.FIRST_MASK == 0x80
    @test LK.VARIANT_BIT == 0x20 && LK.TAGEX_MASK == 0x3f && LK.TAGEX_COUNT == 64
    @test LK.TAG_MASK == 0x7 && LK.STG_MASK == 0x18 && LK.LMASK_BITS == 8
    @test LK.CELL_VAL_SHIFT == LK.LMASK_BITS
end

@testset "every tag × storage pair: tag, storage, tagex and the tests on a word" begin
    for t in _WD_TAGS, s in _WD_STGS
        w = (UInt64(12345) << LK.LMASK_BITS) | s | t
        @test LK.tag(w) == t && LK.storage(w) == s && LK.tagex(w) == (t | s)
        # isAtom: tagex == TAG_ATOM|STG_STATIC; isFunctor: tagex == TAG_ATOM|STG_GLOBAL
        @test LK.isAtomW(w) == (t == LK.TAG_ATOM && s == LK.STG_STATIC)
        @test LK.isFunctor(w) == (t == LK.TAG_ATOM && s == LK.STG_GLOBAL)
        @test !(LK.isAtomW(w) && LK.isFunctor(w))
        # isTaggedInt: tagex == TAG_INTEGER|STG_INLINE
        @test LK.isTaggedIntW(w) == (t == LK.TAG_INTEGER && s == LK.STG_STATIC)
        # INDIRECT_BM: INTEGER, FLOAT, STRING with STG_GLOBAL or STG_LOCAL
        @test LK.isIndirect(w) ==
            (
            t in (LK.TAG_INTEGER, LK.TAG_FLOAT, LK.TAG_STRING) &&
            s in (LK.STG_GLOBAL, LK.STG_LOCAL)
        )
        @test LK.isRef(w) == (t == LK.TAG_REFERENCE)
        @test LK.isAttVar(w) == (t == LK.TAG_ATTVAR)
        @test LK.needsRef(w) == (t <= LK.TAG_ATTVAR)              # tag(w) <= TAG_ATTVAR
        @test LK.isTermW(w) == (t == LK.TAG_COMPOUND)
        @test LK.isFloatW(w) == (t == LK.TAG_FLOAT) &&
            LK.isStringW(w) == (t == LK.TAG_STRING)
        @test LK.isRationalW(w) == (t == LK.TAG_INTEGER)
        @test LK.isConst(w) == (LK.isAtomW(w) || LK.isTaggedIntW(w))
        @test !LK.isVar(w)                                         # nonzero: never a variable
    end
    # #define isVar(w) ((w) == (word)0): the word 0 only; a TAG_VAR word with bits above is not
    @test LK.isVar(UInt64(0)) && !LK.isVar(UInt64(1) << LK.LMASK_BITS)
    @test LK.needsRef(UInt64(0))
end

@testset "consPtr/valPtr: positions 1, 2^27 and the last, on both stacks" begin
    last = Int(typemax(UInt64) >> LK.LMASK_BITS)                   # 2^56 - 1
    for p in (1, 2^27, last),
        ts in (LK.TAG_REFERENCE | LK.STG_GLOBAL, LK.TAG_REFERENCE | LK.STG_LOCAL,
            LK.TAG_FLOAT | LK.STG_GLOBAL, LK.TAG_STRING | LK.STG_LOCAL)

        w = LK.consPtr(p, ts)
        @test LK.valPtr(w) == p && LK.tagex(w) == ts
    end
    @test LK.makeRefG(5) == (UInt64(5) << 8) | LK.TAG_REFERENCE | LK.STG_GLOBAL
    @test LK.makeRefLok(5) == (UInt64(5) << 8) | LK.TAG_REFERENCE | LK.STG_LOCAL
    @test LK.unRef(LK.makeRefG(2^27)) == 2^27 && LK.isRef(LK.makeRefLok(1))
end

@testset "consInt/valInt at the tagged range's edges" begin
    for n in (0, 1, -1, 42, -42, LK.PLMAXTAGGEDINT, LK.PLMINTAGGEDINT)
        w = LK.consInt(n)
        @test LK.valInt(w) == n && LK.isTaggedIntW(w)               # put_int64: valInt(r) == l
    end
    # one past each edge does not survive the shift: put_int64 makes it an MPZ indirect instead
    @test LK.valInt(LK.consInt(LK.PLMAXTAGGEDINT + 1)) != LK.PLMAXTAGGEDINT + 1
    @test LK.valInt(LK.consInt(LK.PLMINTAGGEDINT - 1)) != LK.PLMINTAGGEDINT - 1
    @test LK.PLMAXTAGGEDINT == 2^55 - 1 && LK.PLMINTAGGEDINT == -2^55   # 64 - LMASK_BITS - 1 = 55
    @test LK.consUInt(UInt64(7)) == (UInt64(7) << 8) | LK.TAG_INTEGER
    # 2^55 is one past the signed range and still fits above the 8 mask bits (2^55 << 8 = 2^63)
    @test LK.valUInt(LK.consUInt(UInt64(2)^55)) == UInt64(2)^55
    @test LK.valUInt(LK.consUInt(UInt64(2)^56 - 1)) == UInt64(2)^56 - 1
end

@testset "the indirect headers and pl-gmp.h's size words" begin
    # mkIndHdr(size, tag) = size << (LMASK_BITS+PADBITS) | tag | STG_LOCAL; the kind KIND_MPQ
    # (TAG_INTEGER|VARIANT_BIT) is a header kind too: its tag is TAG_INTEGER, its indKind KIND_MPQ
    for n in (1, 2, 1000, 2^40),
        t in (LK.TAG_FLOAT, LK.TAG_INTEGER, LK.KIND_MPQ, LK.TAG_STRING)

        h = LK.mkIndHdr(n, t)
        @test LK.wsizeofInd(h) == n && LK.indKind(h) == t && LK.storage(h) == LK.STG_LOCAL
        @test LK.tag(h) == (t & LK.TAG_MASK) && LK.isIndirect(h)
        @test h == (UInt64(n) << (LK.LMASK_BITS + LK.PADBITS)) | t | LK.STG_LOCAL
    end
    # padHdr: the pad bits, 0 meaning sizeof(word)
    for pad in 0:7
        h = LK.mkBlobHdr(3, pad, LK.TAG_STRING)
        @test LK.padHdr(h) == (pad == 0 ? 8 : pad) && LK.wsizeofInd(h) == 3
    end
    # TAG1: mpz_size_stack(sz) = (word)(sword)sz and mpz_stack_size(w) = (int)(sword)w: the size word
    # carries the sign only (a rational has the cell kind KIND_MPQ, so the old rational bit is gone)
    for sz in Int32.((0, 1, 2, 17, -1, -17, typemax(Int32) >> 1, -(typemax(Int32) >> 1),
        typemax(Int32), typemin(Int32)))
        z = LK.mpz_size_stack(sz)
        @test z == reinterpret(UInt64, Int64(sz))
        @test LK.mpz_stack_size(z) == sz
    end
    @test !isdefined(LK, :mpq_size_stack) && !isdefined(LK, :MP_RAT_MASK)
end

@testset "TAG1: the variant bit, KIND_MPQ, indKind, the INDIRECT_BM rational rows, the stop tests" begin
    # #define VARIANT_BIT 0x20; KIND_MPQ (TAG_INTEGER|VARIANT_BIT) = 0x23; TAGEX_MASK 0x3f; TAGEX_COUNT 64
    @test LK.KIND_MPQ == 0x23 &&
        LK.TAGEX_MASK == (LK.TAG_MASK | LK.STG_MASK | LK.VARIANT_BIT)
    @test LK.TAGEX_INDIRECT_MPQ == (LK.KIND_MPQ | LK.STG_GLOBAL) == 0x2b
    @test LK.TAGEX_PTRINT == (LK.TAG_INTEGER | LK.STG_INLINE | LK.VARIANT_BIT) == 0x23
    # tagex keeps the variant bit and nothing above it, so every value is below TAGEX_COUNT
    for t in _WD_TAGS, s in _WD_STGS, v in (UInt64(0), LK.VARIANT_BIT)
        w = (UInt64(12345) << LK.LMASK_BITS) | s | t | v
        @test LK.tagex(w) == (t | s | v) && LK.tagex(w) < LK.TAGEX_COUNT
        @test LK.tag(w) == t && LK.storage(w) == s                 # the variant bit is in neither
        @test LK.indKind(w) == (t | v)                              # tagex without the storage bits
        # a MARK or FIRST bit changes no tagex: they sit above the variant bit
        @test LK.tagex(w | LK.MARK_MASK | LK.FIRST_MASK) == LK.tagex(w)
    end
    # INDIRECT_BM: 4 kinds x 2 storages = 8 bits; the rational kind with the variant bit is one
    for s in (LK.STG_GLOBAL, LK.STG_LOCAL)
        w = (UInt64(9) << LK.LMASK_BITS) | LK.KIND_MPQ | s
        @test LK.isIndirect(w) && LK.indKind(w) == LK.KIND_MPQ && LK.isRationalW(w)
    end
    @test count_ones(LK.INDIRECT_BM) == 8
    # a rational with the variant bit in static storage is a pointer integer, not an indirect
    pw = LK.consPtrInt(Int64(77))
    @test LK.isPtrInt(pw) && LK.isTaggedIntW(pw) && !LK.isIndirect(pw) && LK.isRationalW(pw)
    @test pw == LK.consInt(Int64(77)) | 0x20 && LK.valInt(pw) == 77
    @test LK.consPtrInt(Int64(-5)) == LK.consInt(Int64(-5)) | LK.VARIANT_BIT &&
        LK.valInt(LK.consPtrInt(Int64(-5))) == -5
    @test !LK.isPtrInt(LK.consInt(Int64(77))) && LK.isTaggedIntW(LK.consInt(Int64(77)))
    @test !LK.isAtomW(pw) && !LK.isFunctor(pw) && !LK.isVar(pw)
    # nonFunctorKey(k) = k & ~consTagged(0, STG_GLOBAL): bit 3 cleared, so a functor word turns
    # into the atom word with the same index, and no result is a functor
    fw = LK.consTagged(1234, LK.TAG_ATOM | LK.STG_GLOBAL)
    @test LK.isFunctor(fw) && !LK.isFunctor(LK.nonFunctorKey(fw))
    @test LK.nonFunctorKey(fw) == LK.consTagged(1234, LK.TAG_ATOM) &&
        LK.isAtomW(LK.nonFunctorKey(fw))
    @test LK.nonFunctorKey(LK.consInt(Int64(5))) == LK.consInt(Int64(5))      # no STG_GLOBAL bit: unchanged
    for t in _WD_TAGS, s in _WD_STGS
        @test !LK.isFunctor(LK.nonFunctorKey((UInt64(321) << LK.LMASK_BITS) | s | t))
    end
    # isMarkedOrIndHdr: MARK (0x40), FIRST (0x80) or the indirect-header storage bit (STG_LOCAL = 0x10)
    @test LK.INDHDR_BIT == LK.STG_LOCAL
    base = UInt64(5) << LK.LMASK_BITS
    @test !LK.isMarkedOrIndHdr(base | LK.TAG_REFERENCE | LK.STG_GLOBAL)
    @test LK.isMarkedOrIndHdr(base | LK.MARK_MASK) &&
        LK.isMarkedOrIndHdr(base | LK.FIRST_MASK)
    @test LK.isMarkedOrIndHdr(LK.mkIndHdr(2, LK.TAG_FLOAT)) &&
        LK.isMarkedOrIndHdr(LK.mkIndHdr(2, LK.KIND_MPQ))
    @test !LK.isMarkedOrIndHdr(base | LK.VARIANT_BIT)             # bit 5 is not one of the three
    # the cell value starts at CELL_VAL_SHIFT = LMASK_BITS; the mask bits are 0x3f + 0x40 + 0x80 = 0xff
    @test LK.MARK_MASK | LK.FIRST_MASK | LK.TAGEX_MASK == UInt64(0xff) ==
        (UInt64(1) << LK.LMASK_BITS) - 1
end

# TAG1 (pl-index.c hashIndex, pl-trie.c child_hash at swipl-devel af9e2e7e): both hash the VALUE of a key (`key >> CELL_VAL_SHIFT`), not its
# mask bits: consecutive values step by one whatever the tag. Models written here from the C text (Fibonacci hashing), independent of src.
@testset "TAG1: hashIndex and child_hash hash the key without its mask bits" begin
    fib = 0x9E3779B97F4A7C15
    model_hi(k::UInt64, b::UInt32) = begin
        sh = 64 - trailing_zeros(b)                       # key_bits - MSB(buckets), buckets a power of two
        v = k >> 8                                       # CELL_VAL_SHIFT = LMASK_BITS = 8
        v ⊻= (v >> sh)
        ((fib * v) >> sh) % UInt32
    end
    model_ch(k::UInt64, bits::Int) = Int(((k >> 8) * fib) >> (64 - bits))
    for n in (1, 2, 3, 100, 12345, 2^30), b in (UInt32(16), UInt32(1024))
        w = LK.consInt(Int64(n))
        @test LK.hashIndex(w, b) == model_hi(w, b)
        @test LK.hashIndex(w | LK.MARK_MASK | LK.FIRST_MASK | LK.VARIANT_BIT, b) ==
            LK.hashIndex(w, b)   # the mask bits are no part of the hash
    end
    for n in (1, 10, 77, 12345), bits in (3, 5, 6)
        w = LK.consInt(Int64(n))
        @test LK.child_hash(w, bits) == model_ch(w, bits)
        @test LK.child_hash(w | LK.MARK_MASK | LK.FIRST_MASK | LK.VARIANT_BIT, bits) ==
            LK.child_hash(w, bits)
    end
end

@testset "the term-level type tests have no method on a word (JET, CI on 7fa3df4)" begin
    # a method on `word` of a term-level test let JET's whole-package analysis follow a word into
    # term-only code (19 reports); the word tests are the `W` functions until the term tests go (L1f)
    for f in (LK.isAtom, LK.isRational, LK.isFloat, LK.isString, LK.isTerm, LK.isTaggedInt)
        @test which(f, (UInt64,)).sig == Tuple{typeof(f), Any}         # only the untyped term method
    end
    @test hasmethod(LK.isAtomW, Tuple{UInt64}) && hasmethod(LK.isTaggedIntW, Tuple{UInt64})
end
