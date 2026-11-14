#!/usr/bin/env bash
# ORIGINAL: the cases of tools/pre_ci.sh — no swipl-devel counterpart (audit D-0677 item 1).
# A FAKE workflow (PRE_CI_WORKFLOW) in a temp dir lists steps in the compile job's shape; pre_ci.sh must derive its list
# from it (both sides non-empty: the fake's steps are run, steps of ANOTHER job of the file are not), print one line per
# step with the exit status and, for a failed one, the first failing line, and exit non-zero iff a step failed. A row
# reads the REAL workflow and requires >= 8 step lines found (--list: nothing is run, so no recursion into this test).
# The rows are mutation-proved at verdict level: a hand-broken copy of pre_ci.sh must be caught. Exit 0 only if all pass.
set -uo pipefail
REAL="$(cd "$(dirname "$0")/.." && pwd)"
PRE="$REAL/tools/pre_ci.sh"
W="$(mktemp -d "${TMPDIR:-/tmp}/tpre.XXXXXX")"
trap 'rm -rf "$W" "$REAL/tools/.pre_ci_probe.sh"' EXIT
pass=0 fail=0
ok() { pass=$((pass + 1)); echo "  ok   $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL $1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       /'; }

cat > "$W/wf.yml" <<'EOW'
name: fake
jobs:
  compile:
    steps:
      - name: first
        run: tools/ci_compile_run.sh good_step echo hello
      - name: second
        run: |
          tools/ci_compile_run.sh bad_step bash -c 'printf "Test Failed at t.jl:3\n  Expression: p == q\n"; exit 1'
          if [ -f tools/no_such_file.sh ]; then tools/ci_compile_run.sh guarded_step tools/no_such_file.sh; fi
      - name: loop
        run: |
          export FAKE_TOKEN=tok
          for f in a/one.jl b/two.jl; do
              tools/ci_compile_run.sh --needs precompile "$(basename "$f" .jl)" bash -c 'echo "$FAKE_TOKEN $0"' "$f"
          done
  static:
    steps:
      - run: tools/ci_compile_run.sh other_job echo never
EOW
export PRE_CI_WORKFLOW="$W/wf.yml" PRE_CI_LOGS="$W/logs"
out="$(bash "$PRE" 2>&1)"; rc=$?
{ [ "$rc" = 1 ] \
    && printf '%s\n' "$out" | grep -qF "pre_ci: good_step exit 0" \
    && printf '%s\n' "$out" | grep -qF "pre_ci: bad_step exit 1  Test Failed at t.jl:3" \
    && printf '%s\n' "$out" | grep -qF "pre_ci: two exit 0" \
    && printf '%s\n' "$out" | grep -qF "pre_ci: guarded_step not run" \
    && ! printf '%s\n' "$out" | grep -qF "other_job"; } && ok "both steps listed with their status, the failing line of the failed one, a failure is exit 1, another job's step is not run" || bad "fake workflow (rc $rc)" "$out"
# the verbatim step line: the loop's export and file reached the command; the step's own output is in its log
{ grep -qF "tok a/one.jl" "$W/logs/one.log" && grep -qF "tok b/two.jl" "$W/logs/two.log"; } && ok "the loop is expanded per file, the block's export applies, the wrapper's log is kept" || bad "loop expansion"
# an all-passing workflow: exit 0
sed -e '/bad_step/d' "$W/wf.yml" > "$W/wf_ok.yml"
out="$(PRE_CI_WORKFLOW="$W/wf_ok.yml" bash "$PRE" 2>&1)"; rc=$?
{ [ "$rc" = 0 ] && printf '%s\n' "$out" | grep -qF "pre_ci: good_step exit 0"; } && ok "no failing step: exit 0, the passing step listed" || bad "all-pass (rc $rc)" "$out"
# --only runs one step, an unknown one is exit 2
out="$(bash "$PRE" --only good_step 2>&1)"; rc=$?
{ [ "$rc" = 0 ] && printf '%s\n' "$out" | grep -qF "pre_ci: good_step exit 0" && ! printf '%s\n' "$out" | grep -qF "bad_step"; } && ok "--only runs that step alone" || bad "--only (rc $rc)" "$out"
out="$(bash "$PRE" --only bad_step 2>&1)"; rc=$?
[ "$rc" = 1 ] && printf '%s\n' "$out" | grep -qF "pre_ci: bad_step exit 1" && ok "--only of the failing step: exit 1" || bad "--only bad_step (rc $rc)" "$out"
bash "$PRE" --only no_such_step > /dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && ok "--only with an unknown step is exit 2" || bad "--only unknown (rc $rc)"
# the list is DERIVED from the workflow: both sides non-empty (the fake's names, and not the real workflow's)
lst="$(bash "$PRE" --list 2>&1)"
{ printf '%s\n' "$lst" | grep -qx good_step && ! printf '%s\n' "$lst" | grep -qx tools_modes; } && ok "--list shows the fake workflow's steps, not the real one's" || bad "--list derived" "$lst"
# the REAL workflow: every step line found
unset PRE_CI_WORKFLOW
lst="$(bash "$PRE" --list 2>&1)"; n="$(printf '%s\n' "$lst" | grep -c .)"
{ [ "$n" -ge 8 ] && for s in fmt port_check bool_atoms where_return tools_modes test_attvar_words; do printf '%s\n' "$lst" | grep -qx "$s" || exit 1; done; } && ok "the real workflow: $n step lines found (>= 8), the named cheap steps among them" || bad "real workflow list ($n)" "$lst"
# MUTATION PROOF at verdict level
pre_rows() { # SCRIPT — number of the rows that do not hold for the pre_ci.sh copy SCRIPT (0 for the real one)
    local s="$1" o r n=0
    cp "$s" "$REAL/tools/.pre_ci_probe.sh"
    o="$(PRE_CI_WORKFLOW="$W/wf.yml" PRE_CI_LOGS="$W/mlogs" bash "$REAL/tools/.pre_ci_probe.sh" 2>&1)"; r=$?
    [ "$r" = 1 ] || n=$((n + 1))
    printf '%s\n' "$o" | grep -qF "pre_ci: good_step exit 0" || n=$((n + 1))
    printf '%s\n' "$o" | grep -qF "pre_ci: bad_step exit 1  Test Failed at t.jl:3" || n=$((n + 1))
    printf '%s\n' "$o" | grep -qF "pre_ci: two exit 0" || n=$((n + 1))
    ! printf '%s\n' "$o" | grep -qF "other_job" || n=$((n + 1))
    PRE_CI_WORKFLOW="$W/wf_ok.yml" bash "$REAL/tools/.pre_ci_probe.sh" > /dev/null 2>&1 || n=$((n + 1))
    PRE_CI_WORKFLOW="$W/wf.yml" bash "$REAL/tools/.pre_ci_probe.sh" --only good_step > /dev/null 2>&1 || n=$((n + 1))
    rm -f "$REAL/tools/.pre_ci_probe.sh"
    echo "$n"
}
pre_mutant() {
    local label="$1" old="$2" new="$3" cnt
    cp "$PRE" "$W/broken_pre.sh"
    python3 - "$W/broken_pre.sh" "$old" "$new" << 'PYEOF'
import sys
p, old, new = sys.argv[1:4]
s = open(p).read()
assert s.count(old) == 1, "mutant text matches %d times: %r" % (s.count(old), old)
open(p, "w").write(s.replace(old, new))
PYEOF
    [ $? = 0 ] || { bad "mutant $label: could not be built"; return; }
    cnt="$(pre_rows "$W/broken_pre.sh")"
    [ "$cnt" != 0 ] && ok "mutant caught: $label ($cnt row(s) fail)" || bad "mutant SURVIVED: $label"
}
cnt="$(pre_rows "$PRE")"
[ "$cnt" = 0 ] && ok "mutation baseline: the real script holds every verdict row" || bad "baseline: $cnt row(s) fail for the real script"
pre_mutant "exit status always 0" '    echo "pre_ci: $name exit $rc  $first"
            status=1' '    echo "pre_ci: $name exit $rc  $first"
            status=0'
pre_mutant "no first failing line" 'echo "pre_ci: $name exit $rc  $first"' 'echo "pre_ci: $name exit $rc"'
pre_mutant "stops at the first failure" 'status=1
            ;;' 'status=1
            break
            ;;'
pre_mutant "reads every job, not the compile job" 'if re.match(r"^  compile:\s*$", ln):' 'if False:'
pre_mutant "loop not expanded" 'if "$(basename" in m.group(1) and loop:' 'if False:'
pre_mutant "--only ignored" '[ -z "$only" ] || [ "$name" = "$only" ] || continue' ':'

echo "test_pre_ci: $pass passed, $fail failed"
[ "$fail" = 0 ]
