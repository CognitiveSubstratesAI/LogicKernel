# CLASS: test
# ORIGINAL: ZLIB1 piece Z2's gate - the filter of packages/zlib/zlib4pl.c (src/pl-zlib.jl: ZContext, alloc_zcontext, free_zcontext, sync_stream, zread, zwrite4,
# zwrite, zcontrol, zclose; packages-zlib 9f4be6fe; the C line numbers are in the testsets' comments). BLIND-CODED: nothing here has run (no Julia process was
# started to write this file). Every expectation is derived, none invented: from the C (which flush zcontrol sends, when zread restarts a gzip member, what
# sync_stream leaves in the parent, what zclose does with the parent), from round trips (compress then decompress: equal; the three formats; every input
# size), from the format definitions (RFC 1950/1952 header bytes) and from the library's own answers (the message zlib itself sets). NEVER from compressed byte
# values (DIVERGES 1 of the file). `_zopen` is a STAND-IN for pl_zopen (piece Z3, C 455-505): it builds the same filter stream by hand, without SIO_TEXT.
# DOC-ONLY (no row can provoke them): the "zlib: not enough memory" and "zlib: initialization failed" texts (Z_MEM_ERROR/Z_STREAM_ERROR at init), the
# test_zlib.pl zopen rows (they need pl_zopen, Z3). KERNEL-SIDE: the parent's byte position row of z04 rests on the kernel's Sfeof not counting the fetched byte.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE - the filter builds no term, the record holds the local data of a database of the type
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TL = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})

function _env(::Type{T}) where {T}
    gd = LK.PL_global_data{T}()
    ld = LK.PL_local_data{T}(gd)
    LK.PL_open_foreign_frame(ld)
    return gd, ld
end

_zbytes(s::String) = Vector{UInt8}(codeunits(s))
function _lcg_bytes(n::Int, seed::UInt32 = 0x1234abcd)
    x = seed
    out = Vector{UInt8}(undef, n)
    for i in 1:n
        x = x * UInt32(1664525) + UInt32(1013904223)
        out[i] = UInt8(x >> 24)
    end
    return out
end
_text(n::Int) = repeat(_zbytes("the quick brown fox jumps over the lazy dog. "), cld(n, 45))[1:n]

const _INPUTS = Pair{String, Vector{UInt8}}[
    "empty" => UInt8[], "1 byte" => UInt8[0x41], "text 5000" => _text(5000), "random 20000" => _lcg_bytes(20000),
]
const _FORMATS = (LK.Z_F_GZIP, LK.Z_F_DEFLATE, LK.Z_F_RAW_DEFLATE)

_sf_in(bytes::Vector{UInt8}) =
    LK.Sopenmem(Ref{Union{Nothing, Vector{UInt8}}}(copy(bytes)), Ref(length(bytes)), "r")
function _sf_out()
    bufp = Ref{Union{Nothing, Vector{UInt8}}}(nothing)
    sizep = Ref(0)
    return LK.Sopenmem(bufp, sizep, "w"), bufp, sizep
end
_sf_bytes(bufp, sizep) = sizep[] == 0 ? UInt8[] : copy(bufp[][1:sizep[]])

# zlib4pl.c COPY_FLAGS (412-415), without SIO_TEXT
const _COPY_FLAGS = LK.SIO_INPUT | LK.SIO_OUTPUT | LK.SIO_REPXML | LK.SIO_REPPL | LK.SIO_RECORDPOS

# STAND-IN for pl_zopen (piece Z3, C 455-505)
function _zopen(ld, parent::LK.IOSTREAM; format::Int, level::Integer = -1, close_parent::Bool = true, multi_part::Int = -1)
    ctx = LK.alloc_zcontext(ld, parent)
    ctx.close_parent = close_parent
    ctx.multi_part = multi_part
    ctx.format = format
    if (parent.flags & LK.SIO_OUTPUT) != 0
        zs = ctx.zstate
        rc = if format == LK.Z_F_GZIP
            LK.zlib_deflate_init2!(zs, Cint(level), LK.Z_DEFLATED, Cint(LK.MAX_WBITS + 16), LK.MAX_MEM_LEVEL, Cint(0))
        elseif format == LK.Z_F_RAW_DEFLATE
            LK.zlib_deflate_init2!(zs, Cint(level), LK.Z_DEFLATED, Cint(-LK.MAX_WBITS), LK.MAX_MEM_LEVEL, Cint(0))
        else
            LK.zlib_deflate_init!(zs, Cint(level))
        end
        rc == LK.Z_OK || error("deflateInit failed: $rc")
    end
    s2 = LK.Snew(ctx, (parent.flags & _COPY_FLAGS) | LK.SIO_FBUF, LK.Sfilterfunctions)
    s2.encoding = parent.encoding
    ctx.zstream = s2
    LK.Sset_filter(parent, s2)
    return s2, ctx
end

function _compress(ld, data::Vector{UInt8}; format::Int, level::Integer = -1)
    parent, bufp, sizep = _sf_out()
    zs, ctx = _zopen(ld, parent; format, level, close_parent = false)
    @test LK.Sfwrite(data, 1, length(data), zs) == length(data)
    @test LK.closeStream(ld, zs)
    @test parent.upstream === nothing
    @test LK.Sclose(parent) == 0
    return _sf_bytes(bufp, sizep)
end

function _read_all(zs::LK.IOSTREAM; chunk::Int = 1000)
    out = UInt8[]
    buf = Vector{UInt8}(undef, chunk)
    while true
        n = LK.Sfread(buf, 1, chunk, zs)
        n > 0 && append!(out, @view buf[1:n])
        n < chunk && break
    end
    return out
end

# a parent that hands out ONE byte per read
mutable struct Dribble <: LK.AbstractSfilter
    data::Vector{UInt8}
    pos::Int
end
function LK.Sfilter_read(h::Dribble, mem::Vector{UInt8}, from::Int, size::Int)::Int
    h.pos > length(h.data) && return 0
    mem[from] = h.data[h.pos]
    h.pos += 1
    return 1
end
struct FailSink <: LK.AbstractSfilter end
mutable struct CtlParent <: LK.AbstractSfilter
    size::Int
end
LK.Sfilter_write(h::CtlParent, mem::Vector{UInt8}, from::Int, size::Int)::Int = size
function LK.Sfilter_control(h::CtlParent, op::Int, arg)::Int
    if op == LK.SIO_GETSIZE
        arg[] = h.size
        return 0
    end
    return LK.SCONTROL_NONE
end

@testset "z01 the record: alloc_zcontext, free_zcontext, the format constants" begin
    gd, ld = _env(_TL)
    @test (LK.Z_F_UNKNOWN, LK.Z_F_GZIP, LK.Z_F_DEFLATE, LK.Z_F_RAW_DEFLATE) == (0, 1, 2, 3)   # C 64-69
    @test LK.Z_BUFSIZE == LK.SIO_BUFSIZE                                                 # C 62
    parent, bufp, sizep = _sf_out()
    ctx = LK.alloc_zcontext(ld, parent)                                                  # C 84-93
    @test ctx.stream === parent && ctx.zstream === nothing
    @test ctx.close_parent === true                                                      # C 90
    @test ctx.initialized === false && ctx.z_stream_end === false && ctx.multi_part == 0
    @test ctx.format == LK.Z_F_UNKNOWN
    @test ctx.zstate != C_NULL && ctx.zhead != C_NULL
    @test LK.z_stream_avail_in(ctx.zstate) == 0 && LK.z_stream_next_in(ctx.zstate) == C_NULL   # C 88
    @test LK.gz_header_done(ctx.zhead) == 0
    LK.free_zcontext(ctx)                                                                # no filter: release (C 100), PL_free (C 103)
    @test ctx.zstate == C_NULL && ctx.zhead == C_NULL
    @test parent.magic == LK.SIO_MAGIC
    LK.free_zcontext(ctx)                                                                # a second call frees nothing
    zs, ctx2 = _zopen(ld, parent; format = LK.Z_F_DEFLATE, close_parent = false)
    @test parent.upstream === zs
    LK.free_zcontext(ctx2)                                                               # a filter: unlink (C 98-99)
    @test parent.upstream === nothing && ctx2.zstate == C_NULL
    @test LK.Sclose(parent) == 0
end

@testset "z02 round trip: $fname through format $fmt" for (fname, data) in _INPUTS, fmt in _FORMATS
    gd, ld = _env(_TL)
    comp = _compress(ld, data; format = fmt)
    if fmt == LK.Z_F_GZIP
        @test comp[1:2] == UInt8[0x1f, 0x8b]                                              # RFC 1952
    elseif fmt == LK.Z_F_DEFLATE
        @test (comp[1] & 0x0f) == 8 && ((Int(comp[1]) << 8) | Int(comp[2])) % 31 == 0    # RFC 1950
    end
    @test !isempty(comp)
    parent = _sf_in(comp)
    zs, ctx = _zopen(ld, parent; format = fmt)
    @test _read_all(zs) == data
    @test LK.Sferror(zs) == 0                                                            # Z_FINISH was sent
    @test ctx.z_stream_end                                                                # C 206
    @test LK.closeStream(ld, zs)
    @test parent.magic == LK.SIO_CMAGIC                                                  # close_parent default: C 374-377
    @test ctx.zstate == C_NULL
end

@testset "z03 auto-detect (F_UNKNOWN): $fname, format $fmt" for (fname, data) in _INPUTS, fmt in (LK.Z_F_GZIP, LK.Z_F_DEFLATE)
    gd, ld = _env(_TL)
    comp = _compress(ld, data; format = fmt)
    parent = _sf_in(comp)
    zs, ctx = _zopen(ld, parent; format = LK.Z_F_UNKNOWN)
    @test _read_all(zs) == data
    @test LK.Sferror(zs) == 0
    @test LK.closeStream(ld, zs)
end

@testset "z04 the parent's unread bytes and position after the end of the stream" begin
    gd, ld = _env(_TL)
    data = _text(3000)
    comp = _compress(ld, data; format = LK.Z_F_DEFLATE)
    tail = _zbytes("TAIL")
    parent = _sf_in(vcat(comp, tail))
    zs, ctx = _zopen(ld, parent; format = LK.Z_F_DEFLATE, close_parent = false, multi_part = 0)
    @test _read_all(zs) == data
    @test ctx.z_stream_end && ctx.initialized
    if parent.position !== nothing
        @test parent.position.byteno == length(comp)                                     # C 115-118
    end
    @test LK.closeStream(ld, zs)
    @test parent.upstream === nothing
    rest = Vector{UInt8}(undef, 4)
    @test LK.Sfread(rest, 1, 4, parent) == 4 && rest == tail                             # C 120: bufp == next_in
    @test LK.Sclose(parent) == 0
end

@testset "z05 multi_part" begin
    gd, ld = _env(_TL)
    a, b = _text(2000), _lcg_bytes(900, 0x00c0ffee)
    gza = _compress(ld, a; format = LK.Z_F_GZIP)
    gzb = _compress(ld, b; format = LK.Z_F_GZIP)
    parent = _sf_in(vcat(gza, gzb))                                                      # gzip, default -1: done is 0, not < 0 (C 214-215)
    zs, ctx = _zopen(ld, parent; format = LK.Z_F_GZIP, multi_part = -1)
    @test _read_all(zs) == vcat(a, b)
    @test LK.Sferror(zs) == 0
    @test LK.closeStream(ld, zs)
    parent = _sf_in(vcat(gza, gzb))                                                      # multi_part false: stops at the first
    zs, ctx = _zopen(ld, parent; format = LK.Z_F_GZIP, multi_part = 0, close_parent = false)
    @test _read_all(zs) == a
    @test LK.closeStream(ld, zs)
    rest = Vector{UInt8}(undef, length(gzb))
    @test LK.Sfread(rest, 1, length(gzb), parent) == length(gzb) && rest == gzb
    @test LK.Sclose(parent) == 0
    parent = _sf_in(vcat(gza, gzb))                                                      # auto-detect of gzip: done > 0, continues
    zs, ctx = _zopen(ld, parent; format = LK.Z_F_UNKNOWN, multi_part = -1)
    @test _read_all(zs) == vcat(a, b)
    @test LK.gz_header_done(ctx.zhead) > 0
    @test LK.closeStream(ld, zs)
    za = _compress(ld, a; format = LK.Z_F_DEFLATE)                                       # auto-detect of zlib: done < 0, ONE stream (C 214-216)
    zb = _compress(ld, b; format = LK.Z_F_DEFLATE)
    parent = _sf_in(vcat(za, zb))
    zs, ctx = _zopen(ld, parent; format = LK.Z_F_UNKNOWN, multi_part = -1)
    @test _read_all(zs) == a
    @test LK.gz_header_done(ctx.zhead) < 0
    @test LK.closeStream(ld, zs)
    parent = _sf_in(vcat(za, zb))                                                        # explicit multi_part true continues (C 213, 214)
    zs, ctx = _zopen(ld, parent; format = LK.Z_F_UNKNOWN, multi_part = 1)
    @test _read_all(zs) == vcat(a, b)
    @test LK.closeStream(ld, zs)
    parent = _sf_in(vcat(gza, _zbytes("TAIL")))                                          # a member then non-gzip: the restart fails (C 218-225)
    zs, ctx = _zopen(ld, parent; format = LK.Z_F_GZIP, multi_part = -1)
    @test _read_all(zs) == a
    @test LK.Sferror(zs) != 0
    @test zs.message isa String && !isempty(zs.message)                                  # zlib's msg (C 253-256)
end

@testset "z06 one byte per parent read" for fmt in (LK.Z_F_DEFLATE, LK.Z_F_GZIP, LK.Z_F_RAW_DEFLATE)
    gd, ld = _env(_TL)
    data = _text(3000)
    comp = _compress(ld, data; format = fmt)
    parent = LK.Snew(Dribble(comp, 1), LK.SIO_INPUT | LK.SIO_FBUF, LK.Sfilterfunctions)
    zs, ctx = _zopen(ld, parent; format = fmt)                                           # the n == 0 retry (C 190-198), parent re-read (C 139-145)
    @test _read_all(zs) == data
    @test LK.Sferror(zs) == 0
    @test LK.closeStream(ld, zs)
end

@testset "z07 the read function: count, end of file, error" begin
    gd, ld = _env(_TL)
    data = _text(300)
    comp = _compress(ld, data; format = LK.Z_F_DEFLATE)
    parent = _sf_in(comp)
    zs, ctx = _zopen(ld, parent; format = LK.Z_F_DEFLATE, close_parent = false)
    mem = zeros(UInt8, 64 + 10)
    n = LK.Sfilter_read(ctx, mem, 6, 64)                                                 # fills mem[6:69]
    @test n == 64 && mem[6:(5 + n)] == data[1:64] && all(==(0x00), mem[1:5]) && all(==(0x00), mem[70:end])
    big = zeros(UInt8, 1000)
    n2 = LK.Sfilter_read(ctx, big, 1, 1000)
    @test n2 == length(data) - 64 && big[1:n2] == data[65:end]
    @test LK.Sfilter_read(ctx, big, 1, 1000) == 0                                        # C 213-228
    @test LK.closeStream(ld, zs)
    @test LK.Sclose(parent) == 0
    parent = _sf_in(_zbytes("this is not a compressed stream"))                         # corrupt data: -1
    zs, ctx = _zopen(ld, parent; format = LK.Z_F_GZIP, close_parent = false)
    @test LK.Sfilter_read(ctx, big, 1, 1000) == -1
    @test zs.message isa String && !isempty(zs.message) && LK.Sferror(zs) != 0
    @test zs.message == LK.z_stream_msg(ctx.zstate)                                      # zlib's own text wins over the C one (C 253-254)
    LK.Sclearerr(zs)
    @test LK.Sclose(zs) == 0
    @test LK.Sclose(parent) == 0
end

@testset "z08 unexpected end of the input" begin
    gd, ld = _env(_TL)
    for fmt in (LK.Z_F_DEFLATE, LK.Z_F_UNKNOWN)
        parent = _sf_in(UInt8[])
        zs, ctx = _zopen(ld, parent; format = fmt)
        buf = Vector{UInt8}(undef, 10)
        @test LK.Sfread(buf, 1, 10, zs) == 0
        @test LK.Sferror(zs) != 0 && zs.message == "zlib: unexpected end-of-file"       # Z_BUF_ERROR, C 246-249
        LK.Sclearerr(zs)
        @test LK.Sclose(zs) == 0
        @test parent.magic == LK.SIO_CMAGIC
    end
    data = _lcg_bytes(3000)
    comp = _compress(ld, data; format = LK.Z_F_DEFLATE)
    parent = _sf_in(comp[1:(length(comp) ÷ 2)])
    zs, ctx = _zopen(ld, parent; format = LK.Z_F_DEFLATE, close_parent = false)
    out = _read_all(zs)
    @test length(out) < length(data) && out == data[1:length(out)]
    @test LK.Sferror(zs) != 0 && zs.message == "zlib: unexpected end-of-file"
    @test !ctx.z_stream_end
    LK.Sclearerr(zs)
    @test LK.Sclose(zs) == 0
    @test LK.Sclose(parent) == 0
end

@testset "z09 control: flush output, set encoding, the parent's control" begin
    gd, ld = _env(_TL)
    parent, bufp, sizep = _sf_out()
    zs, ctx = _zopen(ld, parent; format = LK.Z_F_DEFLATE, close_parent = false)
    @test LK.Sfilter_control(ctx, LK.SIO_SETENCODING, nothing) == 0                      # C 331-332
    data = _text(300)
    @test LK.Sfwrite(data, 1, length(data), zs) == length(data)
    @test LK.Sflush(zs) == 0                                                             # SIO_FLUSHOUTPUT = a SYNC flush (C 328-330)
    prefix = _sf_bytes(bufp, sizep)
    @test !isempty(prefix)
    pin = _sf_in(prefix)
    zin, cin = _zopen(ld, pin; format = LK.Z_F_DEFLATE)
    got = Vector{UInt8}(undef, length(data))
    @test LK.Sfread(got, 1, length(data), zin) == length(data) && got == data
    @test LK.Sferror(zin) == 0 && !cin.z_stream_end
    LK.Sclearerr(zin)
    @test LK.Sclose(zin) == 0
    more = _lcg_bytes(777, 0x0badf00d)
    @test LK.Sfwrite(more, 1, length(more), zs) == length(more)
    @test LK.closeStream(ld, zs)
    @test LK.Sclose(parent) == 0
    pin = _sf_in(_sf_bytes(bufp, sizep))
    zin, cin = _zopen(ld, pin; format = LK.Z_F_DEFLATE)
    @test _read_all(zin) == vcat(data, more) && LK.Sferror(zin) == 0
    @test LK.closeStream(ld, zin)
    pc = LK.Snew(CtlParent(1234), LK.SIO_OUTPUT | LK.SIO_FBUF, LK.Sfilterfunctions)      # the default arm (C 333-343)
    zc, cc = _zopen(ld, pc; format = LK.Z_F_DEFLATE, close_parent = false)
    size = Ref(0)
    @test LK.Sfilter_control(cc, LK.SIO_GETSIZE, size) == 0 && size[] == 1234
    @test LK.Sfilter_control(cc, 999, nothing) == LK.SCONTROL_NONE
    @test LK.closeStream(ld, zc)
    pm, _, _ = _sf_out()                                                                 # a memory parent has no control function: -1
    zm, cm = _zopen(ld, pm; format = LK.Z_F_DEFLATE, close_parent = false)
    @test LK.Sfilter_control(cm, LK.SIO_GETSIZE, Ref(0)) == -1
    @test LK.closeStream(ld, zm)
    @test LK.Sclose(pm) == 0
    pd, _, _ = _sf_out()                                                                 # a closed parent: -1 (C 335)
    @test LK.Sclose(pd) == 0
    cd = LK.alloc_zcontext(ld, pd)
    @test LK.Sfilter_control(cd, LK.SIO_GETSIZE, Ref(0)) == -1
    LK.z_stream_free(cd.zstate)
    LK.gz_header_free(cd.zhead)
end

@testset "z10 zwrite4: sizes, flush arguments, a failing parent" begin
    gd, ld = _env(_TL)
    data = _text(500)
    parent, bufp, sizep = _sf_out()
    zs, ctx = _zopen(ld, parent; format = LK.Z_F_DEFLATE, close_parent = false)
    @test LK.Sfilter_write(ctx, data, 1, 500) == 500                                     # C 319
    @test sizep[] == 0                                                                   # Z_NO_FLUSH: no Sflush(parent) (C 310); blind: the memory stream publishes its size at Sflush
    @test LK.zwrite4(ctx, data, 101, 200, LK.Z_NO_FLUSH) == 200                          # the slice at `from`
    @test LK.zwrite4(ctx, data, 1, 0, LK.Z_SYNC_FLUSH) == 0                              # C 330
    @test LK.zwrite4(ctx, data, 1, 0, LK.Z_SYNC_FLUSH) == 0                              # nothing new: deflate answers Z_BUF_ERROR, "nothing to do" (C 299-301)
    @test LK.zwrite4(ctx, UInt8[], 1, 0, LK.Z_FINISH) == 0                               # C 362
    @test LK.zlib_deflate_end!(ctx.zstate) == LK.Z_OK
    LK.free_zcontext(ctx)                                                                # (the stream layer's close would run zclose: this is by hand)
    @test LK.Sclose(parent) == 0
    pin = _sf_in(_sf_bytes(bufp, sizep))
    zin, cin = _zopen(ld, pin; format = LK.Z_F_DEFLATE)
    @test _read_all(zin) == vcat(data, data[101:300])
    @test LK.closeStream(ld, zin)
    sink = LK.Snew(FailSink(), LK.SIO_OUTPUT | LK.SIO_NBUF, LK.Sfilterfunctions)
    zf, cf = _zopen(ld, sink; format = LK.Z_F_DEFLATE, close_parent = true)
    @test LK.zwrite4(cf, data, 1, 100, LK.Z_SYNC_FLUSH) == -1                            # C 293-294
    @test LK.Sclose(zf) == -1                                                            # C 362-366, 385-389
    @test cf.zstate == C_NULL && cf.zhead == C_NULL
    @test sink.magic == LK.SIO_CMAGIC
end

@testset "z11 close: close_parent, the parent's state, the records" begin
    gd, ld = _env(_TL)
    parent = _sf_in(_zbytes("whatever"))                                                 # never read: initialized false, Z_OK (C 359-360)
    zs, ctx = _zopen(ld, parent; format = LK.Z_F_GZIP)
    @test !ctx.initialized
    @test LK.closeStream(ld, zs)
    @test parent.magic == LK.SIO_CMAGIC && parent.upstream === nothing && ctx.zstate == C_NULL
    parent, bufp, sizep = _sf_out()                                                      # close_parent false (C 378-380)
    zs, ctx = _zopen(ld, parent; format = LK.Z_F_RAW_DEFLATE, close_parent = false)
    @test LK.Sfwrite(_text(100), 1, 100, zs) == 100
    @test LK.closeStream(ld, zs)
    @test parent.magic == LK.SIO_MAGIC && parent.upstream === nothing
    n0 = sizep[]
    @test LK.Sfwrite(UInt8[0x2a], 1, 1, parent) == 1
    @test LK.Sclose(parent) == 0
    @test sizep[] == n0 + 1 && _sf_bytes(bufp, sizep)[end] == 0x2a
    comp = _compress(ld, _text(100); format = LK.Z_F_DEFLATE)                            # read to the end: inflateEnd (C 358)
    parent = _sf_in(comp)
    zs, ctx = _zopen(ld, parent; format = LK.Z_F_DEFLATE)
    @test _read_all(zs) == _text(100)
    @test ctx.initialized
    @test LK.closeStream(ld, zs)
    @test parent.magic == LK.SIO_CMAGIC
end
