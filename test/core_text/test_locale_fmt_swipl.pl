% ORIGINAL: the rows of test/core_text/test_locale_fmt_swipl.jl (format/2's `~:d` and `~:f`, the locale of a stream, and collation_key/2: the
% unit tests of swipl-devel tests/core_text/test_locale.pl, groups `locale` and `collation_key`, as program rows).
% test/core_text/test_locale_fmt_swipl.pl - LOCALE-FMT rows. Each `tN(R)` is one row with ONE solution (a list: every action of the row, in
% order); test_locale_fmt_swipl.out holds swipl 10.1.20's answers, as the test's driver prints them (`ok`, then one line per row).
% Every locale a row makes is made from the name "C" with decimal_point, thousands_sep and grouping given EXPLICITLY (the machine's locale is
% never read, except by the two default_decimal_point rows, which ask the default locale for its own decimal point as upstream does);
% each row restores the current locale at its end. No row prints on user_output.
lf_res(G, R) :- catch(( G -> R = true ; R = false ), error(E, _), R = error(E)).
% the locales: lfa is upstream's `test` locale (setup_test_locale), lfb is another, lfd has no grouping
lf_mk :- locale_create(_, "C", [alias(lfa), decimal_point('.'), thousands_sep(','), grouping([repeat(3)])]),
    locale_create(_, "C", [alias(lfb), decimal_point(','), thousands_sep(' '), grouping([2,repeat(3)])]),
    locale_create(_, "C", [alias(lfd), decimal_point('.'), thousands_sep(''), grouping([])]).
lf_rm :- forall(member(A, [lfa, lfb, lfd]), catch(locale_destroy(A), error(_, _), true)).
lf_setup(Old) :- current_locale(Old), lf_mk, set_locale(lfa).
lf_cleanup(Old) :- set_locale(Old), lf_rm.
% run Goal with lfa current, restoring the locale at the end
lf_run(G) :- setup_call_cleanup(lf_setup(Old), G, lf_cleanup(Old)).
% format to an atom: the text, or the error
lf_f(F, As, R) :- catch(format(atom(R), F, As), error(E, _), R = error(E)).
lf_fs(L, R) :- findall(F-As-A, ( member(F-As, L), lf_f(F, As, A) ), R).
lf_fw(Props, F, As, R) :-
    current_locale(Old), locale_create(Tmp, Old, Props),
    setup_call_cleanup(set_locale(Tmp), lf_f(F, As, R), set_locale(Old)).
% ~D and ~:d, upstream's `group` tests
t0(R) :- lf_run(lf_fs(['~D'-[0], '~D'-[1000], '~2D'-[1000], '~2D'-[100000], '~:D'-[1234567], '~:d'-[0], '~:d'-[1000], '~2:d'-[1000],
        '~2:d'-[100000], '~:d'-[-1000], '~:d'-[1234567], '~:d'-[123456789012], '~2:d'-[-100000], '~0:d'-[1000], '~d'-[1000], '~2d'-[1000],
        '~:d'-[a]], R)).
% ~2:f of integers, floats, and the same with a rational (the colon takes the stream's locale; ~2f without it does not)
t1(R) :- lf_run(lf_fs(['~2:f'-[0], '~2:f'-[10], '~2:f'-[1000], '~2:f'-[-0], '~2:f'-[-10], '~2:f'-[-1000], '~2:f'-[1234567890], '~2:f'-[-1234567890],
        '~2:f'-[0.0], '~2:f'-[10.0], '~2:f'-[1000.0], '~2:f'-[-0.0], '~2:f'-[-10.0], '~2:f'-[-1000.0], '~2:f'-[1234567.89], '~0:f'-[1234567.89],
        '~:f'-[1234567.5], '~2:F'-[1234567.5], '~2f'-[1234567.89], '~2:f'-[1 rdiv 1000], '~2:f'-[1234567890 rdiv 1], '~2:f'-[9999 rdiv 1000],
        '~2:f'-[-9999 rdiv 1000], '~2:f'-[x]], R)).
% ~:e, ~:E and ~:g are NOT locale sensitive (upstream's `prolog_locale`)
t2(R) :- lf_run(lf_fs(['~2:e'-[0], '~2:e'-[10], '~2:e'-[1000], '~2:e'-[-1000], '~2:e'-[0.0], '~2:e'-[-0.0], '~2:e'-[1000.0], '~2:e'-[1 rdiv 1000],
        '~2:e'-[9999 rdiv 1000], '~2:E'-[10], '~2:E'-[1 rdiv 1000], '~2:e'-[1234567.5], '~3:g'-[1234567.5]], R)).
% a row of lfb as the current locale: the grouping [2, repeat(3)], a blank thousands_sep and a comma decimal point
t3(R) :- setup_call_cleanup(lf_setup(Old), ( set_locale(lfb), lf_fs(['~:d'-[1234567], '~2:d'-[1234567], '~:d'-[12], '~:d'-[123], '~:d'-[1234],
        '~2:f'-[1234567.89], '~:f'-[1234567.5], '~D'-[1234567], '~2:e'-[1234567.5], '~2f'-[1234567.5]], R) ), lf_cleanup(Old)).
% lfd: no grouping, the point stays
t4(R) :- setup_call_cleanup(lf_setup(Old), ( set_locale(lfd), lf_fs(['~:d'-[1234567], '~2:d'-[1234567], '~2:f'-[1234567.89]], R) ), lf_cleanup(Old)).
% upstream's format_with_locale/4 tests (the temporary locale is made from the current one)
t5(R) :- lf_run(( lf_fw([grouping([2,2])], '~:d', [123456789], A1), lf_fw([grouping([2,2])], '~2:d', [123456789], A2),
        lf_fw([grouping([2,2,repeat(3)])], '~:d', [123456789], A3), lf_fw([decimal_point(','), thousands_sep('.')], '~2:d', [123456789], A4),
        lf_fw([decimal_point(','), thousands_sep(' ')], '~2:d', [123456789], A5),
        lf_fw([decimal_point(','), thousands_sep('. ')], '~2:d', [123456789], A6),
        lf_fw([decimal_point(','), thousands_sep(' ')], '~2:f', [1234567.89], A7),
        lf_fw([decimal_point(','), thousands_sep('. ')], '~2:f', [1234567.89], A8),
        lf_fw([decimal_point(','), thousands_sep('.')], '~2f', [1234567.89], A9),
        lf_fw([grouping([3]), thousands_sep(x)], '~:d', [123456789], A10),
        R = [A1, A2, A3, A4, A5, A6, A7, A8, A9, A10] )).
% upstream's default_decimal_point (issue #1525): the temporary locale uses the default locale's own decimal point
t6(R) :- lf_run(( locale_property(default, decimal_point(DP)),
        lf_fw([decimal_point(DP), thousands_sep(':')], '~2:f', [1234567.89], A1),
        lf_fw([decimal_point(DP), thousands_sep(':')], '~2:d', [123456789], A2),
        atomic_list_concat(['1:234:567', DP, '89'], E),
        R = [A1-E, A2-E, A1==E, A2==E] )).
% the stream's locale: a stream made while lfa is current has lfa (the memory stream of format(atom(_)), with_output_to/2), and the
% current output follows set_locale/1 (it is one of the first five streams)
t7(R) :- lf_run(( with_output_to(atom(A1), format('~:d', [1234567])),
        with_output_to(string(A2), format('~2:f', [1234567.5])),
        with_output_to(atom(A3), ( set_locale(lfb), format('~:d', [1234567]) )),
        current_locale(L), L == lfb,
        with_output_to(atom(A4), format('~:d', [1234567])),
        set_locale(lfa),
        R = [A1, A2, A3, A4] )).
% a memory stream outside the first five keeps the locale it was made with: the outer stream M is made under lfa; an inner with_output_to
% replaces the current output, and set_locale/1 there reaches the inner stream and the user streams, not M
t8(R) :- lf_run(( with_output_to(atom(A), ( current_output(M), format('~:d ', [1234567]),
            with_output_to(string(_), set_locale(lfb)),
            current_locale(L1), format('~w ', [L1]), format(M, '~:d ', [1234567]), format('~:d', [1234567]) )),
        set_locale(lfa),
        R = [A] )).
% a memory stream made while lfb is current, then lfa is set: the stream made under lfb stays on lfb
t9(R) :- lf_run(( set_locale(lfb),
        with_output_to(atom(A), ( current_output(M), with_output_to(string(_), set_locale(lfa)), format(M, '~:d ', [1234567]) )),
        set_locale(lfa),
        R = [A] )).
% a locale is kept by the stream while it lives: destroying the alias does not change what the stream prints
t10(R) :- lf_run(( locale_create(_, "C", [alias(lfx), decimal_point(';'), thousands_sep('_'), grouping([1,repeat(2)])]),
        set_locale(lfx),
        with_output_to(atom(A), ( current_output(M), with_output_to(string(_), set_locale(lfa)),
            catch(locale_destroy(lfx), error(_, _), true), format(M, '~:d ~2:f', [1234567, 1234567.5]) )),
        R = [A] )).
% the locale of a file stream is the current locale at open/4
t11(R) :- lf_run(( current_prolog_flag(pid, Pid), format(atom(F), '/tmp/lk_locale_fmt_t11_~w', [Pid]),
        open(F, write, S), set_locale(lfb), format(S, '~:d ~2:f', [1234567, 1234567.5]), close(S),
        set_locale(lfa),
        open(F, write, S2), format(S2, '~:d', [1234567]), close(S2), open(F, read, In1), read_string(In1, _, T2), close(In1),
        set_locale(lfb), open(F, write, S3), set_locale(lfa), format(S3, '~:d', [1234567]), close(S3),
        open(F, read, In2), read_string(In2, _, T3), close(In2), delete_file(F),
        R = [T2, T3] )).
% collation_key/2: a string, the same key for the same text, the order of a and b, strings and atoms alike
t12(R) :- lf_res(( collation_key(abc, K), string(K) ), R1), lf_res(( collation_key("abc", K2), string(K2) ), R2),
    lf_res(( collation_key(abc, K3), collation_key(abc, K4), K3 == K4 ), R3), lf_res(( collation_key(abc, K5), string_length(K5, L5), L5 > 0 ), R4),
    lf_res(( collation_key(a, A1), collation_key(b, B1), A1 @< B1 ), R5), lf_res(( collation_key(abc, A2), collation_key(abd, B2), A2 @< B2 ), R6),
    lf_res(( collation_key(b, A3), collation_key(a, B3), A3 @< B3 ), R7), lf_res(( collation_key('', K8), string(K8), string_length(K8, 0) ), R8),
    lf_res(( collation_key(abc, "x") ), R9), lf_res(( collation_key(abc, K10), K10 == abc ), R10),
    R = [R1, R2, R3, R4, R5, R6, R7, R8, R9, R10].
% collation_key/2: texts of 0, 1, 100, 255, 256, 257, 500, 2000 characters: the key is not shorter than the text and, from 256 on, needs more than the first buffer
lf_ck(N, N-R) :- length(L, N), maplist(=(0'a), L), atom_codes(A, L), lf_res(( collation_key(A, K), string(K), string_length(K, KL), KL >= N ), R).
t13(R) :- findall(X, ( member(N, [0, 1, 100, 255, 256, 257, 500, 2000]), lf_ck(N, X) ), R).
% upstream's WCSXFRM_BUFFER_OVERRUN: every printable code from 32 to 1000
t14(R) :- findall(C, ( between(32, 1000, C), code_type(C, print) ), Codes), atom_codes(Atom, Codes), length(Codes, Len),
    lf_res(( collation_key(Atom, K), string(K) ), R1), lf_res(( string_codes(Str, Codes), collation_key(Str, K2), string(K2) ), R2),
    R = [Len, R1, R2].
% collation_key/2: the errors
t15(R) :- findall(G-E, ( member(G, [collation_key(_, _), collation_key(f(x), _), collation_key(42, _), collation_key(1.5, _), collation_key([], _),
        collation_key("", _), collation_key([a], _), collation_key(abc, 1)]), lf_res(G, E) ), R).
