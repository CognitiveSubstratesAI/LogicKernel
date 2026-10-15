# UPSTREAM: swipl-devel tests/core_text/test_read.pl @ 8609e216cab9
# CLASS: code
# COPYRIGHT: Copyright (c)  2011-2024, University of Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# swipl-devel's test_read.pl — the `read_op`, `read_numbers` and `read_deep` units, and the units
# of `read_term` that came with upstream's fixes of 2026-10-11 — against the
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
#   quote_eos (the second)                       number_codes/2 is not a built-in of the kernel yet
#   read_term's other units                      read_term/2,3 on streams with positions, comments
#                                                and variable names: R2
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
    pvm = LK.PutVarMap()  # one PutVarMap: these puts share their variables as one record does (L1b boundary, user 2026-10-14)
    for (i, x) in enumerate(args)
        LK.putSlotValue!(ld, a + i, x, pvm)
    end
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    rc = LK.PL_next_solution(gd, ld, qid)
    out = if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
        (:true, [LK.resolve_term(ld, LK.slotValue(ld, a + i)) for i in 1:length(args)])
    elseif rc == LK.PL_S_EXCEPTION
        (:exception, [LK.resolve_term(ld, LK.slotValue(ld, LK.PL_exception(ld, qid) + 1))])
    else
        (:false, _RT[])
    end
    LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
    return out
end

"A database of its own, with the operators `ops` declared by op/3 (a name `[]` is SWI-7's `[]`)."
function _rt_db(ops)
    db = let gd = LK.PL_global_data{_RT}()
        (gd, LK.PL_local_data{_RT}(gd))
    end
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

"The ball of `term_to_atom(_, Text)`: `(rc, ball or nothing)`."
function _rt_atom_ball(db, text::String)
    rc, ans = _rt_call(
        db, "term_to_atom", _RT[mk_var(_RT, LK.fresh_var_keys!(1)), _rts(text)]
    )
    return (rc, rc === :exception ? ans[1] : nothing)
end

"`read_term_from_atom(Text, T, Options)`: `(rc, T)`; upstream's units call term_string/3, a library predicate over the same reader and options."
function _rt_read_opts(db, text::String, opts::_RT)
    rc, ans = _rt_call(
        db, "read_term_from_atom", _RT[_rts(text), mk_var(_RT, LK.fresh_var_keys!(1)), opts]
    )
    return (rc, rc === :true ? ans[2] : nothing)
end

@testset "read_term" begin
    db = _rt_db([])
    # Issue #1541: non-ASCII characters in syntax error arguments
    # PORT: test_read.pl eof_in_quoted
    @testset "eof_in_quoted" begin                  # E == end_of_file_in_quoted(Q), Q = «
        rc, ball = _rt_atom_ball(db, "«x")
        @test rc === :exception &&
            lk_eq(_rt_syntax_formal(ball), _rtf("end_of_file_in_quoted", _rts("«")))
    end
    # PORT: test_read.pl undefined_char_escape
    @testset "undefined_char_escape" begin          # E == undefined_char_escape(C), C = Ω
        rc, ball = _rt_atom_ball(db, "'\\Ω'")
        @test rc === :exception &&
            lk_eq(_rt_syntax_formal(ball), _rtf("undefined_char_escape", _rts("Ω")))
    end
    # PORT: test_read.pl undefined_char_escape
    @testset "undefined_char_escape" begin          # C = 😀 (U+1F600)
        rc, ball = _rt_atom_ball(db, "'\\😀'")
        @test rc === :exception &&
            lk_eq(_rt_syntax_formal(ball), _rtf("undefined_char_escape", _rts("😀")))
    end
    # (not a unit of upstream's) the undefined escape of the character 0: its argument is the
    # empty text, as in swipl — `utf8_put_char` writes the terminator itself
    @testset "an undefined escape of the character 0" begin
        rc, ball = _rt_read(db, "'\\\0'")
        @test rc === :exception &&
            lk_eq(_rt_syntax_formal(ball), _rtf("undefined_char_escape", _rts("")))
    end
    # context of an error before anything was read showed a stale byte
    # PORT: test_read.pl eof_in_comment
    @testset "eof_in_comment" begin                 # Ctx == string("", 0)
        _rt_atom_ball(db, "abcdef")
        rc, ball = _rt_atom_ball(db, "/* x")
        @test rc === :exception &&
            lk_eq(child(ball, 3), _rtf("string", lk_gnd(_RT, ""), lk_gnd(_RT, 0)))
    end
    # cycles(Bool) was written as int, overwriting dotlists
    dotted = "'.'(a,b)"
    ab = _rtf("[|]", _rts("a"), _rts("b"))
    opt(n, v) = _rtf(n, _rts(v))
    # PORT: test_read.pl dotlists
    @testset "dotlists" begin                       # T == [a|b]
        rc, t = _rt_read_opts(db, dotted, _rtl(opt("dotlists", "true")))
        @test rc === :true && lk_eq(t, ab)
    end
    # PORT: test_read.pl dotlists_cycles
    @testset "dotlists_cycles" begin
        rc, t = _rt_read_opts(
            db, dotted, _rtl(opt("dotlists", "true"), opt("cycles", "true"))
        )
        @test rc === :true && lk_eq(t, ab)
    end
    # PORT: test_read.pl dotlists_cycles
    @testset "dotlists_cycles" begin
        rc, t = _rt_read_opts(
            db, dotted, _rtl(opt("dotlists", "true"), opt("cycles", "false"))
        )
        @test rc === :true && lk_eq(t, ab)
    end
    # PORT: test_read.pl dotlists_cycles
    @testset "dotlists_cycles" begin
        rc, t = _rt_read_opts(
            db, dotted, _rtl(opt("cycles", "true"), opt("dotlists", "true"))
        )
        @test rc === :true && lk_eq(t, ab)
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
    # 0' at the end of the text used to read beyond the end
    # PORT: test_read.pl quote_eos
    @testset "quote_eos" begin                      # atom_number('0\'', _) fails
        rc, _ = _rt_call(
            db, "atom_number", _RT[_rts("0'"), mk_var(_RT, LK.fresh_var_keys!(1))]
        )
        @test rc === :false
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
