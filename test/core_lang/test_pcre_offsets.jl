# ORIGINAL: PCRE1 piece 1's gate - the subject UTF-8 offset helpers of packages/pcre/pcre4pl.c (utf8_skip_char, utf8_seek, char_offset,
# bytep_to_charp, init_subject), src/pl-pcre.jl. NO oracle and no term layer: every expected value is read off pcre4pl.c (packages-pcre
# a5e4c885, lines 398-455) by hand and cross-checked with a pointer-style python simulation of the C on a NUL terminated buffer
# (python3 -I; the script printed every number below). Nothing here has run (no Julia process was started to write this file).
# KERNEL-ONLY: the whole file (pure functions on bytes; the rows are the same on every term type, there is none).
using Test, LogicKernel
const LK = LogicKernel

_pb(s::AbstractString) = Vector{UInt8}(codeunits(s))

# "a" (1 byte) "é" (c3 a9) "€" (e2 82 ac) "😀" (f0 9f 98 80) "b": 11 bytes, character starts at byte offsets 0 1 3 6 10, end 11
const _PCRE_S = _pb("aé€😀b")
# bytes that are not well formed UTF-8: the C does not check, it skips continuation bytes after a lead byte >= 0x80 only
const _PCRE_LONE = UInt8[0x80, 0x80, 0x41]    # two stray continuation bytes, then 'A'
const _PCRE_ASCII_CB = UInt8[0x41, 0x80, 0x42]  # an ASCII byte is skipped alone, its following continuation byte is its own "character"
const _PCRE_TRUNC = UInt8[0xe2, 0x82]         # a lead byte with one of its two continuation bytes

@testset "re_utf8_skip_char (pcre4pl.c utf8_skip_char)" begin
    @test length(_PCRE_S) == 11
    # offset -> next offset
    for (o, want, why) in (
        (0, 1, "ASCII: one byte"),
        (1, 3, "two-byte character"),
        (3, 6, "three-byte character"),
        (6, 10, "four-byte character"),
        (10, 11, "ASCII at the last byte"),
        (11, 12, "at the end: the NUL terminator is ASCII, one byte (C reads it)"),
        (
            2,
            3,
            "inside a character, at its continuation byte: that is a byte >= 0x80, so the continuation loop runs"
        )
    )
        @test LK.re_utf8_skip_char(_PCRE_S, o) == want  # the row's `why` names its branch
    end
    @test LK.re_utf8_skip_char(_PCRE_LONE, 0) == 2      # stray continuation bytes are all skipped
    @test LK.re_utf8_skip_char(_PCRE_ASCII_CB, 0) == 1  # the ASCII branch does not look at the next byte
    @test LK.re_utf8_skip_char(_PCRE_ASCII_CB, 1) == 2  # the stray byte then stops at 'B'
    @test LK.re_utf8_skip_char(_PCRE_TRUNC, 0) == 2     # the loop stops at the NUL past the end
end

@testset "re_utf8_seek (pcre4pl.c utf8_seek)" begin
    len = length(_PCRE_S)
    # character offset k -> byte offset (python: seek [0, 1, 3, 6, 10, 11, -1, -1])
    for (k, want) in ((0, 0), (1, 1), (2, 3), (3, 6), (4, 10), (5, 11), (6, -1), (7, -1))
        @test LK.re_utf8_seek(_PCRE_S, len, k) == want
    end
    # the check is `s >= e` BEFORE each skip: offset == number of characters is the end (11), one more is -1
    @test LK.re_utf8_seek(UInt8[], 0, 0) == 0
    @test LK.re_utf8_seek(UInt8[], 0, 1) == -1
    @test [LK.re_utf8_seek(_PCRE_LONE, 3, k) for k in 0:4] == [0, 2, 3, -1, -1]
    @test [LK.re_utf8_seek(_PCRE_ASCII_CB, 3, k) for k in 0:4] == [0, 1, 2, 3, -1]
    @test [LK.re_utf8_seek(_PCRE_TRUNC, 2, k) for k in 0:4] == [0, 2, -1, -1, -1]
    # `len` limits the walk, not the vector: the same bytes with len 3 end after "a" and "é"
    @test LK.re_utf8_seek(_PCRE_S, 3, 2) == 3
    @test LK.re_utf8_seek(_PCRE_S, 3, 3) == -1
end

@testset "re_char_offset (pcre4pl.c char_offset)" begin
    # byte offset -> character count from offset 0 (python: choff)
    want = [0, 1, 2, 2, 3, 3, 3, 4, 4, 4, 4, 5, 6]
    for bo in 0:12
        @test LK.re_char_offset(_PCRE_S, 0, bo) == want[bo + 1]
    end
    # byte offset 2 is the second byte of "é" (bytes 1-2): the limit falls mid-character and that partial character counts, so 2
    @test LK.re_char_offset(_PCRE_S, 0, 2) == 2
    # past the end: the NUL terminator is read as one-byte characters (the C does the same on its NUL terminated buffer)
    @test LK.re_char_offset(_PCRE_S, 0, 12) == 6
    # from a start other than 0: 4 bytes from offset 6 are the whole "😀"
    @test LK.re_char_offset(_PCRE_S, 6, 4) == 1
    @test LK.re_char_offset(_PCRE_S, 6, 5) == 2
    @test LK.re_char_offset(_PCRE_S, 3, 0) == 0
    @test LK.re_char_offset(UInt8[], 0, 0) == 0
    @test [LK.re_char_offset(_PCRE_LONE, 0, bo) for bo in 0:4] == [0, 1, 1, 2, 3]
    @test [LK.re_char_offset(_PCRE_ASCII_CB, 0, bo) for bo in 0:4] == [0, 1, 2, 3, 4]
    @test [LK.re_char_offset(_PCRE_TRUNC, 0, bo) for bo in 0:3] == [0, 1, 1, 2]
end

@testset "re_subject and init_subject (pcre4pl.c)" begin
    s = LK.re_subject()
    @test s.subject == UInt8[] && s.length == 0 && s.charp == 0 && s.bytep == 0
    s.subject = _PCRE_S
    s.length = 11
    s.charp = 4
    s.bytep = 10
    LK.init_subject!(s)
    @test s.subject == UInt8[] && s.length == 0 && s.charp == 0 && s.bytep == 0
end

@testset "re_bytep_to_charp (pcre4pl.c bytep_to_charp)" begin
    function subj(b)
        s = LK.re_subject()
        s.subject = copy(b)
        s.length = length(b)
        return s
    end
    # one subject walked forward: the cached pair makes each step count only the new bytes (python: 3, 4, 5)
    s = subj(_PCRE_S)
    @test LK.re_bytep_to_charp(s, 6) == 3
    @test (s.charp, s.bytep) == (3, 6)
    @test LK.re_bytep_to_charp(s, 10) == 4
    @test (s.charp, s.bytep) == (4, 10)
    @test LK.re_bytep_to_charp(s, 11) == 5
    @test (s.charp, s.bytep) == (5, 11)
    # going back: the cache is reset (bytep > asked) and counted from 0 (python: 2)
    @test LK.re_bytep_to_charp(s, 3) == 2
    @test (s.charp, s.bytep) == (2, 3)
    # the same position again: nothing to count (python: 2)
    @test LK.re_bytep_to_charp(s, 3) == 2
    # back to 0 resets and counts nothing
    @test LK.re_bytep_to_charp(s, 0) == 0
    @test (s.charp, s.bytep) == (0, 0)
    # the whole sequence of one subject, as the python simulation printed it: [3, 4, 5, 2, 2, 0, 2, 3, 6, 2]
    s = subj(_PCRE_S)
    @test [LK.re_bytep_to_charp(s, b) for b in (6, 10, 11, 3, 3, 0, 2, 3, 11, 2)] ==
        [3, 4, 5, 2, 2, 0, 2, 3, 6, 2]
    # KNOWN QUIRK, pinned as the C's: a position in the middle of a character is cached, and the next step counts from there,
    # where it skips the rest of that character's continuation bytes as a FULL character: byte 2 (mid "é") -> 2, then byte 3 -> 3,
    # while a fresh subject asked for byte 3 gives 2.
    s = subj(_PCRE_S)
    @test LK.re_bytep_to_charp(s, 2) == 2
    @test LK.re_bytep_to_charp(s, 3) == 3
    @test (s.charp, s.bytep) == (3, 3)
    @test LK.re_bytep_to_charp(s, 3) == 3             # the same position again: `bytep > asked` is strict, nothing is reset or counted
    @test LK.re_bytep_to_charp(subj(_PCRE_S), 3) == 2
    # an empty subject; a byte position past its end reads the NUL as one character (python: 0, 1, then 1/1)
    s = subj(UInt8[])
    @test LK.re_bytep_to_charp(s, 0) == 0
    @test LK.re_bytep_to_charp(s, 1) == 1
    @test (s.charp, s.bytep) == (1, 1)
end
