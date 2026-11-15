% ORIGINAL: the rows of test/core_lang/test_format_predicate_swipl.jl - no swipl-devel counterpart.
% test/core_lang/test_format_predicate_swipl.pl - format_predicate/2, current_format_predicate/2 and the user directive in
% format/2,3 (pl-fmt.c :249-325 and the directive lookup of do_format, :596-621). Each `tN(R)` is one row, run in order, in one
% database (the table is global state: the rows that take over a built-in directive come last). The predicates the directives call
% write with write/1, never format/2, so a directive that replaces ~w or ~a cannot recurse. Answers: yes(Value) | no | ex(Formal)
% | ball(Ball). Pinned from swipl 10.1.20 (the pin's build).
% UNVERIFIED on the kernel: gate decides
:- dynamic seen/1.
fp_x(Arg, V) :- write('<'), write(Arg), write('|'), write(V), write('>').
fp_x2(Arg, V) :- write('['), write(Arg), write('|'), write(V), write(']').
fp_y(Arg) :- write(y(Arg)).
fp_z(Arg, A, B) :- write('('), write(Arg), write(','), write(A), write(','), write(B), write(')').
fp_fail(_, _) :- fail.
fp_throw(_, _) :- throw(oops).
fp_seen(Arg, V) :- assertz(seen(Arg-V)), write(s).
fp_col(_, V) :- write(V), nl, write(V).
m2:fp_w(Arg, V) :- write('{'), write(Arg), write('|'), write(V), write('}').
res(G, R) :- catch(( G -> R = yes ; R = no ), E, ( E = error(F, _) -> R = ex(F) ; R = ball(E) )).
ans(G, V, R) :- catch(( G -> R = yes(V) ; R = no ), E, ( E = error(F, _) -> R = ex(F) ; R = ball(E) )).
fa(F, Args, R) :- ans(format(atom(A), F, Args), A, R).
cfp(L) :- findall(S, ( current_format_predicate(_, H), strip_module(H, M, P), functor(P, N, Ar), format(atom(S), "~w:~w/~w", [M, N, Ar]) ), L0), msort(L0, L1), atomic_list_concat(L1, ',', L).
t1(R) :- res(format_predicate(x, fp_x(_, _)), R).
t2(R) :- fa("a~xb", [v], R).
t3(R) :- fa("~3x", [v], R).
t4(R) :- fa("~`zx", [v], R).
t5(R) :- fa("~*x", [5, v], R).
t6(R) :- fa("~-3x", [v], R).
t7(R) :- fa("~:x", [v], R).
t8(R) :- fa("~x~x", [p, q], R).
t9(R) :- fa("~x", [], R).
t10(R) :- fa("~x", [a, b], R).
t11(R) :- res(format_predicate(y, fp_y(_)), R).
t12(R) :- fa("a~yb~w", [c], R).
t13(R) :- res(format_predicate(z, fp_z(_, _, _)), R).
t14(R) :- fa("~2z", [p, q], R).
t15(R) :- fa("~z", [p], R).
t16(R) :- res(format_predicate(m, m2:fp_w(_, _)), R).
t17(R) :- fa("~m", [k], R).
t18(R) :- ans(cfp(L), L, R).
t19(R) :- res(current_format_predicate(0'x, _), R).
t20(R) :- res(current_format_predicate(0'q, _), R).
t21(R) :- res(current_format_predicate(x, _), R).
t22(R) :- ans(( current_format_predicate(C, fp_y(_)), integer(C), C =\= 0'y ), ok, R).
t23(R) :- ans(( findall(C, current_format_predicate(C, _), L), length(L, N) ), N, R).
t24(R) :- res(current_format_predicate(_, m2:fp_x(_, _)), R).
t25(R) :- res(current_format_predicate(_, user:fp_x(_, _)), R).
t26(R) :- ans(( current_format_predicate(_, H), strip_module(H, M, P), P = fp_w(_, _) ), M, R).
t27(R) :- ans(( current_format_predicate(_, _), ! ), ok, R).
t28(R) :- res(format_predicate(1.5, fp_x(_, _)), R).
t29(R) :- res(format_predicate(_, fp_x(_, _)), R).
t30(R) :- res(format_predicate(xy, fp_x(_, _)), R).
t31(R) :- res(format_predicate(0'j, fp_x(_, _)), R).
t32(R) :- fa("~j", [v], R).
t33(R) :- res(format_predicate(x, fp_noargs), R).
t34(R) :- res(format_predicate(x, 3), R).
t35(R) :- res(format_predicate(x, _), R).
t36(R) :- res(format_predicate(x, fp_x2(_, _)), R).
t37(R) :- fa("~x", [v], R).
t38(R) :- ans(( current_format_predicate(_, H), H = fp_x2(_, _) ), ok, R).
t39(R) :- ans(( findall(C, current_format_predicate(C, _), L), length(L, N) ), N, R).
t40(R) :- res(format_predicate(u, fp_fail(_, _)), R).
t41(R) :- fa("a~ub", [v], R).
t42(R) :- res(format_predicate(0'l, fp_throw(_, _)), R).
t43(R) :- fa("a~lb", [v], R).
t44(R) :- res(format_predicate(v, fp_seen(_, _)), R).
t45(R) :- fa("~5v~v", [q, r], R).
t46(R) :- findall(A-V, seen(A-V), L), format(atom(R), "~w", [L]).
t47(R) :- res(format_predicate(l, fp_col(_, _)), R).
t48(R) :- fa("ab~lcd", [v], R0), ( R0 = yes(A) -> atomic_list_concat(P, '\n', A), atomic_list_concat(P, '/', B), R = yes(B) ; R = R0 ).
t49(R) :- fa("~t~x~12|", [v], R).
t50(R) :- fa("~x~t~12|end", [v], R).
t51(R) :- fa("~a~x~a", [p, q, r], R).
t52(R) :- res(format_predicate(a, fp_x2(_, _)), R).
t53(R) :- fa("~a", [v], R).
t54(R) :- res(format_predicate(c, fp_x(_, _)), R).
t55(R) :- fa("~c~3c", [65, 66], R).
t56(R) :- ans(cfp(L), L, R).
