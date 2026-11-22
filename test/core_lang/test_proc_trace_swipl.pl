% ORIGINAL: the rows of test/core_lang/test_proc_trace_swipl.jl (its predicates are pl-proc.c's: '$cgc_params'/6, '$default_predicate'/2,
% copy_predicate_clauses/2).
% test/core_lang/test_proc_trace_swipl.pl - PROC-TRACE's rows. Each `tN(R)` is one row; test_proc_trace_swipl.out holds
% swipl 10.1.20's answers to them (the pin binary), as the test's driver prints them (`ok`, then one line per row: its name and
% every solution). The rows run IN ORDER, once, on the state the earlier rows left: every `$cgc_params` row restores the defaults
% (8, 0.03, 1.0) before it ends, and the last of them (t8) does so explicitly.
% Rows t0-t8 are '$cgc_params'/6, rows t9-t15 '$default_predicate'/2, rows t16-t34 copy_predicate_clauses/2.
% The ctx_* predicates at the end are no row: the LK-ONLY testsets of the test file run them (the C API's view of the stack).

% --- the modules the rows use (the directives build them) ---
:- dynamic cpa:f1/1.
:- dynamic cpa:r1/1.
:- dynamic cpa:self/1.
:- dynamic cpb:ap/1.
:- assertz(cpa:f1(1)).
:- assertz(cpa:f1(2)).
:- assertz(cpa:f1(3)).
:- assertz(cpa:r1(1)).
:- assertz(cpa:r1(2)).
:- assertz(cpa:r1(3)).
:- assertz(cpa:r1(4)).
:- assertz(cpa:self(1)).
:- assertz(cpa:self(2)).
:- assertz(cpa:baz(1)).
:- assertz(cpb:baz(2)).
:- assertz(cpx:baz(3)).
:- assertz(cpa:(p(X) :- baz(X))).
:- assertz(cpa:(q(X, Y) :- Y is X + 1, atom(foo))).
:- assertz(cpa:(ite(X, R) :- ( X > 0 -> baz(R) ; R = neg ))).
:- assertz(cpa:(ex(X) :- cpx:baz(X))).
:- assertz(cpa:(vs(X, Y) :- X = f(Y, Z), Z = 1)).
:- assertz(cpa:(two(X, Y) :- baz(X), baz(Y))).
:- assertz(cpa:(at(X) :- '@'(baz(X), cpa))).
:- assertz(cpb:ap(0)).
:- assertz(cpa:ap(1)).
:- assertz(cpa:ap(2)).
:- assertz(dpm1:dp_dummy(1)).
:- assertz(user:dp_q(1)).
:- catch(dpm4:dp_ghost(1), _, true).
cpa:sf(1).
cpa:sf(2).
cpa:st(1).

% the state of '$cgc_params' now, read and put back to the defaults in one call
cg_state(S, F, C) :- '$cgc_params'(S, F, C, 8, 0.03, 1.0).
% a goal's outcome: true, false or the error's formal term
cp_try(G, R) :- catch(( G -> R = true ; R = false ), error(E, _), R = E).

% --- '$cgc_params'/6: the old values come back in the first three arguments, the next three set the new ones ---
t0(R) :- cg_state(S, F, C), R = old(S, F, C).
t1(R) :- '$cgc_params'(S0, F0, C0, 5, 0.5, 2.0), cg_state(S1, F1, C1), R = r(S0, F0, C0, S1, F1, C1).
% integers for the float arguments
t2(R) :- '$cgc_params'(_, _, _, 3, 4, 5), cg_state(S, F, C), R = r(S, F, C).
% a type error on the first new value: no effect
t3(R) :- cp_try('$cgc_params'(_, _, _, foo, 0.5, 2.0), E), cg_state(S, F, C), R = r(E, S, F, C).
% a type error on the second: the first new value was set already
t4(R) :- cp_try('$cgc_params'(_, _, _, 4, bar, 2.0), E), cg_state(S, F, C), R = r(E, S, F, C).
% a type error on the third: the first two were set
t5(R) :- cp_try('$cgc_params'(_, _, _, 4, 0.7, baz), E), cg_state(S, F, C), R = r(E, S, F, C).
% an unbound new value
t6(R) :- cp_try('$cgc_params'(_, _, _, _, 0.5, 2.0), E), cg_state(S, F, C), R = r(E, S, F, C).
% the first argument does not unify: it fails before anything is set
t7(R) :- cp_try('$cgc_params'(9, _, _, 4, 0.5, 2.0), E), cg_state(S, F, C), R = r(E, S, F, C).
% a float with an integral value for the integer argument; then the defaults are put back last
t8(R) :- cp_try('$cgc_params'(_, _, _, 8.0, 0.25, 1.5), E), cg_state(S, F, C), R = r(E, S, F, C),
    '$cgc_params'(S2, F2, C2, 8, 0.03, 1.0), S2 == 8, F2 == 0.03, C2 == 1.0.

% --- '$default_predicate'/2: true when the first is the second's definition, or the first is not defined ---
t9(R) :- cp_try('$default_predicate'(dp_q(_), dp_q(_)), R).
% m1 has no dp_q of its own: it is the user's
t10(R) :- cp_try('$default_predicate'(dpm1:dp_q(_), dp_q(_)), R).
% a module with its own, defined dp_q: no
t11(R) :- assertz(dpm2:dp_q(2)), cp_try('$default_predicate'(dpm2:dp_q(_), dp_q(_)), R).
t12(R) :- cp_try('$default_predicate'(system:true, true), R).
% the first exists but is undefined
t13(R) :- cp_try('$default_predicate'(dpm4:dp_ghost(_), dp_q(_)), R).
% the first does not exist at all
t14(R) :- cp_try('$default_predicate'(dp_never_seen_zz(_), dp_q(_)), R).
% arguments that are no heads
t15(R) :- cp_try('$default_predicate'(_, dp_q(_)), R1), cp_try('$default_predicate'(3, dp_q(_)), R2),
    cp_try('$default_predicate'(dp_q(_), _), R3), R = r(R1, R2, R3).

% --- copy_predicate_clauses/2 ---
t16(R) :- copy_predicate_clauses(cpa:f1/1, cpa:g1/1), findall(X, cpa:g1(X), L), R = L.
% only the visible clauses: 2 is retracted before the copy
t17(R) :- retract(cpa:r1(2)), copy_predicate_clauses(cpa:r1/1, cpa:r1c/1), findall(X, cpa:r1c(X), L),
    findall(X, cpa:r1(X), L0), R = L0-L.
% a body calling a local predicate, copied to a module with its own baz/1
t18(R) :- copy_predicate_clauses(cpa:p/1, cpb:p/1), findall(X, cpb:p(X), L2), findall(X, cpa:p(X), L1), R = L1-L2.
% the copy's body as clause/2 shows it
t19(R) :- findall(H-B, clause(cpb:p(H), B), L), R = L.
% a body calling system predicates
t20(R) :- copy_predicate_clauses(cpa:q/2, cpb:q/2), cpb:q(1, Y), R = Y.
% an if-then-else body (the then branch calls baz/1)
t21(R) :- copy_predicate_clauses(cpa:ite/2, cpb:ite/2), cpb:ite(1, R1), cpb:ite(0, R2), R = R1-R2.
% an explicit module call cpx:baz(X): which baz/1 does the copy call?
t22(R) :- copy_predicate_clauses(cpa:ex/1, cpb:ex/1), findall(X, cpb:ex(X), L2), findall(X, cpa:ex(X), L1), R = L1-L2.
% onto an existing dynamic predicate: appended
t23(R) :- copy_predicate_clauses(cpa:ap/1, cpb:ap/1), findall(X, cpb:ap(X), L), R = L.
% from a static predicate
t24(R) :- copy_predicate_clauses(cpa:sf/1, cpb:sf/1), findall(X, cpb:sf(X), L), R = L.
% variables shared between head and body
t25(R) :- copy_predicate_clauses(cpa:vs/2, cpb:vs/2), cpb:vs(A, B), R = A-B.
% from a foreign predicate
t26(R) :- cp_try(copy_predicate_clauses(atom_length/2, cpb:zz_f/2), R).
% onto a static predicate that has clauses
t27(R) :- cp_try(copy_predicate_clauses(cpa:f1/1, cpa:st/1), R).
% onto a foreign predicate
t28(R) :- cp_try(copy_predicate_clauses(cpa:f1/1, atom_length/2), R).
% an undefined source: the destination is created, dynamic and empty
t29(R) :- copy_predicate_clauses(cpa:zz_nosrc/1, cpb:zz_dst/1), '$get_predicate_attribute'(cpb:zz_dst(_), dynamic, V),
    findall(X, cpb:zz_dst(X), L), R = V-L.
% arguments that are no name/arity
t30(R) :- cp_try(copy_predicate_clauses(_, cpb:zz_a/1), R1), cp_try(copy_predicate_clauses(cpa:f1/1, _), R2),
    cp_try(copy_predicate_clauses(foo, cpb:zz_b/1), R3), cp_try(copy_predicate_clauses(cpa:f1/1, bar), R4),
    R = r(R1, R2, R3, R4).
% onto itself: the clauses added meanwhile are of a later generation, the copy sees the ones present at the start
t31(R) :- copy_predicate_clauses(cpa:self/1, cpa:self/1), findall(X, cpa:self(X), L), R = L.
% the source's order, and a source copied twice
t32(R) :- copy_predicate_clauses(cpa:f1/1, cpb:twice/1), copy_predicate_clauses(cpa:f1/1, cpb:twice/1),
    findall(X, cpb:twice(X), L), R = L.
% a call that is not the last goal (a different call instruction from the last call's)
t33(R) :- copy_predicate_clauses(cpa:two/2, cpb:two/2), findall(X-Y, cpb:two(X, Y), L2), findall(X-Y, cpa:two(X, Y), L1), R = L1-L2.
% a goal run in a named module (`@/2`): the module operand names the module the clauses are copied from
t34(R) :- copy_predicate_clauses(cpa:at/1, cpb:at/1), findall(X, cpb:at(X), L2), findall(X, cpa:at(X), L1), R = L1-L2.

% --- not rows: the stack the LK-ONLY testsets of the test file look at (a choice point keeps every frame) ---
ctx_a(F) :- ctx_b(F).
ctx_b(F) :- ctx_c(F).
ctx_c(F) :- prolog_current_frame(F), member(_, [1, 2]).
ctx_f(1) :- repeat.
