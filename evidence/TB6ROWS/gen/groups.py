# group definitions for the TB6 rows: key, program, cases [(id, goal)]
PRE = r"""
tm_yn(G, R) :- ( call(G) -> R = yes ; R = no ).
tp(G, T) :- '$tbl_existing_variant_table'(0, user:G, T, _, _).
ts(G, S) :- ( tp(G, T) -> '$tbl_table_status'(T, S) ; S = none ).
fcn(G, F) :- ( tp(G, T) -> '$idg_falsecount'(T, F) ; F = none ).
dirs(G, Dir, L) :- tp(G, T), findall(S, ('$idg_edge'(T, Dir, D), '$tbl_table_status'(D, S)), L).
"""
G = []
G.append(dict(key="CHAIN", program=PRE + r"""
:- table cp/1 as incremental.
:- table cq/1 as incremental.
:- dynamic([cd/1], [incremental(true)]).
cd(1).
cp(X) :- cd(X).
cq(X) :- cp(X).
""", cases=[
 ("c01", r"findall(X, cq(X), L), R = L"),
 ("c02", r"tp(cp(_), T), findall(Dir-S, ('$idg_edge'(T, Dir, D), '$tbl_table_status'(D, S)), R)"),
 ("c03", r"dirs(cq(_), affected, A1), dirs(cq(_), dependent, D1), dirs(cp(_), affected, A2), dirs(cp(_), dependent, D2), dirs(cd(_), affected, A3), dirs(cd(_), dependent, D3), R = r(A1, D1, A2, D2, A3, D3)"),
 ("c04", r"'$idg_thread_summary'(main, N, E), '$idg_thread_space'(main, B), R = r(N, E, B)"),
 ("c05", r"assertz(cd(2)), fcn(cd(_), F3), fcn(cp(_), F2), fcn(cq(_), F1), ts(cd(_), S3), ts(cp(_), S2), ts(cq(_), S1), R = r(f(F3, F2, F1), s(S3, S2, S1))"),
 ("c06", r"tp(cq(_), T), findall(S, '$idg_false_edge'(T, _, S), L1), tp(cp(_), T2), findall(S, '$idg_false_edge'(T2, _, S), L2), R = r(L1, L2)"),
 ("c07", r"findall(X, cq(X), L0), msort(L0, L), fcn(cp(_), F2), fcn(cq(_), F1), ts(cp(_), S2), ts(cq(_), S1), R = r(L, f(F2, F1), s(S2, S1))"),
 ("c08", r"retract(cd(1)), findall(X, cq(X), L0), msort(L0, L), fcn(cq(_), F1), ts(cq(_), S1), R = r(L, F1, S1)"),
 ("c09", r"'$idg_thread_summary'(main, N, E), '$idg_thread_space'(main, B), R = r(N, E, B)"),
]))
