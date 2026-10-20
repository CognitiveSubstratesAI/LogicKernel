#!/usr/bin/env bash
# ORIGINAL: the whole suite as ONE mutation target (2026-10-20) — no swipl-devel counterpart.
# tools/mutate_suite.sh — test/runtests.jl on the reference term type, for a mutant list's TARGETS
# (`sh:tools/mutate_suite.sh`: a target holds no blank). A mutant it catches is caught by SOME test
# file, and the driver keeps the first failing test line, which names the file; one it does not catch
# is caught by none. In CI, .github/workflows/mutation.yml checks swipl-devel out at the pin for it
# (test/test_vendored_plunit.jl needs it).
# SLICED (D-0059, 2026-10-20; test/ci_slices.jl): the slices Evidence uses — the reference type's file
# groups (MUTATE_SUITE_GROUPS, 2) and the static analysis's shards (MUTATE_SUITE_SA, 2) — as parallel
# processes, MUTATE_SUITE_PROCS (3) at a time: one mutant's job on a 4-core runner, instead of one
# process for the whole suite (~20 min a mutant). Fanning a mutant out over RUNNERS instead would
# multiply a battery's jobs by the slice count, and a battery is already one job per mutant.
# THE EXIT: 1 when a slice exited 1 (a failed test: tools/mutate_drive.py's `judge` reads the
# output, every slice's, in slice order), else the first other non-zero exit, else 0 — and 0 only
# when EVERY slice ran (a slice with no exit file is a failure, 2).
set -u
groups="${MUTATE_SUITE_GROUPS:-2}" shards="${MUTATE_SUITE_SA:-2}" procs="${MUTATE_SUITE_PROCS:-3}"
out="$(mktemp -d "${TMPDIR:-/tmp}/mutate_suite_XXXXXX")"
trap 'rm -rf "$out"' EXIT
slices=()
for k in $(seq "$groups"); do slices+=("LOGICKERNEL_FILE_GROUP=$k/$groups"); done
for k in $(seq "$shards"); do slices+=("LOGICKERNEL_SA_SHARD=$k/$shards"); done
run_slice() {   # $1: index, $2: VAR=k/n
    env LOGICKERNEL_TERM_ONLY=reference "$2" julia --project=. --startup-file=no test/runtests.jl \
        > "$out/$1.log" 2>&1 < /dev/null
    echo $? > "$out/$1.rc"
}
running=0
for i in "${!slices[@]}"; do
    run_slice "$i" "${slices[$i]}" &
    running=$((running + 1))
    if [ "$running" -ge "$procs" ]; then wait -n; running=$((running - 1)); fi
done
wait
rc=0 other=0
for i in "${!slices[@]}"; do
    echo "=== slice ${slices[$i]}: exit $(cat "$out/$i.rc" 2> /dev/null || echo none)"
    cat "$out/$i.log" 2> /dev/null
    r="$(cat "$out/$i.rc" 2> /dev/null || echo 2)"
    [ "$r" = 1 ] && rc=1
    [ "$r" != 0 ] && [ "$r" != 1 ] && [ "$other" = 0 ] && other="$r"
done
[ "$rc" = 1 ] && exit 1
exit "$other"
