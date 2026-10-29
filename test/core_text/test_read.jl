# UPSTREAM: swipl-devel tests/core_text/test_read.pl @ cbf4e1896275
# CLASS: code
# COPYRIGHT: Copyright (c)  2011-2024, University of Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# swipl-devel's test_read.pl — the `read_op`, `read_numbers` and `read_deep` units, and the units
# of `read_term` that came with upstream's fixes of 2026-10-11 — against the
# parser (src/pl-read.jl, since R1d), through `term_string/2` and the query API. Since LB1 the term
# positions: `valid_position_*` and `pos_block` through read_term_from_atom/3 with
# `subterm_positions(P)` (upstream's `term_position_check` calls term_string/3, a library predicate
# over the same reader and options), the term and the position compared as upstream asserts them;
# `valid_term_position/2` (library(prolog_source)) is not run — the positions of every text of the
# reader's corpora are compared with swipl's in test_read_positions_swipl.jl. `read_op`'s
# operators (`:- op(600, fy, !)`, `:- op(600, fy, [])` — a BLOCK operator) are made with op/3 in
# `user`, where `term_string/2` reads (upstream passes `module(M)`, an option of term_string/3).
# `read_deep` reads terms nested 20,000 deep: the parser's state machine must not use Julia stack
# in proportion to the nesting, as upstream's must not use C stack.
#
# NOT PORTED, and why:
#   singletons, warn_singletons                  read_term/2,3's singletons(…) option, and the
#                                                warning (no message system): PL_scan_options
#   position                                     the comments(…) read option (R2: the comments
#                                                collector)
#   positions                                    valid_term_position/2 is library(prolog_source);
#                                                its text's positions are compared with swipl's
#                                                in test_read_positions_swipl.jl
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
        (:true, lk_answers(ld, (a:(a + length(args) - 1))...))
    elseif rc == LK.PL_S_EXCEPTION
        (:exception, [lk_answer(ld, LK.PL_exception(ld, qid))])
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

"""
`read_term_from_atom(Text, T, [subterm_positions(P)|Options])`: `(rc, T, P)` — upstream's
`term_position_check` reads with term_string/3, a library predicate over the same reader.
"""
function _rt_read_pos(db, text::String, opts::_RT...)
    p = mk_var(_RT, LK.fresh_var_keys!(1))
    rc, ans = _rt_call(
        db, "read_term_from_atom",
        _RT[_rts(text), mk_var(_RT, LK.fresh_var_keys!(1)),
            _rtl(_rtf("subterm_positions", p), opts...)]
    )
    rc === :true || return (rc, nothing, nothing)
    return (rc, ans[2], child(child(ans[3], 2), 2))  # [subterm_positions(P)|_]: P
end

"""
Upstream's `term_position_check(TermString, ExpectedTerm, ExpectedTermPos, Options)`: the
position ground, the term a variant of the expected one, the position identical to the expected
one (its `valid_term_position/2` is library(prolog_source): not run, see the header).
"""
function _rt_term_position_check(db, text::String, expected, expected_pos, opts::_RT...)
    rc, t, pos = _rt_read_pos(db, text, opts...)
    @test rc === :true
    rc === :true || return nothing
    @test is_ground(pos)
    @test is_ground(expected_pos)
    @test LK.is_variant_ptr(t, expected)
    @test lk_eq(pos, expected_pos)
    return nothing
end

_rti(n) = lk_gnd(_RT, n)
_rtp(a, b) = _rtf("-", _rti(a), _rti(b))            # From-To

@testset "read_term" begin
    db = _rt_db([])
    _rtv() = mk_var(_RT, LK.fresh_var_keys!(1))
    # PORT: test_read.pl valid_position_var
    @testset "valid_position_var" begin
        _rt_term_position_check(db, "Var", _rtv(), _rtp(0, 3))
    end
    # PORT: test_read.pl valid_position_atom
    @testset "valid_position_atom" begin
        _rt_term_position_check(db, "'Atom'", _rts("Atom"), _rtp(0, 6))
    end
    # PORT: test_read.pl valid_position_number1
    @testset "valid_position_number1" begin
        _rt_term_position_check(db, " 123 ", _rti(123), _rtp(1, 4))
    end
    # PORT: test_read.pl valid_position_number2
    @testset "valid_position_number2" begin
        _rt_term_position_check(db, " -123.45     ", _rti(-123.45), _rtp(1, 8))
    end
    # (upstream sets the double_quotes FLAG around each of the four; the kernel has no Prolog
    # flags yet: `string` is its default, the other three are read with the double_quotes(…) READ
    # option, which sets the same syntax bits for the read)
    spos = _rtf("string_position", _rti(0), _rti(5))
    # PORT: test_read.pl valid_position_string_string
    @testset "valid_position_string_string" begin
        _rt_term_position_check(db, "\"abc\"", lk_gnd(_RT, "abc"), spos)
    end
    # PORT: test_read.pl valid_position_string_codes
    @testset "valid_position_string_codes" begin
        _rt_term_position_check(
            db, "\"abc\"", _rtl(_rti(97), _rti(98), _rti(99)), spos,
            _rtf("double_quotes", _rts("codes"))
        )
    end
    # PORT: test_read.pl valid_position_string_chars
    @testset "valid_position_string_chars" begin
        _rt_term_position_check(
            db, "\"abc\"", _rtl(_rts("a"), _rts("b"), _rts("c")), spos,
            _rtf("double_quotes", _rts("chars"))
        )
    end
    # PORT: test_read.pl valid_position_string_atom
    @testset "valid_position_string_atom" begin
        _rt_term_position_check(
            db, "\"abc\"", _rts("abc"), spos, _rtf("double_quotes", _rts("atom"))
        )
    end
    # PORT: test_read.pl valid_position_nil
    @testset "valid_position_nil" begin
        _rt_term_position_check(db, " [   ] ", mk_nil(_RT), _rtp(1, 6))
    end
    # PORT: test_read.pl valid_position_braces
    @testset "valid_position_braces" begin
        _rt_term_position_check(
            db, " { foo, bar } ", _rtf("{}", _rtf(",", _rts("foo"), _rts("bar"))),
            _rtf(
                "brace_term_position", _rti(1), _rti(13),
                _rtf(
                    "term_position", _rti(3), _rti(11), _rti(6), _rti(7),
                    _rtl(_rtp(3, 6), _rtp(8, 11))
                )
            )
        )
    end
    # PORT: test_read.pl valid_position_braces1
    @testset "valid_position_braces1" begin
        _rt_term_position_check(
            db, " [ foo, [bar] ] ", _rtl(_rts("foo"), _rtl(_rts("bar"))),
            _rtf(
                "list_position", _rti(1), _rti(15),
                _rtl(
                    _rtp(3, 6),
                    _rtf(
                        "list_position", _rti(8), _rti(13), _rtl(_rtp(9, 12)), _rts("none")
                    )
                ),
                _rts("none")
            )
        )
    end
    # PORT: test_read.pl valid_position_braces2
    @testset "valid_position_braces2" begin
        _rt_term_position_check(
            db, " [ foo,123 | bar] ",
            _rtf("[|]", _rts("foo"), _rtf("[|]", _rti(123), _rts("bar"))),
            _rtf(
                "list_position", _rti(1), _rti(17), _rtl(_rtp(3, 6), _rtp(7, 10)),
                _rtp(13, 16)
            )
        )
    end
    # PORT: test_read.pl valid_position_braces3
    @testset "valid_position_braces3" begin
        _rt_term_position_check(
            db, "[X|Xs]", _rtf("[|]", _rtv(), _rtv()),
            _rtf("list_position", _rti(0), _rti(6), _rtl(_rtp(1, 2)), _rtp(3, 5))
        )
    end
    # PORT: test_read.pl valid_position_term1
    @testset "valid_position_term1" begin
        _rt_term_position_check(
            db, "a()", mk_expr(_RT, _RT[_rts("a")]),
            _rtf("term_position", _rti(0), _rti(3), _rti(0), _rti(1), mk_nil(_RT))
        )
    end
    # PORT: test_read.pl valid_position_term2
    @testset "valid_position_term2" begin
        _rt_term_position_check(
            db, "a(X,y)", _rtf("a", _rtv(), _rts("y")),
            _rtf(
                "term_position", _rti(0), _rti(6), _rti(0), _rti(1),
                _rtl(_rtp(2, 3), _rtp(4, 5))
            )
        )
    end
    # PORT: test_read.pl valid_position_term2
    @testset "valid_position_term2" begin
        _rt_term_position_check(
            db, "call(X):[adder]", _rtf(":", _rtf("call", _rtv()), _rtl(_rts("adder"))),
            _rtf(
                "term_position", _rti(0), _rti(15), _rti(7), _rti(8),
                _rtl(
                    _rtf(
                        "term_position",
                        _rti(0),
                        _rti(7),
                        _rti(0),
                        _rti(4),
                        _rtl(_rtp(5, 6))
                    ),
                    _rtf(
                        "list_position", _rti(8), _rti(15), _rtl(_rtp(9, 14)), _rts("none")
                    )
                )
            )
        )
    end
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
    # context of unterminated quoted text or comment held only one byte (upstream 7f8024cc7, BP2)
    # PORT: test_read.pl eof_in_quoted_ctx
    @testset "eof_in_quoted_ctx" begin              # Ctx == string("foo('x", 4)
        rc, ball = _rt_atom_ball(db, "foo('x")
        @test rc === :exception &&
            lk_eq(child(ball, 3), _rtf("string", lk_gnd(_RT, "foo('x"), lk_gnd(_RT, 4)))
    end
    # PORT: test_read.pl eof_in_quoted_ctx (second unit: a quote of two bytes, « at the start)
    @testset "eof_in_quoted_ctx multibyte" begin    # Ctx == string(S, 0)
        txt = String(Char[Char(0xAB), 'x', ' ', '\'', 'y'])      # the unit's code list
        rc, ball = _rt_atom_ball(db, txt)
        @test rc === :exception &&
            lk_eq(child(ball, 3), _rtf("string", lk_gnd(_RT, txt), lk_gnd(_RT, 0)))
    end
    # PORT: test_read.pl eof_in_comment_ctx
    @testset "eof_in_comment_ctx" begin             # Offset == 2
        rc, ball = _rt_atom_ball(db, "a /* x")
        @test rc === :exception && kind(child(ball, 3)) === EXPR &&
            lk_eq(child(child(ball, 3), 3), lk_gnd(_RT, 2))
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
    # PORT: test_read.pl pos_block
    @testset "pos_block" begin                      # the block operator's position (since LB1)
        _rt_term_position_check(
            db, "![x]", _rtf("!", _rtl(_rts("x"))),
            _rtf(
                "term_position", _rti(0), _rti(4), _rti(0), _rti(1),
                _rtl(
                    _rtf("list_position", _rti(1), _rti(4), _rtl(_rtp(2, 3)), _rts("none"))
                )
            )
        )
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
