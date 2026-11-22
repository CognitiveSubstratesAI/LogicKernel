% ORIGINAL: the rows of test/core_lang/test_coverage_run_swipl.jl: the coverage COLLECTION (COV1: pl-coverage.c's `Coverage()` hooks in the run
% loop, pl-vmi.c at the pin, and '$cov_start'/1) through a program; swipl 10.1.20 prints the same rows with the driver of the .jl.
% test/core_lang/test_coverage_run_swipl.pl - COV1's rows. Each `rN(R)` starts its own collection ('$cov_reset', '$cov_start'/1), runs
% some calls, stops it ('$cov_stop'/1) and answers COUNTS: a clause's enter and exit counts (`cvc/2`, in the clause order) or the sorted
% counts of a clause's call sites. NEVER A PC: the kernel's pc offsets index the clause's code, not swipl's byte layout (cov1_design.md Q2).
% Every row stops what it starts: the collection is not active between rows (the data persists; each row resets it first).

cvd(C, E, X) :- ( '$cov_data'(clause(C), E, X) -> true ; E = 0, X = 0 ).
cvc(H, L) :- findall(E-X, ( clause(H, _, C), cvd(C, E, X) ), L).
err(G, R) :- catch(( G -> R = true ; R = failed ), error(E, _), R = err(E)).

% the program the rows run: facts, a rule (called deterministically and not), a two-call clause, a recursion, a last call, a dynamic predicate
pf(1).
pf(2).
rf(1).
rf(2).
sf(3).
qd(1) :- rf(1), true.
qd(2) :- sf(3), true.
qr(X) :- rf(X), true.
qr(X) :- sf(X), true.
cw(X) :- rf(X), sf(_), true.
ln([], 0).
ln([_|T], N) :- ln(T, M), N is M+1.
ql(1) :- rf(1).
ql(2) :- sf(3).
:- dynamic dy/1.
dy(1).
dy(2).

% facts: the clause's enter count is its unify port (I_EXITFACT's), the nesting starts at 1
r0(R) :- '$cov_reset', '$cov_start'(N), pf(1), '$cov_stop'(N), cvc(pf(_), L), R = r(N, L).
% a rule called deterministically: its enter (I_ENTER's unify port) and exit (I_EXIT) counts, and the facts it calls
r1(R) :- '$cov_reset', '$cov_start'(N), qd(1), '$cov_stop'(N), cvc(qd(_), L1), cvc(rf(_), L2), cvc(sf(_), L3), R = r(L1, L2, L3).
% a nondeterministic call: every clause entered and exited, redo included
r2(R) :- '$cov_reset', '$cov_start'(N), findall(X, qr(X), Xs), '$cov_stop'(N),
    cvc(qr(_), L1), cvc(rf(_), L2), cvc(sf(_), L3), R = r(Xs, L1, L2, L3).
% the nesting: the second start answers 2, a stop with the nesting leaves the collection to the outer start
r3(R) :- '$cov_reset', '$cov_start'(A), '$cov_start'(B), '$cov_active'(C), '$cov_stop'(B), '$cov_active'(D), '$cov_stop'(A),
    ( '$cov_active'(_) -> E = active ; E = off ), R = r(A, B, C, D, E).
% collecting goes on after the inner stop, and ends with the outer one
r4(R) :- '$cov_reset', '$cov_start'(_), '$cov_start'(_), pf(1), '$cov_stop'(2), pf(1), '$cov_stop'(1), pf(1), cvc(pf(_), L), R = L.
% a dynamic predicate has no clause site, a static one has (the positive control is in the same row)
r5(R) :- '$cov_reset', '$cov_start'(N), dy(1), pf(1), '$cov_stop'(N),
    findall(C, ( '$cov_data'(clause(C), _, _), clause(H, _, C), H = dy(_) ), L), length(L, Len), cvc(pf(_), Lp), R = r(Len, Lp).
% a clause with two body calls: the counts of its call sites, sorted, no pc
r6(R) :- clause(cw(_), _, C), '$cov_reset', '$cov_start'(N), cw(1), '$cov_stop'(N),
    findall(E-X, '$cov_data'(call_site(C, _), E, X), L), msort(L, R).
% a site read back and written back with '$cov_add'/3 is the same site
r7(R) :- clause(cw(_), _, C), '$cov_reset', '$cov_start'(N), cw(1), '$cov_stop'(N),
    findall(P-E-X, '$cov_data'(call_site(C, P), E, X), [P0-E0-X0|_]),
    '$cov_reset', '$cov_add'(call_site(C, P0), E0, X0), '$cov_data'(call_site(C, P0), E1, X1),
    ( E1 == E0, X1 == X0, E0 > 0 -> R = same ; R = diff ).
% a recursion: three enters of the recursive clause, one of the base case
r8(R) :- '$cov_reset', '$cov_start'(N), ln([a, b, c], M), '$cov_stop'(N), cvc(ln(_, _), L), R = r(M, L).
% a call to a foreign predicate is a call site
r9(R) :- clause(r9(_), _, C), '$cov_reset', '$cov_start'(N), atom_length(abc, _), '$cov_stop'(N),
    findall(E-X, '$cov_data'(call_site(C, _), E, X), L), msort(L, R).
% a start inside a running collection keeps the data
r10(R) :- '$cov_reset', '$cov_start'(A), pf(1), '$cov_start'(_), pf(1), '$cov_stop'(2), '$cov_stop'(A), cvc(pf(_), L), R = r(A, L).
% a start that fails leaves no data (the nesting is unified before the data is made)
r11(R) :- '$cov_reset', ( '$cov_start'(5) -> S = started ; S = failed ), err('$cov_data'(_, _, _), E), R = r(S, E).
% the run mode: the collection clears the last-call and the VMI-builtin flags ('$notrace'/2 reads them), the stop restores them
r12(R) :- '$cov_reset', '$cov_start'(N), '$notrace'(F, _), '$cov_stop'(N), R = F.
r13(R) :- '$notrace'(F, _), R = F.
% a last call: the clause counts of the departing clause and of the callee
r14(R) :- '$cov_reset', '$cov_start'(N), ql(1), '$cov_stop'(N), cvc(ql(_), L1), cvc(rf(_), L2), R = r(L1, L2).
