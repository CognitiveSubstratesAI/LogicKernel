:- dynamic tm_hold/1.
tm_yn(G, R) :- ( call(G) -> R = yes ; R = no ).
t_tmt01(R) :- catch(('$tbl_trienode'(X), ( atom(X) -> R = atom ; R = notatom )), error(SsuE, _), R = raised(SsuE)).
t_tmt02(R) :- catch(('$tbl_trienode'(X), ( atomic(X) -> R = atomic ; R = notatomic )), error(SsuE, _), R = raised(SsuE)).
t_tmt03(R) :- catch(('$tbl_trienode'(X), tm_yn('$tbl_is_trienode'(X), R)), error(SsuE, _), R = raised(SsuE)).
t_tmt04(R) :- catch((tm_yn('$tbl_is_trienode'(a), R)), error(SsuE, _), R = raised(SsuE)).
t_tmt05(R) :- catch((tm_yn('$tbl_is_trienode'(trienode), R)), error(SsuE, _), R = raised(SsuE)).
t_tmt06(R) :- catch((tm_yn('$tbl_is_trienode'(_), R)), error(SsuE, _), R = raised(SsuE)).
t_tmt07(R) :- catch((tm_yn('$tbl_is_trienode'(f(a)), R)), error(SsuE, _), R = raised(SsuE)).
t_tmt08(R) :- catch((tm_yn('$tbl_is_trienode'([]), R)), error(SsuE, _), R = raised(SsuE)).
t_tmt09(R) :- catch((tm_yn('$tbl_is_trienode'(1), R)), error(SsuE, _), R = raised(SsuE)).
t_tmt10(R) :- catch(('$tbl_trienode'(X), '$tbl_trienode'(Y), ( X == Y -> R = same ; R = diff )), error(SsuE, _), R = raised(SsuE)).
t_tmt11(R) :- catch(('$tbl_trienode'(X), ( X == trienode -> R = eqtext ; R = neqtext )), error(SsuE, _), R = raised(SsuE)).
t_tmt12(R) :- catch((tm_yn('$tbl_trienode'(a), R)), error(SsuE, _), R = raised(SsuE)).
t_tmt13(R) :- catch((tm_yn('$tbl_trienode'(trienode), R)), error(SsuE, _), R = raised(SsuE)).
t_tmt14(R) :- catch(('$tbl_trienode'(X), Y = f(X), arg(1, Y, Z), tm_yn('$tbl_is_trienode'(Z), R)), error(SsuE, _), R = raised(SsuE)).
t_tmt15(R) :- catch(('$tbl_trienode'(X), compare(O, X, aaa), R = O), error(SsuE, _), R = raised(SsuE)).
t_tmt16(R) :- catch(('$tbl_trienode'(X), compare(O, X, []), R = O), error(SsuE, _), R = raised(SsuE)).
t_tmt17(R) :- catch(('$tbl_trienode'(X), ( var(X) -> R = var ; R = nonvar )), error(SsuE, _), R = raised(SsuE)).
t_tmt18(R) :- catch(('$tbl_trienode'(X), copy_term(X, Y), tm_yn('$tbl_is_trienode'(Y), R)), error(SsuE, _), R = raised(SsuE)).
t_tmt19(R) :- catch((findall(X, '$tbl_trienode'(X), L), length(L, R)), error(SsuE, _), R = raised(SsuE)).
t_tmt20(R) :- catch((retractall(tm_hold(_)), '$tbl_trienode'(X), assertz(tm_hold(X)), tm_hold(Y), tm_yn('$tbl_is_trienode'(Y), R)), error(SsuE, _), R = raised(SsuE)).
t_tmt21(R) :- catch(('$get_predicate_attribute'(system:'$tbl_trienode'(_), foreign, V), R = V), error(SsuE, _), R = raised(SsuE)).
t_tmt22(R) :- catch(('$get_predicate_attribute'(system:'$tbl_is_trienode'(_), foreign, V), R = V), error(SsuE, _), R = raised(SsuE)).
