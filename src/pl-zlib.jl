# CLASS: code
# COPYRIGHT: Copyright (c)  2006-2015, University of Amsterdam, VU University Amsterdam
# allow-new-artifact: packages/zlib C port (Phase 1), ZLIB1 piece Z1: the carrier binding (Zlib_jll) of packages/zlib/zlib4pl.c
#
# ZLIB1 piece Z1 (packages/zlib/zlib4pl.c, packages-zlib 9f4be6fe at swipl-devel af9e2e7e; the file is not vendored yet, read from the
# submodule's object store; evidence/R2/zlib_plan.md sections 1-3 and 6 Z1): THE CARRIER BINDING. D-1002 (Shivaji): the foreign C libraries of the
# packages are implemented as `ccall`s to the Julia JLLs; Project.toml allows exactly Zlib_jll (the stdlib JLL carrying libz) and
# PrecompileTools (the PCRE branch adds PCRE2_jll beside them at integration). Below: the Z_* and window constants the C uses (values read from zlib.h / zconf.h, checked by behaviour in
# test/core_lang/test_zlib_ccall.jl), the layout of `z_stream` (112 bytes) and `gz_header` (80 bytes) as offsets (x86-64, measured by a C `offsetof`
# probe, zlib_plan.md section 1), `calloc`'ed records with typed field accessors, and the 9 library entry points zlib4pl.c calls as typed
# wrappers (C line numbers in each comment). NO `# UPSTREAM:` header line: `packages/zlib` is a gitlink at the pin, not a blob of
# swipl-devel (as src/pl-json.jl). Z1 is the wrappers; the filter (Z2) and `zopen/3` with the registration (Z3) follow
# in this file. The wrappers carry generic names (`zlib_inflate!`, `zlib_deflate!`) so that the zip port (pl-zip.c, minizip) can reuse
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
z_stream_next_in(strm::Ptr{Cvoid})::Ptr{UInt8} =
    unsafe_load(Ptr{Ptr{UInt8}}(strm + Z_STREAM_OFF_NEXT_IN))
"Set `strm->next_in`."
function z_stream_set_next_in!(strm::Ptr{Cvoid}, p::Ptr{UInt8})::Nothing
    unsafe_store!(Ptr{Ptr{UInt8}}(strm + Z_STREAM_OFF_NEXT_IN), p)
    return nothing
end
"`strm->avail_in`."
z_stream_avail_in(strm::Ptr{Cvoid})::UInt32 =
    unsafe_load(Ptr{UInt32}(strm + Z_STREAM_OFF_AVAIL_IN))
"Set `strm->avail_in`."
function z_stream_set_avail_in!(strm::Ptr{Cvoid}, n::UInt32)::Nothing
    unsafe_store!(Ptr{UInt32}(strm + Z_STREAM_OFF_AVAIL_IN), n)
    return nothing
end
"`strm->total_in`."
z_stream_total_in(strm::Ptr{Cvoid})::UInt =
    unsafe_load(Ptr{UInt}(strm + Z_STREAM_OFF_TOTAL_IN))
"`strm->next_out`."
z_stream_next_out(strm::Ptr{Cvoid})::Ptr{UInt8} =
    unsafe_load(Ptr{Ptr{UInt8}}(strm + Z_STREAM_OFF_NEXT_OUT))
"Set `strm->next_out`."
function z_stream_set_next_out!(strm::Ptr{Cvoid}, p::Ptr{UInt8})::Nothing
    unsafe_store!(Ptr{Ptr{UInt8}}(strm + Z_STREAM_OFF_NEXT_OUT), p)
    return nothing
end
"`strm->avail_out`."
z_stream_avail_out(strm::Ptr{Cvoid})::UInt32 =
    unsafe_load(Ptr{UInt32}(strm + Z_STREAM_OFF_AVAIL_OUT))
"Set `strm->avail_out`."
function z_stream_set_avail_out!(strm::Ptr{Cvoid}, n::UInt32)::Nothing
    unsafe_store!(Ptr{UInt32}(strm + Z_STREAM_OFF_AVAIL_OUT), n)
    return nothing
end
"`strm->total_out`."
z_stream_total_out(strm::Ptr{Cvoid})::UInt =
    unsafe_load(Ptr{UInt}(strm + Z_STREAM_OFF_TOTAL_OUT))
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
gz_header_xflags(head::Ptr{Cvoid})::Cint =
    unsafe_load(Ptr{Cint}(head + GZ_HEADER_OFF_XFLAGS))
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
    strm::Ptr{Cvoid}, level::Cint, method::Cint, window_bits::Cint, mem_level::Cint,
    strategy::Cint
)::Cint
    return ccall(
        (:deflateInit2_, libz), Cint,
        (Ptr{Cvoid}, Cint, Cint, Cint, Cint, Cint, Ptr{UInt8}, Cint),
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

# ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
# ZLIB1 piece Z2 (packages/zlib/zlib4pl.c lines 62-396): THE FILTER. The `z_context` record, `alloc_zcontext`/`free_zcontext`/
# `sync_stream`, the stream functions `zread`, `zwrite`/`zwrite4`, `zcontrol` and `zclose`, over Z1's wrappers and the stream
# filter of STREAMX (src/os/pl-stream.jl `AbstractSfilter`, `Snew(::AbstractSfilter, ...)`, `Sset_filter`, `Sfread`, `Sfwrite`; the model
# is src/pl-hashstream.jl). `zopen/3` and the registration are the Z3 part at the end of the file.
# BLIND-CODED: no Julia process ran when this was written.
#
# DIVERGES (the Z2 part of the file-wide list; 1-4 are in the header of the file):
#   5. THE RECORD. upstream's `IOFUNCTIONS zfunctions` table and the C context `z_context` are one Julia type, `ZContext{T}` (an
#      `AbstractSfilter`): the callbacks are the methods `Sfilter_read/write/close/control` on it. `zstate` and `zhead` (embedded structs in C)
#      are the `Ptr{Cvoid}` of the calloc'ed records of Z1 (DIVERGES 2): allocated by `alloc_zcontext`, freed (and set to NULL) by
#      `free_zcontext`, which is also upstream's `PL_free(ctx)`. `zformat` is four `Int` constants `Z_F_*` (a new `@enum` would need an `_enum_hash`
#      manifest entry), `close_parent`, `initialized` and `z_stream_end` are `Bool` (C `int` used as a flag), `multi_part` an `Int`
#      (0, 1 or -1: it has three values). `ld` is the local data the close hook needs (as `HashContext`, DIVERGES 5 of src/pl-hashstream.jl).
#   6. THE BUFFERS. the C callbacks get `char *buf, size_t size`; the kernel's get the array and the index (`mem`, `from`, `size`). zwrite4's
#      `zwrite4(handle, NULL, 0, flush)` of `zcontrol` and `zclose` is `zwrite4(ctx, UInt8[], 1, 0, flush)`: `next_in` is NULL when `size` is 0.
#      The output scratch `Bytef buffer[SIO_BUFSIZE]` is a local `Vector{UInt8}`; `Sfwrite(buffer, 1, n, ctx->stream)` writes its first `n` bytes.
#   7. THE INPUT POINTER (zlib_plan.md section 4, the one new design point). C keeps `zstate.next_in` pointing INTO the parent's buffer across
#      calls and `sync_stream` sets `parent->bufp = next_in`. The kernel's buffer is `parent.mem`, indexed by `parent.bufp`, and can be replaced by
#      `S__setbuf` (an empty `mem` of an unbuffered parent is replaced by `Sfeof`): so `next_in` is RE-DERIVED from `pointer(parent.mem, parent.bufp)`
#      at every `zread` entry, under `GC.@preserve`, and `sync_stream` adds what zlib consumed (`next_in` minus the derived pointer) to
#      `parent.bufp`. Equivalent to C, where `sync_stream` keeps `bufp == next_in` at every return; `avail_in` is still zlib's own count (set from
#      `limitp - bufp` when the parent is read, C 145). One consequence: C, on a parent at end of file whose input was never fetched, sets
#      `parent->bufp = NULL` (`next_in` still NULL after the first init: undefined position arithmetic); here `bufp` stays.
#   8. NOT PORTED: the `DEBUG(n, ...)`/`zdebug/1` lines (no `Sdprintf` in the kernel, O_DEBUG off in a release build), and the two `Sdprintf` of
#      diagnostics ("inflateGetHeader() failed" C 169, "ERROR: zwrite(): msg" C 304): the failures themselves are handled as C does. A NULL `zstream`
#      (a record not yet attached to its stream, C would dereference it) makes `Sseterr` a no-op.
#   9. THE GOTOS. `again:` and `end_seen:` of `zread` are a `while true` with `continue` and an `end_seen` flag; control flow and the order of
#      the tests are the C's.
#  10. THE CLOSE. As src/pl-hashstream.jl (DIVERGES 5 there): `zclose` closes the PARENT itself, which no kernel closer sees, so `Sclose(parent)`
#      is followed by `freeStream(ctx.ld, parent)`. `zcontrol`'s default arm asks the parent's control function through `S_control`, whose
#      `SCONTROL_NONE` is upstream's NULL `control` (-1).

# PORT: packages/zlib/zlib4pl.c BUFSIZE (62)
"The scratch size of `zwrite4` (zlib4pl.c `BUFSIZE` = `SIO_BUFSIZE`)."
const Z_BUFSIZE = SIO_BUFSIZE

# PORT: packages/zlib/zlib4pl.c zformat (64-69)
# DIVERGES: 5. constants, not an `enum`.
"zlib4pl.c `F_UNKNOWN`: an input stream's format is detected (gzip or zlib) from the data."
const Z_F_UNKNOWN = 0
"zlib4pl.c `F_GZIP`."
const Z_F_GZIP = 1
"zlib4pl.c `F_DEFLATE`: the zlib wrapper."
const Z_F_DEFLATE = 2
"zlib4pl.c `F_RAW_DEFLATE`."
const Z_F_RAW_DEFLATE = 3

# PORT: packages/zlib/zlib4pl.c z_context (71-81)
# DIVERGES: 5.
"The context of a zlib stream (zlib4pl.c `z_context`): the parent `stream`, the compressed stream `zstream`, the options, the flags, the format, the `z_stream` and `gz_header` records."
mutable struct ZContext{T} <: AbstractSfilter
    stream::IOSTREAM                    # Original stream
    zstream::Union{Nothing, IOSTREAM}   # Compressed stream (I'm handle of)
    close_parent::Bool                  # close parent on close
    initialized::Bool                   # did inflateInit()?
    multi_part::Int                     # Multipart gzip file
    z_stream_end::Bool                  # Seen Z_STREAM_END
    format::Int                         # current format (Z_F_*)
    zstate::Ptr{Cvoid}                  # Zlib state (112 bytes, calloc'ed)
    zhead::Ptr{Cvoid}                   # Header (80 bytes, calloc'ed)
    ld::PL_local_data{T}                # for the close hook (DIVERGES 10)
end

# PORT: packages/zlib/zlib4pl.c alloc_zcontext (84-93)
# DIVERGES: 5. `PL_malloc` + `memset` are the record constructor and Z1's `calloc`ed records.
"A zeroed context over the parent `s`, `close_parent` true (zlib4pl.c)."
function alloc_zcontext(ld::PL_local_data{T}, s::IOSTREAM)::ZContext{T} where {T}
    return ZContext{T}(
        s, nothing, true, false, 0, false, Z_F_UNKNOWN, z_stream_alloc(), gz_header_alloc(),
        ld
    )
end

# PORT: packages/zlib/zlib4pl.c free_zcontext (96-104)
# DIVERGES: 5. `PL_free(ctx)` frees the two records and leaves NULL in the context (a second call frees nothing).
"Unlink the filter from its parent, or release the parent, and free the records (zlib4pl.c)."
function free_zcontext(ctx::ZContext)::Nothing
    if ctx.stream.upstream !== nothing
        Sset_filter(ctx.stream, nothing)
    else
        PL_release_stream(ctx.ld, ctx.stream)
    end
    if ctx.zstate != C_NULL
        z_stream_free(ctx.zstate)
        ctx.zstate = C_NULL
    end
    if ctx.zhead != C_NULL
        gz_header_free(ctx.zhead)
        ctx.zhead = C_NULL
    end
    return nothing
end

# PORT: packages/zlib/zlib4pl.c zread (166): memset(&ctx->zhead, 0, sizeof(ctx->zhead))
"Zero the `gz_header` record `head`."
function gz_header_zero!(head::Ptr{Cvoid})::Nothing
    fill!(unsafe_wrap(Vector{UInt8}, Ptr{UInt8}(head), GZ_HEADER_SIZE), 0x00)
    return nothing
end

# PORT: packages/zlib/zlib4pl.c sync_stream (111-121)
# DIVERGES: 7. `pm` is the parent's buffer, preserved by the caller; `bufp` advances by what zlib consumed since `next_in` was derived.
"Make the parent's `bufp` (and its byte position) follow the `next_in` of the inflater (zlib4pl.c)."
function sync_stream(ctx::ZContext, pm::Vector{UInt8})::Nothing
    parent = ctx.stream
    bytes = Int(z_stream_next_in(ctx.zstate)) - Int(pointer(pm, parent.bufp))
    pos = parent.position
    if pos !== nothing
        pos.byteno += bytes
    end
    parent.bufp += bytes
    return nothing
end

# the `Sseterr(ctx->zstream, SIO_FERR, msg)` of zread
# DIVERGES: 8 (a NULL `zstream`).
function _zseterr(ctx::ZContext, msg::String)::Nothing
    zs = ctx.zstream
    zs === nothing || Sseterr(zs, SIO_FERR, msg)
    return nothing
end

# PORT: packages/zlib/zlib4pl.c zread (158-176): the `initialized == false` arm
# DIVERGES: 8 (the "inflateGetHeader() failed" line).
"Start the inflater for `ctx.format`: `Z_OK` or an error code (zlib4pl.c)."
function _zread_init(ctx::ZContext)::Cint
    zs = ctx.zstate
    fmt = ctx.format
    if fmt == Z_F_GZIP
        return zlib_inflate_init2!(zs, Cint(MAX_WBITS + 16))
    elseif fmt == Z_F_DEFLATE
        return zlib_inflate_init!(zs)
    elseif fmt == Z_F_RAW_DEFLATE
        return zlib_inflate_init2!(zs, Cint(-MAX_WBITS))
    end
    gz_header_zero!(ctx.zhead)
    rc = zlib_inflate_init2!(zs, Cint(MAX_WBITS + 32))
    rc == Z_OK && zlib_inflate_get_header!(zs, ctx.zhead)
    return rc
end

# PORT: packages/zlib/zlib4pl.c zread (124-258)
# DIVERGES: 5, 6, 7, 8, 9.
"Read up to `size` decompressed bytes into `mem` at `from`: the count, 0 at end of file, -1 on error (zlib4pl.c `zread`)."
function Sfilter_read(ctx::ZContext, mem::Vector{UInt8}, from::Int, size::Int)::Int
    zs = ctx.zstate
    parent = ctx.stream
    while true                                              # again: (135)
        z_stream_set_next_out!(zs, pointer(mem, from))      # 136-137
        z_stream_set_avail_out!(zs, UInt32(size))
        end_seen = false

        if z_stream_avail_in(zs) == 0                       # 139
            if ctx.z_stream_end                             # 140-141
                end_seen = true
            elseif Sfeof(parent) == 0                       # 143
                z_stream_set_avail_in!(zs, UInt32(parent.limitp - parent.bufp))   # 144-145 (next_in: DIVERGES 7)
            end
        end

        if !end_seen
            pm = parent.mem                                 # after Sfeof: it may have made the buffer
            rc = GC.@preserve mem pm begin
                z_stream_set_next_in!(zs, pointer(pm, parent.bufp))   # DIVERGES 7
                if !ctx.initialized                         # 158
                    irc = _zread_init(ctx)                  # 159-170
                    if irc != Z_OK                          # 171
                        _zseterr(
                            ctx,
                            if irc == Z_MEM_ERROR
                                "zlib: not enough memory"
                            else
                                "zlib: initialization failed"
                            end
                        )                                   # 172-174
                        return -1                           # 175
                    end
                    ctx.initialized = true                  # 177
                    sync_stream(ctx, pm)                    # 178
                end
                r = zlib_inflate!(zs, Z_NO_FLUSH)           # 181
                sync_stream(ctx, pm)                        # 182
                r
            end

            if rc == Z_OK                                   # 185
                n = size - Int(z_stream_avail_out(zs))      # 186
                n == 0 && continue                          # 190-198: not enough data to decode: goto again
                return n                                    # 201
            elseif rc == Z_STREAM_END                       # 203
                ctx.z_stream_end = true                     # 206
                end_seen = true                             # falls into end_seen:
            else
                msg = if rc == Z_NEED_DICT                  # 230-233
                    "zlib: need dictionary"
                elseif rc == Z_DATA_ERROR                   # 234-237
                    "zlib: corrupt input data"
                elseif rc == Z_STREAM_ERROR                 # 238-241
                    "zlib: inconsistent state"
                elseif rc == Z_MEM_ERROR                    # 242-245
                    "zlib: not enough memory"
                elseif rc == Z_BUF_ERROR                    # 246-249
                    "zlib: unexpected end-of-file"
                else
                    nothing                                 # 250-251 default
                end
                zm = z_stream_msg(zs)                       # 253-254
                zm === nothing || (msg = zm)
                msg === nothing || _zseterr(ctx, msg)       # 255-256
                return -1                                   # 257
            end
        end

        # end_seen: (208)
        n = size - Int(z_stream_avail_out(zs))              # 209
        if n == 0 && ctx.multi_part != 0                    # 213
            ctx.multi_part == -1 && gz_header_done(ctx.zhead) < 0 && return n   # 214-216: default multi_part and deflate
            Sfeof(parent) != 0 && return n                  # 218-219
            ctx.z_stream_end = false                        # 222
            ctx.initialized = false                         # 223: multiple zips
            zlib_inflate_end!(zs)                           # 224
            continue                                        # 225: goto again
        end
        return n                                            # 228
    end
end

# PORT: packages/zlib/zlib4pl.c zwrite4 (261-314)
# DIVERGES: 6, 8 (the "ERROR: zwrite()" line).
"Compress the `size` bytes of `mem` at `from` with `flush` (`Z_NO_FLUSH`, `Z_SYNC_FLUSH`, `Z_FINISH`) and write the output to the parent: `size`, or -1 on error (zlib4pl.c)."
function zwrite4(ctx::ZContext, mem::Vector{UInt8}, from::Int, size::Int, flush::Cint)::Int
    zs = ctx.zstate
    buffer = Vector{UInt8}(undef, Z_BUFSIZE)                # 264
    GC.@preserve mem buffer begin
        z_stream_set_next_in!(zs, size > 0 ? pointer(mem, from) : Ptr{UInt8}(C_NULL))   # 268
        z_stream_set_avail_in!(zs, UInt32(size))            # 269
        while true                                          # 272
            z_stream_set_next_out!(zs, pointer(buffer))     # 274
            z_stream_set_avail_out!(zs, UInt32(Z_BUFSIZE))  # 275

            rc = zlib_deflate!(zs, flush)                   # 277
            if rc == Z_OK || rc == Z_STREAM_END             # 278-279
                n = Z_BUFSIZE - Int(z_stream_avail_out(zs)) # 280
                if n > 0                                    # 285
                    Sfwrite(buffer, 1, n, ctx.stream) != n && return -1   # 293-294
                end
            elseif rc == Z_BUF_ERROR                        # 299-301
            # nothing to do
            else
                return -1                                   # 302-305 Z_STREAM_ERROR and default
            end
            # 307-308: while ( avail_in > 0 || (flush != Z_NO_FLUSH && rc == Z_OK) )
            (z_stream_avail_in(zs) > 0 || (flush != Z_NO_FLUSH && rc == Z_OK)) || break
        end
    end

    flush != Z_NO_FLUSH && Sflush(ctx.stream) < 0 && return -1   # 310-311
    return size                                             # 313
end

# PORT: packages/zlib/zlib4pl.c zwrite (317-320)
# DIVERGES: 6.
"Compress and write the `size` bytes of `mem` at `from` (`zwrite4` with `Z_NO_FLUSH`): `size`, or -1 on error (zlib4pl.c)."
function Sfilter_write(ctx::ZContext, mem::Vector{UInt8}, from::Int, size::Int)::Int
    return zwrite4(ctx, mem, from, size, Z_NO_FLUSH)
end

# PORT: packages/zlib/zlib4pl.c zcontrol (323-346)
# DIVERGES: 6, 10.
"Control: `SIO_FLUSHOUTPUT` is a sync flush, the encoding may be switched, everything else is the parent's (zlib4pl.c)."
function Sfilter_control(ctx::ZContext, op::Int, arg)::Int
    if op == SIO_FLUSHOUTPUT                                # 328
        return zwrite4(ctx, UInt8[], 1, 0, Z_SYNC_FLUSH)    # 330
    elseif op == SIO_SETENCODING                            # 331
        return 0                                            # 332: allow switching encoding
    end
    parent = ctx.stream                                     # 334
    if parent.magic == SIO_MAGIC                            # 335
        rc = S_control(parent, op, arg)                     # 339-341: funcs->control, if any
        rc != SCONTROL_NONE && return rc
    end
    return -1                                               # 343
end

# PORT: packages/zlib/zlib4pl.c zclose (349-395)
# DIVERGES: 5, 10.
"Close the zlib stream: end the (de)compressor, finish the output, free the context, close the parent if asked to (zlib4pl.c)."
function Sfilter_close(ctx::ZContext)::Int
    parent = ctx.stream
    rc::Int
    if (parent.flags & SIO_INPUT) != 0                      # 356
        if ctx.initialized                                  # 357
            rc = zlib_inflate_end!(ctx.zstate)              # 358
        else
            rc = Z_OK                                       # 360
        end
    else
        rc = zwrite4(ctx, UInt8[], 1, 0, Z_FINISH)          # 362: flush
        if rc == 0                                          # 363
            rc = zlib_deflate_end!(ctx.zstate)              # 364
        else
            zlib_deflate_end!(ctx.zstate)                   # 366
        end
    end

    if rc == Z_OK                                           # 370
        if ctx.close_parent                                 # 374
            free_zcontext(ctx)                              # 376
            r = Sclose(parent)                              # 377
            freeStream(ctx.ld, parent)                      # DIVERGES 10
            return r
        else
            free_zcontext(ctx)                              # 379
            return 0                                        # 380
        end
    end
    # 382-384: Z_STREAM_ERROR, Z_DATA_ERROR and the default
    if ctx.close_parent                                     # 385
        free_zcontext(ctx)                                  # 387
        Sclose(parent)                                      # 388
        freeStream(ctx.ld, parent)                          # DIVERGES 10
        return -1                                           # 389
    end
    free_zcontext(ctx)                                      # 392
    return -1                                               # 393
end

# ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
# ZLIB1 piece Z3 (packages/zlib/zlib4pl.c lines 398-527): `zopen/3`, `zdebug/1` and the install function, over the filter of Z2.
# BLIND-CODED: no Julia process ran when this was written.
#
# DIVERGES (the Z3 part of the file-wide list; 1-4 are in the header of the file, 5-10 in the Z2 part above):
#  11. REGISTERED IN `system` AT BOOT, as src/pl-hashstream.jl (DIVERGES 1 there): `PL_predicates_from_zlib4pl` is in `_PRED_TABLES` and `_FOREIGN_VA`
#      (src/pl-ext.jl), and `install_zlib4pl` is the empty function (its atoms are `mk_sym(T, :gzip)`, `:deflate` and `:raw_deflate`).
#      `use_foreign_library(foreign(zlib4pl))` (library(zlib), zlib.pl:55) looks the NAME `zlib4pl` up in the `static_extensions` table of
#      src/pl-load.jl; that table (JSON1) is NOT in this branch's base, so the row `("zlib4pl", install_zlib4pl)` is left to integration
#      (zlib_plan.md Z3, Q1).
#  12. THE OPTIONS. `PL_scan_options` returns the values (src/os/pl-option.jl DIVERGES): the C's `close_parent = true` and `multi_part = -1`
#      defaults apply to `nothing`; an `OPT_BOOL` given is `1` or `0` for `multi_part`.
#  13. THE NEW STREAM. `Snew` does not call `initStreamLocale` (src/os/pl-stream.jl, it needs the database): `pl_zopen` calls it, as upstream's `Snew`
#      does. The failure arm of `PL_unify_stream` closes the filter with `Sclose` and then runs the kernel's close hook `freeStream` (DIVERGES 10), as
#      src/pl-hashstream.jl. `PL_instantiation_error(new)` is the kernel's `PL_error(ld, ERR_INSTANTIATION)` (no culprit argument).
#  14. `zdebug/1` (registered because zlib4pl.c defines O_DEBUG, line 36) sets `zlib_debuglevel`, a module-level `Ref{Int}`; nothing reads it: the
#      `DEBUG(n, ...)` bodies are not ported (DIVERGES 8, no `Sdprintf` in the kernel).

# PORT: packages/zlib/zlib4pl.c debuglevel (41)
# DIVERGES: 14.
"The `zdebug/1` level (zlib4pl.c `static int debuglevel`); no code reads it (DIVERGES 14)."
const zlib_debuglevel = Ref{Int}(0)

# PORT: packages/zlib/zlib4pl.c COPY_FLAGS (412-415)
"The flags of the parent stream the zlib stream copies (zlib4pl.c `COPY_FLAGS`)."
const ZLIB_COPY_FLAGS =
    SIO_INPUT | SIO_OUTPUT | SIO_TEXT | SIO_REPXML | SIO_REPPL | SIO_RECORDPOS

# PORT: packages/zlib/zlib4pl.c zopen_options (417-423)
# (PL_OPTION("format", OPT_TERM), PL_OPTION("level", OPT_TERM), PL_OPTION("close_parent", OPT_BOOL), PL_OPTION("multi_part", OPT_BOOL))
const zopen_option_specs = (
    PL_option_t(:format, OPT_TERM), PL_option_t(:level, OPT_TERM),
    PL_option_t(:close_parent, OPT_BOOL), PL_option_t(:multi_part, OPT_BOOL)
)

# PORT: packages/zlib/zlib4pl.c pl_zopen (425-480)
# DIVERGES: 12, 13.
"`zopen(+OrgStream, -ZStream, +Options)`: a (de)compressing filter stream on OrgStream; options `format`, `level`, `close_parent`, `multi_part` (zlib4pl.c)."
function pl_zopen3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2, A3 = PL__t0, PL__t0 + 1, PL__t0 + 2
    fmt = Z_F_UNKNOWN                                           # 426
    level = Int(Z_DEFAULT_COMPRESSION)                          # 427

    vals = PL_scan_options(ld, A3, 0, "zoption", zopen_option_specs)   # 436-438
    vals === nothing && return FFALSE
    fmt_opt = vals[1]
    level_opt = vals[2]
    cp = vals[3]
    close_parent = cp isa Bool ? cp : true                      # 429: true
    mp = vals[4]
    multi_part = mp isa Bool ? (mp ? 1 : 0) : -1                # 430: -1 (default)

    if fmt_opt isa Int                                          # 439
        a = PL_get_atom_ex(ld, fmt_opt)                         # 442
        a === nothing && return FFALSE
        k = sym_key(a)
        if k == sym_key(mk_sym(T, :gzip))                       # 444
            fmt = Z_F_GZIP
        elseif k == sym_key(mk_sym(T, :deflate))                # 446
            fmt = Z_F_DEFLATE
        elseif k == sym_key(mk_sym(T, :raw_deflate))            # 448
            fmt = Z_F_RAW_DEFLATE
        else
            PL_domain_error(ld, "compression_format", fmt_opt)  # 451
            return FFALSE
        end
    end
    if level_opt isa Int                                        # 453
        lv = PL_get_integer_ex(ld, level_opt)                   # 455
        lv === nothing && return FFALSE
        level = lv
        if level < 0 || level > 9                               # 457
            PL_domain_error(ld, "compression_level", level_opt) # 458
            return FFALSE
        end
    end

    s = term_stream_handle(ld, A1, SH_ERRORS | SH_ALIAS)        # 461: PL_get_stream_handle
    s === nothing && return FFALSE                              # Error
    ctx = alloc_zcontext(ld, s)                                 # 463
    ctx.close_parent = close_parent
    ctx.multi_part = multi_part
    ctx.format = fmt
    if (s.flags & SIO_OUTPUT) != 0                              # 467
        rc = if fmt == Z_F_GZIP                                 # 469
            zlib_deflate_init2!(
                ctx.zstate, Cint(level), Z_DEFLATED, MAX_WBITS + Cint(16),
                MAX_MEM_LEVEL,
                Z_DEFAULT_STRATEGY
            )
        elseif fmt == Z_F_RAW_DEFLATE                           # 471
            zlib_deflate_init2!(
                ctx.zstate, Cint(level), Z_DEFLATED, -MAX_WBITS, MAX_MEM_LEVEL,
                Z_DEFAULT_STRATEGY
            )
        else
            zlib_deflate_init!(ctx.zstate, Cint(level))         # 473
        end

        if rc != Z_OK                                           # 476
            free_zcontext(ctx)
            return FFALSE                                       # TBD: Error
        end
    end

    s2 = Snew(ctx, (s.flags & ZLIB_COPY_FLAGS) | SIO_FBUF, Sfilterfunctions)   # 483-485 (no memory: DIVERGES, as hashstream 6)
    initStreamLocale(_query_gd(ld), s2)                         # Snew's initStreamLocale (DIVERGES 13)
    s2.encoding = s.encoding                                    # 490
    ctx.zstream = s2                                            # 491
    Sset_filter(s, s2)                                          # 492
    PL_release_stream(ld, s)                                    # 493
    if PL_unify_stream(ld, A2, s2)                              # 494
        return FTRUE
    end
    ctx.close_parent = false                                    # 498
    Sclose(s2)                                                  # 499
    freeStream(ld, s2)                                          # DIVERGES 13
    PL_error(ld, ERR_INSTANTIATION)                             # 500: PL_instantiation_error(new), actually over instantiation
    return FFALSE
end

# PORT: packages/zlib/zlib4pl.c zdebug (505-510)
# DIVERGES: 14.
"`zdebug(+Level)`: set the debug level (zlib4pl.c; the debug output itself is not ported)."
function pl_zdebug1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    v = PL_get_integer(ld, PL__t0)                              # 509
    v === nothing && return FFALSE
    zlib_debuglevel[] = v
    return FTRUE
end

# PORT: packages/zlib/zlib4pl.c install_zlib4pl (518-527)
# DIVERGES: 11.
"The install function of the static extension `zlib4pl` (zlib4pl.c `install_zlib4pl`): the predicates exist already."
function install_zlib4pl(ld::PL_local_data{T})::Nothing where {T}
    return nothing
end

# PORT: packages/zlib/zlib4pl.c install_zlib4pl as PL_predicates_from_zlib4pl
# DIVERGES: 11.
const PL_predicates_from_zlib4pl = (
    PL_extension("zopen", 3, pl_zopen3_va, PL_FA_VARARGS),
    PL_extension("zdebug", 1, pl_zdebug1_va, PL_FA_VARARGS)
)
