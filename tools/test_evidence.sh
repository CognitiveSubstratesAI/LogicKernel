#!/usr/bin/env bash
# tools/test_evidence.sh — the sharded evidence run's own tests (tools/lib_evidence.sh,
# tools/worker.jl), each judged by an exit code (user, 2026-10-03: every guard mutation-proved).
#
#   tools/test_evidence.sh          # exit 0 only if every case passes
#
# What the coordinator must never do: certify a run in which a unit was skipped, run twice, or
# never claimed; certify an empty run; certify a run that never exercised the second implementation;
# or let a worker that loaded the code BEFORE an edit certify the tree AFTER it.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
. "$ROOT/tools/lib_evidence.sh"
mkdir -p "$ROOT/.evidence"
T="$(mktemp -d "$ROOT/.evidence/test.XXXXXX")"
U="lk-evidence-test-$$"
trap 'systemctl --user stop "$U" "$U-pin" 2>/dev/null; rm -rf "$T"' EXIT
pass=0 fail=0
check() {   # check NAME WANT_EXIT GOT_EXIT
    if [ "$2" = "$3" ]; then pass=$((pass + 1)); echo "  ok   $1"
    else fail=$((fail + 1)); echo "  FAIL $1: exit $3, want $2"; fi
}

# a fixture run: N units, the ones in SEQ ran (one shard), claims for CLAIMED, the given stats
fixture() {   # fixture DIR N "claimed ids" "seq ids" "plain interned shared"
    rm -rf "$1"; mkdir -p "$1/claims"
    echo "$2" > "$1/units_total"
    for i in $3; do mkdir "$1/claims/$i"; done
    for i in $4; do printf '%s\tunit %s\t1.0\n' "$i" "$i" >> "$1/seq_1.tsv"; done
    echo "$5" > "$1/stats_1"
    echo "${LOGICKERNEL_TERM_TYPES:-all}" > "$1/types_1"     # the term types the shard ran
}
F="$T/run"
fixture "$F" 4 "1 2 3 4" "1 2 3 4" "5 6 7";  _check_run "$F" > /dev/null 2>&1; check "a complete run passes" 0 $?
fixture "$F" 4 "1 2 3" "1 2 3" "5 6 7";      _check_run "$F" > /dev/null 2>&1; check "a unit never claimed fails" 1 $?
fixture "$F" 4 "1 2 3 4" "1 2 3" "5 6 7";    _check_run "$F" > /dev/null 2>&1; check "a unit claimed but not run fails" 1 $?
fixture "$F" 4 "1 2 3 4" "1 2 2 3 4" "5 6 7"; _check_run "$F" > /dev/null 2>&1; check "a unit run twice fails" 1 $?
# …and the case only the DUPLICATE check sees: one unit twice, another never — the count is right
fixture "$F" 4 "1 2 3 4" "1 2 2 3" "5 6 7";  _check_run "$F" > /dev/null 2>&1; check "one unit twice, another never, fails" 1 $?
fixture "$F" 0 "" "" "5 6 7";                 _check_run "$F" > /dev/null 2>&1; check "an empty run fails" 1 $?
fixture "$F" 4 "1 2 3 4" "1 2 3 4" "5 6 7"; rm "$F/units_total"
_check_run "$F" > /dev/null 2>&1; check "a run with no unit count fails" 1 $?
fixture "$F" 4 "1 2 3 4" "1 2 3 4" "5 6 0";  _check_run "$F" > /dev/null 2>&1; check "no sharing exercised fails" 1 $?
fixture "$F" 4 "1 2 3 4" "1 2 3 4" "0 6 7";  _check_run "$F" > /dev/null 2>&1; check "no plain AltTerm run fails" 1 $?

# the machine's numbers in a run's summary: steal between two samples, and the host probe
[ "$(_steal_pct "1000 10" "2000 60")" = "5.0" ]; check "steal: 50 of 1000 jiffies is 5.0%" 0 $?
[ "$(_steal_pct "1000 10" "1000 10")" = "n/a" ]; check "steal: no time elapsed is n/a, not 0" 0 $?
read -r t s <<< "$(_cpu_sample)"
[ "${t:-0}" -gt 0 ] && [ -n "$s" ]; check "a /proc/stat sample has a total and a steal" 0 $?
awk -v p="$(_host_probe_s)" 'BEGIN { exit !(p > 0) }'; check "the host probe takes measurable time" 0 $?

# the tree fingerprint: a change of content changes it (a new file, here); restoring restores it
fp1="$(_tree_fp "$ROOT")"; fp2="$(_tree_fp "$ROOT")"
[ -n "$fp1" ] && [ "$fp1" = "$fp2" ]; check "the fingerprint is stable and non-empty" 0 $?
probe="$ROOT/tools/.fp_probe_$$"; echo "x" > "$probe"
fp3="$(_tree_fp "$ROOT")"; rm -f "$probe"
[ "$fp3" != "$fp1" ]; check "a new file changes the fingerprint" 0 $?
[ "$(_tree_fp "$ROOT")" = "$fp1" ]; check "…and removing it restores it" 0 $?

# a REAL worker refuses a run for another tree: started for fingerprint A, told to go for B. It
# compiles in the EVIDENCE depot (as tools/run_tests.sh precompiles before spawning workers)
(cd "$ROOT" && JULIA_DEPOT_PATH="$(_evidence_depot_path "$ROOT")" \
    julia --project=. --startup-file=no -e 'using LogicKernel' < /dev/null) ||
    { echo "test_evidence: precompile into the evidence depot failed"; exit 1; }
W="$T/worker"
_spawn_worker "$ROOT" "$W" "fingerprint-A" "$U" || { echo "test_evidence: could not start a worker"; exit 1; }
_wait_ready "$W" "$U" 900; check "a worker starts and reports ready" 0 $?
grep -qF "worker: depot $(_evidence_depot "$ROOT")" "$W/log"
check "…loading from the evidence depot, not the warm daemon's" 0 $?
# the shard directory does not exist: a worker that skipped the check fails fast, not after a shard
printf '%s\n%s\n%s\n' "fingerprint-B" "$T/nowhere" "1" > "$W/go.tmp" && mv "$W/go.tmp" "$W/go"
for _ in $(seq 1 120); do [ -f "$W/rc" ] && break; sleep 0.5; done
check "a worker REFUSES a run for a changed tree (exit 3)" 3 "$(cat "$W/rc" 2>/dev/null || echo none)"
! grep -q '\[unit\]' "$W/log"
check "…and ran no unit" 0 $?

# a REAL worker whose PATH finds another swipl than the pin refuses before it is ready (exit 4): the
# oracle is checked where the differentials run — a fake swipl first on PATH, as systemd's own PATH
# once put /usr/local/bin/swipl 10.1.12 before the pinned one
FAKE="$T/fakebin"; mkdir -p "$FAKE"
printf '#!/bin/sh\necho "SWI-Prolog version 0.0.1 for x86_64-linux"\n' > "$FAKE/swipl"
chmod +x "$FAKE/swipl"
W2="$T/worker_pin"
PATH="$FAKE:$PATH" _spawn_worker "$ROOT" "$W2" "fingerprint-A" "$U-pin" ||
    { echo "test_evidence: could not start the second worker"; exit 1; }
_wait_ready "$W2" "$U-pin" 900; check "a worker under another swipl never becomes ready" 1 $?
for _ in $(seq 1 60); do [ -f "$W2/rc" ] && break; sleep 0.5; done
check "…it REFUSES (exit 4)" 4 "$(cat "$W2/rc" 2>/dev/null || echo none)"

echo "test_evidence: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
