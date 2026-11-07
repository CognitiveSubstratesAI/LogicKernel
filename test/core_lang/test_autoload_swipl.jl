# ORIGINAL: AUTOLOAD1 A5 part 1 (audit D-0398, D-0416 item 2): the swipl-COMPARED rows of the autoloader hook on the booted database
# (pl-proc.c `autoLoader` :2962 and `trapUndefined` :3008-3063 at swipl-devel cbf4e189; boot/init.pl `'$undefined_procedure'/4` :949-969).
# test/core_lang/test_autoload_swipl.jl — a PROGRAM of `user:exception/3` clauses (init.pl:959-963: `exception(undefined_predicate, Pred, Action)`,
# `Pred` = `Name/Arity` in `user`, `Module:Name/Arity` elsewhere), consulted by the kernel's loader and by swipl, and goal predicates `gNN(R)`
# that run an undefined predicate and answer how it ended. The Action is `fail`, `error`, any other atom, `retry` with a clause that defines the
# predicate (retry once) and `retry` without (retry twice: the warning "exception handler failed to define"), in `user`, in another module, with
# arguments, through `call/1` and as a plain body goal, with the `autoload` flag false, with no clause for the name (the hook's own clauses:
# `$autoload` finds nothing), and with the module's `unknown` flag `fail`.
#   * The answers are swipl 10.1.19's, PINNED (evidence/AUTOLOAD1/gen_autoload_rows.py in the channel repo: it builds the program and the goals
#     from THIS file, runs swipl twice under `timeout -s KILL 20` and requires byte-identical output); the kernel's lines are compared with the pins.
#   * The retry warning is a line `msg([...])`: swipl's `user:message_hook/3` sees `message_lines(["..."])` (kind `error`, pl-init.c `vwarning`);
#     the kernel prints the text through `_qlf_Sdprintf!` into `ld.messages` (DIVERGES, owner AUTOLOAD1 A5 part 2: `vwarning` through
#     print_message/2), and the row converts each text to the same line. The line comes BEFORE its goal's answer, on both sides.
#   * Both sides run with `debug_on_error` false (swipl-side program text only): the retry warning is an `error` message, and with the flag on
#     swipl starts the tracer, which reads its answer from the terminal.
# Mutation-tested by tools/mutants/AUTOLOAD1.py (A3b-A3r: the swipl-compared kill rows next to test_autoload_trap.jl's white-box ones).
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — the autoloader (src/pl-proc.jl), built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "rules_common.jl"))

# the program, as it stands in the file both systems consult
const _AS_PROGRAM = raw"""
exception(undefined_predicate, as_fail/0, fail).
exception(undefined_predicate, as_error/0, error).
exception(undefined_predicate, as_other/0, nonsense).
exception(undefined_predicate, as_number/0, 42).
exception(undefined_predicate, as_retry/0, retry) :- assertz(user:as_retry).
exception(undefined_predicate, as_twice/0, retry).
exception(undefined_predicate, as_args/2, retry) :- assertz(user:as_args(a, b)).
exception(undefined_predicate, asmod:as_mod/0, retry) :- assertz(asmod:as_mod).
exception(undefined_predicate, as_flag/0, retry) :- assertz(user:as_flag).
exception(undefined_predicate, as_plain/0, retry) :- assertz(user:as_plain).
exception(undefined_predicate, as_plainfail/0, fail).
exception(undefined_predicate, as_ctx/0, retry) :- assertz(user:as_ctx).

as_res(G, R) :- catch(( call(G) -> R = yes ; R = no ), error(E, _), R = caught(E)).

g01(R) :- as_res(as_fail, R).
g02(R) :- as_res(as_error, R).
g03(R) :- as_res(as_other, R).
g04(R) :- as_res(as_number, R).
g05(R) :- as_res(as_retry, R).
g06(R) :- as_res(as_retry, R).
g07(R) :- as_res(as_twice, R).
g08(R) :- as_res(as_args(X, Y), R0), R = res(R0, X, Y).
g09(R) :- as_res(asmod:as_mod, R).
g10(R) :- as_res(as_nosuch_name, R).
g11(R) :- as_res(asmod:as_nosuch_mod, R).
g12(R) :- set_prolog_flag(autoload, false), as_res(as_flag, R0), set_prolog_flag(autoload, true),
          ( current_predicate(as_flag/0) -> R = res(R0, defined) ; R = res(R0, undefined) ).
g13(R) :- as_res(as_flag, R).
g14(R) :- catch(( as_plain, R = yes ), error(E, _), R = caught(E)).
g15(R) :- catch(( as_plainfail, R = yes ), error(E, _), R = caught(E)).
g16(R) :- set_prolog_flag(asmod:unknown, fail), as_res(asmod:as_unknown_mod, R),
          set_prolog_flag(asmod:unknown, error).
g17(R) :- as_res(as_twice, R).
g18(R) :- catch(( as_ctx, as_ctx, R = yes ), error(E, _), R = caught(E)).
"""
# the goals, in order: the answers of each, then `end`
const _AS_GOALS = ["g01", "g02", "g03", "g04", "g05", "g06", "g07", "g08", "g09", "g10",
    "g11", "g12", "g13", "g14", "g15", "g16", "g17", "g18"]
# swipl's side only: the hook that prints the retry warning's `message_lines`, and no tracer on an error message
const _AS_SWIPL_ONLY = raw"""
:- set_prolog_flag(debug_on_error, false).
:- multifile user:message_hook/3.
user:message_hook(message_lines(Ls), error, _) :- write_canonical(msg(Ls)), nl, fail.
"""

# the answers swipl 10.1.19 gives, one line per answer, `end` after each goal (filled by evidence/AUTOLOAD1/gen_autoload_rows.py)
const _AS_PINNED = [
    # PINS-BEGIN
    "g01(caught(existence_error(procedure,/(as_fail,0)))) det",
    "end",
    "g02(caught(existence_error(procedure,/(as_error,0)))) det",
    "end",
    "g03(caught(existence_error(procedure,/(as_other,0)))) det",
    "end",
    "g04(caught(existence_error(procedure,/(as_number,0)))) det",
    "end",
    "g05(yes) det",
    "end",
    "g06(yes) det",
    "end",
    "msg([\"[Thread 1]: exception handler failed to define as_twice/0\"])",
    "msg([\"[Thread 1]: exception handler failed to define as_twice/0\"])",
    "g07(caught(existence_error(procedure,/(as_twice,0)))) det",
    "end",
    "g08(res(yes,a,b)) det",
    "end",
    "g09(yes) det",
    "end",
    "g10(caught(existence_error(procedure,/(as_nosuch_name,0)))) det",
    "end",
    "g11(caught(existence_error(procedure,:(asmod,/(as_nosuch_mod,0))))) det",
    "end",
    "g12(res(caught(existence_error(procedure,/(as_flag,0))),undefined)) det",
    "end",
    "g13(yes) det",
    "end",
    "g14(yes) det",
    "end",
    "g15(caught(existence_error(procedure,/(as_plainfail,0)))) det",
    "end",
    "g16(no) det",
    "end",
    "msg([\"[Thread 1]: exception handler failed to define as_twice/0\"])",
    "g17(caught(existence_error(procedure,/(as_twice,0)))) det",
    "end",
    "g18(yes) det",
    "end"
    # PINS-END
]

"The kernel's lines: the retry warnings of each goal (as swipl's hook prints them), then its answers, then `end`."
function _as_kernel_lines(db::_RDB, goals::Vector{String})::Vector{String}
    out = String[]
    for g in goals
        n0 = length(db.ld.messages)
        answers = _rcall(db, _rf(g, _rv(1)))
        for (_, text) in db.ld.messages[(n0 + 1):end]
            ls = split(chomp(String(lk_name(text))), '\n')
            push!(out, "msg([" * join(("\"" * l * "\"" for l in ls), ",") * "])")
        end
        for (a, det) in answers
            push!(out, a * (det ? " det" : " nondet"))
        end
        push!(out, "end")
    end
    return out
end

"A booted database that has consulted `_AS_PROGRAM` (the loader's own status must be `:ok`)."
function _as_db()::_RDB
    db = _RDB()
    path = joinpath(mktempdir(), "autoload_swipl.pl")
    write(path, _AS_PROGRAM)
    st, ball = LK.load_file!(db.gd, db.ld, path)
    st === :ok || error("consulting the program failed: $st")
    return db
end

@testset "the autoloader hook through user:exception/3, as swipl 10.1.19" begin
    db = _as_db()
    lines = _as_kernel_lines(db, _AS_GOALS)
    @test length(lines) == length(_AS_PINNED)
    for (k, p) in zip(lines, _AS_PINNED)
        k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
        @test k == p
    end
    # not vacuous: the pins hold every kind of answer, through the one extractor: a defined predicate, an existence error, a failure of
    # the call, the retry warning, and as many `end` lines as goals
    @test count(==("end"), _AS_PINNED) == length(_AS_GOALS)
    @test count(l -> occursin("caught(existence_error(procedure,", l), _AS_PINNED) >= 8
    @test count(l -> occursin("(yes", l) || occursin(",yes", l), _AS_PINNED) >= 3
    @test count(
        l -> startswith(l, "msg([\"[Thread 1]: exception handler failed to define "),
        _AS_PINNED
    ) >= 1
    # the kernel side is not vacuous either: the program's twelve clauses are in `user:exception/3`
    ex = LK.lookupProcedure(_rs(:exception), 3, db.user)
    @test ex.definition.impl_clauses.number_of_clauses == 12
end
