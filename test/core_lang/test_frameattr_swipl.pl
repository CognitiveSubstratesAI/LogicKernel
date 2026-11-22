% ORIGINAL: the rows of test/core_lang/test_frameattr_swipl.jl (their predicate is pl-trace.c's prolog_frame_attribute/3).
% test/core_lang/test_frameattr_swipl.pl - the rows of prolog_frame_attribute/3 (the old line's DBG1b rows t24-t48, t58-t65; the
% row names are kept so that its mutants' KILL lists read the same). Each `tN(R)` is one row; test_frameattr_swipl.out holds the
% pin's swipl (10.1.20) answers to them as the test's driver prints them (`ok`, then one line per row: its name and every solution).
% Rows t24-t48: the keys of prolog_frame_attribute/3; t58-t61: the rows the old mutants' b-part needed; t62, t63: a frame that is both
% a cleanup frame and a watched one; t64, t65: hidden for a user and for a system frame. None prints a frame number.

% a row's own error is its answer
row(Goal, R) :- catch(Goal, error(E, _), R = raised(E)).
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

% ---- rows for the mutants of DBG1b (tools/mutants/FRAMEATTR.py) ----
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
% a frame that is both a cleanup frame (FR_CLEANUP: setup_call_cleanup/3 runs its handler when the goal exits) and a watched one
% (FR_NOTIFY: prolog_frame_attribute/3 sets it on the frame it reads, pl-trace.c:2509) exits deterministically with its handler run.
% The answer is the frame's predicate indicator and the handler's effect (a global variable): no frame number is printed.
cc_frame(F, CF) :- prolog_frame_attribute(F, predicate_indicator, PI),
                   ( PI = system:setup_call_cleanup/3 -> CF = F
                   ; prolog_frame_attribute(F, parent, P), cc_frame(P, CF) ).
cc_read(R) :- prolog_current_frame(F), cc_frame(F, CF),
              prolog_frame_attribute(CF, predicate_indicator, _:N/A), R = N/A.
% read from the goal: FR_CLEANUP is set already (I_CALLCLEANUP), FR_NOTIFY is set while the goal runs
t62(R) :- nb_setval(dbg1_h, none), setup_call_cleanup(true, cc_read(R0), nb_setval(dbg1_h, ran)), nb_getval(dbg1_h, H), R = R0-H.
% read from the setup, before the goal runs at all: FR_NOTIFY is set before FR_CLEANUP
t63(R) :- nb_setval(dbg1_h, none), setup_call_cleanup(cc_read(R0), true, nb_setval(dbg1_h, ran)), nb_getval(dbg1_h, H), R = R0-H.
% ---- rows for the mutants FRAMEATTR-d1/d2 (lookupProcedure's TRACE_ME) ----
% hidden: a USER predicate's frame (its own, read from inside it) is not hidden ...
hu(R) :- prolog_current_frame(F), prolog_frame_attribute(F, hidden, H), R = H.
t64(R) :- hu(R).
% ... the frame of a SYSTEM predicate called by a system predicate is: findall/3's loop ($bags:findall_loop/4) is the parent of its goal's frame
% (the answer names the predicate read, so a different parent cannot pass as hidden). A system predicate that a user predicate calls without
% last-call optimisation reads hidden=false in swipl (pl-trace.c isDebugFrame: "user calls system"); t61 has the last-call case.
hf(R) :- prolog_current_frame(F), prolog_frame_attribute(F, parent, P),
         prolog_frame_attribute(P, predicate_indicator, PI), prolog_frame_attribute(P, hidden, H), R = PI-H.
t65(R) :- findall(X, hf(X), [R]).
