#!/usr/bin/env bash
# ORIGINAL: no swipl-devel counterpart — the bench's START GATE, before julia starts (user, 2026-10-15).
# tools/bench.sh [bench.jl args…] — run tools/bench.jl's timed report on a machine MEASURED quiet.
#
# WHY A WRAPPER: the 1-minute load average lags, and julia's own start-up raises it, so a gate inside
# bench.jl refused its own run (MEASURED 2026-10-15: 0.42 in the waiter, 0.54 inside bench.jl). So
# quietness is measured HERE, before julia starts:
#   * no julia process runs (the VS Code language server, a warm daemon, a test run);
#   * the CPUs are ≥ 90 % idle over a 10 s sample of /proc/stat.
# The sample goes to bench.jl in BENCH_GATE_SAMPLE, which writes it into the raw file's header;
# bench.jl refuses a timed run without it (unless `--ungated`, which the header then says).
# The run itself is capped (MemoryMax, TasksMax), as every long job here.
#   BENCH_GATE_SECONDS (10), BENCH_GATE_MIN_IDLE (0.90) override the gate's window and threshold.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SECS="${BENCH_GATE_SECONDS:-10}"
MIN_IDLE="${BENCH_GATE_MIN_IDLE:-0.90}"

if pgrep -x julia > /dev/null; then
    echo "tools/bench.sh: REFUSED — julia processes are running:" >&2
    pgrep -a -x julia | cut -c1-120 >&2
    echo "Stop them (the VS Code Julia extension too, a warm daemon: tools/warm.sh stop), then rerun." >&2
    exit 3
fi

# /proc/stat's first line: cpu user nice system idle iowait irq softirq steal …; idle = idle + iowait
read -r _ u0 n0 s0 i0 w0 q0 sq0 st0 _ < /proc/stat
sleep "$SECS"
read -r _ u1 n1 s1 i1 w1 q1 sq1 st1 _ < /proc/stat
TOT=$(((u1 + n1 + s1 + i1 + w1 + q1 + sq1 + st1) - (u0 + n0 + s0 + i0 + w0 + q0 + sq0 + st0)))
IDLE=$(((i1 + w1) - (i0 + w0)))
[ "$TOT" -gt 0 ] || { echo "tools/bench.sh: /proc/stat did not advance" >&2; exit 2; }
SAMPLE=$(awk -v i="$IDLE" -v t="$TOT" 'BEGIN { printf "%.3f", i / t }')
if ! awk -v s="$SAMPLE" -v m="$MIN_IDLE" 'BEGIN { exit !(s >= m) }'; then
    echo "tools/bench.sh: REFUSED — the CPUs were $SAMPLE idle over ${SECS}s (< $MIN_IDLE)." >&2
    exit 3
fi
echo "tools/bench.sh: quiet — $SAMPLE idle over ${SECS}s, no julia process"
export BENCH_GATE_SAMPLE="cpu idle $SAMPLE over ${SECS}s (≥ $MIN_IDLE), no julia process, $(date -u +%FT%TZ)"
cd "$ROOT" || exit 2
exec systemd-run --user --scope -q -p MemoryMax=6G -p MemorySwapMax=0 -p TasksMax=512 \
    julia --project=. tools/bench.jl "$@"
