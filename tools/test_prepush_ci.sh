#!/usr/bin/env bash
# ORIGINAL: no swipl-devel counterpart — the guard rows of the pre-push hook's `ci/<name>` allowance (audit
# D-0636 item 1, Shivaji D-0637, 2026-11-13): rule 4b (a wip/ branch may push to refs/heads/ci/<name> and
# nowhere else) and rule 7 (a ci/ push runs the D-0164 term grep over `git diff refs/remotes/<remote>/main..<sha>`
# and the commit messages of that range; a delete is allowed; no coverage-zero pre-check, no mutants-file rule;
# the `main` arm unchanged). FAKE repositories (git init in a temp dir, a fake `origin/main` ref), the hook
# run with git's own stdin line `<local ref> <local sha> <remote ref> <remote sha>`; each case is judged by the
# EXIT CODE and, for a refusal, by the text that names the refusal — both directions: the same commit passes to
# ci/ and is refused to gate/, main and mutants/; the same push passes clean and is refused with a term in an
# added line, and again with the term only in a commit message. Every case has a non-empty diff, so a guard can
# pass (the ci/ rows), can fail (the refusals) and compares the right thing.
#
# THE HOOK UNDER TEST. Order: LOGICKERNEL_PREPUSH_CI_HOOK=<file> (a seam: tools/mutate.sh and the proof that the
# unpatched hook fails the ci/ rows); else this checkout's tools/githooks/pre-push when it already carries the
# ci/ arm; else a COPY of it with the patch applied, the patch from LOGICKERNEL_PREPUSH_CI_PATCH or
# tools/prepush_ci_refs.patch. Neither → exit 3 (nothing was tested).
# Exit 0 only if every case passes.
set -uo pipefail
REAL="$(cd "$(dirname "$0")/.." && pwd)"
W="$(mktemp -d "${TMPDIR:-/tmp}/ppci.XXXXXX")"
trap 'rm -rf "$W"' EXIT
NOREPLY="11524260+sivaji1012@users.noreply.github.com"
ZERO="$(printf '0%.0s' $(seq 1 40))"
# a D-0164 term, assembled from pieces so this file does not match the grep it tests
TERM_='cra''sh'
pass=0 fail=0

# --- the hook under test ----------------------------------------------------------------------------------
HOOK="${LOGICKERNEL_PREPUSH_CI_HOOK:-}"
if [ -z "$HOOK" ]; then
    if grep -q 'refs/heads/ci/' "$REAL/tools/githooks/pre-push"; then
        HOOK="$REAL/tools/githooks/pre-push"
    else
        PATCH="${LOGICKERNEL_PREPUSH_CI_PATCH:-$REAL/tools/prepush_ci_refs.patch}"
        [ -f "$PATCH" ] || { echo "test_prepush_ci: the hook has no ci/ arm and there is no patch ($PATCH): nothing was tested"; exit 3; }
        mkdir -p "$W/patched/tools/githooks"
        cp "$REAL/tools/githooks/pre-push" "$W/patched/tools/githooks/pre-push"
        (cd "$W/patched" && git init -q && git apply "$PATCH") || { echo "test_prepush_ci: $PATCH does not apply to tools/githooks/pre-push"; exit 3; }
        HOOK="$W/patched/tools/githooks/pre-push"
        echo "test_prepush_ci: WARNING the hook of this checkout is NOT patched yet: the rows run against a patched COPY (apply the patch, then delete it: git apply $PATCH)"
    fi
fi
[ -f "$HOOK" ] || { echo "test_prepush_ci: no hook at $HOOK"; exit 3; }
echo "test_prepush_ci: hook under test: $HOOK"

# mk NAME — a fake repo at $W/NAME: origin/main = a base commit; branch wip/x one commit further (a clean file);
# a local branch gate/x at the same commit. Prints nothing; the SHAs are read with `sha`.
mk() {
    local d="$W/$1"
    mkdir -p "$d/tools/githooks"
    (
        cd "$d" || exit 1
        git init -q -b main . && git config user.name t && git config user.email "$NOREPLY"
        git remote add origin https://x.invalid/r.git
        printf 'f() = 1\n' > a.jl
        cp "$HOOK" tools/githooks/pre-push
        cp "$REAL/tools/githooks/dterm.sh" tools/githooks/dterm.sh      # the hook sources it (the ONE D-0164 definition)
        cp "$REAL/tools/ci_status.sh" tools/ci_status.sh
        git add -A && git commit -q -m base
        git update-ref refs/remotes/origin/main HEAD
        git checkout -q -b wip/x
        printf 'g() = 2\n' > b.jl
        git add -A && git commit -q -m "a clean step"
        git branch gate/x
    )
}
sha() { git -C "$W/$1" rev-parse "${2:-HEAD}"; }
# add_commit NAME FILE-TEXT MESSAGE — one more commit on the current branch of fake repo NAME
add_commit() {
    (cd "$W/$1" && printf '%s\n' "$2" > c.jl && git add -A && git commit -q -m "$3")
}

# push NAME LOCAL_REF LOCAL_SHA REMOTE_REF [ENV...] — the hook's exit status in $rc, its stderr in $out
push() {
    local repo="$W/$1" lref="$2" lsha="$3" rref="$4"
    shift 4
    out="$(printf '%s %s %s %s\n' "$lref" "$lsha" "$rref" "$ZERO" | (cd "$repo" && env -u LOGICKERNEL_PUSH_LOCAL_EVIDENCE -u LOGICKERNEL_CI_FIXTURE "$@" bash tools/githooks/pre-push origin https://x.invalid/r.git) 2>&1)"
    rc=$?
}
# case LABEL WANT_RC NAMED — judge the last push: the exit code, and for a refusal the text it must contain
check() {
    local label="$1" want="$2" named="${3:-}" ok=1
    [ "$rc" = "$want" ] || ok=0
    if [ "$want" = 1 ] && [ -n "$named" ]; then printf '%s' "$out" | grep -qF -- "$named" || ok=0; fi
    if [ "$ok" = 1 ]; then pass=$((pass + 1)); echo "  ok   $label (exit $rc)"
    else fail=$((fail + 1)); echo "  FAIL $label: exit $rc, want $want, named '$named'"; printf '%s\n' "$out" | sed 's/^/       /'; fi
}

mk r1
S="$(sha r1)"
L="refs/heads/wip/x"

# 1. THE ONE MAPPING: wip/ -> ci/<name> passes; every other wip/ target is refused, the same commit throughout
push r1 "$L" "$S" refs/heads/ci/x;        check "wip -> ci/x passes" 0
push r1 "$L" "$S" refs/heads/gate/x;      check "wip -> gate/x refused" 1 "a wip/ branch holds commits"
push r1 "$L" "$S" refs/heads/main;        check "wip -> main refused" 1 "a wip/ branch holds commits"
push r1 "$L" "$S" refs/heads/mutants/X;   check "wip -> mutants/X refused" 1 "a wip/ branch holds commits"
push r1 "$L" "$S" refs/heads/wip/y;       check "wip -> wip/y refused" 1 "a wip/ branch holds commits"
push r1 "$L" "$S" refs/heads/ci/;         check "wip -> ci/ (no name) refused" 1 "pushes only to refs/heads/ci/<name>"
push r1 "$L" "$S" refs/heads/cix;         check "wip -> cix (a name that only begins like ci) refused" 1 "a wip/ branch holds commits"
push r1 refs/heads/ci/x "$S" refs/heads/wip/y; check "ci/x -> wip/y refused (the remote side is wip/)" 1 "a wip/ branch holds commits"

# 2. a non-wip local ref may also push to ci/ ("any local ref"); the other targets keep their own rules
push r1 refs/heads/gate/x "$S" refs/heads/ci/x; check "gate/x -> ci/x passes" 0
push r1 refs/heads/gate/x "$S" refs/heads/gate/x; check "gate/x -> gate/x is still the coverage-zero pre-check's (no script here: refused)" 1 "coverage-zero"

# 3. a delete of a ci/ ref is allowed
push r1 "(delete)" "$ZERO" refs/heads/ci/x; check "delete ci/x allowed" 0
push r1 "(delete)" "$ZERO" refs/heads/wip/x; check "delete wip/x still refused" 1 "a wip/ branch holds commits"
push r1 "(delete)" "$ZERO" refs/heads/main; check "delete main still refused" 1 "deleting main"

# 4. the D-0164 term grep of a ci/ push: an added line, then a commit message, then both clean again
mk r2
add_commit r2 "the run hit a $TERM_ here" "a clean subject"
S2="$(sha r2)"
push r2 "$L" "$S2" refs/heads/ci/x;       check "ci/ push with a D-0164 term in an added line refused" 1 "D-0164"
printf '%s' "$out" | grep -qF -- "$TERM_" && { pass=$((pass + 1)); echo "  ok   the refusal prints the offending line"; } || { fail=$((fail + 1)); echo "  FAIL the refusal does not print the offending line"; }
push r2 refs/heads/gate/x "$S2" refs/heads/ci/x; check "(same, from a non-wip local ref) refused" 1 "D-0164"
mk r3
add_commit r3 "h() = 3" "the $TERM_ of a step"
S3="$(sha r3)"
push r3 "$L" "$S3" refs/heads/ci/x;       check "ci/ push with a D-0164 term only in a commit message refused" 1 "D-0164"
mk r4
add_commit r4 "h() = 3" "a clean second step"
S4="$(sha r4)"
push r4 "$L" "$S4" refs/heads/ci/x;       check "ci/ push, two clean commits, passes" 0
# the term is in the diff of a commit that is NOT on the remote's main but removed again in the pushed tree: the grep
# reads the tree diff main..sha (the playbook's), so it passes — pins which range is read
mk r5
add_commit r5 "the run hit a $TERM_ here" "temporary"
(cd "$W/r5" && git rm -q c.jl && git commit -q -m "drop it")
S5="$(sha r5)"
push r5 "$L" "$S5" refs/heads/ci/x;       check "a term added and removed again: the message range is clean, the tree diff is clean" 0
# a push to a branch that is not ci/ is not this arm's: the same term-carrying commit is not refused by 7. on gate/ (6. is another test's)
push r2 refs/heads/gate/x "$S2" refs/heads/gate/x; check "a D-0164 term is not rule 7's business on gate/ (refused only by the missing pre-check script)" 1 "coverage-zero"

# 4b. the exact-token allowlist of tools/githooks/dterm.sh (audit D-0650): an upstream identifier passes, in an added
# line and in a commit message; a strong term beside it, or in capitals, still refuses. The tokens come from the
# shared definition itself (the hook sources the same file), so this file holds no literal of them.
AL0="$(. "$REAL/tools/githooks/dterm.sh"; printf '%s' "${D0164_ALLOW[0]}")"
AL7="$(. "$REAL/tools/githooks/dterm.sh"; printf '%s' "${D0164_ALLOW[7]}")"
mk r7
add_commit r7 "see $AL0 and call $AL7" "a step on $AL7"
S7="$(sha r7)"
push r7 "$L" "$S7" refs/heads/ci/x;       check "ci/ push, allowlisted identifiers in the added line and in the message, passes" 0
mk r8
add_commit r8 "see $AL0 and the $TERM_" "a clean subject"
S8="$(sha r8)"
push r8 "$L" "$S8" refs/heads/ci/x;       check "ci/ push, a term next to an allowlisted identifier in an added line, refused" 1 "D-0164"
mk r9
add_commit r9 "h() = 3" "a step on $AL7 that ${TERM_}ed"
S9="$(sha r9)"
push r9 "$L" "$S9" refs/heads/ci/x;       check "ci/ push, a term next to an allowlisted identifier in the message, refused" 1 "D-0164"
mk r10
add_commit r10 "the run hit a ${TERM_^^} here" "a clean subject"
S10="$(sha r10)"
push r10 "$L" "$S10" refs/heads/ci/x;     check "ci/ push, the term in capitals, refused (the match is -i)" 1 "D-0164"
mk r11
add_commit r11 "h() = 3" "a clean subject"
rm -f "$W/r11/tools/githooks/dterm.sh"
S11="$(sha r11)"
push r11 "$L" "$S11" refs/heads/ci/x;     check "ci/ push without tools/githooks/dterm.sh is refused (fails closed)" 1 "dterm.sh"

# 5. fails closed: no refs/remotes/origin/main to diff against
mk r6
git -C "$W/r6" update-ref -d refs/remotes/origin/main
S6="$(sha r6)"
push r6 "$L" "$S6" refs/heads/ci/x;       check "ci/ push without origin/main is refused (unreadable range)" 1 "cannot"

# 6. no coverage-zero pre-check and no mutants-file rule on ci/: the fake repo has neither the script nor a list
[ ! -e "$W/r1/tools/check_coverage_zero.sh" ] && [ ! -e "$W/r1/tools/mutants" ] && { pass=$((pass + 1)); echo "  ok   the fake repo has no coverage-zero script and no mutants list (row 1's pass proves neither is required)"; } || { fail=$((fail + 1)); echo "  FAIL the fixture grew a coverage-zero script or a mutants list"; }
push r1 "$L" "$S" refs/heads/mutants/ci;   check "(and a mutants/ name that spells ci is still not a ci/ ref)" 1 "a wip/ branch holds commits"

# 7. the main arm is UNCHANGED: a green Evidence run moves main, an empty answer and a red one do not (planted)
ev="Evidence (three term types)"
fx="$W/fx.json"
runj() { printf '{"head_sha":"%s","name":"%s","status":"%s","conclusion":%s,"html_url":"https://x/1"}' "$1" "$2" "$3" "$4"; }
printf '{"workflow_runs":[%s,%s]}' "$(runj "$S" CI completed '"success"')" "$(runj "$S" "$ev" completed '"success"')" > "$fx"
push r1 refs/heads/gate/x "$S" refs/heads/main LOGICKERNEL_CI_FIXTURE="$fx"; check "main <- a commit with a green Evidence run passes" 0
printf '{"workflow_runs":[]}' > "$fx"
push r1 refs/heads/gate/x "$S" refs/heads/main LOGICKERNEL_CI_FIXTURE="$fx"; check "main <- a commit with no run refused" 1 "REFUSED"
printf '{"workflow_runs":[%s]}' "$(runj "$S" "$ev" completed '"failure"')" > "$fx"
push r1 refs/heads/gate/x "$S" refs/heads/main LOGICKERNEL_CI_FIXTURE="$fx"; check "main <- a commit with a red Evidence run refused" 1 "RED"
push r1 refs/heads/ci/x "$S" refs/heads/main LOGICKERNEL_CI_FIXTURE="$fx"; check "main <- from a ci/ local ref, the same red run refused" 1 "RED"

echo "test_prepush_ci: $pass passed, $fail failed"
[ "$fail" = 0 ]
