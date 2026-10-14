# UPSTREAM: swipl-devel src/pl-inline.h @ 8609e216cab9
# UPSTREAM: swipl-devel src/pl-incl.h @ 8609e216cab9
# UPSTREAM: swipl-devel src/pl-data.h @ 8609e216cab9
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
# ORIGINAL: the two kinds of variable (L1a; src/pl-global.jl `CELL_KEY_TAG`).
"""
The position of the live cell variable `key` names on this engine's global stack, or 0: the key of
a KEYED variable (a caller's, a counter's, another engine's, or a cell's whose position was reused).
"""
@inline function _cell_pos(ld::PL_local_data, key::UInt64)::Int
    (key & CELL_KEY_TAG) == CELL_KEY_TAG || return 0
    p = Int(key & CELL_POS_MASK)
    return (1 <= p <= ld.gTop && ld.gkey[p] == key) ? p : 0
end

# ORIGINAL: what a variable is bound to, for the few readers that look a binding up by key.
"The value variable `key` is bound to, or `nothing` (unbound): its cell, or the store."
function _binding(ld::PL_local_data{T}, key::UInt64)::Union{Nothing, T} where {T}
    p = _cell_pos(ld, key)
    return p != 0 ? ld.gstack[p] : get(ld.bindings, key, nothing)
end

# ORIGINAL: bind without a trail entry — the callers that restore the binding themselves.
"Bind variable `key` to `v` WITHOUT trailing it: its cell, or the store."
function _set_binding!(ld::PL_local_data{T}, key::UInt64, v::T)::Nothing where {T}
    p = _cell_pos(ld, key)
    if p != 0
        ld.gstack[p] = v              # *p = v
    else
        ld.bindings[key] = v
    end
    return nothing
end

# ORIGINAL: unbind, as `setVar(*p)` does.
"Make variable `key` unbound again (`setVar`): its cell, or its entry in the store."
function _unbind!(ld::PL_local_data, key::UInt64)::Nothing
    p = _cell_pos(ld, key)
    if p != 0
        ld.gstack[p] = nothing        # setVar(*p)
    else
        delete!(ld.bindings, key)
    end
    return nothing
end

# ── the local stack's slots: three accessors (L1b) ───────────────────────────────────────────────
# Every read and write of a slot goes through one of these, so that L1b's switch of the slots to
# WORDS (pl-data.h) changes three functions, not the 400 sites that call them (the L1 plan, §5 —
# docs/research/logickernel-step-memos/L1_plan/l1_plan.md in the workspace). `i` is the slot's
# 1-based position on the local stack: term reference `t` is position `t + 1`.

# ORIGINAL: the slot read (L1b commit 1a: the value as stored; then built from the cells).
"The value slot `i` holds (the term reference `t` is slot `t + 1`)."
@inline slotValue(ld::PL_local_data{T}, i::Int) where {T} = ld.slots[i]::T

# ORIGINAL: the ENGINE's slot write — its own value, variable identity kept (upstream `setHandle`).
"Store the engine's value `v` in slot `i`; returns `v`, as the assignment it replaces did."
@inline function setSlotValue!(ld::PL_local_data{T}, i::Int, v::T)::T where {T}
    ld.slots[i] = v
    return v
end

# ORIGINAL: the variables one put shares with the puts that pass the same map (L1b): a caller's
# variable key → the key of its fresh cell. One map is one record's worth of variables — a goal's
# arguments put slot by slot with one map share them as SWI's record of the goal would.
# It DIVERGES from SWI as a Julia-side convenience with no C counterpart: SWI shares variables
# between puts only through `term_t` handles (`PL_put_term`), or by putting one compound.
"""
    PutVarMap()

The variables shared by the puts that pass this map (`putSlotValue!`): each caller variable met
by any of them is ONE fresh variable of the engine. A map is good while its cells live — not across
backtracking below the puts.
"""
struct PutVarMap
    cells::Dict{UInt64, UInt64}
end
PutVarMap() = PutVarMap(Dict{UInt64, UInt64}())

# ORIGINAL: THE BOUNDARY — a Julia caller's value put into a slot, with SWI's semantics (user,
# 2026-10-14): the value is COPIED as a record is (`copyRecordToGlobal`) — bindings followed, every
# unbound variable, a caller's or one of this engine's, a fresh cell, one per variable per `vm` — so
# separate puts make separate variables, and sharing with a variable already in the engine goes
# through its handle (`PL_put_term`, `setSlotValue!`), as in SWI's C interface. The put never asks
# whether a variable is a live cell: no stamp site.
"""
    putSlotValue!(ld, i, v[, vm]) -> the value put

Put a CALLER's value `v` into slot `i`: a copy with fresh variables, shared with the other puts
that pass the same `vm` (`PutVarMap`); without `vm`, a put of its own. Variable identity is the
handle: read an answer through the slot, never through the caller's variable.
"""
function putSlotValue!(ld::PL_local_data{T}, i::Int, v::T, vm::PutVarMap)::T where {T}
    vars = Dict{UInt64, T}()
    for (k, c) in vm.cells
        vars[k] = mk_var(T, c)
    end
    c = copy_term(ld, v, cp_options(true), vars)
    for (k, w) in vars
        vm.cells[k] = var_key(w)
    end
    ld.slots[i] = c
    return c
end
putSlotValue!(ld::PL_local_data{T}, i::Int, v::T) where {T} =
    putSlotValue!(ld, i, v, PutVarMap())

# PORT: pl-data.h deRef
# DIVERGES: follows a cell variable's cell, and a keyed variable's entry in the store, where
# upstream follows reference cells.
"`t` with its variable bindings followed: an unbound variable, or a non-variable (pl-data.h)."
function deRef(ld::PL_local_data{T}, t::T)::T where {T}
    while kind(t) === VAR
        k = var_key(t)
        p = _cell_pos(ld, k)
        b = p != 0 ? ld.gstack[p] : get(ld.bindings, k, nothing)
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
# DIVERGES: a cell variable is trailed as upstream trails a global cell — only below
# `LD->mark_bar`; a KEYED variable (src/pl-global.jl) has no age, and is always trailed, as
# upstream always trails a local-stack cell (`p >= lBase`). Positions are 1-based and `gTop` is the
# LAST cell in use (upstream's `gTop` points at the first free word), so upstream's `p < mark_bar`
# is `p <= mark_bar` here.
"Bind variable `key` to `v`, recording it on the trail where backtracking must undo it (pl-inline.h)."
function Trail!(ld::PL_local_data{T}, key::UInt64, v::T)::Nothing where {T}
    p = _cell_pos(ld, key)
    if p != 0
        p <= ld.mark_bar && push!(ld.trail, key)    # if ( p < LD->mark_bar ) (tTop++)->address = p
        ld.gstack[p] = v              # *p = v
    else
        push!(ld.trail, key)                    # (tTop++)->address = p
        ld.bindings[key] = v                    # *p = v
    end
    return nothing
end

# PORT: pl-incl.h Mark
"A mark at the current heights of the trail and the global stack; sets `mark_bar` (pl-incl.h `Mark`)."
function Mark(ld::PL_local_data)::mark
    m = mark(length(ld.trail), ld.gTop, ld.mark_bar)
    ld.mark_bar != NO_MARK_BAR && (ld.mark_bar = ld.gTop)
    return m
end

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
# DIVERGES: no `frozen_bar` — the kernel's ball is a value (decision 1).
"Abandon mark `m` without undoing to it: `mark_bar` back to what `m` replaced (pl-incl.h `DiscardMark`)."
function DiscardMark(ld::PL_local_data, m::mark)::Nothing
    ld.mark_bar = m.saved_bar
    return nothing
end

# PORT: pl-incl.h NoMark
"A mark that must never be undone to (pl-incl.h `NoMark`): a built-in's foreign frame has one."
NoMark()::mark = mark(NOT_A_MARK, 0, 0)

# PORT: pl-incl.h isRealMark
"Whether `m` was taken by `Mark`, not made by `NoMark` (pl-incl.h)."
isRealMark(m::mark)::Bool = m.trailtop != NOT_A_MARK

# PORT: pl-incl.h Undo
# DIVERGES: the body of upstream's `Undo` without O_DESTRUCTIVE_ASSIGNMENT (with it, `do_undo` also
# restores destructive assignments — setarg/3, b_setval/2 — which the kernel does not have), and no
# `frozen_bar` (the kernel's ball is a value, decision 1). Marks nest: undoing to a mark above the
# trail's or the global stack's top is a misuse, asserted; so is undoing to a `NoMark`, which
# upstream never does.
"Undo every binding made since mark `m`, and free the cells allocated since (pl-incl.h `Undo`)."
function Undo!(ld::PL_local_data, m::mark)::Nothing
    @assert isRealMark(m) "Undo! to a NoMark"
    @assert m.trailtop <= length(ld.trail) "Undo! to a mark above the trail: marks undone out of order"
    @assert m.globaltop <= ld.gTop "Undo! to a mark above the global stack: marks undone out of order"
    while length(ld.trail) > m.trailtop
        _unbind!(ld, pop!(ld.trail))            # setVar(*tt->address)
    end
    ld.gTop = m.globaltop                       # gTop = (b).globaltop
    return nothing
end
