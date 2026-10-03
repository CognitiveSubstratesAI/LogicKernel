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
#   code loaded before an edit must not be certified after it.
# It never writes evidence: only the coordinator (tools/run_tests.sh) does, after every shard.
#
# The protocol: the worker writes `ready`; the coordinator writes `go` (three lines: the fingerprint,
# the run's shard directory, the shard id); the worker writes `rc` and exits with it.
const WDIR, FP = ARGS[1], ARGS[2]
const ROOT = abspath(joinpath(@__DIR__, ".."))
using Test, LogicKernel
# Pre-warm what the static-analysis gate loads (from the global environment); absent ones are the
# gate's to report — LOGICKERNEL_REQUIRE_TOOLS makes it fail, not skip.
for pkg in (:JET, :Aqua, :AllocCheck)
    try
        Core.eval(Main, :(import $pkg))
    catch
    end
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
fp, sdir, sid = split(read(GO, String), '\n')[1:3]
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
