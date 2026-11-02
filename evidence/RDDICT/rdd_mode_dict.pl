:- set_prolog_flag(var_tag, 'dict').
rdt(G, G1) :- ( var(G) -> G1 = var ; G1 = G ).
rdo(A, R) :- ( attvar(A) -> R = attvar ; is_dict(A) -> dict_pairs(A, G, Ps), rdt(G, G1), R = d(G1, Ps) ; var(A) -> R = var ; R = A ).
rdd(Txt, R) :- term_to_atom(T, Txt), ( attvar(T) -> R = attvar ; is_dict(T) -> dict_pairs(T, G, Ps), rdt(G, G1), R = d(G1, Ps) ; R = nodict(T) ).
rdv(Txt, K, R) :- term_to_atom(T, Txt), get_dict(K, T, V), rdo(V, R).
rdw(Txt, K1, K2, R) :- term_to_atom(T, Txt), get_dict(K1, T, V1), get_dict(K2, V1, V2), rdo(V2, R).
rda(Txt, N, R) :- term_to_atom(T, Txt), arg(N, T, A), rdo(A, R).
rdx(Txt, R) :- term_to_atom(T, Txt), ( compound(T), T =.. [F, A, B] -> rdo(A, A1), rdo(B, B1), R = F-A1-B1 ; R = other(T) ).
rds(Txt, R) :- catch(( term_to_atom(_, Txt), R = read ), error(syntax_error(I), string(_, P)), R = syn(I, P)).
t_rm01(R) :- catch((rdd('_{a:1}', R)), error(SsuE, _), R = raised(SsuE)).
t_rm02(R) :- catch((rdd('Tag{a:1,b:2}', R)), error(SsuE, _), R = raised(SsuE)).
t_rm03(R) :- catch((rdd('t{a:1}', R)), error(SsuE, _), R = raised(SsuE)).
t_rm04(R) :- catch((rdd('_{}', R)), error(SsuE, _), R = raised(SsuE)).
t_rm05(R) :- catch((rda('f(_{a:1},_)', 1, R)), error(SsuE, _), R = raised(SsuE)).
t_rm06(R) :- catch((rda('f(t{a:1},_{b:2})', 2, R)), error(SsuE, _), R = raised(SsuE)).
t_rm07(R) :- catch((rds('_{a:1,a:2}', R)), error(SsuE, _), R = raised(SsuE)).
t_rm08(R) :- catch((rds('_{a}', R)), error(SsuE, _), R = raised(SsuE)).
t_rm09(R) :- catch((rds('t{a:1,a:2}', R)), error(SsuE, _), R = raised(SsuE)).
