# ORIGINAL: the Julia-facing query helper `pl_query_answers` (L1c; user, 2026-10-15) — answers copied out, the foreign frame DISCARDED, so a host running many queries leaves the engine's stacks as it found them (no collector until G1); upstream has no counterpart (embedding code discards its frames itself).
# test/foreign/test_query_answers.jl — on every term type:
#   * the answers, each the goal with its bindings resolved, and the order and determinism swipl's
#     (`_rswipl`);
#   * an uncaught exception comes back as its ball, resolved;
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
    (_rf("qa_q", _rf("f", _rv(1)), _rf("g", _rv(1), _rv(1))), nothing)
]

@testset "pl_query_answers: the answers, copied out, as swipl's" begin
    db = _rdb(_qa_clauses())
    goals = _R[_rf("qa_p", _rv(9)), _rf("qa_q", _rf("f", _rg(Int64(1))), _rv(9)),
        _rf("qa_q", _rf("h", _rv(8)), _rv(9))]
    ours = String[]
    for g in goals
        ans, ex = LK.pl_query_answers(db.gd, db.ld, g)
        @test ex === nothing
        append!(ours, _rcanonical.(ans))
        push!(ours, "end")
    end
    @test ours == ["qa_p(a)", "qa_p(b)", "end", "qa_q(f(1),g(1,1))", "end", "end"]
    if _R_SWIPL
        @test [
            replace(l, r" (det|nondet)$" => "") for l in _rswipl(_qa_clauses(), goals)
        ] == ours
    end
    ans, _ = LK.pl_query_answers(db.gd, db.ld, _rf("qa_p", _rv(9)); limit=1)
    @test _rcanonical.(ans) == ["qa_p(a)"]
end

@testset "pl_query_answers: an uncaught exception comes back as its ball" begin
    db = _rdb(_qa_clauses())
    ans, ex = LK.pl_query_answers(db.gd, db.ld, _rf("qa_undefined", _rv(1)))
    @test isempty(ans) && ex !== nothing
    # the formal part — the context term is the caller's frame, as before L1c (not this helper's)
    @test _rcanonical(ex) |>
        startswith("error(existence_error(procedure,/(qa_undefined,1)),")
end

@testset "pl_query_answers: 10^4 queries leave the stacks at their baseline" begin
    db = _rdb(_qa_clauses())
    ld = db.ld
    g = _rf("qa_q", _rf("f", _rf("k", _rg(Int64(7)), _rs("z"))), _rv(9))
    base = (ld.gTop, length(ld.trail), ld.lTop)
    imports0 = ld.cold_imports
    ok = true
    for _ in 1:(10 ^ 4)
        ans, ex = LK.pl_query_answers(db.gd, ld, g)
        ok &= length(ans) == 1 && ex === nothing
        ok &= (ld.gTop, length(ld.trail), ld.lTop) == base
        ok || break
    end
    @test ok
    @test (ld.gTop, length(ld.trail), ld.lTop) == base
    @test ld.cold_imports - imports0 >= 10^4    # every put copied onto the stack: the leak path ran
end
