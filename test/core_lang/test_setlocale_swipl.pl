% ORIGINAL: the rows of test/core_lang/test_setlocale_swipl.jl (its predicate, setlocale/3, is pl-ctype.c's).
% test/core_lang/test_setlocale_swipl.pl - CT1a's rows (setlocale/3 of pl-ctype.c). Each `tN(R)` is one row;
% test_setlocale_swipl.out holds swipl 10.1.19's answers to them, as the test's driver prints them (`ok`, then one line
% per row: its name and every solution). The locale names the machine decides (the environment's LANG, the installed
% locales) never reach an answer: a row reads the names it sets itself ('C', 'C.utf8', 'POSIX') through the environment
% variables it sets, or compares two names of one run. Every row puts the locales back (slc_with/2) and the environment
% variables too (slc_env/3).
slc_mem(X, [X|_]).
slc_mem(X, [_|T]) :- slc_mem(X, T).
slc_cat(C) :- slc_mem(C, [all, collate, ctype, messages, monetary, numeric, time]).
slc_res(G, R) :- catch(( G -> R = true ; R = false ), error(E, C), R = error(E, C)).
slc_rep(0, []) :- !.
slc_rep(N, [97|T]) :- N1 is N-1, slc_rep(N1, T).
slc_with(C, G) :- setup_call_cleanup(setlocale(C, Old, _), once(G), setlocale(C, _, Old)).
slc_env(Name, Val, G) :-
    ( getenv(Name, Old) -> true ; Old = '$slc_unset' ),
    setenv(Name, Val),
    setup_call_cleanup(true, once(G), slc_restore(Name, Old)).
slc_restore(Name, '$slc_unset') :- !, unsetenv(Name).
slc_restore(Name, Old) :- setenv(Name, Old).
% the query form: Old is a non-empty atom for every category; asking twice gives one answer
t0(R) :- slc_cat(C), setlocale(C, O, _), ( atom(O), O \== '' -> R = C-ok ; R = C-bad(O) ).
t1(R) :- slc_cat(C), setlocale(C, O1, N), ( var(N) -> V = unbound ; V = bound ), setlocale(C, O2, _), ( O1 == O2 -> R = C-V-stable ; R = C-V-changed ).
% New equal to Old: nothing is set
t2(R) :- slc_cat(C), slc_with(C, ( setlocale(C, O, O), setlocale(C, O2, _), ( O == O2 -> R = C-same ; R = C-changed ) )).
t3(R) :- slc_cat(C), setlocale(C, O, _), setlocale(C, O, O), R = C-ok.
t4(R) :- slc_with(messages, ( setlocale(messages, _, 'C'), setlocale(messages, 'C', 'C'), setlocale(messages, N, _), R = N )).
% New set: the name libc answers afterwards
t5(R) :- slc_cat(C), slc_with(C, ( setlocale(C, _, 'C'), setlocale(C, N, _), R = C-N )).
t6(R) :- slc_cat(C), slc_with(C, ( setlocale(C, _, 'C.utf8'), setlocale(C, N, _), R = C-N )).
t7(R) :- slc_cat(C), slc_with(C, ( setlocale(C, _, 'POSIX'), setlocale(C, N, _), R = C-N )).
t8(R) :- slc_cat(C), setlocale(C, O, _), setlocale(C, _, 'C.utf8'), setlocale(C, _, O), setlocale(C, O2, _), ( O == O2 -> R = C-restored ; R = C-lost ).
% Old bound: it must equal the locale before New is set
t9(R) :- slc_with(messages, ( setlocale(messages, _, 'C'), setlocale(messages, 'C', 'C.utf8'), setlocale(messages, N, _), R = N )).
t10(R) :- slc_with(messages, ( setlocale(messages, _, 'C'), slc_res(setlocale(messages, zzz, 'C.utf8'), R0), setlocale(messages, N, _), R = R0-N )).
t11(R) :- slc_mem(X, [1, "C", f(x), zzz, []]), slc_res(setlocale(messages, X, _), R0), R = X-R0.
% '' reads the environment (LC_ALL, then LC_<category>, then LANG)
t12(R) :- slc_cat(C), slc_env('LC_ALL', 'C.utf8', slc_with(C, ( setlocale(C, _, ''), setlocale(C, N, _), R = C-N ))).
t13(R) :- slc_cat(C), slc_mem(V, ['C', 'POSIX']), slc_env('LC_ALL', V, slc_with(C, ( setlocale(C, _, ''), setlocale(C, N, _), R = C-V-N ))).
t14(R) :- slc_cat(C), slc_env('LC_ALL', '', slc_env('LC_MESSAGES', 'C.utf8', slc_env('LANG', 'C', slc_with(C, ( setlocale(C, _, ''), setlocale(C, N, _),
    ( C == all -> ( sub_atom(N, _, _, _, 'LC_MESSAGES=C.utf8') -> R = all-has_messages ; R = all-no_messages ) ; R = C-N ) ))))).
t15(R) :- slc_cat(C), slc_env('LC_ALL', nosuch_loc, slc_res(setlocale(C, _, ''), R0)), R = C-R0.
% category errors
t16(R) :- slc_mem(X, [foo, '', 'Messages', 'LC_ALL', 'LC_MESSAGES', 'all ', 'ctype\n']), slc_res(setlocale(X, _, _), R0), R = X-R0.
t17(R) :- slc_res(setlocale(_, _, _), R).
t18(R) :- slc_mem(X, [1, 1.5, "messages", f(x), [], [a]]), slc_res(setlocale(X, _, _), R0), R = X-R0.
t19(R) :- slc_mem(X, [1, 1.5, "C", f(x), [], [a]]), slc_res(setlocale(messages, _, X), R0), R = X-R0.
% the order of the checks: New's text, then the category, then libc
t20(R) :- slc_mem(G, [setlocale(foo, _, 1), setlocale(1, _, 1), setlocale(1, _, nosuch_loc), setlocale(foo, _, nosuch_loc), setlocale(foo, bar, nosuch_loc), setlocale(_, _, nosuch_loc), setlocale(_, _, 1), setlocale(foo, _, _)]), slc_res(G, R0), R = G-R0.
% a locale libc does not have
t21(R) :- slc_mem(N, [nosuch_loc, 'C.utf8x', 'xx_YY', ' ', 'C.']), slc_res(setlocale(messages, _, N), R0), R = N-R0.
t22(R) :- catch(setlocale(messages, O, nosuch_loc), error(E, _), true), ( var(O) -> R = E-unbound ; R = E-bound(O) ).
t23(R) :- slc_with(messages, ( setlocale(messages, _, 'C'), slc_res(setlocale(messages, _, nosuch_loc), R0), setlocale(messages, N, _), R = R0-N )).
t24(R) :- slc_rep(5000, L), atom_codes(A, L), slc_res(setlocale(messages, _, A), R).
% the text of a name is a C string: it ends at its first NUL
t25(R) :- atom_codes(A, [0'C, 0, 0'x]), slc_with(messages, ( setlocale(messages, _, A), setlocale(messages, N, _), R = N )).
t26(R) :- atom_codes(A, [0'a, 0'l, 0'l, 0, 0'x]), setlocale(A, O, _), ( atom(O) -> R = ok ; R = no ).
% the text of a name is ISO Latin-1: a character above 0xFF is refused
t27(R) :- atom_codes(A, [0'c, 0'a, 0'f, 0xe9]), slc_res(setlocale(messages, _, A), R).
t28(R) :- atom_codes(A, [0'c, 0x20ac]), slc_res(setlocale(messages, _, A), R).
t29(R) :- atom_codes(A, [0xe9, 0'x]), slc_res(setlocale(A, _, _), R).
t30(R) :- atom_codes(A, [0x20ac]), slc_res(setlocale(A, _, _), R).
t31(R) :- atom_codes(A, [0'C, 0, 0x20ac]), slc_res(setlocale(messages, _, A), R).
