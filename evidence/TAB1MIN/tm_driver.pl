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
:- initialization((fz_run('/home/shivaji1012/code/lk-tab1/evidence/TAB1MIN/tm_rows.pl', [t_tmt01,t_tmt02,t_tmt03,t_tmt04,t_tmt05,t_tmt06,t_tmt07,t_tmt08,t_tmt09,t_tmt10,t_tmt11,t_tmt12,t_tmt13,t_tmt14,t_tmt15,t_tmt16,t_tmt17,t_tmt18,t_tmt19,t_tmt20,t_tmt21,t_tmt22,t_tma01,t_tma02,t_tma03,t_tma04,t_tma05,t_tma06,t_tma07,t_tma08,t_tma09,t_tma10,t_tma11,t_tma12,t_tma13,t_tma14,t_tma15,t_tma16,t_tma17,t_tma18,t_tma19,t_tma20,t_tma21,t_tma22,t_tma23,t_tmw01,t_tmw02,t_tmw03,t_tmw04,t_tmw05,t_tmw06,t_tmw07,t_tmw08,t_tmw09,t_tmw10,t_tmw11,t_tmw12,t_tmw13,t_tmc01,t_tmc02,t_tmc03,t_tmc04,t_tmc05,t_tmc06]), halt)).
