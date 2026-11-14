# ORIGINAL: a LIVE differential of `'$tbl_node_answer'/2` (pl-tabling.c:8957-8969 at the pin, swipl-devel 18168e62, 10.1.20),
# `take_table_value` (:2804-2822, reached through `empty_variant_table` by every `abolish_all_tables` of a non-empty variant table)
# and `save_tabling_status` / `restore_tabling_status` (:2539-2566) against swipl at the pin. Groups: lz = the lazy monotonic units
# of tests/tabling/test_monotonic_lazy.pl that reach `'$tbl_node_answer'` (the lazy reevaluation, boot/tabling.pl
# `reeval_monotonic_node`: `'$idg_mono_affects_lazy'/5` hands the queued answers as node handles, the dependency's
# `'$tbl_node_answer'/2` turns each into its answer), lc = a DETERMINISTIC closure in place of the random test unit
# tabling_monotonic_lazy_15 (fixed edges, three tabling regimes compared), ab = the abolish-through-`empty_variant_table`
# rows taken from tests/tabling/test_tabling.pl (tabling_ex1, tabling_ex2, mode_components2) and its `bas` unit (start_tabling),
# na = the argument checks of `'$tbl_node_answer'/2` (PL_get_pointer_ex), wb = LK-only white-box rows.
#   * Upstream test names (one case per unit that reaches the predicate; MEASURED at the pin by wrapping the predicate):
#       lz03 tabling_monotonic_lazy_3 `intermediate` (2 calls), lz04 _4 `lazy_on_eager` (1), lz05a/lz05b _5 `lazy_on_eager`,
#       `lazy_on_eager_retract` (2 in all), lz06 _6 `lazy_reeval` (3), lz10 _10 `false_deps` (3), lc15 _15 `closure` (deterministic here),
#       lzab mono_subsumptive.pl, unit mono_abstract, test `lazy`: it needs `max_table_subgoal_size_action` (TB8's flag), so it
#       has its own program and testset: with the flag unknown to the kernel it must answer `no_flag` (owner TB8 flips it to the pin
#       when wip/tb8 is merged), with the flag known it must equal the pin.
#   * The plunit assertions (`expect/3`, `expect_valid`, `expect_invalid`, `assertion(\+ reeval)`) are recorded as values in the
#     answer term, `incr_is_invalid/1` as `'$idg_falsecount'` > 0 of the variant table (what library(increval) does); the case
#     answers are swipl's own text (`format(atom(A), "~q", [R])`, answers sorted as `expect/3` does). The call counts of
#     `'$tbl_node_answer'/2` per case are recorded by `wrap_predicate` (case lz00 installs the wrapper, lz99 reads the counts).
#   * Every pinned line is swipl's (swipl 10.1.20, two byte-identical runs, 2026-11-13: command and output in
#     evidence/TAB1/w2_verify.md of the channel); with `swipl` on PATH the live answers are compared with the pins too.
#   * The lazy monotonic kernel rows need `get_procedure(..., GP_FIND)` for `'$idg_add_mono_dyn_dep'/3`, which refuses by name
#     until V9 (see test_tabling_monotonic_swipl.jl: mono01-mono08), so lz*/lc15 are expected to fail on the kernel until then.
#   * UNVERIFIED on the kernel (nothing was compiled when these rows were written): every kernel answer; the gate decides.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — these built-ins ride the term layer through the FLI (unify, get, the trie blobs)
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TI = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_tis(x) = lk_sym(_TI, Symbol(x))

const _TI_PROGRAM = raw"""
:- dynamic lz_hit/0.
:- dynamic lz_calls/2.
lz_n(N) :- findall(x, lz_hit, L), length(L, N).
lz_q(G, A) :- lz_n(N0), ( catch(call(G, R), E, R = exc(E)) -> true ; R = failed ), lz_n(N1), D is N1-N0,
    ( D > 0 -> assertz(lz_calls(G, D)) ; true ), format(atom(A), "~q", [R]).
lz_inv(G) :- '$tbl_existing_variant_table'(0, user:G, T, _, _), '$idg_falsecount'(T, C), C > 0.
lz_f(G, F) :- ( lz_inv(G) -> F = invalid ; F = valid ).
lz_ex(T, G, L) :- findall(T, G, L0), sort(L0, L).
lz_yn(G, R) :- ( call(G) -> R = yes ; R = no ).

:- dynamic l3_d/1 as monotonic.
:- table (l3_p1/1, l3_p2/1) as (monotonic, lazy).
l3_p1(X) :- l3_d(X).
l3_p2(X) :- l3_p1(X).

:- dynamic l4_d/1 as monotonic.
:- table l4_p1/1 as monotonic.
:- table l4_p2/1 as (monotonic, lazy).
l4_p1(X) :- l4_d(X).
l4_p2(X) :- l4_p1(X).

:- dynamic l5_d/1 as monotonic.
:- table l5_p1/1 as (monotonic, lazy).
:- table l5_p2/1 as monotonic.
l5_p1(X) :- l5_d(X).
l5_p2(X) :- l5_p1(X).

:- dynamic (l6_d1/1, l6_d2/1) as monotonic.
:- table (l6_p(min), l6_r(min), l6_q(min)) as (monotonic, lazy).
:- dynamic l6_reeval/0.
l6_r(X) :- l6_d1(X).
l6_q(X) :- l6_d2(X).
l6_p(X) :- assert(l6_reeval), l6_r(X) ; l6_q(X).

:- dynamic (l10_d1/1, l10_d2/1, l10_d3/1) as monotonic.
:- table (l10_p/1, l10_a/1, l10_b/1, l10_c/1) as (monotonic, lazy).
l10_p(X) :- ( l10_a(X) ; l10_b(X) ; l10_d3(X) ).
l10_b(X) :- l10_c(X).
l10_c(X) :- l10_d1(X).
l10_a(X) :- l10_d2(X).

:- dynamic lc_dm/2 as monotonic.
:- dynamic lc_dml/2 as monotonic.
:- dynamic lc_dt/2.
:- table lc_t/2.
lc_t(A, B) :- lc_dt(A, B).
lc_t(A, B) :- lc_t(A, M), lc_dt(M, B).
:- table lc_tm/2 as monotonic.
lc_tm(A, B) :- lc_dm(A, B).
lc_tm(A, B) :- lc_tm(A, M), lc_dm(M, B).
:- table lc_tml/2 as (monotonic, lazy).
lc_tml(A, B) :- lc_dml(A, B).
lc_tml(A, B) :- lc_tml(A, M), lc_dml(M, B).
lc_solve(P, Ps) :- ( P == lc_t -> abolish_table_subgoals(lc_t(_, _)) ; true ),
    findall(A-B, call(P, A, B), Ps0), sort(Ps0, Ps).
lc_step(A-B, Len-Same) :- assertz(lc_dm(A, B)), assertz(lc_dml(A, B)), assertz(lc_dt(A, B)),
    lc_solve(lc_t, Ok), lc_solve(lc_tm, M), lc_solve(lc_tml, L), length(Ok, Len),
    ( M == Ok, L == Ok -> Same = same ; Same = differ ).
lc_steps([], []).
lc_steps([E|Es], [S|Ss]) :- lc_step(E, S), lc_steps(Es, Ss).

:- table ab_a/2.
ab_a(X, Y) :- ab_a(X, Z), ab_a(Z, Y).
ab_a(X, Y) :- ab_e(X, Y).
ab_e(1, 2).
ab_e(2, 3).
:- table ab_b/2.
ab_b(X, Y) :- ab_b(X, _), ab_b(_, Y).
ab_b(X, Y) :- ab_e(X, Y).
:- table (ab_adv(_, _, lattice(ab_or/3)), ab_r11(_, _, _, lattice(ab_or/3))).
ab_or(A, B, C) :- C is A+B.
ab_adv(A, B, 1) :- ab_stu(A), ab_prof(B), ab_proj(C, A), ab_proj(C, B), ab_r11(A, B, C, _).
ab_r11(A, B, C, 1) :- ab_pub(D, A, C), ab_pub(D, B, C).
ab_stu(harry).
ab_prof(ben).
ab_proj(pr1, harry).
ab_proj(pr1, ben).
ab_proj(pr2, harry).
ab_proj(pr2, ben).
ab_pub(p1, harry, pr1).
ab_pub(p1, ben, pr1).
ab_pub(p2, harry, pr1).
ab_pub(p2, ben, pr1).
ab_pub(p3, harry, pr2).
ab_pub(p3, ben, pr2).
ab_pub(p4, harry, pr2).
ab_pub(p4, ben, pr2).
:- table ab_nc/1.
ab_nc(1).
ab_nc(2).
ab_n(N) :- ( '$tbl_local_variant_table'(V) -> findall(x, trie_gen(V, _, _), L), length(L, N) ; N = none ).
ab_all(L) :- findall(X, ab_a(X, _), L0), sort(L0, L).

t_lz00(R) :- set_prolog_flag(access_level, system),
    wrap_predicate(system:'$tbl_node_answer'(_, _), lz_probe, W, (assertz(lz_hit), W)),
    set_prolog_flag(access_level, user), R = wrapped.
t_lz03(R) :- abolish_all_tables, retractall(l3_d(_)), forall(l3_p2(_), true), assertz(l3_d(1)),
    lz_f(l3_p1(_), I1), lz_f(l3_p2(_), I2), lz_ex(X, l3_p2(X), A1), lz_f(l3_p1(_), V1), lz_f(l3_p2(_), V2),
    assertz(l3_d(2)), lz_ex(X, l3_p2(X), A2), R = r(I1, I2, A1, V1, V2, A2).
t_lz04(R) :- abolish_all_tables, retractall(l4_d(_)), assertz(l4_d(1)), lz_ex(X, l4_p1(X), A1), lz_ex(X, l4_p2(X), A2),
    assertz(l4_d(2)), lz_ex(X, l4_p1(X), A3), lz_f(l4_p2(_), I), lz_ex(X, l4_p2(X), A4), R = r(A1, A2, A3, I, A4).
t_lz05a(R) :- abolish_all_tables, retractall(l5_d(_)), assertz(l5_d(1)), lz_ex(X, l5_p1(X), A1), lz_ex(X, l5_p2(X), A2),
    assertz(l5_d(2)), lz_f(l5_p2(_), I), lz_ex(X, l5_p2(X), A3), R = r(A1, A2, I, A3).
t_lz05b(R) :- abolish_all_tables, retractall(l5_d(_)), assertz(l5_d(1), Ref), lz_ex(X, l5_p1(X), A1), lz_ex(X, l5_p2(X), A2),
    assertz(l5_d(2)), lz_f(l5_p2(_), I1), lz_ex(X, l5_p2(X), A3), erase(Ref),
    lz_f(l5_p1(_), I2), lz_f(l5_p2(_), I3), lz_ex(X, l5_p2(X), A4), lz_ex(X, l5_p1(X), A5), R = r(A1, A2, I1, A3, I2, I3, A4, A5).
t_lz06(R) :- abolish_all_tables, retractall(l6_d1(_)), retractall(l6_d2(_)), lz_ex(X, l6_p(X), A0), retractall(l6_reeval),
    assertz(l6_d1(1)), lz_ex(X, l6_p(X), A1), lz_yn(l6_reeval, E1), assertz(l6_d1(0)), lz_ex(X, l6_p(X), A2), lz_yn(l6_reeval, E2),
    assertz(l6_d2(-1)), lz_ex(X, l6_p(X), A3), lz_yn(l6_reeval, E3), assertz(l6_d2(2)), lz_ex(X, l6_p(X), A4), lz_yn(l6_reeval, E4),
    R = r(A0, A1-E1, A2-E2, A3-E3, A4-E4).
t_lz10(R) :- abolish_all_tables, retractall(l10_d1(_)), retractall(l10_d2(_)), retractall(l10_d3(_)), lz_ex(X, l10_p(X), A0),
    assertz(l10_d1(1)), assertz(l10_d2(2)), assertz(l10_d3(3)), lz_ex(X, l10_p(X), A1), R = r(A0, A1).
t_lc15(R) :- abolish_all_tables, retractall(lc_dt(_, _)), retractall(lc_dm(_, _)), retractall(lc_dml(_, _)),
    lc_steps([3-1, 1-2, 2-5, 5-3, 4-4, 2-6, 6-7, 7-1], R).
t_ab01(R) :- abolish_all_tables, ab_all(L1), ab_n(N1), abolish_all_tables, ab_n(N2), ab_all(L2), ab_n(N3), R = r(L1, N1, N2, L2, N3).
t_ab02(R) :- abolish_all_tables, findall(X-Y, ab_b(X, Y), L0), sort(L0, L1), ab_n(N1), abolish_all_tables, ab_n(N2),
    findall(X-Y, ab_b(X, Y), L2a), sort(L2a, L2), R = r(L1, N1, N2, L2).
t_ab03(R) :- abolish_all_tables, ab_adv(harry, ben, X), ab_n(N1), abolish_all_tables, ab_n(N2), ab_adv(harry, ben, Y), R = r(X, N1, N2, Y).
t_ab04(R) :- abolish_all_tables, '$wrapped_implementation'(ab_nc(X), table, Worker),
    findall(X, '$tabling':start_tabling(0, user:ab_nc(X), Worker), L0), msort(L0, L1),
    findall(X, '$tabling':start_tabling(0, user:ab_nc(X), Worker), L2a), msort(L2a, L2),
    '$tbl_variant_table'(0, user:ab_nc(_), _, S, _, _), abolish_all_tables, ab_n(N), R = r(L1, L2, S, N).
t_na01(R) :- catch('$tbl_node_answer'(foo, _), error(E, _), R = raised(E)).
t_na02(R) :- catch('$tbl_node_answer'(_, _), error(E, _), R = raised(E)).
t_na03(R) :- catch('$tbl_node_answer'(1.5, _), error(E, _), R = raised(E)).
t_na04(R) :- catch('$tbl_node_answer'(f(x), _), error(E, _), R = raised(E)).
t_lz99(R) :- findall(G-D, lz_calls(G, D), L0), sort(L0, R).
"""

const _TI_CASES = [
    "t_lz00", "t_lz03", "t_lz04", "t_lz05a", "t_lz05b", "t_lz06", "t_lz10", "t_lc15",
    "t_ab01", "t_ab02", "t_ab03", "t_ab04", "t_na01", "t_na02", "t_na03", "t_na04", "t_lz99"
]

# swipl 10.1.20 (`lz_q(t_..., A)`, in the order of `_TI_CASES`), two identical runs (md5 equal), 2026-11-13
const _TI_PINNED = String[
    "wrapped",
    "r(invalid,invalid,[1],valid,valid,[1,2])",
    "r([1],[1],[1,2],invalid,[1,2])",
    "r([1],[1],invalid,[1,2])",
    "r([1],[1],invalid,[1,2],invalid,invalid,[2],[2])",
    "r([],[1]-no,[0]-no,[-1]-no,[-1]-no)",
    "r([],[1,2,3])",
    "[1-same,3-same,6-same,16-same,17-same,21-same,26-same,37-same]",
    "r([1,2],3,none,[1,2],3)",
    "r([1-2,1-3,2-2,2-3],1,none,[1-2,1-3,2-2,2-3])",
    "r(2,3,none,2)",
    "r([1,2],[1,2],complete,none)",
    "raised(type_error(address,foo))",
    "raised(instantiation_error)",
    "raised(type_error(address,1.5))",
    "raised(type_error(address,f(x)))",
    "[t_lc15-36,t_lz03-2,t_lz04-1,t_lz05a-1,t_lz05b-1,t_lz06-3,t_lz10-3,t_na01-1,t_na02-1,t_na03-1,t_na04-1]"
]

"The `~q` text of each case's answer, in order, from swipl at the pin."
function _ti_swipl_lines(program::String, cases::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "w2.pl")
        write(
            f,
            program * ":- initialization((forall(member(G, [" * join(cases, ",") *
            "]), (lz_q(G, A), write(A), nl)), halt)).\n"
        )
        read(
            pipeline(addenv(`swipl -q $f`, "LC_ALL" => "C"); stdin=devnull, stderr=devnull),
            String
        )
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

"The `~q` text of the answer of `case`, run as `lz_q(case, A)` in the kernel."
function _ti_ask(gd, ld, case::String)::String
    proc = LK.isCurrentProcedure(sym_key(_tis("lz_q")), 2, LK.MODULE_user(gd))
    (proc === nothing || !LK.isDefinedProcedure(gd, proc)) && return "lz_q undefined"
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 2)
    LK.putSlotValue!(ld, a + 1, _tis(case), LK.PutVarMap())
    LK.putSlotValue!(ld, a + 2, mk_var(_TI, LK.fresh_var_keys!(1)), LK.PutVarMap())
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    rc = LK.PL_next_solution(gd, ld, qid)
    ans = if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
        t = lk_answers(ld, ((a + 1):(a + 1))...)[1]
        kind(t) === SYM ? sym_text(t) : "not an atom"
    else
        rc == LK.PL_S_EXCEPTION ? "exception" : "failed"
    end
    LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
    return ans
end

"A fresh database with `program` consulted: `(gd, ld, status)`."
function _ti_load(program::String)
    f = joinpath(mktempdir(), "tabling_w2.pl")
    write(f, program)
    gd = LK.PL_global_data{_TI}()
    ld = LK.PL_local_data{_TI}(gd)
    st, _ = LK.load_file!(gd, ld, f)
    return gd, ld, st
end

@testset "'\$tbl_node_answer'/2 and the abolish path as swipl's (lz, lc, ab, na)" begin
    gd, ld, st = _ti_load(_TI_PROGRAM)
    @test st === :ok
    @test length(_TI_CASES) == length(_TI_PINNED) && !isempty(_TI_PINNED)       # both sides non-empty, one zip below
    for (case, pin) in zip(_TI_CASES, _TI_PINNED)
        @test _ti_ask(gd, ld, case) == pin
    end
    # the must-fail corruption row: a pin with its first answer changed is not what the kernel answers
    @test _ti_ask(gd, ld, "t_na01") !=
        replace(_TI_PINNED[findfirst(==("t_na01"), _TI_CASES)], "foo" => "bar")

    if Sys.which("swipl") !== nothing
        @test _ti_swipl_lines(_TI_PROGRAM, _TI_CASES) == _TI_PINNED
    end
end

# `'$tbl_node_answer'/2` with an integer that names no node: upstream dereferences the address (its answer is undefined, the
# pinned build stops), the kernel's handle is `answer_ref(serial, nid)` and a handle naming no trie or node FAILS (DIVERGES).
@testset "'\$tbl_node_answer'/2 with a handle naming no node fails (LK-only)" begin
    prog = raw"""
lz_q(G, A) :- ( catch(call(G, R), error(E, _), R = raised(E)) -> true ; R = failed ), format(atom(A), "~q", [R]).
t_nz0(R) :- '$tbl_node_answer'(0, R).
t_nz5(R) :- '$tbl_node_answer'(5, R).
t_nzh(R) :- '$tbl_node_answer'(9999999999, R).
t_nzn(R) :- '$tbl_node_answer'(-1, R).
"""
    gd, ld, st = _ti_load(prog)
    @test st === :ok
    got = [_ti_ask(gd, ld, c) for c in ("t_nz0", "t_nz5", "t_nzh", "t_nzn")]
    @test !isempty(got) && got == fill("failed", 4)
    @test got != fill("raised(type_error(address,foo))", 4)                      # must-fail row: not an error term
end

# tests/tabling/test_mono_subsumptive.pl, unit mono_abstract, test `lazy`: the only call of `'$tbl_node_answer'/2` in that file
# (MEASURED at the pin: 1 call). It sets `max_table_subgoal_size_action` to `abstract` (TB8's flag, wip/tb8, owner TB8): the kernel
# without that flag answers `no_flag`, which is what this row then asserts; once TB8 is merged the answer must be the pin
# (`_TI_ABS_PIN`) and TB8's merge removes the `no_flag` branch. Program and pin: evidence/TAB1/w2_verify.md.
const _TI_ABS_PROGRAM = raw"""
lz_q(G, A) :- ( catch(call(G, R), E, R = exc(E)) -> true ; R = failed ), format(atom(A), "~q", [R]).
:- dynamic lm_e/1 as monotonic.
:- table lm_la/1 as (subgoal_abstract(0), monotonic, lazy).
:- table lm_lb/1 as (monotonic, lazy).
lm_la(args(X)) :- lm_e(X).
lm_lb(X) :- lm_la(args(X)).
t_lzab(R) :-
    ( current_prolog_flag(max_table_subgoal_size_action, Old) -> true ; Old = none ),
    (   Old == none
    ->  R = no_flag
    ;   set_prolog_flag(max_table_subgoal_size_action, abstract),
        abolish_all_tables, retractall(lm_e(_)),
        ( lm_lb(c) -> R0 = yes ; R0 = no ),
        assertz(lm_e(c)),
        ( lm_lb(c) -> R1 = yes ; R1 = no ),
        set_prolog_flag(max_table_subgoal_size_action, Old),
        R = r(Old, R0, R1)
    ).
"""
const _TI_ABS_PIN = "r(error,no,yes)"

@testset "mono_abstract lazy as swipl's (TB8's flag)" begin
    gd, ld, st = _ti_load(_TI_ABS_PROGRAM)
    @test st === :ok
    ans = _ti_ask(gd, ld, "t_lzab")
    @test ans in ("no_flag", _TI_ABS_PIN)
    @test ans != "failed" && ans != "lz_q undefined"                         # must-fail row: a failing or missing case is neither
    if Sys.which("swipl") !== nothing
        @test _ti_swipl_lines(_TI_ABS_PROGRAM, ["t_lzab"]) == [_TI_ABS_PIN]
    end
end

@testset "take_table_value! appends in order (wb)" begin
    vals = UInt64[]
    for v in (UInt64(0x10), UInt64(0x08), UInt64(0x18))
        @test LK.take_table_value!(vals, v) === nothing
    end
    @test vals == UInt64[0x10, 0x08, 0x18]                                       # the order of delivery, not sorted
    @test vals != UInt64[0x08, 0x10, 0x18]                                       # must-fail row: the sorted order is not it
    @test length(vals) == 3 && !isempty(vals)
    LK.take_table_value!(vals, UInt64(0x08))                                     # a repeated value is kept (no dedup)
    @test vals == UInt64[0x10, 0x08, 0x18, 0x08]
end

@testset "save_tabling_status / restore_tabling_status (wb)" begin
    gd = LK.PL_global_data{_TI}()
    ld = LK.PL_local_data{_TI}(gd)
    tb = ld.tabling
    c0 = LK.tbl_component{_TI}()
    tb.component = c0
    tb.has_scheduling_component = true
    tb.in_answer_completion = true
    tb.in_assert_propagation = true
    @test tb.saved_status === nothing
    s1 = LK.tbl_status{_TI}()
    LK.save_tabling_status(ld, s1)
    @test s1.scc === c0 && s1.hsc && s1.iac && s1.iap && s1.prev === nothing      # the state holds the old values
    @test tb.saved_status === s1                                                  # linked
    @test tb.component === nothing && !tb.has_scheduling_component &&
        !tb.in_answer_completion && !tb.in_assert_propagation                   # a fresh status
    # nested: the second save chains to the first
    c1 = LK.tbl_component{_TI}()
    tb.component = c1
    tb.in_assert_propagation = true
    s2 = LK.tbl_status{_TI}()
    LK.save_tabling_status(ld, s2)
    @test s2.scc === c1 && !s2.hsc && !s2.iac && s2.iap && s2.prev === s1 &&
        tb.saved_status === s2
    LK.restore_tabling_status(ld, s2)
    @test tb.component === c1 && !tb.has_scheduling_component && !tb.in_answer_completion &&
        tb.in_assert_propagation && tb.saved_status === s1
    LK.restore_tabling_status(ld, s1)
    @test tb.component === c0 && tb.has_scheduling_component && tb.in_answer_completion &&
        tb.in_assert_propagation && tb.saved_status === nothing
    # must-fail row: the restored component is the saved one, not the other
    @test !(tb.component === c1)
end
