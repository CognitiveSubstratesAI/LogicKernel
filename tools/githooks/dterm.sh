# tools/githooks/dterm.sh — the ONE definition of the D-0164 term grep (audit D-0164, D-0650 item 2).
# SOURCED, never executed, by tools/githooks/pre-push (the ci/<name> arm, rule 7) and tools/prepush.sh (step 6):
# both run   ... | d0164_filter | grep -iE "$TERMS164"   so the two greps cannot drift apart.
#
#   TERMS164      the strong terms (case-insensitive, matched as substrings: D-0164's six, plus five words added by D-0652 item 1).
#   D0164_ALLOW   the EXACT-TOKEN ALLOWLIST: upstream identifiers and two phrases that contain a strong term
#                 only as a substring of an ordinary name/word. Reviewed once (D-0650 item 1); adding a token is a
#                 reviewed change to THIS file, with a row in tools/test_dterm.sh.
#   d0164_filter  stdin -> stdout, line for line: every occurrence of an allowlisted token is deleted when it is a
#                 WHOLE token — the character before it and the character after it are not [A-Za-z0-9_] (or the
#                 line begins/ends there). A token with an identifier character glued to it (a longer name that
#                 merely contains it) keeps its text, so it still matches the strong terms (rows in tools/test_dterm.sh).
#                 The allowlist is matched exactly (case-sensitively); the strong-term match after it is -i.
#                 One guard (D0164_GUARD, below) keeps `ABOed` + ' run' + a word character refusing, although the
#                 token `ABOed` is allowlisted beside the phrase 'ABOed run' (audit D-0656 item 1).
#                 A line that holds a strong term OUTSIDE every allowlisted token still matches, whatever
#                 allowlisted tokens stand beside it.
#
# This file is assembled from pieces ('abo''rt'), so that it does not match its own grep.
TERMS164='seg''ment|SIG''SEGV|cra''sh|abo''rt|invalid term''_t|dies ''of|seg''fault|use-after''-free|heap-buf''fer|double ''free|memory cor''ruption'
D0164_ALLOW=(
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

# FAIL CLOSED (audit D-0652 item 1). A filter that emits nothing would pass every line to "no hit": a silent
# refusal-bypass. So d0164_filter PROVES ITSELF on every call, before it touches the stream: the probe line holds an
# allowlisted token next to a strong term; the output must be exactly the line with the token deleted and the strong
# term intact. If `sed` is missing, exits non-zero, emits nothing, or does anything else to the probe, the filter
# prints D0164_SENTINEL (a line that holds a strong term, so the caller's   | grep -iE "$TERMS164"   matches and the
# push is refused, with the reason in the refusal text) and drops the stream. The same sentinel follows the real
# stream when `sed` exits non-zero on it. The pipeline's status is the LAST stage's, so a non-zero status could not
# carry the refusal: the sentinel line does.
D0164_SENTINEL='D-0164 filter unavailable (sed -E missing or broken): the term check cannot run, the push is refused (abo''rt by design)'

# THE `ABOed` GUARD (audit D-0656 item 1: the token is ADDED beside the phrase 'ABOed run', not substituted).
# (ABO = the first strong term of D-0164, spelled in pieces in the code; this comment must not match its own grep.)
# The token alone would delete `ABOed` inside `ABOed run9`, `ABOed runy` and `ABOed run_`, texts the phrase entry
# alone refuses (the phrase needs a non-word character after `run`); that would be a loosening. So BEFORE the token
# entries run, `ABOed` followed by ' run' and a word character is rewritten to `ABO_ed` (still holding a strong
# term, so the text still matches; `_` is a word character, so no allowlisted token can delete it: `prolog:ABO_ed`
# is not the token `prolog:ABO`). Any other `ABOed` stays a token like the rest. Applied inside the loop.
D0164_GUARD='s/abo''rted( run[A-Za-z0-9_])/abo''rt_ed\1/g'

# d0164_prog — print the sed program for D0164_ALLOW (nothing, and a non-zero status, when sed fails)
d0164_prog() {
    local t esc prog=":a;$D0164_GUARD"
    for t in "${D0164_ALLOW[@]}"; do
        esc="$(printf '%s' "$t" | sed 's/[][\.*^$(){}?+|/]/\\&/g')" || return 1
        [ -n "$esc" ] || return 1
        prog+=";s/(^|[^A-Za-z0-9_])${esc}([^A-Za-z0-9_]|\$)/\\1\\2/g"
    done
    prog+=';ta'
    printf '%s' "$prog"
}

# d0164_filter — see the header. Boundaries are consumed and put back (\1\2), and the substitution loops until
# nothing changes, so two allowlisted tokens separated by one character are both deleted.
d0164_filter() {
    local prog probe_in probe_out
    probe_in="0 ${D0164_ALLOW[0]} SEG""MENT 0"        # token, a space, a strong term (upper case: the match is -i)
    prog="$(d0164_prog)" && [ -n "$prog" ] &&
        probe_out="$(printf '%s\n' "$probe_in" | sed -E "$prog")" &&
        [ "$probe_out" = "0  SEG""MENT 0" ] || {
        printf '%s\n' "$D0164_SENTINEL"
        while IFS= read -r _; do :; done              # drain the stream (no SIGPIPE upstream)
        return 0
    }
    sed -E "$prog" || printf '%s\n' "$D0164_SENTINEL"
}
