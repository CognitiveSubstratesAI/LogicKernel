# ORIGINAL: tests of the reference term type Term{G}; no swipl-devel counterpart.
# test/core_lang/test_default_term.jl — what the DEFAULT term type promises beyond the interface: its
# constructors, DefaultTerm, `==`/`hash` following identity, printing, and that comparing deep terms
# does not recurse (the ported `do_compare` walks an explicit agenda).
using Test, LogicKernel

const _TT = DefaultTerm
_s(x) = sym_term(_TT, x)
_g(x) = gnd_term(_TT, x)
_e(xs::_TT...) = mk_expr(_TT, _TT[xs...])

@testset "default term type" begin
    @testset "constructors cache what the interface reads" begin
        v = mk_var(_TT, UInt64(3))
        @test !is_ground(_e(_s(:f), v)) && is_ground(_e(_s(:f), _g(1)))
        @test is_ground(_e()) && !is_ground(_e(_e(_e(v))))
        @test gnd_key(_g(1)) == gnd_value_key(1) && gnd_key(_g("x")) == gnd_value_key("x")
        @test sym_key(_s(:foo)) == sym_key(_s(Symbol("foo")))       # the same interned symbol
    end

    @testset "sym_hash is the same in another process — the index's keys are reproducible" begin
        names = ["a", "foo", "a b", "α", "p1", "[|]", ""]
        here = [sym_hash(_s(Symbol(n))) for n in names]
        @test allunique(here)                       # on this sample (collisions are allowed)
        code =
            "using LogicKernel; for n in $(repr(names)) " *
            "println(sym_hash(sym_term(DefaultTerm, Symbol(n)))) end"
        cmd = `$(Base.julia_cmd()) --startup-file=no --project=$(pkgdir(LogicKernel)) -e $code`
        there = parse.(
            UInt64, split(strip(read(pipeline(cmd; stdin=devnull), String)), '\n')
        )
        @test length(there) == length(names)        # the other process answered for every name
        @test there == here
    end

    # SWI-Prolog 10.1.16, measured 2026-10-03: `1 = 1.0` fails, `0.0 = -0.0` fails, two NaNs from
    # `is nan` unify, and big integers unify by value.
    @testset "gnd_equal and gnd_value_key follow SWI's identity" begin
        @test !gnd_equal(_g(1), _g(1.0))                            # 1 = 1.0 fails
        @test !gnd_equal(_g(0.0), _g(-0.0))                         # floats by bit pattern
        @test gnd_equal(_g(NaN), _g(NaN))                           # an identical NaN unifies
        @test gnd_equal(_g(2), _g(2)) && gnd_equal(_g("a"), _g("a"))
        @test !gnd_equal(_g("a"), _g("b")) && !gnd_equal(_g(1), _g("1"))
        BT = Term{Union{Int64, BigInt}}
        @test gnd_equal(gnd_term(BT, 5), gnd_term(BT, big(5)))     # one integer type
        @test compareStandard(gnd_term(BT, 5), gnd_term(BT, big(5))) == 0
        @test gnd_value_key(5) == gnd_value_key(big(5))
        @test gnd_value_key(1) != gnd_value_key(1.0)                # unify apart, key apart
        @test gnd_value_key(0.0) != gnd_value_key(-0.0)
        @test gnd_value_key(true) != gnd_value_key(1)
        @test gnd_value_key('a') !== nothing && gnd_value_key(:s) !== nothing
        @test gnd_value_key([1]) === nothing && gnd_value_key((1, 2)) === nothing
        @test gnd_value_key(1 + 0im) === nothing
    end

    @testset "== and hash follow identity in the standard order" begin
        ts = (_s(:a), _s(:a), _g(1), _g(1.0), _g(0.0), _g(-0.0), _g("a"),
            mk_var(_TT, UInt64(1)),
            mk_var(_TT, UInt64(1)), _e(_s(:f), _g(1)), _e(_s(:f), _g(1)),
            _e(_s(:f), _g(1.0)))
        ok = true
        for a in ts, b in ts
            ok &= (a == b) == (compareStandard(a, b) == 0)
            (a == b) && (ok &= hash(a) == hash(b))
        end
        @test ok
        @test length(Set(ts)) == 9          # :a 1 1.0 0.0 -0.0 "a" _G1 (f 1) (f 1.0) — twins collapse
    end

    @testset "printing" begin
        @test repr(_e(_s(:f), _g(1), _g("s"), mk_var(_TT, UInt64(7)), _e())) ==
            "(f 1 \"s\" _G7 ())"
    end

    @testset "comparing deep terms does not recurse" begin
        deep(leaf) = (
            t=leaf;
            for _ in 1:200_000
                t = _e(_s(:f), t)
            end;
            t
        )
        a, b = deep(_g(1)), deep(_g(2))
        @test compareStandard(a, b) == -1                # decided 200 000 levels down, no stack overflow
        @test compareStandard(a, deep(_g(1))) == 0
    end
end
