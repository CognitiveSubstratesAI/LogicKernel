# CLASS: test
# ORIGINAL: ZLIB1 piece Z1's gate - the typed ccall wrappers of libz (Zlib_jll, D-1002) and the z_stream/gz_header records that src/pl-zlib.jl binds for
# packages/zlib/zlib4pl.c (packages-zlib 9f4be6fe; the C line numbers are in the wrappers' comments). Every expectation is derived, none invented: from the
# C (which calls it makes, which values it tests: Z_OK, Z_STREAM_END, Z_BUF_ERROR..., `zhead.done`), from the answers the library itself gives (an error code
# is what the library returns for the input that provokes it: a garbage header, a truncated stream, an uninitialised stream, a dictionary stream, a wrong
# `stream_size`), from round trips (compress then uncompress: equal), from the format definitions (RFC 1950/1952: the gzip magic and method bytes, the zlib header's
# check value, the Adler-32 of the data) and from the compressed bytes read back (the gzip header's own OS/xflags/mtime bytes against `gz_header`). NEVER from
# compressed byte values: the compressed bytes are zlib's and may differ across versions (DIVERGES 1). No term type is used. Nothing here has run (no
# Julia process was started to write this file).
using Test, LogicKernel
import Zlib_jll
const LK = LogicKernel

_zbytes(s::String) = Vector{UInt8}(codeunits(s))

# deterministic pseudo-random bytes (a 32-bit LCG: the wrap-around is the point), so the file needs no Random
function _lcg_bytes(n::Int, seed::UInt32=0x1234abcd)
    x = seed
    out = Vector{UInt8}(undef, n)
    for i in 1:n
        x = x * UInt32(1664525) + UInt32(1013904223)
        out[i] = UInt8(x >> 24)
    end
    return out
end

# Adler-32 of RFC 1950, the value zlib keeps in `strm->adler` for the zlib wrapper
function _adler32(data::Vector{UInt8})::UInt
    a = UInt(1)
    b = UInt(0)
    for x in data
        a = (a + x) % 65521
        b = (b + a) % 65521
    end
    return (b << 16) | a
end

const _Z_TEXT = repeat(_zbytes("the quick brown fox jumps over the lazy dog. "), 224)[1:10000]
const _Z_INPUTS = Pair{String, Vector{UInt8}}[
    "empty" => UInt8[],
    "one byte" => UInt8[0x61],
    "10 KB repeated text" => _Z_TEXT,
    "20 KB pseudo-random" => _lcg_bytes(20000)
]

# One-shot deflate of `data` through the wrappers: window bits `wbits` (15 zlib, 31 gzip, -15 raw), `flush` as the only call (Z_FINISH ends the stream).
# `wbits === nothing` uses the `deflateInit` wrapper (zlib format). The record is freed before returning, so the fields are copied out first.
function _z_deflate(data::Vector{UInt8}, wbits, level::Integer; flush::Cint=LK.Z_FINISH)
    strm = LK.z_stream_alloc()
    try
        init_rc = if wbits === nothing
            LK.zlib_deflate_init!(strm, Cint(level))
        else
            LK.zlib_deflate_init2!(
                strm,
                Cint(level),
                LK.Z_DEFLATED,
                Cint(wbits),
                LK.MAX_MEM_LEVEL,
                LK.Z_DEFAULT_STRATEGY
            )
        end
        init_rc == LK.Z_OK || return (; init_rc)
        out = Vector{UInt8}(undef, 2 * length(data) + 256)
        local rc, nout, total_in, avail_in, avail_out, adler, in_adv, out_adv
        GC.@preserve data out begin
            LK.z_stream_set_next_in!(strm, pointer(data))
            LK.z_stream_set_avail_in!(strm, UInt32(length(data)))
            LK.z_stream_set_next_out!(strm, pointer(out))
            LK.z_stream_set_avail_out!(strm, UInt32(length(out)))
            rc = LK.zlib_deflate!(strm, flush)
            nout = Int(LK.z_stream_total_out(strm))
            total_in = Int(LK.z_stream_total_in(strm))
            avail_in = Int(LK.z_stream_avail_in(strm))
            avail_out = Int(LK.z_stream_avail_out(strm))
            adler = LK.z_stream_adler(strm)
            in_adv = LK.z_stream_next_in(strm) - pointer(data)
            out_adv = LK.z_stream_next_out(strm) - pointer(out)
        end
        end_rc = LK.zlib_deflate_end!(strm)
        return (;
            init_rc,
            rc,
            out=out[1:nout],
            nout,
            total_in,
            avail_in,
            avail_out,
            adler,
            in_adv,
            out_adv,
            end_rc,
            outcap=length(out)
        )
    finally
        LK.z_stream_free(strm)
    end
end

# One-shot inflate of `comp` through the wrappers. `wbits === nothing` uses the `inflateInit` wrapper (zlib format), otherwise `inflateInit2`;
# `header` also calls `inflateGetHeader` first (the C's auto-detect arm). `flush` is the only inflate call's flush.
function _z_inflate(
    comp::Vector{UInt8};
    wbits=nothing,
    header::Bool=false,
    flush::Cint=LK.Z_NO_FLUSH,
    outcap::Int=1 << 16
)
    strm = LK.z_stream_alloc()
    head = LK.gz_header_alloc()
    try
        init_rc = if wbits === nothing
            LK.zlib_inflate_init!(strm)
        else
            LK.zlib_inflate_init2!(strm, Cint(wbits))
        end
        init_rc == LK.Z_OK || return (; init_rc)
        hdr_rc = header ? LK.zlib_inflate_get_header!(strm, head) : LK.Z_OK
        out = Vector{UInt8}(undef, outcap)
        local rc, nout, total_in, avail_in, adler, in_adv, msg
        GC.@preserve comp out begin
            LK.z_stream_set_next_in!(strm, pointer(comp))
            LK.z_stream_set_avail_in!(strm, UInt32(length(comp)))
            LK.z_stream_set_next_out!(strm, pointer(out))
            LK.z_stream_set_avail_out!(strm, UInt32(length(out)))
            rc = LK.zlib_inflate!(strm, flush)
            nout = Int(LK.z_stream_total_out(strm))
            total_in = Int(LK.z_stream_total_in(strm))
            avail_in = Int(LK.z_stream_avail_in(strm))
            adler = LK.z_stream_adler(strm)
            in_adv = LK.z_stream_next_in(strm) - pointer(comp)
            msg = LK.z_stream_msg(strm)
        end
        end_rc = LK.zlib_inflate_end!(strm)
        return (;
            init_rc, hdr_rc, rc, out=out[1:nout], nout, total_in, avail_in, adler, in_adv,
            msg, end_rc,
            done=LK.gz_header_done(head), os=LK.gz_header_os(head),
            xflags=LK.gz_header_xflags(head), time=LK.gz_header_time(head)
        )
    finally
        LK.gz_header_free(head)
        LK.z_stream_free(strm)
    end
end

@testset "one libz in the process, the one Zlib_jll names" begin
    # `libzstd` also contains "libz": the file name must START with `libz.`
    loaded = filter(p -> startswith(basename(p), "libz."), Base.Libc.Libdl.dllist())
    @test length(loaded) == 1
    @test Zlib_jll.libz_path == loaded[1]
    @test Zlib_jll.libz_handle == Base.Libc.Libdl.dlopen(Zlib_jll.libz)
    @test LK.libz == Zlib_jll.libz

    v = LK.zlib_version()
    println("zlibVersion() = ", v, "  (", loaded[1], ")")
    @test occursin(r"^1\.\d+", v)           # zlib checks only the first character of the version string, which is "1"
end

@testset "the records: sizes (the library's own check), zeroing, offsets (read back from what zlib wrote)" begin
    @test LK.Z_STREAM_SIZE == 112
    @test LK.GZ_HEADER_SIZE == 80

    # `*Init_` accepts exactly sizeof(z_stream): the library answers Z_VERSION_ERROR for any other `stream_size` before it touches the record
    function raw_init(strm, size)
        return ccall(
            (:deflateInit_, LK.libz), Cint, (Ptr{Cvoid}, Cint, Ptr{UInt8}, Cint),
            strm, 6, ccall((:zlibVersion, LK.libz), Ptr{UInt8}, ()), size
        )
    end
    s = LK.z_stream_alloc()
    @test raw_init(s, 111) == LK.Z_VERSION_ERROR
    @test raw_init(s, 113) == LK.Z_VERSION_ERROR
    @test raw_init(s, 0) == LK.Z_VERSION_ERROR
    @test raw_init(s, 112) == LK.Z_OK
    @test LK.zlib_deflate_end!(s) == LK.Z_OK
    LK.z_stream_free(s)

    # a fresh record is all zero bytes, on its whole length
    s = LK.z_stream_alloc()
    h = LK.gz_header_alloc()
    @test s != C_NULL && h != C_NULL
    @test all(i -> unsafe_load(Ptr{UInt8}(s + i)) == 0x00, 0:(LK.Z_STREAM_SIZE - 1))
    @test all(i -> unsafe_load(Ptr{UInt8}(h + i)) == 0x00, 0:(LK.GZ_HEADER_SIZE - 1))
    @test LK.z_stream_next_in(s) == C_NULL
    @test LK.z_stream_avail_in(s) == 0
    @test LK.z_stream_total_in(s) == 0
    @test LK.z_stream_next_out(s) == C_NULL
    @test LK.z_stream_avail_out(s) == 0
    @test LK.z_stream_total_out(s) == 0
    @test LK.z_stream_adler(s) == 0
    @test LK.z_stream_msg(s) === nothing
    @test LK.gz_header_done(h) == 0

    # the writers and readers touch their own field and no neighbour
    buf = zeros(UInt8, 8)
    GC.@preserve buf begin
        LK.z_stream_set_next_in!(s, pointer(buf))
        LK.z_stream_set_avail_in!(s, UInt32(0x01020304))
        LK.z_stream_set_next_out!(s, pointer(buf, 5))
        LK.z_stream_set_avail_out!(s, UInt32(0x0a0b0c0d))
        @test LK.z_stream_next_in(s) == pointer(buf)
        @test LK.z_stream_avail_in(s) == 0x01020304
        @test LK.z_stream_next_out(s) == pointer(buf, 5)
        @test LK.z_stream_avail_out(s) == 0x0a0b0c0d
        @test LK.z_stream_total_in(s) == 0 && LK.z_stream_total_out(s) == 0 &&
            LK.z_stream_adler(s) == 0
        # the uInt fields sit in 8-byte slots: the 4 padding bytes after each stay zero
        @test unsafe_load(Ptr{UInt32}(s + LK.Z_STREAM_OFF_AVAIL_IN + 4)) == 0
        @test unsafe_load(Ptr{UInt32}(s + LK.Z_STREAM_OFF_AVAIL_OUT + 4)) == 0
    end
    LK.z_stream_free(s)
    LK.gz_header_free(h)

    # the offsets by what zlib itself wrote into the record: a zlib-format deflate of 100 bytes
    data = _zbytes(repeat("abcdefghij", 10))
    r = _z_deflate(data, 15, 6)
    @test r.init_rc == LK.Z_OK && r.rc == LK.Z_STREAM_END
    @test r.total_in == 100                       # total_in, offset 16
    @test r.nout == length(r.out) && r.nout > 0   # total_out, offset 40
    @test r.avail_in == 0                         # avail_in, offset 8
    @test r.in_adv == 100                         # next_in, offset 0: advanced by the bytes consumed
    @test r.out_adv == r.nout                     # next_out, offset 24: advanced by the bytes produced
    @test r.avail_out == r.outcap - r.nout        # avail_out, offset 32
    @test r.adler == _adler32(data)               # adler, offset 96: the Adler-32 of the input (zlib wrapper)
end

@testset "an uninitialised (zeroed) record: every entry point answers Z_STREAM_ERROR" begin
    # zlib's state check refuses a stream with no allocator functions and no state; this also pins that each wrapper reaches its own library entry point
    s = LK.z_stream_alloc()
    h = LK.gz_header_alloc()
    @test LK.zlib_inflate!(s, LK.Z_NO_FLUSH) == LK.Z_STREAM_ERROR
    @test LK.zlib_inflate_end!(s) == LK.Z_STREAM_ERROR
    @test LK.zlib_inflate_get_header!(s, h) == LK.Z_STREAM_ERROR
    @test LK.zlib_deflate!(s, LK.Z_FINISH) == LK.Z_STREAM_ERROR
    @test LK.zlib_deflate_end!(s) == LK.Z_STREAM_ERROR
    LK.gz_header_free(h)
    LK.z_stream_free(s)
end

@testset "the Z_* constants are what the library answers" begin
    # Z_OK (init) and Z_STREAM_END (a finished stream)
    r = _z_deflate(_zbytes("hello"), 15, 6)
    @test r.init_rc == LK.Z_OK && r.init_rc == 0
    @test r.rc == LK.Z_STREAM_END && r.rc == 1 && r.end_rc == LK.Z_OK
    i = _z_inflate(r.out)
    @test i.init_rc == LK.Z_OK && i.rc == LK.Z_STREAM_END && i.end_rc == LK.Z_OK
    @test i.out == _zbytes("hello")

    # Z_DATA_ERROR: a zlib header whose check value is wrong ((0x0102 mod 31) != 0); the library sets a message text (its words are not pinned)
    i = _z_inflate(UInt8[0x01, 0x02, 0x03, 0x04, 0x05])
    @test i.rc == LK.Z_DATA_ERROR && i.rc == -3
    @test i.msg isa String && !isempty(i.msg)

    # Z_NEED_DICT: a zlib header with the FDICT flag set (0x78 0xBB: (0x78BB mod 31) == 0, FDICT = 0x20 of the second byte) and a 4-byte dictionary id
    i = _z_inflate(UInt8[0x78, 0xbb, 0x00, 0x00, 0x00, 0x01])
    @test i.rc == LK.Z_NEED_DICT && i.rc == 2

    # Z_BUF_ERROR: the input ends before the stream does and the caller said Z_FINISH
    # (incompressible data: zlib stores it, so a cut in the middle still leaves decodable bytes in front of the cut)
    rnd = _Z_INPUTS[4].second
    full = _z_deflate(rnd, 15, 6).out
    cut = full[1:(length(full) ÷ 2)]
    i = _z_inflate(cut; flush=LK.Z_FINISH)
    @test i.rc == LK.Z_BUF_ERROR && i.rc == -5
    @test i.nout > 0                              # it made progress before it ran out
    # ... and with Z_NO_FLUSH the same input is Z_OK, with all the input consumed (zread's "need more input" case, C 188)
    i = _z_inflate(cut; flush=LK.Z_NO_FLUSH)
    @test i.rc == LK.Z_OK && i.avail_in == 0 && i.nout > 0
    @test i.out == rnd[1:i.nout]                  # what it produced is a prefix of the data

    # Z_STREAM_ERROR is the answer for a bad parameter too: level 10, memLevel 0 and 10 (MAX_MEM_LEVEL is 9), a method that is not Z_DEFLATED
    # and a strategy beyond Z_FIXED (4)
    for (lv, m, wb, ml, st) in (
        (10, 8, 15, 9, 0),
        (6, 8, 15, 0, 0),
        (6, 8, 15, 10, 0),
        (6, 0, 15, 9, 0),
        (6, 8, 15, 9, 99)
    )
        s = LK.z_stream_alloc()
        @test LK.zlib_deflate_init2!(s, Cint(lv), Cint(m), Cint(wb), Cint(ml), Cint(st)) ==
            LK.Z_STREAM_ERROR
        LK.z_stream_free(s)
    end
    s = LK.z_stream_alloc()
    @test LK.zlib_deflate_init!(s, Cint(10)) == LK.Z_STREAM_ERROR
    LK.z_stream_free(s)
    # Z_DEFAULT_COMPRESSION is accepted, and so is every level 0-9 (rows of the round-trip matrix below)
    s = LK.z_stream_alloc()
    @test LK.zlib_deflate_init!(s, LK.Z_DEFAULT_COMPRESSION) == LK.Z_OK
    @test LK.zlib_deflate_end!(s) == LK.Z_OK
    LK.z_stream_free(s)

    # the flush values: Z_NO_FLUSH holds data back, Z_SYNC_FLUSH makes everything written so far decodable, Z_FINISH ends the stream
    data = _lcg_bytes(300)
    d = _z_deflate(data, 15, 6; flush=LK.Z_NO_FLUSH)
    @test d.rc == LK.Z_OK && d.avail_in == 0
    held = _z_inflate(d.out)
    @test held.rc != LK.Z_STREAM_END
    @test length(held.out) < length(data)
    d = _z_deflate(data, 15, 6; flush=LK.Z_SYNC_FLUSH)
    @test d.rc == LK.Z_OK && d.avail_in == 0
    flushed = _z_inflate(d.out)
    @test flushed.rc == LK.Z_OK                   # not at the end of the stream yet ...
    @test flushed.out == data                     # ... but every byte written is there
    d = _z_deflate(data, 15, 6; flush=LK.Z_FINISH)
    @test d.rc == LK.Z_STREAM_END
    @test LK.Z_NO_FLUSH == 0 && LK.Z_SYNC_FLUSH == 2 && LK.Z_FINISH == 4     # zlib.h
    @test LK.Z_DEFLATED == 8 && LK.MAX_WBITS == 15 && LK.MAX_MEM_LEVEL == 9 &&
        LK.Z_DEFAULT_COMPRESSION == -1 && LK.Z_DEFAULT_STRATEGY == 0
    @test LK.Z_MEM_ERROR == -4 && LK.Z_STREAM_ERROR == -2 && LK.Z_VERSION_ERROR == -6
end

@testset "round trips: three window forms x levels -1..9 x four inputs (properties, never bytes)" begin
    nrt = 0
    for (name, data) in _Z_INPUTS, level in -1:9
        # the zlib format through `deflateInit` and `inflateInit` (the C's format(deflate))
        d = _z_deflate(data, nothing, level)
        i = _z_inflate(d.out)
        @test d.init_rc == LK.Z_OK && d.rc == LK.Z_STREAM_END
        @test i.rc == LK.Z_STREAM_END && i.out == data && i.total_in == length(d.out)
        # the zlib format through `deflateInit2` with MAX_WBITS, and the auto-detect inflater (MAX_WBITS+32)
        d = _z_deflate(data, 15, level)
        @test d.rc == LK.Z_STREAM_END
        @test _z_inflate(d.out).out == data
        a = _z_inflate(d.out; wbits=47, header=true)
        @test a.rc == LK.Z_STREAM_END && a.out == data
        # gzip (MAX_WBITS+16), inflated as gzip and by the auto-detect inflater
        g = _z_deflate(data, 31, level)
        @test g.init_rc == LK.Z_OK && g.rc == LK.Z_STREAM_END
        @test _z_inflate(g.out; wbits=31).rc == LK.Z_STREAM_END
        @test _z_inflate(g.out; wbits=31).out == data
        ga = _z_inflate(g.out; wbits=47, header=true)
        @test ga.rc == LK.Z_STREAM_END && ga.out == data
        # raw deflate (-MAX_WBITS)
        r = _z_deflate(data, -15, level)
        @test r.init_rc == LK.Z_OK && r.rc == LK.Z_STREAM_END
        ri = _z_inflate(r.out; wbits=-15)
        @test ri.rc == LK.Z_STREAM_END && ri.out == data && ri.total_in == length(r.out)
        nrt += 1
    end
    @test nrt == 4 * 11

    # the level reaches the library: on repeated text level 9 is smaller than level 0 (stored), and the stored size is at least the data's
    c0 = _z_deflate(_Z_TEXT, 15, 0).out
    c9 = _z_deflate(_Z_TEXT, 15, 9).out
    @test length(c9) < length(_Z_TEXT) && length(c9) < length(c0)
    @test length(c0) >= length(_Z_TEXT)
end

@testset "the wrappers' formats are distinct: what each inflater accepts and refuses" begin
    data = _Z_TEXT
    z = _z_deflate(data, 15, 6).out
    g = _z_deflate(data, 31, 6).out
    r = _z_deflate(data, -15, 6).out

    # the format facts of RFC 1952 / 1950, not byte pins: gzip magic and method, a zlib header whose 16-bit value is a multiple of 31 with method 8
    @test g[1] == 0x1f && g[2] == 0x8b && g[3] == 0x08
    @test z[1] & 0x0f == 0x08 && (Int(z[1]) * 256 + Int(z[2])) % 31 == 0
    @test (g[1] != z[1])
    # the zlib wrapper ends with the big-endian Adler-32 of the data, the gzip trailer with CRC-32 and the length (ISIZE, little-endian)
    @test reinterpret(UInt32, reverse(z[(end - 3):end]))[1] == UInt32(_adler32(data))
    @test reinterpret(UInt32, g[(end - 3):end])[1] == UInt32(length(data))

    # zlib-format inflater: refuses gzip and raw data (header check); gzip inflater refuses the zlib wrapper; raw inflater accepts only raw
    @test _z_inflate(g).rc == LK.Z_DATA_ERROR
    @test _z_inflate(g; wbits=15).rc == LK.Z_DATA_ERROR
    @test _z_inflate(z; wbits=31).rc == LK.Z_DATA_ERROR
    zraw = _z_inflate(z; wbits=-15)
    @test !(zraw.rc == LK.Z_STREAM_END && zraw.out == data)
    @test _z_inflate(r; wbits=-15).rc == LK.Z_STREAM_END
    @test _z_inflate(r; wbits=47, header=true).rc == LK.Z_DATA_ERROR     # auto-detect knows gzip and zlib, not raw
    # init and init2 are the same inflater for the zlib format
    @test _z_inflate(z; wbits=15).out == data
    # the other direction of the header check: the zlib deflater's output is not what the gzip inflater wants, and vice versa
    @test _z_inflate(z; wbits=47, header=true).rc == LK.Z_STREAM_END
    @test _z_inflate(g; wbits=47, header=true).rc == LK.Z_STREAM_END
end

@testset "gz_header: inflateGetHeader fills it while inflate reads a gzip header (the field zread reads is `done`)" begin
    data = _Z_TEXT
    g = _z_deflate(data, 31, 6).out
    i = _z_inflate(g; wbits=47, header=true)
    @test i.hdr_rc == LK.Z_OK
    @test i.rc == LK.Z_STREAM_END
    @test i.done == 1                               # the whole header was read (C 215 tests `done < 0`: no gzip header at all)
    # the other fields are the bytes of the gzip header (RFC 1952: MTIME bytes 5-8 little-endian, XFL byte 9, OS byte 10), read back, not pinned
    @test i.time == UInt(g[5]) | (UInt(g[6]) << 8) | (UInt(g[7]) << 16) | (UInt(g[8]) << 24)
    @test i.xflags == Int(g[9])
    @test i.os == Int(g[10])

    # a zlib-wrapped stream has no gzip header: `done` is not 1 (the C's `zhead.done < 0` is how it recognises that, C 215)
    z = _z_deflate(data, 15, 6).out
    iz = _z_inflate(z; wbits=47, header=true)
    @test iz.hdr_rc == LK.Z_OK && iz.rc == LK.Z_STREAM_END
    @test iz.done != 1
    @test iz.done < 0
    # without inflateGetHeader nothing is written into the record
    @test _z_inflate(g; wbits=47, header=false).done == 0

    # the header is read in steps: a gzip stream cut inside its header leaves `done` at 0 and a partial stream
    i = _z_inflate(g[1:5]; wbits=47, header=true)
    @test i.rc == LK.Z_OK && i.done == 0
end

@testset "bookkeeping a multi-member reader relies on: input left over after the end of a stream (zread, C 224-)" begin
    data = _zbytes("first member")
    for wbits in (15, 31, -15)
        c = _z_deflate(data, wbits, 6).out
        tail = _zbytes("tail")
        i = _z_inflate(vcat(c, tail); wbits=wbits)
        @test i.rc == LK.Z_STREAM_END
        @test i.out == data
        @test i.avail_in == length(tail)            # exactly the bytes after the stream are left in the input ...
        @test i.in_adv == length(c)                 # ... and next_in points at them
        @test i.total_in == length(c)
    end
    # the same stream read in one byte per call of the input side: inflate keeps its state across calls
    c = _z_deflate(_Z_TEXT, 31, 6).out
    strm = LK.z_stream_alloc()
    @test LK.zlib_inflate_init2!(strm, Cint(31)) == LK.Z_OK
    out = Vector{UInt8}(undef, 1 << 15)
    rc = LK.Z_OK
    GC.@preserve c out begin
        LK.z_stream_set_next_out!(strm, pointer(out))
        LK.z_stream_set_avail_out!(strm, UInt32(length(out)))
        for k in 1:length(c)
            LK.z_stream_set_next_in!(strm, pointer(c, k))
            LK.z_stream_set_avail_in!(strm, UInt32(1))
            rc = LK.zlib_inflate!(strm, LK.Z_NO_FLUSH)
            rc == LK.Z_OK || break
        end
        @test rc == LK.Z_STREAM_END
        @test Int(LK.z_stream_total_out(strm)) == length(_Z_TEXT)
        @test out[1:length(_Z_TEXT)] == _Z_TEXT
    end
    @test LK.zlib_inflate_end!(strm) == LK.Z_OK
    LK.z_stream_free(strm)
end
