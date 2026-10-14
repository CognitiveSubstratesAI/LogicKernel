# UPSTREAM: swipl-devel tests/core_text/test_io.pl @ 8609e216cab9
# CLASS: code
# COPYRIGHT: Copyright (c)  2011-2015, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
#
# swipl-devel's test_io.pl — the `io` unit's `no_protocol_out` — against write/2 on the standard
# alias `protocol` while no protocol stream is open (src/os/pl-file.jl `get_stream_handle`), under
# upstream's unit name. The goal is called through the query API and the ball read where the query
# ends, with `PL_exception`, as plunit's `error(existence_error(stream, protocol))` reads the one it
# caught: the formal term is compared, the context is not.
#
# NOT PORTED, and why:
#   io: no_protocol_in      read_term/3 on a stream; the kernel reads from text only until R2.
#   io: every other unit    open/4, open_null_stream/1, close/1, set_stream/2, current_input/1,
#                           current_output/1 — files and stream handles: R2.
#   stream_pair ×3          stream_pair/3: R2.
#   line_position ×15       with_output_to/2 and line_position/2: R2.
using Test, LogicKernel
const _TIO_LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TIO = lk_term_type(Union{Int64, Float64, String})
_tios(x) = lk_sym(_TIO, Symbol(x))
_tiof(f, xs::_TIO...) = mk_expr(_TIO, _TIO[_tios(f), xs...])

"The system predicate `name` called on `args` through the query API: `(rc, ball)`, the ball `nothing` when none is pending."
function _tiorun(gd, ld, name::String, args::_TIO...)
    proc = _TIO_LK.isCurrentProcedure(
        sym_key(_tios(name)), length(args), _TIO_LK.MODULE_system(gd)
    )
    fid = _TIO_LK.PL_open_foreign_frame(ld)
    a = _TIO_LK.PL_new_term_refs(ld, length(args))
    pvm = _TIO_LK.PutVarMap()  # one PutVarMap: these puts share their variables as one record does (L1b boundary, user 2026-10-14)
    for (i, x) in enumerate(args)
        _TIO_LK.putSlotValue!(ld, a + i, x, pvm)
    end
    qid = _TIO_LK.PL_open_query(
        gd, ld, nothing, _TIO_LK.PL_Q_CATCH_EXCEPTION | _TIO_LK.PL_Q_EXT_STATUS, proc, a
    )
    rc = _TIO_LK.PL_next_solution(gd, ld, qid)
    ex = _TIO_LK.PL_exception(ld, qid)
    ball = ex == 0 ? nothing : _TIO_LK.resolve_term(ld, _TIO_LK.slotValue(ld, ex + 1))
    _TIO_LK.PL_close_query(ld, qid)
    _TIO_LK.PL_close_foreign_frame(ld, fid)
    return (rc, ball)
end

@testset "io" begin
    gd = _TIO_LK.PL_global_data{_TIO}()
    ld = _TIO_LK.PL_local_data{_TIO}()
    # condition(\+ protocolling(_)): no protocol stream is open
    @test ld.IO_streams[_TIO_LK.SNO_PROTOCOL + 1] === nothing
    # PORT: test_io.pl no_protocol_out
    @testset "no_protocol_out" begin                # error(existence_error(stream, protocol))
        rc, ball = _tiorun(gd, ld, "write", _tios("protocol"), _tios("x"))
        @test rc == _TIO_LK.PL_S_EXCEPTION
        @test ball !== nothing && lk_name(child(ball, 1)) === :error &&
            lk_eq(
                child(ball, 2),
                _tiof("existence_error", _tios("stream"), _tios("protocol"))
            )
    end
end
