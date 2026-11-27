#!/usr/bin/env bash
# ORIGINAL: no swipl-devel counterpart — the decision steps of .github/workflows/land.yml (audit D-0912, D-0922 (3)(a)).
# Run by the workflow, or by hand for a dry look at a SHA:   bash tools/land_check.sh <step> <sha>
#
# Every step is FAIL-CLOSED and records one row in $LAND_WORK/rows.tsv (name, PASS|FAIL, detail). A step never ends the
# run on a FAIL: it writes the row and returns 0, so the table shows every condition; `decide` is the only gate, and a
# row that is missing counts as FAIL.
#
#   input   SHA                the argument is 40 lower-case hex digits
#   git     SHA                (a) SHA is the tip of an origin gate branch (fetched from there), main is its ancestor,
#                              there is something to land, `linear`: `git log --merges main..SHA` is EMPTY (main takes only
#                              linear history, A-0206; the ruleset refuses a merge commit, this refuses it first, and an
#                              unreadable range is a FAIL), ONE author/committer identity, the D-0164 scan of the added
#                              lines and the commit messages is clean (tools/githooks/dterm.sh, the ONE definition)
#   gateset SHA                the candidate's evidence/gate_set.txt, evidence/equivalents.tsv and evidence/survivors.tsv are
#                              extracted to $LAND_WORK; the gate set does not shrink against main unless LAND_SET_MAY_SHRINK=true;
#                              the REFERENCE copies of equivalents.tsv and survivors.tsv come from MAIN's tree: every row ADDED or
#                              REMOVED versus main is printed by `decide`, a row added with no D-entry id is a FAIL, and the ids of
#                              the added rows (`D-NNNN:MUTANT`) are recorded for `marker`
#   verdicts SHA               (b) tools/verdict_read.py (from the TRUSTED tree: main) with --set and --json: CI, Evidence and
#                              every battery of the set read at that exact SHA; the equivalents come from evidence/equivalents.tsv
#   marker  SHA                (c) the audit's release: the ONLY step that knows how the marker is read (see evidence/R2/land_yml_design.md);
#                              the statuses are read from the LIST endpoint `commits/<sha>/statuses` (paged; read_statuses keeps the newest
#                              of each context);
#                              the status description is `LAND <sha>` or `LAND <sha> [ids: D-NNNN:MUTANT,D-NNNN,...]` and the ids it names
#                              must be exactly the rows the SHA adds to the evidence files (a bare D-NNNN covers every added row citing it)
#   decide                     print the decision table; LAND_DRY_RUN=true: exit 0 whatever it says; else exit 1 unless every row is PASS
#   push    SHA                the fast-forward of main: `git` (with `linear`), `gateset` and `marker` again on fresh state, then ONE bare
#                              `git push origin <sha>:refs/heads/main` (no force, no merge, no other ref)
#
# Environment: LAND_WORK (scratch dir, default $RUNNER_TEMP/land_work), LAND_BASE (default origin/main), LAND_IDENTITY
# (default: the repo's one configured identity), LAND_BRANCH_GLOB (default refs/heads/gate/*), GH_TOKEN (the default
# GITHUB_TOKEN: read-only calls; handed to tools/ci_api.sh through a credential helper that reads the variable, never written
# to a file or an argument), LAND_VERDICT_READ and LAND_BUDGET (test seams / API budget), LAND_CHANNEL (the channel file the reader
# reads for a `local: <row id> @<A-entry ref>` release item of a cap-cancelled battery row, D-1009 (5); unset = the reader's default, and
# a missing file fails that item closed; the item's format is in the header of tools/verdict_read.py; a `:`-separated list names several files,
# the D-entry headings of a `tree-ruling` / `stand` item are read from them too). The verdicts step also hands the reader the statuses of
# `commits/<sha>/statuses`, collapsed by read_statuses to the newest per context (--statuses), and evidence/land_approvers.txt
# (--approvers): a `land/local/<ROW>` status releases a `local:` item (LAND-TOOL-3).
# A token is never printed. Only GET calls are made, apart from the final `git push`.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAND_WORK="${LAND_WORK:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}/land_work}"
LAND_BASE="${LAND_BASE:-origin/main}"
LAND_IDENTITY="${LAND_IDENTITY:-Shivaji Gadde <11524260+sivaji1012@users.noreply.github.com>}"
LAND_BRANCH_GLOB="${LAND_BRANCH_GLOB:-refs/heads/gate/*}"
LAND_BUDGET="${LAND_BUDGET:-250}"
TAB=$'\t'
ROWS="$LAND_WORK/rows.tsv"
REQUIRED_ROWS="input gate-tip ancestry linear author d0164 gateset verdicts marker"
mkdir -p "$LAND_WORK"
cd "$ROOT" || exit 64

# row NAME STATUS DETAIL: replace the row of this name (a re-run never leaves two)
row() {
    local name="$1" status="$2" detail="${3:-}"
    detail="$(printf '%s' "$detail" | tr '\t\n' '  ' | cut -c1-400)"
    if [ -f "$ROWS" ]; then
        grep -v "^$name$TAB" "$ROWS" > "$ROWS.new" 2> /dev/null
        mv "$ROWS.new" "$ROWS"
    fi
    printf '%s\t%s\t%s\n' "$name" "$status" "$detail" >> "$ROWS"
}

valid_sha() { [[ "${1:-}" =~ ^[0-9a-f]{40}$ ]]; }
# OWNER/REPO of origin, used when GITHUB_REPOSITORY is unset (never printed raw: only the slug leaves the pipe)
repo_slug() { git remote get-url origin 2> /dev/null | sed -E 's#^.*github\.com[:/]##; s#\.git$##'; }

# read_statuses REPO SHA OUT ERR: the commit statuses of SHA from the LIST endpoint `commits/<sha>/statuses` (its entries carry
# creator.login; the combined answer `commits/<sha>/status` does not), written to OUT as {"sha": SHA, "statuses": [...]} with the
# newest entry of each context only. The list is not collapsed per context: that is done here, by the greatest (created_at, id),
# so a later post revokes an earlier one. Fail closed: return 1 and no OUT if a page cannot be read or is no JSON list, if an
# entry lacks context, created_at or id, or if all 10 pages (1000 statuses) are full: the list may go on. ERR's last line says why.
read_statuses() {
    local repo="$1" sha="$2" out="$3" err="$4" page n=100
    local -a pages=()
    rm -f "$out"
    : > "$err"
    for page in 1 2 3 4 5 6 7 8 9 10; do
        gh api "repos/$repo/commits/$sha/statuses?per_page=100&page=$page" > "$out.page$page" 2> "$err" || return 1
        n="$(python3 -I -c 'import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
if not isinstance(d, list):
    sys.exit(1)
print(len(d))' "$out.page$page" 2> /dev/null)" || { echo "page $page of the status list is not a JSON list" >> "$err"; return 1; }
        pages+=("$out.page$page")
        [ "$n" -lt 100 ] && break
    done
    [ "$n" -lt 100 ] || { echo "10 full pages of statuses: the list may go on" >> "$err"; return 1; }
    python3 -I - "$out" "$sha" "${pages[@]}" 2>> "$err" << 'PY'
import json, sys
out, sha = sys.argv[1:3]
latest = {}
try:
    for path in sys.argv[3:]:
        for s in json.load(open(path, encoding="utf-8")):
            ctx, when, key = s["context"], s["created_at"], int(s["id"])
            if not (isinstance(ctx, str) and isinstance(when, str)):
                raise ValueError(ctx)
            if ctx not in latest or (when, key) > latest[ctx][0]:
                latest[ctx] = ((when, key), s)
except (KeyError, TypeError, ValueError):
    sys.exit("a status entry lacks context, created_at or id")
text = json.dumps({"sha": sha, "statuses": [s for _, s in latest.values()]})
open(out, "w", encoding="utf-8").write(text + "\n")
PY
}

step_input() {
    if valid_sha "$1"; then row input PASS "$1"; else row input FAIL "not 40 lower-case hex digits"; return 1; fi
}

# the base, the gate tip, ancestry, author, D-0164: one function, run by `git` and again by `push`
step_git() {
    local sha="$1" refs line ref tip br="" n idents m d dh mh base ml
    base="$(git rev-parse --verify --quiet "$LAND_BASE^{commit}")" || {
        row gate-tip FAIL "base $LAND_BASE does not resolve"; row ancestry FAIL "base unresolved"; row linear FAIL "base unresolved"
        row author FAIL "base unresolved"; row d0164 FAIL "base unresolved"; return 0; }
    # the SHA must be the TIP of a gate branch of origin: that is where its CI, Evidence and batteries ran (a SHA that is on no
    # branch, or only inside one, fails here); the objects come from that branch ref
    refs="$(git ls-remote origin "$LAND_BRANCH_GLOB" 2> /dev/null)" || refs=""
    while read -r tip ref; do
        [ "$tip" = "$sha" ] && br="$br ${ref#refs/heads/}" && git fetch --no-tags -q origin "$ref:refs/land/tip" 2> /dev/null
    done <<< "$refs"
    if [ -z "$br" ]; then
        row gate-tip FAIL "$sha is the tip of no origin branch matching $LAND_BRANCH_GLOB (not on a gate branch, or only inside one)"
    elif ! git cat-file -e "$sha^{commit}" 2> /dev/null; then
        row gate-tip FAIL "tip of$br but the commit could not be fetched"
    else
        row gate-tip PASS "tip of$br"
    fi
    if ! git cat-file -e "$sha^{commit}" 2> /dev/null; then
        row ancestry FAIL "commit not in the clone"; row linear FAIL "commit not in the clone"; row author FAIL "commit not in the clone"; row d0164 FAIL "commit not in the clone"
        return 0
    fi
    if ! git merge-base --is-ancestor "$base" "$sha" 2> /dev/null; then
        row ancestry FAIL "$LAND_BASE ($(git rev-parse --short=8 "$base")) is NOT an ancestor of the SHA: not a fast-forward"
    else
        n="$(git rev-list --count "$base..$sha")"
        if [ "$n" -gt 0 ]; then row ancestry PASS "$LAND_BASE is an ancestor; $n commit(s) to land"
        else row ancestry FAIL "nothing to land: the SHA is $LAND_BASE itself"; fi
    fi
    # linear: no merge commit anywhere in base..SHA (the base's own history is not read); FAIL closed when the range cannot be read
    if ! ml="$(git log --merges --format='%H %s' "$base..$sha" 2> /dev/null)"; then
        row linear FAIL "the range $LAND_BASE..SHA could not be read"
    elif [ -n "$ml" ]; then
        row linear FAIL "$(printf '%s\n' "$ml" | wc -l) merge commit(s) in $LAND_BASE..SHA, first: $(printf '%s\n' "$ml" | head -1 | cut -c1-120); main takes only linear history (A-0206)"
    else
        row linear PASS "no merge commit in $LAND_BASE..SHA: linear history"
    fi
    idents="$(git log --format='%an <%ae>%n%cn <%ce>' "$base..$sha" | sort -u)"
    if [ -z "$idents" ]; then row author FAIL "no commits in $LAND_BASE..SHA to read an author from"
    elif [ "$(printf '%s\n' "$idents" | wc -l)" -ne 1 ]; then row author FAIL "more than one identity: $(printf '%s' "$idents" | tr '\n' ';')"
    elif [ "$idents" != "$LAND_IDENTITY" ]; then row author FAIL "the one identity is not the repo's: $idents"
    else row author PASS "$idents (author and committer of every commit)"; fi
    # D-0164: exactly the pre-push scan (tools/githooks/pre-push rule 7): the added lines of the cumulative diff, the messages
    if [ ! -f tools/githooks/dterm.sh ]; then row d0164 FAIL "tools/githooks/dterm.sh is not in the trusted tree"; return 0; fi
    # shellcheck source=tools/githooks/dterm.sh
    . tools/githooks/dterm.sh
    d="$(git diff "$base" "$sha")"
    m="$(git log --format='%H %B' "$base..$sha")"
    dh="$(printf '%s\n' "$d" | grep -E '^\+[^+]' | d0164_filter | grep -iE "$TERMS164")"
    mh="$(printf '%s\n' "$m" | d0164_filter | grep -iE "$TERMS164")"
    if [ -n "$dh$mh" ]; then
        row d0164 FAIL "the term grep hits: $(printf '%s' "$dh$mh" | head -c 200)"
    else
        row d0164 PASS "no hit in the added lines or the commit messages"
    fi
    return 0
}

# The data the SHA brings (gate set, equivalents, survivors) is read from the SHA; the REFERENCE copies of equivalents.tsv and
# survivors.tsv are read from MAIN's tree (trusted). Every row ADDED or REMOVED versus main is printed by `decide` (rowdiff.txt);
# a row added with no D-entry id (d_entry empty, or not ^D-[0-9]{4}$) is a FAIL; the ids the audit must name in the release are
# written to added_ids.txt (one `D-NNNN:MUTANT` per line) and read by `marker`. The set may not shrink unless LAND_SET_MAY_SHRINK=true.
step_gateset() {
    local sha="$1" f name cand base_names shrink="" fails="" ref="$LAND_WORK/ref" res
    rm -f "$LAND_WORK/added_ids.txt" "$LAND_WORK/rowdiff.txt"
    mkdir -p "$ref"
    for f in gate_set.txt equivalents.tsv; do
        if ! git show "$sha:evidence/$f" > "$LAND_WORK/$f" 2> /dev/null; then
            row gateset FAIL "evidence/$f is not in the SHA's tree"; return 0
        fi
    done
    git show "$sha:evidence/survivors.tsv" > "$LAND_WORK/survivors.tsv" 2> /dev/null || : > "$LAND_WORK/survivors.tsv"
    cand="$(grep -vE '^[[:space:]]*(#|$)' "$LAND_WORK/gate_set.txt" | awk '{print $1}')"
    if [ -z "$cand" ]; then row gateset FAIL "the gate set names no battery"; return 0; fi
    if base_names="$(git show "$LAND_BASE:evidence/gate_set.txt" 2> /dev/null)"; then
        for name in $(printf '%s\n' "$base_names" | grep -vE '^[[:space:]]*(#|$)' | awk '{print $1}'); do
            printf '%s\n' "$cand" | grep -qx "$name" || shrink="$shrink $name"
        done
    fi
    if [ -n "$shrink" ] && [ "${LAND_SET_MAY_SHRINK:-false}" != true ]; then
        fails="the set shrinks against $LAND_BASE, dropped:$shrink (input set_may_shrink)"
    fi
    {
        for f in equivalents.tsv survivors.tsv; do
            git show "$LAND_BASE:evidence/$f" > "$ref/$f" 2> /dev/null ||
                { : > "$ref/$f"; echo "note: $LAND_BASE has no evidence/$f: every row of the SHA's copy counts as added"; }
        done
        python3 -I - "$ref/equivalents.tsv" "$LAND_WORK/equivalents.tsv" "$ref/survivors.tsv" "$LAND_WORK/survivors.tsv" \
            "$LAND_WORK/added_ids.txt" << 'PY'
import re, sys
refeq, caneq, refsv, cansv, idsout = sys.argv[1:6]
DID = re.compile(r"^D-[0-9]{4}$")
def load(path, header):
    rows = []
    try:
        lines = open(path, encoding="utf-8").read().splitlines()
    except OSError:
        return rows
    for ln in lines:
        if not ln.strip() or ln.lstrip().startswith("#"):
            continue
        f = [c.strip().replace("`", "'") for c in ln.split("\t")]
        if f[0] != header:
            rows.append(f + [""] * (5 - len(f)))
    return rows
out, fails, tokens = [], [], set()
# equivalents.tsv: mutant, d_entry, case_analysis; a row is keyed by (mutant, d_entry); a moved case-analysis line is "changed"
r, c = ({(f[0], f[1]): f for f in load(p, "mutant")} for p in (refeq, caneq))
added = [c[k] for k in c if k not in r]
removed = [r[k] for k in r if k not in c]
changed = [c[k] for k in c if k in r and c[k] != r[k]]
for f in added:
    out.append("+ equivalents.tsv  mutant %s  d_entry %s  %s" % (f[0], f[1] or "(EMPTY)", f[2]))
    if not f[0]:
        fails.append("an added equivalents row names no mutant")
    elif not DID.match(f[1]):
        fails.append("equivalents row %s added with no D-entry id (d_entry %r)" % (f[0], f[1]))
    else:
        tokens.add("%s:%s" % (f[1], f[0]))
for f in removed:
    out.append("- equivalents.tsv  mutant %s  d_entry %s  %s" % (f[0], f[1], f[2]))
for f in changed:
    out.append("~ equivalents.tsv  mutant %s  d_entry %s  case analysis moved: %s (was %s)" % (f[0], f[1], f[2], r[(f[0], f[1])][2]))
# survivors.tsv: battery, mutant, owner, status, d_entry (first_seen/last_seen change on every ledger write and are not compared)
rs = {tuple(f[:5]) for f in load(refsv, "battery")}
cs = {tuple(f[:5]) for f in load(cansv, "battery")}
sadd, srem = sorted(cs - rs), sorted(rs - cs)
for f in sadd:
    out.append("+ survivors.tsv  battery %s  mutant %s  owner %s  status %s  d_entry %s" % (f[0], f[1], f[2] or "(none)", f[3], f[4] or "(none)"))
    if f[3] == "accepted equivalent":
        if not DID.match(f[4]):
            fails.append("survivors row %s/%s added as an accepted equivalent with no D-entry id (d_entry %r)" % (f[0], f[1], f[4]))
        else:
            tokens.add("%s:%s" % (f[4], f[1]))
for f in srem:
    out.append("- survivors.tsv  battery %s  mutant %s  owner %s  status %s  d_entry %s" % (f[0], f[1], f[2] or "(none)", f[3], f[4] or "(none)"))
if not out:
    out.append("no row added, removed or changed in evidence/equivalents.tsv or evidence/survivors.tsv versus main")
open(idsout, "w").write("".join(t + "\n" for t in sorted(tokens)))
summary = "equivalents +%d -%d ~%d, survivors +%d -%d; ids the release must name: %s" % (
    len(added), len(removed), len(changed), len(sadd), len(srem), ",".join(sorted(tokens)) or "none")
print(("FAIL" if fails else "PASS") + "\t" + summary + ("; " + "; ".join(fails) if fails else ""))
print("\n".join(out))
PY
    } > "$LAND_WORK/rowdiff.raw"
    res="$(awk -F'\t' '$1 == "PASS" || $1 == "FAIL" {print; exit}' "$LAND_WORK/rowdiff.raw")"
    awk -F'\t' '!($1 == "PASS" || $1 == "FAIL")' "$LAND_WORK/rowdiff.raw" > "$LAND_WORK/rowdiff.txt"
    case "${res%%"$TAB"*}" in
        PASS) ;;
        FAIL) fails="${fails:+$fails; }${res#*"$TAB"}" ;;
        *) fails="${fails:+$fails; }the row diff of equivalents.tsv/survivors.tsv could not be computed" ;;
    esac
    if [ -n "$fails" ]; then row gateset FAIL "$fails"; return 0; fi
    row gateset PASS "$(printf '%s\n' "$cand" | wc -l) batteries named${shrink:+; shrink allowed, dropped:$shrink}; ${res#*"$TAB"}"
    return 0
}

step_verdicts() {
    local sha="$1" vr="${LAND_VERDICT_READ:-$ROOT/tools/verdict_read.py}" out="$LAND_WORK/verdicts.json" rc
    if [ ! -f "$vr" ]; then row verdicts FAIL "tools/verdict_read.py is not in the trusted tree (land the reader first)"; return 0; fi
    if [ ! -s "$LAND_WORK/gate_set.txt" ]; then row verdicts FAIL "the gate set was not extracted (gateset step)"; return 0; fi
    rm -f "$out"
    # inside Actions tools/ci_api.sh gets the token through `git credential fill`: a helper that reads $GH_TOKEN at call time
    if [ -n "${GH_TOKEN:-}" ]; then
        export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=credential.helper
        # shellcheck disable=SC2016 # single quotes on purpose: the helper must expand $GH_TOKEN when git calls it, never here
        export GIT_CONFIG_VALUE_0='!f() { echo username=x-access-token; echo "password=$GH_TOKEN"; }; f'
    fi
    # the audit's release text (an approver's success `land/approved` status): the reader needs its `src-diff <sha256>` token for a
    # non-empty src diff (D-1006 (2)); no readable release is no argument, and the reader then fails a non-empty src diff
    local rel="" stat="" repo="${GITHUB_REPOSITORY:-}"
    [ -n "$repo" ] || repo="$(repo_slug)"
    if [ -n "$repo" ] && [ -s "$ROOT/evidence/land_approvers.txt" ] && command -v gh > /dev/null 2>&1 &&
        read_statuses "$repo" "$sha" "$LAND_WORK/release.json" "$LAND_WORK/release.err"; then
        # LAND-TOOL-3: the same answer also carries the `land/local/<ROW>` statuses; the reader checks their creator against the approvers
        # file itself (no answer, no gh, no approvers file: no --statuses, and the status route of a `local:` item stays closed)
        stat="$LAND_WORK/release.json"
        rel="$(python3 -I - "$LAND_WORK/release.json" "$ROOT/evidence/land_approvers.txt" << 'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    allowed = {l.strip().lower() for l in open(sys.argv[2]) if l.strip() and not l.lstrip().startswith("#")}
    sts = [s for s in d.get("statuses") or [] if s.get("context") == "land/approved"]
    s = sts[0] if sts else {}
    if s.get("state") == "success" and ((s.get("creator") or {}).get("login") or "").lower() in allowed:
        print((s.get("description") or "").replace("\n", " "))
except Exception:
    pass
PY
)"
    fi
    python3 -I "$vr" "$sha" --base "$LAND_BASE" ${rel:+--release "$rel"} ${LAND_CHANNEL:+--channel "$LAND_CHANNEL"} ${stat:+--statuses "$stat" --approvers "$ROOT/evidence/land_approvers.txt"} --set "$LAND_WORK/gate_set.txt" --equivalents "$LAND_WORK/equivalents.tsv" \
        --survivors "$LAND_WORK/survivors.tsv" --json --budget "$LAND_BUDGET" --cache "$LAND_WORK/cache" --root "$ROOT" \
        > "$out" 2> "$LAND_WORK/verdicts.err"
    rc=$?
    python3 -I - "$out" "$rc" "$LAND_WORK/verdicts.err" << 'PY' > "$LAND_WORK/verdicts.row"
import json, sys
path, rc, err = sys.argv[1], int(sys.argv[2]), sys.argv[3]
try:
    r = json.load(open(path))
except Exception as e:  # unreadable output is a FAIL, whatever the exit code
    tail = open(err).read().strip().splitlines()[-1:] or [""]
    print("FAIL\treader exit %d, output unreadable (%s) %s" % (rc, type(e).__name__, tail[0][:150]))
    sys.exit(0)
bats = r.get("batteries") or []
blocked = [b.get("name", "?") for b in bats if not b.get("clean") and b.get("state") != "pending"]
pending = [b.get("name", "?") for b in bats if b.get("state") == "pending"]
land_fail = [c.get("check", "?") for c in r.get("landing") or [] if not c.get("ok")]
src_note = "; ".join("src diff: " + (c.get("text") or "")[:600] for c in r.get("landing") or []
                     if c.get("check") == "src diff" and c.get("text") != "empty")
ok = rc == 0 and r.get("landable") is True and bool(bats)
detail = "exit %d, landable=%s, CI=%s, Evidence=%s, %d batteries read" % (
    rc, r.get("landable"), "ok" if r.get("ci_ok") else "NOT ok", "ok" if r.get("ev_ok") else "NOT ok", len(bats))
if not ok:
    if blocked: detail += "; blocked: " + ",".join(blocked)
    if pending: detail += "; pending: " + ",".join(pending)
    if land_fail: detail += "; landing checks failed: " + ",".join(land_fail)
    if r.get("gate_why"): detail += "; set: " + r["gate_why"]
    if not bats: detail += "; no battery read"
print("%s\t%s" % ("PASS" if ok else "FAIL", detail + ("; " + src_note if src_note else "")))
PY
    IFS=$'\t' read -r st detail < "$LAND_WORK/verdicts.row"
    row verdicts "${st:-FAIL}" "${detail:-reader summary unreadable}"
    return 0
}

# THE ONLY STEP THAT KNOWS HOW THE AUDIT'S RELEASE IS READ. Option C of the design note: a commit status on the exact SHA, context
# `land/approved`, state success, description `LAND <sha>`, created by a login listed in evidence/land_approvers.txt of the trusted tree.
# Read through read_statuses (the list endpoint: only its entries carry the creator); the newest land/approved post decides.
# Replacing this function (a tag `land/<sha>`, a repository variable) changes nothing else.
step_marker() {
    local sha="$1" repo="${GITHUB_REPOSITORY:-}" ap="$ROOT/evidence/land_approvers.txt" json="$LAND_WORK/marker.json" res
    [ -n "$repo" ] || repo="$(repo_slug)"
    if [ ! -s "$ap" ] || ! grep -qvE '^[[:space:]]*(#|$)' "$ap"; then
        row marker FAIL "evidence/land_approvers.txt names no approver (fail closed)"; return 0
    fi
    if ! command -v gh > /dev/null 2>&1; then row marker FAIL "gh is not available"; return 0; fi
    if ! read_statuses "$repo" "$sha" "$json" "$LAND_WORK/marker.err"; then
        row marker FAIL "the status of the commit could not be read: $(tail -n 1 "$LAND_WORK/marker.err" | cut -c1-150)"; return 0
    fi
    res="$(python3 -I - "$json" "$sha" "$ap" "$LAND_WORK/added_ids.txt" << 'PY'
import json, re, sys
path, sha, ap, idsfile = sys.argv[1:5]
DESC = re.compile(r"^LAND ([0-9a-f]{40})(?: \[ids: ([^\]]*)\])?$")
try:
    d = json.load(open(path))
    allowed = {l.strip().lower() for l in open(ap) if l.strip() and not l.lstrip().startswith("#")}
    sts = [s for s in d.get("statuses") or [] if s.get("context") == "land/approved"]
    if not sts:
        print("FAIL\tno land/approved status on the commit"); sys.exit(0)
    s = sts[0]  # the combined status answers the latest per context: a later failure revokes
    who = ((s.get("creator") or {}).get("login") or "").lower()
    if s.get("state") != "success":
        print("FAIL\tland/approved is %s, not success" % s.get("state"))
    elif not (m := DESC.match(s.get("description") or "")) or m.group(1) != sha:
        print("FAIL\tland/approved description is not 'LAND <this sha>' (optionally followed by ' [ids: D-NNNN:MUTANT,...]')")
    elif who not in allowed:
        print("FAIL\tland/approved was set by %r, who is not in land_approvers.txt" % who)
    else:
        # the rows this commit ADDS to evidence/equivalents.tsv / survivors.tsv (the gateset step wrote them): the audit's
        # release must name exactly them, `D-NNNN:MUTANT`, or a bare `D-NNNN` for every added row that cites that D-entry
        try:
            required = {l.strip() for l in open(idsfile) if l.strip()}
        except OSError:
            print("FAIL\tno record of the added equivalents rows (the gateset step did not run): fail closed"); sys.exit(0)
        named = {t.strip() for t in (m.group(2) or "").split(",") if t.strip()}
        # `src-diff <sha256>` (D-1006 (2)) is the release of the src diff, read and compared by tools/verdict_read.py; here only its
        # form is checked (one token, 64 lower-case hex digits) and it is no id of an evidence row
        srcrel = sorted(t for t in named if t.startswith("src-diff"))
        named -= set(srcrel)
        if any(not re.fullmatch(r"src-diff [0-9a-f]{64}", t) for t in srcrel):
            print("FAIL\tthe release names a malformed src-diff (wanted `src-diff <64 lower-case hex digits>`)"); sys.exit(0)
        if len(srcrel) > 1:
            print("FAIL\tthe release names more than one src-diff"); sys.exit(0)
        # `local: <row id> @<A-entry ref>` (D-1009 (5), LAND-TOOL-2) releases a cap-cancelled battery row; tools/verdict_read.py checks the
        # channel entry; here only the form (and one item per row) is checked, and it is no id of an evidence row
        locrel = sorted(t for t in named if t.startswith("local"))
        named -= set(locrel)
        LOCF = r"local: [A-Za-z0-9][A-Za-z0-9._-]* @(A-NEXT [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}Z|A-[0-9]{4,})( tree-ruling D-[0-9]{4})?"
        if any(not re.fullmatch(LOCF, t) for t in locrel):
            print("FAIL\tthe release names a malformed local item (wanted `local: <row id> @A-NEXT YYYY-MM-DD HH:MMZ` or `@A-NNNN`, then optionally ` tree-ruling D-NNNN`)"); sys.exit(0)
        if len({t.split(" ")[1] for t in locrel}) != len(locrel):
            print("FAIL\tthe release names a local row twice"); sys.exit(0)
        # `stand: <list> @D-NNNN from <old sha>` (D-1012 (2), LAND-TOOL-3) lets an old-SHA battery stand; tools/verdict_read.py checks the diff
        # and the D-entry; here only the form (and one item per list) is checked, and it is no id of an evidence row
        standrel = sorted(t for t in named if t.startswith("stand"))
        named -= set(standrel)
        STANDF = r"stand: [A-Za-z0-9][A-Za-z0-9._-]* @D-[0-9]{4} from [0-9a-f]{40}"
        if any(not re.fullmatch(STANDF, t) for t in standrel):
            print("FAIL\tthe release names a malformed stand item (wanted `stand: <list> @D-NNNN from <40 lower-case hex>`)"); sys.exit(0)
        if len({t.split(" ")[1] for t in standrel}) != len(standrel):
            print("FAIL\tthe release names a stand list twice"); sys.exit(0)
        uncovered = sorted(t for t in required if t not in named and t.split(":")[0] not in named)
        unused = sorted(t for t in named if t not in required and not any(r.split(":")[0] == t for r in required))
        if uncovered:
            print("FAIL\trows added to the evidence files are not named in the release: %s" % ",".join(uncovered))
        elif unused:
            print("FAIL\tthe release names ids this commit does not add: %s" % ",".join(unused))
        else:
            print("PASS\tland/approved success, description LAND %s, set by %s, ids named: %s (rows added: %d)%s" % (
                sha[:8], who, ",".join(sorted(named)) or "none", len(required), ("; " + srcrel[0]) if srcrel else "") + "".join("; " + t for t in locrel) + "".join("; " + t for t in standrel))
except Exception as e:
    print("FAIL\tmarker unreadable (%s)" % type(e).__name__)
PY
)"
    row marker "${res%%"$TAB"*}" "${res#*"$TAB"}"
    return 0
}

step_decide() {
    local name st detail all=PASS missing="" table="" line
    for name in $REQUIRED_ROWS; do
        line="$(grep "^$name$TAB" "$ROWS" 2> /dev/null)"
        if [ -z "$line" ]; then st=FAIL; detail="no row was written (step did not run)"; missing="$missing $name"
        else IFS=$'\t' read -r _ st detail <<< "$line"; fi
        [ "$st" = PASS ] || all=FAIL
        table="$table$(printf '| %-9s | %-4s | %s |' "$name" "$st" "$detail")"$'\n'
    done
    {
        printf '| condition | rule | detail |\n|---|---|---|\n%s\n' "$table"
        if [ "${LAND_DRY_RUN:-true}" = true ]; then
            [ "$all" = PASS ] && echo "DRY RUN: every condition holds, a real run would fast-forward main to ${1:-the SHA}." ||
                echo "DRY RUN: a real run would REFUSE (see the FAIL rows)."
        else
            [ "$all" = PASS ] && echo "LAND: every condition holds." || echo "REFUSED: not every condition holds."
        fi
        printf '\nRows ADDED (+), REMOVED (-) or CHANGED (~) in evidence/equivalents.tsv and evidence/survivors.tsv versus %s:\n\n```\n' "$LAND_BASE"
        if [ -f "$LAND_WORK/rowdiff.txt" ]; then cat "$LAND_WORK/rowdiff.txt"; else echo "not computed: the gateset step did not run (its row is a FAIL)"; fi
        printf '```\n'
    } | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"
    [ -n "${GITHUB_OUTPUT:-}" ] && echo "landable=$([ "$all" = PASS ] && echo true || echo false)" >> "$GITHUB_OUTPUT"
    [ "${LAND_DRY_RUN:-true}" = true ] && return 0
    [ "$all" = PASS ]
}

step_push() {
    local sha="$1"
    step_input "$sha" || { echo "push refused: bad SHA"; return 1; }
    git fetch --no-tags -q origin main:refs/remotes/origin/main || { echo "push refused: cannot fetch main"; return 1; }
    step_git "$sha"
    step_gateset "$sha"
    step_marker "$sha"
    for name in input gate-tip ancestry linear author d0164 gateset marker; do
        if ! grep -q "^$name${TAB}PASS$TAB" "$ROWS"; then echo "push refused: $name: $(grep "^$name$TAB" "$ROWS")"; return 1; fi
    done
    # ONE bare fast-forward: the server refuses a non-fast-forward; no `+`, no force option, no other ref
    git push origin "$sha:refs/heads/main" || { echo "push failed (a race with another push to main, or the ruleset refused it)"; return 1; }
    echo "main is now: $(git ls-remote origin refs/heads/main)"
}

cmd="${1:-}"
sha="${2:-}"
case "$cmd" in
    input) step_input "$sha" || true ;;
    push) step_push "$sha" ;;
    git | gateset | verdicts | marker)
        # a bad SHA is a recorded FAIL (the `input` row), not a dead end: the table still prints and `decide` refuses
        if ! step_input "$sha"; then echo "land_check: $cmd needs a 40-hex SHA"; exit 0; fi
        case "$cmd" in
            git) step_git "$sha" ;;
            gateset) step_gateset "$sha" ;;
            verdicts) step_verdicts "$sha" ;;
            marker) step_marker "$sha" ;;
        esac ;;
    decide) step_decide "$sha" ;;
    *) echo "usage: land_check.sh input|git|gateset|verdicts|marker|decide|push <sha>"; exit 64 ;;
esac
