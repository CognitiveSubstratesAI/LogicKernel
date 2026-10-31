
enc(T) :- enc(T, [], _).
enc(V, S0, S) :- var(V), !, ( vidx(S0, V, 0, I) -> S = S0 ; length(S0, I), append(S0, [V], S) ), format("V~w", [I]).
enc(T, S, S) :- T == [], !, write(nil).
enc(T, S, S) :- atom(T), !, atom_codes(T, Cs), format("a~w", [Cs]).
enc(T, S, S) :- string(T), !, string_codes(T, Cs), format("s~w", [Cs]).
enc(T, S, S) :- integer(T), !, format("i~w", [T]).
enc(T, S, S) :- rational(T, N, D), !, format("q~wr~w", [N, D]).
enc(T, S, S) :- float(T), !, format("f~w", [T]).
enc(T, S0, S) :- compound_name_arity(T, N, A),
    ( N == [] -> write('c[]') ; atom_codes(N, Cs), format("c~w", [Cs]) ),
    format("/~w(", [A]), encargs(1, A, T, S0, S), write(')').
encargs(I, A, _, S, S) :- I > A, !.
encargs(I, A, T, S0, S) :- arg(I, T, X), enc(X, S0, S1), ( I < A -> write(',') ; true ),
    I1 is I+1, encargs(I1, A, T, S1, S).
vidx([X|_], V, I, I) :- X == V, !.
vidx([_|Xs], V, I0, I) :- I1 is I0+1, vidx(Xs, V, I1, I).
fz_pred(N) :-
    format("~w", [N]), functor(G, N, 1),
    catch(findnsols(50, G, G, Gs), _, Gs = [exception]),
    forall(member(S, Gs), ( S == exception -> write(' exception') ; write(' '), enc(S) )), nl.
fz_run(File, Ns) :-
    catch(( consult(File), S = ok ), E, S = exc(E)),
    ( S == ok -> writeln(ok) ; S = exc(B), write('exc '), enc(B), nl ),
    forall(member(N, Ns), fz_pred(N)).
:- initialization((fz_run('/home/shivaji1012/code/lk-o1a/evidence/O1A/o1a_rows.pl', [t_f01,t_f02,t_f03,t_f04,t_f05,t_f06,t_f07,t_f08,t_f09,t_f10,t_f11,t_f12,t_f13,t_f14,t_f15,t_f16,t_f17,t_f18,t_f19,t_f20,t_f21,t_f22,t_f23,t_f24,t_f25,t_f26,t_f27,t_f28,t_f29,t_f30,t_f31,t_f32,t_f33,t_f34,t_f35,t_f36,t_f37,t_f38,t_f39,t_f40,t_f41,t_f42,t_f43,t_f44,t_f45,t_f46,t_f47,t_f48,t_f49,t_f50,t_f51,t_f52,t_f53,t_f54,t_f55,t_f56,t_f57,t_f58,t_f59,t_f60,t_f61,t_f62,t_f63,t_f64,t_f65,t_f66,t_f67,t_f68,t_f69,t_f70,t_f71,t_f72,t_f73,t_f74,t_e01,t_e02,t_e03,t_e04,t_e05,t_e06,t_e07,t_e08,t_e09,t_e10,t_e11,t_e12,t_e13,t_e14,t_e15,t_e16,t_e17,t_e18,t_e19,t_f75,t_f76,t_f77,t_f78,t_f79,t_f80,t_f81,t_f82,t_f83,t_f84,t_f85,t_e20,t_e21,t_f86,t_f87,t_f88,t_f89,t_f90,t_f91,t_f92,t_f93,t_f94,t_f95,t_f96,t_f97,t_f98,t_e22,t_e23,t_e24]), halt)).
