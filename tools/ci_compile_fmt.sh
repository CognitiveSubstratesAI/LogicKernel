#!/usr/bin/env bash
# ORIGINAL: no swipl-devel counterpart — the formatter step of .github/workflows/ci-compile.yml (audit D-0636 item 2):
# the Format job of CI.yml (JuliaFormatter, the SAME pin) over the .jl files this branch CHANGES against origin/main,
# not the whole tree — a compile check that costs minutes, not the formatter's full pass. The verdict is CI's: the
# formatter rewrites the files, and `git diff` must then be empty. Prints `diff --git a/<file>` lines for the summary.
#
#   tools/ci_compile_fmt.sh        (cwd: the checkout; needs `git fetch` depth 0 so origin/main exists)
#
# Exit status: 0 the changed files are Blue-formatted (or none changed); 1 not formatted, or no origin/main to compare
# with (fails closed: an unreadable base never passes).
set -u
cd "$(dirname "$0")/.." || exit 1
FORMATTER_VERSION="2.14.0"      # 🔴 CI.yml's Format job pins the same: change both or neither
git rev-parse --verify --quiet origin/main > /dev/null || {
    echo "ci_compile_fmt: no origin/main to compare with (the checkout needs fetch-depth 0)"
    exit 1
}
files="$(git diff --name-only --diff-filter=ACMR origin/main...HEAD -- '*.jl')"
if [ -z "$files" ]; then
    echo "ci_compile_fmt: no .jl file changed against origin/main: nothing to check"
    exit 0
fi
echo "ci_compile_fmt: $(printf '%s\n' "$files" | wc -l) changed .jl file(s)"
julia -e "using Pkg; Pkg.add(PackageSpec(name=\"JuliaFormatter\", version=\"$FORMATTER_VERSION\"))" || exit 1
julia -e 'using JuliaFormatter; println("JuliaFormatter ", pkgversion(JuliaFormatter))' || exit 1
mapfile -t arr <<< "$files"
julia -e 'using JuliaFormatter; format(ARGS)' "${arr[@]}" || exit 1
if ! git diff --quiet; then
    echo "::error::Formatting check failed — files below are not Blue-formatted:"
    git --no-pager diff --stat
    git --no-pager diff
    exit 1
fi
echo "All changed files Blue-formatted."
