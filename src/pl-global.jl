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

# PORT: pl-global.h PL_local_data
"""
    PL_local_data{T}()

The thread-local state (pl-global.h `struct PL_local_data`): the predicates ongoing enumerations
reference, at the generation each started in — so clause GC keeps what they can still see.
"""
mutable struct PL_local_data{T}
    predicate_references::Vector{definition_ref{T}}            # Referenced predicates
end
PL_local_data{T}() where {T} = PL_local_data{T}(definition_ref{T}[])
