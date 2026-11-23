# CLASS: code
# COPYRIGHT: Copyright (c)  2006-2015, University of Amsterdam, VU University Amsterdam
# allow-new-artifact: packages/zlib C port (Phase 1), ZLIB1 piece Z1: the carrier binding (Zlib_jll) of packages/zlib/zlib4pl.c
#
# ZLIB1 piece Z1 (packages/zlib/zlib4pl.c, packages-zlib 9f4be6fe at swipl-devel af9e2e7e; the file is not vendored yet, read from the
# submodule's object store; evidence/R2/zlib_plan.md sections 1-3 and 6 Z1): THE CARRIER BINDING. D-1002 (Shivaji): the foreign C libraries of the
# packages are implemented as `ccall`s to the Julia JLLs; Project.toml allows exactly Zlib_jll (the stdlib JLL carrying libz), PCRE2_jll and
# PrecompileTools. Below: the Z_* and window constants the C uses (values read from zlib.h / zconf.h, checked by behaviour in
# test/core_lang/test_zlib_ccall.jl), the layout of `z_stream` (112 bytes) and `gz_header` (80 bytes) as offsets (x86-64, measured by a C `offsetof`
# probe, zlib_plan.md section 1), `calloc`'ed records with typed field accessors, and the 9 library entry points zlib4pl.c calls as typed
# wrappers (C line numbers in each comment). NO `# UPSTREAM:` header line: `packages/zlib` is a gitlink at the pin, not a blob of
# swipl-devel (as src/pl-json.jl). NOT registered anywhere; nothing calls these yet. The filter (`zread`, `zwrite4`, `zclose`) and `zopen/3` are the
# next pieces (Z2, Z3). The wrappers carry generic names (`zlib_inflate!`, `zlib_deflate!`) so that the zip port (pl-zip.c, minizip) can reuse
# this file. Nothing here has run (no Julia process was started).
#
# DIVERGES (file-wide):
#   1. The compression library is Julia's Zlib_jll, a platform library (as GMP): the compressed bytes are zlib's and may differ across zlib versions
#      (the oracle links the system libz 1.3, the JLL is 1.3.2; 150 one-shot outputs were equal, zlib_plan.md F4). The tests pin round trips and the
#      protocol, never compressed bytes.
#   2. `z_stream` and `gz_header` are `Libc.calloc`'ed by `z_stream_alloc`/`gz_header_alloc` (the C embeds them in `z_context`, allocated with
#      `PL_malloc` + `memset`) and released by `z_stream_free`/`gz_header_free` in the close path after `inflateEnd`/`deflateEnd`; there is NO
#      finalizer (a ccall from the GC thread against an ended stream risks a double free). zalloc/zfree/opaque stay NULL: zlib's own allocator. The
#      records must not move for the life of the stream (zlib keeps `state->strm == strm` and, for `inflateGetHeader`, the header pointer).
#   3. The `inflateInit`, `inflateInit2`, `deflateInit` and `deflateInit2` macros of zlib.h are the `_` entry points. The version argument is the
#      library's own `zlibVersion()` string, not the header's `ZLIB_VERSION` (zlib compares only its first character); the size argument is
#      `Z_STREAM_SIZE` (112).
#   4. The wrappers take the raw `Ptr{Cvoid}` of the record; the caller sets `next_in`/`next_out` through the accessors, from a Vector it keeps alive with
#      `GC.@preserve` for the call (the pointer discipline of zlib_plan.md section 4: the filter derives them at every entry). The C's `Bytef *` fields
#      are `Ptr{UInt8}`.

using Zlib_jll: libz

# PORT: packages/zlib/zlib4pl.c Z_NO_FLUSH, Z_SYNC_FLUSH, Z_FINISH (277), Z_OK, Z_STREAM_END, Z_NEED_DICT, Z_STREAM_ERROR, Z_DATA_ERROR, Z_MEM_ERROR, Z_BUF_ERROR (zread, zwrite4, zclose)
const Z_NO_FLUSH = Cint(0)
const Z_SYNC_FLUSH = Cint(2)
const Z_FINISH = Cint(4)
const Z_OK = Cint(0)
const Z_STREAM_END = Cint(1)
const Z_NEED_DICT = Cint(2)
const Z_STREAM_ERROR = Cint(-2)
const Z_DATA_ERROR = Cint(-3)
const Z_MEM_ERROR = Cint(-4)
const Z_BUF_ERROR = Cint(-5)
# `Z_VERSION_ERROR` is what `*Init*_` answers for a wrong `stream_size`; the C never tests it (any rc != Z_OK is "initialization failed").
const Z_VERSION_ERROR = Cint(-6)
# PORT: packages/zlib/zlib4pl.c Z_DEFLATED, MAX_WBITS (160-167, 469-471), MAX_MEM_LEVEL (469-471), the default strategy 0 (469-471)
const Z_DEFLATED = Cint(8)
const Z_DEFAULT_COMPRESSION = Cint(-1)
const Z_DEFAULT_STRATEGY = Cint(0)
const MAX_WBITS = Cint(15)
# zconf.h: 9 unless MAXSEG_64K (measured by a C probe, zlib_plan.md section 1).
const MAX_MEM_LEVEL = Cint(9)

# `sizeof(z_stream)` and `sizeof(gz_header)` on x86-64 (zlib_plan.md section 1: sizeof by a C probe against zlib.h).
const Z_STREAM_SIZE = 112
const GZ_HEADER_SIZE = 80
# The byte offsets of the z_stream fields (`offsetof`, x86-64); uInt fields are followed by 4 bytes of padding.
const Z_STREAM_OFF_NEXT_IN = 0       # Bytef *
const Z_STREAM_OFF_AVAIL_IN = 8      # uInt
const Z_STREAM_OFF_TOTAL_IN = 16     # uLong
const Z_STREAM_OFF_NEXT_OUT = 24     # Bytef *
const Z_STREAM_OFF_AVAIL_OUT = 32    # uInt
const Z_STREAM_OFF_TOTAL_OUT = 40    # uLong
const Z_STREAM_OFF_MSG = 48          # char *
const Z_STREAM_OFF_STATE = 56        # struct internal_state *
const Z_STREAM_OFF_ZALLOC = 64
const Z_STREAM_OFF_ZFREE = 72
const Z_STREAM_OFF_OPAQUE = 80
const Z_STREAM_OFF_DATA_TYPE = 88    # int
const Z_STREAM_OFF_ADLER = 96        # uLong
const Z_STREAM_OFF_RESERVED = 104    # uLong
# The byte offsets of the gz_header fields; `done` (72) is the one field zread reads (C 215: `ctx->zhead.done < 0`).
const GZ_HEADER_OFF_TEXT = 0         # int
const GZ_HEADER_OFF_TIME = 8         # uLong
const GZ_HEADER_OFF_XFLAGS = 16      # int
const GZ_HEADER_OFF_OS = 20          # int
const GZ_HEADER_OFF_EXTRA = 24       # Bytef *
const GZ_HEADER_OFF_EXTRA_LEN = 32   # uInt
const GZ_HEADER_OFF_EXTRA_MAX = 36   # uInt
const GZ_HEADER_OFF_NAME = 40        # Bytef *
const GZ_HEADER_OFF_NAME_MAX = 48    # uInt
const GZ_HEADER_OFF_COMMENT = 56     # Bytef *
const GZ_HEADER_OFF_COMM_MAX = 64    # uInt
const GZ_HEADER_OFF_HCRC = 68        # int
const GZ_HEADER_OFF_DONE = 72        # int

# PORT: packages/zlib/zlib4pl.c alloc_zcontext (71-81, 124-135): the `z_stream zstate` and `gz_header zhead` members, zeroed
# DIVERGES: 2 (file header). A NULL from calloc is an out-of-memory error, as the C's `PL_malloc` does not return NULL.
"A zeroed `z_stream` record (112 bytes, `Libc.calloc`); release it with `z_stream_free` after `inflateEnd`/`deflateEnd`."
function z_stream_alloc()::Ptr{Cvoid}
    p = Libc.calloc(1, Z_STREAM_SIZE)
    p == C_NULL && throw(OutOfMemoryError())
    return p
end

# PORT: packages/zlib/zlib4pl.c free_zcontext (the PL_free of the context)
"Release a record made by `z_stream_alloc` (a NULL `strm` is a no-op)."
function z_stream_free(strm::Ptr{Cvoid})::Nothing
    Libc.free(strm)
    return nothing
end

# PORT: packages/zlib/zlib4pl.c alloc_zcontext (71-81, 124-135): the `gz_header zhead` member, zeroed (zread, C 166, `memset(&ctx->zhead, 0, sizeof(ctx->zhead))`)
"A zeroed `gz_header` record (80 bytes, `Libc.calloc`); release it with `gz_header_free`."
function gz_header_alloc()::Ptr{Cvoid}
    p = Libc.calloc(1, GZ_HEADER_SIZE)
    p == C_NULL && throw(OutOfMemoryError())
    return p
end

"Release a record made by `gz_header_alloc` (a NULL `head` is a no-op)."
function gz_header_free(head::Ptr{Cvoid})::Nothing
    Libc.free(head)
    return nothing
end

# PORT: packages/zlib/zlib4pl.c sync_stream (112-121), zread (140-147), zwrite4 (264-277): the next_in/avail_in/next_out/avail_out/total_*/msg/adler fields
# DIVERGES: 4. The field readers and writers; the writers take the pointer (`next_*`) or the count (`avail_*`).
"`strm->next_in`."
z_stream_next_in(strm::Ptr{Cvoid})::Ptr{UInt8} = unsafe_load(Ptr{Ptr{UInt8}}(strm + Z_STREAM_OFF_NEXT_IN))
"Set `strm->next_in`."
function z_stream_set_next_in!(strm::Ptr{Cvoid}, p::Ptr{UInt8})::Nothing
    unsafe_store!(Ptr{Ptr{UInt8}}(strm + Z_STREAM_OFF_NEXT_IN), p)
    return nothing
end
"`strm->avail_in`."
z_stream_avail_in(strm::Ptr{Cvoid})::UInt32 = unsafe_load(Ptr{UInt32}(strm + Z_STREAM_OFF_AVAIL_IN))
"Set `strm->avail_in`."
function z_stream_set_avail_in!(strm::Ptr{Cvoid}, n::UInt32)::Nothing
    unsafe_store!(Ptr{UInt32}(strm + Z_STREAM_OFF_AVAIL_IN), n)
    return nothing
end
"`strm->total_in`."
z_stream_total_in(strm::Ptr{Cvoid})::UInt = unsafe_load(Ptr{UInt}(strm + Z_STREAM_OFF_TOTAL_IN))
"`strm->next_out`."
z_stream_next_out(strm::Ptr{Cvoid})::Ptr{UInt8} = unsafe_load(Ptr{Ptr{UInt8}}(strm + Z_STREAM_OFF_NEXT_OUT))
"Set `strm->next_out`."
function z_stream_set_next_out!(strm::Ptr{Cvoid}, p::Ptr{UInt8})::Nothing
    unsafe_store!(Ptr{Ptr{UInt8}}(strm + Z_STREAM_OFF_NEXT_OUT), p)
    return nothing
end
"`strm->avail_out`."
z_stream_avail_out(strm::Ptr{Cvoid})::UInt32 = unsafe_load(Ptr{UInt32}(strm + Z_STREAM_OFF_AVAIL_OUT))
"Set `strm->avail_out`."
function z_stream_set_avail_out!(strm::Ptr{Cvoid}, n::UInt32)::Nothing
    unsafe_store!(Ptr{UInt32}(strm + Z_STREAM_OFF_AVAIL_OUT), n)
    return nothing
end
"`strm->total_out`."
z_stream_total_out(strm::Ptr{Cvoid})::UInt = unsafe_load(Ptr{UInt}(strm + Z_STREAM_OFF_TOTAL_OUT))
"`strm->adler`: the Adler-32 (zlib wrapper) or CRC-32 (gzip wrapper) of the data so far."
z_stream_adler(strm::Ptr{Cvoid})::UInt = unsafe_load(Ptr{UInt}(strm + Z_STREAM_OFF_ADLER))

# PORT: packages/zlib/zlib4pl.c zread (254-257): `ctx->zstate.msg`, the text zlib sets for an error
"`strm->msg` as a String, or `nothing` when it is NULL (zread tests `msg` before it falls back to its own text)."
function z_stream_msg(strm::Ptr{Cvoid})::Union{Nothing, String}
    p = unsafe_load(Ptr{Ptr{UInt8}}(strm + Z_STREAM_OFF_MSG))
    return p == C_NULL ? nothing : unsafe_string(p)
end

# PORT: packages/zlib/zlib4pl.c zread (215): `ctx->zhead.done`
"`head->done`: 1 once `inflate` has read the whole gzip header, 0 while it is being read, negative when there is none (a zlib or raw stream)."
gz_header_done(head::Ptr{Cvoid})::Cint = unsafe_load(Ptr{Cint}(head + GZ_HEADER_OFF_DONE))
"`head->os`, the operating-system byte of the gzip header."
gz_header_os(head::Ptr{Cvoid})::Cint = unsafe_load(Ptr{Cint}(head + GZ_HEADER_OFF_OS))
"`head->xflags`, the extra-flags byte of the gzip header."
gz_header_xflags(head::Ptr{Cvoid})::Cint = unsafe_load(Ptr{Cint}(head + GZ_HEADER_OFF_XFLAGS))
"`head->time`, the modification time of the gzip header."
gz_header_time(head::Ptr{Cvoid})::UInt = unsafe_load(Ptr{UInt}(head + GZ_HEADER_OFF_TIME))

# The library's version string: the first character is what `*Init*_` checks.
# DIVERGES: 3.
_zlib_version_ptr()::Ptr{UInt8} = ccall((:zlibVersion, libz), Ptr{UInt8}, ())

"zlib's `zlibVersion()` as a String (\"1.3.2\" for Julia 1.13's Zlib_jll)."
function zlib_version()::String
    return unsafe_string(_zlib_version_ptr())
end

# PORT: packages/zlib/zlib4pl.c zread (162): inflateInit
# DIVERGES: 3. `inflateInit(strm)` is `inflateInit_(strm, ZLIB_VERSION, sizeof(z_stream))`: the zlib wrapper, 15-bit window.
"`inflateInit`: start an inflater for the zlib format (pl `format(deflate)`); `Z_OK` or an error code."
function zlib_inflate_init!(strm::Ptr{Cvoid})::Cint
    return ccall(
        (:inflateInit_, libz), Cint, (Ptr{Cvoid}, Ptr{UInt8}, Cint),
        strm, _zlib_version_ptr(), Cint(Z_STREAM_SIZE)
    )
end

# PORT: packages/zlib/zlib4pl.c zread (160, 164, 167): inflateInit2 with MAX_WBITS+16 (gzip), -MAX_WBITS (raw deflate), MAX_WBITS+32 (auto-detect)
# DIVERGES: 3.
"`inflateInit2` with `windowBits` (`MAX_WBITS+16` gzip, `-MAX_WBITS` raw deflate, `MAX_WBITS+32` gzip or zlib auto-detect): `Z_OK` or an error code."
function zlib_inflate_init2!(strm::Ptr{Cvoid}, window_bits::Cint)::Cint
    return ccall(
        (:inflateInit2_, libz), Cint, (Ptr{Cvoid}, Cint, Ptr{UInt8}, Cint),
        strm, window_bits, _zlib_version_ptr(), Cint(Z_STREAM_SIZE)
    )
end

# PORT: packages/zlib/zlib4pl.c zread (168): inflateGetHeader
"`inflateGetHeader`: make `inflate` fill the `gz_header` `head` while it reads a gzip header; `Z_OK`, or `Z_STREAM_ERROR` for a stream that is not initialised (the C prints a debug line only)."
function zlib_inflate_get_header!(strm::Ptr{Cvoid}, head::Ptr{Cvoid})::Cint
    return ccall((:inflateGetHeader, libz), Cint, (Ptr{Cvoid}, Ptr{Cvoid}), strm, head)
end

# PORT: packages/zlib/zlib4pl.c zread (181): inflate
"`inflate(strm, flush)`: `Z_OK`, `Z_STREAM_END`, `Z_NEED_DICT`, `Z_DATA_ERROR`, `Z_MEM_ERROR`, `Z_BUF_ERROR` or `Z_STREAM_ERROR`."
function zlib_inflate!(strm::Ptr{Cvoid}, flush::Cint)::Cint
    return ccall((:inflate, libz), Cint, (Ptr{Cvoid}, Cint), strm, flush)
end

# PORT: packages/zlib/zlib4pl.c zread (224), zclose (358): inflateEnd
"`inflateEnd`: release the inflater's state; `Z_OK`, or `Z_STREAM_ERROR` for a stream that is not initialised."
function zlib_inflate_end!(strm::Ptr{Cvoid})::Cint
    return ccall((:inflateEnd, libz), Cint, (Ptr{Cvoid},), strm)
end

# PORT: packages/zlib/zlib4pl.c pl_zopen (473): deflateInit
# DIVERGES: 3. `deflateInit(strm, level)` is `deflateInit_(strm, level, ZLIB_VERSION, sizeof(z_stream))`: the zlib wrapper, 15-bit window, memLevel 8.
"`deflateInit`: start a deflater for the zlib format at `level` (`Z_DEFAULT_COMPRESSION` or 0-9); `Z_OK` or an error code."
function zlib_deflate_init!(strm::Ptr{Cvoid}, level::Cint)::Cint
    return ccall(
        (:deflateInit_, libz), Cint, (Ptr{Cvoid}, Cint, Ptr{UInt8}, Cint),
        strm, level, _zlib_version_ptr(), Cint(Z_STREAM_SIZE)
    )
end

# PORT: packages/zlib/zlib4pl.c pl_zopen (469, 471): deflateInit2(strm, level, Z_DEFLATED, MAX_WBITS+16 | -MAX_WBITS, MAX_MEM_LEVEL, 0)
# DIVERGES: 3.
"`deflateInit2`: start a deflater with `method` (`Z_DEFLATED`), `windowBits` (`MAX_WBITS+16` gzip, `-MAX_WBITS` raw deflate), `memLevel` and `strategy`; `Z_OK` or an error code."
function zlib_deflate_init2!(
        strm::Ptr{Cvoid}, level::Cint, method::Cint, window_bits::Cint, mem_level::Cint, strategy::Cint
    )::Cint
    return ccall(
        (:deflateInit2_, libz), Cint, (Ptr{Cvoid}, Cint, Cint, Cint, Cint, Cint, Ptr{UInt8}, Cint),
        strm, level, method, window_bits, mem_level, strategy,
        _zlib_version_ptr(), Cint(Z_STREAM_SIZE)
    )
end

# PORT: packages/zlib/zlib4pl.c zwrite4 (277): deflate
"`deflate(strm, flush)` with `flush` one of `Z_NO_FLUSH`, `Z_SYNC_FLUSH`, `Z_FINISH`: `Z_OK`, `Z_STREAM_END`, `Z_BUF_ERROR` or `Z_STREAM_ERROR`."
function zlib_deflate!(strm::Ptr{Cvoid}, flush::Cint)::Cint
    return ccall((:deflate, libz), Cint, (Ptr{Cvoid}, Cint), strm, flush)
end

# PORT: packages/zlib/zlib4pl.c zclose (364, 366): deflateEnd
"`deflateEnd`: release the deflater's state; `Z_OK`, or `Z_STREAM_ERROR` for a stream that is not initialised."
function zlib_deflate_end!(strm::Ptr{Cvoid})::Cint
    return ccall((:deflateEnd, libz), Cint, (Ptr{Cvoid},), strm)
end
