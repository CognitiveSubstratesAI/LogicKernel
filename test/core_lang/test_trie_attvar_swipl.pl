% ORIGINAL: tests/tabling/test_trie_attvars.pl (the pin, 18168e62: simple, plain, nesting, nesting2, shared, unify_true, unify_fail_1/2,
% unify_shared x3, unify_multi, unify_beside_constants(_fail), unify_beside_variable) - the setup written with put_attr/freeze, no dicts.
% test/core_lang/test_trie_attvar_swipl.pl - TR3's rows (O_TRIE_ATTVAR: attributed variables in trie keys). test_trie_attvar_swipl.out
% holds swipl's answers (10.1.20), as the driver of test_trie_attvar_swipl.jl prints them. TWO GROUPS:
%   aN: only trie_insert/4 and trie_term/2, trie_lookup/3 (TR1 + TR3);
%   gN: the upstream tests through trie_gen/2 (TR2's: the .jl runs them once the kernel has trie_gen/2).
% A row never encodes a trie (a blob) nor a node handle: the answers are plain terms.
:- dynamic hooked/1.

even(X) :- X mod 2 =:= 0.
odd(X) :- X mod 2 =:= 1.
yn(G, R) :- ( catch(G, _, fail) -> R = yes ; R = no ).

% ---- group A (TR1 + TR3) ----
a1(R) :- trie_new(T), put_attr(X, a, v), trie_insert(T, f(X), 1, H), trie_term(H, f(Y)), get_attr(Y, a, R).
a2(R) :- trie_new(T), put_attr(X, a, v), trie_insert(T, X, 1, H), trie_term(H, Y), get_attr(Y, a, R).
a3(R) :- trie_new(T), put_attr(X, a, v), trie_insert(T, f(X, a), 1, H), trie_term(H, f(Y, Z)), get_attr(Y, a, V), R = [Z, V].
a4(R) :- trie_new(T), put_attr(X, a, v), trie_insert(T, f(X, g(X, a)), 1, H), trie_term(H, f(Y, Z)),
    ( Z == g(Y, a) -> R1 = same ; R1 = other ), get_attr(Y, a, V), R = [R1, V].
a5(R) :- trie_new(T), put_attr(X, a, v), trie_insert(T, f(X, X), 1, H), trie_term(H, f(Y, Z)),
    ( Y == Z -> R1 = same ; R1 = other ), get_attr(Y, a, V), R = [R1, V].
a6(R) :- trie_new(T), freeze(X, even(X)), trie_insert(T, f(X), 1, H), yn(trie_term(H, f(2)), R).
a7(R) :- trie_new(T), freeze(X, even(X)), trie_insert(T, f(X), 1, H), yn(trie_term(H, f(1)), R).
a8(R) :- trie_new(T), freeze(X, even(X)), trie_insert(T, f(X), 1, H), trie_term(H, f(Y)), yn(Y = 1, R).
a9(R) :- trie_new(T), freeze(X, even(X)), trie_insert(T, f(X, X), 1, H), ( trie_term(H, f(2, Y)) -> R = Y ; R = no ).
a10(R) :- trie_new(T), freeze(X, even(X)), trie_insert(T, f(X, X), 1, H), ( trie_term(H, f(Y, 2)) -> R = Y ; R = no ).
a11(R) :- trie_new(T), freeze(X, even(X)), trie_insert(T, f(X, X), 1, H), freeze(B, Z = z), trie_term(H, f(2, B)), R = [B, Z].
a12(R) :- trie_new(T), freeze(X, even(X)), freeze(Y, odd(Y)), trie_insert(T, f(X, Y), 1, H), yn(trie_term(H, f(2, 1)), R).
a13(R) :- trie_new(T), freeze(X, even(X)), trie_insert(T, f(X), 1, H), trie_insert(T, f(b), 1, _), trie_insert(T, f(c), 1, _),
    yn(trie_term(H, f(2)), R1), yn(trie_term(H, f(1)), R2), R = [R1, R2].
% the lookup of the same frozen variable (its attribute names the variable again) is found, another one is not
a14(R) :- trie_new(T), freeze(X, even(X)), freeze(Y, even(Y)), freeze(Z, odd(Z)), trie_insert(T, f(X), 1, _),
    yn(trie_lookup(T, f(X), _), R1), yn(trie_lookup(T, f(Y), _), R2), yn(trie_lookup(T, f(Z), _), R3), R = [R1, R2, R3].
% two different attributed variables in one key, each with its attributes
a15(R) :- trie_new(T), put_attr(X, a, 1), put_attr(Y, a, 2), trie_insert(T, f(X, Y, X), 1, H), trie_term(H, f(A, B, C)),
    get_attr(A, a, V1), get_attr(B, a, V2), ( A == C -> R1 = same ; R1 = other ), ( A == B -> R2 = same ; R2 = other ), R = [V1, V2, R1, R2].
% a hook that sees the stored attribute: the new attributed variable is bound to a constant
a16(R) :- retractall(hooked(_)), trie_new(T), put_attr(X, user, 1), trie_insert(T, f(X, X), 1, H), trie_term(H, f(b, Y)),
    findall(V, hooked(V), R0), retractall(hooked(_)), R = [Y, R0].
% the second occurrence of a shared attributed variable is unified with what the first one met
a17(R) :- trie_new(T), freeze(X, even(X)), trie_insert(T, f(X, X), 1, H), yn(trie_term(H, f(2, 3)), R).
attr_unify_hook(_, V) :- assertz(hooked(V)).

% ---- group G (trie_gen/2: TR2) ----
g0(R) :- trie_new(T), trie_insert(T, a), trie_gen(T, X), R = X.
g1(R) :- trie_new(T), put_attr(X, a, v), trie_insert(T, f(X)), trie_gen(T, f(Y)), get_attr(Y, a, R).
g2(R) :- trie_new(T), put_attr(X, a, v), trie_insert(T, X), trie_gen(T, Y), get_attr(Y, a, R).
g3(R) :- trie_new(T), put_attr(X, a, v), trie_insert(T, f(X, a)), trie_gen(T, f(Y, Z)), get_attr(Y, a, V), R = [Z, V].
g4(R) :- trie_new(T), put_attr(X, a, v), trie_insert(T, f(X, g(X, a))), trie_gen(T, f(Y, Z)),
    ( Z == g(Y, a) -> R1 = same ; R1 = other ), get_attr(Y, a, V), R = [R1, V].
g5(R) :- trie_new(T), put_attr(X, a, v), trie_insert(T, f(X, X)), trie_gen(T, f(Y, Z)),
    ( Y == Z -> R1 = same ; R1 = other ), get_attr(Y, a, V), R = [R1, V].
g6(R) :- trie_new(T), freeze(X, even(X)), trie_insert(T, f(X)), yn(trie_gen(T, f(2)), R).
g7(R) :- trie_new(T), freeze(X, even(X)), trie_insert(T, f(X)), yn(trie_gen(T, f(1)), R).
g8(R) :- trie_new(T), freeze(X, even(X)), trie_insert(T, f(X)), yn(( trie_gen(T, f(Y)), Y = 1 ), R).
g9(R) :- trie_new(T), freeze(X, even(X)), trie_insert(T, f(X, X)), ( trie_gen(T, f(2, Y)) -> R = Y ; R = no ).
g10(R) :- trie_new(T), freeze(X, even(X)), trie_insert(T, f(X, X)), ( trie_gen(T, f(Y, 2)) -> R = Y ; R = no ).
g11(R) :- trie_new(T), freeze(X, even(X)), trie_insert(T, f(X, X)), freeze(B, Z = z), trie_gen(T, f(2, B)), R = [B, Z].
g12(R) :- trie_new(T), freeze(X, even(X)), freeze(Y, odd(Y)), trie_insert(T, f(X, Y)), yn(trie_gen(T, f(2, 1)), R).
g13(R) :- trie_new(T), freeze(X, even(X)), trie_insert(T, f(X)), trie_insert(T, f(b)), trie_insert(T, f(c)), yn(trie_gen(T, f(2)), R).
g14(R) :- trie_new(T), freeze(X, even(X)), trie_insert(T, f(X)), trie_insert(T, f(b)), trie_insert(T, f(c)), yn(trie_gen(T, f(1)), R).
g15(R) :- trie_new(T), freeze(X, even(X)), trie_insert(T, f(_)), trie_insert(T, f(X)), trie_insert(T, f(b)),
    aggregate_all(count, trie_gen(T, f(2)), R).
