# ORIGINAL: PCRE1's mutant list - a test tool with no twin in swipl-devel.
# tools/mutants/PCRE1.py - the mutation battery of PCRE1 piece 1 (packages/pcre/pcre4pl.c lines 398-455, the subject UTF-8 offset
# helpers: src/pl-pcre.jl), run ONCE, in CI (.github/workflows/mutation.yml; locally: tools/mutate.sh run). Format: tools/mutate_drive.py's
# (as Shift.py and JSON1.py): `id`, `file`, `old` (must occur EXACTLY once in its file), `new`, optional `equivalent` and `targets`.
# Killed by test/core_lang/test_pcre_offsets.jl, by the testset named in each id's KILL (written from the file's text; NOT run: nothing
# was compiled for this list, the verdicts are the battery's). Every `old` was checked to occur exactly once in src/pl-pcre.jl and `new` != `old`
# (python3 -I count, no Julia).
# TARGETS (audit D-0238): every test file that exercises the mutated code. The helpers have NO caller yet (`re_get_subject` and the matcher
# that will call them are later pieces), so test_pcre_offsets.jl is the complete TARGETS. `utf8_skip_char` of src/os/pl-utf8.jl, which
# `re_utf8_skip_char` wraps, is NOT mutated here (its own battery and every reader that calls it own it).
# No mutant is declared EQUIVALENT: the rows pin the C's mid-character quirk (a cached position inside a character), which separates `>` from `>=`.
T = ["test/core_lang/test_pcre_offsets.jl"]
TARGETS = T                                    # the baseline's (mutate_ci.py plan reads TARGETS)
P = "src/pl-pcre.jl"
MUTANTS = [
    # ---- utf8_skip_char, utf8_seek
    dict(id="PCRE1-1 the wrapper returns the 1-based index: the `- 1` is dropped (KILL every re_utf8_skip_char row, the seek rows)", file=P, targets=T,
         old="utf8_skip_char(b, o + 1) - 1\n",
         new="utf8_skip_char(b, o + 1) - 0\n"),
    dict(id="PCRE1-2 seek starts at byte 1 (KILL the seek rows: k = 0 gives 1)", file=P, targets=T,
         old="    s = 0\n    e = len\n",
         new="    s = 1\n    e = len\n"),
    dict(id="PCRE1-3 seek's end is one past the length (KILL the seek rows k = 6, 7 and the len 3 rows: -1 becomes a byte offset)", file=P, targets=T,
         old="    e = len\n    while offset > 0\n",
         new="    e = len + 1\n    while offset > 0\n"),
    dict(id="PCRE1-4 seek refuses only past the end: `s >= e` -> `s > e` (KILL the seek rows k = 6 and the len 3 row, the empty vector row)", file=P, targets=T,
         old="        s >= e && return -1\n",
         new="        s > e && return -1\n"),
    dict(id="PCRE1-5 seek answers 0 where C answers (size_t)-1 (KILL the seek rows k = 6, 7 and the lone, trunc rows)", file=P, targets=T,
         old="        s >= e && return -1\n",
         new="        s >= e && return 0\n"),
    dict(id="PCRE1-6 seek walks one character too many: `offset > 0` -> `offset >= 0` (KILL the seek row k = 0: 1 for 0)", file=P, targets=T,
         old="    while offset > 0\n        s >= e",
         new="    while offset >= 0\n        s >= e"),
    dict(id="PCRE1-7 seek counts two characters per step (KILL the seek rows k = 1, 2)", file=P, targets=T,
         old="        offset -= 1\n",
         new="        offset -= 2\n"),
    # ---- char_offset
    dict(id="PCRE1-8 char_offset forgets its start: the limit is the byte count alone (KILL the rows from start 6 and the bytep_to_charp walk 6, 10, 11)", file=P, targets=T,
         old="    e = start + byte_offset\n",
         new="    e = byte_offset\n"),
    dict(id="PCRE1-9 char_offset counts from byte 0 whatever its start (KILL the rows from start 6 and the walk 6, 10, 11)", file=P, targets=T,
         old="    co = 0\n    s = start\n",
         new="    co = 0\n    s = 0\n"),
    dict(id="PCRE1-10 char_offset also counts at the limit: `s < e` -> `s <= e` (KILL the byte offset 0 row, start 3 length 0 row, empty row)", file=P, targets=T,
         old="    while s < e\n",
         new="    while s <= e\n"),
    dict(id="PCRE1-11 char_offset counts two per character (KILL every char_offset row but 0)", file=P, targets=T,
         old="        co += 1\n",
         new="        co += 2\n"),
    # ---- bytep_to_charp
    dict(id="PCRE1-12 the cache is reset also at the same position: `>` -> `>=` (KILL the quirk row: byte 2, 3, then 3 again expects 3, gets 2)", file=P, targets=T,
         old="    if subj.bytep > bytep\n",
         new="    if subj.bytep >= bytep\n"),
    dict(id="PCRE1-13 going back resets the character count only: the byte position is kept (KILL the going-back row 11 -> 3: 0 for 2)", file=P, targets=T,
         old="        subj.bytep = 0\n        subj.charp = 0\n",
         new="        subj.charp = 0\n"),
    dict(id="PCRE1-14 going back resets the byte position only: the character count is kept (KILL the going-back row: 7 for 2)", file=P, targets=T,
         old="        subj.bytep = 0\n        subj.charp = 0\n",
         new="        subj.bytep = 0\n"),
    dict(id="PCRE1-15 the new characters replace the cached count: `+=` -> `=` (KILL the forward walk 6, 10: 1 for 4)", file=P, targets=T,
         old="    subj.charp += re_char_offset(",
         new="    subj.charp = re_char_offset("),
    dict(id="PCRE1-16 the byte position is not cached (KILL the (charp, bytep) rows and the walk 6, 10: 3 + 4 bytes counted again)", file=P, targets=T,
         old="    subj.bytep = bytep\n    return subj.charp\n",
         new="    return subj.charp\n"),
    dict(id="PCRE1-17 the byte position is returned for the character position (KILL every bytep_to_charp row but the ASCII ones)", file=P, targets=T,
         old="    return subj.charp\nend",
         new="    return subj.bytep\nend"),
    # ---- init_subject / the constructor
    dict(id="PCRE1-18 init_subject! keeps the length (KILL the re_subject and init_subject testset)", file=P, targets=T,
         old="    subject.length = 0\n    subject.charp = 0\n",
         new="    subject.charp = 0\n"),
    dict(id="PCRE1-19 init_subject! keeps the character position (KILL the init_subject testset: charp 4)", file=P, targets=T,
         old="    subject.charp = 0\n    subject.bytep = 0\n    return nothing",
         new="    subject.bytep = 0\n    return nothing"),
    dict(id="PCRE1-20 init_subject! keeps the byte position (KILL the init_subject testset: bytep 10)", file=P, targets=T,
         old="    subject.bytep = 0\n    return nothing",
         new="    return nothing"),
    dict(id="PCRE1-21 init_subject! keeps the string (KILL the init_subject testset)", file=P, targets=T,
         old="    subject.subject = UInt8[]\n    subject.length = 0",
         new="    subject.length = 0"),
    dict(id="PCRE1-22 the constructor starts at character position 1 (KILL the re_subject testset and the bytep_to_charp rows)", file=P, targets=T,
         old="re_subject() = re_subject(UInt8[], 0, 0, 0)",
         new="re_subject() = re_subject(UInt8[], 0, 1, 0)"),
]
