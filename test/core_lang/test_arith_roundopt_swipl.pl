% ORIGINAL: the rows of test/core_lang/test_arith_roundopt_swipl.jl — no swipl-devel counterpart.
% test/core_lang/test_arith_roundopt_swipl.pl — AR1's rows for directed rounding in arithmetic COMPILED under `optimise`
% (pl-vmi.c A_ENTER .. A_IS / A_LT .., A_ROUNDTOWARDS_A, A_ROUNDTOWARDS_V, A_FUNC2 roundtoward; pl-arith.c ar_roundtoward): a clause's `is/2`
% and comparisons are instructions, and they read the mode the process holds (set by `set_prolog_flag(float_rounding, M)`), not
% a flag lookup. The rows are the answers of the pin's swipl (10.1.20, 18168e62, two identical runs); each `tN(R)` is one row, R the
% answer. `1/3.0` is 0.3333333333333333 under to_nearest and to_zero and to_negative, 0.33333333333333337 under to_positive.
% Every row puts the flag back to to_nearest before it returns. The `is` of a row that throws is in its own clause `hN` (a goal
% inside catch/3 is called, not compiled). The `kN` rows are the KNOWN DIFFERENCES (see the .jl): not in the .out.
% UNTESTED on the kernel: written without a compile, the gate decides
:- set_prolog_flag(optimise, true).
% the flag set before: the compiled `is` reads it
t0(R) :- set_prolog_flag(float_rounding, to_positive), Y is 1/3.0, Z is -1/3.0, set_prolog_flag(float_rounding, to_nearest), R = Y-Z.
t1(R) :- set_prolog_flag(float_rounding, to_negative), Y is 1/3.0, Z is -1/3.0, set_prolog_flag(float_rounding, to_nearest), R = Y-Z.
t2(R) :- set_prolog_flag(float_rounding, to_zero), Y is 1/3.0, Z is -1/3.0, set_prolog_flag(float_rounding, to_nearest), R = Y-Z.
t3(R) :- set_prolog_flag(float_rounding, to_nearest), Y is 1/3.0, Z is -1/3.0, R = Y-Z.
% roundtoward(E, Mode), the mode an atom: A_ROUNDTOWARDS_A
t4(R) :- A is roundtoward(1/3.0, to_positive), B is roundtoward(1/3.0, to_negative), C is roundtoward(1/3.0, to_zero), D is roundtoward(1/3.0, to_nearest), R = [A,B,C,D].
t5(R) :- A is roundtoward(-1/3.0, to_positive), B is roundtoward(-1/3.0, to_negative), C is roundtoward(-1/3.0, to_zero), R = [A,B,C].
% ... the mode a variable bound at run time: A_ROUNDTOWARDS_V
rt(M, Y) :- Y is roundtoward(1/3.0, M).
t6(R) :- rt(to_positive, A), rt(to_negative, B), rt(to_zero, C), rt(to_nearest, D), R = [A,B,C,D].
t7(R) :- M = to_positive, A is roundtoward(1/3.0, M), B is 1/3.0, R = A-B.
% nested: the inner mode ends with its operand, the outer goes on (A_FUNC2 roundtoward restores the mode found)
t8(R) :- Y is roundtoward(roundtoward(1/3.0, to_zero) + roundtoward(1/3.0, to_positive), to_negative), R = Y.
t9(R) :- Y is roundtoward(roundtoward(1/3.0, to_positive) + 1/3.0, to_zero), Z is 1/3.0, R = Y-Z.
% the flag and roundtoward together: the roundtoward ends, the flag's mode is back
t10(R) :- set_prolog_flag(float_rounding, to_positive), A is roundtoward(1/3.0, to_zero), B is 1/3.0, set_prolog_flag(float_rounding, to_nearest), R = A-B.
t11(R) :- set_prolog_flag(float_rounding, to_negative), A is roundtoward(1/3.0, to_positive), B is 1/3.0, set_prolog_flag(float_rounding, to_nearest), R = A-B.
% a comparison under roundtoward, true or false, and the mode after it
t12(R) :- ( roundtoward(1/3.0, to_positive) =:= 0.33333333333333337 -> C = eq ; C = ne ), Y is 1/3.0, R = C-Y.
t13(R) :- ( roundtoward(1/3.0, to_positive) < 0.3333333333333333 -> C = lt ; C = nlt ), Y is 1/3.0, R = C-Y.
t14(R) :- set_prolog_flag(float_rounding, to_positive), ( 1/3.0 > 0.3333333333333333 -> C = gt ; C = ngt ), set_prolog_flag(float_rounding, to_nearest), R = C.
% an error in the operand of a roundtoward: the mode is back (a single roundtoward, or one not yet run)
h0 :- _ is roundtoward(1/0, to_positive).
h1 :- _ is roundtoward(roundtoward(1.0, to_zero) + (1/0), to_positive).
h2 :- _ is roundtoward(1.0, to_positive) + (1/0).
h3 :- _ is roundtoward(roundtoward(1.0, to_negative) + (1/0), to_zero).
h4 :- _ is 1/0.
after_throw(H, R) :- catch(H, error(F, _), true), Y is 1/3.0, Z is -1/3.0, set_prolog_flag(float_rounding, to_nearest), R = F-Y-Z.
t15(R) :- after_throw(h0, R).
t16(R) :- after_throw(h1, R).
t17(R) :- after_throw(h2, R).
t18(R) :- after_throw(h3, R).
t19(R) :- after_throw(h4, R).
% the mode a row leaves behind: a row that ends with the flag's mode still set would show in the row after it (flag to_nearest: A_ENTER sets no mode)
lead_is(Y) :- set_prolog_flag(float_rounding, to_positive), Y is 1/3.0.
lead_fv(Y) :- set_prolog_flag(float_rounding, to_positive), Z is 1/3.0, Y = Z.
lead_cmp :- set_prolog_flag(float_rounding, to_positive), 1/3.0 > 0.3333333333333333.
t20(R) :- lead_is(Y), set_prolog_flag(float_rounding, to_nearest), Z is 1/3.0, R = Y-Z.
t21(R) :- lead_fv(Y), set_prolog_flag(float_rounding, to_nearest), Z is 1/3.0, R = Y-Z.
t22(R) :- lead_cmp, set_prolog_flag(float_rounding, to_nearest), Z is 1/3.0, R = Z.
% the inner roundtoward's mode a variable bound at run time (A_ROUNDTOWARDS_V), the outer's mode back after it: the sum is under to_zero
rtv(M, Y) :- Y is roundtoward(roundtoward(1/3.0, M) + 1/3.0, to_zero).
t23(R) :- rtv(to_positive, Y), Z is 1/3.0, R = Y-Z.
% a variable bound to a COMPOUND, read by A_VAR inside roundtoward with the flag not to_nearest: the pin's a_var_n calls evalExpression, which never
% touches the hardware mode, so the walk of X runs in the roundtoward's mode (to_zero), not the flag's (to_positive): 0.3333333333333333
t24(R) :- set_prolog_flag(float_rounding, to_positive), X = 1/3.0, Z is roundtoward(X, to_zero), set_prolog_flag(float_rounding, to_nearest), R = Z.
rtx(X, M, Y) :- Y is roundtoward(X, M).
t25(R) :- set_prolog_flag(float_rounding, to_positive), rtx(1/3.0, to_zero, A), rtx(1/3.0, to_negative, B), set_prolog_flag(float_rounding, to_nearest), R = A-B.
% KNOWN DIFFERENCES (not in the .out): the pin's AR_CLEANUP puts back the mode the LAST roundtoward found, which is the OUTER
% roundtoward's mode when the error comes inside or after the inner one, so the mode of the outer stays set (a leak of the pin);
% the kernel keeps the entry mode in `ar_femode` and puts it back at every end, so no mode leaks.
h5 :- _ is roundtoward(roundtoward(1/0, to_zero), to_positive).
h6 :- _ is roundtoward((1/0) + roundtoward(1.0, to_zero), to_positive).
k0(R) :- after_throw(h5, R).
k1(R) :- after_throw(h6, R).
