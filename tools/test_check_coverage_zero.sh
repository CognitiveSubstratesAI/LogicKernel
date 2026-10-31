#!/usr/bin/env bash
# ORIGINAL: tools/check_coverage_zero.sh's own tests (user, 2026-10-14: every guard mutation-proved) — no
# swipl-devel counterpart. FAKE repositories (git init in a temp dir, a fake `origin/main` ref), a fake
# package with fake src/ files and a fake tools/coverage_zero_known.txt; each case is judged by the EXIT
# CODE and by the file the message names, in both directions: a newly covered file still listed fails, an
# uncovered file not listed fails, a consistent push passes. Every case has a non-empty changed set and a
# non-empty list, so the guard can pass (the OK cases), can fail (the refusals) and compares the right
# thing (the same file flips the verdict when ONLY the list line changes). The pre-push hook is run in the
# same fake repo to prove the wiring. Exit 0 only if every case passes.
set -uo pipefail
REAL="$(cd "$(dirname "$0")/.." && pwd)"
W="$(mktemp -d "${TMPDIR:-/tmp}/ccz.XXXXXX")"
trap 'rm -rf "$W"' EXIT
NOREPLY="11524260+sivaji1012@users.noreply.github.com"
pass=0 fail=0

# mk NAME — a fake repo at $W/NAME: package Fake, src/Fake.jl including a.jl b.jl os/c.jl; zero.jl is listed
# (structural 0%); origin/main = the base commit; HEAD is a branch gate/x one step further (set by the case)
mk() {
    local d="$W/$1"
    mkdir -p "$d/src/os" "$d/tools/githooks"
    (
        cd "$d" || exit 1
        git init -q -b main . && git config user.name t && git config user.email "$NOREPLY"
        printf 'name = "Fake"\nuuid = "x"\n' > Project.toml
        printf 'module Fake\ninclude("a.jl")\ninclude("b.jl")\ninclude("os/c.jl")   # the C file\ninclude("zero.jl")\nend\n' > src/Fake.jl
        for f in a b os/c zero; do printf 'f() = 1\n' > "src/$f.jl"; done
        printf '# fake list\nsrc/zero.jl   # structural\n' > tools/coverage_zero_known.txt
        cp "$REAL/tools/check_coverage_zero.sh" "$REAL/tools/coverage_zero.py" tools/
        cp "$REAL/tools/githooks/pre-push" tools/githooks/
        git add -A && git commit -q -m base
        git update-ref refs/remotes/origin/main HEAD
        git checkout -q -b gate/x
    )
}
commit() { (cd "$1" && git add -A && git commit -q -m step); }

# run CASE WANT_RC NAME FILE_THE_MESSAGE_NAMES(or "") [ENV...] — the check in repo NAME
run() {
    local label="$1" want="$2" repo="$W/$3" named="$4"
    shift 4
    local out rc
    out=$(cd "$repo" && env "$@" tools/check_coverage_zero.sh 2>&1)
    rc=$?
    verdict "$label" "$want" "$rc" "$out" "$named"
}
verdict() {
    local label="$1" want="$2" rc="$3" out="$4" named="$5" ok=1 lines
    [ "$rc" = "$want" ] || ok=0
    if [ "$want" = 1 ] && [ -n "$named" ]; then printf '%s' "$out" | grep -qF -- "$named" || ok=0; fi
    if [ "$want" = 1 ]; then
        lines=$(printf '%s\n' "$out" | wc -l)
        [ "$lines" -le 10 ] || { ok=0; out="$out (message has $lines lines)"; }
        printf '%s' "$out" | grep -q 'coverage_zero_known.txt' || ok=0
    fi
    if [ "$ok" = 1 ]; then pass=$((pass + 1)); echo "  ok   $label (exit $rc)"
    else fail=$((fail + 1)); echo "  FAIL $label: exit $rc, want $want, named '$named'"; printf '%s\n' "$out" | sed 's/^/       /'; fi
}

# 1. consistent: a loaded, unlisted file changed -> pass (the changed set and the list are non-empty)
mk ok; echo 'f() = 2' >> "$W/ok/src/a.jl"; commit "$W/ok"
run "consistent: loaded unlisted file changed" 0 ok ""

# 2. a LISTED file changed (F1a: the step gives it code, the tests now cover it) -> fail, names the file
mk listed; echo 'f() = 2' >> "$W/listed/src/zero.jl"; commit "$W/listed"
run "listed file changed, line kept (F1a's red)" 1 listed src/zero.jl

# 3. the SAME push with ONLY the list line removed -> pass: the verdict follows the list
mk fixed; echo 'f() = 2' >> "$W/fixed/src/zero.jl"; printf '# fake list\n' > "$W/fixed/tools/coverage_zero_known.txt"; commit "$W/fixed"
run "same change, line removed from the list" 0 fixed ""

# 4. a listed file changed but declared structurally 0%: ACK of exactly that file passes, another file's does not
run "listed file changed, ACKed" 0 listed "" LOGICKERNEL_COVZERO_ACK=src/zero.jl
run "listed file changed, ACK names another file" 1 listed src/zero.jl LOGICKERNEL_COVZERO_ACK=src/a.jl

# 5. an uncovered file NOT listed: a new src file nothing includes -> fail, names it
mk newun; echo 'g() = 1' > "$W/newun/src/d.jl"; commit "$W/newun"
run "new file never loaded, not listed" 1 newun src/d.jl

# 6. the same new file listed (audited) -> pass
mk newlist; echo 'g() = 1' > "$W/newlist/src/d.jl"; printf '# fake list\nsrc/zero.jl\nsrc/d.jl\n' > "$W/newlist/tools/coverage_zero_known.txt"; commit "$W/newlist"
run "new file never loaded, listed" 0 newlist ""

# 7. the same new file loaded by a nested include of its basename -> pass (the proxy cannot tell more)
mk newinc; echo 'g() = 1' > "$W/newinc/src/d.jl"; echo 'include("d.jl")' >> "$W/newinc/src/os/c.jl"; commit "$W/newinc"
run "new file loaded (nested include)" 0 newinc ""

# 8. a listed file that is gone (deleted, list kept) -> fail, names it
mk gone; git -C "$W/gone" rm -q src/zero.jl; sed -i '/zero.jl/d' "$W/gone/src/Fake.jl"; echo 'f() = 2' >> "$W/gone/src/a.jl"; commit "$W/gone"
run "listed file deleted, line kept" 1 gone src/zero.jl

# 9. only a non-src file changed -> pass, with the list non-empty
mk nosrc; echo x > "$W/nosrc/README"; commit "$W/nosrc"
run "no src file changed" 0 nosrc ""

# 10. a flood of refusals stays within 10 lines and still names the first file
mk many; for i in 1 2 3 4 5 6 7 8 9 10 11 12; do echo 'g() = 1' > "$W/many/src/n$i.jl"; done; commit "$W/many"
run "twelve refusals, message capped" 1 many src/n1.jl

# 11. no verdict: an unreadable base is exit 2, never a pass
out=$(cd "$W/ok" && tools/check_coverage_zero.sh refs/remotes/origin/nonesuch HEAD 2>&1); rc=$?
verdict "unreadable base ref -> no verdict" 2 "$rc" "$out" ""
out=$(cd "$W/ok" && tools/check_coverage_zero.sh --lcov "$W/does-not-exist.info" 2>&1); rc=$?
verdict "missing LCOV file -> no verdict" 2 "$rc" "$out" ""

# --lcov mode: the SAME judgement as CI (tools/coverage_zero.py), restricted to the changed files
lcov() { # lcov FILE zero... — every src file at 3 hits, except the named ones at 0
    local f="$1"; shift
    (cd "$W/ok" && for s in $(git ls-files 'src/*.jl'); do
        n=3; for z in "$@"; do [ "$z" = "$s" ] && n=0; done
        printf 'SF:%s\nDA:1,%s\nDA:2,0\nend_of_record\n' "$s" "$n"
    done) > "$f"
}
# 12. changed + at 0% in the LCOV + not listed -> fail (an uncovered file not listed)
lcov "$W/l_new.info" src/a.jl src/zero.jl
out=$(cd "$W/ok" && tools/check_coverage_zero.sh --lcov "$W/l_new.info" 2>&1); rc=$?
verdict "lcov: changed file at 0%, not listed" 1 "$rc" "$out" src/a.jl
# 13. changed + covered in the LCOV + not listed -> pass
lcov "$W/l_ok.info" src/zero.jl
out=$(cd "$W/ok" && tools/check_coverage_zero.sh --lcov "$W/l_ok.info" 2>&1); rc=$?
verdict "lcov: changed file covered, not listed" 0 "$rc" "$out" ""
# 14. changed + listed + covered in the LCOV -> fail (a newly covered file still listed)
lcov "$W/l_cov.info"
out=$(cd "$W/listed" && tools/check_coverage_zero.sh --lcov "$W/l_cov.info" 2>&1); rc=$?
verdict "lcov: changed listed file covered, still listed" 1 "$rc" "$out" src/zero.jl
# 15. changed + listed + still 0% in the LCOV -> pass WITHOUT any ACK (the exact verdict replaces the heuristic)
lcov "$W/l_zero.info" src/zero.jl
out=$(cd "$W/listed" && tools/check_coverage_zero.sh --lcov "$W/l_zero.info" 2>&1); rc=$?
verdict "lcov: changed listed file still 0%" 0 "$rc" "$out" ""

# the pre-push hook runs it: a gate/* push with a refusal is refused, a consistent one passes, a non-gate ref is not its business
zeros=0000000000000000000000000000000000000000
hook() { # hook NAME REF -> runs the real hook (the copy in the fake repo) for HEAD pushed to REF
    local repo="$W/$1" sha
    sha=$(git -C "$repo" rev-parse HEAD)
    (cd "$repo" && git remote get-url origin > /dev/null 2>&1 || git remote add origin "$W/bare.git")
    printf 'refs/heads/gate/x %s %s %s\n' "$sha" "$2" "$zeros" | (cd "$repo" && tools/githooks/pre-push origin "$W/bare.git" 2>&1)
}
git init -q --bare "$W/bare.git"
out=$(hook listed refs/heads/gate/x); rc=$?
verdict "pre-push: gate/* push of F1a's shape is refused" 1 "$rc" "$out" src/zero.jl
out=$(hook ok refs/heads/gate/x); rc=$?
verdict "pre-push: gate/* push of a consistent change passes" 0 "$rc" "$out" ""
out=$(hook listed refs/heads/other/x); rc=$?
verdict "pre-push: a non-gate ref is not checked" 0 "$rc" "$out" ""
out=$(hook gone refs/heads/gate/x); rc=$?
verdict "pre-push: gate/* push with a deleted listed file is refused" 1 "$rc" "$out" src/zero.jl

echo "test_check_coverage_zero: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
