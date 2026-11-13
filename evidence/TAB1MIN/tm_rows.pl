:- dynamic tm_hold/1.
:- dynamic tm_ck/2.
:- dynamic tm_x22/1.
tm_yn(G, R) :- ( call(G) -> R = yes ; R = no ).
tm_get(P, A, R) :- ( '$get_predicate_attribute'(P, A, V) -> R = V ; R = none ).
tm_nc(P, N) :- '$get_predicate_attribute'(P, number_of_clauses, N).
tm_wrapb(Head, WName, Closure, call(Wrapped), Body) :-
    Head =.. [P|Args], atom_concat('$wrap$', P, WP), WHead =.. [WP|Args],
    '$c_wrap_predicate'(user:Head, WName, Closure, Wrapped, user:(WHead :- Body)).
tm_wrap(Head, WName, Closure, Wrapped) :- tm_wrapb(Head, WName, Closure, Wrapped, true).
tm_same(A, B, R) :- ( A == B -> R = same ; R = diff ).
tm_w01(1).
tm_w01(2).
tm_w02(1).
tm_w03(1).
tm_w04.
tm_w05(1).
tm_w06(1).
tm_w07(1).
tm_w07b(1).
tm_w11(1).
tm_w12(1).
tm_w13(1).
tm_w13(2).
tm_w14(1, 2).
tm_w15(1, 2, 3).
tm_d01(1).
tm_d02(1).
tm_c01(1).
:- tm_wrap(tm_c01(_), n1, C, _), assertz(tm_ck(c01, C)).
tm_c01(2).
tm_c01(3).
tm_c02(1).
:- tm_wrap(tm_c02(_), n1, C, _), assertz(tm_ck(c02, C)).
tm_c02(2).
tm_c03(1).
:- tm_wrap(tm_c03(_), n1, C, _), assertz(tm_ck(c03a, C)).
tm_c03(2).
:- tm_wrap(tm_c03(_), n2, C, _), assertz(tm_ck(c03b, C)).
tm_c03(3).
:- tm_wrap(tm_c04(_), n1, C, _), assertz(tm_ck(c04, C)).
tm_c04(1).
tm_c04(2).
:- '$set_predicate_attribute'(tm_c05(_), tabled, true), '$set_predicate_attribute'(tm_c05(_), tabled_variant, true),
   tm_wrap(tm_c05(_), table, C, _), assertz(tm_ck(c05, C)).
tm_c05(1).
tm_c05(2).
tm_c06(1).
:- tm_c06(_).
:- tm_wrap(tm_c06(_), n1, C, _), assertz(tm_ck(c06, C)).
tm_c06(2).
t_tmt01(R) :- catch(('$tbl_trienode'(X), ( atom(X) -> R = atom ; R = notatom )), error(SsuE, _), R = raised(SsuE)).
t_tmt02(R) :- catch(('$tbl_trienode'(X), ( atomic(X) -> R = atomic ; R = notatomic )), error(SsuE, _), R = raised(SsuE)).
t_tmt03(R) :- catch(('$tbl_trienode'(X), tm_yn('$tbl_is_trienode'(X), R)), error(SsuE, _), R = raised(SsuE)).
t_tmt04(R) :- catch((tm_yn('$tbl_is_trienode'(a), R)), error(SsuE, _), R = raised(SsuE)).
t_tmt05(R) :- catch((tm_yn('$tbl_is_trienode'(trienode), R)), error(SsuE, _), R = raised(SsuE)).
t_tmt06(R) :- catch((tm_yn('$tbl_is_trienode'(_), R)), error(SsuE, _), R = raised(SsuE)).
t_tmt07(R) :- catch((tm_yn('$tbl_is_trienode'(f(a)), R)), error(SsuE, _), R = raised(SsuE)).
t_tmt08(R) :- catch((tm_yn('$tbl_is_trienode'([]), R)), error(SsuE, _), R = raised(SsuE)).
t_tmt09(R) :- catch((tm_yn('$tbl_is_trienode'(1), R)), error(SsuE, _), R = raised(SsuE)).
t_tmt10(R) :- catch(('$tbl_trienode'(X), '$tbl_trienode'(Y), ( X == Y -> R = same ; R = diff )), error(SsuE, _), R = raised(SsuE)).
t_tmt11(R) :- catch(('$tbl_trienode'(X), ( X == trienode -> R = eqtext ; R = neqtext )), error(SsuE, _), R = raised(SsuE)).
t_tmt12(R) :- catch((tm_yn('$tbl_trienode'(a), R)), error(SsuE, _), R = raised(SsuE)).
t_tmt13(R) :- catch((tm_yn('$tbl_trienode'(trienode), R)), error(SsuE, _), R = raised(SsuE)).
t_tmt14(R) :- catch(('$tbl_trienode'(X), Y = f(X), arg(1, Y, Z), tm_yn('$tbl_is_trienode'(Z), R)), error(SsuE, _), R = raised(SsuE)).
t_tmt15(R) :- catch(('$tbl_trienode'(X), compare(O, X, aaa), R = O), error(SsuE, _), R = raised(SsuE)).
t_tmt16(R) :- catch(('$tbl_trienode'(X), compare(O, X, []), R = O), error(SsuE, _), R = raised(SsuE)).
t_tmt17(R) :- catch(('$tbl_trienode'(X), ( var(X) -> R = var ; R = nonvar )), error(SsuE, _), R = raised(SsuE)).
t_tmt18(R) :- catch(('$tbl_trienode'(X), copy_term(X, Y), tm_yn('$tbl_is_trienode'(Y), R)), error(SsuE, _), R = raised(SsuE)).
t_tmt19(R) :- catch((findall(X, '$tbl_trienode'(X), L), length(L, R)), error(SsuE, _), R = raised(SsuE)).
t_tmt20(R) :- catch((retractall(tm_hold(_)), '$tbl_trienode'(X), assertz(tm_hold(X)), tm_hold(Y), tm_yn('$tbl_is_trienode'(Y), R)), error(SsuE, _), R = raised(SsuE)).
t_tmt21(R) :- catch(('$get_predicate_attribute'(system:'$tbl_trienode'(_), foreign, V), R = V), error(SsuE, _), R = raised(SsuE)).
t_tmt22(R) :- catch(('$get_predicate_attribute'(system:'$tbl_is_trienode'(_), foreign, V), R = V), error(SsuE, _), R = raised(SsuE)).
t_tma01(R) :- catch((tm_get(tm_a01(_), tabled, R)), error(SsuE, _), R = raised(SsuE)).
t_tma02(R) :- catch(('$set_predicate_attribute'(tm_a02(_), tabled, true), tm_get(tm_a02(_), tabled, R)), error(SsuE, _), R = raised(SsuE)).
t_tma03(R) :- catch(('$set_predicate_attribute'(tm_a03(_), tabled, true), tm_get(tm_a03(_), tabled_variant, R)), error(SsuE, _), R = raised(SsuE)).
t_tma04(R) :- catch(('$set_predicate_attribute'(tm_a04(_), tabled_variant, true), tm_get(tm_a04(_), tabled_variant, R)), error(SsuE, _), R = raised(SsuE)).
t_tma05(R) :- catch(('$set_predicate_attribute'(tm_a05(_), tabled, true), '$set_predicate_attribute'(tm_a05(_), tabled, false), tm_get(tm_a05(_), tabled, R)), error(SsuE, _), R = raised(SsuE)).
t_tma06(R) :- catch(('$set_predicate_attribute'(tm_a06(_), tabled, foo)), error(SsuE, _), R = raised(SsuE)).
t_tma07(R) :- catch(('$set_predicate_attribute'(tm_a07(_), tabled, _)), error(SsuE, _), R = raised(SsuE)).
t_tma08(R) :- catch(('$set_predicate_attribute'(tm_a08(_), tabled, 1), tm_get(tm_a08(_), tabled, R)), error(SsuE, _), R = raised(SsuE)).
t_tma09(R) :- catch(('$set_predicate_attribute'(tm_a09(_), incremental, true), tm_get(tm_a09(_), incremental, R)), error(SsuE, _), R = raised(SsuE)).
t_tma10(R) :- catch(('$set_predicate_attribute'(tm_a10(_), incremental, true), '$set_predicate_attribute'(tm_a10(_), incremental, false), tm_get(tm_a10(_), incremental, R)), error(SsuE, _), R = raised(SsuE)).
t_tma11(R) :- catch(('$set_predicate_attribute'(tm_a11(_), monotonic, true), tm_get(tm_a11(_), monotonic, M), tm_get(tm_a11(_), opaque, O), tm_get(tm_a11(_), tshared, S), R = r(M, O, S)), error(SsuE, _), R = raised(SsuE)).
t_tma12(R) :- catch(('$set_predicate_attribute'(tm_a12(_), tshared, true), '$set_predicate_attribute'(tm_a12(_), opaque, true), '$set_predicate_attribute'(tm_a12(_), lazy, true), tm_get(tm_a12(_), tshared, S), tm_get(tm_a12(_), opaque, O), tm_get(tm_a12(_), lazy, L), R = r(S, O, L)), error(SsuE, _), R = raised(SsuE)).
t_tma13(R) :- catch(('$set_predicate_attribute'(tm_a13(_), abstract, infinite), tm_get(tm_a13(_), abstract, R)), error(SsuE, _), R = raised(SsuE)).
t_tma14(R) :- catch(('$set_predicate_attribute'(tm_a14(_), abstract, 5), tm_get(tm_a14(_), abstract, R)), error(SsuE, _), R = raised(SsuE)).
t_tma15(R) :- catch(('$set_predicate_attribute'(tm_a15(_), abstract, -1)), error(SsuE, _), R = raised(SsuE)).
t_tma16(R) :- catch(('$set_predicate_attribute'(tm_a16(_), abstract, foo)), error(SsuE, _), R = raised(SsuE)).
t_tma17(R) :- catch(('$set_predicate_attribute'(tm_a17(_), abstract, _)), error(SsuE, _), R = raised(SsuE)).
t_tma18(R) :- catch(('$set_predicate_attribute'(tm_a18(_), subgoal_abstract, 3), '$set_predicate_attribute'(tm_a18(_), answer_abstract, 4), tm_get(tm_a18(_), subgoal_abstract, S), tm_get(tm_a18(_), answer_abstract, A), tm_get(tm_a18(_), abstract, B), R = r(S, A, B)), error(SsuE, _), R = raised(SsuE)).
t_tma19(R) :- catch(('$set_predicate_attribute'(tm_a19(_), max_answers, 7), tm_get(tm_a19(_), max_answers, A), '$set_predicate_attribute'(tm_a19(_), max_answers, infinite), tm_get(tm_a19(_), max_answers, B), R = r(A, B)), error(SsuE, _), R = raised(SsuE)).
t_tma20(R) :- catch(('$set_predicate_attribute'(tm_a20(_), incremental, true), tm_get(tm_a20(_), tabled, R)), error(SsuE, _), R = raised(SsuE)).
t_tma21(R) :- catch(('$set_predicate_attribute'(tm_a21(_), tabled, true), tm_get(tm_a21(_), tabled, T), tm_get(tm_a21(_), defined, D), R = r(T, D)), error(SsuE, _), R = raised(SsuE)).
t_tma22(R) :- catch(('$set_predicate_attribute'(tm_x22(_), tabled, true), '$set_predicate_attribute'(tm_x22(_), abstract, 5), abolish(tm_x22/1), tm_get(tm_x22(_), tabled, T), tm_get(tm_x22(_), abstract, A), R = r(T, A)), error(SsuE, _), R = raised(SsuE)).
t_tma23(R) :- catch(('$set_predicate_attribute'(tm_a23(_), tabled, true), tm_get(tm_a23(_), incremental, I), tm_get(tm_a23(_), monotonic, M), R = r(I, M)), error(SsuE, _), R = raised(SsuE)).
t_tmw01(R) :- catch((tm_wrap(tm_w01(_), n1, _, _), tm_nc(tm_w01(_), A), tm_nc('$wrap$tm_w01'(_), B), R = r(A, B)), error(SsuE, _), R = raised(SsuE)).
t_tmw02(R) :- catch((tm_wrap(tm_w02(_), n1, C, _), blob(C, T), R = T), error(SsuE, _), R = raised(SsuE)).
t_tmw03(R) :- catch((tm_wrap(tm_w03(P), n1, _, call(W)), functor(W, N, A), blob(N, T), arg(1, W, X), tm_same(X, P, S), R = r(A, T, S)), error(SsuE, _), R = raised(SsuE)).
t_tmw04(R) :- catch((tm_wrap(tm_w04, n1, C, call(W)), blob(W, T), tm_same(W, C, S), R = r(T, S)), error(SsuE, _), R = raised(SsuE)).
t_tmw05(R) :- catch((tm_wrap(tm_w05(_), n1, C1, call(W1)), tm_wrap(tm_w05(_), n1, C2, call(W2)), tm_same(C1, C2, S), functor(W1, N1, _), functor(W2, N2, _), tm_same(N1, N2, S2), tm_nc('$wrap$tm_w05'(_), N), R = r(S, S2, N)), error(SsuE, _), R = raised(SsuE)).
t_tmw06(R) :- catch((tm_wrap(tm_w06(_), n1, C1, _), tm_wrap(tm_w06(_), n2, C2, _), tm_same(C1, C2, S), tm_nc('$wrap$tm_w06'(_), N), R = r(S, N)), error(SsuE, _), R = raised(SsuE)).
t_tmw07(R) :- catch((tm_wrap(tm_w07(_), n1, C1, _), tm_wrap(tm_w07b(_), n1, C2, _), tm_same(C1, C2, R)), error(SsuE, _), R = raised(SsuE)).
t_tmw08(R) :- catch(('$c_wrap_predicate'(user:tm_w08(_), 1, _, _, user:('$wrap$tm_w08'(_) :- true))), error(SsuE, _), R = raised(SsuE)).
t_tmw09(R) :- catch(('$c_wrap_predicate'(user:tm_w09(_), _, _, _, user:('$wrap$tm_w09'(_) :- true))), error(SsuE, _), R = raised(SsuE)).
t_tmw10(R) :- catch(('$c_wrap_predicate'(_, n1, _, _, user:('$wrap$tm_w10'(_) :- true))), error(SsuE, _), R = raised(SsuE)).
t_tmw11(R) :- catch(('$c_wrap_predicate'(user:tm_w11(_), n1, _, _, _)), error(SsuE, _), R = raised(SsuE)).
t_tmw12(R) :- catch((tm_wrapb(tm_w12(_), n1, C, call(W), tm_h(C, W)), clause('$wrap$tm_w12'(Z), B), B = tm_h(C2, W2), tm_same(C2, C, S1), functor(W2, N2, A2), functor(W, N, _), tm_same(N2, N, S2), arg(1, W2, X), tm_same(X, Z, S3), R = r(S1, S2, A2, S3)), error(SsuE, _), R = raised(SsuE)).
t_tmw13(R) :- catch((tm_wrap(tm_w13(_), n1, _, _), findall(X, clause(tm_w13(X), true), L), R = L), error(SsuE, _), R = raised(SsuE)).
t_tmw14(R) :- catch((tm_wrap(tm_w14(P, Q), n1, _, call(W)), functor(W, _, A), arg(1, W, X), arg(2, W, Y), tm_same(X, P, S1), tm_same(Y, Q, S2), tm_same(X, Y, S3), R = r(A, S1, S2, S3)), error(SsuE, _), R = raised(SsuE)).
t_tmw15(R) :- catch((tm_wrap(tm_w15(a, P, c), n1, _, call(W)), arg(1, W, X1), arg(2, W, X2), arg(3, W, X3), tm_same(X2, P, S), R = r(X1, S, X3)), error(SsuE, _), R = raised(SsuE)).
t_tmc01(R) :- catch((tm_nc(tm_c01(_), A), tm_nc('$wrap$tm_c01'(_), B), R = r(A, B)), error(SsuE, _), R = raised(SsuE)).
t_tmc02(R) :- catch((tm_ck(c02, C0), tm_wrap(tm_c02(_), n1, C1, _), tm_same(C0, C1, S), tm_nc('$wrap$tm_c02'(_), N), R = r(S, N)), error(SsuE, _), R = raised(SsuE)).
t_tmc03(R) :- catch((tm_ck(c03a, A0), tm_ck(c03b, B0), tm_wrap(tm_c03(_), n1, A1, _), tm_wrap(tm_c03(_), n2, B1, _), tm_same(A0, A1, S1), tm_same(B0, B1, S2), tm_same(A0, B0, S3), tm_nc('$wrap$tm_c03'(_), N), R = r(S1, S2, S3, N)), error(SsuE, _), R = raised(SsuE)).
t_tmc04(R) :- catch((tm_nc(tm_c04(_), A), tm_nc('$wrap$tm_c04'(_), B), R = r(A, B)), error(SsuE, _), R = raised(SsuE)).
t_tmc05(R) :- catch((tm_get(tm_c05(_), tabled, T), tm_get(tm_c05(_), tabled_variant, V), tm_nc(tm_c05(_), A), tm_nc('$wrap$tm_c05'(_), B), R = r(T, V, A, B)), error(SsuE, _), R = raised(SsuE)).
t_tmc06(R) :- catch((tm_ck(c05, C0), tm_wrap(tm_c05(_), table, C1, _), tm_same(C0, C1, R)), error(SsuE, _), R = raised(SsuE)).
t_tmc07(R) :- catch((tm_ck(c06, C0), tm_wrap(tm_c06(_), n1, C1, _), tm_same(C0, C1, S), tm_nc(tm_c06(_), A), tm_nc('$wrap$tm_c06'(_), B), R = r(S, A, B)), error(SsuE, _), R = raised(SsuE)).
t_tmd01(R) :- catch((tm_wrap(tm_d01(_), n1, C1, _), '$set_predicate_attribute'(user:tm_d01(_), dynamic, true), tm_wrap(tm_d01(_), n1, C2, _), tm_same(C1, C2, S), tm_get(tm_d01(_), dynamic, D), R = r(S, D)), error(SsuE, _), R = raised(SsuE)).
t_tmd02(R) :- catch((tm_wrap(tm_d02(_), n1, C1, _), '$set_predicate_attribute'(user:tm_d02(_), dynamic, true), abolish(user:tm_d02/1), tm_wrap(tm_d02(_), n1, C2, _), tm_same(C1, C2, S), R = S), error(SsuE, _), R = raised(SsuE)).
