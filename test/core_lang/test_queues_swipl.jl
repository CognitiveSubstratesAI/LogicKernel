# ORIGINAL: a LIVE differential of the USER MESSAGE QUEUES of pl-thread.c against swipl at the pin (swipl-devel 18168e62; swipl 10.1.20):
# message_queue_create/1,2, message_queue_destroy/1, message_queue_property/2, message_queue_set/2, is_message_queue/1, thread_send_message/2,3,
# thread_get_message/1,2,3 and thread_peek_message/1,2 (src/pl-queue.jl); rows qa (no queue yet), qc (create), qp (property), qd (destroy),
# qs (set), qm (send, get, peek), qo (the deadline options of /3), qe (engines), qz (the table at the end).
#   * A PROGRAM of cases `t_<id>(R)` run in order in one database, each wrapped in `catch(Goal, error(E, _), R = raised(E))`; the driver is
#     test_thread_ops_swipl.jl's (`enc`oded answers). A row that wants the error's CONTEXT catches it itself (`cx/2`: `R = Formal-Context`).
#     A queue blob and an engine handle are never printed (they carry an address): such rows compare or print a kind.
#   * Every swipl answer line is swipl's, PINNED (swipl 10.1.20, the pin binary, two runs byte-identical, `queues_gen_rows.py --fill`); with
#     `swipl` on PATH the live answers are compared with the pins too.
#   * ORDER = the order of `_TQ_CASES`: rows qa first (no queue was ever created: `queueTable` is NULL), qs08 changes main's queue (and restores it).
#   * QUIRK (qp03, qp05): a thread's queue has no name (q->id is 0), yet `message_queue_property(main, alias(A))` SUCCEEDS with A unbound.
#   * DIVERGES, rows run only on the kernel (`_TQ_KD`): the queue properties of `message_queue_property(Q, P)` with Q unbound come in CREATION
#     order (upstream: hash order); no row pins that order (every enumerating row is sorted or has one answer).
#   * REFUSED by name (TH1), kernel only (never run in swipl: it would wait for ever): qr01-qr09, each its own database (a NotPortedError ends
#     the run); each asserts the exception's step, culprit and `what`. pin swipl cannot answer (it waits forever).
#   * With a deadline the kernel fails AT ONCE where swipl sleeps until it: the rows use `timeout(0)`, `timeout(0.01)` and a past deadline.
#   * UNVERIFIED on the kernel (nothing was compiled when these rows were written): every kernel answer; the gate decides.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: ALL — src/pl-queue.jl: all three term types: the predicates take the term type through the term interface (atoms, integers, compounds)
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TQ = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_tqs(x) = lk_sym(_TQ, Symbol(x))

_tq_codes(s::AbstractString) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _tq_enc(t::_TQ, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _tq_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _tq_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _tq_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_tq_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

# hand-built encodings of expected answers (never read from swipl)
_tq_a(s) = "a" * _tq_codes(s)
_tq_c(name, args...) = "c" * _tq_codes(name) * "/$(length(args))(" * join(args, ",") * ")"
_tq_list(xs) = isempty(xs) ? "nil" : _tq_c("[|]", xs[1], _tq_list(xs[2:end]))

# the swipl side: test/core_lang/test_mutex_swipl.jl's driver (consult, then every answer of each t_<id>/1, `enc`oded)
const _TQ_DRIVER = raw"""
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
function _tq_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _TQ_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(pipeline(`swipl -q $f`; stdin=devnull, stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

# helpers of the rows: drain/2 (the messages of a queue, in order, taken out with /1 /2 and peek only), roundtrip/2 (send a term to a fresh
# queue and read it back), cx/2 (the Formal and the Context of an error), ek/2 (the kind of an existence error), pk/2 (the kind of a
# permission error).
const _TQ_PRELUDE = raw"""
drain(Q, L) :- ( thread_peek_message(Q, X) -> thread_get_message(Q, X), L = [X|T], drain(Q, T) ; L = [] ).
roundtrip(T, R) :- message_queue_create(Q), thread_send_message(Q, T), thread_get_message(Q, R).
cx(G, R) :- catch(G, error(E, C), true), R = E-C.
ek(G, K) :- catch(G, error(E, _), true), ( nonvar(E), E = existence_error(K0, _) -> K = K0 ; K = none ).
pk(G, R) :- catch(G, error(E, _), true), ( nonvar(E), E = permission_error(A, B, _) -> R = A-B ; R = none ).
"""

const _TQ_CASES = [
    # qa: no queue was ever created (swipl: queueTable is NULL), the thread queue of main is reachable
    # kd: swipl's `swipl -q file` start has made one anonymous queue already (the `-g` start has none): the table is not empty there
    ("qa01", raw"findall(P, message_queue_property(_, P), R)"),
    ("qa02", raw"message_queue_property(_, foo(_)), R = yes"),
    ("qa03", raw"is_message_queue(main), R = yes"),
    ("qa04", raw"findall(P, message_queue_property(main, P), R)"),
    ("qa05", raw"thread_get_message(99, _, [timeout(0)])"),
    ("qa06", raw"thread_send_message(99, x)"),
    ("qa07", raw"thread_peek_message(99, x)"),
    ("qa08", raw"thread_send_message(nosuchq, x)"),
    # qc: message_queue_create/1,2
    ("qc01", raw"message_queue_create(Q), is_message_queue(Q), R = yes"),
    ("qc02", raw"message_queue_create(qc02q), R = ok"),
    ("qc03", raw"message_queue_create(qc02q), R = yes"),
    ("qc04", raw"cx(message_queue_create(qc02q), R)"),
    ("qc05", raw"message_queue_create(main)"),
    ("qc06", raw"cx(message_queue_create(main), R)"),
    ("qc07", raw"message_queue_create(f(x))"),
    ("qc08", raw"cx(message_queue_create(f(x)), R)"),
    ("qc09", raw"message_queue_create(1)"),
    ("qc10", raw"message_queue_create(\"str\")"),
    ("qc11", raw"message_queue_create(Q), pk(message_queue_create(Q), R)"),
    ("qc12", raw"message_queue_create(Q), findall(P, message_queue_property(Q, P), R)"),
    (
        "qc13",
        raw"message_queue_create(Q1), message_queue_create(Q2), ( Q1 == Q2 -> R = same ; R = distinct )"
    ),
    ("qc14", raw"message_queue_create(Q), blob(Q, T), R = T"),
    ("qc15", raw"message_queue_create(Q), ( atom(Q) -> R = atom ; R = notatom )"),
    ("qc16", raw"message_queue_create(Q, [alias(qc16q), max_size(2)]), R = Q"),
    ("qc17", raw"message_queue_create(zz, [alias(qc17q)])"),
    ("qc18", raw"cx(message_queue_create(zz, [alias(qc18q)]), R)"),
    ("qc19", raw"message_queue_create(qc19q, [alias(qc19q)]), R = ok"),
    ("qc20", raw"message_queue_create(_, [max_size(-1)])"),
    ("qc21", raw"cx(message_queue_create(_, [max_size(-1)]), R)"),
    ("qc22", raw"message_queue_create(_, [max_size(a)])"),
    ("qc23", raw"message_queue_create(_, [alias(1)])"),
    ("qc24", raw"message_queue_create(_, foo)"),
    ("qc25", raw"cx(message_queue_create(_, foo), R)"),
    ("qc26", raw"message_queue_create(_, _)"),
    ("qc27", raw"message_queue_create(Q, []), is_message_queue(Q), R = yes"),
    ("qc28", raw"message_queue_create(Q, [foo(1)]), is_message_queue(Q), R = yes"),
    ("qc29", raw"message_queue_create(_, [max_size(1.5)])"),
    ("qc30", raw"message_queue_create(_, [alias(main)])"),
    ("qc31", raw"cx(message_queue_create(_, [alias(qc16q)]), R)"),
    (
        "qc32",
        raw"message_queue_create(Q, [max_size(3), max_size(2)]), message_queue_property(Q, max_size(R))"
    ),
    (
        "qc33",
        raw"message_queue_create(_, [alias(qc33q), max_size(0)]), findall(P, message_queue_property(qc33q, P), R)"
    ),
    ("qc34", raw"message_queue_create(_, [alias(_)])"),
    ("qc35", raw"message_queue_create(_, [max_size(_)])"),
    ("qc36", raw"message_queue_create(Q, [alias=qc36q]), R = Q"),
    (
        "qc37",
        raw"message_queue_create(Q, [max_size(1000000000000000000000)]), is_message_queue(Q), R = yes"
    ),
    (
        "qc38",
        raw"message_queue_create(Q, [alias(qc38q), max_size(4)]), is_message_queue(qc38q), message_queue_property(Q, max_size(R))"
    ),
    ("qc39", raw"message_queue_create(_, [alias(a), alias(b)]), R = ok"),
    # qp: message_queue_property/2
    (
        "qp01",
        raw"message_queue_create(_, [alias(qp01q), max_size(2)]), findall(P, message_queue_property(qp01q, P), R)"
    ),
    ("qp02", raw"message_queue_create(Q), findall(P, message_queue_property(Q, P), R)"),
    ("qp03", raw"findall(P, message_queue_property(main, P), R)"),
    ("qp04", raw"findall(P, message_queue_property(1, P), R)"),
    ("qp05", raw"message_queue_property(main, alias(A)), var(A), R = quirk"),
    (
        "qp06",
        raw"message_queue_create(Q), \+ message_queue_property(Q, alias(_)), R = fails"
    ),
    ("qp07", raw"message_queue_property(nosuchq, P), R = P"),
    ("qp08", raw"cx(message_queue_property(nosuchq, _), R)"),
    ("qp09", raw"message_queue_property(f(x), _)"),
    ("qp10", raw"cx(message_queue_property(f(x), _), R)"),
    ("qp11", raw"message_queue_property(_, foo(_))"),
    ("qp12", raw"message_queue_property(qp01q, 1)"),
    ("qp13", raw"cx(message_queue_property(qp01q, 1), R)"),
    ("qp14", raw"message_queue_property(qp01q, foo)"),
    ("qp15", raw"cx(message_queue_property(qp01q, foo), R)"),
    ("qp16", raw"message_queue_property(qp01q, size(S)), R = S"),
    ("qp17", raw"message_queue_property(qp01q, max_size(S)), R = S"),
    ("qp18", raw"message_queue_property(qp01q, waiting(_)), R = yes"),
    ("qp19", raw"message_queue_property(qp01q, alias(A)), R = A"),
    (
        "qp20",
        raw"message_queue_property(Q, alias(qp01q)), ( Q == qp01q -> R = same ; R = other )"
    ),
    ("qp21", raw"findall(A, message_queue_property(_, alias(A)), L), msort(L, R)"),
    (
        "qp22",
        raw"call_cleanup(message_queue_property(qp01q, max_size(M)), Det = true), R = Det-M"
    ),
    (
        "qp23",
        raw"call_cleanup(message_queue_property(qp01q, P), Det = true), ( Det == true -> R = det-P ; R = nondet-P )"
    ),
    (
        "qp24",
        raw"once(message_queue_property(Q, alias(qp01q))), ( Q == qp01q -> R = once ; R = other )"
    ),
    ("qp25", raw"message_queue_property(qp01q, size(1)), R = yes"),
    ("qp26", raw"message_queue_property(qp01q, max_size(3)), R = yes"),
    ("qp27", raw"message_queue_property(qp01q, alias(other)), R = yes"),
    ("qp28", raw"message_queue_property(0, _)"),
    ("qp29", raw"message_queue_property(99, _)"),
    (
        "qp30",
        raw"message_queue_property(_, alias(qp01q)), findall(M, message_queue_property(_, max_size(M)), L), msort(L, R)"
    ),
    (
        "qp31",
        raw"findall(A-S, ( message_queue_property(Q, alias(A)), message_queue_property(Q, size(S)), memberchk(A, [qp01q, qc16q]) ), L), msort(L, R)"
    ),
    # qd: message_queue_destroy/1
    ("qd01", raw"message_queue_destroy(main)"),
    ("qd02", raw"cx(message_queue_destroy(main), R)"),
    ("qd03", raw"message_queue_destroy(1)"),
    ("qd04", raw"message_queue_destroy(nosuchq)"),
    ("qd05", raw"cx(message_queue_destroy(nosuchq), R)"),
    ("qd06", raw"message_queue_destroy(_)"),
    ("qd07", raw"message_queue_destroy(f(x))"),
    ("qd08", raw"message_queue_create(Q), message_queue_destroy(Q), R = ok"),
    (
        "qd09",
        raw"message_queue_create(Q), message_queue_destroy(Q), ek(message_queue_destroy(Q), R)"
    ),
    (
        "qd10",
        raw"message_queue_create(Q), message_queue_destroy(Q), ( is_message_queue(Q) -> R = yes ; R = no )"
    ),
    (
        "qd11",
        raw"message_queue_create(qd11q), message_queue_destroy(qd11q), thread_send_message(qd11q, x)"
    ),
    (
        "qd12",
        raw"message_queue_create(qd12q), message_queue_destroy(qd12q), message_queue_create(qd12q), R = ok"
    ),
    (
        "qd13",
        raw"message_queue_create(qd13q), thread_send_message(qd13q, x), message_queue_destroy(qd13q), message_queue_create(qd13q), findall(P, message_queue_property(qd13q, P), R)"
    ),
    (
        "qd14",
        raw"message_queue_create(Q), message_queue_destroy(Q), ek(thread_send_message(Q, x), R)"
    ),
    ("qd15", raw"message_queue_destroy(0)"),
    ("qd16", raw"message_queue_destroy(-1)"),
    (
        "qd17",
        raw"message_queue_create(_, [alias(qd17q)]), message_queue_destroy(qd17q), \+ message_queue_property(_, alias(qd17q)), R = gone"
    ),
    (
        "qd18",
        raw"message_queue_create(Q), message_queue_destroy(Q), ek(message_queue_property(Q, _), R)"
    ),
    (
        "qd19",
        raw"message_queue_create(Q), message_queue_destroy(Q), ek(thread_get_message(Q, _, [timeout(0)]), R)"
    ),
    (
        "qd20",
        raw"message_queue_create(Q), message_queue_destroy(Q), ek(thread_peek_message(Q, _), R)"
    ),
    (
        "qd21",
        raw"message_queue_create(Q), message_queue_destroy(Q), ek(message_queue_set(Q, max_size(1)), R)"
    ),
    ("qd22", raw"message_queue_destroy(1.5)"),
    (
        "qd23",
        raw"message_queue_destroy(qp01q), message_queue_create(_, [alias(qp01q), max_size(2)]), R = ok"
    ),
    # qs: message_queue_set/2
    (
        "qs01",
        raw"message_queue_create(_, [alias(qs01q)]), message_queue_set(qs01q, max_size(5)), message_queue_property(qs01q, max_size(R))"
    ),
    ("qs02", raw"message_queue_set(qs01q, max_size(-1))"),
    ("qs03", raw"cx(message_queue_set(qs01q, max_size(-1)), R)"),
    ("qs04", raw"message_queue_set(qs01q, foo(1))"),
    ("qs05", raw"cx(message_queue_set(qs01q, foo(1)), R)"),
    ("qs06", raw"message_queue_set(qs01q, foo)"),
    ("qs07", raw"cx(message_queue_set(qs01q, foo), R)"),
    (
        "qs08",
        raw"message_queue_set(main, max_size(3)), message_queue_property(main, max_size(M)), message_queue_set(main, max_size(0)), \+ message_queue_property(main, max_size(_)), R = M"
    ),
    ("qs09", raw"message_queue_set(nosuchq, max_size(1))"),
    ("qs10", raw"message_queue_set(_, max_size(1))"),
    ("qs11", raw"message_queue_set(qs01q, _)"),
    ("qs12", raw"message_queue_set(qs01q, max_size(a))"),
    ("qs13", raw"message_queue_set(qs01q, max_size(_))"),
    ("qs14", raw"message_queue_set(qs01q, max_size(2.5))"),
    (
        "qs15",
        raw"message_queue_set(qs01q, max_size(0)), \+ message_queue_property(qs01q, max_size(_)), R = none"
    ),
    ("qs16", raw"message_queue_set(qs01q, 1)"),
    ("qs17", raw"message_queue_set(qs01q, foo(1, 2))"),
    ("qs18", raw"message_queue_set(f(x), max_size(1))"),
    # qm: thread_send_message/2, thread_get_message/1,2, thread_peek_message/1,2
    (
        "qm01",
        raw"message_queue_create(Q), thread_send_message(Q, a), thread_send_message(Q, b), thread_send_message(Q, c), thread_get_message(Q, b), drain(Q, R)"
    ),
    (
        "qm02",
        raw"message_queue_create(Q), thread_send_message(Q, g(1, x)), thread_send_message(Q, g(2, y)), thread_get_message(Q, g(A, y)), drain(Q, L), R = A-L"
    ),
    (
        "qm03",
        raw"message_queue_create(Q), thread_send_message(Q, g(1, x)), thread_send_message(Q, g(2, y)), thread_peek_message(Q, g(A, y)), drain(Q, L), R = A-L"
    ),
    (
        "qm04",
        raw"message_queue_create(Q), thread_send_message(Q, g(1)), \+ thread_peek_message(Q, h(_)), R = no"
    ),
    ("qm05", raw"message_queue_create(Q), \+ thread_peek_message(Q, _), R = no"),
    (
        "qm06",
        raw"message_queue_create(_, [alias(qm06q)]), thread_send_message(qm06q, a), thread_send_message(qm06q, b), findall(S, message_queue_property(qm06q, size(S)), R)"
    ),
    (
        "qm07",
        raw"message_queue_create(Q), thread_send_message(Q, _), thread_get_message(Q, M), ( var(M) -> R = unbound ; R = M )"
    ),
    (
        "qm08",
        raw"message_queue_create(Q), thread_send_message(Q, f(X, Y, X)), thread_get_message(Q, f(A, B, C)), ( A == C, A \== B, var(X), var(Y) -> R = fresh ; R = shared )"
    ),
    (
        "qm09",
        raw"message_queue_create(Q), thread_send_message(Q, f(X)), X = 1, thread_get_message(Q, f(Y)), ( var(Y) -> R = unbound ; R = Y )"
    ),
    ("qm10", raw"roundtrip(\"str\", R)"),
    ("qm11", raw"roundtrip(1.5, R)"),
    ("qm12", raw"roundtrip(123456789012345678901234567890, R)"),
    ("qm13", raw"roundtrip([a, b|T], R), R = [_, _|T2], ( T2 == T -> true ; true )"),
    ("qm14", raw"roundtrip('hello world', R)"),
    ("qm15", raw"roundtrip([], R)"),
    ("qm16", raw"roundtrip(f(g(h(i(j(1))))), R)"),
    (
        "qm17",
        raw"numlist(1, 1000, L), roundtrip(L, M), ( M == L -> R = same ; R = differ )"
    ),
    ("qm18", raw"roundtrip(1r3, R)"),
    (
        "qm19",
        raw"thread_send_message(main, qm19a), thread_peek_message(qm19a), thread_get_message(qm19a), R = ok"
    ),
    (
        "qm20",
        raw"thread_send_message(1, qm20a), thread_peek_message(main, qm20a), thread_get_message(qm20a), R = ok"
    ),
    ("qm21", raw"\+ thread_peek_message(qm21_nothere), R = no"),
    (
        "qm22",
        raw"thread_send_message(main, qm22a), message_queue_property(main, size(S)), thread_get_message(qm22a), R = S"
    ),
    ("qm23", raw"thread_send_message(_, x)"),
    ("qm24", raw"cx(thread_send_message(nosuchq, x), R)"),
    ("qm25", raw"thread_send_message(f(x), x)"),
    ("qm26", raw"cx(thread_send_message(f(x), x), R)"),
    ("qm27", raw"thread_get_message(nosuchq, _)"),
    ("qm28", raw"thread_get_message(_, _)"),
    ("qm29", raw"thread_get_message(f(x), _)"),
    ("qm30", raw"thread_get_message(0, _)"),
    ("qm31", raw"thread_get_message(-1, _)"),
    ("qm32", raw"thread_get_message(99, _)"),
    ("qm33", raw"thread_peek_message(nosuchq, x)"),
    ("qm34", raw"thread_peek_message(_, x)"),
    ("qm35", raw"thread_peek_message(f(x), x)"),
    ("qm36", raw"thread_send_message(1.5, x)"),
    ("qm37", raw"thread_send_message(\"str\", x)"),
    ("qm38", raw"thread_send_message([], x)"),
    ("qm39", raw"cx(thread_get_message(nosuchq, _), R)"),
    ("qm40", raw"cx(thread_peek_message(nosuchq, x), R)"),
    (
        "qm41",
        raw"thread_send_message(main, qm41a), thread_send_message(main, qm41b), thread_get_message(qm41b), thread_get_message(qm41a), R = ok"
    ),
    (
        "qm42",
        raw"message_queue_create(Q), thread_send_message(Q, a), thread_send_message(Q, b), thread_get_message(Q, X), drain(Q, L), R = X-L"
    ),
    (
        "qm43",
        raw"message_queue_create(Q), thread_send_message(Q, f(1)), thread_get_message(Q, f(X)), R = X"
    ),
    (
        "qm44",
        raw"message_queue_create(Q), thread_send_message(Q, f(1)), ( thread_get_message(Q, f(2), [timeout(0)]) -> R = got ; drain(Q, R) )"
    ),
    (
        "qm46",
        raw"message_queue_create(Q), thread_send_message(Q, x), thread_send_message(Q, x), thread_get_message(Q, x), drain(Q, R)"
    ),
    (
        "qm47",
        raw"message_queue_create(Q), thread_send_message(Q, f(A)), thread_get_message(Q, f(1)), var(A), R = ok"
    ),
    (
        "qm48",
        raw"message_queue_create(Q), thread_send_message(Q, a), thread_peek_message(Q, a), thread_peek_message(Q, a), drain(Q, R)"
    ),
    (
        "qm49",
        raw"message_queue_create(Q), ( thread_get_message(Q, _, [timeout(0)]) -> R = got ; R = empty )"
    ),
    (
        "qm50",
        raw"message_queue_create(Q, [alias(qm50q), max_size(1)]), thread_send_message(qm50q, a), message_queue_set(qm50q, max_size(0)), thread_send_message(qm50q, b), drain(qm50q, R)"
    ),
    # qo: the deadline options of thread_send_message/3 and thread_get_message/3
    (
        "qo01",
        raw"message_queue_create(Q, [max_size(1)]), thread_send_message(Q, a), thread_send_message(Q, b, [timeout(0)])"
    ),
    (
        "qo02",
        raw"message_queue_create(Q, [max_size(1)]), thread_send_message(Q, a), thread_send_message(Q, b, [timeout(0.01)])"
    ),
    (
        "qo03",
        raw"message_queue_create(Q, [max_size(1)]), thread_send_message(Q, a), thread_send_message(Q, b, [deadline(1.0)])"
    ),
    (
        "qo04",
        raw"message_queue_create(Q, [max_size(1)]), thread_send_message(Q, a), thread_send_message(Q, b, [timeout(-1)])"
    ),
    (
        "qo05",
        raw"message_queue_create(Q, [max_size(1)]), thread_send_message(Q, a), thread_send_message(Q, b, [signals(foo), timeout(0)])"
    ),
    (
        "qo06",
        raw"message_queue_create(Q, [max_size(1)]), thread_send_message(Q, a), cx(thread_send_message(Q, b, [signals(foo)]), R)"
    ),
    (
        "qo07",
        raw"message_queue_create(Q, [max_size(1)]), thread_send_message(Q, a), thread_send_message(Q, b, [signals(false), timeout(0)])"
    ),
    (
        "qo08",
        raw"message_queue_create(Q, [max_size(1)]), thread_send_message(Q, a), thread_send_message(Q, b, [signals(0.5), timeout(0)])"
    ),
    (
        "qo09",
        raw"message_queue_create(Q, [max_size(1)]), thread_send_message(Q, a), thread_send_message(Q, b, [signals(-1.0), timeout(0)])"
    ),
    ("qo10", raw"thread_send_message(main, x, foo)"),
    ("qo11", raw"thread_send_message(main, x, [timeout(a)])"),
    ("qo12", raw"thread_send_message(main, x, [timeout(0)|_])"),
    ("qo13", raw"thread_send_message(main, x, [timeout(0)|foo])"),
    ("qo14", raw"message_queue_create(Q), thread_send_message(Q, x, [foo]), R = ok"),
    ("qo15", raw"thread_send_message(main, x, [1])"),
    ("qo16", raw"thread_send_message(main, x, [f(1, 2)])"),
    ("qo17", raw"message_queue_create(Q), thread_send_message(Q, x, [timeout=0]), R = ok"),
    ("qo18", raw"thread_send_message(main, x, [_])"),
    ("qo19", raw"thread_send_message(main, x, [timeout(_)])"),
    (
        "qo20",
        raw"message_queue_create(Q), thread_send_message(Q, x, [timeout(0)]), drain(Q, R)"
    ),
    ("qo21", raw"message_queue_create(Q), thread_send_message(Q, x, []), drain(Q, R)"),
    (
        "qo22",
        raw"message_queue_create(Q), thread_send_message(Q, x, [signals(true)]), drain(Q, R)"
    ),
    (
        "qo23",
        raw"message_queue_create(Q), thread_send_message(Q, x, [timeout(1.0)]), drain(Q, R)"
    ),
    (
        "qo24",
        raw"message_queue_create(Q), thread_send_message(Q, x, [timeout(inf)]), drain(Q, R)"
    ),
    (
        "qo25",
        raw"message_queue_create(Q), thread_send_message(Q, x, [timeout(1)]), drain(Q, R)"
    ),
    (
        "qo26",
        raw"get_time(T), D is T + 100, message_queue_create(Q), thread_send_message(Q, x, [deadline(D)]), drain(Q, R)"
    ),
    (
        "qo27",
        raw"message_queue_create(Q), thread_send_message(Q, x, [deadline(1.0), timeout(5)]), drain(Q, R)"
    ),
    (
        "qo28",
        raw"message_queue_create(Q), thread_send_message(Q, x, [deadline(1.0)]), drain(Q, R)"
    ),
    (
        "qo29",
        raw"message_queue_create(Q), thread_send_message(Q, x, [timeout(-1)]), drain(Q, R)"
    ),
    ("qo30", raw"message_queue_create(Q), thread_send_message(Q, x, [signals(foo)])"),
    (
        "qo31",
        raw"message_queue_create(Q), thread_send_message(Q, a), thread_send_message(Q, b), thread_get_message(Q, b, [timeout(0)]), drain(Q, R)"
    ),
    (
        "qo32",
        raw"message_queue_create(Q), thread_send_message(Q, a), thread_get_message(Q, b, [timeout(0)])"
    ),
    (
        "qo33",
        raw"message_queue_create(Q), thread_send_message(Q, a), thread_get_message(Q, b, [timeout(0.01)])"
    ),
    (
        "qo34",
        raw"message_queue_create(Q), thread_send_message(Q, a), thread_get_message(Q, b, [timeout(-1)])"
    ),
    (
        "qo35",
        raw"message_queue_create(Q), thread_send_message(Q, a), thread_get_message(Q, b, [deadline(1.0)])"
    ),
    ("qo36", raw"thread_get_message(nosuchq, _, [timeout(0)])"),
    ("qo37", raw"cx(thread_get_message(nosuchq, _, [timeout(0)]), R)"),
    ("qo38", raw"thread_get_message(_, _, [timeout(0)])"),
    ("qo39", raw"thread_get_message(f(x), _, [timeout(0)])"),
    ("qo40", raw"thread_get_message(nosuchq, x, [timeout(foo)])"),
    ("qo41", raw"thread_get_message(nosuchq, x, [signals(foo)])"),
    (
        "qo42",
        raw"message_queue_create(Q), thread_send_message(Q, a), thread_get_message(Q, X, []), R = X"
    ),
    (
        "qo43",
        raw"message_queue_create(Q), thread_send_message(Q, a), thread_get_message(Q, X, [signals(true)]), R = X"
    ),
    (
        "qo44",
        raw"message_queue_create(Q), thread_send_message(Q, a), thread_get_message(Q, X, [timeout=0]), R = X"
    ),
    (
        "qo45",
        raw"message_queue_create(Q), thread_send_message(Q, a), thread_get_message(Q, X, foo), R = X"
    ),
    (
        "qo46",
        raw"message_queue_create(Q), thread_send_message(Q, a), thread_get_message(Q, X, [timeout(0)|_]), R = X"
    ),
    (
        "qo47",
        raw"message_queue_create(Q), thread_send_message(Q, a), thread_get_message(Q, X, [timeout(inf)]), R = X"
    ),
    (
        "qo48",
        raw"message_queue_create(Q), thread_send_message(Q, a), thread_get_message(Q, X, [timeout(5)]), R = X"
    ),
    (
        "qo49",
        raw"get_time(T), D is T + 100, message_queue_create(Q), thread_send_message(Q, a), thread_get_message(Q, X, [deadline(D)]), R = X"
    ),
    (
        "qo50",
        raw"message_queue_create(Q), thread_send_message(Q, a), thread_get_message(Q, X, [deadline(1.0)]), R = X"
    ),
    (
        "qo51",
        raw"message_queue_create(Q), thread_send_message(Q, a), thread_get_message(Q, X, [timeout(-1)]), R = X"
    ),
    ("qo52", raw"thread_get_message(nothing, [timeout(0)])"),
    ("qo53", raw"cx(thread_get_message(nothing, [timeout(0)]), R)"),
    (
        "qo54",
        raw"message_queue_create(Q), thread_send_message(Q, a), thread_get_message(Q, X, [signals(foo)]), R = X"
    ),
    (
        "qo55",
        raw"message_queue_create(Q), thread_send_message(Q, a), thread_get_message(Q, X, [timeout(0), timeout(a)]), R = X"
    ),
    (
        "qo56",
        raw"message_queue_create(Q), thread_send_message(Q, f(1)), thread_send_message(Q, g(2)), thread_get_message(Q, g(X), [timeout(0)]), drain(Q, L), R = X-L"
    ),
    (
        "qo57",
        raw"message_queue_create(Q, [max_size(2)]), thread_send_message(Q, a), thread_send_message(Q, b, [timeout(0)]), thread_send_message(Q, c, [timeout(0)])"
    ),
    (
        "qo58",
        raw"message_queue_create(Q, [max_size(2)]), thread_send_message(Q, a), thread_send_message(Q, b, [timeout(0)]), thread_get_message(Q, a), thread_send_message(Q, c, [timeout(0)]), drain(Q, R)"
    ),
    ("qo59", raw"cx(thread_get_message(nosuchq, x, [timeout(foo)]), R)"),
    ("qo60", raw"cx(thread_send_message(main, x, [timeout(a)]), R)"),
    # qe: the queue of an engine, and the queue of main reached from an engine
    (
        "qe01",
        raw"engine_create(x, true, E), thread_send_message(E, hi), thread_peek_message(E, hi), R = yes"
    ),
    (
        "qe02",
        raw"engine_create(ok, thread_send_message(main, qe02a), E), engine_next(E, _), thread_get_message(main, X), R = X"
    ),
    (
        "qe03",
        raw"engine_create(R0, ( thread_self(Me), thread_send_message(Me, qe03a), thread_get_message(qe03a), R0 = ok ), E), engine_next(E, R)"
    ),
    (
        "qe04",
        raw"thread_send_message(main, qe04a), engine_create(R0, ( thread_peek_message(qe04a) -> R0 = sees ; R0 = empty ), E), engine_next(E, R1), thread_get_message(qe04a), R = R1"
    ),
    (
        "qe05",
        raw"engine_create(x, true, E), engine_destroy(E), ek(thread_send_message(E, x), R)"
    ),
    (
        "qe06",
        raw"engine_create(x, true, E), thread_send_message(E, m), message_queue_property(E, size(S)), R = S"
    ),
    ("qe07", raw"engine_create(x, true, E), pk(message_queue_destroy(E), R)"),
    (
        "qe08",
        raw"message_queue_create(Q), engine_create(ok, thread_send_message(Q, qe08a), E), engine_next(E, _), thread_get_message(Q, X), R = X"
    ),
    (
        "qe09",
        raw"engine_create(x, true, E), findall(P, message_queue_property(E, P), R0), R0 = [alias(A), size(S)], ( var(A) -> R = quirk-S ; R = other )"
    ),
    (
        "qe10",
        raw"engine_create(R0, ( thread_self(Me), thread_get_message(Me, _, [timeout(0)]) ), E), \+ engine_next(E, _), R = no"
    ),
    (
        "qe11",
        raw"engine_create(x, true, E), engine_destroy(E), ek(message_queue_property(E, _), R)"
    ),
    ("qe12", raw"engine_create(x, true, E), is_message_queue(E), R = yes"),
    (
        "qe13",
        raw"engine_create(x, true, E), thread_send_message(E, m), engine_destroy(E), R = ok"
    ),
    (
        "qe14",
        raw"engine_create(R0, ( thread_send_message(main, qe14a), thread_send_message(main, qe14b) ), E), engine_next(E, _), thread_get_message(main, qe14b), thread_get_message(main, qe14a), R = ok"
    ),
    (
        "qe15",
        raw"message_queue_create(qe15q), engine_create(x, true, E), cx(set_thread(E, alias(qe15q)), R)"
    ),
    (
        "qe16",
        raw"message_queue_create(qe16q), engine_create(x, true, E), pk(set_thread(E, alias(qe16q)), R)"
    ),
    ("qe17", raw"engine_create(x, true, E), set_thread(E, alias(qe17q)), R = ok"),
    (
        "qe18",
        raw"engine_create(x, true, E), set_thread(E, alias(qe18q)), cx(message_queue_create(qe18q), R)"
    ),
    # qz: the table at the end
    ("qz01", raw"findall(A, message_queue_property(_, alias(A)), L), msort(L, R)"),
    (
        "qz02",
        raw"findall(A, ( message_queue_property(Q, alias(A)), is_message_queue(Q) ), L), msort(L, M), length(M, N), length(L, N), R = ok"
    ),
    (
        "qz03",
        raw"message_queue_property(Q, alias(qc16q)), thread_send_message(Q, qz03a), message_queue_property(Q, size(S)), drain(Q, L), R = S-L"
    ),
    ("qz04", raw"is_message_queue(qc16q), R = yes"),
    ("qz05", raw"is_message_queue(qd12q), is_message_queue(qd13q), R = yes"),
    ("qz06", raw"is_message_queue(qd11q), R = yes"),
    ("qz07", raw"is_message_queue(1), R = yes"),
    ("qz08", raw"is_message_queue(f(x)), R = yes"),
    ("qz09", raw"is_message_queue(_), R = yes"),
    ("qz10", raw"is_message_queue(nosuchq), R = yes")
]

# swipl 10.1.20's answers (the driver's lines): `ok`, then one line per case (filled by evidence/R2/queues_gen_rows.py --fill)
const _TQ_PINNED = [
    "ok",
    "t_qa01 c[116,95,113,97,48,49]/1(c[91,124,93]/2(c[115,105,122,101]/1(i0),nil))",
    "t_qa02 c[116,95,113,97,48,50]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[109,101,115,115,97,103,101,95,113,117,101,117,101,95,112,114,111,112,101,114,116,121],c[102,111,111]/1(V0))))",
    "t_qa03",
    "t_qa04 c[116,95,113,97,48,52]/1(c[91,124,93]/2(c[97,108,105,97,115]/1(V0),c[91,124,93]/2(c[115,105,122,101]/1(i0),nil)))",
    "t_qa05 c[116,95,113,97,48,53]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[116,104,114,101,97,100],i99)))",
    "t_qa06 c[116,95,113,97,48,54]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[116,104,114,101,97,100],i99)))",
    "t_qa07 c[116,95,113,97,48,55]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[116,104,114,101,97,100],i99)))",
    "t_qa08 c[116,95,113,97,48,56]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[109,101,115,115,97,103,101,95,113,117,101,117,101],a[110,111,115,117,99,104,113])))",
    "t_qc01 c[116,95,113,99,48,49]/1(a[121,101,115])",
    "t_qc02 c[116,95,113,99,48,50]/1(a[111,107])",
    "t_qc03 c[116,95,113,99,48,51]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[99,114,101,97,116,101],a[109,101,115,115,97,103,101,95,113,117,101,117,101],a[113,99,48,50,113])))",
    "t_qc04 c[116,95,113,99,48,52]/1(c[45]/2(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[99,114,101,97,116,101],a[109,101,115,115,97,103,101,95,113,117,101,117,101],a[113,99,48,50,113]),c[99,111,110,116,101,120,116]/2(c[47]/2(a[109,101,115,115,97,103,101,95,113,117,101,117,101,95,99,114,101,97,116,101],i1),V0)))",
    "t_qc05 c[116,95,113,99,48,53]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[99,114,101,97,116,101],a[109,101,115,115,97,103,101,95,113,117,101,117,101],a[109,97,105,110])))",
    "t_qc06 c[116,95,113,99,48,54]/1(c[45]/2(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[99,114,101,97,116,101],a[109,101,115,115,97,103,101,95,113,117,101,117,101],a[109,97,105,110]),c[99,111,110,116,101,120,116]/2(c[47]/2(a[109,101,115,115,97,103,101,95,113,117,101,117,101,95,99,114,101,97,116,101],i1),V0)))",
    "t_qc07 c[116,95,113,99,48,55]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[109,101,115,115,97,103,101,95,113,117,101,117,101],c[102]/1(a[120]))))",
    "t_qc08 c[116,95,113,99,48,56]/1(c[45]/2(c[116,121,112,101,95,101,114,114,111,114]/2(a[109,101,115,115,97,103,101,95,113,117,101,117,101],c[102]/1(a[120])),c[99,111,110,116,101,120,116]/2(c[47]/2(a[109,101,115,115,97,103,101,95,113,117,101,117,101,95,99,114,101,97,116,101],i1),V0)))",
    "t_qc09 c[116,95,113,99,48,57]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[109,101,115,115,97,103,101,95,113,117,101,117,101],i1)))",
    "t_qc10 c[116,95,113,99,49,48]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[109,101,115,115,97,103,101,95,113,117,101,117,101],s[115,116,114])))",
    "t_qc11 c[116,95,113,99,49,49]/1(c[45]/2(a[99,114,101,97,116,101],a[109,101,115,115,97,103,101,95,113,117,101,117,101]))",
    "t_qc12 c[116,95,113,99,49,50]/1(c[91,124,93]/2(c[115,105,122,101]/1(i0),nil))",
    "t_qc13 c[116,95,113,99,49,51]/1(a[100,105,115,116,105,110,99,116])",
    "t_qc14 c[116,95,113,99,49,52]/1(a[109,101,115,115,97,103,101,95,113,117,101,117,101])",
    "t_qc15 c[116,95,113,99,49,53]/1(a[110,111,116,97,116,111,109])",
    "t_qc16 c[116,95,113,99,49,54]/1(a[113,99,49,54,113])",
    "t_qc17 c[116,95,113,99,49,55]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[118,97,114,105,97,98,108,101],a[122,122])))",
    "t_qc18 c[116,95,113,99,49,56]/1(c[45]/2(c[116,121,112,101,95,101,114,114,111,114]/2(a[118,97,114,105,97,98,108,101],a[122,122]),c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[109,101,115,115,97,103,101,95,113,117,101,117,101,95,99,114,101,97,116,101],i2)),V0)))",
    "t_qc19 c[116,95,113,99,49,57]/1(a[111,107])",
    "t_qc20 c[116,95,113,99,50,48]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[110,111,116,95,108,101,115,115,95,116,104,97,110,95,122,101,114,111],i-1)))",
    "t_qc21 c[116,95,113,99,50,49]/1(c[45]/2(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[110,111,116,95,108,101,115,115,95,116,104,97,110,95,122,101,114,111],i-1),c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[109,101,115,115,97,103,101,95,113,117,101,117,101,95,99,114,101,97,116,101],i2)),V0)))",
    "t_qc22 c[116,95,113,99,50,50]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],a[97])))",
    "t_qc23 c[116,95,113,99,50,51]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],i1)))",
    "t_qc24 c[116,95,113,99,50,52]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[108,105,115,116],a[102,111,111])))",
    "t_qc25 c[116,95,113,99,50,53]/1(c[45]/2(c[116,121,112,101,95,101,114,114,111,114]/2(a[108,105,115,116],a[102,111,111]),c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[109,101,115,115,97,103,101,95,113,117,101,117,101,95,99,114,101,97,116,101],i2)),V0)))",
    "t_qc26 c[116,95,113,99,50,54]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_qc27 c[116,95,113,99,50,55]/1(a[121,101,115])",
    "t_qc28 c[116,95,113,99,50,56]/1(a[121,101,115])",
    "t_qc29 c[116,95,113,99,50,57]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],f1.5)))",
    "t_qc30 c[116,95,113,99,51,48]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[99,114,101,97,116,101],a[109,101,115,115,97,103,101,95,113,117,101,117,101],a[109,97,105,110])))",
    "t_qc31 c[116,95,113,99,51,49]/1(c[45]/2(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[99,114,101,97,116,101],a[109,101,115,115,97,103,101,95,113,117,101,117,101],a[113,99,49,54,113]),c[99,111,110,116,101,120,116]/2(c[47]/2(a[109,101,115,115,97,103,101,95,113,117,101,117,101,95,99,114,101,97,116,101],i1),V0)))",
    "t_qc32 c[116,95,113,99,51,50]/1(i2)",
    "t_qc33 c[116,95,113,99,51,51]/1(c[91,124,93]/2(c[97,108,105,97,115]/1(a[113,99,51,51,113]),c[91,124,93]/2(c[115,105,122,101]/1(i0),nil)))",
    "t_qc34 c[116,95,113,99,51,52]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_qc35 c[116,95,113,99,51,53]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_qc36 c[116,95,113,99,51,54]/1(a[113,99,51,54,113])",
    "t_qc37 c[116,95,113,99,51,55]/1(c[114,97,105,115,101,100]/1(c[114,101,112,114,101,115,101,110,116,97,116,105,111,110,95,101,114,114,111,114]/1(a[115,105,122,101,95,116])))",
    "t_qc38 c[116,95,113,99,51,56]/1(i4)",
    "t_qc39 c[116,95,113,99,51,57]/1(a[111,107])",
    "t_qp01 c[116,95,113,112,48,49]/1(c[91,124,93]/2(c[97,108,105,97,115]/1(a[113,112,48,49,113]),c[91,124,93]/2(c[115,105,122,101]/1(i0),c[91,124,93]/2(c[109,97,120,95,115,105,122,101]/1(i2),nil))))",
    "t_qp02 c[116,95,113,112,48,50]/1(c[91,124,93]/2(c[115,105,122,101]/1(i0),nil))",
    "t_qp03 c[116,95,113,112,48,51]/1(c[91,124,93]/2(c[97,108,105,97,115]/1(V0),c[91,124,93]/2(c[115,105,122,101]/1(i0),nil)))",
    "t_qp04 c[116,95,113,112,48,52]/1(c[91,124,93]/2(c[97,108,105,97,115]/1(V0),c[91,124,93]/2(c[115,105,122,101]/1(i0),nil)))",
    "t_qp05 c[116,95,113,112,48,53]/1(a[113,117,105,114,107])",
    "t_qp06 c[116,95,113,112,48,54]/1(a[102,97,105,108,115])",
    "t_qp07 c[116,95,113,112,48,55]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[109,101,115,115,97,103,101,95,113,117,101,117,101],a[110,111,115,117,99,104,113])))",
    "t_qp08 c[116,95,113,112,48,56]/1(c[45]/2(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[109,101,115,115,97,103,101,95,113,117,101,117,101],a[110,111,115,117,99,104,113]),c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[109,101,115,115,97,103,101,95,113,117,101,117,101,95,112,114,111,112,101,114,116,121],i2)),V0)))",
    "t_qp09 c[116,95,113,112,48,57]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[109,101,115,115,97,103,101,95,113,117,101,117,101],c[102]/1(a[120]))))",
    "t_qp10 c[116,95,113,112,49,48]/1(c[45]/2(c[116,121,112,101,95,101,114,114,111,114]/2(a[109,101,115,115,97,103,101,95,113,117,101,117,101],c[102]/1(a[120])),c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[109,101,115,115,97,103,101,95,113,117,101,117,101,95,112,114,111,112,101,114,116,121],i2)),V0)))",
    "t_qp11 c[116,95,113,112,49,49]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[109,101,115,115,97,103,101,95,113,117,101,117,101,95,112,114,111,112,101,114,116,121],c[102,111,111]/1(V0))))",
    "t_qp12 c[116,95,113,112,49,50]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[109,101,115,115,97,103,101,95,113,117,101,117,101,95,112,114,111,112,101,114,116,121],i1)))",
    "t_qp13 c[116,95,113,112,49,51]/1(c[45]/2(c[116,121,112,101,95,101,114,114,111,114]/2(a[109,101,115,115,97,103,101,95,113,117,101,117,101,95,112,114,111,112,101,114,116,121],i1),c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[109,101,115,115,97,103,101,95,113,117,101,117,101,95,112,114,111,112,101,114,116,121],i2)),V0)))",
    "t_qp14 c[116,95,113,112,49,52]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[109,101,115,115,97,103,101,95,113,117,101,117,101,95,112,114,111,112,101,114,116,121],a[102,111,111])))",
    "t_qp15 c[116,95,113,112,49,53]/1(c[45]/2(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[109,101,115,115,97,103,101,95,113,117,101,117,101,95,112,114,111,112,101,114,116,121],a[102,111,111]),c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[109,101,115,115,97,103,101,95,113,117,101,117,101,95,112,114,111,112,101,114,116,121],i2)),V0)))",
    "t_qp16 c[116,95,113,112,49,54]/1(i0)",
    "t_qp17 c[116,95,113,112,49,55]/1(i2)",
    "t_qp18",
    "t_qp19 c[116,95,113,112,49,57]/1(a[113,112,48,49,113])",
    "t_qp20 c[116,95,113,112,50,48]/1(a[115,97,109,101])",
    "t_qp21 c[116,95,113,112,50,49]/1(c[91,124,93]/2(a[98],c[91,124,93]/2(a[113,99,48,50,113],c[91,124,93]/2(a[113,99,49,54,113],c[91,124,93]/2(a[113,99,49,57,113],c[91,124,93]/2(a[113,99,51,51,113],c[91,124,93]/2(a[113,99,51,54,113],c[91,124,93]/2(a[113,99,51,56,113],c[91,124,93]/2(a[113,112,48,49,113],nil)))))))))",
    "t_qp22 c[116,95,113,112,50,50]/1(c[45]/2(a[116,114,117,101],i2))",
    "t_qp23 c[116,95,113,112,50,51]/1(c[45]/2(a[110,111,110,100,101,116],c[97,108,105,97,115]/1(a[113,112,48,49,113]))) c[116,95,113,112,50,51]/1(c[45]/2(a[110,111,110,100,101,116],c[115,105,122,101]/1(i0))) c[116,95,113,112,50,51]/1(c[45]/2(a[110,111,110,100,101,116],c[109,97,120,95,115,105,122,101]/1(i2)))",
    "t_qp24 c[116,95,113,112,50,52]/1(a[111,110,99,101])",
    "t_qp25",
    "t_qp26",
    "t_qp27",
    "t_qp28 c[116,95,113,112,50,56]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[109,101,115,115,97,103,101,95,113,117,101,117,101],i0)))",
    "t_qp29 c[116,95,113,112,50,57]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[116,104,114,101,97,100],i99)))",
    "t_qp30 c[116,95,113,112,51,48]/1(c[91,124,93]/2(i2,c[91,124,93]/2(i2,c[91,124,93]/2(i2,c[91,124,93]/2(i4,nil)))))",
    "t_qp31 c[116,95,113,112,51,49]/1(c[91,124,93]/2(c[45]/2(a[113,99,49,54,113],i0),c[91,124,93]/2(c[45]/2(a[113,112,48,49,113],i0),nil)))",
    "t_qd01 c[116,95,113,100,48,49]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[100,101,115,116,114,111,121],a[109,101,115,115,97,103,101,95,113,117,101,117,101],a[109,97,105,110])))",
    "t_qd02 c[116,95,113,100,48,50]/1(c[45]/2(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[100,101,115,116,114,111,121],a[109,101,115,115,97,103,101,95,113,117,101,117,101],a[109,97,105,110]),c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[109,101,115,115,97,103,101,95,113,117,101,117,101,95,100,101,115,116,114,111,121],i1)),a[105,115,32,97,32,116,104,114,101,97,100,45,113,117,101,117,101])))",
    "t_qd03 c[116,95,113,100,48,51]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[100,101,115,116,114,111,121],a[109,101,115,115,97,103,101,95,113,117,101,117,101],i1)))",
    "t_qd04 c[116,95,113,100,48,52]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[109,101,115,115,97,103,101,95,113,117,101,117,101],a[110,111,115,117,99,104,113])))",
    "t_qd05 c[116,95,113,100,48,53]/1(c[45]/2(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[109,101,115,115,97,103,101,95,113,117,101,117,101],a[110,111,115,117,99,104,113]),c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[109,101,115,115,97,103,101,95,113,117,101,117,101,95,100,101,115,116,114,111,121],i1)),V0)))",
    "t_qd06 c[116,95,113,100,48,54]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_qd07 c[116,95,113,100,48,55]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[109,101,115,115,97,103,101,95,113,117,101,117,101],c[102]/1(a[120]))))",
    "t_qd08 c[116,95,113,100,48,56]/1(a[111,107])",
    "t_qd09 c[116,95,113,100,48,57]/1(a[109,101,115,115,97,103,101,95,113,117,101,117,101])",
    "t_qd10 c[116,95,113,100,49,48]/1(a[110,111])",
    "t_qd11 c[116,95,113,100,49,49]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[109,101,115,115,97,103,101,95,113,117,101,117,101],a[113,100,49,49,113])))",
    "t_qd12 c[116,95,113,100,49,50]/1(a[111,107])",
    "t_qd13 c[116,95,113,100,49,51]/1(c[91,124,93]/2(c[97,108,105,97,115]/1(a[113,100,49,51,113]),c[91,124,93]/2(c[115,105,122,101]/1(i0),nil)))",
    "t_qd14 c[116,95,113,100,49,52]/1(a[109,101,115,115,97,103,101,95,113,117,101,117,101])",
    "t_qd15 c[116,95,113,100,49,53]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[109,101,115,115,97,103,101,95,113,117,101,117,101],i0)))",
    "t_qd16 c[116,95,113,100,49,54]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[109,101,115,115,97,103,101,95,113,117,101,117,101],i-1)))",
    "t_qd17 c[116,95,113,100,49,55]/1(a[103,111,110,101])",
    "t_qd18 c[116,95,113,100,49,56]/1(a[109,101,115,115,97,103,101,95,113,117,101,117,101])",
    "t_qd19 c[116,95,113,100,49,57]/1(a[109,101,115,115,97,103,101,95,113,117,101,117,101])",
    "t_qd20 c[116,95,113,100,50,48]/1(a[109,101,115,115,97,103,101,95,113,117,101,117,101])",
    "t_qd21 c[116,95,113,100,50,49]/1(a[109,101,115,115,97,103,101,95,113,117,101,117,101])",
    "t_qd22 c[116,95,113,100,50,50]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[109,101,115,115,97,103,101,95,113,117,101,117,101],f1.5)))",
    "t_qd23 c[116,95,113,100,50,51]/1(a[111,107])",
    "t_qs01 c[116,95,113,115,48,49]/1(i5)",
    "t_qs02 c[116,95,113,115,48,50]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[110,111,116,95,108,101,115,115,95,116,104,97,110,95,122,101,114,111],i-1)))",
    "t_qs03 c[116,95,113,115,48,51]/1(c[45]/2(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[110,111,116,95,108,101,115,115,95,116,104,97,110,95,122,101,114,111],i-1),c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[109,101,115,115,97,103,101,95,113,117,101,117,101,95,115,101,116],i2)),V0)))",
    "t_qs04 c[116,95,113,115,48,52]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[109,101,115,115,97,103,101,95,113,117,101,117,101,95,112,114,111,112,101,114,116,121],c[102,111,111]/1(i1))))",
    "t_qs05 c[116,95,113,115,48,53]/1(c[45]/2(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[109,101,115,115,97,103,101,95,113,117,101,117,101,95,112,114,111,112,101,114,116,121],c[102,111,111]/1(i1)),c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[109,101,115,115,97,103,101,95,113,117,101,117,101,95,115,101,116],i2)),V0)))",
    "t_qs06 c[116,95,113,115,48,54]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,111,109,112,111,117,110,100],a[102,111,111])))",
    "t_qs07 c[116,95,113,115,48,55]/1(c[45]/2(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,111,109,112,111,117,110,100],a[102,111,111]),c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[109,101,115,115,97,103,101,95,113,117,101,117,101,95,115,101,116],i2)),V0)))",
    "t_qs08 c[116,95,113,115,48,56]/1(i3)",
    "t_qs09 c[116,95,113,115,48,57]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[109,101,115,115,97,103,101,95,113,117,101,117,101],a[110,111,115,117,99,104,113])))",
    "t_qs10 c[116,95,113,115,49,48]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_qs11 c[116,95,113,115,49,49]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_qs12 c[116,95,113,115,49,50]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],a[97])))",
    "t_qs13 c[116,95,113,115,49,51]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_qs14 c[116,95,113,115,49,52]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],f2.5)))",
    "t_qs15 c[116,95,113,115,49,53]/1(a[110,111,110,101])",
    "t_qs16 c[116,95,113,115,49,54]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,111,109,112,111,117,110,100],i1)))",
    "t_qs17 c[116,95,113,115,49,55]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,111,109,112,111,117,110,100],c[102,111,111]/2(i1,i2))))",
    "t_qs18 c[116,95,113,115,49,56]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[109,101,115,115,97,103,101,95,113,117,101,117,101],c[102]/1(a[120]))))",
    "t_qm01 c[116,95,113,109,48,49]/1(c[91,124,93]/2(a[97],c[91,124,93]/2(a[99],nil)))",
    "t_qm02 c[116,95,113,109,48,50]/1(c[45]/2(i2,c[91,124,93]/2(c[103]/2(i1,a[120]),nil)))",
    "t_qm03 c[116,95,113,109,48,51]/1(c[45]/2(i2,c[91,124,93]/2(c[103]/2(i1,a[120]),c[91,124,93]/2(c[103]/2(i2,a[121]),nil))))",
    "t_qm04 c[116,95,113,109,48,52]/1(a[110,111])",
    "t_qm05 c[116,95,113,109,48,53]/1(a[110,111])",
    "t_qm06 c[116,95,113,109,48,54]/1(c[91,124,93]/2(i2,nil))",
    "t_qm07 c[116,95,113,109,48,55]/1(a[117,110,98,111,117,110,100])",
    "t_qm08 c[116,95,113,109,48,56]/1(a[102,114,101,115,104])",
    "t_qm09 c[116,95,113,109,48,57]/1(a[117,110,98,111,117,110,100])",
    "t_qm10 c[116,95,113,109,49,48]/1(s[115,116,114])",
    "t_qm11 c[116,95,113,109,49,49]/1(f1.5)",
    "t_qm12 c[116,95,113,109,49,50]/1(i123456789012345678901234567890)",
    "t_qm13 c[116,95,113,109,49,51]/1(c[91,124,93]/2(a[97],c[91,124,93]/2(a[98],V0)))",
    "t_qm14 c[116,95,113,109,49,52]/1(a[104,101,108,108,111,32,119,111,114,108,100])",
    "t_qm15 c[116,95,113,109,49,53]/1(nil)",
    "t_qm16 c[116,95,113,109,49,54]/1(c[102]/1(c[103]/1(c[104]/1(c[105]/1(c[106]/1(i1))))))",
    "t_qm17 c[116,95,113,109,49,55]/1(a[115,97,109,101])",
    "t_qm18 c[116,95,113,109,49,56]/1(q1r3)",
    "t_qm19 c[116,95,113,109,49,57]/1(a[111,107])",
    "t_qm20 c[116,95,113,109,50,48]/1(a[111,107])",
    "t_qm21 c[116,95,113,109,50,49]/1(a[110,111])",
    "t_qm22 c[116,95,113,109,50,50]/1(i1)",
    "t_qm23 c[116,95,113,109,50,51]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_qm24 c[116,95,113,109,50,52]/1(c[45]/2(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[109,101,115,115,97,103,101,95,113,117,101,117,101],a[110,111,115,117,99,104,113]),c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[116,104,114,101,97,100,95,115,101,110,100,95,109,101,115,115,97,103,101],i2)),V0)))",
    "t_qm25 c[116,95,113,109,50,53]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[109,101,115,115,97,103,101,95,113,117,101,117,101],c[102]/1(a[120]))))",
    "t_qm26 c[116,95,113,109,50,54]/1(c[45]/2(c[116,121,112,101,95,101,114,114,111,114]/2(a[109,101,115,115,97,103,101,95,113,117,101,117,101],c[102]/1(a[120])),c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[116,104,114,101,97,100,95,115,101,110,100,95,109,101,115,115,97,103,101],i2)),V0)))",
    "t_qm27 c[116,95,113,109,50,55]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[109,101,115,115,97,103,101,95,113,117,101,117,101],a[110,111,115,117,99,104,113])))",
    "t_qm28 c[116,95,113,109,50,56]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_qm29 c[116,95,113,109,50,57]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[109,101,115,115,97,103,101,95,113,117,101,117,101],c[102]/1(a[120]))))",
    "t_qm30 c[116,95,113,109,51,48]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[109,101,115,115,97,103,101,95,113,117,101,117,101],i0)))",
    "t_qm31 c[116,95,113,109,51,49]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[109,101,115,115,97,103,101,95,113,117,101,117,101],i-1)))",
    "t_qm32 c[116,95,113,109,51,50]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[116,104,114,101,97,100],i99)))",
    "t_qm33 c[116,95,113,109,51,51]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[109,101,115,115,97,103,101,95,113,117,101,117,101],a[110,111,115,117,99,104,113])))",
    "t_qm34 c[116,95,113,109,51,52]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_qm35 c[116,95,113,109,51,53]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[109,101,115,115,97,103,101,95,113,117,101,117,101],c[102]/1(a[120]))))",
    "t_qm36 c[116,95,113,109,51,54]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[109,101,115,115,97,103,101,95,113,117,101,117,101],f1.5)))",
    "t_qm37 c[116,95,113,109,51,55]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[109,101,115,115,97,103,101,95,113,117,101,117,101],s[115,116,114])))",
    "t_qm38 c[116,95,113,109,51,56]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[109,101,115,115,97,103,101,95,113,117,101,117,101],nil)))",
    "t_qm39 c[116,95,113,109,51,57]/1(c[45]/2(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[109,101,115,115,97,103,101,95,113,117,101,117,101],a[110,111,115,117,99,104,113]),c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[116,104,114,101,97,100,95,103,101,116,95,109,101,115,115,97,103,101],i2)),V0)))",
    "t_qm40 c[116,95,113,109,52,48]/1(c[45]/2(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[109,101,115,115,97,103,101,95,113,117,101,117,101],a[110,111,115,117,99,104,113]),c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[116,104,114,101,97,100,95,112,101,101,107,95,109,101,115,115,97,103,101],i2)),V0)))",
    "t_qm41 c[116,95,113,109,52,49]/1(a[111,107])",
    "t_qm42 c[116,95,113,109,52,50]/1(c[45]/2(a[97],c[91,124,93]/2(a[98],nil)))",
    "t_qm43 c[116,95,113,109,52,51]/1(i1)",
    "t_qm44 c[116,95,113,109,52,52]/1(c[91,124,93]/2(c[102]/1(i1),nil))",
    "t_qm46 c[116,95,113,109,52,54]/1(c[91,124,93]/2(a[120],nil))",
    "t_qm47 c[116,95,113,109,52,55]/1(a[111,107])",
    "t_qm48 c[116,95,113,109,52,56]/1(c[91,124,93]/2(a[97],nil))",
    "t_qm49 c[116,95,113,109,52,57]/1(a[101,109,112,116,121])",
    "t_qm50 c[116,95,113,109,53,48]/1(c[91,124,93]/2(a[97],c[91,124,93]/2(a[98],nil)))",
    "t_qo01",
    "t_qo02",
    "t_qo03",
    "t_qo04",
    "t_qo05 c[116,95,113,111,48,53]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[115,105,103,110,97,108,95,111,112,116,105,111,110],a[102,111,111])))",
    "t_qo06 c[116,95,113,111,48,54]/1(c[45]/2(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[115,105,103,110,97,108,95,111,112,116,105,111,110],a[102,111,111]),c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[116,104,114,101,97,100,95,115,101,110,100,95,109,101,115,115,97,103,101],i3)),V0)))",
    "t_qo07",
    "t_qo08",
    "t_qo09 c[116,95,113,111,48,57]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[115,105,103,110,97,108,95,111,112,116,105,111,110],f-1.0)))",
    "t_qo10 c[116,95,113,111,49,48]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[108,105,115,116],a[102,111,111])))",
    "t_qo11 c[116,95,113,111,49,49]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[102,108,111,97,116],a[97])))",
    "t_qo12 c[116,95,113,111,49,50]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_qo13 c[116,95,113,111,49,51]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[108,105,115,116],a[102,111,111])))",
    "t_qo14 c[116,95,113,111,49,52]/1(a[111,107])",
    "t_qo15 c[116,95,113,111,49,53]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[111,112,116,105,111,110],i1)))",
    "t_qo16 c[116,95,113,111,49,54]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[111,112,116,105,111,110],c[102]/2(i1,i2))))",
    "t_qo17 c[116,95,113,111,49,55]/1(a[111,107])",
    "t_qo18 c[116,95,113,111,49,56]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_qo19 c[116,95,113,111,49,57]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_qo20 c[116,95,113,111,50,48]/1(c[91,124,93]/2(a[120],nil))",
    "t_qo21 c[116,95,113,111,50,49]/1(c[91,124,93]/2(a[120],nil))",
    "t_qo22 c[116,95,113,111,50,50]/1(c[91,124,93]/2(a[120],nil))",
    "t_qo23 c[116,95,113,111,50,51]/1(c[91,124,93]/2(a[120],nil))",
    "t_qo24 c[116,95,113,111,50,52]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[102,108,111,97,116],a[105,110,102])))",
    "t_qo25 c[116,95,113,111,50,53]/1(c[91,124,93]/2(a[120],nil))",
    "t_qo26 c[116,95,113,111,50,54]/1(c[91,124,93]/2(a[120],nil))",
    "t_qo27",
    "t_qo28",
    "t_qo29",
    "t_qo30 c[116,95,113,111,51,48]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[115,105,103,110,97,108,95,111,112,116,105,111,110],a[102,111,111])))",
    "t_qo31 c[116,95,113,111,51,49]/1(c[91,124,93]/2(a[97],nil))",
    "t_qo32",
    "t_qo33",
    "t_qo34",
    "t_qo35",
    "t_qo36 c[116,95,113,111,51,54]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[109,101,115,115,97,103,101,95,113,117,101,117,101],a[110,111,115,117,99,104,113])))",
    "t_qo37 c[116,95,113,111,51,55]/1(c[45]/2(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[109,101,115,115,97,103,101,95,113,117,101,117,101],a[110,111,115,117,99,104,113]),c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[116,104,114,101,97,100,95,103,101,116,95,109,101,115,115,97,103,101],i3)),V0)))",
    "t_qo38 c[116,95,113,111,51,56]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_qo39 c[116,95,113,111,51,57]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[109,101,115,115,97,103,101,95,113,117,101,117,101],c[102]/1(a[120]))))",
    "t_qo40 c[116,95,113,111,52,48]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[102,108,111,97,116],a[102,111,111])))",
    "t_qo41 c[116,95,113,111,52,49]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[115,105,103,110,97,108,95,111,112,116,105,111,110],a[102,111,111])))",
    "t_qo42 c[116,95,113,111,52,50]/1(a[97])",
    "t_qo43 c[116,95,113,111,52,51]/1(a[97])",
    "t_qo44 c[116,95,113,111,52,52]/1(a[97])",
    "t_qo45 c[116,95,113,111,52,53]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[108,105,115,116],a[102,111,111])))",
    "t_qo46 c[116,95,113,111,52,54]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_qo47 c[116,95,113,111,52,55]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[102,108,111,97,116],a[105,110,102])))",
    "t_qo48 c[116,95,113,111,52,56]/1(a[97])",
    "t_qo49 c[116,95,113,111,52,57]/1(a[97])",
    "t_qo50",
    "t_qo51",
    "t_qo52 c[116,95,113,111,53,50]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[109,101,115,115,97,103,101,95,113,117,101,117,101],a[110,111,116,104,105,110,103])))",
    "t_qo53 c[116,95,113,111,53,51]/1(c[45]/2(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[109,101,115,115,97,103,101,95,113,117,101,117,101],a[110,111,116,104,105,110,103]),c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[116,104,114,101,97,100,95,103,101,116,95,109,101,115,115,97,103,101],i2)),V0)))",
    "t_qo54 c[116,95,113,111,53,52]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[115,105,103,110,97,108,95,111,112,116,105,111,110],a[102,111,111])))",
    "t_qo55 c[116,95,113,111,53,53]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[102,108,111,97,116],a[97])))",
    "t_qo56 c[116,95,113,111,53,54]/1(c[45]/2(i2,c[91,124,93]/2(c[102]/1(i1),nil)))",
    "t_qo57",
    "t_qo58 c[116,95,113,111,53,56]/1(c[91,124,93]/2(a[98],c[91,124,93]/2(a[99],nil)))",
    "t_qo59 c[116,95,113,111,53,57]/1(c[45]/2(c[116,121,112,101,95,101,114,114,111,114]/2(a[102,108,111,97,116],a[102,111,111]),c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[116,104,114,101,97,100,95,103,101,116,95,109,101,115,115,97,103,101],i3)),V0)))",
    "t_qo60 c[116,95,113,111,54,48]/1(c[45]/2(c[116,121,112,101,95,101,114,114,111,114]/2(a[102,108,111,97,116],a[97]),c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[116,104,114,101,97,100,95,115,101,110,100,95,109,101,115,115,97,103,101],i3)),V0)))",
    "t_qe01 c[116,95,113,101,48,49]/1(a[121,101,115])",
    "t_qe02 c[116,95,113,101,48,50]/1(a[113,101,48,50,97])",
    "t_qe03 c[116,95,113,101,48,51]/1(a[111,107])",
    "t_qe04 c[116,95,113,101,48,52]/1(a[101,109,112,116,121])",
    "t_qe05 c[116,95,113,101,48,53]/1(a[116,104,114,101,97,100])",
    "t_qe06 c[116,95,113,101,48,54]/1(i1)",
    "t_qe07 c[116,95,113,101,48,55]/1(c[45]/2(a[100,101,115,116,114,111,121],a[109,101,115,115,97,103,101,95,113,117,101,117,101]))",
    "t_qe08 c[116,95,113,101,48,56]/1(a[113,101,48,56,97])",
    "t_qe09 c[116,95,113,101,48,57]/1(c[45]/2(a[113,117,105,114,107],i0))",
    "t_qe10 c[116,95,113,101,49,48]/1(a[110,111])",
    "t_qe11 c[116,95,113,101,49,49]/1(a[116,104,114,101,97,100])",
    "t_qe12",
    "t_qe13 c[116,95,113,101,49,51]/1(a[111,107])",
    "t_qe14 c[116,95,113,101,49,52]/1(a[111,107])",
    "t_qe15 c[116,95,113,101,49,53]/1(c[45]/2(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[99,114,101,97,116,101],a[116,104,114,101,97,100],a[113,101,49,53,113]),c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[115,101,116,95,116,104,114,101,97,100],i2)),a[65,108,105,97,115,32,110,97,109,101,32,97,108,114,101,97,100,121,32,116,97,107,101,110])))",
    "t_qe16 c[116,95,113,101,49,54]/1(c[45]/2(a[99,114,101,97,116,101],a[116,104,114,101,97,100]))",
    "t_qe17 c[116,95,113,101,49,55]/1(a[111,107])",
    "t_qe18 c[116,95,113,101,49,56]/1(c[45]/2(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[99,114,101,97,116,101],a[109,101,115,115,97,103,101,95,113,117,101,117,101],a[113,101,49,56,113]),c[99,111,110,116,101,120,116]/2(c[47]/2(a[109,101,115,115,97,103,101,95,113,117,101,117,101,95,99,114,101,97,116,101],i1),V0)))",
    "t_qz01 c[116,95,113,122,48,49]/1(c[91,124,93]/2(a[98],c[91,124,93]/2(a[113,99,48,50,113],c[91,124,93]/2(a[113,99,49,54,113],c[91,124,93]/2(a[113,99,49,57,113],c[91,124,93]/2(a[113,99,51,51,113],c[91,124,93]/2(a[113,99,51,54,113],c[91,124,93]/2(a[113,99,51,56,113],c[91,124,93]/2(a[113,100,49,50,113],c[91,124,93]/2(a[113,100,49,51,113],c[91,124,93]/2(a[113,101,49,53,113],c[91,124,93]/2(a[113,101,49,54,113],c[91,124,93]/2(a[113,109,48,54,113],c[91,124,93]/2(a[113,109,53,48,113],c[91,124,93]/2(a[113,112,48,49,113],c[91,124,93]/2(a[113,115,48,49,113],nil))))))))))))))))",
    "t_qz02 c[116,95,113,122,48,50]/1(a[111,107])",
    "t_qz03 c[116,95,113,122,48,51]/1(c[45]/2(i1,c[91,124,93]/2(a[113,122,48,51,97],nil)))",
    "t_qz04 c[116,95,113,122,48,52]/1(a[121,101,115])",
    "t_qz05 c[116,95,113,122,48,53]/1(a[121,101,115])",
    "t_qz06",
    "t_qz07",
    "t_qz08",
    "t_qz09",
    "t_qz10"
]

const _TQ_IDS = [id for (id, _) in _TQ_CASES]
const _TQ_PIN = Dict(zip(_TQ_IDS, _TQ_PINNED[2:end]))

# the rows where the kernel answers differently from swipl (id => the kernel's exact line); swipl's line is in `_TQ_PINNED`.
# swipl's driver is started as `swipl -q file`, which has made one anonymous queue before the first row (the `-g` start of the same binary has
# none: `findall(P, message_queue_property(_, P), L)` is `[]` there): its table is not empty, so an unbound Queue enumerates it (qa01), and a
# property no queue has is a domain error (qa02). The kernel's table is empty until the first message_queue_create (queueTable is NULL: it fails).
const _TQ_KD = Dict{String, String}(
    "qa01" => "t_qa01 " * _tq_c("t_qa01", "nil"),
    "qa02" => "t_qa02"
)

"The program text: the helpers, then one clause `t_<id>(R)` per case."
function _tq_program()::String
    return _TQ_PRELUDE * join(
        [
        "t_$(id)(R) :- catch(($(g)), error(SsuE, _), R = raised(SsuE)).\n" for
        (id, g) in _TQ_CASES
    ]
    )
end

function _tq_file()::Tuple{String, Vector{String}}
    f = joinpath(mktempdir(), "queues.pl")
    write(f, _tq_program())
    return f, ["t_$id" for id in _TQ_IDS]
end

"""
The kernel's lines for `names` after consulting `path`, as the driver writes swipl's, in a FRESH database. A NotPortedError ends
the run with the line `<name> notported <step> <what>` (the query is abandoned with the database).
"""
function _tq_kernel(path::String, names::Vector{String})
    gd = LK.PL_global_data{_TQ}()
    ld = LK.PL_local_data{_TQ}(gd)
    st, ball = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * _tq_enc(ball::_TQ)]
    for name in names
        proc = LK.isCurrentProcedure(sym_key(_tqs(name)), 1, LK.MODULE_user(gd))
        if proc === nothing || !LK.isDefinedProcedure(gd, proc)
            push!(out, "$name undefined")
            continue
        end
        sols = String[]
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 1)
        LK.putSlotValue!(ld, a + 1, mk_var(_TQ, LK.fresh_var_keys!(1)), LK.PutVarMap())
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
        )
        n = 0
        try
            while (n += 1) <= 50
                rc = LK.PL_next_solution(gd, ld, qid)
                if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
                    push!(
                        sols,
                        _tq_enc(mk_expr(_TQ, _TQ[_tqs(name), lk_answers(ld, (a:a)...)...]))
                    )
                    rc == LK.PL_S_LAST && break
                elseif rc == LK.PL_S_EXCEPTION
                    push!(sols, "exception")
                    break
                else
                    break
                end
            end
        catch e
            e isa LK.NotPortedError || rethrow()
            push!(out, "$name notported $(e.step) $(e.what)")
            return out, gd, ld, e
        end
        LK.PL_close_query(ld, qid)
        LK.PL_close_foreign_frame(ld, fid)
        push!(out, "$name" * join(" " .* sols))
    end
    return out, gd, ld, nothing
end

@testset "user message queues as swipl's (qa, qc, qp, qd, qs, qm, qo, qe, qz rows)" begin
    f, names = _tq_file()
    kl, gd, ld, e = _tq_kernel(f, names)
    @test e === nothing
    @test kl[1] == "ok"
    @test length(kl) == length(names) + 1
    for (k, id) in zip(kl[2:end], _TQ_IDS)
        want = get(_TQ_KD, id, _TQ_PIN[id])
        k == want || println(stderr, "  ours  ", k, "\n  want  ", want)
        @test k == want
    end
    # white box: the table is consistent after the run
    for (key, q) in gd.message_queues
        @test q.type == LK.QTYPE_QUEUE
        @test !q.destroyed
        @test key == sym_key(q.id::_TQ)
        @test q.serial >= 1 && q.serial <= gd.message_queue_serial
    end
    @test length(unique(q.serial for q in values(gd.message_queues))) ==
        length(gd.message_queues)
    @test !isempty(gd.message_queues)
    # the thread queues: the main thread's (tid 1) is empty again (every row drains it), none has a name
    @test haskey(gd.thread_queues, 1)
    for (tid, q) in gd.thread_queues
        @test q.type == LK.QTYPE_THREAD
        @test q.tid == tid
        @test q.id === nothing
    end
    @test isempty(gd.thread_queues[1].messages)
    @test LK.live_states(ld) == 0                                  # every message_queue_property/2 state was given back
end

@testset "the KNOWN DIFFERENCE rows: swipl's driver start has made a queue already (qa01, qa02)" begin
    # swipl's answers, from the pin
    @test _TQ_PIN["qa01"] == "t_qa01 " * _tq_c("t_qa01", _tq_list([_tq_c("size", "i0")]))
    @test startswith(_TQ_PIN["qa02"], "t_qa02 ")
    @test occursin(_tq_codes("domain_error"), _TQ_PIN["qa02"])
    # the kernel's, pinned exactly: no queue was ever made, so an unbound Queue enumerates nothing and the call fails
    @test _TQ_KD["qa01"] == "t_qa01 " * _tq_c("t_qa01", "nil")
    @test _TQ_KD["qa02"] == "t_qa02"
    for id in keys(_TQ_KD)
        @test _TQ_KD[id] != _TQ_PIN[id]
    end
    @test sort(collect(keys(_TQ_KD))) == ["qa01", "qa02"]
end

# REFUSED by name, owner TH1, kernel only (id, goal, culprit, `what`): swipl WAITS for a message (or a drain) that no other thread can send:
# pin swipl cannot answer (it waits forever). The kernel refuses with a NotPortedError of step TH1.
const _TQ_WAIT_GET = "thread_get_message/N: an empty queue, or one with no matching message, and no other thread to send (blocking wait)"
const _TQ_WAIT_SEND = "thread_send_message/N: a full queue with no other thread to drain it (blocking send)"
const _TQ_REFUSED = [
    (
        "qr01",
        raw"message_queue_create(Q), thread_get_message(Q, x)",
        "thread_get_message",
        _TQ_WAIT_GET
    ),
    (
        "qr02",
        raw"message_queue_create(Q), thread_send_message(Q, a), thread_get_message(Q, b)",
        "thread_get_message",
        _TQ_WAIT_GET
    ),
    (
        "qr03",
        raw"message_queue_create(Q), thread_get_message(Q, x, [])",
        "thread_get_message",
        _TQ_WAIT_GET
    ),
    (
        "qr04",
        raw"message_queue_create(Q), thread_get_message(Q, x, [signals(true)])",
        "thread_get_message",
        _TQ_WAIT_GET
    ),
    ("qr05", raw"thread_get_message(qr05_nothing)", "thread_get_message", _TQ_WAIT_GET),
    (
        "qr06",
        raw"message_queue_create(Q, [max_size(1)]), thread_send_message(Q, a), thread_send_message(Q, b)",
        "thread_send_message",
        _TQ_WAIT_SEND
    ),
    (
        "qr07",
        raw"message_queue_create(Q, [max_size(1)]), thread_send_message(Q, a), thread_send_message(Q, b, [])",
        "thread_send_message",
        _TQ_WAIT_SEND
    ),
    (
        "qr08",
        raw"thread_get_message(main, qr08_nothing)",
        "thread_get_message",
        _TQ_WAIT_GET
    ),
    (
        "qr09",
        raw"message_queue_create(Q), thread_send_message(Q, a), message_queue_set(Q, max_size(1)), thread_send_message(Q, b)",
        "thread_send_message",
        _TQ_WAIT_SEND
    ),
    (
        "qr10",
        raw"engine_create(x, true, E), thread_get_message(E, x)",
        "thread_get_message",
        _TQ_WAIT_GET
    ),
    (
        "qr11",
        raw"message_queue_create(Q), thread_get_message(Q, x, [signals(0.5)])",
        "thread_get_message",
        _TQ_WAIT_GET
    ),
    (
        "qr12",
        raw"message_queue_create(Q, [max_size(1)]), thread_send_message(Q, a), thread_send_message(Q, b, [signals(false)])",
        "thread_send_message",
        _TQ_WAIT_SEND
    )
]

@testset "the twelve named refusals of the blocking waits, owner TH1 (qr01-qr12)" begin
    for (id, g, culprit, what) in _TQ_REFUSED
        f = joinpath(mktempdir(), "queues_refused.pl")
        write(f, _TQ_PRELUDE * "t_$(id)(R) :- $(g), R = ok.\n")   # no catch/3: a NotPortedError is a Julia exception
        kl, _, _, e = _tq_kernel(f, ["t_$id"])
        @test e isa LK.NotPortedError
        e isa LK.NotPortedError || continue
        @test e.step == "TH1"
        @test e.what == what
        @test sym_text(e.culprit) == culprit
        @test kl[end] == "t_$id notported TH1 $what"
    end
    @test length(_TQ_REFUSED) == 12
    @test count(r -> r[3] == "thread_get_message", _TQ_REFUSED) == 8
    @test count(r -> r[3] == "thread_send_message", _TQ_REFUSED) == 4
end

@testset "with a deadline the same waits FAIL at once, no sleep (the DIVERGES of the one-thread form)" begin
    # swipl waits until the deadline here; the kernel answers `false` immediately. Both rows ran in the main testset (qo01-qo04, qo32-qo35, qo57):
    # their pins are the failing line (the id alone), the kernel's line is the same.
    for id in
        ("qo01", "qo02", "qo03", "qo04", "qo32", "qo33", "qo34", "qo35", "qo57", "qm44")
        @test haskey(_TQ_PIN, id)
    end
    for id in ("qo01", "qo02", "qo03", "qo04", "qo32", "qo33", "qo34", "qo35", "qo57")
        @test _TQ_PIN[id] == "t_$id"
    end
    f = joinpath(mktempdir(), "queues_nosleep.pl")
    write(
        f,
        "t_ns1(R) :- message_queue_create(Q), thread_get_message(Q, x, [timeout(30)]) -> R = got ; R = timedout.\n"
    )
    t0 = time()
    kl, _, _, e = _tq_kernel(f, ["t_ns1"])
    @test e === nothing
    @test kl[end] == "t_ns1 " * _tq_c("t_ns1", _tq_a("timedout"))
    @test time() - t0 < 20                                          # a wait of 30 s would show here
end

@testset "the thirteen queue predicates are registered with upstream's flags (pl-thread.c:8870-8893)" begin
    ext = Dict((e.predicate_name, e.arity) => e for e in LK.foreigns)
    preds = (
        ("message_queue_create", 1, false, false),
        ("message_queue_create", 2, false, false),
        ("message_queue_destroy", 1, true, false),
        ("message_queue_property", 2, true, true),
        ("message_queue_set", 2, false, false), ("is_message_queue", 1, false, false),
        ("thread_send_message", 2, true, false), ("thread_send_message", 3, false, false),
        ("thread_get_message", 1, true, false), ("thread_get_message", 2, true, false),
        ("thread_get_message", 3, true, false), ("thread_peek_message", 1, true, false),
        ("thread_peek_message", 2, true, false)
    )
    @test length(preds) == 13
    for (name, ar, iso, nondet) in preds
        @test haskey(ext, (name, ar))
        haskey(ext, (name, ar)) || continue
        fl = ext[(name, ar)].flags
        @test ((fl & LK.PL_FA_ISO) != 0) == iso
        @test ((fl & LK.PL_FA_NONDETERMINISTIC) != 0) == nondet
        @test (fl & LK.PL_FA_TRANSPARENT) == 0
    end
end

@testset "a queue's name is refused for a thread alias, and a thread's queue goes with the thread (white box)" begin
    gd = LK.PL_global_data{_TQ}()
    ld = LK.PL_local_data{_TQ}(gd)
    @test isempty(gd.message_queues) && isempty(gd.thread_queues) &&
        gd.message_queue_serial == 0
    f = joinpath(mktempdir(), "queues_wb.pl")
    write(
        f,
        "t_w1(R) :- message_queue_create(wbq), engine_create(x, true, E), thread_send_message(E, m), " *
        "catch(set_thread(E, alias(wbq)), error(permission_error(A, B, C), _), true), R = A-B-C.\n" *
        "t_w2(R) :- engine_create(x, true, E), thread_send_message(E, m), engine_destroy(E), R = ok.\n"
    )
    kl, gd, ld, e = _tq_kernel(f, ["t_w1", "t_w2"])
    @test e === nothing
    @test kl[2] ==
        "t_w1 " * _tq_c(
        "t_w1", _tq_c("-", _tq_c("-", _tq_a("create"), _tq_a("thread")), _tq_a("wbq"))
    )
    @test kl[3] == "t_w2 " * _tq_c("t_w2", _tq_a("ok"))
    @test gd.message_queue_serial == 1
    @test haskey(gd.message_queues, sym_key(_tqs("wbq")))
    # t_w1's engine is alive (its queue stays, one message); t_w2's was destroyed (its queue is gone with it)
    @test count(q -> length(q.messages) == 1, values(gd.thread_queues)) == 1
    @test length(gd.thread_queues) == 1
end

@testset "the QUEUES rows are not vacuous" begin
    @test _TQ_PINNED[1] == "ok"
    @test length(_TQ_PINNED) == length(_TQ_CASES) + 1
    @test length(unique(_TQ_IDS)) == length(_TQ_IDS)
    errors = count(l -> occursin("[114,97,105,115,101,100]", l), _TQ_PINNED)
    @test errors >= 60                                              # the raising rows
    @test count(l -> !occursin(" ", l) && startswith(l, "t_"), _TQ_PINNED) >= 25   # failing rows
    for id in (
        "qc01",
        "qc16",
        "qp01",
        "qp22",
        "qd08",
        "qd13",
        "qs01",
        "qm01",
        "qm02",
        "qm03",
        "qm08",
        "qm17",
        "qo31",
        "qo42",
        "qe02",
        "qe03",
        "qz03"
    )
        @test any(
            l -> startswith(l, "t_$id ") && !occursin("[114,97,105,115,101,100]", l),
            _TQ_PINNED
        )                                                           # an answer, not an error
    end
    for pre in ("qa", "qc", "qp", "qd", "qs", "qm", "qo", "qe", "qz")
        @test count(id -> startswith(id, pre), _TQ_IDS) >= 8
    end
end

@testset "the QUEUES pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    @test length(_TQ_PINNED) == length(_TQ_CASES) + 1
    if swipl === nothing
        @info "QUEUES LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        f, names = _tq_file()
        @test _tq_swipl_lines(f, names) == _TQ_PINNED
    end
end
