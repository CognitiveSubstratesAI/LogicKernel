rdt(G, G1) :- ( var(G) -> G1 = var ; G1 = G ).
rdo(A, R) :- ( attvar(A) -> R = attvar ; is_dict(A) -> dict_pairs(A, G, Ps), rdt(G, G1), R = d(G1, Ps) ; var(A) -> R = var ; R = A ).
rdd(Txt, R) :- term_to_atom(T, Txt), ( attvar(T) -> R = attvar ; is_dict(T) -> dict_pairs(T, G, Ps), rdt(G, G1), R = d(G1, Ps) ; R = nodict(T) ).
rdv(Txt, K, R) :- term_to_atom(T, Txt), get_dict(K, T, V), rdo(V, R).
rdw(Txt, K1, K2, R) :- term_to_atom(T, Txt), get_dict(K1, T, V1), get_dict(K2, V1, V2), rdo(V2, R).
rda(Txt, N, R) :- term_to_atom(T, Txt), arg(N, T, A), rdo(A, R).
rdx(Txt, R) :- term_to_atom(T, Txt), ( compound(T), T =.. [F, A, B] -> rdo(A, A1), rdo(B, B1), R = F-A1-B1 ; R = other(T) ).
rdp(Txt, R) :- read_term_from_atom(Txt, _, [subterm_positions(R)]).
rds(Txt, R) :- catch(( term_to_atom(_, Txt), R = read ), error(syntax_error(I), string(_, P)), R = syn(I, P)).
rdb1(R) :- D = _{a:1,b:2}, dict_pairs(D, _, R).
rdb2(R) :- X = _{file_type:regular}, dict_pairs(X, _, R).
rdb3(R) :- _{module:M, exports:E, file:F} :< _{module:m1, exports:[a/1], file:'x.pl', extra:1}, R = M-E-F.
rdb4(R) :- T = point{x:1, y:2}, dict_pairs(T, Tag, Ps), R = Tag-Ps.
rdb5(R) :- T = Tag{k:v}, dict_pairs(T, G, Ps), ( G == Tag -> R = same(Ps) ; R = other ).
rdh(_{a:1}, yes).
rdh(t{a:1}, tagged).
t_rd01(R) :- catch((rdd('_{}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd02(R) :- catch((rdd('_{ }', R)), error(SsuE, _), R = raised(SsuE)).
t_rd03(R) :- catch((rdd('_{a:1}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd04(R) :- catch((rdd('t{b:1,a:2}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd05(R) :- catch((rdd('Tag{k:v,k2:v2}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd06(R) :- catch((rdd('t{}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd07(R) :- catch((rdd('X{a:1}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd08(R) :- catch((rdd('\'x y\'{a:2}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd09(R) :- catch((rdd('_{1:a,2:b}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd10(R) :- catch((rdd('_{[]:x}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd11(R) :- catch((rdd('_{\'\':1}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd12(R) :- catch((rdd('_{-1:a}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd13(R) :- catch((rdd('_{a:1,1:b,[]:c,z:d}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd14(R) :- catch((rdd('_{0\'a:1}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd15(R) :- catch((rdd('_{a:1,b:2,c:3,d:4,e:5,f:6,g:7,h:8}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd16(R) :- catch((rdd('_{h:8,g:7,f:6,e:5,d:4,c:3,b:2,a:1}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd17(R) :- catch((rdd('_{a:X,b:X}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd18(R) :- catch((rdd('_{a:f(X,Y),b:"str",c:1.5,d:[1,2],e:\'q q\',f:Y}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd19(R) :- catch((rdd('_{a: -1}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd20(R) :- catch((rdd('_{a:(b,c)}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd21(R) :- catch((rdd('_{a:b:c}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd22(R) :- catch((rdd('_{a:(x:-y)}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd23(R) :- catch((rdd('_{a:- 1}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd24(R) :- catch((rdd('_{a:{x}}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd25(R) :- catch((rdd('_{a:1+2*3}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd26(R) :- catch((rdd('_{ a : 1 , b : 2 }', R)), error(SsuE, _), R = raised(SsuE)).
t_rd27(R) :- catch((rdd('_{a:1,\nb:2}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd28(R) :- catch((rdd('_{a:1, /* c */ b:2}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd29(R) :- catch((rdd('_{\'a b\':1}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd30(R) :- catch((rdd('_{{}:1}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd31(R) :- catch((rdd('_{+ :1}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd32(R) :- catch((rdd('_{1:a,a:1,[]:b,\'\':c}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd33(R) :- catch((rdd('{a}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd34(R) :- catch((rdd('f(x)', R)), error(SsuE, _), R = raised(SsuE)).
t_rd35(R) :- catch((rdd('f{}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd36(R) :- catch((rdd('_{a:1} ', R)), error(SsuE, _), R = raised(SsuE)).
t_rd37(R) :- catch((rdd('_{a:\'_{b:1}\'}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd38(R) :- catch((rdv('_{a:_{b:1}}', a, R)), error(SsuE, _), R = raised(SsuE)).
t_rd39(R) :- catch((rdv('_{a:t{b:1,c:x}}', a, R)), error(SsuE, _), R = raised(SsuE)).
t_rd40(R) :- catch((rdw('_{a:t{b:1,c:_{}}}', a, c, R)), error(SsuE, _), R = raised(SsuE)).
t_rd41(R) :- catch((rdw('t{a:u{b:v{c:1}}}', a, b, R)), error(SsuE, _), R = raised(SsuE)).
t_rd42(R) :- catch((rdw('_{a:t{c:_{x:1,y:2}}}', a, c, R)), error(SsuE, _), R = raised(SsuE)).
t_rd43(R) :- catch((rdv('_{a:1,b:X{c:2}}', b, R)), error(SsuE, _), R = raised(SsuE)).
t_rd44(R) :- catch((rda('f(_{a:1},_{b:2})', 1, R)), error(SsuE, _), R = raised(SsuE)).
t_rd45(R) :- catch((rda('f(_{a:1},_{b:2})', 2, R)), error(SsuE, _), R = raised(SsuE)).
t_rd46(R) :- catch((rda('g(x,t{a:1,b:2},y)', 2, R)), error(SsuE, _), R = raised(SsuE)).
t_rd47(R) :- catch((rda('[_{a:1}]', 1, R)), error(SsuE, _), R = raised(SsuE)).
t_rd48(R) :- catch((rda('a- _{x:1}', 2, R)), error(SsuE, _), R = raised(SsuE)).
t_rd49(R) :- catch((rda('f(t{a:1}, t{a:1})', 1, R)), error(SsuE, _), R = raised(SsuE)).
t_rd50(R) :- catch((rda('f(_{a:1,b:2,c:3},x)', 1, R)), error(SsuE, _), R = raised(SsuE)).
t_rd51(R) :- catch((rdx('_{a:1}:b', R)), error(SsuE, _), R = raised(SsuE)).
t_rd52(R) :- catch((rdx('t{a:1}=X', R)), error(SsuE, _), R = raised(SsuE)).
t_rd53(R) :- catch((rdx('p:-_{a:1}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd54(R) :- catch((rdx('f(x):_{a:1}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd55(R) :- catch((rds('_{a}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd56(R) :- catch((rds('_{a:1', R)), error(SsuE, _), R = raised(SsuE)).
t_rd57(R) :- catch((rds('_{a:1,a:2}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd58(R) :- catch((rds('_{1.5:a}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd59(R) :- catch((rds('_{99999999999999999999:1}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd60(R) :- catch((rds('_{f(x):1}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd61(R) :- catch((rds('_{a:1,}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd62(R) :- catch((rds('t{a:1,,b:2}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd63(R) :- catch((rds('_{"s":1}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd64(R) :- catch((rds('_{a:-}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd65(R) :- catch((rds('_{a:1}{b:2}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd66(R) :- catch((rds('1{a:2}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd67(R) :- catch((rds('"s"{a:2}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd68(R) :- catch((rds('_{a:1 b:2}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd69(R) :- catch((rds('_{:1}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd70(R) :- catch((rds('_{a:}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd71(R) :- catch((rds('_{a:1,b}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd72(R) :- catch((rds('_{,}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd73(R) :- catch((rds('_{a:1)', R)), error(SsuE, _), R = raised(SsuE)).
t_rd74(R) :- catch((rds('_{a:1]', R)), error(SsuE, _), R = raised(SsuE)).
t_rd75(R) :- catch((rds('_{a:x:-y}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd76(R) :- catch((rds('_ {a:1}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd77(R) :- catch((rds('foo {a:1}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd78(R) :- catch((rds('_{1:a,1:b}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd79(R) :- catch((rds('_{a:1,b:2,a:3}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd80(R) :- catch((rds('_{(a):1}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd81(R) :- catch((rds('_{a;1}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd82(R) :- catch((rds('_{a=1}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd83(R) :- catch((rds('_{\'a\':1,a:2}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd84(R) :- catch((rds('_{0\'a:1,97:2}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd85(R) :- catch((rds('_{-1:a,-1:b}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd86(R) :- catch((rds('_{a:1,b:2', R)), error(SsuE, _), R = raised(SsuE)).
t_rd87(R) :- catch((rds('_{', R)), error(SsuE, _), R = raised(SsuE)).
t_rd88(R) :- catch((rds('t{', R)), error(SsuE, _), R = raised(SsuE)).
t_rd89(R) :- catch((rds('a{b}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd90(R) :- catch((rds('_{a:1,[a]:2}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd91(R) :- catch((rds('X{a:1}.', R)), error(SsuE, _), R = raised(SsuE)).
t_rd92(R) :- catch((rds('_{[]:1,[]:2}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd93(R) :- catch((rdx('Ctx.get(stack)', R)), error(SsuE, _), R = raised(SsuE)).
t_rd94(R) :- catch((rdx('_{a:1}.put(b,2)', R)), error(SsuE, _), R = raised(SsuE)).
t_rd95(R) :- catch((rdx('X.y.z', R)), error(SsuE, _), R = raised(SsuE)).
t_rd96(R) :- catch((rdx('X.put(a,1).get(a)', R)), error(SsuE, _), R = raised(SsuE)).
t_rd97(R) :- catch((rdx('_{a:1}.a', R)), error(SsuE, _), R = raised(SsuE)).
t_rd98(R) :- catch((rdx('t{a:1}.get(a)', R)), error(SsuE, _), R = raised(SsuE)).
t_rd99(R) :- catch((rdx('a.b', R)), error(SsuE, _), R = raised(SsuE)).
t_rd100(R) :- catch((rdx('X.Y', R)), error(SsuE, _), R = raised(SsuE)).
t_rd101(R) :- catch((rdx('1.5', R)), error(SsuE, _), R = raised(SsuE)).
t_rd102(R) :- catch((rdx('f(a).g', R)), error(SsuE, _), R = raised(SsuE)).
t_rd103(R) :- catch((rdx('X.put(k,v)', R)), error(SsuE, _), R = raised(SsuE)).
t_rd104(R) :- catch((rdx('X.put(f(Y),Y)', R)), error(SsuE, _), R = raised(SsuE)).
t_rd105(R) :- catch((rdx('X.put(a,Y).get(a)', R)), error(SsuE, _), R = raised(SsuE)).
t_rd106(R) :- catch((rdb1(R)), error(SsuE, _), R = raised(SsuE)).
t_rd107(R) :- catch((rdb2(R)), error(SsuE, _), R = raised(SsuE)).
t_rd108(R) :- catch((rdb3(R)), error(SsuE, _), R = raised(SsuE)).
t_rd109(R) :- catch((rdb4(R)), error(SsuE, _), R = raised(SsuE)).
t_rd110(R) :- catch((rdb5(R)), error(SsuE, _), R = raised(SsuE)).
t_rd111(R) :- catch((rdh(_{a:1}, R)), error(SsuE, _), R = raised(SsuE)).
t_rd112(R) :- catch((rdh(_{a:2}, R)), error(SsuE, _), R = raised(SsuE)).
t_rd113(R) :- catch((rdh(t{a:1}, R)), error(SsuE, _), R = raised(SsuE)).
t_rd114(R) :- catch((rdh(X, R), X = _{a:1}), error(SsuE, _), R = raised(SsuE)).
t_rd115(R) :- catch((rdp('_{a:1}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd116(R) :- catch((rdp('t{a:1,b:f(x)}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd117(R) :- catch((rdp('_{}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd118(R) :- catch((rdp('X{k:v}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd119(R) :- catch((rdp('f(_{a:1})', R)), error(SsuE, _), R = raised(SsuE)).
t_rd120(R) :- catch((rdp('_{1:a}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd121(R) :- catch((rdp('_{a:_{b:1}}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd122(R) :- catch((rdp(' _{ a : 1 , b : 2 } ', R)), error(SsuE, _), R = raised(SsuE)).
t_rd123(R) :- catch((rdp('t{a:1,b:2,c:3}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd124(R) :- catch((rdp('[_{a:1},t{}]', R)), error(SsuE, _), R = raised(SsuE)).
t_rd125(R) :- catch((rdp('_{\'x y\':"s"}', R)), error(SsuE, _), R = raised(SsuE)).
t_rd126(R) :- catch((rdp('a- _{}', R)), error(SsuE, _), R = raised(SsuE)).
