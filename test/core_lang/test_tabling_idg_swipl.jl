# ORIGINAL: a LIVE differential of the incremental dependency graph of pl-tabling.c (TAB1 TB6; audit D-0477) against swipl at
# the pin (swipl-devel 18168e62, 10.1.20): `'$idg_edge'/3`, `'$idg_falsecount'/2`, `'$idg_forced'/1`, `'$idg_false_edge'/3`,
# `'$idg_thread_summary'/3` (pl-tabling.c:8562-8850, :9028-9300, :9826-9963), the change propagation of an incremental
# dynamic predicate (`idg_changed`) and the `domain_error(idg_edge_dir, _)` of `idg_edge_gen`. Group: idg (the upstream
# tests tests/tabling/test_idg_sets.pl and test_incr_*.pl exercise the same predicates through `abolish_all_tables` and
# `incr_*`; these rows read the graph directly).
#   * One program, consulted by both: `ti_p/1` tabled `as incremental` over the incremental dynamic `ti_d/1`; the cases
#     `t_idg<NN>(R)` run in order in one database (idg01 calls `ti_p(_)`, idg02 asserts `ti_d(2)`), each answer written
#     with `format(atom(A), "~q", [R])` IN PROLOG, so the pins are swipl's own text. A trie is never printed.
#   * Every pinned line is swipl's (swipl 10.1.20, two byte-identical runs, 2026-11-10); with `swipl` on PATH the live
#     answers are compared with the pins too.
#   * The kernel rows need the stack: `start_tabling` (TB2/TB3) and the `S_INCR_DYNAMIC` edge of a dynamic call (TB6c,
#     `idg_add_dyncall`); on wip/tb6 alone they are expected to fail (docs: evidence/TB6/handoff2.md, open item 1).
#   * UNVERIFIED on the kernel (nothing was compiled when these rows were written): every kernel answer; the gate decides.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — these built-ins ride the term layer through the FLI (unify, get, the trie blobs)
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TI = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_tis(x) = lk_sym(_TI, Symbol(x))

const _TI_PROGRAM = raw"""
:- table ti_p/1 as incremental.
:- dynamic([ti_d/1], [incremental(true)]).
ti_d(1).
ti_p(X) :- ti_d(X).
ti_tab(T) :- '$tbl_existing_variant_table'(0, user:ti_p(_), T, _, _).
ti_q(G, A) :- ( catch(call(G, R), E, R = exc(E)) -> true ; R = failed ), format(atom(A), "~q", [R]).
t_idg01(R) :- ti_p(_), ti_tab(T),
    findall(Dir-S, ('$idg_edge'(T, Dir, D), '$tbl_table_status'(D, S)), R0), '$idg_falsecount'(T, F), R = r(R0, F).
t_idg02(R) :- ti_tab(T), assertz(ti_d(2)), '$idg_falsecount'(T, F), ( '$idg_forced'(T) -> Fo = yes ; Fo = no ), R = r(F, Fo).
t_idg03(R) :- ti_tab(T), catch(('$idg_edge'(T, bogus, _), R = ok), error(E, _), R = raised(E)).
t_idg04(R) :- ti_tab(T), findall(S, '$idg_false_edge'(T, _, S), R0), '$idg_thread_summary'(main, N, E), R = r(R0, N, E).
"""

const _TI_CASES = ["t_idg01", "t_idg02", "t_idg03", "t_idg04"]

# swipl 10.1.20 (`ti_q(t_idg<NN>, A)`, in order), two identical runs
const _TI_PINNED = [
    "r([dependent-(dynamic)],0)",
    "r(1,no)",
    "raised(domain_error(idg_edge_dir,bogus))",
    "r([dynamic],2,1)",
]

"The `~q` text of each case's answer, in order, from swipl at the pin."
function _ti_swipl_lines()::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "ti.pl")
        write(
            f,
            _TI_PROGRAM * ":- initialization((forall(member(G, [" * join(_TI_CASES, ",") *
            "]), (ti_q(G, A), write(A), nl)), halt)).\n"
        )
        read(pipeline(addenv(`swipl -q $f`, "LC_ALL" => "C"); stdin=devnull, stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

"The `~q` text of the answer of `case`, run as `ti_q(case, A)` in the kernel."
function _ti_ask(gd, ld, case::String)::String
    proc = LK.isCurrentProcedure(sym_key(_tis("ti_q")), 2, LK.MODULE_user(gd))
    (proc === nothing || !LK.isDefinedProcedure(gd, proc)) && return "ti_q undefined"
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

@testset "the IDG as swipl's (idg)" begin
    f = joinpath(mktempdir(), "tabling_idg.pl")
    write(f, _TI_PROGRAM)
    gd = LK.PL_global_data{_TI}()
    ld = LK.PL_local_data{_TI}(gd)
    st, _ = LK.load_file!(gd, ld, f)
    @test st === :ok
    for (case, pin) in zip(_TI_CASES, _TI_PINNED)
        @test _ti_ask(gd, ld, case) == pin
    end
    @test ld.tabling.idg_edge_states.live == 0          # every '$idg_edge'/'$idg_false_edge' state was given back

    if Sys.which("swipl") !== nothing
        @test _ti_swipl_lines() == _TI_PINNED
    end
end
