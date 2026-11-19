% ORIGINAL: the rows of test/core_text/test_ctype_text_swipl.jl (their predicates, downcase_atom/2, upcase_atom/2, string_lower/2,
% string_upper/2 and normalize_space/2, are pl-ctype.c's).
% test/core_text/test_ctype_text_swipl.pl - CT1c's rows. Each `tN(R)` is one row; test_ctype_text_swipl.out holds swipl 10.1.20's
% answers to them, as the test's driver prints them (`ok`, then one line per row: its name and every solution). The texts
% are written as code lists, so the file is the same in every encoding; the answers are code lists too.
ctt_texts([[0'A, 0'b, 0'C], [], [0xc9, 0'e], [0x1c5], [0x3a3, 0x391, 0x3a3], [0xdf], [0x130], [0xb5], [0xff],
           [0x10400, 0x10428], [0' , 0'1], [0x3c2, 0x3c3]]).
ctt_res(G, R) :- catch(( G -> R = true ; R = false ), error(E, _), R = error(E)).
% the case maps over atoms: each text, its answer
t0(R) :- ctt_texts(Ts), member(Cs, Ts), atom_codes(A, Cs), downcase_atom(A, L), atom_codes(L, Ls), R = Cs-Ls.
t1(R) :- ctt_texts(Ts), member(Cs, Ts), atom_codes(A, Cs), upcase_atom(A, L), atom_codes(L, Ls), R = Cs-Ls.
% over strings: the answer is a string
t2(R) :- ctt_texts(Ts), member(Cs, Ts), string_codes(S, Cs), string_lower(S, L), string_codes(L, Ls),
    ( string(L) -> K = string ; K = other ), R = Cs-Ls-K.
t3(R) :- ctt_texts(Ts), member(Cs, Ts), string_codes(S, Cs), string_upper(S, L), string_codes(L, Ls),
    ( string(L) -> K = string ; K = other ), R = Cs-Ls-K.
% the input type: any atomic term; the answer's type follows the predicate
t4(R) :- member(In, [123, 1.5, "aBc", 'aBc', 0'a, abc]), downcase_atom(In, X), ( atom(X) -> K = atom ; K = other ), R = In-X-K.
t5(R) :- member(In, [123, 1.5, "aBc", 'aBc', abc]), upcase_atom(In, X), ( atom(X) -> K = atom ; K = other ), R = In-X-K.
t6(R) :- member(In, [123, "aBc", 'aBc', abc]), string_lower(In, X), ( string(X) -> K = string ; K = other ), R = In-X-K.
t7(R) :- member(In, [123, "aBc", 'aBc', abc]), string_upper(In, X), ( string(X) -> K = string ; K = other ), R = In-X-K.
% the output bound: compared character by character
t8(R) :- member(G, [downcase_atom('ABC', abc), downcase_atom('ABC', 'ABC'), downcase_atom('ABC', "abc"), downcase_atom('AB', abc),
                     downcase_atom('ABC', ab), downcase_atom('', ''), downcase_atom('A', 97), upcase_atom(abc, 'ABC'),
                     upcase_atom(abc, "ABC"), upcase_atom(abc, abc), upcase_atom(ab, 'ABC'), upcase_atom(abc, 'AB'),
                     upcase_atom(a1, 'A1'), upcase_atom(1, 1), upcase_atom(1, '1'), upcase_atom(1.5, '1.5'),
                     string_lower("ABC", abc), string_lower("ABC", "abc"), string_lower("ABC", "ABC"), string_upper(abc, "ABC"),
                     string_upper("abc", 'ABC'), string_upper("abc", 1)]),
    ctt_res(G, V), R = G-V.
% errors
t9(R) :- ctt_res(downcase_atom(_, _), R).
t10(R) :- ctt_res(downcase_atom(f(x), _), R).
t11(R) :- ctt_res(downcase_atom(abc, f(x)), R).
t12(R) :- ctt_res(upcase_atom(abc, f(x)), R).
t13(R) :- ctt_res(string_lower("A", f(x)), R).
t14(R) :- ctt_res(string_upper("A", f(x)), R).
t15(R) :- ctt_res(upcase_atom([a], _), R).
t16(R) :- ctt_res(upcase_atom(abc, [a]), R).
t17(R) :- ctt_res(upcase_atom(abc, [0'A, 0'B, 0'C]), R).
t18(R) :- ctt_res(string_lower(_, _), R).
% normalize_space: the output forms, one input
t19(R) :- member(In, ['  a  b   c  ', a, '', '   ', ' lead', 'trail ', 'a b', "x  y", 123]),
    normalize_space(atom(A), In), atom_codes(A, Cs), R = In-Cs.
t20(R) :- member(In, ['  a  b   c  ', a, '', '   ']), normalize_space(string(S), In), string_codes(S, Cs),
    ( string(S) -> K = string ; K = other ), R = In-Cs-K.
t21(R) :- member(In, ['  a  b   c  ', a, '', '   ']), normalize_space(codes(Cs), In), R = In-Cs.
t22(R) :- member(In, ['  a  b   c  ', a, '', '   ']), normalize_space(chars(Cs), In), R = In-Cs.
t23(R) :- member(In, ['  a  b   c  ', '']), normalize_space(codes(Cs, T), In), T = [], R = In-Cs.
% the white space of the Unicode map and the control characters of the ASCII table
t24(R) :- member(Cs, [[0'a, 0xa0, 0'b], [0'a, 0x2003, 0x20, 0'b], [0x3000, 0'a, 0x3000], [0'a, 9, 10, 11, 12, 13, 0'b],
                      [0'a, 0x85, 0'b], [0'a, 0x2028, 0'b], [0'a, 0x200b, 0'b], [0'a, 0x1680, 0'b], [0xe9, 0x20, 0xe9]]),
    atom_codes(In, Cs), normalize_space(codes(Out), In), R = Cs-Out.
% errors and bound outputs
t25(R) :- ctt_res(normalize_space(atom(_), _), R).
t26(R) :- ctt_res(normalize_space(atom(_), f(x)), R).
t27(R) :- ctt_res(normalize_space(foo, a), R).
t28(R) :- ctt_res(normalize_space(atom(abc), ' abc '), R).
t29(R) :- ctt_res(normalize_space(atom(abd), ' abc '), R).
t30(R) :- ctt_res(normalize_space(_, a), R).
t31(R) :- ctt_res(normalize_space(string("a b"), '  a    b'), R).
t32(R) :- ctt_res(normalize_space(codes([0'a, 0' , 0'b]), '  a    b'), R).
t33(R) :- ctt_res(normalize_space(atom(A), [0'a]), R), ( var(A) -> true ; true ).
