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
# UNVERIFIED on the kernel (nothing was compiled when these rows were written): every kernel answer, and every kill named in a label (read off the rows, not observed).
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
    ("c02", raw"'$tbl_propagate_start'(Old), cd(A), '$tbl_propagate_end'(Old), cd(B), R = r(Old, A, B)"),
    ("c03", raw"findall(X, cm(X), L), R = L"),
    ("c04", raw"findall(X, cn(X), L), R = L"),
    ("c05", raw"findall(X, co(X), L), R = L"),
    ("c06", raw"findall(X, cmm(X), L), R = L"),
    ("c07", raw"'$tbl_propagate_start'(O1), '$tbl_propagate_start'(O2), '$tbl_propagate_end'(O2), cd(A), '$tbl_propagate_end'(O1), cd(B), R = r(O1, O2, A, B)")
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
    ("l01", raw"forall(member(G, [lp(_), mp(_), lq(_)]), forall(G, true)), ts(lp(_), A), ts(mp(_), B), ts(lq(_), C), R = r(A, B, C)"),
    ("l02", raw"assertz(ld(1)), ts(lp(_), A), ts(mp(_), B), ts(lq(_), C), qa(lp(_), Q1), qa(lq(_), Q2), R = r(s(A, B, C), q(Q1, Q2))"),
    ("l03", raw"assertz(ld(2)), ts(lp(_), A), qa(lp(_), Q1), qa(lq(_), Q2), R = r(A, Q1, Q2)"),
    ("l04", raw"findall(X, lq(X), L0), msort(L0, L), ts(lp(_), A), ts(lq(_), C), qa(lp(_), Q1), qa(lq(_), Q2), R = r(L, A, C, Q1, Q2)"),
    ("l05", raw"tp(lp(_), T), '$idg_mono_invalidate'(T), ts(lp(_), A), ts(lq(_), C), fo(lp(_), F), R = r(A, C, F)"),
    ("l06", raw"findall(X, lq(X), L0), msort(L0, L), ts(lp(_), A), ts(lq(_), C), fo(lp(_), F), R = r(L, A, C, F)"),
    ("l07", raw"retract(ld(1)), ts(lp(_), A), ts(mp(_), B), ts(lq(_), C), fo(lp(_), F), R = r(A, B, C, F)"),
    ("l08", raw"findall(X, lq(X), L0), msort(L0, L), findall(X, mp(X), M0), msort(M0, M), R = r(L, M)"),
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
    ("q06", raw"rs, assertz(ld(1)), assertz(ld(2)), retract(ld(1)), qa(lp(_), Q), ts(lp(_), S), fo(lp(_), F), R = r(Q, S, F)"),
    ("q07", raw"rs, assertz(ld(1)), assertz(ld(2)), tp(lp(_), T), '$idg_mono_invalidate'(T), qa(lp(_), Q), ts(lp(_), S), findall(X, lp(X), L0), msort(L0, L), R = r(Q, S, L)"),
    ("q08", raw"rs, assertz(ld(1)), assertz(ld(2)), retractall(ld(1)), qa(lp(_), Q), ts(lp(_), S), findall(X, lp(X), L0), msort(L0, L), R = r(Q, S, L)"),
    ("q09", raw"rs, assertz(ld(1)), assertz(ld(2)), assertz(ld(3)), tp(lp(_), T), ts(lp(_), S0), ( '$mono_reeval_prepare'(T, Size) -> P = yes ; P = no ), ts(lp(_), S1), '$idg_mono_affects_lazy'(T, _, _, Ref, Ans), length(Ans, C), '$idg_mono_empty_queue'(Ref, C), qa(lp(_), Q), ( '$mono_reeval_done'(T, Size, Deps) -> D = yes(Deps) ; D = no ), ts(lp(_), S2), R = r(S0, P, Size, S1, C, Q, D, S2)"),
    ("q10", raw"tp(lp(_), T), ( '$mono_reeval_prepare'(T, Size) -> R = r(yes, Size) ; R = r(no) )"),
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
    ("s01", raw"assertz(sd(1)), assertz(sd(2)), findall(X, sm(X), L0), msort(L0, L), findall(x, sm(2), M), tt(sm(_), N), R = r(L, M, N)"),
    ("s02", raw"assertz(sd(3)), findall(X, sm(X), L0), msort(L0, L), findall(x, sm(2), M), findall(x, sm(3), M3), tt(sm(_), N), R = r(L, M, M3, N)"),
    ("s03", raw"findall(X, sc(X), L0), msort(L0, L), assertz(sd(4)), findall(X, sc(X), L1), msort(L1, L2), findall(X, sm(X), L3), msort(L3, L4), R = r(L, L2, L4)"),
    ("s04", raw"retract(sd(1)), findall(X, sm(X), L0), msort(L0, L), findall(X, sc(X), L1), msort(L1, L2), findall(x, sm(2), M), R = r(L, L2, M)"),
    ("s05", raw"assertz(se(a, 1)), assertz(se(b, 2)), findall(Y, sn(a, Y), L0), findall(X-Y, sn(X, Y), L1), msort(L1, L), assertz(se(a, 3)), findall(Y, sn(a, Y), M0), msort(M0, M), findall(X-Y, sn(X, Y), N1), msort(N1, N), tt(sn(_, _), T), R = r(L0, L, M, N, T)")
]

const _T7_PINS_SUBMONO = [
    "ok",
    "t_s01 c[116,95,115,48,49]/1(c[114]/3(c[91,124,93]/2(i1,c[91,124,93]/2(i2,nil)),c[91,124,93]/2(a[120],nil),i1))",
    "t_s02 c[116,95,115,48,50]/1(c[114]/4(c[91,124,93]/2(i1,c[91,124,93]/2(i2,c[91,124,93]/2(i3,nil))),c[91,124,93]/2(a[120],nil),c[91,124,93]/2(a[120],nil),i1))",
    "t_s03 c[116,95,115,48,51]/1(c[114]/3(c[91,124,93]/2(i1,c[91,124,93]/2(i2,c[91,124,93]/2(i3,nil))),c[91,124,93]/2(i1,c[91,124,93]/2(i2,c[91,124,93]/2(i3,c[91,124,93]/2(i4,nil)))),c[91,124,93]/2(i1,c[91,124,93]/2(i2,c[91,124,93]/2(i3,c[91,124,93]/2(i4,nil))))))",
    "t_s04 c[116,95,115,48,52]/1(c[114]/3(c[91,124,93]/2(i2,c[91,124,93]/2(i3,c[91,124,93]/2(i4,nil))),c[91,124,93]/2(i2,c[91,124,93]/2(i3,c[91,124,93]/2(i4,nil))),c[91,124,93]/2(a[120],nil)))",
    "t_s05 c[116,95,115,48,53]/1(c[114]/5(c[91,124,93]/2(i1,nil),c[91,124,93]/2(c[45]/2(a[97],i1),c[91,124,93]/2(c[45]/2(a[98],i2),nil)),c[91,124,93]/2(i1,c[91,124,93]/2(i3,nil)),c[91,124,93]/2(c[45]/2(a[97],i1),c[91,124,93]/2(c[45]/2(a[97],i3),c[91,124,93]/2(c[45]/2(a[98],i2),nil))),i2))"
]

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
    )
]

# Rows whose kernel side cannot answer yet: `GROUP/case => owner`. Each is `@test_broken` below, the same comparison as its neighbours.
const _T7_BROKEN = Dict{String, String}()

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
"The atoms AND functor names (`a[codes]`, `c[codes]`) of a pinned answer line, in order."
function _T7_names(line::AbstractString)::Vector{String}
    return [
        String(Char.(parse.(Int, split(m.captures[1], ',')))) for
        m in eachmatch(r"[ac]\[([0-9,]+)\]", line)
    ]
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
    @test _T7_names(_T7_ans("QUEUE", "q04"))[2:4] == ["raised", "domain_error", "not_less_than_zero"]
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
