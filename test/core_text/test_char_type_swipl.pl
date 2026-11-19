% ORIGINAL: the rows of test/core_text/test_char_type_swipl.jl (their predicates, char_type/2 and code_type/2, are pl-ctype.c's).
% test/core_text/test_char_type_swipl.pl - CT1b's rows (char_type/2, code_type/2 of pl-ctype.c). Each `tN(R)` is one row;
% test_char_type_swipl.out holds swipl 10.1.20's answers to them, as the test's driver prints them (`ok`, then one line per
% row: its name and every solution). The characters are named by code, so the rows do not depend on the source encoding.
% No row reads the locale (the classes are the Unicode map's, as the pin's swipl answers them).
ct_codes([0'a, 0'Z, 0'5, 0' , 0'_, 0'., 0'(, 0'", 0'\n, 0xe9, 0x3b1, 0x660, 0x20ac, 0x2028, 0, 0x7f, 0'`]).
% the same characters without code 0: char_code/2 on 0 makes the atom of the character 0, which the kernel refuses
% (DIVERGES, settled: src/pl-read.jl `_atom_from_text`); the code-0 rows of t1 and t3 are t42 and t43; the rows after them (t44 on) run again on a fresh engine
ct_codes_nz(Cs) :- ct_codes(All), ct_nz(All, Cs).
ct_nz([], []).
ct_nz([C|T], R) :- ( C =:= 0 -> R = R1 ; R = [C|R1] ), ct_nz(T, R1).
ct_cls0([alnum, alpha, csym, csymf, prolog_var_start, prolog_atom_start, prolog_identifier_continue, decimal,
         prolog_symbol, prolog_solo, pattern_syntax, ascii, white, cntrl, digit, print, graph, lower, upper, punct,
         space, end_of_line, prolog_end_of_line, prolog_layout, newline, period, quote]).
ct_cls1([lower, upper, to_lower, to_upper, paren, quote, digit, xdigit, decimal, width]).
ct_res(G, R) :- catch(( G -> R = true ; R = false ), error(E, _), R = error(E)).
% the arity-0 classes each character belongs to, by code_type/2 and by char_type/2
t0(R) :- ct_codes(Cs), ct_cls0(Ts), member(C, Cs), findall(T, ( member(T, Ts), code_type(C, T) ), L), R = C-L.
t1(R) :- ct_codes_nz(Cs), ct_cls0(Ts), member(C, Cs), char_code(Ch, C), findall(T, ( member(T, Ts), char_type(Ch, T) ), L), R = C-L.
% the arity-1 classes: the value each gives (code_type/2: codes, char_type/2: characters)
t2(R) :- ct_codes(Cs), ct_cls1(Ns), member(C, Cs),
    findall(T, ( member(N, Ns), T =.. [N, _], code_type(C, T) ), L), R = C-L.
t3(R) :- ct_codes_nz(Cs), ct_cls1(Ns), member(C, Cs), char_code(Ch, C),
    findall(N-V, ( member(N, Ns), T =.. [N, X], char_type(Ch, T), ( atom(X) -> char_code(X, V) ; V = X ) ), L),
    R = C-L.
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
% t1 and t3 for the character 0 alone (the atom of the character 0: the kernel refuses it, swipl answers)
t42(R) :- ct_cls0(Ts), C = 0, char_code(Ch, C), findall(T, ( member(T, Ts), char_type(Ch, T) ), L), R = C-L.
t43(R) :- ct_cls1(Ns), C = 0, char_code(Ch, C),
    findall(N-V, ( member(N, Ns), T =.. [N, X], char_type(Ch, T), ( atom(X) -> char_code(X, V) ; V = X ) ), L),
    R = C-L.
% CT1b-C1, C2: a member of a run whose two deltas differ (0x101 .. 0x104 alternate lower, upper), and CT1b-C3: the last run of the
% case table (U+1E922 .., Adlam small letters); the answer of each of the four mapping classes, raw
ct_map(C, L) :- findall(N-V, ( member(N, [to_lower, to_upper, upper, lower]), T =.. [N, V], code_type(C, T) ), L).
t44(R) :- member(C, [0x101, 0x102, 0x103, 0x104]), ct_map(C, L), R = C-L.
t45(R) :- member(C, [0x1e900, 0x1e921, 0x1e922, 0x1e943]), ct_map(C, L), R = C-L.
% CT1b-A22: digit(W) and xdigit(W) hold integers (CTX_CODE) in char_type/2 as well: the answers raw, not through char_code/2
t46(R) :- member(C, ['5', '0', '9', 'a']), findall(N-V, ( member(N, [digit, xdigit]), T =.. [N, V], char_type(C, T) ), L), R = C-L.
t47(R) :- member(C, ['5', 'f']), findall(T, ( char_type(C, T), T =.. [N, _], memberchk(N, [digit, xdigit]) ), L), R = C-L.
% CT1b-A25: the character end (-1, or end_of_file for char_type/2) is answered with the atom end_of_file BEFORE the class is looked up, so a
% class that names nothing FAILS (no type error); a class looked up first would raise type_error(char_type, foo) for these
t48(R) :- ct_res(code_type(-1, foo), R).
t49(R) :- ct_res(char_type(end_of_file, foo), R).
t50(R) :- ct_res(code_type(-1, 1), R).
t51(R) :- ct_res(code_type(-1, foo(1)), R).
