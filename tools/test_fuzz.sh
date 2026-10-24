#!/usr/bin/env bash
# ORIGINAL: the nightly fuzzer's own tests (audit D-0127 item 3) — no swipl-devel counterpart.
# tools/test_fuzz.sh — tools/fuzz.jl, judged by its exit code (user, 2026-10-03: every guard mutation-proved).
#
#   tools/test_fuzz.sh          # exit 0 only if every case passes
#
# What the nightly job must never do: report green when a seed's answers differ (FUZZ_INJECT=1 corrupts one
# kernel line — the run must exit 1, name the seed, and keep the program); report green when it compared nothing
# (no oracle: exit 2, not 0); run other seeds than the ones asked for. Needs swipl at the pin on PATH and the
# project instantiated (the tooling job has both).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
pass=0 fail=0
check() {   # check NAME WANT_EXIT GOT_EXIT
    if [ "$2" = "$3" ]; then pass=$((pass + 1)); echo "  ok   $1"
    else fail=$((fail + 1)); echo "  FAIL $1: exit $3, want $2"; fi
}
run_fuzz() {   # run_fuzz OUTDIR SEEDS… — the output in $T/log
    (cd "$ROOT" && julia --project=. tools/fuzz.jl "$@" > "$T/log" 2>&1)
}

run_fuzz 5000 2 "$T/clean" 10;                       check "a clean run of two seeds passes" 0 $?
grep -q 'fuzz: 2 seeds from 5000, 20 cases, 0 seed(s) with a mismatch' "$T/log"
check "…and says which seeds, how many cases" 0 $?

FUZZ_INJECT=1 run_fuzz 5000 2 "$T/inj" 10;           check "an injected mismatch fails the run" 1 $?
grep -q '::error title=fuzz mismatch, seed 5000::' "$T/log";  check "…names the seed in an annotation" 0 $?
[ -s "$T/inj/seed_5000/program.pl" ] && [ -s "$T/inj/seed_5000/swipl.txt" ] && [ -s "$T/inj/seed_5001/kernel.txt" ]
check "…keeps the program and both answers of every failing seed" 0 $?

mkdir "$T/bin"; ln -s "$(command -v julia)" "$T/bin/julia"      # a PATH with julia and no swipl
(cd "$ROOT" && PATH="$T/bin" julia --project=. tools/fuzz.jl 5000 1 "$T/none" 10 > "$T/log" 2>&1)
check "no oracle: exit 2, never a green" 2 $?

mkdir "$T/bin2"; ln -s "$(command -v julia)" "$T/bin2/julia"    # an oracle that answers nothing: a comparison of
printf '#!/bin/sh\nexit 0\n' > "$T/bin2/swipl"; chmod +x "$T/bin2/swipl"      # nothing with the kernel's answers
(cd "$ROOT" && PATH="$T/bin2" julia --project=. tools/fuzz.jl 5000 1 "$T/mute" 10 > "$T/log" 2>&1)
check "an oracle that answers nothing: exit 2, not a mismatch and never a green" 2 $?

echo "tools/test_fuzz.sh: $pass passed, $fail failed"
[ "$fail" = 0 ]
