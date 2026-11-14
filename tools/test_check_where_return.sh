#!/usr/bin/env bash
# ORIGINAL: tools/check_where_return.sh's own cases — no swipl-devel counterpart. FAKE trees in a temp dir; each case
# is judged by the exit code AND the file:line the message names. Both directions: the bad forms are findings (each on
# its own line), the correct forms pass (the multi-line `function ...::R where {T}`, the one-line `where {T}` without a
# return type, a `where` variable used only in the return type, a variable that is a substring of another word, a
# comment, a string and a docstring that quote the bad form), a tree with no .jl file is refused (exit 2), `--changed`
# looks at the files that differ from origin/main only. Then THE CHECKER'S OWN MUTANTS: seven hand-broken copies of the
# tool (a check loosened, tightened or turned off, each by one exact replacement that must occur exactly once) run the
# SAME rows, and every one must FAIL at least one row (a row set that no broken checker can fail guards nothing).
# LOGICKERNEL_CHECK_WHERE_RETURN_TOOL=<file> runs the rows against another copy of the tool (the mutants use it).
# Exit 0 only if every case passes and every mutant is caught.
set -uo pipefail
REAL="$(cd "$(dirname "$0")/.." && pwd)"
TOOL0="${LOGICKERNEL_CHECK_WHERE_RETURN_TOOL:-$REAL/tools/check_where_return.sh}"
W="$(mktemp -d "${TMPDIR:-/tmp}/cwr.XXXXXX")"
trap 'rm -rf "$W"' EXIT
NOREPLY="11524260+sivaji1012@users.noreply.github.com"

# rows TOOL QUIET — run every row against TOOL; sets ROWS_PASS / ROWS_FAIL; QUIET=1 prints nothing
rows() {
    local TOOL="$1" quiet="$2"
    ROWS_PASS=0 ROWS_FAIL=0
    local D="$W/rows.$$.$RANDOM"
    mkdir -p "$D"
    say() { [ "$quiet" = 1 ] || printf '%s\n' "$1"; }
    # mk NAME FILE-TEXT — a fake tree D/NAME with src/a.jl holding FILE-TEXT and test/b.jl clean
    mk() {
        mkdir -p "$D/$1/src" "$D/$1/test"
        printf '%s\n' "$2" > "$D/$1/src/a.jl"
        printf '@test 1 == 1\n' > "$D/$1/test/b.jl"
    }
    # case LABEL WANT_RC NAMED DIR [ARG...] — the tool on DIR; NAMED (if any) must occur in the output
    case_() {
        local label="$1" want="$2" named="$3" dir="$4" out rc ok=1
        shift 4
        out="$("$TOOL" "$@" "$dir" 2>&1)"
        rc=$?
        [ "$rc" = "$want" ] || ok=0
        if [ -n "$named" ]; then printf '%s' "$out" | grep -qF -- "$named" || ok=0; fi
        if [ "$ok" = 1 ]; then ROWS_PASS=$((ROWS_PASS + 1)); say "  ok   $label (exit $rc)"
        else ROWS_FAIL=$((ROWS_FAIL + 1)); say "  FAIL $label: exit $rc, want $want, named '$named'"; [ "$quiet" = 1 ] || printf '%s\n' "$out" | sed 's/^/       /'; fi
    }

    # ---- the findings ----
    mk f1 'visibleClause(c::Clause{T})::Bool where {T} = c.x'
    case_ "the CIFIX1 form: one line, ::Bool where {T}, T in the argument" 1 "src/a.jl:1: visibleClause(c::Clause{T})::Bool where {T} = c.x" "$D/f1"
    mk f2 'f(x::Vector{T})::Int where T = 1'
    case_ "bare \`where T\` (no braces)" 1 "src/a.jl:1:" "$D/f2"
    mk f3 '@inline g(x::Dict{K,V})::V where {K,V} = x.v'
    case_ "a modifier before the name; K and V in the annotation" 1 "src/a.jl:1:" "$D/f3"
    mk f4 $'# header\n\nh(\n    x::Ref{T},\n    y,\n)::Bool where {T} = true'
    case_ "the argument list over several lines: the finding is on the line of its \`(\`" 1 "src/a.jl:3: h(" "$D/f4"
    mk f5 'f(x::C{T}, y::D)::R where {S, T} = 1'
    case_ "where {S, T}: the SECOND variable is the one used" 1 "src/a.jl:1:" "$D/f5"
    mk f6 'f(x::Clause{T})::Bool where {T<:AbstractTerm} = 1'
    case_ "a bounded variable T<:AbstractTerm" 1 "src/a.jl:1:" "$D/f6"
    mk f7 'f(x::Int; k::Vector{T}=T[])::R where {T} = 1'
    case_ "a keyword argument's annotation" 1 "src/a.jl:1:" "$D/f7"
    mk f8 '(::Type{T})(x::Int)::R where {T} = 1'
    case_ "a callable-object head (::Type{T})(...)" 1 "src/a.jl:1:" "$D/f8"
    mk f9 $'ok(x) = 1\nok2(x::Int) = 2\nok3(x::C{T}) where {T} = 3\nbad(x::C{T})::R where {T} = 4'
    case_ "the finding is on ITS line, not on the clean neighbours'" 1 "src/a.jl:4: bad(" "$D/f9"
    mk f10 $'bad(x::C{T})::R where {T} = 1\nbad2(y::D{S})::Q where {S} = 2'
    case_ "two findings are two lines and are counted" 1 "2 finding(s)" "$D/f10"

    # ---- the correct forms ----
    mk p1 $'function f(x::C{T})::R where {T}\n    return 1\nend'
    case_ "the multi-line function with ::R where {T} passes" 0 "no where-bound return type" "$D/p1"
    mk p2 'f(x::C{T}) where {T} = 1'
    case_ "the one-line method WITHOUT a return type passes" 0 ".jl file(s) scanned" "$D/p2"
    mk p3 $'function f(\n    x::C{T},\n    y::Int,\n)::R where {T}\n    return 1\nend'
    case_ "the multi-line function with the argument list wrapped passes" 0 ".jl file(s) scanned" "$D/p3"
    mk p4 $'# f(x::C{T})::Bool where {T} = 1  <- the bad form, quoted\nf(x::C{T}) where {T} = 2'
    case_ "a comment that quotes the bad form passes" 0 ".jl file(s) scanned" "$D/p4"
    mk p5 'f(x::Int)::Vector{T} where {T} = T[]'
    case_ "T used only in the RETURN type passes" 0 ".jl file(s) scanned" "$D/p5"
    mk p6 $'"""\nf(x::C{T})::Bool where {T} = 1\n"""\nf(x::C{T}) where {T} = 2'
    case_ "a docstring that quotes the bad form passes" 0 ".jl file(s) scanned" "$D/p6"
    mk p7 's = "f(x::C{T})::Bool where {T} = 1"'
    case_ "a string literal that quotes the bad form passes" 0 ".jl file(s) scanned" "$D/p7"
    mk p8 'f(x::Tuple{Int})::Bool where {T} = true'
    case_ "T is a WORD: \`Tuple\` does not use T" 0 ".jl file(s) scanned" "$D/p8"
    mk p9 $'#= a block comment\nf(x::C{T})::Bool where {T} = 1\n=#\nf(x::C{T}) where {T} = 2'
    case_ "a block comment that holds the bad form passes" 0 ".jl file(s) scanned" "$D/p9"
    mk p10 $'g(x::C{T})::Bool where {T} == 1'
    case_ "\`==\` after the clause is no method definition" 0 ".jl file(s) scanned" "$D/p10"
    mk p11 'f(x::Int)::Bool = x > 0'
    case_ "a return type with no where passes" 0 ".jl file(s) scanned" "$D/p11"

    # ---- refusals ----
    mkdir -p "$D/empty/src"
    case_ "a tree with no .jl file is refused (an empty scan proves nothing)" 2 "an empty scan proves nothing" "$D/empty"
    case_ "no such directory is refused" 2 "no such directory" "$D/nowhere"
    mkdir -p "$D/bare"
    case_ "a directory with neither src/ nor test/ is refused" 2 "neither src/ nor test/" "$D/bare"
    # the same file flips with ONLY the planted line replaced
    mk flip 'f(x::C{T})::Bool where {T} = 1'
    case_ "(before the flip) the planted line is a finding" 1 "src/a.jl:1:" "$D/flip"
    printf 'f(x::C{T}) where {T} = 1\n' > "$D/flip/src/a.jl"
    case_ "the same tree passes once the line is fixed" 0 "no where-bound return type" "$D/flip"
    # a finding in test/ is found too
    mk intest 'ok(x) = 1'
    printf 'bad(x::C{T})::R where {T} = 1\n' > "$D/intest/test/b.jl"
    case_ "a finding under test/ is a finding" 1 "test/b.jl:1:" "$D/intest"

    # ---- --changed: only the files that differ from origin/main ----
    local R="$D/gitrepo"
    mkdir -p "$R/src" "$R/test"
    printf 'old(x::C{T})::R where {T} = 1\n' > "$R/src/old.jl"    # a bad line ALREADY on origin/main: not this branch's
    printf '@test 1 == 1\n' > "$R/test/b.jl"
    (
        cd "$R" && git init -q -b main . && git config user.name t && git config user.email "$NOREPLY" &&
            git add -A && git commit -q -m base && git update-ref refs/remotes/origin/main HEAD && git checkout -q -b wip/x
    )
    case_ "--changed with no changed file: exit 0 and says so" 0 "nothing to check" "$R" --changed
    printf 'clean(x::C{T}) where {T} = 1\n' > "$R/src/new.jl"
    case_ "--changed: a new clean file passes although old.jl (unchanged) has the bad form" 0 ".jl file(s) scanned" "$R" --changed
    case_ "the tree mode still sees old.jl's finding" 1 "src/old.jl:1:" "$R"
    printf 'bad(x::C{T})::R where {T} = 1\n' > "$R/src/new.jl"
    case_ "--changed: the new file's bad form is a finding, named" 1 "src/new.jl:1:" "$R" --changed
    mkdir -p "$D/nogit/src"
    printf 'f(x) = 1\n' > "$D/nogit/src/a.jl"
    case_ "--changed without an origin/main is refused (exit 2)" 2 "needs an origin/main" "$D/nogit" --changed

    # ---- the real tree: non-empty, and clean ----
    # (not in a mutant's run: the tree is 300 files and the rows above already catch every mutant)
    [ -n "${LOGICKERNEL_CHECK_WHERE_RETURN_TOOL:-}" ] ||
        case_ "this checkout's src/ and test/ are clean, and the scan is non-empty" 0 ".jl file(s) scanned" "$REAL"
}

if [ -n "${LOGICKERNEL_CHECK_WHERE_RETURN_TOOL:-}" ]; then
    # run as a mutant's row set: print the verdict only
    rows "$TOOL0" 1
    echo "mutant rows: $ROWS_PASS passed, $ROWS_FAIL failed"
    [ "$ROWS_FAIL" = 0 ]
    exit $?
fi

rows "$TOOL0" 0
pass=$ROWS_PASS fail=$ROWS_FAIL

# ---- THE CHECKER'S OWN MUTANTS: each is one exact replacement in a copy of the tool; each must break a row ----
# mutate NAME OLD NEW — a copy of the tool with OLD replaced by NEW (OLD must occur exactly once), run through the rows
mutate() {
    local name="$1" old="$2" new="$3" f="$W/mut_$1.sh" n out rc
    n="$(python3 -I -c 'import sys; print(open(sys.argv[1]).read().count(sys.argv[2]))' "$TOOL0" "$old")"
    if [ "$n" != 1 ]; then fail=$((fail + 1)); echo "  FAIL mutant $name: its old text occurs $n times (must be exactly 1)"; return; fi
    python3 -I -c 'import sys; s=open(sys.argv[1]).read(); open(sys.argv[2],"w").write(s.replace(sys.argv[3], sys.argv[4], 1))' "$TOOL0" "$f" "$old" "$new"
    chmod +x "$f"
    out="$(LOGICKERNEL_CHECK_WHERE_RETURN_TOOL="$f" bash "$REAL/tools/test_check_where_return.sh" 2>&1)"
    rc=$?
    if [ "$rc" != 0 ]; then pass=$((pass + 1)); echo "  ok   mutant $name is caught ($(printf '%s' "$out" | tail -1))"
    else fail=$((fail + 1)); echo "  FAIL mutant $name SURVIVES: every row passed on the broken checker"; fi
}
mutate M1_never_finds   '\bwhere\b' '\bwherex\b'
mutate M2_flags_every_where 'used = [v for v in names if any(re.search(r"(?<![\w.])" + re.escape(v) + r"(?!\w)", a) for a in annot)]' 'used = list(names)'
mutate M3_no_equals_needed 'if not (k < len(clean) and clean[k] == "=" and clean[k + 1 : k + 2] not in ("=", ">")):' 'if False:'
mutate M4_first_variable_only 'used = [v for v in names if' 'used = [v for v in names[:1] if'
mutate M5_substring_match 're.search(r"(?<![\w.])" + re.escape(v) + r"(?!\w)", a)' 're.search(re.escape(v), a)'
mutate M6_keeps_comments_and_strings 'clean = blank(raw)' 'clean = raw'
mutate M7_return_type_counts 'annot = [a for g in groups for a in annotations(g)]' 'annot = [a for g in groups for a in annotations(g)] + [mm.group(2)]'

echo "test_check_where_return: $pass passed, $fail failed"
[ "$fail" = 0 ]
