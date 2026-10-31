enc(T) :- enc(T, [], _).
enc(V, S0, S) :- var(V), !, ( vidx(S0, V, 0, I) -> S = S0 ; length(S0, I), append(S0, [V], S) ), format("V~w", [I]).
enc(T, S, S) :- T == [], !, write(nil).
enc(T, S, S) :- blob(T, Ty), Ty \== text, !, ( Ty == record -> write(recref) ; Ty == clause -> write(clref) ; write(blob) ).
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
:- initialization((fz_run('/home/shivaji1012/code/lk-d2/evidence/D2/d2_rows.pl', [t_r01,t_r02,t_r03,t_r04,t_r05,t_r06,t_r07,t_r08,t_r09,t_r10,t_r11,t_r12,t_r13,t_r14,t_r15,t_r16,t_r17,t_r18,t_r19,t_r20,t_r21,t_r22,t_r23,t_r24,t_r25,t_r26,t_r27,t_r28,t_r29,t_r30,t_r31,t_r32,t_r33,t_r34,t_r35,t_r36,t_r37,t_r38,t_r39,t_r40,t_r41,t_r42,t_r43,t_r44,t_r45,t_r46,t_r47,t_r48,t_r49,t_r50,t_r51,t_r52,t_r53,t_r54,t_r55,t_r56,t_r57,t_r58,t_r59,t_r60,t_r61,t_r62,t_r63,t_r64,t_r65,t_r66,t_r67,t_r68,t_r69,t_r70,t_r71,t_r72,t_r73,t_r74,t_r75,t_r76,t_r77,t_r78,t_r79,t_r80,t_r81,t_r82,t_r83,t_r84,t_r85,t_r86,t_r87,t_r88,t_r89,t_r90,t_r91,t_r92,t_r93,t_r94,t_r95,t_r96,t_r97,t_r98,t_r99,t_r100,t_r101]), halt)).
