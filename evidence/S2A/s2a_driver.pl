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
:- initialization((fz_run('/home/shivaji1012/code/lk-s2a/evidence/S2A/s2a_rows.pl', [t_s001,t_s002,t_s003,t_s004,t_s005,t_s006,t_s007,t_s008,t_s009,t_s010,t_s011,t_s012,t_s013,t_s014,t_s015,t_s016,t_s017,t_s018,t_s019,t_s020,t_s021,t_s022,t_s023,t_s024,t_s025,t_s026,t_s027,t_s028,t_s029,t_s030,t_s031,t_s032,t_s033,t_s034,t_s035,t_s036,t_s037,t_s038,t_s039,t_s040,t_s041,t_s042,t_s043,t_s044,t_s045,t_s046,t_s047,t_s048,t_s049,t_s050,t_s051,t_s052,t_s053,t_s054,t_s055,t_s056,t_s057,t_s058,t_s059,t_s060,t_s061,t_s062,t_s063,t_s064,t_s065,t_s066,t_s067,t_s068,t_s069,t_s070,t_s071,t_s072,t_s073,t_s074,t_s075,t_s076,t_s077,t_s078,t_s079,t_s080,t_s081,t_s082,t_s083,t_s084,t_s085,t_s086,t_s087,t_s088,t_s089,t_s090,t_s091,t_s092,t_s093,t_s094,t_s095,t_s096,t_s097,t_s098,t_s099,t_s100,t_s101,t_s102,t_s103,t_s104,t_s105,t_s106,t_s107,t_s108,t_s109,t_s110,t_s111,t_s112,t_s113,t_s114,t_s115,t_s116,t_s117,t_s118,t_s119,t_s120,t_s121,t_s122,t_s123,t_s124,t_s125,t_s126,t_s127,t_s128,t_s129,t_s130,t_s131,t_s132,t_s133,t_s134,t_s135,t_s136,t_s137]), halt)).
