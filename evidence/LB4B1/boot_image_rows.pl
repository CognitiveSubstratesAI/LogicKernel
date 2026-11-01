% LB4B1 oracle: one row per predicate of system, the columns boot_image_predicates reads (T1), from predicate_property/2.
lb4b1_pis([(=)/2, functor/3, arg/3, atom_length/2, atom_codes/2, (\=)/2, (==)/2, var/1, atom/1, (is)/2, (<)/2, write/1, nl/0, halt/0,
           (\+)/1, call/1, assertz/1, retract/1, findall/3, atom_to_term/3]).
lb4b1_flag(P, H, V) :- ( catch(predicate_property(system:H, P), _, fail) -> V = 1 ; V = 0 ).
lb4b1_row(N/A) :-
    functor(H, N, A),
    lb4b1_flag(defined, H, D), lb4b1_flag(foreign, H, F), lb4b1_flag(dynamic, H, Y), lb4b1_flag(iso, H, I), lb4b1_flag(transparent, H, T),
    ( catch(predicate_property(system:H, number_of_clauses(C)), _, fail) -> true ; C = none ),
    format("~q defined=~w foreign=~w dynamic=~w iso=~w transparent=~w number_of_clauses=~w~n", [N/A, D, F, Y, I, T, C]).
:- lb4b1_pis(L), forall(member(PI, L), lb4b1_row(PI)).
