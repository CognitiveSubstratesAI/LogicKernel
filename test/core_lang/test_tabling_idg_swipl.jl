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
#   * The kernel rows t_idg01-t_idg07 need the stack: `start_tabling` (TB2/TB3), the variant tables (TB1) and, for idg01-idg04,
#     the `S_INCR_DYNAMIC` edge of a dynamic call (TB6c); on wip/tb6 alone they are expected to fail. idg05 reaches the
#     dynamic-call edge directly (`'$idg_add_dyncall'/1` under `'$idg_set_current'/1`), idg06/idg07 `'$tbl_reeval_wait'/2`.
#   * idg10-idg15 are LK-only WHITE-BOX rows (TB6d): the graph is built by hand (`idg_new`, `idg_add_child`) on tries made with
#     `trie_create`, so they need no start_tabling; they pin pl-idgset.c and pl-tabling.c at the pin (cited per row).
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
:- dynamic([ti_d2/1], [incremental(true)]).
ti_d(1).
ti_p(X) :- ti_d(X).
ti_tab(T) :- '$tbl_existing_variant_table'(0, user:ti_p(_), T, _, _).
ti_q(G, A) :- ( catch(call(G, R), E, R = exc(E)) -> true ; R = failed ), format(atom(A), "~q", [R]).
t_idg01(R) :- ti_p(_), ti_tab(T),
    findall(Dir-S, ('$idg_edge'(T, Dir, D), '$tbl_table_status'(D, S)), R0), '$idg_falsecount'(T, F), R = r(R0, F).
t_idg05(R) :- ti_tab(T), '$idg_set_current'(T), '$idg_add_dyncall'(ti_d2(_)), '$idg_reset_current',
    findall(S, ('$idg_edge'(T, dependent, D), '$tbl_table_status'(D, S)), L), '$idg_falsecount'(T, F), R = r(L, F).
t_idg02(R) :- ti_tab(T), assertz(ti_d(2)), '$idg_falsecount'(T, F), ( '$idg_forced'(T) -> Fo = yes ; Fo = no ), R = r(F, Fo).
t_idg03(R) :- ti_tab(T), catch(('$idg_edge'(T, bogus, _), R = ok), error(E, _), R = raised(E)).
t_idg04(R) :- ti_tab(T), findall(S, '$idg_false_edge'(T, _, S), R0), '$idg_thread_summary'(main, N, E), R = r(R0, N, E).
t_idg06(R) :- ti_tab(T), '$tbl_reeval_wait'(T, S0),
    findall(S, ('$idg_edge'(T, dependent, D), '$tbl_reeval_wait'(D, S)), L), R = r(S0, L).
t_idg07(R) :- ti_tab(T), '$idg_set_falsecount'(T, 0), '$tbl_reeval_wait'(T, S0), '$idg_falsecount'(T, F), R = r(S0, F).
t_idg08(R) :- '$tbl_variant_table'(0, user:ti_p(_), T, S, Sk, M), '$idg_falsecount'(T, F), '$is_answer_trie'(T, Ty),
    ( Sk = ret(_) -> Sko = ret1 ; Sko = Sk ), ( var(M) -> Mo = unbound ; Mo = M ), R = r(S, F, Ty, Sko, Mo).
t_idg09(R) :- ti_tab(T), '$idg_set_falsecount'(T, 2), '$tbl_variant_table'(0, user:ti_p(_), T2, S, _, _),
    '$idg_falsecount'(T2, F), R = r(S, F).
t_idg10(R) :- '$tbl_variant_table'(0, user:ti_p(_), T, S, _, _), '$idg_set_falsecount'(T, 0),
    '$tbl_variant_table'(0, user:ti_p(_), T2, S2, _, _), ( T == T2 -> Same = same ; Same = other ), R = r(S, S2, Same).
:- table ti_pa/1 as incremental.
:- dynamic([ti_da/1], [incremental(true)]).
ti_da(1).
ti_pa(X) :- ti_da(X).
t_idg13(R) :- '$set_predicate_attribute'(user:ti_da(_), abstract, 0), ti_pa(Y),
    '$get_predicate_attribute'(user:ti_da(_), abstract, V), R = r(Y, V).
:- table ti_v5/1 as incremental.
ti_v5(X) :- statistics(table_space_used, U), L is U+1, set_prolog_flag(table_space, L), ti_d(X).
t_idg11(R) :- ti_p(_), ti_tab(T),
    catch(('$idg_set_falsecount'(T, 4294967296), R0 = ok), error(E, _), R0 = raised(E)),
    '$idg_falsecount'(T, F0), '$idg_set_falsecount'(T, 4294967295), '$idg_falsecount'(T, F1),
    '$idg_set_falsecount'(T, 0), R = r(R0, F0, F1).
t_idg12(R) :- current_prolog_flag(table_space, Old), catch(ti_v5(_), error(E, _), true),
    set_prolog_flag(table_space, Old), ( var(E) -> R = none ; R = raised(E) ).
"""

const _TI_CASES = ["t_idg01", "t_idg05", "t_idg02", "t_idg03", "t_idg04", "t_idg06", "t_idg07", "t_idg08", "t_idg09", "t_idg10", "t_idg11", "t_idg12", "t_idg13"]

# swipl 10.1.20 (`ti_q(t_idg<NN>, A)`, in the order of `_TI_CASES`), two identical runs (md5 equal), 2026-11-10
const _TI_PINNED = [
    "r([dependent-(dynamic)],0)",
    "r([dynamic,dynamic],0)",              # idg05: `\$idg_add_dyncall(ti_d2(_))` under the current node adds a second dynamic child
    "r(1,no)",
    "raised(domain_error(idg_edge_dir,bogus))",
    "r([dynamic],3,2)",                     # idg04 after idg05: three nodes, two edges; only ti_d (invalidated) is a false edge
    "r(invalid,[dynamic,dynamic])",         # idg06: `\$tbl_reeval_wait` of the invalid ti_p table and of its two dynamic children
    "r(complete,0)",                        # idg07: `\$idg_set_falsecount(T, 0)` makes it complete again
    "r(complete,0,incremental,ret1,unbound)",   # idg08 (TB7M5): `\$tbl_variant_table` of the complete incremental table: status, falsecount, type
    "r(invalid,2)",                         # idg09 (TB7M5): falsecount 2: complete_or_invalid_status answers `invalid`
    "r(invalid,complete,same)",             # idg10 (TB7M5): falsecount back to 0: the same table is `complete` again
    "r(raised(representation_error(falsecount)),0,4294967295)",   # idg11 (DEFKILL2, TB6-P14): pl-tabling.c:9864 `fc > UINT_MAX`; UINT_MAX itself is stored
    "raised(resource_error(private_table_space))",                # idg12 (DEFKILL2, TB6-V5): the dyncall edge of a full pool: pl-vmi.c:3547-3548 THROW_EXCEPTION
    "r(1,0)",                              # idg13 (DEFKILL2, TB6-N19): an incremental dynamic predicate with abstract(0) under a tabled one; swipl writes no warning
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
    # DEFKILL2 (TB6-N19): swipl writes no "Only abstract(0)" warning for abstract(0) (pl-vmi.c:3534-3535); the collected messages hold none
    @test !any(m -> kind(m[2]) === SYM && occursin("Only abstract(0)", sym_text(m[2])), ld.messages)
    @test ld.tabling.idg_edge_states.live == 0          # every '$idg_edge'/'$idg_false_edge' state was given back

    if Sys.which("swipl") !== nothing
        @test _ti_swipl_lines() == _TI_PINNED
    end
end

# ── WHITE-BOX ROWS (TB6d): the graph built by hand, no start_tabling and no S_INCR_DYNAMIC ──────────────────────────────────
# The values are upstream's code, each row names its C function (pl-idgset.c, pl-tabling.c at 18168e62), "pinned from the C
# source"; the kernel answers are UNVERIFIED (nothing was compiled when these rows were written): the gate decides.
# An edge `idg_add_child(ld, parent, child, 0, 0)` puts `child` in `parent.dependent` and `parent` in `child.affected`.
const _TIN = LK.idg_node{_TI}

_ti_wb() = (gd = LK.PL_global_data{_TI}(); (gd, LK.PL_local_data{_TI}(gd)))

"A fresh complete answer trie with its IDG node (`idg_new`, the node attached as `idg_init_variant` does)."
function _ti_node(ld)
    tr = LK.trie_create(_TI)
    tr.flags |= LK.TRIE_COMPLETE
    n = LK.idg_new(ld, tr)::_TIN
    tr.IDG = n
    return tr, n
end

"The live entries of an edge set, in enumeration order (`idg_set_enum_init`, `idg_set_next`)."
function _ti_live(set)::Vector{_TIN}
    out = _TIN[]
    e = LK.idg_set_enum_init(set)
    while (p = LK.idg_set_next(e)) !== nothing
        push!(out, p)
    end
    return out
end

@testset "idg10: an edge set is a pointer, then a block of 4, 8, 16 (pl-idgset.c idg_set_add/delete)" begin
    gd, ld = _ti_wb()
    nodes = [_ti_node(ld)[2] for _ in 1:12]
    set = LK.idg_set{_TIN}()
    add(p) = LK.idg_set_add(ld, set, p, nothing, nothing)
    del(p) = LK.idg_set_delete(set, p, nothing, nothing)

    @test LK.idg_set_is_empty(set) && LK.idg_set_size(set) == 0 && LK.idg_set_sizeof(set) == 0
    @test add(nodes[1]) == 1 && set.single === nodes[1] && set.block === nothing      # one pointer, no block
    @test add(nodes[1]) == 0 && LK.idg_set_size(set) == 1                             # already in: not added
    @test add(nodes[2]) == 1 && set.single === nothing && set.block !== nothing       # new_block(4)
    @test set.block.capacity == 4 && set.block.index_bits == 0                        # pl-idgset.c:284
    @test LK.idg_set_size(set) == 2 && LK.idg_set_contains(set, nodes[1]) && !LK.idg_set_contains(set, nodes[3])
    @test LK.idg_set_sizeof(set) == 24 + 4 * 8                                        # sizeof_block(4, 0)
    @test del(nodes[1]) && !del(nodes[1]) && !del(nodes[3])
    @test LK.idg_set_size(set) == 1 && !LK.idg_set_contains(set, nodes[1])
    @test _ti_live(set) == [nodes[2]]
    @test add(nodes[1]) == 1 && _ti_live(set) == [nodes[1], nodes[2]]                 # a dead entry is revived IN PLACE
    @test add(nodes[1]) == 0

    @test add(nodes[3]) == 1 && add(nodes[4]) == 1 && set.block.capacity == 4
    @test add(nodes[5]) == 1 && set.block.capacity == 8                               # grow_block: capacity*2 (:245)
    @test LK.idg_set_sizeof(set) == 24 + 8 * 8 && set.block.index_bits == 0           # no index up to IDG_SET_LINEAR_MAX
    for i in 6:8
        @test add(nodes[i]) == 1
    end
    @test set.block.capacity == 8
    @test add(nodes[9]) == 1 && set.block.capacity == 16 && set.block.index_bits == 5 # 1<<bits >= capacity*2 (:121)
    @test LK.idg_set_sizeof(set) == 24 + 16 * 8 + 32 * 4
    for i in 10:12
        @test add(nodes[i]) == 1
    end
    @test LK.idg_set_size(set) == 12 && all(p -> LK.idg_set_contains(set, p), nodes)
    @test _ti_live(set) == nodes
    @test del(nodes[6]) && _ti_live(set) == nodes[[1:5; 7:12]] && LK.idg_set_size(set) == 11
    for p in nodes
        del(p)
    end
    @test set.block === nothing && LK.idg_set_is_empty(set) && !LK.idg_set_contains(set, nodes[1])   # all dead: the block goes

    # idg_set_clear: the function sees every live entry once, then the set is empty
    for i in 1:3
        add(nodes[i])
    end
    del(nodes[2])
    seen = _TIN[]
    LK.idg_set_clear(set, (p, ctx) -> push!(ctx, p), seen, nothing, nothing)
    @test seen == [nodes[1], nodes[3]] && LK.idg_set_is_empty(set)
end

@testset "idg11: the registry of a thread's IDG nodes (pl-idgset.c reg_block, idg_registry_add/delete/get)" begin
    gd, ld = _ti_wb()
    @test LK.reg_block(0) == (0, 0) && LK.reg_block(63) == (0, 63)                   # 1 << IDG_REG_BASE_BITS = 64 slots
    @test LK.reg_block(64) == (1, 0) && LK.reg_block(191) == (1, 127) && LK.reg_block(192) == (2, 0)
    @test LK.reg_block_size(0) == 64 && LK.reg_block_size(1) == 128

    t1, n1 = _ti_node(ld)
    t2, n2 = _ti_node(ld)
    reg = ld.tabling.idg_registry
    @test reg isa LK.idg_registry{_TIN} && n1.registry === reg && n2.registry === reg
    @test n1.registry_index == 0 && n2.registry_index == 1
    @test LK.idg_registry_get(reg, 0) === n1 && LK.idg_registry_get(reg, 1) === n2 && LK.idg_registry_get(reg, 2) === nothing
    @test LK.idg_registry_count(reg) == 2 && reg.references == 3                      # the thread and the two nodes
    @test LK.idg_registry_sizeof(reg) == 64 * 8

    LK.idg_registry_delete(reg, 0)
    @test LK.idg_registry_get(reg, 0) === nothing && reg.references == 2
    t3, n3 = _ti_node(ld)
    @test n3.registry_index == 0 && LK.idg_registry_get(reg, 0) === n3                # the free slot is reused first
    @test LK.idg_registry_count(reg) == 2                                              # (the high water did not move)
    for _ in 1:70
        _ti_node(ld)
    end
    @test LK.idg_registry_count(reg) == 72 && LK.idg_registry_sizeof(reg) == (64 + 128) * 8   # block 1 allocated on slot 64

    LK.idg_release_registry(ld)
    @test ld.tabling.idg_registry === nothing && reg.references == 72                  # the thread's reference is dropped
end

@testset "idg12: edges and their two halves (idg_add_child, idg_clean_dependent/affected, idg_reset)" begin
    gd, ld = _ti_wb()
    pt, p = _ti_node(ld)
    ct, c = _ti_node(ld)
    ct.worklist = LK.WL_DYNAMIC                                                       # the child is an incremental dynamic call
    @test LK.idg_add_child(ld, p, c, 0, 0)
    @test _ti_live(p.dependent) == [c] && _ti_live(c.affected) == [p]
    @test isempty(_ti_live(p.affected)) && isempty(_ti_live(c.dependent))
    @test LK.idg_add_child(ld, p, c, 0, 0) && LK.idg_set_size(p.dependent) == 1 && LK.idg_set_size(c.affected) == 1   # idempotent

    @test LK.idg_add_edge(ld, ct, pt) == 1                                            # trie-level: the same edge
    plain = LK.trie_create(_TI)
    @test LK.idg_add_edge(ld, plain, pt) == -1                                        # a table without an IDG node: -1

    p.falsecount = 3
    p.answer_count = 5
    p.new_answer = true
    p.reevaluating = true
    @test ld.tabling.dyn_orphan_events == 0
    LK.idg_reset(ld, p)                                                               # edges gone, reevaluation state reset
    @test isempty(_ti_live(p.dependent)) && isempty(_ti_live(c.affected))
    @test p.falsecount == 0 && p.answer_count == 0 && !p.new_answer && !p.reevaluating
    @test ld.tabling.dyn_orphan_events == 1                                           # idg_free_dependent: the dynamic child lost its last parent
end

@testset "idg13: falsecount propagation up the graph (idg_changed, idg_propagate_change, idg_changed_loop)" begin
    gd, ld = _ti_wb()
    dt, d = _ti_node(ld)
    dt.worklist = LK.WL_DYNAMIC
    p1t, p1 = _ti_node(ld)
    p2t, p2 = _ti_node(ld)
    @test LK.idg_add_child(ld, p1, d, 0, 0) && LK.idg_add_child(ld, p2, p1, 0, 0)     # p2 -> p1 -> d
    @test LK.idg_changed(ld, dt, LK.IDG_CHANGED_NODE)
    @test d.falsecount == 1 && p1.falsecount == 1 && p2.falsecount == 1
    @test d.stats_invalidated == 1 && p1.stats_invalidated == 1 && p2.stats_invalidated == 1
    @test LK.idg_changed(ld, dt, LK.IDG_CHANGED_NODE)                                  # already changed: nothing moves
    @test d.falsecount == 1 && p1.falsecount == 1 && p2.falsecount == 1 && d.stats_invalidated == 1

    # the lowering walk (flags 0): `idg_changed`'s rollback; d itself is not lowered here
    d.falsecount = 0
    @test LK.idg_propagate_change(ld, d, 0) === nothing
    @test p1.falsecount == 0 && p2.falsecount == 0

    # a diamond: p1 and p2 depend on d, p2 on p1, p3 on p1 and p2; a node counts every invalid edge into it, is pushed once
    p3t, p3 = _ti_node(ld)
    @test LK.idg_add_child(ld, p2, d, 0, 0) && LK.idg_add_child(ld, p3, p1, 0, 0) && LK.idg_add_child(ld, p3, p2, 0, 0)
    @test LK.idg_changed(ld, dt, LK.IDG_CHANGED_NODE)
    @test d.falsecount == 1 && p1.falsecount == 1 && p2.falsecount == 2 && p3.falsecount == 2   # p2 via d and p1, p3 via p1 and p2
    @test p3.stats_invalidated == 1                                                    # invalidated once (falsecount 0 -> 1), counted 2
    d.falsecount = 0
    LK.idg_propagate_change(ld, d, 0)
    @test p1.falsecount == 0 && p2.falsecount == 0 && p3.falsecount == 0

    # a reevaluating parent is skipped (`if n->reevaluating continue`)
    p1.reevaluating = true
    @test LK.idg_changed(ld, dt, LK.IDG_CHANGED_NODE)
    @test p1.falsecount == 0 && p3.falsecount == 1                                     # p3 still reached through p2
    @test LK.idg_need_invalidated(ld, d) && LK.idg_need_invalidated(ld, p1)

    # a dynamic node that affects nothing needs no invalidation, an ordinary node always does
    lt, l = _ti_node(ld)
    lt.worklist = LK.WL_DYNAMIC
    @test !LK.idg_need_invalidated(ld, l)
    @test LK.idg_changed(ld, lt, LK.IDG_CHANGED_NODE) && l.falsecount == 0
    ot, o = _ti_node(ld)
    @test LK.idg_need_invalidated(ld, o) && LK.idg_changed(ld, ot, LK.IDG_CHANGED_NODE) && o.falsecount == 1
    @test LK.idg_changed(ld, LK.trie_create(_TI), LK.IDG_CHANGED_NODE)                  # no IDG node: true, nothing to do
end

@testset "idg14: prepare_reeval, reeval_complete, reset_reevaluation (pl-tabling.c:11173-11430)" begin
    gd, ld = _ti_wb()
    # prepare_reeval: the node starts over, its children let go of it
    dt, d = _ti_node(ld)
    ct, c = _ti_node(ld)
    @test LK.idg_add_child(ld, d, c, 0, 0)
    d.falsecount = 2
    d.new_answer = true
    dt.flags |= LK.TRIE_DISCARDABLE
    @test LK.prepare_reeval(ld, dt)
    @test d.reevaluating && d.falsecount == 0 && !d.new_answer && d.answer_count == dt.value_count
    @test (dt.flags & LK.TRIE_DISCARDABLE) == 0
    @test isempty(_ti_live(d.dependent)) && isempty(_ti_live(c.affected))               # idg_clean_dependent
    @test !LK.tt_has_modified_dependencies(ld, dt)                                      # no transaction (TB9)

    # reeval_complete with the same (here: no) answers: `not changed` goes up, the parent is valid again
    pt, p = _ti_node(ld)
    @test LK.idg_add_child(ld, p, d, 0, 0)
    p.falsecount = 1
    LK.reeval_complete(ld, dt)
    @test p.falsecount == 0 && d.stats_reevaluated == 1
    @test d.reevaluating                                                                # wls_reeval_complete clears it, not this
    @test !d.force_reeval && !d.aborted

    # reeval_complete with a changed answer count: nothing is propagated, the compiled clause is dropped
    qt, q = _ti_node(ld)
    @test LK.idg_add_child(ld, q, d, 0, 0)
    q.falsecount = 1
    d.answer_count = 1                                                                  # the table had an answer, has none now
    d.force_reeval = true
    d.aborted = true
    LK.reeval_complete(ld, dt)
    @test q.falsecount == 1 && d.stats_reevaluated == 2
    @test !d.force_reeval && !d.aborted

    # a node that is not reevaluating is left alone
    d.reevaluating = false
    LK.reeval_complete(ld, dt)
    @test d.stats_reevaluated == 2

    # reset_reevaluation (an exception in the middle): the next call restarts it
    et, e = _ti_node(ld)
    e.reevaluating = true
    e.new_answer = true
    e.falsecount = 0
    et.flags &= ~LK.TRIE_COMPLETE
    LK.reset_reevaluation(ld, et)
    @test !e.reevaluating && e.aborted && !e.new_answer && e.falsecount == 1
    @test (et.flags & LK.TRIE_COMPLETE) != 0
end

@testset "idg15: idg_destroy leaves the registry and the graph (pl-tabling.c idg_destroy)" begin
    gd, ld = _ti_wb()
    pt, p = _ti_node(ld)
    ct, c = _ti_node(ld)
    @test LK.idg_add_child(ld, p, c, 0, 0)
    reg = ld.tabling.idg_registry
    refs = reg.references
    LK.idg_destroy(ld, c)
    @test isempty(_ti_live(p.dependent)) && isempty(_ti_live(c.affected))
    @test LK.idg_registry_get(reg, c.registry_index) === nothing && reg.references == refs - 1
    @test LK.idg_registry_get(reg, p.registry_index) === p
end

# ── TB7M5 white-box rows: the refusal sites lifted from the merged tree (pl-tabling.c at the pin, cited per row) ────────────
"The text of the status atom `complete_or_invalid_status` gives for `tr`: ONE extractor for both sides of every comparison."
_ti_status(ld, tr, create::Bool)::String = sym_text(LK.complete_or_invalid_status(ld, tr, create))

@testset "idg16: complete_or_invalid_status reads the IDG node (pl-tabling.c:4263-4285)" begin
    gd, ld = _ti_wb()
    plain = LK.trie_create(_TI)
    @test _ti_status(ld, plain, true) == "complete"                                     # no IDG node: complete
    tr, n = _ti_node(ld)
    @test _ti_status(ld, tr, true) == "complete"                                        # an incremental node, nothing wrong
    n.falsecount = 2
    @test _ti_status(ld, tr, true) == "invalid"                                         # falsecount > 0
    n.reevaluating = true
    @test _ti_status(ld, tr, true) == "invalid"                                         # falsecount is asked before reevaluating
    n.falsecount = 0
    @test _ti_status(ld, tr, true) == "fresh"                                           # reevaluating
    n.reevaluating = false

    # monotonic and not lazy: complete whatever the counters say, unless a reevaluation is forced
    n.monotonic = true
    n.falsecount = 3
    n.reevaluating = true
    @test _ti_status(ld, tr, true) == "complete"
    n.force_reeval = true
    @test _ti_status(ld, tr, true) == "invalid"

    # monotonic and lazy: complete only while the assert propagation runs and the call is not creating
    n.force_reeval = false
    n.lazy = true
    @test !ld.tabling.in_assert_propagation
    @test _ti_status(ld, tr, false) == "invalid"
    ld.tabling.in_assert_propagation = true
    @test _ti_status(ld, tr, false) == "complete"
    @test _ti_status(ld, tr, true) == "invalid"
    ld.tabling.in_assert_propagation = false

    # a must-fail corruption: flipping one input changes the answer, so the rows above can fail
    good = _ti_status(ld, tr, true)
    n.falsecount = 0
    n.reevaluating = false
    n.monotonic = false
    bad = _ti_status(ld, tr, true)
    @test !isempty(good) && !isempty(bad) && good != bad
end

"A database with this file's program loaded, and the definition of the incremental `ti_p/1`."
function _ti_db()
    f = joinpath(mktempdir(), "tabling_idg_wb.pl")
    write(f, _TI_PROGRAM)
    gd = LK.PL_global_data{_TI}()
    ld = LK.PL_local_data{_TI}(gd)
    st, _ = LK.load_file!(gd, ld, f)
    @assert st === :ok
    proc = LK.isCurrentProcedure(sym_key(_tis("ti_p")), 1, LK.MODULE_user(gd))
    @assert proc !== nothing
    return gd, ld, proc.definition
end

"The variant `user:ti_p(v)` (`ground`) or `user:ti_p(_)`."
function _ti_variant(ground::Bool, v::Int=1)
    arg = ground ? lk_gnd(_TI, v) : mk_var(_TI, LK.fresh_var_keys!(1))
    return mk_expr(_TI, _TI[_tis(":"), _tis("user"), mk_expr(_TI, _TI[_tis("ti_p"), arg])])
end

"The complete answer table of `ti_p(1)` (`ground`) or `ti_p(_)`, made as swipl's call of `ti_p/1` makes it, without an IDG node."
function _ti_table!(ld, def, ground::Bool, v::Int=1)
    fid = LK.PL_open_foreign_frame(ld)
    t = LK.PL_new_term_refs(ld, 2)
    LK.putSlotValue!(ld, t + 1, _ti_variant(ground, v), LK.PutVarMap())
    atrie = LK.get_answer_table(ld, def, t, t + 1, Int(LK.AT_CREATE))
    @assert atrie !== nothing
    atrie.flags |= LK.TRIE_COMPLETE
    LK.PL_close_foreign_frame(ld, fid)
    return atrie
end

"""
`tbl_variant_table(closure 0, user:ti_p(_) or ti_p(1), -Trie, 0, -Status, -Ret, [-IsMono])` of the kernel as `'\$tbl_variant_table'/6` calls it;
`(succeeded, status text, text of IsMono: `unbound` or its atom)`. One extractor for every row below.
"""
function _ti_tvt(ld, def; ground::Bool=false, v::Int=1, mono::Bool=false)
    fid = LK.PL_open_foreign_frame(ld)
    t = LK.PL_new_term_refs(ld, 6)
    LK.putSlotValue!(ld, t + 1, lk_gnd(_TI, 0), LK.PutVarMap())                       # closure 0: no closure, the variant names the predicate
    LK.putSlotValue!(ld, t + 2, _ti_variant(ground, v), LK.PutVarMap())
    for i in 3:6
        LK.putSlotValue!(ld, t + i, mk_var(_TI, LK.fresh_var_keys!(1)), LK.PutVarMap())
    end
    ok = LK.tbl_variant_table(ld, t, t + 1, t + 2, 0, t + 3, t + 4, mono ? t + 5 : 0, Int(LK.AT_CREATE))
    st = "failed"
    mo = "unbound"
    if ok
        s = lk_answers(ld, (t + 4:t + 4)...)[1]
        st = kind(s) === SYM ? sym_text(s) : "not an atom"
        m = lk_answers(ld, (t + 6:t + 6)...)[1]
        mo = kind(m) === SYM ? sym_text(m) : "unbound"
    end
    LK.PL_close_foreign_frame(ld, fid)
    return ok, st, mo
end

@testset "idg17: tbl_variant_table adds the edge from the current node to the table (idg_add_edge, pl-tabling.c:5977-6020)" begin
    gd, ld, def = _ti_db()
    atrie = _ti_table!(ld, def, false)
    ctab = _ti_table!(ld, def, true)
    @test atrie.IDG === nothing && ctab.IDG === nothing
    n = LK.idg_new(ld, atrie)::_TIN
    atrie.IDG = n                                                                        # the table has its node already
    c = LK.idg_new(ld, ctab)::_TIN
    ctab.IDG = c

    # no current node: idg_add_edge answers -1, which is not a failure: the call goes on, no edge
    ok, st, _ = _ti_tvt(ld, def)
    @test ok && st == "complete"
    @test isempty(_ti_live(c.dependent)) && isempty(_ti_live(n.affected))

    # with the current node: the edge current -> table (`c.dependent` holds `n`, `n.affected` holds `c`)
    @test LK.set_idg_current(ld, ctab)
    ok, st, _ = _ti_tvt(ld, def)
    @test ok && st == "complete"
    @test _ti_live(c.dependent) == [n] && _ti_live(n.affected) == [c]
    ok, st, _ = _ti_tvt(ld, def)                                                         # again: the same edge, idempotent
    @test ok && _ti_live(c.dependent) == [n] && LK.idg_set_size(c.dependent) == 1

    # a must-fail corruption: an invalidated node answers `invalid`, so the status extractor distinguishes
    n.falsecount = 1
    ok, bad, _ = _ti_tvt(ld, def)
    @test ok && !isempty(bad) && bad == "invalid" && bad != st
end

@testset "idg18: tbl_variant_table gives the table of an incremental or monotonic predicate its IDG node (idg_init_variant, pl-tabling.c:8295-8325)" begin
    gd, ld, def = _ti_db()
    tp = def.tabling::LK.table_props
    @test (tp.flags & LK.TP_INCREMENTAL) != 0 && (tp.flags & LK.TP_MONOTONIC) == 0

    # an incremental predicate: the node is made, not monotonic, not lazy
    atrie = _ti_table!(ld, def, false)
    @test atrie.IDG === nothing
    ok, st, _ = _ti_tvt(ld, def)
    @test ok && st == "complete"
    n = atrie.IDG
    @test n isa _TIN && gd.tries[n.atrie] === atrie
    @test !n.monotonic && !n.lazy
    ok, st, _ = _ti_tvt(ld, def)                                                         # the second call keeps the node
    @test ok && atrie.IDG === n

    # a lazy monotonic predicate: the node says so
    saved = tp.flags
    tp.flags = saved | LK.TP_MONOTONIC | LK.TP_LAZY
    mtab = _ti_table!(ld, def, true, 2)
    ok, st, _ = _ti_tvt(ld, def; ground=true, v=2)
    @test ok && st == "complete"
    @test mtab.IDG isa _TIN && mtab.IDG.monotonic && mtab.IDG.lazy

    # neither: the table keeps no node
    tp.flags = saved & ~(LK.TP_INCREMENTAL | LK.TP_MONOTONIC | LK.TP_LAZY)
    ptab = _ti_table!(ld, def, true, 3)
    ok, st, _ = _ti_tvt(ld, def; ground=true, v=3)
    @test ok && st == "complete" && ptab.IDG === nothing
    tp.flags = saved

    # a must-fail corruption: the two kinds of table differ in the one extractor (has a node or not)
    has(t) = t.IDG === nothing ? "plain" : "node"
    @test has(atrie) == "node" && has(ptab) == "plain" && has(atrie) != has(ptab)
end

@testset "idg19: tbl_variant_table unifies IsMono for a monotonic predicate under propagation or an inner monotonic table (inner_is_monotonic, pl-tabling.c:5977-6020, :10503-10515)" begin
    gd, ld, def = _ti_db()
    tp = def.tabling::LK.table_props
    saved = tp.flags
    atrie = _ti_table!(ld, def, false)
    ctab = _ti_table!(ld, def, true)
    ctab.predicate = def                                                                 # `dep->data.predicate`: the table that is being evaluated
    c = LK.idg_new(ld, ctab)::_TIN
    ctab.IDG = c

    # not a monotonic predicate: IsMono stays unbound whatever the state
    ld.tabling.in_assert_propagation = true
    ok, st, mo = _ti_tvt(ld, def; mono=true)
    @test ok && st == "complete" && mo == "unbound"
    ld.tabling.in_assert_propagation = false

    tp.flags = saved | LK.TP_MONOTONIC
    # a monotonic predicate, outside propagation and no inner monotonic table (no scheduling component): unbound (swipl: mono09)
    ok, st, mo = _ti_tvt(ld, def; mono=true)
    @test ok && st == "complete" && mo == "unbound"
    @test !LK.inner_is_monotonic(ld)
    # no IsMono term asked (0): never unified
    ld.tabling.in_assert_propagation = true
    ok, st, mo = _ti_tvt(ld, def)
    @test ok && mo == "unbound"
    # assert propagation running: IsMono is true
    ok, st, mo = _ti_tvt(ld, def; mono=true)
    @test ok && st == "complete" && mo == "true"
    ld.tabling.in_assert_propagation = false

    # the inner tabled predicate (the current IDG node's table) is monotonic: IsMono is true
    ld.tabling.has_scheduling_component = true
    @test LK.set_idg_current(ld, ctab)
    @test LK.inner_is_monotonic(ld)
    ok, st, mo = _ti_tvt(ld, def; mono=true)
    @test ok && st == "complete" && mo == "true"
    ld.tabling.has_scheduling_component = false
    @test !LK.inner_is_monotonic(ld)
    ok, st, mo = _ti_tvt(ld, def; mono=true)
    @test ok && mo == "unbound"                                                           # a must-fail corruption: the same call, one flag less
    tp.flags = saved
end

"A symbol or a compound of symbols (`monotonic(eager)`) as text: ONE extractor for the types of `'\$is_answer_trie'`."
_ti_txt(t)::String = kind(t) === SYM ? sym_text(t) :
    sym_text(child(t, 1)) * "(" * join([_ti_txt(child(t, i)) for i in 2:nchildren(t)], ",") * ")"

"The `Type` of `'\$is_answer_trie'(Trie, Type)` for `atrie` (`failed` when it fails)."
function _ti_answer_trie_type(gd, ld, atrie)::String
    ctx = LK.foreign_context{_TI}(LK.FRG_FIRST_CALL, UInt(0), nothing)
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 2)
    LK.putSlotValue!(ld, a + 1, mk_var(_TI, LK.fresh_var_keys!(1)), LK.PutVarMap())
    LK.putSlotValue!(ld, a + 2, mk_var(_TI, LK.fresh_var_keys!(1)), LK.PutVarMap())
    @assert LK.unify_trie(gd, ld, a, atrie)
    rc = LK.pl_is_answer_trie2_va(ld, a, 2, ctx)
    out = rc == LK.FTRUE ? _ti_txt(lk_answers(ld, (a + 2:a + 2)...)[1]) : "failed"
    LK.PL_close_foreign_frame(ld, fid)
    return out
end

@testset "idg20: '\$is_answer_trie' names the type of a table with an IDG node (pl-tabling.c:7372-7392)" begin
    gd, ld, def = _ti_db()
    tabs = [_ti_table!(ld, def, true, v) for v in 1:5]
    typ(t) = _ti_answer_trie_type(gd, ld, t)
    @test typ(tabs[1]) == "normal"                                                        # no node, no worklist sentinel
    tabs[2].worklist = LK.WL_DYNAMIC
    @test typ(tabs[2]) == "dynamic"
    tabs[2].IDG = LK.idg_new(ld, tabs[2])::_TIN
    @test typ(tabs[2]) == "dynamic"                                                       # dynamic comes before the node
    tabs[3].IDG = LK.idg_new(ld, tabs[3])::_TIN
    @test typ(tabs[3]) == "incremental"                                                   # a node, not monotonic
    n4 = LK.idg_new(ld, tabs[4])::_TIN
    n4.monotonic = true
    tabs[4].IDG = n4
    @test typ(tabs[4]) == "monotonic(eager)"
    n5 = LK.idg_new(ld, tabs[5])::_TIN
    n5.monotonic = true
    n5.lazy = true
    tabs[5].IDG = n5
    @test typ(tabs[5]) == "monotonic(lazy)"
    # `lazy` without `monotonic` does not make the table monotonic (the C tests `n->monotonic` first)
    n5.monotonic = false
    @test typ(tabs[5]) == "incremental"

    # a must-fail corruption: the states differ, so the answers do (non-empty, one extractor): normal, dynamic, incremental (tables 3 and 5), monotonic(eager)
    texts = [typ(t) for t in tabs]
    @test all(!isempty, texts) && length(unique(texts)) == 4
end

"""
`call_complete_table(ld, atrie, def, clref)` of the kernel: `(the result: `clref` or `other`, the change of gen_call, `plain` or `node`)`.
ONE extractor for every row of idg21.
"""
function _ti_call_complete(ld, atrie, def, clref)
    g0 = atrie.gen_call
    r = LK.call_complete_table(ld, atrie, def, clref)
    return (r == clref ? "clref" : "other", atrie.gen_call - g0, atrie.IDG === nothing ? "plain" : "node")
end

@testset "idg21: call_complete_table registers the call of a complete table (idg_init_variant, idg_add_edge, pl-tabling.c:12328-12360)" begin
    gd, ld, def = _ti_db()
    tp = def.tabling::LK.table_props
    saved = tp.flags
    clref = LK.word(4242)
    a = _ti_table!(ld, def, false)
    @test _ti_call_complete(ld, a, def, clref) == ("clref", 1, "node")                   # an incremental predicate: the table gets its node; no current node (-1) is no failure
    n = a.IDG::_TIN
    @test _ti_call_complete(ld, a, def, clref) == ("clref", 1, "node") && a.IDG === n    # the second call keeps the node

    # with a current node: the edge current -> table
    ctab = _ti_table!(ld, def, true)
    c = LK.idg_new(ld, ctab)::_TIN
    ctab.IDG = c
    @test LK.set_idg_current(ld, ctab)
    b = _ti_table!(ld, def, true, 2)
    @test _ti_call_complete(ld, b, def, clref) == ("clref", 1, "node")
    @test _ti_live(c.dependent) == [b.IDG] && _ti_live(b.IDG.affected) == [c]

    # a predicate that is neither incremental nor monotonic: no node, the call is counted
    tp.flags = saved & ~(LK.TP_INCREMENTAL | LK.TP_MONOTONIC | LK.TP_LAZY)
    p = _ti_table!(ld, def, true, 3)
    @test _ti_call_complete(ld, p, def, clref) == ("clref", 1, "plain")
    tp.flags = saved

    # a must-fail corruption: the plain and the incremental table differ in the one extractor
    @test _ti_call_complete(ld, p, def, clref) != _ti_call_complete(ld, b, def, clref)
end

"""
`tbl_complete_answer_clause(ld, def, 0)` of the kernel, for a state where only the monotonic branch can answer: `zero` (the call must shift/1
the dependency: word 0), `other` (another word) or `proceeds` (the branch was passed: the frame 0 does not exist here, so the lookup throws).
ONE extractor for every row of idg22.
"""
function _ti_tcac(ld, def)::String
    try
        r = LK.tbl_complete_answer_clause(ld, def, 0)
        return r == LK.word(0) ? "zero" : "other"
    catch
        return "proceeds"
    end
end

@testset "idg22: tbl_complete_answer_clause leaves a monotonic call to start_tabling under propagation or an inner monotonic table (inner_is_monotonic, pl-tabling.c:12522-12565)" begin
    gd, ld, def = _ti_db()
    tp = def.tabling::LK.table_props
    saved = tp.flags
    ctab = _ti_table!(ld, def, true)
    ctab.predicate = def
    c = LK.idg_new(ld, ctab)::_TIN
    ctab.IDG = c

    # not a monotonic predicate: the branch is not taken whatever the state
    ld.tabling.in_assert_propagation = true
    @test _ti_tcac(ld, def) == "proceeds"
    ld.tabling.in_assert_propagation = false

    tp.flags = saved | LK.TP_MONOTONIC
    @test _ti_tcac(ld, def) == "proceeds"                                                # monotonic, no propagation, no inner monotonic table
    ld.tabling.in_assert_propagation = true
    @test _ti_tcac(ld, def) == "zero"                                                    # the assert propagation runs
    ld.tabling.in_assert_propagation = false

    # the inner tabled predicate (the current IDG node's table) is monotonic
    ld.tabling.has_scheduling_component = true
    @test LK.set_idg_current(ld, ctab)
    @test LK.inner_is_monotonic(ld)
    @test _ti_tcac(ld, def) == "zero"
    ld.tabling.has_scheduling_component = false

    # a must-fail corruption: the same call, one flag less, answers differently (non-empty, one extractor)
    bad = _ti_tcac(ld, def)
    ld.tabling.has_scheduling_component = true
    good = _ti_tcac(ld, def)
    ld.tabling.has_scheduling_component = false
    @test !isempty(good) && !isempty(bad) && good == "zero" && bad == "proceeds" && good != bad
    tp.flags = saved
end

"""
`update_delay_list_any(ld, wl, answer, skel, delays)` of the kernel for an empty delay list (the global one is empty too): `(the UDL_ status,
the number of entries left in wl.delays)`. The entry (the dependent table, node 1) is dropped only when `simplify_answer` ran (`propagate_result`:
the dependent answer has no delay info, so `delete_answer` removes it). ONE extractor for every row of idg23.
"""
function _ti_udl(ld, wl, answer::Int)
    fid = LK.PL_open_foreign_frame(ld)
    skel = LK.PL_new_term_ref(ld)
    delays = LK.PL_new_term_ref(ld)
    LK.PL_put_nil(ld, delays)
    rc = LK.update_delay_list_any(ld, wl, answer, skel, delays)
    LK.PL_close_foreign_frame(ld, fid)
    return rc, length(wl.delays)
end

@testset "idg23: update_delay_list_any simplifies a re-derived unconditional answer while the table reevaluates (pl-tabling.c:1364-1370)" begin
    gd, ld, def = _ti_db()
    t1 = _ti_table!(ld, def, true, 1)                                                      # the table of the worklist
    t2 = _ti_table!(ld, def, true, 2)                                                      # a table with an answer that waits on `t1`
    n = LK.idg_new(ld, t1)::_TIN
    t1.IDG = n
    mkwl(ground::Bool) = (wl = LK.tbl_worklist{_TI}(); wl.table = t1.serial; wl.ground = ground;
        push!(wl.delays, LK.delay(t2.serial, 1)); wl)               # node 1: the root, only its flags are read

    # not reevaluating: the nil/nil branch only answers
    @test _ti_udl(ld, mkwl(false), 1) == (LK.UDL_TRUE, 1)
    @test _ti_udl(ld, mkwl(true), 1) == (LK.UDL_COMPLETE, 1)                               # early completion of a ground call

    # reevaluating and the answer not marked TN_IDG_UNCONDITIONAL: the answer is simplified (true)
    n.reevaluating = true
    @test _ti_udl(ld, mkwl(false), 1) == (LK.UDL_TRUE, 0)
    @test _ti_udl(ld, mkwl(true), 1) == (LK.UDL_COMPLETE, 0)

    # reevaluating, the answer already unconditional in the previous evaluation: left alone
    t1.nodes[1].flags |= LK.TN_IDG_UNCONDITIONAL
    @test _ti_udl(ld, mkwl(false), 1) == (LK.UDL_TRUE, 1)
    t1.nodes[1].flags &= ~LK.TN_IDG_UNCONDITIONAL

    # a must-fail corruption: the same call with one input changed answers differently (non-empty, one extractor)
    good = _ti_udl(ld, mkwl(false), 1)
    n.reevaluating = false
    bad = _ti_udl(ld, mkwl(false), 1)
    @test good[2] != bad[2] && good[2] == 0 && bad[2] == 1
end

@testset "idg24: table_has_no_answers looks for a live answer only while the table reevaluates (pl-tabling.c:2065-2093)" begin
    gd, ld, def = _ti_db()
    t = _ti_table!(ld, def, true, 1)
    has_none() = LK.table_has_no_answers(t)
    @test has_none()                                                                       # value_count == 0
    n = LK.idg_new(ld, t)::_TIN
    t.IDG = n
    t.value_count = 1
    @test !has_none()                                                                      # a node, not reevaluating: the count decides
    n.reevaluating = true
    @test has_none()                                                                       # reevaluating, no node has a value
    t.nodes[1].value = LK.word(7)
    @test !has_none()                                                                      # a live answer
    t.nodes[1].flags |= LK.TN_IDG_DELETED
    @test has_none()                                                                       # the answer of the previous evaluation does not count
    t.nodes[1].flags &= ~LK.TN_IDG_DELETED
    n.reevaluating = false
    t.nodes[1].value = LK.word(0)
    @test !has_none()                                                                      # a node, not reevaluating, no live node: still the count

    # a must-fail corruption: two states of the one table answer differently (one extractor)
    r1 = has_none()
    n.reevaluating = true
    r2 = has_none()
    @test r1 != r2 && !r1 && r2
end

# ── TB7M6 rows owed from TB7M4: the IDG branches of free_worklist_set, wls_reeval_complete, answer_nodes_discardable ──────────
"A worklist for `atrie` (its table, pointed at by the table), alone in a set."
function _ti_wl_set(atrie)
    wl = LK.tbl_worklist{_TI}()
    wl.table = atrie.serial
    atrie.worklist = wl
    wls = LK.worklist_set{LK.tbl_worklist{_TI}}()
    push!(wls.members, wl)
    return wl, wls
end

"`free_worklist_set(ld, wls, freewl)` on one table: `(worklist freed, table points at none, node reevaluating, node aborted, table complete)`. ONE extractor for idg25."
function _ti_fws(ld, atrie, n, freewl::Int)
    wl, wls = _ti_wl_set(atrie)
    LK.free_worklist_set(ld, wls, freewl)
    return (wl.magic == 0, atrie.worklist === nothing, n.reevaluating, n.aborted, (atrie.flags & LK.TRIE_COMPLETE) != 0)
end

@testset "idg25: free_worklist_set resets a reevaluating table instead of destroying it (pl-tabling.c:924-955)" begin
    gd, ld, def = _ti_db()
    mk(v) = (t = _ti_table!(ld, def, true, v); n = LK.idg_new(ld, t)::_TIN; t.IDG = n; (t, n))

    # an incomplete table whose node reevaluates: the worklist is freed and the reevaluation reset (the table is complete again, the next call restarts)
    t1, n1 = mk(1)
    t1.flags &= ~LK.TRIE_COMPLETE
    n1.reevaluating = true
    @test _ti_fws(ld, t1, n1, LK.WLFS_DISCARD_INCOMPLETE) == (true, true, false, true, true)

    # a complete table: only its worklist is freed, the node is not touched
    t2, n2 = mk(2)
    n2.reevaluating = true
    @test _ti_fws(ld, t2, n2, LK.WLFS_DISCARD_INCOMPLETE) == (true, true, true, false, true)

    # freewl == 0 frees nothing
    t3, n3 = mk(3)
    t3.flags &= ~LK.TRIE_COMPLETE
    n3.reevaluating = true
    @test _ti_fws(ld, t3, n3, LK.WLFS_FREE_NONE) == (false, false, true, false, false)

    # a must-fail corruption: the three states answer differently (non-empty, one extractor)
    t4, n4 = mk(4)
    t4.flags &= ~LK.TRIE_COMPLETE
    n4.reevaluating = true
    a = _ti_fws(ld, t4, n4, LK.WLFS_DISCARD_INCOMPLETE)
    t5, n5 = mk(5)
    t5.flags &= ~LK.TRIE_COMPLETE
    n5.reevaluating = true
    b = _ti_fws(ld, t5, n5, LK.WLFS_FREE_NONE)
    @test !isempty(a) && !isempty(b) && a != b
end

@testset "idg26: wls_reeval_complete finishes the reevaluating tables, then clears every node (pl-tabling.c:6226-6255)" begin
    gd, ld, def = _ti_db()
    ta = _ti_table!(ld, def, true, 1)
    na = LK.idg_new(ld, ta)::_TIN
    ta.IDG = na
    tb = _ti_table!(ld, def, true, 2)
    nb = LK.idg_new(ld, tb)::_TIN
    tb.IDG = nb
    tc = _ti_table!(ld, def, true, 3)                                                      # no IDG node
    wla, _ = _ti_wl_set(ta)
    wlb, _ = _ti_wl_set(tb)
    wlc, _ = _ti_wl_set(tc)
    state() = (na.reevaluating, na.stats_reevaluated, nb.reevaluating, nb.stats_reevaluated)

    # nothing reevaluates: nothing happens
    LK.wls_reeval_complete(ld, [wla, wlb, wlc])
    @test state() == (false, 0, false, 0)

    # A reevaluates: reeval_complete runs for A only, then the flag goes
    na.reevaluating = true
    LK.wls_reeval_complete(ld, [wla, wlb, wlc])
    @test state() == (false, 1, false, 0)

    # the flag is cleared by the second loop, not by reeval_complete (idg14): a state where A is the only one and B is reevaluating too
    na.reevaluating = true
    nb.reevaluating = true
    LK.wls_reeval_complete(ld, [wla, wlb])
    @test state() == (false, 2, false, 1)

    # a must-fail corruption: the states before and after differ
    na.reevaluating = true
    before = state()
    LK.wls_reeval_complete(ld, [wla, wlb])
    @test !isempty(before) && state() != before && before[1] && !state()[1]
end

@testset "idg27: answer_nodes_discardable asks the IDG node (pl-tabling.c:3983-3995)" begin
    gd, ld, def = _ti_db()
    tp = def.tabling::LK.table_props
    saved = tp.flags
    tp.flags = saved | LK.TP_VARIANT
    t = _ti_table!(ld, def, true, 1)
    t.predicate = def
    d() = LK.answer_nodes_discardable(ld, t)
    @test d()                                                                              # a plain variant table
    cond() = (t.nodes[1].value = LK.word(7); LK.set_node_delayinfo(gd, t, 1, LK.DL_UNDEFINED_INFO))
    uncond() = (t.nodes[1].value = LK.word(0); LK.set_node_delayinfo(gd, t, 1, nothing))
    cond()
    @test d()                                                                              # no IDG node: the caller verified there are no conditional answers
    uncond()
    n = LK.idg_new(ld, t)::_TIN
    t.IDG = n
    @test d()                                                                              # an incremental table qualifies
    cond()
    @test !d()                                                                             # an IDG node and a conditional answer: not discardable
    uncond()
    n.monotonic = true
    @test !d()                                                                             # a monotonic table adds answers to the complete trie
    n.monotonic = false
    @test d()

    # a must-fail corruption: the two states differ (non-empty, one extractor)
    good = d()
    n.monotonic = true
    bad = d()
    @test good && !bad
    tp.flags = saved
end

# ── DEFKILL2 rows (the DEFERRED KILL entries of tools/mutants/TB6.py): each premise is asserted in the row ───────────────────────
@testset "idg28: a grown block keeps the dead count of the old one (pl-idgset.c:244-250 grow_block, :300-302, :347-352, :387)" begin
    gd, ld = _ti_wb()
    nodes = [_ti_node(ld)[2] for _ in 1:6]
    set = LK.idg_set{_TIN}()
    add(p) = LK.idg_set_add(ld, set, p, nothing, nothing)
    del(p) = LK.idg_set_delete(set, p, nothing, nothing)
    for i in 1:4
        @test add(nodes[i]) == 1
    end
    @test set.block.capacity == 4 && set.block.count == 4 && set.block.dead == 0       # full: the next new entry grows the block
    @test del(nodes[3]) && set.block.dead == 1 && LK.idg_set_size(set) == 3            # one dead entry, not revived
    @test add(nodes[5]) == 1 && set.block.capacity == 8                                 # grow_block(b): `nb->dead = b->dead` (:250)
    @test set.block.count == 5 && set.block.dead == 1                                   # C: count 5, dead 1
    @test LK.idg_set_size(set) == 4 && !LK.idg_set_contains(set, nodes[3])              # size = count - dead (:387)
    @test _ti_live(set) == nodes[[1, 2, 4, 5]]
    for p in nodes[[1, 2, 4]]
        @test del(p)
        @test set.block !== nothing                                                     # `++b->dead == b->count` (:350) not yet
    end
    @test del(nodes[5]) && set.block === nothing && LK.idg_set_is_empty(set)            # 5 dead of 5: the block goes
    @test add(nodes[3]) == 1 && LK.idg_set_size(set) == 1                               # a fresh single pointer again
end

@testset "idg29: an IDG node charges sizeof(idg_node) = 80 bytes to the table pool (pl-tabling.c idg_new alloc_from_pool, pl-tabling.h:225-254)" begin
    gd, ld = _ti_wb()
    pool = ld.tabling.node_pool
    @test pool isa LK.alloc_pool
    # sizeof(idg_node) at the pin, 64-bit, with O_TRIE_STATS (pl-trie.h:43): magic 4 + concurrent 1 (padded to 8), five pointers
    # (atrie, lingering, mono, registry, plus affected+dependent as two uintptr_t = 6 words) at 8 each = 48, three unsigned 12,
    # stats 2 unsigned 8, the bit-field word 4: 8 + 8 + 16 + 8 + 8 + 8 + 12 + 8 + 4 = 80 (the pointer words: atrie 8, affected 8,
    # dependent 8, lingering 8, mono 8, registry 8)
    @test LK.SIZEOF_IDG_NODE == 80
    tr1 = LK.trie_create(_TI)
    s0 = pool.size
    n1 = LK.idg_new(ld, tr1)::_TIN
    first_delta = pool.size - s0
    @test first_delta == LK.SIZEOF_IDG_NODE + LK.reg_block_size(0) * 8      # the node, and the registry's first block (reg_block)
    tr2 = LK.trie_create(_TI)
    s1 = pool.size
    n2 = LK.idg_new(ld, tr2)::_TIN
    @test pool.size - s1 == 80 && pool.size - s1 == LK.SIZEOF_IDG_NODE      # the second node: the node only
    LK.idg_free_node(n2, pool)
    @test pool.size == s1                                                   # idg_free_node discharges the same 80
end

@testset "idg30: with a free direction `\$idg_edge` goes on from the parents to the dependents (pl-tabling.c:8615-8624 advance_idg_edge_state)" begin
    gd, ld = _ti_wb()
    pt, p = _ti_node(ld)            # parent
    st, s = _ti_node(ld)            # self: has a parent AND a child
    ct, c = _ti_node(ld)            # child
    @test LK.idg_add_child(ld, p, s, 0, 0) && LK.idg_add_child(ld, s, c, 0, 0)
    @test _ti_live(s.affected) == [p] && _ti_live(s.dependent) == [c]
    # the state `idg_edge_gen` builds for an unbound direction with a non-empty `affected` set (:8692-8695: fixed_dir stays false)
    state = LK.idg_edge_state{_TI}()
    state.atrie = st
    state.dir = lk_sym(_TI, :affected)
    state.set = s.affected
    state.en = LK.idg_set_enum_init(s.affected)
    @test !state.fixed_dir
    @test LK.advance_idg_edge_state(ld, state)                                      # the parent
    @test sym_text(state.dir) == "affected" && state.deptrie_symbol == LK.trie_symbol(gd, pt)
    @test LK.advance_idg_edge_state(ld, state)                                      # `state->dir = ATOM_dependent` (:8615-8624), the child
    @test sym_text(state.dir) == "dependent" && state.set === s.dependent && state.deptrie_symbol == LK.trie_symbol(gd, ct)
    @test !LK.advance_idg_edge_state(ld, state)                                     # done
    # with a fixed direction it stops after the parents (:8615 `!state->fixed_dir`)
    fixed = LK.idg_edge_state{_TI}()
    fixed.atrie = st
    fixed.dir = lk_sym(_TI, :affected)
    fixed.fixed_dir = true
    fixed.set = s.affected
    fixed.en = LK.idg_set_enum_init(s.affected)
    @test LK.advance_idg_edge_state(ld, fixed) && !LK.advance_idg_edge_state(ld, fixed)
end

@testset "idg31: assert_term! makes a NEW predicate incremental under PL_CREATE_INCREMENTAL only (pl-comp.c:4916-4919)" begin
    gd, ld = _ti_wb()
    fact(name, v) = (
        t = LK.PL_new_term_ref(ld);
        LK.putSlotValue!(ld, t + 1, mk_expr(_TI, _TI[lk_sym(_TI, Symbol(name)), lk_gnd(_TI, v)]), LK.PutVarMap());
        t
    )
    defn(name) = LK.isCurrentProcedure(sym_key(lk_sym(_TI, Symbol(name))), 1, LK.MODULE_user(gd)).definition
    incr(name) = (LK.get_predicate_table_props!(defn(name)).flags & LK.TP_INCREMENTAL) != 0
    # flags 0: a new predicate, not incremental
    @test LK.assert_term!(gd, ld, fact("ti_v6a", 1), 0, LK.CL_END, nothing, nothing, 0) !== nothing
    @test !incr("ti_v6a")
    # PL_CREATE_INCREMENTAL on a new predicate: incremental
    @test LK.assert_term!(gd, ld, fact("ti_v6b", 1), 0, LK.CL_END, nothing, nothing, LK.PL_CREATE_INCREMENTAL) !== nothing
    @test incr("ti_v6b")
    # a predicate that is already defined keeps its attributes (`!isDefinedProcedure(proc)`)
    @test LK.assert_term!(gd, ld, fact("ti_v6c", 1), 0, LK.CL_END, nothing, nothing, 0) !== nothing
    @test LK.assert_term!(gd, ld, fact("ti_v6c", 2), 0, LK.CL_END, nothing, nothing, LK.PL_CREATE_INCREMENTAL) !== nothing
    @test !incr("ti_v6c")
end

@testset "idg32: a retired block goes on the lingering list of the owning node, newest first (pl-idgset.c:155-166 retire_block)" begin
    gd, ld = _ti_wb()
    nodes = [_ti_node(ld)[2] for _ in 1:10]
    owner = nodes[10]
    set = LK.idg_set{_TIN}()
    add(p) = LK.idg_set_add(ld, set, p, owner, nothing)
    @test owner.lingering === nothing
    for i in 1:4
        @test add(nodes[i]) == 1
    end
    b4 = set.block
    @test b4.capacity == 4 && owner.lingering === nothing                         # nothing retired yet
    for i in 5:8
        @test add(nodes[i]) == 1
    end
    b8 = set.block
    @test b8.capacity == 8 && owner.lingering === b4 && b4.older === nothing      # the first grow: `*lingering = b4`, older NULL
    @test add(nodes[9]) == 1
    @test set.block.capacity == 16 && owner.lingering === b8 && b8.older === b4    # the second: `b->older = *lingering` (:161)
    @test b4.older === nothing
    LK.idg_set_free_lingering(owner, nothing)
    @test owner.lingering === nothing                                              # idg_set_free_lingering (:169-178)
end

@testset "idg33: a change of a table that is still being evaluated raises permission_error(update, variant, V) (pl-tabling.c idg_changed, change_incomplete_error)" begin
    gd, ld, def = _ti_db()
    atrie = _ti_table!(ld, def, false)
    atrie.flags &= ~LK.TRIE_COMPLETE                          # a table under evaluation: a worklist and not complete
    LK.new_worklist(ld, atrie)
    n = LK.idg_new(ld, atrie)::_TIN
    atrie.IDG = n
    @test LK.table_is_incomplete(atrie) && n.falsecount == 0 && LK.PL_exception(ld, 0) == 0
    @test !LK.idg_changed(ld, atrie, 0)                       # change_incomplete_error: false, the error raised
    @test LK.PL_exception(ld, 0) != 0 && n.falsecount == 0    # the mutant answers true with nothing raised
    LK.PL_clear_exception(ld)
    # the control side: the same table, complete, is invalidated
    atrie.flags |= LK.TRIE_COMPLETE
    @test !LK.table_is_incomplete(atrie)
    @test LK.idg_changed(ld, atrie, 0) && n.falsecount == 1 && LK.PL_exception(ld, 0) == 0
end

# ── DEFKILL4 rows: answer nodes that carry TN_IDG_* flags, built by hand (TB6-E10, E18, E19, E20) ─────────────────────────────
# The answer is node 1 of a bare trie (`map_trie_node(atrie, 1, ...)` visits it, as idg24 uses it). Its value is `word(11)`: neither a record
# (`isRecord`: low two bits 0) nor a trie pointer (`isTriePtrValue`: low three bits 7), so `trie_delete`'s release_value has nothing to free.
# A conditional answer carries `DL_UNDEFINED_INFO` (`answer_is_conditional`: pl-tabling.c:982). Every premise is asserted in the row.
"A complete trie with its IDG node and ONE answer (node 1, value `word(11)`, counted in `value_count`), no delay info, no IDG flags."
function _ti_answer_node(ld)
    tr, n = _ti_node(ld)
    tr.nodes[1].value = LK.word(11)
    tr.value_count = 1
    return tr, n
end

@testset "idg34: reeval_prep_node marks the answer deleted and settles its unconditional flag (pl-tabling.c:11141-11164)" begin
    gd, ld = _ti_wb()
    # an unconditional answer that was ADDED: DELETED set, ADDED cleared, UNCONDITIONAL set (:11146-11147, :11158-11160)
    tr, n = _ti_answer_node(ld)
    tr.nodes[1].flags |= LK.TN_IDG_ADDED
    @test tr.nodes[1].value != 0 && !LK.answer_is_conditional(gd, tr, 1) && (tr.nodes[1].flags & LK.TN_IDG_DELETED) == 0
    LK.reeval_prep_node(ld, tr, 1)
    f = tr.nodes[1].flags
    @test (f & LK.TN_IDG_DELETED) != 0 && (f & LK.TN_IDG_ADDED) == 0 && (f & LK.TN_IDG_UNCONDITIONAL) != 0
    @test tr.nodes[1].value == LK.word(11)                                              # the answer itself stays

    # a conditional answer: DELETED set, its delay info dropped, UNCONDITIONAL cleared, the worklist's `undefined` count down by one (:11149-11156)
    tc, nc = _ti_answer_node(ld)
    wl = LK.tbl_worklist{_TI}()
    wl.table = tc.serial
    wl.undefined = 2
    tc.worklist = wl
    LK.set_node_delayinfo(gd, tc, 1, LK.DL_UNDEFINED_INFO)
    tc.nodes[1].flags |= LK.TN_IDG_UNCONDITIONAL | LK.TN_IDG_ADDED
    @test LK.answer_is_conditional(gd, tc, 1)
    LK.reeval_prep_node(ld, tc, 1)
    f = tc.nodes[1].flags
    @test (f & LK.TN_IDG_DELETED) != 0 && (f & LK.TN_IDG_ADDED) == 0 && (f & LK.TN_IDG_UNCONDITIONAL) == 0
    @test !LK.answer_is_conditional(gd, tc, 1) && wl.undefined == 1
    wl.undefined = 0                                                                    # `wl->undefined > 0` guards the decrement
    tc.nodes[1].flags |= LK.TN_IDG_UNCONDITIONAL
    LK.set_node_delayinfo(gd, tc, 1, LK.DL_UNDEFINED_INFO)
    LK.reeval_prep_node(ld, tc, 1)
    @test wl.undefined == 0

    # a node without a value (n->value == 0, :11144): nothing is touched
    tz, nz = _ti_node(ld)
    @test tz.nodes[1].value == 0
    LK.reeval_prep_node(ld, tz, 1)
    @test (tz.nodes[1].flags & LK.TN_IDG_MASK) == 0
end

@testset "idg35: reeval_complete_node and reeval_complete know a new answer (pl-tabling.c:11301-11337, :11340-11370)" begin
    gd, ld = _ti_wb()
    # Got UNconditional (:11328-11331): the answer was conditional in the previous evaluation (no UNCONDITIONAL mark) and is not now
    tr, n = _ti_answer_node(ld)
    @test !LK.answer_is_conditional(gd, tr, 1) && (tr.nodes[1].flags & LK.TN_IDG_UNCONDITIONAL) == 0 && !n.new_answer
    LK.reeval_complete_node(ld, tr, 1)
    @test n.new_answer                                                                  # the mutant (TB6-E19) leaves it false
    @test (tr.nodes[1].flags & LK.TN_IDG_MASK) == 0 && tr.nodes[1].value == LK.word(11) # clear(n, TN_IDG_MASK), the answer stays

    # Not modified (:11332-11334): the answer was unconditional and still is: new_answer stays false
    tu, nu = _ti_answer_node(ld)
    tu.nodes[1].flags |= LK.TN_IDG_UNCONDITIONAL
    LK.reeval_complete_node(ld, tu, 1)
    @test !nu.new_answer && (tu.nodes[1].flags & LK.TN_IDG_MASK) == 0

    # Got conditional (:11324-11327): unconditional before, conditional now
    tg, ng = _ti_answer_node(ld)
    tg.nodes[1].flags |= LK.TN_IDG_UNCONDITIONAL
    LK.set_node_delayinfo(gd, tg, 1, LK.DL_UNDEFINED_INFO)
    @test LK.answer_is_conditional(gd, tg, 1)
    LK.reeval_complete_node(ld, tg, 1)
    @test ng.new_answer

    # reeval_complete (:11340-11370): the answer count is the same (1 == 1) but an answer is new: nothing goes up to the parent (TB6-E10)
    tn, nn = _ti_answer_node(ld)
    pt, p = _ti_node(ld)
    @test LK.idg_add_child(ld, p, nn, 0, 0)
    p.falsecount = 1
    nn.reevaluating = true
    nn.answer_count = tn.value_count
    @test nn.answer_count == 1 && !nn.new_answer && (tn.nodes[1].flags & LK.TN_IDG_UNCONDITIONAL) == 0
    LK.reeval_complete(ld, tn)
    @test nn.new_answer && nn.stats_reevaluated == 1
    @test p.falsecount == 1                                                             # not `same_answers`: no idg_propagate_change

    # the control side: the same table with an answer that did not change propagates `not changed` (the parent is valid again)
    tk, nk = _ti_answer_node(ld)
    tk.nodes[1].flags |= LK.TN_IDG_UNCONDITIONAL
    qt, q = _ti_node(ld)
    @test LK.idg_add_child(ld, q, nk, 0, 0)
    q.falsecount = 1
    nk.reevaluating = true
    nk.answer_count = tk.value_count
    LK.reeval_complete(ld, tk)
    @test !nk.new_answer && q.falsecount == 0
end

@testset "idg36: reset_evaluate_node deletes only an added answer (pl-tabling.c:11395-11411)" begin
    gd, ld = _ti_wb()
    # an answer that is not ADDED: it may be enumerated, so it is only marked deleted (:11407-11409); its delay info goes (:11397-11400)
    tr, n = _ti_answer_node(ld)
    LK.set_node_delayinfo(gd, tr, 1, LK.DL_UNDEFINED_INFO)
    @test LK.answer_is_conditional(gd, tr, 1) && (tr.nodes[1].flags & LK.TN_IDG_ADDED) == 0
    LK.reset_evaluate_node(ld, tr, 1)
    @test (tr.nodes[1].flags & LK.TN_IDG_DELETED) != 0 && tr.nodes[1].value == LK.word(11)   # the mutant (TB6-E20) deletes it
    @test !LK.answer_is_conditional(gd, tr, 1)

    # an ADDED answer: trie_delete (:11405): the value goes, DELETED is not set
    ta, na = _ti_answer_node(ld)
    ta.nodes[1].flags |= LK.TN_IDG_ADDED
    LK.reset_evaluate_node(ld, ta, 1)
    @test ta.nodes[1].value == 0 && (ta.nodes[1].flags & LK.TN_IDG_DELETED) == 0
end

@testset "idg37: a re-derived unconditional answer makes a CONDITIONAL dependent answer unconditional, it does not remove it (pl-tabling.c:1364-1370, propagate_to_answer :1900)" begin
    gd, ld, def = _ti_db()
    t1 = _ti_table!(ld, def, true, 1)                                                      # the table of the worklist, as idg23
    t2 = _ti_table!(ld, def, true, 2)                                                      # holds a conditional answer that delays on node 1 of t1
    n = LK.idg_new(ld, t1)::_TIN
    t1.IDG = n
    n.reevaluating = true
    wl = LK.tbl_worklist{_TI}()
    wl.table = t1.serial
    push!(wl.delays, LK.delay(t2.serial, 1))
    # the conditional answer: one conjunction of one delay, on answer 1 of t1 (propagate_to_answer: `answer_ref(d.variant, d.answer) == panswer`)
    t2.nodes[1].value = LK.word(11)
    t2.nodes[1].flags |= LK.TN_PRIMARY
    t2.value_count = 1
    LK.set_node_delayinfo(gd, t2, 1, LK.delay_info(t2.serial, UInt32(0), [LK.delay_set(0, 1, UInt32(1))], [LK.delay(t1.serial, 1)]))
    wl2 = LK.tbl_worklist{_TI}()
    wl2.table = t2.serial
    wl2.undefined = 1
    t2.worklist = wl2
    @test LK.answer_is_conditional(gd, t2, 1) && (t1.nodes[1].flags & LK.TN_IDG_UNCONDITIONAL) == 0 && wl.component === nothing
    @test _ti_udl(ld, wl, 1) == (LK.UDL_TRUE, 0)                                           # simplified: the entry of the dependent answer is gone
    # simplify_answer(wl, answer, true): the delay is removed from the conjunction, none is left: make_answer_unconditional (:1820)
    @test !LK.answer_is_conditional(gd, t2, 1) && wl2.undefined == 0
    # the answer STAYS (the mutant, truth false, removes the conjunction and the answer: remove_conditional_answer, trie_delete)
    @test t2.value_count == 1 && (t2.nodes[1].flags & LK.TN_PRIMARY) != 0 && t2.nodes[1].value == LK.word(11)
end

@testset "idg38: free_worklist_set clears the table's worklist before freeing, whichever worklist it points at (pl-tabling.c:935-939, free_worklist :3912-3915)" begin
    gd, ld, def = _ti_db()
    t = _ti_table!(ld, def, true, 1)
    n = LK.idg_new(ld, t)::_TIN
    t.IDG = n
    t.flags &= ~LK.TRIE_COMPLETE
    n.reevaluating = true
    wl = LK.tbl_worklist{_TI}()                                                            # the worklist in the set, for table t
    wl.table = t.serial
    other = LK.tbl_worklist{_TI}()                                                         # the table points at a different one
    other.table = t.serial
    t.worklist = other
    wls = LK.worklist_set{LK.tbl_worklist{_TI}}()
    push!(wls.members, wl)
    @test t.worklist === other && t.worklist !== wl && wl.magic != 0
    LK.free_worklist_set(ld, wls, LK.WLFS_DISCARD_INCOMPLETE)
    # `atrie->data.worklist = NULL` (:935) runs before free_worklist: the table points at none. Without it (TB7M6-F2) free_worklist finds a worklist
    # that is not wl (:3913-3915, "Oops") and leaves the pointer at `other`.
    @test wl.magic == 0 && t.worklist === nothing
    @test !n.reevaluating && n.aborted && (t.flags & LK.TRIE_COMPLETE) != 0                # reset_reevaluation ran after the free
end
