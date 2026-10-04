# UPSTREAM: swipl-devel src/pl-proc.c @ bae881a24a3f
# UPSTREAM: swipl-devel src/pl-proc.h @ bae881a24a3f
# CLASS: code
# COPYRIGHT: Copyright (c)  1985-2025, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# PREDICATES AND THEIR CLAUSE LISTS — SWI-Prolog's pl-proc.c, as far as the clause database goes:
# allocating a predicate (`lookupProcedure`); adding a clause (`assertDefinition!`, which stamps
# it with a new generation of the database); retracting one (`retract_clause!`, which only sets
# its erased generation — the LOGICAL UPDATE VIEW: an enumeration started earlier still sees it);
# clause garbage collection, which unlinks erased clauses once no generation in use can see them
# (`pl_garbage_collect_clauses!`, `cleanDefinition!`, the dirty-definition records `ddi_*`); and
# the predicates `retract/1` and `retractall/1`.
#
# The database is a `PL_global_data` (`gd`, upstream's GD) and a `PL_local_data` (`ld`, LD),
# passed explicitly (src/pl-global.jl).
#
# UNIFICATION is not ported yet (the `unify` subsystem). Where `retract/1` and `retractall/1`
# unify a clause with their argument (`decompile`, `decompileHead`), the caller passes that test
# as a function; their control flow — the enumeration, the generations, the retracting — is
# upstream's. Answers go to a SINK, the kernel's model of nondeterminism: called per answer, it
# returns false to cut.
#
# NOT PORTED: abolish/reload (`removeClausesPredicate`, `resetProcedure`), transactions, update
# events, the clause GC thread and its trigger (`considerClauseGC`: clause GC runs when
# `pl_garbage_collect_clauses!` is called), memory accounting and reclamation (the garbage
# collector's), statistics and the debug checks.

# PORT: pl-proc.c lookupProcedure
# DIVERGES: the functor is its two parts, the name's `sym_key` and the arity (there is no functor
# table). No `resetProcedure`: for a NEW procedure it only sets the debugger's `TRACE_ME`, which is
# not ported (abolish, its other caller, is not ported either). No program-space limit, statistics
# or lock: there are no threads, so the table cannot gain the functor between the lookup and the add.
"""
    lookupProcedure(name, arity, m) -> Procedure{T}

The procedure `name/arity` (`name` the `sym_key` of its name) of module `m`: the one in its
procedure table, or a new one with a new predicate — no clauses, flags 0, its per-argument
information allocated (zeroed) when it has arguments — added to the table (pl-proc.c).
"""
function lookupProcedure(name::UInt64, arity::Int, m::module_t{T})::Procedure{T} where {T}
    proc = get(m.procedures, (name, arity), nothing)
    proc === nothing || return proc
    clauses = ClauseList{T}()
    if arity > 0
        clauses.args = [arg_info() for _ in 1:arity]
    else
        clauses.args = nothing
    end
    def = Definition{T}(name, arity, clauses, UInt64(0))
    proc = Procedure{T}(def, UInt32(0))
    m.procedures[(name, arity)] = proc
    return proc
end

# PORT: pl-proc.c isCurrentProcedure
# DIVERGES: the functor is its name's `sym_key` and its arity.
"The procedure `name/arity` of module `m`, or `nothing` if `m` has none (pl-proc.c)."
function isCurrentProcedure(
    name::UInt64, arity::Int, m::module_t{T}
)::Union{Nothing, Procedure{T}} where {T}
    return get(m.procedures, (name, arity), nothing)
end

# PORT: pl-proc.c hasClausesDefinition
# DIVERGES: no `acquire_def`/`release_def` around the walk — with no threads, clause GC cannot run
# during it — and no reload generation (`LD->reload.generation` is always `GEN_INVALID`: reloading
# is not ported). Foreign and thread-local predicates do not exist, so the `P_FOREIGN|P_THREAD_LOCAL`
# test is upstream's and always passes.
"""
The first clause reference of `def` whose clause is visible in the current generation of the
database `gd` — the first clause at all for a static predicate not registered as dirty — or
`nothing` (pl-proc.c).
"""
function hasClausesDefinition(
    gd::PL_global_data{T}, def::Definition{T}
)::Union{Nothing, ClauseRef{T}} where {T}
    if (def.flags & (P_FOREIGN | P_THREAD_LOCAL)) == 0 &&
        def.impl_clauses.first_clause !== nothing
        if (def.flags & P_DIRTYREG) == 0 && (def.flags & P_DYNAMIC) == 0
            return def.impl_clauses.first_clause
        else
            generation = global_generation(gd)
            c = def.impl_clauses.first_clause
            while c !== nothing
                cl = c.clause::Clause{T}
                visibleClauseCNT(cl, generation) && break
                c = c.next
            end
            return c
        end
    end
    return nothing
end

# PORT: pl-proc.c isDefinedProcedure
"""
Whether `proc` is defined in the database `gd`: a flag in `PROC_DEFINED` (dynamic, multifile, …)
or a visible clause (pl-proc.c).
"""
function isDefinedProcedure(gd::PL_global_data{T}, proc::Procedure{T})::Bool where {T}
    def = proc.definition
    (def.flags & PROC_DEFINED) != 0 && return true
    return hasClausesDefinition(gd, def) !== nothing
end

# PORT: pl-proc.c setDynamicDefinition
# DIVERGES: no lock (no threads), and upstream's `setDynamicDefinition_unlocked` is inlined. The
# `protect_static_code` flag is not ported — it is false by default, so making a static predicate
# with clauses dynamic is allowed, as in a default swipl. `freeCodesDefinition` (back to
# `S_VIRGIN`) is not ported: supervisors arrive with the VM (V4a).
"""
    setDynamicDefinition!(def, isdyn) -> Bool

Make `def` dynamic (`:- dynamic`) or static: set or clear `P_DYNAMIC` and `P_TRANSACT`
(pl-proc.c). Returns true.
"""
function setDynamicDefinition!(def::Definition, isdyn::Bool)::Bool
    if (isdyn && (def.flags & P_DYNAMIC) != 0) || (!isdyn && (def.flags & P_DYNAMIC) == 0)
        return true
    end
    if isdyn                                            # static --> dynamic
        def.flags |= P_DYNAMIC | P_TRANSACT
    else                                                # dynamic --> static
        def.flags &= ~(P_DYNAMIC | P_TRANSACT)
    end
    return true
end

# PORT: pl-proc.c newClauseRef
"A clause reference to `clause` with index key `key` (pl-proc.c)."
newClauseRef(clause::Clause{T}, key::word) where {T} =
    ClauseRef{T}(nothing, key, clause, nothing)

# PORT: pl-proc.c assertDefinition
# DIVERGES: no events, transactions or SSU clauses; no supervisor to reset (`freeCodesDefinition`)
# — the caller runs `reconsiderIndexes!` and `update_primary_index!` before the next call of a
# static predicate, as upstream's `setDefaultSupervisor` does.
"""
    assertDefinition!(gd, def, clause, where_) -> ClauseRef

Add `clause` to predicate `def` — at its start (`CL_START`), its end (`CL_END`) or before the
clause reference `where_` — keyed on the primary index, add it to the predicate's indexes, and
make it visible from a new generation of the database on (pl-proc.c).
"""
function assertDefinition!(
    gd::PL_global_data{T}, def::Definition{T}, clause::Clause{T},
    where_::Union{Int, ClauseRef{T}}
)::ClauseRef{T} where {T}
    key = argKey(Code(clause, 1), Int(def.impl_clauses.primary_index))
    cref = newClauseRef(clause, key)
    clause.generation_created = max_generation(def)    # invisible while it is linked in
    clause.generation_erased = gen_t(1)
    cl = def.impl_clauses
    if cl.last_clause === nothing
        cl.first_clause = cl.last_clause = cref
    elseif where_ === CL_START || where_ === cl.first_clause
        cref.next = cl.first_clause
        cl.first_clause = cref
    elseif where_ === CL_END
        last = cl.last_clause::ClauseRef{T}
        last.next = cref
        cl.last_clause = cref
    else                                # insert before
        cr = cl.first_clause
        while cr !== nothing
            if cr.next === where_
                cref.next = where_::ClauseRef{T}
                cr.next = cref
                break
            end
            cr = cr.next
        end
        @assert cr !== nothing
    end
    cl.number_of_clauses += 1
    if (clause.flags & UNIT_CLAUSE) == 0
        cl.number_of_rules += 1
    end
    addClauseToIndexes!(def, clause, where_)
    gd._generation += 1                                 # PL_LOCK(L_GENERATION)
    clause.generation_created = gd._generation
    clause.generation_erased = max_generation(def)
    return cref
end

# PORT: pl-proc.c retract_clause
# DIVERGES: no transactions, statistics, breakpoints or incremental-tabling notification.
"""
    retract_clause!(gd, clause, generation) -> Bool

Retract `clause`: it becomes invisible from `generation` on — or, given 0, from a new generation
of the database. False when it was already retracted (pl-proc.c).
"""
function retract_clause!(
    gd::PL_global_data{T}, clause::Clause{T}, generation::gen_t
)::Bool where {T}
    def = clause.predicate
    if generation != 0
        if clause.generation_erased > generation
            clause.generation_erased = generation
        end
    else
        if clause.generation_erased >= gd._generation  # PL_LOCK(L_GENERATION)
            egen = gd._generation + 1
            clause.generation_erased = egen
            gd._generation = egen
        end
    end
    if (clause.flags & CL_ERASED) != 0
        return false
    end
    clause.flags |= CL_ERASED
    deleteActiveClauseFromIndexes!(def, clause)        # just updates "dirtyness"
    def.impl_clauses.number_of_clauses -= 0x00000001
    def.impl_clauses.erased_clauses += 1
    if (clause.flags & UNIT_CLAUSE) == 0
        def.impl_clauses.number_of_rules -= 0x00000001
    end
    registerDirtyDefinition!(gd, def)
    return true
end

# PORT: pl-proc.c retractClauseDefinition
# DIVERGES: no update events (`notify` is kept for the signature) and no transactions.
"Retract `clause` of `def` (pl-proc.c): erase/1, retract/1 and retractall/1 come through here."
retractClauseDefinition!(
    gd::PL_global_data{T}, def::Definition{T}, clause::Clause{T}, notify::Bool
) where {T} = retract_clause!(gd, clause, gen_t(0))

# PORT: pl-proc.c find_prev
"The clause reference before `cref` in `def`'s clause list; `prev` is the likely one (pl-proc.c)."
function find_prev(
    def::Definition{T}, prev::Union{Nothing, ClauseRef{T}}, cref::ClauseRef{T}
)::Union{Nothing, ClauseRef{T}} where {T}
    if (prev === nothing && def.impl_clauses.first_clause === cref) ||
        (prev !== nothing && prev.next === cref)
        return prev
    end
    p = def.impl_clauses.first_clause
    while p !== nothing
        if p.next === cref
            return p
        end
        p = p.next
    end
    @assert false "find_prev: clause reference not in the clause list"
    return nothing
end

# PORT: pl-proc.c cleanDefinition
# DIVERGES: no transactions (`tr_starts`), no debugger call-back (`announceErasedClause`), and the
# unlinked references are left to the garbage collector (upstream lingers them) — an unlinked
# reference keeps its `next`, so an enumeration standing on it continues.
"""
Unlink from `def`'s clause list every erased clause no generation in use can see, then clean its
indexes; the number removed (pl-proc.c).
"""
function cleanDefinition!(
    def::Definition{T}, ddi::dirty_def_info{T}, start::gen_t
)::Int where {T}
    removed = 0
    if mustCleanDefinition(def) && (ddi.flags & DDI_MARKING) != 0
        prev::Union{Nothing, ClauseRef{T}} = nothing
        cref = def.impl_clauses.first_clause
        while cref !== nothing && def.impl_clauses.erased_clauses != 0
            cl = cref.clause::Clause{T}
            if (cl.flags & CL_ERASED) != 0 && ddi_is_garbage(ddi, start, cl)
                prev = find_prev(def, prev, cref)
                if prev === nothing
                    def.impl_clauses.first_clause = cref.next
                    if cref.next === nothing
                        def.impl_clauses.last_clause = nothing
                    end
                else
                    prev.next = cref.next
                    if cref.next === nothing
                        def.impl_clauses.last_clause = prev
                    end
                end
                removed += 1
                def.impl_clauses.erased_clauses -= 1
            else
                prev = cref
            end
            cref = cref.next
        end
        if removed != 0
            cleanClauseIndexes!(def, def.impl_clauses, ddi, start)
        end
    end
    return removed
end

# PORT: pl-proc.c mustCleanDefinition
"True when `def` has erased clauses to collect (pl-proc.c)."
mustCleanDefinition(def::definition)::Bool = def.impl_clauses.erased_clauses > 0

# ── dirty definition info (pl-proc.c) ───────────────────────────────────────────────────────────
# A clause can be collected if it is invisible in all registered access generations. Up to
# PROC_DIRTY_GENS generations are kept one by one; beyond, the record keeps their interval.

# PORT: pl-proc.c ddi_new
"A dirty-definition record for `def`, not yet marking (pl-proc.c)."
ddi_new(def::Definition{T}) where {T} =
    dirty_def_info{T}(0x0000, 0x0000, def, zeros(gen_t, PROC_DIRTY_GENS))

# PORT: pl-proc.c ddi_reset
"Start marking: no access generations recorded (pl-proc.c)."
function ddi_reset!(ddi::dirty_def_info)::Nothing
    ddi.count = 0x0000
    ddi.flags = DDI_MARKING
    return nothing
end

# PORT: pl-proc.c ddi_contains_gen
"True when access generation `access` is already recorded (pl-proc.c)."
function ddi_contains_gen(ddi::dirty_def_info, access::gen_t)::Bool
    if (ddi.flags & DDI_INTERVALS) == 0
        for i in 1:Int(ddi.count)
            if ddi.access[i] == access
                return true
            end
        end
    else
        i = 1
        while i <= Int(ddi.count)
            f = ddi.access[i]
            t = ddi.access[i + 1]
            i += 2
            if access >= f && access <= t
                return true
            end
        end
    end
    return false
end

# PORT: pl-proc.c ddi_to_intervals
"Collapse the recorded generations and `access` into one interval (pl-proc.c)."
function ddi_to_intervals!(ddi::dirty_def_info, access::gen_t)::Nothing
    min = access
    max = access
    for i in 1:Int(ddi.count)
        a = ddi.access[i]
        if a < min
            min = a
        end
        if a > max
            max = a
        end
    end
    ddi.access[1] = min
    ddi.access[2] = max
    ddi.count = 0x0002
    ddi.flags |= DDI_INTERVALS
    return nothing
end

# PORT: pl-proc.c ddi_interval_add_access_gen
"Widen the recorded interval to include `access` (pl-proc.c)."
function ddi_interval_add_access_gen!(ddi::dirty_def_info, access::gen_t)::Nothing
    if access < ddi.access[1]
        ddi.access[1] = access
    end
    if access > ddi.access[2]
        ddi.access[2] = access
    end
    return nothing
end

# PORT: pl-proc.c ddi_add_access_gen
"Record that the predicate is accessed in generation `access`, while marking (pl-proc.c)."
function ddi_add_access_gen!(ddi::dirty_def_info, access::gen_t)::Nothing
    if (ddi.flags & DDI_MARKING) != 0
        if !ddi_contains_gen(ddi, access)
            if (ddi.flags & DDI_INTERVALS) == 0
                if ddi.count < PROC_DIRTY_GENS
                    ddi.count += 0x0001
                    ddi.access[ddi.count] = access
                else
                    ddi_to_intervals!(ddi, access)
                end
            else
                ddi_interval_add_access_gen!(ddi, access)
            end
        end
    end
    return nothing
end

# PORT: pl-proc.c ddi_is_garbage
# DIVERGES: no transactions, so no `tr_starts`: a clause erased at or after `start` is never
# garbage.
"""
True when erased clause `cl` can be collected: erased before clause GC started, and invisible in
every generation the predicate is accessed in (pl-proc.c).
"""
function ddi_is_garbage(ddi::dirty_def_info, start::gen_t, cl::clause)::Bool
    @assert (ddi.flags & DDI_MARKING) != 0
    if cl.generation_erased >= start
        return false
    end
    if (ddi.flags & DDI_INTERVALS) == 0
        for i in 1:Int(ddi.count)
            if GLOBALLY_VISIBLE_CLAUSE(cl, ddi.access[i])
                return false
            end
        end
    else
        @assert ddi.count == 2
        f = ddi.access[1]
        t = ddi.access[2]
        if !(cl.generation_erased < f || cl.generation_created > t)
            return false
        end
    end
    return true
end

# PORT: pl-proc.c ddi_oldest_generation
"The oldest generation the predicate is accessed in; `GEN_MAX` when none (pl-proc.c)."
function ddi_oldest_generation(ddi::dirty_def_info)::gen_t
    oldest = GEN_MAX
    if (ddi.flags & DDI_INTERVALS) == 0
        for i in 1:Int(ddi.count)
            if ddi.access[i] < oldest
                oldest = ddi.access[i]
            end
        end
    else
        i = 1
        while i <= Int(ddi.count)
            f = ddi.access[i]
            if f < oldest
                oldest = f
            end
            i += 2
        end
    end
    return oldest
end

# PORT: pl-proc.c registerDirtyDefinition
# DIVERGES: no clause-GC thread to signal (`considerClauseGC`) — clause GC runs when
# `pl_garbage_collect_clauses!` is called; no dirty-clause statistics.
"Register `def` as having erased clauses (pl-proc.c)."
function registerDirtyDefinition!(
    gd::PL_global_data{T}, def::Definition{T}
)::Nothing where {T}
    if (def.flags & P_DIRTYREG) == 0
        ddi = ddi_new(def)
        if get!(gd.procedures_dirty, def, ddi) === ddi
            def.flags |= P_DIRTYREG
        end
    end
    return nothing
end

# PORT: pl-proc.c unregisterDirtyDefinition
"Forget that `def` has erased clauses (pl-proc.c)."
function unregisterDirtyDefinition!(
    gd::PL_global_data{T}, def::Definition{T}
)::Nothing where {T}
    if haskey(gd.procedures_dirty, def)
        delete!(gd.procedures_dirty, def)
        def.flags &= ~P_DIRTYREG
    end
    return nothing
end

# PORT: pl-proc.c maybeUnregisterDirtyDefinition
# DIVERGES: no erased predicates to destroy (abolish is not ported).
"Unregister `def` when clause GC left it no erased clauses (pl-proc.c)."
function maybeUnregisterDirtyDefinition!(
    gd::PL_global_data{T}, def::Definition{T}
)::Nothing where {T}
    if (def.flags & P_DIRTYREG) != 0 && def.impl_clauses.erased_clauses == 0
        unregisterDirtyDefinition!(gd, def)
    end
    return nothing
end

# PORT: pl-proc.c pl_garbage_collect_clauses
# DIVERGES: no messages, statistics, transactions or lingering references; the predicates a
# running enumeration accesses are those it registered with `pushPredicateAccessObj!`.
"""
    pl_garbage_collect_clauses!(gd, ld) -> Bool

`garbage_collect_clauses/0`: collect every erased clause no generation in use can see — erased
before clause GC started, and invisible to every enumeration still running (pl-proc.c).
"""
function pl_garbage_collect_clauses!(
    gd::PL_global_data{T}, ld::PL_local_data{T}
)::Bool where {T}
    rc = true
    if !isempty(gd.procedures_dirty) && !gd.clauses_cgc_active
        gd.clauses_cgc_active = true
        start_gen = global_generation(gd)
        for ddi in values(gd.procedures_dirty)
            ddi_reset!(ddi)                             # see (*)
        end
        markPredicatesInEnvironments!(ld, gd)
        for (def, ddi) in collect(gd.procedures_dirty)  # maybeUnregister… deletes entries
            if (def.flags & P_FOREIGN) == 0 && def.impl_clauses.erased_clauses > 0
                cleanDefinition!(def, ddi, start_gen)
            end
            maybeUnregisterDirtyDefinition!(gd, def)
        end
        gd.clauses_cgc_active = false
    end
    return rc
end

# PORT: pl-proc.c retract as pl_retract
# DIVERGES: the predicate is given (no module lookup); facts only (no SSU clauses), so the clause is
# unified by its head (`decompileHead!`; upstream `decompile`, whose body side is `true` here). Each
# answer — the retracted clause — is a call of `sink(clause)::Bool` (false to cut) with the bindings
# in place in `ld`, undone when it returns: SWI's foreign frame is rewound after a failed attempt and
# its bindings are undone by backtracking after an answer.
"""
    pl_retract!(gd, ld, def, head, sink)

`retract/1` on dynamic predicate `def` with argument head `head` (pl-proc.c). In the generation
it starts in, unify `head` with each clause in turn; retract each that unifies and call
`sink(clause)` while the bindings hold. A clause someone else retracted first is skipped, and the
enumeration moves to the current generation.
"""
function pl_retract!(
    gd::PL_global_data{T}, ld::PL_local_data{T}, def::Definition{T}, head::T, sink::S
)::Nothing where {T, S}
    if (def.flags & P_FOREIGN) != 0
        error("retract/1: permission_error(modify, static_procedure)")
    end
    if (def.flags & P_DYNAMIC) == 0
        if def.impl_clauses.number_of_clauses > 0       # isDefinedProcedure(proc)
            error("retract/1: permission_error(modify, static_procedure)")
        end
        def.flags |= P_DYNAMIC                          # setDynamicDefinition(def, true)
        return nothing                                  # no clauses
    end
    dref = pushPredicateAccessObj!(ld, gd, def)
    popped = false
    try
        gen = dref.generation                           # setGenerationFrameVal()
        chp = ClauseChoice{T}(nothing, word(0))
        cref = firstClause!(ld, head, gen, def, chp)
        first_call = true                               # CTX_CNTRL == FRG_FIRST_CALL
        while cref !== nothing
            clause = cref.clause::Clause{T}
            m = Mark(ld)                                # PL_open_foreign_frame()
            try
                if decompileHead!(ld, clause, head)
                    if retractClauseDefinition!(gd, def, clause, true) || !first_call
                        if chp.cref === nothing         # deterministic last one
                            popPredicateAccess!(ld, def)
                            popped = true
                            sink(clause)
                            return nothing
                        end
                        sink(clause) || return nothing  # FRG_CUTTED
                        first_call = false              # FRG_REDO
                    else
                        gen = setGenerationFrame(gd, def)
                    end
                end
            finally
                Undo!(ld, m)                            # PL_rewind_foreign_frame(fid)
            end
            cref = nextClause!(ld, chp, head, gen, def)
        end
    finally
        popped || popPredicateAccess!(ld, def)
    end
    return nothing
end

# PORT: pl-proc.c allVars
"True when every argument of the head `head` is a distinct unbound variable (pl-proc.c)."
function allVars(head)::Bool
    seen = Set{UInt64}()
    for i in 2:nchildren(head)
        a = child(head, i)
        if kind(a) !== VAR || var_key(a) in seen
            return false
        end
        push!(seen, var_key(a))
    end
    return true
end

# PORT: pl-proc.c retractall as pl_retractall
# DIVERGES: the predicate is given (no module lookup); no update events. A clause is unified by its
# head (`decompileHead!`) and the bindings are undone before the next (`PL_rewind_foreign_frame`).
"""
    pl_retractall!(gd, ld, def, head) -> Bool

`retractall/1` on predicate `def` (pl-proc.c): retract every clause visible in the generation it
starts in whose head unifies with `head` — all of them, without unifying, when every argument of
`head` is a distinct variable. Leaves no binding behind.
"""
function pl_retractall!(
    gd::PL_global_data{T}, ld::PL_local_data{T}, def::Definition{T}, head::T
)::Bool where {T}
    if (def.flags & P_FOREIGN) != 0
        error("retractall/1: permission_error(modify, static_procedure)")
    end
    if (def.flags & P_DYNAMIC) == 0
        if def.impl_clauses.number_of_clauses > 0       # isDefinedProcedure(proc)
            error("retractall/1: permission_error(modify, static_procedure)")
        end
        def.flags |= P_DYNAMIC                          # setDynamicDefinition(def, true)
        return true                                     # nothing to retract
    end
    allvars = kind(head) === EXPR ? allVars(head) : true
    dref = pushPredicateAccessObj!(ld, gd, def)
    try
        gen = dref.generation
        if allvars
            cref = def.impl_clauses.first_clause
            while cref !== nothing
                cl = cref.clause::Clause{T}
                if visibleClauseCNT(cl, gen)
                    retractClauseDefinition!(gd, def, cl, true)
                end
                cref = cref.next
            end
        else
            chp = ClauseChoice{T}(nothing, word(0))
            cref = firstClause!(ld, head, gen, def, chp)
            while cref !== nothing
                cl = cref.clause::Clause{T}
                m = Mark(ld)
                try
                    if decompileHead!(ld, cl, head)
                        retractClauseDefinition!(gd, def, cl, true)
                    end
                finally
                    Undo!(ld, m)                        # PL_rewind_foreign_frame(fid)
                end
                chp.cref === nothing && break
                cref = nextClause!(ld, chp, head, gen, def)
            end
        end
    finally
        popPredicateAccess!(ld, def)
    end
    return true
end

# PORT: pl-proc.h mode_arg_is_unbound
"True when argument `arg0` (0-based) of `def` has mode `-` (pl-proc.h)."
mode_arg_is_unbound(def::definition, arg0::Int)::Bool =
    (def.impl_clauses.args::Vector{arg_info})[arg0 + 1].meta == MA_VAR
