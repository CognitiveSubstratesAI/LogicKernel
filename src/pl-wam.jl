# UPSTREAM: swipl-devel src/pl-wam.c @ bae881a24a3f
# UPSTREAM: swipl-devel src/pl-vmi.c @ bae881a24a3f
# UPSTREAM: swipl-devel src/pl-incl.h @ bae881a24a3f
# UPSTREAM: swipl-devel src/pl-gc.c @ bae881a24a3f
# CLASS: code
# COPYRIGHT: Copyright (c)  1985-2025, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# THE VIRTUAL MACHINE (pl-wam.c): the local stack's operations — creating a choice point, moving a
# last call's arguments into its frame, foreign frames (V3) — and, since V4a, the query API
# (`PL_open_query`, `PL_next_solution`, `PL_cut_query`, `PL_close_query`, `PL_exception`) and the run
# loop `PL_next_solution_guarded`, which holds the bodies of pl-vmi.c's instructions as upstream
# `#include`s them: the supervisors, the head instructions in read and write mode, the exits,
# backtracking over clause choice points and the query's, and the uncaught-exception path. The layout
# they work on is in src/pl-incl.jl § the local stack.
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
    pushQuery!(ld, p) -> query-frame index

The query-frame record at position `p` — upstream's cast `(QueryFrame)lTop` in `PL_open_query`. The
caller writes every field but `base`.
"""
function pushQuery!(ld::PL_local_data{T}, p::Int)::Int where {T}
    n = ld.nqueries
    @assert n == 0 || ld.queries[n].base < p "pushQuery!: a live query frame at or above the position — a drop was missed"
    n += 1
    ld.nqueries = n
    ld.queries[n].base = p
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
    n = ld.nqueries
    while n > 0 && ld.queries[n].base >= p
        @assert ld.queries[n].base < top "dropRecords!: a live query frame above lTop"
        n -= 1
    end
    ld.nqueries = n
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

# PORT: pl-wam.c vmi_fopen
# DIVERGES: the debugger's branch (a `CHP_DEBUG` choice point, wam:552-557) is not ported;
# `FLI_SET_VALID` is `O_DEBUG` only.
"Open the foreign frame of a deterministic foreign call of `def` in frame `fr` (pl-wam.c `vmi_fopen`)."
function vmi_fopen(ld::PL_local_data{T}, fr::Int, def::Definition{T})::Nothing where {T}
    p = argFrameP(ld.frames[fr].base, def.arity)        # ffr = (FliFrame)argFrameP(fr, arity)
    ffr = pushFliFrame!(ld, p)
    setLTop!(ld, p + SIZEOF_FLIFRAME)                   # lTop = (LocalFrame)(ffr+1)
    f = ld.fliframes[ffr]
    f.size = 0
    f.mark = NoMark()                                   # NoMark(ffr->mark)
    f.parent = ld.fli_context
    ld.fli_context = ffr
    return nothing
end

# PORT: pl-wam.c error_foreign_return_code
# DIVERGES: one foreign frame — upstream opens one, overwrites its handle with a second, and closes
# only the second (pl-wam.c:582-584); the first is no position anyone reads.
"A foreign predicate returned neither true nor false: raise `domain_error(foreign_return_value, Rc)` (pl-wam.c)."
function error_foreign_return_code(ld::PL_local_data{T}, rc::foreign_t)::Nothing where {T}
    fid = PL_open_foreign_frame(ld)
    if fid != 0
        ex = PL_new_term_ref(ld)
        ex != 0 && PL_put_intptr(ld, ex, Int(rc)) &&
            PL_error(ld, ERR_DOMAIN, mk_sym(T, :foreign_return_value), ex)
        PL_close_foreign_frame(ld, fid)
    end
    return nothing
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

# ── frames: leaving, discarding, finding the parent ──────────────────────────────────────────────
# PORT: pl-wam.c unify_mode
"The VM's unification mode (pl-wam.c): reading the caller's terms, or writing a new one."
@enum unify_mode::UInt8 begin
    uread = 0                       # Unification in read-mode
    uwrite                          # Unification in write mode
end

# PORT: pl-wam.c finished
"Why a frame is finished (pl-wam.c `enum finished`), as `frameFinished` and the discards report it."
@enum finished::UInt8 begin
    FINISH_EXIT = 0                 # keep consistent with reason_decls[]
    FINISH_FAIL
    FINISH_CUT
    FINISH_EXITCLEANUP
    FINISH_EXTERNAL_EXCEPT_UNDO
    FINISH_EXTERNAL_EXCEPT
    FINISH_EXCEPT
end

# PORT: pl-wam.c is_exception_finish
# DIVERGES: `reason_decls`' `is_exception` column, written as the set it marks.
"Whether `reason` finishes a frame because of an exception (pl-wam.c)."
is_exception_finish(reason::finished)::Bool =
    reason == FINISH_EXTERNAL_EXCEPT_UNDO || reason == FINISH_EXTERNAL_EXCEPT ||
    reason == FINISH_EXCEPT

# PORT: pl-wam.c leaveFrame
"Frame `fr` is left: it no longer runs a clause (pl-wam.c)."
function leaveFrame(ld::PL_local_data{T}, fr::Int)::Nothing where {T}
    ld.frames[fr].clause = nothing
    # leaveDefinition(fr->predicate): (void)0 upstream (pl-incl.h:1303)
    return nothing
end

# PORT: pl-wam.c discardFrame
# DIVERGES: a foreign frame's `clause` is set only by a NON-deterministic call (V9), so the
# `discardForeignFrame` branch is asserted unreached.
"Frame `fr` is discarded (pl-wam.c)."
function discardFrame(ld::PL_local_data{T}, fr::Int)::Nothing where {T}
    f = ld.frames[fr]
    def = f.predicate::Definition{T}
    if (def.flags & P_FOREIGN) != 0
        @assert f.clause === nothing "discardFrame: a non-deterministic foreign frame (V9)"
        # if ( fr->clause ) discardForeignFrame(fr) — V9
    else
        f.clause = nothing              # leaveDefinition() may destroy clauses (no more)
        # leaveDefinition(def): (void)0 upstream
    end
    return nothing
end

# PORT: pl-wam.c discardChoicesAfter
# DIVERGES: the age tests compare `base` positions; `frameFinished` on an `FR_WATCHED` frame is not
# ported — nothing sets the flag before `setup_call_cleanup/3` (V9) — so it is asserted absent; the
# stack never moves, so there is no re-basing after a shift.
"Discard the choice points created after frame `fr`, and the frames they protected (pl-wam.c)."
function discardChoicesAfter(
    ld::PL_local_data{T}, fr::Int, reason::finished
)::Nothing where {T}
    frbase = ld.frames[fr].base
    if ld.BFR != 0 && ld.choices[ld.BFR].base > frbase
        me = ld.BFR
        while true
            mec = ld.choices[me]
            me_undone = false

            delto = fr
            if mec.parent != 0
                pf = ld.choices[mec.parent].frame
                if ld.frames[pf].base > frbase
                    delto = pf
                end
            end

            fr2 = mec.frame
            while ld.frames[fr2].base > ld.frames[delto].base
                f2 = ld.frames[fr2]
                @assert f2.clause !== nothing ||
                    ((f2.predicate::Definition{T}).flags & P_FOREIGN) != 0
                @assert (f2.flags & FR_WATCHED) == 0 "discardChoicesAfter: frameFinished (FR_WATCHED) arrives with setup_call_cleanup (V9)"
                discardFrame(ld, fr2)
                fr2 = f2.parent
            end

            if mec.parent == 0 || ld.choices[mec.parent].base <= frbase
                if !me_undone
                    if reason == FINISH_EXTERNAL_EXCEPT_UNDO
                        Undo!(ld, mec.mark)
                    end
                    DiscardMark(ld, mec.mark)
                end
                ld.BFR = mec.parent
                return nothing
            end
            me = mec.parent
        end
    end
    return nothing
end

# PORT: pl-wam.c dbg_discardChoicesAfter
# DIVERGES: the pending exception's ball lives resolved in `exception_bin` (decision 1), which no
# `Undo` can change; it is set aside and restored as upstream does, so `exception_term` is clear
# while the choice points are discarded.
"`discardChoicesAfter`, keeping a pending exception (pl-wam.c)."
function dbg_discardChoicesAfter(
    ld::PL_local_data{T}, fr::Int, reason::finished
)::Nothing where {T}
    if ld.exception_term != 0
        w = deRef(ld, ld.slots[ld.exception_term + 1])
        @assert kind(w) !== VAR
        ld.exception_term = 0
        discardChoicesAfter(ld, fr, reason)
        ld.slots[ld.exception_bin + 1] = w
        ld.exception_term = ld.exception_bin
    else
        discardChoicesAfter(ld, fr, reason)
    end
    return nothing
end

# PORT: pl-gc.c queryOfFrame
# DIVERGES: the query record whose base lies `QF_TOP_FRAME` positions below the top frame's — the
# same arithmetic as upstream's `offsetof`, over the pool of query records.
"The query frame (an index) whose top frame is `fr` (pl-gc.c)."
function queryOfFrame(ld::PL_local_data{T}, fr::Int)::Int where {T}
    @assert ld.frames[fr].parent == 0
    b = ld.frames[fr].base - QF_TOP_FRAME
    for i in ld.nqueries:-1:1
        ld.queries[i].base == b && return i
    end
    error("queryOfFrame: no query frame below the top frame")
end

# PORT: pl-incl.h parentFrame
# DIVERGES: a top frame's parent is its query's `saved_environment`, read from the query record
# where upstream reads the word `QF_PARENT_ENV_OFFSET` below the frame.
"The frame `fr` returns to: its parent, or for a query's top frame the frame that opened it (pl-incl.h)."
function parentFrame(ld::PL_local_data{T}, fr::Int)::Int where {T}
    p = ld.frames[fr].parent
    p != 0 && return p
    return ld.queries[queryOfFrame(ld, fr)].saved_environment
end

# `lTop = p`, dropping the records at or above `p` when that LOWERS `lTop` (decision 3): the form of
# every assignment upstream makes that can raise or lower it.
function setLTop!(ld::PL_local_data{T}, p::Int)::Nothing where {T}
    if p < ld.lTop
        lowerLTop!(ld, p)
    else
        ld.lTop = p
    end
    return nothing
end

# A frame `normal_call` built above `lTop` whose own call FAILED before a supervisor raised `lTop`
# over it: `S_LIST` takes `FRAME_FAILED` first (vmi:3607-3608), as `S_UNDEF`'s `unknown=fail` does
# upstream (not reachable here: no module flags, src/pl-modul.jl). Upstream abandons it —
# `deep_backtrack` only resets `lTop` (vmi:6712). Here it is dropped
# where `deep_backtrack` leaves it: the ONE drop of a frame being filled that is allowed, on the
# failure path of its own call (user, 2026-10-05); `dropRecords!` still refuses every other. No
# position moves.
function _drop_unfilled_frame!(ld::PL_local_data{T}, fr::Int)::Nothing where {T}
    @assert fr == ld.nframes "_drop_unfilled_frame!: a frame being filled is the newest frame"
    @assert ld.frames[fr].base >= ld.lTop "_drop_unfilled_frame!: the frame was filled"
    ld.nframes = fr - 1
    return nothing
end

# Whether no record of any kind lies above position `p`.
function _no_record_above(ld::PL_local_data{T}, p::Int)::Bool where {T}
    return (ld.nframes == 0 || ld.frames[ld.nframes].base <= p) &&
           (ld.nchoices == 0 || ld.choices[ld.nchoices].base <= p) &&
           (ld.nfliframes == 0 || ld.fliframes[ld.nfliframes].base <= p) &&
           (ld.nqueries == 0 || ld.queries[ld.nqueries].base <= p)
end

# Whether frame `fr` is the newest live record — what last-call reuse relies on (user, 2026-10-05):
# a frame is reused in place only when everything above it is dead, and dead records are dropped on
# every lowering of `lTop`.
function _is_newest_live_frame(ld::PL_local_data{T}, fr::Int)::Bool where {T}
    return fr == ld.nframes && _no_record_above(ld, ld.frames[fr].base)
end

# The procedure a call operand names: an index into the RUNNING clause's procedure table (V1), read
# through `CL` — upstream's `#define CL (FR->clause)` (wam:3334) — where upstream's operand is the
# procedure pointer itself (user, 2026-10-05).
function _call_procedure(ld::PL_local_data{T}, fr::Int, op::code)::Procedure{T} where {T}
    return ((ld.frames[fr].clause::ClauseRef{T}).clause::Clause{T}).procedures[Int(op)]
end

# ── the argument pointer, the argument stack and the write-mode builder (decision 2, Q3) ─────────
# What `ARGP` points at, as is (upstream's `*ARGP`).
function _argp_raw(ld::PL_local_data{T}, a::argp_t{T})::T where {T}
    if a.form == ARGP_SLOT
        return ld.slots[a.pos + 1]
    elseif a.form == ARGP_CURSOR
        return child(a.term, a.pos)
    end
    return ld.bcells[a.pos]
end

# What `ARGP` points at, dereferenced (upstream's `deRef2(ARGP, k)`).
_argp_deref(ld::PL_local_data{T}, a::argp_t{T}) where {T} = deRef(ld, _argp_raw(ld, a))::T

# Write `t` where `ARGP` points (upstream's `*ARGP = t`): a builder cell, or a slot (body mode).
function _argp_store!(ld::PL_local_data{T}, a::argp_t{T}, t::T)::Nothing where {T}
    if a.form == ARGP_BUILD
        ld.bcells[a.pos] = t
    elseif a.form == ARGP_SLOT
        ld.slots[a.pos + 1] = t
    else
        error("_argp_store!: read mode never writes into the caller's term")
    end
    return nothing
end

# `ARGP + n`.
_argp_add(a::argp_t{T}, n::Int) where {T} = argp_t{T}(a.form, a.pos + n, a.term)

# The argument stack's height, and the builder's, back to what query `q` saved (`aTop = QF->aSave`):
# the builder is reset wherever upstream resets the argument stack (user, 2026-10-05).
function _reset_argument_stack!(ld::PL_local_data{T}, q::queryFrame{T})::Nothing where {T}
    ld.aTop = q.aSave
    ld.nbframes = q.bSave
    ld.bTop = q.bcSave
    return nothing
end

# Open a compound of `n` cells in the builder — the head symbol `head` in its first cell if `hashead`
# — going into the parent's builder cell `cell`, into the frame slot at position `slot` (a body
# argument, V4b), or (`cell` 0, `slot` -1) bound to the caller's unbound variable `var` when it is
# closed. Every argument cell starts as a fresh variable, as upstream
# `setVar`s every cell it allocates ("must clear if we want to do GC"): `H_VOID` and `H_VOID_N` skip
# cells in write mode. Returns the `ARGP` of its first argument cell.
function _bopen!(
    ld::PL_local_data{T}, n::Int, head::T, hashead::Bool, cell::Int, slot::Int, var::T
)::argp_t{T} where {T}
    start = ld.bTop + 1
    need = ld.bTop + n
    if need > length(ld.bcells)
        resize!(ld.bcells, max(need, 2 * length(ld.bcells)))
    end
    if hashead
        ld.bcells[start] = head
    end
    first = hashead ? start + 1 : start
    k = fresh_var_keys!(need - first + 1)
    for i in first:need                         # setVar(*ap++)
        ld.bcells[i] = mk_var(T, k + UInt64(i - first))
    end
    ld.bTop = need
    nb = ld.nbframes + 1
    if nb > length(ld.bframes)
        resize!(ld.bframes, 2 * length(ld.bframes))
    end
    ld.bframes[nb] = bframe{T}(start, n, cell, slot, var)
    ld.nbframes = nb
    return argp_t{T}(ARGP_BUILD, hashead ? start + 1 : start, ld.placeholder)
end

# Close the innermost compound being built — a cell never written holds the fresh variable it was
# opened with (the voids the compiler drops: `f(a,g(_))` ends in `h_rfunctor(g/1) h_pop`) — build it
# (`mk_expr`) and deliver it.
function _bclose!(ld::PL_local_data{T})::Nothing where {T}
    fr = ld.bframes[ld.nbframes]
    stop = fr.start + fr.n - 1
    t = mk_expr(T, ld.bcells[(fr.start):stop])
    ld.bTop = fr.start - 1
    ld.nbframes -= 1
    if fr.slot >= 0
        ld.slots[fr.slot + 1] = t               # a body argument: above lTop, untrailed
    elseif fr.cell != 0
        ld.bcells[fr.cell] = t                  # into the parent's cell, untrailed
    else
        Trail!(ld, var_key(fr.var), t)          # bindConst(p, c): the caller's variable
    end
    return nothing
end

# A compound of fresh variables: `head(V1, …, Vk)` when `hashead`, else `$expr(V1, …, Vn)` — what
# upstream allocates (`setVar` of every cell) before binding the caller's variable to it. Under
# `occurs_check` `true`/`error` the VM binds it at once and reads it (decision 3, DIVERGES).
function _fresh_compound(::Type{T}, head::T, hashead::Bool, n::Int)::T where {T}
    nv = hashead ? n - 1 : n
    k = fresh_var_keys!(nv)
    kids = Vector{T}(undef, n)
    i = 1
    if hashead
        kids[1] = head
        i = 2
    end
    for j in 0:(nv - 1)
        kids[i + j] = mk_var(T, k + UInt64(j))
    end
    return mk_expr(T, kids)
end

# Upstream's `LD->slow_unify` (pl-wam.c `updateAlerted`: `!PLFLAG_VMI_BUILTIN || occurs_check !=
# OCCURS_CHECK_FALSE`): whether a body unification calls `=/2`. Read where upstream reads the cached
# value; the kernel sets the flag as a field, so there is no `updateAlerted` to refresh a cache, and
# `vmi_builtin` is always true (no debugger).
_slow_unify(ld::PL_local_data)::Bool = ld.prolog_flag_occurs_check != OCCURS_CHECK_FALSE

# Whether `p` is a `$expr/3` — three children, a head that is not a symbol — which unifies with a list
# cell child by child (Q2; user, 2026-10-05: `[H|T]` and `'[|]'(H,T)` match the same way).
_is_expr3(p::T) where {T} =
    kind(p) === EXPR && nchildren(p) == 3 && kind(child(p, 1)) !== SYM

# ── the registers, saved and loaded (condition 3) ────────────────────────────────────────────────
# Write the run loop's `FR`, `ARGP` and `PC` into query `qid`'s record (`SAVE_REGISTERS`).
function _save_registers!(
    ld::PL_local_data{T}, qid::Int, fr::Int, argp::argp_t{T}, pcc::Vector{code},
    pcl::Vector{T},
    pc::Int
)::Nothing where {T}
    q = ld.queries[QueryFromQid(ld, qid)]
    q.registers_fr = fr
    q.registers_argp = argp
    q.registers_pc = Code{T}(pcc, pcl, pc)
    return nothing
end

# Read them back, clearing `registers.fr` (`LOAD_REGISTERS`).
function _load_registers!(
    ld::PL_local_data{T}, qid::Int
)::Tuple{Int, argp_t{T}, Vector{code}, Vector{T}, Int} where {T}
    q = ld.queries[QueryFromQid(ld, qid)]
    fr = q.registers_fr
    q.registers_fr = 0
    pc = q.registers_pc
    return (fr, q.registers_argp, pc.codes, pc.literals, pc.pc)
end

# PORT: pl-wam.c SAVE_REGISTERS
# DIVERGES: a macro over the run loop's locals, as upstream's; the work is `_save_registers!`, a
# function the static-analysis gate checks. `PC` is three locals (`PCc`, `PCl`, `PC`), and the query
# record is found by position (`QueryFromQid`).
"Save the run loop's registers into query `qid` (pl-wam.c), before calling out of the VM."
macro SAVE_REGISTERS(qid)
    return esc(:(_save_registers!(ld, $qid, FR, ARGP, PCc, PCl, PC)))
end

# PORT: pl-wam.c LOAD_REGISTERS
# DIVERGES: as `SAVE_REGISTERS`: the work is `_load_registers!`.
"Load the run loop's registers from query `qid` (pl-wam.c), after calling out of the VM."
macro LOAD_REGISTERS(qid)
    return esc(:((FR, ARGP, PCc, PCl, PC) = _load_registers!(ld, $qid)))
end

# PORT: pl-vmi.c TYPE_TEST
# DIVERGES: a macro over the run loop's locals, as upstream's, without its `functor` argument: that
# names the predicate of the `vmi_builtin=false` branch (`debug_pred1`), NOT PORTED — only the
# debugger and coverage clear the flag. `FASTCOND_FAILED` is `BODY_FAILED`: `LD->fast_condition` is
# set only by `C_FASTCOND` (V9).
"The body of a type-test instruction (pl-vmi.c `TYPE_TEST`): `test` the variable at the operand."
macro TYPE_TEST(test)
    return esc(
        quote
            tt_p = deRef(ld, ld.slots[varFrameP(ld.frames[FR].base, Int(PCc[PC])) + 1])
            PC += 1
            $test(tt_p) && @goto next_instruction
            @goto shallow_backtrack                 # FASTCOND_FAILED
        end
    )
end

# PORT: pl-vmi.c ENSURE_LOCAL_SPACE
# DIVERGES: in positions. The overflow raises a Julia `LocalStackOverflow` until V5d ports the stack
# limit's `resource_error` (`raiseStackOverflow`, its context as decided since Q-B), so its `ifnot`
# (`THROW_EXCEPTION`) is not reached.
"Make room for `n` positions above `lTop`, saving the registers around the growth (pl-vmi.c)."
macro ENSURE_LOCAL_SPACE(n)
    return esc(
        quote
            if ld.lTop > ld.lMax || !hasLocalSpace(ld, $n)
                @SAVE_REGISTERS(QID)
                els_rc = growLocalSpace(ld, $n, ALLOW_SHIFT)
                @LOAD_REGISTERS(QID)
                if els_rc != BOOLEX_TRUE
                    raiseStackOverflow(ld, els_rc)
                    @goto b_throw
                end
            end
        end
    )
end

# The run loop's dispatch (ORIGINAL), as a SORTED BRANCH TREE over the opcodes — decision 1's
# fallback. MEASURED 2026-10-05: LLVM makes no single jump table of an if/elseif chain over them; it
# makes four partial ones, broken wherever neighbouring arms share a target, so `S_LIST` was reached
# after nine decisions. The tree reaches each instruction in ⌈log2 n⌉ compares and one equality
# test; a code not listed falls through, past the tree.
function _vmi_dispatch_tree(x::Symbol, pairs::Vector{Tuple{UInt64, Symbol}})::Expr
    if length(pairs) <= 2
        return Expr(
            :block, (:(
                if $x == $v
                    $(Expr(:symbolicgoto, n))
                end
            ) for (v, n) in pairs)...
        )
    end
    mid = length(pairs) ÷ 2 + 1
    return :(
        if $x < $(pairs[mid][1])
            $(_vmi_dispatch_tree(x, pairs[1:(mid - 1)]))
        else
            $(_vmi_dispatch_tree(x, pairs[mid:end]))
        end
    )
end

"""
The instructions the run loop EXECUTES — the leaves of its dispatch tree, each a label of
`PL_next_solution_guarded`. Every other declared instruction (pl-vmi.jl) is refused by name with
`NotPortedError`; test/foreign/test_query.jl picks one of those to test the refusal (user,
2026-10-05), so this one list is what the dispatch and the test both read.
"""
const VMI_RUN = (
    :H_ATOM, :H_SMALLINT, :H_NIL, :H_FLOAT, :H_MPZ, :H_MPQ, :H_STRING, :H_VOID, :H_VOID_N,
    :H_VAR,
    :H_FIRSTVAR, :H_FUNCTOR, :H_RFUNCTOR, :H_LIST, :H_RLIST, :H_POP, :H_LIST_FF, :B_ATOM,
    :B_SMALLINT, :B_NIL, :B_FLOAT, :B_MPZ, :B_MPQ, :B_STRING, :B_ARGVAR, :B_VAR0, :B_VAR1,
    :B_VAR2,
    :B_VAR, :B_ARGFIRSTVAR, :B_FIRSTVAR, :B_VOID, :B_FUNCTOR, :B_RFUNCTOR, :B_LIST,
    :B_RLIST,
    :B_POP, :I_ENTER, :I_CALL, :I_DEPART, :I_EXIT, :I_EXITFACT, :I_EXITQUERY, :L_NOLCO,
    :L_VAR,
    :L_VOID, :L_ATOM, :L_NIL, :L_SMALLINT, :I_LCALL, :I_TCALL, :I_CUT, :S_VIRGIN, :S_UNDEF,
    :S_STATIC,
    :S_DYNAMIC, :S_MULTIFILE, :S_TRUSTME, :S_LIST, :I_FCALLDETVA, :I_FCALLDET0,
    :I_FCALLDET1,
    :I_FCALLDET2, :I_FCALLDET3, :I_FCALLDET4, :I_FCALLDET5, :I_FCALLDET6, :I_FCALLDET7,
    :I_FCALLDET8, :I_FCALLDET9, :I_FCALLDET10, :I_FEXITDET, :I_VAR, :I_NONVAR, :I_INTEGER,
    :I_RATIONAL, :I_FLOAT, :I_NUMBER, :I_ATOMIC, :I_ATOM, :I_STRING, :I_COMPOUND,
    :I_CALLABLE, :A_ADD_FC, :B_UNIFY_FIRSTVAR, :B_UNIFY_VAR, :B_UNIFY_EXIT, :B_UNIFY_FF,
    :B_UNIFY_VF, :B_UNIFY_FV, :B_UNIFY_VV, :B_UNIFY_FC, :B_UNIFY_VC, :B_EQ_VV, :B_EQ_VC,
    :B_NEQ_VV, :B_NEQ_VC, :C_VAR, :I_FAIL, :I_TRUE
)

"Jump to the label named after instruction `x`, one of those `table` names (a balanced tree of compares)."
macro vmi_dispatch(x, table::Symbol)
    names = getfield(__module__, table)::Tuple
    pairs = sort!([(UInt64(getfield(__module__, n)), n) for n in names]; by=first)
    return esc(_vmi_dispatch_tree(x, pairs))
end

# PORT: pl-wam.c resumeAfterException
# DIVERGES: no stack GC or trimming, no spare stacks; `fr_rewritten` is not kept.
"After an exception: clear it (when `clear`) and resume normal operation (pl-wam.c)."
function resumeAfterException(ld::PL_local_data{T}, clear::Bool)::Nothing where {T}
    if clear
        ld.exception_term = 0
        k = fresh_var_keys!(3)
        ld.slots[ld.exception_bin + 1] = mk_var(T, k)                  # setVar(*valTermRef(…))
        ld.slots[ld.exception_printed + 1] = mk_var(T, k + UInt64(1))
        ld.slots[ld.exception_pending + 1] = mk_var(T, k + UInt64(2))
    end
    return nothing
end

"""
    PrologThrow()

The kernel's `longjmp` for `PL_throw` (decision 1): thrown, with the exception pending, by a callback
that raises a Prolog exception out of a call; `PL_next_solution` catches it and re-enters its run
loop at the `except` arm. Nothing raises it yet: the foreign predicates ported (V5a2) raise with
`PL_raise_exception` and return false, never `PL_throw`.
"""
struct PrologThrow <: Exception end

# PORT: pl-wam.c initVM
# DIVERGES: returns the top clause and its reference for the database's global data (one per
# database, no process-wide `GD`), its predicate `$c_call_prolog/0` given.
"""
    initVM(dc_call_prolog) -> (top_clause, top_cref)

The one-instruction clause a query's frame returns to — `I_EXITQUERY` — and its reference
(pl-wam.c): created at generation 0, never erased, in no clause list.
"""
function initVM(dc::Procedure{T})::Tuple{Clause{T}, ClauseRef{T}} where {T}
    cl = Clause{T}(
        dc.definition,                  # cl->predicate = PROCEDURE_dc_call_prolog->definition
        gen_t(0),
        ~gen_t(0),                      # cl->generation.erased = ~(gen_t)0
        clsize_t(0),
        clsize_t(0),
        UInt32(0),
        code[I_EXITQUERY],              # cl->code_size = 1; cl->codes[0] = encode(I_EXITQUERY)
        T[],
        Procedure{T}[]
    )
    cref = ClauseRef{T}(nothing, word(0), cl, nothing)     # GD->clauses.top_cref.value.clause = cl
    return (cl, cref)
end

# ── the query API (decision 1) ────────────────────────────────────────────────────────────────────
"`PL_Q_DETERMINISTIC|PL_Q_EXT_STATUS` (pl-vmi.c `DET_EXIT`): a deterministic answer reported as such."
const DET_EXIT = PL_Q_DETERMINISTIC | PL_Q_EXT_STATUS

# PORT: pl-wam.c PL_open_query
# DIVERGES: the query is a record at `lTop`, with its CHP_TOP choice point and its top frame and
# frame as records at upstream's offsets (since V3; src/pl-incl.jl); its handle is its position
# (decision 1).
# NOT PORTED: `getProcDefinedDefinition` (until V5c: `autoImport`, no autoload), `globalizeTermRef`
# (a keyed variable lives in no cell, decision 2), the profiler, the debugger state `PL_Q_NODEBUG`
# saves (all but `FR_HIDE_CHILDS`), the context module of a transparent predicate, `updateAlerted`.
"""
    PL_open_query(gd, ld, ctx, flags, proc, args) -> qid, or 0

Open a query of procedure `proc` on the term references `args, args+1, …` (pl-wam.c). The caller
must hold an open foreign frame; the query becomes the innermost one.
"""
function PL_open_query(
    gd::PL_global_data{T}, ld::PL_local_data{T}, ctx::Union{Nothing, module_t{T}},
    flags::UInt32,
    proc::Procedure{T}, args::Int
)::Int where {T}
    env = ld.environment_frame
    @assert env == 0 || ld.fliframes[ld.fli_context].base > ld.frames[env].base
    @assert ld.lTop >=
        refFliP(ld.fliframes[ld.fli_context].base, ld.fliframes[ld.fli_context].size)

    def = proc.definition                       # getProcDefinedDefinition(): not ported (see above)
    arity = def.arity

    lneeded = SIZEOF_QUERYFRAME + MAXARITY
    if !ensureLocalSpace(ld, lneeded)
        return 0
    end

    qf = pushQuery!(ld, ld.lTop)                # qf = (QueryFrame)lTop;
    q = ld.queries[qf]
    q.saved_ltop = ld.lTop

    ch = pushChoice!(ld, q.base + QF_CHOICE)    # the embedded choice, top frame and frame
    top = pushFrame!(ld, q.base + QF_TOP_FRAME)
    fr = pushFrame!(ld, q.base + QF_FRAME)
    q.choice, q.top_frame, q.frame = ch, top, fr

    t = ld.frames[top]                          # fill top-frame
    t.parent = 0
    t.predicate = gd.procedures_dc_call_prolog0.definition
    t.programPointer = ld.null_code
    t.clause = gd.clauses_top_cref
    if env != 0
        setNextFrameFlags(t, ld.frames[env])
        t.flags &= ~FR_INRESET                  # shift/1 can't pass callbacks
    else
        t.flags = FR_MAGIC
        t.level = UInt32(0)
    end
    f = ld.frames[fr]
    f.parent = top
    setNextFrameFlags(f, t)
    t.flags |= FR_HIDE_CHILDS
    f.programPointer = Code(gd.clauses_top_clause, 1)

    if flags == UInt32(1)                       # compatibility: `true`
        flags = PL_Q_NORMAL
    elseif flags == UInt32(0)                   # `false`
        flags = PL_Q_NODEBUG
    end
    flags &= ~PL_Q_DETERMINISTIC                # mask reserved flags

    q.magic = QID_MAGIC
    q.foreign_frame = 0
    q.flags = flags
    q.saved_environment = env
    @assert parentFrame(ld, top) == env
    q.saved_bfr = ld.BFR
    q.aSave = ld.aTop
    q.bSave = ld.nbframes
    q.bcSave = ld.bTop
    q.solutions = 0
    q.exception = 0
    q.registers_fr = 0                          # invalid
    q.next_environment = 0                      # see D_BREAK
    # fill frame arguments
    ap = argFrameP(f.base, 0)
    for n in 0:(arity - 1)
        ld.slots[ap + 1] = linkValI(ld, ld.slots[args + n + 1])
        ap += 1
    end
    ld.lTop = ap                                # lTop above the arguments

    if (flags & PL_Q_NODEBUG) != 0
        f.flags |= FR_HIDE_CHILDS
    end
    f.predicate = def
    f.clause = nothing
    # create initial choicepoint
    c = ld.choices[ch]
    c.type = CHP_TOP
    c.parent = 0
    c.frame = top
    c.mark = Mark(ld)
    setGenerationFrame(gd, ld, fr)
    # publish environment
    ld.BFR = ch
    ld.environment_frame = fr
    q.parent = ld.query
    ld.query = qf

    return QidFromQuery(ld, qf)
end

# PORT: pl-wam.c discard_query
# DIVERGES: `frameFinished` on an `FR_WATCHED` query frame is not ported (setup_call_cleanup, V9).
"Discard the choice points and frames a non-deterministic query left (pl-wam.c)."
function discard_query(ld::PL_local_data{T}, qid::Int)::Nothing where {T}
    q = ld.queries[QueryFromQid(ld, qid)]
    discardChoicesAfter(ld, q.frame, FINISH_CUT)
    q = ld.queries[QueryFromQid(ld, qid)]       # may be shifted
    discardFrame(ld, q.frame)
    @assert (ld.frames[q.frame].flags & FR_WATCHED) == 0
    return nothing
end

# PORT: pl-wam.c restore_after_query
# DIVERGES: lowering `lTop` drops the query's records and everything above them (decision 3). Not
# ported: the debugger state `PL_Q_NODEBUG` restores, `updateAlerted`.
"Restore the state the query was opened in (pl-wam.c)."
function restore_after_query(ld::PL_local_data{T}, qf::Int)::Nothing where {T}
    q = ld.queries[qf]
    if q.exception != 0 && ld.exception_term == 0
        ld.slots[ld.exception_printed + 1] = mk_var(T, fresh_var_keys!(1))
    end

    DiscardMark(ld, ld.choices[q.choice].mark)

    ld.query = q.parent
    ld.BFR = q.saved_bfr
    ld.environment_frame = q.saved_environment
    _reset_argument_stack!(ld, q)
    lowerLTop!(ld, q.saved_ltop)
    return nothing
end

# Shared by `PL_cut_query` and `PL_close_query` (upstream's two bodies are identical but the `Undo`).
function _end_query(ld::PL_local_data{T}, qid::Int, close::Bool)::Int where {T}
    rc = 1
    if qid != 0
        qf = QueryFromQid(ld, qid)
        if qf == 0 || ld.query != qf            # DIVERGES: 0 is a closed or stale handle
            return PL_S_NOT_INNER
        end
        q = ld.queries[qf]
        @assert q.magic == QID_MAGIC
        if q.foreign_frame != 0
            PL_close_foreign_frame(ld, q.foreign_frame)
        end

        if (q.flags & PL_Q_DETERMINISTIC) == 0
            exbefore = ld.exception_term != 0

            discard_query(ld, qid)
            q = ld.queries[QueryFromQid(ld, qid)]
            if !exbefore && ld.exception_term != 0
                rc = 0
            end
        end

        if close && !(q.exception != 0 && (q.flags & PL_Q_PASS_EXCEPTION) != 0)
            Undo!(ld, ld.choices[q.choice].mark)
        end

        restore_after_query(ld, qf)
        q.magic = QID_CMAGIC                    # disqualify the frame
    end
    return rc
end

# PORT: pl-wam.c PL_cut_query
"End query `qid`, keeping the bindings of its last answer (pl-wam.c): 1, 0, or `PL_S_NOT_INNER`."
PL_cut_query(ld::PL_local_data{T}, qid::Int) where {T} = _end_query(ld, qid, false)::Int

# PORT: pl-wam.c PL_close_query
"End query `qid`, undoing its bindings (pl-wam.c): 1, 0, or `PL_S_NOT_INNER`."
PL_close_query(ld::PL_local_data{T}, qid::Int) where {T} = _end_query(ld, qid, true)::Int

# PORT: pl-wam.c PL_exception
"The exception query `qid` raised (a new term reference), or 0; with `qid` 0, the pending one (pl-wam.c)."
function PL_exception(ld::PL_local_data{T}, qid::Int)::Int where {T}
    if qid != 0
        q = ld.queries[QueryFromQid(ld, qid)]

        if q.exception != 0
            env = ld.environment_frame
            if env != 0 && ld.fliframes[ld.fli_context].base <= ld.frames[env].base
                error("PL_exception(): No foreign environment")      # fatalError()
            end

            ex = PL_new_term_ref(ld)
            PL_put_term(ld, ex, q.exception)
            return ex
        end

        return 0
    end
    return ld.exception_term
end

# PORT: pl-wam.c PL_current_query
"The handle of the innermost open query, or 0 (pl-wam.c)."
function PL_current_query(ld::PL_local_data{T})::Int where {T}
    if ld.query != 0 && ld.queries[ld.query].magic == QID_MAGIC
        return QidFromQuery(ld, ld.query)
    end
    return 0
end

# PORT: pl-wam.c PL_next_solution
# DIVERGES: Julia's `try`/`catch` stands for upstream's `setjmp` (decision 1). `@goto` cannot cross a
# `try`, so the whole run loop is `PL_next_solution_guarded`, inside one `try`; the handler is
# outside, and re-enters the loop at its single entry with `except` set — upstream's re-entry after
# `PL_throw`'s `longjmp` (`jc == 1`). The kernel's `PL_throw` is a `PrologThrow` (raised by nothing
# yet). Any other Julia exception — a bug, an interrupt, a stack-limit overflow — ends the query
# (closed, as `PL_close_query` would) and is rethrown, never swallowed (decision 1).
"""
    PL_next_solution(gd, ld, qid) -> Int

The next answer of query `qid` (pl-wam.c): `PL_S_TRUE` (1), `PL_S_LAST` (2, a deterministic last
answer under `PL_Q_EXT_STATUS`), `PL_S_FALSE` (0), `PL_S_EXCEPTION` (-1, under `PL_Q_EXT_STATUS`; 0
otherwise, with `PL_exception(qid)` set), or `PL_S_NOT_INNER` (-2). While an answer is current its
bindings are in `ld`.
"""
function PL_next_solution(
    gd::PL_global_data{T}, ld::PL_local_data{T}, qid::Int
)::Int where {T}
    except = false
    while true
        try
            return PL_next_solution_guarded(gd, ld, qid, except)
        catch e
            if e isa PrologThrow
                except = true
            else
                _abandon_query(ld, qid)
                rethrow()
            end
        end
    end
end

# A Julia exception left query `qid` mid-step: close it as `PL_close_query` would, first dropping the
# foreign frames the step left open above it (decision 1).
function _abandon_query(ld::PL_local_data{T}, qid::Int)::Nothing where {T}
    qf = QueryFromQid(ld, qid)
    (qf == 0 || ld.query != qf) && return nothing
    q = ld.queries[qf]
    while ld.fli_context != 0 && ld.fliframes[ld.fli_context].base >= q.base
        ld.fli_context = ld.fliframes[ld.fli_context].parent
    end
    q.foreign_frame = 0
    q.flags &= ~PL_Q_DETERMINISTIC
    ld.exception_term = 0
    _end_query(ld, qid, true)
    return nothing
end

# PORT: pl-wam.c PL_next_solution_guarded
# DIVERGES: upstream's `switch` build (`!VMCODE_IS_ADDRESS`; user, 2026-10-05), as ONE function: every
# instruction and helper of pl-vmi.c is a `@label` here, with its `# PORT: pl-vmi.c` marker, in
# pl-vmi.c's order, and the dispatch is an `if`/`elseif` chain over the dense opcodes. The registers
# are typed locals (wam:3323-3358): `PC` is three (`PCc`, the code; `PCl`, its literal table; `PC`, the
# index of the next word); `CL` is `FR`'s `clause`; `BFR`, `environment_frame`, `lTop` and
# `fli_context` live in `ld`, as upstream's in `LD`. A helper's arguments (`helper_args`) are locals
# named for the helper. Instructions not ported yet raise `NotPortedError` (their step in
# port_inventory). Blocks for subsystems not ported are marked `NOT PORTED` where they stand: the
# signals, debugger, profiler, depth and inference limits of `LD->alerted`; `FR_WATCHED`
# (`frameFinished`: setup_call_cleanup, V9); `FR_DET`/`FR_DETGUARD` (det declarations); yield.
"""
    PL_next_solution_guarded(gd, ld, qid, except) -> Int

The run loop of `PL_next_solution` (pl-wam.c): enter query `qid` — at its first call, a retry, or
(`except`) after a `PrologThrow` — and run instructions until an answer, a failure or an uncaught
exception returns.
"""
function PL_next_solution_guarded(
    gd::PL_global_data{T}, ld::PL_local_data{T}, qid::Int, except::Bool
)::Int where {T}
    ph = ld.placeholder
    # register_file REGISTERS, zeroed (wam:3585)
    UMODE::unify_mode = uread
    QID::Int = qid
    QF::Int = 0
    FR::Int = 0
    NFR::Int = 0                                    # the frame a call builds (wam:3336)
    ARGP::argp_t{T} = argp_t{T}(ARGP_SLOT, 0, ph)
    DEF::Definition{T} = gd.procedures_dc_call_prolog0.definition
    PCc::Vector{code} = gd.code_data.exit           # Code PC = NULL
    PCl::Vector{T} = gd.no_literals
    PC::Int = 0
    thiscode::code = code(0)
    # the helpers' arguments (upstream's `helper_args`)
    hc_c::T = ph                                    # h_const's constant
    tc_cref::ClauseRef{T} = gd.clauses_top_cref     # TRUST_CLAUSE's clause
    bv_voffset::Int = 0                             # bvar_cont's voffset
    fexitdet_rc::foreign_t = FTRUE                  # I_FEXITDET's rc
    SLOW_UNIFY::Bool = false                        # unify_var_cont's copy of LD->slow_unify
    bu_first::Bool = false                          # unify_var_cont came from B_UNIFY_FIRSTVAR
    bu_hold::Int = 0                                # B_UNIFY_FIRSTVAR's holder cell (0: none)
    bu_var::T = ph                                  # B_UNIFY_FIRSTVAR's fresh variable

    if qid == 0                                     # PL_open_query() failed
        return 0
    end

    QF = QueryFromQid(ld, qid)
    if QF == 0                                      # DIVERGES: a closed handle is on no chain
        return 0
    end
    q = ld.queries[QF]
    if q.magic == QID_CMAGIC
        return 0
    end
    if ld.query != QF
        return PL_S_NOT_INNER
    end
    if (q.flags & PL_Q_DETERMINISTIC) != 0          # last one succeeded
        fid = q.foreign_frame
        q.foreign_frame = 0
        PL_close_foreign_frame(ld, fid)
        Undo!(ld, ld.choices[q.choice].mark)
        return 0                                    # fail
    end
    FR = q.frame
    ARGP = argp_t{T}(ARGP_SLOT, argFrameP(ld.frames[FR].base, 0), ph)

    if except
        ffr = ld.fli_context

        FR = ld.environment_frame
        DEF = ld.frames[FR].predicate::Definition{T}
        while ffr != 0 && ld.fliframes[ffr].base > ld.frames[FR].base   # discard foreign contexts
            ffr = ld.fliframes[ffr].parent
        end
        ld.fli_context = ffr
        # NOT PORTED: AR_CLEANUP (it has nothing to do here, see src/pl-arith.jl); the signal being
        # handled (no signals)
        @goto b_throw                               # THROW_EXCEPTION
    end

    DEF = ld.frames[FR].predicate::Definition{T}
    # NOT PORTED: resuming after a yield (decision 1)
    if q.solutions != 0                             # retry
        fid = q.foreign_frame
        q.foreign_frame = 0
        PL_close_foreign_frame(ld, fid)
        @goto shallow_backtrack                     # BODY_FAILED
    else                                            # first call
        @goto depart_or_retry_continue
    end

    @label next_instruction
    thiscode = PCc[PC]
    PC += 1
    @vmi_dispatch(thiscode, VMI_RUN)
    throw(
        NotPortedError{T}(
            DEF.name, "the VM instruction $(codeTable(thiscode).name)", "V4b and later"
        )
    )

    # ── head instructions (pl-vmi.c) ──────────────────────────────────────────────────────────────
    # PORT: pl-vmi.c H_ATOM
    # DIVERGES: the operand indexes the clause's literal table (since V1 L2); no atom GC, so no
    # `pushVolatileAtom`.
    @label H_ATOM
    if UMODE == uwrite
        @goto B_ATOM
    end
    hc_c = PCl[PCc[PC]]
    PC += 1
    @goto h_const

    # PORT: pl-vmi.c H_SMALLINT
    @label H_SMALLINT
    if UMODE == uwrite
        @goto B_SMALLINT
    end
    hc_c = PCl[PCc[PC]]
    PC += 1
    @goto h_const

    # PORT: pl-vmi.c h_const
    # DIVERGES: `unify_simple_ptrs` decides, which has h_const's three outcomes for a constant — the same
    # constant (SWI's identity: `sym_key`, `gnd_equal`), an unbound variable (bound, trailed), anything
    # else; there is no global stack to grow.
    @label h_const
    if unify_simple_ptrs(ld, _argp_deref(ld, ARGP), hc_c) == BOOLEX_TRUE
        ARGP = _argp_add(ARGP, 1)
        @goto next_instruction
    end
    @goto unify_backtrack                           # CLAUSE_FAILED

    # PORT: pl-vmi.c H_NIL
    # DIVERGES: as `h_const`, with the database's `[]`.
    @label H_NIL
    if UMODE == uwrite
        @goto B_NIL
    end
    if unify_simple_ptrs(ld, _argp_deref(ld, ARGP), gd.atom_nil) == BOOLEX_TRUE
        ARGP = _argp_add(ARGP, 1)
        @goto next_instruction
    end
    @goto unify_backtrack

    # PORT: pl-vmi.c H_FLOAT
    # DIVERGES: the operand is one word, the literal's index (since V1 L2); identity and binding as `h_const`
    # (`gnd_equal` is the bitwise comparison upstream makes).
    @label H_FLOAT
    if UMODE == uwrite
        @goto B_FLOAT
    end
    if unify_simple_ptrs(ld, _argp_deref(ld, ARGP), PCl[PCc[PC]]) == BOOLEX_TRUE
        PC += 1
        ARGP = _argp_add(ARGP, 1)
        @goto next_instruction
    end
    @goto unify_backtrack

    # PORT: pl-vmi.c H_MPZ
    @label H_MPZ
    @goto H_STRING                                  # SEPARATE_VMI1; VMI_GOTO(H_STRING)

    # PORT: pl-vmi.c H_MPQ
    @label H_MPQ
    @goto H_STRING                                  # SEPARATE_VMI2; VMI_GOTO(H_STRING)

    # PORT: pl-vmi.c H_STRING
    # DIVERGES: as `H_FLOAT`: one operand word, the literal; `gnd_equal` compares kind and bits, as
    # `VM_equalIndirectFromCode` compares the header and the data.
    @label H_STRING
    if UMODE == uwrite
        @goto B_STRING
    end
    if unify_simple_ptrs(ld, _argp_deref(ld, ARGP), PCl[PCc[PC]]) == BOOLEX_TRUE
        PC += 1
        ARGP = _argp_add(ARGP, 1)
        @goto next_instruction
    end
    @goto unify_backtrack

    # PORT: pl-vmi.c H_VOID
    @label H_VOID
    ARGP = _argp_add(ARGP, 1)
    @goto next_instruction

    # PORT: pl-vmi.c H_VOID_N
    @label H_VOID_N
    ARGP = _argp_add(ARGP, Int(PCc[PC]))
    PC += 1
    @goto next_instruction

    # PORT: pl-vmi.c H_VAR
    # DIVERGES (decision 2): in write mode under `occurs_check=false` the dereferenced slot is COPIED
    # into the cell — the address rules (`k > ARGP`, the trail space) disappear, as a keyed variable
    # lives in no cell. Under `true`/`error` the VM never enters write mode (decision 3), so the
    # `setVar(*ARGP)` branch is not reached.
    @label H_VAR
    hv_k = varFrameP(ld.frames[FR].base, Int(PCc[PC]))
    PC += 1
    if UMODE == uwrite
        @assert ld.prolog_flag_occurs_check == OCCURS_CHECK_FALSE "write mode under occurs_check true/error (decision 3)"
        _argp_store!(ld, ARGP, deRef(ld, ld.slots[hv_k + 1]))
        ARGP = _argp_add(ARGP, 1)
        @goto next_instruction
    end
    # First try the simple case.
    if ld.prolog_flag_occurs_check == OCCURS_CHECK_FALSE
        hv_rc = do_unify(ld, ld.slots[hv_k + 1], _argp_raw(ld, ARGP))
        if hv_rc == BOOLEX_TRUE
            ARGP = _argp_add(ARGP, 1)
            @goto next_instruction
        end
        if hv_rc == BOOLEX_FALSE
            @goto unify_backtrack
        end
    end

    @SAVE_REGISTERS(QID)
    hv_ok = unify_ptrs(ld, ld.slots[hv_k + 1], _argp_raw(ld, ARGP))
    @LOAD_REGISTERS(QID)
    if hv_ok
        ARGP = _argp_add(ARGP, 1)
        @goto next_instruction
    end
    if ld.exception_term != 0
        @goto b_throw                               # THROW_EXCEPTION
    end
    @goto unify_backtrack

    # PORT: pl-vmi.c H_FIRSTVAR
    # DIVERGES: a cell is a term: in write mode a fresh variable goes into both the cell and the slot;
    # in read mode the slot holds the caller's child as it is (upstream's reference to the cell).
    @label H_FIRSTVAR
    hfv_k = varFrameP(ld.frames[FR].base, Int(PCc[PC]))
    PC += 1
    if UMODE == uwrite
        hfv_v = mk_var(T, fresh_var_keys!(1))      # setVar(*ARGP)
        _argp_store!(ld, ARGP, hfv_v)
        ld.slots[hfv_k + 1] = hfv_v                 # varFrame(FR, *PC++) = makeRefG(ARGP)
    else
        ld.slots[hfv_k + 1] = _argp_raw(ld, ARGP)
    end
    ARGP = _argp_add(ARGP, 1)
    @goto next_instruction

    # PORT: pl-vmi.c H_FUNCTOR
    # DIVERGES: the entry records the builders open (decision 2, Q3).
    @label H_FUNCTOR
    pushArgumentStack(
        ld, argstack_entry{T}(_argp_add(ARGP, 1), UMODE == uwrite, ld.nbframes)
    )
    @goto H_RFUNCTOR

    # PORT: pl-vmi.c H_RFUNCTOR
    # DIVERGES: on an unbound argument under `occurs_check=false` a BUILDER is opened (decision 2, Q3)
    # and the argument is bound when it closes; under `true`/`error` the compound of fresh variables
    # is built and bound at once and READ (decision 3) — the same bindings, failures and error terms.
    # A bound argument matches by Q2's rule (user, 2026-10-04): `f/k` a compound of k+1 children
    # whose head is `f`, or whose head is not a symbol and unifies with `f`; `$expr/n` (literal 0)
    # any compound of n children, read from its head.
    @label H_RFUNCTOR
    if UMODE == uwrite
        @goto B_RFUNCTOR
    end
    hf_f = PCc[PC]
    PC += 1
    hf_lit = functor_literal(hf_f)
    hf_ar = functor_arity(hf_f)
    hf_p = _argp_deref(ld, ARGP)
    if kind(hf_p) === VAR                           # canBind(*p)
        hf_n = hf_lit == 0 ? hf_ar : hf_ar + 1
        hf_head = hf_lit == 0 ? ph : PCl[hf_lit]
        if ld.prolog_flag_occurs_check == OCCURS_CHECK_FALSE
            ARGP = _bopen!(ld, hf_n, hf_head, hf_lit != 0, 0, -1, hf_p)
            UMODE = uwrite
        else
            hf_t = _fresh_compound(T, hf_head, hf_lit != 0, hf_n)
            Trail!(ld, var_key(hf_p), hf_t)         # bindConst(p, c)
            ARGP = argp_t{T}(ARGP_CURSOR, hf_lit == 0 ? 1 : 2, hf_t)
        end
        @goto next_instruction
    end
    if kind(hf_p) === EXPR                          # hasFunctor(*p, f)
        if hf_lit == 0
            if nchildren(hf_p) == hf_ar
                ARGP = argp_t{T}(ARGP_CURSOR, 1, hf_p)
                @goto next_instruction
            end
        elseif nchildren(hf_p) == hf_ar + 1
            hf_h = deRef(ld, child(hf_p, 1))
            if kind(hf_h) === SYM
                if sym_key(hf_h) == sym_key(PCl[hf_lit])
                    ARGP = argp_t{T}(ARGP_CURSOR, 2, hf_p)      # ARGP = argTermP(*p, 0)
                    @goto next_instruction
                end
            elseif kind(child(hf_p, 1)) !== SYM &&
                unify_simple_ptrs(ld, hf_h, PCl[hf_lit]) == BOOLEX_TRUE
                ARGP = argp_t{T}(ARGP_CURSOR, 2, hf_p)
                @goto next_instruction
            end
        end
    end
    @goto unify_backtrack

    # PORT: pl-vmi.c H_LIST
    @label H_LIST
    pushArgumentStack(
        ld, argstack_entry{T}(_argp_add(ARGP, 1), UMODE == uwrite, ld.nbframes)
    )
    @goto H_RLIST

    # PORT: pl-vmi.c H_RLIST
    # DIVERGES: as `H_RFUNCTOR` for `'[|]'/2`, a `$expr/3` included (Q2; user, 2026-10-05).
    @label H_RLIST
    if UMODE == uwrite
        @goto B_RLIST
    end
    hl_p = _argp_deref(ld, ARGP)
    if kind(hl_p) === EXPR
        if is_pair(hl_p) ||
            (
            _is_expr3(hl_p) &&
            unify_simple_ptrs(ld, deRef(ld, child(hl_p, 1)), gd.atom_dot) == BOOLEX_TRUE
        )
            ARGP = argp_t{T}(ARGP_CURSOR, 2, hl_p)  # ARGP = argTermP(w, 0)
            @goto next_instruction
        end
        @goto unify_backtrack
    elseif kind(hl_p) === VAR
        if ld.prolog_flag_occurs_check == OCCURS_CHECK_FALSE
            ARGP = _bopen!(ld, 3, gd.atom_dot, true, 0, -1, hl_p)
            UMODE = uwrite
        else
            hl_t = _fresh_compound(T, gd.atom_dot, true, 3)
            Trail!(ld, var_key(hl_p), hl_t)
            ARGP = argp_t{T}(ARGP_CURSOR, 2, hl_t)
        end
        @goto next_instruction
    end
    @goto unify_backtrack

    # PORT: pl-vmi.c H_POP
    # DIVERGES: popping the entry also closes the compounds being built since it was pushed
    # (decision 2, Q3) — upstream filled them in place.
    @label H_POP
    hp_e = ld.astack[ld.aTop]                       # ARGP = *--aTop
    ld.aTop -= 1
    ARGP = hp_e.argp
    UMODE = hp_e.uwrite ? uwrite : uread
    while ld.nbframes > hp_e.builders
        _bclose!(ld)
    end
    @goto next_instruction

    # PORT: pl-vmi.c H_LIST_FF
    # DIVERGES: a cell is a term (see `H_FIRSTVAR`); a `$expr/3` matches as a list cell (Q2).
    @label H_LIST_FF
    hff_a = varFrameP(ld.frames[FR].base, Int(PCc[PC]))
    hff_b = varFrameP(ld.frames[FR].base, Int(PCc[PC + 1]))
    PC += 2
    if UMODE == uwrite
        hff_k = fresh_var_keys!(2)
        hff_x = mk_var(T, hff_k)
        hff_y = mk_var(T, hff_k + UInt64(1))
        ld.slots[hff_a + 1] = hff_x
        ld.slots[hff_b + 1] = hff_y
        _argp_store!(ld, ARGP, mk_expr(T, T[gd.atom_dot, hff_x, hff_y]))   # *p = c
    else
        hff_p = _argp_deref(ld, ARGP)
        if is_pair(hff_p) ||
            (
            _is_expr3(hff_p) &&
            unify_simple_ptrs(ld, deRef(ld, child(hff_p, 1)), gd.atom_dot) == BOOLEX_TRUE
        )
            ld.slots[hff_a + 1] = child(hff_p, 2)
            ld.slots[hff_b + 1] = child(hff_p, 3)
        elseif kind(hff_p) === VAR
            hff_k = fresh_var_keys!(2)
            hff_x = mk_var(T, hff_k)
            hff_y = mk_var(T, hff_k + UInt64(1))
            ld.slots[hff_a + 1] = hff_x
            ld.slots[hff_b + 1] = hff_y
            Trail!(ld, var_key(hff_p), mk_expr(T, T[gd.atom_dot, hff_x, hff_y]))   # bindConst
        else
            @goto unify_backtrack
        end
    end
    ARGP = _argp_add(ARGP, 1)
    @goto next_instruction

    # ── body instructions: a body's arguments, and the head's write mode (pl-vmi.c) ─────────────
    # PORT: pl-vmi.c B_ATOM
    @label B_ATOM
    _argp_store!(ld, ARGP, PCl[PCc[PC]])            # *ARGP++ = code2atom(*PC++)
    PC += 1
    ARGP = _argp_add(ARGP, 1)
    @goto next_instruction

    # PORT: pl-vmi.c B_SMALLINT
    @label B_SMALLINT
    _argp_store!(ld, ARGP, PCl[PCc[PC]])
    PC += 1
    ARGP = _argp_add(ARGP, 1)
    @goto next_instruction

    # PORT: pl-vmi.c B_NIL
    @label B_NIL
    _argp_store!(ld, ARGP, gd.atom_nil)
    ARGP = _argp_add(ARGP, 1)
    @goto next_instruction

    # PORT: pl-vmi.c B_FLOAT
    @label B_FLOAT
    _argp_store!(ld, ARGP, PCl[PCc[PC]])
    PC += 1
    ARGP = _argp_add(ARGP, 1)
    @goto next_instruction

    # PORT: pl-vmi.c B_MPZ
    @label B_MPZ
    @goto B_STRING

    # PORT: pl-vmi.c B_MPQ
    @label B_MPQ
    @goto B_STRING

    # PORT: pl-vmi.c B_STRING
    @label B_STRING
    _argp_store!(ld, ARGP, PCl[PCc[PC]])
    PC += 1
    ARGP = _argp_add(ARGP, 1)
    @goto next_instruction

    # PORT: pl-vmi.c B_ARGVAR
    # DIVERGES: the variable's value, dereferenced, into the builder cell. A keyed variable is its own
    # reference and no cell is bound to point at another (decision 2), so the test that chooses the
    # direction of the link (`ARGP < k`) and the trail-space check disappear.
    @label B_ARGVAR
    _argp_store!(
        ld, ARGP, deRef(ld, ld.slots[varFrameP(ld.frames[FR].base, Int(PCc[PC])) + 1])
    )
    PC += 1
    ARGP = _argp_add(ARGP, 1)
    @goto next_instruction

    # PORT: pl-vmi.c B_VAR0
    @label B_VAR0
    bv_voffset = Int(VAROFFSET(0))
    @goto bvar_cont

    # PORT: pl-vmi.c B_VAR1
    @label B_VAR1
    bv_voffset = Int(VAROFFSET(1))
    @goto bvar_cont

    # PORT: pl-vmi.c B_VAR2
    @label B_VAR2
    bv_voffset = Int(VAROFFSET(2))
    @goto bvar_cont

    # PORT: pl-vmi.c B_VAR
    @label B_VAR
    bv_voffset = Int(PCc[PC])
    PC += 1
    @goto bvar_cont

    # PORT: pl-vmi.c bvar_cont
    # DIVERGES: a helper label, its argument `bv_voffset`. No `globaliseVar`: a keyed variable lives in
    # no cell (decision 2), so the slot's term is stored as is (`linkValI`).
    @label bvar_cont
    _argp_store!(
        ld, ARGP, linkValI(ld, ld.slots[varFrameP(ld.frames[FR].base, bv_voffset) + 1])
    )
    ARGP = _argp_add(ARGP, 1)
    @goto next_instruction

    # PORT: pl-vmi.c B_ARGFIRSTVAR
    # DIVERGES: a fresh variable into the builder cell and the slot (`setVar` + `makeRefG`).
    @label B_ARGFIRSTVAR
    baf_v = mk_var(T, fresh_var_keys!(1))
    _argp_store!(ld, ARGP, baf_v)                   # setVar(*ARGP)
    ld.slots[varFrameP(ld.frames[FR].base, Int(PCc[PC])) + 1] = baf_v   # varFrame(FR, *PC++)
    PC += 1
    ARGP = _argp_add(ARGP, 1)
    @goto next_instruction

    # PORT: pl-vmi.c B_FIRSTVAR
    # DIVERGES: a fresh variable into the slot and the argument; no global stack, so no
    # `ENSURE_GLOBAL_SPACE`.
    @label B_FIRSTVAR
    bfv_v = mk_var(T, fresh_var_keys!(1))
    ld.slots[varFrameP(ld.frames[FR].base, Int(PCc[PC])) + 1] = bfv_v   # *k = w
    PC += 1
    _argp_store!(ld, ARGP, bfv_v)                   # *ARGP++ = w
    ARGP = _argp_add(ARGP, 1)
    @goto next_instruction

    # PORT: pl-vmi.c B_VOID
    @label B_VOID
    _argp_store!(ld, ARGP, mk_var(T, fresh_var_keys!(1)))  # setVar(*ARGP++)
    ARGP = _argp_add(ARGP, 1)
    @goto next_instruction

    # PORT: pl-vmi.c B_FUNCTOR
    # DIVERGES: the entry records the builders open (decision 2, Q3); no mode bit, as upstream.
    @label B_FUNCTOR
    pushArgumentStack(ld, argstack_entry{T}(_argp_add(ARGP, 1), false, ld.nbframes))
    @goto B_RFUNCTOR

    # PORT: pl-vmi.c B_RFUNCTOR
    # DIVERGES: the compound is built in a builder (decision 2, Q3), and goes into the current builder
    # cell — inside a compound — or into the frame slot `ARGP` points at — a body argument (since V4b) —
    # when it is closed: upstream puts the pointer there at once and fills the cells in place.
    @label B_RFUNCTOR
    bf_f = PCc[PC]
    PC += 1
    bf_lit = functor_literal(bf_f)
    bf_ar = functor_arity(bf_f)
    @assert ARGP.form != ARGP_CURSOR "B_RFUNCTOR: a body argument is written, never read"
    ARGP = _bopen!(
        ld, bf_lit == 0 ? bf_ar : bf_ar + 1, bf_lit == 0 ? ph : PCl[bf_lit], bf_lit != 0,
        ARGP.form == ARGP_BUILD ? ARGP.pos : 0, ARGP.form == ARGP_SLOT ? ARGP.pos : -1, ph
    )
    @goto next_instruction

    # PORT: pl-vmi.c B_LIST
    # DIVERGES: as `B_FUNCTOR`.
    @label B_LIST
    pushArgumentStack(ld, argstack_entry{T}(_argp_add(ARGP, 1), false, ld.nbframes))
    @goto B_RLIST

    # PORT: pl-vmi.c B_RLIST
    # DIVERGES: as `B_RFUNCTOR`, for a list cell.
    @label B_RLIST
    @assert ARGP.form != ARGP_CURSOR "B_RLIST: a body argument is written, never read"
    ARGP = _bopen!(
        ld, 3, gd.atom_dot, true, ARGP.form == ARGP_BUILD ? ARGP.pos : 0,
        ARGP.form == ARGP_SLOT ? ARGP.pos : -1, ph
    )
    @goto next_instruction

    # PORT: pl-vmi.c B_POP
    # DIVERGES: popping the entry also closes the compounds built since it was pushed (decision 2, Q3)
    # — the outermost into its frame slot. `UMODE` is untouched, as upstream.
    @label B_POP
    bp_e = ld.astack[ld.aTop]                       # ARGP = *--aTop
    ld.aTop -= 1
    ARGP = bp_e.argp
    while ld.nbframes > bp_e.builders
        _bclose!(ld)
    end
    @goto next_instruction

    # ── unification and comparison in the body (pl-vmi.c, O_COMPILE_IS), V9a ─────────────────────
    # PORT: pl-vmi.c B_UNIFY_FIRSTVAR
    # DIVERGES: the slot gets a fresh variable (decision 2); see `unify_var_cont` for the term.
    @label B_UNIFY_FIRSTVAR
    bu_var = mk_var(T, fresh_var_keys!(1))
    ARGP = argp_t{T}(ARGP_SLOT, varFrameP(ld.frames[FR].base, Int(PCc[PC])), ph)
    PC += 1
    ld.slots[ARGP.pos + 1] = bu_var                 # setVar(*ARGP): needed for GC
    bu_first = true
    @goto unify_var_cont

    # PORT: pl-vmi.c B_UNIFY_VAR
    @label B_UNIFY_VAR
    ARGP = argp_t{T}(ARGP_SLOT, varFrameP(ld.frames[FR].base, Int(PCc[PC])), ph)
    PC += 1
    bu_first = false
    @goto unify_var_cont

    # PORT: pl-vmi.c unify_var_cont
    # DIVERGES: a helper label; `bu_first` says which instruction came. No `globaliseVar`: a keyed
    # variable lives in no cell (decision 2).
    # * The slow path (`occurs_check` true or error) writes the two arguments of `=/2` above `lTop`,
    #   the second a fresh variable. After `B_UNIFY_VAR` the head code then runs in READ mode over
    #   that fresh variable, where upstream sets write mode: it builds the term as a head argument is
    #   built under `true`/`error` (a fresh compound, bound and read; decision 3), so the VM never
    #   writes a head in write mode under those flags (user, 2026-10-06: 2a).
    # * The fast path after `B_UNIFY_FIRSTVAR` builds the term into one HOLDER cell of the builder
    #   (`bu_hold`), and `B_UNIFY_EXIT` binds the slot's fresh variable to it. Upstream points the
    #   slot at the compound at once; the kernel builds a term when it closes (decision 2). A use of
    #   the variable inside the term reads the fresh variable, so `X = f(X)` is cyclic, as upstream's
    #   (user, 2026-10-06: 3a); the binding is trailed where upstream writes the slot.
    @label unify_var_cont
    SLOW_UNIFY = _slow_unify(ld)
    if SLOW_UNIFY
        uvc_k = ld.slots[ARGP.pos + 1]              # Word k = ARGP
        ARGP = argp_t{T}(ARGP_SLOT, argFrameP(ld.lTop, 0), ph)
        _argp_store!(ld, ARGP, uvc_k)               # *ARGP++ = *k
        ARGP = _argp_add(ARGP, 1)
        _argp_store!(ld, ARGP, mk_var(T, fresh_var_keys!(1)))   # setVar(*ARGP)
        UMODE = bu_first ? uwrite : uread           # must write for GC to work (see above)
        bu_hold = 0
        @goto next_instruction
    end
    if bu_first
        bu_hold = ld.bTop + 1
        if bu_hold > length(ld.bcells)
            resize!(ld.bcells, max(bu_hold, 2 * length(ld.bcells)))
        end
        ld.bcells[bu_hold] = bu_var
        ld.bTop = bu_hold
        ARGP = argp_t{T}(ARGP_BUILD, bu_hold, ph)
    else
        bu_hold = 0
    end
    UMODE = uread                                   # needed?
    @goto next_instruction

    # PORT: pl-vmi.c B_UNIFY_EXIT
    # DIVERGES: after `B_UNIFY_FIRSTVAR` the fast path binds the slot's fresh variable to the term
    # in the holder (see `unify_var_cont`); the new frame of the slow path is the record pushed at
    # `lTop`, as `I_CALL`'s.
    # NOT PORTED: `CHECK_WAKEUP` (no attributed variables).
    @label B_UNIFY_EXIT
    ARGP = argp_t{T}(ARGP_SLOT, argFrameP(ld.lTop, 0), ph)
    if SLOW_UNIFY
        NFR = pushFrame!(ld, ld.lTop)               # NFR = lTop
        DEF = gd.procedures_equals2.definition
        setNextFrameFlags(ld.frames[NFR], ld.frames[FR])
        @goto normal_call
    end
    if bu_hold != 0
        bue_t = ld.bcells[bu_hold]
        ld.bTop = bu_hold - 1
        bu_hold = 0
        Trail!(ld, var_key(bu_var), bue_t)
    end
    @goto next_instruction

    # PORT: pl-vmi.c B_UNIFY_FF
    # DIVERGES: one fresh variable in both slots (decision 2: no global stack, `makeRefG`).
    @label B_UNIFY_FF
    buff_1 = varFrameP(ld.frames[FR].base, Int(PCc[PC]))
    buff_2 = varFrameP(ld.frames[FR].base, Int(PCc[PC + 1]))
    PC += 2
    buff_v = mk_var(T, fresh_var_keys!(1))
    ld.slots[buff_1 + 1] = buff_v                   # *v1 = makeRefG(v)
    if _slow_unify(ld)
        buff_w = mk_var(T, fresh_var_keys!(1))
        ld.slots[buff_2 + 1] = buff_w               # *v2 = makeRefG(v)
        ARGP = argp_t{T}(ARGP_SLOT, argFrameP(ld.lTop, 0), ph)
        _argp_store!(ld, ARGP, buff_v)
        ARGP = _argp_add(ARGP, 1)
        _argp_store!(ld, ARGP, buff_w)
        ARGP = _argp_add(ARGP, 1)
        @goto debug_equals2
    end
    ld.slots[buff_2 + 1] = buff_v                   # *v2 = *v1
    @goto next_instruction

    # PORT: pl-vmi.c B_UNIFY_VF
    @label B_UNIFY_VF
    @goto B_UNIFY_FV                                # the compiler swapped the operands

    # PORT: pl-vmi.c B_UNIFY_FV
    # DIVERGES: no `globaliseVar` (decision 2); the first-variable slot gets the value as `bvar_cont`
    # stores one (`linkValI`).
    @label B_UNIFY_FV
    bufv_f = varFrameP(ld.frames[FR].base, Int(PCc[PC]))
    bufv_v = varFrameP(ld.frames[FR].base, Int(PCc[PC + 1]))
    PC += 2
    if _slow_unify(ld)
        ld.slots[bufv_f + 1] = mk_var(T, fresh_var_keys!(1))   # globaliseFirstVar(f)
        ARGP = argp_t{T}(ARGP_SLOT, argFrameP(ld.lTop, 0), ph)
        _argp_store!(ld, ARGP, ld.slots[bufv_f + 1])
        ARGP = _argp_add(ARGP, 1)
        _argp_store!(ld, ARGP, ld.slots[bufv_v + 1])
        ARGP = _argp_add(ARGP, 1)
        @goto debug_equals2
    end
    ld.slots[bufv_f + 1] = linkValI(ld, ld.slots[bufv_v + 1])   # *f = linkValI(v)
    @goto next_instruction

    # PORT: pl-vmi.c B_UNIFY_VV
    # DIVERGES: no `globaliseVar` (decision 2).
    # NOT PORTED: `CHECK_WAKEUP` (no attributed variables).
    @label B_UNIFY_VV
    buvv_1 = varFrameP(ld.frames[FR].base, Int(PCc[PC]))
    buvv_2 = varFrameP(ld.frames[FR].base, Int(PCc[PC + 1]))
    PC += 2
    if _slow_unify(ld)
        ARGP = argp_t{T}(ARGP_SLOT, argFrameP(ld.lTop, 0), ph)
        _argp_store!(ld, ARGP, ld.slots[buvv_1 + 1])
        ARGP = _argp_add(ARGP, 1)
        _argp_store!(ld, ARGP, ld.slots[buvv_2 + 1])
        ARGP = _argp_add(ARGP, 1)
        @goto debug_equals2
    end
    @SAVE_REGISTERS(QID)
    buvv_rc = unify_ptrs(ld, ld.slots[buvv_1 + 1], ld.slots[buvv_2 + 1])
    @LOAD_REGISTERS(QID)
    buvv_rc && @goto next_instruction
    ld.exception_term != 0 && @goto b_throw         # THROW_EXCEPTION
    @goto shallow_backtrack                         # BODY_FAILED

    # PORT: pl-vmi.c debug_equals2
    # DIVERGES: a helper label; the new frame is the record pushed at `lTop`, as `I_CALL`'s.
    @label debug_equals2
    NFR = pushFrame!(ld, ld.lTop)                   # NFR = lTop
    DEF = gd.procedures_equals2.definition
    setNextFrameFlags(ld.frames[NFR], ld.frames[FR])
    @goto normal_call

    # PORT: pl-vmi.c B_UNIFY_FC
    # DIVERGES: the constant operand is a literal (src/pl-vmi.jl).
    @label B_UNIFY_FC
    bufc_f = varFrameP(ld.frames[FR].base, Int(PCc[PC]))
    bufc_c = PCl[PCc[PC + 1]]
    PC += 2
    if _slow_unify(ld)
        ld.slots[bufc_f + 1] = mk_var(T, fresh_var_keys!(1))   # globaliseFirstVar(f)
        ARGP = argp_t{T}(ARGP_SLOT, argFrameP(ld.lTop, 0), ph)
        _argp_store!(ld, ARGP, ld.slots[bufc_f + 1])
        ARGP = _argp_add(ARGP, 1)
        _argp_store!(ld, ARGP, bufc_c)
        ARGP = _argp_add(ARGP, 1)
        @goto debug_equals2
    end
    ld.slots[bufc_f + 1] = bufc_c                   # *f = c
    @goto next_instruction

    # PORT: pl-vmi.c B_UNIFY_VC
    # DIVERGES: the constant operand is a literal; `unify_simple_ptrs` decides, with the three outcomes
    # of `*k == c`, `canBind(*k)` and the rest, as `h_const`'s (SWI's identity).
    # NOT PORTED: `CHECK_WAKEUP` (no attributed variables).
    @label B_UNIFY_VC
    buvc_k = varFrameP(ld.frames[FR].base, Int(PCc[PC]))
    buvc_c = PCl[PCc[PC + 1]]
    PC += 2
    if _slow_unify(ld)
        ARGP = argp_t{T}(ARGP_SLOT, argFrameP(ld.lTop, 0), ph)
        _argp_store!(ld, ARGP, ld.slots[buvc_k + 1])
        ARGP = _argp_add(ARGP, 1)
        _argp_store!(ld, ARGP, buvc_c)
        ARGP = _argp_add(ARGP, 1)
        @goto debug_equals2
    end
    if unify_simple_ptrs(ld, deRef(ld, ld.slots[buvc_k + 1]), buvc_c) == BOOLEX_TRUE
        @goto next_instruction
    end
    @goto unify_backtrack                           # CLAUSE_FAILED

    # PORT: pl-vmi.c B_EQ_VV
    # DIVERGES: the kernel's standard order raises nothing, so there is no `CMP_ERROR`.
    # `FASTCOND_FAILED` is `BODY_FAILED` (see `TYPE_TEST`).
    # NOT PORTED: the `vmi_builtin=false` branch (`debug_eq_vv`; only the debugger clears the flag).
    @label B_EQ_VV
    beq_1 = varFrameP(ld.frames[FR].base, Int(PCc[PC]))
    beq_2 = varFrameP(ld.frames[FR].base, Int(PCc[PC + 1]))
    PC += 2
    if compareStandard(ld, ld.slots[beq_1 + 1], ld.slots[beq_2 + 1], true) == CMP_EQUAL
        @goto next_instruction
    end
    @goto shallow_backtrack                         # FASTCOND_FAILED

    # PORT: pl-vmi.c B_EQ_VC
    # DIVERGES: the constant operand is a literal; `*v1 == c` is SWI's identity of atomic terms
    # (`compare_primitives` in equality mode, as `PL_unify_atomic`). `FASTCOND_FAILED` is
    # `BODY_FAILED`.
    # NOT PORTED: the `vmi_builtin=false` branch.
    @label B_EQ_VC
    beqc_v = deRef(ld, ld.slots[varFrameP(ld.frames[FR].base, Int(PCc[PC])) + 1])
    beqc_c = PCl[PCc[PC + 1]]
    PC += 2
    if compare_primitives(beqc_v, beqc_c, CMP_MODE_EQUAL) == CMP_EQUAL
        @goto next_instruction
    end
    @goto shallow_backtrack                         # FASTCOND_FAILED

    # PORT: pl-vmi.c B_NEQ_VV
    # DIVERGES: as `B_EQ_VV`'s.
    @label B_NEQ_VV
    bneq_1 = varFrameP(ld.frames[FR].base, Int(PCc[PC]))
    bneq_2 = varFrameP(ld.frames[FR].base, Int(PCc[PC + 1]))
    PC += 2
    if compareStandard(ld, ld.slots[bneq_1 + 1], ld.slots[bneq_2 + 1], true) == CMP_EQUAL
        @goto shallow_backtrack                     # FASTCOND_FAILED
    end
    @goto next_instruction

    # PORT: pl-vmi.c B_NEQ_VC
    # DIVERGES: as `B_EQ_VC`'s.
    @label B_NEQ_VC
    bneqc_v = deRef(ld, ld.slots[varFrameP(ld.frames[FR].base, Int(PCc[PC])) + 1])
    bneqc_c = PCl[PCc[PC + 1]]
    PC += 2
    if compare_primitives(bneqc_v, bneqc_c, CMP_MODE_EQUAL) != CMP_EQUAL
        @goto next_instruction
    end
    @goto shallow_backtrack                         # FASTCOND_FAILED

    # ── calls (pl-vmi.c) ──────────────────────────────────────────────────────────────────────────
    # PORT: pl-vmi.c I_ENTER
    # DIVERGES: NOT PORTED: the `LD->alerted` block (coverage, the debugger's unify port, waking
    # attributed variables).
    @label I_ENTER
    ARGP = argp_t{T}(ARGP_SLOT, argFrameP(ld.lTop, 0), ph)
    @goto next_instruction

    # PORT: pl-vmi.c I_CALL
    # DIVERGES: the operand indexes the running clause's procedure table, read through `CL`
    # (`_call_procedure`; since V1, user 2026-10-05). The new frame is the record pushed at `lTop`,
    # upstream's cast `NFR = lTop`.
    @label I_CALL
    ic_proc = _call_procedure(ld, FR, PCc[PC])
    PC += 1
    NFR = pushFrame!(ld, ld.lTop)                   # NFR = lTop
    setNextFrameFlags(ld.frames[NFR], ld.frames[FR])
    DEF = ic_proc.definition
    @goto normal_call

    # PORT: pl-vmi.c normal_call
    # DIVERGES: the new frame stays ABOVE `lTop` (vmi:1869) until its supervisor raises `lTop`; one
    # whose call fails first is dropped where `deep_backtrack` leaves it (`_drop_unfilled_frame!`).
    # The overflow raises a Julia `LocalStackOverflow` until V5d ports the stack limit's
    # `resource_error` (`raiseStackOverflow`, its context as decided since Q-B).
    @label normal_call
    nc_f = ld.frames[NFR]
    nc_f.parent = FR
    setFramePredicate(nc_f, DEF)                    # TBD
    nc_f.programPointer = Code{T}(PCc, PCl, PC)     # save PC in child
    nc_f.clause = nothing                           # for save atom-gc
    FR = NFR
    ld.environment_frame = FR                       # open the frame

    if !hasLocalSpace(ld, LOCAL_MARGIN)
        setLTop!(ld, argFrameP(nc_f.base, DEF.arity))
        @SAVE_REGISTERS(QID)
        nc_rc = growLocalSpace(ld, LOCAL_MARGIN, ALLOW_SHIFT)
        @LOAD_REGISTERS(QID)
        if nc_rc != BOOLEX_TRUE
            raiseStackOverflow(ld, nc_rc)
            @goto b_throw                           # THROW_EXCEPTION
        end
    end
    @goto depart_or_retry_continue

    # PORT: pl-vmi.c depart_or_retry_continue
    # DIVERGES: NOT PORTED: the profiler's node, the inference count, and the `LD->alerted` block
    # (signals, undo hooks, depth and inference limits, the debugger).
    @label depart_or_retry_continue
    setGenerationFrame(gd, ld, FR)
    PCc = DEF.codes
    PCl = gd.no_literals
    PC = 1
    @goto next_instruction

    # PORT: pl-vmi.c I_DEPART
    # DIVERGES: the operand as `I_CALL`'s; `BFR <= FR` compares positions (decision 3). Last-call reuse
    # ASSERTS that FR is the newest live record (user, 2026-10-05), which upstream's reuse relies on.
    # NOT PORTED: `FR_WATCHED` (`frameFinished`, V9; asserted absent), `P_TRANSPARENT` (one module),
    # `HIDE_CHILDS` (only the debugger reads it; port_inventory § "Not ported: nothing here can set or
    # observe it").
    @label I_DEPART
    id_proc = _call_procedure(ld, FR, PCc[PC])
    PC += 1
    id_def = id_proc.definition
    if (ld.BFR == 0 || ld.choices[ld.BFR].base <= ld.frames[FR].base) &&
        ld.prolog_flag_last_call &&
        (id_def.impl_clauses.first_clause !== nothing || (id_def.flags & PROC_DEFINED) != 0)
        id_f = ld.frames[FR]
        @assert (id_f.flags & FR_WATCHED) == 0
        @assert _is_newest_live_frame(ld, FR) "I_DEPART: last-call reuse of a frame that is not the newest live record"
        id_f.clause = nothing                       # for save atom-gc
        # leaveDefinition(DEF): (void)0 upstream
        DEF = id_def
        lcoSetNextFrameFlags(id_f)
        setFramePredicate(id_f, DEF)
        copyFrameArguments(ld, ld.lTop, id_f.base, DEF.arity)
        @goto depart_or_retry_continue
    end

    NFR = pushFrame!(ld, ld.lTop)                   # NFR = lTop
    lcoSetNextFrameFlags2(ld.frames[NFR], ld.frames[FR])
    DEF = id_def
    @goto normal_call

    # ── the exits (pl-vmi.c) ──────────────────────────────────────────────────────────────────────
    # PORT: pl-vmi.c I_EXIT
    # DIVERGES: NOT PORTED: the `LD->alerted` block (the debugger's exit port).
    @label I_EXIT
    @goto exit_continue

    # PORT: pl-vmi.c exit_continue
    # DIVERGES: lowering `lTop` to the frame drops its record and everything above it (decision 3),
    # and the record is still read after, as here (since V3). `FR_WATCHED` (`frameFinished`) and
    # `FR_DET`/`FR_DETGUARD` (`determinism_error`) are NOT PORTED: nothing sets them yet; asserted.
    @label exit_continue
    ec_f = ld.frames[FR]
    if ld.BFR == 0 || ld.choices[ld.BFR].base <= ec_f.base   # deterministic
        @assert (ec_f.flags & FR_WATCHED) == 0
        ec_f.clause = nothing                       # leaveDefinition() destroys clause
        # leaveDefinition(DEF): (void)0 upstream
        lowerLTop!(ld, ec_f.base)                   # lTop = FR
    else
        ec_f.flags &= ~FR_INBOX
        @assert (ec_f.flags & (FR_DET | FR_DETGUARD)) == 0
    end

    PCc = ec_f.programPointer.codes
    PCl = ec_f.programPointer.literals
    PC = ec_f.programPointer.pc
    FR = ec_f.parent
    ld.environment_frame = FR
    DEF = ld.frames[FR].predicate::Definition{T}
    ARGP = argp_t{T}(ARGP_SLOT, argFrameP(ld.lTop, 0), ph)
    @goto next_instruction

    # PORT: pl-vmi.c I_EXITFACT
    # DIVERGES: NOT PORTED: the `LD->alerted` block (the debugger's unify port, coverage).
    @label I_EXITFACT
    @goto exit_checking_wakeup

    # PORT: pl-vmi.c exit_checking_wakeup
    # DIVERGES: NOT PORTED: waking attributed variables' goals and the heartbeat (neither exists).
    @label exit_checking_wakeup
    @goto I_EXIT

    # PORT: pl-vmi.c I_EXITQUERY
    # DIVERGES: `QueryFromQid` is recomputed as upstream does ("may be shifted"), though positions never
    # move. NOT PORTED: `FR_WATCHED` (asserted absent) and the profiler.
    @label I_EXITQUERY
    @assert ld.frames[FR].parent == 0
    QF = QueryFromQid(ld, QID)                      # may be shifted: recompute
    eq_q = ld.queries[QF]
    eq_q.solutions += 1

    @assert FR == eq_q.top_frame

    if ld.BFR == eq_q.choice                        # No alternatives
        eq_q.flags |= PL_Q_DETERMINISTIC
        setLTop!(ld, argFrameP(ld.frames[FR].base, DEF.arity))
        ld.frames[FR].clause = nothing
        @assert (ld.frames[FR].flags & FR_WATCHED) == 0
    end

    eq_q.foreign_frame = PL_open_foreign_frame(ld)

    return (eq_q.flags & DET_EXIT) == DET_EXIT ? PL_S_LAST : PL_S_TRUE    # SOLUTION_RETURN

    # ── the last-call block (pl-vmi.c) ────────────────────────────────────────────────────────────
    # PORT: pl-vmi.c L_NOLCO
    # DIVERGES: the jump counts the kernel's code words from after the operand, as `lco!` fills it
    # (c:3807). Falling through to reuse the frame asserts it is the newest live record, as `I_DEPART`
    # does (user, 2026-10-05).
    @label L_NOLCO
    ln_jmp = Int(PCc[PC])
    PC += 1
    if (ld.BFR == 0 || ld.choices[ld.BFR].base <= ld.frames[FR].base) &&
        ld.prolog_flag_last_call
        @assert _is_newest_live_frame(ld, FR) "L_NOLCO: last-call reuse of a frame that is not the newest live record"
        @goto next_instruction
    end
    PC += ln_jmp
    @goto next_instruction

    # PORT: pl-vmi.c L_VAR
    # DIVERGES: the value, dereferenced: a keyed variable is its own reference, so the chain is
    # followed to its end and an unbound variable is copied as itself (decision 2).
    @label L_VAR
    ld.slots[varFrameP(ld.frames[FR].base, Int(PCc[PC])) + 1] = deRef(
        ld, ld.slots[varFrameP(ld.frames[FR].base, Int(PCc[PC + 1])) + 1]
    )
    PC += 2
    @goto next_instruction

    # PORT: pl-vmi.c L_VOID
    @label L_VOID
    ld.slots[varFrameP(ld.frames[FR].base, Int(PCc[PC])) + 1] = mk_var(
        T, fresh_var_keys!(1)
    )               # setVar(*varFrameP(FR, *PC++))
    PC += 1
    @goto next_instruction

    # PORT: pl-vmi.c L_ATOM
    # DIVERGES: the operand indexes the literal table (since V1 L2); no atom GC, so no `pushVolatileAtom`.
    @label L_ATOM
    ld.slots[varFrameP(ld.frames[FR].base, Int(PCc[PC])) + 1] = PCl[PCc[PC + 1]]
    PC += 2
    @goto next_instruction

    # PORT: pl-vmi.c L_NIL
    @label L_NIL
    ld.slots[varFrameP(ld.frames[FR].base, Int(PCc[PC])) + 1] = gd.atom_nil
    PC += 1
    @goto next_instruction

    # PORT: pl-vmi.c L_SMALLINT
    # DIVERGES: the operand indexes the literal table (since V1 L2).
    @label L_SMALLINT
    ld.slots[varFrameP(ld.frames[FR].base, Int(PCc[PC])) + 1] = PCl[PCc[PC + 1]]
    PC += 2
    @goto next_instruction

    # PORT: pl-vmi.c I_LCALL
    # DIVERGES: the operand as `I_CALL`'s. QUIRK kept: `setFramePredicate` twice (vmi:2499, 2527).
    # NOT PORTED: the context module (one module), `FR_WATCHED` (asserted absent),
    # `getProcDefinedDefinition` until V5c (`autoImport`, no autoload, as decided since Q-A —
    # `S_VIRGIN` takes an undefined procedure as it is), `P_TRANSPARENT`, `HIDE_CHILDS`.
    @label I_LCALL
    il_proc = _call_procedure(ld, FR, PCc[PC])
    PC += 1
    il_f = ld.frames[FR]
    # leaveDefinition(DEF): (void)0 upstream
    il_f.clause = nothing
    DEF = il_proc.definition
    setFramePredicate(il_f, DEF)
    setLTop!(ld, argFrameP(il_f.base, DEF.arity))
    @assert (il_f.flags & FR_WATCHED) == 0
    lcoSetNextFrameFlags(il_f)
    setFramePredicate(il_f, DEF)
    @goto depart_or_retry_continue

    # PORT: pl-vmi.c I_TCALL
    # DIVERGES: NOT PORTED: `FR_WATCHED` (asserted absent), `HIDE_CHILDS` (see `I_DEPART`).
    @label I_TCALL
    @assert (ld.frames[FR].flags & FR_WATCHED) == 0
    tcallSetNextFrameFlags(ld.frames[FR])
    ld.frames[FR].clause = nothing
    @goto depart_or_retry_continue

    # PORT: pl-vmi.c I_CUT
    # DIVERGES: the age test compares positions (`base`), as `discardChoicesAfter`'s. NOT PORTED: the
    # debugger branch (`tracePort(…, CUT_CALL_PORT)`: no debugger). The `exception_term` test after
    # the discard is kept, though nothing can set it yet: only `frameFinished` on an `FR_WATCHED`
    # frame (V9), which `discardChoicesAfter` asserts absent.
    @label I_CUT
    ld.frames[FR].flags &= ~FR_SSU_DET              # clear(FR, FR_SSU_DET)
    if ld.BFR == 0 || ld.choices[ld.BFR].base <= ld.frames[FR].base   # (LocalFrame)BFR <= FR
        @goto next_instruction
    end
    @SAVE_REGISTERS(QID)
    discardChoicesAfter(ld, FR, FINISH_CUT)
    @LOAD_REGISTERS(QID)
    # lTop = (LocalFrame) argFrameP(FR, CL->value.clause->variables): the records of the discarded
    # choice points and frames lie above it, and go with the lowering (decision 3)
    cu_clause = (ld.frames[FR].clause::ClauseRef{T}).clause::Clause{T}
    setLTop!(ld, argFrameP(ld.frames[FR].base, Int(cu_clause.variables)))
    ARGP = argp_t{T}(ARGP_SLOT, argFrameP(ld.lTop, 0), ph)    # ARGP = argFrameP(lTop, 0)
    ld.exception_term != 0 && @goto b_throw         # THROW_EXCEPTION
    @goto next_instruction

    # ── C_VAR, fail/0 and true/0 (pl-vmi.c), V9a ──────────────────────────────────────────────────
    # PORT: pl-vmi.c C_VAR
    # DIVERGES: a fresh variable into the slot (decision 2).
    @label C_VAR
    ld.slots[varFrameP(ld.frames[FR].base, Int(PCc[PC])) + 1] = mk_var(
        T, fresh_var_keys!(1)
    )
    PC += 1
    @goto next_instruction

    # PORT: pl-vmi.c I_FAIL
    # NOT PORTED: the `vmi_builtin=false` branch, which calls `fail/0` (only the debugger clears the
    # flag).
    @label I_FAIL
    @goto shallow_backtrack                         # BODY_FAILED

    # PORT: pl-vmi.c I_TRUE
    # NOT PORTED: the `vmi_builtin=false` branch, which calls `true/0`.
    @label I_TRUE
    @goto next_instruction

    # ── the type tests (pl-vmi.c), V6b ────────────────────────────────────────────────────────────
    # PORT: pl-vmi.c I_VAR
    # DIVERGES: NOT PORTED: the `vmi_builtin=false` branch (`debug_pred1`; see `TYPE_TEST`).
    # `FASTCOND_FAILED` is `BODY_FAILED` (see `TYPE_TEST`).
    @label I_VAR
    tt_p = deRef(ld, ld.slots[varFrameP(ld.frames[FR].base, Int(PCc[PC])) + 1])
    PC += 1
    canBind(tt_p) && @goto next_instruction
    @goto shallow_backtrack                         # FASTCOND_FAILED

    # PORT: pl-vmi.c I_NONVAR
    # DIVERGES: as `I_VAR`'s.
    @label I_NONVAR
    tt_p = deRef(ld, ld.slots[varFrameP(ld.frames[FR].base, Int(PCc[PC])) + 1])
    PC += 1
    !canBind(tt_p) && @goto next_instruction
    @goto shallow_backtrack                         # FASTCOND_FAILED

    # PORT: pl-vmi.c I_INTEGER
    @label I_INTEGER
    @TYPE_TEST(isInteger)

    # PORT: pl-vmi.c I_RATIONAL
    @label I_RATIONAL
    @TYPE_TEST(isRational)

    # PORT: pl-vmi.c I_FLOAT
    @label I_FLOAT
    @TYPE_TEST(isFloat)

    # PORT: pl-vmi.c I_NUMBER
    @label I_NUMBER
    @TYPE_TEST(isNumber)

    # PORT: pl-vmi.c I_ATOMIC
    @label I_ATOMIC
    @TYPE_TEST(isAtomic)

    # PORT: pl-vmi.c I_ATOM
    @label I_ATOM
    @TYPE_TEST(isTextAtom)

    # PORT: pl-vmi.c I_STRING
    @label I_STRING
    @TYPE_TEST(isString)

    # PORT: pl-vmi.c I_COMPOUND
    @label I_COMPOUND
    @TYPE_TEST(isTerm)

    # PORT: pl-vmi.c I_CALLABLE
    @label I_CALLABLE
    @TYPE_TEST(isCallable)

    # ── arithmetic compiled inline (pl-vmi.c), V8 ─────────────────────────────────────────────────
    # PORT: pl-vmi.c A_ADD_FC
    # DIVERGES: the integer operand is a literal (src/pl-vmi.jl). The fast path's test is an `Int64`
    # in the TAGGED range, as upstream's `isTaggedInt`, so `v + add` cannot overflow; the sum is
    # one `Int64` value (`put_int64`'s overflow branch cannot be taken). Writing the result's slot
    # is not a binding (decision 2), as upstream's `*rp = w`. NOT PORTED: the `vmi_builtin=false`
    # branch, which calls `is/2` (only the debugger and coverage clear the flag).
    @label A_ADD_FC
    af_rp = varFrameP(ld.frames[FR].base, Int(PCc[PC]))                 # A =
    af_np = deRef(ld, ld.slots[varFrameP(ld.frames[FR].base, Int(PCc[PC + 1])) + 1])  # B +
    af_add = int64_value(PCl[PCc[PC + 2]])                              # <int>
    PC += 3
    if number_kind(af_np) === NUM_INTEGER && integer_is_int64(af_np) &&
        PLMINTAGGEDINT <= int64_value(af_np) <= PLMAXTAGGEDINT          # isTaggedInt(*np)
        ld.slots[af_rp + 1] = mk_gnd(T, int64_value(af_np) + af_add)    # *rp = consInt(r)
        @goto next_instruction
    end
    @SAVE_REGISTERS(QID)
    af_rc = false
    af_w = ph
    af_fid = PL_open_foreign_frame(ld)                  # Still needed?
    if af_fid != 0
        af_t = new_term_ref(ld)                         # pushWordAsTermRef(np)
        ld.slots[af_t + 1] = af_np
        af_n = _number_alloc!(ld)
        af_rc = evalExpression(ld, af_t, af_n)
        if af_rc                                        # ensureWritableNumber: numbers are values
            af_rc = ar_add_si(ld, af_n, af_add)
            af_rc && (af_w = put_number(T, af_n))
        end
        _number_free!(ld, 1)                            # clearNumber(&n)
        PL_close_foreign_frame(ld, af_fid)
    end
    @LOAD_REGISTERS(QID)
    af_rc || @goto b_throw                              # THROW_EXCEPTION
    ld.slots[varFrameP(ld.frames[FR].base, Int(PCc[PC - 3])) + 1] = af_w  # rp: may have shifted
    @goto next_instruction

    # ── supervisors (pl-vmi.c) ────────────────────────────────────────────────────────────────────
    # PORT: pl-vmi.c S_VIRGIN
    # NOT PORTED: `getProcDefinedDefinition`, until V5c (`autoImport`, no autoload, as decided
    # since Q-A), so `DEF` is kept; the profiler; thread-local predicates (no threads).
    @label S_VIRGIN
    setLTop!(
        ld, argFrameP(ld.frames[FR].base, (ld.frames[FR].predicate::Definition{T}).arity)
    )

    if DEF.impl_clauses.first_clause === nothing && (DEF.flags & PROC_DEFINED) == 0
        setFramePredicate(ld.frames[FR], DEF)
        setGenerationFrame(gd, ld, FR)
        if DEF.impl_clauses.first_clause !== nothing
            @goto depart_or_retry_continue
        end
    end

    if setDefaultSupervisor(gd, DEF)
        PCc = DEF.codes
        PCl = gd.no_literals
        PC = 1
        @goto next_instruction
    else                                            # TBD: temporary
        @assert false
        @goto deep_backtrack                        # FRAME_FAILED
    end

    # PORT: pl-vmi.c S_UNDEF
    # DIVERGES: the error context names the caller `Name/Arity`, never module-qualified, until V5c
    # (src/pl-error.jl). The `CHP_DEBUG` choice point is pushed as upstream pushes it; only the
    # debugger's retry reads it upstream (not ported), and `b_throw` discards it.
    @label S_UNDEF
    # getUnknownModule(DEF->module): a definition has no module here until V5c, and every user
    # predicate lives in `user`; the flag is the default there, UNKNOWN_ERROR (src/pl-modul.jl), so
    # the warning and fail branches are not reachable and not ported.
    @assert getUnknownModule(MODULE_user(gd)) == UNKNOWN_ERROR
    su_caller =
        ld.frames[FR].parent != 0 ? ld.frames[ld.frames[FR].parent].predicate : nothing
    setLTop!(ld, argFrameP(ld.frames[FR].base, DEF.arity))
    newChoice(ld, CHP_DEBUG, FR)
    @SAVE_REGISTERS(QID)
    su_fid = PL_open_foreign_frame(ld)
    if su_fid != 0
        PL_error(ld, ERR_UNDEFINED_PROC, DEF, su_caller)
        PL_close_foreign_frame(ld, su_fid)
    end
    @LOAD_REGISTERS(QID)
    # enterDefinition(DEF): (void)0 upstream (pl-incl.h:1302) — "will be left in exception code"
    @goto b_throw                                   # THROW_EXCEPTION

    # PORT: pl-vmi.c S_STATIC
    # QUIRK, as upstream (vmi:3358): `(LocalFrame)ARGP+DEF->functor->arity` casts first, so it adds
    # `arity` whole frames — `8·arity` positions, not `arity` (probed live: after a failing query of
    # f/1 the next term reference lies at qf+61, of h/2 at qf+69). `chp` is the local data's scratch
    # `clause_choice` where upstream's is on the C stack. NOT PORTED: the debugger's and the det
    # declarations' `CHP_DEBUG` choice point.
    @label S_STATIC
    ARGP = argp_t{T}(ARGP_SLOT, argFrameP(ld.frames[FR].base, 0), ph)
    setLTop!(ld, ARGP.pos + DEF.arity * SIZEOF_LOCALFRAME)

    ss_chp = ld.chp_scratch
    ss_chp.cref = nothing
    ss_chp.key = word(0)
    ss_cl = firstClause!(
        ld, argv_frame(ld, ARGP.pos), generationFrame(ld.frames[FR]), DEF, ss_chp
    )
    if ss_cl === nothing
        @goto deep_backtrack                        # FRAME_FAILED
    end

    ss_clause = ss_cl.clause::Clause{T}
    PCc = ss_clause.codes
    PCl = ss_clause.literals
    PC = 1
    @ENSURE_LOCAL_SPACE(LOCAL_MARGIN + Int(ss_clause.variables))
    setLTop!(ld, ARGP.pos + Int(ss_clause.variables))
    ld.frames[FR].clause = ss_cl                    # CL = cl

    if ss_chp.cref !== nothing
        ss_ch = newChoice(ld, CHP_CLAUSE, FR)
        ss_v = ld.choices[ss_ch].value_clause       # ch->value.clause = chp
        ss_v.cref = ss_chp.cref
        ss_v.key = ss_chp.key
    end

    UMODE = uread
    @goto next_instruction

    # PORT: pl-vmi.c S_DYNAMIC
    @label S_DYNAMIC
    # enterDefinition(DEF): (void)0 upstream (pl-incl.h:1302)
    @goto S_STATIC                                  # SEPARATE_VMI1; VMI_GOTO(S_STATIC)

    # PORT: pl-vmi.c S_MULTIFILE
    @label S_MULTIFILE
    @goto S_STATIC                                  # SEPARATE_VMI2; VMI_GOTO(S_STATIC)

    # PORT: pl-vmi.c S_TRUSTME
    # DIVERGES: the operand indexes the supervisor's clause-reference table (`codes_crefs`).
    @label S_TRUSTME
    tc_cref = DEF.codes_crefs[Int(PCc[PC])]         # code2ptr(ClauseRef, *PC++)
    PC += 1
    ARGP = argp_t{T}(ARGP_SLOT, argFrameP(ld.frames[FR].base, 0), ph)
    @goto TRUST_CLAUSE

    # PORT: pl-vmi.c TRUST_CLAUSE
    # DIVERGES: a helper label where upstream's is a macro; its argument is `tc_cref`. NOT PORTED: the
    # debugger's `CHP_DEBUG` choice point.
    @label TRUST_CLAUSE
    UMODE = uread
    ld.frames[FR].clause = tc_cref                  # CL = cref
    tc_clause = tc_cref.clause::Clause{T}
    setLTop!(ld, ARGP.pos + Int(tc_clause.variables))
    @ENSURE_LOCAL_SPACE(LOCAL_MARGIN)
    PCc = tc_clause.codes
    PCl = tc_clause.literals
    PC = 1
    @goto next_instruction

    # PORT: pl-vmi.c S_LIST
    # DIVERGES: the operands index `codes_crefs`; a `$expr/3` argument goes to `S_STATIC` as an unbound
    # one does — it can unify with a list-cell clause child by child (Q2; user, 2026-10-05).
    @label S_LIST
    ARGP = argp_t{T}(ARGP_SLOT, argFrameP(ld.frames[FR].base, 0), ph)
    sl_k = deRef(ld, ld.slots[ARGP.pos + Int(PCc[PC]) + 1])     # deRef2(ARGP+PC[0], k)
    if is_pair(sl_k)
        tc_cref = DEF.codes_crefs[Int(PCc[PC + 2])]
    elseif is_nil(sl_k)
        tc_cref = DEF.codes_crefs[Int(PCc[PC + 1])]
    elseif kind(sl_k) === VAR || _is_expr3(sl_k)                # canBind(*k)
        PCc = DEF.code_data.staticp                 # PC = SUPERVISOR(staticp) + 1
        PC = 2
        @goto S_STATIC
    else
        @goto deep_backtrack                        # FRAME_FAILED
    end
    PC += 3
    @goto TRUST_CLAUSE

    # ── deterministic foreign calls (pl-vmi.c; V5a2, decision 5) ─────────────────────────────────
    # PORT: pl-vmi.c I_FCALLDETVA
    # DIVERGES: the operand is the built-in's index in the dispatch table (src/pl-ext.jl), called by
    # `_fcall_va` where upstream calls through the pointer; `FNDET_CONTEXT` is the query record's
    # (see `foreign_context`). `VMH_GOTO(I_FEXITDET, rc)` is the helper's argument and a jump.
    @label I_FCALLDETVA
    fv_i = Int(PCc[PC])
    PC += 1
    fv_h0 = argFrameP(ld.frames[FR].base, 0)        # consTermRef(argFrameP(FR, 0))
    vmi_fopen(ld, FR, DEF)                          # inline I_FOPEN
    fv_ctx = ld.queries[QueryFromQid(ld, QID)].fndet_context
    fv_ctx.control = FRG_FIRST_CALL
    fv_ctx.context = UInt(0)
    fv_ctx.predicate = DEF
    @SAVE_REGISTERS(QID)
    fexitdet_rc = _fcall_va(fv_i, ld, fv_h0, DEF.arity, fv_ctx)
    @goto helper_I_FEXITDET

    # PORT: pl-vmi.c I_FCALLDET0
    # DIVERGES: as `I_FCALLDET1`; upstream's `(*f)()` takes no argument, and does not step past the
    # `I_FEXITDET` word (the exit reloads PC from the frame, so the step is not observable).
    @label I_FCALLDET0
    fd_i = Int(PCc[PC])
    PC += 1
    vmi_fopen(ld, FR, DEF)                          # inline I_FOPEN
    @SAVE_REGISTERS(QID)
    fexitdet_rc = _fcall_det(fd_i, ld, argFrameP(ld.frames[FR].base, 0))
    @goto helper_I_FEXITDET

    # PORT: pl-vmi.c FCALL_DETN as I_FCALLDET1
    # DIVERGES: one label per instruction, all calling `_fcall_det`, whose leaf for each FRG built-in
    # passes its arity's term references `h0, h0+1, …` (FCALL_DETN's `__VA_ARGS__`).
    @label I_FCALLDET1
    @goto fcall_detn
    @label I_FCALLDET2
    @goto fcall_detn
    @label I_FCALLDET3
    @goto fcall_detn
    @label I_FCALLDET4
    @goto fcall_detn
    @label I_FCALLDET5
    @goto fcall_detn
    @label I_FCALLDET6
    @goto fcall_detn
    @label I_FCALLDET7
    @goto fcall_detn
    @label I_FCALLDET8
    @goto fcall_detn
    @label I_FCALLDET9
    @goto fcall_detn
    @label I_FCALLDET10
    @label fcall_detn
    fd_i = Int(PCc[PC])
    PC += 1
    fd_h0 = argFrameP(ld.frames[FR].base, 0)        # consTermRef(argFrameP(FR, 0))
    vmi_fopen(ld, FR, DEF)                          # inline I_FOPEN
    PC += 1
    @SAVE_REGISTERS(QID)
    fexitdet_rc = _fcall_det(fd_i, ld, fd_h0)
    @goto helper_I_FEXITDET

    # PORT: pl-vmi.c I_FEXITDET
    @label I_FEXITDET
    @assert false "I_FEXITDET is never executed: the calls jump to its helper"
    @goto b_throw                                   # THROW_EXCEPTION

    # PORT: pl-vmi.c I_FEXITDET as helper_I_FEXITDET
    # DIVERGES: the label is upstream's switch-build helper name (`helper_ ## Name`, wam:3492) — a
    # Julia label cannot share the instruction's; its argument is `fexitdet_rc`.
    @label helper_I_FEXITDET
    @LOAD_REGISTERS(QID)
    while ld.fli_context != 0 && ld.fliframes[ld.fli_context].base > ld.frames[FR].base
        ld.fli_context = ld.fliframes[ld.fli_context].parent
    end
    if fexitdet_rc == FTRUE
        if ld.exception_term != 0                   # false alarm
            PL_clear_foreign_exception(ld, FR)
        end
        @goto exit_checking_wakeup
    elseif fexitdet_rc == FFALSE
        ld.exception_term != 0 && @goto b_throw     # THROW_EXCEPTION
        @goto deep_backtrack                        # FRAME_FAILED
    end
    error_foreign_return_code(ld, fexitdet_rc)
    @goto b_throw                                   # THROW_EXCEPTION

    # ── backtracking (pl-vmi.c) ───────────────────────────────────────────────────────────────────
    # PORT: pl-vmi.c unify_backtrack
    # DIVERGES: the builder is reset with the argument stack (Q3).
    @label unify_backtrack
    QF = QueryFromQid(ld, QID)                      # ARGP is pushed an unknown amount
    _reset_argument_stack!(ld, ld.queries[QF])
    @goto shallow_backtrack

    # PORT: pl-vmi.c shallow_backtrack
    # DIVERGES: the choice point MOVES by changing its base; before that, the records above it — the
    # failed attempt's — are dropped (user, 2026-10-05), because `lTop` can rise over them here. A
    # popped choice point is dropped at its old position. When it cannot move for lack of room, its
    # `clause_choice` is copied out first: `newChoice` resets the record it reuses, which is this one.
    # `CHP_JUMP` arrives with `C_OR` (V9); the debugger's `CHP_DEBUG` is NOT PORTED.
    @label shallow_backtrack
    sb_ch = ld.BFR
    sb_c = ld.choices[sb_ch]
    if FR == sb_c.frame
        Undo!(ld, sb_c.mark)

        if sb_c.type == CHP_JUMP
            throw(
                NotPortedError{T}(
                    DEF.name, "backtracking into a disjunction (CHP_JUMP)", "V9"
                )
            )
        elseif sb_c.type == CHP_CLAUSE
            ARGP = argp_t{T}(ARGP_SLOT, argFrameP(ld.frames[FR].base, 0), ph)
            sb_cl = nextClause!(
                ld, sb_c.value_clause, argv_frame(ld, ARGP.pos),
                generationFrame(ld.frames[FR]),
                DEF
            )
            if sb_cl === nothing
                @goto deep_backtrack                # can happen if scan-ahead was too short
            end
            ld.frames[FR].clause = sb_cl            # CL = …
            sb_clause = sb_cl.clause::Clause{T}
            sb_ntop = argFrameP(ld.frames[FR].base, Int(sb_clause.variables))
            PCc = sb_clause.codes
            PCl = sb_clause.literals
            PC = 1
            UMODE = uread

            if f_hasSpace(sb_ntop, ld.lMax, LOCAL_MARGIN, 1)
                # MQ18 (user, 2026-10-05): when the failing frame owns the youngest choice point, no
                # record lives above that choice point — every path that removes a younger one also
                # lowers `lTop` — so the drop below finds nothing. Asserted, so every run checks it.
                @assert _no_record_above(ld, sb_c.base) "shallow_backtrack: a record above the resumed choice point"
                dropRecords!(ld, sb_c.base + 1)     # the failed attempt's records (none: above)
                if sb_c.value_clause.cref !== nothing
                    sb_c.base = sb_ntop             # Choice point needs to move
                    ld.lTop = sb_ntop + SIZEOF_CHOICE       # lTop = (LocalFrame)(ch+1)
                    @goto next_instruction
                end

                DiscardMark(ld, sb_c.mark)
                ld.BFR = sb_c.parent
                dropRecords!(ld, sb_c.base)         # the popped choice point
                ld.lTop = sb_ntop                   # lTop = (LocalFrame)ch
                @goto next_instruction
            else                                    # We need GC/shift to move the choice point
                sb_chp = ld.chp_scratch
                DiscardMark(ld, sb_c.mark)
                ld.BFR = sb_c.parent
                sb_chp.cref = sb_c.value_clause.cref    # chp = ch->value.clause
                sb_chp.key = sb_c.value_clause.key
                dropRecords!(ld, sb_c.base)
                ld.lTop = sb_ntop
                @ENSURE_LOCAL_SPACE(LOCAL_MARGIN)

                if sb_chp.cref !== nothing
                    sb_new = newChoice(ld, CHP_CLAUSE, FR)
                    sb_v = ld.choices[sb_new].value_clause      # ch->value.clause = chp
                    sb_v.cref = sb_chp.cref
                    sb_v.key = sb_chp.key
                end
                @goto next_instruction
            end
        end
    end
    @goto deep_backtrack

    # PORT: pl-vmi.c deep_backtrack
    # DIVERGES: frames and choice points are compared by `base`; the popped `CHP_CLAUSE` choice point
    # and the records above it are dropped before `lTop` is set (user, 2026-10-05); `chp` is the local
    # data's scratch `clause_choice`. `CHP_TOP` leaves `lTop` where it is, as upstream:
    # `restore_after_query` drops the dead records. NOT PORTED: the debugger (`trace_action`,
    # `CHP_DEBUG`), `frameFailed` for `FR_WATCHED`/det frames (asserted absent), the `LD->alerted`
    # block; `CHP_JUMP` arrives with `C_OR`, `CHP_CATCH` with catch/3 (V9).
    @label deep_backtrack                           # next_choice:
    while FR != 0 && ld.frames[FR].base > ld.choices[ld.BFR].base     # NULL is below every choice
        leaveFrame(ld, FR)                          # LEAVE_FAILED_FRAME(FR)
        @assert (ld.frames[FR].flags & (FR_WATCHED | FR_SSU_DET | FR_DET | FR_DETGUARD)) ==
            0
        if ld.frames[FR].base >= ld.lTop            # its own call failed before it was filled
            _drop_unfilled_frame!(ld, FR)
        end
        FR = ld.frames[FR].parent
    end

    db_c = ld.choices[ld.BFR]
    FR = db_c.frame
    ld.environment_frame = FR
    Undo!(ld, db_c.mark)
    QF = QueryFromQid(ld, QID)
    _reset_argument_stack!(ld, ld.queries[QF])
    DEF = ld.frames[FR].predicate::Definition{T}

    if db_c.type == CHP_CLAUSE                      # try next clause
        db_chp = ld.chp_scratch                     # struct clause_choice chp = BFR->value.clause
        db_chp.cref = db_c.value_clause.cref
        db_chp.key = db_c.value_clause.key

        ARGP = argp_t{T}(ARGP_SLOT, argFrameP(ld.frames[FR].base, 0), ph)
        DiscardMark(ld, db_c.mark)
        ld.BFR = db_c.parent
        dropRecords!(ld, db_c.base)                 # the popped choice point and all above it
        db_cl = nextClause!(
            ld, db_chp, argv_frame(ld, ARGP.pos), generationFrame(ld.frames[FR]), DEF
        )
        if db_cl === nothing
            @goto deep_backtrack                    # Can happen of look-ahead was too short
        end

        ld.frames[FR].clause = db_cl                # CL = …
        db_clause = db_cl.clause::Clause{T}
        PCc = db_clause.codes
        PCl = db_clause.literals
        PC = 1
        ld.lTop = argFrameP(ld.frames[FR].base, Int(db_clause.variables))
        UMODE = uread

        if db_chp.cref !== nothing
            db_new = newChoice(ld, CHP_CLAUSE, FR)
            db_v = ld.choices[db_new].value_clause  # ch->value.clause = chp
            db_v.cref = db_chp.cref
            db_v.key = db_chp.key
        end
        # require space for the args of the next frame
        @ENSURE_LOCAL_SPACE(LOCAL_MARGIN)
        @goto next_instruction
    elseif db_c.type == CHP_TOP                     # Query toplevel
        DiscardMark(ld, db_c.mark)
        QF = QueryFromQid(ld, QID)
        db_q = ld.queries[QF]
        db_q.flags |= PL_Q_DETERMINISTIC
        db_q.foreign_frame = PL_open_foreign_frame(ld)
        return 0                                    # SOLUTION_RETURN(false)
    end
    throw(
        NotPortedError{T}(DEF.name, "backtracking into a $(db_c.type) choice point", "V9")
    )

    # ── exceptions (pl-vmi.c) ─────────────────────────────────────────────────────────────────────
    # PORT: pl-vmi.c b_throw
    # DIVERGES: the no-catcher path (user, 2026-10-05): `findCatcher` finds no catcher, as there is no
    # catch/3 before V9 — so it is not called, and the catcher reference is 0. NOT PORTED: the
    # exception hook that rewrites an exception, `LD->outofstack`, the emergency-space check (the
    # foreign frame is opened with room made first), `fast_condition`.
    @label b_throw
    QF = QueryFromQid(ld, QID)
    _reset_argument_stack!(ld, ld.queries[QF])
    @assert ld.exception_term != 0

    bt_low = argFrameP(ld.frames[FR].base, (ld.frames[FR].predicate::Definition{T}).arity)
    if ld.lTop < bt_low
        ld.lTop = bt_low
    end

    ensureLocalSpace(ld, SIZEOF_FLIFRAME)
    bt_fid = open_foreign_frame(ld)
    # catchfr_ref = findCatcher(fid, FR, LD->choicepoints, exception_term): no catch/3 (V9)
    PL_close_foreign_frame(ld, bt_fid)
    @goto b_throw_debug

    # PORT: pl-vmi.c b_throw_debug
    # DIVERGES: NOT PORTED: the debugger, and printing an uncaught exception (`print_unhandled_exception`;
    # swipl prints it under `PL_Q_NORMAL`, the kernel never prints).
    @label b_throw_debug
    @goto b_throw_unwind

    # PORT: pl-vmi.c b_throw_unwind
    # DIVERGES: with no catcher, every frame up to the query's top is left; `frameFinished` on an
    # `FR_WATCHED` frame is not ported (asserted absent).
    @label b_throw_unwind
    while FR != 0
        ld.environment_frame = FR
        ARGP = argp_t{T}(ARGP_SLOT, argFrameP(ld.frames[FR].base, 0), ph)

        @SAVE_REGISTERS(QID)
        dbg_discardChoicesAfter(ld, FR, FINISH_EXTERNAL_EXCEPT_UNDO)
        @LOAD_REGISTERS(QID)

        setLTop!(
            ld,
            argFrameP(ld.frames[FR].base, (ld.frames[FR].predicate::Definition{T}).arity)
        )
        while ld.fli_context != 0 && ld.fliframes[ld.fli_context].base > ld.frames[FR].base
            ld.fli_context = ld.fliframes[ld.fli_context].parent
        end
        discardFrame(ld, FR)
        @assert (ld.frames[FR].flags & FR_WATCHED) == 0

        PCc = ld.frames[FR].programPointer.codes
        PCl = ld.frames[FR].programPointer.literals
        PC = ld.frames[FR].programPointer.pc
        FR = ld.frames[FR].parent
    end
    @goto b_throw_resume

    # PORT: pl-vmi.c b_throw_resume
    # DIVERGES: its no-catcher branch only (V9 adds the catcher); no GC request to honour.
    @label b_throw_resume
    QF = QueryFromQid(ld, QID)                      # may be shifted
    br_q = ld.queries[QF]
    br_q.flags |= PL_Q_DETERMINISTIC
    FR = br_q.top_frame
    ld.environment_frame = FR
    setLTop!(
        ld, argFrameP(ld.frames[FR].base, (ld.frames[FR].predicate::Definition{T}).arity)
    )

    Undo!(ld, ld.choices[br_q.choice].mark)
    DiscardMark(ld, ld.choices[br_q.choice].mark)
    br_q.foreign_frame = PL_open_foreign_frame(ld)
    br_q.exception = PL_copy_term_ref(ld, ld.exception_term)

    @SAVE_REGISTERS(QID)
    resumeAfterException(ld, (br_q.flags & PL_Q_PASS_EXCEPTION) == 0)
    @LOAD_REGISTERS(QID)

    return (br_q.flags & PL_Q_EXT_STATUS) != 0 ? PL_S_EXCEPTION : 0
end
