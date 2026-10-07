# UPSTREAM: swipl-devel tests/core_text/test_read.pl @ bae881a2
# CLASS: code
# COPYRIGHT: Copyright (c)  2011-2024, University of Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# swipl-devel's test_read.pl — the `read_op`, `read_numbers` and `read_deep` units — against the
# parser (src/pl-read.jl, since R1d), through `term_string/2` and the query API. `read_op`'s
# operators (`:- op(600, fy, !)`, `:- op(600, fy, [])` — a BLOCK operator) are made with op/3 in
# `user`, where `term_string/2` reads (upstream passes `module(M)`, an option of term_string/3).
# `read_deep` reads terms nested 20,000 deep: the parser's state machine must not use Julia stack
# in proportion to the nesting, as upstream's must not use C stack.
#
# NOT PORTED, and why:
#   singletons, warn_singletons                  read_term/2,3's singletons(…) option, and the
#                                                warning (no message system): PL_scan_options
#   position, valid_position_*, pos_block,       term positions: refused until needed (R1's
#   positions                                    decision)
#   valid_position_dict*, dict                   dicts: refused (R1's decision)
#   float_overflow (the second)                  the float_overflow flag (no Prolog flags yet)
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _RT = lk_term_type(Union{Int64, Float64, String})
_rts(x) = lk_sym(_RT, Symbol(x))
_rtf(f, xs::_RT...) = mk_expr(_RT, _RT[_rts(f), xs...])
_rtl(xs::_RT...) = foldr((x, l) -> _rtf("[|]", x, l), collect(xs); init=mk_nil(_RT))

"Run `name(args…)` through the query API in `db`: `(rc, resolved args or [ball])`."
function _rt_call(db, name::String, args::Vector{_RT})
    gd, ld = db
    proc = LK.isCurrentProcedure(sym_key(_rts(name)), length(args), LK.MODULE_system(gd))
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, length(args))
    for (i, x) in enumerate(args)
        ld.slots[a + i] = x
    end
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    rc = LK.PL_next_solution(gd, ld, qid)
    out = if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
        (:true, [LK.resolve_term(ld, ld.slots[a + i]) for i in 1:length(args)])
    elseif rc == LK.PL_S_EXCEPTION
        (:exception, [LK.resolve_term(ld, ld.slots[LK.PL_exception(ld, qid) + 1])])
    else
        (:false, _RT[])
    end
    LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
    return out
end

"A database of its own, with the operators `ops` declared by op/3 (a name `[]` is SWI-7's `[]`)."
function _rt_db(ops)
    db = (LK.PL_global_data{_RT}(), LK.PL_local_data{_RT}())
    for (p, t, n) in ops
        name = n == "[]" ? mk_nil(_RT) : _rts(n)
        _rt_call(db, "op", _RT[lk_gnd(_RT, p), _rts(t), name])[1] === :true ||
            error("op($p, $t, $n) failed")
    end
    return db
end

"`term_string(T, Text)`: `(rc, T or the ball)`."
function _rt_read(db, text::String)
    rc, ans = _rt_call(
        db, "term_string", _RT[mk_var(_RT, LK.fresh_var_keys!(1)), lk_gnd(_RT, text)]
    )
    return (rc, isempty(ans) ? nothing : ans[1])
end

"The formal of a syntax error ball `error(syntax_error(F), _)`, or `nothing`."
function _rt_syntax_formal(ball)
    ball === nothing && return nothing
    f = child(ball, 2)
    return if kind(f) === EXPR && lk_name(child(f, 1)) === :syntax_error
        child(f, 2)
    else
        nothing
    end
end

@testset "read_op" begin
    db = _rt_db([(600, "fy", "!"), (600, "fy", "[]")])
    # PORT: test_read.pl modify
    @testset "modify" begin                         # Term = !([])
        rc, t = _rt_read(db, "![]")
        @test rc === :true && lk_eq(t, _rtf("!", mk_nil(_RT)))
    end
    # PORT: test_read.pl minus_block
    @testset "minus_block" begin                    # Term = -([x])
        rc, t = _rt_read(db, "-[x]")
        @test rc === :true && lk_eq(t, _rtf("-", _rtl(_rts("x"))))
    end
    # PORT: test_read.pl modify_block
    @testset "modify_block" begin                   # Term = !([x])
        rc, t = _rt_read(db, "![x]")
        @test rc === :true && lk_eq(t, _rtf("!", _rtl(_rts("x"))))
    end
end

@testset "read_numbers" begin
    db = _rt_db([])
    # PORT: test_read.pl float_overflow
    @testset "float_overflow" begin                 # error(syntax_error(float_overflow))
        rc, ball = _rt_read(db, "1.797693134862316e+308")
        @test rc === :exception && lk_eq(_rt_syntax_formal(ball), _rts("float_overflow"))
    end
end

# read_deep: the nesting; `nested(Open, Close, Depth)` is Open^Depth, "x", Close^Depth.
const _RT_DEEP = 20_000
_rt_nested(open, close, depth) = repeat(open, depth) * "x" * repeat(close, depth)

"How often the first argument (child 2) can be taken of `t`."
function _rt_depth(t)
    d = 0
    while kind(t) === EXPR && nchildren(t) >= 2
        t = child(t, 2)
        d += 1
    end
    return d
end

"How often the LAST argument can be taken of `t`."
function _rt_last_arg_depth(t)
    d = 0
    while kind(t) === EXPR && nchildren(t) >= 2
        t = child(t, nchildren(t))
        d += 1
    end
    return d
end

@testset "read_deep" begin
    db = _rt_db([])
    # PORT: test_read.pl compound
    @testset "compound" begin
        rc, t = _rt_read(db, _rt_nested("f(", ")", _RT_DEEP))
        @test rc === :true && _rt_depth(t) == _RT_DEEP
    end
    # PORT: test_read.pl list
    @testset "list" begin
        rc, t = _rt_read(db, _rt_nested("[", "]", _RT_DEEP))
        @test rc === :true && _rt_depth(t) == _RT_DEEP
    end
    # PORT: test_read.pl list_tail
    @testset "list_tail" begin
        rc, t = _rt_read(db, _rt_nested("[a|", "]", _RT_DEEP))
        @test rc === :true && _rt_last_arg_depth(t) == _RT_DEEP
    end
    # PORT: test_read.pl braces
    @testset "braces" begin
        rc, t = _rt_read(db, _rt_nested("{", "}", _RT_DEEP))
        @test rc === :true && _rt_depth(t) == _RT_DEEP
    end
    # PORT: test_read.pl parentheses
    @testset "parentheses" begin                    # T == x
        rc, t = _rt_read(db, _rt_nested("(", ")", _RT_DEEP))
        @test rc === :true && lk_eq(t, _rts("x"))
    end
    # PORT: test_read.pl operators
    @testset "operators" begin                      # left recursion: (((x+b)+b)+b)
        rc, t = _rt_read(db, "x" * repeat("+b", _RT_DEEP))
        @test rc === :true && _rt_depth(t) == _RT_DEEP
    end
    # PORT: test_read.pl prefix_operators
    @testset "prefix_operators" begin               # right recursion: - - - x
        rc, t = _rt_read(db, repeat("- ", _RT_DEEP) * "x")
        @test rc === :true && _rt_depth(t) == _RT_DEEP
    end
    # PORT: test_read.pl mixed
    @testset "mixed" begin                          # f([{-…}]) four levels each
        rc, t = _rt_read(db, _rt_nested("f([{-", "}])", _RT_DEEP))
        @test rc === :true && _rt_depth(t) == 4 * _RT_DEEP
    end
    # PORT: test_read.pl last_argument
    @testset "last_argument" begin                  # not the first argument
        rc, t = _rt_read(db, _rt_nested("f(a,", ")", _RT_DEEP))
        @test rc === :true && _rt_last_arg_depth(t) == _RT_DEEP
    end
    # PORT: test_read.pl syntax_error
    @testset "syntax_error" begin                   # unwind a deep frame stack
        rc, ball = _rt_read(db, repeat("f(", _RT_DEEP))
        @test rc === :exception && _rt_syntax_formal(ball) !== nothing
    end
end
