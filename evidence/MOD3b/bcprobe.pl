:- initialization(main, main).

hc_render(I, Out) :-
    I =.. [N|As],
    (   As == [] -> Out = N
    ;   maplist(hc_op(N), As, Ts), atomic_list_concat(Ts, ',', J),
        format(atom(Out), "~w(~w)", [N, J])
    ).
hc_op(N, X, S) :- memberchk(N, [h_void_n, h_var, h_firstvar, h_list_ff]), !, format(string(S), "~w", [X]).
hc_op(_, X, S) :- atom(X), !, atom_codes(X, C), format(string(S), "a:~w", [C]).
hc_op(_, X, S) :- integer(X), !, format(string(S), "i:~d", [X]).
hc_op(_, X, S) :- rational(X, P, Q), !, format(string(S), "q:~d/~d", [P, Q]).
hc_op(_, X, S) :- float(X), !, format(string(S), "f:~h", [X]).
hc_op(_, X, S) :- string(X), !, string_codes(X, C), format(string(S), "s:~w", [C]).
hc_op(_, F/A, S) :- atom(F), integer(A), !, atom_codes(F, C), format(string(S), "F:~w/~d", [C, A]).
hc_op(_, X, S) :- format(string(S), "?:~q", [X]).

:- use_module(library(vm)).
bc_show(Ref) :-
    clause_vm(Ref, VM), vmi_labels(VM, L),
    forall(member(E, L), ( bc_elem(E, Out), writeln(Out) )).
bc_elem(label(L), Out) :- !, format(atom(Out), "~w:", [L]).
bc_elem(vmi(I, _), Out) :-
    I =.. [N|As],
    (   As == [] -> Out = N
    ;   '$vmi_property'(N, argv(Ts)),
        maplist(bc_op(N), Ts, As, Ss), atomic_list_concat(Ss, ',', J),
        format(atom(Out), "~w(~w)", [N, J])
    ).
bc_op(_, var, X, S) :- !, format(string(S), "~w", [X]).
bc_op(_, fvar, X, S) :- !, format(string(S), "~w", [X]).
bc_op(_, chp, X, S) :- !, format(string(S), "~w", [X]).
bc_op(_, jump, X, S) :- !, format(string(S), "~w", [X]).
bc_op(h_void_n, integer, X, S) :- !, format(string(S), "~w", [X]).
bc_op(c_var_n, integer, X, S) :- !, format(string(S), "~w", [X]).
bc_op(_, lproc, F/A, S) :- !, atom_codes(F, C), format(string(S), "P:~w/~d", [C, A]).
bc_op(_, module, M, S) :- var(M), !, S = "M:0".
bc_op(_, module, M, S) :- !, atom_codes(M, C), format(string(S), "M:~w", [C]).
bc_op(_, proc, M:F/A, S) :- !, atom_codes(M, MC), atom_codes(F, C), format(string(S), "P:~w:~w/~d", [MC, C, A]).
bc_op(N, _, X, S) :- hc_op(N, X, S).
bc_case_show(Cl) :- assertz(Cl, Ref), bc_show(Ref).
% clause/2 of the clause as swipl decompiles it, against the kernel's decompiled clause Ours
bc_decomp(Cl, Ours) :-
    assertz(Cl, Ref), clause(H, B, Ref),
    (   (H :- B) =@= Ours -> writeln(same)
    ;   writeln(differs), write_canonical((H :- B)), nl
    ).
% the I-th clause of a CONSULTED program, tied to the kernel's clause by =@= first
bc_prog_show(Cl, I) :-
    ( Cl = (H :- _) -> true ; H = Cl ),
    functor(H, N, A), functor(G, N, A), nth_clause(G, I, Ref), clause(FH, FB, Ref),
    ( FB == true -> FC = FH ; FC = (FH :- FB) ),
    ( FC =@= Cl -> writeln('@@tie ok') ; writeln('@@tie DIFFERS') ),
    bc_show(Ref).
main :- forall(member(G, [bc_case_show((pa1 :- @(q(1), m2))),bc_case_show((pa2 :- @(q(1), m2), r)),bc_case_show((pa3 :- @(m:q(1), m2))),bc_case_show((pa4(M) :- @(q(1), M))),bc_case_show((pa5(M) :- @(q(1), M), r)),bc_case_show((pa6(V) :- @(V, m2))),bc_case_show((pa7 :- @(call(q(1)), m2))),bc_case_show((pa8(V, W) :- @(m:V, W))),bc_case_show((pa9 :- @(m:q(1), m2), r)),bc_case_show((pa10(M) :- @((q(1), r), M))),bc_case_show((pa11 :- @(q(1), user)))]), ( catch(G, E, (print_message(error, E), fail)) -> writeln('@@end') ; writeln('@@failed'), writeln('@@end') )).
