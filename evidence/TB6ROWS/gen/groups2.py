from groups import PRE
G = []
G.append(dict(key="REEVAL", program=PRE + r"""
:- table rt/1 as incremental.
:- dynamic([rd/1], [incremental(true)]).
rd(1).
rd(2).
rt(X) :- rd(X).
tv(G, N) :- tp(G, T), '$trie_property'(T, value_count(N)).
""", cases=[
 ("f01", r"findall(X, rt(X), L0), msort(L0, L), tv(rt(_), N), R = r(L, N)"),
 ("f02", r"assertz(rd(3)), fcn(rt(_), F), ts(rt(_), S), findall(X, rt(X), L0), msort(L0, L), tv(rt(_), N), fcn(rt(_), F1), ts(rt(_), S1), R = r(F, S, L, N, F1, S1)"),
 ("f03", r"retract(rd(2)), findall(X, rt(X), L0), msort(L0, L), tv(rt(_), N), R = r(L, N)"),
 ("f04", r"tp(rt(_), T), '$idg_thread_summary'(main, Nn, E), '$tbl_reeval_wait'(T, W), R = r(Nn, E, W)"),
 ("f05", r"findall(X, rt(X), L0), msort(L0, L), tv(rt(_), N), R = r(L, N)"),
]))
G.append(dict(key="SINGLE", program=PRE + r"""
:- table s1/1 as incremental.
:- table s2/1 as incremental.
:- table s3/1.
:- dynamic([sd1/1, sd2/1], [incremental(true)]).
sd1(1).
sd2(1).
sd2(2).
s1(X) :- sd1(X).
s2(X) :- sd2(X).
s3(X) :- member(X, [1]).
hascl(G, R) :- tp(G, T), tm_yn('$trie_property'(T, compiled_size(_)), R).
""", cases=[
 ("s01", r"findall(X, s1(X), L1), findall(X, s1(X), L2), hascl(s1(_), C), R = r(L1, L2, C)"),
 ("s02", r"findall(X, s2(X), L0), msort(L0, L1), findall(X, s2(X), L2), msort(L2, L3), hascl(s2(_), C), R = r(L1, L3, C)"),
 ("s03", r"findall(X, s3(X), L1), findall(X, s3(X), L2), hascl(s3(_), C), R = r(L1, L2, C)"),
 ("s04", r"assertz(sd1(9)), findall(X, s1(X), L0), msort(L0, L1), findall(X, s1(X), L2), msort(L2, L3), hascl(s1(_), C), R = r(L1, L3, C)"),
]))
G.append(dict(key="FALSECOUNT", program=PRE + r"""
:- table fp/1 as incremental.
:- dynamic([fd/1], [incremental(true)]).
fd(1).
fp(X) :- fd(X).
""", cases=[
 ("p01", r"findall(X, fp(X), L), tp(fp(_), T), '$idg_set_falsecount'(T, 4294967296), R = L"),
 ("p02", r"tp(fp(_), T), '$idg_set_falsecount'(T, 4294967295), '$idg_falsecount'(T, F), ts(fp(_), S), '$idg_set_falsecount'(T, 0), '$idg_falsecount'(T, F0), ts(fp(_), S0), R = r(F, S, F0, S0)"),
 ("p03", r"tp(fp(_), T), '$idg_set_falsecount'(T, -1), R = ok"),
 ("p04", r"tp(fp(_), T), '$idg_set_falsecount'(T, _), R = ok"),
 ("p05", r"tp(fp(_), T), '$idg_set_falsecount'(T, a), R = ok"),
 ("p06", r"tp(fp(_), T), '$idg_set_falsecount'(T, 4294967297), R = ok"),
 ("p07", r"tp(fp(_), T), '$idg_set_falsecount'(T, 18446744073709551616), R = ok"),
 ("p08", r"tp(fp(_), T), '$idg_falsecount'(T, F), R = F"),
]))
G.append(dict(key="ABOLISH", program=PRE + r"""
:- table ap/1 as incremental.
:- table aq/1 as incremental.
:- table an/1.
:- dynamic([ad/1], [incremental(true)]).
ad(1).
ap(X) :- ad(X).
aq(X) :- ap(X).
an(X) :- member(X, [1, 2]).
summ(r(N, E, B)) :- '$idg_thread_summary'(main, N, E), '$idg_thread_space'(main, B).
alls(r(Sd, Sp, Sq, Sn)) :- ts(ad(_), Sd), ts(ap(_), Sp), ts(aq(_), Sq), ts(an(_), Sn).
""", cases=[
 ("a01", r"findall(X, aq(X), L), findall(X, an(X), L1), summ(S), alls(A), R = r(L, L1, S, A)"),
 ("a02", r"abolish_all_tables, summ(S), alls(A), R = r(S, A)"),
 ("a03", r"findall(X, aq(X), L), summ(S), alls(A), R = r(L, S, A)"),
 ("a04", r"abolish_module_tables(user), summ(S), alls(A), R = r(S, A)"),
 ("a05", r"findall(X, aq(X), L), findall(X, an(X), L1), abolish_table_subgoals(ap(_)), summ(S), alls(A), R = r(L, L1, S, A)"),
 ("a06", r"findall(X, aq(X), L), abolish_nonincremental_tables, summ(S), alls(A), R = r(L, S, A)"),
 ("a07", r"abolish_module_tables(nosuchmodule), summ(S), alls(A), R = r(S, A)"),
 ("a08", r"abolish_table_subgoals(aq(_)), summ(S), alls(A), R = r(S, A)"),
]))
G.append(dict(key="EXPAND", program=PRE + r"""
:- table t1/1 as incremental.
:- table t2/1 as incremental.
:- table t3/1 as incremental.
:- table t4/1 as incremental.
:- table t5/1 as incremental.
:- table t6/1 as incremental.
:- dynamic([xd/1], [incremental(true)]).
xd(1).
t1(X) :- xd(X).
t2(X) :- xd(X).
t3(X) :- xd(X).
t4(X) :- xd(X).
t5(X) :- xd(X).
t6(X) :- xd(X).
summ(r(N, E)) :- '$idg_thread_summary'(main, N, E).
nedge(N) :- tp(xd(_), T), findall(D, '$idg_edge'(T, affected, D), L), length(L, N).
""", cases=[
 ("x01", r"findall(X, t1(X), _), findall(X, t2(X), _), findall(X, t3(X), _), findall(X, t4(X), _), summ(S), nedge(N), R = r(S, N)"),
 ("x02", r"abolish_table_subgoals(t3(_)), summ(S), nedge(N), R = r(S, N)"),
 ("x03", r"findall(X, t5(X), _), summ(S), nedge(N), R = r(S, N)"),
 ("x04", r"findall(X, t6(X), _), summ(S), nedge(N), R = r(S, N)"),
 ("x05", r"assertz(xd(2)), tp(t1(_), T1), tp(t5(_), T5), '$idg_falsecount'(T1, F1), '$idg_falsecount'(T5, F5), ts(t3(_), S3), R = r(F1, F5, S3)"),
]))
