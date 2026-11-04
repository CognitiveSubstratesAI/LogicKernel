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
:- initialization((fz_run('/home/shivaji1012/code/lk-lb5/evidence/LB5/lb5_rows.pl', [t_lb001,t_lb002,t_lb003,t_lb004,t_lb005,t_lb006,t_lb007,t_lb008,t_lb009,t_lb010,t_lb011,t_lb012,t_lb013,t_lb014,t_lb015,t_lb016,t_lb017,t_lb018,t_lb019,t_lb020,t_lb021,t_lb022,t_lb023,t_lb024,t_lb025,t_lb026,t_lb027,t_lb028,t_lb029,t_lb030,t_lb031,t_lb032,t_lb033,t_lb034,t_lb035,t_lb036,t_lb037,t_lb038,t_lb039,t_lb040,t_lb041,t_lb042,t_lb043,t_lb044,t_lb045,t_lb046,t_lb047,t_lb048,t_lb049,t_lb050,t_lb051,t_lb052,t_lb053,t_lb054,t_lb055,t_lb056,t_lb057,t_lb058,t_lb059,t_lb060,t_lb061,t_lb062,t_lb063,t_lb064,t_lb065,t_lb066,t_lb067,t_lb068,t_lb069,t_lb070,t_lb071,t_lb072,t_lb073,t_lb074,t_lb075,t_lb076,t_lb077,t_lb078,t_lb079,t_lb080,t_lb081,t_lb082,t_lb083,t_lb084,t_lb085,t_lb086,t_lb087,t_lb088,t_lb089,t_lb090,t_lb091,t_lb092,t_lb093,t_lb094,t_lb095,t_lb096,t_lb097,t_lb098,t_lb099,t_lb100,t_lb101,t_lb102,t_lb103,t_lb104,t_lb105,t_lb106,t_lb107,t_lb108,t_lb109,t_lb110]), halt)).
