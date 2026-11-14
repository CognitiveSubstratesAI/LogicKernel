# UPSTREAM: swipl-devel src/pl-transaction.c @ 18168e629eab
# CLASS: code
# COPYRIGHT: Copyright (c)  2020-2024, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# PORTED FROM pl-transaction.c (TX1): the transaction state's operations (TX1a: retract and assert inside a transaction,
# visibility, the last-modified table, commit, discard, the merge of a nested transaction's tables, the list of updates)
# and the Prolog connection (TX1b: `$transaction/2,3`, `$snapshot/1`, `transaction_updates/1`). The data structures
# (`tr_stack`, `ld_transaction`, the `TR_*` flags and the `GEN_*` marks) are in src/pl-incl.jl, where `index_context` can
# name them. The generation space: 1..GEN_TRANSACTION_BASE is globally visible; a thread starting a transaction takes
# the 2^32 generations from GEN_TRANSACTION_BASE+TID*GEN_TRANSACTION_SIZE (pl-transaction.c:68-100).
#
# NOT PORTED, each to its owner (docs/architecture.md TX1):
#   * `table_trail`, `transaction_commit_tables`, `transaction_rollback_tables`, `merge_tabling_trail` — the tables' share of
#     a transaction: TAB1 TB9.
#   * `acquire_clause`/`release_clause`/`tr_erased_no` — no reference counts: a clause the tables hold stays alive in the
#     tables; `transaction_visible_clause` always looks the clause up in the tables where upstream skips that when
#     `tr_erased_no` is 0, the same answer.
#   * the mutex argument of `$transaction/3` — no mutex table (the kernel has one thread, pl-mutex.jl).
#   * the debug predicate `pred_generations/1` (`O_DEBUG`): the oracle's release build has none (see `PL_predicates_from_transaction`).

# allow-new-artifact: a port of src/pl-transaction.c, read with git show at the pin 18168e629eab (the reference corpus is the pin)

# PORT: pl-transaction.c IS_ASSERT_GEN
"True for the table values of a clause asserted in the transaction (pl-transaction.c)."
IS_ASSERT_GEN(g::tr_gen_t)::Bool = g == GEN_ASSERTA || g == GEN_ASSERTZ

# PORT: pl-transaction.c tr_clause_table
# DIVERGES: the table of `tr` is made on demand as upstream's, without `free_symbol` (`release_clause`: no reference counts).
"The changed-clauses table of the transaction `tr`, made when it has none (pl-transaction.c)."
function tr_clause_table(tr::ld_transaction{T})::Dict{Clause{T}, tr_gen_t} where {T}
    t = tr.clauses
    if t === nothing
        t = Dict{Clause{T}, tr_gen_t}()
        tr.clauses = t
    end
    return t
end

# PORT: pl-transaction.c transaction_retract_clause
# DIVERGES: `rc` is 1 (true), 0 (false) or -1 (an error: upstream's `PL_representation_error` is raised in `ld`); no
# `acquire_clause` or `ATOMIC_INC(&clause->tr_erased_no)`; `next_generation(clause->predicate)` is `next_generation!`'s
# transaction branch: the generation after the transaction's own, or 0 when its space is used up.
"""
    transaction_retract_clause(gd, ld, clause) -> Int

Record in the transaction that `clause` is retracted (pl-transaction.c): 1 when the transaction keeps the record and the
caller is done; 0 when the clause was asserted by this very transaction and the caller retracts it as any clause; -1
when the generation space of the transaction is used up (the error is raised).
"""
function transaction_retract_clause(
    gd::PL_global_data{T}, ld::PL_local_data{T}, clause::Clause{T}
)::Int where {T}
    tr = ld.transaction
    if clause.generation_created < tr.gen_base
        lgen = next_generation!(gd, ld, clause.predicate) - tr.gen_base
        tr_clause_table(tr)[clause] = lgen                  # addHTablePW(tr_clause_table(), clause, lgen)
        return 1
    elseif clause.generation_created <= tr.gen_nest
        egen = next_generation!(gd, ld, clause.predicate)
        if egen == 0
            PL_error(ld, ERR_REPRESENTATION, mk_sym(T, :transaction_generations))   # PL_representation_error("transaction_generations")
            return -1
        end
        clause.generation_erased = egen
        tr_clause_table(tr)[clause] = GEN_NESTED_RETRACT
        return 1
    end
    return 0
end

# PORT: pl-transaction.c transaction_assert_clause
"Record in the transaction that `clause` was asserted at `where_` (pl-transaction.c)."
function transaction_assert_clause(
    ld::PL_local_data{T}, clause::Clause{T}, where_::Union{Int, ClauseRef{T}}
)::Bool where {T}
    lgen = where_ === CL_START ? GEN_ASSERTA : GEN_ASSERTZ
    tr_clause_table(ld.transaction)[clause] = lgen
    return true
end

# PORT: pl-transaction.c transaction_visible_clause
# DIVERGES: takes the transaction state, not the thread's: `index_context` holds it for the searches (src/pl-index.jl); no
# `tr_erased_no` test (see the header). The table value `lgen+gen_base` wraps in 64 bits as upstream's `GEN_NESTED_RETRACT`
# does (`Base.:+` on `UInt64` wraps).
"True when `cl` is visible to generation `gen` of the transaction `tr` (pl-transaction.c)."
function transaction_visible_clause(
    tr::ld_transaction{T}, cl::Clause{T}, gen::gen_t
)::Bool where {T}
    if cl.generation_created <= tr.gen_start && cl.generation_erased > tr.gen_start
        tbl = tr.clauses
        stack = tr.stack
        while true
            if tbl !== nothing
                lgen = get(tbl, cl, tr_gen_t(0))
                if lgen != 0 && !IS_ASSERT_GEN(lgen)
                    if lgen + tr.gen_base <= gen
                        return false
                    end
                end
            end
            stack === nothing && break
            tbl = stack.clauses
            stack = stack.parent
        end
        return true
    end
    return false
end

# PORT: pl-transaction.c LGEN
"A global generation as an offset from the transaction's base (pl-transaction.c `LGEN`)."
LGEN(tr::ld_transaction, gen::gen_t)::tr_gen_t = gen - tr.gen_base
# PORT: pl-transaction.c LGEN_FLAGS_VAL
"The value of a changed-predicates entry: the local generation, shifted left by two, with the flags (pl-transaction.c)."
LGEN_FLAGS_VAL(tr::ld_transaction, gen::gen_t, flags::UInt32)::tr_gen_t =
    (LGEN(tr, gen) << 2) | tr_gen_t(flags)
# PORT: pl-transaction.c VAL_LGEN
"The local generation of a changed-predicates entry (pl-transaction.c)."
VAL_LGEN(ptr::tr_gen_t)::tr_gen_t = ptr >> 2
# PORT: pl-transaction.c VAL_GEN_FLAGS
"The `TWF_*` flags of a changed-predicates entry (pl-transaction.c)."
VAL_GEN_FLAGS(ptr::tr_gen_t)::UInt32 = UInt32(ptr & 0x3)
# PORT: pl-transaction.c VAL_ADD_FLAGS
"A changed-predicates entry with `flags` added (pl-transaction.c)."
VAL_ADD_FLAGS(ptr::tr_gen_t, flags::UInt32)::tr_gen_t = ptr | tr_gen_t(flags)

# PORT: pl-transaction.c transaction_last_modified_predicate
# DIVERGES: the definition has no `last_modified` (src/pl-proc.jl `setLastModifiedPredicate!`): `last_modified` is the one of
# its module, which the caller passes.
"The last modification of `def` as seen inside the transaction (pl-transaction.c): `last_modified` is the global one."
function transaction_last_modified_predicate(
    ld::PL_local_data{T}, def::Definition{T}, last_modified::gen_t
)::gen_t where {T}
    tr = ld.transaction
    table = tr.predicates
    if table !== nothing
        lgen = get(table, def, tr_gen_t(0))
        if lgen != 0
            return tr.gen_start + VAL_LGEN(lgen)
        end
    end
    return last_modified > tr.gen_start ? tr.gen_start : last_modified
end

# PORT: pl-transaction.c transaction_set_last_modified
"Record that `def` was modified at transaction generation `gen` (pl-transaction.c)."
function transaction_set_last_modified(
    ld::PL_local_data{T}, def::Definition{T}, gen::gen_t, flags::UInt32
)::Nothing where {T}
    tr = ld.transaction
    table = tr.predicates
    if table === nothing
        table = Dict{Definition{T}, tr_gen_t}()
        tr.predicates = table
    end
    lgen0 = get(table, def, tr_gen_t(0))
    oflags = VAL_GEN_FLAGS(lgen0)
    table[def] = LGEN_FLAGS_VAL(tr, gen, oflags | flags)
    return nothing
end

# PORT: pl-transaction.c set_modified
"Give every predicate the transaction changed the generation `gen` of the commit as its last modification (pl-transaction.c)."
function set_modified(
    gd::PL_global_data{T}, ld::PL_local_data{T}, gen::gen_t
)::Nothing where {T}
    tr = ld.transaction
    table = tr.predicates
    if table !== nothing
        for (def, v) in table
            setLastModifiedPredicate!(gd, ld, def, gen, VAL_GEN_FLAGS(v))
        end
        tr.predicates = nothing
    end
    return nothing
end

# PORT: pl-transaction.c retract_clause_gen
"Lower the erased generation of `clause` to `generation` (pl-transaction.c)."
function retract_clause_gen(clause::Clause{T}, generation::gen_t)::Nothing where {T}
    if clause.generation_erased > generation
        clause.generation_erased = generation
    end
    return nothing
end

# PORT: pl-transaction.c transaction_commit
# DIVERGES: no `L_GENERATION` lock and no `MEMORY_RELEASE` (one thread); the debug messages are not kept; the branches
# for `GEN_NESTED_RETRACT` and the erased clause do the same here (no `tr_erased_no` to decrement).
"Make the changes of the outermost transaction global, from one new generation of the database on (pl-transaction.c)."
function transaction_commit(gd::PL_global_data{T}, ld::PL_local_data{T})::Bool where {T}
    tr = ld.transaction
    clauses = tr.clauses
    if clauses !== nothing
        gen_commit = global_generation(gd) + 1
        for (cl, lgen) in clauses
            if IS_ASSERT_GEN(lgen)
                if (cl.flags & CL_ERASED) == 0
                    cl.generation_erased = GEN_MAX
                    cl.generation_created = gen_commit
                else
                    cl.generation_erased = GEN_TR_ASSERT_ERASE
                    cl.generation_created = GEN_TR_ASSERT_ERASE
                end
            else
                retract_clause_gen(cl, gen_commit)
            end
        end
        gd._generation = gen_commit

        for (cl, lgen) in clauses
            if !IS_ASSERT_GEN(lgen)
                retract_clause!(gd, ld, cl, cl.generation_erased)
            end
        end

        set_modified(gd, ld, gen_commit)
        tr.clauses = nothing
    end
    return true
end

# PORT: pl-transaction.c transaction_discard
# DIVERGES: the debug messages are not kept; `predicate_update_event` takes `gd` and `ld` and the action as the atom of its name.
"Undo the changes of the (innermost) transaction, raising the rollback events of the predicates that have listeners (pl-transaction.c)."
function transaction_discard(gd::PL_global_data{T}, ld::PL_local_data{T})::Bool where {T}
    rc = true
    tr = ld.transaction
    clauses = tr.clauses
    if clauses !== nothing
        for (cl, lgen) in clauses
            def = cl.predicate
            action = nothing
            if IS_ASSERT_GEN(lgen)
                if (cl.flags & CL_ERASED) == 0
                    cl.generation_erased = GEN_TR_DISCARD_ASSERT
                    cl.generation_created = GEN_TR_DISCARD_ASSERT
                    retract_clause!(gd, ld, cl, cl.generation_created)
                    action = lgen == GEN_ASSERTA ? :asserta : :assertz
                else
                    cl.generation_erased = GEN_TR_DISCARD_ASSERT_ERASE
                    cl.generation_created = GEN_TR_DISCARD_ASSERT_ERASE
                end
            elseif lgen == GEN_NESTED_RETRACT
                cl.generation_erased = tr.gen_max
                action = :retract
            else
                action = :retract
            end

            if def.events !== nothing && action !== nothing && (tr.flags & TR_BULK) == 0
                if !predicate_update_event(
                    gd, ld, def, mk_sym(T, action), cl, P_EVENT_ROLLBACK
                )
                    rc = false
                end
            end
        end
        tr.clauses = nothing
        tr.predicates = nothing
    end
    return rc
end

# PORT: pl-transaction.c merge_clause_tables
# DIVERGES: no reference counts: a clause new in the outer table and one already there are both stored.
"Merge the changed clauses of a nested transaction into its parent's table (pl-transaction.c)."
function merge_clause_tables(
    into::Dict{Clause{T}, tr_gen_t}, from::Dict{Clause{T}, tr_gen_t}
)::Nothing where {T}
    for (cl, v) in from
        into[cl] = v
    end
    return nothing
end

# PORT: pl-transaction.c merge_pred_tables
"Merge the changed predicates of a nested transaction into its parent's table, adding the flags it had (pl-transaction.c)."
function merge_pred_tables(
    into::Dict{Definition{T}, tr_gen_t}, from::Dict{Definition{T}, tr_gen_t}
)::Nothing where {T}
    for (def, lgen) in from
        lgen0 = get(into, def, tr_gen_t(0))
        oflags = VAL_GEN_FLAGS(lgen0)
        into[def] = VAL_ADD_FLAGS(lgen, oflags)
    end
    return nothing
end

# PORT: pl-transaction.c tr_update
"An update of the transaction: the clause and the action, a symbol: `asserta`, `assertz` or `erased` (pl-transaction.c)."
struct tr_update{T}
    clause::Clause{T}
    update::Symbol
end

# PORT: pl-transaction.c update_gen
"The generation an update was made at (pl-transaction.c)."
update_gen(u::tr_update)::gen_t =
    u.update === :erased ? u.clause.generation_erased : u.clause.generation_created

# PORT: pl-transaction.c cmp_updates
"Order two updates by their generation (pl-transaction.c)."
cmp_updates(u1::tr_update, u2::tr_update)::Bool = update_gen(u1) < update_gen(u2)

# PORT: pl-transaction.c is_trie_clause
# DIVERGES: false for every clause: the clauses of `trie_gen_compiled/2,3` are TAB1's (the kernel has no such predicate
# yet); TAB1 TB9 gives it upstream's test.
"True when `cl` is a clause that stands for a trie (pl-transaction.c)."
function is_trie_clause(gd::PL_global_data{T}, cl::Clause{T})::Bool where {T}
    return false
end

# PORT: pl-transaction.c transaction_updates
# DIVERGES: returns the updates, sorted by generation, where upstream fills a `Buffer`; `sort!` is stable where `qsort` is not,
# which no result sees: the generations of the updates are different.
"The updates (asserts and erases) of the transaction, in the order they were made (pl-transaction.c)."
function transaction_updates(
    gd::PL_global_data{T}, ld::PL_local_data{T}
)::Vector{tr_update{T}} where {T}
    b = tr_update{T}[]
    clauses = ld.transaction.clauses
    if clauses !== nothing
        for (cl, lgen) in clauses
            if IS_ASSERT_GEN(lgen)
                if (cl.flags & CL_ERASED) == 0
                    push!(b, tr_update{T}(cl, lgen == GEN_ASSERTA ? :asserta : :assertz))
                end
            elseif !is_trie_clause(gd, cl)
                push!(b, tr_update{T}(cl, :erased))
            end
        end
        sort!(b; lt=cmp_updates)
    end
    return b
end

# PORT: pl-transaction.c announce_updates
"Raise the update events of the listed updates in order; false when a listener raised (pl-transaction.c)."
function announce_updates(
    gd::PL_global_data{T}, ld::PL_local_data{T}, updates::Vector{tr_update{T}}
)::Bool where {T}
    for u in updates
        def = u.clause.predicate
        if !predicate_update_event(gd, ld, def, mk_sym(T, u.update), u.clause, UInt32(0))
            return false
        end
    end
    return true
end


# ── the Prolog connection (TX1b) ────────────────────────────────────────────────────────────────

# PORT: pl-transaction.c transaction
# DIVERGES: `constraint` is 0 for upstream's NULL and `lock` is not examined (no mutex table, see the header); NOT PORTED,
# owner TAB1 TB9: `transaction_commit_tables`, `transaction_rollback_tables`, `merge_tabling_trail`. The outermost transaction
# does not set `LD->transaction.flags` (upstream's does not either, pl-transaction.c:620-630): `bulk(true)` there only
# makes the commit announce the updates. The thread id of the generation space is 1 (`int tid = 1`, the form of the
# source without threads; swipl's main thread is 1 too).
"""
    transaction(gd, ld, goal, constraint, lock, flags) -> Bool

Run `goal` in a transaction (pl-transaction.c): nested inside the running one when there is one, else in a new generation
space. `flags` is `TR_TRANSACTION` (commit when `goal` — and `constraint`, when not 0 — succeed), `TR_SNAPSHOT` (always
discard), with `TR_BULK` (raise the update events when the transaction commits, in generation order).
"""
function transaction(
    gd::PL_global_data{T}, ld::PL_local_data{T}, goal::term_t, constraint::term_t,
    lock::term_t, flags::UInt32
)::Bool where {T}
    tr = ld.transaction
    updates = tr_update{T}[]

    if tr.generation != 0                                   # nested transaction
        parent = tr_stack{T}(
            tr.stack, tr.gen_nest, tr.generation, tr.clauses, tr.predicates, tr.id, tr.flags
        )

        tr.clauses = nothing
        tr.predicates = nothing
        tr.id = goal
        tr.stack = parent
        tr.gen_nest = tr.generation
        tr.flags = flags
        rc = callProlog(gd, ld, 0, goal, PL_Q_PASS_EXCEPTION)
        if rc && constraint != 0
            rc = callProlog(gd, ld, 0, constraint, PL_Q_PASS_EXCEPTION)
        end
        discard = true                                      # (the `nested_discard:` label)
        if rc && (flags & TR_TRANSACTION) != 0
            discard = false
            if tr.predicates !== nothing
                if parent.predicates !== nothing
                    merge_pred_tables(parent.predicates, tr.predicates)
                else
                    parent.predicates = tr.predicates
                end
            end

            if tr.clauses !== nothing
                if parent.clauses !== nothing
                    if (flags & TR_BULK) != 0
                        updates = transaction_updates(gd, ld)
                        if !announce_updates(gd, ld, updates)
                            discard = true                  # goto nested_discard
                        end
                    end
                    if !discard
                        merge_clause_tables(parent.clauses, tr.clauses)
                    end
                else
                    parent.clauses = tr.clauses
                end
            end
        end
        if discard
            rc = transaction_discard(gd, ld) && rc
            tr.generation = parent.generation
        end
        tr.gen_nest = parent.gen_nest
        tr.clauses = parent.clauses
        tr.predicates = parent.predicates
        tr.stack = parent.parent
        tr.id = parent.id
        tr.flags = parent.flags
    else
        tid = gen_t(1)                                      # int tid = 1: no threads
        tr.gen_start = global_generation(gd)
        tr.gen_base = GEN_TRANSACTION_BASE + tid * GEN_TRANSACTION_SIZE
        tr.gen_max = tr.gen_base + GEN_TRANSACTION_SIZE - gen_t(6)
        tr.generation = tr.gen_base
        tr.id = goal
        rc = callProlog(gd, ld, 0, goal, PL_Q_PASS_EXCEPTION)
        if rc && (flags & TR_TRANSACTION) != 0
            if constraint != 0
                tr.gen_start = global_generation(gd)
                rc = callProlog(gd, ld, 0, constraint, PL_Q_PASS_EXCEPTION)
            end
            if rc && (flags & TR_BULK) != 0
                updates = transaction_updates(gd, ld)
                rc = announce_updates(gd, ld, updates)
            end
            if rc
                rc = transaction_commit(gd, ld)             # transaction_commit_tables() && transaction_commit()
            else
                tr.generation = 0                           # avoid recording the rollback
                transaction_discard(gd, ld)
            end
        else
            tr.generation = 0                               # avoid recording the rollback
            rc = transaction_discard(gd, ld) && rc
        end
        tr.id = 0
        tr.generation = 0
        tr.gen_max = 0
        tr.gen_base = GEN_INFINITE
        tr.gen_start = 0
        tr.flags = 0
    end

    return rc
end

# PORT: pl-transaction.c transaction_options
"The options of `\$transaction/2`: `bulk(Bool)` (pl-transaction.c)."
const transaction_options = (PL_option_t(:bulk, OPT_BOOL),)

# PORT: pl-transaction.c transaction as pl_transaction2_va
# (PRED_IMPL("$transaction", 2, transaction, PL_FA_TRANSPARENT), pl-transaction.c:677-691)
"`'\$transaction'(:Goal, +Options)`: run `Goal` in a transaction, `bulk(true)` raising the events at the commit (pl-transaction.c)."
function pl_transaction2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    flags = TR_TRANSACTION

    vals = PL_scan_options(ld, A2, 0, "transaction_option", transaction_options)
    vals === nothing && return FFALSE
    if vals[1] === true
        flags |= TR_BULK
    end

    return transaction(_query_gd(ld), ld, A1, 0, 0, flags) ? FTRUE : FFALSE
end

# PORT: pl-transaction.c transaction as pl_transaction3_va
# (PRED_IMPL("$transaction", 3, transaction, PL_FA_TRANSPARENT), pl-transaction.c:692-697)
"`'\$transaction'(:Goal, :Constraint, +Mutex)`: run `Goal` and then `Constraint` in a transaction (pl-transaction.c)."
function pl_transaction3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2, A3 = PL__t0, PL__t0 + 1, PL__t0 + 2

    return transaction(_query_gd(ld), ld, A1, A2, A3, TR_TRANSACTION) ? FTRUE : FFALSE
end

# PORT: pl-transaction.c snapshot as pl_snapshot1_va
# (PRED_IMPL("$snapshot", 1, snapshot, PL_FA_TRANSPARENT), pl-transaction.c:699-704)
"`'\$snapshot'(:Goal)`: run `Goal` in a transaction that is always discarded (pl-transaction.c)."
function pl_snapshot1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0

    return transaction(_query_gd(ld), ld, A1, 0, 0, TR_SNAPSHOT) ? FTRUE : FFALSE
end

# PORT: pl-transaction.c add_update
"Add `action(ClauseRef)` to the open list `tail` (pl-transaction.c)."
function add_update(
    gd::PL_global_data{T}, ld::PL_local_data{T}, cl::Clause{T}, action::Symbol,
    tail::term_t, head::term_t, tmp::term_t
)::Bool where {T}
    return PL_put_clref(gd, ld, tmp, cl) &&
           PL_cons_functor(ld, tmp, _err_functor(ld, action, 1), tmp) &&
           PL_unify_list(ld, tail, head, tail) &&
           PL_unify(ld, head, tmp)
end

# PORT: pl-transaction.c transaction_updates as pl_transaction_updates1_va
# (PRED_IMPL("transaction_updates", 1, transaction_updates, 0), pl-transaction.c:770-796)
"`transaction_updates(-Updates)`: the clause references the running transaction changed, as `asserta/1`, `assertz/1` and `erased/1` terms in order (pl-transaction.c)."
function pl_transaction_updates1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    gd = _query_gd(ld)

    if ld.transaction.generation == 0
        return FFALSE                                       # error?
    end

    if ld.transaction.clauses !== nothing
        tail = PL_copy_term_ref(ld, A1)
        head = PL_new_term_ref(ld)
        tmp = PL_new_term_ref(ld)
        rc = true

        for u in transaction_updates(gd, ld)
            if !add_update(gd, ld, u.clause, u.update, tail, head, tmp)
                rc = false
                break
            end
        end

        return rc && PL_unify_nil(ld, tail) ? FTRUE : FFALSE
    else
        return PL_unify_nil(ld, A1) ? FTRUE : FFALSE
    end
end

# PORT: pl-transaction.c current_transaction as pl_current_transaction1_va
# (PRED_IMPL("current_transaction", 1, current_transaction, PL_FA_NONDETERMINISTIC|PL_FA_TRANSPARENT), pl-transaction.c:707-768)
# DIVERGES: the redo context is the index of a record of `ld.transaction_enums` (`tr_enum`), freed at the last answer, at a failure and at
# `FRG_CUTTED` (upstream's `default: return true` frees nothing: its context is the stack pointer). `Mark(fli_context->mark)` is `Mark(ld)`
# taken before the loop, as no binding is made between that and the first unification.
"`current_transaction(-Goal)`: the goals of the running transactions, the innermost first (pl-transaction.c); a goal qualified with the context module is given unqualified."
function pl_current_transaction1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    gd = _query_gd(ld)
    pool = ld.transaction_enums
    ctl = PL_foreign_control(PL__ctx)
    m0 = if ld.environment_frame != 0                           # Module m0 = contextModule(environment_frame)
        contextModule(gd, ld, ld.environment_frame)
    else
        MODULE_user(gd).index
    end

    k = 0
    stack = nothing
    id0 = 0
    if ctl == FRG_FIRST_CALL
        ld.transaction.id == 0 && return FFALSE                 # if ( !LD->transaction.id ) return false
        id0 = ld.transaction.id
        stack = ld.transaction.stack
    elseif ctl == FRG_REDO
        k = PL_foreign_context_address(PL__ctx)                 # stack = CTX_PTR
        stack = pool.states[k].stack
        id0 = (stack::tr_stack{T}).id
    else
        free_foreign_state!(pool, PL_foreign_context_address(PL__ctx))
        return FTRUE                                            # default: return true
    end

    id = PL_new_term_ref(ld)
    m = Mark(ld)                                                # Mark(fli_context->mark)
    while true
        ok, mm = PL_strip_module(gd, ld, id0, 0, id)
        if !ok
            k != 0 && free_foreign_state!(pool, k)
            return FFALSE
        end
        rc = mm == m0 ? PL_unify(ld, A1, id) : PL_unify(ld, A1, id0)

        if rc
            if stack !== nothing
                if k == 0
                    k = alloc_foreign_state!(pool)
                end
                pool.states[k].stack = stack
                return PL_retry_address(k)                      # ForeignRedoPtr(stack)
            else
                k != 0 && free_foreign_state!(pool, k)
                return FTRUE
            end
        end
        Undo!(ld, m)                                            # Undo(fli_context->mark)

        if stack !== nothing
            id0 = stack.id
            stack = stack.parent
        else
            k != 0 && free_foreign_state!(pool, k)
            return FFALSE
        end
    end
end

# PORT: pl-transaction.c BeginPredDefs as PL_predicates_from_transaction
# DIVERGES: the `O_DEBUG` predicate `pred_generations/1` has no registration (`#ifdef O_DEBUG`, pl-transaction.c:805-837): swipl 10.1.20, the
# oracle, is a release build without it (`existence_error(procedure, pred_generations/1)`), and so is the kernel's registration table.
# `META` is `PL_FA_TRANSPARENT`.
"pl-transaction.c's registration table (`BeginPredDefs(transaction)`): `\$transaction/2,3`, `\$snapshot/1`, `current_transaction/1`, `transaction_updates/1`."
const PL_predicates_from_transaction = (
    PL_extension("\$transaction", 2, pl_transaction2_va, PL_FA_VARARGS | PL_FA_TRANSPARENT),
    PL_extension("\$transaction", 3, pl_transaction3_va, PL_FA_VARARGS | PL_FA_TRANSPARENT),
    PL_extension("\$snapshot", 1, pl_snapshot1_va, PL_FA_VARARGS | PL_FA_TRANSPARENT),
    PL_extension(
        "current_transaction", 1, pl_current_transaction1_va,
        PL_FA_VARARGS | PL_FA_NONDETERMINISTIC | PL_FA_TRANSPARENT
    ),
    PL_extension("transaction_updates", 1, pl_transaction_updates1_va, PL_FA_VARARGS)
)
