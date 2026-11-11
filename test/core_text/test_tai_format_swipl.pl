% ORIGINAL: the rows of test/core_text/test_tai_format_swipl.jl (their predicates, format_time/3 and format_time/4, are pl-tai.c's).
% test/core_text/test_tai_format_swipl.pl - TAI1's format_time rows. Each `tN(R)` is one row; test_tai_format_swipl.out holds swipl
% 10.1.20's answers to them, as the test's driver prints them (`ok`, then one line per row: its name and every solution).
% The times are date/9 terms with an explicit offset and zone name (the host's zone is never read) or float stamps read only by
% %s and %f; the locale-dependent %c, %x and %X are not used (the test machine's LANG decides them).
tf_dates([date(2020,1,2,3,4,5.5,0,'UTC',-), date(2021,1,3,23,59,59.0,0,'UTC',-), date(2024,12,30,0,0,0.0,3600,'UTC',-),
          date(2000,2,29,12,30,45.123456,-19800,'IST',-), date(2016,1,1,13,5,9.0,0,'UTC',-),
          date(2018,12,31,0,0,0.0,0,'UTC',-), date(1999,12,31,12,0,0.0,0,'UTC',-), date(2015,6,7,0,15,30.75,7200,'CEST',true)]).
tf_res(G, R) :- catch(( G -> R = true ; R = false ), error(E, _), R = error(E)).
tf_run(F, D, R) :- tf_res(format_time(atom(R0), F, D), R1), ( R1 == true -> R = R0 ; R = R1 ).
tf_family(Fs, R) :- tf_dates(Ds), member(F, Fs), nth1(I, Ds, D), tf_run(F, D, O), R = F-I-O.
% the date family
t0(R) :- tf_family(['%a', '%A', '%b', '%B', '%d', '%D', '%e', '%F', '%h', '%j', '%m'], R).
% weekdays and week numbers
t1(R) :- tf_family(['%C', '%y', '%Y', '%u', '%U', '%w', '%W', '%g', '%G', '%V'], R).
% the time family
t2(R) :- tf_family(['%H', '%I', '%k', '%l', '%M', '%S', '%p', '%P', '%r', '%R', '%T'], R).
% the zone family and the stamp
t3(R) :- tf_family(['%z', '%:z', '%Oz', '%Z', '%+', '%s', '%f', '%3f', '%0f', '%9f', '%12f', '%1f'], R).
% literal text, a mix, and the format as a string and a code list
t4(R) :- tf_dates(Ds), member(F, ['', abc, 'a%%b', '%Y-%m-%dT%H:%M:%S%:z', "%Y/%m", [0'%, 0'Y, 0'-, 0'%, 0'm], '%n', '%t',
                                    '100%%', 'x%', '%Y%', [0'a, 0, 0'b]]),
    nth1(I, Ds, D), I =< 2, tf_run(F, D, O), ( F = [_|_] -> L = codes ; L = F ), R = L-I-O.
% format_time/4: posix
t5(R) :- tf_dates(Ds), member(F, ['%a', '%A', '%b', '%B', '%h', '%d %b %Y', '%Y']), nth1(I, Ds, D), I =< 4,
    tf_res(format_time(atom(R0), F, D, posix), R1), ( R1 == true -> R2 = R0 ; R2 = R1 ), R = F-I-R2.
% the locale argument
t6(R) :- member(L, [foo, posi, "posix", 1, _, 'POSIX']), tf_dates([D|_]),
    tf_res(format_time(atom(_), '%Y', D, L), R0), ( var(L) -> L1 = var ; L1 = L ), R = L1-R0.
% directives that are errors
t7(R) :- tf_dates([D|_]), member(F, ['%E', '%Q', '%', '%O', '%Ez', '%5', '%q', '%:', '%1', '%12', '%i', '%J', '%v', '%L', '%N', '%Oq', '%:q', '%O%Y']),
    tf_run(F, D, O), R = F-O.
% %C needs a year of 0..9999
t8(R) :- member(Y, [-1, 0, 99, 100, 1900, 9999, 10000, 12345]), tf_run('%C', date(Y,1,1,0,0,0.0,0,'UTC',-), O), R = Y-O.
% the time argument
t9(R) :- member(T, [foo, f(1), "x", [], 'UTC', date(1,2,3,4)]), tf_res(format_time(atom(_), '%Y', T), R0), R = T-R0.
t10(R) :- tf_res(format_time(atom(_), '%Y', _), R).
% the format argument
t11(R) :- tf_dates([D|_]), member(F, [123, 1.5, f(x), [a], [0'%, a], _]),
    tf_res(format_time(atom(_), F, D), R0), ( var(F) -> F1 = var ; F1 = F ), R = F1-R0.
% the output specification: atom, string, codes, chars, and an error
t12(R) :- tf_dates([D|_]),
    member(O-L, [atom(_)-atom, string(_)-string, codes(_)-codes, chars(_)-chars, atom(abc)-atom_abc, atom('2020')-atom_2020,
                 foo-foo, _-var]),
    tf_res(format_time(O, '%Y', D), R0), R = L-R0.
% the stamp as a float: only %s and %f read it (no zone)
t13(R) :- Ss = [0, 1700000000.5, 1.25, -1.5, 86400.123456789, 1700000000, 59.9999999], nth1(I, Ss, S),
    member(F, ['%s', '%f', '%3f', '%9f', '%0f', '%1f', '%s.%3f']), tf_res(format_time(atom(A), F, S), R0),
    ( R0 == true -> R1 = A ; R1 = R0 ), R = I-F-R1.
% a date/3: no offset given, so the host zone decides - only %Y %m %d are read
t14(R) :- member(D, [date(2020,1,2), date(1999,12,31), date(2000,2,29)]), tf_run('%Y-%m-%d', D, O), R = D-O.
% the date/9 argument errors reach format_time too
t15(R) :- member(D, [date(a,1,1,0,0,0,0,-,-), date(2020,1,1,0,0,x,0,'UTC',-), date(2020,1,1,0,0,0,0,'UTC',maybe)]),
    tf_res(format_time(atom(_), '%Y', D), R0), R = D-R0.
