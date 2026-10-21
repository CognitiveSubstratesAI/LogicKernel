# ORIGINAL: the Julia-facing query helper `query_answers` (L1c; user, 2026-10-15; STABLE from
# v0.1.0-pre.1, 2026-10-20: signature, return shape, `PrologException`) — answers copied out as a vector, the foreign frame DISCARDED, so a host running many
# queries leaves the engine's stacks as it found them (no collector until G1); upstream has no
# counterpart (embedding code discards its frames itself).
# test/foreign/test_query_answers.jl — on every term type:
#   * the answers, each the goal with its bindings resolved, and the order and determinism swipl's
#     (`_rswipl`); `limit` (`nothing`, `n`, `0` running nothing, negative refused); an unbound variable
#     comes back fresh; a goal that is not an atom or an atom-headed compound refused; the exports;
#   * an uncaught exception is thrown as a `PrologException` carrying its ball, resolved — and the
#     stacks are back at their baseline after it (the frame discarded on that path too);
#   * the engine carries its database from birth (`GD`), which the helper reads;
#   * 10^4 repeated queries whose argument is a compound (copied onto the global stack by its put)
#     leave `gTop`, the trail and `lTop` at their baseline after EACH — the check that fails if the
#     helper closed its frame instead of discarding it (mutation-proved 2026-10-15).
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "..", "core_lang", "rules_common.jl"))

_qa_clauses() = Tuple{_R, Union{Nothing, _R}}[
    (_rf("qa_p", _rs("a")), nothing), (_rf("qa_p", _rs("b")), nothing),
    (_rf("qa_q", _rf("f", _rv(1)), _rf("g", _rv(1), _rv(1))), nothing),
    (_rf("qa_free", _rv(1), _rs("x")), nothing)
]

@testset "query_answers: the answers, copied out, as swipl's" begin
    db = _rdb(_qa_clauses())
    @test db.ld.GD === db.gd                    # an engine carries the database it is made for
    goals = _R[_rf("qa_p", _rv(9)), _rf("qa_q", _rf("f", _rg(Int64(1))), _rv(9)),
        _rf("qa_q", _rf("h", _rv(8)), _rv(9))]
    ours = String[]
    for g in goals
        ans = LK.query_answers(db.ld, g)
        @test ans isa Vector{_R}
        append!(ours, _rcanonical.(ans))
        push!(ours, "end")
    end
    @test ours == ["qa_p(a)", "qa_p(b)", "end", "qa_q(f(1),g(1,1))", "end", "end"]
    if _R_SWIPL
        @test [
            replace(l, r" (det|nondet)$" => "") for l in _rswipl(_qa_clauses(), goals)
        ] == ours
    end
    @test _rcanonical.(LK.query_answers(db.ld, _rf("qa_p", _rv(9)); limit=1)) == ["qa_p(a)"]
    @test _rcanonical.(LK.query_answers(db.ld, _rf("qa_p", _rv(9)); limit=nothing)) ==
        ["qa_p(a)", "qa_p(b)"]
    @test isempty(LK.query_answers(db.ld, _rf("qa_p", _rv(9)); limit=0))
    # `limit=0` runs NOTHING: an unknown procedure, which raises when run, is not reached
    @test isempty(LK.query_answers(db.ld, _rf("qa_undefined", _rv(9)); limit=0))
    @test_throws ArgumentError LK.query_answers(db.ld, _rf("qa_p", _rv(9)); limit=-1)
    @test_throws ArgumentError LK.query_answers(db.ld, _rg(Int64(1)))
    @test_throws ArgumentError LK.query_answers(db.ld, _rv(9))                  # a variable goal
    @test_throws ArgumentError LK.query_answers(db.ld, mk_expr(_R, _R[_rv(9), _rs("a")]))  # its head a variable
    # a variable the solution leaves unbound comes back as a FRESH variable, not the caller's
    (a,) = LK.query_answers(db.ld, _rf("qa_free", _rv(9), _rv(8)))
    @test kind(child(a, 2)) === VAR &&
        var_key(child(a, 2)) ∉ (var_key(_rv(9)), var_key(_rv(8)))
    @test _rcanonical(child(a, 3)) == "x"
    # a MODULE-QUALIFIED goal is taken as SWI-Prolog's PL_call takes it (pl-pro.c callProlog:
    # PL_strip_module, then the functor): run in its module; each answer the qualified goal, solved
    qg = mk_expr(_R, _R[_rs(":"), _rs("user"), _rf("qa_p", _rv(9))])
    qa = LK.query_answers(db.ld, qg)
    @test length(qa) == 2 &&
        all(a -> sym_text(child(a, 1)) == ":" && sym_text(child(a, 2)) == "user", qa)
    @test _rcanonical.(child.(qa, 3)) == ["qa_p(a)", "qa_p(b)"]
    if _R_SWIPL                                     # swipl: `user:qa_p(X)` answers user:qa_p(a), user:qa_p(b)
        @test [replace(l, r" (det|nondet)$" => "") for l in _rswipl(_qa_clauses(), [qg])] ==
            [_rcanonical.(qa); "end"]                     # the driver's per-goal end marker
    end
    # …nested qualifiers stripped too (the innermost names the module), and a system predicate
    # reached from `user` as call/1 reaches it
    nested = mk_expr(_R, _R[_rs(":"), _rs("system"), qg])
    @test length(LK.query_answers(db.ld, nested)) == 2
    @test length(
        LK.query_answers(
            db.ld, mk_expr(_R, _R[_rs(":"), _rs("user"), _rf("atom", _rs("a"))])
        )
    ) == 1
    # the stable surface is exported (README "Using it from Julia")
    @test all(n -> n in names(LogicKernel), (:query_answers, :PrologException, :load_file!))
end

@testset "query_answers: an uncaught exception is thrown with its ball" begin
    db = _rdb(_qa_clauses())
    ld = db.ld
    base = (ld.gTop, length(ld.trail), ld.lTop)
    ex = try
        LK.query_answers(ld, _rf("qa_undefined", _rv(1)))
        nothing
    catch e
        e
    end
    @test ex isa LK.PrologException{_R}
    # the formal part — the context term is the caller's frame, as before L1c (not this helper's)
    @test _rcanonical(ex.ball) |>
        startswith("error(existence_error(procedure,/(qa_undefined,1)),")
    @test (ld.gTop, length(ld.trail), ld.lTop) == base    # the frame discarded on this path too
end

@testset "query_answers: 10^4 queries leave the stacks at their baseline" begin
    db = _rdb(_qa_clauses())
    ld = db.ld
    g = _rf("qa_q", _rf("f", _rf("k", _rg(Int64(7)), _rs("z"))), _rv(9))
    base = (ld.gTop, length(ld.trail), ld.lTop)
    ok = true
    for _ in 1:(10 ^ 4)
        ans = LK.query_answers(ld, g)
        ok &= length(ans) == 1
        ok &= (ld.gTop, length(ld.trail), ld.lTop) == base
        ok || break
    end
    @test ok
    @test (ld.gTop, length(ld.trail), ld.lTop) == base
    # the leak path ran: a put copies its value onto the stack — f(k(7, z)) is five cells (f/1 two, k/2
    # three; 7 a tagged word, z an atom). Since f3b-1 the put lays it on the cells itself, no import counted
    # (until then `cold_imports - imports0 >= 10^4` was this guard: each put went through the cold import)
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 1)
    g1 = ld.gTop
    LK.putSlotValue!(ld, a + 1, child(g, 2))
    @test ld.gTop - g1 == 5 && LK._is_gcompound(ld.slots[a + 1])
    LK.PL_discard_foreign_frame(ld, fid)
    @test (ld.gTop, length(ld.trail), ld.lTop) == base
end
