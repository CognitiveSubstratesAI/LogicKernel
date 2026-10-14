# ORIGINAL: the cleanup family (V9g) — `setup_call_cleanup/3`, `setup_call_catcher_cleanup/4`, `call_cleanup/2` — against a LIVE swipl; upstream's tests/core_lang/test_call_cleanup.pl is mirrored by test_call_cleanup.jl when plunit runs (R2), so this file shadows no upstream path.
# test/core_lang/test_cleanup_swipl.jl — pl-vmi.c I_CALLCLEANUP/I_EXITCLEANUP, pl-wam.c callCleanupHandler, frameFinished, call_term, discardChoicesAfter's cleanup branch, pl-pro.c sig_atomic/1, the code under test
using Test, LogicKernel, Random
# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const LK = LogicKernel
include(joinpath(@__DIR__, "rules_common.jl"))

# Every case is a predicate `kN/1` (`kN/2` with the catcher). A cleanup goal LOGS: `log(Item)` is
# `assertz(logged(Item))`, and after each case's answers the goal `logs(L)` answers once per
# logged item, in order — so the differential compares WHAT ran, WHEN (between which answers), and
# how often. The four ways a goal finishes — exit, fail, cut, exception — each alone, nested, and
# with a cleanup goal that itself fails or raises.
const _RCL_N = 34
function _rcl_clauses()
    X, Y, Z, C, E = _rv(1), _rv(2), _rv(3), _rv(4), _rv(5)
    T = _rs("true")
    scc(s, g, c) = _rf("setup_call_cleanup", s, g, c)
    sccc(s, g, k, c) = _rf("setup_call_catcher_cleanup", s, g, k, c)
    log(x) = _rf("log", x)
    c3(g, k, r) = _rf("catch", g, k, r)
    th(b) = _rf("throw", b)
    eq(a, b) = _rf("=", a, b)
    return Tuple{_R, Union{Nothing, _R}}[
        (_rf("p", _rg(1)), nothing), (_rf("p", _rg(2)), nothing),
        (_rf("p", _rg(3)), nothing),
        (_rf("log", X), _rf("assertz", _rf("logged", X))),
        (_rf("logs", X), _rf("logged", X)),
        # ── the four ways out ──
        (_rf("k1", X), scc(T, eq(X, _rg(1)), log(_rs("c1")))),                  # exit
        (_rf("k2", X), scc(T, _rs("fail"), log(_rs("c2")))),                    # fail
        (_rf("k3", X), _rconj(scc(T, _rf("p", X), log(_rs("c3"))), _rs("!"))),  # cut
        (_rf("k4", X), c3(scc(T, th(_rs("b")), log(_rs("c4"))), E, eq(X, E))),  # exception
        (_rf("k5", X), scc(T, _rf("p", X), log(_rs("c5")))),                    # the last answer's exit
        # ── the catcher ──
        (_rf("k6", X, C), sccc(T, eq(X, _rg(1)), C, log(_rf("c6", C)))),
        (_rf("k7", X, C), sccc(T, _rs("fail"), C, log(_rf("c7", C)))),
        (_rf("k8", X, C), _rconj(sccc(T, _rf("p", X), C, log(_rf("c8", C))), _rs("!"))),
        (_rf("k9", X, C), c3(sccc(T, th(_rs("b")), C, log(_rf("c9", C))), E, eq(X, E))),
        (_rf("k10", X, C), sccc(T, _rf("p", X), C, log(_rf("c10", C)))),
        # an exception from OUTSIDE the goal, while its choice points are still there
        (
            _rf("k11", X, C),
            c3(
                _rconj(sccc(T, _rf("p", X), C, log(_rf("c11", C))), th(_rs("b"))),
                E,
                eq(X, E)
            )
        ),
        # ── nesting ──
        (_rf("k12", X), scc(T, scc(T, eq(X, _rg(1)), log(_rs("in12"))), log(_rs("out12")))),
        (
            _rf("k13", X),
            scc(
                T, _rconj(scc(T, _rf("p", X), log(_rs("in13"))), _rs("fail")),
                log(_rs("out13"))
            )
        ),
        (
            _rf("k14", X),
            c3(
                scc(T, scc(T, th(_rs("b")), log(_rs("in14"))), log(_rs("out14"))), E,
                eq(X, E)
            )
        ),
        (
            _rf("k15", X),
            _rconj(
                _rf("p", X), scc(T, _rf("p", Y), log(_rf("c15", X))), _rf("==", X, _rg(2)),
                _rs("!")
            )
        ),
        # ── the cleanup goal itself ──
        (_rf("k16", X), c3(scc(T, T, th(_rs("c"))), E, eq(X, E))),              # raises at exit
        (_rf("k17", X), c3(scc(T, _rs("fail"), th(_rs("c"))), E, eq(X, E))),    # raises at fail
        (_rf("k18", X), c3(scc(T, th(_rs("g")), th(_rs("c"))), E, eq(X, E))),   # both raise
        (
            _rf("k19", X),                                                      # an error beats a ball
            c3(
                scc(T, th(_rs("g")), _rf("is", Y, _rf("+", Z, _rg(1)))),
                E,
                eq(X, E)
            )
        ),
        (_rf("k20", X), scc(T, eq(X, _rg(1)), _rs("fail"))),                    # fails: ignored
        (_rf("k21", X), scc(T, T, eq(X, _rg(1)))),                              # its bindings
        (_rf("k22", X), scc(T, eq(X, _rg(1)), _rconj(log(_rs("a22")), log(_rs("b22"))))),  # a control construct
        (_rf("k23", X), scc(T, eq(X, _rg(1)), _ror(_rs("fail"), log(_rs("c23"))))),
        # ── the setup goal ──
        (_rf("k24", X), scc(_rs("fail"), eq(X, _rg(1)), log(_rs("c24")))),      # fails: nothing runs
        (_rf("k25", X), scc(_rf("p", Y), eq(X, Y), log(_rf("c25", Y)))),        # once
        (_rf("k26", X), c3(scc(th(_rs("s")), T, log(_rs("c26"))), E, eq(X, E))),
        # ── the others of the family, and the goal's own cut ──
        (_rf("k27", X), _rf("call_cleanup", eq(X, _rg(1)), log(_rs("c27")))),
        (_rf("k28", X), _rf("call_cleanup", _rf("p", X), log(_rs("c28")))),
        (_rf("k29", X), scc(T, _rconj(_rf("p", X), _rs("!")), log(_rs("c29")))),
        # an unbound goal: the frame is a cleanup frame already when the error is raised
        (_rf("k30", X), c3(scc(T, Y, log(_rs("c30"))), _rf("error", E, Z), eq(X, E))),
        # ── V9g's battery: the cut of a CONDITION discards the goal's choice points (`c_cut`) ──
        (_rf("k31", X), _rite(scc(T, _rf("p", X), log(_rs("c31"))), T, T)),
        (_rf("k32", X, C), _rite(sccc(T, _rf("p", X), C, log(_rf("c32", C))), T, T)),
        # an exception from outside: the goal's bindings are UNDONE before the handler runs
        (
            _rf("k33", X),
            c3(
                _rconj(
                    sccc(
                        T, _rconj(_rf("p", Y), eq(Z, _rs("seen"))), C,
                        log(_rf("c33", C, Y, Z))
                    ),
                    th(_rs("b"))
                ),
                E,
                eq(X, E)
            )
        ),
        # a cleanup goal that is not callable is refused BEFORE the goal runs: nothing is logged
        (
            _rf("k34", X),
            c3(
                scc(T, log(_rs("g34")), _rg(1)),
                _rf("error", _rf("type_error", X, Y), Z),
                T
            )
        )
    ]
end

"Every case, each followed by the log so far."
function _rcl_goals()
    X, C, L = _rv(51), _rv(52), _rv(53)
    catcher = (6, 7, 8, 9, 10, 11, 32)
    g = _R[]
    for k in 1:_RCL_N
        push!(g, k in catcher ? _rf("k$k", X, C) : _rf("k$k", X))
        push!(g, _rf("logs", L))
    end
    return g
end

"The kernel's lines for `goals`, the pools checked and no exception pending at every answer."
function _rcl_ours(clauses, goals)
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
    return ours, db
end

@testset "the cleanup family: answers, determinism and what the cleanup goals logged equal swipl's" begin
    clauses = _rcl_clauses()
    goals = _rcl_goals()
    ours, db = _rcl_ours(clauses, goals)
    @test count(==("end"), ours) == length(goals)
    # every way out was logged, ONCE (the log grows: the last listing holds all of it): exit, fail,
    # cut, exception — and the catcher's five values
    ends = findall(==("end"), ours)
    final = ours[(ends[end - 1] + 1):(ends[end] - 1)]
    for item in ("c1", "c2", "c3", "c4", "c5", "c6(exit)", "c7(fail)", "c8(!)",
        "c9(exception(b))", "c11(external_exception(b))", "in12", "out12")
        @test count(l -> startswith(l, "logs($item)"), final) == 1
    end
    if _R_SWIPL
        theirs = _rswipl(clauses, goals; extra=":- dynamic logged/1.\n")
        @test ours == theirs
        if ours != theirs
            k = findfirst(i -> i > length(theirs) || ours[i] != theirs[i], eachindex(ours))
            k = something(k, length(ours) + 1)
            println(stderr, "  first difference at line ", k, "\n    kernel ",
                get(ours, k, "—"), "\n    swipl  ", get(theirs, k, "—"))
        end
    elseif _R_SWIPL_REQUIRED
        @test false
    end
end

# White box: the frame flags. A cleanup frame carries `FR_CLEANUP` from `I_CALLCLEANUP` on, and
# `FR_CAUGHT` once its handler ran; a frame called from it carries neither (FR_CLEAR_NEXT).
@testset "FR_CLEANUP on the cleanup frame, not on the frames below it" begin
    db = _rdb(_rcl_clauses())
    seen = Vector{Tuple{Int, Int}}()
    _rcall(
        db,
        _rf("k5", _rv(81));
        at=(qid, k) -> push!(
            seen,
            (
                count(
                    i -> (db.ld.frames[i].flags & LK.FR_CLEANUP) != 0, 1:(db.ld.nframes)
                ),
                count(
                    i ->
                        (db.ld.frames[i].flags & (LK.FR_CLEANUP | LK.FR_CAUGHT)) ==
                        (LK.FR_CLEANUP | LK.FR_CAUGHT),
                    1:(db.ld.nframes)
                )
            )
        )
    )
    @test length(seen) == 3
    @test seen[1] == (1, 0) && seen[2] == (1, 0)    # p/1 has answers left: the handler has not run
end

"What was logged so far, through a query of its own."
_rcall_logged(db::_RDB)::Vector{String} =
    if LK.isCurrentProcedure(sym_key(_rs("logged")), 1, db.user) === nothing
        String[]
    else
        [a for (a, _) in _rcall(db, _rf("logs", _rv(91)))]
    end

# White box: a query CUT while its goal has choice points left runs the handler (pl-wam.c
# `discard_query`: `frameFinished(&qf->frame, FINISH_CUT)`) — the query's own frame is the
# cleanup frame here.
@testset "cutting a query whose goal is a cleanup frame with answers left runs its handler" begin
    db = _rdb(_rcl_clauses())
    gd, ld = db.gd, db.ld
    X, C = _rv(81), _rv(82)
    goal = _rf(
        "setup_call_catcher_cleanup", _rs("true"), _rf("p", X), C, _rf("log", _rf("q", C))
    )
    fid = LK.PL_open_foreign_frame(ld)
    args = LK.PL_new_term_refs(ld, 4)
    for i in 1:4
        ld.slots[args + i] = child(goal, i + 1)
    end
    proc = LK.lookupProcedure(_rs("setup_call_catcher_cleanup"), 4, LK.MODULE_system(gd))
    qid = LK.PL_open_query(gd, ld, nothing, LK.PL_Q_NORMAL | LK.PL_Q_EXT_STATUS, proc, args)
    @test LK.PL_next_solution(gd, ld, qid) == LK.PL_S_TRUE
    @test isempty(_rcall_logged(db))                # not yet: p/1 has answers left
    LK.PL_cut_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
    @test _rcall_logged(db) == ["logs(q(!))"]
    @test _rpools_live(ld)
end

# KNOWN DIFFERENCE, pinned (R2 checklist: "meta-argument qualification of the cleanup family"):
#   kernel: `type_error(callable, 1)` — the cleanup goal arrives unqualified
#   swipl 10.1.18: `type_error(callable, user:1)` — setup_call_cleanup/3 is a meta-predicate
#     (boot/init.pl:381), so its arguments arrive as `Module:Goal` (probed)
@testset "a cleanup goal that is not callable: type_error(callable, Goal), the goal unqualified (R2)" begin
    X, E, Z = _rv(1), _rv(2), _rv(3)
    db = _rdb([
        (
        _rf("nc", X),
        _rf(
            "catch",
            _rf("setup_call_cleanup", _rs("true"), _rs("true"), _rg(1)),
            _rf("error", E, Z),
            _rf("=", X, E)
        )
    )
    ])
    @test [a for (a, _) in _rcall(db, _rf("nc", _rv(51)))] == ["nc(type_error(callable,1))"]
end

# Where the handler runs when the goal FAILS, read with prolog_current_frame/1 on both sides as the
# difference from the caller's frame: backtracking into the cleanup frame's choice point lowers
# `lTop` to just above it (pl-vmi.c: `lTop = (LocalFrame)(BFR+1)`), so the handler's frame lands at
# the same place however deep the goal went before it failed (MG18's kill test).
function _rcl_pos_clauses()
    F0, F, D, N, M, K = _rv(1), _rv(2), _rv(3), _rv(4), _rv(5), _rv(6)
    pcf(v) = _rf("prolog_current_frame", v)
    return Tuple{_R, Union{Nothing, _R}}[
        (
            _rf("lp", K, F0),
            _rconj(
                pcf(F), _rf("is", D, _rf("-", F, F0)), _rf("assertz", _rf("posd", K, D))
            )
        ),
        (
            _rf("dfail", N),
            _rconj(
                _rf(">", N, _rg(0)), _rf("is", M, _rf("-", N, _rg(1))), _rf("dfail", M),
                _rs("true")
            )
        ),
        (
            _rf("hp", N, D),
            _rconj(
                pcf(F0),
                _ror(
                    _rf(
                        "setup_call_cleanup", _rs("true"), _rf("dfail", N), _rf("lp", N, F0)
                    ),
                    _rs("true")
                ),
                _rf("posd", N, D)
            )
        )
    ]
end

@testset "the handler's frame at a failure is at one position, whatever the goal's depth — swipl's" begin
    clauses = _rcl_pos_clauses()
    depths = (1, 5, 40)
    db = _rdb(clauses)
    ours = Int[]
    for n in depths
        ans = _rcall(db, _rf("hp", _rg(n), _rv(80)))
        @test length(ans) == 1
        push!(ours, parse(Int, match(r",(-?\d+)\)", first(ans[1]))[1]))
    end
    @test ours[1] == ours[2] == ours[3]
    if _R_SWIPL
        main =
            "main :- " *
            join(("hp($n, D$n), writeln(D$n)" for n in depths), ", ") * "."
        theirs = parse.(
            Int, _rswipl(clauses, (); extra=":- dynamic posd/2.\n", main_text=main)
        )
        ours == theirs || println(stderr, "  positions, kernel: ", ours, " swipl: ", theirs)
        @test ours == theirs
    elseif _R_SWIPL_REQUIRED
        @test false
    end
end
