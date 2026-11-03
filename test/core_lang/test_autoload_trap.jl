# ORIGINAL: AUTOLOAD1 A2/A3 white-box rows (audit D-0387 item 3, D-0398): the autoloader branch of `trapUndefined` (pl-proc.c:3008-3063 at
# swipl-devel cbf4e189: `test_autoload_loop` :2932, `autoLoader` :2962, the retry loop) and the two LD fields `autoload.nesting`,
# `autoload.loop` (pl-global.h:897-899). LK-only: the swipl-compared rows need the Prolog half (`system:'$undefined_procedure'/4`,
# boot/init.pl:949), which the kernel does not load before the first boot, so the expected values below are HAND-WRITTEN from the
# upstream C and checked against the kernel only; they ride with AUTOLOAD1 A5, where the swipl-compared rows run with the real hook
# and the rows that define a test hook here are retired in the same commit (refusal-flip rule D-0375/D-0376).
# test/core_lang/test_autoload_trap.jl — on every term type:
#   * A2: a fresh local data has an empty `autoload_nesting` and `autoload_loop === nothing` (no reset code: upstream's `resetProlog`
#     belongs to the toplevel step);
#   * THE GUARD (DIVERGES "the Prolog half is not loaded", a skip, no stand-in): without a defined `system:'$undefined_procedure'/4` the
#     answer is nil at once, the hook is NOT created, the supervisor is S_UNDEF, no message, the nesting stays empty — the rows every
#     other test file holds (test_module_path.jl "autoImport and trapUndefined") are its proof too;
#   * a TEST-DEFINED hook (clauses compiled into `system`): its three first arguments (module, name, arity) reach the head, the answers
#     `fail` (returns, no supervisor), `error` (S_UNDEF), `retry` (the hook defines the predicate: returned DEFINED; the hook does not:
#     the second round warns once and returns), any other atom (the error label), the retry's post-increment (the hook runs twice);
#   * `test_autoload_loop`: a definition on the chain is a loop (false, `autoload_loop` set and never cleared, the report lines, innermost
#     first, up to the definition), one that is not on it is not; `trapUndefined` returns at once and never calls the hook;
#   * `autoLoader` restores the chain and the input context stack after every answer, also when the hook raises;
#   * the `autoload` flag false and the boot session: the hook is not called (the Q3 error in the boot session);
#   * `autoImport` precedes everything; the refreshed definition (a hook that makes the module link a super's definition); the helper
#     `_autoload_predicate_name` (pl-util.c predicateName);
#   * the A1 killer: a hook run THROUGH the VM from `call(user:foo)` and from a plain call leaves the caller's frame intact
#     (the autoloader's query frame must not overwrite an unprotected `lTop`, A1's `mcall_cont` frame set-up).
# Mutation-tested by tools/mutants/AUTOLOAD1.py.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "rules_common.jl"))

const _AT_HOOK = "\$undefined_procedure"
_at_user(x) = _rf(":", _rs(:user), _rs(x))
_at_proc(db::_RDB, name, arity::Int=0) = LK.lookupProcedure(_rs(name), arity, db.user)
_at_sysproc(db::_RDB, name, arity::Int) = LK.lookupProcedure(_rs(name), arity, LK.MODULE_system(db.gd))
_at_hookproc(db::_RDB) = LK.isCurrentProcedure(sym_key(_rs(_AT_HOOK)), 4, LK.MODULE_system(db.gd))
_at_text(m::Tuple{Symbol, _R}) = String(lk_name(m[2]))
_at_texts(ld, from::Int) = String[_at_text(m) for m in ld.messages[(from + 1):end]]

"A database whose `called/1` is dynamic (the hook's bodies record in it) and a foreign frame open."
function _at_db()::_RDB
    db = _RDB()
    LK.setDynamicDefinition!(_at_proc(db, :called, 1).definition, true)
    LK.PL_open_foreign_frame(db.ld)
    return db
end

"""
Add `'\$undefined_procedure'(user, name, arity, answer) :- body` to the module `system`, the clause the Prolog half's hook
(boot/init.pl:949) would be, with the module, the name and the arity the autoloader passes.
"""
function _at_hook!(db::_RDB, name, answer; arity::Int=0, body::Union{Nothing, _R}=nothing)
    head = _rf(_AT_HOOK, _rs(:user), _rs(name), _rg(arity), _rs(answer))
    sys = LK.MODULE_system(db.gd)
    pr = LK.lookupProcedure(_rs(_AT_HOOK), 4, sys)
    cl = LK.compileClause(db.gd, db.ld, head, body, pr, sys)
    LK.assertDefinition!(db.gd, pr.definition, cl, LK.CL_END)
    return cl
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
    gd = LK.PL_global_data{_R}()
    ld = LK.PL_local_data{_R}(gd)
    @test isempty(ld.autoload_nesting)
    @test ld.autoload_loop === nothing
end

@testset "the guard: no defined hook, the answer is nil at once" begin
    db = _RDB()
    ld = db.ld
    @test LK.truePrologFlag(ld, LK.PLFLAG_AUTOLOAD)              # the default: autoload is on
    @test _at_hookproc(db) === nothing
    def = _at_proc(db, :nohook).definition
    n0 = length(ld.messages)
    nctx = length(ld.input_context_stack)
    @test LK.trapUndefined(db.gd, ld, def) === def
    @test def.codes[1] == LK.S_UNDEF                             # createUndefSupervisor
    @test length(ld.messages) == n0
    @test isempty(ld.autoload_nesting)
    @test length(ld.input_context_stack) == nctx
    @test _at_hookproc(db) === nothing                           # looked up, NOT created (upstream's PL_pred creates it)
    # a hook procedure that exists but has no clause is not defined either
    _at_sysproc(db, _AT_HOOK, 4)
    def2 = _at_proc(db, :nohook2).definition
    @test LK.trapUndefined(db.gd, ld, def2) === def2
    @test def2.codes[1] == LK.S_UNDEF
    @test isempty(ld.autoload_nesting)
end

@testset "a test-defined hook: its arguments and its answers" begin
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
    db, def, got, called = _at_run(:rd, :retry; body = _rconj(_rf("assertz", _at_user_goal(_rs(:rd))), _at_record(:rd)))
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
        :ar, :retry; arity = 2,
        body = _rconj(_rf("assertz", _at_user_goal(_rf("ar", _rs(:a), _rs(:b)))), _at_record(:ar)),
    )
    @test got === def
    @test called == ["called(ar)"]
    @test LK.isDefinedProcedure(db.gd, _at_proc(db, :ar, 2))
    # a name the hook does not match: no solution, the answer is nil, the error label (the three put_* feed the head)
    db = _at_db()
    _at_hook!(db, :other, :fail)
    def = _at_proc(db, :unmatched).definition
    @test LK.trapUndefined(db.gd, db.ld, def) === def
    @test def.codes[1] == LK.S_UNDEF
    # a module the hook does not match: the same predicate name in the module `mm`
    mm = LK.lookupModule(db.gd, _rs(:mm))
    _at_hook!(db, :inmm, :fail)                                  # (user, inmm, 0, fail) only
    def = LK.lookupProcedure(_rs(:inmm), 0, mm).definition
    @test LK.trapUndefined(db.gd, db.ld, def) === def
    @test def.codes[1] == LK.S_UNDEF
end

@testset "the hook makes the module link a super's definition: the refreshed definition is returned" begin
    # UNVERIFIED (never run): the hook defines `fi` in system and calls user:fi, whose trap links user's procedure to it; the
    # outer answer is `fail`, so the returned definition is the refresh `lookupDefinition(functor, module)`, not the stale argument.
    db = _at_db()
    _at_hook!(db, :fi, :fail; body = _rconj(_rf("assertz", _rf(":", _rs(:system), _rs(:fi))), _at_user(:fi)))
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
    @test _at_texts(ld, 0) == ["ERROR: autoload loop:\n", "ERROR:   lp/0\n", "ERROR:   mm:q/1\n", "ERROR:   lp/0\n"]
    # a hit on the innermost entry stops the walk there
    n0 = length(ld.messages)
    @test !LK.test_autoload_loop(gd, ld, d2)
    @test ld.autoload_loop === d2
    @test _at_texts(ld, n0) == ["ERROR: autoload loop:\n", "ERROR:   mm:q/1\n", "ERROR:   mm:q/1\n"]
    # `autoload_loop` is never cleared by a later search that finds no loop (upstream clears it in resetProlog only)
    @test LK.test_autoload_loop(gd, ld, d3)
    @test ld.autoload_loop === d2
    empty!(ld.autoload_nesting)
    # trapUndefined: the definition is on the chain, so it returns at once and the hook is NOT called
    _at_hook!(db, :lp, :retry; body = _at_record(:lp))
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
        _at_hook!(db, name, answer; body = _at_record(name))
        nctx = length(db.ld.input_context_stack)
        def = _at_proc(db, name).definition
        got = LK.autoLoader(db.gd, db.ld, def)
        @test got !== nothing && sym_key(got) == sym_key(_rs(answer))     # the hook's 4th argument, as an atom
        @test isempty(db.ld.autoload_nesting)
        @test length(db.ld.input_context_stack) == nctx
        @test _at_called(db) == ["called($name)"]
    end
    db = _at_db()
    # UNVERIFIED (never run, the sizing's risk 6): a hook that RAISES leaves the exception pending under PL_Q_PASS_EXCEPTION
    _at_hook!(db, :thr, :retry; body = _rf("throw", _rs(:boom)))
    nctx = length(db.ld.input_context_stack)
    def = _at_proc(db, :thr).definition
    got = LK.autoLoader(db.gd, db.ld, def)
    @test got === nothing
    @test isempty(db.ld.autoload_nesting)
    @test length(db.ld.input_context_stack) == nctx
    LK.PL_clear_exception(db.ld)
end

@testset "the autoload flag false and the boot session: the hook is not called" begin
    db = _at_db()
    _at_hook!(db, :fl, :fail; body = _at_record(:fl))
    LK.clearPrologFlagMask!(db.ld, LK.PLFLAG_AUTOLOAD)
    def = _at_proc(db, :fl).definition
    @test LK.trapUndefined(db.gd, db.ld, def) === def
    @test def.codes[1] == LK.S_UNDEF
    @test _at_called(db) == String[]
    # the boot session: the Q3 error naming the predicate, the hook not called (the flag is on again)
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
    _at_hook!(db, :rational, :retry; arity = 1, body = _at_record(:rational))
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
    @test LK._autoload_predicate_name(gd, LK.lookupProcedure(_rs(:q), 1, mm).definition) == "mm:q/1"
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
    _at_hook!(db, :foo, :retry; body = _rconj(_rf("assertz", _at_user(:foo)), _at_record(:foo)))
    _radd!(
        db, _rf("t", _rv(1), _rv(2)),
        _rconj(_rf("=", _rv(2), _rg(1)), _rf("call", _at_user(:foo)), _rf("=", _rv(1), _rv(2))),
    )
    @test String[a for (a, _) in _rcall(db, _rf("t", _rv(3), _rv(4)))] == ["t(1,1)"]
    @test _at_called(db) == ["called(foo)"]
    # the same through a plain call of an undefined predicate in a clause body
    _at_hook!(db, :baz, :retry; body = _rconj(_rf("assertz", _at_user(:baz)), _at_record(:baz)))
    _radd!(
        db, _rf("u", _rv(1), _rv(2)),
        _rconj(_rf("=", _rv(2), _rg(2)), _rs(:baz), _rf("=", _rv(1), _rv(2))),
    )
    @test String[a for (a, _) in _rcall(db, _rf("u", _rv(3), _rv(4)))] == ["u(2,2)"]
    @test isempty(db.ld.autoload_nesting)
end
