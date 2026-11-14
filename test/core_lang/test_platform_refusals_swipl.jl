# ORIGINAL: R2's LB5-LB7 gate — the refusals by name of pl-load.c and pl-apple.c (+ the pins of PushTty/PopTty, pl-os.c); no swipl-devel counterpart.
# test/core_lang/test_platform_refusals_swipl.jl — what the kernel answers TODAY to a predicate the pin's swipl does not define on Linux
# (`$activate_static_extension/1`: only a build with `O_STATIC_EXTENSIONS` has it; `apple_current_locale_identifier/1`: macOS only):
# a NotPortedError that names the predicate and the pin's lines, where swipl answers existence_error(procedure, Name/1). Each
# row is a KNOWN DIFFERENCE pinned with swipl's exact answer (the pin's own swipl, queried 2026-11-11), and checked against live swipl
# when it is on PATH. UNTESTED when written (nothing compiled, LB5-LB7 relay 11).
using Test, LogicKernel

const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TL = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}, Bool})
_tls(x) = lk_sym(_TL, Symbol(x))

# the cases: id, goal, the name the kernel's refusal carries, the pin lines its `what` holds, the owner step, the pin's swipl answer
const _PR_CASES = [
    (
        "p01", "'\$activate_static_extension'(foo)", "activate_static_extension",
        "pl-load.c:450-540", "LB5-LB7", "existence_error(procedure,'\$activate_static_extension'/1)"
    ),
    (
        "p02", "apple_current_locale_identifier(_)", "apple_current_locale_identifier",
        "pl-apple.c:56-79", "APPLE1", "existence_error(procedure,apple_current_locale_identifier/1)"
    ),
]

"The exception the kernel raises running `goal` (a call of a predicate that is refused by name), or `nothing`."
function _pr_kernel(goal::String)
    f = joinpath(mktempdir(), "pr.pl")
    write(f, "t_pr(R) :- ( $goal ), R = done.\n")
    gd = LK.PL_global_data{_TL}()
    ld = LK.PL_local_data{_TL}(gd)
    st, _ = LK.load_file!(gd, ld, f)
    st === :ok || return ErrorException("load")
    proc = LK.isCurrentProcedure(sym_key(_tls("t_pr")), 1, LK.MODULE_user(gd))
    proc === nothing && return ErrorException("undefined")
    try
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 1)
        LK.putSlotValue!(ld, a + 1, mk_var(_TL, LK.fresh_var_keys!(1)), LK.PutVarMap())
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
        )
        LK.PL_next_solution(gd, ld, qid)
        LK.PL_close_query(ld, qid)
        LK.PL_close_foreign_frame(ld, fid)
    catch e
        return e
    end
    return nothing
end

"swipl's answer to `goal`: the printed error formal of `catch(Goal, error(E, _), true)`."
function _pr_swipl(goal::String)::String
    d = mktempdir()
    f = joinpath(d, "drv.pl")
    write(
        f,
        ":- initialization((catch(($goal), error(E, _), true), print(E), nl, halt)).\n"
    )
    return strip(read(pipeline(`swipl -q $f`; stderr=devnull), String))
end

@testset "the refusals by name of pl-load.c and pl-apple.c (known differences)" begin
    for (id, goal, name, pin, step, swipl_says) in _PR_CASES
        @testset "$id $name" begin
            err = _pr_kernel(goal)
            @test err isa LK.NotPortedError                  # the kernel names the predicate (swipl: existence_error)
            if err isa LK.NotPortedError
                @test kind(err.culprit) === SYM && sym_text(err.culprit) == name
                @test err.step == step
                @test occursin(name, err.what)
                @test occursin(pin, err.what)                # the pin's lines are in the text
            end
            swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
            if swipl !== nothing
                @test _pr_swipl(goal) == swipl_says          # swipl's own answer, live
            end
        end
    end
    @test allunique(first.(_PR_CASES)) && length(_PR_CASES) == 2
end

# PushTty and PopTty (pl-os.c:2294-2346, :2354-2379 at the pin; owner TOP1b). HAND-WRITTEN rows: swipl has no Prolog-visible PushTty, and a
# test run has no terminal, so the expected values are the C at the pin; each row names the exits it takes.
@testset "PushTty and PopTty: upstream's exits, the terminal refused by name (hand-written)" begin
    gd = LK.PL_global_data{_TL}()
    ld = LK.PL_local_data{_TL}(gd)
    s = LK.set_standard_stream!(ld, LK.SNO_USER_INPUT, IOBuffer())
    s.flags &= ~LK.SIO_ISATTY
    LK.clearPrologFlagMask!(ld, LK.PLFLAG_TTY_CONTROL)
    # (a) no terminal: `buf->mode = Sttymode(s)`, `buf->state = NULL`, then `succeed` before the mode is recorded
    buf = LK.ttybuf()
    @test LK.PushTty(ld, s, buf, LK.TTY_RAW)
    @test buf.mode == LK.TTY_COOKED && buf.state === nothing
    @test LK.Sttymode(s) == LK.TTY_COOKED
    # (b) a terminal, tty_control false: the same exit
    s.flags |= LK.SIO_ISATTY
    @test LK.PushTty(ld, s, buf, LK.TTY_RAW)
    @test LK.Sttymode(s) == LK.TTY_COOKED
    LK.Sset_ttymode(s, LK.TTY_RAW)                      # the stream's own mode is what `buf->mode` saves
    @test LK.PushTty(ld, s, buf, LK.TTY_COOKED)
    @test buf.mode == LK.TTY_RAW && LK.Sttymode(s) == LK.TTY_RAW
    LK.Sset_ttymode(s, LK.TTY_COOKED)
    # (c) a terminal, tty_control true: `Sset_ttymode(s, mode)` first, then the termios step, refused by name
    LK.setPrologFlagMask!(ld, LK.PLFLAG_TTY_CONTROL)
    err = try
        LK.PushTty(ld, s, buf, LK.TTY_RAW)
        nothing
    catch e
        e
    end
    @test err isa LK.NotPortedError
    if err isa LK.NotPortedError
        @test kind(err.culprit) === SYM && sym_text(err.culprit) == "PushTty"
        @test err.step == "TOP1b" && occursin("pl-os.c:2294-2346", err.what)
    end
    @test LK.Sttymode(s) == LK.TTY_RAW                  # recorded before the refusal, as upstream's order
    # (d) PopTty: the mode saved by PushTty comes back, no state saved: `true`
    @test LK.PopTty(ld, s, buf, true)
    @test LK.Sttymode(s) == LK.TTY_COOKED
    # (e) a saved state is refused by name
    buf.state = UInt8[0x01]
    err = try
        LK.PopTty(ld, s, buf, true)
        nothing
    catch e
        e
    end
    @test err isa LK.NotPortedError
    if err isa LK.NotPortedError
        @test kind(err.culprit) === SYM && sym_text(err.culprit) == "PopTty"
        @test err.step == "TOP1b" && occursin("pl-os.c:2354-2379", err.what)
    end
end
