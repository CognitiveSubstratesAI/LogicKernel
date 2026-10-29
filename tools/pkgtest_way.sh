#!/usr/bin/env bash
# ORIGINAL: one test file the way Pkg.test runs it (audit D-0222, 2026-10-29) — no swipl-devel counterpart.
#
#   tools/pkgtest_way.sh test/files/test_x.jl     # exit 0 only if the file passed AND its pass line was shown
#   LOGICKERNEL_PKGTEST_WAY_OUT=DIR               # where <file>.out and <file>.err go (default .warm/pkgtest_way)
#
# WHY. A warm run is not Pkg.test: the daemon has swipl and a terminal-less but daemon-shaped stdio, and CI's
# Pkg.test has no swipl and its stdout/stderr are not what the daemon's are. Three CI-only reds in two days
# (BLOB a301561's declaration, SSU2 ca51c2a's inert testset, S1's test_open_close_swipl.jl: `Suser_output(ld)` was no
# IOSTREAM and a table was empty without swipl) passed every local run. So a changed test file runs once more in a
# FRESH process the way CI runs it: LOGICKERNEL_NO_SWIPL=1 (no LOGICKERNEL_REQUIRE_*), stdin from /dev/null,
# stdout and stderr to FILES, and the inert-testset guard over the result (tools/pkgtest_way.jl). In a scope with a
# memory ceiling. FAIL CLOSED: a zero exit without the pass line is a failure (exit 4).
# LOGICKERNEL_PKGTEST_WAY_JULIA replaces the julia binary: a TEST SEAM (test/test_gate_split.jl records the stdio).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
f="${1:-}"
[ -n "$f" ] || { echo "usage: tools/pkgtest_way.sh FILE" >&2; exit 2; }
case "$f" in /*) ;; *) f="$ROOT/$f" ;; esac
[ -f "$f" ] || { echo "pkgtest_way: no such file: $f" >&2; exit 2; }
out="${LOGICKERNEL_PKGTEST_WAY_OUT:-$ROOT/.warm/pkgtest_way}"
mkdir -p "$out"
base="$out/$(basename "$f" .jl)"
J="${LOGICKERNEL_PKGTEST_WAY_JULIA:-julia}"
unset LOGICKERNEL_REQUIRE_SWIPL LOGICKERNEL_REQUIRE_TOOLS LOGICKERNEL_TERM
export LOGICKERNEL_NO_SWIPL=1
cmd=("$J" --project="$ROOT" --startup-file=no "$ROOT/tools/pkgtest_way.jl" "$f")
scope=()
if command -v systemd-run > /dev/null 2>&1 && systemd-run --user --scope true > /dev/null 2>&1; then
    scope=(systemd-run --user --scope --quiet -p MemoryMax="${LOGICKERNEL_TEST_MEM_MAX:-6G}" -p MemorySwapMax=0 -p TasksMax=512)
fi
"${scope[@]}" "${cmd[@]}" < /dev/null > "$base.out" 2> "$base.err"
rc=$?
if [ "$rc" -ne 0 ]; then
    echo "pkgtest_way: FAILED (exit $rc) — $base.out $base.err" >&2
    tail -n 25 "$base.err" >&2
    exit "$rc"
fi
if ! grep -q "^pkgtest-way: PASS " "$base.out"; then
    echo "pkgtest_way: NO VERDICT — exit 0 without the pass line ($base.out) (exit 4)" >&2
    exit 4
fi
echo "pkgtest_way: $(basename "$f") passed the way Pkg.test runs it"
