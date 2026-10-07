# UPSTREAM: swipl-devel tests/core_text/test_syntax.pl @ bae881a2
# CLASS: code
# COPYRIGHT: Copyright (c)  2024, SWI-Prolog Solutions b.v.
#
# swipl-devel's test_syntax.pl — the `syntax` and `iso_op_table_6` units — against the parser
# (src/pl-read.jl, since R1d), through `term_string/2` and the query API. Upstream's units are
# plunit tests; each reads its text as upstream's does and compares the term (`==`, the standard
# order) or the syntax error's formal. A unit that reads its OWN SOURCE upstream (`atom_1`,
# `char_*`, `string_*`, `quote_2`..`quote_6`, `base_1`..`base_3`, `base_5`) reads that source text
# here. The operators upstream declares in the test module (`:- op(600, fx, fx600)`, …) are made
# with op/3 in `user`, where `term_string/2` reads (no module option until read_term/3's options).
#
# NOT PORTED, and why:
#   base_4   `A = 1, B is A+1, B == 2`: evaluation, nothing the reader decides.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _SY = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_sys(x) = lk_sym(_SY, Symbol(x))
_syf(f, xs::_SY...) = mk_expr(_SY, _SY[_sys(f), xs...])
_syi(i) = lk_gnd(_SY, i)

"A database of its own, with the operators `ops` (`(priority, type, name)`) declared by op/3."
function _sy_db(ops)
    gd, ld = LK.PL_global_data{_SY}(), LK.PL_local_data{_SY}()
    for (p, t, n) in ops
        rc, _ = _sy_call(gd, ld, "op", _SY[_syi(p), _sys(t), _sys(n)])
        rc === :true || error("op($p, $t, $n) failed")
    end
    return (gd, ld)
end

"Run `name(args…)` through the query API: `(:true, resolved args)`, `(:exception, [ball])` or `(:false, [])`."
function _sy_call(gd, ld, name::String, args::Vector{_SY})
    proc = LK.isCurrentProcedure(sym_key(_sys(name)), length(args), LK.MODULE_system(gd))
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
        (:false, _SY[])
    end
    LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
    return out
end

"`term_string(T, Text)` in database `db`: the term read, or `nothing` after an exception or a failure."
function _sy_read(db, text::String)
    rc, ans = _sy_call(
        db..., "term_string", _SY[mk_var(_SY, LK.fresh_var_keys!(1)), lk_gnd(_SY, text)]
    )
    return rc === :true ? ans[1] : nothing
end

"The formal of the `error(syntax_error(Formal), _)` that `term_string(T, Text)` raises, or `nothing`."
function _sy_syntax_error(db, text::String)
    rc, ans = _sy_call(
        db..., "term_string", _SY[mk_var(_SY, LK.fresh_var_keys!(1)), lk_gnd(_SY, text)]
    )
    rc === :exception || return nothing
    f = child(ans[1], 2)                            # error(syntax_error(F), _)
    return if kind(f) === EXPR && lk_name(child(f, 1)) === :syntax_error
        child(f, 2)
    else
        nothing
    end
end

const _SY_SYNTAX = _sy_db([(600, "fx", "fx600"), (600, "fy", "fy600"), (500, "xf", "xf500"),
    (100, "yf", "af")])

@testset "syntax" begin
    db = _SY_SYNTAX
    # PORT: test_syntax.pl op_1
    @testset "op_1" begin
        @test lk_eq(_sy_read(db, "3+4*5"), _syf("+", _syi(3), _syf("*", _syi(4), _syi(5))))
    end
    # PORT: test_syntax.pl op_2
    @testset "op_2" begin
        @test lk_eq(_sy_read(db, "1+2+3"), _syf("+", _syf("+", _syi(1), _syi(2)), _syi(3)))
    end
    # PORT: test_syntax.pl op_3
    @testset "op_3" begin
        @test lk_eq(_sy_syntax_error(db, "a:-b:-c"), _sys("operator_clash"))
    end
    # PORT: test_syntax.pl op_4
    @testset "op_4" begin
        @test lk_eq(_sy_read(db, "fx600 1+2"), _syf("fx600", _syf("+", _syi(1), _syi(2))))
    end
    # PORT: test_syntax.pl op_5
    @testset "op_5" begin
        @test lk_eq(_sy_syntax_error(db, "fx600 fx600 1"), _sys("operator_clash"))
    end
    # PORT: test_syntax.pl op_6
    @testset "op_6" begin
        @test lk_eq(_sy_read(db, "fy600 fy600 1"), _syf("fy600", _syf("fy600", _syi(1))))
    end
    # PORT: test_syntax.pl op_7
    @testset "op_7" begin
        @test lk_eq(_sy_read(db, "fy600 a xf500"), _syf("fy600", _syf("xf500", _sys("a"))))
    end
    # PORT: test_syntax.pl op_8
    @testset "op_8" begin                           # assume 200 fy and 500 yfx
        @test lk_eq(_sy_read(db, "- - a"), _syf("-", _syf("-", _sys("a"))))
    end
    # PORT: test_syntax.pl atom_1
    @testset "atom_1" begin                         # atom_codes('\003\\'\n\x80\', X)
        t = _sy_read(db, raw"'\003\\'\n\x80\'")
        @test kind(t) === SYM && Int.(collect(String(lk_name(t)))) == [3, 39, 10, 128]
    end
    # PORT: test_syntax.pl char_1
    @testset "char_1" begin                         # 10 == 0'\n
        @test lk_eq(_sy_read(db, raw"0'\n"), _syi(10))
    end
    # PORT: test_syntax.pl char_2
    @testset "char_2" begin                         # 52 == 0'\x34
        @test lk_eq(_sy_read(db, raw"0'\x34"), _syi(52))
    end
    # PORT: test_syntax.pl char_3
    @testset "char_3" begin                         # "\\" =:= 0'\\
        @test lk_eq(_sy_read(db, "0'\\\\"), _syi(92))
    end
    # PORT: test_syntax.pl char_4
    @testset "char_4" begin                         # 1-48 == 1-0'0
        @test lk_eq(_sy_read(db, "1-0'0"), _syf("-", _syi(1), _syi(48)))
    end
    # PORT: test_syntax.pl cannot_start_term_1
    @testset "cannot_start_term_1" begin
        @test lk_eq(_sy_syntax_error(db, "p(]"), _sys("cannot_start_term"))
    end
    # PORT: test_syntax.pl string_1
    @testset "string_1" begin                       # '\c ' == ''
        @test lk_eq(_sy_read(db, raw"'\c '"), _sys(""))
    end
    # PORT: test_syntax.pl string_2
    @testset "string_2" begin                       # 'x\c y' == xy
        @test lk_eq(_sy_read(db, raw"'x\c y'"), _sys("xy"))
    end
    # PORT: test_syntax.pl quote_1
    @testset "quote_1" begin
        @test lk_eq(
            _sy_syntax_error(db, raw"'\x'"), _syf("undefined_char_escape", _sys("x"))
        )
    end
    # PORT: test_syntax.pl quote_2
    @testset "quote_2" begin                        # '\x61' == a
        @test lk_eq(_sy_read(db, raw"'\x61'"), _sys("a"))
    end
    # PORT: test_syntax.pl quote_3
    @testset "quote_3" begin                        # '\x61\' == a
        @test lk_eq(_sy_read(db, raw"'\x61\'"), _sys("a"))
    end
    # PORT: test_syntax.pl quote_4
    @testset "quote_4" begin                        # char_code('\'', 39)
        @test lk_eq(_sy_read(db, raw"'\''"), _sys("'"))
    end
    # PORT: test_syntax.pl quote_5
    @testset "quote_5" begin                        # 0'\' == 0''
        @test lk_eq(_sy_read(db, raw"0'\'"), _syi(39)) &&
            lk_eq(_sy_read(db, "0''"), _syi(39))
    end
    # PORT: test_syntax.pl quote_6
    @testset "quote_6" begin                        # 0'\' == 0'''
        @test lk_eq(_sy_read(db, raw"0'\'"), _sy_read(db, "0'''"))
    end
    # PORT: test_syntax.pl quote_7
    @testset "quote_7" begin                        # term_string(T, '\'\\\n\''), T == ''
        @test lk_eq(_sy_read(db, "'\\\n'"), _sys(""))
    end
    # PORT: test_syntax.pl base_1
    @testset "base_1" begin                         # 1+1 == 1+1
        @test lk_eq(_sy_read(db, "1+1"), _syf("+", _syi(1), _syi(1)))
    end
    # PORT: test_syntax.pl base_2
    @testset "base_2" begin                         # 16'af == 175
        @test lk_eq(_sy_read(db, "16'af"), _syi(175))
    end
    # PORT: test_syntax.pl base_3
    @testset "base_3" begin                         # 10 af == af(10)
        @test lk_eq(_sy_read(db, "10 af"), _syf("af", _syi(10)))
    end
    # PORT: test_syntax.pl base_5
    @testset "base_5" begin                         # A is 1.0e+0+1: the text read
        @test lk_eq(_sy_read(db, "1.0e+0+1"), _syf("+", lk_gnd(_SY, 1.0), _syi(1)))
    end
    # PORT: test_syntax.pl number_2
    @testset "number_2" begin
        @test lk_eq(_sy_syntax_error(db, "2'"), _sys("end_of_file"))
    end
    # PORT: test_syntax.pl neg_base
    @testset "neg_base" begin
        @test lk_eq(_sy_read(db, "-16'2f"), _syi(-47))
    end
    # PORT: test_syntax.pl zero_1
    @testset "zero_1" begin                         # hello("\000\x"): a string of [0, 120]
        t = _sy_read(db, "hello(\"\\000\\x\")")
        @test kind(t) === EXPR && lk_name(child(t, 1)) === :hello
        a0 = child(t, 2)
        @test kind(a0) === GND && Int.(collect(lk_value(a0))) == [0, 120]
    end
    # PORT: test_syntax.pl latin_1
    @testset "latin_1" begin                        # atom_codes(A, [247]), term_string(T, A)
        t = _sy_read(db, String([Char(247)]))
        @test kind(t) === SYM && Int.(collect(String(lk_name(t)))) == [247]
    end
    # The `<type>(...)` notation is a syntax error by default (blobs need blob(dead|resolve)).
    # PORT: test_syntax.pl blob_default
    @testset "blob_default" begin
        @test lk_eq(_sy_syntax_error(db, "<stream>(0x40e8900)"), _sys("operator_expected"))
    end
    # PORT: test_syntax.pl blob_default_arg
    @testset "blob_default_arg" begin
        @test lk_eq(_sy_syntax_error(db, "f(<a>(b))"), _sys("operator_expected"))
    end
    # PORT: test_syntax.pl blob_default_list
    @testset "blob_default_list" begin
        @test lk_eq(_sy_syntax_error(db, "[<a>(b)]"), _sys("operator_expected"))
    end
    # PORT: test_syntax.pl blob_default_dashed
    @testset "blob_default_dashed" begin
        @test lk_eq(_sy_syntax_error(db, "<rdf-snapshot>(b)"), _sys("operator_expected"))
    end
    # PORT: test_syntax.pl blob_default_hex
    @testset "blob_default_hex" begin
        @test lk_eq(_sy_syntax_error(db, "<#0102ff>"), _sys("operator_expected"))
    end
    # PORT: test_syntax.pl blob_infix_clash
    @testset "blob_infix_clash" begin
        @test lk_eq(_sy_syntax_error(db, "a<b>(c)"), _sys("operator_clash"))
    end
    # PORT: test_syntax.pl blob_not_canonical_lt
    @testset "blob_not_canonical_lt" begin
        @test lk_eq(_sy_read(db, "<(a,b)"), _syf("<", _sys("a"), _sys("b")))
    end
    # PORT: test_syntax.pl blob_not_diamond
    @testset "blob_not_diamond" begin
        @test lk_eq(_sy_read(db, "<>(a)"), _syf("<>", _sys("a")))
    end
    # PORT: test_syntax.pl blob_not_comparison
    @testset "blob_not_comparison" begin
        @test lk_eq(
            _sy_read(db, "f(a<b, c>d)"),
            _syf("f", _syf("<", _sys("a"), _sys("b")), _syf(">", _sys("c"), _sys("d")))
        )
    end
end

@testset "iso_op_table_6" begin
    db = _sy_db([
        (100, "fy", "fy"), (100, "xfy", "xfy"), (100, "yfx", "yfx"), (100, "yf", "yf")
    ])
    # PORT: test_syntax.pl r1
    @testset "r1" begin
        @test lk_eq(_sy_read(db, "fy fy 1"), _syf("fy", _syf("fy", _syi(1))))
    end
    # PORT: test_syntax.pl r2
    @testset "r2" begin
        @test lk_eq(
            _sy_read(db, "1 xfy 2 xfy 3"),
            _syf("xfy", _syi(1), _syf("xfy", _syi(2), _syi(3)))
        )
    end
    # PORT: test_syntax.pl r3
    @testset "r3" begin
        @test lk_eq(
            _sy_read(db, "1 xfy 2 yfx 3"),
            _syf("xfy", _syi(1), _syf("yfx", _syi(2), _syi(3)))
        )
    end
    # PORT: test_syntax.pl r4
    @testset "r4" begin
        @test lk_eq(_sy_read(db, "fy 2 yf"), _syf("fy", _syf("yf", _syi(2))))
    end
    # PORT: test_syntax.pl r5
    @testset "r5" begin
        @test lk_eq(_sy_read(db, "1 yf yf"), _syf("yf", _syf("yf", _syi(1))))
    end
    # PORT: test_syntax.pl r6
    @testset "r6" begin
        @test lk_eq(
            _sy_read(db, "1 yfx 2 yfx 3"),
            _syf("yfx", _syf("yfx", _syi(1), _syi(2)), _syi(3))
        )
    end
end
