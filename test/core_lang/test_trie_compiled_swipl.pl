% ORIGINAL: the rows of test/core_lang/test_trie_compiled_swipl.jl - no swipl-devel counterpart (the cases are those of tests/tabling/
% test_trie_index.pl at the pin that trie_gen_compiled/2,3 and '$trie_compile'/2 answer, written as differential rows).
% test/core_lang/test_trie_compiled_swipl.pl - TR4's rows (pl-trie.c: compile_trie, trie_gen_compiled/2,3, '$trie_compile'/2; pl-vmi.c:
% S_TRIE_GEN and the T_* instructions). Each `tN(R)` is one row; test_trie_compiled_swipl.out holds swipl's answers (10.1.20, pin
% 18168e62), printed by the driver of the .jl (`ok`, then one line per row). A row never encodes a trie nor a clause (blobs): an error that
% names a trie goes through scrub/3, a clause reference goes only to blob/2.
% Rows that call trie_gen/2,3 (TR2's, the comparison of the compiled answers with the interpreted ones) are marked `% runs once TR2 is
% stacked`: the .jl leaves them out of the kernel's check while trie_gen/2 is not defined there.
% NOT HERE (the .jl says why): attributed variables in keys (TR3), conditional answers T_DELAY (TB4), a table's answer trie (TB3/TB6).

mk(Tr, Ks) :- trie_new(Tr), mkv(Ks, Tr).
mkv([], _).
mkv([K|Ks], Tr) :- trie_insert(Tr, K), mkv(Ks, Tr).
mkvv([], _).
mkvv([K-V|Ps], Tr) :- trie_insert(Tr, K, V), mkvv(Ps, Tr).
rt(Tr, G, R) :- catch(( G -> R = true ; R = false ), error(E, C), ( scrub(E, Tr, E1), R = error(E1, C) )).
scrub(V, _, V) :- var(V), !.
scrub(T, Tr, '<trie>') :- T == Tr, !.
scrub(T, Tr, S) :- compound(T), !, T =.. [F|As], scrubs(As, Tr, Bs), S =.. [F|Bs].
scrub(T, _, T).
scrubs([], _, []).
scrubs([A|As], Tr, [B|Bs]) :- scrub(A, Tr, B), scrubs(As, Tr, Bs).
fill(N, N, _) :- !.
fill(I, N, Tr) :- I1 is I+1, trie_insert(Tr, f(I1), I1), fill(I1, N, Tr).

% key-only, the value is true (trie_insert/2): all four shapes of key
t0(R) :- mk(T, [f(1), f(2), g(a), b]), findall(K, trie_gen_compiled(T, K), R).
% the value is read: every key with its value
t1(R) :- trie_new(T), mkvv([f(1)-one, f(2)-two, g(a)-three], T), findall(K-V, trie_gen_compiled(T, K, V), R).
% a partly bound key prunes the other functor
t2(R) :- mk(T, [f(1), f(2), g(a), b]), findall(X, trie_gen_compiled(T, f(X)), R).
% a bound Value
t3(R) :- trie_new(T), mkvv([f(a)-1, f(b)-2, f(c)-1], T), findall(K, trie_gen_compiled(T, K, 1), R).
t4(R) :- trie_new(T), ( trie_gen_compiled(T, _) -> R = yes ; R = no ).
t5(R) :- trie_new(T), ( trie_gen_compiled(T, _, _) -> R = yes ; R = no ).
% variables in the keys: the same variable twice
t6(R) :- trie_new(T), trie_insert(T, f(X, Y, X), v1), trie_insert(T, f(a, b, c), v2), trie_insert(T, f(A, A, B), v3),
    X = Y, B = A,
    findall(Q-V, ( Q = f(P, P, _), trie_gen_compiled(T, Q, V) ), R).
% nested compounds
t7(R) :- mk(T, [f(g(1), 2), f(g(1), 3), f(h, 2), f(g(2), 2), f(g(1, 1), 2)]),
    findall(Q, ( Q = f(g(_), 2), trie_gen_compiled(T, Q) ), R).
t8(R) :- mk(T, [f(g(h(1)), 2), f(g(h(1)), 3), f(g(h(2)), 3), f(g(h(1), x), 3), f(k, 3)]),
    findall(Q, ( Q = f(g(h(_)), 3), trie_gen_compiled(T, Q) ), R).
% strings, floats, big integers (T_STRING, T_FLOAT, T_MPZ)
t9(R) :- mk(T, [f("abc"), f(1.5), f(100000000000000000000), f("abd"), g(2.5)]),
    findall(a(Q1,Q2,Q3,Q4), ( findall(X, trie_gen_compiled(T, f("abx")), Q1), findall(X, trie_gen_compiled(T, f("abc")), Q2),
                              findall(X, trie_gen_compiled(T, f(1.5)), Q3), findall(X, trie_gen_compiled(T, f(100000000000000000000)), Q4) ), R).
t10(R) :- mk(T, [f("abc"), f(1.5), f(100000000000000000000), f("abd"), g(2.5)]), findall(K, trie_gen_compiled(T, K), R).
% small integers: negative, the tagged range, atoms beside them (T_SMALLINT, T_ATOM)
t11(R) :- mk(T, [f(-1), f(0), f(1), f(-7), f(x), f(y), f(7)]), findall(K, trie_gen_compiled(T, K), R).
t12(R) :- mk(T, [f(-1), f(0), f(1), f(-7), f(x), f(y), f(7)]), findall(X, trie_gen_compiled(T, f(X)), R).
% a nonvariable arity-0 compound and the empty list
t13(R) :- mk(T, [[], [a], [a, b], '[]', "", f([])]), findall(K, trie_gen_compiled(T, K), R).
t14(R) :- mk(T, [f(a), f(b), f(c)]), call_cleanup(trie_gen_compiled(T, f(a)), Det = true), R = Det-done.
t15(R) :- mk(T, [f(a), f(b), f(c)]), findall(K, trie_gen_compiled(T, K), R0), once(trie_gen_compiled(T, K1)), R = R0-K1.
% the compiled clause is discarded by a change of the trie: the next call sees the change
t16(R) :- mk(T, [f(1), f(2)]), findall(K, trie_gen_compiled(T, K), R0), trie_insert(T, f(3)),
    findall(K, trie_gen_compiled(T, K), R1), R = R0-R1.
t17(R) :- mk(T, [f(1), f(2), f(3)]), findall(K, trie_gen_compiled(T, K), R0), trie_delete(T, f(2), _),
    findall(K, trie_gen_compiled(T, K), R1), R = R0-R1.
t18(R) :- trie_new(T), fill(0, 50, T), findall(K, trie_gen_compiled(T, K, _), Ks), length(Ks, N),
    findall(I, trie_gen_compiled(T, f(I), _), Is), sum_list(Is, Sum), R = N-Sum.
% a trie with 1000 keys: the code is long
t19(R) :- trie_new(T), fill(0, 1000, T), findall(I, trie_gen_compiled(T, f(I), _), Is), length(Is, N), sum_list(Is, Sum), R = N-Sum.
% '$trie_compile'/2: a clause for a trie with keys; for an empty trie it answers the atom fail
t20(R) :- mk(T, [f(1), f(2)]), '$trie_compile'(T, C), ( blob(C, clause) -> R = clause ; R = other ).
t21(R) :- trie_new(T), ( '$trie_compile'(T, C) -> ( C == fail -> R = isfail ; R = other ) ; R = no ).
% the clause reference as the first argument: every answer, then the answers with a pattern
t22(R) :- mk(T, [f(1), f(2), g(a)]), '$trie_compile'(T, C), findall(K, trie_gen_compiled(C, K), R).
t23(R) :- mk(T, [f(1), f(2), g(a)]), '$trie_compile'(T, C), findall(X, trie_gen_compiled(C, f(X)), R).
t24(R) :- trie_new(T), mkvv([f(1)-one, f(2)-two, g(a)-three], T), '$trie_compile'(T, C),
    findall(K-V, trie_gen_compiled(C, K, V), R).
% '$trie_compile'/2 twice on an unchanged trie: both answer alike
t25(R) :- trie_new(T), mkvv([f(1)-one, f(2)-two], T), '$trie_compile'(T, C1), '$trie_compile'(T, C2),
    findall(K-V, trie_gen_compiled(C1, K, V), R1), findall(K-V, trie_gen_compiled(C2, K, V), R2), R = R1-R2.
% errors of '$trie_compile'/2: not a trie, unbound, a destroyed trie. NOT HERE: trie_gen_compiled/2,3 with a first argument that is neither
% a trie nor a clause (swipl at the pin overflows the local stack on that path and does not recover: no swipl answer; kernel-only testset)
t26(R) :- rt(_, '$trie_compile'(foo, _), R).
t27(R) :- rt(_, '$trie_compile'(_, _), R).
t28(R) :- mk(T, [f(1)]), trie_destroy(T), rt(T, '$trie_compile'(T, _), R).
% the compiled clause of an empty trie is the atom fail: trie_gen_compiled/2,3 on it fail
t29(R) :- trie_new(T), '$trie_compile'(T, C), ( C == fail -> A = isfail ; A = other ),
    ( trie_gen_compiled(C, _) -> B = yes ; B = no ), ( trie_gen_compiled(C, _, _) -> D = yes ; D = no ), R = A-B-D.
% the key argument bound to a whole key: a hit and a miss
t30(R) :- mk(T, [f(1), g(a)]), ( trie_gen_compiled(T, f(1)) -> A = yes ; A = no ), ( trie_gen_compiled(T, f(2)) -> B = yes ; B = no ), R = A-B.
t31(R) :- trie_new(T), mkvv([f(1)-a, f(2)-b], T), ( trie_gen_compiled(T, f(1), a) -> A = yes ; A = no ),
    ( trie_gen_compiled(T, f(1), b) -> B = yes ; B = no ), R = A-B.
% two keys that share a prefix and differ in the last argument
t32(R) :- mk(T, [f(a, b, c), f(a, b, d), f(a, e, c), f(x, b, c)]), findall(Q, ( Q = f(a, b, _), trie_gen_compiled(T, Q) ), R).
t33(R) :- mk(T, [f(a, b, c), f(a, b, d), f(a, e, c), f(x, b, c)]), findall(Q, ( Q = f(a, _, c), trie_gen_compiled(T, Q) ), R).
% a variable key (the whole key a variable) and keys with a first-occurrence variable
t34(R) :- trie_new(T), trie_insert(T, _), trie_insert(T, a), findall(K, trie_gen_compiled(T, K), R0), length(R0, N), R = N.
t35(R) :- trie_new(T), trie_insert(T, f(_, _)), findall(Q, ( Q = f(P, P), trie_gen_compiled(T, Q) ), R).
% the answer shares a variable with the call (bound afterwards)
t36(R) :- mk(T, [f(1, 1), f(1, 2), f(2, 2)]), findall(X-Y, ( trie_gen_compiled(T, f(X, Y)), X == Y ), R).
% the compiled answers of a trie with a value that is a compound
t37(R) :- trie_new(T), mkvv([f(1)-g(x), f(2)-h(y, z)], T), findall(K-V, trie_gen_compiled(T, K, V), R).
t38(R) :- trie_new(T), mkvv([f(1)-g(x), f(2)-h(y, z)], T), findall(K, trie_gen_compiled(T, K, h(_, _)), R).
% key-only on a trie whose values are not true: swipl answers none (the value is read), no error
t39(R) :- trie_new(T), mkvv([f(1)-a, f(2)-b], T), findall(K, trie_gen_compiled(T, K), R).
% a clause reference kept across a change of the trie: the discarded clause still answers what the trie held when it was compiled,
% the trie itself compiles anew
t40(R) :- mk(T, [f(1)]), '$trie_compile'(T, C), trie_insert(T, f(2)),
    findall(K, trie_gen_compiled(C, K), R0), findall(K, trie_gen_compiled(T, K), R1), R = R0-R1.
t41(R) :- trie_new(T), mkvv([f(1)-a], T), '$trie_compile'(T, C), trie_delete(T, f(1), _),
    findall(K-V, trie_gen_compiled(C, K, V), R0), findall(K-V, trie_gen_compiled(T, K, V), R1), R = R0-R1.
% runs once TR2 is stacked: the compiled answers equal the interpreted ones
t42(R) :- mk(T, [f(1), f(2), g(a), b]), findall(K, trie_gen(T, K), R0), findall(K, trie_gen_compiled(T, K), R1), ( R0 == R1 -> R = same ; R = differ(R0, R1) ).
t43(R) :- trie_new(T), mkvv([f(1)-one, f(2)-two, g(a)-three, h("s", 1.5)-four], T),
    findall(K-V, trie_gen(T, K, V), R0), findall(K-V, trie_gen_compiled(T, K, V), R1), ( R0 == R1 -> R = same ; R = differ(R0, R1) ).
t44(R) :- mk(T, [f(g(1), 2), f(g(1), 3), f(h, 2), f(g(2), 2)]),
    findall(Q, ( Q = f(g(_), 2), trie_gen(T, Q) ), R0), findall(Q, ( Q = f(g(_), 2), trie_gen_compiled(T, Q) ), R1),
    ( R0 == R1 -> R = same ; R = differ(R0, R1) ).
t45(R) :- trie_new(T), fill(0, 300, T), findall(I, trie_gen(T, f(I), _), R0), findall(I, trie_gen_compiled(T, f(I), _), R1),
    ( R0 == R1 -> R = same ; R = differ ).
t46(R) :- trie_new(T), trie_insert(T, f(X, Y, X), v1), trie_insert(T, f(a, b, c), v2), trie_insert(T, f(A, A, B), v3), X = Y, B = A,
    findall(K-V, trie_gen(T, K, V), R0), findall(K-V, trie_gen_compiled(T, K, V), R1), ( R0 =@= R1 -> R = same ; R = differ ).

% values that are terms with variables, deep nesting and indirects (T_VAR, T_POP, T_POPN, T_FLOAT/T_STRING/T_MPZ in a value)
t47(R) :- trie_new(T), trie_insert(T, f(1), v(X, X, _)), findall(V, trie_gen_compiled(T, f(1), V), [v(A, B, C)]),
    ( A == B, A \== C -> R = shared ; R = notshared ).
t48(R) :- trie_new(T), trie_insert(T, f(1), a(b(c(d(1))), 2)), trie_insert(T, f(2), a(b(c(d(2))), 3)),
    findall(K-V, trie_gen_compiled(T, K, V), R).
t49(R) :- trie_new(T), trie_insert(T, f(1), w("str", 2.5, 100000000000000000000, x)), findall(K-V, trie_gen_compiled(T, K, V), R).
% a wakeup of an attributed variable of the call, bound by an answer (T_CHECKWAKEUP): the hook runs for each answer
m:attr_unify_hook(_, V) :- V == 1.
t50(R) :- mk(T, [f(1), f(2)]), put_attr(X, m, a), findall(X, trie_gen_compiled(T, f(X)), R).
% a clause reference is made once
t51(R) :- mk(T, [f(1)]), '$trie_compile'(T, C1), '$trie_compile'(T, C2), ( C1 == C2 -> R = same ; R = differ ).
% a compound at a NON-first argument (TriePushArgP saves the offset 2; TrieNextArg after the pop steps from it)
t52(R) :- mk(T, [f(a, g(1), c), f(a, g(2), c), f(a, g(1), d), f(b, h, c)]),
    findall(Q, ( Q = f(a, g(_), c), trie_gen_compiled(T, Q) ), R).
% key-only on a MAP trie (as t39): T_VALUE reads the cell after T_TRIE_GEN2's +(Key), the key's functor word when the key is a
% compound; no constant, functor, float or string matches it, a variable value takes it (an atom key: KD-4 in the .jl)
t53(R) :- trie_new(T), trie_insert(T, f(1), _), findall(K, trie_gen_compiled(T, K), R).
t54(R) :- trie_new(T), trie_insert(T, a, _), findall(K, trie_gen_compiled(T, K), R).
t55(R) :- trie_new(T), mkvv([f(1)-g(x), f(2)-1.5, f(3)-"s", f(4)-7, f(5)-_], T), findall(K, trie_gen_compiled(T, K), R).
