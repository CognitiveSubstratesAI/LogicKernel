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
:- initialization((fz_run('/home/shivaji1012/code/lk-mod3b/evidence/MOD3b/mod3b_rows.pl', [t_a01,t_a02,t_a03,t_a04,t_a05,t_a06,t_a07,t_a08,t_a09,t_a10,t_a11,t_a12,t_a13,t_a14,t_a15,t_a16,t_a17,t_a18,t_a19,t_a20,t_a21,t_a22,t_a23,t_a24,t_a25,t_a26,t_a27,t_a28,t_a29,t_a30,t_a31,t_a32,t_a33,t_a34,t_a35,t_a36,t_a37,t_a38,t_a39,t_a40,t_a41,t_a42,t_a43,t_a44,t_a45,t_a46,t_a47,t_a48,t_a49,t_a50,t_a51,t_a52,t_a53,t_a54,t_a55,t_a56,t_a57,t_a58,t_a59,t_a60,t_a61,t_a62,t_a63,t_a64,t_a65,t_a66,t_a67,t_a68,t_a69,t_a70,t_a71,t_a72,t_a73,t_a74,t_a75]), halt)).
