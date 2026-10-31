:- assertz(qm:(qm(C) :- context_module(C))).
:- '$set_predicate_attribute'(qm:qm(_), transparent, true).
m(qm).
m2(qm2).
g(A, qm(A)).
utp(M) :- context_module(M).
:- '$set_predicate_attribute'(utp(_), transparent, true).
p(1).
p(2).
p(3).
at(C) :- @(qm:qm(C), qm2).
atnl(C) :- @(qm:qm(C), qm2), true.
atu(C) :- @(utp(C), qm2).
atunl(C) :- @(utp(C), qm2), true.
vat(C) :- m(M), @(M:qm(C), qm2).
atv(C) :- m2(QC), @(qm:qm(C), QC).
atvn(C) :- m2(QC), @(qm:qm(C), QC), true.
atvu(C) :- m2(QC), @(utp(C), QC).
atvcp(C) :- m2(QC), between(1, 2, _), @(qm:qm(C), QC).
atvv(C) :- m(M), m2(QC), @(M:qm(C), QC).
atvvv(C) :- m(M), m2(QC), g(C, G), @(M:G, QC).
atvvc(C) :- m(M), m2(QC), g(C, G), @(M:(G, true), QC).
atg(C) :- G = utp(C), @(G, qm2).
atrestore(C1, C2) :- @(utp(C1), qm2), utp(C2).
atnest(C) :- @(@(utp(C), qm2), qm).
atctl(X) :- @((true -> X = 1 ; X = 2), qm2).
atctx(C) :- @((utp(C), true), qm2).
atunify(X) :- @(X = a, qm2).
atcut :- @(!, qm2).
atcalln(C) :- @(call(utp, C), qm2).
rt(M, R) :- @(utp(R), M).
rtn(M, R) :- @(utp(R), M), true.
lcm(N, U, M) :- ( N =:= 0 -> statistics(localused, U) ; N1 is N-1, @(lcm(N1, U, M), M) ).
lca(N, U) :- ( N =:= 0 -> statistics(localused, U) ; N1 is N-1, @(lca(N1, U), qm2) ).
lcpm(N, U, M) :- ( N =:= 0 -> statistics(localused, U) ; N1 is N-1, between(1, 2, _), @(lcpm(N1, U, M), M) ).
lcpa(N, U) :- ( N =:= 0 -> statistics(localused, U) ; N1 is N-1, between(1, 2, _), @(lcpa(N1, U), qm2) ).
atcpx(C0, C) :- m2(QC), between(1, 2, _), utp(C0), @(qm:qm(C), QC).
atcpa(C0, C) :- between(1, 2, _), utp(C0), @(utp(C), qm2).
atnest2(C1, C2) :- @((@(utp(C1), qm2), utp(C2)), qm).
t_a01(R) :- catch((at(R)), error(SsuE, _), R = raised(SsuE)).
t_a02(R) :- catch((atnl(R)), error(SsuE, _), R = raised(SsuE)).
t_a03(R) :- catch((atu(R)), error(SsuE, _), R = raised(SsuE)).
t_a04(R) :- catch((atunl(R)), error(SsuE, _), R = raised(SsuE)).
t_a05(R) :- catch((vat(R)), error(SsuE, _), R = raised(SsuE)).
t_a06(R) :- catch((atv(R)), error(SsuE, _), R = raised(SsuE)).
t_a07(R) :- catch((atvn(R)), error(SsuE, _), R = raised(SsuE)).
t_a08(R) :- catch((atvu(R)), error(SsuE, _), R = raised(SsuE)).
t_a09(R) :- catch((findall(C, atvcp(C), R)), error(SsuE, _), R = raised(SsuE)).
t_a10(R) :- catch((atvv(R)), error(SsuE, _), R = raised(SsuE)).
t_a11(R) :- catch((atvvv(R)), error(SsuE, _), R = raised(SsuE)).
t_a12(R) :- catch((atvvc(R)), error(SsuE, _), R = raised(SsuE)).
t_a13(R) :- catch((atg(R)), error(SsuE, _), R = raised(SsuE)).
t_a14(R) :- catch((atrestore(C1, C2), R = C1-C2), error(SsuE, _), R = raised(SsuE)).
t_a15(R) :- catch((atnest(R)), error(SsuE, _), R = raised(SsuE)).
t_a16(R) :- catch((findall(X, atctl(X), R)), error(SsuE, _), R = raised(SsuE)).
t_a17(R) :- catch((atctx(R)), error(SsuE, _), R = raised(SsuE)).
t_a18(R) :- catch((atunify(R)), error(SsuE, _), R = raised(SsuE)).
t_a19(R) :- catch((atcut, R = yes), error(SsuE, _), R = raised(SsuE)).
t_a20(R) :- catch((atcalln(R)), error(SsuE, _), R = raised(SsuE)).
t_a21(R) :- catch((rt(_, R)), error(SsuE, _), R = raised(SsuE)).
t_a22(R) :- catch((rt(1, R)), error(SsuE, _), R = raised(SsuE)).
t_a23(R) :- catch((rt(foo, R)), error(SsuE, _), R = raised(SsuE)).
t_a24(R) :- catch((rt(f(x), R)), error(SsuE, _), R = raised(SsuE)).
t_a25(R) :- catch((rtn(_, R)), error(SsuE, _), R = raised(SsuE)).
t_a26(R) :- catch((rtn(1, R)), error(SsuE, _), R = raised(SsuE)).
t_a27(R) :- catch((rtn(foo, R)), error(SsuE, _), R = raised(SsuE)).
t_a28(R) :- catch((call(@(utp(R), qm2))), error(SsuE, _), R = raised(SsuE)).
t_a29(R) :- catch((call(@(qm:qm(R), qm2))), error(SsuE, _), R = raised(SsuE)).
t_a30(R) :- catch((call(@(utp(_), _)), R = ok), error(SsuE, _), R = raised(SsuE)).
t_a31(R) :- catch((call(@(_, qm2)), R = ok), error(SsuE, _), R = raised(SsuE)).
t_a32(R) :- catch((call(@(_:utp(_), qm2)), R = ok), error(SsuE, _), R = raised(SsuE)).
t_a33(R) :- catch((call(@(qm:_, qm2)), R = ok), error(SsuE, _), R = raised(SsuE)).
t_a34(R) :- catch((call(@(utp(_), 1)), R = ok), error(SsuE, _), R = raised(SsuE)).
t_a35(R) :- catch((call(@(f(x):utp(_), qm2)), R = ok), error(SsuE, _), R = raised(SsuE)).
t_a36(R) :- catch((findall(X, call(@(p(X), user)), R)), error(SsuE, _), R = raised(SsuE)).
t_a37(R) :- catch((findall(X, (m2(Q), @(p(X), Q)), R)), error(SsuE, _), R = raised(SsuE)).
t_a38(R) :- catch((call(@(user:qm:utp(R), qm2))), error(SsuE, _), R = raised(SsuE)).
t_a39(R) :- catch((( G = p(G), call(@(G, user)) -> R = yes ; R = no )), error(SsuE, _), R = raised(SsuE)).
t_a40(R) :- catch((findall(B, clause(at(_), B), R)), error(SsuE, _), R = raised(SsuE)).
t_a41(R) :- catch((findall(B, clause(atnl(_), B), R)), error(SsuE, _), R = raised(SsuE)).
t_a42(R) :- catch((findall(B, clause(atu(_), B), R)), error(SsuE, _), R = raised(SsuE)).
t_a43(R) :- catch((findall(B, clause(atunl(_), B), R)), error(SsuE, _), R = raised(SsuE)).
t_a44(R) :- catch((findall(B, clause(atv(_), B), R)), error(SsuE, _), R = raised(SsuE)).
t_a45(R) :- catch((findall(B, clause(atvn(_), B), R)), error(SsuE, _), R = raised(SsuE)).
t_a46(R) :- catch((findall(B, clause(atvcp(_), B), R)), error(SsuE, _), R = raised(SsuE)).
t_a47(R) :- catch((findall(B, clause(vat(_), B), R)), error(SsuE, _), R = raised(SsuE)).
t_a48(R) :- catch((findall(B, clause(atvvc(_), B), R)), error(SsuE, _), R = raised(SsuE)).
t_a49(R) :- catch((findall(B, clause(atnest(_), B), R)), error(SsuE, _), R = raised(SsuE)).
t_a50(R) :- catch((findall(B, clause(atctl(_), B), R)), error(SsuE, _), R = raised(SsuE)).
t_a51(R) :- catch((findall(B, clause(atcalln(_), B), R)), error(SsuE, _), R = raised(SsuE)).
t_a52(R) :- catch((findall(B, clause(rt(_, _), B), R)), error(SsuE, _), R = raised(SsuE)).
t_a53(R) :- catch((findall(B, clause(rtn(_, _), B), R)), error(SsuE, _), R = raised(SsuE)).
t_a54(R) :- catch((findall(B, clause(atrestore(_, _), B), R)), error(SsuE, _), R = raised(SsuE)).
t_a55(R) :- catch((assertz((e1 :- @(foo, _))), R = ok), error(SsuE, _), R = raised(SsuE)).
t_a56(R) :- catch((assertz((e2 :- @(foo, 1))), R = ok), error(SsuE, _), R = raised(SsuE)).
t_a57(R) :- catch((assertz((e3 :- @(foo, f(x)))), R = ok), error(SsuE, _), R = raised(SsuE)).
t_a58(R) :- catch((assertz((e4 :- @(foo, M), bar(M))), R = ok), error(SsuE, _), R = raised(SsuE)).
t_a59(R) :- catch((assertz((e5(M, R0) :- @(utp(R0), M))), findall(B, clause(e5(_, _), B), R)), error(SsuE, _), R = raised(SsuE)).
t_a60(R) :- catch((assertz((e6(M) :- bar(M), @(foo, M))), findall(B, clause(e6(_), B), R)), error(SsuE, _), R = raised(SsuE)).
t_a61(R) :- catch((assertz((e7 :- @(foo, qm2), true)), findall(B, clause(e7, B), R)), error(SsuE, _), R = raised(SsuE)).
t_a62(R) :- catch((e5(qm2, R)), error(SsuE, _), R = raised(SsuE)).
t_a63(R) :- catch((e5(_, R)), error(SsuE, _), R = raised(SsuE)).
t_a64(R) :- catch((call((m2(QC), @(qm:qm(C), QC))), R = QC-C), error(SsuE, _), R = raised(SsuE)).
t_a65(R) :- catch((call((true, @(utp(_), _X))), R = ok), error(SsuE, _), R = raised(SsuE)).
t_a66(R) :- catch((call((true, @(utp(_), 1))), R = ok), error(SsuE, _), R = raised(SsuE)).
t_a67(R) :- catch((call((true, @(utp(C), qm2))), R = C), error(SsuE, _), R = raised(SsuE)).
t_a68(R) :- catch((call((@(utp(C1), qm2), utp(C2))), R = C1-C2), error(SsuE, _), R = raised(SsuE)).
t_a69(R) :- catch((call((m(M), m2(Q), @(M:qm(C), Q))), R = C), error(SsuE, _), R = raised(SsuE)).
t_a70(R) :- catch((( lcm(1000, U1, qm2) -> true ), ( lcm(2000, U2, qm2) -> true ), ( U1 == U2 -> R = same ; R = differ(U1, U2) )), error(SsuE, _), R = raised(SsuE)).
t_a71(R) :- catch((( lca(1000, U1) -> true ), ( lca(2000, U2) -> true ), ( U1 == U2 -> R = same ; R = differ(U1, U2) )), error(SsuE, _), R = raised(SsuE)).
t_a72(R) :- catch((( lcpm(1000, U1, qm2) -> true ), ( lcpm(2000, U2, qm2) -> true ), ( U2 > U1 -> R = grows ; R = flat(U1, U2) )), error(SsuE, _), R = raised(SsuE)).
t_a73(R) :- catch((( lcpa(1000, U1) -> true ), ( lcpa(2000, U2) -> true ), ( U2 > U1 -> R = grows ; R = flat(U1, U2) )), error(SsuE, _), R = raised(SsuE)).
t_a74(R) :- catch((findall(C0-C, atcpx(C0, C), R)), error(SsuE, _), R = raised(SsuE)).
t_a75(R) :- catch((findall(C0-C, atcpa(C0, C), R)), error(SsuE, _), R = raised(SsuE)).
t_a76(R) :- catch((atnest2(C1, C2), R = C1-C2), error(SsuE, _), R = raised(SsuE)).
t_a77(R) :- catch((findall(B, clause(atnest2(_, _), B), R)), error(SsuE, _), R = raised(SsuE)).
