#!/usr/bin/env bash
# ORIGINAL: no swipl-devel counterpart — the rows of tools/land_check.sh and the structure of .github/workflows/land.yml
# (audit D-0912, D-0922 (3)(a)). No network, no Julia, seconds: a temporary origin (bare repository) and clone, a FAKE `gh` and a
# FAKE verdict reader (LAND_VERDICT_READ) on PATH/env, fixture SHAs. Every FAIL row has a row that proves the PASS arm beside it.
#   tools/test_land_check.sh        exit 0 only if every row passes; nothing outside a temp dir is touched.
# Environment: LAND_CHECK_UNDER_TEST = the land_check.sh to test (default: the one beside this file); tools/mutate_land_check.sh
# points it at a mutated COPY. LAND_TEST_FAILFAST=1 ends the run at the first FAIL row (the mutation script's use).
# The D-0164 terms below are assembled from pieces ('cra''sh') so that this file does not match the grep.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
UNDER="${LAND_CHECK_UNDER_TEST:-$HERE/land_check.sh}"
T="$(mktemp -d "${TMPDIR:-/tmp}/test_land_check.XXXXXX")"
trap 'rm -rf "$T"' EXIT
pass=0 fail=0
ok() { pass=$((pass + 1)); echo "  ok   $1"; }
bad() {
    fail=$((fail + 1)); echo "  FAIL $1"; shift; printf '       %s\n' "$@"
    if [ "${LAND_TEST_FAILFAST:-0}" = 1 ]; then echo "test_land_check: first FAIL row, stopping (fail-fast)"; exit 1; fi
}
CRA='cra''sh'
ID_NAME='Shivaji Gadde'
ID_MAIL='11524260+sivaji1012@users.noreply.github.com'
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_TERMINAL_PROMPT=0

commit_as() {   # commit_as NAME EMAIL MESSAGE (in the cwd repository)
    GIT_AUTHOR_NAME="$1" GIT_AUTHOR_EMAIL="$2" GIT_COMMITTER_NAME="$1" GIT_COMMITTER_EMAIL="$2" git commit -q -m "$3"
}

merge_as() {   # merge_as NAME EMAIL BRANCH MESSAGE: a --no-ff merge commit of BRANCH into the current branch
    GIT_AUTHOR_NAME="$1" GIT_AUTHOR_EMAIL="$2" GIT_COMMITTER_NAME="$1" GIT_COMMITTER_EMAIL="$2" git merge -q --no-ff -m "$4" "$3"
}

# ---- fixture: origin (bare) with main + gate branches, and a clone `work` holding the trusted tools --------------------------
O="$T/origin.git"
git init -q --bare -b main "$O"
S="$T/seed"
git init -q -b main "$S"
cd "$S" || exit 3
mkdir -p tools/githooks evidence
cp "$UNDER" tools/land_check.sh
cp "$HERE/githooks/dterm.sh" tools/githooks/
printf '# set: X\nB1\nB2 1234abcd\n' > evidence/gate_set.txt
printf '# comment\nmutant\td_entry\tcase_analysis\nEQ1\tD-0900\tsrc/a.jl:10\nEQ2\tD-0901\tsrc/b.jl:20\n' > evidence/equivalents.tsv
printf '# ledger\nbattery\tmutant\towner\tstatus\td_entry\tfirst_seen\tlast_seen\nB1\tB1-S1\tOWN\topen\t\tseed\tseed\nB2\tEQ1\tOWN\taccepted equivalent\tD-0900\tseed\tseed\n' > evidence/survivors.tsv
printf 'oneapprover\n# comment\nAuditBot\n' > evidence/land_approvers.txt
git add -A && commit_as "$ID_NAME" "$ID_MAIL" "seed main"
# main's OWN history holds a merge commit: the `linear` row reads main..SHA only, so every PASS row below also proves that
git checkout -q -b seedside; echo x > seedside.txt; git add -A; commit_as "$ID_NAME" "$ID_MAIL" "seed side"
git checkout -q main; merge_as "$ID_NAME" "$ID_MAIL" seedside "seed merge"
git remote add origin "$O"
git push -q origin main
MAIN="$(git rev-parse HEAD)"

mkbranch() {   # mkbranch BRANCH [message-subject]: one commit on top of main, the identity right; prints the SHA
    git checkout -q -b "$1" "$MAIN"
    echo "$1" > "f_$(echo "$1" | tr / _).txt"
    git add -A && commit_as "$ID_NAME" "$ID_MAIL" "${2:-$1}"
    git rev-parse HEAD
}
GOOD="$(mkbranch gate/good)"; git push -q origin gate/good
cd "$S" || exit 3
# a SHA that is on a wip branch only
git checkout -q -b wip/only "$MAIN"; echo w > w.txt; git add -A; commit_as "$ID_NAME" "$ID_MAIL" "wip only"
WIPONLY="$(git rev-parse HEAD)"; git push -q origin wip/only
# a gate branch with two identities
git checkout -q -b gate/two "$MAIN"; echo a > a.txt; git add -A; commit_as "$ID_NAME" "$ID_MAIL" "one"
echo b > b.txt; git add -A; commit_as "Someone Else" "else@example.org" "two"
TWO="$(git rev-parse HEAD)"; git push -q origin gate/two
# a gate branch with the wrong single identity
git checkout -q -b gate/wrongid "$MAIN"; echo c > c.txt; git add -A; commit_as "Someone Else" "else@example.org" "one"
WRONGID="$(git rev-parse HEAD)"; git push -q origin gate/wrongid
# a strong term in an added line, and in a message
git checkout -q -b gate/termdiff "$MAIN"; echo "the process did a $CRA here" > t.txt; git add -A; commit_as "$ID_NAME" "$ID_MAIL" "harmless subject"
TERMDIFF="$(git rev-parse HEAD)"; git push -q origin gate/termdiff
git checkout -q -b gate/termmsg "$MAIN"; echo m > m.txt; git add -A; commit_as "$ID_NAME" "$ID_MAIL" "fixes a $CRA"
TERMMSG="$(git rev-parse HEAD)"; git push -q origin gate/termmsg
# a gate branch at main itself (nothing to land)
git push -q origin "$MAIN:refs/heads/gate/atmain"
# candidates whose evidence/ files differ: no gate set; a gate set that drops B2
git checkout -q -b gate/noset "$MAIN"; git rm -q evidence/gate_set.txt; commit_as "$ID_NAME" "$ID_MAIL" "no set"
NOSET="$(git rev-parse HEAD)"; git push -q origin gate/noset
git checkout -q -b gate/shrink "$MAIN"; printf '# set: X\nB1\n' > evidence/gate_set.txt; git add -A; commit_as "$ID_NAME" "$ID_MAIL" "shrink"
SHRINK="$(git rev-parse HEAD)"; git push -q origin gate/shrink
# candidates that edit the evidence files (the row diff versus main)
evbranch() {   # evbranch NAME FILE TEXT: a gate branch on main whose one commit appends TEXT (printf %b) to evidence/FILE; prints the SHA
    git checkout -q -b "gate/$1" "$MAIN"; printf '%b' "$3" >> "evidence/$2"; git add -A; commit_as "$ID_NAME" "$ID_MAIL" "$1"
    git rev-parse HEAD
}
EQADD="$(evbranch eqadd equivalents.tsv 'NEWMUT\tD-0950\tsrc/x.jl:1\n')"; git push -q origin gate/eqadd
EQNOID="$(evbranch eqnoid equivalents.tsv 'NEWMUT2\t\tsrc/x.jl:2\n')"; git push -q origin gate/eqnoid
EQBADID="$(evbranch eqbadid equivalents.tsv 'NEWMUT3\tlater\tsrc/x.jl:3\n')"; git push -q origin gate/eqbadid
git checkout -q -b gate/eqmoved "$MAIN"; sed -i 's#src/a.jl:10#src/a.jl:14#' evidence/equivalents.tsv; git add -A; commit_as "$ID_NAME" "$ID_MAIL" "moved"
EQMOVED="$(git rev-parse HEAD)"; git push -q origin gate/eqmoved
git checkout -q -b gate/eqrm "$MAIN"; sed -i '/^EQ2\t/d' evidence/equivalents.tsv; git add -A; commit_as "$ID_NAME" "$ID_MAIL" "rm"
EQRM="$(git rev-parse HEAD)"; git push -q origin gate/eqrm
SVADD="$(evbranch svadd survivors.tsv 'B3\tSM1\tOWN\taccepted equivalent\tD-0951\tnow\tnow\n')"; git push -q origin gate/svadd
SVNOID="$(evbranch svnoid survivors.tsv 'B3\tSM2\tOWN\taccepted equivalent\t\tnow\tnow\n')"; git push -q origin gate/svnoid
SVOPEN="$(evbranch svopen survivors.tsv 'B3\tSM3\tOWN\topen\t\tnow\tnow\n')"; git push -q origin gate/svopen
git checkout -q -b gate/noeq "$MAIN"; git rm -q evidence/equivalents.tsv; commit_as "$ID_NAME" "$ID_MAIL" "no equivalents"; git push -q origin gate/noeq
git checkout -q -b gate/emptyset "$MAIN"; printf '# set: nothing\n' > evidence/gate_set.txt; git add -A; commit_as "$ID_NAME" "$ID_MAIL" "empty set"
EMPTYSET="$(git rev-parse HEAD)"; git push -q origin gate/emptyset
EQNOMUT="$(evbranch eqnomut equivalents.tsv '\tD-0952\tsrc/x.jl:5\n')"; git push -q origin gate/eqnomut
git checkout -q -b gate/svchurn "$MAIN"; sed -i 's/\tseed\tseed$/\tseed\tlater/' evidence/survivors.tsv; git add -A; commit_as "$ID_NAME" "$ID_MAIL" "churn"
SVCHURN="$(git rev-parse HEAD)"; git push -q origin gate/svchurn
# a branch BEHIND a moved main: main moves on, gate/stale was cut from the old main
git checkout -q -b gate/stale "$MAIN"; echo s > s.txt; git add -A; commit_as "$ID_NAME" "$ID_MAIL" "stale"
STALE="$(git rev-parse HEAD)"; git push -q origin gate/stale

# merge commits in the range: at the tip, in the middle (a commit on top of the merge), and a longer linear range as the PASS arm
mergebranch() {   # mergebranch NAME [ontop]: gate/NAME = MAIN + a left commit + a --no-ff merge of a right commit (+ one commit on top); prints the SHA
    git checkout -q -b "gate/$1" "$MAIN"; echo l > "l_$1.txt"; git add -A; commit_as "$ID_NAME" "$ID_MAIL" "left $1"
    git checkout -q -b "side_$1" "$MAIN"; echo r > "r_$1.txt"; git add -A; commit_as "$ID_NAME" "$ID_MAIL" "right $1"
    git checkout -q "gate/$1"; merge_as "$ID_NAME" "$ID_MAIL" "side_$1" "merge $1"
    if [ -n "${2:-}" ]; then echo t > "t_$1.txt"; git add -A; commit_as "$ID_NAME" "$ID_MAIL" "on top of $1"; fi
    git rev-parse HEAD
}
MERGETIP="$(mergebranch mergetip)"; git push -q origin gate/mergetip
MERGEMID="$(mergebranch mergemid ontop)"; git push -q origin gate/mergemid
git checkout -q -b gate/lin3 "$MAIN"
for i in 1 2 3; do echo "$i" > "lin3_$i.txt"; git add -A; commit_as "$ID_NAME" "$ID_MAIL" "linear $i"; done
LIN3="$(git rev-parse HEAD)"; git push -q origin gate/lin3
git checkout -q -b gate/deep "$MAIN"
for i in 1 2; do echo "$i" > "deep_$i.txt"; git add -A; commit_as "$ID_NAME" "$ID_MAIL" "deep $i"; done
DEEP="$(git rev-parse HEAD)"; git push -q origin gate/deep

W="$T/work"
git clone -q "$O" "$W"
cd "$W" || exit 3

# ---- fakes ----------------------------------------------------------------------------------------------------------------
FAKEBIN="$T/bin"; mkdir -p "$FAKEBIN"
cat > "$FAKEBIN/gh" << 'EOF'
#!/usr/bin/env bash
# fake gh: `gh api repos/R/commits/SHA/status?per_page=100` answers the file named by FAKE_GH_JSON; FAKE_GH_FAIL=1 fails
[ "${FAKE_GH_FAIL:-0}" = 1 ] && { echo "HTTP 403: fake failure" >&2; exit 1; }
cat "$FAKE_GH_JSON"
EOF
chmod +x "$FAKEBIN/gh"
status_json() {   # status_json SHA STATE DESCRIPTION LOGIN [CONTEXT] > file
    python3 -I - "$@" << 'PY'
import json, sys
sha, state, desc, login = sys.argv[1:5]
ctx = sys.argv[5] if len(sys.argv) > 5 else "land/approved"
print(json.dumps({"state": state, "sha": sha, "statuses": [
    {"context": "other/thing", "state": "success", "description": "x", "creator": {"login": "AuditBot"}},
    {"context": ctx, "state": state, "description": desc, "creator": {"login": login}}]}))
PY
}
cat > "$T/vr_ok.py" << 'EOF'
import json, os, subprocess, sys
# fake verdict reader: records how it was called and whether a token reached it through the credential helper
open(os.environ["LAND_WORK"] + "/vr_args.txt", "w").write(" ".join(sys.argv[1:]))
p = subprocess.run(["git", "-c", "credential.useHttpPath=false", "credential", "fill"],
                   input="protocol=https\nhost=github.com\n\n", capture_output=True, text=True)
open(os.environ["LAND_WORK"] + "/vr_cred.txt", "w").write(p.stdout)
print(json.dumps({"landable": True, "ci_ok": True, "ev_ok": True, "gate_complete": True,
                  "batteries": [{"name": "B1", "clean": True, "state": "done"}, {"name": "B2", "clean": True, "state": "done"}],
                  "landing": [{"check": "ancestry", "ok": True, "text": "ok"}]}))
EOF
cat > "$T/vr_blocked.py" << 'EOF'
import json, sys
print(json.dumps({"landable": False, "ci_ok": True, "ev_ok": True, "gate_why": "not clean: B2",
                  "batteries": [{"name": "B1", "clean": True, "state": "done"}, {"name": "B2", "clean": False, "state": "done"}],
                  "landing": []}))
sys.exit(1)
EOF
cat > "$T/vr_pending_but_true.py" << 'EOF'
import json, sys
print(json.dumps({"landable": True, "batteries": [{"name": "B1", "clean": True, "state": "done"}], "landing": []}))
sys.exit(3)
EOF
cat > "$T/vr_notlandable.py" << 'EOF'
import json
print(json.dumps({"landable": False, "batteries": [{"name": "B1", "clean": True, "state": "done"}], "landing": []}))
EOF
cat > "$T/vr_nobat.py" << 'EOF'
import json
print(json.dumps({"landable": True, "batteries": [], "landing": []}))
EOF
echo 'this is not json' > "$T/vr_garbage.py"
sed -i 's/^this is not json$/print("not json {")/' "$T/vr_garbage.py"

# run STEP SHA [VAR=value ...]: one land_check.sh step in a fresh LAND_WORK; prints nothing, the rows stay in $LAND_WORK
fresh() { rm -rf "$T/lw"; export LAND_WORK="$T/lw"; mkdir -p "$LAND_WORK"; }
rowstat() { awk -F'\t' -v n="$1" '$1 == n {print $2}' "$T/lw/rows.tsv"; }
rowdetail() { awk -F'\t' -v n="$1" '$1 == n {print $3}' "$T/lw/rows.tsv"; }
expect() {   # expect LABEL ROW STATUS [DETAIL-SUBSTRING]
    local got det; got="$(rowstat "$2")"; det="$(rowdetail "$2")"
    if [ "$got" = "$3" ] && { [ -z "${4:-}" ] || [[ "$det" == *"$4"* ]]; }; then ok "$1"
    else bad "$1" "row $2: wanted $3 ${4:+containing [$4]}, got [$got] / [$det]"; fi
}

echo "== input =="
fresh; bash tools/land_check.sh input "$GOOD" > /dev/null; expect "input: a 40-hex SHA passes" input PASS
fresh; bash tools/land_check.sh input "$(echo "$GOOD" | tr a-f A-F)" > /dev/null; expect "input: upper case refused" input FAIL
fresh; bash tools/land_check.sh input "main" > /dev/null; expect "input: a branch name refused" input FAIL
fresh; bash tools/land_check.sh input "${GOOD:0:12}" > /dev/null; expect "input: an abbreviated SHA refused" input FAIL
fresh; bash tools/land_check.sh git 'x; echo hi' > "$T/o.txt" 2>&1; expect "input: shell text refused, the step does not run it" input FAIL
if grep -q '^hi$' "$T/o.txt"; then bad "input: injected text was executed"; else ok "input: injected text was not executed"; fi

echo "== git conditions (a) =="
git_rows() { fresh; bash tools/land_check.sh git "$1" > /dev/null 2>&1; }
git_rows "$GOOD"
expect "git: gate tip PASS" gate-tip PASS "gate/good"
expect "git: ancestry PASS" ancestry PASS "1 commit"
expect "git: linear PASS (main's own history holds a merge: not read)" linear PASS "linear history"
expect "git: author PASS" author PASS
expect "git: d0164 PASS" d0164 PASS
git_rows "$WIPONLY"; expect "git: a SHA on a wip branch only is no gate tip" gate-tip FAIL "no origin branch"
git_rows 0123456789abcdef0123456789abcdef01234567
expect "git: an unknown SHA: gate-tip FAIL" gate-tip FAIL; expect "git: an unknown SHA: ancestry FAIL" ancestry FAIL; expect "git: an unknown SHA: author FAIL" author FAIL
git_rows "$TWO"; expect "git: two identities" author FAIL "more than one"
git_rows "$WRONGID"; expect "git: one identity that is not the repo's" author FAIL "not the repo's"
git_rows "$TERMDIFF"; expect "git: D-0164 term in an added line" d0164 FAIL "the term grep hits"
git_rows "$TERMMSG"; expect "git: D-0164 term in a commit message" d0164 FAIL
git_rows "$MAIN"; expect "git: the SHA is main: nothing to land" ancestry FAIL "nothing to land"
git_rows "$LIN3"; expect "git: linear: three commits, no merge: PASS" linear PASS "linear history"; expect "git: linear: three commits, ancestry PASS" ancestry PASS "3 commit"
git_rows "$MERGETIP"; expect "git: linear: a merge commit AT THE TIP is refused" linear FAIL "1 merge commit(s)"
expect "git: linear: the FAIL names the merge commit (SHA and subject)" linear FAIL "$(git rev-parse "$MERGETIP") merge mergetip"
expect "git: linear: the FAIL cites the rule" linear FAIL "linear history (A-0206)"
expect "git: linear: a merge range still has ancestry PASS (the rows are independent)" ancestry PASS "3 commit(s)"
git_rows "$MERGEMID"; expect "git: linear: a merge commit in the MIDDLE of the range is refused" linear FAIL "$(git log --merges -1 --format=%H "$MERGEMID") merge mergemid"
git_rows 0123456789abcdef0123456789abcdef01234567; expect "git: linear: an unknown SHA is a FAIL" linear FAIL "not in the clone"
fresh; LAND_BASE=origin/nosuch bash tools/land_check.sh git "$GOOD" > /dev/null 2>&1; expect "git: linear: an unresolvable base is a FAIL" linear FAIL "base unresolved"
# an unreadable range: a clone that lacks the parent of the tip (the tip itself is there, so the step gets past `commit not in the clone`)
W3="$T/work3"; git init -q "$W3"; git -C "$W3" remote add origin "$O"
git -C "$W3" fetch -q origin main:refs/remotes/origin/main gate/deep:refs/heads/deep
mkdir -p "$W3/tools/githooks"; cp tools/land_check.sh "$W3/tools/"; cp tools/githooks/dterm.sh "$W3/tools/githooks/"
( cd "$W3" && fresh && bash tools/land_check.sh git "$DEEP" > /dev/null 2>&1 ); expect "git: linear: the same clone with every object present: PASS" linear PASS "linear history"
DEEPP="$(git -C "$W3" rev-parse "$DEEP^")"; rm -f "$W3/.git/objects/${DEEPP:0:2}/${DEEPP:2}"
if git -C "$W3" cat-file -e "$DEEPP" 2> /dev/null; then bad "git: linear: fixture (the parent object could not be removed: packed?)"
else
    ( cd "$W3" && fresh && bash tools/land_check.sh git "$DEEP" > /dev/null 2>&1 ); expect "git: linear: an unreadable range is a FAIL (fail closed)" linear FAIL "could not be read"
fi
# main moves on: gate/stale no longer descends from it
cd "$S" || exit 3; git checkout -q main; echo more > more.txt; git add -A; commit_as "$ID_NAME" "$ID_MAIL" "main moves"; git push -q origin main
cd "$W" || exit 3; git fetch -q origin
git_rows "$STALE"; expect "git: main moved on: not a fast-forward" ancestry FAIL "NOT an ancestor"
git_rows "$GOOD"; expect "git: (main moved) the old branch is refused too" ancestry FAIL "NOT an ancestor"
# put main back for the rest: a bare repo accepts a push of the old SHA only by force; the fixtures below use a second origin instead
cd "$T" || exit 3
O2="$T/origin2.git"; git init -q --bare -b main "$O2"
cd "$S" || exit 3; git push -q "$O2" "$MAIN:refs/heads/main"
for b in mergetip mergemid lin3 deep good two wrongid termdiff termmsg noset shrink eqadd eqnoid eqbadid eqmoved eqrm svadd svnoid svopen svchurn noeq emptyset eqnomut; do git push -q "$O2" "refs/heads/gate/$b:refs/heads/gate/$b"; done
git push -q "$O2" "refs/heads/wip/only:refs/heads/wip/only"
W2="$T/work2"; git clone -q "$O2" "$W2"; cd "$W2" || exit 3; W="$W2"

echo "== gate set =="
gs() { fresh; bash tools/land_check.sh gateset "$1" > /dev/null 2>&1; }
gs "$GOOD"; expect "gateset: named, no shrink" gateset PASS "2 batteries"
expect "gateset: no row added: the release names no ids" gateset PASS "must name: none"
if grep -q 'no row added, removed or changed' "$T/lw/rowdiff.txt" && [ ! -s "$T/lw/added_ids.txt" ]; then ok "gateset: unchanged evidence files: the row diff says so, the id record is empty"
else bad "gateset: row diff of an unchanged SHA" "$(cat "$T/lw/rowdiff.txt")"; fi
if [ -s "$T/lw/equivalents.tsv" ] && [ -s "$T/lw/gate_set.txt" ]; then ok "gateset: both files extracted from the SHA's tree"; else bad "gateset: files not extracted"; fi
gs "$NOSET"; expect "gateset: no gate set in the SHA" gateset FAIL "not in the SHA"
gs "$EMPTYSET"; expect "gateset: an EMPTY set is no shrink the input can allow" gateset FAIL "names no battery"
fresh; LAND_SET_MAY_SHRINK=true bash tools/land_check.sh gateset "$EMPTYSET" > /dev/null 2>&1; expect "gateset: an EMPTY set fails also with the shrink allowed" gateset FAIL "names no battery"
gs "$SHRINK"; expect "gateset: the set shrinks" gateset FAIL "shrinks"
fresh; LAND_SET_MAY_SHRINK=true bash tools/land_check.sh gateset "$SHRINK" > /dev/null 2>&1; expect "gateset: shrink allowed by the input" gateset PASS "dropped: B2"

echo "== gate set: the rows the SHA adds to or removes from the evidence files (audit D-0923 (4)(a)) =="
rowdiff_has() {   # rowdiff_has LABEL PATTERN: the printed row diff holds a line matching the pattern (fixed string)
    if grep -qF -- "$2" "$T/lw/rowdiff.txt"; then ok "$1"; else bad "$1" "wanted [$2] in the row diff:" "$(cat "$T/lw/rowdiff.txt")"; fi
}
ids_are() {   # ids_are LABEL "id1 id2 ...": the recorded ids, exactly
    if [ "$(tr '\n' ' ' < "$T/lw/added_ids.txt")" = "$2 " ] || { [ -z "$2" ] && [ ! -s "$T/lw/added_ids.txt" ]; }; then ok "$1"
    else bad "$1" "wanted ids [$2], recorded [$(tr '\n' ' ' < "$T/lw/added_ids.txt")]"; fi
}
gs "$EQADD"; expect "rows: an equivalents row added with a D-entry id passes" gateset PASS "D-0950:NEWMUT"
rowdiff_has "rows: the added equivalents row is printed" "+ equivalents.tsv  mutant NEWMUT  d_entry D-0950"
ids_are "rows: the id to name is recorded" "D-0950:NEWMUT"
gs "$EQNOID"; expect "rows: an equivalents row added with an EMPTY d_entry fails closed" gateset FAIL "no D-entry id"
rowdiff_has "rows: the id-less row is printed too" "+ equivalents.tsv  mutant NEWMUT2  d_entry (EMPTY)"
gs "$EQNOMUT"; expect "rows: no mutant name fails closed" gateset FAIL "names no mutant"
gs "$EQBADID"; expect "rows: an equivalents row added with a d_entry that is no D-id fails closed" gateset FAIL "no D-entry id"
gs "$EQRM"; expect "rows: a removed equivalents row passes (printed)" gateset PASS
rowdiff_has "rows: the removed equivalents row is printed" "- equivalents.tsv  mutant EQ2  d_entry D-0901"
ids_are "rows: a removal needs no id" ""
gs "$EQMOVED"; expect "rows: a moved case-analysis line passes" gateset PASS
rowdiff_has "rows: the moved line is printed as changed" "~ equivalents.tsv  mutant EQ1"
ids_are "rows: a moved line needs no id" ""
gs "$SVADD"; expect "rows: a survivors row added as an accepted equivalent with an id passes" gateset PASS "D-0951:SM1"
rowdiff_has "rows: the added survivors row is printed" "+ survivors.tsv  battery B3  mutant SM1"
ids_are "rows: the survivors id is recorded" "D-0951:SM1"
gs "$SVNOID"; expect "rows: a survivors row accepted as equivalent with no id fails closed" gateset FAIL "no D-entry id"
gs "$SVOPEN"; expect "rows: an open survivors row added needs no id" gateset PASS
rowdiff_has "rows: the open survivors row is printed" "+ survivors.tsv  battery B3  mutant SM3"
ids_are "rows: an open survivors row records no id" ""
gs "$SVCHURN"; expect "rows: only first_seen/last_seen moved: no row added or removed" gateset PASS "must name: none"
rowdiff_has "rows: the ledger churn is not reported" "no row added, removed or changed"
# a reference that main does not have: every row of the SHA's copy counts as added
fresh; env LAND_BASE=origin/gate/noeq bash tools/land_check.sh gateset "$EQADD" > /dev/null 2>&1
rowdiff_has "rows: a base without the file: every row counts as added" "+ equivalents.tsv  mutant EQ1"

echo "== verdicts (b) =="
vd() {   # vd SHA READER [VAR=value ...]
    local sha="$1" vr="$2"; shift 2
    fresh; bash tools/land_check.sh gateset "$sha" > /dev/null 2>&1
    # the fake gh always: the release is read through it, and no case may reach the network (no status json = gh fails = no release)
    env PATH="$FAKEBIN:$PATH" GITHUB_REPOSITORY=o/r FAKE_GH_JSON="$T/no_such_status.json" LAND_VERDICT_READ="$vr" "$@" \
        bash tools/land_check.sh verdicts "$sha" > "$T/vd.out" 2>&1
}
vd "$GOOD" "$T/vr_ok.py" GH_TOKEN=TESTTOKEN-not-real; expect "verdicts: landable, exit 0" verdicts PASS "2 batteries read"
grep -q -- "--set $T/lw/gate_set.txt" "$T/lw/vr_args.txt" && grep -q -- "--equivalents $T/lw/equivalents.tsv" "$T/lw/vr_args.txt" &&
    if grep -q -- "--json" "$T/lw/vr_args.txt"; then ok "verdicts: the reader gets the SHA's set and equivalents, --json"; else bad "verdicts: reader arguments" "$(cat "$T/lw/vr_args.txt")"; fi
if grep -q '^password=TESTTOKEN-not-real$' "$T/lw/vr_cred.txt"; then ok "verdicts: the token reaches ci_api.sh's route (git credential fill) by the helper"; else bad "verdicts: credential helper" "$(cat "$T/lw/vr_cred.txt")"; fi
if grep -rq 'TESTTOKEN-not-real' "$T/lw/rows.tsv" "$T/vd.out"; then bad "verdicts: the token leaked into the table or the output"; else ok "verdicts: the token is in no row and no output"; fi
if [ -z "$(git config --get credential.helper)" ]; then ok "verdicts: the repo's own git config is not changed (env only)"; else bad "verdicts: credential.helper written to the config"; fi
vd "$GOOD" "$T/vr_blocked.py"; expect "verdicts: blocked battery" verdicts FAIL "blocked: B2"
vd "$GOOD" "$T/vr_pending_but_true.py"; expect "verdicts: landable true but exit 3 is no pass" verdicts FAIL "exit 3"
vd "$GOOD" "$T/vr_notlandable.py"; expect "verdicts: exit 0 and clean batteries but landable false" verdicts FAIL "landable=False"
vd "$GOOD" "$T/vr_nobat.py"; expect "verdicts: no battery read is no pass" verdicts FAIL "no battery read"
vd "$GOOD" "$T/vr_garbage.py"; expect "verdicts: unreadable output" verdicts FAIL "unreadable"
vd "$GOOD" "$T/does_not_exist.py"; expect "verdicts: reader missing from the trusted tree" verdicts FAIL "land the reader first"
fresh; bash tools/land_check.sh verdicts "$GOOD" > /dev/null 2>&1; expect "verdicts: no reader and no gate set extracted" verdicts FAIL

# the release of a non-empty src diff (D-1006 (2)): the verdicts step hands the reader the description of an APPROVER's success
# `land/approved` status as --release, and prints the reader's src diff text (numstat and sha256) in its row, PASS or FAIL
HEX64="$(printf 'numstat' | sha256sum | cut -d' ' -f1)"
cat > "$T/vr_src.py" << 'EOF'
import json, os, sys
open(os.environ["LAND_WORK"] + "/vr_args.txt", "w").write("\n".join(sys.argv[1:]))
ok = "--release" in sys.argv and "src-diff " in sys.argv[sys.argv.index("--release") + 1]
print(json.dumps({"landable": ok, "ci_ok": True, "ev_ok": True,
                  "batteries": [{"name": "B1", "clean": True, "state": "done"}],
                  "landing": [{"check": "src diff", "ok": ok, "text": "sha256 SENTINEL-DIGEST; numstat: 2 1 src/a.jl"}]}))
sys.exit(0 if ok else 1)
EOF
reldesc() { status_json "$GOOD" "$1" "$2" "$3" > "$T/rel.json"; }   # reldesc STATE DESCRIPTION LOGIN
reldesc success "LAND $GOOD [ids: src-diff $HEX64]" AuditBot
vd "$GOOD" "$T/vr_src.py" FAKE_GH_JSON="$T/rel.json"
expect "verdicts: an approver's release reaches the reader, a src diff it accepts passes" verdicts PASS "src diff: sha256 SENTINEL-DIGEST"
if grep -qxF -- "--release" "$T/lw/vr_args.txt" && grep -qxF -- "LAND $GOOD [ids: src-diff $HEX64]" "$T/lw/vr_args.txt"; then ok "verdicts: the reader gets --release with the whole description"
else bad "verdicts: release argument" "$(cat "$T/lw/vr_args.txt")"; fi
vd "$GOOD" "$T/vr_src.py"
expect "verdicts: no release readable (gh fails): the reader fails the src diff, the row says so" verdicts FAIL "src diff: sha256 SENTINEL-DIGEST"
if grep -qxF -- "--release" "$T/lw/vr_args.txt"; then bad "verdicts: --release passed with no release"; else ok "verdicts: no release, no --release argument"; fi
reldesc success "LAND $GOOD [ids: src-diff $HEX64]" stranger
vd "$GOOD" "$T/vr_src.py" FAKE_GH_JSON="$T/rel.json"
expect "verdicts: a release set by a stranger is no release" verdicts FAIL "landing checks failed: src diff"
if grep -qxF -- "--release" "$T/lw/vr_args.txt"; then bad "verdicts: a stranger's release reached the reader"; else ok "verdicts: a stranger's release does not reach the reader"; fi
reldesc failure "LAND $GOOD [ids: src-diff $HEX64]" AuditBot
vd "$GOOD" "$T/vr_src.py" FAKE_GH_JSON="$T/rel.json"
expect "verdicts: a release whose state is not success is no release" verdicts FAIL "landing checks failed: src diff"
vd "$GOOD" "$T/vr_ok.py" FAKE_GH_JSON="$T/rel.json"
expect "verdicts: an empty src diff row adds no src note" verdicts PASS "2 batteries read"
# the channel of a `local:` release item (D-1009 (5)): LAND_CHANNEL is handed to the reader as --channel, and only when it is set
vd "$GOOD" "$T/vr_src.py" FAKE_GH_JSON="$T/rel.json"
vd "$GOOD" "$T/vr_src.py" LAND_CHANNEL="$T/chan_agent.md"
if grep -qxF -- "--channel" "$T/lw/vr_args.txt" && grep -qxF -- "$T/chan_agent.md" "$T/lw/vr_args.txt"; then ok "verdicts: LAND_CHANNEL reaches the reader as --channel"
else bad "verdicts: --channel argument" "$(cat "$T/lw/vr_args.txt")"; fi
vd "$GOOD" "$T/vr_src.py"
if grep -qxF -- "--channel" "$T/lw/vr_args.txt"; then bad "verdicts: --channel passed with LAND_CHANNEL unset"; else ok "verdicts: LAND_CHANNEL unset, no --channel argument (the reader's default)"; fi
# LAND-TOOL-3: the answer of commits/<sha>/status (which may hold a `land/local/<ROW>` status) and the approvers file reach the reader as
# --statuses / --approvers, and ONLY when the answer was read (gh failed, no approvers file: neither argument, the status route stays closed)
LOCVER="LOCAL VERDICT G1GC3-T3 tree $(git rev-parse "$GOOD^{tree}") caught (hang) site pl-gc.c:1234"
status_json "$GOOD" success "$LOCVER" AuditBot "land/local/G1GC3-T3" > "$T/loc.json"
vd "$GOOD" "$T/vr_src.py" FAKE_GH_JSON="$T/loc.json"
if grep -qxF -- "--statuses" "$T/lw/vr_args.txt" && grep -qxF -- "$T/lw/release.json" "$T/lw/vr_args.txt" &&
    grep -qxF -- "--approvers" "$T/lw/vr_args.txt" && grep -qxF -- "$W/evidence/land_approvers.txt" "$T/lw/vr_args.txt"; then ok "verdicts: the status answer and the approvers file reach the reader (--statuses, --approvers)"
else bad "verdicts: --statuses/--approvers arguments" "$(cat "$T/lw/vr_args.txt")"; fi
if grep -q 'land/local/G1GC3-T3' "$T/lw/release.json"; then ok "verdicts: the saved answer is the whole status answer (the land/local status is in it)"; else bad "verdicts: release.json lacks the land/local status"; fi
vd "$GOOD" "$T/vr_src.py"
if grep -qxF -- "--statuses" "$T/lw/vr_args.txt" || grep -qxF -- "--approvers" "$T/lw/vr_args.txt"; then bad "verdicts: --statuses/--approvers passed though gh could not answer"; else ok "verdicts: gh cannot answer, no --statuses and no --approvers (the status route is closed)"; fi
vd "$GOOD" "$T/vr_src.py" FAKE_GH_JSON="$T/loc.json" FAKE_GH_FAIL=1
if grep -qxF -- "--statuses" "$T/lw/vr_args.txt"; then bad "verdicts: --statuses passed though gh failed"; else ok "verdicts: gh fails: no --statuses"; fi
cp "$W/evidence/land_approvers.txt" "$T/ap.keep2"; : > "$W/evidence/land_approvers.txt"
vd "$GOOD" "$T/vr_src.py" FAKE_GH_JSON="$T/loc.json"
cp "$T/ap.keep2" "$W/evidence/land_approvers.txt"
if grep -qxF -- "--statuses" "$T/lw/vr_args.txt"; then bad "verdicts: --statuses passed with an empty approvers file"; else ok "verdicts: an empty approvers file: no --statuses (fail closed)"; fi
# a release.json left by an earlier run in the same LAND_WORK is never read as this run's answer (gh fails now: no --statuses)
fresh; bash tools/land_check.sh gateset "$GOOD" > /dev/null 2>&1; printf 'stale' > "$LAND_WORK/release.json"
env PATH="$FAKEBIN:$PATH" GITHUB_REPOSITORY=o/r FAKE_GH_JSON="$T/no_such_status.json" LAND_VERDICT_READ="$T/vr_src.py" bash tools/land_check.sh verdicts "$GOOD" > /dev/null 2>&1
if grep -qxF -- "--statuses" "$T/lw/vr_args.txt"; then bad "verdicts: a stale release.json was handed to the reader"; else ok "verdicts: a stale release.json from an earlier run is not handed to the reader"; fi

echo "== marker (c) =="
MKSHA="$GOOD"
mk() {   # mk JSON-FILE [VAR=value ...]: the gateset step first (it records the added rows the release must name), then the marker
    local j="$1"; shift
    fresh
    bash "$W/tools/land_check.sh" gateset "$MKSHA" > /dev/null 2>&1
    env PATH="$FAKEBIN:$PATH" FAKE_GH_JSON="$j" GITHUB_REPOSITORY=o/r "$@" bash "$W/tools/land_check.sh" marker "$MKSHA" > "$T/mk.out" 2>&1
}
status_json "$GOOD" success "LAND $GOOD" AuditBot > "$T/s_ok.json"; mk "$T/s_ok.json"; expect "marker: success, description LAND <sha>, approver" marker PASS "auditbot"
status_json "$GOOD" success "LAND $GOOD" auditbot > "$T/s_case.json"; mk "$T/s_case.json"; expect "marker: login compared case-insensitively" marker PASS
status_json "$GOOD" success "LAND $MAIN" AuditBot > "$T/s_other.json"; mk "$T/s_other.json"; expect "marker: LAND of ANOTHER sha" marker FAIL "description"
status_json "$GOOD" failure "LAND $GOOD" AuditBot > "$T/s_fail.json"; mk "$T/s_fail.json"; expect "marker: a later failure revokes" marker FAIL "failure"
status_json "$GOOD" pending "LAND $GOOD" AuditBot > "$T/s_pend.json"; mk "$T/s_pend.json"; expect "marker: pending is no release" marker FAIL
status_json "$GOOD" success "LAND $GOOD" stranger > "$T/s_who.json"; mk "$T/s_who.json"; expect "marker: a login that is not an approver" marker FAIL "not in land_approvers"
status_json "$GOOD" success "LAND $GOOD" AuditBot "ci/other" > "$T/s_ctx.json"; mk "$T/s_ctx.json"; expect "marker: another context" marker FAIL "no land/approved"
echo '{"state":"pending","statuses":[]}' > "$T/s_none.json"; mk "$T/s_none.json"; expect "marker: no status at all" marker FAIL "no land/approved"
echo 'not json' > "$T/s_bad.json"; mk "$T/s_bad.json"; expect "marker: unreadable answer" marker FAIL "unreadable"
mk "$T/s_ok.json" FAKE_GH_FAIL=1; expect "marker: gh fails (API error, rate limit)" marker FAIL "could not be read"
NOGH="$T/nogh"; mkdir -p "$NOGH"
for c in git python3 bash sed awk grep tr cut sort wc mv mkdir head cat env dirname rm; do ln -sf "$(command -v "$c")" "$NOGH/$c"; done
fresh; env PATH="$NOGH" GITHUB_REPOSITORY=o/r bash "$W/tools/land_check.sh" marker "$GOOD" > /dev/null 2>&1; expect "marker: gh missing from PATH" marker FAIL "gh is not available"
cp "$W/evidence/land_approvers.txt" "$T/ap.keep"; printf '# only a comment\n' > "$W/evidence/land_approvers.txt"
mk "$T/s_ok.json"; expect "marker: no approver listed (fail closed)" marker FAIL "names no approver"
cp "$T/ap.keep" "$W/evidence/land_approvers.txt"
status_json "$GOOD" success "LAND $GOOD extra" AuditBot > "$T/s_junk.json"; mk "$T/s_junk.json"; expect "marker: text after the sha that is not an ids list" marker FAIL "description"
status_json "$GOOD" success "LAND $GOOD [ids: ]" AuditBot > "$T/s_noids.json"; mk "$T/s_noids.json"; expect "marker: an empty ids list, no rows added: passes" marker PASS
fresh; env PATH="$FAKEBIN:$PATH" FAKE_GH_JSON="$T/s_ok.json" GITHUB_REPOSITORY=o/r bash "$W/tools/land_check.sh" marker "$GOOD" > /dev/null 2>&1
expect "marker: the gateset step never ran: no record of the added rows, fail closed" marker FAIL "no record"
# the ids of the rows the SHA adds: the release must name exactly them (audit D-0923 (4)(a))
MKSHA="$EQADD"
status_json "$EQADD" success "LAND $EQADD" AuditBot > "$T/e0.json"; mk "$T/e0.json"; expect "marker ids: rows added, no ids named" marker FAIL "not named"
status_json "$EQADD" success "LAND $EQADD [ids: D-0950:NEWMUT]" AuditBot > "$T/e1.json"; mk "$T/e1.json"; expect "marker ids: the added row named by D-id:mutant" marker PASS "D-0950:NEWMUT"
status_json "$EQADD" success "LAND $EQADD [ids: D-0950]" AuditBot > "$T/e2.json"; mk "$T/e2.json"; expect "marker ids: a bare D-id covers the rows citing it" marker PASS
status_json "$EQADD" success "LAND $EQADD [ids: D-0950:NEWMUT,D-0999:OTHER]" AuditBot > "$T/e3.json"; mk "$T/e3.json"; expect "marker ids: an id the commit does not add" marker FAIL "does not add"
status_json "$EQADD" success "LAND $EQADD [ids: D-0951]" AuditBot > "$T/e4.json"; mk "$T/e4.json"; expect "marker ids: the wrong D-id names nothing added" marker FAIL
status_json "$EQADD" success "LAND $EQADD [ids: D-0950:OTHERMUT]" AuditBot > "$T/e5.json"; mk "$T/e5.json"; expect "marker ids: right D-id, wrong mutant" marker FAIL
status_json "$EQADD" success "LAND $EQADD [ids: D-0950:NEWMUT]" stranger > "$T/e6.json"; mk "$T/e6.json"; expect "marker ids: the ids do not make a stranger an approver" marker FAIL "not in land_approvers"
MKSHA="$SVADD"
status_json "$SVADD" success "LAND $SVADD" AuditBot > "$T/e7.json"; mk "$T/e7.json"; expect "marker ids: a survivors row added, no ids named" marker FAIL "not named"
status_json "$SVADD" success "LAND $SVADD [ids: D-0951:SM1]" AuditBot > "$T/e8.json"; mk "$T/e8.json"; expect "marker ids: the survivors row named" marker PASS
MKSHA="$EQRM"
status_json "$EQRM" success "LAND $EQRM" AuditBot > "$T/e9.json"; mk "$T/e9.json"; expect "marker ids: a removal needs no id" marker PASS
MKSHA="$GOOD"
status_json "$GOOD" success "LAND $GOOD [ids: D-0950:NEWMUT]" AuditBot > "$T/e10.json"; mk "$T/e10.json"; expect "marker ids: ids named but none added" marker FAIL "does not add"
status_json "$GOOD" success "LAND $GOOD [ids: D-0950]" AuditBot > "$T/e11.json"; mk "$T/e11.json"; expect "marker ids: a bare D-id with no row added" marker FAIL "does not add"
# `src-diff <sha256>` in the ids list (D-1006 (2)): form-checked here, compared by tools/verdict_read.py; never an id of an evidence row
status_json "$GOOD" success "LAND $GOOD [ids: src-diff $HEX64]" AuditBot > "$T/q1.json"; mk "$T/q1.json"; expect "marker src-diff: a well-formed release, no rows added: passes" marker PASS "src-diff $HEX64"
status_json "$EQADD" success "LAND $EQADD [ids: D-0950:NEWMUT,src-diff $HEX64]" AuditBot > "$T/q2.json"; MKSHA="$EQADD"; mk "$T/q2.json"; expect "marker src-diff: beside an equivalents id: passes" marker PASS "D-0950:NEWMUT"
status_json "$EQADD" success "LAND $EQADD [ids: src-diff $HEX64]" AuditBot > "$T/q3.json"; mk "$T/q3.json"; expect "marker src-diff: the src-diff names no evidence row" marker FAIL "not named"
MKSHA="$GOOD"
status_json "$GOOD" success "LAND $GOOD [ids: src-diff ${HEX64:0:63}]" AuditBot > "$T/q4.json"; mk "$T/q4.json"; expect "marker src-diff: 63 digits" marker FAIL "malformed src-diff"
status_json "$GOOD" success "LAND $GOOD [ids: src-diff $(echo "$HEX64" | tr a-f A-F)]" AuditBot > "$T/q5.json"; mk "$T/q5.json"; expect "marker src-diff: upper-case digits" marker FAIL "malformed src-diff"
status_json "$GOOD" success "LAND $GOOD [ids: src-diff]" AuditBot > "$T/q6.json"; mk "$T/q6.json"; expect "marker src-diff: no digest" marker FAIL "malformed src-diff"
status_json "$GOOD" success "LAND $GOOD [ids: src-diff $HEX64,src-diff $(printf 'other' | sha256sum | cut -d' ' -f1)]" AuditBot > "$T/q7.json"; mk "$T/q7.json"; expect "marker src-diff: two different digests" marker FAIL "more than one"
status_json "$GOOD" success "LAND $GOOD [ids: src-diff $HEX64]" stranger > "$T/q8.json"; mk "$T/q8.json"; expect "marker src-diff: a stranger's release is still refused" marker FAIL "not in land_approvers"
# `local: <row id> @<A-entry ref>` in the ids list (D-1009 (5)): form-checked here (one item per row), the channel entry is read by
# tools/verdict_read.py; never an id of an evidence row
LOC="local: G1GC3-T3 @A-NEXT 2026-11-23 15:40Z"
status_json "$GOOD" success "LAND $GOOD [ids: $LOC]" AuditBot > "$T/l1.json"; mk "$T/l1.json"; expect "marker local: a well-formed item, no rows added: passes" marker PASS "$LOC"
status_json "$GOOD" success "LAND $GOOD [ids: local: G1GC3-T3 @A-0123]" AuditBot > "$T/l1b.json"; mk "$T/l1b.json"; expect "marker local: an @A-NNNN ref passes" marker PASS "@A-0123"
status_json "$GOOD" success "LAND $GOOD [ids: src-diff $HEX64,$LOC,local: B2-X @A-0456]" AuditBot > "$T/l2.json"; mk "$T/l2.json"; expect "marker local: beside src-diff, two rows: passes" marker PASS "local: B2-X @A-0456"
status_json "$EQADD" success "LAND $EQADD [ids: D-0950:NEWMUT,$LOC]" AuditBot > "$T/l3.json"; MKSHA="$EQADD"; mk "$T/l3.json"; expect "marker local: beside an equivalents id: passes" marker PASS "D-0950:NEWMUT"
status_json "$EQADD" success "LAND $EQADD [ids: $LOC]" AuditBot > "$T/l4.json"; mk "$T/l4.json"; expect "marker local: the item names no evidence row" marker FAIL "not named"
MKSHA="$GOOD"
status_json "$GOOD" success "LAND $GOOD [ids: local: G1GC3-T3]" AuditBot > "$T/l5.json"; mk "$T/l5.json"; expect "marker local: no ref" marker FAIL "malformed local"
status_json "$GOOD" success "LAND $GOOD [ids: local: G1GC3-T3 @yesterday]" AuditBot > "$T/l6.json"; mk "$T/l6.json"; expect "marker local: a ref that is no A-entry heading" marker FAIL "malformed local"
status_json "$GOOD" success "LAND $GOOD [ids: local G1GC3-T3 @A-0123]" AuditBot > "$T/l7.json"; mk "$T/l7.json"; expect "marker local: no colon" marker FAIL "malformed local"
status_json "$GOOD" success "LAND $GOOD [ids: $LOC,local: G1GC3-T3 @A-0123]" AuditBot > "$T/l8.json"; mk "$T/l8.json"; expect "marker local: one row named twice" marker FAIL "twice"
status_json "$GOOD" success "LAND $GOOD [ids: $LOC]" stranger > "$T/l9.json"; mk "$T/l9.json"; expect "marker local: a stranger's release is still refused" marker FAIL "not in land_approvers"
# LAND-TOOL-3: `tree-ruling D-NNNN` after a local item, and `stand: <list> @D-NNNN from <40 hex>`: form-checked here, no evidence-row ids
OLDS="$(git rev-parse "$GOOD^")"
LOCR="$LOC tree-ruling D-1010"
STD="stand: TB5 @D-1012 from $OLDS"
status_json "$GOOD" success "LAND $GOOD [ids: $LOCR]" AuditBot > "$T/r1.json"; mk "$T/r1.json"; expect "marker local: a tree-ruling item passes" marker PASS "tree-ruling D-1010"
status_json "$GOOD" success "LAND $GOOD [ids: $LOC tree-ruling]" AuditBot > "$T/r2.json"; mk "$T/r2.json"; expect "marker local: a tree-ruling with no D-entry" marker FAIL "malformed local"
status_json "$GOOD" success "LAND $GOOD [ids: $LOC tree-ruling D-10]" AuditBot > "$T/r3.json"; mk "$T/r3.json"; expect "marker local: a tree-ruling with a short D id" marker FAIL "malformed local"
status_json "$GOOD" success "LAND $GOOD [ids: $LOC ruling D-1010]" AuditBot > "$T/r4.json"; mk "$T/r4.json"; expect "marker local: the word must be tree-ruling" marker FAIL "malformed local"
status_json "$GOOD" success "LAND $GOOD [ids: $LOCR,local: G1GC3-T3 @A-0123 tree-ruling D-1010]" AuditBot > "$T/r5.json"; mk "$T/r5.json"; expect "marker local: a ruled row named twice" marker FAIL "twice"
status_json "$GOOD" success "LAND $GOOD [ids: $STD]" AuditBot > "$T/r6.json"; mk "$T/r6.json"; expect "marker stand: a well-formed item passes" marker PASS "stand: TB5 @D-1012 from $OLDS"
status_json "$GOOD" success "LAND $GOOD [ids: $STD,stand: TB7 @D-1012 from $OLDS,src-diff $HEX64,$LOCR]" AuditBot > "$T/r7.json"; mk "$T/r7.json"; expect "marker stand: several lists beside the other items" marker PASS "stand: TB7 @D-1012"
status_json "$EQADD" success "LAND $EQADD [ids: D-0950:NEWMUT,$STD]" AuditBot > "$T/r8.json"; MKSHA="$EQADD"; mk "$T/r8.json"; expect "marker stand: beside an equivalents id passes" marker PASS "D-0950:NEWMUT"
status_json "$EQADD" success "LAND $EQADD [ids: $STD]" AuditBot > "$T/r9.json"; mk "$T/r9.json"; expect "marker stand: the item names no evidence row" marker FAIL "not named"
MKSHA="$GOOD"
for bad in "stand: TB5 @D-1012" "stand: TB5 @D-1012 from ${OLDS:0:39}" "stand: TB5 @D-1012 from $(echo "$OLDS" | tr a-f A-F)" "stand: TB5 @D-12 from $OLDS" "stand: TB5 @A-0123 from $OLDS" "stand: TB5 D-1012 from $OLDS" "stand TB5 @D-1012 from $OLDS" "stand: @D-1012 from $OLDS"; do
    status_json "$GOOD" success "LAND $GOOD [ids: $bad]" AuditBot > "$T/r10.json"; mk "$T/r10.json"; expect "marker stand: malformed item ($bad)" marker FAIL "malformed stand"
done
status_json "$GOOD" success "LAND $GOOD [ids: $STD,stand: TB5 @D-1011 from $OLDS]" AuditBot > "$T/r11.json"; mk "$T/r11.json"; expect "marker stand: one list named twice" marker FAIL "stand list twice"
status_json "$GOOD" success "LAND $GOOD [ids: $STD]" stranger > "$T/r12.json"; mk "$T/r12.json"; expect "marker stand: a stranger's release is still refused" marker FAIL "not in land_approvers"

echo "== decide =="
fill() {   # fill ROW=STATUS... : write a full table with the given statuses (default PASS)
    fresh; local n; for n in input gate-tip ancestry linear author d0164 gateset verdicts marker; do printf '%s\tPASS\tfixture\n' "$n" >> "$LAND_WORK/rows.tsv"; done
    local kv; for kv in "$@"; do sed -i "s/^${kv%%=*}\tPASS/${kv%%=*}\t${kv#*=}/" "$LAND_WORK/rows.tsv"; done
}
fill; LAND_DRY_RUN=false bash tools/land_check.sh decide "$GOOD" > "$T/d.out" 2>&1; rc=$?
if [ "$rc" = 0 ] && grep -q '^LAND: every condition holds' "$T/d.out"; then ok "decide: all nine PASS in a real run: exit 0"; else bad "decide: all PASS" "rc=$rc" "$(cat "$T/d.out")"; fi
for r in input gate-tip ancestry linear author d0164 gateset verdicts marker; do
    fill "$r=FAIL"; LAND_DRY_RUN=false bash tools/land_check.sh decide "$GOOD" > "$T/d.out" 2>&1; rc=$?
    if [ "$rc" = 1 ] && grep -q '^REFUSED' "$T/d.out"; then ok "decide: one FAIL ($r) in a real run: exit 1"; else bad "decide: $r FAIL not refused" "rc=$rc"; fi
done
fill marker=FAIL; LAND_DRY_RUN=true bash tools/land_check.sh decide "$GOOD" > "$T/d.out" 2>&1; rc=$?
if [ "$rc" = 0 ] && grep -q '^DRY RUN: a real run would REFUSE' "$T/d.out"; then ok "decide: dry run with a FAIL: exit 0, says REFUSE"; else bad "decide: dry-run FAIL" "rc=$rc" "$(cat "$T/d.out")"; fi
fill; LAND_DRY_RUN=true bash tools/land_check.sh decide "$GOOD" > "$T/d.out" 2>&1
if grep -q '^DRY RUN: every condition holds' "$T/d.out"; then ok "decide: dry run all PASS says it would land"; else bad "decide: dry-run PASS text"; fi
fill; sed -i '/^linear\t/d' "$LAND_WORK/rows.tsv"; LAND_DRY_RUN=false bash tools/land_check.sh decide "$GOOD" > "$T/d.out" 2>&1; rc=$?
if [ "$rc" = 1 ] && grep -q '| linear    | FAIL | no row was written' "$T/d.out"; then ok "decide: only the linear row missing: refused, the table names it"; else bad "decide: a missing linear row" "rc=$rc" "$(cat "$T/d.out")"; fi
fill; LAND_DRY_RUN=true bash tools/land_check.sh decide "$GOOD" > "$T/d.out" 2>&1
if grep -q '^| linear ' "$T/d.out"; then ok "decide: the table prints the linear row"; else bad "decide: no linear row in the table" "$(cat "$T/d.out")"; fi
fresh; printf 'input\tPASS\tfixture\n' > "$T/lw/rows.tsv"; LAND_DRY_RUN=false bash tools/land_check.sh decide "$GOOD" > "$T/d.out" 2>&1; rc=$?
if [ "$rc" = 1 ] && grep -q 'no row was written' "$T/d.out"; then ok "decide: a missing row counts as FAIL"; else bad "decide: missing rows" "rc=$rc"; fi
fresh; LAND_DRY_RUN=false bash tools/land_check.sh decide "$GOOD" > /dev/null 2>&1; rc=$?
if [ "$rc" = 1 ]; then ok "decide: no rows at all: exit 1"; else bad "decide: empty table" "rc=$rc"; fi
fill; GITHUB_OUTPUT="$T/gho" LAND_DRY_RUN=true bash tools/land_check.sh decide "$GOOD" > /dev/null 2>&1
if grep -qx 'landable=true' "$T/gho"; then ok "decide: landable=true on the job output"; else bad "decide: output"; fi
fill gateset=FAIL; : > "$T/gho"; GITHUB_OUTPUT="$T/gho" LAND_DRY_RUN=true bash tools/land_check.sh decide "$GOOD" > /dev/null 2>&1
if grep -qx 'landable=false' "$T/gho"; then ok "decide: landable=false on the job output"; else bad "decide: output false"; fi
fill; bash tools/land_check.sh gateset "$EQADD" > /dev/null 2>&1; LAND_DRY_RUN=true bash tools/land_check.sh decide "$EQADD" > "$T/d.out" 2>&1
if grep -qF '+ equivalents.tsv  mutant NEWMUT  d_entry D-0950' "$T/d.out" && grep -q 'ADDED (+), REMOVED (-)' "$T/d.out"; then ok "decide: prints every row added to the evidence files"
else bad "decide: the row diff is not printed" "$(cat "$T/d.out")"; fi
fill; LAND_DRY_RUN=true bash tools/land_check.sh decide "$GOOD" > "$T/d.out" 2>&1
if grep -q 'not computed' "$T/d.out"; then ok "decide: without the gateset step it says the row diff was not computed"; else bad "decide: no row diff, no notice" "$(cat "$T/d.out")"; fi
fill; bash tools/land_check.sh gateset "$EQRM" > /dev/null 2>&1; LAND_DRY_RUN=true bash tools/land_check.sh decide "$EQRM" > "$T/d.out" 2>&1
if grep -qF -- '- equivalents.tsv  mutant EQ2' "$T/d.out"; then ok "decide: prints every row removed from the evidence files"; else bad "decide: removed row not printed" "$(cat "$T/d.out")"; fi

echo "== a full dry run and a real push, end to end =="
full() {   # full SHA READER JSON [VAR=...]: every step in order, as the workflow runs them
    local sha="$1" vr="$2" j="$3"; shift 3; fresh
    local e=(env PATH="$FAKEBIN:$PATH" FAKE_GH_JSON="$j" GITHUB_REPOSITORY=o/r LAND_VERDICT_READ="$vr" "$@")
    "${e[@]}" bash tools/land_check.sh input "$sha" > /dev/null 2>&1
    "${e[@]}" bash tools/land_check.sh git "$sha" > /dev/null 2>&1
    "${e[@]}" bash tools/land_check.sh gateset "$sha" > /dev/null 2>&1
    "${e[@]}" bash tools/land_check.sh verdicts "$sha" > /dev/null 2>&1
    "${e[@]}" bash tools/land_check.sh marker "$sha" > /dev/null 2>&1
    "${e[@]}" bash tools/land_check.sh decide "$sha" > "$T/full.out" 2>&1
}
status_json "$GOOD" success "LAND $GOOD" AuditBot > "$T/s_good.json"
full "$GOOD" "$T/vr_ok.py" "$T/s_good.json" LAND_DRY_RUN=true; rc=$?
if grep -q '^DRY RUN: every condition holds' "$T/full.out"; then ok "full dry run: every condition holds"; else bad "full dry run" "$(cat "$T/full.out")"; fi
if [ "$(git ls-remote "$O2" refs/heads/main | cut -f1)" = "$MAIN" ]; then ok "full dry run: main untouched"; else bad "dry run moved main"; fi
# the same with the marker withdrawn: refused
status_json "$GOOD" failure "LAND $GOOD" AuditBot > "$T/s_rev.json"
full "$GOOD" "$T/vr_ok.py" "$T/s_rev.json" LAND_DRY_RUN=false
if grep -q '^REFUSED' "$T/full.out"; then ok "full run without a release: REFUSED"; else bad "full refused" "$(cat "$T/full.out")"; fi
# push refused without a release
fresh; env PATH="$FAKEBIN:$PATH" FAKE_GH_JSON="$T/s_rev.json" GITHUB_REPOSITORY=o/r bash tools/land_check.sh push "$GOOD" > "$T/p.out" 2>&1; rc=$?
if [ "$rc" = 1 ] && [ "$(git ls-remote "$O2" refs/heads/main | cut -f1)" = "$MAIN" ]; then ok "push: refused without a release, main unchanged"; else bad "push without release" "rc=$rc" "$(cat "$T/p.out")"; fi
fresh; env PATH="$FAKEBIN:$PATH" FAKE_GH_JSON="$T/s_good.json" GITHUB_REPOSITORY=o/r bash tools/land_check.sh push "not-a-sha" > "$T/p.out" 2>&1; rc=$?
if [ "$rc" = 1 ]; then ok "push: a bad SHA is refused with exit 1"; else bad "push bad sha" "rc=$rc"; fi
status_json "$MERGEMID" success "LAND $MERGEMID" AuditBot > "$T/s_mrg.json"
fresh; env PATH="$FAKEBIN:$PATH" FAKE_GH_JSON="$T/s_mrg.json" GITHUB_REPOSITORY=o/r bash tools/land_check.sh push "$MERGEMID" > "$T/p.out" 2>&1; rc=$?
if [ "$rc" = 1 ] && [ "$(git ls-remote "$O2" refs/heads/main | cut -f1)" = "$MAIN" ] && grep -q 'push refused: linear' "$T/p.out"; then ok "push: a range holding a merge commit is refused even with a release, main unchanged"
else bad "push merge range" "rc=$rc" "$(cat "$T/p.out")"; fi
fresh; env PATH="$FAKEBIN:$PATH" FAKE_GH_JSON="$T/s_good.json" GITHUB_REPOSITORY=o/r bash tools/land_check.sh push "$TERMDIFF" > "$T/p.out" 2>&1; rc=$?
if [ "$rc" = 1 ] && [ "$(git ls-remote "$O2" refs/heads/main | cut -f1)" = "$MAIN" ]; then ok "push: a failing git condition (D-0164) is refused"; else bad "push termdiff" "rc=$rc" "$(cat "$T/p.out")"; fi
# a push is refused when the gate set shrinks, and when the release does not name the rows the SHA adds, even with a valid release
status_json "$SHRINK" success "LAND $SHRINK" AuditBot > "$T/s_shr.json"
fresh; env PATH="$FAKEBIN:$PATH" FAKE_GH_JSON="$T/s_shr.json" GITHUB_REPOSITORY=o/r bash tools/land_check.sh push "$SHRINK" > "$T/p.out" 2>&1; rc=$?
if [ "$rc" = 1 ] && [ "$(git ls-remote "$O2" refs/heads/main | cut -f1)" = "$MAIN" ] && grep -q 'push refused: gateset' "$T/p.out"; then ok "push: a shrinking gate set is refused even with a release"
else bad "push shrink" "rc=$rc" "$(cat "$T/p.out")"; fi
status_json "$EQADD" success "LAND $EQADD" AuditBot > "$T/s_eqa.json"
fresh; env PATH="$FAKEBIN:$PATH" FAKE_GH_JSON="$T/s_eqa.json" GITHUB_REPOSITORY=o/r bash tools/land_check.sh push "$EQADD" > "$T/p.out" 2>&1; rc=$?
if [ "$rc" = 1 ] && [ "$(git ls-remote "$O2" refs/heads/main | cut -f1)" = "$MAIN" ] && grep -q 'push refused: marker' "$T/p.out"; then ok "push: a release that does not name the added rows is refused"
else bad "push eqadd unnamed" "rc=$rc" "$(cat "$T/p.out")"; fi
fresh; env PATH="$FAKEBIN:$PATH" FAKE_GH_JSON="$T/s_good.json" GITHUB_REPOSITORY=o/r bash tools/land_check.sh push "$GOOD" > "$T/p.out" 2>&1; rc=$?
if [ "$rc" = 0 ] && [ "$(git ls-remote "$O2" refs/heads/main | cut -f1)" = "$GOOD" ]; then ok "push: with a release, main fast-forwards to the SHA"; else bad "push with release" "rc=$rc" "$(cat "$T/p.out")"; fi
if [ "$(git ls-remote "$O2" 'refs/heads/*' | wc -l)" = "$(cd "$S" && git ls-remote "$O2" 'refs/heads/*' | wc -l)" ]; then ok "push: no other ref was created or deleted"; else bad "push touched another ref"; fi
fresh; env PATH="$FAKEBIN:$PATH" FAKE_GH_JSON="$T/s_good.json" GITHUB_REPOSITORY=o/r bash tools/land_check.sh push "$GOOD" > "$T/p.out" 2>&1; rc=$?
if [ "$rc" = 1 ]; then ok "push: the same SHA again: nothing to land, refused"; else bad "push twice" "rc=$rc"; fi
# the script contains one push, bare, no force
if [ "$(grep -c 'git push' "$UNDER")" -ge 1 ]; then ok "static: land_check.sh pushes"; else bad "static: no push found"; fi
if grep -nE 'git push[^#]*(--force|-f |--delete|\+refs|:refs/heads/main[^"]*\+| \+)' "$UNDER" > /dev/null; then bad "static: a force or a delete in the push"; else ok "static: the push carries no force, no +refspec, no delete"; fi
if [ "$(grep -cE '^[^#]*git push' "$UNDER")" = 1 ]; then ok "static: exactly one git push call"; else bad "static: more than one push call"; fi

echo "== the workflow file =="
python3 -I - "$REPO/.github/workflows/land.yml" "$REPO/.github/workflows" << 'PY' > "$T/yml.out" 2>&1
import glob, os, re, sys, yaml
path, wfdir = sys.argv[1:3]
raw = open(path).read()
d = yaml.safe_load(raw)
bad = []
def chk(label, cond):
    print(("  ok   " if cond else "  FAIL ") + label)
    if not cond: bad.append(label)
on = d.get(True, d.get("on"))
chk("trigger: workflow_dispatch and nothing else", list(on.keys()) == ["workflow_dispatch"])
inp = on["workflow_dispatch"]["inputs"]
chk("input sha: required string", inp["sha"]["required"] is True and inp["sha"]["type"] == "string")
chk("input dry_run: boolean, default TRUE", inp["dry_run"]["type"] == "boolean" and inp["dry_run"]["default"] is True)
chk("input set_may_shrink: default false", inp["set_may_shrink"]["default"] is False)
chk("workflow permissions: empty", d["permissions"] == {})
jobs = d["jobs"]
chk("two jobs: decide, land", list(jobs) == ["decide", "land"])
for name, j in jobs.items():
    w = [k for k, v in j["permissions"].items() if v == "write"]
    chk("job %s lists its own permissions" % name, "permissions" in j)
    chk("job %s: write scopes = %s" % (name, w), w == (["contents"] if name == "land" else []))
chk("land: contents write and statuses read only", jobs["land"]["permissions"] == {"contents": "write", "statuses": "read"})
chk("land: needs decide, skipped in a dry run", jobs["land"]["needs"] == "decide" and "inputs.dry_run" in jobs["land"]["if"] and "landable" in jobs["land"]["if"])
chk("land: environment land", jobs["land"].get("environment") == "land")
chk("land: the set_may_shrink input reaches push (it reads the gate-set row again)", "set_may_shrink" in jobs["land"]["env"]["LAND_SET_MAY_SHRINK"])
chk("decide: the inputs reach the steps only through env", all("inputs." in v for v in (jobs["decide"]["env"]["SHA"], jobs["decide"]["env"]["LAND_DRY_RUN"], jobs["decide"]["env"]["LAND_SET_MAY_SHRINK"])))
runs = [s["run"] for j in jobs.values() for s in j["steps"] if "run" in s]
chk("no ${{ }} inside any run: block (inputs go through env)", not any("${{" in r for r in runs))
chk("every run: block calls tools/land_check.sh or checks the ref", all("land_check.sh" in r or "GITHUB_REF" in r for r in runs))
uses = [s["uses"] for j in jobs.values() for s in j["steps"] if "uses" in s]
chk("every action pinned to a 40-hex SHA", uses and all(re.fullmatch(r"[\w./-]+@[0-9a-f]{40}", u.split()[0]) for u in uses))
chk("no secrets.* anywhere (no PAT)", "secrets." not in raw)
chk("no pull_request_target / push trigger text", "pull_request_target" not in raw and "\n  push:" not in raw)
chk("decide: checkout of main, credentials not persisted", any(s.get("with", {}).get("ref") == "main" and s["with"].get("persist-credentials") is False for s in jobs["decide"]["steps"] if "uses" in s))
chk("no step sets a token except the two reads", sum("GH_TOKEN" in s.get("env", {}) for j in jobs.values() for s in j["steps"]) == 3)
chk("the push line is the bare land_check push", sum("push" in r for r in runs) == 1)
chk("no `--no-verify`, no `--force` in the file", "--no-verify" not in raw and "--force" not in raw)
# the names of the jobs of the OTHER workflows: none of ours may collide (main's ruleset requires checks by job name)
others = set()
for f in glob.glob(os.path.join(wfdir, "*.yml")):
    if os.path.basename(f) == "land.yml": continue
    for jn, j in (yaml.safe_load(open(f)).get("jobs") or {}).items():
        others.add(jn); others.add(str(j.get("name", jn)))
mine = {jn for jn in jobs} | {j["name"] for j in jobs.values()}
chk("no job id or name collides with another workflow's: %s" % sorted(mine & others), not (mine & others))
chk("workflow name is its own", d["name"] == "Land (fast-forward main)")
sys.exit(1 if bad else 0)
PY
yrc=$?
cat "$T/yml.out"
ok_n="$(grep -c '^  ok ' "$T/yml.out")"; bad_n="$(grep -c '^  FAIL ' "$T/yml.out")"
pass=$((pass + ok_n)); fail=$((fail + bad_n))
[ "$yrc" -ne 0 ] && [ "$bad_n" = 0 ] && { fail=$((fail + 1)); echo "  FAIL workflow structure script died"; }
# the linters RUN when they are on PATH (CI must install the pinned versions of the design note, section 8); the SKIPPED line is only
# for "not installed"; actionlint finds shellcheck itself and checks the run: blocks too
if command -v shellcheck > /dev/null 2>&1; then
    if (cd "$REPO" && shellcheck -x tools/land_check.sh tools/test_land_check.sh tools/mutate_land_check.sh) > "$T/sc.out" 2>&1; then ok "shellcheck $(shellcheck --version | awk '/^version:/ {print $2}'): clean on the three scripts"
    else bad "shellcheck" "$(head -8 "$T/sc.out")"; fi
else echo "  SKIPPED shellcheck (not installed)"; fi
if command -v actionlint > /dev/null 2>&1; then
    if (cd "$REPO" && actionlint .github/workflows/land.yml) > "$T/al.out" 2>&1; then ok "actionlint $(actionlint -version | head -1): clean on land.yml"; else bad "actionlint" "$(head -8 "$T/al.out")"; fi
else echo "  SKIPPED actionlint (not installed)"; fi
# the files hold no strong D-0164 term of their own
. "$REPO/tools/githooks/dterm.sh"
tail -n +1 "$REPO/tools/land_check.sh" "$REPO/tools/mutate_land_check.sh" "$REPO/.github/workflows/land.yml" "$REPO/evidence/land_approvers.txt" |
    d0164_filter | grep -iE "$TERMS164" > "$T/self.txt"
if [ ! -s "$T/self.txt" ]; then ok "the new files hold no D-0164 term"; else bad "D-0164 term in the new files" "$(head -3 "$T/self.txt")"; fi

echo "test_land_check: $pass passed, $fail failed"
[ "$fail" = 0 ]
