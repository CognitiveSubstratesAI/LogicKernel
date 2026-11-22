% ORIGINAL: the rows of test/core_lang/test_dict_set_swipl.jl (its predicates, b_set_dict/3, nb_set_dict/3 and nb_link_dict/3, are pl-dict.c's).
% test/core_lang/test_dict_set_swipl.pl - DICT-SET's rows. Each `tN(R)` is one row (a family of cases);
% test_dict_set_swipl.out holds swipl 10.1.20's answers to them, as the test's driver prints them (`ok`, then one line per
% row: its name and every solution). A dict is never printed as a term (the order of its pairs in memory is the
% implementation's): a row reads it through dict_pairs/3, whose pairs are in the standard order of their keys.
% The three predicates are b_set_dict/3 (the assignment is trailed), nb_set_dict/3 (a compound value is duplicated) and
% nb_link_dict/3 (the value is linked): a row that holds for all three walks `ds_m/1`.

ds_m(b_set_dict).
ds_m(nb_set_dict).
ds_m(nb_link_dict).

ds_dsm(D) :- dict_create(D, tg, [a-1, b-2, c-3]).
ds_dp(D, T-P) :- dict_pairs(D, T, P).

% the formal of the error a goal raises (`no_error` when it succeeds); a dict in it is read as its pairs
ds_ex(G, F) :- catch(( G, F = no_error ), error(F0, _), ds_exf(F0, F)).
ds_exf(existence_error(key, K, D), existence_error(key, K, T, P)) :- !, dict_pairs(D, T, P).
ds_exf(F, F).

ds_call(M, K, D, V) :- G =.. [M, K, D, V], call(G).

% every key of the list gets the value 2*key
ds_set_all(_, [], _).
ds_set_all(M, [K|Ks], D) :- V is K * 2, ds_call(M, K, D, V), ds_set_all(M, Ks, D).
ds_pairs0([], []).
ds_pairs0([K|Ks], [K-0|Ps]) :- ds_pairs0(Ks, Ps).

% t0-t3: the assignment, for each predicate and each key
t0(R) :- ds_m(M), member(K, [a, b, c]), ds_dsm(D), ds_call(M, K, D, 9), ds_dp(D, P), R = M-K-P.
t1(R) :- ds_m(M), member(V, ["str", 1.5, 100000000000000000000, 1r3, [x, y], f(_), at, -7, 0]),
    ds_dsm(D), ds_call(M, b, D, V), ds_dp(D, P), R = M-P.
t2(R) :- ds_m(M), dict_create(D, tg, [1-a, 2-b, 30-c]), member(K, [1, 2, 30]), ds_call(M, K, D, z), ds_dp(D, P), R = M-K-P.
t3(R) :- ds_m(M), dict_create(D, T, [a-1]), ds_call(M, a, D, 2), ds_dp(D, P), R = M-P-T.

% t4-t9: backtracking
t4(R) :- ds_dsm(D), ( b_set_dict(a, D, 10), fail ; true ), ds_dp(D, R).
t5(R) :- ds_dsm(D), ( nb_set_dict(a, D, 10), fail ; true ), ds_dp(D, R).
t6(R) :- ds_dsm(D), ( nb_link_dict(a, D, 10), fail ; true ), ds_dp(D, R).
t7(R) :- ds_dsm(D), ( b_set_dict(a, D, 10), nb_set_dict(b, D, 20), fail ; true ), ds_dp(D, R).
t8(R) :- ds_dsm(D), b_set_dict(a, D, 1), b_set_dict(a, D, 2), ( b_set_dict(a, D, 3), fail ; true ), get_dict(a, D, R).
t9(R) :- ds_m(M), ds_dsm(D),
    findall(V0, ( member(V, [1, 2, 3]), ds_call(M, a, D, V), get_dict(a, D, V0) ), L),
    get_dict(a, D, A), R = M-L-A.

% t10-t12: an unbound argument cell
t10(R) :- dict_create(D, tg, [a-_, b-2]), b_set_dict(a, D, 5), ds_dp(D, R).
t11(R) :- dict_create(D, tg, [a-_, b-2]), ( b_set_dict(a, D, 5), fail ; true ), ds_dp(D, R).
t12(R) :- ds_m(M), dict_create(D, tg, [a-_, b-2]), ds_call(M, a, D, f(X)), X = 1, ds_dp(D, P), R = M-P.

% t13-t18: sharing
t13(R) :- ds_m(M), X = f(Y), ds_dsm(D), ds_call(M, a, D, X), Y = 1, ds_dp(D, P), R = M-P-X.
t14(R) :- ds_m(M), ds_dsm(D), ds_call(M, a, D, V), V = 7, ds_dp(D, P), R = M-P-V.
t15(R) :- ds_m(M), X = h(Y), dict_create(D, tg, [a-X, b-q]), ds_call(M, a, D, k(X, Y)), Y = 1, ds_dp(D, P), R = M-P.
t16(R) :- ds_m(M), S = s(Z), dict_create(D, tg, [a-S, b-S]), ds_call(M, a, D, 1), Z = 2, ds_dp(D, P), R = M-P-S.
t17(R) :- ds_m(M), dict_create(D, tg, [a-0, b-V]), ds_call(M, a, D, g(V)), V = 5, ds_dp(D, P), R = M-P.
t18(R) :- ds_m(M), dict_create(In, i, [z-1]), ds_dsm(D), ds_call(M, a, D, In), b_set_dict(z, In, 2),
    get_dict(a, D, In2), ds_dp(In2, Q), R = M-Q.

% t19-t22: the assignment and the exceptions, \+ and a catch
t19(R) :- ds_m(M), ds_dsm(D), catch(( ds_call(M, a, D, 5), throw(x) ), x, true), get_dict(a, D, V), R = M-V.
t20(R) :- ds_m(M), ds_dsm(D), \+ \+ ds_call(M, a, D, 7), get_dict(a, D, V), R = M-V.
t21(R) :- ds_m(M), ds_dsm(D), \+ ( ds_call(M, a, D, 7), fail ), get_dict(a, D, V), R = M-V.
t22(R) :- ds_m(M), ds_dsm(D), K0 = K1, K1 = c, D0 = D, ds_call(M, K0, D0, done), ds_dp(D, R0), R = M-R0.

% t23-t28: the errors
t23(R) :- ds_m(M), member(K, [z, 0, 4, zz]), ds_dsm(D), G =.. [M, K, D, 1], ds_ex(G, F), R = M-K-F.
t24(R) :- ds_m(M), dict_create(D, tg, []), G =.. [M, a, D, 1], ds_ex(G, F), R = M-F.
t25(R) :- ds_m(M), member(D, [foo, 1, "s", f(x), _, [a], 1.5]), G =.. [M, a, D, 1], ds_ex(G, F), R = M-F.
t26(R) :- ds_m(M), member(K, [_, 1.5, "s", f(x), [a], g(_)]), ds_dsm(D), G =.. [M, K, D, 1], ds_ex(G, F), R = M-F.
t27(R) :- ds_m(M), member(K, [_, 1.5, z]), member(D, [foo, _]), G =.. [M, K, D, 1], ds_ex(G, F), R = M-F.
t28(R) :- ds_m(M), ds_dsm(D), G =.. [M, a, D, _], ds_ex(G, F), ds_dp(D, P), R = M-F-P.

% t29-t31: many keys (the binary search), each predicate; t30 assigns in the reverse order of the keys
t29(R) :- ds_m(M), numlist(1, 40, Ks), ds_pairs0(Ks, Ps), dict_create(D, tg, Ps), ds_set_all(M, Ks, D), ds_dp(D, R0), R = M-R0.
t30(R) :- ds_m(M), numlist(1, 17, Ks),
    ds_pairs0(Ks, Ps), dict_create(D, tg, Ps), reverse(Ks, Rs), ds_set_all(M, Rs, D), ds_dp(D, R0), R = M-R0.
t31(R) :- ds_m(M), dict_create(D, tg, [aa-0, ab-0, ba-0, 1-0, 2-0, zz-0, zy-0]),
    member(K, [aa, ab, ba, 1, 2, zz, zy]), ds_call(M, K, D, hit), ds_dp(D, P), R = M-K-P.
