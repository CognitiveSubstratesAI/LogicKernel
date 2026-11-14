% ORIGINAL: the rows of test/core_lang/test_arith_curfn_swipl.jl — no swipl-devel counterpart.
% test/core_lang/test_arith_curfn_swipl.pl — AR1's rows for current_arithmetic_function/1 (pl-arith.c, non-deterministic).
% Each `tN(R)` is one row; test_arith_curfn_swipl.out holds the pin's (swipl 10.1.20, 18168e62) answers (two byte-identical runs).
% The ORDER of the enumeration differs between the pin (the functor's index) and the kernel (the table's), so a row that enumerates
% sorts its answers (msort) before it shows them: the SET is compared.
% UNTESTED on the kernel: written without a compile, the gate decides
all(L) :- findall(N/A, ( current_arithmetic_function(F), functor(F, N, A) ), L0), msort(L0, L).
ar(A, L) :- findall(N, ( current_arithmetic_function(F), functor(F, N, A) ), L0), msort(L0, L).
ce(F, R) :- catch(( current_arithmetic_function(F) -> R = yes ; R = no ), error(E, _), R = E).
t1(R) :- all(R).
t2(R) :- all(L), length(L, R).
t3(R) :- ar(0, R).
t4(R) :- ar(1, R).
t5(R) :- ar(2, R).
t6(R) :- ar(3, R).
t7(R) :- ar(4, R).
t8(R) :- findall(F, current_arithmetic_function(F), L), length(L, N), sort(L, S), length(S, M), R = N-M.
t9(R) :- ce(pi, R).
t10(R) :- ce(e, R).
t11(R) :- ce(inf, R).
t12(R) :- ce(nan, R).
t13(R) :- ce(epsilon, R).
t14(R) :- ce(cputime, R).
t15(R) :- ce(random_float, R).
t16(R) :- ce(foo, R).
t17(R) :- ce(sin, R).
t18(R) :- ce(max, R).
t19(R) :- ce(sin(_), R).
t20(R) :- ce(sin(x), R).
t21(R) :- ce(sin(_, _), R).
t22(R) :- ce(sin(_, _, _), R).
t23(R) :- ce(+(_), R).
t24(R) :- ce(+(_, _), R).
t25(R) :- ce(+(_, _, _), R).
t26(R) :- ce(-(_), R).
t27(R) :- ce(-(1, 2), R).
t28(R) :- ce(max(_, _), R).
t29(R) :- ce(max(1, 2), R).
t30(R) :- ce(min(_), R).
t31(R) :- ce(atan(_), R).
t32(R) :- ce(atan(_, _), R).
t33(R) :- ce(atan2(_, _), R).
t34(R) :- ce(atan2(_), R).
t35(R) :- ce(powm(_, _, _), R).
t36(R) :- ce(powm(_, _), R).
t37(R) :- ce(roundtoward(_, _), R).
t38(R) :- ce(roundtoward(_), R).
t39(R) :- ce(eval(_), R).
t40(R) :- ce(random(_), R).
t41(R) :- ce(random, R).
t42(R) :- ce(**(_, _), R).
t43(R) :- ce(^(_, _), R).
t44(R) :- ce(//(_, _), R).
t45(R) :- ce(/(_, _), R).
t46(R) :- ce(div(_, _), R).
t47(R) :- ce(mod(_, _), R).
t48(R) :- ce(rdiv(_, _), R).
t49(R) :- ce(\(_), R).
t50(R) :- ce(\(_, _), R).
t51(R) :- ce(/\(_, _), R).
t52(R) :- ce(xor(_, _), R).
t53(R) :- ce(<<(_, _), R).
t54(R) :- ce(>>(_, _), R).
t55(R) :- ce(truncate(_), R).
t56(R) :- ce(integer(_), R).
t57(R) :- ce(round(_), R).
t58(R) :- ce(ceil(_), R).
t59(R) :- ce(ceiling(_), R).
t60(R) :- ce(floor(_), R).
t61(R) :- ce(float(_), R).
t62(R) :- ce(trunc(_), R).
t63(R) :- ce(cot(_), R).
t64(R) :- ce(acot(_), R).
t65(R) :- ce(sec(_), R).
t66(R) :- ce(log2(_), R).
t67(R) :- ce(log(_, _), R).
t68(R) :- ce(cmpflags, R).
t69(R) :- ce(trig, R).
t70(R) :- ce(succ(_), R).
t71(R) :- ce(plus(_, _), R).
t72(R) :- ce(truncate, R).
t73(R) :- ce(abs(_), R).
t74(R) :- ce(sign(_), R).
t75(R) :- ce(gcd(_, _), R).
t76(R) :- ce(lcm(_, _), R).
t77(R) :- ce(msb(_), R).
t78(R) :- ce(lsb(_), R).
t79(R) :- ce(popcount(_), R).
t80(R) :- ce(getbit(_, _), R).
t81(R) :- ce(erf(_), R).
t82(R) :- ce(erfc(_), R).
t83(R) :- ce(lgamma(_), R).
t84(R) :- ce(copysign(_, _), R).
t85(R) :- ce(nexttoward(_, _), R).
t86(R) :- ce(cmpr(_, _), R).
t87(R) :- ce(maxr(_, _), R).
t88(R) :- ce(minr(_, _), R).
t89(R) :- ce(numerator(_), R).
t90(R) :- ce(denominator(_), R).
t91(R) :- ce(rational(_), R).
t92(R) :- ce(rationalize(_), R).
t93(R) :- ce(float_fractional_part(_), R).
t94(R) :- ce(float_integer_part(_), R).
t95(R) :- ce(3, R).
t96(R) :- ce(0, R).
t97(R) :- ce(-1, R).
t98(R) :- ce(1.5, R).
t99(R) :- ce(1r3, R).
t100(R) :- ce("pi", R).
t101(R) :- ce("", R).
t102(R) :- ce([], R).
t103(R) :- ce('[]', R).
t104(R) :- ce([a], R).
t105(R) :- ce([_|_], R).
t106(R) :- ce('', R).
t107(R) :- ce(f(a, b, c, d), R).
t108(R) :- ce('Pi', R).
t109(R) :- ce(0.0, R).
t110(R) :- ce(123456789012345678901234567890, R).
t111(R) :- ce(f(_), R).
t112(R) :- current_arithmetic_function(F), functor(F, pi, 0), R = F.
t113(R) :- current_arithmetic_function(F), functor(F, e, 0), R = F.
t114(R) :- current_arithmetic_function(F), F = abs(_), R = F.
t115(R) :- current_arithmetic_function(F), functor(F, atan, 2), R = F.
t116(R) :- current_arithmetic_function(F), functor(F, powm, 3), R = F.
t117(R) :- current_arithmetic_function(F), functor(F, foo, 1), R = F.
t118(R) :- current_arithmetic_function(F), functor(F, sin, 2), R = F.
t119(R) :- findall(x, ( current_arithmetic_function(F), F = pi ), R).
t120(R) :- findall(x, ( current_arithmetic_function(F), F = sin(_) ), R).
t121(R) :- findall(x, ( current_arithmetic_function(F), F = sin(_, _) ), R).
t122(R) :- findall(x, ( current_arithmetic_function(F), F = -(_) ), R).
t123(R) :- findall(x, ( current_arithmetic_function(F), F = -(_, _) ), R).
t124(R) :- findall(x, ( current_arithmetic_function(F), F = -(_, _, _) ), R).
t125(R) :- ( current_arithmetic_function(_), ! ; fail ), R = cut.
t126(R) :- ( current_arithmetic_function(F), F = pi, ! ; fail ), R = F.
t127(R) :- once(current_arithmetic_function(_)), R = once.
t128(R) :- \+ current_arithmetic_function(foo), R = notfoo.
t129(R) :- \+ current_arithmetic_function(pi), R = notpi.
t130(R) :- forall(member(X, [pi, e, inf, nan, epsilon, cputime, random_float, sin(_), +(_, _), max(_, _)]), current_arithmetic_function(X)), R = all.
t131(R) :- forall(member(X, [foo, bar(_), sin(_, _), max(_)]), \+ current_arithmetic_function(X)), R = none.
t132(R) :- findall(N, ( member(N, [pi, e, inf, nan, epsilon, cputime, random_float, foo]), current_arithmetic_function(N) ), R).
t133(R) :- findall(N/A, ( member(N/A, [sin/1, sin/2, (+)/1, (+)/2, (+)/3, (-)/1, (-)/2, atan/1, atan/2, atan2/2, atan2/1, powm/3, powm/2]), functor(F, N, A), current_arithmetic_function(F) ), R).
t134(R) :- findall(F, ( current_arithmetic_function(F), F = abs(_) ), [R0]), R0 = abs(X), var(X), R = ok.
t135(R) :- current_arithmetic_function(F), F = sqrt(X), X = 4, Y is F, R = Y.
t136(R) :- findall(N/A, ( current_arithmetic_function(F), functor(F, N, A), A > 1, N @< d ), L0), msort(L0, R).
t137(R) :- findall(N/A, ( current_arithmetic_function(F), functor(F, N, A), atom_length(N, 1) ), L0), msort(L0, R).
t138(R) :- all(L), length(L, N), N > 70, R = big.
t139(R) :- ce(foo(_), R0), ce(foo, R1), R = R0-R1.
t140(R) :- ce(g, R).
