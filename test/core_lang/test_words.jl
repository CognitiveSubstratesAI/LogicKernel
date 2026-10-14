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
#     reads as 8), and pl-gmp.h's size words (sign, the rational bit).
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
    @test LK.STG_INLINE == LK.STG_STATIC && LK.MARK_MASK == 0x20 && LK.FIRST_MASK == 0x40
    @test LK.TAG_MASK == 0x7 && LK.STG_MASK == 0x18 && LK.LMASK_BITS == 7
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
    last = Int(typemax(UInt64) >> LK.LMASK_BITS)                   # 2^57 - 1
    for p in (1, 2^27, last),
        ts in (LK.TAG_REFERENCE | LK.STG_GLOBAL, LK.TAG_REFERENCE | LK.STG_LOCAL,
            LK.TAG_FLOAT | LK.STG_GLOBAL, LK.TAG_STRING | LK.STG_LOCAL)

        w = LK.consPtr(p, ts)
        @test LK.valPtr(w) == p && LK.tagex(w) == ts
    end
    @test LK.makeRefG(5) == (UInt64(5) << 7) | LK.TAG_REFERENCE | LK.STG_GLOBAL
    @test LK.makeRefLok(5) == (UInt64(5) << 7) | LK.TAG_REFERENCE | LK.STG_LOCAL
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
    @test LK.PLMAXTAGGEDINT == 2^56 - 1 && LK.PLMINTAGGEDINT == -2^56
    @test LK.consUInt(UInt64(7)) == (UInt64(7) << 7) | LK.TAG_INTEGER
    @test LK.valUInt(LK.consUInt(UInt64(2)^56)) == UInt64(2)^56
end

@testset "the indirect headers and pl-gmp.h's size words" begin
    # mkIndHdr(size, tag) = size << (LMASK_BITS+PADBITS) | tag | STG_LOCAL
    for n in (1, 2, 1000, 2^40), t in (LK.TAG_FLOAT, LK.TAG_INTEGER, LK.TAG_STRING)
        h = LK.mkIndHdr(n, t)
        @test LK.wsizeofInd(h) == n && LK.tag(h) == t && LK.storage(h) == LK.STG_LOCAL
    end
    # padHdr: the pad bits, 0 meaning sizeof(word)
    for pad in 0:7
        h = LK.mkBlobHdr(3, pad, LK.TAG_STRING)
        @test LK.padHdr(h) == (pad == 0 ? 8 : pad) && LK.wsizeofInd(h) == 3
    end
    # mpz_size_stack(sz) = (word)sz<<1 & ~MP_RAT_MASK; mpq_size_stack sets MP_RAT_MASK;
    # mpz_stack_size(w) = (int)w >> 1
    for sz in Int32.((0, 1, 2, 17, -1, -17, typemax(Int32) >> 1, -(typemax(Int32) >> 1)))
        z = LK.mpz_size_stack(sz)
        q = LK.mpq_size_stack(sz)
        @test z & LK.MP_RAT_MASK == 0 && q & LK.MP_RAT_MASK == 1
        @test LK.mpz_stack_size(z) == sz && LK.mpq_stack_size(q) == sz
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
