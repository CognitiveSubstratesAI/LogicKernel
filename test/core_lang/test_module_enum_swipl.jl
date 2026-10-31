# ORIGINAL: MOD6's gate (lk-channel evidence/r2/design/modules.md §7) — `import_module/2` and `'$current_module'/2` (pl-modul.c, the
# `module_enum` pool, NF1's protocol) against swipl 10.1.19; the rows are tests/core_lang style.
# test/core_lang/test_module_enum_swipl.jl — the module enumerations (MOD6), through a PROGRAM (the pattern of
# test/core_lang/test_declare_destroy_swipl.jl): `import_module/2` on `user`, `system`, a module made by the call, a module with a custom
# super list (the answers in order, determinism of each, a bound second argument that only tests the FIRST super, the list changing under
# the enumeration, the errors); `'$current_module'/2` in its four modes (module → file, file → module or list of modules, enumeration,
# the failures), what the enumeration hides (a temporary module; a `system`-class module other than `system`), that EVERY answer leaves a
# choice point, a cut after the first answer, and the interplay with `'$destroy_module'/1` (MOD5b).
#   * A PROGRAM consulted by the kernel's loader and cases `t_<id>(R)` run IN ORDER in one database, each wrapped in
#     `catch(Goal, error(F, _), R = raised(F))` and followed by `mme_done` (the source and typein modules back to `user`).
#   * Every enumeration is compared SORTED (modules.md H9: swipl's order is its hash table's, the kernel's creation order; D-0149); a
#     row that compares a LIST of modules in a given order (c07, i06-i09, i19) is an order swipl fixes (the super list, the file's list).
#   * Every answer line is swipl's, PINNED (swipl 10.1.19-1-gcbf4e189, this program and test_declare_destroy_swipl.jl's driver; lk-channel
#     evidence/MOD6/mm_rows.out in the MOD6 branch); with `swipl` on PATH the live answers are compared with the pins too.
#   * After every row the kernel's `live_states` is 0 (the `module_enum` pool is empty): a missing `FRG_CUTTED` shows as a count.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — the module enumerations (src/pl-modul.jl), built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _MM = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_mms(x) = lk_sym(_MM, Symbol(x))

_mm_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _mm_enc(t::_MM, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _mm_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _mm_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _mm_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_mm_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

# the swipl side: test_declare_destroy_swipl.jl's driver (consult, then every answer of each t_<id>/1, `enc`oded)
const _MM_DRIVER = raw"""
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
function _mm_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _MM_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(pipeline(`swipl -q $f`; stdin=devnull, stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

# the program: mme_done restores the source and typein modules after a row; mme_det runs a goal under call_cleanup and tells whether it
# left a choice point (the cleanup runs at a deterministic exit); mme_names/mme_pairs enumerate '$current_module'/2 restricted to the
# modules this file makes (every name starts with `mmx_`: swipl's library modules are not the kernel's) and sort; mme_supers collects
# import_module/2. The program uses the builtins the kernel ports (findall, msort, atom_concat, call_cleanup, ->, \+).
const _MM_PROGRAM = raw"""
mme_done :- '$set_source_module'(user), '$set_typein_module'(user).
mme_det(G, D) :- call_cleanup(G, Det = true), ( Det == true -> D = det ; D = nondet ).
mme_pre(M) :- atom_concat(mmx_, _, M).
mme_names(L) :- findall(M, ('$current_module'(M, _), mme_pre(M)), L0), msort(L0, L).
mme_pairs(L) :- findall(M-F, ('$current_module'(M, F), mme_pre(M)), L0), msort(L0, L).
mme_supers(M, L) :- findall(S, import_module(M, S), L).
"""

# UNVERIFIED on the kernel: gate decides — nothing here was run on the kernel. The rows that lean on more than MOD6's own code: mme_det
# (`call_cleanup/2` detecting determinism), `'$declare_module'` with a file (s01: the module list of a source file, `addModuleSourceFile`),
# c07 (the ORDER of a file's modules), c14 and c15 (hidden classes, a choice point after the last answer). Left out on purpose: the
# file → module mode on a file whose module was destroyed (swipl 10.1.19 does not answer it: the oracle process ends abnormally; see
# evidence/MOD6/handoff.md). The `system`-class hiding lifts in SYSTEM_MODE: that branch is exercised when the
# access-level flag is settable (a later step).
# (id, goal), run IN ORDER
const _MM_CASES = [
    (
        "s01",
        raw"'$declare_module'(mmx_f, user, user, '/mmx/f.pl', 1, false), '$declare_module'(mmx_g1, user, user, '/mmx/g.pl', 1, false), '$declare_module'(mmx_g2, user, user, '/mmx/g.pl', 5, false), '$declare_module'(mmx_s, system, user, '/mmx/s.pl', 1, false), '$declare_module'(mmx_t, temporary, user, '/mmx/t.pl', 1, false), assertz(mmx_u:p(1)), R = ok"
    ),
    (
        "i01",
        raw"mme_supers(user, L), R = L"
    ),
    (
        "i02",
        raw"mme_supers(system, L), R = L"
    ),
    (
        "i03",
        raw"mme_supers(mmx_fresh1, L), R = L"
    ),
    (
        "i04",
        raw"mme_supers(mmx_u, L), R = L"
    ),
    (
        "i05",
        raw"mme_supers(mmx_f, L), mme_supers(mmx_s, L2), mme_supers(mmx_t, L3), R = [L, L2, L3]"
    ),
    (
        "i06",
        raw"add_import_module(mmx_c2, mmx_u, start), mme_supers(mmx_c2, L), R = L"
    ),
    (
        "i07",
        raw"add_import_module(mmx_c3, mmx_f, end), add_import_module(mmx_c3, mmx_u, end), mme_supers(mmx_c3, L), R = L"
    ),
    (
        "i08",
        raw"mme_supers(mmx_c3, L), delete_import_module(mmx_c3, user), mme_supers(mmx_c3, L2), R = L-L2"
    ),
    (
        "i09",
        raw"findall(S-D, mme_det(import_module(mmx_c2, S), D), L), R = L"
    ),
    (
        "i10",
        raw"mme_det(import_module(mmx_u, S), D), R = S-D"
    ),
    (
        "i11",
        raw"( import_module(mmx_c2, mmx_u) -> A = yes ; A = no ), ( import_module(mmx_c2, user) -> B = yes ; B = no ), R = A-B"
    ),
    (
        "i12",
        raw"( import_module(mmx_u, user) -> A = yes ; A = no ), ( import_module(mmx_u, system) -> B = yes ; B = no ), R = A-B"
    ),
    (
        "i13",
        raw"catch(import_module(_, _), error(E, _), true), R = E"
    ),
    (
        "i14",
        raw"catch(import_module(1, _), error(E, _), true), R = E"
    ),
    (
        "i15",
        raw"catch(import_module(f(x), _), error(E, _), true), R = E"
    ),
    (
        "i16",
        raw"( import_module(mmx_u, 1) -> A = yes ; A = no ), ( import_module(mmx_u, f(x)) -> B = yes ; B = no ), R = A-B"
    ),
    (
        "i17",
        raw"import_module(mmx_c2, S), !, R = S"
    ),
    (
        "i18",
        raw"( forall(import_module(mmx_c2, S), atom(S)) -> R = yes ; R = no )"
    ),
    (
        "i19",
        raw"add_import_module(mmx_c4, mmx_u, start), findall(S, (import_module(mmx_c4, S), ( S == mmx_u -> add_import_module(mmx_c4, mmx_f, end) ; true )), L), R = L"
    ),
    (
        "i20",
        raw"( import_module(user, S), import_module(S, S2) -> R = S-S2 ; R = none )"
    ),
    (
        "c01",
        raw"'$current_module'(user, Fa), '$current_module'(system, Fb), R = Fa-Fb"
    ),
    (
        "c02",
        raw"'$current_module'(mmx_f, Fa), R = Fa"
    ),
    (
        "c03",
        raw"( '$current_module'(mmx_none, Fa) -> R = yes(Fa) ; R = no )"
    ),
    (
        "c04",
        raw"( '$current_module'(mmx_f, '/mmx/f.pl') -> A = yes ; A = no ), ( '$current_module'(mmx_f, '/mmx/other.pl') -> B = yes ; B = no ), ( '$current_module'(user, []) -> C = yes ; C = no ), ( '$current_module'(mmx_f, 1) -> D = yes ; D = no ), R = [A, B, C, D]"
    ),
    (
        "c05",
        raw"'$current_module'(M, '/mmx/f.pl'), R = M"
    ),
    (
        "c06",
        raw"'$current_module'(M, '/mmx/g.pl'), msort(M, S), R = S"
    ),
    (
        "c07",
        raw"( '$current_module'([mmx_g1, mmx_g2], '/mmx/g.pl') -> A = yes ; A = no ), ( '$current_module'([mmx_g2, mmx_g1], '/mmx/g.pl') -> B = yes ; B = no ), R = A-B"
    ),
    (
        "c08",
        raw"( '$current_module'(M, '/mmx/unknown.pl') -> R = yes(M) ; R = no )"
    ),
    (
        "c09",
        raw"( '$current_module'(1, _) -> A = yes ; A = no ), ( '$current_module'(f(x), _) -> B = yes ; B = no ), R = A-B"
    ),
    (
        "c10",
        raw"( '$current_module'(_, 1) -> R = yes ; R = no )"
    ),
    (
        "c11",
        raw"mme_names(L), R = L"
    ),
    (
        "c12",
        raw"mme_pairs(L), R = L"
    ),
    (
        "c13",
        raw"findall(M, ('$current_module'(M, _), ( M == system ; M == user )), L0), msort(L0, L), R = L"
    ),
    (
        "c14",
        raw"findall(M, ('$current_module'(M, _), ( M == mmx_s ; M == mmx_t )), L), '$current_module'(mmx_s, Fa), '$current_module'(mmx_t, Fb), R = L-Fa-Fb"
    ),
    (
        "c15",
        raw"findall(D, mme_det('$current_module'(_, _), D), L0), sort(L0, L), R = L"
    ),
    (
        "c16",
        raw"mme_det('$current_module'(user, _), D1), mme_det('$current_module'(_, '/mmx/f.pl'), D2), mme_det('$current_module'(_, '/mmx/g.pl'), D3), R = [D1, D2, D3]"
    ),
    (
        "c17",
        raw"'$current_module'(M, _), !, ( atom(M) -> R = ok ; R = no )"
    ),
    (
        "c18",
        raw"\+ \+ '$current_module'(_, _), \+ \+ '$current_module'(_, _), once('$current_module'(_, _)), once('$current_module'(_, _)), R = ok"
    ),
    (
        "c19",
        raw"findall(M, ('$current_module'(M, _), ( M == mmx_u ; M == mmx_f ; M == mmx_c2 )), L0), msort(L0, L), R = L"
    ),
    (
        "d01",
        raw"'$destroy_module'(mmx_t), ( '$current_module'(mmx_t, Fa) -> R = yes(Fa) ; R = no )"
    ),
    (
        "d03",
        raw"findall(M, ('$current_module'(M, _), M == mmx_t), L), R = L"
    ),
    (
        "d04",
        raw"assertz(mmx_t:q(1)), findall(M, ('$current_module'(M, _), M == mmx_t), L), '$module_property'(mmx_t, class(C)), R = L-C"
    ),
    (
        "d05",
        raw"'$declare_module'(mmx_t3, temporary, user, '/mmx/t3.pl', 1, false), mme_supers(mmx_t3, L1), '$destroy_module'(mmx_t3), mme_supers(mmx_t3, L2), ( '$current_module'(mmx_t3, Fa) -> A = Fa ; A = none ), R = [L1, L2, A]"
    )
]

"The program and cases as one file; the case predicates' names."
function _mm_file()::Tuple{String, Vector{String}}
    names = ["t_$(id)" for (id, _) in _MM_CASES]
    text =
        _MM_PROGRAM * join([
            "t_$(id)(R) :- catch(($g), error(F, _), R = raised(F)), mme_done.\n" for
            (id, g) in _MM_CASES
        ])
    f = joinpath(mktempdir(), "mm_rows.pl")
    write(f, text)
    return f, names
end

# the swipl answers: filled by evidence/MOD6/gen_rows.py --fill
const _MM_PINNED = [
    "ok",
    "t_s01 c[116,95,115,48,49]/1(a[111,107])",
    "t_i01 c[116,95,105,48,49]/1(c[91,124,93]/2(a[115,121,115,116,101,109],nil))",
    "t_i02 c[116,95,105,48,50]/1(nil)",
    "t_i03 c[116,95,105,48,51]/1(c[91,124,93]/2(a[117,115,101,114],nil))",
    "t_i04 c[116,95,105,48,52]/1(c[91,124,93]/2(a[117,115,101,114],nil))",
    "t_i05 c[116,95,105,48,53]/1(c[91,124,93]/2(c[91,124,93]/2(a[117,115,101,114],nil),c[91,124,93]/2(c[91,124,93]/2(a[117,115,101,114],nil),c[91,124,93]/2(c[91,124,93]/2(a[117,115,101,114],nil),nil))))",
    "t_i06 c[116,95,105,48,54]/1(c[91,124,93]/2(a[109,109,120,95,117],c[91,124,93]/2(a[117,115,101,114],nil)))",
    "t_i07 c[116,95,105,48,55]/1(c[91,124,93]/2(a[117,115,101,114],c[91,124,93]/2(a[109,109,120,95,102],c[91,124,93]/2(a[109,109,120,95,117],nil))))",
    "t_i08 c[116,95,105,48,56]/1(c[45]/2(c[91,124,93]/2(a[117,115,101,114],c[91,124,93]/2(a[109,109,120,95,102],c[91,124,93]/2(a[109,109,120,95,117],nil))),c[91,124,93]/2(a[109,109,120,95,102],c[91,124,93]/2(a[109,109,120,95,117],nil))))",
    "t_i09 c[116,95,105,48,57]/1(c[91,124,93]/2(c[45]/2(a[109,109,120,95,117],a[110,111,110,100,101,116]),c[91,124,93]/2(c[45]/2(a[117,115,101,114],a[100,101,116]),nil)))",
    "t_i10 c[116,95,105,49,48]/1(c[45]/2(a[117,115,101,114],a[100,101,116]))",
    "t_i11 c[116,95,105,49,49]/1(c[45]/2(a[121,101,115],a[110,111]))",
    "t_i12 c[116,95,105,49,50]/1(c[45]/2(a[121,101,115],a[110,111]))",
    "t_i13 c[116,95,105,49,51]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114])",
    "t_i14 c[116,95,105,49,52]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],i1))",
    "t_i15 c[116,95,105,49,53]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],c[102]/1(a[120])))",
    "t_i16 c[116,95,105,49,54]/1(c[45]/2(a[110,111],a[110,111]))",
    "t_i17 c[116,95,105,49,55]/1(a[109,109,120,95,117])",
    "t_i18 c[116,95,105,49,56]/1(a[121,101,115])",
    "t_i19 c[116,95,105,49,57]/1(c[91,124,93]/2(a[109,109,120,95,117],c[91,124,93]/2(a[117,115,101,114],c[91,124,93]/2(a[109,109,120,95,102],nil))))",
    "t_i20 c[116,95,105,50,48]/1(a[110,111,110,101])",
    "t_c01 c[116,95,99,48,49]/1(c[45]/2(nil,nil))",
    "t_c02 c[116,95,99,48,50]/1(a[47,109,109,120,47,102,46,112,108])",
    "t_c03 c[116,95,99,48,51]/1(a[110,111])",
    "t_c04 c[116,95,99,48,52]/1(c[91,124,93]/2(a[121,101,115],c[91,124,93]/2(a[110,111],c[91,124,93]/2(a[121,101,115],c[91,124,93]/2(a[110,111],nil)))))",
    "t_c05 c[116,95,99,48,53]/1(a[109,109,120,95,102])",
    "t_c06 c[116,95,99,48,54]/1(c[91,124,93]/2(a[109,109,120,95,103,49],c[91,124,93]/2(a[109,109,120,95,103,50],nil)))",
    "t_c07 c[116,95,99,48,55]/1(c[45]/2(a[121,101,115],a[110,111]))",
    "t_c08 c[116,95,99,48,56]/1(a[110,111])",
    "t_c09 c[116,95,99,48,57]/1(c[45]/2(a[110,111],a[110,111]))",
    "t_c10 c[116,95,99,49,48]/1(a[110,111])",
    "t_c11 c[116,95,99,49,49]/1(c[91,124,93]/2(a[109,109,120,95,99,50],c[91,124,93]/2(a[109,109,120,95,99,51],c[91,124,93]/2(a[109,109,120,95,99,52],c[91,124,93]/2(a[109,109,120,95,102],c[91,124,93]/2(a[109,109,120,95,102,114,101,115,104,49],c[91,124,93]/2(a[109,109,120,95,103,49],c[91,124,93]/2(a[109,109,120,95,103,50],c[91,124,93]/2(a[109,109,120,95,117],nil)))))))))",
    "t_c12 c[116,95,99,49,50]/1(c[91,124,93]/2(c[45]/2(a[109,109,120,95,99,50],nil),c[91,124,93]/2(c[45]/2(a[109,109,120,95,99,51],nil),c[91,124,93]/2(c[45]/2(a[109,109,120,95,99,52],nil),c[91,124,93]/2(c[45]/2(a[109,109,120,95,102],a[47,109,109,120,47,102,46,112,108]),c[91,124,93]/2(c[45]/2(a[109,109,120,95,102,114,101,115,104,49],nil),c[91,124,93]/2(c[45]/2(a[109,109,120,95,103,49],a[47,109,109,120,47,103,46,112,108]),c[91,124,93]/2(c[45]/2(a[109,109,120,95,103,50],a[47,109,109,120,47,103,46,112,108]),c[91,124,93]/2(c[45]/2(a[109,109,120,95,117],nil),nil)))))))))",
    "t_c13 c[116,95,99,49,51]/1(c[91,124,93]/2(a[115,121,115,116,101,109],c[91,124,93]/2(a[117,115,101,114],nil)))",
    "t_c14 c[116,95,99,49,52]/1(c[45]/2(c[45]/2(nil,a[47,109,109,120,47,115,46,112,108]),a[47,109,109,120,47,116,46,112,108]))",
    "t_c15 c[116,95,99,49,53]/1(c[91,124,93]/2(a[110,111,110,100,101,116],nil))",
    "t_c16 c[116,95,99,49,54]/1(c[91,124,93]/2(a[100,101,116],c[91,124,93]/2(a[100,101,116],c[91,124,93]/2(a[100,101,116],nil))))",
    "t_c17 c[116,95,99,49,55]/1(a[111,107])",
    "t_c18 c[116,95,99,49,56]/1(a[111,107])",
    "t_c19 c[116,95,99,49,57]/1(c[91,124,93]/2(a[109,109,120,95,99,50],c[91,124,93]/2(a[109,109,120,95,102],c[91,124,93]/2(a[109,109,120,95,117],nil))))",
    "t_d01 c[116,95,100,48,49]/1(a[110,111])",
    "t_d03 c[116,95,100,48,51]/1(nil)",
    "t_d04 c[116,95,100,48,52]/1(c[45]/2(c[91,124,93]/2(a[109,109,120,95,116],nil),a[117,115,101,114]))",
    "t_d05 c[116,95,100,48,53]/1(c[91,124,93]/2(c[91,124,93]/2(a[117,115,101,114],nil),c[91,124,93]/2(c[91,124,93]/2(a[117,115,101,114],nil),c[91,124,93]/2(nil,nil))))"
]

"The kernel's lines for `names` after consulting `path`, as the driver writes swipl's, and the pool's live count after each row."
function _mm_kernel(path::String, names::Vector{String})
    gd = LK.PL_global_data{_MM}()
    ld = LK.PL_local_data{_MM}(gd)
    st, ball, _ = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * _mm_enc(ball::_MM)]
    lives = Int[]
    for name in names
        proc = LK.isCurrentProcedure(sym_key(_mms(name)), 1, LK.MODULE_user(gd))
        if proc === nothing || !LK.isDefinedProcedure(gd, proc)
            push!(out, "$name undefined")
            push!(lives, LK.live_states(ld))
            continue
        end
        sols = String[]
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 1)
        LK.putSlotValue!(ld, a + 1, mk_var(_MM, LK.fresh_var_keys!(1)), LK.PutVarMap())
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
        )
        n = 0
        while (n += 1) <= 50
            rc = LK.PL_next_solution(gd, ld, qid)
            if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
                push!(
                    sols,
                    _mm_enc(mk_expr(_MM, _MM[_mms(name), lk_answers(ld, (a:a)...)...]))
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
        push!(lives, LK.live_states(ld))
    end
    return out, lives, gd, ld
end

@testset "the module enumerations as swipl's (MOD6 rows)" begin
    f, names = _mm_file()
    kl, lives, _, _ = _mm_kernel(f, names)
    @test length(kl) == length(_MM_PINNED)
    for (k, p) in zip(kl, _MM_PINNED)
        k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
        @test k == p
    end
    @test length(lives) == length(_MM_CASES)
    @test all(==(0), lives)                      # every state went back to the pool (FRG_CUTTED, the last answer, a failure)
end

@testset "the pins hold both kinds of answer (non-vacuity)" begin
    # the comparison can pass and can fail: answers, errors, failures and the lists of modules are all pinned
    @test length(_MM_PINNED) == length(_MM_CASES) + 1
    @test _MM_PINNED[1] == "ok"
    @test any(
        l ->
            startswith(l, "t_i13 ") && occursin(
                "a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]",
                l
            ),
        _MM_PINNED
    )   # instantiation_error
    @test count(
        l -> occursin("c[116,121,112,101,95,101,114,114,111,114]", l), _MM_PINNED
    ) >= 2   # type_error
    @test count(l -> occursin("c[91,124,93]/2(", l), _MM_PINNED) >= 12                  # lists of modules
    @test count(l -> occursin("c[45]/2(", l), _MM_PINNED) >= 8                         # X-Y answers
    @test count(l -> !occursin(" ", l), _MM_PINNED) == 1                                # only "ok" has no answer; no row fails
    @test count(l -> occursin("a[110,111,110,100,101,116]", l), _MM_PINNED) >= 1        # `nondet` answered: a choice point is pinned
    @test any(
        l -> startswith(l, "t_c11 ") && occursin("a[109,109,120,95,102]", l), _MM_PINNED
    )   # the enumeration lists mmx_f
end

@testset "a cut, a closed query and an exhausted enumeration free the state (FRG_CUTTED)" begin
    # kernel-side; UNVERIFIED on the kernel: gate decides. A query over '$current_module'/2 whose first answer is taken holds ONE state
    # (the choice point's REDO_PTR context); closing the query (the cut of the frame) gives it back; so does every other way out.
    f = joinpath(mktempdir(), "mm_cut.pl")
    write(
        f,
        "mm_enum(M, F) :- '\$current_module'(M, F).\n" *
        "mm_cut(R) :- '\$current_module'(_, _), !, R = ok.\n" *
        "mm_all(N) :- findall(x, '\$current_module'(_, _), L), msort(L, S), S = [_|_], N = ok.\n"
    )
    gd = LK.PL_global_data{_MM}()
    ld = LK.PL_local_data{_MM}(gd)
    st, _, _ = LK.load_file!(gd, ld, f)
    @test st === :ok
    @test LK.live_states(ld) == 0
    proc = LK.isCurrentProcedure(sym_key(_mms("mm_enum")), 2, LK.MODULE_user(gd))
    @test proc !== nothing
    for _ in 1:5
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 2)
        pvm = LK.PutVarMap()
        LK.putSlotValue!(ld, a + 1, mk_var(_MM, LK.fresh_var_keys!(1)), pvm)
        LK.putSlotValue!(ld, a + 2, mk_var(_MM, LK.fresh_var_keys!(1)), pvm)
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
        )
        rc = LK.PL_next_solution(gd, ld, qid)
        @test rc == LK.PL_S_TRUE                  # (PL_S_TRUE: swipl keeps the redo after the last answer too)
        @test LK.live_states(ld) == 1
        @test ld.module_enums.live == 1
        LK.PL_close_query(ld, qid)
        LK.PL_close_foreign_frame(ld, fid)
        @test LK.live_states(ld) == 0
    end
    # the pool keeps its record: the states of the five queries were ONE record, freed and reused
    @test length(ld.module_enums.states) == 1
    for (name, ar) in (("mm_cut", 1), ("mm_all", 1))
        p = LK.isCurrentProcedure(sym_key(_mms(name)), ar, LK.MODULE_user(gd))
        @test p !== nothing
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 1)
        LK.putSlotValue!(ld, a + 1, mk_var(_MM, LK.fresh_var_keys!(1)), LK.PutVarMap())
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, p, a
        )
        rc = LK.PL_next_solution(gd, ld, qid)
        @test rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
        LK.PL_close_query(ld, qid)
        LK.PL_close_foreign_frame(ld, fid)
        @test LK.live_states(ld) == 0
    end
    @test length(ld.module_enums.states) == 1
end

@testset "the enumeration skips a destroyed module's record, not the new one of its name (H3)" begin
    # kernel-side: the vector keeps the destroyed record (src/pl-incl.jl `module_table`), the walk (`advanceModuleEnum`) lists what the
    # name index maps to. UNVERIFIED on the kernel: gate decides.
    f, names = _mm_file()
    _, _, gd, ld = _mm_kernel(f, names)
    ms = [m for m in gd.modules if m.name == sym_key(_mms("mmx_t"))]
    @test length(ms) == 2                         # d01 destroyed the first, d04 made a user module of the name
    old, new = ms
    @test (old.flags & LK.M_DESTROYED) != 0 && (new.flags & LK.M_DESTROYED) == 0
    en = LK.module_enum()
    seen = Int[]
    while (m = LK.advanceModuleEnum(gd, ld, en)) !== nothing
        push!(seen, m.index)
    end
    @test old.index ∉ seen && new.index in seen
    @test allunique(seen)
    @test LK.MODULE_user(gd).index in seen && LK.MODULE_system(gd).index in seen
    t3 = [m for m in gd.modules if m.name == sym_key(_mms("mmx_t3"))]     # d05: destroyed, then made again by import_module/2
    @test length(t3) == 2 && (t3[1].flags & LK.M_DESTROYED) != 0 && t3[2].index ∈ seen
    @test t3[1].index ∉ seen
    # a temporary module is listed only with MENUM_TEMP, and then referenced, the reference released when the enumeration moves on
    t4 = LK.lookupModule(gd, _mms("mmx_tt"))
    t4.class = _mms("temporary")
    r0 = t4.references
    en2 = LK.module_enum()
    en2.flags = Int(LK.MENUM_TEMP)
    found = false
    while (m = LK.advanceModuleEnum(gd, ld, en2)) !== nothing
        m === t4 && (found=true; @test t4.references == r0 + 1 && en2.current == t4.index)
    end
    @test found
    @test t4.references == r0 + 1                 # still held by the enumeration (`current`), which is the last temporary one
    k = LK.newModuleEnum(ld, Int(LK.MENUM_TEMP))
    @test ld.module_enums.live == 1 && ld.module_enums.states[k].flags == Int(LK.MENUM_TEMP)
    LK.freeModuleEnum(gd, ld, k)
    @test ld.module_enums.live == 0
    @test sym_key(t4.class) == sym_key(_mms("temporary"))
end

@testset "the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "MOD6 LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        f, names = _mm_file()
        @test _mm_swipl_lines(f, names) == _MM_PINNED
    end
end
