% ORIGINAL: the rows of test/files/test_tmp_files_swipl.jl - no swipl-devel counterpart.
% test/files/test_tmp_files_swipl.pl - W12-TMPFILES's rows (os/pl-os.c TemporaryFile, DeleteTemporaryFile; os/pl-files.c tmp_file/2,
% `$tmp_file_stream`/4, delete_file/1 on a temporary name). Each `tN(R)` is one row; test_tmp_files_swipl.out holds swipl 10.1.20's
% answers (evidence/W12-TMPFILES/run_rows.sh: two runs, LC_ALL=C, byte-identical). A temporary name differs per run (the process
% number, the counter), so a row answers by SHAPE: `shape/4` takes a name apart as <tmp_dir>/swipl_<Id>[_]<pid>_<n>[.<Ext>] and
% answers the counter, and a row answers `ok` or `bad`, never the name. The files the rows make live in the temporary directory
% (the flag tmp_dir) or, for t14, in lk_tmpf_dir of the working directory; every row removes what it makes, except the last.
% UNVERIFIED on the kernel: gate decides
app([], L, L).
app([H|T], L, [H|R]) :- app(T, L, R).
span([D|T], [D|Ds], R) :- D >= 48, D =< 57, !, span(T, Ds, R).
span(R, [], R).
% /swipl_ = 47,115,119,105,112,108,95; `_` = 95; `.` = 46
shape(N, Id, Ext, Cnt) :-
    current_prolog_flag(tmp_dir, D), current_prolog_flag(pid, Pid),
    atom_codes(N, Ns), atom_codes(D, Ds), atom_codes(Id, Is), atom_codes(Ext, Es), number_codes(Pid, Ps),
    app(Ds, [47,115,119,105,112,108,95|Is], P1),
    ( Is == [] -> P2 = P1 ; app(P1, [95], P2) ),
    app(P2, Ps, P3), app(P3, [95|Rest], Ns),
    span(Rest, Cs, Tail), Cs \== [],
    ( Es == [] -> Tail == [] ; Tail = [46|Es] ),
    number_codes(Cnt, Cs).
yes(G, R) :- ( catch(G, _, fail) -> R = ok ; R = bad ).
err(G, R) :- catch(( G -> R = no_error ; R = failed ), error(E, _), R = E).
rep(0, []) :- !.
rep(N, [97|T]) :- N1 is N-1, rep(N1, T).
mk(N) :- open(N, write, S), write(S, x), close(S).
% --- tmp_file/2: the name
t0(R) :- yes(( tmp_file(base, N), shape(N, base, '', _) ), R).
t1(R) :- tmp_file(base, N), ( exists_file(N) -> A = file ; A = nofile ), ( exists_directory(N) -> B = dir ; B = nodir ), R = r(A, B).
t2(R) :- yes(( tmp_file(base, N1), tmp_file(base, N2), N1 \== N2, shape(N1, base, '', C1), shape(N2, base, '', C2), C2 =:= C1+1 ), R).
t3(R) :- yes(( tmp_file('', N), shape(N, '', '', _) ), R).
t4(R) :- yes(( tmp_file("str", N), shape(N, str, '', _) ), R).
t5(R) :- yes(( tmp_file(12, N), shape(N, '12', '', _) ), R).
t6(R) :- yes(( tmp_file([97,98], N), shape(N, ab, '', _) ), R).
t7(R) :- yes(( tmp_file(base, N), atom(N) ), R).
% --- tmp_file/2: errors and failure
t8(R) :- err(tmp_file(_, _), R).
t9(R) :- err(tmp_file(f(x), _), R).
t10(R) :- err(tmp_file(base, foo), R).
t11(R) :- rep(5000, L), err(tmp_file(L, _), R).
% --- delete_file/1 on a temporary name (the Id lk_del: the test looks that none of these names is left in the registry)
t12(R) :- tmp_file(lk_del, N),
    catch(( delete_file(N), R = deleted ), error(existence_error(file, X), _), ( X == N -> R = existence_error_of_name ; R = other )).
t13(R) :- tmp_file(lk_del, N), mk(N), ( exists_file(N) -> A = made ; A = notmade ), ( delete_file(N) -> B = deleted ; B = notdeleted ),
    ( exists_file(N) -> C = still ; C = gone ),
    catch(( delete_file(N), D = again ), error(existence_error(file, X), _), ( X == N -> D = existence_error_of_name ; D = other )),
    R = r(A, B, C, D).
t14(R) :- make_directory(lk_tmpf_dir), current_prolog_flag(tmp_dir, Old), set_prolog_flag(tmp_dir, lk_tmpf_dir),
    ( yes(( tmp_file(base, N), shape(N, base, '', _) ), A), '$tmp_file_stream'(txt, utf8, F, S), close(S),
      yes(( shape(F, '', txt, _), exists_file(F) ), B), delete_file(F)
    -> true ; A = bad, B = bad ),
    set_prolog_flag(tmp_dir, Old), delete_directory(lk_tmpf_dir), R = r(A, B).
% --- an invalid tmp_dir: the warning (stderr) and the error; the formal term only (the errno text is whatever the warning left)
t15(R) :- current_prolog_flag(tmp_dir, Old), set_prolog_flag(tmp_dir, lk_tmpf_nodir),
    err(tmp_file(base, _), R1), err('$tmp_file_stream'(txt, utf8, _, _), R2),
    set_prolog_flag(tmp_dir, Old), R = r(R1, R2).
% --- the longest name: PATH_MAX (4096) bytes with the terminating NUL, so 4095 characters are made and 4096 are refused. The counter
% comes before the check, and its digits are part of the length: a probe call tells the counter the next call takes.
len_for(Total, Id) :-
    tmp_file(probe, N0), shape(N0, probe, '', C0), C1 is C0+1, number_codes(C1, Cs), length(Cs, CL),
    current_prolog_flag(tmp_dir, D), atom_length(D, DL), current_prolog_flag(pid, P), number_codes(P, Ps), length(Ps, PL),
    Id is Total - (DL + 7 + 1 + PL + 1 + CL).
t16(R) :- len_for(4095, L1), rep(L1, B1), tmp_file(B1, N), atom_length(N, Len), ( Len =:= 4095 -> R1 = ok ; R1 = bad(Len) ),
    len_for(4096, L2), rep(L2, B2), err(tmp_file(B2, _), R2), R = r(R1, R2).
% --- $tmp_file_stream/4
t20(R) :- '$tmp_file_stream'(txt, utf8, F, S),
    yes(shape(F, '', txt, _), A), ( exists_file(F) -> B = exists ; B = missing ),
    yes(stream_property(S, mode(write)), C), yes(stream_property(S, type(text)), D), yes(stream_property(S, encoding(utf8)), E),
    ( stream_property(S, file_name(_)) -> G = has_file_name ; G = no_file_name ),
    write(S, hello), close(S), ( size_file(F, Z) -> true ; Z = nosize ),
    ( delete_file(F) -> H = deleted ; H = notdeleted ), ( exists_file(F) -> I = still ; I = gone ),
    R = r(A, B, C, D, E, G, Z, H, I).
t21(R) :- '$tmp_file_stream'(txt, binary, F, S),
    yes(stream_property(S, mode(write)), A), yes(stream_property(S, type(binary)), B), yes(stream_property(S, encoding(octet)), C),
    close(S), delete_file(F), R = r(A, B, C).
t22(R) :- '$tmp_file_stream'('', utf8, F, S), yes(shape(F, '', '', _), A), close(S), delete_file(F), R = A.
t23(R) :- '$tmp_file_stream'("s", iso_latin_1, F, S), yes(shape(F, '', s, _), A),
    yes(stream_property(S, encoding(iso_latin_1)), B), close(S), delete_file(F), R = r(A, B).
t24(R) :- enc_row([ascii, text, utf8, iso_latin_1, octet, unicode_be, unicode_le], R).
enc_row([], []).
enc_row([E|Es], [E-P|R]) :- '$tmp_file_stream'(txt, E, F, S), ( stream_property(S, encoding(P)) -> true ; P = none ), close(S), delete_file(F), enc_row(Es, R).
t25(R) :- yes(( '$tmp_file_stream'(a, utf8, F1, S1), '$tmp_file_stream'(a, utf8, F2, S2), tmp_file(a, N3),
       shape(F1, '', a, C1), shape(F2, '', a, C2), shape(N3, a, '', C3), C2 =:= C1+1, C3 =:= C2+1,
       close(S1), close(S2), delete_file(F1), delete_file(F2) ), R).
t26(R) :- err('$tmp_file_stream'(txt, foo, _, _), R).
t27(R) :- err('$tmp_file_stream'(txt, _, _, _), R).
t28(R) :- err('$tmp_file_stream'(_, utf8, _, _), R).
t29(R) :- err('$tmp_file_stream'(12, utf8, _, _), R).
t30(R) :- err('$tmp_file_stream'(txt, 12, _, _), R).
t31(R) :- catch('$tmp_file_stream'(txt, utf8, foo, _), error(E, context(_, M)), true), R = r(E, M).
% --- the last row: leaves a file at a temporary name that open/3 made, and a file `$tmp_file_stream`/4 made; the halt removes both
t99(R) :- tmp_file(lk_left, N), mk(N), '$tmp_file_stream'(left, utf8, _, S), close(S), R = left.
