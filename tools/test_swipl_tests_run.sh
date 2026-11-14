#!/usr/bin/env bash
# ORIGINAL: no swipl-devel counterpart. Tests tools/swipl_tests_run.py (R2 acceptance item (c)) over a FAKE test set (a throwaway
# git repo standing in for swipl-devel at its pin) and a FAKE kernel command (KERNEL_CMD): no Julia, no kernel, no daemon.
#
#   tools/test_swipl_tests_run.sh        # exit 0 = every row holds AND every mutant of the classifier is caught
#
# Part 1 runs the rows against the real driver: each class is reachable (PASS, FAIL(n tests), ERROR(load), ERROR(run),
# TIMEOUT, NOT-RUNNABLE by three routes), each owner route (procedure, flag, refusal message, static list) answers, the
# summary line counts, a second run does not run a finished file again, --redo does. Part 2 is MUTATION-STYLE: the same rows
# run against copies of the driver with one decision edited (the FAIL threshold, the TIMEOUT class, the procedure owner
# lookup, the no-tests rule, the resume check, the pin check); every copy MUST make some row fail, or the rows could not tell
# a broken classifier from the real one (a guard that cannot fail, CLAUDE.md Health Gate).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REAL="$ROOT/tools/swipl_tests_run.py"
mkdir -p "$ROOT/.warm"
T="$(mktemp -d "$ROOT/.warm/test_swipl_tests_run.XXXXXX")"
trap 'rm -rf "$T"' EXIT

NAMES="pass fail loaderr hang nr noverdict script_ok script_bad none flag refusal static"

# --- the fake swipl-devel at a fake pin: plumbing only (a snapshot object, no hooks, no config)
FX="$T/fixture"
mkdir -p "$FX/tests/core_lang" "$FX/tests/thread"
for n in $NAMES; do
    printf '%% fake test %s\n' "$n" > "$FX/tests/core_lang/test_$n.pl"
done
printf '%% fake\n' > "$FX/tests/thread/test_t.pl"
git -C "$FX" init -q
git -C "$FX" add tests
TREE="$(git -C "$FX" write-tree)"
PIN="$(printf 'fake pin\n' | GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid git -C "$FX" commit-tree "$TREE")"
git -C "$FX" update-ref refs/heads/fake "$PIN"

# --- the fake files of the runner: list (one file that is not in the pin), owners, static list
LIST="$T/list.tsv"
{
    printf 'file\tmissing_c_predicates\tthe_predicates\tuse_module\n'
    for n in $NAMES; do
        printf 'tests/core_lang/test_%s.pl\t0\t\t-\n' "$n"
    done
    printf 'tests/thread/test_t.pl\t0\t\t-\n'
    printf 'tests/core_lang/test_gone.pl\t0\t\t-\n'
} > "$LIST"
NFILES=14
NPASS=3        # test_pass, test_script_ok, and test_t (the default verdict)
OWNERS="$T/owners.tsv"
{
    printf '# fake owners\n'
    printf 'pred:foo_bar/2\tOWN1\tnote\n'
    printf 'flag:foo_flag\tOWN2\tnote\n'
    printf 'refusal:f.jl::fn::the qlf read side is refused\tOWN3\tnote\n'
} > "$OWNERS"
NEEDS="$T/needs.tsv"
printf 'file\tunits\tuse_module\tc_called\tc_missing_in_kernel\tboot_called\ttop_c_missing\tc_files_with_missing\tboot_files_called\n' > "$NEEDS"
printf 'tests/core_lang/test_static.pl\t0\t-\t1\t1\t0\tfoo_bar/2\tx.c\ty.pl\n' >> "$NEEDS"

# --- the fake kernel: one canned verdict per file name; every call is counted
FK="$T/fakekernel.sh"
cat > "$FK" <<'FAKE'
#!/usr/bin/env bash
f="$1"
echo x >> "$FAKE_COUNT"
case "$(basename "$f")" in
    test_pass.pl) echo "LK-RESULT summary total=3 passed=3 failed=0 timeout=0 blocked=0 fixme=0" ;;
    test_fail.pl) printf 'noise without a newline'; echo "LK-RESULT summary total=4 passed=2 failed=2 timeout=0 blocked=0 fixme=0" ;;
    test_loaderr.pl) echo "LK-RESULT load-error error(existence_error(procedure,foo_bar/2),foo_bar/2)" ;;
    test_hang.pl) sleep 30 ;;
    test_nr.pl) echo "LK-RESULT not-runnable needs threads" ;;
    test_noverdict.pl) echo "ERROR: something went wrong in the kernel" >&2; exit 3 ;;
    test_script_ok.pl) echo "LK-RESULT script passed" ;;
    test_script_bad.pl) echo "LK-RESULT script failed" ;;
    test_none.pl) echo "LK-RESULT no-tests" ;;
    test_flag.pl) echo "LK-RESULT run-error error(domain_error(flag,foo_flag),_)" ;;
    test_refusal.pl) echo "LK-RESULT load-error error(refused,'f.jl: the qlf read side is refused')" ;;
    test_static.pl) echo "ERROR: boom" >&2; exit 1 ;;
    *) echo "LK-RESULT summary total=1 passed=1 failed=0 timeout=0 blocked=0 fixme=0" ;;
esac
FAKE
chmod +x "$FK"

FAILS=0
ROWS=0
# check DESC EXPECTED ACTUAL
check() {
    ROWS=$((ROWS + 1))
    if [ "$2" != "$3" ]; then
        FAILS=$((FAILS + 1))
        [ -n "${VERBOSE:-}" ] && printf '  row %d FAILED: %s: expected [%s] got [%s]\n' "$ROWS" "$1" "$2" "$3" >&2
    fi
    return 0
}
# col WORK NAME N: column N of the row of tests/core_lang/test_NAME.pl in WORK's TSV
col() { awk -F'\t' -v f="tests/core_lang/test_$2.pl" -v n="$3" '$1 == f { print $n }' "$1/results.tsv"; }

# run_rows DRIVER: every row, against DRIVER; the number of failed rows is $FAILS afterwards
run_rows() {
    local driver="$1" W="$T/work.$RANDOM" count out
    FAILS=0
    ROWS=0
    mkdir -p "$W"
    count="$W/count"
    : > "$count"
    export FAKE_COUNT="$count" KERNEL_CMD="$FK" LK_TESTS_PIN="$PIN" LOGICKERNEL_UPSTREAM_SWIPL_DEVEL="$FX"
    local args=(--list "$LIST" --work "$W" --owners "$OWNERS" --needs "$NEEDS" --timeout 2)
    out="$(python3 -I "$driver" "${args[@]}" 2> /dev/null)"
    check "pass" "PASS" "$(col "$W" pass 2)"
    check "pass count" "3" "$(col "$W" pass 3)"
    check "pass has no owner" "" "$(col "$W" pass 7)"
    check "fail" "FAIL(2 tests)" "$(col "$W" fail 2)"
    check "load error" "ERROR(load)" "$(col "$W" loaderr 2)"
    check "owner by procedure" "OWN1 (pred:foo_bar/2)" "$(col "$W" loaderr 7)"
    check "timeout" "TIMEOUT" "$(col "$W" hang 2)"
    check "timeout is prompt" "yes" "$(awk -F'\t' '$1 ~ /test_hang/ { print ($5 < 20) ? "yes" : "no" }' "$W/results.tsv")"
    check "not runnable by the kernel" "NOT-RUNNABLE(needs threads)" "$(col "$W" nr 2)"
    check "not in the pin" "NOT-RUNNABLE(not in pin)" "$(col "$W" gone 2)"
    check "no verdict" "ERROR(load)" "$(col "$W" noverdict 2)"
    check "no verdict says so" "no verdict from the kernel, exit 3" "$(col "$W" noverdict 6 | cut -c1-34)"
    check "script passed" "PASS" "$(col "$W" script_ok 2)"
    check "script failed" "FAIL(1 tests)" "$(col "$W" script_bad 2)"
    check "no tests" "NOT-RUNNABLE(no tests)" "$(col "$W" none 2)"
    check "run error and owner by flag" "ERROR(run) OWN2 (flag:foo_flag)" "$(col "$W" flag 2) $(col "$W" flag 7)"
    check "owner by refusal message" "OWN3 (refusal)" "$(col "$W" refusal 7)"
    check "owner by the static list" "static:OWN1 (pred:foo_bar/2)" "$(col "$W" static 7)"
    check "summary line" "swipl-devel test files through the kernel: $NPASS of $NFILES pass" "$(printf '%s\n' "$out" | grep 'of .* pass')"
    # resume: a second run runs nothing; --only --redo runs that one file again
    local n1 n2 n3
    n1="$(wc -l < "$count")"
    python3 -I "$driver" "${args[@]}" > /dev/null 2>&1
    n2="$(wc -l < "$count")"
    check "resume runs nothing" "$n1" "$n2"
    python3 -I "$driver" "${args[@]}" --only test_pass --redo > /dev/null 2>&1
    n3="$(wc -l < "$count")"
    check "redo runs the one file" "$((n2 + 1))" "$n3"
    # --summary reads the TSV and runs nothing
    check "summary mode" "swipl-devel test files through the kernel: $NPASS of $NFILES pass" \
        "$(python3 -I "$driver" "${args[@]}" --summary | head -1)"
    check "summary mode runs nothing" "$n3" "$(wc -l < "$count")"
    rm -rf "$W"
    return 0
}

# --- part 1: the real driver
run_rows "$REAL"
printf 'rows on the real driver: %d, failed %d\n' "$ROWS" "$FAILS"
if [ "$FAILS" -ne 0 ]; then
    VERBOSE=1 run_rows "$REAL"
    exit 1
fi

# --- part 2: mutants of the driver; each must make a row fail
# mutant NAME SED-EXPRESSION: a copy of the driver with the first line the expression matches edited; the edit must change it
BAD=0
mutant() {
    local name="$1" expr="$2" m="$T/mutant_$1.py"
    sed "$expr" "$REAL" > "$m"
    if cmp -s "$REAL" "$m"; then
        printf 'mutant %s: the edit matched nothing\n' "$name"
        BAD=$((BAD + 1))
        return 0
    fi
    run_rows "$m"
    if [ "$FAILS" -gt 0 ]; then
        printf 'mutant %s: caught (%d rows failed)\n' "$name" "$FAILS"
    else
        printf 'mutant %s: SURVIVED\n' "$name"
        BAD=$((BAD + 1))
    fi
    return 0
}
mutant fail_threshold '0,/    if failed > 0:/s//    if failed > 99:/'
mutant timeout_class '0,/return "TIMEOUT", 0, 0/s//return "ERROR(run)", 0, 0/'
mutant procedure_owner '0,/        if key in owners:/s//        if False:/'
mutant no_tests_rule '0,/    if tests == 0:/s//    if tests == -1:/'
mutant resume_check '0,/if name in rows and not a.redo:/s//if False:/'
mutant not_in_pin '0,/if not os.path.isfile(path):/s//if False:/'
if [ "$BAD" -ne 0 ]; then
    printf 'FAILED: %d mutant(s) not caught\n' "$BAD"
    exit 1
fi
printf 'tools/test_swipl_tests_run.sh: OK\n'
