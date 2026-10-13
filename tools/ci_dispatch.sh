#!/usr/bin/env bash
# ORIGINAL: starting a `workflow_dispatch` workflow of this repository — no swipl-devel counterpart.
# tools/ci_dispatch.sh — start one of this repository's hand-started workflows through the API: the
# mutation battery at a step's close (user, 2026-10-13: the battery runs ONCE per step, in CI).
#
#   tools/ci_dispatch.sh WORKFLOW REF [KEY=VALUE …]
#     WORKFLOW   the workflow's file name (mutation.yml)
#     REF        the branch whose tree runs (gate/ci-offload, main)
#     KEY=VALUE  the workflow's inputs
#   tools/ci_dispatch.sh mutation.yml gate/ci-offload mutants=tools/mutants/V9f.py \
#       "targets=test/core_lang/test_catch_swipl.jl test/core_lang/test_det_swipl.jl"
#
# Exit status: 0 the API accepted it (204: the run starts; tools/ci_status.sh shows it on the ref's
# commit); 1 it refused (the answer is printed); 2 a usage error or no token.
# The token: read with `git credential fill`, handed to curl on STDIN (`-K -`) — never in argv,
# shell history or output (as tools/ci_status.sh).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[ $# -ge 2 ] || { echo "usage: tools/ci_dispatch.sh WORKFLOW REF [KEY=VALUE …]" >&2; exit 2; }
WORKFLOW="$1"; REF="$2"; shift 2
printf '%s' "$WORKFLOW" | grep -qE '^[A-Za-z0-9_.-]+\.yml$' ||
    { echo "ci_dispatch: $WORKFLOW: not a workflow file name" >&2; exit 2; }
[ -f "$ROOT/.github/workflows/$WORKFLOW" ] ||
    { echo "ci_dispatch: .github/workflows/$WORKFLOW does not exist" >&2; exit 2; }
BODY="$(python3 -c '
import json, sys
ref, inputs = sys.argv[1], {}
for kv in sys.argv[2:]:
    k, sep, v = kv.partition("=")
    if not sep or not k:
        sys.exit("ci_dispatch: %r is not KEY=VALUE" % kv)
    inputs[k] = v
print(json.dumps({"ref": ref, "inputs": inputs}))
' "$REF" "$@")" || exit 2
slug="$(git -C "$ROOT" remote get-url origin 2>/dev/null | sed -E 's#^.*github\.com[:/]##; s#\.git$##; s#^[^/@]*@##')"
API="https://api.github.com/repos/$slug/actions/workflows/$WORKFLOW/dispatches"
TOK="$(printf 'protocol=https\nhost=github.com\n\n' |
    git -c credential.useHttpPath=false credential fill 2>/dev/null | sed -n 's/^password=//p')"
[ -n "$TOK" ] || { echo "ci_dispatch: no stored token for github.com" >&2; exit 2; }
OUT="$(printf 'header = "Authorization: Bearer %s"\n' "$TOK" |
    curl -s -m 25 -K - -X POST -H 'Accept: application/vnd.github+json' \
        -d "$BODY" -w '\n%{http_code}' "$API")"
unset TOK
code="$(printf '%s' "$OUT" | tail -n 1)"
if [ "$code" = 204 ]; then
    echo "ci_dispatch: $WORKFLOW started on $REF"
    exit 0
fi
echo "ci_dispatch: $WORKFLOW on $REF refused (HTTP $code)"
printf '%s\n' "$OUT" | sed '$d' | head -c 600
exit 1
