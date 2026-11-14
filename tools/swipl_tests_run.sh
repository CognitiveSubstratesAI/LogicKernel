#!/usr/bin/env bash
# ORIGINAL: no swipl-devel counterpart. R2 acceptance item (c) (audit D-0624/D-0625): how many of the swipl-devel test
# files run and pass through the kernel. The driver is tools/swipl_tests_run.py (its header says what it does and why);
# this wrapper only caps the work and starts it.
#
#   tools/swipl_tests_run.sh [--list TSV] [--timeout S] [--nice N] [--redo] [--only RE] [--limit N] [--summary]
#   KERNEL_CMD='...'   the command that runs ONE test file (the file's path is appended); default: the pinned Julia on
#                      tools/swipl_tests_kernel.jl
#   LK_TESTS_TIMEOUT   wall limit per file in seconds (120)        LK_TESTS_NICE   nice level (0)
#   LK_TESTS_WORK      work directory (<repo>/.warm/swipl_tests)   LK_TESTS_LIST   the file list
#   LK_TESTS_NO_SCOPE=1 skips the capped scope below (tools/test_swipl_tests_run.sh uses it, its kernel being a fake)
#
# One file at a time, one kernel process at a time: a heavy job (D-0114: it never starts a daemon). The whole run is in ONE
# capped systemd scope (6 GB, no swap, 512 tasks), as tools/run_tests.sh does: a runaway is one killed scope.
set -uo pipefail
if [ -z "${LK_TESTS_CAPPED:-}" ] && [ -z "${LK_TESTS_NO_SCOPE:-}" ] && command -v systemd-run > /dev/null 2>&1 &&
    systemd-run --user --scope true > /dev/null 2>&1; then
    exec env LK_TESTS_CAPPED=1 systemd-run --user --scope --quiet \
        -p MemoryMax="${LK_TESTS_MEMMAX:-6G}" -p MemorySwapMax=0 -p TasksMax="${LOGICKERNEL_TASKS_MAX:-512}" "$0" "$@"
fi
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec python3 -I "$ROOT/tools/swipl_tests_run.py" "$@"
