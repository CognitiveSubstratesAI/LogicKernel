# ORIGINAL: the UPSTREAM tests/tabling/test_trie.pl (swipl-devel 18168e62, 10.1.20), unit trie (32 tests: insert_atom, insert_value_term, insert_two, insert_compound, insert_nested, insert_nested2, insert_nested_get, insert_vars, insert_variant, insert_vars, rescale_cars, insert_gsize, insert_cycle, insert_attvar, delete, delete_all, delete_all_var, gen_indirect, var1, var2, var3, issue_1277, gen_compiled2_free, gen_compiled2_instantiated, gen_compiled3_free, gen_compiled3_cycle, update_compound_value, update_compound_value_destroy, update_variant_value, insert_variant_value, update_value_cycle, insert_other_value),
# as kernel rows (TAB1, TABTEST-TR). One row `t_<id>(R)` per upstream test: `abolish_all_tables, <module>:test(<name>...), abolish_all_tables`, R = ok / failed / raised(E).
#   * The unit text is upstream's, verbatim, between `begin_tests` and `end_tests`, plus every line outside the unit (the parent module) and the libraries the file loads (all but plunit).
#     No helper library.
#   * Every pinned line is swipl's (swipl 10.1.20, two identical runs, evidence/TAB1/tabgap_tools/pins_tr.txt, which also holds the plunit
#     run of the unit) AND equals the answer plunit expects (`_TT_UPSTREAM`: each test passes, so `ok`). Nothing fails or hangs on the pin.
#   * DIVERGES from the file: plunit is not used (`<unit module>:test(Name...)` is called directly). The file's parent module is `test_trie`: every
#     line outside the unit, upstream's text (the module header, the libraries, the helper predicates and upstream's term_expansion of
#     the file), in a file of its own, loaded first; the unit is its own module file `plunit_<unit>` (the name plunit gives it) with
#     `:- set_module(base(test_trie))`, the default import module plunit gives a unit. Tests with plunit options are test/2 clauses whose head
#     is the option: the row calls the test with the option unbound and checks it AFTER the call (`Var == Value` / `Var =@= Value`;
#     `fail`: the call fails; `error(F)`: the call raises error(F, _); `set(Var == List)`: findall + sort/2 + `==`; `nondet`, `sto(..)`
#     and `true`: the call succeeds). A test whose name occurs twice is called through `nth_clause/3` + `clause/3` (the n-th test clause),
#     as plunit runs each clause as its own test. The unit option `condition(..)` is not evaluated (it holds on the pin).
#   * No comment was elided: the file has no line matching the D-0164 term list.
#   * A row whose program the kernel refuses stays a row pinned on swipl (the pin is not weakened); none is known for these units.
#   * SKIPPED BY PLUNIT ON THE PIN: insert_attvar (`condition(\+has_trie_attvar_support)`; the pin has attributed-variable support, the condition fails, plunit lists 31 of the 32 tests and runs no insert_attvar). Its row is `( Cond -> <the error(..) check> ; true )` with the condition evaluated in the unit module: pinned ok on the pin by that skip, and the kernel runs the error check only if the kernel lacks attributed-variable keys. The data/1 clauses draw random values (unseeded): the pinned answers are ok on the pin's runs. The kernel may leave '$atom_references'/3 (private), gensym/2, 1r3 rationals, trie_gen_compiled/3 and trie_update/3 undefined: those rows then show the refusal.
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
    ("trie", ":- begin_tests(trie).", raw"""

test(insert_atom, N == noot) :-
	trie_new(T),
	trie_insert(T, aap, noot),
	trie_lookup(T, aap, N).
test(insert_value_term, N == noot(1)) :-
	trie_new(T),
	trie_insert(T, aap, noot(1)),
	trie_lookup(T, aap, N).
test(insert_two, N1-N2 == noot1-noot2) :-
	trie_new(T),
	trie_insert(T, aap1, noot1),
	trie_insert(T, aap2, noot2),
	trie_lookup(T, aap1, N1),
	trie_lookup(T, aap2, N2).
test(insert_compound, N == noot) :-
	trie_new(T),
	trie_insert(T, aap(1), noot),
	trie_lookup(T, aap(1), N).
test(insert_nested, set(Copy == [v(a(x(a)),b(y),c(z))])) :-
	trie_new(T),
	trie_insert(T, v(a(x(a)),b(y),c(z)), true),
	trie_gen(T, Copy, _).
test(insert_nested2, V == 42) :-
	trie_new(T),
	K = user:t([1,2,3,4], [1,2,3,4]),
	trie_insert(T, K, 42),
	trie_gen(T, K, V).
test(insert_nested_get, Copy == v(a(x(a)),b(y),c(z))) :-
	trie_new(T),
	trie_insert(T, v(a(x(a)),b(y),c(z)), true, Node),
	trie_term(Node, Copy).
test(insert_vars, N == noot) :-
	trie_new(T),
	trie_insert(T, aap(_), noot),
	trie_lookup(T, aap(_), N).
test(insert_variant, N == noot) :-
	trie_new(T),
	trie_insert(T, aap(_,_), noot),
	trie_lookup(T, aap(_,_), N),
	assertion(\+ trie_lookup(T, aap(A,A), N)).
test(insert_vars, STKeys =@= Keys) :-
	Keys = [a(1,a,1), a(_,b,2), a(_,_,3), a(A,A,4)],
	trie_new(T),
	forall(member(K, Keys), trie_insert(T, K, true)),
	findall(K, trie_gen(T, K, _), TKeys),
	sort(3, @<, TKeys, STKeys).
test(rescale_cars, STKeys =@= Keys) :-
	maplist(shared_list, [1,10,100,1000,10000], Keys),
	trie_new(T),
	forall(member(K, Keys), trie_insert(T, K, true)),
	findall(K, trie_gen(T, K, _), TKeys),
	sort(2, @<, TKeys, STKeys).
test(insert_gsize, STKeys =@= KPairs) :-
	Keys = [a(1,a), a(1.0,b), a("hello world",c)],
	sort(Keys, KPairs),
	trie_new(T),
	forall(member(K, Keys), trie_insert(T, K, true)),
	findall(K, trie_gen(T, K, _V), TKeys),
	sort(TKeys, STKeys).
test(insert_cycle, [sto(rational_trees)]) :-
	trie_new(T),
	X = f(X),
	catch(trie_insert(T, X, noot), E, true),
	assertion(E = error(type_error(acyclic_term, X),_)),
	\+ trie_gen(T, _, _).
test(insert_attvar,
     [ error(type_error(free_of_attvar,f(_))),
       condition(\+has_trie_attvar_support)
     ]) :-
	trie_new(T),
	freeze(X, true),
	trie_insert(T, f(X), noot).
test(delete, Keys == [aap,mies]) :-
	trie_new(T),
	trie_insert(T, aap, a),
	trie_insert(T, noot, n),
	trie_insert(T, mies, m),
	trie_delete(T, noot, N),
	assertion(N==n),
	findall(K, trie_gen(T, K, _), Keys0),
	sort(Keys0, Keys).
test(delete_all, Keys-Again == []-[aap]) :-
	trie_new(T),
	trie_insert(T, aap, a),
	trie_insert(T, noot, n),
	trie_delete(T, aap, _),
	trie_delete(T, noot, _),
	findall(K, trie_gen(T, K, _), Keys),
	trie_insert(T, aap, a),
	findall(K, trie_gen(T, K, _), Again).
test(delete_all_var, Keys == []) :-
	trie_new(T),
	trie_insert(T, _, v),
	trie_insert(T, aap, a),
	trie_insert(T, noot, n),
	trie_delete(T, _, _),
	trie_delete(T, aap, _),
	trie_delete(T, noot, _),
	findall(K, trie_gen(T, K, _), Keys).
test(gen_indirect, true) :-
	trie_new(T),
	trie_insert(T, 0.25, true),
	trie_gen(T, 0.25).
test(var1, set(Y == [1,2,3])) :-
        test_var(_, Y).
test(var2, set(Y == [1,2])) :-
        test_var(a, Y).
test(var3, set(Y == [1])) :-
        test_var(c, Y).
test(issue_1277, X == [foo]) :-
	trie_new(T),
	trie_insert(T, _, [foo]),
	trie_gen_compiled(T, _, X).
test(gen_compiled2_free, GData =@= Data) :-
	setof(D, data(D), Data),
	trie_new(T),
	maplist(trie_insert(T), Data),
	setof(GD, trie_gen_compiled(T, GD), GData).
test(gen_compiled2_instantiated, GData =@= Data) :-
	setof(D, (data(D), nonvar(D)), Data),
	trie_new(T),
	maplist(trie_insert(T), Data),
	setof(GD, (member(GD, Data), trie_gen_compiled(T, GD)), GData).
test(gen_compiled3_free, GData =@= KVData) :-
	setof(D, data(D), Data),
	copy_term(Data, Copy),
	pairs_keys_values(KVData, Data, Copy),
	trie_new(T),
	maplist(trie_insert(T), Data, Copy),
	setof(GK-GV, trie_gen_compiled(T, GK, GV), GData).
test(gen_compiled3_cycle, error(type_error(acyclic_term,_))) :-
	trie_new(T),
	X = f(X),
	trie_insert(T, x, X),
	forall(trie_gen_compiled(T, K, V), writeln(K-V)).
test(update_compound_value, A1-B1 == 0-1) :-
	fresh_atoms(A, B),
	trie_new(T),
	trie_update(T, k, [v(A)]),
	trie_update(T, k, [v(B)]),
	'$atom_references'(A, A1),
	'$atom_references'(B, B1).
test(update_compound_value_destroy, V-B1 == [v(B)]-0) :-
	fresh_atoms(A, B),
	trie_new(T),
	trie_update(T, k, [v(A)]),
	trie_update(T, k, [v(B)]),
	trie_lookup(T, k, V),
	trie_destroy(T),
	'$atom_references'(B, B1).
test(update_variant_value, V-A1 == [v(A)]-1) :-
	fresh_atoms(A, _),
	trie_new(T),
	trie_update(T, k, [v(A)]),
	trie_update(T, k, [v(A)]),
	trie_lookup(T, k, V),
	'$atom_references'(A, A1).
test(insert_variant_value, fail) :-
	trie_new(T),
	trie_insert(T, k, f(a)),
	trie_insert(T, k, f(a)).
test(update_value_cycle, Refs == [0,0,0,1]) :-
	fresh_atoms(A, B),
	fresh_atoms(C, D),
	trie_new(T),
	forall(member(X, [A,B,C,A,B,C,D]), trie_update(T, k, f(X))),
	maplist('$atom_references', [A,B,C,D], Refs).
test(insert_other_value, V-A1-B1 == f(A)-1-0) :-
	fresh_atoms(A, B),
	trie_new(T),
	trie_insert(T, k, f(A)),
	catch(trie_insert(T, k, f(B)),
	      error(permission_error(modify, trie_key, k), _),
	      true),
	trie_lookup(T, k, V),
	'$atom_references'(A, A1),
	'$atom_references'(B, B1).

:- if(current_prolog_flag(bounded, false)).
data(Big) :- Big is random(1<<200).
data(Big) :- Big is -random(1<<200).
:- endif.
data(Med) :- Med is random(1<<55).
data(Med) :- Med is -random(1<<55).
data(363).
data(-363).
data(0).
data(1r3).
data(3.14).
data("This is a nice string").
data(_Var).
data(f(x)).
data(f(X,X)).
data([nice, list(of(terms))]).


shared_list(N, t(List,N)) :-
	length(List, N),
	reverse(List, R),
	R = List.

test_var(X, Y) :-
	trie_new(T),
	trie_insert(T, f(_, 1)),
	trie_insert(T, f(a, 2)),
	trie_insert(T, f(b, 3)),
	trie_gen(T, f(X, Y)).

%!  fresh_atoms(-A, -B)
%
%   Two atoms made here, so that only what the test stores registers
%   them.

fresh_atoms(A, B) :-
	gensym(trie_value_a_, A),
	gensym(trie_value_b_, B).

"""),
]

"The file's common tail (lines `before :- ...` to the end), verbatim."
const _TT_TAIL = raw"""
/*  Part of SWI-Prolog

    Author:        Jan Wielemaker
    E-mail:        J.Wielemaker@vu.nl
    WWW:           http://www.swi-prolog.org
    Copyright (c)  2017-2025, University of Amsterdam
                              VU University Amsterdam
			      CWI, Amsterdam
			      SWI-Prolog Solutions b.v.
    All rights reserved.

    Redistribution and use in source and binary forms, with or without
    modification, are permitted provided that the following conditions
    are met:

    1. Redistributions of source code must retain the above copyright
       notice, this list of conditions and the following disclaimer.

    2. Redistributions in binary form must reproduce the above copyright
       notice, this list of conditions and the following disclaimer in
       the documentation and/or other materials provided with the
       distribution.

    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
    "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
    LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
    FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
    COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
    INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
    BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
    LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
    CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
    LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
    ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
    POSSIBILITY OF SUCH DAMAGE.
*/

:- module(test_trie,
	  [ test_trie/0
	  ]).
:- use_module(library(apply)).
:- use_module(library(lists)).
:- use_module(library(debug)).
:- use_module(library(pairs)).

test_trie :-
	run_tests([ trie
		  ]).


has_trie_attvar_support :-
    trie_new(T),
    put_attr(X, x, t),
    catch(trie_insert(T, f(X)),
          error(type_error(free_of_attvar, _),_),
          fail).
"""

"The rows: `(id, unit, goal)`; the goal is the plunit test with its options folded by hand."
const _TT_CASES = [
    ("tt01n01", "trie", "(plunit_trie:test(insert_atom, O), O = (A == B), A == B)"),
    ("tt01n02", "trie", "(plunit_trie:test(insert_value_term, O), O = (A == B), A == B)"),
    ("tt01n03", "trie", "(plunit_trie:test(insert_two, O), O = (A == B), A == B)"),
    ("tt01n04", "trie", "(plunit_trie:test(insert_compound, O), O = (A == B), A == B)"),
    ("tt01n05", "trie", "(findall(X, plunit_trie:test(insert_nested, set(X == _)), L0), sort(L0, L), L == [v(a(x(a)),b(y),c(z))])"),
    ("tt01n06", "trie", "(plunit_trie:test(insert_nested2, O), O = (A == B), A == B)"),
    ("tt01n07", "trie", "(plunit_trie:test(insert_nested_get, O), O = (A == B), A == B)"),
    ("tt01n08", "trie", "((nth_clause(plunit_trie:test(_, _), 8, Rf), clause(plunit_trie:test(_, O), Bd, Rf), plunit_trie:Bd), O = (A == B), A == B)"),
    ("tt01n09", "trie", "(plunit_trie:test(insert_variant, O), O = (A == B), A == B)"),
    ("tt01n10", "trie", "((nth_clause(plunit_trie:test(_, _), 10, Rf), clause(plunit_trie:test(_, O), Bd, Rf), plunit_trie:Bd), O = (A =@= B), A =@= B)"),
    ("tt01n11", "trie", "(plunit_trie:test(rescale_cars, O), O = (A =@= B), A =@= B)"),
    ("tt01n12", "trie", "(plunit_trie:test(insert_gsize, O), O = (A =@= B), A =@= B)"),
    ("tt01n13", "trie", "plunit_trie:test(insert_cycle, _)"),
    ("tt01n14", "trie", "(plunit_trie:(\\+has_trie_attvar_support) -> (catch(plunit_trie:test(insert_attvar, _), error(type_error(free_of_attvar,f(_)), _), Caught = yes), Caught == yes) ; true)"),
    ("tt01n15", "trie", "(plunit_trie:test(delete, O), O = (A == B), A == B)"),
    ("tt01n16", "trie", "(plunit_trie:test(delete_all, O), O = (A == B), A == B)"),
    ("tt01n17", "trie", "(plunit_trie:test(delete_all_var, O), O = (A == B), A == B)"),
    ("tt01n18", "trie", "plunit_trie:test(gen_indirect, _)"),
    ("tt01n19", "trie", "(findall(X, plunit_trie:test(var1, set(X == _)), L0), sort(L0, L), L == [1,2,3])"),
    ("tt01n20", "trie", "(findall(X, plunit_trie:test(var2, set(X == _)), L0), sort(L0, L), L == [1,2])"),
    ("tt01n21", "trie", "(findall(X, plunit_trie:test(var3, set(X == _)), L0), sort(L0, L), L == [1])"),
    ("tt01n22", "trie", "(plunit_trie:test(issue_1277, O), O = (A == B), A == B)"),
    ("tt01n23", "trie", "(plunit_trie:test(gen_compiled2_free, O), O = (A =@= B), A =@= B)"),
    ("tt01n24", "trie", "(plunit_trie:test(gen_compiled2_instantiated, O), O = (A =@= B), A =@= B)"),
    ("tt01n25", "trie", "(plunit_trie:test(gen_compiled3_free, O), O = (A =@= B), A =@= B)"),
    ("tt01n26", "trie", "(catch(plunit_trie:test(gen_compiled3_cycle, _), error(type_error(acyclic_term,_), _), Caught = yes), Caught == yes)"),
    ("tt01n27", "trie", "(plunit_trie:test(update_compound_value, O), O = (A == B), A == B)"),
    ("tt01n28", "trie", "(plunit_trie:test(update_compound_value_destroy, O), O = (A == B), A == B)"),
    ("tt01n29", "trie", "(plunit_trie:test(update_variant_value, O), O = (A == B), A == B)"),
    ("tt01n30", "trie", "\\+ plunit_trie:test(insert_variant_value, _)"),
    ("tt01n31", "trie", "(plunit_trie:test(update_value_cycle, O), O = (A == B), A == B)"),
    ("tt01n32", "trie", "(plunit_trie:test(insert_other_value, O), O = (A == B), A == B)"),
]

const _TT_PINNED = [
    "ok",
    "t_tt01n01 c[116,95,116,116,48,49,110,48,49]/1(a[111,107])",
    "t_tt01n02 c[116,95,116,116,48,49,110,48,50]/1(a[111,107])",
    "t_tt01n03 c[116,95,116,116,48,49,110,48,51]/1(a[111,107])",
    "t_tt01n04 c[116,95,116,116,48,49,110,48,52]/1(a[111,107])",
    "t_tt01n05 c[116,95,116,116,48,49,110,48,53]/1(a[111,107])",
    "t_tt01n06 c[116,95,116,116,48,49,110,48,54]/1(a[111,107])",
    "t_tt01n07 c[116,95,116,116,48,49,110,48,55]/1(a[111,107])",
    "t_tt01n08 c[116,95,116,116,48,49,110,48,56]/1(a[111,107])",
    "t_tt01n09 c[116,95,116,116,48,49,110,48,57]/1(a[111,107])",
    "t_tt01n10 c[116,95,116,116,48,49,110,49,48]/1(a[111,107])",
    "t_tt01n11 c[116,95,116,116,48,49,110,49,49]/1(a[111,107])",
    "t_tt01n12 c[116,95,116,116,48,49,110,49,50]/1(a[111,107])",
    "t_tt01n13 c[116,95,116,116,48,49,110,49,51]/1(a[111,107])",
    "t_tt01n14 c[116,95,116,116,48,49,110,49,52]/1(a[111,107])",
    "t_tt01n15 c[116,95,116,116,48,49,110,49,53]/1(a[111,107])",
    "t_tt01n16 c[116,95,116,116,48,49,110,49,54]/1(a[111,107])",
    "t_tt01n17 c[116,95,116,116,48,49,110,49,55]/1(a[111,107])",
    "t_tt01n18 c[116,95,116,116,48,49,110,49,56]/1(a[111,107])",
    "t_tt01n19 c[116,95,116,116,48,49,110,49,57]/1(a[111,107])",
    "t_tt01n20 c[116,95,116,116,48,49,110,50,48]/1(a[111,107])",
    "t_tt01n21 c[116,95,116,116,48,49,110,50,49]/1(a[111,107])",
    "t_tt01n22 c[116,95,116,116,48,49,110,50,50]/1(a[111,107])",
    "t_tt01n23 c[116,95,116,116,48,49,110,50,51]/1(a[111,107])",
    "t_tt01n24 c[116,95,116,116,48,49,110,50,52]/1(a[111,107])",
    "t_tt01n25 c[116,95,116,116,48,49,110,50,53]/1(a[111,107])",
    "t_tt01n26 c[116,95,116,116,48,49,110,50,54]/1(a[111,107])",
    "t_tt01n27 c[116,95,116,116,48,49,110,50,55]/1(a[111,107])",
    "t_tt01n28 c[116,95,116,116,48,49,110,50,56]/1(a[111,107])",
    "t_tt01n29 c[116,95,116,116,48,49,110,50,57]/1(a[111,107])",
    "t_tt01n30 c[116,95,116,116,48,49,110,51,48]/1(a[111,107])",
    "t_tt01n31 c[116,95,116,116,48,49,110,51,49]/1(a[111,107])",
    "t_tt01n32 c[116,95,116,116,48,49,110,51,50]/1(a[111,107])",
]

"The answer plunit expects of every row: the test passes, `R = ok` (run in swipl by gen_reeval.py pin, plunit part of pins file)."
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
    write(joinpath(d, "test_trie.pl"), _TT_TAIL)
    for (short, _, text) in _TT_UNITS
        write(
            joinpath(d, "plunit_$short.pl"),
            ":- module(plunit_$short, []).\n:- set_module(base(test_trie)).\n" * text
        )
    end
    main = ":- use_module('$d/test_trie').\n" * join([":- use_module('$d/plunit_$short').\n" for (short, _, _) in _TT_UNITS])
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

@testset "upstream test_trie.pl units 1..1: the kernel answers every row as swipl does" begin
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
