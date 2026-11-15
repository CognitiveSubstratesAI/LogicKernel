#!/bin/bash -p
# ORIGINAL: a tool of this repository only — the machine-written evidence marker from a GREEN CI run (audit D-0680 item 1b,
# evidence/GATE/ci_parity.md Part 5). The commit hook accepts a marker only when workflows/test_marker.sh `write_marker`
# wrote it for THIS tree; this tool calls that writer, and only after the GitHub API says that the workflows CI and
# Evidence (three term types) ran on the EXACT commit SHA with every required job at its expected conclusion.
#
#   tools/ci_marker.sh [--dry-run [--bootstrap-jobs-from-tree] [--writer-stub FILE]] [--sha SHA] [--repo DIR]
#   --sha SHA   the commit the gate/<step> push carried (default HEAD); resolved to the full SHA
#   --repo DIR  the repository whose tree is certified (default: the clone this script is in)
#   --dry-run   run every check and print the verdict; write nothing
#   --bootstrap-jobs-from-tree   --dry-run ONLY: read the job checklist from the tree's own tools/ci_marker_jobs.tsv (before the
#               tool is on main, so that it can be exercised); with a real write it is refused (exit 2)
#   --writer-stub FILE   TEST MODE, --dry-run ONLY (exit 2 otherwise): the write path (start_marker, write_marker, check_marker) runs
#               against the functions of FILE instead of the real writer, which is then never sourced. The stub runs with TMPDIR set to
#               a fresh directory (printed: `NOTE --writer-stub: TMPDIR=<dir>`, the caller removes it), so a stub that wraps the real
#               write_marker writes its marker there, not into the caller's TMPDIR (review3 B2). It is a TEST SEAM used with fixtures: a stub
#               that writes a real path by absolute name is arbitrary code the caller chose and cannot be stopped from inside the process.
# THE CHECKLIST (audit D-0693 item 5: the tree under test must not choose its own checklist): tools/ci_marker_jobs.tsv is read from
# the COMMITTED main of the repository under --repo, `git show refs/remotes/origin/main:tools/ci_marker_jobs.tsv`; the caller fetches
# first (this tool never does). No origin/main ref, or no such file there (the first gate, before the tool is on main) is exit 2.
#
# The checks (all must hold; the verdict lists every failed one):
#   1. TREE: `git rev-parse SHA^{tree}` equals the tree of the index (`git write-tree`), there is no unstaged change and no
#      untracked file. The marker authorizes a TREE (the commit about to be made, an amend, a rebase onto an unchanged
#      base), never a different one; the writer's own fingerprint is taken before the API is read and handed back to it.
#   2. RUNS: per required workflow (the two names and their files are written into this script, not read from the tsv) a
#      run with head_sha == SHA (checked here too, not only by the API's filter), event `push` and the workflow's own file
#      (a pull_request run judged the MERGE tree); the latest of them completed with conclusion success. A runs answer
#      with more runs than it carries (total_count) is unreadable.
#   3. JOBS, by name, per run (GET /actions/runs/{id}/jobs, never check-runs: `static analysis k/9` has three homes, the
#      lower case one of Evidence, CI's `Static analysis k/9`, ci-compile's): every job of tools/ci_marker_jobs.tsv present
#      with its expected conclusion (success, or skipped for the by-design skips of a gate push); a job the file does not
#      list is refused (fail closed; a name that differs by one character is both an unlisted job and a missing one), a
#      missing one is a failure, never green. The file is refused (exit 2) when it has a duplicate (workflow, job) row, a
#      workflow other than the two, or lacks one; the jobs of a run are paged to the end and their total_count must agree.
#   4. the tracked files: no assume-unchanged / skip-worktree flag (git diff would be blind to such a file).
# RUN THIS TOOL FROM A CLONE WHOSE tools/ ARE MAIN'S (the tool, tools/ci_api.sh, the tsv and the workflow files of the tree under
# test are the tree's own, review2 N4): the verdict prints a NOTE listing which of .github/workflows/*, .github/actions/*,
# tools/ci_marker.sh, tools/ci_marker_jobs.tsv, tools/ci_api.sh differ between origin/main and SHA (a tree that empties its own CI steps
# and keeps the job names is judged by its own CI). The verdict line names the origin/main commit the checklist was read from (N5).
# A commit that edits tools/ci_marker_jobs.tsv or renames/adds a CI job is judged by the OLD list (origin/main) and refused until main
# carries the new tsv: land such a change by the local branch-gate; then the new list is main's.
# CI-DEFINING FILES (review3 B3): a real run REFUSES (exit 1, the file list) when any of .github/workflows, .github/actions,
# tools/ci_marker.sh, tools/ci_marker_jobs.tsv, tools/ci_api.sh, and (review4 F3) the scripts the workflows call to gather a verdict:
# tools/evidence_ci.py, tools/ci_compile_summary.py, tools/ci_compile_run.sh, tools/lib_evidence.sh, differs between origin/main and SHA:
# the tool cannot see the steps the tree's own CI ran, so such a commit is judged by the local branch-gate, not by its own CI. A failing
# `git diff` of these files is itself a refusal (exit 2), never an empty list. --dry-run prints the NOTE only. A tree that neuters
# tools/run_tests.sh or the tests themselves is judged by its own CI by construction: only the dispatcher's author/diff check closes that.
# The writer (review2 N1, review3 B1/R1): the REAL path never accepts a caller-chosen writer. PRIVILEGED MODE: the script is `#!/bin/bash -p`
# and re-executes itself under `bash -p` when it was started another way (`bash tools/ci_marker.sh`): privileged mode imports no exported
# function and ignores the startup files and the shell-option variables of the caller. The first lines use only reserved words and
# parameter expansions, plus `exec` and `exit`, because a function named like a builtin shadows a builtin (an exported compgen, unset, read,
# exec ...): an unprivileged shell after the re-exec (an exported `exec` made it a no-op) ends at a `${var:?}` expansion of a variable this
# script has just ASSIGNED empty (a parameter assignment cannot be shadowed by a function; a name the script did not assign could be
# pre-exported by the caller, review4 F1), which no function can intercept. The caller's BASH_ENV, ENV, PROMPT_COMMAND, CDPATH set, SHELLOPTS / BASHOPTS exported, or a PS4 other than the default is
# exit 2, checked with `[[ -v ]]` and `${v@a}`, never printed (SHELLOPTS=privileged in the environment gives a privileged shell WITH the
# imported functions). IFS is never imported by bash from the environment. The function purge below stays as a second layer. The writer
# is sourced from the ONE candidate $HOME/code/CognitiveSubstratesAI/workflows/test_marker.sh (the dispatcher's workspace; never a path
# next to the repository under --repo), and write_marker/start_marker/check_marker must then be defined BY THAT FILE (declare -F under
# extdebug).
# PATH (review4 F2): the script assigns PATH=/usr/local/bin:/usr/bin:/bin in its first lines (python3, git, curl, realpath, mktemp and the
# writer's sha256sum / find all live there on the dispatcher's machine), and tools/ci_api.sh calls curl with `-q --noproxy '*'` (no
# ~/.curlrc, no proxy of the caller): a python3 / git / curl placed first in the caller's PATH is not run.
# RESIDUAL, stated honestly (review4): refs/remotes/origin/main is a LOCAL ref. A caller who runs `git update-ref refs/remotes/origin/main
# <SHA>` makes the checklist the tree's own tsv and the CI-defining diff empty; the tool cannot detect that. The caller also owns HOME and the
# files under it (a fake lib at the looked-up path), GIT_CONFIG_* / CURL_CA_BUNDLE style variables, and any code that ran before this script
# started. In the reviewer's words: the tool holds against exported shell functions, startup/option variables, the interpreter used to run it,
# a planted writer next to --repo, and a CI-defining file that differs from origin/main in a real run; it does NOT hold, and cannot from inside
# the process, against a caller who owns the process environment and the clone, nor against one who writes the marker file by hand or sources
# the real write_marker himself. The marker rule (D-0094) protects against mistakes and drift, not against a determined local actor: the
# deliberate caller is stopped only by the commit hook's own marker rule, the marker being accepted on a BRANCH commit only (never main), and
# the dispatcher's author/diff check, the only reader of a tree whose tests, run_tests.sh or evidence_ci.py were neutered.
# The origin must be the LogicKernel repository (review2 N2): another slug is exit 2, a NOTE in --dry-run (the fixture repos).
# The marker's label starts with `branch-gate`: the commit hook takes that label on a BRANCH commit only, never on main (an
# unknown label such as `ci-green` would pass as a full-suite run, also on main). The writer's 30-minute age rule stays.
# Scope: the gate/<step> profile (the tsv). A main or perf/ci-** push has other job sets (Evidence is not started there).
# Not read: the `Mutation battery` run of mutants/<STEP> at the same SHA (the dispatcher reads it by name).
#
# Exit: 0 verdict OK (marker written AND verified by check_marker, or --dry-run) / 1 refused / 3 a required run is not completed
# yet, or has not registered at this SHA yet (retry; give up after about 10 minutes) / 2 unreadable or usage.
# API route: tools/ci_api.sh (anonymous first, then the stored token on curl's STDIN; nothing of it printed or written).
# THE TEST SEAMS (tools/test_ci_marker.sh) work in --dry-run only: CI_MARKER_FIXTURE_DIR=<dir> (a fake API: <dir>/runs_<sha>.json,
# <dir>/<run>/jobs_<page>.json), and the two variables LOGICKERNEL_CI_FIXTURE_DIR / LOGICKERNEL_WORKSPACE. Without --dry-run any of
# these three, or CI_MARKER_JOBS_TSV, set is exit 2 (review TOOL4B B1: a hand-made fixture must never reach the real writer, D-0094);
# CI_MARKER_JOBS_TSV is no longer read at all (a set one is exit 2 in --dry-run too: the checklist comes from origin/main).
# CI_MARKER_TEST_WRITER is gone (review2 N1): set at all is exit 2, in the real path and in --dry-run; the test uses --writer-stub.
# --- review3 B1: the FIRST executable lines (reserved words and parameter expansions only; see the header) ---
_bad="" _refused="" _unprivileged="" _g=""
# review4 F2: an assignment; no caller-chosen python3 / git / curl is found (every tool this script and the writer call lives there)
PATH=/usr/local/bin:/usr/bin:/bin
for _v in BASH_ENV ENV PROMPT_COMMAND CDPATH; do [[ -v $_v ]] && _bad="$_bad $_v"; done
for _v in SHELLOPTS BASHOPTS; do [[ ${!_v@a} == *x* ]] && _bad="$_bad $_v(exported)"; done
[[ $PS4 == '+ ' ]] || _bad="$_bad PS4"
[[ -z $_bad ]] || { echo "ci_marker: REFUSED (exit 2): the caller sets:$_bad (names only; not read, not trusted, review3 B1): unset them"; exit 2; }
[[ -z $_bad ]] || _g=${_refused:?ci_marker: REFUSED: the caller sets:$_bad}
[[ $- == *p* ]] || exec "$BASH" -p "$0" "$@"
[[ $- == *p* ]] || { echo "ci_marker: REFUSED (exit 2): not in privileged mode (bash -p) and the re-exec did not happen"; exit 2; }
[[ $- == *p* ]] || _g=${_unprivileged:?ci_marker: REFUSED: not in privileged mode}
set -u
# review2 N1/N3: nothing inherited decides what runs here: imported functions (a function named write_marker, git, curl) are dropped,
# the git environment of a hook / `git rebase -x` is dropped, and a refs/replace entry cannot change a tree or the tsv blob
# (second layer behind privileged mode; builtin-qualified, enumerated by declare -F)
while builtin read -r _d _x _f; do builtin unset -f "$_f"; done < <(builtin declare -F)
unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES
export GIT_NO_REPLACE_OBJECTS=1
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
dry=0 bootstrap=0 sha="" repo="$ROOT" wstub=""
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) dry=1; shift ;;
        --bootstrap-jobs-from-tree) bootstrap=1; shift ;;
        --writer-stub) wstub="${2:-}"; [ -f "$wstub" ] || { echo "ci_marker: --writer-stub needs a file"; exit 2; }; shift 2 ;;
        --sha) sha="${2:-}"; [ -n "$sha" ] || { echo "ci_marker: --sha needs a commit"; exit 2; }; shift 2 ;;
        --repo) repo="${2:-}"; [ -d "$repo" ] || { echo "ci_marker: --repo needs a directory"; exit 2; }; shift 2 ;;
        *) echo "usage: tools/ci_marker.sh [--dry-run [--bootstrap-jobs-from-tree] [--writer-stub FILE]] [--sha SHA] [--repo DIR]"; exit 2 ;;
    esac
done
if [ "$bootstrap" = 1 ] && [ "$dry" = 0 ]; then
    echo "ci_marker: REFUSED (exit 2): --bootstrap-jobs-from-tree is allowed only with --dry-run; a real marker takes its job checklist"
    echo "ci_marker: from origin/main, never from the tree under test (audit D-0693 item 5)."
    exit 2
fi
if [ -n "$wstub" ] && [ "$dry" = 0 ]; then
    echo "ci_marker: REFUSED (exit 2): --writer-stub is allowed only with --dry-run; the real path never takes a caller-chosen writer (D-0094)"
    exit 2
fi
if [ -n "${CI_MARKER_TEST_WRITER:-}" ]; then
    echo "ci_marker: REFUSED (exit 2): CI_MARKER_TEST_WRITER is no longer read; the real path takes no caller-chosen writer (D-0094); the test uses --dry-run --writer-stub"
    exit 2
fi
wmode=real; [ "$dry" = 1 ] && wmode=none; [ -n "$wstub" ] && wmode=stub
repo="$(git -C "$repo" rev-parse --show-toplevel 2> /dev/null)" || { echo "ci_marker: $repo is no git repository"; exit 2; }
full="$(git -C "$repo" rev-parse --verify --quiet "${sha:-HEAD}^{commit}")" || { echo "ci_marker: ${sha:-HEAD}: not a commit of $repo"; exit 2; }
sha="$full"
# B1: the test seams are for --dry-run (read only) and for the test's own writer; a real write refuses them
seams=""
for v in CI_MARKER_FIXTURE_DIR LOGICKERNEL_CI_FIXTURE_DIR CI_MARKER_JOBS_TSV LOGICKERNEL_WORKSPACE; do
    [ -n "${!v:-}" ] && seams="$seams $v"
done
if [ "$dry" = 0 ] && [ -n "$seams" ]; then
    echo "ci_marker: REFUSED (exit 2): a test seam is set:$seams. A fixture, another tsv or another workspace must never reach a real marker"
    echo "ci_marker: (D-0094); unset them, or use --dry-run."
    exit 2
fi
if [ -n "${CI_MARKER_JOBS_TSV:-}" ]; then
    echo "ci_marker: REFUSED (exit 2): CI_MARKER_JOBS_TSV is no longer read: the job checklist comes from origin/main (--dry-run: or the tree, with --bootstrap-jobs-from-tree)"
    exit 2
fi
unset LOGICKERNEL_CI_FIXTURE_DIR   # only the tool's own seam variable may switch the API route to a fixture
[ -n "${CI_MARKER_FIXTURE_DIR:-}" ] && { export LOGICKERNEL_CI_FIXTURE_DIR="$CI_MARKER_FIXTURE_DIR"; echo "ci_marker: NOTE a fixture API is in use (CI_MARKER_FIXTURE_DIR)"; }
export ROOT="$repo"   # ci_slug reads the origin of the repository being certified
# shellcheck source=/dev/null
. "$(dirname "$0")/ci_api.sh"
# review2 N2: the repository whose CI is read is the LogicKernel repository; a fork has its own Actions and its own workflow text
LK_SLUG="CognitiveSubstratesAI/LogicKernel"
slug="$(ci_slug)"
if [ "$slug" != "$LK_SLUG" ]; then
    if [ "$dry" = 0 ]; then
        echo "ci_marker: REFUSED (exit 2): the origin of $repo is the repository '$slug', not $LK_SLUG: its CI is not the evidence of this repository"
        exit 2
    fi
    echo "ci_marker: NOTE the origin is '$slug', not $LK_SLUG (--dry-run only: a real marker is refused for it)"
fi

# the job checklist: the COMMITTED origin/main of the repository, not the tree under test (audit D-0693 item 5)
jt="$(mktemp "${TMPDIR:-/tmp}/ci_marker_jobs.XXXXXX")"
runs="$(mktemp "${TMPDIR:-/tmp}/ci_marker.XXXXXX")"
trap 'rm -f "$runs" "$jt"' EXIT
if [ "$bootstrap" = 1 ]; then
    [ -f "$repo/tools/ci_marker_jobs.tsv" ] || { echo "ci_marker: --bootstrap-jobs-from-tree: $repo/tools/ci_marker_jobs.tsv is not a file"; exit 2; }
    cp "$repo/tools/ci_marker_jobs.tsv" "$jt"
    echo "ci_marker: NOTE --bootstrap-jobs-from-tree: the checklist is the tree's own tsv (a dry run before the tool is on main)"
else
    git -C "$repo" rev-parse --verify --quiet refs/remotes/origin/main > /dev/null ||
        { echo "ci_marker: no origin/main (refs/remotes/origin/main) in $repo: the job checklist is read from there; fetch first (first gate, before the tool is on main: --dry-run --bootstrap-jobs-from-tree)"; exit 2; }
    git -C "$repo" show refs/remotes/origin/main:tools/ci_marker_jobs.tsv > "$jt" 2> /dev/null ||
        { echo "ci_marker: origin/main holds no tools/ci_marker_jobs.tsv: the job checklist is read from there (first gate, before the tool is on main: --dry-run --bootstrap-jobs-from-tree)"; exit 2; }
fi

# the writer: the real one (real path) or the test's stub (--dry-run --writer-stub); not needed for a plain --dry-run
if [ "$wmode" != none ]; then
    if [ "$wmode" = stub ]; then
        lib="$wstub"
        sbx="$(mktemp -d "${TMPDIR:-/tmp}/ci_marker_stub.XXXXXX")" || { echo "ci_marker: no scratch directory for --writer-stub"; exit 2; }
        export TMPDIR="$sbx"   # before the stub is sourced: marker_path of a stub that wraps the real writer lands here (review3 B2)
        echo "ci_marker: NOTE --writer-stub: test mode, the stub stands in for the writer; TMPDIR=$sbx (a marker of a stub that follows TMPDIR lands there; the caller removes it)"
    else
        lib="$HOME/code/CognitiveSubstratesAI/workflows/test_marker.sh"   # review3 R1: the ONE candidate, never a path next to --repo
        [ -f "$lib" ] || lib=""
        [ -n "$lib" ] || { echo "ci_marker: no workflows/test_marker.sh (write_marker): no marker can be written here"; exit 2; }
    fi
    . "$lib"
    shopt -s extdebug
    dfs="$(declare -F write_marker start_marker check_marker 2> /dev/null)"
    shopt -u extdebug
    libr="$(realpath -e "$lib" 2> /dev/null)"
    nd=0
    while read -r _n _l _f; do
        [ -n "$libr" ] && [ "$(realpath -e "$_f" 2> /dev/null)" = "$libr" ] && nd=$((nd + 1))
    done <<< "$dfs"
    [ "$nd" = 3 ] ||
        { echo "ci_marker: REFUSED (exit 2): write_marker, start_marker and check_marker are not all defined by $lib: no marker can be written here"; exit 2; }
    fp="$(start_marker "$repo")"   # BEFORE the API is read: an edit during the check makes write_marker refuse
    [ -n "$fp" ] || { echo "ci_marker: the writer gave no launch fingerprint: no marker can be written"; exit 2; }
fi

# review2 N4/N5/N12: what the tree under test brings along, and where the checklist came from
if [ "$bootstrap" = 1 ]; then osha="the tree's own tsv (bootstrap)"; else osha="origin/main $(git -C "$repo" rev-parse --short=12 refs/remotes/origin/main)"; fi
cidl=""
# --dry-run --bootstrap-jobs-from-tree before the tool is on main may have no origin/main yet: nothing to compare against then
if [ "$bootstrap" = 0 ] || git -C "$repo" rev-parse --verify --quiet refs/remotes/origin/main > /dev/null; then
    cidl="$(git -C "$repo" diff --name-only refs/remotes/origin/main "$sha" -- .github/workflows .github/actions tools/ci_marker.sh tools/ci_marker_jobs.tsv tools/ci_api.sh tools/evidence_ci.py tools/ci_compile_summary.py tools/ci_compile_run.sh tools/lib_evidence.sh 2> /dev/null)" ||
        { echo "ci_marker: REFUSED (exit 2): git error (diff of the CI-defining files against origin/main): the files that define CI cannot be compared"; exit 2; }
fi
cid="$(printf '%s\n' "$cidl" | tr '\n' ' ')"   # review4 F3: the diff status is its own, not the status of tr
if [ -n "$cidl" ]; then
    if [ "$dry" = 0 ]; then
        echo "ci_marker: REFUSED (exit 1): CI-defining files differ from origin/main in ${sha:0:12}: $cid"
        echo "ci_marker: the steps its own CI ran cannot be seen from here: land such a commit by the local branch-gate, not by this tool (review3 B3)"
        exit 1
    fi
    echo "ci_marker: NOTE these CI-defining files differ between origin/main and ${sha:0:12} (the tree is judged by its OWN CI for them; run the tool from a clone whose tools/ are main's; a real run REFUSES): $cid"
fi
hb="$(git -C "$repo" symbolic-ref --short -q HEAD 2> /dev/null)"
case "$hb" in main | master | "") echo "ci_marker: NOTE HEAD of $repo is '${hb:-detached}': the commit hook refuses a branch-gate marker on main, master or a detached HEAD" ;; esac

problems=""
add() { problems="$problems$1"$'\n'; }
# 1. the tree
tree_c="$(git -C "$repo" rev-parse "$sha^{tree}")"
tree_i="$(git -C "$repo" write-tree 2> /dev/null)" || tree_i="(unreadable index)"
[ "$tree_c" = "$tree_i" ] || add "tree: commit ${sha:0:12} has tree ${tree_c:0:12}, the index has ${tree_i:0:12}: CI judged a different tree"
git -C "$repo" diff --quiet; drc=$?
[ "$drc" = 0 ] || { [ "$drc" = 1 ] && add "tree: unstaged changes in the working tree" || add "tree: git error (diff, exit $drc)"; }
uo="$(git -C "$repo" ls-files --others --exclude-standard)" || add "tree: git error (ls-files --others)"
[ -z "$uo" ] || add "tree: untracked files in the working tree"
lsv="$(git -C "$repo" ls-files -v)" || add "tree: git error (ls-files -v)"
printf '%s\n' "$lsv" | grep -q '^[a-zS]' && add "tree: a tracked file is flagged assume-unchanged or skip-worktree (git diff cannot see it)"

# 2 + 3. the runs and their jobs
ci_runs_for_sha "$sha" > "$runs"
read -r -d '' PY << 'PYEOF'
import json, subprocess, sys
sha, runs_file, tsv, api, bashbin = sys.argv[1:6]
# the two workflows and their files: written HERE, so that a commit cannot drop a workflow from the tsv it is judged by (N3)
WF = {"CI": ".github/workflows/CI.yml", "Evidence (three term types)": ".github/workflows/evidence.yml"}
def die(msg):
    print("UNREADABLE " + msg)
    sys.exit(2)
def main():
    required = {}          # workflow -> {job: expected}
    for ln in open(tsv, encoding="utf-8"):
        if not ln.strip() or ln.startswith("#"):
            continue
        f = ln.rstrip("\n").split("\t")
        if len(f) != 3 or f[2] not in ("success", "skipped"):
            die("the required-jobs file has a malformed row: %r" % ln)
        w, j, e = f
        if w not in WF:
            die("the required-jobs file names the workflow %r: only %s are known" % (w, sorted(WF)))
        if j in required.setdefault(w, {}):
            die("the required-jobs file has the row %r twice" % ((w, j),))
        required[w][j] = e
    if set(required) != set(WF) or not all(required.values()):
        die("the required-jobs file does not list both workflows")
    try:
        ans = json.load(open(runs_file, encoding="utf-8"))
        allruns, total = ans["workflow_runs"], ans["total_count"]
        assert isinstance(allruns, list) and isinstance(total, int)
    except Exception:
        die("the runs answer of the API")
    if total > len(allruns):
        die("the API counts %d runs of this SHA, the answer carries %d (one page)" % (total, len(allruns)))
    runs = [r for r in allruns if r["head_sha"] == sha]
    def jobs_of(run):
        out, page, tc = [], 1, None
        while page <= 10:
            p = subprocess.run([bashbin, "-p", "-c", '. "$1"; ci_jobs_page "$2" "$3"', "x", api, str(run), str(page)],
                               capture_output=True, text=True, timeout=120)
            try:
                ans = json.loads(p.stdout)
                got = ans["jobs"]
                tc = ans["total_count"] if tc is None else tc
                assert isinstance(got, list) and isinstance(tc, int)
            except Exception:
                die("the jobs answer of run %s" % run)
            out += got
            if len(got) < 100:
                if tc != len(out):
                    die("run %s: the API counts %d jobs, %d were read" % (run, tc, len(out)))
                return out
            page += 1
        die("more than 1000 jobs in run %s" % run)
    for w, want in required.items():
        named = [r for r in runs if r["name"] == w]
        cand = [r for r in named if r["event"] == "push" and (r.get("path") or "").split("@")[0] == WF[w]]
        if not named:
            print("PENDING %s: no run at this SHA yet (a push registers its runs within minutes: retry, and give up after about "
                  "10 minutes, the SHA was then not pushed to a gate branch)" % w)
            continue
        if not cand:
            print("PROBLEM %s: the runs at this SHA are not push runs of %s (events %s, paths %s)" % (
                w, WF[w], sorted({r["event"] for r in named}), sorted({str(r.get("path")) for r in named})))
            continue
        r = max(cand, key=lambda x: x.get("created_at") or "")
        if r["status"] != "completed":
            print("PENDING %s: run %s is %s" % (w, r["id"], r["status"]))
            continue
        if r["conclusion"] != "success":
            print("PROBLEM %s: run %s concluded %s" % (w, r["id"], r["conclusion"]))
            continue
        jobs = jobs_of(r["id"])
        names = set()
        for j in jobs:
            names.add(j["name"])
            if j.get("head_sha") != sha:   # a job without a head_sha is refused, not trusted (review2 N6)
                print("PROBLEM %s / %s: the job ran on %s" % (w, j["name"], j.get("head_sha")))
        for name, exp in want.items():
            got = [j for j in jobs if j["name"] == name]
            if not got:
                print("PROBLEM %s / %s: job missing" % (w, name))
            for j in got:
                if j["status"] != "completed":
                    print("PENDING %s / %s: %s" % (w, name, j["status"]))
                elif j["conclusion"] != exp:
                    print("PROBLEM %s / %s: %s, expected %s" % (w, name, j["conclusion"], exp))
        for name in sorted(names - set(want)):
            print("PROBLEM %s / %s: a job tools/ci_marker_jobs.tsv does not list" % (w, name))
        print("OK-LINE %s: run %s, %d jobs, %d required" % (w, r["id"], len(jobs), len(want)))
try:
    main()
except SystemExit:
    raise
except Exception as e:
    die("an unexpected answer shape (%s)" % type(e).__name__)
PYEOF
out="$(python3 -I -c "$PY" "$sha" "$runs" "$jt" "$(dirname "$0")/ci_api.sh" "$BASH")"; prc=$?
[ "$prc" = 0 ] || { printf '%s\n' "$out" | sed 's/^UNREADABLE /ci_marker: unreadable: /'; exit 2; }
printf '%s\n' "$out" | sed -n 's/^OK-LINE /ci_marker: /p'
problems="$problems$(printf '%s\n' "$out" | sed -n 's/^PROBLEM //p')"
pend="$(printf '%s\n' "$out" | sed -n 's/^PENDING \(.*\)/\1/p')"
if [ -n "$(printf '%s' "$problems" | tr -d '\n')" ]; then
    printf '%s' "$problems" | grep . | head -20 | sed 's/^/ci_marker: REFUSED  /'
    echo "ci_marker: verdict REFUSED for ${sha:0:12} (checklist $osha), no marker written"
    exit 1
fi
if [ -n "$pend" ]; then
    printf '%s\n' "$pend" | head -20 | sed 's/^/ci_marker: pending  /'
    echo "ci_marker: verdict PENDING for ${sha:0:12} (checklist $osha), no marker written"
    exit 3
fi
echo "ci_marker: verdict OK for ${sha:0:12} (tree ${tree_c:0:12}, checklist $osha)"
if [ "$wmode" = none ]; then
    echo "ci_marker: --dry-run: nothing written"
    exit 0
fi
write_marker "$repo" 0 "branch-gate (CI evidence: CI and Evidence green at ${sha:0:12}, tools/ci_marker.sh; a BRANCH commit only, never main)" "$fp" || exit 1
# exit 0 only when the marker is there and valid for this tree (write_marker returns 0 after a failed write)
check_marker "$repo"; ckrc=$?
[ "$ckrc" = 0 ] || { echo "ci_marker: REFUSED: the marker is not valid after the write (check_marker $ckrc)"; exit 1; }
echo "ci_marker: marker verified by check_marker"
