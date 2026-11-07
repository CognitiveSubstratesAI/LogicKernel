# ORIGINAL: AUTOLOAD1 A2/A3/A5 rows (audit D-0387 item 3, D-0398, D-0416 item 2): the autoloader branch of `trapUndefined` (pl-proc.c:3008-3063
# at swipl-devel cbf4e189: `test_autoload_loop` :2932, `autoLoader` :2962, the retry loop) and the two LD fields `autoload.nesting`,
# `autoload.loop` (pl-global.h:897-899). LK-only white-box rows on the BOOTED database: the real `system:'$undefined_procedure'/4`
# (boot/init.pl:949) is the hook, and the rows steer it through upstream's own mechanism, `user:exception/3` clauses (init.pl:959-963,
# `exception(undefined_predicate, Pred, Action)`, `Pred` = `Name/Arity` in `user`, `Module:Name/Arity` elsewhere; dynamic + multifile).
# The expected values are read from the upstream C and the Prolog text and checked against the kernel; the swipl-COMPARED rows of the same
# mechanism are in test_autoload_swipl.jl. (Before the first boot these rows defined clauses in `system:'$undefined_procedure'/4`; the
# conversion keeps every kill row, refusal-flip rule D-0375/D-0376.)
# test/core_lang/test_autoload_trap.jl — on every term type:
#   * A2: a fresh local data has an empty `autoload_nesting` and `autoload_loop === nothing` (no reset code: upstream's `resetProlog`
#     belongs to the toplevel step);
#   * a hook `exception/3` clause: its Pred argument reaches the head, the answers `fail` (returns, no supervisor), `error` (S_UNDEF),
#     `retry` (the clause defines the predicate: returned DEFINED; it does not: the second round warns once and returns), any other atom
#     (the error label), the retry's post-increment (the clause runs twice); no clause matching: the real hook's own clauses answer
#     (`$autoload` fails: `error`);
#   * `test_autoload_loop`: a definition on the chain is a loop (false, `autoload_loop` set and never cleared, the report lines, innermost
#     first, up to the definition), one that is not on it is not; `trapUndefined` returns at once and never calls the hook;
#   * `autoLoader` restores the chain and the input context stack after every answer, also when the hook raises;
#   * the `autoload` flag false: the hook is not called; the boot session: the Q3 error naming the predicate;
#   * `autoImport` precedes everything; the refreshed definition (a hook that makes the module link a super's definition); the helper
#     `_autoload_predicate_name` (pl-util.c predicateName);
#   * the A1 killer: a hook run THROUGH the VM from `call(user:foo)` and from a plain call leaves the caller's frame intact
#     (the autoloader's query frame must not overwrite an unprotected `lTop`, A1's `mcall_cont` frame set-up);
#   * A1c's killer (audit D-0400 item 2): the hook's query returns to the trapped call's frame (`saved_environment` is foo's frame).
# Every row builds the BOOTED database (`PL_global_data{T}()`, via `_RDB()`), as `_at_db` does; the guard that skipped an undefined hook
# is gone (A5, D-0398 (e)).
# Mutation-tested by tools/mutants/AUTOLOAD1.py.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "rules_common.jl"))

_at_user(x) = _rf(":", _rs(:user), _rs(x))
_at_proc(db::_RDB, name, arity::Int=0) = LK.lookupProcedure(_rs(name), arity, db.user)
_at_sysproc(db::_RDB, name, arity::Int) =
    LK.lookupProcedure(_rs(name), arity, LK.MODULE_system(db.gd))
_at_text(m::Tuple{Symbol, _R}) = String(lk_name(m[2]))
_at_texts(ld, from::Int) = String[_at_text(m) for m in ld.messages[(from + 1):end]]

"The BOOTED database whose `called/1` is dynamic (the hook's bodies record in it) and a foreign frame open."
function _at_db()::_RDB
    db = _RDB()
    LK.setDynamicDefinition!(_at_proc(db, :called, 1).definition, true)
    LK.PL_open_foreign_frame(db.ld)
    return db
end

"""
Add `exception(undefined_predicate, Pred, answer) :- body` to `user:exception/3`, the clause the real `'\$undefined_procedure'/4`
(boot/init.pl:959) asks first: `Pred` is `name/arity` for the module `user`, `mod:name/arity` for another one (`'\$prefix_module'`).
"""
function _at_hook!(
    db::_RDB, name, answer; arity::Int=0, body::Union{Nothing, _R}=nothing, mod=nothing
)
    ind = _rf("/", _rs(name), _rg(arity))
    pred = mod === nothing ? ind : _rf(":", _rs(mod), ind)
    return _radd!(db, _rf("exception", _rs(:undefined_predicate), pred, _rs(answer)), body)
end

"`assertz(user:called(name))`: the hook's record that it ran."
_at_record(name) = _rf("assertz", _at_user_goal(_rf("called", _rs(name))))
_at_user_goal(g::_R) = _rf(":", _rs(:user), g)

"What the hooks recorded in `called/1`, as write_canonical texts, in order."
_at_called(db::_RDB) = String[a for (a, _) in _rcall(db, _rf("called", _rv(1)))]

"A case: a database with one hook clause for `name`; `trapUndefined` on its undefined predicate; `(db, def, got, called)`."
function _at_run(name, answer; arity::Int=0, body::Union{Nothing, _R}=_at_record(name))
    db = _at_db()
    _at_hook!(db, name, answer; arity, body)
    def = _at_proc(db, name, arity).definition
    got = LK.trapUndefined(db.gd, db.ld, def)
    return db, def, got, _at_called(db)
end

@testset "A2: a fresh local data has an empty chain and no loop" begin
    gd = LK.setupProlog(_R)
    ld = LK.PL_local_data{_R}(gd)
    @test isempty(ld.autoload_nesting)
    @test ld.autoload_loop === nothing
end

@testset "a user:exception/3 clause as the hook: its arguments and its answers" begin
    # fail: returns the (still undefined) definition, no supervisor (pl-proc.c returns before `error:`)
    db, def, got, called = _at_run(:fa, :fail)
    @test got === def
    @test def.codes[1] == LK.S_VIRGIN
    @test called == ["called(fa)"]                               # the hook ran once, with (user, fa, 0)
    @test isempty(db.ld.autoload_nesting)
    # error: the error label, S_UNDEF
    db, def, got, called = _at_run(:er, :error)
    @test got === def
    @test def.codes[1] == LK.S_UNDEF
    @test called == ["called(er)"]
    # retry, the hook defines the predicate: round two finds it defined, no warning
    db, def, got, called = _at_run(
        :rd, :retry; body=_rconj(_rf("assertz", _at_user_goal(_rs(:rd))), _at_record(:rd))
    )
    @test got === def
    @test LK.isDefinedProcedure(db.gd, _at_proc(db, :rd))
    @test def.codes[1] != LK.S_UNDEF
    @test called == ["called(rd)"]                               # run ONCE: the second round ends in autoImport
    @test isempty(db.ld.messages)
    # retry, the hook does not define it: the FIRST retry goes round again, the SECOND warns and returns (retry_times++)
    db, def, got, called = _at_run(:rn, :retry)
    @test got === def
    @test called == ["called(rn)", "called(rn)"]                 # the hook ran twice
    @test _at_texts(db.ld, 0) == ["[Thread 1]: exception handler failed to define rn/0\n"]
    @test def.codes[1] == LK.S_VIRGIN                            # the warning branch returns before `error:`
    @test isempty(db.ld.autoload_nesting)
    # any other atom: the error label
    db, def, got, called = _at_run(:ot, :bar)
    @test got === def
    @test def.codes[1] == LK.S_UNDEF
    @test called == ["called(ot)"]
    # the arity is passed as an integer and the name as its atom: a hook of arity 2 for ar/2 answers; the hook for ar/0 would not
    db, def, got, called = _at_run(
        :ar, :retry; arity=2,
        body=_rconj(
            _rf("assertz", _at_user_goal(_rf("ar", _rs(:a), _rs(:b)))), _at_record(:ar)
        )
    )
    @test got === def
    @test called == ["called(ar)"]
    @test LK.isDefinedProcedure(db.gd, _at_proc(db, :ar, 2))
    # a name no clause matches: the real hook's own clauses answer (`$autoload` finds nothing: `error`), the error label
    db = _at_db()
    _at_hook!(db, :other, :fail)
    def = _at_proc(db, :unmatched).definition
    @test LK.trapUndefined(db.gd, db.ld, def) === def
    @test def.codes[1] == LK.S_UNDEF
    # a module the clause does not match: the same predicate name in the module `mm` (its Pred is `mm:inmm/0`, not `inmm/0`)
    mm = LK.lookupModule(db.gd, _rs(:mm))
    _at_hook!(db, :inmm, :fail)                                  # `inmm/0` of `user` only
    def = LK.lookupProcedure(_rs(:inmm), 0, mm).definition
    @test LK.trapUndefined(db.gd, db.ld, def) === def
    @test def.codes[1] == LK.S_UNDEF
    # ... and a clause for `mm:inmm2/0` does match it, in `mm` and not in `user`
    _at_hook!(db, :inmm2, :fail; mod=:mm)
    def = LK.lookupProcedure(_rs(:inmm2), 0, mm).definition
    @test LK.trapUndefined(db.gd, db.ld, def) === def
    @test def.codes[1] == LK.S_VIRGIN                            # `fail`: no supervisor
    def = _at_proc(db, :inmm2).definition
    @test LK.trapUndefined(db.gd, db.ld, def) === def
    @test def.codes[1] == LK.S_UNDEF
end

@testset "the hook makes the module link a super's definition: the refreshed definition is returned" begin
    # UNVERIFIED (never run): the hook defines `fi` in system and calls user:fi, whose trap links user's procedure to it; the
    # outer answer is `fail`, so the returned definition is the refresh `lookupDefinition(functor, module)`, not the stale argument.
    db = _at_db()
    _at_hook!(
        db,
        :fi,
        :fail;
        body=_rconj(_rf("assertz", _rf(":", _rs(:system), _rs(:fi))), _at_user(:fi))
    )
    def = _at_proc(db, :fi).definition
    got = LK.trapUndefined(db.gd, db.ld, def)
    sysdef = _at_sysproc(db, :fi, 0).definition
    @test got === sysdef
    @test got !== def
    @test _at_proc(db, :fi).definition === sysdef
end

@testset "test_autoload_loop and the loop report" begin
    db = _at_db()
    gd, ld = db.gd, db.ld
    mm = LK.lookupModule(gd, _rs(:mm))
    d1 = _at_proc(db, :lp).definition
    d2 = LK.lookupProcedure(_rs(:q), 1, mm).definition
    d3 = _at_proc(db, :other, 1).definition
    # not on the chain: true, `autoload_loop` untouched, no message
    @test LK.test_autoload_loop(gd, ld, d1)
    @test ld.autoload_loop === nothing
    @test isempty(ld.messages)
    # on the chain: false, set, reported innermost first up to the definition; the chain is [d1, d2] (d2 innermost)
    push!(ld.autoload_nesting, d1)
    push!(ld.autoload_nesting, d2)
    @test LK.test_autoload_loop(gd, ld, d3)
    @test ld.autoload_loop === nothing
    @test !LK.test_autoload_loop(gd, ld, d1)
    @test ld.autoload_loop === d1
    @test _at_texts(ld, 0) == [
        "ERROR: autoload loop:\n", "ERROR:   lp/0\n", "ERROR:   mm:q/1\n", "ERROR:   lp/0\n"
    ]
    # a hit on the innermost entry stops the walk there
    n0 = length(ld.messages)
    @test !LK.test_autoload_loop(gd, ld, d2)
    @test ld.autoload_loop === d2
    @test _at_texts(ld, n0) ==
        ["ERROR: autoload loop:\n", "ERROR:   mm:q/1\n", "ERROR:   mm:q/1\n"]
    # `autoload_loop` is never cleared by a later search that finds no loop (upstream clears it in resetProlog only)
    @test LK.test_autoload_loop(gd, ld, d3)
    @test ld.autoload_loop === d2
    empty!(ld.autoload_nesting)
    # trapUndefined: the definition is on the chain, so it returns at once and the hook is NOT called
    _at_hook!(db, :lp, :retry; body=_at_record(:lp))
    push!(ld.autoload_nesting, d1)
    n1 = length(ld.messages)
    @test LK.trapUndefined(gd, ld, d1) === d1
    @test d1.codes[1] == LK.S_VIRGIN                             # `return def`, no supervisor
    @test _at_called(db) == String[]
    @test _at_texts(ld, n1)[1] == "ERROR: autoload loop:\n"
    @test length(ld.autoload_nesting) == 1                       # the chain is the caller's: untouched
end

@testset "autoLoader restores the chain and the input context stack" begin
    for (name, answer) in ((:ra, :fail), (:rb, :error), (:rc, :retry), (:rd2, :nope))
        db = _at_db()
        _at_hook!(db, name, answer; body=_at_record(name))
        nctx = length(db.ld.input_context_stack)
        fli0 = db.ld.fli_context
        def = _at_proc(db, name).definition
        got = LK.autoLoader(db.gd, db.ld, def)
        @test db.ld.fli_context == fli0                       # the foreign frame is discarded
        @test got !== nothing && sym_key(got) == sym_key(_rs(answer))     # the hook's 4th argument, as an atom
        @test isempty(db.ld.autoload_nesting)
        @test length(db.ld.input_context_stack) == nctx
        @test _at_called(db) == ["called($name)"]
    end
    db = _at_db()
    # UNVERIFIED (never run, the sizing's risk 6): a hook that RAISES leaves the exception pending under PL_Q_PASS_EXCEPTION
    _at_hook!(db, :thr, :retry; body=_rf("throw", _rs(:boom)))
    nctx = length(db.ld.input_context_stack)
    def = _at_proc(db, :thr).definition
    got = LK.autoLoader(db.gd, db.ld, def)
    @test got === nothing
    @test isempty(db.ld.autoload_nesting)
    @test length(db.ld.input_context_stack) == nctx
    @test LK.PL_exception(db.ld, 0) != 0                         # PL_Q_PASS_EXCEPTION: the ball is left pending (UNVERIFIED)
    LK.PL_clear_exception(db.ld)
end

@testset "the autoload flag false: the hook is not called; the boot session: the Q3 error" begin
    db = _at_db()
    _at_hook!(db, :fl, :fail; body=_at_record(:fl))
    LK.clearPrologFlagMask!(db.ld, LK.PLFLAG_AUTOLOAD)
    def = _at_proc(db, :fl).definition
    @test LK.trapUndefined(db.gd, db.ld, def) === def
    @test def.codes[1] == LK.S_UNDEF
    @test _at_called(db) == String[]
    # the boot session: the Q3 error naming the predicate (the flag is on again; pl-proc.c:3027 skips the autoloader there)
    LK.setPrologFlagMask!(db.ld, LK.PLFLAG_AUTOLOAD)
    db.gd.bootsession = true
    def2 = _at_proc(db, :fl).definition
    err = try
        LK.trapUndefined(db.gd, db.ld, def2)
        nothing
    catch e
        e
    end
    @test err isa ErrorException
    @test occursin("fl/0", err.msg)
    db.gd.bootsession = false
    @test _at_called(db) == String[]
end

@testset "autoImport precedes the autoloader" begin
    db = _at_db()
    _at_hook!(db, :rational, :retry; arity=1, body=_at_record(:rational))
    sysdef = _at_sysproc(db, :rational, 1).definition
    def = _at_proc(db, :rational, 1).definition
    @test LK.trapUndefined(db.gd, db.ld, def) === sysdef
    @test _at_called(db) == String[]
end

@testset "the predicate's name in a message (pl-util.c predicateName)" begin
    db = _at_db()
    gd = db.gd
    mm = LK.lookupModule(gd, _rs(:mm))
    @test LK._autoload_predicate_name(gd, _at_proc(db, :foo, 0).definition) == "foo/0"
    @test LK._autoload_predicate_name(gd, LK.lookupProcedure(_rs(:q), 1, mm).definition) ==
        "mm:q/1"
    sysdef = _at_sysproc(db, :rational, 1).definition
    @test (sysdef.flags & LK.P_LOCKED) != 0
    @test LK._autoload_predicate_name(gd, sysdef) == "system:rational/1"     # locked, but not visible in user yet
    @test LK.autoImport(gd, _rs(:rational), 1, db.user) === sysdef
    @test LK._autoload_predicate_name(gd, sysdef) == "rational/1"            # isUserSystemPredicate: no prefix
end

@testset "A1's killer: a hook run through the VM leaves the caller's frame intact" begin
    # UNVERIFIED (never run). `call(user:foo)` goes through `mcall_cont`; the hook's query runs on the same local stack: if the
    # frame set-up there left `lTop` below the caller's frame, the hook would overwrite `Y` and `X`.
    db = _at_db()
    _at_hook!(
        db, :foo, :retry; body=_rconj(_rf("assertz", _at_user(:foo)), _at_record(:foo))
    )
    _radd!(
        db, _rf("t", _rv(1), _rv(2)),
        _rconj(
            _rf("=", _rv(2), _rg(1)), _rf("call", _at_user(:foo)), _rf("=", _rv(1), _rv(2))
        )
    )
    @test String[a for (a, _) in _rcall(db, _rf("t", _rv(3), _rv(4)))] == ["t(1,1)"]
    @test _at_called(db) == ["called(foo)"]
    # the same through a plain call of an undefined predicate in a clause body
    _at_hook!(
        db, :baz, :retry; body=_rconj(_rf("assertz", _at_user(:baz)), _at_record(:baz))
    )
    _radd!(
        db, _rf("u", _rv(1), _rv(2)),
        _rconj(_rf("=", _rv(2), _rg(2)), _rs(:baz), _rf("=", _rv(1), _rv(2)))
    )
    @test String[a for (a, _) in _rcall(db, _rf("u", _rv(3), _rv(4)))] == ["u(2,2)"]
    @test isempty(db.ld.autoload_nesting)
end

@testset "A1b's killer: mcall_cont gives the new frame its parent before the hook runs (NFR->parent = FR)" begin
    # src/pl-wam.jl mcall_cont: the restore after trapUndefined reads the NEW frame's parent (`FR = FR->parent`, pl-vmi.c:5722). The
    # frame records are pooled by index and a dropped record keeps its fields (pushFrame!), so a record's STALE parent is often the
    # right one by chance; this row makes it WRONG: every pooled record's parent is set to a position no frame has, as a record
    # left by an earlier call of another shape would hold one. With the parent written the call runs through; without it the
    # restore returns into frame 999999 (a BoundsError on `ld.frames`, no loop). White box, LK-ONLY.
    db = _at_db()
    _at_hook!(
        db, :foo, :retry; body=_rconj(_rf("assertz", _at_user(:foo)), _at_record(:foo))
    )
    _radd!(
        db, _rf("t", _rv(1)), _rconj(_rf("call", _at_user(:foo)), _rf("=", _rv(1), _rg(7)))
    )
    for fr in db.ld.frames
        fr.parent = 999_999
    end
    got = try
        String[a for (a, _) in _rcall(db, _rf("t", _rv(2)))]
    catch e
        "raised " * string(typeof(e))                      # the type only: a failing `==` shows both sides, and a BoundsError carries the frame pool
    end
    @test got == ["t(7)"]
    @test _at_called(db) == ["called(foo)"]
    @test isempty(db.ld.autoload_nesting)
end

@testset "A1c's killer: the autoloader's query returns to the trapped frame" begin
    # LK-ONLY (white-box): swipl cannot show the query's `saved_environment` before DBG1's `prolog_frame_attribute/3`. `call(user:foo)` goes
    # through `mcall_cont`; the hook's query is opened by `PL_open_query` with `saved_environment = ld.environment_frame`, which `mcall_cont`
    # sets to the new frame (`ld.environment_frame = FR`, src/pl-wam.jl:3830, mutant AUTOLOAD1-A1c): that frame is foo's. The real hook runs
    # the clause `exception(undefined_predicate, foo, retry)`, which records `prolog_current_frame/1` (the position of its own frame, the
    # caller of that call). The walk is `parentFrame` (src/pl-wam.jl:1360): exception/3's frame -> `$undefined_procedure/4`'s, the query's top
    # frame (parent 0) -> the query's `saved_environment`. The records are pooled and a dropped one stays readable until a push reuses it, and
    # reading `seen_frame/1` is a query that pushes: so the pool records and the hook's query record are COPIED inside the `at` callback
    # (no query there), and the position is read afterwards.
    db = _at_db()
    LK.setDynamicDefinition!(_at_proc(db, :seen_frame, 1).definition, true)
    _at_hook!(
        db,
        :foo,
        :retry;
        body=_rconj(
            _rf("assertz", _at_user(:foo)),
            _rf("prolog_current_frame", _rv(1)),
            _rf("assertz", _at_user_goal(_rf("seen_frame", _rv(1)))),
            _rs(:true)                            # not the last call: exception/3's frame stays (no LCO into assertz/1)
        )
    )
    _radd!(
        db, _rf("t", _rv(1)), _rconj(_rf("call", _at_user(:foo)), _rf("=", _rv(1), _rg(1)))
    )
    foodef = _at_proc(db, :foo).definition
    excdef = _at_proc(db, :exception, 3).definition
    hookdef = _at_sysproc(db, "\$undefined_procedure", 4).definition
    seen = NamedTuple[]
    at = function (qid, k)
        ld = db.ld
        q = ld.queries[ld.nqueries + 1]          # the hook's query: the one opened inside the outer query
        push!(
            seen,
            (;
                flags=q.flags,
                qbase=q.base,
                saved=q.saved_environment,
                nframes=ld.nframes,
                frames=[
                    (; idx=i, base=f.base, parent=f.parent, pred=f.predicate) for
                    (i, f) in
                    enumerate(ld.frames[1:min(length(ld.frames), ld.nframes + 16)])
                ]
            )
        )
    end
    @test String[a for (a, _) in _rcall(db, _rf("t", _rv(2)); at)] == ["t(1)"]
    @test length(seen) == 1
    s = only(seen)
    # not vacuous: the record is the hook's query (its flags), it has a parent frame, and the hook ran once
    @test (s.flags & LK.PL_Q_PASS_EXCEPTION) != 0
    @test (s.flags & LK.PL_Q_NODEBUG) != 0
    @test s.saved != 0
    got = String[a for (a, _) in _rcall(db, _rf("seen_frame", _rv(1)))]
    @test length(got) == 1                         # one recorded frame: the hook ran once, through the VM
    F = parse(Int, got[1][(length("seen_frame(") + 1):(end - 1)])
    # exception/3's frame: the record at position F whose predicate is exception/3
    cand = [f for f in s.frames if f.base == F && f.pred === excdef]
    @test length(cand) == 1
    exc = only(cand)
    # its parent is the hook's own frame, whose parent is the query's top frame (`$c_call_prolog/0`, parent 0, its position
    # `QF_TOP_FRAME` above the query's base: the frame `parentFrame` takes the query's `saved_environment` for)
    hk = s.frames[exc.parent]
    @test hk.pred === hookdef
    top = s.frames[hk.parent]
    @test top.parent == 0
    @test top.base - LK.QF_TOP_FRAME == s.qbase
    @test String(lk_name(top.pred.name)) == "\$c_call_prolog"
    # the query returns to the frame of the trapped call (a dropped record, readable until a push reuses it): foo
    @test s.frames[s.saved].pred === foodef
end
