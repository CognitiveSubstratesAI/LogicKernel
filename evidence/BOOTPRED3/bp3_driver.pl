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
:- initialization((fz_run('/home/shivaji1012/code/lk-dstack/evidence/BOOTPRED3/bp3_rows.pl', [t_bp3m01,t_bp3m02,t_bp3m03,t_bp3m04,t_bp3m05,t_bp3m06,t_bp3m07,t_bp3m08,t_bp3m09,t_bp3m10,t_bp3m11,t_bp3m12,t_bp3m13,t_bp3m14,t_bp3m15,t_bp3m16,t_bp3m17,t_bp3m18,t_bp3i01,t_bp3i02,t_bp3i03,t_bp3i04,t_bp3i05,t_bp3i06,t_bp3i07,t_bp3i08,t_bp3i09,t_bp3i10,t_bp3i11,t_bp3i12,t_bp3n01,t_bp3n02,t_bp3n03,t_bp3n04,t_bp3n05,t_bp3n06,t_bp3n07,t_bp3n08,t_bp3n09,t_bp3n10,t_bp3n11,t_bp3n12,t_bp3n13,t_bp3n14,t_bp3n15,t_bp3n16,t_bp3n17,t_bp3n18,t_bp3n19,t_bp3l01,t_bp3l02,t_bp3l03,t_bp3l04,t_bp3l05,t_bp3l06,t_bp3l07,t_bp3l08,t_bp3l09,t_bp3l10,t_bp3l11,t_bp3l12,t_bp3l13,t_bp3l14,t_bp3l15,t_bp3l16,t_bp3l17,t_bp3l18,t_bp3l19,t_bp3l20,t_bp3l21,t_bp3l22,t_bp3l23,t_bp3l24,t_bp3l25,t_bp3l26,t_bp3l27,t_bp3l28,t_bp3l29,t_bp3l30,t_bp3l31,t_bp3l32,t_bp3l33,t_bp3v01,t_bp3v02,t_bp3v03,t_bp3v04,t_bp3v05,t_bp3v06,t_bp3v07,t_bp3v08,t_bp3v09,t_bp3v10,t_bp3v11,t_bp3v12,t_bp3v13,t_bp3v14,t_bp3v15]), halt)).
