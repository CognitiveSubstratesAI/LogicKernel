#!/usr/bin/env bash
# ORIGINAL: the cases of tools/ci_marker.sh, a tool of this repository only (audit D-0680 item 1b; review TOOL4B).
# A FAKE API (CI_MARKER_FIXTURE_DIR: runs_<sha>.json and <run>/jobs_<page>.json, built here from tools/ci_marker_jobs.tsv, the ONE
# definition the tool reads too: from refs/remotes/origin/main of the throw-away repository, set per row, audit D-0693 item 5) and a
# throw-away git repository. The marker writer is a STUB (the tool's `--dry-run --writer-stub FILE` test mode, review2 N1): the REAL
# write path takes no caller-chosen writer and refuses every fixture seam (B1), so no row here writes a marker through the real
# writer with a fixture. The real write_marker is exercised on its own interface (start_marker/write_marker/check_marker as the tool
# calls them, under the tool's `set -u`, no fixture, no API) in one row: it is n/a on a machine without workflows/test_marker.sh, which
# includes CI, so CI never runs the real write path, only the stub (N8). Real-path rows have no fixture and an API sink
# (https_proxy to a closed port, no stored credential): a mutant that lets such a row through cannot reach the live API.
# review4 F2: the tool fixes its own PATH and tools/ci_api.sh calls curl with `-q --noproxy '*'`, so a closed proxy port is no longer a
# net. Every row but pathpy / pathgit therefore runs a COPY of the tool whose PATH line has $W/guard (a curl that logs and exits 7) in
# front (and, for the lsfail rows, the git shim): the live API is unreachable from any row. pathpy / pathgit run the tool itself, with a
# fixture, to prove the PATH line; the curl flags are proved on ci_api.sh directly with a recording curl, never the network.
# Every row has both sides: the all-green fixture is OK and writes a marker (stub mode; plain dry-run: none), and each defect is
# refused with no marker (a failed or missing job, a job named one character differently, a skipped job that must succeed, a job
# that should have been skipped, an unlisted one, a missing, pending, pull_request or other-file workflow run, another SHA, another
# tree, a dirty tree, an assume-unchanged file, a name clash with a green job of ANOTHER run, a stale green run beside a newer red
# one, a failed job on page 2 of the jobs, a job that ran on another SHA or has none, garbled / wrong-total answers, a tsv with a
# duplicate or foreign or missing workflow row, a planted json.py, each seam in the real path, every way to inject a writer in the
# real path (an exported function, a lib that defines only some of the functions, a lib that sources another file, the old writer
# variable with TMPDIR games), a fork as origin, the git environment and a replace ref, a git error in a tree check; a tree under test
# that carries its own lax tsv, origin/main without the file or without the ref, the bootstrap option with and without --dry-run;
# review3: exported functions named like builtins and tools (compgen, python3, builtin, exec, exit, read, git, `.` ...) and the caller's
# BASH_ENV / ENV / PROMPT_COMMAND / CDPATH / PS4 / exported SHELLOPTS / BASHOPTS cannot forge a verdict (privileged mode, exit 2), the
# marker of a stub that follows TMPDIR lands in the tool's throw-away directory, a real run whose CI-defining files differ from
# origin/main is refused, a writer lib planted next to --repo is not looked up).
# The guards are mutation-proved at VERDICT level: each hand-broken copy of the tool must be
# rejected by `bash -n` and a python parse first (INVALID otherwise, never "caught"), and counts as caught only where a scenario
# fails with another verdict than the real tool's (a broken mutant, exit 2 where the real tool answers otherwise or a shell / python
# error text on a row that wants exit 2 (N7), is not a catch).
# Exit 0 only if all pass.
set -uo pipefail
REAL="$(cd "$(dirname "$0")/.." && pwd)"
TOOL="$REAL/tools/ci_marker.sh"
TSV="$REAL/tools/ci_marker_jobs.tsv"
W="$(mktemp -d "${TMPDIR:-/tmp}/tcim.XXXXXX")"
trap 'rm -rf "$W"' EXIT
pass=0 fail=0
ok() { pass=$((pass + 1)); echo "  ok   $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL $1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       /'; }

# the throw-away repository: two commits, so that the first one's tree is not the index's
R="$W/repo"
RL="${LOGICKERNEL_WORKSPACE:-$HOME/code/CognitiveSubstratesAI}/workflows/test_marker.sh"   # read before any row unsets it
mkdir -p "$R" "$W/tmp" "$W/empty" "$W/plant" "$W/ws/workflows"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
LKURL="https://github.com/CognitiveSubstratesAI/LogicKernel.git"; FORK="https://github.com/someone-else/LogicKernel.git"
git -C "$R" init -q; git -C "$R" remote add origin "$LKURL"
echo one > "$R/a.txt"; git -C "$R" add a.txt; git -C "$R" commit -q -m c1
C1="$(git -C "$R" rev-parse HEAD)"
echo two > "$R/a.txt"; git -C "$R" add a.txt; git -C "$R" commit -q -m c2
C2="$(git -C "$R" rev-parse HEAD)"
BR="$(git -C "$R" symbolic-ref --short HEAD)"
# mkorigin REPO TSVFILE|nofile|none: refs/remotes/origin/main of REPO holds tools/ci_marker_jobs.tsv = TSVFILE / a commit without it / is gone
mkorigin() {
    local r="$1" what="$2" b i o c tab=$'\t'
    case "$what" in
        none) git -C "$r" update-ref -d refs/remotes/origin/main; return ;;
        nofile) o="$(git -C "$r" mktree < /dev/null)" ;;
        *) b="$(git -C "$r" hash-object -w "$what")"
            i="$(git -C "$r" mktree <<< "100644 blob $b${tab}ci_marker_jobs.tsv")"
            o="$(git -C "$r" mktree <<< "040000 tree $i${tab}tools")" ;;
    esac
    c="$(git -C "$r" commit-tree "$o" -m origin)"
    git -C "$r" update-ref refs/remotes/origin/main "$c"
}
mkorigin "$R" "$TSV"   # the tree of R carries no tsv at all: only origin/main does
# R3: a tree under test that carries its OWN lax tsv (Format (Blue) may be skipped); its origin/main holds the real one
R3="$W/repo3"; mkdir -p "$R3/tools"; git -C "$R3" init -q; git -C "$R3" remote add origin "$LKURL"
echo one > "$R3/a.txt"
sed $'s/^CI\tFormat (Blue)\tsuccess$/CI\tFormat (Blue)\tskipped/' "$TSV" > "$R3/tools/ci_marker_jobs.tsv"
cmp -s "$TSV" "$R3/tools/ci_marker_jobs.tsv" && { echo "test_ci_marker: the lax tsv equals the real one"; exit 2; }
git -C "$R3" add a.txt tools/ci_marker_jobs.tsv; git -C "$R3" commit -q -m c3
C3="$(git -C "$R3" rev-parse HEAD)"
mkorigin "$R3" "$TSV"
# R4: a tree whose CI-defining files equal origin/main's (no NOTE), the origin of the slug rows (a fork's url is set per row)
R4="$W/repo4"; mkdir -p "$R4/tools"; git -C "$R4" init -q; git -C "$R4" remote add origin "$LKURL"
echo one > "$R4/a.txt"; cp "$TSV" "$R4/tools/ci_marker_jobs.tsv"
git -C "$R4" add a.txt tools/ci_marker_jobs.tsv; git -C "$R4" commit -q -m c4
C4="$(git -C "$R4" rev-parse HEAD)"
mkorigin "$R4" "$TSV"
# R5: like R4, plus tools/evidence_ci.py (a CI-defining file the Evidence verdict gather lives in): the only difference from origin/main
R5="$W/repo5"; mkdir -p "$R5/tools"; git -C "$R5" init -q; git -C "$R5" remote add origin "$LKURL"
echo one > "$R5/a.txt"; cp "$TSV" "$R5/tools/ci_marker_jobs.tsv"; echo '# a changed gather' > "$R5/tools/evidence_ci.py"
git -C "$R5" add a.txt tools/ci_marker_jobs.tsv tools/evidence_ci.py; git -C "$R5" commit -q -m c5
C5="$(git -C "$R5" rev-parse HEAD)"
mkorigin "$R5" "$TSV"
# the stub writer (--writer-stub): records what the tool hands to write_marker
cat > "$W/tmp/stubw.sh" << 'EOS'
start_marker() { [ "${STUB_NOFP:-}" = 1 ] || echo STUBFP; }
write_marker() { [ "${STUB_NOWRITE:-}" = 1 ] && return 0; printf '%s\n%s\n%s\n%s\n' "$1" "$2" "$3" "$4" > "$STUB_MARKER"; }
check_marker() { [ -f "$STUB_MARKER" ]; }
EOS
cp "$W/tmp/stubw.sh" "$W/ws/workflows/test_marker.sh"
# a stub that FOLLOWS TMPDIR like the real lib's marker_path (review3 B2): where its marker lands is what the row checks
cat > "$W/tmp/stubwrap.sh" << 'EOS'
marker_path() { printf '%s/primus_tests_verified.wrap' "${TMPDIR:-/tmp}"; }
start_marker() { echo WRAPFP; }
write_marker() { printf 'x\n' > "$(marker_path "$1")"; }
check_marker() { [ -f "$(marker_path "$1")" ]; }
EOS
printf 'shopt -s expand_aliases\nalias python3="echo OK-LINE CI: forged #"\n' > "$W/tmp/be.sh"
# fake workspaces under a fake HOME (the documented lookup: $HOME/code/CognitiveSubstratesAI/workflows/test_marker.sh):
# hws = a lib that defines all three functions, hpart = only two of them, hsrc = a lib that sources another file for all three
for h in hws hpart hsrc; do mkdir -p "$W/$h/code/CognitiveSubstratesAI/workflows"; done
cp "$W/tmp/stubw.sh" "$W/hws/code/CognitiveSubstratesAI/workflows/test_marker.sh"
sed -n 1,2p "$W/tmp/stubw.sh" > "$W/hpart/code/CognitiveSubstratesAI/workflows/test_marker.sh"
cp "$W/tmp/stubw.sh" "$W/hsrc/other.sh"; echo ". '$W/hsrc/other.sh'" > "$W/hsrc/code/CognitiveSubstratesAI/workflows/test_marker.sh"
# a git shim for the git-error rows: `ls-files --others` / `ls-files -v` fail when GITSHIM_FAIL says so, everything else is real git
mkdir -p "$W/shim"; GITSHIM_REAL="$(command -v git)"; export GITSHIM_REAL
cat > "$W/shim/git" << 'EOS'
#!/bin/bash
for a in "$@"; do case "$a" in ls-files) f=1 ;; --others) o=1 ;; -v) v=1 ;; diff) d=1 ;; --quiet) q=1 ;; --name-only) n=1 ;; esac; done
[ "${d:-0}" = 1 ] && [ "${n:-0}" = 1 ] && [ "${GITSHIM_FAIL:-}" = cid ] && exit 128
[ "${d:-0}" = 1 ] && [ "${q:-0}" = 1 ] && [ "${GITSHIM_FAIL:-}" = diff ] && exit 128
[ "${f:-0}" = 1 ] && [ "${GITSHIM_FAIL:-}" = others ] && [ "${o:-0}" = 1 ] && exit 128
[ "${f:-0}" = 1 ] && [ "${GITSHIM_FAIL:-}" = v ] && [ "${v:-0}" = 1 ] && exit 128
exec "$GITSHIM_REAL" "$@"
EOS
chmod +x "$W/shim/git"
# a json.py planted in the directory the tool is run from: imported by `python3 -c`, never by `python3 -I -c` (B2)
printf 'import sys\nprint("OK-LINE forged: nothing was checked")\nsys.exit(0)\n' > "$W/plant/json.py"

# mkfix DIR SHA SPEC...: the fake API answers for SHA; each SPEC is  verb|workflow|job  (see the generator)
mkfix() {
    local d="$1" sha="$2"; shift 2
    python3 -I - "$d" "$sha" "$TSV" "$@" << 'PYEOF'
import json, os, sys
d, sha, tsv = sys.argv[1:4]
specs = [s.split("|") for s in sys.argv[4:]]
req = []
for ln in open(tsv, encoding="utf-8"):
    if ln.strip() and not ln.startswith("#"):
        req.append(ln.rstrip("\n").split("\t"))
assert req
ids = {"CI": 101, "Evidence (three term types)": 102}
paths = {"CI": ".github/workflows/CI.yml", "Evidence (three term types)": ".github/workflows/evidence.yml"}
def okjobs(w):
    return [{"name": j, "status": "completed", "conclusion": e} for (ww, j, e) in req if ww == w]
jobs = {w: okjobs(w) for w in ids}
def mkrun(w, rid, created, conclusion="success"):
    return {"id": rid, "name": w, "head_sha": sha, "status": "completed", "conclusion": conclusion, "event": "push",
            "path": paths[w], "created_at": created}
runs = {w: mkrun(w, ids[w], "2026-11-14T10:00:00Z") for w in ids}
extra_runs, allids = [], dict(ids)
post = []
def named(w, n):
    return [j for j in jobs[w] if j["name"] == n][0]
for v, *a in specs:
    if v == "fail":
        named(a[0], a[1])["conclusion"] = "failure"
    elif v == "skip":
        named(a[0], a[1])["conclusion"] = "skipped"
    elif v == "succeed":
        named(a[0], a[1])["conclusion"] = "success"
    elif v == "drop":
        jobs[a[0]] = [j for j in jobs[a[0]] if j["name"] != a[1]]
    elif v == "extra":
        jobs[a[0]].append({"name": a[1], "status": "completed", "conclusion": "success"})
    elif v == "rename":   # one character differently: not the tsv's job any more
        j = named(a[0], a[1]); j["name"] = j["name"][:-1] + "X"
    elif v == "norun":
        del runs[a[0]]
    elif v == "pending":
        runs[a[0]]["status"] = "in_progress"; runs[a[0]]["conclusion"] = None
    elif v == "runfail":
        runs[a[0]]["conclusion"] = "failure"
    elif v == "othersha":
        for r in runs.values():
            r["head_sha"] = "f" * 40
    elif v == "pr":   # a pull_request run judged the MERGE tree
        runs[a[0]]["event"] = "pull_request"
    elif v == "otherpath":
        runs[a[0]]["path"] = ".github/workflows/other.yml"
    elif v == "stale":   # an OLDER green run of the same workflow beside the newer red one: the newer decides
        runs[a[0]]["conclusion"] = "failure"; runs[a[0]]["created_at"] = "2026-11-14T12:00:00Z"
        old = a[0] + " (old)"; allids[old] = 104 + len(extra_runs)
        extra_runs.append(mkrun(a[0], allids[old], "2026-11-14T09:00:00Z"))
        jobs[old] = okjobs(a[0])
    elif v == "jobsha":
        post.append(("jobsha", a[0], a[1]))
    elif v == "page2":   # page 1 is full (copies of a green job), a copy of JOB with conclusion CONC is alone on page 2
        base = jobs[a[0]]
        jobs[a[0]] = base + [dict(base[0]) for _ in range(100 - len(base))] + [dict(named(a[0], a[1]), conclusion=a[2])]
    elif v == "nohead":   # a job answer without a head_sha (review2 N6)
        post.append(("nohead", a[0], a[1]))
    elif v == "badtotal":
        post.append(("badtotal", a[0]))
    elif v == "garblejobs":
        post.append(("garblejobs", a[0]))
    elif v == "runtotal":
        post.append(("runtotal",))
    elif v == "garbleruns":
        post.append(("garbleruns",))
    elif v == "emptyruns":
        post.append(("emptyruns",))
    elif v == "clash":   # a compile-check run of the SAME sha whose lower case `static analysis k/9` jobs are all green
        r = mkrun("CI", 103, "2026-11-14T11:00:00Z"); r["name"] = "CI compile check"; r["path"] = ".github/workflows/ci-compile.yml"
        extra_runs.append(r)
        jobs["CI compile check"] = [{"name": "static analysis %d/9" % k, "status": "completed", "conclusion": "success"} for k in range(1, 10)]
        allids["CI compile check"] = 103
    else:
        raise SystemExit("unknown verb " + v)
os.makedirs(d, exist_ok=True)
rfile = os.path.join(d, "runs_%s.json" % sha)
allruns = list(runs.values()) + extra_runs
json.dump({"total_count": len(allruns), "workflow_runs": allruns}, open(rfile, "w"))
for w, js in jobs.items():
    rd = os.path.join(d, str(allids[w])); os.makedirs(rd, exist_ok=True)
    for k, j in enumerate(js):
        j.update(id=1000 * allids[w] + k, head_sha=sha, run_id=allids[w])
    for p in post:
        if p[0] == "jobsha" and p[1] == w:
            named(w, p[2])["head_sha"] = "e" * 40
        if p[0] == "nohead" and p[1] == w:
            del named(w, p[2])["head_sha"]
    tot = len(js) + 5 if ("badtotal", w) in post else len(js)
    for pg in range(1, max(1, (len(js) + 99) // 100) + 1):
        json.dump({"total_count": tot, "jobs": js[(pg - 1) * 100:pg * 100]}, open(os.path.join(rd, "jobs_%d.json" % pg), "w"))
    if ("garblejobs", w) in post:
        open(os.path.join(rd, "jobs_1.json"), "w").write("this is not json {")
if ("runtotal",) in post:
    json.dump({"total_count": len(allruns) + 3, "workflow_runs": allruns}, open(rfile, "w"))
if ("garbleruns",) in post:
    open(rfile, "w").write("<html>rate limited")
if ("emptyruns",) in post:
    open(rfile, "w").write("")
PYEOF
}

EV="Evidence (three term types)"
# review4 F2: the net guard (a curl that logs and fails) and the PATH-shim dirs (a python3 forging OK lines / a git that records a call)
mkdir -p "$W/guard" "$W/shim_py" "$W/shim_git"
printf '#!/bin/bash\necho "$*" >> "%s/guard.log"\nexit 7\n' "$W" > "$W/guard/curl"
printf '#!/bin/bash\n: > "%s/shim_py/ran"\necho "OK-LINE CI: forged"\necho "OK-LINE %s: forged"\n' "$W" "$EV" > "$W/shim_py/python3"
printf '#!/bin/bash\n: > "%s/shim_git/ran"\nexec "$GITSHIM_REAL" "$@"\n' "$W" > "$W/shim_git/git"
chmod +x "$W/guard/curl" "$W/shim_py/python3" "$W/shim_git/git"
# one scenario: sc SCRIPT FIXSPEC REPOSTATE WANT_RC WANT_MARKER LIB NEEDLE [ARGS...]. FIXSPEC: `ok` or `verb|w|job;verb|...` (the fixture for
# the SHA the tool is asked about); REPOSTATE: clean|dirty|untracked|assume|skipwt|gitenv (the git environment variables set)|replace
# (a refs/replace entry for the SHA)|detached (HEAD detached)|lsfail:others|lsfail:v (a git shim failing that ls-files call);
# LIB: stub (fixture + `--dry-run --writer-stub`), dry (fixture, a fake workspace lib under HOME that a dry run must never source),
# nowrite / nofp (a stub that wrote nothing / gave no fingerprint), plant (a json.py in cwd and on PYTHONPATH), nolib (real path, no
# seam, no lib: refused before any API call), seam:VAR (a seam variable in the REAL path), seamdry:VAR (the same with the fixture, for
# --dry-run), tree:lax / org:noref / org:nofile (repo R3, whose own tree carries a lax tsv: origin/main holds the real one / no such ref /
# a commit without the file), boot:real|nofile|noref (R3 again, for --bootstrap-jobs-from-tree; origin/main as named), tsv:dup|foreign|
# missing, exgit (test mode with an exported function `git` that plants an untracked file: dropped, the verdict stands), and the writer injections of the REAL path (no fixture): exfn (the three functions exported from the environment),
# partlib (a lib defining two, the third one exported), srclib (a lib that sources another file), twenv / twslash / twdry (the removed
# CI_MARKER_TEST_WRITER, with TMPDIR as it is / TMPDIR=/ / with --dry-run), stubreal (--writer-stub without --dry-run), slug:real|dry
# (repo R4 whose origin is a fork), note:none (repo R4, origin as it is). A NEEDLE `!text` must be ABSENT; `ORIGINSHA` in it is the
# short SHA of the origin/main the row set up. Returns 0 when rc, marker and the needle hold; SCOUT, SCRC are left behind.
# The HOME is an empty one in EVERY row (or a fake workspace as named): the real workspace writer is never found, so no row can write a
# real marker; https_proxy points at a closed port, so no row can reach the live API either.
SCOUT="" SCRC=""
sc() {
    local script="$1" fixspec="$2" repostate="$3" want_rc="$4" want_mk="$5" lib="$6" needle="$7"; shift 7
    local sha="${SC_FIXSHA:-$C2}" rc mk=no fx tmpd="$W/tmp" cwd="$W" kind="${lib#*:}" kv rp="$R" org="$TSV" exf=none osh="" nm=0
    local -a xa=() pre=() ev=(HOME="$W/empty" STUB_MARKER="$W/marker" https_proxy=http://127.0.0.1:9 HTTPS_PROXY=http://127.0.0.1:9 GIT_TERMINAL_PROMPT=0)
    case "$lib" in   # R3 rows: the tree carries its own tsv; the checklist of the real tool is what origin/main holds
        tree:* | org:* | boot:*) rp="$R3"; sha="${SC_FIXSHA:-$C3}" ;;
        slug:* | note:* | cid:ok) rp="$R4"; sha="${SC_FIXSHA:-$C4}" ;;
        cid:py) rp="$R5"; sha="${SC_FIXSHA:-$C5}" ;;
    esac
    case "$lib" in
        org:noref | boot:noref) org=none ;;
        org:nofile | boot:nofile) org=nofile ;;
        tsv:dup | tsv:foreign | tsv:missing) org="$W/tsv_$kind.tsv" ;;
    esac
    case "$lib" in
        tsv:dup) grep -v '^#' "$TSV" > "$W/tsv_dup.tsv"; grep -m1 "^$EV" "$TSV" >> "$W/tsv_dup.tsv" ;;
        tsv:foreign) grep -v '^#' "$TSV" > "$W/tsv_foreign.tsv"; printf 'Other workflow\tx\tsuccess\n' >> "$W/tsv_foreign.tsv" ;;
        tsv:missing) grep -v '^#' "$TSV" | grep -v "^$EV" > "$W/tsv_missing.tsv" ;;
        slug:*) git -C "$rp" remote set-url origin "$FORK" ;;
    esac
    mkorigin "$rp" "$org"
    git -C "$rp" rev-parse --verify --quiet refs/remotes/origin/main > /dev/null && osh="$(git -C "$rp" rev-parse --short=12 refs/remotes/origin/main)"
    needle="${needle//ORIGINSHA/$osh}"
    fx="$W/fxc/$(printf '%s' "$sha|$fixspec" | md5sum | cut -c1-16)"   # one fixture per (SHA, spec), built once
    rm -rf "$W/marker" "$W/workflows"
    if [ ! -d "$fx" ]; then
        if [ "$fixspec" = ok ]; then mkfix "$fx" "$sha"; else
            IFS=';' read -r -a specs <<< "$fixspec"; mkfix "$fx" "$sha" "${specs[@]}"; fi
    fi
    case "$repostate" in
        dirty) echo three >> "$rp/a.txt" ;;
        untracked) : > "$rp/untracked.txt" ;;
        assume) echo three >> "$rp/a.txt"; git -C "$rp" update-index --assume-unchanged a.txt ;;
        skipwt) echo three >> "$rp/a.txt"; git -C "$rp" update-index --skip-worktree a.txt ;;
        replace) git -C "$rp" update-ref "refs/replace/$sha" "$C1" ;;
        detached) git -C "$rp" checkout -q --detach ;;
        gitenv) GIT_INDEX_FILE="$W/idx_other" git -C "$rp" read-tree "$C1" 2> /dev/null   # an index of ANOTHER tree: the tool must not read it
            ev+=(GIT_INDEX_FILE="$W/idx_other" GIT_ALTERNATE_OBJECT_DIRECTORIES="$W/empty/a") ;;
        gitdir) ev+=(GIT_DIR="$W/empty" GIT_WORK_TREE="$W/empty" GIT_OBJECT_DIRECTORY="$W/empty/o") ;;
        lsfail:*) ev+=(GITSHIM_FAIL="${repostate#*:}") ;;
    esac
    [ "$lib" = exgit ] && exf=git
    case "$lib" in
        nolib) : ;;
        exfn) exf=all ;;
        partlib) ev+=(HOME="$W/hpart"); exf=check ;;
        srclib) ev+=(HOME="$W/hsrc") ;;
        twenv) ev+=(CI_MARKER_TEST_WRITER="$W/tmp/stubw.sh") ;;
        twslash) ev+=(CI_MARKER_TEST_WRITER="$W/tmp/stubw.sh"); tmpd=/ ;;
        twdry) ev+=(CI_MARKER_TEST_WRITER="$W/tmp/stubw.sh" CI_MARKER_FIXTURE_DIR="$fx") ;;
        pathpy) ev+=(CI_MARKER_FIXTURE_DIR="$fx" PATH="$W/shim_py:$PATH"); xa=(--dry-run --writer-stub "$W/tmp/stubw.sh"); rm -f "$W/shim_py/ran" ;;
        pathgit) ev+=(CI_MARKER_FIXTURE_DIR="$fx" PATH="$W/shim_git:$PATH"); xa=(--dry-run --writer-stub "$W/tmp/stubw.sh"); rm -f "$W/shim_git/ran" ;;
        stubreal) xa=(--writer-stub "$W/tmp/stubw.sh") ;;
        shadow | shadowexec | shadowexit | shadowall | shadowdot | spriv | shadowexitv | sprivv) exf="$lib"; ev+=(CI_MARKER_FIXTURE_DIR="$fx"); xa=(--dry-run --writer-stub "$W/tmp/stubw.sh")
            # review4 F1: the `v` rows also export the names the startup refusals expand (_unprivileged, _refused): the script assigns them first
            [ "$lib" = shadowexitv ] && { exf=shadowexit; ev+=(_unprivileged=1 _refused=1); }
            [ "$lib" = sprivv ] && { exf=spriv; ev+=(_unprivileged=1 _refused=1); }
            [ "$exf" = spriv ] && pre=(env SHELLOPTS=privileged) ;;
        envvar:BASH_ENV) ev+=(CI_MARKER_FIXTURE_DIR="$fx" BASH_ENV="$W/tmp/be.sh"); xa=(--dry-run --writer-stub "$W/tmp/stubw.sh") ;;
        envvar:ENV | envvar:PROMPT_COMMAND | envvar:CDPATH) ev+=(CI_MARKER_FIXTURE_DIR="$fx" "$kind=/"); xa=(--dry-run --writer-stub "$W/tmp/stubw.sh") ;;
        envvar:PS4) ev+=(CI_MARKER_FIXTURE_DIR="$fx" "PS4=x "); xa=(--dry-run --writer-stub "$W/tmp/stubw.sh") ;;
        envvar:SHELLOPTS | envvar:BASHOPTS) ev+=(CI_MARKER_FIXTURE_DIR="$fx"); xa=(--dry-run --writer-stub "$W/tmp/stubw.sh")
            pre=(env "$kind=$([ "$kind" = SHELLOPTS ] && echo noglob || echo cmdhist)") ;;
        stubwrap) ev+=(CI_MARKER_FIXTURE_DIR="$fx"); xa=(--dry-run --writer-stub "$W/tmp/stubwrap.sh") ;;
        plantlib) mkdir -p "$W/workflows"; cp "$W/tmp/stubw.sh" "$W/workflows/test_marker.sh" ;;
        cid:*) ev+=(HOME="$W/hws") ;;
        slug:real) : ;;
        seam:CI_MARKER_FIXTURE_DIR | seam:LOGICKERNEL_CI_FIXTURE_DIR) ev+=("$kind=$fx") ;;
        seam:CI_MARKER_JOBS_TSV) ev+=("$kind=$TSV") ;;
        seam:LOGICKERNEL_WORKSPACE) ev+=("$kind=$W/ws") ;;
        seamdry:*) ev+=(CI_MARKER_FIXTURE_DIR="$fx" "$kind=$TSV") ;;
        dry) ev+=(HOME="$W/hws" CI_MARKER_FIXTURE_DIR="$fx") ;;
        boot:*) ev+=(CI_MARKER_FIXTURE_DIR="$fx") ;;
        *)
            ev+=(CI_MARKER_FIXTURE_DIR="$fx"); xa=(--dry-run --writer-stub "$W/tmp/stubw.sh")
            [ "$lib" = nowrite ] && ev+=(STUB_NOWRITE=1)
            [ "$lib" = nofp ] && ev+=(STUB_NOFP=1)
            [ "$lib" = plant ] && { cwd="$W/plant"; ev+=(PYTHONPATH="$W/plant"); } ;;
    esac
    # the net guard: every row but the PATH rows runs a copy of the tool with $W/guard (and the git shim for lsfail) ahead of its PATH
    case "$lib" in
        pathpy | pathgit) : ;;
        *) local pp="/usr/local/bin:/usr/bin:/bin"
            if [[ "$repostate" == lsfail:* ]]; then pp="$W/shim:$W/guard:$pp"; else pp="$W/guard:$pp"; fi
            rm -rf "$W/ptool"; mkdir -p "$W/ptool/tools"; cp "$(dirname "$script")/ci_api.sh" "$W/ptool/tools/"
            sed "s#^PATH=/usr/local/bin:/usr/bin:/bin\$#PATH=$pp#" "$script" > "$W/ptool/tools/ci_marker.sh"; script="$W/ptool/tools/ci_marker.sh" ;;
    esac
    SCOUT="$(cd "$cwd" && export TMPDIR="$tmpd"
        unset LOGICKERNEL_CI_FIXTURE_DIR CI_MARKER_FIXTURE_DIR CI_MARKER_JOBS_TSV LOGICKERNEL_WORKSPACE CI_MARKER_TEST_WRITER no_proxy NO_PROXY
        for kv in "${ev[@]}"; do export "$kv"; done
        if [ "$exf" = git ]; then git() { case "$*" in *ls-files*--others*) echo planted.txt ;; esac; command git "$@"; }; export -f git
        elif [[ "$exf" == shadow* || "$exf" == spriv ]]; then   # review3 B1: functions named like the builtins and tools the tool calls
            if [ "$exf" = shadowdot ]; then .() { builtin . "$@"; ci_jobs_page() { echo '{"total_count":0,"jobs":[]}'; }; }; export -f .
            else
                compgen() { :; }; eval "python3() { echo 'OK-LINE CI: forged'; echo 'OK-LINE $EV: forged'; }"; builtin() { return 1; }; export -f compgen python3 builtin
                [ "$exf" = shadowexec ] || [ "$exf" = shadowexit ] && { exec() { :; }; export -f exec; }
                [ "$exf" = shadowexit ] || [ "$exf" = spriv ] && { exit() { :; }; export -f exit; }
                if [ "$exf" = shadowall ]; then
                    for kv in read unset realpath declare shopt source git mktemp; do eval "$kv() { return 0; }"; export -f "$kv"; done
                fi
            fi
        elif [ "$exf" != none ]; then . "$W/tmp/stubw.sh"; if [ "$exf" = all ]; then export -f start_marker write_marker check_marker; else export -f check_marker; fi; fi
        "${pre[@]}" bash "$script" --repo "$rp" "${xa[@]}" "$@" 2>&1)"; rc=$?
    SCRC="$rc"
    case "$lib" in pathpy | pathgit) [ -e "$W/shim_${lib#path}/ran" ] && { rm -f "$W/shim_${lib#path}/ran"; return 1; } ;; esac   # the shim ran: the caller's PATH was used
    git -C "$rp" update-index --no-skip-worktree a.txt; git -C "$rp" update-index --no-assume-unchanged a.txt; git -C "$rp" checkout -q -- a.txt; rm -f "$rp/untracked.txt"
    git -C "$rp" update-ref -d "refs/replace/$sha"; [ "$repostate" = detached ] && git -C "$rp" checkout -q "$BR"
    [ "$lib" = slug:real ] || [ "$lib" = slug:dry ] && git -C "$rp" remote set-url origin "$LKURL"
    [ -f "$W/marker" ] && mk=yes
    rm -rf "$W/workflows"
    if [ "$lib" = stubwrap ]; then   # review3 B2: the marker of a stub that follows TMPDIR lands in the tool's throw-away directory, not in the caller's
        local sbx leak=no got=no
        sbx="$(printf '%s\n' "$SCOUT" | sed -n 's/^ci_marker: NOTE --writer-stub: .*TMPDIR=\([^ ]*\) .*/\1/p')"
        compgen -G "$tmpd/primus_tests_verified.*" > /dev/null && leak=yes
        rm -f "$tmpd"/primus_tests_verified.*
        [ -n "$sbx" ] && [ -f "$sbx/primus_tests_verified.wrap" ] && got=yes
        case "$sbx" in "$tmpd"/ci_marker_stub.*) rm -rf "$sbx" ;; esac
        [ "$leak" = no ] && [ "$got" = yes ] || return 1
    fi
    # a written marker carries the fingerprint taken BEFORE the API was read (the stub's fourth line)
    [ "$mk" = no ] || [ "$(sed -n 4p "$W/marker")" = STUBFP ] || return 1
    [ "$rc" = "$want_rc" ] && [ "$mk" = "$want_mk" ] || return 1
    case "$needle" in
        "") return 0 ;;
        '!'*) ! printf '%s\n' "$SCOUT" | grep -qF -- "${needle#!}" ;;
        *) printf '%s\n' "$SCOUT" | grep -qF -- "$needle" ;;
    esac
}
# check LABEL FIXSPEC REPOSTATE RC MARKER LIB NEEDLE [ARGS...]: one scenario of the REAL tool
check() {
    local label="$1"; shift
    if sc "$TOOL" "$@"; then ok "$label"; else bad "$label (want rc $3, marker $4, '$6'; got rc $SCRC)" "$SCOUT"; fi
}

# the definition itself: both sides non-empty
nci="$(grep -c '^CI	.*	success$' "$TSV")"; nsk="$(grep -c '^CI	.*	skipped$' "$TSV")"; nev="$(grep -c "^$EV	" "$TSV")"
nu="$(grep -v '^#' "$TSV" | cut -f1,2 | sort | uniq -d | wc -l)"
{ [ "$nci" = 15 ] && [ "$nsk" = 13 ] && [ "$nev" = 19 ] && [ "$nu" = 0 ]; } && ok "ci_marker_jobs.tsv: CI 15 executed + 13 skipped-by-design, Evidence 19, no duplicate (workflow, job) row" || bad "tsv counts $nci/$nsk/$nev dup $nu"

# the verdict rows (real tool)
check "all green, --dry-run: verdict OK, nothing written (a fake lib under HOME is never sourced)" ok clean 0 no dry "verdict OK for ${C2:0:12}" --dry-run
check "all green, test mode (--dry-run --writer-stub): verdict OK, the stub writes, the verdict names the origin/main it read (N5)" ok clean 0 yes stub "checklist origin/main ORIGINSHA)"
check "all green, test mode: announced as a stub, no real marker" ok clean 0 yes stub "NOTE --writer-stub: test mode"
check "all green: verdict OK, exit 0, the (stub) marker is written and verified" ok clean 0 yes stub "marker verified by check_marker"
sc "$TOOL" ok clean 0 yes stub ""; mk="$W/marker"
{ [ "$(sed -n 1p "$mk")" = "$(git -C "$R" rev-parse --show-toplevel)" ] && [ "$(sed -n 2p "$mk")" = 0 ] \
    && sed -n 3p "$mk" | grep -q '^branch-gate (CI evidence' && [ "$(sed -n 4p "$mk")" = STUBFP ]; } && ok "the writer is called with the repo, exit code 0, a branch-gate label (the hook refuses it on main) and the launch fingerprint" || bad "writer arguments" "$(cat "$mk" 2> /dev/null)"
check "one failed CI job: refused, no marker" "fail|CI|Format (Blue)" clean 1 no stub "REFUSED  CI / Format (Blue): failure, expected success"
check "one failed Evidence job: refused, no marker" "fail|$EV|static analysis 7/9" clean 1 no stub "static analysis 7/9: failure"
check "a required job missing: refused" "drop|CI|Tooling · fast" clean 1 no stub "Tooling · fast: job missing"
check "a job NAMED ONE CHARACTER DIFFERENTLY from the tsv: refused (unlisted, fail closed)" "rename|$EV|static analysis 7/9" clean 1 no stub "static analysis 7/X: a job tools/ci_marker_jobs.tsv does not list"
check "...and the tsv's own name is reported missing" "rename|$EV|static analysis 7/9" clean 1 no stub "static analysis 7/9: job missing"
check "a job that must succeed was skipped: refused" "skip|$EV|reference · files 1/2" clean 1 no stub "skipped, expected success"
check "a by-design skip that RAN: refused (the table says skipped)" "succeed|CI|Static analysis 1/9" clean 1 no stub "Static analysis 1/9: success, expected skipped"
check "a job the file does not list: refused (fail closed)" "extra|CI|Brand new job" clean 1 no stub "does not list"
check "CI green but no Evidence run yet: PENDING (exit 3), no marker (N7: the run may not have registered yet)" "norun|$EV" clean 3 no stub "no run at this SHA yet"
check "Evidence green but no CI run yet: PENDING" "norun|CI" clean 3 no stub "CI: no run at this SHA yet"
check "a run that concluded failure with every job green: refused" "runfail|CI" clean 1 no stub "concluded failure"
check "an Evidence run still in progress: pending, exit 3, no marker" "pending|$EV" clean 3 no stub "verdict PENDING"
check "runs of ANOTHER SHA only (the API answer is not trusted): no run at this SHA yet, no marker" "othersha" clean 3 no stub "no run at this SHA yet"
check "a pull_request run (it judged the merge tree): refused" "pr|CI" clean 1 no stub "not push runs of .github/workflows/CI.yml"
check "a run of another workflow file under the same name: refused" "otherpath|$EV" clean 1 no stub "not push runs of .github/workflows/evidence.yml"
check "an OLDER green run beside a newer red one: the newer one decides (refused)" "stale|CI" clean 1 no stub "concluded failure"
check "a job that ran on another SHA: refused" "jobsha|CI|Format (Blue)" clean 1 no stub "the job ran on"
check "the name clash: ci-compile's green static analysis does not hide Evidence's red shard" "fail|$EV|static analysis 3/9;clash" clean 1 no stub "static analysis 3/9: failure"
check "the clash fixture without the red shard is OK (the extra run is not a verdict)" "clash" clean 0 yes stub "verdict OK"
# the page loop: a red job alone on page 2 of the jobs
check "a failed job on page 2 of the jobs: refused (the page loop reads on)" "page2|$EV|static analysis 7/9|failure" clean 1 no stub "static analysis 7/9: failure, expected success"
check "the same layout with the page-2 job green: OK" "page2|$EV|static analysis 7/9|success" clean 0 yes stub "verdict OK"
# unreadable answers: exit 2, never green
check "garbled runs answer: exit 2" garbleruns clean 2 no stub "unreadable: the runs answer"
check "empty runs answer: exit 2" emptyruns clean 2 no stub "unreadable: the runs answer"
check "runs total_count above the runs carried: exit 2" runtotal clean 2 no stub "one page"
check "garbled jobs answer: exit 2" "garblejobs|CI" clean 2 no stub "unreadable: the jobs answer of run 101"
check "jobs total_count above the jobs read: exit 2" "badtotal|CI" clean 2 no stub "the API counts"
# the tsv is checked in the tool: a duplicate row, a foreign workflow, a missing workflow
check "a tsv with a duplicate (workflow, job) row: exit 2" ok clean 2 no tsv:dup "twice"
check "a tsv naming a third workflow: exit 2" ok clean 2 no tsv:foreign "names the workflow"
check "a tsv without the Evidence workflow: exit 2" ok clean 2 no tsv:missing "does not list both workflows"
# D-0693 item 5: the checklist is the COMMITTED origin/main's, never the tree under test's
SK="skip|CI|Format (Blue)"
check "the tree under test carries a lax tsv (Format (Blue) may be skipped), origin/main the real one: REFUSED (the checklist came from origin/main)" "$SK" clean 1 no tree:lax "Format (Blue): skipped, expected success"
check "origin/main holds no tools/ci_marker_jobs.tsv (the first gate): exit 2 naming it, not the tree's tsv" "$SK" clean 2 no org:nofile "origin/main holds no tools/ci_marker_jobs.tsv"
check "no origin/main ref at all: exit 2 naming it" "$SK" clean 2 no org:noref "no origin/main (refs/remotes/origin/main)"
check "--dry-run --bootstrap-jobs-from-tree, origin/main without the file: the verdict prints from the tree's tsv, nothing written" "$SK" clean 0 no boot:nofile "verdict OK for ${C3:0:12}" --dry-run --bootstrap-jobs-from-tree
check "--dry-run --bootstrap-jobs-from-tree, no origin/main ref: the verdict prints, nothing written" "$SK" clean 0 no boot:noref "verdict OK for ${C3:0:12}" --dry-run --bootstrap-jobs-from-tree
check "--dry-run --bootstrap-jobs-from-tree: the option is explicit, it wins over origin/main and says so (NOTE)" "$SK" clean 0 no boot:real "NOTE --bootstrap-jobs-from-tree" --dry-run --bootstrap-jobs-from-tree
check "--bootstrap-jobs-from-tree without --dry-run: refused, exit 2, no marker (origin/main holds the tsv)" "$SK" clean 2 no boot:real "allowed only with --dry-run" --bootstrap-jobs-from-tree
check "--bootstrap-jobs-from-tree without --dry-run, origin/main without the file: refused, exit 2" "$SK" clean 2 no boot:nofile "allowed only with --dry-run" --bootstrap-jobs-from-tree
check "CI_MARKER_JOBS_TSV with --dry-run: refused, no longer read (exit 2)" ok clean 2 no seamdry:CI_MARKER_JOBS_TSV "is no longer read" --dry-run
# the tree
SC_FIXSHA="$C1" check "CI green for the first commit, the index holds the second tree: refused" ok clean 1 no stub "CI judged a different tree" --sha "$C1"
check "an unstaged change: refused" ok dirty 1 no stub "unstaged changes"
check "an untracked file: refused" ok untracked 1 no stub "untracked files"
check "an assume-unchanged tracked file (git diff is blind to it): refused" ok assume 1 no stub "assume-unchanged or skip-worktree"
check "a skip-worktree tracked file: refused" ok skipwt 1 no stub "assume-unchanged or skip-worktree"
check "no marker writer on this machine, a real write: exit 2, no marker" ok clean 2 no nolib "no workflows/test_marker.sh"
check "no launch fingerprint from the writer: exit 2, no marker" ok clean 2 no nofp "no launch fingerprint"
check "a writer that wrote nothing: exit 1, no marker (exit 0 only when check_marker verifies it)" ok clean 1 no nowrite "not valid after the write"
# B1: every seam is REFUSED in the real path (no --dry-run), naming the variable; --dry-run honours the fixture
for v in CI_MARKER_FIXTURE_DIR LOGICKERNEL_CI_FIXTURE_DIR CI_MARKER_JOBS_TSV LOGICKERNEL_WORKSPACE; do
    check "seam $v in the real write path: exit 2, named, no marker" ok clean 2 no "seam:$v" "a test seam is set: $v"
done
check "the fixture seam with --dry-run: honoured (and announced)" ok clean 0 yes stub "NOTE a fixture API is in use" --dry-run
# review2 N1: the real path takes no caller-chosen writer; every way to inject one is refused (no fixture: the API is a sink)
check "an exported function write_marker/start_marker/check_marker is no writer: exit 2, no marker" ok clean 2 no exfn "no workflows/test_marker.sh"
check "a lib that defines two of the three functions, the third one exported: refused (not all defined by the lib)" ok clean 2 no partlib "are not all defined by"
check "a lib that sources another file for the three functions: refused (the file is not the lib)" ok clean 2 no srclib "are not all defined by"
check "the removed CI_MARKER_TEST_WRITER in the real path: refused" ok clean 2 no twenv "CI_MARKER_TEST_WRITER is no longer read"
check "...with TMPDIR=/ : refused the same" ok clean 2 no twslash "CI_MARKER_TEST_WRITER is no longer read"
check "...also with --dry-run: refused" ok clean 2 no twdry "CI_MARKER_TEST_WRITER is no longer read" --dry-run
check "--writer-stub without --dry-run (the real path): refused, no marker" ok clean 2 no stubreal "allowed only with --dry-run"
# review2 N2: the origin must be the LogicKernel repository
# review3 B1: privileged mode. Exported functions named like the builtins / tools the tool calls cannot forge the verdict (a red job stays refused)
check "B1: exported compgen + python3 (forging OK lines) + builtin functions: dropped (privileged mode), the red job still refuses" "fail|CI|Format (Blue)" clean 1 no shadow "REFUSED  CI / Format (Blue)"
check "B1: ...with an exported exec (a no-op: no re-exec): refused as not privileged, exit 2" "fail|CI|Format (Blue)" clean 2 no shadowexec "not in privileged mode"
check "B1: ...with exec AND exit shadowed: ends at the parameter-expansion refusal (exit 1), still no verdict" "fail|CI|Format (Blue)" clean 1 no shadowexit "not in privileged mode"
check "B1: exported read/unset/realpath/declare/shopt/source/git/mktemp functions (no-ops) are never imported: the green verdict stands" ok clean 0 yes shadowall "verdict OK for ${C2:0:12}"
check "B1: an exported \`.\` function (forging an empty jobs page) does not reach the jobs child: the green verdict stands" ok clean 0 yes shadowdot "verdict OK for ${C2:0:12}"
check "F1 (review4): exec, exit, builtin, python3 shadowed AND _unprivileged=1 _refused=1 exported: still refused (the backstop names are assigned first), no verdict" "fail|CI|Format (Blue)" clean 1 no shadowexitv "not in privileged mode"
check "F1 (review4): SHELLOPTS=privileged + _refused=1 _unprivileged=1 exported, exit shadowed: refused, names SHELLOPTS" "fail|CI|Format (Blue)" clean 1 no sprivv "sets: SHELLOPTS(exported)"
# review4 F2: the tool's own PATH; the caller's python3 / git placed first are not run (the shim leaves a `ran` file, checked by sc)
check "F2 (review4): a python3 first in the caller's PATH forging OK lines is not run: the red job still refuses" "fail|CI|Format (Blue)" clean 1 no pathpy "REFUSED  CI / Format (Blue)"
check "F2 (review4): a git first in the caller's PATH is not run (it records a call): the green verdict stands" ok clean 0 yes pathgit "verdict OK for ${C2:0:12}"
# review4 F3: the verdict-gather scripts are CI-defining; a failing git diff of the list is a refusal
check "F3 (review4): a real run where only tools/evidence_ci.py differs from origin/main: refused (exit 1) with the file" ok clean 1 no cid:py "CI-defining files differ from origin/main in ${C5:0:12}: tools/evidence_ci.py"
check "F3 (review4): the git diff of the CI-defining files fails: refused (exit 2), never an empty list" ok lsfail:cid 2 no stub "git error (diff of the CI-defining files"
check "B1: SHELLOPTS=privileged in the caller's variables (a privileged shell WITH imported functions, exit shadowed): refused, names SHELLOPTS" "fail|CI|Format (Blue)" clean 1 no spriv "sets: SHELLOPTS(exported)"
for v in BASH_ENV ENV PROMPT_COMMAND CDPATH PS4 SHELLOPTS BASHOPTS; do
    nd="$v"; [ "$v" = SHELLOPTS ] || [ "$v" = BASHOPTS ] && nd="$v(exported)"
    check "B1: the caller sets $v: refused (exit 2), named, no marker (BASH_ENV: with an alias forging python3)" ok clean 2 no "envvar:$v" "sets: $nd"
done
# review3 B2: a stub that follows TMPDIR writes into the tool's throw-away directory
check "B2: a stub that wraps the marker path of the real lib (follows TMPDIR): its marker lands in the tool's throw-away TMPDIR, none in the caller's" ok clean 0 no stubwrap "marker verified by check_marker"
# review3 B3: CI-defining files that differ from origin/main refuse a REAL run (no fixture: the API is a sink)
check "B3: a real run where a CI-defining file differs from origin/main: refused (exit 1) with the file list, before any API call" ok clean 1 no cid:bad "CI-defining files differ from origin/main in ${C2:0:12}: tools/ci_marker_jobs.tsv"
check "B3: a real run with the CI-defining files equal: not refused for them (it goes on to the API sink: exit 2)" ok clean 2 no cid:ok "!CI-defining files differ"
# review3 R1: the one writer candidate is the workspace under HOME; a lib planted next to --repo is not looked up
check "R1: a lib planted at <repo>/../workflows/test_marker.sh is not used (HOME holds none): exit 2" ok clean 2 no plantlib "no workflows/test_marker.sh"
check "an exported function git (one that plants an untracked file) is dropped at the top: the verdict stands" ok clean 0 yes exgit "verdict OK for ${C2:0:12}"
check "a fork as origin, the real path: refused (exit 2), named" ok clean 2 no slug:real "not CognitiveSubstratesAI/LogicKernel"
check "a fork as origin, test mode: OK with a NOTE (a test slug only with --dry-run)" ok clean 0 yes slug:dry "NOTE the origin is 'someone-else/LogicKernel'"
check "the LogicKernel origin: no slug NOTE" ok clean 0 yes note:none "!NOTE the origin is"
# review2 N3: the git environment and replace refs do not retarget the tool
check "GIT_INDEX_FILE of another tree in the environment: dropped, the verdict stands" ok gitenv 0 yes stub "verdict OK for ${C2:0:12}"
check "GIT_DIR / GIT_WORK_TREE / GIT_OBJECT_DIRECTORY (set by a hook or `git rebase -x`): dropped too" ok gitdir 0 yes stub "verdict OK for ${C2:0:12}"
check "a refs/replace entry for the SHA is not honoured: the verdict stands" ok replace 0 yes stub "verdict OK for ${C2:0:12}"
# review2 N4/N5/N12: notes
check "a tree whose CI-defining file differs from origin/main's: NOTE listing it" ok clean 0 yes stub "NOTE these CI-defining files differ between origin/main and ${C2:0:12}"
check "...and a tree that carries the same CI-defining files: no such NOTE" ok clean 0 yes note:none "!NOTE these CI-defining files differ"
check "the refused verdict names the origin/main it read too" "fail|CI|Format (Blue)" clean 1 no stub "(checklist origin/main ORIGINSHA), no marker written"
check "HEAD detached: NOTE (the hook is the authority)" ok detached 0 yes stub "NOTE HEAD of"
check "a job answer without a head_sha: refused (not trusted)" "nohead|CI|Format (Blue)" clean 1 no stub "the job ran on None"
# review2 N11: a git error in a tree check is a refusal, never a pass
check "git diff --quiet fails (exit 128): refused (git error), not read as unstaged changes" ok lsfail:diff 1 no stub "git error (diff, exit 128)"
check "ls-files --others fails: refused (git error)" ok lsfail:others 1 no stub "git error (ls-files --others)"
check "ls-files -v fails: refused (git error)" ok lsfail:v 1 no stub "git error (ls-files -v)"
# B2: a json.py planted in the cwd / on PYTHONPATH is not imported (a red fixture: the planted one would forge an OK)
check "a planted json.py in the cwd and on PYTHONPATH is not imported: the red job still refuses" "fail|CI|Format (Blue)" clean 1 no plant "REFUSED  CI / Format (Blue)"
n="$(grep -v '^ *#' "$TOOL" | grep -c 'python3')"; n2="$(grep -v '^ *#' "$TOOL" | grep 'python3' | grep -vc 'python3 -I')"
{ [ "$n" -ge 1 ] && [ "$n2" = 0 ] && [ "$(grep -c 'python' "$REAL/tools/ci_api.sh")" = 0 ]; } && ok "every python3 of ci_marker.sh runs with -I ($n), ci_api.sh runs none" || bad "python3 without -I: $n2 of $n"

# the real write_marker, on ITS interface as the tool uses it (no fixture, no API: the tool's real path refuses fixtures, B1)
if [ -f "$RL" ]; then
    out="$(TMPDIR="$W/tmp" bash -c "set -u; . '$RL'; r=\"\$(git -C '$R' rev-parse --show-toplevel)\"; fp=\"\$(start_marker \"\$r\")\"; [ -n \"\$fp\" ] || exit 9
        write_marker \"\$r\" 0 'branch-gate (CI evidence: x)' \"\$fp\"; check_marker \"\$r\"; echo \"check=\$? fp=\$fp\"; m=\"\$(marker_path \"\$r\")\"; sed -n 3p \"\$m\"; rm -f \"\$m\"" 2>&1)"
    printf '%s\n' "$out" | grep -q '^check=0 fp=.' && printf '%s\n' "$out" | grep -q '^branch-gate (CI evidence' \
        && ok "the real write_marker/start_marker/check_marker (the tool's calls, no API): fingerprint, branch-gate label, check_marker 0" || bad "real writer interface" "$out"
else
    echo "  n/a  the real writer interface row (no workflows/test_marker.sh on this machine); NOTE: the real write path through the tool cannot be run with a fixture (B1): it is not exercised by this file"
fi
# token discipline: the tool never reads, prints or writes a credential itself (ci_api.sh owns the route)
n="$(grep -v '^ *#' "$TOOL" | grep -cE 'curl|credential|Bearer|Authorization|environ|printenv|\benv\b')"
[ "$n" = 0 ] && ok "no credential handling in ci_marker.sh itself (the route is tools/ci_api.sh)" || bad "ci_marker.sh mentions curl/credential/env text on $n line(s)"

# review4 F2: every curl call of tools/ci_api.sh starts with `-q --noproxy '*'` (no ~/.curlrc, no caller proxy). Proved on a recording curl
# placed first in PATH (it never touches the network), through the three public functions; a stand-in for the stored credential makes the
# authed call reachable. api_curl_rows FILE -> "<calls> <calls not starting with -q --noproxy *>"
mkdir -p "$W/rec"
printf '#!/bin/bash\nprintf "%%s|" "$@" >> "%s/rec.log"\necho >> "%s/rec.log"\nexit 0\n' "$W" "$W" > "$W/rec/curl"; chmod +x "$W/rec/curl"
api_curl_rows() {
    local api="$1" n bad
    rm -f "$W/rec.log"
    (
        unset LOGICKERNEL_CI_FIXTURE_DIR; export TMPDIR="$W/tmp" ROOT="$R"; PATH="$W/rec:$PATH"
        . "$api"
        _ci_token() { echo stand-in; }
        ci_runs_for_sha "$C2" > /dev/null; ci_jobs_page 1 1 > /dev/null; ci_job_log 5 7 > /dev/null 2>&1
    ) < /dev/null > /dev/null 2>&1
    n="$(grep -c '' "$W/rec.log" 2> /dev/null)"; bad="$(grep -vc '^-q|--noproxy|\*|-s|' "$W/rec.log" 2> /dev/null)"
    echo "${n:-0} ${bad:-0}"
}
res="$(api_curl_rows "$REAL/tools/ci_api.sh")"
[ "$res" = "5 0" ] && ok "F2 (review4): ci_api.sh calls curl 5 times (runs and jobs page: anonymous + authed each; job log: authed), each with -q --noproxy '*' first" || bad "ci_api.sh curl calls: '$res' (calls, calls without -q --noproxy first)"
for m in "s#curl -q --noproxy '\\*' -s -K -#curl -s -K -#" "s#curl -q --noproxy '\\*' -s -m 25#curl -s -m 25#" "s#curl -q #curl #" "s# --noproxy '\\*'##"; do
    mkdir -p "$W/apimut"; sed "$m" "$REAL/tools/ci_api.sh" > "$W/apimut/ci_api.sh"
    cmp -s "$W/apimut/ci_api.sh" "$REAL/tools/ci_api.sh" && { bad "ci_api mutant INVALID (no change): $m"; continue; }
    res="$(api_curl_rows "$W/apimut/ci_api.sh")"
    [ "${res#* }" != 0 ] && ok "mutant caught: ci_api.sh curl flags broken by [$m] ($res)" || bad "mutant SURVIVED: ci_api.sh curl flags broken by [$m] ($res)"
done

# MUTATION PROOF at verdict level: a scenario table, every field separated by @: FIXSPEC@REPOSTATE@RC@MARKER@LIB@NEEDLE[@ARG]
SCEN=(
    "ok@clean@0@yes@stub@marker verified"
    "ok@clean@0@yes@stub@verdict OK@--dry-run"
    "fail|CI|Format (Blue)@clean@1@no@stub@Format (Blue): failure"
    "fail|$EV|static analysis 7/9@clean@1@no@stub@static analysis 7/9: failure"
    "drop|CI|Tooling · fast@clean@1@no@stub@job missing"
    "rename|$EV|static analysis 7/9@clean@1@no@stub@does not list"
    "skip|$EV|reference · files 1/2@clean@1@no@stub@skipped, expected success"
    "succeed|CI|Static analysis 1/9@clean@1@no@stub@expected skipped"
    "extra|CI|Brand new job@clean@1@no@stub@does not list"
    "norun|$EV@clean@3@no@stub@no run at this SHA yet"
    "pending|$EV@clean@3@no@stub@verdict PENDING"
    "runfail|CI@clean@1@no@stub@concluded failure"
    "othersha@clean@3@no@stub@no run at this SHA yet"
    "pr|CI@clean@1@no@stub@not push runs"
    "otherpath|$EV@clean@1@no@stub@not push runs"
    "stale|CI@clean@1@no@stub@concluded failure"
    "jobsha|CI|Format (Blue)@clean@1@no@stub@the job ran on"
    "fail|$EV|static analysis 3/9;clash@clean@1@no@stub@static analysis 3/9: failure"
    "page2|$EV|static analysis 7/9|failure@clean@1@no@stub@static analysis 7/9: failure"
    "page2|$EV|static analysis 7/9|success@clean@0@yes@stub@verdict OK"
    "runtotal@clean@2@no@stub@one page"
    "badtotal|CI@clean@2@no@stub@the API counts"
    "garbleruns@clean@2@no@stub@runs answer"
    "garblejobs|CI@clean@2@no@stub@jobs answer"
    "ok@clean@2@no@tsv:dup@twice"
    "ok@clean@2@no@tsv:foreign@names the workflow"
    "ok@clean@2@no@tsv:missing@does not list both"
    "ok@dirty@1@no@stub@unstaged changes"
    "ok@untracked@1@no@stub@untracked files"
    "ok@assume@1@no@stub@assume-unchanged"
    "ok@skipwt@1@no@stub@assume-unchanged"
    "ok@clean@2@no@nofp@no launch fingerprint"
    "ok@clean@1@no@nowrite@not valid after the write"
    "ok@clean@2@no@seam:CI_MARKER_FIXTURE_DIR@a test seam is set: CI_MARKER_FIXTURE_DIR"
    "ok@clean@2@no@seam:LOGICKERNEL_CI_FIXTURE_DIR@a test seam is set: LOGICKERNEL_CI_FIXTURE_DIR"
    "ok@clean@2@no@seam:CI_MARKER_JOBS_TSV@a test seam is set: CI_MARKER_JOBS_TSV"
    "ok@clean@2@no@seam:LOGICKERNEL_WORKSPACE@a test seam is set: LOGICKERNEL_WORKSPACE"
    "ok@clean@2@no@exfn@no workflows/test_marker.sh"
    "ok@clean@2@no@partlib@are not all defined by"
    "ok@clean@2@no@srclib@are not all defined by"
    "ok@clean@2@no@twenv@CI_MARKER_TEST_WRITER is no longer read"
    "ok@clean@2@no@twslash@CI_MARKER_TEST_WRITER is no longer read"
    "ok@clean@2@no@twdry@CI_MARKER_TEST_WRITER is no longer read@--dry-run"
    "ok@clean@2@no@stubreal@allowed only with --dry-run"
    "ok@clean@2@no@slug:real@not CognitiveSubstratesAI/LogicKernel"
    "ok@clean@0@yes@slug:dry@NOTE the origin is"
    "ok@clean@0@no@dry@verdict OK@--dry-run"
    "ok@gitenv@0@yes@stub@verdict OK"
    "ok@replace@0@yes@stub@verdict OK"
    "ok@clean@0@yes@stub@NOTE these CI-defining files differ"
    "ok@clean@0@yes@stub@checklist origin/main ORIGINSHA)"
    "ok@clean@0@yes@note:none@!NOTE these CI-defining files differ"
    "ok@detached@0@yes@stub@NOTE HEAD of"
    "nohead|CI|Format (Blue)@clean@1@no@stub@the job ran on None"
    "ok@lsfail:others@1@no@stub@git error (ls-files --others)"
    "ok@lsfail:v@1@no@stub@git error (ls-files -v)"
    "ok@lsfail:diff@1@no@stub@git error (diff, exit 128)"
    "ok@clean@0@yes@exgit@verdict OK"
    "fail|CI|Format (Blue)@clean@1@no@shadow@REFUSED  CI / Format (Blue)"
    "fail|CI|Format (Blue)@clean@2@no@shadowexec@not in privileged mode"
    "fail|CI|Format (Blue)@clean@1@no@shadowexit@not in privileged mode"
    "ok@clean@0@yes@shadowall@verdict OK"
    "ok@clean@0@yes@shadowdot@verdict OK"
    "fail|CI|Format (Blue)@clean@1@no@spriv@sets: SHELLOPTS(exported)"
    "fail|CI|Format (Blue)@clean@1@no@shadowexitv@not in privileged mode"
    "fail|CI|Format (Blue)@clean@1@no@sprivv@sets: SHELLOPTS(exported)"
    "fail|CI|Format (Blue)@clean@1@no@pathpy@REFUSED  CI / Format (Blue)"
    "ok@clean@0@yes@pathgit@verdict OK"
    "ok@clean@1@no@cid:py@tools/evidence_ci.py"
    "ok@lsfail:cid@2@no@stub@git error (diff of the CI-defining files"
    "ok@clean@2@no@envvar:BASH_ENV@sets: BASH_ENV"
    "ok@clean@2@no@envvar:ENV@sets: ENV"
    "ok@clean@2@no@envvar:PROMPT_COMMAND@sets: PROMPT_COMMAND"
    "ok@clean@2@no@envvar:CDPATH@sets: CDPATH"
    "ok@clean@2@no@envvar:PS4@sets: PS4"
    "ok@clean@2@no@envvar:SHELLOPTS@sets: SHELLOPTS(exported)"
    "ok@clean@2@no@envvar:BASHOPTS@sets: BASHOPTS(exported)"
    "ok@clean@0@no@stubwrap@marker verified by check_marker"
    "ok@clean@1@no@cid:bad@CI-defining files differ from origin/main"
    "ok@clean@2@no@cid:ok@!CI-defining files differ"
    "ok@clean@2@no@plantlib@no workflows/test_marker.sh"
    "fail|CI|Format (Blue)@clean@1@no@plant@REFUSED  CI / Format (Blue)"
    "$SK@clean@1@no@tree:lax@Format (Blue): skipped, expected success"
    "$SK@clean@2@no@org:nofile@origin/main holds no tools/ci_marker_jobs.tsv"
    "$SK@clean@2@no@org:noref@no origin/main"
    "$SK@clean@0@no@boot:nofile@verdict OK@--dry-run@--bootstrap-jobs-from-tree"
    "$SK@clean@0@no@boot:noref@verdict OK@--dry-run@--bootstrap-jobs-from-tree"
    "$SK@clean@0@no@boot:real@NOTE --bootstrap-jobs-from-tree@--dry-run@--bootstrap-jobs-from-tree"
    "$SK@clean@2@no@boot:real@allowed only with --dry-run@--bootstrap-jobs-from-tree"
    "$SK@clean@2@no@boot:nofile@allowed only with --dry-run@--bootstrap-jobs-from-tree"
    "ok@clean@2@no@seamdry:CI_MARKER_JOBS_TSV@is no longer read@--dry-run"
)
# N7: a shell / python error text in the output of a row that WANTS exit 2: such a row is broken, not caught by a verdict
errtok() { printf '%s\n' "$1" | grep -qE 'unexpected answer shape|Traceback|^bash: |: line [0-9]+: |command not found|unbound variable|syntax error'; }
errtok "ci_marker.sh: line 91: x: unbound variable" && ! errtok "ci_marker: unreadable: the runs answer of the API" && errtok "bash: -c: syntax error" \
    && ok "errtok (N7): a shell error text is told from a verdict text" || bad "errtok does not tell a shell error from a verdict"
# MT=<ERE> before a `mutant` call names its TARGETS (D-0238): the scenario lines that exercise the mutated code; the default is all.
# mut_rows SCRIPT -> "<verdict mismatches> <breaks>": scenarios whose verdict does not hold for it (0 0 for the real tool). A
# break (exit 2 where the real tool answers otherwise) is counted apart: it is a broken mutant, not a caught one.
mut_rows() {
    local script="$1" n=0 cr=0 line f
    for line in "${SCEN[@]}"; do
        [ "${MT_STOP:-0}" = 1 ] && [ "$n" != 0 ] && break           # a mutant: the first catch is enough
        [[ "$line" =~ ${MT:-.} ]] || continue                         # TARGETS: the scenarios that exercise the mutated code
        IFS='@' read -r -a f <<< "$line"
        if ! sc "$script" "${f[0]}" "${f[1]}" "${f[2]}" "${f[3]}" "${f[4]}" "${f[5]}" ${f[6]:+"${f[6]}"} ${f[7]:+"${f[7]}"}; then
            # a real-path row without a fixture (cid:*) ends at the API sink (exit 2) in a mutant that lets it through: that is the catch there
            if [ "$SCRC" = 2 ] && { { [[ "${f[4]}" != cid:* ]] && [ "${f[2]}" != 2 ]; } || errtok "$SCOUT"; }; then cr=$((cr + 1)); else n=$((n + 1)); fi
        fi
    done
    if [ "$n" = 0 ] || [ "${MT_STOP:-0}" != 1 ]; then   # the tree scenario (the other commit's tree) always runs
        SC_FIXSHA="$C1" sc "$script" ok clean 1 no stub "CI judged a different tree" --sha "$C1" || n=$((n + 1))
    fi
    echo "$n $cr"
}
PROBE="$W/probe/tools"
# the guard lines of the tool, exactly (a mutant's OLD text must match once)
LEXEC='[[ $- == *p* ]] || exec "$BASH" -p "$0" "$@"'
LMSG='[[ $- == *p* ]] || { echo "ci_marker: REFUSED (exit 2): not in privileged mode (bash -p) and the re-exec did not happen"; exit 2; }'
LX='[[ $- == *p* ]] || _g=${_unprivileged:?ci_marker: REFUSED: not in privileged mode}'
LPURGE='while builtin read -r _d _x _f; do builtin unset -f "$_f"; done < <(builtin declare -F)'
mutant() { # LABEL OLD NEW [OLD NEW ...]: a copy of the tool with each OLD replaced by NEW (OLD must match exactly once)
    local label="$1"; shift
    rm -rf "$W/probe"; mkdir -p "$PROBE"; cp "$REAL/tools/ci_api.sh" "$TSV" "$PROBE/"; cp "$TOOL" "$PROBE/ci_marker.sh"
    python3 -I - "$PROBE/ci_marker.sh" "$@" << 'PYEOF'
import sys
p, pairs = sys.argv[1], sys.argv[2:]
s = open(p, encoding="utf-8").read()
for old, new in zip(pairs[0::2], pairs[1::2]):
    assert s.count(old) == 1, "mutant text matches %d times: %r" % (s.count(old), old)
    s = s.replace(old, new)
open(p, "w", encoding="utf-8").write(s)
PYEOF
    [ $? = 0 ] || { bad "mutant $label: could not be built"; return; }
    # INVALID, never "caught": the mutant must still be a script (bash -n) whose python block parses
    bash -n "$PROBE/ci_marker.sh" 2> /dev/null || { bad "mutant INVALID (bash -n fails): $label"; return; }
    python3 -I - "$PROBE/ci_marker.sh" << 'PYEOF' || { bad "mutant INVALID (the python block does not parse): $label"; return; }
import ast, re, sys
m = re.search(r"<< 'PYEOF'\n(.*?)\nPYEOF\n", open(sys.argv[1], encoding="utf-8").read(), re.S)
ast.parse(m.group(1))
PYEOF
    local res cnt cr; res="$(MT_STOP=1 mut_rows "$PROBE/ci_marker.sh")"; cnt="${res% *}"; cr="${res#* }"
    if [ "$cnt" != 0 ]; then ok "mutant caught: $label ($cnt scenario(s) fail with another verdict, $cr break(s))"
    elif [ "$cr" != 0 ]; then bad "mutant only BREAKS (exit 2) ($cr scenario(s) exit 2): not a verdict-level catch: $label"
    else bad "mutant SURVIVED: $label"; fi
}
res="$(mut_rows "$TOOL")"
[ "$res" = "0 0" ] && ok "mutation baseline: the real tool holds every verdict scenario" || bad "baseline: '$res' (mismatches breaks) for the real tool"
mutant "accept-all: the verdict never refuses" 'if [ -n "$(printf' 'if false && [ -n "$(printf'
MT='Evidence' mutant "ignores Evidence" 'for w, want in required.items():' 'for w, want in [x for x in required.items() if x[0] == "CI"]:'
MT='clash' mutant "name lookup across all runs of the SHA (check-runs style) instead of per run" 'got = [j for j in jobs if j["name"] == name]' 'got = [j for x in runs for j in jobs_of(x["id"]) if j["name"] == name and j["conclusion"] == exp] or [j for j in jobs if j["name"] == name]'
MT='^rename' mutant "job names compared loosely (one character off tolerated)" 'got = [j for j in jobs if j["name"] == name]' 'got = [j for j in jobs if j["name"][:-1] == name[:-1]]' 'for name in sorted(names - set(want)):' 'for name in []:'
MT='^othersha' mutant "ignores the SHA of the runs" 'runs = [r for r in allruns if r["head_sha"] == sha]' 'runs = allruns'
MT='^$' mutant "does not compare the tree" '[ "$tree_c" = "$tree_i" ] || add' 'true || add'
MT='@dirty@' mutant "ignores unstaged changes" 'diff --quiet; drc=$?' 'diff --quiet; drc=0'
MT='@untracked@' mutant "ignores untracked files" '[ -z "$uo" ] || add' 'true || add'
MT='@assume@|@skipwt@' mutant "ignores assume-unchanged / skip-worktree flags" "grep -q '^[a-zS]' && add" 'false && add'
MT='^skip' mutant "a skipped job counts as success" 'elif j["conclusion"] != exp:' 'elif j["conclusion"] not in (exp, "skipped"):'
MT='^extra|^rename' mutant "unlisted jobs allowed" 'for name in sorted(names - set(want)):' 'for name in []:'
MT='@dry@' mutant "a plain --dry-run takes the real writer and writes (wmode ignored)" 'if [ "$wmode" != none ]; then' 'if true; then' 'if [ "$wmode" = none ]; then' 'if false; then'
MT='stubreal' mutant "--writer-stub accepted without --dry-run" 'if [ -n "$wstub" ] && [ "$dry" = 0 ]; then' 'if false; then'
MT='^ok@clean@2@no@tw' mutant "the removed writer variable is accepted" 'if [ -n "${CI_MARKER_TEST_WRITER:-}" ]; then' 'if false; then'
MT='partlib|exfn' mutant "no purge, no privileged mode and no check that the lib defines the three (all layers)" "$LPURGE" ':' "$LEXEC" ':' "$LMSG" ':' "$LX" ':' '[ "$nd" = 3 ] ||' 'true ||'
MT='srclib' mutant "the functions need not be defined by the lib file" '[ "$nd" = 3 ] ||' 'true ||'
# the purge is a second layer behind privileged mode: removed alone it is equivalent (privileged mode imports no function), so it goes together with the first
MT='exgit' mutant "imported functions are dropped by neither layer (purge and privileged mode removed together)" "$LPURGE" ':' "$LEXEC" ':' "$LMSG" ':' "$LX" ':'
# review3 B1: privileged mode and the caller's variables, each guard alone (the rows above name the verdict each one keeps)
MT='@(shadow|spriv)' mutant "B1: no privileged mode (no re-exec, no unprivileged refusal; the purge stays: a shadowed builtin defeats it)" "$LEXEC" ':' "$LMSG" ':' "$LX" ':'
MT='@shadowexec@' mutant "B1: a shell that is not privileged after the re-exec goes on (both refusals removed, the re-exec stays)" "$LMSG" ':' "$LX" ':'
MT='@shadowexit@' mutant "B1: the \${var:?} refusal removed (exit and echo shadowed: the shell goes on)" "$LX" ':'
MT='@spriv@' mutant "B1: the \${var:?} refusal of the caller's variables removed (SHELLOPTS=privileged with imported functions goes on)" '[[ -z $_bad ]] || _g=${_refused:?ci_marker: REFUSED: the caller sets:$_bad}' ':'
MT='@(shadowexitv|sprivv)@' mutant "F1 (review4): the backstop names are not assigned before use (a pre-exported _unprivileged/_refused defeats the refusals)" '_bad="" _refused="" _unprivileged="" _g=""' '_bad=""'
MT='@(pathpy|pathgit)@' mutant "F2 (review4): PATH is not assigned (the caller's python3 / git are found)" $'\nPATH=/usr/local/bin:/usr/bin:/bin\n' $'\n:\n'
MT='cid:py' mutant "F3 (review4): tools/evidence_ci.py is not among the CI-defining files" ' tools/evidence_ci.py tools/ci_compile_summary.py' ' tools/ci_compile_summary.py'
MT='lsfail:cid' mutant "F3 (review4): a failing git diff of the CI-defining files is read as an empty list" '{ echo "ci_marker: REFUSED (exit 2): git error (diff of the CI-defining files against origin/main): the files that define CI cannot be compared"; exit 2; }' ':'
MT='@shadowdot@' mutant "B1: the jobs child is not privileged (an exported . function reaches ci_jobs_page)" 'p = subprocess.run([bashbin, "-p", "-c",' 'p = subprocess.run([bashbin, "-c",'
MT='envvar:BASH_ENV' mutant "B1: BASH_ENV is not refused" 'for _v in BASH_ENV ENV PROMPT_COMMAND CDPATH; do' 'for _v in ENV PROMPT_COMMAND CDPATH; do'
MT='envvar:ENV' mutant "B1: ENV is not refused" 'for _v in BASH_ENV ENV PROMPT_COMMAND CDPATH; do' 'for _v in BASH_ENV PROMPT_COMMAND CDPATH; do'
MT='envvar:PROMPT_COMMAND' mutant "B1: PROMPT_COMMAND is not refused" 'for _v in BASH_ENV ENV PROMPT_COMMAND CDPATH; do' 'for _v in BASH_ENV ENV CDPATH; do'
MT='envvar:CDPATH' mutant "B1: CDPATH is not refused" 'for _v in BASH_ENV ENV PROMPT_COMMAND CDPATH; do' 'for _v in BASH_ENV ENV PROMPT_COMMAND; do'
MT='envvar:SHELLOPTS' mutant "B1: an exported SHELLOPTS is not refused" 'for _v in SHELLOPTS BASHOPTS; do' 'for _v in BASHOPTS; do'
MT='envvar:BASHOPTS' mutant "B1: an exported BASHOPTS is not refused" 'for _v in SHELLOPTS BASHOPTS; do' 'for _v in SHELLOPTS; do'
MT='envvar:PS4' mutant "B1: a changed PS4 is not refused" "[[ \$PS4 == '+ ' ]] || _bad=" 'true || _bad='
MT='stubwrap' mutant "B2: the stub runs with the caller's TMPDIR (no throw-away directory)" 'export TMPDIR="$sbx"' ':'
MT='cid:bad' mutant "B3: CI-defining files that differ are a NOTE in the real path, not a refusal" 'if [ "$dry" = 0 ]; then
        echo "ci_marker: REFUSED (exit 1): CI-defining' 'if false; then
        echo "ci_marker: REFUSED (exit 1): CI-defining'
MT='plantlib' mutant "R1: the lookup also tries <repo>/../workflows/test_marker.sh" '[ -f "$lib" ] || lib=""' '[ -f "$lib" ] || lib="$repo/../workflows/test_marker.sh"; [ -f "$lib" ] || lib=""'
MT='slug:real' mutant "any origin slug is accepted in the real path" 'if [ "$slug" != "$LK_SLUG" ]; then' 'if false; then'
MT='slug:dry' mutant "the slug NOTE is not printed" 'echo "ci_marker: NOTE the origin is' ': "ci_marker: NOTE the origin is'
MT='gitenv' mutant "the git environment is not dropped" 'unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES' ':'
MT='replace' mutant "replace refs are honoured" 'export GIT_NO_REPLACE_OBJECTS=1' ':'
MT='NOTE these' mutant "no NOTE about the CI-defining files" '    echo "ci_marker: NOTE these CI-defining' '    : "ci_marker: NOTE these CI-defining'
MT='NOTE these' mutant "the NOTE always fires" 'if [ -n "$cidl" ]; then' 'if true; then'
MT='NOTE these' mutant "the tsv is not among the compared files" 'tools/ci_marker.sh tools/ci_marker_jobs.tsv tools/ci_api.sh' 'tools/ci_marker.sh tools/ci_api.sh'
MT='checklist origin' mutant "the verdict does not name the origin/main it read" 'else osha="origin/main $(git -C "$repo" rev-parse --short=12 refs/remotes/origin/main)"; fi' 'else osha="origin/main"; fi'
MT='detached' mutant "no NOTE for a detached HEAD" 'case "$hb" in main | master | "")' 'case "$hb" in zzz)'
MT='lsfail:others' mutant "a git error of ls-files --others passes" ' || add "tree: git error (ls-files --others)"' ' || true'
MT='lsfail:v' mutant "a git error of ls-files -v passes" ' || add "tree: git error (ls-files -v)"' ' || true'
MT='lsfail:diff' mutant "a git error of git diff is read as unstaged changes" '{ [ "$drc" = 1 ] && add "tree: unstaged changes in the working tree" || add "tree: git error (diff, exit $drc)"; }' 'add "tree: unstaged changes in the working tree"'
MT='^drop' mutant "a missing job is fine" 'print("PROBLEM %s / %s: job missing" % (w, name))' 'pass'
MT='^pending' mutant "a pending run is skipped, not reported" 'print("PENDING %s: run %s is %s" % (w, r["id"], r["status"]))' 'pass'
MT='^runfail|^stale' mutant "the run conclusion is not read" 'if r["conclusion"] != "success":' 'if False:'
MT='^ok@clean@0@yes' mutant "the launch fingerprint is not handed to the writer" '"$fp" || exit 1' '"" || exit 1'
MT='nofp' mutant "no launch fingerprint is accepted" '[ -n "$fp" ] || {' 'true || {'
MT='nowrite' mutant "exit 0 without check_marker (a failed write passes)" 'check_marker "$repo"; ckrc=$?' 'ckrc=0'
MT='^pr' mutant "the event of the run is not read (pull_request runs count)" 'r["event"] == "push" and ' ''
MT='^otherpath' mutant "the workflow file of the run is not read" '(r.get("path") or "").split("@")[0] == WF[w]' 'True'
MT='^stale' mutant "the OLDEST run of a workflow decides, not the latest" 'r = max(cand,' 'r = min(cand,'
MT='^page2' mutant "the page loop stops after page 1" 'if len(got) < 100:' 'if True:' 'if tc != len(out):' 'if False:'
MT='^jobsha|^nohead' mutant "the per-job head_sha is not checked" 'if j.get("head_sha") != sha:' 'if False:'
MT='^nohead' mutant "a job without a head_sha is trusted (get with a default)" 'if j.get("head_sha") != sha:' 'if j.get("head_sha", sha) != sha:'
MT='^runtotal' mutant "the runs total_count is not compared" 'if total > len(allruns):' 'if False:'
MT='^badtotal' mutant "the jobs total_count is not compared" 'if tc != len(out):' 'if False:'
MT='tsv:dup' mutant "a duplicate tsv row is accepted" 'if j in required.setdefault(w, {}):' 'if False:'
MT='tsv:missing' mutant "a tsv without a workflow is accepted" 'if set(required) != set(WF) or not all(required.values()):' 'if False:'
MT='tsv:foreign' mutant "a tsv naming another workflow is accepted" 'if w not in WF:' 'if False:'
MT='@plant@' mutant "python without -I (cwd / PYTHONPATH imports)" 'python3 -I -c "$PY"' 'python3 -c "$PY"'
MT='@seam:' mutant "seams accepted in the real write path" 'if [ "$dry" = 0 ] && [ -n "$seams" ]; then' 'if false; then'
MT='tree:lax' mutant "reads the tree's tsv instead of origin/main" 'git -C "$repo" show refs/remotes/origin/main:tools/ci_marker_jobs.tsv > "$jt" 2> /dev/null ||' 'cp "$repo/tools/ci_marker_jobs.tsv" "$jt" 2> /dev/null ||'
MT='org:nofile' mutant "a missing file at origin/main is ignored (the tree's tsv is used)" 'origin/main holds no tools/ci_marker_jobs.tsv: the job checklist is read from there (first gate, before the tool is on main: --dry-run --bootstrap-jobs-from-tree)"; exit 2; }' 'origin/main holds no tools/ci_marker_jobs.tsv"; cp "$repo/tools/ci_marker_jobs.tsv" "$jt"; }'
MT='org:noref' mutant "a missing origin/main ref is ignored" 'refs/remotes/origin/main > /dev/null ||' 'refs/remotes/origin/main > /dev/null || true ||'
MT='boot:' mutant "the bootstrap option is allowed in the real path" 'if [ "$bootstrap" = 1 ] && [ "$dry" = 0 ]; then' 'if false; then'
MT='boot:real@NOTE' mutant "the bootstrap option is ignored (origin/main is always read)" 'if [ "$bootstrap" = 1 ]; then'$'\n' 'if false; then'$'\n'
MT='seamdry' mutant "CI_MARKER_JOBS_TSV is accepted with --dry-run" 'if [ -n "${CI_MARKER_JOBS_TSV:-}" ]; then' 'if false; then'

echo "test_ci_marker: $pass passed, $fail failed"
[ "$fail" = 0 ]
