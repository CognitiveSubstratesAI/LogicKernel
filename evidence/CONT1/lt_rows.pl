cl_sh :- statistics(localused, U), shift(ltop(U)).
cl_sc :- statistics(localused, U), shift_for_copy(ltop(U)).
cl_cmp(U0, U1, R) :- D is U1-U0, ( D =:= 0 -> R = same ; D > 0 -> R = above ; R = below ).
cl_kind(C, K) :- ( C == 0 -> K = plain ; K = shifted ).
t_lt_shift(R) :- reset(cl_sh, _, _), reset(cl_sh, ltop(U0), _), statistics(localused, U1), cl_cmp(U0, U1, R).
t_lt_copy(R) :- reset(cl_sc, _, _), reset(cl_sc, ltop(U0), _), statistics(localused, U1), cl_cmp(U0, U1, R).
t_lt_none(R) :- statistics(localused, U0), reset(true, _, _), statistics(localused, U1), cl_cmp(U0, U1, R).
t_lt_call(R) :- reset(cl_sh, _, _), statistics(localused, U0), reset(cl_sh, _, _), statistics(localused, U1), cl_cmp(U0, U1, R).
t_lt_cont(R) :- reset(cl_sh, _, _), reset(cl_sh, ltop(U0), C), statistics(localused, U1), cl_cmp(U0, U1, R0), cl_kind(C, K), R = R0-K.
