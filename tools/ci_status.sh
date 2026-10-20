#!/usr/bin/env bash
# tools/ci_status.sh — the CI verdict on one commit of this repository: the gate split's condition
# (user, 2026-10-06): a chunk's gate stops while the previous push is red, so a defect the local
# gate defers to CI (the alternative term types) is fixed before anything builds on it.
#
#   tools/ci_status.sh [--require NAME] [SHA]
#                                     default: origin/main's commit, the last push; any commit name
#                                     (a short SHA, a branch) is resolved to the full SHA
#   --require NAME: a run of the workflow NAMED so must be among that commit's runs — the push gate
#   (tools/githooks/pre-push; user, 2026-10-13) asks for `Evidence (three term types)`: other green
#   runs of a commit the evidence workflow never ran on are NOT a verdict (exit 3).
#
# Exit status, the answer:
#   0  every workflow run of that commit completed and succeeded (the required one among them)
#   1  one completed and did not succeed (failure, cancelled, timed out, …): RED
#   3  no verdict yet: a run is queued or in progress, none has started, or the required one is
#      missing
#   2  unreadable: no origin/main, no network, an API error
# LOGICKERNEL_CI_FIXTURE=<file>: read that JSON instead of the API (test/test_gate_split.jl).
# The token, only when the API answers "Not Found" (a private repository): read with `git credential
# fill`, handed to curl on STDIN (`-K -`) — never in argv, shell history or output.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REQUIRE=""
if [ "${1:-}" = "--require" ]; then
    REQUIRE="${2:-}"
    [ -n "$REQUIRE" ] || { echo "ci_status: --require needs a workflow name"; exit 2; }
    shift 2
fi
SHA="${1:-}"
if [ -z "$SHA" ]; then
    SHA="$(git -C "$ROOT" rev-parse --verify --quiet origin/main)" || {
        echo "ci_status: no origin/main to read"
        exit 2
    }
fi
# THE FULL SHA, ALWAYS: the API's head_sha filter matches only a full one, so a short SHA read as
# "no run yet" (exit 3) whatever CI said — MEASURED 2026-10-07, `ci_status.sh b615e51` while its
# run was in progress. Resolve any commit name; keep a full SHA git does not have (an unfetched
# commit, the tests' fixtures); anything else is unreadable (exit 2), never a silent "no run".
if full="$(git -C "$ROOT" rev-parse --verify --quiet "$SHA^{commit}" 2>/dev/null)"; then
    SHA="$full"
elif ! printf '%s' "$SHA" | grep -qE '^[0-9a-f]{40}$'; then
    echo "ci_status: $SHA: not a commit this repository has, nor a full SHA"
    exit 2
fi
if [ -n "${LOGICKERNEL_CI_FIXTURE:-}" ]; then
    J="$(cat "$LOGICKERNEL_CI_FIXTURE")"
else
    slug="$(git -C "$ROOT" remote get-url origin 2>/dev/null | sed -E 's#^.*github\.com[:/]##; s#\.git$##')"
    API="https://api.github.com/repos/$slug/actions/runs?head_sha=$SHA&per_page=50"
    J="$(curl -s -m 25 "$API")"
    # the stored token whenever the anonymous answer is no run list — a private repo ("Not Found")
    # or the anonymous RATE LIMIT (60 an hour): MEASURED 2026-10-07, a CI poll every 30 s used it
    # up, every later preflight stopped at "unreadable", and tools/test_warm.sh's cases could not
    # reach the checks they test
    if ! printf '%s' "$J" | grep -q '"workflow_runs"'; then
        TOK="$(printf 'protocol=https\nhost=github.com\n\n' |
            git -c credential.useHttpPath=false credential fill 2>/dev/null | sed -n 's/^password=//p')"
        [ -n "$TOK" ] &&
            J="$(printf 'header = "Authorization: Bearer %s"\n' "$TOK" | curl -s -m 25 -K - "$API")"
        unset TOK
    fi
fi
printf '%s' "$J" | python3 -c '
import json, sys
sha, require = sys.argv[1], sys.argv[2]
try:
    allruns = json.load(sys.stdin)["workflow_runs"]
    runs = [r for r in allruns if r["head_sha"] == sha]
except Exception:
    print(f"ci_status: {sha[:7]}: the CI answer is unreadable")
    sys.exit(2)
if not runs:
    print(f"ci_status: {sha[:7]}: no CI run yet")
    sys.exit(3)
ok = ("success", "neutral", "skipped")
def wf(r):
    return r.get("workflow_id") or r["name"]
def superseded(r):
    # D-0071. A CANCELLED run is not a verdict when a LATER run with the SAME workflow, the SAME
    # head_sha and the SAME head_branch (ref) completed with `success` (MEASURED 2026-10-20: the
    # re-pushed tag v0.1.0-pre.1 cancelled the first tag push'"'"'s CI; the re-run was green). Searched
    # in ALL runs, so a later green commit on another sha never excuses it. Only `cancelled`:
    # failure, timed_out, startup_failure, action_required and stale stay red, and a run the API
    # gave no `created_at` is never superseded.
    if r["conclusion"] != "cancelled" or not r.get("created_at"):
        return False
    return any(
        o is not r and wf(o) == wf(r) and o["head_sha"] == r["head_sha"]
        and o.get("head_branch") == r.get("head_branch")
        and o["status"] == "completed" and o["conclusion"] == "success"
        and (o.get("created_at") or "") > r["created_at"]
        for o in allruns
    )
red = [r for r in runs if r["status"] == "completed" and r["conclusion"] not in ok and not superseded(r)]
pending = [r for r in runs if r["status"] != "completed"]
for r in runs:
    print("ci_status: %s  %s  %s  %s%s  %s" % (sha[:7], r["name"], r["status"], r["conclusion"] or "-", " (superseded)" if superseded(r) else "", r["html_url"]))
if red:
    sys.exit(1)
if pending:
    sys.exit(3)
if require and not any(r["name"] == require for r in runs):
    print("ci_status: %s: no run of the required workflow `%s`" % (sha[:7], require))
    sys.exit(3)
sys.exit(0)
' "$SHA" "$REQUIRE"
