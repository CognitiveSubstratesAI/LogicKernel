# ORIGINAL: a LIVE differential of the event hooks of pl-event.c (swipl-devel 10.1.19, cbf4e1896275) against swipl at the pin:
# prolog_listen/2,3 and prolog_unlisten/2 on predicates (`Name/Arity` and the head form) and on `erase` and `untable`, and the events
# the kernel raises at its wired sites: assertz/asserta (pl-proc.c:1472), retract and erase/1 of a clause (:1709), retractall start and
# end (:3308, :3397), the erase of a record (pl-rec.c:2468) and the erase of a clause by the clause GC (announceErasedClause, :1773, :1850).
# Rows ev1p (predicate events), ev1o (delivery order), ev1u (unlisten), ev1v (vetoes and exceptions), ev1e (bad options), ev1r (record
# erase), ev1g (clause GC, WHITE-BOX on the kernel side: `garbage_collect_clauses/0` is PR1's (wip/pr1e), not this branch's, so the kernel
# row calls the Julia `pl_garbage_collect_clauses!` between the two halves `ev1_gc_a` and `ev1_gc_b`).
#   * A PROGRAM consulted by the kernel's loader and cases `t_<id>(R)` run in order in one database, each wrapped in
#     `catch(Goal, error(SsuE, _), R = raised(SsuE))`, each starting with `ev1_clear` (unlistens everything the rows register, empties the
#     logged events and the dynamic predicates); the driver is test_bootpred3_swipl.jl's (`enc`oded answers). A listener logs into
#     `ev1_log/1` (a clause reference is logged as `cl(Head, Body)`, never printed: it is a blob).
#   * Every answer line is swipl's, PINNED (swipl 10.1.19-1-gcbf4e189, evidence/EV1/ev1_rows.out, two byte-identical runs); with `swipl`
#     on PATH the live answers are compared with the pins too.
#   * UNVERIFIED on the kernel (nothing was compiled when these rows were written): every kernel answer; the gate decides. The rows
#     pin swipl's behaviour even where it is odd (a variable closure of prolog_unlisten/2 binds on the FIRST match; a named replacement
#     keeps the old procedure; after a failing listener later listeners are not called): the port copies pl-event.c.
#   * No row: the `untable` raise (pl-tabling.c:11317, TAB1), thread events (TH1), the break and abort events (DBG1), a listener that
#     removes itself while it runs (the kernel walks a snapshot; upstream a linked list).
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — these built-ins ride the term layer through the FLI (unify, get, strip module)
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _EV = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_evs(x) = lk_sym(_EV, Symbol(x))

_ev_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _ev_enc(t::_EV, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _ev_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _ev_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _ev_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_ev_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

const _EV_DRIVER = raw"""
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
"""function _ev_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _EV_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(pipeline(addenv(`swipl -q $f`, "LC_ALL" => "C"); stdin=devnull, stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

# the program: the listeners (an atom closure is called with the event's arguments, a term closure with them appended), the log, and
# `ev1_clear`, which every row starts with. `ev1_gc_a/1` and `ev1_gc_b/1` are the two halves of the white-box clause-GC row.
const _EV_PROGRAM = raw"""
:- dynamic ev1_log/1, ev1_p/1, ev1_q/1, ev1_m:ev1_q/1.
ev1_x(X, Y) :-
    (   X = start(_) -> Y = X
    ;   X = end(_) -> Y = X
    ;   atom(X) -> Y = X
    ;   catch(clause(H, B, X), _, fail) -> Y = cl(H, B)
    ;   Y = gone
    ).
ev1_t(Tag, Act, X) :- ev1_x(X, Y), assertz(ev1_log(Tag-Act-Y)).
ev1_a(Act, X) :- ev1_t(a, Act, X).
ev1_b(Act, X) :- ev1_t(b, Act, X).
ev1_veto(Tag, Act, X) :- ev1_t(Tag, Act, X), fail.
ev1_vend(Act, X) :- ev1_t(v, Act, X), \+ X = end(_).
ev1_throw(Tag, Act, X) :- ev1_t(Tag, Act, X), throw(ev1_ball(Tag)).
ev1_m:ev1_ma(Act, X) :- user:ev1_t(m, Act, X).
ev1_r(Tag, Ref) :-
    (   recorded(ev1_k, V, Ref) -> Y = present(V) ; Y = gone ),
    assertz(ev1_log(Tag-erase-Y)).
ev1_rveto(Tag, Ref) :- ev1_r(Tag, Ref), fail.
ev1_rthrow(Tag, Ref) :- ev1_r(Tag, Ref), throw(ev1_ball(Tag)).
ev1_e(Tag, X) :- ev1_x(X, Y), assertz(ev1_log(Tag-erase-Y)).
ev1_get(R) :- findall(L, ev1_log(L), R).
ev1_unl(E) :-
    forall(member(C, [ev1_a, ev1_b, ev1_m:ev1_ma, ev1_t(_), ev1_veto(_), ev1_vend, ev1_throw(_), ev1_r(_), ev1_rveto(_), ev1_rthrow(_), ev1_e(_)]),
           prolog_unlisten(E, C)).
ev1_clear :-
    forall(between(1, 4, _), forall(member(E, [ev1_p/1, ev1_q/1, ev1_m:ev1_q/1, ev1_u/1, ev1_p/2, erase, untable]), ev1_unl(E))),
    retractall(ev1_log(_)), retractall(ev1_p(_)), retractall(ev1_q(_)), retractall(ev1_m:ev1_q(_)),
    forall(recorded(ev1_k, _, Ref), erase(Ref)).
ev1_gc_a(R) :- ev1_clear, prolog_listen(erase, ev1_e(g)), assertz(ev1_p(1)), retract(ev1_p(1)), R = ok.
ev1_gc_b(R) :- ev1_get(R).
"""

# ev1p: events of a predicate; ev1o: order; ev1u: prolog_unlisten/2; ev1v: vetoes and exceptions; ev1e: bad options; ev1r: record
# erase; ev1g: the clause GC (white-box on the kernel side, see _EV_WHITEBOX).
const _EV_CASES = [
    ("ev1p01", raw"ev1_clear, prolog_listen(ev1_p/1, ev1_a), assertz(ev1_p(1)), ev1_get(R)"),
    ("ev1p02", raw"ev1_clear, prolog_listen(ev1_p/1, ev1_a), asserta(ev1_p(1)), ev1_get(R)"),
    ("ev1p03", raw"ev1_clear, prolog_listen(ev1_p/1, ev1_a), assert(ev1_p(1)), ev1_get(R)"),
    ("ev1p04", raw"ev1_clear, prolog_listen(ev1_p/1, ev1_a), assertz((ev1_p(X) :- ev1_q(X))), ev1_get(R)"),
    ("ev1p05", raw"ev1_clear, assertz(ev1_p(1)), prolog_listen(ev1_p/1, ev1_a), retract(ev1_p(1)), ev1_get(R)"),
    ("ev1p06", raw"ev1_clear, assertz(ev1_p(1)), assertz(ev1_p(2)), prolog_listen(ev1_p/1, ev1_a), forall(retract(ev1_p(_)), true), ev1_get(R)"),
    ("ev1p07", raw"ev1_clear, assertz(ev1_p(1)), prolog_listen(ev1_p/1, ev1_a), ( retract(ev1_p(9)) -> true ; true ), ev1_get(R)"),
    ("ev1p08", raw"ev1_clear, assertz(ev1_p(1), Ref), prolog_listen(ev1_p/1, ev1_a), erase(Ref), ev1_get(R)"),
    ("ev1p09", raw"ev1_clear, assertz(ev1_p(1)), assertz(ev1_p(2)), assertz(ev1_p(1)), prolog_listen(ev1_p/1, ev1_a), retractall(ev1_p(1)), findall(X, ev1_p(X), Xs), ev1_get(L), R = Xs-L"),
    ("ev1p10", raw"ev1_clear, prolog_listen(ev1_p/1, ev1_a), retractall(ev1_p(_)), ev1_get(R)"),
    ("ev1p11", raw"ev1_clear, assertz(ev1_p(1)), prolog_listen(ev1_p/1, ev1_a), retractall(ev1_p(9)), ev1_get(R)"),
    ("ev1p12", raw"ev1_clear, assertz(ev1_p(1)), assertz(ev1_p(2)), assertz(ev1_p(3)), prolog_listen(ev1_p/1, ev1_a), retractall(ev1_p(2)), findall(X, ev1_p(X), Xs), ev1_get(L), R = Xs-L"),
    ("ev1p13", raw"ev1_clear, prolog_listen(ev1_u/1, ev1_a), retractall(ev1_u(_)), ev1_get(R)"),
    ("ev1p14", raw"ev1_clear, prolog_listen(ev1_m:ev1_q/1, ev1_a), ev1_m:assertz(ev1_q(1)), ev1_get(R)"),
    ("ev1p15", raw"ev1_clear, prolog_listen(ev1_p/1, ev1_a), assertz(ev1_q(1)), ev1_get(R)"),
    ("ev1p16", raw"ev1_clear, prolog_listen(ev1_p(_), ev1_a), assertz(ev1_p(1)), ev1_get(R)"),
    ("ev1p17", raw"ev1_clear, prolog_listen(ev1_p/1, ev1_a), prolog_unlisten(ev1_p/1, ev1_a), assertz(ev1_p(1)), ev1_get(R)"),
    ("ev1p18", raw"ev1_clear, prolog_listen(ev1_p/1, ev1_m:ev1_ma), assertz(ev1_p(1)), ev1_get(R)"),
    ("ev1p19", raw"ev1_clear, prolog_listen(ev1_p/1, ev1_a), assertz(ev1_p(1), Ref), erase(Ref), ev1_get(R)"),
    ("ev1o01", raw"ev1_clear, prolog_listen(ev1_p/1, ev1_a), prolog_listen(ev1_p/1, ev1_b), assertz(ev1_p(1)), ev1_get(R)"),
    ("ev1o02", raw"ev1_clear, prolog_listen(ev1_p/1, ev1_a, [as(last)]), prolog_listen(ev1_p/1, ev1_b, [as(last)]), assertz(ev1_p(1)), ev1_get(R)"),
    ("ev1o03", raw"ev1_clear, prolog_listen(ev1_p/1, ev1_a), prolog_listen(ev1_p/1, ev1_b, [as(last)]), prolog_listen(ev1_p/1, ev1_t(c), [as(first)]), assertz(ev1_p(1)), ev1_get(R)"),
    ("ev1o04", raw"ev1_clear, prolog_listen(ev1_p/1, ev1_t(one), [name(n)]), prolog_listen(ev1_p/1, ev1_t(two), [name(n)]), assertz(ev1_p(1)), ev1_get(R)"),
    ("ev1o05", raw"ev1_clear, prolog_listen(ev1_p/1, ev1_a), prolog_listen(ev1_p/1, ev1_t(one), [name(n), as(last)]), prolog_listen(ev1_p/1, ev1_b, [as(last)]), prolog_listen(ev1_p/1, ev1_t(two), [name(n), as(first)]), assertz(ev1_p(1)), ev1_get(R)"),
    ("ev1o06", raw"ev1_clear, prolog_listen(ev1_p/1, ev1_t(one), [name(n1)]), prolog_listen(ev1_p/1, ev1_t(two), [name(n2)]), assertz(ev1_p(1)), ev1_get(R)"),
    ("ev1o07", raw"ev1_clear, prolog_listen(ev1_p/1, ev1_a), prolog_listen(ev1_p/1, ev1_a), assertz(ev1_p(1)), ev1_get(R)"),
    ("ev1o08", raw"ev1_clear, prolog_listen(ev1_p/1, ev1_a, [as(first)]), prolog_listen(ev1_p/1, ev1_b, [as(first)]), assertz(ev1_p(1)), ev1_get(R)"),
    ("ev1o09", raw"ev1_clear, prolog_listen(ev1_p/1, ev1_a, [name(n)]), prolog_listen(ev1_q/1, ev1_b, [name(n)]), assertz(ev1_p(1)), assertz(ev1_q(1)), ev1_get(R)"),
    ("ev1o10", raw"ev1_clear, prolog_listen(ev1_p/1, ev1_a), prolog_listen(ev1_p/1, ev1_t(one), [name(n)]), prolog_listen(ev1_p/1, ev1_t(three), [name(n)]), assertz(ev1_p(1)), ev1_get(R)"),
    ("ev1o11", raw"ev1_clear, prolog_listen(ev1_p/1, ev1_a, [name(n)]), prolog_listen(ev1_p/1, ev1_t(two), [name(n)]), assertz(ev1_p(1)), ev1_get(R)"),
    ("ev1u01", raw"ev1_clear, prolog_listen(ev1_p/1, ev1_a), prolog_listen(ev1_p/1, ev1_b), prolog_unlisten(ev1_p/1, ev1_a), assertz(ev1_p(1)), ev1_get(R)"),
    ("ev1u02", raw"ev1_clear, prolog_listen(ev1_p/1, ev1_t(1)), prolog_listen(ev1_p/1, ev1_t(2)), prolog_unlisten(ev1_p/1, ev1_t(1)), assertz(ev1_p(1)), ev1_get(R)"),
    ("ev1u03", raw"ev1_clear, prolog_listen(ev1_p/1, ev1_t(1)), prolog_listen(ev1_p/1, ev1_t(2)), prolog_listen(ev1_p/1, ev1_a), prolog_unlisten(ev1_p/1, ev1_t(_)), assertz(ev1_p(1)), ev1_get(R)"),
    ("ev1u04", raw"ev1_clear, prolog_listen(ev1_p/1, ev1_t(1)), prolog_unlisten(ev1_p/1, ev1_t), assertz(ev1_p(1)), ev1_get(R)"),
    ("ev1u05", raw"ev1_clear, ( prolog_unlisten(ev1_q/1, ev1_a) -> R = yes ; R = no )"),
    ("ev1u06", raw"ev1_clear, prolog_unlisten(nosuchevent, ev1_a), R = yes"),
    ("ev1u07", raw"ev1_clear, prolog_unlisten(1, ev1_a), R = yes"),
    ("ev1u08", raw"ev1_clear, prolog_listen(ev1_p/1, ev1_a), prolog_unlisten(ev1_p/1, 1), R = yes"),
    ("ev1u09", raw"ev1_clear, prolog_listen(ev1_p/1, ev1_a), prolog_unlisten(ev1_p/1, _), R = yes"),
    ("ev1u10", raw"ev1_clear, prolog_listen(ev1_p/1, ev1_a), ( prolog_unlisten(ev1_p/1, ev1_b) -> A = yes ; A = no ), assertz(ev1_p(1)), ev1_get(L), R = A-L"),
    ("ev1u11", raw"ev1_clear, prolog_listen(erase, ev1_r(x)), prolog_unlisten(erase, ev1_r(x)), recorda(ev1_k, v, Ref), erase(Ref), ev1_get(R)"),
    ("ev1u12", raw"ev1_clear, prolog_listen(ev1_p/1, user:ev1_a), prolog_unlisten(ev1_p/1, ev1_a), assertz(ev1_p(1)), ev1_get(R)"),
    ("ev1u13", raw"ev1_clear, prolog_listen(ev1_p/1, ev1_a), prolog_unlisten(ev1_p/1, ev1_a), prolog_unlisten(ev1_p/1, ev1_a), assertz(ev1_p(1)), ev1_get(R)"),
    ("ev1u14", raw"ev1_clear, prolog_listen(ev1_p/1, ev1_a), prolog_listen(ev1_p/1, ev1_a), prolog_unlisten(ev1_p/1, ev1_a), assertz(ev1_p(1)), ev1_get(R)"),
    ("ev1u15", raw"ev1_clear, prolog_listen(ev1_p/1, ev1_t(1)), prolog_listen(ev1_p/1, ev1_t(1)), prolog_unlisten(ev1_p/1, ev1_t(1)), assertz(ev1_p(1)), ev1_get(R)"),
    ("ev1u16", raw"ev1_clear, prolog_listen(ev1_p/1, ev1_t(f(1))), prolog_unlisten(ev1_p/1, ev1_t(f(2))), assertz(ev1_p(1)), ev1_get(R)"),
    ("ev1u17", raw"ev1_clear, prolog_listen(untable, ev1_a), prolog_unlisten(untable, ev1_a), R = yes"),
    ("ev1v01", raw"ev1_clear, prolog_listen(ev1_p/1, ev1_veto(v)), ( assertz(ev1_p(1)) -> A = yes ; A = no ), findall(X, ev1_p(X), Xs), ev1_get(L), R = A-Xs-L"),
    ("ev1v02", raw"ev1_clear, assertz(ev1_p(1)), prolog_listen(ev1_p/1, ev1_veto(v)), ( retract(ev1_p(1)) -> A = yes ; A = no ), findall(X, ev1_p(X), Xs), ev1_get(L), R = A-Xs-L"),
    ("ev1v03", raw"ev1_clear, prolog_listen(ev1_p/1, ev1_veto(v)), prolog_listen(ev1_p/1, ev1_b, [as(last)]), ( assertz(ev1_p(1)) -> A = yes ; A = no ), ev1_get(L), R = A-L"),
    ("ev1v04", raw"ev1_clear, prolog_listen(ev1_p/1, ev1_t(w)), prolog_listen(ev1_p/1, ev1_veto(v), [as(last)]), ( assertz(ev1_p(1)) -> A = yes ; A = no ), ev1_get(L), R = A-L"),
    ("ev1v05", raw"ev1_clear, assertz(ev1_p(1)), assertz(ev1_p(2)), prolog_listen(ev1_p/1, ev1_veto(v)), ( retractall(ev1_p(_)) -> A = yes ; A = no ), findall(X, ev1_p(X), Xs), ev1_get(L), R = A-Xs-L"),
    ("ev1v06", raw"ev1_clear, assertz(ev1_p(1)), assertz(ev1_p(2)), prolog_listen(ev1_p/1, ev1_vend), ( retractall(ev1_p(_)) -> A = yes ; A = no ), findall(X, ev1_p(X), Xs), ev1_get(L), R = A-Xs-L"),
    ("ev1v07", raw"ev1_clear, assertz(ev1_p(1), Ref), prolog_listen(ev1_p/1, ev1_veto(v)), ( erase(Ref) -> A = yes ; A = no ), findall(X, ev1_p(X), Xs), ev1_get(L), R = A-Xs-L"),
    ("ev1v08", raw"ev1_clear, prolog_listen(ev1_p/1, ev1_throw(t)), catch(assertz(ev1_p(1)), E, true), findall(X, ev1_p(X), Xs), ev1_get(L), R = E-Xs-L"),
    ("ev1v09", raw"ev1_clear, assertz(ev1_p(1)), prolog_listen(ev1_p/1, ev1_throw(t)), catch(retract(ev1_p(1)), E, true), findall(X, ev1_p(X), Xs), ev1_get(L), R = E-Xs-L"),
    ("ev1v10", raw"ev1_clear, prolog_listen(ev1_p/1, ev1_throw(t)), prolog_listen(ev1_p/1, ev1_b, [as(last)]), catch(assertz(ev1_p(1)), E, true), ev1_get(L), R = E-L"),
    ("ev1v11", raw"ev1_clear, assertz(ev1_p(1)), prolog_listen(ev1_p/1, ev1_throw(t)), catch(retractall(ev1_p(_)), E, true), findall(X, ev1_p(X), Xs), ev1_get(L), R = E-Xs-L"),
    ("ev1v12", raw"ev1_clear, prolog_listen(ev1_p/1, ev1_veto(v)), prolog_listen(ev1_p/1, ev1_t(w), [as(last)]), ( assertz(ev1_p(1)) -> A = yes ; A = no ), ev1_get(L), R = A-L"),
    ("ev1e01", raw"ev1_clear, prolog_listen(ev1_p/1, ev1_a, [as(middle)]), R = yes"),
    ("ev1e02", raw"ev1_clear, prolog_listen(ev1_p/1, ev1_a, [name(1)]), R = yes"),
    ("ev1e03", raw"ev1_clear, prolog_listen(ev1_p/1, 1), R = yes"),
    ("ev1e04", raw"ev1_clear, prolog_listen(ev1_p/1, _), R = yes"),
    ("ev1e05", raw"ev1_clear, prolog_listen(ev1_p/a, ev1_a), R = yes"),
    ("ev1e06", raw"ev1_clear, prolog_listen(ev1_p/(-1), ev1_a), R = yes"),
    ("ev1e07", raw"ev1_clear, prolog_listen(ev1_p/2, ev1_a), assertz(ev1_p(1)), ev1_get(R)"),
    ("ev1e08", raw"ev1_clear, prolog_listen(ev1_p/1, ev1_a, foo), R = yes"),
    ("ev1e09", raw"ev1_clear, prolog_listen(_, ev1_a), R = yes"),
    ("ev1e10", raw"ev1_clear, prolog_listen(nosuchevent/1, ev1_a), R = yes"),
    ("ev1e11", raw"ev1_clear, prolog_listen(foo:ev1_p/1, ev1_a), R = yes"),
    ("ev1e12", raw"ev1_clear, prolog_listen(ev1_p/1, ev1_a, [as(first), foo(1)]), assertz(ev1_p(1)), ev1_get(R)"),
    ("ev1r01", raw"ev1_clear, prolog_listen(erase, ev1_r(x)), recorda(ev1_k, v, Ref), erase(Ref), ev1_get(R)"),
    ("ev1r02", raw"ev1_clear, prolog_listen(erase, ev1_r(x)), prolog_listen(erase, ev1_r(y)), recordz(ev1_k, v, Ref), erase(Ref), ev1_get(R)"),
    ("ev1r03", raw"ev1_clear, prolog_listen(erase, ev1_rthrow(t)), recorda(ev1_k, v, Ref), catch(erase(Ref), E, true), findall(V, recorded(ev1_k, V), Vs), ev1_get(L), R = E-Vs-L"),
    ("ev1r04", raw"ev1_clear, prolog_listen(erase, ev1_rveto(t)), recorda(ev1_k, v, Ref), ( erase(Ref) -> A = yes ; A = no ), findall(V, recorded(ev1_k, V), Vs), ev1_get(L), R = A-Vs-L"),
    ("ev1r05", raw"ev1_clear, prolog_listen(erase, ev1_r(x)), recorda(ev1_k, v, _), recorda(ev1_k, w, _), ( recorded(ev1_k, v, Ref) -> erase(Ref) ; true ), ev1_get(R)"),
    ("ev1r06", raw"ev1_clear, prolog_listen(erase, ev1_r(x)), recorda(ev1_k, v, Ref), erase(Ref), ( catch(erase(Ref), error(E, _), true) -> true ; true ), ev1_get(L), R = E-L"),
    ("ev1r07", raw"ev1_clear, prolog_listen(erase, ev1_r(x)), assertz(ev1_p(1)), ev1_get(R)"),
    ("ev1r08", raw"ev1_clear, prolog_listen(erase, ev1_rveto(t)), prolog_listen(erase, ev1_r(x), [as(last)]), recorda(ev1_k, v, Ref), ( erase(Ref) -> A = yes ; A = no ), ev1_get(L), R = A-L"),
    ("ev1g01", raw"ev1_clear, garbage_collect_clauses, prolog_listen(erase, ev1_e(g)), assertz(ev1_p(1)), retract(ev1_p(1)), garbage_collect_clauses, ev1_get(R)")
]

# the driver's whole output, one line per case after `ok`, filled by evidence/EV1/gen_rows.py --fill from swipl 10.1.19
const _EV_PINNED = [
    "ok",
    "t_ev1p01 c[116,95,101,118,49,112,48,49]/1(c[91,124,93]/2(c[45]/2(c[45]/2(a[97],a[97,115,115,101,114,116,122]),c[99,108]/2(c[101,118,49,95,112]/1(i1),a[116,114,117,101])),nil))",
    "t_ev1p02 c[116,95,101,118,49,112,48,50]/1(c[91,124,93]/2(c[45]/2(c[45]/2(a[97],a[97,115,115,101,114,116,97]),c[99,108]/2(c[101,118,49,95,112]/1(i1),a[116,114,117,101])),nil))",
    "t_ev1p03 c[116,95,101,118,49,112,48,51]/1(c[91,124,93]/2(c[45]/2(c[45]/2(a[97],a[97,115,115,101,114,116,122]),c[99,108]/2(c[101,118,49,95,112]/1(i1),a[116,114,117,101])),nil))",
    "t_ev1p04 c[116,95,101,118,49,112,48,52]/1(c[91,124,93]/2(c[45]/2(c[45]/2(a[97],a[97,115,115,101,114,116,122]),c[99,108]/2(c[101,118,49,95,112]/1(V0),c[101,118,49,95,113]/1(V0))),nil))",
    "t_ev1p05 c[116,95,101,118,49,112,48,53]/1(c[91,124,93]/2(c[45]/2(c[45]/2(a[97],a[114,101,116,114,97,99,116]),c[99,108]/2(c[101,118,49,95,112]/1(i1),a[116,114,117,101])),nil))",
    "t_ev1p06 c[116,95,101,118,49,112,48,54]/1(c[91,124,93]/2(c[45]/2(c[45]/2(a[97],a[114,101,116,114,97,99,116]),c[99,108]/2(c[101,118,49,95,112]/1(i1),a[116,114,117,101])),c[91,124,93]/2(c[45]/2(c[45]/2(a[97],a[114,101,116,114,97,99,116]),c[99,108]/2(c[101,118,49,95,112]/1(i2),a[116,114,117,101])),nil)))",
    "t_ev1p07 c[116,95,101,118,49,112,48,55]/1(nil)",
    "t_ev1p08 c[116,95,101,118,49,112,48,56]/1(c[91,124,93]/2(c[45]/2(c[45]/2(a[97],a[114,101,116,114,97,99,116]),c[99,108]/2(c[101,118,49,95,112]/1(i1),a[116,114,117,101])),nil))",
    "t_ev1p09 c[116,95,101,118,49,112,48,57]/1(c[45]/2(c[91,124,93]/2(i2,nil),c[91,124,93]/2(c[45]/2(c[45]/2(a[97],a[114,101,116,114,97,99,116,97,108,108]),c[115,116,97,114,116]/1(c[58]/2(a[117,115,101,114],c[101,118,49,95,112]/1(i1)))),c[91,124,93]/2(c[45]/2(c[45]/2(a[97],a[114,101,116,114,97,99,116]),c[99,108]/2(c[101,118,49,95,112]/1(i1),a[116,114,117,101])),c[91,124,93]/2(c[45]/2(c[45]/2(a[97],a[114,101,116,114,97,99,116]),c[99,108]/2(c[101,118,49,95,112]/1(i1),a[116,114,117,101])),nil)))))",
    "t_ev1p10 c[116,95,101,118,49,112,49,48]/1(c[91,124,93]/2(c[45]/2(c[45]/2(a[97],a[114,101,116,114,97,99,116,97,108,108]),c[115,116,97,114,116]/1(c[58]/2(a[117,115,101,114],c[101,118,49,95,112]/1(V0)))),c[91,124,93]/2(c[45]/2(c[45]/2(a[97],a[114,101,116,114,97,99,116,97,108,108]),c[101,110,100]/1(c[58]/2(a[117,115,101,114],c[101,118,49,95,112]/1(V1)))),nil)))",
    "t_ev1p11 c[116,95,101,118,49,112,49,49]/1(c[91,124,93]/2(c[45]/2(c[45]/2(a[97],a[114,101,116,114,97,99,116,97,108,108]),c[115,116,97,114,116]/1(c[58]/2(a[117,115,101,114],c[101,118,49,95,112]/1(i9)))),nil))",
    "t_ev1p12 c[116,95,101,118,49,112,49,50]/1(c[45]/2(c[91,124,93]/2(i1,c[91,124,93]/2(i3,nil)),c[91,124,93]/2(c[45]/2(c[45]/2(a[97],a[114,101,116,114,97,99,116,97,108,108]),c[115,116,97,114,116]/1(c[58]/2(a[117,115,101,114],c[101,118,49,95,112]/1(i2)))),c[91,124,93]/2(c[45]/2(c[45]/2(a[97],a[114,101,116,114,97,99,116]),c[99,108]/2(c[101,118,49,95,112]/1(i2),a[116,114,117,101])),nil))))",
    "t_ev1p13 c[116,95,101,118,49,112,49,51]/1(nil)",
    "t_ev1p14 c[116,95,101,118,49,112,49,52]/1(c[91,124,93]/2(c[45]/2(c[45]/2(a[97],a[97,115,115,101,114,116,122]),c[99,108]/2(c[58]/2(a[101,118,49,95,109],c[101,118,49,95,113]/1(i1)),a[116,114,117,101])),nil))",
    "t_ev1p15 c[116,95,101,118,49,112,49,53]/1(nil)",
    "t_ev1p16 c[116,95,101,118,49,112,49,54]/1(c[91,124,93]/2(c[45]/2(c[45]/2(a[97],a[97,115,115,101,114,116,122]),c[99,108]/2(c[101,118,49,95,112]/1(i1),a[116,114,117,101])),nil))",
    "t_ev1p17 c[116,95,101,118,49,112,49,55]/1(nil)",
    "t_ev1p18 c[116,95,101,118,49,112,49,56]/1(c[91,124,93]/2(c[45]/2(c[45]/2(a[109],a[97,115,115,101,114,116,122]),c[99,108]/2(c[101,118,49,95,112]/1(i1),a[116,114,117,101])),nil))",
    "t_ev1p19 c[116,95,101,118,49,112,49,57]/1(c[91,124,93]/2(c[45]/2(c[45]/2(a[97],a[97,115,115,101,114,116,122]),c[99,108]/2(c[101,118,49,95,112]/1(i1),a[116,114,117,101])),c[91,124,93]/2(c[45]/2(c[45]/2(a[97],a[114,101,116,114,97,99,116]),c[99,108]/2(c[101,118,49,95,112]/1(i1),a[116,114,117,101])),nil)))",
    "t_ev1o01 c[116,95,101,118,49,111,48,49]/1(c[91,124,93]/2(c[45]/2(c[45]/2(a[98],a[97,115,115,101,114,116,122]),c[99,108]/2(c[101,118,49,95,112]/1(i1),a[116,114,117,101])),c[91,124,93]/2(c[45]/2(c[45]/2(a[97],a[97,115,115,101,114,116,122]),c[99,108]/2(c[101,118,49,95,112]/1(i1),a[116,114,117,101])),nil)))",
    "t_ev1o02 c[116,95,101,118,49,111,48,50]/1(c[91,124,93]/2(c[45]/2(c[45]/2(a[97],a[97,115,115,101,114,116,122]),c[99,108]/2(c[101,118,49,95,112]/1(i1),a[116,114,117,101])),c[91,124,93]/2(c[45]/2(c[45]/2(a[98],a[97,115,115,101,114,116,122]),c[99,108]/2(c[101,118,49,95,112]/1(i1),a[116,114,117,101])),nil)))",
    "t_ev1o03 c[116,95,101,118,49,111,48,51]/1(c[91,124,93]/2(c[45]/2(c[45]/2(a[99],a[97,115,115,101,114,116,122]),c[99,108]/2(c[101,118,49,95,112]/1(i1),a[116,114,117,101])),c[91,124,93]/2(c[45]/2(c[45]/2(a[97],a[97,115,115,101,114,116,122]),c[99,108]/2(c[101,118,49,95,112]/1(i1),a[116,114,117,101])),c[91,124,93]/2(c[45]/2(c[45]/2(a[98],a[97,115,115,101,114,116,122]),c[99,108]/2(c[101,118,49,95,112]/1(i1),a[116,114,117,101])),nil))))",
    "t_ev1o04 c[116,95,101,118,49,111,48,52]/1(c[91,124,93]/2(c[45]/2(c[45]/2(a[116,119,111],a[97,115,115,101,114,116,122]),c[99,108]/2(c[101,118,49,95,112]/1(i1),a[116,114,117,101])),nil))",
    "t_ev1o05 c[116,95,101,118,49,111,48,53]/1(c[91,124,93]/2(c[45]/2(c[45]/2(a[97],a[97,115,115,101,114,116,122]),c[99,108]/2(c[101,118,49,95,112]/1(i1),a[116,114,117,101])),c[91,124,93]/2(c[45]/2(c[45]/2(a[116,119,111],a[97,115,115,101,114,116,122]),c[99,108]/2(c[101,118,49,95,112]/1(i1),a[116,114,117,101])),c[91,124,93]/2(c[45]/2(c[45]/2(a[98],a[97,115,115,101,114,116,122]),c[99,108]/2(c[101,118,49,95,112]/1(i1),a[116,114,117,101])),nil))))",
    "t_ev1o06 c[116,95,101,118,49,111,48,54]/1(c[91,124,93]/2(c[45]/2(c[45]/2(a[116,119,111],a[97,115,115,101,114,116,122]),c[99,108]/2(c[101,118,49,95,112]/1(i1),a[116,114,117,101])),c[91,124,93]/2(c[45]/2(c[45]/2(a[111,110,101],a[97,115,115,101,114,116,122]),c[99,108]/2(c[101,118,49,95,112]/1(i1),a[116,114,117,101])),nil)))",
    "t_ev1o07 c[116,95,101,118,49,111,48,55]/1(c[91,124,93]/2(c[45]/2(c[45]/2(a[97],a[97,115,115,101,114,116,122]),c[99,108]/2(c[101,118,49,95,112]/1(i1),a[116,114,117,101])),c[91,124,93]/2(c[45]/2(c[45]/2(a[97],a[97,115,115,101,114,116,122]),c[99,108]/2(c[101,118,49,95,112]/1(i1),a[116,114,117,101])),nil)))",
    "t_ev1o08 c[116,95,101,118,49,111,48,56]/1(c[91,124,93]/2(c[45]/2(c[45]/2(a[98],a[97,115,115,101,114,116,122]),c[99,108]/2(c[101,118,49,95,112]/1(i1),a[116,114,117,101])),c[91,124,93]/2(c[45]/2(c[45]/2(a[97],a[97,115,115,101,114,116,122]),c[99,108]/2(c[101,118,49,95,112]/1(i1),a[116,114,117,101])),nil)))",
    "t_ev1o09 c[116,95,101,118,49,111,48,57]/1(c[91,124,93]/2(c[45]/2(c[45]/2(a[97],a[97,115,115,101,114,116,122]),c[99,108]/2(c[101,118,49,95,112]/1(i1),a[116,114,117,101])),c[91,124,93]/2(c[45]/2(c[45]/2(a[98],a[97,115,115,101,114,116,122]),c[99,108]/2(c[101,118,49,95,113]/1(i1),a[116,114,117,101])),nil)))",
    "t_ev1o10 c[116,95,101,118,49,111,49,48]/1(c[91,124,93]/2(c[45]/2(c[45]/2(a[116,104,114,101,101],a[97,115,115,101,114,116,122]),c[99,108]/2(c[101,118,49,95,112]/1(i1),a[116,114,117,101])),c[91,124,93]/2(c[45]/2(c[45]/2(a[97],a[97,115,115,101,114,116,122]),c[99,108]/2(c[101,118,49,95,112]/1(i1),a[116,114,117,101])),nil)))",
    "t_ev1o11 c[116,95,101,118,49,111,49,49]/1(c[91,124,93]/2(c[45]/2(c[45]/2(a[97],c[101,118,49,95,116]/1(a[116,119,111])),a[97,115,115,101,114,116,122]),nil))",
    "t_ev1u01 c[116,95,101,118,49,117,48,49]/1(c[91,124,93]/2(c[45]/2(c[45]/2(a[98],a[97,115,115,101,114,116,122]),c[99,108]/2(c[101,118,49,95,112]/1(i1),a[116,114,117,101])),nil))",
    "t_ev1u02 c[116,95,101,118,49,117,48,50]/1(c[91,124,93]/2(c[45]/2(c[45]/2(i2,a[97,115,115,101,114,116,122]),c[99,108]/2(c[101,118,49,95,112]/1(i1),a[116,114,117,101])),nil))",
    "t_ev1u03 c[116,95,101,118,49,117,48,51]/1(c[91,124,93]/2(c[45]/2(c[45]/2(a[97],a[97,115,115,101,114,116,122]),c[99,108]/2(c[101,118,49,95,112]/1(i1),a[116,114,117,101])),c[91,124,93]/2(c[45]/2(c[45]/2(i1,a[97,115,115,101,114,116,122]),c[99,108]/2(c[101,118,49,95,112]/1(i1),a[116,114,117,101])),nil)))",
    "t_ev1u04 c[116,95,101,118,49,117,48,52]/1(c[91,124,93]/2(c[45]/2(c[45]/2(i1,a[97,115,115,101,114,116,122]),c[99,108]/2(c[101,118,49,95,112]/1(i1),a[116,114,117,101])),nil))",
    "t_ev1u05 c[116,95,101,118,49,117,48,53]/1(a[121,101,115])",
    "t_ev1u06 c[116,95,101,118,49,117,48,54]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[101,118,101,110,116],a[110,111,115,117,99,104,101,118,101,110,116])))",
    "t_ev1u07 c[116,95,101,118,49,117,48,55]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,97,108,108,97,98,108,101],i1)))",
    "t_ev1u08 c[116,95,101,118,49,117,48,56]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,97,108,108,97,98,108,101],i1)))",
    "t_ev1u09 c[116,95,101,118,49,117,48,57]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_ev1u10 c[116,95,101,118,49,117,49,48]/1(c[45]/2(a[121,101,115],c[91,124,93]/2(c[45]/2(c[45]/2(a[97],a[97,115,115,101,114,116,122]),c[99,108]/2(c[101,118,49,95,112]/1(i1),a[116,114,117,101])),nil)))",
    "t_ev1u11 c[116,95,101,118,49,117,49,49]/1(nil)",
    "t_ev1u12 c[116,95,101,118,49,117,49,50]/1(nil)",
    "t_ev1u13 c[116,95,101,118,49,117,49,51]/1(nil)",
    "t_ev1u14 c[116,95,101,118,49,117,49,52]/1(nil)",
    "t_ev1u15 c[116,95,101,118,49,117,49,53]/1(nil)",
    "t_ev1u16 c[116,95,101,118,49,117,49,54]/1(c[91,124,93]/2(c[45]/2(c[45]/2(c[102]/1(i1),a[97,115,115,101,114,116,122]),c[99,108]/2(c[101,118,49,95,112]/1(i1),a[116,114,117,101])),nil))",
    "t_ev1u17 c[116,95,101,118,49,117,49,55]/1(a[121,101,115])",
    "t_ev1v01 c[116,95,101,118,49,118,48,49]/1(c[45]/2(c[45]/2(a[110,111],nil),c[91,124,93]/2(c[45]/2(c[45]/2(a[118],a[97,115,115,101,114,116,122]),c[99,108]/2(c[101,118,49,95,112]/1(i1),a[116,114,117,101])),nil)))",
    "t_ev1v02 c[116,95,101,118,49,118,48,50]/1(c[45]/2(c[45]/2(a[110,111],c[91,124,93]/2(i1,nil)),c[91,124,93]/2(c[45]/2(c[45]/2(a[118],a[114,101,116,114,97,99,116]),c[99,108]/2(c[101,118,49,95,112]/1(i1),a[116,114,117,101])),nil)))",
    "t_ev1v03 c[116,95,101,118,49,118,48,51]/1(c[45]/2(a[110,111],c[91,124,93]/2(c[45]/2(c[45]/2(a[118],a[97,115,115,101,114,116,122]),c[99,108]/2(c[101,118,49,95,112]/1(i1),a[116,114,117,101])),nil)))",
    "t_ev1v04 c[116,95,101,118,49,118,48,52]/1(c[45]/2(a[110,111],c[91,124,93]/2(c[45]/2(c[45]/2(a[119],a[97,115,115,101,114,116,122]),c[99,108]/2(c[101,118,49,95,112]/1(i1),a[116,114,117,101])),c[91,124,93]/2(c[45]/2(c[45]/2(a[118],a[97,115,115,101,114,116,122]),c[99,108]/2(c[101,118,49,95,112]/1(i1),a[116,114,117,101])),nil))))",
    "t_ev1v05 c[116,95,101,118,49,118,48,53]/1(c[45]/2(c[45]/2(a[110,111],c[91,124,93]/2(i1,c[91,124,93]/2(i2,nil))),c[91,124,93]/2(c[45]/2(c[45]/2(a[118],a[114,101,116,114,97,99,116,97,108,108]),c[115,116,97,114,116]/1(c[58]/2(a[117,115,101,114],c[101,118,49,95,112]/1(V0)))),nil)))",
    "t_ev1v06 c[116,95,101,118,49,118,48,54]/1(c[45]/2(c[45]/2(a[110,111],nil),c[91,124,93]/2(c[45]/2(c[45]/2(a[118],a[114,101,116,114,97,99,116,97,108,108]),c[115,116,97,114,116]/1(c[58]/2(a[117,115,101,114],c[101,118,49,95,112]/1(V0)))),c[91,124,93]/2(c[45]/2(c[45]/2(a[118],a[114,101,116,114,97,99,116]),c[99,108]/2(c[101,118,49,95,112]/1(i1),a[116,114,117,101])),c[91,124,93]/2(c[45]/2(c[45]/2(a[118],a[114,101,116,114,97,99,116]),c[99,108]/2(c[101,118,49,95,112]/1(i2),a[116,114,117,101])),c[91,124,93]/2(c[45]/2(c[45]/2(a[118],a[114,101,116,114,97,99,116,97,108,108]),c[101,110,100]/1(c[58]/2(a[117,115,101,114],c[101,118,49,95,112]/1(V1)))),nil))))))",
    "t_ev1v07 c[116,95,101,118,49,118,48,55]/1(c[45]/2(c[45]/2(a[110,111],c[91,124,93]/2(i1,nil)),c[91,124,93]/2(c[45]/2(c[45]/2(a[118],a[114,101,116,114,97,99,116]),c[99,108]/2(c[101,118,49,95,112]/1(i1),a[116,114,117,101])),nil)))",
    "t_ev1v08 c[116,95,101,118,49,118,48,56]/1(c[45]/2(c[45]/2(c[101,118,49,95,98,97,108,108]/1(a[116]),nil),c[91,124,93]/2(c[45]/2(c[45]/2(a[116],a[97,115,115,101,114,116,122]),c[99,108]/2(c[101,118,49,95,112]/1(i1),a[116,114,117,101])),nil)))",
    "t_ev1v09 c[116,95,101,118,49,118,48,57]/1(c[45]/2(c[45]/2(c[101,118,49,95,98,97,108,108]/1(a[116]),c[91,124,93]/2(i1,nil)),c[91,124,93]/2(c[45]/2(c[45]/2(a[116],a[114,101,116,114,97,99,116]),c[99,108]/2(c[101,118,49,95,112]/1(i1),a[116,114,117,101])),nil)))",
    "t_ev1v10 c[116,95,101,118,49,118,49,48]/1(c[45]/2(c[101,118,49,95,98,97,108,108]/1(a[116]),c[91,124,93]/2(c[45]/2(c[45]/2(a[116],a[97,115,115,101,114,116,122]),c[99,108]/2(c[101,118,49,95,112]/1(i1),a[116,114,117,101])),nil)))",
    "t_ev1v11 c[116,95,101,118,49,118,49,49]/1(c[45]/2(c[45]/2(c[101,118,49,95,98,97,108,108]/1(a[116]),c[91,124,93]/2(i1,nil)),c[91,124,93]/2(c[45]/2(c[45]/2(a[116],a[114,101,116,114,97,99,116,97,108,108]),c[115,116,97,114,116]/1(c[58]/2(a[117,115,101,114],c[101,118,49,95,112]/1(V0)))),nil)))",
    "t_ev1v12 c[116,95,101,118,49,118,49,50]/1(c[45]/2(a[110,111],c[91,124,93]/2(c[45]/2(c[45]/2(a[118],a[97,115,115,101,114,116,122]),c[99,108]/2(c[101,118,49,95,112]/1(i1),a[116,114,117,101])),nil)))",
    "t_ev1e01 c[116,95,101,118,49,101,48,49]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[97,115],a[109,105,100,100,108,101])))",
    "t_ev1e02 c[116,95,101,118,49,101,48,50]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],i1)))",
    "t_ev1e03 c[116,95,101,118,49,101,48,51]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,97,108,108,97,98,108,101],i1)))",
    "t_ev1e04 c[116,95,101,118,49,101,48,52]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_ev1e05 c[116,95,101,118,49,101,48,53]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],a[97])))",
    "t_ev1e06 c[116,95,101,118,49,101,48,54]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[110,111,116,95,108,101,115,115,95,116,104,97,110,95,122,101,114,111],i-1)))",
    "t_ev1e07 c[116,95,101,118,49,101,48,55]/1(nil)",
    "t_ev1e08 c[116,95,101,118,49,101,48,56]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[108,105,115,116],a[102,111,111])))",
    "t_ev1e09 c[116,95,101,118,49,101,48,57]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_ev1e10 c[116,95,101,118,49,101,49,48]/1(a[121,101,115])",
    "t_ev1e11 c[116,95,101,118,49,101,49,49]/1(a[121,101,115])",
    "t_ev1e12 c[116,95,101,118,49,101,49,50]/1(c[91,124,93]/2(c[45]/2(c[45]/2(a[97],a[97,115,115,101,114,116,122]),c[99,108]/2(c[101,118,49,95,112]/1(i1),a[116,114,117,101])),nil))",
    "t_ev1r01 c[116,95,101,118,49,114,48,49]/1(c[91,124,93]/2(c[45]/2(c[45]/2(a[120],a[101,114,97,115,101]),c[112,114,101,115,101,110,116]/1(a[118])),nil))",
    "t_ev1r02 c[116,95,101,118,49,114,48,50]/1(c[91,124,93]/2(c[45]/2(c[45]/2(a[121],a[101,114,97,115,101]),c[112,114,101,115,101,110,116]/1(a[118])),c[91,124,93]/2(c[45]/2(c[45]/2(a[120],a[101,114,97,115,101]),c[112,114,101,115,101,110,116]/1(a[118])),nil)))",
    "t_ev1r03 c[116,95,101,118,49,114,48,51]/1(c[45]/2(c[45]/2(c[101,118,49,95,98,97,108,108]/1(a[116]),nil),c[91,124,93]/2(c[45]/2(c[45]/2(a[116],a[101,114,97,115,101]),c[112,114,101,115,101,110,116]/1(a[118])),nil)))",
    "t_ev1r04 c[116,95,101,118,49,114,48,52]/1(c[45]/2(c[45]/2(a[121,101,115],nil),c[91,124,93]/2(c[45]/2(c[45]/2(a[116],a[101,114,97,115,101]),c[112,114,101,115,101,110,116]/1(a[118])),nil)))",
    "t_ev1r05 c[116,95,101,118,49,114,48,53]/1(c[91,124,93]/2(c[45]/2(c[45]/2(a[120],a[101,114,97,115,101]),c[112,114,101,115,101,110,116]/1(a[118])),nil))",
    "t_ev1r06 c[116,95,101,118,49,114,48,54]/1(c[45]/2(V0,c[91,124,93]/2(c[45]/2(c[45]/2(a[120],a[101,114,97,115,101]),c[112,114,101,115,101,110,116]/1(a[118])),nil)))",
    "t_ev1r07 c[116,95,101,118,49,114,48,55]/1(nil)",
    "t_ev1r08 c[116,95,101,118,49,114,48,56]/1(c[45]/2(a[121,101,115],c[91,124,93]/2(c[45]/2(c[45]/2(a[116],a[101,114,97,115,101]),c[112,114,101,115,101,110,116]/1(a[118])),nil)))",
    "t_ev1g01 c[116,95,101,118,49,103,48,49]/1(c[91,124,93]/2(c[45]/2(c[45]/2(a[103],a[101,114,97,115,101]),a[103,111,110,101]),nil))"
]

# rows the kernel answers white-box (the case calls garbage_collect_clauses/0, which a case of this file cannot rely on)
const _EV_WHITEBOX = ["t_ev1g01"]

function _ev_file()::Tuple{String, Vector{String}}
    names = ["t_$(id)" for (id, _) in _EV_CASES]
    text =
        _EV_PROGRAM * join([
            "t_$(id)(R) :- catch(($g), error(SsuE, _), R = raised(SsuE)).\n" for
            (id, g) in _EV_CASES
        ])
    f = joinpath(mktempdir(), "event.pl")
    write(f, text)
    return f, names
end

"A fresh kernel with the file consulted: `(gd, ld, first line of the driver's output)`."
function _ev_load(path::String)
    gd = LK.PL_global_data{_EV}()
    ld = LK.PL_local_data{_EV}(gd)
    st, ball, _ = LK.load_file!(gd, ld, path)
    return gd, ld, (st === :ok ? "ok" : "exc " * _ev_enc(ball::_EV))
end

"The driver's line for `pred/1` (every answer, at most 50), the functor written as `asname`."
function _ev_ask(gd, ld, pred::String, asname::String=pred)::String
    proc = LK.isCurrentProcedure(sym_key(_evs(pred)), 1, LK.MODULE_user(gd))
    (proc === nothing || !LK.isDefinedProcedure(gd, proc)) && return "$asname undefined"
    sols = String[]
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 1)
    LK.putSlotValue!(ld, a + 1, mk_var(_EV, LK.fresh_var_keys!(1)), LK.PutVarMap())
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    n = 0
    while (n += 1) <= 50
        rc = LK.PL_next_solution(gd, ld, qid)
        if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
            push!(sols, _ev_enc(mk_expr(_EV, _EV[_evs(asname), lk_answers(ld, (a:a)...)...])))
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
    return asname * join(" " .* sols)
end

"The kernel's lines for `names` after consulting `path` (a white-box name gets `nothing` instead of a line)."
function _ev_kernel(path::String, names::Vector{String})
    gd, ld, st = _ev_load(path)
    out = [st]
    for name in names
        push!(out, name in _EV_WHITEBOX ? "" : _ev_ask(gd, ld, name))
    end
    return out, gd, ld
end

@testset "event hooks as swipl's (ev1p, ev1o, ev1u, ev1v, ev1e, ev1r)" begin
    f, names = _ev_file()
    kl, _, _ = _ev_kernel(f, names)
    @test length(kl) == length(_EV_PINNED)
    for (k, p) in zip(kl, _EV_PINNED)
        first(split(p, ' ')) in _EV_WHITEBOX && continue
        k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
        @test k == p
    end
end

@testset "the clause GC announces an erased clause (white-box, ev1g01)" begin
    # swipl's case is: clear, GC (flush the garbage of the earlier rows), listen, assertz, retract, GC, log.
    # A fresh kernel has no earlier garbage, so: the first half, the Julia GC, the second half.
    f, _ = _ev_file()
    gd, ld, st = _ev_load(f)
    @test st == "ok"
    pin = only(filter(l -> startswith(l, "t_ev1g01 "), _EV_PINNED))
    a = _ev_ask(gd, ld, "ev1_gc_a")
    @test occursin("(a[111,107])", a)                                  # ok: the listener is registered
    @test LK.pl_garbage_collect_clauses!(gd, ld)
    @test _ev_ask(gd, ld, "ev1_gc_b", "t_ev1g01") == pin
end

@testset "the event rows are not vacuous" begin
    @test _EV_PINNED[1] == "ok"
    @test length(_EV_PINNED) == length(_EV_CASES) + 1
    for pre in ("ev1p", "ev1o", "ev1u", "ev1v", "ev1e", "ev1r", "ev1g")
        ids = [id for (id, _) in _EV_CASES if startswith(id, pre)]
        @test !isempty([l for l in _EV_PINNED if any(id -> startswith(l, "t_$id "), ids)])
    end
    nonempty(id) = !endswith(only(filter(l -> startswith(l, "t_$id "), _EV_PINNED)), "(nil)")
    @test nonempty("ev1p01") && nonempty("ev1o03") && nonempty("ev1r02") && nonempty("ev1g01")   # events were delivered
    @test !nonempty("ev1p15") && !nonempty("ev1p17") && !nonempty("ev1u11")                     # and withheld
    @test count(l -> occursin("raised", l), _EV_PINNED) >= 10                                    # errors were raised
end

@testset "the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    @test length(_EV_PINNED) == length(_EV_CASES) + 1
    if swipl === nothing
        @info "EV1 LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        f, names = _ev_file()
        @test _ev_swipl_lines(f, names) == _EV_PINNED
    end
end
