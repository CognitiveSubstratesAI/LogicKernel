# ORIGINAL: a LIVE differential of the NEW-ANSWER EVENT of a tabled predicate (pl-tabling.c `atrie_answer_event`, :11443-11463 at
# the pin, swipl-devel 18168e62, 10.1.20) against swipl at the pin: `prolog_listen(PI, Closure)` on a tabled predicate, the listener
# called as `Closure(new_answer, M:Variant)` with the new answer unified into the variant, raised by `'$tbl_monotonic_add_answer'/2`
# (the one caller, pl-tabling.c:10468) through `table_answer_event` (pl-event.c:746). Groups: ev01 = the UPSTREAM test
# tests/tabling/test_mono_subsumptive.pl, unit mono_abstract, test `new_answer` (the only test of the event in the pin; names
# prefixed `up_`, the unit's setup/cleanup inline); ev02-ev13 = the same hook reached through `'$tbl_monotonic_add_answer'/2`
# directly on the answer trie of a COMPLETE monotonic table (`ev_tbl/2` creates it, `ev_add/3` adds one answer): a listener sees
# the answer once, a repeated answer sends nothing, no listener or an unlistened one sends nothing, two listeners run in
# `as(first)` / `as(last)` order, a failing listener is ignored, a raising one makes the predicate raise, a listener that calls a
# tabled predicate works also while a tabling evaluation is active (the tabling status is saved around the hook), the event of a
# ground variant. wb = LK-only white-box rows of `atrie_answer_event` (a trie without a variant or without a predicate sends nothing
# and answers true; the tabling status is back after the hook, also after a raising listener).
#   * Every pinned line is swipl's (swipl 10.1.20, two byte-identical runs, 2026-11-14: command and output in
#     evidence/TAB1/ev1_verify.md of the channel); with `swipl` on PATH the live answers are compared with the pins too.
#   * NOT ROWS (with the reason): the answer-subsumption branch of `'$tbl_monotonic_add_answer'/2` (an answer of a moded table raises
#     `domain_error(moded_answer, _)` on the pin for every shape tried by hand: the branch sends no event, but no row reaches it).
#   * ev01 needs the monotonic dependency on a dynamic predicate: `'$idg_add_mono_dyn_dep'/3` looks the head up with
#     `get_procedure_find` (the GP_FIND case; `get_procedure` itself refuses it, owner V9). The row still accepts the NotPortedError
#     of `get_procedure` or an `exc(..get_procedure..)` text, in case a branch carries the older lookup; the pin `[c]` is the answer.
#   * UNVERIFIED on the kernel (nothing was compiled when these rows were written): every kernel answer; the gate decides.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — these built-ins ride the term layer through the FLI (unify, get, the trie blobs, the event hook)
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TI = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_tis(x) = lk_sym(_TI, Symbol(x))

const _TI_PROGRAM = raw"""
:- table ev_b/1 as monotonic.
ev_b(X) :- ev_s(X).
ev_s(_) :- fail.
:- table ev_tq/1.
ev_tq(1).
ev_tq(2).
:- dynamic ev_log/1.
ev_on(A, G) :- assertz(ev_log(on(A, G))).
ev_on2(A, G) :- assertz(ev_log(on2(A, G))).
ev_fail(_, _) :- assertz(ev_log(fail)), fail.
ev_throw(_, _) :- assertz(ev_log(throw)), throw(ev_boom).
ev_tab(_, G) :- findall(X, ev_tq(X), L), assertz(ev_log(tab(G, L))).
ev_unl(PI) :- forall(member(P, [ev_on, ev_on2, ev_fail, ev_throw, ev_tab]), ignore(catch(prolog_unlisten(PI, P), _, true))).
ev_reset :- retractall(ev_log(_)), abolish_all_tables, ev_unl(ev_b/1).
ev_tbl(G, T) :- ignore(\+ G), '$tbl_variant_table'(0, user:G, T, _, _, _).
ev_add(T, A, R) :- catch(( '$tbl_monotonic_add_answer'(T, A) -> R = yes ; R = no ), B, R = raised(B)).
ev_log_list(L) :- findall(X, ev_log(X), L).
ev_ans(L) :- findall(X, ev_b(X), L0), sort(L0, L).
t_ev02(R) :- ev_reset, prolog_listen(ev_b/1, ev_on), ev_tbl(ev_b(_), T), ev_add(T, ret(c), A1), ev_log_list(L1), ev_ans(An), R = r(A1, L1, An).
t_ev03(R) :- ev_reset, prolog_listen(ev_b/1, ev_on), ev_tbl(ev_b(_), T), ev_add(T, ret(c), A1), ev_add(T, ret(c), A2), ev_add(T, ret(d), A3), ev_log_list(L), R = r(A1, A2, A3, L).
t_ev04(R) :- ev_reset, ev_tbl(ev_b(_), T), ev_add(T, ret(c), A1), ev_log_list(L1), prolog_listen(ev_b/1, ev_on), ev_add(T, ret(d), A2), ev_log_list(L2), ev_ans(An), R = r(A1, L1, A2, L2, An).
t_ev05(R) :- ev_reset, prolog_listen(ev_b/1, ev_on), prolog_unlisten(ev_b/1, ev_on), ev_tbl(ev_b(_), T), ev_add(T, ret(c), A1), ev_log_list(L1), R = r(A1, L1).
t_ev06(R) :- ev_reset, prolog_listen(ev_b/1, ev_on), prolog_listen(ev_b/1, ev_on2), ev_tbl(ev_b(_), T), ev_add(T, ret(c), A1), ev_log_list(L1),
    retractall(ev_log(_)), prolog_unlisten(ev_b/1, ev_on2), prolog_listen(ev_b/1, ev_on2, [as(last)]), ev_add(T, ret(d), A2), ev_log_list(L2), R = r(A1, L1, A2, L2).
t_ev07(R) :- ev_reset, prolog_listen(ev_b/1, ev_fail), ev_tbl(ev_b(_), T), ev_add(T, ret(c), A1), ev_log_list(L1), ev_ans(An), R = r(A1, L1, An).
t_ev08(R) :- ev_reset, prolog_listen(ev_b/1, ev_throw), ev_tbl(ev_b(_), T), ev_add(T, ret(c), A1), ev_log_list(L1), ev_ans(An), R = r(A1, L1, An).
t_ev09(R) :- ev_reset, prolog_listen(ev_b/1, ev_tab), ev_tbl(ev_b(_), T), ev_add(T, ret(c), A1), ev_log_list(L1), R = r(A1, L1).
t_ev10(R) :- ev_reset, prolog_listen(ev_b/1, ev_tab), findall(X, ev_in(X), L), ev_log_list(L1), R = r(L, L1).
:- table ev_in/1.
ev_in(R) :- ev_tbl(ev_b(_), T), ev_add(T, ret(c), R).
t_ev13(R) :- ev_reset, prolog_listen(ev_b/1, ev_on), ev_tbl(ev_b(c), T), ev_add(T, ret, A1), ev_log_list(L1), R = r(A1, L1).
ev_q(G, A) :- ( catch(call(G, R), E, R = exc(E)) -> true ; R = failed ), format(atom(A), "~q", [R]).
t_wb0(R) :- ev_reset, ev_tbl(ev_b(_), T), ev_add(T, ret(c), R).
t_wblog(R) :- ev_log_list(R).
t_wblisten(R) :- prolog_listen(ev_b/1, ev_on), R = ok.
"""

const _TI_UP_PROGRAM = raw"""
ev_q(G, A) :- ( catch(call(G, R), E, R = exc(E)) -> true ; R = failed ), format(atom(A), "~q", [R]).
% tests/tabling/test_mono_subsumptive.pl, unit mono_abstract, test new_answer (names prefixed up_, the unit's setup/cleanup inline)
:- dynamic up_e/1 as monotonic.
:- table up_a/1 as (subgoal_abstract(0), monotonic).
:- table up_b/1 as monotonic.
up_a(args(X)) :- up_e(X).
up_b(X) :- up_a(args(X)).
up_init :- abolish_all_tables, retractall(up_e(_)).
up_on_answer(new_answer, _:up_b(X)) :- nb_getval(mono_events, Events), append(Events, [X], Events1), nb_setval(mono_events, Events1).
t_ev01(R) :- current_prolog_flag(max_table_subgoal_size_action, Old), set_prolog_flag(max_table_subgoal_size_action, abstract),
    up_init, nb_setval(mono_events, []), prolog_listen(up_b/1, up_on_answer),
    \+ up_b(c), assertz(up_e(c)), nb_getval(mono_events, Events),
    prolog_unlisten(up_b/1, up_on_answer), up_init, set_prolog_flag(max_table_subgoal_size_action, Old), R = Events.
"""

const _TI_CASES = [
    "t_ev02", "t_ev03", "t_ev04", "t_ev05", "t_ev06", "t_ev07", "t_ev08", "t_ev09", "t_ev10", "t_ev13"
]

# swipl 10.1.20 (`ev_q(t_ev..., A)`, in the order of `_TI_CASES`), two identical runs (md5 equal), 2026-11-14
const _TI_PINNED = String[
    "r(yes,[on(new_answer,user:ev_b(c))],[c])",
    "r(yes,no,yes,[on(new_answer,user:ev_b(c)),on(new_answer,user:ev_b(d))])",
    "r(yes,[],yes,[on(new_answer,user:ev_b(d))],[c,d])",
    "r(yes,[])",
    "r(yes,[on2(new_answer,user:ev_b(c)),on(new_answer,user:ev_b(c))],yes,[on(new_answer,user:ev_b(d)),on2(new_answer,user:ev_b(d))])",
    "r(yes,[fail],[c])",
    "r(raised(ev_boom),[throw],[c])",
    "r(yes,[tab(user:ev_b(c),[1,2])])",
    "r([yes],[tab(user:ev_b(c),[1,2])])",
    "r(yes,[on(new_answer,user:ev_b(c))])"
]

# the pin of ev01 (the upstream test new_answer: `Events == [c]`)
const _TI_UP_PIN = "[c]"

"The `~q` text of each case's answer, in order, from swipl at the pin."
function _ti_swipl_lines(program::String, cases::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "ev1.pl")
        write(
            f,
            program * ":- initialization((forall(member(G, [" * join(cases, ",") *
            "]), (ev_q(G, A), write(A), nl)), halt)).\n"
        )
        read(pipeline(addenv(`swipl -q $f`, "LC_ALL" => "C"); stdin=devnull, stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

"The `~q` text of the answer of `case`, run as `ev_q(case, A)` in the kernel."
function _ti_ask(gd, ld, case::String)::String
    proc = LK.isCurrentProcedure(sym_key(_tis("ev_q")), 2, LK.MODULE_user(gd))
    (proc === nothing || !LK.isDefinedProcedure(gd, proc)) && return "ev_q undefined"
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

"A fresh database with `program` consulted: `(gd, ld, status)`."
function _ti_load(program::String)
    f = joinpath(mktempdir(), "tabling_events.pl")
    write(f, program)
    gd = LK.PL_global_data{_TI}()
    ld = LK.PL_local_data{_TI}(gd)
    st, _ = LK.load_file!(gd, ld, f)
    return gd, ld, st
end

@testset "the new-answer event of a tabled predicate as swipl's (ev02-ev13)" begin
    gd, ld, st = _ti_load(_TI_PROGRAM)
    @test st === :ok
    @test length(_TI_CASES) == length(_TI_PINNED) && !isempty(_TI_PINNED)       # both sides non-empty, one zip below
    for (case, pin) in zip(_TI_CASES, _TI_PINNED)
        @test _ti_ask(gd, ld, case) == pin
    end
    # the must-fail corruption rows: a pin with its event name or its answer changed is not what the kernel answers
    i02 = findfirst(==("t_ev02"), _TI_CASES)
    @test _ti_ask(gd, ld, "t_ev02") != replace(_TI_PINNED[i02], "new_answer" => "answer")
    @test _ti_ask(gd, ld, "t_ev02") != replace(_TI_PINNED[i02], "ev_b(c)" => "ev_b(_)")
    i07 = findfirst(==("t_ev07"), _TI_CASES)
    @test _ti_ask(gd, ld, "t_ev07") != replace(_TI_PINNED[i07], "r(yes" => "r(no")

    if Sys.which("swipl") !== nothing
        @test _ti_swipl_lines(_TI_PROGRAM, _TI_CASES) == _TI_PINNED
    end
end

# ev01: tests/tabling/test_mono_subsumptive.pl, unit mono_abstract, test `new_answer`: the pin `[c]`, or (a branch with the older
# lookup in `'$idg_add_mono_dyn_dep'/3`) the named refusal of `get_procedure`.
@testset "ev01: the upstream test mono_abstract/new_answer" begin
    gd, ld, st = _ti_load(_TI_UP_PROGRAM)
    @test st === :ok
    ans = try
        _ti_ask(gd, ld, "t_ev01")
    catch err
        err isa LK.NotPortedError ? "refused" : rethrow()
    end
    @test ans == _TI_UP_PIN || ans == "refused" || (startswith(ans, "exc(") && occursin("get_procedure", ans))
    @test !isempty(_TI_UP_PIN) && _TI_UP_PIN == "[c]"                           # both sides non-empty, the pin is the test's `[c]`
    @test ans != "[d]" && ans != "failed"                                       # must-fail row: a wrong or failing answer is neither
    if Sys.which("swipl") !== nothing
        @test _ti_swipl_lines(_TI_UP_PROGRAM, ["t_ev01"]) == [_TI_UP_PIN]
    end
end

# LK-only white-box rows of `atrie_answer_event`: the answer trie of `ev_b(_)` (the only trie with a predicate, a variant and a value)
# called directly, outside a query. A trie whose predicate has no listener, no variant or no predicate sends no event and answers
# true (pl-tabling.c:11443-11463: every branch that does not send falls out to `return true`).
@testset "atrie_answer_event sends nothing and answers true when it cannot (wb)" begin
    gd, ld, st = _ti_load(_TI_PROGRAM)
    @test st === :ok
    @test _ti_ask(gd, ld, "t_wb0") == "yes"                                     # complete table of ev_b(_) holding the answer c, no listener
    cands = [tr for tr in gd.tries if tr.predicate !== nothing && tr.variant != 0 && tr.value_count >= 1]
    @test length(cands) == 1
    tr = cands[1]
    nid = findfirst(i -> i > 1 && tr.nodes[i].value != 0, eachindex(tr.nodes))
    @test nid !== nothing
    @test tr.predicate.events === nothing                                       # the predicate has no listener
    @test LK.atrie_answer_event(ld, tr, nid) === true
    @test _ti_ask(gd, ld, "t_wblog") == "[]"

    @test _ti_ask(gd, ld, "t_wblisten") == "ok"
    @test tr.predicate.events !== nothing                                       # now it has one
    v0 = tr.variant
    tr.variant = 0                                                              # unify_skeleton fails: the event is silently dropped
    fid = LK.PL_open_foreign_frame(ld)
    r_novariant = LK.atrie_answer_event(ld, tr, nid)
    LK.PL_close_foreign_frame(ld, fid)
    tr.variant = v0
    @test r_novariant === true
    @test _ti_ask(gd, ld, "t_wblog") == "[]"                                    # no listener ran
    pred = tr.predicate
    tr.predicate = nothing                                                      # no predicate: nothing to tell
    r_nopred = LK.atrie_answer_event(ld, tr, nid)
    tr.predicate = pred
    @test r_nopred === true
    @test _ti_ask(gd, ld, "t_wblog") == "[]"
    @test _ti_ask(gd, ld, "t_wblog") != "[on(new_answer,user:ev_b(c))]"        # must-fail row: an event was not sent
end

@testset "the tabling status is back after the hook, also after a raising listener (wb)" begin
    gd, ld, st = _ti_load(_TI_PROGRAM)
    @test st === :ok
    tb = ld.tabling
    for case in ("t_ev02", "t_ev07", "t_ev08", "t_ev10")                         # a listener, a failing one, a raising one, inside an evaluation
        @test _ti_ask(gd, ld, case) != "ev_q undefined"
        @test tb.saved_status === nothing && tb.component === nothing &&
              !tb.has_scheduling_component && !tb.in_answer_completion
    end
    # must-fail row: the same observation when a status is saved and not restored is NOT this state
    s = LK.tbl_status{_TI}()
    LK.save_tabling_status(ld, s)
    @test !(tb.saved_status === nothing)
    LK.restore_tabling_status(ld, s)
    @test tb.saved_status === nothing
end
