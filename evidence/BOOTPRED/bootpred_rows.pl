p(1).
p(2).
p(3).
dpairs(D, Ps) :- findall(K-V, get_dict(K, D, V), Ps0), msort(Ps0, Ps).
t_bp01(R) :- catch((thread_self(R)), error(SsuE, _), R = raised(SsuE)).
t_bp02(R) :- catch((thread_self(main), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp03(R) :- catch((thread_self(other), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp04(R) :- catch((findall(X, thread_self(X), R)), error(SsuE, _), R = raised(SsuE)).
t_bp05(R) :- catch((thread_self(1), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp06(R) :- catch((thread_self(T), atom(T), R = T), error(SsuE, _), R = raised(SsuE)).
t_bp07(R) :- catch((thread_self(T), T == main, R = ok), error(SsuE, _), R = raised(SsuE)).
t_bp08(R) :- catch((with_mutex(m, thread_self(R))), error(SsuE, _), R = raised(SsuE)).
t_bp09(R) :- catch((with_mutex(m, R = 1)), error(SsuE, _), R = raised(SsuE)).
t_bp10(R) :- catch((findall(X, with_mutex(m, p(X)), R)), error(SsuE, _), R = raised(SsuE)).
t_bp11(R) :- catch((with_mutex(m, fail), R = x), error(SsuE, _), R = raised(SsuE)).
t_bp12(R) :- catch((catch(with_mutex(m, throw(oops)), E, R = caught(E))), error(SsuE, _), R = raised(SsuE)).
t_bp13(R) :- catch((with_mutex(m, (p(X), X > 1)), R = X), error(SsuE, _), R = raised(SsuE)).
t_bp14(R) :- catch((with_mutex(m, with_mutex(m, R = n))), error(SsuE, _), R = raised(SsuE)).
t_bp15(R) :- catch((with_mutex(m, p(X)), X > 1, R = X), error(SsuE, _), R = raised(SsuE)).
t_bp16(R) :- catch((with_mutex(m, (X = f(Y), Y = 1)), R = X), error(SsuE, _), R = raised(SsuE)).
t_bp17(R) :- catch((with_mutex(m, context_module(R))), error(SsuE, _), R = raised(SsuE)).
t_bp18(R) :- catch((with_mutex(m, nosuchpred_bp(R))), error(SsuE, _), R = raised(SsuE)).
t_bp19(R) :- catch((with_mutex(m, true), with_mutex(n, R = two)), error(SsuE, _), R = raised(SsuE)).
t_bp20(R) :- catch(('$garbage_collect'(0), R = ok), error(SsuE, _), R = raised(SsuE)).
t_bp21(R) :- catch(('$garbage_collect'(foo), R = ok), error(SsuE, _), R = raised(SsuE)).
t_bp22(R) :- catch(('$garbage_collect'(_), R = ok), error(SsuE, _), R = raised(SsuE)).
t_bp23(R) :- catch((findall(x, '$garbage_collect'(0), R)), error(SsuE, _), R = raised(SsuE)).
t_bp24(R) :- catch((X = f(Y, Z), Y = 1, '$garbage_collect'(0), R = X-Z), error(SsuE, _), R = raised(SsuE)).
t_bp25(R) :- catch(('$garbage_collect'(0), '$garbage_collect'(1), R = twice), error(SsuE, _), R = raised(SsuE)).
t_bp26(R) :- catch((length(L, 3), '$garbage_collect'(0), R = L), error(SsuE, _), R = raised(SsuE)).
t_bp27(R) :- catch((dict_create(D, t, [a-1, b-2]), dpairs(D, R)), error(SsuE, _), R = raised(SsuE)).
t_bp28(R) :- catch((dict_create(D, t, [a=1, b=2, c=3]), dpairs(D, R)), error(SsuE, _), R = raised(SsuE)).
t_bp29(R) :- catch((dict_create(D, t, [a:1, b:2]), dpairs(D, R)), error(SsuE, _), R = raised(SsuE)).
t_bp30(R) :- catch((dict_create(D, t, [a(1), b(2)]), dpairs(D, R)), error(SsuE, _), R = raised(SsuE)).
t_bp31(R) :- catch((dict_create(D, t, [a-1, b=2, c:3, d(4)]), dpairs(D, R)), error(SsuE, _), R = raised(SsuE)).
t_bp32(R) :- catch((dict_create(D, tag, []), is_dict(D, T), R = T), error(SsuE, _), R = raised(SsuE)).
t_bp33(R) :- catch((dict_create(D, _, [a-1]), is_dict(D, T), var(T), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp34(R) :- catch((dict_create(D, t, [2-b, 1-a, 3-c]), dpairs(D, R)), error(SsuE, _), R = raised(SsuE)).
t_bp35(R) :- catch((dict_create(D, t, [a-1, a-2]), R = D), error(SsuE, _), R = raised(SsuE)).
t_bp36(R) :- catch((dict_create(D, t, [a-1, b-2, a-3]), R = D), error(SsuE, _), R = raised(SsuE)).
t_bp37(R) :- catch((dict_create(D, t, foo), R = D), error(SsuE, _), R = raised(SsuE)).
t_bp38(R) :- catch((dict_create(D, t, [a]), R = D), error(SsuE, _), R = raised(SsuE)).
t_bp39(R) :- catch((dict_create(D, t, [f(1, 2)]), R = D), error(SsuE, _), R = raised(SsuE)).
t_bp40(R) :- catch((dict_create(D, t, [X-1]), R = D-X), error(SsuE, _), R = raised(SsuE)).
t_bp41(R) :- catch((dict_create(D, t, [1.5-a]), R = D), error(SsuE, _), R = raised(SsuE)).
t_bp42(R) :- catch((dict_create(D, t, [f(x)-1]), R = D), error(SsuE, _), R = raised(SsuE)).
t_bp43(R) :- catch((dict_create(D, t, [a-1|_]), R = D), error(SsuE, _), R = raised(SsuE)).
t_bp44(R) :- catch((dict_create(D, t, [a-1|foo]), R = D), error(SsuE, _), R = raised(SsuE)).
t_bp45(R) :- catch((dict_create(foo, t, [a-1]), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp46(R) :- catch((dict_create(D1, t, [a-1, b-2]), dict_create(D2, t, [b=2, a=1]), D1 == D2, R = same), error(SsuE, _), R = raised(SsuE)).
t_bp47(R) :- catch((dict_create(D1, t, [a-1]), dict_create(D2, u, [a-1]), D1 = D2, R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp48(R) :- catch((dict_create(D1, t, [a-X]), dict_create(D2, t, [a-1]), D1 = D2, R = X), error(SsuE, _), R = raised(SsuE)).
t_bp49(R) :- catch((dict_create(D, T, [a-1]), T = foo, is_dict(D, foo), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp50(R) :- catch((dict_create(D, t, [a-1, b-2]), dict_create(D, T, L), R = T-L), error(SsuE, _), R = raised(SsuE)).
t_bp51(R) :- catch((findall(x, dict_create(_, t, [a-1]), R)), error(SsuE, _), R = raised(SsuE)).
t_bp52(R) :- catch((findall(x, is_dict(foo), R)), error(SsuE, _), R = raised(SsuE)).
t_bp53(R) :- catch((findall(x, is_dict(_), R)), error(SsuE, _), R = raised(SsuE)).
t_bp54(R) :- catch((dict_create(D, t, []), is_dict(D), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp55(R) :- catch((findall(x, is_dict(f(a), _), R)), error(SsuE, _), R = raised(SsuE)).
t_bp56(R) :- catch((findall(x, (member(X, [1, 2.5, abc, [], [a], f(a), g(a, b, c)]), is_dict(X)), R)), error(SsuE, _), R = raised(SsuE)).
t_bp57(R) :- catch((dict_create(D, t, [a-1]), is_dict(D, t), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp58(R) :- catch((dict_create(D, t, [a-1]), is_dict(D, u), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp59(R) :- catch((findall(x, is_dict(_, _), R)), error(SsuE, _), R = raised(SsuE)).
t_bp60(R) :- catch((dict_create(D, f(x), [a-1]), is_dict(D, T), R = T), error(SsuE, _), R = raised(SsuE)).
t_bp61(R) :- catch((dict_create(D, t, [a-1, b-2]), get_dict(a, D, V), R = V), error(SsuE, _), R = raised(SsuE)).
t_bp62(R) :- catch((dict_create(D, t, [a-1, b-2]), get_dict(b, D, V), R = V), error(SsuE, _), R = raised(SsuE)).
t_bp63(R) :- catch((dict_create(D, t, [a-1, b-2]), get_dict(c, D, V), R = V), error(SsuE, _), R = raised(SsuE)).
t_bp64(R) :- catch((dict_create(D, t, [a-1, b-2, c-3]), findall(K-V, get_dict(K, D, V), L), length(L, R)), error(SsuE, _), R = raised(SsuE)).
t_bp65(R) :- catch((dict_create(D, t, [a-1, b-2, c-3]), findall(K, get_dict(K, D, 2), R)), error(SsuE, _), R = raised(SsuE)).
t_bp66(R) :- catch((dict_create(D, t, [a-1, b-2]), get_dict(a, D, 2), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp67(R) :- catch((dict_create(D, t, [a-1, b-2]), get_dict(a, D, 1), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp68(R) :- catch((get_dict(a, foo, V), R = V), error(SsuE, _), R = raised(SsuE)).
t_bp69(R) :- catch((get_dict(a, _, V), R = V), error(SsuE, _), R = raised(SsuE)).
t_bp70(R) :- catch((dict_create(D, t, [a-1]), get_dict(1.5, D, V), R = V), error(SsuE, _), R = raised(SsuE)).
t_bp71(R) :- catch((dict_create(D, t, [a-1]), get_dict(f(x), D, V), R = V), error(SsuE, _), R = raised(SsuE)).
t_bp72(R) :- catch((dict_create(D, t, [1-one, 2-two]), get_dict(2, D, V), R = V), error(SsuE, _), R = raised(SsuE)).
t_bp73(R) :- catch((dict_create(D, t, [a-1, b-2]), findall(V, get_dict(a, D, V), R)), error(SsuE, _), R = raised(SsuE)).
t_bp74(R) :- catch((dict_create(D, t, []), findall(K-V, get_dict(K, D, V), R)), error(SsuE, _), R = raised(SsuE)).
t_bp75(R) :- catch((dict_create(D, t, [a-1, b-2, c-3]), findall(K, (get_dict(K, D, V), V > 1), L), msort(L, R)), error(SsuE, _), R = raised(SsuE)).
t_bp76(R) :- catch((dict_create(D, t, [a-X, b-Y]), get_dict(a, D, 5), R = X-Y), error(SsuE, _), R = raised(SsuE)).
t_bp77(R) :- catch((dict_create(D, t, [a-f(Z)]), get_dict(a, D, f(7)), R = Z), error(SsuE, _), R = raised(SsuE)).
t_bp78(R) :- catch((dict_create(D, t, [a-1, b-2, c-3, d-4, e-5]), get_dict(e, D, V), R = V), error(SsuE, _), R = raised(SsuE)).
t_bp79(R) :- catch((dict_create(D, t, [a-1, b-2]), get_dict(K, D, V), K == b, R = V), error(SsuE, _), R = raised(SsuE)).
t_bp80(R) :- catch((dict_create(D, t, [a-1]), put_dict([b-2], D, N), dpairs(N, R)), error(SsuE, _), R = raised(SsuE)).
t_bp81(R) :- catch((dict_create(D, t, [a-1, b-2]), put_dict([a-9], D, N), dpairs(N, R)), error(SsuE, _), R = raised(SsuE)).
t_bp82(R) :- catch((dict_create(D, t, [a-1]), dict_create(E, u, [b-2, c-3]), put_dict(E, D, N), dpairs(N, R)), error(SsuE, _), R = raised(SsuE)).
t_bp83(R) :- catch((dict_create(D, t, [a-1]), dict_create(E, u, [b-2]), put_dict(E, D, N), is_dict(N, T), R = T), error(SsuE, _), R = raised(SsuE)).
t_bp84(R) :- catch((dict_create(D, t, [a-1]), put_dict([], D, N), dpairs(N, R)), error(SsuE, _), R = raised(SsuE)).
t_bp85(R) :- catch((dict_create(D, t, [a-1]), put_dict([b=2, c:3, d(4)], D, N), dpairs(N, R)), error(SsuE, _), R = raised(SsuE)).
t_bp86(R) :- catch((dict_create(D, t, [a-1]), put_dict([a-9], D, _), dpairs(D, R)), error(SsuE, _), R = raised(SsuE)).
t_bp87(R) :- catch((put_dict([a-1], foo, N), R = N), error(SsuE, _), R = raised(SsuE)).
t_bp88(R) :- catch((dict_create(D, t, [a-1]), put_dict(foo, D, N), R = N), error(SsuE, _), R = raised(SsuE)).
t_bp89(R) :- catch((dict_create(D, t, [a-1]), put_dict([b-1, b-2], D, N), R = N), error(SsuE, _), R = raised(SsuE)).
t_bp90(R) :- catch((dict_create(D, t, [a-1]), put_dict([b-1|_], D, N), R = N), error(SsuE, _), R = raised(SsuE)).
t_bp91(R) :- catch((put_dict([x-1], _, N), R = N), error(SsuE, _), R = raised(SsuE)).
t_bp92(R) :- catch((dict_create(D, t, [a-1]), put_dict([b-2], D, N), dict_create(E, t, [a-1, b-2]), N == E, R = same), error(SsuE, _), R = raised(SsuE)).
t_bp93(R) :- catch((dict_create(D, t, []), put_dict([x-1, y-2], D, N), dpairs(N, R)), error(SsuE, _), R = raised(SsuE)).
t_bp94(R) :- catch((dict_create(D0, t, [a-0]), put_dict([a-1], D0, D1), put_dict([b-2], D1, D2), put_dict([a-3, c-4], D2, D3), dpairs(D3, R)), error(SsuE, _), R = raised(SsuE)).
t_bp95(R) :- catch((dict_create(D, t, [1-a, 3-c]), put_dict([2-b, 4-d], D, N), dpairs(N, R)), error(SsuE, _), R = raised(SsuE)).
t_bp96(R) :- catch((dict_create(D, t, [k1-1, k3-3, k5-5, k7-7, k9-9, k11-11]), put_dict([k2-2, k4-4, k6-6, k8-8, k10-10, k3-33], D, N), dpairs(N, R)), error(SsuE, _), R = raised(SsuE)).
t_bp97(R) :- catch((dict_create(D, t, [a-X]), put_dict([b-1], D, N), get_dict(a, N, V), V == X, R = shared), error(SsuE, _), R = raised(SsuE)).
t_bp98(R) :- catch((dict_create(D, t, [a-1, b-2]), put_dict([b-X], D, N), get_dict(b, N, V), V == X, R = replaced), error(SsuE, _), R = raised(SsuE)).
t_bp99(R) :- catch((dict_create(D, t, [a-1]), dict_create(E, t, [a-2]), put_dict(E, D, N), dpairs(N, R)), error(SsuE, _), R = raised(SsuE)).
t_bp100(R) :- catch((dict_create(D, t, [a-1]), put_dict([b-2], D, N), put_dict([b-2], N, M), N == M, R = unchanged), error(SsuE, _), R = raised(SsuE)).
t_bp101(R) :- catch((dict_create(S, t, [a-X]), dict_create(F, t, [a-1, b-2]), select_dict(S, F, Rest), dpairs(Rest, P), R = X-P), error(SsuE, _), R = raised(SsuE)).
t_bp102(R) :- catch((dict_create(S, t, [a-1, b-2]), dict_create(F, t, [a-1, b-2]), select_dict(S, F, Rest), dpairs(Rest, P), R = P), error(SsuE, _), R = raised(SsuE)).
t_bp103(R) :- catch((dict_create(S, t, [c-1]), dict_create(F, t, [a-1, b-2]), select_dict(S, F, _), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp104(R) :- catch((dict_create(S, t, [a-9]), dict_create(F, t, [a-1, b-2]), select_dict(S, F, _), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp105(R) :- catch((dict_create(S, u, [a-1]), dict_create(F, t, [a-1]), select_dict(S, F, _), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp106(R) :- catch((dict_create(S, T, [a-1]), dict_create(F, foo, [a-1, b-2]), select_dict(S, F, _), R = T), error(SsuE, _), R = raised(SsuE)).
t_bp107(R) :- catch((dict_create(S, t, [a-1]), dict_create(F, T, [a-1, b-2]), select_dict(S, F, Rest), is_dict(Rest, T2), R = T2), error(SsuE, _), R = raised(SsuE)).
t_bp108(R) :- catch((select_dict(foo, F, R), R = F), error(SsuE, _), R = raised(SsuE)).
t_bp109(R) :- catch((dict_create(S, t, [a-1]), select_dict(S, foo, R)), error(SsuE, _), R = raised(SsuE)).
t_bp110(R) :- catch((dict_create(S, t, []), dict_create(F, t, [a-1, b-2]), select_dict(S, F, Rest), dpairs(Rest, R)), error(SsuE, _), R = raised(SsuE)).
t_bp111(R) :- catch((dict_create(S, t, [b-X, d-Y]), dict_create(F, t, [a-1, b-2, c-3, d-4, e-5]), select_dict(S, F, Rest), dpairs(Rest, P), R = X-Y-P), error(SsuE, _), R = raised(SsuE)).
t_bp112(R) :- catch((dict_create(S, t, [a-1]), dict_create(F, t, [a-1, b-2]), dict_create(E, '#', [b-2]), select_dict(S, F, E), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp113(R) :- catch((dict_create(S, t, [a-1]), dict_create(F, t, [a-1, b-2]), dict_create(E, '#', [b-3]), select_dict(S, F, E), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp114(R) :- catch((select_dict(_, _, R), R = x), error(SsuE, _), R = raised(SsuE)).
t_bp115(R) :- catch((dict_create(S, t, [a-1]), dict_create(F, t, [a-1, b-2]), findall(P, (select_dict(S, F, Rest), dpairs(Rest, P)), R)), error(SsuE, _), R = raised(SsuE)).
t_bp116(R) :- catch((dict_create(S, t, [a-1]), dict_create(F, t, [a-1, b-2]), dict_create(E, t, [b-2]), select_dict(S, F, E), R = yes), error(SsuE, _), R = raised(SsuE)).
