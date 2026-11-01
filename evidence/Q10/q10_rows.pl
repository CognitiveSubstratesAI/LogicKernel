sc_p(1).
sc_p(2).
t_sc01(R) :- catch(('$style_check'(O, O), R = O), error(SsuE, _), R = raised(SsuE)).
t_sc02(R) :- catch(('$style_check'(202, 202), R = yes), error(SsuE, _), R = raised(SsuE)).
t_sc03(R) :- catch(('$style_check'(O, 5), '$style_check'(P, 202), R = O-P), error(SsuE, _), R = raised(SsuE)).
t_sc04(R) :- catch(('$style_check'(_, 0), '$style_check'(P, 202), R = P), error(SsuE, _), R = raised(SsuE)).
t_sc05(R) :- catch(('$style_check'(1, 1), R = yes), error(SsuE, _), R = raised(SsuE)).
t_sc06(R) :- catch(('$style_check'(_, a), '$style_check'(P, P), R = P), error(SsuE, _), R = raised(SsuE)).
t_sc07(R) :- catch(('$style_check'(_, _), R = yes), error(SsuE, _), R = raised(SsuE)).
t_sc08(R) :- catch(('$style_check'(_, 2.0), R = yes), error(SsuE, _), R = raised(SsuE)).
t_sc09(R) :- catch(('$style_check'(a, 202), R = yes), error(SsuE, _), R = raised(SsuE)).
t_sc10(R) :- catch(('$style_check'(_, 2147483648), R = yes), error(SsuE, _), R = raised(SsuE)).
t_sc11(R) :- catch(('$style_check'(O, 2147483647), '$style_check'(P, 202), R = O-P), error(SsuE, _), R = raised(SsuE)).
t_sc12(R) :- catch(('$style_check'(O, -1), '$style_check'(P, 202), R = O-P), error(SsuE, _), R = raised(SsuE)).
t_sc13(R) :- catch(('$style_check'(_, -2147483648), '$style_check'(P, 202), R = P), error(SsuE, _), R = raised(SsuE)).
t_sc14(R) :- catch(('$style_check'(_, 202), '$style_check'(P, P), R = P), error(SsuE, _), R = raised(SsuE)).
t_sc15(R) :- catch((findall(X, '$style_check'(X, 202), R)), error(SsuE, _), R = raised(SsuE)).
t_sc16(R) :- catch(('$style_check'(_, 7), ( '$style_check'(_, b) -> R = yes ; '$style_check'(P, 202), R = no(P) )), error(SsuE, _), R = raised(SsuE)).
t_sc17(R) :- catch(('$style_check'(_, 7), ( '$style_check'(9, 3) -> R = yes ; '$style_check'(P, 202), R = no(P) )), error(SsuE, _), R = raised(SsuE)).
t_sc18(R) :- catch(('$style_check'(_, 7), ( '$style_check'(_, 4.5) -> R = yes ; '$style_check'(P, 202), R = no(P) )), error(SsuE, _), R = raised(SsuE)).
t_sc19(R) :- catch(('$style_check'(O, 2), '$style_check'(P, 202), '$style_check'(Q, Q), R = O-P-Q), error(SsuE, _), R = raised(SsuE)).
t_sc20(R) :- catch(('$style_check'(_, 8), '$style_check'(P, P), '$style_check'(_, 202), R = P), error(SsuE, _), R = raised(SsuE)).
