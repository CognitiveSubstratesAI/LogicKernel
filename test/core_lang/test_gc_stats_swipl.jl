# ORIGINAL: G1-GC piece G1-1 — the stack collector's statistics and scheduler (src/pl-gc.jl; pl-gc.c:524-703, :3834-3909, :4592; pl-prims.c
# qp_statistics / swi_statistics): test/core_lang/test_gc_stats_swipl.jl
#   * DIFFERENTIAL against swipl at the pin, by SHAPE: every number normalised to `I` / `F` on both sides through ONE normaliser, both sides non-empty
#   * WHITE-BOX, no swipl: ring of three, aggregate, gc_percentage, totals, SIG_TUNE_GC, $gc_statistics/5, considerGarbageCollect, blockGC, statistics keys, call_tune_gc_hook.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "..", "core_lang", "rules_common.jl"))

_gs_db() = _rdb(Tuple{_R, Union{Nothing, _R}}[])
"The one normaliser: every float to `F`, then every integer to `I` (a name with digits in it, `gs12`, is no number)."
_gs_norm(l::AbstractString)::String =
    replace(replace(l, r"-?\b\d+\.\d+(?:e[-+]?\d+)?\b" => "F"), r"\b\d+\b" => "I")
_gs_row(n::Int, body::_R) = (_rf("gs$n", _rv(1)), body)
_gs_stat(key::String, r::_R=_rv(1)) = _rf("statistics", _rs(key), r)

const _GS_CLAUSES = Tuple{_R, Union{Nothing, _R}}[
    _gs_row(1, _gs_stat("garbage_collection")), _gs_row(2, _gs_stat("stack_shifts")),
    _gs_row(3, _gs_stat("collections")), _gs_row(4, _gs_stat("collected")),
    _gs_row(5, _gs_stat("global_shifts")), _gs_row(6, _gs_stat("local_shifts")),
    _gs_row(7, _gs_stat("trail_shifts")), _gs_row(8, _gs_stat("gctime")), _gs_row(9, _gs_stat("shift_time")),
    _gs_row(10, _rf("current_prolog_flag", _rs("gc"), _rv(1))),
    _gs_row(11, _rf("current_prolog_flag", _rs("trace_gc"), _rv(1))),
    _gs_row(12, _rconj(_rf("current_prolog_flag", _rs("agc_margin"), _rv(2)),
        _rf(";", _rf("->", _rf("==", _rv(2), _rg(10000)), _rf("=", _rv(1), _rs("margin_ok"))), _rf("=", _rv(1), _rv(2))))),
    _gs_row(13, _rf(";", _rf("->", _rconj(_rf("\$gc_statistics", _rv(2), _rv(3), _rv(4), _rv(5), _rv(6)),
        _rf("is_list", _rv(2)), _rf("is_list", _rv(3)), _rf("float", _rv(4)), _rf("float", _rv(5)), _rf("float", _rv(6))),
        _rf("=", _rv(1), _rs("ok"))), _rf("=", _rv(1), _rs("no")))),
]
const _GS_GOALS = _R[_rf("gs$n", _rv(1)) for n in 1:13]
# swipl at the pin, normalised (probed twice, identical: md5 8831c207...)
const _GS_SHAPE = String["gs1([I,I,I,I]) det", "end", "gs2([I,I,I]) det", "end", "gs3(I) det", "end", "gs4(I) det", "end",
    "gs5(I) det", "end", "gs6(I) det", "end", "gs7(I) det", "end", "gs8(F) det", "end", "gs9(F) det", "end",
    "gs10(true) det", "end", "gs11(false) det", "end", "gs12(margin_ok) det", "end", "gs13(ok) det", "end"]
const _GS_KERNEL_ZERO = String["gs1([0,0,0,0]) det", "end", "gs2([0,0,0]) det", "end", "gs3(0) det", "end", "gs4(0) det", "end",
    "gs5(0) det", "end", "gs6(0) det", "end", "gs7(0) det", "end", "gs8(0.0) det", "end", "gs9(0.0) det", "end"]

@testset "G1-1: statistics, flags and \$gc_statistics/5 have swipl's shape" begin
    kl = _rlines(_rdb(_GS_CLAUSES), _GS_GOALS)
    @test length(kl) == length(_GS_SHAPE) == 26
    @test _gs_norm.(kl) == _GS_SHAPE
    @test kl[1:18] == _GS_KERNEL_ZERO
    if !_R_SWIPL
        @info "GC-STATISTICS SHAPE DIFFERENTIAL NOT RUN LIVE: `swipl` is not on PATH here (the pinned table was checked). It runs in tools/run_tests.sh and CI."
    else
        sl = _rswipl(_GS_CLAUSES, _GS_GOALS)
        @test !isempty(sl)
        @test _gs_norm.(sl) == _gs_norm.(kl)
    end
end

"One collection on `ld`: the global stack is `g0` words and the trail `t0` entries at the start, `g1` and `t1` at the end (the trail is left as it was)."
function _gs_cycle!(ld, st, g0::Int, g1::Int, reason; t0::Int=0, t1::Int=0)
    n = length(ld.trail)
    ld.gTop = g0
    append!(ld.trail, zeros(UInt64, t0))
    LK.gc_stat_start!(ld, st, UInt64(reason))
    resize!(ld.trail, n)
    append!(ld.trail, zeros(UInt64, t1))
    ld.gTop = g1
    r = LK.gc_stat_end!(ld, st)
    resize!(ld.trail, n)
    return r
end

@testset "G1-1: gc_percentage is a fraction" begin
    s = LK.gc_stat()
    s.gc_time = 1.0; s.prolog_time = 3.0
    @test LK.gc_percentage(s) == 0.25
    s.prolog_time = 0.0
    @test LK.gc_percentage(s) == 1.0
    s.gc_time = 0.0; s.prolog_time = 7.0
    @test LK.gc_percentage(s) == 0.0
    s3 = LK.gc_stats()
    for (i, (g, p)) in enumerate(((1.0, 3.0), (1.0, 3.0), (1.0, 1.0)))
        s3.aggr[i].gc_time = g; s3.aggr[i].prolog_time = p
    end
    @test LK.gc_avg(s3) == 1.0 / 3                               # (0.25 + 0.25 + 0.5) / 3
    @test LK.STAT_NEXT_INDEX(2) == 0 && LK.STAT_NEXT_INDEX(0) == 1
    @test LK.STAT_PREV_INDEX(0) == 2 && LK.STAT_PREV_INDEX(2) == 1
end

@testset "G1-1: the ring of three, the aggregate, the totals, \$gc_statistics/5" begin
    db = _gs_db(); ld = db.ld; st = ld.gc.stats
    g0 = ld.gTop; n0 = length(ld.trail)
    try
        @test st.last_index == 0 && st.totals.collections == 0
        idx = Int[]
        cycles = [(100, 40, LK.GC_GLOBAL_OVERFLOW), (200, 50, LK.GC_GLOBAL_REQUEST), (300, 60, LK.GC_TRAIL_REQUEST), (400, 70, LK.GC_USER)]
        for (i, (a, b, r)) in enumerate(cycles)
            i == 4 && @test st.aggr_index == 0
            _gs_cycle!(ld, st, a, b, r; t0=10, t1=4)
            push!(idx, st.last_index)
        end
        @test idx == [1, 2, 0, 1]
        @test st.aggr_index == 1
        @test st.totals.collections == 4
        @test st.totals.global_gained == 8 * (60 + 150 + 240 + 330)
        @test st.totals.trail_gained == 8 * 6 * 4
        last = LK.last_gc_stats(st)
        @test last.global_before == 8 * 400 && last.global_after == 8 * 70
        @test last.reason == UInt64(LK.GC_USER)
        @test last.trail_before == 8 * 10 && last.trail_after == 8 * 4
        @test ld.gc.global_policy.gced_size == 8 * 70
        ag = st.aggr[1]
        @test ag.global_before == 8 * (100 + 200 + 300) ÷ 3
        @test ag.global_after == 8 * (40 + 50 + 60) ÷ 3
        @test ag.trail_before == 8 * 10 && ag.trail_after == 8 * 4
        @test ag.reason == UInt64(LK.GC_GLOBAL_OVERFLOW) + UInt64(LK.GC_GLOBAL_REQUEST) + UInt64(LK.GC_TRAIL_REQUEST)
        ld.gTop = g0                                    # the query below runs on the real stack, not the cycles' sizes
        last.gc_time = 1.0; last.prolog_time = 3.0               # the times the fractions below are read from
        ag.gc_time = 1.0; ag.prolog_time = 1.0
        ans = _rcall(db, _rf("\$gc_statistics", _rv(1), _rv(2), _rv(3), _rv(4), _rv(5)))
        @test length(ans) == 1
        txt = ans[1][1]
        found = [(m[1], parse(Int, m[2])) for m in eachmatch(r"gc_stats\((gc\([0-9,]*\)),(\d+),", txt)]
        @test length(found) == 4
        @test [f[1] for f in found] == ["gc(0,0,0,0,0,16)", "gc(0,0,0,1,0,0)", "gc(0,1,0,0,0,0)", "gc(1,1,0,1,0,0)"]
        @test [f[2] for f in found] == [3200, 2400, 1600, 1600]
        tail = split(chop(txt), ","; keepempty=false)[(end - 2):end]
        @test length(tail) == 3
        @test parse(Float64, tail[1]) == 0.25                    # the newest collection: 1.0 / (1.0 + 3.0)
        @test parse(Float64, tail[2]) == 0.5                     # the newest aggregate: 1.0 / (1.0 + 1.0)
        @test parse(Float64, tail[3]) == 0.5 / 3                 # the mean over the three aggregates (two empty)

        s2 = LK.gc_stats()
        for (i, v) in enumerate((10, 20, 31))
            s2.last[i].global_before = v; s2.last[i].gc_time = 0.5 * i; s2.last[i].reason = UInt64(v)
        end
        LK.gc_stat_aggregate!(s2)
        @test s2.aggr[1].global_before == (10 + 20 + 31) ÷ 3 == 20
        @test s2.aggr[1].gc_time == (0.5 + 1.0 + 1.5) / 3
        @test s2.aggr[1].reason == 61
        @test s2.aggr_index == 1
        LK.gc_stat_aggregate!(s2); LK.gc_stat_aggregate!(s2)
        @test s2.aggr_index == 0

        LK.clearGcSignal!(ld, LK.SIG_TUNE_GC)
        st.last[st.last_index + 1].prolog_time = 12.0
        st.thread_cpu = LK.ThreadCPUTime(LK.CPU_USER) - 5.0
        this = LK.gc_stat_end!(ld, st)
        @test LK.gc_percentage(this) > 0.2
        @test LK.pendingGcSignal(ld, LK.SIG_TUNE_GC)
        LK.clearGcSignal!(ld, LK.SIG_TUNE_GC)
        st.last[st.last_index + 1].prolog_time = 100.0
        st.thread_cpu = LK.ThreadCPUTime(LK.CPU_USER) - 5.0
        this = LK.gc_stat_end!(ld, st)
        @test 0.0 < LK.gc_percentage(this) < 0.2
        @test !LK.pendingGcSignal(ld, LK.SIG_TUNE_GC)
        st.request = UInt64(LK.GC_TRAIL_REQUEST)
        LK.gc_stat_start!(ld, st, UInt64(0))
        @test st.last[st.last_index + 1].reason == UInt64(LK.GC_TRAIL_REQUEST) && st.request == 0
        @test st.totals.time >= 10.0                              # two collections of >= 5.0 s each were added to the total
    finally
        ld.gTop = g0
        resize!(ld.trail, n0)
    end
end

function _gs_reset!(ld)
    LK.clearGcSignal!(ld, LK.SIG_GC); LK.clearGcSignal!(ld, LK.SIG_TUNE_GC)
    ld.gc.stats.request = UInt64(0)
    ld.gc.global_policy = LK.gc_stack_policy(true)
    ld.gc.trail_policy = LK.gc_stack_policy(true)
    ld.gc.inferences = ld.statistics.inferences - 1
    ld.exception_processing = false
    return nothing
end

@testset "G1-1: considerGarbageCollect" begin
    db = _gs_db(); ld = db.ld
    g0, n0, lim0, lt0 = ld.gTop, length(ld.trail), ld.stacks_limit, ld.lTop
    flags0 = ld.prolog_flag_mask
    try
        _gs_reset!(ld)
        @test LK.truePrologFlag(ld, LK.PLFLAG_GC)
        @test ld.gc.global_policy.small == LK.SMALLSTACK == 32 * 1024 && ld.gc.global_policy.factor == 3
        @test ld.gc.trail_policy.gc && !ld.gc.local_policy.gc && ld.gc.local_policy.factor == 0
        ld.gTop = 4096
        @test !LK.considerGarbageCollect(ld)
        @test !LK.pendingGcSignal(ld, LK.SIG_GC)
        ld.gTop = 200_000
        _gs_reset!(ld)
        ld.prolog_flag_mask &= ~LK.prologFlagMask(LK.PLFLAG_GC)     # flag `gc` off: never
        @test !LK.considerGarbageCollect(ld, :global)
        ld.prolog_flag_mask = flags0
        _gs_reset!(ld)
        ld.gc.inferences = ld.statistics.inferences                 # no inference since the last collection
        @test !LK.considerGarbageCollect(ld, :global)
        @test ld.gc.global_policy.gced_size == 8 * 200_000
        @test !LK.pendingGcSignal(ld, LK.SIG_GC)
        ld.exception_processing = true
        ld.gc.global_policy.gced_size = 0
        @test LK.considerGarbageCollect(ld, :global)
        ld.exception_processing = false
        _gs_reset!(ld)
        @test LK.considerGarbageCollect(ld, nothing)
        @test ld.gc.stats.request == LK.GC_GLOBAL_REQUEST
        @test LK.pendingGcSignal(ld, LK.SIG_GC)
        ld.gc.stats.request = UInt64(0)
        @test LK.considerGarbageCollect(ld)                         # SIG_GC pending: true, no new request
        @test ld.gc.stats.request == 0
        _gs_reset!(ld)
        ld.gc.global_policy.gced_size = 8 * 200_000
        @test !LK.considerGarbageCollect(ld, :global)
        @test !LK.considerGarbageCollect(ld, :local)
        ld.gTop = 4096
        for _ in 1:20_000
            push!(ld.trail, UInt64(0))
        end
        _gs_reset!(ld)
        @test !LK.considerGarbageCollect(ld, :global)
        @test LK.considerGarbageCollect(ld, :combined)
        @test ld.gc.stats.request == LK.GC_TRAIL_REQUEST
        resize!(ld.trail, n0)
        _gs_reset!(ld)
        low = 8 * ld.lTop + LK.SMALLSTACK + 8 * length(ld.trail)    # the global stack's `low`, in bytes
        ld.gc.global_policy.factor = 0                              # `used > low` alone decides: not at, above
        ld.gTop = low ÷ 8
        @test !LK.considerGarbageCollect(ld, :global)
        ld.gTop += 1
        @test LK.considerGarbageCollect(ld, :global)
        _gs_reset!(ld)
        ld.gc.global_policy.gced_size = 100_000                     # factor 3: `used > 3 * gced_size + low`
        ld.gTop = (2 * 100_000 + low) ÷ 8
        @test !LK.considerGarbageCollect(ld, :global)
        ld.gTop = (3 * 100_000 + low) ÷ 8
        @test !LK.considerGarbageCollect(ld, :global)
        ld.gTop += 1
        @test LK.considerGarbageCollect(ld, :global)
        ld.stacks_limit = 250_000                                   # the low-space branch alone
        ld.gTop = 230_000
        _gs_reset!(ld)
        ld.gc.global_policy.factor = 10^9
        ld.gc.global_policy.gced_size = 1
        @test LK.considerGarbageCollect(ld, :global)
        @test ld.gc.stats.request == LK.GC_GLOBAL_REQUEST
        _gs_reset!(ld)
        ld.gc.global_policy.factor = 10^9
        ld.gc.global_policy.gced_size = 8 * 230_000 - 1000          # only 1000 bytes above the last collection: below limit/32
        @test !LK.considerGarbageCollect(ld, :global)
        ld.lTop = 240_000                                           # the local stack nearly fills the limit: low space
        ld.gTop = 4096
        _gs_reset!(ld)
        @test !LK.considerGarbageCollect(ld, :local)                # its policy has gc off
        ld.gc.local_policy.gc = true
        @test LK.considerGarbageCollect(ld, :local)
        ld.gc.local_policy = LK.gc_stack_policy(false)
        ld.lTop = lt0
        ld.gTop = 230_000
        _gs_reset!(ld)
        ld.stacks_limit = lim0
        ld.gc.global_policy.factor = 10^9
        ld.gc.global_policy.gced_size = 1
        @test !LK.considerGarbageCollect(ld, :global)
    finally
        ld.gTop = g0; resize!(ld.trail, n0); ld.stacks_limit = lim0; ld.prolog_flag_mask = flags0; ld.lTop = lt0
        ld.gc.local_policy = LK.gc_stack_policy(false)
        _gs_reset!(ld)
    end
end

@testset "G1-1: blockGC and unblockGC count by flag" begin
    db = _gs_db(); ld = db.ld
    @test ld.gc.status.blocked == 0 && ld.shift_status.blocked == 0
    LK.blockGC(ld, 0);                 @test (ld.gc.status.blocked, ld.shift_status.blocked) == (1, 1)
    LK.blockGC(ld, LK.ALLOW_GC);       @test (ld.gc.status.blocked, ld.shift_status.blocked) == (1, 2)
    LK.blockGC(ld, LK.ALLOW_SHIFT);    @test (ld.gc.status.blocked, ld.shift_status.blocked) == (2, 2)
    LK.blockGC(ld, LK.ALLOW_GC | LK.ALLOW_SHIFT); @test (ld.gc.status.blocked, ld.shift_status.blocked) == (2, 2)
    LK.unblockGC(ld, LK.ALLOW_SHIFT); LK.unblockGC(ld, LK.ALLOW_GC); LK.unblockGC(ld, 0)
    @test (ld.gc.status.blocked, ld.shift_status.blocked) == (0, 0)
end

@testset "G1-1: statistics/2 reads the collector's and the shifter's counters" begin
    db = _gs_db(); ld = db.ld; st = ld.gc.stats
    g0 = ld.gTop
    try
        _gs_cycle!(ld, st, 5000, 1000, LK.GC_USER; t0=3, t1=2)
        _gs_cycle!(ld, st, 9000, 2000, LK.GC_USER; t0=3, t1=2)
        st.totals.time = 0.5
        st.totals.trail_gained = 24
        ld.shift_status.global_shifts = 2; ld.shift_status.local_shifts = 3; ld.shift_status.trail_shifts = 4
        ld.shift_status.time = 0.25
        last = LK.last_gc_stats(st)
        v = zeros(Int64, 4)
        @test LK.qp_statistics(ld, :garbage_collection, v) == 4
        @test v == [2, st.totals.trail_gained + st.totals.global_gained, 500, last.trail_after + last.global_after]
        @test last.trail_after == 8 * 2
        @test v[2] == 24 + 8 * (4000 + 7000) && v[4] == 8 * 2000 + 8 * 2
        @test LK.qp_statistics(ld, :stack_shifts, v) == 3 && v[1:3] == [2, 3, 250]
        ld.statistics.user_cputime = 3.0
        @test LK.qp_statistics(ld, :runtime, v) == 2 && v[1] == 2500   # 3.0 - 0.5 seconds
        ld.gTop = g0                                                   # the queries below run on the real stack
        for (key, want) in (("collections", "2"), ("collected", string(24 + 8 * 11000)), ("global_shifts", "2"),
                ("local_shifts", "3"), ("trail_shifts", "4"), ("gctime", "0.5"), ("shift_time", "0.25"))
            @test _rcall(db, _gs_stat(key)) == [("statistics($key,$want)", true)]
        end
    finally
        ld.gTop = g0
    end
end

@testset "G1-1: call_tune_gc_hook calls prolog:tune_gc/3 with the times and fractions" begin
    db = _gs_db(); ld = db.ld; gd = db.gd; st = ld.gc.stats
    LK.last_gc_stats(st).gc_time = 0.5          # 0.5 / (0.5 + 1.5) = 0.25
    LK.last_gc_stats(st).prolog_time = 1.5
    ag = st.aggr[LK.STAT_PREV_INDEX(st.aggr_index) + 1]
    ag.gc_time = 1.0; ag.prolog_time = 1.0      # 0.5
    @test _rcall(db, _rs("true"); at=(qid, k) -> LK.call_tune_gc_hook(ld)) == [("true", true)]   # no hook: nothing
    pm = LK.lookupModule(gd, _rs("prolog"))
    pr = LK.lookupProcedure(_rs("tune_gc"), 3, pm)
    head = _rf("tune_gc", _rv(1), _rv(2), _rv(3))
    body = _rf("nb_setval", _rs("gs_tuned"), _rf("tuned", _rv(1), _rv(2), _rv(3)))
    LK.assertDefinition!(gd, pr.definition, LK.compileClause(gd, ld, head, body, pr, pm), LK.CL_END)
    @test _rcall(db, _rs("true"); at=(qid, k) -> LK.call_tune_gc_hook(ld)) == [("true", true)]
    @test _rcall(db, _rf("nb_getval", _rs("gs_tuned"), _rv(1))) == [("nb_getval(gs_tuned,tuned(0.5,0.25,0.5))", true)]
end
