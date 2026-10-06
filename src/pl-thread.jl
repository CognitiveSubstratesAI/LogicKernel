# UPSTREAM: swipl-devel src/pl-thread.c @ bae881a24a3f
# CLASS: code
# COPYRIGHT: Copyright (c)  1999-2026, University of Amsterdam,
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# PREDICATE REFERENCES — the slice of SWI-Prolog's pl-thread.c that records which predicates an
# ongoing enumeration (retract/1, clause/2, a call) references and at which generation, so that
# clause garbage collection keeps every clause those enumerations can still see. The rest of
# pl-thread.c is threads, which the kernel does not have.

# PORT: pl-thread.c cgcActivatePredicate
"Record that `def` is accessed in generation `gen`, if it is dirty (pl-thread.c)."
function cgcActivatePredicate!(
    gd::PL_global_data{T}, def::Definition{T}, gen::gen_t
)::Nothing where {T}
    ddi = get(gd.procedures_dirty, def, nothing)
    if ddi !== nothing
        ddi_add_access_gen!(ddi, gen)
    end
    return nothing
end

# PORT: pl-thread.c pushPredicateAccessObj
# DIVERGES: the reference stack is a Vector (upstream: blocks of doubling size). Upstream's
# `enterDefinition()` is a no-op macro (pl-incl.h), so there is nothing to port. NOT PORTED: the
# depth limit — upstream raises `representation_error(predicate references)` past 2^20 − 1000
# references (MAX_BLOCKS) and returns NULL, which its callers handle; here the stack grows without
# limit (the divergence audit, docs/divergence_audit.md).
"""
    pushPredicateAccessObj!(ld, gd, def) -> definition_ref

Push a reference to `def` at its current generation; the enumeration runs in that generation
(pl-thread.c).
"""
function pushPredicateAccessObj!(
    ld::PL_local_data{T}, gd::PL_global_data{T}, def::Definition{T}
)::definition_ref{T} where {T}
    gen = current_generation(gd, def)
    while gen != current_generation(gd, def)        # do … while(): no other thread can move it
        gen = current_generation(gd, def)
    end
    dref = definition_ref{T}(def, gen)
    push!(ld.predicate_references, dref)
    return dref
end

# PORT: pl-thread.c popPredicateAccess
# DIVERGES: removes the vector entry (upstream clears the top entry, or shifts the entries above an
# out-of-order one down, and decrements `top` — the same stack afterwards).
"Pop the reference to `def` — normally the top one; out of order is possible (pl-thread.c)."
function popPredicateAccess!(ld::PL_local_data{T}, def::Definition{T})::Nothing where {T}
    refs = ld.predicate_references
    top = length(refs)
    if refs[top].predicate === def
        pop!(refs)
        return nothing
    end
    while top > 0                                   # Out of order!
        if refs[top].predicate === def
            deleteat!(refs, top)
            return nothing
        end
        top -= 1
    end
    @assert false "popPredicateAccess!: predicate not referenced"
    return nothing
end

# PORT: pl-thread.c markAccessedPredicates
"Record every referenced predicate's generation with clause GC (pl-thread.c)."
function markAccessedPredicates!(
    ld::PL_local_data{T}, gd::PL_global_data{T}
)::Nothing where {T}
    for dref in ld.predicate_references
        cgcActivatePredicate!(gd, dref.predicate, dref.generation)
    end
    return nothing
end
