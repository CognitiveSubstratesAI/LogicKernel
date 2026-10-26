#!/usr/bin/env bash
# ORIGINAL: no swipl-devel counterpart — the SUMMARY MODE of the run tools (audit D-0178 item 1, D-0166/D-0155:
# cut the dispatcher's context). tools/summarize_log.sh KIND LOG RC SECONDS
#
#   KIND  check | file | static | branch-gate | bench | preflight (anything else: the generic summary)
#   LOG   the full log, written by the caller (tools/warm.sh --summary, tools/bench.sh --summary)
#   RC    the REAL exit status of the run; this script prints it and NEVER decides it — the caller
#         exits with RC itself (no pipeline between the run and its status)
#
# Prints at most 10 lines: the verdict, the counts, the elapsed seconds, up to 5 failing places
# (file:line and the expression), and the full log's path. A verdict comes from the RC, never from
# the log alone: RC 0 with no summary line in the log is "NO VERDICT", not a pass (the guard's third
# failure mode: it compares the wrong thing). A failing run with no recognisable failure line says so.
# Tested by tools/test_summary.sh on fake logs.
set -uo pipefail
KIND="${1:-}" LOG="${2:-}" RC="${3:-}" SECS="${4:-0}"
[ -n "$KIND" ] && [ -n "$LOG" ] && [ -n "$RC" ] || { echo "usage: summarize_log.sh KIND LOG RC SECONDS" >&2; exit 2; }
if [ ! -s "$LOG" ]; then
    echo "$KIND: NO VERDICT (rc=$RC, ${SECS}s) — the log is missing or empty"
    echo "log: $LOG"
    exit 0
fi
MAXFAIL=5
strip() { sed -E 's/\x1b\[[0-9;]*m//g' "$@"; }
# the logs to read for failure places: LOG itself and every "— /path.log" it names (branch-gate, preflight)
logs="$LOG"
extra="$(strip "$LOG" | sed -nE 's/.*[—-] (\/[^ ]+\.log).*/\1/p; s/^.*FAILED [—-] (\/[^ ]+\.log).*/\1/p' | sort -u)"
for l in $extra; do [ -f "$l" ] && [ "$l" != "$LOG" ] && logs="$logs $l"; done
# failing places: "Test Failed at F:L" / "Error During Test at F:L" followed by the expression line
fails() {
    # shellcheck disable=SC2086
    strip $logs | awk '
        /^ *(Test Failed|Error During Test) at / { loc=$0; sub(/^ *(Test Failed|Error During Test) at /, "", loc); want=1; next }
        want && /^ *(Expression|Got exception|Evaluated|Test threw)/ { d=$0; sub(/^ */, "", d); print loc "  " substr(d, 1, 100); want=0; next }
        want && NF==0 { print loc; want=0 }
        /JET-test failed|no matching method|possible error|NOT CHECKED|ambigu/ { d=$0; sub(/^ */, "", d); print substr(d, 1, 120) }
    ' | awk '!seen[$0]++'
}
# Pass/Fail/Error/Broken/Total of the top-level "warm: <file>" testset rows (header names the columns)
counts() {
    strip "$LOG" | awk '
        /^Test Summary: *\|/ { n=split($0, h, "|"); ncol=split(h[2], names, " "); next }
        /^warm: .*\|/ { rows++; if (!ncol) { nohdr++; next } split($0, r, "|"); nv=split(r[2], v, " "); for (i=1;i<=nv && i<=ncol;i++) if (names[i] ~ /^(Pass|Fail|Error|Broken|Total)$/) s[names[i]]+=v[i] }
        # a row with no "Test Summary" header above it (a branch-gate log: the headers sit in the per-file logs)
        # has no known columns: say so, never print zeros that read as counts
        END { if (nohdr) printf "%d file run(s): counts not in this log (no Test Summary header), see the per-file logs\n", rows
              else if (rows) printf "%d file run(s): pass %d, fail %d, error %d, total %d\n", rows, s["Pass"], s["Fail"], s["Error"], s["Total"] }
    '
}
verdict_word() { [ "$RC" -eq 0 ] && echo PASS || echo "FAIL(rc=$RC)"; }
out=()
case "$KIND" in
    bench)
        refused="$(strip "$LOG" | grep -m1 'REFUSED')"
        raw="$(strip "$LOG" | sed -nE 's/^raw numbers: (.*)$/\1/p' | tail -1)"
        rows="$(strip "$LOG" | awk '
            /^case +LK / { t=1; next }
            t && /\([ 0-9.]+\)/ {
                if (match($0, /([0-9.]+|NaN) +[0-9.]+ +[0-9]+( +[0-9]+\/[0-9]+)?[ ]*$/)) {
                    tail=substr($0, RSTART); n=split(tail, f, " ");
                    flag=(f[n] ~ /\//); bytes=f[n-flag]; al=f[n-1-flag]; nm=$0; sub(/ +[0-9].*$/, "", nm)
                    print nm "\t" al "\t" (flag ? f[n] : "")
                }
                next }
            t && NF==0 { t=0 }')"
        ncase=$(printf '%s\n' "$rows" | grep -c . || true)
        if [ -n "$refused" ]; then
            out+=("bench: REFUSED (rc=$RC, ${SECS}s) — ${refused#*REFUSED}")
        elif [ "$RC" -eq 0 ] && [ -n "$raw" ] && [ "$ncase" -gt 0 ]; then
            out+=("bench: DONE (rc=0, ${SECS}s), $ncase cases")
            out+=("raw numbers: $raw")
            flagged="$(printf '%s\n' "$rows" | awk -F'\t' '$3!="" {printf "%s%s(%s)", (n++?", ":""), $1, $3}')"
            out+=("GC>10% samples: ${flagged:-none}")
            out+=("top allocs/call: $(printf '%s\n' "$rows" | sort -t$'\t' -k2,2 -g -r | head -3 | awk -F'\t' '{printf "%s%s=%s", (n++?", ":""), $1, $2}')")
        else
            out+=("bench: $([ "$RC" -eq 0 ] && echo "NO VERDICT (rc=0 but no raw-numbers line or no case rows)" || echo "FAIL (rc=$RC)") (${SECS}s)")
            while IFS= read -r l; do out+=("  $l"); done < <(strip "$LOG" | grep -iE 'error|failed|refused' | head -3 | cut -c1-140)
        fi
        ;;
    *)
        marker="$(strip "$LOG" | grep -E '^(check|branch-gate|preflight|fmt):? *(PASS|FAIL)|^warm: .*\|' | tail -1)"
        nov=0
        if [ "$RC" -eq 0 ]; then
            case "$KIND" in
                check | branch-gate | preflight) strip "$LOG" | grep -qE "^$KIND: PASS" || nov=1 ;;
                file | static) strip "$LOG" | grep -qE '^warm: .*\|' || nov=1 ;;
            esac
        fi
        if [ "$nov" -eq 1 ]; then
            out+=("$KIND: NO VERDICT (rc=0, ${SECS}s) — the log lacks its own verdict line")
        else
            out+=("$KIND: $(verdict_word) in ${SECS}s${marker:+ — $(printf '%s' "$marker" | cut -c1-110)}")
        fi
        c="$(counts)"
        [ -n "$c" ] && out+=("$c")
        nfl="$(strip "$LOG" | grep -cE '^branch-gate: (test/|[a-z_/]+\.jl)' || true)"
        [ "$KIND" = branch-gate ] && [ "$nfl" -gt 0 ] && out+=("$nfl test file(s) run")
        f="$(fails)"
        if [ -n "$f" ]; then
            total=$(printf '%s\n' "$f" | grep -c .)
            out+=("failing ($total):")
            while IFS= read -r l; do out+=("  $l"); done < <(printf '%s\n' "$f" | head -"$MAXFAIL")
            [ "$total" -gt "$MAXFAIL" ] && out+=("  ... $((total - MAXFAIL)) more in the log")
        elif [ "$RC" -ne 0 ]; then
            out+=("failing: none recognised — last lines of the log:")
            while IFS= read -r l; do out+=("  $l"); done < <(strip "$LOG" | grep . | tail -2 | cut -c1-140)
        fi
        ;;
esac
out+=("log: $LOG")
# the 10-line cap: keep the first 9 and the log line
if [ "${#out[@]}" -gt 10 ]; then
    last="${out[$((${#out[@]} - 1))]}"
    out=("${out[@]:0:9}" "$last")
fi
printf '%s\n' "${out[@]}"
