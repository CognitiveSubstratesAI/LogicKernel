# ORIGINAL: the UPSTREAM tests/tabling/test_trie_children.pl (swipl-devel 18168e62, 10.1.20), unit trie_children, trie_node_chunks, trie_children_threads (19 tests: sizes, delete_half, delete_reinsert, delete_all, delete_all_nested, nested, kinds, vars, gen_bound, compiled, property, incremental, registered, variants, agc_concurrent, concurrent_insert, concurrent_nested, insert_while_enumerating, shared_variants),
# as kernel rows (TAB1, TABTEST-TR). One row `t_<id>(R)` per upstream test: `abolish_all_tables, <module>:test(<name>...), abolish_all_tables`, R = ok / failed / raised(E).
#   * The unit text is upstream's, verbatim, between `begin_tests` and `end_tests`, plus every line outside the unit (the parent module) and the libraries the file loads (all but plunit).
#     No helper library.
#   * Every pinned line is swipl's (swipl 10.1.20, two identical runs, evidence/TAB1/tabgap_tools/pins_tc.txt, which also holds the plunit
#     run of the unit) AND equals the answer plunit expects (`_TT_UPSTREAM`: each test passes, so `ok`). Nothing fails or hangs on the pin.
#   * DIVERGES from the file: plunit is not used (`<unit module>:test(Name...)` is called directly). The file's parent module is `test_trie_children`: every
#     line outside the unit, upstream's text (the module header, the libraries, the helper predicates and upstream's term_expansion of
#     the file), in a file of its own, loaded first; the unit is its own module file `plunit_<unit>` (the name plunit gives it) with
#     `:- set_module(base(test_trie_children))`, the default import module plunit gives a unit. Tests with plunit options are test/2 clauses whose head
#     is the option: the row calls the test with the option unbound and checks it AFTER the call (`Var == Value` / `Var =@= Value`;
#     `fail`: the call fails; `error(F)`: the call raises error(F, _); `set(Var == List)`: findall + sort/2 + `==`; `nondet`, `sto(..)`
#     and `true`: the call succeeds). A test whose name occurs twice is called through `nth_clause/3` + `clause/3` (the n-th test clause),
#     as plunit runs each clause as its own test. The unit option `condition(..)` is not evaluated (it holds on the pin).
#   * No comment was elided: the file has no line matching the D-0164 term list.
#   * THREAD-BOUND: the five tests of unit trie_children_threads (upstream `condition(threads)`; thread_create/2, concurrent_forall/3, a shared table) are
#     pinned on swipl in their own testset "thread-bound: expected refusal on the kernel": a kernel line that differs from the pin is recorded as
#     @test_broken (visible in the summary), one that equals it passes. The condition is not evaluated: the body runs. The unit option
#     `cleanup(abolish_all_tables)` of trie_node_chunks is the driver's abolish_all_tables after every row (also before it).
#   * A row whose program the kernel refuses stays a row pinned on swipl (the pin is not weakened); none is known for these units.
#   * Environment: registered (trie_node_chunks) tests `N2 < 10` only when `SWIPL_TEST_FAIL_ON_UNLIKELY` is `y`; it is unset in the pin's runs and the kernel's, so that assertion is not run. The kernel may leave the table modifiers `as incremental` / `as shared`, trie_gen_compiled/3, thread_create/3, concurrent_forall/3, garbage_collect_atoms/0 and current_table/2 undefined: the rows then show the refusal.
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
    ("trie_children", ":- begin_tests(trie_children).", raw"""

test(sizes) :-
    forall(member(N, [1,2,3,8,9,16,17,100,1000]),
           ( trie_new(T),
             keys(N, Keys),
             fill(T, Keys),
             check(T, Keys)
           )).
test(delete_half) :-
    forall(member(N, [2,8,9,100,1000]),
           ( trie_new(T),
             keys(N, Keys),
             fill(T, Keys),
             even_odd(Keys, Even, Odd),
             delete_keys(T, Even),
             check(T, Odd),
             forall(member(K, Even), assertion(\+ trie_lookup(T, K, _)))
           )).
test(delete_reinsert) :-
    forall(member(N, [2,9,100,1000]),
           ( trie_new(T),
             keys(N, Keys),
             fill(T, Keys),
             even_odd(Keys, Even, Odd),
             delete_keys(T, Even),
             fill(T, Even),
             check(T, Keys),
             delete_keys(T, Odd),
             check(T, Even)
           )).
test(delete_all, Found == []) :-
    trie_new(T),
    keys(100, Keys),
    fill(T, Keys),
    delete_keys(T, Keys),
    findall(K, trie_gen(T, K, _), Found),
    keys(10, Keys10),
    fill(T, Keys10),
    check(T, Keys10).
test(delete_all_nested, Found == []) :-
    trie_new(T),
    findall(f(X,Y), (between(1, 20, X), between(1, 20, Y)), Keys),
    fill(T, Keys),
    delete_keys(T, Keys),
    findall(K, trie_gen(T, K, _), Found).
test(nested) :-
    trie_new(T),
    findall(f(X,g(Y),Z),
            ( between(1, 30, X), between(1, X, Y), member(Z, [a,b]) ),
            Keys),
    fill(T, Keys),
    check(T, Keys),
    include([f(X,_,_)]>>(X mod 3 =:= 0), Keys, Del),
    subtract(Keys, Del, Rest),
    delete_keys(T, Del),
    check(T, Rest).
test(kinds) :-
    trie_new(T),
    Big is 2^100,
    numlist(1, 20, Ints),
    findall(A, (between(1, 20, I), atom_concat(a, I, A)), Atoms),
    findall(F, (between(1, 20, I), F is I/3.0), Floats),
    findall(S, (between(1, 20, I), number_string(I, S0),
                string_concat("s", S0, S)), Strings),
    append([Ints, Atoms, Floats, Strings, [Big, -Big, f(a), f(_), g(_,_)]],
           Keys0),
    maplist([K,k(K)]>>true, Keys0, Keys),
    fill(T, Keys),
    findall(K, trie_gen(T, K, _), Found),
    length(Keys, Len),
    assertion(length(Found, Len)),
    forall(member(K, Keys),
           assertion((member(F, Found), F =@= K))).
test(vars) :-
    trie_new(T),
    Keys = [f(_,_), f(X,X), f(a,_), f(_,a), f(a,a), f(_,b), f(Y,Y,Y)],
    fill(T, Keys),
    findall(K, trie_gen(T, K, _), Found),
    length(Found, 7),
    forall(member(K, Keys),
           assertion((member(F, Found), F =@= K))),
    findall(Y1, trie_gen(T, f(a,Y1), _), Ys),
    length(Ys, 6).                      % all but f(Y,Y,Y)
test(gen_bound) :-                      % trie_gen/3 with a bound argument
    trie_new(T),
    findall(f(X,Y), (between(1, 50, X), between(1, 50, Y)), Keys),
    fill(T, Keys),
    findall(Y, trie_gen(T, f(17,Y), _), Ys),
    assertion(Ys == Ys),
    length(Ys, 50),
    trie_insert(T, f(_,1), var),
    findall(V, trie_gen(T, f(17,1), V), Vs),
    msort(Vs, VsS),
    assertion(VsS = [_,var]).
test(compiled) :-
    trie_new(T),
    keys(200, Keys),
    fill(T, Keys),
    even_odd(Keys, Even, Odd),
    delete_keys(T, Even),
    findall(K, trie_gen_compiled(T, K, _), Found0),
    msort(Found0, Found),
    assertion(Found == Odd).
test(property) :-
    trie_new(T),
    keys(1000, Keys),
    fill(T, Keys),
    trie_property(T, node_count(Nodes)),
    trie_property(T, value_count(Values)),
    trie_property(T, size(Bytes)),
    assertion(Values == 1000),
    assertion(Nodes == 1001),
    assertion(Bytes > 0).

"""),
    ("trie_node_chunks", ":- begin_tests(trie_node_chunks, [cleanup(abolish_all_tables)]).", raw"""

test(incremental) :-                    % re-evaluate a large answer trie
    abolish_all_tables,
    clear_d,
    forall(between(1, 2000, I), add_d(I)),
    forall(between(1, 3, _),
           ( q_answers(L1), d_facts(D1), assertion(L1 == D1),
             forall(( between(1, 2000, I), I mod 2 =:= 0 ),
                    del_d(I)),
             q_answers(L2), d_facts(D2), assertion(L2 == D2),
             assertion(length(L2, 1000)),
             forall(( between(1, 2000, I), I mod 2 =:= 0 ),
                    add_d(I))
           )),
    q_answers(L), assertion(length(L, 2000)),
    clear_d.
test(registered) :-                     % atom-GC registers full chunks
    abolish_all_tables,
    \+ \+ reg_atom(_),
    reg_atom_count(N0),                 % first scan: chunks are full
    assertion(N0 == 5000),
    reg_atom_count(N1),                 % second scan: register them
    assertion(N1 == 5000),
    aggregate_all(count, reg_atom(_), C),
    assertion(C == 5000),
    abolish_all_tables,                 % releases the registered keys
    assertz(chunk_gen_dummy), retract(chunk_gen_dummy),
    garbage_collect_clauses,            % and the compiled clause
    reg_atom_count(N2),
    (   if_reliable_agc
    ->  assertion(N2 < 10)
    ;   true
    ).
test(variants) :-                       % variant table nodes are pruned
    abolish_all_tables,
    forall(between(1, 3, _),
           ( forall(between(1, 2000, I), v(I, _)),
             v_tables(N1), assertion(N1 == 2000),
             forall(( between(1, 2000, I), I mod 2 =:= 1 ),
                    abolish_table_subgoals(v(I, _))),
             v_tables(N2), assertion(N2 == 1000)
           )),
    forall(between(1, 2000, I), ( v(I, Y), assertion(Y =:= I*2) )).

"""),
    ("trie_children_threads", ":- begin_tests(trie_children_threads, [ condition(current_prolog_flag(threads, true)) ]).", raw"""

test(agc_concurrent) :-
    thread_create(agc_loop(stop), AGC, []),
    numlist(1, 4, Ids),
    findall(T, ( member(Id, Ids),
                 thread_create(agc_worker(Id), T, [])
               ), Workers),
    maplist(thread_join, Workers, Statuses),
    thread_send_message(AGC, stop),
    thread_join(AGC, AStatus),
    assertion(maplist(==(true), Statuses)),
    assertion(AStatus == true).

thread_keys(Id, Keys) :-
    findall(f(K), (between(1, 2000, I), K is (I*Id) mod 3001), Keys0),
    sort(Keys0, Keys).

test(concurrent_insert) :-
    trie_new(T),
    numlist(1, 8, Ids),
    concurrent_forall(member(Id, Ids),
                      ( thread_keys(Id, Keys),
                        forall(member(K, Keys), trie_update(T, K, Id))
                      ),
                      [threads(8)]),
    findall(Ks, (member(Id, Ids), thread_keys(Id, Ks)), Kss),
    append(Kss, All0),
    sort(All0, All),
    check(T, All).
test(concurrent_nested) :-
    trie_new(T),
    numlist(1, 8, Ids),
    concurrent_forall(member(Id, Ids),
                      forall(( between(1, 50, X), between(1, 50, Y) ),
                             trie_update(T, g(X,Id,Y), Id)),
                      [threads(8)]),
    aggregate_all(count, trie_gen(T, _, _), Count),
    assertion(Count == 20000).
test(insert_while_enumerating) :-
    trie_new(T),
    numlist(1, 1000, Before),
    forall(member(K, Before), trie_insert(T, f(K), old)),
    thread_create(forall(between(1001, 20000, K), trie_insert(T, f(K), new)),
                  Id, []),
    findall(K, trie_gen(T, f(K), _), Seen),
    thread_join(Id, Status),
    assertion(Status == true),
    msort(Seen, SeenS),
    assertion(ord_subset(Before, SeenS)),
    length(SeenS, Len), sort(SeenS, Unique),
    assertion(length(Unique, Len)),
    aggregate_all(count, trie_gen(T, _, _), Count),
    assertion(Count == 20000).

test(shared_variants) :-                % concurrent shared variant table
    abolish_all_tables,
    numlist(1, 8, Ids),
    concurrent_forall(member(Id, Ids),
                      forall(between(1, 500, I),
                             ( K is (I*Id) mod 701,
                               findall(X, sv(K, X), Xs),
                               assertion(Xs == [K]) )),
                      [threads(8)]),
    aggregate_all(count, (current_table(_:V, _), V = sv(_,_)), Count),
    findall(K, (member(Id, Ids), between(1, 500, I), K is (I*Id) mod 701),
            Ks0),
    sort(Ks0, Ks),
    length(Ks, Count).

:- table sv/2 as shared.
sv(K, K).

"""),
]

"The file's common tail (lines `before :- ...` to the end), verbatim."
const _TT_TAIL = raw"""
/*  Part of SWI-Prolog

    Author:        Jan Wielemaker
    Copyright (c)  2026, SWI-Prolog Solutions b.v.
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

:- module(test_trie_children,
          [ test_trie_children/0
          ]).
:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(debug)).
:- if(current_prolog_flag(threads, true)).
:- use_module(library(thread)).
:- endif.

/** <module> Test the representation of the children of trie nodes

Nodes have no children, a single child or  a block of children. Small
blocks are searched linearly, larger ones  have   an  index. These tests
exercise growing and compacting blocks,   deletion  and enumeration, and
concurrent insertion into tries created by trie_new/1.

Tries without concurrent writers, i.e., tables, allocate their nodes
from chunks.  The trie_node_chunks tests delete and re-add many nodes
of such tries and re-evaluate large incremental tables.
*/

test_trie_children :-
    run_tests([ trie_children,
                trie_node_chunks,
                trie_children_threads
              ]).

%   fill(+Trie, +Keys)
%   check(+Trie, +Keys)
%
%   Insert Keys with their position as value and verify that the trie
%   holds exactly Keys.

fill(Trie, Keys) :-
    foldl(insert(Trie), Keys, 1, _).

insert(Trie, Key, I0, I) :-
    trie_insert(Trie, Key, I0),
    I is I0+1.

check(Trie, Keys) :-
    findall(K, trie_gen(Trie, K, _), Found0),
    msort(Found0, Found),
    msort(Keys, Expected),
    assertion(Found == Expected),
    forall(member(K, Keys),
           assertion(trie_lookup(Trie, K, _))).

keys(N, Keys) :-
    numlist(1, N, Keys).

delete_keys(Trie, Keys) :-
    forall(member(K, Keys), trie_delete(Trie, K, _)).

even_odd(Keys, Even, Odd) :-
    partition([K]>>(K mod 2 =:= 0), Keys, Even, Odd).


:- dynamic d/1 as incremental.
:- table q/1 as incremental.
:- table v/2.

q(X) :- d(X).
v(X, Y) :- Y is X*2.

q_answers(L) :-
    findall(X, q(X), L0),
    msort(L0, L).

d_facts(L) :-
    findall(X, d(X), L0),
    msort(L0, L).

v_tables(N) :-
    aggregate_all(count,
                  ( current_table(test_trie_children:V, _),
                    V = v(_,_)
                  ), N).

add_d(I)  :- assertz(d(f(I, g(I)))).
del_d(I)  :- retract(d(f(I, g(I)))).
clear_d   :- retractall(d(_)).


%   Tables with fresh atoms.  Atom-GC marks the keys of the chunk
%   nodes rather than the nodes registering the atoms.

:- table agc_atom/3, agc_var/2, reg_atom/1.
:- dynamic chunk_gen_dummy/0.

reg_atom(X) :-
    between(1, 5000, I),
    atom_concat(rga_, I, X).

%   Whether we can expect AGC to reclaim the released atoms.  AGC
%   may find stale references on the stacks, so only test this if
%   `SWIPL_TEST_FAIL_ON_UNLIKELY` is `y`.

if_reliable_agc :-
    getenv('SWIPL_TEST_FAIL_ON_UNLIKELY', y).

reg_atom_count(N) :-
    garbage_collect_atoms,
    aggregate_all(count,
                  ( current_atom(A),
                    sub_atom(A, 0, _, After, rga_),
                    After > 0
                  ), N).

agc_atom(Id, R, X) :-
    between(1, 300, I),
    agc_name(Id, R, I, X).

agc_name(Id, R, I, X) :-
    format(atom(X), 'agc_~w_~w_~w', [Id, R, I]).

agc_var(_, _).

%   agc_worker(+Id)
%
%   Create tables with fresh atoms and verify them a few times, such
%   that atom-GC registers the full chunks.  Then delete and re-add
%   variants with fresh atoms, deleting and reusing nodes of registered
%   chunks of the variant table.

agc_worker(Id) :-
    forall(between(1, 10, R), \+ \+ agc_atom(Id, R, _)),
    forall(between(1, 3, _), agc_check_answers(Id)),
    agc_var_names(Id, Names),
    forall(member(N, Names), agc_var(Id, N)),
    forall(between(1, 3, _), agc_check_variants(Id, Names)),
    agc_odd(Names, Odd, Even),
    forall(member(N, Odd), abolish_table_subgoals(agc_var(Id, N))),
    agc_check_variants(Id, Even),
    forall(member(N, Odd), agc_var(Id, N)),
    forall(between(1, 3, _), agc_check_variants(Id, Names)),
    agc_check_answers(Id).

agc_check_answers(Id) :-
    forall(between(1, 10, R),
           ( findall(X, agc_atom(Id, R, X), Xs),
             msort(Xs, Sorted),
             findall(X, (between(1, 300, I), agc_name(Id, R, I, X)), Exp0),
             msort(Exp0, Exp),
             Sorted == Exp
           )).

agc_var_names(Id, Names) :-
    findall(N, ( between(1, 400, I),
                 format(atom(N), 'agc_var_~w_~w', [Id, I])
               ), Names).

agc_check_variants(Id, Names) :-
    findall(N, ( current_table(test_trie_children:V, _),
                 V = agc_var(Id, N)
               ), Found0),
    msort(Found0, Found),
    findall(N, (member(N0, Names), atom_string(N0, S), atom_string(N, S)),
            Exp0),
    msort(Exp0, Exp),
    Found == Exp.

agc_odd([], [], []).
agc_odd([O], [O], []).
agc_odd([O,E|T0], [O|O1], [E|E1]) :-
    agc_odd(T0, O1, E1).

agc_loop(Stop) :-
    (   thread_peek_message(Stop)
    ->  true
    ;   garbage_collect_atoms,
        agc_loop(Stop)
    ).
"""

"The rows: `(id, unit, goal)`; the goal is the plunit test with its options folded by hand."
const _TT_CASES = [
    ("tt01n01", "trie_children", "plunit_trie_children:test(sizes)"),
    ("tt01n02", "trie_children", "plunit_trie_children:test(delete_half)"),
    ("tt01n03", "trie_children", "plunit_trie_children:test(delete_reinsert)"),
    ("tt01n04", "trie_children", "(plunit_trie_children:test(delete_all, O), O = (A == B), A == B)"),
    ("tt01n05", "trie_children", "(plunit_trie_children:test(delete_all_nested, O), O = (A == B), A == B)"),
    ("tt01n06", "trie_children", "plunit_trie_children:test(nested)"),
    ("tt01n07", "trie_children", "plunit_trie_children:test(kinds)"),
    ("tt01n08", "trie_children", "plunit_trie_children:test(vars)"),
    ("tt01n09", "trie_children", "plunit_trie_children:test(gen_bound)"),
    ("tt01n10", "trie_children", "plunit_trie_children:test(compiled)"),
    ("tt01n11", "trie_children", "plunit_trie_children:test(property)"),
    ("tt02n01", "trie_node_chunks", "plunit_trie_node_chunks:test(incremental)"),
    ("tt02n02", "trie_node_chunks", "plunit_trie_node_chunks:test(registered)"),
    ("tt02n03", "trie_node_chunks", "plunit_trie_node_chunks:test(variants)"),
    ("tt03n01", "trie_children_threads", "plunit_trie_children_threads:test(agc_concurrent)"),
    ("tt03n02", "trie_children_threads", "plunit_trie_children_threads:test(concurrent_insert)"),
    ("tt03n03", "trie_children_threads", "plunit_trie_children_threads:test(concurrent_nested)"),
    ("tt03n04", "trie_children_threads", "plunit_trie_children_threads:test(insert_while_enumerating)"),
    ("tt03n05", "trie_children_threads", "plunit_trie_children_threads:test(shared_variants)"),
]

"The thread-bound rows (upstream `condition(threads)`): pinned on swipl; the kernel's line is compared to the pin, and a line that differs is @test_broken, never a silent pass."
const _TT_THREAD_IDS = ["tt03n01", "tt03n02", "tt03n03", "tt03n04", "tt03n05"]
const _TT_KL = Ref{Vector{String}}(String[])

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
    "t_tt02n01 c[116,95,116,116,48,50,110,48,49]/1(a[111,107])",
    "t_tt02n02 c[116,95,116,116,48,50,110,48,50]/1(a[111,107])",
    "t_tt02n03 c[116,95,116,116,48,50,110,48,51]/1(a[111,107])",
    "t_tt03n01 c[116,95,116,116,48,51,110,48,49]/1(a[111,107])",
    "t_tt03n02 c[116,95,116,116,48,51,110,48,50]/1(a[111,107])",
    "t_tt03n03 c[116,95,116,116,48,51,110,48,51]/1(a[111,107])",
    "t_tt03n04 c[116,95,116,116,48,51,110,48,52]/1(a[111,107])",
    "t_tt03n05 c[116,95,116,116,48,51,110,48,53]/1(a[111,107])",
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
]

"The files of the program in a fresh directory: one module file per unit, the main file with the rows; returns the main file."
function _tt_materialize()::String
    d = realpath(mktempdir())
    write(joinpath(d, "test_trie_children.pl"), _TT_TAIL)
    for (short, _, text) in _TT_UNITS
        write(
            joinpath(d, "plunit_$short.pl"),
            ":- module(plunit_$short, []).\n:- set_module(base(test_trie_children)).\n" * text
        )
    end
    main = ":- use_module('$d/test_trie_children').\n" * join([":- use_module('$d/plunit_$short').\n" for (short, _, _) in _TT_UNITS])
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

@testset "upstream test_trie_children.pl units 1..3: the kernel answers every row as swipl does" begin
    gd, ld, st = _tt_load(_tt_materialize())
    @test st == "ok"
    kl = String[st]
    for (id, _, _) in _TT_CASES
        push!(kl, _tt_ask(gd, ld, "t_$id"))
    end
    _TT_KL[] = kl
    @test length(kl) == length(_TT_PINNED)
    @test _TT_PINNED[1] == st
    for (i, (k, pn)) in enumerate(zip(kl, _TT_PINNED))
        i > 1 && _TT_CASES[i - 1][1] in _TT_THREAD_IDS && continue
        k == pn || println(stderr, "  ours  ", k, "\n  swipl ", pn)
        @test k == pn
    end
    # must-fail: a corrupted pin is not the kernel's line (the comparison can fail)
    @test length(kl) > 1
    @test kl[2] != _tt_corrupt(_TT_PINNED[2])
end

@testset "thread-bound: expected refusal on the kernel (upstream tests with condition(threads))" begin
    kl = _TT_KL[]
    @test length(kl) == length(_TT_PINNED)
    for id in _TT_THREAD_IDS
        j = findfirst(c -> c[1] == id, _TT_CASES)::Int
        k, pn = kl[j + 1], _TT_PINNED[j + 1]
        @test _tt_answer(pn) == _TT_UPSTREAM[j]
        @test k != _tt_corrupt(pn)  # must-fail: the comparison can fail
        if k == pn
            @test true
        else
            println(stderr, "  thread-bound ", id, "\n  ours  ", k, "\n  swipl ", pn)
            @test_broken k == pn
        end
    end
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
