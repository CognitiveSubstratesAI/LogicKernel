% ORIGINAL: the rows of test/core_text/test_tai_swipl.jl (their predicates, stamp_date_time/3 and date_time_stamp/2, are pl-tai.c's).
% test/core_text/test_tai_swipl.pl - TAI1's rows. Each `tN(R)` is one row; test_tai_swipl.out holds swipl 10.1.20's answers to
% them, as the test's driver prints them (`ok`, then one line per row: its name and every solution). Only fixed stamps and the
% zones 'UTC' or a numeric offset are used (the host's local zone is never read): the answers are the same on every machine.
% A float answer that can be large is split into its integer part and its fraction, so no float text depends on the printer.
tai_res(G, R) :- catch(( G -> R = true ; R = false ), error(E, _), R = error(E)).
tai_split(S, I-F-K) :- I is truncate(S), F is S - I, ( float(S) -> K = float ; integer(S) -> K = integer ; K = other ).
% stamp_date_time/3 in 'UTC': the date/9 term
t0(R) :- member(S, [0, 3600, 86400, 1.5, -1.5, -86400, 951782400, 1700000000, 1700000000.25, 4102444800, 0.0, 59.75]),
    stamp_date_time(S, D, 'UTC'), R = S-D.
% a numeric zone offset (seconds west of Greenwich): the date is the stamp's wall clock there
t1(R) :- member(Off, [0, 3600, -19800, 7200, -43200, 45]), stamp_date_time(1700000000.5, D, Off), R = Off-D.
% a stamp near a day and a year boundary, three zones
t2(R) :- member(S, [86399.5, 86400, 1704067199, 1704067200, 1709164800, 1709251200]), member(Z, ['UTC', 3600, -3600]),
    stamp_date_time(S, D, Z), R = S-Z-D.
% the zone as a string and a text: only the atoms 'UTC' and local, a number or a variable name a zone
t3(R) :- member(Z, [foo, "UTC", utc, 'GMT', [], f(x), 1.5, abc, -]), tai_res(stamp_date_time(0, _, Z), R0), R = Z-R0.
% the stamp: a number only
t4(R) :- member(S, [abc, "1", f(x), [], 'UTC']), tai_res(stamp_date_time(S, _, 'UTC'), R0), R = S-R0.
t5(R) :- tai_res(stamp_date_time(_, _, 'UTC'), R).
t6(R) :- tai_res(stamp_date_time(0, _, _), R).
% the date bound: it is unified with the answer
t7(R) :- member(D, [date(1970,1,1,0,0,0.0,0,'UTC',-), date(1970,1,1,0,0,0,0,'UTC',-), date(1970,1,1,_,_,_,_,_,_),
                    date(1971,1,1,0,0,0.0,0,'UTC',-), foo, date(1,2,3), date(1970,1,1,0,0,0.0,0,'UTC',true)]),
    tai_res(stamp_date_time(0, D, 'UTC'), R0), R = D-R0.
% a stamp far out of range (integers only: the float-to-integer cast of a huge float is the C compiler's)
t8(R) :- member(S, [9223372036854775807, 4611686018427387904, 1000000000000000000]),
    tai_res(( stamp_date_time(S, D, 'UTC'), D = date(Y,_,_,_,_,_,_,_,_) ), R0), ( R0 == true -> R = S-Y ; R = S-R0 ).
% date_time_stamp/2: the stamp; the answer is a float
t9(R) :- member(D, [date(2020,1,2,3,4,5.5,0,-,-), date(1970,1,1,0,0,0,0,-,-), date(2000,2,29,12,0,0.0,0,'UTC',-),
                    date(2020,1,2,3,4,5,3600,-,-), date(2020,1,2,3,4,5,-19800,-,-), date(1969,12,31,23,59,59,0,-,-),
                    date(2020,1,2,3,4,5,0,'UTC',-), date(2020,1,2,3,4,5,0,-,false), date(2020,1,2,3,4,5,0,-,true)]),
    date_time_stamp(D, S), tai_split(S, X), R = D-X.
% the fields are normalised: a month, day, hour, minute or second out of range carries over
t10(R) :- member(D, [date(2020,13,1,0,0,0,0,-,-), date(2020,0,1,0,0,0,0,-,-), date(2020,1,32,0,0,0,0,-,-),
                     date(2020,1,0,0,0,0,0,-,-), date(2020,1,1,25,61,61,0,-,-), date(2020,1,1,-1,0,0,0,-,-),
                     date(2020,25,1,0,0,0,0,-,-), date(2021,-1,1,0,0,0,0,-,-), date(2020,3,1,0,0,-1,0,-,-),
                     date(2020,1,1,0,0,86400.5,0,-,-)]),
    date_time_stamp(D, S), tai_split(S, X), R = D-X.
% a variable field, where the offset is given: the defaults
t11(R) :- member(D, [date(2020,1,2,_,_,_,0,_,_), date(2020,1,2,3,_,_,0,_,_), date(2020,1,2,3,4,_,0,_,_),
                     date(2020,1,2,3,4,5,0,_,_), date(2020,1,2,3,4,5.25,0,_,-), date(2020,1,2,3,4,5,0,'UTC',_),
                     date(2020,1,_,_,_,_,0,_,_), date(2020,_,_,_,_,_,0,_,_)]),
    tai_res(( date_time_stamp(D, S), tai_split(S, X) ), R0), ( R0 == true -> R = D-X ; R = D-R0 ).
% the answer bound: compared
t12(R) :- member(S, [0, 0.0, 1577934245.0, 1577934245, 1577934246.0]), tai_res(date_time_stamp(date(2020,1,2,3,4,5,0,-,-), S), R0), R = S-R0.
% the argument errors
t13(R) :- member(D, [foo(1), foo, 12, "x", date(a,1,1,0,0,0,0,-,-), date(2020,b,1,0,0,0,0,-,-), date(2020,1,c,0,0,0,0,-,-),
                     date(2020,1,1,d,0,0,0,-,-), date(2020,1,1,0,e,0,0,-,-), date(2020,1,1,0,0,f,0,-,-),
                     date(2020,1,1,0,0,0,g,-,-), date(2020,1,1,0,0,0,0,h(1),-), date(2020,1,1,0,0,0,0,-,maybe),
                     date(2020,1,1,0,0,0,0,-,1), date(2020,1,1,0,0,0,1.5,-,-), date(2020.5,1,1,0,0,0,0,-,-),
                     date(2020,1,1,0,0,0,0,"UTC",-)]),
    tai_res(date_time_stamp(D, _), R0), R = D-R0.
t14(R) :- tai_res(date_time_stamp(_, _), R).
% a round trip: stamp -> date -> stamp, in UTC, whole seconds and a fraction
t15(R) :- member(S, [0, 1700000000, 1700000000.5, -86400, 951782400.25]), stamp_date_time(S, D, 'UTC'),
    date_time_stamp(D, S2), tai_split(S2, X), R = S-X.
% the value of the second field of a stamp with a fraction, and the zone term of the answer
t16(R) :- stamp_date_time(12345.678, date(Y,Mo,D,H,Mi,Sec,Off,TZ,DST), 'UTC'), I is truncate(Sec), F is Sec - I,
    R = [Y,Mo,D,H,Mi,I,Off,TZ,DST]-F.
t17(R) :- stamp_date_time(12345.678, date(_,_,_,_,_,_,Off,TZ,DST), 7200), R = Off-TZ-DST.
% a negative FRACTIONAL second: its fraction is folded into the previous second (the integer second -1 of t10 has no fraction to fold)
t18(R) :- member(D, [date(2020,3,1,0,0,-0.5,0,-,-), date(2020,3,1,0,0,-1.25,0,-,-), date(2020,3,1,0,0,-59.75,0,-,-), date(2020,3,1,0,0,0.5,0,-,-)]),
    date_time_stamp(D, S), tai_split(S, X), R = D-X.
