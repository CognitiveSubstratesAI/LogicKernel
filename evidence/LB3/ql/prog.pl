:- assertz(d(start)).
r(top).
:- if(true).
r(if_true).
:- if(fail).
r(hidden_in_false_if).
:- else.
r(inner_else).
:- endif.
:- else.
r(hidden_else).
:- endif.
:- if(fail).
r(f_if).
:- assertz(d(hidden_directive)).
:- if(assertz(d(hidden_if_goal))).
r(skipped_nested).
:- else.
r(skipped_nested_else).
:- endif.
:- else.
r(f_else).
:- endif.
:- if(assertz(d(if_goal))).
r(goal_if).
:- endif.
:- user:assertz(d(qualified)).
:- fail.
:- assertz(d(after_fail)).
p(X) :- r(X), X \== top.
r(end).
t_q01(L) :- findall(X, r(X), L).
t_q02(L) :- findall(X, d(X), L).
t_q03(L) :- findall(X, p(X), L).
