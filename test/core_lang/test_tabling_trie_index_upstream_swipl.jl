# ORIGINAL: the UPSTREAM tests/tabling/test_trie_index.pl (swipl-devel 18168e62, 10.1.20), unit trie_index (17 tests: generated_unification, cyclic_query, deleted_pending_answer, garbage_collection_between_answers, variable_mask_overflow, attributed_query, compound_pop, repeated_variables, stored_attvar_beside_constants, absent_indirect_value, stack_shift_between_answers, insert_between_answers, delete_between_answers, single_match_is_deterministic, cut_after_pruned_answer, bound_value, generated_shapes),
# as kernel rows (TAB1, TABTEST-TR). One row `t_<id>(R)` per upstream test: `abolish_all_tables, <module>:test(<name>...), abolish_all_tables`, R = ok / failed / raised(E).
#   * The unit text is upstream's, verbatim, between `begin_tests` and `end_tests`, plus every line outside the unit (the parent module) and the libraries the file loads (all but plunit).
#     No helper library.
#   * Every pinned line is swipl's (swipl 10.1.20, two identical runs, evidence/TAB1/tabgap_tools/pins_ti.txt, which also holds the plunit
#     run of the unit) AND equals the answer plunit expects (`_TT_UPSTREAM`: each test passes, so `ok`). Nothing fails or hangs on the pin.
#   * DIVERGES from the file: plunit is not used (`<unit module>:test(Name...)` is called directly). The file's parent module is `test_trie_index`: every
#     line outside the unit, upstream's text (the module header, the libraries, the helper predicates and upstream's term_expansion of
#     the file), in a file of its own, loaded first; the unit is its own module file `plunit_<unit>` (the name plunit gives it) with
#     `:- set_module(base(test_trie_index))`, the default import module plunit gives a unit. Tests with plunit options are test/2 clauses whose head
#     is the option: the row calls the test with the option unbound and checks it AFTER the call (`Var == Value` / `Var =@= Value`;
#     `fail`: the call fails; `error(F)`: the call raises error(F, _); `set(Var == List)`: findall + sort/2 + `==`; `nondet`, `sto(..)`
#     and `true`: the call succeeds). A test whose name occurs twice is called through `nth_clause/3` + `clause/3` (the n-th test clause),
#     as plunit runs each clause as its own test. The unit option `condition(..)` is not evaluated (it holds on the pin).
#   * No comment was elided: the file has no line matching the D-0164 term list.
#   * A row whose program the kernel refuses stays a row pinned on swipl (the pin is not weakened); none is known for these units.
#   * generated_shapes draws random keys and queries (library(random), unseeded): its pinned answer is ok on the pin's runs; a kernel run draws other keys.
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
    ("trie_index", ":- begin_tests(trie_index).", raw"""

test(generated_unification) :-
    set_random(seed(904219)),
    forall(between(1, 20, _),
           setup_call_cleanup(trie_new(T), generated(T), trie_destroy(T))).

test(cyclic_query, Ids == [1, 2]) :-
    setup_call_cleanup(trie_new(T),
        (trie_insert(T, p(_, a), 1), trie_insert(T, p(f(_), a), 2),
         X = f(X), findall(I, trie_gen(T, p(X, a), I), Found), sort(Found, Ids)),
        trie_destroy(T)).

test(deleted_pending_answer, true(Count == 1)) :-
    setup_call_cleanup(trie_new(T),
        (forall(between(1, 10, I), trie_insert(T, p(I, 17))),
         findall(I, (trie_gen(T, p(I, 17)),
                     forall((between(1, 10, J), J =\= I),
                            ignore(trie_delete(T, p(J, 17), _)))), Ids),
         length(Ids, Count)),
        trie_destroy(T)).

test(garbage_collection_between_answers, true(Count == 100)) :-
    setup_call_cleanup(trie_new(T),
        (forall(between(1, 100, I), trie_insert(T, p(I, f(a), _))),
         findall(I, (trie_gen(T, p(I, f(a), b)), garbage_collect), Ids),
         length(Ids, Count)), trie_destroy(T)).

test(variable_mask_overflow, true(Ids == [1, 2])) :-
    length(Vars, 40), Prefix =.. [f|Vars], last(Vars, Last),
    setup_call_cleanup(trie_new(T),
        (trie_insert(T, p(Prefix, Last, 13), 1),
         trie_insert(T, p(Prefix, a, 13), 2),
         findall(I, trie_gen(T, p(_, a, 13), I), Found), sort(Found, Ids)),
        trie_destroy(T)).

test(attributed_query, true(Ids == [2])) :-
    setup_call_cleanup(trie_new(T),
        (trie_insert(T, p(1, b), 1), trie_insert(T, p(2, b), 2),
         freeze(X, X =:= 2), findall(I, trie_gen(T, p(X, b), I), Ids)),
        trie_destroy(T)).

% Compounds that end before their last argument close with POP keys, and
% last-argument chains share one: skips must end inside them.
test(compound_pop) :-
    Keys = [ p(f(g(a), b), c), p(f(g(a, x), b), c), p(f(_, b), c), p(_, c),
	     p(f(g(a)), c), p(f(g(h(a))), d), p(a, f(g(h(a)))),
	     p(f(g(a), b), f(c)), p(f(z(), b), c), p([a, b, c], d),
	     p([a, b|_], d), p([a|_], e), p(g(f(a), _), [x, y]),
	     p(g(f(a, b), h(c, d)), e(f)), p(z(), z()) ],
    Queries = [ p(_, c), p(f(_, b), c), p(f(g(_), _), c), p(f(g(a), b), _),
		p(_, _), p(f(_), c), p(a, f(g(h(_)))), p(a, f(_)),
		p(f(g(h(a))), _), p(f(z(), _), c), p([a, b, c], _),
		p([a, _, c], d), p([_|_], _), p(g(_, b), [x|_]),
		p(f(g(_, x), _), c), p(g(f(_, b), _), e(_)),
		p(g(_, h(c, _)), _), p(z(), _), p(_, z()) ],
    setup_call_cleanup(trie_new(T),
        ( insert_keys(Keys, T, 1, Pairs),
          forall(member(Query, Queries), same_answers(T, Pairs, Query)) ),
        trie_destroy(T)).

test(repeated_variables) :-
    Keys = [ p(a, b), p(a, a), p(X, X), p(_, _), p(f(Y), Y), p(f(a), b),
	     p(f(Z), g(Z)), p(g(W, W), W), p(h(U, U, V), V) ],
    Queries = [ p(S, S), p(a, _), p(f(R), R), p(f(_), a), p(_, b),
		p(f(P), g(P)), p(f(b), g(c)), p(g(O, O), a), p(g(a, b), _),
		p(h(a, N, N), b), p(h(M, L, L), M) ],
    setup_call_cleanup(trie_new(T),
        ( insert_keys(Keys, T, 1, Pairs),
          forall(member(Query, Queries), same_answers(T, Pairs, Query)) ),
        trie_destroy(T)).

% A stored attributed variable beside constants in a hashed node is
% reached by a bound query; its hook accepts or rejects the binding.
test(stored_attvar_beside_constants) :-
    forall(member(Mode-Expected, [accept-[1, 4], reject-[4]]),
           stored_attvar(Mode, Expected)).

% A bound value the trie never interned matches only stored variables.
test(absent_indirect_value) :-
    setup_call_cleanup(trie_new(T),
        ( trie_insert(T, p(_, 1), 1), trie_insert(T, p("text", 2), 2),
          trie_insert(T, p(12345678901234567890, 3), 3),
          trie_insert(T, p(2.5, 4), 4),
          trie_insert(T, q("a", 1), 5), trie_insert(T, q("b", 2), 6),
          forall(member(Query-Expected,
                        [ p("other", _)-[1], p("text", _)-[1, 2],
                          p(98765432109876543210, _)-[1],
                          p(12345678901234567890, _)-[1, 3],
                          p(3.5, _)-[1], p(2.5, _)-[1, 4],
                          q("c", _)-[], q("a", _)-[5] ]),
                 ( findall(V, trie_gen(T, Query, V), Vs), msort(Vs, Sorted),
                   assertion(Sorted == Expected) )) ),
        trie_destroy(T)),
    setup_call_cleanup(trie_new(T2),
        ( trie_insert(T2, p(_, a), 1),
          findall(V, trie_gen(T2, p("s", a), V), Vs2),
          assertion(Vs2 == [1]) ),
        trie_destroy(T2)).

% Collections and stack shifts move the query between answers; the
% cursor is rebuilt rather than kept.
test(stack_shift_between_answers) :-
    statistics(global_shifts, S0),
    statistics(garbage_collection, [G0|_]),
    setup_call_cleanup(trie_new(T),
        ( forall(between(1, 30, I),
                 ( trie_insert(T, p(f(I), g(_, b)), I),
                   trie_insert(T, p(f(I), g(_, c)), c(I)) )),
          Query = p(f(_), g(h(1), b)),
          findall(V, (trie_gen(T, Query, V), churn), Found0), msort(Found0, Found),
          findall(V, (trie_gen(T, K, V), K = Query), Expected0),
          msort(Expected0, Expected),
          assertion(Found == Expected), assertion(length(Found, 30)) ),
        trie_destroy(T)),
    statistics(global_shifts, S1),
    statistics(garbage_collection, [G1|_]),
    assertion(S1 > S0), assertion(G1 > G0).

% Keys inserted while answers are pending, into the enumerated table and
% beside the path, never repeat an answer or lose one that was there.
test(insert_between_answers) :-
    setup_call_cleanup(trie_new(T),
        ( forall(between(1, 50, I), trie_insert(T, p(_, I), I)),
          findall(V, ( trie_gen(T, p(a, _), V),
                       ( integer(V), V =< 50
                       -> trie_insert(T, p(b, V), b(V)),
                          trie_insert(T, q(V), q(V)),
                          N is 1000+V, trie_insert(T, p(_, N), N)
                       ;  true ) ),
                  Vs),
          partition([E]>>(E =< 50), Vs, Early, Late),
          msort(Early, Sorted), numlist(1, 50, All),
          assertion(Sorted == All),
          msort(Late, LateSorted), sort(Late, LateSet),
          assertion(LateSorted == LateSet),
          forall(member(X, Late), assertion(X > 1000)) ),
        trie_destroy(T)).

test(delete_between_answers, true(Count == 1)) :-
    setup_call_cleanup(trie_new(T),
        ( forall(between(1, 50, I), trie_insert(T, p(_, I), I)),
          findall(V, ( trie_gen(T, p(a, _), V),
                       forall(between(1, 50, J),
                              ignore(trie_delete(T, p(_, J), _))) ),
                  Vs),
          length(Vs, Count) ),
        trie_destroy(T)).

% Below a wildcard, the bound argument is looked up rather than every
% stored value tried, so a single match leaves no choice point.  Det is
% tested in the body, as plunit cuts a choice point the body leaves.
test(single_match_is_deterministic, V == 50) :-
    setup_call_cleanup(trie_new(T),
        ( forall(between(1, 100, I), trie_insert(T, p(_, I), I)),
          call_cleanup(trie_gen(T, p(a, 50), V), Det = true),
          assertion(Det == true) ),
        trie_destroy(T)).

% After an answer below a pruning choice the search stops and leaves the
% rest to the redo; a cut discards it instead.
test(cut_after_pruned_answer) :-
    setup_call_cleanup(trie_new(T),
        ( forall(between(1, 50, I),
                 ( trie_insert(T, p(I, a), I), trie_insert(T, p(I, b), b(I)) )),
          forall(between(1, 3, N),
                 ( findall(V, limit(N, trie_gen(T, p(_, a), V)), Vs),
                   assertion(length(Vs, N)),
                   assertion(maplist(integer, Vs)) )) ),
        trie_destroy(T)).

% A bound Value rejects candidates after Key unified with them, so the
% search goes on with Key unbound again.
test(bound_value, Xs == [25]) :-
    setup_call_cleanup(trie_new(T),
        ( forall(between(1, 50, I),
                 ( trie_insert(T, p(I, a), I), trie_insert(T, p(I, b), b(I)) )),
          findall(X, trie_gen(T, p(X, a), 25), Xs) ),
        trie_destroy(T)).

% Deeper keys with lists, zero-argument compounds, rationals and signed
% zeros, queried by generalisations and instances of the stored keys.
test(generated_shapes) :-
    set_random(seed(310877)),
    forall(between(1, 10, _),
           setup_call_cleanup(trie_new(T), generated_shapes(T), trie_destroy(T))).

"""),
]

"The file's common tail (lines `before :- ...` to the end), verbatim."
const _TT_TAIL = raw"""
:- module(test_trie_index,
          [ test_trie_index/0
          ]).
:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(random)).

% trie_gen/2,3 prunes its walk on the bound parts of the query, also
% after a variable in the query or in the trie.  These tests compare its
% answers with those of enumerating every key and unifying it with the
% query, over generated and hand-picked keys and queries, and check that
% the walk survives garbage collection, stack shifts and changes to the
% trie between answers.

test_trie_index :- run_tests(trie_index).



stored_attvar(Mode, Expected) :-
    setup_call_cleanup(trie_new(T),
        ( put_attr(X, test_trie_index, Mode), trie_insert(T, p(X), 1),
          trie_insert(T, p(b), 2), trie_insert(T, p(c), 3),
          trie_insert(T, p(_), 4),
          put_attr(Y, test_trie_index, Mode), trie_insert(T, q(Y, Y), 5),
          trie_insert(T, q(a, b), 6), trie_insert(T, q(_, b), 7),
          findall(V, trie_gen(T, p(a), V), Found0), msort(Found0, Found),
          assertion(Found == Expected),
          forall(member(Query, [p(a), p(b), p(_), q(a, a), q(a, b), q(_, b),
				q(f(_), _)]),
                 unified_answers(T, Query)) ),
        trie_destroy(T)).

% The hook of the attributes stored_attvar/2 puts: `accept` admits any
% binding and `reject` none.
attr_unify_hook(Mode, _) :-
    Mode == accept.

% Allocate past the global stack, collect and trim, so the query moves.
churn :-
    numlist(1, 5000, L), sum_list(L, _),
    garbage_collect, trim_stacks.

generated_shapes(T) :-
    findall(K, (between(1, 150, _), rich(K)), Keys),
    insert_keys(Keys, T, 1, Pairs),
    forall(( member(K-_, Pairs), copy_term(K, C),
             ( generalize(C, Q) ; specialize(C, Q) ) ),
           same_answers(T, Pairs, Q)),
    forall((between(1, 100, _), rich(Q)), same_answers(T, Pairs, Q)).

rich(T) :- length(Vars, 5), rich(4, Vars, T).
rich(Depth, Vars, T) :-
    random_between(0, 11, Kind),
    (   Kind < 2 -> random_member(T, Vars)
    ;   Kind < 4 -> random_member(T, [a, b, [], 0, 1, -1, 2.5, -0.0, 0.0,
				      "s", "", 98765432109876543210, 1r3])
    ;   Depth =:= 0 -> random_member(T, [a, b, []])
    ;   Next is Depth-1,
        random_member(F/A, [f/1, g/2, h/3, '[|]'/2, z/0, k/5]),
        length(Args, A), maplist(rich(Next, Vars), Args),
        compound_name_arguments(T, F, Args)
    ).

% Replace random subterms by fresh variables.
generalize(T, G) :-
    (   var(T) -> G = T
    ;   random(R), R < 0.25 -> true
    ;   compound(T)
    ->  compound_name_arguments(T, N, As), maplist(generalize, As, Gs),
        compound_name_arguments(G, N, Gs)
    ;   G = T
    ).

% Bind random variables to random terms.  Not forall/2, which would undo
% the bindings.
specialize(T, T) :-
    term_variables(T, Vs),
    maplist(maybe_bind, Vs).

maybe_bind(V) :-
    (   random(R), R < 0.5
    ->  rich(2, [_], V)
    ;   true
    ).

unified_answers(T, Query) :-
    findall(V, trie_gen(T, Query, V), Found0), msort(Found0, Found),
    findall(V, (trie_gen(T, K, V), K = Query), Expected0),
    msort(Expected0, Expected),
    assertion(Found == Expected).

generated(T) :-
    findall(K, (between(1, 100, _), term(K)), Keys),
    insert_keys(Keys, T, 1, Pairs),
    forall((member(K-_, Pairs), copy_term(K, Q)), same_answers(T, Pairs, Q)),
    forall((between(1, 100, _), term(Q)), same_answers(T, Pairs, Q)).

insert_keys([], _, _, []).
insert_keys([K|Ks], T, I, Pairs) :-
    (trie_lookup(T, K, _) -> Pairs = Rest
    ; trie_insert(T, K, I), Pairs = [K-I|Rest]),
    Next is I+1, insert_keys(Ks, T, Next, Rest).

same_answers(T, Pairs, Q) :-
    findall(I-Answer, (member(K-I, Pairs), copy_term(Q-K, Answer-Copy),
                      Answer = Copy, numbervars(Answer, 0, _)), Expected0),
    findall(I-Q, (trie_gen(T, Q, I), numbervars(Q, 0, _)), Actual0),
    sort(Expected0, Expected), sort(Actual0, Actual),
    assertion(Actual == Expected).

term(T) :- length(Vars, 4), term(3, Vars, T).
term(Depth, Vars, T) :-
    random_between(0, 8, Kind),
    (Kind < 2 -> random_member(T, Vars)
    ; Kind =:= 2 -> random_member(T, [a,b,c,0,1,2,3.5,"text",12345678901234567890])
    ; Depth =:= 0 -> random_member(T, [a,b,c])
    ; Next is Depth-1, random_member(F/Arity, [f/1,f/2,g/2,p/3,':'/2]),
      length(Args, Arity), maplist(term(Next, Vars), Args), T =.. [F|Args]).
"""

"The rows: `(id, unit, goal)`; the goal is the plunit test with its options folded by hand."
const _TT_CASES = [
    ("tt01n01", "trie_index", "plunit_trie_index:test(generated_unification)"),
    ("tt01n02", "trie_index", "(plunit_trie_index:test(cyclic_query, O), O = (A == B), A == B)"),
    ("tt01n03", "trie_index", "(plunit_trie_index:test(deleted_pending_answer, true(O)), O = (A == B), A == B)"),
    ("tt01n04", "trie_index", "(plunit_trie_index:test(garbage_collection_between_answers, true(O)), O = (A == B), A == B)"),
    ("tt01n05", "trie_index", "(plunit_trie_index:test(variable_mask_overflow, true(O)), O = (A == B), A == B)"),
    ("tt01n06", "trie_index", "(plunit_trie_index:test(attributed_query, true(O)), O = (A == B), A == B)"),
    ("tt01n07", "trie_index", "plunit_trie_index:test(compound_pop)"),
    ("tt01n08", "trie_index", "plunit_trie_index:test(repeated_variables)"),
    ("tt01n09", "trie_index", "plunit_trie_index:test(stored_attvar_beside_constants)"),
    ("tt01n10", "trie_index", "plunit_trie_index:test(absent_indirect_value)"),
    ("tt01n11", "trie_index", "plunit_trie_index:test(stack_shift_between_answers)"),
    ("tt01n12", "trie_index", "plunit_trie_index:test(insert_between_answers)"),
    ("tt01n13", "trie_index", "(plunit_trie_index:test(delete_between_answers, true(O)), O = (A == B), A == B)"),
    ("tt01n14", "trie_index", "(plunit_trie_index:test(single_match_is_deterministic, O), O = (A == B), A == B)"),
    ("tt01n15", "trie_index", "plunit_trie_index:test(cut_after_pruned_answer)"),
    ("tt01n16", "trie_index", "(plunit_trie_index:test(bound_value, O), O = (A == B), A == B)"),
    ("tt01n17", "trie_index", "plunit_trie_index:test(generated_shapes)"),
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
]

"The files of the program in a fresh directory: one module file per unit, the main file with the rows; returns the main file."
function _tt_materialize()::String
    d = realpath(mktempdir())
    write(joinpath(d, "test_trie_index.pl"), _TT_TAIL)
    for (short, _, text) in _TT_UNITS
        write(
            joinpath(d, "plunit_$short.pl"),
            ":- module(plunit_$short, []).\n:- set_module(base(test_trie_index)).\n" * text
        )
    end
    main = ":- use_module('$d/test_trie_index').\n" * join([":- use_module('$d/plunit_$short').\n" for (short, _, _) in _TT_UNITS])
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

@testset "upstream test_trie_index.pl units 1..1: the kernel answers every row as swipl does" begin
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
