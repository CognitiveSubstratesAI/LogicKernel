% ORIGINAL: the rows of test/core_lang/test_fast_rec_swipl.jl (its predicate, fast_term_serialized/2, is pl-rec.c's).
% test/core_lang/test_fast_rec_swipl.pl - FAST-1c's rows. Each `tN(R)` / `rN(R)` is one row (a family of cases); test_fast_rec_swipl.out
% holds swipl 10.1.20's answers to them, as the test's driver prints them (`ok`, then one line per row: its name and every
% solution). R is the code list of the string fast_term_serialized(Term, String) makes (its bytes), or a short summary.
%   t0-t6   the pinned layouts (one solution each: the test holds their bytes as literals)
%   t7-t66  the encoder: term to string
%   r0-r14  the decoder side (string to term): the round trips and the bound-string answers; the kernel decodes in FAST-2
% Characters above 0xFF and 0x80-0xFF are written as escapes, so the file is the same in every encoding.
% No row carries a size, an offset, a variable number or a length in 256..383, 512..639, 1024..1151 ... (a value written with
% addSizeInt; the header's two sizes are written with addUintBuffer and are outside them as well). Rows for those ranges follow
% the land of wip/rec-sizeint. A dict row has one key: the order of several is the order of their atom handles.

fs(T, Cs) :- fast_term_serialized(T, S), string_codes(S, Cs).
% the first 10 and the last 6 bytes and the count, for a long record
fsh(T, N-P-Tl) :- fs(T, Cs), length(Cs, N),
    ( N > 16 -> length(P, 10), append(P, _, Cs), length(Tl, 6), append(_, Tl, Cs) ; P = Cs, Tl = [] ).
rep(N, C, L) :- length(L, N), maplist(=(C), L).
% what a caught permission_error says, the culprit by its blob type
perm(error(permission_error(A, B, C), _), perm(A, B, Ty)) :- blob(C, Ty).
rt(T, R) :- fast_term_serialized(T, S), fast_term_serialized(T2, S), ( T2 =@= T -> R = same ; R = differ ).

% ---- the pinned layouts (the bytes are literals in the test) ----
t0(R) :- fs(f("abc"), R).                                   % a Latin-1 string: its storage tag B, then the characters
t1(R) :- fs(f("\x3b1\\x3b2\"), R).                          % a wide string: W 0 0 0 then 4 little-endian bytes each
t2(R) :- fs(f("\xe9\"), R).
t3(R) :- X = g(a), Q is 1 rdiv 3, fs(f(Q, X, X), R).   % an mpq's cells before a shared subterm
t4(R) :- X = g(a), N is 10**20, fs(f(N, X, X), R).          % an mpz's cells (2 limbs) before a shared subterm
t5(R) :- X = g(a), fs(f(1.5, X, X), R).                     % a float's cells before a shared subterm
t6(R) :- X = g(a), fs(f("abc", X, X), R).                   % a string's cells before a shared subterm

% ---- atoms (the root atom: a record without header) ----
t7(R) :- member(A, [a, abc, 'hello world', '', x, 'Hello', '123']), fs(A, R).
t8(R) :- member(A, ['\xe9\', 'caf\xe9\', '\x80\', '\xff\', '\xe9\\xe9\']), fs(A, R).
t9(R) :- member(A, ['\x3b1\', '\x3b1\\x3b2\', 'a\x3b1\b', '\x100\', '\x20ac\', '\x1f600\']), fs(A, R).
t10(R) :- member(A, [[], '[]', dict, 'Dict', '{}', '[|]']), fs(A, R).
t11(R) :- atom_codes(A, [0'a, 0, 0'b]), fs(A, R).
t12(R) :- member(N, [126, 127, 128, 200]), rep(N, 0'x, L), atom_codes(A, L), fsh(A, R).     % the length as 1 or 2 bytes
t13(R) :- member(N, [20, 40, 100]), rep(N, 0x3b1, L), atom_codes(A, L), fsh(A, R).         % a wide atom: 4 bytes a character

% ---- integers ----
t14(R) :- member(N, [0, 1, -1, 2, 127, 128, -128, -129, 255, 256, 257, 65535, 65536, 2147483647, -2147483648, 4294967296]), fs(N, R).
t15(R) :- member(E, [2**56-1, 2**56, -(2**56), -(2**56)-1, 2**62, 2**63-1, -(2**63)]), N is E, fs(N, R).   % int64: a root integer has no header
t16(R) :- member(E, [2**63, -(2**63)-1, 2**64, -(2**64), 2**200, -(2**200), 10**30]), N is E, fs(N, R).
t17(R) :- member(E, [0, 1, -1, 127, 128, 255, 256, 65535, 2**31, 2**55, 2**56-1, -(2**56)]), N is E, fs(f(N), R).   % tagged integers
t18(R) :- member(E, [2**56, -(2**56)-1, 2**62, 2**63-1, -(2**63)]), N is E, fs(f(N), R).    % beyond the tagged range, within int64
t19(R) :- member(E, [2**63, 2**64, -(2**64), 2**200, 10**30]), N is E, fs(f(N), R).         % beyond int64

% ---- floats ----
t20(R) :- member(F, [1.5, -1.5, 0.0, -0.0, 1.0e100, 3.141592653589793, 5.0e-324, 1.7976931348623157e308]), fs(F, R).
t21(R) :- member(E, [inf, -inf, nan]), F is E, fs(F, R).
t22(R) :- fs(f(1.5), R).
t23(R) :- F = 2.5, fs(f(F, F, 1.5), R).

% ---- strings ----
t24(R) :- member(Cs, [[], [97], [97, 98, 99], [233], [97, 233, 98], [255], [97, 0, 98], [128]]), string_codes(S, Cs), fs(S, R).
t25(R) :- member(Cs, [[945], [945, 946], [97, 945, 98], [256], [8364], [255, 256], [128512]]), string_codes(S, Cs), fs(S, R).
t26(R) :- fs(f("abc", "\xe9\", "\x3b1\"), R).
t27(R) :- member(N, [126, 127, 128, 200]), rep(N, 0'x, L), string_codes(S, L), fsh(S, R).   % L = N+1 as 1 or 2 bytes
t28(R) :- member(N, [20, 40, 100]), rep(N, 0x3b1, L), string_codes(S, L), fsh(S, R).        % a wide string: L = 4(N+1)

% ---- rationals ----
t29(R) :- member(E, [2**70 rdiv 3, 2**100 rdiv 3**50]), Q is E, fs(Q, R).
% swipl 10.1.20 answers these root rationals with an INTEGER record: 1r3 gives the integer 3, -2r7 gives -3, 7r2**80 gives 5.
% The kernel writes the rational's own PL_REC_MPQ record. The row is pending a named DIVERGES (audit ruling).
t30(R) :- member(E, [1 rdiv 3, -2 rdiv 7, 7 rdiv 2**80]), Q is E, fs(Q, R).
t31(R) :- member(E, [1 rdiv 3, -2 rdiv 7, 2**70 rdiv 3]), Q is E, fs(f(Q), R).

% ---- the cells of each value kind, read from the offset of a shared subterm (the PL_REC_CYCLE index) ----
t32(R) :- X = g(a), member(E, [5, 2**63, 2**64, 2**200, 1 rdiv 3, 2**70 rdiv 3, 2**100 rdiv 3**50]), N is E, fs(f(N, X, X), R).
t33(R) :- X = g(a), member(V, [1.5, "abc", "", "\x3b1\", "a longer string of 29 characters"]), fs(f(V, X, X), R).
t34(R) :- X = g(a), N is 2**62, fs(f(N, X, X), R).          % an int64 beyond the tagged range

% ---- variables ----
t35(R) :- fs(_, R).
t36(R) :- fs(f(X, X), R).
t37(R) :- fs(f(_X, _Y), R).
t38(R) :- fs(f(_, _), R).
t39(R) :- fs(f(X, g(X, Y), Y, h(_Z, X)), R).
t40(R) :- length(L, 40), fsh(L, R).
t41(R) :- functor(T, f, 200), fsh(T, R).                    % variable numbers 128..199 take 2 bytes

% ---- compounds and lists ----
t42(R) :- member(T, [f(a), f(a, b), g(a, b, c, d, e), -(a), a+b*c, [a, b, c], [a|b], '[|]'(a, b), f(g(h(i))),
                     f('\xe9\', "\xe9\"), 'caf\xe9\'(1), '\x3b1\'(a), f('\x3b1\'), 'hello world'(x), {a}, f([]), f(dict)]), fs(T, R).
t43(R) :- member(N, [[], '[]', dict, '{}', 'caf\xe9\', '\x3b1\']), compound_name_arguments(T, N, [x]), fs(T, R).
t44(R) :- member(N, [a, '\x3b1\']), compound_name_arguments(T, N, []), fs(T, R).
t45(R) :- numlist(1, 20, L), fs(L, R).
t46(R) :- member(T, [[1.5, "s", a, f(x), '\xe9\'], [a, b|_], [a|b]]), fs(T, R).
t47(R) :- numlist(1, 160, L), fsh(L, R).                    % the header's two sizes take 2 bytes

% ---- sharing, cycles ----
t48(R) :- X = g(a), fs(f(X, X), R).
t49(R) :- X = g(a), Y = h(X), fs(f(Y, X, Y), R).
t50(R) :- X = g(Y), fs(f(X, X, Y), R).
t51(R) :- X = f(X), fs(X, R).
t52(R) :- X = [a|X], fs(X, R).
t53(R) :- X = f(_, X), fs(X, R).
t54(R) :- X = f(1.5, "s", X), fs(X, R).

% ---- dicts (one key) ----
t55(R) :- member(Tag, [t, _]), dict_create(D, Tag, [a-1]), fs(D, R).
t56(R) :- dict_create(D, t, []), fs(D, R).
t57(R) :- dict_create(E, u, [c-1]), dict_create(D, t, [a-E]), fs(D, R).

% ---- blobs: the error, and what is restored after it ----
t58(R) :- current_output(S), catch(fs(f(S), _), E, true), perm(E, R).
t59(R) :- current_output(S), member(T, [f(a, g(S)), [a, b, S], g(S, S), f(_, S)]),
    catch(fs(T, _), E, true), perm(E, R).
t60(R) :- current_output(S), catch(fs(f(X, Y, S), _), error(permission_error(_, _, _), _), true), R = vars(X, Y).
t61(R) :- current_output(S), Y = g(a), catch(fs(f(Y, Y, S), _), error(permission_error(_, _, _), _), true), fs(f(Y, Y), R).
t62(R) :- current_output(S),
    catch(( fast_term_serialized(S, _) -> R = true ; R = false ), error(F, _), ( F =.. [Fn|_], R = err(Fn) )).

% ---- the second argument bound: what is not a record, what is not a string ----
t63(R) :- member(B, [42, foo, f(x), 1.5, [97]]),
    catch(( fast_term_serialized(a, B) -> R = true ; R = false ), error(E, _), R = E).
t64(R) :- member(Cs, [[114, 1, 2], [118, 5, 1]]), string_codes(S, Cs),
    ( fast_term_serialized(_, S) -> R = true ; R = false ).
t65(R) :- fs(f(a), Cs0), append(Cs0, [0], Cs1), string_codes(S, Cs1),     % a record and a byte more
    ( fast_term_serialized(_, S) -> R = true ; R = false ).
t66(R) :- fs(f(a), Cs0), append(Cs1, [_], Cs0), string_codes(S, Cs1),     % a record less its last byte
    ( fast_term_serialized(_, S) -> R = true ; R = false ).

% ---- the decoder side (string to term): the kernel decodes in FAST-2 ----
r0(R) :- rt(f(X, _, X), R).
r1(R) :- N is 2**70, M is 10**30,
    member(T, [a, '\xe9\', '\x3b1\', [], 42, -1, N, 1.5, "abc", "\x3b1\", f(a, b), [a, b, c], 'x y'(1), M]), rt(T, R).
r2(R) :- X = f(X), fast_term_serialized(X, S), fast_term_serialized(Y, S), ( cyclic_term(Y) -> R = cyclic ; R = acyclic ).
r3(R) :- rt(f(X, g(X), Y, Y), R).
r4(R) :- string_codes(S, [114, 8, 2, 13, 1, 11, 1, 102, 11, 1, 97]), fast_term_serialized(T, S), R = T.   % swipl's own bytes of f(a)
r5(R) :- fast_term_serialized(f(_), S0), ( fast_term_serialized(f(a), S0) -> R = true ; R = false ).
r6(R) :- string_codes(S, [945]), catch(( fast_term_serialized(_, S) -> R = true ; R = false ), error(E, _), R = E).
r7(R) :- dict_create(D, t, [a-1]), rt(D, R).
r8(R) :- member(Cs, [[122, 9], [118, 1, 5], [122, 11, 1, 97], [118, 2, 255, 128]]), string_codes(S, Cs),
    fast_term_serialized(T, S), R = T.     % the header-less records: [], an integer, an atom
r9(R) :- X is 1 rdiv 3, N is 2**70 rdiv 3, rt(f(X, N, "s", 'a\x3b1\'), R).
r10(R) :- rt(f(1.5, a, -2.25, "s", 'x'), R).     % floats inside a compound, more cells after each
r11(R) :- member(E, [2**56, -(2**56)-1, 2**62, 2**63-1, -(2**63), 2**64, 10**30]), N is E, rt(f(N, a, N, "s"), R).   % an mpz record inside a compound, int64 or not
r12(R) :- member(Cs, [[114, 11, 6, 13, 1, 11, 1, 102, 18, 0, 0, 0, 1, 5], [114, 11, 6, 13, 1, 11, 1, 102, 18, 255, 255, 255, 255, 5]]),
    string_codes(S, Cs), fast_term_serialized(T, S), R = T.     % PL_REC_MPZ records of the small integers 5 and -5 inside f(_)
r13(R) :- X is 2**62 rdiv 3, Y is 3 rdiv 2**62, Z is -2 rdiv 7, rt(f(X, Y, Z, a), R).   % rationals inside a compound: a numerator and a denominator of 8 bytes, a negative one
r14(R) :- string_codes(S, [114, 18, 6, 13, 5, 10, 11, 1, 116, 11, 1, 97, 4, 1, 2, 11, 1, 98, 4, 1, 1]), fast_term_serialized(T, S),
    findall(K-V, get_dict(K, T, V), R).     % a dict record whose keys are out of order (2 then 1): the copy puts them in order
