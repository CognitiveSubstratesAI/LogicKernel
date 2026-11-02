#!/usr/bin/env bash
# ORIGINAL: no swipl-devel counterpart — CI TRIAGE of one run (audit D-0327 item 1): what failed, in at most
# 40 lines, instead of a gate agent paging through 300 KB job logs.
#
#   tools/ci_triage.sh <run id>
#
# Prints the run (workflow, branch, SHA), the failed jobs, the first `##[error]` line (with the jobs that
# end in it), and the DISTINCT failing tests across the jobs: kind (Test Failed / Error During Test /
# JET-test failed), file:line, the test's description, Expression and Evaluated (colour codes removed, long
# values cut), and the jobs it failed in. A tools test's `  FAIL <case>` line counts as a failing test too.
# At most 20 failed jobs have their log read.
# Read-only: tools/ci_api.sh (curl GET; the stored token on stdin; nothing is printed or written of it).
# Exit status: 0 no job failed, 1 a job failed (the report), 2 unreadable, 64 usage.
# Seam: LOGICKERNEL_CI_FIXTURE_DIR (tools/ci_api.sh) — tools/test_ci_tools.sh runs it on saved logs.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=tools/ci_api.sh
. "$ROOT/tools/ci_api.sh"
RUN="${1:-}"
case "$RUN" in '' | *[!0-9]*) echo "usage: tools/ci_triage.sh <run id>" >&2; exit 64 ;; esac
T="$(mktemp -d "${TMPDIR:-/tmp}/ci_triage.XXXXXX")"
trap 'rm -rf "$T"' EXIT
page=1
while [ "$page" -le 10 ]; do
    ci_jobs_page "$RUN" "$page" > "$T/jobs_$page.json"
    n="$(python3 -I -c 'import json,sys
try: print(len(json.load(open(sys.argv[1]))["jobs"]))
except Exception: print(-1)' "$T/jobs_$page.json")"
    if [ "$n" -lt 0 ]; then
        [ "$page" -gt 1 ] || { echo "ci_triage: run $RUN: the jobs answer is unreadable"; exit 2; }
        rm -f "$T/jobs_$page.json"
        break
    fi
    [ "$n" -ge 100 ] || break
    page=$((page + 1))
done
count=0
while IFS=$'\t' read -r id _; do
    [ -n "$id" ] || continue
    count=$((count + 1))
    [ "$count" -le 20 ] || break
    ci_job_log "$id" "$RUN" > "$T/$id.log" 2> /dev/null || rm -f "$T/$id.log"
done < <(python3 -I "$ROOT/tools/ci_triage.py" failed "$T")
python3 -I "$ROOT/tools/ci_triage.py" report "$T" "$RUN"
