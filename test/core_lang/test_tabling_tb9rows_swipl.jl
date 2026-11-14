# ORIGINAL: LIVE rows of the transaction tables (TAB1 TB9-ROWS) pinned on swipl at 18168e62 (10.1.20), for TB9 mutants whose only kill row
# was a white-box one (a state built by hand, the expected value read off pl-tabling.c / pl-transaction.c): a Prolog route exists for two
# groups, and each row below is swipl's own answer. tools/mutants/TB9.py names each kill by group and case.
#   * ABOLISH-TWO  two monotonic tables over one dynamic predicate, a transaction adds an answer to BOTH and abolishes ONE of them
#                  (`'$tbl_destroy_table'/1`, the route of `abolish_table_subgoals`), then fails: the table that was NOT abolished must have
#                  its answer taken back. Kills TB9-abolish-trie (`tt_abolish_table` clears the actions of every table: the other table keeps
#                  the answer, `[1,2]` for `[1]`). Cases ab2_destroy_p and ab2_destroy_q (either table is the abolished one; the control
#                  ab2_none abolishes nothing and ab2_destroy_both abolishes both: the same answer, a row that proves the cases are comparable).
#                  Two units: a monotonic table (`NM`) and a monotonic lazy one (`NL`).
#   * TRIE-UPDATES a compiled trie (trie_gen_compiled/2: no value; /3: with a value) destroyed inside a transaction erases its compiled
#                  clause; `transaction_updates/1` must not list that erase (pl-transaction.c is_trie_clause). Kills TB9-trieclause-3
#                  (tc3: `r(1,0)`, the mutant lists the erase: `r(1,1)`), TB9-trieclause-2 (tc2) and, with the control rows, TB9-trieclause-any
#                  (tc_ctl: the erase of a user clause IS listed, `[erased]`; the mutant hides it, `[]`; tc_both: both trie clauses hidden,
#                  the user clause listed). The first field of tc3, tc2 and tc_both is the clause count of the predicate BEFORE the transaction
#                  (`predicate_property(system:trie_gen_compiled(...), number_of_clauses(N))`): 1, so the row is not empty of the clause it hides.
# MUTANTS WITH NO ROW HERE (no Prolog route; the white-box rows of test_tabling_transaction_wb_swipl.jl stay their kill rows):
#   TB9-status-force, TB9-status-falsecount: a lazy monotonic table is checked for an invalid or forced dependent table only at
#     `'$mono_reeval_prepare'`, and the dependent table is re-evaluated BEFORE it (swipl at the pin answers `valid` for the table with an
#     invalid dependency, so the branch is not visible); the variants that force the dependent table inside a nested snapshot make swipl
#     at the pin stop on an internal check (private register; no row can run them).
#   TB9-lg-erased: a clause of a monotonic dynamic predicate is erased only by `retract`, which invalidates the table in the same step:
#     `invalid` with or without the mutation (probed on swipl, rows er1..er8 of evidence/TAB1/tb9rows_handoff.md).
#   TB9-lg-atmax, TB9-lg-belowbase (a clause created AT a generation bound), TB9-abolish-answer (the `answer` field of an entry that
#     `tt_abolish_table` cleared is never read), TB9-merge-order, TB9-resettracked-flag, TB9-hasmod-dynamic, TB9-monostatus-init: state only.
#   TB9-hasmod-break and TB9-abolish-serial stay EQUIVALENT (their reasons are in the list).
# NOT UPSTREAM CASES: no upstream test abolishes a table inside a transaction over two tables, or reads `transaction_updates/1` after
# destroying a trie. Each pin is swipl's answer (two identical runs, listed in evidence/TAB1/tb9rows_handoff.md), compared with the kernel's
# and, with `swipl` on PATH, with a live run.
# ROWS THE KERNEL CANNOT ANSWER YET: none known; UNVERIFIED on the kernel (nothing was compiled when these rows were written): every
# kernel answer; the gate decides. A row that fails there is turned into `@test_broken <the same comparison>` with an owner, never skipped.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — these built-ins ride the term layer through the FLI (unify, get, the trie blobs)
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _T9_T = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_t9s(x) = lk_sym(_T9_T, Symbol(x))

"The helpers every unit's program starts with."
const _T9_COMMON = raw"""
tt_q(G, A) :- ( catch(call(G, R), E, R = exc(E)) -> true ; R = failed ), tt_clean, format(atom(A), "~q", [R]).
tt_ex(G, L) :- findall(X, call(G, X), L0), sort(L0, L).
tt_yn(G, Y) :- ( call(G) -> Y = yes ; Y = no ).
tt_note(X) :- nb_setval(tt_in, X).
:- nb_setval(tt_in, none).
% abolish one table of a variant: the Prolog route of abolish_table_subgoals ('$tbl_destroy_table'/1)
tn_destroy(G) :- '$tbl_variant_table'(0, user:G, T, _, _, _), '$tbl_destroy_table'(T).
"""

"The program of a unit: the helpers, the unit's clauses, the cases."
_t9_text(u) =
    _T9_COMMON * u.program * join(["t_$(id)(R) :- $body.\n" for (id, body) in u.cases])

"The `~q` text of each case's answer, in order, from swipl at the pin."
function _t9_swipl_lines(u)::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "t9.pl")
        write(
            f,
            _t9_text(u) * ":- initialization((forall(member(G, [" *
            join(["t_$id" for (id, _) in u.cases], ",") *
            "]), (tt_q(G, A), write(A), nl)), halt)).\n"
        )
        read(
            pipeline(addenv(`swipl -q $f`, "LC_ALL" => "C"); stdin=devnull, stderr=devnull),
            String
        )
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

"The `~q` text of the answer of `case`, run as `tt_q(case, A)` in the kernel."
function _t9_ask(gd, ld, case::String)::String
    proc = LK.isCurrentProcedure(sym_key(_t9s("tt_q")), 2, LK.MODULE_user(gd))
    (proc === nothing || !LK.isDefinedProcedure(gd, proc)) && return "tt_q undefined"
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 2)
    LK.putSlotValue!(ld, a + 1, _t9s(case), LK.PutVarMap())
    LK.putSlotValue!(ld, a + 2, mk_var(_T9_T, LK.fresh_var_keys!(1)), LK.PutVarMap())
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

"A kernel with the unit's program consulted: `(gd, ld, load status)`."
function _t9_load(u)
    f = joinpath(mktempdir(), "tabling_tb9rows.pl")
    write(f, _t9_text(u))
    gd = LK.PL_global_data{_T9_T}()
    ld = LK.PL_local_data{_T9_T}(gd)
    st, _ = LK.load_file!(gd, ld, f)
    return gd, ld, st
end

"The indices where two answer lists differ (a missing answer counts as a difference)."
_t9_diff(lines::Vector{String}, pins::Vector{String}) =
    [
        i for i in 1:max(length(lines), length(pins)) if
        i > length(lines) || i > length(pins) || lines[i] != pins[i]
    ]

"The must-fail corruptions of a comparison: a corrupted pin, an extra pin, a dropped pin and a corrupted kill row are each flagged."
function _t9_flagged(lines::Vector{String}, pins::Vector{String}, kill::Vector{Int})::Bool
    base = _t9_diff(lines, pins)
    corrupt = copy(pins)
    corrupt[1] = corrupt[1] * "x"
    ok = _t9_diff(lines, corrupt) == sort(union(base, [1]))
    ok &= _t9_diff(lines, vcat(pins, "extra")) == sort(union(base, [length(pins) + 1]))
    ok &= _t9_diff(lines, pins[1:(end - 1)]) == sort(union(base, [length(pins)]))
    for k in kill
        c = copy(pins)
        c[k] = "wrong"
        ok &= _t9_diff(lines, c) == sort(union(base, [k]))
    end
    return ok
end

# ── ABOLISH-TWO: the cases shared by the two table units ────────────────────────────────────────────────────────────────────
# `r(A, Q0, Noted, Y, Q2, E)`: A the answers of p and Q0 of q before; Noted `PIn-QIn`, what p and q answered INSIDE the transaction;
# Y whether the transaction succeeded; Q2 the answers of q after the rollback; E those of p.
const _T9_AB2_CASES = [
    (
        "ab2_destroy_p",
        raw"assertz(d(1)), tt_ex(p, A), tt_ex(q, Q0), tt_yn(transaction((assertz(d(2)), tt_ex(p, B), tt_ex(q, Q1), tt_note(B-Q1), tn_destroy(p(_)), fail)), Y), nb_getval(tt_in, N), tt_ex(q, Q2), tt_ex(p, E), R = r(A, Q0, N, Y, Q2, E)"
    ),   # TB9-abolish-trie: p is abolished, q (not abolished) takes its answer back
    (
        "ab2_destroy_q",
        raw"assertz(d(1)), tt_ex(p, A), tt_ex(q, Q0), tt_yn(transaction((assertz(d(2)), tt_ex(p, B), tt_ex(q, Q1), tt_note(B-Q1), tn_destroy(q(_)), fail)), Y), nb_getval(tt_in, N), tt_ex(q, Q2), tt_ex(p, E), R = r(A, Q0, N, Y, Q2, E)"
    ),   # TB9-abolish-trie: q is abolished (the second table of the trail), p takes its answer back
    (
        "ab2_destroy_both",
        raw"assertz(d(1)), tt_ex(p, A), tt_ex(q, Q0), tt_yn(transaction((assertz(d(2)), tt_ex(p, B), tt_ex(q, Q1), tt_note(B-Q1), tn_destroy(p(_)), tn_destroy(q(_)), fail)), Y), nb_getval(tt_in, N), tt_ex(q, Q2), tt_ex(p, E), R = r(A, Q0, N, Y, Q2, E)"
    ),   # control: both abolished, nothing is left to take back
    (
        "ab2_none",
        raw"assertz(d(1)), tt_ex(p, A), tt_ex(q, Q0), tt_yn(transaction((assertz(d(2)), tt_ex(p, B), tt_ex(q, Q1), tt_note(B-Q1), fail)), Y), nb_getval(tt_in, N), tt_ex(q, Q2), tt_ex(p, E), R = r(A, Q0, N, Y, Q2, E)"
    )   # control: nothing abolished, both take their answer back
]

# the monotonic table unit
const _T9_NM = (
    unit="tb9rows_mono",
    program=raw"""
:- dynamic d/1 as monotonic.
:- table p/1 as (monotonic).
:- table q/1 as (monotonic).
p(X) :- d(X).
q(X) :- d(X).
tt_clean :- abolish_all_tables, retractall(d(_)).
""",
    cases=_T9_AB2_CASES,
    kill=["ab2_destroy_p", "ab2_destroy_q"],
    # swipl 10.1.20, `tt_q(t_<case>, A)` in order, two identical runs
    pinned=[
        "r([1],[1],[1,2]-[1,2],no,[1],[1])",   # ab2_destroy_p
        "r([1],[1],[1,2]-[1,2],no,[1],[1])",   # ab2_destroy_q
        "r([1],[1],[1,2]-[1,2],no,[1],[1])",   # ab2_destroy_both
        "r([1],[1],[1,2]-[1,2],no,[1],[1])"   # ab2_none
    ]
)

# the monotonic lazy table unit
const _T9_NL = (
    unit="tb9rows_mono_lazy",
    program=raw"""
:- dynamic d/1 as monotonic.
:- table p/1 as (monotonic,lazy).
:- table q/1 as (monotonic,lazy).
p(X) :- d(X).
q(X) :- d(X).
tt_clean :- abolish_all_tables, retractall(d(_)).
""",
    cases=_T9_AB2_CASES,
    kill=["ab2_destroy_p", "ab2_destroy_q"],
    # swipl 10.1.20, `tt_q(t_<case>, A)` in order, two identical runs
    pinned=[
        "r([1],[1],[1,2]-[1,2],no,[1],[1])",   # ab2_destroy_p
        "r([1],[1],[1,2]-[1,2],no,[1],[1])",   # ab2_destroy_q
        "r([1],[1],[1,2]-[1,2],no,[1],[1])",   # ab2_destroy_both
        "r([1],[1],[1,2]-[1,2],no,[1],[1])"   # ab2_none
    ]
)

# ── TRIE-UPDATES ────────────────────────────────────────────────────────────────────────────────────────────────────────────
# tc3 / tc2: `r(ClausesBefore, UpdatesListed)`; tc_ctl: the kinds of the updates; tc_both: `r(Clauses3, Clauses2, Kinds)`.
const _T9_TRIE_CASES = [
    (
        "tc3",
        raw"trie_new(T), trie_insert(T, f(1), v1), trie_insert(T, f(2), v2), forall(trie_gen_compiled(T, _, _), true), tc_nc(trie_gen_compiled(_, _, _), C0), transaction((trie_destroy(T), transaction_updates(U), length(U, N))), R = r(C0, N)"
    ),   # TB9-trieclause-3: the erase of a trie_gen_compiled/3 clause is not an update
    (
        "tc2",
        raw"trie_new(T), trie_insert(T, g(1)), trie_insert(T, g(2)), forall(trie_gen_compiled(T, _), true), tc_nc(trie_gen_compiled(_, _), C0), transaction((trie_destroy(T), transaction_updates(U), length(U, N))), R = r(C0, N)"
    ),   # TB9-trieclause-2: the erase of a trie_gen_compiled/2 clause is not an update
    (
        "tc_ctl",
        raw"assertz(d(1)), transaction((retract(d(1)), transaction_updates(U), tc_kinds(U, K))), R = K"
    ),   # TB9-trieclause-any: the erase of a user clause IS an update
    (
        "tc_both",
        raw"assertz(d(1)), trie_new(T3), trie_insert(T3, f(1), v1), forall(trie_gen_compiled(T3, _, _), true), trie_new(T2), trie_insert(T2, g(1)), forall(trie_gen_compiled(T2, _), true), tc_nc(trie_gen_compiled(_, _, _), C3), tc_nc(trie_gen_compiled(_, _), C2), transaction((retract(d(1)), trie_destroy(T3), trie_destroy(T2), transaction_updates(U), tc_kinds(U, K))), R = r(C3, C2, K)"
    )   # TB9-trieclause-2, -3 and -any: both trie erases hidden, the user erase listed
]

const _T9_TRIE = (
    unit="tb9rows_trie",
    program=raw"""
:- dynamic d/1.
tt_clean :- retractall(d(_)).
tc_nc(P, N) :- ( predicate_property(system:P, number_of_clauses(N)) -> true ; N = none ).
tc_kinds(U, K) :- findall(F, (member(X, U), functor(X, F, _)), K0), msort(K0, K).
""",
    cases=_T9_TRIE_CASES,
    kill=["tc3", "tc2", "tc_ctl", "tc_both"],
    # swipl 10.1.20, `tt_q(t_<case>, A)` in order, two identical runs
    pinned=[
        "r(1,0)",   # tc3
        "r(1,0)",   # tc2
        "[erased]",   # tc_ctl
        "r(1,1,[erased])"   # tc_both
    ]
)

"The three testsets of one unit (every one runs >= 1 assertion with or without `swipl`, and each proves its comparison can fail)."
function _t9_check_unit(u)
    ids = [id for (id, _) in u.cases]
    kidx = [findfirst(==(k), ids)::Int for k in u.kill]
    @testset "$(u.unit)" begin
        gd, ld, st = _t9_load(u)
        lines = String[_t9_ask(gd, ld, "t_$id") for id in ids]
        @testset "$(u.unit): the rows run as swipl's pins (kills $(join(u.kill, ", ")))" begin
            @test st === :ok
            @test !isempty(lines) && !isempty(u.pinned) &&
                length(lines) == length(u.pinned) == length(ids)
            for (id, k, p) in zip(ids, lines, u.pinned)
                k == p || println(stderr, "  ours  ", id, " ", k, "\n  swipl ", p)
                @test k == p
            end
            @test _t9_flagged(lines, u.pinned, kidx)        # a corrupted pin is flagged, kill rows included
        end
        @testset "$(u.unit): the pins are well formed; the comparison can fail" begin
            @test allunique(ids)
            @test length(u.pinned) == length(ids)
            @test all(!isempty, u.pinned)
            @test _t9_flagged(u.pinned, u.pinned, kidx)
        end
        @testset "$(u.unit): the pins are swipl's (live, when swipl is on PATH)" begin
            if Sys.which("swipl") === nothing || get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1"
                @info "TB9-ROWS LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
                @test length(u.pinned) == length(ids)
                @test _t9_flagged(u.pinned, u.pinned, kidx)
            else
                live = _t9_swipl_lines(u)
                @test live == u.pinned
                @test _t9_flagged(live, u.pinned, kidx)
            end
        end
    end
    return nothing
end

_t9_check_unit(_T9_NM)
_t9_check_unit(_T9_NL)
_t9_check_unit(_T9_TRIE)

# ── NOT VACUOUS: each kill row shows the very value the mutant changes ──────────────────────────────────────────────────────
@testset "TB9-ROWS: every kill row holds the value its mutant changes, and the mutant's answer is not the pin" begin
    # ABOLISH-TWO: the answer of the table that was NOT abolished was [1,2] inside the transaction and is [1] after the rollback;
    # TB9-abolish-trie keeps [1,2], so the text of the mutant's answer is the pin with its tail changed.
    for u in (_T9_NM, _T9_NL)
        ids = [id for (id, _) in u.cases]
        for (k, tail) in (("ab2_destroy_p", ",no,[1,2],[1])"), ("ab2_destroy_q", ",no,[1],[1,2])"))
            pin = u.pinned[findfirst(==(k), ids)::Int]
            @test occursin("-[1,2],no,[1],[1])", pin)             # in the transaction the tables answered [1,2]; after it [1]
            mutant = replace(pin, ",no,[1],[1])" => tail)           # the table that is not abolished keeps its answer
            @test mutant != pin
            @test _t9_diff([mutant], [pin]) == [1]
        end
        @test u.pinned[findfirst(==("ab2_destroy_p"), ids)::Int] ==
              u.pinned[findfirst(==("ab2_none"), ids)::Int]         # an abolished table changes no other table's rollback
    end
    # TRIE-UPDATES: the clause existed before the transaction, no update is listed for its erase, the user clause's erase is listed.
    ids = [id for (id, _) in _T9_TRIE_CASES]
    pin(k) = _T9_TRIE.pinned[findfirst(==(k), ids)::Int]
    @test pin("tc3") == "r(1,0)" && pin("tc2") == "r(1,0)"      # the mutant lists the erase: r(1,1)
    @test pin("tc_ctl") == "[erased]"                            # the mutant that hides every erase answers []
    @test pin("tc_both") == "r(1,1,[erased])"
end
