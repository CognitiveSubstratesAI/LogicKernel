# UPSTREAM: swipl-devel tests/core_lang/test_exception.pl @ 8e1bc1110be4
# CLASS: code
# COPYRIGHT: Copyright (c)  2007-2011, University of Amsterdam
#
# swipl-devel's test_exception.pl — the `throw` unit — against `throw/1` (src/pl-prims.jl,
# since V5d), called through the query API: with no catch/3 until V9, the ball is read where the
# query ends, with `PL_exception`, as plunit's `throws(Ball)` reads the one its catch/3 caught. A ball is
# the RESOLVED copy `PL_raise_exception` keeps (src/pl-fli.jl `copy_exception!`): an unbound variable
# is renamed, as upstream's `duplicate_term` renames it (since V9f; `throws` holds either way), and
# a cyclic ball keeps its cycle (user, 2026-10-07) — on the cells since L1e e5 (a frozen copy), its test
# a clause since f3b-1 (`B = hello(B), throw(B)`, as upstream's body): a caller's value is laid on the
# cells by the put now, so the rational tree is built where upstream's test builds it.
#
# NOT PORTED, and why:
#   ex_coroutining not, non_unify   freeze/2: the kernel has no attributed variables.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _X = lk_term_type(Union{Int64, Float64, String})
_xs(x) = lk_sym(_X, Symbol(x))
_xf(f, xs::_X...) = mk_expr(_X, _X[_xs(f), xs...])
_xv() = mk_var(_X, LK.fresh_var_keys!(1))

"""
`throw(Ball)` through the query API in a database of its own: `(rc, ball)` — the return code and
the term `PL_exception` holds when the query ends, read off the cells (an acyclic ball).
"""
function _xthrow(
    ball::_X; gd::LK.PL_global_data{_X}=LK.PL_global_data{_X}(),
    ld::LK.PL_local_data{_X}=LK.PL_local_data{_X}(gd)
)
    th = LK.isCurrentProcedure(sym_key(_xs("throw")), 1, LK.MODULE_system(gd))
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 1)
    LK.putSlotValue!(ld, a + 1, ball)
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, th, a
    )
    rc = LK.PL_next_solution(gd, ld, qid)
    ex = LK.PL_exception(ld, qid)
    # the ball on the cells (L1e e5a): read off them through its reference (`lk_answer`, f3-2) —
    # every ball thrown here is acyclic; the cyclic ball below is read in its own testset
    caught = ex == 0 ? nothing : lk_answer(ld, ex)
    LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
    return (rc, caught)
end

@testset "throw" begin
    # PORT: test_exception.pl error
    @testset "error" begin                          # throw(_): error(instantiation_error)
        rc, ball = _xthrow(_xv())
        @test rc == LK.PL_S_EXCEPTION
        @test lk_eq(child(ball::_X, 2), _xs("instantiation_error"))
    end
    # PORT: test_exception.pl ground
    @testset "ground" begin                         # throws(hello(world))
        rc, ball = _xthrow(_xf("hello", _xs("world")))
        @test rc == LK.PL_S_EXCEPTION && lk_eq(ball::_X, _xf("hello", _xs("world")))
    end
    # PORT: test_exception.pl unbound
    @testset "unbound" begin                        # Ball = hello(_), throws(Ball)
        rc, ball = _xthrow(_xf("hello", _xv()))
        @test rc == LK.PL_S_EXCEPTION
        @test lk_name(child(ball::_X, 1)) === :hello && kind(child(ball, 2)) === VAR
    end
    # PORT: test_exception.pl cyclic
    @testset "cyclic" begin                         # sto(rational_trees), Ball = hello(Ball)
        # the test's body as a clause, run through the query API (f3b-1: see the header): the ball is read
        # while the query is open — after its outermost close the frozen region is released (D-0029 (b))
        gd = LK.PL_global_data{_X}()
        ld = LK.PL_local_data{_X}(gd)
        B = _xv()
        user = LK.MODULE_user(gd)
        pr = LK.lookupProcedure(_xs("cyc_throw"), 0, user)
        body = _xf(",", _xf("=", B, _xf("hello", B)), _xf("throw", B))   # Ball = hello(Ball), throw(Ball)
        cl = LK.compileClause(gd, ld, _xs("cyc_throw"), body, pr, user)
        LK.assertDefinition!(gd, pr.definition, cl::LK.Clause{_X}, LK.CL_END)
        fid = LK.PL_open_foreign_frame(ld)
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, pr, 0
        )
        @test LK.PL_next_solution(gd, ld, qid) == LK.PL_S_EXCEPTION
        ex = LK.PL_exception(ld, qid)
        @test ex != 0
        ball = LK.deRef(ld, LK.slotValue(ld, ex + 1))
        @test lk_name(child(ball, 1)) === :hello
        # throws(Ball), Ball = hello(Ball): the caught ball keeps its cycle — hello(Ball) == Ball
        @test LK.compareStandard(ld, ball, _xf("hello", ball), true) == 0
        @test LK.compareStandard(ld, ball, _xf("hello", _xf("hello", ball)), true) == 0
        @test LK.compareStandard(ld, ball, _xf("hello", _xs("x")), true) != 0   # (the guard can fail)
        @test_throws ArgumentError LK.resolve_term(ld, ball)            # a rational tree
        LK.PL_close_query(ld, qid)
        LK.PL_close_foreign_frame(ld, fid)
    end
end
