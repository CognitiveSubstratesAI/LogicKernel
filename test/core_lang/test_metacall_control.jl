# ORIGINAL: call/1 of control constructs — the temporary goal clause (V9e-2) — against swipl; its own file, so no upstream test file's path (tests/core_lang/test_call.pl) is shadowed.
# test/core_lang/test_metacall_control.jl — pl-vmi.c i_metacall_common's control branch and pl-comp.c compileClause with a NULL head (src/pl-comp.jl compileGoalClause), the code under test
using Test, LogicKernel, Random
# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const LK = LogicKernel
include(joinpath(@__DIR__, "rules_common.jl"))

function _rmcc_clauses()
    G, X, Y = _rv(1), _rv(2), _rv(3)
    return Tuple{_R, Union{Nothing, _R}}[
        (_rf("p", _rg(1)), nothing), (_rf("p", _rg(2)), nothing),
        (_rf("p", _rg(3)), nothing),
        (_rf("q", _rs("a")), nothing), (_rf("q", _rs("b")), nothing),
        (_rf("r", _rf("f", _rs("a")), _rg("s")), nothing),
        (
            _rf(
                "g5",
                _rf("f", _rg(1)),
                _rf("f", _rg(2)),
                _rf("f", _rg(3)),
                _rf("f", _rg(4)),
                X
            ),
            nothing
        ),
        (_rf("g7", (_rg(v) for v in 1:7)...), nothing),
        (_rf("g8", (_rg(v) for v in 1:7)..., _rs("done")), nothing),
        (_rf("c", G), _rf("call", G)),                                  # I_CALL1 of call/1
        (_rf("v", G), G),                                               # I_CALL1 of a variable
        (_rf("v2", G, X), _rconj(G, _rf("=", X, _rs("after")))),        # …not the last goal
        # the cut in the goal is local to the call: p/1's other answers are cut, q/1's are not
        (
            _rf("lcut", X, Y),
            _rconj(_rf("call", _rf(",", _rf("p", X), _rs("!"))), _rf("q", Y))
        ),
        # and in a clause body it cuts the clause
        (_rf("ccut", X, Y), _rconj(_rf("p", X), _rs("!"), _rf("q", Y))),
        # the goal's variables BOUND before the call: the goal clause sees their values. The goal is
        # BUILT FIRST and the variable bound AFTER, through a call (`eq/2`: head unification binds in the
        # store) — only then does the goal hold a bound variable (building a term loads each variable
        # through `linkValI`, which dereferences it; and `X = 2` as X's first use writes 2 into the cell)
        (_rf("eq", X, X), nothing),
        (
            _rf("bnd", Y),
            _rconj(
                _rf("eq", G, _rconj(_rf("p", X), _rf("q", Y))),
                _rf("eq", X, _rg(2)),
                _rf("call", G)
            )
        ),
        (
            _rf("bnd2", Y),
            _rconj(
                _rf("eq", G, _rf(";", _rf("=", X, _rf("f", Y)), _rf("=", Y, _rs("no")))),
                _rf("eq", X, _rf("f", _rg(3))),
                _rf("call", G)
            )
        )
    ]
end

function _rmcc_goals()
    X, Y, Z = _rv(51), _rv(52), _rv(53)
    c(g) = _rf("c", g)
    conj(a...) = _rconj(a...)
    disj(a, b) = _rf(";", a, b)
    ite(a, b, e) = _rf(";", _rf("->", a, b), e)
    return _R[
        # 1. every control construct
        c(conj(_rf("p", X), _rf("q", Y))), c(disj(_rf("p", X), _rf("q", X))),
        c(ite(_rf("p", X), _rf("q", Y), _rf("=", Y, _rs("no")))),
        c(ite(_rf("p", _rg(9)), _rf("q", Y), _rf("=", Y, _rs("no")))),
        c(_rf("->", _rf("p", X), _rf("q", Y))), c(_rf("\\+", _rf("p", _rg(1)))),
        c(_rf("\\+", _rf("p", _rg(9)))),
        c(_rf(";", _rf("*->", _rf("p", X), _rf("q", Y)), _rf("=", Y, _rs("none")))),
        c(_rf(";", _rf("*->", _rf("p", _rg(9)), _rf("q", Y)), _rf("=", Y, _rs("none")))),
        c(_rf("*->", _rf("p", X), _rs("true"))), c(_rf("|", _rf("p", X), _rf("q", X))),
        _rf("v", conj(_rf("p", X), _rf("q", Y))),
        _rf("v2", disj(_rf("p", X), _rf("q", X)), Y),
        # 2. the cut is local to the call
        c(conj(_rf("p", X), _rs("!"))), c(conj(_rf("p", X), _rs("!"), _rf("q", Y))),
        c(conj(_rs("!"), _rf("p", X))), _rf("lcut", X, Y), _rf("ccut", X, Y),
        c(disj(conj(_rf("p", X), _rs("!")), _rf("=", X, _rs("other")))),
        # 3. variables shared with the caller, bound by the call, kept through backtracking
        c(conj(_rf("=", X, _rf("f", Y)), _rf("=", Y, _rg(1)))),
        c(conj(disj(_rf("=", X, _rg(1)), _rf("=", X, _rg(2))), _rf("=", Y, X))),
        c(disj(_rf("p", X), _rf("=", X, _rs("z")))),
        # 4. compound and string arguments of sub-goals: the pseudo variables (B_VAR0..2, B_VAR n)
        c(disj(_rf("atom", _rf("f", X)), _rf("=", X, _rg(1)))),
        c(conj(_rf("=", Z, _rlist(_rg(1), _rg(2), X)), _rf("p", X))),
        c(conj(_rf("r", _rf("f", _rs("a")), _rg("s")), _rs("true"))),
        c(
            conj(
                _rf(
                    "g5",
                    _rf("f", _rg(1)),
                    _rf("f", _rg(2)),
                    _rf("f", _rg(3)),
                    _rf("f", _rg(4)),
                    X
                ),
                _rf("p", Y)
            )
        ),
        # 5. nested: a call inside the goal, a control construct inside a call inside the goal
        c(conj(_rf("call", disj(_rf("p", X), _rf("q", X))), _rs("true"))),
        _rf("v", conj(_rs("true"), _rf("call", conj(_rf("p", X), _rf("q", Y))))),
        # 6. call/9 — more than 8 — goes through a goal clause, which compiles it inline (I_CALLN);
        # call/2..8 meta-called as a TERM resolve the predicates boot/init.pl defines (R2: not here)
        c(_rf("call", _rs("g8"), (_rg(v) for v in 1:7)..., X)),
        c(_rconj(_rs("true"), _rf("call", _rs("g7"), (_rg(v) for v in 1:7)...))),
        # true, fail and a goal that fails
        c(conj(_rs("true"), _rs("fail"))), c(disj(_rs("fail"), _rs("true"))),
        # 7. the goal's variables bound before the call
        _rf("bnd", Y), _rf("bnd2", Y)
    ]
end

@testset "call/1 of control constructs: answers and determinism equal swipl's, the pools live at every answer" begin
    clauses = _rmcc_clauses()
    goals = _rmcc_goals()
    db = _rdb(clauses)
    ours = String[]
    for g in goals
        for (a, det) in _rcall(db, g; at=(qid, k) -> (@test _rpools_live(db.ld)))
            push!(ours, a * (det ? " det" : " nondet"))
        end
        push!(ours, "end")
    end
    @test count(==("end"), ours) == length(goals)
    @test length(ours) > length(goals) + 30
    if _R_SWIPL
        theirs = _rswipl(clauses, goals)
        @test ours == theirs
        if ours != theirs
            k = findfirst(i -> i > length(theirs) || ours[i] != theirs[i], eachindex(ours))
            @info "first difference" k ours[something(k, 1)] get(
                theirs, something(k, 1), "—"
            )
        end
    elseif _R_SWIPL_REQUIRED
        @test false
    end
end

# The error formal a goal raises, `no_error` when it answers or fails; written canonically.
function _rmcc_formal(db::_RDB, goal::_R)::String
    gd, ld = db.gd, db.ld
    _, n = _rfunctor(goal)
    fid = LK.PL_open_foreign_frame(ld)
    args = LK.PL_new_term_refs(ld, n)
    pvm = LK.PutVarMap()  # one PutVarMap: these puts share their variables as one record does (L1b boundary, user 2026-10-14)
    for i in 1:n
        LK.putSlotValue!(ld, args + i, child(goal, i + 1), pvm)
    end
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, _rproc(db, goal),
        args
    )
    rc = LK.PL_next_solution(gd, ld, qid)
    out = "no_error"
    if rc == LK.PL_S_EXCEPTION
        out = _rcanonical(child(lk_answer(ld, LK.PL_exception(ld, qid)), 2))
    end
    LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
    return out
end

@testset "call/1 of control constructs: the errors equal swipl's" begin
    X = _rv(61)
    c(g) = _rf("c", g)
    goals = _R[
        c(_rconj(_rf("p", X), _rg(1))),                                  # not callable: at compile
        c(_rconj(_rs("fail"), _rg(1))),                                  # …before anything runs
        c(_rconj(_rf("p", _rg(1)), _rv(62))),                            # a variable goal, unbound
        c(_rf(";", _rs("fail"), _rf("nosuch", X))),                      # undefined, reached
        c(_rconj(_rf("p", X), _rf("is", _rv(63), _rf("+", X, _rs("a")))))
    ]
    clauses = _rmcc_clauses()
    db = _rdb(clauses)
    ours = [_rmcc_formal(db, g) for g in goals]
    @test all(!=("no_error"), ours)
    if _R_SWIPL
        # `r/1` prints an uncaught error as `exception(F) det` (rules_common.jl, L1d step 2): the formals
        theirs = [
            l[(length("exception(") + 1):(end - length(") det"))] for
            l in _rswipl(clauses, goals) if startswith(l, "exception(")
        ]
        @test ours == theirs
        ours == theirs || @info "errors differ" ours theirs
    elseif _R_SWIPL_REQUIRED
        @test false
    end
end

# f3b-3 (localGoal on the cells): a CYCLIC control goal under call/1 is upstream's
# representation_error(cyclic_term) (pl-comp.c analyseVariables2's CYCLE_CHECK_AT test). Before
# f3b-3 the kernel's term walk overflowed the Julia stack — no Prolog answer (an existing divergence,
# D-0110 item 5: measured on the base 42d6205, 2026-10-22).
@testset "call/1 of a cyclic control goal: representation_error(cyclic_term), as swipl" begin
    G, E = _rv(71), _rv(72)
    cyc = _rf("=", G, _rconj(_rs("true"), G))
    clauses = Tuple{_R, Union{Nothing, _R}}[
        (_rs("g3"), _rconj(cyc, _rf("call", G))),                         # uncaught: the formal
        (_rf("g3w", E), _rconj(cyc, _rf("catch", _rf("call", G), E, _rs("true"))))  # the ball
    ]
    goals = _R[_rs("g3"), _rf("g3w", _rv(73))]
    db = _rdb(clauses)
    @test [_rmcc_formal(db, goals[1])] == ["representation_error(cyclic_term)"]
    ours = String[]
    for g in goals
        for (a, det) in _rcall(db, g)
            push!(ours, a * (det ? " det" : " nondet"))
        end
        push!(ours, "end")
    end
    # the WHOLE ball, the context included (D-0112 item 1): swipl 10.1.18 at the pin answers
    # g3w(error(representation_error(cyclic_term),context(system:call/1,_))) (probed 2026-10-22)
    @test ours[3] ==
        "g3w(error(representation_error(cyclic_term),context(:(system,/(call,1)),_))) det"
    if _R_SWIPL
        theirs = _rswipl(clauses, goals)
        @test ours == theirs
        ours == theirs || @info "G3 differs" ours theirs
    elseif _R_SWIPL_REQUIRED
        @test false
    end
end

# Where a frame lands inside a meta-called control goal (decision D, user 2026-10-12: equal to
# swipl's). Upstream builds the goal clause ON THE LOCAL STACK above the frame — pseudo variables,
# variables, then the clause and its code — so a frame made inside the goal lands above all of that;
# read with `prolog_current_frame/1` on both sides, as a difference from the caller's frame.
function _rmcc_pos_clauses()
    F0, F1, D, X = _rv(1), _rv(2), _rv(3), _rv(4)
    pcf(v) = _rf("prolog_current_frame", v)
    pos(name, goal) =
        (_rf(name, D), _rconj(pcf(F0), _rf("call", goal), _rf("is", D, _rf("-", F1, F0))))
    g4f = _rf("g4", _rf("f", _rg(1)), _rf("f", _rg(2)), _rf("f", _rg(3)), _rf("f", _rg(4)))
    return Tuple{_R, Union{Nothing, _R}}[
        # `, true`: `prolog_current_frame/1` is then no last call, and reports fr's own frame — as a
        # last call it would report its caller's (the goal clause's frame), whatever the clause's size
        (_rf("fr", F1), _rconj(pcf(F1), _rs("true"))),
        (_rf("g4", _rv(10), _rv(11), _rv(12), _rv(13)), nothing),
        (_rf("p", _rg(1)), nothing),
        pos("pc1", _rconj(_rf("fr", F1), _rs("true"))),
        pos(
            "pc2",
            _rconj(_rf("g4", _rs("a"), _rf("b", _rs("c")), _rg("s"), X), _rf("fr", F1))
        ),
        pos("pc3", _rf(";", _rf("fr", F1), _rs("true"))),
        pos(
            "pc4",
            _rconj(
                _rs("true"), _rf(";", _rf("->", _rs("true"), _rf("fr", F1)), _rs("true"))
            )
        ),
        pos("pc5", _rconj(_rf("\\+", _rs("fail")), _rf("fr", F1))),
        pos("pc6", _rconj(g4f, _rf("fr", F1))),
        pos("pc7", _rconj(_rs("true"), _rf("call", _rconj(_rf("fr", F1), _rs("true"))))),
        # fr/1 followed by a call: its frame lands above the goal clause's code and data
        pos("pc8", _rconj(_rf("fr", F1), _rf("p", _rv(14)))),
        pos("pc9", _rconj(_rf("fr", F1), g4f)),
        pos("pc10", _rconj(_rf(";", _rf("fr", F1), _rs("true")), _rf("p", _rv(14)))),
        pos("pc11", _rconj(_rf("\\+", _rs("fail")), _rf("fr", F1), _rf("p", _rv(14)))),
        pos(
            "pc12",
            _rconj(
                _rf(";", _rf("->", _rs("true"), _rf("fr", F1)), _rs("true")),
                _rf("p", _rv(14))
            )
        ),
        pos(
            "pc13",
            _rconj(
                _rf("fr", F1),
                _rf("g4", _rs("a"), _rs("t"), _rf("b", _rs("c")), X),
                _rf("p", _rv(14))
            )
        ),
        # variables BOUND before the call: an atomic value is a literal, not a cell; a bound sub-goal
        # compiles inline as control, not as a nested meta-call (`localGoal` dereferences both)
        (
            _rf("pcb1", D),
            _rconj(
                _rf(
                    "=", _rv(7),
                    _rconj(
                        _rf("fr", F1),
                        _rf("g4", _rv(5), _rv(5), _rv(5), _rs("b")),   # 3 uses: a cell + loads ≠ 3 literals
                        _rf("p", _rv(14))
                    )
                ),
                _rf("b2", _rv(5)), pcf(F0), _rf("call", _rv(7)),
                _rf("is", D, _rf("-", F1, F0))
            )
        ),
        (
            _rf("pcb2", D),
            _rconj(
                _rf("=", _rv(7), _rconj(_rv(6), _rf("fr", F1), _rf("p", _rv(14)))),
                _rf("bg", _rv(6)), pcf(F0), _rf("call", _rv(7)),
                _rf("is", D, _rf("-", F1, F0))
            )
        ),
        # (the goal is BUILT FIRST and its variable bound AFTER, through a call: only then does the goal
        # hold a bound variable — a clause building a term loads each variable through `linkValI`,
        # which dereferences it, upstream too; and `X = 2` as X's first use writes 2 into the cell)
        (_rf("b2", _rg(2)), nothing),
        (_rf("bg", _rf(";", _rf("->", _rs("true"), _rs("true")), _rs("true"))), nothing),
        # a STRING argument is a pseudo variable too (see the testset: its swipl side is written by hand)
        pos(
            "pcs",
            _rconj(
                _rf("fr", F1),
                _rf("g4", _rs("a"), _rg("s"), _rf("b", _rs("c")), X),
                _rf("p", _rv(14))
            )
        )
    ]
end

@testset "call/1 of control constructs: frame positions inside the goal equal swipl's" begin
    clauses = _rmcc_pos_clauses()
    names = [["pc$k" for k in 1:13]; "pcb1"; "pcb2"]
    db = _rdb(clauses)
    ours = Int[]
    for n in names
        ans = _rcall(db, _rf(n, _rv(80)))
        # the FIRST answer (swipl's main takes one); a goal with an alternative (`fr(F1) ; true`)
        # then throws an instantiation error on backtracking, a second line since L1d step 2
        @test !isempty(ans) && !startswith(first(ans[1]), "exception(")
        m = match(r"\((-?\d+)\)", first(ans[1]))
        push!(ours, parse(Int, m[1]))
    end
    @test length(unique(ours)) >= 8                                  # the shapes differ in size
    if _R_SWIPL
        main =
            "main :- " *
            join((n * "(D" * n * "), writeln(D" * n * ")" for n in names), ", ") * "."
        theirs = parse.(Int, _rswipl(clauses, (); main_text=main))
        ours == theirs || println(stderr, "  positions, kernel: ", ours, " swipl: ", theirs)
        @test ours == theirs
        # the string case: `_rsrc` writes a string as an atom, so swipl's clause is written here
        ks = parse(Int, match(r"\((-?\d+)\)", first(_rcall(db, _rf("pcs", _rv(81)))[1]))[1])
        prog =
            "pcs(D) :- prolog_current_frame(F0), " *
            "call((fr(F1), g4(a, \"s\", b(c), _X), p(_))), D is F1 - F0.\n" *
            "main :- pcs(D), writeln(D)."
        ss = parse.(Int, _rswipl(clauses[1:3], (); main_text=prog))
        @test ss == [ks]
        ss == [ks] || println(stderr, "  string position, kernel: ", ks, " swipl: ", ss)
    elseif _R_SWIPL_REQUIRED
        @test false
    end
end

@testset "call/1 of control constructs: what stays refused, by name" begin
    X = _rv(71)
    # (`$/1` was refused here until V9f-b: test_det_swipl.jl calls one through call/1)
    for g in (_rf("c", _rf("@", _rf("p", X), _rs("user"))),)            # Goal@Module (R2)
        db = _rdb(_rmcc_clauses())                                      # a refusal abandons the query
        @test_throws LK.NotPortedError _rcall(db, g)
    end
    # a CYCLIC goal (L1f f3): refused the same way, its culprit still naming the goal's functor and the
    # module — read argument by argument, the cyclic one as its functor over fresh variables
    G = _rv(72)
    db = _rdb(_rmcc_clauses())
    e = try
        _rcall(
            db,
            _rf(
                "c",
                _rf(",", _rf("=", G, _rf("p", G)), _rf("c", _rf("@", G, _rs("user"))))
            )
        )
        nothing
    catch err
        err
    end
    @test e isa LK.NotPortedError && e.what == "call/1 of Goal@Module"
    if e isa LK.NotPortedError
        @test occursin(r"^@\(p\(V\d+\),user\)$", _rsrc(e.culprit))
    end
end
