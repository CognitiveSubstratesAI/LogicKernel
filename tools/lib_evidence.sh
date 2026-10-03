# tools/lib_evidence.sh — shared by tools/run_tests.sh (the sharded evidence run) and tools/warm.sh
# (`pool`, the pre-warmed workers). Sourced, not run.

# _tree_fp ROOT — a hash of every tracked or untracked (not ignored) file's CONTENT: what a worker
# was started with, compared with what the run is about to certify.
_tree_fp() {
    git -C "$1" ls-files -co --exclude-standard -z |
        (cd "$1" && xargs -0 -r sha1sum 2>/dev/null) | sha1sum | cut -c1-40
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
_spawn_worker() {
    local root="$1" dir="$2" fp="$3" unit="$4" julia
    julia="$(command -v julia)" || return 1
    mkdir -p "$dir"
    rm -f "$dir/ready" "$dir/go" "$dir/rc"
    echo "$fp" > "$dir/fp"
    systemd-run --user --unit="$unit" --collect --quiet \
        -p MemoryMax="${LOGICKERNEL_WORKER_MEM_MAX:-5G}" -p MemorySwapMax=0 \
        --working-directory="$root" \
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
    read -r plain interned shared < <(cat "$run"/stats_* 2>/dev/null |
        awk '{p += $1; i += $2; s += $3} END {print p + 0, i + 0, s + 0}')
    echo "  AltTerm over all shards: $plain plain compounds, $interned interned, $shared shared"
    if [ "$plain" -le 0 ] || [ "$interned" -le 0 ] || [ "$shared" -le 0 ]; then
        echo "  the second implementation was not exercised, plain AND sharing" >&2
        ok=1
    fi
    return "$ok"
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
