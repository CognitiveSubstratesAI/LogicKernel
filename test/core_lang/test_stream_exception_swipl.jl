# ORIGINAL: the pending exception of a stream (pl-stream.c Sset_exception, Sclearerr; pl-file.c reportStreamError's recorded-exception branch, the consumer prolog_stream.c's error path needs); upstream has no such test.
# test/core_lang/test_stream_exception_swipl.jl
#   * the core layer (src/os/pl-stream.jl, no term type): Sset_exception(s, record) sets SIO_FERR, clears SIO_WARN and keeps the record;
#     with `nothing` it clears SIO_FERR, SIO_WARN and the record; a stream of a wrong magic answers -1; `upstream` is NOT followed;
#     Sclearerr drops the record of the stream and of every stream it filters (`downstream`);
#   * the LD layer (src/os/pl-file.jl): Sset_exception(ld, s, ex) records the term, an EQUAL pending exception is cleared (it is raised
#     again by reportStreamError) and a different one is kept; reportStreamError raises exactly the recorded term, drops the record
#     and clears the error state; with an exception already pending it answers false and keeps the record.
#   Expected values are the C source's (pl-stream.c 1873-1920, pl-file.c 1366-1383 at 18168e62): no Prolog-level route records an
#   exception on a stream without a foreign stream implementation, so swipl cannot answer these rows. None was measured.
using Test, LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — the LD rows run over the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _X = lk_term_type(Union{Int64, Float64, String})
const LKX = LogicKernel
_xs(x::Symbol) = lk_sym(_X, x)
_xf(f::Symbol, xs::_X...) = mk_expr(_X, _X[_xs(f), xs...])

struct _FakeEx <: LKX.AbstractStreamException
    id::Int
end

_xmem() = LKX.Sopenmem(Ref{Union{Nothing, Vector{UInt8}}}(nothing), Ref(0), "w")
_xex(s) = s.exception === nothing ? nothing : s.exception[]

@testset "e01 core Sset_exception records, sets SIO_FERR, clears SIO_WARN" begin
    s = _xmem()
    s.flags |= LKX.SIO_WARN
    @test LKX.Sset_exception(s, _FakeEx(1)) == 0
    @test (s.flags & LKX.SIO_FERR) != 0
    @test (s.flags & LKX.SIO_WARN) == 0
    @test _xex(s) isa _FakeEx
    @test _xex(s).id == 1
    @test LKX.Sset_exception(s, _FakeEx(2)) == 0            # replaces the record
    @test _xex(s).id == 2
end

@testset "e02 core Sset_exception(s, nothing) clears the flags and the record" begin
    s = _xmem()
    @test LKX.Sset_exception(s, _FakeEx(1)) == 0
    s.flags |= LKX.SIO_WARN
    @test LKX.Sset_exception(s, nothing) == 0
    @test (s.flags & (LKX.SIO_FERR | LKX.SIO_WARN)) == 0
    @test s.exception === nothing
    s.flags |= LKX.SIO_FEOF                                 # other flags stay
    @test LKX.Sset_exception(s, nothing) == 0
    @test (s.flags & LKX.SIO_FEOF) != 0
end

@testset "e03 core Sset_exception on a stream of a wrong magic is -1 and changes nothing" begin
    s = _xmem()
    s.magic = 0
    f0 = s.flags
    @test LKX.Sset_exception(s, _FakeEx(1)) == -1
    @test LKX.Sset_exception(s, nothing) == -1
    @test s.exception === nothing
    @test s.flags == f0
end

@testset "e04 core Sset_exception does not follow upstream" begin
    a = _xmem()
    b = _xmem()
    a.upstream = b
    @test LKX.Sset_exception(a, _FakeEx(1)) == 0
    @test _xex(a) isa _FakeEx
    @test b.exception === nothing
    @test (b.flags & LKX.SIO_FERR) == 0
end

@testset "e05 Sclearerr drops the record of the stream and of its downstream" begin
    a = _xmem()
    b = _xmem()
    a.downstream = b
    @test LKX.Sset_exception(a, _FakeEx(1)) == 0
    @test LKX.Sset_exception(b, _FakeEx(2)) == 0
    @test _xex(a) !== nothing && _xex(b) !== nothing
    LKX.Sclearerr(a)
    @test a.exception === nothing
    @test b.exception === nothing
    @test (a.flags & LKX.SIO_FERR) == 0
    @test (b.flags & LKX.SIO_FERR) == 0
end

"Term reference holding `t`."
function _x_ref(ld, t::_X)
    r = LKX.PL_new_term_ref(ld)
    LKX.putSlotValue!(ld, r + 1, t)
    return r
end

"`f(ld, s, ball)` inside a foreign frame, on the host's user_error."
function _x_with(f)
    gd = LKX.PL_global_data{_X}()
    ld = LKX.PL_local_data{_X}(gd)
    s = LKX.set_standard_stream!(ld, LKX.SNO_USER_ERROR, IOBuffer())
    fid = LKX.PL_open_foreign_frame(ld)
    try
        f(ld, s)
    finally
        LKX.PL_clear_exception(ld)
        LKX.PL_discard_foreign_frame(ld, fid)
    end
    return nothing
end

const _X_BALL = () -> _xf(:error, _xf(:io_error, _xs(:read), _xs(:a_file)), _xs(:ctx))

@testset "e06 Sset_exception(ld, s, ex) then reportStreamError raises exactly ex" begin
    _x_with() do ld, s
        ex = _x_ref(ld, _X_BALL())
        @test LKX.Sset_exception(ld, s, ex) == 0
        @test (s.flags & LKX.SIO_FERR) != 0
        @test s.exception !== nothing
        @test s.exception[] isa LKX.StreamException{_X}
        @test ld.exception_term == 0                        # nothing pending: nothing to clear
        @test LKX.reportStreamError(ld, s)                  # rc of PL_raise_exception
        @test ld.exception_term != 0
        @test lk_eq(lk_answer(ld, ld.exception_term), _X_BALL())
        @test s.exception === nothing                       # the record is dropped
        @test (s.flags & (LKX.SIO_FERR | LKX.SIO_WARN)) == 0  # Sclearerr
    end
end

@testset "e07 an equal pending exception is cleared; a different one is kept" begin
    _x_with() do ld, s
        pend = _x_ref(ld, _X_BALL())
        @test LKX.PL_raise_exception(ld, pend)
        @test ld.exception_term != 0
        ex = _x_ref(ld, _X_BALL())                          # a distinct term, ==/2-equal to the pending one
        @test LKX.Sset_exception(ld, s, ex) == 0
        @test ld.exception_term == 0                        # cleared: reportStreamError raises it again
        @test s.exception !== nothing
        @test LKX.reportStreamError(ld, s)
        @test lk_eq(lk_answer(ld, ld.exception_term), _X_BALL())
        LKX.PL_clear_exception(ld)

        other = _x_ref(ld, _xs(:other_ball))
        @test LKX.PL_raise_exception(ld, other)
        ex2 = _x_ref(ld, _X_BALL())
        @test LKX.Sset_exception(ld, s, ex2) == 0
        @test ld.exception_term != 0                        # a different pending exception is kept
        @test lk_eq(lk_answer(ld, ld.exception_term), _xs(:other_ball))
        @test s.exception !== nothing
        @test !LKX.reportStreamError(ld, s)                 # `if (exception_term) return false`: the record stays
        @test s.exception !== nothing
        @test lk_eq(lk_answer(ld, ld.exception_term), _xs(:other_ball))
    end
end

@testset "e08 Sset_exception(ld, s, 0) and a wrong magic drop or refuse the record" begin
    _x_with() do ld, s
        ex = _x_ref(ld, _X_BALL())
        @test LKX.Sset_exception(ld, s, ex) == 0
        @test LKX.Sset_exception(ld, s, 0) == 0
        @test s.exception === nothing
        @test (s.flags & LKX.SIO_FERR) == 0
        t = _xmem()
        t.magic = 0
        @test LKX.Sset_exception(ld, t, ex) == -1
        @test t.exception === nothing
    end
end

@testset "e09 an error state without a record still raises the stream error (no regression)" begin
    _x_with() do ld, s
        LKX.Sseterr(s, LKX.SIO_FERR, "a failure")
        @test !LKX.reportStreamError(ld, s)
        @test ld.exception_term != 0
        @test (s.flags & LKX.SIO_FERR) == 0
    end
end
