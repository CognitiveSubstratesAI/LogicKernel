# ORIGINAL: pl-qlf.c's unsigned varint (qlfPutUInt32, qlfGetUInt32, PL_qlf_put_uint32, PL_qlf_get_uint32; swipl-devel 18168e62) has no Prolog-level test
# upstream: it is reached through a blob's save/load functions. The byte rows below come from an independent transcription of the C loop (python3), not
# from the Julia port. Nothing here has run (written edit-only). Streams: a memory output stream read back through a memory input stream.
using Test, LogicKernel
const LK = LogicKernel

# the bytes a memory output stream holds after `f(w)`
function _q32_bytes(f)::Vector{UInt8}
    bufp = Ref{Union{Nothing, Vector{UInt8}}}(nothing)
    sizep = Ref(0)
    w = LK.Sopenmem(bufp, sizep, "w")
    f(w)
    LK.Sflush(w)
    out = sizep[] == 0 ? UInt8[] : copy(bufp[][1:sizep[]])
    LK.Sclose(w)
    return out
end

_q32_reader(bytes::Vector{UInt8}) = LK.Sopenmem(Ref{Union{Nothing, Vector{UInt8}}}(copy(bytes)), Ref(length(bytes)), "r")

const _Q32_ROWS = [
    (0x00000000, UInt8[0x80]),
    (0x00000001, UInt8[0x81]),
    (0x0000003f, UInt8[0xbf]),
    (0x00000040, UInt8[0xc0]),
    (0x0000007f, UInt8[0xff]),
    (0x00000080, UInt8[0x00, 0x81]),
    (0x00000081, UInt8[0x01, 0x81]),
    (0x000000ff, UInt8[0x7f, 0x81]),
    (0x00000100, UInt8[0x00, 0x82]),
    (0x00003fff, UInt8[0x7f, 0xff]),
    (0x00004000, UInt8[0x00, 0x00, 0x81]),
    (0x00004001, UInt8[0x01, 0x00, 0x81]),
    (0x001fffff, UInt8[0x7f, 0x7f, 0xff]),
    (0x00200000, UInt8[0x00, 0x00, 0x00, 0x81]),
    (0x0fffffff, UInt8[0x7f, 0x7f, 0x7f, 0xff]),
    (0x10000000, UInt8[0x00, 0x00, 0x00, 0x00, 0x81]),
    (0x10000001, UInt8[0x01, 0x00, 0x00, 0x00, 0x81]),
    (0x80000000, UInt8[0x00, 0x00, 0x00, 0x00, 0x88]),
    (0xfffffffe, UInt8[0x7e, 0x7f, 0x7f, 0x7f, 0x8f]),
    (0xffffffff, UInt8[0x7f, 0x7f, 0x7f, 0x7f, 0x8f]),
    (0x12345678, UInt8[0x78, 0x2c, 0x51, 0x11, 0x81]),
    (0xdeadbeef, UInt8[0x6f, 0x7d, 0x36, 0x75, 0x8d]),
]

@testset "qlfPutUInt32: the bytes (7-bit groups, low first, 0x80 on the last)" begin
    for (v, bytes) in _Q32_ROWS
        @test _q32_bytes(w -> LK.qlfPutUInt32(UInt32(v), w)) == bytes
    end
end

@testset "qlfGetUInt32: the bytes read back" begin
    for (v, bytes) in _Q32_ROWS
        r = _q32_reader(bytes)
        @test LK.qlfGetUInt32(r) == UInt32(v)
        @test LK.Sferror(r) == 0
        @test r.position !== nothing && r.position.byteno == 0     # `Qgetc` is `Snpgetc`: no position recording
        LK.Sclose(r)
    end
    # a byte with 0x80 set ends the number even when its low bits are 0
    @test LK.qlfGetUInt32(_q32_reader(UInt8[0x80])) == 0
    # a group without 0x80 continues: 0x00 then 0x81 is 128, not 1
    @test LK.qlfGetUInt32(_q32_reader(UInt8[0x00, 0x81])) == 128
    # a stray high group in the fifth byte keeps only the low 32 bits (the C's unsigned shift)
    @test LK.qlfGetUInt32(_q32_reader(UInt8[0x7f, 0x7f, 0x7f, 0x7f, 0xff])) == 0xffffffff
end

@testset "several numbers in one stream, in order" begin
    vs = UInt32[0, 5, 128, 300, 0xffffffff, 1, 16384, 0]
    bytes = _q32_bytes(w -> foreach(v -> LK.qlfPutUInt32(v, w), vs))
    @test bytes == UInt8[0x80, 0x85, 0x00, 0x81, 0x2c, 0x82, 0x7f, 0x7f, 0x7f, 0x7f, 0x8f, 0x81, 0x00, 0x00, 0x81, 0x80]
    r = _q32_reader(bytes)
    @test [LK.qlfGetUInt32(r) for _ in vs] == vs
    LK.Sclose(r)
end

@testset "round trip over a spread of values" begin
    vs = UInt32[]
    for k in 0:31
        for d in (-1, 0, 1)
            x = (Int64(1) << k) + d
            0 <= x <= 0xffffffff && push!(vs, UInt32(x))
        end
    end
    push!(vs, 0xffffffff)
    bytes = _q32_bytes(w -> foreach(v -> LK.qlfPutUInt32(v, w), vs))
    r = _q32_reader(bytes)
    @test [LK.qlfGetUInt32(r) for _ in vs] == vs
    LK.Sclose(r)
end

@testset "end of file reads as the C's unsigned -1 (value 0x7f)" begin
    r = _q32_reader(UInt8[])
    @test LK.qlfGetUInt32(r) == 0x7f
    LK.Sclose(r)
end

@testset "PL_qlf_put_uint32 / PL_qlf_get_uint32: the success flag and the value" begin
    bufp = Ref{Union{Nothing, Vector{UInt8}}}(nothing)
    sizep = Ref(0)
    w = LK.Sopenmem(bufp, sizep, "w")
    @test LK.PL_qlf_put_uint32(UInt32(300), w) === true
    @test LK.PL_qlf_put_uint32(UInt32(7), w) === true
    LK.Sflush(w)
    bytes = copy(bufp[][1:sizep[]])
    LK.Sclose(w)
    @test bytes == UInt8[0x2c, 0x82, 0x87]
    r = _q32_reader(bytes)
    @test LK.PL_qlf_get_uint32(r) == (true, UInt32(300))
    @test LK.PL_qlf_get_uint32(r) == (true, UInt32(7))
    LK.Sclose(r)
end
