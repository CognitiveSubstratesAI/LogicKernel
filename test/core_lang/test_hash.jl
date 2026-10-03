# UPSTREAM: swipl-devel tests/core_lang/test_hash.pl @ bae881a24a3f
# CLASS: code
# COPYRIGHT: Copyright (c)  2010-2025, University of Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# swipl-devel's test_hash.pl — `variant_sha1/2`, `variant_hash/2` and `term_hash/2`, our
# `pl_variant_sha1`, `pl_variant_hash` and `pl_term_hash` (src/pl-termhash.jl) — under upstream's
# unit names; a name upstream uses more than once is used as often here.
#
# DIVERGES (file-wide): term_hash2's units pin SWI's hash VALUES (one per platform). The port hashes an atom's
# `sym_hash` and a grounded value's `gnd_key` where SWI hashes names and bytes (src/pl-termhash.jl,
# DIVERGES 1), so it cannot produce them; each unit asserts what the pinned value stands for — the
# hash exists, is a 32-bit integer, and (compound_2/compound_3) a shared subterm hashes as its
# copy does. That the values are REPRODUCIBLE — the same in another process — is checked in
# test/core_lang/test_termhash.jl.
#
# NOT PORTED, and why:
#   variant_sha1: cycle ×2, cycle_variant, cycle_distinct, cycle_no_collision, cycle_attvar,
#                 cycle_attvar_hash — rational trees; interface terms are finite.
#   variant_sha1: attvar ×2 — attributed variables do not exist in the kernel.
#   term_hash2:   simple_3 is ported over a `Term{Union{Int64, BigInt}}`: the default term type has
#                 no big integers.
using Test, LogicKernel
using LogicKernel: pl_variant_sha1, pl_variant_hash, pl_term_hash

const _HT = DefaultTerm
_ha(x::Symbol) = sym_term(_HT, x)
_hg(x) = gnd_term(_HT, x)
_hc(f::Symbol, xs::_HT...) = mk_expr(_HT, _HT[_ha(f), xs...])
let n = UInt64(0)
    global _hv() = mk_var(_HT, n += 1)
end

@testset "variant_sha1" begin
    # PORT: test_hash.pl atom
    @testset "atom" begin
        hash = pl_variant_sha1(_ha(:this_is_an_atom))
        @test length(hash) == 40                        # atom_length(Hash, 40)
        @test all(c -> c in "0123456789abcdef", hash)
    end
    # PORT: test_hash.pl vars
    @testset "vars" begin
        a, b = _hv(), _hv()
        @test pl_variant_sha1(_hc(:x, a)) == pl_variant_sha1(_hc(:x, b))
    end
    # PORT: test_hash.pl variant
    @testset "variant" begin
        a, b = _hv(), _hv()
        @test pl_variant_sha1(_hc(:x, a, a)) != pl_variant_sha1(_hc(:x, a, b))
    end
    # PORT: test_hash.pl shared
    @testset "shared" begin
        c = _hv()
        a = _hc(:x, c)                                  # A = x(C)
        @test pl_variant_sha1(_hc(:x, a, a)) ==
            pl_variant_sha1(_hc(:x, _hc(:x, c), _hc(:x, c)))
    end
    # PORT: test_hash.pl float
    @testset "float" begin                              # fail: 1.0 and 2.0 differ
        @test pl_variant_sha1(_hg(1.0)) != pl_variant_sha1(_hg(2.0))
    end
end

@testset "variant_hash" begin
    # PORT: test_hash.pl variant
    @testset "variant" begin
        a, b = _hv(), _hv()
        @test pl_variant_hash(_hc(:x, a, a)) != pl_variant_hash(_hc(:x, a, b))
    end
    # DIVERGES: upstream's B is attributed (`freeze(B, true)`) and variant_hash/2 hashes it as a
    # plain variable; the kernel has no attributed variables, so B is plain and the unit checks
    # the variant equality that remains.
    # PORT: test_hash.pl variant
    @testset "variant" begin
        a, b = _hv(), _hv()
        @test pl_variant_hash(_hc(:x, a, a)) == pl_variant_hash(_hc(:x, b, b))
    end
    # PORT: test_hash.pl variant
    @testset "variant" begin
        a, b = _hv(), _hv()
        @test pl_variant_hash(_hc(:x, a, _hv())) == pl_variant_hash(_hc(:x, b, _hv()))
    end
end

@testset "term_hash2" begin
    _is_hash(x) = x isa UInt32
    # PORT: test_hash.pl simple_1
    @testset "simple_1" begin
        @test _is_hash(pl_term_hash(_ha(:aap)))
    end
    # PORT: test_hash.pl simple_2
    @testset "simple_2" begin                           # small int
        @test _is_hash(pl_term_hash(_hg(42)))
    end
    # PORT: test_hash.pl simple_3
    @testset "simple_3" begin                           # Big int
        BT = Term{Union{Int64, BigInt}}
        num = BigInt(366454713) << 64                   # Num is 366454713<<64
        x = pl_term_hash(gnd_term(BT, num))
        @test _is_hash(x)
        @test x == pl_term_hash(gnd_term(BT, BigInt(366454713) << 64))     # an equal copy
    end
    # PORT: test_hash.pl simple_4
    @testset "simple_4" begin
        @test _is_hash(pl_term_hash(_hg(Float64(pi))))  # A is pi
    end
    # PORT: test_hash.pl simple_5
    @testset "simple_5" begin
        @test _is_hash(pl_term_hash(_hg("hello world")))
    end
    # PORT: test_hash.pl compound_1
    @testset "compound_1" begin
        @test _is_hash(pl_term_hash(_hc(:hello, _ha(:world))))
    end
    # PORT: test_hash.pl compound_2
    @testset "compound_2" begin                         # hello(A, A) with A = x(a) …
        a = _hc(:x, _ha(:a))
        @test pl_term_hash(_hc(:hello, a, a)) ==
            pl_term_hash(_hc(:hello, _hc(:x, _ha(:a)), _hc(:x, _ha(:a))))
    end
    # PORT: test_hash.pl compound_3
    @testset "compound_3" begin                         # … hashes as hello(x(a), x(a))
        h = pl_term_hash(_hc(:hello, _hc(:x, _ha(:a)), _hc(:x, _ha(:a))))
        @test _is_hash(h)
        a = _hc(:x, _ha(:a))
        @test h == pl_term_hash(_hc(:hello, a, a))
    end
end
