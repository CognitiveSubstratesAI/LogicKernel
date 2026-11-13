#!/usr/bin/env bash
# ORIGINAL: the cases of tools/ci_compile_run.sh and tools/ci_compile_summary.py — no swipl-devel counterpart.
# FIXTURE log directories in a temp dir with the shapes the compile check's steps really print (Julia's `Test Failed at`,
# `Error During Test at`, an `ERROR: LoadError` with a stack frame, port_check's two-space violations, the formatter's
# diff, check_bool_atoms' hit line). Each case is judged by the summary's exit code AND by a row it must contain (file,
# line, message); both sides non-empty: an all-green directory is exit 0 with "No failure", a red one exit 1 with its
# rows, a directory with no .rc is refused (exit 2), a failed step nothing explains still gets one row, a skipped step is
# not a failure. The wrapper: a failing command is rc recorded and exit 0, a needed step that failed skips the next.
# Exit 0 only if every case passes.
set -uo pipefail
REAL="$(cd "$(dirname "$0")/.." && pwd)"
SUM="$REAL/tools/ci_compile_summary.py"
RUN="$REAL/tools/ci_compile_run.sh"
W="$(mktemp -d "${TMPDIR:-/tmp}/ccs.XXXXXX")"
trap 'rm -rf "$W"' EXIT
pass=0 fail=0
ok() { pass=$((pass + 1)); echo "  ok   $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL $1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       /'; }
# sum CASE WANT_RC DIR ROW... — the summary of DIR: exit WANT_RC and every ROW (a fixed string) in its output
sum_() {
    local label="$1" want="$2" dir="$3" out rc r good=1
    shift 3
    out="$(python3 -I "$SUM" "$dir" 2>&1)"
    rc=$?
    [ "$rc" = "$want" ] || good=0
    for r in "$@"; do printf '%s' "$out" | grep -qF -- "$r" || good=0; done
    if [ "$good" = 1 ]; then ok "$label (exit $rc)"; else bad "$label: exit $rc, want $want" "$out"; fi
}

# a directory of green steps
mkdir -p "$W/green"
for s in precompile fmt port_check; do echo 0 > "$W/green/$s.rc"; : > "$W/green/$s.log"; done
sum_ "every step passed: exit 0, no failure" 0 "$W/green" "No failure" "| fmt | passed |"

# a red directory: one step of each shape
mkdir -p "$W/red"
echo 1 > "$W/red/precompile.rc"
printf 'Precompiling LogicKernel\nERROR: LoadError: UndefVarError: `foo` not defined in `LogicKernel`\nStacktrace:\n  [1] top-level scope\n    @ /home/runner/work/lk/lk/src/pl-x.jl:42\n' > "$W/red/precompile.log"
echo 1 > "$W/red/fmt.rc"
printf 'diff --git a/src/pl-y.jl b/src/pl-y.jl\n--- a/src/pl-y.jl\n+++ b/src/pl-y.jl\n' > "$W/red/fmt.log"
echo 1 > "$W/red/port_check.rc"
printf 'port_check: 120 file(s), upstream checked for: NONE\n  src/pl-z.jl:7: PORT marker names no function\n  docs/port_inventory.md: table differs\n' > "$W/red/port_check.log"
echo 1 > "$W/red/bool_atoms.rc"
printf 'check_bool_atoms: test/core_lang/test_q.jl:9: @test lk_sym(T, :true) isa T\ncheck_bool_atoms: 1 hit(s)\n' > "$W/red/bool_atoms.log"
echo 1 > "$W/red/test_mark_bar.rc"
printf 'Test Failed at /home/runner/work/lk/lk/test/core_lang/test_mark_bar.jl:55\n  Expression: x == 2\n   Evaluated: 1 == 2\nError During Test at /home/runner/work/lk/lk/test/core_lang/test_mark_bar.jl:70\n  Got exception outside of a @test\n  BoundsError: attempt to access 0-element Vector\n' > "$W/red/test_mark_bar.log"
echo skipped > "$W/red/test_local_stack.rc"
: > "$W/red/test_local_stack.log"
sum_ "red: the load error row names the src frame and the message" 1 "$W/red" "| precompile | src/pl-x.jl | 42 | ERROR: LoadError: UndefVarError"
sum_ "red: the formatter's file" 1 "$W/red" "| fmt | src/pl-y.jl | - | not Blue-formatted"
sum_ "red: port_check's two shapes" 1 "$W/red" "| port_check | src/pl-z.jl | 7 | PORT marker names no function" "| port_check | docs/port_inventory.md | - | table differs"
sum_ "red: the Bool-as-atom hit" 1 "$W/red" "| bool_atoms | test/core_lang/test_q.jl | 9 | Bool is no atom"
sum_ "red: Test Failed and Error During Test rows" 1 "$W/red" "| test_mark_bar | test/core_lang/test_mark_bar.jl | 55 | Test Failed Expression: x == 2" "| test_mark_bar | test/core_lang/test_mark_bar.jl | 70 | Error During Test: BoundsError"
sum_ "red: a skipped step is not a failure row" 1 "$W/red" "| test_local_stack | skipped (a step it needs failed) |"
if python3 -I "$SUM" "$W/red" | grep -E '^\| test_local_stack \|[^|]*\|[^|]*\|' > /dev/null; then bad "a skipped step got a failure row"; else ok "a skipped step has no failure row"; fi

# a failed step nothing explains: one row with the last line
mkdir -p "$W/odd"; echo 3 > "$W/odd/x.rc"; printf 'something\nthe last line\n\n' > "$W/odd/x.log"
sum_ "an unexplained failure still gets a row (its last line)" 1 "$W/odd" "| x | - | - | the last line |"
mkdir -p "$W/nolog"; echo 3 > "$W/nolog/y.rc"
sum_ "a failed step without a log still gets a row" 1 "$W/nolog" "| y | - | - |"
mkdir -p "$W/none"
sum_ "a directory with no .rc is refused" 2 "$W/none"
sum_ "no directory is refused" 2 "$W/nowhere"

# the wrapper
export CI_COMPILE_LOGS="$W/wrap"
bash "$RUN" okstep echo hello > /dev/null; rc=$?
{ [ "$rc" = 0 ] && [ "$(cat "$W/wrap/okstep.rc")" = 0 ] && grep -q hello "$W/wrap/okstep.log"; } && ok "wrapper: a passing command, rc 0 recorded, output kept" || bad "wrapper: a passing command"
bash "$RUN" failstep bash -c 'echo boom; exit 7' > /dev/null; rc=$?
{ [ "$rc" = 0 ] && [ "$(cat "$W/wrap/failstep.rc")" = 7 ] && grep -q boom "$W/wrap/failstep.log"; } && ok "wrapper: a failing command exits 0 itself, records rc 7" || bad "wrapper: a failing command"
bash "$RUN" --needs failstep after echo never > /dev/null; rc=$?
{ [ "$rc" = 0 ] && [ "$(cat "$W/wrap/after.rc")" = skipped ] && ! grep -q never "$W/wrap/after.log"; } && ok "wrapper: a step that needs a failed one is skipped, not run" || bad "wrapper: --needs a failed step"
bash "$RUN" --needs okstep after2 echo ran > /dev/null; rc=$?
{ [ "$rc" = 0 ] && [ "$(cat "$W/wrap/after2.rc")" = 0 ] && grep -q ran "$W/wrap/after2.log"; } && ok "wrapper: a step that needs a passed one runs" || bad "wrapper: --needs a passed step"
bash "$RUN" nocmd /no/such/command > /dev/null 2>&1
[ "$(cat "$W/wrap/nocmd.rc")" = 127 ] && ok "wrapper: a command that cannot start is rc 127 of its step" || bad "wrapper: unstartable command"
bash "$RUN" onlyname > /dev/null 2>&1; rc=$?
[ "$rc" = 64 ] && ok "wrapper: no command is a usage error (64)" || bad "wrapper: usage (rc $rc)"
sum_ "the summary reads what the wrapper wrote: failstep FAILED, after skipped" 1 "$W/wrap" "| failstep | FAILED (exit 7) |" "| after | skipped (a step it needs failed) |"

echo "test_ci_compile_summary: $pass passed, $fail failed"
[ "$fail" = 0 ]
