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
#   tools/warm.sh preflight                # WARM: what a full run would fail on, BEFORE one (exit 0/1);
#                                          # a stale daemon (a deleted method it kept) is restarted
#                                          # and the preflight rerun once
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
# shellcheck source=/dev/null
. "$ROOT/tools/lib_evidence.sh"
UNIT="logickernel-warm-$(printf '%s' "$ROOT" | md5sum | cut -c1-8)"   # one daemon per checkout

_running() { systemctl --user is-active --quiet "$UNIT" && [ -f "$DIR/ready" ]; }

_start() {
    if _running; then echo "warm lane: running (unit $UNIT, pid $(cat "$DIR/ready"))"; return 0; fi
    mkdir -p "$DIR"
    rm -f "$DIR/ready" "$DIR/done" "$DIR/status" "$DIR/in.jl"
    local julia
    julia="$(command -v julia)" || { echo "warm lane: no julia on PATH" >&2; return 1; }
    # PRECOMPILE the current source into the daemon's depot first — no daemon is running, so nothing
    # can refuse a rewritten cache — so `stale_load` starts from a cache that IS the source. Evidence
    # compiles elsewhere (the evidence depot), so this cache only aged: measured 2026-10-04, a start
    # revised 445 methods, and the static-analysis gate then saw each replaced one as unchecked.
    # (JULIA_DEPOT_PATH only when a copy has its own depot: an EMPTY value leaves Julia with no depot)
    local depot_env=()
    [ -n "${LOGICKERNEL_WARM_DEPOT:-}" ] &&
        depot_env=("JULIA_DEPOT_PATH=$LOGICKERNEL_WARM_DEPOT:$HOME/.julia:")
    (cd "$ROOT" && env "${depot_env[@]}" \
        "$julia" --project=. --startup-file=no -e 'using LogicKernel' < /dev/null) ||
        { echo "warm lane: LogicKernel does not precompile" >&2; return 1; }
    # the same ceiling and flags as tools/run_tests.sh. A service starts from systemd's own PATH, not
    # ours, so it gets ours — the swipl its differentials judge against; the daemon checks the pin.
    # A checkout COPY (parallel mutation proofs, user 2026-10-04) gives its daemon a depot of its own,
    # LOGICKERNEL_WARM_DEPOT, and a normal load: the original checkout's cache is not this copy's.
    local copy_env=()
    if [ -n "${LOGICKERNEL_WARM_DEPOT:-}" ]; then
        copy_env=(-E "JULIA_DEPOT_PATH=$LOGICKERNEL_WARM_DEPOT:$HOME/.julia:"
            -E LOGICKERNEL_WARM_NO_STALE_LOAD=1)
    fi
    systemd-run --user --unit="$UNIT" --collect --quiet -p MemoryMax="${LOGICKERNEL_TEST_MEM_MAX:-8G}" \
        -p MemorySwapMax=0 --working-directory="$ROOT" -E "PATH=$PATH" "${copy_env[@]}" \
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
    (cd "$ROOT" && JULIA_DEPOT_PATH="$(_evidence_depot_path "$ROOT")" \
        julia --project=. --startup-file=no -e 'using LogicKernel' < /dev/null) || return 1
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

# _preflight — what a full run would fail on, checked WARM before the cold evidence run (user,
# 2026-10-04: "do not waste time on cold starts .. make use of possible solutions to run warm").
# MEASURED that day: two of three cold runs (~11 min each) failed on port_check and on JET — each
# answer this gives in about a minute. Fast checks first, failing fast: Blue formatting (as
# run_tests.sh and CI check it) and port_check. Then, while the evidence workers pre-warm for this
# tree (`pool`, in the evidence depot, so the daemon's cache is untouched): the static-analysis gate
# (JET/Aqua/AllocCheck — ~26 s warm, against ~200 s in a cold worker) and every test file changed
# since HEAD, on every implementation. Exit 0 only if all of it passed; the cold run that follows is
# then the evidence, and starts from loaded workers. LOGICKERNEL_PREFLIGHT_POOL=0 skips the pool.
_preflight_once() {
    _running || _start > /dev/null || return 1
    local t0 rc=0 f files pooled=""
    PF_SA_FAIL=0 PF_OTHER_FAIL=0                       # which steps failed, for _preflight
    t0=$(date +%s)
    # THE GATE SPLIT'S CONDITION (user, 2026-10-06): a gate cycle starts by reading the previous
    # push's CI — red, or unreadable, stops it here (tools/lib_evidence.sh `_ci_gate`)
    _ci_gate "$ROOT" 0 || {
        PF_OTHER_FAIL=1
        echo "preflight: FAIL — the previous push's CI (tools/ci_status.sh)"
        return 1
    }
    local snippet="$DIR/preflight_snippet.jl"
    cat > "$snippet" <<JL
using JuliaFormatter
if !format("."; overwrite=false)
    bad = String[]
    for (dir, dirs, files) in walkdir(".")
        filter!(d -> !(d in (".git", ".warm", ".evidence", "build")), dirs)
        for f in files
            endswith(f, ".jl") && !format(joinpath(dir, f); overwrite=false) &&
                push!(bad, joinpath(dir, f))
        end
    end
    error("preflight: NOT Blue-formatted: ", join(bad, ", "), " — tools/run_tests.sh shows each diff")
end
println("preflight: Blue-clean (JuliaFormatter ", pkgversion(JuliaFormatter), ")")
# the CURRENT tools/port_check.jl, in a fresh module every time: a daemon that kept the first one
# it loaded would check an edited tree with an old checker (measured 2026-10-04: M1's own docs were
# held to the pre-M1 inventory format)
let pc = Module(:PreflightPortCheck)
    Base.include(pc, raw"$ROOT/tools/port_check.jl")
    r = Base.invokelatest(() -> pc.port_check(raw"$ROOT"))   # the binding too: latest world
    foreach(x -> println("  ", x), r.violations)
    isempty(r.violations) || error("preflight: port_check found violations")
    mk = r.markers                                     # the gate split of markers (user, 2026-10-06)
    println("preflight: port_check clean (", length(r.files), " files; markers: ", mk.diverges,
        " DIVERGES, ", mk.not_ported, " NOT PORTED, ", mk.both, " DIVERGES lines still saying NOT PORTED)")
end
JL
    _send "$snippet" || {
        PF_OTHER_FAIL=1
        echo "preflight: FAIL (format/port_check) in $(( $(date +%s) - t0 ))s"
        return 1
    }
    if [ "${LOGICKERNEL_PREFLIGHT_POOL:-1}" != "0" ]; then
        _pool > "$DIR/preflight_pool.log" 2>&1 &
        pooled=$!
    fi
    echo "preflight: the static-analysis gate"
    local log="$DIR/preflight_test_static_analysis.log"
    _file test/test_static_analysis.jl > "$log" 2>&1 || { rc=1; PF_SA_FAIL=1; echo "preflight: FAILED — $log"; }
    grep -E "\.jl \[|\.jl  *\||Test Failed|Error During|NOT CHECKED|allocates:" "$log"
    # The TREE-WIDE gates run on every preflight, changed or not: they check src/, so a src edit can
    # fail them while their own file is unchanged (V4a, MEASURED: an `@inbounds` in pl-inline.jl
    # passed the preflight and failed test_type_discipline.jl in the cold evidence run).
    files=$( {
        printf '%s\n' test/test_type_discipline.jl test/test_lint_globals.jl
        cd "$ROOT" && { git diff --name-only HEAD; git ls-files -o --exclude-standard; } |
            grep -E '^test/(.*/)?test_[^/]*\.jl$'
    } | sort -u)
    for f in $files; do
        [ -f "$ROOT/$f" ] && [ "$f" != test/test_static_analysis.jl ] || continue
        echo "preflight: $f"
        log="$DIR/preflight_$(basename "$f" .jl).log"
        _file "$f" > "$log" 2>&1 || { rc=1; PF_OTHER_FAIL=1; echo "preflight: FAILED — $log"; }
        grep -E "\.jl \[|\.jl  *\||Test Failed|Error During" "$log"
    done
    if [ -n "$pooled" ]; then
        wait "$pooled" || echo "preflight: the pool did not start — $DIR/preflight_pool.log"
        tail -1 "$DIR/preflight_pool.log"
    fi
    echo "preflight: $([ "$rc" -eq 0 ] && echo PASS || echo FAIL) in $(( $(date +%s) - t0 ))s"
    return "$rc"
}

# _preflight_stale LOG — classify each method the static-analysis gate reported NOT CHECKED in LOG:
# `STALE name` when no file under src/ defines that name any more (port_check's `definitions`, read
# from the SYNTAX TREE, not by grep), `REAL name` otherwise. Errors when src/ yields no definitions at
# all: an empty set would call every method stale.
_preflight_stale() {
    local snippet="$DIR/preflight_stale.jl"
    cat > "$snippet" <<JL
let pc = Module(:PreflightStale), log = read(raw"$1", String)
    Base.include(pc, raw"$ROOT/tools/port_check.jl")         # the current one (see above)
    names = unique([String(m[1]) for m in eachmatch(r"NOT CHECKED for dispatch: (\S+)", log)])
    defined = Set{String}()
    for (dir, _, fs) in walkdir(raw"$ROOT/src"), f in fs
        endswith(f, ".jl") || continue
        p = joinpath(dir, f)
        foreach(d -> push!(defined, d[2]), Base.invokelatest(() -> pc.definitions(read(p, String), p)))
    end
    isempty(defined) && error("preflight: no definitions found under src/ — cannot classify")
    foreach(n -> println(n in defined ? "REAL " : "STALE ", n), names)
end
JL
    _send "$snippet" | grep -E '^(REAL|STALE) '
}

# _preflight — _preflight_once, RECOVERING from a stale daemon (user, 2026-10-04: "make the gate
# recover, not just detect"). A method Revise failed to delete outlives its source in the daemon, and
# the manifest gate reports it NOT CHECKED: a daemon condition, not a code failure — evidence runs
# are fresh processes and never see it. So when the ONLY failure of a preflight is that gate's
# coverage test, and every method it names is STALE (defined in no file under src/), the daemon is
# restarted and the preflight rerun ONCE; the rerun's verdict is the verdict, and a failure after the
# restart is reported as REAL. It never suppresses a NOT CHECKED: the only way to PASS is a clean
# rerun in a fresh daemon. Any other failure beside it — or a REAL name — fails at once, with the
# names classified so a stale one is not mistaken for a code failure.
_preflight() {
    local rc log="$DIR/preflight_test_static_analysis.log" cls nfail ncov
    _preflight_once; rc=$?
    [ "$rc" -eq 0 ] && return 0
    if [ "${LOGICKERNEL_PREFLIGHT_RETRY:-0}" = 1 ]; then
        echo "preflight: still FAILS after a daemon restart — a REAL failure"
        return "$rc"
    fi
    [ "$PF_SA_FAIL" = 1 ] && grep -q "NOT CHECKED for dispatch:" "$log" || return "$rc"
    cls=$(_preflight_stale "$log")
    [ -n "$cls" ] || { echo "preflight: could not classify the NOT CHECKED methods"; return "$rc"; }
    printf '%s\n' "$cls" | sed 's/^STALE /preflight:   STALE (defined in no src\/ file — a daemon leftover) /;
        s/^REAL /preflight:   REAL (still defined in src\/ — add it to the manifest) /'
    nfail=$(grep -c -E "Test Failed at|Error During Test|JET-test failed" "$log")
    ncov=$(grep -c "the manifest covers every method LogicKernel defines: Test Failed" "$log")
    if [ "$PF_OTHER_FAIL" = 0 ] && [ "$nfail" -eq 1 ] && [ "$ncov" -eq 1 ] &&
        ! grep -q "stale exemption:" "$log" && ! printf '%s\n' "$cls" | grep -q '^REAL '; then
        echo "preflight: STALE DAEMON — restarting the daemon and rerunning the preflight once"
        _stop > /dev/null
        _start > /dev/null || { echo "preflight: the daemon did not restart"; return 1; }
        LOGICKERNEL_PREFLIGHT_RETRY=1 LOGICKERNEL_PREFLIGHT_POOL=0 _preflight
        return $?
    fi
    return "$rc"
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
    preflight) _preflight ;;
    evidence) exec "$ROOT/tools/run_tests.sh" ;;
    pool) _pool ;;
    workload) _workload "${1:-}" ;;
    *) sed -n '2,12p' "$0"; exit 2 ;;
esac
