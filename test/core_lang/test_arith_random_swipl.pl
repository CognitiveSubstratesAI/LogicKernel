% ORIGINAL: the rows of test/core_lang/test_arith_random_swipl.jl — no swipl-devel counterpart.
% test/core_lang/test_arith_random_swipl.pl — AR1's rows for set_random/1, random_property/1 and the random functions random/1, random_float/0
% (pl-arith.c, GMP's Mersenne twister): the sequences after a seed, the state integer, the errors. Each `tN(R)` is one row;
% test_arith_random_swipl.out holds the pin's (swipl 10.1.20, 18168e62) answers: R is the answer term, or false, or error(Formal, Context).
% UNTESTED on the kernel: written without a compile, the gate decides
ans(T, G, R) :- catch(( G -> R = T ; R = false ), error(E, C), R = error(E, C)).
t0(R) :- ans(L, (set_random(seed(1)), L=[A,B,C], A is random(1000), B is random(1000), C is random(1000)), R).
t1(R) :- ans(L, (set_random(seed(1)), L=[A,B,C], A is random(1), B is random(1), C is random(1)), R).
t2(R) :- ans(L, (set_random(seed(1)), L=[A,B,C], A is random(2), B is random(2), C is random(2)), R).
t3(R) :- ans(L, (set_random(seed(1)), L=[A,B,C], A is random(3), B is random(3), C is random(3)), R).
t4(R) :- ans(L, (set_random(seed(1)), L=[A,B,C], A is random(4), B is random(4), C is random(4)), R).
t5(R) :- ans(L, (set_random(seed(1)), L=[A,B,C], A is random(5), B is random(5), C is random(5)), R).
t6(R) :- ans(L, (set_random(seed(1)), L=[A,B,C], A is random(7), B is random(7), C is random(7)), R).
t7(R) :- ans(L, (set_random(seed(1)), L=[A,B,C], A is random(255), B is random(255), C is random(255)), R).
t8(R) :- ans(L, (set_random(seed(1)), L=[A,B,C], A is random(256), B is random(256), C is random(256)), R).
t9(R) :- ans(L, (set_random(seed(1)), L=[A,B,C], A is random(257), B is random(257), C is random(257)), R).
t10(R) :- ans(L, (set_random(seed(1)), L=[A,B,C], A is random(65536), B is random(65536), C is random(65536)), R).
t11(R) :- ans(L, (set_random(seed(1)), L=[A,B,C], A is random(4294967295), B is random(4294967295), C is random(4294967295)), R).
t12(R) :- ans(L, (set_random(seed(1)), L=[A,B,C], A is random(4294967296), B is random(4294967296), C is random(4294967296)), R).
t13(R) :- ans(L, (set_random(seed(1)), L=[A,B,C], A is random(4294967297), B is random(4294967297), C is random(4294967297)), R).
t14(R) :- ans(L, (set_random(seed(1)), L=[A,B,C], A is random(9223372036854775807), B is random(9223372036854775807), C is random(9223372036854775807)), R).
t15(R) :- ans(L, (set_random(seed(1)), L=[A,B,C], A is random(9223372036854775808), B is random(9223372036854775808), C is random(9223372036854775808)), R).
t16(R) :- ans(L, (set_random(seed(1)), L=[A,B,C], A is random(18446744073709551615), B is random(18446744073709551615), C is random(18446744073709551615)), R).
t17(R) :- ans(L, (set_random(seed(1)), L=[A,B,C], A is random(18446744073709551616), B is random(18446744073709551616), C is random(18446744073709551616)), R).
t18(R) :- ans(L, (set_random(seed(1)), L=[A,B,C], A is random(18446744073709551617), B is random(18446744073709551617), C is random(18446744073709551617)), R).
t19(R) :- ans(L, (set_random(seed(1)), L=[A,B,C], A is random(100000000000000000000), B is random(100000000000000000000), C is random(100000000000000000000)), R).
t20(R) :- ans(L, (set_random(seed(1)), L=[A,B,C], A is random(10**30), B is random(10**30), C is random(10**30)), R).
t21(R) :- ans(L, (set_random(seed(1)), L=[A,B,C], A is random(10**40), B is random(10**40), C is random(10**40)), R).
t22(R) :- ans(L, (set_random(seed(1)), L=[A,B,C], A is random(2**100), B is random(2**100), C is random(2**100)), R).
t23(R) :- ans(L, (set_random(seed(1)), L=[A,B,C], A is random(2**127+1), B is random(2**127+1), C is random(2**127+1)), R).
t24(R) :- ans(L, (set_random(seed(1)), L=[A,B,C], A is random(2**200-1), B is random(2**200-1), C is random(2**200-1)), R).
t25(R) :- ans(L, (set_random(seed(1)), L=[A,B,C], A is random(1<<70), B is random(1<<70), C is random(1<<70)), R).
t26(R) :- ans(L, (set_random(seed(0)), L=[A,B,C], A is random(1000000), B is random(2**70), C is random_float), R).
t27(R) :- ans(L, (set_random(seed(1)), L=[A,B,C], A is random(1000000), B is random(2**70), C is random_float), R).
t28(R) :- ans(L, (set_random(seed(2)), L=[A,B,C], A is random(1000000), B is random(2**70), C is random_float), R).
t29(R) :- ans(L, (set_random(seed(12345)), L=[A,B,C], A is random(1000000), B is random(2**70), C is random_float), R).
t30(R) :- ans(L, (set_random(seed(-1)), L=[A,B,C], A is random(1000000), B is random(2**70), C is random_float), R).
t31(R) :- ans(L, (set_random(seed(-3)), L=[A,B,C], A is random(1000000), B is random(2**70), C is random_float), R).
t32(R) :- ans(L, (set_random(seed(4294967296)), L=[A,B,C], A is random(1000000), B is random(2**70), C is random_float), R).
t33(R) :- ans(L, (set_random(seed(9223372036854775807)), L=[A,B,C], A is random(1000000), B is random(2**70), C is random_float), R).
t34(R) :- ans(L, (set_random(seed(18446744073709551616)), L=[A,B,C], A is random(1000000), B is random(2**70), C is random_float), R).
t35(R) :- ans(L, (set_random(seed(-18446744073709551617)), L=[A,B,C], A is random(1000000), B is random(2**70), C is random_float), R).
t36(R) :- ans(L, (set_random(seed(12345678901234567890123)), L=[A,B,C], A is random(1000000), B is random(2**70), C is random_float), R).
t37(R) :- ans(L, (set_random(seed(10**100)), L=[A,B,C], A is random(1000000), B is random(2**70), C is random_float), R).
t38(R) :- ans(L, (set_random(seed(2**19937)), L=[A,B,C], A is random(1000000), B is random(2**70), C is random_float), R).
t39(R) :- ans(L, (set_random(seed(2**19937-20027)), L=[A,B,C], A is random(1000000), B is random(2**70), C is random_float), R).
t40(R) :- ans(L, (set_random(seed(-(2**20000))), L=[A,B,C], A is random(1000000), B is random(2**70), C is random_float), R).
t41(R) :- ans(A-B, (set_random(seed(1)), A is random_float, B is random_float), R).
t42(R) :- ans(A-B-C, (set_random(seed(1)), A is random_float, B is random(10), C is random_float), R).
t43(R) :- ans(X, (set_random(seed(7)), findall(F, (between(1,6,_), F is random_float), L), msort(L,L2), L==L2 -> X=sorted ; X=unsorted), R).
t44(R) :- ans(X, (set_random(seed(7)), findall(F, (between(1,4,_), F is random_float), X)), R).
t45(R) :- ans(X, (set_random(seed(1000)), findall(F, (between(1,60,_), F is random_float), L), sum_list(L,Sm), X is truncate(Sm*1000)), R).
t46(R) :- ans(X, (set_random(seed(3)), forall(between(1,700,_), _ is random(2**64)), X is random(1000000)), R).
t47(R) :- ans(X, (set_random(seed(3)), forall(between(1,2000,_), _ is random(1000)), X is random(1000000)), R).
t48(R) :- ans(X, (set_random(seed(3)), forall(between(1,1300,_), _ is random_float), X is random(1000000)), R).
t49(R) :- ans(X, X is random(0), R).
t50(R) :- ans(X, X is random(-1), R).
t51(R) :- ans(X, X is random(-100000000000000000000), R).
t52(R) :- ans(X, X is random(a), R).
t53(R) :- ans(X, X is random(_), R).
t54(R) :- ans(X, X is random(1.5), R).
t55(R) :- ans(X, (set_random(seed(1)), X is random(3.0)), R).
t56(R) :- ans(X, (set_random(seed(1)), X is random(1r1)), R).
t57(R) :- ans(X, X is random(1r2), R).
t58(R) :- ans(X, X is random(1.0Inf), R).
t59(R) :- ans(X, X is random(1.5NaN), R).
t60(R) :- ans(X, (set_random(seed(1)), X is random(2.0**70)), R).
t61(R) :- ans(X, X is random(f(x)), R).
t62(R) :- ans(ok, set_random(seed(a)), R).
t63(R) :- ans(ok, set_random(seed(1.5)), R).
t64(R) :- ans(ok, set_random(seed(1r3)), R).
t65(R) :- ans(ok, set_random(seed(_)), R).
t66(R) :- ans(ok, set_random(seed(f(x))), R).
t67(R) :- ans(ok, set_random(foo(1)), R).
t68(R) :- ans(ok, set_random(foo), R).
t69(R) :- ans(ok, set_random(1), R).
t70(R) :- ans(ok, set_random(_), R).
t71(R) :- ans(ok, set_random(seed), R).
t72(R) :- ans(ok, set_random(seed(1,2)), R).
t73(R) :- ans(ok, set_random(state(a)), R).
t74(R) :- ans(ok, set_random(state(5.0)), R).
t75(R) :- ans(ok, set_random(state(5)), R).
t76(R) :- ans(ok, set_random(state(_)), R).
t77(R) :- ans(ok, set_random(state(1r3)), R).
t78(R) :- ans(ok, set_random(state(f(x))), R).
t79(R) :- ans(ok, set_random([]), R).
t80(R) :- ans(ok, set_random([a]), R).
t81(R) :- ans(ok, set_random(seed(random)), R).
t82(R) :- ans(ok, (set_random(seed(random)), set_random(seed(random)), Xv is random(10) , integer(Xv)), R).
t83(R) :- ans(ok, (set_random(seed(random)), random_property(state(S)), integer(S), S > 0), R).
t84(R) :- ans(ok, (set_random(seed(random)), random_property(state(S1)), set_random(seed(random)), random_property(state(S2)), S1 \== S2), R).
t85(R) :- ans(ok, (set_random(seed(random)), A is random_float, A > 0.0, A < 1.0), R).
t86(R) :- ans(ok, (set_random(seed(random)), Xv is random(10**30), Xv >= 0, Xv < 10**30), R).
t87(R) :- ans(A-B-C-D, (set_random(seed(1)), random_property(state(S0)), S is S0 /\ (2**20000-1), A is S mod 10**30, B is msb(S), C is S >> 19900, D is S >> 19968), R).
t88(R) :- ans(A-B-C, (set_random(seed(0)), random_property(state(S0)), S is S0 /\ (2**20000-1), A is S mod 10**30, B is msb(S), C is S >> 19968), R).
t89(R) :- ans(A-B-C, (set_random(seed(-1)), random_property(state(S0)), S is S0 /\ (2**20000-1), A is S mod 10**30, B is msb(S), C is S >> 19968), R).
t90(R) :- ans(A-B-C, (set_random(seed(10**100)), random_property(state(S0)), S is S0 /\ (2**20000-1), A is S mod 10**30, B is msb(S), C is S >> 19968), R).
t91(R) :- ans(X, (set_random(seed(1)), random_property(state(S1)), set_random(seed(1)), random_property(state(S2)), S1 == S2 -> X = same ; X = different), R).
t92(R) :- ans(X, (set_random(seed(1)), random_property(state(S1)), set_random(seed(2)), random_property(state(S2)), S1 == S2 -> X = same ; X = different), R).
t93(R) :- ans(X, (set_random(seed(1)), random_property(state(S1)), random_property(state(S2)), S1 == S2 -> X = same ; X = different), R).
t94(R) :- ans(X, (set_random(seed(1)), random_property(state(S1)), _ is random(10), random_property(state(S2)), S1 == S2 -> X = same ; X = different), R).
t95(R) :- ans(A-B, (set_random(seed(1)), _ is random(10), random_property(state(S0)), S is S0 /\ (2**20000-1), A is S mod 10**30, B is S >> 19968), R).
t96(R) :- ans(A-B, (set_random(seed(1)), forall(between(1,350,_), _ is random(2**64)), random_property(state(S0)), S is S0 /\ (2**20000-1), A is S mod 10**30, B is S >> 19968), R).
t97(R) :- ans(A-B, (set_random(seed(1)), forall(between(1,312,_), _ is random(2**64)), random_property(state(S0)), S is S0 /\ (2**20000-1), A is S mod 10**30, B is S >> 19968), R).
t98(R) :- ans(A-B, (set_random(seed(1)), forall(between(1,313,_), _ is random(2**64)), random_property(state(S0)), S is S0 /\ (2**20000-1), A is S mod 10**30, B is S >> 19968), R).
t99(R) :- ans(A-B, (set_random(seed(1)), _ is random_float, random_property(state(S0)), S is S0 /\ (2**20000-1), A is S mod 10**30, B is S >> 19968), R).
t100(R) :- ans(X, (set_random(seed(1)), random_property(state(S0)), S is S0 /\ (2**20000-1), A is S mod 10**30, B is S >> 19968, X = A-B), R).
t101(R) :- ans(ok, (set_random(seed(1)), random_property(state(12345))), R).
t102(R) :- ans(ok, (set_random(seed(1)), random_property(state(a))), R).
t103(R) :- ans(ok, (set_random(seed(1)), random_property(state(S, T))), R).
t104(R) :- ans(ok, (set_random(seed(1)), random_property(state)), R).
t105(R) :- ans(ok, (set_random(seed(1)), random_property(seed(1))), R).
t106(R) :- ans(ok, (set_random(seed(1)), random_property(foo(S))), R).
t107(R) :- ans(ok, (set_random(seed(1)), random_property(_)), R).
t108(R) :- ans(ok, (set_random(seed(1)), random_property(a)), R).
t109(R) :- ans(ok, (set_random(seed(1)), random_property(1)), R).
t110(R) :- ans(X, (set_random(seed(11)), random_property(state(S)), L1=[A,B,C], A is random(1000), B is random(1000), C is random(2**80), set_random(state(S)), L2=[D,E,F], D is random(1000), E is random(1000), F is random(2**80), L1==L2 -> X = same(L1) ; X = different), R).
t111(R) :- ans(X, (set_random(seed(11)), forall(between(1,100,_), _ is random(1000)), random_property(state(S)), A is random(10**20), set_random(state(S)), B is random(10**20), A == B -> X = same ; X = different), R).
t112(R) :- ans(X, (set_random(seed(11)), forall(between(1,700,_), _ is random(1000)), random_property(state(S)), A is random(10**20), set_random(state(S)), B is random(10**20), A == B -> X = same ; X = different), R).
t113(R) :- ans(X, (set_random(seed(11)), random_property(state(S)), set_random(seed(12)), set_random(state(S)), random_property(state(T)), S == T -> X = same ; X = different), R).
t114(R) :- ans(X, (set_random(seed(11)), random_property(state(S)), A is random_float, set_random(state(S)), B is random_float, A == B -> X = same ; X = different), R).
t115(R) :- ans(A-B-C, (set_random(seed(1)), set_random(state(100000000000000000000000)), A is random(1000), B is random(1000), C is random(1000)), R).
t116(R) :- ans(A-B, (set_random(seed(1)), Nst is 2**64, set_random(state(Nst)), A is random(1000), B is random(1000)), R).
t117(R) :- ans(A-B, (set_random(seed(1)), Nst is 2**100, set_random(state(Nst)), random_property(state(S0)), S is S0 /\ (2**20000-1), A is S mod 10**30, B is S >> 19968), R).
t118(R) :- ans(A-B, (set_random(seed(1)), Nst is -(2**100), set_random(state(Nst)), random_property(state(S0)), S is S0 /\ (2**20000-1), A is S mod 10**30, B is S >> 19968), R).
t119(R) :- ans(A-B-C, (set_random(seed(1)), Nst is 2**70, set_random(state(Nst)), A is random(1000), B is random(1000), C is random(1000)), R).
t120(R) :- ans(A-B-C, (set_random(seed(1)), Nst is 2**20000, set_random(state(Nst)), A is random(1000), B is random(1000), C is random(1000)), R).
t121(R) :- ans(A-B, (set_random(seed(1)), Nst is 2**19999, set_random(state(Nst)), random_property(state(S0)), S is S0 /\ (2**20000-1), A is S mod 10**30, B is S >> 19968), R).
t122(R) :- ans(A-B, (set_random(seed(1)), Nst is 2**19968, set_random(state(Nst)), A is random(1000), B is random(1000)), R).
t123(R) :- ans(A-B, (set_random(seed(1)), Nst is 2**19969, set_random(state(Nst)), A is random(1000), B is random(1000)), R).
t124(R) :- ans(A, (set_random(seed(1)), set_random(state(0)), A is random(1000)), R).
t125(R) :- ans(A-B, (set_random(seed(1)), Nst is 2**62, set_random(state(Nst)), random_property(state(S0)), S is S0 /\ (2**20000-1), A is S mod 10**30, B is S >> 19968), R).
t126(R) :- ans(ok, set_random(state(9223372036854775807)), R).
t127(R) :- ans(ok, set_random(state(9223372036854775808)), R).
t128(R) :- ans(ok, set_random(state(-9223372036854775809)), R).
t129(R) :- ans(A-B, (set_random(seed(1)), forall(between(1,5,_), _ is random(1000)), random_property(state(S0)), S is S0 /\ (2**20000-1), A is S mod 10**30, B is S >> 19968), R).

t130(R) :- ans(L, (set_random(seed(72057594037927935)), L=[A,B], A is random(1000000), B is random(2**70)), R).
t131(R) :- ans(L, (set_random(seed(72057594037927936)), L=[A,B], A is random(1000000), B is random(2**70)), R).
t132(R) :- ans(L, (set_random(seed(-72057594037927936)), L=[A,B], A is random(1000000), B is random(2**70)), R).
t133(R) :- ans(L, (set_random(seed(-72057594037927937)), L=[A,B], A is random(1000000), B is random(2**70)), R).
t134(R) :- ans(L, (set_random(seed(-72057594037927935)), L=[A,B], A is random(1000000), B is random(2**70)), R).
t135(R) :- ans(L, (set_random(seed(9223372036854775807)), L=[A,B], A is random(1000000), B is random(2**70)), R).
t136(R) :- ans(L, (set_random(seed(-9223372036854775808)), L=[A,B], A is random(1000000), B is random(2**70)), R).
t137(R) :- ans(L, (set_random(seed(-9223372036854775809)), L=[A,B], A is random(1000000), B is random(2**70)), R).
t138(R) :- ans(A-B, (set_random(seed(1)), set_random(state(72057594037927935)), random_property(state(S0)), S is S0 /\ (2**20000-1), A is S mod 10**30, B is S >> 19968), R).
t139(R) :- ans(A-B, (set_random(seed(1)), set_random(state(72057594037927936)), random_property(state(S0)), S is S0 /\ (2**20000-1), A is S mod 10**30, B is S >> 19968), R).
t140(R) :- ans(A-B, (set_random(seed(1)), set_random(state(72057594037927937)), random_property(state(S0)), S is S0 /\ (2**20000-1), A is S mod 10**30, B is S >> 19968), R).
t141(R) :- ans(A-B, (set_random(seed(1)), set_random(state(-72057594037927936)), random_property(state(S0)), S is S0 /\ (2**20000-1), A is S mod 10**30, B is S >> 19968), R).
t142(R) :- ans(A-B, (set_random(seed(1)), set_random(state(9223372036854775807)), random_property(state(S0)), S is S0 /\ (2**20000-1), A is S mod 10**30, B is S >> 19968), R).
t143(R) :- ans(A-B, (set_random(seed(1)), set_random(state(-9223372036854775809)), random_property(state(S0)), S is S0 /\ (2**20000-1), A is S mod 10**30, B is S >> 19968), R).
