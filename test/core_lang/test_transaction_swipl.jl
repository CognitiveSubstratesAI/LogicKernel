# ORIGINAL: a LIVE differential of transactions and undo (TX1; audit D-0479) against swipl at the pin (swipl-devel 18168e62,
# 10.1.20): `transaction/1,2,3`, `snapshot/1`, `transaction_updates/1`, `current_transaction/1` (pl-transaction.c) and `undo/1`
# (pl-undo.c, run by `'$run_undo'/1` of boot/syspred.pl). Groups: txc = commit and discard (transaction/1,2,3), txs = snapshot,
# txn = nested transactions, txu = transaction_updates, txr = current_transaction, txd = undo, txe = update events, txx = the rows
# the mutant list TX1.py owed (nested retract of the parent's clause, the transaction's view of a clause erased at its start, the
# last-modified generation, a read across a commit, two outermost transactions in a row, the WHOLE event term, current_transaction/1
# at depth 2, the flags and gen_nest after a nested level, the updates' order, no event in a bulk level, a listener that raises at
# the bulk commit); txx16 (undo goals run at the backtrack) is the white-box testset at the end.
#   * Cases `t_<id>(R)` run in order in one database, each wrapped in `tx_clean, catch(Goal, error(SsuE, _), R = raised(SsuE))`
#     (`tx_clean` empties the predicates `tx_p/1`, `tx_q/1`, `tx_e/1` and the two global variables the rows read); the driver is
#     test_tabling_variant_swipl.jl's (`enc`oded answers: a row prints the answer of `t_<id>(R)`, or nothing when it fails).
#   * Every answer line is swipl's, PINNED (swipl 10.1.20, two byte-identical runs; evidence/TX1/tx1f_cases.py and
#     tx1f_run_swipl.py make the lines); with `swipl` on PATH the live answers are compared with the pins too.
#   * UPSTREAM QUIRKS pinned as is: (1) `transaction(Goal, Options)` has no meta-predicate declaration in boot/syspred.pl (only
#     `transaction(0)` and `transaction(0,0,+)`), so an unqualified goal runs in `$syspreds`: txc12 asserts into the wrong module
#     and the clause is not seen; txc13/txc14 qualify the goal with `user:`. (2) `bulk(true)` on an OUTERMOST transaction raises
#     the update events DURING the goal (the outer branch never sets the transaction's flags) and again at the commit: txe03
#     (two assertz: two events in the goal, four at the end); `bulk(false)` and `[]` raise them in the goal only (txe04, txe05).
#     (3) a nested `bulk(true)` transaction whose parent has no changed clauses yet hands its clauses to the parent and raises
#     no event at all, not even at the outer commit: txe08. (4) `current_transaction/1` repeats the parent goal at depth 2 and
#     deeper (the redo context is never advanced): only depth 1 is enumerated here (txr05), deeper rows take the first answer.
#   * txx rows: the rollback events of ONE discard come in the order of upstream's clause table (a hash of clause POINTERS; two runs of
#     the same row differ), so the listener of txx10/txx12/txx15 (`tx_evf`, logged by `tx_flog`) sorts them; `current_transaction/1`
#     at depth 2 repeats the parent's goal (quirk 4): txx11 takes three answers with findnsols/4, never `findall`.
#     The listener `tx_evg` (txx17) raises from its At-th event on: a bulk outermost transaction raises the events in the goal and
#     again at the commit (quirk 2), so At = 2 is a raise AT the commit (the transaction is discarded: `[]`, the exception comes out).
#   * Rows left out: an undo goal that RAISES (`undo(1)`, `undo(_)`, `undo(throw(boom))`: the error comes out of the
#     backtracking that runs the hook, `'$run_undo'/1` calls `'$urgent_exception'/3`): a named refusal of the kernel, owner P3.
#   * UNVERIFIED on the kernel (nothing was compiled when these rows were written): every kernel answer; the gate decides.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — these built-ins ride the term layer through the FLI (unify, get, strip module)
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TX = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_txs(x) = lk_sym(_TX, Symbol(x))

_tx_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _tx_enc(t::_TX, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _tx_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _tx_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _tx_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_tx_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

const _TX_DRIVER = raw"""
enc(T) :- enc(T, [], _).
enc(V, S0, S) :- var(V), !, ( vidx(S0, V, 0, I) -> S = S0 ; length(S0, I), append(S0, [V], S) ), format("V~w", [I]).
enc(T, S, S) :- T == [], !, write(nil).
enc(T, S, S) :- atom(T), !, atom_codes(T, Cs), format("a~w", [Cs]).
enc(T, S, S) :- string(T), !, string_codes(T, Cs), format("s~w", [Cs]).
enc(T, S, S) :- integer(T), !, format("i~w", [T]).
enc(T, S, S) :- rational(T, N, D), !, format("q~wr~w", [N, D]).
enc(T, S, S) :- float(T), !, format("f~w", [T]).
enc(T, S0, S) :- compound_name_arity(T, N, A),
    ( N == [] -> write('c[]') ; atom_codes(N, Cs), format("c~w", [Cs]) ),
    format("/~w(", [A]), encargs(1, A, T, S0, S), write(')').
encargs(I, A, _, S, S) :- I > A, !.
encargs(I, A, T, S0, S) :- arg(I, T, X), enc(X, S0, S1), ( I < A -> write(',') ; true ),
    I1 is I+1, encargs(I1, A, T, S1, S).
vidx([X|_], V, I, I) :- X == V, !.
vidx([_|Xs], V, I0, I) :- I1 is I0+1, vidx(Xs, V, I1, I).
fz_pred(N) :-
    format("~w", [N]), functor(G, N, 1),
    catch(findnsols(50, G, G, Gs), _, Gs = [exception]),
    forall(member(S, Gs), ( S == exception -> write(' exception') ; write(' '), enc(S) )), nl.
fz_run(File, Ns) :-
    catch(( consult(File), S = ok ), E, S = exc(E)),
    ( S == ok -> writeln(ok) ; S = exc(B), write('exc '), enc(B), nl ),
    forall(member(N, Ns), fz_pred(N)).
"""

function _tx_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _TX_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(
            pipeline(addenv(`swipl -q $f`, "LC_ALL" => "C"); stdin=devnull, stderr=devnull),
            String
        )
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end


const _TX_PROGRAM = raw"""
:- dynamic tx_p/1, tx_q/1, tx_e/1.
tx_all(P, L) :- G =.. [P, X], findall(X, G, L).
tx_rev(L, R) :- tx_rev(L, [], R).
tx_rev([], R, R).
tx_rev([X|Xs], A, R) :- tx_rev(Xs, [X|A], R).
tx_log(L) :- nb_getval(tx_log, L0), tx_rev(L0, L).
tx_push(X) :- nb_getval(tx_u, L), nb_setval(tx_u, [X|L]).
tx_pushed(L) :- nb_getval(tx_u, L0), tx_rev(L0, L).
tx_ev(A, _) :- functor(A, F, _), nb_getval(tx_log, L), nb_setval(tx_log, [F|L]).
:- prolog_listen(tx_e/1, tx_ev).
tx_clean :- retractall(tx_p(_)), retractall(tx_q(_)), retractall(tx_e(_)), nb_setval(tx_u, []), nb_setval(tx_log, []).
tx_yn(G, R) :- ( call(G) -> R = yes ; R = no ).
tx_cur(F) :- once(current_transaction(G)), functor(G, N, A), F = N/A.
tx_kinds(U, As) :- findall(A, (member(X, U), functor(X, A, _)), As).
% tx_f/1: a listener that logs the WHOLE event term as rollback(Action) / the action's functor (txx10, txx12, txx15); the
% rollback events of one discard come in the order of upstream's clause table (a hash of the clause pointers: it differs from run to
% run), so tx_flog sorts them and keeps the others in order.
:- dynamic tx_f/1.
tx_evf(A, _) :-
    ( A =.. [rollback, X] -> ( compound(X) -> X =.. [F|_] ; F = X ), E = rollback(F) ; functor(A, E, _) ),
    nb_getval(tx_full, L), nb_setval(tx_full, [E|L]).
:- prolog_listen(tx_f/1, tx_evf).
tx_fclean :- retractall(tx_f(_)), nb_setval(tx_full, []).
tx_split([], [], []).
tx_split([E|T], Rb, Ot) :- ( E = rollback(_) -> Rb = [E|Rb1], Ot = Ot1 ; Rb = Rb1, Ot = [E|Ot1] ), tx_split(T, Rb1, Ot1).
tx_flog(L) :- nb_getval(tx_full, L0), tx_rev(L0, L1), tx_split(L1, Rb, Ot), msort(Rb, RbS), append(Ot, RbS, L).
% tx_g/1: a listener that raises from its At-th event on, only while tx_gon is on (txx17: announce_updates at a bulk commit).
:- dynamic tx_g/1.
tx_evg(A, _) :-
    functor(A, F, _),
    (   ( F == rollback ; nb_getval(tx_gon, off) ) -> true
    ;   nb_getval(tx_gn, N0), N is N0 + 1, nb_setval(tx_gn, N), nb_getval(tx_gat, At),
        ( N >= At -> throw(tx_boom(N)) ; true )
    ).
:- prolog_listen(tx_g/1, tx_evg).
tx_gclean(At) :- nb_setval(tx_gon, off), retractall(tx_g(_)), nb_setval(tx_gn, 0), nb_setval(tx_gat, At), nb_setval(tx_gon, on).
:- nb_setval(tx_u, []), nb_setval(tx_log, []), nb_setval(tx_full, []), nb_setval(tx_gon, off), nb_setval(tx_gn, 0), nb_setval(tx_gat, 1).
"""

const _TX_CASES = [
    ("txc01", raw"transaction((assertz(tx_p(1)), assertz(tx_p(2)))), tx_all(tx_p, L), R = L"),
    ("txc02", raw"tx_yn(transaction((assertz(tx_p(1)), fail)), Y), tx_all(tx_p, L), R = r(Y, L)"),
    ("txc03", raw"catch(transaction((assertz(tx_p(1)), throw(oops))), E, true), tx_all(tx_p, L), R = r(E, L)"),
    ("txc04", raw"assertz(tx_p(1)), transaction(retract(tx_p(1))), tx_all(tx_p, L), R = L"),
    ("txc05", raw"transaction((assertz(tx_p(1)), tx_all(tx_p, In))), tx_all(tx_p, Out), R = r(In, Out)"),
    ("txc06", raw"assertz(tx_p(1)), tx_yn(transaction((retract(tx_p(1)), fail)), Y), tx_all(tx_p, L), R = r(Y, L)"),
    ("txc07", raw"assertz(tx_p(1)), assertz(tx_p(2)), transaction(retractall(tx_p(_))), tx_all(tx_p, L), R = L"),
    ("txc08", raw"transaction(assertz(tx_p(1)), tx_all(tx_p, [1]), tx_m), tx_all(tx_p, L), R = L"),
    ("txc09", raw"tx_yn(transaction(assertz(tx_p(1)), fail, tx_m), Y), tx_all(tx_p, L), R = r(Y, L)"),
    ("txc10", raw"assertz(tx_p(1)), tx_yn(transaction(assertz(tx_p(2)), (tx_all(tx_p, L0), L0 == [1]), tx_m), Y), tx_all(tx_p, L), R = r(Y, L)"),
    ("txc11", raw"assertz(tx_p(1)), transaction((asserta(tx_p(0)), assertz(tx_p(2)))), tx_all(tx_p, L), R = L"),
    ("txc12", raw"transaction(assertz(tx_p(9)), []), tx_all(tx_p, L), R = L"),
    ("txc13", raw"transaction(user:assertz(tx_p(9)), []), tx_all(tx_p, L), R = L"),
    ("txc14", raw"transaction(user:assertz(tx_p(9)), [bulk(true)]), tx_all(tx_p, L), R = L"),
    ("txc15", raw"catch(transaction(user:true, [bulk(maybe)]), error(E, _), true), R = E"),
    ("txc16", raw"catch(transaction(_), error(E, _), true), R = E"),
    ("txc17", raw"catch(transaction(1), error(E, _), true), R = E"),
    ("txc18", raw"transaction(true), R = ok"),
    ("txc19", raw"transaction((assertz(tx_p(1)), assertz(tx_q(1)))), tx_all(tx_p, A), tx_all(tx_q, B), R = r(A, B)"),
    ("txc20", raw"assertz(tx_p(1)), tx_yn(transaction((retract(tx_p(1)), assertz(tx_p(2)), fail)), Y), tx_all(tx_p, L), R = r(Y, L)"),
    ("txc21", raw"transaction((assertz(tx_p(1)), retract(tx_p(1)))), tx_all(tx_p, L), R = L"),
    ("txc22", raw"assertz(tx_p(1)), assertz(tx_p(2)), transaction((retract(tx_p(1)), tx_all(tx_p, In))), tx_all(tx_p, Out), R = r(In, Out)"),
    ("txc23", raw"assertz(tx_p(1)), transaction((tx_yn(tx_p(1), A), retract(tx_p(1)), tx_yn(tx_p(1), B))), R = r(A, B)"),
    ("txs01", raw"snapshot((assertz(tx_p(1)), tx_all(tx_p, In))), tx_all(tx_p, Out), R = r(In, Out)"),
    ("txs02", raw"tx_yn(snapshot((assertz(tx_p(1)), fail)), Y), tx_all(tx_p, L), R = r(Y, L)"),
    ("txs03", raw"assertz(tx_p(1)), snapshot(retract(tx_p(1))), tx_all(tx_p, L), R = L"),
    ("txs04", raw"transaction((assertz(tx_p(1)), snapshot(assertz(tx_p(2))))), tx_all(tx_p, L), R = L"),
    ("txs05", raw"catch(snapshot((assertz(tx_p(1)), throw(oops))), E, true), tx_all(tx_p, L), R = r(E, L)"),
    ("txs06", raw"snapshot(true), R = ok"),
    ("txs07", raw"catch(snapshot(_), error(E, _), true), R = E"),
    ("txs08", raw"snapshot((assertz(tx_p(1)), snapshot(assertz(tx_p(2))), tx_all(tx_p, In))), tx_all(tx_p, Out), R = r(In, Out)"),
    ("txn01", raw"transaction((assertz(tx_p(1)), transaction(assertz(tx_p(2))))), tx_all(tx_p, L), R = L"),
    ("txn02", raw"transaction((assertz(tx_p(1)), ( transaction((assertz(tx_p(2)), fail)) -> true ; true ), assertz(tx_p(3)))), tx_all(tx_p, L), R = L"),
    ("txn03", raw"tx_yn(transaction((transaction(assertz(tx_p(1))), fail)), Y), tx_all(tx_p, L), R = r(Y, L)"),
    ("txn04", raw"transaction((assertz(tx_p(1)), catch(transaction((assertz(tx_p(2)), throw(x))), x, true), assertz(tx_p(3)))), tx_all(tx_p, L), R = L"),
    ("txn05", raw"transaction((assertz(tx_p(1)), transaction((assertz(tx_p(2)), transaction(assertz(tx_p(3))))))), tx_all(tx_p, L), R = L"),
    ("txn06", raw"transaction((assertz(tx_p(1)), assertz(tx_p(2)), transaction(retract(tx_p(1))))), tx_all(tx_p, L), R = L"),
    ("txn07", raw"assertz(tx_p(1)), tx_yn(transaction((transaction(retract(tx_p(1))), fail)), Y), tx_all(tx_p, L), R = r(Y, L)"),
    ("txn08", raw"transaction((assertz(tx_p(1)), transaction((assertz(tx_p(2)), tx_all(tx_p, In))), tx_all(tx_p, Out))), R = r(In, Out)"),
    ("txn09", raw"transaction((assertz(tx_p(1)), ( transaction((assertz(tx_p(2)), fail)) -> true ; true ), tx_all(tx_p, In))), tx_all(tx_p, Out), R = r(In, Out)"),
    ("txn10", raw"assertz(tx_p(1)), transaction((transaction((retract(tx_p(1)), assertz(tx_p(2)))), tx_all(tx_p, In))), tx_all(tx_p, Out), R = r(In, Out)"),
    ("txn11", raw"tx_yn(transaction((assertz(tx_p(1)), transaction(assertz(tx_p(2)), fail, tx_m))), Y), tx_all(tx_p, L), R = r(Y, L)"),
    ("txn12", raw"transaction((assertz(tx_p(1)), transaction(assertz(tx_p(2)), tx_all(tx_p, [1,2]), tx_m))), tx_all(tx_p, L), R = L"),
    ("txn13", raw"transaction((assertz(tx_p(1)), snapshot((assertz(tx_p(2)), transaction(assertz(tx_p(3))))))), tx_all(tx_p, L), R = L"),
    ("txn14", raw"transaction((assertz(tx_p(1)), transaction((assertz(tx_p(2)), snapshot(assertz(tx_p(3))), tx_all(tx_p, In))))), tx_all(tx_p, Out), R = r(In, Out)"),
    ("txn15", raw"transaction((assertz(tx_p(1)), transaction(user:assertz(tx_p(2)), [bulk(true)]))), tx_all(tx_p, L), R = L"),
    ("txu01", raw"transaction((assertz(tx_p(1)), asserta(tx_p(0)), transaction_updates(U), tx_kinds(U, As))), R = As"),
    ("txu02", raw"assertz(tx_p(1)), transaction((retract(tx_p(1)), transaction_updates(U), tx_kinds(U, As))), R = As"),
    ("txu03", raw"transaction((assertz(tx_p(1)), retract(tx_p(1)), transaction_updates(U), tx_kinds(U, As))), R = As"),
    ("txu04", raw"transaction_updates(U), R = U"),
    ("txu05", raw"transaction((assertz(tx_p(7)), transaction_updates([assertz(Ref)]), clause(H, B, Ref))), R = r(H, B)"),
    ("txu06", raw"assertz(tx_p(1)), transaction((retract(tx_p(1)), transaction_updates([erased(Ref)]), clause(H, B, Ref))), R = r(H, B)"),
    ("txu07", raw"transaction((assertz(tx_p(1)), transaction((assertz(tx_p(2)), transaction_updates(U), tx_kinds(U, In))), transaction_updates(V), tx_kinds(V, Out))), R = r(In, Out)"),
    ("txu08", raw"transaction((assertz(tx_p(1)), assertz(tx_q(2)), asserta(tx_p(0)), transaction_updates(U), length(U, N))), R = N"),
    ("txu09", raw"snapshot((assertz(tx_p(1)), transaction_updates(U), tx_kinds(U, As))), R = As"),
    ("txu10", raw"transaction((assertz(tx_p(1)), transaction_updates([assertz(_)]))), R = ok"),
    ("txu11", raw"transaction((assertz(tx_p(1)), transaction_updates([erased(_)]))), R = ok"),
    ("txu12", raw"transaction((assertz(tx_p(1)), transaction_updates(U), U = [X], X =.. [F, Ref], blob(Ref, T))), R = r(F, T)"),
    ("txr01", raw"findall(G, current_transaction(G), L), R = L"),
    ("txr02", raw"transaction(tx_cur(F)), R = F"),
    ("txr03", raw"transaction(transaction(tx_cur(F))), R = F"),
    ("txr04", raw"snapshot(tx_cur(F)), R = F"),
    ("txr05", raw"transaction((findall(N, (current_transaction(G), functor(G, N, _)), L))), R = L"),
    ("txr06", raw"transaction(true), findall(G, current_transaction(G), L), R = L"),
    ("txr07", raw"transaction((once(current_transaction(user:G)), functor(G, N, A))), R = N/A"),
    ("txr08", raw"transaction((limit(1, current_transaction(G)), functor(G, N, A))), R = N/A"),
    ("txr09", raw"transaction(user:(tx_cur(F), true)), R = F"),
    ("txr10", raw"transaction(snapshot(tx_cur(F))), R = F"),
    ("txr11", raw"transaction(transaction(transaction(tx_cur(F)))), R = F"),
    ("txr12", raw"transaction(( current_transaction(G), functor(G, N, A) )), R = N/A"),
    ("txd01", raw"( undo(tx_push(a)), fail ; true ), tx_pushed(L), R = L"),
    ("txd02", raw"( undo(tx_push(a)), undo(tx_push(b)), fail ; true ), tx_pushed(L), R = L"),
    ("txd03", raw"undo(tx_push(a)), tx_pushed(L), R = L"),
    ("txd04", raw"findall(X, ( member(X, [1,2,3]), undo(tx_push(X)) ), Xs), tx_pushed(L), R = r(Xs, L)"),
    ("txd05", raw"( undo(fail), fail ; true ), R = ok"),
    ("txd06", raw"( Y = 7, undo(tx_push(Y)), fail ; true ), tx_pushed(L), R = L"),
    ("txd07", raw"( once(undo(tx_push(a))), fail ; true ), tx_pushed(L), R = L"),
    ("txd08", raw"( undo(catch(undo(true), error(E, _), tx_push(E))), fail ; true ), tx_pushed(L), R = L"),
    ("txd11", raw"( member(X, [1,2]), undo(tx_push(X)), X >= 2 -> true ; true ), tx_pushed(L), R = L"),
    ("txd12", raw"( undo(tx_push(a)), undo(tx_push(b)) ), tx_pushed(L), R = L"),
    ("txd13", raw"( undo(tx_push(a)), ( undo(tx_push(b)), fail ; true ), tx_pushed(L0) ), tx_pushed(L), R = r(L0, L)"),
    ("txd14", raw"tx_yn(( undo(tx_push(a)), !, fail ; true ), Y), tx_pushed(L), R = r(Y, L)"),
    ("txd15", raw"( undo(tx_push(a)), \+ fail, fail ; true ), tx_pushed(L), R = L"),
    ("txd16", raw"( undo(tx_push(f(_))), fail ; true ), tx_pushed(L), R = L"),
    ("txd17", raw"( undo((tx_push(a), tx_push(b))), fail ; true ), tx_pushed(L), R = L"),
    ("txd18", raw"( undo(tx_push(1.5)), undo(tx_push(abc)), fail ; true ), tx_pushed(L), R = L"),
    ("txd19", raw"( undo(user:tx_push(a)), fail ; true ), tx_pushed(L), R = L"),
    ("txd21", raw"catch(( undo(tx_push(a)), throw(x) ), x, true), tx_pushed(L), R = L"),
    ("txd22", raw"( transaction(( undo(tx_push(a)), assertz(tx_p(1)) )), fail ; true ), tx_pushed(L), tx_all(tx_p, P), R = r(L, P)"),
    ("txe01", raw"assertz(tx_e(1)), nb_setval(tx_log, []), assertz(tx_e(2)), tx_log(L), R = L"),
    ("txe02", raw"transaction(assertz(tx_e(1))), tx_log(L), R = L"),
    ("txe03", raw"transaction(user:(assertz(tx_e(1)), assertz(tx_e(2)), tx_log(In)), [bulk(true)]), tx_log(Out), R = r(In, Out)"),
    ("txe04", raw"transaction(user:(assertz(tx_e(1)), assertz(tx_e(2)), tx_log(In)), [bulk(false)]), tx_log(Out), R = r(In, Out)"),
    ("txe05", raw"transaction(user:(assertz(tx_e(1)), assertz(tx_e(2)), tx_log(In)), []), tx_log(Out), R = r(In, Out)"),
    ("txe06", raw"tx_yn(transaction((assertz(tx_e(1)), fail)), Y), tx_log(L), R = r(Y, L)"),
    ("txe07", raw"assertz(tx_e(1)), nb_setval(tx_log, []), transaction(retract(tx_e(1))), tx_log(L), R = L"),
    ("txe08", raw"transaction(user:(transaction(user:(assertz(tx_e(1)), assertz(tx_e(2))), [bulk(true)]), tx_log(In))), tx_log(Out), R = r(In, Out)"),
    ("txe09", raw"transaction(user:(assertz(tx_e(1)), transaction(user:assertz(tx_e(2)), [bulk(true)]), tx_log(In))), tx_log(Out), R = r(In, Out)"),
    ("txe10", raw"tx_yn(transaction(user:(assertz(tx_e(1)), fail), [bulk(true)]), Y), tx_log(L), R = r(Y, L)"),
    ("txe11", raw"snapshot((assertz(tx_e(1)), tx_log(In))), tx_log(Out), R = r(In, Out)"),
    ("txe12", raw"assertz(tx_e(1)), nb_setval(tx_log, []), transaction(user:retractall(tx_e(_)), [bulk(true)]), tx_log(L), R = L"),
    ("txx01", raw"transaction((assertz(tx_p(1)), tx_yn(transaction((retract(tx_p(1)), fail)), Y), tx_all(tx_p, L))), R = r(Y, L)"),
    ("txx02", raw"transaction((assertz(tx_p(1)), transaction(retract(tx_p(1))), tx_all(tx_p, In))), R = In"),
    ("txx03", raw"assertz(tx_p(1)), retract(tx_p(1)), transaction(tx_all(tx_p, In)), R = In"),
    ("txx04", raw"assertz(tx_p(1)), transaction((retract(tx_p(1)), transaction(tx_all(tx_p, In)))), R = In"),
    ("txx05", raw"assertz(tx_p(0)), predicate_property(tx_p(_), last_modified_generation(G0)), transaction(assertz(tx_p(1))), predicate_property(tx_p(_), last_modified_generation(G1)), snapshot(assertz(tx_p(2))), predicate_property(tx_p(_), last_modified_generation(G2)), retract(tx_p(0)), predicate_property(tx_p(_), last_modified_generation(G3)), ( G0 < G1 -> A = lt ; A = ge ), ( G1 == G2 -> B = eq ; B = ne ), ( G2 < G3 -> C = lt ; C = ge ), R = r(A, B, C)"),
    ("txx05b", raw"assertz(tx_p(0)), predicate_property(tx_p(_), last_modified_generation(G0)), transaction((assertz(tx_p(1)), predicate_property(tx_p(_), last_modified_generation(G1)))), ( G0 < G1 -> A = lt ; A = ge ), R = A"),
    ("txx05c", raw"assertz(tx_p(0)), predicate_property(tx_p(_), last_modified_generation(G0)), tx_yn(transaction((assertz(tx_p(1)), fail)), _), predicate_property(tx_p(_), last_modified_generation(G1)), ( G0 == G1 -> A = eq ; A = ne ), R = A"),
    ("txx06", raw"assertz(tx_p(1)), findall(X, (tx_p(X), (X == 1 -> transaction(assertz(tx_p(2))) ; true)), L), tx_all(tx_p, All), R = r(L, All)"),
    ("txx07", raw"assertz(tx_p(1)), assertz(tx_p(2)), transaction(retract(tx_p(1))), predicate_property(tx_p(_), number_of_clauses(N)), R = N"),
    ("txx08", raw"transaction(assertz(tx_p(1))), tx_yn(transaction((assertz(tx_p(2)), fail)), Y), tx_all(tx_p, L), R = r(Y, L)"),
    ("txx09", raw"tx_yn(transaction((assertz(tx_p(1)), fail)), _), predicate_property(tx_p(_), number_of_clauses(N)), R = N"),
    ("txx10", raw"tx_fclean, assertz(tx_f(0)), nb_setval(tx_full, []), tx_yn(transaction(user:(assertz(tx_f(1)), asserta(tx_f(2)), retract(tx_f(0)), fail)), Y), tx_flog(L), R = r(Y, L)"),
    ("txx11", raw"transaction(transaction(once(findnsols(3, N/A, (current_transaction(G), functor(G, N, A)), L)))), R = L"),
    ("txx11b", raw"transaction((transaction(true), tx_cur(F))), R = F"),
    ("txx11c", raw"transaction((transaction(true), once(findnsols(3, N/A, (current_transaction(G), functor(G, N, A)), L)))), R = L"),
    ("txx12", raw"tx_fclean, transaction((transaction(user:assertz(tx_f(1)), [bulk(true)]), assertz(tx_f(2)))), tx_flog(L), R = L"),
    ("txx12b", raw"tx_fclean, transaction(user:(transaction(user:assertz(tx_f(1)), [bulk(true)]), assertz(tx_f(2)), tx_flog(In)), [bulk(false)]), tx_flog(Out), R = r(In, Out)"),
    ("txx13", raw"transaction((assertz(tx_p(1)), transaction(true), retract(tx_p(1)), predicate_property(tx_p(_), number_of_clauses(N)))), R = N"),
    ("txx13b", raw"transaction((assertz(tx_p(1)), transaction(true), retract(tx_p(1)))), predicate_property(tx_p(_), number_of_clauses(N)), R = N"),
    ("txx14", raw"transaction((assertz(tx_p(1)), assertz(tx_p(2)), transaction(retract(tx_p(1))), transaction_updates(U), tx_kinds(U, As))), R = As"),
    ("txx14b", raw"transaction((assertz(tx_p(1)), assertz(tx_p(2)), asserta(tx_p(0)), transaction(retract(tx_p(2))), assertz(tx_q(5)), transaction_updates(U), tx_kinds(U, As))), R = As"),
    ("txx15", raw"tx_fclean, transaction(user:(transaction(user:(assertz(tx_f(1)), fail), [bulk(true)]) -> true ; true)), tx_flog(L), R = L"),
    ("txx15b", raw"tx_fclean, assertz(tx_f(1)), nb_setval(tx_full, []), transaction(user:(transaction(user:retract(tx_f(1)), [bulk(true)]), tx_flog(In)), [bulk(true)]), tx_flog(Out), R = r(In, Out)"),
    ("txx15c", raw"tx_fclean, assertz(tx_f(1)), assertz(tx_f(2)), nb_setval(tx_full, []), transaction(user:(assertz(tx_f(3)), transaction(user:retract(tx_f(1)), [bulk(true)]), tx_flog(In)), []), tx_flog(Out), R = r(In, Out)"),
    ("txx17a", raw"tx_gclean(1), catch(transaction(user:assertz(tx_g(1)), []), E, true), nb_getval(tx_gn, N), tx_all(tx_g, L), R = r(E, N, L)"),
    ("txx17b", raw"tx_gclean(2), catch(transaction(user:assertz(tx_g(1)), [bulk(true)]), E, true), nb_getval(tx_gn, N), tx_all(tx_g, L), R = r(E, N, L)"),
    ("txx17c", raw"tx_gclean(2), tx_yn(catch(transaction(user:assertz(tx_g(1)), [bulk(true)]), _, fail), Y), nb_getval(tx_gn, N), tx_all(tx_g, L), R = r(Y, N, L)"),
    ("txx17d", raw"tx_gclean(9), transaction(user:assertz(tx_g(1)), [bulk(true)]), nb_getval(tx_gn, N), tx_all(tx_g, L), R = r(N, L)"),
    ("txx17e", raw"tx_gclean(3), catch(transaction(user:(assertz(tx_g(1)), assertz(tx_g(2))), [bulk(true)]), E, true), nb_getval(tx_gn, N), tx_all(tx_g, L), R = r(E, N, L)"),
]

const _TX_PINNED = [
    "ok",
    "t_txc01 c[116,95,116,120,99,48,49]/1(c[91,124,93]/2(i1,c[91,124,93]/2(i2,nil)))",
    "t_txc02 c[116,95,116,120,99,48,50]/1(c[114]/2(a[110,111],nil))",
    "t_txc03 c[116,95,116,120,99,48,51]/1(c[114]/2(a[111,111,112,115],nil))",
    "t_txc04 c[116,95,116,120,99,48,52]/1(nil)",
    "t_txc05 c[116,95,116,120,99,48,53]/1(c[114]/2(c[91,124,93]/2(i1,nil),c[91,124,93]/2(i1,nil)))",
    "t_txc06 c[116,95,116,120,99,48,54]/1(c[114]/2(a[110,111],c[91,124,93]/2(i1,nil)))",
    "t_txc07 c[116,95,116,120,99,48,55]/1(nil)",
    "t_txc08 c[116,95,116,120,99,48,56]/1(c[91,124,93]/2(i1,nil))",
    "t_txc09 c[116,95,116,120,99,48,57]/1(c[114]/2(a[110,111],nil))",
    "t_txc10 c[116,95,116,120,99,49,48]/1(c[114]/2(a[110,111],c[91,124,93]/2(i1,nil)))",
    "t_txc11 c[116,95,116,120,99,49,49]/1(c[91,124,93]/2(i0,c[91,124,93]/2(i1,c[91,124,93]/2(i2,nil))))",
    "t_txc12 c[116,95,116,120,99,49,50]/1(nil)",
    "t_txc13 c[116,95,116,120,99,49,51]/1(c[91,124,93]/2(i9,nil))",
    "t_txc14 c[116,95,116,120,99,49,52]/1(c[91,124,93]/2(i9,nil))",
    "t_txc15 c[116,95,116,120,99,49,53]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[98,111,111,108],a[109,97,121,98,101]))",
    "t_txc16 c[116,95,116,120,99,49,54]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114])",
    "t_txc17 c[116,95,116,120,99,49,55]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,97,108,108,97,98,108,101],i1))",
    "t_txc18 c[116,95,116,120,99,49,56]/1(a[111,107])",
    "t_txc19 c[116,95,116,120,99,49,57]/1(c[114]/2(c[91,124,93]/2(i1,nil),c[91,124,93]/2(i1,nil)))",
    "t_txc20 c[116,95,116,120,99,50,48]/1(c[114]/2(a[110,111],c[91,124,93]/2(i1,nil)))",
    "t_txc21 c[116,95,116,120,99,50,49]/1(nil)",
    "t_txc22 c[116,95,116,120,99,50,50]/1(c[114]/2(c[91,124,93]/2(i2,nil),c[91,124,93]/2(i2,nil)))",
    "t_txc23 c[116,95,116,120,99,50,51]/1(c[114]/2(a[121,101,115],a[110,111]))",
    "t_txs01 c[116,95,116,120,115,48,49]/1(c[114]/2(c[91,124,93]/2(i1,nil),nil))",
    "t_txs02 c[116,95,116,120,115,48,50]/1(c[114]/2(a[110,111],nil))",
    "t_txs03 c[116,95,116,120,115,48,51]/1(c[91,124,93]/2(i1,nil))",
    "t_txs04 c[116,95,116,120,115,48,52]/1(c[91,124,93]/2(i1,nil))",
    "t_txs05 c[116,95,116,120,115,48,53]/1(c[114]/2(a[111,111,112,115],nil))",
    "t_txs06 c[116,95,116,120,115,48,54]/1(a[111,107])",
    "t_txs07 c[116,95,116,120,115,48,55]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114])",
    "t_txs08 c[116,95,116,120,115,48,56]/1(c[114]/2(c[91,124,93]/2(i1,nil),nil))",
    "t_txn01 c[116,95,116,120,110,48,49]/1(c[91,124,93]/2(i1,c[91,124,93]/2(i2,nil)))",
    "t_txn02 c[116,95,116,120,110,48,50]/1(c[91,124,93]/2(i1,c[91,124,93]/2(i3,nil)))",
    "t_txn03 c[116,95,116,120,110,48,51]/1(c[114]/2(a[110,111],nil))",
    "t_txn04 c[116,95,116,120,110,48,52]/1(c[91,124,93]/2(i1,c[91,124,93]/2(i3,nil)))",
    "t_txn05 c[116,95,116,120,110,48,53]/1(c[91,124,93]/2(i1,c[91,124,93]/2(i2,c[91,124,93]/2(i3,nil))))",
    "t_txn06 c[116,95,116,120,110,48,54]/1(c[91,124,93]/2(i2,nil))",
    "t_txn07 c[116,95,116,120,110,48,55]/1(c[114]/2(a[110,111],c[91,124,93]/2(i1,nil)))",
    "t_txn08 c[116,95,116,120,110,48,56]/1(c[114]/2(c[91,124,93]/2(i1,c[91,124,93]/2(i2,nil)),c[91,124,93]/2(i1,c[91,124,93]/2(i2,nil))))",
    "t_txn09 c[116,95,116,120,110,48,57]/1(c[114]/2(c[91,124,93]/2(i1,nil),c[91,124,93]/2(i1,nil)))",
    "t_txn10 c[116,95,116,120,110,49,48]/1(c[114]/2(c[91,124,93]/2(i2,nil),c[91,124,93]/2(i2,nil)))",
    "t_txn11 c[116,95,116,120,110,49,49]/1(c[114]/2(a[110,111],nil))",
    "t_txn12 c[116,95,116,120,110,49,50]/1(c[91,124,93]/2(i1,c[91,124,93]/2(i2,nil)))",
    "t_txn13 c[116,95,116,120,110,49,51]/1(c[91,124,93]/2(i1,nil))",
    "t_txn14 c[116,95,116,120,110,49,52]/1(c[114]/2(c[91,124,93]/2(i1,c[91,124,93]/2(i2,nil)),c[91,124,93]/2(i1,c[91,124,93]/2(i2,nil))))",
    "t_txn15 c[116,95,116,120,110,49,53]/1(c[91,124,93]/2(i1,c[91,124,93]/2(i2,nil)))",
    "t_txu01 c[116,95,116,120,117,48,49]/1(c[91,124,93]/2(a[97,115,115,101,114,116,122],c[91,124,93]/2(a[97,115,115,101,114,116,97],nil)))",
    "t_txu02 c[116,95,116,120,117,48,50]/1(c[91,124,93]/2(a[101,114,97,115,101,100],nil))",
    "t_txu03 c[116,95,116,120,117,48,51]/1(nil)",
    "t_txu04",
    "t_txu05 c[116,95,116,120,117,48,53]/1(c[114]/2(c[116,120,95,112]/1(i7),a[116,114,117,101]))",
    "t_txu06 c[116,95,116,120,117,48,54]/1(c[114]/2(c[116,120,95,112]/1(i1),a[116,114,117,101]))",
    "t_txu07 c[116,95,116,120,117,48,55]/1(c[114]/2(c[91,124,93]/2(a[97,115,115,101,114,116,122],nil),c[91,124,93]/2(a[97,115,115,101,114,116,122],c[91,124,93]/2(a[97,115,115,101,114,116,122],nil))))",
    "t_txu08 c[116,95,116,120,117,48,56]/1(i3)",
    "t_txu09 c[116,95,116,120,117,48,57]/1(c[91,124,93]/2(a[97,115,115,101,114,116,122],nil))",
    "t_txu10 c[116,95,116,120,117,49,48]/1(a[111,107])",
    "t_txu11",
    "t_txu12 c[116,95,116,120,117,49,50]/1(c[114]/2(a[97,115,115,101,114,116,122],a[99,108,97,117,115,101]))",
    "t_txr01 c[116,95,116,120,114,48,49]/1(nil)",
    "t_txr02 c[116,95,116,120,114,48,50]/1(c[47]/2(a[116,120,95,99,117,114],i1))",
    "t_txr03 c[116,95,116,120,114,48,51]/1(c[47]/2(a[116,120,95,99,117,114],i1))",
    "t_txr04 c[116,95,116,120,114,48,52]/1(c[47]/2(a[116,120,95,99,117,114],i1))",
    "t_txr05 c[116,95,116,120,114,48,53]/1(c[91,124,93]/2(a[102,105,110,100,97,108,108],nil))",
    "t_txr06 c[116,95,116,120,114,48,54]/1(nil)",
    "t_txr07",
    "t_txr08 c[116,95,116,120,114,48,56]/1(c[47]/2(a[44],i2))",
    "t_txr09 c[116,95,116,120,114,48,57]/1(c[47]/2(a[44],i2))",
    "t_txr10 c[116,95,116,120,114,49,48]/1(c[47]/2(a[116,120,95,99,117,114],i1))",
    "t_txr11 c[116,95,116,120,114,49,49]/1(c[47]/2(a[116,120,95,99,117,114],i1))",
    "t_txr12 c[116,95,116,120,114,49,50]/1(c[47]/2(a[44],i2))",
    "t_txd01 c[116,95,116,120,100,48,49]/1(c[91,124,93]/2(a[97],nil))",
    "t_txd02 c[116,95,116,120,100,48,50]/1(c[91,124,93]/2(a[98],c[91,124,93]/2(a[97],nil)))",
    "t_txd03 c[116,95,116,120,100,48,51]/1(nil)",
    "t_txd04 c[116,95,116,120,100,48,52]/1(c[114]/2(c[91,124,93]/2(i1,c[91,124,93]/2(i2,c[91,124,93]/2(i3,nil))),c[91,124,93]/2(i1,c[91,124,93]/2(i2,c[91,124,93]/2(i3,nil)))))",
    "t_txd05 c[116,95,116,120,100,48,53]/1(a[111,107])",
    "t_txd06 c[116,95,116,120,100,48,54]/1(c[91,124,93]/2(i7,nil))",
    "t_txd07 c[116,95,116,120,100,48,55]/1(c[91,124,93]/2(a[97],nil))",
    "t_txd08 c[116,95,116,120,100,48,56]/1(c[91,124,93]/2(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[117,110,100,111],a[103,111,97,108],c[58]/2(a[117,115,101,114],a[116,114,117,101])),nil))",
    "t_txd11 c[116,95,116,120,100,49,49]/1(c[91,124,93]/2(i1,nil))",
    "t_txd12 c[116,95,116,120,100,49,50]/1(nil)",
    "t_txd13 c[116,95,116,120,100,49,51]/1(c[114]/2(c[91,124,93]/2(a[98],nil),c[91,124,93]/2(a[98],nil)))",
    "t_txd14 c[116,95,116,120,100,49,52]/1(c[114]/2(a[110,111],c[91,124,93]/2(a[97],nil)))",
    "t_txd15 c[116,95,116,120,100,49,53]/1(c[91,124,93]/2(a[97],nil))",
    "t_txd16 c[116,95,116,120,100,49,54]/1(c[91,124,93]/2(c[102]/1(V0),nil))",
    "t_txd17 c[116,95,116,120,100,49,55]/1(c[91,124,93]/2(a[97],c[91,124,93]/2(a[98],nil)))",
    "t_txd18 c[116,95,116,120,100,49,56]/1(c[91,124,93]/2(a[97,98,99],c[91,124,93]/2(f1.5,nil)))",
    "t_txd19 c[116,95,116,120,100,49,57]/1(c[91,124,93]/2(a[97],nil))",
    "t_txd21 c[116,95,116,120,100,50,49]/1(c[91,124,93]/2(a[97],nil))",
    "t_txd22 c[116,95,116,120,100,50,50]/1(c[114]/2(c[91,124,93]/2(a[97],nil),c[91,124,93]/2(i1,nil)))",
    "t_txe01 c[116,95,116,120,101,48,49]/1(c[91,124,93]/2(a[97,115,115,101,114,116,122],nil))",
    "t_txe02 c[116,95,116,120,101,48,50]/1(c[91,124,93]/2(a[97,115,115,101,114,116,122],nil))",
    "t_txe03 c[116,95,116,120,101,48,51]/1(c[114]/2(c[91,124,93]/2(a[97,115,115,101,114,116,122],c[91,124,93]/2(a[97,115,115,101,114,116,122],nil)),c[91,124,93]/2(a[97,115,115,101,114,116,122],c[91,124,93]/2(a[97,115,115,101,114,116,122],c[91,124,93]/2(a[97,115,115,101,114,116,122],c[91,124,93]/2(a[97,115,115,101,114,116,122],nil))))))",
    "t_txe04 c[116,95,116,120,101,48,52]/1(c[114]/2(c[91,124,93]/2(a[97,115,115,101,114,116,122],c[91,124,93]/2(a[97,115,115,101,114,116,122],nil)),c[91,124,93]/2(a[97,115,115,101,114,116,122],c[91,124,93]/2(a[97,115,115,101,114,116,122],nil))))",
    "t_txe05 c[116,95,116,120,101,48,53]/1(c[114]/2(c[91,124,93]/2(a[97,115,115,101,114,116,122],c[91,124,93]/2(a[97,115,115,101,114,116,122],nil)),c[91,124,93]/2(a[97,115,115,101,114,116,122],c[91,124,93]/2(a[97,115,115,101,114,116,122],nil))))",
    "t_txe06 c[116,95,116,120,101,48,54]/1(c[114]/2(a[110,111],c[91,124,93]/2(a[97,115,115,101,114,116,122],c[91,124,93]/2(a[114,111,108,108,98,97,99,107],nil))))",
    "t_txe07 c[116,95,116,120,101,48,55]/1(c[91,124,93]/2(a[114,101,116,114,97,99,116],nil))",
    "t_txe08 c[116,95,116,120,101,48,56]/1(c[114]/2(nil,nil))",
    "t_txe09 c[116,95,116,120,101,48,57]/1(c[114]/2(c[91,124,93]/2(a[97,115,115,101,114,116,122],c[91,124,93]/2(a[97,115,115,101,114,116,122],nil)),c[91,124,93]/2(a[97,115,115,101,114,116,122],c[91,124,93]/2(a[97,115,115,101,114,116,122],nil))))",
    "t_txe10 c[116,95,116,120,101,49,48]/1(c[114]/2(a[110,111],c[91,124,93]/2(a[97,115,115,101,114,116,122],c[91,124,93]/2(a[114,111,108,108,98,97,99,107],nil))))",
    "t_txe11 c[116,95,116,120,101,49,49]/1(c[114]/2(c[91,124,93]/2(a[97,115,115,101,114,116,122],nil),c[91,124,93]/2(a[97,115,115,101,114,116,122],c[91,124,93]/2(a[114,111,108,108,98,97,99,107],nil))))",
    "t_txe12 c[116,95,116,120,101,49,50]/1(c[91,124,93]/2(a[114,101,116,114,97,99,116,97,108,108],c[91,124,93]/2(a[114,101,116,114,97,99,116],c[91,124,93]/2(a[114,101,116,114,97,99,116,97,108,108],c[91,124,93]/2(a[101,114,97,115,101,100],nil)))))",
    "t_txx01 c[116,95,116,120,120,48,49]/1(c[114]/2(a[110,111],c[91,124,93]/2(i1,nil)))",
    "t_txx02 c[116,95,116,120,120,48,50]/1(nil)",
    "t_txx03 c[116,95,116,120,120,48,51]/1(nil)",
    "t_txx04 c[116,95,116,120,120,48,52]/1(nil)",
    "t_txx05 c[116,95,116,120,120,48,53]/1(c[114]/3(a[108,116],a[101,113],a[108,116]))",
    "t_txx05b c[116,95,116,120,120,48,53,98]/1(a[108,116])",
    "t_txx05c c[116,95,116,120,120,48,53,99]/1(a[101,113])",
    "t_txx06 c[116,95,116,120,120,48,54]/1(c[114]/2(c[91,124,93]/2(i1,nil),c[91,124,93]/2(i1,c[91,124,93]/2(i2,nil))))",
    "t_txx07 c[116,95,116,120,120,48,55]/1(i1)",
    "t_txx08 c[116,95,116,120,120,48,56]/1(c[114]/2(a[110,111],c[91,124,93]/2(i1,nil)))",
    "t_txx09 c[116,95,116,120,120,48,57]/1(i0)",
    "t_txx10 c[116,95,116,120,120,49,48]/1(c[114]/2(a[110,111],c[91,124,93]/2(a[97,115,115,101,114,116,122],c[91,124,93]/2(a[97,115,115,101,114,116,97],c[91,124,93]/2(a[114,101,116,114,97,99,116],c[91,124,93]/2(c[114,111,108,108,98,97,99,107]/1(a[97,115,115,101,114,116,97]),c[91,124,93]/2(c[114,111,108,108,98,97,99,107]/1(a[97,115,115,101,114,116,122]),c[91,124,93]/2(c[114,111,108,108,98,97,99,107]/1(a[114,101,116,114,97,99,116]),nil))))))))",
    "t_txx11 c[116,95,116,120,120,49,49]/1(c[91,124,93]/2(c[47]/2(a[111,110,99,101],i1),c[91,124,93]/2(c[47]/2(a[116,114,97,110,115,97,99,116,105,111,110],i1),c[91,124,93]/2(c[47]/2(a[116,114,97,110,115,97,99,116,105,111,110],i1),nil))))",
    "t_txx11b c[116,95,116,120,120,49,49,98]/1(c[47]/2(a[44],i2))",
    "t_txx11c c[116,95,116,120,120,49,49,99]/1(c[91,124,93]/2(c[47]/2(a[44],i2),nil))",
    "t_txx12 c[116,95,116,120,120,49,50]/1(c[91,124,93]/2(a[97,115,115,101,114,116,122],nil))",
    "t_txx12b c[116,95,116,120,120,49,50,98]/1(c[114]/2(c[91,124,93]/2(a[97,115,115,101,114,116,122],nil),c[91,124,93]/2(a[97,115,115,101,114,116,122],nil)))",
    "t_txx13 c[116,95,116,120,120,49,51]/1(i0)",
    "t_txx13b c[116,95,116,120,120,49,51,98]/1(i0)",
    "t_txx14 c[116,95,116,120,120,49,52]/1(c[91,124,93]/2(a[97,115,115,101,114,116,122],c[91,124,93]/2(a[101,114,97,115,101,100],nil)))",
    "t_txx14b c[116,95,116,120,120,49,52,98]/1(c[91,124,93]/2(a[97,115,115,101,114,116,122],c[91,124,93]/2(a[97,115,115,101,114,116,97],c[91,124,93]/2(a[101,114,97,115,101,100],c[91,124,93]/2(a[97,115,115,101,114,116,122],nil)))))",
    "t_txx15 c[116,95,116,120,120,49,53]/1(nil)",
    "t_txx15b c[116,95,116,120,120,49,53,98]/1(c[114]/2(nil,c[91,124,93]/2(a[101,114,97,115,101,100],nil)))",
    "t_txx15c c[116,95,116,120,120,49,53,99]/1(c[114]/2(c[91,124,93]/2(a[97,115,115,101,114,116,122],c[91,124,93]/2(a[101,114,97,115,101,100],nil)),c[91,124,93]/2(a[97,115,115,101,114,116,122],c[91,124,93]/2(a[101,114,97,115,101,100],nil))))",
    "t_txx17a c[116,95,116,120,120,49,55,97]/1(c[114]/3(c[116,120,95,98,111,111,109]/1(i1),i1,nil))",
    "t_txx17b c[116,95,116,120,120,49,55,98]/1(c[114]/3(c[116,120,95,98,111,111,109]/1(i2),i2,nil))",
    "t_txx17c c[116,95,116,120,120,49,55,99]/1(c[114]/3(a[110,111],i2,nil))",
    "t_txx17d c[116,95,116,120,120,49,55,100]/1(c[114]/2(i2,c[91,124,93]/2(i1,nil)))",
    "t_txx17e c[116,95,116,120,120,49,55,101]/1(c[114]/3(c[116,120,95,98,111,111,109]/1(i3),i3,nil))",
]

"The program text with the cases appended."
_tx_text(program::String, cases) =
    program * join([
        "t_$(id)(R) :- catch((tx_clean, $g), error(SsuE, _), R = raised(SsuE)).\n" for (id, g) in cases
    ])

"A kernel with the program consulted: `(gd, ld, first line of the driver's output)`."
function _tx_load(program::String)
    f = joinpath(mktempdir(), "transaction.pl")
    write(f, _tx_text(program, _TX_CASES))
    gd = LK.PL_global_data{_TX}()
    ld = LK.PL_local_data{_TX}(gd)
    st, ball = LK.load_file!(gd, ld, f)
    return gd, ld, (st === :ok ? "ok" : "exc " * _tx_enc(ball::_TX))
end

"The driver's line for `pred/1` (every answer, at most 50)."
function _tx_ask(gd, ld, pred::String)::String
    proc = LK.isCurrentProcedure(sym_key(_txs(pred)), 1, LK.MODULE_user(gd))
    (proc === nothing || !LK.isDefinedProcedure(gd, proc)) && return "$pred undefined"
    sols = String[]
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 1)
    LK.putSlotValue!(ld, a + 1, mk_var(_TX, LK.fresh_var_keys!(1)), LK.PutVarMap())
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    n = 0
    while (n += 1) <= 50
        rc = LK.PL_next_solution(gd, ld, qid)
        if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
            push!(sols, _tx_enc(mk_expr(_TX, _TX[_txs(pred), lk_answers(ld, (a:a)...)...])))
            rc == LK.PL_S_LAST && break
        elseif rc == LK.PL_S_EXCEPTION
            push!(sols, "exception")
            break
        else
            break
        end
    end
    LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
    return pred * join(" " .* sols)
end


@testset "transactions and undo as swipl's (txc, txs, txn, txu, txr, txd, txe)" begin
    gd, ld, st = _tx_load(_TX_PROGRAM)
    @test st == "ok"
    kl = String[st]
    for (id, _) in _TX_CASES
        push!(kl, _tx_ask(gd, ld, "t_$id"))
    end
    @test length(kl) == length(_TX_PINNED)
    for (k, p) in zip(kl, _TX_PINNED)
        k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
        @test k == p
    end
end

@testset "the transaction rows are not vacuous" begin
    @test _TX_PINNED[1] == "ok"
    @test length(_TX_PINNED) == length(_TX_CASES) + 1
    for pre in ("txc", "txs", "txn", "txu", "txr", "txd", "txe", "txx")
        ids = [id for (id, _) in _TX_CASES if startswith(id, pre)]
        @test !isempty(ids)
        @test length([l for l in _TX_PINNED if any(id -> l == "t_$id" || startswith(l, "t_$id "), ids)]) ==
            length(ids)
    end
    ans(id) = begin
        l = only(filter(l -> l == "t_$id" || startswith(l, "t_$id "), _TX_PINNED))
        return length(split(l, " "; limit=2)) == 2 ? split(l, " "; limit=2)[2] : "FAILS"
    end
    @test ans("txc01") != ans("txc02")          # a transaction that succeeds keeps its clauses, one that fails drops them
    @test ans("txc12") != ans("txc13")          # transaction/2 with an unqualified goal runs in `$syspreds` (upstream quirk)
    @test ans("txs01") != ans("txc05")          # snapshot discards, transaction commits
    @test ans("txn02") != ans("txn03")          # a failed nested transaction is dropped alone; a failed outer drops the nested one
    @test ans("txu01") != ans("txu03")          # an assert and a retract of the same clause leave no update
    @test ans("txu04") == "FAILS"               # no transaction: transaction_updates/1 fails
    @test ans("txr01") != ans("txr02")          # no transaction: no answer; one: its goal
    @test ans("txd01") != ans("txd03")          # the undo goal runs on backtracking, not on the way forward
    @test ans("txd01") != ans("txd02")          # two undo goals run newest first
    @test ans("txe03") != ans("txe04")          # bulk(true): the events again at the commit
    @test ans("txe08") != ans("txe09")          # a nested bulk(true) in a fresh outer raises no event (upstream quirk)
    val(id) = (l = ans(id); l == "FAILS" ? l : l[(findfirst('(', l) + 1):(end - 1)])       # the answer without the `t_<id>/1(` wrapper
    @test val("txx02") == "nil"                 # a nested retract of the parent's own clause: the parent no longer sees it
    @test val("txx01") != val("txx02")          # ... and when that nested level is discarded the clause is back
    @test val("txx05") == "c[114]/3(a[108,116],a[101,113],a[108,116])"      # r(lt, eq, lt): a commit and a retract move the last-modified generation, a snapshot does not
    @test val("txx05c") == "a[101,113]"         # a discard leaves it as it was (eq)
    @test val("txx17b") == "c[114]/3(c[116,120,95,98,111,111,109]/1(i2),i2,nil)"   # a listener that raises AT the commit: the exception, two events, no clause
    @test val("txx17d") == "c[114]/2(i2,c[91,124,93]/2(i1,nil))"            # one that does not: the clause is kept
    @test val("txx12") != val("txx15")          # the log after a bulk nested level (assertz) is not the log of a discarded bulk level (nothing)
end

@testset "the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "TX1 LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        f = joinpath(mktempdir(), "tx_swipl.pl")
        write(f, _tx_text(_TX_PROGRAM, _TX_CASES))
        @test _tx_swipl_lines(f, ["t_$id" for (id, _) in _TX_CASES]) == _TX_PINNED
    end
end

# txx16 (WHITE-BOX, kernel only; pl-vmi.c b_failed's `LD->alerted` block): the undo goals run AT the backtrack, before the next goal.
# Every txd row asks `tx_pushed(L)`, a predicate call, afterwards, and the call hook (depart_or_retry_continue) runs the goals by
# then; here the query ends at `R = x` with no call in between, so the schedule must already be empty (and the goal pushed).
@testset "undo goals run at the backtrack, not at the next call (txx16)" begin
    gd, ld, st = _tx_load(_TX_PROGRAM * "tx_w16(R) :- ( undo(tx_push(a)), fail ; R = x ).\n")
    @test st == "ok"
    proc = LK.isCurrentProcedure(sym_key(_txs("tx_w16")), 1, LK.MODULE_user(gd))
    @test proc !== nothing
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 1)
    LK.putSlotValue!(ld, a + 1, mk_var(_TX, LK.fresh_var_keys!(1)), LK.PutVarMap())
    qid = LK.PL_open_query(gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a)
    rc = LK.PL_next_solution(gd, ld, qid)
    @test rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
    @test _tx_enc(only(lk_answers(ld, (a:a)...))) == "a[120]"        # R = x
    @test !LK.UNDO_SCHEDULED(ld)                                      # the hook ran at the backtrack
    LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
    @test _tx_ask(gd, ld, "tx_pushed") == "tx_pushed c[91,124,93]/2(a[97],nil)"   # [a]
end

# txx18 (WHITE-BOX, kernel only; pl-undo.c:160-189 push_undo, TX1-N1 and TX1-N2): the cell of the undo list is scheduled only when it
# holds `'[|]'(Atom, Old)`. The control flow read at the pin: `if ( isTerm(*p) )` (:163) then `if ( f->definition == FUNCTOR_dot2 )` (:167)
# else `return` (:172-173); inside it `if ( !isAtom(w) ) return` (:169-170); only then `addBuffer` (:184). The cell is written by `'$undo'/1`
# alone in a run, so no query reaches these returns: the cell is written here by hand, and `push_undo` is called on it, as `Undo!` does.
# The three cells are built in one place and each is tried on its own; the third (a list cell with an atom head) is the control that
# the schedule can be reached at all, so that the two empty schedules before it are not a vacuous pass.
@testset "push_undo schedules a list cell with an atom head and nothing else (txx18a-c)" begin
    gd, ld, st = _tx_load(_TX_PROGRAM)
    @test st == "ok"
    p = ld.undo_list
    @test p == 1                                                      # premise: the first global cell, the one `Undo!` tests for
    @test ld.gstack[p] == ld.atom_nil_w                               # premise: it holds [] and nothing is scheduled
    @test !LK.UNDO_SCHEDULED(ld)
    aw = LK._atom_word!(ld, _txs("tx_w18"))
    @test LK.isAtomW(aw)                                              # premise: the head of the third cell is an atom ...
    iw = LK.consInt(Int64(7))
    @test !LK.isAtomW(iw)                                             # ... and the head of the first is not
    fw = LK.lookupFunctorDef(ld.functors, LK._atom_word!(ld, _txs("tx_w18f")), 1)
    @test fw != ld.functor_dot2                                       # premise: the second cell's functor is not '[|]'/2

    # txx18a (N1): '[|]'(7, []): the head is not an atom: pl-undo.c:169-170 returns before the schedule
    q = LK.allocGlobalCells!(ld, 3)
    ld.gstack[q] = ld.functor_dot2
    ld.gstack[q + 1] = iw
    ld.gstack[q + 2] = ld.atom_nil_w
    ld.gstack[p] = LK.consPtr(q, LK.TAG_COMPOUND | LK.STG_GLOBAL)
    @test LK.isTermW(ld.gstack[p]) && LK.valPtr(ld.gstack[p]) == q    # premise: the cell is a compound over q
    LK.push_undo(ld, p)
    @test !LK.UNDO_SCHEDULED(ld)

    # txx18b (N2): tx_w18f(tx_w18): an atom in the first argument but not the list functor: pl-undo.c:167, :172-173 return
    q = LK.allocGlobalCells!(ld, 2)
    ld.gstack[q] = fw
    ld.gstack[q + 1] = aw
    ld.gstack[p] = LK.consPtr(q, LK.TAG_COMPOUND | LK.STG_GLOBAL)
    @test LK.isTermW(ld.gstack[p]) && LK.valPtr(ld.gstack[p]) == q
    LK.push_undo(ld, p)
    @test !LK.UNDO_SCHEDULED(ld)

    # txx18c (control): '[|]'(tx_w18, []): the atom is scheduled, once
    q = LK.allocGlobalCells!(ld, 3)
    ld.gstack[q] = ld.functor_dot2
    ld.gstack[q + 1] = aw
    ld.gstack[q + 2] = ld.atom_nil_w
    ld.gstack[p] = LK.consPtr(q, LK.TAG_COMPOUND | LK.STG_GLOBAL)
    LK.push_undo(ld, p)
    @test LK.UNDO_SCHEDULED(ld)
    @test ld.undo_scheduled == [aw]
    LK.free_undo_data(ld)
    @test !LK.UNDO_SCHEDULED(ld)
end
