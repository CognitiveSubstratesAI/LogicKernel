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
:- initialization((fz_run('/home/shivaji1012/code/lk-setarg/evidence/SETARG/setarg_rows.pl', [t_sa01,t_sa02,t_sa03,t_sa04,t_sa05,t_sa06,t_sa07,t_sa08,t_sa09,t_sa10,t_sa11,t_sa12,t_sa13,t_sa14,t_sa15,t_sa16,t_sa17,t_sa18,t_sa19,t_sa20,t_sa21,t_sa22,t_sa23,t_sa24,t_sa25,t_sa26,t_sa27,t_sa28,t_sa29,t_sa30,t_sa31,t_sa32,t_sa33,t_sa34,t_sa35,t_sa36,t_sa37,t_sa38,t_sa39,t_sa40,t_sa41,t_sa42,t_sa43,t_sa44,t_sa45,t_sa46,t_sa47,t_sa48,t_sa49,t_sa50,t_sa51,t_sa52,t_sa53,t_sa54,t_sa55,t_sa56,t_sa57,t_sa58,t_sa59,t_sa60,t_sa61,t_sa62,t_sa63,t_sa64,t_sa65,t_sa66,t_sa67,t_sa68,t_sa69,t_sa70,t_sa71,t_sa72,t_sa73,t_sa74,t_sa75,t_sa76,t_sa77,t_sa78,t_sa79,t_sa80,t_sa81,t_sa82,t_sa83,t_sa84,t_sa85,t_sa86,t_sa87,t_sa88,t_sa89,t_sa90,t_sa91,t_sa92,t_sa93,t_sa94]), halt)).
