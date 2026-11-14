# ORIGINAL: WHITE-BOX rows of the transaction tables of pl-tabling.c (lines 7405-7822 at the pin 18168e62, 10.1.20), TAB1 TB9: the
# functions no Prolog goal reaches one by one (the 29 upstream cases of test_tabling_transaction_swipl.jl run them end to end).
#   * No Prolog route and no swipl: the state is BUILT BY HAND on a real kernel and the transaction state is set by hand
#     (`ld.transaction.generation`, `.predicates`, `.gen_base`, `.gen_max`, `.table_trail`), since the `tt_*` functions read only
#     those fields. A table is a trie made with `trie_create` plus its IDG node (`idg_new`), the edges `idg_add_child` (as the
#     TB6d rows of test_tabling_idg_swipl.jl); an answer is a trie node with `TN_PRIMARY` and a value; the clauses of the monotonic
#     rows are the clauses of a loaded `d/1`, each given its reference by `lookup_clref`.
#   * EXPECTED values are what the C function does at the pin, read off pl-tabling.c at 18168e62 (each testset names the function
#     and its lines); none comes from the kernel. UNVERIFIED on the kernel (nothing was compiled when these rows were written):
#     every observed value; the gate decides.
#   * Every testset (`_tw_rows`) observes the kernel through ONE extractor (`obs`: a vector of `name=value` lines) and compares it
#     with the pinned lines; both are non-empty, and the same testset proves the comparison can FAIL: a corrupted line, an extra
#     line and a dropped line are each flagged by `_tw_diff`.
#   * Groups: tt_has_modified_dependencies / lg_clauses + tt_mono_status / the trail (tt_trail, tt_add_table, tt_add_answer, tt_alloc,
#     tbl_trail_free) / tt_abolish_table / transaction_commit_tables / the rollback functions (tt_rollback_answer, tt_rollback_tables,
#     tt_rollback_actions, transaction_rollback_tables) / merge_tabling_trail / reset_answer_table_tracked / is_trie_clause.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — these built-ins ride the term layer through the FLI (unify, get, the trie blobs)
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TW = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_tws(x) = lk_sym(_TW, Symbol(x))
const _TWN = LK.idg_node{_TW}
const _TWM = LK.idg_mdep{_TW, _TWN}

"The indices where two line lists differ (a missing line counts as a difference)."
_tw_diff(lines::Vector{String}, pins::Vector{String}) =
    [i for i in 1:max(length(lines), length(pins)) if i > length(lines) || i > length(pins) || lines[i] != pins[i]]

"One testset: `obs` (what the kernel did, through one extractor) equals `pin` (what pl-tabling.c does); the comparison can fail."
function _tw_rows(name::String, obs::Vector{String}, pin::Vector{String})
    @testset "$name" begin
        @test !isempty(obs) && !isempty(pin) && length(obs) == length(pin)
        for (i, (o, p)) in enumerate(zip(obs, pin))
            o == p || println(stderr, "  ours  ", i, " ", o, "\n  pin   ", i, " ", p)
            @test o == p
        end
        corrupt = copy(pin)
        corrupt[1] = corrupt[1] * "x"
        @test _tw_diff(obs, corrupt) == sort(union(_tw_diff(obs, pin), [1]))                    # a corrupted pin is flagged
        @test _tw_diff(obs, vcat(pin, "extra")) == sort(union(_tw_diff(obs, pin), [length(pin) + 1]))   # an extra pin is flagged
        @test _tw_diff(obs, pin[1:(end - 1)]) == sort(union(_tw_diff(obs, pin), [length(pin)]))        # a dropped pin is flagged
    end
    return nothing
end

"A kernel (`gd`, `ld`) with no program."
_tw_wb() = (gd = LK.PL_global_data{_TW}(); (gd, LK.PL_local_data{_TW}(gd)))

"A kernel with `d/1` (three clauses) and `e/1` (one) loaded: `(gd, ld, load status, def of d/1, def of e/1, the clauses of d/1)`."
function _tw_world()
    f = joinpath(mktempdir(), "tabling_transaction_wb.pl")
    write(f, ":- dynamic d/1.\nd(1).\nd(2).\nd(3).\n:- dynamic e/1.\ne(1).\n")
    gd = LK.PL_global_data{_TW}()
    ld = LK.PL_local_data{_TW}(gd)
    st, _ = LK.load_file!(gd, ld, f)
    def = LK.isCurrentProcedure(sym_key(_tws("d")), 1, LK.MODULE_user(gd)).definition
    edef = LK.isCurrentProcedure(sym_key(_tws("e")), 1, LK.MODULE_user(gd)).definition
    cls = LK.Clause{_TW}[]
    r = def.impl_clauses.first_clause
    while r !== nothing
        push!(cls, r.clause)
        r = r.next
    end
    return gd, ld, st, def, edef, cls
end

"A complete answer trie with its IDG node (as `idg_init_variant` attaches it); `wl` the worklist sentinel, `pred` the predicate."
function _tw_node(ld; wl=nothing, pred=nothing, lazy::Bool=false, mono::Bool=false)
    tr = LK.trie_create(_TW)
    tr.flags |= LK.TRIE_COMPLETE
    wl === nothing || (tr.worklist = wl)
    pred === nothing || (tr.predicate = pred)
    n = LK.idg_new(ld, tr)::_TWN
    tr.IDG = n
    n.lazy = lazy
    n.monotonic = mono

    return tr, n
end

"A trie with no IDG node, registered in `gd.tries` (its `serial` is set)."
function _tw_plain(gd)
    tr = LK.trie_create(_TW)
    LK.trie_serial!(gd, tr)

    return tr
end

"An opaque child key for the number `k` (an atom-tagged word, never a variable key)."
_twk(k::Integer)::UInt64 = LK.consTagged(k, LK.TAG_ATOM | LK.STG_STATIC)

"Add the answer `k` to `tr`: a child of the root holding a value, `TN_PRIMARY`, counted; its node id."
function _tw_answer!(tr, k::Integer)::Int
    a = LK.insert_child(tr, 1, _twk(k))
    tr.nodes[a].value = UInt64(8k + 1)                      # neither a record (low bits 00) nor a trie pointer (low bits 111)
    tr.nodes[a].flags |= LK.TN_PRIMARY
    tr.value_count += 1

    return a
end

"The node ids of the live answers of `tr` (a value, `TN_PRIMARY`)."
_tw_live(tr) = [i for i in 2:length(tr.nodes) if tr.nodes[i].value != 0 && (tr.nodes[i].flags & LK.TN_PRIMARY) != 0]

"Node ids as text: the name of each id given by `named` (`\"a1\" => id`), `?` for another."
_tw_ids(ids, named::Pair...) = join([get(Dict{Int, String}(v => k for (k, v) in named), i, "?") for i in ids], ",")

"The actions of `tt` as text: `<label><answer>` each (`-0` for one `tt_abolish_table` cleared), a trie labelled by its serial."
function _tw_acts(tt, named::Pair...)
    lab = Dict{Int, String}(t.serial => n for (n, t) in named)

    return join([(x.atrie == 0 ? "-" : get(lab, x.atrie, "?")) * string(x.answer) for x in tt.actions], ",")
end

"An action of the trail: a monotonic answer `node` of the trie numbered `serial`."
_tw_act(serial::Int, node::Int) = LK.tbl_trail_answer(LK.TT_ANSWER, serial, node)

"The clause reference of `cl` as a queue entry (`< 0`: minus the number in `gd.clause_refs`)."
function _tw_ref!(gd, cl)::Int
    LK.lookup_clref(gd, cl)

    return -gd.clause_serials[cl]
end

# ── tt_has_modified_dependencies (pl-tabling.c:7405-7438) ─────────────────────────────────────────────────────────────────
# A table depends on a modified dynamic predicate when one of its children (`n.dependent`) is a dynamic call (`WL_DYNAMIC`) whose
# `predicate` is a key of `LD->transaction.predicates`. Outside a transaction (no table) it is false.
@testset "tt_has_modified_dependencies: a dynamic child whose predicate the transaction modified (pl-tabling.c:7405)" begin
    gd, ld, st, def, edef, cls = _tw_world()
    @test st === :ok
    pt, pn = _tw_node(ld)                                       # a table over d/1
    dt, dn = _tw_node(ld; wl=LK.WL_DYNAMIC, pred=def)
    et, en = _tw_node(ld)                                       # a table over e/1
    eyt, eyn = _tw_node(ld; wl=LK.WL_DYNAMIC, pred=edef)
    qt, qn = _tw_node(ld)                                       # a table whose child names d/1 but is not a dynamic call
    gt, gn = _tw_node(ld; wl=LK.WL_GROUND, pred=def)
    rt, rn = _tw_node(ld)                                       # a table whose dynamic child names no predicate
    nt, nn = _tw_node(ld; wl=LK.WL_DYNAMIC)
    plain = LK.trie_create(_TW)                                 # a table with no IDG node
    @test LK.idg_add_child(ld, pn, dn, 0, 0) && LK.idg_add_child(ld, en, eyn, 0, 0) && LK.idg_add_child(ld, qn, gn, 0, 0)
    @test LK.idg_add_child(ld, rn, nn, 0, 0)

    h(t) = string(LK.tt_has_modified_dependencies(ld, t))
    obs = String[]
    @test ld.transaction.predicates === nothing
    push!(obs, "outside=" * h(pt))
    ld.transaction.generation = LK.gen_t(5)
    ld.transaction.predicates = Dict{LK.Definition{_TW}, LK.tr_gen_t}(def => LK.tr_gen_t(1))
    push!(obs, "p=" * h(pt))                                    # the dynamic child's predicate is modified
    push!(obs, "e=" * h(et))                                    # e/1 is not
    push!(obs, "notdynamic=" * h(qt))                           # the child names d/1 but is no dynamic call
    push!(obs, "nopredicate=" * h(rt))                          # a dynamic call without a predicate names none
    push!(obs, "plain=" * h(plain))                             # no IDG node: false
    ld.transaction.predicates = Dict{LK.Definition{_TW}, LK.tr_gen_t}(def => LK.tr_gen_t(1), edef => LK.tr_gen_t(1))
    push!(obs, "both-p=" * h(pt) * ",e=" * h(et))
    ld.transaction.predicates = Dict{LK.Definition{_TW}, LK.tr_gen_t}()
    push!(obs, "empty=" * h(pt))
    ld.transaction.predicates = nothing
    push!(obs, "none=" * h(pt))
    _tw_rows(
        "tt_has_modified_dependencies",
        obs,
        [
            "outside=false", "p=true", "e=false", "notdynamic=false", "nopredicate=false", "plain=false",
            "both-p=true,e=true", "empty=false", "none=false",
        ]
    )
end

# ── lg_clauses and tt_mono_status (pl-tabling.c:7440-7580) ────────────────────────────────────────────────────────────────
# `lg_clauses` counts the live queued clauses of a dependency: `generation_created < GEN_TRANSACTION_BASE` is a global (older)
# clause, `gen_base <= created < gen_max` a clause of this transaction; `tt_mono_status` answers M_INVALID_DEPS (a dependent table
# with falsecount > 0 or force_reeval), else M_MIXED_CLAUSES (both kinds), else M_OLD_CLAUSES (a global one), else M_NEW_CLAUSES.
@testset "lg_clauses and tt_mono_status: old, new and mixed clauses, invalid dependencies (pl-tabling.c:7440)" begin
    gd, ld, st, def, edef, cls = _tw_world()
    @test st === :ok && length(cls) == 3
    @test LK.M_INVALID_DEPS == 0 && LK.M_OLD_CLAUSES == 1 && LK.M_MIXED_CLAUSES == 2 && LK.M_NEW_CLAUSES == 3
    pt, pn = _tw_node(ld; lazy=true, mono=true)                 # the lazy monotonic table
    dt, dn = _tw_node(ld; wl=LK.WL_DYNAMIC, pred=def)           # its dynamic call
    @test LK.idg_add_child(ld, pn, dn, 0, 0)
    m = _TWM(LK.IDG_MDEP_MAGIC, true, UInt32(0), nothing, dn, Int[], 0, nothing)
    dn.mono = LK.idg_mono{_TW, _TWN}(IdDict{_TWN, _TWM}(pn => m), 0, nothing)
    @test LK.idg_mdeps(dn, pn) === m

    base = LK.GEN_TRANSACTION_BASE
    tr = ld.transaction
    tr.gen_base = LK.gen_t(base)
    tr.gen_max = LK.gen_t(base + 10)
    r1, r2, r3 = [_tw_ref!(gd, c) for c in cls]
    @test r1 < 0 && r2 < 0 && r3 < 0 && allunique([r1, r2, r3])
    cls[1].generation_created = LK.gen_t(5)                     # older than any transaction
    cls[2].generation_created = LK.gen_t(base + 1)              # made by this transaction
    cls[3].generation_created = LK.gen_t(base + 10)             # at gen_max: not this transaction's

    row(name, queue) = begin
        m.queue = queue
        s = LK.mono_dep_status()
        LK.lg_clauses(ld, m, s)

        "$name=$(s.global_clauses),$(s.local_clauses)/$(LK.tt_mono_status(ld, pt))"
    end
    obs = String[]
    push!(obs, row("empty", Int[]))
    push!(obs, row("old", [r1]))
    push!(obs, row("new", [r2]))
    push!(obs, row("mixed", [r1, r2]))
    cls[1].flags |= LK.CL_ERASED
    push!(obs, row("erased", [r1]))                             # an erased clause is not counted
    cls[1].flags &= ~LK.CL_ERASED
    push!(obs, row("atmax", [r3]))                              # created == gen_max: neither
    tr.gen_base = LK.gen_t(base + 3)
    push!(obs, row("belowbase", [r2]))                          # created < gen_base: neither
    tr.gen_base = LK.gen_t(base)
    push!(obs, row("answer", [7]))                              # an answer node (> 0) is skipped
    ct, cn = _tw_node(ld)                                       # a complete table the monotonic one depends on
    @test LK.idg_add_child(ld, pn, cn, 0, 0)
    cn.falsecount = 1
    push!(obs, row("falsecount", [r1]))                         # a dependent table is invalid
    cn.falsecount = 0
    cn.force_reeval = true
    push!(obs, row("force", [r1]))                              # so is one forced to reevaluate
    cn.force_reeval = false
    push!(obs, row("valid", [r1]))
    _tw_rows(
        "lg_clauses and tt_mono_status",
        obs,
        [
            "empty=0,0/3", "old=1,0/1", "new=0,1/3", "mixed=1,1/2", "erased=0,0/3", "atmax=0,0/3", "belowbase=0,0/3",
            "answer=0,0/3", "falsecount=1,0/0", "force=1,0/0", "valid=1,0/1",
        ]
    )
end

# ── the trail: tt_trail, tt_add_table, tt_add_answer, tt_alloc, tbl_trail_free (pl-tabling.c:7584-7700) ─────────────────────
# Outside a transaction (`generation == 0`) `tt_add_table` and `tt_add_answer` do nothing. `tt_add_answer` skips a table whose IDG
# node has `tt_notrail` or that is already in `tt.tables`, else it adds one action and sets TRIE_ISTRACKED.
@testset "the trail: tt_trail, tt_add_table, tt_add_answer, tt_alloc, tbl_trail_free (pl-tabling.c:7584)" begin
    gd, ld = _tw_wb()
    at, an = _tw_node(ld)
    bt, bn = _tw_node(ld)
    ct, cn = _tw_node(ld)
    cn.tt_notrail = true
    plain = LK.trie_create(_TW)
    tracked(t) = (t.flags & LK.TRIE_ISTRACKED) != 0
    tr = ld.transaction

    obs = String[]
    push!(obs, "trail0=$(tr.table_trail === nothing)")
    LK.tt_add_table(ld, at, LK.TT_TBL_INVALIDATE)
    LK.tt_add_answer(ld, bt, 6)
    push!(obs, "gen0=$(tr.table_trail === nothing)|$(tracked(bt))")                  # no transaction: no trail, not tracked
    tr.generation = LK.gen_t(5)
    tt = LK.tt_trail(ld)
    push!(obs, "once=$(LK.tt_trail(ld) === tt && tr.table_trail === tt && isempty(tt.tables) && isempty(tt.actions))")
    LK.tt_add_table(ld, at, LK.TT_TBL_INVALIDATE)
    push!(
        obs,
        "table=$(length(tt.tables)),$(get(tt.tables, LK.trie_symbol(gd, at), -1)),$(haskey(tt.tables, LK.trie_symbol(gd, bt)))"
    )
    LK.tt_add_answer(ld, bt, 7)
    push!(obs, "answer=$(_tw_acts(tt, "b" => bt))|$(tt.actions[1].type)|$(tracked(bt))")
    LK.tt_add_answer(ld, at, 8)
    push!(obs, "intables=$(length(tt.actions))|$(tracked(at))")                     # at is in tt.tables: skipped
    LK.tt_add_answer(ld, ct, 9)
    push!(obs, "notrail=$(length(tt.actions))|$(tracked(ct))")                      # tt_notrail: skipped
    LK.tt_add_answer(ld, plain, 10)
    push!(obs, "noidg=$(_tw_acts(tt, "b" => bt, "p" => plain))|$(tracked(plain))")   # no IDG node: recorded
    LK.tt_add_answer(ld, bt, 11)
    push!(obs, "again=$(_tw_acts(tt, "b" => bt, "p" => plain))|$(tracked(bt))")
    LK.tt_alloc(ld, ct, 12)
    push!(obs, "alloc=$(_tw_acts(tt, "b" => bt, "p" => plain, "c" => ct))")         # tt_alloc itself does not test the policy
    LK.tbl_trail_free(tt)
    push!(obs, "freed=$(length(tt.tables)),$(length(tt.actions))")
    _tw_rows(
        "the trail",
        obs,
        [
            "trail0=true", "gen0=true|false", "once=true", "table=1,1,false", "answer=b7|1|true", "intables=1|false",
            "notrail=1|false", "noidg=b7,p10|true", "again=b7,p10,b11|true", "alloc=b7,p10,b11,c12", "freed=0,0",
        ]
    )
end

# ── tt_abolish_table (pl-tabling.c:7704-7722) ─────────────────────────────────────────────────────────────────────────────
@testset "tt_abolish_table: the actions of that table only are cleared (pl-tabling.c:7704)" begin
    gd, ld = _tw_wb()
    at, an = _tw_node(ld)
    bt, bn = _tw_node(ld)
    unregistered = LK.trie_create(_TW)                              # serial 0: names no action
    tr = ld.transaction
    tr.generation = LK.gen_t(5)

    obs = String[]
    LK.tt_abolish_table(ld, at)                                     # no trail yet: nothing, no trail made
    push!(obs, "notrail=$(tr.table_trail === nothing)")
    LK.tt_alloc(ld, at, 21)
    LK.tt_alloc(ld, bt, 22)
    LK.tt_alloc(ld, at, 23)
    tt = tr.table_trail
    push!(obs, "before=$(_tw_acts(tt, "a" => at, "b" => bt))")
    LK.tt_abolish_table(ld, at)
    push!(obs, "abolish-a=$(_tw_acts(tt, "a" => at, "b" => bt))")
    LK.tt_abolish_table(ld, unregistered)
    push!(obs, "unregistered=$(_tw_acts(tt, "a" => at, "b" => bt))")
    LK.tt_abolish_table(ld, bt)
    push!(obs, "abolish-b=$(_tw_acts(tt, "a" => at, "b" => bt))|$(length(tt.actions))")
    _tw_rows(
        "tt_abolish_table",
        obs,
        ["notrail=true", "before=a21,b22,a23", "abolish-a=-0,b22,-0", "unregistered=-0,b22,-0", "abolish-b=-0,-0,-0|3"]
    )
end

# ── transaction_commit_tables (pl-tabling.c:7728-7750) ────────────────────────────────────────────────────────────────────
@testset "transaction_commit_tables: the outermost commit releases the trail and answers true (pl-tabling.c:7728)" begin
    gd, ld = _tw_wb()
    at, an = _tw_node(ld)
    tr = ld.transaction
    tr.generation = LK.gen_t(5)

    obs = String[]
    push!(obs, "notrail=$(LK.transaction_commit_tables(ld))|$(tr.table_trail === nothing)")
    LK.tt_add_table(ld, at, LK.TT_TBL_INVALIDATE)
    LK.tt_alloc(ld, at, 31)
    tt = tr.table_trail
    push!(obs, "before=$(length(tt.tables)),$(length(tt.actions))")
    rc = LK.transaction_commit_tables(ld)
    push!(obs, "commit=$rc|$(tr.table_trail === nothing)|$(length(tt.tables)),$(length(tt.actions))")
    push!(obs, "untouched=$(an.falsecount),$(an.force_reeval)")      # a commit invalidates nothing
    _tw_rows(
        "transaction_commit_tables",
        obs,
        ["notrail=true|true", "before=1,1", "commit=true|true|0,0", "untouched=0,false"]
    )
end

# ── the rollback: tt_rollback_answer, tt_rollback_tables, tt_rollback_actions, transaction_rollback_tables (pl-tabling.c:7752-7822) ──
# `tt_rollback_answer` of a LAZY answer trie first prunes the queues of its dependents' monotonic dependencies of the answer (the
# value is set to 0 while it does so), then deletes the answer node; a dependent with `force_reeval` has no queue and gets its
# falsecount raised (`prune_deleted_mdeps`).
"A lazy (or not) answer trie `ct` with two answers, a lazy parent table `pt` whose dependency queues both: the world of the rows."
function _tw_lazy_world(; lazy_child::Bool=true, force_parent::Bool=false)
    gd, ld = _tw_wb()
    ct, cn = _tw_node(ld; lazy=lazy_child)
    pt, pn = _tw_node(ld; lazy=true)
    LK.idg_add_child(ld, pn, cn, 0, 0)
    m = _TWM(LK.IDG_MDEP_MAGIC, true, UInt32(0), nothing, cn, Int[], 0, nothing)
    cn.mono = LK.idg_mono{_TW, _TWN}(IdDict{_TWN, _TWM}(pn => m), 0, nothing)
    pn.force_reeval = force_parent
    a1 = _tw_answer!(ct, 1)
    a2 = _tw_answer!(ct, 2)
    m.queue = [a1, a2]

    return gd, ld, ct, cn, pt, pn, m, a1, a2
end

@testset "tt_rollback_answer: the queues of a lazy table are pruned, then the answer is deleted (pl-tabling.c:7752)" begin
    obs = String[]
    for (name, kw) in (
        ("lazy", (;)), ("nonlazy", (; lazy_child=false)), ("forced", (; force_parent=true))
    )
        gd, ld, ct, cn, pt, pn, m, a1, a2 = _tw_lazy_world(; kw...)
        named = ("a1" => a1, "a2" => a2)
        before = "live[$(_tw_ids(_tw_live(ct), named...))],q[$(_tw_ids(m.queue, named...))],vc=$(ct.value_count)"
        LK.tt_rollback_answer(ld, ct, a1)
        push!(
            obs,
            "$name=$before>live[$(_tw_ids(_tw_live(ct), named...))],q[$(_tw_ids(m.queue, named...))],vc=$(ct.value_count),pfc=$(pn.falsecount)"
        )
    end
    gd, ld = _tw_wb()
    plain = _tw_plain(gd)                                           # no IDG node: the answer is deleted, nothing pruned
    p1 = _tw_answer!(plain, 1)
    p2 = _tw_answer!(plain, 2)
    LK.tt_rollback_answer(ld, plain, p1)
    push!(obs, "noidg=live[$(_tw_ids(_tw_live(plain), "p1" => p1, "p2" => p2))],vc=$(plain.value_count)")
    _tw_rows(
        "tt_rollback_answer",
        obs,
        [
            "lazy=live[a1,a2],q[a1,a2],vc=2>live[a2],q[a2],vc=1,pfc=0",
            "nonlazy=live[a1,a2],q[a1,a2],vc=2>live[a2],q[a1,a2],vc=1,pfc=0",
            "forced=live[a1,a2],q[a1,a2],vc=2>live[a2],q[a1,a2],vc=1,pfc=1",
            "noidg=live[p2],vc=1",
        ]
    )
end

@testset "tt_rollback_tables: each affected table with an IDG node is invalidated (pl-tabling.c:7790)" begin
    gd, ld = _tw_wb()
    t1, n1 = _tw_node(ld)                                           # an incremental table
    t2, n2 = _tw_node(ld; lazy=true, mono=true)                     # a lazy monotonic table
    t3, n3 = _tw_node(ld)                                           # not affected
    t4, n4 = _tw_node(ld)                                           # affected, but destroyed since
    sym1 = LK.trie_symbol(gd, t1)
    sym2 = LK.trie_symbol(gd, t2)
    sym4 = LK.trie_symbol(gd, t4)
    t4.magic = Int32(0)
    @test LK.symbol_trie(gd, sym4) === nothing && LK.symbol_trie(gd, sym1) === t1
    affected = Dict{UInt64, Int}(sym1 => LK.TT_TBL_INVALIDATE, sym2 => LK.TT_TBL_INVALIDATE, sym4 => LK.TT_TBL_INVALIDATE)

    st(n) = "fc$(n.falsecount),force=$(n.force_reeval)"
    obs = String[]
    push!(obs, "before=$(st(n1)),$(st(n2)),$(st(n3))")
    rc = LK.tt_rollback_tables(ld, affected)
    push!(obs, "rc=$rc")
    push!(obs, "n1=$(st(n1))")
    push!(obs, "n2=$(st(n2))")
    push!(obs, "n3=$(st(n3))")
    push!(obs, "n4=$(st(n4))")                                      # a destroyed table is skipped
    push!(obs, "again=$(LK.tt_rollback_tables(ld, affected))|$(st(n1))|$(st(n2))")     # already invalid: not counted twice
    push!(obs, "empty=$(LK.tt_rollback_tables(ld, Dict{UInt64, Int}()))|$(st(n3))")
    _tw_rows(
        "tt_rollback_tables",
        obs,
        [
            "before=fc0,force=false,fc0,force=false,fc0,force=false", "rc=true", "n1=fc1,force=false", "n2=fc1,force=true",
            "n3=fc0,force=false", "n4=fc0,force=false", "again=true|fc1,force=false|fc1,force=true", "empty=true|fc0,force=false",
        ]
    )
end

@testset "tt_rollback_actions: the trail's answers are deleted, a cleared entry skipped (pl-tabling.c:7806)" begin
    gd, ld = _tw_wb()
    at = _tw_plain(gd)
    bt = _tw_plain(gd)
    a1 = _tw_answer!(at, 1)
    a2 = _tw_answer!(at, 2)
    b1 = _tw_answer!(bt, 1)
    acts = [_tw_act(at.serial, a1), _tw_act(0, 0), _tw_act(bt.serial, b1)]       # the middle one was cleared by tt_abolish_table

    obs = String[]
    push!(obs, "before=a[$(_tw_ids(_tw_live(at), "a1" => a1, "a2" => a2))],b[$(length(_tw_live(bt)))]")
    rc = LK.tt_rollback_actions(ld, acts)
    push!(obs, "rc=$rc")
    push!(obs, "after=a[$(_tw_ids(_tw_live(at), "a1" => a1, "a2" => a2))],b[$(length(_tw_live(bt)))]")
    push!(obs, "kept=$(at.value_count),$(bt.value_count)")
    push!(obs, "empty=$(LK.tt_rollback_actions(ld, LK.tbl_trail_answer[]))")
    _tw_rows(
        "tt_rollback_actions",
        obs,
        ["before=a[a1,a2],b[1]", "rc=true", "after=a[a2],b[0]", "kept=1,0", "empty=true"]
    )
end

@testset "transaction_rollback_tables: invalidate the tables, delete the answers, free the trail (pl-tabling.c:7816)" begin
    gd, ld = _tw_wb()
    t1, n1 = _tw_node(ld)
    at = _tw_plain(gd)
    a1 = _tw_answer!(at, 1)
    a2 = _tw_answer!(at, 2)
    tr = ld.transaction
    tr.generation = LK.gen_t(5)

    obs = String[]
    push!(obs, "notrail=$(LK.transaction_rollback_tables(ld))|$(tr.table_trail === nothing)|$(n1.falsecount)")
    LK.tt_add_table(ld, t1, LK.TT_TBL_INVALIDATE)
    LK.tt_alloc(ld, at, a1)
    tt = tr.table_trail
    push!(obs, "before=$(length(tt.tables)),$(length(tt.actions))|live[$(_tw_ids(_tw_live(at), "a1" => a1, "a2" => a2))]|fc$(n1.falsecount)")
    rc = LK.transaction_rollback_tables(ld)
    push!(obs, "rollback=$rc|$(tr.table_trail === nothing)|$(length(tt.tables)),$(length(tt.actions))")
    push!(obs, "after=live[$(_tw_ids(_tw_live(at), "a1" => a1, "a2" => a2))]|fc$(n1.falsecount)")
    _tw_rows(
        "transaction_rollback_tables",
        obs,
        [
            "notrail=true|true|0", "before=1,1|live[a1,a2]|fc0", "rollback=true|true|0,0", "after=live[a2]|fc1",
        ]
    )
end

# ── merge_tabling_trail (pl-tabling.c:7826-7840) ──────────────────────────────────────────────────────────────────────────
@testset "merge_tabling_trail: the nested trail's actions follow the parent's, the nested trail is emptied (pl-tabling.c:7826)" begin
    into = LK.tbl_trail()
    from = LK.tbl_trail()
    push!(into.actions, _tw_act(1, 11), _tw_act(1, 12))
    into.tables[UInt64(100)] = LK.TT_TBL_INVALIDATE
    push!(from.actions, _tw_act(1, 13), _tw_act(1, 14))
    from.tables[UInt64(200)] = LK.TT_TBL_INVALIDATE

    answers(t) = join([x.answer for x in t.actions], ",")
    obs = String[]
    push!(obs, "before=$(answers(into))|$(answers(from))")
    LK.merge_tabling_trail(into, from)
    push!(obs, "into=$(answers(into))")
    push!(obs, "from=$(length(from.actions)),$(length(from.tables))")
    push!(obs, "tables=$(sort(collect(Int, keys(into.tables))))")           # the nested trail's tables are dropped
    LK.merge_tabling_trail(into, from)
    push!(obs, "empty-from=$(answers(into))")
    into2 = LK.tbl_trail()
    from2 = LK.tbl_trail()
    push!(from2.actions, _tw_act(1, 15))
    LK.merge_tabling_trail(into2, from2)
    push!(obs, "empty-into=$(answers(into2))|$(length(from2.actions))")
    _tw_rows(
        "merge_tabling_trail",
        obs,
        [
            "before=11,12|13,14", "into=11,12,13,14", "from=0,0", "tables=[100]", "empty-from=11,12,13,14",
            "empty-into=15|0",
        ]
    )
end

# ── reset_answer_table_tracked (pl-tabling.c:2664-2665, the TRIE_ISTRACKED branch of reset_answer_table) ───────────────────
@testset "reset_answer_table_tracked: a tracked table is abolished in the trail and loses TRIE_ISTRACKED (pl-tabling.c:2664)" begin
    gd, ld = _tw_wb()
    at, an = _tw_node(ld)
    bt, bn = _tw_node(ld)
    tr = ld.transaction
    tr.generation = LK.gen_t(5)
    LK.tt_alloc(ld, at, 41)
    LK.tt_alloc(ld, bt, 42)
    tt = tr.table_trail
    at.flags |= LK.TRIE_ISTRACKED
    tracked(t) = (t.flags & LK.TRIE_ISTRACKED) != 0

    obs = String[]
    push!(obs, "before=$(_tw_acts(tt, "a" => at, "b" => bt))|$(tracked(at)),$(tracked(bt))")
    LK.reset_answer_table_tracked(ld, bt)                           # not tracked: nothing
    push!(obs, "untracked=$(_tw_acts(tt, "a" => at, "b" => bt))|$(tracked(at)),$(tracked(bt))")
    LK.reset_answer_table_tracked(ld, at)
    push!(obs, "tracked=$(_tw_acts(tt, "a" => at, "b" => bt))|$(tracked(at)),$(tracked(bt))")
    LK.reset_answer_table_tracked(ld, at)                           # the flag is gone: nothing more happens
    push!(obs, "again=$(_tw_acts(tt, "a" => at, "b" => bt))|$(tracked(at))")
    tr.table_trail = nothing                                        # a tracked table with no trail: the flag goes, no error
    bt.flags |= LK.TRIE_ISTRACKED
    LK.reset_answer_table_tracked(ld, bt)
    push!(obs, "notrail=$(tracked(bt))|$(tr.table_trail === nothing)")
    _tw_rows(
        "reset_answer_table_tracked",
        obs,
        [
            "before=a41,b42|true,false", "untracked=a41,b42|true,false", "tracked=-0,b42|false,false",
            "again=-0,b42|false", "notrail=false|true",
        ]
    )
end

# ── is_trie_clause (pl-transaction.c) ─────────────────────────────────────────────────────────────────────────────────────
# A clause of `trie_gen_compiled/2,3` stands for a trie (the transaction code skips it); a clause of any other predicate does not.
@testset "is_trie_clause: a clause of trie_gen_compiled/2,3 (pl-transaction.c)" begin
    gd, ld, st, def, edef, cls = _tw_world()
    @test st === :ok && !isempty(cls)
    cl = cls[1]
    obs = String[]
    push!(obs, "d=$(LK.is_trie_clause(gd, cl))")
    saved = cl.predicate
    cl.predicate = gd.procedures_trie_gen_compiled3.definition
    push!(obs, "compiled3=$(LK.is_trie_clause(gd, cl))")
    cl.predicate = gd.procedures_trie_gen_compiled2.definition
    push!(obs, "compiled2=$(LK.is_trie_clause(gd, cl))")
    cl.predicate = edef
    push!(obs, "e=$(LK.is_trie_clause(gd, cl))")
    cl.predicate = saved
    push!(obs, "restored=$(LK.is_trie_clause(gd, cl))")
    @test gd.procedures_trie_gen_compiled3.definition !== gd.procedures_trie_gen_compiled2.definition
    _tw_rows(
        "is_trie_clause",
        obs,
        ["d=false", "compiled3=true", "compiled2=true", "e=false", "restored=false"]
    )
end
