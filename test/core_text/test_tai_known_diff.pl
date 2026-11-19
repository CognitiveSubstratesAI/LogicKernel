% ORIGINAL: the rows of the KNOWN DIFFERENCES between the kernel's TAI1 and swipl 10.1.20 (test/core_text/test_tai_format_swipl.jl, third testset).
% test/core_text/test_tai_known_diff.pl - each `tN(R)` is one row; the kernel's answers are pinned in test_tai_known_diff_kernel.out, swipl's in
% test_tai_known_diff_swipl.out (the same driver prints both). A row where the two differ is a DIVERGES named in src/os/pl-tai.jl and
% docs/architecture.md, with the swipl answer in the comment above it (the answers are swipl's C `int` wrap and a C cast, not the kernel's bug).
%
% TAI1-INT32-WRAP (t0-t2): swipl computes the date fields in C `int` and wraps (gcc); the kernel does not. Values up to 596523 hours agree.
%   (the stamp, a float, is compared as integer(S))
%   t0 swipl: 596523 -> 3094167600, 1073741823 -> 946681200, 1073741824 -> 946684800, 2147483647 -> 946681200, -2147483648 -> 946684800
%   t1 swipl: year -2147483647 -> -67768100536348800, -2147483648 -> -67768100567971200, 2147483647 -> 67767976201996800
%   t2 swipl: date(2020,1,1) -> 3, date(-2147483648,-1,12) -> 1, date(-2147483648,1,1) -> 2
% TAI1-NAN-CAST (t3): stamp_date_time(NaN, D, 'UTC') gives year 292277026596 on both; swipl's seconds are the garbage bits of a C cast of NaN
%   (undefined, not pinned here): only the year and the zone name are compared.
kd_res(G, R) :- catch(( G -> R = true ; R = false ), error(E, _), R = error(E)).
% TAI1-INT32-WRAP
t0(R) :- member(H, [596523, 1073741823, 1073741824, 2147483647, -2147483648]),
    kd_res(date_time_stamp(date(2000,1,1,H,0,0,0,-,-), S), R0), ( R0 == true -> I is integer(S), R = H-I ; R = H-R0 ).
t1(R) :- member(Y, [-2147483647, -2147483648, 2147483647]),
    kd_res(date_time_stamp(date(Y,1,1,0,0,0,0,-,-), S), R0), ( R0 == true -> I is integer(S), R = Y-I ; R = Y-R0 ).
t2(R) :- member(D, [date(2020,1,1), date(-2147483648,-1,12), date(-2147483648,1,1)]),
    kd_res(day_of_the_week(D, W), R0), ( R0 == true -> R = D-W ; R = D-R0 ).
% TAI1-NAN-CAST: only the year agrees
t3(R) :- X is nan, stamp_date_time(X, date(Y,_,_,_,_,_,_,Z,_), 'UTC'), R = Y-Z.
