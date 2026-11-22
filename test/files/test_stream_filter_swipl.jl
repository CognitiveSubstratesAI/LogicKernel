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
    fail_flush::Bool                  # SIO_FLUSHOUTPUT answers -1
    lasterror::String                 # SIO_LASTERROR's message
    size::Int                         # SIO_GETSIZE's answer
    args::Vector{Any}                 # the argument of each control action, in the order called
end
XorFilter(parent::LK.IOSTREAM, key::Integer=0x55; close_parent::Bool=true) =
    XorFilter(parent, UInt8(key), close_parent, String[], false, false, false, "no good reason", 1234, Any[])

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
        return h.fail_flush ? -1 : 0
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
function LK.Sfilter_write(h::NoControlFilter, mem::Vector{UInt8}, from::Int, size::Int)::Int
    for i in 0:(size - 1)
        LK.Sputc(Int(mem[from + i]), h.parent) < 0 && return -1
    end
    return size
end
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

# f07: Sflush writes the buffer to the write callback FIRST, then asks the control function for SIO_FLUSHOUTPUT (pl-stream.c Sflush)
@testset "f07 Sflush: the buffer reaches the write callback, then control SIO_FLUSHOUTPUT" begin
    parent, bufp, sizep = _sf_out()
    impl = XorFilter(parent)
    filter = _sf_filter(parent, impl)
    @test LK.Sflush(filter) == 0 && isempty(impl.log)        # no buffer yet: nothing to write, no control call
    LK.Sputc(Int('a'), filter)
    LK.Sputc(Int('b'), filter)
    @test LK.Sflush(filter) == 0
    @test impl.log == ["write", "control$(LK.SIO_FLUSHOUTPUT)"]
    @test LK.Sflush(filter) == 0                             # empty buffer: no write, but the control action is still asked
    @test impl.log == ["write", "control$(LK.SIO_FLUSHOUTPUT)", "control$(LK.SIO_FLUSHOUTPUT)"]
    # a control function that fails the flush: Sflush is -1 (the buffer was written all the same)
    impl.fail_flush = true
    LK.Sputc(Int('c'), filter)
    @test LK.Sflush(filter) == -1
    @test impl.log[end - 1:end] == ["write", "control$(LK.SIO_FLUSHOUTPUT)"]
    impl.fail_flush = false
    @test LK.Sclose(filter) == 0
    @test impl.log[end] == "close"
    @test _sf_bytes(bufp, sizep) == _sf_xor("abc")
    # a filter with no control function: the flush works, the control is skipped
    parent2, bufp2, sizep2 = _sf_out()
    f2 = _sf_filter(parent2, NoControlFilter(parent2))
    LK.Sputc(Int('z'), f2)
    @test LK.Sflush(f2) == 0
    @test LK.Sclose(f2) == 0
    @test LK.Sclose(parent2) == 0
    @test _sf_bytes(bufp2, sizep2) == UInt8['z']
end

# f08: a failing read callback is the stream's error; the message comes from the control function (SIO_LASTERROR, S__seterror)
@testset "f08 a read failure: FERR and the SIO_LASTERROR message" begin
    parent = _sf_in(UInt8[1, 2, 3])
    impl = XorFilter(parent; close_parent=false)
    impl.fail_read = true
    filter = _sf_filter(parent, impl)
    @test LK.Sgetcode(filter) == -1
    @test impl.log == ["read", "control$(LK.SIO_LASTERROR)"]
    @test LK.Sferror(filter) == 1
    @test filter.message == "no good reason"
    @test LK.Sferror(parent) == 0                            # the walk goes upstream only
    @test LK.Sgetcode(filter) == -1                          # in error: no second read
    @test count(==("read"), impl.log) == 1
    # a record with no control function: the error has no message
    f2 = LK.Snew(BareFilter(), LK.SIO_INPUT | LK.SIO_FBUF, LK.Sfilterfunctions)
    @test LK.Sgetc(f2) == -1                                 # the default read callback answers -1
    @test LK.Sferror(f2) == 1 && f2.message === nothing
    LK.Sclearerr(filter)
    @test LK.Sset_filter(parent, nothing) == 0
    @test LK.Sclose(filter) == 0
    @test LK.Sclose(parent) == 0
end

# f09: Ssize asks the control function (SIO_GETSIZE); -1 where there is none
@testset "f09 Ssize through control SIO_GETSIZE" begin
    parent = _sf_in(UInt8[])
    impl = XorFilter(parent; close_parent=false)
    filter = _sf_filter(parent, impl)
    @test LK.Ssize(filter) == 1234
    @test impl.log == ["control$(LK.SIO_GETSIZE)"]
    impl.size = 7
    @test LK.Ssize(filter) == 7
    f2 = LK.Snew(NoControlFilter(parent), LK.SIO_INPUT | LK.SIO_FBUF, LK.Sfilterfunctions)
    @test LK.Ssize(f2) == -1
    @test LK.Ssize(parent) == -1                             # a memory stream has no size to give
    @test LK.Sset_filter(parent, nothing) == 0
    @test LK.Sclose(filter) == 0
    @test LK.Sclose(parent) == 0
end

# f10: the filter's position counts what it delivers; the parent's counts what the filter pulled through Sgetc (which updates
# the character, line and line position, not the byte count: get_byte does) or pushed through Sputc (put_byte counts bytes)
@testset "f10 position counting" begin
    pos(s) = (Int(s.position.charno), s.position.lineno, s.position.linepos, Int(s.position.byteno))
    parent = _sf_in(collect(codeunits("ab\ncd")))
    filter = _sf_filter(parent, XorFilter(parent, 0))
    @test filter.position !== nothing && filter.position !== parent.position
    @test pos(filter) == (0, 1, 0, 0)
    @test LK.Sgetcode(filter) == Int('a')
    @test pos(filter) == (1, 1, 1, 1)
    @test pos(parent) == (5, 2, 2, 0)                         # the whole buffer was pulled at the first fill
    for _ in 1:4
        LK.Sgetcode(filter)
    end
    @test pos(filter) == (5, 2, 2, 5)
    @test pos(parent) == (5, 2, 2, 0)
    @test LK.Sclose(filter) == 0
    # output: the filter counts what the application wrote, the parent what the flush pushed through
    parent, bufp, sizep = _sf_out()
    impl = XorFilter(parent, 0)
    filter = _sf_filter(parent, impl)
    for ch in "ab\ncd"
        LK.Sputcode(Int(ch), filter)
    end
    @test pos(filter) == (5, 2, 2, 5)
    @test pos(parent) == (0, 1, 0, 0)                         # nothing reached it yet
    @test LK.Sflush(filter) == 0
    @test pos(parent) == (5, 2, 2, 5)
    @test LK.Sclose(filter) == 0
    @test _sf_bytes(bufp, sizep) == collect(codeunits("ab\ncd"))
end

# f11: close propagation: the filter's close callback decides what happens to the parent (zlib4pl.c, hash_stream.c)
@testset "f11 close propagation" begin
    # close_parent = false: the parent stays open, unlinked, the counts back at zero
    parent, bufp, sizep = _sf_out()
    impl = XorFilter(parent; close_parent=false)
    filter = _sf_filter(parent, impl)
    LK.Sputc(Int('q'), filter)
    @test LK.Sclose(filter) == 0
    @test impl.log == ["write", "close"]
    @test filter.magic == LK.SIO_CMAGIC && parent.magic == LK.SIO_MAGIC
    @test parent.upstream === nothing && filter.downstream === nothing
    @test parent.references == 0 && filter.references == 0
    @test !filter.erased
    @test LK.Sclose(parent) == 0
    @test _sf_bytes(bufp, sizep) == _sf_xor("q")
    # close_parent = true: both closed; closing the parent again is the usual -1 of a closed stream
    parent, _, _ = _sf_out()
    filter = _sf_filter(parent, XorFilter(parent))
    @test LK.Sclose(filter) == 0
    @test filter.magic == LK.SIO_CMAGIC && parent.magic == LK.SIO_CMAGIC
    @test LK.Sclose(parent) == -1
    # a reference taken by someone else keeps the closed filter alive: it is `erased` (freed when the last is released)
    parent, _, _ = _sf_out()
    filter = _sf_filter(parent, XorFilter(parent))
    LK.Sacquire(filter)
    @test filter.references == 2                              # the link and the acquire
    @test LK.Sclose(filter) == 0
    @test filter.references == 1 && filter.erased             # the callback's unlink took the link's reference
    @test LK.Srelease(filter)                                 # the last: unallocStream would run
    # the close callback fails (the parent is closed already): -1, and the filter is closed all the same
    parent, _, _ = _sf_out()
    filter = _sf_filter(parent, XorFilter(parent))
    @test LK.Sset_filter(parent, nothing) == 0
    @test LK.Sclose(parent) == 0
    @test LK.Sclose(filter) == -1
    @test filter.magic == LK.SIO_CMAGIC
end

# f12: the callers' errors: what the C asserts, and a filter stream with no record
@testset "f12 refusals" begin
    parent, _, _ = _sf_out()
    @test_throws AssertionError LK.Snew(XorFilter(parent), LK.SIO_OUTPUT | LK.SIO_FBUF, LK.Siofunctions)
    f1 = _sf_filter(parent, XorFilter(parent; close_parent=false))
    f2 = LK.Snew(XorFilter(parent), LK.SIO_OUTPUT | LK.SIO_FBUF, LK.Sfilterfunctions)
    # a second filter on one parent: assert(parent->upstream==NULL && filter->downstream==NULL), pl-stream.c:3310
    @test_throws AssertionError LK.Sset_filter(parent, f2)
    # a filter function set without a record: the callbacks answer as a NULL control does (read -1, close 0)
    s = LK.Snew(nothing, LK.SIO_INPUT | LK.SIO_FBUF, LK.Sfilterfunctions)
    @test LK.Sread_filter(s, UInt8[0], 1, 1) == -1
    @test LK.Swrite_filter(s, UInt8[0], 1, 1) == -1
    @test LK.Sclose_filter(s) == 0
    @test LK.S_control(s, LK.SIO_GETSIZE, nothing) == LK.SCONTROL_NONE
    @test LK.Sclose(s) == 0
end

# f13: the defaults of a record that supplies nothing, and S_control of a stream that has no control function
@testset "f13 the defaults of an AbstractSfilter, S_control without a filter" begin
    b = BareFilter()
    @test LK.Sfilter_read(b, UInt8[0], 1, 1) == -1
    @test LK.Sfilter_write(b, UInt8[0], 1, 1) == -1
    @test LK.Sfilter_close(b) == 0
    @test LK.Sfilter_control(b, LK.SIO_GETSIZE, nothing) == LK.SCONTROL_NONE
    @test LK.SCONTROL_NONE != 0 && LK.SCONTROL_NONE < 0
    m = _sf_in(UInt8[])
    @test LK.S_control(m, LK.SIO_GETSIZE, nothing) == LK.SCONTROL_NONE
    @test LK.S_control(m, LK.SIO_LASTERROR, Ref{Union{Nothing, String}}(nothing)) == LK.SCONTROL_NONE
    # a stream on a bare record: writing fails with -1 (the default), the error has no message
    s = LK.Snew(b, LK.SIO_OUTPUT | LK.SIO_FBUF, LK.Sfilterfunctions)
    LK.Sputc(Int('x'), s)
    @test LK.Sflush(s) == -1
    @test LK.Sferror(s) == 1 && s.message === nothing
end

# f14: Sfread and Sfwrite (pl-stream.c:1560, 1605): whole elements, on a stream with a position (byte by byte through Sgetc)
# and without (the buffer by memcpy), and through a filter, as hash_stream.c uses them
@testset "f14 Sfread, Sfwrite" begin
    data = collect(codeunits("abcdefghij"))
    for with_position in (true, false)
        s = _sf_in(data)
        with_position || (s.position = nothing)
        buf = zeros(UInt8, 20)
        @test LK.Sfread(buf, 1, 4, s) == 4
        @test buf[1:4] == data[1:4]
        @test LK.Sfread(buf, 2, 3, s) == 3                    # six bytes: all that is left
        @test buf[1:6] == data[5:10]
        @test LK.Sfread(buf, 1, 5, s) == 0                    # at the end
        @test LK.Sclose(s) == 0
        s = _sf_in(data[1:7])                                 # a partial element is not counted
        with_position || (s.position = nothing)
        buf = zeros(UInt8, 20)
        @test LK.Sfread(buf, 2, 5, s) == 3
        @test buf[1:7] == data[1:7]
        @test LK.Sclose(s) == 0
        s = _sf_in(data)
        with_position || (s.position = nothing)
        @test LK.Sfread(UInt8[], 0, 5, s) == 0                # size 0: nothing to read
        @test LK.Sclose(s) == 0
    end
    big = UInt8[i % 251 for i in 1:10000]
    for with_position in (true, false)
        s = _sf_in(big)
        with_position || (s.position = nothing)
        buf = zeros(UInt8, 10000)
        @test LK.Sfread(buf, 1, 10000, s) == 10000            # the 4096-byte buffer is refilled twice
        @test buf == big
        @test LK.Sclose(s) == 0
    end
    # Sfwrite
    w, bufp, sizep = _sf_out()
    @test LK.Sfwrite(collect(codeunits("hello world")), 1, 11, w) == 11
    @test LK.Sfwrite(collect(codeunits("abcdefg")), 3, 2, w) == 2        # 6 bytes
    @test LK.Sfwrite(UInt8[], 0, 3, w) == 0
    @test LK.Sclose(w) == 0
    @test String(_sf_bytes(bufp, sizep)) == "hello worldabcdef"
    # through the xor filter, both ways
    parent, bufp, sizep = _sf_out()
    filter = _sf_filter(parent, XorFilter(parent))
    @test LK.Sfwrite(data, 1, 10, filter) == 10
    @test LK.Sclose(filter) == 0
    @test _sf_bytes(bufp, sizep) == [b ⊻ _SF_KEY for b in data]
    parent = _sf_in([b ⊻ _SF_KEY for b in data])
    filter = _sf_filter(parent, XorFilter(parent))
    buf = zeros(UInt8, 10)
    @test LK.Sfread(buf, 5, 2, filter) == 2
    @test buf == data
    @test LK.Sclose(filter) == 0
end
