# ORIGINAL: a LIVE differential of BOOTPRED3's five boot-load-path predicates against swipl at the pin — `'$memberchk'/3`
# (pl-list.c:109-152), `'$inc_message_count'/1` (pl-error.c:1457-1474), `'$notrace'/2` and `'$restore_trace'/2` (pl-pro.c:317-390),
# prolog_listen/2,3 (pl-event.c:241-290) and variant_sha1/2 (pl-termhash.c:659-681); audit D-0354 ruling 2. Rows bp3m01-bp3v14:
#   * A PROGRAM consulted by the kernel's loader and cases `t_<id>(R)` run in order in one database, each wrapped in
#     `catch(Goal, error(SsuE, _), R = raised(SsuE))`; the driver is test_style_check_swipl.jl's (`enc`oded answers).
#   * Every answer line is swipl's, PINNED (swipl 10.1.19-1-gcbf4e189, lk-channel evidence/BOOTPRED3/bp3_rows.out on the branch);
#     with `swipl` on PATH the live answers are compared with the pins too.
#   * KNOWN DIFFERENCES, each a row whose pin is swipl's answer and whose kernel answer is pinned too (`_B3_KNOWN`, with swipl's in
#     a comment): the debugger state and the message counters are not kernel state (src/pl-pro.jl, src/pl-error.jl: rows bp3n01,
#     bp3n07, bp3n18, bp3i11, bp3i12; the listeners of prolog_listen/2,3 are kept since EV1: row bp3l33 is swipl's answer), and variant_sha1's DIGEST VALUES are not swipl's (pl-termhash.jl DIVERGES 1-2: row bp3v15; the other v-rows compare lengths,
#     alphabet and variant equality, never a digest). A known row stops being one when its kernel line equals swipl's.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — these built-ins ride the term layer through the FLI (unify, get, strip module);
# `variant_sha1/2` exports the term from its cells
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _B3 = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_b3s(x) = lk_sym(_B3, Symbol(x))


_b3_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _b3_enc(t::_B3, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _b3_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _b3_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _b3_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_b3_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

# the swipl side: test/core_lang/test_ssu_swipl.jl's driver (consult, then every answer of each t_<id>/1, `enc`oded)
const _B3_DRIVER = raw"""
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
function _b3_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _B3_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(pipeline(`swipl -q $f`; stdin=devnull, stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end




# the program: closures for the listeners (an atom closure is called with the event's arguments, so every arity),
# helpers for the digest rows, and a list builder for the long-list row
const _B3_PROGRAM = raw"""
:- dynamic bp3_hit/1.
bp3_hit1(_) :- assertz(bp3_hit(x)).
bp3_cb.
bp3_cb(_).
bp3_cb(_, _).
bp3_cb(_, _, _).
bp3_hex([]).
bp3_hex([C|Cs]) :- ( C >= 0'0, C =< 0'9 ; C >= 0'a, C =< 0'f ), !, bp3_hex(Cs).
bp3_mk(0, []) :- !.
bp3_mk(N, [N|T]) :- N1 is N-1, bp3_mk(N1, T).
"""

# bp3m: '$memberchk'/3 (pl-list.c:109-152); bp3i: '$inc_message_count'/1 (pl-error.c:1457-1474); bp3n: '$notrace'/2 and
# '$restore_trace'/2 (pl-pro.c:317-390); bp3l: prolog_listen/2,3 (pl-event.c:241-290); bp3v: variant_sha1/2 (pl-termhash.c:659-681).
# The debugger state is not kernel state (the file header of src/pl-pro.jl): the n-rows never pass the tracing or debugging
# bits; the skip level swipl reads first is 0 and the kernel's is -1 (rows bp3n01, bp3n07, bp3n18). The error and warning counters
# are not kept by the kernel (src/pl-error.jl): bp3i01-bp3i10 check arguments, bp3i11 and bp3i12 read the counters. Listeners on
# a predicate have their rows in test_event_swipl.jl (EV1); a cyclic list has no row (the kernel has no cyclic terms).
const _B3_CASES = [
    ("bp3m01", raw"'$memberchk'(b, [a,b,c], T), R = T"),
    ("bp3m02", raw"'$memberchk'(z, [a,b], T), R = T"),
    ("bp3m03", raw"'$memberchk'(X, [a,b], T), R = X-T"),
    ("bp3m04", raw"'$memberchk'(c, [a,b|L], T), ( T == L -> R = same ; R = diff )"),
    ("bp3m05", raw"'$memberchk'(a, L, T), ( T == L -> R = same ; R = diff )"),
    ("bp3m06", raw"'$memberchk'(a, [a|b], T), R = T"),
    ("bp3m07", raw"'$memberchk'(z, [a|b], T), R = T"),
    ("bp3m08", raw"'$memberchk'(a, foo, T), R = T"),
    ("bp3m09", raw"'$memberchk'(a, 1, T), R = T"),
    ("bp3m10", raw"'$memberchk'(f(X), [g(1), f(2), f(3)], T), R = X-T"),
    ("bp3m11", raw"'$memberchk'(f(X,X), [f(1,2), f(3,3)], T), R = X-T"),
    ("bp3m12", raw"'$memberchk'(a, [], T), R = T"),
    ("bp3m13", raw"'$memberchk'(c, [b,c], x), R = yes"),
    ("bp3m14", raw"findall(X-T, '$memberchk'(X, [a,b], T), R)"),
    ("bp3m15", raw"'$memberchk'(f(X,b), [f(1,a), f(2,b)], T), R = X-T"),
    ("bp3m16", raw"bp3_mk(12000, L), '$memberchk'(1, L, T), R = T"),
    ("bp3m17", raw"'$memberchk'(a, [a,b], []), R = yes"),
    ("bp3m18", raw"'$memberchk'(f(_), [f(x)|_], T), R = T"),
    ("bp3i01", raw"'$inc_message_count'(error), R = yes"),
    ("bp3i02", raw"'$inc_message_count'(warning), R = yes"),
    ("bp3i03", raw"'$inc_message_count'(informational), R = yes"),
    ("bp3i04", raw"'$inc_message_count'(foo), R = yes"),
    ("bp3i05", raw"'$inc_message_count'(1), R = yes"),
    ("bp3i06", raw"'$inc_message_count'(_), R = yes"),
    ("bp3i07", raw"'$inc_message_count'(f(x)), R = yes"),
    ("bp3i08", raw"'$inc_message_count'(1.5), R = yes"),
    ("bp3i09", raw"'$inc_message_count'([]), R = yes"),
    ("bp3i10", raw"findall(x, '$inc_message_count'(error), R)"),
    ("bp3i11", raw"statistics(errors, E0), '$inc_message_count'(error), statistics(errors, E1), R is E1-E0"),
    ("bp3i12", raw"statistics(warnings, E0), '$inc_message_count'(warning), statistics(warnings, E1), R is E1-E0"),
    ("bp3n01", raw"'$notrace'(F, S), '$restore_trace'(F, S), R = F-S"),
    ("bp3n02", raw"'$notrace'(F0, S0), '$notrace'(F, S), '$restore_trace'(F0, S0), R = F-S"),
    ("bp3n03", raw"'$notrace'(F0, S0), '$restore_trace'(0, -1), '$notrace'(F, _), '$restore_trace'(F0, S0), R = F"),
    ("bp3n04", raw"'$notrace'(F0, S0), '$restore_trace'(4, -1), '$notrace'(F, _), '$restore_trace'(F0, S0), R = F"),
    ("bp3n05", raw"'$notrace'(F0, S0), '$restore_trace'(8, -1), '$notrace'(F, _), '$restore_trace'(F0, S0), R = F"),
    ("bp3n06", raw"'$notrace'(F0, S0), '$restore_trace'(12, -1), '$notrace'(F, _), '$restore_trace'(F0, S0), R = F"),
    ("bp3n07", raw"'$notrace'(F0, S0), '$restore_trace'(F0, -2), '$notrace'(_, S), '$restore_trace'(F0, S0), R = S"),
    ("bp3n08", raw"'$notrace'(a, _), R = yes"),
    ("bp3n09", raw"'$notrace'(_, 5), R = yes"),
    ("bp3n10", raw"'$restore_trace'(a, -1), R = yes"),
    ("bp3n11", raw"'$restore_trace'(_, -1), R = yes"),
    ("bp3n12", raw"'$restore_trace'(12, a), R = yes"),
    ("bp3n13", raw"'$restore_trace'(12, _), R = yes"),
    ("bp3n14", raw"'$restore_trace'(4294967296, -1), R = yes"),
    ("bp3n15", raw"'$restore_trace'(12, -3), R = yes"),
    ("bp3n16", raw"'$restore_trace'(12, -1.5), R = yes"),
    ("bp3n17", raw"'$restore_trace'(12, 99999999999999999999), R = yes"),
    ("bp3n18", raw"'$notrace'(F0, S0), '$restore_trace'(F0, S0), '$restore_trace'(F0, S0), '$notrace'(F, S), '$restore_trace'(F0, S0), R = F-S"),
    ("bp3n19", raw"'$notrace'(F0, S0), '$notrace'(F, _), '$restore_trace'(F0, S0), R = F"),
    ("bp3l01", raw"prolog_listen(untable, bp3_cb), R = yes"),
    ("bp3l02", raw"prolog_listen(untable, bp3_cb, [as(last)]), R = yes"),
    ("bp3l03", raw"prolog_listen(untable, bp3_cb, [as(first)]), R = yes"),
    ("bp3l04", raw"prolog_listen(untable, bp3_cb, [name(bp3_n1)]), R = yes"),
    ("bp3l05", raw"prolog_listen(untable, bp3_cb, [name(bp3_n1)]), R = yes"),
    ("bp3l06", raw"prolog_listen(untable, bp3_cb, [as(last), name(bp3_n2)]), R = yes"),
    ("bp3l07", raw"prolog_listen(untable, bp3_cb, []), R = yes"),
    ("bp3l08", raw"prolog_listen(untable, bp3_cb, [as(middle)]), R = yes"),
    ("bp3l09", raw"prolog_listen(untable, bp3_cb, [as(1)]), R = yes"),
    ("bp3l10", raw"prolog_listen(untable, bp3_cb, [foo(1)]), R = yes"),
    ("bp3l11", raw"prolog_listen(untable, bp3_cb, foo), R = yes"),
    ("bp3l12", raw"prolog_listen(untable, bp3_cb, [as(last)|_]), R = yes"),
    ("bp3l13", raw"prolog_listen(nosuchevent, bp3_cb), R = yes"),
    ("bp3l14", raw"prolog_listen(1, bp3_cb), R = yes"),
    ("bp3l15", raw"prolog_listen(_, bp3_cb), R = yes"),
    ("bp3l16", raw"prolog_listen(untable, 1), R = yes"),
    ("bp3l17", raw"prolog_listen(untable, _), R = yes"),
    ("bp3l18", raw"prolog_listen(untable, user:bp3_cb), R = yes"),
    ("bp3l19", raw"prolog_listen(untable, user:1), R = yes"),
    ("bp3l20", raw"prolog_listen(abort, bp3_cb), R = yes"),
    ("bp3l21", raw"prolog_listen(erase, bp3_cb), R = yes"),
    ("bp3l22", raw"prolog_listen(break, bp3_cb), R = yes"),
    ("bp3l23", raw"prolog_listen(frame_finished, bp3_cb), R = yes"),
    ("bp3l24", raw"prolog_listen(thread_start, bp3_cb), R = yes"),
    ("bp3l25", raw"prolog_listen(thread_exit, bp3_cb), R = yes"),
    ("bp3l26", raw"prolog_listen(this_thread_exit, bp3_cb), R = yes"),
    ("bp3l27", raw"prolog_listen(untable, bp3_cb(a)), R = yes"),
    ("bp3l28", raw"prolog_listen(untable, bp3_cb, [as(middle), name(bp3_n3)]), R = yes"),
    ("bp3l29", raw"findall(x, prolog_listen(untable, bp3_cb), R)"),
    ("bp3l30", raw"prolog_listen(untable, bp3_cb, [name(1)]), R = yes"),
    ("bp3l31", raw"prolog_listen(nosuchevent, 1, [as(first)]), R = yes"),
    ("bp3l32", raw"prolog_listen(1, bp3_cb, [as(middle)]), R = yes"),
    ("bp3l33", raw"prolog_listen(erase, bp3_hit1), recorda(bp3_k, v, Ref), erase(Ref), findall(H, bp3_hit(H), Hs), length(Hs, R)"),
    ("bp3v01", raw"variant_sha1(foo, H), atom_length(H, R)"),
    ("bp3v02", raw"variant_sha1(f(X,Y,X), H1), variant_sha1(f(A,B,A), H2), ( H1 == H2 -> R = same ; R = diff )"),
    ("bp3v03", raw"variant_sha1(f(X,Y), H1), variant_sha1(f(X,X), H2), ( H1 == H2 -> R = same ; R = diff )"),
    ("bp3v04", raw"variant_sha1(f(a), H), ( atom(H) -> R = atom ; R = other )"),
    ("bp3v05", raw"variant_sha1(f(a,_), H), atom_codes(H, Cs), ( bp3_hex(Cs) -> R = hex ; R = nothex )"),
    ("bp3v06", raw"variant_sha1(a, H1), variant_sha1(b, H2), ( H1 == H2 -> R = same ; R = diff )"),
    ("bp3v07", raw"variant_sha1(a, H1), variant_sha1(a, H2), ( H1 == H2 -> R = same ; R = diff )"),
    ("bp3v08", raw"variant_sha1(a, foo), R = yes"),
    ("bp3v09", raw"variant_sha1(a, 1), R = yes"),
    ("bp3v10", raw"findall(H, variant_sha1(g(_), H), Hs), length(Hs, R)"),
    ("bp3v11", raw"variant_sha1([a,b|T], H1), variant_sha1([a,b|U], H2), ( H1 == H2 -> R = same ; R = diff )"),
    ("bp3v12", raw"variant_sha1(1, H1), variant_sha1(2, H2), ( H1 == H2 -> R = same ; R = diff )"),
    ("bp3v13", raw"variant_sha1(f(X,Y), H1), variant_sha1(f(Y,X), H2), ( H1 == H2 -> R = same ; R = diff )"),
    ("bp3v14", raw"variant_sha1(f(a), H), atom_length(H, R)"),
    ("bp3v15", raw"variant_sha1(foo, R)")
]

# the driver's whole output, one line per case after `ok`, filled by evidence/BOOTPRED3/gen_rows.py --fill from swipl 10.1.19
const _B3_PINNED = [
    "ok",
    "t_bp3m01 c[116,95,98,112,51,109,48,49]/1(nil)",
    "t_bp3m02",
    "t_bp3m03 c[116,95,98,112,51,109,48,51]/1(c[45]/2(a[97],nil))",
    "t_bp3m04 c[116,95,98,112,51,109,48,52]/1(a[115,97,109,101])",
    "t_bp3m05 c[116,95,98,112,51,109,48,53]/1(a[115,97,109,101])",
    "t_bp3m06 c[116,95,98,112,51,109,48,54]/1(nil)",
    "t_bp3m07 c[116,95,98,112,51,109,48,55]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[108,105,115,116],a[98])))",
    "t_bp3m08 c[116,95,98,112,51,109,48,56]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[108,105,115,116],a[102,111,111])))",
    "t_bp3m09 c[116,95,98,112,51,109,48,57]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[108,105,115,116],i1)))",
    "t_bp3m10 c[116,95,98,112,51,109,49,48]/1(c[45]/2(i2,nil))",
    "t_bp3m11 c[116,95,98,112,51,109,49,49]/1(c[45]/2(i3,nil))",
    "t_bp3m12",
    "t_bp3m13",
    "t_bp3m14 c[116,95,98,112,51,109,49,52]/1(c[91,124,93]/2(c[45]/2(a[97],nil),nil))",
    "t_bp3m15 c[116,95,98,112,51,109,49,53]/1(c[45]/2(i2,nil))",
    "t_bp3m16 c[116,95,98,112,51,109,49,54]/1(nil)",
    "t_bp3m17 c[116,95,98,112,51,109,49,55]/1(a[121,101,115])",
    "t_bp3m18 c[116,95,98,112,51,109,49,56]/1(nil)",
    "t_bp3i01 c[116,95,98,112,51,105,48,49]/1(a[121,101,115])",
    "t_bp3i02 c[116,95,98,112,51,105,48,50]/1(a[121,101,115])",
    "t_bp3i03 c[116,95,98,112,51,105,48,51]/1(a[121,101,115])",
    "t_bp3i04 c[116,95,98,112,51,105,48,52]/1(a[121,101,115])",
    "t_bp3i05 c[116,95,98,112,51,105,48,53]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],i1)))",
    "t_bp3i06 c[116,95,98,112,51,105,48,54]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_bp3i07 c[116,95,98,112,51,105,48,55]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],c[102]/1(a[120]))))",
    "t_bp3i08 c[116,95,98,112,51,105,48,56]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],f1.5)))",
    "t_bp3i09 c[116,95,98,112,51,105,48,57]/1(a[121,101,115])",
    "t_bp3i10 c[116,95,98,112,51,105,49,48]/1(c[91,124,93]/2(a[120],nil))",
    "t_bp3i11 c[116,95,98,112,51,105,49,49]/1(i1)",
    "t_bp3i12 c[116,95,98,112,51,105,49,50]/1(i1)",
    "t_bp3n01 c[116,95,98,112,51,110,48,49]/1(c[45]/2(i12,i0))",
    "t_bp3n02 c[116,95,98,112,51,110,48,50]/1(c[45]/2(i12,i-1))",
    "t_bp3n03 c[116,95,98,112,51,110,48,51]/1(i0)",
    "t_bp3n04 c[116,95,98,112,51,110,48,52]/1(i4)",
    "t_bp3n05 c[116,95,98,112,51,110,48,53]/1(i8)",
    "t_bp3n06 c[116,95,98,112,51,110,48,54]/1(i12)",
    "t_bp3n07 c[116,95,98,112,51,110,48,55]/1(i-2)",
    "t_bp3n08",
    "t_bp3n09",
    "t_bp3n10 c[116,95,98,112,51,110,49,48]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],a[97])))",
    "t_bp3n11 c[116,95,98,112,51,110,49,49]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_bp3n12 c[116,95,98,112,51,110,49,50]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],a[97])))",
    "t_bp3n13 c[116,95,98,112,51,110,49,51]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_bp3n14 c[116,95,98,112,51,110,49,52]/1(c[114,97,105,115,101,100]/1(c[114,101,112,114,101,115,101,110,116,97,116,105,111,110,95,101,114,114,111,114]/1(a[105,110,116])))",
    "t_bp3n15 c[116,95,98,112,51,110,49,53]/1(c[114,97,105,115,101,100]/1(c[114,101,112,114,101,115,101,110,116,97,116,105,111,110,95,101,114,114,111,114]/1(a[115,105,122,101,95,116])))",
    "t_bp3n16 c[116,95,98,112,51,110,49,54]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],f-1.5)))",
    "t_bp3n17 c[116,95,98,112,51,110,49,55]/1(c[114,97,105,115,101,100]/1(c[114,101,112,114,101,115,101,110,116,97,116,105,111,110,95,101,114,114,111,114]/1(a[105,110,116,54,52,95,116])))",
    "t_bp3n18 c[116,95,98,112,51,110,49,56]/1(c[45]/2(i12,i0))",
    "t_bp3n19 c[116,95,98,112,51,110,49,57]/1(i12)",
    "t_bp3l01 c[116,95,98,112,51,108,48,49]/1(a[121,101,115])",
    "t_bp3l02 c[116,95,98,112,51,108,48,50]/1(a[121,101,115])",
    "t_bp3l03 c[116,95,98,112,51,108,48,51]/1(a[121,101,115])",
    "t_bp3l04 c[116,95,98,112,51,108,48,52]/1(a[121,101,115])",
    "t_bp3l05 c[116,95,98,112,51,108,48,53]/1(a[121,101,115])",
    "t_bp3l06 c[116,95,98,112,51,108,48,54]/1(a[121,101,115])",
    "t_bp3l07 c[116,95,98,112,51,108,48,55]/1(a[121,101,115])",
    "t_bp3l08 c[116,95,98,112,51,108,48,56]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[97,115],a[109,105,100,100,108,101])))",
    "t_bp3l09 c[116,95,98,112,51,108,48,57]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],i1)))",
    "t_bp3l10 c[116,95,98,112,51,108,49,48]/1(a[121,101,115])",
    "t_bp3l11 c[116,95,98,112,51,108,49,49]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[108,105,115,116],a[102,111,111])))",
    "t_bp3l12 c[116,95,98,112,51,108,49,50]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_bp3l13 c[116,95,98,112,51,108,49,51]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[101,118,101,110,116],a[110,111,115,117,99,104,101,118,101,110,116])))",
    "t_bp3l14 c[116,95,98,112,51,108,49,52]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,97,108,108,97,98,108,101],i1)))",
    "t_bp3l15 c[116,95,98,112,51,108,49,53]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_bp3l16 c[116,95,98,112,51,108,49,54]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,97,108,108,97,98,108,101],i1)))",
    "t_bp3l17 c[116,95,98,112,51,108,49,55]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_bp3l18 c[116,95,98,112,51,108,49,56]/1(a[121,101,115])",
    "t_bp3l19 c[116,95,98,112,51,108,49,57]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,97,108,108,97,98,108,101],c[58]/2(a[117,115,101,114],i1))))",
    "t_bp3l20 c[116,95,98,112,51,108,50,48]/1(a[121,101,115])",
    "t_bp3l21 c[116,95,98,112,51,108,50,49]/1(a[121,101,115])",
    "t_bp3l22 c[116,95,98,112,51,108,50,50]/1(a[121,101,115])",
    "t_bp3l23 c[116,95,98,112,51,108,50,51]/1(a[121,101,115])",
    "t_bp3l24 c[116,95,98,112,51,108,50,52]/1(a[121,101,115])",
    "t_bp3l25 c[116,95,98,112,51,108,50,53]/1(a[121,101,115])",
    "t_bp3l26 c[116,95,98,112,51,108,50,54]/1(a[121,101,115])",
    "t_bp3l27 c[116,95,98,112,51,108,50,55]/1(a[121,101,115])",
    "t_bp3l28 c[116,95,98,112,51,108,50,56]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[97,115],a[109,105,100,100,108,101])))",
    "t_bp3l29 c[116,95,98,112,51,108,50,57]/1(c[91,124,93]/2(a[120],nil))",
    "t_bp3l30 c[116,95,98,112,51,108,51,48]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],i1)))",
    "t_bp3l31 c[116,95,98,112,51,108,51,49]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[101,118,101,110,116],a[110,111,115,117,99,104,101,118,101,110,116])))",
    "t_bp3l32 c[116,95,98,112,51,108,51,50]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[97,115],a[109,105,100,100,108,101])))",
    "t_bp3l33 c[116,95,98,112,51,108,51,51]/1(i1)",
    "t_bp3v01 c[116,95,98,112,51,118,48,49]/1(i40)",
    "t_bp3v02 c[116,95,98,112,51,118,48,50]/1(a[115,97,109,101])",
    "t_bp3v03 c[116,95,98,112,51,118,48,51]/1(a[100,105,102,102])",
    "t_bp3v04 c[116,95,98,112,51,118,48,52]/1(a[97,116,111,109])",
    "t_bp3v05 c[116,95,98,112,51,118,48,53]/1(a[104,101,120])",
    "t_bp3v06 c[116,95,98,112,51,118,48,54]/1(a[100,105,102,102])",
    "t_bp3v07 c[116,95,98,112,51,118,48,55]/1(a[115,97,109,101])",
    "t_bp3v08",
    "t_bp3v09",
    "t_bp3v10 c[116,95,98,112,51,118,49,48]/1(i1)",
    "t_bp3v11 c[116,95,98,112,51,118,49,49]/1(a[115,97,109,101])",
    "t_bp3v12 c[116,95,98,112,51,118,49,50]/1(a[100,105,102,102])",
    "t_bp3v13 c[116,95,98,112,51,118,49,51]/1(a[115,97,109,101])",
    "t_bp3v14 c[116,95,98,112,51,118,49,52]/1(i40)",
    "t_bp3v15 c[116,95,98,112,51,118,49,53]/1(a[99,101,101,55,49,101,98,99,49,100,48,50,51,97,102,49,51,49,101,51,52,54,49,98,51,50,50,101,52,50,53,49,98,50,101,53,97,53,49,48])"
]
# KNOWN DIFFERENCE rows: the id of the driver line -> the kernel's exact line (swipl's is the pin above). Each swipl answer is quoted
# in the comment; DBG1 and the counters' struct field retire them (EV1 retired row bp3l33).
const _B3_KNOWN = Dict{String, String}(
    # no error counter is kept (src/pl-error.jl DIVERGES): swipl counts 1
    "t_bp3i11" => "t_bp3i11 c[116,95,98,112,51,105,49,49]/1(i0)",
    # no warning counter is kept (src/pl-error.jl DIVERGES): swipl counts 1
    "t_bp3i12" => "t_bp3i12 c[116,95,98,112,51,105,49,50]/1(i0)",
    # swipl's first skip level is 0 (pl-pro.c:317-348 reads debugstatus.skiplevel); the kernel has no such state and reads -1
    "t_bp3n01" => "t_bp3n01 c[116,95,98,112,51,110,48,49]/1(c[45]/2(i12,i-1))",
    # swipl reads back the -2 it restored (pl-pro.c:350-390); the kernel keeps no skip level and reads -1
    "t_bp3n07" => "t_bp3n07 c[116,95,98,112,51,110,48,55]/1(i-1)",
    # as bp3n01: swipl's skip level is 0 at the start of the row's save/restore pair, the kernel's -1
    "t_bp3n18" => "t_bp3n18 c[116,95,98,112,51,110,49,56]/1(c[45]/2(i12,i-1))",
    # the digest values are not swipl's (src/pl-termhash.jl DIVERGES 1-2): swipl's is cee71ebc1d023af131e3461b322e4251b2e5a510
    "t_bp3v15" => "t_bp3v15 c[116,95,98,112,51,118,49,53]/1(a[53,100,97,52,50,51,51,48,52,100,101,50,50,97,101,53,97,49,52,102,56,54,49,57,55,55,53,99,98,49,53,49,99,97,54,55,102,100,55,53])"
)

function _b3_file()::Tuple{String, Vector{String}}
    names = ["t_$(id)" for (id, _) in _B3_CASES]
    text =
        _B3_PROGRAM * join([
            "t_$(id)(R) :- catch(($g), error(SsuE, _), R = raised(SsuE)).\n" for
            (id, g) in _B3_CASES
        ])
    f = joinpath(mktempdir(), "bootpred3.pl")
    write(f, text)
    return f, names
end

"The kernel's lines for `names` after consulting `path`, as the driver writes swipl's; the database, for the white-box tests."
function _b3_kernel(path::String, names::Vector{String})
    gd = LK.PL_global_data{_B3}()
    ld = LK.PL_local_data{_B3}(gd)
    st, ball, _ = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * _b3_enc(ball::_B3)]
    for name in names
        proc = LK.isCurrentProcedure(sym_key(_b3s(name)), 1, LK.MODULE_user(gd))
        if proc === nothing || !LK.isDefinedProcedure(gd, proc)
            push!(out, "$name undefined")
            continue
        end
        sols = String[]
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 1)
        LK.putSlotValue!(ld, a + 1, mk_var(_B3, LK.fresh_var_keys!(1)), LK.PutVarMap())
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
        )
        n = 0
        while (n += 1) <= 50
            rc = LK.PL_next_solution(gd, ld, qid)
            if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
                push!(
                    sols,
                    _b3_enc(mk_expr(_B3, _B3[_b3s(name), lk_answers(ld, (a:a)...)...]))
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


@testset "BOOTPRED3's five predicates as swipl's (bp3m, bp3i, bp3n, bp3l, bp3v)" begin
    f, names = _b3_file()
    kl, _, _ = _b3_kernel(f, names)
    @test length(kl) == length(_B3_PINNED)
    for (k, p) in zip(kl, _B3_PINNED)
        want = get(_B3_KNOWN, first(split(p, ' ')), p)
        k == want || println(stderr, "  ours  ", k, "\\n  swipl ", p)
        @test k == want
    end
end

@testset "KNOWN DIFFERENCES: the kernel's pinned answer is not swipl's" begin
    for (id, line) in _B3_KNOWN
        pin = filter(l -> first(split(l, ' ')) == id, _B3_PINNED)
        @test length(pin) == 1
        @test line != only(pin)
    end
end

@testset "the BOOTPRED3 rows are not vacuous" begin
    @test _B3_PINNED[1] == "ok"
    @test length(_B3_PINNED) == length(_B3_CASES) + 1
    for pre in ("bp3m", "bp3i", "bp3n", "bp3l", "bp3v")
        ids = [id for (id, _) in _B3_CASES if startswith(id, pre)]
        answered = [l for l in _B3_PINNED if any(id -> startswith(l, "t_$id "), ids)]
        failed = [l for l in _B3_PINNED if any(id -> l == "t_$id", ids)]
        @test !isempty(answered)                                            # some rows answer
        pre == "bp3v" || @test !isempty(failed) || pre == "bp3i" || pre == "bp3l"  # some rows fail, where the predicate can
    end
    @test count(l -> occursin("raised", l) || occursin(",97,105,115,101,100", l), _B3_PINNED) >= 1
    @test any(l -> startswith(l, "t_bp3m01 ") && endswith(l, "(nil)"), _B3_PINNED)           # found: the tail is []
    @test any(l -> startswith(l, "t_bp3m02") && !occursin(" ", l), _B3_PINNED)                # not found: fails
    @test any(l -> startswith(l, "t_bp3v01 ") && endswith(l, "(i40)"), _B3_PINNED)           # 40 hex digits
    @test any(l -> startswith(l, "t_bp3n01 "), _B3_PINNED)                                    # the saved state is read back
end

@testset "the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    @test length(_B3_PINNED) == length(_B3_CASES) + 1
    if swipl === nothing
        @info "BOOTPRED3 LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        f, names = _b3_file()
        @test _b3_swipl_lines(f, names) == _B3_PINNED
    end
end
