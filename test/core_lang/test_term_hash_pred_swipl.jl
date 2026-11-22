# ORIGINAL: a LIVE differential of term_hash/2 (pl-termhash.c:306-319), term_hash/4 (pl-prims.c termHashValue4) and
# variant_hash/2, variant_sha1/2 (pl-termhash.c:659-692) against swipl at the pin (18168e62, 10.1.20); audit D-0894. Rows:
#   th01-th50 term_hash/2 (atoms, every number class, strings, compounds, non-ground: the key stays unbound), tq01-tq42
#   term_hash/4 (depth, range, every error), vh01-vh24 variant_hash/2, vs01-vs26 variant_sha1/2; cy01-cy06 a CYCLIC argument.
#   * A PROGRAM consulted by the kernel's loader and cases `t_<id>(R)` run in order in one database, each wrapped in
#     `catch(Goal, error(SsuE, _), R = raised(SsuE))`; the driver is test_bootpred3_swipl.jl's (`enc`oded answers).
#   * Every answer line is swipl's, PINNED (the pinned swipl, run twice, byte-identical output); with `swipl` on PATH the
#     live answers are compared with the pins too. The VALUES are swipl's: a hash is the same number, a digest the same
#     40 hex digits (src/pl-termhash.jl header, DIVERGES 1).
#   * No row hashes a string with a code above 0xff by term_hash (swipl leaves that undefined, the kernel hashes its UTF-8
#     bytes); variant_hash and variant_sha1 of one (rows vh20, vs04) are swipl's UCS-4 bytes.
#   * KNOWN DIFFERENCES (`_TH_CY_KNOWN`): swipl answers a CYCLIC argument (rows cy01-cy04, cy06), the kernel refuses it by name
#     (`NotPortedError`, owner R2: docs/r2_owners.tsv); each runs in a FRESH database and its pin is swipl's answer. Row cy05
#     (term_hash/4 with depth 0 never descends) is the kernel's too. A known row stops being one when its kernel line equals swipl's.
#   * Row vs16: a bare attributed variable to variant_sha1/2 is swipl's `instantiation_error` (type_error on an unbound term).
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — these built-ins ride the term layer through the FLI (unify, get, export from the cells)
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TH = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_ths(x) = lk_sym(_TH, Symbol(x))

_th_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _th_enc(t::_TH, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _th_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _th_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _th_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_th_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

# the swipl side: test_bootpred3_swipl.jl's driver (consult, then every answer of each t_<id>/1, `enc`oded)
const _TH_DRIVER = raw"""
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
function _th_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _TH_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(pipeline(`swipl -q $f`; stdin=devnull, stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

# the program: the helpers the rows call (`thx_h` leaves `unbound` for a term_hash that stays unbound), a list builder
const _TH_PROGRAM = raw"""

thx_h(T, R) :- term_hash(T, H), ( var(H) -> R = unbound ; R = H ).
thx_h4(T, D, G, R) :- term_hash(T, D, G, H), ( var(H) -> R = unbound ; R = H ).
thx_same(A, B, R) :- ( A == B -> R = same ; R = diff ).
thx_cs(Cs, S) :- string_codes(S, Cs).
thx_ca(Cs, A) :- atom_codes(A, Cs).
thx_mk(0, []) :- !.
thx_mk(N, [N|T]) :- N1 is N-1, thx_mk(N1, T).
"""

# thr: term_hash/2 (th), term_hash/4 (tq), variant_hash/2 (vh), variant_sha1/2 (vs); cyclic rows below
const _TH_CASES = [
    ("th01", raw"""thx_h(foo, R)"""),
    ("th02", raw"""thx_h(a, R)"""),
    ("th03", raw"""thx_h('', R)"""),
    ("th04", raw"""thx_h([], R)"""),
    ("th05", raw"""thx_h('[]', R)"""),
    ("th06", raw"""thx_ca([233], A), thx_h(A, R)"""),
    ("th07", raw"""thx_ca([26085, 26412], A), thx_h(A, R)"""),
    ("th08", raw"""thx_h(0, R)"""),
    ("th09", raw"""thx_h(1, R)"""),
    ("th10", raw"""thx_h(-1, R)"""),
    ("th11", raw"""thx_h(42, R)"""),
    ("th12", raw"""thx_h(1.5, R)"""),
    ("th13", raw"""thx_h(0.0, R)"""),
    ("th14", raw"""thx_h(-0.0, R)"""),
    ("th15", raw"""X is 2^56-1, thx_h(X, R)"""),
    ("th16", raw"""X is -(2^56), thx_h(X, R)"""),
    ("th17", raw"""X is -(2^56)-1, thx_h(X, R)"""),
    ("th18", raw"""X is 2^56, thx_h(X, R)"""),
    ("th19", raw"""X is 2^63, thx_h(X, R)"""),
    ("th20", raw"""X is 2^70, thx_h(X, R)"""),
    ("th21", raw"""X is -(2^70), thx_h(X, R)"""),
    ("th22", raw"""X is 1 rdiv 3, thx_h(X, R)"""),
    ("th23", raw"""X is -1 rdiv 3, thx_h(X, R)"""),
    ("th24", raw"""X is 2^200 rdiv 3, thx_h(X, R)"""),
    ("th25", raw"""thx_h(1.0, R)"""),
    ("th26", raw"""thx_h(100.0, R)"""),
    ("th27", raw"""thx_h("abc", R)"""),
    ("th28", raw"""thx_h("", R)"""),
    ("th29", raw"""thx_cs([233], S), thx_h(S, R)"""),
    ("th31", raw"""thx_h(f(a), R)"""),
    ("th32", raw"""thx_h(f(a,b), R)"""),
    ("th33", raw"""thx_h([a,b], R)"""),
    ("th34", raw"""thx_h(f(g(h(a))), R)"""),
    ("th35", raw"""thx_h(foo(bar,"baz",1,2.0), R)"""),
    ("th36", raw"""thx_h(f(a,b), H1), thx_h(f(a,b), H2), thx_same(H1, H2, R)"""),
    ("th37", raw"""thx_h(f(a,b), H1), thx_h(f(b,a), H2), thx_same(H1, H2, R)"""),
    ("th38", raw"""thx_h(0, H1), thx_h(0.0, H2), thx_same(H1, H2, R)"""),
    ("th39", raw"""thx_h(1, H1), thx_h(1.0, H2), thx_same(H1, H2, R)"""),
    ("th40", raw"""thx_h([], H1), thx_h('[]', H2), thx_same(H1, H2, R)"""),
    ("th41", raw"""thx_h(f(a,b,c,d,e,f,g,h,i,j), R)"""),
    ("th42", raw"""thx_mk(300, L), thx_h(L, R)"""),
    ("th43", raw"""compound_name_arguments(T, f, []), thx_h(T, R)"""),
    ("th44", raw"""thx_h(_, R)"""),
    ("th45", raw"""thx_h(f(_), R)"""),
    ("th46", raw"""thx_h(f(a, g(b, _)), R)"""),
    ("th47", raw"""put_attr(X, m, 1), thx_h(X, R)"""),
    ("th48", raw"""put_attr(X, m, 1), thx_h(f(a, X), R)"""),
    ("th49", raw"""thx_h(f(a,b), 5)"""),
    ("th50", raw"""thx_h(f(a,b), H), integer(H), R = int"""),
    ("tq01", raw"""thx_h4(foo, 1, 100, R)"""),
    ("tq02", raw"""thx_h4(f(a,b), -1, 1000, R)"""),
    ("tq03", raw"""thx_h4(f(a,b), 1, 1000, R)"""),
    ("tq04", raw"""thx_h4(f(a,g(b,c)), 2, 1000000, R)"""),
    ("tq05", raw"""thx_h4(f(a,g(b,c)), 1, 1000000, R)"""),
    ("tq06", raw"""thx_h4(f(a,g(b,c)), 0, 1000000, R)"""),
    ("tq07", raw"""thx_h4(f(a,g(b,c)), 3, 1000000, R)"""),
    ("tq08", raw"""thx_h4(f(_,g(b,c)), -1, 1000000, R)"""),
    ("tq09", raw"""thx_h4(_, 0, 10, R)"""),
    ("tq10", raw"""thx_h4(_, 1, 10, R)"""),
    ("tq11", raw"""thx_h4("abc", 1, 1000, R)"""),
    ("tq12", raw"""thx_h4(1.5, 1, 1000, R)"""),
    ("tq13", raw"""thx_h4(42, 1, 1000, R)"""),
    ("tq14", raw"""thx_h4(foo, 1, 2147483647, R)"""),
    ("tq15", raw"""thx_h4([a,b,c], -1, 1000000, R)"""),
    ("tq16", raw"""thx_h4(g(h(i(j))), 2, 1000000, R)"""),
    ("tq17", raw"""thx_h4(foo, 0, 1, R)"""),
    ("tq18", raw"""thx_h4(f(a,g(_,c)), 2, 1000000, R)"""),
    ("tq19", raw"""thx_h4(f(a,g(_,c)), 1, 1000000, R)"""),
    ("tq20", raw"""thx_h4(f(a,b), 1, 1, R)"""),
    ("tq21", raw"""X is 2^70, thx_h4(X, 1, 1000000, R)"""),
    ("tq22", raw"""X is 1 rdiv 3, thx_h4(X, 1, 1000000, R)"""),
    ("tq23", raw"""thx_h4([], 1, 1000000, R)"""),
    ("tq24", raw"""thx_h4(f(a), 1, 1000000, R1), thx_h4(f(a), 2, 1000000, R2), thx_same(R1, R2, R)"""),
    ("tq25", raw"""thx_mk(100, L), thx_h4(L, 5, 1000000, R)"""),
    ("tq26", raw"""compound_name_arguments(T, f, []), thx_h4(T, 1, 1000000, R)"""),
    ("tq27", raw"""put_attr(X, m, 1), thx_h4(f(X), -1, 1000000, R)"""),
    ("tq28", raw"""thx_h4(foo, -2, 100, R)"""),
    ("tq29", raw"""thx_h4(foo, 1, 0, R)"""),
    ("tq30", raw"""thx_h4(foo, 1, -5, R)"""),
    ("tq31", raw"""thx_h4(foo, a, 100, R)"""),
    ("tq32", raw"""thx_h4(foo, 1, b, R)"""),
    ("tq33", raw"""thx_h4(foo, 1.0, 100, R)"""),
    ("tq34", raw"""thx_h4(foo, _, 100, R)"""),
    ("tq35", raw"""thx_h4(foo, 1, _, R)"""),
    ("tq36", raw"""X is 10^20, thx_h4(foo, X, 100, R)"""),
    ("tq37", raw"""X is 10^11, thx_h4(foo, 1, X, R)"""),
    ("tq38", raw"""X is 2^31, thx_h4(foo, 1, X, R)"""),
    ("tq39", raw"""thx_h4(foo, 1, 100, x)"""),
    ("tq40", raw"""thx_h4(foo, 1, 100, 64), R = yes"""),
    ("tq41", raw"""thx_h4(foo, 1, 100, H), integer(H), R = int"""),
    ("tq42", raw"""thx_h4(foo, -2, 0, R)"""),
    ("vh01", raw"""variant_hash(foo, R)"""),
    ("vh02", raw"""variant_hash(f(a,b), R)"""),
    ("vh03", raw"""thx_mk(40, L), variant_hash(L, R)"""),
    ("vh04", raw"""variant_hash("abc", R)"""),
    ("vh05", raw"""X is 1 rdiv 3, variant_hash(X, R)"""),
    ("vh06", raw"""X is 2^63, variant_hash(X, R)"""),
    ("vh07", raw"""variant_hash(f(X,Y,X), H1), variant_hash(f(A,B,A), H2), thx_same(H1, H2, R)"""),
    ("vh08", raw"""variant_hash(f(X,Y), H1), variant_hash(f(X,X), H2), thx_same(H1, H2, R)"""),
    ("vh09", raw"""variant_hash(f(X,Y), H1), variant_hash(f(Y,X), H2), thx_same(H1, H2, R)"""),
    ("vh10", raw"""variant_hash(1, H1), variant_hash(1.0, H2), thx_same(H1, H2, R)"""),
    ("vh11", raw"""variant_hash([], H1), variant_hash('[]', H2), thx_same(H1, H2, R)"""),
    ("vh12", raw"""variant_hash(f(_), R)"""),
    ("vh13", raw"""variant_hash(_, R)"""),
    ("vh14", raw"""variant_hash(f(X,a,X), R)"""),
    ("vh15", raw"""put_attr(X, m, 1), variant_hash(f(X,Y), H1), variant_hash(f(A,B), H2), thx_same(H1, H2, R)"""),
    ("vh16", raw"""variant_hash(f(a), 1), R = yes"""),
    ("vh17", raw"""variant_hash(f(a), x), R = yes"""),
    ("vh18", raw"""variant_hash(foo, H), integer(H), R = int"""),
    ("vh19", raw"""thx_ca([233], A), variant_hash(A, R)"""),
    ("vh20", raw"""thx_cs([26085, 26412], S), variant_hash(S, R)"""),
    ("vh21", raw"""thx_ca([26085, 26412], A), variant_hash(A, R)"""),
    ("vh22", raw"""variant_hash(f(a,b), H1), variant_hash(f(a,b), H2), thx_same(H1, H2, R)"""),
    ("vh23", raw"""variant_hash(f(a,b), H1), variant_hash(f(b,a), H2), thx_same(H1, H2, R)"""),
    ("vh24", raw"""variant_hash(f(g(a)), H1), variant_hash(f(g(b)), H2), thx_same(H1, H2, R)"""),
    ("vs01", raw"""variant_sha1(foo, R)"""),
    ("vs02", raw"""variant_sha1("abc", R)"""),
    ("vs03", raw"""thx_ca([26085, 26412], A), variant_sha1(A, R)"""),
    ("vs04", raw"""thx_cs([26085, 26412], S), variant_sha1(S, R)"""),
    ("vs05", raw"""variant_sha1(f(a,b), R)"""),
    ("vs06", raw"""X is 2^63, variant_sha1(X, R)"""),
    ("vs07", raw"""X is 1 rdiv 3, variant_sha1(X, R)"""),
    ("vs08", raw"""thx_mk(40, L), variant_sha1(L, R)"""),
    ("vs09", raw"""variant_sha1([], R)"""),
    ("vs10", raw"""variant_sha1('[]', R)"""),
    ("vs11", raw"""variant_sha1(1, R)"""),
    ("vs12", raw"""variant_sha1(1.5, R)"""),
    ("vs13", raw"""variant_sha1(f(X,Y,X), H1), variant_sha1(f(A,B,A), H2), thx_same(H1, H2, R)"""),
    ("vs14", raw"""variant_sha1(f(X,Y), H1), variant_sha1(f(X,X), H2), thx_same(H1, H2, R)"""),
    ("vs15", raw"""variant_sha1(f(X,a,X), R)"""),
    ("vs16", raw"""put_attr(X, m, 1), variant_sha1(X, R)"""),
    ("vs17", raw"""put_attr(X, m, 1), variant_sha1(f(a, X), R)"""),
    ("vs18", raw"""variant_sha1(f(a), H), atom(H), atom_length(H, R)"""),
    ("vs19", raw"""X is 2^56-1, variant_sha1(X, R)"""),
    ("vs20", raw"""X is -(2^56)-1, variant_sha1(X, R)"""),
    ("vs21", raw"""variant_sha1("", R)"""),
    ("vs22", raw"""variant_sha1('', R)"""),
    ("vs23", raw"""compound_name_arguments(T, f, []), variant_sha1(T, R)"""),
    ("vs24", raw"""thx_ca([233], A), variant_sha1(A, R)"""),
    ("vs25", raw"""variant_sha1("abcdefg", R)"""),
    ("vs26", raw"""thx_cs([26085], S), variant_sha1(S, R)""")
]

# a cyclic argument: swipl answers; the kernel answers cy05 and refuses the others by name — a separate database each
const _TH_CYCLIC = [
    ("cy01", raw"""X = f(X), thx_h(X, R)"""),
    ("cy02", raw"""X = [a|X], variant_hash(X, R)"""),
    ("cy03", raw"""X = [a|X], variant_sha1(X, R)"""),
    ("cy04", raw"""X = f(X), thx_h4(X, 3, 100000, R)"""),
    ("cy05", raw"""X = [a|X], thx_h4(X, 0, 100, R)"""),
    ("cy06", raw"""X = [a|X], Y = [a,a|Y], variant_hash(X, H1), variant_hash(Y, H2), thx_same(H1, H2, R)""")
]

# the driver's whole output, one line per case after `ok`: the PINNED swipl at 18168e62, two runs, byte-identical
const _TH_PINNED = [
    "ok",
    "t_th01 c[116,95,116,104,48,49]/1(i4132911164)",
    "t_th02 c[116,95,116,104,48,50]/1(i45085902)",
    "t_th03 c[116,95,116,104,48,51]/1(i17268846)",
    "t_th04 c[116,95,116,104,48,52]/1(i1269818963)",
    "t_th05 c[116,95,116,104,48,53]/1(i1269818963)",
    "t_th06 c[116,95,116,104,48,54]/1(i1745793758)",
    "t_th07 c[116,95,116,104,48,55]/1(i2415530588)",
    "t_th08 c[116,95,116,104,48,56]/1(i754250009)",
    "t_th09 c[116,95,116,104,48,57]/1(i3261798158)",
    "t_th10 c[116,95,116,104,49,48]/1(i2513478484)",
    "t_th11 c[116,95,116,104,49,49]/1(i1220239556)",
    "t_th12 c[116,95,116,104,49,50]/1(i3768511644)",
    "t_th13 c[116,95,116,104,49,51]/1(i754250009)",
    "t_th14 c[116,95,116,104,49,52]/1(i3913372751)",
    "t_th15 c[116,95,116,104,49,53]/1(i4113862117)",
    "t_th16 c[116,95,116,104,49,54]/1(i2329647695)",
    "t_th17 c[116,95,116,104,49,55]/1(i1361206487)",
    "t_th18 c[116,95,116,104,49,56]/1(i1586251565)",
    "t_th19 c[116,95,116,104,49,57]/1(i2106756840)",
    "t_th20 c[116,95,116,104,50,48]/1(i1859486738)",
    "t_th21 c[116,95,116,104,50,49]/1(i1375828863)",
    "t_th22 c[116,95,116,104,50,50]/1(i3386870198)",
    "t_th23 c[116,95,116,104,50,51]/1(i843341906)",
    "t_th24 c[116,95,116,104,50,52]/1(i3810345500)",
    "t_th25 c[116,95,116,104,50,53]/1(i2548459879)",
    "t_th26 c[116,95,116,104,50,54]/1(i2997513916)",
    "t_th27 c[116,95,116,104,50,55]/1(i3642536006)",
    "t_th28 c[116,95,116,104,50,56]/1(i1747181055)",
    "t_th29 c[116,95,116,104,50,57]/1(i1955271470)",
    "t_th31 c[116,95,116,104,51,49]/1(i591282682)",
    "t_th32 c[116,95,116,104,51,50]/1(i3162476597)",
    "t_th33 c[116,95,116,104,51,51]/1(i3640712072)",
    "t_th34 c[116,95,116,104,51,52]/1(i4144289781)",
    "t_th35 c[116,95,116,104,51,53]/1(i3657889658)",
    "t_th36 c[116,95,116,104,51,54]/1(a[115,97,109,101])",
    "t_th37 c[116,95,116,104,51,55]/1(a[100,105,102,102])",
    "t_th38 c[116,95,116,104,51,56]/1(a[115,97,109,101])",
    "t_th39 c[116,95,116,104,51,57]/1(a[100,105,102,102])",
    "t_th40 c[116,95,116,104,52,48]/1(a[115,97,109,101])",
    "t_th41 c[116,95,116,104,52,49]/1(i3785393104)",
    "t_th42 c[116,95,116,104,52,50]/1(i691642051)",
    "t_th43 c[116,95,116,104,52,51]/1(i2344975763)",
    "t_th44 c[116,95,116,104,52,52]/1(a[117,110,98,111,117,110,100])",
    "t_th45 c[116,95,116,104,52,53]/1(a[117,110,98,111,117,110,100])",
    "t_th46 c[116,95,116,104,52,54]/1(a[117,110,98,111,117,110,100])",
    "t_th47 c[116,95,116,104,52,55]/1(a[117,110,98,111,117,110,100])",
    "t_th48 c[116,95,116,104,52,56]/1(a[117,110,98,111,117,110,100])",
    "t_th49",
    "t_th50 c[116,95,116,104,53,48]/1(a[105,110,116])",
    "t_tq01 c[116,95,116,113,48,49]/1(i64)",
    "t_tq02 c[116,95,116,113,48,50]/1(i910)",
    "t_tq03 c[116,95,116,113,48,51]/1(i159)",
    "t_tq04 c[116,95,116,113,48,52]/1(i604359)",
    "t_tq05 c[116,95,116,113,48,53]/1(i674159)",
    "t_tq06 c[116,95,116,113,48,54]/1(i132426)",
    "t_tq07 c[116,95,116,113,48,55]/1(i906817)",
    "t_tq08 c[116,95,116,113,48,56]/1(a[117,110,98,111,117,110,100])",
    "t_tq09 c[116,95,116,113,48,57]/1(i6)",
    "t_tq10 c[116,95,116,113,49,48]/1(a[117,110,98,111,117,110,100])",
    "t_tq11 c[116,95,116,113,49,49]/1(i6)",
    "t_tq12 c[116,95,116,113,49,50]/1(i644)",
    "t_tq13 c[116,95,116,113,49,51]/1(i556)",
    "t_tq14 c[116,95,116,113,49,52]/1(i1985427517)",
    "t_tq15 c[116,95,116,113,49,53]/1(i107381)",
    "t_tq16 c[116,95,116,113,49,54]/1(i1790)",
    "t_tq17 c[116,95,116,113,49,55]/1(i0)",
    "t_tq18 c[116,95,116,113,49,56]/1(i604359)",
    "t_tq19 c[116,95,116,113,49,57]/1(i674159)",
    "t_tq20 c[116,95,116,113,50,48]/1(i0)",
    "t_tq21 c[116,95,116,113,50,49]/1(i486738)",
    "t_tq22 c[116,95,116,113,50,50]/1(i870198)",
    "t_tq23 c[116,95,116,113,50,51]/1(i818963)",
    "t_tq24 c[116,95,116,113,50,52]/1(a[100,105,102,102])",
    "t_tq25 c[116,95,116,113,50,53]/1(i479656)",
    "t_tq26 c[116,95,116,113,50,54]/1(i931285)",
    "t_tq27 c[116,95,116,113,50,55]/1(a[117,110,98,111,117,110,100])",
    "t_tq28 c[116,95,116,113,50,56]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[110,111,116,95,108,101,115,115,95,116,104,97,110,95,122,101,114,111],i-2)))",
    "t_tq29 c[116,95,116,113,50,57]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[110,111,116,95,108,101,115,115,95,116,104,97,110,95,111,110,101],i1)))",
    "t_tq30 c[116,95,116,113,51,48]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[110,111,116,95,108,101,115,115,95,116,104,97,110,95,111,110,101],i1)))",
    "t_tq31 c[116,95,116,113,51,49]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],a[97])))",
    "t_tq32 c[116,95,116,113,51,50]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],a[98])))",
    "t_tq33 c[116,95,116,113,51,51]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],f1.0)))",
    "t_tq34 c[116,95,116,113,51,52]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_tq35 c[116,95,116,113,51,53]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_tq36 c[116,95,116,113,51,54]/1(c[114,97,105,115,101,100]/1(c[114,101,112,114,101,115,101,110,116,97,116,105,111,110,95,101,114,114,111,114]/1(a[105,110,116,54,52,95,116])))",
    "t_tq37 c[116,95,116,113,51,55]/1(c[114,97,105,115,101,100]/1(c[114,101,112,114,101,115,101,110,116,97,116,105,111,110,95,101,114,114,111,114]/1(a[105,110,116])))",
    "t_tq38 c[116,95,116,113,51,56]/1(c[114,97,105,115,101,100]/1(c[114,101,112,114,101,115,101,110,116,97,116,105,111,110,95,101,114,114,111,114]/1(a[105,110,116])))",
    "t_tq39",
    "t_tq40 c[116,95,116,113,52,48]/1(a[121,101,115])",
    "t_tq41 c[116,95,116,113,52,49]/1(a[105,110,116])",
    "t_tq42 c[116,95,116,113,52,50]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[110,111,116,95,108,101,115,115,95,116,104,97,110,95,122,101,114,111],i-2)))",
    "t_vh01 c[116,95,118,104,48,49]/1(i2798916)",
    "t_vh02 c[116,95,118,104,48,50]/1(i10148401)",
    "t_vh03 c[116,95,118,104,48,51]/1(i8711832)",
    "t_vh04 c[116,95,118,104,48,52]/1(i13573511)",
    "t_vh05 c[116,95,118,104,48,53]/1(i1877133)",
    "t_vh06 c[116,95,118,104,48,54]/1(i4944308)",
    "t_vh07 c[116,95,118,104,48,55]/1(a[115,97,109,101])",
    "t_vh08 c[116,95,118,104,48,56]/1(a[100,105,102,102])",
    "t_vh09 c[116,95,118,104,48,57]/1(a[115,97,109,101])",
    "t_vh10 c[116,95,118,104,49,48]/1(a[100,105,102,102])",
    "t_vh11 c[116,95,118,104,49,49]/1(a[100,105,102,102])",
    "t_vh12 c[116,95,118,104,49,50]/1(i5177139)",
    "t_vh13 c[116,95,118,104,49,51]/1(i435891)",
    "t_vh14 c[116,95,118,104,49,52]/1(i14134409)",
    "t_vh15 c[116,95,118,104,49,53]/1(a[115,97,109,101])",
    "t_vh16",
    "t_vh17",
    "t_vh18 c[116,95,118,104,49,56]/1(a[105,110,116])",
    "t_vh19 c[116,95,118,104,49,57]/1(i11267097)",
    "t_vh20 c[116,95,118,104,50,48]/1(i16101425)",
    "t_vh21 c[116,95,118,104,50,49]/1(i5832543)",
    "t_vh22 c[116,95,118,104,50,50]/1(a[115,97,109,101])",
    "t_vh23 c[116,95,118,104,50,51]/1(a[100,105,102,102])",
    "t_vh24 c[116,95,118,104,50,52]/1(a[100,105,102,102])",
    "t_vs01 c[116,95,118,115,48,49]/1(a[99,101,101,55,49,101,98,99,49,100,48,50,51,97,102,49,51,49,101,51,52,54,49,98,51,50,50,101,52,50,53,49,98,50,101,53,97,53,49,48])",
    "t_vs02 c[116,95,118,115,48,50]/1(a[56,49,101,56,98,101,102,54,50,56,49,53,57,54,98,56,99,54,101,51,49,51,98,102,97,54,100,98,98,101,54,52,54,102,55,100,101,51,57,54])",
    "t_vs03 c[116,95,118,115,48,51]/1(a[48,57,102,52,52,49,55,55,56,50,54,102,50,55,52,101,102,100,100,52,101,98,53,53,97,56,52,55,99,51,57,49,56,101,100,102,54,49,55,101])",
    "t_vs04 c[116,95,118,115,48,52]/1(a[48,50,49,55,97,99,56,56,100,99,101,48,56,53,99,51,49,49,98,100,97,53,53,54,56,57,101,51,98,97,100,98,53,53,101,56,101,52,54,100])",
    "t_vs05 c[116,95,118,115,48,53]/1(a[48,51,56,57,99,56,55,53,49,50,53,51,56,50,100,55,55,97,99,48,97,97,50,48,99,49,51,55,97,102,53,97,53,54,99,101,50,56,57,97])",
    "t_vs06 c[116,95,118,115,48,54]/1(a[48,98,98,100,102,53,102,101,100,56,97,98,102,57,53,57,54,100,98,50,48,49,99,49,55,53,54,97,102,48,56,100,55,52,98,98,99,51,100,56])",
    "t_vs07 c[116,95,118,115,48,55]/1(a[97,97,101,49,48,56,54,102,53,57,53,56,49,51,102,52,51,55,56,51,99,51,57,49,99,98,50,48,98,53,54,56,102,101,54,102,98,54,54,52])",
    "t_vs08 c[116,95,118,115,48,56]/1(a[102,52,98,51,55,48,53,99,49,51,53,57,100,53,56,98,50,55,57,52,48,57,98,97,57,50,51,54,51,100,54,99,98,50,53,56,49,52,97,100])",
    "t_vs09 c[116,95,118,115,48,57]/1(a[55,101,50,49,54,102,51,51,54,55,57,52,49,102,49,55,54,50,54,48,101,56,55,101,102,101,48,99,100,55,100,55,100,101,54,51,48,55,53,54])",
    "t_vs10 c[116,95,118,115,49,48]/1(a[57,101,55,53,100,99,55,98,48,53,53,99,49,51,100,53,102,55,49,97,49,102,56,52,55,50,100,54,53,99,100,101,48,102,53,50,51,51,98,100])",
    "t_vs11 c[116,95,118,115,49,49]/1(a[100,48,55,52,54,55,53,49,52,51,52,48,55,54,54,56,99,99,50,56,102,98,97,54,100,53,102,97,52,56,54,49,50,98,52,99,102,56,50,51])",
    "t_vs12 c[116,95,118,115,49,50]/1(a[48,98,55,50,50,100,100,98,98,98,51,102,48,56,55,53,102,57,53,98,52,48,49,100,50,55,100,54,54,49,56,98,100,101,54,101,54,53,99,52])",
    "t_vs13 c[116,95,118,115,49,51]/1(a[115,97,109,101])",
    "t_vs14 c[116,95,118,115,49,52]/1(a[100,105,102,102])",
    "t_vs15 c[116,95,118,115,49,53]/1(a[51,50,102,52,100,101,101,50,49,55,100,102,102,102,102,52,55,52,50,50,53,101,51,99,53,56,49,55,99,54,97,52,98,49,52,102,51,56,100,97])",
    "t_vs16 c[116,95,118,115,49,54]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_vs17 c[116,95,118,115,49,55]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[102,114,101,101,95,111,102,95,97,116,116,118,97,114],c[102]/2(a[97],V0))))",
    "t_vs18 c[116,95,118,115,49,56]/1(i40)",
    "t_vs19 c[116,95,118,115,49,57]/1(a[101,54,51,98,101,97,50,56,101,100,98,52,98,48,49,49,51,99,100,49,52,98,53,50,52,50,97,57,97,56,52,101,53,102,100,100,100,98,100,48])",
    "t_vs20 c[116,95,118,115,50,48]/1(a[98,97,100,56,97,99,57,49,98,50,56,52,51,101,99,99,102,99,100,55,101,100,48,99,49,102,57,48,57,99,100,49,48,100,101,98,99,52,56,48])",
    "t_vs21 c[116,95,118,115,50,49]/1(a[48,55,53,48,98,50,51,101,49,100,55,100,49,48,97,51,100,49,55,98,55,48,99,99,48,55,98,97,102,101,102,53,99,101,50,102,100,51,55,54])",
    "t_vs22 c[116,95,118,115,50,50]/1(a[55,52,50,99,51,57,54,99,56,98,49,97,51,101,97,102,102,49,50,98,56,56,52,49,102,102,99,53,54,54,48,55,102,55,54,49,98,50,102,57])",
    "t_vs23 c[116,95,118,115,50,51]/1(a[56,101,53,99,53,49,53,52,102,56,50,55,97,50,51,98,54,98,49,102,101,56,57,55,57,102,50,50,97,102,99,55,99,50,49,56,55,54,50,99])",
    "t_vs24 c[116,95,118,115,50,52]/1(a[53,97,54,53,50,53,52,52,48,55,97,53,51,99,101,52,49,50,101,49,50,100,51,102,55,56,98,98,101,98,99,53,48,99,52,101,53,53,101,51])",
    "t_vs25 c[116,95,118,115,50,53]/1(a[101,51,49,53,53,48,48,54,97,50,50,53,49,52,99,100,99,100,49,57,55,98,50,52,97,97,97,97,57,49,50,101,55,57,50,101,56,56,57,99])",
    "t_vs26 c[116,95,118,115,50,54]/1(a[102,98,50,56,50,98,98,49,51,53,56,52,56,52,102,56,100,56,54,101,50,51,56,48,101,57,57,99,100,97,48,55,98,53,51,100,53,57,98,102])"
]

const _TH_CY_PINNED = [
    "ok",
    "t_cy01 c[116,95,99,121,48,49]/1(i570532129)",
    "t_cy02 c[116,95,99,121,48,50]/1(i12531363)",
    "t_cy03 c[116,95,99,121,48,51]/1(a[101,97,51,56,48,97,55,50,48,48,98,100,48,57,48,55,55,53,49,50,99,49,49,51,48,100,51,48,52,57,53,48,99,55,49,99,53,102,98,52])",
    "t_cy04 c[116,95,99,121,48,52]/1(i56512)",
    "t_cy05 c[116,95,99,121,48,53]/1(i26)",
    "t_cy06 c[116,95,99,121,48,54]/1(a[115,97,109,101])"
]

# KNOWN DIFFERENCE rows: the id of the driver line -> the kernel's exact line (swipl's is the pin above): the cyclic argument is
# refused by name (src/pl-termhash.jl `_term_hash_arg`, `_variant_arg`; docs/r2_owners.tsv), where swipl answers (pins above)
const _TH_CY_KNOWN = Dict{String, String}(
    "t_cy01" => "t_cy01 notported",
    "t_cy02" => "t_cy02 notported",
    "t_cy03" => "t_cy03 notported",
    "t_cy04" => "t_cy04 notported",
    "t_cy06" => "t_cy06 notported"
)

function _th_file(cs)::Tuple{String, Vector{String}}
    names = ["t_$(id)" for (id, _) in cs]
    text =
        _TH_PROGRAM * join([
            "t_$(id)(R) :- catch(($g), error(SsuE, _), R = raised(SsuE)).\n" for (id, g) in cs
        ])
    f = joinpath(mktempdir(), "termhash.pl")
    write(f, text)
    return f, names
end

"The kernel's lines for `names` after consulting `path`, as the driver writes swipl's. A `NotPortedError` ends the run with
`<name> notported` (the query stays open: the database is thrown away)."
function _th_kernel(path::String, names::Vector{String})::Vector{String}
    gd = LK.PL_global_data{_TH}()
    ld = LK.PL_local_data{_TH}(gd)
    st, ball = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * _th_enc(ball::_TH)]
    for name in names
        proc = LK.isCurrentProcedure(sym_key(_ths(name)), 1, LK.MODULE_user(gd))
        if proc === nothing || !LK.isDefinedProcedure(gd, proc)
            push!(out, "$name undefined")
            continue
        end
        sols = String[]
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 1)
        LK.putSlotValue!(ld, a + 1, mk_var(_TH, LK.fresh_var_keys!(1)), LK.PutVarMap())
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
        )
        n = 0
        notported = false
        while (n += 1) <= 50
            rc = try
                LK.PL_next_solution(gd, ld, qid)
            catch e
                e isa LK.NotPortedError || rethrow()
                notported = true
                break
            end
            if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
                push!(
                    sols,
                    _th_enc(mk_expr(_TH, _TH[_ths(name), lk_answers(ld, (a:a)...)...]))
                )
                rc == LK.PL_S_LAST && break
            elseif rc == LK.PL_S_EXCEPTION
                push!(sols, "exception")
                break
            else
                break
            end
        end
        if notported
            push!(out, "$name notported")
            return out
        end
        LK.PL_close_query(ld, qid)
        LK.PL_close_foreign_frame(ld, fid)
        push!(out, "$name" * join(" " .* sols))
    end
    return out
end

# the answer of a pinned line: its integer, or the atom's text
_th_int(l::String) = (m = match(r"\(i(\d+)\)$", l); m === nothing ? nothing : parse(Int, m[1]))
function _th_atom(l::String)
    m = match(r"\(a\[([\d,]*)\]\)$", l)
    return m === nothing ? nothing : String(Char.(parse.(Int, split(m[1], ','))))
end
_th_pin(id::String) = only(filter(l -> startswith(l, "t_$id ") || l == "t_$id", _TH_PINNED))

@testset "term_hash/2, term_hash/4, variant_hash/2, variant_sha1/2 as swipl's (th, tq, vh, vs)" begin
    f, names = _th_file(_TH_CASES)
    kl = _th_kernel(f, names)
    @test length(kl) == length(_TH_PINNED)
    for (k, p) in zip(kl, _TH_PINNED)
        k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
        @test k == p
    end
end

@testset "a CYCLIC argument: row cy05 is swipl's; the others are refused by name (known differences)" begin
    for (i, (id, g)) in enumerate(_TH_CYCLIC)
        f, names = _th_file([(id, g)])
        kl = _th_kernel(f, names)
        pin = _TH_CY_PINNED[i + 1]
        @test startswith(pin, "t_$id ")
        @test length(kl) == 2 && kl[1] == "ok"
        @test kl[2] == get(_TH_CY_KNOWN, "t_$id", pin)
    end
end

@testset "KNOWN DIFFERENCES: the kernel's pinned answer is not swipl's" begin
    @test length(_TH_CY_PINNED) == length(_TH_CYCLIC) + 1 && _TH_CY_PINNED[1] == "ok"
    @test sort(collect(keys(_TH_CY_KNOWN))) == ["t_cy01", "t_cy02", "t_cy03", "t_cy04", "t_cy06"]
    for (id, line) in _TH_CY_KNOWN
        pin = filter(l -> first(split(l, ' ')) == id, _TH_CY_PINNED)
        @test length(pin) == 1
        @test line != only(pin)
    end
end

@testset "the term_hash rows are not vacuous" begin
    @test _TH_PINNED[1] == "ok"
    @test length(_TH_PINNED) == length(_TH_CASES) + 1
    ids = [id for (id, _) in _TH_CASES]
    @test length(ids) == length(unique(ids))
    # term_hash/2 of a ground term is a 32-bit integer; the known value of `foo` is the one the hand model of pl-termhash.c gave
    ints = Dict(id => _th_int(_th_pin(id)) for id in ids)
    ground = [
        "th01", "th02", "th03", "th04", "th06", "th07", "th08", "th09", "th10", "th11", "th12", "th13", "th14",
        "th15", "th16", "th17", "th18", "th19", "th20", "th21", "th22", "th23", "th24", "th25", "th26", "th27",
        "th28", "th29", "th31", "th32", "th33", "th34", "th35", "th41", "th42", "th43"
    ]
    for id in ground
        @test ints[id] !== nothing && 0 <= ints[id] < 2^32
    end
    @test ints["th01"] == 4132911164
    @test length(unique(ints[id] for id in ground[1:12])) == 11                # told apart: 12 terms, th08 == th13
    @test ints["th08"] == ints["th13"] && ints["th04"] == ints["th05"]
    # a non-ground term leaves the key unbound (the call succeeds); a bound wrong key fails
    for id in ("th44", "th45", "th46", "th47", "th48")
        @test _th_atom(_th_pin(id)) == "unbound"
    end
    @test _th_pin("th49") == "t_th49"
    # equal and unequal pairs: `==` terms hash alike; swipl hashes `0` and `0.0` alike (th08, th13: the double's bytes are
    # 0) and `1` and `1.0` apart; `[]` and `'[]'` alike (their text is `[]`)
    @test _th_atom(_th_pin("th36")) == "same" && _th_atom(_th_pin("th37")) == "diff"
    @test _th_atom(_th_pin("th38")) == "same" && _th_atom(_th_pin("th39")) == "diff"
    # term_hash/4: the answer is below the range; a range of 1 answers 0 (tq17, tq20)
    ranges = Dict(
        "tq01" => 100, "tq02" => 1000, "tq03" => 1000, "tq04" => 10^6, "tq05" => 10^6, "tq06" => 10^6,
        "tq07" => 10^6, "tq09" => 10, "tq11" => 1000, "tq12" => 1000, "tq13" => 1000, "tq14" => 2147483647,
        "tq15" => 10^6, "tq16" => 10^6, "tq17" => 1, "tq18" => 10^6, "tq19" => 10^6, "tq20" => 1,
        "tq21" => 10^6, "tq22" => 10^6, "tq23" => 10^6, "tq25" => 10^6, "tq26" => 10^6
    )
    for (id, r) in ranges
        @test ints[id] !== nothing && 0 <= ints[id] < r
    end
    @test ints["tq04"] != ints["tq05"] != ints["tq06"]                         # the depth is read
    @test _th_atom(_th_pin("tq10")) == "unbound" && _th_atom(_th_pin("tq08")) == "unbound"
    @test _th_atom(_th_pin("tq24")) == "diff"                                  # depth 1 and depth 2 of f(a)
    for id in ("tq28", "tq29", "tq30", "tq31", "tq32", "tq33", "tq34", "tq35", "tq36", "tq37", "tq38", "tq42")
        @test occursin("c[114,97,105,115,101,100]/1(", _th_pin(id))                       # every error row raises
    end
    @test occursin(_th_codes("not_less_than_zero"), _th_pin("tq28"))
    @test occursin(_th_codes("not_less_than_one"), _th_pin("tq29")) && occursin(_th_codes("not_less_than_one"), _th_pin("tq30"))
    @test occursin(_th_codes("instantiation_error"), _th_pin("tq34")) && occursin(_th_codes("instantiation_error"), _th_pin("tq35"))
    @test occursin(_th_codes("representation_error"), _th_pin("tq36")) && occursin(_th_codes("int64_t"), _th_pin("tq36"))
    @test _th_pin("tq39") == "t_tq39"                                          # a bound wrong answer fails
    @test _th_atom(_th_pin("tq40")) == "yes" && _th_atom(_th_pin("tq41")) == "int"
    # variant_hash/2: 24 bits; =@= terms agree
    for id in ("vh01", "vh02", "vh03", "vh04", "vh05", "vh06", "vh12", "vh13", "vh14", "vh19", "vh20", "vh21")
        @test ints[id] !== nothing && 0 <= ints[id] < 2^24
    end
    @test _th_atom(_th_pin("vh07")) == "same" && _th_atom(_th_pin("vh08")) == "diff"
    @test _th_atom(_th_pin("vh10")) == "diff" && _th_atom(_th_pin("vh11")) == "diff"
    @test _th_atom(_th_pin("vh15")) == "same" && _th_atom(_th_pin("vh23")) == "diff"
    # variant_sha1/2: 40 hex digits; the variant relation
    for id in ("vs01", "vs02", "vs03", "vs04", "vs05", "vs06", "vs07", "vs08", "vs09", "vs10", "vs11", "vs12", "vs15",
               "vs19", "vs20", "vs21", "vs22", "vs23", "vs24", "vs25", "vs26")
        a = _th_atom(_th_pin(id))
        @test a !== nothing && length(a) == 40 && all(c -> c in "0123456789abcdef", a)
    end
    @test length(unique(_th_atom(_th_pin(id)) for id in ("vs09", "vs10", "vs21", "vs22"))) == 4   # [] vs '[]', "" vs ''
    @test _th_atom(_th_pin("vs13")) == "same" && _th_atom(_th_pin("vs14")) == "diff"
    @test occursin(_th_codes("free_of_attvar"), _th_pin("vs17"))               # an attributed variable in the term
    @test occursin(_th_codes("instantiation_error"), _th_pin("vs16"))          # a bare one: type_error on an unbound term
    # the cyclic pins are answers: integers, a digest, `same`
    @test all(i -> _th_int(_TH_CY_PINNED[i]) !== nothing, (2, 3, 5, 6))
    @test length(_th_atom(_TH_CY_PINNED[4])) == 40
    @test _th_atom(_TH_CY_PINNED[7]) == "same"
end

@testset "the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    @test length(_TH_PINNED) == length(_TH_CASES) + 1
    if swipl === nothing
        @info "TERM_HASH LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        f, names = _th_file(_TH_CASES)
        @test _th_swipl_lines(f, names) == _TH_PINNED
        f, names = _th_file(_TH_CYCLIC)
        @test _th_swipl_lines(f, names) == _TH_CY_PINNED
    end
end
