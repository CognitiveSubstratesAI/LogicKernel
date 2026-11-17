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
#   * S3d (TB9 blockers of 3eaae177, D-0858): hc1 (TB9-hook-commit, units NM and NL), the units PREPARE (TB9-site-prepare-old, -new), NEWDEP
#     (TB9-site-newdep, -done, -prepare-reset), FORCEABOLISH (TB9-site-force-abolish) and PREPARE-MODIFIED (TB9-site-prepare-modified): rows
#     that read the falsecount NUMBER and the store counts the UP rows do not read. The effect of the mutants on them is NOT measured locally
#     (the CI battery mutants/TB9 decides); the catalogue's named kill UP sn3 of TB9-site-prepare-modified is wrong (sn3 leaves the dependencies untouched).
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
% the state the TB9R rows read: `valid`/`invalid`, the falsecount NUMBER, the number of answers in the store (`none`: no table)
tt_inv(G, Y) :- ( '$tbl_variant_table'(0, user:G, T, _, _, _), '$idg_falsecount'(T, C), C > 0 -> Y = invalid ; Y = valid ).
tt_init(G) :- forall(G, true).
tt_fc(G, N) :- ( '$tbl_variant_table'(0, user:G, T, _, _, _) -> '$idg_falsecount'(T, N) ; N = none ).
tt_ns(G, N) :- ( '$tbl_variant_table'(0, user:G, T, _, _, _) -> findall(K, trie_gen(T, K), Ks), length(Ks, N) ; N = none ).
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

# TB9-hook-commit (both table units): `r(A, B, Y1, N, Y2, S, E)`: A, B the answers before and inside the COMMITTED transaction (Y1),
# N what the second transaction saw, Y2 its failure, S the answers in the store afterwards, E the answers after. A commit that leaves
# the trail attached keeps `tt.tables` with the table, so the second transaction does not trail its answer 3: S 3 (not 2), E [1,2,3].
const _T9_HC = [
    (
    "hc1",
    raw"assertz(d(1)), tt_ex(p, A), tt_yn(transaction((assertz(d(2)), tt_ex(p, B))), Y1), tt_yn(transaction((assertz(d(3)), tt_ex(p, C), tt_note(C), fail)), Y2), nb_getval(tt_in, N), tt_ns(p(_), S), tt_ex(p, E), R = r(A, B, Y1, N, Y2, S, E)"
)   # TB9-hook-commit: the outermost commit frees the trail; two transactions in ONE case (tt_clean runs after each case)
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
    cases=vcat(_T9_AB2_CASES, _T9_HC),
    kill=["ab2_destroy_p", "ab2_destroy_q", "hc1"],
    # swipl 10.1.20, `tt_q(t_<case>, A)` in order, two identical runs
    pinned=[
        "r([1],[1],[1,2]-[1,2],no,[1],[1])",   # ab2_destroy_p
        "r([1],[1],[1,2]-[1,2],no,[1],[1])",   # ab2_destroy_q
        "r([1],[1],[1,2]-[1,2],no,[1],[1])",   # ab2_destroy_both
        "r([1],[1],[1,2]-[1,2],no,[1],[1])",   # ab2_none
        "r([1],[1,2],yes,[1,2,3],no,2,[1,2])"   # hc1
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
    cases=vcat(_T9_AB2_CASES, _T9_HC),
    kill=["ab2_destroy_p", "ab2_destroy_q", "hc1"],
    # swipl 10.1.20, `tt_q(t_<case>, A)` in order, two identical runs
    pinned=[
        "r([1],[1],[1,2]-[1,2],no,[1],[1])",   # ab2_destroy_p
        "r([1],[1],[1,2]-[1,2],no,[1],[1])",   # ab2_destroy_q
        "r([1],[1],[1,2]-[1,2],no,[1],[1])",   # ab2_destroy_both
        "r([1],[1],[1,2]-[1,2],no,[1],[1])",   # ab2_none
        "r([1],[1,2],yes,[1,2,3],no,2,[1,2])"   # hc1
    ]
)

# ── PREPARE: the lazy monotonic reevaluation prepares the table from the clauses it depends on ──────────────────────────────────
# `'$mono_reeval_prepare'` trails the answers of the reevaluation only when its clauses are new (`tt_notrail`). `r(.., S, V1, C)`: S the answers
# in the table's store after the transaction was rolled back, V1 whether the table is invalid, C its answers. Kills TB9-site-prepare-old
# (po1) and TB9-site-prepare-new (pn1): the store count is the answer of the table's own trail, which the UP rows read only through `V`/`C`.
const _T9_NP = (
    unit="tb9rows_prepare",
    program=raw"""
:- dynamic d/1 as monotonic.
:- table p/1 as (monotonic,lazy).
p(X) :- d(X).
tt_clean :- abolish_all_tables, retractall(d(_)).
""",
    cases=[
        (
            "po1",
            raw"assertz(d(1)), tt_init(p(_)), assertz(d(2)), snapshot(tt_ex(p,B)), tt_ns(p(_),S), tt_inv(p(_),V1), tt_ex(p,C), R=r(B,S,V1,C)"
        ),   # TB9-site-prepare-old: only OLD clauses changed the table: its answers are not trailed, 2 stay in the store (the mutant trails and rolls them back: 1)
        (
            "pn1",
            raw"assertz(d(1)), tt_ex(p,A), snapshot((assertz(d(2)), tt_ex(p,B))), tt_ns(p(_),S), tt_inv(p(_),V1), tt_ex(p,C), R=r(A,B,S,V1,C)"
        ),   # TB9-site-prepare-new: only NEW clauses (this transaction's): the answers ARE trailed, 1 stays in the store (the mutant does not trail: 2)
        (
            "pm1",
            raw"assertz(d(1)), tt_ex(p,A), assertz(d(2)), snapshot((assertz(d(3)), tt_ex(p,B))), tt_ns(p(_),S), tt_inv(p(_),V1), tt_ex(p,C), R=r(A,B,S,V1,C)"
        )   # control: old and new clauses (mixed): the table is listed, `invalid` after the snapshot
    ],
    kill=["po1", "pn1", "pm1"],
    # swipl 10.1.20, `tt_q(t_<case>, A)` in order, two identical runs
    pinned=[
        "r([1,2],2,valid,[1,2])",   # po1
        "r([1],[1,2],1,valid,[1])",   # pn1
        "r([1],[1,2,3],2,invalid,[1,2])"   # pm1
    ]
)

# ── NEW DEPENDENCY (`tt_new_dep`: set by `idg_add_child` for a new dynamic child modified in the transaction, reset by `'$mono_reeval_prepare'`,
# read by `'$mono_reeval_done'`) ──────────────────────────────────────────────────────────────────────────────────────────────
# The UP row (test_transact_mono_lazy_4) reads `valid`/`invalid`, and those survive TB9-site-newdep, -done and -prepare-reset; these rows read the
# falsecount NUMBER (F) and the store count (S) as well, and nd4/nd5 run a second reevaluation in a transaction of its own.
const _T9_ND = (
    unit="tb9rows_newdep",
    program=raw"""
:- dynamic (da/1,db/1) as monotonic.
:- table p/1 as (monotonic,lazy).
p(X) :- da(A), ( A >= 10 -> db(B), X is A+B ; X = A ).
tt_clean :- abolish_all_tables, retractall(da(_)), retractall(db(_)).
""",
    cases=[
        (
            "nd1",
            raw"assertz(da(1)), tt_init(p(_)), assertz(da(10)), snapshot((tt_inv(p(_),V0), tt_fc(p(_),F0), assertz(db(100)), tt_ex(p,B), tt_fc(p(_),F1))), tt_fc(p(_),F2), tt_inv(p(_),V1), tt_ex(p,C), tt_fc(p(_),F3), tt_ns(p(_),S), R=r(V0,F0,B,F1,F2,V1,C,F3,S)"
        ),   # the lazy_4 shape with the falsecount NUMBER: F2 = 1 after the snapshot (TB9-site-newdep, -done)
        (
            "nd3",
            raw"assertz(da(1)), assertz(db(100)), tt_init(p(_)), assertz(da(10)), snapshot((retract(db(100)), tt_ex(p,B), tt_fc(p(_),F1))), tt_fc(p(_),F2), tt_inv(p(_),V1), tt_ex(p,C), tt_fc(p(_),F3), tt_ns(p(_),S), R=r(B,F1,F2,V1,C,F3,S)"
        ),   # the new dependency db is modified by a RETRACT of an old clause (no erase of a new clause at the rollback): F2 1, S 2
        (
            "nd4",
            raw"assertz(da(1)), tt_init(p(_)), assertz(da(10)), snapshot((assertz(db(100)), tt_ex(p,B))), tt_fc(p(_),F2), snapshot((tt_ex(p,C), tt_fc(p(_),F3))), tt_fc(p(_),F4), tt_inv(p(_),V), tt_ex(p,E), R=r(B,F2,C,F3,F4,V,E)"
        ),   # TB9-site-prepare-reset: a second transaction reevaluates with no new dependency; a flag left from the first lists the table again: F4 0 (the mutant: 1)
        (
            "nd5",
            raw"assertz(da(1)), assertz(db(100)), tt_init(p(_)), assertz(da(10)), snapshot((retract(db(100)), tt_ex(p,B))), tt_fc(p(_),F2), snapshot((tt_ex(p,C), tt_fc(p(_),F3))), tt_fc(p(_),F4), tt_inv(p(_),V), tt_ex(p,E), R=r(B,F2,C,F3,F4,V,E)"
        ),   # TB9-site-prepare-reset with the retract shape of nd3
        (
            "nd6",
            raw"assertz(da(1)), tt_init(p(_)), assertz(da(10)), snapshot((assertz(db(100)), retract(db(100)), tt_ex(p,B), tt_fc(p(_),F1))), tt_fc(p(_),F2), tt_inv(p(_),V1), tt_ex(p,C), tt_fc(p(_),F3), tt_ns(p(_),S), R=r(B,F1,F2,V1,C,F3,S)"
        ),   # TB9-site-newdep, -done: db is modified in the transaction by an assertz AND its retract: the rollback restores nothing, so only tt_new_dep lists the table (F2 1)
        (
            "nd8",
            raw"assertz(da(1)), tt_init(p(_)), assertz(da(10)), snapshot((assertz(db(100)), retract(db(100)), tt_ex(p,B))), tt_fc(p(_),F1), tt_ex(p,C), tt_fc(p(_),F2), assertz(da(2)), tt_fc(p(_),F3), snapshot((tt_ex(p,D), tt_fc(p(_),F4))), tt_fc(p(_),F5), tt_inv(p(_),V), tt_ex(p,E), tt_ns(p(_),S), R=r(B,F1,C,F2,F3,D,F4,F5,V,E,S)"
        )   # TB9-site-prepare-reset: the flag a first transaction left true (nd6's shape) must be reset when a LATER lazy reevaluation (da(2) queued outside) starts: not listed, F5 0 and valid
    ],
    kill=["nd1", "nd3", "nd4", "nd5", "nd6", "nd8"],
    # swipl 10.1.20, `tt_q(t_<case>, A)` in order, two identical runs
    pinned=[
        "r(invalid,1,[1,110],0,1,invalid,[1],0,1)",   # nd1
        "r([1],0,1,invalid,[1,110],0,2)",   # nd3
        "r([1,110],1,[1],0,0,valid,[1])",   # nd4
        "r([1],1,[1,110],0,0,valid,[1,110])",   # nd5
        "r([1],0,1,invalid,[1],0,1)",   # nd6
        "r([1],1,[1],0,1,[1,2],0,0,valid,[1,2],2)"   # nd8
    ]
)

# ── FORCE-ABOLISH (`force_reeval` inside a transaction lists the table and drops its scheduled answers) ──────────────────────────
# `r(A, B, S1, S2, Sa, C, Sb)`: the answers inside, the state after the first call and after `retract(db(11))` (inside), the state after the
# snapshot and after the next call (outside). UP already_forced_2 reads only A, B and C.
const _T9_FA = (
    unit="tb9rows_forceabolish",
    program=raw"""
:- dynamic (da/1,db/1) as monotonic.
:- table (p/1,q/1,r/1) as (monotonic,lazy).
p(X) :- q(X).
p(X) :- r(X).
q(X) :- da(X).
r(X) :- db(X), X < 10.
tt_clean :- abolish_all_tables, retractall(da(_)), retractall(db(_)).
tt_st(S) :- tt_ns(p(_), P), tt_ns(q(_), Q), tt_ns(r(_), Rr), tt_fc(p(_), FP), tt_fc(q(_), FQ), S = s(P, Q, Rr, FP, FQ).
tt_save(K, S) :- nb_setval(K, S).
""",
    cases=[
        (
        "fa1",
        raw"tt_clean, tt_init(p(_)), assert(db(11)), snapshot((assert(da(1)), assert(da(2)), tt_ex(p,A), tt_st(S1), tt_save(tt_s1,S1), retract(db(11)), tt_st(S2), tt_save(tt_s2,S2), tt_ex(p,B))), tt_st(Sa), tt_ex(p,C), tt_st(Sb), nb_getval(tt_s1,T1), nb_getval(tt_s2,T2), R = r(A,B,T1,T2,Sa,C,Sb)"
    )   # TB9-site-force-abolish: the lazy_5 already_forced_2 program with the STATE of the tables: s(answers of p, q, r; falsecount of p, q) inside, after the snapshot and after the next call
    ],
    kill=["fa1"],
    # swipl 10.1.20, `tt_q(t_<case>, A)` in order, two identical runs
    pinned=[
        "r([1,2],[1,2],s(2,2,0,0,0),s(2,2,0,1,0),s(2,0,0,3,0),[],s(0,0,0,0,0))"   # fa1
    ]
)

# ── PREPARE-MODIFIED (`prepare_reeval` lists the table when a dependency was modified in the transaction) ─────────────────────────
# The UP snapshot rows (sn3) leave the dependencies untouched, so the catalogue's named kill (UP sn3) is NOT one; here d/1 is modified inside the
# snapshot before the incremental table is reevaluated. `r(.., F2, V, ..)`: F2 the falsecount after the snapshot (swipl: 1, the table is invalid).
const _T9_PI = (
    unit="tb9rows_prepare_modified",
    program=raw"""
:- dynamic d/1 as incremental.
:- table p/1 as incremental.
p(X) :- d(X), X < 5.
tt_clean :- abolish_all_tables, retractall(d(_)).
""",
    cases=[
        (
            "j1",
            raw"assertz(d(1)), tt_ex(p,A), snapshot((assertz(d(9)), tt_ex(p,B), tt_fc(p(_),F1))), tt_fc(p(_),F2), tt_inv(p(_),V), tt_ns(p(_),S), tt_ex(p,C), tt_fc(p(_),F3), R=r(A,B,F1,F2,V,S,C,F3)"
        ),   # TB9-site-prepare-modified: a reevaluation over a predicate modified in the transaction, answers unchanged: listed (invalid after the snapshot)
        (
            "j2",
            raw"assertz(d(1)), tt_ex(p,A), snapshot((assertz(d(2)), tt_ex(p,B), tt_fc(p(_),F1))), tt_fc(p(_),F2), tt_inv(p(_),V), tt_ns(p(_),S), tt_ex(p,C), tt_fc(p(_),F3), R=r(A,B,F1,F2,V,S,C,F3)"
        ),   # the same with a new answer inside
        (
            "j3",
            raw"assertz(d(1)), tt_ex(p,A), snapshot((assertz(d(9)), tt_fc(p(_),F0), tt_ex(p,B), tt_fc(p(_),F1))), tt_fc(p(_),F2), tt_inv(p(_),V), tt_ex(p,C), R=r(A,F0,B,F1,F2,V,C)"
        ),   # the same with the falsecount read before and inside
        (
            "j4",
            raw"assertz(d(1)), tt_ex(p,A), snapshot((assertz(d(9)), retract(d(9)), tt_ex(p,B), tt_fc(p(_),F1))), tt_fc(p(_),F2), tt_inv(p(_),V), tt_ns(p(_),S), tt_ex(p,C), tt_fc(p(_),F3), R=r(A,B,F1,F2,V,S,C,F3)"
        ),   # TB9-site-prepare-modified: the clause is asserted AND retracted in the transaction: the rollback restores nothing, only the listing in prepare_reeval makes the table invalid
        (
            "j6",
            raw"assertz(d(1)), tt_ex(p,A), snapshot((assertz(d(9)), retract(d(9)), tt_fc(p(_),F0), tt_ex(p,B), tt_fc(p(_),F1))), tt_fc(p(_),F2), tt_inv(p(_),V), tt_ns(p(_),S), tt_ex(p,C), tt_fc(p(_),F3), R=r(A,F0,B,F1,F2,V,S,C,F3)"
        )   # j4 with the falsecount read before the reevaluation
    ],
    kill=["j1", "j2", "j3", "j4", "j6"],
    # swipl 10.1.20, `tt_q(t_<case>, A)` in order, two identical runs
    pinned=[
        "r([1],[1],0,1,invalid,1,[1],0)",   # j1
        "r([1],[1,2],0,1,invalid,2,[1],0)",   # j2
        "r([1],1,[1],0,1,invalid,[1])",   # j3
        "r([1],[1],0,1,invalid,1,[1],0)",   # j4
        "r([1],1,[1],0,1,invalid,1,[1],0)"   # j6
    ]
)

# The reevaluation DROPS the modified dependency: `prepare_reeval` lists the table at its START (the dependency d/1 was modified in the transaction),
# the completion check of the reevaluation no longer sees d/1 (the table now calls only fl/1, which the transaction leaves alone). `r(A, F0, B, F1, F2, V, S, C, F3)`.
const _T9_PI2 = (
    unit="tb9rows_prepare_modified_dropped",
    program=raw"""
:- dynamic (fl/1, d/1) as incremental.
:- table p/1 as incremental.
p(X) :- fl(F), ( F == 1 -> d(X) ; X = 0 ).
tt_clean :- abolish_all_tables, retractall(d(_)), retractall(fl(_)).
""",
    cases=[
        (
            "k1",
            raw"assertz(fl(1)), assertz(d(1)), tt_ex(p,A), retract(fl(1)), assertz(fl(2)), tt_fc(p(_),F0), snapshot((assertz(d(9)), tt_ex(p,B), tt_fc(p(_),F1))), tt_fc(p(_),F2), tt_inv(p(_),V), tt_ns(p(_),S), tt_ex(p,C), tt_fc(p(_),F3), R=r(A,F0,B,F1,F2,V,S,C,F3)"
        ),   # TB9-site-prepare-modified: d/1, a dependency of the OLD evaluation, is modified in the transaction; the reevaluation drops it: only the listing at prepare_reeval makes the table invalid (F2 1)
        (
            "k2",
            raw"assertz(fl(1)), assertz(d(1)), tt_ex(p,A), retract(fl(1)), assertz(fl(2)), snapshot((tt_ex(p,B), tt_fc(p(_),F1))), tt_fc(p(_),F2), tt_inv(p(_),V), tt_ex(p,C), R=r(A,B,F1,F2,V,C)"
        )   # control: d/1 is not modified in the transaction: the table is valid after the snapshot
    ],
    kill=["k1", "k2"],
    # swipl 10.1.20, `tt_q(t_<case>, A)` in order, two identical runs
    pinned=[
        "r([1],1,[0],0,1,invalid,1,[0],0)",   # k1
        "r([1],[0],0,0,valid,[0])"   # k2
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
_t9_check_unit(_T9_NP)
_t9_check_unit(_T9_ND)
_t9_check_unit(_T9_FA)
_t9_check_unit(_T9_PI)
_t9_check_unit(_T9_PI2)
_t9_check_unit(_T9_TRIE)

# ── NOT VACUOUS: each kill row shows the very value the mutant changes ──────────────────────────────────────────────────────
@testset "TB9-ROWS: every kill row holds the value its mutant changes, and the mutant's answer is not the pin" begin
    # ABOLISH-TWO: the answer of the table that was NOT abolished was [1,2] inside the transaction and is [1] after the rollback;
    # TB9-abolish-trie keeps [1,2], so the text of the mutant's answer is the pin with its tail changed.
    for u in (_T9_NM, _T9_NL)
        ids = [id for (id, _) in u.cases]
        for (k, tail) in
            (("ab2_destroy_p", ",no,[1,2],[1])"), ("ab2_destroy_q", ",no,[1],[1,2])"))
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
    # S3d: hook-commit: the second transaction took its answer 3 back (2 answers stay in the store, E without 3)
    for u in (_T9_NM, _T9_NL)
        @test u.pinned[findfirst(==("hc1"), [id for (id, _) in u.cases])::Int] ==
            "r([1],[1,2],yes,[1,2,3],no,2,[1,2])"
    end
    # nd4/nd5: the second reevaluation lists no table (falsecount 0 after it); a stale `tt_new_dep` would make it 1
    @test endswith(_T9_ND.pinned[3], ",0,0,valid,[1])") &&
        endswith(_T9_ND.pinned[4], ",0,0,valid,[1,110])")
end
