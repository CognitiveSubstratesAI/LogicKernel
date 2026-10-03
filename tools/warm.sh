#!/usr/bin/env bash
# tools/warm.sh — LogicKernel's WARM LANE: one daemon with LogicKernel loaded under Revise
# (tools/warm_session.jl), for ITERATION (user, 2026-10-03).
#
#   tools/warm.sh start | stop | restart | status
#   tools/warm.sh file test/core_lang/test_unify.jl [impl]   # one test file, REAL exit code: a term-
#                                                            # generic file on every implementation
#                                                            # (or just `impl`), swipl REQUIRED
#   tools/warm.sh send snippet.jl          # any snippet (or stdin); exit 0 ok · 1 threw · 2 timeout · 3 no daemon
#   tools/warm.sh bench [bench.jl args]    # tools/bench.jl in the daemon: no JIT in the timings
#   tools/warm.sh evidence                 # a FRESH tools/run_tests.sh — the commit gate's run
#   tools/warm.sh pool                     # pre-warm the evidence workers for THIS tree
#   tools/warm.sh workload on|off          # the precompile workload, for THIS checkout only
#
# 🔴 ITERATION ONLY, NEVER EVIDENCE (user, 2026-10-03): a long-lived daemon is where state leaks
# hide, so commit evidence is a process that started clean — `evidence` runs tools/run_tests.sh,
# which shares nothing with the daemon. A STRUCT edit needs no restart on Julia ≥ 1.12 (Revise
# redefines types); `restart` clears what a long-lived process accumulates — values of a type's old
# layout, test residue, an update that failed partway — and recovers from a refused revision.
#
# Exit codes are the snippet's own (Core's tools/warm_send.sh, whose two silent-success bugs this
# keeps fixed): a missing verdict is a FAILURE, and a timeout prints no output — it would be the
# previous run's — and exits 2, distinct from a failure.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIR="$ROOT/.warm"
UNIT="logickernel-warm-$(printf '%s' "$ROOT" | md5sum | cut -c1-8)"   # one daemon per checkout

_running() { systemctl --user is-active --quiet "$UNIT" && [ -f "$DIR/ready" ]; }

_start() {
    if _running; then echo "warm lane: running (unit $UNIT, pid $(cat "$DIR/ready"))"; return 0; fi
    mkdir -p "$DIR"
    rm -f "$DIR/ready" "$DIR/done" "$DIR/status" "$DIR/in.jl"
    local julia
    julia="$(command -v julia)" || { echo "warm lane: no julia on PATH" >&2; return 1; }
    # the same ceiling and flags as tools/run_tests.sh
    systemd-run --user --unit="$UNIT" --collect --quiet -p MemoryMax="${LOGICKERNEL_TEST_MEM_MAX:-8G}" \
        -p MemorySwapMax=0 --working-directory="$ROOT" \
        -E JULIA_REVISE=manual \
        /bin/bash -c "exec '$julia' --project=. --threads=\"\${JULIA_TEST_THREADS:-4}\" --heap-size-hint=6G tools/warm_session.jl >> '$DIR/session.log' 2>&1" ||
        { echo "warm lane: systemd-run failed" >&2; return 1; }
    local deadline=$(( $(date +%s) + ${WARM_START_TIMEOUT_S:-600} ))
    until [ -f "$DIR/ready" ]; do
        systemctl --user is-active --quiet "$UNIT" ||
            { echo "warm lane: the daemon died while starting — $DIR/session.log:" >&2; tail -20 "$DIR/session.log" >&2; return 1; }
        [ "$(date +%s)" -ge "$deadline" ] && { echo "warm lane: not ready after ${WARM_START_TIMEOUT_S:-600}s" >&2; return 1; }
        sleep 1
    done
    echo "warm lane: ready (unit $UNIT, pid $(cat "$DIR/ready"))"
}

_stop() {
    systemctl --user stop "$UNIT" 2>/dev/null
    rm -f "$DIR/ready"
    echo "warm lane: stopped"
}

# _send FILE — run the snippet in the daemon; print its output; exit with its verdict.
_send() {
    _running || { echo "warm lane: not running — tools/warm.sh start" >&2; return 3; }
    local seq=$(( $(cat "$DIR/seq" 2>/dev/null || echo 0) + 1 ))
    cat "${1:-/dev/stdin}" > "$DIR/in.jl"
    rm -f "$DIR/status"                       # never inherit the previous run's verdict
    echo "$seq" > "$DIR/seq"
    local deadline=$(( $(date +%s) + ${WARM_TIMEOUT_S:-1800} ))
    while [ "$(cat "$DIR/done" 2>/dev/null)" != "$seq" ]; do
        if ! systemctl --user is-active --quiet "$UNIT"; then
            echo "warm lane: the daemon DIED during seq=$seq — $DIR/session.log" >&2; return 2
        fi
        if [ "$(date +%s)" -ge "$deadline" ]; then
            echo "warm lane: TIMEOUT after ${WARM_TIMEOUT_S:-1800}s on seq=$seq — it may still be running;" >&2
            echo "           output NOT printed (it would be the previous run's)" >&2
            return 2
        fi
        sleep 0.2
    done
    cat "$DIR/out.txt"
    return "$(cat "$DIR/status" 2>/dev/null || echo 1)"     # a missing verdict is a FAILURE
}

# _file PATH [IMPL] — one test file in a fresh module, as test/runtests.jl runs it.
_file() {
    local f="$1" impl="${2:-}"
    case "$f" in /*) ;; *) f="$ROOT/$f" ;; esac
    [ -f "$f" ] || { echo "warm lane: no such file: $f" >&2; return 2; }
    local impls='("",)'
    if grep -qE '^include\(joinpath\(@__DIR__, "\.\.", "term_under_test\.jl"\)\)' "$f"; then
        impls='("reference", "alt", "alt_interned")'
        [ -n "$impl" ] && impls="(\"$impl\",)"
    fi
    local snippet="$DIR/file_snippet.jl"
    cat > "$snippet" <<JL
let f = raw"$f", ts = Test.DefaultTestSet("warm: " * basename(f); verbose=true)
    Test.@with_testset ts begin
        for impl in $impls
            label = isempty(impl) ? basename(f) : "\$(basename(f)) [\$impl]"
            @testset "\$label" begin
                m = Core.eval(Main, Expr(:module, true, gensym(:LKWarm), Expr(:block)))
                env = ["LOGICKERNEL_REQUIRE_SWIPL" => "1"]
                isempty(impl) || push!(env, "LOGICKERNEL_TERM" => impl)
                withenv(() -> Base.include(m, f), env...)
            end
        end
    end
    Test.finish(ts)                          # throws on any failure or error: the verdict
end
JL
    _send "$snippet"
}

_bench() {
    local snippet="$DIR/bench_snippet.jl" args=""
    for a in "$@"; do args+="\"$a\", "; done
    cat > "$snippet" <<JL
let m = Core.eval(Main, Expr(:module, true, gensym(:LKBench), Expr(:block)))
    empty!(ARGS); append!(ARGS, String[$args])
    Base.include(m, raw"$ROOT/tools/bench.jl")
end
JL
    _send "$snippet"
}

# _pool — pre-warm the evidence workers (tools/worker.jl) for the CURRENT tree: fresh processes that
# have loaded LogicKernel and the analysis tools and run nothing. tools/run_tests.sh uses them only
# if the tree is still the one they started with; workers for another tree are discarded here.
_pool() {
    # shellcheck source=/dev/null
    . "$ROOT/tools/lib_evidence.sh"
    local n fp k w u
    n=$(_shard_count)
    fp="$(_tree_fp "$ROOT")"
    mkdir -p "$DIR/pool"
    for w in "$DIR"/pool/w*; do
        [ -d "$w" ] || continue
        if [ "$(cat "$w/fp" 2>/dev/null)" != "$fp" ] || [ -d "$w/claimed" ]; then
            systemctl --user stop "$(cat "$w/unit" 2>/dev/null)" 2>/dev/null
            rm -rf "$w"
        fi
    done
    (cd "$ROOT" && julia --project=. --startup-file=no -e 'using LogicKernel' < /dev/null) || return 1
    for k in $(seq 1 "$n"); do
        w="$DIR/pool/w$k"
        [ -f "$w/fp" ] && continue                       # already warming for this tree
        u="lk-pool-$(printf '%s' "$ROOT" | md5sum | cut -c1-8)-$k"
        systemctl --user stop "$u" 2>/dev/null
        _spawn_worker "$ROOT" "$w" "$fp" "$u" || return 1
        echo "$u" > "$w/unit"
    done
    echo "pool: $n workers warming for tree ${fp:0:12} — tools/run_tests.sh uses them while the tree is unchanged"
}

_workload() {
    local v
    case "${1:-}" in on) v=true ;; off) v=false ;; *) echo "usage: tools/warm.sh workload on|off" >&2; return 2 ;; esac
    # PrecompileTools' own switch, a LOCAL preference (LocalPreferences.toml, gitignored): CI and
    # fresh clones keep the workload (user, 2026-10-03)
    (cd "$ROOT" && julia --startup-file=no --project=. -e \
        "import PrecompileTools, LogicKernel; PrecompileTools.Preferences.set_preferences!(LogicKernel, \"precompile_workload\" => $v; force=true)" < /dev/null) &&
        echo "precompile workload: $1 (this checkout; restart the lane to recompile)"
}

cmd="${1:-status}"; shift || true
case "$cmd" in
    start) _start ;;
    stop) _stop ;;
    restart) _stop; _start ;;
    status) if _running; then echo "warm lane: running (unit $UNIT, pid $(cat "$DIR/ready"))"; else echo "warm lane: not running"; exit 3; fi ;;
    send) _send "${1:-}" ;;
    file) [ $# -ge 1 ] || { echo "usage: tools/warm.sh file PATH [impl]" >&2; exit 2; }; _file "$@" ;;
    bench) _bench "$@" ;;
    evidence) exec "$ROOT/tools/run_tests.sh" ;;
    pool) _pool ;;
    workload) _workload "${1:-}" ;;
    *) sed -n '2,12p' "$0"; exit 2 ;;
esac
