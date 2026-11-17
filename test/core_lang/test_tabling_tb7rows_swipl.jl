# ORIGINAL: LIVE kill rows for the MONOTONIC half of the incremental dependency graph (TAB1 TB7-ROWS2) against swipl at the pin (swipl-devel 18168e62,
# 10.1.20). They carry the rows that tools/mutants/TB7.py could not name before: the dependency_error of `'$idg_add_monotonic_dep'/3` (TB7R-DE1 .. DE4), the
# collect/propagate flags (TB7R-CO1, CO2) and the lazy / queue / forced states of a monotonic table, read through the IDG built-ins. One program text per group,
# each group in a FRESH database:
#   * DEPERR    `'$idg_add_monotonic_dep'/3` between two tables, one or both without an IDG node: dependency_error(Dst, monotonic(Src)) unless the target is opaque.
#   * COLLECT   `'$tbl_collect_mono_dep'/0`, `'$tbl_propagate_start'/1`, `'$tbl_propagate_end'/1`, in a monotonic body, a plain body, nested.
#   * LAZY      an eager and two lazy monotonic tables over one monotonic dynamic predicate: status, queues (`'$idg_mono_affects_lazy'/5`), invalidation,
#               forcing (`'$idg_forced'/1`), the index (`'$idg_mono_index'/2`).
#   * QUEUE     the answer queue of a lazy dependency: `'$idg_mono_empty_queue'/2` (a count up to the queue length, zero, negative), a retract of a queued
#               answer, `'$idg_mono_invalidate'/1`, `'$mono_reeval_prepare'/2` and `'$mono_reeval_done'/3` by hand.
#   * SUBMONO   `as (subsumptive, monotonic)`: an instance call reuses the complete table, a new clause reaches it and its monotonic consumer. The number of
#               tables is counted with `'$tbl_local_variant_table'/1` and `trie_gen/3` (the body of current_table/2, which needs `'$table_mode'` too).
# Cases `t_<id>(R)` run in order in ONE database, each wrapped in `catch(Goal, error(SsuE, _), R = raised(SsuE))`; the driver is test_tabling_tb6rows_swipl.jl's
# (`enc`oded answers), the program text the same on both sides. Every answer line is swipl's, PINNED: swipl 10.1.20, two byte-identical runs, printed by
# evidence/TB7ROWS/gen/ (groups.py: the programs and cases, emit.py: the constants below, pins.txt: the output); with `swipl` on PATH the live answers are compared
# with the pins too. A trie blob is never printed. `'$idg_mono_empty_queue'/2` is pinned only with a count that is not greater than the queue.
# ROWS THE KERNEL CANNOT ANSWER YET would be `@test_broken <the same comparison>` with an owner in `_T7_BROKEN`: none is known by reading (every built-in the rows call
# is registered in src/pl-tabling.jl / src/pl-trie.jl), so the dictionary is empty; an unproven refusal is not recorded, the run decides.
# VERIFIED (S3c, 2026-11-17): every row, q06-q11 and l02-l07 included, answers on the kernel as swipl 10.1.20 does (file run on all three term types with swipl on PATH: 211/211 each,
# the live pin check included; no pin needed a change). The kills NAMED in a label are still read off the rows, not observed: tools/mutants/TB7.py is the observation.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE - these built-ins ride the term layer through the FLI (unify, get, the table pool)
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _T7_T = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_T7_sym(x) = lk_sym(_T7_T, Symbol(x))

_T7_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _T7_enc(t::_T7_T, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _T7_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _T7_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _T7_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_T7_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

const _T7_DRIVER = raw"""
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

function _T7_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _T7_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(
            pipeline(addenv(`swipl -q $f`, "LC_ALL" => "C"); stdin=devnull, stderr=devnull),
            String
        )
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

"The program text with the cases of `cases` appended."
_T7_text(program::String, cases) =
    program * join([
        "t_$(id)(R) :- catch(($g), error(SsuE, _), R = raised(SsuE)).\n" for
        (id, g) in cases
    ])

"A kernel with the program consulted: `(gd, ld, first line of the driver's output)`."
function _T7_load(program::String, cases)
    f = joinpath(mktempdir(), "tabling_tb7rows.pl")
    write(f, _T7_text(program, cases))
    gd = LK.PL_global_data{_T7_T}()
    ld = LK.PL_local_data{_T7_T}(gd)
    st, ball = LK.load_file!(gd, ld, f)
    return gd, ld, (st === :ok ? "ok" : "exc " * _T7_enc(ball::_T7_T))
end

"The driver's line for `pred/1` (every answer, at most 50)."
function _T7_ask(gd, ld, pred::String)::String
    proc = LK.isCurrentProcedure(sym_key(_T7_sym(pred)), 1, LK.MODULE_user(gd))
    (proc === nothing || !LK.isDefinedProcedure(gd, proc)) && return "$pred undefined"
    sols = String[]
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 1)
    LK.putSlotValue!(ld, a + 1, mk_var(_T7_T, LK.fresh_var_keys!(1)), LK.PutVarMap())
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    n = 0
    while (n += 1) <= 50
        rc = LK.PL_next_solution(gd, ld, qid)
        if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
            push!(
                sols,
                _T7_enc(mk_expr(_T7_T, _T7_T[_T7_sym(pred), lk_answers(ld, (a:a)...)...]))
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
    return pred * join(" " .* sols)
end

"`_T7_ask`, a Julia exception (a NotPortedError of a built-in) answering as the line `<pred> THROWN <type>`."
function _T7_ask_safe(gd, ld, pred::String)::String
    try
        return _T7_ask(gd, ld, pred)
    catch e
        return "$pred THROWN $(typeof(e))"
    end
end

# The pins below are PRINTED BY swipl 10.1.20 (the generators: evidence/TB7ROWS/gen/emit.py), not typed.
const _T7_PROG_DEPERR = raw"""
:- table pa/1.
:- table pb/1.
:- table po/1 as opaque.
:- table pm/1 as monotonic.
:- table pn/1 as monotonic.
:- dynamic md/1 as monotonic.
pa(1). pb(1). po(1).
pm(X) :- md(X).
pn(X) :- pm(X).
md(0).
dv(G, T) :- '$tbl_variant_table'(0, user:G, T, _, _, _).
dep(G1, G2, R) :- call(G1), call(G2), dv(G1, T1), dv(G2, T2),
    ( '$idg_add_monotonic_dep'(T1, dependency(x, y, z, w), T2) -> R = ok ; R = failed ).
"""

const _T7_CASES_DEPERR = [
    ("d01", raw"dep(pa(_), pb(_), R)"),
    ("d02", raw"dep(pa(_), po(_), R)"),
    ("d03", raw"dep(pm(_), pa(_), R)"),
    ("d04", raw"dep(pa(_), pm(_), R)"),
    ("d05", raw"findall(X, pn(X), L), R = L"),
    ("d06", raw"dep(pm(_), pn(_), R)"),
    ("d07", raw"dep(pn(_), po(_), R)")
]

const _T7_PINS_DEPERR = [
    "ok",
    "t_d01 c[116,95,100,48,49]/1(c[114,97,105,115,101,100]/1(c[100,101,112,101,110,100,101,110,99,121,95,101,114,114,111,114]/2(c[58]/2(a[117,115,101,114],c[112,98]/1(i1)),c[109,111,110,111,116,111,110,105,99]/1(c[58]/2(a[117,115,101,114],c[112,97]/1(i1))))))",
    "t_d02 c[116,95,100,48,50]/1(a[111,107])",
    "t_d03 c[116,95,100,48,51]/1(c[114,97,105,115,101,100]/1(c[100,101,112,101,110,100,101,110,99,121,95,101,114,114,111,114]/2(c[58]/2(a[117,115,101,114],c[112,97]/1(i1)),c[109,111,110,111,116,111,110,105,99]/1(c[58]/2(a[117,115,101,114],c[112,109]/1(i0))))))",
    "t_d04 c[116,95,100,48,52]/1(c[114,97,105,115,101,100]/1(c[100,101,112,101,110,100,101,110,99,121,95,101,114,114,111,114]/2(c[58]/2(a[117,115,101,114],c[112,109]/1(i0)),c[109,111,110,111,116,111,110,105,99]/1(c[58]/2(a[117,115,101,114],c[112,97]/1(i1))))))",
    "t_d05 c[116,95,100,48,53]/1(c[91,124,93]/2(i0,nil))",
    "t_d06 c[116,95,100,48,54]/1(a[111,107])",
    "t_d07 c[116,95,100,48,55]/1(a[111,107])"
]

const _T7_PROG_COLLECT = raw"""
:- table cm/1 as monotonic.
:- table cn/1.
:- table co/1.
:- table cmm/1 as monotonic.
cm(X) :- ( '$tbl_collect_mono_dep' -> X = yes ; X = no ).
cn(X) :- ( '$tbl_collect_mono_dep' -> X = yes ; X = no ).
co(X) :- cm(Y), ( '$tbl_collect_mono_dep' -> X = yes(Y) ; X = no(Y) ).
cmm(X) :- cn(Y), ( '$tbl_collect_mono_dep' -> X = yes(Y) ; X = no(Y) ).
cd(R) :- ( '$tbl_collect_mono_dep' -> R = yes ; R = no ).
"""

const _T7_CASES_COLLECT = [
    ("c01", raw"cd(R)"),
    (
        "c02",
        raw"'$tbl_propagate_start'(Old), cd(A), '$tbl_propagate_end'(Old), cd(B), R = r(Old, A, B)"
    ),
    ("c03", raw"findall(X, cm(X), L), R = L"),
    ("c04", raw"findall(X, cn(X), L), R = L"),
    ("c05", raw"findall(X, co(X), L), R = L"),
    ("c06", raw"findall(X, cmm(X), L), R = L"),
    (
        "c07",
        raw"'$tbl_propagate_start'(O1), '$tbl_propagate_start'(O2), '$tbl_propagate_end'(O2), cd(A), '$tbl_propagate_end'(O1), cd(B), R = r(O1, O2, A, B)"
    )
]

const _T7_PINS_COLLECT = [
    "ok",
    "t_c01 c[116,95,99,48,49]/1(a[110,111])",
    "t_c02 c[116,95,99,48,50]/1(c[114]/3(i0,a[121,101,115],a[110,111]))",
    "t_c03 c[116,95,99,48,51]/1(c[91,124,93]/2(a[121,101,115],nil))",
    "t_c04 c[116,95,99,48,52]/1(c[91,124,93]/2(a[110,111],nil))",
    "t_c05 c[116,95,99,48,53]/1(c[91,124,93]/2(c[110,111]/1(a[121,101,115]),nil))",
    "t_c06 c[116,95,99,48,54]/1(c[91,124,93]/2(c[121,101,115]/1(a[110,111]),nil))",
    "t_c07 c[116,95,99,48,55]/1(c[114]/4(i0,i1,a[121,101,115],a[110,111]))"
]

const _T7_PROG_LAZY = raw"""tm_yn(G, R) :- ( call(G) -> R = yes ; R = no ).
tp(G, T) :- '$tbl_existing_variant_table'(0, user:G, T, _, _).
ts(G, S) :- ( tp(G, T) -> '$tbl_table_status'(T, S) ; S = none ).
qa(G, L) :- tp(G, T), findall(C, ('$idg_mono_affects_lazy'(T, _, _, _, A), length(A, C)), L).
fo(G, R) :- tp(G, T), ( '$idg_forced'(T) -> R = forced ; R = notforced ).
mi(G, R) :- tp(G, T), ( '$idg_mono_index'(T, _) -> R = idx ; R = noidx ).

:- dynamic ld/1 as monotonic.
:- table lp/1 as (monotonic, lazy).
:- table mp/1 as monotonic.
:- table lq/1 as (monotonic, lazy).
lp(X) :- ld(X).
mp(X) :- ld(X).
lq(X) :- lp(X).
"""

const _T7_CASES_LAZY = [
    (
        "l01",
        raw"forall(member(G, [lp(_), mp(_), lq(_)]), forall(G, true)), ts(lp(_), A), ts(mp(_), B), ts(lq(_), C), R = r(A, B, C)"
    ),
    (
        "l02",
        raw"assertz(ld(1)), ts(lp(_), A), ts(mp(_), B), ts(lq(_), C), qa(lp(_), Q1), qa(lq(_), Q2), R = r(s(A, B, C), q(Q1, Q2))"
    ),
    (
        "l03",
        raw"assertz(ld(2)), ts(lp(_), A), qa(lp(_), Q1), qa(lq(_), Q2), R = r(A, Q1, Q2)"
    ),
    (
        "l04",
        raw"findall(X, lq(X), L0), msort(L0, L), ts(lp(_), A), ts(lq(_), C), qa(lp(_), Q1), qa(lq(_), Q2), R = r(L, A, C, Q1, Q2)"
    ),
    (
        "l05",
        raw"tp(lp(_), T), '$idg_mono_invalidate'(T), ts(lp(_), A), ts(lq(_), C), fo(lp(_), F), R = r(A, C, F)"
    ),
    (
        "l06",
        raw"findall(X, lq(X), L0), msort(L0, L), ts(lp(_), A), ts(lq(_), C), fo(lp(_), F), R = r(L, A, C, F)"
    ),
    (
        "l07",
        raw"retract(ld(1)), ts(lp(_), A), ts(mp(_), B), ts(lq(_), C), fo(lp(_), F), R = r(A, B, C, F)"
    ),
    (
        "l08",
        raw"findall(X, lq(X), L0), msort(L0, L), findall(X, mp(X), M0), msort(M0, M), R = r(L, M)"
    ),
    ("l09", raw"mi(lp(_), A), mi(mp(_), B), mi(lq(_), C), R = r(A, B, C)")
]

const _T7_PINS_LAZY = [
    "ok",
    "t_l01 c[116,95,108,48,49]/1(c[114]/3(a[99,111,109,112,108,101,116,101],a[99,111,109,112,108,101,116,101],a[99,111,109,112,108,101,116,101]))",
    "t_l02 c[116,95,108,48,50]/1(c[114]/2(c[115]/3(a[105,110,118,97,108,105,100],a[99,111,109,112,108,101,116,101],a[105,110,118,97,108,105,100]),c[113]/2(c[91,124,93]/2(i1,nil),c[91,124,93]/2(i1,nil))))",
    "t_l03 c[116,95,108,48,51]/1(c[114]/3(a[105,110,118,97,108,105,100],c[91,124,93]/2(i2,nil),c[91,124,93]/2(i2,nil)))",
    "t_l04 c[116,95,108,48,52]/1(c[114]/5(c[91,124,93]/2(i1,c[91,124,93]/2(i2,nil)),a[99,111,109,112,108,101,116,101],a[99,111,109,112,108,101,116,101],nil,nil))",
    "t_l05 c[116,95,108,48,53]/1(c[114]/3(a[105,110,118,97,108,105,100],a[105,110,118,97,108,105,100],a[110,111,116,102,111,114,99,101,100]))",
    "t_l06 c[116,95,108,48,54]/1(c[114]/4(c[91,124,93]/2(i1,c[91,124,93]/2(i2,nil)),a[99,111,109,112,108,101,116,101],a[99,111,109,112,108,101,116,101],a[110,111,116,102,111,114,99,101,100]))",
    "t_l07 c[116,95,108,48,55]/1(c[114]/4(a[105,110,118,97,108,105,100],a[105,110,118,97,108,105,100],a[105,110,118,97,108,105,100],a[102,111,114,99,101,100]))",
    "t_l08 c[116,95,108,48,56]/1(c[114]/2(c[91,124,93]/2(i2,nil),c[91,124,93]/2(i2,nil)))",
    "t_l09 c[116,95,108,48,57]/1(c[114]/3(a[105,100,120],a[110,111,105,100,120],a[110,111,105,100,120]))"
]

const _T7_PROG_QUEUE = raw"""tm_yn(G, R) :- ( call(G) -> R = yes ; R = no ).
tp(G, T) :- '$tbl_existing_variant_table'(0, user:G, T, _, _).
ts(G, S) :- ( tp(G, T) -> '$tbl_table_status'(T, S) ; S = none ).
qa(G, L) :- tp(G, T), findall(C, ('$idg_mono_affects_lazy'(T, _, _, _, A), length(A, C)), L).
fo(G, R) :- tp(G, T), ( '$idg_forced'(T) -> R = forced ; R = notforced ).
mi(G, R) :- tp(G, T), ( '$idg_mono_index'(T, _) -> R = idx ; R = noidx ).

:- dynamic ld/1 as monotonic.
:- table lp/1 as (monotonic, lazy).
lp(X) :- ld(X).
rs :- abolish_all_tables, retractall(ld(_)), forall(lp(_), true).
eq(N, R) :- tp(lp(_), T), '$idg_mono_affects_lazy'(T, _, _, Ref, _),
    ( catch('$idg_mono_empty_queue'(Ref, N), error(E, _), Raised = E) -> ( nonvar(Raised) -> R = raised(Raised) ; R = yes ) ; R = no ).
three :- rs, assertz(ld(1)), assertz(ld(2)), assertz(ld(3)).
"""

const _T7_CASES_QUEUE = [
    ("q01", raw"three, eq(2, A), qa(lp(_), Q), ts(lp(_), S), R = r(A, Q, S)"),
    ("q02", raw"three, eq(3, A), qa(lp(_), Q), ts(lp(_), S), R = r(A, Q, S)"),
    ("q03", raw"three, eq(0, A), qa(lp(_), Q), ts(lp(_), S), R = r(A, Q, S)"),
    ("q04", raw"three, eq(-1, A), qa(lp(_), Q), ts(lp(_), S), R = r(A, Q, S)"),
    ("q05", raw"three, eq(1, A1), eq(1, A2), qa(lp(_), Q), R = r(A1, A2, Q)"),
    (
        "q06",
        raw"rs, assertz(ld(1)), assertz(ld(2)), retract(ld(1)), qa(lp(_), Q), ts(lp(_), S), fo(lp(_), F), R = r(Q, S, F)"
    ),
    (
        "q07",
        raw"rs, assertz(ld(1)), assertz(ld(2)), tp(lp(_), T), '$idg_mono_invalidate'(T), qa(lp(_), Q), ts(lp(_), S), findall(X, lp(X), L0), msort(L0, L), R = r(Q, S, L)"
    ),
    (
        "q08",
        raw"rs, assertz(ld(1)), assertz(ld(2)), retractall(ld(1)), qa(lp(_), Q), ts(lp(_), S), findall(X, lp(X), L0), msort(L0, L), R = r(Q, S, L)"
    ),
    (
        "q09",
        raw"rs, assertz(ld(1)), assertz(ld(2)), assertz(ld(3)), tp(lp(_), T), ts(lp(_), S0), ( '$mono_reeval_prepare'(T, Size) -> P = yes ; P = no ), ts(lp(_), S1), '$idg_mono_affects_lazy'(T, _, _, Ref, Ans), length(Ans, C), '$idg_mono_empty_queue'(Ref, C), qa(lp(_), Q), ( '$mono_reeval_done'(T, Size, Deps) -> D = yes(Deps) ; D = no ), ts(lp(_), S2), R = r(S0, P, Size, S1, C, Q, D, S2)"
    ),
    (
        "q10",
        raw"tp(lp(_), T), ( '$mono_reeval_prepare'(T, Size) -> R = r(yes, Size) ; R = r(no) )"
    ),
    ("q11", raw"findall(X, lp(X), L0), msort(L0, L), ts(lp(_), S), R = r(L, S)")
]

const _T7_PINS_QUEUE = [
    "ok",
    "t_q01 c[116,95,113,48,49]/1(c[114]/3(a[121,101,115],c[91,124,93]/2(i1,nil),a[105,110,118,97,108,105,100]))",
    "t_q02 c[116,95,113,48,50]/1(c[114]/3(a[121,101,115],nil,a[105,110,118,97,108,105,100]))",
    "t_q03 c[116,95,113,48,51]/1(c[114]/3(a[121,101,115],c[91,124,93]/2(i3,nil),a[105,110,118,97,108,105,100]))",
    "t_q04 c[116,95,113,48,52]/1(c[114]/3(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[110,111,116,95,108,101,115,115,95,116,104,97,110,95,122,101,114,111],i-1)),c[91,124,93]/2(i3,nil),a[105,110,118,97,108,105,100]))",
    "t_q05 c[116,95,113,48,53]/1(c[114]/3(a[121,101,115],a[121,101,115],c[91,124,93]/2(i1,nil)))",
    "t_q06 c[116,95,113,48,54]/1(c[114]/3(nil,a[105,110,118,97,108,105,100],a[102,111,114,99,101,100]))",
    "t_q07 c[116,95,113,48,55]/1(c[114]/3(c[91,124,93]/2(i2,nil),a[105,110,118,97,108,105,100],c[91,124,93]/2(i1,c[91,124,93]/2(i2,nil))))",
    "t_q08 c[116,95,113,48,56]/1(c[114]/3(nil,a[105,110,118,97,108,105,100],c[91,124,93]/2(i2,nil)))",
    "t_q09 c[116,95,113,48,57]/1(c[114]/8(a[105,110,118,97,108,105,100],a[121,101,115],i3,a[105,110,118,97,108,105,100],i3,nil,c[121,101,115]/1(nil),a[99,111,109,112,108,101,116,101]))",
    "t_q10 c[116,95,113,49,48]/1(c[114]/1(a[110,111]))",
    "t_q11 c[116,95,113,49,49]/1(c[114]/2(c[91,124,93]/2(i1,c[91,124,93]/2(i2,c[91,124,93]/2(i3,nil))),a[99,111,109,112,108,101,116,101]))"
]

const _T7_PROG_SUBMONO = raw"""
tt(G, N) :- '$tbl_local_variant_table'(VT), findall(x, trie_gen(VT, user:G, _), L), length(L, N).
:- dynamic sd/1 as monotonic.
:- table sm/1 as (subsumptive, monotonic).
:- table sc/1 as monotonic.
:- table sn/2 as (subsumptive, monotonic).
:- dynamic se/2 as monotonic.
sm(X) :- sd(X).
sc(X) :- sm(X).
sn(X, Y) :- se(X, Y).
"""

const _T7_CASES_SUBMONO = [
    (
        "s01",
        raw"assertz(sd(1)), assertz(sd(2)), findall(X, sm(X), L0), msort(L0, L), findall(x, sm(2), M), tt(sm(_), N), R = r(L, M, N)"
    ),
    (
        "s02",
        raw"assertz(sd(3)), findall(X, sm(X), L0), msort(L0, L), findall(x, sm(2), M), findall(x, sm(3), M3), tt(sm(_), N), R = r(L, M, M3, N)"
    ),
    (
        "s03",
        raw"findall(X, sc(X), L0), msort(L0, L), assertz(sd(4)), findall(X, sc(X), L1), msort(L1, L2), findall(X, sm(X), L3), msort(L3, L4), R = r(L, L2, L4)"
    ),
    (
        "s04",
        raw"retract(sd(1)), findall(X, sm(X), L0), msort(L0, L), findall(X, sc(X), L1), msort(L1, L2), findall(x, sm(2), M), R = r(L, L2, M)"
    ),
    (
        "s05",
        raw"assertz(se(a, 1)), assertz(se(b, 2)), findall(Y, sn(a, Y), L0), findall(X-Y, sn(X, Y), L1), msort(L1, L), assertz(se(a, 3)), findall(Y, sn(a, Y), M0), msort(M0, M), findall(X-Y, sn(X, Y), N1), msort(N1, N), tt(sn(_, _), T), R = r(L0, L, M, N, T)"
    )
]

const _T7_PINS_SUBMONO = [
    "ok",
    "t_s01 c[116,95,115,48,49]/1(c[114]/3(c[91,124,93]/2(i1,c[91,124,93]/2(i2,nil)),c[91,124,93]/2(a[120],nil),i1))",
    "t_s02 c[116,95,115,48,50]/1(c[114]/4(c[91,124,93]/2(i1,c[91,124,93]/2(i2,c[91,124,93]/2(i3,nil))),c[91,124,93]/2(a[120],nil),c[91,124,93]/2(a[120],nil),i1))",
    "t_s03 c[116,95,115,48,51]/1(c[114]/3(c[91,124,93]/2(i1,c[91,124,93]/2(i2,c[91,124,93]/2(i3,nil))),c[91,124,93]/2(i1,c[91,124,93]/2(i2,c[91,124,93]/2(i3,c[91,124,93]/2(i4,nil)))),c[91,124,93]/2(i1,c[91,124,93]/2(i2,c[91,124,93]/2(i3,c[91,124,93]/2(i4,nil))))))",
    "t_s04 c[116,95,115,48,52]/1(c[114]/3(c[91,124,93]/2(i2,c[91,124,93]/2(i3,c[91,124,93]/2(i4,nil))),c[91,124,93]/2(i2,c[91,124,93]/2(i3,c[91,124,93]/2(i4,nil))),c[91,124,93]/2(a[120],nil)))",
    "t_s05 c[116,95,115,48,53]/1(c[114]/5(c[91,124,93]/2(i1,nil),c[91,124,93]/2(c[45]/2(a[97],i1),c[91,124,93]/2(c[45]/2(a[98],i2),nil)),c[91,124,93]/2(i1,c[91,124,93]/2(i3,nil)),c[91,124,93]/2(c[45]/2(a[97],i1),c[91,124,93]/2(c[45]/2(a[97],i3),c[91,124,93]/2(c[45]/2(a[98],i2),nil))),i2))"
]

# S3C-BEGIN
const _T7_PROG_CHAIN = raw"""tp(G, T) :- '$tbl_existing_variant_table'(0, user:G, T, _, _).
st1(G, S) :- ( tp(G, T) -> '$tbl_table_status'(T, S0), ( '$idg_forced'(T) -> F = f ; F = n ), ( '$idg_falsecount'(T, C) -> true ; C = nofc ),
      findall(Q, ('$idg_mono_affects_lazy'(T, _, _, _, A), length(A, Q)), Qs), S = S0/F/C/Qs ; S = none ).
dump(R) :- findall(N-S, (member(G, [ch_p(_), ch_a(_), ch_b(_), ch_c(_), ch_e(_)]), functor(G, N, _), st1(G, S)), R).
ex(G, L) :- findall(G, G, L0), msort(L0, L).
:- dynamic (ch_d1/1, ch_d2/1, ch_d3/1) as monotonic.
:- dynamic ch_log/1.
:- table (ch_p/1, ch_a/1, ch_b/1, ch_c/1) as (monotonic, lazy).
:- table ch_e/1 as monotonic.
ch_p(X) :- ( ch_a(X) ; ch_b(X) ; ch_d3(X) ).
ch_b(X) :- ch_c(X).
ch_c(X) :- ch_d1(X).
ch_a(X) :- ch_d2(X).
ch_e(X) :- ch_d1(X), assertz(ch_log(X)).
"""

const _T7_CASES_CHAIN = [
    (
        "ch01",
        raw"abolish_all_tables, retractall(ch_d1(_)), retractall(ch_d2(_)), retractall(ch_d3(_)), retractall(ch_log(_)), ex(ch_p(_), A0), ex(ch_e(_), E0), dump(D0), R = r(A0, E0, D0)"
    ),
    (
        "ch02",
        raw"assertz(ch_d1(1)), dump(D1), ex(ch_e(_), E1), findall(X, ch_log(X), Lg), dump(D2), R = r(D1, E1, Lg, D2)"
    ),
    (
        "ch03",
        raw"assertz(ch_d2(2)), assertz(ch_d3(3)), dump(D1), ex(ch_c(_), C), dump(D2), ex(ch_p(_), A), dump(D3), R = r(D1, C, D2, A, D3)"
    ),
    (
        "ch04",
        raw"retract(ch_d1(1)), dump(D1), ex(ch_p(_), A), dump(D2), ex(ch_e(_), E), findall(X, ch_log(X), Lg), dump(D3), R = r(D1, A, D2, E, Lg, D3)"
    ),
    (
        "ch05",
        raw"assertz(ch_d1(5)), assertz(ch_d1(6)), dump(D1), ex(ch_e(_), E), findall(X, ch_log(X), Lg), ex(ch_p(_), A), dump(D2), R = r(D1, E, Lg, A, D2)"
    )
]

const _T7_PINS_CHAIN = [
    "ok",
    "t_ch01 c[116,95,99,104,48,49]/1(c[114]/3(nil,nil,c[91,124,93]/2(c[45]/2(a[99,104,95,112],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[99,104,95,97],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[99,104,95,98],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[99,104,95,99],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[99,104,95,101],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),nil)))))))",
    "t_ch02 c[116,95,99,104,48,50]/1(c[114]/4(c[91,124,93]/2(c[45]/2(a[99,104,95,112],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[110]),i1),c[91,124,93]/2(i1,nil))),c[91,124,93]/2(c[45]/2(a[99,104,95,97],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[99,104,95,98],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[110]),i2),c[91,124,93]/2(i1,nil))),c[91,124,93]/2(c[45]/2(a[99,104,95,99],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[110]),i1),c[91,124,93]/2(i1,nil))),c[91,124,93]/2(c[45]/2(a[99,104,95,101],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),nil))))),c[91,124,93]/2(c[99,104,95,101]/1(i1),nil),c[91,124,93]/2(i1,nil),c[91,124,93]/2(c[45]/2(a[99,104,95,112],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[110]),i1),c[91,124,93]/2(i1,nil))),c[91,124,93]/2(c[45]/2(a[99,104,95,97],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[99,104,95,98],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[110]),i2),c[91,124,93]/2(i1,nil))),c[91,124,93]/2(c[45]/2(a[99,104,95,99],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[110]),i1),c[91,124,93]/2(i1,nil))),c[91,124,93]/2(c[45]/2(a[99,104,95,101],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),nil)))))))",
    "t_ch03 c[116,95,99,104,48,51]/1(c[114]/5(c[91,124,93]/2(c[45]/2(a[99,104,95,112],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[110]),i2),c[91,124,93]/2(i1,c[91,124,93]/2(i1,c[91,124,93]/2(i1,nil))))),c[91,124,93]/2(c[45]/2(a[99,104,95,97],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[110]),i1),c[91,124,93]/2(i1,nil))),c[91,124,93]/2(c[45]/2(a[99,104,95,98],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[110]),i2),c[91,124,93]/2(i1,nil))),c[91,124,93]/2(c[45]/2(a[99,104,95,99],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[110]),i1),c[91,124,93]/2(i1,nil))),c[91,124,93]/2(c[45]/2(a[99,104,95,101],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),nil))))),c[91,124,93]/2(c[99,104,95,99]/1(i1),nil),c[91,124,93]/2(c[45]/2(a[99,104,95,112],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[110]),i2),c[91,124,93]/2(i1,c[91,124,93]/2(i1,c[91,124,93]/2(i1,nil))))),c[91,124,93]/2(c[45]/2(a[99,104,95,97],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[110]),i1),c[91,124,93]/2(i1,nil))),c[91,124,93]/2(c[45]/2(a[99,104,95,98],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[110]),i1),c[91,124,93]/2(i1,nil))),c[91,124,93]/2(c[45]/2(a[99,104,95,99],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[99,104,95,101],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),nil))))),c[91,124,93]/2(c[99,104,95,112]/1(i1),c[91,124,93]/2(c[99,104,95,112]/1(i2),c[91,124,93]/2(c[99,104,95,112]/1(i3),nil))),c[91,124,93]/2(c[45]/2(a[99,104,95,112],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),c[91,124,93]/2(i1,c[91,124,93]/2(i1,c[91,124,93]/2(i1,nil))))),c[91,124,93]/2(c[45]/2(a[99,104,95,97],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[99,104,95,98],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[99,104,95,99],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[99,104,95,101],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),nil)))))))",
    "t_ch04 c[116,95,99,104,48,52]/1(c[114]/6(c[91,124,93]/2(c[45]/2(a[99,104,95,112],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[102]),i1),c[91,124,93]/2(i1,c[91,124,93]/2(i1,nil)))),c[91,124,93]/2(c[45]/2(a[99,104,95,97],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[99,104,95,98],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[102]),i1),nil)),c[91,124,93]/2(c[45]/2(a[99,104,95,99],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[102]),i1),nil)),c[91,124,93]/2(c[45]/2(a[99,104,95,101],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[102]),i1),nil)),nil))))),c[91,124,93]/2(c[99,104,95,112]/1(i2),c[91,124,93]/2(c[99,104,95,112]/1(i3),nil)),c[91,124,93]/2(c[45]/2(a[99,104,95,112],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[99,104,95,97],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[99,104,95,98],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[99,104,95,99],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[99,104,95,101],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[102]),i1),nil)),nil))))),nil,c[91,124,93]/2(i1,nil),c[91,124,93]/2(c[45]/2(a[99,104,95,112],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[99,104,95,97],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[99,104,95,98],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[99,104,95,99],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[99,104,95,101],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),nil)))))))",
    "t_ch05 c[116,95,99,104,48,53]/1(c[114]/5(c[91,124,93]/2(c[45]/2(a[99,104,95,112],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[110]),i1),c[91,124,93]/2(i2,c[91,124,93]/2(i2,nil)))),c[91,124,93]/2(c[45]/2(a[99,104,95,97],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[99,104,95,98],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[110]),i2),c[91,124,93]/2(i2,nil))),c[91,124,93]/2(c[45]/2(a[99,104,95,99],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[110]),i1),c[91,124,93]/2(i2,nil))),c[91,124,93]/2(c[45]/2(a[99,104,95,101],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),nil))))),c[91,124,93]/2(c[99,104,95,101]/1(i5),c[91,124,93]/2(c[99,104,95,101]/1(i6),nil)),c[91,124,93]/2(i1,c[91,124,93]/2(i5,c[91,124,93]/2(i6,nil))),c[91,124,93]/2(c[99,104,95,112]/1(i2),c[91,124,93]/2(c[99,104,95,112]/1(i3),c[91,124,93]/2(c[99,104,95,112]/1(i5),c[91,124,93]/2(c[99,104,95,112]/1(i6),nil)))),c[91,124,93]/2(c[45]/2(a[99,104,95,112],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[99,104,95,97],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[99,104,95,98],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[99,104,95,99],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[99,104,95,101],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),nil)))))))"
]

const _T7_PROG_INDEX = raw"""tp(G, T) :- '$tbl_existing_variant_table'(0, user:G, T, _, _).
st1(G, S) :- ( tp(G, T) -> '$tbl_table_status'(T, S0), ( '$idg_forced'(T) -> F = f ; F = n ), ( '$idg_falsecount'(T, C) -> true ; C = nofc ),
      ( '$idg_mono_index'(T, _) -> I = idx ; I = noidx ),
      findall(Q, ('$idg_mono_affects_lazy'(T, _, _, _, A), length(A, Q)), Qs), S = S0/F/C/I/Qs ; S = none ).
dump(R) :- findall(N-S, (member(G, [ix_u(_), ix_s(_), ix_v(_)]), functor(G, N, _), st1(G, S)), R).
ex(G, L) :- findall(G, G, L0), msort(L0, L).
lg(L) :- findall(X, ix_log(X), L0), msort(L0, L), retractall(ix_log(_)).
:- dynamic ix_d/1 as monotonic.
:- dynamic ix_log/1.
:- table ix_s/1 as (monotonic, lazy).
:- table ix_v/1 as (monotonic, lazy).
:- table ix_u/1 as monotonic.
ix_s(X) :- ix_d(X).
ix_v(X) :- ix_s(X).
ix_u(Y-Z) :- ix_s(Y), ix_s(Z), assertz(ix_log(Y-Z)).
"""

const _T7_CASES_INDEX = [
    (
        "ix01",
        raw"abolish_all_tables, retractall(ix_d(_)), retractall(ix_log(_)), assertz(ix_d(1)), ex(ix_u(_), A0), lg(L0), dump(D0), R = r(A0, L0, D0)"
    ),
    (
        "ix02",
        raw"assertz(ix_d(2)), dump(D1), ex(ix_u(_), A), lg(L), dump(D2), R = r(D1, A, L, D2)"
    ),
    (
        "ix03",
        raw"retract(ix_d(1)), dump(D1), ex(ix_u(_), A), lg(L), dump(D2), assertz(ix_d(3)), dump(D3), ex(ix_u(_), A3), lg(L3), dump(D4), R = r(D1, A, L, D2, D3, A3, L3, D4)"
    )
]

const _T7_PINS_INDEX = [
    "ok",
    "t_ix01 c[116,95,105,120,48,49]/1(c[114]/3(c[91,124,93]/2(c[105,120,95,117]/1(c[45]/2(i1,i1)),nil),c[91,124,93]/2(c[45]/2(i1,i1),nil),c[91,124,93]/2(c[45]/2(a[105,120,95,117],c[47]/2(c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),a[110,111,105,100,120]),nil)),c[91,124,93]/2(c[45]/2(a[105,120,95,115],c[47]/2(c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),a[105,100,120]),nil)),c[91,124,93]/2(c[45]/2(a[105,120,95,118],a[110,111,110,101]),nil)))))",
    "t_ix02 c[116,95,105,120,48,50]/1(c[114]/4(c[91,124,93]/2(c[45]/2(a[105,120,95,117],c[47]/2(c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[110]),i2),a[110,111,105,100,120]),c[91,124,93]/2(i1,c[91,124,93]/2(i1,nil)))),c[91,124,93]/2(c[45]/2(a[105,120,95,115],c[47]/2(c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[110]),i2),a[105,100,120]),c[91,124,93]/2(i1,nil))),c[91,124,93]/2(c[45]/2(a[105,120,95,118],a[110,111,110,101]),nil))),c[91,124,93]/2(c[105,120,95,117]/1(c[45]/2(i1,i1)),c[91,124,93]/2(c[105,120,95,117]/1(c[45]/2(i1,i2)),c[91,124,93]/2(c[105,120,95,117]/1(c[45]/2(i2,i1)),c[91,124,93]/2(c[105,120,95,117]/1(c[45]/2(i2,i2)),nil)))),c[91,124,93]/2(c[45]/2(i1,i2),c[91,124,93]/2(c[45]/2(i1,i2),c[91,124,93]/2(c[45]/2(i2,i1),c[91,124,93]/2(c[45]/2(i2,i1),c[91,124,93]/2(c[45]/2(i2,i2),c[91,124,93]/2(c[45]/2(i2,i2),nil)))))),c[91,124,93]/2(c[45]/2(a[105,120,95,117],c[47]/2(c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),a[110,111,105,100,120]),nil)),c[91,124,93]/2(c[45]/2(a[105,120,95,115],c[47]/2(c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),a[105,100,120]),nil)),c[91,124,93]/2(c[45]/2(a[105,120,95,118],a[110,111,110,101]),nil)))))",
    "t_ix03 c[116,95,105,120,48,51]/1(c[114]/8(c[91,124,93]/2(c[45]/2(a[105,120,95,117],c[47]/2(c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[102]),i1),a[110,111,105,100,120]),nil)),c[91,124,93]/2(c[45]/2(a[105,120,95,115],c[47]/2(c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[102]),i2),a[105,100,120]),nil)),c[91,124,93]/2(c[45]/2(a[105,120,95,118],a[110,111,110,101]),nil))),c[91,124,93]/2(c[105,120,95,117]/1(c[45]/2(i2,i2)),nil),c[91,124,93]/2(c[45]/2(i2,i2),nil),c[91,124,93]/2(c[45]/2(a[105,120,95,117],c[47]/2(c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),a[110,111,105,100,120]),nil)),c[91,124,93]/2(c[45]/2(a[105,120,95,115],c[47]/2(c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),a[105,100,120]),nil)),c[91,124,93]/2(c[45]/2(a[105,120,95,118],a[110,111,110,101]),nil))),c[91,124,93]/2(c[45]/2(a[105,120,95,117],c[47]/2(c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[110]),i2),a[110,111,105,100,120]),c[91,124,93]/2(i1,c[91,124,93]/2(i1,nil)))),c[91,124,93]/2(c[45]/2(a[105,120,95,115],c[47]/2(c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[110]),i2),a[105,100,120]),c[91,124,93]/2(i1,nil))),c[91,124,93]/2(c[45]/2(a[105,120,95,118],a[110,111,110,101]),nil))),c[91,124,93]/2(c[105,120,95,117]/1(c[45]/2(i2,i2)),c[91,124,93]/2(c[105,120,95,117]/1(c[45]/2(i2,i3)),c[91,124,93]/2(c[105,120,95,117]/1(c[45]/2(i3,i2)),c[91,124,93]/2(c[105,120,95,117]/1(c[45]/2(i3,i3)),nil)))),c[91,124,93]/2(c[45]/2(i2,i3),c[91,124,93]/2(c[45]/2(i2,i3),c[91,124,93]/2(c[45]/2(i3,i2),c[91,124,93]/2(c[45]/2(i3,i2),c[91,124,93]/2(c[45]/2(i3,i3),c[91,124,93]/2(c[45]/2(i3,i3),nil)))))),c[91,124,93]/2(c[45]/2(a[105,120,95,117],c[47]/2(c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),a[110,111,105,100,120]),nil)),c[91,124,93]/2(c[45]/2(a[105,120,95,115],c[47]/2(c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),a[105,100,120]),nil)),c[91,124,93]/2(c[45]/2(a[105,120,95,118],a[110,111,110,101]),nil)))))"
]

const _T7_PROG_MODED = raw"""tp(G, T) :- '$tbl_existing_variant_table'(0, user:G, T, _, _).
st1(G, S) :- ( tp(G, T) -> '$tbl_table_status'(T, S0), ( '$idg_forced'(T) -> F = f ; F = n ), ( '$idg_falsecount'(T, C) -> true ; C = nofc ),
      findall(Q, ('$idg_mono_affects_lazy'(T, _, _, _, A), length(A, Q)), Qs), S = S0/F/C/Qs ; S = none ).
dump(R) :- findall(N-S, (member(N-G, [p-'$mn_p$1', r-'$mn_r$1', q-'$mn_q$1', s-'$mn_s$1']), st1(G, S)), R).
ex(G, L) :- findall(G, G, L0), msort(L0, L).
lg(L) :- findall(X, mn_log(X), L), retractall(mn_log(_)).
:- dynamic (mn_d1/1, mn_d2/1) as monotonic.
:- dynamic mn_log/1.
:- table (mn_p(min), mn_r(min), mn_q(min)) as (monotonic, lazy).
:- table mn_s(min) as monotonic.
mn_r(X) :- mn_d1(X).
mn_q(X) :- mn_d2(X).
mn_p(X) :- assertz(mn_log(p)), ( mn_r(X) ; mn_q(X) ).
mn_s(X) :- mn_d1(X), assertz(mn_log(s(X))).
"""

const _T7_CASES_MODED = [
    (
        "mn01",
        raw"abolish_all_tables, retractall(mn_d1(_)), retractall(mn_d2(_)), retractall(mn_log(_)), ex(mn_p(_), A0), ex(mn_s(_), S0), lg(L0), dump(D0), R = r(A0, S0, L0, D0)"
    ),
    (
        "mn02",
        raw"assertz(mn_d1(5)), dump(D1), ex(mn_p(_), A), ex(mn_s(_), S), lg(L), dump(D2), R = r(D1, A, S, L, D2)"
    ),
    (
        "mn03",
        raw"assertz(mn_d1(3)), dump(D1), ex(mn_p(_), A), ex(mn_s(_), S), lg(L), dump(D2), R = r(D1, A, S, L, D2)"
    ),
    (
        "mn04",
        raw"assertz(mn_d2(1)), dump(D1), ex(mn_p(_), A), lg(L), dump(D2), assertz(mn_d2(9)), ex(mn_p(_), A2), dump(D3), R = r(D1, A, L, D2, A2, D3)"
    ),
    (
        "mn05",
        raw"retract(mn_d2(1)), dump(D1), ex(mn_p(_), A), ex(mn_s(_), S), lg(L), dump(D2), R = r(D1, A, S, L, D2)"
    ),
    (
        "mn06",
        raw"retract(mn_d1(3)), dump(D1), ex(mn_p(_), A), ex(mn_s(_), S), lg(L), dump(D2), R = r(D1, A, S, L, D2)"
    )
]

const _T7_PINS_MODED = [
    "ok",
    "t_mn01 c[116,95,109,110,48,49]/1(c[114]/4(nil,nil,c[91,124,93]/2(a[112],nil),c[91,124,93]/2(c[45]/2(a[112],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[114],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[113],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[115],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),nil))))))",
    "t_mn02 c[116,95,109,110,48,50]/1(c[114]/5(c[91,124,93]/2(c[45]/2(a[112],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[110]),i2),c[91,124,93]/2(i1,nil))),c[91,124,93]/2(c[45]/2(a[114],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[110]),i1),c[91,124,93]/2(i1,nil))),c[91,124,93]/2(c[45]/2(a[113],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[115],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),nil)))),c[91,124,93]/2(c[109,110,95,112]/1(i5),nil),c[91,124,93]/2(c[109,110,95,115]/1(i5),nil),c[91,124,93]/2(c[115]/1(i5),nil),c[91,124,93]/2(c[45]/2(a[112],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[114],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[113],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[115],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),nil))))))",
    "t_mn03 c[116,95,109,110,48,51]/1(c[114]/5(c[91,124,93]/2(c[45]/2(a[112],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[110]),i2),c[91,124,93]/2(i1,nil))),c[91,124,93]/2(c[45]/2(a[114],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[110]),i1),c[91,124,93]/2(i1,nil))),c[91,124,93]/2(c[45]/2(a[113],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[115],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),nil)))),c[91,124,93]/2(c[109,110,95,112]/1(i3),nil),c[91,124,93]/2(c[109,110,95,115]/1(i3),nil),c[91,124,93]/2(c[115]/1(i3),nil),c[91,124,93]/2(c[45]/2(a[112],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[114],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[113],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[115],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),nil))))))",
    "t_mn04 c[116,95,109,110,48,52]/1(c[114]/6(c[91,124,93]/2(c[45]/2(a[112],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[110]),i2),c[91,124,93]/2(i1,nil))),c[91,124,93]/2(c[45]/2(a[114],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[113],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[110]),i1),c[91,124,93]/2(i1,nil))),c[91,124,93]/2(c[45]/2(a[115],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),nil)))),c[91,124,93]/2(c[109,110,95,112]/1(i1),nil),nil,c[91,124,93]/2(c[45]/2(a[112],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[114],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[113],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[115],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),nil)))),c[91,124,93]/2(c[109,110,95,112]/1(i1),nil),c[91,124,93]/2(c[45]/2(a[112],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[114],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[113],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[115],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),nil))))))",
    "t_mn05 c[116,95,109,110,48,53]/1(c[114]/5(c[91,124,93]/2(c[45]/2(a[112],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[102]),i1),nil)),c[91,124,93]/2(c[45]/2(a[114],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[113],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[102]),i1),nil)),c[91,124,93]/2(c[45]/2(a[115],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),nil)))),c[91,124,93]/2(c[109,110,95,112]/1(i3),nil),c[91,124,93]/2(c[109,110,95,115]/1(i3),nil),c[91,124,93]/2(a[112],nil),c[91,124,93]/2(c[45]/2(a[112],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[114],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[113],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[115],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),nil))))))",
    "t_mn06 c[116,95,109,110,48,54]/1(c[114]/5(c[91,124,93]/2(c[45]/2(a[112],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[102]),i1),nil)),c[91,124,93]/2(c[45]/2(a[114],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[102]),i1),nil)),c[91,124,93]/2(c[45]/2(a[113],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[115],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[102]),i1),nil)),nil)))),c[91,124,93]/2(c[109,110,95,112]/1(i5),nil),c[91,124,93]/2(c[109,110,95,115]/1(i5),nil),c[91,124,93]/2(a[112],c[91,124,93]/2(c[115]/1(i5),nil)),c[91,124,93]/2(c[45]/2(a[112],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[114],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[113],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[115],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),nil))))))"
]

const _T7_PROG_TXN = raw"""tp(G, T) :- '$tbl_existing_variant_table'(0, user:G, T, _, _).
st1(G, S) :- ( tp(G, T) -> '$tbl_table_status'(T, S0), ( '$idg_forced'(T) -> F = f ; F = n ), ( '$idg_falsecount'(T, C) -> true ; C = nofc ),
      findall(Q, ('$idg_mono_affects_lazy'(T, _, _, _, A), length(A, Q)), Qs), S = S0/F/C/Qs ; S = none ).
dump(R) :- findall(N-S, (member(G, [tx_p(_), tx_q(_), tx_e(_)]), functor(G, N, _), st1(G, S)), R).
ex(G, L) :- findall(G, G, L0), msort(L0, L).
lg(L) :- findall(X, tx_log(X), L), retractall(tx_log(_)).
rolled(G) :- ( transaction((G, fail)) -> true ; true ).
:- dynamic tx_d/1 as monotonic.
:- dynamic tx_log/1.
:- table (tx_p/1, tx_q/1) as (monotonic, lazy).
:- table tx_e/1 as monotonic.
tx_p(X) :- assertz(tx_log(p)), tx_d(X).
tx_q(X) :- tx_p(X).
tx_e(X) :- tx_d(X).
"""

const _T7_CASES_TXN = [
    (
        "tx01",
        raw"abolish_all_tables, retractall(tx_d(_)), retractall(tx_log(_)), ex(tx_q(_), A0), ex(tx_e(_), E0), lg(L0), dump(D0), R = r(A0, E0, L0, D0)"
    ),
    (
        "tx02",
        raw"rolled(assertz(tx_d(9))), dump(D1), ex(tx_q(_), A), ex(tx_e(_), E), lg(L), dump(D2), R = r(D1, A, E, L, D2)"
    ),
    (
        "tx03",
        raw"assertz(tx_d(1)), rolled((assertz(tx_d(9)), ex(tx_q(_), _), ex(tx_e(_), _))), dump(D1), ex(tx_q(_), A), ex(tx_e(_), E), lg(L), dump(D2), R = r(D1, A, E, L, D2)"
    ),
    (
        "tx04",
        raw"rolled((assertz(tx_d(7)), assertz(tx_d(8)))), dump(D1), assertz(tx_d(2)), dump(D2), ex(tx_q(_), A), ex(tx_e(_), E), lg(L), dump(D3), R = r(D1, D2, A, E, L, D3)"
    )
]

const _T7_PINS_TXN = [
    "ok",
    "t_tx01 c[116,95,116,120,48,49]/1(c[114]/4(nil,nil,c[91,124,93]/2(a[112],nil),c[91,124,93]/2(c[45]/2(a[116,120,95,112],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[116,120,95,113],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[116,120,95,101],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),nil)))))",
    "t_tx02 c[116,95,116,120,48,50]/1(c[114]/5(c[91,124,93]/2(c[45]/2(a[116,120,95,112],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[110]),i1),nil)),c[91,124,93]/2(c[45]/2(a[116,120,95,113],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[110]),i2),nil)),c[91,124,93]/2(c[45]/2(a[116,120,95,101],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),nil))),nil,nil,nil,c[91,124,93]/2(c[45]/2(a[116,120,95,112],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[116,120,95,113],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[116,120,95,101],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),nil)))))",
    "t_tx03 c[116,95,116,120,48,51]/1(c[114]/5(c[91,124,93]/2(c[45]/2(a[116,120,95,112],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),c[91,124,93]/2(i1,nil))),c[91,124,93]/2(c[45]/2(a[116,120,95,113],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[116,120,95,101],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),nil))),c[91,124,93]/2(c[116,120,95,113]/1(i1),nil),c[91,124,93]/2(c[116,120,95,101]/1(i1),nil),nil,c[91,124,93]/2(c[45]/2(a[116,120,95,112],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),c[91,124,93]/2(i1,nil))),c[91,124,93]/2(c[45]/2(a[116,120,95,113],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[116,120,95,101],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),nil)))))",
    "t_tx04 c[116,95,116,120,48,52]/1(c[114]/6(c[91,124,93]/2(c[45]/2(a[116,120,95,112],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),c[91,124,93]/2(i1,nil))),c[91,124,93]/2(c[45]/2(a[116,120,95,113],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[110]),i1),nil)),c[91,124,93]/2(c[45]/2(a[116,120,95,101],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),nil))),c[91,124,93]/2(c[45]/2(a[116,120,95,112],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),c[91,124,93]/2(i2,nil))),c[91,124,93]/2(c[45]/2(a[116,120,95,113],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[110]),i1),c[91,124,93]/2(i1,nil))),c[91,124,93]/2(c[45]/2(a[116,120,95,101],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),nil))),c[91,124,93]/2(c[116,120,95,113]/1(i1),c[91,124,93]/2(c[116,120,95,113]/1(i2),nil)),c[91,124,93]/2(c[116,120,95,101]/1(i1),c[91,124,93]/2(c[116,120,95,101]/1(i2),nil)),nil,c[91,124,93]/2(c[45]/2(a[116,120,95,112],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),c[91,124,93]/2(i2,nil))),c[91,124,93]/2(c[45]/2(a[116,120,95,113],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[116,120,95,101],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),nil)))))"
]

const _T7_PROG_DEPS = raw"""tp(G, T) :- '$tbl_existing_variant_table'(0, user:G, T, _, _).
st1(G, S) :- ( tp(G, T) -> '$tbl_table_status'(T, S0), ( '$idg_forced'(T) -> F = f ; F = n ), ( '$idg_falsecount'(T, C) -> true ; C = nofc ),
      findall(Q, ('$idg_mono_affects_lazy'(T, _, _, _, A), length(A, Q)), Qs), S = S0/F/C/Qs ; S = none ).
dump(R) :- findall(N-S, (member(G, [dp_v(_), dp_n(_), dp_l(_), dp_o(_)]), functor(G, N, _), st1(G, S)), R).
ex(G, L) :- findall(G, G, L0), msort(L0, L).
lg(L) :- findall(X, dp_log(X), L), retractall(dp_log(_)).
:- dynamic dp_d/1 as monotonic.
:- dynamic dp_log/1.
:- table (dp_v/1, dp_n/1, dp_o/1) as monotonic.
:- table dp_l/1 as (monotonic, lazy).
dp_v(Y-Z) :- dp_d(Y), dp_d(Z), assertz(dp_log(v(Y-Z))).
dp_n(Y) :- dp_d(Y), dp_d(5), assertz(dp_log(n(Y))).
dp_o(Y) :- dp_d(5), dp_d(Y), assertz(dp_log(o(Y))).
dp_l(Y-Z) :- dp_d(Y), dp_d(Z), assertz(dp_log(l(Y-Z))).
"""

const _T7_CASES_DEPS = [
    (
        "dp01",
        raw"abolish_all_tables, retractall(dp_d(_)), retractall(dp_log(_)), ex(dp_v(_), A1), ex(dp_n(_), A2), ex(dp_o(_), A3), ex(dp_l(_), A4), lg(L), dump(D), R = r(A1, A2, A3, A4, L, D)"
    ),
    (
        "dp02",
        raw"assertz(dp_d(1)), dump(D1), ex(dp_v(_), A1), ex(dp_l(_), A2), lg(L), dump(D2), R = r(D1, A1, A2, L, D2)"
    ),
    (
        "dp03",
        raw"assertz(dp_d(2)), dump(D1), ex(dp_v(_), A1), lg(L1), dump(D2), ex(dp_l(_), A2), lg(L2), dump(D3), R = r(D1, A1, L1, D2, A2, L2, D3)"
    ),
    (
        "dp04",
        raw"assertz(dp_d(5)), dump(D1), ex(dp_n(_), A1), ex(dp_o(_), A2), lg(L1), ex(dp_v(_), A3), lg(L2), dump(D2), R = r(D1, A1, A2, L1, A3, L2, D2)"
    ),
    (
        "dp05",
        raw"assertz(dp_d(3)), lg(L1), ex(dp_l(_), A1), lg(L2), assertz(dp_d(4)), ex(dp_l(_), A2), lg(L3), ex(dp_v(_), A3), lg(L4), dump(D), R = r(L1, A1, L2, A2, L3, A3, L4, D)"
    ),
    (
        "dp06",
        raw"retract(dp_d(1)), dump(D1), ex(dp_v(_), A1), ex(dp_n(_), A2), ex(dp_o(_), A3), ex(dp_l(_), A4), lg(L), dump(D2), R = r(D1, A1, A2, A3, A4, L, D2)"
    )
]

const _T7_PINS_DEPS = [
    "ok",
    "t_dp01 c[116,95,100,112,48,49]/1(c[114]/6(nil,nil,nil,nil,nil,c[91,124,93]/2(c[45]/2(a[100,112,95,118],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[100,112,95,110],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[100,112,95,108],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[100,112,95,111],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),nil))))))",
    "t_dp02 c[116,95,100,112,48,50]/1(c[114]/5(c[91,124,93]/2(c[45]/2(a[100,112,95,118],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[100,112,95,110],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[100,112,95,108],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[110]),i1),c[91,124,93]/2(i1,c[91,124,93]/2(i1,nil)))),c[91,124,93]/2(c[45]/2(a[100,112,95,111],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),nil)))),c[91,124,93]/2(c[100,112,95,118]/1(c[45]/2(i1,i1)),nil),c[91,124,93]/2(c[100,112,95,108]/1(c[45]/2(i1,i1)),nil),c[91,124,93]/2(c[118]/1(c[45]/2(i1,i1)),c[91,124,93]/2(c[108]/1(c[45]/2(i1,i1)),c[91,124,93]/2(c[108]/1(c[45]/2(i1,i1)),c[91,124,93]/2(c[108]/1(c[45]/2(i1,i1)),nil)))),c[91,124,93]/2(c[45]/2(a[100,112,95,118],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[100,112,95,110],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[100,112,95,108],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[100,112,95,111],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),nil))))))",
    "t_dp03 c[116,95,100,112,48,51]/1(c[114]/7(c[91,124,93]/2(c[45]/2(a[100,112,95,118],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[100,112,95,110],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[100,112,95,108],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[110]),i1),c[91,124,93]/2(i1,c[91,124,93]/2(i1,c[91,124,93]/2(i1,nil))))),c[91,124,93]/2(c[45]/2(a[100,112,95,111],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),nil)))),c[91,124,93]/2(c[100,112,95,118]/1(c[45]/2(i1,i1)),c[91,124,93]/2(c[100,112,95,118]/1(c[45]/2(i1,i2)),c[91,124,93]/2(c[100,112,95,118]/1(c[45]/2(i2,i1)),c[91,124,93]/2(c[100,112,95,118]/1(c[45]/2(i2,i2)),nil)))),c[91,124,93]/2(c[118]/1(c[45]/2(i1,i2)),c[91,124,93]/2(c[118]/1(c[45]/2(i2,i1)),c[91,124,93]/2(c[118]/1(c[45]/2(i2,i2)),c[91,124,93]/2(c[108]/1(c[45]/2(i1,i2)),c[91,124,93]/2(c[108]/1(c[45]/2(i2,i1)),c[91,124,93]/2(c[108]/1(c[45]/2(i2,i2)),nil)))))),c[91,124,93]/2(c[45]/2(a[100,112,95,118],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[100,112,95,110],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[100,112,95,108],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[110]),i1),c[91,124,93]/2(i1,c[91,124,93]/2(i1,c[91,124,93]/2(i1,nil))))),c[91,124,93]/2(c[45]/2(a[100,112,95,111],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),nil)))),c[91,124,93]/2(c[100,112,95,108]/1(c[45]/2(i1,i1)),c[91,124,93]/2(c[100,112,95,108]/1(c[45]/2(i1,i2)),c[91,124,93]/2(c[100,112,95,108]/1(c[45]/2(i2,i1)),c[91,124,93]/2(c[100,112,95,108]/1(c[45]/2(i2,i2)),nil)))),c[91,124,93]/2(c[108]/1(c[45]/2(i2,i2)),c[91,124,93]/2(c[108]/1(c[45]/2(i1,i2)),c[91,124,93]/2(c[108]/1(c[45]/2(i2,i1)),c[91,124,93]/2(c[108]/1(c[45]/2(i2,i2)),nil)))),c[91,124,93]/2(c[45]/2(a[100,112,95,118],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[100,112,95,110],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[100,112,95,108],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[100,112,95,111],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),nil))))))",
    "t_dp04 c[116,95,100,112,48,52]/1(c[114]/7(c[91,124,93]/2(c[45]/2(a[100,112,95,118],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[100,112,95,110],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[100,112,95,108],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[110]),i1),c[91,124,93]/2(i1,c[91,124,93]/2(i1,c[91,124,93]/2(i1,c[91,124,93]/2(i1,nil)))))),c[91,124,93]/2(c[45]/2(a[100,112,95,111],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),nil)))),c[91,124,93]/2(c[100,112,95,110]/1(i1),c[91,124,93]/2(c[100,112,95,110]/1(i2),c[91,124,93]/2(c[100,112,95,110]/1(i5),nil))),c[91,124,93]/2(c[100,112,95,111]/1(i1),c[91,124,93]/2(c[100,112,95,111]/1(i2),c[91,124,93]/2(c[100,112,95,111]/1(i5),nil))),c[91,124,93]/2(c[111]/1(i1),c[91,124,93]/2(c[111]/1(i2),c[91,124,93]/2(c[111]/1(i5),c[91,124,93]/2(c[110]/1(i2),c[91,124,93]/2(c[110]/1(i1),c[91,124,93]/2(c[118]/1(c[45]/2(i2,i5)),c[91,124,93]/2(c[118]/1(c[45]/2(i1,i5)),c[91,124,93]/2(c[118]/1(c[45]/2(i5,i1)),c[91,124,93]/2(c[118]/1(c[45]/2(i5,i2)),c[91,124,93]/2(c[118]/1(c[45]/2(i5,i5)),c[91,124,93]/2(c[110]/1(i5),c[91,124,93]/2(c[108]/1(c[45]/2(i2,i5)),c[91,124,93]/2(c[108]/1(c[45]/2(i1,i5)),c[91,124,93]/2(c[108]/1(c[45]/2(i5,i1)),c[91,124,93]/2(c[108]/1(c[45]/2(i5,i2)),c[91,124,93]/2(c[108]/1(c[45]/2(i5,i5)),c[91,124,93]/2(c[111]/1(i5),nil))))))))))))))))),c[91,124,93]/2(c[100,112,95,118]/1(c[45]/2(i1,i1)),c[91,124,93]/2(c[100,112,95,118]/1(c[45]/2(i1,i2)),c[91,124,93]/2(c[100,112,95,118]/1(c[45]/2(i1,i5)),c[91,124,93]/2(c[100,112,95,118]/1(c[45]/2(i2,i1)),c[91,124,93]/2(c[100,112,95,118]/1(c[45]/2(i2,i2)),c[91,124,93]/2(c[100,112,95,118]/1(c[45]/2(i2,i5)),c[91,124,93]/2(c[100,112,95,118]/1(c[45]/2(i5,i1)),c[91,124,93]/2(c[100,112,95,118]/1(c[45]/2(i5,i2)),c[91,124,93]/2(c[100,112,95,118]/1(c[45]/2(i5,i5)),nil))))))))),nil,c[91,124,93]/2(c[45]/2(a[100,112,95,118],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[100,112,95,110],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[100,112,95,108],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[110]),i1),c[91,124,93]/2(i1,c[91,124,93]/2(i1,c[91,124,93]/2(i1,c[91,124,93]/2(i1,nil)))))),c[91,124,93]/2(c[45]/2(a[100,112,95,111],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),nil))))))",
    "t_dp05 c[116,95,100,112,48,53]/1(c[114]/8(c[91,124,93]/2(c[118]/1(c[45]/2(i5,i3)),c[91,124,93]/2(c[118]/1(c[45]/2(i2,i3)),c[91,124,93]/2(c[118]/1(c[45]/2(i1,i3)),c[91,124,93]/2(c[118]/1(c[45]/2(i3,i1)),c[91,124,93]/2(c[118]/1(c[45]/2(i3,i2)),c[91,124,93]/2(c[118]/1(c[45]/2(i3,i5)),c[91,124,93]/2(c[118]/1(c[45]/2(i3,i3)),c[91,124,93]/2(c[110]/1(i3),c[91,124,93]/2(c[108]/1(c[45]/2(i5,i3)),c[91,124,93]/2(c[108]/1(c[45]/2(i2,i3)),c[91,124,93]/2(c[108]/1(c[45]/2(i1,i3)),c[91,124,93]/2(c[108]/1(c[45]/2(i3,i1)),c[91,124,93]/2(c[108]/1(c[45]/2(i3,i2)),c[91,124,93]/2(c[108]/1(c[45]/2(i3,i5)),c[91,124,93]/2(c[108]/1(c[45]/2(i3,i3)),c[91,124,93]/2(c[111]/1(i3),nil)))))))))))))))),c[91,124,93]/2(c[100,112,95,108]/1(c[45]/2(i1,i1)),c[91,124,93]/2(c[100,112,95,108]/1(c[45]/2(i1,i2)),c[91,124,93]/2(c[100,112,95,108]/1(c[45]/2(i1,i3)),c[91,124,93]/2(c[100,112,95,108]/1(c[45]/2(i1,i5)),c[91,124,93]/2(c[100,112,95,108]/1(c[45]/2(i2,i1)),c[91,124,93]/2(c[100,112,95,108]/1(c[45]/2(i2,i2)),c[91,124,93]/2(c[100,112,95,108]/1(c[45]/2(i2,i3)),c[91,124,93]/2(c[100,112,95,108]/1(c[45]/2(i2,i5)),c[91,124,93]/2(c[100,112,95,108]/1(c[45]/2(i3,i1)),c[91,124,93]/2(c[100,112,95,108]/1(c[45]/2(i3,i2)),c[91,124,93]/2(c[100,112,95,108]/1(c[45]/2(i3,i3)),c[91,124,93]/2(c[100,112,95,108]/1(c[45]/2(i3,i5)),c[91,124,93]/2(c[100,112,95,108]/1(c[45]/2(i5,i1)),c[91,124,93]/2(c[100,112,95,108]/1(c[45]/2(i5,i2)),c[91,124,93]/2(c[100,112,95,108]/1(c[45]/2(i5,i3)),c[91,124,93]/2(c[100,112,95,108]/1(c[45]/2(i5,i5)),nil)))))))))))))))),c[91,124,93]/2(c[108]/1(c[45]/2(i3,i3)),c[91,124,93]/2(c[108]/1(c[45]/2(i5,i5)),c[91,124,93]/2(c[108]/1(c[45]/2(i5,i3)),c[91,124,93]/2(c[108]/1(c[45]/2(i2,i5)),c[91,124,93]/2(c[108]/1(c[45]/2(i2,i3)),c[91,124,93]/2(c[108]/1(c[45]/2(i1,i5)),c[91,124,93]/2(c[108]/1(c[45]/2(i1,i3)),c[91,124,93]/2(c[108]/1(c[45]/2(i5,i1)),c[91,124,93]/2(c[108]/1(c[45]/2(i5,i2)),c[91,124,93]/2(c[108]/1(c[45]/2(i5,i5)),c[91,124,93]/2(c[108]/1(c[45]/2(i5,i3)),c[91,124,93]/2(c[108]/1(c[45]/2(i3,i1)),c[91,124,93]/2(c[108]/1(c[45]/2(i3,i2)),c[91,124,93]/2(c[108]/1(c[45]/2(i3,i5)),c[91,124,93]/2(c[108]/1(c[45]/2(i3,i3)),nil))))))))))))))),c[91,124,93]/2(c[100,112,95,108]/1(c[45]/2(i1,i1)),c[91,124,93]/2(c[100,112,95,108]/1(c[45]/2(i1,i2)),c[91,124,93]/2(c[100,112,95,108]/1(c[45]/2(i1,i3)),c[91,124,93]/2(c[100,112,95,108]/1(c[45]/2(i1,i4)),c[91,124,93]/2(c[100,112,95,108]/1(c[45]/2(i1,i5)),c[91,124,93]/2(c[100,112,95,108]/1(c[45]/2(i2,i1)),c[91,124,93]/2(c[100,112,95,108]/1(c[45]/2(i2,i2)),c[91,124,93]/2(c[100,112,95,108]/1(c[45]/2(i2,i3)),c[91,124,93]/2(c[100,112,95,108]/1(c[45]/2(i2,i4)),c[91,124,93]/2(c[100,112,95,108]/1(c[45]/2(i2,i5)),c[91,124,93]/2(c[100,112,95,108]/1(c[45]/2(i3,i1)),c[91,124,93]/2(c[100,112,95,108]/1(c[45]/2(i3,i2)),c[91,124,93]/2(c[100,112,95,108]/1(c[45]/2(i3,i3)),c[91,124,93]/2(c[100,112,95,108]/1(c[45]/2(i3,i4)),c[91,124,93]/2(c[100,112,95,108]/1(c[45]/2(i3,i5)),c[91,124,93]/2(c[100,112,95,108]/1(c[45]/2(i4,i1)),c[91,124,93]/2(c[100,112,95,108]/1(c[45]/2(i4,i2)),c[91,124,93]/2(c[100,112,95,108]/1(c[45]/2(i4,i3)),c[91,124,93]/2(c[100,112,95,108]/1(c[45]/2(i4,i4)),c[91,124,93]/2(c[100,112,95,108]/1(c[45]/2(i4,i5)),c[91,124,93]/2(c[100,112,95,108]/1(c[45]/2(i5,i1)),c[91,124,93]/2(c[100,112,95,108]/1(c[45]/2(i5,i2)),c[91,124,93]/2(c[100,112,95,108]/1(c[45]/2(i5,i3)),c[91,124,93]/2(c[100,112,95,108]/1(c[45]/2(i5,i4)),c[91,124,93]/2(c[100,112,95,108]/1(c[45]/2(i5,i5)),nil))))))))))))))))))))))))),c[91,124,93]/2(c[118]/1(c[45]/2(i3,i4)),c[91,124,93]/2(c[118]/1(c[45]/2(i5,i4)),c[91,124,93]/2(c[118]/1(c[45]/2(i2,i4)),c[91,124,93]/2(c[118]/1(c[45]/2(i1,i4)),c[91,124,93]/2(c[118]/1(c[45]/2(i4,i1)),c[91,124,93]/2(c[118]/1(c[45]/2(i4,i2)),c[91,124,93]/2(c[118]/1(c[45]/2(i4,i5)),c[91,124,93]/2(c[118]/1(c[45]/2(i4,i3)),c[91,124,93]/2(c[118]/1(c[45]/2(i4,i4)),c[91,124,93]/2(c[110]/1(i4),c[91,124,93]/2(c[108]/1(c[45]/2(i3,i4)),c[91,124,93]/2(c[108]/1(c[45]/2(i5,i4)),c[91,124,93]/2(c[108]/1(c[45]/2(i2,i4)),c[91,124,93]/2(c[108]/1(c[45]/2(i1,i4)),c[91,124,93]/2(c[108]/1(c[45]/2(i4,i1)),c[91,124,93]/2(c[108]/1(c[45]/2(i4,i2)),c[91,124,93]/2(c[108]/1(c[45]/2(i4,i5)),c[91,124,93]/2(c[108]/1(c[45]/2(i4,i3)),c[91,124,93]/2(c[108]/1(c[45]/2(i4,i4)),c[91,124,93]/2(c[111]/1(i4),c[91,124,93]/2(c[108]/1(c[45]/2(i4,i4)),c[91,124,93]/2(c[108]/1(c[45]/2(i3,i4)),c[91,124,93]/2(c[108]/1(c[45]/2(i5,i4)),c[91,124,93]/2(c[108]/1(c[45]/2(i2,i4)),c[91,124,93]/2(c[108]/1(c[45]/2(i1,i4)),c[91,124,93]/2(c[108]/1(c[45]/2(i4,i1)),c[91,124,93]/2(c[108]/1(c[45]/2(i4,i2)),c[91,124,93]/2(c[108]/1(c[45]/2(i4,i5)),c[91,124,93]/2(c[108]/1(c[45]/2(i4,i3)),c[91,124,93]/2(c[108]/1(c[45]/2(i4,i4)),nil)))))))))))))))))))))))))))))),c[91,124,93]/2(c[100,112,95,118]/1(c[45]/2(i1,i1)),c[91,124,93]/2(c[100,112,95,118]/1(c[45]/2(i1,i2)),c[91,124,93]/2(c[100,112,95,118]/1(c[45]/2(i1,i3)),c[91,124,93]/2(c[100,112,95,118]/1(c[45]/2(i1,i4)),c[91,124,93]/2(c[100,112,95,118]/1(c[45]/2(i1,i5)),c[91,124,93]/2(c[100,112,95,118]/1(c[45]/2(i2,i1)),c[91,124,93]/2(c[100,112,95,118]/1(c[45]/2(i2,i2)),c[91,124,93]/2(c[100,112,95,118]/1(c[45]/2(i2,i3)),c[91,124,93]/2(c[100,112,95,118]/1(c[45]/2(i2,i4)),c[91,124,93]/2(c[100,112,95,118]/1(c[45]/2(i2,i5)),c[91,124,93]/2(c[100,112,95,118]/1(c[45]/2(i3,i1)),c[91,124,93]/2(c[100,112,95,118]/1(c[45]/2(i3,i2)),c[91,124,93]/2(c[100,112,95,118]/1(c[45]/2(i3,i3)),c[91,124,93]/2(c[100,112,95,118]/1(c[45]/2(i3,i4)),c[91,124,93]/2(c[100,112,95,118]/1(c[45]/2(i3,i5)),c[91,124,93]/2(c[100,112,95,118]/1(c[45]/2(i4,i1)),c[91,124,93]/2(c[100,112,95,118]/1(c[45]/2(i4,i2)),c[91,124,93]/2(c[100,112,95,118]/1(c[45]/2(i4,i3)),c[91,124,93]/2(c[100,112,95,118]/1(c[45]/2(i4,i4)),c[91,124,93]/2(c[100,112,95,118]/1(c[45]/2(i4,i5)),c[91,124,93]/2(c[100,112,95,118]/1(c[45]/2(i5,i1)),c[91,124,93]/2(c[100,112,95,118]/1(c[45]/2(i5,i2)),c[91,124,93]/2(c[100,112,95,118]/1(c[45]/2(i5,i3)),c[91,124,93]/2(c[100,112,95,118]/1(c[45]/2(i5,i4)),c[91,124,93]/2(c[100,112,95,118]/1(c[45]/2(i5,i5)),nil))))))))))))))))))))))))),nil,c[91,124,93]/2(c[45]/2(a[100,112,95,118],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[100,112,95,110],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[100,112,95,108],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[100,112,95,111],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),nil))))))",
    "t_dp06 c[116,95,100,112,48,54]/1(c[114]/7(c[91,124,93]/2(c[45]/2(a[100,112,95,118],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[102]),i1),nil)),c[91,124,93]/2(c[45]/2(a[100,112,95,110],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[102]),i1),nil)),c[91,124,93]/2(c[45]/2(a[100,112,95,108],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[102]),i1),nil)),c[91,124,93]/2(c[45]/2(a[100,112,95,111],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[102]),i1),nil)),nil)))),c[91,124,93]/2(c[100,112,95,118]/1(c[45]/2(i2,i2)),c[91,124,93]/2(c[100,112,95,118]/1(c[45]/2(i2,i3)),c[91,124,93]/2(c[100,112,95,118]/1(c[45]/2(i2,i4)),c[91,124,93]/2(c[100,112,95,118]/1(c[45]/2(i2,i5)),c[91,124,93]/2(c[100,112,95,118]/1(c[45]/2(i3,i2)),c[91,124,93]/2(c[100,112,95,118]/1(c[45]/2(i3,i3)),c[91,124,93]/2(c[100,112,95,118]/1(c[45]/2(i3,i4)),c[91,124,93]/2(c[100,112,95,118]/1(c[45]/2(i3,i5)),c[91,124,93]/2(c[100,112,95,118]/1(c[45]/2(i4,i2)),c[91,124,93]/2(c[100,112,95,118]/1(c[45]/2(i4,i3)),c[91,124,93]/2(c[100,112,95,118]/1(c[45]/2(i4,i4)),c[91,124,93]/2(c[100,112,95,118]/1(c[45]/2(i4,i5)),c[91,124,93]/2(c[100,112,95,118]/1(c[45]/2(i5,i2)),c[91,124,93]/2(c[100,112,95,118]/1(c[45]/2(i5,i3)),c[91,124,93]/2(c[100,112,95,118]/1(c[45]/2(i5,i4)),c[91,124,93]/2(c[100,112,95,118]/1(c[45]/2(i5,i5)),nil)))))))))))))))),c[91,124,93]/2(c[100,112,95,110]/1(i2),c[91,124,93]/2(c[100,112,95,110]/1(i3),c[91,124,93]/2(c[100,112,95,110]/1(i4),c[91,124,93]/2(c[100,112,95,110]/1(i5),nil)))),c[91,124,93]/2(c[100,112,95,111]/1(i2),c[91,124,93]/2(c[100,112,95,111]/1(i3),c[91,124,93]/2(c[100,112,95,111]/1(i4),c[91,124,93]/2(c[100,112,95,111]/1(i5),nil)))),c[91,124,93]/2(c[100,112,95,108]/1(c[45]/2(i2,i2)),c[91,124,93]/2(c[100,112,95,108]/1(c[45]/2(i2,i3)),c[91,124,93]/2(c[100,112,95,108]/1(c[45]/2(i2,i4)),c[91,124,93]/2(c[100,112,95,108]/1(c[45]/2(i2,i5)),c[91,124,93]/2(c[100,112,95,108]/1(c[45]/2(i3,i2)),c[91,124,93]/2(c[100,112,95,108]/1(c[45]/2(i3,i3)),c[91,124,93]/2(c[100,112,95,108]/1(c[45]/2(i3,i4)),c[91,124,93]/2(c[100,112,95,108]/1(c[45]/2(i3,i5)),c[91,124,93]/2(c[100,112,95,108]/1(c[45]/2(i4,i2)),c[91,124,93]/2(c[100,112,95,108]/1(c[45]/2(i4,i3)),c[91,124,93]/2(c[100,112,95,108]/1(c[45]/2(i4,i4)),c[91,124,93]/2(c[100,112,95,108]/1(c[45]/2(i4,i5)),c[91,124,93]/2(c[100,112,95,108]/1(c[45]/2(i5,i2)),c[91,124,93]/2(c[100,112,95,108]/1(c[45]/2(i5,i3)),c[91,124,93]/2(c[100,112,95,108]/1(c[45]/2(i5,i4)),c[91,124,93]/2(c[100,112,95,108]/1(c[45]/2(i5,i5)),nil)))))))))))))))),c[91,124,93]/2(c[118]/1(c[45]/2(i2,i2)),c[91,124,93]/2(c[118]/1(c[45]/2(i2,i5)),c[91,124,93]/2(c[118]/1(c[45]/2(i2,i3)),c[91,124,93]/2(c[118]/1(c[45]/2(i2,i4)),c[91,124,93]/2(c[118]/1(c[45]/2(i5,i2)),c[91,124,93]/2(c[118]/1(c[45]/2(i5,i5)),c[91,124,93]/2(c[118]/1(c[45]/2(i5,i3)),c[91,124,93]/2(c[118]/1(c[45]/2(i5,i4)),c[91,124,93]/2(c[118]/1(c[45]/2(i3,i2)),c[91,124,93]/2(c[118]/1(c[45]/2(i3,i5)),c[91,124,93]/2(c[118]/1(c[45]/2(i3,i3)),c[91,124,93]/2(c[118]/1(c[45]/2(i3,i4)),c[91,124,93]/2(c[118]/1(c[45]/2(i4,i2)),c[91,124,93]/2(c[118]/1(c[45]/2(i4,i5)),c[91,124,93]/2(c[118]/1(c[45]/2(i4,i3)),c[91,124,93]/2(c[118]/1(c[45]/2(i4,i4)),c[91,124,93]/2(c[110]/1(i2),c[91,124,93]/2(c[110]/1(i5),c[91,124,93]/2(c[110]/1(i3),c[91,124,93]/2(c[110]/1(i4),c[91,124,93]/2(c[111]/1(i2),c[91,124,93]/2(c[111]/1(i5),c[91,124,93]/2(c[111]/1(i3),c[91,124,93]/2(c[111]/1(i4),c[91,124,93]/2(c[108]/1(c[45]/2(i2,i2)),c[91,124,93]/2(c[108]/1(c[45]/2(i2,i5)),c[91,124,93]/2(c[108]/1(c[45]/2(i2,i3)),c[91,124,93]/2(c[108]/1(c[45]/2(i2,i4)),c[91,124,93]/2(c[108]/1(c[45]/2(i5,i2)),c[91,124,93]/2(c[108]/1(c[45]/2(i5,i5)),c[91,124,93]/2(c[108]/1(c[45]/2(i5,i3)),c[91,124,93]/2(c[108]/1(c[45]/2(i5,i4)),c[91,124,93]/2(c[108]/1(c[45]/2(i3,i2)),c[91,124,93]/2(c[108]/1(c[45]/2(i3,i5)),c[91,124,93]/2(c[108]/1(c[45]/2(i3,i3)),c[91,124,93]/2(c[108]/1(c[45]/2(i3,i4)),c[91,124,93]/2(c[108]/1(c[45]/2(i4,i2)),c[91,124,93]/2(c[108]/1(c[45]/2(i4,i5)),c[91,124,93]/2(c[108]/1(c[45]/2(i4,i3)),c[91,124,93]/2(c[108]/1(c[45]/2(i4,i4)),nil)))))))))))))))))))))))))))))))))))))))),c[91,124,93]/2(c[45]/2(a[100,112,95,118],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[100,112,95,110],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[100,112,95,108],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[100,112,95,111],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),nil))))))"
]

const _T7_PROG_FORCE = raw"""tp(G, T) :- '$tbl_existing_variant_table'(0, user:G, T, _, _).
st1(G, S) :- ( tp(G, T) -> '$tbl_table_status'(T, S0), ( '$idg_forced'(T) -> F = f ; F = n ), ( '$idg_falsecount'(T, C) -> true ; C = nofc ),
      findall(Q, ('$idg_mono_affects_lazy'(T, _, _, _, A), length(A, Q)), Qs), S = S0/F/C/Qs ; S = none ).
dump(R) :- findall(N-S, (member(N-G, [r-'$fo_r$1', p-'$fo_p$1', e-fe_p(_)]), st1(G, S)), R).
ex(G, L) :- findall(G, G, L0), msort(L0, L).
lg(L) :- findall(X, fo_log(X), L), retractall(fo_log(_)).
:- dynamic (fo_d1/1, fo_d2/1, fe_d/1) as monotonic.
:- dynamic fo_log/1.
:- table (fo_r(min), fo_p(min), fe_p/1) as (monotonic, lazy).
fo_r(X) :- fo_d1(X).
fo_p(X) :- ( fo_r(X) ; fo_d2(X) ).
fe_p(X) :- assertz(fo_log(fe)), fe_d(5), X = 1.
"""

const _T7_CASES_FORCE = [
    (
        "fo01",
        raw"abolish_all_tables, retractall(fo_d1(_)), retractall(fo_d2(_)), retractall(fe_d(_)), retractall(fo_log(_)), assertz(fo_d1(5)), assertz(fo_d2(7)), assertz(fe_d(5)), ex(fo_p(_), A1), ex(fe_p(_), A2), lg(L), dump(D), R = r(A1, A2, L, D)"
    ),
    (
        "fo02",
        raw"retract(fo_d2(7)), dump(D1), assertz(fo_d1(3)), dump(D2), ex(fo_r(_), A), dump(D3), ex(fo_p(_), A2), lg(L), dump(D4), R = r(D1, D2, A, D3, A2, L, D4)"
    ),
    (
        "fo03",
        raw"assertz(fo_d2(9)), assertz(fo_d1(4)), dump(D1), retract(fo_d2(9)), dump(D2), assertz(fo_d1(1)), ex(fo_r(_), A), dump(D3), ex(fo_p(_), A2), dump(D4), R = r(D1, D2, A, D3, A2, D4)"
    ),
    (
        "fo04",
        raw"assertz(fe_d(7), Ref), dump(D1), erase(Ref), dump(D2), ex(fe_p(_), A), lg(L), dump(D3), R = r(D1, D2, A, L, D3)"
    ),
    (
        "fo05",
        raw"assertz(fe_d(8)), assertz(fe_d(9), Ref), retract(fe_d(8)), dump(D1), ex(fe_p(_), A), lg(L), erase(Ref), ex(fe_p(_), A2), lg(L2), dump(D2), R = r(D1, A, L, A2, L2, D2)"
    ),
    (
        "fo06",
        raw"assertz(fe_d(5), Ref), dump(D1), erase(Ref), dump(D2), ex(fe_p(_), A), lg(L), dump(D3), R = r(D1, D2, A, L, D3)"
    )
]

const _T7_PINS_FORCE = [
    "ok",
    "t_fo01 c[116,95,102,111,48,49]/1(c[114]/4(c[91,124,93]/2(c[102,111,95,112]/1(i5),nil),c[91,124,93]/2(c[102,101,95,112]/1(i1),nil),c[91,124,93]/2(a[102,101],nil),c[91,124,93]/2(c[45]/2(a[114],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[112],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[101],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),nil)))))",
    "t_fo02 c[116,95,102,111,48,50]/1(c[114]/7(c[91,124,93]/2(c[45]/2(a[114],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[112],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[102]),i1),nil)),c[91,124,93]/2(c[45]/2(a[101],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),nil))),c[91,124,93]/2(c[45]/2(a[114],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[110]),i1),c[91,124,93]/2(i1,nil))),c[91,124,93]/2(c[45]/2(a[112],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[102]),i3),nil)),c[91,124,93]/2(c[45]/2(a[101],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),nil))),c[91,124,93]/2(c[102,111,95,114]/1(i3),nil),c[91,124,93]/2(c[45]/2(a[114],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[112],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[102]),i3),nil)),c[91,124,93]/2(c[45]/2(a[101],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),nil))),c[91,124,93]/2(c[102,111,95,112]/1(i3),nil),nil,c[91,124,93]/2(c[45]/2(a[114],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[112],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[101],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),nil)))))",
    "t_fo03 c[116,95,102,111,48,51]/1(c[114]/6(c[91,124,93]/2(c[45]/2(a[114],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[110]),i1),c[91,124,93]/2(i1,nil))),c[91,124,93]/2(c[45]/2(a[112],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[110]),i2),c[91,124,93]/2(i1,nil))),c[91,124,93]/2(c[45]/2(a[101],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),nil))),c[91,124,93]/2(c[45]/2(a[114],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[110]),i1),c[91,124,93]/2(i1,nil))),c[91,124,93]/2(c[45]/2(a[112],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[102]),i3),nil)),c[91,124,93]/2(c[45]/2(a[101],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),nil))),c[91,124,93]/2(c[102,111,95,114]/1(i1),nil),c[91,124,93]/2(c[45]/2(a[114],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[112],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[102]),i4),nil)),c[91,124,93]/2(c[45]/2(a[101],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),nil))),c[91,124,93]/2(c[102,111,95,112]/1(i1),nil),c[91,124,93]/2(c[45]/2(a[114],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[112],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[101],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),nil)))))",
    "t_fo04 c[116,95,102,111,48,52]/1(c[114]/5(c[91,124,93]/2(c[45]/2(a[114],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[112],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[101],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),nil))),c[91,124,93]/2(c[45]/2(a[114],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[112],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[101],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),nil))),c[91,124,93]/2(c[102,101,95,112]/1(i1),nil),nil,c[91,124,93]/2(c[45]/2(a[114],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[112],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[101],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),nil)))))",
    "t_fo05 c[116,95,102,111,48,53]/1(c[114]/6(c[91,124,93]/2(c[45]/2(a[114],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[112],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[101],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),nil))),c[91,124,93]/2(c[102,101,95,112]/1(i1),nil),nil,c[91,124,93]/2(c[102,101,95,112]/1(i1),nil),nil,c[91,124,93]/2(c[45]/2(a[114],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[112],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[101],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),nil)))))",
    "t_fo06 c[116,95,102,111,48,54]/1(c[114]/5(c[91,124,93]/2(c[45]/2(a[114],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[112],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[101],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[110]),i1),c[91,124,93]/2(i1,nil))),nil))),c[91,124,93]/2(c[45]/2(a[114],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[112],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[101],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[102]),i2),nil)),nil))),c[91,124,93]/2(c[102,101,95,112]/1(i1),nil),c[91,124,93]/2(a[102,101],nil),c[91,124,93]/2(c[45]/2(a[114],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[112],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[101],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),nil)))))"
]

const _T7_PROG_ROLL = raw"""tp(G, T) :- '$tbl_existing_variant_table'(0, user:G, T, _, _).
st1(G, S) :- ( tp(G, T) -> '$tbl_table_status'(T, S0), ( '$idg_forced'(T) -> F = f ; F = n ), ( '$idg_falsecount'(T, C) -> true ; C = nofc ),
      findall(Q, ('$idg_mono_affects_lazy'(T, _, _, _, A), length(A, Q)), Qs), S = S0/F/C/Qs ; S = none ).
dump(R) :- findall(N-S, (member(G, [ro_p(_), ro_q(_), ro_e(_)]), functor(G, N, _), st1(G, S)), R).
ex(G, L) :- findall(G, G, L0), msort(L0, L).
lg(L) :- findall(X, ro_log(X), L), retractall(ro_log(_)).
rolled(G) :- ( transaction((G, fail)) -> true ; true ).
:- dynamic ro_d/1 as monotonic.
:- dynamic ro_log/1.
:- table (ro_p/1, ro_q/1) as (monotonic, lazy).
:- table ro_e/1 as monotonic.
ro_p(X) :- assertz(ro_log(p)), ro_d(X).
ro_q(X) :- ro_p(X).
ro_e(X) :- ro_d(X).
"""

const _T7_CASES_ROLL = [
    (
        "ro01",
        raw"abolish_all_tables, retractall(ro_d(_)), retractall(ro_log(_)), ex(ro_q(_), A0), ex(ro_e(_), E0), lg(L0), dump(D0), R = r(A0, E0, L0, D0)"
    ),
    (
        "ro02",
        raw"assertz(ro_d(1)), ex(ro_q(_), A), ex(ro_e(_), E), lg(L), dump(D), R = r(A, E, L, D)"
    ),
    (
        "ro03",
        raw"retract(ro_d(1)), dump(D1), rolled((assertz(ro_d(9)), ex(ro_p(_), _))), dump(D2), ex(ro_q(_), A), ex(ro_e(_), E), lg(L), dump(D3), R = r(D1, D2, A, E, L, D3)"
    ),
    (
        "ro04",
        raw"assertz(ro_d(2), Ref), dump(D1), erase(Ref), dump(D2), ex(ro_q(_), A), lg(L), dump(D3), R = r(D1, D2, A, L, D3)"
    ),
    (
        "ro05",
        raw"assertz(ro_d(4), R4), assertz(ro_d(5)), ex(ro_q(_), A1), lg(L1), assertz(ro_d(6), R6), dump(D1), erase(R6), dump(D2), ex(ro_q(_), A2), lg(L2), dump(D3), erase(R4), dump(D4), ex(ro_q(_), A3), ex(ro_e(_), E), dump(D5), R = r(A1, L1, D1, D2, A2, L2, D3, D4, A3, E, D5)"
    ),
    (
        "ro06",
        raw"assertz(ro_d(7)), ex(ro_q(_), A0), lg(_), rolled(assertz(ro_d(8))), dump(D1), assertz(ro_d(10)), rolled((retract(ro_d(7)), assertz(ro_d(11)))), dump(D2), ex(ro_q(_), A), lg(L), dump(D3), R = r(A0, D1, D2, A, L, D3)"
    )
]

const _T7_PINS_ROLL = [
    "ok",
    "t_ro01 c[116,95,114,111,48,49]/1(c[114]/4(nil,nil,c[91,124,93]/2(a[112],nil),c[91,124,93]/2(c[45]/2(a[114,111,95,112],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[114,111,95,113],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[114,111,95,101],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),nil)))))",
    "t_ro02 c[116,95,114,111,48,50]/1(c[114]/4(c[91,124,93]/2(c[114,111,95,113]/1(i1),nil),c[91,124,93]/2(c[114,111,95,101]/1(i1),nil),nil,c[91,124,93]/2(c[45]/2(a[114,111,95,112],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[114,111,95,113],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[114,111,95,101],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),nil)))))",
    "t_ro03 c[116,95,114,111,48,51]/1(c[114]/6(c[91,124,93]/2(c[45]/2(a[114,111,95,112],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[102]),i1),nil)),c[91,124,93]/2(c[45]/2(a[114,111,95,113],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[102]),i1),nil)),c[91,124,93]/2(c[45]/2(a[114,111,95,101],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[102]),i1),nil)),nil))),c[91,124,93]/2(c[45]/2(a[114,111,95,112],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[102]),i1),nil)),c[91,124,93]/2(c[45]/2(a[114,111,95,113],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[102]),i2),nil)),c[91,124,93]/2(c[45]/2(a[114,111,95,101],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[102]),i2),nil)),nil))),nil,nil,c[91,124,93]/2(a[112],nil),c[91,124,93]/2(c[45]/2(a[114,111,95,112],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[114,111,95,113],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[114,111,95,101],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),nil)))))",
    "t_ro04 c[116,95,114,111,48,52]/1(c[114]/5(c[91,124,93]/2(c[45]/2(a[114,111,95,112],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[110]),i1),c[91,124,93]/2(i1,nil))),c[91,124,93]/2(c[45]/2(a[114,111,95,113],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[110]),i2),c[91,124,93]/2(i1,nil))),c[91,124,93]/2(c[45]/2(a[114,111,95,101],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),nil))),c[91,124,93]/2(c[45]/2(a[114,111,95,112],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[102]),i2),nil)),c[91,124,93]/2(c[45]/2(a[114,111,95,113],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[102]),i2),nil)),c[91,124,93]/2(c[45]/2(a[114,111,95,101],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[102]),i1),nil)),nil))),nil,c[91,124,93]/2(a[112],nil),c[91,124,93]/2(c[45]/2(a[114,111,95,112],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[114,111,95,113],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[114,111,95,101],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[102]),i1),nil)),nil)))))",
    "t_ro05 c[116,95,114,111,48,53]/1(c[114]/11(c[91,124,93]/2(c[114,111,95,113]/1(i4),c[91,124,93]/2(c[114,111,95,113]/1(i5),nil)),nil,c[91,124,93]/2(c[45]/2(a[114,111,95,112],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[110]),i1),c[91,124,93]/2(i1,nil))),c[91,124,93]/2(c[45]/2(a[114,111,95,113],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[110]),i2),c[91,124,93]/2(i1,nil))),c[91,124,93]/2(c[45]/2(a[114,111,95,101],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[102]),i4),nil)),nil))),c[91,124,93]/2(c[45]/2(a[114,111,95,112],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[102]),i2),nil)),c[91,124,93]/2(c[45]/2(a[114,111,95,113],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[102]),i2),nil)),c[91,124,93]/2(c[45]/2(a[114,111,95,101],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[102]),i5),nil)),nil))),c[91,124,93]/2(c[114,111,95,113]/1(i4),c[91,124,93]/2(c[114,111,95,113]/1(i5),nil)),c[91,124,93]/2(a[112],nil),c[91,124,93]/2(c[45]/2(a[114,111,95,112],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[114,111,95,113],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[114,111,95,101],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[102]),i5),nil)),nil))),c[91,124,93]/2(c[45]/2(a[114,111,95,112],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[102]),i1),nil)),c[91,124,93]/2(c[45]/2(a[114,111,95,113],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[102]),i1),nil)),c[91,124,93]/2(c[45]/2(a[114,111,95,101],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[102]),i6),nil)),nil))),c[91,124,93]/2(c[114,111,95,113]/1(i5),nil),c[91,124,93]/2(c[114,111,95,101]/1(i5),nil),c[91,124,93]/2(c[45]/2(a[114,111,95,112],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[114,111,95,113],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[114,111,95,101],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),nil)))))",
    "t_ro06 c[116,95,114,111,48,54]/1(c[114]/6(c[91,124,93]/2(c[114,111,95,113]/1(i5),c[91,124,93]/2(c[114,111,95,113]/1(i7),nil)),c[91,124,93]/2(c[45]/2(a[114,111,95,112],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[110]),i1),nil)),c[91,124,93]/2(c[45]/2(a[114,111,95,113],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[110]),i2),nil)),c[91,124,93]/2(c[45]/2(a[114,111,95,101],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),nil))),c[91,124,93]/2(c[45]/2(a[114,111,95,112],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[102]),i3),nil)),c[91,124,93]/2(c[45]/2(a[114,111,95,113],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[102]),i2),nil)),c[91,124,93]/2(c[45]/2(a[114,111,95,101],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[102]),i2),nil)),nil))),c[91,124,93]/2(c[114,111,95,113]/1(i5),c[91,124,93]/2(c[114,111,95,113]/1(i7),c[91,124,93]/2(c[114,111,95,113]/1(i10),nil))),c[91,124,93]/2(a[112],nil),c[91,124,93]/2(c[45]/2(a[114,111,95,112],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[114,111,95,113],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[114,111,95,101],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[102]),i2),nil)),nil)))))"
]

const _T7_PROG_ALIVE = raw"""tp(G, T) :- '$tbl_existing_variant_table'(0, user:G, T, _, _).
st1(G, S) :- ( tp(G, T) -> '$tbl_table_status'(T, S0), ( '$idg_forced'(T) -> F = f ; F = n ), ( '$idg_falsecount'(T, C) -> true ; C = nofc ),
      findall(Q, ('$idg_mono_affects_lazy'(T, _, _, _, A), length(A, Q)), Qs), S = S0/F/C/Qs ; S = none ).
dump(R) :- findall(N-S, (member(G, [lq_p(_), lq_q(_)]), functor(G, N, _), st1(G, S)), R).
ex(G, L) :- findall(G, G, L0), msort(L0, L).
lg(L) :- findall(X, lq_log(X), L), retractall(lq_log(_)).
rolled(G) :- ( transaction((G, fail)) -> true ; true ).
:- dynamic lq_d/1 as monotonic.
:- dynamic (lq_log/1, lq_flag/0).
:- table (lq_p/1, lq_q/1) as (monotonic, lazy).
lq_p(X) :- lq_d(X), assertz(lq_log(p(X))), ( X == 2, \+ lq_flag -> assertz(lq_flag), assertz(lq_d(100)) ; true ).
lq_q(X) :- lq_p(X).
"""

const _T7_CASES_ALIVE = [
    (
        "al01",
        raw"abolish_all_tables, retractall(lq_d(_)), retractall(lq_flag), retractall(lq_log(_)), assertz(lq_d(1)), ex(lq_p(_), A), lg(L), dump(D), R = r(A, L, D)"
    ),
    (
        "al02",
        raw"assertz(lq_d(5)), dump(D1), ex(lq_q(_), A), lg(L), dump(D2), R = r(D1, A, L, D2)"
    ),
    (
        "al03",
        raw"assertz(lq_d(2)), dump(D1), ex(lq_q(_), A), lg(L), dump(D2), ex(lq_p(_), A2), lg(L2), dump(D3), R = r(D1, A, L, D2, A2, L2, D3)"
    ),
    (
        "al04",
        raw"rolled(assertz(lq_d(7))), dump(D1), ex(lq_q(_), A), lg(L), dump(D2), R = r(D1, A, L, D2)"
    ),
    (
        "al05",
        raw"assertz(lq_d(8)), rolled(assertz(lq_d(9))), dump(D1), ex(lq_p(_), A), lg(L), dump(D2), ex(lq_q(_), A2), dump(D3), R = r(D1, A, L, D2, A2, D3)"
    ),
    (
        "al06",
        raw"assertz(lq_d(11)), assertz(lq_d(12)), dump(D1), ex(lq_q(_), A), lg(L), dump(D2), R = r(D1, A, L, D2)"
    )
]

const _T7_PINS_ALIVE = [
    "ok",
    "t_al01 c[116,95,97,108,48,49]/1(c[114]/3(c[91,124,93]/2(c[108,113,95,112]/1(i1),nil),c[91,124,93]/2(c[112]/1(i1),nil),c[91,124,93]/2(c[45]/2(a[108,113,95,112],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[108,113,95,113],a[110,111,110,101]),nil))))",
    "t_al02 c[116,95,97,108,48,50]/1(c[114]/4(c[91,124,93]/2(c[45]/2(a[108,113,95,112],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[110]),i1),c[91,124,93]/2(i1,nil))),c[91,124,93]/2(c[45]/2(a[108,113,95,113],a[110,111,110,101]),nil)),c[91,124,93]/2(c[108,113,95,113]/1(i1),c[91,124,93]/2(c[108,113,95,113]/1(i5),nil)),c[91,124,93]/2(c[112]/1(i5),c[91,124,93]/2(c[112]/1(i5),nil)),c[91,124,93]/2(c[45]/2(a[108,113,95,112],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[108,113,95,113],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),nil))))",
    "t_al03 c[116,95,97,108,48,51]/1(c[114]/7(c[91,124,93]/2(c[45]/2(a[108,113,95,112],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[110]),i1),c[91,124,93]/2(i2,nil))),c[91,124,93]/2(c[45]/2(a[108,113,95,113],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[110]),i2),c[91,124,93]/2(i2,nil))),nil)),c[91,124,93]/2(c[108,113,95,113]/1(i1),c[91,124,93]/2(c[108,113,95,113]/1(i2),c[91,124,93]/2(c[108,113,95,113]/1(i5),c[91,124,93]/2(c[108,113,95,113]/1(i100),nil)))),c[91,124,93]/2(c[112]/1(i2),c[91,124,93]/2(c[112]/1(i100),c[91,124,93]/2(c[112]/1(i100),c[91,124,93]/2(c[112]/1(i2),nil)))),c[91,124,93]/2(c[45]/2(a[108,113,95,112],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[108,113,95,113],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),nil)),c[91,124,93]/2(c[108,113,95,112]/1(i1),c[91,124,93]/2(c[108,113,95,112]/1(i2),c[91,124,93]/2(c[108,113,95,112]/1(i5),c[91,124,93]/2(c[108,113,95,112]/1(i100),nil)))),nil,c[91,124,93]/2(c[45]/2(a[108,113,95,112],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[108,113,95,113],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),nil))))",
    "t_al04 c[116,95,97,108,48,52]/1(c[114]/4(c[91,124,93]/2(c[45]/2(a[108,113,95,112],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[110]),i1),nil)),c[91,124,93]/2(c[45]/2(a[108,113,95,113],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[110]),i2),nil)),nil)),c[91,124,93]/2(c[108,113,95,113]/1(i1),c[91,124,93]/2(c[108,113,95,113]/1(i2),c[91,124,93]/2(c[108,113,95,113]/1(i5),c[91,124,93]/2(c[108,113,95,113]/1(i100),nil)))),nil,c[91,124,93]/2(c[45]/2(a[108,113,95,112],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),c[91,124,93]/2(c[45]/2(a[108,113,95,113],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),nil))))",
    "t_al05 c[116,95,97,108,48,53]/1(c[114]/6(c[91,124,93]/2(c[45]/2(a[108,113,95,112],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),c[91,124,93]/2(i1,nil))),c[91,124,93]/2(c[45]/2(a[108,113,95,113],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[110]),i1),c[91,124,93]/2(i1,nil))),nil)),c[91,124,93]/2(c[108,113,95,112]/1(i1),c[91,124,93]/2(c[108,113,95,112]/1(i2),c[91,124,93]/2(c[108,113,95,112]/1(i5),c[91,124,93]/2(c[108,113,95,112]/1(i8),c[91,124,93]/2(c[108,113,95,112]/1(i100),nil))))),c[91,124,93]/2(c[112]/1(i8),nil),c[91,124,93]/2(c[45]/2(a[108,113,95,112],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),c[91,124,93]/2(i1,nil))),c[91,124,93]/2(c[45]/2(a[108,113,95,113],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[110]),i1),c[91,124,93]/2(i1,nil))),nil)),c[91,124,93]/2(c[108,113,95,113]/1(i1),c[91,124,93]/2(c[108,113,95,113]/1(i2),c[91,124,93]/2(c[108,113,95,113]/1(i5),c[91,124,93]/2(c[108,113,95,113]/1(i8),c[91,124,93]/2(c[108,113,95,113]/1(i100),nil))))),c[91,124,93]/2(c[45]/2(a[108,113,95,112],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),c[91,124,93]/2(i1,nil))),c[91,124,93]/2(c[45]/2(a[108,113,95,113],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),nil))))",
    "t_al06 c[116,95,97,108,48,54]/1(c[114]/4(c[91,124,93]/2(c[45]/2(a[108,113,95,112],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),c[91,124,93]/2(i3,nil))),c[91,124,93]/2(c[45]/2(a[108,113,95,113],c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[110]),i1),c[91,124,93]/2(i2,nil))),nil)),c[91,124,93]/2(c[108,113,95,113]/1(i1),c[91,124,93]/2(c[108,113,95,113]/1(i2),c[91,124,93]/2(c[108,113,95,113]/1(i5),c[91,124,93]/2(c[108,113,95,113]/1(i8),c[91,124,93]/2(c[108,113,95,113]/1(i11),c[91,124,93]/2(c[108,113,95,113]/1(i12),c[91,124,93]/2(c[108,113,95,113]/1(i100),nil))))))),c[91,124,93]/2(c[112]/1(i11),c[91,124,93]/2(c[112]/1(i12),nil)),c[91,124,93]/2(c[45]/2(a[108,113,95,112],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),c[91,124,93]/2(i3,nil))),c[91,124,93]/2(c[45]/2(a[108,113,95,113],c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),nil)),nil))))"
]

const _T7_PROG_FIND = raw"""tp(G, T) :- '$tbl_existing_variant_table'(0, user:G, T, _, _).
st1(G, S) :- ( tp(G, T) -> '$tbl_table_status'(T, S0), ( '$idg_forced'(T) -> F = f ; F = n ), ( '$idg_falsecount'(T, C) -> true ; C = nofc ),
      ( '$idg_mono_index'(T, _) -> I = idx ; I = noidx ),
      findall(Q, ('$idg_mono_affects_lazy'(T, _, _, _, A), length(A, Q)), Qs), S = S0/F/C/I/Qs ; S = none ).
dump(R) :- findall(N-S, (member(G, [fn_s(_), fn_u(_), fn_w(_), fn_l(_)]), functor(G, N, _), st1(G, S)), R).
ex(G, L) :- findall(G, G, L0), msort(L0, L).
lg(L) :- findall(T-N, (member(T, [u, w, l]), aggregate_all(count, (fn_log(X), functor(X, T, _)), N)), L), retractall(fn_log(_)).
cnt(G, N) :- aggregate_all(count, G, N).
:- dynamic fn_d/1 as monotonic.
:- dynamic fn_log/1.
:- table fn_s/1 as monotonic.
:- table (fn_u/1, fn_w/1) as monotonic.
:- table fn_l/1 as (monotonic, lazy).
fn_s(X) :- fn_d(X).
fn_u(Y-Z) :- fn_s(Y), fn_s(Z), assertz(fn_log(u(Y-Z))).
fn_w(X-Y-Z) :- fn_s(X), fn_s(Y), fn_s(Z), assertz(fn_log(w(X-Y-Z))).
fn_l(Y-Z) :- fn_s(Y), fn_s(Z), assertz(fn_log(l(Y-Z))).
"""

const _T7_CASES_FIND = [
    (
        "fn01",
        raw"abolish_all_tables, retractall(fn_d(_)), retractall(fn_log(_)), assertz(fn_d(1)), cnt(fn_u(_), A1), cnt(fn_w(_), A2), cnt(fn_l(_), A3), lg(L), dump(D), R = r(A1, A2, A3, L, D)"
    ),
    (
        "fn02",
        raw"assertz(fn_d(2)), dump(D1), cnt(fn_u(_), A1), cnt(fn_w(_), A2), lg(L), dump(D2), R = r(D1, A1, A2, L, D2)"
    ),
    (
        "fn03",
        raw"assertz(fn_d(3)), cnt(fn_u(_), A1), lg(L1), assertz(fn_d(4)), cnt(fn_w(_), A2), lg(L2), dump(D), R = r(A1, L1, A2, L2, D)"
    ),
    (
        "fn04",
        raw"assertz(fn_d(5)), dump(D1), cnt(fn_l(_), A1), lg(L1), assertz(fn_d(6)), cnt(fn_l(_), A2), lg(L2), cnt(fn_u(_), A3), lg(L3), dump(D2), R = r(D1, A1, L1, A2, L2, A3, L3, D2)"
    ),
    (
        "fn05",
        raw"cnt(fn_l(_), A1), cnt(fn_u(_), A2), cnt(fn_w(_), A3), ex(fn_l(_), L), length(L, N), R = r(A1, A2, A3, N)"
    )
]

const _T7_PINS_FIND = [
    "ok",
    "t_fn01 c[116,95,102,110,48,49]/1(c[114]/5(i1,i1,i1,c[91,124,93]/2(c[45]/2(a[117],i1),c[91,124,93]/2(c[45]/2(a[119],i1),c[91,124,93]/2(c[45]/2(a[108],i1),nil))),c[91,124,93]/2(c[45]/2(a[102,110,95,115],c[47]/2(c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),a[105,100,120]),nil)),c[91,124,93]/2(c[45]/2(a[102,110,95,117],c[47]/2(c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),a[110,111,105,100,120]),nil)),c[91,124,93]/2(c[45]/2(a[102,110,95,119],c[47]/2(c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),a[110,111,105,100,120]),nil)),c[91,124,93]/2(c[45]/2(a[102,110,95,108],c[47]/2(c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),a[110,111,105,100,120]),nil)),nil))))))",
    "t_fn02 c[116,95,102,110,48,50]/1(c[114]/5(c[91,124,93]/2(c[45]/2(a[102,110,95,115],c[47]/2(c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),a[105,100,120]),nil)),c[91,124,93]/2(c[45]/2(a[102,110,95,117],c[47]/2(c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),a[110,111,105,100,120]),nil)),c[91,124,93]/2(c[45]/2(a[102,110,95,119],c[47]/2(c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),a[110,111,105,100,120]),nil)),c[91,124,93]/2(c[45]/2(a[102,110,95,108],c[47]/2(c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[110]),i1),a[110,111,105,100,120]),c[91,124,93]/2(i1,c[91,124,93]/2(i1,nil)))),nil)))),i4,i8,c[91,124,93]/2(c[45]/2(a[117],i3),c[91,124,93]/2(c[45]/2(a[119],i7),c[91,124,93]/2(c[45]/2(a[108],i3),nil))),c[91,124,93]/2(c[45]/2(a[102,110,95,115],c[47]/2(c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),a[105,100,120]),nil)),c[91,124,93]/2(c[45]/2(a[102,110,95,117],c[47]/2(c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),a[110,111,105,100,120]),nil)),c[91,124,93]/2(c[45]/2(a[102,110,95,119],c[47]/2(c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),a[110,111,105,100,120]),nil)),c[91,124,93]/2(c[45]/2(a[102,110,95,108],c[47]/2(c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[110]),i1),a[110,111,105,100,120]),c[91,124,93]/2(i1,c[91,124,93]/2(i1,nil)))),nil))))))",
    "t_fn03 c[116,95,102,110,48,51]/1(c[114]/5(i9,c[91,124,93]/2(c[45]/2(a[117],i5),c[91,124,93]/2(c[45]/2(a[119],i19),c[91,124,93]/2(c[45]/2(a[108],i5),nil))),i64,c[91,124,93]/2(c[45]/2(a[117],i7),c[91,124,93]/2(c[45]/2(a[119],i37),c[91,124,93]/2(c[45]/2(a[108],i7),nil))),c[91,124,93]/2(c[45]/2(a[102,110,95,115],c[47]/2(c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),a[105,100,120]),nil)),c[91,124,93]/2(c[45]/2(a[102,110,95,117],c[47]/2(c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),a[110,111,105,100,120]),nil)),c[91,124,93]/2(c[45]/2(a[102,110,95,119],c[47]/2(c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),a[110,111,105,100,120]),nil)),c[91,124,93]/2(c[45]/2(a[102,110,95,108],c[47]/2(c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[110]),i1),a[110,111,105,100,120]),c[91,124,93]/2(i1,c[91,124,93]/2(i2,c[91,124,93]/2(i3,c[91,124,93]/2(i3,nil)))))),nil))))))",
    "t_fn04 c[116,95,102,110,48,52]/1(c[114]/8(c[91,124,93]/2(c[45]/2(a[102,110,95,115],c[47]/2(c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),a[105,100,120]),nil)),c[91,124,93]/2(c[45]/2(a[102,110,95,117],c[47]/2(c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),a[110,111,105,100,120]),nil)),c[91,124,93]/2(c[45]/2(a[102,110,95,119],c[47]/2(c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),a[110,111,105,100,120]),nil)),c[91,124,93]/2(c[45]/2(a[102,110,95,108],c[47]/2(c[47]/2(c[47]/2(c[47]/2(a[105,110,118,97,108,105,100],a[110]),i1),a[110,111,105,100,120]),c[91,124,93]/2(i1,c[91,124,93]/2(i2,c[91,124,93]/2(i3,c[91,124,93]/2(i4,c[91,124,93]/2(i4,nil))))))),nil)))),i25,c[91,124,93]/2(c[45]/2(a[117],i9),c[91,124,93]/2(c[45]/2(a[119],i61),c[91,124,93]/2(c[45]/2(a[108],i39),nil))),i36,c[91,124,93]/2(c[45]/2(a[117],i11),c[91,124,93]/2(c[45]/2(a[119],i91),c[91,124,93]/2(c[45]/2(a[108],i30),nil))),i36,c[91,124,93]/2(c[45]/2(a[117],i0),c[91,124,93]/2(c[45]/2(a[119],i0),c[91,124,93]/2(c[45]/2(a[108],i0),nil))),c[91,124,93]/2(c[45]/2(a[102,110,95,115],c[47]/2(c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),a[105,100,120]),nil)),c[91,124,93]/2(c[45]/2(a[102,110,95,117],c[47]/2(c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),a[110,111,105,100,120]),nil)),c[91,124,93]/2(c[45]/2(a[102,110,95,119],c[47]/2(c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),a[110,111,105,100,120]),nil)),c[91,124,93]/2(c[45]/2(a[102,110,95,108],c[47]/2(c[47]/2(c[47]/2(c[47]/2(a[99,111,109,112,108,101,116,101],a[110]),i0),a[110,111,105,100,120]),nil)),nil))))))",
    "t_fn05 c[116,95,102,110,48,53]/1(c[114]/4(i36,i36,i216,i36))"
]

# S3C-END
const _T7_GROUPS = [
    (
        key="DEPERR",
        label=raw"DEPERR: `'$idg_add_monotonic_dep'/3` between two tables, one or both without an IDG node: dependency_error(Dst, monotonic(Src)) unless the target is opaque (kills TB7R-DE1 d01 d03 d04, TB7R-DE2 d01 d02, TB7R-DE3 d03 d04, TB7R-DE4 d01)",
        program=_T7_PROG_DEPERR,
        cases=_T7_CASES_DEPERR,
        pins=_T7_PINS_DEPERR
    ),
    (
        key="COLLECT",
        label=raw"COLLECT: `'$tbl_collect_mono_dep'/0`, `'$tbl_propagate_start'/1`, `'$tbl_propagate_end'/1` (kills TB7R-CO1 c01 c02, TB7R-CO2 c03-c06, TB7-propagate-start-flag c02 c07, TB7-inner-monotonic-flag c03-c06)",
        program=_T7_PROG_COLLECT,
        cases=_T7_CASES_COLLECT,
        pins=_T7_PINS_COLLECT
    ),
    (
        key="LAZY",
        label=raw"LAZY: an eager and two lazy monotonic tables over one monotonic dynamic predicate: status, queues, invalidation, forcing, the index (kills TB7-add-dep-lazy-child, TB7-add-dep-lazy-parent, TB7-changed-lazy, TB7-changed-flag-mono, TB7-edge-step-lazy, TB7-monotonic-edge-lazy, TB7-queue-was-nonempty: l02 l03 l04; TB7-edge-step-force, TB7-changed-forced, TB7-changed-falsecount, TB7-scc-complete-false, TB7-scc-complete-start: l05 l07; TB7-mono-index-pred, TB7-index-build-deps: l09)",
        program=_T7_PROG_LAZY,
        cases=_T7_CASES_LAZY,
        pins=_T7_PINS_LAZY
    ),
    (
        key="QUEUE",
        label=raw"QUEUE: the answer queue of a lazy dependency and its reevaluation by hand: `'$idg_mono_empty_queue'/2` (a count, zero, negative), `'$mono_reeval_prepare'/2`, `'$mono_reeval_done'/3`, a retract of a queued answer (kills TB7-empty-queue-count q01, TB7-empty-queue-pred-magic q05, TB7-prune-filter q06, TB7-prune-forced q06 q08, TB7-prune-lazy q06 q08, TB7-reeval-prepare-lazy q09 q10, TB7-reeval-done-count q09, TB7-invalid-deps-count q09 q11; q02 pins the count equal to the queue length, where TB7-empty-queue-bound stays EQUIVALENT, see TB7.py)",
        program=_T7_PROG_QUEUE,
        cases=_T7_CASES_QUEUE,
        pins=_T7_PINS_QUEUE
    ),
    (
        key="SUBMONO",
        label=raw"SUBMONO: `as (subsumptive, monotonic)`: a later call of an instance reuses the complete table, a new clause reaches it and its monotonic consumer (an own-program control: no mutant is attributed to it by name; it adds the subsumptive-monotonic combination to the monotonic files that every TB7 mutant targets)",
        program=_T7_PROG_SUBMONO,
        cases=_T7_CASES_SUBMONO,
        pins=_T7_PINS_SUBMONO
    ),
    # S3C-GROUPS-BEGIN
    (
        key="CHAIN",
        label=raw"CHAIN: a lazy chain over three monotonic dynamic predicates (fan-in, depth 3) and an eager table with a side effect: status, forced, `'$idg_falsecount'/2` and the queue lengths of every table after each clause, retract and call",
        program=_T7_PROG_CHAIN,
        cases=_T7_CASES_CHAIN,
        pins=_T7_PINS_CHAIN
    ),
    (
        key="INDEX",
        label=raw"INDEX: a monotonic parent calling a monotonic TABLE twice (the child's dependency index is built by the second dependency, the later calls and a re-evaluation look it up), a lazy child of its own: answers, the side effect of every continuation, status, forced, `'$idg_falsecount'/2`, index and queue lengths after each clause, retract and call",
        program=_T7_PROG_INDEX,
        cases=_T7_CASES_INDEX,
        pins=_T7_PINS_INDEX
    ),
    (
        key="MODED",
        label=raw"MODED: lazy monotonic tables with a `min` argument over two monotonic dynamic predicates, and an eager one: the aggregate improves, the other branch is added, retracted; side effects of the bodies, status, forced, falsecount, queue lengths",
        program=_T7_PROG_MODED,
        cases=_T7_CASES_MODED,
        pins=_T7_PINS_MODED
    ),
    (
        key="TXN",
        label=raw"TXN: a clause asserted in a transaction that fails (rolled back) while lazy and eager monotonic tables depend on its predicate: status, forced, falsecount and queue lengths before and after the next calls, the side effect of the lazy body, answers",
        program=_T7_PROG_TXN,
        cases=_T7_CASES_TXN,
        pins=_T7_PINS_TXN
    ),
    (
        key="DEPS",
        label=raw"DEPS: monotonic tables whose body calls the SAME monotonic dynamic predicate twice (a variant dependency, found in the chain of the edge: eager and lazy), a variant call in the other order and a non-variant second call (`dp_d(Y), dp_d(5)`): answers, the side effect of every continuation (a duplicated dependency shows as a repeated log line), status, forced, `'$idg_falsecount'/2` and queue lengths after each clause, retract and call",
        program=_T7_PROG_DEPS,
        cases=_T7_CASES_DEPS,
        pins=_T7_PINS_DEPS
    ),
    (
        key="FORCE",
        label=raw"FORCE: a lazy dependent that is INVALID (a retract of its own dynamic dependency) while its lazy `min` child is re-evaluated and replaces its aggregated value (the child's old leaf is deleted, its queues are pruned and the invalid dependent is counted); and a lazy table with a call `fe_d(5)` over a dynamic predicate whose clause of another call (`fe_d(7)`) is queued and then erased: status, forced, `'$idg_falsecount'/2`, queue lengths, side effect of the lazy bodies, answers",
        program=_T7_PROG_FORCE,
        cases=_T7_CASES_FORCE,
        pins=_T7_PINS_FORCE
    ),
    (
        key="ROLL",
        label=raw"ROLL: an INVALID lazy dependent (a retract) and a transaction that reevaluates its lazy child with a new clause and rolls back (the child's answer is deleted while the dependent is still invalid), then a queued clause that is erased before the table is called: status, forced, `'$idg_falsecount'/2` and queue lengths after each step, the side effect of the lazy body, answers",
        program=_T7_PROG_ROLL,
        cases=_T7_CASES_ROLL,
        pins=_T7_PINS_ROLL
    ),
    (
        key="ALIVE",
        label=raw"ALIVE: a lazy monotonic table `lq_p` over a monotonic dynamic predicate and a lazy table `lq_q` over it; the body of `lq_p` asserts a NEW clause of its own dynamic predicate while a queued clause is being pulled in (the reevaluation ends with a live queued clause reference: the table is not complete), a new lazy parent that calls an INVALID lazy table, a rolled-back transaction (invalid, nothing queued) and a queued clause next to it: answers, the side effect of every continuation, status, forced, `'$idg_falsecount'/2` and queue lengths after each step (kills TB7-answer-live-erased, TB7-invalid-deps-queued, TB7-invalid-deps-count, TB7-monotonic-edge-lazy)",
        program=_T7_PROG_ALIVE,
        cases=_T7_CASES_ALIVE,
        pins=_T7_PINS_ALIVE
    ),
    (
        key="FIND",
        label=raw"FIND: monotonic tables that call a monotonic TABLE (`fn_s`) at several call points, so that its dependency index is built, and whose later calls re-register a dependency that already exists in that index while a propagated answer runs the rest of the body (a variant dependency FOUND in the index of the child; a duplicate would run a continuation twice): answers, the side effect of every continuation, status, forced, `'$idg_falsecount'/2`, index and queue lengths after each clause and call, eager and lazy parents (kills TB7-index-find-value, TB7-index-find-hash)",
        program=_T7_PROG_FIND,
        cases=_T7_CASES_FIND,
        pins=_T7_PINS_FIND
    )
    # S3C-GROUPS-END
]

# Rows whose kernel side cannot answer yet: `GROUP/case => owner`. Each is `@test_broken` below, the same comparison as its neighbours.
# FIND/fn04 KNOWINGLY DIFFERS from swipl 10.1.20 (a named DIVERGES, audit D-0894, a consequence of the atom-hash divergence of src/pl-termhash.jl): the variant
# hash of a trie blob is identity-based in the kernel; lazy monotonic body re-run counts can differ from swipl 10.1.20 (kernel 22, swipl 30 in FIND/fn04: the
# lazy table `fn_l`'s body runs, counted by `fn_log(l(_))`, after the second `assertz(fn_d(6))`; the answers are identical, A2 = 36, and so are the eager
# tables' counts). The kernel's answer is the same on the reference, alt and alt_interned term types. The row stays `@test_broken` with these numbers
# (an unexpected pass is an error); fn05 pins what both sides share.
const _T7_BROKEN = Dict{String, String}(
    "FIND/fn04" => "named DIVERGES (D-0894): lazy monotonic body re-run count, kernel 22, swipl 30"
)

@testset "TB7 rows as swipl's: $(g.label)" for g in _T7_GROUPS
    gd, ld, st = _T7_load(g.program, g.cases)
    @test st == "ok"
    @test !isempty(g.cases)                                   # both sides non-empty, through the ONE extractor `_T7_ask`
    kl = String[st]
    for (id, _) in g.cases
        push!(kl, _T7_ask_safe(gd, ld, "t_$id"))
    end
    @test length(kl) == length(g.pins) == length(g.cases) + 1
    for ((id, _), k, p) in zip(g.cases, kl[2:end], g.pins[2:end])
        k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
        if haskey(_T7_BROKEN, "$(g.key)/$id")
            @test_broken k == p                               # $(_T7_BROKEN[...]) above; an unexpected pass is an error
        else
            @test k == p
        end
    end
end

"The atoms (`a[codes]`) of a pinned answer line, in order."
function _T7_atoms(line::AbstractString)::Vector{String}
    return [
        String(Char.(parse.(Int, split(m.captures[1], ',')))) for
        m in eachmatch(r"a\[([0-9,]+)\]", line)
    ]
end
"""
The atoms AND functor names (`a[codes]`, `c[codes]`) of a pinned answer line, in order, WITHOUT the wrapper `t_<id>/1` of the answer: the
pinned text of case `t_d01` is `t_d01(raised(...))` (swipl's own `~q` output of the row's answer `R`, not an assertion of this file), so the
first name of the line is the case's own functor, and the rows below compare the answer `R` alone.
"""
function _T7_names(line::AbstractString)::Vector{String}
    ns = [
        String(Char.(parse.(Int, split(m.captures[1], ',')))) for
        m in eachmatch(r"[ac]\[([0-9,]+)\]", line)
    ]
    @assert !isempty(ns) && startswith(ns[1], "t_")          # the wrapper of the answer line
    return ns[2:end]
end
"The integers (`i<n>`) of a pinned answer line, in order."
function _T7_ints(line::AbstractString)::Vector{BigInt}
    return [parse(BigInt, m.captures[1]) for m in eachmatch(r"(?<![a-z])i(-?[0-9]+)", line)]
end

_T7_group(key) = only(filter(g -> g.key == key, _T7_GROUPS))
"The answer part of the pinned line of case `id` in group `key`."
function _T7_ans(key, id)
    g = _T7_group(key)
    return split(only(filter(l -> startswith(l, "t_$id "), g.pins)), " "; limit=2)[2]
end

# Not vacuous: kills TB7R-DE1 .. DE4, TB7R-CO1, CO2 and every mutant of the group labels above only if the pins differ where the mutant's answer would
@testset "the TB7 rows are not vacuous" begin
    for g in _T7_GROUPS
        @test g.pins[1] == "ok"
        @test length(g.pins) == length(g.cases) + 1
        @test all(!isempty, g.pins)
        for (id, goal) in g.cases
            @test !isempty(goal)
            @test count(l -> startswith(l, "t_$id "), g.pins) == 1
        end
    end
    for k in keys(_T7_BROKEN)                                  # a broken row names a case that exists
        key, id = split(k, "/")
        @test any(==(id), first.(_T7_group(key).cases))
    end
    # DEPERR (DE1, DE4: the error term; DE2: the opaque target; DE3: both sides must have an IDG node to pass): src and dst of the error are in the order dst, monotonic(src)
    @test _T7_names(_T7_ans("DEPERR", "d01")) == [
        "raised", "dependency_error", ":", "user", "pb", "monotonic", ":", "user", "pa"
    ]
    @test _T7_ints(_T7_ans("DEPERR", "d01")) == [1, 1]
    @test _T7_names(_T7_ans("DEPERR", "d02")) == ["ok"]
    @test _T7_ans("DEPERR", "d01") != _T7_ans("DEPERR", "d02")
    @test _T7_names(_T7_ans("DEPERR", "d03"))[1:2] == ["raised", "dependency_error"]
    @test _T7_ints(_T7_ans("DEPERR", "d03")) == [1, 0]                # dst pa(1), src pm(0)
    @test _T7_ints(_T7_ans("DEPERR", "d04")) == [0, 1]                # dst pm(0), src pa(1)
    @test _T7_ans("DEPERR", "d03") != _T7_ans("DEPERR", "d04")
    for id in ("d06", "d07")                                          # both sides with an IDG node: no error (the control of DE3)
        @test _T7_names(_T7_ans("DEPERR", id)) == ["ok"]
    end
    @test _T7_ints(_T7_ans("DEPERR", "d05")) == [0]
    # COLLECT: no collection outside a propagation or a monotonic body (CO1: c01), the saved state comes back (c02, c07), a monotonic body collects, a plain one does not (CO2: c03-c06)
    @test _T7_atoms(_T7_ans("COLLECT", "c01")) == ["no"]
    @test _T7_ints(_T7_ans("COLLECT", "c02")) == [0]
    @test _T7_atoms(_T7_ans("COLLECT", "c02")) == ["yes", "no"]
    @test _T7_atoms(_T7_ans("COLLECT", "c03")) == ["yes"]
    @test _T7_atoms(_T7_ans("COLLECT", "c04")) == ["no"]
    @test _T7_names(_T7_ans("COLLECT", "c05")) == ["[|]", "no", "yes"]
    @test _T7_names(_T7_ans("COLLECT", "c06")) == ["[|]", "yes", "no"]
    @test _T7_ints(_T7_ans("COLLECT", "c07")) == [0, 1]                # the nested start returns 0, then 1
    @test _T7_atoms(_T7_ans("COLLECT", "c07")) == ["yes", "no"]
    @test _T7_ans("COLLECT", "c03") != _T7_ans("COLLECT", "c04")
    # LAZY: a new clause leaves the lazy tables invalid and queues its answer, the eager table is completed at once (l02), a lazy table is forced by an invalidation (l05 vs l06)
    @test _T7_atoms(_T7_ans("LAZY", "l01")) == ["complete", "complete", "complete"]
    @test _T7_atoms(_T7_ans("LAZY", "l02")) == ["invalid", "complete", "invalid"]
    @test _T7_ints(_T7_ans("LAZY", "l02")) == [1, 1]
    @test _T7_atoms(_T7_ans("LAZY", "l03")) == ["invalid"]
    @test _T7_ints(_T7_ans("LAZY", "l03")) == [2, 2]
    @test _T7_ints(_T7_ans("LAZY", "l04")) == [1, 2]
    @test _T7_atoms(_T7_ans("LAZY", "l04")) == ["complete", "complete"]
    @test _T7_atoms(_T7_ans("LAZY", "l05")) == ["invalid", "invalid", "notforced"]
    @test _T7_atoms(_T7_ans("LAZY", "l06")) == ["complete", "complete", "notforced"]
    @test _T7_atoms(_T7_ans("LAZY", "l07")) == ["invalid", "invalid", "invalid", "forced"]
    @test _T7_ints(_T7_ans("LAZY", "l08")) == [2, 2]
    @test _T7_atoms(_T7_ans("LAZY", "l09")) == ["idx", "noidx", "noidx"]
    @test _T7_ans("LAZY", "l02") != _T7_ans("LAZY", "l03")
    @test _T7_ans("LAZY", "l05") != _T7_ans("LAZY", "l07")
    # QUEUE: emptying 2 of 3 leaves 1 (q01), 3 of 3 leaves none (q02), 0 leaves 3 (q03), a negative count is refused and leaves the queue (q04)
    @test _T7_ints(_T7_ans("QUEUE", "q01")) == [1]
    @test _T7_ints(_T7_ans("QUEUE", "q02")) == []
    @test _T7_ints(_T7_ans("QUEUE", "q03")) == [3]
    @test _T7_names(_T7_ans("QUEUE", "q04"))[2:4] ==
        ["raised", "domain_error", "not_less_than_zero"]
    @test _T7_ints(_T7_ans("QUEUE", "q04")) == [-1, 3]
    for (a, b) in (("q01", "q02"), ("q02", "q03"), ("q01", "q03"), ("q03", "q04"))
        @test _T7_ans("QUEUE", a) != _T7_ans("QUEUE", b)
    end
    @test _T7_ints(_T7_ans("QUEUE", "q05")) == [1]
    @test _T7_atoms(_T7_ans("QUEUE", "q06")) == ["invalid", "forced"]
    @test _T7_ints(_T7_ans("QUEUE", "q07")) == [2, 1, 2]
    @test _T7_ints(_T7_ans("QUEUE", "q08")) == [2]
    @test _T7_atoms(_T7_ans("QUEUE", "q09")) == ["invalid", "yes", "invalid", "complete"]
    @test _T7_ints(_T7_ans("QUEUE", "q09")) == [3, 3]
    @test _T7_atoms(_T7_ans("QUEUE", "q10")) == ["no"]
    @test _T7_ints(_T7_ans("QUEUE", "q11")) == [1, 2, 3]
    # SUBMONO: an instance call adds no table (s01, s02: one table), the new clause reaches the table and its consumer (s03), a retract too (s04)
    @test _T7_ints(_T7_ans("SUBMONO", "s01")) == [1, 2, 1]
    @test _T7_ints(_T7_ans("SUBMONO", "s02")) == [1, 2, 3, 1]
    @test _T7_ints(_T7_ans("SUBMONO", "s03")) == [1, 2, 3, 1, 2, 3, 4, 1, 2, 3, 4]
    @test _T7_ints(_T7_ans("SUBMONO", "s04")) == [2, 3, 4, 2, 3, 4]
    @test _T7_ints(_T7_ans("SUBMONO", "s05")) == [1, 1, 2, 1, 3, 1, 3, 2, 2]
    @test _T7_ans("SUBMONO", "s03") != _T7_ans("SUBMONO", "s04")
    # S3C-ASSERT-BEGIN: the dependency-state rows (status atoms of every dump) of the S3c groups; the numbers are swipl's own answers read back
    @test count(==("invalid"), _T7_atoms(_T7_ans("CHAIN", "ch01"))) == 0 &&
        count(==("complete"), _T7_atoms(_T7_ans("CHAIN", "ch01"))) == 5
    @test count(==("invalid"), _T7_atoms(_T7_ans("CHAIN", "ch02"))) == 6 &&
        count(==("complete"), _T7_atoms(_T7_ans("CHAIN", "ch02"))) == 4
    @test count(==("invalid"), _T7_atoms(_T7_ans("CHAIN", "ch03"))) == 7 &&
        count(==("complete"), _T7_atoms(_T7_ans("CHAIN", "ch03"))) == 8
    @test count(==("invalid"), _T7_atoms(_T7_ans("CHAIN", "ch04"))) == 5 &&
        count(==("complete"), _T7_atoms(_T7_ans("CHAIN", "ch04"))) == 10
    @test count(==("invalid"), _T7_atoms(_T7_ans("CHAIN", "ch05"))) == 3 &&
        count(==("complete"), _T7_atoms(_T7_ans("CHAIN", "ch05"))) == 7
    @test count(==("invalid"), _T7_atoms(_T7_ans("INDEX", "ix01"))) == 0 &&
        count(==("complete"), _T7_atoms(_T7_ans("INDEX", "ix01"))) == 2
    @test count(==("invalid"), _T7_atoms(_T7_ans("INDEX", "ix02"))) == 2 &&
        count(==("complete"), _T7_atoms(_T7_ans("INDEX", "ix02"))) == 2
    @test count(==("invalid"), _T7_atoms(_T7_ans("INDEX", "ix03"))) == 4 &&
        count(==("complete"), _T7_atoms(_T7_ans("INDEX", "ix03"))) == 4
    @test count(==("invalid"), _T7_atoms(_T7_ans("MODED", "mn01"))) == 0 &&
        count(==("complete"), _T7_atoms(_T7_ans("MODED", "mn01"))) == 4
    @test count(==("invalid"), _T7_atoms(_T7_ans("MODED", "mn02"))) == 2 &&
        count(==("complete"), _T7_atoms(_T7_ans("MODED", "mn02"))) == 6
    @test count(==("invalid"), _T7_atoms(_T7_ans("MODED", "mn03"))) == 2 &&
        count(==("complete"), _T7_atoms(_T7_ans("MODED", "mn03"))) == 6
    @test count(==("invalid"), _T7_atoms(_T7_ans("MODED", "mn04"))) == 2 &&
        count(==("complete"), _T7_atoms(_T7_ans("MODED", "mn04"))) == 10
    @test count(==("invalid"), _T7_atoms(_T7_ans("MODED", "mn05"))) == 2 &&
        count(==("complete"), _T7_atoms(_T7_ans("MODED", "mn05"))) == 6
    @test count(==("invalid"), _T7_atoms(_T7_ans("MODED", "mn06"))) == 3 &&
        count(==("complete"), _T7_atoms(_T7_ans("MODED", "mn06"))) == 5
    @test count(==("invalid"), _T7_atoms(_T7_ans("TXN", "tx01"))) == 0 &&
        count(==("complete"), _T7_atoms(_T7_ans("TXN", "tx01"))) == 3
    @test count(==("invalid"), _T7_atoms(_T7_ans("TXN", "tx02"))) == 2 &&
        count(==("complete"), _T7_atoms(_T7_ans("TXN", "tx02"))) == 4
    @test count(==("invalid"), _T7_atoms(_T7_ans("TXN", "tx03"))) == 0 &&
        count(==("complete"), _T7_atoms(_T7_ans("TXN", "tx03"))) == 6
    @test count(==("invalid"), _T7_atoms(_T7_ans("TXN", "tx04"))) == 2 &&
        count(==("complete"), _T7_atoms(_T7_ans("TXN", "tx04"))) == 7
    @test count(==("invalid"), _T7_atoms(_T7_ans("DEPS", "dp01"))) == 0 &&
        count(==("complete"), _T7_atoms(_T7_ans("DEPS", "dp01"))) == 4
    @test count(==("invalid"), _T7_atoms(_T7_ans("DEPS", "dp02"))) == 1 &&
        count(==("complete"), _T7_atoms(_T7_ans("DEPS", "dp02"))) == 7
    @test count(==("invalid"), _T7_atoms(_T7_ans("DEPS", "dp03"))) == 2 &&
        count(==("complete"), _T7_atoms(_T7_ans("DEPS", "dp03"))) == 10
    @test count(==("invalid"), _T7_atoms(_T7_ans("DEPS", "dp04"))) == 2 &&
        count(==("complete"), _T7_atoms(_T7_ans("DEPS", "dp04"))) == 6
    @test count(==("invalid"), _T7_atoms(_T7_ans("DEPS", "dp05"))) == 0 &&
        count(==("complete"), _T7_atoms(_T7_ans("DEPS", "dp05"))) == 4
    @test count(==("invalid"), _T7_atoms(_T7_ans("DEPS", "dp06"))) == 4 &&
        count(==("complete"), _T7_atoms(_T7_ans("DEPS", "dp06"))) == 4
    @test count(==("invalid"), _T7_atoms(_T7_ans("FORCE", "fo01"))) == 0 &&
        count(==("complete"), _T7_atoms(_T7_ans("FORCE", "fo01"))) == 3
    @test count(==("invalid"), _T7_atoms(_T7_ans("FORCE", "fo02"))) == 4 &&
        count(==("complete"), _T7_atoms(_T7_ans("FORCE", "fo02"))) == 8
    @test count(==("invalid"), _T7_atoms(_T7_ans("FORCE", "fo03"))) == 5 &&
        count(==("complete"), _T7_atoms(_T7_ans("FORCE", "fo03"))) == 7
    @test count(==("invalid"), _T7_atoms(_T7_ans("FORCE", "fo04"))) == 0 &&
        count(==("complete"), _T7_atoms(_T7_ans("FORCE", "fo04"))) == 9
    @test count(==("invalid"), _T7_atoms(_T7_ans("FORCE", "fo05"))) == 0 &&
        count(==("complete"), _T7_atoms(_T7_ans("FORCE", "fo05"))) == 6
    @test count(==("invalid"), _T7_atoms(_T7_ans("FORCE", "fo06"))) == 2 &&
        count(==("complete"), _T7_atoms(_T7_ans("FORCE", "fo06"))) == 7
    @test count(==("invalid"), _T7_atoms(_T7_ans("ROLL", "ro01"))) == 0 &&
        count(==("complete"), _T7_atoms(_T7_ans("ROLL", "ro01"))) == 3
    @test count(==("invalid"), _T7_atoms(_T7_ans("ROLL", "ro02"))) == 0 &&
        count(==("complete"), _T7_atoms(_T7_ans("ROLL", "ro02"))) == 3
    @test count(==("invalid"), _T7_atoms(_T7_ans("ROLL", "ro03"))) == 6 &&
        count(==("complete"), _T7_atoms(_T7_ans("ROLL", "ro03"))) == 3
    @test count(==("invalid"), _T7_atoms(_T7_ans("ROLL", "ro04"))) == 6 &&
        count(==("complete"), _T7_atoms(_T7_ans("ROLL", "ro04"))) == 3
    @test count(==("invalid"), _T7_atoms(_T7_ans("ROLL", "ro05"))) == 10 &&
        count(==("complete"), _T7_atoms(_T7_ans("ROLL", "ro05"))) == 5
    @test count(==("invalid"), _T7_atoms(_T7_ans("ROLL", "ro06"))) == 6 &&
        count(==("complete"), _T7_atoms(_T7_ans("ROLL", "ro06"))) == 3
    @test count(==("invalid"), _T7_atoms(_T7_ans("ALIVE", "al01"))) == 0 &&
        count(==("complete"), _T7_atoms(_T7_ans("ALIVE", "al01"))) == 1
    @test count(==("invalid"), _T7_atoms(_T7_ans("ALIVE", "al02"))) == 1 &&
        count(==("complete"), _T7_atoms(_T7_ans("ALIVE", "al02"))) == 2
    @test count(==("invalid"), _T7_atoms(_T7_ans("ALIVE", "al03"))) == 2 &&
        count(==("complete"), _T7_atoms(_T7_ans("ALIVE", "al03"))) == 4
    @test count(==("invalid"), _T7_atoms(_T7_ans("ALIVE", "al04"))) == 2 &&
        count(==("complete"), _T7_atoms(_T7_ans("ALIVE", "al04"))) == 2
    @test count(==("invalid"), _T7_atoms(_T7_ans("ALIVE", "al05"))) == 2 &&
        count(==("complete"), _T7_atoms(_T7_ans("ALIVE", "al05"))) == 4
    @test count(==("invalid"), _T7_atoms(_T7_ans("ALIVE", "al06"))) == 1 &&
        count(==("complete"), _T7_atoms(_T7_ans("ALIVE", "al06"))) == 3
    @test count(==("invalid"), _T7_atoms(_T7_ans("FIND", "fn01"))) == 0 &&
        count(==("complete"), _T7_atoms(_T7_ans("FIND", "fn01"))) == 4
    @test count(==("invalid"), _T7_atoms(_T7_ans("FIND", "fn02"))) == 2 &&
        count(==("complete"), _T7_atoms(_T7_ans("FIND", "fn02"))) == 6
    @test count(==("invalid"), _T7_atoms(_T7_ans("FIND", "fn03"))) == 1 &&
        count(==("complete"), _T7_atoms(_T7_ans("FIND", "fn03"))) == 3
    @test count(==("invalid"), _T7_atoms(_T7_ans("FIND", "fn04"))) == 1 &&
        count(==("complete"), _T7_atoms(_T7_ans("FIND", "fn04"))) == 7
    # S3C-ASSERT-END
end

@testset "the TB7 pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "TB7 ROWS LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
        # without swipl the pins are all there is: the load line `ok`, then one `t_<id> answer` line per case, in order
        for g in _T7_GROUPS
            @test g.pins[1] == "ok"
            @test [first(split(l, " ")) for l in g.pins[2:end]] ==
                ["t_$id" for (id, _) in g.cases]
        end
    else
        for g in _T7_GROUPS
            f = joinpath(mktempdir(), "tb7rows_swipl.pl")
            write(f, _T7_text(g.program, g.cases))
            @test _T7_swipl_lines(f, ["t_$id" for (id, _) in g.cases]) == g.pins
        end
    end
end
