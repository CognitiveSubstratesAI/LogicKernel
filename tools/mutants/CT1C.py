# ORIGINAL: CT1c's mutant list (downcase_atom/2, upcase_atom/2, string_lower/2, string_upper/2, normalize_space/2 and enc_from_locale of pl-ctype.c); its counterpart is the port itself.
# tools/mutants/CT1C.py — the mutation battery of CT1c, run ONCE, in CI (.github/workflows/mutation.yml). Format: tools/mutate_drive.py's
# (as CT1B.py): `id`, `file`, `old` (must occur EXACTLY once in its file), `new`, optional `equivalent` and `targets`.
# Killed by test/core_text/test_ctype_text_swipl.jl (rows t0-t33 of test_ctype_text_swipl.pl, named in each id's KILL; the C ids by its
# enc_from_locale testset). Verdicts: written by the battery, not yet run; every `old` was checked to occur exactly once in its file at the
# lane-E worktree (a text count, no Julia, UNTESTED code). The `old` strings are in the repo's formatted style BEFORE `tools/warm.sh fmt`:
# RE-FIT any that fmt rewraps.
# CT1c-A8, B1 and B2 make write_normalize_space's `while i < end_` loop stop advancing (src/os/pl-ctype-pred.jl:660-662), each pass writes a space to the
# output redirect: an unbounded loop that grows memory (rss 5.6-6.7 GB at 107-154 s, ENGINE-CAT-FIX); the kill rows t0/t1/t19/t24 are normalize_space rows,
# so the mutant never FAILS one of them, it hangs. They declare `expect="hang"` with the site `write_normalize_space` (audit D-0935 (2), fallback of the
# CT1c watchdog: no test-side watchdog row is built; D-0918 (2)(e)). MEASURED (ENGINE-R2D-BUILD-2, evidence/R2/engine_r2d_handoff.md): under
# MUTATE_CI_MEM_MB=2400 and a 300 s limit the site is NOT shown: the stack at the cut is the JIT compile of test_ctype_text_swipl.jl's own top level
# (LLVM passes; no write_normalize_space frame), because that file's compile alone passes 2400 MB (the UNMUTATED baseline is cut at rss 2430 MB at
# second 502) and runs past 300 s before it executes a row. So the verdict stays `TIMEOUT (hang declared, site not shown)` (blocking) at those settings;
# a cut after the file's compile needs a larger cap and limit. (A8 alone, on a pre-compiled tree, is `caught` by the second target, test_char_type_swipl.jl:168.)
# NOT LISTED (each with its reason):
#   * `init_locale`: written, not called at boot and not a predicate; no test reaches it (it reads and sets the process locale).
#   * `discardOutputRedirect(ld, ctx)` (the failure path of normalize_space/2): the row's failing call leaves no visible state, so a removal is
#     not observable through the rows (equivalent for them).
#   * `tin === nothing && return FFALSE` (modify_case_atom): `PL_get_text` has already raised; a changed return value is the caller's.
#   * `while i < end_` as `i <= end_`: an endless loop, which the battery's time-out would count as killed without evidence.
# TARGETS (audit D-0238): no other test file calls these predicates (`git grep` over test/: only the manifest names them); the char_type test
# is listed for the case maps (`ftolower`, `ftoupper`) both files share.
TS = [
    "test/core_text/test_ctype_text_swipl.jl",
    "test/core_text/test_char_type_swipl.jl",
]
TARGETS = TS
P = "src/os/pl-ctype-pred.jl"
MUTANTS = [
    dict(id="CT1c-A1 the length test of the output bound is dropped: `ci == co` becomes true at the first end (KILL t8: downcase_atom('AB', abc))",
         file=P, targets=TS,
         old='(ci == -1 || co == -1) && return ci == co ? FTRUE : FFALSE',
         new='(ci == -1 || co == -1) && return FTRUE'),
    dict(id="CT1c-A2 downcase compares with the upper-case map (KILL t8)",
         file=P, targets=TS,
         old='co != ftolower(ci) && return FFALSE',
         new='co != ftoupper(ci) && return FFALSE'),
    dict(id="CT1c-A3 upcase compares with the lower-case map (KILL t8)",
         file=P, targets=TS,
         old='co != ftoupper(ci) && return FFALSE',
         new='co != ftolower(ci) && return FFALSE'),
    dict(id="CT1c-A4 the unbound output is built with the opposite map (KILL t0, t1, t2, t3)",
         file=P, targets=TS,
         old='utf8_put_char(bytes, down ? ftolower(c) : ftoupper(c))',
         new='utf8_put_char(bytes, down ? ftoupper(c) : ftolower(c))'),
    dict(id="CT1c-A5 the type error names the other type (KILL t13, t14: type_error(string, f(x)))",
         file=P, targets=TS,
         old='text_type == PL_STRING ? :string : :atom',
         new='text_type == PL_STRING ? :atom : :string'),
    dict(id="CT1c-A6 the unbound-output branch tests the input (KILL t0: an atomic input is never a variable)",
         file=P, targets=TS,
         old='elseif PL_is_variable(ld, out)',
         new='elseif PL_is_variable(ld, in_)'),
    dict(id="CT1c-A7 the result text is built with the wrong length (KILL t0, t9: multi-character texts)",
         file=P, targets=TS,
         old='res = PL_chars_t(bytes, length(cin), ENC_UTF8, false)',
         new='res = PL_chars_t(bytes, length(cin) + 1, ENC_UTF8, false)',
         equivalent="src/os/pl-ctype-pred.jl:568 builds the result text with length(cin) as the length argument; src/os/pl-text.jl:281 and :290 (PL_canonicalise_text, ENC_UTF8 branch) overwrite text.length from the bytes before any read, for PL_ATOM and PL_STRING, the only text types that arrive (35 and 32 of 67 reaches), so the passed length is dead and +1 changes nothing; accepted D-0919 (counters: reached 67, diverged 0, list diverged 0)"),
    dict(id="CT1c-A8 get_chr_from_text ends one character early (KILL t0, t1)",
         file=P, targets=TS,
         old='index > length(cps) && return (-1, index)',
         new='index >= length(cps) && return (-1, index)',
         expect="hang", site="write_normalize_space"),
    dict(id="CT1c-A9 get_chr_from_text skips a character (KILL t0, t19)",
         file=P, targets=TS,
         old='return (cps[index], index + 1)',
         new='return (cps[index], index + 2)'),
    dict(id="CT1c-A10 downcase_atom/2 upcases (KILL t0)",
         file=P, targets=TS,
         old='return modify_case_atom(ld, PL__t0, PL__t0 + 1, true, PL_ATOM)',
         new='return modify_case_atom(ld, PL__t0, PL__t0 + 1, false, PL_ATOM)'),
    dict(id="CT1c-A11 upcase_atom/2 downcases (KILL t1)",
         file=P, targets=TS,
         old='return modify_case_atom(ld, PL__t0, PL__t0 + 1, false, PL_ATOM)',
         new='return modify_case_atom(ld, PL__t0, PL__t0 + 1, true, PL_ATOM)'),
    dict(id="CT1c-A12 string_lower/2 answers an atom (KILL t2, t6)",
         file=P, targets=TS,
         old='return modify_case_atom(ld, PL__t0, PL__t0 + 1, true, PL_STRING)',
         new='return modify_case_atom(ld, PL__t0, PL__t0 + 1, true, PL_ATOM)'),
    dict(id="CT1c-A13 string_upper/2 answers an atom (KILL t3, t7)",
         file=P, targets=TS,
         old='return modify_case_atom(ld, PL__t0, PL__t0 + 1, false, PL_STRING)',
         new='return modify_case_atom(ld, PL__t0, PL__t0 + 1, false, PL_ATOM)'),
    dict(id="CT1c-B1 skip_separators stops at white space (KILL t19, t24)",
         file=P, targets=TS,
         old='        if f_is_space(c)\n            i = at',
         new='        if !f_is_space(c)\n            i = at',
         expect="hang", site="write_normalize_space"),
    dict(id="CT1c-B2 copy_non_separators copies the white space instead (KILL t19)",
         file=P, targets=TS,
         old='        if !f_is_space(c)\n            i = at',
         new='        if f_is_space(c)\n            i = at',
         expect="hang", site="write_normalize_space"),
    dict(id="CT1c-B3 the word loop stops one character early (KILL t19: the one-character input `a`)",
         file=P, targets=TS,
         old='    while i < end_\n',
         new='    while i < end_ - 1\n'),
    dict(id="CT1c-B4 a space is written after the last word (KILL t19, t20, t21)",
         file=P, targets=TS,
         old='        if i < end_\n',
         new='        if i <= end_\n'),
    dict(id="CT1c-B5 the separator written is not a space (KILL t19, t21, t22, t31, t32)",
         file=P, targets=TS,
         old="Sputcode(Int(' '), out) < 0 && return false",
         new="Sputcode(Int('_'), out) < 0 && return false"),
    dict(id="CT1c-B6 the end of the text is one character early (KILL t19, t21)",
         file=P, targets=TS,
         old='end_ = length(cps) + 1',
         new='end_ = length(cps)'),
    dict(id="CT1c-B7 the output is never closed into the term (KILL t19, t20, t21, t22)",
         file=P, targets=TS,
         old='            rc = closeOutputRedirect(ld, ctx)',
         new='            rc = true'),
    dict(id="CT1c-B8 the input is read as a non-text (KILL t26: type_error(string, f(x)))",
         file=P, targets=TS,
         old='tin = PL_get_text(ld, in_, CVT_ATOMIC | CVT_EXCEPTION)\n    tin === nothing && return false',
         new='tin = PL_get_text(ld, in_, CVT_ATOMIC)\n    tin === nothing && return false'),
    dict(id="CT1c-C1 enc_from_locale matches the other codesets (KILL the unit test: `x.iso_8859_1`, `en_US.UTF-8`)",
         file=P, targets=TS,
         old='lowercase(ext) == lowercase(name) && return encoding',
         new='lowercase(ext) != lowercase(name) && return encoding'),
    dict(id="CT1c-C2 a codeset not in the map is UTF-8 (KILL the unit test: `C`)",
         file=P, targets=TS,
         old='return ENC_ANSI ',
         new='return ENC_UTF8 '),
    dict(id="CT1c-C3 the codeset is the whole name (KILL the unit test: `en_US.UTF-8`)",
         file=P, targets=TS,
         old='ext = dot === nothing ? enc : enc[(dot + 1):end]',
         new='ext = enc'),
]
