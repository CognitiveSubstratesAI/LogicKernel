# ORIGINAL: the UPSTREAM tests/tabling/test_tabling.pl (swipl-devel 18168e62, 10.1.20), units 13..25 of 36 (tabling_ex9e, tabling_ex10, tabling_ex11, tabling_ex12, tabling_ex13, tabling_ex14, tabling_ex15, tabling_ex16, tabling_ex17, tabling_clpfd, tabling_eruption, tabling_eruption2, tabling_sneezing),
# as kernel rows (TAB1, TABTEST-B). One row `t_<id>(R)` per upstream test: `abolish_all_tables, <unit>:test(<name>), abolish_all_tables`
# (the unit's `cleanup(abolish_all_tables)` option and test_tabling/0's first call folded by hand), R = ok / failed / raised(E).
#   * Comments matching the D-0164 terms are elided from the embedded text; no code differs.
#   * The unit text is upstream's, verbatim, between `begin_tests` and `end_tests`, plus the file's common tail (before/0, between/0,
#     feedback, end, has_trie_attvar_support); each unit is its own module `pu_<unit>` (plunit gives each unit a module) that uses the
#     pin's helper library test/core_lang/tabling_testlib_upstream.pl (tests/tabling/tabling_testlib.pl, verbatim) as `tabling_testlib`.
#   * Every pinned line is swipl's (swipl 10.1.20, two identical runs, evidence/TAB1/tabgap_tools/pins_b.txt, which also holds the plunit
#     run of the same units) AND equals the answer plunit expects (`_TT_UPSTREAM`: each test passes, so `ok`).
#   * DIVERGES from the file: plunit is not used (`pu_<unit>:test(Name)` is called directly), the unit modules are `pu_<unit>` not `plunit_<unit>`.
#   * A row whose program the kernel refuses stays a row pinned on swipl (the pin is not weakened); expected refusals (by reading, unverified): clpfd (needs library(clpfd) and attributed variables in tries); sneezing (compares a float with =:=).
#   * Rows with plunit options folded by hand (ROW_FOLD in gen_tabling.py, from the unit text): tabling_clpfd, tabling_eruption, tabling_eruption2, tabling_sneezing: `Var op Val` options as once(Goal) then the check, `set(T == L)` as findall + sort + compare, `nondet` dropped; tabling_clpfd's two conditional tests as one if-then-else row.
#   * UNVERIFIED on the kernel (nothing was compiled when these rows were written): every kernel answer; the gate decides.
# elided: unit tabling_ex16, upstream line 865, reason: matches the D-0164 term list

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
    ("ex9e", ":- begin_tests(tabling_ex9e, [cleanup(abolish_all_tables)]).", raw"""
expected_variants([a(3,_),a(2,_),a(_,_)]).
% Note: a(3,_) is an empty table, but it is there
expected_answers_for_variant(a(_,_),[a(1,2),a(2,3),a(1,3)]).
expected_answers_for_variant(a(3,_),[]).
expected_answers_for_variant(a(2,_),[a(2,3)]).

reachability_expected_answers([1-2,2-3,1-3]).

:- table a/2.

a(X,Y) :- e(X,Y).
a(X,Y) :- feedback('before'), e(X,Z), feedback('between'),  a(Z,Y).

e(1,2).
e(2,3).

test(ex9d) :-
	compare_real_expected_answers(a,2,reachability_expected_answers),
	test_expected_variants_present,
	test_answers_expected_tables.

"""),
    ("ex10", ":- begin_tests(tabling_ex10, [cleanup(abolish_all_tables)]).", raw"""
%d(X) <- e(Y), Y < 5, X is Y + 1.  % Will never run, because e doesn't have any facts
%d(X) <- d(Y), Y < 20, X is Y + 5. % Should run
%d(0).
%e(X) <- d(Y), Y < 5, X is Y + 1.
%% No facts for e

expected_variants([d(_),e(_)]).
expected_answers_for_variant(d(_),[d(0),d(2),d(4),d(5),d(7),d(9),
				   d(10),d(12),d(14),d(15),d(17),d(19),
				   d(20),d(22),d(24)]).
expected_answers_for_variant(e(_),[e(5),e(3),e(1)]).

d_expected_answers([0,2,4,5,7,9,10,12,14,15,17,19,20,22,24]).
e_expected_answers([5,3,1]).

:- table d/1, e/1.

d(X) :- e(Y), Y < 5, X is Y + 1.  % Will never run, because e doesn't have any facts (initially)
d(X) :- d(Y), Y < 20, X is Y + 5. % Should run
d(0).
e(X) :- d(Y), Y < 5, X is Y + 1.
% No facts for e

test(ex10) :-
	compare_real_expected_answers(d,1,d_expected_answers),
	compare_real_expected_answers(e,1,e_expected_answers),
	test_expected_variants_present,
	test_answers_expected_tables.

"""),
    ("ex11", ":- begin_tests(tabling_ex11, [cleanup(abolish_all_tables)]).", raw"""
% Expected answers:
% d(0), d(2), d(4)
% e(1), e(3), e(5)

expected_variants([d(_),e(_)]).
expected_answers_for_variant(d(_),[d(0),d(2),d(4)]).
expected_answers_for_variant(e(_),[e(1),e(3),e(5)]).

d_expected_answers([0,2,4]).
e_expected_answers([1,3,5]).

:- table d/1, e/1.

d(X) :- e(Y), Y < 5, X is Y + 1.
d(0).
e(X) :- d(Y), Y < 5, X is Y + 1.
% No facts for e

test(ex11) :-
	compare_real_expected_answers(d,1,d_expected_answers),
	compare_real_expected_answers(e,1,e_expected_answers),
	test_expected_variants_present,
	test_answers_expected_tables.

"""),
    ("ex12", ":- begin_tests(tabling_ex12, [cleanup(abolish_all_tables)]).", raw"""
expected_variants([f(4),f(3),f(2),f(0),f(1),e(_),d(_),f(_)]).
% Note: f(4) and f(0) are empty tables, but they are there...
expected_answers_for_variant(d(_),L) :-
  findall(d(X),between(0,4,X),L).
expected_answers_for_variant(f(4),[]).
expected_answers_for_variant(f(3),[f(3)]).
expected_answers_for_variant(f(2),[f(2)]).
expected_answers_for_variant(f(0),[]).
expected_answers_for_variant(f(1),[f(1)]).
expected_answers_for_variant(e(_),L) :-
  findall(e(X),between(0,3,X),L).
expected_answers_for_variant(f(_),L) :-	% JW: Added
  findall(f(X),between(1,3,X),L).

d_expected_answers([0,1,2,3,4]).
e_expected_answers([0,1,2,3]).
f_expected_answers([1,2,3]).

:- table d/1, e/1, f/1.

% Something like:
d(X) :- e(Y), feedback('d_aux: after e(Y): ~w\n',[e(Y)]), X is Y + 1, X < 5.
d(0).
% Number of predicates involved in mutual recursion will increase at runtime
e(X) :- d(X), f(X),
	feedback('e_aux: at end of clause; head is now ~w\n',[e_aux(X)]).
e(0) :- feedback('using fact e(0)\n',[]).
f(X) :- e(Y), X is Y + 1, X < 4.

test(ex12) :-
	compare_real_expected_answers(d,1,d_expected_answers),
	compare_real_expected_answers(e,1,e_expected_answers),
	compare_real_expected_answers(f,1,f_expected_answers),
	test_expected_variants_present,
	test_answers_expected_tables.

"""),
    ("ex13", ":- begin_tests(tabling_ex13, [cleanup(abolish_all_tables)]).", raw"""
expected_variants([p(2,_),p(1,_),p(_,_)]).
expected_answers_for_variant(p(_,_),L) :-
  findall(p(X,Y),(between(1,2,X),between(1,2,Y)),L).
expected_answers_for_variant(p(2,_),L) :-
  findall(p(2,X),between(1,2,X),L).
expected_answers_for_variant(p(1,_),L) :-
  findall(p(1,X),between(1,2,X),L).

% The answers we expect for example 13, returned as a list with entries of the form X-Y. The order does not matter.
% We expect four answers.
p_expected_answers([1-2,2-1,1-1,2-2]).

:- table p/2.

p(X,Y) :-
	feedback('before'), p(X,Z), feedback('between'), p(Z,Y).
p(X,Y) :- e2(X,Y).

e2(1,2).
e2(2,1).

test(ex12) :-
	compare_real_expected_answers(p,2,p_expected_answers),
	test_expected_variants_present,
	test_answers_expected_tables.

"""),
    ("ex14", ":- begin_tests(tabling_ex14, [cleanup(abolish_all_tables)]).", raw"""
% Simpler example than example12.pl, but the number of predicates involved in mutual recursion will also increase at runtime.

expected_variants([p(3,_),p(2,_),q(2,_),q(3,_),p(_,_),q(_,_)]).
% Note: p(3,_) and q(3,_) are empty tables, but they are there.
expected_answers_for_variant(p(_,_),[p(1,2),p(2,3),p(1,3)]).
expected_answers_for_variant(p(3,_),[]).
expected_answers_for_variant(p(2,_),[p(2,3)]).
expected_answers_for_variant(q(_,_),[q(1,2),q(1,3),q(2,3)]).
expected_answers_for_variant(q(2,_),[q(2,3)]).
expected_answers_for_variant(q(3,_),[]).

p_expected_answers([1-2,2-3,1-3]).
q_expected_answers([1-2,1-3,2-3]).	% JW: added

go :-
  once(p(_X,_Y)).

:- table p/2, q/2.

p(X,Y) :- p(X,Z), q(Z,Y).
p(X,Y) :- e(X,Y).
q(X,Y) :- p(X,Y).

e(1,2).
e(2,3).

test(ex14) :-
	compare_real_expected_answers(p,2,p_expected_answers),
	compare_real_expected_answers(q,2,q_expected_answers),
	test_expected_variants_present,
	test_answers_expected_tables.

"""),
    ("ex15", ":- begin_tests(tabling_ex15, [cleanup(abolish_all_tables)]).", raw"""
% Example designed to test whether the true   in fresh status works fine
% in case only a continuation is saved. See issue 55.

expected_variants([d(_),e(_)]).
expected_answers_for_variant(d(_),L) :-
  findall(d(X),between(0,5,X),L).
expected_answers_for_variant(e(_),L) :-
  findall(e(X),between(0,5,X),L).

d_expected_answers([0,1,2,3,4,5]).
e_expected_answers([0,1,2,3,4,5]).

:- table d/1, e/1.

d(X) :- e(Y), Y < 5, X is Y + 1.
d(0).
e(X) :- d(Y), e(_), Y < 5, X is Y + 1.
e(0).

test(ex15) :-
	compare_real_expected_answers(d,1,d_expected_answers),
	compare_real_expected_answers(e,1,e_expected_answers),
	test_expected_variants_present,
	test_answers_expected_tables.

"""),
    ("ex16", ":- begin_tests(tabling_ex16, [cleanup(abolish_all_tables)]).", raw"""
% [comment elided: D-0164]

expected_variants([d(_),e(_),f(_),g(_)]).
expected_answers_for_variant(d(_),L) :-
  findall(d(X),between(0,5,X),L).
expected_answers_for_variant(e(_),L) :-
  findall(e(X),between(0,5,X),L).
expected_answers_for_variant(f(_),L) :-
  findall(f(X),between(0,5,X),L).
expected_answers_for_variant(g(_),L) :-
  findall(g(X),between(0,5,X),L).

% Two mutually recursive predicates:
% d(X) :- e(Y), Y < 5, X is Y + 1.
% d(0).
%
% e(X) :- d(Y), Y < 5, X is Y + 1.
% e(0).

:- table d/1, e/1, f/1, g/1.

d(X) :-
	feedback('d_aux: before calling e(Y)'),
	e(Y),
	feedback('d_aux: after calling e(Y)'),
	feedback('d_aux: Y is ~w~n',[Y]),
	Y < 5,
	feedback('d_aux: Y < 5 OK\n',[]),
	(   X is Y + 1
	->  feedback('d_aux: is OK\n',[])
	;   feedback('d_aux: ~w is ~w + 1 NOT ok\n',[X,Y])
	),
	feedback('d_aux: X is ~w~n',[X]).
d(0).

e(X) :-
	feedback('e_aux: before calling d(Y)'),
	d(Y),
	feedback('e_aux: after calling d(Y)'),
	feedback('e_aux: Y is ~w~n',[Y]),
	Y < 5,
	feedback('e_aux: Y < 5 OK\n', []),
	(   X is Y + 1
	->  feedback('e_aux: is OK\n',[])
	;   feedback('e_aux: ~w is ~w + 1 NOT ok\n',[X,Y])
	),
	feedback('e_aux: X is ~w~n',[X]).
e(0).

f(X) :- g(Y), Y < 5, X is Y + 1.
f(0).

g(X) :- f(Y), Y < 5, X is Y + 1.
g(0).

test(ex16) :-
	once((d(_X), f(_Y))).

"""),
    ("ex17", ":- begin_tests(tabling_ex17, [cleanup(abolish_all_tables)]).", raw"""
% Smaller version of example 10.

% Expected answers

expected_variants([d(_),e(_)]).
expected_answers_for_variant(d(_),[d(0), d(2), d(5)]).
expected_answers_for_variant(e(_),[e(1)]).

:- table d/1, e/1.

d(X) :- e(Y), Y < 2, X is Y + 1.  % Will never run, because e doesn't have any facts (initially)
d(X) :- d(Y), Y < 2 , X is Y + 5. % Should run
d(0).
e(X) :- d(Y), Y < 2, X is Y + 1.
% No facts for e

test(ex17) :-
	once(d(_)),
	test_expected_variants_present,
	test_answers_expected_tables.

"""),
    ("clpfd", ":- begin_tests(tabling_clpfd, [ cleanup(abolish_all_tables) ]).", raw"""

:- table fib/2.
:- use_module(library(clpfd)).

fib(1, 1).
fib(2, 2).
fib(N, X) :-
    N #> 2, N #< 10,              % #< 10 to ensure termination
    N1 #= N-1, N2 #= N-2,
    fib(N1, X1),
    fib(N2, X2),
    X #= X1+X2.

test(fib_error,
     [ condition(has_trie_attvar_support),
       N == 6,
       nondet
     ]) :-
	fib(N, 13).
test(fib_error,
     [ error(type_error(free_of_attvar, _)),
       condition(\+ has_trie_attvar_support)
     ]) :-
	fib(_N, 13).

"""),
    ("eruption", ":- begin_tests(tabling_eruption, [cleanup(abolish_all_tables)]).", raw"""

:- table
  eruption(lattice(prob_sum_e/3)),
  sudden_energy_release/0,
  fault_rupture(_,lattice(prob_sum_e/3)).

eruption(P)  :-
  sudden_energy_release,
  fault_rupture(_,P0),
  P is P0*0.6.
% If there is a sudden energy release under the island and there is a fault
% rupture, then there can be an eruption of the volcano on the island with
% probability 0.6

sudden_energy_release.
% The energy release occurs with certainty

fault_rupture(southwest_northeast,0.7).
fault_rupture(east_west,0.6).
% we are sure that ruptures occur

prob_sum_e(A,B,C):-
  C is 1-(1-A)*(1-B).

test(tabling_eruption, [P =:= 0.6288, nondet]) :-
	eruption(P).

"""),
    ("eruption2", ":- begin_tests(tabling_eruption2, [cleanup(abolish_all_tables)]).", raw"""

:- table
  sudden_energy_release/0,
  eruption(lattice(prob_sum_e/3)).

eruption(P)  :-
  sudden_energy_release,
  fault_rupture(_,P0),
  P is P0*0.6.
% If there is a sudden energy release under the island and there is a fault
% rupture, then there can be an eruption of the volcano on the island with
% probability 0.6

sudden_energy_release.
% The energy release occurs with certainty

fault_rupture(southwest_northeast,0.7).
fault_rupture(east_west,0.6).
% we are sure that ruptures occur

prob_sum_e(A,B,C):-
  C is 1-(1-A)*(1-B).

test(tabling_eruption, [P =:= 0.6288, nondet]) :-
	eruption(P).

"""),
    ("sneezing", ":- begin_tests(tabling_sneezing, [cleanup(abolish_all_tables)]).", raw"""

:- table
    sneezing(_,lattice(prob_sum)),
    flu(_,lattice(prob_sum)),
    hay_fever(_,lattice(prob_sum)).

sneezing(X,P) :- flu(X,P0), P is P0*0.3.
% if X has the flu, there is a probability of 0.3 that he sneezes

sneezing(X,P) :- hay_fever(X,P0), P is P0*0.2.
% if X has hay fever, there is a probability of 0.2 that he sneezes

flu(bob,0.2).
% bob has the flu with prob 0.2

hay_fever(bob,0.4).
% bob has hay fever with prob 0.4

prob_sum(A,B,C):-
  C is 1-(1-A)*(1-B).

test(tabling_sneezing, P =:= 0.1352000000000001) :-
	sneezing(bob, P).

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
    ("tt13", "ex9e", "pu_ex9e:test(ex9d)"),
    ("tt14", "ex10", "pu_ex10:test(ex10)"),
    ("tt15", "ex11", "pu_ex11:test(ex11)"),
    ("tt16", "ex12", "pu_ex12:test(ex12)"),
    ("tt17", "ex13", "pu_ex13:test(ex12)"),
    ("tt18", "ex14", "pu_ex14:test(ex14)"),
    ("tt19", "ex15", "pu_ex15:test(ex15)"),
    ("tt20", "ex16", "pu_ex16:test(ex16)"),
    ("tt21", "ex17", "pu_ex17:test(ex17)"),
    ("tt22", "clpfd", "( pu_clpfd:has_trie_attvar_support -> once((pu_clpfd:fib(Ncl, 13), Ncl == 6)) ; catch((pu_clpfd:fib(_, 13), fail), error(type_error(free_of_attvar, _), _), true) )"),
    ("tt23", "eruption", "once(pu_eruption:eruption(Per)), Per =:= 0.6288"),
    ("tt24", "eruption2", "once(pu_eruption2:eruption(Per)), Per =:= 0.6288"),
    ("tt25", "sneezing", "once(pu_sneezing:sneezing(bob, Psn)), Psn =:= 0.1352000000000001"),
]

const _TT_PINNED = [
    "ok",
    "t_tt13 c[116,95,116,116,49,51]/1(a[111,107])",
    "t_tt14 c[116,95,116,116,49,52]/1(a[111,107])",
    "t_tt15 c[116,95,116,116,49,53]/1(a[111,107])",
    "t_tt16 c[116,95,116,116,49,54]/1(a[111,107])",
    "t_tt17 c[116,95,116,116,49,55]/1(a[111,107])",
    "t_tt18 c[116,95,116,116,49,56]/1(a[111,107])",
    "t_tt19 c[116,95,116,116,49,57]/1(a[111,107])",
    "t_tt20 c[116,95,116,116,50,48]/1(a[111,107])",
    "t_tt21 c[116,95,116,116,50,49]/1(a[111,107])",
    "t_tt22 c[116,95,116,116,50,50]/1(a[111,107])",
    "t_tt23 c[116,95,116,116,50,51]/1(a[111,107])",
    "t_tt24 c[116,95,116,116,50,52]/1(a[111,107])",
    "t_tt25 c[116,95,116,116,50,53]/1(a[111,107])",
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

@testset "upstream test_tabling.pl units 13..25: the kernel answers every row as swipl does" begin
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
