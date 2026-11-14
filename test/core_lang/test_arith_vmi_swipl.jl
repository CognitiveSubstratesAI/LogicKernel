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
    if n.type === LKV.V_INTEGER
        n.i
    elseif n.type === LKV.V_MPZ
        n.mpz
    elseif n.type === LKV.V_MPQ
        n.mpq
    else
        n.f
    end

# an Int operand as a code word (`A_INTEGER`'s `(scode) *PC++`)
_vi(i::Integer) = reinterpret(LKV.code, Int64(i))

"""
Run `h(args...)` with the clause body replaced by `codes` (between I_ENTER and I_EXIT) and its literals by `lits`: the
return code and, when there is an exception, its term, else (an answer) the arguments as the query left them.
"""
function _vrun(
    gd, ld, body::Vector{LKV.code}, lits::Vector{_VT}, args::Vector{_VT}; top0::Int=0
)
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
    out = if rc == LKV.PL_S_EXCEPTION
        lk_answer(ld, LKV.PL_exception(ld, qid))
    elseif rc != LKV.PL_S_FALSE                         # an answer: the arguments as the query left them
        _VT[lk_answer(ld, a + k - 1) for k in 1:length(args)]
    else
        nothing
    end
    LKV.PL_close_query(ld, qid)
    LKV.PL_close_foreign_frame(ld, fid)
    return rc, out
end

@testset "AR1 d2b (constants and variables): A_ENTER, A_INTEGER, A_MPZ, A_MPQ, A_DOUBLE, A_VAR, A_VAR0, A_VAR1, A_VAR2" begin
    gd = LKV.PL_global_data{_VT}()
    ld = LKV.PL_local_data{_VT}(gd)
    # A_ENTER; A_INTEGER 7; A_INTEGER -3; A_VAR0, A_VAR1, A_VAR2 (the three arguments); A_MPZ 2; A_MPQ 3; A_DOUBLE 1
    body = LKV.code[
        LKV.A_ENTER, LKV.A_INTEGER, _vi(7), LKV.A_INTEGER, _vi(-3), LKV.A_VAR0, LKV.A_VAR1,
        LKV.A_VAR2,
        LKV.A_MPZ, LKV.code(2), LKV.A_MPQ, LKV.code(3), LKV.A_DOUBLE, LKV.code(1)
    ]
    lits = _VT[_vg(2.5), _vg(big(2)^80), _vg(big(7) // big(9))]
    for (a1, a2, w1, w2) in (
        (_vg(5), _vg(2.5), 5, 2.5),                             # a tagged integer, a float: the fast paths
        (_vg(big(2)^70), _vg(1 // big(3)), big(2)^70, 1 // big(3)),   # a value-table integer and rational
        (_vf(:+, _vg(1), _vg(2)), _vg(4), 3, 4)                # an expression: the slow path, evaluated
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
        gd, ld,
        LKV.code[LKV.A_ENTER, LKV.A_VAR, LKV.VAROFFSET(1), LKV.A_VAR, LKV.VAROFFSET(0)],
        _VT[], _VT[_vg(10), _vg(20), _vg(30)]
    )
    @test rc != LKV.PL_S_FALSE && rc != LKV.PL_S_EXCEPTION
    @test ld.arith_top == 2 && ld.arith_numbers[1].i == 20 && ld.arith_numbers[2].i == 10
end

# the 0-based function index the compile side writes (`indexArithFunction`, AR1 d1)
_vfi(name, arity) = LKV.indexArithFunction(_VT, sym_key(_vs(name)), arity)

@testset "AR1 d2b (functions): A_FUNC0, A_FUNC1, A_FUNC2, A_FUNC, A_ADD, A_MUL, A_ROUNDTOWARDS_A, A_ROUNDTOWARDS_V" begin
    gd = LKV.PL_global_data{_VT}()
    ld = LKV.PL_local_data{_VT}(gd)
    args3 = _VT[_vg(0), _vg(0), _vg(0)]
    run(body, lits=_VT[], args=args3; top0=0) =
        _vrun(gd, ld, LKV.code[body...], lits, args; top0=top0)
    ok(rc) = rc != LKV.PL_S_FALSE && rc != LKV.PL_S_EXCEPTION
    st = ld.arith_numbers
    # 10 - 3: the arguments are pushed right to left (the first argument is the LAST pushed): 7, one number left
    rc, _ = run(
        LKV.code[
            LKV.A_ENTER,
            LKV.A_INTEGER,
            _vi(3),
            LKV.A_INTEGER,
            _vi(10),
            LKV.A_FUNC2,
            LKV.code(_vfi(:-, 2))
        ]
    )
    @test ok(rc) && ld.arith_top == 1 && st[1].type === LKV.V_INTEGER && st[1].i == 7
    # -(9), pi, abs(-4) through the general A_FUNC with its argument count
    rc, _ = run(
        LKV.code[LKV.A_ENTER, LKV.A_INTEGER, _vi(9), LKV.A_FUNC1, LKV.code(_vfi(:-, 1))]
    )
    @test ok(rc) && ld.arith_top == 1 && st[1].i == -9
    rc, _ = run(LKV.code[LKV.A_ENTER, LKV.A_FUNC0, LKV.code(_vfi(:pi, 0))])
    @test ok(rc) && ld.arith_top == 1 && st[1].type === LKV.V_FLOAT &&
        st[1].f == Float64(pi)
    rc, _ = run(
        LKV.code[
            LKV.A_ENTER,
            LKV.A_INTEGER,
            _vi(-4),
            LKV.A_FUNC,
            LKV.code(_vfi(:abs, 1)),
            LKV.code(1)
        ]
    )
    @test ok(rc) && ld.arith_top == 1 && st[1].i == 4
    rc, _ = run(
        LKV.code[
            LKV.A_ENTER,
            LKV.A_INTEGER,
            _vi(3),
            LKV.A_INTEGER,
            _vi(10),
            LKV.A_FUNC,
            LKV.code(_vfi(:-, 2)),
            LKV.code(2)
        ]
    )
    @test ok(rc) && ld.arith_top == 1 && st[1].i == 7
    # an error in a function: 1 // 0 — the stack is cut to A_ENTER's top, the query raises
    for top0 in (0, 2)
        rc, _ = run(
            LKV.code[
                LKV.A_ENTER,
                LKV.A_INTEGER,
                _vi(0),
                LKV.A_INTEGER,
                _vi(1),
                LKV.A_FUNC2,
                LKV.code(_vfi(:(//), 2))
            ];
            top0=top0
        )
        @test rc == LKV.PL_S_EXCEPTION && ld.arith_top == top0
    end
    # A_ADD and A_MUL: small and past 64 bits; a float overflow raises (A_ADD)
    rc, _ = run(
        LKV.code[LKV.A_ENTER, LKV.A_INTEGER, _vi(3), LKV.A_INTEGER, _vi(4), LKV.A_ADD]
    )
    @test ok(rc) && ld.arith_top == 1 && st[1].type === LKV.V_INTEGER && st[1].i == 7
    rc, _ = run(
        LKV.code[
            LKV.A_ENTER,
            LKV.A_INTEGER,
            _vi(typemax(Int64)),
            LKV.A_INTEGER,
            _vi(1),
            LKV.A_ADD
        ]
    )
    @test ok(rc) && ld.arith_top == 1 && st[1].type === LKV.V_MPZ &&
        st[1].mpz == big(typemax(Int64)) + 1
    rc, _ = run(
        LKV.code[LKV.A_ENTER, LKV.A_INTEGER, _vi(6), LKV.A_INTEGER, _vi(7), LKV.A_MUL]
    )
    @test ok(rc) && ld.arith_top == 1 && st[1].i == 42
    rc, _ = run(
        LKV.code[
            LKV.A_ENTER,
            LKV.A_INTEGER,
            _vi(typemax(Int64)),
            LKV.A_INTEGER,
            _vi(2),
            LKV.A_MUL
        ]
    )
    @test ok(rc) && ld.arith_top == 1 && st[1].type === LKV.V_MPZ &&
        st[1].mpz == big(typemax(Int64)) * 2
    for (op, lit_codes) in ((LKV.A_ADD, nothing),)
        rc, _ = run(
            LKV.code[LKV.A_ENTER, LKV.A_DOUBLE, LKV.code(1), LKV.A_DOUBLE, LKV.code(1), op],
            _VT[_vg(1.0e308)];
            top0=2
        )
        @test rc == LKV.PL_S_EXCEPTION && ld.arith_top == 2
    end
    # roundtoward(1.0/3, to_positive) with the mode in the code (FLT_ROUND_TO_POS = 2): the next float up,
    # and the hardware mode is back to nearest after the evaluation; also after an error inside it
    lits = _VT[_vg(3.0), _vg(1.0)]
    third = LKV.code[
        LKV.A_DOUBLE,
        LKV.code(1),
        LKV.A_DOUBLE,
        LKV.code(2),
        LKV.A_FUNC2,
        LKV.code(_vfi(:/, 2))
    ]
    rt = LKV.code(_vfi(:roundtoward, 2))
    rc, _ = run(
        LKV.code[LKV.A_ENTER, LKV.A_ROUNDTOWARDS_A, LKV.code(2), third..., LKV.A_FUNC2, rt],
        lits
    )
    @test ok(rc) && ld.arith_top == 1 && st[1].type === LKV.V_FLOAT &&
        st[1].f == nextfloat(1.0 / 3)
    @test LKV.fegetround() == LKV.FE_TONEAREST
    rc, _ = run(
        LKV.code[
            LKV.A_ENTER,
            LKV.A_ROUNDTOWARDS_A,
            LKV.code(2),
            LKV.A_INTEGER,
            _vi(0),
            LKV.A_INTEGER,
            _vi(1),
            LKV.A_FUNC2,
            LKV.code(_vfi(:(//), 2))
        ]
    )
    @test rc == LKV.PL_S_EXCEPTION && LKV.fegetround() == LKV.FE_TONEAREST
    # the mode in a variable (A_ROUNDTOWARDS_V): an atom that names one, then one that names none, then a non-atom
    rc, _ = run(
        LKV.code[
            LKV.A_ENTER, LKV.A_ROUNDTOWARDS_V, LKV.VAROFFSET(0), third..., LKV.A_FUNC2, rt
        ],
        lits,
        _VT[_vs(:to_positive), _vg(0), _vg(0)]
    )
    @test ok(rc) && ld.arith_top == 1 && st[1].f == nextfloat(1.0 / 3)
    @test LKV.fegetround() == LKV.FE_TONEAREST
    rc, _ = run(
        LKV.code[
            LKV.A_ENTER, LKV.A_ROUNDTOWARDS_V, LKV.VAROFFSET(0), third..., LKV.A_FUNC2, rt
        ],
        lits,
        _VT[_vs(:to_zero), _vg(0), _vg(0)]
    )
    @test ok(rc) && st[1].f == 1.0 / 3                          # toward zero: the nearest here
    for (bad, formal) in (
        (_vs(:foo), "domain_error"), (_vg(1), "type_error"), (_vv(), "instantiation_error")
    )
        rc, out = run(
            LKV.code[
                LKV.A_ENTER,
                LKV.A_ROUNDTOWARDS_V,
                LKV.VAROFFSET(0),
                third...,
                LKV.A_FUNC2,
                rt
            ],
            lits,
            _VT[bad, _vg(0), _vg(0)]
        )
        @test rc == LKV.PL_S_EXCEPTION && ld.arith_top == 0
        @test sym_text(child(child(out, 2), 1)) == formal
        @test LKV.fegetround() == LKV.FE_TONEAREST
    end
end

@testset "AR1 d2b (comparisons): A_LT, A_LE, A_GT, A_GE, A_EQ, A_NE" begin
    gd = LKV.PL_global_data{_VT}()
    ld = LKV.PL_local_data{_VT}(gd)
    args3 = _VT[_vg(0), _vg(0), _vg(0)]
    run(body, lits=_VT[], args=args3; top0=0) =
        _vrun(gd, ld, LKV.code[body...], lits, args; top0=top0)
    ok(rc) = rc != LKV.PL_S_FALSE && rc != LKV.PL_S_EXCEPTION
    ops = (
        (LKV.A_LT, <), (LKV.A_LE, <=), (LKV.A_GT, >), (LKV.A_GE, >=), (LKV.A_EQ, ==),
        (LKV.A_NE, !=)
    )
    # a comparison pops both numbers (the left one was pushed FIRST) and succeeds or fails the query
    for (op, f) in ops, (x, y) in ((3, 4), (4, 4), (5, 4)), top0 in (0, 2)
        rc, _ = run(
            LKV.code[LKV.A_ENTER, LKV.A_INTEGER, _vi(x), LKV.A_INTEGER, _vi(y), op];
            top0=top0
        )
        @test (rc != LKV.PL_S_EXCEPTION) && (ok(rc) == f(x, y)) && ld.arith_top == top0
    end
    # two floats; a float and an integer (through ar_compare); an integer past 64 bits; a NaN (unordered, unequal)
    lits = _VT[_vg(1.5), _vg(2.5), _vg(2.0), _vg(big(2)^80), _vg(NaN)]
    for (op, f) in ops
        rc, _ = run(
            LKV.code[LKV.A_ENTER, LKV.A_DOUBLE, LKV.code(1), LKV.A_DOUBLE, LKV.code(2), op],
            lits
        )
        @test (rc != LKV.PL_S_EXCEPTION) && (ok(rc) == f(1.5, 2.5)) && ld.arith_top == 0
        rc, _ = run(
            LKV.code[LKV.A_ENTER, LKV.A_DOUBLE, LKV.code(3), LKV.A_DOUBLE, LKV.code(3), op],
            lits
        )
        @test (rc != LKV.PL_S_EXCEPTION) && (ok(rc) == f(2.0, 2.0)) && ld.arith_top == 0
        rc, _ = run(
            LKV.code[LKV.A_ENTER, LKV.A_INTEGER, _vi(2), LKV.A_DOUBLE, LKV.code(3), op],
            lits
        )
        @test (rc != LKV.PL_S_EXCEPTION) && (ok(rc) == f(2, 2.0)) && ld.arith_top == 0
        rc, _ = run(
            LKV.code[LKV.A_ENTER, LKV.A_DOUBLE, LKV.code(2), LKV.A_INTEGER, _vi(3), op],
            lits
        )
        @test (rc != LKV.PL_S_EXCEPTION) && (ok(rc) == f(2.5, 3)) && ld.arith_top == 0
        rc, _ = run(
            LKV.code[LKV.A_ENTER, LKV.A_MPZ, LKV.code(4), LKV.A_INTEGER, _vi(5), op], lits
        )
        @test (rc != LKV.PL_S_EXCEPTION) && (ok(rc) == f(big(2)^80, 5)) && ld.arith_top == 0
        rc, _ = run(
            LKV.code[LKV.A_ENTER, LKV.A_DOUBLE, LKV.code(5), LKV.A_DOUBLE, LKV.code(5), op],
            lits
        )
        @test (rc != LKV.PL_S_EXCEPTION) && (ok(rc) == f(NaN, NaN)) && ld.arith_top == 0
        rc, _ = run(
            LKV.code[LKV.A_ENTER, LKV.A_DOUBLE, LKV.code(5), LKV.A_INTEGER, _vi(1), op],
            lits
        )
        @test (rc != LKV.PL_S_EXCEPTION) && (ok(rc) == f(NaN, 1)) && ld.arith_top == 0
    end
    # AR_END puts the rounding mode back: A_ROUNDTOWARDS_A (mode 2) leaves its number below the two compared
    for (op, want) in ((LKV.A_LT, true), (LKV.A_GT, false))
        rc, _ = run(
            LKV.code[
                LKV.A_ENTER,
                LKV.A_ROUNDTOWARDS_A,
                LKV.code(2),
                LKV.A_INTEGER,
                _vi(1),
                LKV.A_INTEGER,
                _vi(2),
                op
            ]
        )
        @test (rc != LKV.PL_S_EXCEPTION) && ok(rc) == want
        @test ld.arith_top == 1 && LKV.fegetround() == LKV.FE_TONEAREST
    end
end

@testset "AR1 d2b (is): A_IS, A_FIRSTVAR_IS" begin
    gd = LKV.PL_global_data{_VT}()
    ld = LKV.PL_local_data{_VT}(gd)
    run(body, lits=_VT[], args=_VT[_vg(0), _vv(), _vg(0)]; top0=0) =
        _vrun(gd, ld, LKV.code[body...], lits, args; top0=top0)
    ok(rc) = rc != LKV.PL_S_FALSE && rc != LKV.PL_S_EXCEPTION
    st = ld.arith_numbers
    # X is 4 + 3, written `B_VAR1, A_ENTER, <expression>, A_IS` (the variable first: it goes to the argument cell of is/2)
    sum7 = LKV.code[
        LKV.B_VAR1,
        LKV.A_ENTER,
        LKV.A_INTEGER,
        _vi(4),
        LKV.A_INTEGER,
        _vi(3),
        LKV.A_ADD,
        LKV.A_IS
    ]
    rc, out = run(sum7)                                         # unbound: bound to 7
    @test ok(rc) && ld.arith_top == 0 && lk_eq(out[2], _vg(7))
    rc, out = run(sum7; top0=2)                                 # pops exactly the result
    @test ok(rc) && ld.arith_top == 2 && lk_eq(out[2], _vg(7))
    rc, _ = run(sum7, _VT[], _VT[_vg(0), _vg(7), _vg(0)])       # bound to the same integer: succeeds, ...
    @test ok(rc) && ld.arith_top == 0
    rc, _ = run(sum7, _VT[], _VT[_vg(0), _vg(8), _vg(0)])       # ... to another one: the body fails
    @test rc == LKV.PL_S_FALSE && ld.arith_top == 0
    rc, _ = run(sum7, _VT[], _VT[_vg(0), _vg(7.0), _vg(0)])     # 7 is not 7.0 (SWI's identity)
    @test rc == LKV.PL_S_FALSE && ld.arith_top == 0
    rc, _ = run(sum7, _VT[], _VT[_vg(0), _vf(:f, _vg(7)), _vg(0)])   # a compound never matches
    @test rc == LKV.PL_S_FALSE && ld.arith_top == 0
    # a float, an integer past 64 bits and a rational result, each bound and then compared
    lits = _VT[_vg(2.5), _vg(big(2)^80), _vg(big(7) // big(9))]
    for (code, lit, other) in (
        (LKV.A_DOUBLE, _vg(2.5), _vg(2.0)), (LKV.A_MPZ, _vg(big(2)^80), _vg(big(2)^81)),
        (LKV.A_MPQ, _vg(big(7) // big(9)), _vg(big(8) // big(9)))
    )
        k = if code == LKV.A_DOUBLE
            1
        elseif code == LKV.A_MPZ
            2
        else
            3
        end
        body = LKV.code[LKV.B_VAR1, LKV.A_ENTER, code, LKV.code(k), LKV.A_IS]
        rc, out = run(body, lits)
        @test ok(rc) && lk_eq(out[2], lit)
        rc, _ = run(body, lits, _VT[_vg(0), lit, _vg(0)])
        @test ok(rc)
        rc, _ = run(body, lits, _VT[_vg(0), other, _vg(0)])
        @test rc == LKV.PL_S_FALSE
    end
    # AR_END: the rounding mode is back after the binding and after the failure
    for arg in (_vv(), _vg(99))
        rc, _ = run(
            LKV.code[
                LKV.B_VAR1,
                LKV.A_ENTER,
                LKV.A_ROUNDTOWARDS_A,
                LKV.code(2),
                LKV.A_INTEGER,
                _vi(4),
                LKV.A_INTEGER,
                _vi(3),
                LKV.A_ADD,
                LKV.A_IS
            ],
            _VT[], _VT[_vg(0), arg, _vg(0)]
        )
        @test (ok(rc) || rc == LKV.PL_S_FALSE) && ld.arith_top == 1 &&
            LKV.fegetround() == LKV.FE_TONEAREST
    end
    # A_FIRSTVAR_IS: the result goes to the variable's slot (here the third argument's); A_VAR2 reads it back
    fv(expr) = LKV.code[
        LKV.A_ENTER,
        expr...,
        LKV.A_FIRSTVAR_IS,
        LKV.VAROFFSET(2),
        LKV.A_ENTER,
        LKV.A_VAR2
    ]
    rc, _ = run(fv(LKV.code[LKV.A_INTEGER, _vi(4), LKV.A_INTEGER, _vi(3), LKV.A_ADD]))
    @test ok(rc) && ld.arith_top == 1 && st[1].type === LKV.V_INTEGER && st[1].i == 7
    rc, _ = run(fv(LKV.code[LKV.A_DOUBLE, LKV.code(1)]), lits)
    @test ok(rc) && ld.arith_top == 1 && st[1].type === LKV.V_FLOAT && st[1].f == 2.5
    rc, _ = run(fv(LKV.code[LKV.A_MPZ, LKV.code(2)]), lits)
    @test ok(rc) && ld.arith_top == 1 && st[1].type === LKV.V_MPZ && st[1].mpz == big(2)^80
    rc, _ = run(fv(LKV.code[LKV.A_MPQ, LKV.code(3)]), lits)
    @test ok(rc) && ld.arith_top == 1 && st[1].type === LKV.V_MPQ &&
        st[1].mpq == big(7) // big(9)
    rc, _ = run(      # the mode is back (A_ROUNDTOWARDS_A's number stays below)
        LKV.code[
            LKV.A_ENTER,
            LKV.A_ROUNDTOWARDS_A,
            LKV.code(2),
            LKV.A_INTEGER,
            _vi(4),
            LKV.A_INTEGER,
            _vi(3),
            LKV.A_ADD,
            LKV.A_FIRSTVAR_IS,
            LKV.VAROFFSET(2)
        ]
    )
    @test ok(rc) && ld.arith_top == 1 && LKV.fegetround() == LKV.FE_TONEAREST
end
