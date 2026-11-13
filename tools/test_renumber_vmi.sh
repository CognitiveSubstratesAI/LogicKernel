#!/usr/bin/env bash
# ORIGINAL: tools/renumber_vmi.py's own tests (every guard mutation-proved) — no swipl-devel counterpart.
# A FAKE tree (src/pl-vmi.jl with a 5-row `_CODE_TABLE`, a test file and a mutant list) per case under a temp dir, run with
# `--root`. Each case is judged by the EXIT CODE and by the file contents, in both directions: a consistent tree passes
# `--check` (non-empty table, non-empty quotes: the guard can pass), a stale or colliding tree fails (it can fail), and
# the same quote flips the verdict when ONLY the table order changes (it compares the right thing). Exit 0 only if every case passes.
#   1 idempotence: a consistent tree: --check exits 0 and a write changes no file
#   2 a table reorder: --check exits 1 and writes nothing; the write renumbers the constants, the fixture quote and the
#     mutant `old`; the `new` keeps its offset; a second write changes nothing and --check then exits 0
#   3 collision: two constants with one number, a row without a constant, a duplicate row: each exits 1, nothing written
#   4 the mutant-list text rows: old and new in one list renumbered; a `new` with no `old` number is UNRESOLVED (exit 1)
set -uo pipefail
REAL="$(cd "$(dirname "$0")/.." && pwd)"
W="$(mktemp -d "${TMPDIR:-/tmp}/rnv.XXXXXX")"
trap 'rm -rf "$W"' EXIT
pass=0 fail=0
ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
no() { fail=$((fail + 1)); printf 'FAIL %s\n' "$1"; }
run() { python3 -I "$REAL/tools/renumber_vmi.py" --root "$1" "${@:2}" > "$W/out.txt" 2>&1; }

# mk NAME [ORDER...] — fake tree $W/NAME; constants numbered by the first order given (CONSTS), rows in ORDER
mk() {
    local d="$W/$1"; shift
    mkdir -p "$d/src" "$d/test" "$d/tools/mutants"
    {
        printf 'const code = Int32\n'
        local i=0
        for n in $CONSTS; do printf '# PORT: pl-vmi.c %s\n"doc"\nconst %s = code(%d)\n' "$n" "$n" "$i"; i=$((i + 1)); done
        printf 'const _CODE_TABLE = (\n'
        local first=1
        for n in "$@"; do
            [ $first = 1 ] || printf ',\n'
            printf '    code_info(:%s, 0x00, 0, (0x00, 0x00, 0x00, 0x00))' "$n"; first=0
        done
        printf '\n)\n'
    } > "$d/src/pl-vmi.jl"
    printf 'using Test\nconst S_B = code(2)   # a fixture copy\nx = code(7)\n' > "$d/test/fix.jl"
    cat > "$d/tools/mutants/T.py" <<'PY'
MUTANTS = [
    dict(id="T-1 gap", file="src/pl-vmi.jl",
         old="const S_B = code(2)",
         new="const S_B = code(4)"),
    dict(id="T-2 other", file="src/pl-vmi.jl",
         old="const S_C = code(3)\n",
         new="const S_C = code(2)\n"),
]
PY
}
sums() { (cd "$1" && find . -type f | sort | xargs cat | md5sum); }

CONSTS="I_NOP S_A S_B S_C S_D"

# --- 1 idempotence
mk t1 I_NOP S_A S_B S_C S_D
before="$(sums "$W/t1")"
run "$W/t1" --check; rc=$?
{ [ $rc = 0 ] && grep -q '5 opcodes, 0 mismatches' "$W/out.txt"; } && ok "1a consistent tree: --check exits 0 over 5 opcodes" || no "1a (rc=$rc) $(cat "$W/out.txt")"
run "$W/t1"; rc=$?
{ [ $rc = 0 ] && [ "$(sums "$W/t1")" = "$before" ]; } && ok "1b write on a consistent tree changes no file" || no "1b (rc=$rc)"

# --- 2 a reorder: S_B and S_C swap places in the table (pl-vmi.c's order changed)
mk t2 I_NOP S_A S_C S_B S_D
before="$(sums "$W/t2")"
run "$W/t2" --check; rc=$?
{ [ $rc = 1 ] && grep -q 'S_B = code(2), _CODE_TABLE order says 3' "$W/out.txt" && [ "$(sums "$W/t2")" = "$before" ]; } \
    && ok "2a --check fails on the stale constants and writes nothing" || no "2a (rc=$rc) $(cat "$W/out.txt")"
run "$W/t2"; rc=$?
v="$W/t2/src/pl-vmi.jl"
{ [ $rc = 0 ] && grep -q '^const S_C = code(2)$' "$v" && grep -q '^const S_B = code(3)$' "$v" \
    && grep -q 'const S_B = code(3)   # a fixture copy' "$W/t2/test/fix.jl" && grep -q 'x = code(7)' "$W/t2/test/fix.jl"; } \
    && ok "2b write renumbers constants and the fixture quote, leaves an operand code(7)" || no "2b (rc=$rc) $(cat "$W/out.txt")"
m="$W/t2/tools/mutants/T.py"
{ grep -q 'old="const S_B = code(3)"' "$m" && grep -q 'new="const S_B = code(5)"' "$m" \
    && grep -q 'old="const S_C = code(2)\\n"' "$m" && grep -q 'new="const S_C = code(1)\\n"' "$m"; } \
    && ok "2c mutant texts: old = derived number, new keeps its offset (+2 and -1)" || no "2c $(cat "$m")"
after="$(sums "$W/t2")"
run "$W/t2"; rc=$?
{ [ $rc = 0 ] && [ "$(sums "$W/t2")" = "$after" ]; } && ok "2d second write is a no-op" || no "2d (rc=$rc)"
run "$W/t2" --check; rc=$?
[ $rc = 0 ] && ok "2e --check passes after the write" || no "2e (rc=$rc) $(cat "$W/out.txt")"

# --- 3 collision, a row without a constant, a duplicate row: each must FAIL and write nothing
mk t3 I_NOP S_A S_B S_C S_D
sed -i 's/^const S_C = code(3)$/const S_C = code(2)/; s/^const S_C = code(2)$/const S_C = code(2)/' "$W/t3/src/pl-vmi.jl"
sed -i 's/^const S_B = code(2)$/const S_B = code(2)/' "$W/t3/src/pl-vmi.jl"
before="$(sums "$W/t3")"
run "$W/t3"; rc=$?
{ [ $rc = 1 ] && grep -q 'collision: code(2) is declared by S_B, S_C' "$W/out.txt" && [ "$(sums "$W/t3")" = "$before" ]; } \
    && ok "3a two constants with one number: exit 1, nothing written" || no "3a (rc=$rc) $(cat "$W/out.txt")"
mk t4 I_NOP S_A S_B S_C S_D S_E
run "$W/t4"; rc=$?
{ [ $rc = 1 ] && grep -q 'S_E has no constant' "$W/out.txt"; } && ok "3b a row without a constant: exit 1" || no "3b (rc=$rc) $(cat "$W/out.txt")"
mk t5 I_NOP S_A S_B S_C S_D S_D
run "$W/t5" --check; rc=$?
{ [ $rc = 1 ] && grep -q 'row S_D declared twice' "$W/out.txt"; } && ok "3c a duplicate row: exit 1" || no "3c (rc=$rc) $(cat "$W/out.txt")"

# --- 4 the mutant-list text rows
mk t6 I_NOP S_A S_C S_B S_D
cat > "$W/t6/tools/mutants/T.py" <<'PY'
MUTANTS = [
    dict(id="U-1 new without old", file="src/pl-vmi.jl",
         old="foo",
         new="const S_B = code(9)"),
]
PY
run "$W/t6"; rc=$?
{ [ $rc = 1 ] && grep -q 'UNRESOLVED tools/mutants/T.py line 4: `new` quotes S_B = code(9)' "$W/out.txt" && grep -q 'new="const S_B = code(9)"' "$W/t6/tools/mutants/T.py"; } \
    && ok "4a a new text with no old number is UNRESOLVED (exit 1) and left as written" || no "4a (rc=$rc) $(cat "$W/out.txt")"
mk t7 I_NOP S_A S_B S_C S_D
rm "$W/t7/test/fix.jl"
sed -i 's/S_B = code(2)/S_B = code(1)/' "$W/t7/tools/mutants/T.py"   # stale quote in the list only
run "$W/t7" --check; rc=$?
{ [ $rc = 1 ] && grep -q 'T.py quotes an opcode number the table does not give' "$W/out.txt"; } \
    && ok "4b a stale mutant quote ALONE (constants consistent) fails --check" || no "4b (rc=$rc) $(cat "$W/out.txt")"

printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
