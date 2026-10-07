# UPSTREAM: swipl-devel tests/core_text/test_op.pl @ bae881a2
# CLASS: code
# COPYRIGHT: Copyright (c)  2009-2021, University of Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# swipl-devel's test_op.pl — the `op_syntax` units — against the parser (src/pl-read.jl, since
# R1d), through `term_string/2` and the query API. Upstream declares 72 operators in the test module
# (`xf100` … `yfx1200`: every type at every hundred) and parses with `module(M)`; here they are
# declared with op/3 in `user`, where `term_string/2` reads (no module option until read_term/3's
# options). R1b's operator gate is test/core_lang/test_op_swipl.jl.
#
# NOT PORTED, and why:
#   plus, no_atom, bad_type, bad_precedence, inherit   current_op/3: non-deterministic (V9)
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _OT = lk_term_type(Union{Int64, Float64, String})
_ots(x) = lk_sym(_OT, Symbol(x))
_otf(f, xs::_OT...) = mk_expr(_OT, _OT[_ots(f), xs...])

"Run `name(args…)` through the query API: `(rc, resolved args or [ball])`."
function _ot_call(gd, ld, name::String, args::Vector{_OT})
    proc = LK.isCurrentProcedure(sym_key(_ots(name)), length(args), LK.MODULE_system(gd))
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
        (:false, _OT[])
    end
    LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
    return out
end

# the test module's operators: every type at every priority from 100 to 1200
const _OT_DB = let gd = LK.PL_global_data{_OT}(), ld = LK.PL_local_data{_OT}()
    for t in ("xf", "yf", "fx", "fy", "xfx", "xfy", "yfx"), p in 100:100:1200
        rc, _ = _ot_call(gd, ld, "op", _OT[lk_gnd(_OT, p), _ots(t), _ots("$t$p")])
        rc === :true || error("op($p, $t, $t$p) failed")
    end
    (gd, ld)
end

"parse(String, Term): `term_string(Term, String)` — `(rc, Term or the ball)`."
function _ot_parse(text::String)
    rc, ans = _ot_call(
        _OT_DB..., "term_string", _OT[mk_var(_OT, LK.fresh_var_keys!(1)), lk_gnd(_OT, text)]
    )
    return (rc, isempty(ans) ? nothing : ans[1])
end

@testset "op_syntax" begin
    # PORT: test_op.pl parse
    @testset "parse" begin                          # Term == xf200(xf100)
        rc, t = _ot_parse("xf100 xf200")
        @test rc === :true && lk_eq(t, _otf("xf200", _ots("xf100")))
    end
    # PORT: test_op.pl parse
    @testset "parse" begin                          # error(syntax_error(_))
        rc, ball = _ot_parse("xf100 xf200 xf100")
        @test rc === :exception && lk_name(child(child(ball, 2), 1)) === :syntax_error
    end
    # PORT: test_op.pl parse
    @testset "parse" begin                          # Term == xf200(fx100(1))
        rc, t = _ot_parse("fx100 1 xf200")
        @test rc === :true && lk_eq(t, _otf("xf200", _otf("fx100", lk_gnd(_OT, 1))))
    end
    # PORT: test_op.pl parse
    @testset "parse" begin                          # Term == ','(p, xfy900(yf100(q),c))
        rc, t = _ot_parse("p, q yf100 xfy900 c")
        @test rc === :true &&
            lk_eq(
            t, _otf(",", _ots("p"), _otf("xfy900", _otf("yf100", _ots("q")), _ots("c")))
        )
    end
end
