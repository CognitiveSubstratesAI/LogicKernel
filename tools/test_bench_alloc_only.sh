#!/usr/bin/env bash
# ORIGINAL: the allocation-only bench's own tests (audit D-0188 item 2; user, 2026-10-03: every guard
# mutation-proved) — no swipl-devel counterpart. Style of tools/test_evidence.sh / test_oracle_cache.sh.
#
#   tools/test_bench_alloc_only.sh          # both parts; exit 0 only if every case passes
#   tools/test_bench_alloc_only.sh stub     # tools/bench_alloc_sets.sh against STUB julia processes (no julia, seconds)
#   tools/test_bench_alloc_only.sh real     # the real `tools/bench.jl --alloc-only` in a fresh julia (compiles; minutes cold)
#
# stub: the script alternates N fresh processes per side, displays a bimodal count as a SET ({237x4, 239x1}),
#       calls a mode shift a MODE SHIFT and a multiplicity-only difference "same set", refuses N=0, a tree
#       without the flag and a failing process.
# real: the flag REFUSES NOTHING — with another julia process alive, no BENCH_GATE_SAMPLE, no --ungated, and a
#       `swipl` on PATH that records any call and fails — and prints ALLOC rows (numeric, non-empty, one per
#       selected case), no timing columns, and writes no tools/bench_results file.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODE="${1:-all}"
W="$(mktemp -d "${TMPDIR:-/tmp}/balloc.XXXXXX")"
HELPER=""
trap '[ -n "$HELPER" ] && kill "$HELPER" 2>/dev/null; rm -rf "$W"' EXIT
pass=0 fail=0
check() {   # check NAME WANT GOT
    if [ "$2" = "$3" ]; then pass=$((pass + 1)); echo "  ok   $1"
    else fail=$((fail + 1)); echo "  FAIL $1: got '$3', want '$2'"; fi
}
has() {     # has NAME TEXT PATTERN(fixed string) — a NON-EMPTY text that contains it
    if [ -n "$2" ] && printf '%s\n' "$2" | grep -qF -- "$3"; then pass=$((pass + 1)); echo "  ok   $1"
    else fail=$((fail + 1)); echo "  FAIL $1: no '$3' in: $(printf '%s' "$2" | head -c 400)"; fi
}

if [ "$MODE" = all ] || [ "$MODE" = stub ]; then
    echo "== stub: tools/bench_alloc_sets.sh"
    # a fake tree: Project.toml, a bench.jl that mentions the flag, and per-process canned output stub/<i>.tsv
    mktree() {   # mktree DIR -- then the caller fills stub/1.tsv …
        mkdir -p "$1/tools" "$1/stub"; : > "$1/Project.toml"
        echo '# stub bench.jl: --alloc-only' > "$1/tools/bench.jl"
    }
    row() { printf 'ALLOC\t%s\t%s\t%s\t%s\t64\t10\n' "$1" "$2" "$2" "$2"; }
    mkdir -p "$W/bin"
    cat > "$W/bin/julia" <<'SH'
#!/usr/bin/env bash
# stub: the n-th call in this tree prints stub/n.tsv; "fail" in stub/n.tsv makes it exit 1
n=$(( $(cat .n 2>/dev/null || echo 0) + 1 )); echo "$n" > .n
echo "args: $*" >&2
[ "$(cat "stub/$n.tsv")" = fail ] && exit 1
cat "stub/$n.tsv"
SH
    chmod +x "$W/bin/julia"
    export PATH="$W/bin:$PATH"
    A="$W/A"; B="$W/B"; mktree "$A"; mktree "$B"
    for i in 1 2 3 4 5; do
        # A: 'write clause' {237x4, 239x1}; B: {239x5}; 'steady' 12 on both; 'multi' A {1x3, 2x2} B {1x2, 2x3}
        w=237; [ "$i" = 5 ] && w=239
        { row "write clause" "$w"; row steady 12; row multi $((i <= 3 ? 1 : 2)); row mode $((i <= 3 ? 10 : 11)); } > "$A/stub/$i.tsv"
        { row "write clause" 239; row steady 12; row multi $((i <= 2 ? 1 : 2)); row mode $((i <= 4 ? 10 : 12)); } > "$B/stub/$i.tsv"
    done
    out="$(BENCH_ALLOC_OUT="$W/out" bash "$ROOT/tools/bench_alloc_sets.sh" "$A" "$B" 5 2> "$W/err")"; rc=$?
    check "5 processes per side: exit 0" 0 "$rc"
    check "alternation: ten processes ran, five per side" "5 5" "$(cat "$A/.n") $(cat "$B/.n")"
    check "each process's rows are kept" 10 "$(ls "$W/out"/*.tsv | wc -l | tr -d ' ')"
    has "bimodal A displays as a SET" "$out" "{237x4, 239x1}"
    has "unimodal B displays as a set" "$out" "{239x5}"
    has "a modal shift is flagged" "$(printf '%s\n' "$out" | grep '^write clause')" "MODE SHIFT"
    has "an identical case is identical" "$(printf '%s\n' "$out" | grep '^steady')" "identical"
    has "a multiplicity-only difference is 'same set'" "$(printf '%s\n' "$out" | grep '^multi')" "same set"
    has "same mode, different sets: 'mode same', not a shift" "$(printf '%s\n' "$out" | grep '^mode')" "mode same"
    has "the summary counts the shifts" "$out" "4 case(s), 1 with a MODE SHIFT"
    has "the process was asked for --alloc-only" "$(cat "$W/out/A_1.err")" "--alloc-only"
    # the same bimodal case on both sides is NOT a shift (the whole point of D-0172)
    rm -f "$A/.n" "$B/.n"
    for i in 1 2 3 4 5; do cp "$A/stub/$i.tsv" "$B/stub/$i.tsv"; done
    out2="$(BENCH_ALLOC_OUT="$W/out2" bash "$ROOT/tools/bench_alloc_sets.sh" "$A" "$B" 5 2> /dev/null)"
    has "the same bimodal sets on both sides: no shift" "$out2" "4 case(s), 0 with a MODE SHIFT"
    # refusals
    bash "$ROOT/tools/bench_alloc_sets.sh" "$A" "$B" 0 > /dev/null 2>&1; check "N=0 refused (exit 2)" 2 "$?"
    bash "$ROOT/tools/bench_alloc_sets.sh" "$A" "$W/nowhere" 5 > /dev/null 2>&1; check "a missing tree refused (exit 2)" 2 "$?"
    mkdir -p "$W/D/tools"; echo '# stub bench.jl: --alloc-only' > "$W/D/tools/bench.jl"   # a directory, but no Project.toml
    bash "$ROOT/tools/bench_alloc_sets.sh" "$A" "$W/D" 5 > /dev/null 2>&1; check "a directory without Project.toml refused (exit 2)" 2 "$?"
    mktree "$W/C"; echo '# no flag here' > "$W/C/tools/bench.jl"
    bash "$ROOT/tools/bench_alloc_sets.sh" "$A" "$W/C" 5 > /dev/null 2>&1; check "a tree whose bench.jl lacks the flag refused (exit 2)" 2 "$?"
    rm -f "$A/.n" "$B/.n"; echo fail > "$B/stub/2.tsv"
    BENCH_ALLOC_OUT="$W/out3" bash "$ROOT/tools/bench_alloc_sets.sh" "$A" "$B" 5 > /dev/null 2>&1
    check "a failing process stops the run (exit 3)" 3 "$?"
    # (B's stub/2 held 'fail' above: restore it, or this case would exit 3 from THAT process, not from the empty one)
    cp "$A/stub/2.tsv" "$B/stub/2.tsv"
    rm -f "$A/.n" "$B/.n"; printf '# only comments\n' > "$B/stub/1.tsv"
    BENCH_ALLOC_OUT="$W/out4" bash "$ROOT/tools/bench_alloc_sets.sh" "$A" "$B" 5 > /dev/null 2>&1
    check "a process that prints NO rows is a failure, not an empty set (exit 3)" 3 "$?"
    # the same for a failing process on side A
    rm -f "$A/.n" "$B/.n"; cp "$A/stub/1.tsv" "$B/stub/1.tsv"   # (B's stub/1 held only comments above)
    cp "$A/stub/2.tsv" "$W/a2.keep"; echo fail > "$A/stub/2.tsv"
    BENCH_ALLOC_OUT="$W/out7" bash "$ROOT/tools/bench_alloc_sets.sh" "$A" "$B" 5 > /dev/null 2>&1
    check "a failing process on side A stops the run (exit 3)" 3 "$?"
    cp "$W/a2.keep" "$A/stub/2.tsv"
    # fewer than five processes per side runs, with a warning (D-0172 asks >= 5)
    rm -f "$A/.n" "$B/.n"
    BENCH_ALLOC_OUT="$W/out8" bash "$ROOT/tools/bench_alloc_sets.sh" "$A" "$B" 3 > /dev/null 2> "$W/err3"; rc=$?
    check "N=3 still runs (exit 0)" 0 "$rc"
    has "N=3 warns that D-0172 asks for five" "$(cat "$W/err3")" "WARNING N=3 < 5"
    # an aggregation that dies (awk exits 1) is a failure of the script, not an empty table
    rm -f "$A/.n" "$B/.n"; cp "$A/stub/1.tsv" "$B/stub/1.tsv"; mkdir -p "$W/badawk"
    printf '#!/bin/sh\nexit 1\n' > "$W/badawk/awk"; chmod +x "$W/badawk/awk"
    PATH="$W/badawk:$PATH" BENCH_ALLOC_OUT="$W/out6" bash "$ROOT/tools/bench_alloc_sets.sh" "$A" "$B" 5 > /dev/null 2>&1
    check "an aggregation that fails is a non-zero exit" 1 "$?"
    # BENCH_ALLOC_BENCH: a bench.jl for the base tree whose own predates the flag
    echo '# old bench' > "$W/C/tools/bench.jl"; rm -f "$A/.n" "$W/C/.n"; mkdir -p "$W/C/stub"
    for i in 1 2 3 4 5; do cp "$A/stub/$i.tsv" "$W/C/stub/$i.tsv"; done
    BENCH_ALLOC_BENCH="$A/tools/bench.jl" BENCH_ALLOC_OUT="$W/out5" bash "$ROOT/tools/bench_alloc_sets.sh" "$A" "$W/C" 5 > /dev/null 2>&1
    check "BENCH_ALLOC_BENCH runs the given bench.jl on a tree without the flag" 0 "$?"
fi

if [ "$MODE" = all ] || [ "$MODE" = real ]; then
    echo "== real: tools/bench.jl --alloc-only"
    mkdir -p "$W/swbin"
    printf '#!/usr/bin/env bash\necho called >> "%s/swipl_called"\nexit 99\n' "$W" > "$W/swbin/swipl"
    chmod +x "$W/swbin/swipl"
    julia --startup-file=no -e 'sleep(300)' &   # another julia process alive at the flag's start: the timed report refuses
    HELPER=$!
    for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$HELPER" 2> /dev/null && [ -d "/proc/$HELPER" ] && break; sleep 1; done
    before="$(ls "$ROOT/tools/bench_results" 2> /dev/null | sort)"
    out="$(cd "$ROOT" && env -u BENCH_GATE_SAMPLE PATH="$W/swbin:$PATH" \
        julia --project=. tools/bench.jl --alloc-only --runs=2 "compare ground" "var-var" 2> "$W/real.err")"; rc=$?
    check "exit 0 with another julia process alive, no gate sample, no --ungated" 0 "$rc"
    rows="$(printf '%s\n' "$out" | grep -c '^ALLOC	')"
    check "one ALLOC row per selected case (2)" 2 "$rows"
    bad="$(printf '%s\n' "$out" | grep '^ALLOC	' | awk -F'\t' 'NF != 7 || $3 !~ /^[0-9]+(\.[0-9]+)?$/ || $4 !~ /^[0-9.]+$/ || $5 !~ /^[0-9.]+$/ || $6 < 1 { n++ } END { print n + 0 }')"
    check "every ALLOC row has 7 fields and numeric counts" 0 "$bad"
    has "the compare ground row is there" "$out" "ALLOC	compare ground	"
    check "no timing column or ratio is printed" 0 "$(printf '%s\n' "$out" | grep -ciE 'us_per_call|swipl µs|LK/swipl|QUIET|ratio')"
    check "swipl was never called" none "$([ -e "$W/swipl_called" ] && echo called || echo none)"
    check "no tools/bench_results file written" "$before" "$(ls "$ROOT/tools/bench_results" 2> /dev/null | sort)"
fi

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
