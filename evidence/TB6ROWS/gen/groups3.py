from groups import PRE
def vprog(lim):
    return PRE + r"""
:- table vp/1 as incremental.
:- dynamic([vd/1], [incremental(true)]).
vd(1).
vp(X) :- vd(X).
"""
def vcases(lim):
    return [
 ("v01", r"set_prolog_flag(table_space, %d), findall(X, vp(X), L), R = L" % lim),
 ("v02", r"'$idg_thread_summary'(main, N, E), ts(vp(_), S1), ts(vd(_), S2), R = r(N, E, S1, S2)"),
 ("v03", r"set_prolog_flag(table_space, 1000000000), findall(X, vp(X), L), '$idg_thread_summary'(main, N, E), ts(vp(_), S1), ts(vd(_), S2), R = r(L, N, E, S1, S2)"),
]
G = [dict(key="DYNERR", program=vprog(1508), cases=vcases(1508)), dict(key="DYNOK", program=vprog(1516), cases=vcases(1516)),
 dict(key="INCRPROP", program=PRE + r"""
:- table ip/1 as incremental.
:- dynamic([id/1], [incremental(true)]).
:- dynamic(plain/1).
id(1).
ip(X) :- id(X).
inc_prop(G, R) :- tm_yn(predicate_property(G, incremental), R).
dyn_prop(G, R) :- tm_yn(predicate_property(G, dynamic), R).
""", cases=[
 ("i01", r"assertz(wb_plain(1)), inc_prop(wb_plain(_), I), dyn_prop(wb_plain(_), D), R = r(I, D)"),
 ("i02", r"inc_prop(id(_), I), dyn_prop(id(_), D), inc_prop(plain(_), I2), dyn_prop(plain(_), D2), inc_prop(ip(_), I3), R = r(I, D, I2, D2, I3)"),
])]
