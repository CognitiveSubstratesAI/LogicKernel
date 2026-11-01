gv_member(X, [X|_]).
gv_member(X, [_|T]) :- gv_member(X, T).
gv_forall(C, A) :- \+ ( C, \+ A ).
gv_len(L, N) :- gv_len(L, 0, N).
gv_len([], N, N).
gv_len([_|T], N0, N) :- N1 is N0+1, gv_len(T, N1, N).
gv_dom:attr_unify_hook(_, _).
user:exception(undefined_global_variable, gv_auto, retry) :- nb_setval(gv_auto, 42).
user:exception(undefined_global_variable, gv_fl, fail).
user:exception(undefined_global_variable, gv_er, error).
user:exception(undefined_global_variable, gv_bad, foo).
user:exception(undefined_global_variable, gv_cnt, retry) :- nb_getval(gv_cnt_calls, N), N1 is N+1, nb_setval(gv_cnt_calls, N1).
t_g01(R) :- catch((nb_setval(gv_a, 1), nb_getval(gv_a, R)), error(SsuE, _), R = raised(SsuE)).
t_g02(R) :- catch((nb_setval(gv_b, f(X, _, X)), nb_getval(gv_b, R)), error(SsuE, _), R = raised(SsuE)).
t_g03(R) :- catch((nb_setval(gv_h6, f(_, _)), R = stored), error(SsuE, _), R = raised(SsuE)).
t_g04(R) :- catch((nb_getval(gv_h6, R)), error(SsuE, _), R = raised(SsuE)).
t_g05(R) :- catch((nb_setval(gv_h6b, g(_, _)), gv_forall(between(1, 10000, _), catch(throw(ball(_, _)), _, true)), nb_getval(gv_h6b, R)), error(SsuE, _), R = raised(SsuE)).
t_g06(R) :- catch((nb_getval(gv_h6b, R)), error(SsuE, _), R = raised(SsuE)).
t_g07(R) :- catch((nb_setval(gv_c, X), X = 1, nb_getval(gv_c, R)), error(SsuE, _), R = raised(SsuE)).
t_g08(R) :- catch((( nb_setval(gv_d, X), X = 1, fail ; nb_getval(gv_d, R) )), error(SsuE, _), R = raised(SsuE)).
t_g09(R) :- catch((nb_setval(gv_e, X), b_setval(gv_e, 1), R = X), error(SsuE, _), R = raised(SsuE)).
t_g10(R) :- catch((b_setval(gv_f, 1), b_setval(gv_f, f(_)), b_getval(gv_f, R)), error(SsuE, _), R = raised(SsuE)).
t_g11(R) :- catch((( b_setval(gv_v, 1), fail ; true ), b_getval(gv_v, R)), error(SsuE, _), R = raised(SsuE)).
t_g12(R) :- catch((b_setval(gv_w, 1), b_setval(gv_w, 2), b_getval(gv_w, R)), error(SsuE, _), R = raised(SsuE)).
t_g13(R) :- catch((findall(V, ( gv_member(X, [1, 2, 3]), b_setval(gv_x, X), b_getval(gv_x, V) ), R)), error(SsuE, _), R = raised(SsuE)).
t_g14(R) :- catch((b_setval(gv_y, 1), ( b_setval(gv_y, 2), fail ; b_getval(gv_y, R) )), error(SsuE, _), R = raised(SsuE)).
t_g15(R) :- catch((X = f(X), nb_setval(gv_cy, X), nb_getval(gv_cy, Y), Y = f(Y), R = yes), error(SsuE, _), R = raised(SsuE)).
t_g16(R) :- catch((nb_linkval(gv_l, f(X)), nb_getval(gv_l, f(Y)), ( Y == X -> R = same ; R = diff )), error(SsuE, _), R = raised(SsuE)).
t_g17(R) :- catch((nb_setval(gv_l2, f(X)), nb_getval(gv_l2, f(Y)), ( Y == X -> R = same ; R = diff )), error(SsuE, _), R = raised(SsuE)).
t_g18(R) :- catch((nb_linkval(gv_l3, f(X)), X = 1, nb_getval(gv_l3, R)), error(SsuE, _), R = raised(SsuE)).
t_g19(R) :- catch((nb_setval(gv_n1, a), nb_setval(gv_n2, b), nb_setval(gv_n3, c), findall(K, ( nb_current(K, _), gv_member(K, [gv_n1, gv_n2, gv_n3]) ), L), msort(L, R)), error(SsuE, _), R = raised(SsuE)).
t_g20(R) :- catch((nb_current(gv_n2, R)), error(SsuE, _), R = raised(SsuE)).
t_g21(R) :- catch((findall(K, ( nb_current(K, b), gv_member(K, [gv_n1, gv_n2, gv_n3]) ), R)), error(SsuE, _), R = raised(SsuE)).
t_g22(R) :- catch((nb_setval(gv_dd, 1), nb_delete(gv_dd), ( nb_current(gv_dd, _) -> R = still ; R = gone )), error(SsuE, _), R = raised(SsuE)).
t_g23(R) :- catch((( nb_delete(gv_never) -> R = yes ; R = no )), error(SsuE, _), R = raised(SsuE)).
t_g24(R) :- catch((nb_getval(gv_nokey, _)), error(SsuE, _), R = raised(SsuE)).
t_g25(R) :- catch((catch(nb_getval(gv_nokey2, _), E, true), R = E), error(SsuE, _), R = raised(SsuE)).
t_g26(R) :- catch((nb_setval(1, a)), error(SsuE, _), R = raised(SsuE)).
t_g27(R) :- catch((nb_setval(f(x), a)), error(SsuE, _), R = raised(SsuE)).
t_g28(R) :- catch((nb_setval(_, a)), error(SsuE, _), R = raised(SsuE)).
t_g29(R) :- catch((nb_getval(f(x), _)), error(SsuE, _), R = raised(SsuE)).
t_g30(R) :- catch((b_setval(f(x), a)), error(SsuE, _), R = raised(SsuE)).
t_g31(R) :- catch((b_getval(_, _)), error(SsuE, _), R = raised(SsuE)).
t_g32(R) :- catch((nb_delete(f(x))), error(SsuE, _), R = raised(SsuE)).
t_g33(R) :- catch((nb_delete(_)), error(SsuE, _), R = raised(SsuE)).
t_g34(R) :- catch((( nb_current(f(x), _) -> R = yes ; R = no )), error(SsuE, _), R = raised(SsuE)).
t_g35(R) :- catch((S = "str", nb_setval(gv_s, S), nb_getval(gv_s, R)), error(SsuE, _), R = raised(SsuE)).
t_g36(R) :- catch((nb_setval(gv_fl2, 1.5), nb_getval(gv_fl2, R)), error(SsuE, _), R = raised(SsuE)).
t_g37(R) :- catch((nb_setval(gv_bi, 100000000000000000000), nb_getval(gv_bi, R)), error(SsuE, _), R = raised(SsuE)).
t_g38(R) :- catch((nb_setval(gv_ow, a), nb_setval(gv_ow, b), nb_getval(gv_ow, R)), error(SsuE, _), R = raised(SsuE)).
t_g39(R) :- catch((( nb_current(gv_nope, _) -> R = yes ; R = no )), error(SsuE, _), R = raised(SsuE)).
t_g40(R) :- catch((b_setval(gv_bg, f(_)), nb_getval(gv_bg, R)), error(SsuE, _), R = raised(SsuE)).
t_g41(R) :- catch((( gv_member(X, [1, 2]), nb_setval(gv_t, X), fail ; nb_getval(gv_t, R) )), error(SsuE, _), R = raised(SsuE)).
t_g42(R) :- catch((put_attr(X, gv_dom, 1), nb_setval(gv_av, X), nb_getval(gv_av, Y), get_attr(Y, gv_dom, R)), error(SsuE, _), R = raised(SsuE)).
t_g43(R) :- catch((b_setval(gv_nest, a), ( \+ \+ ( b_setval(gv_nest, b), b_getval(gv_nest, I), I == b ) -> b_getval(gv_nest, R) ; R = bad )), error(SsuE, _), R = raised(SsuE)).
t_g44(R) :- catch((nb_getval(gv_auto, R)), error(SsuE, _), R = raised(SsuE)).
t_g45(R) :- catch((( nb_getval(gv_fl, _) -> R = yes ; R = no )), error(SsuE, _), R = raised(SsuE)).
t_g46(R) :- catch((nb_getval(gv_er, _)), error(SsuE, _), R = raised(SsuE)).
t_g47(R) :- catch((nb_getval(gv_bad, _)), error(SsuE, _), R = raised(SsuE)).
t_g48(R) :- catch((nb_setval(gv_cnt_calls, 0), catch(nb_getval(gv_cnt, _), _, true), nb_getval(gv_cnt_calls, R)), error(SsuE, _), R = raised(SsuE)).
t_g49(R) :- catch((b_setval(gv_u, X), X = 1, b_getval(gv_u, R)), error(SsuE, _), R = raised(SsuE)).
t_g50(R) :- catch((nb_setval(gv_u2, _), nb_getval(gv_u2, R)), error(SsuE, _), R = raised(SsuE)).
t_g51(R) :- catch((nb_setval([], 1)), error(SsuE, _), R = raised(SsuE)).
t_g52(R) :- catch((gv_forall(between(1, 300, I), ( atom_concat(gv_k_, I, K), nb_setval(K, I) )), findall(K-V, nb_current(K, V), All), findall(I, ( between(1, 300, I), atom_concat(gv_k_, I, K), gv_member(K-I, All) ), Is), gv_len(Is, R)), error(SsuE, _), R = raised(SsuE)).
t_g53(R) :- catch((nb_setval(gv_m1, x), nb_setval(gv_m2, x), findall(K, ( nb_current(K, x), gv_member(K, [gv_m1, gv_m2]), nb_setval(gv_new_during, 1) ), L), msort(L, S), nb_current(gv_new_during, N), R = S-N), error(SsuE, _), R = raised(SsuE)).
t_g54(R) :- catch((b_setval(gv_mix, 1), nb_setval(gv_mix, 2), nb_getval(gv_mix, R)), error(SsuE, _), R = raised(SsuE)).
t_g55(R) :- catch((nb_setval(gv_mix2, a), ( b_setval(gv_mix2, b), fail ; nb_getval(gv_mix2, R) )), error(SsuE, _), R = raised(SsuE)).
t_g56(R) :- catch((nb_setval(gv_k1, f(_)), nb_getval(gv_k1, A), nb_getval(gv_k1, B), ( A == B -> R = same ; R = diff )), error(SsuE, _), R = raised(SsuE)).
t_g57(R) :- catch((nb_setval(gv_nv, 1), nb_delete(gv_nv), findall(K, ( nb_current(K, _), K == gv_nv ), R)), error(SsuE, _), R = raised(SsuE)).
