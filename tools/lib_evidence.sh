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

# _swipl_pin ROOT KEY — the pin file's value for KEY: `version`, `commit` or `sync-from`
_swipl_pin() {
    sed -n "s/^$2:[[:space:]]*//p" "$1/tools/SWIPL_VERSION" 2>/dev/null | tr -d '[:space:]'
}

# _oracle_env ROOT STATS — export the oracle cache's environment (tools/oracle_cache/swipl) for this
# process and every worker it spawns (`_spawn_worker` passes it to the unit): the pinned commit, the
# shim first on PATH, and the file the shim counts hits, misses and bypasses in. ONE helper for both
# spawners — tools/run_tests.sh's fresh workers and tools/warm.sh's pre-warmed pool — because the pool
# was spawned without it, and the evidence run that used the pool then showed `0 hit, 0 miss, 0 bypass`
# (measured 2026-10-13: the real swipl answered every differential, the cache was never consulted).
# LOGICKERNEL_ORACLE_CACHE=0: nothing is exported, the real swipl runs.
_oracle_env() {
    [ "${LOGICKERNEL_ORACLE_CACHE:-1}" = 0 ] && return 0
    LOGICKERNEL_ORACLE_PIN="$(_swipl_pin "$1" commit)"
    export LOGICKERNEL_ORACLE_PIN
    case ":$PATH:" in
        *":$1/tools/oracle_cache:"*) ;;
        *) PATH="$1/tools/oracle_cache:$PATH"; export PATH ;;
    esac
    LOGICKERNEL_ORACLE_STATS="$2"
    export LOGICKERNEL_ORACLE_STATS
}

# _oracle_pool_stats ROOT — where the pre-warmed pool's workers count: they are spawned by a preflight,
# before the evidence run that claims them has made its own stats file, so they count here and that
# run folds this file into its own (tools/run_tests.sh `_finish`).
_oracle_pool_stats() { printf '%s/.warm/pool/oracle_stats' "$1"; }

# _check_swipl_pin ROOT WHO — 0 when the `swipl` on THIS PATH is THE ORACLE (tools/SWIPL_VERSION):
# its `--version` is the pinned version AND its `version_git` flag names the pinned commit — a
# build of exactly the commit the ports cite (tools/build_oracle.sh; user, 2026-10-11). A release
# binary has no such flag and is refused, and so is a build of another commit: the oracle and the
# ported source cannot drift. Otherwise says what it found, and where. Both sides non-empty.
_check_swipl_pin() {
    local ver commit have vg sfx
    ver="$(_swipl_pin "$1" version)"
    commit="$(_swipl_pin "$1" commit)"
    if [ -z "$ver" ] || ! printf '%s' "$commit" | grep -qE '^[0-9a-f]{40}$'; then
        echo "$2: tools/SWIPL_VERSION names no pinned version and commit — no oracle to judge against" >&2
        return 1
    fi
    have=$(swipl --version 2>/dev/null)
    case "$have" in
        *"version $ver "*) ;;
        *) echo "$2: swipl must be $ver (tools/SWIPL_VERSION); found: ${have:-no swipl} at $(command -v swipl || echo '(none on PATH)')" >&2
           return 1 ;;
    esac
    vg="$(swipl -g "current_prolog_flag(version_git, G), writeln(G)" -t halt 2>/dev/null)"
    sfx="${vg##*-g}"
    if [ "$sfx" = "$vg" ] || [ "${#sfx}" -lt 7 ] || [ "${commit#"$sfx"}" = "$commit" ]; then
        echo "$2: the oracle must be a BUILD OF THE PINNED COMMIT ${commit:0:12} (tools/SWIPL_VERSION); the swipl at $(command -v swipl) says version_git '${vg:-none}' — build it: tools/build_oracle.sh PREFIX" >&2
        return 1
    fi
    return 0
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
        ${LOGICKERNEL_ORACLE_PIN:+-E LOGICKERNEL_ORACLE_PIN=$LOGICKERNEL_ORACLE_PIN} \
        ${LOGICKERNEL_ORACLE_STATS:+-E LOGICKERNEL_ORACLE_STATS=$LOGICKERNEL_ORACLE_STATS} \
        ${LOGICKERNEL_ORACLE_CACHE_DIR:+-E LOGICKERNEL_ORACLE_CACHE_DIR=$LOGICKERNEL_ORACLE_CACHE_DIR} \
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

# _ci_full_sha ROOT NAME — the full SHA of the commit NAME (a SHA, short or full, or a ref); a full
# SHA git does not have is kept as it is (an unfetched commit, the tests' fixtures); else nothing.
_ci_full_sha() {
    git -C "$1" rev-parse --verify --quiet "$2^{commit}" 2>/dev/null && return 0
    printf '%s' "$2" | grep -qE '^[0-9a-f]{40}$' && printf '%s\n' "$2"
}

# _ci_fix_file ROOT — where a gate cycle that passed a RED push as its DECLARED FIX records the red
# commit, for the commit-msg hook (tools/githooks/commit-msg): the fixing commit must name it.
_ci_fix_file() { echo "${LOGICKERNEL_CI_FIX_FILE:-$1/.warm/CI_FIX}"; }

# _ci_fix_gate ROOT RC [SHA] — THE DECLARED FIX (user, 2026-10-11). The gate refuses every cycle
# while the previous push is red, the cycle of the commit that FIXES it included (`264a7f2` went in
# with the whole check switched off). LOGICKERNEL_CI_FIX=<sha> lets ONE thing through: a RED verdict
# (RC 1) on exactly that commit, which must be the push the gate is reading (SHA, default
# origin/main). Everything else FAILS while the variable is set — a green push, one with no verdict
# yet, an unreadable answer, another commit — so it cannot stay set past the fix: once the fix is
# pushed, origin/main is another commit and its CI is pending. The red commit is recorded
# (`_ci_fix_file`); the commit-msg hook then requires the trailer `CI-Fix: <sha>` and checks it.
_ci_fix_gate() {
    local root="$1" rc="$2" checked fix
    checked="$(_ci_full_sha "$root" "${3:-origin/main}")"
    fix="$(_ci_full_sha "$root" "$LOGICKERNEL_CI_FIX")"
    if [ -z "$checked" ] || [ -z "$fix" ]; then
        echo "  CI check: LOGICKERNEL_CI_FIX=$LOGICKERNEL_CI_FIX or the previous push names no commit — fails closed" >&2
        return 1
    fi
    if [ "$rc" != 1 ]; then
        echo "  CI check: LOGICKERNEL_CI_FIX is set, but the previous push ${checked:0:7} is not RED (exit $rc of tools/ci_status.sh: 0 green, 3 no verdict yet, 2 unreadable) — a declared fix is for a red push only; unset it" >&2
        return 1
    fi
    if [ "$fix" != "$checked" ]; then
        echo "  CI check: LOGICKERNEL_CI_FIX names ${fix:0:7}, but the red push is ${checked:0:7} — it must name the commit CI reports red" >&2
        return 1
    fi
    mkdir -p "$(dirname "$(_ci_fix_file "$root")")"
    printf '%s\n' "$checked" > "$(_ci_fix_file "$root")"
    echo "  CI check: the previous push ${checked:0:7} is RED — passed as the DECLARED FIX (LOGICKERNEL_CI_FIX); the commit must carry the trailer 'CI-Fix: $checked'"
    return 0
}

# _ci_gate ROOT WAIT_S [SHA] — the gate split's condition (user, 2026-10-06): no gate cycle passes
# while the previous push is red. tools/ci_status.sh on SHA (default origin/main): 0 passes;
# 1 (red) fails; 2 (unreadable) fails CLOSED; 3 (no verdict yet) passes when WAIT_S is 0 — a cycle's
# start, where the evidence run's end checks again — and otherwise polls every
# LOGICKERNEL_CI_POLL_S (150) seconds for up to WAIT_S, failing if there is still no verdict.
# LOGICKERNEL_CI_FIX=<sha> is the one way past a red push: `_ci_fix_gate`.
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
        if [ -n "${LOGICKERNEL_CI_FIX:-}" ]; then
            _ci_fix_gate "$root" "$rc" "$sha"
            return $?
        fi
        rm -f "$(_ci_fix_file "$root")"                 # no fix declared: an earlier cycle's record is stale
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

# ── the two lanes on one machine (Tooling 1, 2026-10-11): mutants run in a separate worktree with
# their own daemon (tools/mutate.sh), beside the main tree's preflight but never beside its EVIDENCE
# run, whose timings and worker count they would change.
# _mutants_dir — the mutant worktree
_mutants_dir() { echo "${LOGICKERNEL_MUTANTS_DIR:-$HOME/code/lk-mutants/worktree}"; }
# _lane_held TREE — 0 when a run (preflight, evidence, `locked CMD`) holds TREE's warm lane now
_lane_held() { [ -e "$1/.warm/run.lock" ] && ! flock -n -s "$1/.warm/run.lock" true 2>/dev/null; }
# _mutants_running ROOT — 0 when a mutation run holds the lane of ROOT's mutant worktree
_mutants_running() {
    local w
    w="$(_mutants_dir)"
    [ "$(cat "$w/.warm/MUTANT_WORKTREE" 2>/dev/null)" = "$1" ] && _lane_held "$w"
}
# _evidence_running ROOT — 0 when an evidence run holds ROOT's lane (tools/warm.sh writes run.kind)
_evidence_running() { _lane_held "$1" && [ "$(cat "$1/.warm/run.kind" 2>/dev/null)" = evidence ]; }

# _unit_active UNIT — 0 when the systemd user unit runs. A TEST SEAM: LOGICKERNEL_UNIT_ACTIVE names
# the command (default `systemctl --user is-active --quiet`), so test/test_gate_split.jl can decide
# alive and dead on a machine with no user systemd (CI).
_unit_active() {
    [ -n "$1" ] || return 1
    ${LOGICKERNEL_UNIT_ACTIVE:-systemctl --user is-active --quiet} "$1"
}

# _pool_usable W FP — 0 when the pool worker in W was started for the tree FP, is ready, and its
# unit still RUNS. MEASURED 2026-10-09: after a reboot the pool kept three DEAD workers whose `ready`
# files and fingerprints matched the tree (nothing had changed since they were started); the
# evidence run handed them its shards and got no verdict from any (fail closed, an hour lost).
_pool_usable() {
    local w="$1" fp="$2"
    [ -f "$w/ready" ] && [ "$(cat "$w/fp" 2>/dev/null)" = "$fp" ] &&
        _unit_active "$(cat "$w/unit" 2>/dev/null)"
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
