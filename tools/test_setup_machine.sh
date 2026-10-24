#!/usr/bin/env bash
# ORIGINAL: the setup script's own tests (audit D-0130 item 2) — no swipl-devel counterpart.
# tools/test_setup_machine.sh — tools/setup_machine.sh's modes, judged by exit code (no installs): the real run on a
# clean machine is .github/workflows/setup.yml's, in a bare ubuntu:24.04 container.
#
#   tools/test_setup_machine.sh          # exit 0 only if every case passes
#
# What the script must never do: report a machine READY that lacks a component (--check exits 1 when one is missing),
# change anything under --plan, or take an unknown argument as a request to install.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
S="$ROOT/tools/setup_machine.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
pass=0 fail=0
check() {   # check NAME WANT_EXIT GOT_EXIT
    if [ "$2" = "$3" ]; then pass=$((pass + 1)); echo "  ok   $1"
    else fail=$((fail + 1)); echo "  FAIL $1: exit $3, want $2"; fi
}

"$S" --plan > "$T/plan" 2>&1;                          check "--plan exits 0" 0 $?
[ "$(grep -c '\[\(done\|missing\|n/a (no systemd)\)\]' "$T/plan")" = 6 ]
check "…and lists the six steps" 0 $?
grep -q 'plan only — nothing changed' "$T/plan";       check "…saying that it changed nothing" 0 $?

"$S" --no-such-flag > "$T/bad" 2>&1;                   check "an unknown argument is exit 2, not an install" 2 $?

# a machine with nothing: an empty HOME (no ~/.juliaup, no oracle prefix) and a PATH of the system tools WITHOUT julia,
# juliaup and swipl (a runner image may have one in /usr/bin: the first CI run of this file failed two cases that way) —
# so --check must say Julia is missing and exit 1
mkdir "$T/home" "$T/bin"
for f in /usr/bin/* /bin/*; do
    case "${f##*/}" in julia | juliaup | swipl) continue ;; esac
    ln -sf "$f" "$T/bin/${f##*/}" 2> /dev/null
done
HOME="$T/home" PATH="$T/bin" "$S" --check --no-oracle > "$T/empty" 2>&1
check "--check on a machine without Julia exits 1" 1 $?
grep -q 'Julia 1.13 (juliaup) *missing' "$T/empty";    check "…naming what is missing" 0 $?
grep -q 'the machine is ready' "$T/empty";             check "…and never saying the machine is ready" 1 $?
[ ! -e "$T/home/.juliaup" ] && [ -z "$(ls -A "$T/home")" ]
check "…and --check installs nothing" 0 $?

echo "tools/test_setup_machine.sh: $pass passed, $fail failed"
[ "$fail" = 0 ]
