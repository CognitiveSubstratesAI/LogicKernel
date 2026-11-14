% ORIGINAL: the rows of test/core_lang/test_arith_wakeup_swipl.jl — no swipl-devel counterpart.
% test/core_lang/test_arith_wakeup_swipl.pl — AR1's rows for `A_IS` binding an ATTRIBUTED variable (pl-vmi.c A_IS ends in
% CHECK_WAKEUP, :4330-4339 at 18168e62): the clauses are compiled under `optimise`, so `X is Expr` is `A_ENTER .. A_IS` and the hook
% of X runs when A_IS binds it, before the goal after it. The hooks fixture is test/core_lang/test_attvar_wakeup.jl's (`no` fails,
% `throw(E)` throws, `log(Tag)` logs `Tag-Value`); `log/1` reads and clears the log. Each `tN(R)` is one row; the .out holds the pin's
% (swipl 10.1.20, 18168e62) answers: R is the answer term.
% UNTESTED on the kernel: written without a compile, the gate decides
:- set_prolog_flag(optimise, true).
:- dynamic hooklog/2.
attr_unify_hook(no, _) :- fail.
attr_unify_hook(yes, _).
attr_unify_hook(throw(E), _) :- throw(E).
attr_unify_hook(log(Tag), V) :- ( attvar(V) -> K = attvar ; var(V) -> K = var ; K = V ), assertz(hooklog(Tag, K)).
log(L) :- findall(T-K, hooklog(T, K), L), retractall(hooklog(_, _)).
% the hook runs at the binding
t0(R) :- retractall(hooklog(_, _)), put_attr(X, user, log(ai)), X is 1+2, log(R).
% ... before the goal after it (a FOREIGN call: a hook run late shows after `z-0`)
t1(R) :- retractall(hooklog(_, _)), put_attr(X, user, log(ai)), X is 1+2, assertz(hooklog(z, 0)), log(R).
% a hook that fails fails the `is`
t2(R) :- retractall(hooklog(_, _)), put_attr(X, user, no), ( X is 1+2 -> R = yes ; R = no ).
% a float result
t3(R) :- retractall(hooklog(_, _)), put_attr(X, user, log(ai)), X is 2.5*2, log(R).
% the operand is a variable (A_VAR), the result comes after a foreign call
t4(R) :- retractall(hooklog(_, _)), put_attr(X, user, log(ai)), Y = 3, X is Y+0, assertz(hooklog(z, 0)), log(R).
% a hook that throws: the exception is the `is`'s (the `is` is in t5b: a goal inside catch/3 is called, not compiled inline)
t5b(X) :- X is 1+2.
t5(R) :- retractall(hooklog(_, _)), put_attr(X, user, throw(boom)), catch(t5b(X), R, true).
% a hook that succeeds: the variable is bound
t6(R) :- retractall(hooklog(_, _)), put_attr(X, user, yes), X is 1+2, R = X.
% a bound X: no wakeup, the comparison is the result's
t7(R) :- retractall(hooklog(_, _)), put_attr(X, user, log(ai)), X = 3, log(L0), ( X is 1+2 -> R = L0 ; R = no ).
% the hook runs once, not at the comparison after it
t8(R) :- retractall(hooklog(_, _)), put_attr(X, user, log(ai)), X is 4+5, X =:= 9, assertz(hooklog(z, 0)), log(R).
