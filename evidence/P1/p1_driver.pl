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
:- initialization((fz_run('/home/shivaji1012/code/lk-p1/evidence/P1/p1_rows.pl', [t_p001,t_p002,t_p003,t_p004,t_p005,t_p006,t_p007,t_p008,t_p009,t_p010,t_p011,t_p012,t_p013,t_p014,t_p015,t_p016,t_p017,t_p018,t_p019,t_p020,t_p021,t_p022,t_p023,t_p024,t_p025,t_p026,t_p027,t_p028,t_p029,t_p030,t_p031,t_p032,t_p033,t_p034,t_p035,t_p036,t_p037,t_p038,t_p039,t_p040,t_p041,t_p042,t_p043,t_p044,t_p045,t_p046,t_p047,t_p048,t_p049,t_p050,t_p051,t_p052,t_p053,t_p054,t_p055,t_p056,t_p057,t_p058,t_p059,t_p060,t_p061,t_p062,t_p063,t_p064,t_p065,t_p066,t_p067,t_p068,t_p069,t_p070,t_p071,t_p072,t_p073,t_p074,t_p075,t_p076,t_p077,t_p078,t_p079,t_p080,t_p081,t_p082,t_p083,t_p084,t_p085,t_p086,t_p087,t_p088,t_p089,t_p090,t_p091,t_p092,t_p093,t_p094,t_p095,t_p096,t_p097,t_p098,t_p099,t_p100,t_p101,t_p102,t_p103,t_p104,t_p105,t_p106,t_p107,t_p108,t_p109,t_p110,t_p111,t_p112,t_p113,t_p114,t_p115,t_p116,t_p117,t_p118,t_p119,t_p120,t_p121,t_p122,t_p123,t_p124,t_p125,t_p126,t_p127,t_p128,t_p129,t_p130,t_p131,t_p132,t_p133,t_p134,t_p135,t_p136,t_p137,t_p138,t_p139,t_p140,t_p141,t_p142,t_p143,t_p144,t_p145,t_p146,t_p147,t_p148,t_p149,t_p150,t_p151,t_p152,t_p153,t_p154,t_p155,t_p156,t_p157,t_p158,t_p159,t_p160,t_p161,t_p162,t_p163,t_p164,t_p165,t_p166,t_p167,t_p168,t_p169,t_p170,t_p171,t_p172,t_p173]), halt)).
