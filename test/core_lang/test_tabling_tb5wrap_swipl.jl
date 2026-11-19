# ORIGINAL: LIVE rows for a WRAPPED predicate that is made dynamic, made static and abolished (TAB1 TB5-WRAP, S3f; audit D-0884 (2)),
# pinned on swipl at 18168e62 (10.1.20). `freeCodesDefinition!(gd, def, ...)` resets a wrapped predicate through its closure; the method
# WITHOUT the database raises NotPortedError for one. The three TB5 mutants that take the 2-argument method (TB5-P1 in `_setDynamicDefinition!`,
# TB5-P3 in `_resetProcedure!`, TB5-P7 in the abolish path) are reached only by a wrapped predicate, which the DYN files never build.
#   * a predicate wrapped with `'$wrap_predicate'/5` (the wrapper body logs `called`, then calls the wrapped predicate), then
#     `dynamic/1` (P1), `'$set_predicate_attribute'(_, dynamic, false)` (P1, the other direction), `abolish/1` over a static, a dynamic and a
#     clause-less wrapped predicate (P3 and P7: `resetProcedure!` runs in the abolish path).
#   * every answer is `~q` of `r(...)`: the wrapper count `'$wrapped_predicate'/2` before and after, the predicate's state, the
#     answers and the log. Each pin is swipl's own (swipl 10.1.20, two identical runs, evidence/TAB1/s3f_handoff.md), compared with the
#     kernel's and, with `swipl` on PATH, with a live run. The case ids name the mutants they kill.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — these built-ins ride the term layer through the FLI (unify, get, the trie blobs)
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TW_T = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_tws(x) = lk_sym(_TW_T, Symbol(x))

"The helpers every unit's program starts with: the case runner `tw_q/2` (the `~q` text of the answer, an error as `exc(Formal)`), the wrapper and its readers."
const _TW_COMMON = raw"""
:- dynamic log/1.
tw_q(G, A) :- ( catch(call(G, R), error(E, _), R = exc(E)) -> true ; R = failed ), format(atom(A), "~q", [R]).
tw_wrap(H) :- '$wrap_predicate'(user:H, wp, _C, W, (assertz(log(called)), W)).
tw_wr(H, N) :- ( '$wrapped_predicate'(user:H, L) -> length(L, N) ; N = none ).
tw_log(L) :- findall(X, retract(log(X)), L).
tw_pd(H, P) :- ( predicate_property(user:H, dynamic) -> P = isdyn ; predicate_property(user:H, defined) -> P = static ; P = undefined ).
tw_all(H, Xs) :- H =.. [_, X], catch(findall(X, H, Xs), error(E, _), Xs = exc(E)).
"""

"The program of a unit: the helpers, the unit's clauses, the cases."
_tw_text(u) =
    _TW_COMMON * u.program * join(["t_$(id)(R) :- $body.\n" for (id, body) in u.cases])

"The `~q` text of each case's answer, in order, from swipl at the pin."
function _tw_swipl_lines(u)::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "tw.pl")
        write(
            f,
            _tw_text(u) * ":- initialization((forall(member(G, [" *
            join(["t_$id" for (id, _) in u.cases], ",") *
            "]), (tw_q(G, A), write(A), nl)), halt)).\n"
        )
        read(
            pipeline(addenv(`swipl -q $f`, "LC_ALL" => "C"); stdin=devnull, stderr=devnull),
            String
        )
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

"The `~q` text of the answer of `case`, run as `tw_q(case, A)` in the kernel."
function _tw_ask(gd, ld, case::String)::String
    proc = LK.isCurrentProcedure(sym_key(_tws("tw_q")), 2, LK.MODULE_user(gd))
    (proc === nothing || !LK.isDefinedProcedure(gd, proc)) && return "tw_q undefined"
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 2)
    LK.putSlotValue!(ld, a + 1, _tws(case), LK.PutVarMap())
    LK.putSlotValue!(ld, a + 2, mk_var(_TW_T, LK.fresh_var_keys!(1)), LK.PutVarMap())
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    rc = LK.PL_next_solution(gd, ld, qid)
    ans = if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
        t = lk_answers(ld, ((a + 1):(a + 1))...)[1]
        kind(t) === SYM ? sym_text(t) : "not an atom"
    else
        rc == LK.PL_S_EXCEPTION ? "exception" : "failed"
    end
    LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
    return ans
end

"A kernel with the unit's program consulted: `(gd, ld, load status)`."
function _tw_load(u)
    f = joinpath(mktempdir(), "tabling_tb5wrap.pl")
    write(f, _tw_text(u))
    gd = LK.PL_global_data{_TW_T}()
    ld = LK.PL_local_data{_TW_T}(gd)
    st, _ = LK.load_file!(gd, ld, f)
    return gd, ld, st
end

"The indices where two answer lists differ (a missing answer counts as a difference)."
_tw_diff(lines::Vector{String}, pins::Vector{String}) =
    [
        i for i in 1:max(length(lines), length(pins)) if
        i > length(lines) || i > length(pins) || lines[i] != pins[i]
    ]

"The must-fail corruptions of a comparison: a corrupted pin, an extra pin, a dropped pin and a corrupted kill row are each flagged."
function _tw_flagged(lines::Vector{String}, pins::Vector{String}, kill::Vector{Int})::Bool
    base = _tw_diff(lines, pins)
    corrupt = copy(pins)
    corrupt[1] = corrupt[1] * "x"
    ok = _tw_diff(lines, corrupt) == sort(union(base, [1]))
    ok &= _tw_diff(lines, vcat(pins, "extra")) == sort(union(base, [length(pins) + 1]))
    ok &= _tw_diff(lines, pins[1:(end - 1)]) == sort(union(base, [length(pins)]))
    for k in kill
        c = copy(pins)
        c[k] = "wrong"
        ok &= _tw_diff(lines, c) == sort(union(base, [k]))
    end
    return ok
end

const _TW_PROGRAM = raw"""
wa1(1).
wa1(2).
wd1(1).
wu1(1).
wa2(1).
"""

"The cases: `(id, body)`; the comment after each names the mutants it kills."
const _TW_CASES = [
    (
        "dyn1",
        raw"tw_wrap(wb1(_)), tw_wr(wb1(_), W0), dynamic(wb1/1), tw_pd(wb1(_), P), tw_wr(wb1(_), W1), assertz(wb1(7)), wb1(X), tw_log(L), R = r(W0, P, W1, X, L)"
    ),   # TB5-P1: an undefined predicate WRAPPED, then made dynamic: the wrapper stays (1 wrapper), the predicate answers and the wrapper body logs the call
    (
        "dyn2",
        raw"tw_wrap(wb2(_)), dynamic(wb2/1), assertz(wb2(7)), tw_log(_), '$set_predicate_attribute'(wb2(_), dynamic, false), tw_pd(wb2(_), P), tw_wr(wb2(_), W1), tw_all(wb2(_), Xs), tw_log(L), R = r(P, W1, Xs, L)"
    ),   # TB5-P1: the other direction (dynamic --> static) over a wrapped predicate
    (
        "dyn3",
        raw"tw_wrap(wb3(_)), dynamic(wb3/1), tw_wr(wb3(_), W1), dynamic(wb3/1), tw_wr(wb3(_), W2), tw_all(wb3(_), Xs), tw_log(L), R = r(W1, W2, Xs, L)"
    ),   # control: `dynamic` twice over a wrapped predicate (the second returns before the reset)
    (
        "abs1",
        raw"tw_wrap(wa1(_)), tw_wr(wa1(_), W0), abolish(wa1/1), tw_pd(wa1(_), P), tw_wr(wa1(_), W1), tw_log(L0), tw_all(wa1(_), Xs), tw_log(L), R = r(W0, L0, P, W1, Xs, L)"
    ),   # TB5-P3, TB5-P7: abolish of a STATIC wrapped predicate with clauses (resetProcedure! over the wrapper): the wrapper stays, the predicate is undefined
    (
        "abs2",
        raw"tw_wrap(wa2(_)), abolish(wa2/1), assertz(wa2(9)), tw_all(wa2(_), Xs), tw_log(L), tw_pd(wa2(_), P), tw_wr(wa2(_), W), R = r(Xs, L, P, W)"
    ),   # TB5-P3, TB5-P7: the abolished wrapped predicate is dynamic again once a clause is added
    (
        "abd1",
        raw"tw_wrap(wd1(_)), tw_wr(wd1(_), W0), dynamic(wd1/1), abolish(wd1/1), tw_pd(wd1(_), P), tw_wr(wd1(_), W1), tw_all(wd1(_), Xs), tw_log(L), R = r(W0, P, W1, Xs, L)"
    ),   # TB5-P1, TB5-P3, TB5-P7: wrapped, made dynamic, abolished (setDynamicDefinition! false, then resetProcedure!)
    (
        "abu1",
        raw"tw_wrap(wu1(_)), abolish(wu1/1), tw_pd(wu1(_), P), tw_wr(wu1(_), W1), assertz(wu1(5)), wu1(X), tw_log(L), R = r(P, W1, X, L)"
    ),   # TB5-P3, TB5-P7: wrapped before any clause, abolished, then asserted
    (
        "abd2",
        raw"tw_wrap(wd2(_)), dynamic(wd2/1), assertz(wd2(1)), abolish(wd2/1), tw_pd(wd2(_), P), tw_wr(wd2(_), W1), assertz(wd2(5)), wd2(X), tw_log(L), tw_pd(wd2(_), P2), R = r(P, W1, X, L, P2)"
    ),   # TB5-P1, TB5-P3, TB5-P7: a dynamic wrapped predicate with a clause, abolished
    (
        "ctl",
        raw"assertz(wc1(1)), abolish(wc1/1), tw_pd(wc1(_), P), tw_all(wc1(_), Xs), R = r(P, Xs)"
    )   # control: abolish of a predicate that is NOT wrapped
]

const _TW_UNIT = (
    unit="tb5wrap",
    program=_TW_PROGRAM,
    cases=_TW_CASES,
    kill=["dyn1", "dyn2", "abs1", "abs2", "abd1", "abu1", "abd2"],
    # swipl 10.1.20, `tw_q(t_<case>, A)` in order, two identical runs
    pinned=[
        "r(1,isdyn,1,7,[called])",   # dyn1
        "r(static,1,[7],[])",   # dyn2
        "r(1,1,[],[])",   # dyn3
        "r(1,[],undefined,1,exc(existence_error(procedure,wa1/1)),[])",   # abs1
        "r([9],[],isdyn,1)",   # abs2
        "r(1,undefined,1,exc(existence_error(procedure,wd1/1)),[])",   # abd1
        "r(undefined,1,5,[called])",   # abu1
        "r(undefined,1,5,[called],isdyn)",   # abd2
        "r(undefined,exc(existence_error(procedure,wc1/1)))"   # ctl
    ]
)

"The three testsets of one unit (every one runs >= 1 assertion with or without `swipl`, and each proves its comparison can fail)."
function _tw_check_unit(u)
    ids = [id for (id, _) in u.cases]
    kidx = [findfirst(==(k), ids)::Int for k in u.kill]
    @testset "$(u.unit)" begin
        gd, ld, st = _tw_load(u)
        lines = String[_tw_ask(gd, ld, "t_$id") for id in ids]
        @testset "$(u.unit): the rows run as swipl's pins (kills $(join(u.kill, ", ")))" begin
            @test st === :ok
            @test !isempty(lines) && !isempty(u.pinned) &&
                length(lines) == length(u.pinned) == length(ids)
            for (id, k, p) in zip(ids, lines, u.pinned)
                k == p || println(stderr, "  ours  ", id, " ", k, "\n  swipl ", p)
                @test k == p
            end
            @test _tw_flagged(lines, u.pinned, kidx)        # a corrupted pin is flagged, kill rows included
        end
        @testset "$(u.unit): the pins are well formed; the comparison can fail" begin
            @test allunique(ids)
            @test length(u.pinned) == length(ids)
            @test all(!isempty, u.pinned)
            @test _tw_flagged(u.pinned, u.pinned, kidx)
        end
        @testset "$(u.unit): the pins are swipl's (live, when swipl is on PATH)" begin
            if Sys.which("swipl") === nothing || get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1"
                @info "TB5-WRAP LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
                @test length(u.pinned) == length(ids)
                @test _tw_flagged(u.pinned, u.pinned, kidx)
            else
                live = _tw_swipl_lines(u)
                @test live == u.pinned
                @test _tw_flagged(live, u.pinned, kidx)
            end
        end
    end
    return nothing
end

_tw_check_unit(_TW_UNIT)

# ── NOT VACUOUS: each kill row shows the value the mutants change ──────────────────────────────────────────────────
@testset "TB5-WRAP: the kill rows hold a wrapped predicate and the answer a thrown error would replace" begin
    ids = [id for (id, _) in _TW_CASES]
    pin(k) = _TW_UNIT.pinned[findfirst(==(k), ids)::Int]
    # the wrapper is still there after the reset (`'$wrapped_predicate'/2` counts 1): the mutants raise NotPortedError instead of resetting
    for k in ("dyn1", "dyn2", "abs1", "abd1", "abu1", "abd2")
        @test !occursin("NotPorted", pin(k)) && !occursin("failed", pin(k))
    end
    @test pin("dyn2") == "r(static,1,[7],[])"
    @test pin("abs2") == "r([9],[],isdyn,1)"
    @test pin("abs1") == "r(1,[],undefined,1,exc(existence_error(procedure,wa1/1)),[])"
    @test pin("abd1") == "r(1,undefined,1,exc(existence_error(procedure,wd1/1)),[])"
    @test pin("dyn1") == "r(1,isdyn,1,7,[called])"
    @test pin("abu1") == "r(undefined,1,5,[called])"
    # the control without a wrapper is the same abolish: undefined, calling raises the existence error
    @test pin("ctl") == "r(undefined,exc(existence_error(procedure,wc1/1)))"
end
