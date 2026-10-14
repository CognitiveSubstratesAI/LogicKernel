#!/usr/bin/env bash
# ORIGINAL: tools/coverage_zero.py's own tests (user, 2026-10-14: every guard mutation-proved) — no
# swipl-devel counterpart. Planted LCOV files over the real src/ tree, each judged by its EXIT CODE,
# against a green baseline (the listed files at 0%, nothing else): exit 0 only if every case passes.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
W="$(mktemp -d "${TMPDIR:-/tmp}/cz.XXXXXX")"
trap 'rm -rf "$W"' EXIT
cd "$ROOT" || exit 1
python3 - "$W" "$ROOT/tools/coverage_zero_known.txt" << 'PY'
import os, sys
W, known = sys.argv[1], sys.argv[2]
files = sorted(os.path.relpath(os.path.join(d, f)) for d, _, fs in os.walk("src") for f in fs if f.endswith(".jl"))
zero0 = {l.split("#", 1)[0].strip() for l in open(known)} - {""}
assert zero0 and zero0 <= set(files), zero0
other = next(f for f in files if f not in zero0)
def write(name, zero, drop=()):
    with open(f"{W}/{name}.info", "w") as o:
        for f in files:
            if f in drop:
                continue
            o.write(f"SF:{f}\nDA:1,{0 if f in zero else 3}\nDA:2,0\nend_of_record\n")
write("baseline", zero0)                          # the listed files at 0%, nothing else: OK
write("newzero", zero0 | {other})                 # a new file at 0%
write("covered", set(sorted(zero0)[1:]))          # a listed file no longer at 0%
write("absent", zero0, drop={other})              # a src/ file never loaded counts as 0%
open(f"{W}/empty.info", "w").close()              # no source file at all: no verdict
PY
pass=0 fail=0
for c in "baseline 0" "newzero 1" "covered 1" "absent 1" "empty 1"; do
    set -- $c
    python3 tools/coverage_zero.py "$W/$1.info" tools/coverage_zero_known.txt > "$W/$1.out" 2>&1
    rc=$?
    if [ "$rc" = "$2" ]; then pass=$((pass + 1)); echo "  ok   $1 (exit $rc)"
    else fail=$((fail + 1)); echo "  FAIL $1: exit $rc, want $2"; sed 's/^/       /' "$W/$1.out"; fi
done
echo "test_coverage_zero: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
