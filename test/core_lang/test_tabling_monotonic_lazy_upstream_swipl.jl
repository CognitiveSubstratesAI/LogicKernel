# ORIGINAL: the UPSTREAM tests/tabling/test_monotonic_lazy.pl (swipl-devel 18168e62, 10.1.20), 15 of its 16 units (tabling_monotonic_lazy_1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 16), 17
# of its 18 tests, as kernel rows (TAB1, TABTEST-LAZY). One row `t_z<NN>(R)` per upstream test: `abolish_all_tables, <goal>, abolish_all_tables`,
# R = ok / failed / raised(E).
# unit 15 (verify/2 uses a D-0164-listed token in code) is NOT ported here: open question for the audit (D-0664 follow-up)
#   (unit tabling_monotonic_lazy_15, its test `closure`, row id z17 skipped; upstream line 525).
#   * Comments matching the D-0164 terms are elided from the embedded text; no code differs.
#   * Each unit is its own module (`pu_lz1`..): the text between `begin_tests` and `end_tests` verbatim, preceded by the use_module lines of
#     the file's libraries and `:- discontiguous test/1, test/2.` and the file's `:- meta_predicate` declaration, followed by the file's TEST
#     HELPERS section (init/1, cleanup/1, expect/3, expect_valid/1 .. expect_queued_answers/2) verbatim. plunit gives each unit a module that
#     sees the file module's helpers; here every unit module carries its own copy. A unit whose load a kernel refuses leaves only ITS rows
#     undefined: main.pl loads each unit with `catch(use_module(..), _, true)` (the pin loads all, status ok).
#   * DIVERGES from the file: plunit is not used (a row calls the unit's test/1 or test/2 clause directly). The options are folded by hand:
#     `cleanup(cleanup([d/1]))` (units 1 and 2) is the cleanup goal of a setup_call_cleanup (the option sits in the clause head, a row passes
#     an unbound variable); the option `fail` (unit 14) is a negated row.
#   * Expected refusals on the kernel (by reading, unverified): `table .. as monotonic`, `:- dynamic .. as monotonic`, `lazy`, incr_is_invalid/1,
#     and, for unit 3 only (its `expect_queued_answers/2`), get_calls/3, '$idg_mono_affects_lazy'/5 and '$tbl_table_status'/4; the helpers
#     expect_forced/1, incr_is_forced/1 and '$idg_forced'/1 are only loaded (no test calls them). The kernel's own monotonic rows
#     (test_tabling_monotonic_swipl.jl, mono01-08) are a different file. Every row stays pinned on swipl.
#   * Every pinned line is swipl's (swipl 10.1.20, two identical runs, evidence/TAB1/tabgap_tools/pins_lazy*.txt, which also hold the plunit
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
    ("lz1", "begin_tests(tabling_monotonic_lazy_1)", raw"""
:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(debug)).
:- use_module(library(tables)).
:- use_module(library(prolog_code)).
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
:- dynamic d/1 as monotonic.
:- table p/1 as (monotonic,lazy).

p(X) :- d(X).

test(simple, [cleanup(cleanup([d/1]))]) :-
    init(p(_)),
    assertz(d(1)),
    expect_invalid(p(_)),
    expect(X, p(X), [1]),
    expect_valid(p(_)),
    assertz(d(2)),
    expect_invalid(p(_)),
    expect(X, p(X), [1,2]),
    expect_valid(p(_)).
test(retract, [cleanup(cleanup([d/1]))]) :-
    init(p(_)),
    assertz(d(1)),
    assertz(d(2)),
    expect(X, p(X), [1,2]),
    retract(d(1)),
    expect(X, p(X), [2]).
"""),
    ("lz2", "begin_tests(tabling_monotonic_lazy_2)", raw"""
:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(debug)).
:- use_module(library(tables)).
:- use_module(library(prolog_code)).
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
:- dynamic d/1 as monotonic.
:- table p1/1 as (monotonic,lazy).
:- table p2/1 as (monotonic).

p1(X) :- d(X).
p2(X) :- d(X).

test(mon_and_lazy, [cleanup(cleanup([d/1]))]) :-
    init(p1(_)),
    init(p2(_)),
    assertz(d(1)),
    expect_invalid(p1(_)),
    expect_queued_answers(p1(_), [d(_)-1]),
    expect_valid(p2(_)),
    expect(X, p1(X), [1]),
    expect(X, p2(X), [1]),
    expect_valid(p1(_)).
"""),
    ("lz3", "begin_tests(tabling_monotonic_lazy_3)", raw"""
:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(debug)).
:- use_module(library(tables)).
:- use_module(library(prolog_code)).
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
:- dynamic d/1 as monotonic.
:- table (p1/1,p2/1) as (monotonic,lazy).

p1(X) :- d(X).
p2(X) :- p1(X).

test(intermediate) :-
    cleanup([d/1]),
    init(p2(_)),
    assertz(d(1)),
    expect_invalid(p1(_)),
    expect_invalid(p2(_)),
    expect(X, p2(X), [1]),
    expect_valid(p1(_)),
    expect_valid(p2(_)),
    assertz(d(2)),
    expect(X, p2(X), [1,2]).
"""),
    ("lz4", "begin_tests(tabling_monotonic_lazy_4)", raw"""
:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(debug)).
:- use_module(library(tables)).
:- use_module(library(prolog_code)).
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
:- dynamic d/1 as monotonic.
:- table p1/1 as monotonic.
:- table p2/1 as (monotonic,lazy).

p1(X) :- d(X).
p2(X) :- p1(X).

test(lazy_on_eager) :-
    cleanup([d/1]),
    assert(d(1)),
    expect(X, p1(X), [1]),
    expect(X, p2(X), [1]),
    assert(d(2)),
    expect(X, p1(X), [1,2]),
    expect_invalid(p2(_)),
    expect(X, p2(X), [1,2]),
    true.
"""),
    ("lz5", "begin_tests(tabling_monotonic_lazy_5)", raw"""
:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(debug)).
:- use_module(library(tables)).
:- use_module(library(prolog_code)).
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
:- dynamic d/1 as monotonic.
:- table p1/1 as (monotonic,lazy).
:- table p2/1 as monotonic.

p1(X) :- d(X).
p2(X) :- p1(X).

test(lazy_on_eager) :-
    cleanup([d/1]),
    assert(d(1)),
    expect(X, p1(X), [1]),
    expect(X, p2(X), [1]),
    assert(d(2)),
    expect_invalid(p2(_)),
    expect(X, p2(X), [1,2]).
test(lazy_on_eager_retract) :-
    cleanup([d/1]),
    assert(d(1), Ref),
    expect(X, p1(X), [1]),
    expect(X, p2(X), [1]),
    assert(d(2)),
    expect_invalid(p2(_)),
    expect(X, p2(X), [1,2]),
    erase(Ref),
    expect_invalid(p1(_)),
    expect_invalid(p2(_)),
    expect(X, p2(X), [2]),
    expect(X, p1(X), [2]).
"""),
    ("lz6", "begin_tests(tabling_monotonic_lazy_6)", raw"""
:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(debug)).
:- use_module(library(tables)).
:- use_module(library(prolog_code)).
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
% Deal with depending answer subsumptive tabling

:- dynamic (d1/1,d2/1) as monotonic.
:- table (p(min),r(min),q(min)) as (monotonic,lazy).
:- dynamic reeval/0.

r(X) :- d1(X).
q(X) :- d2(X).
p(X) :- assert(reeval), r(X) ; q(X).

test(lazy_reeval) :-
    cleanup([d1/1, d2/1]),
    expect(X, p(X), []),
    retractall(reeval),
    assert(d1(1)),
    expect(X, p(X), [1]),
    assertion(\+ reeval),
    assert(d1(0)),
    expect(X, p(X), [0]),
    assertion(\+ reeval),
    assert(d2(-1)),
    expect(X, p(X), [-1]),
    assertion(\+ reeval),
    assert(d2(2)),
    expect(X, p(X), [-1]),
    assertion(\+ reeval).
"""),
    ("lz7", "begin_tests(tabling_monotonic_lazy_7)", raw"""
:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(debug)).
:- use_module(library(tables)).
:- use_module(library(prolog_code)).
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
% Deal with depending answer subsumptive tabling (non-lazy)

:- dynamic (d1/1,d2/1) as monotonic.
:- table (p(min),r(min),q(min)) as (monotonic).
:- dynamic reeval/0.

r(X) :- d1(X).
q(X) :- d2(X).
p(X) :- assert(reeval), r(X) ; q(X).

test(lazy_reeval) :-
    cleanup([d1/1, d2/1]),
    expect(X, p(X), []),
    retractall(reeval),
    assert(d1(1)),
    expect(X, p(X), [1]),
    assertion(\+ reeval),
    assert(d1(0)),
    expect(X, p(X), [0]),
    assertion(\+ reeval),
    assert(d2(-1)),
    expect(X, p(X), [-1]),
    assertion(\+ reeval),
    assert(d2(2)),
    expect(X, p(X), [-1]),
    assertion(\+ reeval).
"""),
    ("lz8", "begin_tests(tabling_monotonic_lazy_8)", raw"""
:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(debug)).
:- use_module(library(tables)).
:- use_module(library(prolog_code)).
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
% Verify that a switch to incremental due to a retract propagates.
% Note that eventually this may change.

:- dynamic dm/1 as monotonic.
:- dynamic xm/1 as monotonic.
:- table aml/1 as (monotonic,lazy).
:- table bml/1 as (monotonic,lazy).

bml(X) :- aml(X) ; xm(X).
aml(X) :- dm(X).

test(indirect_lazy_retract) :-
    cleanup([dm/1, xm/1]),
    assert(dm(1)),
    assert(dm(2)),
    expect(X, bml(X), [1,2]),
    assert(xm(3)),
    assert(dm(4)),
    retract(dm(1)),
    expect_invalid(aml(_)),
    expect_invalid(bml(_)),
    expect_forced(aml(_)),
    expect_forced(bml(_)),
    expect(X, bml(X), [2,3,4]).
"""),
    ("lz9", "begin_tests(tabling_monotonic_lazy_9)", raw"""
:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(debug)).
:- use_module(library(tables)).
:- use_module(library(prolog_code)).
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
:- dynamic d/1 as monotonic.
:- table p/1 as (monotonic,lazy).

p(c) :-
    d(a),
    d(b).

test(capture_new_dependencies) :-
    cleanup([d/1]),
    expect(X, p(X), []),
    assert(d(a)),
    expect(X, p(X), []),                % evaluation must create dependency on d(b).
    assert(d(b)),
    expect(X, p(X), [c]).
"""),
    ("lz10", "begin_tests(tabling_monotonic_lazy_10)", raw"""
:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(debug)).
:- use_module(library(tables)).
:- use_module(library(prolog_code)).
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
% We can only  only  update  a  lazy   monotonic  table  after  all  its
% dependencies are updated. As we currently work bottom-up breath-first,
% this does not always has to be the   case.  Therefore we keep nodes we
% cannot yet reevaluate in the falsepaths.
%
% TBD: Eventually we may opt for a better planning of the reevaluation.

:- dynamic (d1/1,d2/1,d3/1) as monotonic.
:- table (p/1,a/1,b/1,c/1) as (monotonic,lazy).

p(X) :- ( a(X) ; b(X); d3(X) ).
b(X) :- c(X).
c(X) :- d1(X).
a(X) :- d2(X).

test(false_deps) :-
    cleanup([d1/1,d2/1,d3/1]),
    expect(X, p(X), []),
    assert(d1(1)),
    assert(d2(2)),
    assert(d3(3)),
    expect(X, p(X), [1,2,3]).
"""),
    ("lz11", "begin_tests(tabling_monotonic_lazy_11)", raw"""
:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(debug)).
:- use_module(library(tables)).
:- use_module(library(prolog_code)).
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
:- dynamic d/1 as monotonic.
:- table p/1 as (monotonic, lazy).

p(X) :- d(X).

test(rollback) :-
    cleanup([d/1]),
    expect(X, p(X), []),
    \+ transaction(
           ( assert(d(a)),
             expect(X, p(X), [a]),
             fail
           )),
    expect(X, p(X), []).
"""),
    ("lz12", "begin_tests(tabling_monotonic_lazy_12)", raw"""
:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(debug)).
:- use_module(library(tables)).
:- use_module(library(prolog_code)).
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
:- dynamic d/1 as monotonic.
:- table (p/1,q/1) as (monotonic,lazy).

p(X) :-
    q(X).

q(X) :-
    d(X).

test(indirect) :-
    cleanup([d/1]),
    expect(X, q(X), []),
    assert(d(1)),
    expect(X, p(X), [1]).
"""),
    ("lz13", "begin_tests(tabling_monotonic_lazy_13)", raw"""
:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(debug)).
:- use_module(library(tables)).
:- use_module(library(prolog_code)).
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
:- table p/1 as (monotonic,lazy).

p(X) :- d(X).
d(X) :- data(X).

test(incr_propagate_lazy) :-
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
    ("lz14", "begin_tests(tabling_monotonic_lazy_14)", raw"""
:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(debug)).
:- use_module(library(tables)).
:- use_module(library(prolog_code)).
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
% Test completion on lazy monotonic tables when there are
% cyclic dependencies.

:- dynamic (d/2) as monotonic.
:- table (p/2) as (monotonic,lazy).

p(X, Y) :-
    d(X, Y).
p(X, Y) :-
    d(X, M),
    p(M, Y).

test(mono_completion, fail) :-
    cleanup([d/2]),
    assert(d(a, b)),
    init(p(a,c)),
    assert(d(b, a)),
    p(a,c).
"""),
    ("lz16", "begin_tests(tabling_monotonic_lazy_16)", raw"""
:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(debug)).
:- use_module(library(tables)).
:- use_module(library(prolog_code)).
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
/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
Problem:

  - Lazy reevaluation creates a fresh table that depends on an
    invalid lazy table because:
    - The dependency gets to complete_or_invalid_status()
    - As our dependency is lazy and we are in_assert_propagation
      our table is considered complete.
    - The new table is created from the old (invalid) data and
      marked as complete and valid.
      - The table is NOT valid!
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - */

:- table (p/1,q/1,r/1) as (monotonic,lazy).
:- dynamic d/1 as monotonic.

p(X) :-
    d(1),
    q(X).
p(X) :-
    d(11),
    asserta(d(12)),
    r(X).

r(X) :-
    q(X).

q(X) :-
    d(X),
    X < 10.

test(reeval) :-
    cleanup([d/1]),
    asserta(d(1)),
    init(p(_)),
    asserta(d(11)),
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
    ("z01", "lz1", "setup_call_cleanup(true, pu_lz1:test(simple, _), pu_lz1:cleanup([d/1]))"),
    ("z02", "lz1", "setup_call_cleanup(true, pu_lz1:test(retract, _), pu_lz1:cleanup([d/1]))"),
    ("z03", "lz2", "setup_call_cleanup(true, pu_lz2:test(mon_and_lazy, _), pu_lz2:cleanup([d/1]))"),
    ("z04", "lz3", "pu_lz3:test(intermediate)"),
    ("z05", "lz4", "pu_lz4:test(lazy_on_eager)"),
    ("z06", "lz5", "pu_lz5:test(lazy_on_eager)"),
    ("z07", "lz5", "pu_lz5:test(lazy_on_eager_retract)"),
    ("z08", "lz6", "pu_lz6:test(lazy_reeval)"),
    ("z09", "lz7", "pu_lz7:test(lazy_reeval)"),
    ("z10", "lz8", "pu_lz8:test(indirect_lazy_retract)"),
    ("z11", "lz9", "pu_lz9:test(capture_new_dependencies)"),
    ("z12", "lz10", "pu_lz10:test(false_deps)"),
    ("z13", "lz11", "pu_lz11:test(rollback)"),
    ("z14", "lz12", "pu_lz12:test(indirect)"),
    ("z15", "lz13", "pu_lz13:test(incr_propagate_lazy)"),
    ("z16", "lz14", "\+ pu_lz14:test(mono_completion)"),
    ("z18", "lz16", "pu_lz16:test(reeval)"),
]

const _TT_PINNED = [
    "ok",
    "t_z01 c[116,95,122,48,49]/1(a[111,107])",
    "t_z02 c[116,95,122,48,50]/1(a[111,107])",
    "t_z03 c[116,95,122,48,51]/1(a[111,107])",
    "t_z04 c[116,95,122,48,52]/1(a[111,107])",
    "t_z05 c[116,95,122,48,53]/1(a[111,107])",
    "t_z06 c[116,95,122,48,54]/1(a[111,107])",
    "t_z07 c[116,95,122,48,55]/1(a[111,107])",
    "t_z08 c[116,95,122,48,56]/1(a[111,107])",
    "t_z09 c[116,95,122,48,57]/1(a[111,107])",
    "t_z10 c[116,95,122,49,48]/1(a[111,107])",
    "t_z11 c[116,95,122,49,49]/1(a[111,107])",
    "t_z12 c[116,95,122,49,50]/1(a[111,107])",
    "t_z13 c[116,95,122,49,51]/1(a[111,107])",
    "t_z14 c[116,95,122,49,52]/1(a[111,107])",
    "t_z15 c[116,95,122,49,53]/1(a[111,107])",
    "t_z16 c[116,95,122,49,54]/1(a[111,107])",
    "t_z18 c[116,95,122,49,56]/1(a[111,107])",
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

@testset "upstream test_monotonic_lazy.pl: the kernel answers every row as swipl does" begin
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
