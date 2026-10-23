# UPSTREAM: swipl-devel tests/core_lang/test_occurs_check.pl @ 8e1bc1110be4
# CLASS: code
# COPYRIGHT: Copyright (C): 2007-2024, University of Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# swipl-devel's test_occurs_check.pl — the `occurs_check` flag's three modes — against `PL_unify`,
# `unify_with_occurs_check/2`, `unifiable_cells` and `?=/2` (src/pl-prims.jl) on the CELLS (since L1f
# f3; the term-level `pl_unify!`, `pl_unify_with_occurs_check!`, `unifiable` and `pl_can_compare`
# before), under upstream's unit names; a name upstream uses more than once is used as often here.
# The terms are put into term references with ONE variable map (`_oput`: a variable shared between
# them is one cell).
#
# The flag is the local data's `prolog_flag_occurs_check`. plunit's `sto(finite_trees)` runs a test
# with the flag `true` (packages/plunit/plunit.pl `map_sto`); the `occurs_check_error` unit runs only
# when the flag is `error` (`condition(error_unification)`), which each unit here sets itself.
# `unify(X, X).` is upstream's helper: calling `unify(X, f(X))` unifies the call with that head.
#
# NOT PORTED, and why:
#   attvar_1 … attvar_4   attributed variables (freeze/2) — the kernel has none.
#   occurs_check_error_space: full_stack (since ac807ba)
#                         catch/3 in a loop (V9), raising the error with the GLOBAL stack nearly
#                         full — the kernel has no global stack (G1).
using Test, LogicKernel
using LogicKernel:
    PL_local_data, PL_global_data, PL_unify, OCCURS_CHECK_TRUE, OCCURS_CHECK_ERROR
const LK = LogicKernel

# TERM TYPES PER CHUNK: ALL — the term layer: src/pl-prims.jl
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _OT = lk_term_type(Union{Int64, Float64, String})
_os(x::Symbol) = lk_sym(_OT, x)
_oc(f::Symbol, xs::_OT...) = mk_expr(_OT, _OT[_os(f), xs...])
_ov(k::Int) = mk_var(_OT, UInt64(k))
# The ball `error(occurs_check(Var, Term), _)` against the expected pair, UP TO A RENAMING of the
# variables (`=@=`): the ball is a copy with fresh variables (copy_exception: duplicate_term,
# pl-fli.c; since V9f), and plunit's `error(E)` asks only that the ball is subsumed by `E`.
_oball(e, var, term) =
    LogicKernel.is_variant_ptr(
        _oc(:occurs_check, e.var, e.term), _oc(:occurs_check, var, term)
    )

"Local data with the `occurs_check` flag set."
function _old(flag)
    ld = PL_local_data{_OT}(PL_global_data{_OT}())
    ld.prolog_flag_occurs_check = flag
    return ld
end
"Each of `vs` put into a term reference of its own in `ld`, ONE variable map; `vs[i]` is reference `t + i - 1`."
function _oput(ld, vs::_OT...)
    t = LK.PL_new_term_refs(ld, length(vs))
    pvm = LK.PutVarMap()
    for (i, v) in enumerate(vs)
        LK.putSlotValue!(ld, t + i, v, pvm)
    end
    return t
end
"Whether term reference `r` holds a reference to an unbound cell (nothing bound it)."
_ofree(ld, r) = LK.isRef(ld.slots[r + 1]) && ld.gstack[LK.unRef(ld.slots[r + 1])] == 0
_octx() = LK.foreign_context{_OT}(LK.FRG_FIRST_CALL, UInt(0), nothing)
"`unify_with_occurs_check(A1, A2)` on two consecutive term references from `t`."
_ouwoc(ld, t) = LK.pl_unify_with_occurs_check2_va(ld, t, 2, _octx()) == LK.FTRUE
"`?=(A1, A2)` on two consecutive term references from `t`."
_ocan_compare(ld, t) = LK.pl_can_compare2_va(ld, t, 2, _octx()) == LK.FTRUE

"""
The occurs-check error `f()` leaves pending in `ld`, as upstream raises it (S10): `(var, term)` of
the ball `error(occurs_check(Var, Term), _)`, after `f()` failed — or `nothing` if none is pending.
"""
function _oerr(ld, f)
    rc = f()
    ld.exception_term == 0 && return nothing
    @test rc === false || rc === nothing            # it failed, the error pending
    ball = lk_answer(ld, ld.exception_term)
    lk_name(child(ball, 1)) == :error || return nothing
    formal = child(ball, 2)
    lk_name(child(formal, 1)) == :occurs_check || return nothing
    return (var=child(formal, 2), term=child(formal, 3))
end

@testset "unify_with_occurs_check" begin
    # PORT: test_occurs_check.pl simple_1
    @testset "simple_1" begin                    # \+ unify_with_occurs_check(A, list(A))
        A = _ov(1)
        ld = PL_local_data{_OT}(PL_global_data{_OT}())
        @test !_ouwoc(ld, _oput(ld, A, _oc(:list, A)))
    end
    # PORT: test_occurs_check.pl simple_2
    @testset "simple_2" begin                    # unify_with_occurs_check(_A, _B)
        ld = PL_local_data{_OT}(PL_global_data{_OT}())
        @test _ouwoc(ld, _oput(ld, _ov(1), _ov(2)))
    end
end

@testset "occurs_check_fail" begin
    # PORT: test_occurs_check.pl unify
    @testset "unify" begin                       # sto(finite_trees), fail: X = f(X)
        X = _ov(1)
        ld = _old(OCCURS_CHECK_TRUE)
        t = _oput(ld, X, _oc(:f, X))
        @test !PL_unify(ld, t, t + 1)
    end
    # PORT: test_occurs_check.pl unify
    @testset "unify" begin                       # sto(finite_trees), fail: unify(X, f(X))
        X, A = _ov(1), _ov(2)                    # A: the head unify(A, A)
        ld = _old(OCCURS_CHECK_TRUE)
        t = _oput(ld, _oc(:unify, X, _oc(:f, X)), _oc(:unify, A, A))
        @test !PL_unify(ld, t, t + 1)
    end
    # PORT: test_occurs_check.pl unifiable
    @testset "unifiable" begin                   # sto(finite_trees), fail: unifiable(X, f(X), _)
        X = _ov(1)
        ld = _old(OCCURS_CHECK_TRUE)
        t = _oput(ld, X, _oc(:f, X), _ov(9))
        @test !LK.unifiable_cells(ld, t, t + 1, t + 2)
    end
end

@testset "occurs_check_error" begin
    # PORT: test_occurs_check.pl unify
    @testset "unify" begin                       # error(occurs_check(X, f(X))): X = f(X)
        X = _ov(1)
        ld = _old(OCCURS_CHECK_ERROR)
        t = _oput(ld, X, _oc(:f, X))
        e = _oerr(ld, () -> PL_unify(ld, t, t + 1))
        @test e !== nothing && _oball(e, X, _oc(:f, X))
    end
    # PORT: test_occurs_check.pl unify
    @testset "unify" begin                       # error(occurs_check(X, f(X))): unify(X, f(X))
        X, A = _ov(1), _ov(2)
        ld = _old(OCCURS_CHECK_ERROR)
        t = _oput(ld, _oc(:unify, X, _oc(:f, X)), _oc(:unify, A, A), X, A)
        e = _oerr(ld, () -> PL_unify(ld, t, t + 1))
        @test e !== nothing && _oball(e, X, _oc(:f, X))
        # undone before the error: X and A are unbound (the occurs-check binding is gone); the cells
        # above hold the ball's compounds (L1c: a compound on the global stack; kept by
        # PL_close_foreign_frame as upstream's frozen ball is), so not `lk_no_bindings` (until L1f f3
        # also: the keyed store held only variables, as many as the trail's entries)
        @test _ofree(ld, t + 2) && _ofree(ld, t + 3)
    end
    # PORT: test_occurs_check.pl unifiable
    @testset "unifiable" begin                   # error(occurs_check(X, f(X)))
        X = _ov(1)
        ld = _old(OCCURS_CHECK_ERROR)
        t = _oput(ld, X, _oc(:f, X), _ov(9))
        e = _oerr(ld, () -> LK.unifiable_cells(ld, t, t + 1, t + 2))
        @test e !== nothing && _oball(e, X, _oc(:f, X))
    end
    # PORT: test_occurs_check.pl ?=
    @testset "?=" begin                          # error(occurs_check(X, f(X))): ?=(X, f(X))
        X = _ov(1)
        ld = _old(OCCURS_CHECK_ERROR)
        t = _oput(ld, X, _oc(:f, X))
        e = _oerr(ld, () -> _ocan_compare(ld, t))
        @test e !== nothing && _oball(e, X, _oc(:f, X))
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
        t = _oput(ld, _oc(:my_unify, X, X), _oc(:my_unify, Y, _oc(:s, Y)))
        e = _oerr(ld, () -> PL_unify(ld, t, t + 1))
        @test e !== nothing && _oball(e, X, _oc(:s, Y))     # s(Y), as swipl's `=` (see header)
    end
end
