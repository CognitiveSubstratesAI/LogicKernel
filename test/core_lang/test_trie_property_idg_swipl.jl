# ORIGINAL: a LIVE differential of the branches of `'$trie_property'/2` that read a trie's IDG node or its compiled clause (pl-trie.c:4304-4313
# `compiled_size`, :4326-4331 `invalidated` and `reevaluated`, :4336-4351 `idg_affected_count`, `idg_dependent_count` and `idg_size`) against swipl at the
# pin (swipl-devel 18168e62, 10.1.20). Group: trie-property (library/tableutil.pl:504 reads `idg_size`; tests/tabling/test_idg_sets.pl and
# test_answer_discard.pl name `idg_size` and `compiled_size`).
#   * One program, consulted by both: four tables `as incremental` over the incremental dynamic `tp_d/1` (`tp_t` calls `tp_q`, `tp_s` and `tp_d`;
#     `tp_q` and `tp_s` call `tp_p`; `tp_p` calls `tp_d`), so `tp_p` and the dynamic node each have TWO affected nodes and `tp_t` THREE dependents.
#     The cases `t_tpNN(R)` run in order in one database; `R` is built IN PROLOG and written with `~q`, so every pin is swipl's own text.
#   * A property list is `[invalidated, reevaluated, idg_affected_count, idg_dependent_count, idg_size, compiled_size]`: `none` for a failed branch,
#     `int` for a `compiled_size` > 0 (the number is a machine size: swipl 160 and 192 where the kernel counts `8 * sizeofClause` bytes, a DIVERGES
#     of the function). `idg_size` is pinned EXACTLY: 80 (= sizeof(idg_node), the edge sets hold at most one pointer) and 136 (80 + the 56 bytes of a
#     block of four, `sizeof_block(4, 0)`), because the kernel computes it from the same sizes (SIZEOF_IDG_NODE, `idg_set_sizeof`).
#   * Every pinned line is swipl's (two byte-identical runs, 2026-11-14); with `swipl` on PATH the live lines are compared with the pins too.
#   * tp05 is a monotonic chain (`tm_q` calls `tm_p`): the child's `idg_mono` adds `sizeof(idg_mono)` 24 and `sizeofTablePP` 136 (32 + 40 + 4 * 16, one
#     entry in a table of four slots) to the 80, so the kernel's modelled capacity (`sizeofTablePP`, white-box testset below) is pinned at one entry.
#     KNOWN DIFFERENCE (named): with more entries swipl's capacity follows its reprobe history, the kernel's a doubling rule; no row grows the table.
#   * UNVERIFIED on the kernel (nothing was compiled when this file was written): every kernel answer; the gate decides.
# allow-new-artifact: TBP, the rows of the '$trie_property' branches, after test/core_lang/test_tabling_idg_swipl.jl
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — these built-ins ride the term layer through the FLI (unify, get, the trie blobs)
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TP = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_tps(x) = lk_sym(_TP, Symbol(x))

const _TP_PROGRAM = raw"""
:- table tp_p/1 as incremental.
:- table tp_q/1 as incremental.
:- table tp_s/1 as incremental.
:- table tp_t/1 as incremental.
:- table tm_p/1 as monotonic.
:- table tm_q/1 as monotonic.
:- dynamic([tp_d/1], [incremental(true)]).
:- dynamic([tm_d/1], [monotonic(true)]).
tp_d(1).
tm_d(1).
tm_p(X) :- tm_d(X).
tm_q(X) :- tm_p(X).
tp_p(X) :- tp_d(X).
tp_q(X) :- tp_p(X).
tp_s(X) :- tp_p(X).
tp_t(X) :- tp_q(_), tp_s(_), tp_d(X).
tp_tab(G, T) :- '$tbl_existing_variant_table'(0, user:G, T, _, _).
tp_props(T, L) :- findall(V, ( member(P, [invalidated, reevaluated, idg_affected_count, idg_dependent_count, idg_size, compiled_size]),
        Q =.. [P, V0], ( '$trie_property'(T, Q) -> ( P == compiled_size, V0 > 0 -> V = int ; V = V0 ) ; V = none ) ), L).
tp_all(R) :- tp_tab(tp_t(_), T), tp_tab(tp_q(_), Q), tp_tab(tp_s(_), S), tp_tab(tp_p(_), P),
    '$idg_edge'(P, dependent, D), tp_props(T, LT), tp_props(Q, LQ), tp_props(S, LS), tp_props(P, LP), tp_props(D, LD),
    R = r(t(LT), q(LQ), s(LS), p(LP), d(LD)).
t_tp01(R) :- tp_t(_), tp_all(R).
t_tp02(R) :- assertz(tp_d(2)), tp_all(R).
t_tp03(R) :- tp_t(_), tp_all(R).
t_tp04(R) :- trie_new(T), tp_props(T, L0), trie_insert(T, a, 1), trie_insert(T, b, 2), ( trie_gen_compiled(T, _) -> true ; true ),
    tp_props(T, L1), R = r(L0, L1).
t_tp05(R) :- tm_q(_), tp_tab(tm_q(_), Q), tp_tab(tm_p(_), P), tp_props(Q, LQ), tp_props(P, LP), R = r(q(LQ), p(LP)).
tp_q1(G, A) :- ( catch(call(G, R), E, R = exc(E)) -> true ; R = failed ), format(atom(A), "~q", [R]).
"""

const _TP_CASES = ["t_tp01", "t_tp02", "t_tp03", "t_tp04", "t_tp05"]

# swipl 10.1.20 (`tp_q1(t_tp<NN>, A)`, in the order of `_TP_CASES`), two identical runs (md5 equal), 2026-11-14
const _TP_PINNED = [
    # tp01: complete; nothing invalidated, no clause yet (the answer tries are not compiled); the tables' edge counts and sizes
    "r(t([0,0,0,3,136,none]),q([0,0,1,1,80,none]),s([0,0,1,1,80,none]),p([0,0,2,1,136,none]),d([0,0,2,0,136,none]))",
    # tp02: `assertz(tp_d(2))` invalidates the dynamic node and the four tables once (`invalidated` 1); nothing re-evaluated yet
    "r(t([1,0,0,3,136,none]),q([1,0,1,1,80,none]),s([1,0,1,1,80,none]),p([1,0,2,1,136,none]),d([1,0,2,0,136,none]))",
    # tp03: re-evaluated once (`reevaluated` 1) and the answer tries are compiled (`compiled_size` an integer); the dynamic node has no clause
    "r(t([1,1,0,3,136,int]),q([1,1,1,1,80,int]),s([1,1,1,1,80,int]),p([1,1,2,1,136,int]),d([1,0,2,0,136,none]))",
    # tp04: a plain trie has no IDG node (the four branches fail); `compiled_size` fails until the trie is compiled
    "r([none,none,none,none,none,none],[none,none,none,none,none,int])",
    # tp05: a monotonic table with a monotonic child: the child's `mono` holds one dependency table, so `idg_size` is 80 + 24 + sizeofTablePP (136) = 240
    "r(q([0,0,0,1,80,none]),p([0,0,1,0,240,none]))",
]

"The `~q` text of each case's answer, in order, from swipl at the pin."
function _tp_swipl_lines()::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "tp.pl")
        write(
            f,
            _TP_PROGRAM * ":- initialization((forall(member(G, [" * join(_TP_CASES, ",") *
            "]), (tp_q1(G, A), write(A), nl)), halt)).\n"
        )
        read(pipeline(addenv(`swipl -q $f`, "LC_ALL" => "C"); stdin=devnull, stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

"The `~q` text of the answer of `case`, run as `tp_q1(case, A)` in the kernel."
function _tp_ask(gd, ld, case::String)::String
    proc = LK.isCurrentProcedure(sym_key(_tps("tp_q1")), 2, LK.MODULE_user(gd))
    (proc === nothing || !LK.isDefinedProcedure(gd, proc)) && return "tp_q1 undefined"
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 2)
    LK.putSlotValue!(ld, a + 1, _tps(case), LK.PutVarMap())
    LK.putSlotValue!(ld, a + 2, mk_var(_TP, LK.fresh_var_keys!(1)), LK.PutVarMap())
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

# the kernel's answers of the four cases, from one database (the cases run in order)
function _tp_kernel_lines()::Vector{String}
    f = joinpath(mktempdir(), "trie_property_idg.pl")
    write(f, _TP_PROGRAM)
    gd = LK.PL_global_data{_TP}()
    ld = LK.PL_local_data{_TP}(gd)
    st, _ = LK.load_file!(gd, ld, f)
    st === :ok || return ["load: $st"]
    return [_tp_ask(gd, ld, case) for case in _TP_CASES]
end

# an exception while loading or asking becomes five lines that differ from the pins (a throw outside a testset gives no verdict in CI mode)
const _TP_KERNEL = try
    _tp_kernel_lines()
catch e
    ["exception: $(typeof(e))" for _ in _TP_CASES]
end

@testset "tp01-tp03: the counters, the sizes and the edge counts of an incremental chain, as swipl's (pl-trie.c:4326-4351)" begin
    for (i, pin) in enumerate(_TP_PINNED[1:3])
        @test _TP_KERNEL[i] == pin
        # must-fail corruption: a counter or a size off by one is not the pin
        @test _TP_KERNEL[i] != replace(pin, "136" => "135"; count=1)
    end
    # the invalidated counter is 0 before the assert, 1 after it; the reevaluated one is 1 only after the re-evaluation
    @test occursin("t([0,0,", _TP_KERNEL[1]) && occursin("t([1,0,", _TP_KERNEL[2]) && occursin("t([1,1,", _TP_KERNEL[3])
    @test occursin("d([1,0,2,0,136,none])", _TP_KERNEL[3])      # the dynamic node was invalidated, never re-evaluated: 0
end

@testset "tp04: a trie without an IDG node fails the four branches; compiled_size fails until the trie is compiled (pl-trie.c:4304-4351)" begin
    @test _TP_KERNEL[4] == _TP_PINNED[4]
    @test _TP_KERNEL[4] != replace(_TP_PINNED[4], "[none,none,none,none,none,int]" => "[none,none,none,none,none,none]")
end

@testset "tp05: the mono dependency table is part of idg_size (pl-trie.c:4341-4351: sizeof(*idg->mono) + sizeofTablePP(idg->mono->deps))" begin
    @test _TP_KERNEL[5] == _TP_PINNED[5]
    @test _TP_KERNEL[5] != replace(_TP_PINNED[5], "240" => "80")      # the mono part dropped: 80 only
    @test _TP_KERNEL[5] != replace(_TP_PINNED[5], "240" => "104")     # the table part dropped: 80 + 24
end

@testset "sizeofTablePP: the modelled capacity (os/pl-table.c sizeofTable; DIVERGES documented)" begin
    N = LK.idg_node{_TP}
    ht = IdDict{N, LK.idg_mdep{_TP, N}}()
    @test LK.sizeofTablePP(ht) == LK.SIZEOF_TABLE + LK.SIZEOF_KVS + 4 * LK.SIZEOF_SYMBOL == 136     # newHTablePP(4)
    @test LK.SIZEOF_TABLE == 32 && LK.SIZEOF_KVS == 40 && LK.SIZEOF_SYMBOL == 16
    @test LK.SIZEOF_IDG_NODE == 80 && LK.SIZEOF_IDG_MONO == 24
    @test LK.sizeofTablePP(ht) != 135
    @test LK.sizeofTablePP(IdDict{Int, Int}(1 => 1, 2 => 2)) == 136                 # 2 * 2 > 4 is false: still four slots
    @test LK.sizeofTablePP(IdDict{Int, Int}(1 => 1, 2 => 2, 3 => 3)) == 32 + 40 + 8 * 16 == 200   # doubled once
end

if Sys.which("swipl") !== nothing
    @testset "the pinned lines are swipl's, live (trie-property)" begin
        @test _tp_swipl_lines() == _TP_PINNED
    end
end
