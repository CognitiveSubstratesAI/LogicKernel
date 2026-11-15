% ORIGINAL: the program of test_generation_swipl.jl (ASSERT-GEN, audit D-0713 (3)): clause/2 and retract/1 take the frame generation from the
% predicate access object (pl-comp.c:7413, pl-proc.c:3180). The cases are the probes of evidence/PROBES (channel repo), p1a*/p1b*/p1c*, and the p1d* rows of the redo's logical update view (audit D-0755);
% a case whose comment starts with [autoload-decl] runs with `:- autoload(library(lists), [append/3, last/2, subtract/3]).` in front of this text.
% The same text goes to swipl and to the kernel.
% shared by both probe programs: the case helpers (consulted by swipl AND by the kernel, the same text).
% pr_show(+T, -S): S is the string print/1 writes for a COPY of T, numbered by numbervars/4 (variable sharing shows as A, B, ...).
pr_show(T, S) :-
    copy_term(T, T2),
    numbervars(T2, 0, _, []),
    with_output_to(string(S), print(T2)).
% pr_case(+Goal, +Tpl, -R): R is the shown list of every Tpl of Goal; an exception of Goal is shown too, as threw(E);
% a CYCLIC answer is not printed (print/1 of a cyclic term is not what is probed here).
pr_case(Goal, Tpl, R) :-
    catch(( findall(Tpl, Goal, L),
            (   acyclic_term(L) -> pr_show(L, R) ;   R = "cyclic-answer" ) ),
          E,
          pr_show(threw(E), R)).
% pr_cyc(+T, -S): is T cyclic (the answer of a unification that can build a cycle)
pr_cyc(T, S) :- ( acyclic_term(T) -> S = acyclic ; S = cyclic ).

:- dynamic foo/1.
foo(1).
foo(2).
foo(3).

pr_on_erase(_) :- assertz(foo(9)).
user:attr_unify_hook(_, _) :- assertz(foo(9)).

% p1e*: the autoloader hook (user:exception/3, `fail` answer) DEFINES pe/1 inside clause/2's window between the call and the access object: pe/1
% carries the autoload attribute, so clause/2 calls trapUndefined (pl-comp.c:7404-7405), whose `$undefined_procedure` runs this hook; the hook's
% assertz creates the generations and `import/1` links pe/1 into user (what the library autoloader does), all before pushPredicateAccessObj.
:- '$set_predicate_attribute'(user:pe(_), autoload, true).
user:exception(undefined_predicate, pe/1, fail) :-
    assertz(pe_impl:pe(1)),
    assertz(pe_impl:pe(2)),
    import(pe_impl:pe/1).

%% p1a0: control, plain clause/2 on a dynamic predicate (no trigger)
p1a0(R) :- pr_case(clause(foo(X), B), X-B, R).
%% p1a1: clause/2 on an AUTOLOADABLE predicate not yet loaded, all solutions through findall
p1a1(R) :- pr_case(clause(append(_,_,_), B), B, R).
%% p1a2: the same, module-qualified lists:append/3
p1a2(R) :- pr_case(clause(lists:append(_,_,_), B), B, R).
%% p1a3: another autoloadable library predicate (last/2)
p1a3(R) :- pr_case(clause(last(_,_), B), B, R).
%% p1a4: append/3 CALLED first (autoload by call), then clause/2
p1a4(R) :- pr_case(( append([], [], _), clause(append(_,_,_), B) ), B, R).
%% p1a5: the autoload flag
p1a5(R) :- pr_case(current_prolog_flag(autoload, F), F, R).
%% p1a6: clause/2 on append/3 as a plain body goal, every solution by REDO (the Julia side enumerates)
p1a6(R) :- clause(append(_,_,_), B), pr_show(B, R).
%% p1a7: control, clause/2 on a predicate that exists nowhere
p1a7(R) :- pr_case(clause(pr_nosuch_zz(_), B), B, R).
%% p1a8: retract/1 on a not-yet-autoloaded library predicate
p1a8(R) :- pr_case(retract(append(_,_,_)), x, R).
%% p1a9: clause/2 (autoloads append/3), then retract/1 of it
p1a9(R) :- pr_case(( clause(append(_,_,_), _), retract(append(_,_,_)) ), x, R).
%% p1a10: a third autoloadable predicate (subtract/3)
p1a10(R) :- pr_case(clause(subtract(_,_,_), B), B, R).
%% p1a11: clause/2 with a body-only unbound reference: the autoloadable predicate's body var shared with the caller
p1a11(R) :- pr_case(clause(append(X,Y,Z), B), t(X,Y,Z,B), R).

%% p1a12: [autoload-decl] the program starts with `:- autoload(library(lists), [append/3, last/2, subtract/3]).` (the procedures are flagged autoload); clause/2 on append/3, all solutions through findall
p1a12(R) :- pr_case(clause(append(_,_,_), B), B, R).
%% p1a13: [autoload-decl] as a12, as a plain body goal, every solution by REDO
p1a13(R) :- clause(append(_,_,_), B), pr_show(B, R).
%% p1a14: [autoload-decl] as a12 for last/2
p1a14(R) :- pr_case(clause(last(_,_), B), B, R).
%% p1a15: [autoload-decl] as a12, then retract/1 of the declared (now loaded, static) predicate
p1a15(R) :- pr_case(retract(append(_,_,_)), x, R).
%% p1a16: [autoload-decl] as a12, then clause/2 TWICE (the second finds it loaded)
p1a16(R) :- pr_case(( clause(append(_,_,_), _), clause(append(_,_,_), B) ), B, R).
%% p1a17: [autoload-decl] control, library(lists) LOADED by use_module/1 first, then clause/2
p1a17(R) :- pr_case(( use_module(library(lists)), clause(append(_,_,_), B) ), B, R).
%% p1a18: [autoload-decl] as a12 with the body variables shared with the caller (t(X,Y,Z,B))
p1a18(R) :- pr_case(clause(append(X,Y,Z), B), t(X,Y,Z,B), R).
%% p1a19: [autoload-decl] as a12 inside a woken goal: a freeze goal (woken by V = 1 right before) is followed by clause/2 on the declared predicate
p1a19(R) :- pr_case(( freeze(V, assertz(foo(9))), V = 1, clause(append(_,_,_), B) ), B, R).

%% p1b0: control, plain retract/1 on a dynamic predicate (no trigger)
p1b0(R) :- pr_case(retract(foo(X)), X, R).
%% p1b1: freeze goal ASSERTS foo(9), woken by V = 1, then retract(foo(X))
p1b1(R) :- pr_case(( freeze(V, assertz(foo(9))), V = 1, retract(foo(X)) ), X, R).
%% p1b2: freeze goal RETRACTS foo(2) (retractall), then retract(foo(X))
p1b2(R) :- pr_case(( freeze(V, retractall(foo(2))), V = 1, retract(foo(X)) ), X, R).
%% p1b3: put_attr/3 with a user:attr_unify_hook/2 that ASSERTS foo(9), then retract(foo(X))
p1b3(R) :- pr_case(( put_attr(V, user, a), V = 1, retract(foo(X)) ), X, R).
%% p1b4: as b1 with clause/2
p1b4(R) :- pr_case(( freeze(V, assertz(foo(9))), V = 1, clause(foo(X), B) ), X-B, R).
%% p1b5: as b2 with clause/2
p1b5(R) :- pr_case(( freeze(V, retractall(foo(2))), V = 1, clause(foo(X), B) ), X-B, R).
%% p1b6: as b3 with clause/2
p1b6(R) :- pr_case(( put_attr(V, user, a), V = 1, clause(foo(X), B) ), X-B, R).
%% p1b7: the attributed variable is retract's OWN argument: the wakeup runs after retract/1's exit
p1b7(R) :- pr_case(( freeze(X, assertz(foo(9))), retract(foo(X)) ), X, R).
%% p1b8: the attributed variable is clause/2's own argument
p1b8(R) :- pr_case(( freeze(X, assertz(foo(9))), clause(foo(X), B) ), X-B, R).
%% p1b9: b1 as a plain body goal, every solution by REDO
p1b9(R) :- freeze(V, assertz(foo(9))), V = 1, retract(foo(X)), pr_show(X, R).
%% p1b10: b4 as a plain body goal, every solution by REDO
p1b10(R) :- freeze(V, assertz(foo(9))), V = 1, clause(foo(X), B), pr_show(X-B, R).
%% p1b11: b1 with retract((foo(X) :- true))
p1b11(R) :- pr_case(( freeze(V, assertz(foo(9))), V = 1, retract((foo(X) :- true)) ), X, R).
%% p1b12: wakeup that asserts, and the woken variable is bound INSIDE call/1 right before clause/2
p1b12(R) :- pr_case(call(( freeze(V, assertz(foo(9))), V = 1, call(clause(foo(X), B)) )), X-B, R).
%% p1b13: two pending wakeups (assert, then retract) before clause/2
p1b13(R) :- pr_case(( freeze(V, assertz(foo(9))), freeze(W, retractall(foo(1))), V = 1, W = 1, clause(foo(X), B) ), X-B, R).

%% p1c1: prolog_listen(erase, L): the listener asserts foo(9) when retract/1 erases a clause (no call-port hook exists in swipl either)
p1c1(R) :- prolog_listen(erase, pr_on_erase), pr_case(retract(foo(X)), X, R0), prolog_unlisten(erase, pr_on_erase), R = R0.
%% p1c2: erase listener fired from a wakeup (freeze goal retracts foo(1)) right before clause/2
p1c2(R) :- prolog_listen(erase, pr_on_erase), pr_case(( freeze(V, retract(foo(1))), V = 1, clause(foo(X), B) ), X-B, R0), prolog_unlisten(erase, pr_on_erase), R = R0.
%% p1c3: c1 as a plain body goal, every solution by REDO (the listener stays)
p1c3(R) :- prolog_listen(erase, pr_on_erase), retract(foo(X)), pr_show(X, R).
%% p1c4: erase listener, retract(foo(2)) then clause/2
p1c4(R) :- prolog_listen(erase, pr_on_erase), pr_case(( retract(foo(2)), clause(foo(X), B) ), X-B, R0), prolog_unlisten(erase, pr_on_erase), R = R0.

%% p1d1: the LOGICAL UPDATE VIEW of clause/2's redo: a clause asserted while the first answer's choice point is open is NOT answered (the frame keeps the generation of the call); plain body goal, every solution by REDO
p1d1(R) :- clause(foo(X), B), ( X == 1 -> assertz(foo(7)) ; true ), pr_show(X-B, R).
%% p1d2: as d1, every answer through findall
p1d2(R) :- pr_case(( clause(foo(X), B), ( X == 1 -> assertz(foo(7)) ; true ) ), X-B, R).
%% p1d3: clause/2's redo, the LATER clause foo(3) is retracted while the first answer's choice point is open: it is still answered (the older generation sees it); by REDO
p1d3(R) :- clause(foo(X), B), ( X == 1 -> once(retract(foo(3))) ; true ), pr_show(X-B, R).
%% p1d4: as d3, every answer through findall
p1d4(R) :- pr_case(( clause(foo(X), B), ( X == 1 -> once(retract(foo(3))) ; true ) ), X-B, R).
%% p1d5: retract/1's redo, a clause asserted between two solutions is NOT retracted by the redo (the logical update view); by REDO
p1d5(R) :- retract(foo(X)), ( X == 1 -> assertz(foo(7)) ; true ), pr_show(X, R).
%% p1d6: as d5, every answer through findall; foo(7) is left in the database (asserted, never retracted: d7 shows it)
p1d6(R) :- pr_case(( retract(foo(X)), ( X == 1 -> assertz(foo(7)) ; true ) ), X, R).
%% p1d7: as d6, then what is left of foo/1 (the asserted clause survives the redo)
p1d7(R) :- pr_case(( retract(foo(X)), ( X == 1 -> assertz(foo(7)) ; true ) ), X, _), pr_case(foo(Y), Y, R).
%% p1d8: retract/1's redo, the LATER clause foo(3) is retracted by someone else while the first answer's choice point is open; by REDO
p1d8(R) :- retract(foo(X)), ( X == 1 -> once(retract(foo(3))) ; true ), pr_show(X, R).
%% p1d9: as d8, every answer through findall
p1d9(R) :- pr_case(( retract(foo(X)), ( X == 1 -> once(retract(foo(3))) ; true ) ), X, R).
%% p1d10: as d8, then what is left of foo/1
p1d10(R) :- pr_case(( retract(foo(X)), ( X == 1 -> once(retract(foo(3))) ; true ) ), X, _), pr_case(foo(Y), Y, R).

%% p1e1: clause/2 on pe/1, whose autoload hook asserts pe_impl:pe(1), pe(2) BETWEEN the call and the access object: the frame's generation is the access object's, so both clauses are answered; findall
p1e1(R) :- pr_case(clause(pe(X), B), X-B, R).
%% p1e2: as e1, as a plain body goal, every solution by REDO
p1e2(R) :- clause(pe(X), B), pr_show(X-B, R).
%% p1e3: as e1 with the body variable shared with the caller (the whole head)
p1e3(R) :- pr_case(clause(pe(X), B), t(X, B), R).
%% p1e4: as e1, then the logical update view from that generation: pe_impl:pe(7) asserted while the first answer's choice point is open is NOT answered
p1e4(R) :- pr_case(( clause(pe(X), B), ( X == 1 -> assertz(pe_impl:pe(7)) ; true ) ), X-B, R).
%% p1e5: clause/2 TWICE on pe/1 (the second finds it linked: no hook), then every solution of the second
p1e5(R) :- pr_case(( clause(pe(_), _), clause(pe(X), B) ), X-B, R).
%% p1e6: e1 in a goal after a wakeup that asserted foo(9) (a generation created before the call, the hook's after it): both are seen as in b1
p1e6(R) :- pr_case(( freeze(V, assertz(foo(9))), V = 1, clause(pe(X), B) ), X-B, R).
