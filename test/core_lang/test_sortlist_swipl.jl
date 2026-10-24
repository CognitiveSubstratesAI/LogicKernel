# ORIGINAL: the built-ins boot/bags.pl's bagof/3 and setof/3 call (V9g-b) — sort/2, msort/2, keysort/2, length/2, is_list/1, functor/3, term_variables/2,3, ground/1 — against a LIVE swipl; upstream's tests of them (tests/core_lang/test_sort.pl, test_list.pl, test_term.pl) are mirrored by their own files, so this file shadows no upstream path.
# test/core_lang/test_sortlist_swipl.jl — pl-list.c nat_sort, pl_nat_sort, '$length'/2, is_list/1; pl-prims.c functor/3, term_variables/2,3, ground/1, '$skip_list'/3; boot/init.pl length/2, the code under test
using Test, LogicKernel, Random
# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const LK = LogicKernel
include(joinpath(@__DIR__, "rules_common.jl"))

# Every case is a predicate `<name>/1`; the differential compares its answers and determinism.
function _rsl_cases()
    X, Y, Z, L, M, E, A, B, N, T = (_rv(i) for i in 1:10)
    S = _rv(11)
    c3(g, k, r) = _rf("catch", g, k, r)
    eq(a, b) = _rf("=", a, b)
    pair(a, b) = _rf("-", a, b)
    T_ = _rs("true")
    err(g) = c3(g, _rf("error", E, Z), T_)              # the formal term only
    a, b, c = _rs("a"), _rs("b"), _rs("c")
    cases = Tuple{String, _R, _R}[
        # ── sort/2: the standard order, duplicates removed ──
        ("s1", L, _rf("sort", _rlist(c, a, b, a), L)),
        ("s2", L, _rf("sort", _rnil(), L)),
        ("s3", L, _rf("sort", _rlist(_rs("x")), L)),
        (
            "s4", L,
            _rf(
                "sort",
                _rlist(
                    _rf("f", _rs("x")), a, _rg(1), _rg(1.0), Z, _rg(2), b,
                    _rf("g", a, b), _rf("f", _rs("y")), _rnil(), _rs("A"), _rg(-3),
                    _rf("f", _rs("x")), _rg(2.5)
                ),
                L
            )
        ),
        (
            "s5",
            L,
            _rf("sort", _rlist(_rf("f", X), _rf("f", X), _rf("f", Y), _rf("f", X)), L)
        ),
        ("s6", E, err(_rf("sort", _rcons(a, T), L))),                       # a partial list
        ("s7", E, err(_rf("sort", _rs("foo"), L))),
        ("s8", E, err(_rf("sort", _rcons(a, b), L))),
        ("s9", X, _rf("sort", _rlist(b, a, b), _rlist(a, b))),
        ("s10", X, _rf("sort", _rlist(b, a), _rlist(b, a))),                # fails
        ("s11", L, _rf("sort", _rlist(_rg(3), _rg(1), _rg(2), _rg(1), _rg(3), _rg(0)), L)),
        (
            "s12", S,                                                       # a cyclic list
            _rconj(eq(L, _rcons(b, _rcons(a, L))), _rf("sort", L, S))
        ),
        (
            "s13", E,                                                       # … which msort/2 refuses
            _rconj(
                eq(L, _rcons(b, _rcons(a, L))),
                c3(_rf("msort", L, S), _rf("error", _rf("type_error", E, Y), Z), T_)
            )
        ),
        ("s14", L, _rconj(eq(X, _rg(2)), _rf("sort", _rlist(_rg(3), X, Y, _rg(1)), L))),
        # ── msort/2: duplicates kept ──
        ("m1", L, _rf("msort", _rlist(c, a, b, a), L)),
        ("m2", L, _rf("msort", _rnil(), L)),
        ("m3", L, _rf("msort", _rlist(_rf("f", X), _rf("f", X), b, b), L)),
        ("m4", E, err(_rf("msort", _rcons(a, T), L))),
        # ── keysort/2: by the key, stable ──
        (
            "k1", L,
            _rf(
                "keysort",
                _rlist(
                    pair(b, _rg(1)), pair(a, _rg(2)), pair(b, _rg(0)), pair(a, _rg(1)),
                    pair(c, _rg(9)), pair(a, _rg(0))
                ),
                L
            )
        ),
        ("k2", L, _rf("keysort", _rnil(), L)),
        ("k3", L, _rf("keysort", _rlist(pair(_rs("k"), _rs("v"))), L)),
        ("k4", E, err(_rf("keysort", _rlist(pair(a, _rg(1)), _rs("foo")), L))),
        ("k5", E, err(_rf("keysort", _rlist(pair(a, _rg(1)), X), L))),
        ("k6", E, err(_rf("keysort", _rlist(_rs("foo")), L))),              # one element: still a pair
        (
            "k7",
            L,
            _rf(
                "keysort", _rlist(pair(_rf("f", X), _rg(1)), pair(_rg(2), Y), pair(Z, a)), L
            )
        ),
        ("k8", E, err(_rf("keysort", _rs("foo"), L))),
        # ── sort/4 (pl-list.c; ported 2026-10-24, audit D-0127 item 2): the order names, keys by argument, error cases ──
        ("q1", L, _rf("sort", _rg(0), _rs("@>="), _rlist(c, a, b, a), L)),
        ("q2", L, _rf("sort", _rg(0), _rs("@<"), _rlist(c, a, b, a), L)),
        ("q3", L, _rf("sort", _rg(0), _rs("@>"), _rlist(c, a, b, a), L)),
        ("q4", L, _rf("sort", _rg(0), _rs("@=<"), _rlist(c, a, b, a), L)),
        ("q5", L, _rf("sort", _rg(0), _rs("<"), _rlist(_rg(3), _rg(1), _rg(2), _rg(1)), L)),
        (
            "q6",
            L,
            _rf("sort", _rg(0), _rs("=<"), _rlist(_rg(3), _rg(1), _rg(2), _rg(1)), L)
        ),
        ("q7", L, _rf("sort", _rg(0), _rs(">"), _rlist(_rg(3), _rg(1), _rg(2), _rg(1)), L)),
        (
            "q8",
            L,
            _rf("sort", _rg(0), _rs(">="), _rlist(_rg(3), _rg(1), _rg(2), _rg(1)), L)
        ),
        (
            "q9", L,
            _rf(
                "sort", _rg(1), _rs("@<"),
                _rlist(_rf("f", _rg(2), a), _rf("f", _rg(1), b), _rf("f", _rg(2), c)), L
            )
        ),
        (
            "q10", L,
            _rf(
                "sort", _rg(1), _rs("@=<"),
                _rlist(_rf("f", _rg(2), a), _rf("f", _rg(1), b), _rf("f", _rg(2), c)), L
            )
        ),
        (
            "q11", L,
            _rf(
                "sort", _rg(2), _rs("@>="),
                _rlist(_rf("f", _rg(1), b), _rf("f", _rg(2), a), _rf("f", _rg(3), b)), L
            )
        ),
        (
            "q12", L,
            _rf(
                "sort", _rlist(_rg(1), _rg(1)), _rs("@<"),
                _rlist(_rf("f", _rf("g", _rg(2)), a), _rf("f", _rf("g", _rg(1)), b)), L
            )
        ),
        (
            "q13", L,
            _rf(
                "sort", _rlist(_rg(2), _rg(1)), _rs("@>"),
                _rlist(
                    _rf("f", a, _rf("g", _rg(1), _rg(2))),
                    _rf("f", b, _rf("g", _rg(2), _rg(1)))
                ), L
            )
        ),
        ("q14", L, _rf("sort", _rlist(), _rs("@<"), _rlist(a, b), L)),     # an empty key list: the item itself
        ("q15", L, _rf("sort", _rg(1), _rs("@<"), _rnil(), L)),
        ("q16", L, _rf("sort", _rg(1), _rs("@<"), _rlist(_rf("f", a)), L)),   # one element: still checked
        ("q17", E, err(_rf("sort", _rg(3), _rs("@<"), _rlist(_rf("f", a)), L))),
        ("q18", E, err(_rf("sort", _rg(1), _rs("@<"), _rlist(a), L))),
        ("q19", E, err(_rf("sort", _rs("foo"), _rs("@<"), _rlist(_rf("f", a)), L))),
        ("q20", E, err(_rf("sort", _rg(-1), _rs("@<"), _rnil(), L))),
        ("q21", E, err(_rf("sort", _rs("a"), _rs("foo"), _rnil(), L))),
        ("q22", E, err(_rf("sort", _rg(1), _rg(5), _rlist(_rf("f", a)), L))),
        ("q23", E, err(_rf("sort", _rg(1), _rs("@<"), _rs("foo"), L))),
        ("q24", E, err(_rf("sort", _rg(1), _rs("@<"), X, L))),
        ("q25", E, err(_rf("sort", X, _rs("@<"), _rnil(), L))),
        ("q26", E, err(_rf("sort", _rlist(_rg(0)), _rs("@<"), _rlist(_rf("f", a)), L))),
        ("q27", E, err(_rf("sort", _rs("foo"), _rs("@<"), _rlist(a), L))),
        ("q28", E, err(_rf("sort", _rg(1), _rs("@<"), _rlist(_rf("f", a), X), L))),
        (
            "q29",
            L,
            _rf(
                "sort",
                _rg(1),
                _rs("@<"),
                _rlist(_rf("f", a, _rg(1)), _rf("f", a, _rg(2))),
                L
            )
        ),
        (
            "q30",
            E,
            err(_rf("sort", _rg(2), _rs("@>="), _rlist(_rf("f", a, b), _rf("g", c)), L))
        ),
        # ── many elements: the runs and their merges ──
        (
            "n1", _rf("r", N, A, B),
            _rconj(
                _rf("findall", X, _rf("down", _rg(300), X), L), _rf("sort", L, S),
                _rf("len", S, N), eq(S, _rcons(A, M)), _rf("last", S, B)
            )
        ),
        (
            "n2", _rf("r", N, S),
            _rconj(
                _rf(
                    "findall", Y,
                    _rconj(_rf("down", _rg(200), X), _rf("cls", X, Y)),
                    L
                ),
                _rf("sort", L, S), _rf("msort", L, M), _rf("len", M, N)
            )
        ),
        (
            "n3", S,
            _rconj(
                _rf(
                    "findall", pair(Y, X),
                    _rconj(_rf("down", _rg(40), X), _rf("cls", X, Y)),
                    L
                ),
                _rf("keysort", L, S)
            )
        ),
        # ── length/2 ──
        ("l1", N, _rf("length", _rlist(a, b, c), N)),
        ("l2", L, _rf("length", L, _rg(2))),
        ("l3", pair(L, N), _rconj(_rf("length", L, N), _rf(">=", N, _rg(2)), _rs("!"))),
        ("l4", T, _rf("length", _rcons(a, T), _rg(3))),
        (
            "l5",
            pair(T, N),
            _rconj(_rf("length", _rcons(a, T), N), _rf(">=", N, _rg(3)), _rs("!"))
        ),
        ("l6", E, c3(_rf("length", L, _rg(-1)), E, T_)),
        ("l7", E, c3(_rf("length", L, a), E, T_)),
        ("l8", E, c3(_rf("length", _rs("foo"), N), E, T_)),
        ("l9", E, c3(_rf("length", _rcons(a, b), N), E, T_)),
        ("l10", L, _rf("length", L, L)),                                    # fails
        ("l11", X, _rf("length", _rlist(a, b), _rg(3))),                    # fails
        ("l12", T, _rf("length", _rcons(a, _rcons(b, T)), _rg(1))),         # fails
        ("l13", N, _rf("length", _rnil(), N)),
        ("l14", L, _rf("length", L, _rg(0))),
        ("l15", E, c3(_rf("length", _rcons(a, b), _rg(2)), E, T_)),
        ("l16", E, c3(_rf("length", L, _rg(1.5)), E, T_)),
        # ── is_list/1, '$skip_list'/3, '$length'/2 ──
        ("i1", X, _rf("is_list", _rlist(a))),
        ("i2", T, _rf("is_list", _rcons(a, T))),                            # fails
        ("i3", X, _rf("is_list", _rs("foo"))),                              # fails
        ("i4", X, _rf("is_list", _rnil())),
        ("sk1", pair(N, T), _rf("\$skip_list", N, _rlist(a, b, c), T)),
        ("sk2", pair(N, T), _rf("\$skip_list", N, _rcons(a, _rcons(b, X)), T)),
        ("sk3", pair(N, T), _rf("\$skip_list", N, _rs("foo"), T)),
        ("sk4", pair(N, T), _rf("\$skip_list", N, _rcons(a, b), T)),
        ("sk5", X, _rf("\$skip_list", _rg(2), _rlist(a, b, c), T)),         # fails: 3 cells
        ("dl1", L, _rf("\$length", L, _rg(2))),
        ("dl2", L, _rf("\$length", L, _rg(0))),
        ("dl3", L, _rf("\$length", L, _rg(-1))),                            # fails
        ("dl4", E, c3(_rf("\$length", L, a), E, T_)),
        ("dl5", X, _rf("\$length", _rlist(a, X), _rg(2))),
        # ── functor/3 ──
        ("fu1", pair(N, A), _rf("functor", _rf("foo", a, b), N, A)),
        ("fu2", T, _rf("functor", T, _rs("foo"), _rg(3))),
        ("fu3", pair(N, A), _rf("functor", _rs("foo"), N, A)),
        ("fu4", pair(N, A), _rf("functor", _rg(1.5), N, A)),
        ("fu5", T, _rf("functor", T, _rs("foo"), _rg(0))),
        ("fu6", T, _rf("functor", T, _rg(5), _rg(0))),
        ("fu7", E, err(_rf("functor", T, N, _rg(2)))),
        ("fu8", E, err(_rf("functor", T, _rf("foo", a), _rg(1)))),
        ("fu9", E, err(_rf("functor", T, _rs("foo"), _rg(-1)))),
        ("fu10", E, err(_rf("functor", T, _rs("foo"), a))),
        ("fu11", E, err(_rf("functor", T, _rg(1.5), _rg(2)))),
        ("fu12", pair(N, A), _rf("functor", _rlist(a, b), N, A)),
        ("fu13", E, err(_rf("functor", T, _rs("foo"), A))),
        ("fu14", A, _rf("functor", _rf("foo", a), _rs("bar"), A)),          # fails
        ("fu15", X, _rf("functor", _rf("foo", a), _rs("foo"), _rg(2))),     # fails
        ("fu16", pair(N, A), _rf("functor", _rnil(), N, A)),
        (
            "fu17",
            pair(X, Y),
            _rconj(
                _rf("functor", T, _rs("pt"), _rg(2)), eq(T, _rf("pt", X, Y)), eq(X, _rg(1))
            )
        ),
        ("fu18", X, _rf("functor", _rf("foo", a, b), _rs("foo"), _rg(2))),
        # f3b-5a's gap rows on the arity read (swipl 10.1.18, probed 2026-10-22): a float arity
        # (`type_error(integer, 1.0)`) and the smallest Int64 (`domain_error(not_less_than_zero,
        # -9223372036854775808)`); fu13 is the unbound arity, and the big integers are below
        ("fu19", E, err(_rf("functor", T, _rs("foo"), _rg(1.0)))),
        ("fu20", E, err(_rf("functor", T, _rs("foo"), _rg(typemin(Int64))))),
        # ── term_variables/2,3 ──
        ("tv1", L, _rf("term_variables", _rf("f", X, _rf("g", Y, X), Z), L)),
        ("tv2", L, _rf("term_variables", _rf("f", a, _rg(1)), L)),
        ("tv3", pair(L, T), _rf("term_variables", _rf("f", X, Y), L, T)),
        ("tv4", A, _rf("term_variables", _rf("f", X, Y), _rlist(A))),       # fails: two variables
        (
            "tv5",
            pair(A, B),
            _rconj(_rf("term_variables", _rf("f", X, Y), _rlist(A, B)), eq(X, _rg(1)))
        ),
        ("tv6", L, _rconj(eq(X, _rf("g", Y)), _rf("term_variables", _rf("f", X, Z), L))),
        ("tv7", L, _rconj(eq(X, _rf("f", X, Y)), _rf("term_variables", X, L))),   # a rational tree
        ("tv8", L, _rf("term_variables", X, L)),
        (
            "tv9", N,
            _rconj(
                _rf("term_variables", _rf("f", X, Y, X), L),
                _rite(
                    _rf("==", L, _rlist(X, Y)),
                    eq(N, _rs("the_variables")),
                    eq(N, _rs("copies"))
                )
            )
        ),
        ("tv10", L, _rf("term_variables", _rf("f", X, Y), L, _rlist(a))),
        (
            "tv11",
            L,
            _rf("term_variables", _rlist(_rf("p", X), _rf("q", Y, X), Z, _rf("r", Y)), L)
        ),
        ("tv12", A, _rf("term_variables", _rf("f", X, Y), _rcons(A, _rs("foo")))),   # fails
        # ── ground/1 ──
        ("g1", X, _rf("ground", _rf("f", a, _rlist(_rg(1), b)))),
        ("g2", X, _rf("ground", _rf("f", a, X))),                           # fails
        ("g3", X, _rconj(eq(X, a), _rf("ground", _rf("f", X)))),
        ("g4", N, _rconj(eq(X, _rf("f", X)), _rf("ground", X), eq(N, _rs("ground")))),
        ("g5", N, _rconj(eq(X, _rf("f", X, Y)), _rf("ground", X))),         # fails
        ("g6", X, _rf("ground", a)),
        ("g7", X, _rf("ground", X))                                         # fails
    ]
    return cases
end

function _rsl_clauses()
    X, Y, Z, M, N, A = (_rv(i) for i in 21:26)
    cl = Tuple{_R, Union{Nothing, _R}}[
        (_rf("down", X, X), _rf(">=", X, _rg(1))),
        (
            _rf("down", X, Y),
            _rconj(
                _rf(">", X, _rg(1)), _rf("is", Z, _rf("-", X, _rg(1))), _rf("down", Z, Y)
            )
        ),
        (_rf("len", _rnil(), _rg(0)), nothing),
        (
            _rf("len", _rcons(X, Y), N),
            _rconj(_rf("len", Y, M), _rf("is", N, _rf("+", M, _rg(1))))
        ),
        (_rf("last", _rcons(X, _rnil()), X), nothing),
        (_rf("last", _rcons(X, _rcons(Y, Z)), A), _rf("last", _rcons(Y, Z), A)),
        # three classes of a number (the kernel's arithmetic has no mod/2 yet): many equal keys
        (_rf("cls", X, _rs("lo")), _rf("<", X, _rg(15))),
        (_rf("cls", X, _rs("mid")), _rconj(_rf(">=", X, _rg(15)), _rf("<", X, _rg(30)))),
        (_rf("cls", X, _rs("hi")), _rf(">=", X, _rg(30)))
    ]
    for (name, arg, body) in _rsl_cases()
        push!(cl, (_rf(name, arg), body))
    end
    return cl
end

_rsl_goals() = _R[_rf(name, _rv(50 + i)) for (i, (name, _, _)) in enumerate(_rsl_cases())]

@testset "sort/2, msort/2, keysort/2, length/2, functor/3, term_variables/2,3, ground/1: answers equal swipl's" begin
    clauses = _rsl_clauses()
    goals = _rsl_goals()
    db = _rdb(clauses)
    ours = String[]
    for g in goals
        for (a, det) in _rcall(
            db, g; at=(qid, k) -> (@test _rpools_live(db.ld) && db.ld.exception_term == 0)
        )
            push!(ours, a * (det ? " det" : " nondet"))
        end
        push!(ours, "end")
    end
    @test count(==("end"), ours) == length(goals)
    @test "s1([a,b,c]) det" in ours
    @test "m1([a,a,b,c]) det" in ours
    @test "k1([-(a,2),-(a,1),-(a,0),-(b,1),-(b,0),-(c,9)]) det" in ours      # stable
    @test "n1(r(300,1,300)) det" in ours
    @test "l2([_,_]) det" in ours
    @test "fu2(foo(_,_,_)) det" in ours
    @test "tv1([_,_,_]) det" in ours
    @test "tv9(the_variables) det" in ours
    if _R_SWIPL
        theirs = _rswipl(clauses, goals)
        @test ours == theirs
        if ours != theirs
            for k in 1:max(length(ours), length(theirs))
                get(ours, k, "—") == get(theirs, k, "—") && continue
                println(stderr, "  line ", k, "\n    kernel ", get(ours, k, "—"),
                    "\n    swipl  ", get(theirs, k, "—"))
            end
        end
    elseif _R_SWIPL_REQUIRED
        @test false
    end
end

# ── big integers (f3b-5a's gap rows: the arity read of functor/3, the length of '$length'/2) ──
# `_R` holds no BigInt, so these goals run through a small driver of their own, over a term type
# that does (the loader's and the readers' payload). A line is `true`, `fails` or
# `exception(<formal>)`, the formal as write_canonical/1 writes it; swipl prints the same lines.
const _RB = lk_term_type(Union{Int64, Float64, String, BigInt})
_rbs(x) = lk_sym(_RB, Symbol(x))
_rbg(v) = lk_gnd(_RB, v)
_rbv(k::Integer) = lk_var(_RB, UInt64(k))

"`t` as write_canonical/1 writes it (atoms, numbers, compounds), each variable by `var(t)`."
function _rb_text(t::_RB, var)::String
    k = kind(t)
    k === VAR && return var(t)
    k === SYM && return lk_atom_text(t)
    k === GND && return string(lk_value(t))
    return _rb_text(child(t, 1), var) * "(" *
           join((_rb_text(child(t, i), var) for i in 2:nchildren(t)), ",") * ")"
end

"The kernel's line for the built-in `name` called on `args`: `true`, `fails` or `exception(F)`."
function _rb_kernel(gd, ld, name::String, args::Vector{_RB})::String
    proc = LK.isCurrentProcedure(sym_key(_rbs(name)), length(args), LK.MODULE_system(gd))
    proc === nothing && return "no such built-in " * name * "/" * string(length(args))
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, length(args))
    pvm = LK.PutVarMap()  # one PutVarMap: these puts share their variables as one record does
    for (i, x) in enumerate(args)
        LK.putSlotValue!(ld, a + i, x, pvm)
    end
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    rc = LK.PL_next_solution(gd, ld, qid)
    out = if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
        "true"
    elseif rc == LK.PL_S_EXCEPTION
        ball = lk_answer(ld, LK.PL_exception(ld, qid))
        formal =
            if kind(ball) === EXPR && nchildren(ball) == 3 &&
                kind(child(ball, 1)) === SYM &&
                String(lk_name(child(ball, 1))) == "error"
                child(ball, 2)
            else
                ball
            end
        "exception(" * _rb_text(formal, v -> "_") * ")"
    else
        "fails"
    end
    LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
    return out
end

# (built-in, arguments, swipl's line, the kernel's line when it differs). swipl 10.1.18's lines
# are probed 2026-10-22 (`catch((G -> true ; fails), error(F, _), exception(F))`).
const _RB_CASES = let T = _rbv(1), L = _rbv(2), foo = _rbs("foo")
    big2(n) = big(2)^n
    Tuple{String, Vector{_RB}, String, Union{Nothing, String}}[
        (
            "functor", _RB[T, foo, _rbg(-big2(64))],
            "exception(domain_error(not_less_than_zero,-18446744073709551616))", nothing
        ),
        (
            "functor", _RB[T, foo, _rbg(big2(64))],
            "exception(representation_error(size_t))", nothing
        ),
        # KNOWN DIFFERENCE (design decision 5; an R2 checklist item, "functor/3 arity past
        # Int64"): 2^63 fits `uint64` (pl-error.c `mpz_to_uint64`, case 0), so swipl reads it as
        # the arity and raises resource_error(stack) when the term does not fit; the kernel's
        # `PL_get_size_ex` raises representation_error(size_t) for any integer past Int64
        # (pl-error.jl:690-695). This row pins the kernel's answer, swipl's is above.
        # The kernel's answer was confirmed by running this row on the base, 42d6205 (2026-10-22).
        (
            "functor", _RB[T, foo, _rbg(big2(63))],
            "exception(resource_error(stack))",
            "exception(representation_error(size_t))"
        ),
        ("\$length", _RB[L, _rbg(-big2(64))], "fails", nothing),
        (
            "\$length", _RB[L, _rbg(big2(64))],
            "exception(resource_error(stack))", nothing
        ),
        (
            "\$length", _RB[L, _rbg(big2(63))],
            "exception(resource_error(stack))", nothing
        )
    ]
end

"swipl's lines for the built-in calls of `_RB_CASES`."
function _rb_swipl()::Vector{String}
    goals = [
        "rb(" * _rb_text(_rbs(n), v -> "") * "(" *
        join((_rb_text(x, v -> "V" * string(var_key(v))) for x in args), ",") * "))" for
        (n, args, _, _) in _RB_CASES
    ]
    prog =
        join(
            [
                ":- style_check(-singleton).",
                "rb(G) :- catch(( G -> R = true ; R = fails ), error(F, _), R = exception(F)),",
                "         write_canonical(R), nl.",
                "main :- " * join(goals, ", ") * "."
            ],
            "\n"
        ) * "\n"
    mktempdir() do d
        f = joinpath(d, "rb.pl")
        write(f, prog)
        out = read(
            pipeline(
                ignorestatus(`swipl -q -g main -t halt $f`); stdin=devnull, stderr=devnull
            ),
            String
        )
        return [String(l) for l in split(strip(out), '\n') if !isempty(l)]
    end
end

@testset "functor/3 and '\$length'/2 on big integers: answers equal swipl's (f3b-5a)" begin
    gd = LK.PL_global_data{_RB}()
    ld = LK.PL_local_data{_RB}(gd)
    ours = [_rb_kernel(gd, ld, n, args) for (n, args, _, _) in _RB_CASES]
    for (i, (_, _, theirs, known)) in enumerate(_RB_CASES)
        @test ours[i] == something(known, theirs)               # swipl's line, or the pinned one
    end
    @test ld.exception_term == 0
    if _R_SWIPL
        theirs = _rb_swipl()
        @test theirs == [t for (_, _, t, _) in _RB_CASES]       # the pinned lines are swipl's
        for (i, (_, _, _, known)) in enumerate(_RB_CASES)
            known === nothing && @test ours[i] == get(theirs, i, "—")
        end
    elseif _R_SWIPL_REQUIRED
        @test false
    end
end

# White box: `nat_sort` against Julia's stable sort, on random keys — every length from 0 to 40
# (the run stack's merges change with the number of runs), with and without duplicates removed,
# ascending and descending.
@testset "nat_sort equals a stable sort of the keys, for every small length" begin
    rng = MersenneTwister(0x5eed)
    db = _RDB()
    ld = db.ld
    for len in 1:40, trial in 1:6
        keys = [rand(rng, 1:8) for _ in 1:len]
        for remove_dups in (false, true), order in (LK.SORT_ASC, LK.SORT_DESC)
            # f3-3: the records on cells — item i is argument i of `w(e(K1,1), …)` on the global
            # stack, its key that item's first argument (global positions, as
            # prolog_list_to_sort_list_cells lays them)
            fid = LK.PL_open_foreign_frame(ld)
            r = LK.PL_new_term_ref(ld)
            LK.putSlotValue!(
                ld, r + 1, _rf("w", (_rf("e", _rg(keys[i]), _rg(i)) for i in 1:len)...)
            )
            _, ww, _ = LK._deref_loc(ld, -(r + 1))
            items = [LK._deref_loc(ld, LK.valPtr(ww) + i) for i in 1:len]
            terms = [ip for (_, _, ip) in items]
            ks = [LK._deref_loc(ld, LK.valPtr(w) + 1)[3] for (_, w, _) in items]
            L = LK.List_Record_cells(
                [i < len ? i + 1 : 0 for i in 1:(len + 1)], copy(terms), copy(ks)
            )
            L.next[len + 1] = 0
            p = LK.nat_sort(ld, L, 1, remove_dups, order)
            @test L.term == terms && L.key == ks    # nat_sort relinks `next` only: record i is item i
            got = Tuple{Int, Int}[]
            while p != 0
                push!(got, (keys[p], p))            # record p's item: e(keys[p], p)
                p = L.next[p]
            end
            LK.PL_close_foreign_frame(ld, fid)
            want = sort(
                collect(zip(keys, 1:len)); by=first, rev=(order == LK.SORT_DESC),
                alg=MergeSort
            )
            if order == LK.SORT_DESC            # stable among equal keys in the INPUT order
                want = sort(collect(zip(keys, 1:len)); by=x -> -x[1], alg=MergeSort)
            end
            if remove_dups                      # the first of each run of equal keys stays
                want = [w for (i, w) in enumerate(want) if i == 1 || want[i - 1][1] != w[1]]
            end
            @test got == want
        end
    end
end
