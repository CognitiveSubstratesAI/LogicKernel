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
:- initialization((fz_run('/home/shivaji1012/code/lk-dict/evidence/RDDICT/rdd_rows.pl', [t_rd01,t_rd02,t_rd03,t_rd04,t_rd05,t_rd06,t_rd07,t_rd08,t_rd09,t_rd10,t_rd11,t_rd12,t_rd13,t_rd14,t_rd15,t_rd16,t_rd17,t_rd18,t_rd19,t_rd20,t_rd21,t_rd22,t_rd23,t_rd24,t_rd25,t_rd26,t_rd27,t_rd28,t_rd29,t_rd30,t_rd31,t_rd32,t_rd33,t_rd34,t_rd35,t_rd36,t_rd37,t_rd38,t_rd39,t_rd40,t_rd41,t_rd42,t_rd43,t_rd44,t_rd45,t_rd46,t_rd47,t_rd48,t_rd49,t_rd50,t_rd51,t_rd52,t_rd53,t_rd54,t_rd55,t_rd56,t_rd57,t_rd58,t_rd59,t_rd60,t_rd61,t_rd62,t_rd63,t_rd64,t_rd65,t_rd66,t_rd67,t_rd68,t_rd69,t_rd70,t_rd71,t_rd72,t_rd73,t_rd74,t_rd75,t_rd76,t_rd77,t_rd78,t_rd79,t_rd80,t_rd81,t_rd82,t_rd83,t_rd84,t_rd85,t_rd86,t_rd87,t_rd88,t_rd89,t_rd90,t_rd91,t_rd92,t_rd93,t_rd94,t_rd95,t_rd96,t_rd97,t_rd98,t_rd99,t_rd100,t_rd101,t_rd102,t_rd103,t_rd104,t_rd105,t_rd106,t_rd107,t_rd108,t_rd109,t_rd110,t_rd111,t_rd112,t_rd113,t_rd114,t_rd115,t_rd116,t_rd117,t_rd118,t_rd119,t_rd120,t_rd121,t_rd122,t_rd123,t_rd124,t_rd125,t_rd126]), halt)).
