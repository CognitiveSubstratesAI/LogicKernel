# UPSTREAM: swipl-devel tests/core_lang/test_bips.pl @ bae881a24a3f
# CLASS: code
# COPYRIGHT: Copyright (C): Ulrich Neumerkel
#
# The units of swipl-devel's test_bips.pl that exercise what LogicKernel has ported so far —
# `ground/1` (our `is_ground`) and `compare/3` / `==/2` (our `compareStandard`, src/pl-prims.jl) —
# under upstream's own unit names, each case as upstream states it.
#
# NOT PORTED from this file, and why:
#   iso_8_4_2_3_a/b       compare/3 rejecting a non-atom / non-order first argument — Prolog
#                         argument checking; `compareStandard` returns the order instead of
#                         unifying it, so there is no argument to reject.
#   iso_8_11_8            stream positions at end of file — streams are not part of the kernel.
#   bips_occurs_check_error, arg, length, is_most_general_term — builtins not ported yet.
using Test, LogicKernel

const _BT = DefaultTerm
_ba(x::Symbol) = sym_term(_BT, x)
_bg(x) = gnd_term(_BT, x)
_bc(xs::_BT...) = mk_expr(_BT, _BT[xs...])
_bv(k) = mk_var(_BT, UInt64(k))
# Prolog's order atom from our -1/0/1, so each case reads like upstream's `Order == (<)`.
_border(a, b) = (:<, :(=), :>)[compareStandard(a, b) + 2]

@testset "bips" begin
    # PORT: test_bips.pl iso_8_3_10_4
    @testset "iso_8_3_10_4" begin
        @test is_ground(_bg(3))                                    # ground(3).
        @test !is_ground(_bc(_ba(:a), _bg(1), _bv(1)))             # ground(a(1,_)) fails.
    end

    # PORT: test_bips.pl iso_8_3_10
    @testset "iso_8_3_10" begin
        for _ in 0:20                                              # forall(between(0,20,_), …)
            @test is_ground(_bc(_ba(:-), _bg(1), _bg(2)))          # X=1, Y=2, ground(X-Y)
        end
        @test is_ground(_bc(_ba(:-), _bg(1), _bg(1)))              # ground(1-1)
    end

    # PORT: test_bips.pl iso_8_4_2_4
    @testset "iso_8_4_2_4" begin
        @test _border(_bg(3), _bg(5)) === :<                       # compare(Order, 3, 5)
        @test _border(_ba(:d), _ba(:d)) === :(=)                   # compare(Order, d, d)
        # upstream comments out `compare(Order, 3, 3.0)` as a "current disagreement" (ISO says >,
        # SWI's non-ISO mode puts the float first); the live differential pins SWI's behaviour.
    end

    # Compare must order by Unicode CODE POINT, not by UTF-16 code unit (upstream's comment): a
    # non-BMP code point is stored as a surrogate pair on 16-bit wchar_t platforms and would sort
    # below BMP code points U+DC00..U+FFFF. Julia compares UTF-8, which preserves code-point order.
    # PORT: test_bips.pl non_bmp_vs_bmp_unified
    @testset "non_bmp_vs_bmp_unified" begin
        @test _border(_ba(Symbol("\U0001D11E")), _ba(Symbol("豈"))) === :>     # U+1D11E > U+8C48
    end

    # PORT: test_bips.pl non_bmp_vs_bmp_compat
    @testset "non_bmp_vs_bmp_compat" begin
        @test _border(_ba(Symbol("\U0001D11E")), _ba(Symbol("豈"))) === :>     # U+1D11E > U+F900
    end

    # PORT: test_bips.pl non_bmp_vs_bmp_halfwidth
    @testset "non_bmp_vs_bmp_halfwidth" begin
        @test _border(_ba(Symbol("\U0001D11E")), _ba(Symbol("ﾀ"))) === :>     # U+1D11E > U+FF80
    end

    # PORT: test_bips.pl zero_codes
    # DIVERGES: upstream compares two ATOMS containing NUL; a Julia Symbol cannot contain NUL, so the case is ported on STRINGS, which SWI orders by the same character-code rule — the point (a NUL code does not end the comparison) is the same.
    @testset "zero_codes" begin
        @test _border(_bg("ကhello\0world"), _bg("ကhello")) === :>
    end
end

@testset "eq" begin
    # PORT: test_bips.pl eq_ff
    @testset "eq_ff" begin
        v = _bv(1)
        @test compareStandard(v, v, true) == 0                     # a :- A == A.
    end
end
