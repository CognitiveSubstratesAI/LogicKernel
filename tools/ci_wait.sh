#!/usr/bin/env bash
# ORIGINAL: no swipl-devel counterpart — the CI WAITER (audit D-0178 item 1, D-0166/D-0155: cut the
# dispatcher's context). Run it in the BACKGROUND (you are notified when it exits); it sleeps itself.
#
#   tools/ci_wait.sh [--timeout S] [--all] [--repo OWNER/NAME] SHA
#
# Polls the GitHub check runs of SHA (one API call per poll, ONE per >= 300 s: the unauthenticated API
# is 60 an hour) until the commit is decided, then prints <= 10 lines: the verdict, the job counts, one
# line per job that is NOT green (name, status, conclusion, URL — feed the job id to
# workflows/ci_job_log.sh), and the elapsed time. --all lists every job instead (no line cap).
# Of several runs of one job name (a re-run) the LATEST counts.
#
# Exit status:  0 every job completed green (success, neutral, skipped)
#               1 a job completed and did not succeed (decided at once, other jobs may still run)
#               2 TIMEOUT (default 3600 s) with jobs still queued/in progress or no check yet
#               3 the API answer was unreadable on 3 polls in a row (not a verdict)
# Seams for tools/test_summary.sh: LOGICKERNEL_CI_WAIT_TESTING=1 lets LOGICKERNEL_CI_WAIT_INTERVAL_S go below
# 300 and skips the stored-token lookup; `curl` is found through PATH.
# The token, only when the anonymous answer is no check list (a rate limit): read with `git credential
# fill`, handed to curl on STDIN (`-K -`) — never in argv, history or output (as tools/ci_status.sh).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TIMEOUT=3600 ALL=0 REPO="" SHA=""
while [ $# -gt 0 ]; do
    case "$1" in
        --timeout) TIMEOUT="${2:-}"; shift 2 ;;
        --all) ALL=1; shift ;;
        --repo) REPO="${2:-}"; shift 2 ;;
        -*) echo "ci_wait: unknown option $1" >&2; exit 2 ;;
        *) SHA="$1"; shift ;;
    esac
done
case "$TIMEOUT" in '' | *[!0-9]*) echo "ci_wait: --timeout needs seconds" >&2; exit 2 ;; esac
[ -n "$SHA" ] || { echo "usage: tools/ci_wait.sh [--timeout S] [--all] [--repo OWNER/NAME] SHA" >&2; exit 2; }
if full="$(git -C "$ROOT" rev-parse --verify --quiet "$SHA^{commit}" 2> /dev/null)"; then
    SHA="$full"
elif ! printf '%s' "$SHA" | grep -qE '^[0-9a-f]{40}$'; then
    echo "ci_wait: $SHA: not a commit this repository has, nor a full SHA"
    exit 2
fi
[ -n "$REPO" ] || REPO="$(git -C "$ROOT" remote get-url origin 2> /dev/null | sed -E 's#^.*github\.com[:/]##; s#\.git$##')"
INTERVAL="${LOGICKERNEL_CI_WAIT_INTERVAL_S:-300}"
if [ "${LOGICKERNEL_CI_WAIT_TESTING:-}" != 1 ] && { [ "$INTERVAL" -lt 300 ] 2> /dev/null || ! [ "$INTERVAL" -ge 0 ] 2> /dev/null; }; then
    INTERVAL=300
fi
API="https://api.github.com/repos/$REPO/commits/$SHA/check-runs?per_page=100"

_fetch() {
    local J TOK
    J="$(curl -s -m 25 "$API")"
    if ! printf '%s' "$J" | grep -q '"check_runs"' && [ "${LOGICKERNEL_CI_WAIT_TESTING:-}" != 1 ]; then
        TOK="$(printf 'protocol=https\nhost=github.com\n\n' |
            git -c credential.useHttpPath=false credential fill 2> /dev/null | sed -n 's/^password=//p')"
        [ -n "$TOK" ] && J="$(printf 'header = "Authorization: Bearer %s"\n' "$TOK" | curl -s -m 25 -K - "$API")"
        unset TOK
    fi
    printf '%s' "$J"
}

# _judge — reads the API answer on stdin; prints the report; exit 0 green, 1 red, 3 pending/none, 4 unreadable
_judge() {
    python3 -I -c '
import json, sys
sha, allv, secs = sys.argv[1], sys.argv[2] == "1", sys.argv[3]
try:
    runs = json.load(sys.stdin)["check_runs"]
except Exception:
    sys.exit(4)
latest = {}
for r in runs:                      # a re-run of one job name: the latest (highest id) counts
    if r["name"] not in latest or r["id"] > latest[r["name"]]["id"]:
        latest[r["name"]] = r
jobs = sorted(latest.values(), key=lambda r: r["name"])
ok = ("success", "neutral", "skipped")
red = [r for r in jobs if r["status"] == "completed" and r.get("conclusion") not in ok]
pend = [r for r in jobs if r["status"] != "completed"]
green = [r for r in jobs if r not in red and r not in pend]
if not jobs:
    v, code = "NO CHECKS YET", 3
elif red:
    v, code = "RED", 1
elif pend:
    v, code = "PENDING", 3
else:
    v, code = "GREEN", 0
lines = ["ci_wait: %s %s after %ss — %d job(s): %d green, %d red, %d pending" % (sha[:7], v, secs, len(jobs), len(green), len(red), len(pend))]
show = jobs if allv else red + pend
for r in show:
    lines.append("  %-44s %-11s %-9s %s" % (r["name"][:44], r["status"], r.get("conclusion") or "-", r.get("html_url", "")))
if not allv and len(lines) > 9:
    n = len(lines) - 8
    lines = lines[:8] + ["  ... %d more not green (--all lists every job)" % n]
print("\n".join(lines))
sys.exit(code)
' "$SHA" "$ALL" "$1"
}

start=$(date +%s) bad=0
while :; do
    J="$(_fetch)"
    elapsed=$(( $(date +%s) - start ))
    report="$(printf '%s' "$J" | _judge "$elapsed")"
    rc=$?
    case "$rc" in
        0 | 1) printf '%s\n' "$report"; exit "$rc" ;;
        4) bad=$((bad + 1)) ;;
        *) bad=0 ;;
    esac
    if [ "$bad" -ge 3 ]; then
        echo "ci_wait: $SHA: the API answer was unreadable 3 times in a row ($(printf '%s' "$J" | head -c 120 | tr '\n' ' '))"
        exit 3
    fi
    if [ $(( $(date +%s) - start + INTERVAL )) -gt "$TIMEOUT" ]; then
        if [ "$rc" = 4 ]; then echo "ci_wait: TIMEOUT after ${elapsed}s — the last API answer was unreadable"
        else printf '%s\n' "$report" | sed '1s/^ci_wait: \([0-9a-f]*\) /ci_wait: \1 TIMEOUT, last state: /'; fi
        exit 2
    fi
    sleep "$INTERVAL"
done
