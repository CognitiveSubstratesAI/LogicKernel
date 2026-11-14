% ORIGINAL: the rows of test/core_lang/test_dbg1_swipl.jl (their predicates are pl-trace.c's and pl-pro.c's).
% test/core_lang/test_dbg1_swipl.pl - DBG1's rows. Each `tN(R)` is one row; test_dbg1_swipl.out holds the pin's swipl
% (10.1.20) answers to them as the test's driver prints them (`ok`, then one line per row: its name and every solution).
% Rows t0-t13: tracing/0, notrace/0, trace/0 and the ports' masks '$leash'/2 and '$visible'/2. Every row that turns tracing
% on first makes no port visible ('$visible'(_, 0)), so neither swipl's tracer (it would stop at a port) nor the kernel's
% refusal of a tracer it does not have (trace/0 with a visible port) is reached, and restores what it changed.
% Rows t14-t23 (no t20): '$can_yield'/0 and '$call_no_catch'/1.
% Rows t24-t61: prolog_frame_attribute/3 (t24-t48), prolog_choice_attribute/3 (t49-t57), the mutants' rows (t58-t61); none prints a frame or choice number.

% a row's own error is its answer
row(Goal, R) :- catch(Goal, error(E, _), R = raised(E)).
% the debugger's state, as a term: tracing/0, the `debug` flag
dstate(s(T, D)) :- ( tracing -> T = on ; T = off ), current_prolog_flag(debug, D).
% leave tracing and debugging off
dclean :- notrace, set_prolog_flag(debug, false).

% tracing/0 is false at the start; notrace/0 keeps it so
t0(R) :- dstate(R).
t1(R) :- notrace, dstate(R).
% '$leash'/2 and '$visible'/2: the initial masks (pl-trace.c initTracer), the round trips, the errors
t2(R) :- '$leash'(L, L), '$visible'(V, V), R = L-V.
t3(R) :- '$leash'(O, 7), '$leash'(N, O), R = O-N.
t4(R) :- '$visible'(O, 7), '$visible'(N, O), R = O-N.
t5(R) :- '$leash'(O, 511), '$leash'(M, 0), '$leash'(Z, O), R = [M, Z].
t6(R) :- '$visible'(O, 0), '$visible'(M, 511), '$visible'(Z, O), R = [M, Z].
t7(R) :- ( '$leash'(foo, 1) -> R = yes ; R = no ).
t8(R) :- ( '$visible'(foo, 1) -> R = yes ; R = no ).
t9(R) :- findall(X, ( member(G, ['$leash'(_, a), '$leash'(_, 1.5), '$leash'(_, _), '$leash'(_, 4294967296),
                                 '$visible'(_, b), '$visible'(_, "s"), '$visible'(_, f(x)), '$visible'(_, -4294967297)]),
                      row(G, X) ), R).
% a negative mask is stored as it is
t10(R) :- '$leash'(O, -1), '$leash'(N, O), R = O-N.
% a failed unification of Old leaves the mask alone
t11(R) :- '$leash'(O, O), ( '$leash'(foo, 3) -> true ; true ), '$leash'(N, O), R = O-N.
% trace/0 with no visible port: tracing and debugging on, notrace/0 off (debugging stays on)
t12(R) :- '$visible'(V, 0), trace, dstate(A), notrace, dstate(B), dclean, '$visible'(_, V), dstate(C), R = [A, B, C].
% trace/0 twice, and notrace/0 twice
t13(R) :- '$visible'(V, 0), trace, trace, dstate(A), notrace, notrace, dstate(B), dclean, '$visible'(_, V), R = [A, B].
% '$can_yield'/0 in a query that was opened without PL_Q_ALLOW_YIELD
t14(R) :- ( '$can_yield' -> R = yes ; R = no ).
% '$call_no_catch'/1: always true, bindings kept
t15(R) :- '$call_no_catch'(X = 1), R = X.
t16(R) :- '$call_no_catch'(fail), R = failed.
t17(R) :- '$call_no_catch'(throw(ball(1))), R = caught.
t18(R) :- '$call_no_catch'(_), R = var.
t19(R) :- '$call_no_catch'(1), R = number.
% (an unknown procedure is not a row: swipl's debugger stops at its error, with the status 4 of an EOF)
% an exception leaves tracing and debugging off (restore_after_exception)
t21(R) :- '$visible'(V, 0), trace, dstate(A), '$call_no_catch'(throw(x)), dstate(B), dclean, '$visible'(_, V), R = [A, B].
% a failure leaves them as they are
t22(R) :- '$visible'(V, 0), trace, '$call_no_catch'(fail), dstate(A), dclean, '$visible'(_, V), R = A.
% the context module is the caller's (the predicate is transparent)
:- assertz(dbg1m:here(1)).
t23(R) :- dbg1m:'$call_no_catch'(here(X)), R = X.
% (a goal cut short is not a row: swipl's top-level unwind discards the driver's pending output, the row's name)
% ---- prolog_frame_attribute/3 (DBG1b) ----
% (a frame reference taken in a clause whose last call is prolog_frame_attribute/3 names that callee's frame after the last-call
% optimisation, so the rows keep it from the last call)
t24(R) :- prolog_current_frame(F), prolog_frame_attribute(F, predicate_indicator, PI), R = PI.
t25(R) :- prolog_current_frame(F), prolog_frame_attribute(F, goal, G), G =.. [N|_], R = N.
t26(R) :- prolog_current_frame(F), prolog_frame_attribute(F, level, L), ( integer(L), L > 0 -> R = ok ; R = L ).
t27(R) :- prolog_current_frame(F), prolog_frame_attribute(F, top, T), prolog_frame_attribute(F, skipped, S),
          prolog_frame_attribute(F, hidden, H), prolog_frame_attribute(F, depth_limit_exceeded, D),
          ( memberchk(D, [true, false]) -> R = [T, S, H, bool] ; R = D ).
t28(R) :- prolog_current_frame(F), prolog_frame_attribute(F, context_module, M), R = M.
:- assertz((dbg1m:gl(X) :- prolog_current_frame(F), prolog_frame_attribute(F, goal, G), G = M:Gl, Gl =.. [N|_], X = M-N)).
:- assertz((dbg1m:ctx(M) :- prolog_current_frame(F), prolog_frame_attribute(F, context_module, M0), M = M0)).
:- assertz((dbg1m:pin(PI) :- prolog_current_frame(F), prolog_frame_attribute(F, predicate_indicator, PI0), PI = PI0)).
t29(R) :- dbg1m:gl(R).
t30(R) :- dbg1m:ctx(R).
t31(R) :- dbg1m:pin(R).
fa(X, R) :- prolog_current_frame(F), prolog_frame_attribute(F, argument(1), A), R = A-X.
t32(R) :- fa(foo, R).
fb(_, R) :- prolog_current_frame(F), prolog_frame_attribute(F, argument(2), A), ( var(A) -> R = var ; R = A ).
t33(R) :- fb(foo, R).
fc(_, R) :- prolog_current_frame(F), ( prolog_frame_attribute(F, argument(1000), _) -> R = yes ; R = no ).
t34(R) :- fc(foo, R).
cl1(R) :- prolog_current_frame(F), prolog_frame_attribute(F, clause, C), clause(H, _, C), functor(H, N, A), R = N/A.
t35(R) :- cl1(R).
pa(R) :- pb(R0), R = R0.
pb(R) :- prolog_current_frame(F), prolog_frame_attribute(F, parent, P),
         prolog_frame_attribute(P, predicate_indicator, PI), prolog_frame_attribute(P, goal, G), G =.. [N|_], R = PI-N.
t36(R) :- pa(R).
pc1(R) :- pc2(R0), R = R0.
pc2(R) :- prolog_current_frame(F), ( prolog_frame_attribute(F, pc, PC) -> ( integer(PC) -> R = pc ; R = PC ) ; R = nopc ).
t37(R) :- pc1(R).
hc(_, R) :- prolog_current_frame(F), prolog_frame_attribute(F, has_alternatives, A), R = A.
hc(_, none).
t38(R) :- hc(_, R).
hd(a, R) :- prolog_current_frame(F), prolog_frame_attribute(F, has_alternatives, A), R = A.
hd(b, none).
t39(R) :- hd(a, R).
t40(R) :- prolog_current_frame(F), ( prolog_frame_attribute(F, alternative, A) -> ( prolog_frame_attribute(A, level, L), integer(L) -> R = frame ; R = A ) ; R = none ).
pg1(X, R) :- pg2(Y), R = X-Y.
pg2(R) :- prolog_current_frame(F), prolog_frame_attribute(F, parent_goal, pg1(A, _)), R = A.
t41(R) :- pg1(1, R).
pg3(X, R) :- pg4(Y), R = X-Y.
pg4(R) :- prolog_current_frame(F), prolog_frame_attribute(F, parent_goal(N), pg3(A, _)), integer(N), R = A.
t42(R) :- pg3(7, R).
pg5(X, R) :- pg6(Y), R = X-Y.
pg6(R) :- prolog_current_frame(F), ( prolog_frame_attribute(F, parent_goal, pg5(2, _)) -> R = yes ; R = no ).
t43(R) :- pg5(1, R).
pg7(R) :- prolog_current_frame(F), ( prolog_frame_attribute(F, parent_goal, nosuchpred_dbg1(_)) -> R = yes ; R = no ).
t44(R) :- pg7(R).
t45(R) :- ( prolog_frame_attribute(none, level, _) -> R = yes ; R = no ).
t46(R) :- prolog_current_frame(F),
          findall(X, ( member(G, [prolog_frame_attribute(foo, level, _), prolog_frame_attribute(_, level, _),
                                  prolog_frame_attribute(1000000000, level, _), prolog_frame_attribute(F, nosuch, _),
                                  prolog_frame_attribute(F, 1, _), prolog_frame_attribute(F, level(1), _),
                                  prolog_frame_attribute(F, argument(0), _), prolog_frame_attribute(F, argument(a), _),
                                  prolog_frame_attribute(F, argument(-1), _), prolog_frame_attribute(F, argument, _),
                                  prolog_frame_attribute(F, parent_goal(a, b), _), prolog_frame_attribute(F, _, _)]),
                       row(G, X) ), R).
t47(R) :- prolog_current_frame(F), ( prolog_frame_attribute(F, top, true) -> R = yes ; R = no ).
t48(R) :- prolog_current_frame(F), prolog_frame_attribute(F, level, user:L), ( integer(L) -> R = ok ; R = L ).
% ---- prolog_choice_attribute/3 (DBG1b) ----
ch(1).
ch(2).
t49(R) :- ch(X), X == 1, prolog_current_choice(C), prolog_choice_attribute(C, type, T), R = T.
t50(R) :- ch(X), X == 1, prolog_current_choice(C), prolog_choice_attribute(C, frame, Fr),
          prolog_frame_attribute(Fr, predicate_indicator, PI), R = PI.
t51(R) :- ch(X), X == 1, prolog_current_choice(C), prolog_choice_attribute(C, clause, Cl), clause(H, _, Cl), R = H.
t52(R) :- ch(X), X == 1, prolog_current_choice(C), ( prolog_choice_attribute(C, pc, PC) -> R = PC ; R = nopc ).
t53(R) :- ch(X), X == 1, prolog_current_choice(C), ( prolog_choice_attribute(C, parent, P) -> ( prolog_choice_attribute(P, type, T), atom(T) -> R = parent ; R = P ) ; R = noparent ).
t54(R) :- ( X = 1 ; X = 2 ), X == 1, prolog_current_choice(C), prolog_choice_attribute(C, type, T), R = T.
t55(R) :- ( X = 1 ; X = 2 ), X == 1, prolog_current_choice(C), ( prolog_choice_attribute(C, pc, PC), integer(PC) -> R = pc ; R = nopc ).
t56(R) :- ch(X), X == 1, prolog_current_choice(C),
          findall(E, ( member(G, [prolog_choice_attribute(foo, type, _), prolog_choice_attribute(_, type, _),
                                  prolog_choice_attribute(1000000000, type, _), prolog_choice_attribute(C, bad, _),
                                  prolog_choice_attribute(C, 1, _), prolog_choice_attribute(C, _, _)]),
                       row(G, E) ), R).
t57(R) :- ch(X), X == 1, prolog_current_choice(C), prolog_choice_attribute(C, type, T), ( memberchk(T, [jump, clause, top, catch, debug, foreign]) -> R = known ; R = T ).
% ---- rows for the mutants of DBG1b (tools/mutants/DBG1.py b-part) ----
% parent_goal: the arguments that unified in a frame that then failed are unbound again before the next frame is tried
pq(X, _, R) :- ( X == outer -> pq(inner, 2, R0), R = R0 ; pq2(R0), R = R0 ).
pq2(R) :- prolog_current_frame(F), prolog_frame_attribute(F, parent_goal, pq(A, 3, _)), R = A.
t58(R) :- pq(outer, 3, R).
% has_alternatives: a jump choice point of the frame (a disjunction) counts, once it is spent it does not
hj(R) :- prolog_current_frame(F), ( true ; true ), prolog_frame_attribute(F, has_alternatives, A), R = A.
t59(R) :- hj(R).
% context_module of a parent frame: the qualifier of a transparent predicate, not the context of the caller of prolog_frame_attribute/3
:- module_transparent trc/1.
trc(R) :- ctxof(R0), R = R0.
ctxof(R) :- prolog_current_frame(F), prolog_frame_attribute(F, parent, P),
            prolog_frame_attribute(P, context_module, M0), R = M0.
t60(R) :- dbg1m:trc(R).
% hidden: the frame of a system predicate (catch/3) is hidden, a user predicate's is not
hp(R) :- prolog_current_frame(F), prolog_frame_attribute(F, parent, P),
         prolog_frame_attribute(P, hidden, H), R = H.
t61(R) :- catch(hp(R), _, true).
