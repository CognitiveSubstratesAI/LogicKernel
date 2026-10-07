# ORIGINAL: the stream layer (R1c, src/os/pl-stream.jl) against swipl 10.1.16; upstream tests its streams through Prolog (tests/files), which needs the stream predicates (R2).
# test/files/test_stream_swipl.jl — R1c's stream gate (user, 2026-10-07: the IOSTREAM subset with
# memory streams and the position record):
#   * memory streams: text written with Sputcode reads back through Sopenmem, byte for byte; a
#     string stream reads the user's buffer; Speekcode leaves the character unread and the position
#     unmoved; Sungetc pushes back into the undo area; end of file, and reading past it;
#   * a Julia IO as a stream (Sopen_julia_io), both ways;
#   * the position record against swipl: after reading N characters of a memory stream, its
#     character, line, line-position and byte counts are what swipl's stream_position_data/3 reports
#     for open_string/2 — tabs, backspaces, CR, wide and zero-width characters, ANSI escape sequences,
#     multi-byte UTF-8 — on a corpus and on generated text.
using Test, LogicKernel, Random
const LK = LogicKernel

_st_mem(text::String) = LK.Sopenmem(
    Ref{Union{Nothing, Vector{UInt8}}}(Vector{UInt8}(codeunits(text))),
    Ref(ncodeunits(text)), "r"
)

"""
A memory stream on `text` as swipl's `open_string/2` opens one (pl-string.c): text that ISO
Latin-1 holds stays Latin-1, one byte a character; any other is UTF-8.
"""
function _st_open_string(text::String)
    if all(c -> Int(c) <= 0xff, text)
        bytes = UInt8[Int(c) % UInt8 for c in text]
        s = LK.Sopenmem(Ref{Union{Nothing, Vector{UInt8}}}(bytes), Ref(length(bytes)), "rF")
        s.encoding = LK.ENC_ISO_LATIN_1
        return s
    end
    s = _st_mem(text)
    s.encoding = LK.ENC_UTF8
    return s
end

"Read `n` characters of `text` through a stream opened as `open_string/2` opens it: its position afterwards."
function _st_pos(text::String, n::Int)::NTuple{4, Int}
    s = _st_open_string(text)
    for _ in 1:n
        LK.Sgetcode(s)
    end
    p = s.position
    r = (Int(p.charno), p.lineno, p.linepos, Int(p.byteno))
    LK.Sclose(s)
    return r
end

@testset "a memory stream round trip" begin
    for text in ("", "a", "ab\ncd", "é漢\U0001D11E", "x"^5000, "tab\there\r\nend")
        bufp = Ref{Union{Nothing, Vector{UInt8}}}(nothing)
        sizep = Ref(0)
        w = LK.Sopenmem(bufp, sizep, "w")
        for ch in text
            @test LK.Sputcode(Int(ch), w) == Int(ch)
        end
        @test LK.Sclose(w) == 0
        out = sizep[] == 0 ? UInt8[] : bufp[][1:sizep[]]
        @test String(copy(out)) == text              # (String takes the vector)
        r = LK.Sopenmem(Ref{Union{Nothing, Vector{UInt8}}}(out), Ref(length(out)), "r")
        got = Char[]
        while (c = LK.Sgetcode(r)) != LK.EOF
            push!(got, Char(c))
        end
        @test String(got) == text
        @test LK.Sgetcode(r) == LK.EOF                # past the end: EOF again, no error
        @test LK.Sferror(r) == 0 && LK.Sfpasteof(r) == 0
        @test LK.Sclose(r) == 0 && r.magic == LK.SIO_CMAGIC
    end
end

@testset "a string stream reads the user's buffer" begin
    buf = Vector{UInt8}(codeunits("ab"))
    s = LK.Sopen_string(buf, -1, "r")
    @test s.encoding == LK.ENC_ISO_LATIN_1 && LK.isStringStream(s)
    @test LK.Sgetcode(s) == Int('a') && LK.Sgetcode(s) == Int('b') &&
        LK.Sgetcode(s) == LK.EOF
    @test LK.Sopen_string(buf, 2, "x") === nothing  # a bad mode
end

@testset "Speekcode and Sungetc" begin
    s = _st_mem("aé")
    @test LK.Speekcode(s) == Int('a')
    @test LK.Speekcode(s) == Int('a')
    @test LK.Sgetcode(s) == Int('a')
    @test LK.Speekcode(s) == Int('é')
    @test s.position.charno == 1 && s.position.byteno == 1     # peeking moved nothing
    @test LK.Sgetcode(s) == Int('é') && s.position.byteno == 3
    @test LK.Sungetc(0xa9 % Int, s) == 0xa9 && LK.Sungetc(0xc3 % Int, s) == 0xc3   # é, as bytes
    @test LK.Sgetcode(s) == Int('é')
    @test LK.Speekcode(s) == LK.EOF
    @test LK.Sgetcode(s) == LK.EOF
    LK.Sclose(s)
end

@testset "a Julia IO as a stream" begin
    io = IOBuffer()
    w = LK.Sopen_julia_io(io, "w", false)
    for ch in "héllo\n"
        LK.Sputcode(Int(ch), w)
    end
    @test LK.Sflush(w) == 0
    @test String(take!(copy(io))) == "héllo\n"
    LK.Sclose(w)
    r = LK.Sopen_julia_io(IOBuffer("wörld"), "r", true)
    @test [Char(LK.Sgetcode(r)) for _ in 1:5] == collect("wörld")
    @test LK.Sgetcode(r) == LK.EOF && r.position.byteno == 6
    LK.Sclose(r)
    @test LK.Sopen_julia_io(IOBuffer(), "a", false) === nothing
end

# swipl 10.1.16 reads the same bytes from a UTF-8 file as the same codes (probed with
# read_stream_to_codes/2: ff 41 → [65533,65], c3 41 → [65533,65])
@testset "malformed UTF-8: U+FFFD and a warning, as upstream's Sgetcode" begin
    function codes(bytes::Vector{UInt8})
        s = LK.Sopenmem(Ref{Union{Nothing, Vector{UInt8}}}(bytes), Ref(length(bytes)), "r")
        s.encoding = LK.ENC_UTF8
        out = Int[]
        msgs = Union{Nothing, String}[]
        while (c = LK.Sgetcode(s)) != LK.EOF
            push!(out, c)
            push!(msgs, (s.flags & LK.SIO_WARN) != 0 ? s.message : nothing)
            LK.Sclearerr(s)
        end
        LK.Sclose(s)
        return out, msgs
    end
    # a byte that cannot start a sequence
    @test codes(UInt8[0xff, 0x41]) == ([0xfffd, 0x41], ["Illegal UTF-8 start", nothing])
    # a start byte whose continuation is missing: the non-continuation byte is read again
    @test codes(UInt8[0xc3, 0x41]) ==
        ([0xfffd, 0x41], ["Illegal UTF-8 continuation", nothing])
    # a surrogate, D800, encoded in UTF-8
    @test codes(UInt8[0xed, 0xa0, 0x80, 0x42]) ==
        ([0xfffd, 0x42], ["UTF-8 surrogate code point", nothing])
    # a truncated sequence at the end of the stream: Sungetc pushes EOF back as the byte 0xff,
    # which then reads as an illegal start — two U+FFFD, as swipl 10.1.16 reads such a file
    # (probed: read_stream_to_codes/2 on 41 e6 bc gives [65,65533,65533])
    @test codes(UInt8[0x41, 0xe6, 0xbc])[1] == [0x41, 0xfffd, 0xfffd]
end

@testset "an unrepresentable character and the encodings refused" begin
    s = LK.Sopenmem(Ref{Union{Nothing, Vector{UInt8}}}(nothing), Ref(0), "w")
    s.encoding = LK.ENC_ISO_LATIN_1
    @test LK.Sputcode(Int(0x263a), s) == -1 && LK.Sferror(s) == 1   # reperror: no SIO_REP* flag
    @test LK.Scanrepresent(Int(0x263a), s) == -1 && LK.Scanrepresent(Int(0xe9), s) == 0
    s.encoding = LK.ENC_UTF16LE
    @test_throws LK.NotPortedError LK.Sputcode(Int('a'), s)    # UTF-8 only (user, 2026-10-07)
end

const _ST_SWIPL = Sys.which("swipl")
const _ST_SWIPL_REQUIRED = get(ENV, "LOGICKERNEL_REQUIRE_SWIPL", "") == "1"

if _ST_SWIPL !== nothing
    @testset "positions == swipl's stream_position_data/3 on open_string/2" begin
        corpus = Tuple{String, Int}[("ab\ncd", 4), ("a\tb", 3), ("é\n漢x", 4), ("a\bb", 3),
            ("x\r\ny", 3), ("\e[1mA", 5), ("\e]8;;http://x\aZ", 15), ("áb", 3),
            ("\t\t", 2), ("\b\b", 2), ("\e(BA", 4), ("\e\e[mB", 5), ("a​b", 3),
            (" x", 2), (" y", 2)]
        rng = Xoshiro(20261007)
        alphabet = ['a', 'Z', ' ', '\t', '\n', '\r', '\b', 'é', '漢', '́', '\e', '[', '1',
            'm', ']', '\a', '\\', '\U0001D11E', ' ', ' ', '​', '\x7f', '\x01']
        for _ in 1:300
            txt = String(rand(rng, alphabet, rand(rng, 1:40)))
            push!(corpus, (txt, rand(rng, 0:length(txt))))
        end
        ours = [_st_pos(t, n) for (t, n) in corpus]
        prog = IOBuffer()
        println(
            prog,
            """
  pos(Cs, N) :- string_codes(S, Cs), open_string(S, In), length(L, N), maplist(get_char(In), L),
      stream_property(In, position(P)),
      stream_position_data(char_count, P, C), stream_position_data(line_count, P, Li),
      stream_position_data(line_position, P, LP), stream_position_data(byte_count, P, B),
      close(In), format("~w ~w ~w ~w~n", [C, Li, LP, B])."""
        )
        print(prog, "run :- ")
        for (t, n) in corpus
            print(prog, "pos([", join(Int.(collect(t)), ","), "], ", n, "), ")
        end
        println(prog, "true.\n:- initialization((run, halt)).")
        text = mktempdir() do d
            f = joinpath(d, "p.pl")
            write(f, String(take!(prog)))
            read(`swipl -q $f`, String)
        end
        theirs = [Tuple(parse.(Int, split(l))) for l in split(chomp(text), '\n')]
        @test length(theirs) == length(ours)
        bad = [
            (corpus[k], ours[k], theirs[k]) for k in 1:min(length(ours), length(theirs))
            if ours[k] != theirs[k]
        ]
        for (c, o, t) in bad[1:min(end, 8)]
            println(stderr, "  DIVERGES: ", repr(c), "\n    kernel ", o, "\n    swipl  ", t)
        end
        @test isempty(bad)
    end
elseif _ST_SWIPL_REQUIRED
    error(
        "LOGICKERNEL_REQUIRE_SWIPL=1 but `swipl` is not on PATH — the position differential would be skipped"
    )
else
    @info "POSITION DIFFERENTIAL NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI's analysis job."
    @testset "position differential skipped only where it is not required" begin
        @test !_ST_SWIPL_REQUIRED
    end
end
