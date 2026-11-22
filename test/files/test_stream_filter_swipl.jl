# ORIGINAL: the stream filter (STREAMX: pl-stream.c Sset_filter, the `upstream`/`downstream` links and the `control` actions of SWI-Stream.h) with Julia filters over memory streams; no swipl oracle: a filter is a callback record that only C packages (zlib4pl.c, hash_stream.c, prolog_stream.c) supply, so every expected value below is what the C source does, with the line named.
# test/files/test_stream_filter_swipl.jl — the shared FILTER-STREAM extension of the stream layer
# (src/os/pl-stream.jl `AbstractSfilter`, `Sset_filter`, `Snew(::AbstractSfilter, ...)`, `S_control`):
#   * an XOR filter (`XorFilter`) over a memory stream, both ways: bytes written through it reach the parent XORed, bytes read
#     through it are XORed back (pl-stream.c S__flushbuf/S__fillbuf call the function set's write/read);
#   * the close protocol as the C packages do it: Sclose(filter) calls the filter's own close callback, which unlinks
#     (`Sset_filter(parent, NULL)`) and closes the parent if it was asked to; there is no flag that keeps the downstream
#     open (zlib4pl.c zclose/free_zcontext, hash_stream.c hash_close); Sclose(parent) while the filter is on it fails (S__close);
#   * Sset_filter's links and reference counts, Sseterr (walks upstream) and Sclearerr (walks downstream);
#   * the control actions: SIO_SETENCODING (Ssetenc), SIO_FLUSHOUTPUT (Sflush), SIO_LASTERROR (S__seterror), SIO_GETSIZE (Ssize);
#   * the position record of the filter and of its parent; the defaults of a filter record that supplies nothing;
#   * Sfread and Sfwrite (pl-stream.c:1560, 1605) over a plain and a filter stream.
using Test, LogicKernel
const LK = LogicKernel

"A filter that XORs every byte with `key`: the way a package's record (zlib4pl.c's `zcontext`) holds its parent and its options."
mutable struct XorFilter <: LK.AbstractSfilter
    parent::LK.IOSTREAM
    key::UInt8
    close_parent::Bool
    log::Vector{String}               # one entry per callback, in the order called
    fail_read::Bool                   # the read callback fails (-1)
    refuse_enc::Bool                  # SIO_SETENCODING answers -1
    lasterror::String                 # SIO_LASTERROR's message
    size::Int                         # SIO_GETSIZE's answer
    args::Vector{Any}                 # the argument of each control action, in the order called
end
XorFilter(parent::LK.IOSTREAM, key::Integer=0x55; close_parent::Bool=true) =
    XorFilter(parent, UInt8(key), close_parent, String[], false, false, "no good reason", 1234, Any[])

function LK.Sfilter_read(h::XorFilter, mem::Vector{UInt8}, from::Int, size::Int)::Int
    push!(h.log, "read")
    h.fail_read && return -1
    n = 0
    while n < size                                  # one byte at a time through the parent, as hash_stream.c's reader does
        c = LK.Sgetc(h.parent)
        c < 0 && break
        mem[from + n] = UInt8(c) ⊻ h.key
        n += 1
    end
    return n
end

function LK.Sfilter_write(h::XorFilter, mem::Vector{UInt8}, from::Int, size::Int)::Int
    push!(h.log, "write")
    for i in 0:(size - 1)
        LK.Sputc(Int(mem[from + i] ⊻ h.key), h.parent) < 0 && return -1
    end
    return size
end

function LK.Sfilter_close(h::XorFilter)::Int
    push!(h.log, "close")
    LK.Sset_filter(h.parent, nothing)               # zlib4pl.c free_zcontext: the filter unlinks itself,
    h.close_parent && return LK.Sclose(h.parent)    # then closes the parent if it was told to
    return 0
end

function LK.Sfilter_control(h::XorFilter, op::Int, arg)::Int
    push!(h.log, "control$op")
    if op == LK.SIO_SETENCODING
        push!(h.args, arg[])
        return h.refuse_enc ? -1 : 0
    elseif op == LK.SIO_FLUSHOUTPUT
        return 0
    elseif op == LK.SIO_LASTERROR
        arg[] = h.lasterror
        return 0
    elseif op == LK.SIO_GETSIZE
        arg[] = h.size
        return 0
    end
    return LK.SCONTROL_NONE
end

"A filter that defines the read, write and close callbacks only: its `control` is the record's default."
mutable struct NoControlFilter <: LK.AbstractSfilter
    parent::LK.IOSTREAM
end
LK.Sfilter_read(h::NoControlFilter, mem::Vector{UInt8}, from::Int, size::Int)::Int = 0
LK.Sfilter_write(h::NoControlFilter, mem::Vector{UInt8}, from::Int, size::Int)::Int = size
LK.Sfilter_close(h::NoControlFilter)::Int = (LK.Sset_filter(h.parent, nothing); 0)

"A record that supplies nothing: every callback is the default."
struct BareFilter <: LK.AbstractSfilter end

"A memory stream on `bytes`, for reading."
_sf_in(bytes::Vector{UInt8}) =
    LK.Sopenmem(Ref{Union{Nothing, Vector{UInt8}}}(copy(bytes)), Ref(length(bytes)), "r")
"A memory stream for writing: the stream and the references its bytes and size land in."
function _sf_out()
    bufp = Ref{Union{Nothing, Vector{UInt8}}}(nothing)
    sizep = Ref(0)
    return LK.Sopenmem(bufp, sizep, "w"), bufp, sizep
end
"What a memory stream written and closed holds."
_sf_bytes(bufp, sizep) = sizep[] == 0 ? UInt8[] : copy(bufp[][1:sizep[]])

"""
The stream a package's `Snew` builds over `parent` (zlib4pl.c/hash_stream.c): the parent's direction, text and position flags,
its encoding copied (`s2->encoding = s->encoding`), then linked with Sset_filter.
"""
function _sf_filter(parent::LK.IOSTREAM, impl::LK.AbstractSfilter)
    flags = (parent.flags & (LK.SIO_INPUT | LK.SIO_OUTPUT | LK.SIO_TEXT | LK.SIO_RECORDPOS)) | LK.SIO_FBUF
    s2 = LK.Snew(impl, flags, LK.Sfilterfunctions)
    s2.encoding = parent.encoding
    @test LK.Sset_filter(parent, s2) == 0
    return s2
end

"Every character of `s`, through Sgetcode, to the end of file."
function _sf_read_all(s::LK.IOSTREAM)::String
    cs = Char[]
    while true
        c = LK.Sgetcode(s)
        c < 0 && break
        push!(cs, Char(c))
    end
    return String(cs)
end

const _SF_TEXT = "héllo\nwörld"
const _SF_KEY = 0x55
_sf_xor(text::String, key=_SF_KEY) = UInt8[b ⊻ UInt8(key) for b in codeunits(text)]

# f01: written through the filter, the bytes reach the parent XORed (S__flushbuf -> the write callback -> Sputc(parent)); the
# filter's close callback closes the parent (`close_parent`), which writes the memory file out.
@testset "f01 write through an xor filter over a memory stream" begin
    parent, bufp, sizep = _sf_out()
    impl = XorFilter(parent)
    filter = _sf_filter(parent, impl)
    @test filter.functions == LK.Sfilterfunctions
    @test filter.encoding == parent.encoding == LK.ENC_UTF8
    for ch in _SF_TEXT
        @test LK.Sputcode(Int(ch), filter) == Int(ch)
    end
    @test isempty(impl.log)                          # buffered: the callback has not run
    @test LK.Sclose(filter) == 0
    @test impl.log == ["write", "close"]             # S__removebuf flushes, then S_close calls the close callback
    @test filter.magic == LK.SIO_CMAGIC
    @test parent.magic == LK.SIO_CMAGIC              # close_parent: the filter closed it
    @test parent.upstream === nothing && filter.downstream === nothing
    @test _sf_bytes(bufp, sizep) == _sf_xor(_SF_TEXT)
    @test _sf_bytes(bufp, sizep) != collect(codeunits(_SF_TEXT))
end

# f02: read through the filter: the parent holds the cipher text, Sgetcode of the filter decodes it
@testset "f02 read through an xor filter over a memory stream" begin
    parent = _sf_in(_sf_xor(_SF_TEXT))
    impl = XorFilter(parent)
    filter = _sf_filter(parent, impl)
    @test (filter.flags & LK.SIO_INPUT) != 0
    @test _sf_read_all(filter) == _SF_TEXT
    @test impl.log == ["read", "read"]               # one fill with the bytes, one that finds the end
    @test LK.Sferror(filter) == 0 && LK.Sferror(parent) == 0
    @test LK.Sclose(filter) == 0
    @test impl.log == ["read", "read", "close"]
    @test parent.magic == LK.SIO_CMAGIC
    # key 0 is the identity filter: the parent's own bytes come back unchanged
    parent = _sf_in(collect(codeunits(_SF_TEXT)))
    filter = _sf_filter(parent, XorFilter(parent, 0))
    @test _sf_read_all(filter) == _SF_TEXT
    @test LK.Sclose(filter) == 0
end

# f03: S__close of a stream with a filter on it refuses (pl-stream.c:2269): -1, the stream stays open and in error, the
# message names the lock, and the filter is in error too (Sseterr walks upstream)
@testset "f03 Sclose of the parent while the filter is on it" begin
    parent, bufp, sizep = _sf_out()
    impl = XorFilter(parent)
    filter = _sf_filter(parent, impl)
    @test LK.Sclose(parent) == -1
    @test parent.magic == LK.SIO_MAGIC
    @test parent.message == "Locked by upstream filter"
    @test LK.Sferror(parent) == 1
    @test LK.Sferror(filter) == 1                    # the walk upstream
    @test filter.message == "Locked by upstream filter"
    @test parent.upstream === filter && filter.downstream === parent   # still linked
    @test isempty(impl.log)                          # the filter was not asked to do anything
    # unlink and clear: the close now succeeds
    @test LK.Sset_filter(parent, nothing) == 0
    LK.Sclearerr(parent)
    @test LK.Sferror(parent) == 0 && parent.message === nothing
    @test LK.Sclose(parent) == 0
    @test parent.magic == LK.SIO_CMAGIC
    @test _sf_bytes(bufp, sizep) == UInt8[]          # nothing was written
    LK.Sclearerr(filter)                             # the filter is still in error: it is not downstream of anything now
    @test LK.Sferror(filter) == 0
    impl.close_parent = false                        # the parent is closed already
    @test LK.Sclose(filter) == 0
end

# f04: Sset_filter (pl-stream.c:3297): the links, the references, the refusals
@testset "f04 Sset_filter links, references, refusals" begin
    parent, _, _ = _sf_out()
    filter = LK.Snew(
        XorFilter(parent; close_parent=false), LK.SIO_OUTPUT | LK.SIO_FBUF, LK.Sfilterfunctions
    )
    @test parent.upstream === nothing && filter.downstream === nothing
    @test parent.references == 0 && filter.references == 0
    @test LK.Sset_filter(parent, filter) == 0
    @test parent.upstream === filter
    @test filter.downstream === parent
    @test parent.references == 1 && filter.references == 1     # Sreference(filter), Sreference(parent)
    @test LK.Sset_filter(parent, nothing) == 0
    @test parent.upstream === nothing && filter.downstream === nothing
    @test parent.references == 0 && filter.references == 0
    @test LK.Sset_filter(parent, nothing) == 0                 # nothing on it: no change, no count below zero
    @test parent.references == 0 && filter.references == 0
    # a closed stream, on either side, is refused with -1 and no link
    closed, _, _ = _sf_out()
    @test LK.Sclose(closed) == 0
    @test LK.Sset_filter(closed, filter) == -1
    @test LK.Sset_filter(closed, nothing) == -1
    @test LK.Sset_filter(parent, closed) == -1
    @test parent.upstream === nothing && closed.downstream === nothing
    @test parent.references == 0 && closed.references == 0
    # a filter on a parent, then Sclose of the filter with close_parent = false: the parent stays open
    @test LK.Sset_filter(parent, filter) == 0
    @test LK.Sclose(filter) == 0                               # the record's close callback unlinks
    @test parent.magic == LK.SIO_MAGIC && parent.upstream === nothing
    @test LK.Sclose(parent) == 0
end

# f05: Sseterr sets the stream and every filter on it (upstream); Sclearerr clears it and every stream it filters (downstream)
@testset "f05 Sseterr walks upstream, Sclearerr walks downstream" begin
    parent, _, _ = _sf_out()
    filter = _sf_filter(parent, XorFilter(parent; close_parent=false))
    LK.Sseterr(filter, LK.SIO_FERR, "filter's own")
    @test LK.Sferror(filter) == 1
    @test LK.Sferror(parent) == 0 && parent.message === nothing    # the walk goes up, not down
    LK.Sseterr(parent, LK.SIO_FERR, "parent's")
    @test LK.Sferror(parent) == 1 && LK.Sferror(filter) == 1
    @test parent.message == "parent's" && filter.message == "parent's"
    LK.Sclearerr(filter)                                           # clears the filter and the parent it filters
    @test LK.Sferror(filter) == 0 && LK.Sferror(parent) == 0
    @test filter.message === nothing && parent.message === nothing
    LK.Sseterr(parent, LK.SIO_FERR, "again")
    LK.Sclearerr(parent)                                           # Sclearerr's Sseterr(0, NULL) clears the filter above it too
    @test LK.Sferror(parent) == 0 && LK.Sferror(filter) == 0
    @test LK.Sset_filter(parent, nothing) == 0
    @test LK.Sclose(filter) == 0
    @test LK.Sclose(parent) == 0
end

# f06: Ssetenc forwards SIO_SETENCODING to the control function (pl-stream.c Ssetenc): a refusal leaves the encoding as it was
@testset "f06 encoding: inherited, forwarded, refused" begin
    parent = _sf_in(UInt8[])
    parent.encoding = LK.ENC_ISO_LATIN_1
    impl = XorFilter(parent)
    filter = _sf_filter(parent, impl)
    @test filter.encoding == LK.ENC_ISO_LATIN_1                    # the creator copies it
    @test LK.Ssetenc(filter, LK.ENC_ISO_LATIN_1) == 0              # unchanged: control is not asked
    @test isempty(impl.log)
    @test LK.Ssetenc(filter, LK.ENC_OCTET) == 0
    @test impl.log == ["control$(LK.SIO_SETENCODING)"]
    @test impl.args == Any[LK.ENC_OCTET]                           # the argument is a Ref of the new encoding
    @test filter.encoding == LK.ENC_OCTET && (filter.flags & LK.SIO_TEXT) == 0
    impl.refuse_enc = true
    @test LK.Ssetenc(filter, LK.ENC_UTF8) == -1                    # the control function refuses
    @test filter.encoding == LK.ENC_OCTET && (filter.flags & LK.SIO_TEXT) == 0
    @test impl.args == Any[LK.ENC_OCTET, LK.ENC_UTF8]              # it was asked
    impl.refuse_enc = false
    @test LK.Ssetenc(filter, LK.ENC_UTF8) == 0
    @test filter.encoding == LK.ENC_UTF8 && (filter.flags & LK.SIO_TEXT) != 0
    # a filter with no control function: the change is made
    parent2 = _sf_in(UInt8[])
    f2 = LK.Snew(NoControlFilter(parent2), LK.SIO_INPUT | LK.SIO_FBUF, LK.Sfilterfunctions)
    @test LK.Ssetenc(f2, LK.ENC_UTF8) == 0 && f2.encoding == LK.ENC_UTF8
    @test LK.Sclose(filter) == 0                                   # closes the parent too
    @test parent.magic == LK.SIO_CMAGIC
end
