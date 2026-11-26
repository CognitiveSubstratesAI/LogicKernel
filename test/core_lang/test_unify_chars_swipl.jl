# ORIGINAL: a kernel unit test of pl-fli.c's PL_unify_chars (src/pl-fli.jl; the clib1/1d callers that need it are not
# on this tree yet). test/core_lang/test_unify_chars_swipl.jl — on every term type. No swipl differential: PL_unify_chars is a
# C-interface function no Prolog goal reaches by name, so each expected value is derived from the C at the pin
# (swipl-devel 18168e62: src/pl-fli.c:3675-3704 PL_unify_chars, src/os/pl-text.c:533-566 unify_text) and the line is named in a
# comment at the row. Where a Prolog-level equivalent exists (atom_codes/2, atom_chars/2, string_codes/2) it only names the
# EXPECTED term, e.g. atom_codes(X, "abc") gives [97,98,99]; it is not run here.
# UNTESTED on the kernel: written without a compile, the gate decides.
# Rows (the mutants of tools/mutants/UNIFYCH1.py are killed by them): the four text types, PL_DIFF_LIST with its tail in t+1,
# the empty text, a Latin-1 byte, `len` shorter than the buffer and -1 (strlen), REP_ISO_LATIN_1 (= 0, the default) against
# REP_UTF8, REP_MB refused (a NotPortedError: the locale encoding is not ported), the return value on a bound term, and
# len > length(s) (BoundsError: a DIVERGES, upstream reads past the buffer).
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "..", "core_lang", "rules_common.jl"))

"An engine with `n` fresh term references; `(ld, t)` — `t` the first."
function _uc_engine(n::Int)
    db = _rdb(Tuple{_R, Union{Nothing, _R}}[])
    ld = db.ld
    LK.PL_open_foreign_frame(ld)
    return ld, LK.PL_new_term_refs(ld, n)
end

"`PL_unify_chars(t, flags, len, bytes)` on a fresh reference; `(ld, t, rc)`."
function _uc_run(flags::Int, len::Int, bytes::Vector{UInt8}; refs::Int=2)
    ld, t = _uc_engine(refs)
    return ld, t, LK.PL_unify_chars(ld, t, flags, len, bytes)
end

"The term `t` holds."
_uc_read(ld, t::Int) = lk_answers(ld, t)[1]

"A list's elements (an integer for a code, a name for an atom) and its end."
function _uc_list(x::_R)
    out = Any[]
    while is_pair(x)
        e = child(x, 2)
        push!(out, kind(e) === SYM ? String(lk_name(e)) : Int(lk_value(e)))
        x = child(x, 3)
    end
    return out, x
end

"The result of a row whose text is a list ending in `[]`: its elements."
function _uc_elems(flags::Int, len::Int, bytes::Vector{UInt8})
    ld, t, rc = _uc_run(flags, len, bytes)
    rc || return nothing
    es, tail = _uc_list(_uc_read(ld, t))
    return is_nil(tail) ? es : nothing
end

_uc_isatom(x::_R, name::String) = kind(x) === SYM && String(lk_name(x)) == name
_uc_isstring(x::_R, s::String) = kind(x) === GND && lk_value(x) == s

const _UC_ATOM, _UC_STR = LK.PL_ATOM, LK.PL_STRING
const _UC_CODES, _UC_CHARS = LK.PL_CODE_LIST, LK.PL_CHAR_LIST
const _UC_UTF8, _UC_LATIN1, _UC_MB = Int(LK.REP_UTF8), Int(LK.REP_ISO_LATIN_1), Int(LK.REP_MB)
const _UC_DIFF = Int(LK.PL_DIFF_LIST)
const _UC_ABC = UInt8[0x61, 0x62, 0x63]

@testset "PL_unify_chars: the four text types (pl-fli.c:3700 -> pl-text.c:533-566)" begin
    # PL_ATOM (pl-text.c:533): the atom abc, as atom_codes(X, "abc")
    ld, t, rc = _uc_run(_UC_ATOM, 3, _UC_ABC)
    @test rc && _uc_isatom(_uc_read(ld, t), "abc")
    # PL_STRING (pl-text.c:544): the string "abc", not the atom
    ld, t, rc = _uc_run(_UC_STR, 3, _UC_ABC)
    @test rc && _uc_isstring(_uc_read(ld, t), "abc")
    @test !(kind(_uc_read(ld, t)) === SYM)
    # PL_CODE_LIST (pl-text.c:559, EXTEND_SEQ_CODES): [97,98,99], the end []
    @test _uc_elems(_UC_CODES, 3, _UC_ABC) == [97, 98, 99]
    # PL_CHAR_LIST (pl-text.c:560, EXTEND_SEQ_CHARS): [a,b,c]
    @test _uc_elems(_UC_CHARS, 3, _UC_ABC) == ["a", "b", "c"]
end

@testset "PL_unify_chars: PL_DIFF_LIST leaves the tail in t+1 (pl-fli.c:3693-3695, pl-text.c CLOSE_SEQ_STRING)" begin
    for (ty, want) in ((_UC_CODES, [97, 98, 99]), (_UC_CHARS, ["a", "b", "c"]))
        ld, t, rc = _uc_run(ty | _UC_DIFF, 3, _UC_ABC)
        @test rc
        l, tl = lk_answers(ld, t, t + 1)                     # one read: the shared variable stays shared
        es, tail = _uc_list(l)
        @test es == want
        # the list's end is an unbound variable, and it is the one t+1 holds (`tail = t+1`)
        @test kind(tail) === VAR && kind(tl) === VAR && var_key(tail) == var_key(tl)
        # closing the difference list: t+1 = [] makes t the proper list
        @test LK.PL_unify_nil(ld, t + 1)
        es2, tail2 = _uc_list(_uc_read(ld, t))
        @test es2 == want && is_nil(tail2)
    end
    # a text that is not a list ignores the flag (the tail is only read for the list types, pl-text.c:559-566)
    ld, t, rc = _uc_run(_UC_ATOM | _UC_DIFF, 3, _UC_ABC)
    @test rc && _uc_isatom(_uc_read(ld, t), "abc")
end

@testset "PL_unify_chars: the empty text (pl-text.c:561-567)" begin
    for len in (0,)
        ld, t, rc = _uc_run(_UC_ATOM, len, UInt8[])
        @test rc && _uc_isatom(_uc_read(ld, t), "")
        ld, t, rc = _uc_run(_UC_STR, len, UInt8[])
        @test rc && _uc_isstring(_uc_read(ld, t), "")
        # text->length == 0 without a tail: PL_unify_nil (pl-text.c:566)
        ld, t, rc = _uc_run(_UC_CODES, len, UInt8[])
        @test rc && is_nil(_uc_read(ld, t))
        ld, t, rc = _uc_run(_UC_CHARS, len, UInt8[])
        @test rc && is_nil(_uc_read(ld, t))
    end
    # with a tail: PL_put_term(tail, term) (pl-text.c:563), t+1 is t itself: closing t+1 closes t
    ld, t, rc = _uc_run(_UC_CODES | _UC_DIFF, 0, UInt8[])
    @test rc
    @test LK.PL_unify_nil(ld, t + 1)
    @test is_nil(_uc_read(ld, t))
    # `len` 0 on a non-empty buffer is the empty text (pl-fli.c:3688 text.length = len)
    ld, t, rc = _uc_run(_UC_ATOM, 0, _UC_ABC)
    @test rc && _uc_isatom(_uc_read(ld, t), "")
end

@testset "PL_unify_chars: len shorter than the buffer, and -1 (pl-fli.c:3681-3682, 3688)" begin
    abcd = UInt8[0x61, 0x62, 0x63, 0x64]
    ld, t, rc = _uc_run(_UC_ATOM, 2, abcd)
    @test rc && _uc_isatom(_uc_read(ld, t), "ab")
    @test _uc_elems(_UC_CODES, 2, abcd) == [97, 98]
    ld, t, rc = _uc_run(_UC_STR, 3, abcd)
    @test rc && _uc_isstring(_uc_read(ld, t), "abc")
    # len == (size_t)-1: len = strlen(s), up to the first NUL (pl-fli.c:3681-3682)
    nul = UInt8[0x61, 0x62, 0x00, 0x63]
    ld, t, rc = _uc_run(_UC_ATOM, -1, nul)
    @test rc && _uc_isatom(_uc_read(ld, t), "ab")
    @test _uc_elems(_UC_CODES, -1, nul) == [97, 98]
    # no NUL in the vector: the whole of it (the DIVERGES: a Julia vector carries no terminator)
    ld, t, rc = _uc_run(_UC_ATOM, -1, abcd)
    @test rc && _uc_isatom(_uc_read(ld, t), "abcd")
    # a NUL first: the empty text
    ld, t, rc = _uc_run(_UC_ATOM, -1, UInt8[0x00, 0x61])
    @test rc && _uc_isatom(_uc_read(ld, t), "")
end

@testset "PL_unify_chars: a non-ASCII Latin-1 byte (pl-fli.c:3685-3686 ENC_ISO_LATIN_1)" begin
    e9 = UInt8[0xe9]                                         # é in ISO Latin-1
    ld, t, rc = _uc_run(_UC_ATOM, 1, e9)
    @test rc && _uc_isatom(_uc_read(ld, t), "é")
    ld, t, rc = _uc_run(_UC_STR, 1, e9)
    @test rc && _uc_isstring(_uc_read(ld, t), "é")
    @test _uc_elems(_UC_CODES, 1, e9) == [233]
    @test _uc_elems(_UC_CHARS, 1, e9) == ["é"]
    # with the representation spelled out: REP_ISO_LATIN_1 is 0, the same as no representation flag
    @test _UC_LATIN1 == 0
    @test _uc_elems(_UC_CODES | _UC_LATIN1, 3, UInt8[0x61, 0xe9, 0xff]) == [97, 233, 255]
end

@testset "PL_unify_chars: REP_ISO_LATIN_1 against REP_UTF8 (pl-fli.c:3685-3686, 3691)" begin
    u = Vector{UInt8}(codeunits("aé€"))            # the UTF-8 bytes 61 C3 A9 E2 82 AC
    @test length(u) == 6
    # as UTF-8: three characters
    @test _uc_elems(_UC_CODES | _UC_UTF8, length(u), u) == [97, 233, 8364]
    @test _uc_elems(_UC_CHARS | _UC_UTF8, length(u), u) == ["a", "é", "€"]
    ld, t, rc = _uc_run(_UC_STR | _UC_UTF8, length(u), u)
    @test rc && _uc_isstring(_uc_read(ld, t), "aé€")
    ld, t, rc = _uc_run(_UC_ATOM | _UC_UTF8, length(u), u)
    @test rc && _uc_isatom(_uc_read(ld, t), "aé€")
    # as ISO Latin-1 (explicit or the default): six characters, one per byte
    for rep in (_UC_LATIN1, 0)
        @test _uc_elems(_UC_CODES | rep, length(u), u) == [0x61, 0xc3, 0xa9, 0xe2, 0x82, 0xac]
        ld, t, rc = _uc_run(_UC_ATOM | rep, 2, UInt8[0xc3, 0xa9])
        @test rc && _uc_isatom(_uc_read(ld, t), "Ã©")
    end
    # a UTF-8 text is shorter than its bytes: the two bytes C3 A9 are one character
    ld, t, rc = _uc_run(_UC_ATOM | _UC_UTF8, 2, UInt8[0xc3, 0xa9])
    @test rc && _uc_isatom(_uc_read(ld, t), "é")
    # REP_UTF8 wins over REP_MB (pl-fli.c:3685: the test of REP_UTF8 comes first): no refusal
    ld, t, rc = _uc_run(_UC_ATOM | _UC_UTF8 | _UC_MB, 2, UInt8[0xc3, 0xa9])
    @test rc && _uc_isatom(_uc_read(ld, t), "é")
end

@testset "PL_unify_chars: REP_MB is refused (pl-fli.c:3686 ENC_ANSI; DIVERGES, the locale encoding is not ported)" begin
    ld, t = _uc_engine(2)
    @test_throws LK.NotPortedError LK.PL_unify_chars(ld, t, _UC_ATOM | _UC_MB, 3, _UC_ABC)
    @test_throws LK.NotPortedError LK.PL_unify_chars(ld, t, _UC_CODES | _UC_MB, 3, _UC_ABC)
end

@testset "PL_unify_chars: the return value on a bound term (pl-fli.c:3700-3703: rc of PL_unify_text)" begin
    ld, t = _uc_engine(1)
    @test LK.PL_unify_chars(ld, t, _UC_ATOM, 1, UInt8[0x61])        # t = a
    @test LK.PL_unify_chars(ld, t, _UC_ATOM, 1, UInt8[0x61])        # the same atom: true
    @test !LK.PL_unify_chars(ld, t, _UC_ATOM, 1, UInt8[0x62])       # another atom: false
    @test !LK.PL_unify_chars(ld, t, _UC_STR, 1, UInt8[0x61])        # the string "a" is not the atom a
    ld, t = _uc_engine(1)
    @test LK.PL_unify_chars(ld, t, _UC_CODES, 2, UInt8[0x61, 0x62])
    @test !LK.PL_unify_chars(ld, t, _UC_CODES, 2, UInt8[0x61, 0x63])
    @test LK.PL_unify_chars(ld, t, _UC_CODES, 2, UInt8[0x61, 0x62])
end

@testset "PL_unify_chars: len > length(s) (DIVERGES: a BoundsError)" begin
    ld, t = _uc_engine(1)
    # upstream would read past the buffer: a DIVERGES (the vector is cut at `len`, `s[1:len]`)
    @test_throws BoundsError LK.PL_unify_chars(ld, t, _UC_ATOM, 4, _UC_ABC)
    @test_throws BoundsError LK.PL_unify_chars(ld, t, _UC_ATOM, 1, UInt8[])
    # len == length(s) is not an error
    @test LK.PL_unify_chars(ld, t, _UC_ATOM, 3, _UC_ABC)
end
