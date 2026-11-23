# ORIGINAL: the ENC_WCHAR encoding of Sgetcode/Sputcode (pl-stream.c put_code, Sgetcode; the encoding prolog_stream.c's streams use); expected values are the pinned swipl's (~/.local/swipl-pin1-18168e62, `open(F, write, S, [encoding(wchar_t)])` and its binary read-back, measured 2026-11-22) wherever it can answer; the signed-value rows (w04) are the C source's (`c = chr`, pl-stream.c:1402-1426), which no Prolog read can show.
# test/files/test_stream_wchar_swipl.jl
#   * write: each code point is the 4 bytes of a `wchar_t` in the machine's byte order (little-endian here), surrogates are refused
#     before the encoding is looked at (put_code's first line);
#   * read: 4 bytes per code, a partial one at the end is the replacement character with a warning ("EOF in UCS character"),
#     then end of file; Speekcode leaves the stream where it was.
using Test, LogicKernel
const LK = LogicKernel

# swipl: put_char of [0'a, 0'\n, 233, 8364, 128512, 0x10ffff] on an encoding(wchar_t) stream, read back as bytes
const _WC_CODES = [97, 10, 233, 8364, 128512, 0x10ffff]
const _WC_BYTES = UInt8[
    97, 0, 0, 0, 10, 0, 0, 0, 233, 0, 0, 0, 172, 32, 0, 0, 0, 246, 1, 0, 255, 255, 16, 0
]

"A memory stream on `bytes`, for reading, its encoding ENC_WCHAR."
function _wc_in(bytes::Vector{UInt8})
    s = LK.Sopenmem(
        Ref{Union{Nothing, Vector{UInt8}}}(copy(bytes)), Ref(length(bytes)), "r"
    )
    @test LK.Ssetenc(s, LK.ENC_WCHAR) == 0
    return s
end

@testset "w01 Sputcode in ENC_WCHAR" begin
    bufp = Ref{Union{Nothing, Vector{UInt8}}}(nothing)
    sizep = Ref(0)
    s = LK.Sopenmem(bufp, sizep, "w")
    @test LK.Ssetenc(s, LK.ENC_WCHAR) == 0
    @test (s.flags & LK.SIO_TEXT) != 0
    for c in _WC_CODES
        @test LK.Sputcode(c, s) == c
    end
    @test s.position.charno == 6
    @test LK.Sclose(s) == 0
    @test sizep[] == 24
    @test bufp[][1:sizep[]] == _WC_BYTES                # swipl's bytes
end

@testset "w02 Sputcode in ENC_WCHAR refuses a surrogate" begin
    bufp = Ref{Union{Nothing, Vector{UInt8}}}(nothing)
    sizep = Ref(0)
    s = LK.Sopenmem(bufp, sizep, "w")
    @test LK.Ssetenc(s, LK.ENC_WCHAR) == 0
    @test LK.Sputcode(0xd800, s) == -1
    @test LK.Sferror(s) == 1
    @test s.message == "Encoding cannot represent character"
    @test s.position.charno == 0                        # nothing was written for it
    LK.Sclose(s)                                        # (the error state decides its result; not what is pinned here)
end

# the bytes are swipl's: [97, 233, 8364, 128512] and then 3 bytes (swipl: "EOF in UCS character", 65533, then -1)
@testset "w03 Sgetcode in ENC_WCHAR" begin
    s = _wc_in(
        UInt8[97, 0, 0, 0, 233, 0, 0, 0, 0xac, 0x20, 0, 0, 0x00, 0xf6, 0x01, 0, 0x61, 0, 0]
    )
    @test LK.Sgetcode(s) == 97
    @test LK.Sgetcode(s) == 233
    @test LK.Sgetcode(s) == 8364
    @test LK.Sgetcode(s) == 128512
    @test (s.flags & LK.SIO_WARN) == 0
    @test LK.Sgetcode(s) == 0xfffd                      # the partial code
    @test (s.flags & LK.SIO_WARN) != 0
    @test s.message == "EOF in UCS character"
    @test LK.Sgetcode(s) == -1                          # then the end
    @test LK.Sclose(s) == 0
    s = _wc_in(_WC_BYTES)                               # the whole of w01's bytes
    @test [LK.Sgetcode(s) for _ in 1:6] == _WC_CODES
    @test LK.Sgetcode(s) == -1
    @test (s.flags & LK.SIO_WARN) == 0
    @test s.position.charno == 6
    @test LK.Sclose(s) == 0
end

@testset "w04 get_wchar is a signed 32-bit value (pl-stream.c: `c = chr`)" begin
    for (bytes, want) in (
        (UInt8[0, 0, 0, 0x80], -2147483648), (UInt8[0xff, 0xff, 0xff, 0xff], -1),
        (UInt8[0xff, 0xff, 0xff, 0x7f], 2147483647),
        (UInt8[1, 2, 3, 4], Int(only(reinterpret(Int32, UInt8[1, 2, 3, 4]))))
    )
        s = _wc_in(bytes)
        @test LK.get_wchar(s) == want
        @test LK.get_wchar(s) == -1                     # then the end, no warning
        @test (s.flags & LK.SIO_WARN) == 0
        @test LK.Sclose(s) == 0
    end
end

@testset "w05 Speekcode in ENC_WCHAR leaves the stream where it was" begin
    s = _wc_in(UInt8[97, 0, 0, 0, 0xac, 0x20, 0, 0, 0x00, 0xf6, 0x01, 0])
    @test LK.Speekcode(s) == 97
    @test LK.Speekcode(s) == 97
    @test s.position.charno == 0
    @test LK.Sgetcode(s) == 97
    @test s.position.charno == 1
    @test LK.Speekcode(s) == 8364
    @test LK.Sgetcode(s) == 8364
    @test LK.Sgetcode(s) == 128512
    @test LK.Speekcode(s) == -1
    @test LK.Sclose(s) == 0
end
