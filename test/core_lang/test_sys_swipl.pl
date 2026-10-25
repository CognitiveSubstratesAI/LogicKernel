% ORIGINAL: the rows of test/core_lang/test_sys_swipl.jl — no swipl-devel counterpart.
% test/core_lang/test_sys_swipl.pl — Y1's rows (getenv/2, setenv/2, unsetenv/1, get_time/1, sleep/1, statistics/2,
% delete_file/1). Each `tN(R)` is one row; test_sys_swipl.out holds swipl 10.1.19's answers to them, as the test's driver
% prints them (`ok`, then one line per row: its name and every solution). Environment-dependent values (the time, the
% CPU, the stacks, the environment) are compared by TYPE or by an order; the rest exactly. The files `lk_y1_victim`,
% `lk_y1_emptydir` and `lk_y1_nonempty_dir/inner` are made by the test in the working directory, as the .out was made.
ty(V, int) :- integer(V), !.
ty(V, float) :- float(V), !.
ty(V, L) :- is_list(V), !, tys(V, L).
ty(_, other).
tys([], []).
tys([X|Xs], [T|Ts]) :- ty(X, T), tys(Xs, Ts).
stat(K, T) :- statistics(K, V), ty(V, T).
rep(0, []) :- !.
rep(N, [97|T]) :- N1 is N-1, rep(N1, T).
mem(X, [X|_]).
mem(X, [_|T]) :- mem(X, T).
res(G, R) :- catch(( G -> R = true ; R = false ), error(E, C), R = error(E, C)).
t0(R) :- statistics(walltime, [T, D]), ( T =:= D -> R = ok ; R = no(T, D) ).
t1(R) :- statistics(real_time, [T, D]), ( T =:= D -> R = ok ; R = no(T, D) ).
t2(R) :- statistics(runtime, [T, D]), ( T =:= D -> R = ok ; R = no(T, D) ).
t3(R) :- statistics(system_time, [T, D]), ( T =:= 0, D =:= 0 -> R = ok ; R = no(T, D) ).
t4(R) :- mem(K, [self_cputime, cputime, process_cputime, self_inferences, inferences, stack, stack_limit, local, localused, trail, trailused, global, globalused, c_stack, atoms, atom_space, functors, functor_space, predicates, clauses, modules, codes, epoch, process_epoch, gctime, collections, collected, heapused, agc, agc_gained, agc_time, cgc, cgc_gained, cgc_time, global_shifts, local_shifts, trail_shifts, shift_time, threads, engines, threads_created, engines_created, thread_cputime, threads_peak, table_space_used, indexes_created, indexes_destroyed, warnings, errors]), stat(K, T), R = K-T.
t5(R) :- mem(K, [runtime, system_time, real_time, walltime, memory, core, stacks, global_stack, local_stack, trail, program, garbage_collection, stack_shifts, atoms, atom_garbage_collection, clause_garbage_collection]), stat(K, T), R = K-T.
t6(R) :- mem(K, [runtime, system_time, real_time, walltime, memory, core, stacks, global_stack, local_stack, trail, program, garbage_collection, stack_shifts, atoms, atom_garbage_collection, clause_garbage_collection]), V = [_|_], statistics(K, V), ty(V, T), R = K-T.
t7(R) :- res(statistics(foo, _), R).
t8(R) :- res(statistics(_, _), R).
t9(R) :- res(statistics(1, _), R).
t10(R) :- res(statistics("atoms", _), R).
t11(R) :- res(statistics([], _), R).
t12(R) :- res(statistics(cputime, [_|_]), R).
t13(R) :- res(statistics(runtime, foo), R).
t14(R) :- res(statistics(runtime, [_, _, _]), R).
t15(R) :- statistics(runtime, [X]), ty(X, R).
t16(R) :- statistics(atoms, [A, B, C]), ty([A, B, C], R).
t17(R) :- statistics(inferences, A), functor(_, f, 2), statistics(inferences, B), ( B > A -> R = up ; R = same ).
t18(R) :- statistics(self_inferences, A), functor(_, f, 2), statistics(self_inferences, B), ( B > A -> R = up ; R = same ).
t19(R) :- statistics(cputime, A), statistics(cputime, B), ( B >= A -> R = ok ; R = down ).
t20(R) :- statistics(cputime, T), ( T > 0.0, T < 1000000.0 -> R = ok ; R = no(T) ).
t21(R) :- statistics(process_cputime, T), ( T > 0.0, T < 1000000.0 -> R = ok ; R = no(T) ).
t22(R) :- statistics(real_time, [T, _]), ( T > 1000000000 -> R = ok ; R = no(T) ).
t23(R) :- statistics(walltime, [T0, _]), sleep(0.05), statistics(walltime, [T1, D]), ( T1 > T0, D >= 40 -> R = ok ; R = no ).
t24(R) :- statistics(epoch, E), get_time(N), ( E > 1000000000.0, E =< N -> R = ok ; R = no ).
t25(R) :- statistics(runtime, [T, D]), ( T > 0, T >= D, D >= 0 -> R = ok ; R = no(T, D) ).
t26(R) :- statistics(runtime, [T1, _]), statistics(runtime, [T2, D2]), ( D2 =:= T2 - T1 -> R = ok ; R = no(T1, T2, D2) ).
t27(R) :- statistics(real_time, [T1, _]), statistics(real_time, [T2, D2]), ( D2 =:= T2 - T1 -> R = ok ; R = no(T1, T2, D2) ).
t28(R) :- statistics(walltime, [T1, _]), statistics(walltime, [T2, D2]), ( abs(D2 - (T2 - T1)) =< 1 -> R = ok ; R = no(T1, T2, D2) ).
t29(R) :- statistics(stack_limit, L), ( L =:= 1073741824 -> R = ok ; R = no(L) ).
t30(R) :- statistics(inferences, A), ( between(1, 50, _), fail ; true ), statistics(inferences, B), D is B - A, ( D >= 50 -> R = ok ; R = no(D) ).
t31(R) :- res(getenv(lk_y1_nonexistent, _), R).
t32(R) :- res(getenv(_, _), R).
t33(R) :- res(getenv(f(x), _), R).
t34(R) :- res(getenv(1, _), R).
t35(R) :- res(getenv([], _), R).
t36(R) :- res(getenv('', _), R).
t37(R) :- res(( getenv("PATH", X), atom(X) ), R).
t38(R) :- res(( getenv([80, 65, 84, 72], X), atom(X) ), R).
t39(R) :- setenv(lk_y1_a, abc), getenv(lk_y1_a, R).
t40(R) :- setenv(lk_y1_a, 12), getenv(lk_y1_a, R).
t41(R) :- setenv(lk_y1_a, "str"), getenv(lk_y1_a, R).
t42(R) :- setenv(lk_y1_a, one), setenv(lk_y1_a, two), getenv(lk_y1_a, R).
t43(R) :- setenv(lk_y1_a, ''), getenv(lk_y1_a, R).
t44(R) :- setenv(lk_y1_a, abc), res(getenv(lk_y1_a, xyz), R).
t45(R) :- setenv(lk_y1_a, [120, 0, 121]), getenv(lk_y1_a, R).
t46(R) :- res(setenv(lk_y1_a, f(x)), R).
t47(R) :- res(setenv(_, a), R).
t48(R) :- res(setenv(a, _), R).
t49(R) :- res(setenv('a=b', c), R).
t50(R) :- res(setenv('', c), R).
t51(R) :- setenv(lk_y1_a, x), unsetenv(lk_y1_a), res(getenv(lk_y1_a, _), R).
t52(R) :- res(unsetenv(lk_y1_none), R).
t53(R) :- res(unsetenv(_), R).
t54(R) :- res(unsetenv(f(x)), R).
t55(R) :- res(unsetenv('a=b'), R).
t56(R) :- res(unsetenv(''), R).
t57(R) :- get_time(T), ( float(T), T > 1000000000.0 -> R = ok ; R = no(T) ).
t58(R) :- res(get_time(1), R).
t59(R) :- res(get_time(a), R).
t60(R) :- get_time(A), get_time(B), ( B >= A -> R = ok ; R = down ).
t61(R) :- res(sleep(0), R).
t62(R) :- res(sleep(0.0), R).
t63(R) :- res(sleep(-0.0), R).
t64(R) :- res(sleep(-1), R).
t65(R) :- res(sleep(-0.5), R).
t66(R) :- res(sleep(0.01), R).
t67(R) :- res(sleep(1.0e-9), R).
t68(R) :- res(sleep(1r100), R).
t69(R) :- res(sleep(a), R).
t70(R) :- res(sleep(_), R).
t71(R) :- res(sleep("0.01"), R).
t72(R) :- res(sleep(f(x)), R).
t73(R) :- X is nan, res(sleep(X), R).
t74(R) :- X is inf, res(sleep(X), R).
t75(R) :- get_time(A), sleep(0.2), get_time(B), D is B - A, ( D >= 0.15, D < 5.0 -> R = ok ; R = no(D) ).
t76(R) :- get_time(A), sleep(-1), get_time(B), D is B - A, ( D >= 0.0, D < 0.15 -> R = ok ; R = no(D) ).
t77(R) :- res(delete_file(lk_y1_nonexistent), R).
t78(R) :- res(delete_file(_), R).
t79(R) :- res(delete_file(f(x)), R).
t80(R) :- res(delete_file(1), R).
t81(R) :- res(delete_file('lk_y1_no_dir/x'), R).
t82(R) :- res(delete_file("lk_y1_nonexistent_s"), R).
t83(R) :- res(delete_file([108, 107]), R).
t84(R) :- res(delete_file(''), R).
t85(R) :- res(delete_file([97, 0, 98]), R).
t86(R) :- rep(5000, L), res(delete_file(L), R).
t87(R) :- res(delete_file(lk_y1_nonempty_dir), R).
t88(R) :- res(delete_file(lk_y1_victim), R1), res(delete_file(lk_y1_victim), R2), R = R1-R2.
t89(R) :- res(delete_file(lk_y1_emptydir), R).
