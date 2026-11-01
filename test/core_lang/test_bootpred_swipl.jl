# ORIGINAL: a LIVE differential of BOOTPRED against swipl at the pin (pl-gc.c, pl-thread.c, pl-mutex.c, pl-dict.c) — BOOTPRED's rows
# test/core_lang/test_bootpred_swipl.jl — `'$garbage_collect'/1`, thread_self/1 and with_mutex/2 (bp01-bp26) and the pl-dict.c predicates
# is_dict/1,2, dict_create/3, get_dict/3, put_dict/3, select_dict/3 (bp27-bp119) against swipl 10.1.19:
#   * A PROGRAM consulted by the kernel's loader and cases `t_<id>(R)` run in order in one database, each wrapped in
#     `catch(Goal, error(SsuE, _), R = raised(SsuE))`; the driver is test_at_body_swipl.jl's (`enc`oded answers).
#   * Every answer line is swipl's, PINNED (swipl 10.1.19-1-gcbf4e189, 2026-10-31, lk-channel evidence/BOOTPRED/bootpred_rows.out in the
#     BOOTPRED branch); with `swipl` on PATH the live answers are compared with the pins too.
#   * UNVERIFIED on the kernel (nothing was compiled when these rows were written): every kernel answer; the gate decides.
#   * KNOWN DIFFERENCES (single-thread forms, pinned separately below): with_mutex/2 does not examine its mutex.
#   * Dicts are built by dict_create/3 and put_dict/3 only (the reader refuses dicts, the writer has no dict arm) and never appear in an
#     answer: the kernel orders the pairs by its own key words, swipl by its atom handles, so every order-dependent row observes a dict
#     through `dpairs/2` (get_dict/3 findall, msort) or a single get_dict/3, is_dict/2 or `==` between two dicts built here.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — the three built-ins ride the term layer only through PL_unify_atom and callProlog; every type in CI
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _BP = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_bps(x) = lk_sym(_BP, Symbol(x))

_bp_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _bp_enc(t::_BP, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _bp_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _bp_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _bp_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_bp_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

# the swipl side: test/core_lang/test_ssu_swipl.jl's driver (consult, then every answer of each t_<id>/1, `enc`oded)
const _BP_DRIVER = raw"""
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
function _bp_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _BP_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(pipeline(`swipl -q $f`; stdin=devnull, stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

# the program: three facts for the once/1 rows. The goals handed to with_mutex/2 are single predicates (bp_p2, bp_bind), and
# bp_mem stands for member/2: with_mutex/2 is callProlog, which resolves the goal's functor, and `','/2` and member/2 are
# boot/init.pl and library(lists) definitions that the kernel does not load yet (LB4; handoff checklist). swipl's own
# answers to the conjunction forms are the same as these rows' (with_mutex(m, (p(X), X > 1)) gives 2).
const _BP_PROGRAM = raw"""
p(1).
p(2).
p(3).
dpairs(D, Ps) :- findall(K-V, get_dict(K, D, V), Ps0), msort(Ps0, Ps).
bp_p2(X) :- p(X), X > 1.
bp_bind(X) :- X = f(Y), Y = 1.
bp_mem(X, [X|_]).
bp_mem(X, [_|T]) :- bp_mem(X, T).
"""

# bp01-bp08 thread_self/1; bp09-bp19 with_mutex/2; bp20-bp26 '$garbage_collect'/1; bp27-bp51 dict_create/3; bp52-bp60 is_dict/1,2;
# bp61-bp79 get_dict/3; bp80-bp100 put_dict/3; bp101-bp116 select_dict/3; bp117-bp119 kill rows of the mutant list
const _BP_CASES = [
    ("bp01", raw"thread_self(R)"),                                       # main
    ("bp02", raw"thread_self(main), R = yes"),
    ("bp03", raw"thread_self(other), R = yes"),                          # fails
    ("bp04", raw"findall(X, thread_self(X), R)"),                        # [main]: one answer, no choice point
    ("bp05", raw"thread_self(1), R = yes"),                              # fails
    ("bp06", raw"thread_self(T), atom(T), R = T"),
    ("bp07", raw"thread_self(T), T == main, R = ok"),
    ("bp08", raw"with_mutex(m, thread_self(R))"),
    ("bp09", raw"with_mutex(m, R = 1)"),
    ("bp10", raw"findall(X, with_mutex(m, p(X)), R)"),                   # once/1: [1]
    ("bp11", raw"with_mutex(m, fail), R = x"),                           # fails
    ("bp12", raw"catch(with_mutex(m, throw(oops)), E, R = caught(E))"),
    ("bp13", raw"with_mutex(m, bp_p2(X)), R = X"),                         # 2: the goal backtracks inside
    ("bp14", raw"with_mutex(m, with_mutex(m, R = n))"),                  # nested, same mutex
    ("bp15", raw"with_mutex(m, p(X)), X > 1, R = X"),                    # fails: once/1 gave 1 only
    ("bp16", raw"with_mutex(m, bp_bind(X)), R = X"),                         # bindings stay
    ("bp17", raw"with_mutex(m, context_module(R))"),                     # user
    ("bp18", raw"with_mutex(m, nosuchpred_bp(R))"),                      # existence_error(procedure, …)
    ("bp19", raw"with_mutex(m, true), with_mutex(n, R = two)"),
    ("bp20", raw"'$garbage_collect'(0), R = ok"),
    ("bp21", raw"'$garbage_collect'(foo), R = ok"),                      # d is read only under O_DEBUG
    ("bp22", raw"'$garbage_collect'(_), R = ok"),
    ("bp23", raw"findall(x, '$garbage_collect'(0), R)"),                 # [x]: deterministic
    ("bp24", raw"X = f(Y, Z), Y = 1, '$garbage_collect'(0), R = X-Z"),   # bindings survive
    ("bp25", raw"'$garbage_collect'(0), '$garbage_collect'(1), R = twice"),
    ("bp26", raw"length(L, 3), '$garbage_collect'(0), R = L"),
    # dict_create/3
    ("bp27", raw"dict_create(D, t, [a-1, b-2]), dpairs(D, R)"),
    ("bp28", raw"dict_create(D, t, [a=1, b=2, c=3]), dpairs(D, R)"),
    ("bp29", raw"dict_create(D, t, [a:1, b:2]), dpairs(D, R)"),
    ("bp30", raw"dict_create(D, t, [a(1), b(2)]), dpairs(D, R)"),
    ("bp31", raw"dict_create(D, t, [a-1, b=2, c:3, d(4)]), dpairs(D, R)"),
    ("bp32", raw"dict_create(D, tag, []), is_dict(D, T), R = T"),
    ("bp33", raw"dict_create(D, _, [a-1]), is_dict(D, T), var(T), R = yes"),
    ("bp34", raw"dict_create(D, t, [2-b, 1-a, 3-c]), dpairs(D, R)"),
    ("bp35", raw"dict_create(D, t, [a-1, a-2]), R = D"),
    ("bp36", raw"dict_create(D, t, [a-1, b-2, a-3]), R = D"),
    ("bp37", raw"dict_create(D, t, foo), R = D"),
    ("bp38", raw"dict_create(D, t, [a]), R = D"),
    ("bp39", raw"dict_create(D, t, [f(1, 2)]), R = D"),
    ("bp40", raw"dict_create(D, t, [X-1]), R = D-X"),
    ("bp41", raw"dict_create(D, t, [1.5-a]), R = D"),
    ("bp42", raw"dict_create(D, t, [f(x)-1]), R = D"),
    ("bp43", raw"dict_create(D, t, [a-1|_]), R = D"),
    ("bp44", raw"dict_create(D, t, [a-1|foo]), R = D"),
    ("bp45", raw"dict_create(foo, t, [a-1]), R = yes"),
    (
        "bp46",
        raw"dict_create(D1, t, [a-1, b-2]), dict_create(D2, t, [b=2, a=1]), D1 == D2, R = same"
    ),
    ("bp47", raw"dict_create(D1, t, [a-1]), dict_create(D2, u, [a-1]), D1 = D2, R = yes"),
    ("bp48", raw"dict_create(D1, t, [a-X]), dict_create(D2, t, [a-1]), D1 = D2, R = X"),
    ("bp49", raw"dict_create(D, T, [a-1]), T = foo, is_dict(D, foo), R = yes"),
    ("bp50", raw"dict_create(D, t, [a-1, b-2]), dict_create(D, T, L), R = T-L"),
    ("bp51", raw"findall(x, dict_create(_, t, [a-1]), R)"),
    # is_dict/1,2
    ("bp52", raw"findall(x, is_dict(foo), R)"),
    ("bp53", raw"findall(x, is_dict(_), R)"),
    ("bp54", raw"dict_create(D, t, []), is_dict(D), R = yes"),
    ("bp55", raw"findall(x, is_dict(f(a), _), R)"),
    (
        "bp56",
        raw"findall(x, (bp_mem(X, [1, 2.5, abc, [], [a], f(a), g(a, b, c)]), is_dict(X)), R)"
    ),
    ("bp57", raw"dict_create(D, t, [a-1]), is_dict(D, t), R = yes"),
    ("bp58", raw"dict_create(D, t, [a-1]), is_dict(D, u), R = yes"),
    ("bp59", raw"findall(x, is_dict(_, _), R)"),
    ("bp60", raw"dict_create(D, f(x), [a-1]), is_dict(D, T), R = T"),
    # get_dict/3
    ("bp61", raw"dict_create(D, t, [a-1, b-2]), get_dict(a, D, V), R = V"),
    ("bp62", raw"dict_create(D, t, [a-1, b-2]), get_dict(b, D, V), R = V"),
    ("bp63", raw"dict_create(D, t, [a-1, b-2]), get_dict(c, D, V), R = V"),
    (
        "bp64",
        raw"dict_create(D, t, [a-1, b-2, c-3]), findall(K-V, get_dict(K, D, V), L), length(L, R)"
    ),
    ("bp65", raw"dict_create(D, t, [a-1, b-2, c-3]), findall(K, get_dict(K, D, 2), R)"),
    ("bp66", raw"dict_create(D, t, [a-1, b-2]), get_dict(a, D, 2), R = yes"),
    ("bp67", raw"dict_create(D, t, [a-1, b-2]), get_dict(a, D, 1), R = yes"),
    ("bp68", raw"get_dict(a, foo, V), R = V"),
    ("bp69", raw"get_dict(a, _, V), R = V"),
    ("bp70", raw"dict_create(D, t, [a-1]), get_dict(1.5, D, V), R = V"),
    ("bp71", raw"dict_create(D, t, [a-1]), get_dict(f(x), D, V), R = V"),
    ("bp72", raw"dict_create(D, t, [1-one, 2-two]), get_dict(2, D, V), R = V"),
    ("bp73", raw"dict_create(D, t, [a-1, b-2]), findall(V, get_dict(a, D, V), R)"),
    ("bp74", raw"dict_create(D, t, []), findall(K-V, get_dict(K, D, V), R)"),
    (
        "bp75",
        raw"dict_create(D, t, [a-1, b-2, c-3]), findall(K, (get_dict(K, D, V), V > 1), L), msort(L, R)"
    ),
    ("bp76", raw"dict_create(D, t, [a-X, b-Y]), get_dict(a, D, 5), R = X-Y"),
    ("bp77", raw"dict_create(D, t, [a-f(Z)]), get_dict(a, D, f(7)), R = Z"),
    ("bp78", raw"dict_create(D, t, [a-1, b-2, c-3, d-4, e-5]), get_dict(e, D, V), R = V"),
    ("bp79", raw"dict_create(D, t, [a-1, b-2]), get_dict(K, D, V), K == b, R = V"),
    # put_dict/3
    ("bp80", raw"dict_create(D, t, [a-1]), put_dict([b-2], D, N), dpairs(N, R)"),
    ("bp81", raw"dict_create(D, t, [a-1, b-2]), put_dict([a-9], D, N), dpairs(N, R)"),
    (
        "bp82",
        raw"dict_create(D, t, [a-1]), dict_create(E, u, [b-2, c-3]), put_dict(E, D, N), dpairs(N, R)"
    ),
    (
        "bp83",
        raw"dict_create(D, t, [a-1]), dict_create(E, u, [b-2]), put_dict(E, D, N), is_dict(N, T), R = T"
    ),
    ("bp84", raw"dict_create(D, t, [a-1]), put_dict([], D, N), dpairs(N, R)"),
    ("bp85", raw"dict_create(D, t, [a-1]), put_dict([b=2, c:3, d(4)], D, N), dpairs(N, R)"),
    ("bp86", raw"dict_create(D, t, [a-1]), put_dict([a-9], D, _), dpairs(D, R)"),
    ("bp87", raw"put_dict([a-1], foo, N), R = N"),
    ("bp88", raw"dict_create(D, t, [a-1]), put_dict(foo, D, N), R = N"),
    ("bp89", raw"dict_create(D, t, [a-1]), put_dict([b-1, b-2], D, N), R = N"),
    ("bp90", raw"dict_create(D, t, [a-1]), put_dict([b-1|_], D, N), R = N"),
    ("bp91", raw"put_dict([x-1], _, N), R = N"),
    (
        "bp92",
        raw"dict_create(D, t, [a-1]), put_dict([b-2], D, N), dict_create(E, t, [a-1, b-2]), N == E, R = same"
    ),
    ("bp93", raw"dict_create(D, t, []), put_dict([x-1, y-2], D, N), dpairs(N, R)"),
    (
        "bp94",
        raw"dict_create(D0, t, [a-0]), put_dict([a-1], D0, D1), put_dict([b-2], D1, D2), put_dict([a-3, c-4], D2, D3), dpairs(D3, R)"
    ),
    ("bp95", raw"dict_create(D, t, [1-a, 3-c]), put_dict([2-b, 4-d], D, N), dpairs(N, R)"),
    (
        "bp96",
        raw"dict_create(D, t, [k1-1, k3-3, k5-5, k7-7, k9-9, k11-11]), put_dict([k2-2, k4-4, k6-6, k8-8, k10-10, k3-33], D, N), dpairs(N, R)"
    ),
    (
        "bp97",
        raw"dict_create(D, t, [a-X]), put_dict([b-1], D, N), get_dict(a, N, V), V == X, R = shared"
    ),
    (
        "bp98",
        raw"dict_create(D, t, [a-1, b-2]), put_dict([b-X], D, N), get_dict(b, N, V), V == X, R = replaced"
    ),
    (
        "bp99",
        raw"dict_create(D, t, [a-1]), dict_create(E, t, [a-2]), put_dict(E, D, N), dpairs(N, R)"
    ),
    (
        "bp100",
        raw"dict_create(D, t, [a-1]), put_dict([b-2], D, N), put_dict([b-2], N, M), N == M, R = unchanged"
    ),
    # select_dict/3
    (
        "bp101",
        raw"dict_create(S, t, [a-X]), dict_create(F, t, [a-1, b-2]), select_dict(S, F, Rest), dpairs(Rest, P), R = X-P"
    ),
    (
        "bp102",
        raw"dict_create(S, t, [a-1, b-2]), dict_create(F, t, [a-1, b-2]), select_dict(S, F, Rest), dpairs(Rest, P), R = P"
    ),
    (
        "bp103",
        raw"dict_create(S, t, [c-1]), dict_create(F, t, [a-1, b-2]), select_dict(S, F, _), R = yes"
    ),
    (
        "bp104",
        raw"dict_create(S, t, [a-9]), dict_create(F, t, [a-1, b-2]), select_dict(S, F, _), R = yes"
    ),
    (
        "bp105",
        raw"dict_create(S, u, [a-1]), dict_create(F, t, [a-1]), select_dict(S, F, _), R = yes"
    ),
    (
        "bp106",
        raw"dict_create(S, T, [a-1]), dict_create(F, foo, [a-1, b-2]), select_dict(S, F, _), R = T"
    ),
    (
        "bp107",
        raw"dict_create(S, t, [a-1]), dict_create(F, T, [a-1, b-2]), select_dict(S, F, Rest), is_dict(Rest, T2), R = T2"
    ),      # the rest has the tag dyndict, written #
    ("bp108", raw"select_dict(foo, F, R), R = F"),
    ("bp109", raw"dict_create(S, t, [a-1]), select_dict(S, foo, R)"),
    (
        "bp110",
        raw"dict_create(S, t, []), dict_create(F, t, [a-1, b-2]), select_dict(S, F, Rest), dpairs(Rest, R)"
    ),
    (
        "bp111",
        raw"dict_create(S, t, [b-X, d-Y]), dict_create(F, t, [a-1, b-2, c-3, d-4, e-5]), select_dict(S, F, Rest), dpairs(Rest, P), R = X-Y-P"
    ),
    (
        "bp112",
        raw"dict_create(S, t, [a-1]), dict_create(F, t, [a-1, b-2]), dict_create(E, '#', [b-2]), select_dict(S, F, E), R = yes"
    ),
    (
        "bp113",
        raw"dict_create(S, t, [a-1]), dict_create(F, t, [a-1, b-2]), dict_create(E, '#', [b-3]), select_dict(S, F, E), R = yes"
    ),
    ("bp114", raw"select_dict(_, _, R), R = x"),
    (
        "bp115",
        raw"dict_create(S, t, [a-1]), dict_create(F, t, [a-1, b-2]), findall(P, (select_dict(S, F, Rest), dpairs(Rest, P)), R)"
    ),
    (
        "bp116",
        raw"dict_create(S, t, [a-1]), dict_create(F, t, [a-1, b-2]), dict_create(E, t, [b-2]), select_dict(S, F, E), R = yes"
    ),   # fails: the rest is tagged #, E is t
    # rows added for the mutant list: the dyndict tag of a rest as the next select's From, a deterministic exit, a tag shared with its variable
    (
        "bp117",
        raw"dict_create(S, t, [a-1]), dict_create(F, t, [a-1, b-2, c-3]), select_dict(S, F, R1), dict_create(S2, t, [b-2]), select_dict(S2, R1, R2), dpairs(R2, R)"
    ),   # [c-3]: unify_tags accepts the dyndict tag
    (
        "bp118",
        raw"dict_create(D, t, [a-1]), call_cleanup(get_dict(K, D, V), Det = true), R = Det-K-V"
    ),   # the last pair leaves no choice point
    ("bp119", raw"dict_create(D, T, [a-1]), is_dict(D, foo), R = T")                                    # foo: the tag is the caller's variable
]

# swipl 10.1.19-1-gcbf4e189's answers to the program and cases above (the driver's lines; lk-channel evidence/BOOTPRED/bootpred_rows.out)
const _BP_PINNED = [
    "ok",
    "t_bp01 c[116,95,98,112,48,49]/1(a[109,97,105,110])",
    "t_bp02 c[116,95,98,112,48,50]/1(a[121,101,115])",
    "t_bp03",
    "t_bp04 c[116,95,98,112,48,52]/1(c[91,124,93]/2(a[109,97,105,110],nil))",
    "t_bp05",
    "t_bp06 c[116,95,98,112,48,54]/1(a[109,97,105,110])",
    "t_bp07 c[116,95,98,112,48,55]/1(a[111,107])",
    "t_bp08 c[116,95,98,112,48,56]/1(a[109,97,105,110])",
    "t_bp09 c[116,95,98,112,48,57]/1(i1)",
    "t_bp10 c[116,95,98,112,49,48]/1(c[91,124,93]/2(i1,nil))",
    "t_bp11",
    "t_bp12 c[116,95,98,112,49,50]/1(c[99,97,117,103,104,116]/1(a[111,111,112,115]))",
    "t_bp13 c[116,95,98,112,49,51]/1(i2)",
    "t_bp14 c[116,95,98,112,49,52]/1(a[110])",
    "t_bp15",
    "t_bp16 c[116,95,98,112,49,54]/1(c[102]/1(i1))",
    "t_bp17 c[116,95,98,112,49,55]/1(a[117,115,101,114])",
    "t_bp18 c[116,95,98,112,49,56]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[112,114,111,99,101,100,117,114,101],c[47]/2(a[110,111,115,117,99,104,112,114,101,100,95,98,112],i1))))",
    "t_bp19 c[116,95,98,112,49,57]/1(a[116,119,111])",
    "t_bp20 c[116,95,98,112,50,48]/1(a[111,107])",
    "t_bp21 c[116,95,98,112,50,49]/1(a[111,107])",
    "t_bp22 c[116,95,98,112,50,50]/1(a[111,107])",
    "t_bp23 c[116,95,98,112,50,51]/1(c[91,124,93]/2(a[120],nil))",
    "t_bp24 c[116,95,98,112,50,52]/1(c[45]/2(c[102]/2(i1,V0),V0))",
    "t_bp25 c[116,95,98,112,50,53]/1(a[116,119,105,99,101])",
    "t_bp26 c[116,95,98,112,50,54]/1(c[91,124,93]/2(V0,c[91,124,93]/2(V1,c[91,124,93]/2(V2,nil))))",
    "t_bp27 c[116,95,98,112,50,55]/1(c[91,124,93]/2(c[45]/2(a[97],i1),c[91,124,93]/2(c[45]/2(a[98],i2),nil)))",
    "t_bp28 c[116,95,98,112,50,56]/1(c[91,124,93]/2(c[45]/2(a[97],i1),c[91,124,93]/2(c[45]/2(a[98],i2),c[91,124,93]/2(c[45]/2(a[99],i3),nil))))",
    "t_bp29 c[116,95,98,112,50,57]/1(c[91,124,93]/2(c[45]/2(a[97],i1),c[91,124,93]/2(c[45]/2(a[98],i2),nil)))",
    "t_bp30 c[116,95,98,112,51,48]/1(c[91,124,93]/2(c[45]/2(a[97],i1),c[91,124,93]/2(c[45]/2(a[98],i2),nil)))",
    "t_bp31 c[116,95,98,112,51,49]/1(c[91,124,93]/2(c[45]/2(a[97],i1),c[91,124,93]/2(c[45]/2(a[98],i2),c[91,124,93]/2(c[45]/2(a[99],i3),c[91,124,93]/2(c[45]/2(a[100],i4),nil)))))",
    "t_bp32 c[116,95,98,112,51,50]/1(a[116,97,103])",
    "t_bp33 c[116,95,98,112,51,51]/1(a[121,101,115])",
    "t_bp34 c[116,95,98,112,51,52]/1(c[91,124,93]/2(c[45]/2(i1,a[97]),c[91,124,93]/2(c[45]/2(i2,a[98]),c[91,124,93]/2(c[45]/2(i3,a[99]),nil))))",
    "t_bp35 c[116,95,98,112,51,53]/1(c[114,97,105,115,101,100]/1(c[100,117,112,108,105,99,97,116,101,95,107,101,121]/1(a[97])))",
    "t_bp36 c[116,95,98,112,51,54]/1(c[114,97,105,115,101,100]/1(c[100,117,112,108,105,99,97,116,101,95,107,101,121]/1(a[97])))",
    "t_bp37 c[116,95,98,112,51,55]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[100,105,99,116,45,100,97,116,97],a[102,111,111])))",
    "t_bp38 c[116,95,98,112,51,56]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[107,101,121,45,118,97,108,117,101],a[97])))",
    "t_bp39 c[116,95,98,112,51,57]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[107,101,121,45,118,97,108,117,101],c[102]/2(i1,i2))))",
    "t_bp40 c[116,95,98,112,52,48]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_bp41 c[116,95,98,112,52,49]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[100,105,99,116,45,107,101,121],f1.5)))",
    "t_bp42 c[116,95,98,112,52,50]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[100,105,99,116,45,107,101,121],c[102]/1(a[120]))))",
    "t_bp43 c[116,95,98,112,52,51]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[108,105,115,116],c[91,124,93]/2(c[45]/2(a[97],i1),V0))))",
    "t_bp44 c[116,95,98,112,52,52]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[108,105,115,116],c[91,124,93]/2(c[45]/2(a[97],i1),a[102,111,111]))))",
    "t_bp45",
    "t_bp46 c[116,95,98,112,52,54]/1(a[115,97,109,101])",
    "t_bp47",
    "t_bp48 c[116,95,98,112,52,56]/1(i1)",
    "t_bp49 c[116,95,98,112,52,57]/1(a[121,101,115])",
    "t_bp50 c[116,95,98,112,53,48]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_bp51 c[116,95,98,112,53,49]/1(c[91,124,93]/2(a[120],nil))",
    "t_bp52 c[116,95,98,112,53,50]/1(nil)",
    "t_bp53 c[116,95,98,112,53,51]/1(nil)",
    "t_bp54 c[116,95,98,112,53,52]/1(a[121,101,115])",
    "t_bp55 c[116,95,98,112,53,53]/1(nil)",
    "t_bp56 c[116,95,98,112,53,54]/1(nil)",
    "t_bp57 c[116,95,98,112,53,55]/1(a[121,101,115])",
    "t_bp58",
    "t_bp59 c[116,95,98,112,53,57]/1(nil)",
    "t_bp60 c[116,95,98,112,54,48]/1(c[102]/1(a[120]))",
    "t_bp61 c[116,95,98,112,54,49]/1(i1)",
    "t_bp62 c[116,95,98,112,54,50]/1(i2)",
    "t_bp63",
    "t_bp64 c[116,95,98,112,54,52]/1(i3)",
    "t_bp65 c[116,95,98,112,54,53]/1(c[91,124,93]/2(a[98],nil))",
    "t_bp66",
    "t_bp67 c[116,95,98,112,54,55]/1(a[121,101,115])",
    "t_bp68 c[116,95,98,112,54,56]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[100,105,99,116],a[102,111,111])))",
    "t_bp69 c[116,95,98,112,54,57]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_bp70 c[116,95,98,112,55,48]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[100,105,99,116,45,107,101,121],f1.5)))",
    "t_bp71 c[116,95,98,112,55,49]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[100,105,99,116,45,107,101,121],c[102]/1(a[120]))))",
    "t_bp72 c[116,95,98,112,55,50]/1(a[116,119,111])",
    "t_bp73 c[116,95,98,112,55,51]/1(c[91,124,93]/2(i1,nil))",
    "t_bp74 c[116,95,98,112,55,52]/1(nil)",
    "t_bp75 c[116,95,98,112,55,53]/1(c[91,124,93]/2(a[98],c[91,124,93]/2(a[99],nil)))",
    "t_bp76 c[116,95,98,112,55,54]/1(c[45]/2(i5,V0))",
    "t_bp77 c[116,95,98,112,55,55]/1(i7)",
    "t_bp78 c[116,95,98,112,55,56]/1(i5)",
    "t_bp79 c[116,95,98,112,55,57]/1(i2)",
    "t_bp80 c[116,95,98,112,56,48]/1(c[91,124,93]/2(c[45]/2(a[97],i1),c[91,124,93]/2(c[45]/2(a[98],i2),nil)))",
    "t_bp81 c[116,95,98,112,56,49]/1(c[91,124,93]/2(c[45]/2(a[97],i9),c[91,124,93]/2(c[45]/2(a[98],i2),nil)))",
    "t_bp82 c[116,95,98,112,56,50]/1(c[91,124,93]/2(c[45]/2(a[97],i1),c[91,124,93]/2(c[45]/2(a[98],i2),c[91,124,93]/2(c[45]/2(a[99],i3),nil))))",
    "t_bp83 c[116,95,98,112,56,51]/1(a[116])",
    "t_bp84 c[116,95,98,112,56,52]/1(c[91,124,93]/2(c[45]/2(a[97],i1),nil))",
    "t_bp85 c[116,95,98,112,56,53]/1(c[91,124,93]/2(c[45]/2(a[97],i1),c[91,124,93]/2(c[45]/2(a[98],i2),c[91,124,93]/2(c[45]/2(a[99],i3),c[91,124,93]/2(c[45]/2(a[100],i4),nil)))))",
    "t_bp86 c[116,95,98,112,56,54]/1(c[91,124,93]/2(c[45]/2(a[97],i1),nil))",
    "t_bp87 c[116,95,98,112,56,55]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[100,105,99,116,45,100,97,116,97],a[102,111,111])))",
    "t_bp88 c[116,95,98,112,56,56]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[100,105,99,116,45,100,97,116,97],a[102,111,111])))",
    "t_bp89 c[116,95,98,112,56,57]/1(c[114,97,105,115,101,100]/1(c[100,117,112,108,105,99,97,116,101,95,107,101,121]/1(a[98])))",
    "t_bp90 c[116,95,98,112,57,48]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[108,105,115,116],c[91,124,93]/2(c[45]/2(a[98],i1),V0))))",
    "t_bp91 c[116,95,98,112,57,49]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_bp92 c[116,95,98,112,57,50]/1(a[115,97,109,101])",
    "t_bp93 c[116,95,98,112,57,51]/1(c[91,124,93]/2(c[45]/2(a[120],i1),c[91,124,93]/2(c[45]/2(a[121],i2),nil)))",
    "t_bp94 c[116,95,98,112,57,52]/1(c[91,124,93]/2(c[45]/2(a[97],i3),c[91,124,93]/2(c[45]/2(a[98],i2),c[91,124,93]/2(c[45]/2(a[99],i4),nil))))",
    "t_bp95 c[116,95,98,112,57,53]/1(c[91,124,93]/2(c[45]/2(i1,a[97]),c[91,124,93]/2(c[45]/2(i2,a[98]),c[91,124,93]/2(c[45]/2(i3,a[99]),c[91,124,93]/2(c[45]/2(i4,a[100]),nil)))))",
    "t_bp96 c[116,95,98,112,57,54]/1(c[91,124,93]/2(c[45]/2(a[107,49],i1),c[91,124,93]/2(c[45]/2(a[107,49,48],i10),c[91,124,93]/2(c[45]/2(a[107,49,49],i11),c[91,124,93]/2(c[45]/2(a[107,50],i2),c[91,124,93]/2(c[45]/2(a[107,51],i33),c[91,124,93]/2(c[45]/2(a[107,52],i4),c[91,124,93]/2(c[45]/2(a[107,53],i5),c[91,124,93]/2(c[45]/2(a[107,54],i6),c[91,124,93]/2(c[45]/2(a[107,55],i7),c[91,124,93]/2(c[45]/2(a[107,56],i8),c[91,124,93]/2(c[45]/2(a[107,57],i9),nil))))))))))))",
    "t_bp97 c[116,95,98,112,57,55]/1(a[115,104,97,114,101,100])",
    "t_bp98 c[116,95,98,112,57,56]/1(a[114,101,112,108,97,99,101,100])",
    "t_bp99 c[116,95,98,112,57,57]/1(c[91,124,93]/2(c[45]/2(a[97],i2),nil))",
    "t_bp100 c[116,95,98,112,49,48,48]/1(a[117,110,99,104,97,110,103,101,100])",
    "t_bp101 c[116,95,98,112,49,48,49]/1(c[45]/2(i1,c[91,124,93]/2(c[45]/2(a[98],i2),nil)))",
    "t_bp102 c[116,95,98,112,49,48,50]/1(nil)",
    "t_bp103",
    "t_bp104",
    "t_bp105",
    "t_bp106 c[116,95,98,112,49,48,54]/1(a[102,111,111])",
    "t_bp107 c[116,95,98,112,49,48,55]/1(a[35])",
    "t_bp108 c[116,95,98,112,49,48,56]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[100,105,99,116,45,100,97,116,97],a[102,111,111])))",
    "t_bp109 c[116,95,98,112,49,48,57]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[100,105,99,116,45,100,97,116,97],a[102,111,111])))",
    "t_bp110 c[116,95,98,112,49,49,48]/1(c[91,124,93]/2(c[45]/2(a[97],i1),c[91,124,93]/2(c[45]/2(a[98],i2),nil)))",
    "t_bp111 c[116,95,98,112,49,49,49]/1(c[45]/2(c[45]/2(i2,i4),c[91,124,93]/2(c[45]/2(a[97],i1),c[91,124,93]/2(c[45]/2(a[99],i3),c[91,124,93]/2(c[45]/2(a[101],i5),nil)))))",
    "t_bp112 c[116,95,98,112,49,49,50]/1(a[121,101,115])",
    "t_bp113",
    "t_bp114 c[116,95,98,112,49,49,52]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_bp115 c[116,95,98,112,49,49,53]/1(c[91,124,93]/2(c[91,124,93]/2(c[45]/2(a[98],i2),nil),nil))",
    "t_bp116",
    "t_bp117 c[116,95,98,112,49,49,55]/1(c[91,124,93]/2(c[45]/2(a[99],i3),nil))",
    "t_bp118 c[116,95,98,112,49,49,56]/1(c[45]/2(c[45]/2(a[116,114,117,101],a[97]),i1))",
    "t_bp119 c[116,95,98,112,49,49,57]/1(a[102,111,111])"
]

function _bp_file()::Tuple{String, Vector{String}}
    names = ["t_$(id)" for (id, _) in _BP_CASES]
    text =
        _BP_PROGRAM * join([
            "t_$(id)(R) :- catch(($g), error(SsuE, _), R = raised(SsuE)).\n" for
            (id, g) in _BP_CASES
        ])
    f = joinpath(mktempdir(), "bootpred.pl")
    write(f, text)
    return f, names
end

"The kernel's lines for `names` after consulting `path`, as the driver writes swipl's; the database, for the white-box tests."
function _bp_kernel(path::String, names::Vector{String})
    gd = LK.PL_global_data{_BP}()
    ld = LK.PL_local_data{_BP}(gd)
    st, ball, _ = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * _bp_enc(ball::_BP)]
    for name in names
        proc = LK.isCurrentProcedure(sym_key(_bps(name)), 1, LK.MODULE_user(gd))
        if proc === nothing || !LK.isDefinedProcedure(gd, proc)
            push!(out, "$name undefined")
            continue
        end
        sols = String[]
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 1)
        LK.putSlotValue!(ld, a + 1, mk_var(_BP, LK.fresh_var_keys!(1)), LK.PutVarMap())
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
        )
        n = 0
        while (n += 1) <= 50
            rc = LK.PL_next_solution(gd, ld, qid)
            if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
                push!(
                    sols,
                    _bp_enc(mk_expr(_BP, _BP[_bps(name), lk_answers(ld, (a:a)...)...]))
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

@testset "thread_self/1, with_mutex/2, \$garbage_collect/1, the dict predicates as swipl's (bp01-bp119)" begin
    f, names = _bp_file()
    kl, _, _ = _bp_kernel(f, names)
    @test length(kl) == length(_BP_PINNED)
    for (k, p) in zip(kl, _BP_PINNED)
        k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
        @test k == p
    end
    # not vacuous: `main` answers, the failing rows have no answer, the raised row holds the existence error, the throw row `caught(oops)`
    @test count(l -> occursin("a[109,97,105,110]", l), _BP_PINNED) >= 4            # main
    @test any(l -> l == "t_bp03", _BP_PINNED)                                      # no answer: the row failed
    @test any(
        l -> startswith(l, "t_bp18 ") && occursin("c[114,97,105,115,101,100]", l),
        _BP_PINNED
    )   # raised(…)
    @test any(
        l -> startswith(l, "t_bp12 ") && occursin("c[99,97,117,103,104,116]", l), _BP_PINNED
    )    # caught(…)
    # once/1: bp10 holds [1] alone
    @test any(
        l -> startswith(l, "t_bp10 ") && endswith(l, "c[91,124,93]/2(i1,nil))"), _BP_PINNED
    )
end

@testset "the dict rows are not vacuous (bp27-bp119)" begin
    dict_rows = _BP_PINNED[(1 + 27):end]                                           # the driver's first line is `ok`
    @test length(dict_rows) == 93
    code(t) = "[" * join(Int.(collect(t)), ",") * "]"
    # raised(…) rows: 15 type errors, 5 instantiation errors, 3 duplicate_key (bp35, bp36, bp89)
    @test count(l -> occursin(code("raised"), l), dict_rows) == 23
    @test count(l -> occursin(code("type_error") * "/2", l), dict_rows) == 15
    @test count(l -> occursin(code("instantiation_error"), l), dict_rows) == 5
    @test count(l -> occursin(code("duplicate_key") * "/1", l), dict_rows) == 3
    # rows that fail have no answer after the name
    @test count(l -> occursin(r"^t_bp\d+$", l), dict_rows) == 10
    # the sorted pair list [a-1,b-2] answers 9 rows, and no answer holds a dict
    @test count(
        l -> occursin("c[45]/2(a[97],i1),c[91,124,93]/2(c[45]/2(a[98],i2)", l), dict_rows
    ) == 9
    @test !any(l -> occursin(code("dict") * "/", l), _BP_PINNED)
    # get_dict/3 on a one-pair dict exits deterministically (bp118: Det = true)
    @test any(l -> startswith(l, "t_bp118 ") && occursin(code("true"), l), _BP_PINNED)
    # select_dict/3's rest carries the tag dyndict, written #
    @test any(l -> startswith(l, "t_bp107 ") && endswith(l, "(a[35])"), _BP_PINNED)
end

# KNOWN DIFFERENCE (single-thread form, pl-mutex.c:768-772): swipl 10.1.19 examines the mutex argument (`get_mutex`); the kernel does not.
@testset "with_mutex/2 does not examine its mutex (the single-thread form; swipl's answers in the comments)" begin
    # swipl: with_mutex(_, true) raises instantiation_error; with_mutex(1.5, true) raises type_error(mutex, 1.5)
    f = joinpath(mktempdir(), "bootpred_diff.pl")
    write(
        f,
        "t_d1(R) :- with_mutex(_, R = z).\nt_d2(R) :- with_mutex(1.5, R = z).\n"
    )
    kl, _, _ = _bp_kernel(f, ["t_d1", "t_d2"])
    @test kl[2] == "t_d1 c[116,95,100,49]/1(a[122])"
    @test kl[3] == "t_d2 c[116,95,100,50]/1(a[122])"
end

@testset "the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    # the pinned table is the driver's whole output (the inert-testset guard: an assertion either way)
    @test length(_BP_PINNED) == length(_BP_CASES) + 1
    if swipl === nothing
        @info "BOOTPRED LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        f, names = _bp_file()
        @test _bp_swipl_lines(f, names) == _BP_PINNED
    end
end
