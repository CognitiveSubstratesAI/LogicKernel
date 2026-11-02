#!/usr/bin/env bash
# ORIGINAL: no swipl-devel counterpart — the tests of tools/secret_scan.sh and tools/install_gitleaks.sh (audit D-0340)
# and of the secret-scan step of tools/prepush.sh. Throwaway git repositories under $TMPDIR. EVERY fake secret is
# GENERATED here at run time from /dev/urandom (the prefix of its shape is assembled from pieces) and is never stored
# in the repository, never written to the output: every text a case shows is scrubbed of it first.
#
#   tools/test_secret_scan.sh        # exit 0 only if every case passes; needs the pinned binary (tools/install_gitleaks.sh)
#
# Both sides of every guard: a clean range passes and a range with a token fails; a token OUTSIDE the range passes
# and the same token INSIDE it fails; the allowlist routes (a gitleaks:allow comment, a .gitleaksignore, an allowlist
# in the config, a GITLEAKS_* variable) are all closed or proven inert; a tampered binary and a wrong archive are refused.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
W="$(mktemp -d "${TMPDIR:-/tmp}/secret_scan_test.XXXXXX")"
trap 'rm -rf "$W"' EXIT
pass=0 fail=0
TOKS=()   # every secret generated below; scrub() hides them from anything printed
scrub() {
    local t="$1" s
    for s in "${TOKS[@]}"; do t="${t//"$s"/<FAKE-SECRET>}"; done
    printf '%s' "$t"
}
ok() {   # ok NAME WANT GOT
    if [ "$2" = "$3" ]; then pass=$((pass + 1)); echo "  ok   $1"
    else fail=$((fail + 1)); echo "  FAIL $1: got '$(scrub "$3")', want '$2'"; fi
}
has() {   # has NAME TEXT PATTERN — TEXT is non-empty and matches the ERE
    if [ -n "$2" ] && printf '%s\n' "$2" | grep -qE -- "$3"; then pass=$((pass + 1)); echo "  ok   $1"
    else fail=$((fail + 1)); echo "  FAIL $1: no match for /$3/ in: $(scrub "$(printf '%s' "$2" | head -c 300 | tr '\n' '|')")"; fi
}
hasnt() {   # hasnt NAME TEXT PATTERN — TEXT is non-empty and does NOT match
    if [ -n "$2" ] && ! printf '%s\n' "$2" | grep -qE -- "$3"; then pass=$((pass + 1)); echo "  ok   $1"
    else fail=$((fail + 1)); echo "  FAIL $1: unexpected /$3/ (or empty) in: $(scrub "$(printf '%s' "$2" | head -c 300 | tr '\n' '|')")"; fi
}
rnd() {   # rnd CHARSET LENGTH — LENGTH random characters of CHARSET
    local out="" c
    while [ "${#out}" -lt "$2" ]; do
        c="$(head -c 256 /dev/urandom | LC_ALL=C tr -dc "$1" | head -c "$(($2 - ${#out}))")"
        out="$out$c"
    done
    printf '%s' "$out"
}
newtok() {   # newtok KIND — sets TOK to a fresh fake secret (and registers it for scrubbing); never printed
    case "$1" in
        ghp) TOK="gh""p_$(rnd 'A-Za-z0-9' 36)" ;;
        aws) TOK="AK""IA$(rnd 'A-Z2-7' 16)" ;;
    esac
    TOKS+=("$TOK")
}
BIN="${LOGICKERNEL_GITLEAKS:-$ROOT/tools/bin/gitleaks}"
SCAN="$ROOT/tools/secret_scan.sh"
if ! "$SCAN" --check > "$W/check.txt" 2>&1; then
    echo "tools/test_secret_scan.sh: the pinned gitleaks is not installed ($(cat "$W/check.txt")); run tools/install_gitleaks.sh first"
    exit 1
fi

idt=(GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t.invalid)
commit() {   # commit DIR MESSAGE [REF] — everything staged becomes one commit on main (REF also set when given)
    local R="$1" c parent=()
    git -C "$R" rev-parse --verify -q HEAD > /dev/null && parent=(-p HEAD)
    git -C "$R" add -A
    c="$(env "${idt[@]}" git -C "$R" commit-tree "$(git -C "$R" write-tree)" "${parent[@]}" -m "$2")"
    git -C "$R" update-ref refs/heads/main "$c"
    [ -n "${3:-}" ] && git -C "$R" update-ref "$3" "$c"
    git -C "$R" reset -q --hard main
}
mkrepo() {   # mkrepo DIR — a repository whose origin/main is a clean base commit
    mkdir -p "$1/src"
    git init -q -b main "$1"
    printf 'f(x) = x\n' > "$1/src/a.jl"
    commit "$1" base refs/remotes/origin/main
}
scan() {   # scan DIR RANGE [ENV...] — output and status; the repository scanned is DIR
    local R="$1" range="$2"
    shift 2
    env LOGICKERNEL_SECRET_SCAN_REPO="$R" "$@" "$SCAN" "$range" 2>&1
}

# ---------------------------------------------------------------- a clean range, and a token outside the range
R="$W/r1"
mkrepo "$R"
printf 'f(x) = x\ng(x) = x + 1\n' > "$R/src/a.jl"
commit "$R" "ADDED: g"
out="$(scan "$R" origin/main..HEAD)"; rc=$?
ok "clean range: exit 0" 0 "$rc"
has "clean range: says clean and counts the commit" "$out" '^secret_scan: clean — gitleaks 8\.30\.1, 1 commit\(s\) in origin/main\.\.HEAD scanned'

newtok ghp
R="$W/r2"
mkdir -p "$R/src"; git init -q -b main "$R"
printf 'f(x) = x\nTOKEN=%s\n' "$TOK" > "$R/src/old.jl"   # the token sits in the BASE commit, outside the range
commit "$R" base refs/remotes/origin/main
printf 'f(x) = x\ng(x) = 2\n' > "$R/src/a.jl"
commit "$R" "ADDED: g"
out="$(scan "$R" origin/main..HEAD)"; rc=$?
ok "token in the base commit only: the range scan is clean (exit 0)" 0 "$rc"
out="$(scan "$R" HEAD)"; rc=$?
ok "the same token, whole history: exit 1 (the scan does see it)" 1 "$rc"
has "whole history: names the rule" "$out" 'RuleID:[[:space:]]+github-pat'

# ---------------------------------------------------------------- a token in the range: each shape, caught and redacted
for kind in ghp aws; do
    newtok "$kind"
    R="$W/r3$kind"
    mkrepo "$R"
    printf 'f(x) = x\n# key: %s\n' "$TOK" > "$R/src/conf.jl"
    commit "$R" "ADDED: conf"
    out="$(scan "$R" origin/main..HEAD)"; rc=$?
    ok "$kind token in the range: exit 1" 1 "$rc"
    has "$kind token: reported as a finding to stop on" "$out" '^secret_scan: FINDING\(S\) in origin/main\.\.HEAD — STOP'
    has "$kind token: the rule is named" "$out" 'RuleID:[[:space:]]+(github-pat|aws-access-token)'
    has "$kind token: the file is named" "$out" 'File:[[:space:]]+src/conf\.jl'
    has "$kind token: the line is named" "$out" 'Line:[[:space:]]+[0-9]+'
    ok "$kind token: the output does NOT contain the secret" 0 "$(printf '%s' "$out" | grep -cF "$TOK")"
done

# ---------------------------------------------------------------- the allowlist routes are closed
newtok ghp
R="$W/r4"
mkrepo "$R"
printf 'f(x) = x\nkey = "%s" # gitleaks:allow\n' "$TOK" > "$R/src/conf.jl"
commit "$R" "ADDED: conf"
out="$(scan "$R" origin/main..HEAD)"; rc=$?
ok "a gitleaks:allow comment does not hide it: exit 1" 1 "$rc"
has "a gitleaks:allow comment: still a finding" "$out" 'RuleID:[[:space:]]+github-pat'
fp="$(printf '%s\n' "$out" | sed -n 's/^Fingerprint:[[:space:]]*//p' | head -n 1)"
has "a finding carries a fingerprint (the ignore file below is built from it)" "$fp" ':src/conf\.jl:'

printf '%s\n' "$fp" > "$R/.gitleaksignore"
git -C "$R" add -A
out="$(scan "$R" origin/main..HEAD)"; rc=$?
ok "a .gitleaksignore in the repository is refused: exit 1" 1 "$rc"
has "a .gitleaksignore: named as a config finding" "$out" 'FINDING-CONFIG: .*\.gitleaksignore exists'
rm -f "$R/.gitleaksignore"
printf '[allowlist]\nregexes = ["gh.*"]\n' > "$R/.gitleaks.toml"
out="$(scan "$R" origin/main..HEAD)"; rc=$?
ok "a .gitleaks.toml in the repository is refused: exit 1" 1 "$rc"
rm -f "$R/.gitleaks.toml"

printf 'title = "x"\n[extend]\nuseDefault = true\n[allowlist]\npaths = ["src/conf.jl"]\n' > "$W/wide.toml"
out="$(scan "$R" origin/main..HEAD LOGICKERNEL_GITLEAKS_CONFIG="$W/wide.toml")"; rc=$?
ok "an allowlist in the config is refused: exit 1" 1 "$rc"
has "an allowlist in the config: named" "$out" 'FINDING-CONFIG: .*allowlist/rule/exclusion'
: > "$W/empty.toml"
out="$(scan "$R" origin/main..HEAD LOGICKERNEL_GITLEAKS_CONFIG="$W/empty.toml")"; rc=$?
ok "an empty config is refused: exit 1" 1 "$rc"
# the committed config is the built-in rules only (and passes its own check, with the token above caught)
hasnt "tools/gitleaks.toml: no allowlist, rule, path or regex exclusion" "$(cat "$ROOT/tools/gitleaks.toml")" '^[[:space:]]*(\[+[^]]*(allowlist|rules)|allowlist|paths|regexes|stopwords)'
has "tools/gitleaks.toml: extends the built-in rules" "$(cat "$ROOT/tools/gitleaks.toml")" 'useDefault = true'

# GITLEAKS_* variables would be routes (a baseline file hides findings, ENABLE_RULE narrows the rule set): gitleaks 8.30.1
# ignores them under the flags the scan passes; this case fails the day a release honours one
newtok ghp
R="$W/r5"
mkrepo "$R"
printf 'f(x) = x\nk = "%s"\n' "$TOK" > "$R/src/conf.jl"
commit "$R" "ADDED: conf"
"$BIN" git --no-banner --redact --report-format json --report-path "$W/baseline.json" --exit-code 0 "$R" > /dev/null 2>&1
ok "the baseline file for the case below is non-empty (it holds the finding)" 1 "$(grep -q 'github-pat' "$W/baseline.json" && echo 1 || echo 0)"
out="$(scan "$R" origin/main..HEAD)"; rc=$?
ok "r5 without a variable: exit 1 (so the cases below change only the variable)" 1 "$rc"
out="$(scan "$R" origin/main..HEAD GITLEAKS_BASELINE_PATH="$W/baseline.json")"; rc=$?
ok "GITLEAKS_BASELINE_PATH does not hide the finding: exit 1" 1 "$rc"
has "GITLEAKS_BASELINE_PATH: the finding is reported" "$out" 'RuleID:[[:space:]]+github-pat'
out="$(scan "$R" origin/main..HEAD GITLEAKS_ENABLE_RULE=aws-access-token)"; rc=$?
ok "GITLEAKS_ENABLE_RULE does not narrow the rules: exit 1" 1 "$rc"
has "GITLEAKS_ENABLE_RULE: the finding is reported" "$out" 'RuleID:[[:space:]]+github-pat'

# ---------------------------------------------------------------- the scan fails closed
out="$(scan "$R" nosuchref..HEAD)"; rc=$?
ok "a range that is not one: exit 2" 2 "$rc"
has "a bad range: says so" "$out" 'is not a commit range'
out="$("$SCAN" 2>&1)"; rc=$?
ok "no argument: exit 64" 64 "$rc"
out="$(scan "$W/not_a_repo" origin/main..HEAD)"; rc=$?
ok "not a git repository: exit 2" 2 "$rc"
mkdir -p "$W/fakebin"
printf '#!/usr/bin/env bash\necho "8.30.1"\n' > "$W/fakebin/gitleaks"; chmod +x "$W/fakebin/gitleaks"
out="$(scan "$R" origin/main..HEAD LOGICKERNEL_GITLEAKS="$W/fakebin/gitleaks")"; rc=$?
ok "a binary that is not the pinned one (right version string): exit 3" 3 "$rc"
has "a tampered binary: says so, nothing scanned" "$out" 'does not match the pinned SHA-256.*nothing was scanned'
out="$(scan "$R" origin/main..HEAD LOGICKERNEL_GITLEAKS="$W/nowhere/gitleaks")"; rc=$?
ok "no binary: exit 3" 3 "$rc"
has "no binary: says how to install it" "$out" 'Run: tools/install_gitleaks\.sh'

# ---------------------------------------------------------------- the installer
INS="$ROOT/tools/install_gitleaks.sh"
out="$(LOGICKERNEL_GITLEAKS_BIN_DIR="$(dirname "$BIN")" "$INS" 2>&1)"; rc=$?
ok "installer: the pinned binary is already there: exit 0" 0 "$rc"
has "installer: says the binary SHA-256 matches" "$out" 'already the pinned 8\.30\.1'
mkdir -p "$W/base_bad" "$W/inst"
printf 'not the release\n' > "$W/base_bad/gitleaks_8.30.1_linux_x64.tar.gz"
out="$(LOGICKERNEL_GITLEAKS_BASE="$W/base_bad" LOGICKERNEL_GITLEAKS_BIN_DIR="$W/inst" "$INS" 2>&1)"; rc=$?
ok "installer: an archive with the wrong SHA-256: exit 1" 1 "$rc"
has "installer: says nothing was extracted or installed" "$out" 'NOTHING extracted or installed'
ok "installer: the wrong archive left nothing installed" 0 "$(ls "$W/inst" | wc -l)"
# a wrong archive AND a wrong installed binary: the installer must not call the tampered one 'already installed'
mkdir -p "$W/inst2"; cp "$W/fakebin/gitleaks" "$W/inst2/gitleaks"
out="$(LOGICKERNEL_GITLEAKS_BASE="$W/base_bad" LOGICKERNEL_GITLEAKS_BIN_DIR="$W/inst2" "$INS" 2>&1)"; rc=$?
ok "installer: a tampered installed binary is not accepted: exit 1" 1 "$rc"
mkdir -p "$W/base_none"
out="$(LOGICKERNEL_GITLEAKS_BASE="$W/base_none" LOGICKERNEL_GITLEAKS_BIN_DIR="$W/inst" "$INS" 2>&1)"; rc=$?
ok "installer: no archive at all: exit 1" 1 "$rc"
body="$(grep -v '^ *#' "$INS")"
has "installer: verifies the archive before extracting (check precedes tar)" "$(printf '%s\n' "$body" | grep -nE 'ARCHIVE_SHA256|tar -xzf' | tr '\n' ' ')" 'ARCHIVE_SHA256.*tar -xzf'
hasnt "installer: no sudo, no eval, nothing run from a download directory" "$body" '(^|[ ;|&])(sudo|eval)[ ]|\$D[12]/gitleaks[ "]*(version|git)'

# ---------------------------------------------------------------- tools/prepush.sh: the secret-scan step, the real scan
# A warm.sh stub that passes everything; the throwaway repository is the one prepush runs in.
cat > "$W/warm_stub.sh" <<'EOS'
#!/usr/bin/env bash
echo "$*" >> "$STUB_LOG"
exit 0
EOS
chmod +x "$W/warm_stub.sh"
export STUB_LOG="$W/stub.log"
runpre() {   # runpre DIR STEP — the REAL tools/prepush.sh and the REAL scan, warm.sh stubbed
    : > "$STUB_LOG"
    env LOGICKERNEL_PREPUSH_WARM="$W/warm_stub.sh" LOGICKERNEL_PREPUSH_REPO="$1" LOGICKERNEL_SECRET_SCAN_REPO="$1" "$ROOT/tools/prepush.sh" "$2" 2>&1
}
R="$W/p1"
mkrepo "$R"
printf 'f(x) = x\ng(x) = 3\n' > "$R/src/a.jl"
commit "$R" "ADDED: g"
out="$(runpre "$R" S1)"; rc=$?
ok "prepush with a clean diff: exit 0" 0 "$rc"
has "prepush with a clean diff: the secret-scan step ran and passed" "$out" 'secret_scan: clean — gitleaks 8\.30\.1, 1 commit\(s\) in origin/main\.\.HEAD scanned'
has "prepush with a clean diff: ALL PASSED" "$out" '^prepush: ALL PASSED for S1'

newtok ghp
R="$W/p2"
mkrepo "$R"
printf 'f(x) = x\nk = "%s"\n' "$TOK" > "$R/src/a.jl"
commit "$R" "ADDED: k"
out="$(runpre "$R" S2)"; rc=$?
ok "prepush with a token in the diff: exit 1" 1 "$rc"
has "prepush with a token: stops at the secret scan, named" "$out" '^prepush: FAILED at secret scan'
has "prepush with a token: the finding is shown (rule)" "$out" 'RuleID:[[:space:]]+github-pat'
hasnt "prepush with a token: no ALL PASSED, no next command" "$out" '^prepush: ALL PASSED|^next:'
ok "prepush with a token: the output does NOT contain the secret" 0 "$(printf '%s' "$out" | grep -cF "$TOK")"

# the binary missing: prepush stops BEFORE any warm step (exit 3), like a warm lane that is down
out="$(env LOGICKERNEL_GITLEAKS="$W/nowhere/gitleaks" LOGICKERNEL_PREPUSH_WARM="$W/warm_stub.sh" LOGICKERNEL_PREPUSH_REPO="$W/p1" LOGICKERNEL_SECRET_SCAN_REPO="$W/p1" "$ROOT/tools/prepush.sh" S3 2>&1)"; rc=$?
ok "prepush without the pinned binary: exit 3" 3 "$rc"
has "prepush without the binary: says how to install it" "$out" 'tools/install_gitleaks\.sh'
body="$(grep -v '^ *#' "$ROOT/tools/prepush.sh")"
has "prepush code: calls tools/secret_scan.sh on the merge-base range" "$body" 'secret_scan\.sh'
hasnt "prepush code: no allowlist or ignore option" "$body" 'gitleaksignore|--baseline|--config|gitleaks:allow'

# ---------------------------------------------------------------- the CI job runs the same scan
CI="$ROOT/.github/workflows/CI.yml"
has "CI.yml: a Secret scan job" "$(cat "$CI")" '^  secret-scan:'
has "CI.yml: the job installs the pinned binary then scans" "$(grep -E 'tools/install_gitleaks\.sh|tools/secret_scan\.sh' "$CI" | tr '\n' ' ')" 'install_gitleaks\.sh.*secret_scan\.sh'
has "CI.yml: tools/test_secret_scan.sh in the light shard" "$(cat "$CI")" 'run: tools/test_secret_scan\.sh'

echo "tools/test_secret_scan.sh: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
