p_zero(foo()).
p_cyc(X) :- X = f(X).
t_p001(R) :- catch((arg(1, f(a,b,c), R)), error(SsuE, _), R = raised(SsuE)).
t_p002(R) :- catch((arg(3, f(a,b,c), R)), error(SsuE, _), R = raised(SsuE)).
t_p003(R) :- catch((arg(4, f(a,b,c), R)), error(SsuE, _), R = raised(SsuE)).
t_p004(R) :- catch((arg(0, f(a,b), R)), error(SsuE, _), R = raised(SsuE)).
t_p005(R) :- catch((arg(-1, f(a), R)), error(SsuE, _), R = raised(SsuE)).
t_p006(R) :- catch((arg(a, f(a), R)), error(SsuE, _), R = raised(SsuE)).
t_p007(R) :- catch((arg(1, a, R)), error(SsuE, _), R = raised(SsuE)).
t_p008(R) :- catch((arg(1, _, R)), error(SsuE, _), R = raised(SsuE)).
t_p009(R) :- catch((arg(100000000000000000000, f(a), R)), error(SsuE, _), R = raised(SsuE)).
t_p010(R) :- catch((arg(-100000000000000000000, f(a), R)), error(SsuE, _), R = raised(SsuE)).
t_p011(R) :- catch((arg(1.0, f(a), R)), error(SsuE, _), R = raised(SsuE)).
t_p012(R) :- catch((findall(N-A, arg(N, f(a,b,c), A), R)), error(SsuE, _), R = raised(SsuE)).
t_p013(R) :- catch((findall(N, arg(N, f(a,b,a), a), R)), error(SsuE, _), R = raised(SsuE)).
t_p014(R) :- catch((call_cleanup(arg(N, f(a,b,c), c), Det = true), R = N-Det), error(SsuE, _), R = raised(SsuE)).
t_p015(R) :- catch((call_cleanup(arg(N, f(a,b,c), a), Det = true), ( Det == true -> R = N-det ; R = N-nondet )), error(SsuE, _), R = raised(SsuE)).
t_p016(R) :- catch((arg(2, f(a,B), X), R = B-X), error(SsuE, _), R = raised(SsuE)).
t_p017(R) :- catch((arg(1, f(X), Y), X = 1, R = Y), error(SsuE, _), R = raised(SsuE)).
t_p018(R) :- catch((findall(N-X-Y, arg(N, f(X,Y), 1), R)), error(SsuE, _), R = raised(SsuE)).
t_p019(R) :- catch((arg(1, f(a), b), R = yes), error(SsuE, _), R = raised(SsuE)).
t_p020(R) :- catch((p_zero(T), findall(N, arg(N, T, _), R)), error(SsuE, _), R = raised(SsuE)).
t_p021(R) :- catch((p_zero(T), arg(1, T, _), R = yes), error(SsuE, _), R = raised(SsuE)).
t_p022(R) :- catch((arg(1, "str", R)), error(SsuE, _), R = raised(SsuE)).
t_p023(R) :- catch((findall(N-A, arg(N, [a,b], A), R)), error(SsuE, _), R = raised(SsuE)).
t_p024(R) :- catch((call(arg, 2, f(a,b), R)), error(SsuE, _), R = raised(SsuE)).
t_p025(R) :- catch((findall(N-A, arg(N, f(a,b,c), A), [_,_|R])), error(SsuE, _), R = raised(SsuE)).
t_p026(R) :- catch((arg(N, f(a,b,c), A), N > 1, R = N-A), error(SsuE, _), R = raised(SsuE)).
t_p027(R) :- catch((arg(N, f(a), a), R = N), error(SsuE, _), R = raised(SsuE)).
t_p028(R) :- catch((p_cyc(C), arg(1, C, A), ( A == C -> R = same ; R = diff )), error(SsuE, _), R = raised(SsuE)).
t_p029(R) :- catch((compound_name_arity(f(a,b), N, A), R = N/A), error(SsuE, _), R = raised(SsuE)).
t_p030(R) :- catch((compound_name_arity(T, foo, 3), R = T), error(SsuE, _), R = raised(SsuE)).
t_p031(R) :- catch((p_zero(T), compound_name_arity(T, N, A), R = N/A), error(SsuE, _), R = raised(SsuE)).
t_p032(R) :- catch((compound_name_arity(T, foo, 0), compound_name_arity(T, N, A), R = T-N/A), error(SsuE, _), R = raised(SsuE)).
t_p033(R) :- catch((compound_name_arity(a, N, A), R = N/A), error(SsuE, _), R = raised(SsuE)).
t_p034(R) :- catch((compound_name_arity(_, _, _)), error(SsuE, _), R = raised(SsuE)).
t_p035(R) :- catch((compound_name_arity(T, 1, 2), R = T), error(SsuE, _), R = raised(SsuE)).
t_p036(R) :- catch((compound_name_arity(T, f, -1), R = T), error(SsuE, _), R = raised(SsuE)).
t_p037(R) :- catch((compound_name_arity(T, f, a), R = T), error(SsuE, _), R = raised(SsuE)).
t_p038(R) :- catch((compound_name_arity(T, f, _), R = T), error(SsuE, _), R = raised(SsuE)).
t_p039(R) :- catch((compound_name_arity(T, _, 2), R = T), error(SsuE, _), R = raised(SsuE)).
t_p040(R) :- catch((compound_name_arity([a], N, A), R = N/A), error(SsuE, _), R = raised(SsuE)).
t_p041(R) :- catch((compound_name_arity(f(a), g, A), R = A), error(SsuE, _), R = raised(SsuE)).
t_p042(R) :- catch((compound_name_arity(f(a,b), N, 3), R = N), error(SsuE, _), R = raised(SsuE)).
t_p043(R) :- catch((compound_name_arity(T, "s", 2), R = T), error(SsuE, _), R = raised(SsuE)).
t_p044(R) :- catch((compound_name_arity(T, [], 2), R = T), error(SsuE, _), R = raised(SsuE)).
t_p045(R) :- catch((compound_name_arity(T, 'hello world', 1), R = T), error(SsuE, _), R = raised(SsuE)).
t_p046(R) :- catch((compound_name_arity("str", N, A), R = N/A), error(SsuE, _), R = raised(SsuE)).
t_p047(R) :- catch((compound_name_arity(f(X,Y,X), N, A), R = N/A-X-Y), error(SsuE, _), R = raised(SsuE)).
t_p048(R) :- catch((compound_name_arity(T, f, 2), arg(1, T, a), R = T), error(SsuE, _), R = raised(SsuE)).
t_p049(R) :- catch((compound_name_arity(T, f, 100000000000000000000), R = T), error(SsuE, _), R = raised(SsuE)).
t_p050(R) :- catch((compound_name_arity(T, f, 1.0), R = T), error(SsuE, _), R = raised(SsuE)).
t_p051(R) :- catch((compound_name_arity(T, g, 0), compound_name_arity(T, N, 0), R = N), error(SsuE, _), R = raised(SsuE)).
t_p052(R) :- catch((compound_name_arguments(f(a,b), N, As), R = N-As), error(SsuE, _), R = raised(SsuE)).
t_p053(R) :- catch((compound_name_arguments(T, foo, [x,Y,Y]), R = T-Y), error(SsuE, _), R = raised(SsuE)).
t_p054(R) :- catch((compound_name_arguments(T, foo, []), R = T), error(SsuE, _), R = raised(SsuE)).
t_p055(R) :- catch((p_zero(T), compound_name_arguments(T, N, As), R = N-As), error(SsuE, _), R = raised(SsuE)).
t_p056(R) :- catch((compound_name_arguments(a, N, As), R = N-As), error(SsuE, _), R = raised(SsuE)).
t_p057(R) :- catch((compound_name_arguments(T, foo, [a|_]), R = T), error(SsuE, _), R = raised(SsuE)).
t_p058(R) :- catch((compound_name_arguments(T, foo, bar), R = T), error(SsuE, _), R = raised(SsuE)).
t_p059(R) :- catch((compound_name_arguments(T, foo, _), R = T), error(SsuE, _), R = raised(SsuE)).
t_p060(R) :- catch((compound_name_arguments(T, 1, [a]), R = T), error(SsuE, _), R = raised(SsuE)).
t_p061(R) :- catch((compound_name_arguments(f(a,b), g, As), R = As), error(SsuE, _), R = raised(SsuE)).
t_p062(R) :- catch((compound_name_arguments(f(a,b), N, [X]), R = N-X), error(SsuE, _), R = raised(SsuE)).
t_p063(R) :- catch((compound_name_arguments([a,b], N, As), R = N-As), error(SsuE, _), R = raised(SsuE)).
t_p064(R) :- catch((compound_name_arguments(T, N, [a]), R = T-N), error(SsuE, _), R = raised(SsuE)).
t_p065(R) :- catch((compound_name_arguments(f(a,b), N, [a|T]), R = N-T), error(SsuE, _), R = raised(SsuE)).
t_p066(R) :- catch((compound_name_arguments(f(a,b), N, [x,y,z]), R = N), error(SsuE, _), R = raised(SsuE)).
t_p067(R) :- catch((compound_name_arguments(T, foo, [a,b|c]), R = T), error(SsuE, _), R = raised(SsuE)).
t_p068(R) :- catch((compound_name_arguments(T, foo, [a,b]), compound_name_arity(T, N, A), R = N/A), error(SsuE, _), R = raised(SsuE)).
t_p069(R) :- catch((compound_name_arguments("s", N, As), R = N-As), error(SsuE, _), R = raised(SsuE)).
t_p070(R) :- catch((compound_name_arguments(T, [], [a]), R = T), error(SsuE, _), R = raised(SsuE)).
t_p071(R) :- catch((( subsumes_term(f(_), f(a)) -> R = yes ; R = no )), error(SsuE, _), R = raised(SsuE)).
t_p072(R) :- catch((( subsumes_term(f(a), f(_)) -> R = yes ; R = no )), error(SsuE, _), R = raised(SsuE)).
t_p073(R) :- catch((( subsumes_term(f(X,X), f(a,b)) -> R = yes ; R = no )), error(SsuE, _), R = raised(SsuE)).
t_p074(R) :- catch((( subsumes_term(f(X,Y), f(Z,Z)) -> R = yes ; R = no )), error(SsuE, _), R = raised(SsuE)).
t_p075(R) :- catch((( subsumes_term(f(X,Y), f(Y,X)) -> R = yes ; R = no )), error(SsuE, _), R = raised(SsuE)).
t_p076(R) :- catch((( subsumes_term(X, X) -> R = yes ; R = no )), error(SsuE, _), R = raised(SsuE)).
t_p077(R) :- catch((( subsumes_term(f(X), f(g(X))) -> R = yes ; R = no )), error(SsuE, _), R = raised(SsuE)).
t_p078(R) :- catch((( subsumes_term(f(X,X), f(Y,Y)) -> R = yes ; R = no )), error(SsuE, _), R = raised(SsuE)).
t_p079(R) :- catch((subsumes_term(f(X), f(a)), ( var(X) -> R = unbound ; R = bound )), error(SsuE, _), R = raised(SsuE)).
t_p080(R) :- catch((subsumes_term(f(X), f(Y)), ( var(Y) -> R = unbound ; R = bound )), error(SsuE, _), R = raised(SsuE)).
t_p081(R) :- catch((( subsumes_term(1, 1.0) -> R = yes ; R = no )), error(SsuE, _), R = raised(SsuE)).
t_p082(R) :- catch((( subsumes_term(f(a), f(a)) -> R = yes ; R = no )), error(SsuE, _), R = raised(SsuE)).
t_p083(R) :- catch((( subsumes_term("a", "a") -> R = yes ; R = no )), error(SsuE, _), R = raised(SsuE)).
t_p084(R) :- catch((( subsumes_term(f(X,g(X)), f(a,g(a))) -> R = yes ; R = no )), error(SsuE, _), R = raised(SsuE)).
t_p085(R) :- catch((( subsumes_term(f(X,g(X)), f(a,g(b))) -> R = yes ; R = no )), error(SsuE, _), R = raised(SsuE)).
t_p086(R) :- catch((( subsumes_term([X|Y], [a,b,c]) -> R = Y ; R = no )), error(SsuE, _), R = raised(SsuE)).
t_p087(R) :- catch((( subsumes_term(f(X,Y), f(Y,Z)) -> R = yes ; R = no )), error(SsuE, _), R = raised(SsuE)).
t_p088(R) :- catch((p_cyc(C), ( subsumes_term(C, C) -> R = yes ; R = no )), error(SsuE, _), R = raised(SsuE)).
t_p089(R) :- catch((( subsumes_term(a, X) -> R = yes ; R = no )), error(SsuE, _), R = raised(SsuE)).
t_p090(R) :- catch((( subsumes_term(X, f(X)) -> R = yes ; R = no )), error(SsuE, _), R = raised(SsuE)).
t_p091(R) :- catch((( subsumes_term(f(_,_), f(Y,Y)) -> R = yes ; R = no )), error(SsuE, _), R = raised(SsuE)).
t_p092(R) :- catch((( subsumes_term(f(X,X), f(Y,_)) -> R = yes ; R = no )), error(SsuE, _), R = raised(SsuE)).
t_p093(R) :- catch(('$factorize_term'(f(a,b), T, S), R = T-S), error(SsuE, _), R = raised(SsuE)).
t_p094(R) :- catch((G = g(a), '$factorize_term'(f(G,G), T, S), R = T-S), error(SsuE, _), R = raised(SsuE)).
t_p095(R) :- catch((p_cyc(C), '$factorize_term'(C, T, S), R = T-S), error(SsuE, _), R = raised(SsuE)).
t_p096(R) :- catch(('$factorize_term'(X, T, S), R = X-T-S), error(SsuE, _), R = raised(SsuE)).
t_p097(R) :- catch((G = g(X), '$factorize_term'(f(G,G,X), T, S), R = T-S), error(SsuE, _), R = raised(SsuE)).
t_p098(R) :- catch((G = g(a), H = h(G), '$factorize_term'(f(H,H,G), T, S), length(S, N), R = N), error(SsuE, _), R = raised(SsuE)).
t_p099(R) :- catch(('$factorize_term'(a, T, S), R = T-S), error(SsuE, _), R = raised(SsuE)).
t_p100(R) :- catch(('$factorize_term'(f(X,Y,X), T, S), R = T-S-X-Y), error(SsuE, _), R = raised(SsuE)).
t_p101(R) :- catch(('$term_size'(a, _, S), R = S), error(SsuE, _), R = raised(SsuE)).
t_p102(R) :- catch(('$term_size'(1.5, _, S), R = S), error(SsuE, _), R = raised(SsuE)).
t_p103(R) :- catch(('$term_size'("abc", _, S), R = S), error(SsuE, _), R = raised(SsuE)).
t_p104(R) :- catch(('$term_size'("abcdefgh", _, S), R = S), error(SsuE, _), R = raised(SsuE)).
t_p105(R) :- catch((X is 2^64, '$term_size'(X, _, S), R = S), error(SsuE, _), R = raised(SsuE)).
t_p106(R) :- catch((X is 1 rdiv 3, '$term_size'(X, _, S), R = S), error(SsuE, _), R = raised(SsuE)).
t_p107(R) :- catch(('$term_size'(f(X,X), _, S), R = S), error(SsuE, _), R = raised(SsuE)).
t_p108(R) :- catch((string_codes(W, [97,256]), '$term_size'(W, _, S), R = S), error(SsuE, _), R = raised(SsuE)).
t_p109(R) :- catch(('$term_size'(f(a), 1, S), R = S), error(SsuE, _), R = raised(SsuE)).
t_p110(R) :- catch(('$term_size'(f(a), 2, S), R = S), error(SsuE, _), R = raised(SsuE)).
t_p111(R) :- catch(('$term_size'(f(a), 100, S), R = S), error(SsuE, _), R = raised(SsuE)).
t_p112(R) :- catch(('$term_size'(f(a), a, S), R = S), error(SsuE, _), R = raised(SsuE)).
t_p113(R) :- catch(('$term_size'(f(a), -1, S), R = S), error(SsuE, _), R = raised(SsuE)).
t_p114(R) :- catch((G = g(a), '$term_size'(f(G,G), _, S), R = S), error(SsuE, _), R = raised(SsuE)).
t_p115(R) :- catch(('$term_size'(_, _, S), R = S), error(SsuE, _), R = raised(SsuE)).
t_p116(R) :- catch(('$term_size'(f(_,_), _, S), R = S), error(SsuE, _), R = raised(SsuE)).
t_p117(R) :- catch((p_cyc(C), '$term_size'(C, _, S), R = S), error(SsuE, _), R = raised(SsuE)).
t_p118(R) :- catch(('$term_size'([a,b,c], _, S), R = S), error(SsuE, _), R = raised(SsuE)).
t_p119(R) :- catch(('$term_size'(f(1,2), _, S), R = S), error(SsuE, _), R = raised(SsuE)).
t_p120(R) :- catch(('$term_size'(f(a), _, 2), R = yes), error(SsuE, _), R = raised(SsuE)).
t_p121(R) :- catch(('$term_size'(f(a), _, 4), R = yes), error(SsuE, _), R = raised(SsuE)).
t_p122(R) :- catch((p_zero(T), '$term_size'(T, _, S), R = S), error(SsuE, _), R = raised(SsuE)).
t_p123(R) :- catch((X is 2^200, '$term_size'(X, _, S), R = S), error(SsuE, _), R = raised(SsuE)).
t_p124(R) :- catch((X is 2^63, '$term_size'(X, _, S), R = S), error(SsuE, _), R = raised(SsuE)).
t_p125(R) :- catch(('$term_size'(f(1.5,2.5), _, S), R = S), error(SsuE, _), R = raised(SsuE)).
t_p126(R) :- catch(('$term_size'(f(a), 0, S), R = S), error(SsuE, _), R = raised(SsuE)).
t_p127(R) :- catch((( is_most_general_term(a) -> R = yes ; R = no )), error(SsuE, _), R = raised(SsuE)).
t_p128(R) :- catch((( is_most_general_term([X,Y]) -> R = yes ; R = no )), error(SsuE, _), R = raised(SsuE)).
t_p129(R) :- catch((( is_most_general_term([X,X]) -> R = yes ; R = no )), error(SsuE, _), R = raised(SsuE)).
t_p130(R) :- catch((( is_most_general_term(f(X,Y)) -> R = yes ; R = no )), error(SsuE, _), R = raised(SsuE)).
t_p131(R) :- catch((( is_most_general_term(f(X,X)) -> R = yes ; R = no )), error(SsuE, _), R = raised(SsuE)).
t_p132(R) :- catch((( is_most_general_term(f(a)) -> R = yes ; R = no )), error(SsuE, _), R = raised(SsuE)).
t_p133(R) :- catch((( is_most_general_term([a|_]) -> R = yes ; R = no )), error(SsuE, _), R = raised(SsuE)).
t_p134(R) :- catch((( is_most_general_term(1) -> R = yes ; R = no )), error(SsuE, _), R = raised(SsuE)).
t_p135(R) :- catch((( is_most_general_term(_) -> R = yes ; R = no )), error(SsuE, _), R = raised(SsuE)).
t_p136(R) :- catch((( is_most_general_term([]) -> R = yes ; R = no )), error(SsuE, _), R = raised(SsuE)).
t_p137(R) :- catch((( is_most_general_term(f(X,g(Y))) -> R = yes ; R = no )), error(SsuE, _), R = raised(SsuE)).
t_p138(R) :- catch((( is_most_general_term("s") -> R = yes ; R = no )), error(SsuE, _), R = raised(SsuE)).
t_p139(R) :- catch((p_zero(T), ( is_most_general_term(T) -> R = yes ; R = no )), error(SsuE, _), R = raised(SsuE)).
t_p140(R) :- catch((( is_most_general_term([X|T]) -> R = yes ; R = no )), error(SsuE, _), R = raised(SsuE)).
t_p141(R) :- catch((( is_most_general_term([X,Y|T]) -> R = yes ; R = no )), error(SsuE, _), R = raised(SsuE)).
t_p142(R) :- catch((( is_most_general_term(f(X,Y,Z)) -> R = yes ; R = no )), error(SsuE, _), R = raised(SsuE)).
t_p143(R) :- catch((( is_most_general_term(f(X,Y,X)) -> R = yes ; R = no )), error(SsuE, _), R = raised(SsuE)).
t_p144(R) :- catch((X = 1, ( is_most_general_term(f(X,Y)) -> R = yes ; R = no )), error(SsuE, _), R = raised(SsuE)).
t_p145(R) :- catch((( is_most_general_term(f(X,Y)) -> true ; true ), term_variables(f(X,Y), L), length(L, N), R = N), error(SsuE, _), R = raised(SsuE)).
t_p146(R) :- catch((( is_most_general_term(f(X,X)) -> true ; true ), term_variables(f(X,X), L), length(L, N), R = N), error(SsuE, _), R = raised(SsuE)).
t_p147(R) :- catch((( is_most_general_term([X,Y]) -> true ; true ), X = Y, R = X-Y), error(SsuE, _), R = raised(SsuE)).
t_p148(R) :- catch((term_singletons(f(X,Y,X), L), R = L-Y), error(SsuE, _), R = raised(SsuE)).
t_p149(R) :- catch((term_singletons(f(a,b), L), R = L), error(SsuE, _), R = raised(SsuE)).
t_p150(R) :- catch((term_singletons(f(X,X), L), R = L), error(SsuE, _), R = raised(SsuE)).
t_p151(R) :- catch((term_singletons(f(X,Y,Z), L), R = L-X-Y-Z), error(SsuE, _), R = raised(SsuE)).
t_p152(R) :- catch((term_singletons(X, L), R = L-X), error(SsuE, _), R = raised(SsuE)).
t_p153(R) :- catch((p_cyc(C), term_singletons(C, L), R = L), error(SsuE, _), R = raised(SsuE)).
t_p154(R) :- catch((term_singletons(f(g(X),h(Y,X)), L), R = L-Y), error(SsuE, _), R = raised(SsuE)).
t_p155(R) :- catch((term_singletons(f(X,Y), [A]), R = A), error(SsuE, _), R = raised(SsuE)).
t_p156(R) :- catch((term_singletons(f(X,Y), [A,B]), R = A-B-X-Y), error(SsuE, _), R = raised(SsuE)).
t_p157(R) :- catch((term_singletons(a, L), R = L), error(SsuE, _), R = raised(SsuE)).
t_p158(R) :- catch((term_singletons(f(X,Y,X,Z,Z,W), L), R = L-Y-W), error(SsuE, _), R = raised(SsuE)).
t_p159(R) :- catch((G = g(X), term_singletons(f(G,G), L), R = L-X), error(SsuE, _), R = raised(SsuE)).
t_p160(R) :- catch((term_singletons(f(X,Y), a), R = yes), error(SsuE, _), R = raised(SsuE)).
t_p161(R) :- catch((term_singletons(f(X,Y), L), term_variables(f(X,Y), V), R = L-V), error(SsuE, _), R = raised(SsuE)).
t_p162(R) :- catch(('$term_multitons'(f(X,Y,X), L), R = L-X), error(SsuE, _), R = raised(SsuE)).
t_p163(R) :- catch(('$term_multitons'(f(a,b), L), R = L), error(SsuE, _), R = raised(SsuE)).
t_p164(R) :- catch(('$term_multitons'(f(X,X), L), R = L-X), error(SsuE, _), R = raised(SsuE)).
t_p165(R) :- catch(('$term_multitons'(f(X,Y,Z), L), R = L), error(SsuE, _), R = raised(SsuE)).
t_p166(R) :- catch((p_cyc(C), '$term_multitons'(C, L), R = L), error(SsuE, _), R = raised(SsuE)).
t_p167(R) :- catch(('$term_multitons'(f(g(X),h(Y,X),Y,Z), L), R = L-X-Y), error(SsuE, _), R = raised(SsuE)).
t_p168(R) :- catch(('$term_multitons'(f(X,Y,X), [A|T]), R = A-T-X), error(SsuE, _), R = raised(SsuE)).
t_p169(R) :- catch(('$term_multitons'(f(X,X,Y,Y), [A,B]), R = A-B-X-Y), error(SsuE, _), R = raised(SsuE)).
t_p170(R) :- catch(('$term_multitons'(f(X,X,Y,Y), [A,B,C]), R = A), error(SsuE, _), R = raised(SsuE)).
t_p171(R) :- catch((G = g(X), '$term_multitons'(f(G,G), L), R = L-X), error(SsuE, _), R = raised(SsuE)).
t_p172(R) :- catch(('$term_multitons'(f(X,X,X), L), R = L-X), error(SsuE, _), R = raised(SsuE)).
t_p173(R) :- catch(('$term_multitons'(f(X,Y,Y,X,Z), L), R = L-X-Y-Z), error(SsuE, _), R = raised(SsuE)).
t_p174(R) :- catch((arg(N, f(g(X,b), g(c,X)), g(A,d)), R = N-A-X), error(SsuE, _), R = raised(SsuE)).
t_p175(R) :- catch((( is_most_general_term([X,Y]) -> true ; true ), term_variables([X,Y], L), length(L, N), R = N), error(SsuE, _), R = raised(SsuE)).
t_p176(R) :- catch((term_singletons(f(X,Y,X), [A]), R = A-Y), error(SsuE, _), R = raised(SsuE)).
