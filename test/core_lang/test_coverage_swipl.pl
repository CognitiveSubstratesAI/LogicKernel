% ORIGINAL: the rows of test/core_lang/test_coverage_swipl.jl (its predicates are pl-coverage.c's: '$cov_add'/3, '$cov_data'/3,
% '$cov_reset'/0, '$cov_stop'/1, '$cov_active'/1; '$cov_start'/1 is run by the kernel's own row `tcs`, which is no row of the .out).
% test/core_lang/test_coverage_swipl.pl - COVERAGE's rows. Each `tN(R)` (pass 1, a clean state) and `wN(R)` (pass 2, the collection
% active twice) is one row; test_coverage_swipl.out holds swipl 10.1.20's answers (`ok`, then one line per row: its name and every
% solution), as the test's driver prints them. A clause reference is never printed (the encoder takes no blob): a row reads its
% counts and its call-site offsets back. An error is caught inside the row and answered as err(Formal) (err(existence_error(Type)) for an
% error that names a clause reference); a failure is answered as the atom `failed`.

err(G, R) :- catch(( G -> R = true ; R = failed ), error(E, _), R = err(E)).
errt(G, R) :- catch(( G -> R = true ; R = failed ), error(E, _), ( E = existence_error(Ty, _) -> R = err(existence_error(Ty)) ; R = err(E) )).

cvf(1).
cvf(2).

% pass 1, a clean state: nothing is active, nothing is collected
t0(R) :- err('$cov_active'(_), R).
t1(R) :- err('$cov_stop'(1), R).
t2(R) :- err('$cov_stop'(a), R).
t3(R) :- err('$cov_data'(_, _, _), R).
t4(R) :- err('$cov_reset', R).
t5(R) :- err('$cov_data'(clause(_), _, _), R).

% '$cov_add'/3: the order of the checks (the counts, then the site)
t6(R) :- err('$cov_add'(clause(_), a, 1), R).
t7(R) :- err('$cov_add'(clause(_), _, 1), R).
t8(R) :- err('$cov_add'(clause(_), 1, b), R).
t9(R) :- err('$cov_add'(clause(_), 1, _), R).
t10(R) :- err('$cov_add'(foo, 1, 1), R).
t11(R) :- err('$cov_add'(call_site(r, x), 1, 1), R).
t12(R) :- err('$cov_add'(call_site(r, _), 1, 1), R).
t13(R) :- assertz(zz(1), C), erase(C), errt('$cov_add'(clause(C), 1, 1), R).
t14(R) :- assertz(zz(2), C), erase(C), errt('$cov_add'(call_site(C, 3), 1, 1), R).

% a clause site: add, read back by the ground lookup
t15(R) :- clause(cvf(1), true, C), '$cov_reset', '$cov_add'(clause(C), 2, 3), '$cov_data'(clause(C), E, X), R = r(E, X).
t16(R) :- clause(cvf(1), true, C), '$cov_reset', '$cov_add'(clause(C), 1, 2), '$cov_add'(clause(C), 1, 2),
    '$cov_data'(clause(C), E, X), R = r(E, X).
t17(R) :- clause(cvf(1), true, C), '$cov_reset', '$cov_add'(clause(C), 0, 0), '$cov_data'(clause(C), E, X), R = r(E, X).
t18(R) :- clause(cvf(1), true, C), '$cov_reset', '$cov_add'(clause(C), 0, 0), findall(E-X, '$cov_data'(_, E, X), L), R = L.
t19(R) :- clause(cvf(1), true, C), clause(cvf(2), true, D), '$cov_reset', '$cov_add'(clause(C), 1, 1),
    ( '$cov_data'(clause(D), _, _) -> R = found ; R = failed ).
t20(R) :- clause(cvf(1), true, C), '$cov_reset', '$cov_add'(clause(C), 4, 5), '$cov_add'(clause(C), 1, 0),
    findall(E-X, '$cov_data'(_, E, X), L), R = L.

% a call site: pc 0 and 7, read back by the ground lookup and by the enumeration
t21(R) :- clause(cvf(1), true, C), '$cov_reset', '$cov_add'(call_site(C, 0), 4, 5), '$cov_data'(call_site(C, 0), E, X), R = r(E, X).
t22(R) :- clause(cvf(1), true, C), '$cov_reset', '$cov_add'(call_site(C, 7), 1, 2), '$cov_data'(call_site(C, 7), E, X), R = r(E, X).
t23(R) :- clause(cvf(1), true, C), '$cov_reset', '$cov_add'(call_site(C, 7), 1, 2),
    '$cov_data'(call_site(C, P), E, X), !, R = r(P, E, X).
t24(R) :- clause(cvf(1), true, C), '$cov_reset', '$cov_add'(call_site(C, 7), 1, 2), '$cov_add'(call_site(C, 7), 3, 4),
    '$cov_data'(call_site(C, 7), E, X), R = r(E, X).
t25(R) :- clause(cvf(1), true, C), '$cov_reset', '$cov_add'(call_site(C, 7), 1, 2),
    ( '$cov_data'(call_site(C, 9), _, _) -> R = found ; R = failed ).
t26(R) :- clause(cvf(1), true, C), '$cov_reset', '$cov_add'(clause(C), 1, 1),
    ( '$cov_data'(call_site(C, 0), _, _) -> R = found ; R = failed ).
t27(R) :- clause(cvf(1), true, C), '$cov_reset', '$cov_add'(call_site(C, 7), 0, 0),
    findall(E-X, '$cov_data'(call_site(_, _), E, X), L), R = L.

% the pattern restricts the type of the sites
t28(R) :- clause(cvf(1), true, C), '$cov_reset', '$cov_add'(clause(C), 1, 1), '$cov_add'(call_site(C, 3), 2, 2),
    findall(E-X, '$cov_data'(call_site(_, _), E, X), L1), findall(E-X, '$cov_data'(clause(_), E, X), L2), R = r(L1, L2).
t29(R) :- clause(cvf(1), true, C), '$cov_reset', '$cov_add'(clause(C), 1, 1), '$cov_add'(call_site(C, 3), 2, 2),
    '$cov_add'(call_site(C, 4), 3, 3), findall(P-E, '$cov_data'(call_site(C, P), E, _), L), msort(L, S), R = S.
t30(R) :- clause(cvf(1), true, C), clause(cvf(2), true, D), '$cov_reset', '$cov_add'(call_site(C, 3), 1, 1),
    '$cov_add'(call_site(D, 3), 5, 5), '$cov_add'(call_site(D, 4), 6, 6),
    findall(E, '$cov_data'(call_site(_, 3), E, _), L), msort(L, S), R = S.
t31(R) :- clause(cvf(1), true, C), clause(cvf(2), true, D), '$cov_reset', '$cov_add'(call_site(C, 3), 1, 1),
    '$cov_add'(call_site(D, 3), 5, 5), '$cov_add'(call_site(D, 4), 6, 6),
    findall(P-E, '$cov_data'(call_site(D, P), E, _), L), msort(L, S), R = S.
t32(R) :- clause(cvf(1), true, C), '$cov_reset', '$cov_add'(clause(C), 3, 4), findall(E-X, '$cov_data'(_, E, X), L), R = L.
t33(R) :- clause(cvf(1), true, C), '$cov_reset', '$cov_add'(clause(C), 3, 4), '$cov_data'(_, E, X), !, R = r(E, X).
t34(R) :- clause(cvf(1), true, C), '$cov_reset', '$cov_add'(clause(C), 3, 4),
    '$cov_data'(S, _, _), !, ( S = clause(C2), C2 == C -> R = same ; R = diff ).

% the reset gives the data back
t35(R) :- clause(cvf(1), true, C), '$cov_reset', '$cov_add'(clause(C), 3, 4), '$cov_reset',
    ( '$cov_data'(clause(C), _, _) -> R = found ; R = failed ).
t36(R) :- clause(cvf(1), true, C), '$cov_reset', '$cov_add'(clause(C), 3, 4), '$cov_reset', '$cov_add'(clause(C), 1, 1),
    '$cov_data'(clause(C), E, X), R = r(E, X).

% an answer needs one count not zero; a site whose clause was erased is not an answer; a pc offset outside the table is no key
t37(R) :- clause(cvf(1), true, C), '$cov_reset', '$cov_add'(clause(C), 3, 0), findall(E-X, '$cov_data'(_, E, X), L), R = L.
t38(R) :- assertz(zz(9), C), '$cov_reset', '$cov_add'(call_site(C, 1), 1, 1), erase(C),
    findall(E-X, '$cov_data'(_, E, X), L), R = L.
t39(R) :- clause(cvf(1), true, C), '$cov_reset', '$cov_add'(call_site(C, 1), 1, 1),
    ( '$cov_data'(call_site(C, -2), _, _) -> R = found ; R = failed ).
% both counts wrong: the enter count is checked first
t40(R) :- err('$cov_add'(clause(_), a, b), R).

% pass 2: the collection is active twice (the driver runs '$cov_start'/1 twice; the kernel's test sets the count to 2),
% the rows are cumulative: each starts where the one before left the count
w0(R) :- '$cov_active'(R).
w1(R) :- err('$cov_stop'(a), R).
w2(R) :- err('$cov_stop'(_), R).
w3(R) :- '$cov_stop'(3), '$cov_active'(R).
w4(R) :- '$cov_stop'(2), '$cov_active'(R).
w5(R) :- err('$cov_reset', R).
w6(R) :- '$cov_stop'(1), ( '$cov_active'(_) -> R = active ; R = failed ).
w7(R) :- err('$cov_reset', R).

% rows only the kernel runs (`tcs`: '$cov_start'/1 answers the nesting 1 and leaves the collection active; `tcp`, `tcq`: refusals)
tcs(R) :- '$cov_start'(R).
% ... and the pc offsets outside 0..2^32-2 of a call site (the table key's low half): a named refusal in the kernel
tcp(R) :- clause(cvf(1), true, C), '$cov_add'(call_site(C, -2), 1, 1), R = ok.
tcq(R) :- clause(cvf(1), true, C), '$cov_add'(call_site(C, 4294967295), 1, 1), R = ok.
