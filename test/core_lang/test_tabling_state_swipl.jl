# ORIGINAL: TAB1 TB0's gate (evidence/TAB1/tb0_state.md §3 iv): the table state — pl-allocpool.c, the tabling flags (setMonotonicMode,
# table_space, table_compile_threshold, table_drop_intermediate), initTabling's restraint defaults, tbl_alloc/tbl_free — against swipl at the pin.
# test/core_lang/test_tabling_state_swipl.jl
#   * Rows `t_<id>(R)` of a program the kernel consults; the answers are PINNED lines, each swipl's own (10.1.20-1-g18168e629, the oracle
#     ~/.local/swipl-pin1-18168e62/bin/swipl, probed 2026-11-09), and with `swipl` on PATH they are compared live with the same program.
#   * White-box rows on what no predicate reaches (the pool's accounting, the free lists, the restraint defaults, the `TF_*` flag bits):
#     their values are upstream's code (pl-allocpool.c:41-93, pl-tabling.c:396-452, :12696-12706, :11471-11485), each cited at its row.
#   * Every kill row is an @test INSIDE a @testset (a failing top-level @test gives no verdict in CI mode).
# Mutants proposed for tools/mutants/TAB1*.py (a later step): restraint default -1 -> 0; `*_action` default error -> warning; compile
# threshold default 32 -> 31; `table_monotonic` lazy/eager swapped; TBL_FREE_MAX 16 -> 17; tbl_alloc not popping; alloc_from_pool `<=` -> `<`;
# the table_space flag not updating the limit of an existing pool; free_to_pool not subtracting.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — the state and the flag side (src/pl-global.jl, src/pl-tabling.jl, src/os/pl-prologflag.jl); every type in CI
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TS = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_tss(x) = lk_sym(_TS, Symbol(x))

"A ground answer as `write_term(T, [quoted(false)])` writes it: atoms and integers bare, `f(a,b)` without spaces."
function _ts_show(t::_TS)::String
    k = kind(t)
    k === SYM && return is_nil(t) ? "[]" : sym_text(t)
    k === GND && return string(lk_value(t))
    h = child(t, 1)
    return sym_text(h) * "(" * join([_ts_show(child(t, i)) for i in 2:nchildren(t)], ",") *
           ")"
end

const _TS_PROGRAM = raw"""
t_defaults(R) :- current_prolog_flag(table_space, A), current_prolog_flag(table_compile_threshold, B),
    current_prolog_flag(table_drop_intermediate, C), current_prolog_flag(table_monotonic, D), R = f(A,B,C,D).
t_used(R) :- statistics(table_space_used, R).
t_mono(R) :- set_prolog_flag(table_monotonic, lazy), current_prolog_flag(table_monotonic, A),
    set_prolog_flag(table_monotonic, eager), current_prolog_flag(table_monotonic, B), R = f(A,B).
t_mono_bad(R) :- catch(set_prolog_flag(table_monotonic, foo), error(E, _), true), current_prolog_flag(table_monotonic, A), R = f(E,A).
t_mono_type(R) :- catch(set_prolog_flag(table_monotonic, 1), error(E, _), true), R = E.
t_space_neg(R) :- catch(set_prolog_flag(table_space, -1), error(E, _), true), R = E.
t_thresh_neg(R) :- catch(set_prolog_flag(table_compile_threshold, -1), error(E, _), true), R = E.
t_drop_neg(R) :- catch(set_prolog_flag(table_drop_intermediate, -1), error(E, _), true), R = E.
t_space_type(R) :- catch(set_prolog_flag(table_space, a), error(E, _), true), R = E.
t_set(R) :- set_prolog_flag(table_space, 1000000), set_prolog_flag(table_compile_threshold, 5), set_prolog_flag(table_drop_intermediate, 7),
    current_prolog_flag(table_space, A), current_prolog_flag(table_compile_threshold, B), current_prolog_flag(table_drop_intermediate, C),
    R = f(A,B,C).
t_used_after(R) :- statistics(table_space_used, R).
t_thresh_after(R) :- catch(set_prolog_flag(table_compile_threshold, -1), error(_, _), true), current_prolog_flag(table_compile_threshold, R).
t_space_after(R) :- catch(set_prolog_flag(table_space, -1), error(_, _), true), current_prolog_flag(table_space, R).
t_drop_after(R) :- catch(set_prolog_flag(table_drop_intermediate, -1), error(_, _), true), current_prolog_flag(table_drop_intermediate, R).
t_zero(R) :- set_prolog_flag(table_space, 0), set_prolog_flag(table_drop_intermediate, 0),
    current_prolog_flag(table_space, A), current_prolog_flag(table_drop_intermediate, B), R = f(A,B).
"""
const _TS_ROWS = [
    ("t_defaults", "f(1073741824,32,0,eager)"),
    ("t_used", "0"),
    ("t_mono", "f(lazy,eager)"),
    ("t_mono_bad", "f(domain_error(table_monotonic,foo),eager)"),
    ("t_mono_type", "type_error(atom,1)"),
    ("t_space_neg", "representation_error(size_t)"),
    ("t_thresh_neg", "representation_error(size_t)"),
    ("t_drop_neg", "representation_error(size_t)"),
    ("t_space_type", "type_error(integer,a)"),
    # a failed set changes nothing (R8, TB0-G9: the setter returns false before it stores) and 0 is no size_t error (R7, TB0-G4, G8)
    ("t_thresh_after", "32"),
    ("t_space_after", "1073741824"),
    ("t_drop_after", "0"),
    ("t_zero", "f(0,0)"),
    ("t_set", "f(1000000,5,7)"),
    ("t_used_after", "0")
]

"The formal term of the pending exception as `_ts_show` writes it, or `none` (the exception is `error(Formal, Context)`: test_attvar_store.jl)."
function _ts_formal(ld)::String
    ld.exception_term == 0 && return "none"
    return _ts_show(child(lk_answer(ld, ld.exception_term), 2))
end

"The ten restraint fields of `r` in struct order, the actions as their atoms' text (upstream's `LD->tabling.restraint`, pl-global.h)."
_ts_restraint(r) = (
    sym_text(r.max_table_subgoal_size_action), r.max_table_subgoal_size,
    sym_text(r.max_table_answer_size_action), r.max_table_answer_size,
    sym_text(r.max_answers_for_subgoal_action), r.max_answers_for_subgoal,
    sym_text(r.max_incomplete_subgoals_action), r.max_incomplete_subgoals,
    sym_text(r.max_scc_subgoals_action), r.max_scc_subgoals
)
"initTabling's defaults (pl-tabling.c:12696-12706): `error` for each action, `(size_t)-1` for each size."
const _TS_RESTRAINT_DEFAULTS = (
    "error", -1, "error", -1, "error", -1, "error", -1, "error", -1
)

"Whether `f()` returns without throwing (a kill is then an @test inside the testset, not an exception out of it)."
function _ts_ok(f)::Bool
    try
        f()
        return true
    catch
        return false
    end
end

"Whether an exception is pending on `ld` (the check of test_attvar_words.jl `_aw_formal`: `exception_term` is 0 without one)."
_ts_pending(ld)::Bool = ld.exception_term != 0

"The kernel's one answer text of `name(R)`, or `exception` / `undefined`."
function _ts_query(gd, ld, name::String)::String
    proc = LK.isCurrentProcedure(sym_key(_tss(name)), 1, LK.MODULE_user(gd))
    (proc === nothing || !LK.isDefinedProcedure(gd, proc)) && return "undefined"
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 1)
    LK.putSlotValue!(ld, a + 1, mk_var(_TS, LK.fresh_var_keys!(1)), LK.PutVarMap())
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    out = "no"
    try
        rc = LK.PL_next_solution(gd, ld, qid)
        if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
            out = _ts_show(lk_answers(ld, (a:a)...)[1])
        elseif rc == LK.PL_S_EXCEPTION
            out = "exception"
        end
    catch e
        out = "threw " * string(nameof(typeof(e)))      # a failing @test of the caller, not an error escaping it (TB0-G1)
    finally
        LK.PL_close_query(ld, qid)
        LK.PL_close_foreign_frame(ld, fid)
    end
    return out
end

@testset "TB0: the tabling flags, pinned from swipl 10.1.20 and run in order in one database" begin
    path = joinpath(mktempdir(), "tabling_state.pl")
    write(path, _TS_PROGRAM)
    gd = LK.PL_global_data{_TS}()
    ld = LK.PL_local_data{_TS}(gd)
    st, _ = LK.load_file!(gd, ld, path)
    @test st === :ok
    for (name, want) in _TS_ROWS
        @test _ts_query(gd, ld, name) == want
    end
    # the flags reached the thread's state (white box: upstream's `LD->tabling.node_pool`, `LD->table_flags`)
    @test ld.table_flags_compile_threshold == 5
    @test ld.table_flags_drop_intermediate == 7
    @test ld.tabling.node_pool isa LK.alloc_pool
    @test ld.tabling.node_pool.limit == 1000000
    @test ld.tabling.node_pool.name == "private_table_space"      # pl-prologflag.c:1449
    @test (ld.tabling.flags & LK.TF_MONOTONIC_LAZY) == 0          # `eager` last
    # R10 (TB0-S3): `statistics(table_space_used)` is the pool's size (pl-prims.c:6260); nothing charges the pool until TR1, so charge it here
    pool = ld.tabling.node_pool
    @test LK.alloc_from_pool(ld, pool, 100) && pool.size == 100
    @test _ts_query(gd, ld, "t_used") == "100"
    LK.free_to_pool(pool, 100)
    @test _ts_query(gd, ld, "t_used") == "0"
    # the second `set_prolog_flag(table_space, N)` keeps the pool and moves its limit (pl-prologflag.c:1451)
    write(
        joinpath(dirname(path), "again.pl"),
        "t_again(R) :- set_prolog_flag(table_space, 42), R = ok.\n"
    )
    LK.load_file!(gd, ld, joinpath(dirname(path), "again.pl"))
    @test _ts_query(gd, ld, "t_again") == "ok"
    @test ld.tabling.node_pool === pool && pool.limit == 42

    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "TB0 LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        driver = joinpath(dirname(path), "driver.pl")
        # the form of test_tabling_min_swipl.jl (`_tm_swipl_lines`): ONE driver file that consults the program and runs the rows in order
        write(
            driver,
            "main :- consult('$path'), forall(member(N, [" *
            join([n for (n, _) in _TS_ROWS], ",") *
            "]), (call(N, R), write_term(R, [quoted(false)]), nl)).\n:- initialization((main, halt)).\n"
        )
        got = String.(
            split(
                chomp(
                    read(
                        pipeline(
                            addenv(`swipl -q $driver`, "LC_ALL" => "C");
                            stdin=devnull,
                            stderr=devnull
                        ),
                        String
                    )
                ), '\n'; keepempty=false
            )
        )
        @test got == [w for (_, w) in _TS_ROWS]
    end
end

@testset "TB0: the allocation pool (pl-allocpool.c)" begin
    gd = LK.PL_global_data{_TS}()
    ld = LK.PL_local_data{_TS}(gd)
    p = LK.new_alloc_pool("test_pool", 100)
    @test (p.size, p.limit, p.name, p.freed) == (0, 100, "test_pool", false)       # :41-47, memset 0 then limit and name
    @test LK.alloc_from_pool(ld, p, 60) && p.size == 60
    @test LK.alloc_from_pool(ld, p, 40) && p.size == 100                           # size+bytes <= limit: the limit itself fits (:75)
    @test !LK.alloc_from_pool(ld, p, 1) && p.size == 100                           # over: false, nothing charged (:79-80)
    @test _ts_pending(ld)                                              # resource_error(test_pool) is pending
    @test _ts_formal(ld) == "resource_error(test_pool)"                # R1 (TB0-P6): PL_resource_error(pool->name), pl-allocpool.c:79
    LK.PL_clear_exception(ld)
    LK.free_to_pool(p, 30)
    @test p.size == 70
    @test LK.alloc_from_pool(ld, p, 30) && p.size == 100
    @test LK.alloc_from_pool(ld, nothing, 10^9)                                    # NULL pool: nothing counted (:72)
    LK.free_to_pool(nothing, 10^9)
    @test_throws AssertionError LK.free_to_pool(p, p.size + 1)                     # R2 (TB0-P9): assert(bytes <= pool->size), pl-allocpool.c:88
    @test p.size == 100                                                            # the refused return took nothing
    LK.free_alloc_pool(p)
    @test p.freed
end

@testset "TB0: freed objects (tbl_alloc, tbl_free, free_tbl_free_objects)" begin
    gd = LK.PL_global_data{_TS}()
    ld = LK.PL_local_data{_TS}(gd)
    kind = Val(LK.TBL_FREE_CLUSTER)
    @test LK.tbl_alloc(ld, kind) === nothing                                       # none to reuse: the caller allocates
    cs = [LK.cluster{_TS}(LK.CLUSTER_ANSWERS) for _ in 1:(LK.TBL_FREE_MAX + 3)]
    for c in cs
        LK.tbl_free(ld, kind, c)
    end
    @test length(ld.tabling.free_objects.cluster) == LK.TBL_FREE_MAX == 16         # the first 16 kept, the rest dropped (:424-432)
    @test LK.tbl_alloc(ld, kind) === cs[16]                                        # the list is a stack: last freed, first reused (:410-420)
    @test length(ld.tabling.free_objects.cluster) == 15
    @test isempty(ld.tabling.free_objects.worklist)                                # the kinds are separate lists
    LK.tbl_free(ld, Val(LK.TBL_FREE_COMPONENT), LK.tbl_component{_TS}())
    @test length(ld.tabling.free_objects.component) == 1
    # R3 (TB0-F8, F11): the other two kinds have their own lists, and `free_tbl_free_objects` empties ALL FOUR
    fo = ld.tabling.free_objects
    w = LK.tbl_worklist{_TS}()
    ws = LK.worklist_set{LK.tbl_worklist{_TS}}()
    @test LK.tbl_alloc(ld, Val(LK.TBL_FREE_WORKLIST)) === nothing &&
        LK.tbl_alloc(ld, Val(LK.TBL_FREE_WORKLIST_SET)) === nothing
    @test _ts_ok(() -> LK.tbl_free(ld, Val(LK.TBL_FREE_WORKLIST), w))
    @test _ts_ok(() -> LK.tbl_free(ld, Val(LK.TBL_FREE_WORKLIST_SET), ws))
    @test (
        length(fo.component),
        length(fo.worklist_set),
        length(fo.worklist),
        length(fo.cluster)
    ) == (1, 1, 1, 15)
    @test LK.tbl_alloc(ld, Val(LK.TBL_FREE_WORKLIST)) === w &&
        LK.tbl_alloc(ld, Val(LK.TBL_FREE_WORKLIST_SET)) === ws
    @test _ts_ok(() -> LK.tbl_free(ld, Val(LK.TBL_FREE_WORKLIST), w))
    @test _ts_ok(() -> LK.tbl_free(ld, Val(LK.TBL_FREE_WORKLIST_SET), ws))
    LK.free_tbl_free_objects(ld, false)
    @test all(isempty, (fo.component, fo.worklist_set, fo.worklist, fo.cluster)) &&
        !fo.closed
    LK.tbl_free(ld, kind, cs[1])                                                   # not closed: kept again
    @test length(fo.cluster) == 1
    LK.free_tbl_free_objects(ld, true)                                             # :437-451: `closed` stops the keeping
    @test fo.closed && isempty(fo.cluster)
    LK.free_tbl_free_objects(ld, false)                                            # R4 (TB0-F9): upstream sets `closed` only when `closed`
    @test fo.closed
    LK.tbl_free(ld, kind, cs[1])
    @test isempty(ld.tabling.free_objects.cluster)
end

@testset "TB0: the thread's state at its defaults, initTabling!, setMonotonicMode" begin
    gd = LK.PL_global_data{_TS}()
    ld = LK.PL_local_data{_TS}(gd)
    t = ld.tabling
    @test t.component === nothing && t.saved_status === nothing && t.node_pool === nothing
    @test (t.incomplete_tables, t.active_components, t.variant_table) == (0, 0, 0)
    @test !t.has_scheduling_component && !t.in_answer_completion && !t.in_assert_propagation
    @test t.flags == 0 && t.delay_list == 0 && t.idg_current == 0
    @test ld.table_flags_compile_threshold == LK.TABLE_COMPILE_THRESHOLD == 32     # pl-prologflag.c:2587
    @test ld.table_flags_drop_intermediate == 0                                    # :2589
    r = t.restraint
    err = _tss(:error)
    @test sym_key(r.max_table_subgoal_size_action) == sym_key(err)
    @test sym_key(r.max_table_answer_size_action) == sym_key(err)
    @test sym_key(r.max_answers_for_subgoal_action) == sym_key(err)
    @test sym_key(r.max_incomplete_subgoals_action) == sym_key(err)
    @test sym_key(r.max_scc_subgoals_action) == sym_key(err)
    @test (r.max_table_subgoal_size, r.max_table_answer_size, r.max_answers_for_subgoal) ==
        (-1, -1, -1)
    @test (r.max_incomplete_subgoals, r.max_scc_subgoals) == (-1, -1)              # (size_t)-1: pl-tabling.c:12696-12706
    @test isempty(gd.tabling_answer_delay_infos)
    # R6 (TB0-I1 doc, I4): the constructor's own defaults (a fresh LD shows `initTabling!`'s, it runs last in `_bare_local_data`)
    r0 = LK.tbl_restraint{_TS}()
    @test _ts_restraint(r0) == _TS_RESTRAINT_DEFAULTS
    # initTabling! puts them back: R5 (TB0-I2) dirties ALL TEN fields first
    warn = _tss(:warning)
    r.max_table_subgoal_size_action = warn
    r.max_table_subgoal_size = 3
    r.max_table_answer_size_action = warn
    r.max_table_answer_size = 3
    r.max_answers_for_subgoal_action = warn
    r.max_answers_for_subgoal = 3
    r.max_incomplete_subgoals_action = warn
    r.max_incomplete_subgoals = 3
    r.max_scc_subgoals_action = warn
    r.max_scc_subgoals = 3
    t.in_assert_propagation = true
    LK.initTabling!(ld)
    @test _ts_restraint(r) == _TS_RESTRAINT_DEFAULTS
    @test !t.in_assert_propagation
    # setMonotonicMode (pl-tabling.c:11471): lazy sets and eager clears TF_MONOTONIC_LAZY; another atom is domain_error
    @test LK.setMonotonicMode(ld, _tss(:lazy)) && (t.flags & LK.TF_MONOTONIC_LAZY) != 0
    @test LK.setMonotonicMode(ld, _tss(:eager)) && (t.flags & LK.TF_MONOTONIC_LAZY) == 0
    t.flags |= UInt32(0x8)
    @test LK.setMonotonicMode(ld, _tss(:lazy)) &&
        t.flags == (UInt32(0x8) | LK.TF_MONOTONIC_LAZY)   # the other bits stay
    @test LK.setMonotonicMode(ld, _tss(:eager)) && t.flags == UInt32(0x8)
    @test !LK.setMonotonicMode(ld, _tss(:foo)) && _ts_pending(ld)
    LK.PL_clear_exception(ld)
    # the sentinels of pl-tabling.c:283-300
    @test LK.WL_IS_SPECIAL(LK.WL_GROUND) && LK.WL_IS_SPECIAL(LK.WL_DYNAMIC)
    @test LK.WL_IS_WORKLIST(2) && !LK.WL_IS_WORKLIST(0) && !LK.WL_IS_WORKLIST(LK.WL_GROUND)
    @test LK.DL_IS_DELAY_LIST(2) && !LK.DL_IS_DELAY_LIST(0) &&
        !LK.DL_IS_DELAY_LIST(LK.DL_UNDEFINED)
    @test (LK.WORKLIST_MAGIC, LK.COMPONENT_MAGIC, LK.DELAY_MAGIC) ==
        (0x67e9124e, 0x67e9124f, 0x67e9124d)
    @test (LK.SCC_ACTIVE, LK.SCC_MERGED, LK.SCC_COMPLETED) == (0, 1, 2)
    @test LK.tbl_component{_TS}().magic == LK.COMPONENT_MAGIC &&
        LK.tbl_worklist{_TS}().magic == LK.WORKLIST_MAGIC
    # R9 (TB0-C3, C5, K3, K4): the VALUES, upstream's literals (the PIN1-R1 pattern: every row above follows the constant, so a wrong value passes it)
    @test LK.TF_MONOTONIC_LAZY === UInt32(0x0001)                                  # pl-tabling.h:50
    @test (LK.CLUSTER_ANSWERS, LK.CLUSTER_SUSPENSIONS) == (0, 1)                   # pl-tabling.h:42-43
    @test (LK.SCC_NEG_NONE, LK.SCC_NEG_DELAY, LK.SCC_NEG_SIMPLIFY) == (0, 1, 2)    # pl-tabling.h:72-74
    @test (
        LK.TBL_FREE_COMPONENT,
        LK.TBL_FREE_WORKLIST_SET,
        LK.TBL_FREE_WORKLIST,
        LK.TBL_FREE_CLUSTER
    ) == (0, 1, 2, 3)   # pl-tabling.c:360-363
    @test (LK.TBL_FREE_KINDS, LK.TBL_FREE_MAX) == (4, 16)                          # pl-tabling.c:364-365
    @test (
        LK.WLFS_FREE_NONE,
        LK.WLFS_KEEP_COMPLETE,
        LK.WLFS_FREE_ALL,
        LK.WLFS_DISCARD_INCOMPLETE
    ) == (0x0000, 0x0001, 0x0002, 0x0004)   # pl-tabling.c:210-213
    @test (LK.CAND_UNDECIDED, LK.CAND_ALL, LK.CAND_KEYED) == (0, 1, 2)             # pl-tabling.c:161-163
    @test (LK.DV_DELETED, LK.DL_UNDEFINED) == (-1, 1)                              # pl-tabling.c:215-216 ((trie*)0x1, (delay_info*)0x1); DV_DELETED is -1: a table trie's serial is >= 1 (TB1)
    @test (LK.WL_GROUND, LK.WL_DYNAMIC) == (0x21, 0x41)                            # pl-tabling.c:207-208
    c = LK.tbl_component{_TS}()                                                    # new_component: memset 0, magic set (pl-tabling.c:285-292)
    @test (c.status, c.neg_status) == (LK.SCC_ACTIVE, LK.SCC_NEG_NONE) == (0, 0)
end

# ── Tier-1 ALLOCATION PINS (test_local_stack.jl's pattern: a warm call, then `@allocated(f(...)) == 0`; the kill row is the path that does allocate) ──
# The hot-path-free helpers of TB0: charging and returning pool bytes, and recycling a freed object. The wrappers are functions, so the call
# is compiled before it is measured (a top-level `@allocated` would count the global lookups).
_ts_charge!(ld, p) = (LK.alloc_from_pool(ld, p, 16); LK.free_to_pool(p, 16); nothing)
_ts_recycle!(ld, c) = (
    LK.tbl_free(ld, Val(LK.TBL_FREE_CLUSTER), c);
    LK.tbl_alloc(ld, Val(LK.TBL_FREE_CLUSTER)); nothing
)
_ts_overrun(ld, p) = LK.alloc_from_pool(ld, p, 1)

@testset "TB0: allocation pins (alloc_from_pool, free_to_pool, tbl_alloc, tbl_free)" begin
    gd = LK.PL_global_data{_TS}()
    ld = LK.PL_local_data{_TS}(gd)
    p = LK.new_alloc_pool("pin_pool", 1 << 20)
    @test _ts_ok(() -> _ts_charge!(ld, p))                              # warm (TB0-P8: a strict assertion throws here, a failing @test)
    na = try
        @allocated(_ts_charge!(ld, p))
    catch
        -1
    end
    @test na == 0                                                       # charge and return: two field updates
    @test p.size == 0                                                   # the pair is balanced
    c = LK.cluster{_TS}(LK.CLUSTER_ANSWERS)
    full = LK.new_alloc_pool("pin_full", 8)
    @test LK.alloc_from_pool(ld, full, 8) && full.size == 8             # the pool is now full: `_ts_overrun` fails
    # kill row: the path that does allocate (the first push onto an empty list grows its buffer; the over-limit path builds an error term)
    @test @allocated(LK.tbl_free(ld, Val(LK.TBL_FREE_CLUSTER), c)) > 0
    LK.tbl_alloc(ld, Val(LK.TBL_FREE_CLUSTER))                          # back to an empty list with its capacity kept
    _ts_recycle!(ld, c)                                                 # warm
    @test @allocated(_ts_recycle!(ld, c)) == 0                          # free then reuse: push! and pop! within the kept capacity
    @test isempty(ld.tabling.free_objects.cluster)
    _ts_overrun(ld, full)                                               # warm
    LK.PL_clear_exception(ld)
    @test @allocated(_ts_overrun(ld, full)) > 0
    LK.PL_clear_exception(ld)
end
