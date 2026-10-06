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
#     float overflow); every value and every error — its formal, its context's predicate (swipl's
#     module stripped: Q-A) and its message — identical; and random comparisons with all six
#     operators;
#   * what the kernel decides alone, pinned: the interim for a term type that cannot hold a big
#     result (Q-AR1), `[Atom]` refused (Q-AR7), and the kernel-only terms (Q-AR5).
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
const _ALD = LKA.PL_local_data{_A}()

"Run the system predicate `name/n` on `args`: (rc, the first argument resolved, or the ball)."
function _arun(name, args::Vector{_A}; gd=_AGD, ld=_ALD)
    p = LKA.isCurrentProcedure(sym_key(_as(name)), length(args), LKA.MODULE_system(gd))
    fid = LKA.PL_open_foreign_frame(ld)
    a = LKA.PL_new_term_refs(ld, length(args))
    for (k, t) in enumerate(args)
        ld.slots[a + k] = t
    end
    qid = LKA.PL_open_query(
        gd, ld, nothing, LKA.PL_Q_CATCH_EXCEPTION | LKA.PL_Q_EXT_STATUS, p, a
    )
    rc = LKA.PL_next_solution(gd, ld, qid)
    out = if rc == LKA.PL_S_EXCEPTION
        LKA.resolve_term(ld, ld.slots[LKA.PL_exception(ld, qid) + 1])
    else
        LKA.resolve_term(ld, ld.slots[a + 1])
    end
    LKA.PL_close_query(ld, qid)
    LKA.PL_close_foreign_frame(ld, fid)
    return rc, out
end

"Run procedure `p` on `args`: (rc, the goal resolved — its arguments as answered — or the ball)."
function _arun_proc(gd, ld, p, args::Vector{_A})
    fid = LKA.PL_open_foreign_frame(ld)
    a = LKA.PL_new_term_refs(ld, length(args))
    for (k, t) in enumerate(args)
        ld.slots[a + k] = t
    end
    qid = LKA.PL_open_query(
        gd, ld, nothing, LKA.PL_Q_CATCH_EXCEPTION | LKA.PL_Q_EXT_STATUS, p, a
    )
    rc = LKA.PL_next_solution(gd, ld, qid)
    out = if rc == LKA.PL_S_EXCEPTION
        LKA.resolve_term(ld, ld.slots[LKA.PL_exception(ld, qid) + 1])
    else
        mk_expr(
            _A,
            _A[
                _as(:goal);
                [LKA.resolve_term(ld, ld.slots[a + k]) for k in eachindex(args)]
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
    # the context: the built-in (swipl: system:(is)/2, Q-A) and a message only where upstream gives one
    out = at(_af(:+, _ag("ab"), _ag(1)))
    @test occursin(_aenc(_af(:/, _as(:is), _ag(2))), out)
    @test endswith(out, "@" * _aenc(_as("\"x\" must hold one character")))
    @test endswith(at(_af(:+, _as(:a), _ag(1))), "@_")
    @test isctx(_af(:*, _ag(1.0e308), _ag(10)))                                 # float_overflow
end

# swipl raises `type_error(expression, T)` with the message 'cyclic term' (research probe p8). The
# kernel detects the cycle as upstream does, but the ball holds the rational tree, and a ball is
# RESOLVED into an interface term (decision 1), which a rational tree does not have (V5a1): the
# resolution raises a Julia `ArgumentError`, and the query closes (decision 1). Pinned as the interim
# for the user's open question Q-AR8.
@testset "cyclic: T = T+1, X is T — detected; its ball cannot be resolved (Q-AR8, pinned)" begin
    ld = LKA.PL_local_data{_A}()
    T1 = _av()
    LKA.Trail!(ld, var_key(T1), _af(:+, T1, _ag(1)))                             # T = T+1
    err = try
        _arun(:is, _A[_av(), T1]; ld=ld)
        nothing
    catch e
        e
    end
    @test err isa ArgumentError && occursin("rational tree", err.msg)
    @test ld.query == 0                                         # the query is closed
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
# interim is NotPortedError (the user's Q-B/Q-C). `1 << (1 << 40)` fails int_bits_ok. A right shift
# of a big integer floors (mpz_fdiv_q_2exp).
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
    gd, ld = LKA.PL_global_data{_A}(), LKA.PL_local_data{_A}()
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
@testset "the interims (Q-AR1, Q-AR7) and the kernel-only terms (Q-AR5), pinned" begin
    # Q-AR1: DefaultTerm holds no BigInt: a big result raises, loudly — never a wrong value
    D = DefaultTerm
    dgd, dld = LKA.PL_global_data{D}(), LKA.PL_local_data{D}()
    p = LKA.isCurrentProcedure(sym_key(mk_sym(D, :is)), 2, LKA.MODULE_system(dgd))
    fid = LKA.PL_open_foreign_frame(dld)
    a = LKA.PL_new_term_refs(dld, 2)
    dld.slots[a + 1] = mk_var(D, UInt64(1))
    dld.slots[a + 2] = mk_expr(D, D[mk_sym(D, :+), mk_gnd(D, typemax(Int64)), mk_gnd(D, 1)])
    qid = LKA.PL_open_query(dgd, dld, nothing, LKA.PL_Q_CATCH_EXCEPTION, p, a)
    @test_throws ArgumentError LKA.PL_next_solution(dgd, dld, qid)
    @test dld.query == 0                                       # the query is closed (decision 1)
    LKA.PL_close_foreign_frame(dld, fid)
    # Q-AR7: [Atom] needs the atom's text: refused
    @test_throws LKA.NotPortedError _arun(:is, _A[_av(), _af("[|]", _as(:a), mk_nil(_A))])
    @test lk_value(_ais(_af("[|]", _ag(97), mk_nil(_A)))) == 97                 # [Code] is ported
    # Q-AR5: a value of no SWI type is not evaluable; `$expr/n` is evaluated, then not evaluable
    O = lk_term_type(Union{Int64, Bool})
    ogd, old = LKA.PL_global_data{O}(), LKA.PL_local_data{O}()
    po = LKA.isCurrentProcedure(sym_key(lk_sym(O, :is)), 2, LKA.MODULE_system(ogd))
    fid = LKA.PL_open_foreign_frame(old)
    a = LKA.PL_new_term_refs(old, 2)
    old.slots[a + 1] = mk_var(O, UInt64(1))
    old.slots[a + 2] = lk_gnd(O, true)
    qid = LKA.PL_open_query(
        ogd, old, nothing, LKA.PL_Q_CATCH_EXCEPTION | LKA.PL_Q_EXT_STATUS, po, a
    )
    @test LKA.PL_next_solution(ogd, old, qid) == LKA.PL_S_EXCEPTION
    ball = LKA.resolve_term(old, old.slots[LKA.PL_exception(old, qid) + 1])
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

# ── the live differential ────────────────────────────────────────────────────────────────────────
const _A_LEAVES = Any[
    0, 1, -1, 2, 3, -7, 100, 2 ^ 53 + 1, 2 ^ 56 - 1, 2 ^ 56, -2 ^ 56, 2 ^ 62,
    typemax(Int64), typemin(Int64),
    typemax(Int64) - 1, big(2) ^ 64, -big(2) ^ 70, big(10) ^ 21, 0.0, -0.0, 1.5, -2.25, 0.1,
    1.0e300,
    1.0e-300, 1 // big(3), -5 // big(7), big(2) ^ 70 // 3, "a", "z"
]
const _A_BAD = ("var", "atom", "nil", "unknown", "ab", "code")    # planted, rarely

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
    op = rand(rng, ((:+, 2), (:-, 2), (:*, 2), (:-, 1), (:+, 1)))
    args = [_aexpr(rng, depth + 1) for _ in 1:op[2]]
    return (_af(op[1], first.(args)...), string(op[1], "(", join(last.(args), ","), ")"))
end

const _A_SWIPL = Sys.which("swipl")
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
ctx(context(M:P, Msg), P, Msg) :- atom(M), !.
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
