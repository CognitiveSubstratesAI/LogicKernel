#!/usr/bin/env bash
# ORIGINAL: no swipl-devel counterpart — the step wrapper of .github/workflows/ci-compile.yml (audit D-0636 item 2).
#
#   tools/ci_compile_run.sh [--needs NAME] NAME COMMAND [ARG...]
#
# Runs COMMAND with its output shown AND kept in $CI_COMPILE_LOGS/NAME.log (default ${RUNNER_TEMP:-/tmp}/ci-compile),
# writes its exit code to NAME.rc, and EXITS 0 whatever the command did: the compile check wants every failure of the
# push in ONE run, so a step never stops the next; the job's last step (tools/ci_compile_summary.py) turns the .rc
# files into the table and the verdict. `--needs NAME2`: if step NAME2 did not pass, this step is not run and
# NAME.rc says `skipped` (a test file is meaningless when `using LogicKernel` itself failed). A command that cannot
# be started is a failure of its step (rc 127), not of the wrapper.
set -u
LOGS="${CI_COMPILE_LOGS:-${RUNNER_TEMP:-/tmp}/ci-compile}"
mkdir -p "$LOGS"
needs=""
if [ "${1:-}" = "--needs" ]; then
    needs="${2:-}"
    shift 2
fi
name="${1:-}"
[ -n "$name" ] && [ "$#" -ge 2 ] || { echo "usage: tools/ci_compile_run.sh [--needs NAME] NAME COMMAND [ARG...]" >&2; exit 64; }
case "$name" in *[!A-Za-z0-9._-]*) echo "ci_compile_run: bad step name: $name" >&2; exit 64 ;; esac
shift
if [ -n "$needs" ] && [ "$(cat "$LOGS/$needs.rc" 2> /dev/null)" != "0" ]; then
    echo "ci_compile_run: $name skipped: $needs did not pass"
    echo skipped > "$LOGS/$name.rc"
    : > "$LOGS/$name.log"
    exit 0
fi
"$@" > "$LOGS/$name.log" 2>&1
rc=$?
cat "$LOGS/$name.log"
echo "$rc" > "$LOGS/$name.rc"
echo "ci_compile_run: $name exit $rc"
exit 0
