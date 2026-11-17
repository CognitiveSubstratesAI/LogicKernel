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
t1(R) :- findall(X, ( member(G, [[3,3,3], [repeat(3)], [2,3], [3], [1,repeat(2)], [3,3], [], [3,2,repeat(1)], [3,repeat(3)], [2,2,repeat(2)], [4,4,4,4,4,4,4,4], [126],
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
    lc_res(( locale_create(L1, lc5, [alias(lc5b)]), ( L1 == lc5b -> K1 = alias ; K1 = other ), locale_property(L1, decimal_point(D1)), locale_property(L1, thousands_sep(T1)),
             locale_property(L1, grouping(G1)), locale_property(L1, alias(A1)) ), R1),
    lc_res(( locale_property(B, alias(lc5)), locale_create(L2, B, [alias(lc5c), thousands_sep(x)]), locale_property(L2, decimal_point(D2)),
             locale_property(L2, thousands_sep(T2)), locale_property(L2, grouping(G2)) ), R2),
    lc_res(locale_create(_, nosuch, []), R3), lc_res(locale_create(_, 'xx_NOPE.nonexist', []), R4), lc_res(locale_create(_, 'xx_NOPE.nonexist', []), R4b),
    lc_res(( locale_create(_, "default", [alias(lc5e)]), locale_property(lc5e, decimal_point(D5)) ), R14), lc_res(locale_create(_, 'xx_NOPE.nonexist', []), R4c), lc_res(locale_create(_, 1, []), R5),
    lc_res(locale_create(_, _, []), R6), lc_res(locale_create(_, f(x), []), R7),    lc_res(locale_create(_, [], []), R9), lc_res(locale_create(_, "C", foo), R10), lc_res(locale_create(_, "C", [a|_]), R11),
    lc_res(locale_create(_, "C", _), R12), lc_res(locale_create(a, "C", []), R13),
    lc_destroy(lc5), lc_destroy(lc5b), lc_destroy(lc5c), lc_destroy(lc5e),
    R = [R1-K1-D1-T1-G1-A1, R2-D2-T2-G2, R3, R4, R4b, R4c, R5, R6, R7, R9, R14-D5, R10, R11, R12, R13].
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
    lc_res(locale_property(lc6, grouping([3,repeat(2)|x])), R18), lc_res(locale_property(lc6, grouping([3,repeat(2),4])), R19),
    lc_res(locale_property(lc6, decimal_point(a, b)), R20),
    lc_res(( locale_property(B3, alias(lc6)), locale_property(B4, alias(lc6)), B3 == B4, ( B3 == lc6 -> fail ; true ) ), R21),
    lc_destroy(lc6),
    R = [Ps, Ds, Ts, Gs, As, R1, R2, R3, R4, Ps2, X5, R5, R6, R7, R8, R9, R10, R11, R12, R13, R14, R15, R16, R17, A3s, R18, R19, R20, R21].
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
    findall(A, ( locale_property(L, grouping([2,repeat(127)])), locale_property(L, alias(A)), sub_atom(A, 0, _, _, lc7) ), L9),
    findall(A, ( locale_property(L, thousands_sep(_)), locale_property(L, alias(A)), sub_atom(A, 0, _, _, lc7) ), L10a), msort(L10a, L10),
    lc_destroy(lc7a), lc_destroy(lc7b),
    R = [L1, L2, L3, L4, L5, L6, L7, L8, L9, L10].
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
t9(R) :- lc_mk(lc9, [decimal_point(',')]), locale_property(B, alias(lc9)),
    lc_res(locale_destroy(nosuch), R1), lc_res(locale_destroy(1), R2), lc_res(locale_destroy(_), R3), lc_res(locale_destroy(f(x)), R4),
    lc_res(locale_destroy(lc9), R5), lc_res(locale_destroy(lc9), R6),
    lc_res(set_locale(lc9), R7), lc_res(locale_create(_, lc9, []), R8),
    lc_res(( locale_property(L, alias(lc9)) ), R9), lc_res(locale_property(lc9, alias(_)), R10),
    findall(P, locale_property(B, P), Pb), lc_res(locale_destroy(B), R11), findall(P, locale_property(B, P), Pb2),
    lc_res(( locale_create(_, B, [alias(lc9c)]), locale_property(lc9c, decimal_point(D2)) ), R12), lc_destroy(lc9c),
    R = [R1, R2, R3, R4, R5, R6, R7, R8, R9, R10, L, Pb, R11, Pb2, R12-D2].
% a locale made from a name: the "C" and "POSIX" locales' numeric conventions (an empty thousands_sep or grouping is no property)
% a name that exists on most hosts: where it does not, the answer is ok (the .out is the same on every host)
lc_en(R) :- ( catch(locale_create(_, 'en_US.UTF-8', [alias(lc10)]), error(existence_error(locale, _), _), fail)
    -> lc_props(lc10, Pu), lc_destroy(lc10),
       ( Pu == [alias(lc10), decimal_point('.'), thousands_sep(','), grouping([repeat(3)])] -> R = ok ; R = bad(Pu) )
    ; R = ok ).
t10(R) :- findall(N-Ps, ( member(N, ["C", "POSIX", 'C', 'POSIX']), locale_create(_, N, [alias(lc10)]), lc_props(lc10, Ps), lc_destroy(lc10) ), R0),
    lc_res(( locale_create(_, "C", [alias(lc10)]), locale_property(lc10, thousands_sep(_)) ), R1), lc_destroy(lc10),
    lc_res(( locale_create(_, "C", [alias(lc10), thousands_sep(',')]), locale_property(lc10, thousands_sep(S)) ), R2), lc_destroy(lc10),
    lc_res(( locale_create(_, "C", [alias(lc10), grouping([2])]), locale_property(lc10, grouping(G)) ), R3), lc_destroy(lc10),
    lc_res(( locale_create(_, "C", [alias(lc10), decimal_point('')]), lc_props(lc10, Pe) ), R4), lc_destroy(lc10),
    lc_res(( locale_create(Lb, "C", []), findall(P, locale_property(Lb, P), Pb) ), R5),
    lc_res(( locale_create(_, 'C', [alias(lc10), grouping([1,2])]), locale_property(lc10, alias(A10)) ), R7), lc_destroy(lc10),
    lc_en(R8),
    R = [R0, R1, R2, R3, S, G, R4-Pe, R5-Pb, R7-A10, R8].
% setlocale/3 refreshes the default locale (updateLocale, pl-ctype.c): LC_NUMERIC and LC_ALL do, the other categories do not. A host without
% en_US.UTF-8 cannot set it: the row then answers `ok` for that category (the .out is the same on every host).
lc_def(Ps) :- findall(P, locale_property(default, P), Ps).
lc_base([alias(default), decimal_point('.')]).
lc_us([alias(default), decimal_point('.'), thousands_sep(','), grouping([repeat(3)])]).
lc_upd(Cat, Want, R) :-
    ( catch(setlocale(Cat, Old, 'en_US.UTF-8'), error(_, _), fail)
    -> lc_def(Ps), setlocale(Cat, _, Old), lc_def(Ps2), lc_base(B),
       ( Ps == Want, Ps2 == B -> R = ok ; R = bad(Ps, Ps2) )
    ;  R = ok ).
t11(R) :- setlocale(numeric, _, 'C'), lc_base(B), lc_us(U), lc_def(P0),
    lc_upd(numeric, U, R1), lc_upd(all, U, R2), lc_upd(ctype, B, R3), lc_upd(time, B, R4), lc_upd(messages, B, R5), lc_upd(collate, B, R6),
    lc_def(P1), R = [P0, R1, R2, R3, R4, R5, R6, P1].
% t10's decimal_point('a\000\b') row (a decimal point holding the character 0), apart from t10: the atom of the character 0 is
% refused by the kernel (DIVERGES, settled: src/pl-read.jl:2061-2064), whether the reader makes it from the program text or
% atom_codes/2 makes it at run time; the atom is built at run time here so that only this row meets the refusal, and it is the last row.
t12(R) :- atom_codes(Dp, [97, 0, 98]),
    lc_res(( locale_create(_, "C", [alias(lc10), decimal_point(Dp)]), locale_property(lc10, decimal_point(Dn)) ), R6), lc_destroy(lc10),
    R = R6-Dn.
% locale_destroy/1 takes the locale out of the table (pl-locale.c deleteHTableWP): the enumeration of locale_property/2 with the locale unbound,
% over a property every locale has, finds the same locales before create, after create (one more) and after destroy (the same again). A blob B
% of the locale outlives the destroy (its reference keeps the locale's properties: a locale nobody refers to is freed and has none to find, so a
% stale table entry would not show); B answers its decimal_point after the destroy. Only the differences and the aliases of this row are
% answered (the other locales alive are the host's and the earlier rows').
t13(R) :- lc_cnt(N0), lc_mk(lc13, [decimal_point('!')]), lc_cnt(N1), locale_property(B, alias(lc13)),
    findall(A, ( locale_property(L, decimal_point('!')), locale_property(L, alias(A)) ), As),
    lc_destroy(lc13), lc_cnt(N2), D1 is N1-N0, D2 is N2-N0,
    findall(D, locale_property(B, decimal_point(D)), Ds), findall(A, locale_property(B, alias(A)), Bs),
    lc_res(locale_property(lc13, _), R1), lc_destroy(B), lc_cnt(N3), D3 is N3-N0,
    R = [D1, D2, As, Ds, Bs, R1, D3].
lc_cnt(N) :- findall(L, locale_property(L, decimal_point(_)), Ls), length(Ls, N).
% the enumeration with the locale unbound hands every locale back as its ALIAS atom when it has one (pl-locale.c unifyLocale(..., TRUE)), not as a blob
t14(R) :- lc_mk(lc14, [decimal_point('!'), thousands_sep('_'), grouping([2])]),
    findall(A-K, ( locale_property(L, decimal_point('!')), locale_property(L, alias(A)), sub_atom(A, 0, _, _, lc14),
                   ( L == A -> K = alias ; K = blob ) ), R1),
    findall(A-K, ( locale_property(L, thousands_sep('_')), locale_property(L, alias(A)), sub_atom(A, 0, _, _, lc14),
                   ( L == A -> K = alias ; K = blob ) ), R2),
    findall(A-K, ( locale_property(L, alias(A)), sub_atom(A, 0, _, _, lc14), ( L == A -> K = alias ; K = blob ) ), R3),
    lc_destroy(lc14),
    R = [R1, R2, R3].
