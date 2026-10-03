# UPSTREAM: swipl-devel tests/core_lang/test_unify.pl @ bae881a24a3f
# CLASS: code
# COPYRIGHT: Copyright (c)  2008-2024, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# swipl-devel's test_unify.pl — "unification oddities" — against `pl_unify!`, `pl_can_compare` and
# `unifiable` (src/pl-prims.jl), under upstream's unit names; a name upstream uses more than once is
# used as often here. Each unit runs in fresh local data and leaves its bindings undone.
#
# DIVERGES (file-wide): there is no predicate execution in the kernel yet, so `blam` and
# `unify_self` replay the unifications of upstream's successful derivation (named per case).
#
# NOT PORTED, and why:
#   unify_fv   garbage_collect/0 and copy_term/2 on an uninitialised variable — the kernel has no
#              stacks to collect, and copy_term/2 is not ported.
#   gc_1       attributed variables (freeze/2) — the kernel has none.
using Test, LogicKernel
using LogicKernel:
    PL_local_data, pl_unify!, pl_can_compare, unifiable, resolve_term, Mark, Undo!

include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _UT = lk_term_type(Union{Int64, Float64, String})
_us(x::Symbol) = lk_sym(_UT, x)
_ug(x) = lk_gnd(_UT, x)
_uc(f::Symbol, xs::_UT...) = mk_expr(_UT, _UT[_us(f), xs...])
_uv(k::Int) = mk_var(_UT, UInt64(k))
_unil() = _us(Symbol("[]"))
_ucons(h, t) = _uc(Symbol("[|]"), h, t)                     # [H|T]
_uid(a, b) = compareStandard(a, b) == 0                     # ==/2

@testset "unify" begin
    # PORT: test_unify.pl blam
    # blam([]).  blam([L|L]) :- blam(L).   blam(X), length(X, 2): the successful derivation binds
    # X = [L|L], L = [L2|L2], L2 = [] — so X == [[[]], []].
    @testset "blam" begin
        ld = PL_local_data{_UT}()
        X, L, L2 = _uv(1), _uv(2), _uv(3)
        @test pl_unify!(ld, X, _ucons(L, L))
        @test pl_unify!(ld, L, _ucons(L2, L2))
        @test pl_unify!(ld, L2, _unil())
        expected = _ucons(_ucons(_unil(), _unil()), _ucons(_unil(), _unil()))
        @test _uid(resolve_term(ld, X), expected)          # X == [[[]], []]
    end
    # PORT: test_unify.pl unify_self
    # p/2 runs U=U, V=V (Bug#436): unifying a variable with itself binds nothing.
    @testset "unify_self" begin
        ld = PL_local_data{_UT}()
        U, V = _uv(1), _uv(2)
        @test pl_unify!(ld, U, U) && pl_unify!(ld, V, V)
        @test isempty(ld.trail) && isempty(ld.bindings)
    end
    # PORT: test_unify.pl unify_arity_0
    @testset "unify_arity_0" begin                           # A = f(), X == f()
        ld = PL_local_data{_UT}()
        X = _uv(1)
        @test pl_unify!(ld, X, _uc(:f))
        @test _uid(resolve_term(ld, X), _uc(:f))
        m = Mark(ld)
        @test !pl_unify!(ld, _uc(:f), _us(:f))              # f() is not the atom f
        Undo!(ld, m)
    end
    # PORT: test_unify.pl cycle_1
    @testset "cycle_1" begin                                 # Kuniaki Mukai
        ld = PL_local_data{_UT}()
        X, Y = _uv(1), _uv(2)
        @test pl_unify!(ld, X, _uc(:f, Y))                  # X = f(Y),
        @test pl_unify!(ld, Y, _uc(:f, X))                  # Y = f(X),
        @test pl_unify!(ld, X, Y)                           # X = Y.
    end
    # PORT: test_unify.pl cycle_2
    @testset "cycle_2" begin                                 # Kuniaki Mukai
        ld = PL_local_data{_UT}()
        X, Y = _uv(1), _uv(2)
        @test pl_unify!(ld, X, _uc(:f, X))                  # X = f(X),
        @test pl_unify!(ld, Y, _uc(:f, Y))                  # Y = f(Y),
        @test pl_unify!(ld, X, _uc(:f, Y))                  # X = f(Y).
    end
end

@testset "can_compare" begin
    # PORT: test_unify.pl ground
    @testset "ground" begin
        @test pl_can_compare(PL_local_data{_UT}(), _us(:a), _us(:b))   # ?=(a,b)
    end
    # PORT: test_unify.pl ground
    @testset "ground" begin
        @test pl_can_compare(PL_local_data{_UT}(), _us(:a), _us(:a))   # ?=(a,a)
    end
    # PORT: test_unify.pl ground
    @testset "ground" begin                                  # fail
        ld = PL_local_data{_UT}()
        @test !pl_can_compare(ld, _us(:a), _uv(1))                     # ?=(a,X)
        @test isempty(ld.trail) && isempty(ld.bindings)                # nothing left bound
    end
end

@testset "unifiable" begin
    # PORT: test_unify.pl unifiable_1
    @testset "unifiable_1" begin                             # S == [X=1]
        ld = PL_local_data{_UT}()
        X = _uv(1)
        S = unifiable(ld, X, _ug(1))
        @test S !== nothing && length(S) == 1
        @test _uid(S[1].first, X) && _uid(S[1].second, _ug(1))
    end
    # PORT: test_unify.pl unifiable_2
    @testset "unifiable_2" begin                             # S == [Z=X, Y=X]
        ld = PL_local_data{_UT}()
        X, Y, Z = _uv(1), _uv(2), _uv(3)                    # created in that order, as upstream's
        S = unifiable(ld, _uc(:a, X, X), _uc(:a, Y, Z))
        @test S !== nothing && length(S) == 2
        @test _uid(S[1].first, Z) && _uid(S[1].second, X)
        @test _uid(S[2].first, Y) && _uid(S[2].second, X)
        @test isempty(ld.trail) && isempty(ld.bindings)     # read off the trail, rewound
    end
end
