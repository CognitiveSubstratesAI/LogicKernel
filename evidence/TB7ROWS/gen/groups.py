# TB7ROWS groups: (key, label, program, [(id, goal)])
HDR = """tm_yn(G, R) :- ( call(G) -> R = yes ; R = no ).
tp(G, T) :- '$tbl_existing_variant_table'(0, user:G, T, _, _).
ts(G, S) :- ( tp(G, T) -> '$tbl_table_status'(T, S) ; S = none ).
qa(G, L) :- tp(G, T), findall(C, ('$idg_mono_affects_lazy'(T, _, _, _, A), length(A, C)), L).
fo(G, R) :- tp(G, T), ( '$idg_forced'(T) -> R = forced ; R = notforced ).
mi(G, R) :- tp(G, T), ( '$idg_mono_index'(T, _) -> R = idx ; R = noidx ).
"""
G = []
G.append(("DEPERR", "DEPERR: `'$idg_add_monotonic_dep'/3` between two tables, one or both without an IDG node: dependency_error(Dst, monotonic(Src)) unless the target is opaque (kills TB7R-DE1 d01 d03 d04, TB7R-DE2 d01 d02, TB7R-DE3 d03 d04, TB7R-DE4 d01)",
"""
:- table pa/1.
:- table pb/1.
:- table po/1 as opaque.
:- table pm/1 as monotonic.
:- table pn/1 as monotonic.
:- dynamic md/1 as monotonic.
pa(1). pb(1). po(1).
pm(X) :- md(X).
pn(X) :- pm(X).
md(0).
dv(G, T) :- '$tbl_variant_table'(0, user:G, T, _, _, _).
dep(G1, G2, R) :- call(G1), call(G2), dv(G1, T1), dv(G2, T2),
    ( '$idg_add_monotonic_dep'(T1, dependency(x, y, z, w), T2) -> R = ok ; R = failed ).
""",
[("d01", "dep(pa(_), pb(_), R)"),
 ("d02", "dep(pa(_), po(_), R)"),
 ("d03", "dep(pm(_), pa(_), R)"),
 ("d04", "dep(pa(_), pm(_), R)"),
 ("d05", "findall(X, pn(X), L), R = L"),
 ("d06", "dep(pm(_), pn(_), R)"),
 ("d07", "dep(pn(_), po(_), R)")]))
G.append(("COLLECT", "COLLECT: `'$tbl_collect_mono_dep'/0`, `'$tbl_propagate_start'/1`, `'$tbl_propagate_end'/1` (kills TB7R-CO1 c01 c02, TB7R-CO2 c03-c06, TB7-propagate-start-flag c02 c07, TB7-inner-monotonic-flag c03-c06)",
"""
:- table cm/1 as monotonic.
:- table cn/1.
:- table co/1.
:- table cmm/1 as monotonic.
cm(X) :- ( '$tbl_collect_mono_dep' -> X = yes ; X = no ).
cn(X) :- ( '$tbl_collect_mono_dep' -> X = yes ; X = no ).
co(X) :- cm(Y), ( '$tbl_collect_mono_dep' -> X = yes(Y) ; X = no(Y) ).
cmm(X) :- cn(Y), ( '$tbl_collect_mono_dep' -> X = yes(Y) ; X = no(Y) ).
cd(R) :- ( '$tbl_collect_mono_dep' -> R = yes ; R = no ).
""",
[("c01", "cd(R)"),
 ("c02", "'$tbl_propagate_start'(Old), cd(A), '$tbl_propagate_end'(Old), cd(B), R = r(Old, A, B)"),
 ("c03", "findall(X, cm(X), L), R = L"),
 ("c04", "findall(X, cn(X), L), R = L"),
 ("c05", "findall(X, co(X), L), R = L"),
 ("c06", "findall(X, cmm(X), L), R = L"),
 ("c07", "'$tbl_propagate_start'(O1), '$tbl_propagate_start'(O2), '$tbl_propagate_end'(O2), cd(A), '$tbl_propagate_end'(O1), cd(B), R = r(O1, O2, A, B)")]))
G.append(("LAZY", "LAZY: an eager and two lazy monotonic tables over one monotonic dynamic predicate: status, queues, invalidation, forcing, the index (kills TB7-add-dep-lazy-child, TB7-add-dep-lazy-parent, TB7-changed-lazy, TB7-changed-flag-mono, TB7-edge-step-lazy, TB7-monotonic-edge-lazy, TB7-queue-was-nonempty: l02 l03 l04; TB7-edge-step-force, TB7-changed-forced, TB7-changed-falsecount, TB7-scc-complete-false, TB7-scc-complete-start: l05 l07; TB7-mono-index-pred, TB7-index-build-deps: l09)",
HDR + """
:- dynamic ld/1 as monotonic.
:- table lp/1 as (monotonic, lazy).
:- table mp/1 as monotonic.
:- table lq/1 as (monotonic, lazy).
lp(X) :- ld(X).
mp(X) :- ld(X).
lq(X) :- lp(X).
""",
[("l01", "forall(member(G, [lp(_), mp(_), lq(_)]), forall(G, true)), ts(lp(_), A), ts(mp(_), B), ts(lq(_), C), R = r(A, B, C)"),
 ("l02", "assertz(ld(1)), ts(lp(_), A), ts(mp(_), B), ts(lq(_), C), qa(lp(_), Q1), qa(lq(_), Q2), R = r(s(A, B, C), q(Q1, Q2))"),
 ("l03", "assertz(ld(2)), ts(lp(_), A), qa(lp(_), Q1), qa(lq(_), Q2), R = r(A, Q1, Q2)"),
 ("l04", "findall(X, lq(X), L0), msort(L0, L), ts(lp(_), A), ts(lq(_), C), qa(lp(_), Q1), qa(lq(_), Q2), R = r(L, A, C, Q1, Q2)"),
 ("l05", "tp(lp(_), T), '$idg_mono_invalidate'(T), ts(lp(_), A), ts(lq(_), C), fo(lp(_), F), R = r(A, C, F)"),
 ("l06", "findall(X, lq(X), L0), msort(L0, L), ts(lp(_), A), ts(lq(_), C), fo(lp(_), F), R = r(L, A, C, F)"),
 ("l07", "retract(ld(1)), ts(lp(_), A), ts(mp(_), B), ts(lq(_), C), fo(lp(_), F), R = r(A, B, C, F)"),
 ("l08", "findall(X, lq(X), L0), msort(L0, L), findall(X, mp(X), M0), msort(M0, M), R = r(L, M)"),
 ("l09", "mi(lp(_), A), mi(mp(_), B), mi(lq(_), C), R = r(A, B, C)")]))
RS = "abolish_all_tables, retractall(ld(_)), forall(lp(_), true)"
G.append(("QUEUE", "QUEUE: the answer queue of a lazy dependency and its reevaluation by hand: `'$idg_mono_empty_queue'/2` (a count, zero, negative), `'$mono_reeval_prepare'/2`, `'$mono_reeval_done'/3`, a retract of a queued answer (kills TB7-empty-queue-count q01, TB7-empty-queue-pred-magic q05, TB7-prune-filter q06, TB7-prune-forced q06 q08, TB7-prune-lazy q06 q08, TB7-reeval-prepare-lazy q09 q10, TB7-reeval-done-count q09, TB7-invalid-deps-count q09 q11; q02 pins the count equal to the queue length, where TB7-empty-queue-bound stays EQUIVALENT, see TB7.py)",
HDR + """
:- dynamic ld/1 as monotonic.
:- table lp/1 as (monotonic, lazy).
lp(X) :- ld(X).
rs :- abolish_all_tables, retractall(ld(_)), forall(lp(_), true).
eq(N, R) :- tp(lp(_), T), '$idg_mono_affects_lazy'(T, _, _, Ref, _),
    ( catch('$idg_mono_empty_queue'(Ref, N), error(E, _), Raised = E) -> ( nonvar(Raised) -> R = raised(Raised) ; R = yes ) ; R = no ).
three :- rs, assertz(ld(1)), assertz(ld(2)), assertz(ld(3)).
""",
[("q01", "three, eq(2, A), qa(lp(_), Q), ts(lp(_), S), R = r(A, Q, S)"),
 ("q02", "three, eq(3, A), qa(lp(_), Q), ts(lp(_), S), R = r(A, Q, S)"),
 ("q03", "three, eq(0, A), qa(lp(_), Q), ts(lp(_), S), R = r(A, Q, S)"),
 ("q04", "three, eq(-1, A), qa(lp(_), Q), ts(lp(_), S), R = r(A, Q, S)"),
 ("q05", "three, eq(1, A1), eq(1, A2), qa(lp(_), Q), R = r(A1, A2, Q)"),
 ("q06", "rs, assertz(ld(1)), assertz(ld(2)), retract(ld(1)), qa(lp(_), Q), ts(lp(_), S), fo(lp(_), F), R = r(Q, S, F)"),
 ("q07", "rs, assertz(ld(1)), assertz(ld(2)), tp(lp(_), T), '$idg_mono_invalidate'(T), qa(lp(_), Q), ts(lp(_), S), findall(X, lp(X), L0), msort(L0, L), R = r(Q, S, L)"),
 ("q08", "rs, assertz(ld(1)), assertz(ld(2)), retractall(ld(1)), qa(lp(_), Q), ts(lp(_), S), findall(X, lp(X), L0), msort(L0, L), R = r(Q, S, L)"),
 ("q09", "rs, assertz(ld(1)), assertz(ld(2)), assertz(ld(3)), tp(lp(_), T), ts(lp(_), S0), ( '$mono_reeval_prepare'(T, Size) -> P = yes ; P = no ), ts(lp(_), S1), '$idg_mono_affects_lazy'(T, _, _, Ref, Ans), length(Ans, C), '$idg_mono_empty_queue'(Ref, C), qa(lp(_), Q), ( '$mono_reeval_done'(T, Size, Deps) -> D = yes(Deps) ; D = no ), ts(lp(_), S2), R = r(S0, P, Size, S1, C, Q, D, S2)"),
 ("q10", "tp(lp(_), T), ( '$mono_reeval_prepare'(T, Size) -> R = r(yes, Size) ; R = r(no) )"),
 ("q11", "findall(X, lp(X), L0), msort(L0, L), ts(lp(_), S), R = r(L, S)")]))
G.append(("SUBMONO", "SUBMONO: `as (subsumptive, monotonic)`: a later call of an instance reuses the complete table, a new clause reaches it and its monotonic consumer (an own-program control: no mutant is attributed to it by name; it adds the subsumptive-monotonic combination to the monotonic files that every TB7 mutant targets)",
"""
tt(G, N) :- '$tbl_local_variant_table'(VT), findall(x, trie_gen(VT, user:G, _), L), length(L, N).
:- dynamic sd/1 as monotonic.
:- table sm/1 as (subsumptive, monotonic).
:- table sc/1 as monotonic.
:- table sn/2 as (subsumptive, monotonic).
:- dynamic se/2 as monotonic.
sm(X) :- sd(X).
sc(X) :- sm(X).
sn(X, Y) :- se(X, Y).
""",
[("s01", "assertz(sd(1)), assertz(sd(2)), findall(X, sm(X), L0), msort(L0, L), findall(x, sm(2), M), tt(sm(_), N), R = r(L, M, N)"),
 ("s02", "assertz(sd(3)), findall(X, sm(X), L0), msort(L0, L), findall(x, sm(2), M), findall(x, sm(3), M3), tt(sm(_), N), R = r(L, M, M3, N)"),
 ("s03", "findall(X, sc(X), L0), msort(L0, L), assertz(sd(4)), findall(X, sc(X), L1), msort(L1, L2), findall(X, sm(X), L3), msort(L3, L4), R = r(L, L2, L4)"),
 ("s04", "retract(sd(1)), findall(X, sm(X), L0), msort(L0, L), findall(X, sc(X), L1), msort(L1, L2), findall(x, sm(2), M), R = r(L, L2, M)"),
 ("s05", "assertz(se(a, 1)), assertz(se(b, 2)), findall(Y, sn(a, Y), L0), findall(X-Y, sn(X, Y), L1), msort(L1, L), assertz(se(a, 3)), findall(Y, sn(a, Y), M0), msort(M0, M), findall(X-Y, sn(X, Y), N1), msort(N1, N), tt(sn(_, _), T), R = r(L0, L, M, N, T)")]))
