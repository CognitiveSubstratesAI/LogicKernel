# tools/lib_evidence.sh — shared by tools/run_tests.sh (the sharded evidence run) and tools/warm.sh
# (`pool`, the pre-warmed workers). Sourced, not run.

# _tree_fp ROOT — a hash of every tracked or untracked (not ignored) file's CONTENT: what a worker
# was started with, compared with what the run is about to certify.
_tree_fp() {
    git -C "$1" ls-files -co --exclude-standard -z |
        (cd "$1" && xargs -0 -r sha1sum 2>/dev/null) | sha1sum | cut -c1-40
}

# _evidence_depot ROOT — where EVIDENCE processes keep their compiled caches: the coordinator's
# precompile, the workers, `pool`, every tools/run_tests.sh process. It sits ahead of the default
# depot (JULIA_DEPOT_PATH="<it>:"), so their precompiles never rewrite the cache the warm daemon
# loaded — which the daemon would rightly refuse to revise past (tools/warm_session.jl) — and the
# pool can warm while the daemon works (user, 2026-10-04: no cold starts that a warm lane avoids).
_evidence_depot() { echo "$1/.warm/evidence-depot"; }

# _evidence_depot_path ROOT — the JULIA_DEPOT_PATH value for an evidence process: the evidence
# depot, then the depots it would have had. NAMED explicitly: a trailing ":" alone drops the user
# depot (~/.julia) — MEASURED 2026-10-04, DEPOT_PATH became [evidence, juliaup's two] and no
# installed package was found.
_evidence_depot_path() {
    local d
    d="$(_evidence_depot "$1")"
    if [ -n "${JULIA_DEPOT_PATH:-}" ]; then
        case ":$JULIA_DEPOT_PATH:" in
            *":$d:"*) echo "$JULIA_DEPOT_PATH" ;;
            *) echo "$d:$JULIA_DEPOT_PATH" ;;
        esac
    else
        echo "$d:$HOME/.julia:"
    fi
}

# _check_swipl_pin ROOT WHO — 0 when the `swipl` on THIS PATH is the pinned version
# (tools/SWIPL_VERSION); otherwise says which swipl it found, and where. Both sides non-empty.
_check_swipl_pin() {
    local pin have
    pin=$(grep -v '^#' "$1/tools/SWIPL_VERSION" 2>/dev/null | tr -d '[:space:]')
    have=$(swipl --version 2>/dev/null)
    if [ -z "$pin" ]; then
        echo "$2: tools/SWIPL_VERSION is missing or empty — no pinned swipl to judge against" >&2
        return 1
    fi
    case "$have" in
        *"version $pin "*) return 0 ;;
        *) echo "$2: swipl must be $pin (tools/SWIPL_VERSION); found: ${have:-no swipl} at $(command -v swipl || echo '(none on PATH)')" >&2
           return 1 ;;
    esac
}

# ── what the MACHINE did during a run (user, 2026-10-04: a slow run must say whether it was the
# host). A VM's host contention shows as STEAL time where the hypervisor reports it; this VM (VMware)
# reported 0 steal over 16 h of uptime and a fixed 2394.569 MHz on every core, so neither can show
# a slow host here. A fixed single-core probe is timed too, before the workers start and after they
# finish (measured 2.00-2.10 s on a quiet machine): the same work, slower, is the host.
# _cpu_sample — "total steal" CPU jiffies, from /proc/stat's aggregate line
_cpu_sample() {
    awk '/^cpu /{t = 0; for (i = 2; i <= 9; i++) t += $i; print t, $9; exit}' /proc/stat 2>/dev/null
}
# _steal_pct "T0 S0" "T1 S1" — the share of CPU time the host stole between two samples, in %
_steal_pct() {
    awk -v a="$1" -v b="$2" 'BEGIN { split(a, x, " "); split(b, y, " "); dt = y[1] - x[1]
        if (dt > 0) printf "%.1f", 100 * (y[2] - x[2]) / dt; else printf "n/a" }'
}
# _cpu_mhz — the mean clock over the CPUs, as /proc/cpuinfo reports it
_cpu_mhz() {
    awk -F: '/^cpu MHz/ {s += $2; n++} END { if (n) printf "%.0f", s / n; else printf "n/a" }' \
        /proc/cpuinfo 2>/dev/null
}
# _host_probe_s — seconds for a fixed single-core loop
_host_probe_s() {
    local t0 t1
    t0=$(date +%s.%N)
    awk 'BEGIN { for (i = 0; i < 2e7; i++) s += i }'
    t1=$(date +%s.%N)
    awk -v a="$t0" -v b="$t1" 'BEGIN { printf "%.2f", b - a }'
}

# _shard_count — from the machine: one core left free, and ~2.5 GB per worker (Julia with the
# analysis tools loaded, plus swipl children) with 3 GB kept back. LOGICKERNEL_SHARDS overrides.
_shard_count() {
    if [ -n "${LOGICKERNEL_SHARDS:-}" ]; then echo "$LOGICKERNEL_SHARDS"; return; fi
    local cores mem n m
    cores=$(nproc 2>/dev/null || echo 1)
    mem=$(awk '/MemAvailable/ {print int($2 / 1048576)}' /proc/meminfo 2>/dev/null || echo 4)
    n=$(( cores - 1 ))
    m=$(( (mem - 3) * 2 / 5 ))
    [ "$m" -lt "$n" ] && n=$m
    [ "$n" -lt 1 ] && n=1
    echo "$n"
}

# _spawn_worker ROOT DIR FP UNIT — one evidence worker, in its own memory-capped unit, with
# automatic precompilation OFF: a worker that meets a stale cache fails loudly instead of compiling
# alongside its siblings (the coordinator precompiles once, before any worker starts).
# 🔴 The unit gets the caller's PATH. A `systemd-run --user` SERVICE starts from the user manager's
# environment, not the caller's: MEASURED 2026-10-04, its PATH found /usr/local/bin/swipl 10.1.12
# while the caller's found the pinned 10.1.16 — the coordinator checked the pin in one environment
# and every differential ran in the other. The worker also checks the pin itself (tools/worker.jl).
_spawn_worker() {
    local root="$1" dir="$2" fp="$3" unit="$4" julia
    julia="$(command -v julia)" || return 1
    mkdir -p "$dir"
    rm -f "$dir/ready" "$dir/go" "$dir/rc"
    echo "$fp" > "$dir/fp"
    systemd-run --user --unit="$unit" --collect --quiet \
        -p MemoryMax="${LOGICKERNEL_WORKER_MEM_MAX:-5G}" -p MemorySwapMax=0 \
        --working-directory="$root" -E "PATH=$PATH" -E "JULIA_DEPOT_PATH=$(_evidence_depot_path "$root")" \
        -E JULIA_PKG_PRECOMPILE_AUTO=0 -E LOGICKERNEL_REQUIRE_TOOLS=1 -E LOGICKERNEL_REQUIRE_SWIPL=1 \
        ${LOGICKERNEL_WORKER_IDLE_S:+-E LOGICKERNEL_WORKER_IDLE_S=$LOGICKERNEL_WORKER_IDLE_S} \
        /bin/bash -c "exec '$julia' --project=. --threads=1 --heap-size-hint=${LOGICKERNEL_WORKER_HEAP_HINT:-2G} tools/worker.jl '$dir' '$fp' >> '$dir/log' 2>&1"
}

# _check_run RUN — the verdict only the coordinator gives, from what the shards wrote in their run
# directory: every unit of the run ran EXACTLY once (claimed = ran = the run's unit count, no unit
# twice, and that count is not zero), and the second implementation was exercised across all shards
# (each AltTerm count, summed, non-zero). Prints what it found; exit 0 only if all of it holds.
_check_run() {
    local run="$1" units claimed ran dup plain interned shared ok=0
    units=$(cat "$run/units_total" 2>/dev/null || echo 0)
    claimed=$(find "$run/claims" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
    ran=$(cat "$run"/seq_*.tsv 2>/dev/null | wc -l)
    dup=$(cat "$run"/seq_*.tsv 2>/dev/null | cut -f1 | sort | uniq -d | wc -l)
    if [ "$units" -le 0 ] || [ "$claimed" -ne "$units" ] || [ "$ran" -ne "$units" ] || [ "$dup" -ne 0 ]; then
        echo "  units: $units in the run, $claimed claimed, $ran ran, $dup more than once — each must run EXACTLY once" >&2
        ok=1
    else
        echo "  units: $units, each run exactly once"
    fi
    # the gate split: every shard ran the term types the coordinator decided (tools/worker.jl reads
    # them from its `go` file; a worker that dropped them would run every unit and pass, slower)
    local want="${LOGICKERNEL_TERM_TYPES:-all}" got
    got=$(cat "$run"/types_* 2>/dev/null | sort -u | tr '\n' ' ')
    if [ "$got" != "$want " ]; then
        echo "  term types: the shards ran '${got% }', the run decided '$want'" >&2
        ok=1
    else
        echo "  term types: $want, in every shard"
    fi
    read -r plain interned shared < <(cat "$run"/stats_* 2>/dev/null |
        awk '{p += $1; i += $2; s += $3} END {print p + 0, i + 0, s + 0}')
    echo "  AltTerm over all shards: $plain plain compounds, $interned interned, $shared shared"
    if [ "$plain" -le 0 ] || [ "$interned" -le 0 ] || [ "$shared" -le 0 ]; then
        echo "  the second implementation was not exercised, plain AND sharing" >&2
        ok=1
    fi
    return "$ok"
}

# _ci_gate ROOT WAIT_S [SHA] — the gate split's condition (user, 2026-10-06): no gate cycle passes
# while the previous push is red. tools/ci_status.sh on SHA (default origin/main): 0 passes;
# 1 (red) fails; 2 (unreadable) fails CLOSED; 3 (no verdict yet) passes when WAIT_S is 0 — a cycle's
# start, where the evidence run's end checks again — and otherwise polls every
# LOGICKERNEL_CI_POLL_S (150) seconds for up to WAIT_S, failing if there is still no verdict.
# LOGICKERNEL_CI_CHECK=off skips it LOUDLY: for a machine without network, never by default.
_ci_gate() {
    local root="$1" wait_s="$2" sha="${3:-}" t0 rc
    if [ "${LOGICKERNEL_CI_CHECK:-on}" = "off" ]; then
        echo "  CI check: OFF (LOGICKERNEL_CI_CHECK=off) — the previous push's CI was NOT checked" >&2
        return 0
    fi
    t0=$(date +%s)
    while :; do
        "$root/tools/ci_status.sh" $sha
        rc=$?
        case "$rc" in
            0) echo "  CI check: the previous push is green"; return 0 ;;
            1) echo "  CI check: the previous push is RED — fix it before the next commit" >&2; return 1 ;;
            3) ;;
            *) echo "  CI check: unreadable — fails closed (LOGICKERNEL_CI_CHECK=off skips it)" >&2; return 1 ;;
        esac
        if [ "$wait_s" -le 0 ]; then
            echo "  CI check: no verdict yet on the previous push — the evidence run's end checks again"
            return 0
        fi
        if [ $(( $(date +%s) - t0 )) -ge "$wait_s" ]; then
            echo "  CI check: still no verdict after ${wait_s} s — no evidence until there is one" >&2
            return 1
        fi
        sleep "${LOGICKERNEL_CI_POLL_S:-150}"           # GitHub allows 60 anonymous calls an hour
    done
}

# _wait_ready DIR UNIT TIMEOUT_S — 0 when the worker is ready; 1 when its unit died or timed out.
_wait_ready() {
    local dir="$1" unit="$2" deadline=$(( $(date +%s) + $3 ))
    until [ -f "$dir/ready" ]; do
        systemctl --user is-active --quiet "$unit" || return 1
        [ "$(date +%s)" -ge "$deadline" ] && return 1
        sleep 0.5
    done
}
