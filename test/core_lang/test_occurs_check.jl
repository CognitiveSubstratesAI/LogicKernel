# UPSTREAM: swipl-devel tests/core_lang/test_occurs_check.pl @ bae881a24a3f
# CLASS: code
# COPYRIGHT: Copyright (C): 2007-2024, University of Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# swipl-devel's test_occurs_check.pl — the `occurs_check` flag's three modes — against
# `pl_unify!`, `pl_unify_with_occurs_check!`, `unifiable` and `pl_can_compare` (src/pl-prims.jl),
# under upstream's unit names; a name upstream uses more than once is used as often here.
#
# The flag is the local data's `prolog_flag_occurs_check`. plunit's `sto(finite_trees)` runs a test
# with the flag `true` (packages/plunit/plunit.pl `map_sto`); the `occurs_check_error` unit runs only
# when the flag is `error` (`condition(error_unification)`), which each unit here sets itself.
# `unify(X, X).` is upstream's helper: calling `unify(X, f(X))` unifies the call with that head.
#
# NOT PORTED, and why:
#   attvar_1 … attvar_4   attributed variables (freeze/2) — the kernel has none.
using Test, LogicKernel
using LogicKernel:
    PL_local_data,
    pl_unify!,
    pl_unify_with_occurs_check!,
    pl_can_compare,
    unifiable,
    OCCURS_CHECK_TRUE,
    OCCURS_CHECK_ERROR

# TERM TYPES PER CHUNK: ALL — the term layer: src/pl-prims.jl
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _OT = lk_term_type(Union{Int64, Float64, String})
_os(x::Symbol) = lk_sym(_OT, x)
_oc(f::Symbol, xs::_OT...) = mk_expr(_OT, _OT[_os(f), xs...])
_ov(k::Int) = mk_var(_OT, UInt64(k))
_oid(a, b) = compareStandard(a, b) == 0                     # ==/2

"Local data with the `occurs_check` flag set."
function _old(flag)
    ld = PL_local_data{_OT}()
    ld.prolog_flag_occurs_check = flag
    return ld
end

"""
The occurs-check error `f()` leaves pending in `ld`, as upstream raises it (S10): `(var, term)` of
the ball `error(occurs_check(Var, Term), _)`, after `f()` failed — or `nothing` if none is pending.
"""
function _oerr(ld, f)
    rc = f()
    ld.exception_term == 0 && return nothing
    @test rc === false || rc === nothing            # it failed, the error pending
    ball = ld.slots[ld.exception_term + 1]
    lk_name(child(ball, 1)) == :error || return nothing
    formal = child(ball, 2)
    lk_name(child(formal, 1)) == :occurs_check || return nothing
    return (var=child(formal, 2), term=child(formal, 3))
end

@testset "unify_with_occurs_check" begin
    # PORT: test_occurs_check.pl simple_1
    @testset "simple_1" begin                    # \+ unify_with_occurs_check(A, list(A))
        A = _ov(1)
        @test !pl_unify_with_occurs_check!(PL_local_data{_OT}(), A, _oc(:list, A))
    end
    # PORT: test_occurs_check.pl simple_2
    @testset "simple_2" begin                    # unify_with_occurs_check(_A, _B)
        @test pl_unify_with_occurs_check!(PL_local_data{_OT}(), _ov(1), _ov(2))
    end
end

@testset "occurs_check_fail" begin
    # PORT: test_occurs_check.pl unify
    @testset "unify" begin                       # sto(finite_trees), fail: X = f(X)
        X = _ov(1)
        @test !pl_unify!(_old(OCCURS_CHECK_TRUE), X, _oc(:f, X))
    end
    # PORT: test_occurs_check.pl unify
    @testset "unify" begin                       # sto(finite_trees), fail: unify(X, f(X))
        X, A = _ov(1), _ov(2)                    # A: the head unify(A, A)
        @test !pl_unify!(
            _old(OCCURS_CHECK_TRUE), _oc(:unify, X, _oc(:f, X)), _oc(:unify, A, A)
        )
    end
    # PORT: test_occurs_check.pl unifiable
    @testset "unifiable" begin                   # sto(finite_trees), fail: unifiable(X, f(X), _)
        X = _ov(1)
        @test unifiable(_old(OCCURS_CHECK_TRUE), X, _oc(:f, X)) === nothing
    end
end

@testset "occurs_check_error" begin
    # PORT: test_occurs_check.pl unify
    @testset "unify" begin                       # error(occurs_check(X, f(X))): X = f(X)
        X = _ov(1)
        ld = _old(OCCURS_CHECK_ERROR)
        e = _oerr(ld, () -> pl_unify!(ld, X, _oc(:f, X)))
        @test e !== nothing && _oid(e.var, X) && _oid(e.term, _oc(:f, X))
    end
    # PORT: test_occurs_check.pl unify
    @testset "unify" begin                       # error(occurs_check(X, f(X))): unify(X, f(X))
        X, A = _ov(1), _ov(2)
        ld = _old(OCCURS_CHECK_ERROR)
        e = _oerr(ld, () -> pl_unify!(ld, _oc(:unify, X, _oc(:f, X)), _oc(:unify, A, A)))
        @test e !== nothing && _oid(e.var, X) && _oid(e.term, _oc(:f, X))
        @test isempty(ld.trail) && isempty(ld.bindings)     # undone before the error
    end
    # PORT: test_occurs_check.pl unifiable
    @testset "unifiable" begin                   # error(occurs_check(X, f(X)))
        X = _ov(1)
        ld = _old(OCCURS_CHECK_ERROR)
        e = _oerr(ld, () -> unifiable(ld, X, _oc(:f, X)))
        @test e !== nothing && _oid(e.var, X) && _oid(e.term, _oc(:f, X))
    end
    # PORT: test_occurs_check.pl ?=
    @testset "?=" begin                          # error(occurs_check(X, f(X))): ?=(X, f(X))
        X = _ov(1)
        ld = _old(OCCURS_CHECK_ERROR)
        e = _oerr(ld, () -> pl_can_compare(ld, X, _oc(:f, X)))
        @test e !== nothing && _oid(e.var, X) && _oid(e.term, _oc(:f, X))
        @test isempty(ld.trail)                             # ?= undoes, error or not
    end
    # PORT: test_occurs_check.pl head
    # DIVERGES: upstream's error comes from COMPILED head unification and names `s(X)`; the kernel
    # unifies a call with a head by `=`, whose error names the head's variable after the undo,
    # `s(Y)` — exactly what swipl 10.1.16 raises for `my_unify(A,A) = my_unify(B,s(B))` (measured
    # 2026-10-03: `occurs_check(_752, s(_758))`). The test pins that shape.
    @testset "head" begin                        # my_unify(X, X) against my_unify(Y, s(Y))
        X, Y = _ov(1), _ov(2)
        ld = _old(OCCURS_CHECK_ERROR)
        e = _oerr(
            ld,
            () -> pl_unify!(ld, _oc(:my_unify, X, X), _oc(:my_unify, Y, _oc(:s, Y)))
        )
        @test e !== nothing && _oid(e.var, X)
        @test _oid(e.term, _oc(:s, Y))                      # s(Y), as swipl's `=` (see header)
    end
end
