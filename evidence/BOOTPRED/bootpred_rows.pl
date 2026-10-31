p(1).
p(2).
p(3).
t_bp01(R) :- catch((thread_self(R)), error(SsuE, _), R = raised(SsuE)).
t_bp02(R) :- catch((thread_self(main), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp03(R) :- catch((thread_self(other), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp04(R) :- catch((findall(X, thread_self(X), R)), error(SsuE, _), R = raised(SsuE)).
t_bp05(R) :- catch((thread_self(1), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp06(R) :- catch((thread_self(T), atom(T), R = T), error(SsuE, _), R = raised(SsuE)).
t_bp07(R) :- catch((thread_self(T), T == main, R = ok), error(SsuE, _), R = raised(SsuE)).
t_bp08(R) :- catch((with_mutex(m, thread_self(R))), error(SsuE, _), R = raised(SsuE)).
t_bp09(R) :- catch((with_mutex(m, R = 1)), error(SsuE, _), R = raised(SsuE)).
t_bp10(R) :- catch((findall(X, with_mutex(m, p(X)), R)), error(SsuE, _), R = raised(SsuE)).
t_bp11(R) :- catch((with_mutex(m, fail), R = x), error(SsuE, _), R = raised(SsuE)).
t_bp12(R) :- catch((catch(with_mutex(m, throw(oops)), E, R = caught(E))), error(SsuE, _), R = raised(SsuE)).
t_bp13(R) :- catch((with_mutex(m, (p(X), X > 1)), R = X), error(SsuE, _), R = raised(SsuE)).
t_bp14(R) :- catch((with_mutex(m, with_mutex(m, R = n))), error(SsuE, _), R = raised(SsuE)).
t_bp15(R) :- catch((with_mutex(m, p(X)), X > 1, R = X), error(SsuE, _), R = raised(SsuE)).
t_bp16(R) :- catch((with_mutex(m, (X = f(Y), Y = 1)), R = X), error(SsuE, _), R = raised(SsuE)).
t_bp17(R) :- catch((with_mutex(m, context_module(R))), error(SsuE, _), R = raised(SsuE)).
t_bp18(R) :- catch((with_mutex(m, nosuchpred_bp(R))), error(SsuE, _), R = raised(SsuE)).
t_bp19(R) :- catch((with_mutex(m, true), with_mutex(n, R = two)), error(SsuE, _), R = raised(SsuE)).
t_bp20(R) :- catch(('$garbage_collect'(0), R = ok), error(SsuE, _), R = raised(SsuE)).
t_bp21(R) :- catch(('$garbage_collect'(foo), R = ok), error(SsuE, _), R = raised(SsuE)).
t_bp22(R) :- catch(('$garbage_collect'(_), R = ok), error(SsuE, _), R = raised(SsuE)).
t_bp23(R) :- catch((findall(x, '$garbage_collect'(0), R)), error(SsuE, _), R = raised(SsuE)).
t_bp24(R) :- catch((X = f(Y, Z), Y = 1, '$garbage_collect'(0), R = X-Z), error(SsuE, _), R = raised(SsuE)).
t_bp25(R) :- catch(('$garbage_collect'(0), '$garbage_collect'(1), R = twice), error(SsuE, _), R = raised(SsuE)).
t_bp26(R) :- catch((length(L, 3), '$garbage_collect'(0), R = L), error(SsuE, _), R = raised(SsuE)).
