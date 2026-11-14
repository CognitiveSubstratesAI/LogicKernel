# ORIGINAL: rows of the transaction tables (TAB1 TB9) that NO upstream test reaches, pinned on swipl at 18168e62 (10.1.20).
# NOT UPSTREAM CASES: no upstream test nests a transaction over a table (tests/transaction/test_transactions.pl nests with no
# table; tests/transaction/test_transaction_tabling.pl and tests/tabling/test_transact_*.pl use one transaction level), none
# makes a transaction fail through a constraint or a bulk announce over a table, none abolishes a table inside a transaction.
# Each row is a program of this file run on swipl at the pin (two identical runs): the pins are swipl's answers, not an upstream
# expectation. The 29 upstream cases are test_tabling_transaction_swipl.jl, the hand-built state is
# test_tabling_transaction_wb_swipl.jl; this file is the third leg and carries the kill rows of five TB9 mutants:
#   TB9-hook-rollback-fail    <- cf_constraint, cf_bulk_announce      (the outermost transaction fails: the tables roll back)
#   TB9-hook-nested-merge     <- nm_merge, nm_merge_fresh             (a committed nested transaction hands its table trail up)
#   TB9-hook-nested-rollback  <- nr_snapshot, nr_failed, nr_constraint (a discarded nested transaction rolls its tables back)
#   TB9-hook-restore          <- restore_trail, restore_trail_after   (the nested transaction restores the parent's trail)
#   TB9-site-reset-abolish    <- ab_destroy and the white-box testset `abolish_table forgets the trail's answers`
# Three units run the same 16 cases: an incremental table (`NI`), a monotonic one (`NM`), a monotonic lazy one (`NL`).
#   * A case `t_<id>(R)` is wrapped by `tt_q/2`: it runs, the unit's cleanup runs, and the answer is written with
#     `format(atom(A), "~q", [R])` IN PROLOG, so a pin is swipl's text. A failed transaction binds nothing: a case reads what
#     happened inside through `tt_note/1` and `nb_getval/2`.
#   * `cf_constraint` / `nr_constraint` make the transaction fail through `transaction(Goal, fail, tn_m)` (a constraint that
#     fails); `cf_bulk_announce` uses a listener on d/1 that raises from its second event (`prolog_listen(d/1, tn_ev)`) under
#     `transaction(Goal, [bulk(true)])`: the bulk announce fails and the transaction is discarded. There is NO nested row of the
#     bulk announce failure: the kernel's DIVERGES comment at pl-transaction.jl names why.
#   * `ab_abolish*` abolish with `abolish_all_tables` (the bulk reset, `reset_table_bulk`); `ab_destroy*` abolish one table with
#     `'$tbl_destroy_table'/1` (`tn_destroy/1`, the route of `abolish_table_subgoals`, the `abolish_table` of pl-tabling.c).
#   * A QUIRK pinned as it is: `ab_abolish_reeval` on the monotonic NON-lazy unit answers [1,2] after the rollback (the other two
#     units answer [1]); swipl's table keeps the answer that was re-evaluated inside the transaction that was rolled back. The pin is swipl's.
#   * UNVERIFIED on the kernel (nothing was compiled when these rows were written): every kernel answer; the gate decides.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — these built-ins ride the term layer through the FLI (unify, get, the trie blobs)
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TN = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_tns(x) = lk_sym(_TN, Symbol(x))

"The helpers every unit's program starts with."
const _TN_COMMON = raw"""
tt_q(G, A) :- ( catch(call(G, R), E, R = exc(E)) -> true ; R = failed ), tt_clean, format(atom(A), "~q", [R]).
tt_ex(G, L) :- findall(X, call(G, X), L0), sort(L0, L).
tt_inv(G, Y) :- ( '$tbl_variant_table'(0, user:G, T, _, _, _), '$idg_falsecount'(T, C), C > 0 -> Y = invalid ; Y = valid ).
tt_yn(G, Y) :- ( call(G) -> Y = yes ; Y = no ).
tt_note(X) :- nb_setval(tt_in, X).
:- nb_setval(tt_in, none).
% a listener on d/1 that raises from its At-th event on, only while tn_gon is on (an announce that fails at the bulk commit)
:- nb_setval(tn_gon, off), nb_setval(tn_gn, 0), nb_setval(tn_gat, 1).
tn_ev(A, _) :-
    functor(A, F, _),
    (   ( F == rollback ; nb_getval(tn_gon, off) ) -> true
    ;   nb_getval(tn_gn, N0), N is N0 + 1, nb_setval(tn_gn, N), nb_getval(tn_gat, At),
        ( N >= At -> throw(tn_boom(N)) ; true )
    ).
tn_gclean(At) :- nb_setval(tn_gon, off), nb_setval(tn_gn, 0), nb_setval(tn_gat, At), nb_setval(tn_gon, on).
tn_goff :- nb_setval(tn_gon, off).
% abolish_table of one variant: the Prolog route of abolish_table_subgoals ('$tbl_destroy_table'/1)
tn_destroy(G) :- '$tbl_variant_table'(0, user:G, T, _, _, _), '$tbl_destroy_table'(T).
"""

"The program of a unit: the helpers, the unit's clauses, the cases."
_tn_text(u) = _TN_COMMON * u.program * join(["t_$(id)(R) :- $body.\n" for (id, body) in _TN_CASES])

"The `~q` text of each case's answer, in order, from swipl at the pin."
function _tn_swipl_lines(u)::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "tn.pl")
        write(
            f,
            _tn_text(u) * ":- initialization((forall(member(G, [" * join(["t_$id" for (id, _) in _TN_CASES], ",") *
            "]), (tt_q(G, A), write(A), nl)), halt)).\n"
        )
        read(pipeline(addenv(`swipl -q $f`, "LC_ALL" => "C"); stdin=devnull, stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

"The `~q` text of the answer of `case`, run as `tt_q(case, A)` in the kernel."
function _tn_ask(gd, ld, case::String)::String
    proc = LK.isCurrentProcedure(sym_key(_tns("tt_q")), 2, LK.MODULE_user(gd))
    (proc === nothing || !LK.isDefinedProcedure(gd, proc)) && return "tt_q undefined"
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 2)
    LK.putSlotValue!(ld, a + 1, _tns(case), LK.PutVarMap())
    LK.putSlotValue!(ld, a + 2, mk_var(_TN, LK.fresh_var_keys!(1)), LK.PutVarMap())
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

"Run the goal `tn_run(case)` for its effect in the kernel (`case` an atom; no cleanup runs): did it succeed?"
function _tn_do(gd, ld, case::String)::Bool
    proc = LK.isCurrentProcedure(sym_key(_tns("tn_run")), 1, LK.MODULE_user(gd))
    (proc === nothing || !LK.isDefinedProcedure(gd, proc)) && return false
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 1)
    LK.putSlotValue!(ld, a + 1, _tns(case), LK.PutVarMap())
    qid = LK.PL_open_query(gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a)
    rc = LK.PL_next_solution(gd, ld, qid)
    ok = rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
    LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
    return ok
end

"A kernel with the unit's program consulted: `(gd, ld, load status)`."
function _tn_load(u)
    f = joinpath(mktempdir(), "tabling_transaction_nested.pl")
    write(f, _tn_text(u))
    gd = LK.PL_global_data{_TN}()
    ld = LK.PL_local_data{_TN}(gd)
    st, _ = LK.load_file!(gd, ld, f)
    return gd, ld, st
end

"The indices where two answer lists differ (a missing answer counts as a difference)."
_tn_diff(lines::Vector{String}, pins::Vector{String}) =
    [i for i in 1:max(length(lines), length(pins)) if i > length(lines) || i > length(pins) || lines[i] != pins[i]]

"The must-fail corruptions of a comparison: a corrupted pin, an extra pin, a dropped pin and a corrupted kill row are each flagged."
function _tn_flagged(lines::Vector{String}, pins::Vector{String}, kill::Vector{Int})::Bool
    base = _tn_diff(lines, pins)
    corrupt = copy(pins)
    corrupt[1] = corrupt[1] * "x"
    ok = _tn_diff(lines, corrupt) == sort(union(base, [1]))
    ok &= _tn_diff(lines, vcat(pins, "extra")) == sort(union(base, [length(pins) + 1]))
    ok &= _tn_diff(lines, pins[1:(end - 1)]) == sort(union(base, [length(pins)]))
    for k in kill
        c = copy(pins)
        c[k] = "wrong"
        ok &= _tn_diff(lines, c) == sort(union(base, [k]))
    end
    return ok
end

# ── the sixteen cases, shared by the three units; each pin below is swipl's `~q` text of that case ──────────────────────────
const _TN_CASES = [
    ("nm_commit", raw"assertz(d(1)), tt_ex(p, A), transaction((assertz(d(3)), tt_ex(p, B), transaction((assertz(d(2)), tt_ex(p, C))), tt_ex(p, D))), tt_inv(p(_), V), tt_ex(p, E), R = r(A, B, C, D, V, E)"),   # control: both levels commit, the outer answers its own and the inner changes
    ("nm_merge", raw"assertz(d(1)), tt_ex(p, A), tt_yn(transaction((assertz(d(3)), tt_ex(p, _), transaction((assertz(d(2)), tt_ex(p, C), tt_note(C))), fail)), Y), nb_getval(tt_in, C1), tt_inv(p(_), V), tt_ex(p, E), R = r(A, C1, Y, V, E)"),   # TB9-hook-nested-merge: the outer owns a trail, the inner commits and hands its trail up
    ("nm_merge_fresh", raw"assertz(d(1)), tt_ex(p, A), tt_yn(transaction((transaction((assertz(d(2)), tt_ex(p, B), tt_note(B))), fail)), Y), nb_getval(tt_in, B1), tt_inv(p(_), V), tt_ex(p, E), R = r(A, B1, Y, V, E)"),   # TB9-hook-nested-merge: the outer owns no trail, the inner commits and hands its trail up
    ("nr_snapshot", raw"assertz(d(1)), tt_ex(p, A), transaction((snapshot((assertz(d(2)), tt_ex(p, B))), tt_inv(p(_), V0), tt_ex(p, C))), tt_inv(p(_), V1), tt_ex(p, D), R = r(A, B, V0, C, V1, D)"),   # TB9-hook-nested-rollback: a discarded snapshot rolls its tables back inside the outer transaction
    ("nr_failed", raw"assertz(d(1)), tt_ex(p, A), transaction((assertz(d(3)), tt_ex(p, B), tt_yn(transaction((assertz(d(2)), tt_ex(p, C), tt_note(C), fail)), Y), nb_getval(tt_in, C1), tt_inv(p(_), V0), tt_ex(p, D))), tt_inv(p(_), V1), tt_ex(p, E), R = r(A, B, C1, Y, V0, D, V1, E)"),   # TB9-hook-nested-rollback: a failed inner transaction inside an outer one
    ("nr_constraint", raw"assertz(d(1)), tt_ex(p, A), transaction((assertz(d(3)), tt_ex(p, B), tt_yn(transaction((assertz(d(2)), tt_ex(p, C), tt_note(C)), fail, tn_m), Y), nb_getval(tt_in, C1), tt_inv(p(_), V0), tt_ex(p, D))), tt_inv(p(_), V1), tt_ex(p, E), R = r(A, B, C1, Y, V0, D, V1, E)"),   # TB9-hook-nested-rollback: an inner transaction whose constraint fails
    ("restore_trail", raw"assertz(d(1)), tt_ex(p, A), tt_yn(transaction((assertz(d(2)), tt_ex(p, B), tt_note(B), transaction(true), fail)), Y), nb_getval(tt_in, B1), tt_inv(p(_), V), tt_ex(p, E), R = r(A, B1, Y, V, E)"),   # TB9-hook-restore: a committed empty inner transaction, then the outer fails
    ("restore_trail_after", raw"assertz(d(1)), tt_ex(p, A), tt_yn(transaction((assertz(d(2)), tt_ex(p, B), tt_note(B), transaction(true), assertz(d(3)), tt_ex(p, _), fail)), Y), nb_getval(tt_in, B1), tt_inv(p(_), V), tt_ex(p, E), R = r(A, B1, Y, V, E)"),   # TB9-hook-restore: as restore_trail with a change after the inner transaction
    ("cf_constraint", raw"assertz(d(1)), tt_ex(p, A), tt_yn(transaction((assertz(d(2)), tt_ex(p, B), tt_note(B)), fail, tn_m), Y), nb_getval(tt_in, B1), tt_inv(p(_), V), tt_ex(p, E), R = r(A, B1, Y, V, E)"),   # TB9-hook-rollback-fail: the outermost constraint fails
    ("cf_bulk_announce", raw"assertz(d(1)), tt_ex(p, A), tn_gclean(2), catch(transaction(user:(assertz(d(2)), tt_ex(p, B), tt_note(B)), [bulk(true)]), Ex, true), tn_goff, nb_getval(tt_in, B1), nb_getval(tn_gn, N), tt_inv(p(_), V), tt_ex(p, E), R = r(A, B1, Ex, N, V, E)"),   # TB9-hook-rollback-fail: the outermost bulk announce fails (a listener raises from its 2nd event)
    ("cf_bulk_ok", raw"assertz(d(1)), tt_ex(p, A), tn_gclean(9), transaction(user:(assertz(d(2)), tt_ex(p, B), tt_note(B)), [bulk(true)]), tn_goff, tt_inv(p(_), V), tt_ex(p, E), R = r(A, B, V, E)"),   # control: the bulk announce passes (the lazy table stays invalid: pinned)
    ("ab_abolish", raw"assertz(d(1)), tt_ex(p, A), tt_yn(transaction((assertz(d(2)), tt_ex(p, B), tt_note(B), abolish_all_tables, fail)), Y), nb_getval(tt_in, B1), tt_ex(p, E), R = r(A, B1, Y, E)"),   # abolish_all_tables (reset_table_bulk) inside a transaction that fails
    ("ab_abolish_reeval", raw"assertz(d(1)), tt_ex(p, A), tt_yn(transaction((assertz(d(2)), tt_ex(p, _), abolish_all_tables, tt_ex(p, C), tt_note(C), fail)), Y), nb_getval(tt_in, C1), tt_ex(p, E), R = r(A, C1, Y, E)"),   # abolish_all_tables then a re-evaluation inside a transaction that fails; QUIRK: the NM unit answers [1,2]
    ("ab_abolish_commit", raw"assertz(d(1)), tt_ex(p, A), transaction((assertz(d(2)), tt_ex(p, B), abolish_all_tables)), tt_ex(p, E), R = r(A, B, E)"),   # abolish_all_tables inside a transaction that commits
    ("ab_destroy", raw"assertz(d(1)), tt_ex(p, A), tt_yn(transaction((assertz(d(2)), tt_ex(p, B), tt_note(B), tn_destroy(p(_)), fail)), Y), nb_getval(tt_in, B1), tt_ex(p, E), R = r(A, B1, Y, E)"),   # TB9-site-reset-abolish (Prolog route): abolish one table inside a transaction that fails
    ("ab_destroy_commit", raw"assertz(d(1)), tt_ex(p, A), transaction((assertz(d(2)), tt_ex(p, B), tn_destroy(p(_)))), tt_ex(p, E), R = r(A, B, E)"),   # abolish one table inside a transaction that commits
]

# the incremental table unit
const _TN_INCR = (
    unit = "nested_incr",
    program = raw"""
:- dynamic d/1 as incremental.
:- table p/1 as (incremental).
:- prolog_listen(d/1, tn_ev).
p(X) :- d(X).
tt_clean :- nb_setval(tn_gon, off), abolish_all_tables, retractall(d(_)).
""",
    # swipl 10.1.20, `tt_q(t_<case>, A)` in the order of `_TN_CASES`, two identical runs
    pinned = [
        "r([1],[1,3],[1,2,3],[1,2,3],valid,[1,2,3])",   # nm_commit
        "r([1],[1,2,3],no,invalid,[1])",   # nm_merge
        "r([1],[1,2],no,invalid,[1])",   # nm_merge_fresh
        "r([1],[1,2],invalid,[1],valid,[1])",   # nr_snapshot
        "r([1],[1,3],[1,2,3],no,invalid,[1,3],valid,[1,3])",   # nr_failed
        "r([1],[1,3],[1,2,3],no,invalid,[1,3],valid,[1,3])",   # nr_constraint
        "r([1],[1,2],no,invalid,[1])",   # restore_trail
        "r([1],[1,2],no,invalid,[1])",   # restore_trail_after
        "r([1],[1,2],no,invalid,[1])",   # cf_constraint
        "r([1],[1,2],tn_boom(2),2,invalid,[1])",   # cf_bulk_announce
        "r([1],[1,2],invalid,[1,2])",   # cf_bulk_ok
        "r([1],[1,2],no,[1])",   # ab_abolish
        "r([1],[1,2],no,[1])",   # ab_abolish_reeval
        "r([1],[1,2],[1,2])",   # ab_abolish_commit
        "r([1],[1,2],no,[1])",   # ab_destroy
        "r([1],[1,2],[1,2])",   # ab_destroy_commit
    ],
)

# the monotonic table unit
const _TN_MONO = (
    unit = "nested_mono",
    program = raw"""
:- dynamic d/1 as monotonic.
:- table p/1 as (monotonic).
:- prolog_listen(d/1, tn_ev).
p(X) :- d(X).
tt_clean :- nb_setval(tn_gon, off), abolish_all_tables, retractall(d(_)).
""",
    # swipl 10.1.20, `tt_q(t_<case>, A)` in the order of `_TN_CASES`, two identical runs
    pinned = [
        "r([1],[1,3],[1,2,3],[1,2,3],valid,[1,2,3])",   # nm_commit
        "r([1],[1,2,3],no,valid,[1])",   # nm_merge
        "r([1],[1,2],no,valid,[1])",   # nm_merge_fresh
        "r([1],[1,2],valid,[1],valid,[1])",   # nr_snapshot
        "r([1],[1,3],[1,2,3],no,valid,[1,3],valid,[1,3])",   # nr_failed
        "r([1],[1,3],[1,2,3],no,valid,[1,3],valid,[1,3])",   # nr_constraint
        "r([1],[1,2],no,valid,[1])",   # restore_trail
        "r([1],[1,2],no,valid,[1])",   # restore_trail_after
        "r([1],[1,2],no,valid,[1])",   # cf_constraint
        "r([1],[1,2],tn_boom(2),2,valid,[1])",   # cf_bulk_announce
        "r([1],[1,2],valid,[1,2])",   # cf_bulk_ok
        "r([1],[1,2],no,[1])",   # ab_abolish
        "r([1],[1,2],no,[1,2])",   # ab_abolish_reeval
        "r([1],[1,2],[1,2])",   # ab_abolish_commit
        "r([1],[1,2],no,[1])",   # ab_destroy
        "r([1],[1,2],[1,2])",   # ab_destroy_commit
    ],
)

# the monotonic lazy table unit
const _TN_LAZY = (
    unit = "nested_mono_lazy",
    program = raw"""
:- dynamic d/1 as monotonic.
:- table p/1 as (monotonic,lazy).
:- prolog_listen(d/1, tn_ev).
p(X) :- d(X).
tt_clean :- nb_setval(tn_gon, off), abolish_all_tables, retractall(d(_)).
""",
    # swipl 10.1.20, `tt_q(t_<case>, A)` in the order of `_TN_CASES`, two identical runs
    pinned = [
        "r([1],[1,3],[1,2,3],[1,2,3],valid,[1,2,3])",   # nm_commit
        "r([1],[1,2,3],no,valid,[1])",   # nm_merge
        "r([1],[1,2],no,valid,[1])",   # nm_merge_fresh
        "r([1],[1,2],valid,[1],valid,[1])",   # nr_snapshot
        "r([1],[1,3],[1,2,3],no,valid,[1,3],valid,[1,3])",   # nr_failed
        "r([1],[1,3],[1,2,3],no,valid,[1,3],valid,[1,3])",   # nr_constraint
        "r([1],[1,2],no,valid,[1])",   # restore_trail
        "r([1],[1,2],no,valid,[1])",   # restore_trail_after
        "r([1],[1,2],no,valid,[1])",   # cf_constraint
        "r([1],[1,2],tn_boom(2),2,valid,[1])",   # cf_bulk_announce
        "r([1],[1,2],invalid,[1,2])",   # cf_bulk_ok
        "r([1],[1,2],no,[1])",   # ab_abolish
        "r([1],[1,2],no,[1])",   # ab_abolish_reeval
        "r([1],[1,2],[1,2])",   # ab_abolish_commit
        "r([1],[1,2],no,[1])",   # ab_destroy
        "r([1],[1,2],[1,2])",   # ab_destroy_commit
    ],
)

"The case ids whose rows kill a TB9 mutant (see the header): the rows a wrong answer must flag."
const _TN_KILL = [
    "nm_merge", "nm_merge_fresh", "nr_snapshot", "nr_failed", "nr_constraint", "restore_trail", "restore_trail_after",
    "cf_constraint", "cf_bulk_announce", "ab_destroy",
]
const _TN_KILL_IDX = [findfirst(==(k), [id for (id, _) in _TN_CASES])::Int for k in _TN_KILL]

"The kernel's answers of the unit, by unit name (filled by `_tn_check_unit`, read by the cross-unit testset)."
const _TN_LINES = Dict{String, Vector{String}}()

"The three testsets of one unit (every one runs >= 1 assertion with or without `swipl`, and each proves its comparison can fail)."
function _tn_check_unit(u)
    @testset "$(u.unit)" begin
        ids = [id for (id, _) in _TN_CASES]
        gd, ld, st = _tn_load(u)
        lines = String[_tn_ask(gd, ld, "t_$id") for id in ids]
        _TN_LINES[u.unit] = lines
        @testset "$(u.unit): the nested, constraint-failure and abolish cases run as swipl's pins" begin
            @test st === :ok
            @test !isempty(lines) && !isempty(u.pinned) && length(lines) == length(u.pinned) == length(ids)
            for (id, k, p) in zip(ids, lines, u.pinned)
                k == p || println(stderr, "  ours  ", id, " ", k, "\n  swipl ", p)
                @test k == p
            end
            @test _tn_flagged(lines, u.pinned, _TN_KILL_IDX)        # a corrupted pin is flagged, kill rows included
        end
        @testset "$(u.unit): the pins are well formed; the comparison can fail" begin
            @test allunique(ids)
            @test length(u.pinned) == length(ids)
            @test length(unique(u.pinned)) >= 8                      # not one row repeated
            @test all(startswith("r("), u.pinned)
            @test _tn_flagged(u.pinned, u.pinned, _TN_KILL_IDX)      # the pins compared with themselves: each corruption flagged
            @test _tn_diff(u.pinned, reverse(u.pinned)) != Int[]     # a reordered list is flagged
        end
        @testset "$(u.unit): the pins are swipl's (live, when swipl is on PATH)" begin
            if Sys.which("swipl") === nothing || get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1"
                @info "TB9 NESTED LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
                @test length(u.pinned) == length(ids)
                @test _tn_flagged(u.pinned, u.pinned, _TN_KILL_IDX)
            else
                live = _tn_swipl_lines(u)
                @test live == u.pinned
                @test _tn_flagged(live, u.pinned, _TN_KILL_IDX)
            end
        end
    end
    return nothing
end

_tn_check_unit(_TN_INCR)
_tn_check_unit(_TN_MONO)
_tn_check_unit(_TN_LAZY)

# ── across the units: the rollback rows tell an incremental table from a monotonic one ───────────────────────────────────────
# An incremental table that a rolled-back change touched is INVALID afterwards; a monotonic one is not (its answer is taken back).
# A kernel that never rolls a table back answers the same on all three units, so these rows read the kernel's own lines.
@testset "nested transactions over tables: the three units differ where swipl's do" begin
    ni, nm, nl = _TN_LINES["nested_incr"], _TN_LINES["nested_mono"], _TN_LINES["nested_mono_lazy"]
    @test !isempty(ni) && length(ni) == length(nm) == length(nl)
    ids = [id for (id, _) in _TN_CASES]
    for k in ("nm_merge", "nm_merge_fresh", "nr_snapshot", "nr_failed", "nr_constraint", "restore_trail", "restore_trail_after",
              "cf_constraint", "cf_bulk_announce")
        i = findfirst(==(k), ids)::Int
        @test occursin("invalid", ni[i])                         # the incremental table is invalid after the rollback
        @test !occursin("invalid", nm[i]) && !occursin("invalid", nl[i])
        @test ni[i] != nm[i]
        @test nm[i] == nl[i]
    end
    i = findfirst(==("cf_bulk_ok"), ids)::Int
    @test nm[i] != nl[i]                                         # the lazy table is invalid after a bulk commit, the eager one is not
    for k in ("ab_abolish", "ab_destroy")                        # abolishing inside a failing transaction: the same answer on all three
        i = findfirst(==(k), ids)::Int
        @test ni[i] == nm[i] == nl[i]
    end
end

# ── abolish_table forgets the trail's answers (pl-tabling.c abolish_table -> reset_answer_table, the tracked branch) ─────────
# `'$tbl_destroy_table'/1` on a table that holds a trail action must clear the action and the table's TRIE_ISTRACKED flag. No
# Prolog goal shows it (the action is read only at the rollback): the answer is added to the trail by hand on a real table.
"Run the white-box once: the observed lines (`name=value`), one extractor for the testset and its corruptions."
function _tn_abolish_obs()::Vector{String}
    f = joinpath(mktempdir(), "tabling_transaction_nested_wb.pl")
    write(
        f,
        _TN_COMMON * _TN_MONO * "tn_run(G) :- call(G).\ntn_setup :- assertz(d(1)), assertz(d(2)), forall(p(_), true).\n" *
        "tn_destroy_p :- tn_destroy(p(_)).\n"
    )
    gd = LK.PL_global_data{_TN}()
    ld = LK.PL_local_data{_TN}(gd)
    st, _ = LK.load_file!(gd, ld, f)
    tracked(t) = (t.flags & LK.TRIE_ISTRACKED) != 0
    obs = String["load=$(st === :ok)"]
    push!(obs, "setup=$(_tn_do(gd, ld, "tn_setup"))")
    cand = [t for t in gd.tries if t.IDG !== nothing && t.variant != 0 && !LK._wl_is(t, LK.WL_DYNAMIC)]
    push!(obs, "tables=$(length(cand))")
    if length(cand) == 1
        at = cand[1]
        live = [i for i in 2:length(at.nodes) if at.nodes[i].value != 0 && (at.nodes[i].flags & LK.TN_PRIMARY) != 0]
        push!(obs, "live=$(length(live))")
        if !isempty(live)
            tr = ld.transaction
            try
                tr.generation = LK.gen_t(5)
                LK.tt_add_answer(ld, at, live[1])
                tt = tr.table_trail
                push!(obs, "added=$(tt === nothing ? -1 : length(tt.actions))|$(tracked(at))")
                push!(obs, "destroy=$(_tn_do(gd, ld, "tn_destroy_p"))")
                if tt !== nothing && !isempty(tt.actions)
                    act = tt.actions[1]
                    push!(obs, "cleared=$(act.atrie)|$(act.answer)|$(tracked(at))")
                end
            finally
                tr.generation = LK.gen_t(0)
                tr.table_trail = nothing
            end
        end
    end
    return obs
end

@testset "abolish_table forgets the trail's answers: the action and TRIE_ISTRACKED are cleared (kills TB9-site-reset-abolish)" begin
    obs = _tn_abolish_obs()
    pin = ["load=true", "setup=true", "tables=1", "live=2", "added=1|true", "destroy=true", "cleared=0|0|false"]
    @test !isempty(obs) && !isempty(pin) && length(obs) == length(pin)
    for (i, (o, p)) in enumerate(zip(obs, pin))
        o == p || println(stderr, "  ours  ", i, " ", o, "\n  pin   ", i, " ", p)
        @test o == p
    end
    @test _tn_flagged(obs, pin, [length(pin)])                  # the cleared-action row is the one the mutant changes
end
