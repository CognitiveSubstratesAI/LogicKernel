#!/usr/bin/env bash
# ORIGINAL: tools/check_bool_atoms.sh's own cases — no swipl-devel counterpart. FAKE trees in a temp dir; each case
# is judged by the exit code AND the file:line the message names. Both directions: a clean tree passes (its files
# hold the look-alikes `Symbol("true")`, `mk_sym(T, :truthy)` and a comment that quotes a bad call), each planted
# pattern fails on its own line, the same file passes again once the planted line is replaced, and a tree with no
# .jl file (an empty scan) is refused with exit 2. The scan runs over a real tree too, with a non-empty file count.
# Exit 0 only if every case passes.
set -uo pipefail
REAL="$(cd "$(dirname "$0")/.." && pwd)"
TOOL="$REAL/tools/check_bool_atoms.sh"
W="$(mktemp -d "${TMPDIR:-/tmp}/cba.XXXXXX")"
trap 'rm -rf "$W"' EXIT
pass=0 fail=0

mk() {   # mk NAME — a clean fake tree W/NAME with src/a.jl and test/b.jl
    mkdir -p "$W/$1/src" "$W/$1/test"
    cat > "$W/$1/src/a.jl" <<'EOF'
f(T) = mk_sym(T, Symbol("true"))
g(T) = mk_sym(T, :truthy)
# mk_sym(T, :true) in a comment is not code
h(T) = lk_sym(T, "false")
EOF
    cat > "$W/$1/test/b.jl" <<'EOF'
@test lk_sym(T, :a) isa T
EOF
}
# case LABEL WANT_RC NAMED DIR — the tool on DIR; NAMED (for a refusal) must occur in the output
case_() {
    local label="$1" want="$2" named="$3" dir="$4" out rc ok=1
    out="$("$TOOL" "$dir" 2>&1)"
    rc=$?
    [ "$rc" = "$want" ] || ok=0
    if [ -n "$named" ]; then printf '%s' "$out" | grep -qF -- "$named" || ok=0; fi
    if [ "$ok" = 1 ]; then pass=$((pass + 1)); echo "  ok   $label (exit $rc)"
    else fail=$((fail + 1)); echo "  FAIL $label: exit $rc, want $want, named '$named'"; printf '%s\n' "$out" | sed 's/^/       /'; fi
}

mk clean
case_ "a clean tree, look-alikes and a comment included, passes" 0 "2 .jl file(s) scanned" "$W/clean"

mk t1; printf 'x(T) = mk_sym(T, :true)\n' >> "$W/t1/src/a.jl"
case_ "mk_sym(T, :true) is a hit, on its line" 1 "src/a.jl:5: x(T) = mk_sym(T, :true)" "$W/t1"
mk t2; printf 'x(U) = mk_sym(U, :false)\n' >> "$W/t2/src/a.jl"
case_ "mk_sym(U, :false): any type variable" 1 "src/a.jl:5:" "$W/t2"
mk t3; printf 'x(T) = mk_sym(T,:nothing)\n' >> "$W/t3/src/a.jl"
case_ "mk_sym(T,:nothing): no space" 1 "src/a.jl:5:" "$W/t3"
mk t4; printf '@test lk_sym(T, :false) isa T\n' >> "$W/t4/test/b.jl"
case_ "lk_sym(T, :false) in test/ is a hit" 1 "test/b.jl:2:" "$W/t4"
mk t5; printf 'x(T) = lk_sym(T, :true)\n' >> "$W/t5/test/b.jl"
case_ "lk_sym(T, :true) in test/ is a hit" 1 "1 hit(s)" "$W/t5"
mk t6; printf 'x(T) = mk_sym(T, :true) + mk_sym(T, :false)\n' >> "$W/t6/src/a.jl"
case_ "two patterns on one line count once per line" 1 "1 hit(s)" "$W/t6"
# the same file flips with ONLY the planted line replaced
sed -i 's/mk_sym(T, :true)/mk_sym(T, Symbol("true"))/' "$W/t1/src/a.jl"
case_ "the same tree passes once the line is fixed" 0 "no Bool-as-atom" "$W/t1"

mkdir -p "$W/empty/src"
case_ "a tree with no .jl file is refused (an empty scan proves nothing)" 2 "an empty scan proves nothing" "$W/empty"
case_ "no such directory is refused" 2 "no such directory" "$W/nowhere"
# the real tree: the scan is non-empty and finds nothing (a hit here is a real defect of the checkout)
case_ "this checkout's src/ and test/ are clean, and the scan is non-empty" 0 ".jl file(s) scanned" "$REAL"

echo "test_check_bool_atoms: $pass passed, $fail failed"
[ "$fail" = 0 ]
