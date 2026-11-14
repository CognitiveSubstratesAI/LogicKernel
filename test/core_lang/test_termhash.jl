# ORIGINAL: properties of the term hashing port (src/pl-termhash.jl) that upstream's units do not state — its SHA-1 against FIPS 180 and Julia's SHA stdlib, the kept hash_compile defect, reproducibility across processes, digests on interface-only shapes.
# test/core_lang/test_termhash.jl — what the term hashes owe, beyond upstream's test_hash.pl.
#
# upstream's own units are ported in test/core_lang/test_hash.jl; the =@= differential against a
# live swipl is test/core_lang/test_variant_swipl.jl.
using Test, LogicKernel, Random, SHA
using LogicKernel:
    pl_variant_sha1,
    pl_variant_hash,
    pl_term_hash,
    is_variant_ptr,
    sha1_ctx,
    sha1_begin!,
    sha1_hash!,
    sha1_end!,
    hash_state,
    hash_init!,
    hash_compile!,
    hash_end,
    HASH_BLOCK_SIZE,
    MurmurHashAligned2,
    MurmurHashWide,
    _MurmurHashWide_blocks,
    POPCOUNT64,
    LSB64,
    MURMUR_SEED

# TERM TYPES PER CHUNK: ALL — the term layer: src/pl-termhash.jl
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _KT = lk_term_type(Union{Int64, Float64, String})
_ka(x::Symbol) = lk_sym(_KT, x)
_kg(x) = lk_gnd(_KT, x)
_kc(f::Symbol, xs::_KT...) = mk_expr(_KT, _KT[_ka(f), xs...])
_ke(xs::_KT...) = mk_expr(_KT, _KT[xs...])
_kv(k::Int) = mk_var(_KT, UInt64(k))

"The port's SHA-1 of `data`, fed in pieces of the given sizes (the rest in one piece), as hex."
function _ksha1(data::Vector{UInt8}, pieces::Vector{Int}=Int[])::String
    ctx = sha1_ctx()
    sha1_begin!(ctx)
    at = 0
    for n in pieces
        n = min(n, length(data) - at)
        sha1_hash!(data[(at + 1):(at + n)], n, ctx)
        at += n
    end
    sha1_hash!(data[(at + 1):end], length(data) - at, ctx)
    out = zeros(UInt8, 20)
    sha1_end!(out, ctx)
    return bytes2hex(out)
end

@testset "SHA-1 (Gladman, ported)" begin
    @testset "FIPS 180 test vectors" begin
        @test _ksha1(UInt8[]) == "da39a3ee5e6b4b0d3255bfef95601890afd80709"
        @test _ksha1(Vector{UInt8}("abc")) == "a9993e364706816aba3e25717850c26c9cd0d89d"
        @test _ksha1(
            Vector{UInt8}("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")
        ) == "84983e441c3bd26ebaae4aa1f95129e5e54670f1"
        @test _ksha1(
            Vector{UInt8}(
                "abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu"
            )
        ) == "a49b2446a02c645bf419f995b67091253a04a259"
        @test _ksha1(fill(UInt8('a'), 1_000_000), fill(1000, 999)) ==
            "34aa973cd4c4daa4f61eeb2bdbad27316534016f"
    end
    @testset "== Julia's SHA stdlib, every length to 300 and random pieces" begin
        rng = Xoshiro(20261003)
        bad = 0
        for len in [0:300; 1000; 4096; 4097]
            data = rand(rng, UInt8, len)
            pieces = [rand(rng, 0:70) for _ in 1:rand(rng, 0:8)]
            bad += _ksha1(data, pieces) != bytes2hex(SHA.sha1(data))
        end
        @test bad == 0
    end
end

"The incremental MurmurHash of `data`, fed in `pieces`."
function _kmur(data::Vector{UInt8}, pieces::Vector{Int})::UInt32
    s = hash_state()
    hash_init!(s)
    at = 0
    for n in pieces
        hash_compile!(s, view(data, (at + 1):(at + n)), n)
        at += n
    end
    return hash_end(s)
end

# ── MurmurHashAligned2 against upstream's own function: KNOWN ANSWERS ───────────────────────────────
# The kernel ports pl-hash.c's byte-wise body (src/pl-hash.jl); swipl on a little-endian host runs
# the aligned one, which upstream says gives the same hash. Checked by the divergence audit
# (2026-10-06): upstream's aligned body, compiled from pl-hash.c at bae881a2, for every length 0..40
# at four alignments and three seeds, gives these 492 lines, `seed offset length hash` — their
# SHA-1, and some of the values themselves.
@testset "MurmurHashAligned2 == upstream's, 492 known answers (pl-hash.c at bae881a2)" begin
    buf = UInt8[UInt8((i * 37 + 11) % 256) for i in 0:63]
    io = IOBuffer()
    for seed in (0x1a3be34a, 0x00000000, 0xdeadbeef), off in 0:3, len in 0:40
        h = MurmurHashAligned2(buf[(off + 1):end], len, UInt32(seed))
        println(io, Int(seed), " ", off, " ", len, " ", Int(h))
    end
    @test bytes2hex(sha1(take!(io))) == "02deabd1d66695c040d213923b53c99b69911416"
    for (seed, off, len, want) in (
        (0x1a3be34a, 0, 0, 1747181055), (0x1a3be34a, 0, 1, 2329118897),
        (0x1a3be34a, 0, 7, 472877332), (0x1a3be34a, 0, 8, 1224129436),
        (0x1a3be34a, 0, 13, 4015555493), (0x00000000, 1, 5, 1757487611),
        (0xdeadbeef, 3, 40, 931406165)
    )
        @test MurmurHashAligned2(buf[(off + 1):end], len, UInt32(seed)) == want
    end
    @test MURMUR_SEED == 0x1a3be34a                              # pl-hash.h
end

# ── MurmurHashWide (pl-hash.c, NEW at swipl-devel cf6960c2) ────────────────────────────────────────
# TARGET-ONLY: pin when the oracle moves to cf6960c2 (the pin 18168e62 has no MurmurHashWide); (swipl-devel cf6960c2 pl-hash.c:219-266).
# The expected values are the TARGET's own C: src/pl-hash.c at cf6960c2 compiled stand-alone (-DNO_SWIPL, little-endian,
# 4-byte wchar_t) on the seven texts and three seeds below. Its other two arms — the big-endian one and the 2-byte
# `wchar_t` one over UTF-16 units — gave the SAME hashes for the same code points, which is the function's point.
const _MW_CASES = (
    (UInt32[], ((440132426, 1747181055), (0, 0), (3735928559, 1552874934))),
    (UInt32[0x61], ((440132426, 859932490), (0, 960914556), (3735928559, 4293966780))),
    (
        UInt32[0x61, 0x62, 0x63],
        ((440132426, 2765092511), (0, 1706470512), (3735928559, 631187916))
    ),
    (UInt32[0x1f600], ((440132426, 2759298159), (0, 1379774625), (3735928559, 1715006877))),
    (
        UInt32[0x20ac, 0x10000, 0x10ffff, 0x41],
        ((440132426, 710218905), (0, 1182717783), (3735928559, 2134004924))
    ),
    (
        UInt32[
            0x41,
            0x142,
            0x243,
            0x344,
            0x445,
            0x546,
            0x647,
            0x748,
            0x849,
            0x94a,
            0xa4b,
            0xb4c,
            0xc4d,
            0xd4e,
            0xe4f,
            0xf50,
            0x1051
        ],
        ((440132426, 998673622), (0, 3163429894), (3735928559, 4238135819))
    ),
    (
        UInt32[
            0x10000,
            0x11111,
            0x12222,
            0x13333,
            0x14444,
            0x15555,
            0x16666,
            0x17777,
            0x18888
        ],
        ((440132426, 1914875778), (0, 2682305984), (3735928559, 499226922))
    )
)
"The UTF-16 units of the code points `cps` (a code point above 0xffff is a surrogate pair)."
function _mw_utf16(cps::Vector{UInt32})::Vector{UInt16}
    out = UInt16[]
    for c in cps
        if c >= 0x10000
            c -= 0x10000
            push!(out, UInt16(0xd800 + (c >> 10)), UInt16(0xdc00 + (c & 0x3ff)))
        else
            push!(out, UInt16(c))
        end
    end
    return out
end

@testset "MurmurHashWide == the target's pl-hash.c (7 texts x 3 seeds)" begin
    for (cps, wants) in _MW_CASES, (seed, want) in wants
        @test MurmurHashWide(cps, 4 * length(cps), UInt32(seed)) == UInt32(want)
        # the UTF-16 units give the hash of the code points (the 2-byte `wchar_t` arm)
        u16 = _mw_utf16(cps)
        @test MurmurHashWide(u16, 2 * length(u16), UInt32(seed)) == UInt32(want)
        # the portable arm over 4-byte code points is the aligned arm's hash (upstream's comment)
        @test _MurmurHashWide_blocks(cps, 4 * length(cps), UInt32(seed)) == UInt32(want)
    end
end

@testset "MurmurHashWide: a `len` that is no multiple of 4 is hashed as bytes (the aligned arm)" begin
    cps = _MW_CASES[6][1]
    for (len, want) in (
        (1, 1398196891),
        (2, 2279955291),
        (3, 1587262217),
        (5, 2279061976),
        (6, 1304952242),
        (7, 2215990012)
    )
        @test MurmurHashWide(cps, len, MURMUR_SEED) == UInt32(want)
    end
    # `len` bytes only: the units past it are not read (859932490 is the target's value for [0x61])
    abc32 = UInt32[0x61, 0x62, 0x63]
    abc16 = UInt16[0x61, 0x62, 0x63]
    @test MurmurHashWide(abc32, 4, MURMUR_SEED) == 859932490
    @test MurmurHashWide(abc16, 2, MURMUR_SEED) == 859932490
end

@testset "MurmurHashWide: a lone surrogate unit is a code point of its own, a pair is one" begin
    # the expected values are the target's, from its 2-byte `wchar_t` arm and from its 4-byte arm
    pair = UInt16[0xd83d, 0xde00]                       # U+1F600
    @test MurmurHashWide(pair, 4, MURMUR_SEED) == 2759298159
    @test MurmurHashWide(UInt32[0x1f600], 4, MURMUR_SEED) == 2759298159
    lone_hi = UInt16[0xd83d, 0x41]                      # high surrogate, then a plain unit: two code points
    @test MurmurHashWide(lone_hi, 4, MURMUR_SEED) == 417663900
    @test MurmurHashWide(UInt32[0xd83d, 0x41], 8, MURMUR_SEED) == 417663900
    lone_lo = UInt16[0xde00, 0xd83d]                    # low surrogate first: no pair either
    @test MurmurHashWide(lone_lo, 4, MURMUR_SEED) == 804242943
    @test MurmurHashWide(UInt32[0xde00, 0xd83d], 8, MURMUR_SEED) == 804242943
    cut = UInt16[0x41, 0xd83d]                          # high surrogate last: nothing to pair with
    @test MurmurHashWide(cut, 4, MURMUR_SEED) == 859116668
    @test MurmurHashWide(UInt32[0x41, 0xd83d], 8, MURMUR_SEED) == 859116668
    # the edges of the two ranges: a pair is a unit in d800..dbff then one in dc00..dfff
    @test MurmurHashWide(UInt16[0xd800, 0xdc00], 4, MURMUR_SEED) == 3421940055     # U+10000
    @test MurmurHashWide(UInt32[0x10000], 4, MURMUR_SEED) == 3421940055
    @test MurmurHashWide(UInt16[0xdbff, 0xdfff], 4, MURMUR_SEED) == 3347687709     # U+10FFFF
    @test MurmurHashWide(UInt32[0x10ffff], 4, MURMUR_SEED) == 3347687709
    @test MurmurHashWide(UInt16[0xd83d, 0xe000], 4, MURMUR_SEED) == 3415968347     # e000 is no low surrogate
    @test MurmurHashWide(UInt32[0xd83d, 0xe000], 8, MURMUR_SEED) == 3415968347
    @test MurmurHashWide(UInt16[0xdc00, 0xdc00], 4, MURMUR_SEED) == 270663950      # dc00 is no high surrogate
    @test MurmurHashWide(UInt32[0xdc00, 0xdc00], 8, MURMUR_SEED) == 270663950
    @test MurmurHashWide(UInt16[0xd7ff, 0xdc00], 4, MURMUR_SEED) == 1653718646     # d7ff is no high surrogate
    @test MurmurHashWide(UInt32[0xd7ff, 0xdc00], 8, MURMUR_SEED) == 1653718646
end

# ── POPCOUNT64 and LSB64 (pl-inline.h, NEW at swipl-devel cf6960c2) ─────────────────────────────────
# TARGET-ONLY: pin when the oracle moves to cf6960c2. Hand-written from the target's C (the bit counts of the
# literals are exact), plus the target's own portable shift ladder (pl-inline.h, the arm without `__builtin_ctzll`)
# as the reference for LSB64 on pseudo-random words. They live in this file with the hashes that use them upstream
# (atom hashing, the generational GC's bitmaps), not because the term hash does.
"The portable arm of upstream's LSB64, written out (pl-inline.h:347-355)."
function _lsb64_ladder(i::UInt64)::UInt32
    j = UInt32(0)
    if (i & 0xffffffff) == 0
        i >>= 32
        j += 32
    end
    if (i & 0xffff) == 0
        i >>= 16
        j += 16
    end
    if (i & 0xff) == 0
        i >>= 8
        j += 8
    end
    if (i & 0xf) == 0
        i >>= 4
        j += 4
    end
    if (i & 0x3) == 0
        i >>= 2
        j += 2
    end
    if (i & 0x1) == 0
        j += 1
    end
    return j
end

@testset "POPCOUNT64: the number of set bits" begin
    for (i, want) in (
        (0x0000000000000000, 0), (0x0000000000000001, 1), (0x00000000000000ff, 8),
        (0x8000000000000001, 2), (0x5555555555555555, 32), (0xffffffffffffffff, 64),
        (0x0123456789abcdef, 32)
    )
        @test POPCOUNT64(i) === UInt32(want)
    end
    @test all(k -> POPCOUNT64(UInt64(1) << k) == 1, 0:63)
    @test all(k -> POPCOUNT64(typemax(UInt64) >> k) == 64 - k, 0:63)
end

@testset "LSB64: the index of the lowest set bit" begin
    for (i, want) in (
        (0x0000000000000001, 0), (0x0000000000000008, 3), (0x00000000ffff0000, 16),
        (0x0000000100000000, 32), (0x00000a0000000000, 41), (0x8000000000000000, 63),
        (0xffffffffffffffff, 0), (0x0000000000000006, 1)
    )
        @test LSB64(i) === UInt32(want)
    end
    @test all(k -> LSB64(UInt64(1) << k) == k, 0:63)
    # every bit above the lowest one is ignored
    @test all(k -> LSB64((typemax(UInt64) >> k) << k) == k, 0:63)
    rng = Random.MersenneTwister(20261114)
    for _ in 1:2000
        i = rand(rng, UInt64) >> rand(rng, 0:62) << rand(rng, 0:62)
        i == 0 && continue
        @test LSB64(i) == _lsb64_ladder(i)
    end
end

@testset "incremental MurmurHash (hash_state)" begin
    @testset "within one block it is MurmurHashAligned2 of the bytes" begin
        rng = Xoshiro(7)
        for len in 0:256
            data = rand(rng, UInt8, len)
            @test _kmur(data, [len]) == MurmurHashAligned2(data, len, MURMUR_SEED)
        end
    end
    # Upstream's fix e02d93f (SWI-Prolog/swipl-devel#1538; see `hash_compile!`): a piece that
    # straddles a block is hashed whole. Until it the piece was copied from its START for every
    # block, so its tail was never hashed and the two texts below — upstream's own, test_hash.pl
    # long_atom — hashed alike when added in one piece.
    @testset "a straddling piece is hashed whole, however the bytes are cut (e02d93f)" begin
        a = vcat(fill(UInt8('a'), 300), Vector{UInt8}("xxxxxxxxxx"))
        b = vcat(fill(UInt8('a'), 300), Vector{UInt8}("yyyyyyyyyy"))
        @test _kmur(a, [length(a)]) != _kmur(b, [length(b)])        # one straddling piece
        @test _kmur(a, fill(1, length(a))) != _kmur(b, fill(1, length(b)))  # byte by byte
        # the same bytes hash alike in one piece, byte by byte, and in uneven pieces that end
        # before, on and after a block boundary (no total here is a whole number of blocks above
        # one: there the last block is flushed or not by how the pieces fall, upstream's as well)
        rng = Xoshiro(11)
        for len in (HASH_BLOCK_SIZE - 1, HASH_BLOCK_SIZE, HASH_BLOCK_SIZE + 1, 310, 1000)
            data = rand(rng, UInt8, len)
            whole = _kmur(data, [len])
            @test whole == _kmur(data, fill(1, len))
            @test whole == _kmur(data, [7, len - 7])
            @test whole == _kmur(data, [len - 1, 1])
            len > HASH_BLOCK_SIZE &&
                @test whole == _kmur(data, [HASH_BLOCK_SIZE, len - HASH_BLOCK_SIZE])
        end
    end
end

@testset "term_hash" begin
    x = _kv(1)
    @test pl_term_hash(x) === nothing                           # non-ground: no hash
    @test pl_term_hash(_kc(:f, _ka(:a), x)) === nothing
    @test pl_term_hash(_kc(:f, _kc(:g, x))) === nothing
    @test pl_term_hash(_ke(x, _ka(:a))) === nothing             # a variable head
    t1 = _kc(:f, _ka(:a), _kg(1), _kc(:g, _kg("s"), _kg(2.5)))
    t2 = _kc(:f, _ka(:a), _kg(1), _kc(:g, _kg("s"), _kg(2.5)))
    @test pl_term_hash(t1) isa UInt32 && pl_term_hash(t1) == pl_term_hash(t2)
    @test pl_term_hash(_kc(:f, _ka(:a))) != pl_term_hash(_kc(:f, _ka(:b)))
    @test pl_term_hash(_kc(:f, _ka(:a))) != pl_term_hash(_kc(:g, _ka(:a)))
    @test pl_term_hash(_kc(:f, _kc(:g, _ka(:a)))) != pl_term_hash(_kc(:f, _ka(:g), _ka(:a)))
    @test pl_term_hash(_kc(:f, _kc(:g, _ka(:a)))) != pl_term_hash(_kc(:f, _kc(:g, _ka(:b))))
end

"`f(a,X,Y,X)`, `g(1,2.5,\"s\",h(Z))`, `aap` and a headless compound — the terms the other process builds too."
function _kterms()::Vector{_KT}
    x, y, z = _kv(1), _kv(2), _kv(3)
    return [
        _kc(:f, _ka(:a), x, y, x),
        _kc(:g, _kg(1), _kg(2.5), _kg("s"), _kc(:h, z)),
        _ka(:aap),
        _ke(_kc(:c, x), y)
    ]
end

@testset "digests are the same in another process" begin
    here = [
        (pl_variant_sha1(t), pl_variant_hash(t), something(pl_term_hash(t), UInt32(0))) for
        t in _kterms()
    ]
    code = """
    using LogicKernel
    using LogicKernel: pl_variant_sha1, pl_variant_hash, pl_term_hash
    include($(repr(joinpath(@__DIR__, "..", "term_under_test.jl"))))
    T = lk_term_type(Union{Int64, Float64, String})
    a(x) = lk_sym(T, x); g(x) = lk_gnd(T, x); v(k) = mk_var(T, UInt64(k))
    c(f, xs...) = mk_expr(T, T[a(f), xs...]); e(xs...) = mk_expr(T, T[xs...])
    x, y, z = v(1), v(2), v(3)
    for t in [c(:f, a(:a), x, y, x), c(:g, g(1), g(2.5), g("s"), c(:h, z)), a(:aap), e(c(:c, x), y)]
        println(pl_variant_sha1(t), " ", pl_variant_hash(t), " ", something(pl_term_hash(t), UInt32(0)))
    end
    """
    cmd = `$(Base.julia_cmd()) --startup-file=no --project=$(pkgdir(LogicKernel)) -e $code`
    there = split(strip(read(pipeline(cmd; stdin=devnull), String)), '\n')
    @test length(there) == length(here)                         # the other process answered
    @test there == ["$s $h $t" for (s, h, t) in here]
    @test here[1][3] == 0 && here[3][3] != 0                    # f(a,X,Y,X) has none; aap has one
end

# Shapes only the interface has — variable heads, compound heads, no children — have no swipl
# oracle; the digests must still agree with is_variant_ptr on every pair.
@testset "digest equality ⇔ =@= on interface-only shapes" begin
    x, y = _kv(1), _kv(2)
    terms = [
        _ke(), _ke(x), _ke(y), _ke(x, x), _ke(x, y), _ke(_ka(:f)), _ke(_ka(:f), x),
        _ke(_kc(:f, x), x), _ke(_kc(:f, x), y), _ke(_kc(:f, y), x), _ke(_ke(), _ka(:a)),
        _ke(_kg(1), _ka(:a)), _kc(:f, _ke(x, x)), _kc(:f, _ke(y, y)), _kc(:f, _ke(x, y)),
        _ke(x, _kc(:f, y)), _ke(y, _kc(:f, x)), _ke(x, _kc(:f, x))
    ]
    n = length(terms)
    bad = String[]
    variants = 0
    for i in 1:n, j in 1:n
        v = is_variant_ptr(terms[i], terms[j])
        variants += v
        s = pl_variant_sha1(terms[i]) == pl_variant_sha1(terms[j])
        h = pl_variant_hash(terms[i]) == pl_variant_hash(terms[j])
        (v == s && (!v || h)) ||
            push!(bad, "$i vs $j: =@= $v, sha1 equal $s, hash equal $h")
    end
    foreach(b -> println(stderr, "  ", b), bad)
    @test isempty(bad)
    @test variants > n                              # some distinct terms are variants
end

# A grounded value contributes its `gnd_key`, which follows the reference type's `gnd_equal` — SWI's
# identity — so values that are `==` but not identical hash apart, as upstream's do: `1 =@= 1.0`
# fails and their digests differ. (Until 2026-10-03 the reference type matched by `==` and these
# shared a digest; this testset pinned that divergence the other way.)
@testset "== but not identical grounded values: not variants, different digests (as SWI)" begin
    @test !is_variant_ptr(_kg(1), _kg(1.0))
    @test pl_variant_sha1(_kg(1)) != pl_variant_sha1(_kg(1.0))
    @test pl_variant_hash(_kg(1)) != pl_variant_hash(_kg(1.0))
    @test !is_variant_ptr(_kc(:f, _kg(0.0)), _kc(:f, _kg(-0.0)))
    @test pl_variant_sha1(_kc(:f, _kg(0.0))) != pl_variant_sha1(_kc(:f, _kg(-0.0)))
    @test pl_term_hash(_kg(1)) != pl_term_hash(_kg(1.0))
end

# SWI-7's `[]` against the text atom `'[]'`, probed in swipl 10.1.16: term_hash hashes an atom by
# its TEXT (pl-termhash.c `primitiveHashValue`: `atomValue(w)->hash_value`), so the two share a
# term_hash; the variant hashes also feed in the blob TYPE's name (`variant_sha1`:
# `HASH(av->type->name, …)` — "text" against "reserved_symbol"), so they hash apart.
@testset "[] and '[]': one term_hash, two variant digests (as swipl)" begin
    nil, qnil = mk_nil(_KT), _ka(Symbol("[]"))
    @test pl_term_hash(nil) == pl_term_hash(qnil)
    @test pl_term_hash(_kc(:f, nil)) == pl_term_hash(_kc(:f, qnil))
    @test pl_variant_sha1(nil) != pl_variant_sha1(qnil)
    @test pl_variant_hash(nil) != pl_variant_hash(qnil)
    @test pl_variant_sha1(_kc(:f, nil)) != pl_variant_sha1(_kc(:f, qnil))
    @test !is_variant_ptr(nil, qnil)
end

# TARGET-ONLY: pin when the oracle moves to cf6960c2 (swipl-devel cf6960c2 pl-termhash.c:177-186, 640, 652). The expectation is written by hand from the TARGET's pl-termhash.c
# `variant_sha1` and `HASH_VAR` (the local swipl is the pin, which hashes the variable's marked cell, a cell-layout word): a
# numbered variable is hashed as "V" and `le64(valTagged(*p))`, which is its number — 0 for the first variable met, 1 for the
# second, a repeat keeps its number. The digests are recomputed here with Julia's SHA stdlib and MurmurHashAligned2 from the
# bytes the walk writes (the digest is not swipl's value, file-wide DIVERGES 1; only the bytes of a variable are the target's).
@testset "SYNC-E: a variable is hashed by its number (pl-termhash.c HASH_VAR, swipl-devel cf6960c2, TARGET-ONLY)" begin
    le64(w) = UInt8[((UInt64(w) >> (8 * j)) % UInt8) for j in 0:7]
    vword(n) = vcat(UInt8['V'], le64(n))
    sha(bytes) = bytes2hex(SHA.sha1(bytes))
    mur(bytes) = Int(
        MurmurHashAligned2(bytes, length(bytes), MURMUR_SEED) &
        LogicKernel.PLMAXTAGGEDINT32
    )
    x, y = _kv(1), _kv(2)
    @test pl_variant_sha1(x) == sha(vword(0))
    @test pl_variant_hash(x) == mur(vword(0))
    @test pl_variant_sha1(_kv(7)) == pl_variant_sha1(x)           # the number is not the variable's own key
    t = _kc(:f, x, y, x)
    head = vcat(UInt8['T'], le64(LogicKernel.sym_hash(LogicKernel.child(t, 1))), le64(3))
    want = vcat(head, vword(0), vword(1), vword(0))
    @test pl_variant_sha1(t) == sha(want)
    @test pl_variant_hash(t) == mur(want)
    @test pl_variant_sha1(_kc(:f, y, x, y)) == pl_variant_sha1(t)   # a variant: the same numbers
    @test pl_variant_sha1(_kc(:f, x, x, y)) != pl_variant_sha1(t)
end
