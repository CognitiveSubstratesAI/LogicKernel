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
:- initialization((fz_run('/home/shivaji1012/code/lk-ev1/evidence/EV1/ev1_rows.pl', [t_ev1p01,t_ev1p02,t_ev1p03,t_ev1p04,t_ev1p05,t_ev1p06,t_ev1p07,t_ev1p08,t_ev1p09,t_ev1p10,t_ev1p11,t_ev1p12,t_ev1p13,t_ev1p14,t_ev1p15,t_ev1p16,t_ev1p17,t_ev1p18,t_ev1p19,t_ev1o01,t_ev1o02,t_ev1o03,t_ev1o04,t_ev1o05,t_ev1o06,t_ev1o07,t_ev1o08,t_ev1o09,t_ev1o10,t_ev1o11,t_ev1u01,t_ev1u02,t_ev1u03,t_ev1u04,t_ev1u05,t_ev1u06,t_ev1u07,t_ev1u08,t_ev1u09,t_ev1u10,t_ev1u11,t_ev1u12,t_ev1u13,t_ev1u14,t_ev1u15,t_ev1u16,t_ev1u17,t_ev1v01,t_ev1v02,t_ev1v03,t_ev1v04,t_ev1v05,t_ev1v06,t_ev1v07,t_ev1v08,t_ev1v09,t_ev1v10,t_ev1v11,t_ev1v12,t_ev1e01,t_ev1e02,t_ev1e03,t_ev1e04,t_ev1e05,t_ev1e06,t_ev1e07,t_ev1e08,t_ev1e09,t_ev1e10,t_ev1e11,t_ev1e12,t_ev1r01,t_ev1r02,t_ev1r03,t_ev1r04,t_ev1r05,t_ev1r06,t_ev1r07,t_ev1r08,t_ev1g01]), halt)).
