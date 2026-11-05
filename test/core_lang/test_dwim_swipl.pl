% ORIGINAL: the rows of test/core_lang/test_dwim_swipl.jl (its predicates, dwim_match/3 and '$dwim_predicate'/2, are pl-dwim.c's).
% test/core_lang/test_dwim_swipl.pl - DWIM1's rows. Each `tN(R)` is one row (a family of cases); test_dwim_swipl.out holds
% swipl 10.1.19's answers to them, as the test's driver prints them (`ok`, then one line per row: its name and every
% solution). Rows t0-t11 are dwim_match/3 over pairs of texts, each pair in both orders; rows t12-t33 are
% '$dwim_predicate'/2 over the module dwtm below, whose procedures the directives make: a row reads the SORTED set of
% Name/Arity answers (the order the answers come in is the hash order of the module's table in swipl).
% Characters above 0xFF and 0x80-0xFF are written as escapes, so the file is the same in every encoding.

:- dynamic dwtm:decl_only/1.
:- multifile dwtm:mf_pred/1.
:- discontiguous dwtm:disc_pred/1.
:- assertz(dwtm:foo_bar(1)).
:- assertz(dwtm:foo_bar(1, 2)).
:- assertz(dwtm:foo_baz).
:- assertz(dwtm:zzz_other(1, 2, 3)).
:- assertz(dwtm:'$foo_bor'(1)).
:- assertz(dwtm:'123'(1)).
:- assertz((dwtm:caller :- zz_never_defined_xy)).
:- catch(dwtm:zz_undef_called_xy, _, true).
:- assertz(dwtm:'caf\xe9\'(1)).
:- assertz(dwtm:'w\x20ac\bc'(1)).
:- assertz(dwtm:f(1)).
:- assertz(dwtm:'\x20ac\y'(1)).
:- compound_name_arguments(T, [], [1]), assertz(dwtm:T).
:- assertz(dwtm:'[]'(1, 2)).
:- assertz(dwtm:'{}'(1)).
zq_user_pred(1).

dw_mem(X, [X|_]).
dw_mem(X, [_|T]) :- dw_mem(X, T).
% the kind dwim_match/3 answers, or fail
dw_dm(A, B, R) :- catch(( dwim_match(A, B, K) -> R = K ; R = fail ), error(E, _), R = error(E)).
% every pair of the list, in both orders
dw_pairs(Ps, R) :- dw_mem(A-B, Ps), ( X-Y = A-B ; X-Y = B-A ), dw_dm(X, Y, K), R = X-Y-K.
% the sorted Name/Arity answers of '$dwim_predicate'/2 for a term
dw_dp(P, S) :- findall(N/A, ( '$dwim_predicate'(P, H), functor(H, N, A) ), L), msort(L, S).
dw_dps(Ps, R) :- dw_mem(P, Ps), dw_dp(P, S), R = P-S.
dw_sys(G) :- setup_call_cleanup(set_prolog_flag(access_level, system), once(G), set_prolog_flag(access_level, user)).

% equal: the same text, whatever its length (no length condition applies to two equal texts)
t0(R) :- dw_pairs([foo-foo, abc-abc, a-a, ab-ab, ''-'', foo_bar-foo_bar, 'Foo'-'Foo', 'a b'-'a b', 'caf\xe9\'-'caf\xe9\', abc-"abc", "abc"-"abc", 123-123, abc-[0'a, 0'b, 0'c], [a, b, c]-abc, []-[]], R).
% mismatched_char: one character differs (the first rest character; cl + l1 >= 3 is the lower bound)
t1(R) :- dw_pairs([spy-spu, abc-abd, abc-xbc, abc-aXc, hello-hallo, hello-jello, abcd-abce, abcdef-abcdeg, ab-ac, a-b, abc-xyz, 'a b'-'a c', a_c-a_d, 'caf\xe9\'-'caf\xe8\', 'ab\x80\'-'ab\xff\', 'x\xe9\y'-'x\xe8\y'], R).
% transposed_char: two adjacent characters swapped
t2(R) :- dw_pairs([trace-tarce, abc-bac, abc-acb, abcd-abdc, abcd-bacd, abca-abac, ab-ba, aab-aba, abcd-badc, abcde-abdce, abc-cba], R).
% inserted_char: one character inserted or deleted (either end of the common prefix)
t3(R) :- dw_pairs([debug-deug, abc-abcd, abc-xabc, abcd-abxcd, abcde-abcdef, abcde-bcde, abcde-abcd, ab-abc, a-ab, abc-abxy, abcdef-abcdefghijk, foobar-foo_bar, foo_bar-foobar, foo__bar-foo_bar, 'caf\xe9\e'-'cafe'], R).
% separated: the same words, written with another separation (_ or an upper case letter after a lower case one)
t4(R) :- dw_pairs([exists_file-existsFile, fooBarBaz-foobarbaz, fooBarBaz-foo_bar_baz, foo_bar_baz-fooBarBaz, fooBarBaz-foo_barBaz, aaBbCc-aa_bb_cc, a_b_c-aBC, abCdEf-ab_cd_ef, a_b-aB, aB-a_b, ab_cd-abCd, abCd-abcd, fooBar-foobar, foo_bar-foo_Bar, 'FooBar'-foo_bar, foo_bar_-foo_bar, foo__bar-fooBar, ab_c_d_e_f_g-abCdEfG, ab_c_d_e_f_g_h-abCdEfGh, fooAbcZed-fooabczed], R).
% transposed_word: two sub-words (split at _ or at a lower to upper case change) exchanged
t5(R) :- dw_pairs([exists_file-file_exists, fooBar-barFoo, foo_bar-bar_foo, a_b_c-b_a_c, one_two_three-two_one_three, abc_def-def_abc, abcDef-defAbc, foo_bar_baz-bar_foo_baz, foo_bar_baz-baz_bar_foo, foo_bar-foo_baz, abc_def-def_abx, 'Foo_bar'-bar_foo, foo_bar-bar__foo, 'foo_'-'_foo', ab_cd-cd_ab, ab-ba, foo_bar-bar_baz, foo_bar-baz_foo, 'Abc_def'-def_Abc, 'Zed_foo'-foo_Zed, abc_def-xyz, abc_def-def, abc-def_abc], R).
% no match: a difference of more than 5 in the length, too short a text, several differences, an empty text
t6(R) :- dw_pairs([a-abcdefgh, abc-abcdefghi, abcd-abcdefghi, abcde-abcdefghi, foo-barbaz, ''-abc, ''-a, ''-abcdefg, abc-abcdef, abc-abcdefg, abc-abxyz, abcde-abxyz, abcdef-ghijkl, abc-def, ab-cd, a-bc, ab-abcd, abcde-fghij, abcdef-abcxyz, fooBar-foo_bar_baz], R).
% case: upper and lower case are different characters; only the sub-word rules fold the case of a letter after a lower case one
t7(R) :- dw_pairs(['FOO'-foo, 'Foo'-foo, foo-'FOO', 'foo_bar'-'FOO_BAR', fooBar-foobar, foo_Bar-foobar, 'FooBar'-foobar, abc-'ABC', aBc-abc, 'Abc'-abc, abcD-abcd, abcDE-abcde, 'AB_CD'-'ab_cd', 'Foo_Bar'-'foo_bar'], R).
% short texts and the bound cl + l1 >= 3 (the common prefix counts)
t8(R) :- dw_pairs([a-b, a-ab, ab-abc, abc-abd, ab-ac, ab-ab, a-abc, abc-ab, abcd-abce, abc-bbc, ab-bb, ab-b, abc-b, a_-a_b, a-'', ''-''], R).
% texts that are no atoms: numbers, strings, code lists, character lists, the empty list; and terms that are no text
t9(R) :- dw_pairs([123-124, 12-13, 123-123, 1.5-1.6, 1.5-1.5, "abc"-abd, "abc"-"abd", "abc"-"abcd", [0'a, 0'b, 0'c]-abd, [a, b, c]-abd, [a, b, c]-[a, b, d], [0'a, 0'b, 0'c]-[a, b, d], []-abc, []-[a], [] -'', 123-"124", 123-'124', 1000000-1000001, 100000000000000000000-100000000000000000001, _-abc, abc-_, _-_, f(x)-f(y), f(x)-abc, abc-f(abc), [a|_]-abc, [a, b|c]-abc, [0'a, b, c]-abc, [a, 1, c]-abc, [-1]-abc, '$VAR'(1)-abc, 'a'-'a'], R).
% the third argument: bound to the kind, to another kind, to a non-atom, unbound
t10(R) :- dw_mem(K, [mismatched_char, equal, transposed_char, "mismatched_char", 1, f(x), _]), ( dwim_match(abc, abd, K) -> R = K-yes ; R = K-no ).
t11(R) :- dw_mem(K, [mismatched_char, equal, 1, _]), ( dwim_match(abc, abc, K) -> R = K-yes ; R = K-no ).
% the text is ISO Latin-1 and a C string: a character above 0xFF fails (silently), the text ends at its first NUL
t12(R) :- dw_pairs(['caf\x20ac\'-'caf\x20ac\', 'ab\x20ac\'-abc, 'abc\x20ac\'-'abc\x20ac\', '\x20ac\'-'\x20ac\', 'ab\x100\'-'ab\x100\', 'ab\xff\'-'ab\xfe\', "ab\x20ac\"-abc, [0'a, 0'b, 0'c, 0x20ac]-abc, [0'a, 0'b, 0'c, 0x20ac]-abcd, [0'a, 0'b, 0'c, 0x20ac]-[0'a, 0'b, 0'c, 0x20ac]], R).
t13(R) :- dw_pairs([[0'a, 0'b, 0'c, 0, 0'x]-[0'a, 0'b, 0'c, 0, 0'y], [0'a, 0'b, 0'c, 0, 0'x]-[0'a, 0'b, 0'd, 0, 0'x], [0'a, 0'b, 0'c, 0, 0'x]-[0'a, 0'b, 0'c], [0'a, 0'b, 0'c, 0, 0'x]-abd, [0'a, 0'b, 0'c, 0, 0'x]-abcdefghijk, [0, 0'a, 0'b, 0'c]-[0, 0'x, 0'y, 0'z], [0, 0'a]-abc, [0'a, 0'b, 0'c, 0, 0x20ac]-abc, [0'a, 0'b, 0'c, 0, 0x20ac]-abd, [0x20ac, 0]-abc], R).

% '$dwim_predicate'/2 over dwtm: foo_bar/1, foo_bar/2, foo_baz/0, zzz_other/3, '$foo_bor'/1, '123'/1, caller/0, f/1,
% 'caf\xe9\'/1, 'w\x20ac\bc'/1, '\x20ac\y'/1, []/1, '[]'/2, {}/1 (defined), decl_only/1 (dynamic, no clause), mf_pred/1 (multifile),
% disc_pred/1 (discontiguous): declared, and zz_never_defined_xy/0, which caller/0 calls, and zz_undef_called_xy/0, which a directive calls: nothing defines them.
% a near miss, the exact name (the same name with another arity, and one character off), a name nothing is near
t14(R) :- dw_dps([dwtm:foo_bor, dwtm:foo_bar, dwtm:foo_baz, dwtm:zzzzzz_none, dwtm:zzz_otheq, dwtm:zzz_other], R).
% only the name of the head matters, not its arguments
t15(R) :- dw_dps([dwtm:foo_bor(a, b), dwtm:foo_bor(_), dwtm:foo_bor(a, b, c, d), dwtm:foo_baz(x)], R).
% the head of the answer: the functor with fresh variables
t16(R) :- findall(H, '$dwim_predicate'(dwtm:foo_baz, H), L), msort(L, R).
t17(R) :- findall(H, '$dwim_predicate'(dwtm:zzz_otheq, H), L), L = [H0], R = H0.
% the second argument is bound: only a procedure with that functor answers (the others are skipped)
t18(R) :- dw_mem(D, [foo_bar(_, _), foo_bar(_), foo_bar, foo_qux(_), foo_baz, foo_baz(_), zzz_other(_, _, _), 7, _]),
    findall(x, '$dwim_predicate'(dwtm:foo_bar, D), L), length(L, N), R = D-N.
% once/1 cuts the enumeration; a failed call leaves nothing behind; two enumerations live at once do not disturb each other
t19(R) :- ( once('$dwim_predicate'(dwtm:foo_bar, H)), functor(H, N, _) -> memberchk(N, [foo_bar, foo_baz]), R = found ; R = none ).
t20(R) :- ( \+ \+ '$dwim_predicate'(dwtm:zzzzzz_none, _) -> R = found ; R = none ).
t21(R) :- findall(N-N2, ( '$dwim_predicate'(dwtm:foo_bar, H), functor(H, N, _), '$dwim_predicate'(dwtm:zzz_otheq, H2), functor(H2, N2, _) ), L), msort(L, R).
% declared procedures are defined; a referenced one that nothing defines is not
t22(R) :- dw_dps([dwtm:decl_onlz, dwtm:mf_pre, dwtm:disc_pre, dwtm:zz_never_defined_xz, dwtm:zz_never_defined_xy, dwtm:zz_undef_called_xz, dwtm:zz_undef_called_xy, dwtm:calle], R).
% a name that begins with $ answers only in system mode
t23(R) :- dw_dps([dwtm:'$foo_bar', dwtm:'$foo_bor', dwtm:foo_bor, dwtm:'$foo_bax'], R).
t24(R) :- dw_mem(P, [dwtm:'$foo_bar', dwtm:'$foo_bor', dwtm:foo_bor, dwtm:'$foo_bax', dwtm:foo_bar]), dw_sys(dw_dp(P, S)), R = P-S.
% the access level is back to user after dw_sys/1
t25(R) :- dw_sys(true), dw_dps([dwtm:'$foo_bar'], R).
% the head is what PL_get_functor reads: an atom or a compound; a number, a string and a variable have none
t26(R) :- dw_dps([dwtm:'123', dwtm:123, dwtm:124, dwtm:"foo_bor", dwtm:"foo_bar", dwtm:_, dwtm:[], dwtm:'[]', dwtm:'{}', dwtm:{}, dwtm:{x}, dwtm:(a, b), dwtm:[a], dwtm:f, dwtm:f(x)], R).
% the module: the one the term names; a module that has no procedures, one that does not exist, a nested qualification
t27(R) :- dw_dps([nomod_zz:foo_bor, user:foo_bor, dwtm:foo_bor, dwtm:dwtm:foo_bor, nomod_zz:dwtm:foo_bor, dwtm:nomod_zz:foo_bor, dwtm:user:foo_bor], R).
% no module in the term: the module of the context, which a system predicate takes to be system
t28(R) :- dw_dps([zq_user_prd, zq_user_pred], R).
t29(R) :- dw_dp(atom_lengtn, S), ( memberchk(atom_length/2, S) -> R = has_atom_length ; R = none ).
t30(R) :- dw_dp(user:zq_user_prd, S), R = S.
% ISO Latin-1 names, and a name of 0x80-0xFF characters
t31(R) :- dw_dps([dwtm:'caf\xe8\', dwtm:'caf\xe9\', dwtm:cafe, dwtm:'f\xe9\z', dwtm:'f\xe8\', dwtm:fo, dwtm:f, dwtm:'foo_ba\xe9\'], R).
% atoms with a character above 0xFF (wide atoms): swipl compares the names as the char strings its wide atoms hold
t32(R) :- dw_dps([dwtm:'w\x20ac\qq', dwtm:'w\x20ac\bc', dwtm:'f\x20ac\zz', dwtm:'\x20ac\x', dwtm:'\x20ac\y', dwtm:'foo_ba\x20ac\', dwtm:f, dwtm:'w\x20ac\'], R).
t33(R) :- dw_dps([dwtm:w, dwtm:wa, dwtm:'\xac\', dwtm:'\xac\ '], R).

% the unknown=warning flow (pl-vmi.c S_UNDEF, boot/messages.pl): a call of an undefined procedure with unknown=warning prints TWO
% warnings, unknown_in_module_user (the flag in the global module) and the existence_error whose lines name the near procedures
% ('$dwim_predicate'/2, through boot/dwim.pl: "However, there are definitions for:"). The hook records (Kind, Term, Lines) of the
% warnings and prints nothing; the path of the url(File:Line, _) line is cut to the base name (the file is at another path in every checkout).
:- dynamic dw_msg/3, dw_rec/0.
:- multifile user:message_hook/3.
user:message_hook(Term, Kind, Lines) :- dw_rec, Kind == warning, dw_norm(Lines, L1), assertz(dw_msg(Kind, Term, L1)).
dw_norm([], []).
dw_norm([url(P:L, A)|T], [url(B:L, A)|T1]) :- !, file_base_name(P, B), dw_norm(T, T1).
dw_norm([X|T], [X|T1]) :- dw_norm(T, T1).
dwim_target_pred(1).
t34(R) :- assertz(dw_rec), set_prolog_flag(unknown, warning), ( catch(dwim_target_prd, _, fail) -> B = yes ; B = no ),
    set_prolog_flag(unknown, error), retractall(dw_rec), findall(K-T-L, retract(dw_msg(K, T, L)), Ms), R = B-Ms.
