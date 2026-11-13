% ORIGINAL: the rows of test/core_lang/test_g1gc_safe_points.jl - no swipl-devel counterpart (G1-GC's own: one program per safe point of docs/g1gc_safe_points.md).
% test/core_lang/test_g1gc_safe_points.pl - one row `gN(R)` per SAFE site (the SITE block of the table): each calls the predicate whose body passes
% ALLOW_GC to ensureGlobalSpace. test_g1gc_safe_points.out holds swipl's answers (10.1.20, pin 18168e62), printed by the driver of the .jl.
% The .jl runs every row twice, with ld.gc_force off and on, and compares both with the .out.
% A row prints plain terms: no blob, no dict, no continuation (`g19` prints the ball and the continuation's size class only).

% an attributed variable: put_attr/3, get_attr/3
g1(R) :- put_attr(X, m, 1), get_attr(X, m, R).
% put_attrs/2 replaces the whole list
g2(R) :- put_attrs(X, att(m, 1, [])), get_attr(X, m, R).
% del_attr/2: the last attribute gone, a plain variable again
g3(R) :- put_attr(X, m, 1), del_attr(X, m), ( attvar(X) -> R = attvar ; R = plain ).
% del_attrs/1
g4(R) :- put_attr(X, m, 1), put_attr(X, n, 2), del_attrs(X), ( attvar(X) -> R = attvar ; R = plain ).
% '$attv_unify'/2: bind an attributed variable without a wakeup
g5(R) :- put_attr(X, m, 1), '$attv_unify'(X, a), R = X.
% '$freeze'/2 through freeze/2
g6(R) :- freeze(X, foo), get_attr(X, freeze, R).
% '$suspend'/3
g7(R) :- '$suspend'(X, m, true), get_attr(X, m, R).
% functor/3, compound_name_arity/3, =../2, compound_name_arguments/3
g8(R) :- functor(T, foo, 3), R = T.
g9(R) :- compound_name_arity(T, foo, 2), R = T.
g10(R) :- T =.. [f, a, b], R = T.
g11(R) :- compound_name_arguments(T, f, [a, b]), R = T.
% '$length'/2: a list of fresh variables
g12(R) :- '$length'(L, 3), R = L.
% b_setval/2 and nb_setval/2
g13(R) :- b_setval(g1gc_v, 1), b_getval(g1gc_v, R).
g14(R) :- nb_setval(g1gc_w, f(_)), nb_getval(g1gc_w, R).
% the findall bag: '$collect_findall_bag'/2 and the copy of each answer
g15(R) :- findall(f(X), member(X, [1, 2]), R).
% the recorded database: recorded/2 copies the record to the global stack
g16(R) :- recorda(g1gc_key, foo(a, _)), recorded(g1gc_key, R).
% copy_term/2: copy_term_refs
g17(R) :- copy_term(f(X, _, X), R).
% dict_create/3: PL_get_dict_ex; the answer is the value, not the dict
g18(R) :- dict_create(D, t, [a-1]), get_dict(a, D, R).
% a continuation: shift/1 builds the environment (put_environment)
g19_p :- shift(ball), true.
g19(R) :- reset(g19_p, B, C), ( C == 0 -> K = done ; K = cont ), R = B-K.
% not a safe point (bind_attvar_const keeps flags 0): the wakeup of a frozen variable must record nothing of its own
g20(R) :- freeze(X, true), X = 1, R = X.
% the other callers of copyRecordToGlobal (one row per call site of the kernel's pl-rec.jl and pl-trie.jl):
% recorded/3 with a bound reference (the key is unified, not looked up)
g21(R) :- recorda(g1gc_k2, foo(a), Ref), recorded(K, T, Ref), R = K-T.
% instance/2 of a record reference
g22(R) :- recorda(g1gc_k3, bar(_), Ref), instance(Ref, T), R = T.
% PL_recorded: the value of a trie node is a record
g23(R) :- trie_new(Tr), trie_insert(Tr, g1gc_k4, f(a, _)), trie_lookup(Tr, g1gc_k4, R).
