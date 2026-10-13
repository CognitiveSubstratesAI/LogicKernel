# ORIGINAL: bagof/3 and setof/3 (V9g-b) — boot/bags.pl's clauses over '$free_variable_set'/3 — against a LIVE swipl; upstream's tests of them are in tests/core_lang/test_bags.pl, mirrored when plunit runs (R2), so this file shadows no upstream path.
# test/core_lang/test_bagof_swipl.jl — pl-prims.c free_variables_loop, '$free_variable_set'/3; boot/bags.pl bagof/3, setof/3, pick/3 and their helpers, the code under test
using Test, LogicKernel, Random
# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const LK = LogicKernel
include(joinpath(@__DIR__, "rules_common.jl"))

# Every case is a predicate `<name>/1`; the differential compares its answers — for bagof/3 and
# setof/3 one per binding of the free variables, in the order of those bindings — and determinism.
function _rbg_cases()
    X, Y, Z, L, M, E, A, B, N, T = (_rv(i) for i in 1:10)
    W, G, V, K, Q = (_rv(i) for i in 11:15)
    bag(t, g, l) = _rf("bagof", t, g, l)
    set(t, g, l) = _rf("setof", t, g, l)
    hat(v, g) = _rf("^", v, g)
    c3(g, k, r) = _rf("catch", g, k, r)
    eq(a, b) = _rf("=", a, b)
    pair(a, b) = _rf("-", a, b)
    T_ = _rs("true")
    err(g) = c3(g, _rf("error", E, Z), T_)
    fvs(t, g, v) = _rf("\$free_variable_set", t, g, v)
    a, b, c = _rs("a"), _rs("b"), _rs("c")
    pairs = _rlist(
        pair(_rg(1), _rf("f", A)), pair(_rg(2), _rf("f", B)), pair(_rg(3), _rs("g"))
    )
    cases = Tuple{String, _R, _R}[
        # ── no free variable: one bag ──
        ("b1", L, bag(X, _rf("p", X), L)),
        ("b2", L, bag(X, _rs("fail"), L)),                                  # fails: no empty bag
        ("b3", L, bag(pair(X, Y), _rf("q", X, Y), L)),
        ("b4", L, bag(X, hat(Y, _rf("q", X, Y)), L)),
        ("b5", L, bag(X, _rconj(_rf("p", X), _rf(">", X, _rg(1))), L)),
        ("b6", L, bag(X, _rf("mem", X, _rlist(c, a, b, a)), L)),            # order and duplicates kept
        # ── free variables: a bag for each binding, in the order of the bindings ──
        ("b7", pair(Y, L), bag(X, _rf("q", X, Y), L)),
        ("b8", _rf("r", Y, Z, L), bag(X, _rf("r", X, Y, Z), L)),
        ("b9", pair(Z, L), bag(X, hat(Y, _rf("r", X, Y, Z)), L)),
        ("b10", L, bag(X, hat(Y, hat(Z, _rf("r", X, Y, Z))), L)),
        ("b11", pair(Y, L), bag(_rf("f", X, Z), _rf("q", X, Y), L)),        # Z is the template's
        ("b12", pair(X, L), bag(Z, _rf("p", X), L)),
        ("b13", pair(Y, L), _rconj(eq(Y, a), bag(X, _rf("q", X, Y), L))),   # bound when called
        ("b14", L, bag(X, hat(_rf("foo", Y, Z), _rf("r", X, Y, Z)), L)),    # a compound left of ^
        ("b15", pair(Y, L), bag(X, hat(_rg(3), _rf("q", X, Y)), L)),        # a non-variable left of ^
        # ── witnesses that are not ground: the variables of equal witnesses are made one ──
        ("b16", pair(W, L), bag(X, _rf("mem", pair(X, W), pairs), L)),
        ("b17", pair(W, L), set(X, _rf("mem", pair(X, W), pairs), L)),
        (
            "b18", _rf("r", W, V, L),
            bag(X,
                _rf(
                    "mem",
                    _rf("t", X, W, V),
                    _rlist(
                        _rf("t", _rg(1), A, B), _rf("t", _rg(2), B, A),
                        _rf("t", _rg(3), A, A),
                        _rf("t", _rg(4), K, Q)
                    )
                ), L)
        ),
        # ── setof/3 ──
        ("s1", L, set(X, hat(Y, _rf("q", X, Y)), L)),
        ("s2", pair(Y, L), set(X, _rf("q", X, Y), L)),
        ("s3", L, set(pair(A, N), _rf("age", N, A), L)),
        ("s4", pair(A, L), set(N, _rf("age", N, A), L)),
        ("s5", L, set(X, _rs("fail"), L)),                                  # fails
        (
            "s6",
            L,
            set(
                X,
                _rf(
                    "mem",
                    X,
                    _rlist(c, a, b, a, _rg(2), _rg(1.0), _rg(1), _rf("f", _rs("x")))
                ),
                L
            )
        ),
        ("s7", L, set(X, hat(N, _rf("age", X, N)), L)),
        ("s8", _rf("r", Y, Z, L), set(X, _rf("r", X, Y, Z), L)),
        (
            "s9", L,                        # fresh variables in the answers: their standard order
            set(
                _rf("t", X, Y, Z),
                _rf(
                    "mem",
                    _rf("t", X, Y, Z),
                    _rlist(
                        _rf("t", b, A, _rs("t1")), _rf("t", a, B, _rs("t2")),
                        _rf("t", b, A, _rs("t3"))
                    )
                ),
                L
            )
        ),
        # ── nested ──
        ("n1", L, bag(pair(X, M), hat(Y, bag(Y, _rf("q", X, Y), M)), L)),
        ("n2", L, set(pair(X, M), hat(Y, set(Y, _rf("q", X, Y), M)), L)),
        ("n3", pair(Y, L), bag(X, _rconj(_rf("q", X, Y), bag(Z, _rf("p", Z), M)), L)),
        # ── Module:Goal ──
        ("m1", L, bag(X, _rf(":", _rs("user"), _rf("p", X)), L)),
        ("m2", pair(Y, L), bag(X, _rf(":", _rs("user"), _rf("q", X, Y)), L)),
        ("m3", L, bag(X, hat(Y, _rf(":", _rs("user"), _rf("q", X, Y))), L)),
        ("m4", L, bag(X, _rf(":", _rs("user"), hat(Y, _rf("q", X, Y))), L)),
        (
            "m5",
            pair(Y, L),
            set(X, _rf(":", _rs("user"), _rf(":", _rs("user"), _rf("q", X, Y))), L)
        ),
        # ── the list is bound already ──
        ("l1", pair(A, B), bag(X, _rf("p", X), _rcons(A, B))),
        ("l2", X, bag(X, _rf("p", X), _rints(1:2))),                        # fails
        ("l3", Y, bag(X, _rf("q", X, Y), _rlist(_rg(2)))),                  # selects the binding
        ("l4", Y, set(X, _rf("q", X, Y), _rlist(_rg(1), _rg(3)))),
        # ── errors, and many answers ──
        ("e1", E, err(bag(X, G, L))),
        ("e2", E, err(bag(X, _rg(1), L))),
        ("e3", E, err(set(X, hat(Y, G), L))),
        (
            "g1", pair(K, N),
            _rconj(
                bag(X, _rconj(_rf("gen", _rg(1), _rg(300), X), _rf("cls", X, K)), L),
                _rf("len", L, N)
            )
        ),
        (
            "g2", pair(K, pair(A, B)),
            _rconj(
                set(X, _rconj(_rf("gen", _rg(1), _rg(300), X), _rf("cls", X, K)), L),
                eq(L, _rcons(A, M)), _rf("last", L, B)
            )
        ),
        # ── '$free_variable_set'/3 itself ──
        ("v1", pair(G, V), fvs(hat(X, hat(Y, _rf("foo", X, Y, Z))), G, V)),
        (
            "v2", pair(G, V),
            fvs(
                hat(
                    _rf("f", X, Y), _rconj(hat(Z, _rf("foo", X, Y, Z, W)), _rf("bar", W, Q))
                ),
                G,
                V
            )
        ),
        (
            "v3",
            pair(G, V),
            fvs(
                hat(X, _rf(":", _rs("m"), _rf(":", _rs("n"), hat(Y, _rf("foo", X, Y, Z))))),
                G,
                V
            )
        ),
        ("v4", pair(G, V), fvs(hat(X, _rg(1)), G, V)),
        ("v5", pair(G, V), fvs(hat(X, _rs("atom")), G, V)),
        ("v6", pair(G, V), fvs(_rs("foo"), G, V)),
        ("v7", pair(G, V), fvs(_rf("g", Z, X), G, V)),
        ("v8", pair(G, V), fvs(hat(X, _rnot(hat(Y, _rf("foo", X, Y, Z)))), G, V)),
        (
            "v9",
            pair(G, V),
            fvs(hat(X, _rconj(hat(Y, _rf("foo", X, Y)), hat(Z, _rf("bar", Z)))), G, V)
        ),
        (
            "v10",
            pair(G, V),
            _rconj(eq(A, _rf("f", K, Q)), fvs(hat(X, _rf("foo", A, A, X)), G, V))
        ),
        ("v11", V, fvs(hat(X, hat(Z, Z)), G, V)),                           # the goal is a variable
        ("v12", pair(G, V), fvs(hat(X, hat(_rg(3), _rf("foo", X, Z))), G, V)),
        ("v13", pair(G, V), fvs(hat(X, _rf(":", M, _rf("foo", X, Z))), G, V)),   # an unbound module
        ("v14", pair(G, V), fvs(hat(X, _rf(":", _rg(3), _rf("foo", X, Z))), G, V)),
        ("v15", pair(G, V), fvs(hat(X, hat(_rf("foo", X, Z), _rf("bar", Z, W))), G, V)),
        ("v16", pair(G, V), fvs(hat(X, _rf("foo", X, Y, Z)), G, _rf("v", a, B))),
        ("v17", G, fvs(hat(X, _rf("foo", X, Y)), G, _rs("v"))),             # fails: one free variable
        ("v18", pair(G, V), _rconj(eq(A, _rf("foo", Z)), fvs(hat(A, A), G, V))),
        ("v19", pair(G, V), fvs(hat(X, _rf("foo", Y, _rf("g", Y, Z), Z, K)), G, V)),
        (
            "v20",
            pair(G, V),
            _rconj(eq(Y, _rf("h", Z)), fvs(hat(X, _rf("foo", X, Y)), G, V))
        )
    ]
    return cases
end

function _rbg_clauses()
    X, Y, Z, M, N, A = (_rv(i) for i in 21:26)
    fact(f, xs...) = (_rf(f, xs...), nothing)
    cl = Tuple{_R, Union{Nothing, _R}}[
        fact("p", _rg(1)), fact("p", _rg(2)), fact("p", _rg(3)),
        fact("q", _rg(1), _rs("c")), fact("q", _rg(2), _rs("b")),
        fact("q", _rg(1), _rs("a")),
        fact("q", _rg(3), _rs("a")),
        fact("r", _rg(1), _rs("x"), _rs("u")), fact("r", _rg(2), _rs("y"), _rs("u")),
        fact("r", _rg(3), _rs("x"), _rs("v")), fact("r", _rg(1), _rs("y"), _rs("v")),
        fact("r", _rg(0), _rs("x"), _rs("u")),
        fact("age", _rs("peter"), _rg(7)), fact("age", _rs("ann"), _rg(11)),
        fact("age", _rs("pat"), _rg(8)), fact("age", _rs("tom"), _rg(5)),
        fact("age", _rs("mike"), _rg(11)),
        (_rf("mem", X, _rcons(X, Y)), nothing),
        (_rf("mem", X, _rcons(Y, Z)), _rf("mem", X, Z)),
        (_rf("gen", X, Y, X), _rf("=<", X, Y)),
        (
            _rf("gen", X, Y, Z),
            _rconj(_rf("<", X, Y), _rf("is", A, _rf("+", X, _rg(1))), _rf("gen", A, Y, Z))
        ),
        (_rf("len", _rnil(), _rg(0)), nothing),
        (
            _rf("len", _rcons(X, Y), N),
            _rconj(_rf("len", Y, M), _rf("is", N, _rf("+", M, _rg(1))))
        ),
        (_rf("last", _rcons(X, _rnil()), X), nothing),
        (_rf("last", _rcons(X, _rcons(Y, Z)), A), _rf("last", _rcons(Y, Z), A)),
        (_rf("cls", X, _rs("lo")), _rf("<", X, _rg(100))),
        (_rf("cls", X, _rs("mid")), _rconj(_rf(">=", X, _rg(100)), _rf("<", X, _rg(250)))),
        (_rf("cls", X, _rs("hi")), _rf(">=", X, _rg(250)))
    ]
    for (name, arg, body) in _rbg_cases()
        push!(cl, (_rf(name, arg), body))
    end
    return cl
end

_rbg_goals() = _R[_rf(name, _rv(50 + i)) for (i, (name, _, _)) in enumerate(_rbg_cases())]

@testset "bagof/3, setof/3, '\$free_variable_set'/3: answers and determinism equal swipl's" begin
    clauses = _rbg_clauses()
    goals = _rbg_goals()
    db = _rdb(clauses)
    ours = String[]
    for g in goals
        for (a, det) in _rcall(
            db,
            g;
            at=(qid, k) -> (@test _rpools_live(db.ld) && db.ld.exception_term == 0 &&
                isempty(db.ld.bags))
        )
            push!(ours, a * (det ? " det" : " nondet"))
        end
        push!(ours, "end")
        @test isempty(db.ld.bags)
    end
    @test count(==("end"), ours) == length(goals)
    @test "b1([1,2,3]) det" in ours
    @test "b4([1,2,1,3]) det" in ours
    @test "b7(-(a,[1,3])) nondet" in ours && "b7(-(c,[1])) det" in ours    # the last bag: no choice point
    @test "s1([1,2,3]) det" in ours
    @test "s4(-(11,[ann,mike])) det" in ours
    @test "v1(-(foo(_,_,A),v(A))) det" in ours
    @test !any(startswith("b2("), ours) && !any(startswith("s5("), ours)    # no empty bag
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

# The stand-in's helper predicates are `system`'s but NOT locked: `user` defines predicates of
# those names, as it may in swipl, and bagof/3 keeps calling its own.
@testset "user may define pick/3 and the other private names of boot/bags.pl" begin
    X, Y, L = _rv(1), _rv(2), _rv(3)
    clauses = Tuple{_R, Union{Nothing, _R}}[
        (_rf("q", _rg(1), _rs("a")), nothing), (_rf("q", _rg(2), _rs("b")), nothing),
        (_rf("pick", _rs("mine"), _rs("mine"), _rs("mine")), nothing),
        (_rf("select_bag", X, X, X, X, X), nothing),
        (_rf("pick_first", X, X, X, X), nothing), (_rf("pick_same", X, X, X, X), nothing),
        (_rf("alloc_bind_key_list", X, X), nothing),
        (_rf("bind_bagof_keys", X, X), nothing),
        (_rf("findall_loop", X, X, X, X), nothing), (_rf("cleanup_bag", X, X), nothing),
        (_rf("t", _rf("r", Y, L)), _rf("bagof", X, _rf("q", X, Y), L)),
        (_rf("u", X), _rf("pick", X, X, X))
    ]
    db = _rdb(clauses)
    @test [a for (a, _) in _rcall(db, _rf("t", _rv(51)))] == ["t(r(a,[1]))", "t(r(b,[2]))"]
    @test [a for (a, _) in _rcall(db, _rf("u", _rv(52)))] == ["u(mine)"]
    if _R_SWIPL
        theirs = _rswipl(clauses, _R[_rf("t", _rv(51)), _rf("u", _rv(52))])
        @test theirs ==
            ["t(r(a,[1])) nondet", "t(r(b,[2])) det", "end", "u(mine) det", "end"]
    end
end

# The exported predicates are system predicates: `user` cannot redefine them (as in swipl:
# `No permission to modify static procedure `bagof/3'`).
@testset "bagof/3, setof/3, findall/3,4 and length/2 are locked system predicates" begin
    gd = LK.PL_global_data{_R}()
    sys = LK.MODULE_system(gd)
    for (n, a, iso) in (("bagof", 3, true), ("setof", 3, true), ("findall", 3, true),
        ("findall", 4, false), ("length", 2, true))
        p = LK.isCurrentProcedure(sym_key(_rs(n)), a, sys)
        @test p !== nothing
        @test (p.definition.flags & LK.P_LOCKED) != 0
        @test ((p.definition.flags & LK.P_ISO) != 0) == iso
    end
    for (n, a) in (("pick", 3), ("select_bag", 5), ("pick_first", 4), ("pick_same", 4),
        ("alloc_bind_key_list", 2), ("bind_bagof_keys", 2), ("findall_loop", 4),
        ("cleanup_bag", 2))
        p = LK.isCurrentProcedure(sym_key(_rs(n)), a, sys)
        @test p !== nothing && (p.definition.flags & LK.P_LOCKED) == 0
    end
end
