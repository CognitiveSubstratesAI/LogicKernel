# UPSTREAM: swipl-devel src/pl-gc.c @ bae881a24a3f
# CLASS: code
# COPYRIGHT: Copyright (c)  1985-2024, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# The one function of SWI-Prolog's garbage collector (pl-gc.c) that clause GC calls: finding the
# generations the predicates are being executed in. Stack garbage collection is not the kernel's.

# PORT: pl-gc.c markPredicatesInEnvironments
# DIVERGES: there is no local stack and there are no transactions, so no frames and no
# transaction start to walk: what remains is upstream's last step, the predicates referenced
# explicitly (`markAccessedPredicates`). Every enumeration over a dynamic predicate references it
# with `pushPredicateAccessObj!` — calls included, where upstream would find their frames.
"Record the generations every predicate is accessed in, for clause GC (pl-gc.c)."
function markPredicatesInEnvironments!(
    ld::PL_local_data{T}, gd::PL_global_data{T}
)::Nothing where {T}
    markAccessedPredicates!(ld, gd)
    return nothing
end
