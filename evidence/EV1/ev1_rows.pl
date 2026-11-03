:- dynamic ev1_log/1, ev1_p/1, ev1_q/1.
ev1_x(X, Y) :-
    (   X = start(_) -> Y = X
    ;   X = end(_) -> Y = X
    ;   atom(X) -> Y = X
    ;   catch(clause(H, B, X), _, fail) -> Y = cl(H, B)
    ;   Y = gone
    ).
ev1_t(Tag, Act, X) :- ev1_x(X, Y), assertz(ev1_log(Tag-Act-Y)).
ev1_a(Act, X) :- ev1_t(a, Act, X).
ev1_b(Act, X) :- ev1_t(b, Act, X).
ev1_veto(Tag, Act, X) :- ev1_t(Tag, Act, X), fail.
ev1_vend(Act, X) :- ev1_t(v, Act, X), \+ X = end(_).
ev1_throw(Tag, Act, X) :- ev1_t(Tag, Act, X), throw(ev1_ball(Tag)).
ev1_r(Tag, Ref) :-
    (   recorded(ev1_k, V, Ref) -> Y = present(V) ; Y = gone ),
    assertz(ev1_log(Tag-erase-Y)).
ev1_rveto(Tag, Ref) :- ev1_r(Tag, Ref), fail.
ev1_rthrow(Tag, Ref) :- ev1_r(Tag, Ref), throw(ev1_ball(Tag)).
ev1_e(Tag, X) :- ev1_x(X, Y), assertz(ev1_log(Tag-erase-Y)).
ev1_ethrow(Tag, X) :- ev1_e(Tag, X), throw(ev1_ball(Tag)).
ev1_pair(P, Q, Act, X) :- ev1_t(P-Q, Act, X).
ev1_get(R) :- findall(L, ev1_log(L), R).
ev1_unl(E) :- ev1_unl(E, [ev1_a, ev1_b, ev1_t(_), ev1_veto(_), ev1_vend, ev1_throw(_), ev1_r(_), ev1_rveto(_), ev1_rthrow(_), ev1_e(_), ev1_ethrow(_), ev1_pair(_, _)]).
ev1_unl(_, []).
ev1_unl(E, [C|Cs]) :- prolog_unlisten(E, C), ev1_unl(E, Cs).
ev1_unl_all([]).
ev1_unl_all([E|Es]) :- ev1_unl(E), ev1_unl_all(Es).
ev1_rounds(0) :- !.
ev1_rounds(N) :- ev1_unl_all([ev1_p/1, ev1_q/1, ev1_m:ev1_q/1, ev1_u/1, ev1_p/2, erase, untable]), N1 is N-1, ev1_rounds(N1).
ev1_clear :-
    ev1_rounds(4),
    retractall(ev1_log(_)), retractall(ev1_p(_)), retractall(ev1_q(_)), retractall(ev1_m:ev1_q(_)),
    ( recorded(ev1_k, _, Ref), erase(Ref), fail ; true ).
ev1_retall :- ( retract(ev1_p(_)), fail ; true ).
t_ev1p01(R) :- catch((ev1_clear, prolog_listen(ev1_p/1, ev1_a), assertz(ev1_p(1)), ev1_get(R)), error(SsuE, _), R = raised(SsuE)).
t_ev1p02(R) :- catch((ev1_clear, prolog_listen(ev1_p/1, ev1_a), asserta(ev1_p(1)), ev1_get(R)), error(SsuE, _), R = raised(SsuE)).
t_ev1p03(R) :- catch((ev1_clear, prolog_listen(ev1_p/1, ev1_a), assert(ev1_p(1)), ev1_get(R)), error(SsuE, _), R = raised(SsuE)).
t_ev1p04(R) :- catch((ev1_clear, prolog_listen(ev1_p/1, ev1_a), assertz((ev1_p(X) :- ev1_q(X))), ev1_get(R)), error(SsuE, _), R = raised(SsuE)).
t_ev1p05(R) :- catch((ev1_clear, assertz(ev1_p(1)), prolog_listen(ev1_p/1, ev1_a), retract(ev1_p(1)), ev1_get(R)), error(SsuE, _), R = raised(SsuE)).
t_ev1p06(R) :- catch((ev1_clear, assertz(ev1_p(1)), assertz(ev1_p(2)), prolog_listen(ev1_p/1, ev1_a), ev1_retall, ev1_get(R)), error(SsuE, _), R = raised(SsuE)).
t_ev1p07(R) :- catch((ev1_clear, assertz(ev1_p(1)), prolog_listen(ev1_p/1, ev1_a), ( retract(ev1_p(9)) -> true ; true ), ev1_get(R)), error(SsuE, _), R = raised(SsuE)).
t_ev1p08(R) :- catch((ev1_clear, assertz(ev1_p(1), Ref), prolog_listen(ev1_p/1, ev1_a), erase(Ref), ev1_get(R)), error(SsuE, _), R = raised(SsuE)).
t_ev1p09(R) :- catch((ev1_clear, assertz(ev1_p(1)), assertz(ev1_p(2)), assertz(ev1_p(1)), prolog_listen(ev1_p/1, ev1_a), retractall(ev1_p(1)), findall(X, ev1_p(X), Xs), ev1_get(L), R = Xs-L), error(SsuE, _), R = raised(SsuE)).
t_ev1p10(R) :- catch((ev1_clear, prolog_listen(ev1_p/1, ev1_a), retractall(ev1_p(_)), ev1_get(R)), error(SsuE, _), R = raised(SsuE)).
t_ev1p11(R) :- catch((ev1_clear, assertz(ev1_p(1)), prolog_listen(ev1_p/1, ev1_a), retractall(ev1_p(9)), ev1_get(R)), error(SsuE, _), R = raised(SsuE)).
t_ev1p12(R) :- catch((ev1_clear, assertz(ev1_p(1)), assertz(ev1_p(2)), assertz(ev1_p(3)), prolog_listen(ev1_p/1, ev1_a), retractall(ev1_p(2)), findall(X, ev1_p(X), Xs), ev1_get(L), R = Xs-L), error(SsuE, _), R = raised(SsuE)).
t_ev1p13(R) :- catch((ev1_clear, prolog_listen(ev1_u/1, ev1_a), retractall(ev1_u(_)), ev1_get(R)), error(SsuE, _), R = raised(SsuE)).
t_ev1p14(R) :- catch((ev1_clear, prolog_listen(ev1_m:ev1_q/1, ev1_a), ev1_m:assertz(ev1_q(1)), ev1_get(R)), error(SsuE, _), R = raised(SsuE)).
t_ev1p15(R) :- catch((ev1_clear, prolog_listen(ev1_p/1, ev1_a), assertz(ev1_q(1)), ev1_get(R)), error(SsuE, _), R = raised(SsuE)).
t_ev1p16(R) :- catch((ev1_clear, prolog_listen(ev1_p(_), ev1_a), assertz(ev1_p(1)), ev1_get(R)), error(SsuE, _), R = raised(SsuE)).
t_ev1p17(R) :- catch((ev1_clear, prolog_listen(ev1_p/1, ev1_a), prolog_unlisten(ev1_p/1, ev1_a), assertz(ev1_p(1)), ev1_get(R)), error(SsuE, _), R = raised(SsuE)).
t_ev1p19(R) :- catch((ev1_clear, prolog_listen(ev1_p/1, ev1_a), assertz(ev1_p(1), Ref), erase(Ref), ev1_get(R)), error(SsuE, _), R = raised(SsuE)).
t_ev1o01(R) :- catch((ev1_clear, prolog_listen(ev1_p/1, ev1_a), prolog_listen(ev1_p/1, ev1_b), assertz(ev1_p(1)), ev1_get(R)), error(SsuE, _), R = raised(SsuE)).
t_ev1o02(R) :- catch((ev1_clear, prolog_listen(ev1_p/1, ev1_a, [as(last)]), prolog_listen(ev1_p/1, ev1_b, [as(last)]), assertz(ev1_p(1)), ev1_get(R)), error(SsuE, _), R = raised(SsuE)).
t_ev1o03(R) :- catch((ev1_clear, prolog_listen(ev1_p/1, ev1_a), prolog_listen(ev1_p/1, ev1_b, [as(last)]), prolog_listen(ev1_p/1, ev1_t(c), [as(first)]), assertz(ev1_p(1)), ev1_get(R)), error(SsuE, _), R = raised(SsuE)).
t_ev1o04(R) :- catch((ev1_clear, prolog_listen(ev1_p/1, ev1_t(one), [name(n)]), prolog_listen(ev1_p/1, ev1_t(two), [name(n)]), assertz(ev1_p(1)), ev1_get(R)), error(SsuE, _), R = raised(SsuE)).
t_ev1o05(R) :- catch((ev1_clear, prolog_listen(ev1_p/1, ev1_a), prolog_listen(ev1_p/1, ev1_t(one), [name(n), as(last)]), prolog_listen(ev1_p/1, ev1_b, [as(last)]), prolog_listen(ev1_p/1, ev1_t(two), [name(n), as(first)]), assertz(ev1_p(1)), ev1_get(R)), error(SsuE, _), R = raised(SsuE)).
t_ev1o06(R) :- catch((ev1_clear, prolog_listen(ev1_p/1, ev1_t(one), [name(n1)]), prolog_listen(ev1_p/1, ev1_t(two), [name(n2)]), assertz(ev1_p(1)), ev1_get(R)), error(SsuE, _), R = raised(SsuE)).
t_ev1o07(R) :- catch((ev1_clear, prolog_listen(ev1_p/1, ev1_a), prolog_listen(ev1_p/1, ev1_a), assertz(ev1_p(1)), ev1_get(R)), error(SsuE, _), R = raised(SsuE)).
t_ev1o08(R) :- catch((ev1_clear, prolog_listen(ev1_p/1, ev1_a, [as(first)]), prolog_listen(ev1_p/1, ev1_b, [as(first)]), assertz(ev1_p(1)), ev1_get(R)), error(SsuE, _), R = raised(SsuE)).
t_ev1o09(R) :- catch((ev1_clear, prolog_listen(ev1_p/1, ev1_a, [name(n)]), prolog_listen(ev1_q/1, ev1_b, [name(n)]), assertz(ev1_p(1)), assertz(ev1_q(1)), ev1_get(R)), error(SsuE, _), R = raised(SsuE)).
t_ev1o10(R) :- catch((ev1_clear, prolog_listen(ev1_p/1, ev1_a), prolog_listen(ev1_p/1, ev1_t(one), [name(n)]), prolog_listen(ev1_p/1, ev1_t(three), [name(n)]), assertz(ev1_p(1)), ev1_get(R)), error(SsuE, _), R = raised(SsuE)).
t_ev1o11(R) :- catch((ev1_clear, prolog_listen(ev1_p/1, ev1_a, [name(n)]), prolog_listen(ev1_p/1, ev1_t(two), [name(n)]), assertz(ev1_p(1)), ev1_get(R)), error(SsuE, _), R = raised(SsuE)).
t_ev1u01(R) :- catch((ev1_clear, prolog_listen(ev1_p/1, ev1_a), prolog_listen(ev1_p/1, ev1_b), prolog_unlisten(ev1_p/1, ev1_a), assertz(ev1_p(1)), ev1_get(R)), error(SsuE, _), R = raised(SsuE)).
t_ev1u02(R) :- catch((ev1_clear, prolog_listen(ev1_p/1, ev1_t(1)), prolog_listen(ev1_p/1, ev1_t(2)), prolog_unlisten(ev1_p/1, ev1_t(1)), assertz(ev1_p(1)), ev1_get(R)), error(SsuE, _), R = raised(SsuE)).
t_ev1u03(R) :- catch((ev1_clear, prolog_listen(ev1_p/1, ev1_t(1)), prolog_listen(ev1_p/1, ev1_t(2)), prolog_listen(ev1_p/1, ev1_a), prolog_unlisten(ev1_p/1, ev1_t(_)), assertz(ev1_p(1)), ev1_get(R)), error(SsuE, _), R = raised(SsuE)).
t_ev1u04(R) :- catch((ev1_clear, prolog_listen(ev1_p/1, ev1_t(1)), prolog_unlisten(ev1_p/1, ev1_t), assertz(ev1_p(1)), ev1_get(R)), error(SsuE, _), R = raised(SsuE)).
t_ev1u05(R) :- catch((ev1_clear, ( prolog_unlisten(ev1_q/1, ev1_a) -> R = yes ; R = no )), error(SsuE, _), R = raised(SsuE)).
t_ev1u06(R) :- catch((ev1_clear, prolog_unlisten(nosuchevent, ev1_a), R = yes), error(SsuE, _), R = raised(SsuE)).
t_ev1u07(R) :- catch((ev1_clear, prolog_unlisten(1, ev1_a), R = yes), error(SsuE, _), R = raised(SsuE)).
t_ev1u08(R) :- catch((ev1_clear, prolog_listen(ev1_p/1, ev1_a), prolog_unlisten(ev1_p/1, 1), R = yes), error(SsuE, _), R = raised(SsuE)).
t_ev1u09(R) :- catch((ev1_clear, prolog_listen(ev1_p/1, ev1_a), prolog_unlisten(ev1_p/1, _), R = yes), error(SsuE, _), R = raised(SsuE)).
t_ev1u10(R) :- catch((ev1_clear, prolog_listen(ev1_p/1, ev1_a), ( prolog_unlisten(ev1_p/1, ev1_b) -> A = yes ; A = no ), assertz(ev1_p(1)), ev1_get(L), R = A-L), error(SsuE, _), R = raised(SsuE)).
t_ev1u11(R) :- catch((ev1_clear, prolog_listen(erase, ev1_r(x)), prolog_unlisten(erase, ev1_r(x)), recorda(ev1_k, v, Ref), erase(Ref), ev1_get(R)), error(SsuE, _), R = raised(SsuE)).
t_ev1u12(R) :- catch((ev1_clear, prolog_listen(ev1_p/1, user:ev1_a), prolog_unlisten(ev1_p/1, ev1_a), assertz(ev1_p(1)), ev1_get(R)), error(SsuE, _), R = raised(SsuE)).
t_ev1u13(R) :- catch((ev1_clear, prolog_listen(ev1_p/1, ev1_a), prolog_unlisten(ev1_p/1, ev1_a), prolog_unlisten(ev1_p/1, ev1_a), assertz(ev1_p(1)), ev1_get(R)), error(SsuE, _), R = raised(SsuE)).
t_ev1u14(R) :- catch((ev1_clear, prolog_listen(ev1_p/1, ev1_a), prolog_listen(ev1_p/1, ev1_a), prolog_unlisten(ev1_p/1, ev1_a), assertz(ev1_p(1)), ev1_get(R)), error(SsuE, _), R = raised(SsuE)).
t_ev1u15(R) :- catch((ev1_clear, prolog_listen(ev1_p/1, ev1_t(1)), prolog_listen(ev1_p/1, ev1_t(1)), prolog_unlisten(ev1_p/1, ev1_t(1)), assertz(ev1_p(1)), ev1_get(R)), error(SsuE, _), R = raised(SsuE)).
t_ev1u16(R) :- catch((ev1_clear, prolog_listen(ev1_p/1, ev1_t(f(1))), prolog_unlisten(ev1_p/1, ev1_t(f(2))), assertz(ev1_p(1)), ev1_get(R)), error(SsuE, _), R = raised(SsuE)).
t_ev1u17(R) :- catch((ev1_clear, prolog_listen(untable, ev1_a), prolog_unlisten(untable, ev1_a), R = yes), error(SsuE, _), R = raised(SsuE)).
t_ev1v01(R) :- catch((ev1_clear, prolog_listen(ev1_p/1, ev1_veto(v)), ( assertz(ev1_p(1)) -> A = yes ; A = no ), findall(X, ev1_p(X), Xs), ev1_get(L), R = A-Xs-L), error(SsuE, _), R = raised(SsuE)).
t_ev1v02(R) :- catch((ev1_clear, assertz(ev1_p(1)), prolog_listen(ev1_p/1, ev1_veto(v)), ( retract(ev1_p(1)) -> A = yes ; A = no ), findall(X, ev1_p(X), Xs), ev1_get(L), R = A-Xs-L), error(SsuE, _), R = raised(SsuE)).
t_ev1v03(R) :- catch((ev1_clear, prolog_listen(ev1_p/1, ev1_veto(v)), prolog_listen(ev1_p/1, ev1_b, [as(last)]), ( assertz(ev1_p(1)) -> A = yes ; A = no ), ev1_get(L), R = A-L), error(SsuE, _), R = raised(SsuE)).
t_ev1v04(R) :- catch((ev1_clear, prolog_listen(ev1_p/1, ev1_t(w)), prolog_listen(ev1_p/1, ev1_veto(v), [as(last)]), ( assertz(ev1_p(1)) -> A = yes ; A = no ), ev1_get(L), R = A-L), error(SsuE, _), R = raised(SsuE)).
t_ev1v05(R) :- catch((ev1_clear, assertz(ev1_p(1)), assertz(ev1_p(2)), prolog_listen(ev1_p/1, ev1_veto(v)), ( retractall(ev1_p(_)) -> A = yes ; A = no ), findall(X, ev1_p(X), Xs), ev1_get(L), R = A-Xs-L), error(SsuE, _), R = raised(SsuE)).
t_ev1v06(R) :- catch((ev1_clear, assertz(ev1_p(1)), assertz(ev1_p(2)), prolog_listen(ev1_p/1, ev1_vend), ( retractall(ev1_p(_)) -> A = yes ; A = no ), findall(X, ev1_p(X), Xs), ev1_get(L), R = A-Xs-L), error(SsuE, _), R = raised(SsuE)).
t_ev1v07(R) :- catch((ev1_clear, assertz(ev1_p(1), Ref), prolog_listen(ev1_p/1, ev1_veto(v)), ( erase(Ref) -> A = yes ; A = no ), findall(X, ev1_p(X), Xs), ev1_get(L), R = A-Xs-L), error(SsuE, _), R = raised(SsuE)).
t_ev1v08(R) :- catch((ev1_clear, prolog_listen(ev1_p/1, ev1_throw(t)), catch(assertz(ev1_p(1)), E, true), findall(X, ev1_p(X), Xs), ev1_get(L), R = E-Xs-L), error(SsuE, _), R = raised(SsuE)).
t_ev1v09(R) :- catch((ev1_clear, assertz(ev1_p(1)), prolog_listen(ev1_p/1, ev1_throw(t)), catch(retract(ev1_p(1)), E, true), findall(X, ev1_p(X), Xs), ev1_get(L), R = E-Xs-L), error(SsuE, _), R = raised(SsuE)).
t_ev1v10(R) :- catch((ev1_clear, prolog_listen(ev1_p/1, ev1_throw(t)), prolog_listen(ev1_p/1, ev1_b, [as(last)]), catch(assertz(ev1_p(1)), E, true), ev1_get(L), R = E-L), error(SsuE, _), R = raised(SsuE)).
t_ev1v11(R) :- catch((ev1_clear, assertz(ev1_p(1)), prolog_listen(ev1_p/1, ev1_throw(t)), catch(retractall(ev1_p(_)), E, true), findall(X, ev1_p(X), Xs), ev1_get(L), R = E-Xs-L), error(SsuE, _), R = raised(SsuE)).
t_ev1v12(R) :- catch((ev1_clear, prolog_listen(ev1_p/1, ev1_veto(v)), prolog_listen(ev1_p/1, ev1_t(w), [as(last)]), ( assertz(ev1_p(1)) -> A = yes ; A = no ), ev1_get(L), R = A-L), error(SsuE, _), R = raised(SsuE)).
t_ev1e01(R) :- catch((ev1_clear, prolog_listen(ev1_p/1, ev1_a, [as(middle)]), R = yes), error(SsuE, _), R = raised(SsuE)).
t_ev1e02(R) :- catch((ev1_clear, prolog_listen(ev1_p/1, ev1_a, [name(1)]), R = yes), error(SsuE, _), R = raised(SsuE)).
t_ev1e03(R) :- catch((ev1_clear, prolog_listen(ev1_p/1, 1), R = yes), error(SsuE, _), R = raised(SsuE)).
t_ev1e04(R) :- catch((ev1_clear, prolog_listen(ev1_p/1, _), R = yes), error(SsuE, _), R = raised(SsuE)).
t_ev1e05(R) :- catch((ev1_clear, prolog_listen(ev1_p/a, ev1_a), R = yes), error(SsuE, _), R = raised(SsuE)).
t_ev1e06(R) :- catch((ev1_clear, prolog_listen(ev1_p/(-1), ev1_a), R = yes), error(SsuE, _), R = raised(SsuE)).
t_ev1e07(R) :- catch((ev1_clear, prolog_listen(ev1_p/2, ev1_a), assertz(ev1_p(1)), ev1_get(R)), error(SsuE, _), R = raised(SsuE)).
t_ev1e08(R) :- catch((ev1_clear, prolog_listen(ev1_p/1, ev1_a, foo), R = yes), error(SsuE, _), R = raised(SsuE)).
t_ev1e09(R) :- catch((ev1_clear, prolog_listen(_, ev1_a), R = yes), error(SsuE, _), R = raised(SsuE)).
t_ev1e10(R) :- catch((ev1_clear, prolog_listen(nosuchevent/1, ev1_a), R = yes), error(SsuE, _), R = raised(SsuE)).
t_ev1e11(R) :- catch((ev1_clear, prolog_listen(foo:ev1_p/1, ev1_a), R = yes), error(SsuE, _), R = raised(SsuE)).
t_ev1e12(R) :- catch((ev1_clear, prolog_listen(ev1_p/1, ev1_a, [as(first), foo(1)]), assertz(ev1_p(1)), ev1_get(R)), error(SsuE, _), R = raised(SsuE)).
t_ev1r01(R) :- catch((ev1_clear, prolog_listen(erase, ev1_r(x)), recorda(ev1_k, v, Ref), erase(Ref), ev1_get(R)), error(SsuE, _), R = raised(SsuE)).
t_ev1r02(R) :- catch((ev1_clear, prolog_listen(erase, ev1_r(x)), prolog_listen(erase, ev1_r(y)), recordz(ev1_k, v, Ref), erase(Ref), ev1_get(R)), error(SsuE, _), R = raised(SsuE)).
t_ev1r03(R) :- catch((ev1_clear, prolog_listen(erase, ev1_rthrow(t)), recorda(ev1_k, v, Ref), catch(erase(Ref), E, true), findall(V, recorded(ev1_k, V), Vs), ev1_get(L), R = E-Vs-L), error(SsuE, _), R = raised(SsuE)).
t_ev1r04(R) :- catch((ev1_clear, prolog_listen(erase, ev1_rveto(t)), recorda(ev1_k, v, Ref), ( erase(Ref) -> A = yes ; A = no ), findall(V, recorded(ev1_k, V), Vs), ev1_get(L), R = A-Vs-L), error(SsuE, _), R = raised(SsuE)).
t_ev1r05(R) :- catch((ev1_clear, prolog_listen(erase, ev1_r(x)), recorda(ev1_k, v, _), recorda(ev1_k, w, _), ( recorded(ev1_k, v, Ref) -> erase(Ref) ; true ), ev1_get(R)), error(SsuE, _), R = raised(SsuE)).
t_ev1r06(R) :- catch((ev1_clear, prolog_listen(erase, ev1_r(x)), recorda(ev1_k, v, Ref), erase(Ref), ( catch(erase(Ref), error(E, _), true) -> true ; true ), ev1_get(L), R = E-L), error(SsuE, _), R = raised(SsuE)).
t_ev1r07(R) :- catch((ev1_clear, prolog_listen(erase, ev1_r(x)), assertz(ev1_p(1)), ev1_get(R)), error(SsuE, _), R = raised(SsuE)).
t_ev1r08(R) :- catch((ev1_clear, prolog_listen(erase, ev1_rveto(t)), prolog_listen(erase, ev1_r(x), [as(last)]), recorda(ev1_k, v, Ref), ( erase(Ref) -> A = yes ; A = no ), ev1_get(L), R = A-L), error(SsuE, _), R = raised(SsuE)).
t_ev1g01(R) :- catch((ev1_clear, garbage_collect_clauses, prolog_listen(erase, ev1_e(g)), assertz(ev1_p(1)), retract(ev1_p(1)), garbage_collect_clauses, ev1_get(R)), error(SsuE, _), R = raised(SsuE)).
t_ev1g02(R) :- catch((ev1_clear, garbage_collect_clauses, prolog_listen(erase, ev1_ethrow(g)), assertz(ev1_p(1)), retract(ev1_p(1)), catch(garbage_collect_clauses, E, true), ev1_get(L), R = E-L), error(SsuE, _), R = raised(SsuE)).
t_ev1u18(R) :- catch((ev1_clear, prolog_listen(ev1_p/1, ev1_pair(a, b)), prolog_listen(ev1_p/1, ev1_pair(z, c)), prolog_unlisten(ev1_p/1, ev1_pair(X, c)), assertz(ev1_p(1)), ev1_get(L), R = X-L), error(SsuE, _), R = raised(SsuE)).
t_ev1p20(R) :- catch((ev1_clear, assertz(ev1_p(1)), prolog_listen(ev1_p/1, ev1_a), abolish(ev1_p/1), assertz(ev1_p(2)), ev1_get(R)), error(SsuE, _), R = raised(SsuE)).
