#!/usr/bin/env bash
# ORIGINAL: no swipl-devel counterpart — the LOCAL run of the cheap steps of the `compile` job of
# .github/workflows/ci-compile.yml (audit D-0677 item 1): fmt, port_check, bool_atoms, where_return, the tool cases and
# the cheap test files, in the workflow's order and with the workflow's own step lines, before a push to a ci/ ref.
#
#   tools/pre_ci.sh [--only STEP] [--list]       (cwd: ignored, the script works in the repo root it lives in)
#
# THE LIST IS THE WORKFLOW'S: every `tools/ci_compile_run.sh [--needs N] NAME COMMAND...` line of the compile job is read
# from the workflow file (PRE_CI_WORKFLOW overrides the file, for tools/test_pre_ci.sh) and run VERBATIM, so the
# invocation is CI's and the list cannot drift from it. A `for f in A B; do ... "$(basename "$f" .jl)" ...` loop is
# expanded per file, an `export X=1` line of the same block is applied. Not run, by design: `instantiate` and
# `precompile` (the first julia call of a later step precompiles; their .rc is recorded as 0 here so a `--needs` is met).
# One line per step: `pre_ci: NAME exit RC  FIRST FAILING LINE` (the extractor of tools/ci_compile_summary.py, the
# summary's own); a step whose guard (`if [ -f X ]`) is false is `not run`. Steps run one after the other (one julia
# process at a time), the output of each in $PRE_CI_LOGS/NAME.log (default: a fresh temp dir, printed at the end).
# Julia: the juliaup binary of tools/WARM_JULIA_VERSION is put first on PATH (a warning if `julia` is another one).
# Exit status: 0 every step passed (or skipped / not run), 1 a step failed, 2 usage or an unknown step.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2
WF="${PRE_CI_WORKFLOW:-$ROOT/.github/workflows/ci-compile.yml}"
only="" list=0
while [ $# -gt 0 ]; do
    case "$1" in
        --only) [ $# -ge 2 ] || { echo "usage: tools/pre_ci.sh [--only STEP] [--list]" >&2; exit 2; }; only="$2"; shift 2 ;;
        --list) list=1; shift ;;
        *) echo "usage: tools/pre_ci.sh [--only STEP] [--list]" >&2; exit 2 ;;
    esac
done
[ -f "$WF" ] || { echo "pre_ci: no workflow file $WF" >&2; exit 2; }

# the steps: NAME <TAB> PRELUDE <TAB> LINE, one per step, in the workflow's order
steps="$(python3 -I - "$WF" << 'PYEOF'
import re, sys
text = open(sys.argv[1]).read().splitlines()
# the `compile:` job only (when the file has jobs); else the whole file
start, end = 0, len(text)
for i, ln in enumerate(text):
    if re.match(r"^  compile:\s*$", ln):
        start = i + 1
        for j in range(i + 1, len(text)):
            if re.match(r"^  [A-Za-z_][\w-]*:\s*$", text[j]):
                end = j
                break
        break
exports, loop = [], None
for ln in text[start:end]:
    s = ln.strip()
    if s.startswith("- name:") or s.startswith("run:") and s.endswith("|"):
        exports, loop = [], None
        continue
    if s.startswith("#") or not s:
        continue
    m = re.match(r"for f in (.*?);\s*do\s*$", s)
    if m:
        loop = m.group(1).split()
        continue
    if s == "done":
        loop = None
        continue
    if s.startswith("export "):
        exports.append(s)
        continue
    s = re.sub(r"^run:\s*", "", s)
    m = re.search(r"tools/ci_compile_run\.sh\s+(?:--needs\s+\S+\s+)?(\S+)", s)
    if not m:
        continue
    prelude = "; ".join(exports) or ":"
    if "$(basename" in m.group(1) and loop:
        for f in loop:
            name = re.sub(r"\.jl$", "", f.rsplit("/", 1)[-1])
            print("%s\t%s; f=%s\t%s" % (name, prelude, f, s))
    else:
        print("%s\t%s\t%s" % (m.group(1).strip('"'), prelude, s))
PYEOF
)" || exit 2

if [ "$list" = 1 ]; then
    printf '%s\n' "$steps" | cut -f1
    exit 0
fi
if [ -n "$only" ] && ! printf '%s\n' "$steps" | cut -f1 | grep -qxF -- "$only"; then
    echo "pre_ci: no step named $only in $WF (steps: $(printf '%s\n' "$steps" | cut -f1 | tr '\n' ' '))" >&2
    exit 2
fi

wantv="$(awk 'NR == 1 { print $1 }' tools/WARM_JULIA_VERSION 2> /dev/null)"
[ -n "$wantv" ] || wantv=1.13.3
for d in "$HOME"/.julia/juliaup/julia-"$wantv"*/bin; do
    [ -x "$d/julia" ] && PATH="$d:$PATH" && break
done
if command -v julia > /dev/null 2>&1; then
    case "$(julia --version 2> /dev/null)" in *" $wantv"*) ;; *) echo "pre_ci: warning: julia on PATH is not $wantv" >&2 ;; esac
fi
export CI_COMPILE_LOGS="${PRE_CI_LOGS:-$(mktemp -d "${TMPDIR:-/tmp}/pre-ci.XXXXXX")}"
mkdir -p "$CI_COMPILE_LOGS"
# the steps this script does not run: their .rc says 0 so a `--needs` of a later step is met
for s in instantiate precompile; do echo 0 > "$CI_COMPILE_LOGS/$s.rc"; : > "$CI_COMPILE_LOGS/$s.log"; done

status=0
while IFS=$'\t' read -r name prelude line; do
    [ -n "$name" ] || continue
    case "$name" in instantiate | precompile) continue ;; esac
    [ -z "$only" ] || [ "$name" = "$only" ] || continue
    rm -f "$CI_COMPILE_LOGS/$name.rc"
    bash -c "$prelude; $line" < /dev/null > /dev/null 2>&1
    if [ ! -f "$CI_COMPILE_LOGS/$name.rc" ]; then
        echo "pre_ci: $name not run (its guard is false)"
        continue
    fi
    rc="$(cat "$CI_COMPILE_LOGS/$name.rc")"
    case "$rc" in
        0) echo "pre_ci: $name exit 0" ;;
        skipped) echo "pre_ci: $name skipped (a step it needs failed)" ;;
        *)
            first=""
            read -r first < <(python3 -I "$ROOT/tools/ci_compile_summary.py" --first-lines "$name" "$CI_COMPILE_LOGS/$name.log" 2> /dev/null)
            echo "pre_ci: $name exit $rc  $first"
            status=1
            ;;
    esac
done <<< "$steps"
echo "pre_ci: logs in $CI_COMPILE_LOGS"
exit "$status"
