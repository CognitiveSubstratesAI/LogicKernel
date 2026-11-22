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
:- initialization((fz_run('/home/shivaji1012/code/lk-dictrec/evidence/DICT-REC/dictrec_rows.pl', [t_dr01,t_dr02,t_dr03,t_dr04,t_dr05,t_dr06,t_dr07,t_dr08,t_dr09,t_dr10,t_dr11,t_dr12,t_dr13,t_dr14,t_dr15,t_dr16,t_dr17,t_dr18,t_dr19,t_dr20,t_dr21,t_dr22,t_dr23,t_dr24,t_dr25,t_dr26,t_dr27,t_dr28,t_dr29,t_dr30,t_dr31,t_dr32,t_dr33,t_dr34,t_dr35,t_dr36,t_dr37,t_dr38,t_dr39,t_dr40,t_dr41,t_dr42,t_dr43,t_dr44,t_dr45,t_dr46,t_dr47,t_dr48,t_dr49,t_dr50,t_dr51,t_dr52,t_dr53,t_dr54,t_dr55,t_dr56,t_dr57,t_dr58,t_dr59,t_dr60,t_dr61,t_dr62,t_dr63,t_dr64,t_dr65,t_dr66,t_dr67,t_dr68,t_dr69,t_dr70,t_dr71,t_dr72,t_dr73,t_dr74,t_dr75,t_dr76,t_dr77,t_dr78,t_dr79,t_dr80,t_dr81,t_dr82,t_dr83,t_dr84,t_dr85,t_dr86,t_dr87,t_dr88,t_dr89,t_dr90,t_dr91,t_dr92,t_dr93,t_dr94,t_dr95,t_dr96,t_dr97,t_dr98,t_dr99,t_dr100,t_dr101,t_dr102,t_dr103,t_dr104,t_dr105,t_dr106,t_dr107,t_dr108,t_dr109,t_dr110,t_dr111,t_dr112,t_dr113,t_dr114,t_dr115,t_dr116,t_dr117,t_dr118,t_dr119,t_dr120,t_dr121,t_dr122,t_dr123,t_dr124,t_dr125,t_dr126,t_dr127,t_dr128,t_dr129,t_dr130,t_dr131]), halt)).
