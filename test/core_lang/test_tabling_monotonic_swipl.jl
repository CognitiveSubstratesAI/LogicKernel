# ORIGINAL: a LIVE differential of the MONOTONIC tabling of pl-tabling.c (TAB1 TB7) against swipl at the pin (swipl-devel
# 18168e62, 10.1.20): `:- table _ as monotonic` over `:- dynamic _ as monotonic` (and `as (incremental, monotonic)`), the
# propagation of a new clause into a COMPLETE table (`'$tbl_monotonic_add_answer'/2`, `'$idg_add_monotonic_dep'/3`,
# `'$idg_add_mono_dyn_dep'/3`, `'$tbl_propagate_start'/1`, `'$tbl_propagate_end'/1`, `'$mono_idg_changed'/2`), the
# invalidation on a retract (`'$idg_mono_invalidate'/1`, `'$mono_reeval_*'`) and `abolish_all_tables/0`. Group: mono (the
# upstream tests tests/tabling/test_monotonic.pl, test_monotonic_lazy.pl run the same programs under plunit; these rows are
# the same predicates without plunit, in one database, in order).
#   * One program, consulted by both: cases `t_mono<NN>(R)` run in order; each answer is written with
#     `format(atom(A), "~q", [R])` IN PROLOG, so the pins are swipl's own text (answers sorted where the order is the
#     tables' business). No table, dependency or queue is ever printed.
#   * Every pinned line is swipl's (swipl 10.1.20, two byte-identical runs, 2026-11-10); with `swipl` on PATH the live
#     answers are compared with the pins too.
#   * The kernel rows need the stack (TB1-TB3 tabling, TB6 IDG, TB7); `'$idg_add_mono_dyn_dep'/3` calls
#     `get_procedure(..., GP_FIND)`, which refuses by name until V9, so mono01-mono08 are expected to fail on the kernel
#     until then (docs/architecture.md, TB7 section).
#   * UNVERIFIED on the kernel (nothing was compiled when these rows were written): every kernel answer; the gate decides.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — these built-ins ride the term layer through the FLI (unify, get, the trie blobs)
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TI = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_tis(x) = lk_sym(_TI, Symbol(x))

const _TI_PROGRAM = raw"""
:- table tm_p/1 as monotonic.
:- dynamic tm_d/1 as monotonic.
:- table tm_c/2 as monotonic.
:- dynamic tm_l/2 as monotonic.
:- dynamic tm_i/1 as (incremental, monotonic).
:- table tm_pi/1 as monotonic.
:- table tm_qi/1 as incremental.
tm_p(X) :- tm_d(Y), X is Y+1.
tm_c(X, Z) :- tm_c(X, Y), tm_c(Y, Z).
tm_c(X, Y) :- tm_l(X, Y).
tm_pi(X) :- tm_i(Y), X is Y+1.
tm_qi(X) :- tm_i(Y), X is Y+2.
tm_q(G, A) :- ( catch(call(G, R), E, R = exc(E)) -> true ; R = failed ), format(atom(A), "~q", [R]).
t_mono01(R) :- ( tm_p(_) -> R0 = some ; R0 = none ), assertz(tm_d(0)), findall(X, tm_p(X), L), R = r(R0, L).
t_mono02(R) :- assertz(tm_d(5)), findall(X, tm_p(X), L0), sort(L0, L), R = L.
t_mono03(R) :- tm_d(5), retract(tm_d(5)), findall(X, tm_p(X), L0), sort(L0, L), R = L.
t_mono04(R) :- findall(X-Y, tm_c(X, Y), L0), assertz(tm_l(a, b)), assertz(tm_l(b, c)), findall(X-Y, tm_c(X, Y), L1), sort(L1, L), R = r(L0, L).
t_mono05(R) :- assertz(tm_l(c, d)), findall(X-Y, tm_c(X, Y), L0), sort(L0, L), length(L, N), R = r(N, L).
t_mono06(R) :- assertz(tm_i(0)), findall(X, tm_pi(X), L1), findall(X, tm_qi(X), L2), assertz(tm_i(10)), findall(X, tm_pi(X), L3a), sort(L3a, L3), findall(X, tm_qi(X), L4a), sort(L4a, L4), R = r(L1, L2, L3, L4).
t_mono07(R) :- retractall(tm_i(_)), findall(X, tm_pi(X), L1), findall(X, tm_qi(X), L2), R = r(L1, L2).
t_mono08(R) :- abolish_all_tables, findall(X, tm_p(X), L0), sort(L0, L), R = L.
t_mono09(R) :- '$tbl_variant_table'(0, user:tm_p(_), T, S, Sk, M), '$is_answer_trie'(T, Ty),
    ( var(M) -> Mo = unbound ; Mo = M ), ( Sk = ret(_) -> Sko = ret1 ; Sko = Sk ), R = r(S, Mo, Sko, Ty).
"""

const _TI_CASES = ["t_mono01", "t_mono02", "t_mono03", "t_mono04", "t_mono05", "t_mono06", "t_mono07", "t_mono08", "t_mono09"]

# swipl 10.1.20 (`tm_q(t_mono<NN>, A)`, in order), two identical runs
const _TI_PINNED = [
    "r(none,[1])",
    "[1,6]",
    "[1]",
    "r([],[a-b,a-c,b-c])",
    "r(6,[a-b,a-c,a-d,b-c,b-d,c-d])",
    "r([1],[2],[1,11],[2,12])",
    "r([],[])",
    "[1]",
    "r(complete,unbound,ret1,monotonic(eager))",   # mono09 (TB7M5): `\$tbl_variant_table` of the complete monotonic table outside propagation: IsMono stays unbound
]

"The `~q` text of each case's answer, in order, from swipl at the pin."
function _ti_swipl_lines()::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "tm.pl")
        write(
            f,
            _TI_PROGRAM * ":- initialization((forall(member(G, [" * join(_TI_CASES, ",") *
            "]), (tm_q(G, A), write(A), nl)), halt)).\n"
        )
        read(pipeline(addenv(`swipl -q $f`, "LC_ALL" => "C"); stdin=devnull, stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

"The `~q` text of the answer of `case`, run as `tm_q(case, A)` in the kernel."
function _ti_ask(gd, ld, case::String)::String
    proc = LK.isCurrentProcedure(sym_key(_tis("tm_q")), 2, LK.MODULE_user(gd))
    (proc === nothing || !LK.isDefinedProcedure(gd, proc)) && return "tm_q undefined"
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 2)
    LK.putSlotValue!(ld, a + 1, _tis(case), LK.PutVarMap())
    LK.putSlotValue!(ld, a + 2, mk_var(_TI, LK.fresh_var_keys!(1)), LK.PutVarMap())
    qid = LK.PL_open_query(gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a)
    rc = LK.PL_next_solution(gd, ld, qid)
    ans = if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
        t = lk_answers(ld, (a + 1:a + 1)...)[1]
        kind(t) === SYM ? sym_text(t) : "not an atom"
    else
        rc == LK.PL_S_EXCEPTION ? "exception" : "failed"
    end
    LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
    return ans
end

@testset "monotonic tabling as swipl's (mono)" begin
    f = joinpath(mktempdir(), "tabling_monotonic.pl")
    write(f, _TI_PROGRAM)
    gd = LK.PL_global_data{_TI}()
    ld = LK.PL_local_data{_TI}(gd)
    st, _ = LK.load_file!(gd, ld, f)
    @test st === :ok
    for (case, pin) in zip(_TI_CASES, _TI_PINNED)
        @test _ti_ask(gd, ld, case) == pin
    end
    @test ld.tabling.idg_edge_states.live == 0          # every '$idg_edge' state was given back

    if Sys.which("swipl") !== nothing
        @test _ti_swipl_lines() == _TI_PINNED
    end
end
