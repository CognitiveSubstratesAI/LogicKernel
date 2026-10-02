# UPSTREAM: swipl-devel src/pl-proc.c @ bae881a24a3f
# UPSTREAM: swipl-devel src/pl-proc.h @ bae881a24a3f
# CLASS: code
# COPYRIGHT: Copyright (c)  1985-2025, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# PREDICATES AND THEIR CLAUSE LISTS — the slice of SWI-Prolog's pl-proc.c the index needs: allocating
# a predicate (`lookupProcedure`), a clause reference (`newClauseRef`), and adding a clause to a
# predicate (`assertDefinition!`), which keys it on the primary index and adds it to the
# predicate's indexes. The rest of pl-proc.c — retract, abolish, the logical update view's
# generations, clause garbage collection, reload — is the `db` subsystem, ported next.

# PORT: pl-proc.c lookupProcedure
# DIVERGES: allocates the definition only — upstream also looks the functor up in the module's
# procedure table and creates a procedure. `name` is the predicate name's `sym_key`, `flags` its
# initial P_* flags (e.g. `P_DYNAMIC` for `:- dynamic`).
"""
    lookupProcedure(T, name, arity, flags) -> Definition{T}

A new predicate `name/arity` over terms `T`, with no clauses: its per-argument information
allocated (zeroed) when it has arguments, as upstream allocates `impl.any.args`.
"""
function lookupProcedure(
    ::Type{T}, name::UInt64, arity::Int, flags::UInt64
)::Definition{T} where {T}
    clauses = ClauseList{T}()
    if arity > 0
        clauses.args = [arg_info() for _ in 1:arity]
    else
        clauses.args = nothing
    end
    return Definition{T}(name, arity, clauses, flags)
end

# PORT: pl-proc.c newClauseRef
"A clause reference to `clause` with index key `key` (pl-proc.c)."
newClauseRef(clause::Clause{T}, key::word) where {T} =
    ClauseRef{T}(nothing, key, clause, nothing)

# PORT: pl-proc.c assertDefinition
# DIVERGES: no generation counter, events or transactions yet (the `db` subsystem): the clause
# keeps the generations it was created with, and `generation_erased` becomes `GEN_MAX`
# (upstream's `max_generation(def)`). No supervisor to reset (`freeCodesDefinition`) — the caller
# runs `reconsiderIndexes!` and `update_primary_index!` before the next call, as upstream's
# `setDefaultSupervisor` does.
"""
    assertDefinition!(def, clause, where_) -> ClauseRef

Add `clause` to predicate `def` — at its start (`CL_START`), its end (`CL_END`) or before the
clause reference `where_` — keyed on the primary index, and add it to the predicate's indexes
(pl-proc.c).
"""
function assertDefinition!(
    def::Definition{T}, clause::Clause{T}, where_::Union{Int, ClauseRef{T}}
)::ClauseRef{T} where {T}
    key = argKey(Code(clause.codes, 1), Int(def.impl_clauses.primary_index))
    cref = newClauseRef(clause, key)
    clause.generation_erased = GEN_MAX
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
    return cref
end

# PORT: pl-proc.h mode_arg_is_unbound
"True when argument `arg0` (0-based) of `def` has mode `-` (pl-proc.h)."
mode_arg_is_unbound(def::definition, arg0::Int)::Bool =
    (def.impl_clauses.args::Vector{arg_info})[arg0 + 1].meta == MA_VAR
