# ORIGINAL: the UPSTREAM tests/tabling/test_mono_reuse.pl (swipl-devel 18168e62, 10.1.20), units mono_reuse_subsumptive, mono_reuse_abstract of 2 (6 of 6 tests), as
# kernel rows (TAB1, TABTEST-MR). One row `t_mr<NN>(R)` per upstream test: `abolish_all_tables, <goal>, abolish_all_tables`, R = ok / failed /
# raised(E). Monotonic tabling of reused tables: each consumer is called with the same variant before and after the update (subsumptive
# tables, indirect keys, incremental tables, subgoal_abstract(0)).
#   * Comments matching the D-0164 terms are elided from the embedded text; no code differs (none matched in this file).
#   * Each unit is its own module (`pu_mr1`, `pu_mr2`): the text between `begin_tests` and `end_tests` verbatim, preceded by the use_module
#     lines of the file's libraries (lists; debug for assertion/1, which plunit provides), `:- discontiguous test/1, test/2.` and the file's own
#     helper, all/3 with its meta_predicate declaration (the prelude of the file; the pin's unit modules inherit it from the file's module).
#     The file has no other helper section (`_TT_TAIL` is empty). Each unit loads with `catch(use_module(..), _, true)`, so a unit the kernel
#     refuses leaves only ITS rows undefined (the pin loads both, status ok).
#   * DIVERGES from the file: plunit is not used (a row calls the unit's test/2 clause directly). The options are folded by hand: `cleanup(init)`
#     is the cleanup goal of a setup_call_cleanup (init/0 of the unit); the single option `L2-L3 == [a,b]-[c]` of incremental_reevaluation
#     (no list, no cleanup) is called after the body (the variables are shared with the clause). The unit options of mono_reuse_abstract,
#     setup(abstract_subgoals) and cleanup(restore_subgoal_action), wrap EVERY row of unit 2 (plunit runs them once around the unit's tests):
#     they set max_table_subgoal_size_action to `abstract` and restore it (nb_setval/nb_getval inside the unit).
#   * Expected refusals on the kernel (by reading, unverified): `table .. as (subsumptive, monotonic)`, `:- dynamic .. as monotonic`,
#     `as incremental` on a dynamic predicate combined with subsumptive/monotonic, subgoal_abstract(0), the flag max_table_subgoal_size_action.
#     The kernel's own partial port (test_tabling_mono_subsumptive_swipl.jl, its own programs) is a different file, untouched. Every row stays
#     pinned on swipl.
#   * Every pinned line is swipl's (swipl 10.1.20, two identical runs, evidence/TAB1/tabgap_tools/pins_mr.txt, which also holds the plunit
#     run: 6 of 6 tests passed, none failed or hung on the pin) AND equals the answer plunit expects (`_TT_UPSTREAM`: each test passes, so `ok`).
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
    ("mr1", "begin_tests(mono_reuse_subsumptive)", raw"""
:- use_module(library(lists)).
:- use_module(library(debug)).
:- discontiguous test/1, test/2.
:- meta_predicate all(?, 0, -).
all(T, G, L) :- findall(T, G, L0), msort(L0, L).
:- dynamic e/2 as monotonic.
:- dynamic s0/1 as monotonic.
:- dynamic inc/1 as incremental.

:- table p/2 as (subsumptive, monotonic).
:- table r1/1 as monotonic.
:- table r2/1 as monotonic.
:- table r3/1 as monotonic.
p(X,Y) :- e(X,Y).
r1(Y) :- p(a, Y).
r2(X) :- p(X, b).
r3(Z) :- p(Z, Z).

:- table sp/2 as (subsumptive, monotonic).
:- table sq/1 as monotonic.
sp(X,Y) :- e(X,Y).
sp(X,Y) :- e(X,Z), sp(Z,Y).
sq(Y) :- sp(k, Y).

:- table tq/1 as monotonic.
tq(Y) :- s0(X), p(X, Y).

:- table ip/2 as (subsumptive, monotonic, incremental).
:- table iq/1 as (monotonic, incremental).
ip(X,Y) :- e(X,Y), \+ inc(Y).
iq(Y) :- ip(k, Y).

init :-
    abolish_all_tables,
    retractall(e(_,_)),
    retractall(s0(_)),
    retractall(inc(_)).

test(binding_patterns, [cleanup(init)]) :-
    init,
    all(X-Y, p(X,Y), []),
    all(Y, r1(Y), []), all(X, r2(X), []), all(Z, r3(Z), []),
    assertz(e(a, b)),
    assertion(all(Y, r1(Y), [b])),
    assertion(all(X, r2(X), [a])),
    assertion(all(Z, r3(Z), [])),
    assertz(e(c, c)),
    assertion(all(Z, r3(Z), [c])),
    assertz(e(a, a)),
    assertion(all(Y, r1(Y), [a,b])),
    assertion(all(X, r2(X), [a])),
    assertion(all(Z, r3(Z), [a,c])).
test(subsumed_recursive, [cleanup(init)]) :-
    init,
    assertz(e(k, m)),
    all(X-Y, sp(X,Y), _),
    assertion(all(Y, sq(Y), [m])),
    assertz(e(m, n)),
    assertion(all(Y, sq(Y), [m,n])),
    assertz(e(q, k)),
    assertion(all(Y, sq(Y), [m,n])),
    assertz(e(n, q)),
    assertion(all(Y, sq(Y), [k,m,n,q])).
test(dep_during_propagation, [cleanup(init)]) :-
    init,
    assertz(e(a, 1)), assertz(e(b, 2)),
    all(X-Y, p(X,Y), _),
    assertion(all(Y, tq(Y), [])),
    assertz(s0(a)),                     % propagation calls subsumed p(a,Y)
    assertion(all(Y, tq(Y), [1])),
    assertz(e(a, 3)),                   % reaches tq/1 through the new dep
    assertion(all(Y, tq(Y), [1,3])),
    assertz(e(b, 4)),
    assertion(all(Y, tq(Y), [1,3])).
test(incremental, [cleanup(init)]) :-
    init,
    all(X-Y, ip(X,Y), _),
    assertion(all(Y, iq(Y), [])),
    assertz(e(k, 1)),
    assertion(all(Y, iq(Y), [1])),
    assertz(inc(1)),
    assertion(all(Y, iq(Y), [])),
    assertz(e(k, 2)),
    assertion(all(Y, iq(Y), [2])),
    retract(inc(1)),
    assertion(all(Y, iq(Y), [1,2])).
"""),
    ("mr2", "begin_tests(mono_reuse_abstract)", raw"""
:- use_module(library(lists)).
:- use_module(library(debug)).
:- discontiguous test/1, test/2.
:- meta_predicate all(?, 0, -).
all(T, G, L) :- findall(T, G, L0), msort(L0, L).
:- dynamic kb/2 as monotonic.
:- dynamic d/2 as incremental.

:- table kp/1 as (subgoal_abstract(0), monotonic).
:- table kq/2 as monotonic.
kp(k(X,Y)) :- kb(X,Y).
kq(X,Y) :- kp(k(X,Y)).

:- table ia/1 as (subgoal_abstract(0), incremental).
ia(args(X,Y)) :- d(X,Y).

abstract_subgoals :-
    current_prolog_flag(max_table_subgoal_size_action, Action),
    nb_setval(mono_reuse_subgoal_action, Action),
    set_prolog_flag(max_table_subgoal_size_action, abstract).

restore_subgoal_action :-
    nb_getval(mono_reuse_subgoal_action, Action),
    set_prolog_flag(max_table_subgoal_size_action, Action).

init :-
    abolish_all_tables,
    retractall(kb(_,_)),
    retractall(d(_,_)).

test(indirect_keys, [cleanup(init)]) :-
    init,
    B is 2^100, S = "a string", F = 1.5,
    all(Y, kq(B,Y), []), all(Y, kq(S,Y), []), all(Y, kq(F,Y), []),
    assertz(kb(B, big)), assertz(kb(S, str)), assertz(kb(F, flt)),
    assertz(kb(2^100, wrong)),
    assertion(all(Y, kq(B,Y), [big])),
    assertion(all(Y, kq(S,Y), [str])),
    assertion(all(Y, kq(F,Y), [flt])).
test(incremental_reevaluation, L2-L3 == [a,b]-[c]) :-
    init,
    assertz(d(1,a)),
    all(Y, ia(args(1,Y)), [a]),
    assertz(d(1,b)), assertz(d(2,c)),
    all(Y, ia(args(1,Y)), L2),
    all(Y, ia(args(2,Y)), L3),
    init.
"""),
]

"The file's common tail (lines `before :- ...` to the end), verbatim."
const _TT_TAIL = raw"""
"""

"The rows: `(id, unit, goal)`; the goal is the plunit test with its options folded by hand."
const _TT_CASES = [
    ("mr01", "mr1", "setup_call_cleanup(true, pu_mr1:test(binding_patterns, _), pu_mr1:init)"),
    ("mr02", "mr1", "setup_call_cleanup(true, pu_mr1:test(subsumed_recursive, _), pu_mr1:init)"),
    ("mr03", "mr1", "setup_call_cleanup(true, pu_mr1:test(dep_during_propagation, _), pu_mr1:init)"),
    ("mr04", "mr1", "setup_call_cleanup(true, pu_mr1:test(incremental, _), pu_mr1:init)"),
    ("mr05", "mr2", "setup_call_cleanup(pu_mr2:abstract_subgoals, setup_call_cleanup(true, pu_mr2:test(indirect_keys, _), pu_mr2:init), pu_mr2:restore_subgoal_action)"),
    ("mr06", "mr2", "setup_call_cleanup(pu_mr2:abstract_subgoals, setup_call_cleanup(true, (pu_mr2:test(incremental_reevaluation, C), call(C)), true), pu_mr2:restore_subgoal_action)"),
]

const _TT_PINNED = [
    "ok",
    "t_mr01 c[116,95,109,114,48,49]/1(a[111,107])",
    "t_mr02 c[116,95,109,114,48,50]/1(a[111,107])",
    "t_mr03 c[116,95,109,114,48,51]/1(a[111,107])",
    "t_mr04 c[116,95,109,114,48,52]/1(a[111,107])",
    "t_mr05 c[116,95,109,114,48,53]/1(a[111,107])",
    "t_mr06 c[116,95,109,114,48,54]/1(a[111,107])",
]

"The answer plunit expects of every row: the test passes, `R = ok` (run in swipl by gen_tabling.py pin, plunit part of pins file)."
const _TT_UPSTREAM = [
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

@testset "upstream test_mono_reuse.pl: the kernel answers every row as swipl does" begin
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
