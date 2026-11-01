dpairs(D, Ps) :- findall(K-V, get_dict(K, D, V), Ps0), msort(Ps0, Ps).
dp_mem(X, [X|_]).
dp_mem(X, [_|T]) :- dp_mem(X, T).
t_dp01(R) :- catch((dict_create(D, t, [a-1, b-2]), '$get_dict_ex'(a, D, V), R = V), error(SsuE, _), R = raised(SsuE)).
t_dp02(R) :- catch((dict_create(D, t, [a-1, b-2]), '$get_dict_ex'(b, D, V), R = V), error(SsuE, _), R = raised(SsuE)).
t_dp03(R) :- catch((dict_create(D, t, [a-1, b-2]), catch('$get_dict_ex'(c, D, _), error(existence_error(T, K, _), _), R = ex(T, K))), error(SsuE, _), R = raised(SsuE)).
t_dp04(R) :- catch(('$get_dict_ex'(a, foo, V), R = V), error(SsuE, _), R = raised(SsuE)).
t_dp05(R) :- catch(('$get_dict_ex'(a, _, V), R = V), error(SsuE, _), R = raised(SsuE)).
t_dp06(R) :- catch((dict_create(D, t, [a-1, b-2, c-3]), findall(K-V, '$get_dict_ex'(K, D, V), L), msort(L, R)), error(SsuE, _), R = raised(SsuE)).
t_dp07(R) :- catch((dict_create(D, t, [a-1, b-2]), '$get_dict_ex'(1.5, D, V), R = V), error(SsuE, _), R = raised(SsuE)).
t_dp08(R) :- catch((dict_create(D, t, [a-1, b-2]), '$get_dict_ex'(a, D, 2), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dp09(R) :- catch((dict_create(D, t, [1-one]), '$get_dict_ex'(1, D, V), R = V), error(SsuE, _), R = raised(SsuE)).
t_dp10(R) :- catch((dict_create(D, t, [a-1, b-2, c-3]), findall(K, '$get_dict_ex'(K, D, 2), R)), error(SsuE, _), R = raised(SsuE)).
t_dp11(R) :- catch((dict_create(D, t, []), findall(K, '$get_dict_ex'(K, D, _), R)), error(SsuE, _), R = raised(SsuE)).
t_dp12(R) :- catch((dict_create(D, t, [a-1]), findall(V, '$get_dict_ex'(a, D, V), R)), error(SsuE, _), R = raised(SsuE)).
t_dp13(R) :- catch((dict_create(D, t, [a-1, b-2]), get_dict(a, D, V, N, 9), dpairs(N, P), R = V-P), error(SsuE, _), R = raised(SsuE)).
t_dp14(R) :- catch((dict_create(D, t, [a-1, b-2]), get_dict(b, D, V, N, 9), dpairs(N, P), R = V-P), error(SsuE, _), R = raised(SsuE)).
t_dp15(R) :- catch((dict_create(D, t, [a-1, b-2]), get_dict(c, D, V, N, 9), R = V-N), error(SsuE, _), R = raised(SsuE)).
t_dp16(R) :- catch((dict_create(D, t, [a-1, b-2]), get_dict(a, D, 2, N, 9), R = N), error(SsuE, _), R = raised(SsuE)).
t_dp17(R) :- catch((dict_create(D, t, [a-1]), get_dict(1.5, D, V, N, 9), R = V-N), error(SsuE, _), R = raised(SsuE)).
t_dp18(R) :- catch((dict_create(D, t, [a-1]), get_dict(_, D, V, N, 9), R = V-N), error(SsuE, _), R = raised(SsuE)).
t_dp19(R) :- catch((get_dict(a, foo, V, N, 9), R = V-N), error(SsuE, _), R = raised(SsuE)).
t_dp20(R) :- catch((get_dict(a, [a-1, b-2], V, N, 9), dpairs(N, P), R = V-P), error(SsuE, _), R = raised(SsuE)).
t_dp21(R) :- catch((dict_create(D, t, [a-1]), get_dict(a, D, _, N, X), get_dict(a, N, Y), Y == X, R = yes), error(SsuE, _), R = raised(SsuE)).
t_dp22(R) :- catch((dict_create(D, t, [a-1]), get_dict(a, D, V, N, 9), get_dict(a, N, Y), dpairs(D, P0), R = V-Y-P0), error(SsuE, _), R = raised(SsuE)).
t_dp23(R) :- catch((dict_create(D, t, [a-1]), get_dict(a, D, 1, N, 1), dpairs(N, P), R = P), error(SsuE, _), R = raised(SsuE)).
t_dp24(R) :- catch((dict_create(D, t, [a-X, b-Y]), get_dict(a, D, 5, N, Z), dpairs(N, P), R = X-Y-P-Z), error(SsuE, _), R = raised(SsuE)).
t_dp25(R) :- catch((dict_create(D, t, [a-1]), get_dict(a, D, _, N, f(Q)), get_dict(a, N, f(7)), R = Q), error(SsuE, _), R = raised(SsuE)).
t_dp26(R) :- catch((dict_create(D, t, [a-1, b-2]), get_dict(a, D, _, N, 9), is_dict(N, T), R = T), error(SsuE, _), R = raised(SsuE)).
t_dp27(R) :- catch((dict_create(D, t, [a-1]), get_dict(f(x), D, V, N, 9), R = V-N), error(SsuE, _), R = raised(SsuE)).
t_dp28(R) :- catch((dict_create(D, t, [1-a, 2-b]), get_dict(2, D, V, N, z), dpairs(N, P), R = V-P), error(SsuE, _), R = raised(SsuE)).
t_dp29(R) :- catch((dict_create(D, t, [a-1]), get_dict(a, D, V, foo, 9), R = V), error(SsuE, _), R = raised(SsuE)).
t_dp30(R) :- catch((dict_create(D, t, [a-1, b-2, c-3]), get_dict(b, D, _, N, new), dict_pairs(N, T, P), R = T-P), error(SsuE, _), R = raised(SsuE)).
t_dp31(R) :- catch((dict_create(D, t, [a-1]), put_dict(b, D, 2, N), dpairs(N, R)), error(SsuE, _), R = raised(SsuE)).
t_dp32(R) :- catch((dict_create(D, t, [a-1, b-2]), put_dict(a, D, 9, N), dpairs(N, R)), error(SsuE, _), R = raised(SsuE)).
t_dp33(R) :- catch((dict_create(D, t, []), put_dict(a, D, 1, N), dpairs(N, R)), error(SsuE, _), R = raised(SsuE)).
t_dp34(R) :- catch((put_dict(c, [a-1, b-2], 3, N), dpairs(N, R)), error(SsuE, _), R = raised(SsuE)).
t_dp35(R) :- catch((dict_create(D, t, [a-1]), put_dict(1.5, D, x, N), R = N), error(SsuE, _), R = raised(SsuE)).
t_dp36(R) :- catch((dict_create(D, t, [a-1]), put_dict(_, D, x, N), R = N), error(SsuE, _), R = raised(SsuE)).
t_dp37(R) :- catch((put_dict(a, foo, x, N), R = N), error(SsuE, _), R = raised(SsuE)).
t_dp38(R) :- catch((put_dict(a, _, x, N), R = N), error(SsuE, _), R = raised(SsuE)).
t_dp39(R) :- catch((dict_create(D, t, [a-1]), put_dict(a, D, 1, N), dpairs(N, R)), error(SsuE, _), R = raised(SsuE)).
t_dp40(R) :- catch((dict_create(D, t, [a-1]), put_dict(b, D, X, N), get_dict(b, N, Y), X = 5, R = Y), error(SsuE, _), R = raised(SsuE)).
t_dp41(R) :- catch((dict_create(D, t, [a-1]), put_dict(b, D, 2, _), dpairs(D, R)), error(SsuE, _), R = raised(SsuE)).
t_dp42(R) :- catch((dict_create(D, t, [b-1, d-1]), put_dict(c, D, 2, N), put_dict(a, N, 3, M), put_dict(e, M, 4, Q), dpairs(Q, R)), error(SsuE, _), R = raised(SsuE)).
t_dp43(R) :- catch((dict_create(D, t, [a-1]), put_dict(b, D, 2, N), is_dict(N, T), R = T), error(SsuE, _), R = raised(SsuE)).
t_dp44(R) :- catch((dict_create(D, t, [a-1]), put_dict(b, D, 2, N), put_dict(b, D, 2, N2), N == N2, R = same), error(SsuE, _), R = raised(SsuE)).
t_dp45(R) :- catch((dict_create(D, t, [1-a]), put_dict(2, D, b, N), put_dict(c, N, x, M), dpairs(M, R)), error(SsuE, _), R = raised(SsuE)).
t_dp46(R) :- catch((dict_create(D, t, [a-1]), put_dict(b, D, 2, N), put_dict(b, N, 3, M), dpairs(M, R)), error(SsuE, _), R = raised(SsuE)).
t_dp47(R) :- catch((dict_create(D, T, [a-1]), put_dict(b, D, 2, N), is_dict(N, T2), T2 == T, R = yes), error(SsuE, _), R = raised(SsuE)).
t_dp48(R) :- catch((dict_create(D, t, [a-1]), put_dict(a, D, 2, N), get_dict(a, D, V), get_dict(a, N, W), R = V-W), error(SsuE, _), R = raised(SsuE)).
t_dp49(R) :- catch((dict_create(D, t, [a-1]), put_dict(b, D, 2, foo), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dp50(R) :- catch((dict_create(D, t, [b-2, a-1, c-3]), dict_pairs(D, T, P), R = T-P), error(SsuE, _), R = raised(SsuE)).
t_dp51(R) :- catch((dict_create(D, t, [b-1, 2-x, a-3, 1-y]), dict_pairs(D, _, P), R = P), error(SsuE, _), R = raised(SsuE)).
t_dp52(R) :- catch((dict_create(D, t, []), dict_pairs(D, T, P), R = T-P), error(SsuE, _), R = raised(SsuE)).
t_dp53(R) :- catch((dict_pairs(D, t, [a-1, b-2]), dpairs(D, R)), error(SsuE, _), R = raised(SsuE)).
t_dp54(R) :- catch((dict_pairs(D, t, [b-2, a-1]), dict_pairs(D, T, P), R = T-P), error(SsuE, _), R = raised(SsuE)).
t_dp55(R) :- catch((dict_pairs(D, T, [a-1]), is_dict(D, T2), T2 == T, R = yes), error(SsuE, _), R = raised(SsuE)).
t_dp56(R) :- catch((dict_pairs(D, t, []), is_dict(D, T), R = T), error(SsuE, _), R = raised(SsuE)).
t_dp57(R) :- catch((dict_pairs(D, t, [a-1, a-2]), R = D), error(SsuE, _), R = raised(SsuE)).
t_dp58(R) :- catch((dict_pairs(D, t, [a=1]), R = D), error(SsuE, _), R = raised(SsuE)).
t_dp59(R) :- catch((dict_pairs(D, t, [a:1]), R = D), error(SsuE, _), R = raised(SsuE)).
t_dp60(R) :- catch((dict_pairs(D, t, [a(1)]), R = D), error(SsuE, _), R = raised(SsuE)).
t_dp61(R) :- catch((dict_pairs(D, t, foo), R = D), error(SsuE, _), R = raised(SsuE)).
t_dp62(R) :- catch((dict_pairs(D, t, _), R = D), error(SsuE, _), R = raised(SsuE)).
t_dp63(R) :- catch((dict_pairs(D, t, [a-1|_]), R = D), error(SsuE, _), R = raised(SsuE)).
t_dp64(R) :- catch((dict_pairs(D, t, [1.5-a]), R = D), error(SsuE, _), R = raised(SsuE)).
t_dp65(R) :- catch((dict_pairs(foo, T, P), R = T-P), error(SsuE, _), R = raised(SsuE)).
t_dp66(R) :- catch((dict_pairs(_, _, _), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dp67(R) :- catch((dict_create(D, t, [a-1]), dict_pairs(D, u, P), R = P), error(SsuE, _), R = raised(SsuE)).
t_dp68(R) :- catch((dict_create(D, t, [a-1]), dict_pairs(D, t, [a-1]), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dp69(R) :- catch((dict_create(D, t, [a-1]), dict_pairs(D, t, [b-1]), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dp70(R) :- catch((dict_create(D, t, [a-1, b-2]), dict_pairs(D, t, [a-X, b-Y]), R = X-Y), error(SsuE, _), R = raised(SsuE)).
t_dp71(R) :- catch((dict_create(D, t, [a-1, b-2]), dict_pairs(D, t, [a-1]), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dp72(R) :- catch((dict_create(D, t, [a-1]), dict_pairs(D, t, [a-1, b-2]), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dp73(R) :- catch((dict_create(D, t, [a-1]), dict_pairs(D, t, foo), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dp74(R) :- catch((dict_create(D, t, [a-f(X), b-X, c-1.5]), dict_pairs(D, _, P), R = P), error(SsuE, _), R = raised(SsuE)).
t_dp75(R) :- catch((dict_create(D, t, [a-1, b-2]), dict_pairs(D, t, P), findall(x, dict_pairs(D, t, _), L), R = P-L), error(SsuE, _), R = raised(SsuE)).
t_dp76(R) :- catch((dict_create(D, t, [a-1]), dict_pairs(D, T, P), P = [K-V], R = K-V-T), error(SsuE, _), R = raised(SsuE)).
t_dp77(R) :- catch((dict_pairs([a-1, b-2], T, P), R = T-P), error(SsuE, _), R = raised(SsuE)).
t_dp78(R) :- catch((dict_pairs(D, t, [a-X]), dict_pairs(D, t, [a-1]), R = X), error(SsuE, _), R = raised(SsuE)).
t_dp79(R) :- catch((dict_create(D, t, [a-1]), dict_pairs(D, t, [a-1|T]), R = T), error(SsuE, _), R = raised(SsuE)).
t_dp80(R) :- catch((dict_pairs(D, t, [h-8, g-7, f-6, e-5, d-4, c-3, b-2, a-1]), dict_pairs(D, _, P), R = P), error(SsuE, _), R = raised(SsuE)).
t_dp81(R) :- catch((dict_pairs(D, t, [x-1, 5-a, y-2, 3-b]), dict_pairs(D, _, P), R = P), error(SsuE, _), R = raised(SsuE)).
t_dp82(R) :- catch((dict_create(D, t, [a-1, b-2]), del_dict(a, D, V, N), dpairs(N, P), R = V-P), error(SsuE, _), R = raised(SsuE)).
t_dp83(R) :- catch((dict_create(D, t, [a-1, b-2]), del_dict(b, D, V, N), dpairs(N, P), R = V-P), error(SsuE, _), R = raised(SsuE)).
t_dp84(R) :- catch((dict_create(D, t, [a-1, b-2]), del_dict(c, D, V, N), R = V-N), error(SsuE, _), R = raised(SsuE)).
t_dp85(R) :- catch((dict_create(D, t, [a-1, b-2]), del_dict(a, D, 2, N), R = N), error(SsuE, _), R = raised(SsuE)).
t_dp86(R) :- catch((dict_create(D, t, [a-1]), del_dict(1.5, D, V, N), R = V-N), error(SsuE, _), R = raised(SsuE)).
t_dp87(R) :- catch((dict_create(D, t, [a-1]), del_dict(_, D, V, N), R = V-N), error(SsuE, _), R = raised(SsuE)).
t_dp88(R) :- catch((del_dict(a, foo, V, N), R = V-N), error(SsuE, _), R = raised(SsuE)).
t_dp89(R) :- catch((dict_create(D, t, [a-1]), del_dict(a, D, V, N), dict_pairs(N, T, P), R = V-T-P), error(SsuE, _), R = raised(SsuE)).
t_dp90(R) :- catch((del_dict(a, [a-1, b-2], V, N), dpairs(N, P), R = V-P), error(SsuE, _), R = raised(SsuE)).
t_dp91(R) :- catch((dict_create(D, t, [a-X, b-Y]), del_dict(a, D, 5, _), R = X-Y), error(SsuE, _), R = raised(SsuE)).
t_dp92(R) :- catch((dict_create(D, t, [a-1, b-2, c-3]), del_dict(b, D, _, N), dpairs(D, P0), dpairs(N, P), R = P0-P), error(SsuE, _), R = raised(SsuE)).
t_dp93(R) :- catch((dict_create(D, T, [a-1, b-2]), del_dict(a, D, _, N), is_dict(N, T2), T2 == T, R = yes), error(SsuE, _), R = raised(SsuE)).
t_dp94(R) :- catch((dict_create(D, t, [1-x, a-y]), del_dict(1, D, V, N), dpairs(N, P), R = V-P), error(SsuE, _), R = raised(SsuE)).
t_dp95(R) :- catch((dict_create(D, t, [a-f(Z)]), del_dict(a, D, f(3), _), R = Z), error(SsuE, _), R = raised(SsuE)).
t_dp96(R) :- catch((dict_create(D, t, [a-1]), del_dict(a, D, _, foo), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dp97(R) :- catch((dict_create(D, t, [a-1, b-2]), del_dict(a, D, V, N), del_dict(b, N, W, M), dict_pairs(M, T, P), R = V-W-T-P), error(SsuE, _), R = raised(SsuE)).
t_dp98(R) :- catch((dict_create(S, _, [a-X]), dict_create(F, t, [a-1, b-2]), ':<'(S, F), R = X), error(SsuE, _), R = raised(SsuE)).
t_dp99(R) :- catch((dict_create(S, s, [a-1]), dict_create(F, t, [a-1, b-2]), ':<'(S, F), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dp100(R) :- catch((dict_create(S, _, [a-1, c-3]), dict_create(F, t, [a-1, b-2]), ':<'(S, F), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dp101(R) :- catch((dict_create(S, _, [a-2]), dict_create(F, t, [a-1, b-2]), ':<'(S, F), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dp102(R) :- catch((dict_create(S, T, [a-1]), dict_create(F, t, [a-1, b-2]), ':<'(S, F), R = T), error(SsuE, _), R = raised(SsuE)).
t_dp103(R) :- catch((dict_create(S, _, []), dict_create(F, t, [a-1]), ':<'(S, F), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dp104(R) :- catch((dict_create(S, _, [a-1]), dict_create(F, t, []), ':<'(S, F), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dp105(R) :- catch((dict_create(F, t, [a-1, b-2, c-3]), ':<'([b-X], F), R = X), error(SsuE, _), R = raised(SsuE)).
t_dp106(R) :- catch((dict_create(F, t, [a-1]), ':<'(foo, F), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dp107(R) :- catch((dict_create(S, _, [a-1]), ':<'(S, foo), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dp108(R) :- catch((dict_create(F, t, [a-1]), ':<'(_, F), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dp109(R) :- catch((dict_create(S, _, [a-X, b-Y]), dict_create(F, t, [a-1, b-2]), ':<'(S, F), R = X-Y), error(SsuE, _), R = raised(SsuE)).
t_dp110(R) :- catch((':<'([a-X], [a-1, b-2]), R = X), error(SsuE, _), R = raised(SsuE)).
t_dp111(R) :- catch((dict_create(S, _, [b-1, d-2]), dict_create(F, t, [a-0, b-1, c-0, d-2, e-0]), ':<'(S, F), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dp112(R) :- catch((dict_create(S, _, [b-1, z-2]), dict_create(F, t, [a-0, b-1, c-0, d-2, e-0]), ':<'(S, F), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dp113(R) :- catch((dict_create(S, _, [a-X]), dict_create(F, t, [a-f(Y)]), ':<'(S, F), R = X-Y), error(SsuE, _), R = raised(SsuE)).
t_dp114(R) :- catch((dict_create(A, t, [a-X, b-2]), dict_create(B, t, [b-2, c-Y]), '>:<'(A, B), R = X-Y), error(SsuE, _), R = raised(SsuE)).
t_dp115(R) :- catch((dict_create(A, t, [a-1]), dict_create(B, t, [a-2]), '>:<'(A, B), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dp116(R) :- catch((dict_create(A, t, [a-1]), dict_create(B, t, [b-2]), '>:<'(A, B), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dp117(R) :- catch((dict_create(A, t, [a-1]), dict_create(B, u, [a-1]), '>:<'(A, B), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dp118(R) :- catch((dict_create(A, T, [a-1]), dict_create(B, u, [b-2]), '>:<'(A, B), R = T), error(SsuE, _), R = raised(SsuE)).
t_dp119(R) :- catch((dict_create(A, t, [a-X]), dict_create(B, t, [a-1]), '>:<'(A, B), R = X), error(SsuE, _), R = raised(SsuE)).
t_dp120(R) :- catch((dict_create(A, t, []), dict_create(B, t, []), '>:<'(A, B), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dp121(R) :- catch((dict_create(B, t, [a-1]), '>:<'(foo, B), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dp122(R) :- catch((dict_create(A, t, [a-1]), '>:<'(A, foo), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dp123(R) :- catch((dict_create(B, t, [a-1]), '>:<'(_, B), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dp124(R) :- catch(('>:<'([a-X], [a-1, b-2]), R = X), error(SsuE, _), R = raised(SsuE)).
t_dp125(R) :- catch((dict_create(A, t, [a-X, b-Y]), dict_create(B, t, [a-Y, b-3]), '>:<'(A, B), R = X-Y), error(SsuE, _), R = raised(SsuE)).
t_dp126(R) :- catch((dict_create(A, t, [a-1, b-2, c-3]), dict_create(B, t, [a-1, c-4]), '>:<'(A, B), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dp127(R) :- catch((dict_create(A, t, [a-1, c-3]), dict_create(B, t, [a-1, b-2, c-3, d-4]), '>:<'(A, B), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dp128(R) :- catch((dict_create(A, t, [a-1, b-2]), dict_create(B, u, [b-9, a-8]), dict_same_keys(A, B), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dp129(R) :- catch((dict_create(A, t, [a-1, b-2]), dict_create(B, t, [a-1, c-2]), dict_same_keys(A, B), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dp130(R) :- catch((dict_create(A, t, [a-1, b-2]), dict_create(B, t, [a-1]), dict_same_keys(A, B), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dp131(R) :- catch((dict_create(A, t, [a-1, b-2]), dict_same_keys(A, B), dict_pairs(B, T, P), R = T-P), error(SsuE, _), R = raised(SsuE)).
t_dp132(R) :- catch((dict_create(A, t, [a-1, b-2]), dict_same_keys(B, A), dict_pairs(B, T, P), R = T-P), error(SsuE, _), R = raised(SsuE)).
t_dp133(R) :- catch((dict_same_keys(_, _), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dp134(R) :- catch((dict_create(A, t, [a-1]), dict_same_keys(A, foo), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dp135(R) :- catch((dict_create(A, t, [a-1]), dict_same_keys(foo, A), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dp136(R) :- catch((dict_same_keys(foo, bar), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dp137(R) :- catch((dict_create(A, t, []), dict_same_keys(A, B), dict_pairs(B, T, P), R = T-P), error(SsuE, _), R = raised(SsuE)).
t_dp138(R) :- catch((dict_create(A, t, [a-1]), dict_same_keys(A, B), dict_same_keys(A, B), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dp139(R) :- catch((dict_create(A, t, [a-1]), dict_same_keys(A, B), dict_pairs(B, _, [_-V]), V = 7, dpairs(A, R)), error(SsuE, _), R = raised(SsuE)).
t_dp140(R) :- catch((dict_same_keys([a-1], _), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dp141(R) :- catch((dict_create(A, t, [a-1, b-2, c-3, d-4]), dict_same_keys(A, B), dict_pairs(B, _, P), length(P, R)), error(SsuE, _), R = raised(SsuE)).
t_dp142(R) :- catch((dict_create(A, t, [a-1]), dict_same_keys(A, [a-1]), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dp143(R) :- catch((dict_create(A, t, [a-1, b-2]), dict_same_keys(A, B), dict_pairs(B, _, [K1-V1, K2-V2]), R = K1-K2-(V1 == V2)), error(SsuE, _), R = raised(SsuE)).
t_dp144(R) :- catch((dict_create(D, t, [a-1, b-2, c-3]), findall(K-V, (dp_mem(I, [1, 2, 3]), '$get_dict_kv'(I, D, K, V)), L), msort(L, R)), error(SsuE, _), R = raised(SsuE)).
t_dp145(R) :- catch((dict_create(D, t, [a-1, b-2, c-3]), '$get_dict_kv'(0, D, K, V), R = K-V), error(SsuE, _), R = raised(SsuE)).
t_dp146(R) :- catch((dict_create(D, t, [a-1, b-2, c-3]), '$get_dict_kv'(4, D, K, V), R = K-V), error(SsuE, _), R = raised(SsuE)).
t_dp147(R) :- catch((dict_create(D, t, [a-1]), '$get_dict_kv'(-1, D, K, V), R = K-V), error(SsuE, _), R = raised(SsuE)).
t_dp148(R) :- catch((dict_create(D, t, [a-1]), '$get_dict_kv'(_, D, K, V), R = K-V), error(SsuE, _), R = raised(SsuE)).
t_dp149(R) :- catch((dict_create(D, t, [a-1]), '$get_dict_kv'(a, D, K, V), R = K-V), error(SsuE, _), R = raised(SsuE)).
t_dp150(R) :- catch(('$get_dict_kv'(1, foo, K, V), R = K-V), error(SsuE, _), R = raised(SsuE)).
t_dp151(R) :- catch(('$get_dict_kv'(1, _, K, V), R = K-V), error(SsuE, _), R = raised(SsuE)).
t_dp152(R) :- catch((dict_create(D, t, [a-1]), '$get_dict_kv'(1, D, a, V), R = V), error(SsuE, _), R = raised(SsuE)).
t_dp153(R) :- catch((dict_create(D, t, [a-1]), '$get_dict_kv'(1, D, b, V), R = V), error(SsuE, _), R = raised(SsuE)).
t_dp154(R) :- catch((dict_create(D, t, [a-1]), '$get_dict_kv'(1, D, K, 2), R = K), error(SsuE, _), R = raised(SsuE)).
t_dp155(R) :- catch((dict_create(D, t, []), '$get_dict_kv'(1, D, K, V), R = K-V), error(SsuE, _), R = raised(SsuE)).
t_dp156(R) :- catch((dict_create(D, t, [a-1, b-2]), dict_create(E, u, [a-x, b-y]), findall(K-V1-V2, (dp_mem(I, [1, 2]), '$get_dict_kv'(I, D, E, K, V1, V2)), L), msort(L, R)), error(SsuE, _), R = raised(SsuE)).
t_dp157(R) :- catch((dict_create(D, t, [a-1, b-2]), dict_create(E, u, [c-x, d-y]), catch('$get_dict_kv'(1, D, E, K, V1, V2), error(domain_error(T, _), _), R = d(T)), R \== K-V1-V2), error(SsuE, _), R = raised(SsuE)).
t_dp158(R) :- catch((dict_create(D, t, [a-1, b-2]), dict_create(E, u, [a-x]), catch('$get_dict_kv'(1, D, E, K, V1, V2), error(domain_error(T, _), _), R = d(T)), R \== K-V1-V2), error(SsuE, _), R = raised(SsuE)).
t_dp159(R) :- catch((dict_create(D, t, [a-1, b-2]), '$get_dict_kv'(1, D, foo, K, V1, V2), R = K-V1-V2), error(SsuE, _), R = raised(SsuE)).
t_dp160(R) :- catch((dict_create(D, t, [a-1, b-2]), '$get_dict_kv'(1, D, _, K, V1, V2), R = K-V1-V2), error(SsuE, _), R = raised(SsuE)).
t_dp161(R) :- catch((dict_create(D, t, [a-1, b-2]), dict_create(E, u, [a-x, b-y]), dict_create(F, v, [a-p, b-q]), findall(K-V1-V2-V3, (dp_mem(I, [1, 2]), '$get_dict_kv'(I, D, E, F, K, V1, V2, V3)), L), msort(L, R)), error(SsuE, _), R = raised(SsuE)).
t_dp162(R) :- catch((dict_create(D, t, [a-1, b-2]), dict_create(E, u, [a-x, b-y]), dict_create(F, v, [c-p, d-q]), catch('$get_dict_kv'(1, D, E, F, K, V1, V2, V3), error(domain_error(T, _), _), R = d(T)), R \== K-V1-V2-V3), error(SsuE, _), R = raised(SsuE)).
t_dp163(R) :- catch((dict_create(D, t, [a-1, b-2]), '$get_dict_kv'(3, D, D, K, V1, V2), R = K-V1-V2), error(SsuE, _), R = raised(SsuE)).
t_dp164(R) :- catch((dict_create(D, t, [a-1, b-2]), '$get_dict_kv'(1, D, D, K, V1, V1), R = K-V1), error(SsuE, _), R = raised(SsuE)).
