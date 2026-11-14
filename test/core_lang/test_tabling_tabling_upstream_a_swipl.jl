# ORIGINAL: the UPSTREAM tests/tabling/test_tabling.pl (swipl-devel 18168e62, 10.1.20), units 1..12 of 36 (tabling_ex1, tabling_ex2, tabling_ex3, tabling_ex4, tabling_ex5, tabling_ex6, tabling_ex7, tabling_ex8, tabling_ex9a, tabling_ex9b, tabling_ex9c, tabling_ex9d),
# as kernel rows (TAB1, TABTEST-A). One row `t_<id>(R)` per upstream test: `abolish_all_tables, <unit>:test(<name>), abolish_all_tables`
# (the unit's `cleanup(abolish_all_tables)` option and test_tabling/0's first call folded by hand), R = ok / failed / raised(E).
#   * Comments matching the D-0164 terms are elided from the embedded text; no code differs.
#   * The unit text is upstream's, verbatim, between `begin_tests` and `end_tests`, plus the file's common tail (before/0, between/0,
#     feedback, end, has_trie_attvar_support); each unit is its own module `pu_<unit>` (plunit gives each unit a module) that uses the
#     pin's helper library test/core_lang/tabling_testlib_upstream.pl (tests/tabling/tabling_testlib.pl, verbatim) as `tabling_testlib`.
#   * Every pinned line is swipl's (swipl 10.1.20, two identical runs, evidence/TAB1/tabgap_tools/pins_a.txt, which also holds the plunit
#     run of the same units) AND equals the answer plunit expects (`_TT_UPSTREAM`: each test passes, so `ok`).
#   * DIVERGES from the file: plunit is not used (`pu_<unit>:test(Name)` is called directly), the unit modules are `pu_<unit>` not `plunit_<unit>`.
#   * A row whose program the kernel refuses stays a row pinned on swipl (the pin is not weakened); none is known for these units.
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

"The pin's helper library, verbatim (tests/tabling/tabling_testlib.pl)."
const _TT_TESTLIB = joinpath(@__DIR__, "tabling_testlib_upstream.pl")

"The units' text, verbatim between begin_tests and end_tests: `(short name, begin_tests directive, text)`."
const _TT_UNITS = [
    ("ex1", ":- begin_tests(tabling_ex1, [cleanup(abolish_all_tables)]).", raw"""

expected_variants([a(2,_),a(3,_),a(_,_)]).
% Note: a(3,_) is an empty table, but it is there...
expected_answers_for_variant(a(_,_),[a(1,2),a(2,3),a(1,3)]).
expected_answers_for_variant(a(2,_),[a(2,3)]).
expected_answers_for_variant(a(3,_),[]).

a_expected_answers([1-2,2-3,1-3]).

a_compare_answers :-
  compare_real_expected_answers(a,2,a_expected_answers),
  test_expected_variants_present,
  test_answers_expected_tables.

:- table a/2.

a(X,Y) :- before, a(X,Z), between, a(Z,Y).
a(X,Y) :- e(X,Y).

e(1,2).
e(2,3).

test(ex1) :-
	a_compare_answers.

"""),
    ("ex2", ":- begin_tests(tabling_ex2, [cleanup(abolish_all_tables)]).", raw"""
% Meerdere recursieve calls met zelfde callpattern:
% b(X,Y) :- b(X,Z), b(Q,Y).
% For two given facts e(1,2) and e(2,3), there are four (!) solutions to b(X,Y):
% 1,2
% 2,3
% 1,3
% 2,2

expected_variants([b(_,_)]).
expected_answers_for_variant(b(_,_),[b(1,2),b(2,3),b(1,3),b(2,2)]).

% The answers we expect for example 2, returned as a list with entries of the form X-Y. The order does not matter.
b_expected_answers([1-2,2-3,1-3,2-2]).

% TEST: Tests answers of example 2.
b_compare_answers :-
  compare_real_expected_answers(b,2,b_expected_answers).

go :-
  once(b(_X,_Y)).

:- table b/2.

b(X,Y) :- before, b(X,_Z), between, b(_Q,Y).
b(X,Y) :- e(X,Y).

% Test facts
e(1,2).
e(2,3).

test(ex2) :-
	b_compare_answers,
	test_expected_variants_present,
	test_answers_expected_tables.

"""),
    ("ex3", ":- begin_tests(tabling_ex3, [cleanup(abolish_all_tables)]).", raw"""
% Answers: all integers between -10 and 10 (included).
%
% Consider the execution of the query {\tt ?- p$_g$(Y).} which
% succeeds for all integers between {\tt -10} and {\tt 10} (included)
% against the following tabled program:
% :- table p/1. \\
% p(X) :- p$_{c_1}$(Y), 0 =< Y, Y < 10, X is -Y - 1.  \\
% p(X) :- p$_{c_2}$(Y), -10 < Y, Y =< 0, X is -Y + 1. \\
% p(0).
% The two consumers that are encountered have been given an index for
% ease of reference.  The abstract machine needs to alternate between
% consumers {\tt p$_{c_1}$(Y)} and {\tt p$_{c_2}$(Y)} multiple times
% before all answers have been generated.

expected_variants([c(_)]).
expected_answers_for_variant(c(_),L) :-
  findall(c(X),between(-10,10,X),L).

c_expected_answers(L) :-
  findall(X,between(-10,10,X),L).

c_compare_answers :-
  compare_real_expected_answers(c,1,c_expected_answers).

:- table c/1.

c(X) :- before(1), c(Y), feedback('after recusive 1: Y is ~w, and X is ~w',[Y,X]),
	0 =< Y, Y < 10, X is -Y-1, end(1).
c(X) :- before(2), c(Y), feedback('after recusive 2: Y is ~w, and X is ~w',[Y,X]),
	-10 < Y, Y =< 0, X is -Y+1, end(2).
c(0).

test(ex3) :-
	c_compare_answers,
	test_expected_variants_present,
	test_answers_expected_tables.

"""),
    ("ex4", ":- begin_tests(tabling_ex4, [cleanup(abolish_all_tables)]).", raw"""
% Two mutually recursive predicates:
% d(X) :- e(Y), Y < 5, X is Y + 1.
% d(0).
%
% e(X) :- d(Y), Y < 5, X is Y + 1.
% e(0).

expected_variants([d(_), e(_)]).
expected_answers_for_variant(d(_),L) :-
  findall(d(X),between(0,5,X),L).
expected_answers_for_variant(e(_),L) :-
  findall(e(X),between(0,5,X),L).

de_expected_answers(L) :-
  findall(X,between(0,5,X),L).

:- table d/1, e/1.

d(X) :-
	feedback('d/1: before calling e(Y)'),
	e(Y),
	feedback('d/1: after calling e(Y)'),
	feedback('d/1: Y is ~w~n',[Y]),
	Y < 5,
	feedback('d/1: Y < 5 OK\n'),
	(   X is Y + 1
	->  feedback('d/1: is OK\n')
	;   feedback('d/1: ~w is ~w + 1 NOT ok\n',[X,Y])
	),
	feedback('d/1: X is ~w~n', [X]).
d(0).

e(X) :-
	feedback('e/1: before calling d(Y)'),
	d(Y),
	feedback('e/1: after calling d(Y)'),
	feedback('e/1: Y is ~w~n',[Y]),
	Y < 5,
	feedback('e/1: Y < 5 OK\n', []),
	(   X is Y + 1
	->  feedback('e/1: is OK\n',[])
	;   feedback('e/1: ~w is ~w + 1 NOT ok\n',[X,Y])
	),
	feedback('e/1: X is ~w~n',[X]).
e(0).

test(ex4) :-
  compare_real_expected_answers(d,1,de_expected_answers),
  compare_real_expected_answers(e,1,de_expected_answers),
  test_expected_variants_present,
  test_answers_expected_tables.

"""),
    ("ex5", ":- begin_tests(tabling_ex5, [cleanup(abolish_all_tables)]).", raw"""
% Variation on example 1 but with a  cycle. This is an important example
% for tabling.

expected_variants([f(1,_),f(2,_),f(3,_),f(_,_)]).
expected_answers_for_variant(f(_,_),L) :-
  findall(f(X,Y),(between(1,3,X),between(1,3,Y)),L).
expected_answers_for_variant(f(1,_),L) :-
  findall(f(1,X),between(1,3,X),L).
expected_answers_for_variant(f(2,_),L) :-
  findall(f(2,X),between(1,3,X),L).
expected_answers_for_variant(f(3,_),L) :-
  findall(f(3,X),between(1,3,X),L).

% The answers we expect for example 5,   returned as a list with entries
% of the form X-Y. The order does not matter. We expect nine answers.
f_expected_answers([1-1,1-2,1-3,2-1,2-2,2-3,3-1,3-2,3-3]).

:- table f/2.

f(X,Y) :- before, f(X,Z), between, f(Z,Y).
f(X,Y) :- e2(X,Y).

e2(1,2).
e2(2,3).
e2(3,1).

test(ex5) :-
	findall(_,f(_,_),_),
	compare_real_expected_answers(f,2,f_expected_answers),
	test_expected_variants_present,
	test_answers_expected_tables.

"""),
    ("ex6", ":- begin_tests(tabling_ex6, [cleanup(abolish_all_tables)]).", raw"""
% Nested tabling: a tabled predicate calls another tabled predicate, but not mutually recursive.
% g(X) <- h(Y), X is Y + 1.
%
% h(X) <- h(Y), X is Y + 1, X < 5.
% h(0).

expected_variants([g(_),h(_)]).
expected_answers_for_variant(g(_),L) :-
  findall(g(X),between(1,5,X),L).
expected_answers_for_variant(h(_),L) :-
  findall(h(X),between(0,4,X),L).

g_expected_answers([1,2,3,4,5]).
h_expected_answers([0,1,2,3,4]).

:- table g/1, h/1.

g(X) :-
	feedback('g_aux: before calling h(Y)'),
	h(Y),
	feedback('g_aux: after calling h(Y)'),
	X is Y + 1.

h(X) :-
	feedback('h_aux: before calling h(Y)'),
	h(Y),
	feedback('h_aux: after calling h(Y)'),
	X is Y + 1,
	X < 5.
h(0).

test(ex6) :-
	compare_real_expected_answers(g,1,g_expected_answers),
	compare_real_expected_answers(h,1,h_expected_answers),
	test_expected_variants_present,
	test_answers_expected_tables.

"""),
    ("ex7", ":- begin_tests(tabling_ex7, [cleanup(abolish_all_tables)]).", raw"""
% A more complicated graph example:
%
%       i1
%       |
%    +--+---+
%    |      |
%    v      v
%    i2     i3
%    |
% +--+---+
% |      |
% v      v
% i4 --> i5
%
% i1(X) :- i2(Y), X is Y + 1.
% i1(X) :- i3(Y), X is Y + 1.
%
% i2(X) :- i4(Y), X is Y + 1.
% i2(X) :- i5(Y), X is Y + 4. % !! + 4
%
% i4(X) :- i5(Y), X is Y + 1. % !! TABLE table7d
%
% i3(X) :- between(0,1,X). % !! TABLE table7c
%
% i5(Y) :- between(2,3,X).

expected_variants([i1(_),i2(_),i3(_),i4(_),i5(_)]).
expected_answers_for_variant(i1(_),[i1(5),i1(6),i1(7),i1(8),i1(1),i1(2)]).
expected_answers_for_variant(i2(_),[i2(4),i2(5),i2(6),i2(7)]).
expected_answers_for_variant(i3(_),[i3(0),i3(1)]).
expected_answers_for_variant(i4(_),[i4(3),i4(4)]).
expected_answers_for_variant(i5(_),[i5(2),i5(3)]).

i1_expected_answers([5,6,7,8,1,2]).
i2_expected_answers([4,5,6,7]).
i3_expected_answers([0,1]).
i4_expected_answers([3,4]).
i5_expected_answers([2,3]).

:- table i1/1, i2/1, i3/1, i4/1, i5/1.

i1(X) :-
	feedback('i1_aux 1: before'), i2(Y),
	feedback('i1_aux 1: after'),  X is Y + 1.
i1(X) :-
	feedback('i1_aux 2: before'), i3(Y),
	feedback('i1_aux 2: after'),  X is Y + 1.
i2(X) :-
	feedback('i2_aux 1: before'), i4(Y),
	feedback('i2_aux 1: after'),  X is Y + 1.
i2(X) :-
	feedback('i2_aux 2: before'), i5(Y),
	feedback('i2_aux 2: after'),  X is Y + 4.
i4(X) :-
	feedback('i4_aux 1: before'), i5(Y),
	feedback('i4_aux 1: after'),  X is Y + 1.
i3(X) :- between(0,1,X).
i5(X) :- between(2,3,X).

test(ex7) :-
	compare_real_expected_answers(i1,1,i1_expected_answers),
	compare_real_expected_answers(i2,1,i2_expected_answers),
	compare_real_expected_answers(i3,1,i3_expected_answers),
	compare_real_expected_answers(i4,1,i4_expected_answers),
	compare_real_expected_answers(i5,1,i5_expected_answers),
	test_expected_variants_present,
	test_answers_expected_tables.

"""),
    ("ex8", ":- begin_tests(tabling_ex8, [cleanup(abolish_all_tables)]).", raw"""
% Example specifically designed  to  test  whether   we  can  get  a new
% continuation in the last iteration of  run_contins. This is indeed the
% case. Thus in run_contins we  also  need   to  look  at  the number of
% continuations to determine whether we can   stop.  However we had some
% questions: we might need to look  whether   the  new continuation is a
% variant of a continuation that is   already present (to avoid infinite
% loops).
%
% j(a,b).
% j(X,Y) :- j(_,_), j(Y,X).

expected_variants([j(_,_)]).
expected_answers_for_variant(j(_,_),[j(a,b),j(b,a)]).
j_expected_answers([a-b,b-a]).

:- table j/2.

j(a,b) :-
	feedback('j 1: give answer'). % TODO: check why we don*t have to save this answer here explicitly.
j(X,Y) :-
	feedback('j 2: before'),
	j(_,_),
	feedback('j 2: between'),
	j(Y,X),
	feedback('j 2: after').

test(ex8) :-
	compare_real_expected_answers(j,2,j_expected_answers),
	test_expected_variants_present,
	test_answers_expected_tables.

"""),
    ("ex9a", ":- begin_tests(tabling_ex9a, [cleanup(abolish_all_tables)]).", raw"""
% The reachability predicate can be written in several variants.
% Example 1: a
% p(X,Y) :- p(X,Z), p(Z,Y).
% p(X,Y) :- e(X,Y).
%
% Example 9a:
% p(X,Y) :- p(X,Z), e(Z,Y).
% p(X,Y) :- e(X,Y).
%
% Example 9b:
% p(X,Y) :- e(X,Z), p(Z,Y).
% p(X,Y) :- e(X,Y).
%
% Example 9c:
% p(X,Y) :- e(X,Y).
% p(X,Y) :- p(X,Z), p(Z,Y).
%
% Example 9d:
% p(X,Y) :- e(X,Y).
% p(X,Y) :- p(X,Z), e(Z,Y).
%
% Example 9e:
% p(X,Y) :- e(X,Y).
% p(X,Y) :- e(X,Z), p(Z,Y).

expected_variants([a(_,_)]).
expected_answers_for_variant(a(_,_),[a(1,2),a(2,3),a(1,3)]).

% The answers we expect for reachability   variants,  returned as a list
% with entries of the form X-Y. The order does not matter.

reachability_expected_answers([1-2,2-3,1-3]).

:- table a/2.

a(X,Y) :-
	feedback('before'),
	a(X,Z),
	feedback('between: prove ~w~n',[e(Z,Y)]),
	e(Z,Y).
a(X,Y) :-
	e(X,Y).

% Test facts for examples 1 and 2.
e(1,2).
e(2,3).

test(ex9a) :-
	compare_real_expected_answers(a,2,reachability_expected_answers),
	test_expected_variants_present,
	test_answers_expected_tables.
"""),
    ("ex9b", ":- begin_tests(tabling_ex9b, [cleanup(abolish_all_tables)]).", raw"""
expected_variants([a(3,_),a(2,_),a(_,_)]).
% Note: a(3,_) is an empty table, but it is there...
expected_answers_for_variant(a(_,_),[a(1,2),a(2,3),a(1,3)]).
expected_answers_for_variant(a(3,_),[]).
expected_answers_for_variant(a(2,_),[a(2,3)]).
reachability_expected_answers([1-2,2-3,1-3]).

:- table a/2.

a(X,Y) :-
	feedback('before'),
	e(X,Z),
	feedback('between: prove ~w~n',[a(Z,Y)]),
	a(Z,Y).
a(X,Y) :-
	e(X,Y).

e(1,2).
e(2,3).

test(ex9b) :-
	compare_real_expected_answers(a,2,reachability_expected_answers),
	test_expected_variants_present,
	test_answers_expected_tables.

"""),
    ("ex9c", ":- begin_tests(tabling_ex9c, [cleanup(abolish_all_tables)]).", raw"""
expected_variants([a(2,_),a(3,_),a(_,_)]).
% Note: a(3,_) is an empty table, but it is there...
expected_answers_for_variant(a(_,_),[a(1,2),a(2,3),a(1,3)]).
expected_answers_for_variant(a(2,_),[a(2,3)]).
expected_answers_for_variant(a(3,_),[]).

reachability_expected_answers([1-2,2-3,1-3]).

:- table a/2.

a(X,Y) :- e(X,Y).
a(X,Y) :- feedback('before'), a(X,Z), feedback('between'),  a(Z,Y).

e(1,2).
e(2,3).

test(ex9c) :-
	compare_real_expected_answers(a,2,reachability_expected_answers),
	test_expected_variants_present,
	test_answers_expected_tables.

"""),
    ("ex9d", ":- begin_tests(tabling_ex9d, [cleanup(abolish_all_tables)]).", raw"""
expected_variants([a(_,_)]).
expected_answers_for_variant(a(_,_),[a(1,2),a(2,3),a(1,3)]).

reachability_expected_answers([1-2,2-3,1-3]).

:- table a/2.

a(X,Y) :- e(X,Y).
a(X,Y) :- feedback('before'), a(X,Z), feedback('between'),  e(Z,Y).

e(1,2).
e(2,3).

test(ex9d) :-
	compare_real_expected_answers(a,2,reachability_expected_answers),
	test_expected_variants_present,
	test_answers_expected_tables.

"""),
]

"The file's common tail (lines `before :- ...` to the end), verbatim."
const _TT_TAIL = raw"""
before    :- debug(tabling, 'before',  []).
before(I) :- debug(tabling, 'before ~w',  [I]).
between   :- debug(tabling, 'between', []).
feedback(Fmt) :- debug(tabling, Fmt, []).
feedback(Fmt,Args) :- debug(tabling, Fmt, Args).
end       :- debug(tabling, 'end',   []).
end(I)    :- debug(tabling, 'end ~w',   [I]).

has_trie_attvar_support :-
    trie_new(T),
    put_attr(X, x, t),
    catch(trie_insert(T, f(X)),
          error(type_error(free_of_attvar, _),_),
          fail).
"""

"The rows: `(id, unit, goal)`; the goal is the plunit test with its options folded by hand."
const _TT_CASES = [
    ("tt01", "ex1", "pu_ex1:test(ex1)"),
    ("tt02", "ex2", "pu_ex2:test(ex2)"),
    ("tt03", "ex3", "pu_ex3:test(ex3)"),
    ("tt04", "ex4", "pu_ex4:test(ex4)"),
    ("tt05", "ex5", "pu_ex5:test(ex5)"),
    ("tt06", "ex6", "pu_ex6:test(ex6)"),
    ("tt07", "ex7", "pu_ex7:test(ex7)"),
    ("tt08", "ex8", "pu_ex8:test(ex8)"),
    ("tt09", "ex9a", "pu_ex9a:test(ex9a)"),
    ("tt10", "ex9b", "pu_ex9b:test(ex9b)"),
    ("tt11", "ex9c", "pu_ex9c:test(ex9c)"),
    ("tt12", "ex9d", "pu_ex9d:test(ex9d)"),
]

const _TT_PINNED = [
    "ok",
    "t_tt01 c[116,95,116,116,48,49]/1(a[111,107])",
    "t_tt02 c[116,95,116,116,48,50]/1(a[111,107])",
    "t_tt03 c[116,95,116,116,48,51]/1(a[111,107])",
    "t_tt04 c[116,95,116,116,48,52]/1(a[111,107])",
    "t_tt05 c[116,95,116,116,48,53]/1(a[111,107])",
    "t_tt06 c[116,95,116,116,48,54]/1(a[111,107])",
    "t_tt07 c[116,95,116,116,48,55]/1(a[111,107])",
    "t_tt08 c[116,95,116,116,48,56]/1(a[111,107])",
    "t_tt09 c[116,95,116,116,48,57]/1(a[111,107])",
    "t_tt10 c[116,95,116,116,49,48]/1(a[111,107])",
    "t_tt11 c[116,95,116,116,49,49]/1(a[111,107])",
    "t_tt12 c[116,95,116,116,49,50]/1(a[111,107])",
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
]

"The files of the program in a fresh directory: testlib, one module file per unit, the main file with the rows; returns the main file."
function _tt_materialize()::String
    d = realpath(mktempdir())
    cp(_TT_TESTLIB, joinpath(d, "tabling_testlib.pl"))
    for (short, _, text) in _TT_UNITS
        write(
            joinpath(d, "pu_$short.pl"),
            ":- module(pu_$short, []).\n:- use_module('$d/tabling_testlib').\n" * text * "\n" * _TT_TAIL
        )
    end
    main = join([":- use_module('$d/pu_$short').\n" for (short, _, _) in _TT_UNITS])
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

@testset "upstream test_tabling.pl units 1..12: the kernel answers every row as swipl does" begin
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
