# UPSTREAM: swipl-devel src/pl-gc.c @ 18168e629eab
# CLASS: code
# COPYRIGHT: Copyright (c)  1985-2024, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
# allow-new-artifact: a port of pl-gc.c at the pin (read via git show 18168e62:src/pl-gc.c; the design is in evidence/G1/g1gc4_handoff.md)
# G1-GC (G1-4): the TRAIL half of SWI-Prolog's stack garbage collector (pl-gc.c): `compact_trail`,
# `tag_trail`/`untag_trail` (audit D-0634 ruling D2, option (a): the entries are re-encoded cell for cell as
# upstream does), `is_dead_attvar` and `clean_attvar_chain`. The other definitions of the G1-4 row are G1-3's
# and already written in pl-gcwalk.jl and pl-gcmark.jl: `mergeTrailedAssignments` (with `push_marked` and
# `popall_marked` as a local vector), `early_reset_vars`, `early_reset_choicepoint` and `mark_foreign_frame`.
# LEAF file: it is included after pl-gcwalk.jl and needs only the cell helpers of pl-gcmark.jl.
#
# THE TRAIL DURING A COLLECTION (the data G1-5's `sweep_trail` consumes, and G1-6's `garbageCollect` drives):
#   * `gc_trail_begin!(ld)` pushes ONE zero SENTINEL word and returns a `gc_trail_state` whose `top` is the
#     index of the sentinel (upstream `tTop`, with `tTop->address = 0`). A mark's `trailtop` (an entry COUNT)
#     names the entry at index `trailtop + 1`, which is the sentinel for the newest mark: the head of a
#     relocation chain can live there. Entries are `1:top-1`; a word 0 is a DELETED entry (early reset).
#   * between `tag_trail` and `untag_trail` an entry is a TAGGED word as upstream's: an address entry is
#     `consPtr(pos, STG_GLOBAL)` (tag bit 0 clear), a value entry `consPtr(pos, STG_GLOBAL | TAG_TRAILVAL)`
#     (bit 0 set); the position sits at bit `LMASK_BITS` so the MARK and FIRST bits are free (the kernel's
#     untagged entry has its position at bit 3, where those bits would overwrite it).
#   * `gc_trail_sweep_entries(ld, ts)` lists, in upstream's order (newest first), the entries `sweep_trail`
#     puts into relocation chains.
# DIVERGES (order): upstream calls `tag_trail` BEFORE `mark_phase`; the kernel's early reset (pl-gcwalk.jl)
# reads the UNTAGGED entries and starts at the last entry (`mark_stacks`: `reset_entry = length(ld.trail)`),
# so the kernel order is `mark_phase`, `gc_trail_begin!`, `tag_trail`, `compact_trail`, the collect phase,
# `untag_trail`, `clean_attvar_chain`, `gc_trail_end!` (the sentinel is pushed after marking). The two orders
# agree because nothing between the two upstream calls reads an entry in any other way than early reset,
# and the relocation-chain heads of a mark's `trailtop` (`alien_into_relocation_chain`, G1-5) are made
# after `tag_trail`, in the same pass that numbers the marks.

# ── the state of the trail during one collection ────────────────────────────────────────────────
"""
    gc_trail_state()

The bookkeeping of the trail across one collection: `top` the index of the sentinel word (upstream
`tTop`), `tagged` whether the entries are in the tagged form, and the counters `values` (value entries
seen by `tag_trail`), `zeroed` (deleted entries `compact_trail` removed), `kept` (entries it kept) and
`chains` (relocation chains it unwound).
"""
mutable struct gc_trail_state
    top::Int
    tagged::Bool
    values::Int
    zeroed::Int
    kept::Int
    chains::Int
    gc_trail_state() = new(0, false, 0, 0, 0, 0)
end

# ORIGINAL: `tTop->address = 0` of garbageCollect(): the sentinel entry past the last one (see above).
"Push the zero sentinel word on the trail and return the state naming it; the first call of a collection."
function gc_trail_begin!(ld::PL_local_data{T})::gc_trail_state where {T}
    push!(ld.trail, word(0))
    ts = gc_trail_state()
    ts.top = length(ld.trail)
    return ts
end

# ORIGINAL: removes the sentinel `gc_trail_begin!` pushed (after `compact_trail` it sits at the new `top`).
"Remove the sentinel word of `ts`; the last call of a collection."
function gc_trail_end!(ld::PL_local_data{T}, ts::gc_trail_state)::Nothing where {T}
    length(ld.trail) == ts.top || error(
        "gc_trail_end!: the trail has $(length(ld.trail)) words, the sentinel is at $(ts.top)"
    )
    pop!(ld.trail)
    ts.top = 0
    return nothing
end

# ── the tagged form of an entry (pl-data.h consPtr over the trail) ──────────────────────────────
# ORIGINAL: pl-gc.c's `ttag(w)` = `w & TAG_TRAILMASK` for the tagged words: a value entry has bit 0 set.
"Whether the TAGGED trail word `w` is a value entry (`ttag(w) == TAG_TRAILVAL`, pl-gc.c)."
@inline gc_trail_tagged_isval(w::word)::Bool = (w & TAG_TRAILMASK) == TAG_TRAILVAL

# ORIGINAL: `valPtr(te->as_word)` of the tagged entry: the cell position the entry names.
"The position the TAGGED trail word `w` names (`valPtr`, pl-gc.c): an address, or the saved old value."
@inline gc_trail_tagged_pos(w::word)::Int = valPtr(w)

# ORIGINAL: the word `tag_trail` writes for one untagged entry `e` (0 stays 0: a deleted entry).
"The tagged form of the untagged trail entry `e`; a refusal for a local-stack address (the kernel trails global cells only)."
function gc_trail_tag_entry(ld::PL_local_data{T}, e::word)::word where {T}
    e == 0 && return word(0)
    if isTrailVal(e)
        return consPtr(trailValP(e), STG_GLOBAL | TAG_TRAILVAL)    # consPtr(p2, STG_GLOBAL|TAG_TRAILVAL)
    end
    if _trail_stack(e) != TRAIL_GLOBAL
        throw(
            NotPortedError(
                ld.placeholder,
                "a trail entry for a local-stack variable (pl-gc.c tag_trail; the kernel trails global cells only)",
                "G1-4"
            )
        )
    end
    return consPtr(_trail_pos(e), STG_GLOBAL)                      # consPtr(te->address, stg)
end

# ORIGINAL: the word `untag_trail` writes back for one tagged entry `w` (0 stays 0).
"The untagged trail entry of the tagged word `w`; the gc bits `w` may still carry are dropped."
function gc_trail_untag_entry(ld::PL_local_data{T}, w::word)::word where {T}
    w == 0 && return word(0)
    p = valPtr(w)
    if gc_trail_tagged_isval(w)
        return tagTrailPtr(p)                                      # address = valPtr | mask
    end
    if (w & STG_MASK) != STG_GLOBAL
        throw(
            NotPortedError(
                ld.placeholder,
                "a trail entry for a local-stack variable (pl-gc.c untag_trail; the kernel trails global cells only)",
                "G1-4"
            )
        )
    end
    return _trail_addr(p, TRAIL_GLOBAL)
end

# PORT: pl-gc.c tag_trail
# DIVERGES: the entries are indexes `1:ts.top-1` of `ld.trail`; the kernel's entry is `(pos << 3) | ...`,
# so the tagged word is built from the position (see the header) and an address entry for a local variable
# is a named refusal; a deleted entry (word 0, early reset ran first in the kernel's order) stays 0;
# the debug assertions `onStack(global, p2)` / `onGlobalArea` are not carried; the order of the walk is
# upstream's (newest entry first).
"""
    tag_trail(ld, ts)

Turn the trail's entries into tagged words (pl-gc.c): afterwards an entry is `consPtr(pos, STG_GLOBAL)`
(address) or `consPtr(pos, STG_GLOBAL | TAG_TRAILVAL)` (value) and may carry the MARK and FIRST bits.
"""
function tag_trail(ld::PL_local_data{T}, ts::gc_trail_state)::Nothing where {T}
    ts.tagged && error("tag_trail: the trail is already tagged")
    trail = ld.trail
    ts.values = 0
    for i in (ts.top - 1):-1:1                                     # for( te = tTop; --te >= tBase; )
        e = trail[i]
        isTrailVal(e) && (ts.values += 1)
        trail[i] = gc_trail_tag_entry(ld, e)
    end
    ts.tagged = true
    return nothing
end

# PORT: pl-gc.c untag_trail
# DIVERGES: see `tag_trail`; `te[-1].address` is the entry at `i - 1` (already untagged: the walk goes up,
# as upstream's); the `on_attvar_chain` assertion is not carried. The cell of an attvar whose value was
# overwritten but is kept by a trailed assignment gets the MARK bit, which `is_dead_attvar` reads and clears.
"""
    untag_trail(ld, ts)

Turn the tagged words back into the trail's entries (pl-gc.c). A value entry whose saved value is an
attributed variable marks the attvar cell its address entry names (unless that cell is still an attvar),
so that `clean_attvar_chain` keeps it on the chain.
"""
function untag_trail(ld::PL_local_data{T}, ts::gc_trail_state)::Nothing where {T}
    ts.tagged || error("untag_trail: the trail is not tagged")
    trail = ld.trail
    for i in 1:(ts.top - 1)                                        # for(te = tBase; te < tTop; te++)
        w = trail[i]
        if w != 0
            e = gc_trail_untag_entry(ld, w)
            trail[i] = e
            if isTrailVal(e)
                old = ld.gstack[trailValP(e)]                      # w = trailVal(te->as_word)
                if isAttVar(old)
                    i > 1 || error("untag_trail: a value entry without its address entry")
                    avp = _trail_pos(trail[i - 1])                 # Word avp = te[-1].address
                    if !isAttVar(ld.gstack[avp])
                        ld.gstack[avp] = set_marked(ld.gstack[avp])    # *(avp) |= MARK_MASK
                    end
                end
            end
        end
    end
    ts.tagged = false
    return nothing
end

# ORIGINAL: the entries `sweep_trail` (pl-gc.c, G1-5) puts into relocation chains: `te->as_word != 0` and
# either a value entry (`ttag == TAG_TRAILVAL`) or `isGlobalPtr(te->as_word)`; newest first, as its loop.
# This is the data G1-5 consumes; the chain insertion itself (`needsRelocation`, `check_relocation`,
# `into_relocation_chain(&te->as_word, STG_TRAIL)`) is G1-5's.
"The indexes, newest first, of the tagged entries `sweep_trail` puts into relocation chains (the trail must be tagged)."
function gc_trail_sweep_entries(
    ld::PL_local_data{T}, ts::gc_trail_state
)::Vector{Int} where {T}
    ts.tagged || error("gc_trail_sweep_entries: the trail is not tagged")
    out = Int[]
    for i in (ts.top - 1):-1:1                                     # for( ; te >= tBase; te-- )
        w = ld.trail[i]
        w == 0 && continue
        if gc_trail_tagged_isval(w) || (w & STG_MASK) == STG_GLOBAL
            push!(out, i)
        end
    end
    return out
end

# ── trail compaction (pl-gc.c compact_trail) ────────────────────────────────────────────────────
# ORIGINAL: the stand-in for `update_relocation_chain` (pl-gc.c:2647, G1-5): `compact_trail` meets a FIRST
# bit only where a relocation chain starts, and the chains are G1-5's, so without a handler a collection
# that built one is refused by name instead of silently dropping the chain.
"The default chain handler of `compact_trail`: a named refusal (the relocation chains are G1-5's)."
function gc_trail_no_chain(ld::PL_local_data{T}, current::Int, dest::Int)::Nothing where {T}
    throw(
        NotPortedError(
            ld.placeholder,
            "update_relocation_chain of a trail entry (pl-gc.c:2647)",
            "G1-5"
        )
    )
end

# PORT: pl-gc.c compact_trail
# DIVERGES: `current` and `dest` are indexes of `ld.trail`; `update_relocation_chain(&current->as_word,
# &dest->as_word)` is the handler `urc(ld, current, dest)` (G1-5's, default `gc_trail_no_chain`), called
# before the entry is copied as upstream does, and it must leave the head's restored value in
# `ld.trail[current]`; the sentinel at `ts.top` is not copied but its word is carried to the new top
# (the head of the newest mark's chain lives there); the final check `relocated_cells != relocation_cells`
# is G1-5's (it owns the counters). The old tail beyond the new sentinel is cut off (`resize!`).
"""
    compact_trail(ld, ts, urc = gc_trail_no_chain) -> Int

Remove the deleted (zero) entries of the tagged trail, keeping the order of the others; an entry that
heads a relocation chain (FIRST bit) is handed to `urc(ld, current, dest)` first. `ts.top` becomes the
index of the sentinel in the shorter trail; the result is that index.
"""
function compact_trail(
    ld::PL_local_data{T}, ts::gc_trail_state, urc::F=gc_trail_no_chain
)::Int where {T, F}
    ts.tagged || error("compact_trail: the trail must be tagged")
    trail = ld.trail
    dest = 1
    current = 1
    while current < ts.top                                         # for( dest = current = tBase; current < tTop; )
        if is_first(trail[current])
            urc(ld, current, dest)
            ts.chains += 1
        end
        if trail[current] != 0
            trail[dest] = trail[current]                           # *dest++ = *current++
            dest += 1
            ts.kept += 1
        else
            ts.zeroed += 1
        end
        current += 1
    end
    if is_first(trail[current])                                    # the sentinel: gTop refs from marks
        urc(ld, current, dest)
        ts.chains += 1
    end
    trail[dest] = trail[current]
    resize!(trail, dest)
    ts.top = dest                                                  # tTop = dest
    return dest
end

# ── attvar chain cleaning (pl-gc.c is_dead_attvar, clean_attvar_chain) ──────────────────────────
# PORT: pl-gc.c is_dead_attvar
# DIVERGES: `p` is the global position of the attvar cell.
"""
    is_dead_attvar(ld, p) -> Bool

An attvar cell is dead when its value is no longer a TAG_ATTVAR word and no trailed assignment keeps it:
`untag_trail` marks the cells of such assignments, and this clears that mark (pl-gc.c).
"""
function is_dead_attvar(ld::PL_local_data{T}, p::Int)::Bool where {T}
    w = ld.gstack[p]
    if is_marked(w)
        ld.gstack[p] = clear_marked(w)                             # *p = (w & ~MARK_MASK)
        return false
    end
    isAttVar(w) && return false
    return true
end

# PORT: pl-gc.c clean_attvar_chain
# DIVERGES: the chain's positions are 1-based and 0 is NULL (`ld.attvar_attvars`); the debug count of the
# cleaned cells is not carried; the result is the number of links removed (for the tests).
"""
    clean_attvar_chain(ld) -> Int

Remove the dead cells from the chain of attributed variables (`ld.attvar_attvars`: the newest link cell,
each link cell holds a reference to the previous one and the attvar cell sits above it), pl-gc.c. Returns
the number of links removed.
"""
function clean_attvar_chain(ld::PL_local_data{T})::Int where {T}
    last = 0
    removed = 0
    p = ld.attvar_attvars
    while p != 0                                                   # for(p = LD->attvar.attvars; p; p = next)
        avp = p + 1
        nxt = isRef(ld.gstack[p]) ? unRef(ld.gstack[p]) : 0
        if is_dead_attvar(ld, avp)
            if last != 0
                ld.gstack[last] = ld.gstack[p]                     # *last = *p
            else
                ld.attvar_attvars = nxt                            # LD->attvar.attvars = next
            end
            removed += 1
        else
            last = p
        end
        p = nxt
    end
    return removed
end
