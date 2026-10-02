#!/usr/bin/env bash
# run_tests.sh — run LogicKernel's suite (or ONE file) with a REAL EXIT CODE.
#
#   tools/run_tests.sh                       # full suite
#   tools/run_tests.sh test/some/test_x.jl   # one file (not evidence for a commit)
#
# An instance of the workspace's `workflows/run_tests_template.sh` (2026-10-02). What it guards:
#
# 🔴 `julia -i` WITH PIPED STDIN ALWAYS EXITS 0 — interactive mode swallows exceptions, so a red
# suite reports success (measured in MORK: piped `-i` with a FAILING testset -> exit 0). The driver
# below wraps everything in try/catch and calls `exit(ok ? 0 : 1)` itself.
# ⚠️ `< /dev/null` is load-bearing: a closed pipe as stdin breaks anything that spawns a subprocess
# with explicit stdio (EINVAL).
# ⚠️ MEMORY CEILING: a runaway test is killed in its own cgroup scope (exit 137) instead of the
# kernel's OOM-killer choosing the editor. Find the unbounded allocation; do not just raise the cap.
# 🔴 NEVER wrap this in `timeout`: it kills only the wrapper and the scope keeps running, orphaned.
#
# EVIDENCE. In the CognitiveSubstratesAI workspace, a FULL run writes the per-repo, tree-fingerprinted
# marker the commit hook checks, and fingerprints the tree at LAUNCH so an edit made DURING a run is
# refused rather than certified. In a standalone clone the helper is absent and both steps are no-ops.
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
TARGET="${1:-test/runtests.jl}"
case "$TARGET" in /*) ABS_TARGET="$TARGET" ;; *) ABS_TARGET="$ROOT/$TARGET" ;; esac
[ -f "$ABS_TARGET" ] || { echo "run_tests.sh: no such target: $ABS_TARGET" >&2; exit 2; }

# shellcheck source=/dev/null
. "$ROOT/../workflows/test_marker.sh" 2>/dev/null || true
_LAUNCH_FP=""
command -v start_marker >/dev/null 2>&1 && _LAUNCH_FP="$(start_marker "$ROOT")"

DRIVER="$(mktemp "${TMPDIR:-/tmp}/LogicKernel_run_tests_XXXXXX.jl")"
_finish() {
    local rc="$1"
    rm -f "$DRIVER"
    if command -v write_marker >/dev/null 2>&1; then
        if [ "$TARGET" = "test/runtests.jl" ]; then
            write_marker "$ROOT" "$rc" "run_tests.sh full suite" "$_LAUNCH_FP"
        else
            echo "  test_marker: NOT evidence — filtered run (TARGET=$TARGET)"
        fi
    fi
    exit "$rc"
}

cat > "$DRIVER" <<JL
ok = try
    include(raw"$ABS_TARGET")
    true
catch e
    showerror(stderr, e); println(stderr)
    false
end
exit(ok ? 0 : 1)
JL

MEM_MAX="${LOGICKERNEL_TEST_MEM_MAX:-8G}"
HEAP_HINT="${LOGICKERNEL_TEST_HEAP_HINT:-6G}"
JL=(julia --project=. --threads="${JULIA_TEST_THREADS:-4}" --heap-size-hint="$HEAP_HINT" -i "$DRIVER")

if [ "$MEM_MAX" = "none" ]; then
    echo "run_tests.sh: memory ceiling DISABLED (LOGICKERNEL_TEST_MEM_MAX=none)" >&2
    "${JL[@]}" < /dev/null
    _finish $?
elif command -v systemd-run >/dev/null 2>&1 && systemd-run --user --scope true >/dev/null 2>&1; then
    systemd-run --user --scope -p MemoryMax="$MEM_MAX" -p MemorySwapMax=0 --quiet "${JL[@]}" < /dev/null
    rc=$?
    [ $rc -eq 137 ] && echo "run_tests.sh: KILLED at the ${MEM_MAX} ceiling — a test allocated without bound. Find it before raising LOGICKERNEL_TEST_MEM_MAX." >&2
    _finish $rc
else
    echo "run_tests.sh: WARNING — systemd-run --user --scope unavailable; running WITHOUT a memory ceiling." >&2
    "${JL[@]}" < /dev/null
    _finish $?
fi
# allow-cold-start: full-suite runner; a suite run is a cold run by nature
