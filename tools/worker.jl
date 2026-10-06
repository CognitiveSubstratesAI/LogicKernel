# tools/worker.jl — an EVIDENCE WORKER: a fresh process that loads LogicKernel and the analysis
# tools, waits, runs ONE shard of the suite, and exits (user, 2026-10-03). Started by
# tools/run_tests.sh — on demand, or ahead of time by `tools/warm.sh pool` (pre-warmed).
#
#   julia --project=. tools/worker.jl <worker dir> <tree fingerprint>
#
# WHY A FRESH PROCESS: evidence must come from a process that started clean — no values of an old
# type layout, no residue of earlier tests, no Revise update that failed partway. So a worker
# * never loads Revise: nothing in it may change while it waits;
# * runs exactly once and is discarded;
# * REFUSES its run (exit 3) when the tree's fingerprint differs from the one it started with —
#   code loaded before an edit must not be certified after it;
# * REFUSES to start (exit 4) when the swipl on ITS PATH is not the pinned one: the live
#   differentials' oracle is checked where they run (2026-10-04: a pin checked in the coordinator's
#   shell, a worker started by systemd from another PATH, every differential against 10.1.12).
# It never writes evidence: only the coordinator (tools/run_tests.sh) does, after every shard.
#
# The protocol: the worker writes `ready`; the coordinator writes `go` (three lines: the fingerprint,
# the run's shard directory, the shard id); the worker writes `rc` and exits with it.
const WDIR, FP = ARGS[1], ARGS[2]
const ROOT = abspath(joinpath(@__DIR__, ".."))
include(joinpath(@__DIR__, "swipl_pin.jl"))
if get(ENV, "LOGICKERNEL_REQUIRE_SWIPL", "") == "1"
    let why = swipl_pin_refusal(ROOT)
        if why !== nothing
            write(joinpath(WDIR, "rc"), "4")
            println(stderr, "worker: REFUSED — ", why)
            exit(4)
        end
    end
end
using Test, LogicKernel
println("worker: depot ", first(DEPOT_PATH))            # the evidence depot (tools/lib_evidence.sh)
# Pre-warm what the static-analysis gate loads (from the global environment); absent ones are the
# gate's to report — LOGICKERNEL_REQUIRE_TOOLS makes it fail, not skip.
for pkg in (:JET, :Aqua, :AllocCheck)
    try
        Core.eval(Main, :(import $pkg))
    catch
    end
end
# …and USE them once, on functions of no package, before `ready`: their own compilation is ~19 s in
# a fresh process (MEASURED 2026-10-04: load 2.3 s, first JET/AllocCheck use 18.7 s), paid here —
# off the critical path when the worker is pre-warmed — instead of inside the timed run. Nothing of
# LogicKernel is analysed, so no verdict is formed early.
try
    Base.invokelatest(Main.JET.report_opt, sum, (Vector{Int},))
    Base.invokelatest(Main.JET.report_opt, sum, (Vector{Float64},))
    Base.invokelatest(Main.AllocCheck.check_allocs, sum, (Vector{Int},))
catch e
    println("worker: tool warm-up skipped (", sprint(showerror, e), ")")
end
write(joinpath(WDIR, "ready"), string(getpid()))
flush(stdout)

const GO = joinpath(WDIR, "go")
const IDLE_S = parse(Float64, get(ENV, "LOGICKERNEL_WORKER_IDLE_S", "7200"))
let t0 = time()
    while !isfile(GO)
        time() - t0 > IDLE_S &&
            (println("worker: idle for $(IDLE_S) s — exiting unused"); exit(0))
        sleep(0.1)
    end
end
go = split(read(GO, String), '\n')
fp, sdir, sid = go[1:3]
# the gate split's term types (test/term_scope.jl), decided by the coordinator after this worker
# started: the 4th line, when present (`all` otherwise, as in CI)
length(go) >= 4 && !isempty(go[4]) && (ENV["LOGICKERNEL_TERM_TYPES"] = go[4])
if fp != FP
    write(joinpath(WDIR, "rc"), "3")
    println(
        stderr, "worker: REFUSED — the tree changed since this worker started ($FP ≠ $fp)"
    )
    exit(3)
end
ENV["LOGICKERNEL_SHARD_DIR"] = sdir
ENV["LOGICKERNEL_SHARD_ID"] = sid
ok = try
    include(joinpath(ROOT, "test", "runtests.jl"))
    true
catch e
    showerror(stderr, e)
    println(stderr)
    false
end
flush(stdout)                      # the summary reaches the log BEFORE the coordinator reads it
flush(stderr)
write(joinpath(WDIR, "rc"), ok ? "0" : "1")
exit(ok ? 0 : 1)
