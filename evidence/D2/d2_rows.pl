:- dynamic d/1.
strv("abc").
rset :- recorded(_, _, R), erase(R), fail.
rset.
ex(G, R) :- catch(( G, R = true ), error(E, _), R = err(E)).
exc(G, R) :- catch(( G, R = true ), error(E, C), R = err(E, C)).
btype(S, B) :- ( atom(S) -> B = atom ; atomic(S) -> B = atomic ; B = other ).
kd(K, D) :- ( atom(K) -> D = K ; integer(K) -> D = K ; functor(K, N, A), D = N/A ).
refshape(Ref, S) :- term_to_atom(Ref, A), ( atom_concat('<record>(0x', _, A) -> S = recordform ; S = A ).
t_r01(R) :- rset, catch((recordz(k, 1), recordz(k, 2), findall(X, recorded(k, X), R)), error(RcE, _), R = raised(RcE)).
t_r02(R) :- rset, catch((recorda(k, 1), recorda(k, 2), findall(X, recorded(k, X), R)), error(RcE, _), R = raised(RcE)).
t_r03(R) :- rset, catch((recordz(k, b), recorda(k, a), recordz(k, c), findall(X, recorded(k, X), R)), error(RcE, _), R = raised(RcE)).
t_r04(R) :- rset, catch((recorda(k, x, R)), error(RcE, _), R = raised(RcE)).
t_r05(R) :- rset, catch((recordz(k, x, Ref), blob(Ref, T), R = T), error(RcE, _), R = raised(RcE)).
t_r06(R) :- rset, catch((recordz(k, x, Ref), btype(Ref, B), R = B), error(RcE, _), R = raised(RcE)).
t_r07(R) :- rset, catch((recorda(k, x, Ref), refshape(Ref, R)), error(RcE, _), R = raised(RcE)).
t_r08(R) :- rset, catch((recordz(k, x, R1), recordz(k, x, R2), ( R1 == R2 -> R = same ; R = diff )), error(RcE, _), R = raised(RcE)).
t_r09(R) :- rset, catch((recordz(k, x, R1), copy_term(R1, R3), ( R1 == R3 -> R = same ; R = diff )), error(RcE, _), R = raised(RcE)).
t_r10(R) :- rset, catch((recordz(k, x, R1), recordz(k, y, R2), ( R1 = R2 -> R = unified ; R = apart )), error(RcE, _), R = raised(RcE)).
t_r11(R) :- rset, catch((recordz(f(a, b), x), recorded(f(_, _), R)), error(RcE, _), R = raised(RcE)).
t_r12(R) :- rset, catch((recordz(f(a, b), x), recorded(f(c, d), R)), error(RcE, _), R = raised(RcE)).
t_r13(R) :- rset, catch((recordz(f(a, b), x), ( recorded(f(_), _) -> R = yes ; R = no )), error(RcE, _), R = raised(RcE)).
t_r14(R) :- rset, catch((recordz(42, x), recorded(42, R)), error(RcE, _), R = raised(RcE)).
t_r15(R) :- rset, catch((recordz(-7, x), recorded(-7, R)), error(RcE, _), R = raised(RcE)).
t_r16(R) :- rset, catch((X is 2^55, recordz(X, x), recorded(X, R)), error(RcE, _), R = raised(RcE)).
t_r17(R) :- rset, catch((X is 2^56, ex(recordz(X, x), R)), error(RcE, _), R = raised(RcE)).
t_r18(R) :- rset, catch((X is -(2^55), ex(recordz(X, x), R)), error(RcE, _), R = raised(RcE)).
t_r19(R) :- rset, catch((X is -(2^56), ex(recordz(X, x), R)), error(RcE, _), R = raised(RcE)).
t_r20(R) :- rset, catch((ex(recordz(1.5, x), R)), error(RcE, _), R = raised(RcE)).
t_r21(R) :- rset, catch((strv(S), ex(recordz(S, x), R)), error(RcE, _), R = raised(RcE)).
t_r22(R) :- rset, catch((ex(recordz(_, x), R)), error(RcE, _), R = raised(RcE)).
t_r23(R) :- rset, catch((exc(recordz(1.5, x), R)), error(RcE, _), R = raised(RcE)).
t_r24(R) :- rset, catch((exc(recorda(_, x, _), R)), error(RcE, _), R = raised(RcE)).
t_r25(R) :- rset, catch((exc(recorded(1.5, _), R)), error(RcE, _), R = raised(RcE)).
t_r26(R) :- rset, catch((exc(recorded(1.5, _, _), R)), error(RcE, _), R = raised(RcE)).
t_r27(R) :- rset, catch((recordz([], x), recorded([], R)), error(RcE, _), R = raised(RcE)).
t_r28(R) :- rset, catch((recordz([a|b], x), recorded([_|_], R)), error(RcE, _), R = raised(RcE)).
t_r29(R) :- rset, catch((recordz(m:k, x), recorded(n:j, R)), error(RcE, _), R = raised(RcE)).
t_r30(R) :- rset, catch((recordz(k, x), recordz(f, y), recordz(f(a), z), recordz(f(a, b), w), findall(X, recorded(f, X), R)), error(RcE, _), R = raised(RcE)).
t_r31(R) :- rset, catch((recordz(5, x), recordz('5', y), findall(X, recorded(5, X), R)), error(RcE, _), R = raised(RcE)).
t_r32(R) :- rset, catch((exc(recorda(k, x, foo), R)), error(RcE, _), R = raised(RcE)).
t_r33(R) :- rset, catch((recorda(k, x, R1), exc(recorda(k, y, R1), R)), error(RcE, _), R = raised(RcE)).
t_r34(R) :- rset, catch((recorda(k, x, R1), ex(recordz(k, y, R1), R)), error(RcE, _), R = raised(RcE)).
t_r35(R) :- rset, catch((recordz(k, f(X, Y, X)), recorded(k, R)), error(RcE, _), R = raised(RcE)).
t_r36(R) :- rset, catch((recordz(k, f(X, g(Y), Y)), recorded(k, T), T = f(A, g(B), C), ( A \== B, B == C -> R = ok ; R = bad )), error(RcE, _), R = raised(RcE)).
t_r37(R) :- rset, catch((strv(S), Big is 2^100, recordz(k, S), recordz(k, 1.5), recordz(k, Big), findall(X, recorded(k, X), R)), error(RcE, _), R = raised(RcE)).
t_r38(R) :- rset, catch((recordz(k, _), recorded(k, R)), error(RcE, _), R = raised(RcE)).
t_r39(R) :- rset, catch((recordz(k, f(A)), recorded(k, T), T = f(B), ( A == B -> R = shared ; R = fresh )), error(RcE, _), R = raised(RcE)).
t_r40(R) :- rset, catch((recordz(k, x, Ref), recordz(j, ref(Ref)), recorded(j, ref(R2)), ( R2 == Ref -> R = same ; R = diff )), error(RcE, _), R = raised(RcE)).
t_r41(R) :- rset, catch((assertz(d(1), C), recordz(k, c(C)), recorded(k, c(C2)), ( C2 == C -> R = same ; R = diff )), error(RcE, _), R = raised(RcE)).
t_r42(R) :- rset, catch((recordz(k, a), recordz(k, b), recorded(k, a), R = ok), error(RcE, _), R = raised(RcE)).
t_r43(R) :- rset, catch((recordz(k, f(1)), recordz(k, f(2)), recorded(k, f(R))), error(RcE, _), R = raised(RcE)).
t_r44(R) :- rset, catch((recordz(k, a), ( recorded(k, b) -> R = yes ; R = no )), error(RcE, _), R = raised(RcE)).
t_r45(R) :- rset, catch((( recorded(nokey, _) -> R = yes ; R = no )), error(RcE, _), R = raised(RcE)).
t_r46(R) :- rset, catch((recordz(k, a, _), recordz(k, b, R2), recorded(k, T, R2), R = T), error(RcE, _), R = raised(RcE)).
t_r47(R) :- rset, catch((recordz(k, a, _), recordz(k, b, R2), recorded(K, T, R2), R = K-T), error(RcE, _), R = raised(RcE)).
t_r48(R) :- rset, catch((recordz(k, a, R1), recordz(j, b, _), ( recorded(j, _, R1) -> R = yes ; R = no )), error(RcE, _), R = raised(RcE)).
t_r49(R) :- rset, catch((recordz(k, a, R1), erase(R1), ( recorded(k, _, R1) -> R = yes ; R = no )), error(RcE, _), R = raised(RcE)).
t_r50(R) :- rset, catch((exc(recorded(k, _, foo), R)), error(RcE, _), R = raised(RcE)).
t_r51(R) :- rset, catch((assertz(d(1), C), exc(recorded(k, _, C), R)), error(RcE, _), R = raised(RcE)).
t_r52(R) :- rset, catch((recordz(k, a, R1), recordz(k, b, _), findall(T, recorded(k, T, R1), R)), error(RcE, _), R = raised(RcE)).
t_r53(R) :- rset, catch((recordz(ka, 1), recordz(kb, 2), recordz(ka, 3), recordz(f(x), 4), recordz(9, 5), findall(D-T, ( recorded(K, T), kd(K, D) ), L), msort(L, R)), error(RcE, _), R = raised(RcE)).
t_r54(R) :- rset, catch((recordz(ka, 1), recordz(kb, 2), recordz(ka, 3), recordz(f(x), 4), recordz(9, 5), findall(D-T, ( recorded(K, T, _), kd(K, D) ), L), msort(L, R)), error(RcE, _), R = raised(RcE)).
t_r55(R) :- rset, catch((recordz(ka, 1), recordz(kb, 2), recordz(f(x), 4), recordz(9, 5), findall(D, ( current_key(K), kd(K, D) ), L), msort(L, R)), error(RcE, _), R = raised(RcE)).
t_r56(R) :- rset, catch((recordz(ka, 1), ( current_key(ka) -> R = yes ; R = no )), error(RcE, _), R = raised(RcE)).
t_r57(R) :- rset, catch((( current_key(nokey) -> R = yes ; R = no )), error(RcE, _), R = raised(RcE)).
t_r58(R) :- rset, catch((recordz(ka, 1, Ref), erase(Ref), ( current_key(ka) -> R = yes ; R = no )), error(RcE, _), R = raised(RcE)).
t_r59(R) :- rset, catch((recordz(f(a), 1), ( current_key(f(_)) -> R = yes ; R = no )), error(RcE, _), R = raised(RcE)).
t_r60(R) :- rset, catch((recordz(f(a), 1), current_key(K), functor(K, N, A), R = N/A), error(RcE, _), R = raised(RcE)).
t_r61(R) :- rset, catch((exc(current_key(1.5), R)), error(RcE, _), R = raised(RcE)).
t_r62(R) :- rset, catch((recordz(a, 1), recordz(b, 2), ( current_key(_) -> true ), R = ok), error(RcE, _), R = raised(RcE)).
t_r63(R) :- rset, catch((recordz(a, 1), recordz(b, 2), recordz(c, 3), findall(K, current_key(K), L), msort(L, R)), error(RcE, _), R = raised(RcE)).
t_r64(R) :- rset, catch((recordz(k, 1), recordz(j, 2), recorded(K, 2), R = K), error(RcE, _), R = raised(RcE)).
t_r65(R) :- rset, catch((recordz(k, a, Ref), erase(Ref), ( recorded(k, a) -> R = yes ; R = no )), error(RcE, _), R = raised(RcE)).
t_r66(R) :- rset, catch((recordz(k, a, Ref), erase(Ref), ( erase(Ref) -> R = again ; R = failed )), error(RcE, _), R = raised(RcE)).
t_r67(R) :- rset, catch((recordz(k, a, Ref), erase(Ref), R = ok), error(RcE, _), R = raised(RcE)).
t_r68(R) :- rset, catch((recordz(k, a, Ref), recordz(k, b, _), erase(Ref), findall(X, recorded(k, X), R)), error(RcE, _), R = raised(RcE)).
t_r69(R) :- rset, catch((ex(erase(foo), R)), error(RcE, _), R = raised(RcE)).
t_r70(R) :- rset, catch((ex(erase(_), R)), error(RcE, _), R = raised(RcE)).
t_r71(R) :- rset, catch((exc(erase(foo), R)), error(RcE, _), R = raised(RcE)).
t_r72(R) :- rset, catch((recordz(k, a), recorded(k, a, Ref), erase(Ref), ( recorded(k, _) -> R = yes ; R = no )), error(RcE, _), R = raised(RcE)).
t_r73(R) :- rset, catch((recordz(k, f(X, Y, X), Ref), instance(Ref, R)), error(RcE, _), R = raised(RcE)).
t_r74(R) :- rset, catch((recordz(k, g(1), Ref), ( instance(Ref, g(2)) -> R = yes ; R = no )), error(RcE, _), R = raised(RcE)).
t_r75(R) :- rset, catch((recordz(k, g(1), Ref), instance(Ref, g(R))), error(RcE, _), R = raised(RcE)).
t_r76(R) :- rset, catch((recordz(k, a, Ref), erase(Ref), ( instance(Ref, _) -> R = yes ; R = no )), error(RcE, _), R = raised(RcE)).
t_r77(R) :- rset, catch((ex(instance(foo, _), R)), error(RcE, _), R = raised(RcE)).
t_r78(R) :- rset, catch((ex(instance(_, _), R)), error(RcE, _), R = raised(RcE)).
t_r79(R) :- rset, catch((exc(instance(foo, _), R)), error(RcE, _), R = raised(RcE)).
t_r80(R) :- rset, catch((recordz(k, f(Z), Ref), instance(Ref, T), T = f(Q), ( Z == Q -> R = shared ; R = fresh )), error(RcE, _), R = raised(RcE)).
t_r81(R) :- rset, catch((assertz(d(1), C), instance(C, R)), error(RcE, _), R = raised(RcE)).
t_r82(R) :- rset, catch((assertz(d(1), C), erase(C), ( d(_) -> R = yes ; R = no )), error(RcE, _), R = raised(RcE)).
t_r83(R) :- rset, catch((assertz(d(1), C), recordz(k, x, Rf), erase(Rf), ( instance(C, _) -> R = clause_alive ; R = clause_gone )), error(RcE, _), R = raised(RcE)).
t_r84(R) :- rset, catch((recordz(k, x, Rf), assertz(d(1), C), erase(C), ( instance(Rf, I) -> R = I ; R = gone )), error(RcE, _), R = raised(RcE)).
t_r85(R) :- rset, catch((recordz(k, x, Rf), assertz(d(1), C), exc(recorded(k, _, C), R0), R = R0-Rf), error(RcE, _), R = raised(RcE)).
t_r86(R) :- rset, catch((recordz(k, 1), recordz(k, 2), recordz(k, 3), findall(X, ( recorded(k, X), ( X == 1 -> recordz(k, 4) ; true ) ), R)), error(RcE, _), R = raised(RcE)).
t_r87(R) :- rset, catch((recordz(k, 1), recordz(k, 2), recordz(k, 3), findall(X, ( recorded(k, X, Ref), erase(Ref) ), R)), error(RcE, _), R = raised(RcE)).
t_r88(R) :- rset, catch((recordz(k, 1), recordz(k, 2), recordz(k, 3), findall(X, ( recorded(k, X), ( X == 1 -> recorded(k, 2, R2), erase(R2) ; true ) ), R)), error(RcE, _), R = raised(RcE)).
t_r89(R) :- rset, catch((recordz(k, 1), recordz(k, 2), ( recorded(k, _, Ref), erase(Ref), fail ; true ), recordz(k, 3), findall(X, recorded(k, X), R)), error(RcE, _), R = raised(RcE)).
t_r90(R) :- rset, catch((recordz(k, 1), recordz(k, 2), ( recorded(k, _, Ref), erase(Ref), fail ; true ), ( current_key(k) -> R = alive ; R = gone )), error(RcE, _), R = raised(RcE)).
t_r91(R) :- rset, catch((recordz(k, 1), recordz(k, 2), recordz(k, 3), recorded(k, R, Ref), erase(Ref)), error(RcE, _), R = raised(RcE)).
t_r92(R) :- rset, catch((recordz(k, 1), recordz(k, 2), ( recorded(k, _, Ref) -> true ), erase(Ref), findall(X, recorded(k, X), R)), error(RcE, _), R = raised(RcE)).
t_r93(R) :- rset, catch((recordz(k, 1), recorded(k, 1, Ref), recorda(k, 0), erase(Ref), findall(X, recorded(k, X), R)), error(RcE, _), R = raised(RcE)).
t_r94(R) :- rset, catch((recordz(k, 1), recordz(k, 2), recorded(k, X, Ref), erase(Ref), recorded(k, Y), R = X-Y), error(RcE, _), R = raised(RcE)).
t_r95(R) :- rset, catch((recordz(k, 1), recordz(k, 2), recordz(k, 3), recorded(k, X), X >= 2, !, R = X), error(RcE, _), R = raised(RcE)).
t_r96(R) :- rset, catch((( between(1, 300, N), recordz(k, N), fail ; true ), findall(X, recorded(k, X), L), length(L, R)), error(RcE, _), R = raised(RcE)).
t_r97(R) :- rset, catch((( between(1, 300, N), recorda(k, N), fail ; true ), ( recorded(k, R) -> true )), error(RcE, _), R = raised(RcE)).
t_r98(R) :- rset, catch((recordz(k, 1), recordz(k, 2), ( recorded(k, X, Ref), erase(Ref), recorded(k, Y), R = X-Y ; R = none )), error(RcE, _), R = raised(RcE)).
t_r99(R) :- rset, catch((recordz(k, f(1)), recordz(k, g(2)), recordz(k, g(3)), recorded(k, f(_)), recorded(k, g(2), Rg), erase(Rg), findall(X, recorded(k, g(X)), R)), error(RcE, _), R = raised(RcE)).
t_r100(R) :- rset, catch((recordz(ka, 1, Ref), recordz(kb, 2), erase(Ref), findall(K, current_key(K), R)), error(RcE, _), R = raised(RcE)).
t_r101(R) :- rset, catch((recordz(ka, 1, Ref), recordz(kb, 2), erase(Ref), findall(K-T, recorded(K, T), R)), error(RcE, _), R = raised(RcE)).
