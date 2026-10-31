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
:- initialization((fz_run('/home/shivaji1012/code/lk-mod5a/evidence/MOD5a/mx_rows.pl', [t_e01,t_e02,t_e03,t_e04,t_e05,t_e06,t_e07,t_e08,t_e09,t_e10,t_e11,t_e12,t_e13,t_e14,t_e15,t_e16,t_e17,t_e18,t_e19,t_e20,t_e21,t_e22,t_e23,t_e24,t_e25,t_u01,t_u02,t_u03,t_u04,t_u05,t_d01,t_d02,t_d03,t_d04,t_d05,t_d06,t_d07,t_d08,t_d09,t_d10,t_d11,t_d12,t_d18,t_d19,t_d13,t_i01,t_i02,t_i03,t_i04,t_i05,t_i06,t_i07,t_i08,t_i09,t_i10,t_i11,t_i12,t_i13,t_u06,t_i14,t_i15,t_i16,t_i17,t_w01,t_w02,t_w03,t_w04,t_w05,t_w06,t_w07,t_w08,t_w09,t_d14,t_d15,t_d16,t_d20,t_d17]), halt)).
