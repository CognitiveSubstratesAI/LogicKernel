# ORIGINAL: a LIVE differential of pl-mutex.c's mutex predicates in their single-thread form (MUTEX): mutex_create/1,2,
# mutex_destroy/1, mutex_lock/1, mutex_trylock/1, mutex_unlock/1, mutex_unlock_all/0 and mutex_property/2, against swipl at the
# pin: rows m01-m56, ids prefixed `m`, the main thread's behaviour only (the kernel has no second thread):
#   * A PROGRAM consulted by the kernel's loader and cases `t_<id>(R)` run in order in one database, each wrapped in
#     `catch(Goal, error(E, _), R = raised(E))`; the driver is test_p2_swipl.jl's (`enc`oded answers). Each row names its own
#     mutexes (the table persists across the cases); an anonymous mutex is never printed (blob/2, `X == M`).
#   * Every answer line is swipl's, PINNED (swipl 10.1.20 (the pin binary), two runs byte-identical, evidence/MUTEX/gen_rows.py
#     --fill); with `swipl` on PATH the live answers are compared with the pins too.
#   * m01-m10 create (names, anonymous, the errors, mutex_create/2); m11-m21 lock, unlock, trylock, destroy and the status;
#     m22-m28 the type, instantiation and domain errors; m29-m32, m38 mutex_property/2 enumeration; m33-m34, m56
#     mutex_unlock_all/0; m35-m37, m39-m55 recreation, destroyed mutexes, the error contexts.
#   * UNVERIFIED on the kernel: gate decides (nothing was compiled when these rows were written): every kernel answer.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: all three: the predicates take the term type through the term interface (atoms, integers, compounds)
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _MX = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_mxs(x) = lk_sym(_MX, Symbol(x))


_mx_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _mx_enc(t::_MX, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _mx_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _mx_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _mx_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_mx_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

# the swipl side: test/core_lang/test_ssu_swipl.jl's driver (consult, then every answer of each t_<id>/1, `enc`oded)
const _MX_DRIVER = raw"""
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
function _mx_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _MX_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(pipeline(`swipl -q $f`; stdin=devnull, stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end



# the program: a helper that locks a mutex N times
const _MX_PROGRAM = raw"""
m_lock_n(0, _) :- !.
m_lock_n(N, M) :- mutex_lock(M), N1 is N-1, m_lock_n(N1, M).
"""

const _MX_CASES = [
    ("m01", raw"mutex_create(mx01), mutex_property(mx01, alias(R))"),
    ("m02", raw"mutex_create(M), blob(M, R)"),
    ("m03", raw"mutex_create(M), \+ mutex_property(M, alias(_)), R = no_alias"),
    ("m04", raw"mutex_create(mx04), mutex_property(mx04, status(R))"),
    ("m05", raw"mutex_create(f(x))"),
    ("m06", raw"mutex_create(mx06), mutex_create(mx06)"),
    ("m07", raw"mutex_create(M, [alias(mx07)]), R = M"),
    ("m08", raw"mutex_create(mx08, [alias(mx08b)])"),
    ("m09", raw"mutex_create(_, [alias(1)])"),
    ("m10", raw"mutex_create(M, []), blob(M, R)"),
    (
        "m11",
        raw"mutex_create(mx11), mutex_lock(mx11), mutex_lock(mx11), mutex_property(mx11, status(R))"
    ),
    (
        "m12",
        raw"mutex_create(mx12), mutex_lock(mx12), mutex_lock(mx12), mutex_unlock(mx12), mutex_property(mx12, status(R))"
    ),
    (
        "m13",
        raw"mutex_create(mx13), mutex_lock(mx13), mutex_unlock(mx13), mutex_property(mx13, status(R))"
    ),
    ("m14", raw"mutex_create(mx14), mutex_unlock(mx14)"),
    ("m15", raw"mutex_unlock(mx15)"),
    ("m16", raw"mutex_destroy(mx16)"),
    ("m17", raw"mutex_lock(mx17), mutex_property(mx17, status(R))"),
    ("m18", raw"mutex_trylock(mx18), mutex_trylock(mx18), mutex_property(mx18, status(R))"),
    ("m19", raw"mutex_create(mx19), mutex_destroy(mx19), mutex_property(mx19, status(_))"),
    (
        "m20",
        raw"mutex_create(mx20), mutex_lock(mx20), mutex_destroy(mx20), mutex_property(mx20, status(R))"
    ),
    (
        "m21",
        raw"mutex_create(mx21), mutex_lock(mx21), mutex_destroy(mx21), mutex_unlock(mx21), catch(mutex_property(mx21, status(_)), error(E, _), R = E)"
    ),
    ("m22", raw"mutex_lock(_)"),
    ("m23", raw"mutex_lock(f(x))"),
    ("m24", raw"mutex_lock(1)"),
    ("m25", raw"mutex_lock([])"),
    ("m26", raw"mutex_create(mx26), mutex_property(mx26, foo(x))"),
    ("m27", raw"mutex_create(mx27), mutex_property(mx27, 3)"),
    ("m28", raw"mutex_property(_, foo(1))"),
    ("m29", raw"mutex_create(mx29), findall(P, mutex_property(mx29, P), R)"),
    ("m30", raw"mutex_create(M), findall(P, mutex_property(M, P), R)"),
    (
        "m31",
        raw"mutex_create(mx31), mutex_lock(mx31), findall(P, mutex_property(mx31, P), R)"
    ),
    (
        "m32",
        raw"mutex_create(mxe_b), mutex_create(mxe_a), mutex_create(mxe_c), mutex_lock(mxe_b), findall(A-S, (mutex_property(M, alias(A)), sub_atom(A, 0, _, _, mxe_), mutex_property(M, status(S))), L0), msort(L0, R)"
    ),
    (
        "m33",
        raw"mutex_create(mx33), mutex_lock(mx33), mutex_lock(mx33), mutex_unlock_all, mutex_property(mx33, status(R))"
    ),
    ("m34", raw"mutex_create(mx34), mutex_lock(mx34), mutex_unlock_all, mutex_unlock(mx34)"),
    (
        "m35",
        raw"mutex_create(mx35), mutex_destroy(mx35), mutex_create(mx35), mutex_property(mx35, status(R))"
    ),
    (
        "m36",
        raw"mutex_create(M), mutex_destroy(M), catch(mutex_lock(M), error(existence_error(mutex, X), _), true), ( X == M -> R = same ; R = other )"
    ),
    ("m37", raw"mutex_create(M), mutex_lock(M), mutex_property(M, status(R))"),
    (
        "m38",
        raw"mutex_create(M), m_lock_n(7, M), findall(x, (mutex_property(X, status(locked(main, 7))), X == M), R)"
    ),
    ("m39", raw"mutex_trylock(f(x))"),
    (
        "m40",
        raw"mutex_create(M), mutex_lock(M), mutex_destroy(M), mutex_unlock(M), catch(mutex_unlock(M), error(existence_error(mutex, X), _), true), ( X == M -> R = gone ; R = other )"
    ),
    (
        "m41",
        raw"mutex_create(mx41), mutex_lock(mx41), mutex_destroy(mx41), mutex_lock(mx41), mutex_unlock(mx41), mutex_property(mx41, status(R))"
    ),
    ("m42", raw"mutex_create(_, foo)"),
    ("m43", raw"mutex_create(M, [alias(mx43), unknown(1)]), R = M"),
    ("m44", raw"mutex_create(_, [alias(_)])"),
    ("m45", raw"mutex_create(mx45), mutex_property(mx45, alias(other))"),
    ("m46", raw"mutex_create(M), mutex_property(M, status(locked(_, _)))"),
    (
        "m47",
        raw"mutex_create(mx47), mutex_lock(mx47), mutex_property(mx47, status(locked(B, C))), R = B-C"
    ),
    (
        "m48",
        raw"mutex_create(mx48), mutex_lock(mx48), mutex_property(mx48, status(locked(other, 1)))"
    ),
    ("m49", raw"mutex_create([]), R = created"),
    ("m50", raw"mutex_create(1)"),
    ("m51", raw"mutex_trylock(mx51), mutex_unlock(mx51), mutex_unlock(mx51)"),
    (
        "m52",
        raw"mutex_create(mx52), catch(mutex_unlock(mx52), error(_, context(P, Msg)), true), R = P-Msg"
    ),
    ("m53", raw"catch(mutex_create(f(x)), error(_, context(P, _)), true), R = P"),
    ("m54", raw"catch(mutex_lock(f(x)), error(_, context(P, _)), true), R = P"),
    (
        "m55",
        raw"catch(mutex_create(mx55, [alias(mx55b)]), error(_, context(P, Msg)), true), R = P-Msg"
    ),
    (
        "m56",
        raw"mutex_create(mx56), mutex_lock(mx56), mutex_lock(mx56), mutex_unlock_all, mutex_unlock(mx56)"
    )
]

# the driver's whole output, one line per case after `ok`, filled by evidence/MUTEX/gen_rows.py --fill from swipl 10.1.20
const _MX_PINNED = [
    "ok",
    "t_m01 c[116,95,109,48,49]/1(a[109,120,48,49])",
    "t_m02 c[116,95,109,48,50]/1(a[109,117,116,101,120])",
    "t_m03 c[116,95,109,48,51]/1(a[110,111,95,97,108,105,97,115])",
    "t_m04 c[116,95,109,48,52]/1(a[117,110,108,111,99,107,101,100])",
    "t_m05 c[116,95,109,48,53]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[109,117,116,101,120],c[102]/1(a[120]))))",
    "t_m06 c[116,95,109,48,54]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[99,114,101,97,116,101],a[109,117,116,101,120],a[109,120,48,54])))",
    "t_m07 c[116,95,109,48,55]/1(a[109,120,48,55])",
    "t_m08 c[116,95,109,48,56]/1(c[114,97,105,115,101,100]/1(c[117,110,105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]/1(a[109,120,48,56])))",
    "t_m09 c[116,95,109,48,57]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],i1)))",
    "t_m10 c[116,95,109,49,48]/1(a[109,117,116,101,120])",
    "t_m11 c[116,95,109,49,49]/1(c[108,111,99,107,101,100]/2(a[109,97,105,110],i2))",
    "t_m12 c[116,95,109,49,50]/1(c[108,111,99,107,101,100]/2(a[109,97,105,110],i1))",
    "t_m13 c[116,95,109,49,51]/1(a[117,110,108,111,99,107,101,100])",
    "t_m14 c[116,95,109,49,52]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[117,110,108,111,99,107],a[109,117,116,101,120],a[109,120,49,52])))",
    "t_m15 c[116,95,109,49,53]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[109,117,116,101,120],a[109,120,49,53])))",
    "t_m16 c[116,95,109,49,54]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[109,117,116,101,120],a[109,120,49,54])))",
    "t_m17 c[116,95,109,49,55]/1(c[108,111,99,107,101,100]/2(a[109,97,105,110],i1))",
    "t_m18 c[116,95,109,49,56]/1(c[108,111,99,107,101,100]/2(a[109,97,105,110],i2))",
    "t_m19 c[116,95,109,49,57]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[109,117,116,101,120],a[109,120,49,57])))",
    "t_m20 c[116,95,109,50,48]/1(c[108,111,99,107,101,100]/2(a[109,97,105,110],i1))",
    "t_m21 c[116,95,109,50,49]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[109,117,116,101,120],a[109,120,50,49]))",
    "t_m22 c[116,95,109,50,50]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_m23 c[116,95,109,50,51]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[109,117,116,101,120],c[102]/1(a[120]))))",
    "t_m24 c[116,95,109,50,52]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[109,117,116,101,120],i1)))",
    "t_m25 c[116,95,109,50,53]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[109,117,116,101,120],nil)))",
    "t_m26 c[116,95,109,50,54]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[109,117,116,101,120,95,112,114,111,112,101,114,116,121],c[102,111,111]/1(a[120]))))",
    "t_m27 c[116,95,109,50,55]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[109,117,116,101,120,95,112,114,111,112,101,114,116,121],i3)))",
    "t_m28 c[116,95,109,50,56]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[109,117,116,101,120,95,112,114,111,112,101,114,116,121],c[102,111,111]/1(i1))))",
    "t_m29 c[116,95,109,50,57]/1(c[91,124,93]/2(c[97,108,105,97,115]/1(a[109,120,50,57]),c[91,124,93]/2(c[115,116,97,116,117,115]/1(a[117,110,108,111,99,107,101,100]),nil)))",
    "t_m30 c[116,95,109,51,48]/1(c[91,124,93]/2(c[115,116,97,116,117,115]/1(a[117,110,108,111,99,107,101,100]),nil))",
    "t_m31 c[116,95,109,51,49]/1(c[91,124,93]/2(c[97,108,105,97,115]/1(a[109,120,51,49]),c[91,124,93]/2(c[115,116,97,116,117,115]/1(c[108,111,99,107,101,100]/2(a[109,97,105,110],i1)),nil)))",
    "t_m32 c[116,95,109,51,50]/1(c[91,124,93]/2(c[45]/2(a[109,120,101,95,97],a[117,110,108,111,99,107,101,100]),c[91,124,93]/2(c[45]/2(a[109,120,101,95,98],c[108,111,99,107,101,100]/2(a[109,97,105,110],i1)),c[91,124,93]/2(c[45]/2(a[109,120,101,95,99],a[117,110,108,111,99,107,101,100]),nil))))",
    "t_m33 c[116,95,109,51,51]/1(a[117,110,108,111,99,107,101,100])",
    "t_m34 c[116,95,109,51,52]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[117,110,108,111,99,107],a[109,117,116,101,120],a[109,120,51,52])))",
    "t_m35 c[116,95,109,51,53]/1(a[117,110,108,111,99,107,101,100])",
    "t_m36 c[116,95,109,51,54]/1(a[115,97,109,101])",
    "t_m37 c[116,95,109,51,55]/1(c[108,111,99,107,101,100]/2(a[109,97,105,110],i1))",
    "t_m38 c[116,95,109,51,56]/1(c[91,124,93]/2(a[120],nil))",
    "t_m39 c[116,95,109,51,57]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[109,117,116,101,120],c[102]/1(a[120]))))",
    "t_m40 c[116,95,109,52,48]/1(a[103,111,110,101])",
    "t_m41 c[116,95,109,52,49]/1(c[108,111,99,107,101,100]/2(a[109,97,105,110],i1))",
    "t_m42 c[116,95,109,52,50]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[108,105,115,116],a[102,111,111])))",
    "t_m43 c[116,95,109,52,51]/1(a[109,120,52,51])",
    "t_m44 c[116,95,109,52,52]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_m45",
    "t_m46",
    "t_m47 c[116,95,109,52,55]/1(c[45]/2(a[109,97,105,110],i1))",
    "t_m48",
    "t_m49 c[116,95,109,52,57]/1(a[99,114,101,97,116,101,100])",
    "t_m50 c[116,95,109,53,48]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[109,117,116,101,120],i1)))",
    "t_m51 c[116,95,109,53,49]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[117,110,108,111,99,107],a[109,117,116,101,120],a[109,120,53,49])))",
    "t_m52 c[116,95,109,53,50]/1(c[45]/2(c[47]/2(a[109,117,116,101,120,95,117,110,108,111,99,107],i1),a[110,111,116,32,108,111,99,107,101,100]))",
    "t_m53 c[116,95,109,53,51]/1(c[47]/2(a[109,117,116,101,120,95,99,114,101,97,116,101],i1))",
    "t_m54 c[116,95,109,53,52]/1(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[109,117,116,101,120,95,108,111,99,107],i1)))",
    "t_m55 c[116,95,109,53,53]/1(c[45]/2(c[47]/2(a[109,117,116,101,120,95,99,114,101,97,116,101],i2),a[49,45,115,116,32,97,114,103,117,109,101,110,116]))",
    "t_m56 c[116,95,109,53,54]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[117,110,108,111,99,107],a[109,117,116,101,120],a[109,120,53,54])))"
]

function _mx_file()::Tuple{String, Vector{String}}
    names = ["t_$(id)" for (id, _) in _MX_CASES]
    text =
        _MX_PROGRAM * join([
            "t_$(id)(R) :- catch(($g), error(SsuE, _), R = raised(SsuE)).\n" for
            (id, g) in _MX_CASES
        ])
    f = joinpath(mktempdir(), "mutex.pl")
    write(f, text)
    return f, names
end

"The kernel's lines for `names` after consulting `path`, as the driver writes swipl's; the database, for the white-box tests."
function _mx_kernel(path::String, names::Vector{String})
    gd = LK.PL_global_data{_MX}()
    ld = LK.PL_local_data{_MX}(gd)
    st, ball = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * _mx_enc(ball::_MX)]
    for name in names
        proc = LK.isCurrentProcedure(sym_key(_mxs(name)), 1, LK.MODULE_user(gd))
        if proc === nothing || !LK.isDefinedProcedure(gd, proc)
            push!(out, "$name undefined")
            continue
        end
        sols = String[]
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 1)
        LK.putSlotValue!(ld, a + 1, mk_var(_MX, LK.fresh_var_keys!(1)), LK.PutVarMap())
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
        )
        n = 0
        while (n += 1) <= 50
            rc = LK.PL_next_solution(gd, ld, qid)
            if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
                push!(
                    sols,
                    _mx_enc(mk_expr(_MX, _MX[_mxs(name), lk_answers(ld, (a:a)...)...]))
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


@testset "mutex predicates as swipl's (m01-m56)" begin
    f, names = _mx_file()
    kl, gd, ld = _mx_kernel(f, names)
    @test length(kl) == length(_MX_PINNED)
    for (k, p) in zip(kl, _MX_PINNED)
        k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
        @test k == p
    end
    @test LK.live_states(ld) == 0                                  # every mutex_property/2 state was given back
end

@testset "the MUTEX rows are not vacuous" begin
    # the program loaded; every case has a line; the answering rows answer, the failing rows have none, the raising rows raise
    @test _MX_PINNED[1] == "ok"
    @test length(_MX_PINNED) == length(_MX_CASES) + 1
    answered = count(
        l -> occursin(" c[", l) || occursin(" a[", l) || occursin(" i", l), _MX_PINNED
    )
    @test answered >= 35
    @test any(l -> !occursin(" ", l) && startswith(l, "t_m"), _MX_PINNED)          # a row without an answer: it failed
    @test count(l -> occursin("[114,97,105,115,101,100]", l), _MX_PINNED) >= 20   # the error rows
    for id in ("m01", "m11", "m12", "m29", "m32", "m38", "m41")
        @test any(
            l -> startswith(l, "t_$id ") && !occursin("[114,97,105,115,101,100]", l),
            _MX_PINNED
        )                                                                          # an answer
    end
end

@testset "the MUTEX pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    @test length(_MX_PINNED) == length(_MX_CASES) + 1
    if swipl === nothing
        @info "MUTEX LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        f, names = _mx_file()
        @test _mx_swipl_lines(f, names) == _MX_PINNED
    end
end
