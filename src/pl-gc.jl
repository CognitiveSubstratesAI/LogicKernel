# UPSTREAM: swipl-devel src/pl-gc.c @ cbf4e1896275
# UPSTREAM: swipl-devel src/pl-gc.h @ cbf4e1896275
# CLASS: code
# COPYRIGHT: Copyright (c)  1985-2024, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# What the kernel takes from SWI-Prolog's garbage collector (pl-gc.c, pl-gc.h): finding the
# generations the predicates are being executed in, for clause GC, growing the local stack, and
# (since V9f) `clearUninitialisedVarsFrame`. Stack garbage collection and stack shifting are not
# the kernel's.

# PORT: pl-gc.c markPredicatesInEnvironments
# DIVERGES: walks the live FRAME RECORDS where upstream scans every word of the local stack below
# `lTop` for a frame (`isFrame`) — the records are the frames. No transactions, so no transaction
# start to record; the `erased_skipped` statistic is not kept. Then, as upstream, the predicates
# referenced explicitly (`markAccessedPredicates`): clause/2 and retract/1 (foreign predicates since
# NF2, and their sinks) reference theirs with `pushPredicateAccessObj!`.
"Record the generations every predicate is being run or accessed in, for clause GC (pl-gc.c)."
function markPredicatesInEnvironments!(
    ld::PL_local_data{T}, gd::PL_global_data{T}
)::Nothing where {T}
    lend = ld.lTop                                  # see (*): frames are never written above lTop
    for i in 1:ld.nframes
        fr = ld.frames[i]
        if fr.base < lend && isFrame(fr)
            def = fr.predicate
            if def !== nothing
                ddi = get(gd.procedures_dirty, def, nothing)
                if ddi !== nothing
                    gen = generationFrame(fr)
                    ddi_add_access_gen!(ddi, gen)
                end
            end
        end
    end

    markAccessedPredicates!(ld, gd)
    return nothing
end

# PORT: pl-gc.c makeMoreStackSpace
# DIVERGES (since L1f f1b): no collector (`garbageCollect`, `ALLOW_GC`) and no global or trail stack to grow —
# they grow on demand, so their callers (`allocGlobalNoShift`) were refused for the LIMIT, which growing
# cannot pass: the overflow is raised and false returned, as upstream's when `growStacks` fails. Upstream's
# first case — while an exception is processed, the stack's spare enabled — cannot arise: nothing is refused
# for the limit while one is processed (`ensureGlobalSpace`). A loop that calls it (`copy_term_refs`)
# therefore runs its body once more only upstream.
"Make room after `overflow`, or raise it and return false (pl-gc.c `makeMoreStackSpace`)."
function makeMoreStackSpace(ld::PL_local_data, overflow::boolex_t, flags::Int)::Bool
    return raiseStackOverflow(ld, overflow)
end

# PORT: pl-gc.c growStacks as growStacks!
# DIVERGES: grows the local stack only — there is no global, trail or argument stack of fixed
# size — and moves nothing: positions are offsets and records are indices, so upstream's work here,
# shifting the stacks and relocating every pointer into them, does not exist. The size doubles until
# the request fits with the spare above it (`include_spare_stack`), within what `stacks_limit` leaves
# after the global stack and the trail (`tsize + gsize + lsize`, since L1f f2: audit D-0036); while an
# exception is processed the limit is raised to the need plus 1 MiB (`grow_stacks`' error condition,
# in positions; since V5d). Past the limit nothing grows, and the caller's re-check reports the
# overflow, as upstream's does when `grow_stacks` refuses. After growing, the spare is reserved again
# at the top (`reenable_spare_stack`: the room is at least the spare, so `trim_stack`).
"Grow the local stack so `l` more positions fit above `lTop` (pl-gc.c `growStacks`)."
function growStacks!(ld::PL_local_data{T}, l::Int)::Nothing where {T}
    need = ld.lTop + l
    need <= ld.lMax && return nothing
    want = need + ld.local_def_spare                # include_spare_stack: the spare on top
    size = max(ld.lMax + ld.local_spare, 1)
    while size < want
        size *= 2
    end
    limit =
        ld.stacks_limit -                       # one limit over the three stacks (L1f f2), with
        (ld.gTop + ld.global_spare + length(ld.trail) + ld.trail_spare)   # their spares (f1b)
    if size > limit && ld.exception_processing      # in error condition: raising limit with 1Mb
        limit = max(limit, want + EMERGENCY_LIMIT)
    end
    size = min(size, limit)
    size < want && return nothing
    _resize_local!(ld, size)
    ld.lMax = size                                  # include_spare_stack: max += spare
    ld.local_spare = 0
    trim_stack!(ld)                                 # reenable_spare_stack
    return nothing
end

# PORT: pl-gc.c growStacks as growStacks_trim!
# DIVERGES (since L1f f1b, audit D-0049): upstream's GROW_TRIM request (trimStacks(resize), after an overflow) alone.
# The global stack and the trail are sized by their use here, so only their spares take part — included
# (`include_spare_stack`: the spare released) and re-reserved (`reenable_spare_stack`: `trim_stack`). The local
# stack shrinks to `nextStackSize(s, GROW_TRIM)`: the next size above its use, `min_free` (LOCAL_MARGIN) and
# its spare, as a power of two of at least SMALLSTACK (4096 positions, LOCAL_INITIAL), never above its size;
# its cells are kept (`_resize_local!` frees nothing) — `lMax` and the spare are its size in the limit. A local
# stack with less room than its spare is GROWN by it instead (`include_spare_stack`'s request), `growStacks!`.
"Shrink the stacks to their use after an overflow, their spares reserved again (pl-gc.c `growStacks(GROW_TRIM, …)`)."
function growStacks_trim!(ld::PL_local_data)::Nothing
    ld.global_spare = 0                             # include_spare_stack(global)
    ld.trail_spare = 0                              # include_spare_stack(trail)
    size = ld.lMax + ld.local_spare                 # include_spare_stack(local): max += spare
    ld.lMax = size
    ld.local_spare = 0
    if size - ld.lTop < ld.local_def_spare          # roomStackP(s) < s->def_spare: request = def_spare
        growStacks!(ld, ld.local_def_spare)
    else
        n = ld.lTop + LOCAL_MARGIN + ld.local_def_spare     # usedStackP(s) + s->min_free + s->def_spare
        new = max(2 << MSB64(Int64(n)), LOCAL_INITIAL)      # nextStackSizeAbove(n): SMALLSTACK at least
        ld.lMax = min(new, size)                    # never above the stack's size
    end
    trim_stack_trail!(ld)                           # reenable_spare_stack(trail)
    trim_stack_global!(ld)                          # … (global)
    trim_stack!(ld)                                 # … (local)
    return nothing
end

# gc:5384 the room an exception being processed may take past the limit: 1 MiB, in positions.
"How far past `stacks_limit` the local stack grows while an exception is processed (pl-gc.c)."
const EMERGENCY_LIMIT = (1024 * 1024) ÷ 8

"Make the cells and the record pools of the local stack hold `size` positions."
function _resize_local!(ld::PL_local_data{T}, size::Int)::Nothing where {T}
    n = length(ld.slots)
    if n < size                                     # never read before they are written: the
        resize!(ld.slots, size)                     # words start as 0, which the readers refuse
        resize!(ld.slot_values, size)
        fill!(view(ld.slots, (n + 1):size), word(0))
    end
    _grow_pool!(ld, ld.frames, cld(size, SIZEOF_LOCALFRAME))
    _grow_pool!(ld, ld.choices, cld(size, SIZEOF_CHOICE))
    _grow_pool!(ld, ld.fliframes, cld(size, SIZEOF_FLIFRAME))
    _grow_pool!(ld, ld.queries, cld(size, SIZEOF_QUERYFRAME))
    return nothing
end

# A record pool holds as many records as fit in the stack's positions: records of one kind never
# overlap, so pushing one never allocates.
function _grow_pool!(
    ld::PL_local_data{T}, pool::Vector{localFrame{T}}, n::Int
)::Nothing where {T}
    while length(pool) < n
        push!(
            pool,
            localFrame{T}(
                0, ld.null_code, 0, nothing, nothing, gen_t(0), 0x0, 0x0, UInt(0)
            )
        )
    end
    return nothing
end
function _grow_pool!(
    ld::PL_local_data{T}, pool::Vector{choice{T}}, n::Int
)::Nothing where {T}
    while length(pool) < n
        push!(
            pool,
            choice{T}(
                0, CHP_JUMP, 0, mark(0, 0, 0), 0, ClauseChoice{T}(nothing, word(0)), 0,
                false
            )
        )
    end
    return nothing
end
function _grow_pool!(::PL_local_data, pool::Vector{fliFrame}, n::Int)::Nothing
    while length(pool) < n
        push!(pool, fliFrame(0, 0, 0, 0, mark(0, 0, 0)))
    end
    return nothing
end
function _grow_pool!(
    ld::PL_local_data{T}, pool::Vector{queryFrame{T}}, n::Int
)::Nothing where {T}
    while length(pool) < n
        push!(
            pool,
            queryFrame{T}(
                0, UInt(0), 0, argp_t{T}(ARGP_SLOT, 0, ld.placeholder), ld.null_code, 0, 0,
                0,
                UInt32(0), 0, 0, 0, 0, 0, 0, 0, 0, 0,
                foreign_context{T}(FRG_FIRST_CALL, UInt(0), nothing)
            )
        )
    end
    return nothing
end

# PORT: pl-gc.c growLocalSpace
# DIVERGES: `n` is in positions, where upstream's is in bytes; the spare is enabled while an
# exception is processed (since V5d), not while GC runs (no stack garbage collector until G1).
"Make room for `n` positions above `lTop`, growing the stack if `flags` allows (pl-gc.c)."
function growLocalSpace(ld::PL_local_data{T}, n::Int, flags::Int)::boolex_t where {T}
    if ld.lTop + n <= ld.lMax                   # addPointer(lTop, bytes) <= (void*)lMax
        return BOOLEX_TRUE
    end
    if ld.exception_processing                  # || LD->gc.status.active
        enableSpareStack!(ld, true)
        if ld.lTop + n <= ld.lMax
            return BOOLEX_TRUE
        end
    end
    if flags == 0
        @goto nospace
    end
    growStacks!(ld, n)
    if ld.lTop + n <= ld.lMax
        return BOOLEX_TRUE
    end
    @label nospace
    return LOCAL_OVERFLOW
end

# PORT: pl-gc.h ensureLocalSpace_ex as ensureLocalSpace
# DIVERGES: `n` is in positions.
"Make room for `n` positions above `lTop`, or raise the overflow (pl-gc.h)."
function ensureLocalSpace(ld::PL_local_data{T}, n::Int)::Bool where {T}
    if hasLocalSpace(ld, n)
        return true
    end
    if (rc = growLocalSpace(ld, n, ALLOW_SHIFT)) == BOOLEX_TRUE
        return true
    end
    return raiseStackOverflow(ld, rc)
end

"Make the cell at offset `n` of the frame at `base` a variable (`setVar(varFrame(fr, n))`)."
function _setVar!(ld::PL_local_data{T}, base::Int, n::Int)::Nothing where {T}
    _slot_new_var!(ld, varFrameP(base, n) + 1)
    return nothing
end

# PORT: pl-gc.c clearUninitialisedVarsFrame
# DIVERGES: `PC` is the clause's code and an index into it; a cell is set to a FRESH variable, where
# upstream's `setVar` makes the cell itself the variable (decision 2). The instructions walked are
# the ones the kernel declares — not `I_EXITRESET`, `I_FEXITNDET`, `I_FREDO`, `A_FIRSTVAR_IS`,
# `B_ARG_CF`, `B_ARG_VF`.
"""
    clearUninitialisedVarsFrame(ld, fr, codes, pc)

Assuming frame `fr`'s clause resumes at `codes[pc]`, set the variables the code from there still
has to initialise to variables (pl-gc.c): what reads the frame meanwhile — the decompiler of
`det_goal_error` — then finds no stale cell.
"""
function clearUninitialisedVarsFrame(
    ld::PL_local_data{T}, fr::Int, codes::Vector{code}, pc::Int
)::Nothing where {T}
    base = ld.frames[fr].base
    while true
        c = codes[pc]
        while c == C_JMP || c == L_NOLCO                        # jumps
            pc += Int(codes[pc + 1]) + 2
            c = codes[pc]
        end
        if c == I_EXIT || c == I_EXITFACT || c == I_EXITCATCH || c == I_EXITQUERY ||
            c == I_FEXITDET || c == I_FCALLDETVA || c == S_TRUSTME || c == S_LIST
            return nothing                                      # terminate code list
        elseif c == H_FIRSTVAR || c == B_FIRSTVAR || c == B_ARGFIRSTVAR ||
            c == B_UNIFY_FIRSTVAR || c == C_VAR                 # Firstvar assignments
            _setVar!(ld, base, Int(codes[pc + 1]))
        elseif c == C_VAR_N
            var = Int(codes[pc + 1])
            for i in 0:(Int(codes[pc + 2]) - 1)
                _setVar!(ld, base, var + i)
            end
        elseif c == H_LIST_FF || c == B_UNIFY_FF
            _setVar!(ld, base, Int(codes[pc + 1]))
            _setVar!(ld, base, Int(codes[pc + 2]))
        elseif c == B_UNIFY_FV || c == B_UNIFY_VF || c == B_UNIFY_FC || c == A_ADD_FC
            _setVar!(ld, base, Int(codes[pc + 1]))
        end
        pc += 1 + codeTable(c).arguments                        # stepPC(PC)
    end
end
