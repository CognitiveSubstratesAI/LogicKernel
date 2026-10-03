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
    MurmurHashAligned2,
    MURMUR_SEED

const _KT = DefaultTerm
_ka(x::Symbol) = sym_term(_KT, x)
_kg(x) = gnd_term(_KT, x)
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

@testset "incremental MurmurHash (hash_state)" begin
    @testset "within one block it is MurmurHashAligned2 of the bytes" begin
        rng = Xoshiro(7)
        for len in 0:256
            data = rand(rng, UInt8, len)
            @test _kmur(data, [len]) == MurmurHashAligned2(data, len, MURMUR_SEED)
        end
    end
    # The defect src/pl-termhash.jl keeps (see `hash_compile!`): a piece that straddles a block is
    # copied from its START twice, so its tail is never hashed. Measured on swipl 10.1.16 through
    # variant_hash/2 on two long atoms; here it is pinned at the function, both ways.
    @testset "UPSTREAM DEFECT kept: a straddling piece's tail is not hashed" begin
        a = vcat(fill(UInt8('a'), 300), Vector{UInt8}("xxxxxxxxxx"))
        b = vcat(fill(UInt8('a'), 300), Vector{UInt8}("yyyyyyyyyy"))
        @test _kmur(a, [length(a)]) == _kmur(b, [length(b)])        # one straddling piece
        @test _kmur(a, fill(1, length(a))) != _kmur(b, fill(1, length(b)))  # byte by byte
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
    T = DefaultTerm
    a(x) = sym_term(T, x); g(x) = gnd_term(T, x); v(k) = mk_var(T, UInt64(k))
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
