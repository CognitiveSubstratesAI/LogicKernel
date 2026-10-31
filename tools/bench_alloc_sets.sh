#!/usr/bin/env bash
# ORIGINAL: no swipl-devel counterpart — the allocation-set comparison of two trees (audit D-0172 item 2,
# D-0187 item 1, D-0188 item 2; user's tooling rule: a recurring operation is a script).
# tools/bench_alloc_sets.sh <tree-A> <tree-B> <N> [bench.jl args after --alloc-only: --runs=K, CASE filters…]
#
# Alternates N FRESH julia processes per side (A, B, A, B, …), each `julia --project=. tools/bench.jl
# --alloc-only` run in that tree: no swipl, no quiet-machine gate, no tools/bench.sh (allocation counts do
# not depend on the load, so it runs beside other work). Prints, per case, the SET of per-process counts
# on each side next to each other, e.g. `{237x4, 239x1}` — a count is bimodal per instance (D-0172), so
# one run proves nothing and a delta counts only when the MODES shift (D-0172 item 2). The verdict column:
#   identical   same values, same multiplicities
#   same set    same distinct values, different multiplicities (not a shift)
#   mode same   the most frequent value(s) agree, the sets differ (read the sets)
#   MODE SHIFT  the modes differ — an allocation-set shift is a stop (D-0187 item 3)
# The per-process rows are kept in the output directory (BENCH_ALLOC_OUT, default a fresh mktemp dir under
# $TMPDIR or /tmp… printed first) as <side>_<i>.tsv, with each process's stderr in <side>_<i>.err.
#   BENCH_ALLOC_BENCH=<path to a bench.jl with --alloc-only>   run THAT file (cwd = the tree, --project=. the
#       tree) instead of the tree's own tools/bench.jl — for a base tree whose bench.jl predates the flag; the
#       file must run against both trees' APIs.
# Each process is capped (MemoryMax, TasksMax) as every long job here; processes run one at a time.
# Exit: 0 all processes ran; 2 usage/tree problem; 3 a process failed.
set -u
usage() { echo "usage: tools/bench_alloc_sets.sh <tree-A> <tree-B> <N> [--runs=K] [CASE…]" >&2; exit 2; }
[ "$#" -ge 3 ] || usage
TA="$1"; TB="$2"; N="$3"; shift 3
case "$N" in '' | *[!0-9]* | 0) echo "bench_alloc_sets: N must be a positive integer, got '$N'" >&2; exit 2 ;; esac
[ "$N" -ge 5 ] || echo "bench_alloc_sets: WARNING N=$N < 5: D-0172 asks >= 5 fresh processes per side" >&2
for t in "$TA" "$TB"; do
    [ -d "$t" ] && [ -f "$t/Project.toml" ] || { echo "bench_alloc_sets: not a LogicKernel tree: $t" >&2; exit 2; }
done
TA="$(cd "$TA" && pwd)"; TB="$(cd "$TB" && pwd)"
bench_for() { # tree -> the bench.jl to run there
    local f="${BENCH_ALLOC_BENCH:-$1/tools/bench.jl}"
    [ -f "$f" ] || { echo "bench_alloc_sets: no $f" >&2; return 2; }
    grep -q -- '--alloc-only' "$f" || {
        echo "bench_alloc_sets: $f has no --alloc-only; set BENCH_ALLOC_BENCH=<a bench.jl that has it>" >&2
        return 2
    }
    echo "$f"
}
BA="$(bench_for "$TA")" || exit 2
BB="$(bench_for "$TB")" || exit 2
OUT="${BENCH_ALLOC_OUT:-$(mktemp -d "${TMPDIR:-/tmp}/alloc_sets.XXXXXX")}"
mkdir -p "$OUT"
echo "bench_alloc_sets: A=$TA B=$TB N=$N; per-process rows in $OUT"

CAP=()
command -v systemd-run > /dev/null 2>&1 && systemd-run --user --scope true > /dev/null 2>&1 &&
    CAP=(systemd-run --user --scope -q -p MemoryMax=6G -p MemorySwapMax=0 -p TasksMax=512)

one() { # side tree benchfile i
    local rc
    (cd "$2" && "${CAP[@]}" julia --project=. "$3" --alloc-only "${@:5}") \
        > "$OUT/$1_$4.tsv" 2> "$OUT/$1_$4.err"
    rc=$?
    if [ "$rc" -ne 0 ] || ! grep -q '^ALLOC	' "$OUT/$1_$4.tsv"; then
        echo "bench_alloc_sets: side $1 process $4 FAILED (exit $rc, rows: $(grep -c '^ALLOC	' "$OUT/$1_$4.tsv")); see $OUT/$1_$4.err" >&2
        tail -5 "$OUT/$1_$4.err" >&2
        return 3
    fi
    echo "bench_alloc_sets: $1 $4/$N done" >&2
}
for i in $(seq 1 "$N"); do
    one A "$TA" "$BA" "$i" "$@" || exit 3
    one B "$TB" "$BB" "$i" "$@" || exit 3
done

# aggregate: side, case, the process's median count -> {value x processes} per side and the verdict
for s in A B; do
    for i in $(seq 1 "$N"); do
        awk -F'\t' -v s="$s" '$1 == "ALLOC" { print s "\t" $2 "\t" $3 }' "$OUT/${s}_$i.tsv"
    done
done | awk -F'\t' '
function fmt(v) { return (v == int(v)) ? sprintf("%d", v) : sprintf("%.3f", v) }
{
    s = $1; c = $2; v = $3 + 0
    if (!(c in seen)) { seen[c] = 1; order[++nc] = c }
    key = s SUBSEP c SUBSEP v
    if (!(key in cnt)) { vals[s, c] = vals[s, c] " " v }
    cnt[key]++
}
function sorted(s, c,    n, a, i, j, t) {
    n = split(vals[s, c], a, " ")
    for (i = 1; i <= n; i++) for (j = i + 1; j <= n; j++) if (a[j] + 0 < a[i] + 0) { t = a[i]; a[i] = a[j]; a[j] = t }
    SORTED_N = n
    for (i = 1; i <= n; i++) SV[i] = a[i]
}
function setstr(s, c,    i, r, mx) {   # {v x k, …}; MODES_<s> = the most frequent values
    sorted(s, c); r = ""; mx = 0
    for (i = 1; i <= SORTED_N; i++) { k = cnt[s SUBSEP c SUBSEP (SV[i] + 0)]; if (k > mx) mx = k }
    modes = ""
    for (i = 1; i <= SORTED_N; i++) {
        k = cnt[s SUBSEP c SUBSEP (SV[i] + 0)]
        r = r (i > 1 ? ", " : "") fmt(SV[i] + 0) "x" k
        if (k == mx) modes = modes (modes == "" ? "" : ",") fmt(SV[i] + 0)
    }
    LASTMODES = modes
    return "{" r "}"
}
END {
    printf("%-28s  %-34s  %-34s  %s\n", "case", "A", "B", "verdict")
    for (i = 1; i <= nc; i++) {
        c = order[i]
        a = setstr("A", c); ma = LASTMODES
        b = setstr("B", c); mb = LASTMODES
        if (a == b) v = "identical"
        else {
            sorted("A", c); da = ""; for (j = 1; j <= SORTED_N; j++) da = da " " fmt(SV[j] + 0)
            sorted("B", c); db = ""; for (j = 1; j <= SORTED_N; j++) db = db " " fmt(SV[j] + 0)
            if (da == db) v = "same set"
            else if (ma == mb) v = "mode same"
            else v = "MODE SHIFT"
        }
        if (v == "MODE SHIFT") nshift++
        printf("%-28s  %-34s  %-34s  %s\n", c, a, b, v)
    }
    printf("%d case(s), %d with a MODE SHIFT\n", nc, nshift + 0)
}'
exit "${PIPESTATUS[1]:-0}"
