#!/usr/bin/env bash
# ORIGINAL: no swipl-devel counterpart — the mutation proof of tools/test_land_check.sh (audit D-0923 (4)(b): a guard that cannot fail
# is useless). Each mutant is one old/new pair applied to a COPY of tools/land_check.sh; `old` must occur EXACTLY once (the script stops
# if it does not); the test runs against the copy through LAND_CHECK_UNDER_TEST, fail-fast; a mutant the test does not fail on is a
# SURVIVOR and the script exits 1. The unmutated copy must pass first (else every "kill" would be a broken harness).
#   tools/mutate_land_check.sh            all mutants, sequentially (~90 s each in the worst case, a kill stops at the first FAIL row)
#   tools/mutate_land_check.sh M9 G1      only these
#   tools/mutate_land_check.sh --check    only verify that every `old` occurs exactly once; no test is run
# Prints one line per mutant (id, KILLED by <first failing row> | SURVIVED) and at the end `killed N of N`.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/land_check.sh"
TEST="$HERE/test_land_check.sh"
W="$(mktemp -d "${TMPDIR:-/tmp}/mutate_land_check.XXXXXX")"
trap 'rm -rf "$W"' EXIT

cat > "$W/mutants.py" << 'PY'
import sys
# (id, what the mutant breaks, old, new): `old` occurs exactly once in tools/land_check.sh
M = [
 ("M1", "input: upper-case hex accepted", "^[0-9a-f]{40}$", "^[0-9a-fA-F]{40}$"),
 ("M2", "ancestry: not-a-fast-forward accepted", 'if ! git merge-base --is-ancestor "$base" "$sha" 2> /dev/null; then', 'if false; then'),
 ("M3", "ancestry: nothing to land accepted", 'if [ "$n" -gt 0 ]; then', 'if [ "$n" -ge 0 ]; then'),
 ("M4", "author: the repo identity is not compared", 'elif [ "$idents" != "$LAND_IDENTITY" ]; then', 'elif false; then'),
 ("M5", "author: a second identity accepted", 'elif [ "$(printf \'%s\\n\' "$idents" | wc -l)" -ne 1 ]; then', 'elif false; then'),
 ("M6", "d0164: the added lines are not read", 'if [ -n "$dh$mh" ]; then', 'if [ -n "$mh" ]; then'),
 ("M7", "d0164: the commit messages are not read", 'if [ -n "$dh$mh" ]; then', 'if [ -n "$dh" ]; then'),
 ("M8", "decide: a FAIL row does not refuse", '[ "$st" = PASS ] || all=FAIL', '[ "$st" = PASS ] || :'),
 ("M8b", "decide: a missing row counts as PASS", 'st=FAIL; detail="no row was written (step did not run)"', 'st=PASS; detail="no row was written (step did not run)"'),
 ("M8c", "decide: a dry run exits 1", '[ "${LAND_DRY_RUN:-true}" = true ] && return 0', ':'),
 ("M9", "gateset: the SHRINK check never refuses", 'if [ -n "$shrink" ] && [ "${LAND_SET_MAY_SHRINK:-false}" != true ]; then', 'if false; then'),
 ("M9b", "gateset: the set_may_shrink input is ignored (a shrink is never allowed)", '[ "${LAND_SET_MAY_SHRINK:-false}" != true ]', '[ "${LAND_SET_MAY_SHRINK:-false}" != never ]'),
 ("M9c", "gateset: the shrink is computed against nothing", 'printf \'%s\\n\' "$cand" | grep -qx "$name" || shrink="$shrink $name"', 'printf \'%s\\n\' "$cand" | grep -qx "$name" || :'),
 ("M9d", "gateset: no battery named is accepted", 'if [ -z "$cand" ]; then row gateset FAIL "the gate set names no battery"; return 0; fi', ':'),
 ("M10", "gateset: any failure is turned into PASS", 'if [ -n "$fails" ]; then row gateset FAIL "$fails"; return 0; fi', ':'),
 ("G1", "gate-tip: ANY gate branch tip counts as the SHA's (a SHA inside or on a wip branch passes)", '[ "$tip" = "$sha" ] && br="$br ${ref#refs/heads/}"', '[ -n "$tip" ] && br="$br ${ref#refs/heads/}"'),
 ("G2", "gate-tip: the row is PASS whatever the branches say", 'if [ -z "$br" ]; then', 'if false; then'),
 ("G3", "gate-tip: every branch counts, not only gate/*", 'LAND_BRANCH_GLOB="${LAND_BRANCH_GLOB:-refs/heads/gate/*}"', 'LAND_BRANCH_GLOB="${LAND_BRANCH_GLOB:-refs/heads/*}"'),
 ("V1", "verdicts: the reader's exit code is not read", 'ok = rc == 0 and r.get("landable") is True and bool(bats)', 'ok = r.get("landable") is True and bool(bats)'),
 ("V2", "verdicts: no battery read passes", 'ok = rc == 0 and r.get("landable") is True and bool(bats)', 'ok = rc == 0 and r.get("landable") is True'),
 ("V3", "verdicts: landable is not read", 'ok = rc == 0 and r.get("landable") is True and bool(bats)', 'ok = rc == 0 and bool(bats)'),
 ("K1", "marker: the state is not read", 'if s.get("state") != "success":', 'if False:'),
 ("K2", "marker: the description may name another SHA", 'or m.group(1) != sha:', 'or False:'),
 ("K3", "marker: the creator is not checked against the approvers", 'elif who not in allowed:', 'elif False:'),
 ("K4", "marker: the up-front refusal of an empty approver list is gone (defense in depth: the later approver match still refuses; killed by the message)", 'if [ ! -s "$ap" ] || ! grep -qvE \'^[[:space:]]*(#|$)\' "$ap"; then', 'if false; then'),
 ("P1", "push: the marker is not required", 'for name in input gate-tip ancestry linear author d0164 gateset marker; do', 'for name in input gate-tip ancestry author d0164 gateset; do'),
 ("P2", "push: the gate set (shrink, added rows) is not required", 'for name in input gate-tip ancestry linear author d0164 gateset marker; do', 'for name in input gate-tip ancestry author d0164 marker; do'),
 ("P3", "push: the git conditions are not required", 'for name in input gate-tip ancestry linear author d0164 gateset marker; do', 'for name in input marker; do'),
 ("A1", "rows: the added-row detection is dropped", 'added = [c[k] for k in c if k not in r]', 'added = []'),
 ("A2", "rows: the reference copy is read from the SHA, not from main", 'git show "$LAND_BASE:evidence/$f" > "$ref/$f" 2> /dev/null ||', 'git show "$sha:evidence/$f" > "$ref/$f" 2> /dev/null ||'),
 ("A3", "rows: any d_entry text counts as an id", 'DID = re.compile(r"^D-[0-9]{4}$")', 'DID = re.compile(r"^.*$")'),
 ("A3b", "rows: an empty d_entry counts as an id", 'DID = re.compile(r"^D-[0-9]{4}$")', 'DID = re.compile(r"^.*$|^$")'),
 ("A4", "rows: a survivors row accepted as equivalent needs no id", 'if f[3] == "accepted equivalent":', 'if False:'),
 ("A5", "rows: the survivors ledger churn (first_seen/last_seen) counts as added", 'cs = {tuple(f[:5]) for f in load(cansv, "battery")}', 'cs = {tuple(f[:7]) for f in load(cansv, "battery")}'),
 ("A6", "rows: removed equivalents rows are not printed", '    out.append("- equivalents.tsv  mutant %s  d_entry %s  %s" % (f[0], f[1], f[2]))', '    pass'),
 ("A7", "rows: the table does not print the row diff", 'if [ -f "$LAND_WORK/rowdiff.txt" ]; then cat "$LAND_WORK/rowdiff.txt";', 'if false; then cat "$LAND_WORK/rowdiff.txt";'),
 ("A8", "rows: added survivors rows are not printed", '    out.append("+ survivors.tsv  battery', '    (lambda *a: None)("+ survivors.tsv  battery'),
 ("A9", "rows: an added equivalents row with no mutant name passes", '    if not f[0]:\n        fails.append("an added equivalents row names no mutant")\n    elif not DID.match(f[1]):', '    if False:\n        pass\n    elif not DID.match(f[1]):'),
 ("N1", "marker: rows added but not named still pass", 'if uncovered:', 'if False:'),
 ("N2", "marker: ids named that the commit does not add still pass", 'elif unused:', 'elif False:'),
 ("N3", "marker: a bare D-id does not cover its rows", 'uncovered = sorted(t for t in required if t not in named and t.split(":")[0] not in named)', 'uncovered = sorted(t for t in required if t not in named)'),
 ("N4", "marker: a missing record of the added rows is read as no rows", 'print("FAIL\\tno record of the added equivalents rows (the gateset step did not run): fail closed"); sys.exit(0)', 'required = set()'),
 ("N5", "marker: a bare D-id with no added row is not an unused id", 'unused = sorted(t for t in named if t not in required and not any(r.split(":")[0] == t for r in required))', 'unused = sorted(t for t in named if t not in required and ":" in t)'),
 ("L1", "linear: a merge commit in the range is accepted", 'elif [ -n "$ml" ]; then', 'elif false; then'),
 ("L2", "linear: the --merges flag is dropped (every range lists its commits)", "git log --merges --format='%H %s' \"$base..$sha\"", "git log --format='%H %s' \"$base..$sha\""),
 ("L3", "linear: the verdict is inverted (a linear range fails, a merge passes)", 'elif [ -n "$ml" ]; then', 'elif [ -z "$ml" ]; then'),
 ("L4", "linear: an unreadable range passes", 'row linear FAIL "the range $LAND_BASE..SHA could not be read"', 'row linear PASS "the range $LAND_BASE..SHA could not be read"'),
 ("L5", "push: the linear row is not required on the fresh state", 'for name in input gate-tip ancestry linear author d0164 gateset marker; do', 'for name in input gate-tip ancestry author d0164 gateset marker; do'),
 ("L6", "decide: the linear row is not one of the required rows", 'REQUIRED_ROWS="input gate-tip ancestry linear author', 'REQUIRED_ROWS="input gate-tip ancestry author'),
 ("L7", "linear: the base is dropped from the range (main's own history is read)", "git log --merges --format='%H %s' \"$base..$sha\"", "git log --merges --format='%H %s' \"$sha\""),
 ("L8", "linear: only the tip commit is read, not the range", "git log --merges --format='%H %s' \"$base..$sha\"", "git log --merges --format='%H %s' \"$sha^!\""),
 ("L9", "linear: an unresolved base passes", 'row ancestry FAIL "base unresolved"; row linear FAIL "base unresolved"', 'row ancestry FAIL "base unresolved"; row linear PASS "base unresolved"'),
 ("L10", "linear: a commit that is not in the clone passes", 'row linear FAIL "commit not in the clone"', 'row linear PASS "commit not in the clone"'),
 ("L11", "linear: the exit status of the range read is not read as a failure (inverted)", 'if ! ml="$(git log --merges', 'if ml="$(git log --merges'),
 ("L12", "linear: the FAIL does not name the merge commit", 'first: $(printf \'%s\\n\' "$ml" | head -1 | cut -c1-120)', 'first: (not named)'),
 ("L13", "linear: the FAIL does not cite the rule", '; main takes only linear history (A-0206)"', '"'),
]
if __name__ == "__main__":
    cmd = sys.argv[1]
    if cmd == "ids":
        print("\n".join(m[0] for m in M))
    elif cmd == "what":
        print([m[1] for m in M if m[0] == sys.argv[2]][0])
    elif cmd in ("apply", "check"):
        src = open(sys.argv[2]).read()
        bad = 0
        for i, what, old, new in M:
            if cmd == "check" or i == sys.argv[3]:
                n = src.count(old)
                if n != 1:
                    print("mutant %s: `old` occurs %d times, not once" % (i, n), file=sys.stderr); bad += 1
                elif cmd == "apply":
                    open(sys.argv[4], "w").write(src.replace(old, new)); break
        else:
            if cmd == "apply":
                print("no mutant %s" % sys.argv[3], file=sys.stderr); bad += 1
        sys.exit(1 if bad else 0)
PY

if ! python3 -I "$W/mutants.py" check "$SRC"; then echo "mutate_land_check: a mutant does not apply (see above)"; exit 2; fi
if [ "${1:-}" = "--check" ]; then echo "every mutant's old text occurs exactly once: $(python3 -I "$W/mutants.py" ids | wc -l) mutants"; exit 0; fi

if [ "$#" -gt 0 ]; then ids="$*"; else ids="$(python3 -I "$W/mutants.py" ids)"; fi

# the unmutated copy first: through the same seam, it must pass
cp "$SRC" "$W/land_check.base.sh"
if ! LAND_CHECK_UNDER_TEST="$W/land_check.base.sh" bash "$TEST" > "$W/base.log" 2>&1; then
    echo "mutate_land_check: the UNMUTATED copy fails the test; no mutant result means anything"; grep '^  FAIL' "$W/base.log" | head -5; exit 2
fi
echo "baseline: unmutated copy passes ($(tail -1 "$W/base.log"))"

killed=0 total=0
for id in $ids; do
    total=$((total + 1))
    if ! python3 -I "$W/mutants.py" apply "$SRC" "$id" "$W/m.sh"; then echo "$id: DOES NOT APPLY"; continue; fi
    cmp -s "$SRC" "$W/m.sh" && { echo "$id: NO CHANGE"; continue; }
    bash -n "$W/m.sh" || { echo "$id: the mutant is not valid bash"; continue; }
    LAND_TEST_FAILFAST=1 LAND_CHECK_UNDER_TEST="$W/m.sh" bash "$TEST" > "$W/m.log" 2>&1
    rc=$?
    if [ "$rc" -ne 0 ] && grep -q '^  FAIL' "$W/m.log"; then
        killed=$((killed + 1))
        echo "$id: KILLED by [$(grep -m1 '^  FAIL' "$W/m.log" | cut -c8-110)]  ($(python3 -I "$W/mutants.py" what "$id"))"
    elif [ "$rc" -ne 0 ]; then
        echo "$id: test exited $rc with no FAIL row (harness error, NOT a kill): $(tail -2 "$W/m.log" | tr '\n' ' ')"
    else
        echo "$id: SURVIVED ($(python3 -I "$W/mutants.py" what "$id"))"
    fi
done
echo "killed $killed of $total"
[ "$killed" = "$total" ]
