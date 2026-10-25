# UPSTREAM: swipl-devel src/pl-proc.c @ cbf4e1896275
# UPSTREAM: swipl-devel src/pl-proc.h @ cbf4e1896275
# CLASS: code
# COPYRIGHT: Copyright (c)  1985-2025, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# PREDICATES AND THEIR CLAUSE LISTS — SWI-Prolog's pl-proc.c, as far as the clause database goes:
# allocating a predicate (`lookupProcedure`); the checks `assert_term` (src/pl-comp.jl) makes
# before it compiles a clause (`get_head_functor`, `checkModifySystemProc`, since V9c); adding a
# clause (`assertDefinition!`, which stamps it with a new generation of the database); retracting one (`retract_clause!`, which only sets
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
# returns false to cut. Since NF2, `retract/1` is registered as upstream's NON-DETERMINISTIC foreign
# predicate (`pl_retract1_va`, its state in a pool, docs/architecture.md "Non-deterministic built-ins");
# the sink `pl_retract!` stays for its Julia callers until they are re-pointed (audit D-0136 Q3).
#
# NOT PORTED: abolish/reload (`removeClausesPredicate`, `resetProcedure`), transactions, update
# events, the clause GC thread and its trigger (`considerClauseGC`: clause GC runs when
# `pl_garbage_collect_clauses!` is called), memory accounting and reclamation (the garbage
# collector's), statistics and the debug checks.

# PORT: pl-proc.c lookupProcedure
# DIVERGES: the functor is its parts: the name symbol `name` and the arity (there is no functor
# table); the procedure table is keyed by the name's `sym_key`. No `resetProcedure`: for a NEW
# procedure it sets the debugger's `TRACE_ME`, which is not ported (abolish, its other caller, is
# not ported either), and `SUPERVISOR(virgin)`, which the new definition starts with. No
# program-space limit, statistics or lock: there are no threads, so the table cannot gain the
# functor between the lookup and the add.
"""
    lookupProcedure(name, arity, m) -> Procedure{T}

The procedure `name/arity` (`name` a symbol) of module `m`: the one in its procedure table, or a new
one with a new predicate — no clauses, flags 0, its per-argument information allocated (zeroed) when
it has arguments, its supervisor `S_VIRGIN` — added to the table (pl-proc.c).
"""
function lookupProcedure(name::T, arity::Int, m::module_t{T})::Procedure{T} where {T}
    key = sym_key(name)
    proc = get(m.procedures, (key, arity), nothing)
    proc === nothing || return proc
    clauses = ClauseList{T}()
    if arity > 0
        clauses.args = [arg_info() for _ in 1:arity]
    else
        clauses.args = nothing
    end
    cd = m.code_data
    def = Definition{T}(
        key, arity, clauses, UInt64(0), name, cd.virgin, ClauseRef{T}[], cd, 0, m.index
    )
    proc = Procedure{T}(def, UInt32(0), UInt32(0))
    m.procedures[(key, arity)] = proc
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

# PORT: pl-proc.c isStaticSystemProcedure
# DIVERGES: the functor is its name's `sym_key` and its arity, and the `system` module is `gd`'s.
# No `SYSTEM_MODE` test: the kernel has no system mode (no boot compilation), so it is always off;
# the `system` module always exists (`MODULE_system`).
"""
The `system` module's procedure `name/arity` in the database `gd` if it is static and locked — a
built-in — or `nothing` (pl-proc.c).
"""
function isStaticSystemProcedure(
    gd::PL_global_data{T}, name::UInt64, arity::Int
)::Union{Nothing, Procedure{T}} where {T}
    proc = isCurrentProcedure(name, arity, MODULE_system(gd))
    if proc !== nothing && (proc.definition.flags & P_LOCKED) != 0 &&
        (proc.definition.flags & P_DYNAMIC) == 0
        return proc
    end
    return nothing
end

# PORT: pl-proc.c checkModifySystemProc
# DIVERGES: the functor is its name's `sym_key` and its arity; the database `gd` and the local data
# `ld` are arguments (upstream: GD and LD).
"""
    checkModifySystemProc(gd, ld, name, arity) -> Bool

False, with `permission_error(modify, static_procedure, Name/Arity)` raised, when `name/arity` is
an ISO built-in of the database `gd`; true otherwise (pl-proc.c).
"""
function checkModifySystemProc(
    gd::PL_global_data{T}, ld::PL_local_data{T}, name::UInt64, arity::Int
)::Bool where {T}
    proc = isStaticSystemProcedure(gd, name, arity)
    if proc !== nothing && (proc.definition.flags & P_ISO) != 0
        return PL_error(ld, ERR_MODIFY_STATIC_PROC, proc)
    end
    return true
end

# PORT: pl-proc.c getDefinitionProc
# DIVERGES: the database `gd` is an argument; the functor is the definition's name key and arity, its module
# an index into `gd`'s table.
"The procedure of `def`'s functor in `def`'s module (pl-proc.c); asserted to exist."
function getDefinitionProc(
    gd::PL_global_data{T}, def::Definition{T}
)::Procedure{T} where {T}
    proc = isCurrentProcedure(def.functor_name, def.arity, gd.modules[def.module_])
    @assert proc !== nothing "getDefinitionProc: no procedure"
    return proc
end

# PORT: pl-proc.c get_head_functor
# DIVERGES: the functor is returned as its parts — the name and the arity, arity -1 (name `[]`) for
# upstream's false — where upstream writes a `functor_t` (as `PL_get_functor` gives it). A compound
# named by a term that is no symbol (`$expr/n`, the kernel's) has no functor (`PL_get_functor`).
"""
    get_head_functor(ld, head, how) -> (name, arity)

The functor of the clause head in term reference `head` — arity -1 when it has none, the arity is
past `MAXARITY`, or the name is no callable atom: then `type_error(callable, Head)` or
`representation_error(max_procedure_arity)` is raised, unless `how` has `GP_TYPE_QUIET` (pl-proc.c).
"""
function get_head_functor(
    ld::PL_local_data{T}, head::term_t, how::Int
)::Tuple{T, Int} where {T}
    fd = PL_get_functor(ld, head)
    if fd === nothing                                           # !PL_get_functor(head, fdef)
        if (how & GP_TYPE_QUIET) == 0
            PL_error(ld, ERR_TYPE, mk_sym(T, :callable), head)
        end
        return (mk_nil(T), -1)
    end
    name, arity = fd                                            # fd = valueFunctor(*fdef)
    if arity > MAXARITY
        if (how & GP_TYPE_QUIET) == 0
            PL_error(
                ld, "", 0, "limit is $MAXARITY, request = $arity", ERR_REPRESENTATION,
                mk_sym(T, :max_procedure_arity)
            )
        end
        return (mk_nil(T), -1)
    end
    if !isCallableAtom(name)
        if (how & GP_TYPE_QUIET) == 0
            PL_error(ld, ERR_TYPE, mk_sym(T, :callable), head)
        end
        return (mk_nil(T), -1)
    end
    return (name, arity)
end

# PORT: pl-proc.c hasClausesDefinition
# DIVERGES: no `acquire_def`/`release_def` around the walk — with no threads, clause GC cannot run
# during it — and no reload generation (`LD->reload.generation` is always `GEN_INVALID`: reloading
# is not ported). The `P_FOREIGN|P_THREAD_LOCAL` test is upstream's: a built-in is foreign since V5a2, so
# it has no clauses here, as upstream; no predicate is thread-local.
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

# From pl-incl.h `impl.any.defined`: the first word of the definition's implementation — the
# clause list's first clause, or the foreign function — upstream's test "has a body at all".
"Whether `def` has an implementation: a clause, or a foreign function (pl-incl.h `impl.any.defined`)."
_impl_any_defined(def::Definition)::Bool =
    def.impl_foreign_function != 0 || def.impl_clauses.first_clause !== nothing

# PORT: pl-proc.c isDefinedOrAutoloadProcedure
"Whether `proc` is defined, or marked for autoloading, in the database `gd` (pl-proc.c)."
function isDefinedOrAutoloadProcedure(
    gd::PL_global_data{T}, proc::Procedure{T}
)::Bool where {T}
    def = proc.definition
    (def.flags & (PROC_DEFINED | P_AUTOLOAD)) != 0 && return true
    return hasClausesDefinition(gd, def) !== nothing
end

# PORT: pl-proc.c visibleProcedure
# DIVERGES: the functor is its parts (name, arity); the database `gd` is an argument and the super
# modules are indices into its module table.
"The defined procedure `name/arity` visible in module `m`: its own, else the first its super modules see (pl-proc.c)."
function visibleProcedure(
    gd::PL_global_data{T}, name::T, arity::Int, m::module_t{T}
)::Union{Nothing, Procedure{T}} where {T}
    while true
        p = isCurrentProcedure(sym_key(name), arity, m)
        p !== nothing && isDefinedOrAutoloadProcedure(gd, p) && return p
        supers = m.supers
        isempty(supers) && return nothing
        last = length(supers)
        for i in 1:(last - 1)
            r = visibleProcedure(gd, name, arity, gd.modules[supers[i]])
            r !== nothing && return r
        end
        m = gd.modules[supers[last]]                    # goto next: the last super in the loop
    end
end

# PORT: pl-proc.c resolveProcedure
# DIVERGES: the functor is its parts (name, arity); the database `gd` is an argument.
"""
    resolveProcedure(gd, name, arity, m) -> Procedure

The procedure a dynamic call to `name/arity` in `m` runs: the visible one, else an undefined one
created in `m` (pl-proc.c).
"""
function resolveProcedure(
    gd::PL_global_data{T}, name::T, arity::Int, m::module_t{T}
)::Procedure{T} where {T}
    proc = visibleProcedure(gd, name, arity, m)
    proc !== nothing && return proc
    return lookupProcedure(name, arity, m)
end

# PORT: pl-proc.c autoImport
# DIVERGES: the functor is its parts; the database `gd` is an argument and the super modules are
# indices into its module table. The definition replaced in `m`'s procedure is left to Julia's
# garbage collector, where upstream unshares it and frees or lingers it; no lock (no threads).
"""
    autoImport(gd, name, arity, m) -> Definition, or nothing

The definition of `name/arity` visible in module `m`: `m`'s own if it is defined, else a super
module's — LINKED into `m`'s procedure, created if needed — or `nothing` (pl-proc.c).
"""
function autoImport(
    gd::PL_global_data{T}, name::T, arity::Int, m::module_t{T}
)::Union{Nothing, Definition{T}} where {T}
    proc = isCurrentProcedure(sym_key(name), arity, m)
    if proc !== nothing                                 # Defined: no problem
        isDefinedProcedure(gd, proc) && return proc.definition
        (proc.definition.flags & P_AUTOLOAD) != 0 && return nothing
    end
    def::Union{Nothing, Definition{T}} = nothing
    for s in m.supers
        def = autoImport(gd, name, arity, gd.modules[s])
        def !== nothing && break                        # goto found
    end
    def === nothing && return nothing
    if proc === nothing                                 # Create header if not there
        proc = lookupProcedure(name, arity, m)
    end
    if proc.definition !== def                          # Nope, we must link the def
        proc.definition = def                           # shareDefinition(def)
    end
    return def
end

# PORT: pl-proc.c trapUndefined
# DIVERGES: the database `gd` is an argument; the module is the definition's index into its table.
# NOT PORTED: the autoloader — the `autoload` flag, `autoLoader` and its retry — as decided since Q-A
# (no autoload), and `GD->bootsession`'s `sysError` (no boot session).
"""
    trapUndefined(gd, def) -> Definition

Resolve the undefined `def`: a definition `autoImport` finds through its module's supers; else
`def` itself, its supervisor `S_UNDEF` unless it is defined otherwise or its module's `unknown`
flag is `fail` (pl-proc.c).
"""
function trapUndefined(gd::PL_global_data{T}, def::Definition{T})::Definition{T} where {T}
    m = gd.modules[def.module_]
    newdef = autoImport(gd, def.name, def.arity, m)     # Auto import
    newdef !== nothing && return newdef
    if (def.flags & PROC_DEFINED) != 0 || getUnknownModule(gd, m) == UNKNOWN_FAIL
        return def                                      # Pred/Module does not want to trap
    end
    createUndefSupervisor(def)                          # No one wants to intercept
    return def
end

# PORT: pl-proc.c setDynamicDefinition
# DIVERGES: no lock (no threads), and upstream's `setDynamicDefinition_unlocked` is inlined. The
# `protect_static_code` flag is not ported — it is false by default, so making a static predicate
# with clauses dynamic is allowed, as in a default swipl.
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
        freeCodesDefinition!(def, true)                 # reset to S_VIRGIN
    else                                                # dynamic --> static
        def.flags &= ~(P_DYNAMIC | P_TRANSACT)
        freeCodesDefinition!(def, true)                 # reset to S_VIRGIN
    end
    return true
end

# PORT: pl-proc.c newClauseRef
"A clause reference to `clause` with index key `key` (pl-proc.c)."
newClauseRef(clause::Clause{T}, key::word) where {T} =
    ClauseRef{T}(nothing, key, clause, nothing)

# PORT: pl-proc.c setLastModifiedPredicate as setLastModifiedPredicate!
# DIVERGES: only the module's `last_modified` (the definition has no such field), no wakeup of waiting threads, no
# transaction generations (`gen < GEN_TRANSACTION_BASE` always).
"Record that a clause of `def` was added or erased at generation `gen`: the module's `last_modified` rises to it (pl-proc.c)."
function setLastModifiedPredicate!(
    gd::PL_global_data{T}, def::Definition{T}, gen::gen_t
)::Nothing where {T}
    m = gd.modules[def.module_]
    if m.last_modified < gen
        m.last_modified = gen
    end
    return nothing
end

# PORT: pl-proc.c assertDefinition
# DIVERGES: no events, transactions or SSU clauses. A caller that selects clauses outside the VM
# (clause/2, retract/1, the index tests) runs `reconsiderIndexes!` and `update_primary_index!` itself
# before the next call of a static predicate, as the VM's `S_VIRGIN` does through
# `setDefaultSupervisor`.
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
    if (def.flags & (P_DYNAMIC | P_LOCKED_SUPERVISOR)) == 0     # see (*) above
        freeCodesDefinition!(def, true)
    end
    addClauseToIndexes!(def, clause, where_)
    gd._generation += 1                                 # PL_LOCK(L_GENERATION)
    clause.generation_created = gd._generation
    clause.generation_erased = max_generation(def)
    setLastModifiedPredicate!(gd, def, clause.generation_created)     # setLastModifiedPredicate(def, …created, TWF_ASSERT)
    return cref
end

# PORT: pl-proc.c assertProcedure as assertProcedure!
# DIVERGES: the database `gd` is an argument (upstream: GD); `getProcDefinition(proc)` is
# `proc.definition` (no thread-local predicates).
"Add `clause` to procedure `proc` at `where_` (pl-proc.c): see [`assertDefinition!`](@ref)."
assertProcedure!(
    gd::PL_global_data{T}, proc::Procedure{T}, clause::Clause{T},
    where_::Union{Int, ClauseRef{T}}
) where {T} = assertDefinition!(gd, proc.definition, clause, where_)

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
    setLastModifiedPredicate!(gd, def, clause.generation_erased)      # …, TWF_RETRACT
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
# unlinked references are left to the garbage collector (upstream lingers them and frees what no
# one uses, `free_lingering`) — an unlinked reference keeps its `next`, so an enumeration standing on
# it continues. No `LOCKDEF` (no threads) and no `rcp` result; the caller sets `cgc_active`, which
# upstream asserts.
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
# DIVERGES: the predicate is given (no module lookup); `retract(Head)` only — its body is `true`, so
# only facts answer (a rule's body is V9's `decompile`) — and no SSU clauses, so the clause is
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
    gd::PL_global_data{T}, ld::PL_local_data{T}, def::Definition{T}, head::term_t, sink::S
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
        cref = firstClause!(ld, _head_argv(ld, def, head), gen, def, chp)
        first_call = true                               # CTX_CNTRL == FRG_FIRST_CALL
        while cref !== nothing
            clause = cref.clause::Clause{T}
            m = Mark(ld)                                # PL_open_foreign_frame()
            try
                # retract(Head) is retract((Head :- true)): a rule's body is not `true`
                if (clause.flags & UNIT_CLAUSE) != 0 && decompileHead!(ld, clause, head)
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
                ld.exception_term != 0 && return nothing   # if ( PL_exception(0) ) break
            finally
                Undo!(ld, m)                            # PL_rewind_foreign_frame(fid)
            end
            cref = nextClause!(ld, chp, _head_argv(ld, def, head), gen, def)
        end
    finally
        popped || popPredicateAccess!(ld, def)
    end
    return nothing
end

# PORT: pl-proc.c allVars
# DIVERGES: on the cells — distinct unbound argument cells after `_deref_loc`, a set of positions
# where upstream marks each variable and unmarks them after; a head that is not a compound (an
# atom) has no argument, so `true`.
"True when every argument of the head term reference `head` is a distinct unbound variable (pl-proc.c)."
function allVars(ld::PL_local_data{T}, head::term_t)::Bool where {T}
    k, w, _ = _deref_loc(ld, -(head + 1))
    (k == DU_WORD && _is_gcompound(w)) || return true
    q = valPtr(w)
    seen = Set{Int}()
    for i in 1:arityFunctor(ld.functors, ld.gstack[q])
        ka, _, p = _deref_loc(ld, q + i)
        if ka != DU_CELL || p in seen
            return false
        end
        push!(seen, p)
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
`head` is a distinct variable. Leaves no binding behind. `false` when an exception is pending (an
occurs-check error from a head), which stops it.
"""
function pl_retractall!(
    gd::PL_global_data{T}, ld::PL_local_data{T}, def::Definition{T}, head::term_t
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
    allvars = allVars(ld, head)
    rc = true
    dref = pushPredicateAccessObj!(ld, gd, def)
    try
        gen = dref.generation
        if allvars
            cref = def.impl_clauses.first_clause
            while cref !== nothing
                cl = cref.clause::Clause{T}
                if visibleClauseCNT(cl, gen)
                    if !retractClauseDefinition!(gd, def, cl, true)
                        ld.exception_term != 0 && break    # if ( PL_exception(0) ) break
                    end
                end
                cref = cref.next
            end
            rc = ld.exception_term == 0                 # ignore plain failures, keep an exception
        else
            chp = ClauseChoice{T}(nothing, word(0))
            cref = firstClause!(ld, _head_argv(ld, def, head), gen, def, chp)
            while cref !== nothing
                cl = cref.clause::Clause{T}
                m = Mark(ld)
                stop = false
                try
                    if decompileHead!(ld, cl, head)
                        if !retractClauseDefinition!(gd, def, cl, true)
                            stop = ld.exception_term != 0   # if ( PL_exception(0) ) break
                        end
                    elseif ld.exception_term != 0
                        rc = false                      # rc = false; break
                        stop = true
                    end
                finally
                    Undo!(ld, m)                        # PL_rewind_foreign_frame(fid)
                end
                stop && break
                chp.cref === nothing && break
                cref = nextClause!(ld, chp, _head_argv(ld, def, head), gen, def)
            end
        end
    finally
        popPredicateAccess!(ld, def)
    end
    return rc
end

# PORT: pl-proc.h mode_arg_is_unbound
"True when argument `arg0` (0-based) of `def` has mode `-` (pl-proc.h)."
mode_arg_is_unbound(def::definition, arg0::Int)::Bool =
    (def.impl_clauses.args::Vector{arg_info})[arg0 + 1].meta == MA_VAR

# ── defining a predicate from a file (pl-proc.c), since R1f ─────────────────────────────────────

# PORT: pl-proc.c overruleImportedProcedure
# DIVERGES: the database `gd` is an argument; a module is an index into its table. NOT PORTED:
# a weak (implicit) import is abolished (`abolishProcedure`) — refused (`NotPortedError`): the
# kernel makes no weak imports (`autoImport` links strongly), so it is not reached.
"""
May `target` define `proc` — its own, or an import it may overrule (pl-proc.c)? Raises
`permission_error(redefine, built_in_procedure | imported_procedure, PI)` when not.
"""
function overruleImportedProcedure(
    gd::PL_global_data{T}, ld::PL_local_data{T}, proc::Procedure{T}, target::module_t{T}
)::Bool where {T}
    def = proc.definition                   # we do *not* want a thread-local version
    if (def.flags & P_AUTOLOAD) != 0
        return PL_error(
            ld, ERR_PERMISSION_PROC, mk_sym(T, :redefine), mk_sym(T, :imported_procedure),
            proc
        )
    end
    def.module_ == target.index && return true
    if (gd.modules[def.module_].flags & M_SYSTEM) != 0
        return PL_error(
            ld, ERR_PERMISSION_PROC, mk_sym(T, :redefine), mk_sym(T, :built_in_procedure),
            proc
        )
    elseif (proc.flags & PROC_WEAK) != 0
        throw(
            NotPortedError{T}(def.name, "overruling a weak import (abolishProcedure)", "R2")
        )
    end
    return PL_error(
        ld, ERR_PERMISSION_PROC, mk_sym(T, :redefine), mk_sym(T, :imported_procedure), proc
    )
end

# `Name/Arity` of `def` in a new term reference, as `PL_unify_term`'s `_PL_PREDICATE_INDICATOR` makes it
# (`unify_definition`, GP_HIDESYSTEM; on the cells since f3b-4).
function _redefine_indicator(
    gd::PL_global_data{T}, ld::PL_local_data{T}, def::Definition{T}
)::term_t where {T}
    t = new_term_ref(ld)
    unify_definition(gd, ld, MODULE_user(gd), t, def, 0, GP_HIDESYSTEM | GP_NAMEARITY)
    return t
end


# PORT: pl-proc.c redefineProcedure
# DIVERGES: the database `gd` is an argument; the warnings go to `printMessage`. No reload context
# (a first load). NOT PORTED, refused (`NotPortedError`): abolishing a definition another file — or
# C — made (`abolishProcedure`: a second file defining a predicate, a foreign predicate redefined),
# after its warning; a thread-local predicate (no threads).
"""
`proc` is about to get a clause from the source file `sf`, which owns the definition: warn of a
discontiguous predicate or a redefinition, as the style checks ask (pl-proc.c). True to go on.
"""
function redefineProcedure(
    gd::PL_global_data{T}, ld::PL_local_data{T}, proc::Procedure{T}, sf::SourceFile{T},
    suppress::Int
)::Bool where {T}
    def = proc.definition

    if (def.flags & P_FOREIGN) != 0
        # first call printMessage() so we can provide info about the old definition
        printMessage(                               # PL_FUNCTOR_CHARS, "redefined_procedure", 2,
            ld, :warning,                           #   PL_CHARS, "foreign", _PL_PREDICATE_INDICATOR
            _message_term(
                ld, :redefined_procedure, _err_atom(ld, mk_sym(T, :foreign)),
                _redefine_indicator(gd, ld, def)
            )
        ) || return false
        throw(
            NotPortedError{T}(
                def.name, "redefining a foreign predicate (abolishProcedure)", "R2"
            )
        )
    elseif (def.flags & P_MULTIFILE) == 0
        first = hasClausesDefinition(gd, def)       # def = getLocalProcDefinition(def)
        first === nothing && return true            # (*) see above

        cl = first.clause::Clause{T}
        if cl.owner_no == sf.index
            # sf->reload: never (no reload context)
            if ((ld.debugstatus_styleCheck & ~suppress) & DISCONTIGUOUS_STYLE) != 0 &&
                (def.flags & P_DISCONTIGUOUS) == 0 && sf.current_procedure !== nothing
                cur = (sf.current_procedure::Procedure{T}).definition
                printMessage(                       # PL_FUNCTOR_CHARS, "discontiguous", 2,
                    ld, :warning,                   #   _PL_PREDICATE_INDICATOR ×2
                    _message_term(
                        ld, :discontiguous, _redefine_indicator(gd, ld, def),
                        _redefine_indicator(gd, ld, cur)
                    )
                ) || return false
            end
        elseif !hasProcedureSourceFile(sf, proc)
            if (def.flags & P_THREAD_LOCAL) != 0
                throw(NotPortedError{T}(def.name, "a thread-local predicate", "no threads"))
            end
            printMessage(                           # PL_FUNCTOR_CHARS, "redefined_procedure", 2,
                ld, :warning,                       #   PL_CHARS, "static", _PL_PREDICATE_INDICATOR
                _message_term(
                    ld, :redefined_procedure, _err_atom(ld, mk_sym(T, :static)),
                    _redefine_indicator(gd, ld, def)
                )
            ) || return false
            # again, _after_ the printMessage()
            throw(
                NotPortedError{T}(
                    def.name,
                    "redefining a predicate another file defined (abolishProcedure)",
                    "R2"
                )
            )
        end
    end
    return true
end

# PORT: pl-proc.c lookupProcedureToDefine
# DIVERGES: the functor is its parts (name, arity); the database `gd` is an argument.
"The procedure `name/arity` of `m` to give a definition, or `nothing` with the error raised (pl-proc.c)."
function lookupProcedureToDefine(
    gd::PL_global_data{T}, ld::PL_local_data{T}, name::T, arity::Int, m::module_t{T}
)::Union{Nothing, Procedure{T}} where {T}
    proc = isCurrentProcedure(sym_key(name), arity, m)
    if proc !== nothing
        overruleImportedProcedure(gd, ld, proc, m) || return nothing
        return proc
    end
    checkModifySystemProc(gd, ld, sym_key(name), arity) &&
        return lookupProcedure(name, arity, m)
    return nothing
end

# PORT: pl-proc.c patt_masks
"The predicate attributes `'\$set_predicate_attribute'/3` sets, by name (pl-proc.c)."
const patt_masks = (
    (:dynamic, P_DYNAMIC), (:transact, P_TRANSACT), (:multifile, P_MULTIFILE),
    (:locked, P_LOCKED), (:system, P_LOCKED), (:spy, SPY_ME), (:trace, TRACE_ME),
    (:hide_childs, HIDE_CHILDS), (:transparent, P_TRANSPARENT),
    (:discontiguous, P_DISCONTIGUOUS), (:volatile, P_VOLATILE),
    (:thread_local, P_THREAD_LOCAL),
    (:noprofile, P_NOPROFILE), (:iso, P_ISO), (:public, P_PUBLIC),
    (:non_terminal, P_NON_TERMINAL), (:quasi_quotation_syntax, P_QUASI_QUOTATION_SYNTAX),
    (:clausable, P_CLAUSABLE), (:autoload, P_AUTOLOAD), (:ssu, P_SSU_DET), (:det, P_DET),
    (:sig_atomic, P_SIG_ATOMIC)
)

# PORT: pl-proc.c attribute_mask
# DIVERGES: the key is an atom term; the domain error's culprit is put in a new term reference.
"The mask of the predicate attribute `key`, or 0 with `domain_error(predicate_property, Key)` (pl-proc.c)."
function attribute_mask(ld::PL_local_data{T}, key::T)::UInt64 where {T}
    for (k, mask) in patt_masks
        sym_key(key) == sym_key(mk_sym(T, k)) && return mask
    end
    t = PL_new_term_ref(ld)
    setSlotValue!(ld, t + 1, key)
    PL_domain_error(ld, "predicate_property", t)
    return UInt64(0)
end

# PORT: pl-proc.c get_bool_or_int_ex
# DIVERGES: returns the value, or `nothing` with the error raised, where upstream writes it
# through `val`.
"`true`/`on`/1 → 1, `false`/`off`/0 → 0; else `nothing` with `type_error(bool, T)` (pl-proc.c)."
function get_bool_or_int_ex(ld::PL_local_data{T}, t::term_t)::Union{Nothing, Int} where {T}
    b = PL_get_bool(ld, t)
    b === nothing || return Int(b)                  # if ( PL_get_bool(t, val) ) return true
    v = PL_get_integer(ld, t)
    v !== nothing && (v & ~1) == 0 && return v      # accept 0 and 1
    b = PL_get_bool_ex(ld, t)                       # generate an error
    return b === nothing ? nothing : Int(b)
end

# PORT: pl-proc.c get_procedure
# DIVERGES: the `GP_DEFINE` path only (the one `'$set_predicate_attribute'/3` asks for): the term
# stripped of its module, its functor from a head or a `Name/Arity` (`get_functor`), and
# `lookupProcedureToDefine` in that module (which exists: no module is created).
"The procedure the term `descr` (`M:Head` or `M:Name/Arity`) names, to define (pl-proc.c)."
function get_procedure(
    gd::PL_global_data{T}, ld::PL_local_data{T}, descr::term_t, how::Int
)::Union{Nothing, Procedure{T}} where {T}
    (how & GP_HOW_MASK) == GP_DEFINE || throw(
        NotPortedError{T}(
            mk_sym(T, :get_procedure), "get_procedure: other than GP_DEFINE", "V9"
        )
    )
    head = PL_new_term_ref(ld)
    ok, m = PL_strip_module(gd, ld, descr, 0, head)
    ok || return nothing
    if PL_is_functor(ld, head, mk_sym(T, :/), 2)        # PL_is_functor(head, FUNCTOR_divide2)
        a = PL_new_term_ref(ld)
        _PL_get_arg(ld, 1, head, a)
        name = PL_get_atom_ex(ld, a)                    # PL_get_atom_ex(a, &name)
        name === nothing && return nothing
        _PL_get_arg(ld, 2, head, a)
        arity = PL_get_integer_ex(ld, a)                # get_arity(a, …): PL_get_integer_ex
        arity === nothing && return nothing
        if arity < 0
            PL_error(ld, ERR_DOMAIN, mk_sym(T, :not_less_than_zero), a)
            return nothing
        end
    else
        name, arity = get_head_functor(ld, head, 0)
        arity < 0 && return nothing
    end
    return lookupProcedureToDefine(gd, ld, name, arity, gd.modules[m])
end

# PORT: pl-proc.c set_predicate_attribute as pl_set_predicate_attribute3_va
# (PRED_IMPL("$set_predicate_attribute", 3, set_predicate_attribute, PL_FA_TRANSPARENT))
# DIVERGES: no tabling attributes (`tbl_is_predicate_attribute`: refused, as is `spy`, which needs
# `GP_RESOLVE`); `ReadingSource` is `LD->read_source`'s file and line (src/pl-modul.jl), `MODULE_parse` the source
# module while reading, else the typein module.
"`'\$set_predicate_attribute'(:Head, +Key, +Value)` (pl-proc.c): set a predicate attribute."
function pl_set_predicate_attribute3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    gd = _query_gd(ld)
    pred, what, value = PL__t0, PL__t0 + 1, PL__t0 + 2

    key = PL_get_atom_ex(ld, what)
    key === nothing && return FFALSE
    val = get_bool_or_int_ex(ld, value)
    val === nothing && return FFALSE
    att = attribute_mask(ld, key)
    att == 0 && return FFALSE

    (att & SPY_ME) != 0 &&
        throw(NotPortedError{T}(key, "spy points (GP_RESOLVE)", "the debugger"))
    proc = get_procedure(gd, ld, pred, GP_DEFINE | GP_NAMEARITY)
    proc === nothing && return FFALSE
    def = proc.definition

    reading = ReadingSource(ld)
    mparse = MODULE_parse(ld)
    if reading && mparse == def.module_
        sf = lookupSourceFile(gd, ld.read_source.file::T, true)::SourceFile{T}
        rc = setAttrProcedureSource(sf, proc, att, val == 1)
        releaseSourceFile(sf)
        return rc ? FTRUE : FFALSE
    else
        return setAttrDefinition(def, att, val == 1) ? FTRUE : FFALSE
    end
end

# PORT: pl-proc.c setAttrDefinition
# DIVERGES: `P_THREAD_LOCAL`, `P_CLAUSABLE` and `P_DET` (their own setters) are refused.
"Set (or clear) attribute `attr` of `def` (pl-proc.c)."
function setAttrDefinition(def::Definition{T}, attr::UInt64, val::Bool)::Bool where {T}
    attr == P_DYNAMIC && return setDynamicDefinition!(def, val)
    (attr == P_THREAD_LOCAL || attr == P_CLAUSABLE || attr == P_DET) && throw(
        NotPortedError{T}(def.name, "setAttrDefinition: attribute $attr", "not ported")
    )
    if val
        def.flags |= attr
    else
        def.flags &= ~attr
    end
    return true
end

# PORT: pl-proc.c get_procedure as get_procedure_create
# (the `GP_CREATE` case, as retractall/1 asks it; the `GP_DEFINE` case above is the other port)
# DIVERGES: `GP_CREATE` only, as a function of its own (`get_procedure` above refuses it); the term stripped of its
# module (`PL_strip_module`, which puts the plain head in `h`), its functor from the head (`get_head_functor`: the
# `callable` type error) and `lookupBodyProcedure` in that module. A qualifier naming no module creates it
# (`PL_strip_module` -> `stripModule_cells`, since MOD1).
"The procedure the head term `descr` (`M:Head`) names, found or created for a body to call (pl-proc.c); `h` holds the plain head."
function get_procedure_create(
    gd::PL_global_data{T}, ld::PL_local_data{T}, descr::term_t, h::term_t
)::Union{Nothing, Procedure{T}} where {T}
    head = PL_new_term_ref(ld)
    ok, m = PL_strip_module(gd, ld, descr, 0, head)
    ok || return nothing
    PL_put_term(ld, h, head)                            # if ( h ) PL_put_term(h, head)
    name, arity = get_head_functor(ld, head, 0)
    arity < 0 && return nothing
    return lookupBodyProcedure(gd, name, arity, gd.modules[m])
end

# PORT: pl-proc.c get_procedure as get_procedure_find
# (the `GP_FIND` case, as clause/2 asks it: `get_procedure(head, &proc, 0, GP_FIND)`)
# DIVERGES: `GP_FIND` without `GP_NAMEARITY`, no `h` and no `GP_EXISTENCE_ERROR`, as a function of its own
# (`get_procedure` above refuses it). The term is stripped of its qualifiers (`stripModuleName_cells`) and
# `get_module`'s `GP_FIND` case is inlined: the module a qualifier names if it is current (`isCurrentModule`:
# none is created), else `user`; no qualifier, the context module, `user` (no `contextModule`). Not found:
# `nothing` with no error, as upstream's `notfound` without `GP_EXISTENCE_ERROR`.
"The defined procedure the head term `descr` (`M:Head`) names, as seen from its module, or `nothing` (pl-proc.c)."
function get_procedure_find(
    gd::PL_global_data{T}, ld::PL_local_data{T}, descr::term_t
)::Union{Nothing, Procedure{T}} where {T}
    head = PL_new_term_ref(ld)
    ok, loc, mname = stripModuleName_cells(ld, -(descr + 1))  # stripModuleName(valTermRef(descr), &mname)
    ok || return nothing
    _slot_link_loc!(ld, head + 1, loc)                  # *valTermRef(head) = linkValNoG(p)
    m = MODULE_user(gd)                                 # get_module(mname, GP_FIND)
    if mname != 0
        cm = isCurrentModule(gd.modules, _atom_value(ld, mname))
        if cm !== nothing                               # isCurrentModule(mname), else MODULE_user
            m = cm
        end
    end
    name, arity = get_head_functor(ld, head, GP_FIND)
    arity < 0 && return nothing
    return visibleProcedure(gd, name, arity, m)         # GP_FIND: found -> out; else notfound
end

# ── retract/1, a non-deterministic foreign predicate (pl-proc.c; NF2, docs/architecture.md) ─────────────
# PORT: pl-proc.c alloc_retract_context as alloc_retract_context!
# DIVERGES: the heap copy is a record of the local data's pool (`ld.retract_contexts`, design D3) and the
# result is its index — the `REDO_PTR` context `PL_retry_address` encodes — where upstream's is the address.
# `*ctx = *ctx0` copies field by field (the record's `chp` is its own).
"Copy the first call's context `ctx0` into a record of retract/1's pool; the record's index (pl-proc.c)."
function alloc_retract_context!(
    ld::PL_local_data{T}, ctx0::retract_context{T}
)::Int where {T}
    k = alloc_foreign_state!(ld.retract_contexts)      # allocForeignState(sizeof(*ctx))
    ctx = ld.retract_contexts.states[k]
    ctx.def = ctx0.def                                  # *ctx = *ctx0
    ctx.chp.cref = ctx0.chp.cref
    ctx.chp.key = ctx0.chp.key
    ctx.allocated = true
    return k
end

# PORT: pl-proc.c free_retract_context as free_retract_context!
# DIVERGES: the context is its record and its pool index `k` (0 for the first call's buffer, which is not
# `allocated`). `leaveDefinition` is a no-op upstream (pl-incl.h:1348).
"Release retract/1's context `ctx` (index `k`): pop its predicate access, free its record if it is one (pl-proc.c)."
function free_retract_context!(
    ld::PL_local_data{T}, ctx::retract_context{T}, k::Int
)::Nothing where {T}
    popPredicateAccess!(ld, ctx.def::Definition{T})
    # leaveDefinition(ctx->def): (void)0 upstream
    if ctx.allocated
        free_foreign_state!(ld.retract_contexts, k)     # freeForeignState(ctx, sizeof(*ctx))
    end
    return nothing
end

# PORT: pl-proc.c retract as pl_retract1_va
# (PRED_IMPL("retract", 1, retract, PL_FA_TRANSPARENT|PL_FA_NONDETERMINISTIC|PL_FA_ISO))
# DIVERGES: the context is a record of `ld.retract_contexts`, its index the `REDO_PTR` context (design D3);
# `ctxbuf`, upstream's C-stack buffer, is the local data's scratch record `ld.retract_ctxbuf` (no Prolog
# runs during a call, so it is never in use twice), and `ctx === ctxbuf` is upstream's `ctx == &ctxbuf`.
# THE CLAUSE TERM IS ITS TWO SIDES (`decompile!`'s convention): upstream builds `cl` — the head when the
# body is `true`, else `Head :- Body` — and `decompile(clause, cl)`; a bare head matches a FACT only
# (`decompile` fails a rule against a term that is no `:-/2`, pl-comp.c:6308), so it is
# `UNIT_CLAUSE && decompileHead!`, and `Head :- Body` is `decompile!(clause, head, body)` (a fact's body
# unifies with `true`, pl-comp.c:6293-6302); `cl` itself is not built. No SSU clauses (`is_neck` refuses
# them), so upstream's `CLAUSE_SSU_FLAGS` test compares two zeros and is not written. The functor and its
# `type_error(callable, Head)` are `get_head_functor`'s (the kernel's `PL_get_functor` takes any word;
# the callable test is upstream's `PL_get_functor`'s). `argv` is the head's argument cells
# (`_head_argv`), read where a search reads it. `protectCRef`/`unprotectCRef` are `(void)0` upstream
# without `O_DEBUG` (pl-proc.c:83-88); no `DEBUG` lines.
"`retract(+Clause)` (pl-proc.c): retract a clause that unifies with `Clause`, one per answer, on backtracking the next."
function pl_retract1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    term = PL__t0
    ctxbuf = ld.retract_ctxbuf
    pool = ld.retract_contexts

    if PL_foreign_control(PL__ctx) == FRG_CUTTED
        k = PL_foreign_context_address(PL__ctx)          # ctx = CTX_PTR
        ctx = pool.states[k]
        # unprotectCRef(ctx->chp.cref): (void)0
        free_retract_context!(ld, ctx, k)
        return FTRUE
    end

    gd = _query_gd(ld)
    fr = ld.environment_frame
    m = 0                                               # Module m = NULL
    cl = PL_new_term_ref(ld)
    head = PL_new_term_ref(ld)
    body = PL_new_term_ref(ld)

    ok, m = PL_strip_module_ex(gd, ld, term, m, cl)
    ok || return FFALSE
    ok, m = get_head_and_body_clause(gd, ld, cl, head, body, m)
    ok || return FFALSE
    bk, bw, _ = _deref_loc(ld, -(body + 1))
    # PL_get_atom(body, &b) && b == ATOM_true: `cl` is the head, else `Head :- Body`
    cl_is_head = bk == DU_WORD && bw == _atom_word!(ld, mk_sym(T, Symbol("true")))

    if PL_foreign_control(PL__ctx) == FRG_FIRST_CALL
        name, arity = get_head_functor(ld, head, 0)     # PL_get_functor(head, &fd), else ERR_TYPE callable
        arity < 0 && return FFALSE
        fd = sym_key(name)
        proc = isCurrentProcedure(fd, arity, gd.modules[m])
        if proc === nothing
            checkModifySystemProc(gd, ld, fd, arity)
            return FFALSE
        end

        def = proc.definition                           # getProcDefinition(proc)

        if (def.flags & P_FOREIGN) != 0
            return PL_error(ld, ERR_MODIFY_STATIC_PROC, proc) ? FTRUE : FFALSE
        end
        if (def.flags & P_DYNAMIC) == 0
            if isDefinedProcedure(gd, proc)
                return PL_error(ld, ERR_MODIFY_STATIC_PROC, proc) ? FTRUE : FFALSE
            end
            setDynamicDefinition!(def, true)            # implicit
            return FFALSE                               # no clauses
        end

        # enterDefinition(def): (void)0 upstream
        dref = pushPredicateAccessObj!(ld, gd, def)
        # D-0147 / D-0100 (asserted invariant; NF2-R6 equivalent, NF2-G1 breaks it)
        @assert(
            dref.generation == generationFrame(ld.frames[fr]),
            "retract: nothing ran between the call and pushPredicateAccessObj!",
        )
        ld.frames[fr].generation = dref.generation      # setGenerationFrameVal(environment_frame, …)
        ctxbuf.chp.cref = nothing
        ctxbuf.chp.key = word(0)
        cref = firstClause!(
            ld, _head_argv(ld, def, head), generationFrame(ld.frames[fr]), def, ctxbuf.chp
        )
        if cref === nothing
            popPredicateAccess!(ld, def)
            # leaveDefinition(def): (void)0
            return FFALSE
        end

        ctx = ctxbuf
        ctx.def = def
        ctx.allocated = false
        k = 0
    else
        k = PL_foreign_context_address(PL__ctx)          # ctx = CTX_PTR
        ctx = pool.states[k]
        def = ctx.def::Definition{T}
        # unprotectCRef(ctx->chp.cref): (void)0
        cref = nextClause!(
            ld, ctx.chp, _head_argv(ld, def, head), generationFrame(ld.frames[fr]), def
        )
    end

    fid = PL_open_foreign_frame(ld)
    if fid == 0
        free_retract_context!(ld, ctx, k)
        return FFALSE
    end

    while cref !== nothing
        clause = cref.clause::Clause{T}

        matched = if cl_is_head                         # decompile(clause, cl, 0)
            (clause.flags & UNIT_CLAUSE) != 0 && decompileHead!(ld, clause, head)
        else
            decompile!(ld, clause, head, body)
        end
        if matched
            if retractClauseDefinition!(gd, def, clause, true) ||
                PL_foreign_control(PL__ctx) != FRG_FIRST_CALL
                if ctx.chp.cref === nothing             # deterministic last one
                    free_retract_context!(ld, ctx, k)
                    PL_close_foreign_frame(ld, fid)
                    return FTRUE
                end

                if ctx === ctxbuf                       # non-determinisic; save state
                    k = alloc_retract_context!(ld, ctx)
                    ctx = pool.states[k]
                end

                # protectCRef(ctx->chp.cref): (void)0
                PL_close_foreign_frame(ld, fid)
                return PL_retry_address(k)              # ForeignRedoPtr(ctx)
            else
                setGenerationFrame(gd, ld, fr)          # the first clause was retracted meanwhile
            end
        end

        PL_exception(ld, 0) != 0 && break

        PL_rewind_foreign_frame(ld, fid)
        cref = nextClause!(
            ld, ctx.chp, _head_argv(ld, def, head), generationFrame(ld.frames[fr]), def
        )
    end

    PL_close_foreign_frame(ld, fid)
    free_retract_context!(ld, ctx, k)
    return FFALSE
end

# PORT: pl-proc.c retractall as pl_retractall1_va
# (PRED_IMPL("retractall", 1, retractall, PL_FA_NONDETERMINISTIC|PL_FA_ISO))
# DIVERGES: registered as a deterministic variadic built-in (the body never leaves a choice point; upstream's
# NONDETERMINISTIC flag only gives it a foreign frame); the work is `pl_retractall!` below (its permission checks are
# the ones here, done first with the Prolog error); no update events (`retractall_event`). Kept deterministic after
# NF1 (audit D-0136 Q6: representation only). RE-CHECK: a `prolog_current_frame/1` or `prolog_current_choice/1` row
# around retractall/1 that differs from swipl ports the NONDETERMINISTIC flag.
"`retractall(+Head)`: retract every clause whose head unifies with `Head`, creating the predicate dynamic if it is new (pl-proc.c)."
function pl_retractall1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    gd = _query_gd(ld)
    head = PL__t0
    thehead = PL_new_term_ref(ld)
    proc = get_procedure_create(gd, ld, head, thehead)
    proc === nothing && return FFALSE
    def = proc.definition
    if (def.flags & P_FOREIGN) != 0
        PL_error(ld, ERR_MODIFY_STATIC_PROC, proc)
        return FFALSE
    end
    if (def.flags & P_DYNAMIC) == 0
        if isDefinedProcedure(gd, proc)
            PL_error(ld, ERR_MODIFY_STATIC_PROC, proc)
            return FFALSE
        end
        return setDynamicDefinition!(def, true) ? FTRUE : FFALSE      # nothing to retract
    end
    return pl_retractall!(gd, ld, def, thehead) ? FTRUE : FFALSE
end

# PORT: pl-proc.c BeginPredDefs as PL_predicates_from_proc
# DIVERGES: the entries of the predicates the kernel has ported; `PRED_DEF` ors in `PL_FA_VARARGS`.
"pl-proc.c's registration table (`BeginPredDefs(proc)`): the ported entries."
const PL_predicates_from_proc = (
    PL_extension("retractall", 1, pl_retractall1_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension(
        "\$set_predicate_attribute", 3, pl_set_predicate_attribute3_va,
        PL_FA_TRANSPARENT | PL_FA_VARARGS
    ),
    PL_extension(
        "retract", 1, pl_retract1_va,
        PL_FA_TRANSPARENT | PL_FA_NONDETERMINISTIC | PL_FA_ISO | PL_FA_VARARGS
    )
)
