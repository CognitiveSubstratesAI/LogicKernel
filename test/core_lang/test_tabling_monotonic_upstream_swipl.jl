# ORIGINAL: the UPSTREAM tests/tabling/test_monotonic.pl (swipl-devel 18168e62, 10.1.20), units monotonic_tabling, monotonic_tabling_2, monotonic_tabling_3 of 3 (10 of 10 tests), as
# kernel rows (TAB1, TABTEST-MON). One row `t_m<NN>(R)` per upstream test: `abolish_all_tables, <goal>, abolish_all_tables`, R = ok / failed /
# raised(E).
#   * Comments matching the D-0164 terms are elided from the embedded text; no code differs.
#   * Each unit is its own module (`pu_mono1`..): the text between `begin_tests` and `end_tests` verbatim, preceded by the use_module lines of
#     the file's libraries and `:- discontiguous test/1, test/2.` and the file's `:- meta_predicate` declaration, followed by the file's TEST
#     HELPERS section (init/1, cleanup/1, expect/3, expect_valid/1 .. expect_queued_answers/2) verbatim. plunit gives each unit a module that
#     sees the file module's helpers; here every unit module carries its own copy. A unit whose load a kernel refuses leaves only ITS rows
#     undefined: main.pl loads each unit with `catch(use_module(..), _, true)` (the pin loads all, status ok).
#   * DIVERGES from the file: plunit is not used (a row calls the unit's test/1 or test/2 clause directly). The unit's `term_expansion` (unit 1,
#     module-local) adds `cleanup(cleanup)` to every test/2 option: a row passes `[_, Cond]` (so a kernel without module-local term_expansion
#     shows it as a failed row). The options are folded by hand: `Var op Val` is called after the body (shared variable), `cleanup(G)` is the
#     cleanup goal of a setup_call_cleanup (cleanup/0 of unit 1, clean/0 of unit 2). Two tests are named incr_mono (unit 1), told apart by the
#     option (`true` / `L == [1]`).
#   * Expected refusals on the kernel (by reading, unverified): `table .. as monotonic`, `:- dynamic .. as (incremental,monotonic)`, `lazy`
#     (unit 2), incr_propagate_calls/1 and incr_invalidate_calls/1 (unit 3), get_returns_for_call/2, incr_is_invalid/1, random_between/3; the
#     helpers '$idg_forced'/1 and '$idg_mono_affects_lazy'/5 are only loaded, no row calls them.
#     The kernel's own monotonic rows (test_tabling_monotonic_swipl.jl, mono01-08) are a different file. Every row stays pinned on swipl.
#   * Every pinned line is swipl's (swipl 10.1.20, two identical runs, evidence/TAB1/tabgap_tools/pins_mon*.txt, which also holds the plunit
#     run) AND equals the answer plunit expects (`_TT_UPSTREAM`: each test passes, so `ok`).
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
    ("mono1", "begin_tests(monotonic_tabling)", raw"""
:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(debug)).
:- use_module(library(tables)).
:- use_module(library(random)).
:- use_module(library(increval)).
:- discontiguous test/1, test/2.
:- meta_predicate
    init(0),
    cleanup(:),
    queued_answers(:,-,-),
    expect(?, 0, +),
    expect_valid(0),
    expect_invalid(0),
    expect_forced(0),
    incr_is_forced(0),
    expect_queued_answers(:, +).
term_expansion((test(Name, Cond0) :- Body),
               (test(Name, Cond) :- Body)) :-
    (   is_list(Cond0)
    ->  Cond = [cleanup(cleanup)|Cond0]
    ;   Cond = [cleanup(cleanup),Cond0]
    ).

cleanup :-
    abolish_all_tables,
    retractall(da(_)),
    retractall(db(_)),
    retractall(dx(_)),
    retractall(lm(_,_)),
    retractall(la(_,_)),
    retractall(nd1(_)),
    retractall(nd2(_)).

% Very basic test

:- dynamic da/1 as monotonic.
:- table pa/1 as monotonic.

pa(X) :- da(Y), X is Y+1.

test(pa1, X == 1) :-
    assertion(\+ pa(_)),
    assert(da(0)),
    assertion(get_returns_for_call(pa(_), pa(1))),
    pa(X).
test(pa2, X == 1) :-
    assert(da(0), Ref),
    pa(X),
    erase(Ref),
    assertion(\+ pa(_)).

% Combining monotonic and incremental

:- dynamic db/1 as (incremental,monotonic).
:- table pb/1 as monotonic.
:- table qb/1 as incremental.

pb(X) :- db(Y), X is Y+1.
qb(X) :- db(Y), X is Y+2.

test(pb, true) :-
    assertion(\+ pb(_)),
    assertion(\+ qb(_)),
    assert(db(0)),
    assertion((pb(X), X == 1)),
    assertion(\+ qb(1)),
    assertion((qb(X), X == 2)).

% Deal with new dependencies while propagating

:- table cm/2 as monotonic.
:- dynamic lm/2 as monotonic.

cm(X, Y) :-
    cm(Y, X).
cm(X, Z) :-
    cm(X, Y),
    cm(Y, Z).
cm(X, Y) :-
    lm(X, Y).

:- table ca/2.
:- dynamic la/2.

ca(X, Y) :-
    ca(Y, X).
ca(X, Z) :-
    ca(X, Y),
    ca(Y, Z).
ca(X, Y) :-
    la(X, Y).

test(closure, Len == 9) :-
    ignore(cm(_,_)),
    assert(lm(a, b)),
    assert(lm(a, c)),
    findall(X-Y, cm(X,Y), Pairs),
    length(Pairs, Len).
test(closure2, PairsMS == PairsAS) :-
    N = 16,
    Max is 10*N,
    ignore(cm(_,_)),
    (   between(1, N, _),
        random_between(1, Max, X),
        random_between(1, Max, Y),
        assert(lm(X,Y)),
        assert(la(X,Y)),
        fail
    ;   true
    ),
    findall(X-Y, cm(X,Y), PairsM),
    findall(X-Y, ca(X,Y), PairsA),
    sort(PairsM, PairsMS),
    sort(PairsA, PairsAS).

% Incremental tables can depend on monotonic tables

:- dynamic dx/1 as (incremental,monotonic).
:- table px/1 as monotonic.
:- table qx/1 as incremental.

px(X) :- dx(Y), X is Y+1.
qx(X) :- px(Y), X is Y*2.

test(incr_mono, true) :-
    retractall(dx(_)),
    assert(dx(1)),
    qx(X),
    assertion(X == 4),
    assert(dx(2)),
    assertion(incr_is_invalid(qx(_))),
    forall(qx(_), true),
    assertion(get_returns_for_call(qx(_), qx(6))).

% Monotonic table can have both monotonic and incremental dependents

:- table pmi/1 as monotonic.
:- dynamic dm/1 as monotonic.
:- dynamic di/1 as incremental.

pmi(X) :-
    dm(X),
    \+ di(X).

test(incr_mono, L == [1]) :-
    forall(pmi(_), true),
    asserta(dm(1)),
    asserta(dm(2)),
    asserta(di(2)),
    assertion(incr_is_invalid(pmi(_))),
    findall(X, pmi(X), L).

% Test nested reevaluation of a monotonic table that was invalidated
% due to a retract

:- dynamic (nd1/1, nd2/1) as (incremental,monotonic).
:- table (np/1,ni/1) as (incremental).
:- table (nm/1) as monotonic.

np(X) :-
    (   ni(X)
    ;   nm(X)
    ).

ni(X) :- nd1(X).
nm(X) :- nd2(X).

test(nested_reeval_mono, true) :-
    assert(nd1(1)),
    assert(nd2(2)),
    setof(X, np(X), Xs1),
    assertion(Xs1 == [1,2]),
    assert(nd1(3)),
    retract(nd2(2)),
    assert(nd2(3)),
    setof(X, np(X), Xs2),
    assertion(Xs2 == [1,3]).
"""),
    ("mono2", "begin_tests(monotonic_tabling_2)", raw"""
:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(debug)).
:- use_module(library(tables)).
:- use_module(library(random)).
:- use_module(library(increval)).
:- discontiguous test/1, test/2.
:- meta_predicate
    init(0),
    cleanup(:),
    queued_answers(:,-,-),
    expect(?, 0, +),
    expect_valid(0),
    expect_invalid(0),
    expect_forced(0),
    incr_is_forced(0),
    expect_queued_answers(:, +).
:- dynamic (d1/1, d2/1, d3/1) as (incremental,monotonic).
:- table (p/1,i/1) as (incremental).
:- table (m/1,n/1) as (monotonic,lazy).

p(X) :-
    (   i(X)
    ;   m(X)
    ).

i(X) :- d3(X).
m(X) :- n(X).
m(X) :- d2(X).

n(X) :- d1(X).

clean :-
    retractall(d1(_)),
    retractall(d2(_)),
    retractall(d3(_)),
    abolish_all_tables.

test(twice_invalid, [Xs == [1,2,3], cleanup(clean)]) :-
    assert(d1(1)),
    assert(d2(2)),
    forall(p(_), true),
    retract(d1(1)),
    assert(d1(1)),
    retract(d2(2)),
    assert(d2(2)),
    assert(d3(3)),
    setof(X, p(X), Xs).
"""),
    ("mono3", "begin_tests(monotonic_tabling_3)", raw"""
:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(debug)).
:- use_module(library(tables)).
:- use_module(library(random)).
:- use_module(library(increval)).
:- discontiguous test/1, test/2.
:- meta_predicate
    init(0),
    cleanup(:),
    queued_answers(:,-,-),
    expect(?, 0, +),
    expect_valid(0),
    expect_invalid(0),
    expect_forced(0),
    incr_is_forced(0),
    expect_queued_answers(:, +).
:- dynamic data/1.
:- dynamic d/1 as monotonic.
:- table p/1 as monotonic.

p(X) :- d(X).
d(X) :- data(X).

test(incr_propagate) :-
    cleanup([data/1]),
    assert(data(1)),
    expect(X, p(X), [1]),
    assert(data(2)),
    expect(X, p(X), [1]),
    incr_propagate_calls(d(2)),
    expect(X, p(X), [1,2]),
    retractall(data(2)),
    expect(X, p(X), [1,2]),
    incr_invalidate_calls(d(2)),
    expect(X, p(X), [1]).
"""),
]

"The file's common tail (lines `before :- ...` to the end), verbatim."
const _TT_TAIL = raw"""
init(P) :-
    forall(P, true).

cleanup(M:List) :-
    abolish_all_tables,
    maplist(cleanup(M), List).

cleanup(M, PI) :-
    pi_head(PI, Head),
    retractall(M:Head).

expect(Templ, Goal, Answer) :-
    findall(Templ, Goal, R0),
    sort(R0, R),
    sort(Answer, Answer1),
    assertion(Answer1 == R).

expect_valid(Goal) :-
    assertion(\+ incr_is_invalid(Goal)).

expect_invalid(Goal) :-
    assertion(incr_is_invalid(Goal)).

expect_forced(Goal) :-
    assertion(incr_is_forced(Goal)).

incr_is_forced(Goal) :-
    get_call(Goal, ATrie, _Templ),
    '$idg_forced'(ATrie).

queued_answers(To, From, Count) :-
    get_calls(To, DstTrie, _Ret),
    '$idg_mono_affects_lazy'(DstTrie, SrcTrie, _Dep, _DepRef, Answers),
    '$tbl_table_status'(SrcTrie, _Status, From0, _Skeleton),
    unqualify(To, From0, From),
    length(Answers, Count).

unqualify(M:_, M:From, From) :- !.
unqualify(_, From, From).


expect_queued_answers(To, Expected0) :-
    findall(From-Count, queued_answers(To, From, Count), Pairs1),
    sort(Pairs1, Found),
    sort(Expected0, Expected),
    assertion(Found =@= Expected).
"""

"The rows: `(id, unit, goal)`; the goal is the plunit test with its options folded by hand."
const _TT_CASES = [
    ("m01", "mono1", "setup_call_cleanup(true, (pu_mono1:test(pa1, [_, C]), call(C)), pu_mono1:cleanup)"),
    ("m02", "mono1", "setup_call_cleanup(true, (pu_mono1:test(pa2, [_, C]), call(C)), pu_mono1:cleanup)"),
    ("m03", "mono1", "setup_call_cleanup(true, pu_mono1:test(pb, [_, true]), pu_mono1:cleanup)"),
    ("m04", "mono1", "setup_call_cleanup(true, (pu_mono1:test(closure, [_, C]), call(C)), pu_mono1:cleanup)"),
    ("m05", "mono1", "setup_call_cleanup(true, (pu_mono1:test(closure2, [_, C]), call(C)), pu_mono1:cleanup)"),
    ("m06", "mono1", "setup_call_cleanup(true, pu_mono1:test(incr_mono, [_, true]), pu_mono1:cleanup)"),
    ("m07", "mono1", "setup_call_cleanup(true, (pu_mono1:test(incr_mono, [_, (Lm == [1])]), Lm == [1]), pu_mono1:cleanup)"),
    ("m08", "mono1", "setup_call_cleanup(true, pu_mono1:test(nested_reeval_mono, [_, true]), pu_mono1:cleanup)"),
    ("m09", "mono2", "setup_call_cleanup(true, (pu_mono2:test(twice_invalid, [C, _]), call(C)), pu_mono2:clean)"),
    ("m10", "mono3", "pu_mono3:test(incr_propagate)"),
]

const _TT_PINNED = [
    "ok",
    "t_m01 c[116,95,109,48,49]/1(a[111,107])",
    "t_m02 c[116,95,109,48,50]/1(a[111,107])",
    "t_m03 c[116,95,109,48,51]/1(a[111,107])",
    "t_m04 c[116,95,109,48,52]/1(a[111,107])",
    "t_m05 c[116,95,109,48,53]/1(a[111,107])",
    "t_m06 c[116,95,109,48,54]/1(a[111,107])",
    "t_m07 c[116,95,109,48,55]/1(a[111,107])",
    "t_m08 c[116,95,109,48,56]/1(a[111,107])",
    "t_m09 c[116,95,109,48,57]/1(a[111,107])",
    "t_m10 c[116,95,109,49,48]/1(a[111,107])",
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

@testset "upstream test_monotonic.pl: the kernel answers every row as swipl does" begin
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
