% ORIGINAL: the rows of test/core_text/test_locale_swipl.jl (their predicates, locale_create/3, locale_property/2, locale_destroy/1, set_locale/1 and
% current_locale/1, are pl-locale.c's).
% test/core_text/test_locale_swipl.pl - CT1 LOCALE rows. Each `tN(R)` is one row with ONE solution (a list: every action of the row,
% in order); test_locale_swipl.out holds swipl 10.1.20's answers, as the test's driver prints them (`ok`, then one line per row).
% Every locale a row makes is made from the name "C" with decimal_point, thousands_sep and grouping given EXPLICITLY, and is read
% back through locale_property/2 only: the machine's locale (LANG, LC_*) is never read. Each row destroys its aliases at its end.
lc_res(G, R) :- catch(( G -> R = true ; R = false ), error(E, _), R = error(E)).
lc_mk(A, Props) :- locale_create(_, "C", [alias(A)|Props]).
lc_props(A, Ps) :- findall(P, locale_property(A, P), Ps).
lc_destroy(A) :- catch(locale_destroy(A), error(_, _), true).
% the properties of a locale made with all four given
t0(R) :- lc_mk(lc0, [decimal_point(','), thousands_sep('.'), grouping([3,repeat(2)])]),
    lc_props(lc0, Ps), lc_destroy(lc0), R = Ps.
% the grouping forms, read back
lc_grp(G, G-R) :- lc_res(lc_mk(lc1, [decimal_point('.'), thousands_sep(','), grouping(G)]), R0),
    ( R0 == true -> findall(P, locale_property(lc1, grouping(P)), R), lc_destroy(lc1) ; R = R0 ).
t1(R) :- findall(X, ( member(G, [[3,3,3], [repeat(3)], [2,3], [3], [1,repeat(2)], [3,3], [], [3,2,repeat(1)], [4,4,4,4,4,4,4,4], [126],
                                  [1,2,3,4,5,6,7,8], [1,2,3,4,5,6,7,8,9]]), lc_grp(G, X) ), R).
% group sizes and grouping shapes that are errors
t2(R) :- findall(G-E, ( member(G, [[0], [127], [128], [-1], [a], [1.5], x, [3|_], [3|x], [repeat(0)], [repeat(a)], [repeat(3),4], [repeat(_)], [_]]),
                         lc_res(lc_mk(lc2, [grouping(G)]), E0), ( E0 == true -> lc_destroy(lc2), E = true ; E = E0 ) ), R).
% decimal_point and thousands_sep: forms and errors
t3(R) :- findall(P-E, ( member(P, [decimal_point(x), decimal_point(''), decimal_point(abc), decimal_point("s"), decimal_point(1), decimal_point(_),
                                    decimal_point(f(x)), thousands_sep(x), thousands_sep(''), thousands_sep(' '), thousands_sep(1), thousands_sep([a]),
                                    alias(1), alias(_), alias("s"), alias(f(x)), foo(x), bar, 1, _, decimal_point, 'a b'(c)]),
                         lc_res(locale_create(_, "C", [P]), E) ), R).
% the alias: taken, destroyed and made again
t4(R) :- lc_mk(lc4, [decimal_point(',')]),
    lc_res(lc_mk(lc4, []), R1), lc_res(locale_destroy(lc4), R2), lc_res(lc_mk(lc4, [thousands_sep(x)]), R3),
    lc_props(lc4, Ps), lc_res(locale_destroy(lc4), R4), lc_res(locale_destroy(lc4), R5), lc_res(locale_property(lc4, _), R6),
    R = [R1, R2, R3, Ps, R4, R5, R6].
% the second argument: a name, an alias (a copy), a locale blob (a copy), the errors
t5(R) :- lc_mk(lc5, [decimal_point(','), thousands_sep('.'), grouping([3,repeat(2)])]),
    lc_res(( locale_create(L1, lc5, [alias(lc5b)]), locale_property(L1, decimal_point(D1)), locale_property(L1, thousands_sep(T1)),
             locale_property(L1, grouping(G1)), locale_property(L1, alias(A1)) ), R1),
    lc_res(( locale_property(B, alias(lc5)), locale_create(L2, B, [alias(lc5c), thousands_sep(x)]), locale_property(L2, decimal_point(D2)),
             locale_property(L2, thousands_sep(T2)), locale_property(L2, grouping(G2)) ), R2),
    lc_res(locale_create(_, nosuch, []), R3), lc_res(locale_create(_, 'xx_NOPE.nonexist', []), R4), lc_res(locale_create(_, 1, []), R5),
    lc_res(locale_create(_, _, []), R6), lc_res(locale_create(_, f(x), []), R7),    lc_res(locale_create(_, [], []), R9), lc_res(locale_create(_, "C", foo), R10), lc_res(locale_create(_, "C", [a|_]), R11),
    lc_res(locale_create(_, "C", _), R12), lc_res(locale_create(a, "C", []), R13),
    lc_destroy(lc5), lc_destroy(lc5b), lc_destroy(lc5c),
    R = [R1-D1-T1-G1-A1, R2-D2-T2-G2, R3, R4, R5, R6, R7, R9, R10, R11, R12, R13].
% locale_property/2 on a bound locale (the alias, a blob), by property, and the errors
t6(R) :- lc_mk(lc6, [decimal_point(','), thousands_sep('.'), grouping([3,repeat(2)])]),
    findall(P, locale_property(lc6, P), Ps),
    findall(D, locale_property(lc6, decimal_point(D)), Ds),
    findall(T, locale_property(lc6, thousands_sep(T)), Ts),
    findall(G, locale_property(lc6, grouping(G)), Gs),
    findall(A, locale_property(lc6, alias(A)), As),
    lc_res(locale_property(lc6, decimal_point('.')), R1),
    lc_res(locale_property(lc6, decimal_point(',')), R2),
    lc_res(locale_property(lc6, grouping([3,repeat(2)])), R3),
    lc_res(locale_property(lc6, grouping([3,repeat(3)])), R4),
    ( locale_property(B, alias(lc6)) -> findall(P2, locale_property(B, P2), Ps2) ; Ps2 = none ),
    lc_res(( locale_property(B2, alias(lc6)), locale_property(B2, thousands_sep(X)) ), R5), ( R5 == true -> X5 = X ; X5 = none ),
    lc_res(locale_property(lc6, foo(x)), R6), lc_res(locale_property(lc6, foo), R7), lc_res(locale_property(lc6, 1), R8),
    lc_res(locale_property(nosuch, _), R9), lc_res(locale_property(1, _), R10), lc_res(locale_property(f(x), _), R11),
    lc_res(locale_property(lc6, decimal_point), R12), lc_res(locale_property(_, foo(x)), R13), lc_res(locale_property(_, 1), R14),
    lc_res(locale_property(_, alias(nosuch)), R15), lc_res(locale_property(_, alias(1)), R16), lc_res(locale_property(lc6, alias(nosuch)), R17),
    findall(A3, ( locale_property(L3, alias(lc6)), locale_property(L3, alias(A3)) ), A3s),
    lc_destroy(lc6),
    R = [Ps, Ds, Ts, Gs, As, R1, R2, R3, R4, Ps2, X5, R5, R6, R7, R8, R9, R10, R11, R12, R13, R14, R15, R16, R17, A3s].
% locale_property/2 with the locale unbound and a given property: the alias of a locale found by it, a locale found
% by its decimal_point among the ones this row makes (a filter on the aliases of the row, never the other locales)
t7(R) :- lc_mk(lc7a, [decimal_point(':'), thousands_sep('_'), grouping([2])]),
    lc_mk(lc7b, [decimal_point(';'), thousands_sep('_'), grouping([1,repeat(4)])]),
    findall(A-D, ( member(A, [lc7a, lc7b]), locale_property(A, decimal_point(D)) ), L1),
    findall(A, ( locale_property(L, decimal_point(':')), locale_property(L, alias(A)), sub_atom(A, 0, _, _, lc7) ), L2),
    findall(A-x, ( locale_property(L, grouping([1,repeat(4)])), locale_property(L, alias(A)), sub_atom(A, 0, _, _, lc7) ), L3),
    findall(A-u, ( locale_property(L, thousands_sep('_')), locale_property(L, alias(A)), sub_atom(A, 0, _, _, lc7) ), L4a), msort(L4a, L4),
    findall(A-P, ( member(A, [lc7a, lc7b]), locale_property(A, P) ), L5),
    findall(A, ( locale_property(L, alias(A)), sub_atom(A, 0, _, _, lc7) ), L6a), msort(L6a, L6),
    findall(A-P, ( locale_property(L, P), locale_property(L, alias(A)), sub_atom(A, 0, _, _, lc7) ), L7a), msort(L7a, L7),
    findall(A-D, ( locale_property(L, decimal_point(D)), locale_property(L, alias(A)), sub_atom(A, 0, _, _, lc7) ), L8a), msort(L8a, L8),
    lc_destroy(lc7a), lc_destroy(lc7b),
    R = [L1, L2, L3, L4, L5, L6, L7, L8].
% set_locale/1 and current_locale/1
t8(R) :- lc_mk(lc8, [decimal_point(','), thousands_sep('.'), grouping([3])]),
    current_locale(C0), locale_property(C0, alias(A0)),
    lc_res(set_locale(lc8), R1), current_locale(C1), ( C1 == lc8 -> E1 = alias ; E1 = other ),
    findall(P, locale_property(C1, P), Ps1),
    lc_res(( current_locale(C2), C2 == C1 ), R2), lc_res(current_locale(lc8), R3), lc_res(current_locale(nosuch), R4),
    lc_res(set_locale(lc8), R5),
    lc_res(set_locale(nosuch), R6), lc_res(set_locale(1), R7), lc_res(set_locale(_), R8), lc_res(set_locale(f(x)), R9), lc_res(set_locale("lc8"), R10),
    lc_res(( locale_property(B, alias(lc8)), set_locale(B) ), R11),
    lc_res(set_locale(current_locale), R12), current_locale(C3), ( C3 == lc8 -> E3 = alias ; E3 = other ),
    lc_res(( locale_create(Lc, current_locale, [alias(lc8b)]), locale_property(Lc, thousands_sep(Ts8)) ), R13),
    lc_res(set_locale(A0), R14), current_locale(C4), locale_property(C4, alias(A4)),
    ( A4 == A0 -> E4 = restored ; E4 = A4 ),
    lc_destroy(lc8), lc_destroy(lc8b),
    R = [A0, R1, E1, Ps1, R2, R3, R4, R5, R6, R7, R8, R9, R10, R11, R12, E3, R13, Ts8, R14, E4].
% locale_destroy/1: the errors, and what a destroyed alias is
t9(R) :- lc_mk(lc9, [decimal_point(',')]),
    lc_res(locale_destroy(nosuch), R1), lc_res(locale_destroy(1), R2), lc_res(locale_destroy(_), R3), lc_res(locale_destroy(f(x)), R4),
    lc_res(locale_destroy(lc9), R5), lc_res(locale_destroy(lc9), R6),
    lc_res(set_locale(lc9), R7), lc_res(locale_create(_, lc9, []), R8),
    lc_res(( locale_property(L, alias(lc9)) ), R9), lc_res(locale_property(lc9, alias(_)), R10),
    R = [R1, R2, R3, R4, R5, R6, R7, R8, R9, R10, L].
