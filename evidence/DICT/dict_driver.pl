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
:- initialization((fz_run('/home/shivaji1012/code/lk-dict/evidence/DICT/dict_rows.pl', [t_dp01,t_dp02,t_dp03,t_dp04,t_dp05,t_dp06,t_dp07,t_dp08,t_dp09,t_dp10,t_dp11,t_dp12,t_dp13,t_dp14,t_dp15,t_dp16,t_dp17,t_dp18,t_dp19,t_dp20,t_dp21,t_dp22,t_dp23,t_dp24,t_dp25,t_dp26,t_dp27,t_dp28,t_dp29,t_dp30,t_dp31,t_dp32,t_dp33,t_dp34,t_dp35,t_dp36,t_dp37,t_dp38,t_dp39,t_dp40,t_dp41,t_dp42,t_dp43,t_dp44,t_dp45,t_dp46,t_dp47,t_dp48,t_dp49,t_dp50,t_dp51,t_dp52,t_dp53,t_dp54,t_dp55,t_dp56,t_dp57,t_dp58,t_dp59,t_dp60,t_dp61,t_dp62,t_dp63,t_dp64,t_dp65,t_dp66,t_dp67,t_dp68,t_dp69,t_dp70,t_dp71,t_dp72,t_dp73,t_dp74,t_dp75,t_dp76,t_dp77,t_dp78,t_dp79,t_dp80,t_dp81,t_dp82,t_dp83,t_dp84,t_dp85,t_dp86,t_dp87,t_dp88,t_dp89,t_dp90,t_dp91,t_dp92,t_dp93,t_dp94,t_dp95,t_dp96,t_dp97,t_dp98,t_dp99,t_dp100,t_dp101,t_dp102,t_dp103,t_dp104,t_dp105,t_dp106,t_dp107,t_dp108,t_dp109,t_dp110,t_dp111,t_dp112,t_dp113,t_dp114,t_dp115,t_dp116,t_dp117,t_dp118,t_dp119,t_dp120,t_dp121,t_dp122,t_dp123,t_dp124,t_dp125,t_dp126,t_dp127,t_dp128,t_dp129,t_dp130,t_dp131,t_dp132,t_dp133,t_dp134,t_dp135,t_dp136,t_dp137,t_dp138,t_dp139,t_dp140,t_dp141,t_dp142,t_dp143,t_dp144,t_dp145,t_dp146,t_dp147,t_dp148,t_dp149,t_dp150,t_dp151,t_dp152,t_dp153,t_dp154,t_dp155,t_dp156,t_dp157,t_dp158,t_dp159,t_dp160,t_dp161,t_dp162,t_dp163,t_dp164]), halt)).
