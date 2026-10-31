:- assertz(mwfs:wq(1)).
:- mwf:'$import'(mwfs:wq/1, weak).
mwf:wq(9).
t_f5(R) :- findall(X, mwf:wq(X), R).
