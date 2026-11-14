#!/usr/bin/env bash
# ORIGINAL: no swipl-devel counterpart — the rows of the D-0164 term grep's EXACT-TOKEN ALLOWLIST (audit D-0650
# item 2): tools/githooks/dterm.sh holds the ONE definition (TERMS164, D0164_ALLOW, d0164_filter) that the pre-push
# hook's ci/ arm and tools/prepush.sh step 6 both run as   ... | d0164_filter | grep -iE "$TERMS164".
#
#   tools/test_dterm.sh        exit 0 only if every row passes; nothing is pushed, no repository is touched.
#
# THE ROWS. (1) the reviewed list is pinned (spec = D-0650 item 1) and every entry still contains a strong term
# (an entry that needs no allowlisting is dead weight); (2) each allowlisted token passes alone and in context —
# and each such row first checks that the UNFILTERED text DOES match (a pass row that could not fail proves
# nothing); (3) each strong term outside the list refuses; (4) a strong term next to an allowlisted token on the
# same line refuses; (5) the strong match is case-insensitive, the allowlist is exact; (6) whole token, not
# substring: an identifier character glued to either end keeps the text; (7) the two call sites carry the SAME
# pipeline (filter first, then the match) and define no term list of their own.
# (6b) the `ABOed` token is ADDED beside the phrase 'ABOed run' (audit D-0656 item 1); the guard in dterm.sh keeps the three
# glued-after rows of the phrase refusing.
# (8) FAIL CLOSED (audit D-0652 item 1): with `sed` missing from PATH, or a `sed` that emits nothing, exits 1, is the identity
# or fails on the real stream, the pipeline  ... | d0164_filter | grep -iE "$TERMS164"  prints the sentinel line, so the caller
# refuses; a working `sed` in a restricted PATH still passes the normal rows.
# D-0652 item 1 (Q4): TERMS164 is D-0164's six terms plus five more words (rows "P4-*", assembled from pieces like every
# term here; they were the rows "gap-*" that passed before).
#
# SEAM: LOGICKERNEL_DTERM_TOOLS=<a copy of tools/> (githooks/dterm.sh, githooks/pre-push, prepush.sh are read from
# it): the mutation proof runs this very file against hand-broken copies (evidence/HOOKTERM1/mutation_proof.sh).
# The strong terms below are assembled from pieces so that this file does not match the grep it tests.
set -uo pipefail
TOOLS="${LOGICKERNEL_DTERM_TOOLS:-$(cd "$(dirname "$0")" && pwd)}"
[ -f "$TOOLS/githooks/dterm.sh" ] || { echo "test_dterm: no $TOOLS/githooks/dterm.sh: nothing was tested"; exit 3; }
# shellcheck source=/dev/null
. "$TOOLS/githooks/dterm.sh"
SEG='seg''ment'; SIGS='SIG''SEGV'; CRA='cra''sh'; ABO='abo''rt'; INV='invalid term''_t'; DIE='dies ''of'
pass=0 fail=0

ok() { pass=$((pass + 1)); echo "  ok   $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL $1"; shift; printf '       %s\n' "$@"; }
# hits TEXT — the lines of TEXT that still match after the filter (what the grep of the hook would print)
hits() { printf '%s\n' "$1" | d0164_filter | grep -iE "$TERMS164"; }
raw() { printf '%s\n' "$1" | grep -iE "$TERMS164"; }
# allowed LABEL TEXT — the text matches the strong terms UNFILTERED and not after the filter
allowed() {
    if ! raw "$2" > /dev/null; then bad "$1: the row is vacuous, the raw text holds no strong term" "text: $2"
    elif h="$(hits "$2")"; then bad "$1" "still a hit: $h" "text: $2"
    else ok "$1"; fi
}
# refused LABEL TEXT — the text still matches after the filter
refused() {
    if hits "$2" > /dev/null; then ok "$1"; else bad "$1: NOT refused" "text: $2"; fi
}
# clean LABEL TEXT — no match at all, raw or filtered
clean() {
    if raw "$2" > /dev/null || hits "$2" > /dev/null; then bad "$1: matched" "text: $2"; else ok "$1"; fi
}

# --- 1. the reviewed list ------------------------------------------------------------------------------------
SPEC=(
    'sigCra''shHandler'
    'SIGH_CRA''SH'
    'SIG_PLABO''RT'
    'SIGH_ABO''RT'
    'abo''rt_handler'
    'prolog:abo''rt'
    'unwind(abo''rt)'
    'abo''rt/0'
    'bodies ''of'
    'abo''rted run'
    'abo''rted'
    '"abo''rt"'
)
SPEC_N=12
if [ "${#D0164_ALLOW[@]}" = "${#SPEC[@]}" ] && [ "${#SPEC[@]}" = "$SPEC_N" ] && [ "${D0164_ALLOW[*]}" = "${SPEC[*]}" ]; then
    ok "the allowlist is the reviewed list of D-0650 item 1 ($SPEC_N tokens, in order)"
else bad "the allowlist differs from the reviewed list" "has ${#D0164_ALLOW[@]}: ${D0164_ALLOW[*]}"; fi
for t in "${D0164_ALLOW[@]}"; do
    raw "$t" > /dev/null && ok "entry '$t' contains a strong term (it needs the allowlist)" || bad "entry '$t' contains no strong term: dead weight"
done

# --- 2. each allowlisted token passes alone and in context ---------------------------------------------------
for t in "${D0164_ALLOW[@]}"; do
    allowed "pass alone: $t" "$t"
    allowed "pass in a sentence: $t" "see $t here"
    allowed "pass at line start: $t" "$t is named upstream"
    allowed "pass at line end: $t" "named upstream: $t"
    allowed "pass parenthesised: $t" "($t)"
    allowed "pass quoted: $t" "\"$t\""
    allowed "pass after a colon, before a comma: $t" "mk_sym(T, :$t), x"
    allowed "pass after a dot, before a paren: $t" "LK.$t(x)"
    allowed "pass between hyphens: $t" "a-$t-b"
    allowed "pass twice on a line: $t" "$t $t"
    allowed "pass in a markdown table cell: $t" "| \`$t\` | since X |"
done
for i in $(seq 0 $((${#D0164_ALLOW[@]} - 2))); do
    allowed "pass, two different tokens one space apart: ${D0164_ALLOW[$i]} / ${D0164_ALLOW[$((i + 1))]}" "${D0164_ALLOW[$i]} ${D0164_ALLOW[$((i + 1))]}"
done
allowed "pass, all tokens on one line" "${D0164_ALLOW[*]}"
allowed "the goal abort/0 as a whole token, end of a clause" "call ${ABO}/0."
allowed "the phrase in prose" "the ${D0164_ALLOW[8]} the clauses"
allowed "the phrase of an interrupted run" "(can only fail on an ${D0164_ALLOW[9]}, has no twin)"

# --- 3. each strong term outside the list refuses ------------------------------------------------------------
refused "strong: $SEG" "the $SEG of the stack"
refused "strong: $SIGS" "got $SIGS in the walk"
refused "strong: $CRA (bare)" "this $CRA"
refused "strong: ${CRA}es swipl" "${CRA}es swipl"
refused "strong: ${CRA}ed upstream" "${CRA}ed upstream"
refused "strong: ${CRA}es the pin" "${CRA}es the pin"
refused "strong: $ABO (bare)" "the $ABO of the run"
refused "strong: ${ABO}/1" "${ABO}/1"
refused "strong: ${ABO}_handlers (a longer name)" "${ABO}_handlers"
allowed "the upstream IDG field (P1): ${ABO}ed alone is an allowlisted whole token" "it ${ABO}ed"
refused "strong: ${ABO}edly (a longer word)" "it ${ABO}edly"
allowed "the quoted data literal (P2): \"${ABO}\" with its double quotes" "x = \"${ABO}\"."
refused "strong: the bare word next to a quoted one" "\"${ABO}\" and the ${ABO}"
refused "strong: $INV" "an $INV was seen"
refused "strong: $DIE" "the process $DIE a bad pointer"
refused "strong: a name that holds a term: my_${CRA}_site" "my_${CRA}_site(x)"
# D-0652 (P4): the five words D-0164 did not name, now in TERMS164 (they were the rows "gap-*" that passed)
refused "P4-1: a seg""fault word" "a seg""fault in the walk"
refused "P4-2: use-after""-free" "a use-after""-free in the walk"
refused "P4-3: heap-buf""fer" "heap-buf""fer overflow"
refused "P4-4: double ""free" "a double ""free"
refused "P4-5: memory cor""ruption" "memory cor""ruption"
clean "a clean line passes" "f(x) = x + 1 # an ordinary line"
clean "the empty line passes" ""

# --- 4. a strong term NEXT TO an allowlisted token refuses ---------------------------------------------------
for t in "${D0164_ALLOW[@]}"; do
    refused "term before: $SEG $t" "$SEG $t"
    refused "term after: $t $CRA" "$t $CRA"
    refused "term after a comma: $t, $SIGS" "$t, $SIGS"
    refused "term joined by a hyphen: $CRA-$t" "$CRA-$t"
    refused "term on both sides: $INV $t $DIE" "$INV $t $DIE"
    refused "term in the same word list: $t and the $ABO" "$t and the $ABO"
done

# --- 5. case: the strong match is -i, the allowlist is exact -------------------------------------------------
refused "case: upper $SEG" "${SEG^^}"
refused "case: Capital $CRA" "${CRA^}"
refused "case: lower $SIGS" "${SIGS,,}"
refused "case: upper $ABO" "${ABO^^}"
refused "case: mixed $DIE" "Dies ""Of"
refused "case: upper $INV" "${INV^^}"
refused "case: upper ${ABO}/0 is not the allowlisted goal" "${ABO^^}/0"
refused "case: Capital ${ABO}/0" "${ABO^}/0"
refused "case: upper-case spelling of the first token (a different token)" "SIG${CRA^^}HANDLER"
refused "case: lower-case spelling of the second token (a different token)" "sigh_$CRA"
refused "case: upper-case spelling of the phrase" "BODIES ""OF"
refused "case: capitalised phrase (the list is exact)" "Bodies ""of"

# --- 6. whole token, not substring ---------------------------------------------------------------------------
for t in "${D0164_ALLOW[@]}"; do
    refused "glued before: x$t" "x$t"
    refused "glued after: ${t}y" "${t}y"
    refused "glued both sides: x${t}y" "x${t}y"
    refused "underscore before: _$t" "_$t"
    refused "underscore after: ${t}_" "${t}_"
    refused "digit after: ${t}9" "${t}9"
done
refused "the goal with a glued letter is not the goal" "${ABO}/0x"
refused "the goal with a second digit is not the goal" "${ABO}/00"
refused "a token beside a glued one: the glued one stays" "${D0164_ALLOW[0]} x${D0164_ALLOW[0]}y"

# --- 6b. the `ABOed` ADD variant (audit D-0656 item 1: token ADDED beside the phrase, list not shortened) -------
# The phrase entry and the token entry are BOTH on the list (entries 9 and 10). A pure add would let the token delete
# `ABOed` inside `ABOed run9` (the phrase refuses those): d0164_filter carries D0164_GUARD (see dterm.sh) so the
# three "glued after" rows of the phrase still refuse. Each row below is named for that decision.
ABR="${ABO}ed run"
[ "${D0164_ALLOW[9]}" = "$ABR" ] && [ "${D0164_ALLOW[10]}" = "${ABO}ed" ] && ok "D-0656: the phrase entry AND the token entry are both on the list (add, not substitute)" || bad "D-0656: entries 9/10 are not the phrase and the token" "9: ${D0164_ALLOW[9]}  10: ${D0164_ALLOW[10]}"
allowed "D-0656: the phrase passes (its own boundary)" "an $ABR."
allowed "D-0656: the token alone passes" "the field ${ABO}ed is set"
allowed "D-0656: the token before a word that is not 'run'" "${ABO}ed twice"
allowed "D-0656: the token before 'run' preceded by a second space" "${ABO}ed  run9"
allowed "D-0656: the token twice" "${ABO}ed ${ABO}ed"
allowed "D-0656: the phrase followed by a space and a word" "${ABR} run9"
allowed "D-0656: the phrase at line end" "${ABR}"
refused "D-0656 glued after: ${ABR}y" "${ABR}y"
refused "D-0656 underscore after: ${ABR}_" "${ABR}_"
refused "D-0656 digit after: ${ABR}9" "${ABR}9"
refused "D-0656 glued after, upper-case letter: ${ABR}Y" "${ABR}Y"
refused "D-0656 glued after, inside a sentence" "the ${ABR}9 was set"
refused "D-0656 glued after, then the token alone (the line still refuses)" "${ABR}9 ${ABO}ed"
refused "D-0656 glued after, then the phrase (the line still refuses)" "${ABR}9 and ${ABR}"
refused "D-0656 glued after, behind a colon: the guard marker is not deleted by the token prolog:${ABO}" "prolog:${ABR}9"
refused "D-0656 glued before the token: x${ABO}ed" "x${ABO}ed"
refused "D-0656 the token glued after: ${ABO}edy" "${ABO}edy"
refused "D-0656 the token followed by an underscore: ${ABO}ed_" "${ABO}ed_"
refused "D-0656 the token followed by a digit: ${ABO}ed9" "${ABO}ed9"
refused "D-0656 the token in a longer word: ${ABO}edly" "${ABO}edly"
refused "D-0656 a strong term next to the token" "${ABO}ed $CRA"
# the guard step is part of the program the probe validates (a broken guard changes nothing on the probe line, so it
# is its own row): the program text carries the guard, ahead of the first token entry
case "$(d0164_prog)" in ":a;${D0164_GUARD};"*) ok "D-0656: the sed program starts with the guard step";; *) bad "D-0656: the sed program does not start with the guard step";; esac

# --- 7. the two call sites run one pipeline ------------------------------------------------------------------
FRAG='d0164_filter | grep -iE "$TERMS164"'
for f in "githooks/pre-push" "prepush.sh"; do
    [ -f "$TOOLS/$f" ] || { bad "call site $f is missing"; continue; }
    n="$(grep -cF -- "$FRAG" "$TOOLS/$f")"
    m="$(grep -c -- '"\$TERMS164"' "$TOOLS/$f")"
    [ "$n" = 2 ] && ok "$f: two greps run the filter first, then -i (found $n)" || bad "$f: expected 2 of the pipeline '$FRAG', found $n"
    [ "$n" -gt 0 ] && [ "$m" = "$n" ] && ok "$f: no grep of \$TERMS164 outside the filtered pipeline" || bad "$f: $m uses of \$TERMS164, $n filtered"
    grep -qE '^[[:space:]]*TERMS164=' "$TOOLS/$f" && bad "$f defines a TERMS164 of its own (drift)" || ok "$f defines no term list of its own"
    grep -qF 'githooks/dterm.sh' "$TOOLS/$f" && ok "$f sources githooks/dterm.sh" || bad "$f does not source githooks/dterm.sh"
done
c="$(grep -cE '^TERMS164=' "$TOOLS/githooks/dterm.sh")"
[ "$c" = 1 ] && ok "dterm.sh defines TERMS164 once" || bad "dterm.sh defines TERMS164 $c times"
# the terms themselves are D-0164's six, unchanged
[ "$TERMS164" = "$SEG|$SIGS|$CRA|$ABO|$INV|$DIE|seg""fault|use-after""-free|heap-buf""fer|double ""free|memory cor""ruption" ] && ok "TERMS164 is D-0164's six terms plus the five of D-0652 (P4)" || bad "TERMS164 changed" "$TERMS164"

# --- 8. FAIL CLOSED (audit D-0652 item 1): a broken or missing `sed` makes the CALLER refuse -----------------------
# A filter that emits nothing is a silent refusal-bypass. Each row runs the very pipeline of the call sites
#   printf TEXT | d0164_filter | grep -iE "$TERMS164"
# in a child shell whose PATH holds ONLY the named tools (grep, cat, and sed: real, absent or a fake), and requires a
# refusal (the pipeline prints a line) for text that holds NO strong term and for text that holds only an
# allowlisted token: the cases that a broken filter would let through.
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/dterm_failclosed.XXXXXX")" || { echo "test_dterm: no scratch dir"; exit 3; }
trap 'rm -rf "$SCRATCH"' EXIT
REAL_SED="$(command -v sed)"; REAL_GREP="$(command -v grep)"; REAL_CAT="$(command -v cat)"
mkbin() {  # mkbin NAME — a PATH dir holding grep and cat only
    local d="$SCRATCH/$1"; mkdir -p "$d" && ln -s "$REAL_GREP" "$d/grep" && ln -s "$REAL_CAT" "$d/cat" && printf '%s' "$d"
}
fake() {  # fake NAME BODY — a PATH dir with grep and a `sed` script with BODY ($REAL_SED is exported to it)
    local d; d="$(mkbin "$1")" && printf '#!/bin/sh\n%s\n' "$2" > "$d/sed" && chmod +x "$d/sed" && printf '%s' "$d"
}
export REAL_SED
# piped DIR TEXT — what the call sites' pipeline prints with PATH=DIR
piped() { local d="$1"; shift; PATH="$d" "$BASH" -c '. "$1"; shift; printf "%s\n" "$@" | d0164_filter | grep -iE "$TERMS164"' _ "$TOOLS/githooks/dterm.sh" "$@" 2>/dev/null; }
CLEANLINE="f(x) = x + 1 # an ordinary line"
ALLOWLINE="see ${D0164_ALLOW[0]} here"
fc_refused() {  # fc_refused LABEL DIR — clean text, allowlisted-only text and an empty line all refuse
    local l="$1" d="$2" o
    for txt in "$CLEANLINE" "$ALLOWLINE" ""; do
        if o="$(piped "$d" "$txt")" && [ -n "$o" ]; then ok "$l: refused for '${txt:0:24}'"; else bad "$l: NOT refused for '$txt'" "output: $o"; fi
    done
    o="$(piped "$d" "$CLEANLINE")"
    case "$o" in *"filter unavailable"*) ok "$l: the refusal says why (filter unavailable)";; *) bad "$l: the refusal text does not say why" "output: $o";; esac
}
BIN_REAL="$(mkbin real)"; ln -s "$REAL_SED" "$BIN_REAL/sed"
BIN_NONE="$(mkbin nosed)"
fc_refused "sed missing from PATH" "$BIN_NONE"
fc_refused "fake sed emits nothing, exit 0" "$(fake sed_silent 'cat > /dev/null; exit 0')"
fc_refused "fake sed emits nothing, exit 1" "$(fake sed_exit1 'cat > /dev/null; exit 1')"
fc_refused "fake sed exits 1 with no input read" "$(fake sed_exit1b 'exit 1')"
fc_refused "fake sed is the identity (the token is not removed)" "$(fake sed_identity 'cat')"
fc_refused "fake sed blanks every line" "$(fake sed_blank 'while IFS= read -r l; do echo; done')"
fc_refused "fake sed blanks the token-escape step (the plain sed call) and runs real sed for -E" "$(fake sed_noesc 'if [ "$1" = -E ]; then exec "$REAL_SED" "$@"; fi; echo; exit 0')"
# real sed in a restricted PATH: the normal case still works (and proves the harness)
if [ -z "$(piped "$BIN_REAL" "$CLEANLINE")" ]; then ok "real sed, restricted PATH: a clean line passes"; else bad "real sed, restricted PATH: a clean line is refused"; fi
if [ -z "$(piped "$BIN_REAL" "$ALLOWLINE")" ]; then ok "real sed, restricted PATH: an allowlisted token passes"; else bad "real sed, restricted PATH: an allowlisted token is refused"; fi
if [ -z "$(piped "$BIN_REAL" "")" ]; then ok "real sed, restricted PATH: an empty line passes"; else bad "real sed, restricted PATH: an empty line is refused"; fi
o="$(piped "$BIN_REAL" "the $SEG of it")"; [ -n "$o" ] && ok "real sed, restricted PATH: a strong term refuses" || bad "real sed, restricted PATH: a strong term passes"
case "$o" in *"filter unavailable"*) bad "real sed: the sentinel was printed on a working filter";; *) ok "real sed: no sentinel on a working filter";; esac
# a sed that works for the probe but fails on the real stream (exit 1 after its output): the sentinel follows
BIN_LATE="$(fake sed_late 'if [ "$1" = -E ]; then t="$(cat)"; printf "%s\n" "$t" | "$REAL_SED" "$@"; case "$t" in *TRIGGER*) exit 1;; esac; exit 0; fi; exec "$REAL_SED" "$@"')"
o="$(piped "$BIN_LATE" "TRIGGER $CLEANLINE")"
case "$o" in *"filter unavailable"*) ok "sed that fails on the real stream: refused";; *) bad "sed that fails on the real stream: NOT refused" "output: $o";; esac
[ -z "$(piped "$BIN_LATE" "$CLEANLINE")" ] && ok "the same fake sed on a stream without the trigger passes (the row above is the exit status)" || bad "the late-fail fake refuses a stream without the trigger"
# the sentinel: holds a strong term (so the callers' grep matches it), is one line, comes once
if raw "$D0164_SENTINEL" > /dev/null; then ok "the sentinel matches TERMS164"; else bad "the sentinel does not match TERMS164: a silent pass"; fi
case "$D0164_SENTINEL" in *"filter unavailable"*) ok "the sentinel names the cause";; *) bad "the sentinel does not name the cause";; esac
n="$(piped "$BIN_NONE" "$CLEANLINE" "$CLEANLINE" "$CLEANLINE" | wc -l)"
[ "$n" = 1 ] && ok "a three-line stream with sed missing: one sentinel line (the stream is drained)" || bad "sentinel lines for a three-line stream: $n"
# the call sites' captured form:   x="$(... | d0164_filter | grep -iE ...)"   is non-empty on a broken sed
x="$(PATH="$BIN_NONE" "$BASH" -c '. "$1"; x="$(printf "%s\n" "$2" | d0164_filter | grep -iE "$TERMS164")"; [ -n "$x" ] && echo REFUSED' _ "$TOOLS/githooks/dterm.sh" "$CLEANLINE" 2>/dev/null)"
[ "$x" = REFUSED ] && ok "the call sites' captured form is non-empty with sed missing" || bad "the captured form is empty with sed missing"

echo "test_dterm: $pass ok, $fail failed"
[ "$fail" = 0 ] && [ "$pass" -gt 0 ]
