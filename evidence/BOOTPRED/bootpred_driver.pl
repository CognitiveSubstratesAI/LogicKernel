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
:- initialization((fz_run('/home/shivaji1012/code/lk-bootpred/evidence/BOOTPRED/bootpred_rows.pl', [t_bp01,t_bp02,t_bp03,t_bp04,t_bp05,t_bp06,t_bp07,t_bp08,t_bp09,t_bp10,t_bp11,t_bp12,t_bp13,t_bp14,t_bp15,t_bp16,t_bp17,t_bp18,t_bp19,t_bp20,t_bp21,t_bp22,t_bp23,t_bp24,t_bp25,t_bp26,t_bp27,t_bp28,t_bp29,t_bp30,t_bp31,t_bp32,t_bp33,t_bp34,t_bp35,t_bp36,t_bp37,t_bp38,t_bp39,t_bp40,t_bp41,t_bp42,t_bp43,t_bp44,t_bp45,t_bp46,t_bp47,t_bp48,t_bp49,t_bp50,t_bp51,t_bp52,t_bp53,t_bp54,t_bp55,t_bp56,t_bp57,t_bp58,t_bp59,t_bp60,t_bp61,t_bp62,t_bp63,t_bp64,t_bp65,t_bp66,t_bp67,t_bp68,t_bp69,t_bp70,t_bp71,t_bp72,t_bp73,t_bp74,t_bp75,t_bp76,t_bp77,t_bp78,t_bp79,t_bp80,t_bp81,t_bp82,t_bp83,t_bp84,t_bp85,t_bp86,t_bp87,t_bp88,t_bp89,t_bp90,t_bp91,t_bp92,t_bp93,t_bp94,t_bp95,t_bp96,t_bp97,t_bp98,t_bp99,t_bp100,t_bp101,t_bp102,t_bp103,t_bp104,t_bp105,t_bp106,t_bp107,t_bp108,t_bp109,t_bp110,t_bp111,t_bp112,t_bp113,t_bp114,t_bp115,t_bp116,t_bp117,t_bp118,t_bp119]), halt)).
