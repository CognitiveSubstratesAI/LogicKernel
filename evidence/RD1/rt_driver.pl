enc(T) :- enc(T, [], _).
enc(V, S0, S) :- var(V), !, ( vidx(S0, V, 0, I) -> S = S0 ; length(S0, I), append(S0, [V], S) ), format("V~w", [I]).
enc(T, S, S) :- blob(T, stream), !, write(stream).
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
:- initialization((fz_run('/home/shivaji1012/code/lk-rd1/evidence/RD1/rt_rows.pl', [t_rt01,t_rt02,t_rt03,t_rt04,t_rt05,t_rt06,t_rt07,t_rt08,t_rt09,t_rt10,t_rt11,t_rt12,t_rt13,t_rt14,t_rt15,t_rt16,t_rt17,t_rt18,t_rt19,t_rt20,t_rt21,t_rt22,t_rt23,t_rt24,t_rt25,t_rt26,t_rt30,t_rt31,t_rt32,t_rt33,t_rt34,t_rt35,t_rt36,t_rt37,t_rt38,t_rt39,t_rt40,t_rt41,t_rt42,t_rt50,t_rt51,t_rt52,t_rt53,t_rt54,t_rt55,t_rt56,t_rt57,t_rt58,t_rt59,t_rt60,t_rt61,t_rt62,t_rt63,t_rt64,t_rt65,t_rt66,t_rt67,t_rt68,t_rt70,t_rt71,t_rt72,t_rt73,t_rt74,t_rt75,t_rt76,t_rt77,t_rt80,t_rt81,t_rt82,t_rt83,t_rt84,t_rt85,t_rt86,t_rt100,t_rt101,t_rt102,t_rt103,t_rt104,t_rt105,t_rt106,t_rt107,t_rt108,t_rt109,t_rt110,t_rt111,t_rt112,t_rt113,t_rt114,t_rt115,t_rt116,t_rt117,t_rt118,t_rt130,t_rt131,t_rt132,t_rt133,t_rt134,t_rt135,t_rt136,t_rt137,t_rt138,t_rt139,t_rt140,t_rt141,t_rt142,t_rt143,t_rt144,t_rt150,t_rt151,t_rt152,t_rt153,t_rt154,t_rt155,t_rt156,t_rt157,t_rt158,t_rt159,t_rt160,t_rt161,t_rt162,t_rt163,t_rt164,t_rt165,t_rt166,t_rt167,t_rt168,t_rt169,t_rt170,t_rt171,t_rt172,t_rt173,t_rt174,t_rt175,t_rt177,t_rt178,t_rt179,t_rt180,t_rt181,t_rt182,t_rt183,t_rt185,t_rt186,t_rt187,t_rt188,t_rt189,t_rt190,t_rt191,t_rt192,t_rt193,t_rt194,t_rt195,t_rt196,t_rt197,t_rt198,t_rt199,t_rt200,t_rt201,t_rt202,t_rt203,t_rt204,t_rt205,t_rt206,t_rt207,t_rt208,t_rt209,t_rt210,t_rt211,t_rt212,t_rt213,t_rt214,t_rt215,t_rt216,t_rt217,t_rt218,t_rt219,t_rt303,t_rt305,t_rt306,t_rt307,t_rt308,t_rt309,t_rt310,t_rt311,t_rt312,t_rt313,t_rt314,t_rt315,t_rt316,t_rt317,t_rt318,t_rt319,t_rt87,t_rt88,t_rt89,t_rt120,t_rt121,t_rt122,t_rt123,t_rt124,t_rt176,t_rt184,t_rt300,t_rt301,t_rt302,t_rt304,t_rt320,t_rt321]), halt)).
