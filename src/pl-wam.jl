# UPSTREAM: swipl-devel src/pl-wam.c @ 8609e216cab9
# UPSTREAM: swipl-devel src/pl-vmi.c @ 8609e216cab9
# UPSTREAM: swipl-devel src/pl-incl.h @ 8609e216cab9
# UPSTREAM: swipl-devel src/pl-gc.c @ 8609e216cab9
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
    c.value_pc = 0
    c.unlinked = false
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
        _slot_copy!(ld, ARGD + 1, ARGS + 1)          # *ARGD++ = *ARGS++ (words, L1b C6a)
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

# PORT: pl-wam.c findCatcher
# DIVERGES: frames and choice points are records found by index, compared by POSITION (`fr <= ch`:
# the frame lies below the newest choice point — it is not catch/3's call port); the result is the
# catching frame's index (0: none) where upstream returns a term reference to it, which GC can move.
# NOT PORTED: `foreignWakeup` (no attributed variables: nothing to wake, so no `ex2`).
"""
    findCatcher(gd, ld, fid, fr, ch, ex0) -> frame index, or 0

The frame running catch/3, from `fr` upward, that has not caught yet (`FR_CAUGHT`: a ball from its
recover goal passes on) and whose catcher unifies with the ball `ex0` references; it is marked
`FR_CAUGHT`. The search runs with NO exception pending (`saveWakeup`), so an error the catcher's
unification raises is raised — and is the ball from there on; the bindings of the unification are
undone when the search ends (`restoreWakeup`; `b_throw_resume` unifies again) (pl-wam.c).
"""
function findCatcher(
    gd::PL_global_data{T}, ld::PL_local_data{T}, fid::Int, fr::Int, ch::Int, ex0::Int
)::Int where {T}
    catch3 = gd.procedures_catch3.definition
    ex = PL_copy_term_ref(ld, ex0)
    wstate = saveWakeup(ld, false)
    if wstate === nothing
        ld.outofstack = true
        outOfStack!(ld, STACK_OVERFLOW_THROW)           # throws: see outOfStack!
        return 0                                        # assert(0)
    end
    chpos = ch == 0 ? typemax(Int) : ld.choices[ch].base
    while fr != 0
        f = ld.frames[fr]
        if f.predicate === catch3 &&
            (f.flags & FR_CAUGHT) == 0 &&               # not thrown from recover
            f.base <= chpos                              # not call-port of catch/3
            catcher = argFrameP(f.base, 1)               # consTermRef(argFrameP(fr, 1))
            if PL_unify(ld, catcher, ex)
                restoreWakeup(ld, wstate)
                PL_put_term(ld, ld.exception_term, ex)
                f.flags |= FR_CAUGHT
                return fr
            elseif ld.exception_term != 0               # Exception from PL_unify()
                PL_put_term(ld, ex, ld.exception_term)
            end
            PL_rewind_foreign_frame(ld, wstate.fid != 0 ? wstate.fid : fid)
        end
        fr = f.parent
    end
    restoreWakeup(ld, wstate)
    PL_put_term(ld, ld.exception_term, ex)
    return 0
end

# PORT: pl-wam.c findCatchExit
# DIVERGES: the code position (an index into catch/3's clause) where upstream caches the address in
# `GD->exceptions.catch_exit_address`.
"The position of catch/3's `I_EXIT`, the recover goal's return address: its clause's last code (pl-wam.c)."
function findCatchExit(gd::PL_global_data{T})::Code{T} where {T}
    cl =
        (gd.procedures_catch3.definition.impl_clauses.first_clause::ClauseRef{T}).clause::Clause{
            T
        }
    n = length(cl.codes)
    @assert cl.codes[n] == I_EXIT
    return Code{T}(cl.codes, cl.literals, n)
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

# PORT: pl-wam.c determinism_error
# DIVERGES: `bfr` is a choice point's index (0: none) and the age test compares positions; the flag
# is the local data's `prolog_flag_determinism_error`; `found` and the declaration are symbols.
"""
    determinism_error(ld, fr, bfr, found) -> Bool

Frame `fr`, which must be deterministic — a `\$/0` guard, in it or in a caller, or the `det`
property — `found` otherwise: `:nondet` (it exits with choice point `bfr` left) or `:fail`
(pl-wam.c). Under the flag `determinism_error`: `error` raises
`determinism_error(PI, det, Found, Decl)` and returns false; `warning` reports it and returns true;
`silent` returns true. A `:nondet` whose `bfr` is older than the frame is no error: true.
"""
function determinism_error(
    ld::PL_local_data{T}, fr::Int, bfr::Int, found::Symbol
)::Bool where {T}
    rc = false
    if found === :nondet
        while bfr != 0 && ld.choices[bfr].type == CHP_DEBUG
            bfr = ld.choices[bfr].parent
        end
        if bfr == 0 || ld.choices[bfr].base < ld.frames[fr].base   # (void*)bfr < (void*)fr
            return true
        end
    end

    a = ld.prolog_flag_determinism_error
    a === :silent && return true

    fid = PL_open_foreign_frame(ld)
    if fid != 0
        f = ld.frames[fr]
        def = f.predicate::Definition{T}
        if (f.flags & FR_DETGUARD) != 0
            if (f.flags & FR_DETGUARD_SET) != 0
                decl = :guard
            else
                decl = :guard_in_caller
                fr2 = f.parent
                while fr2 != 0
                    if (ld.frames[fr2].flags & FR_DETGUARD_SET) != 0
                        def = ld.frames[fr2].predicate::Definition{T}
                        break
                    end
                    fr2 = ld.frames[fr2].parent
                end
            end
        else
            decl = :property
            if (def.flags & P_DET) == 0
                fr2 = f.parent
                while fr2 != 0
                    def2 = ld.frames[fr2].predicate::Definition{T}
                    if (def2.flags & P_DET) != 0
                        def = def2
                        break
                    end
                    fr2 = ld.frames[fr2].parent
                end
            end
        end

        if a === :warning
            gd = _query_gd(ld)
            pi = unify_definition(gd, MODULE_user(gd), def, GP_NAMEARITY | GP_HIDESYSTEM)
            rc = printMessage(
                ld,
                :warning,
                mk_expr(
                    T,
                    T[
                        mk_sym(T, :error),
                        mk_expr(
                            T,
                            T[
                                mk_sym(T, :determinism_error), pi, mk_sym(T, :det),
                                mk_sym(T, found), mk_sym(T, decl)
                            ]
                        ),
                        _cell_var(ld, allocGlobalCells!(ld, 1))
                    ]
                )
            )
        else
            rc = PL_error(
                ld, ERR_DETERMINISM, def, mk_sym(T, :det), mk_sym(T, found), mk_sym(T, decl)
            )
        end

        PL_close_foreign_frame(ld, fid)
    end

    return rc
end

# PORT: pl-wam.c ssu_or_det_failed
# DIVERGES: NOT PORTED: the `FR_SSU_DET` branch (`existence_error(matching_rule, Goal)`: SSU is not
# ported, nothing sets the flag — asserted).
"Frame `fr`, which must not fail, failed: the determinism error (pl-wam.c)."
function ssu_or_det_failed(ld::PL_local_data{T}, fr::Int)::Bool where {T}
    @assert (ld.frames[fr].flags & FR_SSU_DET) == 0
    return determinism_error(ld, fr, 0, :fail)
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

# PORT: pl-wam.c unify_finished
# DIVERGES: the reason's atom is written out per reason (upstream's `reason_decls[]`).
"""
Unify the term reference `catcher` with how a frame finished (pl-wam.c): `exception(Ball)` or
`external_exception(Ball)`, `fail`, `!` (a cut), or `exit` for the cleanup instruction's own exit. A plain
`FINISH_EXIT` fails: that exit is not reported.
"""
function unify_finished(
    ld::PL_local_data{T}, catcher::term_t, reason::finished
)::Bool where {T}
    if is_exception_finish(reason)
        f = reason == FINISH_EXCEPT ? :exception : :external_exception
        return pl_unify!(
            ld,
            slotValue(ld, catcher + 1),
            mk_expr(T, T[mk_sym(T, f), slotValue(ld, ld.exception_bin + 1)])
        )
    elseif reason == FINISH_EXIT
        return false
    else
        # reason_decls[]: ATOM_fail, ATOM_cut — whose text is `!` (src/ATOMS) — ATOM_exit
        name = if reason == FINISH_FAIL
            :fail
        elseif reason == FINISH_CUT
            :!
        else
            :exit
        end
        return pl_unify!(ld, slotValue(ld, catcher + 1), mk_sym(T, name))
    end
end

# PORT: pl-wam.c call1
# DIVERGES: the module is `user` (see `call_term`); `call/1` is looked up in `system` at each call,
# where upstream caches the procedure (`GD->procedures.call1`).
"Call the goal in term reference `goal` once through `call/1`, in a query of its own (pl-wam.c)."
function call1(gd::PL_global_data{T}, ld::PL_local_data{T}, goal::term_t)::Bool where {T}
    pred = lookupProcedure(mk_sym(T, :call), 1, MODULE_system(gd))

    qid = PL_open_query(gd, ld, MODULE_user(gd), PL_Q_PASS_EXCEPTION, pred, goal)
    rc = PL_next_solution(gd, ld, qid) != 0
    PL_cut_query(ld, qid)

    return rc
end

# PORT: pl-wam.c call_term
# DIVERGES: the database `gd` is an argument. No `mdef`: the context module of an unqualified goal
# is `user` until R2 (`stripModule`; `contextModule(fr)` reads frames' context modules, not
# ported). The goal's arguments go to the new term references as values.
"""
Call the goal in term reference `goal` once, from the VM (pl-wam.c): a plain goal directly, in a
query of its own; a control construct, a goal that is no text atom or `call/N` beyond 8 through
`call/1`. True when it succeeded; false when it failed or raised (`PL_Q_PASS_EXCEPTION`: the
exception stays pending).
"""
function call_term(
    gd::PL_global_data{T}, ld::PL_local_data{T}, goal::term_t
)::Bool where {T}
    ok, p, mi = stripModule(gd, ld, deRef(ld, slotValue(ld, goal + 1)))
    if ok
        p = deRef(ld, p)
        m = gd.modules[mi]
        av = 0
        if isAtom(p)
            if isTextAtom(p)
                name = p
                arity = 0
            else
                return call1(gd, ld, goal)
            end
        elseif isTerm(p)
            h = child(p, 1)
            arity = nchildren(p) - 1
            if isTextAtom(h) && !_is_control(p, gd.functors_control) &&
                !(sym_key(h) == gd.subclause_names.atom_call && arity > 8)
                av = PL_new_term_refs(ld, arity)
                for i in 1:arity
                    setSlotValue!(ld, av + i, child(p, i + 1))          # *ap = linkValG(&args[i])
                end
                name = h
            else
                return call1(gd, ld, goal)
            end
        else
            return PL_type_error(ld, "callable", goal)
        end

        proc = resolveProcedure(gd, name, arity, m)
        qid = PL_open_query(gd, ld, m, PL_Q_PASS_EXCEPTION, proc, av)
        rval = PL_next_solution(gd, ld, qid) != 0
        PL_cut_query(ld, qid)

        return rval
    else
        return false                                    # exception in env
    end
end

# ORIGINAL: the Julia-facing query helper (L1c; user, 2026-10-15). PROVISIONAL (user, 2026-10-15):
# the public Julia API — a lazy iterator, bindings by variable name, the exception's form — is
# designed with R2; until then this is the one entry point a host has, and its shape may change. It
# carries no `pl_` prefix: `pl_`/`PL_` names are ports of upstream functions, and this has no
# counterpart (embedding code discards its frames itself).
# Since L1c a put copies its term onto the global stack and closing a foreign frame keeps global
# data, as upstream's `PL_close_foreign_frame` does — with no collector until G1, a host that ran
# many queries through open/close would grow the stack without bound. So this helper copies every
# answer OUT (resolved: an interface term, no cell of the engine's in it) and then DISCARDS its
# foreign frame (upstream's `PL_discard_foreign_frame`, as embedding code does with libswipl):
# `gTop`, the trail and the local stack are back where they were. A host using the FLI itself must
# open and discard frames the same way (README: "Memory at the boundary").
"""
    PrologException(ball)

An uncaught Prolog exception, thrown to the Julia caller of [`query_answers`](@ref): `ball` is the
exception term, resolved (a term of its own). PROVISIONAL with `query_answers` (R2 designs the form).
"""
struct PrologException{T} <: Exception
    ball::T
end

"""
    query_answers(db, goal; limit=nothing) -> Vector

Run `goal` (an atom or a compound) in `user` on the engine `db` and return its answers — each `goal`
with its bindings resolved, a term of its own — at most `limit` of them (`nothing`: all). An
uncaught Prolog exception is thrown as a [`PrologException`](@ref) carrying its ball. The engine's
stacks are left as they were found. PROVISIONAL (user, 2026-10-15): the public API comes with R2.

`db` is an ENGINE (`PL_local_data`), made for its database (`PL_local_data{T}(gd)`), which it
carries as `GD` — an engine is the one object a host holds.
"""
function query_answers(
    db::PL_local_data{T}, goal::T; limit::Union{Nothing, Int}=nothing
)::Vector{T} where {T}
    k = kind(goal)
    (k === SYM || (k === EXPR && nchildren(goal) >= 1 && kind(child(goal, 1)) === SYM)) ||
        throw(ArgumentError("query_answers: the goal must be an atom or a compound"))
    gd = db.GD::PL_global_data{T}                   # the engine's database (set when it was made)
    name = k === SYM ? goal : child(goal, 1)
    arity = k === SYM ? 0 : nchildren(goal) - 1
    fid = PL_open_foreign_frame(db)
    a = PL_new_term_refs(db, max(arity, 1))
    vm = PutVarMap()                                # the goal's variables shared across its arguments
    for i in 1:arity
        putSlotValue!(db, a + i, child(goal, i + 1), vm)
    end
    proc = resolveProcedure(gd, name, arity, MODULE_user(gd))
    qid = PL_open_query(gd, db, nothing, PL_Q_CATCH_EXCEPTION | PL_Q_EXT_STATUS, proc, a)
    answers = T[]
    while limit === nothing || length(answers) < limit
        rc = PL_next_solution(gd, db, qid)
        if rc == PL_S_TRUE || rc == PL_S_LAST
            kids = T[name]
            for i in 1:arity
                push!(kids, slotValue(db, a + i))
            end
            push!(answers, resolve_term(db, arity == 0 ? name : mk_expr(T, kids)))
            rc == PL_S_LAST && break
        elseif rc == PL_S_EXCEPTION
            ball = resolve_term(db, slotValue(db, PL_exception(db, qid) + 1))
            PL_close_query(db, qid)
            PL_discard_foreign_frame(db, fid)       # as below: nothing of the query stays
            throw(PrologException{T}(ball))     # {T}: a leaf may be a concrete subtype of T
        else
            break
        end
    end
    PL_close_query(db, qid)
    PL_discard_foreign_frame(db, fid)               # not closed: nothing of the query stays
    return answers
end

# PORT: pl-wam.c callCleanupHandler
# DIVERGES: the frame is an index (it cannot move); the arguments are positions. NOT PORTED:
# `startCritical`/`endCritical` around the handler (no signals).
"""
    callCleanupHandler(ld, fr, reason)

Frame `fr` runs one of the cleanup family — `call_cleanup/2`, `setup_call_cleanup/3`,
`setup_call_catcher_cleanup/4`, told apart by arity — and finished for `reason`: unless its handler
ran already (`FR_CAUGHT`), unify the catcher of the `/4` with the reason and call the cleanup goal
once (pl-wam.c). The goal runs with no exception pending; an exception it raises replaces a
pending one only when it is the more urgent.
"""
function callCleanupHandler(
    ld::PL_local_data{T}, fr::Int, reason::finished
)::Nothing where {T}
    f = ld.frames[fr]
    if (f.flags & FR_CAUGHT) == 0                   # from handler
        cid = PL_open_foreign_frame(ld)
        cid == 0 && return nothing                  # exception is in the environment

        arity = (f.predicate::Definition{T}).arity
        arg_catcher = 0
        if arity == 2                               # call_cleanup(Goal, Cleanup)
            arg_cleanup = 2
        elseif arity == 3                           # setup_call_cleanup(Setup, Goal, Cleanup)
            arg_cleanup = 3
        elseif arity == 4                           # setup_call_catcher_cleanup(Stp, Goal, Catcher, Cln)
            arg_cleanup = 4
            arg_catcher = 3
        else
            error("callCleanupHandler: a cleanup frame of arity $arity")    # assert(0)
        end

        f.flags |= FR_CAUGHT

        # Unify the catcher
        if arg_catcher == 0 ||
            unify_finished(ld, argFrameP(f.base, arg_catcher - 1), reason)
            # Call the cleanup handler
            clean = argFrameP(f.base, arg_cleanup - 1)
            wstate = saveWakeup(ld, false)
            if wstate !== nothing
                rval = call_term(_query_gd(ld), ld, clean)
                if !rval && ld.exception_term != 0
                    wstate = wakeup_state(
                        wstate.fid, wstate.outofstack,
                        wstate.flags | WAKEUP_KEEP_URGENT_EXCEPTION
                    )
                end
                restoreWakeup(ld, wstate)
            end
        end

        PL_close_foreign_frame(ld, cid)
    end
    return nothing
end

# PORT: pl-wam.c frameFinished
# DIVERGES: NOT PORTED: the event hook of an `FR_NOTIFY` frame (`callEventHook`: the debugger's).
"""
Frame `fr` is finished for `reason`: run the cleanup handler of a cleanup frame (pl-wam.c). False
when an exception is pending after it.
"""
function frameFinished(ld::PL_local_data{T}, fr::Int, reason::finished)::Bool where {T}
    if (ld.frames[fr].flags & FR_CLEANUP) != 0
        callCleanupHandler(ld, fr, reason)
        ld.exception_term != 0 && return false
    end

    return true
end

# PORT: pl-wam.c mustBeCallable
# DIVERGES: upstream accepts ONLY `Module:Goal` — the cleanup family's goals reach it qualified by
# their meta-predicate declarations (boot/init.pl:381-383). Those are not ported (no module
# transparency until R2), so an UNQUALIFIED term is checked as the goal itself: unbound is an
# instantiation error, anything but a compound or a text atom `type_error(callable, Term)`. The
# culprit of that error is then the plain term where upstream's is `Module:Term` (R2).
"Whether the term reference `call` holds a callable goal, raising the error when not (pl-wam.c)."
function mustBeCallable(ld::PL_local_data{T}, call::term_t)::Bool where {T}
    p = deRef(ld, slotValue(ld, call + 1))
    kind(p) === VAR && return PL_error(ld, ERR_INSTANTIATION)
    ap = p
    if _hasFunctor(p, mk_sym(T, :(:)), 2)
        mp = deRef(ld, child(p, 2))
        kind(mp) === VAR && return PL_error(ld, ERR_INSTANTIATION)
        isAtom(mp) || return PL_type_error(ld, "callable", call)
        ap = deRef(ld, child(p, 3))
        kind(ap) === VAR && return PL_error(ld, ERR_INSTANTIATION)
    end
    (isTerm(ap) || isTextAtom(ap)) || return PL_type_error(ld, "callable", call)

    return true
end

# PORT: pl-wam.c frameFailed
# DIVERGES: NOT PORTED: the event hook (`frameFinished`'s `FR_NOTIFY` branch).
"Frame `fr` failed: report a frame that must not, and run a cleanup frame's handler (pl-wam.c). False when that raised an exception."
function frameFailed(ld::PL_local_data{T}, fr::Int)::Bool where {T}
    ld.environment_frame = fr
    f = ld.frames[fr]
    setLTop!(ld, argFrameP(f.base, (f.predicate::Definition{T}).arity))

    if (f.flags & (FR_SSU_DET | FR_DET | FR_DETGUARD)) != 0
        ssu_or_det_failed(ld, fr)
        ld.exception_term != 0 && return false
    end

    return frameFinished(ld, fr, FINISH_FAIL)
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

# PORT: pl-wam.c in_continuation
# DIVERGES: frames and choice points are compared by position (`base`); a NULL frame or choice
# point is index 0, below every position.
"""
True if frame `fr` is in the continuation of `frame`, or of the frame of choice point `ch` or of
one of `ch`'s parents (pl-wam.c).
"""
function in_continuation(ld::PL_local_data{T}, fr::Int, frame::Int, ch::Int)::Bool where {T}
    frbase = ld.frames[fr].base
    while true
        while frame != 0 && ld.frames[frame].base > frbase
            frame = ld.frames[frame].parent
        end
        frame == fr && return true

        if ch != 0 && ld.choices[ch].base > frbase
            frame = ld.choices[ch].frame
            ch = ld.choices[ch].parent
        else
            return false
        end
    end
end

# PORT: pl-wam.c discardChoicesAfter
# DIVERGES: the age tests compare `base` positions; the stack never moves, so there is no
# re-basing after `frameFinished` (since V9g: the cleanup handler of a discarded cleanup frame).
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
                if (f2.flags & FR_WATCHED) != 0
                    if !me_undone && is_exception_finish(reason)
                        me_undone = true
                        Undo!(ld, mec.mark)
                        DiscardMark(ld, mec.mark)
                    end
                    ld.BFR = me
                    frameFinished(ld, fr2, reason)
                    ld.BFR = ld.choices[ld.BFR].parent
                end

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
        w = deRef(ld, slotValue(ld, ld.exception_term + 1))
        @assert kind(w) !== VAR
        ld.exception_term = 0
        discardChoicesAfter(ld, fr, reason)
        _slot_store_value!(ld, ld.exception_bin + 1, w)          # a value (decision 1)
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

# THE POOLS' INVARIANT (user, 2026-10-05; restated 2026-10-12 for `*->`): the pools hold the LIVE
# records — the choice points on the `BFR` chain, the frames on the parent chains of the running
# frame and of those choice points' frames — PLUS the choice-point records `C_SOFTCUT` unlinked
# (`unlinked`) whose stack region is still in use; those are reclaimed when that region is popped:
# by every lowering of `lTop` to or below them (`dropRecords!`), and, where upstream reuses the
# region WITHOUT lowering `lTop` past it — a last call reusing its frame, a clause choice point
# resumed in place — by `dropUnlinkedChoices!` first. So `_no_record_above` stays exact at those
# points. test/core_lang/test_rules_swipl.jl `_rpools_live` checks exactly this at every answer.
"""
    dropUnlinkedChoices!(ld, p)

Reclaim the choice-point records above position `p` that `C_SOFTCUT` took out of the chain: the
region above `p` is about to be reused. A record above `p` must BE one `C_SOFTCUT` unlinked — "no
LIVE record above `p`" is a precondition at every call site (the LCO guard at `I_DEPART`/`L_NOLCO`,
`_no_record_above` after this call at `shallow_backtrack`), so `unlinked` is a CHECKED assertion
here, not a loop guard: a future call site (V9e's `islocal` temporary clauses, the exception
unwind, tabling) that broke the precondition would be caught here rather than silently reclaiming a
live record (mutation 2026-10-12, SC11′).
"""
function dropUnlinkedChoices!(ld::PL_local_data{T}, p::Int)::Nothing where {T}
    n = ld.nchoices
    while n > 0 && ld.choices[n].base > p
        @assert ld.choices[n].unlinked "dropUnlinkedChoices!: a LIVE choice record above p=$p at n=$n (the pool invariant: no live record above a region about to be reused)"
        n -= 1
    end
    ld.nchoices = n
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

# ── the argument pointer and the argument stack ────────────────────────────────────────────────
# What `ARGP` points at, as is (upstream's `*ARGP`): a slot's value; a cell of the global stack as
# its variable term, which `deRef` follows (L1c); a term's child.
function _argp_raw(ld::PL_local_data{T}, a::argp_t{T})::T where {T}
    if a.form == ARGP_SLOT
        return slotValue(ld, a.pos + 1)
    elseif a.form == ARGP_GLOBAL
        return _cell_var(ld, a.pos)
    end
    return child(a.term, a.pos)
end

# What `ARGP` points at, dereferenced (upstream's `deRef2(ARGP, k)`).
_argp_deref(ld::PL_local_data{T}, a::argp_t{T}) where {T} = deRef(ld, _argp_raw(ld, a))::T

# Write `t` where `ARGP` points (upstream's `*ARGP = t`): a slot (body mode), or a cell of the global
# stack (write mode, L1c) as `t`'s word.
function _argp_store!(ld::PL_local_data{T}, a::argp_t{T}, t::T)::Nothing where {T}
    if a.form == ARGP_SLOT
        setSlotValue!(ld, a.pos + 1, t)
    elseif a.form == ARGP_GLOBAL
        ld.gstack[a.pos] = _word_of!(ld, t)
    else
        error("_argp_store!: read mode never writes into the caller's term")
    end
    return nothing
end

# A fresh variable where `ARGP` points, referenced from slot `i` (upstream's `setVar(*ARGP);
# varFrame(FR, n) = makeRefG(ARGP)`): on the global stack the ARGUMENT CELL is the variable (L1c);
# a slot (a frame argument) gets a reference to a fresh cell, as the slot `i` does.
function _argp_fresh_var!(ld::PL_local_data{T}, a::argp_t{T}, i::Int)::Nothing where {T}
    if a.form == ARGP_GLOBAL
        ld.gstack[a.pos] = word(0)                  # setVar(*ARGP)
        ld.slots[i] = makeRefG(a.pos)               # varFrame(FR, n) = makeRefG(ARGP)
    elseif a.form == ARGP_SLOT
        ld.slots[a.pos + 1] = makeRefG(_slot_new_var!(ld, i))
    else
        error("_argp_fresh_var!: read mode never writes into the caller's term")
    end
    return nothing
end

# An unbound variable where `ARGP` points (upstream's `setVar(*ARGP)`): the argument cell itself on
# the global stack (L1c); a reference to a fresh cell in a slot.
function _argp_void!(ld::PL_local_data{T}, a::argp_t{T})::Nothing where {T}
    if a.form == ARGP_GLOBAL
        ld.gstack[a.pos] = word(0)
    elseif a.form == ARGP_SLOT
        ld.slots[a.pos + 1] = makeRefG(allocGlobalCells!(ld, 1))
    else
        error("_argp_void!: read mode never writes into the caller's term")
    end
    return nothing
end

# `ARGP + n`.
_argp_add(a::argp_t{T}, n::Int) where {T} = argp_t{T}(a.form, a.pos + n, a.term)

# `deRef2(ARGP, p)` on the WORDS (L1c): where ARGP's value lives — `DREF_CELL`: an unbound cell, its
# position in the second word; `DREF_WORD`: an atom or a compound, its word; `DREF_TERM`: a value
# with no word form (a value-table word, a `SLOT_VALUE`, a cursor's child), decided on terms.
"`_argp_deref_word`: an unbound cell at the position returned."
const DREF_CELL = 0x01
"`_argp_deref_word`: an atom or a compound, the word returned."
const DREF_WORD = 0x02
"`_argp_deref_word`: a value with no word form: decide on terms (`_argp_deref`)."
const DREF_TERM = 0x03

# ORIGINAL: upstream's `deRef2(ARGP, p)` (pl-data.h) on the words of a slot or a cell (L1c).
"ARGP dereferenced on the words: `(DREF_CELL, position)`, `(DREF_WORD, word)` or `(DREF_TERM, 0)`."
@inline function _argp_deref_word(
    ld::PL_local_data{T}, a::argp_t{T}
)::Tuple{UInt8, word} where {T}
    if a.form == ARGP_SLOT
        w = ld.slots[a.pos + 1]
        if !isRef(w)
            (isAtomW(w) || _is_gcompound(w)) && return (DREF_WORD, w)
            return (DREF_TERM, word(0))
        end
        p = unRef(w)
    elseif a.form == ARGP_GLOBAL
        p = a.pos
    else
        return (DREF_TERM, word(0))
    end
    while true
        c = ld.gstack[p]
        isVar(c) && return (DREF_CELL, word(p))
        if isRef(c)
            p = unRef(c)
        elseif isAtomW(c) || _is_gcompound(c)
            return (DREF_WORD, c)
        else
            return (DREF_TERM, word(0))
        end
    end
end

# ORIGINAL: upstream's `varFrame(FR, n) = (needsRef(*p) ? makeRefG(p) : *p)` (pl-vmi.c H_LIST_FF) for
# slot `i` and global cell `p` (L1c): the cell's own word when it is an atom, a compound or a
# reference; else a reference to the cell (an unbound cell, or a value-table word: no slot holds one).
"Slot `i` takes global cell `p`'s word, or a reference to the cell (pl-vmi.c H_LIST_FF)."
@inline function _slot_from_cell!(ld::PL_local_data, i::Int, p::Int)::Nothing
    c = ld.gstack[p]
    ld.slots[i] = (isRef(c) || isAtomW(c) || _is_gcompound(c)) ? c : makeRefG(p)
    return nothing
end

# h_const's outcomes on the words (`_h_const_word!`): matched or bound, failed, or undecided.
"`_h_const_word!`: the slot's word is the constant, or a cell it reaches was bound to it."
const H_CONST_MATCH = Int8(1)
"`_h_const_word!`: the slot's word reaches another constant (`CLAUSE_FAILED`)."
const H_CONST_FAIL = Int8(0)
"`_h_const_word!`: the slot's word reaches a value with no word form yet: decide on terms."
const H_CONST_TERMS = Int8(-1)

# PORT: pl-vmi.c h_const as _h_const_word!
# (its test and binding, on the words)
# DIVERGES, transitional (L1b stage C6b): decided on the WORDS when argument slot `i` holds its word
# form — a reference to a cell, followed through the cells it is bound to (`deRef`), or an atom
# word: `*k == c` matches; an unbound cell is bound (`bindConst`, pl-attvar.h `varBindConst`:
# `*p = c`, trailed when `p < mark_bar` — `<=` here, `gTop` being the last cell in use, as
# `Trail!` trails a cell); any other atom word, and a compound (L1c), fails. A value-table word (a value with no word form
# yet, a keyed variable among them) and a `SLOT_VALUE` slot are UNDECIDED: the VM decides on terms,
# as before C6b, until L1d (unification over cells) gives them words.
"h_const on slot `i`'s words for the atom word `c`: `H_CONST_MATCH`, `H_CONST_FAIL` or `H_CONST_TERMS`."
@inline function _h_const_word!(ld::PL_local_data, i::Int, c::word)::Int8
    w = ld.slots[i]
    if isRef(w)
        p = unRef(w)
        while true
            k = ld.gstack[p]
            k == c && return H_CONST_MATCH                          # *k == c
            if isVar(k)                                             # canBind(*k)
                _bind_const!(ld, p, c)                              # bindConst(k, c)
                return H_CONST_MATCH
            elseif isRef(k)
                p = unRef(k)
            elseif isAtomW(k) || _is_gcompound(k)
                return H_CONST_FAIL
            else
                return H_CONST_TERMS                                # a value-table word
            end
        end
    end
    w == c && return H_CONST_MATCH
    (isAtomW(w) || _is_gcompound(w)) && return H_CONST_FAIL
    return H_CONST_TERMS                                            # SLOT_VALUE
end

# The argument stack's height back to what query `q` saved (`aTop = QF->aSave`).
function _reset_argument_stack!(ld::PL_local_data{T}, q::queryFrame{T})::Nothing where {T}
    ld.aTop = q.aSave
    return nothing
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

# PORT: pl-vmi.c FASTCOND_FAILED
# DIVERGES: `LD->fast_condition` is an index into the running clause's code (0 for NULL): a fast
# condition holds no call, so the code registers are that clause's.
"A test compiled inline failed (pl-vmi.c): in a fast condition jump to its else branch, else `BODY_FAILED`."
macro FASTCOND_FAILED()
    return esc(
        quote
            if ld.fast_condition == 0
                @goto shallow_backtrack             # BODY_FAILED
            else
                PC = ld.fast_condition
                ld.fast_condition = 0
                @goto next_instruction
            end
        end
    )
end

# PORT: pl-vmi.c TYPE_TEST
# DIVERGES: a macro over the run loop's locals, as upstream's, without its `functor` argument: that
# names the predicate of the `vmi_builtin=false` branch (`debug_pred1`), NOT PORTED — only the
# debugger and coverage clear the flag.
"The body of a type-test instruction (pl-vmi.c `TYPE_TEST`): `test` the variable at the operand."
macro TYPE_TEST(test)
    return esc(
        quote
            tt_p = deRef(ld, slotValue(ld, varFrameP(ld.frames[FR].base, Int(PCc[PC])) + 1))
            PC += 1
            $test(tt_p) && @goto next_instruction
            @FASTCOND_FAILED
        end
    )
end

# PORT: pl-vmi.c ENSURE_LOCAL_SPACE
# DIVERGES: in positions. Its `ifnot` is `THROW_EXCEPTION` (`@goto b_throw`): the overflow is the
# pending `resource_error` (since V5d).
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
    :B_NEQ_VV, :B_NEQ_VC, :C_VAR, :I_FAIL, :I_TRUE, :C_JMP, :C_OR, :C_VAR_N,
    :C_IFTHENELSE, :C_IFTHEN, :C_CUT, :C_FASTCOND, :C_FASTCUT, :C_END, :C_NOT, :C_FAIL,
    :C_LCUT, :C_LCUTIFTHEN, :C_SOFTIF, :C_SOFTCUT, :C_SOFTIFTHEN, :C_SCUT, :C_LSCUT,
    :I_CALL1, :I_CALLN, :I_CATCH, :I_EXITCATCH, :I_DET, :C_DET, :C_DETTRUE, :C_DETFALSE,
    :I_CALLCLEANUP, :I_EXITCLEANUP
)

"Jump to the label named after instruction `x`, one of those `table` names (a balanced tree of compares)."
macro vmi_dispatch(x, table::Symbol)
    names = getfield(__module__, table)::Tuple
    pairs = sort!([(UInt64(getfield(__module__, n)), n) for n in names]; by=first)
    return esc(_vmi_dispatch_tree(x, pairs))
end

# PORT: pl-wam.c getProcDefinedDefinition
# DIVERGES: the database `gd` is an argument (`trapUndefined` reads its modules).
# NOT PORTED: thread-local predicates (`getLocalProcDefinition`: no threads).
"`def`, or the definition `trapUndefined` resolves it to when it is not defined (pl-wam.c)."
function getProcDefinedDefinition(
    gd::PL_global_data{T}, def::Definition{T}
)::Definition{T} where {T}
    if !_impl_any_defined(def) && (def.flags & PROC_DEFINED) == 0
        def = trapUndefined(gd, def)
    end
    return def
end

# ORIGINAL: upstream's `setVar(*valTermRef(t))` for the exception term references (pl-wam.c
# resumeAfterException, restore_after_query): the reference's PERMANENT cell (src/pl-setup.jl
# `emptyStacks!`) unbound again, and the slot pointing at it — it held the ball as a value. A
# fresh cell allocated here (until 2026-10-15) died with the next `Undo!` while the slot kept
# pointing at its position; the next query laid a compound there and `classify_exception`
# read a functor cell as a value word (test/db/test_db.jl, test_catch_swipl.jl: BoundsError).
"Make exception term reference `t` an unbound variable again: its permanent cell, `exception_cells + off`."
@inline function _reset_exception_slot!(ld::PL_local_data, t::Int, off::Int)::Nothing
    c = ld.exception_cells + off
    ld.gstack[c] = word(0)                          # setVar(*p)
    ld.slots[t + 1] = makeRefG(c)
    return nothing
end

# PORT: pl-wam.c resumeAfterException
# DIVERGES: `outofstack` is a flag (the local stack is the only one that overflows); there is no
# stack garbage collector to consult (`considerGarbageCollect`, the `gced_size`s; G1), so the stacks
# are trimmed (`trimStacks!`: the spare reserved again) as when it declines; `fr_rewritten` is not
# kept.
# NOT PORTED: `clear_low_c_stack` (no C stack) and `updatePendingThreadSignals` (no threads).
"""
    resumeAfterException(ld, clear, outofstack)

After an exception: clear it (when `clear`), reserve the local stack's spare again, and resume
normal operation (pl-wam.c).
"""
function resumeAfterException(
    ld::PL_local_data{T}, clear::Bool, outofstack::Bool
)::Nothing where {T}
    if clear
        ld.exception_term = 0
        _reset_exception_slot!(ld, ld.exception_bin, 0)         # setVar(*valTermRef(LD->exception.bin))
        _reset_exception_slot!(ld, ld.exception_printed, 1)     # setVar(*valTermRef(LD->exception.printed))
        _reset_exception_slot!(ld, ld.exception_pending, 3)     # setVar(*valTermRef(LD->exception.pending))
    end
    trimStacks!(ld, outofstack)                     # !considerGarbageCollect(NULL)
    ld.exception_processing = false
    ld.outofstack = false
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
        Procedure{T}[],
        UInt32(0), UInt32(0), UInt32(0)  # no source
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
# (decision 1). It records its database in `ld.GD` (since V9c), which a built-in reads where
# upstream reads its global `GD` (src/pl-global.jl), and refuses a local data that a second stack
# overflow made unusable (since V5d; `outOfStack!`, src/pl-alloc.jl).
# NOT PORTED: `globalizeTermRef` (a keyed variable lives in no cell, decision 2), the profiler, the
# debugger state `PL_Q_NODEBUG` saves (all but `FR_HIDE_CHILDS`), the context module of a transparent
# predicate (`ctx`: every clause is `user`'s until R2's `module/2`), `updateAlerted`.
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
    # an engine runs queries on the database it was made for: its atom words name GD->atoms (L1b)
    @assert ld.atoms === gd.atoms "PL_open_query: the engine was made for another database (PL_local_data{T}(gd))"
    @assert ld.atom_symbols === gd.atom_symbols "PL_open_query: the engine reads another database's atom symbols"
    env = ld.environment_frame
    @assert env == 0 || ld.fliframes[ld.fli_context].base > ld.frames[env].base
    @assert ld.lTop >=
        refFliP(ld.fliframes[ld.fli_context].base, ld.fliframes[ld.fli_context].size)

    ld.unusable && error(                       # (after a second overflow: see outOfStack!)
        "PL_open_query: this local data is unusable after a second local-stack overflow; " *
        "create a fresh PL_local_data"
    )
    ld.GD = gd                                  # (the built-ins' GD; see above)
    def = getProcDefinedDefinition(gd, proc.definition)    # resolve can call-back
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
    q.solutions = 0
    q.exception = 0
    q.registers_fr = 0                          # invalid
    q.next_environment = 0                      # see D_BREAK
    # fill frame arguments
    ap = argFrameP(f.base, 0)
    for n in 0:(arity - 1)
        _slot_link!(ld, ap + 1, args + n + 1)          # *ap++ = linkValI(…) — words (L1c)
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
"Discard the choice points and frames a non-deterministic query left (pl-wam.c)."
function discard_query(ld::PL_local_data{T}, qid::Int)::Nothing where {T}
    q = ld.queries[QueryFromQid(ld, qid)]
    discardChoicesAfter(ld, q.frame, FINISH_CUT)
    q = ld.queries[QueryFromQid(ld, qid)]       # may be shifted
    discardFrame(ld, q.frame)
    qfr = ld.frames[q.frame]
    if (qfr.flags & FR_WATCHED) != 0
        setLTop!(ld, argFrameP(qfr.base, (qfr.predicate::Definition{T}).arity))
        frameFinished(ld, q.frame, FINISH_CUT)
    end
    return nothing
end

# PORT: pl-wam.c restore_after_query
# DIVERGES: lowering `lTop` drops the query's records and everything above them (decision 3). Not
# ported: the debugger state `PL_Q_NODEBUG` restores, `updateAlerted`.
"Restore the state the query was opened in (pl-wam.c)."
function restore_after_query(ld::PL_local_data{T}, qf::Int)::Nothing where {T}
    q = ld.queries[qf]
    if q.exception != 0 && ld.exception_term == 0
        _reset_exception_slot!(ld, ld.exception_printed, 1)     # setVar(*valTermRef(LD->exception.printed))
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
# signals, debugger, profiler, depth and inference limits of `LD->alerted`; `FR_NOTIFY` (the
# debugger's half of `FR_WATCHED`: `frameFinished` runs the cleanup handler of an `FR_CLEANUP`
# frame since V9g); `FR_DET` (the `det` property: nothing sets it — the `$/0` guard's
# `FR_DETGUARD` is ported, V9f); yield.
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
    hc_w::word = word(0)                            # … as an atom word (0: none; L1b C6b)
    nil_w::word = ld.atom_nil_w                     # ATOM_nil, the word of `[]` (L1b C6b; a field since L1c-6)
    tc_cref::ClauseRef{T} = gd.clauses_top_cref     # TRUST_CLAUSE's clause
    bv_voffset::Int = 0                             # bvar_cont's voffset
    fexitdet_rc::foreign_t = FTRUE                  # I_FEXITDET's rc
    SLOW_UNIFY::Bool = false                        # unify_var_cont's copy of LD->slow_unify
    dot_f::word = gd.functor_dot2                   # FUNCTOR_dot2 (L1c)
    bt_outofstack::Bool = false                     # b_throw's outofstack

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
    # DIVERGES: the operand is packed (`atom_operand`, L1b C6b): the literal, and its atom word —
    # upstream's whole operand (`code2atom(*PC++)`); no atom GC, so no `pushVolatileAtom`.
    @label H_ATOM
    if UMODE == uwrite
        @goto B_ATOM
    end
    hc_c = PCl[atom_literal(PCc[PC])]
    hc_w = atom_operand_word(PCc[PC])
    PC += 1
    @goto h_const

    # PORT: pl-vmi.c H_SMALLINT
    # DIVERGES: no word (`consInt(i)`) until L1d — a small integer in a cell is still a value-table
    # entry, so its compare is on terms (L1b C6b, user-approved).
    @label H_SMALLINT
    if UMODE == uwrite
        @goto B_SMALLINT
    end
    hc_c = PCl[PCc[PC]]
    hc_w = word(0)
    PC += 1
    @goto h_const

    # PORT: pl-vmi.c h_const
    # DIVERGES: an atom constant against an argument slot is decided on the words when they can
    # decide it (`_h_const_word!`, L1b C6b); otherwise `unify_simple_ptrs` decides, which has
    # h_const's three outcomes for a constant — the same constant (SWI's identity: `sym_key`,
    # `gnd_equal`), an unbound variable (bound, trailed), anything else; there is no global stack to
    # grow.
    @label h_const
    if hc_w != 0 && ARGP.form == ARGP_SLOT
        hc_r = _h_const_word!(ld, ARGP.pos + 1, hc_w)
        if hc_r == H_CONST_MATCH
            ARGP = _argp_add(ARGP, 1)
            @goto next_instruction
        elseif hc_r == H_CONST_FAIL
            @goto unify_backtrack                   # CLAUSE_FAILED
        end
    end
    if unify_simple_ptrs(ld, _argp_deref(ld, ARGP), hc_c) == BOOLEX_TRUE
        ARGP = _argp_add(ARGP, 1)
        @goto next_instruction
    end
    @goto unify_backtrack                           # CLAUSE_FAILED

    # PORT: pl-vmi.c H_NIL
    # DIVERGES: `h_const` with the database's `[]` and its word (upstream repeats h_const's body).
    @label H_NIL
    if UMODE == uwrite
        @goto B_NIL
    end
    hc_c = gd.atom_nil
    hc_w = nil_w                                    # c = ATOM_nil
    @goto h_const

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
    # DIVERGES: in write mode under `occurs_check=false` the variable's value goes into the argument
    # cell on the WORDS (`_cell_link!`: `makeRefG(k)` for an unbound cell, else `*k`) — the address
    # test `k > ARGP` and the trail space disappear, as no variable lives in a frame slot (each is a
    # cell). Under `true`/`error`: `setVar(*ARGP)` and unification decides, as upstream (L1c; the
    # "never write under those flags" of decision 3 is retired with the builder).
    @label H_VAR
    hv_k = varFrameP(ld.frames[FR].base, Int(PCc[PC]))
    PC += 1
    if UMODE == uwrite
        if ld.prolog_flag_occurs_check == OCCURS_CHECK_FALSE
            if ARGP.form == ARGP_GLOBAL
                _cell_link!(ld, ARGP.pos, hv_k + 1)
            else
                _argp_store!(ld, ARGP, deRef(ld, slotValue(ld, hv_k + 1)))
            end
            ARGP = _argp_add(ARGP, 1)
            @goto next_instruction
        end
        _argp_void!(ld, ARGP)                       # setVar(*ARGP)
    end
    # First try the simple case — on the CELLS (L1c sub-commit 4): the variable's slot against
    # ARGP's location; a read-mode cursor into a TERM (a keyed variable's binding) on terms.
    if ld.prolog_flag_occurs_check == OCCURS_CHECK_FALSE
        hv_loc = _argp_loc(ARGP)
        hv_rc = if hv_loc != 0
            do_unify_cells(ld, -(hv_k + 1), hv_loc)
        else
            do_unify(ld, slotValue(ld, hv_k + 1), _argp_raw(ld, ARGP))
        end
        if hv_rc == BOOLEX_TRUE
            ARGP = _argp_add(ARGP, 1)
            @goto next_instruction
        end
        if hv_rc == BOOLEX_FALSE
            @goto unify_backtrack
        end
    end

    @SAVE_REGISTERS(QID)
    hv_ok = unify_ptrs(ld, slotValue(ld, hv_k + 1), _argp_raw(ld, ARGP))
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
    # DIVERGES: in read mode an argument slot's word is copied (`*ARGP`, L1b C6a), a global cell's
    # word or a reference to it taken (`needsRef(*ARGP) ? makeRefG(ARGP) : *ARGP`, L1c), and a term's
    # child stored as its word (`_slot_store!`: a cell variable its reference).
    @label H_FIRSTVAR
    hfv_k = varFrameP(ld.frames[FR].base, Int(PCc[PC]))
    PC += 1
    if UMODE == uwrite
        _argp_fresh_var!(ld, ARGP, hfv_k + 1)       # setVar(*ARGP); varFrame = makeRefG(ARGP)
    elseif ARGP.form == ARGP_SLOT
        _slot_copy!(ld, hfv_k + 1, ARGP.pos + 1)            # varFrame(FR, *PC++) = *ARGP
    elseif ARGP.form == ARGP_GLOBAL
        _slot_from_cell!(ld, hfv_k + 1, ARGP.pos)
    else
        _slot_store!(ld, hfv_k + 1, _argp_raw(ld, ARGP))
    end
    ARGP = _argp_add(ARGP, 1)
    @goto next_instruction

    # PORT: pl-vmi.c H_FUNCTOR
    @label H_FUNCTOR
    pushArgumentStack(ld, argstack_entry{T}(_argp_add(ARGP, 1), UMODE == uwrite))
    @goto H_RFUNCTOR

    # PORT: pl-vmi.c H_RFUNCTOR
    # DIVERGES: decided on the WORDS (L1c): an unbound cell gets the compound of fresh arguments laid
    # out at `gTop` and bound to it (`bindConst`), then write mode; a compound with the operand's
    # functor is read in place (`argTermP`). The TERM path (Q2, user 2026-10-04; and a value with no
    # word form): `f/k` matches a compound of k+1 children whose head is `f`, or whose head is not a
    # symbol and unifies with `f`; `$expr/n` (literal 0) any compound of n children, read from its
    # head — a stack compound crossing `$expr` read through the cold export; a KEYED variable is bound
    # to a new stack compound through it.
    @label H_RFUNCTOR
    if UMODE == uwrite
        @goto B_RFUNCTOR
    end
    hf_f = PCc[PC]
    PC += 1
    hf_fw = functor_operand_word(hf_f)
    hf_ar = functor_arity(hf_f)
    hf_d, hf_w = _argp_deref_word(ld, ARGP)         # deRef2(ARGP, p)
    if hf_d == DREF_CELL                            # canBind(*p)
        hf_q = _alloc_compound!(ld, hf_fw, hf_ar)
        _bind_const!(ld, Int(hf_w), consPtr(hf_q, TAG_COMPOUND | STG_GLOBAL))
        ARGP = argp_t{T}(ARGP_GLOBAL, hf_q + 1, ph)
        UMODE = uwrite
        @goto next_instruction
    elseif hf_d == DREF_WORD
        _is_gcompound(hf_w) || @goto unify_backtrack           # an atom
        hf_q = valPtr(hf_w)
        if ld.gstack[hf_q] == hf_fw                 # hasFunctor(*p, f)
            ARGP = argp_t{T}(ARGP_GLOBAL, hf_q + 1, ph)        # ARGP = argTermP(*p, 0)
            @goto next_instruction
        end
        (
            functor_literal(hf_f) == 0 ||
            nameFunctor(ld.functors, ld.gstack[hf_q]) == ld.atom_dexpr
        ) ||
            @goto unify_backtrack
    end
    hf_lit = functor_literal(hf_f)
    hf_p = _argp_deref(ld, ARGP)
    if kind(hf_p) === VAR                           # a keyed variable
        hf_q = _alloc_compound!(ld, hf_fw, hf_ar)
        Trail!(ld, var_key(hf_p), _compound_term(ld, hf_q))   # bindConst(p, c)
        ARGP = argp_t{T}(ARGP_GLOBAL, hf_q + 1, ph)
        UMODE = uwrite
        @goto next_instruction
    end
    if kind(hf_p) === EXPR                          # hasFunctor(*p, f), on the term (Q2)
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
    pushArgumentStack(ld, argstack_entry{T}(_argp_add(ARGP, 1), UMODE == uwrite))
    @goto H_RLIST

    # PORT: pl-vmi.c H_RLIST
    # DIVERGES: as `H_RFUNCTOR` for `'[|]'/2` (`FUNCTOR_dot2`), a `$expr/3` included on the term path
    # (Q2; user, 2026-10-05).
    @label H_RLIST
    if UMODE == uwrite
        @goto B_RLIST
    end
    hl_d, hl_w = _argp_deref_word(ld, ARGP)         # deRef2(ARGP, p)
    if hl_d == DREF_CELL                            # case TAG_VAR
        hl_q = _alloc_compound!(ld, dot_f, 2)
        _bind_const!(ld, Int(hl_w), consPtr(hl_q, TAG_COMPOUND | STG_GLOBAL))
        ARGP = argp_t{T}(ARGP_GLOBAL, hl_q + 1, ph)
        UMODE = uwrite
        @goto next_instruction
    elseif hl_d == DREF_WORD
        _is_gcompound(hl_w) || @goto unify_backtrack           # an atom
        hl_q = valPtr(hl_w)
        if ld.gstack[hl_q] == dot_f                 # valueTerm(w)->definition == FUNCTOR_dot2
            ARGP = argp_t{T}(ARGP_GLOBAL, hl_q + 1, ph)        # ARGP = argTermP(w, 0)
            @goto next_instruction
        end
        nameFunctor(ld.functors, ld.gstack[hl_q]) == ld.atom_dexpr || @goto unify_backtrack
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
    elseif kind(hl_p) === VAR                       # a keyed variable
        hl_q = _alloc_compound!(ld, dot_f, 2)
        Trail!(ld, var_key(hl_p), _compound_term(ld, hl_q))
        ARGP = argp_t{T}(ARGP_GLOBAL, hl_q + 1, ph)
        UMODE = uwrite
        @goto next_instruction
    end
    @goto unify_backtrack

    # PORT: pl-vmi.c H_POP
    @label H_POP
    hp_e = ld.astack[ld.aTop]                       # ARGP = *--aTop
    ld.aTop -= 1
    ARGP = hp_e.argp
    UMODE = hp_e.uwrite ? uwrite : uread
    @goto next_instruction

    # PORT: pl-vmi.c H_LIST_FF
    # DIVERGES: on the WORDS (L1c), as `H_RLIST`; a `$expr/3` matches as a list cell on the term path
    # (Q2), and a keyed variable is bound through the cold export.
    @label H_LIST_FF
    hff_a = varFrameP(ld.frames[FR].base, Int(PCc[PC]))
    hff_b = varFrameP(ld.frames[FR].base, Int(PCc[PC + 1]))
    PC += 2
    if UMODE == uwrite
        hff_q = _alloc_compound!(ld, dot_f, 2)      # write:
        ld.slots[hff_a + 1] = makeRefG(hff_q + 1)   # varFrame(FR, *PC++) = makeRefG(ap)
        ld.slots[hff_b + 1] = makeRefG(hff_q + 2)
        hff_c = consPtr(hff_q, TAG_COMPOUND | STG_GLOBAL)
        if ARGP.form == ARGP_GLOBAL                 # *p = c
            ld.gstack[ARGP.pos] = hff_c
        else
            ld.slots[ARGP.pos + 1] = hff_c
        end
    else
        hff_d, hff_w = _argp_deref_word(ld, ARGP)   # deRef2(ARGP, p)
        if hff_d == DREF_WORD && _is_gcompound(hff_w) && ld.gstack[valPtr(hff_w)] == dot_f
            hff_q = valPtr(hff_w)                   # isList(*p): p = argTermP(*p, 0)
            _slot_from_cell!(ld, hff_a + 1, hff_q + 1)
            _slot_from_cell!(ld, hff_b + 1, hff_q + 2)
        elseif hff_d == DREF_CELL                   # canBind(*p)
            hff_q = _alloc_compound!(ld, dot_f, 2)
            ld.slots[hff_a + 1] = makeRefG(hff_q + 1)
            ld.slots[hff_b + 1] = makeRefG(hff_q + 2)
            _bind_const!(ld, Int(hff_w), consPtr(hff_q, TAG_COMPOUND | STG_GLOBAL))
        elseif hff_d == DREF_WORD &&
            !(
            _is_gcompound(hff_w) &&
            nameFunctor(ld.functors, ld.gstack[valPtr(hff_w)]) == ld.atom_dexpr
        )
            @goto unify_backtrack                   # an atom, or another functor
        else                                        # the term path
            hff_p = _argp_deref(ld, ARGP)
            if is_pair(hff_p) ||
                (
                _is_expr3(hff_p) &&
                unify_simple_ptrs(ld, deRef(ld, child(hff_p, 1)), gd.atom_dot) ==
                BOOLEX_TRUE
            )
                setSlotValue!(ld, hff_a + 1, child(hff_p, 2))
                setSlotValue!(ld, hff_b + 1, child(hff_p, 3))
            elseif kind(hff_p) === VAR              # a keyed variable
                hff_q = _alloc_compound!(ld, dot_f, 2)
                ld.slots[hff_a + 1] = makeRefG(hff_q + 1)
                ld.slots[hff_b + 1] = makeRefG(hff_q + 2)
                Trail!(ld, var_key(hff_p), _compound_term(ld, hff_q))   # bindConst
            else
                @goto unify_backtrack
            end
        end
    end
    ARGP = _argp_add(ARGP, 1)
    @goto next_instruction

    # ── body instructions: a body's arguments, and the head's write mode (pl-vmi.c) ─────────────
    # PORT: pl-vmi.c B_ATOM
    # DIVERGES: the operand as `H_ATOM`'s; a slot or a global cell gets the atom WORD (L1b C6b, L1c);
    # an opaque literal (no word) its term.
    @label B_ATOM
    hc_w = atom_operand_word(PCc[PC])
    if hc_w != 0 && ARGP.form == ARGP_SLOT
        ld.slots[ARGP.pos + 1] = hc_w               # *ARGP++ = code2atom(*PC++)
    elseif hc_w != 0 && ARGP.form == ARGP_GLOBAL
        ld.gstack[ARGP.pos] = hc_w
    else
        _argp_store!(ld, ARGP, PCl[atom_literal(PCc[PC])])
    end
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
    # DIVERGES: as `B_ATOM`: a slot or a global cell gets the word.
    @label B_NIL
    if ARGP.form == ARGP_SLOT
        ld.slots[ARGP.pos + 1] = nil_w              # *ARGP++ = ATOM_nil
    elseif ARGP.form == ARGP_GLOBAL
        ld.gstack[ARGP.pos] = nil_w
    else
        _argp_store!(ld, ARGP, gd.atom_nil)
    end
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
    # DIVERGES: on the WORDS into a global cell (L1c: `_cell_link!`); a keyed variable is its own
    # reference and no cell lies in a frame (decision 2), so the test that chooses the direction of
    # the link (`ARGP < k`) and the trail-space check disappear.
    @label B_ARGVAR
    bav_i = varFrameP(ld.frames[FR].base, Int(PCc[PC])) + 1
    if ARGP.form == ARGP_GLOBAL
        _cell_link!(ld, ARGP.pos, bav_i)
    elseif ARGP.form == ARGP_SLOT                   # *ARGP = linkValI(k), slot to slot on the WORDS (L1c-6)
        _slot_link!(ld, ARGP.pos + 1, bav_i)
    else
        error("B_ARGVAR: a body argument is written, never read")
    end
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
    # no cell (decision 2). It moves WORDS: into an argument slot (`_slot_link!`, L1b C6a), into a
    # global cell (`_cell_link!`, L1c).
    @label bvar_cont
    if ARGP.form == ARGP_SLOT
        _slot_link!(ld, ARGP.pos + 1, varFrameP(ld.frames[FR].base, bv_voffset) + 1)
    elseif ARGP.form == ARGP_GLOBAL
        _cell_link!(ld, ARGP.pos, varFrameP(ld.frames[FR].base, bv_voffset) + 1)
    else
        error("bvar_cont: read mode never writes into the caller's term")
    end
    ARGP = _argp_add(ARGP, 1)
    @goto next_instruction

    # PORT: pl-vmi.c B_ARGFIRSTVAR
    # DIVERGES: in a slot (a frame argument) a fresh cell, referenced from both slots; in a global cell
    # (L1c) the cell itself, as upstream (`setVar(*ARGP); varFrame = makeRefG(ARGP)`).
    @label B_ARGFIRSTVAR
    _argp_fresh_var!(ld, ARGP, varFrameP(ld.frames[FR].base, Int(PCc[PC])) + 1)
    PC += 1
    ARGP = _argp_add(ARGP, 1)
    @goto next_instruction

    # PORT: pl-vmi.c B_FIRSTVAR
    # DIVERGES: the global stack grows on demand, so no `ENSURE_GLOBAL_SPACE`; the cell's reference
    # into the slot and where ARGP points, as words (L1b C6a, L1c).
    @label B_FIRSTVAR
    bfv_p = _slot_new_var!(ld, varFrameP(ld.frames[FR].base, Int(PCc[PC])) + 1)  # *k = w
    PC += 1
    if ARGP.form == ARGP_GLOBAL                     # *ARGP++ = w
        ld.gstack[ARGP.pos] = makeRefG(bfv_p)
    else
        ld.slots[ARGP.pos + 1] = makeRefG(bfv_p)
    end
    ARGP = _argp_add(ARGP, 1)
    @goto next_instruction

    # PORT: pl-vmi.c B_VOID
    # DIVERGES: in a slot, a fresh GLOBAL cell referenced, where upstream leaves the argument an
    # unbound local cell: a local cell read as a term needs a variable naming it, which arrives when
    # the stamp falls (L1f). A global cell is set unbound, as upstream (L1c).
    @label B_VOID
    _argp_void!(ld, ARGP)                           # setVar(*ARGP++)
    ARGP = _argp_add(ARGP, 1)
    @goto next_instruction

    # PORT: pl-vmi.c B_FUNCTOR
    @label B_FUNCTOR
    pushArgumentStack(ld, argstack_entry{T}(_argp_add(ARGP, 1), false))
    @goto B_RFUNCTOR

    # PORT: pl-vmi.c B_RFUNCTOR
    # DIVERGES: the compound laid out on the global stack in one call (`_alloc_compound!`: the functor
    # word and `setVar` arguments at `gTop`); its word goes where ARGP points — a frame slot (a body
    # argument) or a global cell (inside a compound) — as upstream's (L1c).
    @label B_RFUNCTOR
    bf_f = PCc[PC]
    PC += 1
    bf_q = _alloc_compound!(ld, functor_operand_word(bf_f), functor_arity(bf_f))
    bf_c = consPtr(bf_q, TAG_COMPOUND | STG_GLOBAL)     # consPtr(gTop, TAG_COMPOUND|STG_GLOBAL)
    if ARGP.form == ARGP_SLOT                       # *ARGP = …
        ld.slots[ARGP.pos + 1] = bf_c
    elseif ARGP.form == ARGP_GLOBAL
        ld.gstack[ARGP.pos] = bf_c
    else
        error("B_RFUNCTOR: a body argument is written, never read")
    end
    ARGP = argp_t{T}(ARGP_GLOBAL, bf_q + 1, ph)     # ARGP = gTop; *ARGP++ = f
    @goto next_instruction

    # PORT: pl-vmi.c B_LIST
    @label B_LIST
    pushArgumentStack(ld, argstack_entry{T}(_argp_add(ARGP, 1), false))
    @goto B_RLIST

    # PORT: pl-vmi.c B_RLIST
    # DIVERGES: as `B_RFUNCTOR`, for `FUNCTOR_dot2`.
    @label B_RLIST
    bl_q = _alloc_compound!(ld, dot_f, 2)
    bl_c = consPtr(bl_q, TAG_COMPOUND | STG_GLOBAL)
    if ARGP.form == ARGP_SLOT
        ld.slots[ARGP.pos + 1] = bl_c
    elseif ARGP.form == ARGP_GLOBAL
        ld.gstack[ARGP.pos] = bl_c
    else
        error("B_RLIST: a body argument is written, never read")
    end
    ARGP = argp_t{T}(ARGP_GLOBAL, bl_q + 1, ph)
    @goto next_instruction

    # PORT: pl-vmi.c B_POP
    @label B_POP
    bp_e = ld.astack[ld.aTop]                       # ARGP = *--aTop
    ld.aTop -= 1
    ARGP = bp_e.argp
    @goto next_instruction

    # ── unification and comparison in the body (pl-vmi.c, O_COMPILE_IS), V9a ─────────────────────
    # PORT: pl-vmi.c B_UNIFY_FIRSTVAR
    # DIVERGES: the slot gets a fresh CELL variable (no unbound slot: decision 2), referenced.
    @label B_UNIFY_FIRSTVAR
    ARGP = argp_t{T}(ARGP_SLOT, varFrameP(ld.frames[FR].base, Int(PCc[PC])), ph)
    PC += 1
    ld.slots[ARGP.pos + 1] = makeRefG(allocGlobalCells!(ld, 1))   # setVar(*ARGP): needed for GC
    @goto unify_var_cont

    # PORT: pl-vmi.c B_UNIFY_VAR
    @label B_UNIFY_VAR
    ARGP = argp_t{T}(ARGP_SLOT, varFrameP(ld.frames[FR].base, Int(PCc[PC])), ph)
    PC += 1
    @goto unify_var_cont

    # PORT: pl-vmi.c unify_var_cont
    # DIVERGES: a helper label. No `globaliseVar`: a slot's variable is a cell already, and a keyed
    # variable lives in no cell (decision 2). The slow path (`occurs_check` true or error) writes the
    # two arguments of `=/2` above `lTop`, the slot's word copied (`*ARGP++ = *k`) and the second a
    # fresh variable, then the head code runs in WRITE mode, as upstream's (L1c: the read-mode
    # detour of decision 3 is retired with the builder). The fast path runs the head code in read
    # mode on the slot: on its fresh variable `H_RFUNCTOR` binds it to the compound it lays out on
    # the global stack, as upstream binds the frame cell — so `X = f(X)` is cyclic, as upstream's.
    @label unify_var_cont
    SLOW_UNIFY = _slow_unify(ld)
    if SLOW_UNIFY
        uvc_k = ARGP.pos + 1                        # Word k = ARGP
        ARGP = argp_t{T}(ARGP_SLOT, argFrameP(ld.lTop, 0), ph)
        _slot_copy!(ld, ARGP.pos + 1, uvc_k)        # *ARGP++ = *k
        ARGP = _argp_add(ARGP, 1)
        _argp_void!(ld, ARGP)                       # setVar(*ARGP)
        UMODE = uwrite                              # must write for GC to work
        @goto next_instruction
    end
    UMODE = uread                                   # needed?
    @goto next_instruction

    # PORT: pl-vmi.c B_UNIFY_EXIT
    # DIVERGES: the new frame of the slow path is the record pushed at `lTop`, as `I_CALL`'s.
    # NOT PORTED: `CHECK_WAKEUP` (no attributed variables).
    @label B_UNIFY_EXIT
    ARGP = argp_t{T}(ARGP_SLOT, argFrameP(ld.lTop, 0), ph)
    if SLOW_UNIFY
        NFR = pushFrame!(ld, ld.lTop)               # NFR = lTop
        DEF = gd.procedures_equals2.definition
        setNextFrameFlags(ld.frames[NFR], ld.frames[FR])
        @goto normal_call
    end
    @goto next_instruction

    # PORT: pl-vmi.c B_UNIFY_FF
    # DIVERGES: one fresh variable in both slots (decision 2: no global stack, `makeRefG`).
    @label B_UNIFY_FF
    buff_1 = varFrameP(ld.frames[FR].base, Int(PCc[PC]))
    buff_2 = varFrameP(ld.frames[FR].base, Int(PCc[PC + 1]))
    PC += 2
    buff_v = _slot_new_var!(ld, buff_1 + 1)                # *v1 = makeRefG(v): a WORD (L1c-6)
    if _slow_unify(ld)
        buff_w = _slot_new_var!(ld, buff_2 + 1)            # *v2 = makeRefG(v)
        ARGP = argp_t{T}(ARGP_SLOT, argFrameP(ld.lTop, 0), ph)
        ld.slots[ARGP.pos + 1] = makeRefG(buff_v)
        ARGP = _argp_add(ARGP, 1)
        ld.slots[ARGP.pos + 1] = makeRefG(buff_w)
        ARGP = _argp_add(ARGP, 1)
        @goto debug_equals2
    end
    ld.slots[buff_2 + 1] = ld.slots[buff_1 + 1]             # *v2 = *v1
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
        _slot_new_var!(ld, bufv_f + 1)                      # globaliseFirstVar(f): a WORD (L1c-6)
        ARGP = argp_t{T}(ARGP_SLOT, argFrameP(ld.lTop, 0), ph)
        _slot_copy!(ld, ARGP.pos + 1, bufv_f + 1)
        ARGP = _argp_add(ARGP, 1)
        _slot_copy!(ld, ARGP.pos + 1, bufv_v + 1)
        ARGP = _argp_add(ARGP, 1)
        @goto debug_equals2
    end
    _slot_link!(ld, bufv_f + 1, bufv_v + 1)          # *f = linkValI(v)
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
        _slot_copy!(ld, ARGP.pos + 1, buvv_1 + 1)
        ARGP = _argp_add(ARGP, 1)
        _slot_copy!(ld, ARGP.pos + 1, buvv_2 + 1)
        ARGP = _argp_add(ARGP, 1)
        @goto debug_equals2
    end
    @SAVE_REGISTERS(QID)
    buvv_rc = unify_ptrs_cells(ld, -(buvv_1 + 1), -(buvv_2 + 1))   # on the cells (L1c-4)
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
        _slot_new_var!(ld, bufc_f + 1)                      # globaliseFirstVar(f): a WORD (L1c-6)
        ARGP = argp_t{T}(ARGP_SLOT, argFrameP(ld.lTop, 0), ph)
        _slot_copy!(ld, ARGP.pos + 1, bufc_f + 1)
        ARGP = _argp_add(ARGP, 1)
        _argp_store!(ld, ARGP, bufc_c)
        ARGP = _argp_add(ARGP, 1)
        @goto debug_equals2
    end
    setSlotValue!(ld, bufc_f + 1, bufc_c)                   # *f = c
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
        _slot_copy!(ld, ARGP.pos + 1, buvc_k + 1)
        ARGP = _argp_add(ARGP, 1)
        _argp_store!(ld, ARGP, buvc_c)
        ARGP = _argp_add(ARGP, 1)
        @goto debug_equals2
    end
    if unify_simple_ptrs(ld, deRef(ld, slotValue(ld, buvc_k + 1)), buvc_c) == BOOLEX_TRUE
        @goto next_instruction
    end
    @goto unify_backtrack                           # CLAUSE_FAILED

    # PORT: pl-vmi.c B_EQ_VV
    # DIVERGES: the kernel's standard order raises nothing, so there is no `CMP_ERROR`.
    # NOT PORTED: the `vmi_builtin=false` branch (`debug_eq_vv`; only the debugger clears the flag).
    @label B_EQ_VV
    beq_1 = varFrameP(ld.frames[FR].base, Int(PCc[PC]))
    beq_2 = varFrameP(ld.frames[FR].base, Int(PCc[PC + 1]))
    PC += 2
    if compareStandard_cells(ld, -(beq_1 + 1), -(beq_2 + 1), true) == CMP_EQUAL   # cells (L1d)
        @goto next_instruction
    end
    @FASTCOND_FAILED

    # PORT: pl-vmi.c B_EQ_VC
    # DIVERGES: the constant operand is a literal; `*v1 == c` is SWI's identity of atomic terms
    # (`compare_primitives` in equality mode, as `PL_unify_atomic`).
    # NOT PORTED: the `vmi_builtin=false` branch.
    @label B_EQ_VC
    beqc_v = -(varFrameP(ld.frames[FR].base, Int(PCc[PC])) + 1)   # the slot's location (L1d)
    beqc_c = PCl[PCc[PC + 1]]
    PC += 2
    if _identical_atomic(ld, beqc_v, beqc_c)
        @goto next_instruction
    end
    @FASTCOND_FAILED

    # PORT: pl-vmi.c B_NEQ_VV
    # DIVERGES: as `B_EQ_VV`'s.
    @label B_NEQ_VV
    bneq_1 = varFrameP(ld.frames[FR].base, Int(PCc[PC]))
    bneq_2 = varFrameP(ld.frames[FR].base, Int(PCc[PC + 1]))
    PC += 2
    if compareStandard_cells(ld, -(bneq_1 + 1), -(bneq_2 + 1), true) == CMP_EQUAL   # cells (L1d)
        @FASTCOND_FAILED
    end
    @goto next_instruction

    # PORT: pl-vmi.c B_NEQ_VC
    # DIVERGES: as `B_EQ_VC`'s.
    @label B_NEQ_VC
    bneqc_v = -(varFrameP(ld.frames[FR].base, Int(PCc[PC])) + 1)  # the slot's location (L1d)
    bneqc_c = PCl[PCc[PC + 1]]
    PC += 2
    if !_identical_atomic(ld, bneqc_v, bneqc_c)
        @goto next_instruction
    end
    @FASTCOND_FAILED

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
    # NOT PORTED: `frameFinished` on an `FR_WATCHED` frame — a cleanup frame's clause ends in
    # `I_CALLCLEANUP I_EXITCLEANUP I_EXIT` and makes no last call, so only the debugger's
    # `FR_NOTIFY` could be set here (asserted absent; so too at `I_LCALL` and `I_TCALL`);
    # `P_TRANSPARENT` (every clause
    # is `user`'s until R2's `module/2`),
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
        dropUnlinkedChoices!(ld, id_f.base)         # (the region above the frame is reused)
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

    # PORT: pl-vmi.c I_CALL1
    # DIVERGES: the new frame is the record pushed at `lTop`, upstream's cast `NFR = lTop`.
    # NOT PORTED: the debug output.
    @label I_CALL1
    NFR = pushFrame!(ld, ld.lTop)                   # NFR = lTop
    mc_callargs = 0
    mc_call0 = true
    @goto i_metacall_common

    # PORT: pl-vmi.c I_CALLN
    # DIVERGES: as `I_CALL1`'s.
    @label I_CALLN
    mc_callargs = Int(PCc[PC])
    PC += 1
    NFR = pushFrame!(ld, ld.lTop)                   # NFR = lTop
    mc_call0 = false
    @goto i_metacall_common

    # PORT: pl-vmi.c i_metacall_common
    # DIVERGES: values for the stack's words: the goal's arguments are copied (`linkValI`) and the
    # extra arguments of `call/N` move without the reference adjustment (a term is a value); the
    # module is an index into the database's table; the procedure is `resolveProcedure`'s.
    # `max_arity_overflow` raises `lTop` over the frame, as upstream's does; so does a refusal by name
    # (a Julia exception unwinds the frame being filled: no `b_throw`). A stripModule error, a goal
    # clause that does not compile and `call_type_error` reach `b_throw` as upstream's do, with the
    # frame above `lTop`.
    # Since V9e-2 the control constructs and `call/N` for N > 8 under `call/1` run in a temporary
    # clause (`compileGoalClause`, src/pl-comp.jl), entered here as upstream enters it; NOT PORTED:
    # `Goal@Module` (refused by name, R2). NOT PORTED: closures (`_PL_closure_blob`: no closures), `FR_INRESET` (no `reset/3`:
    # asserted absent) and the `mcall_cont` trap of an undefined procedure (the supervisor
    # `S_VIRGIN` traps it, as for `I_CALL`).
    @label i_metacall_common
    mc_nb = ld.frames[NFR].base
    mc_ok, mc_goal, mc_mi = stripModule(gd, ld, slotValue(ld, argFrameP(mc_nb, 0) + 1))
    mc_ok || @goto b_throw                          # THROW_EXCEPTION
    mc_arity = 0
    mc_name = mc_goal
    mc_kind = kind(mc_goal)
    if mc_kind === SYM
        # ison(ap->type, PL_BLOB_TEXT) || goal == ATOM_nil
        (isTextAtom(mc_goal) || is_nil(mc_goal)) || @goto call_type_error
    elseif mc_kind === EXPR
        nchildren(mc_goal) >= 1 || @goto call_type_error
        mc_name = child(mc_goal, 1)
        kind(mc_name) === SYM || @goto call_type_error      # `$expr/n`
        mc_arity = nchildren(mc_goal) - 1
        if mc_call0 && _has_functor(mc_goal, gd.functors_control.colon, 2)
            @goto call_type_error
        end
        # !isCallableAtom(fd->name): no closures here
        (isTextAtom(mc_name) || is_nil(mc_name)) || @goto call_type_error
        mc_arity + mc_callargs > MAXARITY && @goto max_arity_overflow
        if mc_call0 &&
            (
            _is_control(mc_goal, gd.functors_control) ||
            (sym_key(mc_name) == gd.subclause_names.atom_call && mc_arity > 8)
        )
            @assert (ld.frames[FR].flags & FR_INRESET) == 0     # (no reset/3: '$meta_call'/1)
            if _has_functor(mc_goal, gd.functors_control.at_sign, 2)
                setLTop!(ld, argFrameP(mc_nb, 1))   # (a Julia exception unwinds this frame)
                throw(NotPortedError{T}(mc_goal, "call/1 of Goal@Module", "R2"))
            end
            # lTop = NFR (it is); compileClause(&cl, NULL, a, PROCEDURE_dcall1, module, 0, 0)
            mc_cl = try
                compileGoalClause(gd, ld, mc_goal, gd.modules[mc_mi], mc_nb)
            catch mc_e
                # a construct the compiler refuses by name (`Module:Goal`, …): a Julia
                # exception, which unwinds the frame being filled from below lTop
                mc_e isa NotPortedError && setLTop!(ld, argFrameP(mc_nb, 1))
                rethrow()
            end
            mc_cl === nothing && @goto b_throw      # case false: THROW_EXCEPTION
            DEF = gd.procedures_dcall1.definition   # NFR->predicate
            mc_f = ld.frames[NFR]
            setFramePredicate(mc_f, DEF)            # (compileClause: fr->predicate)
            setNextFrameFlags(mc_f, ld.frames[FR])  # setNextFrameFlags(NFR, FR)
            mc_f.parent = FR
            mc_f.programPointer = Code{T}(PCc, PCl, PC)
            setGenerationFrame(gd, ld, NFR)         # cl->generation set by compileGoalClause
            mc_cref = ClauseRef{T}(nothing, word(0), mc_cl, nothing)
            FR = NFR                                # environment_frame = FR = NFR
            ld.environment_frame = FR
            setLTop!(ld, argFrameP(mc_nb, Int(mc_cl.variables)))   # lTop = p (compileClause)
            ld.frames[FR].clause = mc_cref          # fr->clause = cref
            PCc = mc_cl.codes                       # PC = cl->codes
            PCl = mc_cl.literals
            PC = 1
            ARGP = argp_t{T}(ARGP_SLOT, argFrameP(ld.lTop, 0), ph)
            @goto next_instruction
        end
    else
        @goto call_type_error
    end
    if !mc_call0 && mc_arity != 1
        mc_a1 = argFrameP(mc_nb, 1)                 # pointer to 1-st arg
        mc_shift = mc_arity - 1
        if mc_shift > 0
            for mc_i in (mc_callargs - 1):-1:0
                setSlotValue!(
                    ld, mc_a1 + mc_i + mc_shift + 1, slotValue(ld, mc_a1 + mc_i + 1)
                )
            end
        else
            for mc_i in 0:(mc_callargs - 1)
                setSlotValue!(
                    ld, mc_a1 + mc_i + mc_shift + 1, slotValue(ld, mc_a1 + mc_i + 1)
                )
            end
        end
    end
    for mc_i in 1:mc_arity                          # the arguments of the goal
        setSlotValue!(      # linkValI(argTermP(goal, i)): a cell variable as its reference (L1c)
            ld, argFrameP(mc_nb, mc_i - 1) + 1, child(mc_goal, mc_i + 1)
        )
    end
    mc_proc = resolveProcedure(gd, mc_name, mc_arity + mc_callargs, gd.modules[mc_mi])
    DEF = mc_proc.definition
    @goto mcall_cont

    # PORT: pl-vmi.c mcall_cont
    # DIVERGES: only the part reached here: no `P_TRANSPARENT` (every clause is `user`'s until R2's `module/2`).
    @label mcall_cont
    setNextFrameFlags(ld.frames[NFR], ld.frames[FR])
    @goto normal_call

    # PORT: pl-vmi.c call_type_error
    @label call_type_error
    @SAVE_REGISTERS(QID)
    cte_fid = PL_open_foreign_frame(ld)
    if cte_fid != 0
        cte_t = new_term_ref(ld)                    # pushWordAsTermRef(argFrameP(NFR, 0))
        setSlotValue!(ld, cte_t + 1, slotValue(ld, argFrameP(mc_nb, 0) + 1))
        PL_error(ld, ERR_TYPE, mk_sym(T, :callable), cte_t)
        PL_close_foreign_frame(ld, cte_fid)
    end
    @LOAD_REGISTERS(QID)
    @goto b_throw                                   # THROW_EXCEPTION

    # PORT: pl-vmi.c max_arity_overflow
    @label max_arity_overflow
    setLTop!(ld, argFrameP(mc_nb, 1))
    @SAVE_REGISTERS(QID)
    mao_fid = PL_open_foreign_frame(ld)
    PL_error(ld, ERR_REPRESENTATION, mk_sym(T, :max_procedure_arity))
    PL_close_foreign_frame(ld, mao_fid)
    @LOAD_REGISTERS(QID)
    @goto b_throw                                   # THROW_EXCEPTION

    # PORT: pl-vmi.c I_CATCH
    # DIVERGES: the goal goes to `argFrameP(lTop, 0)` as a value (`linkValI`). NOT PORTED: retyping the
    # frame's `CHP_DEBUG` choice point (the debugger's; none here).
    @label I_CATCH
    icatch_p = argFrameP(ld.frames[FR].base, 0)
    newChoice(ld, CHP_CATCH, FR)
    if kind(deRef(ld, slotValue(ld, icatch_p + 1))) === VAR
        @SAVE_REGISTERS(QID)
        icatch_fid = PL_open_foreign_frame(ld)
        PL_error(ld, ERR_INSTANTIATION)
        PL_close_foreign_frame(ld, icatch_fid)
        @LOAD_REGISTERS(QID)
        @goto b_throw                               # THROW_EXCEPTION
    end
    _slot_link!(ld, argFrameP(ld.lTop, 0) + 1, icatch_p + 1)    # = B_VAR0
    @goto I_CALL1

    # PORT: pl-vmi.c I_EXITCATCH
    # DIVERGES: the CHP_CATCH record taken out of the chain is marked `unlinked` (the soft-cut's
    # record, since V9d): its region is reclaimed when `lTop` drops below it. NOT PORTED: the
    # debugger's `CHP_DEBUG` (none here; `debugstatus.debugging` is never set).
    @label I_EXITCATCH
    iec_b = ld.BFR
    while iec_b != 0 && ld.choices[iec_b].type == CHP_DEBUG
        iec_b = ld.choices[iec_b].parent
    end
    if iec_b != 0 && ld.choices[iec_b].frame == FR &&
        ld.choices[iec_b].base == argFrameP(ld.frames[FR].base, 3)
        @assert ld.choices[iec_b].type == CHP_CATCH
        ld.BFR = ld.choices[iec_b].parent
        ld.choices[iec_b].unlinked = true
        ld.frames[FR].flags |= FR_CAUGHT
    end
    @goto I_EXIT

    # ── the cleanup family (pl-vmi.c), V9g ─────────────────────────────────────────────────────
    # PORT: pl-vmi.c I_CALLCLEANUP
    # DIVERGES: the goal goes to `argFrameP(lTop, 0)` as a value (`linkValI`), as `I_CATCH`'s.
    @label I_CALLCLEANUP
    icc_f = ld.frames[FR]
    icc_arity = (icc_f.predicate::Definition{T}).arity
    icc_arg_goal = icc_arity == 2 ? 1 : 2

    # last arg is cleanup
    @SAVE_REGISTERS(QID)
    icc_fid = PL_open_foreign_frame(ld)
    icc_ok = mustBeCallable(ld, argFrameP(icc_f.base, icc_arity - 1))
    PL_close_foreign_frame(ld, icc_fid)
    @LOAD_REGISTERS(QID)
    if !icc_ok
        @goto b_throw                               # THROW_EXCEPTION
    end

    newChoice(ld, CHP_CATCH, FR)
    icc_f.flags |= FR_CLEANUP                       # set(FR, FR_CLEANUP)

    icc_p = argFrameP(icc_f.base, icc_arg_goal - 1)
    if kind(deRef(ld, slotValue(ld, icc_p + 1))) === VAR
        @SAVE_REGISTERS(QID)
        icc_fid = PL_open_foreign_frame(ld)
        PL_error(ld, ERR_INSTANTIATION)
        PL_close_foreign_frame(ld, icc_fid)
        @LOAD_REGISTERS(QID)
        @goto b_throw                               # THROW_EXCEPTION
    end
    _slot_link!(ld, argFrameP(ld.lTop, 0) + 1, icc_p + 1)       # = B_VAR1
    @goto I_CALL1

    # PORT: pl-vmi.c I_EXITCLEANUP
    # DIVERGES: positions for addresses. The frame's `CHP_CATCH` record, and any other the walk
    # steps over, taken out of the chain while its stack region stays in use, is marked `unlinked`
    # (as `I_EXITCATCH`'s). NOT PORTED: the debugger's `CHP_DEBUG` (none can be the newest here).
    @label I_EXITCLEANUP
    iecl_b = ld.BFR
    while iecl_b != 0 && ld.choices[iecl_b].type == CHP_DEBUG
        iecl_b = ld.choices[iecl_b].parent
    end
    if iecl_b != 0 && ld.choices[iecl_b].frame == FR && ld.choices[iecl_b].type == CHP_CATCH
        ld.choices[iecl_b].unlinked = true
        ld.BFR = ld.choices[iecl_b].parent
        while ld.BFR != 0 && ld.choices[ld.BFR].base > ld.frames[FR].base  # BFR > (Choice)FR
            iecl_c = ld.choices[ld.BFR]
            if iecl_c.type != CHP_DEBUG && ld.frames[iecl_c.frame].base > ld.frames[FR].base
                @goto next_instruction              # choice from setup of setup_call_catcher_cleanup/4
            end
            iecl_c.unlinked = true
            ld.BFR = iecl_c.parent
        end

        @SAVE_REGISTERS(QID)
        frameFinished(ld, FR, FINISH_EXITCLEANUP)
        @LOAD_REGISTERS(QID)
        if ld.exception_term != 0
            @goto b_throw                           # THROW_EXCEPTION
        end
    end
    @goto next_instruction                          # goto i_exit?

    # ── the exits (pl-vmi.c) ──────────────────────────────────────────────────────────────────────
    # PORT: pl-vmi.c I_EXIT
    # DIVERGES: NOT PORTED: the `LD->alerted` block (the debugger's exit port).
    @label I_EXIT
    @goto exit_continue

    # PORT: pl-vmi.c exit_continue
    # DIVERGES: lowering `lTop` to the frame drops its record and everything above it (decision 3),
    # and the record is still read after, as here (since V3). `FR_DET`/`FR_DETGUARD`
    # (`determinism_error`): since V9f (`$/0` sets the guard; the `det` property's `FR_DET` is still
    # set by nothing). `leave` (since V9g): a cleanup frame that exits deterministically has run its
    # handler at `I_EXITCLEANUP` (`FR_CAUGHT`; asserted), so `frameFinished` finds nothing to do —
    # it reads the dropped record's flags only.
    @label exit_continue
    ec_f = ld.frames[FR]
    ec_leave = 0
    if ld.BFR == 0 || ld.choices[ld.BFR].base <= ec_f.base   # deterministic
        if (ec_f.flags & FR_WATCHED) != 0
            @assert (ec_f.flags & FR_CAUGHT) != 0 "exit_continue: a cleanup frame exits before its handler ran"
            ec_leave = FR
        end
        ec_f.clause = nothing                       # leaveDefinition() destroys clause
        # leaveDefinition(DEF): (void)0 upstream
        lowerLTop!(ld, ec_f.base)                   # lTop = FR
    else
        ec_f.flags &= ~FR_INBOX
        if (ec_f.flags & (FR_DET | FR_DETGUARD)) != 0
            @SAVE_REGISTERS(QID)
            determinism_error(ld, FR, ld.BFR, :nondet)
            @LOAD_REGISTERS(QID)
            if ld.exception_term != 0
                @goto b_throw                       # THROW_EXCEPTION
            end
        end
    end

    PCc = ec_f.programPointer.codes
    PCl = ec_f.programPointer.literals
    PC = ec_f.programPointer.pc
    FR = ec_f.parent
    ld.environment_frame = FR
    DEF = ld.frames[FR].predicate::Definition{T}
    ARGP = argp_t{T}(ARGP_SLOT, argFrameP(ld.lTop, 0), ph)
    if ec_leave != 0
        @SAVE_REGISTERS(QID)
        frameFinished(ld, ec_leave, FINISH_EXIT)
        @LOAD_REGISTERS(QID)
        if ld.exception_term != 0
            @goto b_throw                           # THROW_EXCEPTION
        end
    end
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
    # move. NOT PORTED: the profiler; `frameFinished` on the query's TOP frame — only the debugger
    # watches it (`FR_NOTIFY`): the frame of the goal is `qf->frame`, below it (asserted absent).
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
        dropUnlinkedChoices!(ld, ld.frames[FR].base)    # (the region above the frame is reused)
        @assert _is_newest_live_frame(ld, FR) "L_NOLCO: last-call reuse of a frame that is not the newest live record"
        @goto next_instruction
    end
    PC += ln_jmp
    @goto next_instruction

    # PORT: pl-vmi.c L_VAR
    # DIVERGES: on the WORDS (L1c, `_slot_link!`): the references followed while their cells are
    # bound, an unbound cell as a reference to it, an atom or a compound as its word (`*v1 = w`); a
    # value with no word form dereferenced, a keyed variable being its own reference (decision 2).
    @label L_VAR
    _slot_link!(
        ld,
        varFrameP(ld.frames[FR].base, Int(PCc[PC])) + 1,
        varFrameP(ld.frames[FR].base, Int(PCc[PC + 1])) + 1
    )
    PC += 2
    @goto next_instruction

    # PORT: pl-vmi.c L_VOID
    @label L_VOID
    _slot_new_var!(ld, varFrameP(ld.frames[FR].base, Int(PCc[PC])) + 1)   # setVar(*varFrameP(FR, *PC++)): a WORD (L1c-6)
    PC += 1
    @goto next_instruction

    # PORT: pl-vmi.c L_ATOM
    # DIVERGES: the operand is `B_ATOM`'s (`atom_operand`, L1b C6b): the slot gets the atom word, or
    # an opaque literal its term; no atom GC, so no `pushVolatileAtom`.
    @label L_ATOM
    hc_w = atom_operand_word(PCc[PC + 1])
    if hc_w != 0
        ld.slots[varFrameP(ld.frames[FR].base, Int(PCc[PC])) + 1] = hc_w
    else
        setSlotValue!(
            ld, varFrameP(ld.frames[FR].base, Int(PCc[PC])) + 1,
            PCl[atom_literal(PCc[PC + 1])]
        )
    end
    PC += 2
    @goto next_instruction

    # PORT: pl-vmi.c L_NIL
    @label L_NIL
    ld.slots[varFrameP(ld.frames[FR].base, Int(PCc[PC])) + 1] = nil_w   # the word (L1b C6b)
    PC += 1
    @goto next_instruction

    # PORT: pl-vmi.c L_SMALLINT
    # DIVERGES: the operand indexes the literal table (since V1 L2).
    @label L_SMALLINT
    setSlotValue!(ld, varFrameP(ld.frames[FR].base, Int(PCc[PC])) + 1, PCl[PCc[PC + 1]])
    PC += 2
    @goto next_instruction

    # PORT: pl-vmi.c I_LCALL
    # DIVERGES: the operand as `I_CALL`'s. QUIRK kept: `setFramePredicate` twice (vmi:2499, 2527).
    # NOT PORTED: the context module and `P_TRANSPARENT` (every clause is `user`'s until R2's
    # `module/2`), `FR_WATCHED` (asserted absent: see `I_DEPART`), `HIDE_CHILDS`.
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
    if !_impl_any_defined(DEF) && (DEF.flags & PROC_DEFINED) == 0
        @SAVE_REGISTERS(QID)
        DEF = getProcDefinedDefinition(gd, DEF)
        @LOAD_REGISTERS(QID)
    end
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

    # PORT: pl-vmi.c I_DET
    @label I_DET
    ld.frames[FR].flags |= FR_DETGUARD | FR_DETGUARD_SET       # set(FR, FR_DETGUARD|FR_DETGUARD_SET)
    @goto I_CUT

    # PORT: pl-vmi.c I_CUT
    # DIVERGES: the age test compares positions (`base`), as `discardChoicesAfter`'s. NOT PORTED: the
    # debugger branch (`tracePort(…, CUT_CALL_PORT)`: no debugger). The `exception_term` test after
    # the discard is read since V9g: a cleanup frame the cut discards runs its handler
    # (`discardChoicesAfter` → `frameFinished`), which can raise.
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
    # DIVERGES: a fresh GLOBAL cell's reference into the slot, where upstream leaves the slot an
    # unbound local cell (see `B_VOID`).
    @label C_VAR
    _slot_new_var!(ld, varFrameP(ld.frames[FR].base, Int(PCc[PC])) + 1)
    PC += 1
    @goto next_instruction

    # ── disjunctions (pl-vmi.c), V9d ──────────────────────────────────────────────────────────────
    # PORT: pl-vmi.c C_JMP
    @label C_JMP
    PC += Int(PCc[PC])
    PC += 1
    @goto next_instruction

    # PORT: pl-vmi.c C_OR
    # DIVERGES: the choice point's `value.pc` is an index into the clause's code (see `choice`).
    @label C_OR
    co_skip = Int(PCc[PC])
    PC += 1
    @ENSURE_LOCAL_SPACE(SIZEOF_CHOICE)              # hasLocalSpace(sizeof(struct choice))
    co_ch = newChoice(ld, CHP_JUMP, FR)
    ld.choices[co_ch].value_pc = PC + co_skip
    ARGP = argp_t{T}(ARGP_SLOT, argFrameP(ld.lTop, 0), ph)    # ARGP = argFrameP(lTop, 0)
    @goto next_instruction

    # ── the conditionals (pl-vmi.c), V9d ──────────────────────────────────────────────────────────
    # A condition keeps the choice point that was current when it started in a frame slot of its own
    # (upstream: `consTermRef(BFR)`, an offset on the local stack). Here the slot holds the choice
    # point's POSITION (`base`) as an integer term, and `c_cut` compares positions, as
    # `discardChoicesAfter` does (decision 3).
    # PORT: pl-vmi.c C_IFTHENELSE
    # DIVERGES: the slot's value (above).
    @label C_IFTHENELSE
    setSlotValue!(
        ld,
        varFrameP(ld.frames[FR].base, Int(PCc[PC])) + 1,
        mk_gnd(
            T, ld.choices[ld.BFR].base
        )
    )                                               # == C_IFTHEN
    PC += 1
    @goto C_OR

    # PORT: pl-vmi.c C_IFTHEN
    # DIVERGES: the slot's value (above).
    @label C_IFTHEN
    setSlotValue!(
        ld,
        varFrameP(ld.frames[FR].base, Int(PCc[PC])) + 1,
        mk_gnd(
            T, ld.choices[ld.BFR].base
        )
    )
    PC += 1
    @goto next_instruction

    # PORT: pl-vmi.c C_FASTCOND
    # DIVERGES: the slot's value (above); `LD->fast_condition` is an index (see `FASTCOND_FAILED`).
    # NOT PORTED: the `vmi_builtin=false` branch (only the debugger clears the flag).
    @label C_FASTCOND
    setSlotValue!(
        ld,
        varFrameP(ld.frames[FR].base, Int(PCc[PC])) + 1,
        mk_gnd(
            T, ld.choices[ld.BFR].base
        )
    )                                               # == C_IFTHEN
    cfc_skip = Int(PCc[PC + 1])
    PC += 2
    ld.fast_condition = PC + cfc_skip
    @goto next_instruction

    # PORT: pl-vmi.c C_FASTCUT
    @label C_FASTCUT
    if ld.fast_condition == 0
        @goto C_CUT
    end
    PC += 1
    ld.fast_condition = 0
    @goto next_instruction

    # PORT: pl-vmi.c C_CUT
    # DIVERGES: the slot holds the choice point's position (above).
    @label C_CUT
    cc_och = Int(
        int64_value(slotValue(ld, varFrameP(ld.frames[FR].base, Int(PCc[PC])) + 1))
    )
    PC += 1                                         # cannot be in macro!
    @goto c_cut

    # PORT: pl-vmi.c c_cut
    # DIVERGES: `och` is a position; the walk compares positions. The frames a choice point
    # protected are discarded and killed as upstream, and their records — with the choice points' —
    # are dropped when `lTop` is lowered (decision 3). Since V9g a cleanup frame cut away runs its
    # handler (`frameFinished`, `cut`); the stack never moves, so there is no re-basing after it.
    @label c_cut
    cc_ch = ld.BFR
    @assert ld.choices[cc_ch].base >= cc_och        # assert(BFR>=och)
    while ld.choices[cc_ch].base > cc_och
        cc_c = ld.choices[cc_ch]
        cc_fr2 = cc_c.frame
        while !in_continuation(ld, cc_fr2, FR, cc_c.parent)     # See (*)
            cc_f2 = ld.frames[cc_fr2]
            @assert cc_f2.clause !== nothing ||
                ((cc_f2.predicate::Definition{T}).flags & P_FOREIGN) != 0
            if (cc_f2.flags & FR_WATCHED) != 0
                ld.BFR = cc_ch
                @SAVE_REGISTERS(QID)
                frameFinished(ld, cc_fr2, FINISH_CUT)
                @LOAD_REGISTERS(QID)
                if ld.exception_term != 0
                    @goto b_throw                   # THROW_EXCEPTION
                end
            end
            discardFrame(ld, cc_fr2)
            killFrame(cc_f2)                        # kill for markPredicates()
            cc_fr2 = cc_f2.parent
        end
        if cc_c.parent != 0 && ld.choices[cc_c.parent].base == cc_och   # ch->parent == och
            DiscardMark(ld, cc_c.mark)
        end
        cc_ch = cc_c.parent
    end
    @assert ld.choices[cc_ch].base == cc_och        # assert(och == ch)
    ld.BFR = cc_ch
    if cc_och > ld.frames[FR].base                  # (void *)och > (void *)FR
        setLTop!(ld, cc_och + SIZEOF_CHOICE)        # lTop = (LocalFrame)(och+1)
    else
        cc_pred = ld.frames[FR].predicate::Definition{T}
        cc_nvar = if (cc_pred.flags & P_FOREIGN) != 0
            cc_pred.arity
        else
            Int(((ld.frames[FR].clause::ClauseRef{T}).clause::Clause{T}).variables)
        end
        setLTop!(ld, argFrameP(ld.frames[FR].base, cc_nvar))
    end
    ARGP = argp_t{T}(ARGP_SLOT, argFrameP(ld.lTop, 0), ph)    # ARGP = argFrameP(lTop, 0)
    @goto next_instruction

    # PORT: pl-vmi.c C_LCUT
    # DIVERGES: the slot holds the choice point's position (see `C_IFTHENELSE`).
    @label C_LCUT
    cl_och = Int(
        int64_value(slotValue(ld, varFrameP(ld.frames[FR].base, Int(PCc[PC])) + 1))
    )
    PC += 1
    @goto c_lcut_cont

    # PORT: pl-vmi.c c_lcut_cont
    # DIVERGES: `och` is a position: the choice point made right after the mark — the
    # condition's own — is the one whose parent lies at it. A NULL `och` (`C_LSCUT` at the bottom
    # of the chain) is position 0.
    @label c_lcut_cont
    cl_ch = ld.BFR
    while cl_ch != 0
        cl_parent = ld.choices[cl_ch].parent
        if (cl_parent == 0 ? 0 : ld.choices[cl_parent].base) == cl_och  # ch->parent == och
            cc_och = ld.choices[cl_ch].base         # VMH_GOTO(c_cut, ch)
            @goto c_cut
        end
        cl_ch = cl_parent
    end
    @assert ld.choices[ld.BFR].base == cl_och       # assert(BFR == och): no choicepoint yet
    @goto next_instruction

    # PORT: pl-vmi.c C_LCUTIFTHEN
    @label C_LCUTIFTHEN
    @goto C_CUT

    # ── the soft-cut (pl-vmi.c), V9d ──────────────────────────────────────────────────────────────
    # PORT: pl-vmi.c C_SOFTIFTHEN
    @label C_SOFTIFTHEN
    @goto C_IFTHEN

    # PORT: pl-vmi.c C_SOFTIF
    # DIVERGES: the slot holds a POSITION (see `C_IFTHENELSE`) — here `lTop`, where `C_OR` is about
    # to make the condition's choice point.
    @label C_SOFTIF
    setSlotValue!(ld, varFrameP(ld.frames[FR].base, Int(PCc[PC])) + 1, mk_gnd(T, ld.lTop))  # see C_SOFTCUT
    PC += 1
    @goto C_OR

    # PORT: pl-vmi.c C_SOFTCUT
    # DIVERGES: the slot holds a position, NEGATED once the soft-cut has run, as upstream negates
    # its term reference. The choice point taken out of the chain is marked `unlinked`: its record
    # stays in the pool while its stack region is in use (see `dropUnlinkedChoices!`), where
    # upstream leaves the struct on the local stack.
    @label C_SOFTCUT
    sc_slot = varFrameP(ld.frames[FR].base, Int(PCc[PC])) + 1
    PC += 1
    sc_ref = Int(int64_value(slotValue(ld, sc_slot)))
    if sc_ref > 0
        sc_bfr = ld.BFR
        if ld.choices[sc_bfr].base == sc_ref        # bfr == ch
            ld.choices[sc_bfr].unlinked = true
            ld.BFR = ld.choices[sc_bfr].parent
            setSlotValue!(ld, sc_slot, mk_gnd(T, -ld.choices[ld.BFR].base))
        else
            while sc_bfr != 0 && ld.choices[sc_bfr].base >= sc_ref      # for(; bfr >= ch; …)
                sc_par = ld.choices[sc_bfr].parent
                if sc_par != 0 && ld.choices[sc_par].base == sc_ref     # bfr->parent == ch
                    ld.choices[sc_par].unlinked = true
                    ld.choices[sc_bfr].parent = ld.choices[sc_par].parent
                    setSlotValue!(
                        ld, sc_slot, mk_gnd(
                            T, -ld.choices[ld.choices[sc_par].parent].base
                        )
                    )
                    break
                end
                sc_bfr = sc_par
            end
        end
    end                                             # else: Already killed
    @goto next_instruction

    # PORT: pl-vmi.c C_SCUT
    @label C_SCUT
    @goto next_instruction

    # PORT: pl-vmi.c C_LSCUT
    # DIVERGES: the slot holds a position (see `C_SOFTCUT`); the choice point at it is found on the
    # chain, and its parent's position — 0 for none — is what `c_lcut_cont` cuts back to.
    @label C_LSCUT
    ls_ref = Int(
        int64_value(slotValue(ld, varFrameP(ld.frames[FR].base, Int(PCc[PC])) + 1))
    )
    PC += 1
    if ls_ref < 0
        ls_ref = -ls_ref
    end
    ls_ch = ld.BFR
    while ls_ch != 0 && ld.choices[ls_ch].base > ls_ref
        ls_ch = ld.choices[ls_ch].parent
    end
    @assert ls_ch != 0 && ld.choices[ls_ch].base == ls_ref "C_LSCUT: the slot's choice point is not on the chain"
    ls_par = ld.choices[ls_ch].parent
    cl_och = ls_par == 0 ? 0 : ld.choices[ls_par].base          # ch->parent
    @goto c_lcut_cont

    # PORT: pl-vmi.c C_END
    @label C_END
    @goto next_instruction

    # PORT: pl-vmi.c C_NOT
    @label C_NOT
    @goto C_IFTHENELSE

    # PORT: pl-vmi.c C_DET
    @label C_DET
    @goto C_IFTHENELSE

    # PORT: pl-vmi.c C_DETTRUE
    # DIVERGES: the slot holds the choice point's position (see `C_IFTHENELSE`), so `ch->parent ==
    # och` compares the parent's position. The block's own choice point, taken out of the chain while
    # its stack region stays in use (upstream lowers nothing here), is marked `unlinked`, as
    # `C_SOFTCUT`'s: the pools hold live records only (decision 3).
    @label C_DETTRUE
    cdt_och = Int(
        int64_value(slotValue(ld, varFrameP(ld.frames[FR].base, Int(PCc[PC])) + 1))
    )
    cdt_ch = ld.BFR
    cdt_parent = ld.choices[cdt_ch].parent
    if cdt_parent != 0 && ld.choices[cdt_parent].base == cdt_och    # ch->parent == och
        @assert ld.choices[cdt_ch].type == CHP_JUMP
        ld.choices[cdt_ch].unlinked = true
        ld.BFR = cdt_parent                         # BFR = och
        @assert PCc[PC + 1] == C_JMP                # assert(PC[1] == encode(C_JMP))
        PC += Int(PCc[PC + 2])
        PC += 3
        @goto next_instruction
    end
    @SAVE_REGISTERS(QID)
    det_goal_error(ld, FR, PC - 1, :nondet)
    @LOAD_REGISTERS(QID)
    if ld.exception_term != 0
        @goto b_throw                               # THROW_EXCEPTION
    end
    @goto C_CUT

    # PORT: pl-vmi.c C_DETFALSE
    @label C_DETFALSE
    @SAVE_REGISTERS(QID)
    det_goal_error(ld, FR, PC - 1, :fail)
    @LOAD_REGISTERS(QID)
    if ld.exception_term != 0
        @goto b_throw                               # THROW_EXCEPTION
    end
    @goto shallow_backtrack                         # BODY_FAILED

    # PORT: pl-vmi.c C_FAIL
    @label C_FAIL
    @goto shallow_backtrack                         # BODY_FAILED

    # PORT: pl-vmi.c C_VAR_N
    # DIVERGES: fresh variables into the slots (decision 2), as `C_VAR`.
    @label C_VAR_N
    cvn_vp = varFrameP(ld.frames[FR].base, Int(PCc[PC]))
    cvn_count = Int(PCc[PC + 1])
    PC += 2
    cvn_p = allocGlobalCells!(ld, cvn_count)
    for cvn_i in 0:(cvn_count - 1)
        ld.slots[cvn_vp + cvn_i + 1] = makeRefG(cvn_p + cvn_i)   # one block, as before C6a
    end
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
    # DIVERGES: NOT PORTED: the `vmi_builtin=false` branch (`debug_pred1`; see `TYPE_TEST`). On the WORDS
    # (L1c-6: `deRef2(varFrameP(FR, *PC++), p); canBind(*p)`, `_slot_is_var`).
    @label I_VAR
    tt_v = _slot_is_var(ld, varFrameP(ld.frames[FR].base, Int(PCc[PC])) + 1)
    PC += 1
    tt_v && @goto next_instruction
    @FASTCOND_FAILED

    # PORT: pl-vmi.c I_NONVAR
    # DIVERGES: as `I_VAR`'s.
    @label I_NONVAR
    tt_v = _slot_is_var(ld, varFrameP(ld.frames[FR].base, Int(PCc[PC])) + 1)
    PC += 1
    !tt_v && @goto next_instruction
    @FASTCOND_FAILED

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
    af_np = deRef(ld, slotValue(ld, varFrameP(ld.frames[FR].base, Int(PCc[PC + 1])) + 1))  # B +
    af_add = int64_value(PCl[PCc[PC + 2]])                              # <int>
    PC += 3
    if number_kind(af_np) === NUM_INTEGER && integer_is_int64(af_np) &&
        PLMINTAGGEDINT <= int64_value(af_np) <= PLMAXTAGGEDINT          # isTaggedInt(*np)
        setSlotValue!(ld, af_rp + 1, mk_gnd(T, int64_value(af_np) + af_add))    # *rp = consInt(r)
        @goto next_instruction
    end
    @SAVE_REGISTERS(QID)
    af_rc = false
    af_w = ph
    af_fid = PL_open_foreign_frame(ld)                  # Still needed?
    if af_fid != 0
        af_t = new_term_ref(ld)                         # pushWordAsTermRef(np)
        setSlotValue!(ld, af_t + 1, af_np)
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
    setSlotValue!(ld, varFrameP(ld.frames[FR].base, Int(PCc[PC - 3])) + 1, af_w)  # rp: may have shifted
    @goto next_instruction

    # ── supervisors (pl-vmi.c) ────────────────────────────────────────────────────────────────────
    # PORT: pl-vmi.c S_VIRGIN
    # NOT PORTED: the profiler; thread-local predicates (no threads).
    @label S_VIRGIN
    setLTop!(
        ld, argFrameP(ld.frames[FR].base, (ld.frames[FR].predicate::Definition{T}).arity)
    )

    if !_impl_any_defined(DEF) && (DEF.flags & PROC_DEFINED) == 0
        @SAVE_REGISTERS(QID)
        DEF = getProcDefinedDefinition(gd, DEF)     # since V5c: autoImport, as decided since Q-A
        @LOAD_REGISTERS(QID)
        setFramePredicate(ld.frames[FR], DEF)
        setGenerationFrame(gd, ld, FR)
        if _impl_any_defined(DEF)
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
    # DIVERGES: the `CHP_DEBUG` choice point is pushed as upstream pushes it; only the debugger's
    # retry reads it upstream (not ported), and `b_throw` discards it. (The context is qualified as
    # upstream's since V5c: src/pl-error.jl.)
    @label S_UNDEF
    # getUnknownModule(DEF->module): nothing sets a module's `unknown` flag, so it is `system`'s,
    # UNKNOWN_ERROR (src/pl-modul.jl); the warning and fail branches are not reachable, not ported.
    @assert getUnknownModule(gd, gd.modules[DEF.module_]) == UNKNOWN_ERROR
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
    # `clause_choice` where upstream's is on the C stack. With no clause, a frame that must not fail
    # (`FR_DETGUARD`, since V9f) gets upstream's `CHP_DEBUG` choice point; NOT PORTED: the debugger's.
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
        if (ld.frames[FR].flags & (FR_SSU_DET | FR_DET | FR_DETGUARD)) != 0
            newChoice(ld, CHP_DEBUG, FR)            # (`debugstatus.debugging`: no debugger)
        end
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
    # one does — it can unify with a list-cell clause child by child (Q2; user, 2026-10-05). Decided
    # on the WORDS (L1c): `isList(*k)` is the functor word `FUNCTOR_dot2`, `isNil(*k)` the word of
    # `[]`; only a value with no word form (a keyed variable's binding) is read as a term.
    @label S_LIST
    ARGP = argp_t{T}(ARGP_SLOT, argFrameP(ld.frames[FR].base, 0), ph)
    sl_d, sl_w = _argp_deref_word(ld, _argp_add(ARGP, Int(PCc[PC])))   # deRef2(ARGP+PC[0], k)
    if sl_d == DREF_CELL                            # canBind(*k)
        PCc = DEF.code_data.staticp                 # PC = SUPERVISOR(staticp) + 1
        PC = 2
        @goto S_STATIC
    elseif sl_d == DREF_WORD
        if _is_gcompound(sl_w)
            sl_f = ld.gstack[valPtr(sl_w)]
            if sl_f == dot_f                        # isList(*k)
                tc_cref = DEF.codes_crefs[Int(PCc[PC + 2])]
                PC += 3
                @goto TRUST_CLAUSE
            elseif nameFunctor(ld.functors, sl_f) == ld.atom_dexpr &&
                arityFunctor(ld.functors, sl_f) == 3                # a `$expr/3` (Q2)
                PCc = DEF.code_data.staticp
                PC = 2
                @goto S_STATIC
            end
        elseif sl_w == nil_w                        # isNil(*k)
            tc_cref = DEF.codes_crefs[Int(PCc[PC + 1])]
            PC += 3
            @goto TRUST_CLAUSE
        end
        @goto deep_backtrack                        # FRAME_FAILED
    end
    sl_k = _argp_deref(ld, _argp_add(ARGP, Int(PCc[PC])))   # (a value with no word form)
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
    # `CHP_JUMP` (since V9d): the popped choice point's record, and any above it, are dropped before
    # `lTop` is lowered to it, and the code registers are reloaded from the frame's clause (see
    # `deep_backtrack`). The debugger's `CHP_DEBUG` is NOT PORTED.
    @label shallow_backtrack
    sb_ch = ld.BFR
    sb_c = ld.choices[sb_ch]
    if FR == sb_c.frame
        Undo!(ld, sb_c.mark)

        if sb_c.type == CHP_JUMP
            DiscardMark(ld, sb_c.mark)
            # PC = ch->value.pc: an index into the code of the frame's clause, which the code
            # registers need not hold — a retry (PL_next_solution) arrives here from the query's
            # own code
            sb_jclause = (ld.frames[FR].clause::ClauseRef{T}).clause::Clause{T}
            PCc = sb_jclause.codes
            PCl = sb_jclause.literals
            PC = sb_c.value_pc
            ld.BFR = sb_c.parent
            sb_base = sb_c.base
            dropRecords!(ld, sb_base)               # the popped choice point and all above it
            ld.lTop = sb_base                       # lTop = (LocalFrame)ch
            ARGP = argp_t{T}(ARGP_SLOT, argFrameP(ld.lTop, 0), ph)

            @goto next_instruction
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
                # (A record C_SOFTCUT unlinked may lie there: it is reclaimed first — `*->`, V9d.)
                dropUnlinkedChoices!(ld, sb_c.base)
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
    # `restore_after_query` drops the dead records. NOT PORTED: the debugger (`trace_action`),
    # the `LD->alerted` block, the
    # inference count. Since V9f: `frameFailed` for a frame that must not fail, and the `CHP_DEBUG`
    # choice point of such a frame (`S_STATIC` with no clause) — the popped record and the dead ones
    # above it are dropped at once, as at `CHP_CATCH`. `CHP_JUMP` (since V9d): the code registers are reloaded from the
    # frame's clause, because `value.pc` is an index into it where upstream's is an address.
    # `CHP_CATCH` (since V9f): the popped record and the dead ones above it are dropped at once, as
    # at `CHP_CLAUSE`; since V9g its `FR_WATCHED` branch: the goal of a cleanup frame failed, the
    # handler runs with `fail` (`callCleanupHandler`).
    @label deep_backtrack                           # next_choice:
    while FR != 0 && ld.frames[FR].base > ld.choices[ld.BFR].base     # NULL is below every choice
        leaveFrame(ld, FR)                          # LEAVE_FAILED_FRAME(FR)
        if (ld.frames[FR].flags & (FR_WATCHED | FR_SSU_DET | FR_DET | FR_DETGUARD)) != 0
            @SAVE_REGISTERS(QID)
            frameFailed(ld, FR)
            @LOAD_REGISTERS(QID)
            if ld.exception_term != 0
                @goto b_throw                       # THROW_EXCEPTION
            end
        end
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

    if db_c.type == CHP_JUMP
        db_jclause = (ld.frames[FR].clause::ClauseRef{T}).clause::Clause{T}
        PCc = db_jclause.codes
        PCl = db_jclause.literals
        PC = db_c.value_pc
        DiscardMark(ld, db_c.mark)
        db_jbase = db_c.base
        ld.BFR = db_c.parent
        dropRecords!(ld, db_jbase)                  # the popped choice point and all above it
        ld.lTop = db_jbase                          # lTop = (LocalFrame)(BFR)
        ARGP = argp_t{T}(ARGP_SLOT, argFrameP(ld.lTop, 0), ph)
        @goto next_instruction
    elseif db_c.type == CHP_CLAUSE                  # try next clause
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
    elseif db_c.type == CHP_CATCH                   # catch/3 & setup_call_cleanup/3
        if (ld.frames[FR].flags & FR_WATCHED) != 0  # (BFR->frame is FR here)
            DiscardMark(ld, db_c.mark)
            ld.environment_frame = FR               # environment_frame = FR = BFR->frame
            setLTop!(ld, db_c.base + SIZEOF_CHOICE) # lTop = (LocalFrame)(BFR+1)
            ld.frames[FR].clause = nothing
            if (ld.frames[FR].flags & FR_CLEANUP) != 0
                @SAVE_REGISTERS(QID)
                callCleanupHandler(ld, FR, FINISH_FAIL)
                @LOAD_REGISTERS(QID)
            else
                ld.frames[FR].flags |= FR_CAUGHT
            end
            if ld.exception_term != 0
                @goto b_throw                       # THROW_EXCEPTION
            end
        else
            ld.frames[FR].flags |= FR_CAUGHT        # set(BFR->frame, FR_CAUGHT)
        end
        DiscardMark(ld, db_c.mark)
        ld.BFR = db_c.parent
        dropRecords!(ld, db_c.base)                 # the popped choice point and all above it
        @goto deep_backtrack                        # goto next_choice
    elseif db_c.type == CHP_DEBUG                   # Just for debugging purposes
        if (ld.frames[FR].flags & (FR_SSU_DET | FR_DET | FR_DETGUARD)) != 0 &&
            db_c.frame == FR
            @SAVE_REGISTERS(QID)
            db_rc = ssu_or_det_failed(ld, FR)
            @LOAD_REGISTERS(QID)
            if !db_rc
                @assert ld.exception_term != 0
                @goto b_throw                       # THROW_EXCEPTION
            end
        end
        DiscardMark(ld, db_c.mark)
        ld.BFR = db_c.parent
        dropRecords!(ld, db_c.base)                 # the popped choice point and all above it
        @goto deep_backtrack                        # goto next_choice
    end
    throw(
        NotPortedError{T}(DEF.name, "backtracking into a $(db_c.type) choice point", "V9")
    )

    # ── exceptions (pl-vmi.c) ─────────────────────────────────────────────────────────────────────
    # PORT: pl-vmi.c b_throw
    # DIVERGES: since V9f `findCatcher` finds catch/3's frame (an index; 0 when none). `outofstack` is a flag
    # (the local stack's); with no emergency space, `outOfStack!`'s second-overflow branch marks the
    # local data unusable and throws, where upstream ends the process (see there). The rewrite loop's
    # `exception_hook` runs only when `'$exception_hook'/5` has clauses — none: not entered.
    @label b_throw
    ld.fast_condition = 0                           # A_FUNC exceptions
    QF = QueryFromQid(ld, QID)
    _reset_argument_stack!(ld, ld.queries[QF])
    @assert ld.exception_term != 0
    bt_outofstack = ld.outofstack                   # outofstack = LD->outofstack
    ld.outofstack = false

    bt_low = argFrameP(ld.frames[FR].base, (ld.frames[FR].predicate::Definition{T}).arity)
    if ld.lTop < bt_low
        ld.lTop = bt_low
    end

    if has_emergency_space(ld, SIZEOF_LOCALFRAME)
        bt_fid = open_foreign_frame(ld)
    else                                            # fatal
        ld.outofstack = true
        outOfStack!(ld, STACK_OVERFLOW_THROW)       # throws: see outOfStack!
        bt_fid = 0
    end
    # find the catching frame (since V9f). The rewrite loop runs `exception_hook` only when
    # `'$exception_hook'/5` has clauses (pl-wam.c:2276): none here, so it is not entered.
    @SAVE_REGISTERS(QID)
    bt_catchfr = findCatcher(gd, ld, bt_fid, FR, ld.BFR, ld.exception_term)
    @LOAD_REGISTERS(QID)
    PL_close_foreign_frame(ld, bt_fid)
    @goto b_throw_debug

    # PORT: pl-vmi.c b_throw_debug
    # DIVERGES: NOT PORTED: the debugger, and printing an uncaught exception (`print_unhandled_exception`;
    # swipl prints it under `PL_Q_NORMAL`, the kernel never prints).
    @label b_throw_debug
    @goto b_throw_unwind

    # PORT: pl-vmi.c b_throw_unwind
    # DIVERGES: frames compared by position; the frames above the catcher (or, with none, up to the
    # query's top) are left; since V9g a cleanup frame left runs its handler (`frameFinished`,
    # `exception(Ball)`), with the ball pending around it.
    @label b_throw_unwind
    while FR != 0 && (bt_catchfr == 0 || ld.frames[FR].base > ld.frames[bt_catchfr].base)
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
        if (ld.frames[FR].flags & FR_WATCHED) != 0
            @SAVE_REGISTERS(QID)
            frameFinished(ld, FR, FINISH_EXCEPT)
            @LOAD_REGISTERS(QID)
        end

        PCc = ld.frames[FR].programPointer.codes
        PCl = ld.frames[FR].programPointer.literals
        PC = ld.frames[FR].programPointer.pc
        FR = ld.frames[FR].parent
    end
    @goto b_throw_resume

    # PORT: pl-vmi.c b_throw_resume
    # DIVERGES: since V9f both branches. The catcher's: the recover goal is copied to
    # `argFrameP(lTop, 0)` as a value; `LD->query->next_environment` (GC's) is not kept; an `unwind(_)`
    # ball (`uncachableException`: abort, halt — `'$recover_and_rethrow'/2`, boot/init.pl) is refused by
    # name (R2). No GC request to honour.
    @label b_throw_resume
    if bt_catchfr != 0
        @assert FR == bt_catchfr
        br_base = ld.frames[FR].base
        @SAVE_REGISTERS(QID)
        dbg_discardChoicesAfter(ld, FR, FINISH_EXTERNAL_EXCEPT_UNDO)
        @LOAD_REGISTERS(QID)
        ld.environment_frame = FR
        PL_unify(ld, argFrameP(br_base, 1), ld.exception_term)      # re-unify
        setLTop!(ld, argFrameP(br_base, 3))                         # above the catch/3
        if _hasFunctor(
            deRef(ld, slotValue(ld, ld.exception_term + 1)), mk_sym(T, :unwind), 1
        )
            throw(
                NotPortedError{T}(
                    slotValue(ld, ld.exception_term + 1),
                    "an unwind(_) ball caught ('\$recover_and_rethrow'/2, boot/init.pl)",
                    "R2"
                )
            )
        end
        setSlotValue!(
            ld, argFrameP(ld.lTop, 0) + 1, slotValue(ld, argFrameP(br_base, 2) + 1)
        )   # recover goal
        br_exit = findCatchExit(gd)                                 # PC = findCatchExit()
        PCc = br_exit.codes
        PCl = br_exit.literals
        PC = br_exit.pc
        ARGP = argp_t{T}(ARGP_SLOT, argFrameP(ld.lTop, 1), ph)
        @SAVE_REGISTERS(QID)
        resumeAfterException(ld, true, bt_outofstack)
        @LOAD_REGISTERS(QID)
        @goto I_CALL1
    end
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
    resumeAfterException(ld, (br_q.flags & PL_Q_PASS_EXCEPTION) == 0, bt_outofstack)
    @LOAD_REGISTERS(QID)

    return (br_q.flags & PL_Q_EXT_STATUS) != 0 ? PL_S_EXCEPTION : 0
end
