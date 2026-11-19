# TRIEKEYS: the IDG keys of '$trie_property'/2 (pl-trie.c:4326-4345)
from groups import PRE
G = [dict(key="TRIEKEYS", program=PRE + r"""
:- table cp/1 as incremental.
:- table cq/1 as incremental.
:- dynamic([cd/1], [incremental(true)]).
cd(1).
cp(X) :- cd(X).
cq(X) :- cp(X).
tk(G, K, V) :- tp(G, T), K =.. [_, V], ( '$trie_property'(T, K) -> true ; V = none ).
keys(G, r(A, D, S, I, R)) :- tk(G, idg_affected_count(A), _), tk(G, idg_dependent_count(D), _), tk(G, idg_size(S), _), tk(G, invalidated(I), _), tk(G, reevaluated(R), _).
""", cases=[
 ("k01", r"findall(X, cq(X), _), keys(cp(_), K1), keys(cq(_), K2), keys(cd(_), K3), R = r(K1, K2, K3)"),
 ("k02", r"assertz(cd(2)), keys(cp(_), K1), keys(cq(_), K2), keys(cd(_), K3), R = r(K1, K2, K3)"),
 ("k03", r"findall(X, cq(X), _), keys(cp(_), K1), keys(cq(_), K2), keys(cd(_), K3), R = r(K1, K2, K3)"),
])]
