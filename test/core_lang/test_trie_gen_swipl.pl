% ORIGINAL: the rows of test/core_lang/test_trie_gen_swipl.jl - no swipl-devel counterpart (the cases are those of tests/tabling/test_trie_index.pl
% and test_trie_children.pl at the pin that trie_gen/2,3, '$trie_gen_node'/3 and '$trie_property'/2 answer).
% test/core_lang/test_trie_gen_swipl.pl - TR2's rows (pl-trie.c: trie_gen/2,3, '$trie_gen_node'/3, '$trie_property'/2). Each `tN(R)` is one row;
% test_trie_gen_swipl.out holds swipl's answers (10.1.20, pin 18168e62), printed by the driver of the .jl (`ok`, then one line per row).
% A row never encodes a trie (a blob) nor a node handle: an error that names a trie goes through scrub/3.
% NOT HERE (the .jl says why): attributed_query and stored_attvar_beside_constants (TR3), stack_shift/garbage_collection (no collector),
% the threads, tabling and compiled tests, '$trie_property' idg_* and invalidated (TB6).

mk(Tr, Ks) :- trie_new(Tr), mkv(Ks, Tr).
mkv([], _).
mkv([K|Ks], Tr) :- trie_insert(Tr, K, K), mkv(Ks, Tr).
keys(Tr, Ks) :- findall(K, trie_gen(Tr, K), Ks).
res(G, R) :- catch(( G -> R = true ; R = false ), error(E, C), R = error(E, C)).
rt(Tr, G, R) :- catch(( G -> R = true ; R = false ), error(E, C), ( scrub(E, Tr, E1), R = error(E1, C) )).
scrub(V, _, V) :- var(V), !.
scrub(T, Tr, '<trie>') :- T == Tr, !.
scrub(T, Tr, S) :- compound(T), !, T =.. [F|As], scrubs(As, Tr, Bs), S =.. [F|Bs].
scrub(T, _, T).
scrubs([], _, []).
scrubs([A|As], Tr, [B|Bs]) :- scrub(A, Tr, B), scrubs(As, Tr, Bs).
fill(N, N, _) :- !.
fill(I, N, Tr) :- I1 is I+1, trie_insert(Tr, f(I1), I1), fill(I1, N, Tr).
prop(Tr, P, V) :- ( '$trie_property'(Tr, P) -> V = P ; V = none ).

t0(R) :- mk(T, [f(1), f(2), g(a), b]), keys(T, R).
t1(R) :- trie_new(T), trie_insert(T, f(1), one), trie_insert(T, f(2), two), trie_insert(T, g(a), three),
    findall(K-V, trie_gen(T, K, V), R).
t2(R) :- mk(T, [f(1), f(2), g(a), b]), findall(X, trie_gen(T, f(X)), R).
t3(R) :- mk(T, [f(1), f(2), g(a), b]), findall(K, trie_gen(T, f(2), K), R).
t4(R) :- trie_new(T), ( trie_gen(T, _) -> R = yes ; R = no ).
t5(R) :- trie_new(T), trie_insert(T, f(X, Y, X), v1), trie_insert(T, f(a, b, c), v2), trie_insert(T, f(A, A, B), v3),
    X = Y, B = A,
    findall(Q-V, ( Q = f(P, P, _), trie_gen(T, Q, V) ), R).
t6(R) :- mk(T, [f(g(1), 2), f(g(1), 3), f(h, 2), f(g(2), 2), f(g(1, 1), 2)]),
    findall(Q, ( Q = f(g(_), 2), trie_gen(T, Q) ), R).
t7(R) :- mk(T, [f(g(h(1)), 2), f(g(h(1)), 3), f(g(h(2)), 3), f(g(h(1), x), 3), f(k, 3)]),
    findall(Q, ( Q = f(g(h(_)), 3), trie_gen(T, Q) ), R).
t8(R) :- mk(T, [f("abc"), f(1.5), f(100000000000000000000), f("abd"), g(2.5)]),
    findall(a(Q1,Q2,Q3,Q4), ( findall(X, trie_gen(T, f("abx")), Q1), findall(X, trie_gen(T, f("abc")), Q2),
                              findall(X, trie_gen(T, f(1.5)), Q3), findall(X, trie_gen(T, f(100000000000000000000)), Q4) ), R).
t9(R) :- mk(T, [f(a), f(b), f(c)]), call_cleanup(trie_gen(T, f(a)), Det = true), R = Det-done.
t10(R) :- mk(T, [f(a), f(b), f(c)]), findall(K, ( trie_gen(T, K), K = f(_) ), R0), once(trie_gen(T, K1)), R = R0-K1.
t11(R) :- mk(T, [f(1), f(2), f(3), f(4)]),
    findall(K, ( trie_gen(T, K), ( K == f(1) -> trie_delete(T, f(3), _) ; true ) ), R).
t12(R) :- mk(T, [f(1), f(2)]),
    findall(K, ( trie_gen(T, K), ( K == f(1) -> trie_insert(T, f(9), 9) ; true ) ), R).
% pick/3: nth1/3 without lists:nth1 (nth1 calls '$seek_list'/4, which P2 will port: docs/r2_owners.tsv:48; the row's answers are unchanged: test_trie_gen_swipl.out)
pick(1, [X|_], X) :- !.
pick(N, [_|T], X) :- N > 1, M is N-1, pick(M, T, X).
t13(R) :- trie_new(T), numlist(1, 40, Is),
    forall(member(I, Is), ( length(Vs, 40), pick(I, Vs, X), append(Vs, [X], As), Tm =.. [p|As], trie_insert(T, Tm, I) )),
    length(Q0, 41), Q0 = [a|Q1], last(Q0, b), Q =.. [p|Q0], Q1 = Q1,
    findall(V, trie_gen(T, Q, V), Vs2), msort(Vs2, R).
t14(R) :- trie_new(T), fill(0, 1000, T), findall(K, trie_gen(T, K), Ks), length(Ks, N), prop(T, node_count(NC), _),
    prop(T, value_count(VC), _), ( '$trie_property'(T, size(S)), S > 0 -> Sz = positive ; Sz = bad ), R = N-NC-VC-Sz.
t15(R) :- trie_new(T), fill(0, 1000, T),
    forall(( between(1, 1000, I), I mod 2 =:= 0 ), trie_delete(T, f(I), _)),
    findall(I, trie_gen(T, f(I)), Is), length(Is, N), sum_list(Is, Sum), R = N-Sum.
t16(R) :- trie_new(T), fill(0, 200, T), forall(between(1, 200, I), trie_delete(T, f(I), _)),
    ( trie_gen(T, _) -> R = some ; R = none ), fill(0, 3, T), findall(K, trie_gen(T, K), R1), R-R1 = R-R1.
t17(R) :- mk(T, [f(1), g(2)]), findall(K-V, trie_gen(T, K, V), R0), findall(K, ( '$trie_gen_node'(T, K, N), trie_term(N, K2), K2 =@= K ), R1), R = R0-R1.
t18(R) :- trie_new(T), trie_insert(T, f(a), 1), trie_insert(T, f(b), 2), trie_insert(T, f(c), 1),
    findall(K, trie_gen(T, K, 1), R).
t19(R) :- trie_new(T), trie_insert(T, f(X, Y, X), a), trie_insert(T, g(a), b), Y = Y,
    prop(T, node_count(_), P1), prop(T, value_count(_), P2), prop(T, size(_), P3), prop(T, hashed(_), P4), prop(T, discarded(_), P5),
    prop(T, wait(_), P6), prop(T, deadlock(_), P7), prop(T, gen_call_count(_), P8),
    R = [P1, P2, P3, P4, P5, P6, P7, P8].
t20(R) :- trie_new(T), trie_insert(T, a, 1), trie_insert(T, b, 2), ( trie_lookup(T, a, _) -> true ; true ),
    prop(T, lookup_count(_), L), prop(T, gen_call_count(_), G0), ( trie_gen(T, _) -> true ; true ), prop(T, gen_call_count(_), G1), R = L-G0-G1.
t21(R) :- trie_new(T), findall(P, ( member(P, [compiled_size(_), invalidated(_), reevaluated(_), idg_size(_), idg_affected_count(_), nosuch(_), bar, foo(_, _)]),
    '$trie_property'(T, P) ), R).
t22(R) :- trie_new(T), '$trie_property'(T, _) -> R = yes ; R = no.
t23(R) :- findall(X, ( member(G, [trie_gen(foo, _), trie_gen(_, _), trie_gen(foo, _, _), '$trie_property'(foo, _), '$trie_property'(_, _), '$trie_gen_node'(foo, _, _)]),
    res(G, X) ), R).
t24(R) :- trie_new(T), trie_insert(T, a, 1), trie_destroy(T),
    findall(X, ( member(G, [trie_gen(T, _), trie_gen(T, _, _), '$trie_property'(T, node_count(_)), '$trie_gen_node'(T, _, _)]), rt(T, G, X) ), R).
t25(R) :- mk(T, [f(a, 1), f(a, 2), f(b, 1), f(c, 3)]), findall(X-Y, ( trie_gen(T, f(X, Y)), Y == 1 ), R).
t26(R) :- mk(T, [f(1, a), f(2, a), f(3, b)]), findall(X, ( trie_gen(T, f(X, Y)), Y = a ), R).
t27(R) :- mk(T, [f(1), f(2), f(3)]), trie_gen(T, f(2)), ( trie_gen(T, f(5)) -> R = bad ; R = ok ).
t28(R) :- trie_new(T), trie_insert(T, f(X), x), trie_insert(T, f(a), a), trie_insert(T, f(g(Y)), g), Y = X,
    findall(Q-V, ( trie_gen(T, f(Q), V) ), R).
t29(R) :- mk(T, [h(1, 2, 3), h(1, 2, 4), h(1, 5, 3), h(6, 2, 3)]),
    findall(a(A, B, C), trie_gen(T, h(A, B, C)), R0), findall(C, trie_gen(T, h(1, _, C)), R1), R = R0-R1.
