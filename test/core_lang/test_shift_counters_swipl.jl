# ORIGINAL: G1 (audit D-0966 (2), option (b)) — the stack shifter's counters tick where the stacks grow: test/core_lang/test_shift_counters_swipl.jl
# allow-new-artifact: G1 kill rows of the shift counters (src/pl-gc.jl growStacks!/growStacks_trim!, src/pl-alloc.jl _growGlobalStack!, src/pl-inline.jl
# _trail_push!/_growTrail!), after test/core_lang/test_gc_stats_swipl.jl; upstream pl-gc.c grow_stacks :5419-5421, :5472, :5496-5499 at 18168e62.
#   * DIFFERENTIAL against swipl at the pin: sc1 reads the three counters on a FRESH engine ([0,0,0], the FIRST row); sc2 a deep recursion
#     (local_shifts), sc3 a long list (global_shifts), sc4 20000 trailed bindings under a choice point (trail_shifts), sc5 trim_stacks after a deep
#     recursion (the local stack shrinks: local_shifts). sc2..sc5 compare only whether the counter grew (`grew` / `same`): the counts follow each
#     system's own sizes. The pinned table is swipl's (scratch probe p2.pl, run twice, identical; evidence/R2/g1_engine_fix_handoff.md E2).
#   * MUST-FAIL ARM: the kernel's lines differ from the table of frozen counters (every row `same`), so the comparison can fail.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "..", "core_lang", "rules_common.jl"))

_sc_stat(key::String, r::_R) = _rf("statistics", _rs(key), r)
"`( B > A -> R = Yes ; R = No )`"
_sc_cmp(b::_R, a::_R, r::_R, yes::_R, no::_R) =
    _rf(";", _rf("->", _rf(">", b, a), _rf("=", r, yes)), _rf("=", r, no))

# d(0) :- !.   d(N) :- N1 is N-1, d(N1), true.
# mk(0, []) :- !.   mk(N, [N|T]) :- N1 is N-1, mk(N1, T).
# bv([]).   bv([a|T]) :- bv(T).
# sc1(R) :- statistics(global_shifts,G), statistics(local_shifts,L), statistics(trail_shifts,T), R = [G,L,T].
# sc2(R) :- statistics(local_shifts,A), d(5000), statistics(local_shifts,B), ( B > A -> R = grew ; R = same ).
# sc3(R) :- statistics(global_shifts,A), mk(20000,L), statistics(global_shifts,B), length(L,N), ( B > A -> R = grew(N) ; R = same(N) ).
# sc4(R) :- length(L,20000), statistics(trail_shifts,A), ( bv(L), statistics(trail_shifts,B) ; B = A ), !, ( B > A -> R = grew ; R = same ).
# sc5(R) :- d(5000), statistics(local_shifts,A), trim_stacks, statistics(local_shifts,B), ( B > A -> R = grew ; R = same ).
const _SC_CLAUSES = Tuple{_R, Union{Nothing, _R}}[
    (_rf("d", _rg(0)), _rs("!")),
    (
        _rf("d", _rv(1)),
        _rconj(_rf("is", _rv(2), _rf("-", _rv(1), _rg(1))), _rf("d", _rv(2)), _rs("true"))
    ),
    (_rf("mk", _rg(0), _rnil()), _rs("!")),
    (
        _rf("mk", _rv(1), _rcons(_rv(1), _rv(2))),
        _rconj(_rf("is", _rv(3), _rf("-", _rv(1), _rg(1))), _rf("mk", _rv(3), _rv(2)))
    ),
    (_rf("bv", _rnil()), nothing),
    (_rf("bv", _rcons(_rs("a"), _rv(1))), _rf("bv", _rv(1))),
    (
        _rf("sc1", _rv(1)),
        _rconj(_sc_stat("global_shifts", _rv(2)), _sc_stat("local_shifts", _rv(3)),
            _sc_stat("trail_shifts", _rv(4)), _rf("=", _rv(1), _rlist(_rv(2), _rv(3), _rv(4))))
    ),
    (
        _rf("sc2", _rv(1)),
        _rconj(_sc_stat("local_shifts", _rv(2)), _rf("d", _rg(5000)),
            _sc_stat("local_shifts", _rv(3)),
            _sc_cmp(_rv(3), _rv(2), _rv(1), _rs("grew"), _rs("same")))
    ),
    (
        _rf("sc3", _rv(1)),
        _rconj(_sc_stat("global_shifts", _rv(2)), _rf("mk", _rg(20000), _rv(3)),
            _sc_stat("global_shifts", _rv(4)), _rf("length", _rv(3), _rv(5)),
            _sc_cmp(_rv(4), _rv(2), _rv(1), _rf("grew", _rv(5)), _rf("same", _rv(5))))
    ),
    (
        _rf("sc4", _rv(1)),
        _rconj(_rf("length", _rv(2), _rg(20000)), _sc_stat("trail_shifts", _rv(3)),
            _rf(";", _rconj(_rf("bv", _rv(2)), _sc_stat("trail_shifts", _rv(4))),
                _rf("=", _rv(4), _rv(3))),
            _rs("!"),
            _sc_cmp(_rv(4), _rv(3), _rv(1), _rs("grew"), _rs("same")))
    ),
    (
        _rf("sc5", _rv(1)),
        _rconj(_rf("d", _rg(5000)), _sc_stat("local_shifts", _rv(2)), _rs("trim_stacks"),
            _sc_stat("local_shifts", _rv(3)),
            _sc_cmp(_rv(3), _rv(2), _rv(1), _rs("grew"), _rs("same")))
    )
]
const _SC_GOALS = _R[_rf("sc$n", _rv(1)) for n in 1:5]
# swipl at the pin (18168e62, 10.1.20; scratch p2.pl run twice, identical): evidence/R2/g1_engine_fix_handoff.md E2
const _SC_SWIPL = String["sc1([0,0,0]) det", "end", "sc2(grew) det", "end",
    "sc3(grew(20000)) det", "end", "sc4(grew) det", "end", "sc5(grew) det", "end"]
# the must-fail arm: what the kernel answered before G1 ticked the counters (nothing grows)
const _SC_FROZEN = String["sc1([0,0,0]) det", "end", "sc2(same) det", "end",
    "sc3(same(20000)) det", "end", "sc4(same) det", "end", "sc5(same) det", "end"]

@testset "G1: the shift counters tick where the stacks grow, as swipl's" begin
    kl = _rlines(_rdb(_SC_CLAUSES), _SC_GOALS)
    @test length(kl) == length(_SC_SWIPL) == 10
    @test kl == _SC_SWIPL
    @test kl != _SC_FROZEN                         # must-fail: the comparison tells a ticking counter from a frozen one
    if !_R_SWIPL
        @info "SHIFT-COUNTER DIFFERENTIAL NOT RUN LIVE: `swipl` is not on PATH here (the pinned table was checked). It runs in tools/run_tests.sh and CI."
    else
        sl = _rswipl(_SC_CLAUSES, _SC_GOALS)
        @test !isempty(sl)
        @test sl == _SC_SWIPL
        @test sl == kl
    end
end
