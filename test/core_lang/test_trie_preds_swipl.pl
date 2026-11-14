% ORIGINAL: the rows of test/core_lang/test_trie_preds_swipl.jl - no swipl-devel counterpart.
% test/core_lang/test_trie_preds_swipl.pl - TR1's rows (pl-trie.c: trie_new/1, trie_destroy/1, is_trie/1, trie_insert/2,3,4,
% trie_update/3, trie_delete/3, trie_lookup/3, trie_term/2, '$trie_insert_abstract'/3). Each `tN(R)` is one row;
% test_trie_preds_swipl.out holds swipl's answers (10.1.20, pin 18168e62), as the test's driver prints them (`ok`, then one
% line per row: its name and every solution). A row never encodes a trie (a blob has no stable text) nor a node handle (swipl's
% is a pointer, the kernel's an integer): an error that names a trie goes through scrub/3, a handle goes only to trie_term/2.
% The value of a trie that is a SET (trie_insert/2) is a reserved blob: sv/2 reads it as `set_value`. The rows that swipl
% answers and the kernel answers differently BY DESIGN (a bad handle, an attributed variable in a key) are not here: the .jl
% holds them as named known-difference rows.
:- dynamic hooked/1.

mem(X, [X|_]).
mem(X, [_|T]) :- mem(X, T).
mapres([], []).
mapres([G|Gs], [R|Rs]) :- res(G, R), mapres(Gs, Rs).
mapres_t(_, [], []).
mapres_t(Tr, [G|Gs], [R|Rs]) :- rt(Tr, G, R), mapres_t(Tr, Gs, Rs).
numl(L, H, []) :- L > H, !.
numl(L, H, [L|T]) :- L1 is L + 1, numl(L1, H, T).
res(G, R) :- catch(( G -> R = true ; R = false ), error(E, C), R = error(E, C)).
% the same, the trie `Tr` in the error replaced by '<trie>'
rt(Tr, G, R) :- catch(( G -> R = true ; R = false ), error(E, C), ( scrub(E, Tr, E1), R = error(E1, C) )).
scrub(V, _, V) :- var(V), !.
scrub(T, Tr, '<trie>') :- T == Tr, !.
scrub(T, Tr, S) :- compound(T), !, T =.. [F|As], scrubs(As, Tr, Bs), S =.. [F|Bs].
scrub(T, _, T).
scrubs([], _, []).
scrubs([A|As], Tr, [B|Bs]) :- scrub(A, Tr, B), scrubs(As, Tr, Bs).
sv(V, R) :- \+ atom(V), atomic(V), \+ number(V), \+ string(V), !, R = set_value.
sv(V, V).
% a goal list over a trie argument that is not a live trie
tg(X, [trie_insert(X, a), trie_insert(X, a, 1), trie_insert(X, a, 1, _), trie_update(X, a, 1), trie_delete(X, a, _),
       trie_lookup(X, a, _), '$trie_insert_abstract'(X, 1, a), trie_destroy(X)]).
ins(T, Ks, Rs) :- findall(R, ( mem(K, Ks), res(trie_insert(T, K), R) ), Rs).
look(T, Ks, Rs) :- findall(K-S, ( mem(K, Ks), trie_lookup(T, K, V), sv(V, S) ), Rs).
found(T, Ks, Rs) :- findall(K, ( mem(K, Ks), trie_lookup(T, K, _) ), Rs).
big(X) :- X is 1 << 100.
nbig(X) :- X is -(1 << 64).

% t0..t7: trie_new/1, is_trie/1, trie_destroy/1
t0(R) :- trie_new(T), ( is_trie(T) -> R = ok ; R = no ).
t1(R) :- findall(X-Y, ( mem(X, [foo, 1, 2.5, "s", f(x), [], a]), ( is_trie(X) -> Y = yes ; Y = no ) ), R).
t2(R) :- res(is_trie(_), R).
t3(R) :- trie_new(T), trie_destroy(T), ( is_trie(T) -> R = yes ; R = no ).
t4(R) :- trie_new(T), trie_destroy(T), rt(T, trie_destroy(T), R).
t5(R) :- mapres([trie_destroy(foo), trie_destroy(_), trie_destroy(1), trie_destroy("s"), trie_destroy(f(x))], R).
t6(R) :- trie_new(T), mapres([trie_new(foo), trie_new(f(_)), trie_new(1), trie_new(T)], R).
t7(R) :- trie_new(T), trie_new(T2), copy_term(T, T3),
    ( T == T2 -> A = same ; A = different ), ( T == T -> B = same ; B = different ), ( T == T3 -> C = same ; C = different ),
    ( is_trie(T3) -> D = trie ; D = no ), R = [A, B, C, D].

% t8..t13: every predicate on something that is not a live trie (type_error(trie, _), instantiation_error, existence_error)
t8(R) :- tg(foo, Gs), mapres(Gs, R).
t9(R) :- tg(_, Gs), mapres(Gs, R).
t10(R) :- tg(1, Gs), mapres(Gs, R).
t11(R) :- tg("s", Gs), mapres(Gs, R).
t12(R) :- tg(f(x), Gs), mapres(Gs, R).
t13(R) :- trie_new(T), trie_destroy(T), tg(T, Gs), mapres_t(T, Gs, R).

% t14..t17: the two kinds of trie: a set (no values) and a map (values), and what a destroyed one answers
t14(R) :- trie_new(T), trie_insert(T, a),
    rt(T, trie_insert(T, b, 1), R1), rt(T, trie_insert(T, b, 1, _), R2), rt(T, trie_update(T, b, 1), R3),
    ( trie_lookup(T, b, _) -> R4 = found ; R4 = absent ), ( trie_insert(T, b) -> R5 = inserted ; R5 = failed ),
    R = [R1, R2, R3, R4, R5].
t15(R) :- trie_new(T), trie_insert(T, a, 1),
    rt(T, trie_insert(T, b), R1), rt(T, trie_insert(T, c, 1), R2), rt(T, trie_update(T, d, 1), R3), trie_lookup(T, c, V),
    R = [R1, R2, R3, V].
t16(R) :- trie_new(T), rt(T, trie_update(T, k, 1), R1), rt(T, trie_insert(T, k, 2), R2), trie_lookup(T, k, V), R = [R1, R2, V].
t17(R) :- trie_new(T), res(trie_insert(T, k, _), R1), rt(T, trie_insert(T, j), R2), res(trie_insert(T, k, _), R3), res(trie_insert(T, k, v), R4),
    R = [R1, R2, R3, R4].

% t18..t23: insert/2 of ground terms of every kind; the second insert fails; lookup gives the set value
t18(R) :- trie_new(T), big(B), nbig(NB),
    Ks = [a, 'B c', '', 0, 1, -1, 123456789012345, 4611686018427387904, B, NB, 1.5, "s", "", f(x), f(g(a), h(b, c)), [], '[]', [a, b|c], [1, 2, 3]],
    ins(T, Ks, R1), ins(T, Ks, R2), look(T, Ks, R3), R = R1-R2-R3.
t19(R) :- trie_new(T), big(B), nbig(NB), Ks = [a, 1, 1.5, "s", f(x), B, NB, '1', "1", 1.0],
    ins(T, Ks, R1), found(T, Ks, R2), found(T, [b, 2, 1.25, "t", f(y), '', 2.5], R3), R = R1-R2-R3.
t20(R) :- trie_new(T), X1 is 0.0, X2 is -0.0, Y is 1.0, Z is 1,
    res(trie_insert(T, X1), R1), res(trie_insert(T, X2), R2), res(trie_insert(T, Y), R3), res(trie_insert(T, Z), R4),
    res(trie_insert(T, X1), R5), res(trie_insert(T, X2), R6), res(trie_insert(T, Y), R7), res(trie_insert(T, Z), R8),
    R = [R1, R2, R3, R4, R5, R6, R7, R8].
t21(R) :- trie_new(T), X is nan, Y is inf, Z is -inf,
    res(trie_insert(T, X), R1), res(trie_insert(T, Y), R2), res(trie_insert(T, Z), R3),
    res(trie_insert(T, Y), R4), res(trie_insert(T, Z), R5), res(trie_insert(T, X), R6),
    ( trie_lookup(T, X, _) -> R7 = found ; R7 = absent ), ( trie_lookup(T, Y, _) -> R8 = found ; R8 = absent ),
    ( trie_lookup(T, Z, _) -> R9 = found ; R9 = absent ),
    R = [R1, R2, R3, R4, R5, R6, R7, R8, R9].
t22(R) :- trie_new(T), A is 1 rdiv 3, B is 2 rdiv 3,
    res(trie_insert(T, A), R1), res(trie_insert(T, B), R2), res(trie_insert(T, A), R3),
    ( trie_lookup(T, A, _) -> R4 = found ; R4 = absent ), C is 1 rdiv 3, ( trie_lookup(T, C, _) -> R5 = found ; R5 = absent ),
    R = [R1, R2, R3, R4, R5].
t23(R) :- trie_new(T), big(B), B2 is B + 1, B3 is 1 << 100,
    res(trie_insert(T, B), R1), res(trie_insert(T, B2), R2), res(trie_insert(T, B3), R3),
    ( trie_lookup(T, B, _) -> R4 = found ; R4 = absent ), ( trie_lookup(T, B3, _) -> R5 = found ; R5 = absent ),
    ( trie_lookup(T, 1, _) -> R6 = found ; R6 = absent ),
    R = [R1, R2, R3, R4, R5, R6].

% t24..t29: a map: values of every kind come back; the second insert of the same value fails, another value is a permission error
t24(R) :- trie_new(T), big(Big), nbig(NB),
    KVs = [a-b, k1-1, k2-1.5, k3-"str", k4-Big, k5-NB, k6-f(x, g(y)), k7-[a, b, c], k8-[], k9-'', k10-f(A, _, A), k11-g(C, C), k12-_, 1-one, 1.0-onef, "1"-str, '1'-atom],
    findall(R1, ( mem(K-V, KVs), res(trie_insert(T, K, V), R1) ), Rs1),
    findall(K-V2, ( mem(K-_, KVs), trie_lookup(T, K, V2) ), Rs2),
    R = Rs1-Rs2.
t25(R) :- trie_new(T), trie_insert(T, k, v),
    res(trie_insert(T, k, v), R1), res(trie_insert(T, k, w), R2), res(trie_insert(T, k, f(_)), R3), trie_lookup(T, k, V),
    R = [R1, R2, R3, V].
t26(R) :- trie_new(T), trie_insert(T, f(_, _), 1),
    res(trie_insert(T, f(_, _), 1), R1), res(trie_insert(T, f(_, _), 2), R2), res(trie_insert(T, f(Z, Z), 2), R3),
    res(trie_insert(T, f(Z, Z), 3), R4), res(trie_insert(T, g(a), 3), R5),
    R = [R1, R2, R3, R4, R5].
t27(R) :- trie_new(T), trie_insert(T, f(X, Y), g(Y, X)), trie_insert(T, h(X), X), trie_insert(T, i, j(_, _)),
    trie_lookup(T, f(A, B), V1), trie_lookup(T, f(C, D), V2), trie_lookup(T, h(E), V3), trie_lookup(T, h(F), V4),
    trie_lookup(T, i, V5), trie_lookup(T, i, V6), R = [V1, V2, V3, V4, V5, V6, A, B, C, D, E, F].
t28(R) :- trie_new(T), trie_insert(T, x, v),
    ( trie_lookup(T, x, v) -> R1 = v ; R1 = no ), ( trie_lookup(T, x, w) -> R2 = w ; R2 = no ),
    ( trie_lookup(T, x, f(_)) -> R3 = f ; R3 = no ), ( trie_lookup(T, y, _) -> R4 = y ; R4 = no ),
    R = [R1, R2, R3, R4].
t29(R) :- trie_new(T), trie_insert(T, f(X, Y), g(X, Y, X)), trie_lookup(T, f(A, B), g(P, Q, S)), R = [A, B, P, Q, S, X, Y].

% t30..t34: trie_update/3
t30(R) :- trie_new(T), res(trie_update(T, k, 1), R1), trie_lookup(T, k, V1), res(trie_update(T, k, 2), R2), trie_lookup(T, k, V2),
    res(trie_update(T, k, 2), R3), trie_lookup(T, k, V3), res(trie_update(T, j, f(_)), R4), trie_lookup(T, j, V4),
    R = [R1, V1, R2, V2, R3, V3, R4, V4].
t31(R) :- trie_new(T), trie_insert(T, k, 1), res(trie_update(T, k, 2), R1), trie_lookup(T, k, V), res(trie_insert(T, k, 2), R2),
    res(trie_insert(T, k, 1), R3), R = [R1, V, R2, R3].
t32(R) :- trie_new(T), trie_update(T, f(X, _, X), a), res(trie_update(T, f(A, B, A), b), R1), trie_lookup(T, f(C, _, C), V),
    res(trie_update(T, f(A, B, B), c), R2), res(trie_update(T, f(1, 2, 1), d), R3), trie_lookup(T, f(A, B, B), V2),
    R = [R1, V, R2, R3, V2].
t33(R) :- trie_new(T), trie_update(T, x, v), trie_update(T, y, v), trie_update(T, x, _), trie_lookup(T, x, V1), trie_lookup(T, y, V2),
    trie_update(T, x, f(_)), trie_lookup(T, x, V3), R = [V1, V2, V3].
t34(R) :- findall(A-B, ( mem(A, [foo, 1, 2.5]), trie_new(T), trie_insert(T, z), rt(T, trie_update(T, A, v), B) ), R).

% t35..t40: trie_delete/3
t35(R) :- trie_new(T), trie_insert(T, k, v), res(trie_delete(T, k, z), R1), ( trie_lookup(T, k, _) -> R2 = kept ; R2 = gone ),
    res(trie_delete(T, k, V), R3), ( trie_lookup(T, k, _) -> R4 = kept ; R4 = gone ), res(trie_delete(T, k, _), R5),
    res(trie_delete(T, q, _), R6), R = [R1, R2, R3, V, R4, R5, R6].
t36(R) :- trie_new(T), trie_insert(T, k), res(trie_delete(T, k, V), R1), sv(V, S), res(trie_delete(T, k, _), R2),
    res(trie_insert(T, k), R3), R = [R1, S, R2, R3].
t37(R) :- trie_new(T), trie_insert(T, k, f(1, 2)), res(trie_delete(T, k, f(1, Z)), R1), R = [R1, Z].
t38(R) :- trie_new(T), trie_insert(T, k, f(1, 2)), res(trie_delete(T, k, f(2, _)), R1), res(trie_delete(T, k, g(_, _)), R2),
    ( trie_lookup(T, k, f(1, 2)) -> R3 = kept ; R3 = gone ), R = [R1, R2, R3].
t39(R) :- trie_new(T), trie_insert(T, k, v), trie_delete(T, k, v), res(trie_insert(T, k, w), R1), trie_lookup(T, k, V),
    res(trie_insert(T, k, w), R2), trie_delete(T, k, w), res(trie_update(T, k, x), R3), trie_lookup(T, k, V3),
    R = [R1, V, R2, R3, V3].
t40(R) :- trie_new(T), trie_insert(T, f(X, _, X), 1), trie_insert(T, f(_, Y, Y), 2), trie_insert(T, f(a, _, _), 3),
    res(trie_delete(T, f(A, B, B), V), R1), res(trie_delete(T, f(A, B, B), V), R2), trie_lookup(T, f(C, _, C), V2),
    trie_lookup(T, f(a, _, _), V3), R = [R1, V, R2, V2, V3].

% t41..t46: trie_lookup/3: variant matching
t41(R) :- trie_new(T), trie_insert(T, f(_, _, _), v), trie_new(T2), trie_insert(T2, f(X, _, X), v),
    findall(G, ( mem(G, [f(A, B, A), f(A, B, B), f(A, B, C), f(1, 2, 1), f(A, A, A), f(_, _), g(_, _, _), _, a, f(A, B, A, C)]), trie_lookup(T2, G, _) ), Gs),
    findall(G, ( mem(G, [f(A, B, A), f(A, B, B), f(A, B, C), f(1, 2, 1), f(A, A, A), f(_, _), g(_, _, _), _, a]), trie_lookup(T, G, _) ), Gs2),
    R = Gs-Gs2.
t42(R) :- trie_new(T), trie_insert(T, g(X, h(X)), 1), trie_insert(T, g(X, h(Y)), 2), trie_insert(T, h(X, X), 3), trie_insert(T, h(X, Y), 4),
    trie_insert(T, h(X, f(Y, X, Y)), 5), trie_lookup(T, g(A, h(A)), V1), trie_lookup(T, g(A, h(B)), V2), trie_lookup(T, h(A, A), V3),
    trie_lookup(T, h(A, B), V4), trie_lookup(T, h(A, f(B, A, B)), V5),
    ( trie_lookup(T, h(A, f(B, B, A)), _) -> V6 = yes ; V6 = no ), R = [V1, V2, V3, V4, V5, V6].
t43(R) :- trie_new(T), trie_insert(T, _, v), findall(K, ( mem(K, [x, f(_), _, 1, "s"]), trie_lookup(T, K, _) ), Ks), R = Ks.
t44(R) :- trie_new(T), trie_insert(T, f(_), v), findall(K, ( mem(K, [x, f(_), f(a), f(f(_)), _, f(_, _)]), trie_lookup(T, K, _) ), Ks), R = Ks.
t45(R) :- trie_new(T), trie_insert(T, p, v), trie_lookup(T, p, V1), trie_lookup(T, p, V2), R = [V1, V2].
t46(R) :- trie_new(T), trie_insert(T, [X, Y|X], v), trie_insert(T, [X, Y|Y], w), trie_lookup(T, [A, B|A], V1), trie_lookup(T, [A, B|B], V2),
    ( trie_lookup(T, [A, B|_], _) -> V3 = yes ; V3 = no ), R = [V1, V2, V3].

% t47..t52: trie_insert/4 + trie_term/2 (the handle itself is never printed)
t47(R) :- trie_new(T), trie_insert(T, a, 1, H), trie_term(H, A), R = A.
t48(R) :- trie_new(T), big(B), Ks = [a, 1, -7, 1.5, "s", "", f(a), f(a, g(b, 1)), [], [a, b], [1, 2|c], B, f(B, 2.5, "t")],
    findall(K, ( mem(K, Ks), trie_insert(T, K, v, H), trie_term(H, K2), K2 == K ), Ok), length(Ok, N), length(Ks, N),
    findall(K2, ( mem(K, Ks), trie_lookup(T, K, _), trie_new(T2), trie_insert(T2, K, 0, H2), trie_term(H2, K2) ), Back),
    R = N-Back.
t49(R) :- trie_new(T), trie_insert(T, f(X, Y, X), v, H1), trie_insert(T, g(X, h(X, Y), Y), v, H2), trie_insert(T, Z, v, H3),
    trie_insert(T, [X, Y|X], v, H4), trie_insert(T, f(Z, Z), v, H5), trie_term(H1, A), trie_term(H2, B), trie_term(H3, C),
    trie_term(H4, D), trie_term(H5, E), R = [A, B, C, D, E].
t50(R) :- trie_new(T), trie_insert(T, f(a, b), 1, H1), trie_insert(T, f(a, c), 2, H2), trie_insert(T, f(b, b), 3, H3), trie_insert(T, f(a), 4, H4),
    trie_insert(T, f, 5, H5), trie_insert(T, f(a, b, c), 6, H6),
    trie_term(H1, A1), trie_term(H2, A2), trie_term(H3, A3), trie_term(H4, A4), trie_term(H5, A5), trie_term(H6, A6),
    trie_delete(T, f(a, c), _), trie_term(H1, B1), trie_term(H3, B3), R = [A1, A2, A3, A4, A5, A6, B1, B3].
t51(R) :- trie_new(T), trie_insert(T, f(_, _), v, H), trie_term(H, A), trie_term(H, B),
    ( trie_term(H, f(1, 2)) -> R1 = bound ; R1 = no ), ( trie_term(H, f(Z, Z)) -> R2 = bound ; R2 = no ),
    ( trie_term(H, g(_, _)) -> R3 = bound ; R3 = no ), trie_term(H, f(P, Q)), R = [A, B, R1, R2, R3, P, Q].
t52(R) :- trie_new(T), trie_insert(T, a, 1, H), res(trie_insert(T, a, 1, _), R1), res(trie_insert(T, a, 1, foo), R2), res(trie_insert(T, b, 1, foo), R3),
    res(trie_insert(T, a, 2, _), R4), ( trie_term(H, a) -> R5 = a ; R5 = no ), R = [R1, R2, R3, R4, R5].

% t53..t55: trie_term/2 on something that is not a handle (swipl: type_error(address, _); the kernel's own text is in the .jl)
t53(R) :- res(trie_term(_, _), R).
t54(R) :- trie_new(T), trie_insert(T, a, 1, H), ( trie_term(H, b) -> R = yes ; R = no ).
t55(R) :- trie_new(T), trie_insert(T, a, 1, H), trie_destroy(T), ( is_trie(T) -> R1 = yes ; R1 = no ), ( integer(H) -> R2 = integer ; R2 = other ), R = [R1, R2].

% t56..t64: '$trie_insert_abstract'/3
abs(Size, Ks, Qs, R) :- trie_new(T), findall(Ok, ( mem(K, Ks), res('$trie_insert_abstract'(T, Size, K), Ok) ), Oks),
    findall(Q, ( mem(Q, Qs), trie_lookup(T, Q, _) ), Found), R = Oks-Found.
t56(R) :- abs(1, [f(g(a)), f(g(b)), f(g(h(c))), f(h(b)), f(a), f(b), f(g(a), b), f(g(a), c)],
    [f(g(_)), f(g(a)), f(_), f(a), f(h(_)), f(g(h(c))), f(g(h(_))), f(g(a), b), f(g(a), _), f(g(a), c)], R).
t57(R) :- abs(2, [f(g(a)), f(g(b)), f(g(h(c))), f(g(h(d))), f(g(h(d(e)))), f(g(h(d(f))))],
    [f(g(a)), f(g(h(_))), f(g(h(c))), f(g(h(d))), f(g(h(d(_)))), f(g(h(d(e))))], R).
t58(R) :- abs(0, [g(a), g(b), a, a, [a], [b], f(X, X), f(X, _), X], [g(_), g(a), a, [_], [a], f(_, _), _], R).
t59(R) :- abs(1, [a, a, [a, b, c], [a, b, d], [a, c], [a, b|c], X, f(X, Y, X), f(X, Y, Y)], [a, [a, b, c], [a, c], [a|_], [_|_], _, f(A, _, A)], R).
t60(R) :- abs(3, [f(g(h(i(a)))), f(g(h(i(b)))), f(g(h(i(j(a))))), f(g(h(i(j(b))))), [1, 2, 3, 4, 5], [1, 2, 3, 4, 6]], [f(g(h(i(a)))), f(g(h(i(j(a))))), f(g(h(i(_)))), [1, 2, 3, 4, 5], [1, 2, 3|_]], R).
t61(R) :- trie_new(T), trie_insert(T, a, 1, _), rt(T, '$trie_insert_abstract'(T, 1, b), R1), R = R1.
t62(R) :- trie_new(T), mapres(['$trie_insert_abstract'(T, foo, a), '$trie_insert_abstract'(T, -1, a), '$trie_insert_abstract'(T, _, a),
    '$trie_insert_abstract'(T, 1.5, a), '$trie_insert_abstract'(T, "1", a), '$trie_insert_abstract'(T, f(x), a)], R).
t63(R) :- trie_new(T), X is 1 << 70, res('$trie_insert_abstract'(T, X, f(a)), R1), res('$trie_insert_abstract'(T, 9223372036854775807, f(a)), R2),
    R = [R1, R2].
t64(R) :- trie_new(T), '$trie_insert_abstract'(T, 1, f(g(a))), res(trie_insert(T, f(g(a))), R1), res(trie_insert(T, f(g(b))), R2),
    res('$trie_insert_abstract'(T, 1, f(g(a))), R3), res('$trie_insert_abstract'(T, 1, f(g(b))), R4), R = [R1, R2, R3, R4].

% t65..t69: bigger tries (children hash tables grow, chains, lists, deep terms)
t65(R) :- trie_new(T), findall(I, ( between(1, 300, I), trie_insert(T, I) ), Is), length(Is, N1),
    findall(I, ( between(1, 300, I), \+ trie_insert(T, I) ), Js), length(Js, N2),
    findall(I, ( between(1, 300, I), trie_lookup(T, I, _) ), Ls), length(Ls, N3),
    findall(I, ( between(301, 320, I), trie_lookup(T, I, _) ), Ms), length(Ms, N4), R = [N1, N2, N3, N4].
t66(R) :- trie_new(T), findall(I, ( between(1, 200, I), atom_concat(k, I, K), trie_insert(T, f(K, g(I)), I) ), Is), length(Is, N1),
    findall(I, ( between(1, 200, I), atom_concat(k, I, K), trie_lookup(T, f(K, g(I)), V), V =:= I ), Vs), length(Vs, N6),
    findall(I, ( between(1, 200, I), I mod 2 =:= 0, atom_concat(k, I, K), trie_delete(T, f(K, g(I)), _) ), Ds), length(Ds, N2),
    findall(I, ( between(1, 200, I), atom_concat(k, I, K), trie_lookup(T, f(K, g(I)), _) ), Ls), length(Ls, N3),
    findall(I, ( between(1, 200, I), I mod 2 =:= 0, atom_concat(k, I, K), trie_insert(T, f(K, g(I)), I) ), Rs), length(Rs, N4),
    findall(I, ( between(1, 200, I), atom_concat(k, I, K), trie_lookup(T, f(K, g(I)), _) ), Ls2), length(Ls2, N5),
    R = [N1, N6, N2, N3, N4, N5].
t67(R) :- trie_new(T), numl(1, 1500, L), trie_insert(T, L, long, H), trie_lookup(T, L, V), trie_term(H, L2),
    ( L2 == L -> R1 = same ; R1 = different ), numl(1, 1499, L3), ( trie_lookup(T, L3, _) -> R2 = found ; R2 = absent ), R = [V, R1, R2].
t68(R) :- trie_new(T), deep(1000, D), trie_insert(T, D, deep, H), trie_lookup(T, D, V), trie_term(H, D2), ( D2 == D -> R1 = same ; R1 = different ),
    deep(999, D3), ( trie_lookup(T, D3, _) -> R2 = found ; R2 = absent ), res(trie_insert(T, D, deep), R3), R = [V, R1, R2, R3].
deep(0, a) :- !.
deep(N, f(D)) :- N1 is N - 1, deep(N1, D).
t69(R) :- trie_new(T), findall(I, ( between(1, 60, I), trie_insert(T, f(I, X, X, I), I) ), Ks), length(Ks, N1),
    findall(I, ( between(1, 60, I), trie_lookup(T, f(I, A, A, I), V), V =:= I ), Vs), length(Vs, N2),
    findall(I, ( between(1, 60, I), trie_lookup(T, f(I, _, _, I), _) ), Ws), length(Ws, N3), R = [N1, N2, N3].

% t70..t73: cyclic terms and attributed variables
t70(R) :- trie_new(T), trie_new(M), trie_insert(M, k, 0), X = f(X),
    cyc(trie_insert(T, X), R1), cyc(trie_insert(M, X, k), R2), cyc(trie_lookup(M, X, _), R3), cyc(trie_delete(M, X, _), R4),
    cyc(trie_update(M, X, 1), R5), cyc(trie_lookup(T, X, _), R6), R = [R1, R2, R3, R4, R5, R6].
cyc(G, R) :- catch(( G -> R = true ; R = false ), error(type_error(K, _), C), R = type_error(K, C)).
t71(R) :- trie_new(T), put_attr(X, user, 1), trie_insert(T, a, 1, H), trie_term(H, X), findall(V, hooked(V), R0), retractall(hooked(_)), R = R0.
t72(R) :- trie_new(T), trie_insert(T, a, 1, H), put_attr(X, user, 1), ( trie_term(H, b) -> R1 = yes ; R1 = no ), ( trie_term(H, X) -> R2 = yes ; R2 = no ),
    findall(V, hooked(V), R3), retractall(hooked(_)), R = [R1, R2, R3].
t73(R) :- trie_new(T), trie_insert(T, 7, 1, H), put_attr(X, user, 1), trie_term(H, X), findall(V, hooked(V), R0), retractall(hooked(_)), R = R0.
attr_unify_hook(_, V) :- assertz(hooked(V)).

% t74, t75: a whole subtree goes and comes back (prune); the value of a lookup is unified, not just compared
t74(R) :- trie_new(T), findall(I, ( between(1, 50, I), trie_insert(T, f(a, I), I) ), Is), length(Is, N1),
    findall(I, ( between(1, 50, I), trie_delete(T, f(a, I), _) ), Ds), length(Ds, N2),
    findall(I, ( between(1, 50, I), trie_lookup(T, f(a, I), _) ), Ls), length(Ls, N3),
    findall(I, ( between(1, 50, I), trie_insert(T, f(a, I), I) ), Rs), length(Rs, N4),
    findall(I, ( between(1, 50, I), trie_lookup(T, f(a, I), V), V =:= I ), Ms), length(Ms, N5), R = [N1, N2, N3, N4, N5].
t75(R) :- trie_new(T), trie_insert(T, k, f(1, 2)),
    ( trie_lookup(T, k, f(1, Z)) -> R1 = Z ; R1 = no ), ( trie_lookup(T, k, f(2, _)) -> R2 = yes ; R2 = no ),
    ( trie_lookup(T, k, g(_, _)) -> R3 = yes ; R3 = no ), ( trie_lookup(T, k, f(_, _, _)) -> R4 = yes ; R4 = no ), R = [R1, R2, R3, R4].

% t76: the type name of the trie blob (blob/2 reads the name of its PL_blob_t, `trie`; nothing else reads it)
t76(R) :- trie_new(T), ( blob(T, Ty) -> R = Ty ; R = none ).

% t77-t86 (TR3): attributed variables in a trie. swipl's answers (10.1.20): a key with an attributed variable is inserted and found; the
% same attributed variable is found, one with another attribute value is not; trie_term/2 gives back a variable with the same attributes.
t77(R) :- put_attr(X, user, 1), put_attr(Y, user, 1), put_attr(Z, user, 2), trie_new(T), trie_insert(T, X),
    ( trie_lookup(T, X, _) -> R1 = yes ; R1 = no ), ( trie_lookup(T, Y, _) -> R2 = yes ; R2 = no ), ( trie_lookup(T, Z, _) -> R3 = yes ; R3 = no ),
    R = [R1, R2, R3].
t78(R) :- put_attr(X, user, 1), put_attr(Z, user, 2), trie_new(T), trie_insert(T, f(X)),
    ( trie_lookup(T, f(X), _) -> R1 = yes ; R1 = no ), ( trie_lookup(T, f(Z), _) -> R2 = yes ; R2 = no ), ( trie_lookup(T, f(_), _) -> R3 = yes ; R3 = no ),
    ( trie_lookup(T, f(a), _) -> R4 = yes ; R4 = no ), R = [R1, R2, R3, R4].
t79(R) :- retractall(hooked(_)), trie_new(T), trie_insert(T, f(a), 1, H), put_attr(X, user, 1), trie_term(H, X),
    findall(V, hooked(V), R0), retractall(hooked(_)), R = [X, R0].
t80(R) :- trie_new(T), trie_insert(T, f(a)), put_attr(X, user, 1), ( trie_lookup(T, f(X), _) -> R = found ; R = notfound ).
t81(R) :- put_attr(X, user, 1), trie_new(T), trie_insert(T, f(a, X), 1, H), ( trie_lookup(T, f(a, X), V) -> R1 = V ; R1 = no ),
    trie_term(H, f(A, B)), ( A == a -> R2 = a ; R2 = other ), get_attr(B, user, At), R = [R1, R2, At].
t82(R) :- put_attr(X, user, 1), trie_new(T), trie_insert(T, f(X, X), 1, H), trie_term(H, f(A, B)), ( A == B -> R1 = same ; R1 = distinct ),
    get_attr(A, user, At), put_attr(Y, user, 1), ( trie_lookup(T, f(X, X), _) -> R2 = yes ; R2 = no ), ( trie_lookup(T, f(X, Y), _) -> R3 = yes ; R3 = no ),
    ( trie_lookup(T, f(Y, Y), _) -> R4 = yes ; R4 = no ), R = [R1, At, R2, R3, R4].
t83(R) :- put_attr(X, user, 1), put_attr(X, other, 2), trie_new(T), trie_insert(T, g(X), 1, H), trie_term(H, g(A)), get_attrs(A, As), R = As.
t84(R) :- put_attr(Y, user, 7), put_attr(X, user, Y), trie_new(T), trie_insert(T, f(X), 1, H), trie_term(H, f(A)),
    get_attr(A, user, B), ( attvar(B) -> get_attr(B, user, C) ; C = noattvar ), ( trie_lookup(T, f(X), _) -> R1 = yes ; R1 = no ), R = [C, R1].
t85(R) :- put_attr(X, user, 1), trie_new(T), trie_insert(T, f(X), 1, H), retractall(hooked(_)), trie_term(H, f(b)),
    findall(V, hooked(V), R0), retractall(hooked(_)), R = R0.
t86(R) :- put_attr(X, user, 1), trie_new(T), trie_insert(T, f(X, b), 1, H), put_attr(W, user, 1),
    ( trie_term(H, f(W, b)) -> R1 = yes ; R1 = no ), put_attr(W2, user, 2), ( trie_term(H, f(W2, b)) -> R2 = yes ; R2 = no ),
    ( trie_term(H, f(_, c)) -> R3 = yes ; R3 = no ), R = [R1, R2, R3].
