# ORIGINAL: a LIVE differential of the load-time slice of boot/tabling.pl's `:- table` path (TAB1-min; audit D-0387 item 2,
# swipl-devel 10.1.19, cbf4e1896275) against swipl at the pin. Rows tmt: '$tbl_trienode'/1 and '$tbl_is_trienode'/1
# (pl-tabling.c:6253-6277). Groups: tma = the tabling attributes of '$set_predicate_attribute'/3 and '$get_predicate_attribute'/3
# (pl-tabling.c:10299-10393), tmw = '$c_wrap_predicate'/5 called directly (pl-wrap.c:337-403), tmc = clauses added to a wrapped
# predicate while the file loads (boot/tabling.pl:2358 shape; pl-supervisor.c:108-129). The tmw and tmc rows (and the wrapper
# white-box rows at the end, among them T3's opcode rows) need the supervisor opcodes of T3, declared in the same step: UNVERIFIED until the gate.
#   * A PROGRAM consulted by the kernel's loader and cases `t_<id>(R)` run in order in one database, each wrapped in
#     `catch(Goal, error(SsuE, _), R = raised(SsuE))`; the driver is test_event_swipl.jl's (`enc`oded answers).
#   * Every answer line is swipl's, PINNED (swipl 10.1.19-1-gcbf4e189, evidence/TAB1MIN/tm_rows.out, two byte-identical runs); with
#     `swipl` on PATH the live answers are compared with the pins too.
#   * UNVERIFIED on the kernel (nothing was compiled when these rows were written): every kernel answer; the gate decides.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — these built-ins ride the term layer through the FLI (unify, get, strip module)
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TM = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_tms(x) = lk_sym(_TM, Symbol(x))

_tm_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _tm_enc(t::_TM, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _tm_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _tm_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _tm_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_tm_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

const _TM_DRIVER = raw"""
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

function _tm_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _TM_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(
            pipeline(addenv(`swipl -q $f`, "LC_ALL" => "C"); stdin=devnull, stderr=devnull),
            String
        )
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

# the program: `tm_yn/2` turns a goal into `yes`/`no` (the answers stay atoms: the reserved symbol itself is never encoded).
const _TM_PROGRAM = raw"""
:- dynamic tm_hold/1.
:- dynamic tm_ck/2.
:- dynamic tm_x22/1.
tm_yn(G, R) :- ( call(G) -> R = yes ; R = no ).
tm_get(P, A, R) :- ( '$get_predicate_attribute'(P, A, V) -> R = V ; R = none ).
tm_nc(P, N) :- '$get_predicate_attribute'(P, number_of_clauses, N).
tm_wrapb(Head, WName, Closure, call(Wrapped), Body) :-
    Head =.. [P|Args], atom_concat('$wrap$', P, WP), WHead =.. [WP|Args],
    '$c_wrap_predicate'(user:Head, WName, Closure, Wrapped, user:(WHead :- Body)).
tm_wrap(Head, WName, Closure, Wrapped) :- tm_wrapb(Head, WName, Closure, Wrapped, true).
tm_same(A, B, R) :- ( A == B -> R = same ; R = diff ).
tm_w01(1).
tm_w01(2).
tm_w02(1).
tm_w03(1).
tm_w04.
tm_w05(1).
tm_w06(1).
tm_w07(1).
tm_w07b(1).
tm_w11(1).
tm_w12(1).
tm_w13(1).
tm_w13(2).
tm_w14(1, 2).
tm_w15(1, 2, 3).
tm_c01(1).
:- tm_wrap(tm_c01(_), n1, C, _), assertz(tm_ck(c01, C)).
tm_c01(2).
tm_c01(3).
tm_c02(1).
:- tm_wrap(tm_c02(_), n1, C, _), assertz(tm_ck(c02, C)).
tm_c02(2).
tm_c03(1).
:- tm_wrap(tm_c03(_), n1, C, _), assertz(tm_ck(c03a, C)).
tm_c03(2).
:- tm_wrap(tm_c03(_), n2, C, _), assertz(tm_ck(c03b, C)).
tm_c03(3).
:- tm_wrap(tm_c04(_), n1, C, _), assertz(tm_ck(c04, C)).
tm_c04(1).
tm_c04(2).
:- '$set_predicate_attribute'(tm_c05(_), tabled, true), '$set_predicate_attribute'(tm_c05(_), tabled_variant, true),
   tm_wrap(tm_c05(_), table, C, _), assertz(tm_ck(c05, C)).
tm_c05(1).
tm_c05(2).
tm_c06(1).
:- tm_c06(_).
:- tm_wrap(tm_c06(_), n1, C, _), assertz(tm_ck(c06, C)).
tm_c06(2).
"""

# tmt: '$tbl_trienode'/1 and '$tbl_is_trienode'/1.
const _TM_CASES = [
    ("tmt01", raw"'$tbl_trienode'(X), ( atom(X) -> R = atom ; R = notatom )"),
    ("tmt02", raw"'$tbl_trienode'(X), ( atomic(X) -> R = atomic ; R = notatomic )"),
    ("tmt03", raw"'$tbl_trienode'(X), tm_yn('$tbl_is_trienode'(X), R)"),
    ("tmt04", raw"tm_yn('$tbl_is_trienode'(a), R)"),
    ("tmt05", raw"tm_yn('$tbl_is_trienode'(trienode), R)"),
    ("tmt06", raw"tm_yn('$tbl_is_trienode'(_), R)"),
    ("tmt07", raw"tm_yn('$tbl_is_trienode'(f(a)), R)"),
    ("tmt08", raw"tm_yn('$tbl_is_trienode'([]), R)"),
    ("tmt09", raw"tm_yn('$tbl_is_trienode'(1), R)"),
    (
        "tmt10",
        raw"'$tbl_trienode'(X), '$tbl_trienode'(Y), ( X == Y -> R = same ; R = diff )"
    ),
    ("tmt11", raw"'$tbl_trienode'(X), ( X == trienode -> R = eqtext ; R = neqtext )"),
    ("tmt12", raw"tm_yn('$tbl_trienode'(a), R)"),
    ("tmt13", raw"tm_yn('$tbl_trienode'(trienode), R)"),
    (
        "tmt14",
        raw"'$tbl_trienode'(X), Y = f(X), arg(1, Y, Z), tm_yn('$tbl_is_trienode'(Z), R)"
    ),
    ("tmt15", raw"'$tbl_trienode'(X), compare(O, X, aaa), R = O"),
    ("tmt16", raw"'$tbl_trienode'(X), compare(O, X, []), R = O"),
    ("tmt17", raw"'$tbl_trienode'(X), ( var(X) -> R = var ; R = nonvar )"),
    ("tmt18", raw"'$tbl_trienode'(X), copy_term(X, Y), tm_yn('$tbl_is_trienode'(Y), R)"),
    ("tmt19", raw"findall(X, '$tbl_trienode'(X), L), length(L, R)"),
    (
        "tmt20",
        raw"retractall(tm_hold(_)), '$tbl_trienode'(X), assertz(tm_hold(X)), tm_hold(Y), tm_yn('$tbl_is_trienode'(Y), R)"
    ),
    (
        "tmt21",
        raw"'$get_predicate_attribute'(system:'$tbl_trienode'(_), foreign, V), R = V"
    ),
    (
        "tmt22",
        raw"'$get_predicate_attribute'(system:'$tbl_is_trienode'(_), foreign, V), R = V"
    ),
    # tma: the tabling attributes of '$set_predicate_attribute'/3 and '$get_predicate_attribute'/3 (pl-tabling.c:10299-10393)
    ("tma01", raw"tm_get(tm_a01(_), tabled, R)"),
    (
        "tma02",
        raw"'$set_predicate_attribute'(tm_a02(_), tabled, true), tm_get(tm_a02(_), tabled, R)"
    ),
    (
        "tma03",
        raw"'$set_predicate_attribute'(tm_a03(_), tabled, true), tm_get(tm_a03(_), tabled_variant, R)"
    ),
    (
        "tma04",
        raw"'$set_predicate_attribute'(tm_a04(_), tabled_variant, true), tm_get(tm_a04(_), tabled_variant, R)"
    ),
    (
        "tma05",
        raw"'$set_predicate_attribute'(tm_a05(_), tabled, true), '$set_predicate_attribute'(tm_a05(_), tabled, false), tm_get(tm_a05(_), tabled, R)"
    ),
    ("tma06", raw"'$set_predicate_attribute'(tm_a06(_), tabled, foo)"),
    ("tma07", raw"'$set_predicate_attribute'(tm_a07(_), tabled, _)"),
    (
        "tma08",
        raw"'$set_predicate_attribute'(tm_a08(_), tabled, 1), tm_get(tm_a08(_), tabled, R)"
    ),
    (
        "tma09",
        raw"'$set_predicate_attribute'(tm_a09(_), incremental, true), tm_get(tm_a09(_), incremental, R)"
    ),
    (
        "tma10",
        raw"'$set_predicate_attribute'(tm_a10(_), incremental, true), '$set_predicate_attribute'(tm_a10(_), incremental, false), tm_get(tm_a10(_), incremental, R)"
    ),
    (
        "tma11",
        raw"'$set_predicate_attribute'(tm_a11(_), monotonic, true), tm_get(tm_a11(_), monotonic, M), tm_get(tm_a11(_), opaque, O), tm_get(tm_a11(_), tshared, S), R = r(M, O, S)"
    ),
    (
        "tma12",
        raw"'$set_predicate_attribute'(tm_a12(_), tshared, true), '$set_predicate_attribute'(tm_a12(_), opaque, true), '$set_predicate_attribute'(tm_a12(_), lazy, true), tm_get(tm_a12(_), tshared, S), tm_get(tm_a12(_), opaque, O), tm_get(tm_a12(_), lazy, L), R = r(S, O, L)"
    ),
    (
        "tma13",
        raw"'$set_predicate_attribute'(tm_a13(_), abstract, infinite), tm_get(tm_a13(_), abstract, R)"
    ),
    (
        "tma14",
        raw"'$set_predicate_attribute'(tm_a14(_), abstract, 5), tm_get(tm_a14(_), abstract, R)"
    ),
    ("tma15", raw"'$set_predicate_attribute'(tm_a15(_), abstract, -1)"),
    ("tma16", raw"'$set_predicate_attribute'(tm_a16(_), abstract, foo)"),
    ("tma17", raw"'$set_predicate_attribute'(tm_a17(_), abstract, _)"),
    (
        "tma18",
        raw"'$set_predicate_attribute'(tm_a18(_), subgoal_abstract, 3), '$set_predicate_attribute'(tm_a18(_), answer_abstract, 4), tm_get(tm_a18(_), subgoal_abstract, S), tm_get(tm_a18(_), answer_abstract, A), tm_get(tm_a18(_), abstract, B), R = r(S, A, B)"
    ),
    (
        "tma19",
        raw"'$set_predicate_attribute'(tm_a19(_), max_answers, 7), tm_get(tm_a19(_), max_answers, A), '$set_predicate_attribute'(tm_a19(_), max_answers, infinite), tm_get(tm_a19(_), max_answers, B), R = r(A, B)"
    ),
    (
        "tma20",
        raw"'$set_predicate_attribute'(tm_a20(_), incremental, true), tm_get(tm_a20(_), tabled, R)"
    ),
    (
        "tma21",
        raw"'$set_predicate_attribute'(tm_a21(_), tabled, true), tm_get(tm_a21(_), tabled, T), tm_get(tm_a21(_), defined, D), R = r(T, D)"
    ),
    (
        "tma22",
        raw"'$set_predicate_attribute'(tm_x22(_), tabled, true), '$set_predicate_attribute'(tm_x22(_), abstract, 5), abolish(tm_x22/1), tm_get(tm_x22(_), tabled, T), tm_get(tm_x22(_), abstract, A), R = r(T, A)"
    ),
    (
        "tma23",
        raw"'$set_predicate_attribute'(tm_a23(_), tabled, true), tm_get(tm_a23(_), incremental, I), tm_get(tm_a23(_), monotonic, M), R = r(I, M)"
    ),
    # tmw: '$c_wrap_predicate'/5 called directly (the wrapper clause is `$wrap$P(Args) :- Body`; the closure is a blob)
    (
        "tmw01",
        raw"tm_wrap(tm_w01(_), n1, _, _), tm_nc(tm_w01(_), A), tm_nc('$wrap$tm_w01'(_), B), R = r(A, B)"
    ),
    ("tmw02", raw"tm_wrap(tm_w02(_), n1, C, _), blob(C, T), R = T"),
    (
        "tmw03",
        raw"tm_wrap(tm_w03(P), n1, _, call(W)), functor(W, N, A), blob(N, T), arg(1, W, X), tm_same(X, P, S), R = r(A, T, S)"
    ),
    (
        "tmw04",
        raw"tm_wrap(tm_w04, n1, C, call(W)), blob(W, T), tm_same(W, C, S), R = r(T, S)"
    ),
    (
        "tmw05",
        raw"tm_wrap(tm_w05(_), n1, C1, call(W1)), tm_wrap(tm_w05(_), n1, C2, call(W2)), tm_same(C1, C2, S), functor(W1, N1, _), functor(W2, N2, _), tm_same(N1, N2, S2), tm_nc('$wrap$tm_w05'(_), N), R = r(S, S2, N)"
    ),
    (
        "tmw06",
        raw"tm_wrap(tm_w06(_), n1, C1, _), tm_wrap(tm_w06(_), n2, C2, _), tm_same(C1, C2, S), tm_nc('$wrap$tm_w06'(_), N), R = r(S, N)"
    ),
    (
        "tmw07",
        raw"tm_wrap(tm_w07(_), n1, C1, _), tm_wrap(tm_w07b(_), n1, C2, _), tm_same(C1, C2, R)"
    ),
    (
        "tmw08",
        raw"'$c_wrap_predicate'(user:tm_w08(_), 1, _, _, user:('$wrap$tm_w08'(_) :- true))"
    ),
    (
        "tmw09",
        raw"'$c_wrap_predicate'(user:tm_w09(_), _, _, _, user:('$wrap$tm_w09'(_) :- true))"
    ),
    ("tmw10", raw"'$c_wrap_predicate'(_, n1, _, _, user:('$wrap$tm_w10'(_) :- true))"),
    ("tmw11", raw"'$c_wrap_predicate'(user:tm_w11(_), n1, _, _, _)"),
    (
        "tmw12",
        raw"tm_wrapb(tm_w12(_), n1, C, call(W), tm_h(C, W)), clause('$wrap$tm_w12'(Z), B), B = tm_h(C2, W2), tm_same(C2, C, S1), functor(W2, N2, A2), functor(W, N, _), tm_same(N2, N, S2), arg(1, W2, X), tm_same(X, Z, S3), R = r(S1, S2, A2, S3)"
    ),
    (
        "tmw13",
        raw"tm_wrap(tm_w13(_), n1, _, _), findall(X, clause(tm_w13(X), true), L), R = L"
    ),
    # tmw14, tmw15: a wrapped predicate of arity 2 and 3 with DIFFERENT arguments: unify_wrapped (pl-wrap.c) copies argument i of the
    # head to argument i of the closure compound (every other tmw head has arity 1, where the argument position cannot differ)
    (
        "tmw14",
        raw"tm_wrap(tm_w14(P, Q), n1, _, call(W)), functor(W, _, A), arg(1, W, X), arg(2, W, Y), tm_same(X, P, S1), tm_same(Y, Q, S2), tm_same(X, Y, S3), R = r(A, S1, S2, S3)"
    ),
    (
        "tmw15",
        raw"tm_wrap(tm_w15(a, P, c), n1, _, call(W)), arg(1, W, X1), arg(2, W, X2), arg(3, W, X3), tm_same(X2, P, S), R = r(X1, S, X3)"
    ),
    # tmc: clauses added to a wrapped predicate while the file loads (boot/tabling.pl:2358 shape); the program wraps in a directive
    ("tmc01", raw"tm_nc(tm_c01(_), A), tm_nc('$wrap$tm_c01'(_), B), R = r(A, B)"),
    (
        "tmc02",
        raw"tm_ck(c02, C0), tm_wrap(tm_c02(_), n1, C1, _), tm_same(C0, C1, S), tm_nc('$wrap$tm_c02'(_), N), R = r(S, N)"
    ),
    (
        "tmc03",
        raw"tm_ck(c03a, A0), tm_ck(c03b, B0), tm_wrap(tm_c03(_), n1, A1, _), tm_wrap(tm_c03(_), n2, B1, _), tm_same(A0, A1, S1), tm_same(B0, B1, S2), tm_same(A0, B0, S3), tm_nc('$wrap$tm_c03'(_), N), R = r(S1, S2, S3, N)"
    ),
    ("tmc04", raw"tm_nc(tm_c04(_), A), tm_nc('$wrap$tm_c04'(_), B), R = r(A, B)"),
    (
        "tmc05",
        raw"tm_get(tm_c05(_), tabled, T), tm_get(tm_c05(_), tabled_variant, V), tm_nc(tm_c05(_), A), tm_nc('$wrap$tm_c05'(_), B), R = r(T, V, A, B)"
    ),
    ("tmc06", raw"tm_ck(c05, C0), tm_wrap(tm_c05(_), table, C1, _), tm_same(C0, C1, R)"),
    (
        "tmc07",
        raw"tm_ck(c06, C0), tm_wrap(tm_c06(_), n1, C1, _), tm_same(C0, C1, S), tm_nc(tm_c06(_), A), tm_nc('$wrap$tm_c06'(_), B), R = r(S, A, B)"
    )
]

# the pins are filled by evidence/TAB1MIN/gen_rows.py --fill from swipl's output
const _TM_PINNED = [
    "ok",
    "t_tmt01 c[116,95,116,109,116,48,49]/1(a[110,111,116,97,116,111,109])",
    "t_tmt02 c[116,95,116,109,116,48,50]/1(a[97,116,111,109,105,99])",
    "t_tmt03 c[116,95,116,109,116,48,51]/1(a[121,101,115])",
    "t_tmt04 c[116,95,116,109,116,48,52]/1(a[110,111])",
    "t_tmt05 c[116,95,116,109,116,48,53]/1(a[110,111])",
    "t_tmt06 c[116,95,116,109,116,48,54]/1(a[110,111])",
    "t_tmt07 c[116,95,116,109,116,48,55]/1(a[110,111])",
    "t_tmt08 c[116,95,116,109,116,48,56]/1(a[110,111])",
    "t_tmt09 c[116,95,116,109,116,48,57]/1(a[110,111])",
    "t_tmt10 c[116,95,116,109,116,49,48]/1(a[115,97,109,101])",
    "t_tmt11 c[116,95,116,109,116,49,49]/1(a[110,101,113,116,101,120,116])",
    "t_tmt12 c[116,95,116,109,116,49,50]/1(a[110,111])",
    "t_tmt13 c[116,95,116,109,116,49,51]/1(a[110,111])",
    "t_tmt14 c[116,95,116,109,116,49,52]/1(a[121,101,115])",
    "t_tmt15 c[116,95,116,109,116,49,53]/1(a[60])",
    "t_tmt16 c[116,95,116,109,116,49,54]/1(a[62])",
    "t_tmt17 c[116,95,116,109,116,49,55]/1(a[110,111,110,118,97,114])",
    "t_tmt18 c[116,95,116,109,116,49,56]/1(a[121,101,115])",
    "t_tmt19 c[116,95,116,109,116,49,57]/1(i1)",
    "t_tmt20 c[116,95,116,109,116,50,48]/1(a[121,101,115])",
    "t_tmt21 c[116,95,116,109,116,50,49]/1(i1)",
    "t_tmt22 c[116,95,116,109,116,50,50]/1(i1)",
    "t_tma01 c[116,95,116,109,97,48,49]/1(a[110,111,110,101])",
    "t_tma02 c[116,95,116,109,97,48,50]/1(i1)",
    "t_tma03 c[116,95,116,109,97,48,51]/1(i0)",
    "t_tma04 c[116,95,116,109,97,48,52]/1(i1)",
    "t_tma05 c[116,95,116,109,97,48,53]/1(i0)",
    "t_tma06 c[116,95,116,109,97,48,54]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[98,111,111,108],a[102,111,111])))",
    "t_tma07 c[116,95,116,109,97,48,55]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_tma08 c[116,95,116,109,97,48,56]/1(i1)",
    "t_tma09 c[116,95,116,109,97,48,57]/1(i1)",
    "t_tma10 c[116,95,116,109,97,49,48]/1(i0)",
    "t_tma11 c[116,95,116,109,97,49,49]/1(c[114]/3(i1,i0,i0))",
    "t_tma12 c[116,95,116,109,97,49,50]/1(c[114]/3(i1,i1,i1))",
    "t_tma13 c[116,95,116,109,97,49,51]/1(a[110,111,110,101])",
    "t_tma14 c[116,95,116,109,97,49,52]/1(i5)",
    "t_tma15 c[116,95,116,109,97,49,53]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[110,111,116,95,108,101,115,115,95,116,104,97,110,95,122,101,114,111],i-1)))",
    "t_tma16 c[116,95,116,109,97,49,54]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],a[102,111,111])))",
    "t_tma17 c[116,95,116,109,97,49,55]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_tma18 c[116,95,116,109,97,49,56]/1(c[114]/3(i3,i4,a[110,111,110,101]))",
    "t_tma19 c[116,95,116,109,97,49,57]/1(c[114]/2(i7,a[110,111,110,101]))",
    "t_tma20 c[116,95,116,109,97,50,48]/1(i0)",
    "t_tma21 c[116,95,116,109,97,50,49]/1(c[114]/2(i1,i0))",
    "t_tma22 c[116,95,116,109,97,50,50]/1(c[114]/2(i0,a[110,111,110,101]))",
    "t_tma23 c[116,95,116,109,97,50,51]/1(c[114]/2(i0,i0))",
    "t_tmw01 c[116,95,116,109,119,48,49]/1(c[114]/2(i2,i1))",
    "t_tmw02 c[116,95,116,109,119,48,50]/1(a[99,108,111,115,117,114,101])",
    "t_tmw03 c[116,95,116,109,119,48,51]/1(c[114]/3(i1,a[99,108,111,115,117,114,101],a[115,97,109,101]))",
    "t_tmw04 c[116,95,116,109,119,48,52]/1(c[114]/2(a[99,108,111,115,117,114,101],a[115,97,109,101]))",
    "t_tmw05 c[116,95,116,109,119,48,53]/1(c[114]/3(a[115,97,109,101],a[115,97,109,101],i1))",
    "t_tmw06 c[116,95,116,109,119,48,54]/1(c[114]/2(a[100,105,102,102],i2))",
    "t_tmw07 c[116,95,116,109,119,48,55]/1(a[100,105,102,102])",
    "t_tmw08 c[116,95,116,109,119,48,56]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],i1)))",
    "t_tmw09 c[116,95,116,109,119,48,57]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_tmw10 c[116,95,116,109,119,49,48]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_tmw11 c[116,95,116,109,119,49,49]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_tmw12 c[116,95,116,109,119,49,50]/1(c[114]/4(a[115,97,109,101],a[115,97,109,101],i1,a[115,97,109,101]))",
    "t_tmw13 c[116,95,116,109,119,49,51]/1(c[91,124,93]/2(i1,c[91,124,93]/2(i2,nil)))",
    "t_tmw14 c[116,95,116,109,119,49,52]/1(c[114]/4(i2,a[115,97,109,101],a[115,97,109,101],a[100,105,102,102]))",
    "t_tmw15 c[116,95,116,109,119,49,53]/1(c[114]/3(a[97],a[115,97,109,101],a[99]))",
    "t_tmc01 c[116,95,116,109,99,48,49]/1(c[114]/2(i3,i1))",
    "t_tmc02 c[116,95,116,109,99,48,50]/1(c[114]/2(a[115,97,109,101],i1))",
    "t_tmc03 c[116,95,116,109,99,48,51]/1(c[114]/4(a[115,97,109,101],a[115,97,109,101],a[100,105,102,102],i2))",
    "t_tmc04 c[116,95,116,109,99,48,52]/1(c[114]/2(i2,i1))",
    "t_tmc05 c[116,95,116,109,99,48,53]/1(c[114]/4(i1,i1,i2,i1))",
    "t_tmc06 c[116,95,116,109,99,48,54]/1(a[115,97,109,101])",
    "t_tmc07 c[116,95,116,109,99,48,55]/1(c[114]/3(a[115,97,109,101],i2,i1))"
]

function _tm_file()::Tuple{String, Vector{String}}
    names = ["t_$(id)" for (id, _) in _TM_CASES]
    text =
        _TM_PROGRAM * join([
            "t_$(id)(R) :- catch(($g), error(SsuE, _), R = raised(SsuE)).\n" for
            (id, g) in _TM_CASES
        ])
    f = joinpath(mktempdir(), "tabling_min.pl")
    write(f, text)
    return f, names
end

"A fresh kernel with the file consulted: `(gd, ld, first line of the driver's output)`."
function _tm_load(path::String)
    gd = LK.PL_global_data{_TM}()
    ld = LK.PL_local_data{_TM}(gd)
    st, ball, _ = LK.load_file!(gd, ld, path)
    return gd, ld, (st === :ok ? "ok" : "exc " * _tm_enc(ball::_TM))
end

"The driver's line for `pred/1` (every answer, at most 50), the functor written as `asname`."
function _tm_ask(gd, ld, pred::String, asname::String=pred)::String
    proc = LK.isCurrentProcedure(sym_key(_tms(pred)), 1, LK.MODULE_user(gd))
    (proc === nothing || !LK.isDefinedProcedure(gd, proc)) && return "$asname undefined"
    sols = String[]
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 1)
    LK.putSlotValue!(ld, a + 1, mk_var(_TM, LK.fresh_var_keys!(1)), LK.PutVarMap())
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    n = 0
    while (n += 1) <= 50
        rc = LK.PL_next_solution(gd, ld, qid)
        if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
            push!(
                sols, _tm_enc(mk_expr(_TM, _TM[_tms(asname), lk_answers(ld, (a:a)...)...]))
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
    return asname * join(" " .* sols)
end

"The kernel's lines for `names` after consulting `path`."
function _tm_kernel(path::String, names::Vector{String})
    gd, ld, st = _tm_load(path)
    out = [st]
    for name in names
        push!(out, _tm_ask(gd, ld, name))
    end
    return out, gd, ld
end

"The definition of `name/arity` in the user module of `gd`."
function _tm_def(gd, name::String, arity::Int=1)
    proc = LK.isCurrentProcedure(sym_key(_tms(name)), arity, LK.MODULE_user(gd))
    @assert proc !== nothing
    return proc.definition
end

"Whether `def`'s supervisor is a wrapper: the first instruction after the prefix is a wrapper opcode."
_tm_wrapped(def) = LK.isCallWrapper(def.codes[LK.skipWrapperPrefix(def.codes)])

"Call `name/1` of the user module once with a fresh variable; the Julia exception the run loop raised, or `nothing`."
function _tm_call_error(gd, ld, name::String)
    proc = LK.isCurrentProcedure(sym_key(_tms(name)), 1, LK.MODULE_user(gd))
    @assert proc !== nothing
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 1)
    LK.putSlotValue!(ld, a + 1, mk_var(_TM, LK.fresh_var_keys!(1)), LK.PutVarMap())
    qid = LK.PL_open_query(gd, ld, nothing, LK.PL_Q_NORMAL, proc, a)
    err = try
        LK.PL_next_solution(gd, ld, qid)
        nothing
    catch e
        e
    end
    LK.PL_close_foreign_frame(ld, fid)
    return err
end

@testset "tabling minimum as swipl's (tmt, tma, tmw, tmc)" begin
    f, names = _tm_file()
    kl, gd, ld = _tm_kernel(f, names)
    @test length(kl) == length(_TM_PINNED)
    for (k, p) in zip(kl, _TM_PINNED)
        k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
        @test k == p
    end

    # LK-only white-box rows (swipl keeps the supervisor in C structures): UNVERIFIED on the kernel, the gate decides.
    @testset "wrapper supervisors (LK-only white-box)" begin
        # T4: '$c_wrap_predicate' installed a wrapper that names its closure; the closure wraps the definition itself
        d01 = _tm_def(gd, "tm_w01")
        i = LK.skipWrapperPrefix(d01.codes)
        @test d01.codes[i] == LK.S_CALLWRAPPER
        c = LK.closure_of_word(gd, d01.codes[i + 2])
        @test c !== nothing
        @test c.predicate === d01
        @test c.supervisor === d01.code_data.virgin             # the wrapped predicate had its virgin supervisor
        @test length(d01.codes_crefs) >= 1
        # wrapper_vmi: the `table` wrapper of a variant tabled predicate is S_TABLED, every other wrapper S_CALLWRAPPER
        d05 = _tm_def(gd, "tm_c05")
        @test d05.codes[LK.skipWrapperPrefix(d05.codes)] == LK.S_TABLED
        d01c = _tm_def(gd, "tm_c01")
        @test d01c.codes[LK.skipWrapperPrefix(d01c.codes)] == LK.S_CALLWRAPPER
        # T5: the clauses added after the wrap (tmc01) left the wrapper in place and reset the wrapped supervisor
        # (this row FAILS without the wrapper branch of freeCodesDefinition!: the supervisor would be the virgin one)
        @test _tm_wrapped(d01c)
        ic = LK.skipWrapperPrefix(d01c.codes)
        cc = LK.closure_of_word(gd, d01c.codes[ic + 2])::LK.closure
        @test cc.supervisor === d01c.code_data.virgin
        @test isempty(cc.supervisor_crefs)
        @test d01c.codes !== d01c.code_data.virgin
        # T5: two wrappers (tmc03): both found by name after the clause adds, an unknown name is not found
        d03 = _tm_def(gd, "tm_c03")
        @test _tm_wrapped(d03)
        n1 = LK._atom_word!(ld, _tms("n1"))
        n2 = LK._atom_word!(ld, _tms("n2"))
        n3 = LK._atom_word!(ld, _tms("n3"))
        @test LK.find_wrapper(gd, d03, n1) !== nothing
        @test LK.find_wrapper(gd, d03, n2) !== nothing
        @test LK.find_wrapper(gd, d03, n3) === nothing
        @test LK.find_wrapper(gd, d03, n2)[1] === d03.codes       # the last wrapper is the outer one
        @test LK.find_wrapper(gd, d03, n1)[1] !== d03.codes       # the first sits in the closure of the outer one
        # Q-A (audit ruling): without the database a wrapped predicate is refused by name; an unwrapped one is reset as before
        @test_throws LK.NotPortedError LK.freeCodesDefinition!(d01c, true)
        @test _tm_wrapped(d01c)                                   # the refusal changed nothing
        LK.freeCodesDefinition!(gd, d01c, true)                   # with the database the wrapper stays
        @test _tm_wrapped(d01c)
        # T5: a predicate that RAN before it was wrapped (tmc07) has its wrapped supervisor reset by the clause add
        d06 = _tm_def(gd, "tm_c06")
        c06 = LK.closure_of_word(
            gd, d06.codes[LK.skipWrapperPrefix(d06.codes) + 2]
        )::LK.closure
        @test c06.supervisor === d06.code_data.virgin
        @test isempty(c06.supervisor_crefs)                       # the reset also drops the side table of the old supervisor
        # T4: the second wrap of a name (tmw05) installs the NEW wrapper clause in the side table, the old one is gone
        d05w = _tm_def(gd, "tm_w05")
        j = LK.skipWrapperPrefix(d05w.codes)
        wd = _tm_def(gd, "\$wrap\$tm_w05")
        @test d05w.codes_crefs[Int(d05w.codes[j + 1])].clause ===
            wd.impl_clauses.last_clause.clause   # the newest clause
        @test wd.impl_clauses.number_of_clauses == 1                          # the old one was retracted
    end

    @testset "skipWrapperPrefix and isCallWrapper (LK-only)" begin
        c(x...) = LK.code[x...]
        @test LK.skipWrapperPrefix(c(LK.S_CALLWRAPPER, 1, 0, 0)) == 1
        @test LK.skipWrapperPrefix(c(LK.S_MQUAL, 7, LK.S_TABLED, 1, 0, 0)) == 3
        @test LK.skipWrapperPrefix(c(LK.S_LMQUAL, 7, LK.S_TABLED, 1, 0, 0)) == 3
        @test LK.skipWrapperPrefix(c(LK.S_SSU_DET, LK.S_CALLWRAPPER, 1, 0, 0)) == 2
        @test LK.skipWrapperPrefix(
            c(LK.S_MQUAL, 7, LK.S_SSU_DET, LK.S_CALLWRAPPER, 1, 0, 0)
        ) == 4
        @test LK.skipWrapperPrefix(c(LK.S_MQUAL, 7, LK.S_VIRGIN)) == 3
        @test LK.skipWrapperPrefix(c(LK.S_MQUAL, 7, LK.S_CALLWRAPPER, 1, 0, 0), 3) == 3
        @test LK.isCallWrapper(LK.S_CALLWRAPPER)
        @test LK.isCallWrapper(LK.S_TABLED)
        @test !LK.isCallWrapper(LK.S_VIRGIN)
        @test !LK.isCallWrapper(LK.S_TRUSTME)
        @test !LK.isCallWrapper(LK.S_MQUAL)
    end

    # T3: the three opcodes, the shared `wrapper` block and the run loop's named refusals (swipl keeps all of it in C: LK-only).
    # UNVERIFIED on the kernel (nothing was compiled when these rows were written): the gate decides.
    @testset "wrapper opcodes and the wrapper block (T3, LK-only)" begin
        # pl-vmi.c order: S_WRAP (3560) before S_CALLWRAPPER (3624) before S_TABLED (3644); appended after B_ARG_VF
        @test LK.S_WRAP == LK.B_ARG_VF + 1
        @test LK.S_CALLWRAPPER == LK.S_WRAP + 1
        @test LK.S_TABLED == LK.S_CALLWRAPPER + 1
        @test LK.code(length(LK._CODE_TABLE) - 1) >= LK.S_TABLED     # the table has their rows
        z = (0x00, 0x00, 0x00, 0x00)
        iw = LK.codeTable(LK.S_WRAP)
        @test iw.name === :S_WRAP && iw.arguments == 0 && iw.flags == 0x00 &&
            iw.argtype == z
        want = (LK.CA1_CLAUSEREF, LK.CA1_DATA, LK.CA1_DATA, 0x00)
        for (op, nm) in ((LK.S_CALLWRAPPER, :S_CALLWRAPPER), (LK.S_TABLED, :S_TABLED))
            ic = LK.codeTable(op)
            @test ic.name === nm && ic.arguments == 3 && ic.flags == 0x00 &&
                ic.argtype == want
        end
        # every operand word the wrapper supervisors write is counted: a decoder that steps `1 + arguments` lands after them
        d01 = _tm_def(gd, "tm_w01")
        wi = LK.skipWrapperPrefix(d01.codes)
        @test wi + 1 + LK.codeTable(d01.codes[wi]).arguments == length(d01.codes) + 1
        # the shared block (pl-supervisor.c MAKE_SV1(wrapper, S_WRAP)) is the closure copy's supervisor and is known by identity
        cd = d01.code_data
        @test cd.wrapper == LK.code[LK.S_WRAP, LK.I_EXIT]
        @test all(
            b -> cd.wrapper !== b,
            (cd.exit, cd.virgin, cd.undef, cd.dynamic, cd.multifile, cd.staticp)
        )
        @test LK._shared_supervisor(cd, cd.wrapper)
        @test !LK._shared_supervisor(cd, LK.code[LK.S_WRAP, LK.I_EXIT])
        c01 = LK.closure_of_word(gd, d01.codes[wi + 2])::LK.closure
        @test c01.def.codes === cd.wrapper
        # the run loop executes them as named refusals (not as unknown instructions): the owner is named
        for nm in (:S_WRAP, :S_CALLWRAPPER, :S_TABLED)
            @test nm in LK.VMI_RUN
        end
        e = _tm_call_error(gd, ld, "tm_w02")                      # wrapped by tmw02: S_CALLWRAPPER
        @test e isa LK.NotPortedError && occursin("S_CALLWRAPPER", e.what) &&
            e.step == "WRAP1"
        @test ld.query == 0 && ld.nqueries == 0
        e = _tm_call_error(gd, ld, "tm_c05")                      # the `table` wrapper of a variant tabled predicate: S_TABLED
        @test e isa LK.NotPortedError && occursin("S_TABLED", e.what) && e.step == "TAB1"
        @test ld.query == 0 && ld.nqueries == 0
        d03 = _tm_def(gd, "tm_w03")                               # S_WRAP is a closure copy's supervisor: enter it by hand
        saved = d03.codes
        d03.codes = d03.code_data.wrapper
        e = _tm_call_error(gd, ld, "tm_w03")
        d03.codes = saved
        @test e isa LK.NotPortedError && occursin("S_WRAP", e.what) && e.step == "WRAP1"
        @test ld.query == 0 && ld.nqueries == 0
        # the first declared instruction outside the dispatch stays an unknown-instruction refusal (test/foreign/test_query.jl)
        @test !(:I_NOP in LK.VMI_RUN)
    end
end

@testset "the tabling minimum rows are not vacuous" begin
    @test _TM_PINNED[1] == "ok"
    @test length(_TM_PINNED) == length(_TM_CASES) + 1
    for pre in ("tmt", "tma", "tmw", "tmc")
        ids = [id for (id, _) in _TM_CASES if startswith(id, pre)]
        @test !isempty(ids)
        @test length([l for l in _TM_PINNED if any(id -> startswith(l, "t_$id "), ids)]) ==
            length(ids)
    end
    line(id) = only(filter(l -> startswith(l, "t_$id "), _TM_PINNED))
    ans(id) = split(line(id), " "; limit=2)[2]
    @test line("tmt03") != line("tmt04")          # the node is recognised, other terms are not
    @test line("tmt10") != line("tmt11")          # the node is the same symbol each time, not the text atom
    @test ans("tma01") != ans("tma20")            # no properties at all (the getter fails) vs properties with the flag clear (0)
    @test ans("tma02") != ans("tma05")            # set, then cleared
    @test ans("tma13") != ans("tma14")            # `infinite` is not unified, an integer is
    @test ans("tma23") != ans("tma01")            # properties allocated by `tabled`: incremental and monotonic read 0
    @test ans("tma22") != ans("tma02")            # abolish clears the properties
    @test ans("tmw05") != ans("tmw06")            # the same name finds its wrapper, another name adds one
    @test occursin(_tm_codes("diff"), ans("tmw07"))          # a closure is per predicate, even for the same wrapper name
    @test occursin(_tm_codes("same"), ans("tmc02")) &&
        occursin(_tm_codes("same"), ans("tmc06"))   # the wrapper survived the clause adds (T5)
    @test ans("tmc03") != ans("tmc02")            # two layers: both found, but the layers differ
end

@testset "the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    @test length(_TM_PINNED) == length(_TM_CASES) + 1
    if swipl === nothing
        @info "TAB1MIN LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        f, names = _tm_file()
        @test _tm_swipl_lines(f, names) == _TM_PINNED
    end
end
