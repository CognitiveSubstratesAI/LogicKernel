# ORIGINAL: HALT1's gate (pl-prims.c halt/1, pl-fli.c PL_halt haltProlog PL_abort_process, pl-init.c PL_cleanup, pl-pro.c abortProlog raise_halt_exception abort/0,
# pl-wam.c handles_unwind, pl-setup.c PL_get_signum_ex signal_index) against swipl 10.1.19; evidence/HALT1/handoff.md section 2 is the table of pins.
# test/core_lang/test_halt_swipl.jl — halt/1 and abort/0: the ball `unwind(halt(Code))` (Code = Status & 0xffff) and `unwind(abort)`, the signal names
# (128 + signal, no cancel), the errors of the argument, the process exit through the seam, and the cancel limit of `cancel_halt/1`.
#   * Every test sets `gd.halt_exit = false` (src/pl-global.jl): the process does not end, `gd.halt_exited` records the RAW status of each halt (the flags
#     included: `halt(3)` records `3 | PL_HALT_WITH_EXCEPTION`; the process takes `& 0xff`).
#   * Every ball and every exit status is swipl's, PINNED (swipl 10.1.19, LC_ALL=C, one process per row, two runs byte-identical); with `swipl` on PATH the
#     live answers are compared with the pins too (`catch(G, B, (write_canonical(B), nl, throw(B)))`: the ball, then the process exit code).
#   * The rows that need `catch/3` to RUN the handler of an `unwind(_)` ball (da14a14: `'$recover_and_rethrow'/2`) or the loader's `at_halt/1` (boot/init.pl)
#     are probed at run time and SKIPPED with a note on stderr that names the missing piece (the last testset).
# UNVERIFIED on the kernel: gate decides (every pin is swipl's; the rows were not run on the kernel).
using Test, LogicKernel
# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const LK = LogicKernel
include(joinpath(@__DIR__, "rules_common.jl"))

# a fresh database whose halts are recorded, never carried out
function _hdb()::_RDB
    db = _RDB()
    db.gd.halt_exit = false
    return db
end

"""
`goal` run once through the query API: `(status, ball)`; `ball` is the exception as `write_canonical/1` writes it, or "" where there is none.
`except_halt`: the query is opened with `PL_Q_EXCEPT_HALT` (the toplevel's flag), so `halt/1` raises `unwind(halt(_))` instead of ending the process.
"""
function _hrun(db::_RDB, goal::_R; except_halt::Bool=true)::Tuple{Int, String}
    gd, ld = db.gd, db.ld
    _, n = _rfunctor(goal)
    fid = LK.PL_open_foreign_frame(ld)
    args = LK.PL_new_term_refs(ld, n)
    pvm = LK.PutVarMap()
    for i in 1:n
        LK.putSlotValue!(ld, args + i, child(goal, i + 1), pvm)
    end
    flags = LK.PL_Q_NORMAL | LK.PL_Q_EXT_STATUS
    except_halt && (flags |= LK.PL_Q_EXCEPT_HALT)
    qid = LK.PL_open_query(gd, ld, nothing, flags, _rproc(db, goal), args)
    rc = Int(LK.PL_next_solution(gd, ld, qid))
    ball = if rc == Int(LK.PL_S_EXCEPTION)
        _rcanonical(lk_answer(ld, LK.PL_exception(ld, qid)))
    else
        ""
    end
    LK.PL_close_query(ld, qid)
    LK.PL_discard_foreign_frame(ld, fid)
    return (rc, ball)
end

_hint(i::Integer) = _rf("halt", _rg(Int64(i)))
_hatom(a::AbstractString) = _rf("halt", _rs(a))

"The ball `unwind(halt(Code))` as `write_canonical/1` writes it."
_hball(code::Integer) = "unwind(halt($code))"

"swipl's answer to `goal`: the ball its `catch/3` wrapper writes, and the exit code of the process (nothing if swipl is off the PATH)."
function _hlive(goal::_R)::Union{Nothing, Tuple{String, Int}}
    _R_SWIPL || return nothing
    text = "catch(" * _rsrc(goal) * ",B,(write_canonical(B),nl,throw(B)))"
    out = IOBuffer()
    proc = run(
        pipeline(
            ignorestatus(
                addenv(`swipl -q -f none --no-tty -g $text -t true`, "LC_ALL" => "C")
            );
            stdin=devnull, stdout=out, stderr=devnull
        )
    )
    return (String(strip(String(take!(out)))), proc.exitcode)
end

# one row: the kernel's ball (and nothing recorded by the seam), and swipl's ball and exit status
function _hrow(goal::_R, ball::String, exit_status::Int; live::Bool=true)
    db = _hdb()
    rc, got = _hrun(db, goal)
    @test rc == Int(LK.PL_S_EXCEPTION)
    @test got == ball
    @test isempty(db.gd.halt_exited)                    # the exception path never reaches the seam
    if live
        theirs = _hlive(goal)
        if theirs !== nothing
            @test theirs[1] == ball
            @test theirs[2] == exit_status
        elseif _R_SWIPL_REQUIRED
            error("no swipl on PATH")
        end
    end
    return nothing
end

@testset "halt/1 and abort/0: the ball of an EXCEPT_HALT query and the exit status, equal swipl's" begin
    # integers: the code is Status & 0xffff, the process takes & 0xff (h09, h10, h23, g07)
    for (st, code, exit_status) in (
        (0, 0, 0), (3, 3, 3), (-1, 65535, 255), (255, 255, 255), (256, 256, 0),
        (65536, 0, 0)
    )
        _hrow(_hint(st), _hball(code), exit_status)
    end
    # integers 31 and 32 are plain statuses; only a NAME is range-checked
    _hrow(_hint(31), _hball(31), 31)
    _hrow(_hint(32), _hball(32), 32)
    # a signal name: 128 + signal (g01, g02, g03 and the rest of the table)
    for (name, code) in (
        ("term", 143), ("SIGTERM", 143), ("int", 130), ("SIGterm", 143), ("usr1", 138),
        ("SIGusr1", 138), ("stop", 147), ("winch", 156), ("pwr", 158), ("sys", 159)
    )
        _hrow(_hatom(name), _hball(code), code)
    end
    # abort/0: the ball unwind(abort), exit 1 (h02 without the handler)
    _hrow(_rs("abort"), "unwind(abort)", 1)
    # the ball is also raised without the flag (abortProlog does not test it)
    let db = _hdb()
        rc, ball = _hrun(db, _rs("abort"); except_halt=false)
        @test rc == Int(LK.PL_S_EXCEPTION)
        @test ball == "unwind(abort)"
        @test isempty(db.gd.halt_exited)
    end
    # halt inside a negation, and inside a query of its own whose parent has the flag (h18/h26/h27 family; sig_atomic/1 opens a query)
    _hrow(_rf("\\+", _rf("\\+", _hint(16))), _hball(16), 16)
    let db = _hdb()
        X = _rv(1)
        _radd!(db, _rf("hw", X), _rf("halt", X))
        rc, ball = _hrun(db, _rf("sig_atomic", _rf("hw", _rg(3))))
        @test rc == Int(LK.PL_S_EXCEPTION)
        @test ball == _hball(3)
        @test isempty(db.gd.halt_exited)
    end
    # handles_unwind: no query running, none handles it
    let db = _hdb()
        @test !LK.handles_unwind(db.ld, 0, LK.PL_Q_EXCEPT_HALT)
    end
end

const _HCTX = "context(:(system,/(halt,1)),_)"       # PL_error's context: the running foreign predicate, halt/1

@testset "halt/1: the errors of the argument equal swipl's (h05-h08, h20, h21, h24, g05, g06)" begin
    for (goal, formal, live) in (
        (_hatom("foo"), "domain_error(signal,foo)", true),                    # h05
        (_rf("halt", _rv(1)), "instantiation_error", true),                   # h06
        (_rf("halt", _rg(1.5)), "type_error(integer,1.5)", true),             # h07
        (_hint(99999999999), "representation_error(int)", true),              # h08
        (_rf("halt", _rg("3")), "type_error(integer,\"3\")", true),           # h24
        (_rf("halt", _rf("foo", _rg(1))), "type_error(integer,foo(1))", true),   # g05
        (_rf("halt", _rnil()), "type_error(signal,[])", true),                # g06: [] is no text atom
        (_hatom("sigterm"), "domain_error(signal,sigterm)", true),            # h20: a lowercase `sig` prefix is not stripped
        (_hatom("not_a_signal"), "domain_error(signal,not_a_signal)", true),  # h21
        (_hatom("SIG"), "domain_error(signal,'SIG')", true),                  # the prefix alone
        (_hatom("info"), "domain_error(signal,info)", false),                 # no Linux number for info and emt (DIVERGES: kernel table)
        (_hatom("emt"), "domain_error(signal,emt)", false)
    )
        _hrow(goal, "error(" * formal * "," * _HCTX * ")", 2; live=live)      # an uncaught error ends the -g goal with status 2
    end
end

# the kernel's text of `current_prolog_flag(exit_status, N)`
function _hexit_flag(db::_RDB)::String
    ans = _rcall(db, _rf("current_prolog_flag", _rs("exit_status"), _rv(1)))
    return only(ans)[1]
end

@testset "halt/1 in a query WITHOUT PL_Q_EXCEPT_HALT: the clean-up, the flag exit_status and the seam record the status" begin
    # (goal, raw status without the flags, signal name?) ; the raw status the seam records is that | PL_HALT_WITH_EXCEPTION [| PL_CLEANUP_NO_CANCEL]
    for (goal, code, named) in (
        (_hint(3), 3, false), (_hint(0), 0, false), (_hint(-1), 65535, false),
        (_hint(256), 256, false), (_hint(65536), 0, false),
        (_hatom("term"), 143, true), (_hatom("SIGTERM"), 143, true),
        (_hatom("int"), 130, true),
        (_hatom("usr1"), 138, true), (_hatom("sys"), 159, true)
    )
        db = _hdb()
        rc, ball = _hrun(db, goal; except_halt=false)
        @test rc == Int(LK.PL_S_FALSE)                  # the seam returned: PL_halt returns false, halt/1 fails
        @test ball == ""
        raw = only(db.gd.halt_exited)
        @test raw & 0xffff == code                      # the whole status, the flags above bit 16
        @test raw & 0xff == code & 0xff                 # what the process takes
        @test (raw & Int(LK.PL_HALT_WITH_EXCEPTION)) != 0
        raw < 0 || @test ((raw & Int(LK.PL_CLEANUP_NO_CANCEL)) != 0) == named   # halt(-1) is all bits set
        @test _hexit_flag(db) == "current_prolog_flag(exit_status,$code)"
        @test db.gd.halt_cleaning == LK.CLN_NORMAL      # reset where the seam is off (DIVERGES (a))
        @test db.gd.halt_status == 0
        @test db.gd.halt_thread == 0
        theirs = _hlive(goal)                           # the process exit status is the low byte, whatever the query
        if theirs !== nothing
            @test theirs[2] == code & 0xff
        elseif _R_SWIPL_REQUIRED
            error("no swipl on PATH")
        end
    end
    # halt(abort): no ball, the status 134 (PL_abort_process: haltProlog then abort()), in either kind of query; swipl is not asked (it dumps core)
    for except_halt in (false, true)
        db = _hdb()
        rc, ball = _hrun(db, _hatom("abort"); except_halt=except_halt)
        @test rc == Int(LK.PL_S_FALSE)
        @test ball == ""
        @test db.gd.halt_exited == [134]
        @test _hexit_flag(db) == "current_prolog_flag(exit_status,134)"
    end
    # three halts in one database: each recorded, the flag follows the last (a second setPrologFlag of exit_status is accepted)
    let db = _hdb()
        for st in (3, 4, 5)
            rc, _ = _hrun(db, _hint(st); except_halt=false)
            @test rc == Int(LK.PL_S_FALSE)
        end
        @test [raw & 0xffff for raw in db.gd.halt_exited] == [3, 4, 5]
        @test _hexit_flag(db) == "current_prolog_flag(exit_status,5)"
    end
end

# `'$run_at_halt' :- assertz(user:hook_ran(a)), fail.` in the system module: what `at_halt/1` with `cancel_halt/1` comes to when the hook vetoes
function _hhook!(db::_RDB, body::_R)
    gd, ld = db.gd, db.ld
    sys = LK.MODULE_system(gd)
    head = _rs("\$run_at_halt")
    pr = LK.lookupProcedure(head, 0, sys)
    cl = LK.compileClause(gd, ld, head, body, pr, sys)
    LK.assertDefinition!(gd, pr.definition, cl, LK.CL_END)
    return nothing
end
_hveto_hook!(db::_RDB) =
    _hhook!(
        db,
        _rconj(
            _rf("assertz", _rf(":", _rs("user"), _rf("hook_ran", _rs("a")))), _rs("fail")
        )
    )

# how many times the hook ran (user:hook_ran/1 has one fact per run; before the first run the predicate is unknown: 0)
function _hruns(db::_RDB)::Int
    ans = _rcall(db, _rf("hook_ran", _rv(1)))
    return length(ans) == 1 && startswith(ans[1][1], "exception") ? 0 : length(ans)
end

# The vetoing `'$run_at_halt'` below is the WHOLE procedure of the row: a booted copy carries boot/init.pl's own `'$run_at_halt'/0` clauses
# (they run the at_halt/1 goals and succeed, so the appended veto clause is never reached and the halt is not cancelled), so these rows
# build the UNBOOTED database; the booted system's own `'$run_at_halt'` is the subject of no row here.
function _hdb_unbooted()::_RDB
    db = _RDB_unbooted()
    db.gd.halt_exit = false
    return db
end

@testset "a vetoing hook cancels a halt nine times, the tenth goes ahead (MAX_HALT_CANCELLED); a signal name or halt(abort) is not cancelled" begin
    let db = _hdb_unbooted()
        _hveto_hook!(db)
        for k in 1:9
            rc, ball = _hrun(db, _hint(4); except_halt=false)
            @test rc == Int(LK.PL_S_TRUE) || rc == Int(LK.PL_S_LAST)   # PL_halt returned true: halt/1 SUCCEEDS (h12)
            @test ball == ""
            @test isempty(db.gd.halt_exited)
            @test db.gd.halt_cancelled == k
            @test _hruns(db) == k
            @test db.gd.halt_cleaning == LK.CLN_NORMAL
            @test db.gd.halt_status == 0
            @test db.gd.halt_thread == 0
        end
        @test _hexit_flag(db) == "current_prolog_flag(exit_status,4)"
        rc, ball = _hrun(db, _hint(4); except_halt=false)              # the tenth: ++halt_cancelled < 10 is false
        @test rc == Int(LK.PL_S_FALSE)
        @test ball == ""
        @test [raw & 0xffff for raw in db.gd.halt_exited] == [4]
        @test db.gd.halt_cancelled == 10
        @test _hruns(db) == 10
    end
    # NO_CANCEL: a signal name goes ahead at once, the hook runs once
    let db = _hdb_unbooted()
        _hveto_hook!(db)
        rc, _ = _hrun(db, _hatom("term"); except_halt=false)
        @test rc == Int(LK.PL_S_FALSE)
        @test [raw & 0xffff for raw in db.gd.halt_exited] == [143]
        @test db.gd.halt_cancelled == 0
        @test _hruns(db) == 1
    end
    # halt(abort): haltProlog with NO_CANCEL, the hook runs once, the status is 134
    let db = _hdb_unbooted()
        _hveto_hook!(db)
        rc, _ = _hrun(db, _hatom("abort"); except_halt=false)
        @test rc == Int(LK.PL_S_FALSE)
        @test db.gd.halt_exited == [134]
        @test db.gd.halt_cancelled == 0
        @test _hruns(db) == 1
    end
    # the EXCEPT_HALT query raises before any clean-up: the hook does not run
    let db = _hdb_unbooted()
        _hveto_hook!(db)
        rc, ball = _hrun(db, _hint(4))
        @test rc == Int(LK.PL_S_EXCEPTION)
        @test ball == _hball(4)
        @test _hruns(db) == 0
        @test db.gd.halt_cancelled == 0
    end
end

@testset "signal_index and the signal table (pl-setup.c)" begin
    for (name, num) in (
        ("term", 15), ("SIGTERM", 15), ("SIGterm", 15), ("sigterm", -1), ("SIG", -1),
        ("nosuch", -1),
        ("", -1), ("SIGHUP", 1), ("hup", 1), ("io", 29), ("poll", 29), ("SIGVTALRM", 26),
        ("stkflt", 16), ("winch", 28), ("sys", 31), ("emt", -1), ("info", -1)
    )
        @test LK.signal_index(name) == num
    end
    @test LK.signal_index("io") == LK.signal_index("poll")
    @test length(LK.SIGNAMES) == 32
    @test all(n -> 1 <= n[2] < 32, LK.SIGNAMES)                       # every entry is in the range PL_get_signum_ex accepts
    @test length(unique(first.(LK.SIGNAMES))) == 32                    # no name twice
end

# ── the rows gated after the stack (da14a14: catch/3 runs the handler of an unwind(_) ball and re-raises it) and the loader (boot/init.pl: at_halt/1) ──
# Each row is run on a fresh database; a NotPortedError (the kernel refuses what is not ported yet) is a SKIP with the reason on stderr, never a pass.
_hlog(t::_R) = _rf("assertz", _rf(":", _rs("user"), _rf("hl", t)))      # the log: one fact user:hl/1 per entry, read back in order

function _hlogged(db::_RDB)::Vector{String}
    ans = _rcall(db, _rf("hl", _rv(1)))
    length(ans) == 1 && startswith(ans[1][1], "exception") && return String[]    # hl/1 unknown: nothing logged
    return [a for (a, _) in ans]
end

function _hskip(why::String)
    println(stderr, "SKIP test_halt_swipl: ", why)
    @test_skip false
    return nothing
end

"""
One gated row: the clause `name :- body` run in a fresh database. `expect`: `:ball` (an EXCEPT_HALT query ends with `ball`), `:fails` (no flag: the seam
records the halt, halt/1 fails) or `:succeeds` (no flag, a hook cancelled the halt: the goal goes on). `log` is the `hl/1` entries; `exited` the codes
(`& 0xffff`) the seam recorded; `exit_status` the exit code of swipl's process.
"""
function _hgated(
    name::String, body::_R, expect::Symbol, ball::String, log::Vector{String},
    exited::Vector{Int}, exit_status::Int
)
    db = _hdb()
    _radd!(db, _rs(name), body)
    res = try
        _hrun(db, _rs(name); except_halt=(expect === :ball))
    catch e
        e isa LK.NotPortedError || rethrow()
        return _hskip("$name: $(e.what) ($(e.step))")
    end
    rc, got = res
    if expect === :ball
        @test rc == Int(LK.PL_S_EXCEPTION)
        @test got == ball
    elseif expect === :fails
        @test rc == Int(LK.PL_S_FALSE)
        @test got == ""
    else
        @test rc == Int(LK.PL_S_TRUE) || rc == Int(LK.PL_S_LAST)
        @test got == ""
    end
    @test _hlogged(db) == log
    @test [raw & 0xffff for raw in db.gd.halt_exited] == exited
    theirs = _hlive(body)
    if theirs !== nothing
        expect === :ball && @test theirs[1] == ball
        @test theirs[2] == exit_status
    elseif _R_SWIPL_REQUIRED
        error("no swipl on PATH")
    end
    return nothing
end

@testset "catch/3, call_cleanup/2 and setup_call_cleanup/3 around halt/1 and abort/0 (needs da14a14; SKIPPED where the kernel refuses)" begin
    probe = _hdb()
    catch_runs =
        try
            _hrun(
                probe,
                _rf("catch", _rf("throw", _rf("unwind", _rs("x"))), _rv(1), _rs("true"))
            )
            true
        catch e
            e isa LK.NotPortedError || rethrow()
            println(
                stderr,
                "SKIP test_halt_swipl: catch/3 refuses an unwind(_) ball: ",
                e.what,
                " (",
                e.step,
                "); the rows need da14a14 (wip/lb4b2c) and the booted init.pl"
            )
            false
        end
    E, S = _rv(1), _rv(2)
    h(n) = _hint(n)
    rows = (
        # name, goal, ball, log, exit status of the process
        ("hg01", _rf("catch", h(3), E, _hlog(E)), _hball(3), ["hl(unwind(halt(3)))"], 3),          # h01
        (
            "hg16",
            _rf("catch", h(8), _rf("unwind", _rf("halt", S)), _hlog(_rf("got", S))),
            _hball(8),
            ["hl(got(8))"],
            8
        ),  # h16
        ("hg08", _rf("catch", h(3), _rv(3), _rs("true")), _hball(3), String[], 3),                 # g08: the ball is re-raised after the handler
        ("hg09", _rf("catch", h(3), _rv(3), _rs("fail")), _hball(3), String[], 3),                 # g09
        (
            "hg02",
            _rf("catch", _rs("abort"), E, _hlog(E)),
            "unwind(abort)",
            ["hl(unwind(abort))"],
            1
        ),   # h02
        (
            "hg28",
            _rf("catch", _rs("abort"), _rf("unwind", _rs("abort")), _hlog(_rs("caught"))),
            "unwind(abort)",
            ["hl(caught)"],
            1
        ),   # h28
        ("hg15", _rf("catch", _rf("call_cleanup", h(7), _hlog(_rs("c1"))), E, _hlog(E)),
            _hball(7),
            ["hl(c1)", "hl(unwind(halt(7)))"], 7),                                                 # h15: the cleanup runs, then the handler sees the ball
        (
            "hg03",
            _rf("setup_call_cleanup", _rs("true"), h(3), _hlog(_rs("cleanup"))),
            _hball(3),
            ["hl(cleanup)"],
            3
        ),   # h03
        (
            "hg29",
            _rf("setup_call_cleanup", _rs("true"), _rs("abort"), _hlog(_rs("cleanup"))),
            "unwind(abort)",
            ["hl(cleanup)"],
            1
        ),   # h29
        (
            "hg10",
            _rf("catch", _rf("call_cleanup", _rs("abort"), _rs("true")), E, _hlog(E)),
            "unwind(abort)",
            ["hl(unwind(abort))"],
            1
        ),   # g10
        ("hg18", _rf("findall", _rs("x"), h(10), _rv(4)), _hball(10), String[], 10)               # h18: not gated on catch/3 itself
    )
    for (name, goal, ball, log, st) in rows
        if !catch_runs && !startswith(name, "hg18")
            _hskip("$name: catch/3 refuses an unwind(_) ball (da14a14 not in this tree)")
            continue
        end
        _hgated(name, goal, :ball, ball, log, Int[], st)
    end
end

@testset "at_halt/1 and cancel_halt/1 (needs the loader's boot/init.pl; SKIPPED where at_halt/1 is not defined)" begin
    probe = _hdb()
    # the baseline of every row below, asserted whether or not the loader is there: with no hook registered the halt goes straight to the seam
    # (pl-init.c PL_cleanup: `$run_at_halt` not defined or empty), status 2, and halt/1 fails (the seam returned)
    let db = _hdb()
        rc, got = _hrun(db, _hint(2); except_halt=false)
        @test rc == Int(LK.PL_S_FALSE)
        @test got == ""
        @test [raw & 0xffff for raw in db.gd.halt_exited] == [2]
    end
    pr = LK.lookupProcedure(_rs("at_halt"), 1, LK.MODULE_system(probe.gd))
    if !LK.isDefinedProcedure(probe.gd, pr)
        println(
            stderr,
            "SKIP test_halt_swipl: at_halt/1 is not defined in this tree (boot/init.pl is the loader's); the h04, h12-h14, h22, h25 rows wait for it"
        )
        @test_skip false
    else
        a(g) = _rf("at_halt", g)
        h(n) = _hint(n)
        # name, goal, expect, log, exited codes, exit status of swipl's process
        _hgated(
            "ha04",
            _rconj(a(_hlog(_rs("a"))), a(_hlog(_rs("b"))), h(2)),
            :fails,
            "",
            ["hl(b)", "hl(a)"],
            [2],
            2
        )     # h04: last registered, first run
        _hgated(
            "ha12",
            _rconj(a(_rf("cancel_halt", _rs("because"))), h(4), _hlog(_rs("after"))),
            :succeeds,
            "",
            ["hl(after)"],
            Int[],
            0
        )   # h12
        _hgated("ha13", _rconj(a(_rs("fail")), h(5)), :fails, "", String[], [5], 5)                               # h13
        _hgated(
            "ha14",
            _rconj(
                a(
                    _rconj(
                        _rf("current_prolog_flag", _rs("exit_status"), _rv(1)),
                        _hlog(_rf("status", _rv(1)))
                    )
                ),
                h(6)
            ),
            :fails, "", ["hl(status(6))"], [6], 6                                                                  # h14
        )
        _hgated(
            "ha22",
            _rconj(a(_rconj(_hlog(_rs("h1")), h(12))), h(13)),
            :fails,
            "",
            ["hl(h1)"],
            [13],
            13
        )        # h22: a halt in a hook does not recurse
        _hgated(
            "ha25",
            _rconj(a(_rf("throw", _rs("oops"))), h(14)),
            :fails,
            "",
            String[],
            [14],
            14
        )               # h25
    end
end

@testset "the pieces called directly: PL_get_signum_ex, PL_cleanup, haltProlog, raise_halt_exception, and a hook that raises or halts" begin
    # PL_get_signum_ex on an integer: 1..31 is the number, the rest a domain error (the rows through halt/1 take an atom only)
    for (n, ok) in ((0, false), (1, true), (31, true), (32, false), (-3, false))
        db = _hdb()
        ld = db.ld
        t = LK.PL_new_term_ref(ld)
        LK.PL_put_integer(ld, t, n)
        r = LK.PL_get_signum_ex(ld, t)
        if ok
            @test r == n
            @test LK.PL_exception(ld, 0) == 0
        else
            @test r === nothing
            ex = LK.PL_exception(ld, 0)
            @test ex != 0
            @test occursin("domain_error(signal,$n)", _rcanonical(lk_answer(ld, ex)))
            LK.PL_clear_exception(ld)
        end
    end
    # a clean-up while one is running is refused (RECURSIVE) and leaves the state alone
    let db = _hdb()
        gd, ld = db.gd, db.ld
        gd.halt_cleaning = LK.CLN_PROLOG
        @test LK.PL_cleanup(gd, ld, 3) == LK.PL_CLEANUP_RECURSIVE
        @test !LK.haltProlog(gd, ld, 3)
        @test gd.halt_cleaning == LK.CLN_PROLOG
        @test isempty(gd.halt_exited)
    end
    # a clean-up in the normal state succeeds, sets the flag and ends in CLN_DATA; haltProlog goes on to CLN_ATEXIT
    let db = _hdb()
        gd, ld = db.gd, db.ld
        @test LK.PL_cleanup(gd, ld, 7 | LK.PL_CLEANUP_NO_CANCEL) == LK.PL_CLEANUP_SUCCESS
        @test gd.halt_cleaning == LK.CLN_DATA
        @test _hexit_flag(db) == "current_prolog_flag(exit_status,7)"
    end
    let db = _hdb()
        @test LK.haltProlog(db.gd, db.ld, 7)
        @test db.gd.halt_cleaning == LK.CLN_ATEXIT
    end
    # raise_halt_exception: no query handles it and no force: nothing raised; force: raised whatever the query
    let db = _hdb()
        ld = db.ld
        @test !LK.raise_halt_exception(ld, 3, false)
        @test LK.PL_exception(ld, 0) == 0
        @test LK.raise_halt_exception(ld, 65536 + 5, true)
        ex = LK.PL_exception(ld, 0)
        @test ex != 0
        @test _rcanonical(lk_answer(ld, ex)) == "unwind(halt(5))"
    end
    # a hook that raises does not cancel the halt: the exception counts as "did not cancel" (pl-init.c: the query's failure alone cancels)
    let db = _hdb()
        _hhook!(db, _rf("throw", _rs("oops")))
        rc, _ = _hrun(db, _hint(4); except_halt=false)
        @test rc == Int(LK.PL_S_FALSE)
        @test [raw & 0xffff for raw in db.gd.halt_exited] == [4]
        @test db.gd.halt_cancelled == 0
    end
    # a hook that halts and then fails: its query has PL_Q_EXCEPT_HALT, so the nested halt raises, the hook never reaches `fail`, nothing is cancelled
    let db = _hdb()
        _hhook!(db, _rconj(_hint(12), _rs("fail")))
        rc, _ = _hrun(db, _hint(4); except_halt=false)
        @test rc == Int(LK.PL_S_FALSE)
        @test [raw & 0xffff for raw in db.gd.halt_exited] == [4]
        @test db.gd.halt_cancelled == 0
    end
end
