# ORIGINAL: `$/1` and `$/0` (V9f) — the determinism guards — against a LIVE swipl. It holds the `det_guard` and `det_goal` units of upstream's tests/core_lang/test_det_decl.pl (cases d33-d37) without their `with_debug/1` twins and `garbage_collect/0`; that file's mirror, test_det_decl.jl, waits for the `det/1` declaration and plunit (R2), so this file shadows no upstream path.
# test/core_lang/test_det_swipl.jl — pl-vmi.c I_DET, C_DET, C_DETTRUE, C_DETFALSE; pl-comp.c det_goal_error, start_of_cdet; pl-wam.c determinism_error, frameFailed, the code under test
using Test, LogicKernel, Random
# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const LK = LogicKernel
include(joinpath(@__DIR__, "rules_common.jl"))

# Every case is a predicate `dN/1`; `tN(X, E)` calls it under catch/3, so an answer shows the
# binding or the ball. The expected shapes are swipl's (probed, 10.1.18): a `$(Goal)` that leaves a
# choice point or fails raises `determinism_error(Goal, det, nondet|fail, goal)`; after `$` the
# clause must exit without a choice point and must not fail — `guard` when the frame is the one
# that ran `$`, `guard_in_caller` when a last call reused that frame.
const _RDT_N = 38
function _rdt_clauses()
    X, Y, Z, E = _rv(1), _rv(2), _rv(3), _rv(4)
    d(g) = _rf("\$", g)
    D = _rs("\$")
    eq(a, b) = _rf("=", a, b)
    cases = Tuple{_R, Union{Nothing, _R}}[
        (_rf("p", _rg(1)), nothing), (_rf("p", _rg(2)), nothing),
        (_rf("w2", _rs("a")), nothing),
        (_rf("w3", _rs("a")), nothing), (_rf("w3", _rs("b")), nothing),
        (_rf("k1", X), _rf("k2", X)), (_rf("k2", X), _rf("==", X, _rg(1))),
        (_rf("k4", X), _rconj(_rf("w3", Y), eq(X, _rg(1)))),
        (_rf("nope", X, Y, Z), _rs("fail")),
        # ── $/1 ──
        (_rf("d1", X), d(_rf("p", X))),                         # leaves a choice point
        (_rf("d2", X), d(eq(X, _rg(1)))),                       # deterministic
        (_rf("d3", X), _rconj(d(_rs("fail")), eq(X, _rg(1)))),  # fails
        (_rf("d4", X), d(_rconj(_rf("p", X), _rs("!")))),       # the cut is local to the goal
        (_rf("d5", X), _ror(_rit(d(_rf("p", X)), _rs("true")), _rs("true"))),
        (_rf("d6", X), _rconj(_rnot(d(_rs("fail"))), eq(X, _rg(1)))),
        (_rf("d7", X), d(d(_rf("p", X)))),                      # nested: the inner one reports
        (_rf("d8", X), d(_rconj(d(eq(X, _rg(1))), _rf("p", Y)))),   # nested: the outer one
        (_rf("d9", X), _rconj(d(_rf("nope", X, Y, _rf("f", Z))), eq(X, _rg(1)))),   # fresh variables
        (_rf("d10", X), _ror(_rconj(eq(X, _rg(1)), d(_rf("p", Y))), eq(X, _rg(2)))),
        (_rf("d11", X), _rconj(_rf("p", X), _rf("catch", d(_rf("p", Y)), E, _rs("true")))),
        (_rf("d12", X), _rconj(_rf("p", X), d(eq(X, _rg(2))))), # fails for the first answer of p
        # the block's record, then an answer of a call that is not the last
        (_rf("d13", X), _rconj(d(eq(X, _rg(1))), _rf("p", Y), _rf("nonvar", Y))),
        (_rf("d14", X), d(_rs("!"))),
        (_rf("d15", X), _rconj(d(_rf("w3", Y)), eq(X, Y))),     # the goal's variable is bound in the ball
        # ── $/0 ──
        (_rf("d16", X), _rconj(_rf("p", X), D, _rf("nonvar", X))),  # cuts p's choice point
        (_rf("d17", X), _rconj(D, _rf("p", X))),                # last call: guard_in_caller, nondet
        (_rf("d18", X), _rconj(D, eq(X, _rg(1)))),
        (_rf("d19", X), _rconj(D, _rs("fail"))),                # guard, fail
        (_rf("d20", X), _rconj(D, _rf("w2", X))),               # last call: fails in the callee
        (_rf("d21", X), _rconj(D, _rf("w3", X))),
        (_rf("d22", X), _rconj(D, _rf("w3", Y), _rf("==", Y, _rs("b")), eq(X, Y))),
        (_rf("d23", X), _rconj(D, _ror(_rf("w3", X), eq(X, _rs("c"))))),    # guard, nondet
        (_rf("d24", X), _rconj(D, _rf("w3", X), _rs("!"))),
        (_rf("d25", X), _rconj(D, _rf("k1", X))),               # the guard two last calls down
        (_rf("d26", X), _rconj(D, _rf("k4", X), _rf("nonvar", X))), # a callee's choice point at exit
        (_rf("d27", X), _rconj(_rf("p", X), D)),                # `$` last
        (_rf("d28", _rg(1)), D), (_rf("d28", _rg(2)), nothing), # `$` cuts the clause alternatives
        (_rf("d29", X), _rconj(D, _rf("p", Y), D, eq(X, Y))),   # twice
        (_rf("d30", X), _rconj(D, d(_rf("p", X)))),             # the goal error comes first
        (_rf("d31", X), _rconj(D, _rf("nope", X, Y, Z))),       # a callee with a clause that fails
        # through call/1: the goal's own temporary clause holds the block
        (_rf("d32", X), _rconj(eq(Y, d(_rf("p", X))), _rf("call", Y))),
        # ── upstream's tests/core_lang/test_det_decl.pl: det_guard (d33), det_goal (d34-d37) ──
        (_rf("nd", X), _rf("nd2", X)), (_rf("nd2", X), _rf("nd3", X)),
        (_rf("nd3", _rg(1)), nothing), (_rf("nd3", _rg(2)), nothing),
        (_rf("nd3", _rg(2)), nothing),
        (_rs("uend"), nothing), (_rf("u", X), nothing),
        (_rf("ndd", _rg(1)), nothing), (_rf("ndf", _rg(1)), _rs("fail")),
        (_rf("d33", X), _rconj(D, _rf("nd", X))),               # d(X) :- $, nd(X).
        (_rf("d34", X), _rconj(d(_rf("nd", X)), _rs("uend"))),  # d(X) :- $nd(X), end.
        (_rf("d35", X), _rconj(d(_rf("ndd", Y)), _rf("u", Y), eq(X, Y))),   # d1
        (_rf("d36", X), _rconj(d(_rf("nd3", Y)), _rf("u", Y), eq(X, Y))),   # d2
        (_rf("d37", X), _rconj(d(_rf("ndf", Y)), _rf("u", Y), eq(X, Y))),   # d3
        # A goal that fails BEFORE it initialises two of its variables, in a frame whose region
        # held another frame's arguments: the ball shows fresh variables there — pl-gc.c
        # `clearUninitialisedVarsFrame` (without it: `q3(A,g2,g3)`).
        (_rf("fill5", _rv(31), _rv(32), _rv(33), _rv(34), _rv(35)), nothing),
        (_rf("q3", X, Y, Z), nothing),
        (
            _rf("d38i", X),
            _rconj(d(_rconj(_rf("==", X, _rg(1)), _rf("q3", X, Y, Z))), _rf("q3", X, Y, Z))
        ),
        (
            _rf("d38", X),
            _rconj(
                _rf("fill5", _rs("g1"), _rs("g2"), _rs("g3"), _rs("g4"), _rs("g5")),
                _rf("d38i", X), _rs("true")
            )
        )
    ]
    for k in 1:_RDT_N
        push!(cases, (_rf("t$k", X, E), _rf("catch", _rf("d$k", X), E, _rs("true"))))
    end
    return cases
end

"The goals: every case with its argument unbound, and the ones whose answer depends on it bound."
function _rdt_goals()
    X, E = _rv(51), _rv(52)
    g = _R[_rf("t$k", X, E) for k in 1:_RDT_N]
    append!(
        g,
        _R[
            _rf("t20", _rs("a"), E), _rf("t20", _rs("b"), E), _rf("t21", _rs("b"), E),
            _rf("t25", _rg(1), E), _rf("t25", _rg(2), E), _rf("t28", _rg(2), E),
            _rf("t17", _rg(2), E), _rf("t1", _rg(2), E), _rf("t12", _rg(2), E),
            # no clause of w3/1 matches: the frame's `CHP_DEBUG` choice point (S_STATIC) reports,
            # and under `warning` the failing frame reports again — twice, as swipl
            _rf("t21", _rs("c"), E),
            # upstream's units: det (1), nondet (2: two clauses match), fail (3: none does)
            _rf("t33", _rg(1), E), _rf("t33", _rg(2), E), _rf("t33", _rg(3), E),
            _rf("t34", _rg(1), E), _rf("t34", _rg(2), E), _rf("t34", _rg(3), E)
        ]
    )
    return g
end

"The kernel's lines for `goals` under the flag value `flag`, the pools checked at every answer."
function _rdt_ours(clauses, goals, flag::Symbol)
    db = _rdb(clauses)
    db.ld.prolog_flag_determinism_error = flag
    ours = String[]
    for g in goals
        for (a, det) in _rcall(db, g; at=(qid, k) -> (@test _rpools_live(db.ld)))
            push!(ours, a * (det ? " det" : " nondet"))
        end
        push!(ours, "end")
    end
    return ours, db
end

function _rdt_compare(ours, theirs)
    @test ours == theirs
    if ours != theirs
        k = findfirst(i -> i > length(theirs) || ours[i] != theirs[i], eachindex(ours))
        k = something(k, length(ours) + 1)
        println(stderr, "  first difference at line ", k, "\n    kernel ",
            get(ours, k, "—"),
            "\n    swipl  ", get(theirs, k, "—"))
    end
end

@testset "\$/1 and \$/0: answers, balls and determinism equal swipl's, the pools live at every answer" begin
    clauses = _rdt_clauses()
    goals = _rdt_goals()
    ours, db = _rdt_ours(clauses, goals, :error)
    @test count(==("end"), ours) == length(goals)
    # both kinds of ball, each of the three declarations, and plain answers
    for needle in (",det,nondet,goal)", ",det,fail,goal)", ",det,nondet,guard)",
        ",det,fail,guard)", ",det,nondet,guard_in_caller)", ",det,fail,guard_in_caller)")
        @test count(l -> occursin(needle, l), ours) >= 1
    end
    @test count(l -> !occursin("determinism_error", l) && l != "end", ours) >= 12
    @test isempty(db.ld.messages)                               # an error is raised, not reported
    if _R_SWIPL
        _rdt_compare(ours, _rswipl(clauses, goals))
    elseif _R_SWIPL_REQUIRED
        @test false
    end
end

@testset "determinism_error = silent: nothing is raised or reported, the goals answer as without the guard" begin
    clauses = _rdt_clauses()
    goals = _rdt_goals()
    ours, db = _rdt_ours(clauses, goals, :silent)
    @test !any(l -> occursin("determinism_error", l), ours)
    @test isempty(db.ld.messages)
    if _R_SWIPL
        _rdt_compare(
            ours,
            _rswipl(
                clauses, goals; extra=":- set_prolog_flag(determinism_error, silent).\n"
            )
        )
    elseif _R_SWIPL_REQUIRED
        @test false
    end
end

# Under `warning` the error term is reported and the goal goes on. swipl's side collects what
# print_message/2 is given (a `message_hook` that keeps the term and prints nothing), in order.
const _RDT_HOOK = raw"""
:- set_prolog_flag(determinism_error, warning).
:- dynamic rdt_warned/1.
:- multifile user:message_hook/3.
user:message_hook(error(determinism_error(A, B, C, D), _), warning, _) :-
    assertz(rdt_warned(determinism_error(A, B, C, D))).
"""

@testset "determinism_error = warning: the same answers, and the reported terms equal swipl's, in order" begin
    clauses = _rdt_clauses()
    goals = _rdt_goals()
    ours, db = _rdt_ours(clauses, goals, :warning)
    @test !any(l -> occursin("determinism_error", l), ours)
    reported = String[]
    for (severity, msg) in db.ld.messages
        @test severity === :warning
        @test kind(msg) === EXPR && nchildren(msg) == 3 &&
            _ratom_text(child(msg, 1)) == "error"
        push!(reported, _rcanonical(child(msg, 2)))
    end
    @test length(reported) >= 15
    if _R_SWIPL
        main =
            "main :- " * join(("r($(_rsrc(g)))" for g in goals), ", ") *
            ", forall(rdt_warned(W), (write_canonical(W), nl))."
        theirs = _rswipl(clauses, goals; extra=_RDT_HOOK, main_text=main)
        _rdt_compare([ours; reported], theirs)
    elseif _R_SWIPL_REQUIRED
        @test false
    end
end

"The positions in `cl`'s code that hold an instruction (not an operand)."
function _rdt_op_positions(cl)::Vector{Int}
    out = Int[]
    pc = 1
    while pc <= length(cl.codes)
        push!(out, pc)
        pc += 1 + LK.codeTable(cl.codes[pc]).arguments
    end
    return out
end

# White box. `start_of_cdet` (pl-comp.c) finds the block an error location belongs to: for nested
# blocks the inner `C_DETTRUE` belongs to the inner `C_DET`, the outer one to the outer.
@testset "start_of_cdet: the block of each C_DETTRUE and C_DETFALSE, nested blocks apart" begin
    db = _rdb(_rdt_clauses())
    cl = _rproc(db, _rf("d7", _rv(81))).definition.impl_clauses.first_clause.clause
    pos = _rdt_op_positions(cl)
    dets = [k for k in pos if cl.codes[k] == LK.C_DET]
    trues = [k for k in pos if cl.codes[k] == LK.C_DETTRUE]
    falses = [k for k in pos if cl.codes[k] == LK.C_DETFALSE]
    @test length(dets) == 2 && length(trues) == 2 && length(falses) == 2
    # in code order: outer C_DET, inner C_DET, inner C_DETTRUE, inner C_DETFALSE, outer C_DETTRUE, …
    @test LK.start_of_cdet(cl, trues[1]) == dets[2]
    @test LK.start_of_cdet(cl, falses[1]) == dets[2]
    @test LK.start_of_cdet(cl, trues[2]) == dets[1]
    @test LK.start_of_cdet(cl, falses[2]) == dets[1]
end

# White box. A `$(Goal)` that succeeded takes its own choice point out of the chain and leaves the
# stack where it is (pl-vmi.c C_DETTRUE): the record stays below `lTop`, marked unlinked, until the
# region is popped — `_rpools_live` at d13's answers (above) accepts exactly that. And the guard
# flags: `$/0` sets both on its frame; a frame made by a call has neither.
@testset "the guard's frame flags and the block's unlinked record" begin
    db = _rdb(_rdt_clauses())
    seen = Tuple{Int, Int}[]
    _rcall(
        db,
        _rf("d13", _rv(81));
        at=(qid, k) -> push!(
            seen,
            (
                count(i -> db.ld.choices[i].unlinked, 1:(db.ld.nchoices)),
                count(
                    i -> (db.ld.frames[i].flags & LK.FR_DETGUARD) != 0,
                    1:(db.ld.nframes)
                )
            )
        )
    )
    @test length(seen) == 2
    @test seen[1] == (1, 0)                                     # the block's record, no guard
    db2 = _rdb(_rdt_clauses())
    flags = UInt32[]
    _rcall(
        db2,
        _rf("d23", _rv(81));                                    # `$, (w3(X) ; X = c)` under silent
        at=(qid, k) -> append!(
            flags,
            [
                db2.ld.frames[i].flags & (LK.FR_DETGUARD | LK.FR_DETGUARD_SET) for
                i in 1:(db2.ld.nframes) if
                (db2.ld.frames[i].flags & LK.FR_DETGUARD) != 0
            ]
        )
    )
    @test isempty(flags)                                        # under `error` there is no answer
    db2.ld.prolog_flag_determinism_error = :silent
    _rcall(
        db2,
        _rf("d23", _rv(81));
        at=(qid, k) -> append!(
            flags,
            [
                db2.ld.frames[i].flags & (LK.FR_DETGUARD | LK.FR_DETGUARD_SET) for
                i in 1:(db2.ld.nframes) if
                (db2.ld.frames[i].flags & LK.FR_DETGUARD) != 0
            ]
        )
    )
    @test !isempty(flags) && all(==(LK.FR_DETGUARD | LK.FR_DETGUARD_SET), flags)
end
