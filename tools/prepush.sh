#!/usr/bin/env bash
# ORIGINAL: no swipl-devel counterpart — the PRE-PUSH BUNDLE of a gate (audit D-0327 item 3): the order of
# evidence/GATE-PLAYBOOK.md, run in one go, stopping at the FIRST failure and naming it.
#
#   tools/prepush.sh <STEP>
#
#   0  the warm daemon of THIS checkout is up (else: fails loudly, exit 3, nothing run) and the tree is
#      clean (every change committed: the diff and the messages checked below are the commits')
#   1  inventory   tools/warm.sh inventory; docs/port_inventory.md & co. must not change (else commit them)
#   2  fmt         tools/warm.sh fmt; no tracked file may change (else commit the formatting)
#   3  check       tools/warm.sh check
#   4  static      tools/warm.sh file test/static_analysis_fast.jl (Aqua + JET report_package, ~170 s)
#   5  stale pins  the playbook's grep over test/ (KNOWN DIFFERENCE, interim, until R2, ...): the hits that
#                  name a name/arity the diff adds to src/ are listed — READ them (information, not a stop)
#   6  D-0164 terms the D-0164 grep over the added lines of `git diff origin/main..HEAD` and over the commit
#                  messages of origin/main..HEAD
#   7  secret scan the pinned gitleaks (tools/secret_scan.sh, audit D-0340) over the patches of origin/main..HEAD
#                  (the diff against the merge base); a finding STOPS the push and is reported (redacted), and is
#                  NEVER allowlisted or ignored by the agent. The binary is checked at step 0, before any long step.
# Then it prints the next command (rename to gate/<STEP>, `git ls-remote` empty first, push for CI).
# It never creates, touches or deletes a gate marker, never passes --no-verify, never pushes, never
# edits a file itself (only the warm.sh steps it names do), and reads no environment value.
# Exit status: 0 all passed; 1 the first failed step (named on the "prepush: FAILED at <step>" line);
# 3 the warm lane is not up, or the pinned gitleaks is not installed (tools/install_gitleaks.sh); 64 usage.
# Seams for tools/test_ci_tools.sh: LOGICKERNEL_PREPUSH_WARM=<program> stands for tools/warm.sh,
# LOGICKERNEL_PREPUSH_REPO=<dir> for the repository root, LOGICKERNEL_PREPUSH_SECRETS=<program> for
# tools/secret_scan.sh.
set -u
ROOT="${LOGICKERNEL_PREPUSH_REPO:-$(cd "$(dirname "$0")/.." && pwd)}"
WARM="${LOGICKERNEL_PREPUSH_WARM:-$ROOT/tools/warm.sh}"
SECRETS="${LOGICKERNEL_PREPUSH_SECRETS:-$(cd "$(dirname "$0")" && pwd)/secret_scan.sh}"
STEP="${1:-}"
case "$STEP" in '' | *[!A-Za-z0-9._-]*) echo "usage: tools/prepush.sh <STEP>" >&2; exit 64 ;; esac
cd "$ROOT" || exit 64
BASE="origin/main"
# the terms of D-0164, assembled from pieces so this file does not match its own grep
TERMS164='seg''ment|SIG''SEGV|cra''sh|abo''rt|invalid term''_t|dies ''of'

fail() {   # fail STEP DETAIL...
    local s="$1"
    shift
    echo "prepush: FAILED at $s"
    printf '%s\n' "$@"
    exit 1
}
step() { echo "prepush: [$1] $2"; }

# --- 0: the lane and the tree -------------------------------------------------------------------
if ! "$WARM" status > /dev/null 2>&1; then
    echo "prepush: the warm lane of this checkout is NOT up; nothing was run."
    echo "  start it:  LOGICKERNEL_WARM_SECOND=1 tools/warm.sh start   (run it as its own background command)"
    exit 3
fi
if ! sc="$("$SECRETS" --check 2>&1)"; then
    echo "prepush: the secret scanner is not ready; nothing was run."
    printf '  %s\n' "$sc"
    exit 3
fi
git rev-parse --verify --quiet "$BASE" > /dev/null || fail "0 setup" "no $BASE to compare with (git fetch origin)"
dirty="$(git status --porcelain --untracked-files=no)"
[ -z "$dirty" ] || fail "0 clean tree" "uncommitted changes (commit them first; this bundle checks the commits):" "$dirty"
untracked="$(git ls-files --others --exclude-standard)"
[ -z "$untracked" ] || fail "0 clean tree" "untracked files (commit or remove them; a partial index is refused by the hooks):" "$untracked"
L="$(mktemp -d "${TMPDIR:-/tmp}/prepush.XXXXXX")"
trap 'rm -rf "$L"' EXIT

run() {   # run LABEL CMD... — output kept in $L/LABEL.log, its tail shown on failure
    local label="$1"
    shift
    "$@" > "$L/$label.log" 2>&1
    local rc=$?
    if [ "$rc" -ne 0 ]; then
        fail "$label" "$* exited $rc; last lines:" "$(tail -n 12 "$L/$label.log")"
    fi
}
changed_after() {   # changed_after STEP — a warm.sh step must leave the committed tree as it found it
    local c
    c="$(git status --porcelain --untracked-files=no)"
    [ -z "$c" ] || fail "$1" "this step rewrote tracked files; commit them (stage explicit paths) and run again:" "$c"
}

# --- 1..4 -----------------------------------------------------------------------------------------
step 1 "inventory"
run inventory "$WARM" inventory
changed_after inventory
step 2 "fmt"
run fmt "$WARM" fmt
changed_after fmt
step 3 "check"
run check "$WARM" check
step 4 "fast static pre-check (Aqua + JET report_package)"
run static "$WARM" file test/static_analysis_fast.jl

# --- 5: the stale-pin grep ----------------------------------------------------------------------
step 5 "stale-pin hunt over test/"
grep -rnE 'KNOWN DIFFERENCE|interim|until R2|not ported|existence_error' test/ > "$L/pins.txt" 2> /dev/null
total="$(grep -c . "$L/pins.txt")"
git diff "$BASE..HEAD" -- src | grep -E '^\+[^+]' | grep -oE '[a-z][A-Za-z0-9_]*/[0-9]+' | sort -u > "$L/names.txt"
nn="$(grep -c . "$L/names.txt")"
if [ "$nn" -gt 0 ]; then
    grep -F -f "$L/names.txt" "$L/pins.txt" > "$L/pins_named.txt" 2> /dev/null || : > "$L/pins_named.txt"
else
    : > "$L/pins_named.txt"
fi
named="$(grep -c . "$L/pins_named.txt")"
echo "  $total pin/interim hit(s) in test/; $nn name/arity token(s) in the diff's added src lines; $named hit(s) name one:"
head -n 30 "$L/pins_named.txt" | cut -c1-200 | sed 's/^/    /'
[ "$named" -le 30 ] || echo "    ... $((named - 30)) more (grep -F the names of $L/names.txt)"
[ "$nn" -gt 0 ] || echo "  (no name/arity in the added src lines: read the hits yourself: grep -rnE 'KNOWN DIFFERENCE|interim|until R2|not ported|existence_error' test/)"

# --- 6: the D-0164 terms -------------------------------------------------------------------------
step 6 "D-0164 term grep (diff $BASE..HEAD and the commit messages)"
git diff "$BASE..HEAD" | grep -E '^\+[^+]' | grep -iE "$TERMS164" > "$L/d0164_diff.txt"
git log "$BASE..HEAD" --format='%H %B' | grep -iE "$TERMS164" > "$L/d0164_msg.txt"
if [ -s "$L/d0164_diff.txt" ] || [ -s "$L/d0164_msg.txt" ]; then
    fail "D-0164 term grep" "D-0164: no upstream failure details in public text; reword:" \
        "$(cut -c1-200 "$L/d0164_diff.txt" | head -n 8)" "$(cut -c1-200 "$L/d0164_msg.txt" | head -n 4)"
fi

# --- 7: the secret scan --------------------------------------------------------------------------
step 7 "secret scan (gitleaks, the patches of $BASE..HEAD)"
LOGICKERNEL_SECRET_SCAN_REPO="$ROOT" "$SECRETS" "$BASE..HEAD" > "$L/secrets.txt" 2>&1
src=$?
[ "$src" -eq 0 ] || fail "secret scan" "tools/secret_scan.sh exited $src: STOP and report it (do NOT allowlist or ignore a finding):" "$(head -n 40 "$L/secrets.txt" | cut -c1-200)"
echo "  $(tail -n 1 "$L/secrets.txt")"

echo "prepush: ALL PASSED for $STEP at $(git rev-parse --short HEAD) ($(git rev-list --count "$BASE..HEAD") commit(s) over $BASE)"
echo "next: git ls-remote origin refs/heads/gate/$STEP   # must print nothing"
echo "      git branch -m \"\$(git branch --show-current)\" gate/$STEP && git push -u origin gate/$STEP   # bare push, never force"
echo "      (then: tools/warm.sh branch-gate, and ONE capped tools/ci_wait.sh <full sha> in the background)"
