# ORIGINAL: the pending-input functions of the stream layer (pl-stream.c Sread_pending, Spending, Sfileno, S__fileno; packages/clib prolog_stream.c and hash_stream.c use them); no swipl oracle: the functions are the C ones over a Julia byte buffer, so every expected value below is what the C source does, with the line named (swipl-devel 18168e62).
# test/files/test_stream_pending_swipl.jl
#   * Sread_pending (pl-stream.c:1623): the buffered bytes (at most `limit`), with SIO_RP_BLOCK a fill first when the buffer is empty
#     (that first byte counts, `limit` shrinks by it), the position update over every delivered byte unless SIO_RP_NOPOS, 0 at a
#     clean end of file;
#   * Spending (pl-stream.c:1666): the buffered bytes, else the control function's SIO_GETPENDING (a filter's), else 0;
#   * Sfileno / S__fileno (pl-stream.c:3859-3898): the cached file number of a filter stream, from its control function's
#     SIO_GETFILENO when the stream was made; -1 for every stream without one and for a closed stream.
using Test, LogicKernel
const LK = LogicKernel

"A filter that supplies `data` once and answers the SIO_GETPENDING / SIO_GETFILENO control actions with `pending` / `fileno`."
mutable struct PendFilter <: LK.AbstractSfilter
    data::Vector{UInt8}
    pending::Int
    fileno::Int
    rc::Int                           # what the control actions return (0: handled)
end
PendFilter(data::AbstractString=""; pending::Int=0, fileno::Int=-1, rc::Int=0) =
    PendFilter(collect(codeunits(data)), pending, fileno, rc)

function LK.Sfilter_read(h::PendFilter, mem::Vector{UInt8}, from::Int, size::Int)::Int
    n = min(length(h.data), size)
    for i in 1:n
        mem[from + i - 1] = h.data[i]
    end
    deleteat!(h.data, 1:n)
    return n
end
function LK.Sfilter_control(h::PendFilter, op::Int, arg)::Int
    if op == LK.SIO_GETPENDING
        arg[] = h.pending
        return h.rc
    elseif op == LK.SIO_GETFILENO
        arg[] = h.fileno
        return h.rc
    end
    return LK.SCONTROL_NONE
end

"A memory stream on the text `str`, for reading."
_sp_in(str::AbstractString) =
    let bytes = collect(codeunits(str))
        LK.Sopenmem(Ref{Union{Nothing, Vector{UInt8}}}(bytes), Ref(length(bytes)), "r")
    end
"The position of `s` as (charno, lineno, linepos)."
_sp_pos(s::LK.IOSTREAM) = (s.position.charno, s.position.lineno, s.position.linepos)
"A filter input stream over `impl` (no parent: the way prolog_stream.c's streams are made)."
_sp_filter(impl::PendFilter) =
    LK.Snew(impl, LK.SIO_INPUT | LK.SIO_FBUF, LK.Sfilterfunctions)

# p01: SIO_RP_BLOCK on an empty buffer fills it, the first byte is `buf[1]`, the rest of the buffer follows; every byte updates
# the position (charno 7, lineno 2 after the newline, linepos 3 for "def")
@testset "p01 Sread_pending blocking fill, position update" begin
    s = _sp_in("abc\ndef")
    buf = zeros(UInt8, 20)
    @test LK.Spending(s) == 0                                  # nothing buffered, no control function
    @test _sp_pos(s) == (0, 1, 0)
    @test LK.Sread_pending(s, buf, 20, LK.SIO_RP_BLOCK) == 7
    @test String(buf[1:7]) == "abc\ndef"
    @test _sp_pos(s) == (7, 2, 3)
    @test LK.Spending(s) == 0                                  # all consumed
    @test LK.Sread_pending(s, buf, 20, 0) == 0                 # no BLOCK: nothing buffered, nothing delivered
    @test LK.Sread_pending(s, buf, 20, LK.SIO_RP_BLOCK) == 0   # a clean end of file (not past it) is 0, not -1
    @test LK.Sclose(s) == 0
end

# p02: `limit` bounds the delivery; the bytes stay buffered for the next call (Spending counts them)
@testset "p02 Sread_pending limit, Spending of the buffered rest" begin
    s = _sp_in("abcdef")
    buf = zeros(UInt8, 20)
    @test LK.Sread_pending(s, buf, 3, LK.SIO_RP_BLOCK) == 3    # the filled byte 'a' counts: limit 3 delivers "abc"
    @test String(buf[1:3]) == "abc"
    @test _sp_pos(s) == (3, 1, 3)
    @test LK.Spending(s) == 3
    @test LK.Sread_pending(s, buf, 2, 0) == 2
    @test String(buf[1:2]) == "de"
    @test LK.Spending(s) == 1
    @test LK.Sgetc(s) == Int('f')                              # the stream goes on from where the pending read stopped
    @test LK.Sclose(s) == 0
end

# p03: limit 1 with BLOCK delivers only the filled byte (limit-- leaves 0 for the copy)
@testset "p03 Sread_pending limit 1 blocking" begin
    s = _sp_in("abcdef")
    buf = zeros(UInt8, 20)
    @test LK.Sread_pending(s, buf, 1, LK.SIO_RP_BLOCK) == 1
    @test buf[1] == UInt8('a')
    @test _sp_pos(s) == (1, 1, 1)
    @test LK.Spending(s) == 5
    @test LK.Sgetc(s) == Int('b')
    @test LK.Sclose(s) == 0
end

# p04: SIO_RP_NOPOS leaves the position alone; a stream without a position works too
@testset "p04 Sread_pending SIO_RP_NOPOS and no position" begin
    s = _sp_in("ab\ncd")
    buf = zeros(UInt8, 20)
    @test LK.Sread_pending(s, buf, 20, LK.SIO_RP_BLOCK | LK.SIO_RP_NOPOS) == 5
    @test String(buf[1:5]) == "ab\ncd"
    @test _sp_pos(s) == (0, 1, 0)
    @test LK.Sclose(s) == 0
    s = _sp_in("ab\ncd")
    s.position = nothing
    @test LK.Sread_pending(s, buf, 20, LK.SIO_RP_BLOCK) == 5
    @test String(buf[1:5]) == "ab\ncd"
    @test LK.Sclose(s) == 0
end

# p05: without BLOCK on a fresh stream nothing is read and nothing moves; after one Sgetc the rest is pending and delivered
@testset "p05 Sread_pending without SIO_RP_BLOCK" begin
    s = _sp_in("abcd")
    buf = zeros(UInt8, 20)
    @test LK.Sread_pending(s, buf, 20, 0) == 0
    @test _sp_pos(s) == (0, 1, 0)
    @test LK.Sgetc(s) == Int('a')
    @test LK.Spending(s) == 3
    @test LK.Sread_pending(s, buf, 20, 0) == 3
    @test String(buf[1:3]) == "bcd"
    @test _sp_pos(s) == (4, 1, 4)                              # 'a' counted by Sgetc, "bcd" by Sread_pending
    @test LK.Sclose(s) == 0
end

# p06: Spending of a filter stream: the buffered bytes first (the control function is not asked), else SIO_GETPENDING, a refusing
# control answer is 0
@testset "p06 Spending and the control function" begin
    impl = PendFilter("wxyz"; pending=99)
    s = _sp_filter(impl)
    @test LK.Spending(s) == 99                                 # nothing buffered: the control's answer
    @test LK.Sgetc(s) == Int('w')                              # fills the buffer with 4 bytes
    @test LK.Spending(s) == 3                                  # buffered: 3, not 99
    @test LK.Sclose(s) == 0
    impl = PendFilter(""; pending=5, rc=-1)
    s = _sp_filter(impl)
    @test LK.Spending(s) == 0                                  # the control refuses: 0
    @test LK.Sclose(s) == 0
    impl = PendFilter(""; pending=5, rc=LK.SCONTROL_NONE)
    s = _sp_filter(impl)
    @test LK.Spending(s) == 0
    @test LK.Sclose(s) == 0
end

# p07: Sfileno: the number the control function gave when the filter stream was made, cached (S__fileno asks again), 0 is a
# number, a refusal and a stream without control are -1, a closed stream is -1 although the cache is still set
@testset "p07 Sfileno, S__fileno" begin
    mem = _sp_in("abc")
    @test mem.fileno == -1
    @test LK.Sfileno(mem) == -1
    @test LK.S__fileno(mem) == -1
    @test LK.Sclose(mem) == 0
    impl = PendFilter(""; fileno=7)
    s = _sp_filter(impl)
    @test s.fileno == 7
    @test LK.Sfileno(s) == 7
    impl.fileno = 9
    @test LK.Sfileno(s) == 7                                   # cached
    @test LK.S__fileno(s) == 9                                 # live
    @test LK.Sclose(s) == 0
    @test s.fileno == 7
    @test LK.Sfileno(s) == -1                                  # magic is no longer SIO_MAGIC
    @test LK.S__fileno(s) == -1
    s = _sp_filter(PendFilter(""; fileno=0))
    @test LK.Sfileno(s) == 0                                   # descriptor 0 is >= 0
    @test LK.Sclose(s) == 0
    s = _sp_filter(PendFilter(""; fileno=7, rc=-1))
    @test s.fileno == -1
    @test LK.Sfileno(s) == -1
    @test LK.Sclose(s) == 0
    s = _sp_filter(PendFilter(""; fileno=7, rc=LK.SCONTROL_NONE))
    @test LK.Sfileno(s) == -1
    @test LK.Sclose(s) == 0
end
