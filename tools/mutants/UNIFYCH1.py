# ORIGINAL: UNIFYCH1's mutant list, a kernel-only file (a battery has no upstream text).
# tools/mutants/UNIFYCH1.py: the mutation battery of PL_unify_chars (REPLAY-1E, the pick of 848cb28e): src/pl-fli.jl `PL_unify_chars`
# (the `len == -1` strlen, the REP_MB refusal and its order after REP_UTF8, the slice of `len` bytes, the UTF-8 length, the ISO Latin-1
# encoding, the flag strip, PL_DIFF_LIST's tail in t+1).
# NOT RUN (written edit-only on wip/replay-1e, nothing compiled): every KILL below is read off the rows of the file UC.
# KILL ROWS: UC = test/core_lang/test_unify_chars_swipl.jl: the testsets "the four text types" (abc as atom, string, codes, chars),
#   "PL_DIFF_LIST leaves the tail in t+1", "the empty text", "len shorter than the buffer, and -1", "a non-ASCII Latin-1 byte",
#   "REP_ISO_LATIN_1 against REP_UTF8", "REP_MB is refused", "the return value on a bound term", "len > length(s)".
# EQUIVALENT: none declared. UC1-C7 (the UTF-8 length forced to 0) is killed only through the list types (an empty `text.length` answers `[]`);
#   a UTF-8 string or atom recodes from the bytes, not from `length`, so those rows do not see it: if the battery says SURVIVED, read the
#   list rows first (the codes/chars UTF-8 rows of "REP_ISO_LATIN_1 against REP_UTF8").
# TARGETS (audit D-0238): UC only: `git grep PL_unify_chars test` finds no other test, and no src caller on this tree (pl-files.jl, pl-qlf.jl,
#   pl-read.jl, pl-string.jl name it in comments only); the 1d PL_unify_term body and the pl-sha/pl-md5 callers are not on this tree: when
#   one lands its test file joins TARGETS.
UC = "test/core_lang/test_unify_chars_swipl.jl"
TARGETS = [UC]
FLI = "src/pl-fli.jl"
MUTANTS = [
    dict(id='UC1-C1 the REP flags are not stripped (KILL UC: PL_unify_text gets PL_ATOM|REP_UTF8, an unknown type, on every REP_UTF8 row)',
         file=FLI, targets=[UC],
         old='fl &= ~(Int(REP_UTF8) | Int(REP_MB) | Int(REP_ISO_LATIN_1))',
         new='fl &= ~Int(REP_ISO_LATIN_1)'),
    dict(id='UC1-C2 PL_DIFF_LIST puts the tail in t, not t+1 (KILL UC "PL_DIFF_LIST leaves the tail in t+1": the tail reference is the list reference itself, t+1 stays unbound and apart from the list end)',
         file=FLI, targets=[UC],
         old='tail = t + 1',
         new='tail = t'),
    dict(id='UC1-C3 the slice of len bytes takes one byte more (KILL UC: BoundsError on every row whose len is length(s); an extra character on "len shorter than the buffer")',
         file=FLI, targets=[UC],
         old='bytes = Vector{UInt8}(s[1:len])',
         new='bytes = Vector{UInt8}(s[1:(len + 1)])'),
    dict(id='UC1-C4 REP_MB is no longer refused (KILL UC "REP_MB is refused": no NotPortedError, the text is made as ISO Latin-1)',
         file=FLI, targets=[UC],
         old='if !utf8 && (fl & Int(REP_MB)) != 0',
         new='if false'),
    dict(id='UC1-C5 REP_MB wins over REP_UTF8 (KILL UC "REP_ISO_LATIN_1 against REP_UTF8": the row PL_ATOM|REP_UTF8|REP_MB raises, pl-fli.c:3685 tests REP_UTF8 first)',
         file=FLI, targets=[UC],
         old='if !utf8 && (fl & Int(REP_MB)) != 0',
         new='if (fl & Int(REP_MB)) != 0'),
    dict(id='UC1-C6 len -1 keeps the NUL in the text (KILL UC "len shorter than the buffer, and -1": the NUL vector answers a three-byte text, ab and a NUL; a NUL first answers one byte)',
         file=FLI, targets=[UC],
         old='len = z === nothing ? length(s) : z - 1',
         new='len = z === nothing ? length(s) : z'),
    dict(id='UC1-C7 the UTF-8 length is 0 (KILL UC "REP_ISO_LATIN_1 against REP_UTF8": a list type with text.length 0 answers [], pl-text.c:561-566; see the EQUIVALENT note on the string and atom types)',
         file=FLI, targets=[UC],
         old='PL_chars_t(bytes, nchars, ENC_UTF8, false)',
         new='PL_chars_t(bytes, 0, ENC_UTF8, false)'),
    dict(id='UC1-C8 an ISO Latin-1 text is made ENC_UTF8 (KILL UC "a non-ASCII Latin-1 byte": the byte E9 alone is not UTF-8; and "REP_ISO_LATIN_1 against REP_UTF8": C3 A9 would be one character, not two)',
         file=FLI, targets=[UC],
         old='PL_chars_t(bytes, len, ENC_ISO_LATIN_1, false)',
         new='PL_chars_t(bytes, len, ENC_UTF8, false)'),
]
