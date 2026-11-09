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
% PIN1 step C (D-0447 item 4): the statistics keys of 10.1.20, `shared_table_space_used`, `erased_clauses`, `erased_clause_space`.
% `settle` moves the database generation past every erasure and runs clause GC twice, so a row compares the DELTA of the
% two erased-clause keys from a settled state (what the machine had erased before the row is not the row's business):
% a retract, an erase, an abolish and a retractall each raise the count by the clauses erased and the space by more than
% 8 bytes a clause (swipl: 112; the kernel counts its own bytes, so only the order is pinned), and
% clause GC returns both; a clause an open query still reads (t94) is not collected until that query is cut.
% Not here: a re-consult (the kernel refuses it until LB6b) and the absolute space (swipl's bytes are its own).
:- dynamic ef/1, eg/1, eh/1.
est(E, S) :- statistics(erased_clauses, E), statistics(erased_clause_space, S).
settle :- assertz(eh(1)), garbage_collect_clauses, assertz(eh(2)), garbage_collect_clauses.
edelta(E0, S0, R) :- est(E1, S1), D is E1-E0, ( S1 - S0 > 8*D -> U = up ; U = noup ), R = D-U.
eback(E0, S0, B) :- settle, est(E2, S2), ( E2 =:= E0, S2 =:= S0 -> B = back ; B = no(E0, E2, S0, S2) ).
t90(R) :- settle, est(E0, S0), assertz(ef(1)), assertz(ef(2)), assertz(ef(3)), retract(ef(1)), edelta(E0, S0, D), eback(E0, S0, B), R = [D, B].
t91(R) :- settle, est(E0, S0), assertz(ef(1), Ref), assertz(ef(2)), erase(Ref), edelta(E0, S0, D), eback(E0, S0, B), R = [D, B].
t92(R) :- settle, est(E0, S0), assertz(eg(1)), assertz(eg(2)), assertz(eg(3)), abolish(eg/1), edelta(E0, S0, D), eback(E0, S0, B), R = [D, B].
t93(R) :- settle, est(E0, S0), retractall(ef(_)), settle, est(E0b, S0b), assertz(ef(1)), assertz(ef(2)), retractall(ef(_)), edelta(E0b, S0b, D), eback(E0, S0, B), R = [E0b-S0b, D, B].
t94(R) :- settle, est(E0, S0), assertz(ef(1)), assertz(ef(2)), ef(_), retract(ef(1)), settle, edelta(E0, S0, D), !, eback(E0, S0, B), R = [D, B].
t95(R) :- settle, est(E0, S0), R = E0-S0.
t96(R) :- findall(K-V, ( member(K, [shared_table_space_used, table_space_used]), statistics(K, V) ), R).
t97(R) :- res(statistics(erased_clauses, [_]), R).
t98(R) :- res(statistics(shared_table_space_used, [_]), R).
t99(R) :- mem(K, [shared_table_space_used, erased_clauses, erased_clause_space]), stat(K, T), R = K-T.
% PIN1 step C (D-0447 item 5): the attributes `erased_clauses` and `erased_clause_space` of `$get_predicate_attribute`/3
% (pl-proc.c, 10.1.20). Each FAILS for a foreign predicate and for a definition with no erased clause, else answers the
% count and the bytes of the erased clauses clause GC has not yet returned. `eas` pins the count exactly and the space by
% its relations only: more than 8 bytes a clause and no more than the `size` of the predicate, which counts them (swipl:
% 112 bytes a clause; the kernel counts its own bytes). A row that erases from a `settle`d state runs on a predicate of its own.
:- dynamic ea1/1, ea2/1, ea3/1, ea4/1, ea5/1, ea6/1, ea7/1.
eas(H, R) :-
    ( '$get_predicate_attribute'(H, erased_clauses, E) -> true ; E = none ),
    (   '$get_predicate_attribute'(H, erased_clause_space, S)
    ->  (   integer(E), S > 8*E, '$get_predicate_attribute'(H, size, Z), S =< Z -> SS = ok ; SS = bad(S) )
    ;   SS = none
    ),
    R = E-SS.
t100(R) :- settle, assertz(ea1(1)), assertz(ea1(2)), eas(ea1(_), R).
t101(R) :- settle, assertz(ea2(1)), assertz(ea2(2)), assertz(ea2(3)), retract(ea2(1)), eas(ea2(_), R1), findall(X, ea2(X), L), R = R1-L.
t102(R) :- settle, assertz(ea3(1)), assertz(ea3(2)), retract(ea3(1)), eas(ea3(_), R1), retract(ea3(2)), eas(ea3(_), R2), settle, eas(ea3(_), R3), R = [R1, R2, R3].
t103(R) :- settle, assertz(ea4(1)), assertz(ea4(2)), assertz(ea4(3)), abolish(ea4/1), eas(ea4(_), R1), settle, eas(ea4(_), R2), R = R1-R2.
t104(R) :- settle, assertz(ea5(1)), assertz(ea5(2)), ea5(_), retract(ea5(1)), settle, eas(ea5(_), R1), !, settle, eas(ea5(_), R2), R = R1-R2.
t105(R) :- settle, assertz(ea6(1), Ref), assertz(ea6(2)), erase(Ref), eas(ea6(_), R1), res('$get_predicate_attribute'(ea6(_), erased_clauses, 2), R2), res('$get_predicate_attribute'(ea6(_), erased_clauses, 1), R3), R = [R1, R2, R3].
t106(R) :- eas(system:atom_length(_, _), R).
t107(R) :- eas(ea_no_such(_), R).
t108(R) :- eas(ea7(_), R).
t109(R) :- settle, assertz(ea7(1)), retract(ea7(1)), settle, eas(ea7(_), R).
