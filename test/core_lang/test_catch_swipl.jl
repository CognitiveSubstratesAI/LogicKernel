# ORIGINAL: catch/3 and throw/1 (V9f) against a LIVE swipl; upstream's tests/core_lang/test_exception.pl is mirrored by test_exception.jl, so this file shadows no upstream path.
# test/core_lang/test_catch_swipl.jl — pl-vmi.c I_CATCH/I_EXITCATCH, pl-wam.c findCatcher and b_throw's catcher branches, boot/init.pl's catch/3, the code under test
using Test, LogicKernel, Random
# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const LK = LogicKernel
include(joinpath(@__DIR__, "rules_common.jl"))

function _rct_clauses()
    X, Y, E, R, G = _rv(1), _rv(2), _rv(3), _rv(4), _rv(5)
    c(g, k, r) = _rf("catch", g, k, r)
    th(b) = _rf("throw", b)
    return Tuple{_R, Union{Nothing, _R}}[
        (_rf("p", _rg(1)), nothing), (_rf("p", _rg(2)), nothing),
        (_rf("p", _rg(3)), nothing),
        (_rf("q", _rs("a")), nothing), (_rf("q", _rs("b")), nothing),
        (_rf("thr", X), th(X)),                                         # throws from a clause below
        (_rf("deep", _rg(0), X), th(X)),
        (_rf("deep", Y, X), _rconj(_rf("is", G, _rf("-", Y, _rg(1))), _rf("deep", G, X))),
        # 1. a ball, its catcher, the recovery; a catcher that does not match passes the ball on
        (_rf("t1", E), c(th(_rs("a")), E, _rs("true"))),
        (_rf("t2", R), c(th(_rf("f", _rg(1))), _rf("f", X), _rf("=", R, X))),
        (
            _rf("t3", R),
            c(
                c(th(_rs("b")), _rs("a"), _rf("=", R, _rs("inner"))),
                _rs("b"),
                _rf("=", R, _rs("outer"))
            )
        ),
        (
            _rf("t4", R),
            c(_rf("deep", _rg(5), _rf("ball", _rg(7))), _rf("ball", X), _rf("=", R, X))
        ),
        # 2. an error raised by a built-in, caught by its formal
        (
            _rf("t5", R),
            c(
                _rf("is", X, _rf("+", _rs("foo"), _rg(1))),
                _rf("error", E, _rv(8)),
                _rf("=", R, E)
            )
        ),
        # (not `call(1)`: meta-called as a term it resolves the PROCEDURE call/1, boot/init.pl's — R2,
        # pinned in test_metacall.jl)
        (
            _rf("t6", R),
            c(
                _rf("is", X, _rf("+", _rv(10), _rg(1))),
                _rf("error", E, _rv(8)),
                _rf("=", R, E)
            )
        ),
        # 3. the recovery's own ball is not caught by the same catch/3; an outer one catches it
        (
            _rf("t7", R),
            c(
                c(th(_rs("a")), _rs("a"), th(_rs("b"))),
                _rs("b"),
                _rf("=", R, _rs("rethrown"))
            )
        ),
        (
            _rf("t8", R),
            c(
                c(th(_rs("a")), _rs("a"), th(_rs("a"))),
                _rs("a"),
                _rf("=", R, _rs("outer_a"))
            )
        ),
        # 4. catch/3 is transparent to backtracking; the last answer is deterministic
        (_rf("t9", X), c(_rf("p", X), _rv(9), _rs("true"))),
        (_rf("t10", X, Y), c(_rconj(_rf("p", X), _rf("q", Y)), _rv(9), _rs("true"))),
        (_rf("t11", X), _rconj(c(_rf("p", X), _rv(9), _rs("true")), _rf(">", X, _rg(1)))),
        # 5. a cut inside the goal cuts the goal only
        (_rf("t12", X), c(_rconj(_rf("p", X), _rs("!")), _rv(9), _rs("true"))),
        (
            _rf("t13", X, Y),
            _rconj(_rf("q", Y), c(_rconj(_rf("p", X), _rs("!")), _rv(9), _rs("true")))
        ),
        # 6. bindings made before the ball are undone; the catcher's are kept
        (
            _rf("t14", X, R),
            c(_rconj(_rf("=", X, _rs("bound")), th(_rs("x"))), _rv(9), _rf("=", R, X))
        ),
        (
            _rf("t15", R),
            c(
                th(_rf("g", _rs("a"), _rs("b"))),
                _rf("g", X, Y),
                _rf("=", R, _rf("-", Y, X))
            )
        ),
        # backtracking into the goal after an answer, then a ball
        (
            _rf("t16", X, R),
            c(
                _rconj(_rf("p", X), _rf(">", X, _rg(1)), th(_rf("at", X))),
                _rf("at", Y),
                _rf("=", R, Y)
            )
        ),
        # the goal unbound: an instantiation error, caught outside
        (
            _rf("t17", R),
            c(c(G, _rv(9), _rs("true")), _rf("error", E, _rv(8)), _rf("=", R, E))
        ),
        # recovery that fails; the goal that fails (no ball)
        (_rf("t18"), c(th(_rs("a")), _rs("a"), _rs("fail"))),
        (_rf("t19"), c(_rs("fail"), _rv(9), _rs("true"))),
        # true/0 and fail/0 meta-called (the predicates, since V9f)
        (_rf("t20"), _rf("call", _rs("true"))), (_rf("t21"), _rf("call", _rs("fail"))),
        # the recovery's ball while a choice point of the RECOVERY lies above catch/3's frame (rg/2's
        # clause choice): `fr <= ch` holds, so `FR_CAUGHT` alone keeps the same catch/3 from catching
        # it again (findCatcher, pl-wam.c:2040-2042) — caught again, rg/2's second clause answers `inner`
        (_rf("rg", E, _rv(9)), _rconj(_rf("var", E), _rf("=", E, _rg(1)), th(_rf("f", E)))),
        (_rf("rg", E, R), _rconj(_rf("nonvar", E), _rf("=", R, _rs("inner")))),
        (
            _rf("t22", R),
            c(
                c(th(_rf("f", _rv(9))), _rf("f", E), _rf("rg", E, R)),
                _rf("f", _rv(10)),
                _rf("=", R, _rs("outer"))
            )
        ),
        # catch/3 is system code: locked (boot/init.pl is loaded in system mode)
        (
            _rf("t23", R),
            c(
                _rf("assertz", _rf("catch", _rs("x"), _rs("y"), _rs("z"))),
                _rf("error", E, _rv(8)),
                _rf("=", R, E)
            )
        ),
        # the catcher's unification under the occurs_check flag: `false` binds Y = g(Y) and catches;
        # `error` raises, and THAT error is the ball from there on (findCatcher's "Exception from
        # PL_unify()", pl-wam.c:2067-2069)
        (
            _rf("t24", R),
            c(
                c(th(_rf("f", X, X)), _rf("f", Y, _rf("g", Y)), _rf("=", R, _rs("inner"))),
                _rf("error", E, _rv(8)),
                _rf("=", R, E)
            )
        ),
        (
            _rf("t25", R),
            c(
                c(th(_rf("f", X, X)), _rf("f", Y, _rf("g", Y)), _rf("=", R, _rs("inner"))),
                _rv(9),
                _rf("=", R, _rs("outer"))
            )
        ),
        # the ball is a COPY with fresh variables, its sharing kept (copy_exception: duplicate_term,
        # pl-fli.c): the caught term's variables are not the thrown term's
        (_rf("same", X, Y, _rs("same")), _rf("==", X, Y)),
        (_rf("same", X, Y, _rs("fresh")), _rf("\\==", X, Y)),
        (
            _rf("t26", R),
            _rconj(c(th(_rf("f", X)), _rf("f", Y), _rs("true")), _rf("same", X, Y, R))
        ),
        (
            _rf("t27", R, G),
            _rconj(c(th(_rf("f", X, X, E)), _rf("f", Y, _rv(11), _rv(12)), _rs("true")),
                _rf("same", Y, _rv(11), R), _rf("same", _rv(12), E, G))
        ),
        (
            _rf("t28", R),
            _rconj(
                c(th(_rf("f", X)), _rf("f", Y), _rs("true")),
                _rf("=", Y, _rg(1)),
                _rf("=", R, _rf("x", X))
            )
        ),
        # a CYCLIC ball keeps its cycle through the unwind: the copy's own bindings are frozen
        # (copy_exception's freezeGlobal, pl-fli.c) — undone with the rest, Y would come back unbound
        (
            _rf("t29", R),
            _rconj(
                c(
                    _rconj(_rf("=", X, _rf("f", X)), th(_rf("b", X))),
                    _rf("b", Y),
                    _rs("true")
                ),
                _rf("=", Y, _rf("f", _rv(12))),
                _ror(
                    _rit(_rf("==", _rv(12), Y), _rf("=", R, _rs("cyclic"))),
                    _rf("=", R, _rs("lost"))
                )
            )
        ),
        # 30. after a caught ball NOTHING is pending: the next error is raised as itself. (An error
        # of `PL_error` is not built while an older exception is pending — pl-error.c "do not
        # overrule older exception" — so a ball left pending would be thrown again in its place.)
        # The recover goal is a clause of the program: a FOREIGN one that succeeds clears a
        # pending exception itself (`PL_clear_foreign_exception`) and would hide the difference.
        (_rf("rec", _rs("ok")), nothing),
        (
            _rf("t30", R),
            _rconj(
                c(th(_rs("a")), _rv(13), _rf("rec", _rv(14))),
                c(
                    _rf("is", X, _rf("+", _rv(10), _rg(1))),
                    _rf("error", E, _rv(8)),
                    _rf("=", R, E)
                )
            )
        ),
        # 31. (L1f f3b-1) the ball unwound through a catch/3 whose catcher does not match, the choice
        # points of p/1 and q/1 open: dbg_discardChoicesAfter keeps the ball's WORD across each discard
        # (pl-wam.c), the outer catch/3 gets it (swipl 10.1.18: `t31(-(3,a))`, probed 2026-10-20)
        (
            _rf("t31", R),
            c(
                _rconj(
                    _rf("p", X),
                    c(
                        _rconj(_rf("q", Y), _rf(">=", X, _rg(3)), th(_rf("in", X, Y))),
                        _rs("out"),
                        _rs("true")
                    )
                ),
                _rf("in", _rv(15), _rv(16)),
                _rf("=", R, _rf("-", _rv(15), _rv(16)))
            )
        ),
        # 32. (L1f f3b-1) a cyclic ball inside a compound keeps its cycle through the unwind (swipl
        # 10.1.18: `t32(yes)`, probed 2026-10-20)
        (
            _rf("t32", R),
            _rconj(
                c(
                    _rconj(_rf("=", X, _rf("f", X, _rs("x"))), th(_rf("g", X))),
                    _rf("g", Y),
                    _rs("true")
                ),
                _ror(
                    _rit(
                        _rconj(
                            _rf("=", Y, _rf("f", _rv(12), _rs("x"))), _rf("==", _rv(12), Y)
                        ),
                        _rf("=", R, _rs("yes"))
                    ),
                    _rf("=", R, _rs("no"))
                )
            )
        )
    ]
end

function _rct_goals()
    X, Y = _rv(51), _rv(52)
    g = _R[_rf("t$k", X) for k in 1:9]
    append!(
        g,
        _R[_rf("t10", X, Y), _rf("t11", X), _rf("t12", X), _rf("t13", X, Y),
            _rf("t14", X, Y), _rf("t15", X), _rf("t16", X, Y), _rf("t17", X),
            _rs("t18"), _rs("t19"), _rs("t20"), _rs("t21"), _rf("t22", X), _rf("t23", X),
            _rf("t24", X),
            _rf("t25", X), _rf("t26", X), _rf("t27", X, Y), _rf("t28", X), _rf("t29", X),
            _rf("t30", X), _rf("t31", X), _rf("t32", X)]
    )
    return g
end

@testset "catch/3 and throw/1: answers and determinism equal swipl's, the pools live at every answer" begin
    clauses = _rct_clauses()
    goals = _rct_goals()
    db = _rdb(clauses)
    ours = String[]
    for g in goals
        # at every answer: the pools hold the live records, and no exception is pending — a caught
        # ball is cleared when its recover goal is called (pl-vmi.c b_throw_resume)
        for (a, det) in _rcall(
            db, g; at=(qid, k) -> (@test _rpools_live(db.ld) && db.ld.exception_term == 0)
        )
            push!(ours, a * (det ? " det" : " nondet"))
        end
        push!(ours, "end")
    end
    @test count(==("end"), ours) == length(goals)
    @test length(ours) > length(goals) + 15
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

@testset "the catcher's unification raises under occurs_check = error: that error becomes the ball" begin
    clauses = _rct_clauses()
    goals = _R[_rf("t24", _rv(51)), _rf("t25", _rv(51))]
    db = _rdb(clauses)
    db.ld.prolog_flag_occurs_check = LK.OCCURS_CHECK_ERROR
    ours = _rlines(db, goals)
    @test length(ours) == 4
    if _R_SWIPL
        @test ours ==
            _rswipl(clauses, goals; extra=":- set_prolog_flag(occurs_check, error).\n")
    elseif _R_SWIPL_REQUIRED
        @test false
    end
end

# KNOWN DIFFERENCE, pinned (R2 checklist: "`unwind(_)` balls ('\$recover_and_rethrow'/2)"):
#   kernel: NotPortedError at the catcher — the recover goal's wrapper is boot/init.pl's
#   swipl 10.1.17: the recover goal runs, then the ball is thrown again and no catch/3 stops it —
#     `catch(catch(throw(unwind(x)), _, true), _, true)` ends the query with unwind(x) (probed)
@testset "an unwind(_) ball reaching a catcher is refused by name (R2)" begin
    db = _rdb([(
        _rf("tu"), _rf("catch", _rf("throw", _rf("unwind", _rs("x"))), _rv(1), _rs("true"))
    )])
    err = try
        _rcall(db, _rs("tu"))
        nothing
    catch e
        e
    end
    @test err isa LK.NotPortedError
    @test err isa LK.NotPortedError && occursin("unwind(_)", err.what) && err.step == "R2"
end

# Frame positions after a CAUGHT exception (read with prolog_current_frame/1 on both sides, as the
# difference from the caller's frame): the recover goal runs where catch/3's goal ran, above its
# arguments. MC19's kill test (V9e-1 memo): a LOOPING qualifier chain makes `stripModule` fail, the
# ball is caught, and the next frame's position must equal swipl's — an extra `lTop` raise at that
# failure would move it.
function _rct_pos_clauses()
    F0, F1, D, X, E = _rv(1), _rv(2), _rv(3), _rv(4), _rv(5)
    pcf(v) = _rf("prolog_current_frame", v)
    fr = (_rf("fr", F1), _rconj(pcf(F1), _rs("true")))
    pos(name, goal) =
        (_rf(name, D), _rconj(pcf(F0), goal, _rf("fr", F1), _rf("is", D, _rf("-", F1, F0))))
    return Tuple{_R, Union{Nothing, _R}}[
        fr, (_rf("p", _rg(1)), nothing),
        pos("cp1", _rf("catch", _rf("throw", _rs("a")), _rv(9), _rs("true"))),
        pos("cp2", _rf("catch", _rs("true"), _rv(9), _rs("true"))),
        pos("cp3", _rf("catch", _rf("p", _rv(10)), _rv(9), _rs("true"))),
        # the recover goal reports its own frame's position
        (
            _rf("cp4", D),
            _rconj(
                pcf(F0),
                _rf("catch", _rf("throw", _rs("a")), _rv(9), _rf("fr", F1)),
                _rf("is", D, _rf("-", F1, F0))
            )
        ),
        # MC19: X = user:X, call(X) — stripModule fails, type_error(acyclic_term, X) is caught
        pos(
            "cp5",
            _rconj(
                _rf("=", X, _rf(":", _rs("user"), X)),
                _rf("catch", _rf("call", X), E, _rs("true"))
            )
        )
    ]
end

@testset "frame positions after a caught exception equal swipl's (MC19's kill test)" begin
    clauses = _rct_pos_clauses()
    names = ["cp$k" for k in 1:5]
    db = _rdb(clauses)
    ours = Int[]
    for n in names
        ans = _rcall(db, _rf(n, _rv(80)))
        @test length(ans) == 1
        push!(ours, parse(Int, match(r"\((-?\d+)\)", first(ans[1]))[1]))
    end
    if _R_SWIPL
        main =
            "main :- " *
            join((n * "(D" * n * "), writeln(D" * n * ")" for n in names), ", ") * "."
        theirs = parse.(Int, _rswipl(clauses, (); main_text=main))
        ours == theirs || println(stderr, "  positions, kernel: ", ours, " swipl: ", theirs)
        @test ours == theirs
    elseif _R_SWIPL_REQUIRED
        @test false
    end
end
