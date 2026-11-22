% ORIGINAL: the rows of test/files/test_iri_hook_swipl.jl — no swipl-devel counterpart.
% test/files/test_iri_hook_swipl.pl — time_file/2, size_file/2, access_file/2, exists_file/1 and exists_directory/1 on an IRI
% (pl-file.c iri_hook, pl-files.c): `'$iri':iri_hook/4` calls the handler a program registers with `iri_scheme_handler/2`
% (the clause register_iri_scheme/3 as a directive makes, boot/iri.pl). Each `tN(R)` is one row, run in order (the last rows read
% what the handler saw). Answers: yes(Value) | no | ex(Formal) | ball(Ball). Pinned from swipl 10.1.20 (the pin's build).
% UNVERIFIED on the kernel: gate decides
:- multifile '$iri':iri_scheme_handler/2.
:- dynamic '$iri':iri_scheme_handler/2.
'$iri':iri_scheme_handler(foo, user:h).
:- dynamic seen/2.
h(Action, IRI, R) :- assertz(seen(Action, IRI)), r(Action, IRI, R).
ends(IRI, S) :- sub_string(IRI, _, _, 0, S).
r(time, IRI, R) :- ( ends(IRI, "int") -> R = 3 ; ends(IRI, "fail") -> fail ; ends(IRI, "bad") -> R = abc ; ends(IRI, "boom") -> throw(oops) ; R = 12.5 ).
r(size, IRI, R) :- ( ends(IRI, "fail") -> fail ; ends(IRI, "big") -> R = 1.5 ; ends(IRI, "bad") -> R = abc ; R = 42 ).
r(access(_), IRI, R) :- ( ends(IRI, "yes") -> R = true ; ends(IRI, "bad") -> R = maybe ; ends(IRI, "fail") -> fail ; R = false ).
res(G, R) :- catch(( G -> R = yes ; R = no ), E, ( E = error(F, _) -> R = ex(F) ; R = ball(E) )).
ans(G, V, R) :- catch(( G -> R = yes(V) ; R = no ), E, ( E = error(F, _) -> R = ex(F) ; R = ball(E) )).
nth(1, [X|_], X) :- !.
nth(N, [_|T], X) :- N > 1, N1 is N-1, nth(N1, T, X).
sn(N, R) :- findall(A-I, seen(A, I), L), ( nth(N, L, X) -> R = X ; R = none ).
t1(R) :- ans(time_file('foo://x', T), T, R).
t2(R) :- ans(time_file('foo://int', T), T, R).
t3(R) :- ans(time_file('foo://fail', T), T, R).
t4(R) :- ans(time_file('foo://bad', T), T, R).
t5(R) :- ans(time_file('foo://boom', T), T, R).
t6(R) :- ans(size_file('foo://x', S), S, R).
t7(R) :- ans(size_file('foo://big', S), S, R).
t8(R) :- ans(size_file('foo://bad', S), S, R).
t9(R) :- res(access_file('foo://x/yes', read), R).
t10(R) :- res(access_file('foo://x/no', read), R).
t11(R) :- res(access_file('foo://bad', read), R).
t12(R) :- res(access_file('foo://fail', read), R).
t13(R) :- res(access_file('foo://x/yes', write), R).
t14(R) :- res(access_file('foo://x/yes', append), R).
t15(R) :- res(access_file('foo://x/yes', execute), R).
t16(R) :- res(access_file('foo://x/yes', search), R).
t17(R) :- res(access_file('foo://x/yes', exist), R).
t18(R) :- res(access_file('foo://x/yes', none), R).
t19(R) :- res(exists_file('foo://x/yes'), R).
t20(R) :- res(exists_file('foo://x/no'), R).
t21(R) :- res(exists_directory('foo://x/yes'), R).
t22(R) :- res(exists_directory('foo://x/no'), R).
t23(R) :- res(time_file('bar://x', _), R).
t24(R) :- res(exists_file('bar://x'), R).
t25(R) :- res(access_file('bar://x', read), R).
t26(R) :- res(size_file('bar://x', _), R).
t27(R) :- res(is_absolute_file_name('bar://x'), R).
t28(R) :- res(access_file('foo://x/yes', badmode), R).
t29(R) :- sn(1, R).
t30(R) :- sn(2, R).
t31(R) :- sn(6, R).
t32(R) :- sn(7, R).
t33(R) :- sn(9, R).
t34(R) :- sn(11, R).
t35(R) :- sn(17, R).
t36(R) :- sn(18, R).
t37(R) :- sn(19, R).
t38(R) :- sn(20, R).
t39(R) :- sn(21, R).
t40(R) :- sn(22, R).
t41(R) :- sn(13, R).
t42(R) :- sn(14, R).
t43(R) :- sn(15, R).
t44(R) :- sn(16, R).
t45(R) :- ans(size_file('foo://fail', S), S, R).
t46(R) :- res(exists_file('foo://fail'), R).
