% ORIGINAL: the rows of test/core_lang/test_tty_swipl.jl (its predicates, tty_size/2, tty_get_capability/3, tty_goto/2 and tty_put/2, are pl-term.c's).
% test/core_lang/test_tty_swipl.pl - TTY1's rows. Each `tN(R)` is one row (a family of cases); test_tty_swipl.out holds
% swipl 10.1.19's answers to them, as the test's driver prints them (`ok`, then one line per row: its name and every
% solution). A pin run is NOT on a terminal: stdin is /dev/null, so the answers are the non-terminal ones.
% Rows t0-t2 are the argument checks of tty_get_capability/3, tty_goto/2 and tty_put/2 (each is answered before the terminal
% library is reached, whatever TERM holds); row t3 is tty_size/2 on a descriptor that is no terminal.
% Rows t4-t7 are the FIRST call into the terminal library of a process (swipl keeps the state of a failed TERM lookup, so each
% runs in a process of its own): t4-t6 with TERM unset, t7 with TERM of 100 bytes (as unset: swipl's buffer is 100 bytes).
% Rows lk0-lk3 are LK-ONLY (the test's own expectations: the calls into libtinfo are refused with owner TTY2); swipl is not run on them.

tt_mem(X, [X|_]).
tt_mem(X, [_|T]) :- tt_mem(X, T).
% the answer of a goal: true, false or the error term with its context
tt_try(G, R) :- catch(( G -> R = true ; R = false ), error(E, C), R = ex(E, C)).
tt_each(Gs, R) :- tt_mem(G, Gs), tt_try(G, X), R = G-X.

% tty_get_capability/3: both names must be atoms (the first error is raised, in the order name, type)
t0(R) :- tt_each([tty_get_capability(1, string, _), tty_get_capability(foo, 1, _), tty_get_capability(_, string, _), tty_get_capability(foo, _, _),
                  tty_get_capability(f(x), string, _), tty_get_capability(foo, f(x), _), tty_get_capability("co", number, _), tty_get_capability(foo, "number", _),
                  tty_get_capability(1.5, number, _), tty_get_capability(foo, 1.5, _), tty_get_capability(1, 2, 3), tty_get_capability(_, _, _),
                  tty_get_capability(100000000000000000000, string, _), tty_get_capability([a], string, _), tty_get_capability(foo, [a], _)], R).
% tty_goto/2: both arguments must be integers that fit an int (the first error is raised, in the order X, Y)
t1(R) :- tt_each([tty_goto(a, 1), tty_goto(1, a), tty_goto(_, 1), tty_goto(1, _), tty_goto(1.5, 2), tty_goto(1, 2.5), tty_goto(f(x), 1), tty_goto(1, f(x)),
                  tty_goto(100000000000000000000, 1), tty_goto(1, 100000000000000000000), tty_goto(-100000000000000000000, 1), tty_goto("1", 2),
                  tty_goto(1, "2"), tty_goto(a, b), tty_goto(_, _), tty_goto(2147483648, 1), tty_goto(1, 2147483648)], R).
% tty_put/2: the first argument is read as text (CVT_ALL), the second as an int
t2(R) :- tt_each([tty_put(f(x), 1), tty_put(_, 1), tty_put(abc, a), tty_put(abc, _), tty_put(f(x), a), tty_put([a|_], 0), tty_put([a, b|c], 0),
                  tty_put(abc, 1.5), tty_put(abc, 100000000000000000000), tty_put(abc, f(x)), tty_put("abc", a), tty_put(123, a), tty_put(1.5, a),
                  tty_put([f(x)], 0), tty_put(f(_), 1), tty_put(_, _), tty_put([0'a|_], a), tty_put(abc, "1"), tty_put(abc, 2147483648)], R).
% tty_size/2 on stdin, a descriptor that is no terminal: the ioctl fails before either argument is looked at
t3(R) :- tt_each([tty_size(_, _), tty_size(a, b), tty_size(1, 2), tty_size(24, 80), tty_size(f(x), _)], R).
% the first call into the terminal library with TERM unset (tty_get_capability: the lookup raises)
t4(R) :- tt_each([tty_get_capability(co, number, _)], R).
t5(R) :- tt_each([tty_goto(1, 2)], R).
% the TERM lookup comes before the type of the capability is looked at
t6(R) :- tt_each([tty_get_capability(co, foo, _)], R).
% TERM of 100 bytes is as unset
t7(R) :- tt_each([tty_get_capability(co, number, _)], R).

% LK-ONLY: the calls into libtinfo are refused (owner TTY2)
lk0(R) :- tty_put(abc, 1), R = done.
lk1(R) :- tty_put("", 0), R = done.
lk2(R) :- tty_goto(1, 2), R = done.
lk3(R) :- tty_get_capability(co, number, X), R = X.
