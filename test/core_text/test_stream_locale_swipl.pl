% ORIGINAL: the rows of test/core_text/test_stream_locale_swipl.jl (their built-ins, open/4's locale(Locale) option, set_stream/2's locale(Locale) and the
% stream property locale(Locale), are pl-file.c's; the locale objects pl-locale.c's).
% test/core_text/test_stream_locale_swipl.pl - CT1 LOCALE-STREAM rows. Each `tN(R)` is one row with ONE solution (a list: every action of the row,
% in order); test_stream_locale_swipl.out holds swipl 10.1.20's answers, as the test's driver prints them (`ok`, then one line per row).
% Every locale a row makes is made from the name "C" with decimal_point, thousands_sep and grouping given EXPLICITLY (the machine's locale is never read);
% the files are tmp_file/2 names, closed and deleted at the row's end; nothing here reads or waits on a terminal.
lcs_res(G, R) :- catch(( G -> R = true ; R = false ), error(E, _), R = error(E)).
lcs_mk(A, Props) :- locale_create(_, "C", [alias(A)|Props]).
lcs_destroy(A) :- catch(locale_destroy(A), error(_, _), true).
lcs_prop(S, L) :- findall(X, stream_property(S, locale(X)), [L]).
% open/4 with locale(Alias): the stream has exactly that locale (stream_property answers the ALIAS atom: unifyLocale(..., true)) and its properties
t0(R) :- lcs_mk(lcs0, [decimal_point(','), thousands_sep('.'), grouping([3])]), tmp_file(lcs, F),
    open(F, write, S, [locale(lcs0)]), lcs_prop(S, L), locale_property(L, decimal_point(D)), locale_property(L, thousands_sep(T)),
    close(S), delete_file(F), lcs_destroy(lcs0), R = [L, D, T].
% open/4 with locale(Blob): the alias is destroyed while the stream holds the locale; the property then answers the blob (the stream's reference
% keeps the locale and its properties alive), the same blob as before the destroy
t1(R) :- lcs_mk(lcs1, [decimal_point(';')]), locale_property(B, alias(lcs1)), tmp_file(lcs, F), open(F, write, S, [locale(B)]),
    lcs_prop(S, L1), locale_destroy(lcs1), lcs_prop(S, L2), ( L2 == B -> K = blob ; K = other ), locale_property(L2, decimal_point(D)),
    close(S), delete_file(F), R = [L1, K, D].
% a stream opened without the option has the current locale (the default one at the start); so have the standard streams
t2(R) :- tmp_file(lcs, F), open(F, write, S, []), lcs_prop(S, L0), lcs_prop(user_output, L1), lcs_prop(user_input, L2), close(S), delete_file(F),
    R = [L0, L1, L2].
% set_stream/2: by alias, then by blob; a second stream opened meanwhile is not touched
t3(R) :- lcs_mk(lcs3, [decimal_point('!')]), lcs_mk(lcs3b, [decimal_point('?')]), tmp_file(lcs, F), tmp_file(lcs, F2),
    open(F, write, S, [locale(lcs3)]), lcs_prop(S, A), set_stream(S, locale(lcs3b)), lcs_prop(S, B),
    locale_property(Bl, alias(lcs3)), set_stream(S, locale(Bl)), lcs_prop(S, C), open(F2, write, S2, []), lcs_prop(S2, D),
    close(S2), close(S), delete_file(F), delete_file(F2), lcs_destroy(lcs3), lcs_destroy(lcs3b), R = [A, B, C, D].
% the errors of a locale that is not one: an unknown alias is existence_error(locale, A), another term type_error(locale, T), in open/4 and in
% set_stream/2 alike; a refused open leaves no file, a refused set_stream leaves the stream's locale
t4(R) :- tmp_file(lcs, F), tmp_file(lcs, F2), lcs_res(open(F, write, _, [locale(nosuch)]), E1), lcs_res(open(F, write, _, [locale(1)]), E2),
    lcs_res(open(F, write, _, [locale(f(x))]), E3), lcs_res(open(F, write, _, [locale(_)]), E4),
    ( exists_file(F) -> X = exists ; X = absent ),
    open(F2, write, S, []), lcs_prop(S, L0), lcs_res(set_stream(S, locale(nosuch)), E5), lcs_res(set_stream(S, locale(1)), E6),
    lcs_res(set_stream(S, locale(g(y))), E7), lcs_res(set_stream(S, locale(_)), E8), lcs_prop(S, L1),
    close(S), delete_file(F2), R = [E1, E2, E3, E4, X, E5, E6, E7, E8, L0, L1].
% what a stream's locale does: format/2's ~:d prints by the locale of the stream it writes to (here: given by the option, then changed by set_stream/2)
t5(R) :- lcs_mk(lcs5, [decimal_point(','), thousands_sep('.'), grouping([repeat(3)])]), lcs_mk(lcs5b, [decimal_point('.'), thousands_sep('_'), grouping([3,repeat(2)])]),
    tmp_file(lcs, F), open(F, write, S, [locale(lcs5)]), format(S, "'~:d'.~n", [1234567]), set_stream(S, locale(lcs5b)),
    format(S, "'~:d'.~n", [1234567]), close(S), open(F, read, In), read(In, X1), read(In, X2), close(In), delete_file(F),
    lcs_destroy(lcs5), lcs_destroy(lcs5b), R = [X1, X2].
