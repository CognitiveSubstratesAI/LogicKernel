% ORIGINAL: a KNOWN DIFFERENCE of the kernel's TAI1 against swipl 10.1.20: TAI1-TZNAME-CACHE (test/core_text/test_tai_format_swipl.jl, third testset).
% swipl's tz_name_as_atom keeps `static atom_t a[2]`: the zone name is the one glibc's tzname[dst] had at the FIRST call in the process, and every localtime_r
% rewrites tzname[]. Run with TZ=Europe/Amsterdam in a FRESH process: swipl answers 'LMT'-false-'LMT'-false (the first stamp's name wins for both),
% the kernel keeps no cache and answers each stamp's own name: LMT then CET. test_tai_known_tzcache2.pl has the reverse order (swipl: CET both).
% the stamp with the historic LMT name first
t0(R) :- stamp_date_time(-5000000000, date(_,_,_,_,_,_,_,Z1,D1), local), stamp_date_time(2147483647, date(_,_,_,_,_,_,_,Z2,D2), local), R = Z1-D1-Z2-D2.
