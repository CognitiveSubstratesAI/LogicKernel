sa_same(A, B, R) :- ( same_term(A, B) -> R = same ; R = distinct ).
sa_mem(X, [X|_]).
sa_mem(X, [_|T]) :- sa_mem(X, T).
% sa_arg: the two argument numbers the rows use, through =../2 (arg/3 itself is a later step of the port)
% sa_zero: a zero-argument compound built outside catch/3's goal
sa_zero(T) :- T = foo().
sa_arg(1, T, A) :- T =.. [_, A|_].
sa_arg(2, T, A) :- T =.. [_, _, A|_].
sa_inc(T) :- sa_arg(1, T, V0), V is V0+1, nb_setarg(1, T, V).
sa_binc(T) :- sa_arg(1, T, V0), V is V0+1, setarg(1, T, V).
:- dynamic sa_hooklog/2.
% sa_log(Tag): an attribute (module user) whose hook records the value it is bound to
attr_unify_hook(sa_log(Tag), V) :- ( attvar(V) -> K = attvar ; var(V) -> K = var ; K = V ), assertz(sa_hooklog(Tag, K)).
t_sa01(R) :- catch((T = f(a,b), setarg(1, T, x), R = T), error(SsuE, _), R = raised(SsuE)).
t_sa02(R) :- catch((T = f(a,b), setarg(2, T, x), R = T), error(SsuE, _), R = raised(SsuE)).
t_sa03(R) :- catch((T = f(a,b,c), ( setarg(2, T, x), fail ; true ), R = T), error(SsuE, _), R = raised(SsuE)).
t_sa04(R) :- catch((T = f(a), setarg(1, T, x), setarg(1, T, y), R = T), error(SsuE, _), R = raised(SsuE)).
t_sa05(R) :- catch((T = f(a), ( setarg(1, T, x), setarg(1, T, y), fail ; true ), R = T), error(SsuE, _), R = raised(SsuE)).
t_sa06(R) :- catch((T = f(a), setarg(1, T, x), ( setarg(1, T, y), fail ; true ), R = T), error(SsuE, _), R = raised(SsuE)).
t_sa07(R) :- catch((T = f(_), setarg(1, T, v), R = T), error(SsuE, _), R = raised(SsuE)).
t_sa08(R) :- catch((T = f(_), ( setarg(1, T, v), fail ; true ), R = T), error(SsuE, _), R = raised(SsuE)).
t_sa09(R) :- catch((T = f(X), setarg(1, T, a), R = X-T), error(SsuE, _), R = raised(SsuE)).
t_sa10(R) :- catch((T = f(X), ( setarg(1, T, a), fail ; true ), R = X-T), error(SsuE, _), R = raised(SsuE)).
t_sa11(R) :- catch((T = f(X), X = b, setarg(1, T, c), R = X-T), error(SsuE, _), R = raised(SsuE)).
t_sa12(R) :- catch((T = f(_), setarg(1, T, X), R = T-X), error(SsuE, _), R = raised(SsuE)).
t_sa13(R) :- catch((T = f(a), setarg(1, T, X), X = q, R = T-X), error(SsuE, _), R = raised(SsuE)).
t_sa14(R) :- catch((T = f(a), setarg(1, T, X), ( X = q, fail ; true ), R = T-X), error(SsuE, _), R = raised(SsuE)).
t_sa15(R) :- catch((T = f(a), ( setarg(0, T, x) -> R = yes ; R = no )), error(SsuE, _), R = raised(SsuE)).
t_sa16(R) :- catch((T = f(a), ( setarg(2, T, x) -> R = yes ; R = no )), error(SsuE, _), R = raised(SsuE)).
t_sa17(R) :- catch((setarg(-1, f(a), x), R = yes), error(SsuE, _), R = raised(SsuE)).
t_sa18(R) :- catch((setarg(_, f(a), x), R = yes), error(SsuE, _), R = raised(SsuE)).
t_sa19(R) :- catch((setarg(a, f(a), x), R = yes), error(SsuE, _), R = raised(SsuE)).
t_sa20(R) :- catch((setarg(1.0, f(a), x), R = yes), error(SsuE, _), R = raised(SsuE)).
t_sa21(R) :- catch((X is 1<<70, setarg(X, f(a), x), R = yes), error(SsuE, _), R = raised(SsuE)).
t_sa22(R) :- catch((X is -(1<<70), setarg(X, f(a), x), R = yes), error(SsuE, _), R = raised(SsuE)).
t_sa23(R) :- catch((setarg(1, a, x), R = yes), error(SsuE, _), R = raised(SsuE)).
t_sa24(R) :- catch((setarg(1, _, x), R = yes), error(SsuE, _), R = raised(SsuE)).
t_sa25(R) :- catch((setarg(1, 3, x), R = yes), error(SsuE, _), R = raised(SsuE)).
t_sa26(R) :- catch((atom_string(abc, S), setarg(1, S, x), R = yes), error(SsuE, _), R = raised(SsuE)).
t_sa27(R) :- catch((setarg(1, [], x), R = yes), error(SsuE, _), R = raised(SsuE)).
t_sa28(R) :- catch((( nb_setarg(0, f(a), x) -> R = yes ; R = no )), error(SsuE, _), R = raised(SsuE)).
t_sa29(R) :- catch((( nb_setarg(3, f(a), x) -> R = yes ; R = no )), error(SsuE, _), R = raised(SsuE)).
t_sa30(R) :- catch((nb_setarg(a, f(a), x), R = yes), error(SsuE, _), R = raised(SsuE)).
t_sa31(R) :- catch((nb_setarg(-1, f(a), x), R = yes), error(SsuE, _), R = raised(SsuE)).
t_sa32(R) :- catch((nb_setarg(1, a, x), R = yes), error(SsuE, _), R = raised(SsuE)).
t_sa33(R) :- catch((nb_setarg(1, _, x), R = yes), error(SsuE, _), R = raised(SsuE)).
t_sa34(R) :- catch((( nb_linkarg(0, f(a), x) -> R = yes ; R = no )), error(SsuE, _), R = raised(SsuE)).
t_sa35(R) :- catch((( nb_linkarg(2, f(a), x) -> R = yes ; R = no )), error(SsuE, _), R = raised(SsuE)).
t_sa36(R) :- catch((nb_linkarg(a, f(a), x), R = yes), error(SsuE, _), R = raised(SsuE)).
t_sa37(R) :- catch((nb_linkarg(1, a, x), R = yes), error(SsuE, _), R = raised(SsuE)).
t_sa38(R) :- catch((nb_linkarg(1, _, x), R = yes), error(SsuE, _), R = raised(SsuE)).
t_sa39(R) :- catch((T = f(a,b), nb_setarg(1, T, x), R = T), error(SsuE, _), R = raised(SsuE)).
t_sa40(R) :- catch((T = f(a), ( nb_setarg(1, T, x), fail ; true ), R = T), error(SsuE, _), R = raised(SsuE)).
t_sa41(R) :- catch((T = f(a), ( setarg(1, T, b), nb_setarg(1, T, c), fail ; true ), R = T), error(SsuE, _), R = raised(SsuE)).
t_sa42(R) :- catch((T = f(a), ( nb_setarg(1, T, b), setarg(1, T, c), fail ; true ), R = T), error(SsuE, _), R = raised(SsuE)).
t_sa43(R) :- catch((T = f(a), ( nb_setarg(1, T, g(1)), fail ; true ), R = T), error(SsuE, _), R = raised(SsuE)).
t_sa44(R) :- catch((T = f(a), ( X is 1.5*2, nb_setarg(1, T, X), fail ; true ), R = T), error(SsuE, _), R = raised(SsuE)).
t_sa45(R) :- catch((T = f(a), ( X is 1<<70, nb_setarg(1, T, X), fail ; true ), R = T), error(SsuE, _), R = raised(SsuE)).
t_sa46(R) :- catch((T = f(a), ( atom_string(abc, S), nb_setarg(1, T, S), fail ; true ), R = T), error(SsuE, _), R = raised(SsuE)).
t_sa47(R) :- catch((T = f(a), ( nb_setarg(1, T, [x,y,z]), fail ; true ), R = T), error(SsuE, _), R = raised(SsuE)).
t_sa48(R) :- catch((T = c(0), ( sa_mem(_, [1,2,3]), sa_inc(T), fail ; true ), R = T), error(SsuE, _), R = raised(SsuE)).
t_sa49(R) :- catch((T = c(0), ( sa_mem(_, [1,2,3]), sa_binc(T), fail ; true ), R = T), error(SsuE, _), R = raised(SsuE)).
t_sa50(R) :- catch((T = acc([]), ( sa_mem(X, [a,b,c]), sa_arg(1, T, L), nb_setarg(1, T, [X|L]), fail ; true ), sa_arg(1, T, R)), error(SsuE, _), R = raised(SsuE)).
t_sa51(R) :- catch((T = f(a), ( nb_linkarg(1, T, g(1)), fail ; true ), R = T), error(SsuE, _), R = raised(SsuE)).
t_sa52(R) :- catch((T = f(a), V = g(1), setarg(1, T, V), sa_arg(1, T, A), sa_same(A, V, R)), error(SsuE, _), R = raised(SsuE)).
t_sa53(R) :- catch((T = f(a), V = g(1), nb_setarg(1, T, V), sa_arg(1, T, A), sa_same(A, V, R)), error(SsuE, _), R = raised(SsuE)).
t_sa54(R) :- catch((T = f(a), V = g(1), nb_linkarg(1, T, V), sa_arg(1, T, A), sa_same(A, V, R)), error(SsuE, _), R = raised(SsuE)).
t_sa55(R) :- catch((T = f(g(1)), sa_arg(1, T, Old), nb_setarg(1, T, h(Old)), sa_arg(1, T, H), sa_arg(1, H, O2), sa_same(O2, Old, R)), error(SsuE, _), R = raised(SsuE)).
t_sa56(R) :- catch((T = f(g(1)), sa_arg(1, T, Old), nb_setarg(1, T, h(i(Old))), sa_arg(1, T, H), sa_arg(1, H, I), sa_arg(1, I, O2), sa_same(O2, Old, R)), error(SsuE, _), R = raised(SsuE)).
t_sa57(R) :- catch((T = f(g(1)), sa_arg(1, T, Old), nb_setarg(1, T, Old), sa_arg(1, T, A), sa_same(A, Old, R)), error(SsuE, _), R = raised(SsuE)).
t_sa58(R) :- catch((T = f(g(1)), sa_arg(1, T, Old), nb_setarg(1, T, h(g(1))), sa_arg(1, T, H), sa_arg(1, H, O2), sa_same(O2, Old, R)), error(SsuE, _), R = raised(SsuE)).
t_sa59(R) :- catch((T = f(g(1), k), sa_arg(1, T, Old), nb_setarg(2, T, h(Old)), sa_arg(2, T, H), sa_arg(1, H, O2), sa_same(O2, Old, R)), error(SsuE, _), R = raised(SsuE)).
t_sa60(R) :- catch((T = f(g(a)), sa_arg(1, T, G), setarg(1, G, b), R = T), error(SsuE, _), R = raised(SsuE)).
t_sa61(R) :- catch((T = f(g(a)), sa_arg(1, T, G), ( nb_setarg(1, G, b), fail ; true ), R = T), error(SsuE, _), R = raised(SsuE)).
t_sa62(R) :- catch((X = f(a), Y = g(X), setarg(1, X, b), R = Y), error(SsuE, _), R = raised(SsuE)).
t_sa63(R) :- catch((L = [a,b], setarg(1, L, x), setarg(2, L, [z]), R = L), error(SsuE, _), R = raised(SsuE)).
t_sa64(R) :- catch((sa_zero(T), ( setarg(1, T, a) -> R = yes ; R = no )), error(SsuE, _), R = raised(SsuE)).
t_sa65(R) :- catch((findall(x, setarg(1, f(a), b), R)), error(SsuE, _), R = raised(SsuE)).
t_sa66(R) :- catch((findall(x, nb_setarg(1, f(a), b), R)), error(SsuE, _), R = raised(SsuE)).
t_sa67(R) :- catch((findall(x, nb_linkarg(1, f(a), b), R)), error(SsuE, _), R = raised(SsuE)).
t_sa68(R) :- catch((put_attr(X, sa, 1), T = f(a), setarg(1, T, X), sa_arg(1, T, A), get_attr(A, sa, R)), error(SsuE, _), R = raised(SsuE)).
t_sa69(R) :- catch((put_attr(X, sa, 1), T = f(a), ( setarg(1, T, X), fail ; true ), R = T), error(SsuE, _), R = raised(SsuE)).
t_sa70(R) :- catch((put_attr(X, sa, 1), T = f(a), ( nb_setarg(1, T, X), fail ; true ), sa_arg(1, T, A), ( attvar(A) -> R = att ; R = plain )), error(SsuE, _), R = raised(SsuE)).
t_sa71(R) :- catch((put_attr(X, sa, 1), T = f(a), nb_setarg(1, T, g(X)), sa_arg(1, T, G), sa_arg(1, G, A), ( attvar(A) -> get_attr(A, sa, R) ; R = plain )), error(SsuE, _), R = raised(SsuE)).
t_sa72(R) :- catch((put_attr(X, sa, 1), T = f(X), setarg(1, T, b), get_attr(X, sa, V), R = T-V), error(SsuE, _), R = raised(SsuE)).
t_sa73(R) :- catch((X = g(X), T = f(a), setarg(1, T, X), sa_arg(1, T, A), ( cyclic_term(A) -> R = cyc ; R = acyc )), error(SsuE, _), R = raised(SsuE)).
t_sa74(R) :- catch((X = g(X), T = f(a), nb_setarg(1, T, X), sa_arg(1, T, A), ( cyclic_term(A) -> R = cyc ; R = acyc )), error(SsuE, _), R = raised(SsuE)).
t_sa75(R) :- catch((X = g(X), T = f(a), nb_setarg(1, T, X), sa_arg(1, T, A), sa_same(A, X, R)), error(SsuE, _), R = raised(SsuE)).
t_sa76(R) :- catch((T = f(T), setarg(1, T, b), R = T), error(SsuE, _), R = raised(SsuE)).
t_sa77(R) :- catch((T = f(T), ( setarg(1, T, b), fail ; true ), sa_arg(1, T, A), sa_same(A, T, R)), error(SsuE, _), R = raised(SsuE)).
t_sa78(R) :- catch((T = f(a), nb_setarg(1, T, X), X = q, R = T), error(SsuE, _), R = raised(SsuE)).
t_sa79(R) :- catch((T = f(a), nb_setarg(1, T, X), sa_arg(1, T, A), ( A == X -> R = same ; R = diff )), error(SsuE, _), R = raised(SsuE)).
t_sa80(R) :- catch((T = f(a), nb_linkarg(1, T, X), X = q, R = T), error(SsuE, _), R = raised(SsuE)).
t_sa81(R) :- catch((T = f(a), ( nb_setarg(1, T, X), fail ; true ), sa_arg(1, T, A), ( var(A) -> R = var ; R = nonvar )), error(SsuE, _), R = raised(SsuE)).
t_sa82(R) :- catch((T = f(a), ( put_attr(X, sa, 1), nb_setarg(1, T, X), fail ; true ), sa_arg(1, T, A), ( attvar(A) -> get_attr(A, sa, R) ; R = plain )), error(SsuE, _), R = raised(SsuE)).
t_sa83(R) :- catch((T = f(a), ( put_attr(X, sa, 1), nb_setarg(1, T, g(X)), fail ; true ), sa_arg(1, T, G), sa_arg(1, G, A), ( attvar(A) -> get_attr(A, sa, R) ; R = plain )), error(SsuE, _), R = raised(SsuE)).
t_sa84(R) :- catch((W = _, V = _, T = f(a), setarg(1, T, V), sa_arg(1, T, A), compare(O1, W, A), compare(O2, A, V), R = O1-O2), error(SsuE, _), R = raised(SsuE)).
t_sa85(R) :- catch((W = _, V = _, T = f(a), nb_setarg(1, T, V), sa_arg(1, T, A), compare(O1, W, A), compare(O2, A, V), R = O1-O2), error(SsuE, _), R = raised(SsuE)).
t_sa86(R) :- catch((W = _, V = _, T = f(a), nb_linkarg(1, T, V), sa_arg(1, T, A), compare(O1, W, A), compare(O2, A, V), R = O1-O2), error(SsuE, _), R = raised(SsuE)).
t_sa87(R) :- catch((T = f(a), W = _, X = _, setarg(1, T, X), sa_arg(1, T, A), compare(O1, A, W), compare(O2, A, X), R = O1-O2), error(SsuE, _), R = raised(SsuE)).
t_sa88(R) :- catch((T = f(a), W = _, X = _, nb_setarg(1, T, X), sa_arg(1, T, A), compare(O1, A, W), compare(O2, A, X), R = O1-O2), error(SsuE, _), R = raised(SsuE)).
t_sa89(R) :- catch((T = f(a), W = _, X = _, nb_linkarg(1, T, X), sa_arg(1, T, A), compare(O1, A, W), compare(O2, A, X), R = O1-O2), error(SsuE, _), R = raised(SsuE)).
t_sa90(R) :- catch((put_attr(X, user, sa_log(s90)), T = f(a), setarg(1, T, X), sa_arg(1, T, A), get_attr(A, user, At), ( A == X -> I = same ; I = diff ), R = At-I), error(SsuE, _), R = raised(SsuE)).
t_sa91(R) :- catch((put_attr(X, user, sa_log(s91)), T = f(a), nb_setarg(1, T, X), sa_arg(1, T, A), get_attr(A, user, At), ( A == X -> I = same ; I = diff ), R = At-I), error(SsuE, _), R = raised(SsuE)).
t_sa92(R) :- catch((put_attr(X, user, sa_log(s92)), T = f(a), setarg(1, T, X), X = 5, findall(K, sa_hooklog(s92, K), L), R = T-L), error(SsuE, _), R = raised(SsuE)).
t_sa93(R) :- catch((put_attr(X, user, sa_log(s93)), T = f(a), nb_linkarg(1, T, X), sa_arg(1, T, A), A = 6, findall(K, sa_hooklog(s93, K), L), R = X-L), error(SsuE, _), R = raised(SsuE)).
t_sa94(R) :- catch((put_attr(X, user, sa_log(s94)), T = f(a), nb_setarg(1, T, X), X = 7, findall(K, sa_hooklog(s94, K), L), R = T-L), error(SsuE, _), R = raised(SsuE)).
