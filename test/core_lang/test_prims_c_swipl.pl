% ORIGINAL: the rows of test/core_lang/test_prims_c_swipl.jl (the predicates are pl-prims.c's: functor/4, nonground/2, '$filled_array'/4, '$unbind_template'/1, '$is_char_code'/1, '$is_char'/1, '$is_code_list'/2, '$is_char_list'/2, collation_key/2).
% test/core_lang/test_prims_c_swipl.pl - PRIMS-C's rows. Each `tN(R)` is one row (a family of cases); test_prims_c_swipl.out holds
% swipl 10.1.20's answers to them, as the test's driver prints them (`ok`, then one line per row: its name and every
% solution). A case answers `ok(Goal)` (the goal after it ran), `fail(Goal)` or `err(Formal, Goal)` (the formal part of the
% error term only); the printed goal shows the variables' sharing (V0, V1, ...), so it holds the bindings too.
% t0-t4 functor/4, t5-t6 nonground/2, t7-t8 '$filled_array'/4, t9 '$unbind_template'/1, t10-t13 the code and char lists,
% t14-t15 '$is_char_code'/1 and '$is_char'/1, t16-t17 collation_key/2 (under the "C" collate locale).
% Characters above 0x7F are written as escapes, so the file is the same in every encoding.

pc_mem(X, [X|_]).
pc_mem(X, [_|T]) :- pc_mem(X, T).
% the answer of one goal
pc(G, R) :- catch(( call(G) -> R = ok(G) ; R = fail(G) ), error(E, _), R = err(E, G)).
% every goal of the list
pcs(Gs, R) :- pc_mem(G, Gs), pc(G, R).
% collation_key/2 goals run under the "C" collate locale, which is put back
ck(G, R) :-
    setup_call_cleanup(setlocale(collate, Old, 'C'), pc(G, R), setlocale(collate, _, Old)).
cks(Gs, R) :- pc_mem(G, Gs), ck(G, R).

% functor/4 on a given term: a compound, an atom, an atomic term
t0(R) :-
    pcs([ functor(foo(a, b), N, A, T),
          functor(foo(a, b), N, A, compound),
          functor(foo(a, b), N, A, callable),
          functor(foo(a, b), N, A, atom),
          functor(foo(a, b), N, A, atomic),
          functor(foo(a, b), foo, 2, compound),
          functor(foo(a, b), bar, 2, compound),
          functor(foo(a, b), foo, 3, compound),
          functor(foo(a, b), N, A, bar),
          functor(foo, N, A, T),
          functor(foo, N, A, atom),
          functor(foo, N, A, callable),
          functor(foo, N, A, compound),
          functor(foo, N, A, atomic),
          functor(foo, foo, 0, atom),
          functor(foo, foo, 1, atom),
          functor(1, N, A, T),
          functor(1, N, A, atomic),
          functor(1, N, A, atom),
          functor(1, N, A, callable),
          functor(1, N, A, compound),
          functor(1, 1, 0, atomic),
          functor(1, 2, 0, atomic),
          functor(1.5, N, A, T),
          functor("str", N, A, T),
          functor("str", N, A, atomic),
          functor(12345678901234567890123, N, A, T),
          functor(1r3, N, A, T),
          functor([], N, A, T),
          functor([], N, A, atom),
          functor([], N, A, atomic),
          functor([a|b], N, A, T),
          functor([a|b], N, A, callable),
          functor('hello world', N, A, T),
          ( put_attr(Xa, dwm, 1), functor(Xa, N, A, T) )
        ], R).

% functor/4: a zero-arity compound, and the Type argument that is no atom
t1(R) :-
    pcs([ ( compound_name_arity(Z, foo, 0), functor(Z, N, A, T) ),
          ( compound_name_arity(Z, foo, 0), functor(Z, N, A, compound) ),
          ( compound_name_arity(Z, foo, 0), functor(Z, N, A, callable) ),
          ( compound_name_arity(Z, foo, 0), functor(Z, N, A, atom) ),
          ( compound_name_arity(Z, foo, 0), functor(Z, N, A, atomic) ),
          functor(foo, N, A, 1),
          functor(foo, N, A, "atom"),
          functor(foo, N, A, f(x)),
          functor(f(a), N, A, 1.5),
          functor(X, foo, 1, 1),
          functor(1, N, A, []),
          functor(X, foo, 1, []),
          functor(X, foo, 0, 7),
          functor(X, N, A, f(a))
        ], R).

% functor/4 building a compound: arity > 0, and the errors of its Name and Arity
t2(R) :-
    pcs([ functor(T, foo, 2, T2),
          functor(T, foo, 2, compound),
          functor(T, foo, 2, callable),
          functor(T, foo, 2, atom),
          functor(T, foo, 2, atomic),
          functor(T, foo, 2, bar),
          functor(T, foo, 3, compound),
          functor(T, 'hello world', 1, compound),
          functor(T, [], 2, compound),
          functor(T, '[|]', 2, compound),
          functor(foo(X, Y), foo, 2, compound),
          functor(foo(X), foo, 2, compound),
          functor(T, N, 2, compound),
          functor(T, foo, A, compound),
          functor(T, foo, a, compound),
          functor(T, foo, -1, compound),
          functor(T, foo, 1.0, compound),
          functor(T, foo, 100000000000000000000, compound),
          functor(T, 1, 2, compound),
          functor(T, "s", 2, compound),
          functor(T, f(x), 2, compound),
          functor(T, 1.5, 1, compound),
          functor(T, 1, 2, atom),
          functor(T, foo, 1, [])
        ], R).

% functor/4 building with arity 0: the Type picks a compound, an atom or an atomic
t3(R) :-
    pcs([ functor(T, foo, 0, compound),
          functor(T, foo, 0, callable),
          functor(T, foo, 0, atom),
          functor(T, foo, 0, atomic),
          functor(T, foo, 0, bar),
          functor(T, foo, 0, T2),
          functor(T, N, 0, atomic),
          functor(T, N, 0, T2),
          functor(T, f(x), 0, atomic),
          functor(T, 1, 0, atomic),
          functor(T, 1, 0, atom),
          functor(T, 1, 0, callable),
          functor(T, 1, 0, compound),
          functor(T, 1, 0, T2),
          functor(T, 1.5, 0, T2),
          functor(T, "s", 0, atomic),
          functor(T, "s", 0, T2),
          functor(T, [], 0, atom),
          functor(T, [], 0, compound),
          functor(T, [], 0, atomic),
          functor(T, foo, 0, 1),
          functor(T, foo, A, atom),
          functor(T, foo, a, atom),
          functor(foo, foo, 0, atom),
          functor(T, 'hello world', 0, callable)
        ], R).

% functor/4: the built term is the term the matching functor/3 builds
t4(R) :-
    pc_mem(Ty, [compound, callable]),
    pc_mem(N-A, [foo-1, foo-5, 'a b'-3, '[|]'-2]),
    ( functor(T, N, A, Ty), functor(T3, N, A), T =@= T3 -> R = same(Ty, N, A)
    ; R = differs(Ty, N, A) ).

% nonground/2: V is the first variable, in the order ground/1 meets them
t5(R) :-
    pcs([ nonground(a, V),
          nonground(f(a, b), V),
          nonground(f(X, Y, X), V),
          nonground(f(Y, X, Y), V),
          nonground(X, V),
          nonground([a, b|T], V),
          nonground(f(g(h(_))), V),
          nonground("s", V),
          nonground(1.5, V),
          nonground(12345678901234567890123, V),
          nonground(f(A, B), A),
          nonground(f(A, B), B),
          nonground(f(A, B), 1),
          nonground(f(A, B), f(x)),
          nonground(f(a, g(B, C), D), V),
          nonground([], V),
          nonground('$VAR'(1), V)
        ], R).

% nonground/2 on a cyclic term and on an attributed variable
ng_first(T, V0, R) :-
    ( nonground(T, V) -> ( V == V0 -> R = first_is_given ; R = first_is_other ) ; R = ground ).
t6(R) :-
    (   X = f(X), ng_first(X, _, R0), R = cyc_ground(R0)
    ;   X = f(X, Y), ng_first(X, Y, R0), R = cyc_var(R0)
    ;   X = [a, b|X], ng_first(X, _, R0), R = cyc_list(R0)
    ;   X = g(Y, X), ng_first(X, Y, R0), R = cyc_var_first(R0)
    ;   X = g(X, Y), ng_first(X, Y, R0), R = cyc_var_last(R0)
    ;   put_attr(X, dwm, 1), ng_first(g(a, X), X, R0), R = attvar(R0)
    ;   put_attr(X, dwm, 1), ng_first(g(Y, X), Y, R0), R = attvar_after(R0)
    ;   put_attr(X, dwm, 1), ng_first(g(X, Y), Y, R0), R = attvar_before(R0)
    ).

% '$filled_array'/4: Compound is Name(Value, ..., Value)
t7(R) :-
    pcs([ '$filled_array'(T, foo, 3, x),
          '$filled_array'(T, foo, 1, x),
          '$filled_array'(T, foo, 0, x),
          '$filled_array'(T, foo, 2, V),
          '$filled_array'(T, foo, 3, V),
          '$filled_array'(T, foo, 2, f(X)),
          '$filled_array'(T, foo, 2, f(X, X)),
          '$filled_array'(T, 'a b', 2, "s"),
          '$filled_array'(T, [], 2, x),
          '$filled_array'(T, foo, 2, [a, b]),
          '$filled_array'(foo(1, 1), foo, 2, 1),
          '$filled_array'(foo(1, 2), foo, 2, 1),
          '$filled_array'(bar(1), foo, 1, 1),
          '$filled_array'(foo(X, Y), foo, 2, 1),
          '$filled_array'(foo(X, X), foo, 2, V),
          '$filled_array'(foo, foo, 0, x),
          '$filled_array'(T, N, 2, x),
          '$filled_array'(T, 1, 2, x),
          '$filled_array'(T, "s", 2, x),
          '$filled_array'(T, f(x), 2, x),
          '$filled_array'(T, foo, A, x),
          '$filled_array'(T, foo, a, x),
          '$filled_array'(T, foo, -1, x),
          '$filled_array'(T, foo, 1.0, x),
          '$filled_array'(T, foo, 100000000000000000000, x)
        ], R).

% '$filled_array'/4: a larger arity, read back
t8(R) :-
    pc_mem(N, [1, 2, 7, 255, 256, 1000, 5000]),
    '$filled_array'(T, foo, N, V),
    functor(T, Name, Ar),
    arg(1, T, A1), arg(N, T, AN),
    ( A1 == V, AN == V -> S = shared ; S = apart ),
    ( N > 1, arg(2, T, A2), A2 == V -> S2 = second_shared ; S2 = no_second ),
    R = N-Name-Ar-S-S2.

% '$unbind_template'/1: the referenced cells are made unbound again
t9(R) :-
    (   T = f(X, Y), term_variables(T, Vs), Tpl =.. [v|Vs], X = 1, Y = 2,
        '$unbind_template'(Tpl),
        ( var(X), var(Y) -> R = unbound_two ; R = still_bound(X, Y) )
    ;   T = f(X, g(Y, Z)), term_variables(T, Vs), Tpl =.. [v|Vs], X = 1, Y = g(a), Z = "s",
        '$unbind_template'(Tpl),
        ( var(X), var(Y), var(Z) -> R = unbound_three ; R = still_bound(X, Y, Z) )
    ;   T = f(X, Y), term_variables(T, Vs), Tpl =.. [v|Vs], X = 1,
        '$unbind_template'(Tpl),
        ( var(X), var(Y) -> R = unbound_one_of_two ; R = still_bound(X, Y) )
    ;   T = f(X), term_variables(T, Vs), Tpl =.. [v|Vs],
        '$unbind_template'(Tpl),
        ( var(X) -> R = was_unbound ; R = bound(X) )
    ;   pc('$unbind_template'(foo), R)
    ;   pc('$unbind_template'([]), R)
    ;   pc('$unbind_template'(1), R)
    ;   pc('$unbind_template'(1.5), R)
    ;   pc('$unbind_template'("s"), R)
    ;   pc('$unbind_template'(_), R)
    ;   pc('$unbind_template'(v(a)), R)
    ;   pc('$unbind_template'(v(a, b)), R)
    ;   pc('$unbind_template'([a]), R)
    ;   pc('$unbind_template'(f(_)), R)
    ;   pc('$unbind_template'(f(_, _)), R)
    ;   compound_name_arity(Z0, v, 0), pc('$unbind_template'(Z0), R)
    ;   T = f(X, Y), term_variables(T, Vs), Tpl =.. [v|Vs], pc('$unbind_template'(Tpl), R0),
        R = tpl(R0), var(X), var(Y)
    ).

% '$is_code_list'/2 on short lists
t10(R) :-
    pcs([ '$is_code_list'([], N),
          '$is_code_list'([97], N),
          '$is_code_list'([97, 98, 99], N),
          '$is_code_list'([97, 98, 99], 3),
          '$is_code_list'([97, 98, 99], 2),
          '$is_code_list'([97, 98, 99], a),
          '$is_code_list'([0], N),
          '$is_code_list'([0, 1114111], N),
          '$is_code_list'([1114112], N),
          '$is_code_list'([55295, 57344], N),
          '$is_code_list'([55296], N),
          '$is_code_list'([57343], N),
          '$is_code_list'([-1], N),
          '$is_code_list'([97, -1], N),
          '$is_code_list'([97, a], N),
          '$is_code_list'([97, 1.0], N),
          '$is_code_list'([97, "a"], N),
          '$is_code_list'([97, _], N),
          '$is_code_list'([97, 1180591620717411303424], N),
          '$is_code_list'([a, b], N),
          '$is_code_list'([97|_], N),
          '$is_code_list'([97|foo], N),
          '$is_code_list'([97, 98|c], N),
          '$is_code_list'(foo, N),
          '$is_code_list'("abc", N),
          '$is_code_list'(_, N),
          '$is_code_list'(f(97), N),
          '$is_code_list'([[97]], N),
          '$is_code_list'(97, N)
        ], R).

% '$is_char_list'/2 on short lists
t11(R) :-
    pcs([ '$is_char_list'([], N),
          '$is_char_list'([a], N),
          '$is_char_list'([a, b, c], N),
          '$is_char_list'([a, b, c], 3),
          '$is_char_list'([a, b, c], 2),
          '$is_char_list'([a, b, c], a),
          '$is_char_list'(['\x20AC\', 'e\x301\'], N),
          '$is_char_list'(['\x20AC\', b], N),
          '$is_char_list'([a, ab], N),
          '$is_char_list'([a, ''], N),
          '$is_char_list'([a, []], N),
          '$is_char_list'([a, 1], N),
          '$is_char_list'([a, "b"], N),
          '$is_char_list'([a, _], N),
          '$is_char_list'([a, f(b)], N),
          '$is_char_list'([97, 98], N),
          '$is_char_list'([a|_], N),
          '$is_char_list'([a|foo], N),
          '$is_char_list'([a, b|c], N),
          '$is_char_list'(foo, N),
          '$is_char_list'("abc", N),
          '$is_char_list'(_, N),
          '$is_char_list'(f(a), N),
          '$is_char_list'([[a]], N),
          '$is_char_list'(a, N)
        ], R).

% '$is_code_list'/2 on long lists (the 1000th element is where upstream looks for a cycle), with every kind of tail
t12(R) :-
    pc_mem(N, [0, 1, 999, 1000, 1001, 1500]),
    length(L0, N), maplist(=(97), L0),
    pc_mem(Tl-T, [nil-[], bad-[-1], partial-[97|_], atom-foo, cyc-T0]),
    ( Tl == cyc -> T0 = [97|T0] ; true ),
    append(L0, T, L),
    (   catch('$is_code_list'(L, Len), error(E, _), Len = err(E))
    ->  R = N-Tl-ok(Len)
    ;   R = N-Tl-fail
    ).

% '$is_char_list'/2 on long lists
t13(R) :-
    pc_mem(N, [0, 1, 999, 1000, 1001, 1500]),
    length(L0, N), maplist(=(a), L0),
    pc_mem(Tl-T, [nil-[], bad-[ab], partial-[a|_], atom-foo, cyc-T0]),
    ( Tl == cyc -> T0 = [a|T0] ; true ),
    append(L0, T, L),
    (   catch('$is_char_list'(L, Len), error(E, _), Len = err(E))
    ->  R = N-Tl-ok(Len)
    ;   R = N-Tl-fail
    ).

% '$is_char_code'/1
t14(R) :-
    pc_mem(V, [0, 1, 97, 127, 255, 256, 65535, 65536, 1114111, 1114112, 55295, 55296, 56319, 56320, 57343, 57344,
               -1, -2, 1180591620717411303424, -1180591620717411303424, 1.0, 97.0, a, "a", [], [97], f(97), _, 0'a, 8364]),
    pc('$is_char_code'(V), R).

% '$is_char'/1
t15(R) :-
    pc_mem(V, [a, z, 'A', ' ', '\x7f\', '\xe9\', '\x20AC\', ab, '', [], '[]', '{}', "a", "", 97, 1.5, f(a), _, 'e\x301\',
               [a], '\x1F600\', '\x1F600\a', '\x10FFFF\']),
    pc('$is_char'(V), R).

% collation_key/2 under the "C" locale: the key is the text itself
t16(R) :-
    cks([ collation_key(abc, K),
          collation_key("abc", K),
          collation_key('', K),
          collation_key("", K),
          collation_key('caf\xe9\', K),
          collation_key('a\x20AC\b', K),
          collation_key('\x1F600\a', K),
          collation_key('Hello World', K),
          collation_key('[]', K),
          collation_key(abc, "abc"),
          collation_key(abc, abc),
          collation_key(abc, "abd"),
          collation_key(abc, 1),
          collation_key(abc, f(x)),
          collation_key(abc, K2),
          collation_key(X, K),
          collation_key(f(x), K),
          collation_key(123, K),
          collation_key(1.5, K),
          collation_key([a, b], K),
          collation_key([], K),
          collation_key(1r3, K),
          ( string_codes(S, [97, 0, 98]), collation_key(S, K) )
        ], R).

% collation_key/2: texts around the 256-wide first buffer
t17(R) :-
    pc_mem(N, [1, 255, 256, 257, 300, 1000]),
    length(L, N), maplist(=(0'x), L), atom_codes(A, L),
    ck(collation_key(A, K), R0),
    (   R0 = ok(collation_key(_, K1)), string_length(K1, KL), string_codes(K1, KC)
    ->  ( KC == L -> Same = same ; Same = differs ), R = N-KL-Same
    ;   R = N-R0
    ).
