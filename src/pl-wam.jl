# UPSTREAM: swipl-devel src/pl-wam.c @ bae881a24a3f
# CLASS: code
# COPYRIGHT: Copyright (c)  1985-2025, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# THE LOCAL STACK'S OPERATIONS (pl-wam.c), as the virtual machine will use them: creating a choice
# point, moving a last call's arguments into its frame, and opening, closing, rewinding and
# discarding foreign frames. The layout they work on is in src/pl-incl.jl § the local stack.
#
# Upstream makes a record by CASTING a position — `(Choice)lTop`, `(FliFrame)lTop`, the frame
# `normal_call` fills at `lTop` — and finds it again by casting its handle (`valTermRef(id)`). The
# kernel's records are pool entries, so the casts are three functions here: `pushFrame!`,
# `pushChoice!` and `pushFliFrame!` take the next record of their pool and give it a base;
# `fliFrameOfFid` finds a foreign frame by its handle.
#
# THE RECORD DISCIPLINE (decision 3, with the user's refinements of 2026-10-05):
#   * live records lie below `lTop`, in base order within each pool. The one exception is a frame
#     being filled ABOVE `lTop`, between `normal_call` and clause selection (vmi:1869);
#   * every assignment that LOWERS `lTop` drops the records at or above the new value
#     (`lowerLTop!`). Dropping lowers the pool's live count and nothing else: upstream reads a frame
#     after lowering `lTop` to it (`exit_continue`, vmi:2178-2194), so a dropped record stays
#     readable until a push reuses it;
#   * a drop never takes a record at or above the current `lTop`, which would be the frame being
#     filled. ASSERTED, so a violation fails loudly instead of corrupting a frame;
#   * backtracking to a choice point drops every record above it before moving it (V4a), because
#     there `lTop` can RISE over dead records (vmi:6503-6528, 6712).

# ── the records: push, find, drop (the casts upstream makes on positions) ───────────────────────
"""
    pushFrame!(ld, p) -> frame index

The frame record at position `p` — upstream's cast of `p` to a `LocalFrame`, where `normal_call`
then fills the frame's fields (vmi:1869-1879). The caller writes every field but `base`.
"""
function pushFrame!(ld::PL_local_data{T}, p::Int)::Int where {T}
    n = ld.nframes
    @assert n == 0 || ld.frames[n].base < p "pushFrame!: a live frame at or above the position — a drop was missed"
    n += 1
    ld.nframes = n
    ld.frames[n].base = p
    return n
end

"""
    pushChoice!(ld, p) -> choice index

The choice-point record at position `p` — upstream's cast `(Choice)lTop` in `newChoice`. The caller
writes every field but `base`.
"""
function pushChoice!(ld::PL_local_data{T}, p::Int)::Int where {T}
    n = ld.nchoices
    @assert n == 0 || ld.choices[n].base < p "pushChoice!: a live choice point at or above the position — a drop was missed"
    n += 1
    ld.nchoices = n
    ld.choices[n].base = p
    return n
end

"""
    pushFliFrame!(ld, p) -> foreign-frame index

The foreign-frame record at position `p` — upstream's cast `(FliFrame)lTop` in
`open_foreign_frame`. The caller writes every field but `base`.
"""
function pushFliFrame!(ld::PL_local_data{T}, p::Int)::Int where {T}
    n = ld.nfliframes
    @assert n == 0 || ld.fliframes[n].base < p "pushFliFrame!: a live foreign frame at or above the position — a drop was missed"
    n += 1
    ld.nfliframes = n
    ld.fliframes[n].base = p
    return n
end

"""
    fliFrameOfFid(ld, id) -> foreign-frame index, or 0

The open foreign frame whose handle is `id` — upstream's cast `(FliFrame) valTermRef(id)`. Found on
the chain from `fli_context`: a handle that is not on it names no open frame, and gives 0.
"""
function fliFrameOfFid(ld::PL_local_data{T}, id::Int)::Int where {T}
    fr = ld.fli_context
    while fr != 0
        f = ld.fliframes[fr]
        f.base == id && return fr
        f.base < id && return 0                 # the chain descends: `id` is not on it
        fr = f.parent
    end
    return 0
end

"""
    dropRecords!(ld, p)

Drop every record at or above position `p`, of every kind. The records stay readable until a push
reuses them. Asserts that none of them lies at or above `lTop`: that would be a frame being filled
above `lTop` (vmi:1869), which nothing may drop.
"""
function dropRecords!(ld::PL_local_data{T}, p::Int)::Nothing where {T}
    top = ld.lTop
    n = ld.nframes
    while n > 0 && ld.frames[n].base >= p
        @assert ld.frames[n].base < top "dropRecords!: a frame being filled above lTop (normal_call, vmi:1869) must not be dropped"
        n -= 1
    end
    ld.nframes = n
    n = ld.nchoices
    while n > 0 && ld.choices[n].base >= p
        @assert ld.choices[n].base < top "dropRecords!: a live choice point above lTop"
        n -= 1
    end
    ld.nchoices = n
    n = ld.nfliframes
    while n > 0 && ld.fliframes[n].base >= p
        @assert ld.fliframes[n].base < top "dropRecords!: a live foreign frame above lTop"
        n -= 1
    end
    ld.nfliframes = n
    return nothing
end

"""
    lowerLTop!(ld, p)

`lTop = p` where that LOWERS `lTop`: the records at or above `p` are dropped first.
"""
function lowerLTop!(ld::PL_local_data{T}, p::Int)::Nothing where {T}
    @assert p <= ld.lTop "lowerLTop!: the position is above lTop"
    dropRecords!(ld, p)
    ld.lTop = p
    return nothing
end

# ── choice points ────────────────────────────────────────────────────────────────────────────────
# PORT: pl-wam.c newChoice
# DIVERGES: returns the choice point's index. Its `value.clause` is RESET (no clause, key 0), where
# upstream leaves `value` to the caller: the reused record must not carry the previous
# enumeration's state (user, 2026-10-05). `prof_node` is not kept. The two `DEBUG(0, …)` assertions
# are kept.
"Create a choice point of `type` for frame `fr` at `lTop` and make it `BFR` (pl-wam.c)."
function newChoice(ld::PL_local_data{T}, type::choice_type, fr::Int)::Int where {T}
    ch = pushChoice!(ld, ld.lTop)               # Choice ch = (Choice)lTop;
    c = ld.choices[ch]
    @assert c.base + SIZEOF_CHOICE <= ld.lMax "newChoice: past lMax"         # ch+1 <= (Choice)lMax
    @assert ld.BFR == 0 || ld.choices[ld.BFR].base < c.base "newChoice: BFR is not older" # BFR < ch
    ld.lTop = c.base + SIZEOF_CHOICE            # lTop = (LocalFrame)(ch+1);

    c.type = type
    c.frame = fr
    c.parent = ld.BFR
    c.mark = Mark(ld)
    c.value_clause.cref = nothing
    c.value_clause.key = word(0)
    ld.BFR = ch

    return ch
end

# ── last-call arguments ─────────────────────────────────────────────────────────────────────────
# PORT: pl-wam.c copyFrameArguments
# DIVERGES: the frames are given by their base positions: upstream's caller passes `lTop` cast to a
# frame as `from` (vmi:2069). The long comment above upstream's body describes a reference fix-up
# pass the body no longer has; the copy is a plain forward copy, safe because `to` is below `from`.
"Copy the `argc` arguments of the frame at `from` into the frame at `to` (pl-wam.c)."
function copyFrameArguments(
    ld::PL_local_data{T}, from::Int, to::Int, argc::Int
)::Nothing where {T}
    if argc == 0
        return nothing
    end

    ARGS = argFrameP(from, 0)
    ARGE = ARGS + argc
    ARGD = argFrameP(to, 0)
    while ARGS < ARGE                           # now copy them
        ld.slots[ARGD + 1] = ld.slots[ARGS + 1]
        ARGD += 1
        ARGS += 1
    end
    return nothing
end

# ── foreign frames ──────────────────────────────────────────────────────────────────────────────
# PORT: pl-wam.c open_foreign_frame
# DIVERGES: `FLI_SET_VALID` and the `CHK_SECURE` assertion are `O_DEBUG` only.
"Open a foreign frame at `lTop`; its handle (pl-wam.c)."
function open_foreign_frame(ld::PL_local_data{T})::Int where {T}
    fr = pushFliFrame!(ld, ld.lTop)             # FliFrame fr = (FliFrame) lTop;
    f = ld.fliframes[fr]

    @assert f.base + SIZEOF_FLIFRAME <= ld.lMax "open_foreign_frame: past lMax"
    ld.lTop = f.base + SIZEOF_FLIFRAME          # lTop = (LocalFrame)(fr+1);
    f.size = 0
    f.no_free_before = -1                       # (size_t)-1
    f.mark = Mark(ld)
    f.parent = ld.fli_context
    ld.fli_context = fr

    return f.base                               # consTermRef(fr)
end

# PORT: pl-wam.c PL_close_foreign_frame
# DIVERGES: a handle that names no open foreign frame is refused (`fliFrameOfFid`), where upstream
# checks only `!id` (`FLI_VALID` is `O_DEBUG` only). `FLI_SET_CLOSED` is `O_DEBUG` only.
"Close foreign frame `id`, keeping its bindings (pl-wam.c)."
function PL_close_foreign_frame(ld::PL_local_data{T}, id::Int)::Nothing where {T}
    fr = id == 0 ? 0 : fliFrameOfFid(ld, id)

    if fr == 0
        error("PL_close_foreign_frame(): illegal frame: $id")   # sysError
    end
    f = ld.fliframes[fr]
    DiscardMark(ld, f.mark)
    ld.fli_context = f.parent
    lowerLTop!(ld, f.base)                      # lTop = (LocalFrame) fr;
    return nothing
end

# PORT: pl-wam.c PL_open_foreign_frame
# DIVERGES: no atom garbage collector, so no `gc_active` refusal; the room is in positions.
"Open a foreign frame with room for `MINFOREIGNSIZE` references; its handle, or 0 (pl-wam.c)."
function PL_open_foreign_frame(ld::PL_local_data{T})::Int where {T}
    lneeded = SIZEOF_FLIFRAME + MINFOREIGNSIZE

    if !ensureLocalSpace(ld, lneeded)
        return 0
    end

    return open_foreign_frame(ld)
end

# PORT: pl-wam.c PL_rewind_foreign_frame
# DIVERGES: the frame is found by its handle (`fliFrameOfFid`), which must name an open one.
"Undo foreign frame `id`'s bindings and drop its references; the frame stays open (pl-wam.c)."
function PL_rewind_foreign_frame(ld::PL_local_data{T}, id::Int)::Nothing where {T}
    fr = fliFrameOfFid(ld, id)
    @assert fr != 0 "PL_rewind_foreign_frame(): illegal frame: $id"
    f = ld.fliframes[fr]

    ld.fli_context = fr
    Undo!(ld, f.mark)
    lowerLTop!(ld, f.base + SIZEOF_FLIFRAME)    # lTop = addPointer(fr, sizeof(struct fliFrame));
    f.size = 0
    return nothing
end

# PORT: pl-wam.c PL_discard_foreign_frame
# DIVERGES: the frame is found by its handle (`fliFrameOfFid`), which must name an open one.
"Undo foreign frame `id`'s bindings and close it (pl-wam.c)."
function PL_discard_foreign_frame(ld::PL_local_data{T}, id::Int)::Nothing where {T}
    fr = fliFrameOfFid(ld, id)
    @assert fr != 0 "PL_discard_foreign_frame(): illegal frame: $id"
    f = ld.fliframes[fr]

    ld.fli_context = f.parent
    Undo!(ld, f.mark)
    DiscardMark(ld, f.mark)
    lowerLTop!(ld, f.base)                      # lTop = (LocalFrame) fr;
    return nothing
end
