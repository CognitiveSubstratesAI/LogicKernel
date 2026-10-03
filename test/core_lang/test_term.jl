# UPSTREAM: swipl-devel tests/core_lang/test_term.pl @ bae881a24a3f
# CLASS: code
# COPYRIGHT: Copyright (c)  2008-2020, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
#
# The `variant` unit of swipl-devel's test_term.pl — `=@=/2`, our `is_variant_ptr`
# (src/pl-variant.jl) — under upstream's unit names, each case as upstream states it; a name upstream uses more than
# once is used as often here.
#
# NOT PORTED from this unit, and why:
#   cyclic ×4, cycle, ground, sharing_cycles, cycle_with_prefix — rational trees (`sto(rational_trees)`);
#                       interface terms are finite.
#   attvar ×2           attributed variables do not exist in the kernel.
# NOT PORTED from this file: numbervars, compound, zero_arity_compound, term_singletons — builtins
# not ported yet.
using Test, LogicKernel
using LogicKernel: is_variant_ptr

const _TT = DefaultTerm
_ta(x::Symbol) = sym_term(_TT, x)
_tc(f::Symbol, xs::_TT...) = mk_expr(_TT, _TT[_ta(f), xs...])
let n = UInt64(0)
    global _tv() = mk_var(_TT, n += 1)
end
_tl(h, t) = _tc(Symbol("[|]"), h, t)             # [H|T]

# PORT: test_term.pl dag as _tdag
"The same term as Depth cells (shared) — `f(D,D)` nested Depth deep."
function _tdag(n::Int, l::_TT)::_TT
    n == 0 && return l
    d = _tdag(n - 1, l)
    return _tc(:f, d, d)
end
# PORT: test_term.pl tree as _ttree
"…and as 2^Depth cells (unshared)."
function _ttree(n::Int, l::_TT)::_TT
    n == 0 && return l
    return _tc(:f, _ttree(n - 1, l), _ttree(n - 1, l))
end

@testset "variant" begin
    # PORT: test_term.pl simple
    @testset "simple" begin
        a, b = _tv(), _tv()
        @test is_variant_ptr(_tc(:a, a), _tc(:a, b))                   # a(A) =@= a(B)
    end
    # PORT: test_term.pl shared
    @testset "shared" begin
        a = _tv()
        @test is_variant_ptr(_tc(:a, a), _tc(:a, a))                   # a(A) =@= a(A)
    end
    # PORT: test_term.pl shared
    @testset "shared" begin
        a = _tv()
        @test is_variant_ptr(_tc(:a, a, a), _tc(:a, a, a))             # a(A,A) =@= a(A,A)
    end
    # PORT: test_term.pl shared
    @testset "shared" begin
        a, b = _tv(), _tv()
        @test is_variant_ptr(_tc(:a, a, b), _tc(:a, a, b))             # a(A,B) =@= a(A,B)
    end
    # PORT: test_term.pl shared
    @testset "shared" begin                                           # fail
        a, b = _tv(), _tv()
        @test !is_variant_ptr(_tc(:a, a, b), _tc(:a, a, a))            # a(A,B) =@= a(A,A)
    end
    # PORT: test_term.pl shared
    @testset "shared" begin                                           # fail
        a, b = _tv(), _tv()
        @test !is_variant_ptr(_tc(:a, a, b), _tc(:a, b, b))            # a(A,B) =@= a(B,B)
    end
    # PORT: test_term.pl dubious
    @testset "dubious" begin
        x, y, z = _tv(), _tv(), _tv()
        @test is_variant_ptr(_tc(:a, x, y), _tc(:a, y, z))             # a(X,Y) =@= a(Y,Z)
    end
    # PORT: test_term.pl common
    @testset "common" begin                                             # Bug #464
        a = _tc(:x, _tv())
        b = _tv()
        @test is_variant_ptr(_tc(:s, a, a), _tc(:s, _tc(:x, b), _tc(:x, b)))
    end
    # PORT: test_term.pl common
    @testset "common" begin                                           # fail
        a, b = _tv(), _tv()
        x = _tc(:x, a)
        @test !is_variant_ptr(_tc(:a, x, a), _tc(:a, x, b))            # a(X,A) =@= a(X,B)
    end
    # PORT: test_term.pl common
    @testset "common" begin                                           # fail
        a, b = _tv(), _tv()
        x = _tc(:x, a)
        @test !is_variant_ptr(_tc(:a, a, x), _tc(:a, b, x))            # a(A,X) =@= a(B,X)
    end
    # PORT: test_term.pl shared
    @testset "shared" begin                                           # fail
        a, b = _tv(), _tv()
        x, y = _tc(:x, a), _tc(:x, b)
        @test !is_variant_ptr(_tc(:s, x, y, x), _tc(:s, x, y, y))      # s(X,Y,X) =@= s(X,Y,Y)
    end
    # PORT: test_term.pl symmetry
    @testset "symmetry" begin                                           # fail — Ulrich
        x, y, z = _tv(), _tv(), _tv()
        b = _tl(x, y)                                                   # B=[X|_Y]
        c = _tl(z, x)                                                   # C=[_Z|X]
        @test !is_variant_ptr(_tl(b, c), _tl(c, b))                    # [B|C] =@= [C|B]
    end
    # PORT: test_term.pl symmetry
    @testset "symmetry" begin                                         # fail — Ulrich
        x, y, z = _tc(:s, _tv()), _tc(:s, _tv()), _tc(:s, _tv())
        @test !is_variant_ptr(_tc(:v, x, y, x), _tc(:v, z, x, y))      # v(X,Y,X) =@= v(Z,X,Y)
    end
    # PORT: test_term.pl shared_expanded
    @testset "shared_expanded" begin                                    # node buffer grows
        @test is_variant_ptr(_tdag(12, _ta(:l)), _ttree(12, _ta(:l)))
    end
    # PORT: test_term.pl shared_expanded
    @testset "shared_expanded" begin                                  # fail
        @test !is_variant_ptr(_tdag(12, _ta(:l)), _ttree(12, _ta(:m)))
    end
end
