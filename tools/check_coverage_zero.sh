#!/usr/bin/env bash
# ORIGINAL: the coverage_zero ratchet, run BEFORE the push on the src/ files the push changes (audit
# D-0178 item 2; F1a's gate/f1a was red on exactly this — "pl-prologflag.jl is no longer at 0%" —
# with every test green). No swipl-devel counterpart.
#
#   tools/check_coverage_zero.sh [--lcov FILE] [BASE [REV]]
#
# BASE defaults to refs/remotes/origin/main, REV to HEAD. "The files the push changes" = the src/*.jl
# files of `git diff BASE...REV` (against the merge base). The list read is REV's
# tools/coverage_zero_known.txt, so what is judged is the commit that is pushed, not the working tree.
# Exit 0 = nothing found, 1 = a refusal (<= 10 lines: the file, the reason, the fix), 2 = no verdict
# (unreadable ref/list: fail closed, like the pre-push hook around it).
#
# WHAT CI CHECKS, AND WHAT THIS CAN AND CANNOT DO. CI (.github/workflows/CI.yml, "No src/ file at 0%
# coverage") feeds the LCOV of the three Pkg.test groups — real line coverage — to tools/coverage_zero.py,
# which fails a file at 0% that is not listed AND a listed file that is no longer at 0%. An LCOV needs the
# whole suite under coverage (hours); no local lane makes it. So there are two modes:
#
#   with --lcov FILE (or LOGICKERNEL_COVZERO_LCOV=FILE through the hook): the SAME verdict as CI, from
#     tools/coverage_zero.py's own functions, restricted to the changed src/ files — meant for an LCOV
#     the caller has (a CI artifact of an earlier run of the branch, a local coverage run of the new
#     tests). Limits: unseen src/ files are read from the WORKING tree, so the checkout must be REV; a
#     partial LCOV is meaningful only for the files it ran.
#
#   without it (the pre-push default): a STATIC PROXY, three checks, none of which measures coverage:
#     1. a listed file that is not in src/ at REV (deleted, renamed)          -> CI: "no longer at 0%"
#        (exact: coverage_zero.py takes a missing file as not at 0%).
#     2. a changed src/ file that no include("...") in src/ loads, and that is not listed
#        -> CI: "is at 0%" (exact: a file never loaded has no record in the LCOV and counts as 0%;
#        a match is by the file's basename inside an include("...") string, the package's root file exempt).
#     3. a changed src/ file that is listed AND was already listed at the merge base (a line this push adds
#        is a deliberate listing): the push gives code to a file declared 0%. If the tests now
#        run it CI fails "no longer at 0%" (F1a); if it is still 0% (structural, e.g.
#        precompile_workload.jl) say so with LOGICKERNEL_COVZERO_ACK="src/x.jl ..." (exactly those files).
#        This is a heuristic with false positives by design (fail closed), the one thing it cannot do is
#        see whether the code was run.
#     NOT covered by the proxy: a new or changed file that is loaded but whose code no test runs (CI's
#     "is at 0%" for a loaded file), and a listed file newly covered by a push that does not change it
#     (tests only). Those are CI's alone; run with --lcov to catch them.
set -uo pipefail

lcov=${LOGICKERNEL_COVZERO_LCOV:-}
while [ $# -gt 0 ]; do
    case "$1" in
        --lcov) lcov=${2:-}; shift 2 || { echo "check_coverage_zero: --lcov needs a file" >&2; exit 2; } ;;
        --) shift; break ;;
        -*) echo "check_coverage_zero: unknown option $1" >&2; exit 2 ;;
        *) break ;;
    esac
done
base=${1:-refs/remotes/origin/main}
rev=${2:-HEAD}
KNOWN=tools/coverage_zero_known.txt

top=$(git rev-parse --show-toplevel 2> /dev/null) || { echo "check_coverage_zero: not in a git repository" >&2; exit 2; }
g() { git -C "$top" "$@"; }
g rev-parse --verify -q "$base^{commit}" > /dev/null || { echo "check_coverage_zero: no verdict — cannot read $base (fetch the remote first)" >&2; exit 2; }
g rev-parse --verify -q "$rev^{commit}" > /dev/null || { echo "check_coverage_zero: no verdict — cannot read $rev" >&2; exit 2; }
mb=$(g merge-base "$base" "$rev" 2> /dev/null) || { echo "check_coverage_zero: no verdict — $base and $rev share no history" >&2; exit 2; }
known_txt=$(g show "$rev:$KNOWN" 2> /dev/null) || { echo "check_coverage_zero: no verdict — $rev has no $KNOWN" >&2; exit 2; }
if [ -n "$lcov" ] && [ ! -s "$lcov" ]; then
    echo "check_coverage_zero: no verdict — the LCOV file '$lcov' is missing or empty" >&2
    exit 2
fi

# the listed files (comments and blanks dropped, as coverage_zero.py's known_files does)
known=$(printf '%s\n' "$known_txt" | sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | sed '/^$/d')
known_base=$(g show "$mb:$KNOWN" 2> /dev/null | sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | sed '/^$/d' || true)
present=$(g ls-tree -r --name-only "$rev" -- src | grep -E '\.jl$' || true)
# changed src/*.jl files that exist at REV (added or modified); a deleted one is check 1's business
changed=$(g diff --name-only --no-renames --diff-filter=AMT "$mb" "$rev" -- src | grep -E '\.jl$' || true)

fails=()
fail() { fails+=("check_coverage_zero: $1 — $2; fix: $3"); }
in_list() { printf '%s\n' "$2" | grep -qxF -- "$1"; }

# 1. every listed file must exist (also in --lcov mode: the list is the commit's)
while IFS= read -r f; do
    [ -n "$f" ] || continue
    in_list "$f" "$present" || fail "$f" "listed in $KNOWN but not in src/ at ${rev:0:7} (deleted or renamed)" "remove the line from $KNOWN"
done <<< "$known"

root_file=""
name=$(g show "$rev:Project.toml" 2> /dev/null | sed -n 's/^name[[:space:]]*=[[:space:]]*"\(.*\)"/\1/p' | head -n 1)
[ -n "$name" ] && root_file="src/$name.jl"

if [ -n "$lcov" ]; then
    # the SAME verdict as CI (tools/coverage_zero.py's own functions), restricted to the changed files
    out=$(python3 - "$top" "$lcov" "$known" "$changed" << 'PY'
import importlib.util, sys
top, lcov, known = sys.argv[1], sys.argv[2], {l for l in sys.argv[3].split("\n") if l}
spec = importlib.util.spec_from_file_location("coverage_zero", top + "/tools/coverage_zero.py")
cz = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cz)
changed = {l for l in sys.argv[4].split("\n") if l}
zero = cz.zero_files(lcov, top)
for f in sorted(changed):
    if f in zero and f not in known:
        print(f"NEW\t{f}")
    elif f not in zero and f in known:
        print(f"GONE\t{f}")
PY
    ) || { echo "check_coverage_zero: no verdict — the LCOV judgement failed to run" >&2; exit 2; }
    while IFS=$'\t' read -r kind f; do
        case "$kind" in
            NEW) fail "$f" "at 0% in $lcov and not listed" "test it, or (audited) add it to $KNOWN" ;;
            GONE) fail "$f" "no longer at 0% in $lcov but still listed" "remove the line from $KNOWN" ;;
        esac
    done <<< "$out"
    mode="exact, from $lcov"
else
    ack_in=${LOGICKERNEL_COVZERO_ACK:-}
    ack=" ${ack_in//,/ } "
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        if in_list "$f" "$known"; then
            # a line this push ADDS is a deliberate, audited listing; only a file already declared 0% at the base counts
            in_list "$f" "$known_base" || continue
            case "$ack" in
                *" $f "*) ;;
                *) fail "$f" "listed as 0% and this push changes it; if the tests now run it CI says 'no longer at 0%'" "remove it from $KNOWN; if it is still 0% (structural) push with LOGICKERNEL_COVZERO_ACK=$f" ;;
            esac
        elif [ "$f" != "$root_file" ]; then
            bn=$(basename "$f")
            re=$(printf '%s' "$bn" | sed 's/[][\.*^$+?(){}|]/\\&/g')
            g grep -q -E "include\(\"([^\"]*/)?$re\"\)" "$rev" -- src || \
                fail "$f" "no include(\"...$bn\") loads it, so CI counts it at 0%" "include it, or (audited) add it to $KNOWN"
        fi
    done <<< "$changed"
    mode="static proxy — CI measures real coverage; --lcov gives its verdict"
fi

nchanged=$(printf '%s\n' "$changed" | sed '/^$/d' | wc -l)
if [ ${#fails[@]} -eq 0 ]; then
    echo "check_coverage_zero: OK — $nchanged changed src/ file(s) checked ($mode)"
    exit 0
fi
max=7
for ((i = 0; i < ${#fails[@]} && i < max; i++)); do echo "${fails[$i]}" >&2; done
[ ${#fails[@]} -gt $max ] && echo "check_coverage_zero: ... and $((${#fails[@]} - max)) more" >&2
echo "check_coverage_zero: ${#fails[@]} refusal(s) ($mode); CI's ratchet is tools/coverage_zero.py" >&2
exit 1
