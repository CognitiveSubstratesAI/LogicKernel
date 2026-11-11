% ORIGINAL: the rows of test/core_text/test_char_type_swipl.jl (their predicates, char_type/2 and code_type/2, are pl-ctype.c's).
% test/core_text/test_char_type_swipl.pl - CT1b's rows (char_type/2, code_type/2 of pl-ctype.c). Each `tN(R)` is one row;
% test_char_type_swipl.out holds swipl 10.1.20's answers to them, as the test's driver prints them (`ok`, then one line per
% row: its name and every solution). The characters are named by code, so the rows do not depend on the source encoding.
% No row reads the locale (the classes are the Unicode map's, as the pin's swipl answers them).
ct_codes([0'a, 0'Z, 0'5, 0' , 0'_, 0'., 0'(, 0'", 0'\n, 0xe9, 0x3b1, 0x660, 0x20ac, 0x2028, 0, 0x7f]).
ct_cls0([alnum, alpha, csym, csymf, prolog_var_start, prolog_atom_start, prolog_identifier_continue, decimal,
         prolog_symbol, prolog_solo, pattern_syntax, ascii, white, cntrl, digit, print, graph, lower, upper, punct,
         space, end_of_line, prolog_end_of_line, prolog_layout, newline, period, quote]).
ct_cls1([lower, upper, to_lower, to_upper, paren, quote, digit, xdigit, decimal, width]).
ct_res(G, R) :- catch(( G -> R = true ; R = false ), error(E, _), R = error(E)).
% the arity-0 classes each character belongs to, by code_type/2 and by char_type/2
t0(R) :- ct_codes(Cs), ct_cls0(Ts), member(C, Cs), findall(T, ( member(T, Ts), code_type(C, T) ), L), R = C-L.
t1(R) :- ct_codes(Cs), ct_cls0(Ts), member(C, Cs), char_code(Ch, C), findall(T, ( member(T, Ts), char_type(Ch, T) ), L), R = C-L.
% the arity-1 classes: the value each gives (code_type/2: codes, char_type/2: characters)
t2(R) :- ct_codes(Cs), ct_cls1(Ns), member(C, Cs),
    findall(T, ( member(N, Ns), T =.. [N, _], code_type(C, T) ), L), R = C-L.
t3(R) :- ct_codes(Cs), ct_cls1(Ns), member(C, Cs), char_code(Ch, C),
    findall(T, ( member(N, Ns), T =.. [N, _], char_type(Ch, T) ), L0), maplist(ct_codes_of, L0, L), R = C-L.
ct_codes_of(T, N-V) :- T =.. [N, X], ( atom(X) -> char_code(X, V) ; V = X ).
% the reverse mappings: the characters that have a given value
t4(R) :- member(Q, [to_lower, to_upper, upper, lower]), member(V, [0'a, 0'A, 0'5, 0x3b1, 0x391]),
    T =.. [Q, V], findall(X, code_type(X, T), L), R = Q-V-L.
t5(R) :- member(T, [digit(5), digit(0), digit(10), xdigit(10), xdigit(15), xdigit(0), xdigit(16)]),
    findall(X, code_type(X, T), L), R = T-L.
t6(R) :- member(Cl, [0'), 0'], 0'}, 0'>, 0'a, 0'(]), findall(X, code_type(X, paren(Cl)), L), R = Cl-L.
t7(R) :- member(Cl, [0'", 0'', 0'`, 0'a, 0xab, 0xbb, 0x201c, 0x201d]), findall(X, code_type(X, quote(Cl)), L), R = Cl-L.
% a full enumeration (decimal(W) has no reverse mapping): how many, and the first
t8(R) :- member(W, [0, 5, 10]), findall(X, code_type(X, decimal(W)), L),
    length(L, N), ( L = [F|_] -> R = W-N-F ; R = W-N-none ).
% enumerating the classes of a character, and of end_of_file
t9(R) :- member(C, [0'a, 0'5, 0'(, 0x20ac, 0x660]), findall(T, code_type(C, T), L), R = C-L.
t10(R) :- member(C, [a, 'Z', '_', ' ']), findall(T, char_type(C, T), L), R = C-L.
t11(R) :- findall(T, code_type(-1, T), L), R = L.
t12(R) :- findall(T, char_type(end_of_file, T), L), R = L.
t13(R) :- ct_res(code_type(-1, end_of_file), R).
% the first answer of a full enumeration over the characters
t14(R) :- member(T, [digit, upper, lower, space, punct, csymf, cntrl]), once(code_type(X, T)), R = T-X.
% the end of an enumeration of the characters through a class with a test and no reverse
t15(R) :- findall(X, ( between(0, 255, X), code_type(X, width(1)) ), L), length(L, N), R = N.
t16(R) :- findall(X-W, ( member(X, [0, 0x300, 0x1100, 0x4e00, 0x20ac, 0xff21]), code_type(X, width(W)) ), R0), R = R0.
% errors
t17(R) :- ct_res(char_type(_, _), R).
t18(R) :- ct_res(char_type(a, foo), R).
t19(R) :- ct_res(char_type(a, foo(1)), R).
t20(R) :- ct_res(char_type(ab, alpha), R).
t21(R) :- ct_res(char_type(1.5, alpha), R).
t22(R) :- ct_res(code_type(a, alpha), R).
t23(R) :- ct_res(code_type(0x110000, alpha), R).
t24(R) :- ct_res(code_type(-2, alpha), R).
t25(R) :- ct_res(char_type(a, alpha(_)), R).
t26(R) :- ct_res(char_type(a, upper(1)), R).
t27(R) :- ct_res(code_type(0'a, upper(_)), R).
t28(R) :- ct_res(code_type(0'a, 1), R).
t29(R) :- ct_res(char_type("a", alpha), R).
t30(R) :- ct_res(code_type(0'a, to_lower(foo)), R).
t31(R) :- ct_res(code_type(0'A, to_lower(0'a)), R).
t32(R) :- ct_res(char_type('A', to_lower(a)), R).
t33(R) :- ct_res(char_type(_, to_lower(a)), R).
% a mapping unified with a bound argument, and one that cannot be
t34(R) :- ct_res(char_type(a, upper('A')), R).
t35(R) :- ct_res(char_type('A', upper(a)), R).
t36(R) :- ct_res(char_type(a, lower('A')), R).
t37(R) :- ct_res(char_type('A', lower(a)), R).
t38(R) :- ct_res(code_type(0'5, digit(5)), R).
t39(R) :- ct_res(code_type(0'5, digit(6)), R).
t40(R) :- ct_res(code_type(0'f, xdigit(15)), R).
t41(R) :- code_type(0'f, xdigit(W)), R = W.
