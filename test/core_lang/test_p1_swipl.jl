# ORIGINAL: a LIVE differential of P1's term inspection predicates against swipl at the pin (pl-prims.c, swipl-devel cbf4e189):
# test/core_lang/test_p1_swipl.jl — arg/3 (nondeterministic, pl-prims.c:2704), compound_name_arity/3 (:2508),
# compound_name_arguments/3 (:3161), subsumes_term/2 (:3954), '$factorize_term'/3 (:1485), '$term_size'/3 (:993),
# is_most_general_term/1 (:3850), term_singletons/2 (:3741) and '$term_multitons'/2 (:3752): rows p001-p176 against swipl 10.1.19.
#   * A PROGRAM consulted by the kernel's loader and cases `t_<id>(R)` run in order in one database, each wrapped in
#     `catch(Goal, error(SsuE, _), R = raised(SsuE))`; the driver is test_style_check_swipl.jl's (`enc`oded answers; an
#     answer's variables are numbered by first occurrence).
#   * Every answer line is swipl's, PINNED (swipl 10.1.19, evidence/P1/p1_rows.out: two runs, byte-identical); with `swipl`
#     on PATH the live answers are compared with the pins too. ONE extractor (`enc`) writes both sides.
#   * The zero-argument compound `foo()` is built in a helper clause (`p_zero/1`), the cyclic term `f(f(...))` in `p_cyc/1`.
#   * KNOWN DIFFERENCES (flagged in evidence/P1/handoff.md): '$term_size'/3 sizes of numbers and strings are computed from the
#     value-table entry (`_indirect_cells`), representation-only; `'$term_multitons'(T, L)` with a PROPER list `L` shorter than
#     the variables (maxcount) has NO row: swipl 10.1.19 cannot answer it (the kernel fails the call).
#   * `$expr/n` (kernel-only, swipl has no such term): the last testset, built with `mk_expr` and answered from the kernel.
#   * UNVERIFIED on the kernel (nothing was compiled when these rows were written): every kernel answer; the gate decides.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: ALL — the built-ins ride the term layer (src/pl-prims.jl), the loader and the run loop
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _P1 = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_p1s(x) = lk_sym(_P1, Symbol(x))


_p1_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _p1_enc(t::_P1, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _p1_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _p1_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _p1_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_p1_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

# the swipl side: test/core_lang/test_style_check_swipl.jl's driver (consult, then every answer of each t_<id>/1, `enc`oded)
const _P1_DRIVER = raw"""
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
function _p1_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _P1_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(pipeline(`swipl -q $f`; stdin=devnull, stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

# the program: the helper clauses (a zero-argument compound and a cyclic term are built in a clause, not inside a `catch`)
const _P1_PROGRAM = raw"""
p_zero(foo()).
p_cyc(X) :- X = f(X).
"""

# p001-p028 arg/3: N bound (in range, 0, past the arity, negative, big, non-integer), the compound argument (atom, variable,
# string, list, zero arity, cyclic), enumeration (order, matching value, determinism on the last argument, shared
# variables), call/N; p029-p051 compound_name_arity/3, p052-p070 compound_name_arguments/3: both directions, zero arity,
# the type, instantiation and domain errors; p071-p092 subsumes_term/2; p093-p100 '$factorize_term'/3; p101-p126
# '$term_size'/3 (calibration: atom 0, float 3, "abc" 3, "abcdefgh" 4, 2^64 5, 1r3 6, f(X,X) 3, a wide string 4);
# p127-p147 is_most_general_term/1; p148-p161 term_singletons/2; p162-p173 '$term_multitons'/2; p174-p176 the rows of the mutants
# UNVERIFIED on the kernel: gate decides — p014/p015 (call_cleanup/2 for the determinism), p028/p095/p117/p153/p166 (the cyclic
# term), p106 (rdiv), p108 (a wide string's size), p049 (the size_t representation error of a huge arity), p044/p070 (the
# reserved `[]` as a compound name), p031/p054/p122 (a zero-argument compound from a clause head)
const _P1_CASES = [
    # arg/3
    ("p001", raw"""arg(1, f(a,b,c), R)"""),
    ("p002", raw"""arg(3, f(a,b,c), R)"""),
    ("p003", raw"""arg(4, f(a,b,c), R)"""),
    ("p004", raw"""arg(0, f(a,b), R)"""),
    ("p005", raw"""arg(-1, f(a), R)"""),
    ("p006", raw"""arg(a, f(a), R)"""),
    ("p007", raw"""arg(1, a, R)"""),
    ("p008", raw"""arg(1, _, R)"""),
    ("p009", raw"""arg(100000000000000000000, f(a), R)"""),
    ("p010", raw"""arg(-100000000000000000000, f(a), R)"""),
    ("p011", raw"""arg(1.0, f(a), R)"""),
    ("p012", raw"""findall(N-A, arg(N, f(a,b,c), A), R)"""),
    ("p013", raw"""findall(N, arg(N, f(a,b,a), a), R)"""),
    ("p014", raw"""call_cleanup(arg(N, f(a,b,c), c), Det = true), R = N-Det"""),
    (
        "p015",
        raw"""call_cleanup(arg(N, f(a,b,c), a), Det = true), ( Det == true -> R = N-det ; R = N-nondet )"""
    ),
    ("p016", raw"""arg(2, f(a,B), X), R = B-X"""),
    ("p017", raw"""arg(1, f(X), Y), X = 1, R = Y"""),
    ("p018", raw"""findall(N-X-Y, arg(N, f(X,Y), 1), R)"""),
    ("p019", raw"""arg(1, f(a), b), R = yes"""),
    ("p020", raw"""p_zero(T), findall(N, arg(N, T, _), R)"""),
    ("p021", raw"""p_zero(T), arg(1, T, _), R = yes"""),
    ("p022", raw"""arg(1, "str", R)"""),
    ("p023", raw"""findall(N-A, arg(N, [a,b], A), R)"""),
    ("p024", raw"""call(arg, 2, f(a,b), R)"""),
    ("p025", raw"""findall(N-A, arg(N, f(a,b,c), A), [_,_|R])"""),
    ("p026", raw"""arg(N, f(a,b,c), A), N > 1, R = N-A"""),
    ("p027", raw"""arg(N, f(a), a), R = N"""),
    ("p028", raw"""p_cyc(C), arg(1, C, A), ( A == C -> R = same ; R = diff )"""),
    # compound_name_arity/3
    ("p029", raw"""compound_name_arity(f(a,b), N, A), R = N/A"""),
    ("p030", raw"""compound_name_arity(T, foo, 3), R = T"""),
    ("p031", raw"""p_zero(T), compound_name_arity(T, N, A), R = N/A"""),
    (
        "p032",
        raw"""compound_name_arity(T, foo, 0), compound_name_arity(T, N, A), R = T-N/A"""
    ),
    ("p033", raw"""compound_name_arity(a, N, A), R = N/A"""),
    ("p034", raw"""compound_name_arity(_, _, _)"""),
    ("p035", raw"""compound_name_arity(T, 1, 2), R = T"""),
    ("p036", raw"""compound_name_arity(T, f, -1), R = T"""),
    ("p037", raw"""compound_name_arity(T, f, a), R = T"""),
    ("p038", raw"""compound_name_arity(T, f, _), R = T"""),
    ("p039", raw"""compound_name_arity(T, _, 2), R = T"""),
    ("p040", raw"""compound_name_arity([a], N, A), R = N/A"""),
    ("p041", raw"""compound_name_arity(f(a), g, A), R = A"""),
    ("p042", raw"""compound_name_arity(f(a,b), N, 3), R = N"""),
    ("p043", raw"""compound_name_arity(T, "s", 2), R = T"""),
    ("p044", raw"""compound_name_arity(T, [], 2), R = T"""),
    ("p045", raw"""compound_name_arity(T, 'hello world', 1), R = T"""),
    ("p046", raw"""compound_name_arity("str", N, A), R = N/A"""),
    ("p047", raw"""compound_name_arity(f(X,Y,X), N, A), R = N/A-X-Y"""),
    ("p048", raw"""compound_name_arity(T, f, 2), arg(1, T, a), R = T"""),
    ("p049", raw"""compound_name_arity(T, f, 100000000000000000000), R = T"""),
    ("p050", raw"""compound_name_arity(T, f, 1.0), R = T"""),
    ("p051", raw"""compound_name_arity(T, g, 0), compound_name_arity(T, N, 0), R = N"""),
    # compound_name_arguments/3
    ("p052", raw"""compound_name_arguments(f(a,b), N, As), R = N-As"""),
    ("p053", raw"""compound_name_arguments(T, foo, [x,Y,Y]), R = T-Y"""),
    ("p054", raw"""compound_name_arguments(T, foo, []), R = T"""),
    ("p055", raw"""p_zero(T), compound_name_arguments(T, N, As), R = N-As"""),
    ("p056", raw"""compound_name_arguments(a, N, As), R = N-As"""),
    ("p057", raw"""compound_name_arguments(T, foo, [a|_]), R = T"""),
    ("p058", raw"""compound_name_arguments(T, foo, bar), R = T"""),
    ("p059", raw"""compound_name_arguments(T, foo, _), R = T"""),
    ("p060", raw"""compound_name_arguments(T, 1, [a]), R = T"""),
    ("p061", raw"""compound_name_arguments(f(a,b), g, As), R = As"""),
    ("p062", raw"""compound_name_arguments(f(a,b), N, [X]), R = N-X"""),
    ("p063", raw"""compound_name_arguments([a,b], N, As), R = N-As"""),
    ("p064", raw"""compound_name_arguments(T, N, [a]), R = T-N"""),
    ("p065", raw"""compound_name_arguments(f(a,b), N, [a|T]), R = N-T"""),
    ("p066", raw"""compound_name_arguments(f(a,b), N, [x,y,z]), R = N"""),
    ("p067", raw"""compound_name_arguments(T, foo, [a,b|c]), R = T"""),
    (
        "p068",
        raw"""compound_name_arguments(T, foo, [a,b]), compound_name_arity(T, N, A), R = N/A"""
    ),
    ("p069", raw"""compound_name_arguments("s", N, As), R = N-As"""),
    ("p070", raw"""compound_name_arguments(T, [], [a]), R = T"""),
    # subsumes_term/2
    ("p071", raw"""( subsumes_term(f(_), f(a)) -> R = yes ; R = no )"""),
    ("p072", raw"""( subsumes_term(f(a), f(_)) -> R = yes ; R = no )"""),
    ("p073", raw"""( subsumes_term(f(X,X), f(a,b)) -> R = yes ; R = no )"""),
    ("p074", raw"""( subsumes_term(f(X,Y), f(Z,Z)) -> R = yes ; R = no )"""),
    ("p075", raw"""( subsumes_term(f(X,Y), f(Y,X)) -> R = yes ; R = no )"""),
    ("p076", raw"""( subsumes_term(X, X) -> R = yes ; R = no )"""),
    ("p077", raw"""( subsumes_term(f(X), f(g(X))) -> R = yes ; R = no )"""),
    ("p078", raw"""( subsumes_term(f(X,X), f(Y,Y)) -> R = yes ; R = no )"""),
    ("p079", raw"""subsumes_term(f(X), f(a)), ( var(X) -> R = unbound ; R = bound )"""),
    ("p080", raw"""subsumes_term(f(X), f(Y)), ( var(Y) -> R = unbound ; R = bound )"""),
    ("p081", raw"""( subsumes_term(1, 1.0) -> R = yes ; R = no )"""),
    ("p082", raw"""( subsumes_term(f(a), f(a)) -> R = yes ; R = no )"""),
    ("p083", raw"""( subsumes_term("a", "a") -> R = yes ; R = no )"""),
    ("p084", raw"""( subsumes_term(f(X,g(X)), f(a,g(a))) -> R = yes ; R = no )"""),
    ("p085", raw"""( subsumes_term(f(X,g(X)), f(a,g(b))) -> R = yes ; R = no )"""),
    ("p086", raw"""( subsumes_term([X|Y], [a,b,c]) -> R = Y ; R = no )"""),
    ("p087", raw"""( subsumes_term(f(X,Y), f(Y,Z)) -> R = yes ; R = no )"""),
    ("p088", raw"""p_cyc(C), ( subsumes_term(C, C) -> R = yes ; R = no )"""),
    ("p089", raw"""( subsumes_term(a, X) -> R = yes ; R = no )"""),
    ("p090", raw"""( subsumes_term(X, f(X)) -> R = yes ; R = no )"""),
    ("p091", raw"""( subsumes_term(f(_,_), f(Y,Y)) -> R = yes ; R = no )"""),
    ("p092", raw"""( subsumes_term(f(X,X), f(Y,_)) -> R = yes ; R = no )"""),
    # '$factorize_term'/3
    ("p093", raw"""'$factorize_term'(f(a,b), T, S), R = T-S"""),
    ("p094", raw"""G = g(a), '$factorize_term'(f(G,G), T, S), R = T-S"""),
    ("p095", raw"""p_cyc(C), '$factorize_term'(C, T, S), R = T-S"""),
    ("p096", raw"""'$factorize_term'(X, T, S), R = X-T-S"""),
    ("p097", raw"""G = g(X), '$factorize_term'(f(G,G,X), T, S), R = T-S"""),
    (
        "p098",
        raw"""G = g(a), H = h(G), '$factorize_term'(f(H,H,G), T, S), length(S, N), R = N"""
    ),
    ("p099", raw"""'$factorize_term'(a, T, S), R = T-S"""),
    ("p100", raw"""'$factorize_term'(f(X,Y,X), T, S), R = T-S-X-Y"""),
    # '$term_size'/3
    ("p101", raw"""'$term_size'(a, _, S), R = S"""),
    ("p102", raw"""'$term_size'(1.5, _, S), R = S"""),
    ("p103", raw"""'$term_size'("abc", _, S), R = S"""),
    ("p104", raw"""'$term_size'("abcdefgh", _, S), R = S"""),
    ("p105", raw"""X is 2^64, '$term_size'(X, _, S), R = S"""),
    ("p106", raw"""X is 1 rdiv 3, '$term_size'(X, _, S), R = S"""),
    ("p107", raw"""'$term_size'(f(X,X), _, S), R = S"""),
    ("p108", raw"""string_codes(W, [97,256]), '$term_size'(W, _, S), R = S"""),
    ("p109", raw"""'$term_size'(f(a), 1, S), R = S"""),
    ("p110", raw"""'$term_size'(f(a), 2, S), R = S"""),
    ("p111", raw"""'$term_size'(f(a), 100, S), R = S"""),
    ("p112", raw"""'$term_size'(f(a), a, S), R = S"""),
    ("p113", raw"""'$term_size'(f(a), -1, S), R = S"""),
    ("p114", raw"""G = g(a), '$term_size'(f(G,G), _, S), R = S"""),
    ("p115", raw"""'$term_size'(_, _, S), R = S"""),
    ("p116", raw"""'$term_size'(f(_,_), _, S), R = S"""),
    ("p117", raw"""p_cyc(C), '$term_size'(C, _, S), R = S"""),
    ("p118", raw"""'$term_size'([a,b,c], _, S), R = S"""),
    ("p119", raw"""'$term_size'(f(1,2), _, S), R = S"""),
    ("p120", raw"""'$term_size'(f(a), _, 2), R = yes"""),
    ("p121", raw"""'$term_size'(f(a), _, 4), R = yes"""),
    ("p122", raw"""p_zero(T), '$term_size'(T, _, S), R = S"""),
    ("p123", raw"""X is 2^200, '$term_size'(X, _, S), R = S"""),
    ("p124", raw"""X is 2^63, '$term_size'(X, _, S), R = S"""),
    ("p125", raw"""'$term_size'(f(1.5,2.5), _, S), R = S"""),
    ("p126", raw"""'$term_size'(f(a), 0, S), R = S"""),
    # is_most_general_term/1
    ("p127", raw"""( is_most_general_term(a) -> R = yes ; R = no )"""),
    ("p128", raw"""( is_most_general_term([X,Y]) -> R = yes ; R = no )"""),
    ("p129", raw"""( is_most_general_term([X,X]) -> R = yes ; R = no )"""),
    ("p130", raw"""( is_most_general_term(f(X,Y)) -> R = yes ; R = no )"""),
    ("p131", raw"""( is_most_general_term(f(X,X)) -> R = yes ; R = no )"""),
    ("p132", raw"""( is_most_general_term(f(a)) -> R = yes ; R = no )"""),
    ("p133", raw"""( is_most_general_term([a|_]) -> R = yes ; R = no )"""),
    ("p134", raw"""( is_most_general_term(1) -> R = yes ; R = no )"""),
    ("p135", raw"""( is_most_general_term(_) -> R = yes ; R = no )"""),
    ("p136", raw"""( is_most_general_term([]) -> R = yes ; R = no )"""),
    ("p137", raw"""( is_most_general_term(f(X,g(Y))) -> R = yes ; R = no )"""),
    ("p138", raw"""( is_most_general_term("s") -> R = yes ; R = no )"""),
    ("p139", raw"""p_zero(T), ( is_most_general_term(T) -> R = yes ; R = no )"""),
    ("p140", raw"""( is_most_general_term([X|T]) -> R = yes ; R = no )"""),
    ("p141", raw"""( is_most_general_term([X,Y|T]) -> R = yes ; R = no )"""),
    ("p142", raw"""( is_most_general_term(f(X,Y,Z)) -> R = yes ; R = no )"""),
    ("p143", raw"""( is_most_general_term(f(X,Y,X)) -> R = yes ; R = no )"""),
    ("p144", raw"""X = 1, ( is_most_general_term(f(X,Y)) -> R = yes ; R = no )"""),
    (
        "p145",
        raw"""( is_most_general_term(f(X,Y)) -> true ; true ), term_variables(f(X,Y), L), length(L, N), R = N"""
    ),
    (
        "p146",
        raw"""( is_most_general_term(f(X,X)) -> true ; true ), term_variables(f(X,X), L), length(L, N), R = N"""
    ),
    ("p147", raw"""( is_most_general_term([X,Y]) -> true ; true ), X = Y, R = X-Y"""),
    # term_singletons/2
    ("p148", raw"""term_singletons(f(X,Y,X), L), R = L-Y"""),
    ("p149", raw"""term_singletons(f(a,b), L), R = L"""),
    ("p150", raw"""term_singletons(f(X,X), L), R = L"""),
    ("p151", raw"""term_singletons(f(X,Y,Z), L), R = L-X-Y-Z"""),
    ("p152", raw"""term_singletons(X, L), R = L-X"""),
    ("p153", raw"""p_cyc(C), term_singletons(C, L), R = L"""),
    ("p154", raw"""term_singletons(f(g(X),h(Y,X)), L), R = L-Y"""),
    ("p155", raw"""term_singletons(f(X,Y), [A]), R = A"""),
    ("p156", raw"""term_singletons(f(X,Y), [A,B]), R = A-B-X-Y"""),
    ("p157", raw"""term_singletons(a, L), R = L"""),
    ("p158", raw"""term_singletons(f(X,Y,X,Z,Z,W), L), R = L-Y-W"""),
    ("p159", raw"""G = g(X), term_singletons(f(G,G), L), R = L-X"""),
    ("p160", raw"""term_singletons(f(X,Y), a), R = yes"""),
    ("p161", raw"""term_singletons(f(X,Y), L), term_variables(f(X,Y), V), R = L-V"""),
    # '$term_multitons'/2
    ("p162", raw"""'$term_multitons'(f(X,Y,X), L), R = L-X"""),
    ("p163", raw"""'$term_multitons'(f(a,b), L), R = L"""),
    ("p164", raw"""'$term_multitons'(f(X,X), L), R = L-X"""),
    ("p165", raw"""'$term_multitons'(f(X,Y,Z), L), R = L"""),
    ("p166", raw"""p_cyc(C), '$term_multitons'(C, L), R = L"""),
    ("p167", raw"""'$term_multitons'(f(g(X),h(Y,X),Y,Z), L), R = L-X-Y"""),
    ("p168", raw"""'$term_multitons'(f(X,Y,X), [A|T]), R = A-T-X"""),
    ("p169", raw"""'$term_multitons'(f(X,X,Y,Y), [A,B]), R = A-B-X-Y"""),
    ("p170", raw"""'$term_multitons'(f(X,X,Y,Y), [A,B,C]), R = A"""),
    ("p171", raw"""G = g(X), '$term_multitons'(f(G,G), L), R = L-X"""),
    ("p172", raw"""'$term_multitons'(f(X,X,X), L), R = L-X"""),
    ("p173", raw"""'$term_multitons'(f(X,Y,Y,X,Z), L), R = L-X-Y-Z"""),
    # rows that kill mutants of tools/mutants/P1.py: arg/3 undoes a failed argument's bindings; the marks of is_most_general_term
    # on a list are cleared; term_singletons/2 against a proper list is not cut by that list's length
    ("p174", raw"""arg(N, f(g(X,b), g(c,X)), g(A,d)), R = N-A-X"""),
    (
        "p175",
        raw"""( is_most_general_term([X,Y]) -> true ; true ), term_variables([X,Y], L), length(L, N), R = N"""
    ),
    ("p176", raw"""term_singletons(f(X,Y,X), [A]), R = A-Y""")
]

# the driver's whole output, one line per case after `ok`, filled by evidence/P1/gen_rows.py --fill from swipl 10.1.19
const _P1_PINNED = [
    "ok",
    "t_p001 c[116,95,112,48,48,49]/1(a[97])",
    "t_p002 c[116,95,112,48,48,50]/1(a[99])",
    "t_p003",
    "t_p004",
    "t_p005 c[116,95,112,48,48,53]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[110,111,116,95,108,101,115,115,95,116,104,97,110,95,122,101,114,111],i-1)))",
    "t_p006 c[116,95,112,48,48,54]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],a[97])))",
    "t_p007 c[116,95,112,48,48,55]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,111,109,112,111,117,110,100],a[97])))",
    "t_p008 c[116,95,112,48,48,56]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_p009",
    "t_p010 c[116,95,112,48,49,48]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[110,111,116,95,108,101,115,115,95,116,104,97,110,95,122,101,114,111],i-100000000000000000000)))",
    "t_p011 c[116,95,112,48,49,49]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],f1.0)))",
    "t_p012 c[116,95,112,48,49,50]/1(c[91,124,93]/2(c[45]/2(i1,a[97]),c[91,124,93]/2(c[45]/2(i2,a[98]),c[91,124,93]/2(c[45]/2(i3,a[99]),nil))))",
    "t_p013 c[116,95,112,48,49,51]/1(c[91,124,93]/2(i1,c[91,124,93]/2(i3,nil)))",
    "t_p014 c[116,95,112,48,49,52]/1(c[45]/2(i3,a[116,114,117,101]))",
    "t_p015 c[116,95,112,48,49,53]/1(c[45]/2(i1,a[110,111,110,100,101,116]))",
    "t_p016 c[116,95,112,48,49,54]/1(c[45]/2(V0,V0))",
    "t_p017 c[116,95,112,48,49,55]/1(i1)",
    "t_p018 c[116,95,112,48,49,56]/1(c[91,124,93]/2(c[45]/2(c[45]/2(i1,i1),V0),c[91,124,93]/2(c[45]/2(c[45]/2(i2,V1),i1),nil)))",
    "t_p019",
    "t_p020 c[116,95,112,48,50,48]/1(nil)",
    "t_p021",
    "t_p022 c[116,95,112,48,50,50]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,111,109,112,111,117,110,100],s[115,116,114])))",
    "t_p023 c[116,95,112,48,50,51]/1(c[91,124,93]/2(c[45]/2(i1,a[97]),c[91,124,93]/2(c[45]/2(i2,c[91,124,93]/2(a[98],nil)),nil)))",
    "t_p024 c[116,95,112,48,50,52]/1(a[98])",
    "t_p025 c[116,95,112,48,50,53]/1(c[91,124,93]/2(c[45]/2(i3,a[99]),nil))",
    "t_p026 c[116,95,112,48,50,54]/1(c[45]/2(i2,a[98])) c[116,95,112,48,50,54]/1(c[45]/2(i3,a[99]))",
    "t_p027 c[116,95,112,48,50,55]/1(i1)",
    "t_p028 c[116,95,112,48,50,56]/1(a[115,97,109,101])",
    "t_p029 c[116,95,112,48,50,57]/1(c[47]/2(a[102],i2))",
    "t_p030 c[116,95,112,48,51,48]/1(c[102,111,111]/3(V0,V1,V2))",
    "t_p031 c[116,95,112,48,51,49]/1(c[47]/2(a[102,111,111],i0))",
    "t_p032 c[116,95,112,48,51,50]/1(c[45]/2(c[102,111,111]/0(),c[47]/2(a[102,111,111],i0)))",
    "t_p033 c[116,95,112,48,51,51]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,111,109,112,111,117,110,100],a[97])))",
    "t_p034 c[116,95,112,48,51,52]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_p035 c[116,95,112,48,51,53]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],i1)))",
    "t_p036 c[116,95,112,48,51,54]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[110,111,116,95,108,101,115,115,95,116,104,97,110,95,122,101,114,111],i-1)))",
    "t_p037 c[116,95,112,48,51,55]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],a[97])))",
    "t_p038 c[116,95,112,48,51,56]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_p039 c[116,95,112,48,51,57]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_p040 c[116,95,112,48,52,48]/1(c[47]/2(a[91,124,93],i2))",
    "t_p041",
    "t_p042",
    "t_p043 c[116,95,112,48,52,51]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],s[115])))",
    "t_p044 c[116,95,112,48,52,52]/1(c[]/2(V0,V1))",
    "t_p045 c[116,95,112,48,52,53]/1(c[104,101,108,108,111,32,119,111,114,108,100]/1(V0))",
    "t_p046 c[116,95,112,48,52,54]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,111,109,112,111,117,110,100],s[115,116,114])))",
    "t_p047 c[116,95,112,48,52,55]/1(c[45]/2(c[45]/2(c[47]/2(a[102],i3),V0),V1))",
    "t_p048 c[116,95,112,48,52,56]/1(c[102]/2(a[97],V0))",
    "t_p049 c[116,95,112,48,52,57]/1(c[114,97,105,115,101,100]/1(c[114,101,112,114,101,115,101,110,116,97,116,105,111,110,95,101,114,114,111,114]/1(a[115,105,122,101,95,116])))",
    "t_p050 c[116,95,112,48,53,48]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],f1.0)))",
    "t_p051 c[116,95,112,48,53,49]/1(a[103])",
    "t_p052 c[116,95,112,48,53,50]/1(c[45]/2(a[102],c[91,124,93]/2(a[97],c[91,124,93]/2(a[98],nil))))",
    "t_p053 c[116,95,112,48,53,51]/1(c[45]/2(c[102,111,111]/3(a[120],V0,V0),V0))",
    "t_p054 c[116,95,112,48,53,52]/1(c[102,111,111]/0())",
    "t_p055 c[116,95,112,48,53,53]/1(c[45]/2(a[102,111,111],nil))",
    "t_p056 c[116,95,112,48,53,54]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,111,109,112,111,117,110,100],a[97])))",
    "t_p057 c[116,95,112,48,53,55]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_p058 c[116,95,112,48,53,56]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[108,105,115,116],a[98,97,114])))",
    "t_p059 c[116,95,112,48,53,57]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_p060 c[116,95,112,48,54,48]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],i1)))",
    "t_p061",
    "t_p062",
    "t_p063 c[116,95,112,48,54,51]/1(c[45]/2(a[91,124,93],c[91,124,93]/2(a[97],c[91,124,93]/2(c[91,124,93]/2(a[98],nil),nil))))",
    "t_p064 c[116,95,112,48,54,52]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_p065 c[116,95,112,48,54,53]/1(c[45]/2(a[102],c[91,124,93]/2(a[98],nil)))",
    "t_p066",
    "t_p067 c[116,95,112,48,54,55]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[108,105,115,116],c[91,124,93]/2(a[97],c[91,124,93]/2(a[98],a[99])))))",
    "t_p068 c[116,95,112,48,54,56]/1(c[47]/2(a[102,111,111],i2))",
    "t_p069 c[116,95,112,48,54,57]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,111,109,112,111,117,110,100],s[115])))",
    "t_p070 c[116,95,112,48,55,48]/1(c[]/1(a[97]))",
    "t_p071 c[116,95,112,48,55,49]/1(a[121,101,115])",
    "t_p072 c[116,95,112,48,55,50]/1(a[110,111])",
    "t_p073 c[116,95,112,48,55,51]/1(a[110,111])",
    "t_p074 c[116,95,112,48,55,52]/1(a[121,101,115])",
    "t_p075 c[116,95,112,48,55,53]/1(a[110,111])",
    "t_p076 c[116,95,112,48,55,54]/1(a[121,101,115])",
    "t_p077 c[116,95,112,48,55,55]/1(a[110,111])",
    "t_p078 c[116,95,112,48,55,56]/1(a[121,101,115])",
    "t_p079 c[116,95,112,48,55,57]/1(a[117,110,98,111,117,110,100])",
    "t_p080 c[116,95,112,48,56,48]/1(a[117,110,98,111,117,110,100])",
    "t_p081 c[116,95,112,48,56,49]/1(a[110,111])",
    "t_p082 c[116,95,112,48,56,50]/1(a[121,101,115])",
    "t_p083 c[116,95,112,48,56,51]/1(a[121,101,115])",
    "t_p084 c[116,95,112,48,56,52]/1(a[121,101,115])",
    "t_p085 c[116,95,112,48,56,53]/1(a[110,111])",
    "t_p086 c[116,95,112,48,56,54]/1(V0)",
    "t_p087 c[116,95,112,48,56,55]/1(a[110,111])",
    "t_p088 c[116,95,112,48,56,56]/1(a[121,101,115])",
    "t_p089 c[116,95,112,48,56,57]/1(a[110,111])",
    "t_p090 c[116,95,112,48,57,48]/1(a[110,111])",
    "t_p091 c[116,95,112,48,57,49]/1(a[121,101,115])",
    "t_p092 c[116,95,112,48,57,50]/1(a[110,111])",
    "t_p093 c[116,95,112,48,57,51]/1(c[45]/2(c[102]/2(a[97],a[98]),nil))",
    "t_p094 c[116,95,112,48,57,52]/1(c[45]/2(c[102]/2(V0,V0),c[91,124,93]/2(c[61]/2(V0,c[103]/1(a[97])),nil)))",
    "t_p095 c[116,95,112,48,57,53]/1(c[45]/2(V0,c[91,124,93]/2(c[61]/2(V0,c[102]/1(V0)),nil)))",
    "t_p096 c[116,95,112,48,57,54]/1(c[45]/2(c[45]/2(V0,V0),nil))",
    "t_p097 c[116,95,112,48,57,55]/1(c[45]/2(c[102]/3(V0,V0,V1),c[91,124,93]/2(c[61]/2(V0,c[103]/1(V1)),nil)))",
    "t_p098 c[116,95,112,48,57,56]/1(i2)",
    "t_p099 c[116,95,112,48,57,57]/1(c[45]/2(a[97],nil))",
    "t_p100 c[116,95,112,49,48,48]/1(c[45]/2(c[45]/2(c[45]/2(c[102]/3(V0,V1,V0),nil),V0),V1))",
    "t_p101 c[116,95,112,49,48,49]/1(i0)",
    "t_p102 c[116,95,112,49,48,50]/1(i3)",
    "t_p103 c[116,95,112,49,48,51]/1(i3)",
    "t_p104 c[116,95,112,49,48,52]/1(i4)",
    "t_p105 c[116,95,112,49,48,53]/1(i5)",
    "t_p106 c[116,95,112,49,48,54]/1(i6)",
    "t_p107 c[116,95,112,49,48,55]/1(i3)",
    "t_p108 c[116,95,112,49,48,56]/1(i4)",
    "t_p109",
    "t_p110 c[116,95,112,49,49,48]/1(i2)",
    "t_p111 c[116,95,112,49,49,49]/1(i2)",
    "t_p112 c[116,95,112,49,49,50]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],a[97])))",
    "t_p113 c[116,95,112,49,49,51]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[110,111,116,95,108,101,115,115,95,116,104,97,110,95,122,101,114,111],i-1)))",
    "t_p114 c[116,95,112,49,49,52]/1(i5)",
    "t_p115 c[116,95,112,49,49,53]/1(i0)",
    "t_p116 c[116,95,112,49,49,54]/1(i3)",
    "t_p117 c[116,95,112,49,49,55]/1(i2)",
    "t_p118 c[116,95,112,49,49,56]/1(i9)",
    "t_p119 c[116,95,112,49,49,57]/1(i3)",
    "t_p120 c[116,95,112,49,50,48]/1(a[121,101,115])",
    "t_p121",
    "t_p122 c[116,95,112,49,50,50]/1(i1)",
    "t_p123 c[116,95,112,49,50,51]/1(i7)",
    "t_p124 c[116,95,112,49,50,52]/1(i4)",
    "t_p125 c[116,95,112,49,50,53]/1(i9)",
    "t_p126",
    "t_p127 c[116,95,112,49,50,55]/1(a[121,101,115])",
    "t_p128 c[116,95,112,49,50,56]/1(a[121,101,115])",
    "t_p129 c[116,95,112,49,50,57]/1(a[110,111])",
    "t_p130 c[116,95,112,49,51,48]/1(a[121,101,115])",
    "t_p131 c[116,95,112,49,51,49]/1(a[110,111])",
    "t_p132 c[116,95,112,49,51,50]/1(a[110,111])",
    "t_p133 c[116,95,112,49,51,51]/1(a[110,111])",
    "t_p134 c[116,95,112,49,51,52]/1(a[110,111])",
    "t_p135 c[116,95,112,49,51,53]/1(a[110,111])",
    "t_p136 c[116,95,112,49,51,54]/1(a[121,101,115])",
    "t_p137 c[116,95,112,49,51,55]/1(a[110,111])",
    "t_p138 c[116,95,112,49,51,56]/1(a[110,111])",
    "t_p139 c[116,95,112,49,51,57]/1(a[121,101,115])",
    "t_p140 c[116,95,112,49,52,48]/1(a[110,111])",
    "t_p141 c[116,95,112,49,52,49]/1(a[110,111])",
    "t_p142 c[116,95,112,49,52,50]/1(a[121,101,115])",
    "t_p143 c[116,95,112,49,52,51]/1(a[110,111])",
    "t_p144 c[116,95,112,49,52,52]/1(a[110,111])",
    "t_p145 c[116,95,112,49,52,53]/1(i2)",
    "t_p146 c[116,95,112,49,52,54]/1(i1)",
    "t_p147 c[116,95,112,49,52,55]/1(c[45]/2(V0,V0))",
    "t_p148 c[116,95,112,49,52,56]/1(c[45]/2(c[91,124,93]/2(V0,nil),V0))",
    "t_p149 c[116,95,112,49,52,57]/1(nil)",
    "t_p150 c[116,95,112,49,53,48]/1(nil)",
    "t_p151 c[116,95,112,49,53,49]/1(c[45]/2(c[45]/2(c[45]/2(c[91,124,93]/2(V0,c[91,124,93]/2(V1,c[91,124,93]/2(V2,nil))),V0),V1),V2))",
    "t_p152 c[116,95,112,49,53,50]/1(c[45]/2(c[91,124,93]/2(V0,nil),V0))",
    "t_p153 c[116,95,112,49,53,51]/1(c[114,97,105,115,101,100]/1(c[114,101,112,114,101,115,101,110,116,97,116,105,111,110,95,101,114,114,111,114]/1(a[97,99,121,99,108,105,99,95,116,101,114,109])))",
    "t_p154 c[116,95,112,49,53,52]/1(c[45]/2(c[91,124,93]/2(V0,nil),V0))",
    "t_p155",
    "t_p156 c[116,95,112,49,53,54]/1(c[45]/2(c[45]/2(c[45]/2(V0,V1),V0),V1))",
    "t_p157 c[116,95,112,49,53,55]/1(nil)",
    "t_p158 c[116,95,112,49,53,56]/1(c[45]/2(c[45]/2(c[91,124,93]/2(V0,c[91,124,93]/2(V1,nil)),V0),V1))",
    "t_p159 c[116,95,112,49,53,57]/1(c[45]/2(nil,V0))",
    "t_p160",
    "t_p161 c[116,95,112,49,54,49]/1(c[45]/2(c[91,124,93]/2(V0,c[91,124,93]/2(V1,nil)),c[91,124,93]/2(V0,c[91,124,93]/2(V1,nil))))",
    "t_p162 c[116,95,112,49,54,50]/1(c[45]/2(c[91,124,93]/2(V0,nil),V0))",
    "t_p163 c[116,95,112,49,54,51]/1(nil)",
    "t_p164 c[116,95,112,49,54,52]/1(c[45]/2(c[91,124,93]/2(V0,nil),V0))",
    "t_p165 c[116,95,112,49,54,53]/1(nil)",
    "t_p166 c[116,95,112,49,54,54]/1(c[114,97,105,115,101,100]/1(c[114,101,112,114,101,115,101,110,116,97,116,105,111,110,95,101,114,114,111,114]/1(a[97,99,121,99,108,105,99,95,116,101,114,109])))",
    "t_p167 c[116,95,112,49,54,55]/1(c[45]/2(c[45]/2(c[91,124,93]/2(V0,c[91,124,93]/2(V1,nil)),V0),V1))",
    "t_p168 c[116,95,112,49,54,56]/1(c[45]/2(c[45]/2(V0,nil),V0))",
    "t_p169 c[116,95,112,49,54,57]/1(c[45]/2(c[45]/2(c[45]/2(V0,V1),V0),V1))",
    "t_p170",
    "t_p171 c[116,95,112,49,55,49]/1(c[45]/2(c[91,124,93]/2(V0,nil),V0))",
    "t_p172 c[116,95,112,49,55,50]/1(c[45]/2(c[91,124,93]/2(V0,nil),V0))",
    "t_p173 c[116,95,112,49,55,51]/1(c[45]/2(c[45]/2(c[45]/2(c[91,124,93]/2(V0,c[91,124,93]/2(V1,nil)),V0),V1),V2))",
    "t_p174 c[116,95,112,49,55,52]/1(c[45]/2(c[45]/2(i2,a[99]),a[100]))",
    "t_p175 c[116,95,112,49,55,53]/1(i2)",
    "t_p176 c[116,95,112,49,55,54]/1(c[45]/2(V0,V0))"
]

function _p1_file()::Tuple{String, Vector{String}}
    names = ["t_$(id)" for (id, _) in _P1_CASES]
    text =
        _P1_PROGRAM * join([
            "t_$(id)(R) :- catch(($g), error(SsuE, _), R = raised(SsuE)).\n" for
            (id, g) in _P1_CASES
        ])
    f = joinpath(mktempdir(), "p1.pl")
    write(f, text)
    return f, names
end

"The kernel's lines for `names` after consulting `path`, as the driver writes swipl's; the database, for the white-box tests."
function _p1_kernel(path::String, names::Vector{String})
    gd = LK.PL_global_data{_P1}()
    ld = LK.PL_local_data{_P1}(gd)
    st, ball, _ = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * _p1_enc(ball::_P1)]
    for name in names
        proc = LK.isCurrentProcedure(sym_key(_p1s(name)), 1, LK.MODULE_user(gd))
        if proc === nothing || !LK.isDefinedProcedure(gd, proc)
            push!(out, "$name undefined")
            continue
        end
        sols = String[]
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 1)
        LK.putSlotValue!(ld, a + 1, mk_var(_P1, LK.fresh_var_keys!(1)), LK.PutVarMap())
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
        )
        n = 0
        while (n += 1) <= 50
            rc = LK.PL_next_solution(gd, ld, qid)
            if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
                push!(
                    sols,
                    _p1_enc(mk_expr(_P1, _P1[_p1s(name), lk_answers(ld, (a:a)...)...]))
                )
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
        push!(out, "$name" * join(" " .* sols))
    end
    return out, gd, ld
end

@testset "P1 term inspection as swipl's (p001-p176)" begin
    f, names = _p1_file()
    kl, _, _ = _p1_kernel(f, names)
    @test length(kl) == length(_P1_PINNED)
    for (k, p) in zip(kl, _P1_PINNED)
        k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
        @test k == p
    end
end

@testset "the P1 rows are not vacuous (p001-p176)" begin
    # the program loaded (`ok`); each predicate's group answers; the failing and the raising rows are told apart
    @test _P1_PINNED[1] == "ok"
    @test length(_P1_PINNED) == length(_P1_CASES) + 1
    answered = count(l -> occursin(' ', l), _P1_PINNED[2:end])
    failed = count(l -> !occursin(' ', l), _P1_PINNED[2:end])
    @test answered >= 100
    @test failed >= 15                                                          # rows that failed: no answer line
    @test count(l -> occursin(_p1_codes("raised"), l), _P1_PINNED) >= 25   # the error rows
    for pre in (
        "t_p001 ",
        "t_p012 ",
        "t_p029 ",
        "t_p052 ",
        "t_p071 ",
        "t_p093 ",
        "t_p101 ",
        "t_p127 ",
        "t_p148 ",
        "t_p162 "
    )
        @test any(l -> startswith(l, pre), _P1_PINNED)                           # each predicate's first row answers
    end
    @test any(l -> startswith(l, "t_p012 ") && occursin("i3", l), _P1_PINNED)    # the enumeration reached the last argument
    for pre in ("t_p174 ", "t_p175 ", "t_p176 ")
        @test any(l -> startswith(l, pre), _P1_PINNED)                           # the mutant-killing rows answer
    end
end

@testset "the P1 pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    # the pinned table is the driver's whole output (the inert-testset guard: an assertion either way)
    @test length(_P1_PINNED) == length(_P1_CASES) + 1
    if swipl === nothing
        @info "P1 LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        f, names = _p1_file()
        @test _p1_swipl_lines(f, names) == _P1_PINNED
    end
end

# `$expr/n` (KERNEL-ONLY: swipl has no compound whose head is not a symbol). UNVERIFIED on the kernel: gate decides.
# compound_name_arity/3 and compound_name_arguments/3 answer the name `$expr` and ALL the children (PL_get_name_arity), as
# `=..` does (DIVERGES, flagged in evidence/P1/handoff.md): arity = the number of children, the arguments = the children.
@testset "P1: compound_name_arity/arguments on a \$expr/n compound (kernel-only)" begin
    prog = raw"""
t_ex_arity(E, R) :- compound_name_arity(E, N, A), R = N/A.
t_ex_args(E, R) :- compound_name_arguments(E, N, As), R = N-As.
"""
    f = joinpath(mktempdir(), "p1_expr.pl")
    write(f, prog)
    expr_codes = _p1_codes("\$expr")
    function answer(name::String, e::_P1)::String
        gd = LK.PL_global_data{_P1}()
        ld = LK.PL_local_data{_P1}(gd)
        st, _, _ = LK.load_file!(gd, ld, f)
        @test st === :ok
        proc = LK.isCurrentProcedure(sym_key(_p1s(name)), 2, LK.MODULE_user(gd))
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 2)
        LK.putSlotValue!(ld, a + 1, e, LK.PutVarMap())
        LK.putSlotValue!(ld, a + 2, mk_var(_P1, LK.fresh_var_keys!(1)), LK.PutVarMap())
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
        )
        rc = LK.PL_next_solution(gd, ld, qid)
        r = if (rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST)
            _p1_enc(lk_answers(ld, a + 1)[1])
        else
            "no"
        end
        LK.PL_close_query(ld, qid)
        LK.PL_close_foreign_frame(ld, fid)
        return r
    end
    vh = mk_expr(_P1, _P1[mk_var(_P1, LK.fresh_var_keys!(1)), _p1s("a")])      # (X a)
    gh = mk_expr(_P1, _P1[lk_gnd(_P1, 5), _p1s("a"), _p1s("b")])                # (5 a b)
    cons(h, t) = "c[91,124,93]/2($h,$t)"
    @test answer("t_ex_arity", vh) == "c[47]/2(a$expr_codes,i2)"
    @test answer("t_ex_arity", gh) == "c[47]/2(a$expr_codes,i3)"
    @test answer("t_ex_args", vh) ==
        "c[45]/2(a$expr_codes," * cons("V0", cons("a[97]", "nil")) * ")"
    @test answer("t_ex_args", gh) ==
        "c[45]/2(a$expr_codes," * cons("i5", cons("a[97]", cons("a[98]", "nil"))) * ")"
end
