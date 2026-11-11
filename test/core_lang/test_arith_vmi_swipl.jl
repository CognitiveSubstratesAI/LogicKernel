# ORIGINAL: kernel-only white-box rows of the A_* instructions (pl-vmi.c A_ENTER .. A_FIRSTVAR_IS) — swipl cannot answer a hand-built clause
# test/core_lang/test_arith_vmi_swipl.jl — AR1 d2b: each row runs a tiny HAND-BUILT clause through the arms of
# src/pl-wam.jl: `h(A, B, C) :- g(A, B, C)` is compiled and asserted, then its codes and literals are REPLACED by the row's
# (the pattern of test/foreign/test_query.jl), and the query `h(Arg1, Arg2)` runs it. The rows read the arithmetic
# stack (`ld.arith_numbers`, `ld.arith_top`) where the instructions leave it, or the arguments they bind. The compile
# side (compileArith, AR1 d3) is not written: these rows do not need it.
# UNTESTED on the kernel: written without a compile, the gate decides
using Test, LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _VT = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
const LKV = LogicKernel
_vs(x) = lk_sym(_VT, Symbol(x))
_vg(x) = lk_gnd(_VT, x)
_vf(f, xs::_VT...) = mk_expr(_VT, _VT[_vs(f), xs...])
const _vkey = Ref(UInt64(100))
_vv() = (_vkey[] += 1; lk_var(_VT, _vkey[]))
const _vn = Ref(0)

# the value a pooled number holds
_vnum(n) =
    n.type === LKV.V_INTEGER ? n.i :
    n.type === LKV.V_MPZ ? n.mpz : n.type === LKV.V_MPQ ? n.mpq : n.f

# an Int operand as a code word (`A_INTEGER`'s `(scode) *PC++`)
_vi(i::Integer) = reinterpret(LKV.code, Int64(i))

"""
Run `h(args...)` with the clause body replaced by `codes` (between I_ENTER and I_EXIT) and its literals by `lits`: the
return code and the exception term's printed form when there is one.
"""
function _vrun(gd, ld, body::Vector{LKV.code}, lits::Vector{_VT}, args::Vector{_VT}; top0::Int=0)
    _vn[] += 1
    name = Symbol("h", _vn[])
    user = LKV.MODULE_user(gd)
    A, B, C = _vv(), _vv(), _vv()
    hd = _vf(name, A, B, C)
    pr = LKV.lookupProcedure(child(hd, 1), nchildren(hd) - 1, user)
    cl = LKV.compileClause(gd, ld, hd, _vf(:g, A, B, C), pr, user)
    LKV.assertDefinition!(gd, pr.definition, cl, LKV.CL_END)
    new = vcat(LKV.code[LKV.I_ENTER], body, LKV.code[LKV.I_EXIT])
    splice!(cl.codes, 1:length(cl.codes), new)          # the row's code, in place (the supervisor reads the clause)
    empty!(cl.literals)
    append!(cl.literals, lits)
    ld.arith_top = 0
    for _ in 1:top0                                     # numbers a caller's evaluation holds
        LKV._number_alloc!(ld)
    end
    fid = LKV.PL_open_foreign_frame(ld)
    a = LKV.PL_new_term_refs(ld, length(args))
    pvm = LKV.PutVarMap()
    for (k, t) in enumerate(args)
        LKV.putSlotValue!(ld, a + k, t, pvm)
    end
    qid = LKV.PL_open_query(
        gd, ld, nothing, LKV.PL_Q_CATCH_EXCEPTION | LKV.PL_Q_EXT_STATUS, pr, a
    )
    rc = LKV.PL_next_solution(gd, ld, qid)
    out = rc == LKV.PL_S_EXCEPTION ? lk_answer(ld, LKV.PL_exception(ld, qid)) : nothing
    LKV.PL_close_query(ld, qid)
    LKV.PL_close_foreign_frame(ld, fid)
    return rc, out
end

@testset "AR1 d2b (constants and variables): A_ENTER, A_INTEGER, A_MPZ, A_MPQ, A_DOUBLE, A_VAR, A_VAR0, A_VAR1, A_VAR2" begin
    gd = LKV.PL_global_data{_VT}()
    ld = LKV.PL_local_data{_VT}(gd)
    # A_ENTER; A_INTEGER 7; A_INTEGER -3; A_VAR0, A_VAR1, A_VAR2 (the three arguments); A_MPZ 2; A_MPQ 3; A_DOUBLE 1
    body = LKV.code[
        LKV.A_ENTER, LKV.A_INTEGER, _vi(7), LKV.A_INTEGER, _vi(-3), LKV.A_VAR0, LKV.A_VAR1, LKV.A_VAR2,
        LKV.A_MPZ, LKV.code(2), LKV.A_MPQ, LKV.code(3), LKV.A_DOUBLE, LKV.code(1),
    ]
    lits = _VT[_vg(2.5), _vg(big(2)^80), _vg(big(7) // big(9))]
    for (a1, a2, w1, w2) in (
        (_vg(5), _vg(2.5), 5, 2.5),                             # a tagged integer, a float: the fast paths
        (_vg(big(2)^70), _vg(1 // big(3)), big(2)^70, 1 // big(3)),   # a value-table integer and rational
        (_vf(:+, _vg(1), _vg(2)), _vg(4), 3, 4),                # an expression: the slow path, evaluated
    )
        rc, out = _vrun(gd, ld, body, lits, _VT[a1, a2, _vg(99)])
        @test rc != LKV.PL_S_FALSE && rc != LKV.PL_S_EXCEPTION
        @test ld.arith_top == 8                                 # eight numbers pushed, none popped
        st = ld.arith_numbers
        @test st[1].type === LKV.V_INTEGER && st[1].i == 7
        @test st[2].type === LKV.V_INTEGER && st[2].i == -3
        @test _vnum(st[3]) == w1
        @test _vnum(st[4]) == w2
        @test st[5].type === LKV.V_INTEGER && st[5].i == 99
        @test st[6].type === LKV.V_MPZ && st[6].mpz == big(2)^80
        @test st[7].type === LKV.V_MPQ && st[7].mpq == big(7) // big(9)
        @test st[8].type === LKV.V_FLOAT && st[8].f == 2.5
    end
    # an expression that raises: AR_THROW_EXCEPTION cuts the stack to the top A_ENTER found (a caller's numbers stay)
    for top0 in (0, 2)
        rc, out = _vrun(gd, ld, body, lits, _VT[_vs(:a), _vg(1), _vg(1)]; top0=top0)
        @test rc == LKV.PL_S_EXCEPTION
        @test ld.arith_top == top0
    end
    # A_VAR (the operand form), against A_VAR0/1's
    rc, out = _vrun(
        gd, ld, LKV.code[LKV.A_ENTER, LKV.A_VAR, LKV.VAROFFSET(1), LKV.A_VAR, LKV.VAROFFSET(0)],
        _VT[], _VT[_vg(10), _vg(20), _vg(30)],
    )
    @test rc != LKV.PL_S_FALSE && rc != LKV.PL_S_EXCEPTION
    @test ld.arith_top == 2 && ld.arith_numbers[1].i == 20 && ld.arith_numbers[2].i == 10
end
