# ORIGINAL: a LIVE differential of SETARG's `setarg/3`, `nb_setarg/3` and `nb_linkarg/3` (pl-prims.c:2790-2923) against swipl at
# the pin — SETARG's rows test/core_lang/test_setarg_swipl.jl (sa01-sa83) against swipl 10.1.19:
#   * A PROGRAM consulted by the kernel's loader and cases `t_<id>(R)` run in order in one database, each wrapped in
#     `catch(Goal, error(SsuE, _), R = raised(SsuE))`; the driver is test_bootpred_swipl.jl's (`enc`oded answers).
#   * Every answer line is swipl's, PINNED (swipl 10.1.19-1-gcbf4e189, lk-channel evidence/SETARG/setarg_rows.out on the
#     SETARG branch); with `swipl` on PATH the live answers are compared with the pins too.
#   * The helpers are the program's own (`sa_mem/2` stands for member/2, `sa_same/3` for same_term/2): nothing of init.pl.
#   * UNVERIFIED on the kernel (nothing was compiled when these rows were written): every kernel answer; the gate decides.
#     The attributed-variable and cycle rows (sa68-sa77) are the first to read if the kernel differs.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — the built-in rides the term layer through PL_unify_integer and PL_get_integer only
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _SA = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_sas(x) = lk_sym(_SA, Symbol(x))


_sa_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _sa_enc(t::_SA, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _sa_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _sa_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _sa_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_sa_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

# the swipl side: test/core_lang/test_ssu_swipl.jl's driver (consult, then every answer of each t_<id>/1, `enc`oded)
const _SA_DRIVER = raw"""
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
function _sa_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _SA_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(pipeline(`swipl -q $f`; stdin=devnull, stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end





# the program: the helpers the rows call (no library is loaded)
const _SA_PROGRAM = raw"""
sa_same(A, B, R) :- ( same_term(A, B) -> R = same ; R = distinct ).
sa_mem(X, [X|_]).
sa_mem(X, [_|T]) :- sa_mem(X, T).
sa_inc(T) :- arg(1, T, V0), V is V0+1, nb_setarg(1, T, V).
sa_binc(T) :- arg(1, T, V0), V is V0+1, setarg(1, T, V).
"""

const _SA_CASES = [
    # sa01-sa14 setarg/3: assignment, undo on backtracking, a variable argument
    ("sa01", raw"T = f(a,b), setarg(1, T, x), R = T"),
    ("sa02", raw"T = f(a,b), setarg(2, T, x), R = T"),
    ("sa03", raw"T = f(a,b,c), ( setarg(2, T, x), fail ; true ), R = T"),
    ("sa04", raw"T = f(a), setarg(1, T, x), setarg(1, T, y), R = T"),
    ("sa05", raw"T = f(a), ( setarg(1, T, x), setarg(1, T, y), fail ; true ), R = T"),
    ("sa06", raw"T = f(a), setarg(1, T, x), ( setarg(1, T, y), fail ; true ), R = T"),
    ("sa07", raw"T = f(_), setarg(1, T, v), R = T"),
    ("sa08", raw"T = f(_), ( setarg(1, T, v), fail ; true ), R = T"),
    ("sa09", raw"T = f(X), setarg(1, T, a), R = X-T"),
    ("sa10", raw"T = f(X), ( setarg(1, T, a), fail ; true ), R = X-T"),
    ("sa11", raw"T = f(X), X = b, setarg(1, T, c), R = X-T"),
    ("sa12", raw"T = f(_), setarg(1, T, X), R = T-X"),
    ("sa13", raw"T = f(a), setarg(1, T, X), X = q, R = T-X"),
    ("sa14", raw"T = f(a), setarg(1, T, X), ( X = q, fail ; true ), R = T-X"),
    # sa15-sa38 the failures and the errors of the argument and of the term
    ("sa15", raw"T = f(a), ( setarg(0, T, x) -> R = yes ; R = no )"),
    ("sa16", raw"T = f(a), ( setarg(2, T, x) -> R = yes ; R = no )"),
    ("sa17", raw"setarg(-1, f(a), x), R = yes"),
    ("sa18", raw"setarg(_, f(a), x), R = yes"),
    ("sa19", raw"setarg(a, f(a), x), R = yes"),
    ("sa20", raw"setarg(1.0, f(a), x), R = yes"),
    ("sa21", raw"X is 1<<70, setarg(X, f(a), x), R = yes"),
    ("sa22", raw"X is -(1<<70), setarg(X, f(a), x), R = yes"),
    ("sa23", raw"setarg(1, a, x), R = yes"),
    ("sa24", raw"setarg(1, _, x), R = yes"),
    ("sa25", raw"setarg(1, 3, x), R = yes"),
    ("sa26", raw"string_to_atom(S, abc), setarg(1, S, x), R = yes"),
    ("sa27", raw"setarg(1, [], x), R = yes"),
    ("sa28", raw"( nb_setarg(0, f(a), x) -> R = yes ; R = no )"),
    ("sa29", raw"( nb_setarg(3, f(a), x) -> R = yes ; R = no )"),
    ("sa30", raw"nb_setarg(a, f(a), x), R = yes"),
    ("sa31", raw"nb_setarg(-1, f(a), x), R = yes"),
    ("sa32", raw"nb_setarg(1, a, x), R = yes"),
    ("sa33", raw"nb_setarg(1, _, x), R = yes"),
    ("sa34", raw"( nb_linkarg(0, f(a), x) -> R = yes ; R = no )"),
    ("sa35", raw"( nb_linkarg(2, f(a), x) -> R = yes ; R = no )"),
    ("sa36", raw"nb_linkarg(a, f(a), x), R = yes"),
    ("sa37", raw"nb_linkarg(1, a, x), R = yes"),
    ("sa38", raw"nb_linkarg(1, _, x), R = yes"),
    # sa39-sa51 nb_setarg/3 and nb_linkarg/3: no undo on backtracking, the value kept
    ("sa39", raw"T = f(a,b), nb_setarg(1, T, x), R = T"),
    ("sa40", raw"T = f(a), ( nb_setarg(1, T, x), fail ; true ), R = T"),
    ("sa41", raw"T = f(a), ( setarg(1, T, b), nb_setarg(1, T, c), fail ; true ), R = T"),
    ("sa42", raw"T = f(a), ( nb_setarg(1, T, b), setarg(1, T, c), fail ; true ), R = T"),
    ("sa43", raw"T = f(a), ( nb_setarg(1, T, g(1)), fail ; true ), R = T"),
    ("sa44", raw"T = f(a), ( X is 1.5*2, nb_setarg(1, T, X), fail ; true ), R = T"),
    ("sa45", raw"T = f(a), ( X is 1<<70, nb_setarg(1, T, X), fail ; true ), R = T"),
    ("sa46", raw"T = f(a), ( string_to_atom(S, abc), nb_setarg(1, T, S), fail ; true ), R = T"),
    ("sa47", raw"T = f(a), ( nb_setarg(1, T, [x,y,z]), fail ; true ), R = T"),
    ("sa48", raw"T = c(0), ( sa_mem(_, [1,2,3]), sa_inc(T), fail ; true ), R = T"),
    ("sa49", raw"T = c(0), ( sa_mem(_, [1,2,3]), sa_binc(T), fail ; true ), R = T"),
    ("sa50", raw"T = acc([]), ( sa_mem(X, [a,b,c]), arg(1, T, L), nb_setarg(1, T, [X|L]), fail ; true ), arg(1, T, R)"),
    ("sa51", raw"T = f(a), ( nb_linkarg(1, T, g(1)), fail ; true ), R = T"),
    # sa52-sa67 sharing: setarg and nb_linkarg link the value, nb_setarg copies it but keeps the old argument's compound
    ("sa52", raw"T = f(a), V = g(1), setarg(1, T, V), arg(1, T, A), sa_same(A, V, R)"),
    ("sa53", raw"T = f(a), V = g(1), nb_setarg(1, T, V), arg(1, T, A), sa_same(A, V, R)"),
    ("sa54", raw"T = f(a), V = g(1), nb_linkarg(1, T, V), arg(1, T, A), sa_same(A, V, R)"),
    ("sa55", raw"T = f(g(1)), arg(1, T, Old), nb_setarg(1, T, h(Old)), arg(1, T, H), arg(1, H, O2), sa_same(O2, Old, R)"),
    ("sa56", raw"T = f(g(1)), arg(1, T, Old), nb_setarg(1, T, h(i(Old))), arg(1, T, H), arg(1, H, I), arg(1, I, O2), sa_same(O2, Old, R)"),
    ("sa57", raw"T = f(g(1)), arg(1, T, Old), nb_setarg(1, T, Old), arg(1, T, A), sa_same(A, Old, R)"),
    ("sa58", raw"T = f(g(1)), arg(1, T, Old), nb_setarg(1, T, h(g(1))), arg(1, T, H), arg(1, H, O2), sa_same(O2, Old, R)"),
    ("sa59", raw"T = f(g(1), k), arg(1, T, Old), nb_setarg(2, T, h(Old)), arg(2, T, H), arg(1, H, O2), sa_same(O2, Old, R)"),
    ("sa60", raw"T = f(g(a)), arg(1, T, G), setarg(1, G, b), R = T"),
    ("sa61", raw"T = f(g(a)), arg(1, T, G), ( nb_setarg(1, G, b), fail ; true ), R = T"),
    ("sa62", raw"X = f(a), Y = g(X), setarg(1, X, b), R = Y"),
    ("sa63", raw"L = [a,b], setarg(1, L, x), setarg(2, L, [z]), R = L"),
    ("sa64", raw"compound_name_arguments(T, foo, []), ( setarg(1, T, a) -> R = yes ; R = no )"),
    ("sa65", raw"findall(x, setarg(1, f(a), b), R)"),
    ("sa66", raw"findall(x, nb_setarg(1, f(a), b), R)"),
    ("sa67", raw"findall(x, nb_linkarg(1, f(a), b), R)"),
    # sa68-sa77 attributed variables and cycles (UNVERIFIED on the kernel: gate decides)
    ("sa68", raw"put_attr(X, sa, 1), T = f(a), setarg(1, T, X), arg(1, T, A), get_attr(A, sa, R)"),
    ("sa69", raw"put_attr(X, sa, 1), T = f(a), ( setarg(1, T, X), fail ; true ), R = T"),
    ("sa70", raw"put_attr(X, sa, 1), T = f(a), ( nb_setarg(1, T, X), fail ; true ), arg(1, T, A), ( attvar(A) -> R = att ; R = plain )"),
    ("sa71", raw"put_attr(X, sa, 1), T = f(a), nb_setarg(1, T, g(X)), arg(1, T, G), arg(1, G, A), ( attvar(A) -> get_attr(A, sa, R) ; R = plain )"),
    ("sa72", raw"put_attr(X, sa, 1), T = f(X), setarg(1, T, b), get_attr(X, sa, V), R = T-V"),
    ("sa73", raw"X = g(X), T = f(a), setarg(1, T, X), arg(1, T, A), ( cyclic_term(A) -> R = cyc ; R = acyc )"),
    ("sa74", raw"X = g(X), T = f(a), nb_setarg(1, T, X), arg(1, T, A), ( cyclic_term(A) -> R = cyc ; R = acyc )"),
    ("sa75", raw"X = g(X), T = f(a), nb_setarg(1, T, X), arg(1, T, A), sa_same(A, X, R)"),
    ("sa76", raw"T = f(T), setarg(1, T, b), R = T"),
    ("sa77", raw"T = f(T), ( setarg(1, T, b), fail ; true ), arg(1, T, A), sa_same(A, T, R)"),
    # sa78-sa81 a variable as the value
    ("sa78", raw"T = f(a), nb_setarg(1, T, X), X = q, R = T"),
    ("sa79", raw"T = f(a), nb_setarg(1, T, X), arg(1, T, A), ( A == X -> R = same ; R = diff )"),
    ("sa80", raw"T = f(a), nb_linkarg(1, T, X), X = q, R = T"),
    ("sa81", raw"T = f(a), ( nb_setarg(1, T, X), fail ; true ), arg(1, T, A), ( var(A) -> R = var ; R = nonvar )"),
    # sa82-sa83 an attributed variable created INSIDE the failing branch (UNVERIFIED on the kernel: gate decides)
    ("sa82", raw"T = f(a), ( put_attr(X, sa, 1), nb_setarg(1, T, X), fail ; true ), arg(1, T, A), ( attvar(A) -> get_attr(A, sa, R) ; R = plain )"),
    ("sa83", raw"T = f(a), ( put_attr(X, sa, 1), nb_setarg(1, T, g(X)), fail ; true ), arg(1, T, G), arg(1, G, A), ( attvar(A) -> get_attr(A, sa, R) ; R = plain )")
]

# the driver's whole output, one line per case after `ok`, filled by evidence/SETARG/gen_rows.py --fill from swipl 10.1.19
const _SA_PINNED = [
    "ok",
    "t_sa01 c[116,95,115,97,48,49]/1(c[102]/2(a[120],a[98]))",
    "t_sa02 c[116,95,115,97,48,50]/1(c[102]/2(a[97],a[120]))",
    "t_sa03 c[116,95,115,97,48,51]/1(c[102]/3(a[97],a[98],a[99]))",
    "t_sa04 c[116,95,115,97,48,52]/1(c[102]/1(a[121]))",
    "t_sa05 c[116,95,115,97,48,53]/1(c[102]/1(a[97]))",
    "t_sa06 c[116,95,115,97,48,54]/1(c[102]/1(a[120]))",
    "t_sa07 c[116,95,115,97,48,55]/1(c[102]/1(a[118]))",
    "t_sa08 c[116,95,115,97,48,56]/1(c[102]/1(V0))",
    "t_sa09 c[116,95,115,97,48,57]/1(c[45]/2(a[97],c[102]/1(a[97])))",
    "t_sa10 c[116,95,115,97,49,48]/1(c[45]/2(V0,c[102]/1(V0)))",
    "t_sa11 c[116,95,115,97,49,49]/1(c[45]/2(a[99],c[102]/1(a[99])))",
    "t_sa12 c[116,95,115,97,49,50]/1(c[45]/2(c[102]/1(V0),V0))",
    "t_sa13 c[116,95,115,97,49,51]/1(c[45]/2(c[102]/1(a[113]),a[113]))",
    "t_sa14 c[116,95,115,97,49,52]/1(c[45]/2(c[102]/1(V0),V0))",
    "t_sa15 c[116,95,115,97,49,53]/1(a[110,111])",
    "t_sa16 c[116,95,115,97,49,54]/1(a[110,111])",
    "t_sa17 c[116,95,115,97,49,55]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[110,111,116,95,108,101,115,115,95,116,104,97,110,95,122,101,114,111],i-1)))",
    "t_sa18 c[116,95,115,97,49,56]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_sa19 c[116,95,115,97,49,57]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],a[97])))",
    "t_sa20 c[116,95,115,97,50,48]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],f1.0)))",
    "t_sa21 c[116,95,115,97,50,49]/1(c[114,97,105,115,101,100]/1(c[114,101,112,114,101,115,101,110,116,97,116,105,111,110,95,101,114,114,111,114]/1(a[115,105,122,101,95,116])))",
    "t_sa22 c[116,95,115,97,50,50]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[110,111,116,95,108,101,115,115,95,116,104,97,110,95,122,101,114,111],i-1180591620717411303424)))",
    "t_sa23 c[116,95,115,97,50,51]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,111,109,112,111,117,110,100],a[97])))",
    "t_sa24 c[116,95,115,97,50,52]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_sa25 c[116,95,115,97,50,53]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,111,109,112,111,117,110,100],i3)))",
    "t_sa26 c[116,95,115,97,50,54]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,111,109,112,111,117,110,100],s[97,98,99])))",
    "t_sa27 c[116,95,115,97,50,55]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,111,109,112,111,117,110,100],nil)))",
    "t_sa28 c[116,95,115,97,50,56]/1(a[110,111])",
    "t_sa29 c[116,95,115,97,50,57]/1(a[110,111])",
    "t_sa30 c[116,95,115,97,51,48]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],a[97])))",
    "t_sa31 c[116,95,115,97,51,49]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[110,111,116,95,108,101,115,115,95,116,104,97,110,95,122,101,114,111],i-1)))",
    "t_sa32 c[116,95,115,97,51,50]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,111,109,112,111,117,110,100],a[97])))",
    "t_sa33 c[116,95,115,97,51,51]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_sa34 c[116,95,115,97,51,52]/1(a[110,111])",
    "t_sa35 c[116,95,115,97,51,53]/1(a[110,111])",
    "t_sa36 c[116,95,115,97,51,54]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],a[97])))",
    "t_sa37 c[116,95,115,97,51,55]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,111,109,112,111,117,110,100],a[97])))",
    "t_sa38 c[116,95,115,97,51,56]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_sa39 c[116,95,115,97,51,57]/1(c[102]/2(a[120],a[98]))",
    "t_sa40 c[116,95,115,97,52,48]/1(c[102]/1(a[120]))",
    "t_sa41 c[116,95,115,97,52,49]/1(c[102]/1(a[97]))",
    "t_sa42 c[116,95,115,97,52,50]/1(c[102]/1(a[98]))",
    "t_sa43 c[116,95,115,97,52,51]/1(c[102]/1(c[103]/1(i1)))",
    "t_sa44 c[116,95,115,97,52,52]/1(c[102]/1(f3.0))",
    "t_sa45 c[116,95,115,97,52,53]/1(c[102]/1(i1180591620717411303424))",
    "t_sa46 c[116,95,115,97,52,54]/1(c[102]/1(s[97,98,99]))",
    "t_sa47 c[116,95,115,97,52,55]/1(c[102]/1(c[91,124,93]/2(a[120],c[91,124,93]/2(a[121],c[91,124,93]/2(a[122],nil)))))",
    "t_sa48 c[116,95,115,97,52,56]/1(c[99]/1(i3))",
    "t_sa49 c[116,95,115,97,52,57]/1(c[99]/1(i0))",
    "t_sa50 c[116,95,115,97,53,48]/1(c[91,124,93]/2(a[99],c[91,124,93]/2(a[98],c[91,124,93]/2(a[97],nil))))",
    "t_sa51 c[116,95,115,97,53,49]/1(c[102]/1(c[103]/1(i1)))",
    "t_sa52 c[116,95,115,97,53,50]/1(a[115,97,109,101])",
    "t_sa53 c[116,95,115,97,53,51]/1(a[100,105,115,116,105,110,99,116])",
    "t_sa54 c[116,95,115,97,53,52]/1(a[115,97,109,101])",
    "t_sa55 c[116,95,115,97,53,53]/1(a[115,97,109,101])",
    "t_sa56 c[116,95,115,97,53,54]/1(a[115,97,109,101])",
    "t_sa57 c[116,95,115,97,53,55]/1(a[115,97,109,101])",
    "t_sa58 c[116,95,115,97,53,56]/1(a[100,105,115,116,105,110,99,116])",
    "t_sa59 c[116,95,115,97,53,57]/1(a[100,105,115,116,105,110,99,116])",
    "t_sa60 c[116,95,115,97,54,48]/1(c[102]/1(c[103]/1(a[98])))",
    "t_sa61 c[116,95,115,97,54,49]/1(c[102]/1(c[103]/1(a[98])))",
    "t_sa62 c[116,95,115,97,54,50]/1(c[103]/1(c[102]/1(a[98])))",
    "t_sa63 c[116,95,115,97,54,51]/1(c[91,124,93]/2(a[120],c[91,124,93]/2(a[122],nil)))",
    "t_sa64 c[116,95,115,97,54,52]/1(a[110,111])",
    "t_sa65 c[116,95,115,97,54,53]/1(c[91,124,93]/2(a[120],nil))",
    "t_sa66 c[116,95,115,97,54,54]/1(c[91,124,93]/2(a[120],nil))",
    "t_sa67 c[116,95,115,97,54,55]/1(c[91,124,93]/2(a[120],nil))",
    "t_sa68 c[116,95,115,97,54,56]/1(i1)",
    "t_sa69 c[116,95,115,97,54,57]/1(c[102]/1(a[97]))",
    "t_sa70 c[116,95,115,97,55,48]/1(a[97,116,116])",
    "t_sa71 c[116,95,115,97,55,49]/1(i1)",
    "t_sa72 c[116,95,115,97,55,50]/1(c[45]/2(c[102]/1(a[98]),i1))",
    "t_sa73 c[116,95,115,97,55,51]/1(a[99,121,99])",
    "t_sa74 c[116,95,115,97,55,52]/1(a[99,121,99])",
    "t_sa75 c[116,95,115,97,55,53]/1(a[100,105,115,116,105,110,99,116])",
    "t_sa76 c[116,95,115,97,55,54]/1(c[102]/1(a[98]))",
    "t_sa77 c[116,95,115,97,55,55]/1(a[115,97,109,101])",
    "t_sa78 c[116,95,115,97,55,56]/1(c[102]/1(a[113]))",
    "t_sa79 c[116,95,115,97,55,57]/1(a[115,97,109,101])",
    "t_sa80 c[116,95,115,97,56,48]/1(c[102]/1(a[113]))",
    "t_sa81 c[116,95,115,97,56,49]/1(a[118,97,114])",
    "t_sa82 c[116,95,115,97,56,50]/1(i1)",
    "t_sa83 c[116,95,115,97,56,51]/1(i1)"
]

function _sa_file()::Tuple{String, Vector{String}}
    names = ["t_$(id)" for (id, _) in _SA_CASES]
    text =
        _SA_PROGRAM * join([
            "t_$(id)(R) :- catch(($g), error(SsuE, _), R = raised(SsuE)).\n" for
            (id, g) in _SA_CASES
        ])
    f = joinpath(mktempdir(), "setarg.pl")
    write(f, text)
    return f, names
end

"The kernel's lines for `names` after consulting `path`, as the driver writes swipl's; the database, for the white-box tests."
function _sa_kernel(path::String, names::Vector{String})
    gd = LK.PL_global_data{_SA}()
    ld = LK.PL_local_data{_SA}(gd)
    st, ball, _ = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * _sa_enc(ball::_SA)]
    for name in names
        proc = LK.isCurrentProcedure(sym_key(_sas(name)), 1, LK.MODULE_user(gd))
        if proc === nothing || !LK.isDefinedProcedure(gd, proc)
            push!(out, "$name undefined")
            continue
        end
        sols = String[]
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 1)
        LK.putSlotValue!(ld, a + 1, mk_var(_SA, LK.fresh_var_keys!(1)), LK.PutVarMap())
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
        )
        n = 0
        while (n += 1) <= 50
            rc = LK.PL_next_solution(gd, ld, qid)
            if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
                push!(
                    sols,
                    _sa_enc(mk_expr(_SA, _SA[_sas(name), lk_answers(ld, (a:a)...)...]))
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

@testset "setarg/3, nb_setarg/3, nb_linkarg/3 as swipl's (sa01-sa83)" begin
    f, names = _sa_file()
    kl, _, _ = _sa_kernel(f, names)
    @test length(kl) == length(_SA_PINNED)
    for (k, p) in zip(kl, _SA_PINNED)
        k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
        @test k == p
    end
end

@testset "the setarg rows are not vacuous (sa01-sa83)" begin
    # the program loaded (`ok`); every row has a line; the failing rows answer `no`, the errors `raised(_)`
    @test _SA_PINNED[1] == "ok"
    @test all(id -> any(l -> l == "t_$id" || startswith(l, "t_$id "), _SA_PINNED), first.(_SA_CASES))
    @test count(l -> occursin("c[114,97,105,115,101,100]", l), _SA_PINNED) >= 10   # the errors
    @test any(l -> occursin("a[100,105,115,116,105,110,99,116]", l), _SA_PINNED)    # `distinct`: nb_setarg copied
    @test any(l -> occursin("a[115,97,109,101]", l), _SA_PINNED)                    # `same`: linked or kept shared
    @test count(l -> occursin("a[110,111])", l), _SA_PINNED) >= 6                   # `no`: the rows that failed
end

@testset "the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    # the pinned table is the driver's whole output (the inert-testset guard: an assertion either way)
    @test length(_SA_PINNED) == length(_SA_CASES) + 1
    if swipl === nothing
        @info "SETARG LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        f, names = _sa_file()
        @test _sa_swipl_lines(f, names) == _SA_PINNED
    end
end
