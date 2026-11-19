% ORIGINAL: a KNOWN DIFFERENCE of the kernel's TAI1 against swipl 10.1.20: TAI1-TZNAME-CACHE, the reverse order of test_tai_known_tzcache1.pl.
% TZ=Europe/Amsterdam, a FRESH swipl process: swipl answers 'CET'-false-'CET'-false (the first call, the 2038 stamp, fixed the name); the kernel: CET then LMT.
t0(R) :- stamp_date_time(2147483647, date(_,_,_,_,_,_,_,Z2,D2), local), stamp_date_time(-5000000000, date(_,_,_,_,_,_,_,Z1,D1), local), R = Z2-D2-Z1-D1.
