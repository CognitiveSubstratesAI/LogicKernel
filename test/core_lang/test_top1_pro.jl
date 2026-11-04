# ORIGINAL: TOP1 white-box rows (audit D-0402 item 2(b)) — pl-pro.c `resetProlog` (:60-94), `query_loop` (:147-218), `restore_after_exception`,
# `halt_from_exception`; pl-file.c `PL_write_prompt`, `PrologPrompt`, `validUserStreams`; pl-fli.c `PL_prompt_next`; pl-trace.c `resetTracer`,
# `enable_debug_on_interrupt`; pl-write.c `writeAtomToStream`. LK-only: swipl has no Prolog-visible `LD->prompt.next`, `LD->autoload.*` or
# `query_loop`, so the expected values are HAND-WRITTEN from the upstream C at the pin (swipl-devel cbf4e189) and checked against the kernel only;
# the prompt TEXT is compared with swipl in test_top1_prompt_swipl.jl.
# # UNVERIFIED on the kernel: gate decides (nothing in this file was run when it was written).
# test/core_lang/test_top1_pro.jl — on every term type:
#   * resetProlog: clears `autoload_nesting` and `autoload_loop` (the AUTOLOAD1 A2 DIVERGES); an error on `user_input` is cleared and
#     `prompt_next` set (an error-free `user_input` leaves it as it was); `Scurin`/`Scurout` become the user streams; the pending exception is
#     cleared; the debugger is reset; `clear_stacks` empties the stacks only without a global variable;
#   * PL_write_prompt writes `PrologPrompt`'s atom where `dowrite` and clears `prompt_next` either way; PrologPrompt: `prompt1/1`'s atom once,
#     else `prompt/2`'s at the start of a line, else nothing; PL_prompt_next sets the flag for `user_input` only; validUserStreams;
#   * query_loop: rc 1, 0 and -1; the loop runs again after an error and stops after a halt, an invalid user stream, or with `loop` false;
#     `unwind(abort)` runs the `abort` event and the loop goes on; `unwind(halt(N))` halts with `N & 0xff` through the `gd.halt_exit` seam;
#     the stacks are emptied before the first run; the flag `debug_on_interrupt` follows `loop`.
# Mutation-tested by tools/mutants/TOP1.py.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "rules_common.jl"))

"A database whose three user streams are buffers (`halt_exit` off): `(db, (inb, outb, errb), (ui, uo, ue))`."
function _tp_db(; booted::Bool=true)
    db = booted ? _RDB() : _RDB_unbooted()
    # the `informational` unwind(abort) message is print_message/2's since LB4 b2: a `user:message_hook/3` collector records it
    # (the unbooted database cannot load the collector, which needs load_files/2: its rows record no message)
    booted && lk_install_message_collector!(db.gd, db.ld; kinds=(:informational,))
    db.gd.halt_exit = false
    bufs = (IOBuffer(), IOBuffer(), IOBuffer())
    ld = db.ld
    ui = LK.set_standard_stream!(ld, LK.SNO_USER_INPUT, bufs[1])
    uo = LK.set_standard_stream!(ld, LK.SNO_USER_OUTPUT, bufs[2])
    ue = LK.set_standard_stream!(ld, LK.SNO_USER_ERROR, bufs[3])
    return db, bufs, (ui, uo, ue)
end

"What `uo` has written, flushed and taken out of its buffer."
function _tp_out(buf::IOBuffer, s)::String
    LK.Sflush(s)
    return String(take!(buf))
end

"`name :- body` (a fact for `body` nothing) in the module `system`: the goal `query_loop` runs."
function _tp_sys!(db::_RDB, name::Symbol, body::Union{Nothing, _R}=nothing)
    head = _rs(name)
    sys = LK.MODULE_system(db.gd)
    pr = LK.lookupProcedure(head, 0, sys)
    cl = LK.compileClause(db.gd, db.ld, head, body, pr, sys)
    LK.assertDefinition!(db.gd, pr.definition, cl, LK.CL_END)
    return nothing
end

"Declare `user:name/0` dynamic: the markers the system goals assert."
function _tp_dyn!(db::_RDB, names::Symbol...)
    for n in names
        LK.setDynamicDefinition!(LK.lookupProcedure(_rs(n), 0, db.user).definition, true)
    end
    return nothing
end
_tp_user(x::Symbol) = _rf(":", _rs(:user), _rs(x))
"Does `user:name` hold? (the marker was asserted)"
_tp_has(db::_RDB, name::Symbol) = !isempty(_rcall(db, _rs(name)))

const _TP_ABORTS = IdDict{Any, Int}()       # per local data: the unwind(abort) messages taken so far
"""
The `unwind(abort)` messages `printMessage` printed on `ld` so far: the collector's records since the last call are
taken (a query, so no exception may be pending) and added to the count.
"""
function _tp_aborts(ld)
    n = count(
        m -> m[1] === :informational && lk_eq(m[2], _rf("unwind", _rs(:abort))),
        lk_take_messages!(ld)
    )
    return _TP_ABORTS[ld] = get(_TP_ABORTS, ld, 0) + n
end

"The goals of the query_loop rows: a marker is asserted the first time the goal runs."
function _tp_loop_db(; booted::Bool=true)
    db, bufs, ss = _tp_db(; booted)
    _tp_dyn!(db, :tp_seen, :tp_seen2, :tp_seen3, :tp_ev_ran)
    _tp_sys!(db, :tp_ok)                                                    # a fact
    _tp_sys!(db, :tp_fail, _rs(:fail))
    _tp_sys!(db, :tp_throw, _rf("throw", _rs(:tp_ball)))
    # raises the first time, succeeds the second
    _tp_sys!(
        db, :tp_twice,
        _rf(
            ";", _rf("->", _tp_user(:tp_seen), _rs(:true)),
            _rconj(_rf("assertz", _tp_user(:tp_seen)), _rf("throw", _rs(:tp_ball)))
        )
    )
    # aborts the first time, succeeds the second
    _tp_sys!(
        db, :tp_abort_once,
        _rf(
            ";", _rf("->", _tp_user(:tp_seen2), _rs(:true)),
            _rconj(_rf("assertz", _tp_user(:tp_seen2)), _rs(:abort))
        )
    )
    # halts the first time, succeeds the second
    _tp_sys!(
        db, :tp_halt_once,
        _rf(
            ";", _rf("->", _tp_user(:tp_seen3), _rs(:true)),
            _rconj(_rf("assertz", _tp_user(:tp_seen3)), _rf("halt", _rg(3)))
        )
    )
    return db, bufs, ss
end

@testset "PL_prompt_next: the flag is set for user_input only (pl-fli.c:5345)" begin
    db, _, (ui, uo, ue) = _tp_db()
    ld = db.ld
    for s in (uo, ue)
        ld.prompt_next = false
        LK.PL_prompt_next(ld, s)
        @test ld.prompt_next === false
    end
    other = LK.Sopen_string(Vector{UInt8}(codeunits("x")), 1, "r")
    ld.prompt_next = false
    LK.PL_prompt_next(ld, other::LK.IOSTREAM)
    @test ld.prompt_next === false
    ld.prompt_next = false
    LK.PL_prompt_next(ld, ui)
    @test ld.prompt_next === true
end

@testset "PrologPrompt and PL_write_prompt (pl-file.c:3795, :1868)" begin
    db, (inb, outb, errb), (ui, uo, ue) = _tp_db()
    gd, ld = db.gd, db.ld
    # the default prompt, at the start of a line; the flag is cleared
    ld.prompt_next = true
    LK.PL_write_prompt(gd, ld, true)
    @test _tp_out(outb, uo) == "|: "
    @test ld.prompt_next === false
    # dowrite false: nothing written, the flag cleared all the same
    ld.prompt_next = true
    LK.PL_write_prompt(gd, ld, false)
    @test _tp_out(outb, uo) == ""
    @test ld.prompt_next === false
    # prompt/2's atom is the one written; prompt1/1's atom once, then prompt/2's again
    ld.prompt_current = _rs(Symbol("P2> "))
    LK.prompt1(ld, _rs(Symbol("P1> ")))
    LK.PL_write_prompt(gd, ld, true)
    @test _tp_out(outb, uo) == "P1> "
    LK.PL_write_prompt(gd, ld, true)
    @test _tp_out(outb, uo) == "P2> "
    # a prompt1/1 call arms it again
    LK.prompt1(ld, _rs(Symbol("P1> ")))
    @test LK.PrologPrompt(ld) === ld.prompt_first
    @test LK.PrologPrompt(ld) === ld.prompt_current                 # used: the second ask is prompt/2's
    # not at the start of a line: no prompt/2 text, prompt1/1's still
    ui.position.linepos = 3
    @test LK.PrologPrompt(ld) === nothing
    LK.PL_write_prompt(gd, ld, true)
    @test _tp_out(outb, uo) == ""
    LK.prompt1(ld, _rs(Symbol("P1m> ")))
    LK.PL_write_prompt(gd, ld, true)
    @test _tp_out(outb, uo) == "P1m> "
    # no user_output slot: nothing is written and the flag is cleared all the same (`s` is NULL in PL_write_prompt)
    ld.IO_streams[LK.SNO_USER_OUTPUT + 1] = nothing
    ld.prompt_next = true
    LK.PL_write_prompt(gd, ld, true)
    @test ld.prompt_next === false
    @test _tp_out(outb, uo) == ""
end

@testset "writeAtomToStream writes the text of the atom, unquoted (pl-write.c:1318)" begin
    db, (inb, outb, errb), (ui, uo, ue) = _tp_db()
    @test LK.writeAtomToStream(db.gd, db.ld, uo, _rs(Symbol("it's a b")))
    @test _tp_out(outb, uo) == "it's a b"
    @test LK.writeAtomToStream(db.gd, db.ld, uo, _rs(Symbol("")))
    @test _tp_out(outb, uo) == ""
end

@testset "validUserStreams: a user stream in error mode (pl-file.c:1488)" begin
    db, _, (ui, uo, ue) = _tp_db()
    ld = db.ld
    @test LK.validUserStreams(ld)
    for s in (ui, uo, ue)
        LK.Sseterr(s, LK.SIO_FERR, "boom")
        @test !LK.validUserStreams(ld)
        LK.Sclearerr(s)
        @test LK.validUserStreams(ld)
    end
    # a warning is not an error mode
    LK.Sseterr(ue, LK.SIO_WARN, "careful")
    @test LK.validUserStreams(ld)
    LK.Sclearerr(ue)
    # a missing stream counts as invalid
    ld.IO_streams[LK.SNO_USER_ERROR + 1] = nothing
    @test !LK.validUserStreams(ld)
end

@testset "resetTracer and enable_debug_on_interrupt (pl-trace.c:1882, :2092)" begin
    db, _, _ = _tp_db()
    ld = db.ld
    ld.debugstatus_tracing = true
    ld.debugstatus_debugging = true
    ld.debugstatus_skiplevel = UInt(7)
    LK.resetTracer(ld)
    @test !ld.debugstatus_tracing
    @test !ld.debugstatus_debugging
    @test ld.debugstatus_skiplevel == UInt(0)
    # the flag follows the argument where the flag `signals` allows it
    LK.setPrologFlagMask!(ld, LK.PLFLAG_SIGNALS)
    @test LK.enable_debug_on_interrupt(ld, true)
    @test LK.truePrologFlag(ld, LK.PLFLAG_DEBUG_ON_INTERRUPT)
    @test LK.enable_debug_on_interrupt(ld, false)
    @test !LK.truePrologFlag(ld, LK.PLFLAG_DEBUG_ON_INTERRUPT)
    LK.clearPrologFlagMask!(ld, LK.PLFLAG_SIGNALS)
    @test !LK.enable_debug_on_interrupt(ld, true)
    @test !LK.truePrologFlag(ld, LK.PLFLAG_DEBUG_ON_INTERRUPT)
end

@testset "resetProlog (pl-pro.c:60-94)" begin
    db, _, (ui, uo, ue) = _tp_db()
    gd, ld = db.gd, db.ld
    def = LK.lookupProcedure(_rs(:tp_chain), 0, db.user).definition
    other = LK.lookupProcedure(_rs(:tp_loop), 0, db.user).definition

    # the autoloader's chain and loop mark (the AUTOLOAD1 A2 DIVERGES)
    push!(ld.autoload_nesting, def)
    ld.autoload_loop = other
    @test !isempty(ld.autoload_nesting)
    @test LK.resetProlog(ld, false)
    @test isempty(ld.autoload_nesting)
    @test ld.autoload_loop === nothing

    # an error on user_input is cleared and the next read prompts; without an error the flag is left alone
    ld.prompt_next = false
    LK.resetProlog(ld, false)
    @test ld.prompt_next === false
    LK.Sseterr(ui, LK.SIO_FERR, "boom")
    @test LK.Sferror(ui) != 0
    LK.resetProlog(ld, false)
    @test LK.Sferror(ui) == 0
    @test ld.prompt_next === true

    # the current streams are the user streams again
    ld.IO_streams[LK.SNO_CURRENT_INPUT + 1] = LK.Sopen_string(UInt8[0x78], 1, "r")
    ld.IO_streams[LK.SNO_CURRENT_OUTPUT + 1] = ue
    LK.resetProlog(ld, false)
    @test LK.Scurin(ld) === ui
    @test LK.Scurout(ld) === uo

    # the pending exception and the debugger
    @test LK.abortProlog(ld) === false
    @test ld.exception_term != 0
    ld.debugstatus_tracing = true
    ld.debugstatus_skiplevel = UInt(5)
    LK.resetProlog(ld, false)
    @test ld.exception_term == 0
    @test !ld.debugstatus_tracing
    @test ld.debugstatus_skiplevel == UInt(0)

    # clear_stacks: the stacks are emptied (the foreign frames with them) only without a global variable
    n0 = ld.nfliframes
    LK.PL_open_foreign_frame(ld)
    LK.PL_open_foreign_frame(ld)
    @test ld.nfliframes == n0 + 2
    LK.resetProlog(ld, false)
    @test ld.nfliframes == n0 + 2                               # clear_stacks false: the frames stay
    ld.gvar_nb_vars[UInt64(1)] = UInt64(0)                      # a nb_setval/2 variable: we would lose it
    LK.resetProlog(ld, true)
    @test ld.nfliframes == n0 + 2
    empty!(ld.gvar_nb_vars)
    LK.resetProlog(ld, true)
    @test ld.nfliframes == n0                                   # emptyStacks!: the base frame only
end

@testset "halt_from_exception and restore_after_exception (pl-pro.c:100-145)" begin
    db, _, _ = _tp_db()
    gd, ld = db.gd, db.ld
    # a halt ball halts with Status & 0xff through the seam
    @test LK.raise_halt_exception(ld, 263, true)
    @test LK.classify_exception(ld, ld.exception_term) == LK.EXCEPT_HALT
    LK.halt_from_exception(gd, ld, ld.exception_term)             # with the seam off PL_halt returns false: the record is the answer
    @test [r & 0xffff for r in gd.halt_exited] == [7]
    LK.PL_clear_exception(ld)
    # another ball is left alone
    m0 = _tp_aborts(ld)                                           # read with no exception pending
    LK.abortProlog(ld)
    n = length(gd.halt_exited)
    LK.halt_from_exception(gd, ld, ld.exception_term)
    @test length(gd.halt_exited) == n
    # the abort ball: tracing and debugging off, the message printed; another ball prints nothing
    ld.debugstatus_tracing = true
    ld.debugstatus_debugging = true
    @test LK.restore_after_exception(gd, ld, ld.exception_term)
    @test !ld.debugstatus_tracing && !ld.debugstatus_debugging
    LK.PL_clear_exception(ld)
    @test _tp_aborts(ld) == m0 + 1
    LK.raise_halt_exception(ld, 1, true)
    @test LK.restore_after_exception(gd, ld, ld.exception_term)
    LK.PL_clear_exception(ld)
    @test _tp_aborts(ld) == m0 + 1                                # the halt ball printed no abort message
end

@testset "query_loop: the three results" begin
    db, _, _ = _tp_loop_db()
    gd, ld = db.gd, db.ld
    @test LK.query_loop(gd, ld, _rs(:tp_ok), false) == 1
    @test LK.query_loop(gd, ld, _rs(:tp_fail), false) == 0
    @test LK.query_loop(gd, ld, _rs(:tp_throw), false) == -1
    # the next run resets the engine: the pending exception does not leak into it
    @test LK.query_loop(gd, ld, _rs(:tp_ok), false) == 1
    @test ld.exception_term == 0
    # a goal that no clause defines raises, and the result is -1
    @test LK.query_loop(gd, ld, _rs(:tp_nosuch), false) == -1
end

@testset "query_loop: the stacks are emptied before the first run (clear_stacks)" begin
    # pl-pro.c resetProlog: `if ( !LD->gvar.nb_vars ) emptyStacks()` (we would lose nb_setval/2 variables). The UNBOOTED database
    # has none; a booted copy has the boot's (the next row)
    db, _, _ = _tp_loop_db(; booted=false)
    gd, ld = db.gd, db.ld
    @test isempty(ld.gvar_nb_vars)
    n0 = ld.nfliframes
    LK.PL_open_foreign_frame(ld)
    LK.PL_open_foreign_frame(ld)
    LK.PL_open_foreign_frame(ld)
    @test ld.nfliframes == n0 + 3
    @test LK.query_loop(gd, ld, _rs(:tp_ok), false) == 1
    @test ld.nfliframes == n0
end

@testset "query_loop: with nb_setval/2 variables the stacks are NOT emptied (resetProlog keeps them)" begin
    db, _, _ = _tp_loop_db()                                      # a booted copy: the boot's global variables
    gd, ld = db.gd, db.ld
    @test !isempty(ld.gvar_nb_vars)
    n0 = ld.nfliframes
    LK.PL_open_foreign_frame(ld)
    LK.PL_open_foreign_frame(ld)
    LK.PL_open_foreign_frame(ld)
    @test ld.nfliframes == n0 + 3
    @test LK.query_loop(gd, ld, _rs(:tp_ok), false) == 1
    @test ld.nfliframes == n0 + 3                                 # the frames stay: emptyStacks did not run
end

@testset "query_loop: after an error the goal runs again only with loop" begin
    db, _, _ = _tp_loop_db()
    gd, ld = db.gd, db.ld
    @test LK.query_loop(gd, ld, _rs(:tp_twice), false) == -1       # one run, the error
    @test _tp_has(db, :tp_seen)
    @test LK.query_loop(gd, ld, _rs(:tp_ok), false) == 1
    db2, _, _ = _tp_loop_db()
    @test LK.query_loop(db2.gd, db2.ld, _rs(:tp_twice), true) == 1  # the error, a second run, success
    @test _tp_has(db2, :tp_seen)
    # a goal that fails does not loop
    @test LK.query_loop(db2.gd, db2.ld, _rs(:tp_fail), true) == 0
end

@testset "query_loop: unwind(abort) runs the abort event and the loop goes on" begin
    for loop in (false, true)
        db, _, _ = _tp_loop_db()
        gd, ld = db.gd, db.ld
        _radd!(db, _rs(:tp_ev), _rf("assertz", _tp_user(:tp_ev_ran)))
        @test !isempty(_rcall(db, _rf("prolog_listen", _rs(:abort), _tp_user(:tp_ev))))
        rc = LK.query_loop(gd, ld, _rs(:tp_abort_once), loop)
        @test rc == (loop ? 1 : -1)
        @test _tp_has(db, :tp_seen2)
        @test _tp_has(db, :tp_ev_ran)                              # the `abort` event ran
        @test _tp_aborts(ld) == 1                                  # print_message(informational, unwind(abort))
    end
end

@testset "query_loop: unwind(halt(N)) halts and ends the loop" begin
    db, _, _ = _tp_loop_db()
    gd, ld = db.gd, db.ld
    @test LK.query_loop(gd, ld, _rs(:tp_halt_once), true) == -1    # no second run, although loop
    @test [r & 0xffff for r in gd.halt_exited] == [3]
    @test _tp_has(db, :tp_seen3)
end

@testset "query_loop: an invalid user stream ends the loop" begin
    db, _, (ui, uo, ue) = _tp_loop_db()
    gd, ld = db.gd, db.ld
    LK.Sseterr(ue, LK.SIO_FERR, "boom")                            # resetProlog clears user_input's error only
    @test LK.query_loop(gd, ld, _rs(:tp_twice), true) == -1
    LK.Sclearerr(ue)
    db2, _, _ = _tp_loop_db()
    @test LK.query_loop(db2.gd, db2.ld, _rs(:tp_twice), true) == 1  # the same goal and loop, valid streams
end

@testset "query_loop: the flag debug_on_interrupt follows loop (pl-pro.c:156)" begin
    for loop in (false, true)
        db, _, _ = _tp_loop_db()
        gd, ld = db.gd, db.ld
        LK.setPrologFlagMask!(ld, LK.PLFLAG_SIGNALS)
        LK.clearPrologFlagMask!(ld, LK.PLFLAG_DEBUG_ON_INTERRUPT)
        LK.query_loop(gd, ld, _rs(:tp_ok), loop)
        @test LK.truePrologFlag(ld, LK.PLFLAG_DEBUG_ON_INTERRUPT) == loop
    end
end
