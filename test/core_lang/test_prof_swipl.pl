% ORIGINAL: the rows of test/core_lang/test_prof_swipl.jl (its predicates are pl-prof.c's: profiler/2, '$profile'/4, '$prof_statistics'/8,
% '$prof_node'/8, '$prof_sibling_of'/2, '$prof_procedure_data'/8, reset_profiler/0; '$prof_exact_ok'/1 and '$prof_clock_cost'/1 and a
% successful start are named refusals in the kernel and have no row in the .out).
% test/core_lang/test_prof_swipl.pl - PROF's rows. Each `tN(R)` is one row on a state that never profiled; test_prof_swipl.out holds
% swipl 10.1.20's answers (`ok`, then one line per row: its name and every solution), as the test's driver prints them. An error is
% caught inside the row and answered as err(Formal); a failure is answered as the atom `failed`.

err(G, R) :- catch(( G -> R = true ; R = failed ), error(E, _), R = err(E)).

% profiler/2: the state, and the argument checks
t0(R) :- err(profiler(X, false), R0), ( R0 == true -> R = X ; R = R0 ).
t1(R) :- err(profiler(_, foo), R).
t2(R) :- err(profiler(_, 1), R).
t3(R) :- err(profiler(false, false), R).
t4(R) :- err(profiler(true, _), R).
t5(R) :- err(profiler(_, _), R).
t6(R) :- err(profiler(_, "false"), R).

% '$prof_statistics'/8 on a state that never profiled (samples, ticks, accounting ticks, time, nodes, period, ports, mode)
t7(R) :- err('$prof_statistics'(S, T, A, Time, N, P, Po, M), R0), ( R0 == true -> R = s(S, T, A, Time, N, P, Po, M) ; R = R0 ).
t8(R) :- err('$prof_statistics'(0, 0, 0, 0.0, 0, _, _, false), R).
t9(R) :- err('$prof_statistics'(1, _, _, _, _, _, _, _), R).

% '$prof_node'/8: the node must be '$prof_node'(Ptr) of a node that exists
t10(R) :- err('$prof_node'(foo, _, _, _, _, _, _, _), R).
t11(R) :- err('$prof_node'('$prof_node'(1), _, _, _, _, _, _, _), R).
t12(R) :- err('$prof_node'(_, _, _, _, _, _, _, _), R).
t13(R) :- err('$prof_node'('$prof_node'(foo), _, _, _, _, _, _, _), R).
t14(R) :- err('$prof_node'('$prof_node'(0), _, _, _, _, _, _, _), R).

% '$prof_sibling_of'/2: no roots, no nodes
t15(R) :- err('$prof_sibling_of'(_, -), R).
t16(R) :- err('$prof_sibling_of'(foo, _), R).
t17(R) :- err('$prof_sibling_of'(_, foo), R).
t18(R) :- err('$prof_sibling_of'(_, '$prof_node'(1)), R).
t19(R) :- err('$prof_sibling_of'('$prof_node'(1), _), R).
t20(R) :- err('$prof_sibling_of'(_, _), R).

% '$prof_procedure_data'/8: the predicate indicator is looked up; nothing is known about it
t21(R) :- err('$prof_procedure_data'(foo/0, _, _, _, _, _, _, _), R).
t22(R) :- err('$prof_procedure_data'(t0/1, _, _, _, _, _, _, _), R).
t23(R) :- err('$prof_procedure_data'(foo, _, _, _, _, _, _, _), R).
t24(R) :- err('$prof_procedure_data'(_, _, _, _, _, _, _, _), R).
t25(R) :- err('$prof_procedure_data'(user:t0/1, _, _, _, _, _, _, _), R).
t26(R) :- err('$prof_procedure_data'(1/2, _, _, _, _, _, _, _), R).

% reset_profiler/0
t27(R) :- err(reset_profiler, R).
t28(R) :- err(( reset_profiler, '$prof_statistics'(0, 0, 0, _, 0, _, _, _) ), R).

% '$profile'/4 (Goal, Status, Ports, Rate): the options are checked before anything starts
t29(R) :- err('$profile'(true, foo, false, 100), R).
t30(R) :- err('$profile'(true, 1, false, 100), R).
t31(R) :- err('$profile'(true, _, false, 100), R).
t32(R) :- err('$profile'(true, cputime, 1, 100), R).
t33(R) :- err('$profile'(true, cputime, _, 100), R).
t34(R) :- err('$profile'(true, cputime, false, foo), R).
t35(R) :- err('$profile'(true, cputime, false, _), R).

% '$prof_exact_ok'/1: the atom check comes first (what follows reads the clock: a named refusal in the kernel)
t36(R) :- err('$prof_exact_ok'(1), R).
t37(R) :- err('$prof_exact_ok'(_), R).

% KERNEL-ONLY rows (no row in the .out): a hand-built call tree (test_prof_swipl.jl: nodes 1 = pf/1 with the children 2, 3 = pg/1),
% read through the predicates; `n(...)` rows strip the module the identifier carries.
pf(_).
pg(_).
pi_name(Id, N) :- ( Id = _:PI -> true ; PI = Id ), PI = N/1.

k0(R) :- '$prof_node'('$prof_node'(1), Id, C, Rd, E, Rc, T, S), pi_name(Id, N), R = n(N, C, Rd, E, Rc, T, S).
k1(R) :- '$prof_node'('$prof_node'(2), Id, C, Rd, E, Rc, T, S), pi_name(Id, N), R = n(N, C, Rd, E, Rc, T, S).
k2(R) :- '$prof_sibling_of'(R, -).
k3(R) :- '$prof_sibling_of'(R, '$prof_node'(1)).
k4(R) :- '$prof_sibling_of'('$prof_node'(3), R).
k5(R) :- err('$prof_sibling_of'('$prof_node'(1), _), R).
k6(R) :- '$prof_procedure_data'(pf/1, T, S, C, Rd, E, Cr, Ce), Ce = [node(Id, Cy, Ti, Si, Ca, Re, Ex)], pi_name(Id, N),
    R = d(T, S, C, Rd, E, Cr, N, Cy, Ti, Si, Ca, Re, Ex).
k7(R) :- '$prof_procedure_data'(pg/1, T, S, C, Rd, E, Cr, Ce), Cr = [node(Id, Cy, Ti, Si, Ca, Re, Ex)], pi_name(Id, N),
    R = d(T, S, C, Rd, E, Ce, N, Cy, Ti, Si, Ca, Re, Ex).
k8(R) :- err('$prof_procedure_data'(err/2, _, _, _, _, _, _, _), R).
k9(R) :- '$prof_statistics'(S, T, A, Time, N, P, Po, M), R = s(S, T, A, Time, N, P, Po, M).
% after reset_profiler: no node, nothing counted
k10(R) :- reset_profiler, '$prof_statistics'(S, T, A, _, N, _, _, _), R = r(S, T, A, N).
k11(R) :- err('$prof_node'('$prof_node'(1), _, _, _, _, _, _, _), R).
k12(R) :- err('$prof_sibling_of'(_, -), R).

% kernel-only: the collection is a named refusal (each row ends in NotPortedError, step PROF1)
kr0(R) :- profiler(R, true).
kr1(R) :- '$prof_exact_ok'(cputime), R = x.
kr2(R) :- '$prof_clock_cost'(R).
kr3(R) :- '$profile'(true, cputime, false, 100), R = x.
kr4(R) :- profiler(R, exact_cputime).
kr5(R) :- '$profile'(true, walltime, true, 4), R = x.
