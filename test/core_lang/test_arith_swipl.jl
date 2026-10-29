# ORIGINAL: V6c's gate — arithmetic (is/2, the comparisons) against swipl: SWI's own test_arith.pl units that need only what is ported, and a live differential.
# test/core_lang/test_arith_swipl.jl — arithmetic at run time (port_inventory row V6, V6c), against
# swipl:
#
#   * SWI's own tests (swipl-devel tests/core_lang/test_arith.pl) that need only what V6c ports — `is/2`
#     with `+ - *` and unary minus, the comparisons, overflow to big integers, the minint/maxint
#     promotions — one goal at a time through the query API; `format(atom(A), '~w', [N])` becomes a
#     value check;
#   * a LIVE DIFFERENTIAL: random expressions over `+ - *`, unary `-`/`+`, integers at the Int64 and
#     tagged boundaries, big integers, floats (`-0.0` among them), rationals, one-character strings
#     and `[Code]`, and planted errors (a variable, an atom, `[]`, an unknown function, `"ab"`, a
#     float overflow); every value and every error — its formal, its context's predicate (qualified
#     as swipl's, since V5c) and its message — identical; and random comparisons with all six
#     operators;
#   * what the kernel decides alone, pinned: the interim for a term type that cannot hold a big
#     result (until T1), `[Atom]` against swipl's answers (since R1), and the kernel-only terms
#     (Q-AR5).
#
# swipl present ⇒ the live comparisons run. Absent: an ERROR when LOGICKERNEL_REQUIRE_SWIPL=1,
# otherwise a LOUD note plus an assertion that it was not required — never a silent pass.
using Test, LogicKernel, Random

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _A = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
const LKA = LogicKernel
_as(x) = lk_sym(_A, Symbol(x))
_ag(x) = lk_gnd(_A, x)
_af(f, xs::_A...) = mk_expr(_A, _A[_as(f), xs...])
_akey = Ref(UInt64(100))
_av() = (_akey[] += 1; lk_var(_A, _akey[]))

const _AGD = LKA.PL_global_data{_A}()
const _ALD = LKA.PL_local_data{_A}(_AGD)

"Run the system predicate `name/n` on `args`: (rc, the first argument resolved, or the ball)."
function _arun(name, args::Vector{_A}; gd=_AGD, ld=_ALD)
    p = LKA.isCurrentProcedure(sym_key(_as(name)), length(args), LKA.MODULE_system(gd))
    fid = LKA.PL_open_foreign_frame(ld)
    a = LKA.PL_new_term_refs(ld, length(args))
    pvm = LogicKernel.PutVarMap()  # one PutVarMap: these puts share their variables as one record does (L1b boundary, user 2026-10-14)
    for (k, t) in enumerate(args)
        LogicKernel.putSlotValue!(ld, a + k, t, pvm)
    end
    qid = LKA.PL_open_query(
        gd, ld, nothing, LKA.PL_Q_CATCH_EXCEPTION | LKA.PL_Q_EXT_STATUS, p, a
    )
    rc = LKA.PL_next_solution(gd, ld, qid)
    out = if rc == LKA.PL_S_EXCEPTION
        lk_answer(ld, LKA.PL_exception(ld, qid))
    else
        lk_answer(ld, a)
    end
    LKA.PL_close_query(ld, qid)
    LKA.PL_close_foreign_frame(ld, fid)
    return rc, out
end

"Run procedure `p` on `args`: (rc, the goal resolved — its arguments as answered — or the ball)."
function _arun_proc(gd, ld, p, args::Vector{_A})
    fid = LKA.PL_open_foreign_frame(ld)
    a = LKA.PL_new_term_refs(ld, length(args))
    pvm = LogicKernel.PutVarMap()  # one PutVarMap: these puts share their variables as one record does (L1b boundary, user 2026-10-14)
    for (k, t) in enumerate(args)
        LogicKernel.putSlotValue!(ld, a + k, t, pvm)
    end
    qid = LKA.PL_open_query(
        gd, ld, nothing, LKA.PL_Q_CATCH_EXCEPTION | LKA.PL_Q_EXT_STATUS, p, a
    )
    rc = LKA.PL_next_solution(gd, ld, qid)
    out = if rc == LKA.PL_S_EXCEPTION
        lk_answer(ld, LKA.PL_exception(ld, qid))
    else                                                # the arguments read with ONE export
        mk_expr(_A, _A[_as(:goal); lk_answers(ld, (a:(a + length(args) - 1))...)])
    end
    LKA.PL_close_query(ld, qid)
    LKA.PL_close_foreign_frame(ld, fid)
    return rc, out
end

"`X is E`: the value (an interface term) or `nothing` when it failed; an error throws `ArgumentError`."
function _ais(e::_A)
    rc, out = _arun(:is, _A[_av(), e])
    rc == LKA.PL_S_EXCEPTION && throw(ArgumentError("error: " * _aenc(out)))
    return rc == LKA.PL_S_FALSE ? nothing : out
end
_acmp(op, a::_A, b::_A) = _arun(op, _A[a, b])[1] != LKA.PL_S_FALSE

# ── the structural encoding both sides print ─────────────────────────────────────────────────────
"A term as `_aenc` prints it: tags and codes, so no printer's quoting or float format is compared."
function _aenc(t)::String
    k = kind(t)
    k === VAR && return "_"
    if k === SYM
        is_nil(t) && return "nil"
        return "a" * string(Int.(codeunits(String(lk_name(t)))))
    elseif k === GND
        nk = number_kind(t)
        nk === NUM_INTEGER && return "i" * string(bigint_value(t))
        nk === NUM_RATIONAL &&
            (
                r=rational_value(t);
                return "q" * string(numerator(r)) * "r" * string(denominator(r))
            )
        nk === NUM_FLOAT &&
            return "F" * string(reinterpret(UInt64, float_value(t)); base=16)
        nk === NUM_STRING && return "s" * string(Int.(codeunits(string_value(t))))
        return "?"
    end
    h = child(t, 1)
    name = if kind(h) === SYM && !is_nil(h)
        "a" * string(Int.(codeunits(String(lk_name(h)))))
    else
        "nil"
    end
    return "c" * name * "/" * string(nchildren(t) - 1) * "(" *
           join((_aenc(child(t, i)) for i in 2:nchildren(t)), ",") * ")"
end

"An outcome as both sides print it: `ok:<value>` or `err:<formal>@<context predicate>@<message>`."
function _aoutcome(rc, out)::String
    if rc == LKA.PL_S_EXCEPTION
        formal, ctx = child(out, 2), child(out, 3)
        pi = kind(ctx) === EXPR ? child(ctx, 2) : mk_var(_A, UInt64(1))
        msg = kind(ctx) === EXPR ? child(ctx, 3) : mk_var(_A, UInt64(1))
        return "err:" * _aenc(formal) * "@" * _aenc(pi) * "@" * _aenc(msg)
    end
    rc == LKA.PL_S_FALSE && return "false"
    return "ok:" * _aenc(out)
end

# ── SWI's own tests (tests/core_lang/test_arith.pl), the ported subset ──────────────────────────
@testset "test_arith.pl: arith_basics, bigint, minint/maxint promotion (the ported subset)" begin
    M, X = typemin(Int64), typemax(Int64)
    @test lk_value(_ais(_af(:+, _ag(5), _ag(5)))) == 10                         # arith_1
    @test _acmp(Symbol("=:="), _ag(0), _af(:+, _ag(-5), _af(:*, _ag(2.5), _ag(2))))  # arith_2
    @test _acmp(Symbol("=:="), _ag(0), _af(:-, _af(:-, _ag(10), _ag(3.4)), _ag(6.6)))  # arith_4
    @test _acmp(:<, _ag(67), _ag(100.0e6))                                       # cmp_1
    @test lk_value(_ais(_af(:+, _ag(1), _ag(X)))) == big(X) + 1                 # add_promote1
    @test lk_value(_ais(_af(:+, _ag(M), _ag(-1)))) == big(M) - 1                # add_promote2
    a = _ais(_ag(M))                                                             # neg_1
    @test _acmp(Symbol("=:="), _af(:-, a), _ag(-big(M)))
    @test lk_value(_ais(_af(:-, _ag(0), _ag(M)))) == -big(M)                    # neg_promote
    @test lk_value(_ais(_af(:+, _ag(big(10)^21), _ag(1)))) == big(10)^21 + 1    # ar_add_ui
    @test lk_value(_ais(_af(:+, _af(:-, _ag(M), _ag(1)), _ag(1)))) == M          # mpz_to_int64
    minp = big(M) - 1                                                            # minint_promotion
    for e in (
        _af(:+, _ag(M), _ag(-1)), _af(:+, _ag(-1), _ag(M)), _af(:-, _ag(M), _ag(1)),
        _af(:-, _af(:*, _ag(M), _ag(2)), _ag(-(X))),
        _af(:-, _af(:*, _ag(2), _ag(M)), _ag(-(X))),
        _af(:-, _af(:*, _ag(-4294967296), _ag(4294967296)), _ag(-(X)))
    )
        @test lk_value(_ais(e)) == minp
    end
    maxp = big(X) + 1                                                            # maxint_promotion
    for e in (
        _af(:+, _ag(X), _ag(1)), _af(:+, _ag(1), _ag(X)), _af(:-, _ag(X), _ag(-1)),
        _af(:-, _af(:*, _ag(X), _ag(2)), _ag(X - 1)),
        _af(:-, _af(:*, _ag(2), _ag(X)), _ag(X - 1)),
        _af(:-, _af(:*, _ag(4294967295), _ag(4294967297)), _ag(X))
    )
        @test lk_value(_ais(e)) == maxp
    end
end

# ── the evaluation order and the error terms (research probe p7, p3), pinned ────────────────────
@testset "errors: last argument first, the formal, the context (is/2), the message" begin
    V = mk_var(_A, UInt64(1))
    at(e) = _aoutcome(_arun(:is, _A[_av(), e])...)
    isctx(f) = startswith(at(f), "err:")
    @test startswith(at(_af(:+, _as(:a), _av())), "err:instantiation_error") ||
        startswith(at(_af(:+, _as(:a), _av())), "err:a")                        # X is a+_
    @test occursin(_aenc(_af(:type_error, _as(:evaluable), _af(:/, _as(:a), _ag(0)))),
        at(_af(:+, _av(), _as(:a))))                                             # X is _+a
    @test occursin(_aenc(_af(:type_error, _as(:evaluable), _af(:/, _as(:bar), _ag(0)))),
        at(_af(:+, _as(:foo), _as(:bar))))                                       # foo+bar → bar/0
    @test occursin(_aenc(_af(:type_error, _as(:evaluable), mk_nil(_A))), at(mk_nil(_A)))
    @test occursin(_aenc(_af(:type_error, _as(:evaluable), _af(:/, _as(:f), _ag(3)))),
        at(_af(:f, _ag(1), _ag(2), _ag(3))))                                     # f/3 after its args
    # the context: the built-in, `system:(is)/2` (since V5c, Q-A), and a message only where upstream
    # gives one
    out = at(_af(:+, _ag("ab"), _ag(1)))
    @test occursin(
        "@" * _aenc(_af(:(:), _as(:system), _af(:/, _as(:is), _ag(2)))) * "@", out
    )
    @test endswith(out, "@" * _aenc(_as("\"x\" must hold one character")))
    # f3b-4 gap rows — swipl 10.1.18 at the pin (probed 2026-10-22): `X is [a,b]+0` raises
    # type_error(character, [a,b]) with the same message (pl-arith.c `len_not_one:`), and
    # `X is foo()+0` type_error(evaluable, foo()) (the `arity0:` branch)
    ab = _af("[|]", _as(:a), _af("[|]", _as(:b), mk_nil(_A)))
    out = at(_af(:+, ab, _ag(0)))
    @test occursin(_aenc(_af(:type_error, _as(:character), ab)), out)
    @test endswith(out, "@" * _aenc(_as("\"x\" must hold one character")))
    foo0 = mk_expr(_A, _A[_as(:foo)])
    @test occursin(
        _aenc(_af(:type_error, _as(:evaluable), foo0)), at(_af(:+, foo0, _ag(0)))
    )
    @test endswith(at(_af(:+, _as(:a), _ag(1))), "@_")
    @test isctx(_af(:*, _ag(1.0e308), _ag(10)))                                 # float_overflow
end

# swipl raises `type_error(expression, T)` with the message 'cyclic term' (research probe p8). The
# kernel detects the cycle as upstream does and raises with the REAL culprit, as upstream: since V5d
# a ball keeps its cycles (src/pl-fli.jl `copy_exception!`; user, 2026-10-07), which ends Q-AR8's
# placeholder. The ball is read on its cells, where its cycle lives (f3-3: until then under the
# keyed bindings): compared with `compareStandard_cells`, never exported.
@testset "cyclic: T = T+1, X is T — type_error(expression, T), the real culprit (Q-AR8, since V5d)" begin
    ld = LKA.PL_local_data{_A}(_AGD)
    T1 = _av()
    p = LKA.isCurrentProcedure(sym_key(_as(:is)), 2, LKA.MODULE_system(_AGD))
    fid = LKA.PL_open_foreign_frame(ld)
    a = LKA.PL_new_term_refs(ld, 3)
    pvm = LogicKernel.PutVarMap()  # one PutVarMap: these puts share their variables as one record does (L1b boundary, user 2026-10-14)
    LogicKernel.putSlotValue!(ld, a + 1, _av(), pvm)
    LogicKernel.putSlotValue!(ld, a + 2, T1, pvm)
    LogicKernel.putSlotValue!(ld, a + 3, _af(:+, T1, _ag(1)), pvm)
    @test LKA.do_unify_cells(ld, -(a + 2), -(a + 3)) == LKA.BOOLEX_TRUE        # T = T+1, on the cells
    qid = LKA.PL_open_query(
        _AGD, ld, nothing, LKA.PL_Q_CATCH_EXCEPTION | LKA.PL_Q_EXT_STATUS, p, a
    )
    @test LKA.PL_next_solution(_AGD, ld, qid) == LKA.PL_S_EXCEPTION
    ex = LKA.PL_exception(ld, qid)
    r = LKA.PL_new_term_refs(ld, 4)             # the formal, the context, the culprit, the formal's first
    @test LKA.PL_is_functor(ld, ex, _as(:error), 2)
    @test LKA._PL_get_arg(ld, 1, ex, r) && LKA._PL_get_arg(ld, 2, ex, r + 1)
    @test LKA.PL_is_functor(ld, r, _as(:type_error), 2)
    @test LKA._PL_get_arg(ld, 1, r, r + 3) && LKA._PL_get_arg(ld, 2, r, r + 2)
    @test lk_name(lk_answer(ld, r + 3)) === :expression
    @test LKA.compareStandard_cells(ld, -(r + 3), -(a + 2), true) == LKA.CMP_EQUAL   # the culprit: T
    @test lk_eq(lk_answer(ld, r + 1),
        _af(
            :context, _af(:(:), _as(:system), _af(:/, _as(:is), _ag(2))), _as("cyclic term")
        ))
    LKA.PL_reset_term_refs(ld, r)               # no reference into the ball when the query closes
    LKA.PL_close_query(ld, qid)
    LKA.PL_close_foreign_frame(ld, fid)
    @test ld.query == 0
end

# ── a bound left side, and the rounding to double — pinned to swipl 10.1.16 (probed) ───────────
@testset "is/2 with a bound left side; a big integer rounded to the NEAREST double" begin
    is_(a, e) = _arun(:is, _A[a, e])[1] != LKA.PL_S_FALSE
    @test !is_(_ag(1), _ag(1.0)) && !is_(_ag(1.0), _ag(1))                       # 1 is 1.0: false
    @test !is_(_ag(-0.0), _ag(0.0)) && !is_(_ag(0.0), _ag(-0.0))                 # the bit pattern
    @test !is_(_as(:a), _ag(1))                                                   # no error
    @test is_(_ag(2), _af(:+, _ag(1), _ag(1)))
    @test is_(_ag(big(2)^70), _af(:*, _ag(big(2)^70), _ag(1)))
    @test is_(_ag(1 // big(3)), _af(:*, _ag(1 // big(3)), _ag(1)))
    x = big(2)^64 + 2049                     # between two doubles, nearer the upper: 2^64 + 4096
    @test _acmp(Symbol("=:="), _ag(x), _ag(18446744073709555712.0))
    @test !_acmp(Symbol("=:="), _ag(x), _ag(18446744073709551616.0))           # not truncated
    @test _acmp(:>, _ag(x), _ag(18446744073709551616.0))
    @test _acmp(Symbol("=:="), _ag(x // 1), _ag(18446744073709555712.0))       # canonical: an integer
    q = _ais(_af(:*, _ag(x // 3), _ag(1.0)))                                     # mpq_to_double
    @test reinterpret(UInt64, lk_value(q)) ==
        reinterpret(UInt64, parse(Float64, "6148914691236518000.0"))
    # the comparison evaluates its LEFT side first (research probe p7)
    l = _aoutcome(_arun(:<, _A[_av(), _as(:a)])...)
    r = _aoutcome(_arun(:<, _A[_as(:a), _av()])...)
    @test startswith(l, "err:" * _aenc(_as(:instantiation_error)))
    @test occursin(_aenc(_af(:/, _as(:a), _ag(0))), r)
end

# ── integer size and shifts too far (V8) — pinned to swipl 10.1.16 (probed) ──────────────────────
# `1 << 20000` passes int_bits_ok's second bound: over 10000 bits, under the stacks limit. A shift
# amount beyond `long` is shift_to_far: 0 for a right shift, or for a left one by a negative amount,
# even of a negative number. A left one is int_too_big: resource_error(stack), swipl's and, since L1f
# f2, the kernel's. `1 << (1 << 40)` fails int_bits_ok.
# A right shift of a big integer floors (mpz_fdiv_q_2exp).
@testset "integer size, shifts too far, the floor of a right shift (V8)" begin
    v(e) = lk_value(_ais(e))
    @test v(_af(:<<, _ag(1), _ag(20000))) == big(2)^20000
    @test v(_af(:>>, _ag(-1), _ag(big(2)^70))) == 0
    @test v(_af(:>>, _ag(5), _ag(big(2)^70))) == 0
    @test v(_af(:<<, _ag(-5), _ag(-big(2)^70))) == 0
    @test v(_af(:<<, _ag(0), _ag(big(2)^70))) == 0
    # a left shift by LONG_MIN is a right shift by the unsigned 2^63 (swipl 10.1.18: 0, and -1 for a negative base)
    @test v(_af(:<<, _ag(1), _ag(typemin(Int64)))) == 0
    @test v(_af(:<<, _ag(-1), _ag(typemin(Int64)))) == -1
    @test v(_af(:<<, _ag(big(2)^63), _ag(typemin(Int64)))) == 0
    @test v(_af(:<<, _ag(-big(2)^63 - 1), _ag(typemin(Int64)))) == -1
    @test v(_af(:>>, _ag(0), _ag(typemin(Int64)))) == 0
    # L1f f2: int_too_big raises the global overflow, as swipl (probed 2026-10-19: resource_error(stack))
    rerr = _aenc(_af(:resource_error, _as(:stack)))
    for e in (_af(:<<, _ag(1), _ag(big(2)^70)), _af(:<<, _ag(1), _ag(1 << 40)))
        msg = try
            _ais(e)
            "no error"
        catch x
            x isa ArgumentError ? x.msg : "THROW: " * sprint(showerror, x)
        end
        @test occursin(rerr, msg)
    end
    @test _ALD.query == 0                                       # the query is closed
    @test v(_af(:>>, _ag(-big(2)^70), _ag(100))) == -1
    @test v(_af(:>>, _ag(1 - big(2)^70), _ag(7))) == typemin(Int64)
end

# ── A_ADD_FC (V8): `M is N-1` compiled inline, its fast and slow paths — pinned to swipl 10.1.16 ──
# The research probe's (scratchpad v6a/p5_addfc.pl): `p(N, R) :- M is N-1, id(M, R).` The slow path
# evaluates `N` (`evalExpression`) and adds (`ar_add_si`); its error names the CLAUSE's predicate,
# `p/2`, where the call of is/2 names `is/2`.
@testset "A_ADD_FC: the fast path, the slow path's values, and its error's context (V8)" begin
    gd = LKA.PL_global_data{_A}()
    ld = LKA.PL_local_data{_A}(gd)
    user = LKA.MODULE_user(gd)
    N, M, R, X = _av(), _av(), _av(), _av()
    for (h, b) in
        ((_af(:p, N, R), _af(",", _af(:is, M, _af(:-, N, _ag(1))), _af(:id, M, R))),
        (_af(:id, X, X), nothing))
        pr = LKA.lookupProcedure(child(h, 1), nchildren(h) - 1, user)
        cl = LKA.compileClause(gd, ld, h, b, pr, user)
        b === nothing || @test LKA.A_ADD_FC in cl.codes
        LKA.assertDefinition!(gd, pr.definition, cl, LKA.CL_END)
    end
    pp = LKA.lookupProcedure(_as(:p), 2, user)
    run(n) = (r=_arun_proc(gd, ld, pp, _A[n, _av()]); r)
    for (n, want) in (
        (5, 4), (-big(2)^56, -big(2)^56 - 1), (big(2)^56, big(2)^56 - 1),       # fast; slow
        (typemin(Int64), big(typemin(Int64)) - 1), (1 // big(3), -2 // big(3)), (1.5, 0.5),
        ("a", 96)
    )
        rc, out = run(_ag(n))
        @test rc != LKA.PL_S_FALSE && rc != LKA.PL_S_EXCEPTION
        @test lk_value(child(out, 3)) == want
    end
    rc, out = run(_as(:a))
    @test rc == LKA.PL_S_EXCEPTION
    o = _aoutcome(rc, out)
    @test occursin(_aenc(_af(:type_error, _as(:evaluable), _af(:/, _as(:a), _ag(0)))), o)
    @test occursin("@" * _aenc(_af(:/, _as(:p), _ag(2))) * "@", o)               # context(p/2, _)
end

# ── what the kernel decides alone ────────────────────────────────────────────────────────────────
@testset "the interim (Q-AR1), [Atom] (Q-AR7, since R1) and the kernel-only terms (Q-AR5), pinned" begin
    # Q-AR1: DefaultTerm holds no BigInt: a big result raises, loudly — never a wrong value
    D = DefaultTerm
    dgd = LKA.PL_global_data{D}()
    dld = LKA.PL_local_data{D}(dgd)
    p = LKA.isCurrentProcedure(sym_key(mk_sym(D, :is)), 2, LKA.MODULE_system(dgd))
    fid = LKA.PL_open_foreign_frame(dld)
    a = LKA.PL_new_term_refs(dld, 2)
    LogicKernel.putSlotValue!(dld, a + 1, mk_var(D, UInt64(1)))
    LogicKernel.putSlotValue!(
        dld, a + 2, mk_expr(D, D[mk_sym(D, :+), mk_gnd(D, typemax(Int64)), mk_gnd(D, 1)])
    )
    qid = LKA.PL_open_query(dgd, dld, nothing, LKA.PL_Q_CATCH_EXCEPTION, p, a)
    @test_throws ArgumentError LKA.PL_next_solution(dgd, dld, qid)
    @test dld.query == 0                                       # the query is closed (decision 1)
    LKA.PL_close_foreign_frame(dld, fid)
    # Q-AR7: [Atom], through the atom's text (`sym_text`, since R1): swipl 10.1.16's answers (probed
    # 2026-10-07) — a one-code-point atom is its code; `ab`, '[]', `[]`, '' and a string are not
    # characters
    one(x) = _af("[|]", x, mk_nil(_A))
    @test lk_value(_ais(one(_as(:a)))) == 97
    @test lk_value(_ais(one(_as("é")))) == 233
    @test lk_value(_ais(one(_as("\U0001D11E")))) == 119070
    @test lk_value(_ais(one(_ag(97)))) == 97                                       # [Code]
    for x in (_as(:ab), _as("[]"), mk_nil(_A), _as(""), _ag("a"))
        o = _aoutcome(_arun(:is, _A[_av(), one(x)])...)
        @test startswith(o, "err:" * _aenc(_af(:type_error, _as(:character), x)) * "@")
    end
    # Q-AR5: a value of no SWI type is not evaluable; `$expr/n` is evaluated, then not evaluable
    O = lk_term_type(Union{Int64, Bool})
    ogd = LKA.PL_global_data{O}()
    old = LKA.PL_local_data{O}(ogd)
    po = LKA.isCurrentProcedure(sym_key(lk_sym(O, :is)), 2, LKA.MODULE_system(ogd))
    fid = LKA.PL_open_foreign_frame(old)
    a = LKA.PL_new_term_refs(old, 2)
    pvm = LogicKernel.PutVarMap()  # one PutVarMap: these puts share their variables as one record does (L1b boundary, user 2026-10-14)
    LogicKernel.putSlotValue!(old, a + 1, mk_var(O, UInt64(1)), pvm)
    LogicKernel.putSlotValue!(old, a + 2, lk_gnd(O, true), pvm)
    qid = LKA.PL_open_query(
        ogd, old, nothing, LKA.PL_Q_CATCH_EXCEPTION | LKA.PL_Q_EXT_STATUS, po, a
    )
    @test LKA.PL_next_solution(ogd, old, qid) == LKA.PL_S_EXCEPTION
    ball = lk_answer(old, LKA.PL_exception(old, qid))
    @test lk_name(child(child(ball, 2), 2)) == :evaluable
    LKA.PL_close_query(old, qid)
    LKA.PL_close_foreign_frame(old, fid)
    ex = mk_expr(_A, _A[_av(), _as(:a)])                                         # (V a)
    rc, out = _arun(:is, _A[_av(), ex])
    @test rc == LKA.PL_S_EXCEPTION                             # `a` first: type_error(evaluable, a/0)
    @test occursin(_aenc(_af(:/, _as(:a), _ag(0))), _aoutcome(rc, out))
    rc, out = _arun(:is, _A[_av(), mk_expr(_A, _A[_av(), _ag(1)])])             # (V 1)
    @test occursin(_aenc(_af(:/, _as("\$expr"), _ag(1))), _aoutcome(rc, out))
end

# ── arith-a: the functions of pl-arith.c's table added by arith_funcs_design.md §2 (division, sign
# and order, integer, bitwise, rounding and conversion), pinned to swipl's own answers ───────────────
# `_A_ARITHA_CASES` are expression trees — a tuple is a compound, a Symbol an atom, `nothing` a fresh
# variable, anything else a grounded value; `_A_ARITHA_EXPECT` are swipl's outcomes for them, in the
# `_aoutcome` format, pasted from the oracle (the pin's build, 10.1.18): `X is E` through
# `_A_DRIVER`'s `is_/1`, floats as the bit patterns of their written text. The live testset at the end
# of this file runs the same cases through swipl again, so a pasted value cannot drift from the oracle.
# Known surprises, pinned like the rest: `-9223372036854775808 / -1` is 9223372036854775808 where C's
# `%` is undefined (see ar_divide); `integer(2^63 as a float)` is 9223372036854775807 (lround's
# overflow, patched to PLMAXINT); `max(1r3, 0.25)` is 1r3, not promoted (cmpNumbers compares a float
# against a rational without converting the other); `cot`, `acot`, `log/2` and `max_tagged_integer`
# are no functions at the pin.
# DBL_MAX as a big integer, and half its unit in the last place (the rounding midpoint above it)
const _A_DBLMAX = (big(2)^53 - 1) * big(2)^971
const _A_HALFULP = big(2)^970
const _A_ARITHA_CASES = Any[
    # division: / — an integer when it divides, else a float (iso and prefer_rationals false)
    (:/, 7, 2), (:/, 6, 3), (:/, -7, 2), (:/, 0, 5), (:/, 1, 0), (:/, 0, 0), (:/, 1.0, 0),
    (:/, 0.0, 0.0), (:/, 1, 3.0), (:/, 6, 3.0), (:/, big(10)^30, big(10)^10),
    (:/, big(10)^30, 7), (:/, 1 // big(3), 2), (:/, 1 // big(3), 0), (:/, 1 // big(3), 0.5),
    (:/, typemin(Int64), -1), (:/, typemin(Int64), 2), (:/, 1.0e308, 1.0e-10),
    (:/, 1, 1.0e308), (:/, 5, Inf), (:/, 5.0, Inf), (:/, -5.0, Inf), (:/, 5.0, -Inf),
    (:/, Inf, Inf), (:/, 1.0, -0.0), (:/, -1.0, 0.0), (:/, big(10)^30, 0), (:/, nothing, 1),
    # //  truncates toward zero
    (:(//), 7, 2), (:(//), -7, 2), (:(//), 7, -2), (:(//), -7, -2), (:(//), 0, 5),
    (:(//), typemin(Int64), -1), (:(//), big(10)^30, 7), (:(//), -big(10)^30, 7),
    (:(//), 1, 0), (:(//), big(10)^30, 0), (:(//), 5, big(2)^70), (:(//), 7.0, 2),
    (:(//), 7, 2.0), (:(//), 1 // big(3), 2),
    # div  floors
    (:div, 7, 2), (:div, -7, 2), (:div, 7, -2), (:div, -7, -2), (:div, 0, 5), (:div, 6, -3),
    (:div, typemin(Int64), -1), (:div, typemin(Int64), 3), (:div, big(10)^30, 7),
    (:div, -big(10)^30, 7), (:div, 1, 0), (:div, 1.5, 2), (:div, 2, 1 // big(3)),
    # mod: the sign of the divisor; rem: the sign of the dividend
    (:mod, 7, 3), (:mod, -7, 3), (:mod, 7, -3), (:mod, -7, -3), (:mod, 0, 5),
    (:mod, typemin(Int64), -1), (:mod, big(10)^30, 7), (:mod, -big(10)^30, 7),
    (:mod, big(10)^30, -7), (:mod, 7, 0), (:mod, big(10)^30, 0), (:mod, 7.0, 3),
    (:mod, 7, 1.5),
    (:mod, nothing, 3), (:mod, 3, nothing),
    (:rem, 7, 3), (:rem, -7, 3), (:rem, 7, -3), (:rem, -7, -3), (:rem, 0, 5),
    (:rem, typemin(Int64), -1), (:rem, big(10)^30, 7), (:rem, -big(10)^30, 7),
    (:rem, big(10)^30, -7), (:rem, 7, 0), (:rem, big(10)^30, 0), (:rem, 7.0, 3),
    (:rem, 7, 1.5),
    # abs, sign
    (:abs, 5), (:abs, -5), (:abs, 0), (:abs, typemin(Int64)), (:abs, -big(10)^30),
    (:abs, big(10)^30), (:abs, -2.5), (:abs, -0.0), (:abs, 0.0), (:abs, -1 // big(3)),
    (:abs, 1 // big(3)), (:abs, NaN),
    (:sign, -5), (:sign, 0), (:sign, 7), (:sign, typemin(Int64)), (:sign, -big(10)^30),
    (:sign, big(10)^30), (:sign, -2.5), (:sign, 0.0), (:sign, -0.0), (:sign, 3.0),
    (:sign, -1 // big(3)), (:sign, 1 // big(3)), (:sign, NaN),
    # min, max: -0.0 < 0.0, a NaN is the result, equal values of mixed type
    (:min, 1, 2), (:min, 2, 1), (:min, 1, 1.0), (:min, 1.0, 1), (:max, 1, 2), (:max, 2, 1),
    (:max, 1, 1.0), (:max, 1.0, 1), (:max, 0.0, -0.0), (:max, -0.0, 0.0), (:min, 0.0, -0.0),
    (:min, -0.0, 0.0), (:max, 1, big(2)^70), (:min, 1, big(2)^70), (:max, -big(2)^70, 1),
    (:max, 1 // big(3), 0.25), (:min, 1 // big(3), 0.5), (:max, 1 // big(2), 0.5),
    (:min, 1 // big(2), 0.5), (:max, 1 // big(2), 1 // big(3)), (:min, 2, 1 // big(3)),
    (:max, 3, 1 // big(3)), (:max, NaN, 1), (:max, 1, NaN), (:min, 1, NaN),
    (:min, NaN, NaN),
    (:max, 1, :a), (:min, nothing, 1), (:max, 3, 3), (:min, 3, 3),
    # copysign
    (:copysign, 1.5, -0.0), (:copysign, -1.5, 2), (:copysign, 3, -1.0), (:copysign, 3, 1.0),
    (:copysign, -3, 1), (:copysign, 3, -1), (:copysign, 1 // big(3), -1),
    (:copysign, -1 // big(3), 1), (:copysign, big(10)^30, -1), (:copysign, NaN, -1.0),
    (:copysign, 0.0, -1.0), (:copysign, 2, -0.0), (:copysign, -2, 0.0),
    (:copysign, 1.5, NaN),
    (:copysign, typemin(Int64), 1),
    # gcd, msb
    (:gcd, 12, 18), (:gcd, -12, 18), (:gcd, 12, -18), (:gcd, 0, 5), (:gcd, 5, 0),
    (:gcd, 0, 0),
    (:gcd, typemin(Int64), 6), (:gcd, typemin(Int64), typemin(Int64)),
    (:gcd, big(10)^30, big(10)^20), (:gcd, -big(10)^30, 7), (:gcd, 1.5, 2), (:gcd, 2, 1.5),
    (:gcd, 7, 1 // big(2)), (:gcd, nothing, 2),
    (:msb, 1), (:msb, 2), (:msb, 255), (:msb, 2^62), (:msb, typemax(Int64)),
    (:msb, big(2)^100),
    (:msb, big(2)^100 - 1), (:msb, 0), (:msb, -1), (:msb, -big(2)^70), (:msb, 1.5),
    (:msb, 4.0),
    (:msb, nothing),
    # the bitwise functions
    (Symbol("/\\"), 12, 10), (Symbol("\\/"), 12, 10), (:xor, 12, 10),
    (Symbol("/\\"), -1, 5), (Symbol("\\/"), -1, 5), (:xor, -1, 5),
    (Symbol("/\\"), typemin(Int64), 1), (Symbol("\\/"), typemin(Int64), 1),
    (:xor, typemin(Int64), -1), (Symbol("/\\"), big(2)^70, big(2)^70 - 1),
    (Symbol("\\/"), big(2)^70, big(2)^70 - 1), (:xor, big(2)^70, big(2)^70 - 1),
    (Symbol("/\\"), 5, big(2)^70), (Symbol("\\/"), 5, big(2)^70), (:xor, 5, big(2)^70),
    (Symbol("/\\"), -big(2)^70, 255), (Symbol("\\/"), -big(2)^70, 255),
    (:xor, -big(2)^70, -big(2)^69), (Symbol("/\\"), 5, 1.5), (Symbol("\\/"), 1.5, 5),
    (:xor, 5, 1 // big(3)), (:xor, nothing, 1), (Symbol("/\\"), 7.0, 3),
    (Symbol("\\"), 5), (Symbol("\\"), -1), (Symbol("\\"), 0),
    (Symbol("\\"), typemax(Int64)),
    (Symbol("\\"), big(2)^70), (Symbol("\\"), -big(2)^70), (Symbol("\\"), 1.5),
    (Symbol("\\"), 4.0), (Symbol("\\"), nothing),
    # integer and round: halves away from zero; the float range edge; rationals
    (:integer, 2.5), (:integer, -2.5), (:integer, 0.5), (:integer, -0.5), (:integer, 3),
    (:integer, 1 // big(2)), (:integer, -1 // big(2)), (:integer, 7 // big(2)),
    (:integer, 5 // big(2)), (:integer, -5 // big(2)), (:integer, 1 // big(3)),
    (:integer, -1 // big(3)), (:integer, 9.223372036854775808e18),
    (:integer, -9.223372036854775808e18), (:integer, 9.223372036854774784e18),
    (:integer, 1.0e19), (:integer, -1.0e19), (:integer, 1.0e300), (:integer, big(10)^30),
    (:integer, 0.49999999999999994), (:integer, -0.0), (:integer, 1.0e-300),
    (:integer, NaN),
    (:integer, nothing),
    (:round, 2.5), (:round, -2.5), (:round, 1.5), (:round, 0.5), (:round, 3),
    (:round, 7 // big(2)),
    (:round, -7 // big(2)), (:round, 9.223372036854775808e18), (:round, 1.0e19),
    (:round, big(10)^30), (:round, 2.4999999999999996),
    # truncate, floor, ceiling, ceil
    (:truncate, 2.7), (:truncate, -2.7), (:truncate, 0.5), (:truncate, -0.5),
    (:truncate, 3),
    (:truncate, 7 // big(2)), (:truncate, -7 // big(2)), (:truncate, 1 // big(3)),
    (:truncate, -1 // big(3)), (:truncate, 1.0e19), (:truncate, -1.0e19),
    (:truncate, big(10)^30),
    (:truncate, NaN), (:truncate, 9.223372036854775808e18),
    (:truncate, -9.223372036854775808e18),
    (:floor, 2.7), (:floor, -2.7), (:floor, 2.0), (:floor, -0.0), (:floor, 0.5),
    (:floor, -0.5),
    (:floor, 5), (:floor, 7 // big(2)), (:floor, -7 // big(2)), (:floor, 1 // big(3)),
    (:floor, -1 // big(3)), (:floor, 1.0e19), (:floor, -1.0e19), (:floor, big(10)^30),
    (:floor, 9.223372036854775808e18), (:floor, -9.223372036854775808e18), (:floor, NaN),
    (:ceiling, 2.1), (:ceiling, -2.1), (:ceiling, 2.0), (:ceiling, -0.5), (:ceiling, 0.5),
    (:ceiling, 5), (:ceiling, 7 // big(2)), (:ceiling, -7 // big(2)),
    (:ceiling, 1 // big(3)),
    (:ceiling, -1 // big(3)), (:ceiling, 1.0e19), (:ceiling, -1.0e19),
    (:ceiling, big(10)^30),
    (:ceiling, 9.223372036854775808e18), (:ceiling, NaN), (:ceiling, nothing),
    (:ceil, 2.1), (:ceil, -2.1), (:ceil, 7 // big(2)), (:ceil, -7 // big(2)), (:ceil, 5),
    (:ceil, 1.0e19),
    # float, float_integer_part, float_fractional_part
    (:float, 3), (:float, -3), (:float, big(10)^30), (:float, 1 // big(3)), (:float, 1.5),
    (:float, -0.0), (:float, big(10)^400), (:float, -big(10)^400), (:float, typemin(Int64)),
    (:float, 2^53 + 1), (:float, nothing),
    (:float_integer_part, 2.7), (:float_integer_part, -2.7), (:float_integer_part, 5),
    (:float_integer_part, 7 // big(2)), (:float_integer_part, -7 // big(2)),
    (:float_integer_part, 0.5), (:float_integer_part, -0.5), (:float_integer_part, 1.0e300),
    (:float_integer_part, big(10)^30), (:float_integer_part, -0.0),
    (:float_fractional_part, 2.75), (:float_fractional_part, -2.75),
    (:float_fractional_part, 5),
    (:float_fractional_part, big(10)^30), (:float_fractional_part, 7 // big(2)),
    (:float_fractional_part, -7 // big(2)), (:float_fractional_part, -0.0),
    (:float_fractional_part, 3.0), (:float_fractional_part, -3.0),
    (:float_fractional_part, 1.0e300), (:float_fractional_part, 0.1),
    # nested, and what swipl's table does not have (see arith_funcs_design.md section 2)
    (:+, (:mod, 17, 5), (:*, (:div, -7, 2), (:abs, -3))),
    (:max, (:min, 3, 4), (:gcd, 12, 18)),
    (:cot, 1.0), (:acot, 1.0), (:log, 2, 8), :max_tagged_integer,
    (:ceiling, (:/, 7, 2)), (:truncate, (:/, -7, 2)), (:integer, (:/, 5, 2)),
    # every leaf kind: a one-character string and [Code]
    (:abs, "a"), (:mod, "a", 7),
    # the big integer → double boundary (audit D-0025): DBL_MAX exactly, one above it, the last below
    # the rounding midpoint, the midpoint itself (ties to even: overflows), their negatives, 2^1024, 2^1023 —
    # overflow decided by the kernel (src/pl-gmp.jl `_mpz_get_d`), not by the installed Julia's conversion
    (:float, _A_DBLMAX), (:float, _A_DBLMAX + 1), (:float, _A_DBLMAX + _A_HALFULP - 1),
    (:float, _A_DBLMAX + _A_HALFULP), (:float, -_A_DBLMAX),
    (:float, -(_A_DBLMAX + _A_HALFULP)),
    (:float, big(2)^1024), (:float, big(2)^1023),
    # one row per other conversion site (audit D-0026): `/` on big integers (mpz_fdiv), a rational to a
    # double (mpq_to_double), a float compared with a big integer (cmpFloatNumbers: under the 1.13.2 clamp
    # DBL_MAX and 10^400 compare equal and max/2 keeps the float)
    (:/, big(10)^400, 3), (:/, -big(10)^400, 3), (:/, big(10)^400, big(10)^399),
    (:float, big(10)^400 // 3),
    (:max, floatmax(Float64), big(10)^400), (:min, -floatmax(Float64), -big(10)^400),
    (:max, big(10)^400, floatmax(Float64))
]

"The kernel term of a case tree (see `_A_ARITHA_CASES`)."
function _atree(x)::_A
    x === nothing && return _av()
    x isa Symbol && return _as(x)
    x isa Tuple && return _af(x[1], _A[_atree(a) for a in x[2:end]]...)
    return _ag(x)
end

"The swipl source text of a case tree, in functional notation."
function _asrc(x)::String
    x === nothing && return "_"
    x isa Symbol && return String(x)
    x isa Tuple && return string(x[1], "(", join((_asrc(a) for a in x[2:end]), ","), ")")
    x isa Rational && return string(numerator(x), "r", denominator(x))
    x isa String && return "\"" * x * "\""
    if x isa AbstractFloat
        isnan(x) && return "1.5NaN"
        isinf(x) && return x > 0 ? "1.0Inf" : "-1.0Inf"
        return repr(x)
    end
    return string(x)
end

const _A_ARITHA_EXPECT = String[
    "ok:F400c000000000000",  # /(7,2)
    "ok:i2",  # /(6,3)
    "ok:Fc00c000000000000",  # /(-7,2)
    "ok:i0",  # /(0,5)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[122, 101, 114, 111, 95, 100, 105, 118, 105, 115, 111, 114])@ca[47]/2(a[47],i2)@_",  # /(1,0)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[122, 101, 114, 111, 95, 100, 105, 118, 105, 115, 111, 114])@ca[47]/2(a[47],i2)@_",  # /(0,0)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[122, 101, 114, 111, 95, 100, 105, 118, 105, 115, 111, 114])@ca[47]/2(a[47],i2)@_",  # /(1.0,0)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # /(0.0,0.0)
    "ok:F3fd5555555555555",  # /(1,3.0)
    "ok:F4000000000000000",  # /(6,3.0)
    "ok:i100000000000000000000",  # /(1000000000000000000000000000000,10000000000)
    "ok:F45fcd98a8b00a10b",  # /(1000000000000000000000000000000,7)
    "ok:q1r6",  # /(1r3,2)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[122, 101, 114, 111, 95, 100, 105, 118, 105, 115, 111, 114])@ca[47]/2(a[47],i2)@_",  # /(1r3,0)
    "ok:F3fe5555555555555",  # /(1r3,0.5)
    "ok:i9223372036854775808",  # /(-9223372036854775808,-1)
    "ok:i-4611686018427387904",  # /(-9223372036854775808,2)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # /(1.0e308,1.0e-10)
    "ok:F730d67819e8d2",  # /(1,1.0e308)
    "ok:i0",  # /(5,1.0Inf)
    "ok:F0",  # /(5.0,1.0Inf)
    "ok:F8000000000000000",  # /(-5.0,1.0Inf)
    "ok:F8000000000000000",  # /(5.0,-1.0Inf)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # /(1.0Inf,1.0Inf)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[122, 101, 114, 111, 95, 100, 105, 118, 105, 115, 111, 114])@ca[47]/2(a[47],i2)@_",  # /(1.0,-0.0)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[122, 101, 114, 111, 95, 100, 105, 118, 105, 115, 111, 114])@ca[47]/2(a[47],i2)@_",  # /(-1.0,0.0)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[122, 101, 114, 111, 95, 100, 105, 118, 105, 115, 111, 114])@ca[47]/2(a[47],i2)@_",  # /(1000000000000000000000000000000,0)
    "err:a[105, 110, 115, 116, 97, 110, 116, 105, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # /(_,1)
    "ok:i3",  # //(7,2)
    "ok:i-3",  # //(-7,2)
    "ok:i-3",  # //(7,-2)
    "ok:i3",  # //(-7,-2)
    "ok:i0",  # //(0,5)
    "ok:i9223372036854775808",  # //(-9223372036854775808,-1)
    "ok:i142857142857142857142857142857",  # //(1000000000000000000000000000000,7)
    "ok:i-142857142857142857142857142857",  # //(-1000000000000000000000000000000,7)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[122, 101, 114, 111, 95, 100, 105, 118, 105, 115, 111, 114])@ca[47]/2(a[47, 47],i2)@_",  # //(1,0)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[122, 101, 114, 111, 95, 100, 105, 118, 105, 115, 111, 114])@ca[47]/2(a[47, 47],i2)@_",  # //(1000000000000000000000000000000,0)
    "ok:i0",  # //(5,1180591620717411303424)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[105, 110, 116, 101, 103, 101, 114],F401c000000000000)@ca[47]/2(a[47, 47],i2)@_",  # //(7.0,2)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[105, 110, 116, 101, 103, 101, 114],F4000000000000000)@ca[47]/2(a[47, 47],i2)@_",  # //(7,2.0)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[105, 110, 116, 101, 103, 101, 114],q1r3)@ca[47]/2(a[47, 47],i2)@_",  # //(1r3,2)
    "ok:i3",  # div(7,2)
    "ok:i-4",  # div(-7,2)
    "ok:i-4",  # div(7,-2)
    "ok:i3",  # div(-7,-2)
    "ok:i0",  # div(0,5)
    "ok:i-2",  # div(6,-3)
    "ok:i9223372036854775808",  # div(-9223372036854775808,-1)
    "ok:i-3074457345618258603",  # div(-9223372036854775808,3)
    "ok:i142857142857142857142857142857",  # div(1000000000000000000000000000000,7)
    "ok:i-142857142857142857142857142858",  # div(-1000000000000000000000000000000,7)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[122, 101, 114, 111, 95, 100, 105, 118, 105, 115, 111, 114])@ca[47]/2(a[100, 105, 118],i2)@_",  # div(1,0)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[105, 110, 116, 101, 103, 101, 114],F3ff8000000000000)@ca[47]/2(a[100, 105, 118],i2)@_",  # div(1.5,2)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[105, 110, 116, 101, 103, 101, 114],q1r3)@ca[47]/2(a[100, 105, 118],i2)@_",  # div(2,1r3)
    "ok:i1",  # mod(7,3)
    "ok:i2",  # mod(-7,3)
    "ok:i-2",  # mod(7,-3)
    "ok:i-1",  # mod(-7,-3)
    "ok:i0",  # mod(0,5)
    "ok:i0",  # mod(-9223372036854775808,-1)
    "ok:i1",  # mod(1000000000000000000000000000000,7)
    "ok:i6",  # mod(-1000000000000000000000000000000,7)
    "ok:i-6",  # mod(1000000000000000000000000000000,-7)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[122, 101, 114, 111, 95, 100, 105, 118, 105, 115, 111, 114])@ca[47]/2(a[109, 111, 100],i2)@_",  # mod(7,0)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[122, 101, 114, 111, 95, 100, 105, 118, 105, 115, 111, 114])@ca[47]/2(a[109, 111, 100],i2)@_",  # mod(1000000000000000000000000000000,0)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[105, 110, 116, 101, 103, 101, 114],F401c000000000000)@ca[47]/2(a[109, 111, 100],i2)@_",  # mod(7.0,3)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[105, 110, 116, 101, 103, 101, 114],F3ff8000000000000)@ca[47]/2(a[109, 111, 100],i2)@_",  # mod(7,1.5)
    "err:a[105, 110, 115, 116, 97, 110, 116, 105, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # mod(_,3)
    "err:a[105, 110, 115, 116, 97, 110, 116, 105, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # mod(3,_)
    "ok:i1",  # rem(7,3)
    "ok:i-1",  # rem(-7,3)
    "ok:i1",  # rem(7,-3)
    "ok:i-1",  # rem(-7,-3)
    "ok:i0",  # rem(0,5)
    "ok:i0",  # rem(-9223372036854775808,-1)
    "ok:i1",  # rem(1000000000000000000000000000000,7)
    "ok:i-1",  # rem(-1000000000000000000000000000000,7)
    "ok:i1",  # rem(1000000000000000000000000000000,-7)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[122, 101, 114, 111, 95, 100, 105, 118, 105, 115, 111, 114])@ca[47]/2(a[114, 101, 109],i2)@_",  # rem(7,0)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[122, 101, 114, 111, 95, 100, 105, 118, 105, 115, 111, 114])@ca[47]/2(a[114, 101, 109],i2)@_",  # rem(1000000000000000000000000000000,0)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[105, 110, 116, 101, 103, 101, 114],F401c000000000000)@ca[47]/2(a[114, 101, 109],i2)@_",  # rem(7.0,3)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[105, 110, 116, 101, 103, 101, 114],F3ff8000000000000)@ca[47]/2(a[114, 101, 109],i2)@_",  # rem(7,1.5)
    "ok:i5",  # abs(5)
    "ok:i5",  # abs(-5)
    "ok:i0",  # abs(0)
    "ok:i9223372036854775808",  # abs(-9223372036854775808)
    "ok:i1000000000000000000000000000000",  # abs(-1000000000000000000000000000000)
    "ok:i1000000000000000000000000000000",  # abs(1000000000000000000000000000000)
    "ok:F4004000000000000",  # abs(-2.5)
    "ok:F0",  # abs(-0.0)
    "ok:F0",  # abs(0.0)
    "ok:q1r3",  # abs(-1r3)
    "ok:q1r3",  # abs(1r3)
    "ok:F7ff8000000000000",  # abs(1.5NaN)
    "ok:i-1",  # sign(-5)
    "ok:i0",  # sign(0)
    "ok:i1",  # sign(7)
    "ok:i-1",  # sign(-9223372036854775808)
    "ok:i-1",  # sign(-1000000000000000000000000000000)
    "ok:i1",  # sign(1000000000000000000000000000000)
    "ok:Fbff0000000000000",  # sign(-2.5)
    "ok:F0",  # sign(0.0)
    "ok:F0",  # sign(-0.0)
    "ok:F3ff0000000000000",  # sign(3.0)
    "ok:i-1",  # sign(-1r3)
    "ok:i1",  # sign(1r3)
    "ok:F7ff8000000000000",  # sign(1.5NaN)
    "ok:i1",  # min(1,2)
    "ok:i1",  # min(2,1)
    "ok:F3ff0000000000000",  # min(1,1.0)
    "ok:F3ff0000000000000",  # min(1.0,1)
    "ok:i2",  # max(1,2)
    "ok:i2",  # max(2,1)
    "ok:F3ff0000000000000",  # max(1,1.0)
    "ok:F3ff0000000000000",  # max(1.0,1)
    "ok:F0",  # max(0.0,-0.0)
    "ok:F0",  # max(-0.0,0.0)
    "ok:F8000000000000000",  # min(0.0,-0.0)
    "ok:F8000000000000000",  # min(-0.0,0.0)
    "ok:i1180591620717411303424",  # max(1,1180591620717411303424)
    "ok:i1",  # min(1,1180591620717411303424)
    "ok:i1",  # max(-1180591620717411303424,1)
    "ok:q1r3",  # max(1r3,0.25)
    "ok:q1r3",  # min(1r3,0.5)
    "ok:F3fe0000000000000",  # max(1r2,0.5)
    "ok:F3fe0000000000000",  # min(1r2,0.5)
    "ok:q1r2",  # max(1r2,1r3)
    "ok:q1r3",  # min(2,1r3)
    "ok:i3",  # max(3,1r3)
    "ok:F7ff8000000000000",  # max(1.5NaN,1)
    "ok:F7ff8000000000000",  # max(1,1.5NaN)
    "ok:F7ff8000000000000",  # min(1,1.5NaN)
    "ok:F7ff8000000000000",  # min(1.5NaN,1.5NaN)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[101, 118, 97, 108, 117, 97, 98, 108, 101],ca[47]/2(a[97],i0))@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # max(1,a)
    "err:a[105, 110, 115, 116, 97, 110, 116, 105, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # min(_,1)
    "ok:i3",  # max(3,3)
    "ok:i3",  # min(3,3)
    "ok:Fbff8000000000000",  # copysign(1.5,-0.0)
    "ok:F3ff8000000000000",  # copysign(-1.5,2)
    "ok:i-3",  # copysign(3,-1.0)
    "ok:i3",  # copysign(3,1.0)
    "ok:i3",  # copysign(-3,1)
    "ok:i-3",  # copysign(3,-1)
    "ok:q-1r3",  # copysign(1r3,-1)
    "ok:q1r3",  # copysign(-1r3,1)
    "ok:i-1000000000000000000000000000000",  # copysign(1000000000000000000000000000000,-1)
    "ok:F7ff8000000000000",  # copysign(1.5NaN,-1.0)
    "ok:F8000000000000000",  # copysign(0.0,-1.0)
    "ok:i-2",  # copysign(2,-0.0)
    "ok:i2",  # copysign(-2,0.0)
    "ok:F3ff8000000000000",  # copysign(1.5,1.5NaN)
    "ok:i9223372036854775808",  # copysign(-9223372036854775808,1)
    "ok:i6",  # gcd(12,18)
    "ok:i6",  # gcd(-12,18)
    "ok:i6",  # gcd(12,-18)
    "ok:i5",  # gcd(0,5)
    "ok:i5",  # gcd(5,0)
    "ok:i0",  # gcd(0,0)
    "ok:i2",  # gcd(-9223372036854775808,6)
    "ok:i9223372036854775808",  # gcd(-9223372036854775808,-9223372036854775808)
    "ok:i100000000000000000000",  # gcd(1000000000000000000000000000000,100000000000000000000)
    "ok:i1",  # gcd(-1000000000000000000000000000000,7)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[105, 110, 116, 101, 103, 101, 114],F3ff8000000000000)@ca[47]/2(a[103, 99, 100],i2)@_",  # gcd(1.5,2)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[105, 110, 116, 101, 103, 101, 114],F3ff8000000000000)@ca[47]/2(a[103, 99, 100],i2)@_",  # gcd(2,1.5)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[105, 110, 116, 101, 103, 101, 114],q1r2)@ca[47]/2(a[103, 99, 100],i2)@_",  # gcd(7,1r2)
    "err:a[105, 110, 115, 116, 97, 110, 116, 105, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # gcd(_,2)
    "ok:i0",  # msb(1)
    "ok:i1",  # msb(2)
    "ok:i7",  # msb(255)
    "ok:i62",  # msb(4611686018427387904)
    "ok:i62",  # msb(9223372036854775807)
    "ok:i100",  # msb(1267650600228229401496703205376)
    "ok:i99",  # msb(1267650600228229401496703205375)
    "err:ca[100, 111, 109, 97, 105, 110, 95, 101, 114, 114, 111, 114]/2(a[110, 111, 116, 95, 108, 101, 115, 115, 95, 116, 104, 97, 110, 95, 111, 110, 101],i0)@ca[47]/2(a[109, 115, 98],i1)@_",  # msb(0)
    "err:ca[100, 111, 109, 97, 105, 110, 95, 101, 114, 114, 111, 114]/2(a[110, 111, 116, 95, 108, 101, 115, 115, 95, 116, 104, 97, 110, 95, 111, 110, 101],i-1)@ca[47]/2(a[109, 115, 98],i1)@_",  # msb(-1)
    "err:ca[100, 111, 109, 97, 105, 110, 95, 101, 114, 114, 111, 114]/2(a[110, 111, 116, 95, 108, 101, 115, 115, 95, 116, 104, 97, 110, 95, 111, 110, 101],i-1180591620717411303424)@ca[47]/2(a[109, 115, 98],i1)@_",  # msb(-1180591620717411303424)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[105, 110, 116, 101, 103, 101, 114],F3ff8000000000000)@ca[47]/2(a[109, 115, 98],i1)@_",  # msb(1.5)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[105, 110, 116, 101, 103, 101, 114],F4010000000000000)@ca[47]/2(a[109, 115, 98],i1)@_",  # msb(4.0)
    "err:a[105, 110, 115, 116, 97, 110, 116, 105, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # msb(_)
    "ok:i8",  # /\(12,10)
    "ok:i14",  # \/(12,10)
    "ok:i6",  # xor(12,10)
    "ok:i5",  # /\(-1,5)
    "ok:i-1",  # \/(-1,5)
    "ok:i-6",  # xor(-1,5)
    "ok:i0",  # /\(-9223372036854775808,1)
    "ok:i-9223372036854775807",  # \/(-9223372036854775808,1)
    "ok:i9223372036854775807",  # xor(-9223372036854775808,-1)
    "ok:i0",  # /\(1180591620717411303424,1180591620717411303423)
    "ok:i2361183241434822606847",  # \/(1180591620717411303424,1180591620717411303423)
    "ok:i2361183241434822606847",  # xor(1180591620717411303424,1180591620717411303423)
    "ok:i0",  # /\(5,1180591620717411303424)
    "ok:i1180591620717411303429",  # \/(5,1180591620717411303424)
    "ok:i1180591620717411303429",  # xor(5,1180591620717411303424)
    "ok:i0",  # /\(-1180591620717411303424,255)
    "ok:i-1180591620717411303169",  # \/(-1180591620717411303424,255)
    "ok:i590295810358705651712",  # xor(-1180591620717411303424,-590295810358705651712)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[105, 110, 116, 101, 103, 101, 114],F3ff8000000000000)@ca[47]/2(a[47, 92],i2)@_",  # /\(5,1.5)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[105, 110, 116, 101, 103, 101, 114],F3ff8000000000000)@ca[47]/2(a[92, 47],i2)@_",  # \/(1.5,5)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[105, 110, 116, 101, 103, 101, 114],q1r3)@ca[47]/2(a[120, 111, 114],i2)@_",  # xor(5,1r3)
    "err:a[105, 110, 115, 116, 97, 110, 116, 105, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # xor(_,1)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[105, 110, 116, 101, 103, 101, 114],F401c000000000000)@ca[47]/2(a[47, 92],i2)@_",  # /\(7.0,3)
    "ok:i-6",  # \(5)
    "ok:i0",  # \(-1)
    "ok:i-1",  # \(0)
    "ok:i-9223372036854775808",  # \(9223372036854775807)
    "ok:i-1180591620717411303425",  # \(1180591620717411303424)
    "ok:i1180591620717411303423",  # \(-1180591620717411303424)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[105, 110, 116, 101, 103, 101, 114],F3ff8000000000000)@ca[47]/2(a[92],i1)@_",  # \(1.5)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[105, 110, 116, 101, 103, 101, 114],F4010000000000000)@ca[47]/2(a[92],i1)@_",  # \(4.0)
    "err:a[105, 110, 115, 116, 97, 110, 116, 105, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # \(_)
    "ok:i3",  # integer(2.5)
    "ok:i-3",  # integer(-2.5)
    "ok:i1",  # integer(0.5)
    "ok:i-1",  # integer(-0.5)
    "ok:i3",  # integer(3)
    "ok:i1",  # integer(1r2)
    "ok:i-1",  # integer(-1r2)
    "ok:i4",  # integer(7r2)
    "ok:i3",  # integer(5r2)
    "ok:i-3",  # integer(-5r2)
    "ok:i0",  # integer(1r3)
    "ok:i0",  # integer(-1r3)
    "ok:i9223372036854775807",  # integer(9.223372036854776e18)
    "ok:i-9223372036854775808",  # integer(-9.223372036854776e18)
    "ok:i9223372036854774784",  # integer(9.223372036854775e18)
    "ok:i10000000000000000000",  # integer(1.0e19)
    "ok:i-10000000000000000000",  # integer(-1.0e19)
    "ok:i1000000000000000052504760255204420248704468581108159154915854115511802457988908195786371375080447864043704443832883878176942523235360430575644792184786706982848387200926575803737830233794788090059368953234970799945081119038967640880074652742780142494579258788820056842838115669472196386865459400540160",  # integer(1.0e300)
    "ok:i1000000000000000000000000000000",  # integer(1000000000000000000000000000000)
    "ok:i0",  # integer(0.49999999999999994)
    "ok:i0",  # integer(-0.0)
    "ok:i0",  # integer(1.0e-300)
    "ok:F7ff8000000000000",  # integer(1.5NaN)
    "err:a[105, 110, 115, 116, 97, 110, 116, 105, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # integer(_)
    "ok:i3",  # round(2.5)
    "ok:i-3",  # round(-2.5)
    "ok:i2",  # round(1.5)
    "ok:i1",  # round(0.5)
    "ok:i3",  # round(3)
    "ok:i4",  # round(7r2)
    "ok:i-4",  # round(-7r2)
    "ok:i9223372036854775807",  # round(9.223372036854776e18)
    "ok:i10000000000000000000",  # round(1.0e19)
    "ok:i1000000000000000000000000000000",  # round(1000000000000000000000000000000)
    "ok:i2",  # round(2.4999999999999996)
    "ok:i2",  # truncate(2.7)
    "ok:i-2",  # truncate(-2.7)
    "ok:i0",  # truncate(0.5)
    "ok:i0",  # truncate(-0.5)
    "ok:i3",  # truncate(3)
    "ok:i3",  # truncate(7r2)
    "ok:i-3",  # truncate(-7r2)
    "ok:i0",  # truncate(1r3)
    "ok:i0",  # truncate(-1r3)
    "ok:i10000000000000000000",  # truncate(1.0e19)
    "ok:i-10000000000000000000",  # truncate(-1.0e19)
    "ok:i1000000000000000000000000000000",  # truncate(1000000000000000000000000000000)
    "ok:F7ff8000000000000",  # truncate(1.5NaN)
    "ok:i9223372036854775808",  # truncate(9.223372036854776e18)
    "ok:i-9223372036854775808",  # truncate(-9.223372036854776e18)
    "ok:i2",  # floor(2.7)
    "ok:i-3",  # floor(-2.7)
    "ok:i2",  # floor(2.0)
    "ok:i0",  # floor(-0.0)
    "ok:i0",  # floor(0.5)
    "ok:i-1",  # floor(-0.5)
    "ok:i5",  # floor(5)
    "ok:i3",  # floor(7r2)
    "ok:i-4",  # floor(-7r2)
    "ok:i0",  # floor(1r3)
    "ok:i-1",  # floor(-1r3)
    "ok:i10000000000000000000",  # floor(1.0e19)
    "ok:i-10000000000000000000",  # floor(-1.0e19)
    "ok:i1000000000000000000000000000000",  # floor(1000000000000000000000000000000)
    "ok:i9223372036854775808",  # floor(9.223372036854776e18)
    "ok:i-9223372036854775808",  # floor(-9.223372036854776e18)
    "ok:F7ff8000000000000",  # floor(1.5NaN)
    "ok:i3",  # ceiling(2.1)
    "ok:i-2",  # ceiling(-2.1)
    "ok:i2",  # ceiling(2.0)
    "ok:i0",  # ceiling(-0.5)
    "ok:i1",  # ceiling(0.5)
    "ok:i5",  # ceiling(5)
    "ok:i4",  # ceiling(7r2)
    "ok:i-3",  # ceiling(-7r2)
    "ok:i1",  # ceiling(1r3)
    "ok:i0",  # ceiling(-1r3)
    "ok:i10000000000000000000",  # ceiling(1.0e19)
    "ok:i-10000000000000000000",  # ceiling(-1.0e19)
    "ok:i1000000000000000000000000000000",  # ceiling(1000000000000000000000000000000)
    "ok:i9223372036854775808",  # ceiling(9.223372036854776e18)
    "ok:F7ff8000000000000",  # ceiling(1.5NaN)
    "err:a[105, 110, 115, 116, 97, 110, 116, 105, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # ceiling(_)
    "ok:i3",  # ceil(2.1)
    "ok:i-2",  # ceil(-2.1)
    "ok:i4",  # ceil(7r2)
    "ok:i-3",  # ceil(-7r2)
    "ok:i5",  # ceil(5)
    "ok:i10000000000000000000",  # ceil(1.0e19)
    "ok:F4008000000000000",  # float(3)
    "ok:Fc008000000000000",  # float(-3)
    "ok:F46293e5939a08cea",  # float(1000000000000000000000000000000)
    "ok:F3fd5555555555555",  # float(1r3)
    "ok:F3ff8000000000000",  # float(1.5)
    "ok:F8000000000000000",  # float(-0.0)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # float(10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # float(-10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000)
    "ok:Fc3e0000000000000",  # float(-9223372036854775808)
    "ok:F4340000000000000",  # float(9007199254740993)
    "err:a[105, 110, 115, 116, 97, 110, 116, 105, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # float(_)
    "ok:F4000000000000000",  # float_integer_part(2.7)
    "ok:Fc000000000000000",  # float_integer_part(-2.7)
    "ok:i5",  # float_integer_part(5)
    "ok:i3",  # float_integer_part(7r2)
    "ok:i-3",  # float_integer_part(-7r2)
    "ok:F0",  # float_integer_part(0.5)
    "ok:F8000000000000000",  # float_integer_part(-0.5)
    "ok:F7e37e43c8800759c",  # float_integer_part(1.0e300)
    "ok:i1000000000000000000000000000000",  # float_integer_part(1000000000000000000000000000000)
    "ok:F8000000000000000",  # float_integer_part(-0.0)
    "ok:F3fe8000000000000",  # float_fractional_part(2.75)
    "ok:Fbfe8000000000000",  # float_fractional_part(-2.75)
    "ok:i0",  # float_fractional_part(5)
    "ok:i0",  # float_fractional_part(1000000000000000000000000000000)
    "ok:q1r2",  # float_fractional_part(7r2)
    "ok:q-1r2",  # float_fractional_part(-7r2)
    "ok:F8000000000000000",  # float_fractional_part(-0.0)
    "ok:F0",  # float_fractional_part(3.0)
    "ok:F8000000000000000",  # float_fractional_part(-3.0)
    "ok:F0",  # float_fractional_part(1.0e300)
    "ok:F3fb999999999999a",  # float_fractional_part(0.1)
    "ok:i-10",  # +(mod(17,5),*(div(-7,2),abs(-3)))
    "ok:i6",  # max(min(3,4),gcd(12,18))
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[101, 118, 97, 108, 117, 97, 98, 108, 101],ca[47]/2(a[99, 111, 116],i1))@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # cot(1.0)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[101, 118, 97, 108, 117, 97, 98, 108, 101],ca[47]/2(a[97, 99, 111, 116],i1))@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # acot(1.0)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[101, 118, 97, 108, 117, 97, 98, 108, 101],ca[47]/2(a[108, 111, 103],i2))@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # log(2,8)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[101, 118, 97, 108, 117, 97, 98, 108, 101],ca[47]/2(a[109, 97, 120, 95, 116, 97, 103, 103, 101, 100, 95, 105, 110, 116, 101, 103, 101, 114],i0))@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # max_tagged_integer
    "ok:i4",  # ceiling(/(7,2))
    "ok:i-3",  # truncate(/(-7,2))
    "ok:i3",  # integer(/(5,2))
    "ok:i97",  # abs("a")
    "ok:i6",  # mod("a",7)
    "ok:F7fefffffffffffff",  # float(DBL_MAX)
    "ok:F7fefffffffffffff",  # float(DBL_MAX+1)
    "ok:F7fefffffffffffff",  # float(DBL_MAX+2^970-1)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # float(DBL_MAX+2^970)
    "ok:Fffefffffffffffff",  # float(-DBL_MAX)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # float(-(DBL_MAX+2^970))
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # float(2^1024)
    "ok:F7fe0000000000000",  # float(2^1023)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # /(10^400,3)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # /(-10^400,3)
    "ok:i10",  # /(10^400,10^399)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # float(10^400r3)
    "ok:i" * string(big(10) ^ 400),  # max(DBL_MAX,10^400)
    "ok:i" * string(-big(10) ^ 400),  # min(-DBL_MAX,-10^400)
    "ok:i" * string(big(10) ^ 400)  # max(10^400,DBL_MAX)
]

"`X is E` for a case tree: the outcome string, a Julia exception included (it would be a defect)."
function _aoutcome_of(c)::String
    try
        return _aoutcome(_arun(:is, _A[_av(), _atree(c)])...)
    catch e
        return "THROW:" * sprint(showerror, e)
    end
end

"`X is E` for a case tree, a Julia exception included as the throw (it propagates)."
_aoutcome_of_raw(c) = _aoutcome(_arun(:is, _A[_av(), _atree(c)])...)

# swipl's written floats in an outcome line (a NaN or an infinity too) as the kernel's bit patterns
function _afloat_bits(line::String)::String
    function fbits(m)
        x = if endswith(m, "NaN")
            NaN
        elseif endswith(m, "Inf")
            m[2] == '-' ? -Inf : Inf
        else
            parse(Float64, m[2:end])
        end
        return "F" * string(reinterpret(UInt64, x); base=16)
    end
    return replace(line, r"f-?[0-9]+\.[0-9]+(?:e[+-]?[0-9]+)?(?:NaN|Inf)?" => fbits)
end

const _A_ARITHA_FUNCS = (
    :/, :(//), :mod, :rem, :div, :abs, :sign, :min, :max, :copysign, :gcd, :msb,
    Symbol("/\\"), Symbol("\\/"), :xor, Symbol("\\"), :integer, :round, :truncate, :float,
    :floor, :ceiling, :ceil, :float_integer_part, :float_fractional_part
)

# the functions no argument of which raises (every kind of number is accepted)
const _A_ARITHA_NO_ERR_ROW = (
    :sign, :abs, :float_integer_part, :float_fractional_part, :min, :max, :copysign,
    :truncate, :ceil, :round, :floor
)

@testset "arith-a: the 25 functions of pl-arith.c's table added — swipl's answers (pinned)" begin
    @test length(_A_ARITHA_CASES) == length(_A_ARITHA_EXPECT)
    got = [_aoutcome_of(c) for c in _A_ARITHA_CASES]
    bad = [k for k in eachindex(got) if got[k] != _A_ARITHA_EXPECT[k]]
    for k in bad[1:min(end, 8)]
        src = _asrc(_A_ARITHA_CASES[k])
        println(stderr, "  arith-a DIVERGES: ", src, "\n    kernel ", got[k])
        println(stderr, "    swipl  ", _A_ARITHA_EXPECT[k])
    end
    @test isempty(bad)
    # the guard has teeth: every function has a case that succeeds and one that raises (the rows
    # that kill the mutants — mod's sign rule, round at .5, xor as \/ — are among them)
    head(c) = c isa Tuple ? c[1] : nothing
    for f in _A_ARITHA_FUNCS
        ks = [k for k in eachindex(_A_ARITHA_CASES) if head(_A_ARITHA_CASES[k]) === f]
        @test any(k -> startswith(_A_ARITHA_EXPECT[k], "ok:"), ks)
        if !(f in _A_ARITHA_NO_ERR_ROW)
            @test any(k -> startswith(_A_ARITHA_EXPECT[k], "err:"), ks)
        end
    end
    @test count(startswith("ok:F"), _A_ARITHA_EXPECT) > 20 &&
        count(startswith("ok:i"), _A_ARITHA_EXPECT) > 150 &&
        count(startswith("ok:q"), _A_ARITHA_EXPECT) > 5 &&
        count(startswith("err:"), _A_ARITHA_EXPECT) > 50
end

# ── arith-b: the functions of pl-arith.c's table added by arith_funcs_design.md §2 (powers,
# transcendental, constants and system), pinned to swipl's own answers; the INT64_MIN rows of the
# audit's probe (D-0024, A-0020) that were not pinned yet, and the rational-to-double rows of D-0027
# (A-0022). Same format as `_A_ARITHA_CASES`: pasted from the oracle (the pin's build, 10.1.18), and
# re-run through swipl by the live testset at the end of this file.
# Known surprises, pinned like the rest: `0 ** 1.5` is the integer 0 (the special cases return before the
# float path) and `2 ** 0.0` the integer 1; `log(0)` is a float_overflow, not undefined; `atan2(0, 0)`
# is 0.0 (glibc); an inexact rational power is a float (`2 ** (1r2)`), an exact one stays a rational
# (`4r9 ** (1r2)` is 2r3); `sin(pi)` is 1.2246467991473532e-16, not 0. `2 ** (2 ** 64)` is swipl's
# resource_error and, since L1f f2, the kernel's (int_too_big, below).
# The exponentiation functions are named by `Symbol("**")`: `:**` does not parse.
const _A_POW2 = Symbol("**")
const _A_ARITHB_CASES = Any[
    # ** and ^: integers (an integer when the exponent is not negative), the special bases, the
    # promotion to a big integer, the size estimate
    (_A_POW2, 2, 3), (_A_POW2, 2, 0), (_A_POW2, 0, 0), (_A_POW2, 0, 5), (_A_POW2, 0, -1),
    (_A_POW2, 1, -5),
    (_A_POW2, -1, 3), (_A_POW2, -1, 4), (_A_POW2, -1, big(2)^70 + 1),
    (_A_POW2, -1, -big(2)^70),
    (_A_POW2, 1, big(2)^70), (_A_POW2, 0, big(2)^70), (_A_POW2, 2, -1), (_A_POW2, 2, -3),
    (_A_POW2, -2, -3),
    (_A_POW2, 3, 39), (_A_POW2, 3, 40), (_A_POW2, 7, 77), (_A_POW2, -7, 77),
    (_A_POW2, 2, 62), (_A_POW2, 2, 63),
    (_A_POW2, -2, 63), (_A_POW2, -2, 64), (_A_POW2, typemax(Int64), 2),
    (_A_POW2, typemin(Int64), 2),
    (_A_POW2, typemin(Int64), 3), (_A_POW2, big(2)^70, 3), (_A_POW2, -big(2)^70, 3),
    (_A_POW2, big(10)^30, 0), (_A_POW2, big(10)^30, -1), (_A_POW2, 2, 100),
    (_A_POW2, 10, 18), (_A_POW2, 10, 19),
    (_A_POW2, -10, 19), (_A_POW2, 1, 1000000), (_A_POW2, "a", 2),
    (:msb, (_A_POW2, 2, 100000)), (:msb, (_A_POW2, 3, 20000)),
    (:msb, (_A_POW2, big(2)^70, 300)),
    # a float on either side, the zero base, NaN, infinity
    (_A_POW2, 0, 1.5), (_A_POW2, 0, -1.5), (_A_POW2, 0, NaN), (_A_POW2, 1, 1.5),
    (_A_POW2, 1, NaN), (_A_POW2, 2, 0.0),
    (_A_POW2, 0, 0.0), (_A_POW2, 2.0, 0), (_A_POW2, NaN, 0), (_A_POW2, 2.0, 3),
    (_A_POW2, 2.0, 0.5), (_A_POW2, 2, 0.5),
    (_A_POW2, 2, 3.0), (_A_POW2, -8.0, 1 / 3), (_A_POW2, -1, 0.5), (_A_POW2, 0.0, -1),
    (_A_POW2, -0.0, -1),
    (_A_POW2, -0.0, -2), (_A_POW2, 0.0, 0), (_A_POW2, 0.0, 0.0), (_A_POW2, 0.0, -1.0),
    (_A_POW2, 0.0, 2),
    (_A_POW2, 2.5, 2), (_A_POW2, 1.0e200, 2), (_A_POW2, 1.0e-200, 2), (_A_POW2, 1.0, NaN),
    (_A_POW2, NaN, 1.0),
    (_A_POW2, Inf, -1), (_A_POW2, Inf, 2), (_A_POW2, 2, Inf), (_A_POW2, 2, -Inf),
    (_A_POW2, 0.5, Inf),
    (_A_POW2, 10, 400.0), (_A_POW2, big(10)^30, 0.5), (_A_POW2, 1 // big(3), 2.0),
    (_A_POW2, 1.5, 1 // big(3)),
    # rationals: to an integer power, to a rational power (exact roots stay exact), inexact roots
    # and out-of-range exponents become floats
    (_A_POW2, 1 // big(2), 3), (_A_POW2, 1 // big(2), -3), (_A_POW2, -1 // big(2), 3),
    (_A_POW2, -2 // big(3), -3),
    (_A_POW2, 2 // big(3), 0), (_A_POW2, 1 // big(2), 1 // big(2)),
    (_A_POW2, 1 // big(4), 1 // big(2)),
    (_A_POW2, 4 // big(9), 1 // big(2)), (_A_POW2, -8 // big(27), 1 // big(3)),
    (_A_POW2, -8 // big(27), 2 // big(3)), (_A_POW2, -8 // big(27), -2 // big(3)),
    (_A_POW2, -1 // big(4), 1 // big(2)), (_A_POW2, 8, 1 // big(3)),
    (_A_POW2, -8, 1 // big(3)),
    (_A_POW2, -8, 2 // big(3)), (_A_POW2, 8, -1 // big(3)), (_A_POW2, 8, -2 // big(3)),
    (_A_POW2, 2, 1 // big(2)),
    (_A_POW2, 4, 1 // big(2)), (_A_POW2, -4, 1 // big(2)), (_A_POW2, 0, 1 // big(2)),
    (_A_POW2, 1, 1 // big(2)),
    (_A_POW2, -1, 1 // big(2)), (_A_POW2, 27, 2 // big(3)), (_A_POW2, 16, 3 // big(4)),
    (_A_POW2, 16, -3 // big(4)), (_A_POW2, big(2)^100, 1 // big(2)),
    (_A_POW2, big(2)^101, 1 // big(2)),
    (_A_POW2, 2, 1 // big(2)^70), (_A_POW2, 3 // big(2), 1 // big(2)^70),
    (_A_POW2, 2.0, 1 // big(2)),
    (_A_POW2, -2.0, 1 // big(2)), (_A_POW2, -2.0, 1 // big(3)),
    (_A_POW2, -2.0, 2 // big(3)),
    (_A_POW2, 0.0, 1 // big(2)), (_A_POW2, 0.0, -1 // big(2)), (_A_POW2, 4.0, -1 // big(2)),
    (_A_POW2, 1 // big(2), 0.5), (_A_POW2, 1 // big(2), 1 // big(3)),
    # inexact roots of integers and rationals beyond the square (Newton's iteration), exact ones too
    (_A_POW2, 2, 1 // big(3)), (_A_POW2, 2, -1 // big(3)), (_A_POW2, 100, 1 // big(5)),
    (_A_POW2, 3, 2 // big(3)), (_A_POW2, 9 // big(8), 1 // big(3)),
    (_A_POW2, 8 // big(9), 1 // big(3)), (_A_POW2, 27 // big(8), 2 // big(3)),
    (_A_POW2, 32, 1 // big(5)), (_A_POW2, 243 // big(32), -1 // big(5)),
    # errors: the arguments are evaluated first, last one first
    (_A_POW2, nothing, 2), (_A_POW2, 2, nothing), (_A_POW2, :a, 2), (_A_POW2, nothing, :a),
    # ^ is the same function
    (:^, 2, 3), (:^, 2, -1), (:^, 0, -1), (:^, 0, 0), (:^, -3, 3), (:^, 8, 1 // big(3)),
    (:^, 2.0, 0.5), (:^, 1 // big(2), 2), (:^, big(2)^70, 2), (:^, nothing, 1),
    (:^, 2, 0.5),
    (:^, 2, 62),
    # sqrt
    (:sqrt, 4), (:sqrt, 2), (:sqrt, 0), (:sqrt, -1), (:sqrt, 0.0), (:sqrt, -0.0),
    (:sqrt, 1 // big(4)), (:sqrt, big(10)^40), (:sqrt, big(10)^400), (:sqrt, 2.25),
    (:sqrt, -4.0), (:sqrt, Inf), (:sqrt, NaN), (:sqrt, 1.0e-320), (:sqrt, nothing),
    (:sqrt, :a), (:sqrt, typemax(Int64)), (:sqrt, "a"),
    # exp, log
    (:exp, 0), (:exp, 1), (:exp, -1), (:exp, 710), (:exp, -745.0), (:exp, -746.0),
    (:exp, -1000), (:exp, 0.5), (:exp, 1 // big(2)), (:exp, big(2)^70), (:exp, Inf),
    (:exp, -Inf), (:exp, NaN), (:exp, 709.0), (:exp, 709.782712893384), (:exp, nothing),
    (:exp, -0.0), (:exp, 1.0e-300),
    (:log, 1), (:log, 2), (:log, 0), (:log, -1), (:log, 0.0), (:log, -0.0), (:log, 10.0),
    (:log, big(10)^400), (:log, big(10)^30), (:log, 1 // big(2)), (:log, Inf), (:log, NaN),
    (:log, 1.0e-320), (:log, 5.0e-324), (:log, nothing), (:log, 1.0e300),
    (:log, 2.718281828459045),
    # sin, cos, tan
    (:sin, 0), (:sin, 1), (:sin, -1), (:sin, 1.0), (:sin, 0.5), (:sin, 3), (:sin, 100),
    (:sin, 1.0e22), (:sin, 1.0e300), (:sin, big(10)^20), (:sin, 1 // big(3)), (:sin, Inf),
    (:sin, NaN), (:sin, -0.0), (:sin, nothing), (:sin, 1.0e-320),
    (:cos, 0), (:cos, 1), (:cos, -1), (:cos, 1.0), (:cos, 0.5), (:cos, 3), (:cos, 100),
    (:cos, 1.0e22), (:cos, 1.0e300), (:cos, big(10)^20), (:cos, 1 // big(3)), (:cos, Inf),
    (:cos, NaN), (:cos, -0.0), (:cos, nothing),
    (:tan, 0), (:tan, 1), (:tan, -1), (:tan, 1.0), (:tan, 0.5), (:tan, 3), (:tan, 100),
    (:tan, 1.0e22), (:tan, 1.5707963267948966), (:tan, big(10)^20), (:tan, 1 // big(3)),
    (:tan, Inf), (:tan, NaN), (:tan, -0.0), (:tan, nothing),
    # asin, acos, atan
    (:asin, 0), (:asin, 1), (:asin, -1), (:asin, 0.5), (:asin, 2), (:asin, -2),
    (:asin, 1.0),
    (:asin, 1 // big(2)), (:asin, NaN), (:asin, Inf), (:asin, nothing), (:asin, -0.0),
    (:acos, 0), (:acos, 1), (:acos, -1), (:acos, 0.5), (:acos, 2), (:acos, -2),
    (:acos, 1.0),
    (:acos, 1 // big(2)), (:acos, NaN), (:acos, Inf), (:acos, nothing), (:acos, big(10)^30),
    (:atan, 0), (:atan, 1), (:atan, -1), (:atan, 1.0e300), (:atan, Inf), (:atan, -Inf),
    (:atan, NaN), (:atan, 1 // big(3)), (:atan, big(10)^30), (:atan, nothing),
    (:atan, -0.0),
    (:atan, 0.5),
    # atan/2 and atan2/2: the angle of the point (x, y) = (second, first)
    (:atan, 1, 1), (:atan, 1, 0), (:atan, 0, 0), (:atan, 0.0, 0.0), (:atan, 0.0, -0.0),
    (:atan, -0.0, -0.0), (:atan, -1, -1), (:atan, 1, -1), (:atan, -1, 1), (:atan, 1, 2),
    (:atan, 2, 1), (:atan, 1, 1.0), (:atan, 1 // big(2), 1), (:atan, big(10)^30, 1),
    (:atan, Inf, Inf), (:atan, NaN, 1), (:atan, 1, NaN), (:atan, nothing, 1),
    (:atan, 1, nothing),
    (:atan, 1.0e300, 1.0e-300), (:atan, -1, 0), (:atan, 0, -1), (:atan, 3, 1 // big(7)),
    (:atan2, 1, 1), (:atan2, 1, 0), (:atan2, 0, 0), (:atan2, 0.0, -0.0), (:atan2, -1, -1),
    (:atan2, 1, -1), (:atan2, 1, 2), (:atan2, 2, 1), (:atan2, 1 // big(2), 1),
    (:atan2, Inf, Inf), (:atan2, NaN, 1), (:atan2, nothing, 1), (:atan2, 3, 1 // big(7)),
    (:atan2, -1, 0), (:atan2, 0, -1), (:atan2, 1.5, 2.5),
    # the constants: an atom, and the compound with no arguments
    :pi, :e, (:pi,), (:e,), (:+, :pi, 1), (:*, 2, :pi), (:-, :e), (:sin, :pi),
    (:cos, (:/, :pi, 2)),
    (:foo,), (:pi, 1), (:e, 1, 2), (:+, :foo, 1),
    # random/1: only the deterministic outcomes (random(1) is 0) and the errors; the range of the
    # others is checked in its own testset
    (:random, 1), (:random, 1.0), (:random, 0), (:random, -3), (:random, 1.5),
    (:random, nothing),
    (:random, :a), (:random, 1 // big(2)), (:random, -big(2)^70), (:random, NaN),
    (:random, Inf), (:random, 0.0), (:random, -0.0), (:random, -1.0),
    # nested
    (:sqrt, (:+, 16, 9)), (:exp, (:log, 2)), (_A_POW2, (:sqrt, 16), 2),
    (:atan2, (:sin, 1), (:cos, 1)),
    (_A_POW2, 2, (:/, 1, 2)), (:^, (:/, 1, 4), 2), (:log, (:exp, 1)),
    (:floor, (:*, 100, (:sin, 1))),
    (:+, (_A_POW2, 2, 10), (_A_POW2, 2, -1)), (:max, (:sqrt, 2), (:atan, 1, 1)),
    # D-0024: the INT64_MIN rows of the audit's probe that were not pinned yet
    (:-, typemin(Int64)), (:*, typemin(Int64), -1), (:gcd, typemin(Int64), 0),
    (:min, typemin(Int64), 0), (:truncate, typemin(Int64)), (:integer, typemin(Int64)),
    # D-0027 / A-0022: a rational to the nearest double (mpq_to_double) — exact quotients near a power
    # of ten, the overflow, and the subnormals (`float_underflow` is `ignore`)
    (:float, big(10)^400 // (big(10)^399 + 1)), (:float, (big(10)^400 + 1) // big(10)^400),
    (:float, big(10)^700 // 3), (:float, 1 // big(10)^400), (:float, 1 // big(2)^1074),
    (:float, 1 // big(2)^1073), (:float, 1 // big(2)^1075), (:float, 3 // big(2)^1075)
]

const _A_ARITHB_EXPECT = String[
    "ok:i8",  # **(2,3)
    "ok:i1",  # **(2,0)
    "ok:i1",  # **(0,0)
    "ok:i0",  # **(0,5)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[122, 101, 114, 111, 95, 100, 105, 118, 105, 115, 111, 114])@ca[47]/2(a[42, 42],i2)@_",  # **(0,-1)
    "ok:i1",  # **(1,-5)
    "ok:i-1",  # **(-1,3)
    "ok:i1",  # **(-1,4)
    "ok:i-1",  # **(-1,1180591620717411303425)
    "ok:i1",  # **(-1,-1180591620717411303424)
    "ok:i1",  # **(1,1180591620717411303424)
    "ok:i0",  # **(0,1180591620717411303424)
    "ok:F3fe0000000000000",  # **(2,-1)
    "ok:F3fc0000000000000",  # **(2,-3)
    "ok:Fbfc0000000000000",  # **(-2,-3)
    "ok:i4052555153018976267",  # **(3,39)
    "ok:i12157665459056928801",  # **(3,40)
    "ok:i118181386580595879976868414312001964434038548836769923458287039207",  # **(7,77)
    "ok:i-118181386580595879976868414312001964434038548836769923458287039207",  # **(-7,77)
    "ok:i4611686018427387904",  # **(2,62)
    "ok:i9223372036854775808",  # **(2,63)
    "ok:i-9223372036854775808",  # **(-2,63)
    "ok:i18446744073709551616",  # **(-2,64)
    "ok:i85070591730234615847396907784232501249",  # **(9223372036854775807,2)
    "ok:i85070591730234615865843651857942052864",  # **(-9223372036854775808,2)
    "ok:i-784637716923335095479473677900958302012794430558004314112",  # **(-9223372036854775808,3)
    "ok:i1645504557321206042154969182557350504982735865633579863348609024",  # **(1180591620717411303424,3)
    "ok:i-1645504557321206042154969182557350504982735865633579863348609024",  # **(-1180591620717411303424,3)
    "ok:i1",  # **(<31d>,0)
    "ok:F39b4484bfeebc29f",  # **(<31d>,-1)
    "ok:i1267650600228229401496703205376",  # **(2,100)
    "ok:i1000000000000000000",  # **(10,18)
    "ok:i10000000000000000000",  # **(10,19)
    "ok:i-10000000000000000000",  # **(-10,19)
    "ok:i1",  # **(1,1000000)
    "ok:i9409",  # **("a",2)
    "ok:i100000",  # msb(**(2,100000))
    "ok:i31699",  # msb(**(3,20000))
    "ok:i21000",  # msb(**(1180591620717411303424,300))
    "ok:i0",  # **(0,1.5)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[122, 101, 114, 111, 95, 100, 105, 118, 105, 115, 111, 114])@ca[47]/2(a[42, 42],i2)@_",  # **(0,-1.5)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # **(0,1.5NaN)
    "ok:i1",  # **(1,1.5)
    "ok:i1",  # **(1,1.5NaN)
    "ok:i1",  # **(2,0.0)
    "ok:i1",  # **(0,0.0)
    "ok:i1",  # **(2.0,0)
    "ok:i1",  # **(1.5NaN,0)
    "ok:F4020000000000000",  # **(2.0,3)
    "ok:F3ff6a09e667f3bcd",  # **(2.0,0.5)
    "ok:F3ff6a09e667f3bcd",  # **(2,0.5)
    "ok:F4020000000000000",  # **(2,3.0)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # **(-8.0,0.3333333333333333)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # **(-1,0.5)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[122, 101, 114, 111, 95, 100, 105, 118, 105, 115, 111, 114])@ca[47]/2(a[42, 42],i2)@_",  # **(0.0,-1)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[122, 101, 114, 111, 95, 100, 105, 118, 105, 115, 111, 114])@ca[47]/2(a[42, 42],i2)@_",  # **(-0.0,-1)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[122, 101, 114, 111, 95, 100, 105, 118, 105, 115, 111, 114])@ca[47]/2(a[42, 42],i2)@_",  # **(-0.0,-2)
    "ok:i1",  # **(0.0,0)
    "ok:i1",  # **(0.0,0.0)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[122, 101, 114, 111, 95, 100, 105, 118, 105, 115, 111, 114])@ca[47]/2(a[42, 42],i2)@_",  # **(0.0,-1.0)
    "ok:F0",  # **(0.0,2)
    "ok:F4019000000000000",  # **(2.5,2)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # **(1.0e200,2)
    "ok:F0",  # **(1.0e-200,2)
    "ok:F3ff0000000000000",  # **(1.0,1.5NaN)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # **(1.5NaN,1.0)
    "ok:F0",  # **(1.0Inf,-1)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # **(1.0Inf,2)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # **(2,1.0Inf)
    "ok:F0",  # **(2,-1.0Inf)
    "ok:F0",  # **(0.5,1.0Inf)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # **(10,400.0)
    "ok:F430c6bf526340000",  # **(<31d>,0.5)
    "ok:F3fbc71c71c71c71c",  # **(1r3,2.0)
    "ok:F3ff250bfe1b082f5",  # **(1.5,1r3)
    "ok:q1r8",  # **(1r2,3)
    "ok:i8",  # **(1r2,-3)
    "ok:q-1r8",  # **(-1r2,3)
    "ok:q-27r8",  # **(-2r3,-3)
    "ok:i1",  # **(2r3,0)
    "ok:F3fe6a09e667f3bcd",  # **(1r2,1r2)
    "ok:q1r2",  # **(1r4,1r2)
    "ok:q2r3",  # **(4r9,1r2)
    "ok:q-2r3",  # **(-8r27,1r3)
    "ok:q4r9",  # **(-8r27,2r3)
    "ok:q9r4",  # **(-8r27,-2r3)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # **(-1r4,1r2)
    "ok:i2",  # **(8,1r3)
    "ok:i-2",  # **(-8,1r3)
    "ok:i4",  # **(-8,2r3)
    "ok:q1r2",  # **(8,-1r3)
    "ok:q1r4",  # **(8,-2r3)
    "ok:F3ff6a09e667f3bcd",  # **(2,1r2)
    "ok:i2",  # **(4,1r2)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # **(-4,1r2)
    "ok:i0",  # **(0,1r2)
    "ok:i1",  # **(1,1r2)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # **(-1,1r2)
    "ok:i9",  # **(27,2r3)
    "ok:i8",  # **(16,3r4)
    "ok:q1r8",  # **(16,-3r4)
    "ok:i1125899906842624",  # **(<31d>,1r2)
    "ok:F4316a09e667f3bcd",  # **(<31d>,1r2)
    "ok:F3ff0000000000000",  # **(2,1r1180591620717411303424)
    "ok:F3ff0000000000000",  # **(3r2,1r1180591620717411303424)
    "ok:F3ff6a09e667f3bcd",  # **(2.0,1r2)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # **(-2.0,1r2)
    "ok:Fbff428a2f98d728b",  # **(-2.0,1r3)
    "ok:F3ff965fea53d6e3c",  # **(-2.0,2r3)
    "ok:F0",  # **(0.0,1r2)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[122, 101, 114, 111, 95, 100, 105, 118, 105, 115, 111, 114])@ca[47]/2(a[42, 42],i2)@_",  # **(0.0,-1r2)
    "ok:F3fe0000000000000",  # **(4.0,-1r2)
    "ok:F3fe6a09e667f3bcd",  # **(1r2,0.5)
    "ok:F3fe965fea53d6e3d",  # **(1r2,1r3)
    "ok:F3ff428a2f98d728b",  # **(2,1r3)
    "ok:F3fe965fea53d6e3d",  # **(2,-1r3)
    "ok:F40041857e9d4cc5f",  # **(100,1r5)
    "ok:F4000a402fcc79298",  # **(3,2r3)
    "ok:F3ff0a402fcc79298",  # **(9r8,1r3)
    "ok:F3feec49b0c1853f3",  # **(8r9,1r3)
    "ok:q9r4",  # **(27r8,2r3)
    "ok:i2",  # **(32,1r5)
    "ok:q2r3",  # **(243r32,-1r5)
    "err:a[105, 110, 115, 116, 97, 110, 116, 105, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # **(_,2)
    "err:a[105, 110, 115, 116, 97, 110, 116, 105, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # **(2,_)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[101, 118, 97, 108, 117, 97, 98, 108, 101],ca[47]/2(a[97],i0))@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # **(a,2)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[101, 118, 97, 108, 117, 97, 98, 108, 101],ca[47]/2(a[97],i0))@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # **(_,a)
    "ok:i8",  # ^(2,3)
    "ok:F3fe0000000000000",  # ^(2,-1)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[122, 101, 114, 111, 95, 100, 105, 118, 105, 115, 111, 114])@ca[47]/2(a[42, 42],i2)@_",  # ^(0,-1)
    "ok:i1",  # ^(0,0)
    "ok:i-27",  # ^(-3,3)
    "ok:i2",  # ^(8,1r3)
    "ok:F3ff6a09e667f3bcd",  # ^(2.0,0.5)
    "ok:q1r4",  # ^(1r2,2)
    "ok:i1393796574908163946345982392040522594123776",  # ^(1180591620717411303424,2)
    "err:a[105, 110, 115, 116, 97, 110, 116, 105, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # ^(_,1)
    "ok:F3ff6a09e667f3bcd",  # ^(2,0.5)
    "ok:i4611686018427387904",  # ^(2,62)
    "ok:F4000000000000000",  # sqrt(4)
    "ok:F3ff6a09e667f3bcd",  # sqrt(2)
    "ok:F0",  # sqrt(0)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # sqrt(-1)
    "ok:F0",  # sqrt(0.0)
    "ok:F8000000000000000",  # sqrt(-0.0)
    "ok:F3fe0000000000000",  # sqrt(1r4)
    "ok:F4415af1d78b58c40",  # sqrt(<41d>)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # sqrt(<401d>)
    "ok:F3ff8000000000000",  # sqrt(2.25)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # sqrt(-4.0)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # sqrt(1.0Inf)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # sqrt(1.5NaN)
    "ok:F1eb67e93ddbc0e73",  # sqrt(1.0e-320)
    "err:a[105, 110, 115, 116, 97, 110, 116, 105, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # sqrt(_)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[101, 118, 97, 108, 117, 97, 98, 108, 101],ca[47]/2(a[97],i0))@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # sqrt(a)
    "ok:F41e6a09e667f3bcd",  # sqrt(9223372036854775807)
    "ok:F4023b29d7d635662",  # sqrt("a")
    "ok:F3ff0000000000000",  # exp(0)
    "ok:F4005bf0a8b145769",  # exp(1)
    "ok:F3fd78b56362cef38",  # exp(-1)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # exp(710)
    "ok:F1",  # exp(-745.0)
    "ok:F0",  # exp(-746.0)
    "ok:F0",  # exp(-1000)
    "ok:F3ffa61298e1e069c",  # exp(0.5)
    "ok:F3ffa61298e1e069c",  # exp(1r2)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # exp(1180591620717411303424)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # exp(1.0Inf)
    "ok:F0",  # exp(-1.0Inf)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # exp(1.5NaN)
    "ok:F7fdd422d2be5dc9b",  # exp(709.0)
    "ok:F7fefffffffffff2a",  # exp(709.782712893384)
    "err:a[105, 110, 115, 116, 97, 110, 116, 105, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # exp(_)
    "ok:F3ff0000000000000",  # exp(-0.0)
    "ok:F3ff0000000000000",  # exp(1.0e-300)
    "ok:F0",  # log(1)
    "ok:F3fe62e42fefa39ef",  # log(2)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # log(0)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # log(-1)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # log(0.0)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # log(-0.0)
    "ok:F40026bb1bbb55516",  # log(10.0)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # log(<401d>)
    "ok:F405144f69ff9ffc4",  # log(<31d>)
    "ok:Fbfe62e42fefa39ef",  # log(1r2)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # log(1.0Inf)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # log(1.5NaN)
    "ok:Fc087069e3078e52d",  # log(1.0e-320)
    "ok:Fc0874385446d71c3",  # log(5.0e-324)
    "err:a[105, 110, 115, 116, 97, 110, 116, 105, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # log(_)
    "ok:F4085963447f87fb5",  # log(1.0e300)
    "ok:F3ff0000000000000",  # log(2.718281828459045)
    "ok:F0",  # sin(0)
    "ok:F3feaed548f090cee",  # sin(1)
    "ok:Fbfeaed548f090cee",  # sin(-1)
    "ok:F3feaed548f090cee",  # sin(1.0)
    "ok:F3fdeaee8744b05f0",  # sin(0.5)
    "ok:F3fc210386db6d55b",  # sin(3)
    "ok:Fbfe03425b78c4db8",  # sin(100)
    "ok:Fbfeb453ab76bf397",  # sin(1.0e22)
    "ok:Fbfea2c16b010e385",  # sin(1.0e300)
    "ok:Fbfe4a5e605fd6450",  # sin(100000000000000000000)
    "ok:F3fd4f0c2068a80c6",  # sin(1r3)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # sin(1.0Inf)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # sin(1.5NaN)
    "ok:F8000000000000000",  # sin(-0.0)
    "err:a[105, 110, 115, 116, 97, 110, 116, 105, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # sin(_)
    "ok:F7e8",  # sin(1.0e-320)
    "ok:F3ff0000000000000",  # cos(0)
    "ok:F3fe14a280fb5068c",  # cos(1)
    "ok:F3fe14a280fb5068c",  # cos(-1)
    "ok:F3fe14a280fb5068c",  # cos(1.0)
    "ok:F3fec1528065b7d50",  # cos(0.5)
    "ok:Fbfefae04be85e5d2",  # cos(3)
    "ok:F3feb981dbf665fdf",  # cos(100)
    "ok:F3fe0be2cef01c8f4",  # cos(1.0e22)
    "ok:Fbfe2699022adc4c1",  # cos(1.0e300)
    "ok:F3fe872720fc60d3d",  # cos(100000000000000000000)
    "ok:F3fee3d165991982d",  # cos(1r3)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # cos(1.0Inf)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # cos(1.5NaN)
    "ok:F3ff0000000000000",  # cos(-0.0)
    "err:a[105, 110, 115, 116, 97, 110, 116, 105, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # cos(_)
    "ok:F0",  # tan(0)
    "ok:F3ff8eb245cbee3a6",  # tan(1)
    "ok:Fbff8eb245cbee3a6",  # tan(-1)
    "ok:F3ff8eb245cbee3a6",  # tan(1.0)
    "ok:F3fe17b4f5bf3474a",  # tan(0.5)
    "ok:Fbfc23ef71254b86f",  # tan(3)
    "ok:Fbfe2ca74d62b5d38",  # tan(100)
    "ok:Fbffa0f79c1b6b257",  # tan(1.0e22)
    "ok:F434d02967c31cdb5",  # tan(1.5707963267948966)
    "ok:Fbfeb06fbbe995394",  # tan(100000000000000000000)
    "ok:F3fd62904a5d165cd",  # tan(1r3)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # tan(1.0Inf)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # tan(1.5NaN)
    "ok:F8000000000000000",  # tan(-0.0)
    "err:a[105, 110, 115, 116, 97, 110, 116, 105, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # tan(_)
    "ok:F0",  # asin(0)
    "ok:F3ff921fb54442d18",  # asin(1)
    "ok:Fbff921fb54442d18",  # asin(-1)
    "ok:F3fe0c152382d7366",  # asin(0.5)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # asin(2)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # asin(-2)
    "ok:F3ff921fb54442d18",  # asin(1.0)
    "ok:F3fe0c152382d7366",  # asin(1r2)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # asin(1.5NaN)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # asin(1.0Inf)
    "err:a[105, 110, 115, 116, 97, 110, 116, 105, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # asin(_)
    "ok:F8000000000000000",  # asin(-0.0)
    "ok:F3ff921fb54442d18",  # acos(0)
    "ok:F0",  # acos(1)
    "ok:F400921fb54442d18",  # acos(-1)
    "ok:F3ff0c152382d7366",  # acos(0.5)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # acos(2)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # acos(-2)
    "ok:F0",  # acos(1.0)
    "ok:F3ff0c152382d7366",  # acos(1r2)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # acos(1.5NaN)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # acos(1.0Inf)
    "err:a[105, 110, 115, 116, 97, 110, 116, 105, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # acos(_)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # acos(<31d>)
    "ok:F0",  # atan(0)
    "ok:F3fe921fb54442d18",  # atan(1)
    "ok:Fbfe921fb54442d18",  # atan(-1)
    "ok:F3ff921fb54442d18",  # atan(1.0e300)
    "ok:F3ff921fb54442d18",  # atan(1.0Inf)
    "ok:Fbff921fb54442d18",  # atan(-1.0Inf)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # atan(1.5NaN)
    "ok:F3fd4978fa3269ee1",  # atan(1r3)
    "ok:F3ff921fb54442d18",  # atan(<31d>)
    "err:a[105, 110, 115, 116, 97, 110, 116, 105, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # atan(_)
    "ok:F8000000000000000",  # atan(-0.0)
    "ok:F3fddac670561bb4f",  # atan(0.5)
    "ok:F3fe921fb54442d18",  # atan(1,1)
    "ok:F3ff921fb54442d18",  # atan(1,0)
    "ok:F0",  # atan(0,0)
    "ok:F0",  # atan(0.0,0.0)
    "ok:F400921fb54442d18",  # atan(0.0,-0.0)
    "ok:Fc00921fb54442d18",  # atan(-0.0,-0.0)
    "ok:Fc002d97c7f3321d2",  # atan(-1,-1)
    "ok:F4002d97c7f3321d2",  # atan(1,-1)
    "ok:Fbfe921fb54442d18",  # atan(-1,1)
    "ok:F3fddac670561bb4f",  # atan(1,2)
    "ok:F3ff1b6e192ebbe44",  # atan(2,1)
    "ok:F3fe921fb54442d18",  # atan(1,1.0)
    "ok:F3fddac670561bb4f",  # atan(1r2,1)
    "ok:F3ff921fb54442d18",  # atan(<31d>,1)
    "ok:F3fe921fb54442d18",  # atan(1.0Inf,1.0Inf)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # atan(1.5NaN,1)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # atan(1,1.5NaN)
    "err:a[105, 110, 115, 116, 97, 110, 116, 105, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # atan(_,1)
    "err:a[105, 110, 115, 116, 97, 110, 116, 105, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # atan(1,_)
    "ok:F3ff921fb54442d18",  # atan(1.0e300,1.0e-300)
    "ok:Fbff921fb54442d18",  # atan(-1,0)
    "ok:F400921fb54442d18",  # atan(0,-1)
    "ok:F3ff85f14d43d81be",  # atan(3,1r7)
    "ok:F3fe921fb54442d18",  # atan2(1,1)
    "ok:F3ff921fb54442d18",  # atan2(1,0)
    "ok:F0",  # atan2(0,0)
    "ok:F400921fb54442d18",  # atan2(0.0,-0.0)
    "ok:Fc002d97c7f3321d2",  # atan2(-1,-1)
    "ok:F4002d97c7f3321d2",  # atan2(1,-1)
    "ok:F3fddac670561bb4f",  # atan2(1,2)
    "ok:F3ff1b6e192ebbe44",  # atan2(2,1)
    "ok:F3fddac670561bb4f",  # atan2(1r2,1)
    "ok:F3fe921fb54442d18",  # atan2(1.0Inf,1.0Inf)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # atan2(1.5NaN,1)
    "err:a[105, 110, 115, 116, 97, 110, 116, 105, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # atan2(_,1)
    "ok:F3ff85f14d43d81be",  # atan2(3,1r7)
    "ok:Fbff921fb54442d18",  # atan2(-1,0)
    "ok:F400921fb54442d18",  # atan2(0,-1)
    "ok:F3fe14b1dd5f90ce1",  # atan2(1.5,2.5)
    "ok:F400921fb54442d18",  # pi
    "ok:F4005bf0a8b145769",  # e
    "ok:F400921fb54442d18",  # pi()
    "ok:F4005bf0a8b145769",  # e()
    "ok:F401090fdaa22168c",  # +(pi,1)
    "ok:F401921fb54442d18",  # *(2,pi)
    "ok:Fc005bf0a8b145769",  # -(e)
    "ok:F3ca1a62633145c07",  # sin(pi)
    "ok:F3c91a62633145c07",  # cos(/(pi,2))
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[101, 118, 97, 108, 117, 97, 98, 108, 101],ca[102, 111, 111]/0())@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # foo()
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[101, 118, 97, 108, 117, 97, 98, 108, 101],ca[47]/2(a[112, 105],i1))@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # pi(1)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[101, 118, 97, 108, 117, 97, 98, 108, 101],ca[47]/2(a[101],i2))@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # e(1,2)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[101, 118, 97, 108, 117, 97, 98, 108, 101],ca[47]/2(a[102, 111, 111],i0))@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # +(foo,1)
    "ok:i0",  # random(1)
    "ok:i0",  # random(1.0)
    "err:ca[100, 111, 109, 97, 105, 110, 95, 101, 114, 114, 111, 114]/2(a[110, 111, 116, 95, 108, 101, 115, 115, 95, 116, 104, 97, 110, 95, 111, 110, 101],i0)@ca[47]/2(a[114, 97, 110, 100, 111, 109],i1)@_",  # random(0)
    "err:ca[100, 111, 109, 97, 105, 110, 95, 101, 114, 114, 111, 114]/2(a[110, 111, 116, 95, 108, 101, 115, 115, 95, 116, 104, 97, 110, 95, 111, 110, 101],i-3)@ca[47]/2(a[114, 97, 110, 100, 111, 109],i1)@_",  # random(-3)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[105, 110, 116, 101, 103, 101, 114],F3ff8000000000000)@ca[47]/2(a[114, 97, 110, 100, 111, 109],i1)@_",  # random(1.5)
    "err:a[105, 110, 115, 116, 97, 110, 116, 105, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # random(_)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[101, 118, 97, 108, 117, 97, 98, 108, 101],ca[47]/2(a[97],i0))@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # random(a)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[105, 110, 116, 101, 103, 101, 114],q1r2)@ca[47]/2(a[114, 97, 110, 100, 111, 109],i1)@_",  # random(1r2)
    "err:ca[100, 111, 109, 97, 105, 110, 95, 101, 114, 114, 111, 114]/2(a[110, 111, 116, 95, 108, 101, 115, 115, 95, 116, 104, 97, 110, 95, 111, 110, 101],i-1180591620717411303424)@ca[47]/2(a[114, 97, 110, 100, 111, 109],i1)@_",  # random(-1180591620717411303424)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # random(1.5NaN)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # random(1.0Inf)
    "err:ca[100, 111, 109, 97, 105, 110, 95, 101, 114, 114, 111, 114]/2(a[110, 111, 116, 95, 108, 101, 115, 115, 95, 116, 104, 97, 110, 95, 111, 110, 101],i0)@ca[47]/2(a[114, 97, 110, 100, 111, 109],i1)@_",  # random(0.0)
    "err:ca[100, 111, 109, 97, 105, 110, 95, 101, 114, 114, 111, 114]/2(a[110, 111, 116, 95, 108, 101, 115, 115, 95, 116, 104, 97, 110, 95, 111, 110, 101],i0)@ca[47]/2(a[114, 97, 110, 100, 111, 109],i1)@_",  # random(-0.0)
    "err:ca[100, 111, 109, 97, 105, 110, 95, 101, 114, 114, 111, 114]/2(a[110, 111, 116, 95, 108, 101, 115, 115, 95, 116, 104, 97, 110, 95, 111, 110, 101],i-1)@ca[47]/2(a[114, 97, 110, 100, 111, 109],i1)@_",  # random(-1.0)
    "ok:F4014000000000000",  # sqrt(+(16,9))
    "ok:F4000000000000000",  # exp(log(2))
    "ok:F4030000000000000",  # **(sqrt(16),2)
    "ok:F3ff0000000000000",  # atan2(sin(1),cos(1))
    "ok:F3ff6a09e667f3bcd",  # **(2,/(1,2))
    "ok:F3fb0000000000000",  # ^(/(1,4),2)
    "ok:F3ff0000000000000",  # log(exp(1))
    "ok:i84",  # floor(*(100,sin(1)))
    "ok:F4090020000000000",  # +(**(2,10),**(2,-1))
    "ok:F3ff6a09e667f3bcd",  # max(sqrt(2),atan(1,1))
    "ok:i9223372036854775808",  # -(-9223372036854775808)
    "ok:i9223372036854775808",  # *(-9223372036854775808,-1)
    "ok:i9223372036854775808",  # gcd(-9223372036854775808,0)
    "ok:i-9223372036854775808",  # min(-9223372036854775808,0)
    "ok:i-9223372036854775808",  # truncate(-9223372036854775808)
    "ok:i-9223372036854775808",  # integer(-9223372036854775808)
    "ok:F4024000000000000",  # float(10^400r(10^399+1))
    "ok:F3ff0000000000000",  # float((10^400+1)r10^400)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # float(10^700r3)
    "ok:F0",  # float(1r10^400)
    "ok:F1",  # float(1r2^1074)
    "ok:F2",  # float(1r2^1073)
    "ok:F0",  # float(1r2^1075)
    "ok:F2"  # float(3r2^1075)
]

const _A_ARITHB_FUNCS = (
    _A_POW2, :^, :sqrt, :exp, :log, :sin, :cos, :tan, :asin, :acos, :atan, :atan2, :random
)

@testset "arith-b: the 17 functions of pl-arith.c's table added, D-0024 and D-0027's rows — swipl's answers (pinned)" begin
    @test length(_A_ARITHB_CASES) == length(_A_ARITHB_EXPECT)
    got = [_aoutcome_of(c) for c in _A_ARITHB_CASES]
    bad = [k for k in eachindex(got) if got[k] != _A_ARITHB_EXPECT[k]]
    for k in bad[1:min(end, 8)]
        src = _asrc(_A_ARITHB_CASES[k])
        println(stderr, "  arith-b DIVERGES: ", src, "\n    kernel ", got[k])
        println(stderr, "    swipl  ", _A_ARITHB_EXPECT[k])
    end
    @test isempty(bad)
    # the guard has teeth: every function has a case that succeeds and one that raises (the rows
    # that kill the mutants — atan2's argument order, ** of a negative exponent — are among them),
    # the constants are cases, as atoms and as compounds with no arguments, and atan has both arities
    head(c) = c isa Tuple ? c[1] : nothing
    for f in _A_ARITHB_FUNCS
        ks = [k for k in eachindex(_A_ARITHB_CASES) if head(_A_ARITHB_CASES[k]) === f]
        @test any(k -> startswith(_A_ARITHB_EXPECT[k], "ok:"), ks)
        @test any(k -> startswith(_A_ARITHB_EXPECT[k], "err:"), ks)
    end
    for c in (:pi, :e, (:pi,), (:e,))
        k = findfirst(==(c), _A_ARITHB_CASES)
        @test k !== nothing && startswith(_A_ARITHB_EXPECT[k], "ok:F")
    end
    @test any(c -> head(c) === :atan && length(c) == 2, _A_ARITHB_CASES) &&
        any(c -> head(c) === :atan && length(c) == 3, _A_ARITHB_CASES)
    @test count(startswith("ok:F"), _A_ARITHB_EXPECT) > 120 &&
        count(startswith("ok:i"), _A_ARITHB_EXPECT) > 50 &&
        count(startswith("ok:q"), _A_ARITHB_EXPECT) > 8 &&
        count(startswith("err:"), _A_ARITHB_EXPECT) > 60
end

# `2 ** (2 ** 64)` and kin: swipl raises resource_error(stack) (`int_too_big`), and since L1f f2 the
# kernel too (the global stack's overflow). The live testset at the end checks swipl's side of each row.
# Group F's fuzzer found the shifts (2026-10-23): a negative amount, negated, is read as UNSIGNED by upstream
# (`-LONG_MIN` stays `LONG_MIN`): `1 >> -9223372036854775808` threw a Julia InexactError out of the query; swipl
# 10.1.18's answer is this resource_error for every row below (live in the testset at the end).
const _A_TOOBIG = Any[
    (_A_POW2, 2, big(2)^70),
    (_A_POW2, 2, 1 << 62),
    (:^, 3, -big(2)^70),
    (:>>, 1, typemin(Int64)),
    (:>>, 7, -typemax(Int64)),
    (:>>, -1, typemin(Int64)),
    (:>>, big(2)^63, typemin(Int64)),
    (:>>, 7, -big(2)^63 - 1),
    (:<<, 1, typemax(Int64))
]
@testset "arith-b: an exponent too big is resource_error(stack), as swipl's; the query is closed" begin
    for c in _A_TOOBIG
        @test startswith(_aoutcome_of(c), "err:" * _aenc(_af(:resource_error, _as(:stack))))
        @test _ALD.query == 0
    end
end

# random/1: swipl's generator is not reproducible (no set_random/1 yet), so only the range, the
# spread and the shape of the answer are checked; the errors are in the pinned table above.
@testset "arith-b: random/1 — the range, every value, a big bound" begin
    draw(n, k) = [lk_value(_ais(_af(:random, _ag(n)))) for _ in 1:k]
    d = draw(10, 400)
    @test all(v -> 0 <= v < 10, d) && Set(d) == Set(0:9)
    @test Set(draw(2, 100)) == Set(0:1) && Set(draw(3, 200)) == Set(0:2)
    d = draw(2^62 + 1, 100)                              # the mask is 63 bits: redraws are rare
    @test all(v -> 0 <= v <= 2^62, d) && length(Set(d)) > 90
    d = draw(2^40, 100)
    @test all(v -> 0 <= v < 2^40, d) && any(v -> v >= 2^32, d) && length(Set(d)) > 90
    b = big(2)^70 + 12345
    d = draw(b, 60)
    @test all(v -> 0 <= v < b, d) && any(v -> v > big(2)^64, d) && length(Set(d)) > 55
    @test all(v -> 0 <= v < 1000, [lk_value(_ais(_af(:random, _ag(1000.0)))) for _ in 1:50])
    @test all(
        v -> 0 <= v < 5,
        [lk_value(_ais(_af(:random, _af(:+, _ag(2), _ag(3))))) for _ in 1:50]
    )
end

# cputime/0: the process's CPU seconds — not reproducible, so a float, non-negative, not going back.
@testset "arith-b: cputime is a growing non-negative float" begin
    t1 = lk_value(_ais(_as(:cputime)))
    s = 0.0
    for i in 1:2_000_000
        s += sqrt(i)                                       # burn some CPU
    end
    t2 = lk_value(_ais(_af(:cputime)))
    @test t1 isa Float64 && t2 isa Float64 && 0.0 <= t1 <= t2 && s > 0
    @test lk_value(_ais(_af(:+, _as(:cputime), _ag(1)))) >= 1.0
end

# ── arith-c: the last functions of pl-arith.c's table added by arith_funcs_design.md §2 (rationals,
# the order of reals, bits, the remaining float functions and `powm/3`), pinned to swipl's own answers.
# Same format as `_A_ARITHA_CASES`: pasted from the oracle (the pin's build, 10.1.18) and re-run through
# swipl by the live testset at the end of this file. Known surprises, pinned like the rest:
# `rational(-0.0)` is the integer 0; `rationalize(0.1)` is 1r10 (continued fractions, `mpq_set_double`)
# where `rational(0.1)` is the exact 3602879701896397r36028797018963968; `cmpr/2`, `maxr/2` and `minr/2`
# compare the mathematical values (`cmpr(1r3, 0.3333333333333333)` is 1) and prefer the rational of two
# equal values (`maxr(1, 1.0)` is the integer 1, `minr(1r2, 0.5)` the rational), a NaN gives the other
# argument in `maxr/2` and `minr/2`, an error in `cmpr/2`; `lcm/2` and `getbit/2` accept big integers
# of any size (a bit past `LONG_MAX` is 0, and `getbit(-5, 2^70)` is 0, not an error, the bit being
# checked before the sign of I); `getbit/2`'s errors are named `bit/2`; `lgamma(X)` for `X =< 0` is
# `float_overflow`; `nexttoward(inf, inf)` is `float_overflow`; `acosh(0.5)` and `atanh(2)` are
# `undefined`, `atanh(1)` is `float_overflow`; `tanh(nan)` is `undefined`; `rdiv/2`'s zero divisor
# is named `(/)/2`, its type error `rdiv/2`.
# NOT in this table: `random_float/0` (not reproducible: its own testset) and `roundtoward/2` (NOT
# PORTED, below). `powm/3` with a float argument is in it since BP2 (upstream 1582e8b37): the error.
const _A_ARITHC_CASES = Any[
    # rational/1
    (:rational, 0), (:rational, 5), (:rational, -3), (:rational, typemin(Int64)),
    (:rational, typemax(Int64)), (:rational, big(2)^70), (:rational, -big(2)^70),
    (:rational, 0.5), (:rational, 0.1), (:rational, -0.0), (:rational, 0.0),
    (:rational, 2.0), (:rational, -2.5), (:rational, 1.0e22),
    (:rational, 9.5367431640625e-7), (:rational, 3.5), (:rational, 3 // big(4)),
    (:rational, -7 // big(4)), (:rational, big(2)^70 // big(3)), (:rational, Inf),
    (:rational, -Inf), (:rational, NaN), (:rational, nothing), (:rational, :a),
    (:rational, (:+, 1, 1 // big(2))), (:+, (:rational, 0.25), (:rational, 0.5)),
    (:rational, (:rational, 0.75)),
    # numerator/1
    (:numerator, 5), (:numerator, 0), (:numerator, -3), (:numerator, big(2)^70),
    (:numerator, typemin(Int64)), (:numerator, 3 // big(4)), (:numerator, -7 // big(4)),
    (:numerator, big(2)^70 // big(3)), (:numerator, 1 // big(2)^70),
    (:numerator, 3 // big(2)), (:numerator, 0.5), (:numerator, 2.0), (:numerator, -0.0),
    (:numerator, Inf), (:numerator, NaN), (:numerator, nothing), (:numerator, :a),
    (:numerator, (:rdiv, 6, 4)), (:numerator, (:rational, 0.1)),
    (:+, (:numerator, 3 // big(4)), 1),
    # denominator/1
    (:denominator, 5), (:denominator, 0), (:denominator, -3), (:denominator, big(2)^70),
    (:denominator, typemin(Int64)), (:denominator, 3 // big(4)),
    (:denominator, -7 // big(4)), (:denominator, big(2)^70 // big(3)),
    (:denominator, 1 // big(2)^70), (:denominator, 3 // big(2)), (:denominator, 0.5),
    (:denominator, 2.0), (:denominator, -0.0), (:denominator, Inf), (:denominator, NaN),
    (:denominator, nothing), (:denominator, :a), (:denominator, (:rdiv, 6, 4)),
    (:denominator, (:rational, 0.1)), (:+, (:denominator, 3 // big(4)), 1),
    # rationalize/1
    (:rationalize, 0.1), (:rationalize, 0.25), (:rationalize, 3.14159),
    (:rationalize, -0.5), (:rationalize, 0.0), (:rationalize, -0.0), (:rationalize, 2.0),
    (:rationalize, -2.0), (:rationalize, 1.0e22), (:rationalize, 1.0e-5),
    (:rationalize, 0.3333333333333333), (:rationalize, 1.0000000000000002),
    (:rationalize, 123456.789), (:rationalize, -1.0e-5),
    (:rationalize, 0.7071067811865476), (:rationalize, Inf), (:rationalize, -Inf),
    (:rationalize, NaN), (:rationalize, 0), (:rationalize, 7), (:rationalize, -7),
    (:rationalize, typemin(Int64)), (:rationalize, big(2)^70),
    (:rationalize, 3 // big(4)), (:rationalize, big(2)^70 // big(3)),
    (:rationalize, nothing), (:rationalize, :a), (:rationalize, (:/, 1, 3.0)),
    (:+, (:rationalize, 0.1), (:rationalize, 0.2)), (:rational, (:rationalize, 0.1)),
    # rdiv/2
    (:rdiv, 1, 3), (:rdiv, 4, 2), (:rdiv, 6, -4), (:rdiv, -6, 4), (:rdiv, 0, 5),
    (:rdiv, 5, 5), (:rdiv, 1, 0), (:rdiv, 0, 0), (:rdiv, -1, 0), (:rdiv, big(2)^70, 0),
    (:rdiv, 3 // big(4), 1 // big(2)), (:rdiv, 1 // big(3), 0), (:rdiv, 1 // big(3), 2),
    (:rdiv, 2, 3 // big(4)), (:rdiv, big(2)^70, 3), (:rdiv, big(2)^70, big(2)^70),
    (:rdiv, -big(2)^70, big(2)^70), (:rdiv, 3, big(2)^70), (:rdiv, typemin(Int64), -1),
    (:rdiv, typemin(Int64), 3), (:rdiv, 1 // big(2), 1 // big(2)),
    (:rdiv, big(2)^70 // big(3), 1 // big(2)^70), (:rdiv, 1 // big(3), -1 // big(3)),
    (:rdiv, 1.5, 2), (:rdiv, 2, 1.5), (:rdiv, 1.5, 1.5), (:rdiv, 1, 0.0), (:rdiv, 0.0, 1),
    (:rdiv, Inf, 1), (:rdiv, 1, NaN), (:rdiv, nothing, 1), (:rdiv, 1, nothing),
    (:rdiv, :a, 1), (:rdiv, 1, :a), (:rdiv, (:+, 1, 2), (:*, 2, 3)),
    (:+, (:rdiv, 1, 3), (:rdiv, 2, 3)),
    # cmpr/2
    (:cmpr, 1, 2), (:cmpr, 2, 1), (:cmpr, 1, 1), (:cmpr, 0, 0), (:cmpr, -1, 1),
    (:cmpr, 1, 1.0), (:cmpr, 1, 2.0), (:cmpr, 2, 1.0), (:cmpr, 1.0, 1), (:cmpr, 1.5, 1),
    (:cmpr, 1, 1.5), (:cmpr, -5, -5.5), (:cmpr, -5.5, -5), (:cmpr, 3 // big(4), 0.75),
    (:cmpr, 0.75, 3 // big(4)), (:cmpr, 1 // big(3), 0.3333333333333333),
    (:cmpr, 0.3333333333333333, 1 // big(3)), (:cmpr, 1 // big(3), 1 // big(2)),
    (:cmpr, 1 // big(2), 1 // big(3)), (:cmpr, 1 // big(3), 1 // big(3)),
    (:cmpr, 9007199254740993, 9007199254740992.0),
    (:cmpr, 9007199254740992.0, 9007199254740993),
    (:cmpr, typemax(Int64), 9.223372036854776e18),
    (:cmpr, typemin(Int64), -9.223372036854776e18),
    (:cmpr, typemax(Int64), 9.223372036854775e18), (:cmpr, -4294967297, -4294967297.0),
    (:cmpr, 4294967297, 4294967297.0), (:cmpr, 1099511627779, 1099511627779.5),
    (:cmpr, -1099511627779, -1099511627779.5), (:cmpr, 4294967296, 4294967296.5),
    (:cmpr, big(2)^70, 1.0e21), (:cmpr, big(2)^70, 1.1805916207174113e21),
    (:cmpr, -big(2)^70, -1.1805916207174113e21), (:cmpr, big(10)^400, 1.0e308),
    (:cmpr, -big(10)^400, -Inf), (:cmpr, big(10)^400, Inf), (:cmpr, Inf, big(10)^400),
    (:cmpr, Inf, Inf), (:cmpr, -Inf, Inf), (:cmpr, Inf, -Inf), (:cmpr, -0.0, 0.0),
    (:cmpr, 0.0, -0.0), (:cmpr, 0.0, 0), (:cmpr, -0.0, 0),
    (:cmpr, big(2)^70, big"1180591620717411303425"),
    (:cmpr, big"1180591620717411303425", big(2)^70), (:cmpr, big(2)^70, big(2)^70),
    (:cmpr, big(2)^70, 5), (:cmpr, 5, big(2)^70), (:cmpr, -big(2)^70, 5),
    (:cmpr, typemin(Int64), typemax(Int64)), (:cmpr, typemax(Int64), typemin(Int64)),
    (:cmpr, typemax(Int64), big(2)^70), (:cmpr, typemin(Int64), -big(2)^70),
    (:cmpr, big(2)^70 // big(3), big(2)^70), (:cmpr, big(2)^70, big(2)^70 // big(3)),
    (:cmpr, big(2)^70 // big(3), 1.0e20), (:cmpr, 1.0e21, big(2)^70 // big(3)),
    (:cmpr, 1 // big(3), 0), (:cmpr, 0, 1 // big(3)), (:cmpr, -1 // big(3), 0),
    (:cmpr, 1 // big(3), -5), (:cmpr, -5, 1 // big(3)), (:cmpr, 7 // big(2), 3),
    (:cmpr, 7 // big(2), 4), (:cmpr, 3, 7 // big(2)), (:cmpr, 7 // big(2), Inf),
    (:cmpr, -Inf, 7 // big(2)), (:cmpr, 7 // big(2), NaN), (:cmpr, NaN, 1),
    (:cmpr, 1, NaN), (:cmpr, NaN, NaN), (:cmpr, NaN, Inf), (:cmpr, NaN, big(2)^70),
    (:cmpr, 1 // big(2), NaN), (:cmpr, nothing, 1), (:cmpr, 1, nothing), (:cmpr, :a, 1),
    (:+, (:cmpr, 1, 2), 10), (:cmpr, (:+, 1, 1), (:*, 1, 2)),
    # maxr/2
    (:maxr, 1, 2), (:maxr, 2, 1), (:maxr, 1, 1), (:maxr, 1, 1.0), (:maxr, 1.0, 1),
    (:maxr, 1.0, 1.0), (:maxr, 1.5, 2), (:maxr, 2, 1.5), (:maxr, -1, -2),
    (:maxr, -0.0, 0.0), (:maxr, 0.0, -0.0), (:maxr, -0.0, -0.0), (:maxr, 0.0, 0.0),
    (:maxr, -0.0, 0), (:maxr, 0, -0.0), (:maxr, 0.0, 0), (:maxr, 0, 0.0), (:maxr, NaN, 1),
    (:maxr, 1, NaN), (:maxr, NaN, NaN), (:maxr, NaN, 1.5), (:maxr, 1.5, NaN),
    (:maxr, NaN, 1 // big(3)), (:maxr, 1 // big(3), NaN), (:maxr, NaN, big(2)^70),
    (:maxr, big(2)^70, NaN), (:maxr, 1 // big(3), 0.3333333333333333),
    (:maxr, 0.3333333333333333, 1 // big(3)), (:maxr, 1 // big(2), 0.5),
    (:maxr, 0.5, 1 // big(2)), (:maxr, 3 // big(2), 1.5), (:maxr, 1.5, 3 // big(2)),
    (:maxr, 1 // big(3), 1 // big(2)), (:maxr, 1 // big(2), 1 // big(3)),
    (:maxr, Inf, big(2)^70), (:maxr, big(2)^70, Inf), (:maxr, -Inf, typemin(Int64)),
    (:maxr, typemin(Int64), -Inf), (:maxr, Inf, Inf), (:maxr, -Inf, Inf),
    (:maxr, big(2)^70, big"1180591620717411303425"), (:maxr, big(2)^70, 1.0e21),
    (:maxr, 1.0e21, big(2)^70), (:maxr, 9007199254740993, 9007199254740992.0),
    (:maxr, 9007199254740992.0, 9007199254740993),
    (:maxr, big(2)^70, big(2)^70 // big(3)), (:maxr, nothing, 1), (:maxr, 1, nothing),
    (:maxr, :a, 1), (:maxr, 1, :a), (:maxr, (:+, 1, 2), (:*, 1, 3)),
    (:+, (:maxr, 1, 2), (:maxr, 3, 4)),
    # minr/2
    (:minr, 1, 2), (:minr, 2, 1), (:minr, 1, 1), (:minr, 1, 1.0), (:minr, 1.0, 1),
    (:minr, 1.0, 1.0), (:minr, 1.5, 2), (:minr, 2, 1.5), (:minr, -1, -2),
    (:minr, -0.0, 0.0), (:minr, 0.0, -0.0), (:minr, -0.0, -0.0), (:minr, 0.0, 0.0),
    (:minr, -0.0, 0), (:minr, 0, -0.0), (:minr, 0.0, 0), (:minr, 0, 0.0), (:minr, NaN, 1),
    (:minr, 1, NaN), (:minr, NaN, NaN), (:minr, NaN, 1.5), (:minr, 1.5, NaN),
    (:minr, NaN, 1 // big(3)), (:minr, 1 // big(3), NaN), (:minr, NaN, big(2)^70),
    (:minr, big(2)^70, NaN), (:minr, 1 // big(3), 0.3333333333333333),
    (:minr, 0.3333333333333333, 1 // big(3)), (:minr, 1 // big(2), 0.5),
    (:minr, 0.5, 1 // big(2)), (:minr, 3 // big(2), 1.5), (:minr, 1.5, 3 // big(2)),
    (:minr, 1 // big(3), 1 // big(2)), (:minr, 1 // big(2), 1 // big(3)),
    (:minr, Inf, big(2)^70), (:minr, big(2)^70, Inf), (:minr, -Inf, typemin(Int64)),
    (:minr, typemin(Int64), -Inf), (:minr, Inf, Inf), (:minr, -Inf, Inf),
    (:minr, big(2)^70, big"1180591620717411303425"), (:minr, big(2)^70, 1.0e21),
    (:minr, 1.0e21, big(2)^70), (:minr, 9007199254740993, 9007199254740992.0),
    (:minr, 9007199254740992.0, 9007199254740993),
    (:minr, big(2)^70, big(2)^70 // big(3)), (:minr, nothing, 1), (:minr, 1, nothing),
    (:minr, :a, 1), (:minr, 1, :a), (:minr, (:+, 1, 2), (:*, 1, 3)),
    (:+, (:minr, 1, 2), (:minr, 3, 4)),
    # lcm/2
    (:lcm, 4, 6), (:lcm, 6, 4), (:lcm, 0, 5), (:lcm, 5, 0), (:lcm, 0, 0), (:lcm, -4, 6),
    (:lcm, 4, -6), (:lcm, -4, -6), (:lcm, 7, 13), (:lcm, 12, 12), (:lcm, 1, 1),
    (:lcm, 1, 0), (:lcm, typemax(Int64), typemax(Int64)), (:lcm, typemax(Int64), 2),
    (:lcm, 2, typemax(Int64)), (:lcm, typemax(Int64), 9223372036854775806),
    (:lcm, typemin(Int64), 1), (:lcm, 1, typemin(Int64)),
    (:lcm, typemin(Int64), typemin(Int64)), (:lcm, typemin(Int64), 2),
    (:lcm, typemin(Int64), -1), (:lcm, 4611686018427387904, 3),
    (:lcm, 4611686018427387904, 4611686018427387904), (:lcm, 3037000500, 3037000500),
    (:lcm, 3037000499, 3037000499), (:lcm, 4294967296, 4294967297), (:lcm, big(2)^70, 6),
    (:lcm, 6, big(2)^70), (:lcm, -big(2)^70, 6), (:lcm, 6, -big(2)^70),
    (:lcm, big(2)^70, 0), (:lcm, 0, big(2)^70), (:lcm, big(2)^70, big(2)^70),
    (:lcm, big(2)^70, big"1180591620717411303425"), (:lcm, big(10)^30, big(10)^20),
    (:lcm, -big(10)^30, big(10)^20), (:lcm, 2.5, 3), (:lcm, 3, 2.5), (:lcm, 2.0, 3),
    (:lcm, 3, 2.0), (:lcm, 1 // big(2), 3), (:lcm, 3, 1 // big(2)), (:lcm, NaN, 3),
    (:lcm, Inf, 3), (:lcm, nothing, 1), (:lcm, 1, nothing), (:lcm, :a, 1), (:lcm, 1, :a),
    (:+, (:lcm, 4, 6), (:gcd, 4, 6)), (:lcm, (:+, 2, 2), (:*, 2, 3)),
    # nexttoward/2
    (:nexttoward, 1.0, 2), (:nexttoward, 1.0, 0), (:nexttoward, 1.0, 2.0),
    (:nexttoward, 1.0, 0.5), (:nexttoward, 1, 2), (:nexttoward, 1, 0),
    (:nexttoward, 1, 1), (:nexttoward, 1.0, 1.0), (:nexttoward, 0.0, 1),
    (:nexttoward, 0.0, -1), (:nexttoward, -0.0, 1), (:nexttoward, -0.0, -1),
    (:nexttoward, 0.0, 0.0), (:nexttoward, -0.0, 0.0), (:nexttoward, 0.0, -0.0),
    (:nexttoward, 5.0e-324, 0), (:nexttoward, 5.0e-324, 1), (:nexttoward, -5.0e-324, 0),
    (:nexttoward, -5.0e-324, -1), (:nexttoward, 2.2250738585072014e-308, 0),
    (:nexttoward, 2.2250738585072014e-308, 1), (:nexttoward, 1.7976931348623157e308, 0),
    (:nexttoward, 1.7976931348623157e308, Inf),
    (:nexttoward, 1.7976931348623157e308, 1.7976931348623157e308),
    (:nexttoward, -1.7976931348623157e308, -Inf), (:nexttoward, Inf, 0),
    (:nexttoward, -Inf, 0), (:nexttoward, Inf, Inf), (:nexttoward, -Inf, -Inf),
    (:nexttoward, Inf, -Inf), (:nexttoward, NaN, 1), (:nexttoward, 1, NaN),
    (:nexttoward, NaN, NaN), (:nexttoward, big(2)^70, Inf), (:nexttoward, big(2)^70, 0),
    (:nexttoward, 1 // big(3), 1), (:nexttoward, 1 // big(3), 0),
    (:nexttoward, 1, 1 // big(3)), (:nexttoward, 0.1, 0.2), (:nexttoward, 0.2, 0.1),
    (:nexttoward, -1.0, 0), (:nexttoward, -1.0, -2), (:nexttoward, 2.0, 3),
    (:nexttoward, 1.0e300, Inf), (:nexttoward, nothing, 1), (:nexttoward, 1, nothing),
    (:nexttoward, :a, 1), (:nexttoward, 1, :a), (:nexttoward, big(10)^400, 1),
    (:nexttoward, 1, big(10)^400), (:-, (:nexttoward, 1, 2), 1),
    (:nexttoward, (:+, 0.5, 0.5), (:*, 2, 2)),
    # sinh/1
    (:sinh, 0), (:sinh, 1), (:sinh, -1), (:sinh, 5), (:sinh, 0.5), (:sinh, -0.5),
    (:sinh, 2.5), (:sinh, -0.0), (:sinh, 1.0e-320), (:sinh, 710.0), (:sinh, -710.0),
    (:sinh, 1.0e300), (:sinh, typemin(Int64)), (:sinh, big(2)^70), (:sinh, big(10)^30),
    (:sinh, 1 // big(3)), (:sinh, Inf), (:sinh, -Inf), (:sinh, NaN), (:sinh, nothing),
    (:sinh, :a), (:sinh, (:+, 0.25, 0.25)), (:+, (:sinh, 0.5), (:sinh, 0.25)),
    # cosh/1
    (:cosh, 0), (:cosh, 1), (:cosh, -1), (:cosh, 5), (:cosh, 0.5), (:cosh, -0.5),
    (:cosh, 2.5), (:cosh, -0.0), (:cosh, 1.0e-320), (:cosh, 710.0), (:cosh, -710.0),
    (:cosh, 1.0e300), (:cosh, typemin(Int64)), (:cosh, big(2)^70), (:cosh, big(10)^30),
    (:cosh, 1 // big(3)), (:cosh, Inf), (:cosh, -Inf), (:cosh, NaN), (:cosh, nothing),
    (:cosh, :a), (:cosh, (:+, 0.25, 0.25)), (:+, (:cosh, 0.5), (:cosh, 0.25)),
    # tanh/1
    (:tanh, 0), (:tanh, 1), (:tanh, -1), (:tanh, 5), (:tanh, 0.5), (:tanh, -0.5),
    (:tanh, 2.5), (:tanh, -0.0), (:tanh, 1.0e-320), (:tanh, 710.0), (:tanh, -710.0),
    (:tanh, 1.0e300), (:tanh, typemin(Int64)), (:tanh, big(2)^70), (:tanh, big(10)^30),
    (:tanh, 1 // big(3)), (:tanh, Inf), (:tanh, -Inf), (:tanh, NaN), (:tanh, nothing),
    (:tanh, :a), (:tanh, 1000), (:tanh, -1000), (:tanh, 0.1), (:tanh, (:+, 0.25, 0.25)),
    (:+, (:tanh, 0.5), (:tanh, 0.25)),
    # asinh/1
    (:asinh, 0), (:asinh, 1), (:asinh, -1), (:asinh, 5), (:asinh, 0.5), (:asinh, -0.5),
    (:asinh, 2.5), (:asinh, -0.0), (:asinh, 1.0e-320), (:asinh, 710.0), (:asinh, -710.0),
    (:asinh, 1.0e300), (:asinh, typemin(Int64)), (:asinh, big(2)^70),
    (:asinh, big(10)^30), (:asinh, 1 // big(3)), (:asinh, Inf), (:asinh, -Inf),
    (:asinh, NaN), (:asinh, nothing), (:asinh, :a), (:asinh, -1.0e300), (:asinh, 1.0e-10),
    (:asinh, (:+, 0.25, 0.25)), (:+, (:asinh, 0.5), (:asinh, 0.25)),
    # acosh/1
    (:acosh, 0), (:acosh, 1), (:acosh, -1), (:acosh, 5), (:acosh, 0.5), (:acosh, -0.5),
    (:acosh, 2.5), (:acosh, -0.0), (:acosh, 1.0e-320), (:acosh, 710.0), (:acosh, -710.0),
    (:acosh, 1.0e300), (:acosh, typemin(Int64)), (:acosh, big(2)^70),
    (:acosh, big(10)^30), (:acosh, 1 // big(3)), (:acosh, Inf), (:acosh, -Inf),
    (:acosh, NaN), (:acosh, nothing), (:acosh, :a), (:acosh, 1.0), (:acosh, 1.5),
    (:acosh, (:+, 0.25, 0.25)), (:+, (:acosh, 0.5), (:acosh, 0.25)),
    # atanh/1
    (:atanh, 0), (:atanh, 1), (:atanh, -1), (:atanh, 5), (:atanh, 0.5), (:atanh, -0.5),
    (:atanh, 2.5), (:atanh, -0.0), (:atanh, 1.0e-320), (:atanh, 710.0), (:atanh, -710.0),
    (:atanh, 1.0e300), (:atanh, typemin(Int64)), (:atanh, big(2)^70),
    (:atanh, big(10)^30), (:atanh, 1 // big(3)), (:atanh, Inf), (:atanh, -Inf),
    (:atanh, NaN), (:atanh, nothing), (:atanh, :a), (:atanh, 0.9999999999999999),
    (:atanh, 2), (:atanh, -2), (:atanh, 1.0), (:atanh, -1.0), (:atanh, 1 // big(2)),
    (:atanh, 3 // big(2)), (:atanh, (:+, 0.25, 0.25)),
    (:+, (:atanh, 0.5), (:atanh, 0.25)),
    # lgamma/1
    (:lgamma, 0), (:lgamma, 1), (:lgamma, 2), (:lgamma, 3), (:lgamma, 5), (:lgamma, 100),
    (:lgamma, 171), (:lgamma, 0.5), (:lgamma, 1.5), (:lgamma, 2.5), (:lgamma, -0.5),
    (:lgamma, -1.5), (:lgamma, -1), (:lgamma, -2), (:lgamma, -1.0), (:lgamma, 0.0),
    (:lgamma, -0.0), (:lgamma, 1.0e-300), (:lgamma, 5.0e-324), (:lgamma, 10000000000.0),
    (:lgamma, 1.0e300), (:lgamma, 1.0e305), (:lgamma, 1.0e308),
    (:lgamma, 1.7976931348623157e308), (:lgamma, big(2)^70), (:lgamma, big(10)^30),
    (:lgamma, big(10)^400), (:lgamma, -big(2)^70), (:lgamma, 1 // big(2)),
    (:lgamma, -3 // big(2)), (:lgamma, big(2)^70 // big(3)), (:lgamma, Inf),
    (:lgamma, -Inf), (:lgamma, NaN), (:lgamma, nothing), (:lgamma, :a),
    (:lgamma, typemin(Int64)), (:lgamma, typemax(Int64)), (:lgamma, 3.5), (:lgamma, -2.5),
    (:lgamma, (:+, 1, 2)), (:+, (:lgamma, 3), (:lgamma, 4)),
    # erf/1
    (:erf, 0), (:erf, 1), (:erf, -1), (:erf, 5), (:erf, 0.5), (:erf, -0.5), (:erf, 2.5),
    (:erf, -0.0), (:erf, 1.0e-320), (:erf, 710.0), (:erf, -710.0), (:erf, 1.0e300),
    (:erf, typemin(Int64)), (:erf, big(2)^70), (:erf, big(10)^30), (:erf, 1 // big(3)),
    (:erf, Inf), (:erf, -Inf), (:erf, NaN), (:erf, nothing), (:erf, :a), (:erf, 3.0),
    (:erf, 6.0), (:erf, (:+, 0.25, 0.25)), (:+, (:erf, 0.5), (:erf, 0.25)),
    # erfc/1
    (:erfc, 0), (:erfc, 1), (:erfc, -1), (:erfc, 5), (:erfc, 0.5), (:erfc, -0.5),
    (:erfc, 2.5), (:erfc, -0.0), (:erfc, 1.0e-320), (:erfc, 710.0), (:erfc, -710.0),
    (:erfc, 1.0e300), (:erfc, typemin(Int64)), (:erfc, big(2)^70), (:erfc, big(10)^30),
    (:erfc, 1 // big(3)), (:erfc, Inf), (:erfc, -Inf), (:erfc, NaN), (:erfc, nothing),
    (:erfc, :a), (:erfc, 3.0), (:erfc, 6.0), (:erfc, 26.0), (:erfc, 27.0), (:erfc, 26.55),
    (:erfc, 30.0), (:erfc, -30.0), (:erfc, (:+, 0.25, 0.25)),
    # D-0040: where `1 - erf` and the C library's erfc differ (erfc(10.0): 0.0 against 2.09e-45) — swipl's 0.0
    (:erfc, 4.0), (:erfc, 10.0),
    (:+, (:erfc, 0.5), (:erfc, 0.25)),
    # log10/1
    (:log10, 1), (:log10, 10), (:log10, 100), (:log10, 1000), (:log10, 2), (:log10, 5),
    (:log10, 0), (:log10, -1), (:log10, 0.001), (:log10, 0.5), (:log10, 1.0e300),
    (:log10, 1.0e-300), (:log10, 5.0e-324), (:log10, 1.0e-320), (:log10, 0.0),
    (:log10, -0.0), (:log10, -0.5), (:log10, 1.0), (:log10, 10.0), (:log10, 1.0e22),
    (:log10, 3.0), (:log10, typemax(Int64)), (:log10, typemin(Int64)),
    (:log10, big(2)^70), (:log10, big(10)^30), (:log10, big(10)^400),
    (:log10, big(10)^308), (:log10, -big(2)^70), (:log10, 1 // big(2)),
    (:log10, 1 // big(3)), (:log10, big(2)^70 // big(3)), (:log10, Inf), (:log10, -Inf),
    (:log10, NaN), (:log10, nothing), (:log10, :a), (:log10, (:*, 10, 10)),
    (:+, (:log10, 100), (:log10, 1000)), (:floor, (:log10, 999)),
    # constants
    :epsilon, (:epsilon,), :inf, (:inf,), :nan, (:nan,), (:+, :epsilon, 1), (:-, :inf),
    (:-, :nan), (:max, :inf, 1), (:min, :inf, 1), (:max, :nan, 1), (:min, 1, :nan),
    (:+, :inf, 1), (:+, :nan, 1), (:+, 1, (:*, 2, :epsilon)), (:*, :epsilon, :epsilon),
    (:float, :inf), (:sign, :inf), (:sign, (:-, :inf)), (:abs, (:-, :inf)),
    (:integer, :inf), (:integer, :nan), (:truncate, :inf), (:floor, :nan),
    (:cmpr, :inf, big(2)^70), (:cmpr, 1, :nan), (:maxr, :nan, 2), (:minr, :inf, 3),
    (:epsilon, 1), (:inf, 1), (:nan, 1, 2), (:inf, 1, 2), (:copysign, :inf, -1),
    (:copysign, 1, (:-, :inf)), (:nexttoward, :inf, 0), (:+, 1.0, 0.0),
    # lsb/1
    (:lsb, 1), (:lsb, 2), (:lsb, 3), (:lsb, 4), (:lsb, 12), (:lsb, 255), (:lsb, 256),
    (:lsb, 2147483648), (:lsb, 4294967296), (:lsb, 6442450944), (:lsb, 1099511627776),
    (:lsb, 4611686018427387904), (:lsb, typemax(Int64)), (:lsb, 6917529027641081856),
    (:lsb, big(2)^64), (:lsb, big(2)^70), (:lsb, big"3802951800684688204490109616128"),
    (:lsb, big"1199038364791120855040"), (:lsb, big(2)^200),
    (:lsb, big"1606938044258990275541962092342430253122431223184289538506752"),
    (:lsb, big(10)^30), (:lsb, 0), (:lsb, -1), (:lsb, -2), (:lsb, typemin(Int64)),
    (:lsb, -big(2)^70), (:lsb, 0.0), (:lsb, 2.0), (:lsb, 2.5), (:lsb, 1 // big(2)),
    (:lsb, 8 // big(3)), (:lsb, NaN), (:lsb, Inf), (:lsb, nothing), (:lsb, :a),
    (:lsb, (:*, 3, 8)), (:+, (:lsb, 8), (:msb, 8)),
    # popcount/1
    (:popcount, 0), (:popcount, 1), (:popcount, 2), (:popcount, 3), (:popcount, 7),
    (:popcount, 8), (:popcount, 255), (:popcount, 256), (:popcount, 1023),
    (:popcount, 4294967296), (:popcount, 4294967295), (:popcount, 4611686018427387904),
    (:popcount, typemax(Int64)), (:popcount, big"18446744073709551615"),
    (:popcount, big(2)^64), (:popcount, big"1180591620717411303423"),
    (:popcount, big(2)^70), (:popcount, big"1199038364791120855040"),
    (:popcount, big(10)^30),
    (:popcount, big"1606938044258990275541962092341162602522202993782792835301375"),
    (:popcount, -1), (:popcount, -2), (:popcount, typemin(Int64)),
    (:popcount, -big(2)^70), (:popcount, 0.0), (:popcount, 2.0), (:popcount, 2.5),
    (:popcount, 1 // big(2)), (:popcount, 3 // big(4)), (:popcount, NaN),
    (:popcount, Inf), (:popcount, nothing), (:popcount, :a),
    (:popcount, (:-, (:<<, 1, 10), 1)), (:+, (:popcount, 255), (:popcount, 3)),
    # getbit/2
    (:getbit, 5, 0), (:getbit, 5, 1), (:getbit, 5, 2), (:getbit, 5, 3), (:getbit, 0, 0),
    (:getbit, 1, 0), (:getbit, 1, 1), (:getbit, typemax(Int64), 0),
    (:getbit, typemax(Int64), 62), (:getbit, typemax(Int64), 63),
    (:getbit, typemax(Int64), 64), (:getbit, 5, 63), (:getbit, 5, 64), (:getbit, 5, 65),
    (:getbit, 5, 1000), (:getbit, 5, 1000000), (:getbit, 5, big(2)^70),
    (:getbit, 5, big(2)^63), (:getbit, 5, typemax(Int64)),
    (:getbit, 5, 9223372036854775806), (:getbit, big(2)^70, 70), (:getbit, big(2)^70, 69),
    (:getbit, big(2)^70, 71), (:getbit, big(2)^70, 0), (:getbit, big(2)^70, 1000000),
    (:getbit, big(2)^70, typemax(Int64)), (:getbit, big(2)^70, big(2)^63),
    (:getbit, big(2)^70, big(2)^70), (:getbit, big"1180591620717411303425", 0),
    (:getbit, big"1180591620717411303425", 1), (:getbit, big"18446744073709551615", 63),
    (:getbit, big"18446744073709551615", 64), (:getbit, big(2)^64, 64),
    (:getbit, big(2)^64, 63), (:getbit, big(10)^30, 0), (:getbit, big(10)^30, 30),
    (:getbit, -1, 0), (:getbit, -big(2)^70, 0), (:getbit, 5, -1),
    (:getbit, 5, -big(2)^70), (:getbit, -1, -1), (:getbit, -big(2)^70, -1),
    (:getbit, -5, big(2)^70), (:getbit, 2.5, 1), (:getbit, 5, 1.5), (:getbit, 2.0, 1),
    (:getbit, 5, 1.0), (:getbit, 1 // big(2), 1), (:getbit, 5, 1 // big(2)),
    (:getbit, NaN, 1), (:getbit, 1, NaN), (:getbit, nothing, 1), (:getbit, 1, nothing),
    (:getbit, :a, 1), (:getbit, 1, :a), (:getbit, nothing, nothing),
    (:getbit, (:+, 2, 3), (:-, 3, 1)), (:+, (:getbit, 5, 0), (:getbit, 5, 1)),
    # powm/3
    (:powm, 2, 10, 1000), (:powm, 2, 10, 1024), (:powm, 2, 10, 1025), (:powm, 2, 0, 5),
    (:powm, 0, 0, 5), (:powm, 0, 0, 1), (:powm, 0, 5, 7), (:powm, 3, 100, 1),
    (:powm, 3, 100, 2), (:powm, 2, 3, 5), (:powm, 5, 3, 7), (:powm, 2, 100, 1000000007),
    (:powm, 2, 100, 2305843009213693951), (:powm, 123456789, 987654321, 1000000007),
    (:powm, typemax(Int64), typemax(Int64), typemax(Int64)),
    (:powm, typemax(Int64), 2, typemax(Int64)),
    (:powm, typemax(Int64), 2, 4611686018427387904), (:powm, big(2)^70, 3, 1000),
    (:powm, big(2)^70, big(2)^70, 97), (:powm, 2, big(2)^70, 97),
    (:powm, 2, 3, big"1180591620717411303425"),
    (:powm, big(2)^70, 3, big"1180591620717411303425"),
    (:powm, big(10)^30, big(10)^30, 1000000007), (:powm, 2, 3, big(2)^63),
    (:powm, 2, 3, big(2)^64), (:powm, -2, 3, 5), (:powm, 2, -3, 5), (:powm, 2, 3, 0),
    (:powm, 2, 3, -5), (:powm, -2, -3, 0), (:powm, -big(2)^70, 3, 5),
    (:powm, 2, -big(2)^70, 5), (:powm, 2, 3, -big(2)^70), (:powm, 0, 0, 0),
    (:powm, -1, 0, 1), (:powm, 1, -1, 1), (:powm, 2, 3, -1), (:powm, nothing, 3, 5),
    (:powm, 2, nothing, 5), (:powm, 2, 3, nothing), (:powm, :a, 3, 5), (:powm, 2, :a, 5),
    (:powm, 2, 3, :a), (:powm, nothing, nothing, nothing),
    # a float argument: type_error(integer, F) at powm/3 (upstream 1582e8b37, BP2: ar_powm returns the error)
    (:powm, 2.0, 3, 5), (:powm, 2, 3.0, 5), (:powm, 2, 3, 5.0),
    (:powm, (:+, 1, 1), (:*, 5, 2), (:+, 500, 500)), (:+, (:powm, 2, 10, 1000), 1),
    # eval/1
    (:eval, 1), (:eval, 0), (:eval, -1), (:eval, typemin(Int64)), (:eval, big(2)^70),
    (:eval, 1.5), (:eval, -0.0), (:eval, Inf), (:eval, NaN), (:eval, 1 // big(3)),
    (:eval, nothing), (:eval, :a), (:eval, (:+, 1, 2)), (:eval, (:eval, 3)),
    (:+, (:eval, 1), 2), (:eval, (:max, 1, 2.0)), (:eval, (:/, 1, 3)),
    (:eval, (:rdiv, 1, 3)), (:eval, :pi), (:eval, :inf), (:eval, (:foo, 1)),
    (:eval, 1, 2), (:eval, :foo), (:eval, (:rational, 0.5)),
    # nested
    (:+, (:lcm, 4, 6), (:powm, 2, 10, 1000)), (:denominator, (:rationalize, 0.25)),
    (:maxr, (:rationalize, 0.1), 0.1), (:minr, (:rationalize, 0.1), 0.1),
    (:cmpr, (:rational, 0.1), 0.1), (:cmpr, (:rationalize, 0.1), 0.1),
    (:lsb, (:lcm, 6, 10)), (:popcount, (:lcm, 6, 10)), (:getbit, (:lcm, 4, 6), (:lsb, 8)),
    (:sinh, (:log10, 1)), (:erf, (:tanh, 0)), (:rational, (:sinh, 0)),
    (:log10, (:powm, 2, 10, 1000)), (:lgamma, (:lcm, 2, 3)),
    (:rdiv, (:+, (:rational, 0.5), (:rational, 0.5)), 3),
    (:numerator, (:+, (:rational, 0.5), (:rational, 0.5))),
    (:denominator, (:+, (:rational, 0.5), (:rational, 0.5))), (:*, 2, (:rdiv, 1, 3)),
    (:+, (:rdiv, 1, 3), 0.5), (:rdiv, (:rdiv, 1, 2), (:rdiv, 1, 3)),
    (:abs, (:rdiv, -1, 3))
]

const _A_ARITHC_EXPECT = String[
    "ok:i0",  # rational(0)
    "ok:i5",  # rational(5)
    "ok:i-3",  # rational(-3)
    "ok:i-9223372036854775808",  # rational(INT64_MIN)
    "ok:i9223372036854775807",  # rational(INT64_MAX)
    "ok:i1180591620717411303424",  # rational(2^70)
    "ok:i-1180591620717411303424",  # rational(-2^70)
    "ok:q1r2",  # rational(0.5)
    "ok:q3602879701896397r36028797018963968",  # rational(0.1)
    "ok:i0",  # rational(-0.0)
    "ok:i0",  # rational(0.0)
    "ok:i2",  # rational(2.0)
    "ok:q-5r2",  # rational(-2.5)
    "ok:i10000000000000000000000",  # rational(1.0e22)
    "ok:q1r1048576",  # rational(9.5367431640625e-7)
    "ok:q7r2",  # rational(3.5)
    "ok:q3r4",  # rational(3r4)
    "ok:q-7r4",  # rational(-7r4)
    "ok:q1180591620717411303424r3",  # rational(2^70r3)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[114, 97, 116, 105, 111, 110, 97, 108, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # rational(1.0Inf)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[114, 97, 116, 105, 111, 110, 97, 108, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # rational(-1.0Inf)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # rational(1.5NaN)
    "err:a[105, 110, 115, 116, 97, 110, 116, 105, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # rational(_)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[101, 118, 97, 108, 117, 97, 98, 108, 101],ca[47]/2(a[97],i0))@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # rational(a)
    "ok:q3r2",  # rational(+(1,1r2))
    "ok:q3r4",  # +(rational(0.25),rational(0.5))
    "ok:q3r4",  # rational(rational(0.75))
    "ok:i5",  # numerator(5)
    "ok:i0",  # numerator(0)
    "ok:i-3",  # numerator(-3)
    "ok:i1180591620717411303424",  # numerator(2^70)
    "ok:i-9223372036854775808",  # numerator(INT64_MIN)
    "ok:i3",  # numerator(3r4)
    "ok:i-7",  # numerator(-7r4)
    "ok:i1180591620717411303424",  # numerator(2^70r3)
    "ok:i1",  # numerator(1r2^70)
    "ok:i3",  # numerator(3r2)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[114, 97, 116, 105, 111, 110, 97, 108],F3fe0000000000000)@ca[47]/2(a[110, 117, 109, 101, 114, 97, 116, 111, 114],i1)@_",  # numerator(0.5)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[114, 97, 116, 105, 111, 110, 97, 108],F4000000000000000)@ca[47]/2(a[110, 117, 109, 101, 114, 97, 116, 111, 114],i1)@_",  # numerator(2.0)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[114, 97, 116, 105, 111, 110, 97, 108],F8000000000000000)@ca[47]/2(a[110, 117, 109, 101, 114, 97, 116, 111, 114],i1)@_",  # numerator(-0.0)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[114, 97, 116, 105, 111, 110, 97, 108],F7ff0000000000000)@ca[47]/2(a[110, 117, 109, 101, 114, 97, 116, 111, 114],i1)@_",  # numerator(1.0Inf)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[114, 97, 116, 105, 111, 110, 97, 108],F7ff8000000000000)@ca[47]/2(a[110, 117, 109, 101, 114, 97, 116, 111, 114],i1)@_",  # numerator(1.5NaN)
    "err:a[105, 110, 115, 116, 97, 110, 116, 105, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # numerator(_)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[101, 118, 97, 108, 117, 97, 98, 108, 101],ca[47]/2(a[97],i0))@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # numerator(a)
    "ok:i3",  # numerator(rdiv(6,4))
    "ok:i3602879701896397",  # numerator(rational(0.1))
    "ok:i4",  # +(numerator(3r4),1)
    "ok:i1",  # denominator(5)
    "ok:i1",  # denominator(0)
    "ok:i1",  # denominator(-3)
    "ok:i1",  # denominator(2^70)
    "ok:i1",  # denominator(INT64_MIN)
    "ok:i4",  # denominator(3r4)
    "ok:i4",  # denominator(-7r4)
    "ok:i3",  # denominator(2^70r3)
    "ok:i1180591620717411303424",  # denominator(1r2^70)
    "ok:i2",  # denominator(3r2)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[114, 97, 116, 105, 111, 110, 97, 108],F3fe0000000000000)@ca[47]/2(a[100, 101, 110, 111, 109, 105, 110, 97, 116, 111, 114],i1)@_",  # denominator(0.5)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[114, 97, 116, 105, 111, 110, 97, 108],F4000000000000000)@ca[47]/2(a[100, 101, 110, 111, 109, 105, 110, 97, 116, 111, 114],i1)@_",  # denominator(2.0)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[114, 97, 116, 105, 111, 110, 97, 108],F8000000000000000)@ca[47]/2(a[100, 101, 110, 111, 109, 105, 110, 97, 116, 111, 114],i1)@_",  # denominator(-0.0)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[114, 97, 116, 105, 111, 110, 97, 108],F7ff0000000000000)@ca[47]/2(a[100, 101, 110, 111, 109, 105, 110, 97, 116, 111, 114],i1)@_",  # denominator(1.0Inf)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[114, 97, 116, 105, 111, 110, 97, 108],F7ff8000000000000)@ca[47]/2(a[100, 101, 110, 111, 109, 105, 110, 97, 116, 111, 114],i1)@_",  # denominator(1.5NaN)
    "err:a[105, 110, 115, 116, 97, 110, 116, 105, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # denominator(_)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[101, 118, 97, 108, 117, 97, 98, 108, 101],ca[47]/2(a[97],i0))@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # denominator(a)
    "ok:i2",  # denominator(rdiv(6,4))
    "ok:i36028797018963968",  # denominator(rational(0.1))
    "ok:i5",  # +(denominator(3r4),1)
    "ok:q1r10",  # rationalize(0.1)
    "ok:q1r4",  # rationalize(0.25)
    "ok:q314159r100000",  # rationalize(3.14159)
    "ok:q-1r2",  # rationalize(-0.5)
    "ok:i0",  # rationalize(0.0)
    "ok:i0",  # rationalize(-0.0)
    "ok:i2",  # rationalize(2.0)
    "ok:i-2",  # rationalize(-2.0)
    "ok:i10000000000000000000000",  # rationalize(1.0e22)
    "ok:q1r100000",  # rationalize(1.0e-5)
    "ok:q1r3",  # rationalize(0.3333333333333333)
    "ok:q4503599627370497r4503599627370496",  # rationalize(1.0000000000000002)
    "ok:q123456789r1000",  # rationalize(123456.789)
    "ok:q-1r100000",  # rationalize(-1.0e-5)
    "ok:q170450288r241053109",  # rationalize(0.7071067811865476)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[114, 97, 116, 105, 111, 110, 97, 108, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # rationalize(1.0Inf)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[114, 97, 116, 105, 111, 110, 97, 108, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # rationalize(-1.0Inf)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # rationalize(1.5NaN)
    "ok:i0",  # rationalize(0)
    "ok:i7",  # rationalize(7)
    "ok:i-7",  # rationalize(-7)
    "ok:i-9223372036854775808",  # rationalize(INT64_MIN)
    "ok:i1180591620717411303424",  # rationalize(2^70)
    "ok:q3r4",  # rationalize(3r4)
    "ok:q1180591620717411303424r3",  # rationalize(2^70r3)
    "err:a[105, 110, 115, 116, 97, 110, 116, 105, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # rationalize(_)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[101, 118, 97, 108, 117, 97, 98, 108, 101],ca[47]/2(a[97],i0))@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # rationalize(a)
    "ok:q1r3",  # rationalize(/(1,3.0))
    "ok:q3r10",  # +(rationalize(0.1),rationalize(0.2))
    "ok:q1r10",  # rational(rationalize(0.1))
    "ok:q1r3",  # rdiv(1,3)
    "ok:i2",  # rdiv(4,2)
    "ok:q-3r2",  # rdiv(6,-4)
    "ok:q-3r2",  # rdiv(-6,4)
    "ok:i0",  # rdiv(0,5)
    "ok:i1",  # rdiv(5,5)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[122, 101, 114, 111, 95, 100, 105, 118, 105, 115, 111, 114])@ca[47]/2(a[47],i2)@_",  # rdiv(1,0)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[122, 101, 114, 111, 95, 100, 105, 118, 105, 115, 111, 114])@ca[47]/2(a[47],i2)@_",  # rdiv(0,0)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[122, 101, 114, 111, 95, 100, 105, 118, 105, 115, 111, 114])@ca[47]/2(a[47],i2)@_",  # rdiv(-1,0)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[122, 101, 114, 111, 95, 100, 105, 118, 105, 115, 111, 114])@ca[47]/2(a[47],i2)@_",  # rdiv(2^70,0)
    "ok:q3r2",  # rdiv(3r4,1r2)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[122, 101, 114, 111, 95, 100, 105, 118, 105, 115, 111, 114])@ca[47]/2(a[47],i2)@_",  # rdiv(1r3,0)
    "ok:q1r6",  # rdiv(1r3,2)
    "ok:q8r3",  # rdiv(2,3r4)
    "ok:q1180591620717411303424r3",  # rdiv(2^70,3)
    "ok:i1",  # rdiv(2^70,2^70)
    "ok:i-1",  # rdiv(-2^70,2^70)
    "ok:q3r1180591620717411303424",  # rdiv(3,2^70)
    "ok:i9223372036854775808",  # rdiv(INT64_MIN,-1)
    "ok:q-9223372036854775808r3",  # rdiv(INT64_MIN,3)
    "ok:i1",  # rdiv(1r2,1r2)
    "ok:q1393796574908163946345982392040522594123776r3",  # rdiv(2^70r3,1r2^70)
    "ok:i-1",  # rdiv(1r3,-1r3)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[114, 97, 116, 105, 111, 110, 97, 108],F3ff8000000000000)@ca[47]/2(a[114, 100, 105, 118],i2)@_",  # rdiv(1.5,2)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[114, 97, 116, 105, 111, 110, 97, 108],F3ff8000000000000)@ca[47]/2(a[114, 100, 105, 118],i2)@_",  # rdiv(2,1.5)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[114, 97, 116, 105, 111, 110, 97, 108],F3ff8000000000000)@ca[47]/2(a[114, 100, 105, 118],i2)@_",  # rdiv(1.5,1.5)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[114, 97, 116, 105, 111, 110, 97, 108],F0)@ca[47]/2(a[114, 100, 105, 118],i2)@_",  # rdiv(1,0.0)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[114, 97, 116, 105, 111, 110, 97, 108],F0)@ca[47]/2(a[114, 100, 105, 118],i2)@_",  # rdiv(0.0,1)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # rdiv(1.0Inf,1)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # rdiv(1,1.5NaN)
    "err:a[105, 110, 115, 116, 97, 110, 116, 105, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # rdiv(_,1)
    "err:a[105, 110, 115, 116, 97, 110, 116, 105, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # rdiv(1,_)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[101, 118, 97, 108, 117, 97, 98, 108, 101],ca[47]/2(a[97],i0))@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # rdiv(a,1)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[101, 118, 97, 108, 117, 97, 98, 108, 101],ca[47]/2(a[97],i0))@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # rdiv(1,a)
    "ok:q1r2",  # rdiv(+(1,2),*(2,3))
    "ok:i1",  # +(rdiv(1,3),rdiv(2,3))
    "ok:i-1",  # cmpr(1,2)
    "ok:i1",  # cmpr(2,1)
    "ok:i0",  # cmpr(1,1)
    "ok:i0",  # cmpr(0,0)
    "ok:i-1",  # cmpr(-1,1)
    "ok:i0",  # cmpr(1,1.0)
    "ok:i-1",  # cmpr(1,2.0)
    "ok:i1",  # cmpr(2,1.0)
    "ok:i0",  # cmpr(1.0,1)
    "ok:i1",  # cmpr(1.5,1)
    "ok:i-1",  # cmpr(1,1.5)
    "ok:i1",  # cmpr(-5,-5.5)
    "ok:i-1",  # cmpr(-5.5,-5)
    "ok:i0",  # cmpr(3r4,0.75)
    "ok:i0",  # cmpr(0.75,3r4)
    "ok:i1",  # cmpr(1r3,0.3333333333333333)
    "ok:i-1",  # cmpr(0.3333333333333333,1r3)
    "ok:i-1",  # cmpr(1r3,1r2)
    "ok:i1",  # cmpr(1r2,1r3)
    "ok:i0",  # cmpr(1r3,1r3)
    "ok:i1",  # cmpr(9007199254740993,9007199254740992.0)
    "ok:i-1",  # cmpr(9007199254740992.0,9007199254740993)
    "ok:i-1",  # cmpr(INT64_MAX,9.223372036854776e18)
    "ok:i0",  # cmpr(INT64_MIN,-9.223372036854776e18)
    "ok:i1",  # cmpr(INT64_MAX,9.223372036854775e18)
    "ok:i0",  # cmpr(-4294967297,-4294967297.0)
    "ok:i0",  # cmpr(4294967297,4294967297.0)
    "ok:i-1",  # cmpr(1099511627779,1099511627779.5)
    "ok:i1",  # cmpr(-1099511627779,-1099511627779.5)
    "ok:i-1",  # cmpr(4294967296,4294967296.5)
    "ok:i1",  # cmpr(2^70,1.0e21)
    "ok:i0",  # cmpr(2^70,1.1805916207174113e21)
    "ok:i0",  # cmpr(-2^70,-1.1805916207174113e21)
    "ok:i1",  # cmpr(10^400,1.0e308)
    "ok:i1",  # cmpr(-10^400,-1.0Inf)
    "ok:i-1",  # cmpr(10^400,1.0Inf)
    "ok:i1",  # cmpr(1.0Inf,10^400)
    "ok:i0",  # cmpr(1.0Inf,1.0Inf)
    "ok:i-1",  # cmpr(-1.0Inf,1.0Inf)
    "ok:i1",  # cmpr(1.0Inf,-1.0Inf)
    "ok:i0",  # cmpr(-0.0,0.0)
    "ok:i0",  # cmpr(0.0,-0.0)
    "ok:i0",  # cmpr(0.0,0)
    "ok:i0",  # cmpr(-0.0,0)
    "ok:i-1",  # cmpr(2^70,1180591620717411303425)
    "ok:i1",  # cmpr(1180591620717411303425,2^70)
    "ok:i0",  # cmpr(2^70,2^70)
    "ok:i1",  # cmpr(2^70,5)
    "ok:i-1",  # cmpr(5,2^70)
    "ok:i-1",  # cmpr(-2^70,5)
    "ok:i-1",  # cmpr(INT64_MIN,INT64_MAX)
    "ok:i1",  # cmpr(INT64_MAX,INT64_MIN)
    "ok:i-1",  # cmpr(INT64_MAX,2^70)
    "ok:i1",  # cmpr(INT64_MIN,-2^70)
    "ok:i-1",  # cmpr(2^70r3,2^70)
    "ok:i1",  # cmpr(2^70,2^70r3)
    "ok:i1",  # cmpr(2^70r3,1.0e20)
    "ok:i1",  # cmpr(1.0e21,2^70r3)
    "ok:i1",  # cmpr(1r3,0)
    "ok:i-1",  # cmpr(0,1r3)
    "ok:i-1",  # cmpr(-1r3,0)
    "ok:i1",  # cmpr(1r3,-5)
    "ok:i-1",  # cmpr(-5,1r3)
    "ok:i1",  # cmpr(7r2,3)
    "ok:i-1",  # cmpr(7r2,4)
    "ok:i-1",  # cmpr(3,7r2)
    "ok:i-1",  # cmpr(7r2,1.0Inf)
    "ok:i-1",  # cmpr(-1.0Inf,7r2)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # cmpr(7r2,1.5NaN)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # cmpr(1.5NaN,1)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # cmpr(1,1.5NaN)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # cmpr(1.5NaN,1.5NaN)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # cmpr(1.5NaN,1.0Inf)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # cmpr(1.5NaN,2^70)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # cmpr(1r2,1.5NaN)
    "err:a[105, 110, 115, 116, 97, 110, 116, 105, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # cmpr(_,1)
    "err:a[105, 110, 115, 116, 97, 110, 116, 105, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # cmpr(1,_)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[101, 118, 97, 108, 117, 97, 98, 108, 101],ca[47]/2(a[97],i0))@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # cmpr(a,1)
    "ok:i9",  # +(cmpr(1,2),10)
    "ok:i0",  # cmpr(+(1,1),*(1,2))
    "ok:i2",  # maxr(1,2)
    "ok:i2",  # maxr(2,1)
    "ok:i1",  # maxr(1,1)
    "ok:i1",  # maxr(1,1.0)
    "ok:i1",  # maxr(1.0,1)
    "ok:F3ff0000000000000",  # maxr(1.0,1.0)
    "ok:i2",  # maxr(1.5,2)
    "ok:i2",  # maxr(2,1.5)
    "ok:i-1",  # maxr(-1,-2)
    "ok:F0",  # maxr(-0.0,0.0)
    "ok:F0",  # maxr(0.0,-0.0)
    "ok:F8000000000000000",  # maxr(-0.0,-0.0)
    "ok:F0",  # maxr(0.0,0.0)
    "ok:i0",  # maxr(-0.0,0)
    "ok:i0",  # maxr(0,-0.0)
    "ok:i0",  # maxr(0.0,0)
    "ok:i0",  # maxr(0,0.0)
    "ok:i1",  # maxr(1.5NaN,1)
    "ok:i1",  # maxr(1,1.5NaN)
    "ok:F7ff8000000000000",  # maxr(1.5NaN,1.5NaN)
    "ok:F3ff8000000000000",  # maxr(1.5NaN,1.5)
    "ok:F3ff8000000000000",  # maxr(1.5,1.5NaN)
    "ok:q1r3",  # maxr(1.5NaN,1r3)
    "ok:q1r3",  # maxr(1r3,1.5NaN)
    "ok:i1180591620717411303424",  # maxr(1.5NaN,2^70)
    "ok:i1180591620717411303424",  # maxr(2^70,1.5NaN)
    "ok:q1r3",  # maxr(1r3,0.3333333333333333)
    "ok:q1r3",  # maxr(0.3333333333333333,1r3)
    "ok:q1r2",  # maxr(1r2,0.5)
    "ok:q1r2",  # maxr(0.5,1r2)
    "ok:q3r2",  # maxr(3r2,1.5)
    "ok:q3r2",  # maxr(1.5,3r2)
    "ok:q1r2",  # maxr(1r3,1r2)
    "ok:q1r2",  # maxr(1r2,1r3)
    "ok:F7ff0000000000000",  # maxr(1.0Inf,2^70)
    "ok:F7ff0000000000000",  # maxr(2^70,1.0Inf)
    "ok:i-9223372036854775808",  # maxr(-1.0Inf,INT64_MIN)
    "ok:i-9223372036854775808",  # maxr(INT64_MIN,-1.0Inf)
    "ok:F7ff0000000000000",  # maxr(1.0Inf,1.0Inf)
    "ok:F7ff0000000000000",  # maxr(-1.0Inf,1.0Inf)
    "ok:i1180591620717411303425",  # maxr(2^70,1180591620717411303425)
    "ok:i1180591620717411303424",  # maxr(2^70,1.0e21)
    "ok:i1180591620717411303424",  # maxr(1.0e21,2^70)
    "ok:i9007199254740993",  # maxr(9007199254740993,9007199254740992.0)
    "ok:i9007199254740993",  # maxr(9007199254740992.0,9007199254740993)
    "ok:i1180591620717411303424",  # maxr(2^70,2^70r3)
    "err:a[105, 110, 115, 116, 97, 110, 116, 105, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # maxr(_,1)
    "err:a[105, 110, 115, 116, 97, 110, 116, 105, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # maxr(1,_)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[101, 118, 97, 108, 117, 97, 98, 108, 101],ca[47]/2(a[97],i0))@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # maxr(a,1)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[101, 118, 97, 108, 117, 97, 98, 108, 101],ca[47]/2(a[97],i0))@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # maxr(1,a)
    "ok:i3",  # maxr(+(1,2),*(1,3))
    "ok:i6",  # +(maxr(1,2),maxr(3,4))
    "ok:i1",  # minr(1,2)
    "ok:i1",  # minr(2,1)
    "ok:i1",  # minr(1,1)
    "ok:i1",  # minr(1,1.0)
    "ok:i1",  # minr(1.0,1)
    "ok:F3ff0000000000000",  # minr(1.0,1.0)
    "ok:F3ff8000000000000",  # minr(1.5,2)
    "ok:F3ff8000000000000",  # minr(2,1.5)
    "ok:i-2",  # minr(-1,-2)
    "ok:F8000000000000000",  # minr(-0.0,0.0)
    "ok:F8000000000000000",  # minr(0.0,-0.0)
    "ok:F8000000000000000",  # minr(-0.0,-0.0)
    "ok:F0",  # minr(0.0,0.0)
    "ok:i0",  # minr(-0.0,0)
    "ok:i0",  # minr(0,-0.0)
    "ok:i0",  # minr(0.0,0)
    "ok:i0",  # minr(0,0.0)
    "ok:i1",  # minr(1.5NaN,1)
    "ok:i1",  # minr(1,1.5NaN)
    "ok:F7ff8000000000000",  # minr(1.5NaN,1.5NaN)
    "ok:F3ff8000000000000",  # minr(1.5NaN,1.5)
    "ok:F3ff8000000000000",  # minr(1.5,1.5NaN)
    "ok:q1r3",  # minr(1.5NaN,1r3)
    "ok:q1r3",  # minr(1r3,1.5NaN)
    "ok:i1180591620717411303424",  # minr(1.5NaN,2^70)
    "ok:i1180591620717411303424",  # minr(2^70,1.5NaN)
    "ok:F3fd5555555555555",  # minr(1r3,0.3333333333333333)
    "ok:F3fd5555555555555",  # minr(0.3333333333333333,1r3)
    "ok:q1r2",  # minr(1r2,0.5)
    "ok:q1r2",  # minr(0.5,1r2)
    "ok:q3r2",  # minr(3r2,1.5)
    "ok:q3r2",  # minr(1.5,3r2)
    "ok:q1r3",  # minr(1r3,1r2)
    "ok:q1r3",  # minr(1r2,1r3)
    "ok:i1180591620717411303424",  # minr(1.0Inf,2^70)
    "ok:i1180591620717411303424",  # minr(2^70,1.0Inf)
    "ok:Ffff0000000000000",  # minr(-1.0Inf,INT64_MIN)
    "ok:Ffff0000000000000",  # minr(INT64_MIN,-1.0Inf)
    "ok:F7ff0000000000000",  # minr(1.0Inf,1.0Inf)
    "ok:Ffff0000000000000",  # minr(-1.0Inf,1.0Inf)
    "ok:i1180591620717411303424",  # minr(2^70,1180591620717411303425)
    "ok:F444b1ae4d6e2ef50",  # minr(2^70,1.0e21)
    "ok:F444b1ae4d6e2ef50",  # minr(1.0e21,2^70)
    "ok:F4340000000000000",  # minr(9007199254740993,9007199254740992.0)
    "ok:F4340000000000000",  # minr(9007199254740992.0,9007199254740993)
    "ok:q1180591620717411303424r3",  # minr(2^70,2^70r3)
    "err:a[105, 110, 115, 116, 97, 110, 116, 105, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # minr(_,1)
    "err:a[105, 110, 115, 116, 97, 110, 116, 105, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # minr(1,_)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[101, 118, 97, 108, 117, 97, 98, 108, 101],ca[47]/2(a[97],i0))@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # minr(a,1)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[101, 118, 97, 108, 117, 97, 98, 108, 101],ca[47]/2(a[97],i0))@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # minr(1,a)
    "ok:i3",  # minr(+(1,2),*(1,3))
    "ok:i4",  # +(minr(1,2),minr(3,4))
    "ok:i12",  # lcm(4,6)
    "ok:i12",  # lcm(6,4)
    "ok:i0",  # lcm(0,5)
    "ok:i0",  # lcm(5,0)
    "ok:i0",  # lcm(0,0)
    "ok:i12",  # lcm(-4,6)
    "ok:i12",  # lcm(4,-6)
    "ok:i12",  # lcm(-4,-6)
    "ok:i91",  # lcm(7,13)
    "ok:i12",  # lcm(12,12)
    "ok:i1",  # lcm(1,1)
    "ok:i0",  # lcm(1,0)
    "ok:i9223372036854775807",  # lcm(INT64_MAX,INT64_MAX)
    "ok:i18446744073709551614",  # lcm(INT64_MAX,2)
    "ok:i18446744073709551614",  # lcm(2,INT64_MAX)
    "ok:i85070591730234615838173535747377725442",  # lcm(INT64_MAX,9223372036854775806)
    "ok:i9223372036854775808",  # lcm(INT64_MIN,1)
    "ok:i9223372036854775808",  # lcm(1,INT64_MIN)
    "ok:i9223372036854775808",  # lcm(INT64_MIN,INT64_MIN)
    "ok:i9223372036854775808",  # lcm(INT64_MIN,2)
    "ok:i9223372036854775808",  # lcm(INT64_MIN,-1)
    "ok:i13835058055282163712",  # lcm(4611686018427387904,3)
    "ok:i4611686018427387904",  # lcm(4611686018427387904,4611686018427387904)
    "ok:i3037000500",  # lcm(3037000500,3037000500)
    "ok:i3037000499",  # lcm(3037000499,3037000499)
    "ok:i18446744078004518912",  # lcm(4294967296,4294967297)
    "ok:i3541774862152233910272",  # lcm(2^70,6)
    "ok:i3541774862152233910272",  # lcm(6,2^70)
    "ok:i3541774862152233910272",  # lcm(-2^70,6)
    "ok:i3541774862152233910272",  # lcm(6,-2^70)
    "ok:i0",  # lcm(2^70,0)
    "ok:i0",  # lcm(0,2^70)
    "ok:i1180591620717411303424",  # lcm(2^70,2^70)
    "ok:i1393796574908163946347162983661240005427200",  # lcm(2^70,1180591620717411303425)
    "ok:i1000000000000000000000000000000",  # lcm(10^30,10^20)
    "ok:i1000000000000000000000000000000",  # lcm(-10^30,10^20)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[105, 110, 116, 101, 103, 101, 114],F4004000000000000)@ca[47]/2(a[108, 99, 109],i2)@_",  # lcm(2.5,3)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[105, 110, 116, 101, 103, 101, 114],F4004000000000000)@ca[47]/2(a[108, 99, 109],i2)@_",  # lcm(3,2.5)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[105, 110, 116, 101, 103, 101, 114],F4000000000000000)@ca[47]/2(a[108, 99, 109],i2)@_",  # lcm(2.0,3)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[105, 110, 116, 101, 103, 101, 114],F4000000000000000)@ca[47]/2(a[108, 99, 109],i2)@_",  # lcm(3,2.0)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[105, 110, 116, 101, 103, 101, 114],q1r2)@ca[47]/2(a[108, 99, 109],i2)@_",  # lcm(1r2,3)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[105, 110, 116, 101, 103, 101, 114],q1r2)@ca[47]/2(a[108, 99, 109],i2)@_",  # lcm(3,1r2)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # lcm(1.5NaN,3)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # lcm(1.0Inf,3)
    "err:a[105, 110, 115, 116, 97, 110, 116, 105, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # lcm(_,1)
    "err:a[105, 110, 115, 116, 97, 110, 116, 105, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # lcm(1,_)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[101, 118, 97, 108, 117, 97, 98, 108, 101],ca[47]/2(a[97],i0))@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # lcm(a,1)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[101, 118, 97, 108, 117, 97, 98, 108, 101],ca[47]/2(a[97],i0))@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # lcm(1,a)
    "ok:i14",  # +(lcm(4,6),gcd(4,6))
    "ok:i12",  # lcm(+(2,2),*(2,3))
    "ok:F3ff0000000000001",  # nexttoward(1.0,2)
    "ok:F3fefffffffffffff",  # nexttoward(1.0,0)
    "ok:F3ff0000000000001",  # nexttoward(1.0,2.0)
    "ok:F3fefffffffffffff",  # nexttoward(1.0,0.5)
    "ok:F3ff0000000000001",  # nexttoward(1,2)
    "ok:F3fefffffffffffff",  # nexttoward(1,0)
    "ok:F3ff0000000000000",  # nexttoward(1,1)
    "ok:F3ff0000000000000",  # nexttoward(1.0,1.0)
    "ok:F1",  # nexttoward(0.0,1)
    "ok:F8000000000000001",  # nexttoward(0.0,-1)
    "ok:F1",  # nexttoward(-0.0,1)
    "ok:F8000000000000001",  # nexttoward(-0.0,-1)
    "ok:F0",  # nexttoward(0.0,0.0)
    "ok:F0",  # nexttoward(-0.0,0.0)
    "ok:F8000000000000000",  # nexttoward(0.0,-0.0)
    "ok:F0",  # nexttoward(5.0e-324,0)
    "ok:F2",  # nexttoward(5.0e-324,1)
    "ok:F8000000000000000",  # nexttoward(-5.0e-324,0)
    "ok:F8000000000000002",  # nexttoward(-5.0e-324,-1)
    "ok:Ffffffffffffff",  # nexttoward(2.2250738585072014e-308,0)
    "ok:F10000000000001",  # nexttoward(2.2250738585072014e-308,1)
    "ok:F7feffffffffffffe",  # nexttoward(1.7976931348623157e308,0)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # nexttoward(1.7976931348623157e308,1.0Inf)
    "ok:F7fefffffffffffff",  # nexttoward(1.7976931348623157e308,1.7976931348623157e308)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # nexttoward(-1.7976931348623157e308,-1.0Inf)
    "ok:F7fefffffffffffff",  # nexttoward(1.0Inf,0)
    "ok:Fffefffffffffffff",  # nexttoward(-1.0Inf,0)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # nexttoward(1.0Inf,1.0Inf)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # nexttoward(-1.0Inf,-1.0Inf)
    "ok:F7fefffffffffffff",  # nexttoward(1.0Inf,-1.0Inf)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # nexttoward(1.5NaN,1)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # nexttoward(1,1.5NaN)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # nexttoward(1.5NaN,1.5NaN)
    "ok:F4450000000000001",  # nexttoward(2^70,1.0Inf)
    "ok:F444fffffffffffff",  # nexttoward(2^70,0)
    "ok:F3fd5555555555556",  # nexttoward(1r3,1)
    "ok:F3fd5555555555554",  # nexttoward(1r3,0)
    "ok:F3fefffffffffffff",  # nexttoward(1,1r3)
    "ok:F3fb999999999999b",  # nexttoward(0.1,0.2)
    "ok:F3fc9999999999999",  # nexttoward(0.2,0.1)
    "ok:Fbfefffffffffffff",  # nexttoward(-1.0,0)
    "ok:Fbff0000000000001",  # nexttoward(-1.0,-2)
    "ok:F4000000000000001",  # nexttoward(2.0,3)
    "ok:F7e37e43c8800759d",  # nexttoward(1.0e300,1.0Inf)
    "err:a[105, 110, 115, 116, 97, 110, 116, 105, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # nexttoward(_,1)
    "err:a[105, 110, 115, 116, 97, 110, 116, 105, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # nexttoward(1,_)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[101, 118, 97, 108, 117, 97, 98, 108, 101],ca[47]/2(a[97],i0))@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # nexttoward(a,1)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[101, 118, 97, 108, 117, 97, 98, 108, 101],ca[47]/2(a[97],i0))@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # nexttoward(1,a)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # nexttoward(10^400,1)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # nexttoward(1,10^400)
    "ok:F3cb0000000000000",  # -(nexttoward(1,2),1)
    "ok:F3ff0000000000001",  # nexttoward(+(0.5,0.5),*(2,2))
    "ok:F0",  # sinh(0)
    "ok:F3ff2cd9fc44eb982",  # sinh(1)
    "ok:Fbff2cd9fc44eb982",  # sinh(-1)
    "ok:F40528d0166f07374",  # sinh(5)
    "ok:F3fe0acd00fe63b97",  # sinh(0.5)
    "ok:Fbfe0acd00fe63b97",  # sinh(-0.5)
    "ok:F40183368cdb0b6d3",  # sinh(2.5)
    "ok:F8000000000000000",  # sinh(-0.0)
    "ok:F7e8",  # sinh(1.0e-320)
    "ok:F7fe3e21a464507fa",  # sinh(710.0)
    "ok:Fffe3e21a464507fa",  # sinh(-710.0)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # sinh(1.0e300)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # sinh(INT64_MIN)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # sinh(2^70)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # sinh(10^30)
    "ok:F3fd5bb0851452b81",  # sinh(1r3)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # sinh(1.0Inf)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # sinh(-1.0Inf)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # sinh(1.5NaN)
    "err:a[105, 110, 115, 116, 97, 110, 116, 105, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # sinh(_)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[101, 118, 97, 108, 117, 97, 98, 108, 101],ca[47]/2(a[97],i0))@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # sinh(a)
    "ok:F3fe0acd00fe63b97",  # sinh(+(0.25,0.25))
    "ok:F3fe8c2367cce7c18",  # +(sinh(0.5),sinh(0.25))
    "ok:F3ff0000000000000",  # cosh(0)
    "ok:F3ff8b07551d9f550",  # cosh(1)
    "ok:F3ff8b07551d9f550",  # cosh(-1)
    "ok:F40528d6fcbeff3aa",  # cosh(5)
    "ok:F3ff20ac1862ae8d0",  # cosh(0.5)
    "ok:F3ff20ac1862ae8d0",  # cosh(-0.5)
    "ok:F40188776e4b30aa3",  # cosh(2.5)
    "ok:F3ff0000000000000",  # cosh(-0.0)
    "ok:F3ff0000000000000",  # cosh(1.0e-320)
    "ok:F7fe3e21a464507fa",  # cosh(710.0)
    "ok:F7fe3e21a464507fa",  # cosh(-710.0)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # cosh(1.0e300)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # cosh(INT64_MIN)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # cosh(2^70)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # cosh(10^30)
    "ok:F3ff0e5ab9d68e233",  # cosh(1r3)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # cosh(1.0Inf)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # cosh(-1.0Inf)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # cosh(1.5NaN)
    "err:a[105, 110, 115, 116, 97, 110, 116, 105, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # cosh(_)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[101, 118, 97, 108, 117, 97, 98, 108, 101],ca[47]/2(a[97],i0))@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # cosh(a)
    "ok:F3ff20ac1862ae8d0",  # cosh(+(0.25,0.25))
    "ok:F400145b645faa50b",  # +(cosh(0.5),cosh(0.25))
    "ok:F0",  # tanh(0)
    "ok:F3fe85efab514f394",  # tanh(1)
    "ok:Fbfe85efab514f394",  # tanh(-1)
    "ok:F3fefff419668df11",  # tanh(5)
    "ok:F3fdd9353d7568af3",  # tanh(0.5)
    "ok:Fbfdd9353d7568af3",  # tanh(-0.5)
    "ok:F3fef9258260a71c2",  # tanh(2.5)
    "ok:F8000000000000000",  # tanh(-0.0)
    "ok:F7e8",  # tanh(1.0e-320)
    "ok:F3ff0000000000000",  # tanh(710.0)
    "ok:Fbff0000000000000",  # tanh(-710.0)
    "ok:F3ff0000000000000",  # tanh(1.0e300)
    "ok:Fbff0000000000000",  # tanh(INT64_MIN)
    "ok:F3ff0000000000000",  # tanh(2^70)
    "ok:F3ff0000000000000",  # tanh(10^30)
    "ok:F3fd493aa293c8802",  # tanh(1r3)
    "ok:F3ff0000000000000",  # tanh(1.0Inf)
    "ok:Fbff0000000000000",  # tanh(-1.0Inf)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # tanh(1.5NaN)
    "err:a[105, 110, 115, 116, 97, 110, 116, 105, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # tanh(_)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[101, 118, 97, 108, 117, 97, 98, 108, 101],ca[47]/2(a[97],i0))@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # tanh(a)
    "ok:F3ff0000000000000",  # tanh(1000)
    "ok:Fbff0000000000000",  # tanh(-1000)
    "ok:F3fb983d7795f413a",  # tanh(0.1)
    "ok:F3fdd9353d7568af3",  # tanh(+(0.25,0.25))
    "ok:F3fe6a0099551cc9b",  # +(tanh(0.5),tanh(0.25))
    "ok:F0",  # asinh(0)
    "ok:F3fec34366179d427",  # asinh(1)
    "ok:Fbfec34366179d427",  # asinh(-1)
    "ok:F40027fdfac4e4380",  # asinh(5)
    "ok:F3fdecc2caec5160a",  # asinh(0.5)
    "ok:Fbfdecc2caec5160a",  # asinh(-0.5)
    "ok:F3ffa5b0f0be9dcf6",  # asinh(2.5)
    "ok:F8000000000000000",  # asinh(-0.0)
    "ok:F7e8",  # asinh(1.0e-320)
    "ok:F401d089d5326d8df",  # asinh(710.0)
    "ok:Fc01d089d5326d8df",  # asinh(-710.0)
    "ok:F40859bbfd8b83e43",  # asinh(1.0e300)
    "ok:Fc0462e42fefa39ef",  # asinh(INT64_MIN)
    "ok:F40489b5252dd9846",  # asinh(2^70)
    "ok:F4051715325f7f438",  # asinh(10^30)
    "ok:F3fd4f4f17995b748",  # asinh(1r3)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # asinh(1.0Inf)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # asinh(-1.0Inf)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # asinh(1.5NaN)
    "err:a[105, 110, 115, 116, 97, 110, 116, 105, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # asinh(_)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[101, 118, 97, 108, 117, 97, 98, 108, 101],ca[47]/2(a[97],i0))@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # asinh(a)
    "ok:Fc0859bbfd8b83e43",  # asinh(-1.0e300)
    "ok:F3ddb7cdfd9d7bdbb",  # asinh(1.0e-10)
    "ok:F3fdecc2caec5160a",  # asinh(+(0.25,0.25))
    "ok:F3fe7515520490493",  # +(asinh(0.5),asinh(0.25))
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # acosh(0)
    "ok:F0",  # acosh(1)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # acosh(-1)
    "ok:F400256e66a48a3b6",  # acosh(5)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # acosh(0.5)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # acosh(-0.5)
    "ok:F3ff9119c13a31bb0",  # acosh(2.5)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # acosh(-0.0)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # acosh(1.0e-320)
    "ok:F401d089d1096b506",  # acosh(710.0)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # acosh(-710.0)
    "ok:F40859bbfd8b83e43",  # acosh(1.0e300)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # acosh(INT64_MIN)
    "ok:F40489b5252dd9846",  # acosh(2^70)
    "ok:F4051715325f7f438",  # acosh(10^30)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # acosh(1r3)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # acosh(1.0Inf)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # acosh(-1.0Inf)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # acosh(1.5NaN)
    "err:a[105, 110, 115, 116, 97, 110, 116, 105, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # acosh(_)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[101, 118, 97, 108, 117, 97, 98, 108, 101],ca[47]/2(a[97],i0))@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # acosh(a)
    "ok:F0",  # acosh(1.0)
    "ok:F3feecc2caec5160a",  # acosh(1.5)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # acosh(+(0.25,0.25))
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # +(acosh(0.5),acosh(0.25))
    "ok:F0",  # atanh(0)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # atanh(1)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # atanh(-1)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # atanh(5)
    "ok:F3fe193ea7aad030a",  # atanh(0.5)
    "ok:Fbfe193ea7aad030a",  # atanh(-0.5)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # atanh(2.5)
    "ok:F8000000000000000",  # atanh(-0.0)
    "ok:F7e8",  # atanh(1.0e-320)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # atanh(710.0)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # atanh(-710.0)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # atanh(1.0e300)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # atanh(INT64_MIN)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # atanh(2^70)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # atanh(10^30)
    "ok:F3fd62e42fefa39ef",  # atanh(1r3)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # atanh(1.0Inf)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # atanh(-1.0Inf)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # atanh(1.5NaN)
    "err:a[105, 110, 115, 116, 97, 110, 116, 105, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # atanh(_)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[101, 118, 97, 108, 117, 97, 98, 108, 101],ca[47]/2(a[97],i0))@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # atanh(a)
    "ok:F4032b708872320e2",  # atanh(0.9999999999999999)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # atanh(2)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # atanh(-2)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # atanh(1.0)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # atanh(-1.0)
    "ok:F3fe193ea7aad030a",  # atanh(1r2)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # atanh(3r2)
    "ok:F3fe193ea7aad030a",  # atanh(+(0.25,0.25))
    "ok:F3fe9c041f7ed8d33",  # +(atanh(0.5),atanh(0.25))
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # lgamma(0)
    "ok:F0",  # lgamma(1)
    "ok:F0",  # lgamma(2)
    "ok:F3fe62e42fefa39ef",  # lgamma(3)
    "ok:F40096ca77c922cf9",  # lgamma(5)
    "ok:F40767225b4879463",  # lgamma(100)
    "ok:F40861495a1a8a1d5",  # lgamma(171)
    "ok:F3fe250d048e7a1bd",  # lgamma(0.5)
    "ok:Fbfbeeb95b094c191",  # lgamma(1.5)
    "ok:F3fd2383e809a67e8",  # lgamma(2.5)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # lgamma(-0.5)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # lgamma(-1.5)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # lgamma(-1)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # lgamma(-2)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # lgamma(-1.0)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # lgamma(0.0)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # lgamma(-0.0)
    "ok:F4085963447f87fb5",  # lgamma(1.0e-300)
    "ok:F40874385446d71c3",  # lgamma(5.0e-324)
    "ok:F4249a43710f467c1",  # lgamma(10000000000.0)
    "ok:F7ed017f38e7a1ab5",  # lgamma(1.0e300)
    "ok:F7fd8f7797fbe814f",  # lgamma(1.0e305)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # lgamma(1.0e308)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # lgamma(1.7976931348623157e308)
    "ok:F44a7c29946e1af5e",  # lgamma(2^70)
    "ok:F468ada137e8ad860",  # lgamma(10^30)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # lgamma(10^400)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # lgamma(-2^70)
    "ok:F3fe250d048e7a1bd",  # lgamma(1r2)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # lgamma(-3r2)
    "ok:F448ef2a29965b45c",  # lgamma(2^70r3)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # lgamma(1.0Inf)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # lgamma(-1.0Inf)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # lgamma(1.5NaN)
    "err:a[105, 110, 115, 116, 97, 110, 116, 105, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # lgamma(_)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[101, 118, 97, 108, 117, 97, 98, 108, 101],ca[47]/2(a[97],i0))@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # lgamma(a)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # lgamma(INT64_MIN)
    "ok:F44355589f2fe5107",  # lgamma(INT64_MAX)
    "ok:F3ff3373018970a36",  # lgamma(3.5)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # lgamma(-2.5)
    "ok:F3fe62e42fefa39ef",  # lgamma(+(1,2))
    "ok:F4003e116bcd39e7d",  # +(lgamma(3),lgamma(4))
    "ok:F0",  # erf(0)
    "ok:F3feaf767a741088b",  # erf(1)
    "ok:Fbfeaf767a741088b",  # erf(-1)
    "ok:F3fefffffffffc9e8",  # erf(5)
    "ok:F3fe0a7ef5c18edd2",  # erf(0.5)
    "ok:Fbfe0a7ef5c18edd2",  # erf(-0.5)
    "ok:F3feffcaa8f4c9bea",  # erf(2.5)
    "ok:F8000000000000000",  # erf(-0.0)
    "ok:F8ec",  # erf(1.0e-320)
    "ok:F3ff0000000000000",  # erf(710.0)
    "ok:Fbff0000000000000",  # erf(-710.0)
    "ok:F3ff0000000000000",  # erf(1.0e300)
    "ok:Fbff0000000000000",  # erf(INT64_MIN)
    "ok:F3ff0000000000000",  # erf(2^70)
    "ok:F3ff0000000000000",  # erf(10^30)
    "ok:F3fd735a06cff72fc",  # erf(1r3)
    "ok:F3ff0000000000000",  # erf(1.0Inf)
    "ok:Fbff0000000000000",  # erf(-1.0Inf)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # erf(1.5NaN)
    "err:a[105, 110, 115, 116, 97, 110, 116, 105, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # erf(_)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[101, 118, 97, 108, 117, 97, 98, 108, 101],ca[47]/2(a[97],i0))@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # erf(a)
    "ok:F3fefffd1ac4135f9",  # erf(3.0)
    "ok:F3ff0000000000000",  # erf(6.0)
    "ok:F3fe0a7ef5c18edd2",  # erf(+(0.25,0.25))
    "ok:F3fe97f99cd3258d6",  # +(erf(0.5),erf(0.25))
    "ok:F3ff0000000000000",  # erfc(0)
    "ok:F3fc4226162fbddd4",  # erfc(1)
    "ok:F3ffd7bb3d3a08446",  # erfc(-1)
    "ok:F3d7b0c0000000000",  # erfc(5)
    "ok:F3fdeb02147ce245c",  # erfc(0.5)
    "ok:F3ff853f7ae0c76e9",  # erfc(-0.5)
    "ok:F3f3aab859b20b000",  # erfc(2.5)
    "ok:F3ff0000000000000",  # erfc(-0.0)
    "ok:F3ff0000000000000",  # erfc(1.0e-320)
    "ok:F0",  # erfc(710.0)
    "ok:F4000000000000000",  # erfc(-710.0)
    "ok:F0",  # erfc(1.0e300)
    "ok:F4000000000000000",  # erfc(INT64_MIN)
    "ok:F0",  # erfc(2^70)
    "ok:F0",  # erfc(10^30)
    "ok:F3fe4652fc9804682",  # erfc(1r3)
    "ok:F0",  # erfc(1.0Inf)
    "ok:F4000000000000000",  # erfc(-1.0Inf)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # erfc(1.5NaN)
    "err:a[105, 110, 115, 116, 97, 110, 116, 105, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # erfc(_)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[101, 118, 97, 108, 117, 97, 98, 108, 101],ca[47]/2(a[97],i0))@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # erfc(a)
    "ok:F3ef729df65038000",  # erfc(3.0)
    "ok:F0",  # erfc(6.0)
    "ok:F0",  # erfc(26.0)
    "ok:F0",  # erfc(27.0)
    "ok:F0",  # erfc(26.55)
    "ok:F0",  # erfc(30.0)
    "ok:F4000000000000000",  # erfc(-30.0)
    "ok:F3fdeb02147ce245c",  # erfc(+(0.25,0.25))
    "ok:F3e508ddd14000000",  # erfc(4.0) — 1 - erf: the low bits lost (D-0040)
    "ok:F0",  # erfc(10.0) — swipl's 0.0, the C library's 2.09e-45 (D-0040)
    "ok:F3ff340331966d395",  # +(erfc(0.5),erfc(0.25))
    "ok:F0",  # log10(1)
    "ok:F3ff0000000000000",  # log10(10)
    "ok:F4000000000000000",  # log10(100)
    "ok:F4008000000000000",  # log10(1000)
    "ok:F3fd34413509f79ff",  # log10(2)
    "ok:F3fe65df657b04301",  # log10(5)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # log10(0)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # log10(-1)
    "ok:Fc008000000000000",  # log10(0.001)
    "ok:Fbfd34413509f79ff",  # log10(0.5)
    "ok:F4072c00000000000",  # log10(1.0e300)
    "ok:Fc072c00000000000",  # log10(1.0e-300)
    "ok:Fc07434e6420f4374",  # log10(5.0e-324)
    "ok:Fc07400000511df19",  # log10(1.0e-320)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # log10(0.0)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # log10(-0.0)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # log10(-0.5)
    "ok:F0",  # log10(1.0)
    "ok:F3ff0000000000000",  # log10(10.0)
    "ok:F4036000000000000",  # log10(1.0e22)
    "ok:F3fde8927964fd5fd",  # log10(3.0)
    "ok:F4032f703035cfc17",  # log10(INT64_MAX)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # log10(INT64_MIN)
    "ok:F40351275202e6d6f",  # log10(2^70)
    "ok:F403e000000000000",  # log10(10^30)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # log10(10^400)
    "ok:F4073400000000000",  # log10(10^308)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # log10(-2^70)
    "ok:Fbfd34413509f79ff",  # log10(1r2)
    "ok:Fbfde8927964fd5fe",  # log10(1r3)
    "ok:F4034985081d52e17",  # log10(2^70r3)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # log10(1.0Inf)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # log10(-1.0Inf)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # log10(1.5NaN)
    "err:a[105, 110, 115, 116, 97, 110, 116, 105, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # log10(_)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[101, 118, 97, 108, 117, 97, 98, 108, 101],ca[47]/2(a[97],i0))@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # log10(a)
    "ok:F4000000000000000",  # log10(*(10,10))
    "ok:F4014000000000000",  # +(log10(100),log10(1000))
    "ok:i2",  # floor(log10(999))
    "ok:F3cb0000000000000",  # epsilon
    "ok:F3cb0000000000000",  # epsilon()
    "ok:F7ff0000000000000",  # inf
    "ok:F7ff0000000000000",  # inf()
    "ok:F7ff8000000000000",  # nan
    "ok:F7ff8000000000000",  # nan()
    "ok:F3ff0000000000001",  # +(epsilon,1)
    "ok:Ffff0000000000000",  # -(inf)
    "ok:F7ff8000000000000",  # -(nan)
    "ok:F7ff0000000000000",  # max(inf,1)
    "ok:i1",  # min(inf,1)
    "ok:F7ff8000000000000",  # max(nan,1)
    "ok:F7ff8000000000000",  # min(1,nan)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # +(inf,1)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # +(nan,1)
    "ok:F3ff0000000000002",  # +(1,*(2,epsilon))
    "ok:F3970000000000000",  # *(epsilon,epsilon)
    "ok:F7ff0000000000000",  # float(inf)
    "ok:F3ff0000000000000",  # sign(inf)
    "ok:Fbff0000000000000",  # sign(-(inf))
    "ok:F7ff0000000000000",  # abs(-(inf))
    "ok:F7ff0000000000000",  # integer(inf)
    "ok:F7ff8000000000000",  # integer(nan)
    "ok:F7ff0000000000000",  # truncate(inf)
    "ok:F7ff8000000000000",  # floor(nan)
    "ok:i1",  # cmpr(inf,2^70)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # cmpr(1,nan)
    "ok:i2",  # maxr(nan,2)
    "ok:i3",  # minr(inf,3)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[101, 118, 97, 108, 117, 97, 98, 108, 101],ca[47]/2(a[101, 112, 115, 105, 108, 111, 110],i1))@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # epsilon(1)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[101, 118, 97, 108, 117, 97, 98, 108, 101],ca[47]/2(a[105, 110, 102],i1))@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # inf(1)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[101, 118, 97, 108, 117, 97, 98, 108, 101],ca[47]/2(a[110, 97, 110],i2))@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # nan(1,2)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[101, 118, 97, 108, 117, 97, 98, 108, 101],ca[47]/2(a[105, 110, 102],i2))@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # inf(1,2)
    "ok:Ffff0000000000000",  # copysign(inf,-1)
    "ok:i-1",  # copysign(1,-(inf))
    "ok:F7fefffffffffffff",  # nexttoward(inf,0)
    "ok:F3ff0000000000000",  # +(1.0,0.0)
    "ok:i0",  # lsb(1)
    "ok:i1",  # lsb(2)
    "ok:i0",  # lsb(3)
    "ok:i2",  # lsb(4)
    "ok:i2",  # lsb(12)
    "ok:i0",  # lsb(255)
    "ok:i8",  # lsb(256)
    "ok:i31",  # lsb(2147483648)
    "ok:i32",  # lsb(4294967296)
    "ok:i31",  # lsb(6442450944)
    "ok:i40",  # lsb(1099511627776)
    "ok:i62",  # lsb(4611686018427387904)
    "ok:i0",  # lsb(INT64_MAX)
    "ok:i61",  # lsb(6917529027641081856)
    "ok:i64",  # lsb(2^64)
    "ok:i70",  # lsb(2^70)
    "ok:i100",  # lsb(3802951800…)
    "ok:i64",  # lsb(1199038364791120855040)
    "ok:i200",  # lsb(2^200)
    "ok:i100",  # lsb(1606938044…)
    "ok:i30",  # lsb(10^30)
    "err:ca[100, 111, 109, 97, 105, 110, 95, 101, 114, 114, 111, 114]/2(a[110, 111, 116, 95, 108, 101, 115, 115, 95, 116, 104, 97, 110, 95, 111, 110, 101],i0)@ca[47]/2(a[108, 115, 98],i1)@_",  # lsb(0)
    "err:ca[100, 111, 109, 97, 105, 110, 95, 101, 114, 114, 111, 114]/2(a[110, 111, 116, 95, 108, 101, 115, 115, 95, 116, 104, 97, 110, 95, 111, 110, 101],i-1)@ca[47]/2(a[108, 115, 98],i1)@_",  # lsb(-1)
    "err:ca[100, 111, 109, 97, 105, 110, 95, 101, 114, 114, 111, 114]/2(a[110, 111, 116, 95, 108, 101, 115, 115, 95, 116, 104, 97, 110, 95, 111, 110, 101],i-2)@ca[47]/2(a[108, 115, 98],i1)@_",  # lsb(-2)
    "err:ca[100, 111, 109, 97, 105, 110, 95, 101, 114, 114, 111, 114]/2(a[110, 111, 116, 95, 108, 101, 115, 115, 95, 116, 104, 97, 110, 95, 111, 110, 101],i-9223372036854775808)@ca[47]/2(a[108, 115, 98],i1)@_",  # lsb(INT64_MIN)
    "err:ca[100, 111, 109, 97, 105, 110, 95, 101, 114, 114, 111, 114]/2(a[110, 111, 116, 95, 108, 101, 115, 115, 95, 116, 104, 97, 110, 95, 111, 110, 101],i-1180591620717411303424)@ca[47]/2(a[108, 115, 98],i1)@_",  # lsb(-2^70)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[105, 110, 116, 101, 103, 101, 114],F0)@ca[47]/2(a[108, 115, 98],i1)@_",  # lsb(0.0)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[105, 110, 116, 101, 103, 101, 114],F4000000000000000)@ca[47]/2(a[108, 115, 98],i1)@_",  # lsb(2.0)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[105, 110, 116, 101, 103, 101, 114],F4004000000000000)@ca[47]/2(a[108, 115, 98],i1)@_",  # lsb(2.5)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[105, 110, 116, 101, 103, 101, 114],q1r2)@ca[47]/2(a[108, 115, 98],i1)@_",  # lsb(1r2)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[105, 110, 116, 101, 103, 101, 114],q8r3)@ca[47]/2(a[108, 115, 98],i1)@_",  # lsb(8r3)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # lsb(1.5NaN)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # lsb(1.0Inf)
    "err:a[105, 110, 115, 116, 97, 110, 116, 105, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # lsb(_)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[101, 118, 97, 108, 117, 97, 98, 108, 101],ca[47]/2(a[97],i0))@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # lsb(a)
    "ok:i3",  # lsb(*(3,8))
    "ok:i6",  # +(lsb(8),msb(8))
    "ok:i0",  # popcount(0)
    "ok:i1",  # popcount(1)
    "ok:i1",  # popcount(2)
    "ok:i2",  # popcount(3)
    "ok:i3",  # popcount(7)
    "ok:i1",  # popcount(8)
    "ok:i8",  # popcount(255)
    "ok:i1",  # popcount(256)
    "ok:i10",  # popcount(1023)
    "ok:i1",  # popcount(4294967296)
    "ok:i32",  # popcount(4294967295)
    "ok:i1",  # popcount(4611686018427387904)
    "ok:i63",  # popcount(INT64_MAX)
    "ok:i64",  # popcount(18446744073709551615)
    "ok:i1",  # popcount(2^64)
    "ok:i70",  # popcount(1180591620717411303423)
    "ok:i1",  # popcount(2^70)
    "ok:i2",  # popcount(1199038364791120855040)
    "ok:i37",  # popcount(10^30)
    "ok:i200",  # popcount(1606938044…)
    "err:ca[100, 111, 109, 97, 105, 110, 95, 101, 114, 114, 111, 114]/2(a[110, 111, 116, 95, 108, 101, 115, 115, 95, 116, 104, 97, 110, 95, 122, 101, 114, 111],i-1)@ca[47]/2(a[112, 111, 112, 99, 111, 117, 110, 116],i1)@_",  # popcount(-1)
    "err:ca[100, 111, 109, 97, 105, 110, 95, 101, 114, 114, 111, 114]/2(a[110, 111, 116, 95, 108, 101, 115, 115, 95, 116, 104, 97, 110, 95, 122, 101, 114, 111],i-2)@ca[47]/2(a[112, 111, 112, 99, 111, 117, 110, 116],i1)@_",  # popcount(-2)
    "err:ca[100, 111, 109, 97, 105, 110, 95, 101, 114, 114, 111, 114]/2(a[110, 111, 116, 95, 108, 101, 115, 115, 95, 116, 104, 97, 110, 95, 122, 101, 114, 111],i-9223372036854775808)@ca[47]/2(a[112, 111, 112, 99, 111, 117, 110, 116],i1)@_",  # popcount(INT64_MIN)
    "err:ca[100, 111, 109, 97, 105, 110, 95, 101, 114, 114, 111, 114]/2(a[110, 111, 116, 95, 108, 101, 115, 115, 95, 116, 104, 97, 110, 95, 122, 101, 114, 111],i-1180591620717411303424)@ca[47]/2(a[112, 111, 112, 99, 111, 117, 110, 116],i1)@_",  # popcount(-2^70)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[105, 110, 116, 101, 103, 101, 114],F0)@ca[47]/2(a[112, 111, 112, 99, 111, 117, 110, 116],i1)@_",  # popcount(0.0)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[105, 110, 116, 101, 103, 101, 114],F4000000000000000)@ca[47]/2(a[112, 111, 112, 99, 111, 117, 110, 116],i1)@_",  # popcount(2.0)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[105, 110, 116, 101, 103, 101, 114],F4004000000000000)@ca[47]/2(a[112, 111, 112, 99, 111, 117, 110, 116],i1)@_",  # popcount(2.5)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[105, 110, 116, 101, 103, 101, 114],q1r2)@ca[47]/2(a[112, 111, 112, 99, 111, 117, 110, 116],i1)@_",  # popcount(1r2)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[105, 110, 116, 101, 103, 101, 114],q3r4)@ca[47]/2(a[112, 111, 112, 99, 111, 117, 110, 116],i1)@_",  # popcount(3r4)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # popcount(1.5NaN)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[102, 108, 111, 97, 116, 95, 111, 118, 101, 114, 102, 108, 111, 119])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # popcount(1.0Inf)
    "err:a[105, 110, 115, 116, 97, 110, 116, 105, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # popcount(_)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[101, 118, 97, 108, 117, 97, 98, 108, 101],ca[47]/2(a[97],i0))@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # popcount(a)
    "ok:i10",  # popcount(-(<<(1,10),1))
    "ok:i10",  # +(popcount(255),popcount(3))
    "ok:i1",  # getbit(5,0)
    "ok:i0",  # getbit(5,1)
    "ok:i1",  # getbit(5,2)
    "ok:i0",  # getbit(5,3)
    "ok:i0",  # getbit(0,0)
    "ok:i1",  # getbit(1,0)
    "ok:i0",  # getbit(1,1)
    "ok:i1",  # getbit(INT64_MAX,0)
    "ok:i1",  # getbit(INT64_MAX,62)
    "ok:i0",  # getbit(INT64_MAX,63)
    "ok:i0",  # getbit(INT64_MAX,64)
    "ok:i0",  # getbit(5,63)
    "ok:i0",  # getbit(5,64)
    "ok:i0",  # getbit(5,65)
    "ok:i0",  # getbit(5,1000)
    "ok:i0",  # getbit(5,1000000)
    "ok:i0",  # getbit(5,2^70)
    "ok:i0",  # getbit(5,2^63)
    "ok:i0",  # getbit(5,INT64_MAX)
    "ok:i0",  # getbit(5,9223372036854775806)
    "ok:i1",  # getbit(2^70,70)
    "ok:i0",  # getbit(2^70,69)
    "ok:i0",  # getbit(2^70,71)
    "ok:i0",  # getbit(2^70,0)
    "ok:i0",  # getbit(2^70,1000000)
    "ok:i0",  # getbit(2^70,INT64_MAX)
    "ok:i0",  # getbit(2^70,2^63)
    "ok:i0",  # getbit(2^70,2^70)
    "ok:i1",  # getbit(1180591620717411303425,0)
    "ok:i0",  # getbit(1180591620717411303425,1)
    "ok:i1",  # getbit(18446744073709551615,63)
    "ok:i0",  # getbit(18446744073709551615,64)
    "ok:i1",  # getbit(2^64,64)
    "ok:i0",  # getbit(2^64,63)
    "ok:i0",  # getbit(10^30,0)
    "ok:i1",  # getbit(10^30,30)
    "err:ca[100, 111, 109, 97, 105, 110, 95, 101, 114, 114, 111, 114]/2(a[110, 111, 116, 95, 108, 101, 115, 115, 95, 116, 104, 97, 110, 95, 122, 101, 114, 111],i-1)@ca[47]/2(a[98, 105, 116],i2)@_",  # getbit(-1,0)
    "err:ca[100, 111, 109, 97, 105, 110, 95, 101, 114, 114, 111, 114]/2(a[110, 111, 116, 95, 108, 101, 115, 115, 95, 116, 104, 97, 110, 95, 122, 101, 114, 111],i-1180591620717411303424)@ca[47]/2(a[98, 105, 116],i2)@_",  # getbit(-2^70,0)
    "err:ca[100, 111, 109, 97, 105, 110, 95, 101, 114, 114, 111, 114]/2(a[110, 111, 116, 95, 108, 101, 115, 115, 95, 116, 104, 97, 110, 95, 122, 101, 114, 111],i-1)@ca[47]/2(a[98, 105, 116],i2)@_",  # getbit(5,-1)
    "err:ca[100, 111, 109, 97, 105, 110, 95, 101, 114, 114, 111, 114]/2(a[110, 111, 116, 95, 108, 101, 115, 115, 95, 116, 104, 97, 110, 95, 122, 101, 114, 111],i-1180591620717411303424)@ca[47]/2(a[98, 105, 116],i2)@_",  # getbit(5,-2^70)
    "err:ca[100, 111, 109, 97, 105, 110, 95, 101, 114, 114, 111, 114]/2(a[110, 111, 116, 95, 108, 101, 115, 115, 95, 116, 104, 97, 110, 95, 122, 101, 114, 111],i-1)@ca[47]/2(a[98, 105, 116],i2)@_",  # getbit(-1,-1)
    "err:ca[100, 111, 109, 97, 105, 110, 95, 101, 114, 114, 111, 114]/2(a[110, 111, 116, 95, 108, 101, 115, 115, 95, 116, 104, 97, 110, 95, 122, 101, 114, 111],i-1)@ca[47]/2(a[98, 105, 116],i2)@_",  # getbit(-2^70,-1)
    "ok:i0",  # getbit(-5,2^70)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[105, 110, 116, 101, 103, 101, 114],F4004000000000000)@ca[47]/2(a[98, 105, 116],i2)@_",  # getbit(2.5,1)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[105, 110, 116, 101, 103, 101, 114],F3ff8000000000000)@ca[47]/2(a[98, 105, 116],i2)@_",  # getbit(5,1.5)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[105, 110, 116, 101, 103, 101, 114],F4000000000000000)@ca[47]/2(a[98, 105, 116],i2)@_",  # getbit(2.0,1)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[105, 110, 116, 101, 103, 101, 114],F3ff0000000000000)@ca[47]/2(a[98, 105, 116],i2)@_",  # getbit(5,1.0)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[105, 110, 116, 101, 103, 101, 114],q1r2)@ca[47]/2(a[98, 105, 116],i2)@_",  # getbit(1r2,1)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[105, 110, 116, 101, 103, 101, 114],q1r2)@ca[47]/2(a[98, 105, 116],i2)@_",  # getbit(5,1r2)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # getbit(1.5NaN,1)
    "err:ca[101, 118, 97, 108, 117, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]/1(a[117, 110, 100, 101, 102, 105, 110, 101, 100])@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # getbit(1,1.5NaN)
    "err:a[105, 110, 115, 116, 97, 110, 116, 105, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # getbit(_,1)
    "err:a[105, 110, 115, 116, 97, 110, 116, 105, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # getbit(1,_)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[101, 118, 97, 108, 117, 97, 98, 108, 101],ca[47]/2(a[97],i0))@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # getbit(a,1)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[101, 118, 97, 108, 117, 97, 98, 108, 101],ca[47]/2(a[97],i0))@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # getbit(1,a)
    "err:a[105, 110, 115, 116, 97, 110, 116, 105, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # getbit(_,_)
    "ok:i1",  # getbit(+(2,3),-(3,1))
    "ok:i1",  # +(getbit(5,0),getbit(5,1))
    "ok:i24",  # powm(2,10,1000)
    "ok:i0",  # powm(2,10,1024)
    "ok:i1024",  # powm(2,10,1025)
    "ok:i1",  # powm(2,0,5)
    "ok:i1",  # powm(0,0,5)
    "ok:i0",  # powm(0,0,1)
    "ok:i0",  # powm(0,5,7)
    "ok:i0",  # powm(3,100,1)
    "ok:i1",  # powm(3,100,2)
    "ok:i3",  # powm(2,3,5)
    "ok:i6",  # powm(5,3,7)
    "ok:i976371285",  # powm(2,100,1000000007)
    "ok:i549755813888",  # powm(2,100,2305843009213693951)
    "ok:i652541198",  # powm(123456789,987654321,1000000007)
    "ok:i0",  # powm(INT64_MAX,INT64_MAX,INT64_MAX)
    "ok:i0",  # powm(INT64_MAX,2,INT64_MAX)
    "ok:i1",  # powm(INT64_MAX,2,4611686018427387904)
    "ok:i24",  # powm(2^70,3,1000)
    "ok:i61",  # powm(2^70,2^70,97)
    "ok:i61",  # powm(2,2^70,97)
    "ok:i8",  # powm(2,3,1180591620717411303425)
    "ok:i1180591620717411303424",  # powm(2^70,3,1180591620717411303425)
    "ok:i806875036",  # powm(10^30,10^30,1000000007)
    "ok:i8",  # powm(2,3,2^63)
    "ok:i8",  # powm(2,3,2^64)
    "err:ca[100, 111, 109, 97, 105, 110, 95, 101, 114, 114, 111, 114]/2(a[110, 111, 116, 95, 108, 101, 115, 115, 95, 116, 104, 97, 110, 95, 122, 101, 114, 111],i-2)@ca[47]/2(a[112, 111, 119, 109],i3)@_",  # powm(-2,3,5)
    "err:ca[100, 111, 109, 97, 105, 110, 95, 101, 114, 114, 111, 114]/2(a[110, 111, 116, 95, 108, 101, 115, 115, 95, 116, 104, 97, 110, 95, 122, 101, 114, 111],i-3)@ca[47]/2(a[112, 111, 119, 109],i3)@_",  # powm(2,-3,5)
    "err:ca[100, 111, 109, 97, 105, 110, 95, 101, 114, 114, 111, 114]/2(a[110, 111, 116, 95, 108, 101, 115, 115, 95, 116, 104, 97, 110, 95, 111, 110, 101],i0)@ca[47]/2(a[112, 111, 119, 109],i3)@_",  # powm(2,3,0)
    "err:ca[100, 111, 109, 97, 105, 110, 95, 101, 114, 114, 111, 114]/2(a[110, 111, 116, 95, 108, 101, 115, 115, 95, 116, 104, 97, 110, 95, 111, 110, 101],i-5)@ca[47]/2(a[112, 111, 119, 109],i3)@_",  # powm(2,3,-5)
    "err:ca[100, 111, 109, 97, 105, 110, 95, 101, 114, 114, 111, 114]/2(a[110, 111, 116, 95, 108, 101, 115, 115, 95, 116, 104, 97, 110, 95, 122, 101, 114, 111],i-2)@ca[47]/2(a[112, 111, 119, 109],i3)@_",  # powm(-2,-3,0)
    "err:ca[100, 111, 109, 97, 105, 110, 95, 101, 114, 114, 111, 114]/2(a[110, 111, 116, 95, 108, 101, 115, 115, 95, 116, 104, 97, 110, 95, 122, 101, 114, 111],i-1180591620717411303424)@ca[47]/2(a[112, 111, 119, 109],i3)@_",  # powm(-2^70,3,5)
    "err:ca[100, 111, 109, 97, 105, 110, 95, 101, 114, 114, 111, 114]/2(a[110, 111, 116, 95, 108, 101, 115, 115, 95, 116, 104, 97, 110, 95, 122, 101, 114, 111],i-1180591620717411303424)@ca[47]/2(a[112, 111, 119, 109],i3)@_",  # powm(2,-2^70,5)
    "err:ca[100, 111, 109, 97, 105, 110, 95, 101, 114, 114, 111, 114]/2(a[110, 111, 116, 95, 108, 101, 115, 115, 95, 116, 104, 97, 110, 95, 111, 110, 101],i-1180591620717411303424)@ca[47]/2(a[112, 111, 119, 109],i3)@_",  # powm(2,3,-2^70)
    "err:ca[100, 111, 109, 97, 105, 110, 95, 101, 114, 114, 111, 114]/2(a[110, 111, 116, 95, 108, 101, 115, 115, 95, 116, 104, 97, 110, 95, 111, 110, 101],i0)@ca[47]/2(a[112, 111, 119, 109],i3)@_",  # powm(0,0,0)
    "err:ca[100, 111, 109, 97, 105, 110, 95, 101, 114, 114, 111, 114]/2(a[110, 111, 116, 95, 108, 101, 115, 115, 95, 116, 104, 97, 110, 95, 122, 101, 114, 111],i-1)@ca[47]/2(a[112, 111, 119, 109],i3)@_",  # powm(-1,0,1)
    "err:ca[100, 111, 109, 97, 105, 110, 95, 101, 114, 114, 111, 114]/2(a[110, 111, 116, 95, 108, 101, 115, 115, 95, 116, 104, 97, 110, 95, 122, 101, 114, 111],i-1)@ca[47]/2(a[112, 111, 119, 109],i3)@_",  # powm(1,-1,1)
    "err:ca[100, 111, 109, 97, 105, 110, 95, 101, 114, 114, 111, 114]/2(a[110, 111, 116, 95, 108, 101, 115, 115, 95, 116, 104, 97, 110, 95, 111, 110, 101],i-1)@ca[47]/2(a[112, 111, 119, 109],i3)@_",  # powm(2,3,-1)
    "err:a[105, 110, 115, 116, 97, 110, 116, 105, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # powm(_,3,5)
    "err:a[105, 110, 115, 116, 97, 110, 116, 105, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # powm(2,_,5)
    "err:a[105, 110, 115, 116, 97, 110, 116, 105, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # powm(2,3,_)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[101, 118, 97, 108, 117, 97, 98, 108, 101],ca[47]/2(a[97],i0))@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # powm(a,3,5)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[101, 118, 97, 108, 117, 97, 98, 108, 101],ca[47]/2(a[97],i0))@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # powm(2,a,5)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[101, 118, 97, 108, 117, 97, 98, 108, 101],ca[47]/2(a[97],i0))@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # powm(2,3,a)
    "err:a[105, 110, 115, 116, 97, 110, 116, 105, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # powm(_,_,_)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[105, 110, 116, 101, 103, 101, 114],F4000000000000000)@ca[47]/2(a[112, 111, 119, 109],i3)@_",  # powm(2.0,3,5)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[105, 110, 116, 101, 103, 101, 114],F4008000000000000)@ca[47]/2(a[112, 111, 119, 109],i3)@_",  # powm(2,3.0,5)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[105, 110, 116, 101, 103, 101, 114],F4014000000000000)@ca[47]/2(a[112, 111, 119, 109],i3)@_",  # powm(2,3,5.0)
    "ok:i24",  # powm(+(1,1),*(5,2),+(500,500))
    "ok:i25",  # +(powm(2,10,1000),1)
    "ok:i1",  # eval(1)
    "ok:i0",  # eval(0)
    "ok:i-1",  # eval(-1)
    "ok:i-9223372036854775808",  # eval(INT64_MIN)
    "ok:i1180591620717411303424",  # eval(2^70)
    "ok:F3ff8000000000000",  # eval(1.5)
    "ok:F8000000000000000",  # eval(-0.0)
    "ok:F7ff0000000000000",  # eval(1.0Inf)
    "ok:F7ff8000000000000",  # eval(1.5NaN)
    "ok:q1r3",  # eval(1r3)
    "err:a[105, 110, 115, 116, 97, 110, 116, 105, 97, 116, 105, 111, 110, 95, 101, 114, 114, 111, 114]@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # eval(_)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[101, 118, 97, 108, 117, 97, 98, 108, 101],ca[47]/2(a[97],i0))@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # eval(a)
    "ok:i3",  # eval(+(1,2))
    "ok:i3",  # eval(eval(3))
    "ok:i3",  # +(eval(1),2)
    "ok:F4000000000000000",  # eval(max(1,2.0))
    "ok:F3fd5555555555555",  # eval(/(1,3))
    "ok:q1r3",  # eval(rdiv(1,3))
    "ok:F400921fb54442d18",  # eval(pi)
    "ok:F7ff0000000000000",  # eval(inf)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[101, 118, 97, 108, 117, 97, 98, 108, 101],ca[47]/2(a[102, 111, 111],i1))@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # eval(foo(1))
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[101, 118, 97, 108, 117, 97, 98, 108, 101],ca[47]/2(a[101, 118, 97, 108],i2))@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # eval(1,2)
    "err:ca[116, 121, 112, 101, 95, 101, 114, 114, 111, 114]/2(a[101, 118, 97, 108, 117, 97, 98, 108, 101],ca[47]/2(a[102, 111, 111],i0))@ca[58]/2(a[115, 121, 115, 116, 101, 109],ca[47]/2(a[105, 115],i2))@_",  # eval(foo)
    "ok:q1r2",  # eval(rational(0.5))
    "ok:i36",  # +(lcm(4,6),powm(2,10,1000))
    "ok:i4",  # denominator(rationalize(0.25))
    "ok:F3fb999999999999a",  # maxr(rationalize(0.1),0.1)
    "ok:q1r10",  # minr(rationalize(0.1),0.1)
    "ok:i0",  # cmpr(rational(0.1),0.1)
    "ok:i-1",  # cmpr(rationalize(0.1),0.1)
    "ok:i1",  # lsb(lcm(6,10))
    "ok:i4",  # popcount(lcm(6,10))
    "ok:i1",  # getbit(lcm(4,6),lsb(8))
    "ok:F0",  # sinh(log10(1))
    "ok:F0",  # erf(tanh(0))
    "ok:i0",  # rational(sinh(0))
    "ok:F3ff61558620b90fe",  # log10(powm(2,10,1000))
    "ok:F401326643c4479c9",  # lgamma(lcm(2,3))
    "ok:q1r3",  # rdiv(+(rational(0.5),rational(0.5)),3)
    "ok:i1",  # numerator(+(rational(0.5),rational(0.5)))
    "ok:i1",  # denominator(+(rational(0.5),rational(0.5)))
    "ok:q2r3",  # *(2,rdiv(1,3))
    "ok:F3feaaaaaaaaaaaaa",  # +(rdiv(1,3),0.5)
    "ok:q3r2",  # rdiv(rdiv(1,2),rdiv(1,3))
    "ok:q1r3"  # abs(rdiv(-1,3))
]

const _A_ARITHC_FUNCS = (
    :rational, :numerator, :denominator, :rationalize, :rdiv, :cmpr, :maxr, :minr, :lcm,
    :nexttoward, :sinh, :cosh, :tanh, :asinh, :acosh, :atanh, :lgamma, :erf, :erfc, :log10,
    :lsb, :popcount, :getbit, :powm, :eval
)

@testset "arith-c: the 28 functions of pl-arith.c's table added — swipl's answers (pinned)" begin
    @test length(_A_ARITHC_CASES) == length(_A_ARITHC_EXPECT)
    got = [_aoutcome_of(c) for c in _A_ARITHC_CASES]
    bad = [k for k in eachindex(got) if got[k] != _A_ARITHC_EXPECT[k]]
    for k in bad[1:min(end, 8)]
        src = _asrc(_A_ARITHC_CASES[k])
        println(stderr, "  arith-c DIVERGES: ", src, "\n    kernel ", got[k])
        println(stderr, "    swipl  ", _A_ARITHC_EXPECT[k])
    end
    @test isempty(bad)
    # the guard has teeth: every function has a case that succeeds and one that raises (the rows that
    # kill the mutants — lcm via gcd, popcount/lsb swapped, sinh/cosh swapped, rdiv truncating,
    # nexttoward's direction, cmpr's sign — are among them), the constants are cases, as atoms and as
    # compounds with no arguments, and every family reaches the type it returns
    head(c) = c isa Tuple ? c[1] : nothing
    for f in _A_ARITHC_FUNCS
        ks = [k for k in eachindex(_A_ARITHC_CASES) if head(_A_ARITHC_CASES[k]) === f]
        @test any(k -> startswith(_A_ARITHC_EXPECT[k], "ok:"), ks)
        @test any(k -> startswith(_A_ARITHC_EXPECT[k], "err:"), ks)
    end
    for c in (:epsilon, (:epsilon,), :inf, (:inf,), :nan, (:nan,))
        k = findfirst(==(c), _A_ARITHC_CASES)
        @test k !== nothing && startswith(_A_ARITHC_EXPECT[k], "ok:F")
    end
    @test count(startswith("ok:F"), _A_ARITHC_EXPECT) > 250 &&
        count(startswith("ok:i"), _A_ARITHC_EXPECT) > 300 &&
        count(startswith("ok:q"), _A_ARITHC_EXPECT) > 50 &&
        count(startswith("err:"), _A_ARITHC_EXPECT) > 200
end

# random_float/0: swipl's generator is not reproducible (no set_random/1 yet), so only the range, the
# spread, the 53-bit fraction and the two forms (an atom, and a compound with no arguments) are checked.
@testset "arith-c: random_float/0 — in (0.0, 1.0), spread, a 53-bit fraction" begin
    draw(k) = [lk_value(_ais(_as(:random_float))) for _ in 1:k]
    d = draw(400)
    @test all(v -> v isa Float64 && 0.0 < v < 1.0, d)
    @test length(Set(d)) > 395
    @test 0.4 < sum(d) / length(d) < 0.6
    @test count(<(0.5), d) in 150:250
    @test count(v -> (v * 2.0^53) % 2.0 == 1.0, d) > 100       # the lowest of 53 bits is used
    @test all(
        v -> 0.0 < v < 1.0, [lk_value(_ais(_af(:random_float))) for _ in 1:50]
    )
    @test all(
        v -> 1.0 < v < 2.0,
        [lk_value(_ais(_af(:+, _as(:random_float), _ag(1)))) for _ in 1:50]
    )
end

# roundtoward/2 is NOT PORTED: the kernel has no rounding mode but to nearest, so a call is not
# evaluable (swipl evaluates it, `X is roundtoward(2.5, to_nearest)` is 2.5, and sets the hardware mode
# for its first argument). The arguments are evaluated first, the last one first: an atom mode is
# `to_nearest/0`, not evaluable, a number reaches the function itself. A KNOWN DIFFERENCE, pinned to
# the kernel's answer; the live testset at the end of this file pins swipl's. Checklist: when the
# rounding modes land (a subsystem of its own), port `ar_roundtoward` and `set_roundtoward` and move
# these rows to `_A_ARITHC_CASES`.
@testset "arith-c: roundtoward/2 is not evaluable (NOT PORTED, known difference)" begin
    isctx = _aenc(_af(:(:), _as(:system), _af(:/, _as(:is), _ag(2))))
    ev(f, n) = _aenc(_af(:type_error, _as(:evaluable), _af(:/, _as(f), _ag(n))))
    @test _aoutcome_of((:roundtoward, 2.5, 3)) ==
        "err:" * ev(:roundtoward, 2) * "@" * isctx * "@_"
    @test _aoutcome_of((:roundtoward, 2.5, :to_nearest)) ==
        "err:" * ev(:to_nearest, 0) * "@" * isctx * "@_"
end

# ── the live differential ────────────────────────────────────────────────────────────────────────
const _A_LEAVES = Any[
    0, 1, -1, 2, 3, -7, 100, 2 ^ 53 + 1, 2 ^ 56 - 1, 2 ^ 56, -2 ^ 56, 2 ^ 62,
    typemax(Int64), typemin(Int64),
    typemax(Int64) - 1, big(2) ^ 64, -big(2) ^ 70, big(10) ^ 21, 0.0, -0.0, 1.5, -2.25, 0.1,
    1.0e300,
    1.0e-300, 1 // big(3), -5 // big(7), big(2) ^ 70 // 3, "a", "z"
]
const _A_BAD = ("var", "atom", "nil", "unknown", "ab", "code")    # planted, rarely
# the functions the generator draws: + - * and unary - + (V6c), then arith-a's, arith-b's and arith-c's
const _A_OPS = (
    (:+, 2), (:-, 2), (:*, 2), (:-, 1), (:+, 1), (:/, 2), (:(//), 2), (:mod, 2), (:rem, 2),
    (:div, 2), (:min, 2), (:max, 2), (:copysign, 2), (:gcd, 2), (Symbol("/\\"), 2),
    (Symbol("\\/"), 2), (:xor, 2), (:abs, 1), (:sign, 1), (:msb, 1), (Symbol("\\"), 1),
    (:integer, 1), (:round, 1), (:truncate, 1), (:float, 1), (:floor, 1), (:ceiling, 1),
    (:ceil, 1), (:float_integer_part, 1), (:float_fractional_part, 1),
    # arith-b's (`**` and `^` are drawn below, with a small exponent)
    (:sqrt, 1), (:exp, 1), (:log, 1), (:sin, 1), (:cos, 1), (:tan, 1), (:asin, 1),
    (:acos, 1),
    (:atan, 1), (:atan, 2), (:atan2, 2),
    # arith-c's (`random_float`, `powm` and the constants are not drawn: not reproducible, three
    # arguments, or none)
    (:rational, 1), (:numerator, 1), (:denominator, 1), (:rationalize, 1), (:rdiv, 2),
    (:cmpr, 2), (:maxr, 2), (:minr, 2), (:lcm, 2), (:nexttoward, 2), (:sinh, 1), (:cosh, 1),
    (:tanh, 1), (:asinh, 1), (:acosh, 1), (:atanh, 1), (:lgamma, 1), (:erf, 1), (:erfc, 1),
    (:log10, 1), (:lsb, 1), (:popcount, 1), (:getbit, 2), (:eval, 1)
)

"A random expression and its swipl source text."
function _aexpr(rng, depth::Int)::Tuple{_A, String}
    r = rand(rng)
    if depth >= 3 || r < 0.35
        if rand(rng) < 0.06
            b = rand(rng, _A_BAD)
            b == "var" && return (_av(), "_")
            b == "atom" && return (_as(:a), "a")
            b == "nil" && return (mk_nil(_A), "[]")
            b == "unknown" && return (_af(:foo, _ag(1)), "foo(1)")
            b == "ab" && return (_ag("ab"), "\"ab\"")
            return (_af("[|]", _ag(97), mk_nil(_A)), "[97]")
        end
        v = rand(rng, _A_LEAVES)
        t = _ag(v)
        src = if v isa Rational
            string(numerator(v), "r", denominator(v))
        elseif v isa String
            "\"" * v * "\""
        elseif v isa AbstractFloat
            repr(v)
        else
            string(v)
        end
        return (t, src)
    end
    if rand(rng) < 0.15                                     # a shift (V8): a small amount
        a = _aexpr(rng, depth + 1)
        k = rand(rng, (-70, -3, -1, 0, 1, 2, 7, 63, 64, 65, 100))
        op = rand(rng, (:>>, :<<))
        return (_af(op, a[1], _ag(k)), string(op, "(", a[2], ",", k, ")"))
    end
    if rand(rng) < 0.1                                      # ** or ^ (arith-b): a small exponent
        a = _aexpr(rng, depth + 1)
        k = rand(
            rng,
            (-3, -1, 0, 1, 2, 3, 5, 0.5, 2.0, -0.5, 1 // big(2), -1 // big(3), 2 // big(3))
        )
        ksrc = k isa Rational ? string(numerator(k), "r", denominator(k)) : repr(k)
        op = rand(rng, (_A_POW2, :^))
        return (_af(op, a[1], _ag(k)), string(op, "(", a[2], ",", ksrc, ")"))
    end
    op = rand(rng, _A_OPS)
    args = [_aexpr(rng, depth + 1) for _ in 1:op[2]]
    return (_af(op[1], first.(args)...), string(op[1], "(", join(last.(args), ","), ")"))
end

const _A_SWIPL = (
    get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
)
const _A_SWIPL_REQUIRED = get(ENV, "LOGICKERNEL_REQUIRE_SWIPL", "") == "1"

const _A_DRIVER = raw"""
enc(X) :- var(X), !, write('_').
enc(X) :- integer(X), !, write(i), write(X).
enc(X) :- rational(X, N, D), !, format("q~wr~w", [N, D]).
enc(X) :- float(X), !, write(f), write(X).
enc(X) :- string(X), !, string_codes(X, Cs), write(s), enc_codes(Cs).
enc([]) :- !, write(nil).
enc(X) :- atom(X), !, atom_codes(X, Cs), write(a), enc_codes(Cs).
enc(X) :- compound_name_arguments(X, N, As), length(As, L),
    write(c), ( N == [] -> write(nil) ; atom_codes(N, Cs), write(a), enc_codes(Cs) ),
    format("/~w(", [L]), enc_args(As), write(')').
enc_args([]).
enc_args([A]) :- !, enc(A).
enc_args([A|As]) :- enc(A), write(','), enc_args(As).
enc_codes(Cs) :- write('['), atomic_list_concat(Cs, ', ', A), write(A), write(']').
ctx(context(P, Msg), P, Msg) :- !.
ctx(_, _, _).
err(F, C) :- ctx(C, P, Msg), write('err:'), enc(F), write('@'), enc(P), write('@'), enc(Msg), nl.
is_(E) :- catch((X is E, write('ok:'), enc(X), nl), error(F, C), err(F, C)).
cmp(G) :- catch((call(G) -> writeln(true) ; writeln(false)), error(F, C), err(F, C)).
"""

if _A_SWIPL !== nothing
    @testset "is/2 and the comparisons == live swipl (random expressions)" begin
        rng = Xoshiro(20261008)
        exprs = [_aexpr(rng, 0) for _ in 1:600]
        ops = (:<, :>, Symbol("=<"), Symbol(">="), Symbol("=\\="), Symbol("=:="))
        cmps = [(rand(rng, ops), _aexpr(rng, 1), _aexpr(rng, 1)) for _ in 1:300]
        ours = String[]
        for (t, _) in exprs
            push!(ours, _aoutcome(_arun(:is, _A[_av(), t])...))
        end
        for (op, (a, _), (b, _)) in cmps
            rc, out = _arun(op, _A[a, b])
            push!(
                ours,
                if rc == LKA.PL_S_EXCEPTION
                    _aoutcome(rc, out)
                else
                    string(rc != LKA.PL_S_FALSE)
                end
            )
        end
        prog = IOBuffer()
        print(prog, _A_DRIVER)
        print(prog, "run :- ")
        for (_, s) in exprs
            print(prog, "is_(", s, "), ")
        end
        for (op, (_, sa), (_, sb)) in cmps
            print(
                prog,
                "cmp('",
                replace(string(op), "\\" => "\\\\"),
                "'(",
                sa,
                ", ",
                sb,
                ")), "
            )
        end
        println(prog, "true.\n:- initialization((run, halt)).")
        text = mktempdir() do d
            f = joinpath(d, "a.pl")
            write(f, String(take!(prog)))
            read(`swipl -q $f`, String)
        end
        theirs = String[]
        # a float, anywhere — a value or inside an error term: swipl prints the shortest text, `f…`;
        # compare its bit pattern, as the kernel's side prints it
        fbits(m) = "F" * string(reinterpret(UInt64, parse(Float64, m[2:end])); base=16)
        for l in split(strip(text), '\n')
            push!(
                theirs, replace(String(l), r"f-?[0-9]+\.[0-9]+(?:e[+-]?[0-9]+)?" => fbits)
            )
        end
        @test length(theirs) == length(ours)
        bad = [
            (k, ours[k], theirs[k]) for
            k in 1:min(length(ours), length(theirs)) if ours[k] != theirs[k]
        ]
        for (k, o, t) in bad[1:min(end, 5)]
            src = k <= length(exprs) ? exprs[k][2] : string(cmps[k - length(exprs)])
            println(stderr, "  DIVERGES: ", src, "\n    kernel ", o, "\n    swipl  ", t)
        end
        @test isempty(bad)
        nerr = count(startswith("err:"), ours)
        @info "arithmetic differential: $(length(exprs)) is/2 goals, $(length(cmps)) comparisons, $nerr errors"
        @test nerr > 0 && count(startswith("ok:i"), ours) > 0 &&
            count(startswith("ok:F"), ours) > 0 &&
            count(startswith("ok:q"), ours) > 0
    end
elseif _A_SWIPL_REQUIRED
    error(
        "LOGICKERNEL_REQUIRE_SWIPL=1 but `swipl` is not on PATH — the arithmetic differential would be skipped"
    )
else
    @info "ARITHMETIC DIFFERENTIAL NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI's analysis job."
    @testset "arithmetic differential skipped only where it is not required" begin
        @test !_A_SWIPL_REQUIRED
    end
end

# ── arith-a's pinned table == live swipl (so a pasted value cannot drift from the oracle) ────────
if _A_SWIPL !== nothing
    @testset "arith-a: the pinned answers == live swipl" begin
        prog = IOBuffer()
        print(prog, _A_DRIVER)
        print(prog, "run :- ")
        for c in _A_ARITHA_CASES
            print(prog, "is_(", _asrc(c), "), ")
        end
        println(prog, "true.\n:- initialization((run, halt)).")
        text = mktempdir() do d
            f = joinpath(d, "a.pl")
            write(f, String(take!(prog)))
            read(`swipl -q $f`, String)
        end
        theirs = [_afloat_bits(String(l)) for l in split(strip(text), '\n')]
        @test theirs == _A_ARITHA_EXPECT
    end
end

# ── arith-b's pinned table == live swipl ─────────────────────────────────────────────────────────
if _A_SWIPL !== nothing
    @testset "arith-b: the pinned answers == live swipl" begin
        prog = IOBuffer()
        print(prog, _A_DRIVER)
        print(prog, "run :- ")
        for c in _A_ARITHB_CASES
            print(prog, "is_(", _asrc(c), "), ")
        end
        for c in _A_TOOBIG
            print(prog, "is_(", _asrc(c), "), ")
        end
        println(prog, "true.\n:- initialization((run, halt)).")
        text = mktempdir() do d
            f = joinpath(d, "a.pl")
            write(f, String(take!(prog)))
            read(`swipl -q $f`, String)
        end
        theirs = [_afloat_bits(String(l)) for l in split(strip(text), '\n')]
        n = length(_A_ARITHB_CASES)
        @test theirs[1:n] == _A_ARITHB_EXPECT
        # an exponent too big: swipl's resource_error, as the kernel's since L1f f2 (the testset above)
        for k in (n + 1):length(theirs)
            @test startswith(theirs[k], "err:" * _aenc(_af(:resource_error, _as(:stack))))
        end
    end
end

# ── arith-c's pinned table == live swipl; and swipl's side of the known differences ──────────────
if _A_SWIPL !== nothing
    @testset "arith-c: the pinned answers == live swipl" begin
        prog = IOBuffer()
        print(prog, _A_DRIVER)
        print(prog, "run :- ")
        for c in _A_ARITHC_CASES
            print(prog, "is_(", _asrc(c), "), ")
        end
        println(prog, "true.\n:- initialization((run, halt)).")
        text = mktempdir() do d
            f = joinpath(d, "a.pl")
            write(f, String(take!(prog)))
            read(`swipl -q $f`, String)
        end
        theirs = [_afloat_bits(String(l)) for l in split(strip(text), '\n')]
        @test theirs == _A_ARITHC_EXPECT
    end
    @testset "arith-c: swipl's side of roundtoward/2" begin
        prog = IOBuffer()
        print(prog, _A_DRIVER)
        print(prog, "run :- ")
        for c in ((:roundtoward, 2.5, :to_nearest), (:roundtoward, 2.5, 3))
            print(prog, "is_(", _asrc(c), "), ")
        end
        println(prog, "true.\n:- initialization((run, halt)).")
        text = mktempdir() do d
            f = joinpath(d, "a.pl")
            write(f, String(take!(prog)))
            read(pipeline(`swipl -q $f`; stderr=devnull), String)
        end
        theirs = [_afloat_bits(String(l)) for l in split(strip(text), '\n')]
        # evaluated: the first argument, the mode set for it; a number is not a mode (a type error)
        @test theirs[1] == "ok:F4004000000000000" && startswith(theirs[2], "err:")
    end
end
