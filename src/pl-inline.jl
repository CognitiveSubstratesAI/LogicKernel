# UPSTREAM: swipl-devel src/pl-inline.h @ bae881a24a3f
# UPSTREAM: swipl-devel src/pl-incl.h @ bae881a24a3f
# UPSTREAM: swipl-devel src/pl-data.h @ bae881a24a3f
# CLASS: code
# COPYRIGHT: Copyright (c)  2008-2024, University of Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# SWI-Prolog's inline helpers the clause store uses: the bit scan behind bucket counts, the
# cleaning of hashed index keys, clause visibility in a generation, and the database generation —
# and the binding primitives the unifier (src/pl-prims.jl) is built on: `Trail` (pl-inline.h),
# `Mark` and `Undo` (pl-incl.h macros) and `deRef` (a pl-data.h macro). They take the local data
# explicitly, so they are defined here, after it (src/pl-global.jl), rather than in pl-incl.jl.
# Transactions are not ported: where upstream asks "inside a transaction on a P_TRANSACT
# predicate?", the answer here is always no.

# PORT: pl-inline.h MSB
"Index of the most significant set bit: `MSB(1) == 0`, `MSB(2) == 1` (pl-inline.h)."
MSB(i::Integer)::Int = 63 - leading_zeros(UInt64(i))

# PORT: pl-inline.h clean_index_key
"A hashed key that is never 0 and never reads as a functor (pl-inline.h)."
function clean_index_key(key::word)::word
    key &= ~STG_GLOBAL
    if key == 0
        key = word(1)
    end
    return key
end

# PORT: pl-inline.h visibleClause
# DIVERGES: the reload and transaction cases are not ported (neither exists yet); this is
# upstream's core test, `c <= gen && e > gen`.
"True when clause `cl` is visible in generation `gen` (pl-inline.h)."
function visibleClause(cl::clause, gen::gen_t)::Bool
    c = cl.generation_created
    e = cl.generation_erased
    if c <= gen && e > gen
        return true
    end
    return false
end

# PORT: pl-inline.h visibleClauseCNT
# DIVERGES: the erased-skipped statistic is not kept.
"`visibleClause`, counting the misses upstream (pl-inline.h)."
visibleClauseCNT(cl::clause, gen::gen_t)::Bool = visibleClause(cl, gen)

# PORT: pl-inline.h global_generation
"The generation of the database (pl-inline.h)."
global_generation(gd::PL_global_data)::gen_t = gd._generation

# PORT: pl-inline.h current_generation
# DIVERGES: no transactions — always the global generation.
"The generation a call of `def` runs in (pl-inline.h)."
current_generation(gd::PL_global_data{T}, def::Definition{T}) where {T} =
    global_generation(gd)

# PORT: pl-inline.h next_generation
# DIVERGES: no transactions — always the next global generation.
"Advance the database generation; the new generation (pl-inline.h)."
function next_generation!(gd::PL_global_data{T}, def::Definition{T})::gen_t where {T}
    gd._generation += 1
    return gd._generation
end

# PORT: pl-inline.h max_generation
# DIVERGES: no transactions — always `GEN_MAX`.
"The erased generation of a live clause of `def` (pl-inline.h)."
max_generation(def::definition)::gen_t = GEN_MAX

# PORT: pl-inline.h setGenerationFrame
# DIVERGES: there are no frames — returns the generation upstream stores in the frame, for the
# caller to run in.
"The generation a frame of `def` is (re)set to: the current global generation (pl-inline.h)."
function setGenerationFrame(gd::PL_global_data{T}, def::Definition{T})::gen_t where {T}
    gen = global_generation(gd)
    while gen != global_generation(gd)              # do … while(): no other thread can move it
        gen = global_generation(gd)
    end
    return gen
end

# ── bindings: deRef, Trail, Mark, Undo ───────────────────────────────────────────────────────────
# PORT: pl-data.h deRef
# DIVERGES: follows bindings in the store where upstream follows reference cells.
"`t` with its variable bindings followed: an unbound variable, or a non-variable (pl-data.h)."
function deRef(ld::PL_local_data{T}, t::T)::T where {T}
    while kind(t) === VAR
        b = get(ld.bindings, var_key(t), nothing)
        b === nothing && return t
        t = b
    end
    return t
end

# PORT: pl-inline.h Trail
# DIVERGES: every binding is trailed. Upstream skips an assignment to a cell created after the last
# mark (`p >= LD->mark_bar`: backtracking discards the cell itself); bindings here have no age.
"Bind variable `key` to `v`, recording it on the trail (pl-inline.h)."
function Trail!(ld::PL_local_data{T}, key::UInt64, v::T)::Nothing where {T}
    push!(ld.trail, key)                        # (tTop++)->address = p
    ld.bindings[key] = v                        # *p = v
    return nothing
end

# PORT: pl-incl.h Mark
"A mark at the current height of the trail (pl-incl.h `Mark`)."
Mark(ld::PL_local_data)::mark = mark(length(ld.trail))

# PORT: pl-incl.h Undo
# DIVERGES: the body of upstream's `Undo` without O_DESTRUCTIVE_ASSIGNMENT (with it, `do_undo` also
# restores destructive assignments — setarg/3, b_setval/2 — which the kernel does not have), and no
# global stack to reset. Marks nest: undoing to a mark above the trail's top is a misuse, asserted.
"Undo every binding made since mark `m` (pl-incl.h `Undo`)."
function Undo!(ld::PL_local_data, m::mark)::Nothing
    @assert m.trailtop <= length(ld.trail) "Undo! to a mark above the trail: marks undone out of order"
    while length(ld.trail) > m.trailtop
        delete!(ld.bindings, pop!(ld.trail))    # setVar(*tt->address)
    end
    return nothing
end
