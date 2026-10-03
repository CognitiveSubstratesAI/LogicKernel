# UPSTREAM: swipl-devel src/pl-global.h @ bae881a24a3f
# CLASS: code
# COPYRIGHT: Copyright (c)  1997-2025, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# THE GLOBAL AND THREAD-LOCAL DATA the clause database reads — the fields of SWI-Prolog's
# `struct PL_global_data` (GD) and `struct PL_local_data` (LD) that the ported code uses.
#
# DIVERGES (both structs): upstream has ONE GD per process and one LD per thread, reached through
# globals. The kernel allows no module-level mutable state (tools/lint_globals.jl), so a GD and an
# LD are VALUES the caller creates and passes wherever upstream reads `GD->` or `LD->` — one pair
# per database, over one term type `T`. There are no threads: one LD per GD.

# PORT: pl-global.h PL_global_data
"""
    PL_global_data{T}()

The database-wide state (pl-global.h `struct PL_global_data`): the generation of the database,
the predicates with erased clauses, and whether clause GC is running. Field names are upstream's,
nesting flattened (`procedures.dirty` is `procedures_dirty`).
"""
mutable struct PL_global_data{T}
    _generation::gen_t                                          # generation of the database
    procedures_dirty::Dict{Definition{T}, dirty_def_info{T}}    # procedures.dirty
    clauses_cgc_active::Bool                                    # clauses.cgc_active: CGC running
end
PL_global_data{T}() where {T} =
    PL_global_data{T}(gen_t(0), Dict{Definition{T}, dirty_def_info{T}}(), false)

# ── the kernel's variable keys ───────────────────────────────────────────────────────────────────
# DIVERGES: SWI's fresh variables are new cells on the global stack, unique by address. Interface
# variables are keys, so the kernel takes its own from the top half of the key space (callers own
# the bottom half — see `var_key`), from ONE PROCESS-WIDE counter: an answer retained from one
# `PL_local_data` and passed into another can carry a kernel key, which a per-instance counter
# would issue again (user, 2026-10-03). Module-level state, allowlisted in tools/lint_globals.jl:
# a monotonic source of fresh ids cannot carry behaviour from one caller to another.
# the next free kernel variable key (see `fresh_var_keys!`) — a comment, not a docstring: a docstring
# on a constant keeps a second binding to the value, which the global-state lint rightly flags
const _KERNEL_VAR_COUNTER = Threads.Atomic{UInt64}(KERNEL_VAR_BASE)

"""
    fresh_var_keys!(n) -> UInt64

Reserve `n` kernel variable keys, never issued before in this process: they are
`first, first + 1, …, first + n - 1`. Thread-safe.
"""
function fresh_var_keys!(n::Int)::UInt64
    first = Threads.atomic_add!(_KERNEL_VAR_COUNTER, UInt64(n))
    @assert first >= KERNEL_VAR_BASE && first + UInt64(n) >= first "kernel variable keys exhausted"
    return first
end

# PORT: pl-global.h PL_local_data
# DIVERGES: `index_ctx` is scratch upstream declares on the C stack in each firstClause/nextClause.
# `bindings` has no field upstream — SWI binds a variable by overwriting its cell on the
# global stack; interface variables are immutable values, so a binding is an entry keyed by
# `var_key`. `trail` is `stacks.trail` (its length is `tTop`) and holds those keys. A cyclic link or
# a visited mark is an entry in an identity map (`cycle_links`, `occurs_marked`) where upstream
# overwrites a functor cell; the stacks that restore them are upstream's (`cycle.lstack`,
# `var_occurs_in`'s `visited`). The agendas and the `visited` stack are scratch upstream keeps on
# the C stack; kept here, and emptied entry by entry, a warm unification allocates nothing.
"""
    PL_local_data{T}()

The thread-local state (pl-global.h `struct PL_local_data`): the predicates ongoing enumerations
reference, at the generation each started in — so clause GC keeps what they can still see — and
the state of unification: the bindings, the trail that undoes them back to a [`mark`](@ref), the
`occurs_check` flag, and the records the unifier keeps while it walks.
"""
mutable struct PL_local_data{T}
    predicate_references::Vector{definition_ref{T}}            # Referenced predicates
    bindings::Dict{UInt64, T}                                   # var_key → value (see above)
    trail::Vector{UInt64}                                       # stacks.trail: bound var_keys
    prolog_flag_occurs_check::occurs_check_t                    # prolog_flag.occurs_check
    cycle_lstack::Vector{T}                                     # cycle.lstack: linked compounds
    cycle_links::IdDict{T, T}                                   # the links themselves
    occurs_visited::Vector{T}                                   # var_occurs_in's `visited`
    occurs_marked::IdDict{T, Nothing}                           # its FIRST_MASK marks
    unify_agenda::term_agendaLR{T}                              # do_unify's `agenda`
    occurs_agenda::term_agenda{T}                               # var_occurs_in's `agenda`
    index_ctx::index_context{T}                                 # firstClause/nextClause scratch
end
function PL_local_data{T}() where {T}
    e = mk_expr(T, T[])                         # any term: the agendas' idle work nodes
    return PL_local_data{T}(
        definition_ref{T}[], Dict{UInt64, T}(), UInt64[], OCCURS_CHECK_FALSE, T[],
        IdDict{T, T}(), T[], IdDict{T, Nothing}(),
        term_agendaLR{T}(aNodeLR{T}(e, e, 0, 0), aNodeLR{T}[]),
        term_agenda{T}(aNode{T}(e, 0, 0), aNode{T}[]),
        # idle until a search resets it (`_index_context!`): any predicate will do
        index_context{T}(
            gen_t(0),
            Definition{T}(UInt64(0), 0, ClauseList{T}(), UInt64(0)),
            nothing,
            0,
            _TOP_POSITION,
            false
        )
    )
end
