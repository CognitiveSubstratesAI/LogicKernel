% ORIGINAL: the rows of test/core_text/test_tai_format_swipl.jl (their predicates, format_time/3 and format_time/4, are pl-tai.c's).
% test/core_text/test_tai_format_tz_swipl.pl - TAI1's format_time rows that read the HOST: the zone (TZ is fixed by the test's driver to
% the POSIX rule CET-1CEST,M3.5.0/2,M10.5.0/3 on both sides: no zoneinfo file is read), the locale of %c %x %X %p %P and the
% names of %a %A %b %B %h (a row switches LC_TIME to C and restores it), the output sinks and the 32-bit corners of C's int.
% test_tai_format_tz_swipl.out holds swipl 10.1.20's answers (the driver prints `ok`, then one line per row: its name and every solution).
tz_stamps([0, 1700000000, 1720000000, -1.5, 1700000000.75, 1711846799, 1711846800, 1729990799, 1729990800]).
tz_dates([date(2024,7,3,11,46,40.0,_,-,-), date(2024,1,3,11,46,40.0,_,-,-), date(2024,7,3,11,46,40.0,_,-,true),
          date(2024,7,3,11,46,40.0,_,-,false), date(2024,7,3,11,46,40.0,-7200,-,-), date(2024,7,3,11,46,40.0,-7200,'CEST',true),
          date(2024,7,3,11,46,40.0,0,-,-), date(2024,7,3), date(2024,13,35,25,61,61.5,_,-,-), date(2024,7,3,11,46,40.5,_,-,-)]).
tz_res(G, R) :- catch(( G -> R = true ; R = false ), error(E, _), R = error(E)).
tz_run(F, D, R) :- tz_res(format_time(atom(R0), F, D), R1), ( R1 == true -> R = R0 ; R = R1 ).
tz_run4(F, D, R) :- tz_res(format_time(atom(R0), F, D, posix), R1), ( R1 == true -> R = R0 ; R = R1 ).
tz_family(Fs, Ds, R) :- member(F, Fs), nth1(I, Ds, D), tz_run(F, D, O), R = F-I-O.
% LC_TIME is C for the rows that call this (swipl and the kernel start in the environment's locale)
tz_in_c(Goal, Rs) :- setlocale(time, Old, 'C'), findall(R, call(Goal, R), Rs), setlocale(time, _, Old).
% the zone family over stamps
t0(R) :- tz_stamps(Ds), tz_family(['%z', '%:z', '%Oz', '%Z', '%H:%M:%S', '%Y-%m-%dT%H:%M:%S%:z'], Ds, R).
% the stamp family and the day numbers
t1(R) :- tz_stamps(Ds), tz_family(['%s', '%f', '%3f', '%+', '%j %u %U %W %V %G', '%e|%k|%l'], Ds, R).
% the host-locale forms in the C locale: %c %x %X %p %P and the names, format_time/3 and the posix format_time/4
t2a(R) :- tz_stamps(Ds), tz_family(['%c', '%x', '%X', '%p', '%P', '%a', '%A', '%b', '%B', '%r'], Ds, R).
t2(R) :- tz_in_c(t2a, Rs), member(R, Rs).
t3a(R) :- tz_stamps(Ds), member(F, ['%c', '%x', '%X', '%p', '%P', '%a', '%A', '%b', '%B', '%h', '%r']), nth1(I, Ds, D),
    tz_run4(F, D, O), R = F-I-O.
t3(R) :- tz_in_c(t3a, Rs), member(R, Rs).
% a date/9 or date/3 term that leaves the offset, zone or DST to the host
t4(R) :- tz_dates(Ds), tz_family(['%Y-%m-%d %H:%M:%S %z %Z', '%j %u %U %W %V %G %s', '%f %+'], Ds, R).
% far years: localtime_r's answers, %C of a year outside 0..9999
t5(R) :- Ss = [1e11, 253402300800, -62135596800, -1e11, 1e17, 67768036191676799, 67768036191676800], member(F, ['%Y', '%C', '%y', '%G', '%V', '%s']), nth1(I, Ss, S),
    tz_run(F, S, O), R = F-I-O.
% the year is a C int: it wraps at 32 bits (observed on the pinned build)
t6(R) :- member(D, [date(2147483647,12,31,0,0,0.0,0,'UTC',-), date(2147483647,1,1,0,0,0.0,0,'UTC',-),
                    date(2147483646,12,31,0,0,0.0,0,'UTC',-), date(-2147481748,1,1,0,0,0.0,0,'UTC',-),
                    date(-2147481747,1,1,0,0,0.0,0,'UTC',-)]),
    member(F, ['%G', '%g', '%V', '%Y', '%y', '%j', '%u', '%U', '%W', '%C']), tz_run(F, D, O), R = D-F-O.
% the offset is a long: %z and %:z of the extreme and the round values
t7(R) :- member(Off, [-2147483648, 2147483647, 3600000, -3600000, 45296, -45296, 59, -59, 0, 1, -1, 86399]),
    tz_run('%z|%:z', date(2020,1,1,0,0,0.0,Off,'UTC',-), O), R = Off-O.
% the output sinks
t8(R) :- tz_dates([D|_]),
    member(g(G, L), [g(with_output_to(string(S), format_time(current_output, '%Y-%m-%d', D)), [S]),
                     g(with_output_to(string(S), ( current_output(O), format_time(O, '%H:%M', D) )), [S]),
                     g(with_output_to(string(S), tz_res(format_time(current_output, 'ab%Qcd', D), _)), [S]),
                     g(with_output_to(string(S), tz_res(format_time(current_output, 'ab%Cx', date(10000,1,1,0,0,0.0,0,'UTC',-)), _)), [S]),
                     g(with_output_to(codes(S), format_time(current_output, '%d', D)), [S]),
                     g(format_time(string(S), '', D), [S]),
                     g(format_time(codes(S, T), '%Y', D), [S, T]),
                     g(format_time(chars(S, T), '%m', D), [S, T]),
                     g(format_time(string(S), '%Y', D), [S]),
                     g(format_time(atom(S), 'é%Y→日本', D), [S]),
                     g(format_time(string(S), '\x1F600\%d', D), [S]),
                     g(format_time(codes(S), 'é', D), [S])]),
    tz_res(G, R0), R = L-R0.
% a sink that cannot take the output, and an error in the middle of the format leaves no answer
t9(R) :- tz_dates([D|_]),
    member(O-L, [user_input-user_input, nostream-nostream, 42-int, f(x)-compound, "str"-string, [a]-list, '$stream'-atom_stream]),
    tz_res(format_time(O, '%Y', D), R0), R = L-R0.
t10(R) :- tz_dates([D|_]), tz_res(format_time(atom(A), 'ab%Qcd', D), R0), ( var(A) -> R = unbound-R0 ; R = bound(A)-R0 ).
% a non-ASCII zone name and literal text; %Z of a date that gives its name, and of the host's
t11(R) :- member(D-F, [date(2020,1,1,0,0,0.0,0,'ÜTC',-)-'%Z', date(2020,1,1,0,0,0.0,0,'日本',-)-'%Z|%z', date(2020,1,1,0,0,0.0,0,'',-)-'[%Z]',
                       date(2020,1,1,0,0,0.0,0,'UTC',-)-'日本%Y', date(2020,6,1,0,0,0.0,_,-,-)-'%Z', date(2020,1,1,0,0,0.0,_,-,-)-'%Z']),
    tz_run(F, D, O), R = D-F-O.
% the ISO year of the days around New Year, where glibc's __isleap of the neighbouring year decides (centuries, 4-year rule)
t12(R) :- member(Y-M-Dy, [2101-1-1, 2101-1-2, 1800-12-29, 1800-12-31, 2200-12-30, 1502-12-31, 1508-12-30, 1521-1-1, 1510-1-2, 1701-1-1,
                          2020-12-31, 2021-1-3, 2024-12-30, 2026-1-1, 2000-12-31, 2001-1-1, 1900-12-31, 1901-1-1]),
    member(F, ['%G %V', '%g']), tz_run(F, date(Y,M,Dy,0,0,0.0,0,'UTC',-), O), R = Y-M-Dy-F-O.
% the wrap of tm_year + 1900 itself: local year 2147484000 has tm_year 2147482100 (an int, no wrap), +1900 leaves 32 bits and wraps to -2147483296
% (t5's stamps have tm_year 2147483648 = -2147483648 already wrapped, so the sum never leaves the range there)
t13(R) :- member(F, ['%Y', '%C', '%y', '%G']), tz_run(F, 67767987355891200, O), R = F-O.
% the host's zone name (a stamp: tb.tzname is unset, so the name is tz_name_as_atom's) takes the same token break as a date's: 'x%Zy' is 'x CETy' (T13)
t14(R) :- tz_stamps(Ds), tz_family(['x%Zy', '%d%Z', '%Z%Z', '-%Z'], Ds, R).
