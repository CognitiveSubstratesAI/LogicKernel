# UPSTREAM: swipl-devel tests/core_lang/test_resource_error.pl @ bae881a24a3f
# CLASS: code
# COPYRIGHT: Copyright (c)  2010-2018, VU University, Amsterdam
#
# swipl-devel's test_resource_error.pl — the `local` unit — against the stack limit's error
# (since V5d: src/pl-alloc.jl `outOfStack!`), the goal called through the query API under upstream's
# `small_stacks` limit, 1 000 000 bytes, here 125 000 positions (the kernel's limit is the local
# stack's alone). With no catch/3 until V9, the ball is read where the query ends, with
# `PL_exception`, as plunit's `throws(error(resource_error(stack), _))` reads the one it caught.
#
# NOT PORTED, and why:
#   global                 the global stack: its overflow is NOT PORTED until G1 (as decided since Q-C).
#   string ×2              format/2 and strings, and the global stack.
#   length, tight_stacks   length/2, trim_stacks/0 and numbervars/3, and the global stack.
#   cleanup_handler        threads.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _RE = lk_term_type(Union{Int64, Float64, String})
_res(x) = lk_sym(_RE, Symbol(x))
_ref(f, xs::_RE...) = mk_expr(_RE, _RE[_res(f), xs...])

"The procedure of `name/arity` in database `gd`'s `user` module."
_reproc(gd, name, arity) = LK.lookupProcedure(_res(name), arity, LK.MODULE_user(gd))

"`head :- body` (`body` nothing: a fact) compiled and added at the end of its predicate."
function _readd!(gd, ld, head::_RE, body::Union{Nothing, _RE}=nothing)
    name, ar = kind(head) === SYM ? (head, 0) : (child(head, 1), nchildren(head) - 1)
    pr = LK.lookupProcedure(name, ar, LK.MODULE_user(gd))
    cl = LK.compileClause(gd, ld, head, body, pr, LK.MODULE_user(gd))
    LK.assertDefinition!(gd, pr.definition, cl::LK.Clause{_RE}, LK.CL_END)
    return nothing
end

"The goal `name/0` through the query API: `(rc, ball)`, the ball `nothing` when none is pending."
function _rerun(gd, ld, name)
    fid = LK.PL_open_foreign_frame(ld)
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, _reproc(gd, name, 0),
        0
    )
    rc = LK.PL_next_solution(gd, ld, qid)
    ex = LK.PL_exception(ld, qid)
    ball = ex == 0 ? nothing : LK.resolve_term(ld, ld.slots[ex + 1])
    LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
    return (rc, ball)
end

@testset "resource_error" begin
    gd = LK.PL_global_data{_RE}()
    ld = LK.PL_local_data{_RE}()
    ld.stacks_limit = 1_000_000 ÷ 8                 # small_stacks: set_prolog_flag(stack_limit, 1e6)
    _readd!(gd, ld, _res("choice"))                 # choice.
    _readd!(gd, ld, _res("choice"))                 # choice.
    # local_overflow :- choice, local_overflow.
    _readd!(
        gd, ld, _res("local_overflow"), _ref(",", _res("choice"), _res("local_overflow"))
    )
    # PORT: test_resource_error.pl local
    @testset "local" begin                          # throws(error(resource_error(stack), _))
        rc, ball = _rerun(gd, ld, "local_overflow")
        @test rc == LK.PL_S_EXCEPTION
        @test ball !== nothing && lk_name(child(ball, 1)) === :error &&
            lk_eq(child(ball, 2), _ref("resource_error", _res("stack")))
    end
end
