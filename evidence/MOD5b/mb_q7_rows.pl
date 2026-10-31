mq:qs(1).
mq:qs(2).
t_q7a(R) :- '$declare_module'(mq, user, user, '/mb/q.pl', 1, false), '$set_source_module'(user), R = ok.
t_q7b(R) :- catch(findall(X, mq:qs(X), R), error(F, _), R = raised(F)).
