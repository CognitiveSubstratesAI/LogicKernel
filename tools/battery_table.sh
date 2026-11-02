#!/usr/bin/env bash
# ORIGINAL: no swipl-devel counterpart — the MUTATION BATTERY TABLE of one run (audit D-0327 item 2): the
# verdict in at most 60 lines, with the void case caught first (D-0315: a battery whose Baseline job failed
# proves nothing).
#
#   tools/battery_table.sh <run id>
#
# Finds the `Verdict table` job and the `Baseline (unmutated)` job of the run. A Baseline that did not
# succeed prints "VOID: baseline failed" and stops. Otherwise it prints the caught count, every SURVIVED
# mutant, every EQUIVALENT (declared) mutant with the first 300 characters of its argument, and every
# NO VERDICT mutant with the LAST `##[error]` line of its own job (so a runner shutdown / exit 143 shows).
# Read-only: tools/ci_api.sh (curl GET; the stored token on stdin; never printed or written).
# Exit status: 0 every mutant caught, 1 a survivor / a declared equivalent / no verdict, 2 VOID or
# unreadable, 3 the battery is still running, 64 usage.
# Seam: LOGICKERNEL_CI_FIXTURE_DIR (tools/ci_api.sh) — tools/test_ci_tools.sh runs it on saved logs.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=tools/ci_api.sh
. "$ROOT/tools/ci_api.sh"
RUN="${1:-}"
case "$RUN" in '' | *[!0-9]*) echo "usage: tools/battery_table.sh <run id>" >&2; exit 64 ;; esac
T="$(mktemp -d "${TMPDIR:-/tmp}/battery_table.XXXXXX")"
trap 'rm -rf "$T"' EXIT
page=1
while [ "$page" -le 10 ]; do
    ci_jobs_page "$RUN" "$page" > "$T/jobs_$page.json"
    n="$(python3 -I -c 'import json,sys
try: print(len(json.load(open(sys.argv[1]))["jobs"]))
except Exception: print(-1)' "$T/jobs_$page.json")"
    if [ "$n" -lt 0 ]; then
        [ "$page" -gt 1 ] || { echo "battery_table: run $RUN: the jobs answer is unreadable"; exit 2; }
        rm -f "$T/jobs_$page.json"
        break
    fi
    [ "$n" -ge 100 ] || break
    page=$((page + 1))
done
IFS=$'\t' read -r vid bid < <(python3 -I "$ROOT/tools/battery_table.py" ids "$T" "$RUN")
for id in $vid $bid; do
    ci_job_log "$id" "$RUN" > "$T/$id.log" 2> /dev/null || rm -f "$T/$id.log"
done
# the mutants without a verdict: their own job logs (the job is named by the mutant id)
python3 -I - "$T" "$ROOT" "$RUN" << 'PY' > "$T/nov.ids"
import re, sys, json, glob, os
sys.path.insert(0, sys.argv[2] + "/tools")
import battery_table as b
d = sys.argv[1]
v = b.find(b.load_jobs(d), lambda n: n == "Verdict table")
rows = b.table_of(b.lines_of(os.path.join(d, "%s.log" % v["id"])))[1] if v else []
jobs = b.load_jobs(d)
for r in rows:
    if r[1] == "NO VERDICT":
        j = b.find(jobs, lambda n, i=r[0]: n == i)
        if j:
            print(j["id"])
PY
count=0
while read -r id; do
    [ -n "$id" ] || continue
    count=$((count + 1))
    [ "$count" -le 12 ] || break
    ci_job_log "$id" "$RUN" > "$T/$id.log" 2> /dev/null || rm -f "$T/$id.log"
done < "$T/nov.ids"
python3 -I "$ROOT/tools/battery_table.py" report "$T" "$RUN"
