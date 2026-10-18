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
        LKA.resolve_term(ld, LogicKernel.slotValue(ld, LKA.PL_exception(ld, qid) + 1))
    else
        LKA.resolve_term(ld, LogicKernel.slotValue(ld, a + 1))
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
        LKA.resolve_term(ld, LogicKernel.slotValue(ld, LKA.PL_exception(ld, qid) + 1))
    else
        mk_expr(
            _A,
            _A[
                _as(:goal);
                [
                    LKA.resolve_term(ld, LogicKernel.slotValue(ld, a + k)) for
                    k in eachindex(args)
                ]
            ]
        )
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
    @test endswith(at(_af(:+, _as(:a), _ag(1))), "@_")
    @test isctx(_af(:*, _ag(1.0e308), _ag(10)))                                 # float_overflow
end

# swipl raises `type_error(expression, T)` with the message 'cyclic term' (research probe p8). The
# kernel detects the cycle as upstream does and raises with the REAL culprit, as upstream: since V5d
# a ball keeps its cycles (src/pl-fli.jl `copy_exception!`; user, 2026-10-07), which ends Q-AR8's
# placeholder. The ball is read under the bindings, where its cycle lives.
@testset "cyclic: T = T+1, X is T — type_error(expression, T), the real culprit (Q-AR8, since V5d)" begin
    ld = LKA.PL_local_data{_A}(_AGD)
    T1 = _av()
    LKA.Trail!(ld, var_key(T1), _af(:+, T1, _ag(1)))                             # T = T+1
    p = LKA.isCurrentProcedure(sym_key(_as(:is)), 2, LKA.MODULE_system(_AGD))
    fid = LKA.PL_open_foreign_frame(ld)
    a = LKA.PL_new_term_refs(ld, 2)
    pvm = LogicKernel.PutVarMap()  # one PutVarMap: these puts share their variables as one record does (L1b boundary, user 2026-10-14)
    LogicKernel.putSlotValue!(ld, a + 1, _av(), pvm)
    LogicKernel.putSlotValue!(ld, a + 2, T1, pvm)
    qid = LKA.PL_open_query(
        _AGD, ld, nothing, LKA.PL_Q_CATCH_EXCEPTION | LKA.PL_Q_EXT_STATUS, p, a
    )
    @test LKA.PL_next_solution(_AGD, ld, qid) == LKA.PL_S_EXCEPTION
    ball = LogicKernel.slotValue(ld, LKA.PL_exception(ld, qid) + 1)
    formal = LKA.deRef(ld, child(ball, 2))
    @test lk_name(child(formal, 1)) === :type_error &&
        lk_name(child(formal, 2)) === :expression
    @test LKA.compareStandard(ld, child(formal, 3), T1, true) == 0              # the culprit: T
    @test lk_eq(LKA.resolve_term(ld, child(ball, 3)),
        _af(
            :context, _af(:(:), _as(:system), _af(:/, _as(:is), _ag(2))), _as("cyclic term")
        ))
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
# even of a negative number. A left one is int_too_big; swipl raises resource_error, and the
# interim is NotPortedError (until G1, as decided since Q-C). `1 << (1 << 40)` fails int_bits_ok.
# A right shift of a big integer floors (mpz_fdiv_q_2exp).
@testset "integer size, shifts too far, the floor of a right shift (V8)" begin
    v(e) = lk_value(_ais(e))
    @test v(_af(:<<, _ag(1), _ag(20000))) == big(2)^20000
    @test v(_af(:>>, _ag(-1), _ag(big(2)^70))) == 0
    @test v(_af(:>>, _ag(5), _ag(big(2)^70))) == 0
    @test v(_af(:<<, _ag(-5), _ag(-big(2)^70))) == 0
    @test v(_af(:<<, _ag(0), _ag(big(2)^70))) == 0
    @test_throws LKA.NotPortedError _ais(_af(:<<, _ag(1), _ag(big(2)^70)))
    @test_throws LKA.NotPortedError _ais(_af(:<<, _ag(1), _ag(1 << 40)))
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
    ball = LKA.resolve_term(old, LogicKernel.slotValue(old, LKA.PL_exception(old, qid) + 1))
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

# ── the live differential ────────────────────────────────────────────────────────────────────────
const _A_LEAVES = Any[
    0, 1, -1, 2, 3, -7, 100, 2 ^ 53 + 1, 2 ^ 56 - 1, 2 ^ 56, -2 ^ 56, 2 ^ 62,
    typemax(Int64), typemin(Int64),
    typemax(Int64) - 1, big(2) ^ 64, -big(2) ^ 70, big(10) ^ 21, 0.0, -0.0, 1.5, -2.25, 0.1,
    1.0e300,
    1.0e-300, 1 // big(3), -5 // big(7), big(2) ^ 70 // 3, "a", "z"
]
const _A_BAD = ("var", "atom", "nil", "unknown", "ab", "code")    # planted, rarely
# the functions the generator draws: + - * and unary - + (V6c), then arith-a's
const _A_OPS = (
    (:+, 2), (:-, 2), (:*, 2), (:-, 1), (:+, 1), (:/, 2), (:(//), 2), (:mod, 2), (:rem, 2),
    (:div, 2), (:min, 2), (:max, 2), (:copysign, 2), (:gcd, 2), (Symbol("/\\"), 2),
    (Symbol("\\/"), 2), (:xor, 2), (:abs, 1), (:sign, 1), (:msb, 1), (Symbol("\\"), 1),
    (:integer, 1), (:round, 1), (:truncate, 1), (:float, 1), (:floor, 1), (:ceiling, 1),
    (:ceil, 1), (:float_integer_part, 1), (:float_fractional_part, 1)
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
