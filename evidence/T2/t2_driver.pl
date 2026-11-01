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
:- initialization((fz_run('/home/shivaji1012/code/lk-t2/evidence/T2/t2_rows.pl', [st001,st002,st003,st004,st005,st006,st007,st008,st009,st010,st011,st012,st013,st014,st015,st016,st017,st018,st019,st020,st021,st022,st023,st024,st025,st026,st027,st028,st029,st030,st031,st032,st033,st034,st035,st036,st037,st038,st039,st040,st041,st042,st043,st044,st045,st046,st047,st048,st049,st050,st051,st052,st053,st054,st055,st056,st057,st058,st059,st060,st061,st062,st063,st064,st065,st066,st067,st068,st069,st070,st071,st072,st073,st074,st075,st076,st077,st078,st079,st080,st081,st082,st083,st084,st085,st086,st087,st088,st089,st090,st091,st092,st093,st094,st095,st096,st097,st098,st099,st100,st101,st102,st103,st104,st105,st106,st107,st108,st109,st110,st111,st112,st113,st114,st115,st116,st117,st118,st119,st120,st121,st122,st123,st124,st125,st126,st127,st128,st129,st130,st131,st132,st133,st134,st135,st136,st137,st138,st139,st140,st141,st142,st143,st144,st145,st146,st147,st148,st149,st150,st151,st152,st153,st154,st155,st156,st157,st158,st159,st160,st161,st162,st163,st164,st165,st166,st167,st168,st169,st170,st171,st172,st173,st174,st175,st176,st177,st178,st179,st180,st181,st182,st183,st184,st185,st186,st187,st188,st189,st190,st191,st192,st193,st194,st195,st196,st197,st198,st199,st200,st201,st202,st203,st204,st205,st206,st207,st208]), halt)).
