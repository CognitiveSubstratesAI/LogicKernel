
hello_out :- write(hello).
nested_out :- format("<~w>", [inner]).
col_out :- write(abc), format("~t~w~8|", [x]).
nl_out :- write(a), nl, write(b).
thrower :- throw(boom).
failer :- fail.
tabs(0, S, S) :- !.
tabs(N, S0, S) :- atom_concat(S0, '~t', S1), N1 is N-1, tabs(N1, S1, S).
t_f100(R) :- catch((format(atom(R), "~t~w~10|", ['Ã©'])), error(SsuE, _), R = raised(SsuE)).
t_f101(R) :- catch((format(atom(R), "~t~s~t~10|~a", [[97,98], cd])), error(SsuE, _), R = raised(SsuE)).
t_f102(R) :- catch((format(atom(R), "~s~t~10|~a", [[97,98], cd])), error(SsuE, _), R = raised(SsuE)).
t_f103(R) :- catch((format(atom(R), "~1s|~5s|~0s|~3s", [[104,105],[104,105],[104,105],[104,105,106,107]])), error(SsuE, _), R = raised(SsuE)).
t_f104(R) :- catch((format(atom(R), "~h|~h|~h|~h", [1.0e5, 1.0e-5, 123456.0, 1.0e6])), error(SsuE, _), R = raised(SsuE)).
t_f105(R) :- catch((format(atom(R), "~g|~2g|~g|~g", [0.123456789, 123.456, 1234.5678, 1.0e-4])), error(SsuE, _), R = raised(SsuE)).
t_f106(R) :- catch((with_output_to(atom(R), (open('/dev/null', write, S), format(S, "a~@b", [hello_out]), write(x), format(S, "~w", [y]), write(z), close(S)))), error(SsuE, _), R = raised(SsuE)).
