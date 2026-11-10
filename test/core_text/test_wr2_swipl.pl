% ORIGINAL: the rows of test/core_text/test_wr2_swipl.jl — no swipl-devel counterpart.
% test/core_text/test_wr2_swipl.pl — WR2's rows: write_term/2,3's integer_format and float_format (pl-write.c writeNumber,
% through do_format), and blobs(portray) (pl-write.c writeAtom, through callPortray). Each `tN(R)` is one row;
% test_wr2_swipl.out holds swipl 10.1.20's answers to them, as the test's driver prints them (`ok`, then one line per row:
% its name and every solution). Each row writes into a string (`w/2`): its answer is that string, `false`, `error(Formal)` or
% `ex(Ball)` for a ball that is no error term. A stream blob has no deterministic text (its address): a row that would
% print one only checks the prefix.
:- dynamic pmode/1.
% the user's portray/1, steered by `pmode/1`: `stream` writes <S> for a stream; `all` writes P for everything it is offered;
% `failing` and `throw` are offered the stream too, and fail or throw; `foobar` writes `bar` for the atom foo (t67, and the halt rows of the .jl).
portray(X) :- pmode(M), pact(M, X).
pact(stream, X) :- is_stream(X), write('<S>').
pact(all, _) :- write('P').
pact(failing, X) :- is_stream(X), fail.
pact(throw, X) :- is_stream(X), throw(portray_oops).
pact(foobar, X) :- X == foo, write(bar).
setm(M) :- retractall(pmode(_)), assertz(pmode(M)).
w(G, R) :- catch(( with_output_to(string(S), G) -> R = S ; R = false ), B, ( B = error(E, _) -> R = error(E) ; R = ex(B) )).
pre(G, P, R) :- w(G, S), ( string(S), sub_string(S, 0, _, _, P) -> R = prefix_ok ; R = S ).
% integer_format
t0(R) :- w(write_term(1234567, [integer_format('~D')]), R).
t1(R) :- w(write_term(-1234567, [integer_format('~D')]), R).
t2(R) :- w(write_term(255, [integer_format('~16r')]), R).
t3(R) :- w(write_term(1234, [integer_format('~2d')]), R).
t4(R) :- w(write_term(123456789012345678901234567890, [integer_format('~D')]), R).
t5(R) :- w(write_term(-123456789012345678901234567890, [integer_format('~2d')]), R).
t6(R) :- w(write_term(0, [integer_format('~3d')]), R).
t7(R) :- w(write_term(f(1, 22, -3, a), [integer_format('<~d>')]), R).
t8(R) :- w(write_term(-5, [integer_format('~3d')]), R).
t9(R) :- w(write_term(5, [integer_format('~8|~d')]), R).
t10(R) :- w(write_term([1,2,3], [integer_format('~t~d~3+'), quoted(true)]), R).
t11(R) :- w(write_term(2.5, [integer_format('~D')]), R).
t12(R) :- w(write_term(1r3, [integer_format('~D')]), R).
t13(R) :- w(write_term('a b'-1, [integer_format('~D'), quoted(true)]), R).
t14(R) :- w((write_term(10, [integer_format('~2d')]), write(' '), write(10)), R).
t15(R) :- w((print(1234567), write(' '), print(f(1.5))), R).
% float_format
t16(R) :- w(write_term(3.14159, [float_format('~2f')]), R).
t17(R) :- w(write_term(-0.5, [float_format('~1f')]), R).
t18(R) :- w(write_term(1.5e10, [float_format('~4e')]), R).
t19(R) :- w(write_term(0.1, [float_format('~g')]), R).
t20(R) :- w(write_term(1.0, [float_format('~15g|')]), R).
t21(R) :- w(write_term(f(1, 2.5, a), [integer_format('<~d>'), float_format('[~1f]')]), R).
t22(R) :- w(write_term(123, [float_format('~2f')]), R).
t23(R) :- w(write_term(1.0Inf, [float_format('~2f')]), R).
t24(R) :- w(write_term(1.5NaN, [float_format('~2f')]), R).
t25(R) :- w(write_term(100000.0, [float_format('~0f')]), R).
t26(R) :- w(write_term(1.0e100, [float_format('~3f')]), R).
t27(R) :- w(write_term(-1.5, [float_format('~h')]), R).
t28(R) :- w(write_term(3.0, [float_format('~15g|')]), R).
% separate_number: the first character of the format decides, else the sign
t29(R) :- w(write_term(a=1, [integer_format('-~d')]), R).
t30(R) :- w(write_term(a=1, [integer_format('~d')]), R).
t31(R) :- w(write_term(a= -1, [integer_format('~D')]), R).
t32(R) :- w(write_term(a-1, [integer_format('x~d')]), R).
t33(R) :- w(write_term(a is 1, [integer_format('x~d')]), R).
t34(R) :- w(write_term(a=1.5, [float_format('-~1f')]), R).
t35(R) :- w(write_term(a= -1.5, [float_format('~1f')]), R).
t36(R) :- w(write_term(a=1, [float_format('-~1f')]), R).
t37(R) :- w(write_term(- 1, [integer_format('~D')]), R).
t38(R) :- w(write_term(-(1), [integer_format('-~d')]), R).
t39(R) :- w(write_term(1-2, [integer_format('~d~d~d')]), R).
% format errors
t40(R) :- w(write_term(1, [integer_format('~a')]), R).
t41(R) :- w(write_term(1, [integer_format('~z')]), R).
t42(R) :- w(write_term(1, [integer_format('~d~d')]), R).
t43(R) :- w(write_term(1, [integer_format('')]), R).
t44(R) :- w(write_term(1.5, [float_format('~d')]), R).
t45(R) :- w(write_term(1, [integer_format(1)]), R).
t46(R) :- w(write_term(1.5, [float_format('~2f~2f')]), R).
% blobs(portray)
t47(R) :- setm(stream), w((current_output(S), write_term(f(S, a, []), [blobs(portray)])), R).
t48(R) :- setm(stream), w((current_output(S), write_term(S, [blobs(portray), quoted(true)])), R).
t49(R) :- setm(all), w((current_output(S), write_term(f(S, a, [], "s", 1, 'A b', []), [blobs(portray), quoted(true)])), R).
t50(R) :- setm(all), w(write_term([], [blobs(portray)]), R).
t51(R) :- setm(all), w(write_term('[]', [blobs(portray)]), R).
t52(R) :- setm(all), w(write_term(f("s", 1, 'A b', abc), [blobs(portray), quoted(true)]), R).
t53(R) :- setm(all), w((assertz(wr2_f(1), Ref), write_term(Ref, [blobs(portray)])), R).
t54(R) :- setm(all), w((assertz(wr2_f(2), Ref), write_term(g(Ref, Ref), [blobs(portray)])), R).
t55(R) :- setm(stream), w((current_output(S), write_term(f(S), [blobs(portray), portray(true)])), R).
t56(R) :- setm(stream), w((current_output(S), print(f(S))), R).
t57(R) :- setm(failing), pre((current_output(S), write_term(f(S), [blobs(portray)])), "f(<stream>(0x", R).
t58(R) :- setm(throw), w((current_output(S), write_term(f(S), [blobs(portray)])), R).
t59(R) :- setm(none), pre((current_output(S), write_term(f(S), [blobs(portray)])), "f(<stream>(0x", R).
t60(R) :- setm(stream), pre((current_output(S), write_term(f(S), [])), "f(<stream>(0x", R).
t61(R) :- setm(all), w((current_output(S), write_term(g(S), [blobs(portray), portray_goal(wr2_pg)])), R).
t62(R) :- setm(stream), w((current_output(S), write_term(f(S, S), [blobs(portray), quoted(true), max_depth(3)])), R).
wr2_pg(T, _) :- is_stream(T), write('<pg>').
% tests/core_text/test_write.pl's `float_format_non_bmp` shape: a format text with a code point above 0xffff
t63(R) :- w(write_term(1.5, [float_format('\U0001D431~w')]), R).
% separate_number on a BIGNUM after a symbol character, the format path (t64) and the default path (t65): the space before the sign
t64(R) :- w(write_term(a= -123456789012345678901234567890, [integer_format('~D')]), R).
t65(R) :- w(write(a- -123456789012345678901234567890), R).
% the priority callPortray hands portray_goal for a BLOB is 1200 (pl-write.c writeAtom), not the option's 999: the goal writes its options
wr2_pg2(T, O) :- is_stream(T), write(O).
t66(R) :- w((current_output(S), write_term(S, [blobs(portray), portray_goal(wr2_pg2), priority(999)])), R).
% portray/1 on an atom under portray(true): the row the halt rows of the .jl run with gd.halt_cleaning raised (callPortray's own test)
t67(R) :- setm(foobar), w(write_term(f(foo), [portray(true)]), R).
