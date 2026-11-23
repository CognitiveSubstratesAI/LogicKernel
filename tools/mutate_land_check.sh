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
VSRC="$HERE/verdict_read.py"
VTEST="$HERE/test_verdict_read.py"
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
 ("S1", "marker: a malformed src-diff token (63 digits, upper case, no digest) is accepted", 'if any(not re.fullmatch(r"src-diff [0-9a-f]{64}", t) for t in srcrel):', 'if False:'),
 ("S2", "marker: a src-diff token is counted as an evidence-row id (a release carrying one fails as unused)", 'named -= set(srcrel)', 'pass'),
 ("S3", "marker: two src-diff tokens are accepted", 'if len(srcrel) > 1:', 'if False:'),
 ("S4", "verdicts: the release is never handed to the reader", '${rel:+--release "$rel"}', ''),
 ("S5", "verdicts: the release is read from ANY creator, not only an approver", 'if s.get("state") == "success" and ((s.get("creator") or {}).get("login") or "").lower() in allowed:', 'if s.get("state") == "success":'),
 ("S6", "verdicts: the release is read whatever the state of the status", 'if s.get("state") == "success" and ((s.get("creator") or {}).get("login") or "").lower() in allowed:', 'if ((s.get("creator") or {}).get("login") or "").lower() in allowed:'),
 ("S7", "verdicts: the src diff text (numstat, sha256) is not shown in the row", 'detail + ("; " + src_note if src_note else "")', 'detail'),
 ("S8", "marker: a malformed local item (no ref, a ref that is no A-entry heading) is accepted", 'if any(not re.fullmatch(LOCF, t) for t in locrel):', 'if False:'),
 ("S9", "marker: a local item is counted as an evidence-row id (a release carrying one fails as unused)", 'named -= set(locrel)', 'pass'),
 ("S10", "marker: one row named by two local items is accepted", 'if len({t.split(" ")[1] for t in locrel}) != len(locrel):', 'if False:'),
 ("S11", "verdicts: LAND_CHANNEL is never handed to the reader", '${LAND_CHANNEL:+--channel "$LAND_CHANNEL"}', ''),
 ("S12", "marker: a tree-ruling with no / a malformed D-entry id is accepted", r'( tree-ruling D-[0-9]{4})?"', r'( tree-ruling.*)?"'),
 ("S13", "marker: a malformed stand item is accepted", 'if any(not re.fullmatch(STANDF, t) for t in standrel):', 'if False:'),
 ("S14", "marker: one list named by two stand items is accepted", 'if len({t.split(" ")[1] for t in standrel}) != len(standrel):', 'if False:'),
 ("S15", "marker: a stand item is counted as an evidence-row id (a release carrying one fails as unused)", 'named -= set(standrel)', 'pass'),
 ("S16", "verdicts: the status answer and the approvers file are never handed to the reader (the land/local status route is dead)", '${stat:+--statuses "$stat" --approvers "$ROOT/evidence/land_approvers.txt"}', ''),
 ("S17", "verdicts: --statuses is handed over even when gh could not answer (a stale or empty file is read)", 'local rel="" stat="" repo=', 'local rel="" stat="$LAND_WORK/release.json" repo='),
 ("S18", "verdicts: --approvers is not handed over (the reader sees no approvers: only a closed route, never a wider one; this one widens nothing, so it must still be KILLED by the argument test)", ' --approvers "$ROOT/evidence/land_approvers.txt"}', '}'),
]
# `old` occurs exactly once in tools/verdict_read.py (mutated COPY, checked by tools/test_verdict_read.py, D-1006 (2))
VM = [
 ("R1", "src release: the released digest is not compared with the numstat's (any well-formed digest releases)", "elif good[0] != digest:", "elif False:"),
 ("R2", "src release: the numstat hashed is not the raw bytes git prints (trailing newline stripped)", "digest = hashlib.sha256(ns.stdout).hexdigest()", "digest = hashlib.sha256(ns.stdout.strip()).hexdigest()"),
 ("R3", "src release: a malformed token is not refused as such", "        if bad:\n", "        if False:\n"),
 ("R4", "src release: a second src-diff token is accepted", "elif len(good) > 1:", "elif False:"),
 ("R5", "src release: an empty numstat is not recognised (every diff needs a release, the empty one too)", "elif not ns.stdout.strip():", "elif False:"),
 ("R6", "src release: a missing release passes the check (the digest is taken as the release)", "        elif not good:\n            out.append((\"src diff\", False, \"NON-EMPTY, no `src-diff <sha256>` release; %s\" % shown))\n", "        elif not good:\n            out.append((\"src diff\", True, \"NON-EMPTY, no release; %s\" % shown))\n"),
 ("R7", "src release: the row does not print the numstat's sha256 (the audit cannot compare)", '"sha256 %s; numstat (git diff --numstat %s..%s -- src): %s" % (digest, base, sha[:8], "; ".join(', '"numstat (git diff --numstat %s..%s -- src): %s" % (base, sha[:8], "; ".join('),
 ("R8", "local release: the tree of the line is not compared with the landing SHA's tree (any tree releases)", "if t != tree and ruling is None:", "if False:"),
 ("R9", "local release: the verdict word is not checked (TIMEOUT, survived, anything releases)", 'elif w != "caught (hang)":', "elif False:"),
 ("R10", "local release: a NO VERDICT row whose job did NOT conclude cancelled (failed) is releasable", 'elif r.get("jconc") != "cancelled":', "elif False:"),
 ("R11", "local release: a row that is not NO VERDICT (caught, SURVIVED, TIMEOUT, INVALID) is releasable", 'if r["kind"] != "nov":', "if False:"),
 ("R12", "local release: a failed job with no row is releasable whatever it concluded", 'if f["conclusion"] != "cancelled":', "if False:"),
 ("R13", "local release: a missing channel file is not refused (the file is read as empty)", "    if not have_chan:\n        early =", "    if False:\n        early ="),
 ("R14", "local release: a heading that merely STARTS with the ref matches (A-0123 matches A-01234)", 'head[len(ref)] in " \\t"', "True"),
 ("R15", "local release: a line under another entry counts (the file is read as one body)", 'cur = [] if head.startswith(ref) and (len(head) == len(ref) or head[len(ref)] in " \\t") else None', 'cur = [] if head.startswith(ref) and (len(head) == len(ref) or head[len(ref)] in " \\t") else cur if cur is not None else None'),
 ("R16", "local release: one row named twice is accepted", "        if row in seen:", "        if False:"),
 ("R17", "local release: a malformed item is not refused as such", "    if bad:\n        out.append((\"local verdict\", False,", "    if False:\n        out.append((\"local verdict\", False,"),
 ("R18", "local release: a verified release does not lift the failed-job blocker", 'if f["name"] not in nov and (b["name"], f["name"]) not in released:', 'if f["name"] not in nov:'),
 ("R19", "local release: a verified release does not lift the NO VERDICT row (the battery stays blocked)", 'b["counts"]["decided"] + rel_n == b["counts"]["total"]', 'b["counts"]["decided"] == b["counts"]["total"]'),
 ("R20", "local release: the same row id cancelled in TWO batteries is accepted (ambiguity)", "    if len(rel) != 1:", "    if len(rel) < 1:"),
 ("R21", "status route: the creator is not checked against the approvers (any login releases)", "    if who not in allowed:\n        return [], ", "    if False:\n        return [], "),
 ("R22", "status route: the state is not read (pending / failure releases)", '    if x.get("state") != "success":\n        return [], ', '    if False:\n        return [], '),
 ("R23", "tree-ruling: a ruling excuses nothing (the tree must always equal the landing SHA's)", "if t != tree and ruling is None:", "if t != tree:"),
 ("R24", "two sources: a status that disagrees with the channel line(s) is not refused", "    if chan and stat and not all(", "    if False and not all("),
 ("R25", "tree-ruling: the named D-entry need not exist as a heading (nor as a land/ruling status)", "        if not how:\n            return False, \"the item names", "        if False:\n            return False, \"the item names"),
 ("R26", "status route: the row of the description is not compared with the context's row", "    if not m or m.group(1) != row:\n        return [], [", "    if not m:\n        return [], ["),
 ("R27", "status route: the context is matched by its family (land/local/*), not by the row", 'x.get("context") == "land/local/" + row', 'x.get("context", "").startswith("land/local/")'),
 ("R28", "status route: no approvers file is no refusal (the creator check is skipped when none is given)", "    if not statuses or not approvers:\n        return [], []", "    if not statuses:\n        return [], []"),
 ("R29", "tree-ruling: the ruling is dropped on the way to the check (a ruled item is judged as a plain one)", "ok, text, bname = local_release(batteries, row, ref, tree, channels, statuses, approvers, ruling)", "ok, text, bname = local_release(batteries, row, ref, tree, channels, statuses, approvers)"),
 ("R30", "tree-ruling: trailing text after the D id is accepted", r'(?: tree-ruling (D-\d{4}))?$")', r'(?: tree-ruling (D-\d{4}))?.*$")'),
 ("R31", "channels: a `:`-joined value is read as ONE path", "out += [p for p in c.split(os.pathsep) if p and os.path.isfile(p)]", "out += [c] if os.path.isfile(c) else []"),
 ("R32", "stand: the src diff is not part of the diff (only the list file is compared)", '"--", "src", "tools/mutants/%s.py" % lst)', '"--", "tools/mutants/%s.py" % lst)'),
 ("R33", "stand: the list file is not part of the diff (only src is compared)", '"--", "src", "tools/mutants/%s.py" % lst)', '"--", "src")'),
 ("R34", "stand: a non-empty diff is not refused", "            elif d.strip():", "            elif False:"),
 ("R35", "stand: the D-entry need not exist as a heading", "                if not how:\n", "                if False:\n"),
 ("R36", "stand: a list file that exists at neither SHA gives a vacuously empty diff (accepted)", 'elif any(git(root, "cat-file", "-e", "%s:tools/mutants/%s.py" % (c, lst))[0] != 0 for c in (old, sha)):', "elif False:"),
 ("R37", "stand: a list with a battery run at the landing SHA is accepted (the item masks the run)", "        elif lst in have:", "        elif False:"),
 ("R38", "stand: a list outside the gate set is accepted", "if gate_set is not None and lst not in {n for n, _ in gate_set}:", "if False:"),
 ("R39", "stand: a standing list is still `no run and no clean read` (the gate set is not covered)", 'and not g["last_clean"] and g["name"] not in stood]', 'and not g["last_clean"]]'),
 ("R40", "stand: one list named twice is accepted", "        if lst in seen:", "        if False:"),
 ("R41", "stand: a malformed item is not refused as such", '    if bad:\n        out.append(("stand", False,', '    if False:\n        out.append(("stand", False,'),
 ("R42", "stand: an old SHA that is no commit is not refused as such", 'elif git(root, "cat-file", "-e", old + "^{commit}")[0] != 0:', "elif False:"),
 ("R43", "stand: upper-case hex accepted in the old SHA", r'from ([0-9a-f]{40})$")', r'from ([0-9a-fA-F]{40})$")'),
 ("R44", "stand: the checks are not part of the landing checks (never refuse)", "landing += lc + sc", "landing += lc"),
 ("R45", "stand: what stands is not handed to the judge (the set stays uncovered)", "judge(res, eqs, ledger, gate_set, released, stood)", "judge(res, eqs, ledger, gate_set, released)"),
 # LAND-TOOL-3b (audit D-1013 (1)): the land/ruling/D-NNNN status for a tree-ruling or stand D-entry
 ("R46", "ruling status: the creator is not checked against the approvers (any login releases)", '    if who not in allowed:\n        return False, ["the land/ruling', '    if False:\n        return False, ["the land/ruling'),
 ("R47", "ruling status: the state is not read (pending / failure releases)", '    if x.get("state") != "success":\n        return False, ["the land/ruling', '    if False:\n        return False, ["the land/ruling'),
 ("R48", "ruling status: the context is not the D-entry's (any land/ status releases any D-entry)", 'x.get("context") == "land/ruling/" + did', 'x.get("context", "").startswith("land/")'),
 ("R49", "ruling source: the status is never consulted (the heading is the only source)", "    ok, notes = ruling_status(statuses, approvers, did)", "    ok, notes = False, []"),
 ("R50", "ruling source: a refused status releases (the answer of ruling_status is ignored)", '    return ("status" if ok else ""), notes', '    return "status", notes'),
 ("R51", "ruling source: the channel heading is never consulted (the status is the only source)", '    if d_entry_exists(channels, did):\n        return "channel", []', '    if False:\n        return "channel", []'),
 ("R52", "ruling status: no statuses file / no approvers is not a closed route (open(None) raises instead of a refusal)", "    if not statuses or not approvers:\n        return False, []", "    if False:\n        return False, []"),
 ("R53", "ruling status: an unreadable statuses or approvers file RELEASES (fails open)", 'except (OSError, ValueError):\n        return False, ["the status route is closed', 'except (OSError, ValueError):\n        return True, ["the status route is closed'),
 ("R54", "stand: the statuses and approvers are not handed to the D-entry check (a stand item sees only the heading)", "how, rnotes = ruling_source(channels, statuses, approvers, did)", "how, rnotes = ruling_source(channels, None, None, did)"),
 ("R55", "tree-ruling: the statuses and approvers are not handed to the D-entry check", "ruling_source(channels, statuses, approvers, ruling)", "ruling_source(channels, None, None, ruling)"),
 ("R56", "main: the statuses and approvers are not handed to stand_checks", "gate_set, a.release, channels, a.statuses, a.approvers)", "gate_set, a.release, channels)"),
 ("R57", "ruling status: the description must be non-empty (it is irrelevant to the check)", "    return True, []\n\n\ndef ruling_source", "    return bool((x.get(\"description\") or \"\").strip()), []\n\n\ndef ruling_source"),
 ("R58", "stand: a refused D-entry still records the list as standing (the FAIL row stays, but `stood` is set)", "                    continue\n                out.append((name, True,", "                    pass\n                out.append((name, True,"),
]
if __name__ == "__main__":
    cmd = sys.argv[1]
    if cmd == "ids":
        print("\n".join(m[0] for m in M))
    elif cmd == "vids":
        print("\n".join(m[0] for m in VM))
    elif cmd == "what":
        print([m[1] for m in M + VM if m[0] == sys.argv[2]][0])
    elif cmd in ("apply", "check", "vapply", "vcheck"):
        src = open(sys.argv[2]).read()
        bad = 0
        for i, what, old, new in (VM if cmd[0] == "v" else M):
            if cmd in ("check", "vcheck") or i == sys.argv[3]:
                n = src.count(old)
                if n != 1:
                    print("mutant %s: `old` occurs %d times, not once" % (i, n), file=sys.stderr); bad += 1
                elif cmd in ("apply", "vapply"):
                    open(sys.argv[4], "w").write(src.replace(old, new)); break
        else:
            if cmd in ("apply", "vapply"):
                print("no mutant %s" % sys.argv[3], file=sys.stderr); bad += 1
        sys.exit(1 if bad else 0)
PY

if ! python3 -I "$W/mutants.py" check "$SRC" || ! python3 -I "$W/mutants.py" vcheck "$VSRC"; then echo "mutate_land_check: a mutant does not apply (see above)"; exit 2; fi
if [ "${1:-}" = "--check" ]; then echo "every mutant's old text occurs exactly once: $(python3 -I "$W/mutants.py" ids | wc -l) mutants of land_check.sh, $(python3 -I "$W/mutants.py" vids | wc -l) of verdict_read.py"; exit 0; fi

if [ "$#" -gt 0 ]; then ids="$*"; else ids="$(python3 -I "$W/mutants.py" ids) $(python3 -I "$W/mutants.py" vids)"; fi
vids=" $(python3 -I "$W/mutants.py" vids | tr '\n' ' ') "

# the unmutated copy first: through the same seam, it must pass
cp "$SRC" "$W/land_check.base.sh"
if ! LAND_CHECK_UNDER_TEST="$W/land_check.base.sh" bash "$TEST" > "$W/base.log" 2>&1; then
    echo "mutate_land_check: the UNMUTATED copy fails the test; no mutant result means anything"; grep '^  FAIL' "$W/base.log" | head -5; exit 2
fi
echo "baseline: unmutated copy passes ($(tail -1 "$W/base.log"))"
# the verdict_read.py mutants (src-diff release, D-1006 (2)): a COPY of the reader beside its helper module, run by the python test
# (the Landing cases: they hold every row of the src-diff release; the LocalVerdict cases hold the local-verdict ones), the test pointed at the copy through VERDICT_READ_UNDER_TEST
mkdir -p "$W/vr"; cp "$HERE/battery_table.py" "$W/vr/"; cp "$VSRC" "$W/vr/verdict_read.py"
# R1-R7 (src-diff release) run the Landing class, R8 and up (local verdict, D-1009 (5)) the LocalVerdict class; both fail-fast
vtest() { VERDICT_READ_UNDER_TEST="$W/vr/verdict_read.py" python3 -I "$VTEST" -f $1 > "$W/v.log" 2>&1; }
vsel() { case "$1" in R[1-7]) echo Landing ;; R3[2-9] | R4[0-5] | R54 | R56 | R58) echo StandItem ;; R4[6-9] | R5[0-3] | R57) echo "LocalVerdict StandItem" ;; *) echo LocalVerdict ;; esac; }
for cls in Landing LocalVerdict StandItem; do
    if ! vtest "$cls"; then echo "mutate_land_check: the UNMUTATED verdict_read copy fails the $cls tests"; tail -5 "$W/v.log"; exit 2; fi
    echo "baseline: unmutated verdict_read copy passes $cls ($(grep -m1 '^Ran ' "$W/v.log"))"
done

killed=0 total=0
for id in $ids; do
    total=$((total + 1))
    if [[ "$vids" == *" $id "* ]]; then
        if ! python3 -I "$W/mutants.py" vapply "$VSRC" "$id" "$W/vr/verdict_read.py"; then echo "$id: DOES NOT APPLY"; continue; fi
        cmp -s "$VSRC" "$W/vr/verdict_read.py" && { echo "$id: NO CHANGE"; continue; }
        python3 -I -c "import ast,sys; ast.parse(open(sys.argv[1]).read())" "$W/vr/verdict_read.py" || { echo "$id: the mutant is not valid python"; continue; }
        if vtest "$(vsel "$id")"; then echo "$id: SURVIVED ($(python3 -I "$W/mutants.py" what "$id"))"
        else
            killed=$((killed + 1))
            echo "$id: KILLED by [$(grep -m1 -E '^(FAIL|ERROR):' "$W/v.log" | cut -c1-110)]  ($(python3 -I "$W/mutants.py" what "$id"))"
        fi
        cp "$VSRC" "$W/vr/verdict_read.py"
        continue
    fi
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
