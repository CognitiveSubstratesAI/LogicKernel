% ORIGINAL: the rows of test/core_lang/test_arith_round_swipl.jl — no swipl-devel counterpart.
% test/core_lang/test_arith_round_swipl.pl — AR1's rows for the directed rounding modes (pl-arith.c): the flag float_rounding,
% roundtoward/2, the float flags and their errors, the mode of the cr_* functions, ar_pi/ar_e, rational to float.
% Each `tN(R)` is one row; test_arith_round_swipl.out holds the pin's (swipl 10.1.20, 18168e62) answers: R is the answer term, `false`,
% or error(Formal, Context); a float that is not finite is named (posinf, neginf, nan). The hardware mode is the process's in swipl
% and the evaluation's in the kernel (the DIVERGES in pl-arith.jl's header): swipl leaves the mode set after an error in the first
% argument of roundtoward/2, so every row ends in rst, `set_prolog_flag(float_rounding, to_nearest)`, which sets the mode on both sides.
% UNTESTED on the kernel: written without a compile, the gate decides
rst :- set_prolog_flag(float_rounding, to_nearest).
fl(X, R) :- float(X), X =\= X, !, R = nan.
fl(X, R) :- float(X), X =:= inf, !, R = posinf.
fl(X, R) :- float(X), X =:= -inf, !, R = neginf.
fl(X, X).
fin(ok(X), R) :- !, fl(X, R).
fin(R, R).
ev0(E, R0) :- catch(( X is E -> R0 = ok(X) ; R0 = false ), error(Er, C), R0 = error(Er, C)).
ev(E, R) :- ev0(E, R0), rst, fin(R0, R).
fm(M, E, R) :- set_prolog_flag(float_rounding, M), ev0(E, R0), rst, fin(R0, R).
rt(M, E, R) :- ev0(roundtoward(E, M), R0), rst, fin(R0, R).
fl_get(R) :- findall(K-V, ( member(K, [float_overflow, float_zero_div, float_undefined, float_underflow, float_rounding]), current_prolog_flag(K, V) ), R).
fl_set(K, V, R) :- catch(( set_prolog_flag(K, V) -> R0 = ok ; R0 = false ), error(Er, C), R0 = error(Er, C)),
    ( K == float_rounding -> rst ; reset_flag(K) ), R = R0.
reset_flag(float_overflow) :- set_prolog_flag(float_overflow, error).
reset_flag(float_zero_div) :- set_prolog_flag(float_zero_div, error).
reset_flag(float_undefined) :- set_prolog_flag(float_undefined, error).
reset_flag(float_underflow) :- set_prolog_flag(float_underflow, ignore).
reset_flag(max_rational_size_action).
reset_flag(max_rational_size).
reset_flag(max_integer_size).
t0(R) :- fm(to_nearest, 1/3.0, R).
t1(R) :- fm(to_nearest, 2/3.0, R).
t2(R) :- fm(to_nearest, -1/3.0, R).
t3(R) :- fm(to_nearest, 1.0e308*10, R).
t4(R) :- fm(to_nearest, -1.0e308*10, R).
t5(R) :- fm(to_nearest, 0.1+0.2, R).
t6(R) :- fm(to_nearest, 1.0-0.9, R).
t7(R) :- fm(to_nearest, 3*0.1, R).
t8(R) :- fm(to_nearest, sqrt(2), R).
t9(R) :- fm(to_nearest, sqrt(0.5), R).
t10(R) :- fm(to_nearest, sin(0.1), R).
t11(R) :- fm(to_nearest, sin(2.0), R).
t12(R) :- fm(to_nearest, cos(0.5), R).
t13(R) :- fm(to_nearest, cos(1.0), R).
t14(R) :- fm(to_nearest, tan(0.1), R).
t15(R) :- fm(to_nearest, tan(1.0), R).
t16(R) :- fm(to_nearest, asin(0.5), R).
t17(R) :- fm(to_nearest, acos(0.5), R).
t18(R) :- fm(to_nearest, atan(1.0), R).
t19(R) :- fm(to_nearest, atan2(1.0,3.0), R).
t20(R) :- fm(to_nearest, exp(0.1), R).
t21(R) :- fm(to_nearest, exp(1.0), R).
t22(R) :- fm(to_nearest, exp(710.0), R).
t23(R) :- fm(to_nearest, log(2.0), R).
t24(R) :- fm(to_nearest, log(0.5), R).
t25(R) :- fm(to_nearest, log10(2.0), R).
t26(R) :- fm(to_nearest, sinh(0.5), R).
t27(R) :- fm(to_nearest, cosh(0.5), R).
t28(R) :- fm(to_nearest, cosh(2.0), R).
t29(R) :- fm(to_nearest, tanh(0.5), R).
t30(R) :- fm(to_nearest, erf(0.5), R).
t31(R) :- fm(to_nearest, erfc(0.5), R).
t32(R) :- fm(to_nearest, asinh(0.5), R).
t33(R) :- fm(to_nearest, acosh(1.5), R).
t34(R) :- fm(to_nearest, atanh(0.5), R).
t35(R) :- fm(to_nearest, lgamma(2.5), R).
t36(R) :- fm(to_nearest, 2.0**0.5, R).
t37(R) :- fm(to_nearest, 2**0.5, R).
t38(R) :- fm(to_nearest, 0.5**2.5, R).
t39(R) :- fm(to_nearest, 2**(1 rdiv 3), R).
t40(R) :- fm(to_nearest, (-8)**(1 rdiv 3), R).
t41(R) :- fm(to_nearest, pi, R).
t42(R) :- fm(to_nearest, e, R).
t43(R) :- fm(to_nearest, pi*2, R).
t44(R) :- fm(to_nearest, float(1 rdiv 3), R).
t45(R) :- fm(to_nearest, (1 rdiv 3)+0.0, R).
t46(R) :- fm(to_nearest, float(2 rdiv 3), R).
t47(R) :- fm(to_nearest, float(-1 rdiv 3), R).
t48(R) :- fm(to_nearest, float(10**30+1), R).
t49(R) :- fm(to_nearest, float(2**70+1), R).
t50(R) :- fm(to_nearest, float(-(2**70+1)), R).
t51(R) :- fm(to_nearest, 10**30/3.0, R).
t52(R) :- fm(to_nearest, float(1)/3, R).
t53(R) :- fm(to_nearest, 0.1+0.2+0.3, R).
t54(R) :- fm(to_nearest, 1.0e-320/10, R).
t55(R) :- fm(to_nearest, nexttoward(1.0,2), R).
t56(R) :- fm(to_nearest, float_fractional_part(2.7), R).
t57(R) :- fm(to_nearest, 2.0** -3, R).
t58(R) :- fm(to_nearest, 10.0**15, R).
t59(R) :- fm(to_nearest, 10.0**23, R).
t60(R) :- fm(to_nearest, 2**(-1 rdiv 3), R).
t61(R) :- fm(to_nearest, 7 rdiv 3*1.0, R).
t62(R) :- fm(to_nearest, truncate(1.0e20/3), R).
t63(R) :- fm(to_nearest, 1.0e308+1.0e308, R).
t64(R) :- fm(to_nearest, 1/0.0, R).
t65(R) :- fm(to_positive, 1/3.0, R).
t66(R) :- fm(to_positive, 2/3.0, R).
t67(R) :- fm(to_positive, -1/3.0, R).
t68(R) :- fm(to_positive, 1.0e308*10, R).
t69(R) :- fm(to_positive, -1.0e308*10, R).
t70(R) :- fm(to_positive, 0.1+0.2, R).
t71(R) :- fm(to_positive, 1.0-0.9, R).
t72(R) :- fm(to_positive, 3*0.1, R).
t73(R) :- fm(to_positive, sqrt(2), R).
t74(R) :- fm(to_positive, sqrt(0.5), R).
t75(R) :- fm(to_positive, sin(0.1), R).
t76(R) :- fm(to_positive, sin(2.0), R).
t77(R) :- fm(to_positive, cos(0.5), R).
t78(R) :- fm(to_positive, cos(1.0), R).
t79(R) :- fm(to_positive, tan(0.1), R).
t80(R) :- fm(to_positive, tan(1.0), R).
t81(R) :- fm(to_positive, asin(0.5), R).
t82(R) :- fm(to_positive, acos(0.5), R).
t83(R) :- fm(to_positive, atan(1.0), R).
t84(R) :- fm(to_positive, atan2(1.0,3.0), R).
t85(R) :- fm(to_positive, exp(0.1), R).
t86(R) :- fm(to_positive, exp(1.0), R).
t87(R) :- fm(to_positive, exp(710.0), R).
t88(R) :- fm(to_positive, log(2.0), R).
t89(R) :- fm(to_positive, log(0.5), R).
t90(R) :- fm(to_positive, log10(2.0), R).
t91(R) :- fm(to_positive, sinh(0.5), R).
t92(R) :- fm(to_positive, cosh(0.5), R).
t93(R) :- fm(to_positive, cosh(2.0), R).
t94(R) :- fm(to_positive, tanh(0.5), R).
t95(R) :- fm(to_positive, erf(0.5), R).
t96(R) :- fm(to_positive, erfc(0.5), R).
t97(R) :- fm(to_positive, asinh(0.5), R).
t98(R) :- fm(to_positive, acosh(1.5), R).
t99(R) :- fm(to_positive, atanh(0.5), R).
t100(R) :- fm(to_positive, lgamma(2.5), R).
t101(R) :- fm(to_positive, 2.0**0.5, R).
t102(R) :- fm(to_positive, 2**0.5, R).
t103(R) :- fm(to_positive, 0.5**2.5, R).
t104(R) :- fm(to_positive, 2**(1 rdiv 3), R).
t105(R) :- fm(to_positive, (-8)**(1 rdiv 3), R).
t106(R) :- fm(to_positive, pi, R).
t107(R) :- fm(to_positive, e, R).
t108(R) :- fm(to_positive, pi*2, R).
t109(R) :- fm(to_positive, float(1 rdiv 3), R).
t110(R) :- fm(to_positive, (1 rdiv 3)+0.0, R).
t111(R) :- fm(to_positive, float(2 rdiv 3), R).
t112(R) :- fm(to_positive, float(-1 rdiv 3), R).
t113(R) :- fm(to_positive, float(10**30+1), R).
t114(R) :- fm(to_positive, float(2**70+1), R).
t115(R) :- fm(to_positive, float(-(2**70+1)), R).
t116(R) :- fm(to_positive, 10**30/3.0, R).
t117(R) :- fm(to_positive, float(1)/3, R).
t118(R) :- fm(to_positive, 0.1+0.2+0.3, R).
t119(R) :- fm(to_positive, 1.0e-320/10, R).
t120(R) :- fm(to_positive, nexttoward(1.0,2), R).
t121(R) :- fm(to_positive, float_fractional_part(2.7), R).
t122(R) :- fm(to_positive, 2.0** -3, R).
t123(R) :- fm(to_positive, 10.0**15, R).
t124(R) :- fm(to_positive, 10.0**23, R).
t125(R) :- fm(to_positive, 2**(-1 rdiv 3), R).
t126(R) :- fm(to_positive, 7 rdiv 3*1.0, R).
t127(R) :- fm(to_positive, truncate(1.0e20/3), R).
t128(R) :- fm(to_positive, 1.0e308+1.0e308, R).
t129(R) :- fm(to_positive, 1/0.0, R).
t130(R) :- fm(to_negative, 1/3.0, R).
t131(R) :- fm(to_negative, 2/3.0, R).
t132(R) :- fm(to_negative, -1/3.0, R).
t133(R) :- fm(to_negative, 1.0e308*10, R).
t134(R) :- fm(to_negative, -1.0e308*10, R).
t135(R) :- fm(to_negative, 0.1+0.2, R).
t136(R) :- fm(to_negative, 1.0-0.9, R).
t137(R) :- fm(to_negative, 3*0.1, R).
t138(R) :- fm(to_negative, sqrt(2), R).
t139(R) :- fm(to_negative, sqrt(0.5), R).
t140(R) :- fm(to_negative, sin(0.1), R).
t141(R) :- fm(to_negative, sin(2.0), R).
t142(R) :- fm(to_negative, cos(0.5), R).
t143(R) :- fm(to_negative, cos(1.0), R).
t144(R) :- fm(to_negative, tan(0.1), R).
t145(R) :- fm(to_negative, tan(1.0), R).
t146(R) :- fm(to_negative, asin(0.5), R).
t147(R) :- fm(to_negative, acos(0.5), R).
t148(R) :- fm(to_negative, atan(1.0), R).
t149(R) :- fm(to_negative, atan2(1.0,3.0), R).
t150(R) :- fm(to_negative, exp(0.1), R).
t151(R) :- fm(to_negative, exp(1.0), R).
t152(R) :- fm(to_negative, exp(710.0), R).
t153(R) :- fm(to_negative, log(2.0), R).
t154(R) :- fm(to_negative, log(0.5), R).
t155(R) :- fm(to_negative, log10(2.0), R).
t156(R) :- fm(to_negative, sinh(0.5), R).
t157(R) :- fm(to_negative, cosh(0.5), R).
t158(R) :- fm(to_negative, cosh(2.0), R).
t159(R) :- fm(to_negative, tanh(0.5), R).
t160(R) :- fm(to_negative, erf(0.5), R).
t161(R) :- fm(to_negative, erfc(0.5), R).
t162(R) :- fm(to_negative, asinh(0.5), R).
t163(R) :- fm(to_negative, acosh(1.5), R).
t164(R) :- fm(to_negative, atanh(0.5), R).
t165(R) :- fm(to_negative, lgamma(2.5), R).
t166(R) :- fm(to_negative, 2.0**0.5, R).
t167(R) :- fm(to_negative, 2**0.5, R).
t168(R) :- fm(to_negative, 0.5**2.5, R).
t169(R) :- fm(to_negative, 2**(1 rdiv 3), R).
t170(R) :- fm(to_negative, (-8)**(1 rdiv 3), R).
t171(R) :- fm(to_negative, pi, R).
t172(R) :- fm(to_negative, e, R).
t173(R) :- fm(to_negative, pi*2, R).
t174(R) :- fm(to_negative, float(1 rdiv 3), R).
t175(R) :- fm(to_negative, (1 rdiv 3)+0.0, R).
t176(R) :- fm(to_negative, float(2 rdiv 3), R).
t177(R) :- fm(to_negative, float(-1 rdiv 3), R).
t178(R) :- fm(to_negative, float(10**30+1), R).
t179(R) :- fm(to_negative, float(2**70+1), R).
t180(R) :- fm(to_negative, float(-(2**70+1)), R).
t181(R) :- fm(to_negative, 10**30/3.0, R).
t182(R) :- fm(to_negative, float(1)/3, R).
t183(R) :- fm(to_negative, 0.1+0.2+0.3, R).
t184(R) :- fm(to_negative, 1.0e-320/10, R).
t185(R) :- fm(to_negative, nexttoward(1.0,2), R).
t186(R) :- fm(to_negative, float_fractional_part(2.7), R).
t187(R) :- fm(to_negative, 2.0** -3, R).
t188(R) :- fm(to_negative, 10.0**15, R).
t189(R) :- fm(to_negative, 10.0**23, R).
t190(R) :- fm(to_negative, 2**(-1 rdiv 3), R).
t191(R) :- fm(to_negative, 7 rdiv 3*1.0, R).
t192(R) :- fm(to_negative, truncate(1.0e20/3), R).
t193(R) :- fm(to_negative, 1.0e308+1.0e308, R).
t194(R) :- fm(to_negative, 1/0.0, R).
t195(R) :- fm(to_zero, 1/3.0, R).
t196(R) :- fm(to_zero, 2/3.0, R).
t197(R) :- fm(to_zero, -1/3.0, R).
t198(R) :- fm(to_zero, 1.0e308*10, R).
t199(R) :- fm(to_zero, -1.0e308*10, R).
t200(R) :- fm(to_zero, 0.1+0.2, R).
t201(R) :- fm(to_zero, 1.0-0.9, R).
t202(R) :- fm(to_zero, 3*0.1, R).
t203(R) :- fm(to_zero, sqrt(2), R).
t204(R) :- fm(to_zero, sqrt(0.5), R).
t205(R) :- fm(to_zero, sin(0.1), R).
t206(R) :- fm(to_zero, sin(2.0), R).
t207(R) :- fm(to_zero, cos(0.5), R).
t208(R) :- fm(to_zero, cos(1.0), R).
t209(R) :- fm(to_zero, tan(0.1), R).
t210(R) :- fm(to_zero, tan(1.0), R).
t211(R) :- fm(to_zero, asin(0.5), R).
t212(R) :- fm(to_zero, acos(0.5), R).
t213(R) :- fm(to_zero, atan(1.0), R).
t214(R) :- fm(to_zero, atan2(1.0,3.0), R).
t215(R) :- fm(to_zero, exp(0.1), R).
t216(R) :- fm(to_zero, exp(1.0), R).
t217(R) :- fm(to_zero, exp(710.0), R).
t218(R) :- fm(to_zero, log(2.0), R).
t219(R) :- fm(to_zero, log(0.5), R).
t220(R) :- fm(to_zero, log10(2.0), R).
t221(R) :- fm(to_zero, sinh(0.5), R).
t222(R) :- fm(to_zero, cosh(0.5), R).
t223(R) :- fm(to_zero, cosh(2.0), R).
t224(R) :- fm(to_zero, tanh(0.5), R).
t225(R) :- fm(to_zero, erf(0.5), R).
t226(R) :- fm(to_zero, erfc(0.5), R).
t227(R) :- fm(to_zero, asinh(0.5), R).
t228(R) :- fm(to_zero, acosh(1.5), R).
t229(R) :- fm(to_zero, atanh(0.5), R).
t230(R) :- fm(to_zero, lgamma(2.5), R).
t231(R) :- fm(to_zero, 2.0**0.5, R).
t232(R) :- fm(to_zero, 2**0.5, R).
t233(R) :- fm(to_zero, 0.5**2.5, R).
t234(R) :- fm(to_zero, 2**(1 rdiv 3), R).
t235(R) :- fm(to_zero, (-8)**(1 rdiv 3), R).
t236(R) :- fm(to_zero, pi, R).
t237(R) :- fm(to_zero, e, R).
t238(R) :- fm(to_zero, pi*2, R).
t239(R) :- fm(to_zero, float(1 rdiv 3), R).
t240(R) :- fm(to_zero, (1 rdiv 3)+0.0, R).
t241(R) :- fm(to_zero, float(2 rdiv 3), R).
t242(R) :- fm(to_zero, float(-1 rdiv 3), R).
t243(R) :- fm(to_zero, float(10**30+1), R).
t244(R) :- fm(to_zero, float(2**70+1), R).
t245(R) :- fm(to_zero, float(-(2**70+1)), R).
t246(R) :- fm(to_zero, 10**30/3.0, R).
t247(R) :- fm(to_zero, float(1)/3, R).
t248(R) :- fm(to_zero, 0.1+0.2+0.3, R).
t249(R) :- fm(to_zero, 1.0e-320/10, R).
t250(R) :- fm(to_zero, nexttoward(1.0,2), R).
t251(R) :- fm(to_zero, float_fractional_part(2.7), R).
t252(R) :- fm(to_zero, 2.0** -3, R).
t253(R) :- fm(to_zero, 10.0**15, R).
t254(R) :- fm(to_zero, 10.0**23, R).
t255(R) :- fm(to_zero, 2**(-1 rdiv 3), R).
t256(R) :- fm(to_zero, 7 rdiv 3*1.0, R).
t257(R) :- fm(to_zero, truncate(1.0e20/3), R).
t258(R) :- fm(to_zero, 1.0e308+1.0e308, R).
t259(R) :- fm(to_zero, 1/0.0, R).
t260(R) :- rt(to_nearest, 1/3.0, R).
t261(R) :- rt(to_nearest, 2/3.0, R).
t262(R) :- rt(to_nearest, -1/3.0, R).
t263(R) :- rt(to_nearest, 1.0e308*10, R).
t264(R) :- rt(to_nearest, sqrt(2), R).
t265(R) :- rt(to_nearest, sin(0.1), R).
t266(R) :- rt(to_nearest, cos(1.0), R).
t267(R) :- rt(to_nearest, exp(1.0), R).
t268(R) :- rt(to_nearest, log(2.0), R).
t269(R) :- rt(to_nearest, atan2(1.0,3.0), R).
t270(R) :- rt(to_nearest, 2**(1 rdiv 3), R).
t271(R) :- rt(to_nearest, float(1 rdiv 3), R).
t272(R) :- rt(to_nearest, float(2**70+1), R).
t273(R) :- rt(to_nearest, pi, R).
t274(R) :- rt(to_nearest, e, R).
t275(R) :- rt(to_nearest, 0.1+0.2, R).
t276(R) :- rt(to_nearest, cosh(0.5), R).
t277(R) :- rt(to_nearest, erf(0.5), R).
t278(R) :- rt(to_nearest, 2.0**0.5, R).
t279(R) :- rt(to_positive, 1/3.0, R).
t280(R) :- rt(to_positive, 2/3.0, R).
t281(R) :- rt(to_positive, -1/3.0, R).
t282(R) :- rt(to_positive, 1.0e308*10, R).
t283(R) :- rt(to_positive, sqrt(2), R).
t284(R) :- rt(to_positive, sin(0.1), R).
t285(R) :- rt(to_positive, cos(1.0), R).
t286(R) :- rt(to_positive, exp(1.0), R).
t287(R) :- rt(to_positive, log(2.0), R).
t288(R) :- rt(to_positive, atan2(1.0,3.0), R).
t289(R) :- rt(to_positive, 2**(1 rdiv 3), R).
t290(R) :- rt(to_positive, float(1 rdiv 3), R).
t291(R) :- rt(to_positive, float(2**70+1), R).
t292(R) :- rt(to_positive, pi, R).
t293(R) :- rt(to_positive, e, R).
t294(R) :- rt(to_positive, 0.1+0.2, R).
t295(R) :- rt(to_positive, cosh(0.5), R).
t296(R) :- rt(to_positive, erf(0.5), R).
t297(R) :- rt(to_positive, 2.0**0.5, R).
t298(R) :- rt(to_negative, 1/3.0, R).
t299(R) :- rt(to_negative, 2/3.0, R).
t300(R) :- rt(to_negative, -1/3.0, R).
t301(R) :- rt(to_negative, 1.0e308*10, R).
t302(R) :- rt(to_negative, sqrt(2), R).
t303(R) :- rt(to_negative, sin(0.1), R).
t304(R) :- rt(to_negative, cos(1.0), R).
t305(R) :- rt(to_negative, exp(1.0), R).
t306(R) :- rt(to_negative, log(2.0), R).
t307(R) :- rt(to_negative, atan2(1.0,3.0), R).
t308(R) :- rt(to_negative, 2**(1 rdiv 3), R).
t309(R) :- rt(to_negative, float(1 rdiv 3), R).
t310(R) :- rt(to_negative, float(2**70+1), R).
t311(R) :- rt(to_negative, pi, R).
t312(R) :- rt(to_negative, e, R).
t313(R) :- rt(to_negative, 0.1+0.2, R).
t314(R) :- rt(to_negative, cosh(0.5), R).
t315(R) :- rt(to_negative, erf(0.5), R).
t316(R) :- rt(to_negative, 2.0**0.5, R).
t317(R) :- rt(to_zero, 1/3.0, R).
t318(R) :- rt(to_zero, 2/3.0, R).
t319(R) :- rt(to_zero, -1/3.0, R).
t320(R) :- rt(to_zero, 1.0e308*10, R).
t321(R) :- rt(to_zero, sqrt(2), R).
t322(R) :- rt(to_zero, sin(0.1), R).
t323(R) :- rt(to_zero, cos(1.0), R).
t324(R) :- rt(to_zero, exp(1.0), R).
t325(R) :- rt(to_zero, log(2.0), R).
t326(R) :- rt(to_zero, atan2(1.0,3.0), R).
t327(R) :- rt(to_zero, 2**(1 rdiv 3), R).
t328(R) :- rt(to_zero, float(1 rdiv 3), R).
t329(R) :- rt(to_zero, float(2**70+1), R).
t330(R) :- rt(to_zero, pi, R).
t331(R) :- rt(to_zero, e, R).
t332(R) :- rt(to_zero, 0.1+0.2, R).
t333(R) :- rt(to_zero, cosh(0.5), R).
t334(R) :- rt(to_zero, erf(0.5), R).
t335(R) :- rt(to_zero, 2.0**0.5, R).
t336(R) :- ev(roundtoward(roundtoward(1/3.0,to_negative)+1/3.0, to_positive), R).
t337(R) :- ev(roundtoward(roundtoward(1/3.0,to_positive)+1/3.0, to_negative), R).
t338(R) :- ev(roundtoward(1/3.0,to_positive)+roundtoward(1/3.0,to_negative), R).
t339(R) :- ev(roundtoward(1/3.0,to_positive)-roundtoward(1/3.0,to_negative), R).
t340(R) :- ev(1/3.0+roundtoward(1/3.0,to_negative), R).
t341(R) :- ev(roundtoward(1/3.0,to_negative)+1/3.0, R).
t342(R) :- ev(roundtoward(1/3.0,to_negative)*3, R).
t343(R) :- ev(roundtoward(roundtoward(1/3.0,to_negative),to_positive)+1/3.0, R).
t344(R) :- ev(roundtoward(2,to_zero), R).
t345(R) :- ev(roundtoward(1 rdiv 3, to_positive), R).
t346(R) :- ev(roundtoward(1+2, to_positive), R).
t347(R) :- ev(roundtoward(1/3.0, to_nearest)+roundtoward(1/3.0, to_positive), R).
t348(R) :- (M = to_zero, ev(roundtoward(-1/3.0, M), R)).
t349(R) :- (M = to_positive, ev(roundtoward(1/3.0, M)+roundtoward(1/3.0, M), R)).
t350(R) :- ev(roundtoward(1/3.0, foo), R).
t351(R) :- ev(roundtoward(1/3.0, 1), R).
t352(R) :- ev(roundtoward(1/3.0, _), R).
t353(R) :- ev(roundtoward(1/3.0, "to_zero"), R).
t354(R) :- ev(roundtoward(1/3.0, f(x)), R).
t355(R) :- ev(roundtoward(1/3.0, [a]), R).
t356(R) :- ev(roundtoward(1/3.0, 'to_Zero'), R).
t357(R) :- ev(roundtoward(1/3.0), R).
t358(R) :- ev(roundtoward(1/3.0, to_zero, x), R).
t359(R) :- ev(roundtoward(_, to_positive), R).
t360(R) :- ev(roundtoward(foo+1, to_positive), R).
t361(R) :- ev(roundtoward(a, to_positive), R).
t362(R) :- ev(roundtoward(1/0, to_positive), R).
t363(R) :- ev(roundtoward(1/0.0, to_positive), R).
t364(R) :- ev(roundtoward(foo, bar), R).
t365(R) :- ev(roundtoward(1, 2), R).
t366(R) :- ev(roundtoward(to_zero, to_zero), R).
t367(R) :- ev(roundtoward("a", to_positive), R).
t368(R) :- ev(roundtoward([0'a], to_positive), R).
t369(R) :- ev(roundtoward(1/3.0, to_positive) > 0.3, R).
t370(R) :- ev(roundtoward(1.0e308*10, to_positive), R).
t371(R) :- ev(roundtoward(1.0e308*10, to_negative), R).
t372(R) :- ev(roundtoward(-1.0e308*10, to_negative), R).
t373(R) :- ev(roundtoward(-1.0e308*10, to_positive), R).
t374(R) :- ev(roundtoward(1.0e308*10, to_zero), R).
t375(R) :- fl_get(R).
t376(R) :- (set_prolog_flag(float_rounding, to_positive), current_prolog_flag(float_rounding, M), rst, R = M).
t377(R) :- (set_prolog_flag(float_rounding, to_negative), current_prolog_flag(float_rounding, M), rst, R = M).
t378(R) :- (set_prolog_flag(float_rounding, to_zero), current_prolog_flag(float_rounding, M), rst, R = M).
t379(R) :- (set_prolog_flag(float_rounding, to_zero), set_prolog_flag(float_rounding, to_nearest), current_prolog_flag(float_rounding, M), R = M).
t380(R) :- fl_set(float_rounding, foo, R).
t381(R) :- fl_set(float_rounding, 1, R).
t382(R) :- fl_set(float_rounding, _, R).
t383(R) :- fl_set(float_rounding, f(x), R).
t384(R) :- fl_set(float_rounding, "to_zero", R).
t385(R) :- fl_set(float_rounding, infinity, R).
t386(R) :- fl_set(float_overflow, foo, R).
t387(R) :- fl_set(float_overflow, 1, R).
t388(R) :- fl_set(float_overflow, nan, R).
t389(R) :- fl_set(float_overflow, ignore, R).
t390(R) :- fl_set(float_zero_div, foo, R).
t391(R) :- fl_set(float_zero_div, nan, R).
t392(R) :- fl_set(float_undefined, foo, R).
t393(R) :- fl_set(float_undefined, infinity, R).
t394(R) :- fl_set(float_underflow, foo, R).
t395(R) :- fl_set(float_underflow, infinity, R).
t396(R) :- fl_set(float_underflow, nan, R).
t397(R) :- fl_set(max_rational_size_action, foo, R).
t398(R) :- fl_set(max_rational_size_action, 1, R).
t399(R) :- fl_set(max_rational_size_action, _, R).
t400(R) :- fl_set(max_rational_size, foo, R).
t401(R) :- fl_set(max_rational_size, -1, R).
t402(R) :- fl_set(max_rational_size, _, R).
t403(R) :- fl_set(max_rational_size, 1.5, R).
t404(R) :- fl_set(max_integer_size, foo, R).
t405(R) :- fl_set(max_integer_size, -5, R).
t406(R) :- fl_set(max_integer_size, _, R).
t407(R) :- fl_set(max_integer_size, f(x), R).
t408(R) :- (set_prolog_flag(float_overflow, infinity), ev(1.0e308*10, R0), set_prolog_flag(float_overflow, error), R = R0).
t409(R) :- (set_prolog_flag(float_overflow, infinity), ev(-1.0e308*10, R0), set_prolog_flag(float_overflow, error), R = R0).
t410(R) :- (set_prolog_flag(float_overflow, infinity), ev(exp(710.0), R0), set_prolog_flag(float_overflow, error), R = R0).
t411(R) :- (set_prolog_flag(float_overflow, infinity), current_prolog_flag(float_overflow, V), set_prolog_flag(float_overflow, error), R = V).
t412(R) :- (set_prolog_flag(float_zero_div, infinity), ev(1/0.0, R0), ev(-1/0.0, R1), set_prolog_flag(float_zero_div, error), R = R0-R1).
t413(R) :- (set_prolog_flag(float_undefined, nan), ev(inf-inf, R0), ev(sqrt(-1.0), R1), set_prolog_flag(float_undefined, error), R = R0-R1).
t414(R) :- (set_prolog_flag(float_underflow, error), ev(1.0e-320/10, R0), set_prolog_flag(float_underflow, ignore), R = R0).
t415(R) :- (set_prolog_flag(float_underflow, error), ev(1.0e-300*1.0e-300, R0), set_prolog_flag(float_underflow, ignore), R = R0).
t416(R) :- (set_prolog_flag(float_overflow, infinity), set_prolog_flag(float_rounding, to_positive), ev(1.0e308*10, R0), rst, set_prolog_flag(float_overflow, error), R = R0).
t417(R) :- (set_prolog_flag(float_overflow, infinity), set_prolog_flag(float_rounding, to_negative), ev(1.0e308*10, R0), rst, set_prolog_flag(float_overflow, error), R = R0).
t418(R) :- (set_prolog_flag(float_overflow, infinity), set_prolog_flag(float_rounding, to_zero), ev(1.0e308*10, R0), rst, set_prolog_flag(float_overflow, error), R = R0).
t419(R) :- (set_prolog_flag(float_overflow, infinity), set_prolog_flag(float_rounding, to_negative), ev(-1.0e308*10, R0), rst, set_prolog_flag(float_overflow, error), R = R0).
t420(R) :- (set_prolog_flag(float_rounding, to_positive), ev(roundtoward(1/3.0, to_negative), R0), rst, R = R0).
t421(R) :- (set_prolog_flag(float_rounding, to_positive), ev(roundtoward(1/3.0, to_negative)+1/3.0, R0), rst, R = R0).
t422(R) :- (set_prolog_flag(float_rounding, to_negative), ev(roundtoward(1/3.0, to_positive)+1/3.0, R0), rst, R = R0).
t423(R) :- (set_prolog_flag(float_rounding, to_positive), ev(1/3.0+roundtoward(1/3.0, to_nearest), R0), rst, R = R0).
t424(R) :- (set_prolog_flag(float_rounding, to_positive), ev(1/3.0, R0), ev(2/3.0, R1), rst, ev(1/3.0, R2), R = [R0,R1,R2]).
t425(R) :- (set_prolog_flag(float_rounding, to_negative), ev(roundtoward(1/3.0, to_positive), R0), ev(1/3.0, R1), rst, R = R0-R1).
t426(R) :- (set_prolog_flag(float_rounding, to_positive), ( 1/3.0 > 0.3333333333333333 -> R0 = yes ; R0 = no ), rst, R = R0).
t427(R) :- (set_prolog_flag(float_rounding, to_positive), X is 1/3.0, rst, Y is 1/3.0, ( X > Y -> R = up ; R = notup )).
t428(R) :- (set_prolog_flag(float_rounding, to_negative), X is 1/3.0, rst, Y is 1/3.0, ( X < Y -> R = down ; R = notdown )).
t429(R) :- (set_prolog_flag(float_rounding, to_zero), X is -1/3.0, rst, Y is -1/3.0, ( X > Y -> R = zero ; R = notzero )).
t430(R) :- (set_prolog_flag(float_rounding, to_positive), X is 1/3.0, rst, Y is nexttoward(1/3.0, 1), ( X =:= Y -> R = up1 ; R = other )).
t431(R) :- (set_prolog_flag(float_rounding, to_positive), X is 0.1+0.2, rst, R = X).
t432(R) :- fl_set(max_rational_size, infinite, R).
t433(R) :- fl_set(max_integer_size, infinite, R).
t434(R) :- fl_set(max_rational_size_action, error, R).
t435(R) :- fm(to_zero, float((2**1100) rdiv 3), R).
t436(R) :- fm(to_zero, float(-(2**1100) rdiv 3), R).
t437(R) :- fm(to_positive, float(-(2**1100) rdiv 3), R).
t438(R) :- fm(to_negative, float((2**1100) rdiv 3), R).
t439(R) :- fm(to_positive, float(1 rdiv (3*2**1100)), R).
t440(R) :- fm(to_negative, float(-1 rdiv (3*2**1100)), R).
t441(R) :- fm(to_nearest, float(1 rdiv (3*2**1100)), R).
t442(R) :- fm(to_nearest, float((2**1100) rdiv 3), R).
t443(R) :- fm(to_positive, float((2**1100) rdiv 3), R).
t444(R) :- fm(to_zero, float(1 rdiv (3*2**1100)), R).
