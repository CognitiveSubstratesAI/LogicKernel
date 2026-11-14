#!/usr/bin/env bash
# ORIGINAL: no swipl-devel counterpart — the mode guard of the tools/ test scripts (audit D-0666 item 2).
#
# CIREF2's compile job once failed with exit 126 because tools/test_check_where_return.sh was committed as mode 100644.
# This test makes every tools/test_*.sh of the tree be mode 100755 (read from the INDEX: `git ls-files -s`), through ONE
# extractor, `modes_check DIR`, used for the real tree and for the fixtures. The guard has two sides: it must find at
# least one test_*.sh AND at least one 100755 in DIR (an empty listing is a failure, not a pass), and it must report
# each tracked test_*.sh whose mode is not 100755. Fixtures are throw-away git repos in a temp dir: a 100644 test file
# is reported (rc 1, its path named), a 100755 one passes (rc 0), a mix reports only the 644 one, a subdirectory file is
# reached, a non-test 100644 file is no finding, an empty repo is a failure. Exit 0 only if every case passes.
set -uo pipefail
REAL="$(cd "$(dirname "$0")/.." && pwd)"
W="$(mktemp -d "${TMPDIR:-/tmp}/tmodes.XXXXXX")"
trap 'rm -rf "$W"' EXIT
pass=0 fail=0
ok() { pass=$((pass + 1)); echo "  ok   $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL $1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       /'; }

# modes_check DIR — prints "found N test file(s), M executable" and one "NOT 100755: PATH" line per offender;
# rc 0 only if N >= 1, M >= 1 and no offender.
modes_check() {
    local dir="$1" listing
    listing="$(git -C "$dir" ls-files -s tools 2> /dev/null)" || { echo "modes_check: not a git work tree: $dir"; return 2; }
    printf '%s\n' "$listing" | awk '
        $4 ~ /(^|\/)test_[^\/]*\.sh$/ { n++; if ($1 == "100755") m++; else { bad++; print "NOT 100755: " $4 " (" $1 ")" } }
        END {
            printf "found %d test file(s), %d executable\n", n, m
            if (n < 1 || m < 1 || bad > 0) exit 1
        }'
}

# fixture NAME FILE:MODE... — a git repo W/NAME with the files added to its index at the given modes (644 or 755)
fixture() {
    local name="$1" spec f m
    shift
    mkdir -p "$W/$name"
    env -u GIT_INDEX_FILE -u GIT_DIR -u GIT_WORK_TREE git -C "$W/$name" init -q
    for spec in "$@"; do
        f="${spec%:*}"
        m="${spec#*:}"
        mkdir -p "$W/$name/$(dirname "$f")"
        printf '#!/usr/bin/env bash\ntrue\n' > "$W/$name/$f"
        chmod "$m" "$W/$name/$f"
        env -u GIT_INDEX_FILE -u GIT_DIR -u GIT_WORK_TREE git -C "$W/$name" add "$f"
        env -u GIT_INDEX_FILE -u GIT_DIR -u GIT_WORK_TREE git -C "$W/$name" update-index --chmod="$([ "$m" = 755 ] && echo +x || echo -x)" "$f"
    done
}
# case LABEL WANT_RC DIR ROW... — modes_check's rc and every ROW (fixed string) in its output
case_() {
    local label="$1" want="$2" dir="$3" out rc r good=1
    shift 3
    out="$(env -u GIT_INDEX_FILE -u GIT_DIR -u GIT_WORK_TREE bash -c "$(declare -f modes_check); modes_check \"\$1\"" _ "$dir" 2>&1)"
    rc=$?
    [ "$rc" = "$want" ] || good=0
    for r in "$@"; do printf '%s' "$out" | grep -qF -- "$r" || good=0; done
    if [ "$good" = 1 ]; then ok "$label (rc $rc)"; else bad "$label: rc $rc, want $want" "$out"; fi
}

fixture planted tools/test_x.sh:644 tools/test_y.sh:755
case_ "a planted 100644 test file is reported by path and mode (rc 1)" 1 "$W/planted" "NOT 100755: tools/test_x.sh (100644)" "found 2 test file(s), 1 executable"
if env -u GIT_INDEX_FILE bash -c "$(declare -f modes_check); modes_check \"$W/planted\"" 2> /dev/null | grep -F 'test_y.sh' > /dev/null; then bad "a 100755 file next to the offender was reported too"; else ok "the 100755 file next to the offender is not reported"; fi
fixture clean tools/test_a.sh:755 tools/test_b.sh:755 tools/helper.py:644
case_ "100755 test files only (and a 100644 non-test file): pass (rc 0)" 0 "$W/clean" "found 2 test file(s), 2 executable"
fixture sub tools/sub/test_deep.sh:644 tools/test_top.sh:755
case_ "a 100644 test file in a subdirectory is reached (rc 1)" 1 "$W/sub" "NOT 100755: tools/sub/test_deep.sh (100644)"
fixture onlynon tools/helper.sh:644 tools/test_ok.sh:755
case_ "a 100644 file that is not a test_*.sh is no finding (rc 0)" 0 "$W/onlynon" "found 1 test file(s), 1 executable"
fixture notests tools/helper.sh:755
case_ "no test_*.sh at all is a failure, not a pass (rc 1)" 1 "$W/notests" "found 0 test file(s), 0 executable"
mkdir -p "$W/emptyrepo" && env -u GIT_INDEX_FILE -u GIT_DIR -u GIT_WORK_TREE git -C "$W/emptyrepo" init -q
case_ "an empty repo is a failure (rc 1)" 1 "$W/emptyrepo" "found 0 test file(s)"
mkdir -p "$W/nogit"
case_ "a directory that is no git work tree is refused (rc 2)" 2 "$W/nogit" "not a git work tree"

# THE TREE: every tools/test_*.sh of this checkout, both sides non-empty
out="$(modes_check "$REAL" 2>&1)"
rc=$?
if [ "$rc" = 0 ]; then ok "the tree: every tools/test_*.sh is 100755 ($out)"; else bad "the tree: rc $rc" "$out"; fi

echo "test_tool_modes: $pass passed, $fail failed"
[ "$fail" = 0 ]
