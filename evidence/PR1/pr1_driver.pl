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
:- initialization((fz_run('/home/shivaji1012/code/lk-pr1/evidence/PR1/pr1_rows.pl', [t_pr01,t_pr02,t_pr03,t_pr04,t_pr05,t_pr06,t_pr07,t_pr08,t_pr09,t_pr10,t_pr11,t_pr12,t_pr13,t_pr14,t_pr15,t_pr16,t_pr17,t_pr18,t_pr19,t_pr20,t_pr21,t_pr22,t_pr23,t_pr24,t_pr25,t_pr26,t_pr27,t_pr28,t_pr29,t_pr30,t_pr31,t_pr32,t_pr33,t_pr34,t_pr35,t_pr36,t_pr37,t_pr38,t_pr39,t_pr40,t_pr41,t_pr42,t_pr43,t_pr44,t_pr45,t_pr46,t_pr47,t_pr48,t_pr49,t_pr50,t_pr51,t_pr52,t_pr53,t_pr54,t_pr55,t_pr56,t_pr57,t_pr58,t_pr59,t_pr60,t_pr61,t_pr62,t_pr63,t_pr64,t_pr65,t_pr66,t_pr67,t_pr68,t_pr69,t_pr70,t_pr71,t_pr72,t_pr73,t_pr74,t_pr75,t_pr76,t_pr77,t_pr78,t_pr79,t_pr80,t_pr81,t_pr82,t_pr83,t_pr84,t_pr85,t_pr86,t_pr87,t_pr88,t_pr89,t_pr90,t_pr91,t_pr92,t_pr93,t_pr94,t_pr95,t_pr96,t_pr97,t_pr98,t_pr99,t_pr100,t_pr101,t_pr102,t_pr103,t_pr104,t_pr105,t_pr106,t_pr107,t_pr108,t_pr109,t_pr110,t_pr111,t_pr112,t_pr113,t_pr114,t_pr115,t_pr116,t_pr117,t_pr118,t_pr119,t_pr120,t_pr121,t_pr122,t_pr123,t_pr124,t_pr125,t_pr126,t_pr127]), halt)).
