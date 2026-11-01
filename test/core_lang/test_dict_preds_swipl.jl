# ORIGINAL: a LIVE differential of BOOTPRED-dict against swipl at the pin (pl-dict.c) — DICT's rows
# test/core_lang/test_dict_preds_swipl.jl — the pl-dict.c predicates written for R2b (D-0290; the wip/dict stack): $get_dict_ex/3,
# get_dict/5, put_dict/4, dict_pairs/3, del_dict/4, :</2, >:</2, dict_same_keys/2 and $get_dict_kv/4,6,8 (dp01-dp164) against swipl 10.1.19:
#   * A PROGRAM consulted by the kernel's loader and cases `t_<id>(R)` run in order in one database, each wrapped in
#     `catch(Goal, error(SsuE, _), R = raised(SsuE))`; the driver and the term encoder are test_bootpred_swipl.jl's (one extractor, both sides).
#   * Every answer line is swipl's, PINNED (swipl 10.1.19-1-gcbf4e189, evidence/DICT/dict_rows.out in the wip/dict branch, two byte-identical
#     runs); with `swipl` on PATH the live answers are compared with the pins too.
#   * UNVERIFIED on the kernel (nothing was compiled when these rows were written): every kernel answer; the gate decides.
#   * Dicts are built by dict_create/3 and put_dict/3 only (the reader refuses dicts, the writer has no dict arm) and never appear in an
#     answer: a row observes a dict through dict_pairs/3, `dpairs/2` (get_dict/3 findall, msort) or a single lookup.
#   * b_set_dict/3, nb_set_dict/3 and nb_link_dict/3 are left to the SETARG follow-up, which adds their rows.
# dp01-dp12: $get_dict_ex/3
# dp13-dp30: get_dict/5
# dp31-dp49: put_dict/4
# dp50-dp81: dict_pairs/3
# dp82-dp97: del_dict/4
# dp98-dp127: :</2 and >:</2
# dp128-dp143: dict_same_keys/2
# dp144-dp164: $get_dict_kv/4,6,8
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — the predicates ride the term layer through the dict cells and callProlog; every type in CI
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _DP = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_dps(x) = lk_sym(_DP, Symbol(x))

_dp_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _dp_enc(t::_DP, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _dp_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _dp_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _dp_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_dp_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

# the swipl side: test/core_lang/test_ssu_swipl.jl's driver (consult, then every answer of each t_<id>/1, `enc`oded)
const _DP_DRIVER = raw"""
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
function _dp_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _DP_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(pipeline(`swipl -q $f`; stdin=devnull, stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end


# the program: dpairs/2 observes a dict, dp_mem/2 stands for member/2 (library(lists) is not loaded by the kernel yet; LB4)
const _DP_PROGRAM = raw"""
dpairs(D, Ps) :- findall(K-V, get_dict(K, D, V), Ps0), msort(Ps0, Ps).
dp_mem(X, [X|_]).
dp_mem(X, [_|T]) :- dp_mem(X, T).
"""

const _DP_CASES = [
    ("dp01", raw"dict_create(D, t, [a-1, b-2]), '$get_dict_ex'(a, D, V), R = V"),
    ("dp02", raw"dict_create(D, t, [a-1, b-2]), '$get_dict_ex'(b, D, V), R = V"),
    ("dp03", raw"dict_create(D, t, [a-1, b-2]), catch('$get_dict_ex'(c, D, _), error(existence_error(T, K, _), _), R = ex(T, K))"),
    ("dp04", raw"'$get_dict_ex'(a, foo, V), R = V"),
    ("dp05", raw"'$get_dict_ex'(a, _, V), R = V"),
    ("dp06", raw"dict_create(D, t, [a-1, b-2, c-3]), findall(K-V, '$get_dict_ex'(K, D, V), L), msort(L, R)"),
    ("dp07", raw"dict_create(D, t, [a-1, b-2]), '$get_dict_ex'(1.5, D, V), R = V"),
    ("dp08", raw"dict_create(D, t, [a-1, b-2]), '$get_dict_ex'(a, D, 2), R = yes"),
    ("dp09", raw"dict_create(D, t, [1-one]), '$get_dict_ex'(1, D, V), R = V"),
    ("dp10", raw"dict_create(D, t, [a-1, b-2, c-3]), findall(K, '$get_dict_ex'(K, D, 2), R)"),
    ("dp11", raw"dict_create(D, t, []), findall(K, '$get_dict_ex'(K, D, _), R)"),
    ("dp12", raw"dict_create(D, t, [a-1]), findall(V, '$get_dict_ex'(a, D, V), R)"),
    ("dp13", raw"dict_create(D, t, [a-1, b-2]), get_dict(a, D, V, N, 9), dpairs(N, P), R = V-P"),
    ("dp14", raw"dict_create(D, t, [a-1, b-2]), get_dict(b, D, V, N, 9), dpairs(N, P), R = V-P"),
    ("dp15", raw"dict_create(D, t, [a-1, b-2]), get_dict(c, D, V, N, 9), R = V-N"),
    ("dp16", raw"dict_create(D, t, [a-1, b-2]), get_dict(a, D, 2, N, 9), R = N"),
    ("dp17", raw"dict_create(D, t, [a-1]), get_dict(1.5, D, V, N, 9), R = V-N"),
    ("dp18", raw"dict_create(D, t, [a-1]), get_dict(_, D, V, N, 9), R = V-N"),
    ("dp19", raw"get_dict(a, foo, V, N, 9), R = V-N"),
    ("dp20", raw"get_dict(a, [a-1, b-2], V, N, 9), dpairs(N, P), R = V-P"),
    ("dp21", raw"dict_create(D, t, [a-1]), get_dict(a, D, _, N, X), get_dict(a, N, Y), Y == X, R = yes"),
    ("dp22", raw"dict_create(D, t, [a-1]), get_dict(a, D, V, N, 9), get_dict(a, N, Y), dpairs(D, P0), R = V-Y-P0"),
    ("dp23", raw"dict_create(D, t, [a-1]), get_dict(a, D, 1, N, 1), dpairs(N, P), R = P"),
    ("dp24", raw"dict_create(D, t, [a-X, b-Y]), get_dict(a, D, 5, N, Z), dpairs(N, P), R = X-Y-P-Z"),
    ("dp25", raw"dict_create(D, t, [a-1]), get_dict(a, D, _, N, f(Q)), get_dict(a, N, f(7)), R = Q"),
    ("dp26", raw"dict_create(D, t, [a-1, b-2]), get_dict(a, D, _, N, 9), is_dict(N, T), R = T"),
    ("dp27", raw"dict_create(D, t, [a-1]), get_dict(f(x), D, V, N, 9), R = V-N"),
    ("dp28", raw"dict_create(D, t, [1-a, 2-b]), get_dict(2, D, V, N, z), dpairs(N, P), R = V-P"),
    ("dp29", raw"dict_create(D, t, [a-1]), get_dict(a, D, V, foo, 9), R = V"),
    ("dp30", raw"dict_create(D, t, [a-1, b-2, c-3]), get_dict(b, D, _, N, new), dict_pairs(N, T, P), R = T-P"),
    ("dp31", raw"dict_create(D, t, [a-1]), put_dict(b, D, 2, N), dpairs(N, R)"),
    ("dp32", raw"dict_create(D, t, [a-1, b-2]), put_dict(a, D, 9, N), dpairs(N, R)"),
    ("dp33", raw"dict_create(D, t, []), put_dict(a, D, 1, N), dpairs(N, R)"),
    ("dp34", raw"put_dict(c, [a-1, b-2], 3, N), dpairs(N, R)"),
    ("dp35", raw"dict_create(D, t, [a-1]), put_dict(1.5, D, x, N), R = N"),
    ("dp36", raw"dict_create(D, t, [a-1]), put_dict(_, D, x, N), R = N"),
    ("dp37", raw"put_dict(a, foo, x, N), R = N"),
    ("dp38", raw"put_dict(a, _, x, N), R = N"),
    ("dp39", raw"dict_create(D, t, [a-1]), put_dict(a, D, 1, N), dpairs(N, R)"),
    ("dp40", raw"dict_create(D, t, [a-1]), put_dict(b, D, X, N), get_dict(b, N, Y), X = 5, R = Y"),
    ("dp41", raw"dict_create(D, t, [a-1]), put_dict(b, D, 2, _), dpairs(D, R)"),
    ("dp42", raw"dict_create(D, t, [b-1, d-1]), put_dict(c, D, 2, N), put_dict(a, N, 3, M), put_dict(e, M, 4, Q), dpairs(Q, R)"),
    ("dp43", raw"dict_create(D, t, [a-1]), put_dict(b, D, 2, N), is_dict(N, T), R = T"),
    ("dp44", raw"dict_create(D, t, [a-1]), put_dict(b, D, 2, N), put_dict(b, D, 2, N2), N == N2, R = same"),
    ("dp45", raw"dict_create(D, t, [1-a]), put_dict(2, D, b, N), put_dict(c, N, x, M), dpairs(M, R)"),
    ("dp46", raw"dict_create(D, t, [a-1]), put_dict(b, D, 2, N), put_dict(b, N, 3, M), dpairs(M, R)"),
    ("dp47", raw"dict_create(D, T, [a-1]), put_dict(b, D, 2, N), is_dict(N, T2), T2 == T, R = yes"),
    ("dp48", raw"dict_create(D, t, [a-1]), put_dict(a, D, 2, N), get_dict(a, D, V), get_dict(a, N, W), R = V-W"),
    ("dp49", raw"dict_create(D, t, [a-1]), put_dict(b, D, 2, foo), R = yes"),
    ("dp50", raw"dict_create(D, t, [b-2, a-1, c-3]), dict_pairs(D, T, P), R = T-P"),
    ("dp51", raw"dict_create(D, t, [b-1, 2-x, a-3, 1-y]), dict_pairs(D, _, P), R = P"),
    ("dp52", raw"dict_create(D, t, []), dict_pairs(D, T, P), R = T-P"),
    ("dp53", raw"dict_pairs(D, t, [a-1, b-2]), dpairs(D, R)"),
    ("dp54", raw"dict_pairs(D, t, [b-2, a-1]), dict_pairs(D, T, P), R = T-P"),
    ("dp55", raw"dict_pairs(D, T, [a-1]), is_dict(D, T2), T2 == T, R = yes"),
    ("dp56", raw"dict_pairs(D, t, []), is_dict(D, T), R = T"),
    ("dp57", raw"dict_pairs(D, t, [a-1, a-2]), R = D"),
    ("dp58", raw"dict_pairs(D, t, [a=1]), R = D"),
    ("dp59", raw"dict_pairs(D, t, [a:1]), R = D"),
    ("dp60", raw"dict_pairs(D, t, [a(1)]), R = D"),
    ("dp61", raw"dict_pairs(D, t, foo), R = D"),
    ("dp62", raw"dict_pairs(D, t, _), R = D"),
    ("dp63", raw"dict_pairs(D, t, [a-1|_]), R = D"),
    ("dp64", raw"dict_pairs(D, t, [1.5-a]), R = D"),
    ("dp65", raw"dict_pairs(foo, T, P), R = T-P"),
    ("dp66", raw"dict_pairs(_, _, _), R = yes"),
    ("dp67", raw"dict_create(D, t, [a-1]), dict_pairs(D, u, P), R = P"),
    ("dp68", raw"dict_create(D, t, [a-1]), dict_pairs(D, t, [a-1]), R = yes"),
    ("dp69", raw"dict_create(D, t, [a-1]), dict_pairs(D, t, [b-1]), R = yes"),
    ("dp70", raw"dict_create(D, t, [a-1, b-2]), dict_pairs(D, t, [a-X, b-Y]), R = X-Y"),
    ("dp71", raw"dict_create(D, t, [a-1, b-2]), dict_pairs(D, t, [a-1]), R = yes"),
    ("dp72", raw"dict_create(D, t, [a-1]), dict_pairs(D, t, [a-1, b-2]), R = yes"),
    ("dp73", raw"dict_create(D, t, [a-1]), dict_pairs(D, t, foo), R = yes"),
    ("dp74", raw"dict_create(D, t, [a-f(X), b-X, c-1.5]), dict_pairs(D, _, P), R = P"),
    ("dp75", raw"dict_create(D, t, [a-1, b-2]), dict_pairs(D, t, P), findall(x, dict_pairs(D, t, _), L), R = P-L"),
    ("dp76", raw"dict_create(D, t, [a-1]), dict_pairs(D, T, P), P = [K-V], R = K-V-T"),
    ("dp77", raw"dict_pairs([a-1, b-2], T, P), R = T-P"),
    ("dp78", raw"dict_pairs(D, t, [a-X]), dict_pairs(D, t, [a-1]), R = X"),
    ("dp79", raw"dict_create(D, t, [a-1]), dict_pairs(D, t, [a-1|T]), R = T"),
    ("dp80", raw"dict_pairs(D, t, [h-8, g-7, f-6, e-5, d-4, c-3, b-2, a-1]), dict_pairs(D, _, P), R = P"),
    ("dp81", raw"dict_pairs(D, t, [x-1, 5-a, y-2, 3-b]), dict_pairs(D, _, P), R = P"),
    ("dp82", raw"dict_create(D, t, [a-1, b-2]), del_dict(a, D, V, N), dpairs(N, P), R = V-P"),
    ("dp83", raw"dict_create(D, t, [a-1, b-2]), del_dict(b, D, V, N), dpairs(N, P), R = V-P"),
    ("dp84", raw"dict_create(D, t, [a-1, b-2]), del_dict(c, D, V, N), R = V-N"),
    ("dp85", raw"dict_create(D, t, [a-1, b-2]), del_dict(a, D, 2, N), R = N"),
    ("dp86", raw"dict_create(D, t, [a-1]), del_dict(1.5, D, V, N), R = V-N"),
    ("dp87", raw"dict_create(D, t, [a-1]), del_dict(_, D, V, N), R = V-N"),
    ("dp88", raw"del_dict(a, foo, V, N), R = V-N"),
    ("dp89", raw"dict_create(D, t, [a-1]), del_dict(a, D, V, N), dict_pairs(N, T, P), R = V-T-P"),
    ("dp90", raw"del_dict(a, [a-1, b-2], V, N), dpairs(N, P), R = V-P"),
    ("dp91", raw"dict_create(D, t, [a-X, b-Y]), del_dict(a, D, 5, _), R = X-Y"),
    ("dp92", raw"dict_create(D, t, [a-1, b-2, c-3]), del_dict(b, D, _, N), dpairs(D, P0), dpairs(N, P), R = P0-P"),
    ("dp93", raw"dict_create(D, T, [a-1, b-2]), del_dict(a, D, _, N), is_dict(N, T2), T2 == T, R = yes"),
    ("dp94", raw"dict_create(D, t, [1-x, a-y]), del_dict(1, D, V, N), dpairs(N, P), R = V-P"),
    ("dp95", raw"dict_create(D, t, [a-f(Z)]), del_dict(a, D, f(3), _), R = Z"),
    ("dp96", raw"dict_create(D, t, [a-1]), del_dict(a, D, _, foo), R = yes"),
    ("dp97", raw"dict_create(D, t, [a-1, b-2]), del_dict(a, D, V, N), del_dict(b, N, W, M), dict_pairs(M, T, P), R = V-W-T-P"),
    ("dp98", raw"dict_create(S, _, [a-X]), dict_create(F, t, [a-1, b-2]), ':<'(S, F), R = X"),
    ("dp99", raw"dict_create(S, s, [a-1]), dict_create(F, t, [a-1, b-2]), ':<'(S, F), R = yes"),
    ("dp100", raw"dict_create(S, _, [a-1, c-3]), dict_create(F, t, [a-1, b-2]), ':<'(S, F), R = yes"),
    ("dp101", raw"dict_create(S, _, [a-2]), dict_create(F, t, [a-1, b-2]), ':<'(S, F), R = yes"),
    ("dp102", raw"dict_create(S, T, [a-1]), dict_create(F, t, [a-1, b-2]), ':<'(S, F), R = T"),
    ("dp103", raw"dict_create(S, _, []), dict_create(F, t, [a-1]), ':<'(S, F), R = yes"),
    ("dp104", raw"dict_create(S, _, [a-1]), dict_create(F, t, []), ':<'(S, F), R = yes"),
    ("dp105", raw"dict_create(F, t, [a-1, b-2, c-3]), ':<'([b-X], F), R = X"),
    ("dp106", raw"dict_create(F, t, [a-1]), ':<'(foo, F), R = yes"),
    ("dp107", raw"dict_create(S, _, [a-1]), ':<'(S, foo), R = yes"),
    ("dp108", raw"dict_create(F, t, [a-1]), ':<'(_, F), R = yes"),
    ("dp109", raw"dict_create(S, _, [a-X, b-Y]), dict_create(F, t, [a-1, b-2]), ':<'(S, F), R = X-Y"),
    ("dp110", raw"':<'([a-X], [a-1, b-2]), R = X"),
    ("dp111", raw"dict_create(S, _, [b-1, d-2]), dict_create(F, t, [a-0, b-1, c-0, d-2, e-0]), ':<'(S, F), R = yes"),
    ("dp112", raw"dict_create(S, _, [b-1, z-2]), dict_create(F, t, [a-0, b-1, c-0, d-2, e-0]), ':<'(S, F), R = yes"),
    ("dp113", raw"dict_create(S, _, [a-X]), dict_create(F, t, [a-f(Y)]), ':<'(S, F), R = X-Y"),
    ("dp114", raw"dict_create(A, t, [a-X, b-2]), dict_create(B, t, [b-2, c-Y]), '>:<'(A, B), R = X-Y"),
    ("dp115", raw"dict_create(A, t, [a-1]), dict_create(B, t, [a-2]), '>:<'(A, B), R = yes"),
    ("dp116", raw"dict_create(A, t, [a-1]), dict_create(B, t, [b-2]), '>:<'(A, B), R = yes"),
    ("dp117", raw"dict_create(A, t, [a-1]), dict_create(B, u, [a-1]), '>:<'(A, B), R = yes"),
    ("dp118", raw"dict_create(A, T, [a-1]), dict_create(B, u, [b-2]), '>:<'(A, B), R = T"),
    ("dp119", raw"dict_create(A, t, [a-X]), dict_create(B, t, [a-1]), '>:<'(A, B), R = X"),
    ("dp120", raw"dict_create(A, t, []), dict_create(B, t, []), '>:<'(A, B), R = yes"),
    ("dp121", raw"dict_create(B, t, [a-1]), '>:<'(foo, B), R = yes"),
    ("dp122", raw"dict_create(A, t, [a-1]), '>:<'(A, foo), R = yes"),
    ("dp123", raw"dict_create(B, t, [a-1]), '>:<'(_, B), R = yes"),
    ("dp124", raw"'>:<'([a-X], [a-1, b-2]), R = X"),
    ("dp125", raw"dict_create(A, t, [a-X, b-Y]), dict_create(B, t, [a-Y, b-3]), '>:<'(A, B), R = X-Y"),
    ("dp126", raw"dict_create(A, t, [a-1, b-2, c-3]), dict_create(B, t, [a-1, c-4]), '>:<'(A, B), R = yes"),
    ("dp127", raw"dict_create(A, t, [a-1, c-3]), dict_create(B, t, [a-1, b-2, c-3, d-4]), '>:<'(A, B), R = yes"),
    ("dp128", raw"dict_create(A, t, [a-1, b-2]), dict_create(B, u, [b-9, a-8]), dict_same_keys(A, B), R = yes"),
    ("dp129", raw"dict_create(A, t, [a-1, b-2]), dict_create(B, t, [a-1, c-2]), dict_same_keys(A, B), R = yes"),
    ("dp130", raw"dict_create(A, t, [a-1, b-2]), dict_create(B, t, [a-1]), dict_same_keys(A, B), R = yes"),
    ("dp131", raw"dict_create(A, t, [a-1, b-2]), dict_same_keys(A, B), dict_pairs(B, T, P), R = T-P"),
    ("dp132", raw"dict_create(A, t, [a-1, b-2]), dict_same_keys(B, A), dict_pairs(B, T, P), R = T-P"),
    ("dp133", raw"dict_same_keys(_, _), R = yes"),
    ("dp134", raw"dict_create(A, t, [a-1]), dict_same_keys(A, foo), R = yes"),
    ("dp135", raw"dict_create(A, t, [a-1]), dict_same_keys(foo, A), R = yes"),
    ("dp136", raw"dict_same_keys(foo, bar), R = yes"),
    ("dp137", raw"dict_create(A, t, []), dict_same_keys(A, B), dict_pairs(B, T, P), R = T-P"),
    ("dp138", raw"dict_create(A, t, [a-1]), dict_same_keys(A, B), dict_same_keys(A, B), R = yes"),
    ("dp139", raw"dict_create(A, t, [a-1]), dict_same_keys(A, B), dict_pairs(B, _, [_-V]), V = 7, dpairs(A, R)"),
    ("dp140", raw"dict_same_keys([a-1], _), R = yes"),
    ("dp141", raw"dict_create(A, t, [a-1, b-2, c-3, d-4]), dict_same_keys(A, B), dict_pairs(B, _, P), length(P, R)"),
    ("dp142", raw"dict_create(A, t, [a-1]), dict_same_keys(A, [a-1]), R = yes"),
    ("dp143", raw"dict_create(A, t, [a-1, b-2]), dict_same_keys(A, B), dict_pairs(B, _, [K1-V1, K2-V2]), R = K1-K2-(V1 == V2)"),
    ("dp144", raw"dict_create(D, t, [a-1, b-2, c-3]), findall(K-V, (dp_mem(I, [1, 2, 3]), '$get_dict_kv'(I, D, K, V)), L), msort(L, R)"),
    ("dp145", raw"dict_create(D, t, [a-1, b-2, c-3]), '$get_dict_kv'(0, D, K, V), R = K-V"),
    ("dp146", raw"dict_create(D, t, [a-1, b-2, c-3]), '$get_dict_kv'(4, D, K, V), R = K-V"),
    ("dp147", raw"dict_create(D, t, [a-1]), '$get_dict_kv'(-1, D, K, V), R = K-V"),
    ("dp148", raw"dict_create(D, t, [a-1]), '$get_dict_kv'(_, D, K, V), R = K-V"),
    ("dp149", raw"dict_create(D, t, [a-1]), '$get_dict_kv'(a, D, K, V), R = K-V"),
    ("dp150", raw"'$get_dict_kv'(1, foo, K, V), R = K-V"),
    ("dp151", raw"'$get_dict_kv'(1, _, K, V), R = K-V"),
    ("dp152", raw"dict_create(D, t, [a-1]), '$get_dict_kv'(1, D, a, V), R = V"),
    ("dp153", raw"dict_create(D, t, [a-1]), '$get_dict_kv'(1, D, b, V), R = V"),
    ("dp154", raw"dict_create(D, t, [a-1]), '$get_dict_kv'(1, D, K, 2), R = K"),
    ("dp155", raw"dict_create(D, t, []), '$get_dict_kv'(1, D, K, V), R = K-V"),
    ("dp156", raw"dict_create(D, t, [a-1, b-2]), dict_create(E, u, [a-x, b-y]), findall(K-V1-V2, (dp_mem(I, [1, 2]), '$get_dict_kv'(I, D, E, K, V1, V2)), L), msort(L, R)"),
    ("dp157", raw"dict_create(D, t, [a-1, b-2]), dict_create(E, u, [c-x, d-y]), catch('$get_dict_kv'(1, D, E, K, V1, V2), error(domain_error(T, _), _), R = d(T)), R \== K-V1-V2"),
    ("dp158", raw"dict_create(D, t, [a-1, b-2]), dict_create(E, u, [a-x]), catch('$get_dict_kv'(1, D, E, K, V1, V2), error(domain_error(T, _), _), R = d(T)), R \== K-V1-V2"),
    ("dp159", raw"dict_create(D, t, [a-1, b-2]), '$get_dict_kv'(1, D, foo, K, V1, V2), R = K-V1-V2"),
    ("dp160", raw"dict_create(D, t, [a-1, b-2]), '$get_dict_kv'(1, D, _, K, V1, V2), R = K-V1-V2"),
    ("dp161", raw"dict_create(D, t, [a-1, b-2]), dict_create(E, u, [a-x, b-y]), dict_create(F, v, [a-p, b-q]), findall(K-V1-V2-V3, (dp_mem(I, [1, 2]), '$get_dict_kv'(I, D, E, F, K, V1, V2, V3)), L), msort(L, R)"),
    ("dp162", raw"dict_create(D, t, [a-1, b-2]), dict_create(E, u, [a-x, b-y]), dict_create(F, v, [c-p, d-q]), catch('$get_dict_kv'(1, D, E, F, K, V1, V2, V3), error(domain_error(T, _), _), R = d(T)), R \== K-V1-V2-V3"),
    ("dp163", raw"dict_create(D, t, [a-1, b-2]), '$get_dict_kv'(3, D, D, K, V1, V2), R = K-V1-V2"),
    ("dp164", raw"dict_create(D, t, [a-1, b-2]), '$get_dict_kv'(1, D, D, K, V1, V1), R = K-V1")
]

# swipl 10.1.19-1-gcbf4e189's answers to the program and cases above (the driver's lines; evidence/DICT/dict_rows.out in the wip/dict branch)
const _DP_PINNED = [
    "ok",
    "t_dp01 c[116,95,100,112,48,49]/1(i1)",
    "t_dp02 c[116,95,100,112,48,50]/1(i2)",
    "t_dp03 c[116,95,100,112,48,51]/1(c[101,120]/2(a[107,101,121],a[99]))",
    "t_dp04",
    "t_dp05",
    "t_dp06 c[116,95,100,112,48,54]/1(c[91,124,93]/2(c[45]/2(a[97],i1),c[91,124,93]/2(c[45]/2(a[98],i2),c[91,124,93]/2(c[45]/2(a[99],i3),nil))))",
    "t_dp07",
    "t_dp08",
    "t_dp09 c[116,95,100,112,48,57]/1(a[111,110,101])",
    "t_dp10 c[116,95,100,112,49,48]/1(c[91,124,93]/2(a[98],nil))",
    "t_dp11 c[116,95,100,112,49,49]/1(nil)",
    "t_dp12 c[116,95,100,112,49,50]/1(c[91,124,93]/2(i1,nil))",
    "t_dp13 c[116,95,100,112,49,51]/1(c[45]/2(i1,c[91,124,93]/2(c[45]/2(a[97],i9),c[91,124,93]/2(c[45]/2(a[98],i2),nil))))",
    "t_dp14 c[116,95,100,112,49,52]/1(c[45]/2(i2,c[91,124,93]/2(c[45]/2(a[97],i1),c[91,124,93]/2(c[45]/2(a[98],i9),nil))))",
    "t_dp15",
    "t_dp16",
    "t_dp17 c[116,95,100,112,49,55]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[100,105,99,116,45,107,101,121],f1.5)))",
    "t_dp18 c[116,95,100,112,49,56]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_dp19 c[116,95,100,112,49,57]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[100,105,99,116,45,100,97,116,97],a[102,111,111])))",
    "t_dp20 c[116,95,100,112,50,48]/1(c[45]/2(i1,c[91,124,93]/2(c[45]/2(a[97],i9),c[91,124,93]/2(c[45]/2(a[98],i2),nil))))",
    "t_dp21 c[116,95,100,112,50,49]/1(a[121,101,115])",
    "t_dp22 c[116,95,100,112,50,50]/1(c[45]/2(c[45]/2(i1,i9),c[91,124,93]/2(c[45]/2(a[97],i1),nil)))",
    "t_dp23 c[116,95,100,112,50,51]/1(c[91,124,93]/2(c[45]/2(a[97],i1),nil))",
    "t_dp24 c[116,95,100,112,50,52]/1(c[45]/2(c[45]/2(c[45]/2(i5,V0),c[91,124,93]/2(c[45]/2(a[97],V1),c[91,124,93]/2(c[45]/2(a[98],V2),nil))),V3))",
    "t_dp25 c[116,95,100,112,50,53]/1(i7)",
    "t_dp26 c[116,95,100,112,50,54]/1(a[116])",
    "t_dp27 c[116,95,100,112,50,55]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[100,105,99,116,45,107,101,121],c[102]/1(a[120]))))",
    "t_dp28 c[116,95,100,112,50,56]/1(c[45]/2(a[98],c[91,124,93]/2(c[45]/2(i1,a[97]),c[91,124,93]/2(c[45]/2(i2,a[122]),nil))))",
    "t_dp29",
    "t_dp30 c[116,95,100,112,51,48]/1(c[45]/2(a[116],c[91,124,93]/2(c[45]/2(a[97],i1),c[91,124,93]/2(c[45]/2(a[98],a[110,101,119]),c[91,124,93]/2(c[45]/2(a[99],i3),nil)))))",
    "t_dp31 c[116,95,100,112,51,49]/1(c[91,124,93]/2(c[45]/2(a[97],i1),c[91,124,93]/2(c[45]/2(a[98],i2),nil)))",
    "t_dp32 c[116,95,100,112,51,50]/1(c[91,124,93]/2(c[45]/2(a[97],i9),c[91,124,93]/2(c[45]/2(a[98],i2),nil)))",
    "t_dp33 c[116,95,100,112,51,51]/1(c[91,124,93]/2(c[45]/2(a[97],i1),nil))",
    "t_dp34 c[116,95,100,112,51,52]/1(c[91,124,93]/2(c[45]/2(a[97],i1),c[91,124,93]/2(c[45]/2(a[98],i2),c[91,124,93]/2(c[45]/2(a[99],i3),nil))))",
    "t_dp35 c[116,95,100,112,51,53]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[100,105,99,116,45,107,101,121],f1.5)))",
    "t_dp36 c[116,95,100,112,51,54]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_dp37 c[116,95,100,112,51,55]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[100,105,99,116,45,100,97,116,97],a[102,111,111])))",
    "t_dp38 c[116,95,100,112,51,56]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_dp39 c[116,95,100,112,51,57]/1(c[91,124,93]/2(c[45]/2(a[97],i1),nil))",
    "t_dp40 c[116,95,100,112,52,48]/1(i5)",
    "t_dp41 c[116,95,100,112,52,49]/1(c[91,124,93]/2(c[45]/2(a[97],i1),nil))",
    "t_dp42 c[116,95,100,112,52,50]/1(c[91,124,93]/2(c[45]/2(a[97],i3),c[91,124,93]/2(c[45]/2(a[98],i1),c[91,124,93]/2(c[45]/2(a[99],i2),c[91,124,93]/2(c[45]/2(a[100],i1),c[91,124,93]/2(c[45]/2(a[101],i4),nil))))))",
    "t_dp43 c[116,95,100,112,52,51]/1(a[116])",
    "t_dp44 c[116,95,100,112,52,52]/1(a[115,97,109,101])",
    "t_dp45 c[116,95,100,112,52,53]/1(c[91,124,93]/2(c[45]/2(i1,a[97]),c[91,124,93]/2(c[45]/2(i2,a[98]),c[91,124,93]/2(c[45]/2(a[99],a[120]),nil))))",
    "t_dp46 c[116,95,100,112,52,54]/1(c[91,124,93]/2(c[45]/2(a[97],i1),c[91,124,93]/2(c[45]/2(a[98],i3),nil)))",
    "t_dp47 c[116,95,100,112,52,55]/1(a[121,101,115])",
    "t_dp48 c[116,95,100,112,52,56]/1(c[45]/2(i1,i2))",
    "t_dp49",
    "t_dp50 c[116,95,100,112,53,48]/1(c[45]/2(a[116],c[91,124,93]/2(c[45]/2(a[97],i1),c[91,124,93]/2(c[45]/2(a[98],i2),c[91,124,93]/2(c[45]/2(a[99],i3),nil)))))",
    "t_dp51 c[116,95,100,112,53,49]/1(c[91,124,93]/2(c[45]/2(i1,a[121]),c[91,124,93]/2(c[45]/2(i2,a[120]),c[91,124,93]/2(c[45]/2(a[97],i3),c[91,124,93]/2(c[45]/2(a[98],i1),nil)))))",
    "t_dp52 c[116,95,100,112,53,50]/1(c[45]/2(a[116],nil))",
    "t_dp53 c[116,95,100,112,53,51]/1(c[91,124,93]/2(c[45]/2(a[97],i1),c[91,124,93]/2(c[45]/2(a[98],i2),nil)))",
    "t_dp54 c[116,95,100,112,53,52]/1(c[45]/2(a[116],c[91,124,93]/2(c[45]/2(a[97],i1),c[91,124,93]/2(c[45]/2(a[98],i2),nil))))",
    "t_dp55 c[116,95,100,112,53,53]/1(a[121,101,115])",
    "t_dp56 c[116,95,100,112,53,54]/1(a[116])",
    "t_dp57 c[116,95,100,112,53,55]/1(c[114,97,105,115,101,100]/1(c[100,117,112,108,105,99,97,116,101,95,107,101,121]/1(a[97])))",
    "t_dp58 c[116,95,100,112,53,56]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[112,97,105,114],c[61]/2(a[97],i1))))",
    "t_dp59 c[116,95,100,112,53,57]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[112,97,105,114],c[58]/2(a[97],i1))))",
    "t_dp60 c[116,95,100,112,54,48]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[112,97,105,114],c[97]/1(i1))))",
    "t_dp61 c[116,95,100,112,54,49]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[100,105,99,116,45,100,97,116,97],a[102,111,111])))",
    "t_dp62 c[116,95,100,112,54,50]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_dp63 c[116,95,100,112,54,51]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[108,105,115,116],c[91,124,93]/2(c[45]/2(a[97],i1),V0))))",
    "t_dp64 c[116,95,100,112,54,52]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[100,105,99,116,45,107,101,121],f1.5)))",
    "t_dp65 c[116,95,100,112,54,53]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[100,105,99,116,45,100,97,116,97],a[102,111,111])))",
    "t_dp66 c[116,95,100,112,54,54]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_dp67",
    "t_dp68 c[116,95,100,112,54,56]/1(a[121,101,115])",
    "t_dp69",
    "t_dp70 c[116,95,100,112,55,48]/1(c[45]/2(i1,i2))",
    "t_dp71",
    "t_dp72",
    "t_dp73 c[116,95,100,112,55,51]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[108,105,115,116],a[102,111,111])))",
    "t_dp74 c[116,95,100,112,55,52]/1(c[91,124,93]/2(c[45]/2(a[97],c[102]/1(V0)),c[91,124,93]/2(c[45]/2(a[98],V0),c[91,124,93]/2(c[45]/2(a[99],f1.5),nil))))",
    "t_dp75 c[116,95,100,112,55,53]/1(c[45]/2(c[91,124,93]/2(c[45]/2(a[97],i1),c[91,124,93]/2(c[45]/2(a[98],i2),nil)),c[91,124,93]/2(a[120],nil)))",
    "t_dp76 c[116,95,100,112,55,54]/1(c[45]/2(c[45]/2(a[97],i1),a[116]))",
    "t_dp77 c[116,95,100,112,55,55]/1(c[45]/2(V0,c[91,124,93]/2(c[45]/2(a[97],i1),c[91,124,93]/2(c[45]/2(a[98],i2),nil))))",
    "t_dp78 c[116,95,100,112,55,56]/1(i1)",
    "t_dp79 c[116,95,100,112,55,57]/1(nil)",
    "t_dp80 c[116,95,100,112,56,48]/1(c[91,124,93]/2(c[45]/2(a[97],i1),c[91,124,93]/2(c[45]/2(a[98],i2),c[91,124,93]/2(c[45]/2(a[99],i3),c[91,124,93]/2(c[45]/2(a[100],i4),c[91,124,93]/2(c[45]/2(a[101],i5),c[91,124,93]/2(c[45]/2(a[102],i6),c[91,124,93]/2(c[45]/2(a[103],i7),c[91,124,93]/2(c[45]/2(a[104],i8),nil)))))))))",
    "t_dp81 c[116,95,100,112,56,49]/1(c[91,124,93]/2(c[45]/2(i3,a[98]),c[91,124,93]/2(c[45]/2(i5,a[97]),c[91,124,93]/2(c[45]/2(a[120],i1),c[91,124,93]/2(c[45]/2(a[121],i2),nil)))))",
    "t_dp82 c[116,95,100,112,56,50]/1(c[45]/2(i1,c[91,124,93]/2(c[45]/2(a[98],i2),nil)))",
    "t_dp83 c[116,95,100,112,56,51]/1(c[45]/2(i2,c[91,124,93]/2(c[45]/2(a[97],i1),nil)))",
    "t_dp84",
    "t_dp85",
    "t_dp86 c[116,95,100,112,56,54]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[100,105,99,116,45,107,101,121],f1.5)))",
    "t_dp87 c[116,95,100,112,56,55]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_dp88 c[116,95,100,112,56,56]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[100,105,99,116,45,100,97,116,97],a[102,111,111])))",
    "t_dp89 c[116,95,100,112,56,57]/1(c[45]/2(c[45]/2(i1,a[116]),nil))",
    "t_dp90 c[116,95,100,112,57,48]/1(c[45]/2(i1,c[91,124,93]/2(c[45]/2(a[98],i2),nil)))",
    "t_dp91 c[116,95,100,112,57,49]/1(c[45]/2(i5,V0))",
    "t_dp92 c[116,95,100,112,57,50]/1(c[45]/2(c[91,124,93]/2(c[45]/2(a[97],i1),c[91,124,93]/2(c[45]/2(a[98],i2),c[91,124,93]/2(c[45]/2(a[99],i3),nil))),c[91,124,93]/2(c[45]/2(a[97],i1),c[91,124,93]/2(c[45]/2(a[99],i3),nil))))",
    "t_dp93 c[116,95,100,112,57,51]/1(a[121,101,115])",
    "t_dp94 c[116,95,100,112,57,52]/1(c[45]/2(a[120],c[91,124,93]/2(c[45]/2(a[97],a[121]),nil)))",
    "t_dp95 c[116,95,100,112,57,53]/1(i3)",
    "t_dp96",
    "t_dp97 c[116,95,100,112,57,55]/1(c[45]/2(c[45]/2(c[45]/2(i1,i2),a[116]),nil))",
    "t_dp98 c[116,95,100,112,57,56]/1(i1)",
    "t_dp99",
    "t_dp100",
    "t_dp101",
    "t_dp102 c[116,95,100,112,49,48,50]/1(a[116])",
    "t_dp103 c[116,95,100,112,49,48,51]/1(a[121,101,115])",
    "t_dp104",
    "t_dp105 c[116,95,100,112,49,48,53]/1(i2)",
    "t_dp106 c[116,95,100,112,49,48,54]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[100,105,99,116,45,100,97,116,97],a[102,111,111])))",
    "t_dp107 c[116,95,100,112,49,48,55]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[100,105,99,116,45,100,97,116,97],a[102,111,111])))",
    "t_dp108 c[116,95,100,112,49,48,56]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_dp109 c[116,95,100,112,49,48,57]/1(c[45]/2(i1,i2))",
    "t_dp110 c[116,95,100,112,49,49,48]/1(i1)",
    "t_dp111 c[116,95,100,112,49,49,49]/1(a[121,101,115])",
    "t_dp112",
    "t_dp113 c[116,95,100,112,49,49,51]/1(c[45]/2(c[102]/1(V0),V0))",
    "t_dp114 c[116,95,100,112,49,49,52]/1(c[45]/2(V0,V1))",
    "t_dp115",
    "t_dp116 c[116,95,100,112,49,49,54]/1(a[121,101,115])",
    "t_dp117",
    "t_dp118 c[116,95,100,112,49,49,56]/1(a[117])",
    "t_dp119 c[116,95,100,112,49,49,57]/1(i1)",
    "t_dp120 c[116,95,100,112,49,50,48]/1(a[121,101,115])",
    "t_dp121 c[116,95,100,112,49,50,49]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[100,105,99,116,45,100,97,116,97],a[102,111,111])))",
    "t_dp122 c[116,95,100,112,49,50,50]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[100,105,99,116,45,100,97,116,97],a[102,111,111])))",
    "t_dp123 c[116,95,100,112,49,50,51]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_dp124 c[116,95,100,112,49,50,52]/1(i1)",
    "t_dp125 c[116,95,100,112,49,50,53]/1(c[45]/2(i3,i3))",
    "t_dp126",
    "t_dp127 c[116,95,100,112,49,50,55]/1(a[121,101,115])",
    "t_dp128 c[116,95,100,112,49,50,56]/1(a[121,101,115])",
    "t_dp129",
    "t_dp130",
    "t_dp131 c[116,95,100,112,49,51,49]/1(c[45]/2(V0,c[91,124,93]/2(c[45]/2(a[97],V1),c[91,124,93]/2(c[45]/2(a[98],V2),nil))))",
    "t_dp132 c[116,95,100,112,49,51,50]/1(c[45]/2(V0,c[91,124,93]/2(c[45]/2(a[97],V1),c[91,124,93]/2(c[45]/2(a[98],V2),nil))))",
    "t_dp133 c[116,95,100,112,49,51,51]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_dp134 c[116,95,100,112,49,51,52]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[100,105,99,116],a[102,111,111])))",
    "t_dp135 c[116,95,100,112,49,51,53]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[100,105,99,116],a[102,111,111])))",
    "t_dp136 c[116,95,100,112,49,51,54]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[100,105,99,116],a[102,111,111])))",
    "t_dp137 c[116,95,100,112,49,51,55]/1(c[45]/2(V0,nil))",
    "t_dp138 c[116,95,100,112,49,51,56]/1(a[121,101,115])",
    "t_dp139 c[116,95,100,112,49,51,57]/1(c[91,124,93]/2(c[45]/2(a[97],i1),nil))",
    "t_dp140 c[116,95,100,112,49,52,48]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[100,105,99,116],c[91,124,93]/2(c[45]/2(a[97],i1),nil))))",
    "t_dp141 c[116,95,100,112,49,52,49]/1(i4)",
    "t_dp142 c[116,95,100,112,49,52,50]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[100,105,99,116],c[91,124,93]/2(c[45]/2(a[97],i1),nil))))",
    "t_dp143 c[116,95,100,112,49,52,51]/1(c[45]/2(c[45]/2(a[97],a[98]),c[61,61]/2(V0,V1)))",
    "t_dp144 c[116,95,100,112,49,52,52]/1(c[91,124,93]/2(c[45]/2(a[97],i1),c[91,124,93]/2(c[45]/2(a[98],i2),c[91,124,93]/2(c[45]/2(a[99],i3),nil))))",
    "t_dp145",
    "t_dp146",
    "t_dp147 c[116,95,100,112,49,52,55]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[110,111,116,95,108,101,115,115,95,116,104,97,110,95,122,101,114,111],i-1)))",
    "t_dp148 c[116,95,100,112,49,52,56]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_dp149 c[116,95,100,112,49,52,57]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],a[97])))",
    "t_dp150 c[116,95,100,112,49,53,48]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[100,105,99,116],a[102,111,111])))",
    "t_dp151 c[116,95,100,112,49,53,49]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_dp152 c[116,95,100,112,49,53,50]/1(i1)",
    "t_dp153",
    "t_dp154",
    "t_dp155",
    "t_dp156 c[116,95,100,112,49,53,54]/1(c[91,124,93]/2(c[45]/2(c[45]/2(a[97],i1),a[120]),c[91,124,93]/2(c[45]/2(c[45]/2(a[98],i2),a[121]),nil)))",
    "t_dp157 c[116,95,100,112,49,53,55]/1(c[100]/1(a[99,111,109,112,97,116,105,98,108,101,95,100,105,99,116]))",
    "t_dp158 c[116,95,100,112,49,53,56]/1(c[100]/1(a[99,111,109,112,97,116,105,98,108,101,95,100,105,99,116]))",
    "t_dp159 c[116,95,100,112,49,53,57]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[100,105,99,116],a[102,111,111])))",
    "t_dp160 c[116,95,100,112,49,54,48]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_dp161 c[116,95,100,112,49,54,49]/1(c[91,124,93]/2(c[45]/2(c[45]/2(c[45]/2(a[97],i1),a[120]),a[112]),c[91,124,93]/2(c[45]/2(c[45]/2(c[45]/2(a[98],i2),a[121]),a[113]),nil)))",
    "t_dp162 c[116,95,100,112,49,54,50]/1(c[100]/1(a[99,111,109,112,97,116,105,98,108,101,95,100,105,99,116]))",
    "t_dp163",
    "t_dp164 c[116,95,100,112,49,54,52]/1(c[45]/2(a[97],i1))"
]

function _dp_file()::Tuple{String, Vector{String}}
    names = ["t_$(id)" for (id, _) in _DP_CASES]
    text =
        _DP_PROGRAM * join([
            "t_$(id)(R) :- catch(($g), error(SsuE, _), R = raised(SsuE)).\n" for
            (id, g) in _DP_CASES
        ])
    f = joinpath(mktempdir(), "dictpreds.pl")
    write(f, text)
    return f, names
end

"The kernel's lines for `names` after consulting `path`, as the driver writes swipl's; the database, for the white-box tests."
function _dp_kernel(path::String, names::Vector{String})
    gd = LK.PL_global_data{_DP}()
    ld = LK.PL_local_data{_DP}(gd)
    st, ball, _ = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * _dp_enc(ball::_DP)]
    for name in names
        proc = LK.isCurrentProcedure(sym_key(_dps(name)), 1, LK.MODULE_user(gd))
        if proc === nothing || !LK.isDefinedProcedure(gd, proc)
            push!(out, "$name undefined")
            continue
        end
        sols = String[]
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 1)
        LK.putSlotValue!(ld, a + 1, mk_var(_DP, LK.fresh_var_keys!(1)), LK.PutVarMap())
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
        )
        n = 0
        while (n += 1) <= 50
            rc = LK.PL_next_solution(gd, ld, qid)
            if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
                push!(
                    sols,
                    _dp_enc(mk_expr(_DP, _DP[_dps(name), lk_answers(ld, (a:a)...)...]))
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


@testset "dict-predicate rows: the kernel's answers are swipl's (dp01-dp164)" begin
    f, names = _dp_file()
    kl, _, _ = _dp_kernel(f, names)
    @test length(kl) == length(_DP_PINNED)
    for (k, p) in zip(kl, _DP_PINNED)
        k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
        @test k == p
    end
end

@testset "the dict-predicate rows are not vacuous (dp01-dp164)" begin
    rows = _DP_PINNED[2:end]                                                       # the driver's first line is `ok`
    @test _DP_PINNED[1] == "ok"
    @test length(rows) == length(_DP_CASES) == 164
    code(t) = "[" * join(Int.(collect(t)), ",") * "]"
    # raised(…) rows: 27 type errors, 12 instantiation errors, 1 duplicate_key, 1 domain_error
    @test count(l -> occursin(code("raised"), l), rows) == 41
    @test count(l -> occursin(code("type_error") * "/2", l), rows) == 27
    @test count(l -> occursin(code("instantiation_error"), l), rows) == 12
    @test count(l -> occursin(code("duplicate_key") * "/1", l), rows) == 1
    @test count(l -> occursin(code("not_less_than_zero"), l), rows) == 1
    # rows that fail have no answer after the name; rows that answer `yes`
    @test count(l -> occursin(r"^t_dp\d+$", l), rows) == 31
    @test count(l -> endswith(l, "(a" * code("yes") * "))"), rows) == 12
    # '$get_dict_kv'/6,8 on dicts with other keys raise domain_error(compatible_dict, _), caught inside the row as d(compatible_dict)
    @test count(l -> occursin(code("compatible_dict"), l), rows) == 3
    # no answer holds a dict (a dict is a compound named `dict`)
    @test !any(l -> occursin(code("dict") * "/", l), _DP_PINNED)
    # '$get_dict_ex'/3 raises existence_error(key, c) (dp03)
    @test any(l -> startswith(l, "t_dp03 ") && occursin(code("key"), l) && endswith(l, "a" * code("c") * "))"), rows)
    # get_dict/5 hands back V and the new dict's pairs (dp13: 1 with [a-9, b-2])
    @test any(l -> startswith(l, "t_dp13 ") && occursin("c[45]/2(i1,c[91,124,93]/2(c[45]/2(a[97],i9)", l), rows)
end

@testset "the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    # the pinned table is the driver's whole output (the inert-testset guard: an assertion either way)
    @test length(_DP_PINNED) == length(_DP_CASES) + 1
    if swipl === nothing
        @info "DICT LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        f, names = _dp_file()
        @test _dp_swipl_lines(f, names) == _DP_PINNED
    end
end
