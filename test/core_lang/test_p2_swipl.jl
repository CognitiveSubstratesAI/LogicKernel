# ORIGINAL: a LIVE differential of P2's pl-prims.c text predicates — atomic_list_concat/2,3, atomics_to_string/2,3 and
# sub_atom/5 (pl-prims.c 4903-5092, pl_sub_atom 5487) — against swipl at the pin: rows p01-p70, ids prefixed `p`:
#   * A PROGRAM consulted by the kernel's loader and cases `t_<id>(R)` run in order in one database, each wrapped in
#     `catch(Goal, error(E, _), R = raised(E))`; the driver is test_style_check_swipl.jl's (`enc`oded answers).
#   * Every answer line is swipl's, PINNED (swipl 10.1.19, two runs byte-identical, evidence/P2/gen_rows.py --fill);
#     with `swipl` on PATH the live answers are compared with the pins too.
#   * p01-p39 atomic_list_concat/2,3 (join, the (-,+,+) split, the errors); p40-p46 atomics_to_string/2,3; p50-p70 sub_atom/5.
#   * UNVERIFIED on the kernel: gate decides (nothing was compiled when these rows were written): every kernel answer.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — the built-in rides the term layer through PL_unify_integer and PL_get_integer only
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _P2 = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_p2s(x) = lk_sym(_P2, Symbol(x))


_p2_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _p2_enc(t::_P2, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _p2_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _p2_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _p2_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_p2_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

# the swipl side: test/core_lang/test_ssu_swipl.jl's driver (consult, then every answer of each t_<id>/1, `enc`oded)
const _P2_DRIVER = raw"""
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
function _p2_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _P2_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(pipeline(`swipl -q $f`; stdin=devnull, stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end



# the program: helpers that build what a row needs without a library (a counted list; a wide-character atom)
const _P2_PROGRAM = raw"""
p2_nl(0, []) :- !.
p2_nl(N, [N|T]) :- N1 is N-1, p2_nl(N1, T).
p2_as(0, []) :- !.
p2_as(N, [a|T]) :- N1 is N-1, p2_as(N1, T).
p2_open([], _) :- !.
p2_open([X|Xs], [X|Ys]) :- p2_open(Xs, Ys).
p2_wide(A) :- atom_codes(A, [945, 98, 233]).
p2_ty(X, T) :- ( atom(X) -> T = atom ; string(X) -> T = string ; T = other ).
"""

const _P2_CASES = [
    ("p01", raw"atomic_list_concat([a,b,c], '-', R)"),
    ("p02", raw"atomic_list_concat([a,1,2.5,x], ',', R)"),
    ("p03", raw"atomic_list_concat([], '-', R)"),
    ("p04", raw"atomic_list_concat([a], '-', R)"),
    ("p05", raw"atomic_list_concat([a,b], '', R)"),
    ("p06", raw"atomic_list_concat(L, '-', 'a-b-c'), R = L"),
    ("p07", raw"atomic_list_concat(L, ',', 'a,,b'), R = L"),
    ("p08", raw"atomic_list_concat(L, '--', 'x--y--'), R = L"),
    ("p09", raw"atomic_list_concat(L, '-', abc), R = L"),
    ("p10", raw"atomic_list_concat(L, '-', ''), R = L"),
    ("p11", raw"atomic_list_concat([a,X], '-', 'a-b'), R = X"),
    ("p12", raw"atomic_list_concat([a,X], '-', 'a-b-c'), R = X"),
    ("p13", raw"atomic_list_concat(L, '', abc), R = L"),
    ("p14", raw"atomic_list_concat([a|_], '-', R)"),
    ("p15", raw"atomic_list_concat([a,f(x)], '-', R)"),
    ("p16", raw"atomic_list_concat([a,b], f(x), R)"),
    ("p17", raw"atomic_list_concat(foo, '-', R)"),
    ("p18", raw"atomic_list_concat([a,b], _, R)"),
    ("p19", raw"atomic_list_concat([a,_], '-', R)"),
    ("p20", raw"atomic_list_concat([a,_], R)"),
    ("p21", raw"atomic_list_concat([a|_], R)"),
    ("p22", raw"atomic_list_concat([a,b], R)"),
    ("p23", raw"atomic_list_concat([a,1,2.5,x], R)"),
    ("p24", raw"atomic_list_concat(_, R)"),
    ("p25", raw"atomic_list_concat([a,b], ab), R = yes"),
    ("p26", raw"atomic_list_concat([a,b], abc), R = yes"),
    ("p27", raw"atomic_list_concat([a,b], '-', 'a-b'), R = yes"),
    ("p28", raw"atomic_list_concat([a,b], '-', 'a_b'), R = yes"),
    ("p29", raw"p2_wide(W), atom_codes(E, [233]), atomic_list_concat([E,W], '-', A), atom_codes(A, R)"),
    ("p30", raw"p2_wide(W), atom_codes(S, [45]), atomic_list_concat([a,W], S, A), atomic_list_concat(L, S, A), R = L-A"),
    ("p31", raw"atomic_list_concat(L, 'aa', 'aaaa'), R = L"),
    ("p32", raw"atomic_list_concat(L, 'aa', 'aaa'), R = L"),
    ("p33", raw"p2_as(100, Ns), p2_open(Ns, L), atomic_list_concat(Ns, '-', A0), atom_concat(A0, '-z', A), atomic_list_concat(L, '-', A), R = ok"),
    ("p34", raw"p2_nl(150, Ns), atomic_list_concat(Ns, '-', A), atom_length(A, R)"),
    ("p35", raw"atomic_list_concat([a|b], '-', R)"),
    ("p36", raw"atomic_list_concat([a,b], 1, R)"),
    ("p37", raw"string_concat(x, y, S), atomic_list_concat([S,z], R)"),
    ("p38", raw"atomic_list_concat(L, '-', 12), R = L"),
    ("p39", raw"atomic_list_concat(L, '-', f(x)), R = L"),
    ("p40", raw"atomics_to_string([a,b], R)"),
    ("p41", raw"atomics_to_string([a,1], '-', R)"),
    ("p42", raw"atomics_to_string(L, '-', 'a-b'), R = L"),
    ("p43", raw"atomics_to_string([a,X], '-', 'a-b'), R = X"),
    ("p44", raw"atomics_to_string([], R)"),
    ("p45", raw"atomic_list_concat([a,b], '-', A), p2_ty(A, R)"),
    ("p46", raw"atomics_to_string([a,b], '-', A), p2_ty(A, R)"),
    ("p47", raw"atomics_to_string([a|b], '-', R)"),
    ("p48", raw"p2_wide(W), atomics_to_string([W,a], '', A), string_codes(A, R)"),
    ("p49", raw"p2_as(99, Ns), p2_open(Ns, L), atomic_list_concat(Ns, '-', A0), atom_concat(A0, '-z', A), atomic_list_concat(L, '-', A), R = L"),
    ("p50", raw"findall(B-L-A-S, sub_atom(abc, B, L, A, S), R)"),
    ("p51", raw"sub_atom(hello, 1, 3, A, S), R = A-S"),
    ("p52", raw"sub_atom(hello, B, 2, 0, S), R = B-S"),
    ("p53", raw"findall(B-L-A, sub_atom(hello, B, L, A, l), R)"),
    ("p54", raw"findall(B, sub_atom(hello, B, _, 0, o), R)"),
    ("p55", raw"sub_atom(hello, 0, _, _, he), R = yes"),
    ("p56", raw"sub_atom(hello, 0, _, _, el), R = yes"),
    ("p57", raw"sub_atom(_, 1, 1, _, a)"),
    ("p58", raw"sub_atom(f(x), _, _, _, _)"),
    ("p59", raw"sub_atom(abc, a, _, _, _)"),
    ("p60", raw"sub_atom(abc, -1, _, _, _), R = yes"),
    ("p61", raw"sub_atom(abc, _, _, _, f(x))"),
    ("p62", raw"sub_atom(123, 0, 2, A, S), R = A-S"),
    ("p63", raw"string_concat(a, bc, S0), sub_atom(S0, 1, 1, _, S), p2_ty(S, R)"),
    ("p64", raw"p2_wide(W), sub_atom(W, 1, 2, 0, S), atom_codes(S, R)"),
    ("p65", raw"findall(B-A, sub_atom(abc, B, 0, A, _), R)"),
    ("p66", raw"findall(x, sub_atom(abc, 3, 0, 0, _), R)"),
    ("p67", raw"sub_atom(abc, 4, _, _, _), R = yes"),
    ("p68", raw"findall(B-A, sub_atom(aXa, B, 1, A, a), R)"),
    ("p69", raw"catch(assertz(sub_atom(a, b, c, d, e)), error(E, _), true), R = E"),
    ("p70", raw"catch(assertz(atomic_list_concat(a, b, c)), error(E, _), true), R = E"),
]

# the driver's whole output, one line per case after `ok`, filled by evidence/P2/gen_rows.py --fill from swipl 10.1.19
const _P2_PINNED = [
    "ok",
    "t_p01 c[116,95,112,48,49]/1(a[97,45,98,45,99])",
    "t_p02 c[116,95,112,48,50]/1(a[97,44,49,44,50,46,53,44,120])",
    "t_p03 c[116,95,112,48,51]/1(a[])",
    "t_p04 c[116,95,112,48,52]/1(a[97])",
    "t_p05 c[116,95,112,48,53]/1(a[97,98])",
    "t_p06 c[116,95,112,48,54]/1(c[91,124,93]/2(a[97],c[91,124,93]/2(a[98],c[91,124,93]/2(a[99],nil))))",
    "t_p07 c[116,95,112,48,55]/1(c[91,124,93]/2(a[97],c[91,124,93]/2(a[],c[91,124,93]/2(a[98],nil))))",
    "t_p08 c[116,95,112,48,56]/1(c[91,124,93]/2(a[120],c[91,124,93]/2(a[121],c[91,124,93]/2(a[],nil))))",
    "t_p09 c[116,95,112,48,57]/1(c[91,124,93]/2(a[97,98,99],nil))",
    "t_p10 c[116,95,112,49,48]/1(c[91,124,93]/2(a[],nil))",
    "t_p11 c[116,95,112,49,49]/1(a[98])",
    "t_p12",
    "t_p13 c[116,95,112,49,51]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[110,111,110,95,101,109,112,116,121,95,97,116,111,109],a[])))",
    "t_p14 c[116,95,112,49,52]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_p15 c[116,95,112,49,53]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[116,101,120,116],c[102]/1(a[120]))))",
    "t_p16 c[116,95,112,49,54]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[116,101,120,116],c[102]/1(a[120]))))",
    "t_p17 c[116,95,112,49,55]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[108,105,115,116],a[102,111,111])))",
    "t_p18 c[116,95,112,49,56]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_p19 c[116,95,112,49,57]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_p20 c[116,95,112,50,48]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_p21 c[116,95,112,50,49]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_p22 c[116,95,112,50,50]/1(a[97,98])",
    "t_p23 c[116,95,112,50,51]/1(a[97,49,50,46,53,120])",
    "t_p24 c[116,95,112,50,52]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_p25 c[116,95,112,50,53]/1(a[121,101,115])",
    "t_p26",
    "t_p27 c[116,95,112,50,55]/1(a[121,101,115])",
    "t_p28",
    "t_p29 c[116,95,112,50,57]/1(c[91,124,93]/2(i233,c[91,124,93]/2(i45,c[91,124,93]/2(i945,c[91,124,93]/2(i98,c[91,124,93]/2(i233,nil))))))",
    "t_p30 c[116,95,112,51,48]/1(c[45]/2(c[91,124,93]/2(a[97],c[91,124,93]/2(a[945,98,233],nil)),a[97,45,945,98,233]))",
    "t_p31 c[116,95,112,51,49]/1(c[91,124,93]/2(a[],c[91,124,93]/2(a[],c[91,124,93]/2(a[],nil))))",
    "t_p32 c[116,95,112,51,50]/1(c[91,124,93]/2(a[],c[91,124,93]/2(a[97],nil)))",
    "t_p33 c[116,95,112,51,51]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_p34 c[116,95,112,51,52]/1(i491)",
    "t_p35 c[116,95,112,51,53]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[108,105,115,116],a[98])))",
    "t_p36 c[116,95,112,51,54]/1(a[97,49,98])",
    "t_p37 c[116,95,112,51,55]/1(a[120,121,122])",
    "t_p38 c[116,95,112,51,56]/1(c[91,124,93]/2(a[49,50],nil))",
    "t_p39 c[116,95,112,51,57]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[115,116,114,105,110,103],c[102]/1(a[120]))))",
    "t_p40 c[116,95,112,52,48]/1(s[97,98])",
    "t_p41 c[116,95,112,52,49]/1(s[97,45,49])",
    "t_p42 c[116,95,112,52,50]/1(c[91,124,93]/2(a[97],c[91,124,93]/2(a[98],nil)))",
    "t_p43 c[116,95,112,52,51]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_p44 c[116,95,112,52,52]/1(s[])",
    "t_p45 c[116,95,112,52,53]/1(a[97,116,111,109])",
    "t_p46 c[116,95,112,52,54]/1(a[115,116,114,105,110,103])",
    "t_p47 c[116,95,112,52,55]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[108,105,115,116],a[98])))",
    "t_p48 c[116,95,112,52,56]/1(c[91,124,93]/2(i945,c[91,124,93]/2(i98,c[91,124,93]/2(i233,c[91,124,93]/2(i97,nil)))))",
    "t_p49 c[116,95,112,52,57]/1(c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[97],c[91,124,93]/2(a[122],nil)))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))",
    "t_p50 c[116,95,112,53,48]/1(c[91,124,93]/2(c[45]/2(c[45]/2(c[45]/2(i0,i0),i3),a[]),c[91,124,93]/2(c[45]/2(c[45]/2(c[45]/2(i0,i1),i2),a[97]),c[91,124,93]/2(c[45]/2(c[45]/2(c[45]/2(i0,i2),i1),a[97,98]),c[91,124,93]/2(c[45]/2(c[45]/2(c[45]/2(i0,i3),i0),a[97,98,99]),c[91,124,93]/2(c[45]/2(c[45]/2(c[45]/2(i1,i0),i2),a[]),c[91,124,93]/2(c[45]/2(c[45]/2(c[45]/2(i1,i1),i1),a[98]),c[91,124,93]/2(c[45]/2(c[45]/2(c[45]/2(i1,i2),i0),a[98,99]),c[91,124,93]/2(c[45]/2(c[45]/2(c[45]/2(i2,i0),i1),a[]),c[91,124,93]/2(c[45]/2(c[45]/2(c[45]/2(i2,i1),i0),a[99]),c[91,124,93]/2(c[45]/2(c[45]/2(c[45]/2(i3,i0),i0),a[]),nil)))))))))))",
    "t_p51 c[116,95,112,53,49]/1(c[45]/2(i1,a[101,108,108]))",
    "t_p52 c[116,95,112,53,50]/1(c[45]/2(i3,a[108,111]))",
    "t_p53 c[116,95,112,53,51]/1(c[91,124,93]/2(c[45]/2(c[45]/2(i2,i1),i2),c[91,124,93]/2(c[45]/2(c[45]/2(i3,i1),i1),nil)))",
    "t_p54 c[116,95,112,53,52]/1(c[91,124,93]/2(i4,nil))",
    "t_p55 c[116,95,112,53,53]/1(a[121,101,115])",
    "t_p56",
    "t_p57 c[116,95,112,53,55]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_p58 c[116,95,112,53,56]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],c[102]/1(a[120]))))",
    "t_p59 c[116,95,112,53,57]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],a[97])))",
    "t_p60 c[116,95,112,54,48]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[110,111,116,95,108,101,115,115,95,116,104,97,110,95,122,101,114,111],i-1)))",
    "t_p61 c[116,95,112,54,49]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],c[102]/1(a[120]))))",
    "t_p62 c[116,95,112,54,50]/1(c[45]/2(i1,a[49,50]))",
    "t_p63 c[116,95,112,54,51]/1(a[97,116,111,109])",
    "t_p64 c[116,95,112,54,52]/1(c[91,124,93]/2(i98,c[91,124,93]/2(i233,nil)))",
    "t_p65 c[116,95,112,54,53]/1(c[91,124,93]/2(c[45]/2(i0,i3),c[91,124,93]/2(c[45]/2(i1,i2),c[91,124,93]/2(c[45]/2(i2,i1),c[91,124,93]/2(c[45]/2(i3,i0),nil)))))",
    "t_p66 c[116,95,112,54,54]/1(c[91,124,93]/2(a[120],nil))",
    "t_p67",
    "t_p68 c[116,95,112,54,56]/1(c[91,124,93]/2(c[45]/2(i0,i2),c[91,124,93]/2(c[45]/2(i2,i0),nil)))",
    "t_p69 c[116,95,112,54,57]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[109,111,100,105,102,121],a[115,116,97,116,105,99,95,112,114,111,99,101,100,117,114,101],c[47]/2(a[115,117,98,95,97,116,111,109],i5)))",
    "t_p70 c[116,95,112,55,48]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[109,111,100,105,102,121],a[115,116,97,116,105,99,95,112,114,111,99,101,100,117,114,101],c[47]/2(a[97,116,111,109,105,99,95,108,105,115,116,95,99,111,110,99,97,116],i3)))"
]

function _p2_file()::Tuple{String, Vector{String}}
    names = ["t_$(id)" for (id, _) in _P2_CASES]
    text =
        _P2_PROGRAM * join([
            "t_$(id)(R) :- catch(($g), error(SsuE, _), R = raised(SsuE)).\n" for
            (id, g) in _P2_CASES
        ])
    f = joinpath(mktempdir(), "p2_text.pl")
    write(f, text)
    return f, names
end

"The kernel's lines for `names` after consulting `path`, as the driver writes swipl's; the database, for the white-box tests."
function _p2_kernel(path::String, names::Vector{String})
    gd = LK.PL_global_data{_P2}()
    ld = LK.PL_local_data{_P2}(gd)
    st, ball, _ = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * _p2_enc(ball::_P2)]
    for name in names
        proc = LK.isCurrentProcedure(sym_key(_p2s(name)), 1, LK.MODULE_user(gd))
        if proc === nothing || !LK.isDefinedProcedure(gd, proc)
            push!(out, "$name undefined")
            continue
        end
        sols = String[]
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 1)
        LK.putSlotValue!(ld, a + 1, mk_var(_P2, LK.fresh_var_keys!(1)), LK.PutVarMap())
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
        )
        n = 0
        while (n += 1) <= 50
            rc = LK.PL_next_solution(gd, ld, qid)
            if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
                push!(
                    sols,
                    _p2_enc(mk_expr(_P2, _P2[_p2s(name), lk_answers(ld, (a:a)...)...]))
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


@testset "P2 text predicates as swipl's (p01-p70)" begin
    f, names = _p2_file()
    kl, _, _ = _p2_kernel(f, names)
    @test length(kl) == length(_P2_PINNED)
    for (k, p) in zip(kl, _P2_PINNED)
        k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
        @test k == p
    end
end

@testset "the P2 rows are not vacuous" begin
    # the program loaded; every case has a line; the answering rows answer, the failing rows have none, the raising rows raise
    @test _P2_PINNED[1] == "ok"
    @test length(_P2_PINNED) == length(_P2_CASES) + 1
    answered = count(l -> occursin(" c[", l) || occursin(" a[", l) || occursin(" i", l), _P2_PINNED)
    @test answered >= 40
    @test any(l -> !occursin(" ", l) && startswith(l, "t_p"), _P2_PINNED)           # a row without an answer: it failed
    @test count(l -> occursin("[114,97,105,115,101,100]", l), _P2_PINNED) >= 8   # the error rows
    for id in ("p01", "p06", "p22", "p40", "p50", "p64")
        @test any(l -> startswith(l, "t_$id "), _P2_PINNED)                        # an answer
    end
end

@testset "the P2 pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    @test length(_P2_PINNED) == length(_P2_CASES) + 1
    if swipl === nothing
        @info "P2 LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        f, names = _p2_file()
        @test _p2_swipl_lines(f, names) == _P2_PINNED
    end
end
