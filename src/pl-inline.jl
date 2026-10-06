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
# DIVERGES: no transactions — always the next global generation — and no `L_GENERATION` lock (no
# threads). Upstream's database starts at generation 1 (`setupProlog` calls it), the kernel's at 0
# (`gen_t(0)`, src/pl-global.jl): not observable from Prolog. (The assert and retract paths increment
# the generation inline, as upstream's do.)
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
# DIVERGES: two forms. On a frame (`fr`, an index), upstream's: the frame's `generation` becomes the
# current global generation. Without one — `retract/1`, which has no frame until V9 makes it a
# foreign predicate — the generation is returned for the caller to run in. No transactions, so never
# the transaction's generation (`P_TRANSACT`, inl:733-736).
"The generation a frame of `def` is (re)set to: the current global generation (pl-inline.h)."
function setGenerationFrame(gd::PL_global_data{T}, def::Definition{T})::gen_t where {T}
    gen = global_generation(gd)
    while gen != global_generation(gd)              # do … while(): no other thread can move it
        gen = global_generation(gd)
    end
    return gen
end
function setGenerationFrame(
    gd::PL_global_data{T}, ld::PL_local_data{T}, fr::Int
)::Nothing where {T}
    f = ld.frames[fr]
    gen = global_generation(gd)
    while gen != global_generation(gd)              # do … while()
        gen = global_generation(gd)
    end
    f.generation = gen                              # setGenerationFrameVal(fr, gen)
    return nothing
end

# PORT: pl-inline.h QueryFromQid
# DIVERGES: a query handle is the query frame's POSITION (decision 1); the record is found on the
# chain of open queries from `LD->query` (since V3), where upstream computes its address from
# the handle's offset. A handle that names no open query gives 0 — upstream's would point at a
# closed (`QID_CMAGIC`) or reused frame.
"The open query frame (an index) whose handle is `qid`, or 0 (pl-inline.h)."
function QueryFromQid(ld::PL_local_data{T}, qid::Int)::Int where {T}
    qf = ld.query
    while qf != 0
        q = ld.queries[qf]
        q.base == qid && return qf
        qf = q.parent
    end
    return 0
end

# PORT: pl-incl.h QidFromQuery
"The handle of query frame `qf` (pl-incl.h): its position."
QidFromQuery(ld::PL_local_data{T}, qf::Int) where {T} = ld.queries[qf].base

# PORT: pl-incl.h pushArgumentStack
# DIVERGES: an entry is an `argstack_entry` (src/pl-incl.jl). Growth is `f_pushArgumentStack`'s.
"Push `e` on the argument stack (pl-incl.h)."
function pushArgumentStack(ld::PL_local_data{T}, e::argstack_entry{T})::Nothing where {T}
    if ld.aTop < length(ld.astack)                  # aTop+1 < aMax
        ld.aTop += 1
        ld.astack[ld.aTop] = e                      # *aTop++ = (p)
    else
        f_pushArgumentStack(ld, e)
    end
    return nothing
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

# PORT: pl-inline.h linkValI
# DIVERGES: the dereferenced term. Upstream returns a reference to an unbound variable's cell
# (`makeRefG(p)`) and the value otherwise; a keyed variable IS its own reference (decision 2).
"The value to store for the term `t` refers to: `t` dereferenced (pl-inline.h)."
function linkValI(ld::PL_local_data{T}, t::T)::T where {T}
    return deRef(ld, t)
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

# PORT: pl-incl.h f_hasSpace
# QUIRK, as upstream: the distance is signed and `esize` unsigned, so C converts a NEGATIVE distance
# (`here` above `top`) to a huge unsigned one, and the answer is `true`. Callers that can see
# `lTop > lMax` test that first (`ENSURE_LOCAL_SPACE`, vmi:142).
"Whether `nelem` elements of `esize` fit between `here` and `top` (pl-incl.h)."
function f_hasSpace(here::Int, top::Int, nelem::Int, esize::Int)::Bool
    return reinterpret(UInt, top - here) ÷ UInt(esize) >= UInt(nelem)
end

# PORT: pl-incl.h hasLocalSpace
# DIVERGES: `n` is in positions, where upstream's is in bytes.
"Whether `n` positions are free above `lTop` (pl-incl.h)."
hasLocalSpace(ld::PL_local_data, n::Int)::Bool = f_hasSpace(ld.lTop, ld.lMax, n, 1)

# PORT: pl-incl.h DiscardMark
# DIVERGES: a no-op. Upstream restores `LD->mark_bar`, which decides what needs trailing; every
# binding is trailed here (`Trail!`), so there is no bar. Kept, so every upstream call site reads
# `DiscardMark(…)` and a future `mark_bar` (condition 1's collector) has its place.
"Abandon mark `m` without undoing to it (pl-incl.h `DiscardMark`)."
DiscardMark(ld::PL_local_data, m::mark)::Nothing = nothing

# PORT: pl-incl.h NoMark
"A mark that must never be undone to (pl-incl.h `NoMark`): a built-in's foreign frame has one."
NoMark()::mark = mark(NOT_A_MARK)

# PORT: pl-incl.h isRealMark
"Whether `m` was taken by `Mark`, not made by `NoMark` (pl-incl.h)."
isRealMark(m::mark)::Bool = m.trailtop != NOT_A_MARK

# PORT: pl-incl.h Undo
# DIVERGES: the body of upstream's `Undo` without O_DESTRUCTIVE_ASSIGNMENT (with it, `do_undo` also
# restores destructive assignments — setarg/3, b_setval/2 — which the kernel does not have), and no
# global stack to reset. Marks nest: undoing to a mark above the trail's top is a misuse, asserted;
# so is undoing to a `NoMark`, which upstream never does.
"Undo every binding made since mark `m` (pl-incl.h `Undo`)."
function Undo!(ld::PL_local_data, m::mark)::Nothing
    @assert isRealMark(m) "Undo! to a NoMark"
    @assert m.trailtop <= length(ld.trail) "Undo! to a mark above the trail: marks undone out of order"
    while length(ld.trail) > m.trailtop
        delete!(ld.bindings, pop!(ld.trail))    # setVar(*tt->address)
    end
    return nothing
end
