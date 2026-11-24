% ORIGINAL: the rows of test/core_lang/test_trie_gen_swipl.jl - no swipl-devel counterpart (the cases are those of tests/tabling/test_trie_index.pl
% and test_trie_children.pl at the pin that trie_gen/2,3, '$trie_gen_node'/3 and '$trie_property'/2 answer).
% test/core_lang/test_trie_gen_swipl.pl - TR2's rows (pl-trie.c: trie_gen/2,3, '$trie_gen_node'/3, '$trie_property'/2). Each `tN(R)` is one row;
% test_trie_gen_swipl.out holds swipl's answers (10.1.20, pin 18168e62), printed by the driver of the .jl (`ok`, then one line per row).
% A row never encodes a trie (a blob) nor a node handle: an error that names a trie goes through scrub/3.
% NOT HERE (the .jl says why): attributed_query and stored_attvar_beside_constants (TR3), stack_shift (t51 is the garbage_collection_between_answers row),
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
% t30/t31: the leaf the enumeration is POSITIONED on is deleted between two answers (t11 deletes one further ahead, which next_choice! skips by itself)
t30(R) :- mk(T, [f(1), f(2), f(3), f(4)]),
    findall(K, ( trie_gen(T, K), ( K == f(1) -> trie_delete(T, f(2), _) ; true ) ), R).
t31(R) :- mk(T, [f(1), f(2), f(3), f(4)]),
    findall(K, ( trie_gen(T, K), ( K == f(1) -> trie_delete(T, f(2), _), trie_delete(T, f(3), _) ; true ) ), R).

% a trie for the white-box rows of the .jl (not a `tN(R)` row: it names a blob, which no row encodes)
wb_trie(T) :- mk(T, [f(1), f(2), f(3)]).
% t32/t33: two concrete query arguments equal to the same constant, a stored variable key beside the constant (the replay of an advanced choice, R)
t32(R) :- trie_new(T), trie_insert(T, f(_, a), 1), trie_insert(T, f(a, a), 2),
    findall(V, trie_gen(T, f(a, a), V), R).
t33(R) :- trie_new(T), trie_insert(T, f(a, a), 1), trie_insert(T, f(_, a), 2), trie_insert(T, f(b, a), 3),
    findall(V, trie_gen(T, f(a, a), V), R).
% t34-t37: the det flag (call_cleanup) of the answer after which only deleted leaves are left
t34(R) :- mk(T, [f(1), f(2), f(3)]),
    findall(K-D, ( call_cleanup(trie_gen(T, K), D = det), ( K == f(1) -> trie_delete(T, f(3), _) ; true ) ), R).
t35(R) :- mk(T, [f(1), f(2), f(3)]),
    findall(K-D, ( call_cleanup(trie_gen(T, f(X)), D = det), K = f(X), ( K == f(1) -> trie_delete(T, f(3), _) ; true ) ), R).
t36(R) :- mk(T, [f(a, 1), f(a, 2), f(b, 1), f(b, 2)]),
    findall(K-D, ( call_cleanup(trie_gen(T, K), D = det), ( K == f(a, 1) -> trie_delete(T, f(b, 2), _), trie_delete(T, f(a, 2), _) ; true ) ), R).
t37(R) :- mk(T, [f(a, 1), f(a, 2), f(b, 1), f(b, 2)]),
    findall(K-D, ( K = f(_, 2), call_cleanup(trie_gen(T, K), D = det), ( K == f(a, 2) -> trie_delete(T, f(b, 2), _) ; true ) ), R).
% t38: a variable first argument, a constant second: the choice over the first argument is advanced to a key that differs from the constant
t38(R) :- mk(T, [f(a, b), f(c, b), f(d, e)]), findall(X, trie_gen(T, f(X, b)), R).
% t39-t47 (E4): a trie deleted while it is enumerated. trie_gen_raw holds a reference on the trie (pl-trie.c acquire_trie), so a
% trie_delete/3 under it clears the value and does not prune (trie_delete: `prune && trie->references == 0`); release_trie at the end.
nk(N, T) :- trie_new(T), forall(between(1, N, I), trie_insert(T, k(I), I)).
cnt(T, C) :- findall(x, trie_gen(T, _), Xs), length(Xs, C).
gdel(T) :- ( trie_gen(T, K, V), trie_delete(T, K, V), fail ; true ).
% t39: what remains after deleting each answer as it is enumerated, N = 1..40 (the 4/5 boundary, 8, 16, 40)
t39(R) :- findall(C, ( between(1, 40, N), nk(N, T), gdel(T), cnt(T, C) ), R).
% t40: the answers enumerated while each is deleted (N = 9) and the node and value counts after the loop (no pruning under it)
t40(R) :- nk(9, T), findall(K, ( trie_gen(T, K, V), trie_delete(T, K, V) ), Ks), cnt(T, C),
    prop(T, node_count(_), P1), prop(T, value_count(_), P2), R = Ks-C-P1-P2.
% t41: nested keys with shared prefixes, all deleted while enumerated; then only those with an even J
t41(R) :- trie_new(T), forall(( between(1, 6, I), between(1, 6, J) ), trie_insert(T, f(g(I), h(J)), I-J)),
    forall(between(1, 6, I), trie_insert(T, f(g(I)), I)), gdel(T), cnt(T, C1),
    trie_new(T2), forall(( between(1, 6, I), between(1, 6, J) ), trie_insert(T2, f(g(I), h(J)), I-J)),
    findall(I-J, ( trie_gen(T2, f(g(I), h(J)), V), J mod 2 =:= 0, trie_delete(T2, f(g(I), h(J)), V) ), D),
    length(D, ND), findall(I-J, trie_gen(T2, f(g(I), h(J))), Left), msort(Left, LS), R = C1-ND-LS.
% t42: the NEXT sibling deleted while k(I) is enumerated (N = 10): the answers and what remains
t42(R) :- nk(10, T), findall(I, ( trie_gen(T, k(I)), J is I+1, ( trie_lookup(T, k(J), _) -> trie_delete(T, k(J), _) ; true ) ), A),
    findall(I, trie_gen(T, k(I)), L), msort(L, LS), R = A-LS.
% t43: the PREVIOUS sibling deleted while k(I) is enumerated (N = 10)
t43(R) :- nk(10, T), findall(I, ( trie_gen(T, k(I)), J is I-1, ( trie_lookup(T, k(J), _) -> trie_delete(T, k(J), _) ; true ) ), A),
    findall(I, trie_gen(T, k(I)), L), msort(L, LS), R = A-LS.
% t44: every second answer deleted while enumerated (N = 12)
t44(R) :- nk(12, T), findall(I, ( trie_gen(T, k(I)), ( I mod 2 =:= 0 -> trie_delete(T, k(I), _) ; true ) ), A),
    findall(I, trie_gen(T, k(I)), L), msort(L, LS), R = A-LS.
% t45: a pruning query f(a, X) over a hashed node, each answer deleted (f(b, _) stays)
t45(R) :- trie_new(T), forall(between(1, 10, I), ( trie_insert(T, f(a, I), I), trie_insert(T, f(b, I), I) )),
    findall(X, ( trie_gen(T, f(a, X)), trie_delete(T, f(a, X), _) ), A),
    findall(Y-X, trie_gen(T, f(Y, X)), L), msort(L, LS), R = A-LS.
% t46: the reference is released after a cut, an exception and a complete run: a delete after each prunes (the node count falls)
t46(R) :- nk(8, T1), once(trie_gen(T1, _)), forall(between(1, 8, I), trie_delete(T1, k(I), _)), prop(T1, node_count(_), P1),
    nk(8, T2), catch(( trie_gen(T2, _), throw(x) ), x, true), forall(between(1, 8, I), trie_delete(T2, k(I), _)), prop(T2, node_count(_), P2),
    nk(8, T3), findall(K, trie_gen(T3, K), _), forall(between(1, 8, I), trie_delete(T3, k(I), _)), prop(T3, node_count(_), P3),
    R = [P1, P2, P3].
% t47: the trie destroyed while it is enumerated: the enumeration goes on over the nodes it holds
t47(R) :- nk(6, T), findall(K, ( trie_gen(T, K), ( K == k(2) -> trie_destroy(T) ; true ) ), R).
% t48: a mixed block {variable key, b} BELOW a closed compound argument: the query f(g(a), b) keeps pruning after the POP (kills the cursor that stops there)
t48(R) :- trie_new(T), trie_insert(T, f(g(a), _), 1), trie_insert(T, f(g(a), b), 2),
    findall(V, trie_gen(T, f(g(a), b), V), R).
% t49: the same block below the SECOND nonvar argument of a flat compound (the last nonvar argument keeps the pruning going)
t49(R) :- trie_new(T), trie_insert(T, f(a, _), 1), trie_insert(T, f(a, b), 2),
    findall(V, trie_gen(T, f(a, b), V), R).
% t50: the descent BELOW A BACKTRACK still prunes: the mixed block under the second first-argument child
t50(R) :- trie_new(T), trie_insert(T, f(a, _), 1), trie_insert(T, f(a, b), 2),
    trie_insert(T, f(c, _), 3), trie_insert(T, f(c, b), 4),
    findall(V, trie_gen(T, f(_, b), V), R).
% t51: a garbage collection between the answers (dead cells below the query; upstream's garbage_collection_between_answers): the kept cursors are rebuilt
mkgar :- numlist(1, 400, L), length(L, _).
t51(R) :- mkgar, trie_new(T), forall(between(1, 100, I), trie_insert(T, p(I, f(a), _))),
    findall(I, ( trie_gen(T, p(I, f(a), b)), garbage_collect ), Ids), length(Ids, R).
% EQ8 (TR4-K4, TR4-S4; the tabling side of the compiled trie: tools/mutants/TRIE4.py): the `fail` atom that compile_trie stores in `tr.clause` of an EMPTY trie
% decides whether `trie_maybe_discard_nodes` (pl-trie.h:339-344: needs `trie->clause != 0`) may set TRIE_DISCARDED on a complete table with no answer.
% t52: a complete variant table with no answers, called a SECOND time: the S_TABLED path (complete_answer_clause: compile_trie, then trie_maybe_discard_nodes)
:- table k4q/1.
k4q(_) :- fail.
t52(R) :- abolish_all_tables, ( k4q(_) -> true ; true ), ( k4q(_) -> true ; true ),
    '$tbl_variant_table'(0, user:k4q(_), T, _, _, _), '$trie_property'(T, discarded(D)), R = D.
% t53: trie_gen_compiled/2 run by the body of the tabled predicate on its OWN, still incomplete, empty variant trie (S_TRIE_GEN: an empty trie leaves at once,
% before it could compile `fail` into `tr.clause`); the table is completed by that one call, then `discarded/1` is read (ONE call only: a second one would
% reach complete_answer_clause and give the same answer in both versions)
:- table s4q/1.
s4q(_) :- '$tbl_variant_table'(0, user:s4q(_), T, _, _, _), nb_setval(s4_trie, T), ( trie_gen_compiled(T, _) -> true ; true ), fail.
t53(R) :- abolish_all_tables, ( s4q(_) -> true ; true ), nb_getval(s4_trie, T), '$trie_property'(T, discarded(D)), R = D.
