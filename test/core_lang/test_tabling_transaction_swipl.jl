# ORIGINAL: the UPSTREAM tabling-transaction tests as LIVE rows against swipl at the pin (swipl-devel 18168e62, 10.1.20), TAB1 TB9
# (transaction tables: the table trail of pl-tabling.c 7405-7822 and its eight sites). The four upstream files
#   tests/tabling/test_transaction_tabling.pl   unit tr_incremental_tabling           assert, tmp_assert, retract            (3)
#   tests/tabling/test_transact_incr.pl         unit test_transact_incr_1             commit, rollback, snapshot x4          (6)
#   tests/tabling/test_transact_mono.pl         units test_transact_mono_1, _2        6 + retract                            (7)
#   tests/tabling/test_transact_mono_lazy.pl    units test_transact_mono_lazy_1 .. _5 6 + 3 + 1 + 1 + 2                      (13)
# are 29 cases; every one is a row here (`tabling_testlib.pl` is a helper library USED BY NONE of the four: no case).
#   * Each unit is its own program in its own database; its cases `t_<id>(R)` run in order, each wrapped by `tt_q/2`, which runs the
#     case, runs the unit's cleanup (upstream's `cleanup(cleanup([d/1]))` option) and writes the answer with
#     `format(atom(A), "~q", [R])` IN PROLOG, so a pin is swipl's own text. A case returns what the upstream test ASSERTS as a
#     term: every `expect(X, p(X), L)` is the sorted answers of `p/1` (`tt_ex/2`), every `expect_valid/1` / `expect_invalid/1` is
#     `valid` / `invalid` (`tt_inv/2`), a failing transaction is `no` (`tt_yn/2`). The answers the upstream test passes to
#     `assertion/1` are listed beside the pin as `upstream` (hand-written from its source) and must EQUAL the pin: the pin is swipl's
#     run, the upstream list is the test's own expectation, a unit passes only when both agree and the kernel agrees.
#   * HELPERS the kernel cannot load: library(increval) `incr_is_invalid/1` and library(tables) `get_call/3` / `get_calls/3` are
#     library predicates the kernel has no loader for yet (owner LIB; `'$tbl_implementation'/2` and `'$table_mode'/3` are the
#     tabling directive's, TB8). `tt_inv/2` is their semantics for a variant: the falsecount of the table found by
#     `'$tbl_variant_table'(0, user:G, T, ...)` is above 0 (`incr_is_invalid` = `get_calls` + `'$idg_falsecount' > 0`); both
#     swipl and the kernel run the SAME helper. `expect_forced/1` (`'$idg_forced'/1`), `expect_queued_answers/2`
#     (`'$idg_mono_affects_lazy'/5`) are DEFINED by the four files and CALLED by none of the 29 cases.
#   * `assertion/1` and plunit are not used by the kernel rows (a failed `assertion` there is a failing row: the term differs).
#   * Every pin was produced by running the exact program on swipl TWICE (identical), and the four upstream files were run on the
#     same binary with `run_tests` (29 of 29 passed): evidence/TAB1/w3_verify.md.
#   * UNVERIFIED on the kernel (nothing was compiled when these rows were written): every kernel answer; the gate decides.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — these built-ins ride the term layer through the FLI (unify, get, the trie blobs)
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TT = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_tts(x) = lk_sym(_TT, Symbol(x))

"The helpers every unit's program starts with."
const _TT_COMMON = raw"""
tt_q(G, A) :- ( catch(call(G, R), E, R = exc(E)) -> true ; R = failed ), tt_clean, format(atom(A), "~q", [R]).
tt_ex(G, L) :- findall(X, call(G, X), L0), sort(L0, L).
tt_inv(G, Y) :- ( '$tbl_variant_table'(0, user:G, T, _, _, _), '$idg_falsecount'(T, C), C > 0 -> Y = invalid ; Y = valid ).
tt_yn(G, Y) :- ( call(G) -> Y = yes ; Y = no ).
tt_init(G) :- forall(G, true).
tt_note(X) :- nb_setval(tt_in, X).
:- nb_setval(tt_in, none).
"""

"The program of a unit: the helpers, the unit's clauses, the cases."
_tt_text(u) = _TT_COMMON * u.program * join(["t_$(id)(R) :- $body.\n" for (id, body) in u.cases])

"The `~q` text of each case's answer, in order, from swipl at the pin."
function _tt_swipl_lines(u)::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "tt.pl")
        write(
            f,
            _tt_text(u) * ":- initialization((forall(member(G, [" * join(["t_$id" for (id, _) in u.cases], ",") *
            "]), (tt_q(G, A), write(A), nl)), halt)).\n"
        )
        read(pipeline(addenv(`swipl -q $f`, "LC_ALL" => "C"); stdin=devnull, stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

"The `~q` text of the answer of `case`, run as `tt_q(case, A)` in the kernel."
function _tt_ask(gd, ld, case::String)::String
    proc = LK.isCurrentProcedure(sym_key(_tts("tt_q")), 2, LK.MODULE_user(gd))
    (proc === nothing || !LK.isDefinedProcedure(gd, proc)) && return "tt_q undefined"
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 2)
    LK.putSlotValue!(ld, a + 1, _tts(case), LK.PutVarMap())
    LK.putSlotValue!(ld, a + 2, mk_var(_TT, LK.fresh_var_keys!(1)), LK.PutVarMap())
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

"A kernel with the unit's program consulted: `(gd, ld, load status)`."
function _tt_load(u)
    f = joinpath(mktempdir(), "tabling_transaction.pl")
    write(f, _tt_text(u))
    gd = LK.PL_global_data{_TT}()
    ld = LK.PL_local_data{_TT}(gd)
    st, _ = LK.load_file!(gd, ld, f)
    return gd, ld, st
end

"The indices where two answer lists differ (a missing answer counts as a difference)."
_tt_diff(lines::Vector{String}, pins::Vector{String}) =
    [i for i in 1:max(length(lines), length(pins)) if i > length(lines) || i > length(pins) || lines[i] != pins[i]]

"The three testsets of one unit (every one runs >= 1 assertion with or without `swipl`)."
function _tt_check_unit(u)
    @testset "$(u.unit)" begin
        ids = [id for (id, _) in u.cases]
        gd, ld, st = _tt_load(u)
        lines = String[_tt_ask(gd, ld, "t_$id") for id in ids]
        @testset "$(u.unit): the upstream cases run as swipl's pins" begin
            @test st === :ok
            @test !isempty(lines) && !isempty(u.pinned) && length(lines) == length(u.pinned) == length(ids)
            for (id, k, p) in zip(ids, lines, u.pinned)
                k == p || println(stderr, "  ours  ", id, " ", k, "\n  swipl ", p)
                @test k == p
            end
        end
        @testset "$(u.unit): the pins are the upstream expectation; the comparison can fail" begin
            @test u.pinned == u.upstream                 # swipl's run satisfies what the upstream test asserts
            @test allunique(u.pinned)                    # no two cases are the same row
            corrupt = copy(u.pinned)
            corrupt[1] = corrupt[1] * "x"
            @test _tt_diff(lines, corrupt) == sort(union(_tt_diff(lines, u.pinned), [1]))      # a corrupted pin is flagged
            @test _tt_diff(lines, vcat(u.pinned, "extra")) == sort(union(_tt_diff(lines, u.pinned), [length(u.pinned) + 1]))
            @test _tt_diff(lines, u.pinned[1:(end - 1)]) == sort(union(_tt_diff(lines, u.pinned), [length(u.pinned)]))
        end
        @testset "$(u.unit): the pins are swipl's (live, when swipl is on PATH)" begin
            if Sys.which("swipl") === nothing || get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1"
                @info "TB9 LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
                @test length(u.pinned) == length(u.cases) == length(u.upstream)
            else
                @test _tt_swipl_lines(u) == u.pinned
            end
        end
    end
    return nothing
end

# upstream: tests/tabling/test_transaction_tabling.pl, unit `tr_incremental_tabling`
const _TT_TABLING = (
    unit = "tr_incremental_tabling",
    program = raw"""
:- table p/1 as incremental.
:- dynamic d/1 as incremental.
p(X) :- d(X).
tt_clean :- retractall(d(_)), abolish_all_tables.
tt_add_to_p(B) :- assertz(d(2)), tt_ex(p, B).
tt_add_to_p2(A) :- assertz(d(1)), tt_ex(p, A), retractall(d(_)).
tt_del_from_p(B) :- retract(d(2)), tt_ex(p, B).
""",
    cases = [
        ("assert", raw"assertz(d(1)), tt_ex(p, A), snapshot(tt_add_to_p(B)), tt_ex(p, C), R = r(A, B, C)"),   # upstream test(assert)
        ("tmp_assert", raw"snapshot(tt_add_to_p2(A)), tt_yn(p(_), Y), R = r(A, Y)"),   # upstream test(tmp_assert)
        ("retract", raw"assertz(d(1)), assertz(d(2)), tt_ex(p, A), snapshot(tt_del_from_p(B)), tt_ex(p, C), R = r(A, B, C)"),   # upstream test(retract)
    ],
    # swipl 10.1.20, `tt_q(t_<case>, A)` in order, two identical runs (evidence/TAB1/w3_verify.md)
    pinned = [
        "r([1],[1,2],[1])",   # assert
        "r([1],no)",   # tmp_assert
        "r([1,2],[1],[1,2])",   # retract
    ],
    # hand-written from the assertions of the upstream test (expect/3, expect_valid/1, expect_invalid/1)
    upstream = [
        "r([1],[1,2],[1])",   # assert
        "r([1],no)",   # tmp_assert
        "r([1,2],[1],[1,2])",   # retract
    ],
)

_tt_check_unit(_TT_TABLING)

# upstream: tests/tabling/test_transact_incr.pl, unit `test_transact_incr_1`
const _TT_INCR = (
    unit = "test_transact_incr_1",
    program = raw"""
:- dynamic d/1 as incremental.
:- table p/1 as (incremental).
p(X) :- d(X).
tt_clean :- abolish_all_tables, retractall(d(_)).
""",
    cases = [
        ("commit", raw"assertz(d(1)), tt_ex(p, A), transaction((assertz(d(2)), tt_ex(p, B))), tt_inv(p(_), V), tt_ex(p, C), R = r(A, B, V, C)"),   # upstream test(commit)
        ("rollback", raw"assertz(d(1)), tt_ex(p, A), tt_yn(transaction((assertz(d(2)), tt_ex(p, B), tt_note(B), fail)), Y), nb_getval(tt_in, B1), tt_inv(p(_), V), tt_ex(p, C), R = r(A, Y, B1, V, C)"),   # upstream test(rollback)
        ("sn1", raw"assertz(d(1)), tt_ex(p, A), snapshot((assertz(d(2)), tt_ex(p, B))), tt_inv(p(_), V), tt_ex(p, C), R = r(A, B, V, C)"),   # upstream test(snapshot (1: snapshots behave the same))
        ("sn2", raw"assertz(d(1)), assertz(d(2)), snapshot(tt_ex(p, A)), tt_inv(p(_), V), tt_ex(p, C), R = r(A, V, C)"),   # upstream test(snapshot (2: evaluated inside, no dependency modified))
        ("sn3", raw"assertz(d(1)), tt_ex(p, A), assertz(d(2)), snapshot((tt_inv(p(_), V0), tt_ex(p, B))), tt_inv(p(_), V1), tt_ex(p, C), R = r(A, V0, B, V1, C)"),   # upstream test(snapshot (3: re-evaluated inside, dependencies untouched in it))
        ("sn4", raw"assertz(d(1)), assertz(d(2)), snapshot((tt_ex(p, A), assertz(d(3)), tt_ex(p, B))), tt_inv(p(_), V), tt_ex(p, C), R = r(A, B, V, C)"),   # upstream test(snapshot (4: evaluated inside, then updated))
    ],
    # swipl 10.1.20, `tt_q(t_<case>, A)` in order, two identical runs (evidence/TAB1/w3_verify.md)
    pinned = [
        "r([1],[1,2],valid,[1,2])",   # commit
        "r([1],no,[1,2],invalid,[1])",   # rollback
        "r([1],[1,2],invalid,[1])",   # sn1
        "r([1,2],valid,[1,2])",   # sn2
        "r([1],invalid,[1,2],valid,[1,2])",   # sn3
        "r([1,2],[1,2,3],invalid,[1,2])",   # sn4
    ],
    # hand-written from the assertions of the upstream test (expect/3, expect_valid/1, expect_invalid/1)
    upstream = [
        "r([1],[1,2],valid,[1,2])",   # commit
        "r([1],no,[1,2],invalid,[1])",   # rollback
        "r([1],[1,2],invalid,[1])",   # sn1
        "r([1,2],valid,[1,2])",   # sn2
        "r([1],invalid,[1,2],valid,[1,2])",   # sn3
        "r([1,2],[1,2,3],invalid,[1,2])",   # sn4
    ],
)

_tt_check_unit(_TT_INCR)

# upstream: tests/tabling/test_transact_mono.pl, unit `test_transact_mono_1`
const _TT_MONO1 = (
    unit = "test_transact_mono_1",
    program = raw"""
:- dynamic d/1 as monotonic.
:- table p/1 as (monotonic).
p(X) :- d(X).
tt_clean :- abolish_all_tables, retractall(d(_)).
""",
    cases = [
        ("commit", raw"assertz(d(1)), tt_ex(p, A), transaction((assertz(d(2)), tt_ex(p, B))), tt_inv(p(_), V), tt_ex(p, C), R = r(A, B, V, C)"),   # upstream test(commit)
        ("rollback", raw"assertz(d(1)), tt_ex(p, A), tt_yn(transaction((assertz(d(2)), tt_ex(p, B), tt_note(B), fail)), Y), nb_getval(tt_in, B1), tt_inv(p(_), V), tt_ex(p, C), R = r(A, Y, B1, V, C)"),   # upstream test(rollback)
        ("sn1", raw"assertz(d(1)), tt_ex(p, A), snapshot((assertz(d(2)), tt_ex(p, B))), tt_inv(p(_), V), tt_ex(p, C), R = r(A, B, V, C)"),   # upstream test(snapshot (1: snapshots behave the same))
        ("sn2", raw"assertz(d(1)), assertz(d(2)), snapshot(tt_ex(p, A)), tt_inv(p(_), V), tt_ex(p, C), R = r(A, V, C)"),   # upstream test(snapshot (2: evaluated inside, no dependency modified))
        ("sn3", raw"assertz(d(1)), tt_ex(p, A), assertz(d(2)), snapshot((tt_inv(p(_), V0), tt_ex(p, B))), tt_inv(p(_), V1), tt_ex(p, C), R = r(A, V0, B, V1, C)"),   # upstream test(snapshot (3: re-evaluated inside, dependencies untouched in it))
        ("sn4", raw"assertz(d(1)), assertz(d(2)), snapshot((tt_ex(p, A), assertz(d(3)), tt_ex(p, B))), tt_inv(p(_), V), tt_ex(p, C), R = r(A, B, V, C)"),   # upstream test(snapshot (4: evaluated inside, then updated))
    ],
    # swipl 10.1.20, `tt_q(t_<case>, A)` in order, two identical runs (evidence/TAB1/w3_verify.md)
    pinned = [
        "r([1],[1,2],valid,[1,2])",   # commit
        "r([1],no,[1,2],valid,[1])",   # rollback
        "r([1],[1,2],valid,[1])",   # sn1
        "r([1,2],valid,[1,2])",   # sn2
        "r([1],valid,[1,2],valid,[1,2])",   # sn3
        "r([1,2],[1,2,3],valid,[1,2])",   # sn4
    ],
    # hand-written from the assertions of the upstream test (expect/3, expect_valid/1, expect_invalid/1)
    upstream = [
        "r([1],[1,2],valid,[1,2])",   # commit
        "r([1],no,[1,2],valid,[1])",   # rollback
        "r([1],[1,2],valid,[1])",   # sn1
        "r([1,2],valid,[1,2])",   # sn2
        "r([1],valid,[1,2],valid,[1,2])",   # sn3
        "r([1,2],[1,2,3],valid,[1,2])",   # sn4
    ],
)

_tt_check_unit(_TT_MONO1)

# upstream: tests/tabling/test_transact_mono.pl, unit `test_transact_mono_2`
const _TT_MONO2 = (
    unit = "test_transact_mono_2",
    program = raw"""
:- dynamic d/1 as monotonic.
:- table p/1 as (monotonic).
p(X) :- d(X).
tt_clean :- abolish_all_tables, retractall(d(_)).
""",
    cases = [
        ("retract", raw"assertz(d(1)), assertz(d(2)), snapshot((tt_ex(p, A), retract(d(2)), tt_ex(p, B))), tt_inv(p(_), V), tt_ex(p, C), R = r(A, B, V, C)"),   # upstream test(retract)
    ],
    # swipl 10.1.20, `tt_q(t_<case>, A)` in order, two identical runs (evidence/TAB1/w3_verify.md)
    pinned = [
        "r([1,2],[1],invalid,[1,2])",   # retract
    ],
    # hand-written from the assertions of the upstream test (expect/3, expect_valid/1, expect_invalid/1)
    upstream = [
        "r([1,2],[1],invalid,[1,2])",   # retract
    ],
)

_tt_check_unit(_TT_MONO2)

# upstream: tests/tabling/test_transact_mono_lazy.pl, unit `test_transact_mono_lazy_1`
const _TT_LAZY1 = (
    unit = "test_transact_mono_lazy_1",
    program = raw"""
:- dynamic d/1 as monotonic.
:- table p/1 as (monotonic,lazy).
p(X) :- d(X).
tt_clean :- abolish_all_tables, retractall(d(_)).
""",
    cases = [
        ("commit", raw"assertz(d(1)), tt_ex(p, A), transaction((assertz(d(2)), tt_ex(p, B))), tt_inv(p(_), V), tt_ex(p, C), R = r(A, B, V, C)"),   # upstream test(commit)
        ("rollback", raw"assertz(d(1)), tt_ex(p, A), tt_yn(transaction((assertz(d(2)), tt_ex(p, B), tt_note(B), fail)), Y), nb_getval(tt_in, B1), tt_inv(p(_), V), tt_ex(p, C), R = r(A, Y, B1, V, C)"),   # upstream test(rollback)
        ("sn1", raw"assertz(d(1)), tt_ex(p, A), snapshot((assertz(d(2)), tt_ex(p, B))), tt_inv(p(_), V), tt_ex(p, C), R = r(A, B, V, C)"),   # upstream test(snapshot (1: snapshots behave the same))
        ("sn2", raw"assertz(d(1)), assertz(d(2)), snapshot(tt_ex(p, A)), tt_inv(p(_), V), tt_ex(p, C), R = r(A, V, C)"),   # upstream test(snapshot (2: evaluated inside, no dependency modified))
        ("sn3", raw"assertz(d(1)), tt_ex(p, A), assertz(d(2)), snapshot((tt_inv(p(_), V0), tt_ex(p, B))), tt_inv(p(_), V1), tt_ex(p, C), R = r(A, V0, B, V1, C)"),   # upstream test(snapshot (3: re-evaluated inside, dependencies untouched in it))
        ("sn4", raw"assertz(d(1)), assertz(d(2)), snapshot((tt_ex(p, A), assertz(d(3)), tt_ex(p, B))), tt_inv(p(_), V), tt_ex(p, C), R = r(A, B, V, C)"),   # upstream test(snapshot (4: evaluated inside, then updated))
    ],
    # swipl 10.1.20, `tt_q(t_<case>, A)` in order, two identical runs (evidence/TAB1/w3_verify.md)
    pinned = [
        "r([1],[1,2],valid,[1,2])",   # commit
        "r([1],no,[1,2],valid,[1])",   # rollback
        "r([1],[1,2],valid,[1])",   # sn1
        "r([1,2],valid,[1,2])",   # sn2
        "r([1],invalid,[1,2],valid,[1,2])",   # sn3
        "r([1,2],[1,2,3],valid,[1,2])",   # sn4
    ],
    # hand-written from the assertions of the upstream test (expect/3, expect_valid/1, expect_invalid/1)
    upstream = [
        "r([1],[1,2],valid,[1,2])",   # commit
        "r([1],no,[1,2],valid,[1])",   # rollback
        "r([1],[1,2],valid,[1])",   # sn1
        "r([1,2],valid,[1,2])",   # sn2
        "r([1],invalid,[1,2],valid,[1,2])",   # sn3
        "r([1,2],[1,2,3],valid,[1,2])",   # sn4
    ],
)

_tt_check_unit(_TT_LAZY1)

# upstream: tests/tabling/test_transact_mono_lazy.pl, unit `test_transact_mono_lazy_2`
const _TT_LAZY2 = (
    unit = "test_transact_mono_lazy_2",
    program = raw"""
:- dynamic d/1 as monotonic.
:- table p/1 as (monotonic,lazy).
p(X) :- d(X).
tt_clean :- abolish_all_tables, retractall(d(_)).
""",
    cases = [
        ("retract", raw"assertz(d(1)), assertz(d(2)), snapshot((tt_ex(p, A), retract(d(2)), tt_ex(p, B))), tt_inv(p(_), V), tt_ex(p, C), R = r(A, B, V, C)"),   # upstream test(retract)
        ("outside_assert", raw"assertz(d(1)), tt_init(p(_)), assertz(d(2)), snapshot((tt_inv(p(_), V0), tt_ex(p, B))), tt_inv(p(_), V1), tt_ex(p, C), R = r(V0, B, V1, C)"),   # upstream test(outside_assert)
        ("mixed_assert", raw"tt_init(p(_)), assertz(d(1)), tt_inv(p(_), V0), snapshot((assert(d(2)), tt_ex(p, B))), tt_inv(p(_), V1), tt_ex(p, C), R = r(V0, B, V1, C)"),   # upstream test(mixed_assert)
    ],
    # swipl 10.1.20, `tt_q(t_<case>, A)` in order, two identical runs (evidence/TAB1/w3_verify.md)
    pinned = [
        "r([1,2],[1],invalid,[1,2])",   # retract
        "r(invalid,[1,2],valid,[1,2])",   # outside_assert
        "r(invalid,[1,2],invalid,[1])",   # mixed_assert
    ],
    # hand-written from the assertions of the upstream test (expect/3, expect_valid/1, expect_invalid/1)
    upstream = [
        "r([1,2],[1],invalid,[1,2])",   # retract
        "r(invalid,[1,2],valid,[1,2])",   # outside_assert
        "r(invalid,[1,2],invalid,[1])",   # mixed_assert
    ],
)

_tt_check_unit(_TT_LAZY2)

# upstream: tests/tabling/test_transact_mono_lazy.pl, unit `test_transact_mono_lazy_3`
const _TT_LAZY3 = (
    unit = "test_transact_mono_lazy_3",
    program = raw"""
:- dynamic (da/1,db/1) as monotonic.
:- table p/1 as (monotonic,lazy).
p(X) :- da(A), db(B), X is A+B.
tt_clean :- abolish_all_tables, retractall(da(_)), retractall(db(_)).
""",
    cases = [
        ("outside_assert", raw"assertz(da(1)), assertz(db(10)), tt_init(p(_)), assertz(da(2)), snapshot((tt_inv(p(_), V0), assertz(db(100)), tt_ex(p, B))), tt_inv(p(_), V1), tt_ex(p, C), R = r(V0, B, V1, C)"),   # upstream test(outside_assert)
    ],
    # swipl 10.1.20, `tt_q(t_<case>, A)` in order, two identical runs (evidence/TAB1/w3_verify.md)
    pinned = [
        "r(invalid,[11,12,101,102],invalid,[11,12])",   # outside_assert
    ],
    # hand-written from the assertions of the upstream test (expect/3, expect_valid/1, expect_invalid/1)
    upstream = [
        "r(invalid,[11,12,101,102],invalid,[11,12])",   # outside_assert
    ],
)

_tt_check_unit(_TT_LAZY3)

# upstream: tests/tabling/test_transact_mono_lazy.pl, unit `test_transact_mono_lazy_4`
const _TT_LAZY4 = (
    unit = "test_transact_mono_lazy_4",
    program = raw"""
:- dynamic (da/1,db/1) as monotonic.
:- table p/1 as (monotonic,lazy).
p(X) :-
    da(A),
    (   A >= 10
    ->  db(B),
        X is A+B
    ;   X = A
    ).
tt_clean :- abolish_all_tables, retractall(da(_)), retractall(db(_)).
""",
    cases = [
        ("new_dependencies", raw"assertz(da(1)), tt_init(p(_)), assertz(da(10)), snapshot((tt_inv(p(_), V0), assertz(db(100)), tt_ex(p, B))), tt_inv(p(_), V1), tt_ex(p, C), R = r(V0, B, V1, C)"),   # upstream test(new_dependencies)
    ],
    # swipl 10.1.20, `tt_q(t_<case>, A)` in order, two identical runs (evidence/TAB1/w3_verify.md)
    pinned = [
        "r(invalid,[1,110],invalid,[1])",   # new_dependencies
    ],
    # hand-written from the assertions of the upstream test (expect/3, expect_valid/1, expect_invalid/1)
    upstream = [
        "r(invalid,[1,110],invalid,[1])",   # new_dependencies
    ],
)

_tt_check_unit(_TT_LAZY4)

# upstream: tests/tabling/test_transact_mono_lazy.pl, unit `test_transact_mono_lazy_5`
const _TT_LAZY5 = (
    unit = "test_transact_mono_lazy_5",
    program = raw"""
:- dynamic (da/1,db/1) as monotonic.
:- table (p/1,q/1,r/1) as (monotonic,lazy).
p(X) :- q(X).
p(X) :- r(X).
q(X) :- da(X).
r(X) :- db(X), X < 10.
tt_clean :- abolish_all_tables, retractall(da(_)), retractall(db(_)).
""",
    cases = [
        ("already_forced_1", raw"tt_clean, tt_init(p(_)), snapshot((assert(db(11)), retract(db(11)), assert(da(1)), assert(da(2)), tt_ex(p, A))), tt_ex(p, C), R = r(A, C)"),   # upstream test(already_forced_1)
        ("already_forced_2", raw"tt_clean, tt_init(p(_)), assert(db(11)), snapshot((assert(da(1)), assert(da(2)), tt_ex(p, A), retract(db(11)), tt_ex(p, B))), tt_ex(p, C), R = r(A, B, C)"),   # upstream test(already_forced_2)
    ],
    # swipl 10.1.20, `tt_q(t_<case>, A)` in order, two identical runs (evidence/TAB1/w3_verify.md)
    pinned = [
        "r([1,2],[])",   # already_forced_1
        "r([1,2],[1,2],[])",   # already_forced_2
    ],
    # hand-written from the assertions of the upstream test (expect/3, expect_valid/1, expect_invalid/1)
    upstream = [
        "r([1,2],[])",   # already_forced_1
        "r([1,2],[1,2],[])",   # already_forced_2
    ],
)

_tt_check_unit(_TT_LAZY5)

