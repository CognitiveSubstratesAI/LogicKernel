# ORIGINAL: the UPSTREAM tests/tabling/test_mono_subsumptive.pl (swipl-devel 18168e62, 10.1.20), units mono_subsumptive, mono_abstract of 2 (15 of 15 tests), as
# kernel rows (TAB1, TABTEST-MS). One row `t_ms<NN>(R)` per upstream test: `abolish_all_tables, <goal>, abolish_all_tables`, R = ok / failed /
# raised(E). Monotonic tabling through subsumptive and abstract tables (`subsumptive`, `subgoal_abstract(0)`, `lazy`, transaction/snapshot).
#   * Comments matching the D-0164 terms are elided from the embedded text; no code differs (none matched in this file).
#   * Each unit is its own module (`pu_ms1`, `pu_ms2`): the text between `begin_tests` and `end_tests` verbatim, preceded by the use_module
#     lines of the file's libraries (lists, apply, aggregate; debug for assertion/1, which plunit provides; no library(tables), the file has none) and `:- discontiguous test/1, test/2.`
#     The file has no meta_predicate block and no helper section (`_TT_TAIL` is empty): each unit text is self-contained. Each unit loads with
#     `catch(use_module(..), _, true)`, so a unit the kernel refuses leaves only ITS rows undefined (the pin loads both, status ok).
#   * DIVERGES from the file: plunit is not used (a row calls the unit's test/2 clause directly). The options are folded by hand: `cleanup(init)`
#     is the cleanup goal of a setup_call_cleanup (init/0 of the unit); `Var == Val` options (unit 2: many_consumers, index_shapes,
#     one_shared_table, recursive, new_answer) are called after the body (the variables are shared with the clause); new_answer's cleanup
#     `(init, prolog_unlisten(b/1, on_answer))` runs as `pu_ms2:(..)` (module context as plunit gives it). The unit options of mono_abstract,
#     setup(abstract_subgoals) and cleanup(restore_subgoal_action), wrap EVERY row of unit 2 (plunit runs them once around the unit's tests):
#     they set max_table_subgoal_size_action to `abstract` and restore it (nb_setval/nb_getval inside the unit).
#   * Expected refusals on the kernel (by reading, unverified): `table .. as (subsumptive, monotonic)`, `:- dynamic .. as monotonic`,
#     subgoal_abstract(0), the flag max_table_subgoal_size_action, `lazy`, current_table/2 (a_tables/1), prolog_listen/2 and prolog_unlisten/2
#     with the channel b/1 (new_answer). The kernel's own partial port
#     (test_tabling_mono_subsumptive_swipl.jl, its own programs) is a different file, untouched. Every row stays pinned on swipl.
#   * Every pinned line is swipl's (swipl 10.1.20, two identical runs, evidence/TAB1/tabgap_tools/pins_ms.txt, which also holds the plunit
#     run: 15 of 15 tests passed, none failed or hung on the pin) AND equals the answer plunit expects (`_TT_UPSTREAM`: each test passes, so `ok`).
#   * UNVERIFIED on the kernel (nothing was compiled when these rows were written): every kernel answer; the gate decides.

using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — these built-ins ride the term layer through the FLI (unify, get, strip module)
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TT = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_tts(x) = lk_sym(_TT, Symbol(x))

_tt_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _tt_enc(t::_TT, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _tt_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _tt_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _tt_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_tt_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

const _TT_DRIVER = raw"""
enc(T) :- enc(T, [], _).
enc(V, S0, S) :- var(V), !, ( vidx(S0, V, 0, I) -> S = S0 ; length(S0, I), append(S0, [V], S) ), format("V~w", [I]).
enc(T, S, S) :- T == [], !, write(nil).
enc(T, S, S) :- atom(T), !, atom_codes(T, Cs), format("a~w", [Cs]).
enc(T, S, S) :- string(T), !, string_codes(T, Cs), format("s~w", [Cs]).
enc(T, S, S) :- integer(T), !, format("i~w", [T]).
enc(T, S, S) :- rational(T, N, D), !, format("q~wr~w", [N, D]).
enc(T, S, S) :- float(T), !, format("f~w", [T]).
enc(T, S0, S) :- compound_name_arity(T, N, A),
    ( N == [] -> write('c[]') ; atom_codes(N, Cs), format("c~w", [Cs]) ),
    format("/~w(", [A]), encargs(1, A, T, S0, S), write(')').
encargs(I, A, _, S, S) :- I > A, !.
encargs(I, A, T, S0, S) :- arg(I, T, X), enc(X, S0, S1), ( I < A -> write(',') ; true ),
    I1 is I+1, encargs(I1, A, T, S1, S).
vidx([X|_], V, I, I) :- X == V, !.
vidx([_|Xs], V, I0, I) :- I1 is I0+1, vidx(Xs, V, I1, I).
fz_pred(N) :-
    format("~w", [N]), functor(G, N, 1),
    catch(findnsols(50, G, G, Gs), _, Gs = [exception]),
    forall(member(S, Gs), ( S == exception -> write(' exception') ; write(' '), enc(S) )), nl.
fz_run(File, Ns) :-
    catch(( consult(File), S = ok ), E, S = exc(E)),
    ( S == ok -> writeln(ok) ; S = exc(B), write('exc '), enc(B), nl ),
    forall(member(N, Ns), fz_pred(N)).
"""

"The units' text, verbatim between begin_tests and end_tests: `(short name, begin_tests directive, text)`."
const _TT_UNITS = [
    ("ms1", "begin_tests(mono_subsumptive)", raw"""
:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(debug)).
:- use_module(library(aggregate)).
:- discontiguous test/1, test/2.
:- dynamic d/1 as monotonic.
:- table p/1 as (subsumptive, monotonic).
:- table q/1 as monotonic.

p(X) :- d(X).
q(X) :- p(X).                           % q(a) calls the subsumed p(a)

init :-
    abolish_all_tables,
    retractall(d(_)).

test(subsumed_empty_then_added, [cleanup(init)]) :-
    init,
    forall(p(_), true),                 % create the general table
    \+ q(a),
    assertz(d(a)),
    assertion(q(a)),
    assertion(\+ q(b)).
test(subsumed_warm, [cleanup(init)]) :-
    init,
    assertz(d(a)),
    forall(p(_), true),
    assertion(q(a)),
    assertz(d(b)),
    assertion(q(b)).
test(existing_variant, [cleanup(init)]) :-
    init,
    \+ p(a),                            % p(a) gets its own variant table
    \+ q(a),                            % and q(a) reuses it
    assertz(d(a)),
    assertion(q(a)).
test(retract_reassert, [cleanup(init)]) :-
    init,
    forall(p(_), true),
    assertz(d(a)),
    assertion(q(a)),
    retract(d(a)),
    assertion(\+ q(a)),
    assertz(d(a)),
    assertion(q(a)).
"""),
    ("ms2", "begin_tests(mono_abstract)", raw"""
:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(debug)).
:- use_module(library(aggregate)).
:- discontiguous test/1, test/2.
:- dynamic e/1 as monotonic.
:- dynamic edge/2 as monotonic.
:- dynamic e2/2 as monotonic.

:- table a/1 as (subgoal_abstract(0), monotonic).
:- table b/1 as monotonic.
:- table v/1 as (subgoal_abstract(0), monotonic).
:- table w/1 as monotonic.
:- table reach/1 as (subgoal_abstract(0), monotonic).
:- table from/2 as monotonic.
:- table la/1 as (subgoal_abstract(0), monotonic, lazy).
:- table lb/1 as (monotonic, lazy).
:- table pairs/1 as (subgoal_abstract(0), monotonic).
:- table same/1 as monotonic.
:- table firsts/1 as monotonic.

a(args(X)) :- e(X).                     % a(args(c)) is abstracted to a(_)
b(X) :- a(args(X)).
v(X) :- e(X).                           % v(c) is not abstracted
w(X) :- v(X).
reach(t(X,Y)) :- edge(X,Y).
reach(t(X,Z)) :- reach(t(X,Y)), edge(Y,Z).
from(X, Y) :- reach(t(X,Y)).
la(args(X)) :- e(X).
lb(X) :- la(args(X)).
pairs(args(X, Y)) :- e2(X, Y).
same(X) :- pairs(args(X, X)).          % a non-linear skeleton
firsts(X) :- pairs(args(X, _)).

abstract_subgoals :-
    current_prolog_flag(max_table_subgoal_size_action, Action),
    nb_setval(mono_subgoal_action, Action),
    set_prolog_flag(max_table_subgoal_size_action, abstract).

restore_subgoal_action :-
    nb_getval(mono_subgoal_action, Action),
    set_prolog_flag(max_table_subgoal_size_action, Action).

init :-
    abolish_all_tables,
    retractall(e(_)),
    retractall(edge(_,_)),
    retractall(e2(_,_)).

answers(Goal, Template, List) :-
    findall(Template, Goal, List0),
    msort(List0, List).

a_tables(Count) :-
    aggregate_all(count, current_table(a(_), _), Count).

test(empty_then_added, [cleanup(init)]) :-
    init,
    \+ b(c),
    assertz(e(c)),
    assertion(b(c)),
    assertion(\+ b(d)),
    assertz(e(d)),
    assertion(b(d)).
test(many_consumers, [Gained == Keys, cleanup(init)]) :-
    init,
    numlist(1, 20, Keys),
    forall(member(K, Keys), \+ b(K)),   % 20 dependencies on one a(_)
    forall(member(K, Keys), assertz(e(K))),
    findall(K, (member(K, Keys), b(K)), Gained).
test(index_shapes, [S1-F1-S2-F2 == []-[a]-[c]-[a,c], cleanup(init)]) :-
    init,
    \+ same(_),
    \+ firsts(_),
    assertz(e2(a, b)),                  % matches firsts' skeleton only
    answers(same(X), X, S1),
    answers(firsts(X), X, F1),
    assertz(e2(c, c)),                  % matches both
    answers(same(X), X, S2),
    answers(firsts(X), X, F2).
test(one_shared_table, [Count == 1, cleanup(init)]) :-
    init,
    \+ b(c),
    \+ b(d),
    assertz(e(c)),
    assertion(b(c)),
    a_tables(Count).
test(warm, [cleanup(init)]) :-
    init,
    assertz(e(c)),
    assertion(b(c)),
    assertz(e(d)),
    assertion(b(d)).
test(not_abstracted, [cleanup(init)]) :-
    init,
    \+ w(c),
    assertz(e(c)),
    assertion(w(c)).
test(recursive, [L1-L2-L3 == [b]-[b,c]-[a,b,c], cleanup(init)]) :-
    init,
    assertz(edge(a,b)),
    answers(from(a,Y), Y, L1),
    assertz(edge(b,c)),
    answers(from(a,Y), Y, L2),
    assertz(edge(c,a)),
    answers(from(a,Y), Y, L3).
test(new_answer, [Events == [c], cleanup((init, prolog_unlisten(b/1, on_answer)))]) :-
    init,
    nb_setval(mono_events, []),
    prolog_listen(b/1, on_answer),
    \+ b(c),
    assertz(e(c)),
    nb_getval(mono_events, Events).
test(retract_reassert, [cleanup(init)]) :-
    init,
    assertz(e(c)),
    assertion(b(c)),
    retract(e(c)),
    assertion(\+ b(c)),
    assertz(e(c)),
    assertion(b(c)).
test(rollback, [cleanup(init)]) :-
    init,
    assertz(e(c)),
    assertion(b(c)),
    \+ b(d),                            % b(d) and b(f) exist before the
    \+ b(f),                            % transaction and the snapshot
    \+ transaction((assertz(e(d)), assertion(b(d)), fail)),
    assertion(\+ b(d)),
    snapshot((assertz(e(f)), assertion(b(f)))),
    assertion(\+ b(f)),
    assertion(b(c)).
test(lazy, [cleanup(init)]) :-
    init,
    \+ lb(c),
    assertz(e(c)),
    assertion(lb(c)).

on_answer(new_answer, _:b(X)) :-
    nb_getval(mono_events, Events),
    append(Events, [X], Events1),
    nb_setval(mono_events, Events1).
"""),
]

"The file's common tail (lines `before :- ...` to the end), verbatim."
const _TT_TAIL = raw"""
"""

"The rows: `(id, unit, goal)`; the goal is the plunit test with its options folded by hand."
const _TT_CASES = [
    ("ms01", "ms1", "setup_call_cleanup(true, pu_ms1:test(subsumed_empty_then_added, _), pu_ms1:init)"),
    ("ms02", "ms1", "setup_call_cleanup(true, pu_ms1:test(subsumed_warm, _), pu_ms1:init)"),
    ("ms03", "ms1", "setup_call_cleanup(true, pu_ms1:test(existing_variant, _), pu_ms1:init)"),
    ("ms04", "ms1", "setup_call_cleanup(true, pu_ms1:test(retract_reassert, _), pu_ms1:init)"),
    ("ms05", "ms2", "setup_call_cleanup(pu_ms2:abstract_subgoals, setup_call_cleanup(true, pu_ms2:test(empty_then_added, _), pu_ms2:init), pu_ms2:restore_subgoal_action)"),
    ("ms06", "ms2", "setup_call_cleanup(pu_ms2:abstract_subgoals, setup_call_cleanup(true, (pu_ms2:test(many_consumers, [C, _]), call(C)), pu_ms2:init), pu_ms2:restore_subgoal_action)"),
    ("ms07", "ms2", "setup_call_cleanup(pu_ms2:abstract_subgoals, setup_call_cleanup(true, (pu_ms2:test(index_shapes, [C, _]), call(C)), pu_ms2:init), pu_ms2:restore_subgoal_action)"),
    ("ms08", "ms2", "setup_call_cleanup(pu_ms2:abstract_subgoals, setup_call_cleanup(true, (pu_ms2:test(one_shared_table, [C, _]), call(C)), pu_ms2:init), pu_ms2:restore_subgoal_action)"),
    ("ms09", "ms2", "setup_call_cleanup(pu_ms2:abstract_subgoals, setup_call_cleanup(true, pu_ms2:test(warm, _), pu_ms2:init), pu_ms2:restore_subgoal_action)"),
    ("ms10", "ms2", "setup_call_cleanup(pu_ms2:abstract_subgoals, setup_call_cleanup(true, pu_ms2:test(not_abstracted, _), pu_ms2:init), pu_ms2:restore_subgoal_action)"),
    ("ms11", "ms2", "setup_call_cleanup(pu_ms2:abstract_subgoals, setup_call_cleanup(true, (pu_ms2:test(recursive, [C, _]), call(C)), pu_ms2:init), pu_ms2:restore_subgoal_action)"),
    ("ms12", "ms2", "setup_call_cleanup(pu_ms2:abstract_subgoals, setup_call_cleanup(true, (pu_ms2:test(new_answer, [C, _]), call(C)), pu_ms2:(init, prolog_unlisten(b/1, on_answer))), pu_ms2:restore_subgoal_action)"),
    ("ms13", "ms2", "setup_call_cleanup(pu_ms2:abstract_subgoals, setup_call_cleanup(true, pu_ms2:test(retract_reassert, _), pu_ms2:init), pu_ms2:restore_subgoal_action)"),
    ("ms14", "ms2", "setup_call_cleanup(pu_ms2:abstract_subgoals, setup_call_cleanup(true, pu_ms2:test(rollback, _), pu_ms2:init), pu_ms2:restore_subgoal_action)"),
    ("ms15", "ms2", "setup_call_cleanup(pu_ms2:abstract_subgoals, setup_call_cleanup(true, pu_ms2:test(lazy, _), pu_ms2:init), pu_ms2:restore_subgoal_action)"),
]

const _TT_PINNED = [
    "ok",
    "t_ms01 c[116,95,109,115,48,49]/1(a[111,107])",
    "t_ms02 c[116,95,109,115,48,50]/1(a[111,107])",
    "t_ms03 c[116,95,109,115,48,51]/1(a[111,107])",
    "t_ms04 c[116,95,109,115,48,52]/1(a[111,107])",
    "t_ms05 c[116,95,109,115,48,53]/1(a[111,107])",
    "t_ms06 c[116,95,109,115,48,54]/1(a[111,107])",
    "t_ms07 c[116,95,109,115,48,55]/1(a[111,107])",
    "t_ms08 c[116,95,109,115,48,56]/1(a[111,107])",
    "t_ms09 c[116,95,109,115,48,57]/1(a[111,107])",
    "t_ms10 c[116,95,109,115,49,48]/1(a[111,107])",
    "t_ms11 c[116,95,109,115,49,49]/1(a[111,107])",
    "t_ms12 c[116,95,109,115,49,50]/1(a[111,107])",
    "t_ms13 c[116,95,109,115,49,51]/1(a[111,107])",
    "t_ms14 c[116,95,109,115,49,52]/1(a[111,107])",
    "t_ms15 c[116,95,109,115,49,53]/1(a[111,107])",
]

"The answer plunit expects of every row: the test passes, `R = ok` (run in swipl by gen_tabling.py pin, plunit part of pins file)."
const _TT_UPSTREAM = [
    "a[111,107]",
    "a[111,107]",
    "a[111,107]",
    "a[111,107]",
    "a[111,107]",
    "a[111,107]",
    "a[111,107]",
    "a[111,107]",
    "a[111,107]",
    "a[111,107]",
    "a[111,107]",
    "a[111,107]",
    "a[111,107]",
    "a[111,107]",
    "a[111,107]",
]

"The files of the program in a fresh directory: one module file per unit, the main file with the rows; returns the main file."
function _tt_materialize()::String
    d = realpath(mktempdir())
    for (short, _, text) in _TT_UNITS
        write(
            joinpath(d, "pu_$short.pl"),
            ":- module(pu_$short, []).\n" * text * "\n" * _TT_TAIL
        )
    end
    main = join([":- catch(use_module('$d/pu_$short'), _, true).\n" for (short, _, _) in _TT_UNITS])
    main *= join([
        "t_$(id)(R) :- ( catch((abolish_all_tables, $g, abolish_all_tables, R = ok), error(SsuE, _), R = raised(SsuE)) -> true ; R = failed ).\n"
        for (id, _, g) in _TT_CASES
    ])
    write(joinpath(d, "main.pl"), main)
    return joinpath(d, "main.pl")
end

function _tt_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(f, _TT_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") * "]), halt)).\n")
        read(pipeline(addenv(`swipl -q $f`, "LC_ALL" => "C"); stdin=devnull, stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

"A kernel with the program consulted: `(gd, ld, first line of the driver's output)`."
function _tt_load(main::String)
    gd = LK.PL_global_data{_TT}()
    ld = LK.PL_local_data{_TT}(gd)
    st, ball = LK.load_file!(gd, ld, main)
    return gd, ld, (st === :ok ? "ok" : "exc " * _tt_enc(ball::_TT))
end

"The driver's line for `pred/1` (every answer, at most 50)."
function _tt_ask(gd, ld, pred::String)::String
    proc = LK.isCurrentProcedure(sym_key(_tts(pred)), 1, LK.MODULE_user(gd))
    (proc === nothing || !LK.isDefinedProcedure(gd, proc)) && return "$pred undefined"
    sols = String[]
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 1)
    LK.putSlotValue!(ld, a + 1, mk_var(_TT, LK.fresh_var_keys!(1)), LK.PutVarMap())
    qid = LK.PL_open_query(gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a)
    n = 0
    while (n += 1) <= 50
        rc = LK.PL_next_solution(gd, ld, qid)
        if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
            push!(sols, _tt_enc(mk_expr(_TT, _TT[_tts(pred), lk_answers(ld, (a:a)...)...])))
            rc == LK.PL_S_LAST && break
        elseif rc == LK.PL_S_EXCEPTION
            push!(sols, "exception")
            break
        else
            break
        end
    end
    LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
    return pred * join(" " .* sols)
end

"The part of a driver line after `t_<id> c[...]/1(`: the answer, as `_TT_UPSTREAM` holds it."
function _tt_answer(line::String)::String
    k = findfirst("/1(", line)::UnitRange{Int}
    return line[(last(k) + 1):(end - 1)]
end

"A line the same length that must differ from `s` (the must-fail corruption)."
_tt_corrupt(s::String) = s[1:(end - 2)] * (s[end - 1] == '0' ? "1" : "0") * s[end]

@testset "upstream test_mono_subsumptive.pl: the kernel answers every row as swipl does" begin
    gd, ld, st = _tt_load(_tt_materialize())
    @test st == "ok"
    kl = String[st]
    for (id, _, _) in _TT_CASES
        push!(kl, _tt_ask(gd, ld, "t_$id"))
    end
    @test length(kl) == length(_TT_PINNED)
    for (k, pn) in zip(kl, _TT_PINNED)
        k == pn || println(stderr, "  ours  ", k, "\n  swipl ", pn)
        @test k == pn
    end
    # must-fail: a corrupted pin is not the kernel's line (the comparison can fail)
    @test length(kl) > 1
    @test kl[2] != _tt_corrupt(_TT_PINNED[2])
end

@testset "the pins are the upstream (plunit) expectations (no swipl needed)" begin
    @test length(_TT_PINNED) == length(_TT_CASES) + 1
    @test length(_TT_UPSTREAM) == length(_TT_CASES)
    @test !isempty(_TT_UPSTREAM) && all(!isempty, _TT_UPSTREAM)
    @test _TT_PINNED[1] == "ok"
    for (pn, up) in zip(_TT_PINNED[2:end], _TT_UPSTREAM)
        @test _tt_answer(pn) == up
    end
    # must-fail: the corruption of a pin is not the upstream expectation
    @test _tt_answer(_tt_corrupt(_TT_PINNED[2])) != _TT_UPSTREAM[1]
end

@testset "the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        got = _tt_swipl_lines(_tt_materialize(), ["t_$id" for (id, _, _) in _TT_CASES])
        @test !isempty(got) && got == _TT_PINNED
        # must-fail: a corrupted pin is not swipl's line
        @test got[2] != _tt_corrupt(_TT_PINNED[2])
    end
end
