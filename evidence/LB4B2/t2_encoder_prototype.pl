% T2 encoder: ONE text for a clause, variables numbered by first occurrence (so equal text == =@=)
lb4b2_enc(T, Cs) :- lb4b2_enc(T, [], _, Cs, []).
lb4b2_enc(V, S0, S, Cs, T) :- var(V), !,
    ( lb4b2_vidx(S0, V, 0, I) -> S = S0 ; lb4b2_len(S0, 0, I), lb4b2_app(S0, [V], S) ),
    number_codes(I, IC), Cs = [0'V|C1], lb4b2_app(IC, T, C1).
lb4b2_enc(X, S, S, Cs, T) :- X == [], !, lb4b2_app("n", T, Cs).
lb4b2_enc(X, S, S, Cs, T) :- atom(X), !, atom_codes(X, AC), lb4b2_codes(0'a, AC, Cs, T).
lb4b2_enc(X, S, S, Cs, T) :- string(X), !, string_codes(X, SC), lb4b2_codes(0's, SC, Cs, T).
lb4b2_enc(X, S, S, Cs, T) :- number(X), !, number_codes(X, NC), Cs = [0'#|C1], lb4b2_app(NC, T, C1).
lb4b2_enc(X, S0, S, Cs, T) :- compound_name_arity(X, N, A),
    ( N == [] -> NC = [] ; atom_codes(N, NC) ), lb4b2_codes(0'c, NC, Cs, C1),
    number_codes(A, AC), C1 = [0'/|C2], lb4b2_app(AC, [0'(|C3], C2), lb4b2_args(1, A, X, S0, S, C3, [0')|T]).
lb4b2_args(I, A, _, S, S, T, T) :- I > A, !.
lb4b2_args(I, A, X, S0, S, Cs, T) :- arg(I, X, Y), lb4b2_enc(Y, S0, S1, Cs, C1),
    ( I < A -> C1 = [0',|C2] ; C2 = C1 ), I1 is I+1, lb4b2_args(I1, A, X, S1, S, C2, T).
lb4b2_codes(Tag, Codes, [Tag, 0'[|Cs], T) :- lb4b2_numlist(Codes, Cs, [0']|T]).
lb4b2_numlist([], T, T).
lb4b2_numlist([C|Cs], Out, T) :- number_codes(C, NC), lb4b2_app(NC, R, Out),
    ( Cs == [] -> R = R1 ; R = [0',|R1] ), lb4b2_numlist(Cs, R1, T).
lb4b2_vidx([X|_], V, I, I) :- X == V, !.
lb4b2_vidx([_|Xs], V, I0, I) :- I1 is I0+1, lb4b2_vidx(Xs, V, I1, I).
lb4b2_len([], N, N).
lb4b2_len([_|T], N0, N) :- N1 is N0+1, lb4b2_len(T, N1, N).
lb4b2_app([], L, L).
lb4b2_app([H|T], L, [H|R]) :- lb4b2_app(T, L, R).
lb4b2_member(X, [X|_]).
lb4b2_member(X, [_|T]) :- lb4b2_member(X, T).
% one line per clause of a Prolog predicate DEFINED in a module of Ms, predicates sorted by Name/Arity
lb4b2_t2_line(Ms, Line) :-
    lb4b2_member(M, Ms),
    findall(N/A, ( current_predicate(_, M:H), \+ predicate_property(M:H, imported_from(_)),
                   \+ predicate_property(M:H, foreign), functor(H, N, A) ), PIs0),
    sort(PIs0, PIs), lb4b2_member(N/A, PIs), functor(H, N, A),
    clause(M:H, B),
    lb4b2_enc((H :- B), Cs), atom_codes(M, MC), atom_codes(N, NC),
    lb4b2_codes(0'm, MC, L0, [0' |L1]), lb4b2_codes(0'p, NC, L1, [0' |L2]), number_codes(A, AC),
    lb4b2_app(AC, [0' |Cs], L2), string_codes(Line, L0).
