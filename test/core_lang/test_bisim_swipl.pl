% ORIGINAL: the rows of test/core_lang/test_bisim_swipl.jl (its predicates are pl-bisim.c's: term_factorized/3,4, term_minimal/2,
% '$term_canonical_form'/2, term_automaton/2, automaton_minimal/2,3).
% test/core_lang/test_bisim_swipl.pl - BISIM's rows. Each `tN(R)` is one row; test_bisim_swipl.out holds swipl 10.1.20's answers
% (`ok`, then one line per row: its name and every solution), as the test's driver prints them. A cyclic term is never an answer
% (the encoder would not end): a row that builds one reads it back through term_factorized/3,4 or a comparison. An error is
% caught inside the row and answered as err(Formal); a failure is answered as the atom `failed`.

err(G, R) :- catch(( G -> R = true ; R = failed ), error(E, _), R = err(E)).

% term_factorized/3,4
t0(R) :- X = f(X), term_factorized(X, S, Sub), R = r(S, Sub).
t1(R) :- Y = g(a, b), T = f(Y, Y), term_factorized(T, S, Sub), R = r(S, Sub).
t2(R) :- T = f(g(a), g(a)), term_factorized(T, S, Sub), R = r(S, Sub).
t3(R) :- T = f('$VAR'(1), '$VAR'(1), g(a), g(a)), term_factorized(T, S, Sub), R = r(S, Sub).
t4(R) :- T = f(g(a), g(a)), term_factorized(T, S, Sub, [minimal(false)]), R = r(S, Sub).
t5(R) :- Y = g(a), T = f(Y, Y), term_factorized(T, S, Sub, [minimal(false)]), R = r(S, Sub).
t6(R) :- T = f('$VAR'(1), '$VAR'(1)), term_factorized(T, S, Sub, [dollar_var(false)]), R = r(S, Sub).
t7(R) :- X = f(X, a), term_factorized(X, S, Sub, [minimal(false)]), R = r(S, Sub).
t8(R) :- X = f(f(X, a), a), term_factorized(X, S, Sub), R = r(S, Sub).
t9(R) :- X = f(f(X, a), a), term_factorized(X, S, Sub, [minimal(false)]), R = r(S, Sub).
t10(R) :- term_factorized(a, S, Sub), R = r(S, Sub).
t11(R) :- term_factorized(X, S, Sub), R = r(S, Sub, X).
t12(R) :- T = f(X, Y, X), term_factorized(T, S, Sub), R = r(S, Sub, Y).
t13(R) :- T = h(X, g(X), g(X)), term_factorized(T, S, Sub), R = r(S, Sub).
t14(R) :- term_factorized(f(a), S, Sub), R = r(S, Sub).
t15(R) :- err(term_factorized(f(a), _, _, [minimal(maybe)]), R).
t16(R) :- err(term_factorized(f(a), _, _, foo), R).
t17(R) :- T = f(g(a), g(a)), term_factorized(T, S, Sub, [minimal(true), dollar_var(true)]), R = r(S, Sub).

% term_minimal/2
t18(R) :- term_minimal(f(g(a), g(a)), M), R = M.
t19(R) :- term_minimal(f(g(a), g(a)), M), term_factorized(M, S, Sub, [minimal(false)]), R = r(S, Sub).
t20(R) :- X = f(f(X, a), a), term_minimal(X, M), term_factorized(M, S, Sub, [minimal(false)]), R = r(S, Sub).
t21(R) :- term_minimal(foo, M), R = M.
t22(R) :- term_minimal(Y, M), ( M == Y -> R = same ; R = diff ).
t23(R) :- term_minimal(f(X, Y, X), M), R = r(M, Y).
t24(R) :- X = f(f(X, a), a), term_minimal(X, M), ( M == X -> R = same ; R = diff ).

% '$term_canonical_form'/2
t25(R) :- '$term_canonical_form'(f(X, Y, X), F), R = r(F, Y).
t26(R) :- X = f(X), '$term_canonical_form'(X, F), R = F.
t27(R) :- X = f(f(X)), Y = f(Y), '$term_canonical_form'(X, F1), '$term_canonical_form'(Y, F2), ( F1 == F2 -> R = same ; R = diff ).
t28(R) :- '$term_canonical_form'(a, F), R = F.
t29(R) :- '$term_canonical_form'(f(A, _, A), F1), '$term_canonical_form'(f(C, _, C), F2), ( F1 == F2 -> R = same ; R = diff ).
t30(R) :- '$term_canonical_form'(f(A, B, A), F1), '$term_canonical_form'(f(A, B, B), F2), ( F1 == F2 -> R = same ; R = diff ).
t31(R) :- X = f(X, a), Y = f(f(Y, a), a), '$term_canonical_form'(X, F1), '$term_canonical_form'(Y, F2), ( F1 == F2 -> R = same ; R = diff ).

% term_automaton/2, term to automaton
t32(R) :- term_automaton(f(a, b), A), R = A.
t33(R) :- term_automaton(f(g(a), g(a)), A), R = A.
t34(R) :- T = f(T), term_automaton(T, A), R = A.
t35(R) :- term_automaton(X, A), R = r(A, X).
t36(R) :- term_automaton(f(X, X), A), R = A.
t37(R) :- Y = g(a), T = f(Y, Y), term_automaton(T, A), R = A.
% term_automaton/2, automaton to term
t38(R) :- term_automaton(T, automaton(f(2, 3), a, b)), R = T.
t39(R) :- term_automaton(T, automaton(f(1, 2), a)), term_factorized(T, S, Sub), R = r(S, Sub).
t40(R) :- term_automaton(T, automaton(a)), R = T.
t41(R) :- term_automaton(T, automaton(f(2), _)), R = T.
t42(R) :- term_automaton(T, automaton(f(2), a)), R = T.
t43(R) :- term_automaton(f(a, b), automaton(f(2, 3), a, b)), R = ok.
t44(R) :- err(term_automaton(f(a, b), automaton(f(3, 2), a, b)), R).
t45(R) :- term_automaton(T, automaton(f(2, 2), g(3), a)), R = T.

% automaton_minimal/2,3
t46(R) :- automaton_minimal(automaton(f(2, 3), g(4), g(4), a), M), R = M.
t47(R) :- automaton_minimal(automaton(f(2, 3), g(4), g(4), a), M, Map), R = r(M, Map).
t48(R) :- automaton_minimal(automaton(a, b), M, Map), R = r(M, Map).
t49(R) :- automaton_minimal(automaton(f(2), a, b, c), M, Map), R = r(M, Map).
t50(R) :- automaton_minimal(automaton(f(1)), M), R = M.
t51(R) :- automaton_minimal(automaton(f(2), f(1)), M, Map), R = r(M, Map).
t52(R) :- automaton_minimal(automaton(f(2), g(1)), M), R = M.
t53(R) :- A = automaton(f(2, 3), g(4), g(4), a), automaton_minimal(A, M), automaton_minimal(M, M2), ( M == M2 -> R = same ; R = diff ).
t54(R) :- automaton_minimal(automaton(f(2, 2), _), M), R = M.
t55(R) :- automaton_minimal(automaton(f(2, 3), _, _), M, Map), R = r(M, Map).
t56(R) :- automaton_minimal(automaton(f(2), 1), M), R = M.
t57(R) :- automaton_minimal(automaton(f(2), "s"), M), R = M.
t58(R) :- automaton_minimal(automaton(f(2, 3, 4), g(4), g(4), a, b), M, Map), R = r(M, Map).
t59(R) :- err(automaton_minimal(automaton(a), _, bad), R).
t60(R) :- automaton_minimal(automaton(a), M, Map), R = r(M, Map).

% errors
t61(R) :- err(automaton_minimal(_, _), R).
t62(R) :- err(automaton_minimal(foo, _), R).
t63(R) :- compound_name_arguments(A, automaton, []), err(automaton_minimal(A, _), R).
t64(R) :- err(automaton_minimal(automaton(f(_), a), _), R).
t65(R) :- err(automaton_minimal(automaton(f(x), a), _), R).
t66(R) :- err(automaton_minimal(automaton(f(5), a), _), R).
t67(R) :- err(automaton_minimal(automaton(f(0), a), _), R).
t68(R) :- err(term_automaton(_, foo), R).
t69(R) :- err(term_automaton(_, automaton(f(x), a)), R).
t70(R) :- err(term_automaton(_, automaton(f(9), a)), R).
t71(R) :- compound_name_arguments(A, automaton, []), err(term_automaton(_, A), R).

% the option defaults of term_factorized/4: minimal(true) and dollar_var(true) when the other is given
t72(R) :- T = f('$VAR'(1), '$VAR'(1), g(a), g(a)), term_factorized(T, S, Sub, [minimal(true)]), R = r(S, Sub).
t73(R) :- T = f(g(a), g(a), '$VAR'(1), '$VAR'(1)), term_factorized(T, S, Sub, [dollar_var(true)]), R = r(S, Sub).
