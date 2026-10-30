#!/usr/bin/env bash
# ORIGINAL: one test file the way Pkg.test runs it (audit D-0222, 2026-10-29) — no swipl-devel counterpart.
#
#   tools/pkgtest_way.sh test/files/test_x.jl     # exit 0 only if the file passed AND its pass line was shown
#   LOGICKERNEL_PKGTEST_WAY_OUT=DIR               # where <file>.out and <file>.err go (default .warm/pkgtest_way)
#   LOGICKERNEL_INERT_MEM_MAX=3G                  # the run's own memory ceiling (audit D-0242 item 2)
#   LOGICKERNEL_INERT_SLICE=lk-warm.slice         # the lane's slice the run's scope is nested in (warm.sh sets it)
#
# WHY. A warm run is not Pkg.test: the daemon has swipl and a terminal-less but daemon-shaped stdio, and CI's
# Pkg.test has no swipl and its stdout/stderr are PIPES, not what the daemon's are. Three CI-only reds in two days
# (BLOB a301561's declaration, SSU2 ca51c2a's inert testset, S1's test_open_close_swipl.jl: `Suser_output(ld)` was no
# IOSTREAM and a table was empty without swipl) passed every local run. So a changed test file runs once more in a
# FRESH process the way CI runs it: LOGICKERNEL_NO_SWIPL=1 (no LOGICKERNEL_REQUIRE_*), stdin from /dev/null,
# stdout and stderr to PIPES (a logger writes the files), and the inert-testset guard over the result
# (tools/pkgtest_way.jl). In a scope with a memory ceiling. FAIL CLOSED: a zero exit without the pass line is a failure (exit 4).
#
# ONE AT A TIME, IN ITS OWN SCOPE (audit D-0242 item 2, 2026-10-29): BP2's second daemon was OOM-killed by its 6G slice
# while a Pkg.test-way process shared it. So (a) the runs hold one lock (.warm/pkgtest_way.lock): a second waits, they
# never overlap (warm.sh runs them from its own serial steps, never beside the daemon's file run); (b) each run is its
# OWN `systemd-run --user --scope` with MemoryMax=3G and no swap, NESTED in the lane's slice (--slice=), with
# OOMPolicy=continue so only the test process is killed — the daemon, a sibling in the slice, survives, and this script
# survives to report it; (c) the scope's PEAK memory (cgroup memory.peak, read from inside the scope before it ends, no
# root) is printed (`pkgtest_way: <file> peak N MiB (cap C, oom_kill K)`) and appended to peaks.tsv in the output
# directory, so the branch-gate log carries it and the slice's right size can be read off.
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
mem="${LOGICKERNEL_INERT_MEM_MAX:-3G}"
# ONE AT A TIME: a second run waits for the first (fd 9 is closed for the test process below)
lock="${LOGICKERNEL_PKGTEST_WAY_LOCK:-$ROOT/.warm/pkgtest_way.lock}"
mkdir -p "$(dirname "$lock")"
exec 9> "$lock"
if ! flock -n 9; then
    echo "pkgtest_way: another Pkg.test-way run holds $lock — waiting (they run one at a time, D-0242)" >&2
    flock 9
fi
unset LOGICKERNEL_REQUIRE_SWIPL LOGICKERNEL_REQUIRE_TOOLS LOGICKERNEL_TERM
export LOGICKERNEL_NO_SWIPL=1
cmd=("$J" --project="$ROOT" --startup-file=no "$ROOT/tools/pkgtest_way.jl" "$f")
scope=()
peakf="$base.peak"
rm -f "$peakf"
if command -v systemd-run > /dev/null 2>&1 && systemd-run --user --scope true > /dev/null 2>&1; then
    slice=()
    [ -n "${LOGICKERNEL_INERT_SLICE:-}" ] && slice=(--slice="$LOGICKERNEL_INERT_SLICE")
    scope=(systemd-run --user --scope --quiet "${slice[@]}" -p MemoryMax="$mem" -p MemorySwapMax=0 -p TasksMax=512
        -p OOMPolicy=continue)
fi
# Inside the scope: run the command, then read the scope's own peak before the scope ends. OOMPolicy=continue keeps this
# shell alive when the kernel kills the test process (exit 137), so the peak of a KILLED run is read too.
# shellcheck disable=SC2016                       # the snippet is for the inner shell
inner='cg=$(sed -n "s/^0:://p" /proc/self/cgroup); p=$1; shift; "$@"; rc=$?
{ echo "peak_bytes=$(cat "/sys/fs/cgroup$cg/memory.peak" 2> /dev/null)"
  echo "oom_kill=$(sed -n "s/^oom_kill //p" "/sys/fs/cgroup$cg/memory.events" 2> /dev/null)"; } > "$p"
exit $rc'
runner=()
[ "${#scope[@]}" -gt 0 ] && runner=(bash -c "$inner" _ "$peakf")
# STDOUT AND STDERR ARE PIPES, like CI's julia-runtest (audit D-0247): each stream goes through a pipe to a logger
# (`tee FILE`, its own copy to /dev/null: the log stays quiet), the two kept apart (.out, .err), not files the child
# opens. The child's exit status is the first stage's PIPESTATUS of the inner pipeline, written to $base.rc.
rcf="$base.rc"
rm -f "$rcf"
{
    "${scope[@]}" "${runner[@]}" "${cmd[@]}" < /dev/null 2>&1 >&3 3>&- 9>&- | tee "$base.err" > /dev/null 9>&-
    echo "${PIPESTATUS[0]}" > "$rcf"
} 3>&1 | tee "$base.out" > /dev/null 9>&-
rc=$(cat "$rcf" 2> /dev/null)
rc="${rc:-125}"                                  # no status written: the run is lost, never a pass
peak_mib="" oom=0
if [ -s "$peakf" ]; then
    pb=$(sed -n 's/^peak_bytes=//p' "$peakf")
    oom=$(sed -n 's/^oom_kill=//p' "$peakf")
    oom="${oom:-0}"
    if [ -n "$pb" ]; then peak_mib=$((pb / 1048576)); fi
fi
peak_txt="${peak_mib:+${peak_mib} MiB}"
peak_txt="${peak_txt:-not measured (no user systemd scope)}"
echo "pkgtest_way: $(basename "$f") peak ${peak_txt} (cap $mem, oom_kill $oom)"
printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$(date -u +%FT%TZ)" "$(basename "$f")" "${peak_mib:--}" "$mem" "$oom" "$rc" >> "$out/peaks.tsv"
if [ "$rc" -ne 0 ] && { [ "$rc" -eq 137 ] || [ "$oom" != 0 ]; }; then
    # the kernel killed the test process in ITS scope; the lane's daemon is not in it
    echo "pkgtest_way: KILLED — $(basename "$f") hit its memory cap ($mem): peak ${peak_txt}, oom_kill $oom, exit $rc — the test process was killed in its own scope, not the daemon" >&2
elif [ "$oom" != 0 ]; then
    echo "pkgtest_way: WARNING — a process in $(basename "$f")'s scope was OOM-killed (oom_kill $oom) though the run exited 0" >&2
fi
if [ "$rc" -ne 0 ]; then
    echo "pkgtest_way: FAILED (exit $rc) — $base.out $base.err" >&2
    # the failing test's OWN report (its `Test Failed` / `Error During` lines, with the testset's name) is on STDOUT,
    # not stderr, which holds only the summary exception: both are shown (CI's tooling job lost the planted file's
    # `planted: Test Failed` line to a tail of stderr alone, 2026-10-29)
    grep -E -A5 'Test Failed|Error During' "$base.out" | head -n 40 >&2
    tail -n 25 "$base.err" >&2
    exit "$rc"
fi
if ! grep -q "^pkgtest-way: PASS " "$base.out"; then
    echo "pkgtest_way: NO VERDICT — exit 0 without the pass line ($base.out) (exit 4)" >&2
    exit 4
fi
echo "pkgtest_way: $(basename "$f") passed the way Pkg.test runs it"
