#!/usr/bin/env bash
# ORIGINAL: tools/check_parse.jl's own cases — no swipl-devel twin. FAKE trees in a temp dir; each case is judged
# by the exit code AND the file:line the message names. Both directions: a clean tree passes, a file with an invalid
# string escape (`"\+ x"`, the TABTEST-REBUILD class) fails with its file:line, an incomplete expression fails, the same
# file passes again once the line is fixed, an error in src/ and in tools/ is found (the scan is not test/ only), a tree
# with no .jl file is refused with exit 2. Three MUTANTS of the checker (a sed copy, asserted to differ from the original)
# are judged on the fixture that only the original verdict separates: one that ignores :error nodes, one that ignores
# :incomplete nodes, one that scans test/ only must each answer "no parse error" where the original fails. The scan
# runs over the real checkout too, non-empty. Julia: $JULIA or `julia` on PATH, started with --startup-file=no.
# Exit 0 only if every case passes.
set -uo pipefail
REAL="$(cd "$(dirname "$0")/.." && pwd)"
TOOL="$REAL/tools/check_parse.jl"
JULIA="${JULIA:-julia}"
W="$(mktemp -d "${TMPDIR:-/tmp}/cpr.XXXXXX")"
trap 'rm -rf "$W"' EXIT
pass=0 fail=0

# case_ LABEL WANT_RC NAMED TOOLFILE DIR — TOOLFILE on DIR; NAMED (if non-empty) must occur in the output
case_() {
    local label="$1" want="$2" named="$3" tool="$4" dir="$5" out rc ok=1
    out="$("$JULIA" --startup-file=no "$tool" "$dir" 2>&1)"
    rc=$?
    [ "$rc" = "$want" ] || ok=0
    if [ -n "$named" ]; then printf '%s' "$out" | grep -qF -- "$named" || ok=0; fi
    if [ "$ok" = 1 ]; then pass=$((pass + 1)); echo "  ok   $label (exit $rc)"
    else fail=$((fail + 1)); echo "  FAIL $label: exit $rc, want $want, named '$named'"; printf '%s\n' "$out" | sed 's/^/       /'; fi
}

mk() {   # mk NAME — a clean fake tree W/NAME with src/, test/ and tools/ files (look-alikes of the bad forms included)
    mkdir -p "$W/$1/src" "$W/$1/test" "$W/$1/tools"
    cat > "$W/$1/src/a.jl" << 'EOF'
f(x) = x + 1
g() = "a \\+ b"
EOF
    cat > "$W/$1/test/b.jl" << 'EOF'
@test occursin("\\+ goal", s)
# "\+ goal" in a comment is not code
h() = raw"\+ goal"
EOF
    cat > "$W/$1/tools/c.jl" << 'EOF'
function k()
    1
end
EOF
}

mk clean
case_ "a clean tree (look-alikes included) passes" 0 "3 .jl file(s) scanned, no parse error" "$TOOL" "$W/clean"

mk esc; printf 'x = 1\ny = "\\+ goal"\nz = 2\n' > "$W/esc/test/d.jl"
case_ "an invalid string escape is a failure, on its line" 1 "test/d.jl:2: [error] invalid escape sequence" "$TOOL" "$W/esc"
case_ "... and the count names the file" 1 "1 of 4 .jl file(s) do not parse" "$TOOL" "$W/esc"
printf 'x = 1\ny = "\\\\+ goal"\nz = 2\n' > "$W/esc/test/d.jl"
case_ "the same file passes once the escape is doubled" 0 "4 .jl file(s) scanned, no parse error" "$TOOL" "$W/esc"

mk inc; printf 'function g()\n    1\n' > "$W/inc/test/e.jl"
case_ "an incomplete expression is a failure" 1 "test/e.jl:3: [incomplete]" "$TOOL" "$W/inc"

mk srcb; printf 'a = 1\nb = (2\n' > "$W/srcb/src/s.jl"; printf 'c = 3\nd = "\\+ x"\n' > "$W/srcb/tools/t.jl"
case_ "a bad file in src/ is found" 1 "src/s.jl:" "$TOOL" "$W/srcb"
case_ "a bad file in tools/ is found" 1 "tools/t.jl:2: [error]" "$TOOL" "$W/srcb"

mkdir -p "$W/empty/src"
case_ "a tree with no .jl file is refused (an empty scan proves nothing)" 2 "an empty scan proves nothing" "$TOOL" "$W/empty"
case_ "no such directory is refused" 2 "no such directory" "$TOOL" "$W/nowhere"

# MUTANTS: a sed copy of the checker, asserted to differ; the fixture holds ONLY the defect that mutant would miss
mutant() {   # mutant NAME SED_EXPR
    cp "$TOOL" "$W/$1.jl"
    sed -i -e "$2" "$W/$1.jl"
    if cmp -s "$TOOL" "$W/$1.jl"; then fail=$((fail + 1)); echo "  FAIL mutant $1: the sed expression changed nothing"; return 1; fi
}
mk mx1; printf 'y = "\\+ goal"\n' > "$W/mx1/test/d.jl"
mutant ign_error 's/Meta.isexpr(x, :error) || //' &&
    case_ "mutant: ignoring :error nodes passes the escape tree the original fails" 0 "no parse error" "$W/ign_error.jl" "$W/mx1"
mk mx2; printf 'function g()\n    1\n' > "$W/mx2/test/e.jl"
mutant ign_incomplete 's/ || Meta.isexpr(x, :incomplete)//' &&
    case_ "mutant: ignoring :incomplete nodes passes the incomplete tree the original fails" 0 "no parse error" "$W/ign_incomplete.jl" "$W/mx2"
mk mx3; printf 'y = "\\+ goal"\n' > "$W/mx3/src/s.jl"; printf 'z = (1\n' > "$W/mx3/tools/t.jl"
mutant test_only 's/for sub in ("test", "tools", "src")/for sub in ("test",)/' &&
    case_ "mutant: scanning test/ only passes the src/ and tools/ tree the original fails" 0 "no parse error" "$W/test_only.jl" "$W/mx3"
case_ "the original fails each of the three mutant fixtures (mx1)" 1 "test/d.jl:1:" "$TOOL" "$W/mx1"
case_ "the original fails each of the three mutant fixtures (mx2)" 1 "test/e.jl:" "$TOOL" "$W/mx2"
case_ "the original fails each of the three mutant fixtures (mx3)" 1 "2 of 5" "$TOOL" "$W/mx3"

# the real tree: the scan is non-empty and finds nothing (a hit here is a real defect of the checkout)
case_ "this checkout's test/, tools/ and src/ all parse, and the scan is non-empty" 0 ".jl file(s) scanned, no parse error" "$TOOL" "$REAL"

echo "test_check_parse: $pass passed, $fail failed"
[ "$fail" = 0 ]
