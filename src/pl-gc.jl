# UPSTREAM: swipl-devel src/pl-gc.c @ 18168e629eab
# UPSTREAM: swipl-devel src/pl-gc.h @ 18168e629eab
# CLASS: code
# COPYRIGHT: Copyright (c)  1985-2024, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
# PIN1 ledger (V10.1.20): structure only, d755bdc4 — pl-gc.c: cell-tag access behind pl-data.h macros, no change of value, order, error or side effect.
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
# DIVERGES (since L1f f1b; the collector hook is G1-GC's `considerGC` above, wired at `ensureGlobalSpace`'s audited sites only): no collector (`garbageCollect`) and no global or trail stack to grow —
# they grow on demand, so their callers (`allocGlobalNoShift`) were refused for the LIMIT, which growing
# cannot pass: the overflow is raised and false returned, as upstream's when `growStacks` fails. Upstream's
# first case — while an exception is processed, the stack's spare enabled — cannot arise: nothing is refused
# for the limit while one is processed (`ensureGlobalSpace`). A loop that calls it (`copy_term_refs`)
# therefore runs its body once more only upstream.
"Make room after `overflow`, or raise it and return false (pl-gc.c `makeMoreStackSpace`)."
function makeMoreStackSpace(ld::PL_local_data, overflow::boolex_t, flags::Int)::Bool
    return raiseStackOverflow(ld, overflow)
end

# ── the stack collector's safe-point hook (G1-GC, piece G1-2; docs/g1gc_safe_points.md) ─────────────
# PORT: pl-gc.c considerGarbageCollect
# DIVERGES: G1-GC placeholder — never wanted. G1-1 replaces the body with the scheduler (pl-gc.c:3834: the `gc` flag, `SIG_GC`, the stacks' sizes);
# until then only `ld.gc_force` (below) makes a collection due. `s` is upstream's `Stack s` (`nothing` = NULL: global or trail).
"Is a stack collection due (pl-gc.c `considerGarbageCollect`)? The placeholder: never."
considerGarbageCollect(ld::PL_local_data, s::Union{Nothing, Symbol}=nothing)::Bool = false

# PORT: pl-gc.c garbageCollect
# DIVERGES: G1-GC placeholder — there is no collector (G1-3 marks, G1-4 sweeps, G1-5 relocates, G1-6 drives it); it answers `BOOLEX_FALSE`, the
# answer upstream gives while the collector is blocked (`gc_status.blocked`): nothing moved, nothing freed. `reason` is a `GC_*` word.
"Run the stack garbage collector for `reason` (pl-gc.c `garbageCollect`); here it declines."
garbageCollect(ld::PL_local_data, reason::Int)::boolex_t = BOOLEX_FALSE

# ORIGINAL: the hook of a SAFE ALLOW_GC site (pl-gc.c:4707-4719 `f_ensureStackSpace`'s "consider, collect" half); `ensureGlobalSpace` calls it only
# when `flags & ALLOW_GC` and the area is full or `ld.gc_force` is set (the model of `FAKE_GC`, pl-vmi.c:238-251, never defined at the pin). Under
# `gc_force` it records `site` in `ld.gc_safe_hits` and collects; otherwise only `considerGarbageCollect` decides. True iff a collection ran.
"The safe-point hook: run the collector for `reason` at the audited `site` when `flags` allow it and one is due (or forced); true iff one ran."
function considerGC(ld::PL_local_data, flags::Int, reason::Int, site::Symbol)::Bool
    (flags & ALLOW_GC) == 0 && return false                 # G1-GC safe point: only a site that passed ALLOW_GC
    if ld.gc_force                                          # G1-GC safe point: FAKE_GC's model
        push!(ld.gc_safe_hits, site)
    elseif !considerGarbageCollect(ld, nothing)             # considerGarbageCollect(NULL)
        return false
    end
    return garbageCollect(ld, reason) == BOOLEX_TRUE        # garbageCollect(reason)
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
                0, ld.null_code, 0, nothing, nothing, 0, gen_t(0), 0x0, 0x0, UInt(0)
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
                word(0), false
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
# the ones the kernel declares — not `I_FEXITNDET`, `I_FREDO`, `A_FIRSTVAR_IS` (`I_EXITRESET` since LB4 b2).
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
        if c == I_EXIT || c == I_EXITFACT || c == I_EXITCATCH || c == I_EXITRESET ||
            c == I_EXITQUERY ||
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
        elseif c == B_ARG_CF || c == B_ARG_VF                   # the first variable is the third operand
            _setVar!(ld, base, Int(codes[pc + 3]))
        end
        pc += 1 + codeTable(c).arguments                       # stepPC(PC)
    end
end

# PORT: pl-gc.c pl_garbage_collect
# (FRG("$garbage_collect", 1, pl_garbage_collect, 0), pl-ext.c:168; pl-gc.c:4570-4584 at the pin. The
# Prolog `garbage_collect/0` is boot/syspred.pl:1423-1424: `garbage_collect :- '$garbage_collect'(0).`)
# DIVERGES: the body of `garbageCollect(GC_USER)` (pl-gc.c:4581) is not the kernel's — no stack garbage
# collection, so the call has nothing to do and succeeds. The debug level argument `d` is read only
# under `#if O_DEBUG` (pl-gc.c:4573-4579), which a release build of swipl does not define, so `d` is not examined.
"`'\$garbage_collect'(+DebugLevel)`: run the stack garbage collector (pl-gc.c); here there is none, so it succeeds."
function pl_garbage_collect(ld::PL_local_data{T}, d::term_t)::foreign_t where {T}
    return FTRUE
end

# ── the liveness walk of an environment (pl-gc.c), CONT1 C3 ──────────────────────────────────────
# PORT: pl-gc.c walk_state
# DIVERGES: only what the ACTIVE walk (`GCM_ACTIVE|GCM_CLEAR|GCM_CHOICE`, `mark_active_environment`)
# reads: the stack collector's fields (`envtop`, `unmarked`, `ARGP`, `adepth`, `MARK_ALT_CLAUSES`'s
# `GCM_ALTCLAUSE` and `mark_argp`) belong to the stack garbage collection the kernel does not have
# (above). `c0`, the start of the code list, is read by upstream's debug output only. The walk is on
# an INDEX into the clause's code (the opcode's position, as `clearUninitialisedVarsFrame`), and
# `arity` is `state->frame->predicate->functor->arity`. The flag word is not carried: the active walk always
# sets `GCM_ACTIVE|GCM_CLEAR|GCM_CHOICE`.
"The state of one `walk_and_mark` (pl-gc.c `walk_state`): the bit vectors `active` and `clear` (index `i` is bit `i+1`) and the arity of the frame's predicate."
struct walk_state
    arity::Int                                  # frame->predicate->functor->arity
    active::BitVector                           # bit_vector *active: variables read before they are written
    clear::BitVector                            # bit_vector *clear: variables (and choice slots) written first
end

# PORT: pl-gc.c mark_frame_var
# (the `state->active` branch; the other is the stack collector's)
"Variable operand `v` is read: it is active unless an earlier instruction cleared it (pl-gc.c `mark_frame_var`)."
@inline function mark_frame_var(state::walk_state, v::code)::Nothing
    i = VARNUM(v) + 1
    state.clear[i] || (state.active[i] = true)  # if ( !true_bit(state->clear, i) ) set_bit(state->active, i)
    return nothing
end

# PORT: pl-gc.c clear_frame_var
# (the `state->clear` branch; the `GCM_CLEAR` one writes the frame's cell, as the stack collector's)
"Variable operand `v` is written first here: it is not active before this point (pl-gc.c `clear_frame_var`)."
@inline function clear_frame_var(state::walk_state, v::code)::Nothing
    state.clear[VARNUM(v) + 1] = true           # set_bit(state->clear, i)
    return nothing
end

# PORT: pl-gc.c clear_choice_mark
"A choice-point slot is (re)made at operand `slot`: it is not active before this point (pl-gc.c; `GCM_CHOICE`)."
@inline function clear_choice_mark(state::walk_state, slot::code)::Nothing
    state.clear[VARNUM(slot) + 1] = true
    return nothing
end

# PORT: pl-gc.c mark_choice_mark
"A choice-point slot is read (a cut): it is active unless cleared since (pl-gc.c; `GCM_CHOICE`)."
@inline function mark_choice_mark(state::walk_state, slot::code)::Nothing
    i = VARNUM(slot) + 1
    state.clear[i] || (state.active[i] = true)
    return nothing
end

# PORT: pl-gc.c walk_and_mark
# DIVERGES: `pc` and the result are the INDEX of an opcode in `codes`, not a pointer past it, so an
# operand `PC[k]` is `codes[pc + 1 + k]`; the instructions are those the kernel declares, a literal
# operand is one word (`code_get_indirect`'s block is the table's `arguments`), and `D_BREAK`
# (`replacedBreak`) is left out (the debugger is deferred). Left to the stack collector: `mark_argp`,
# `adepth`, `GCM_ALTCLAUSE` (so the control constructs are always walked) and `I_FREDO`'s
# `mark_arguments`. A variable operand of `I_RATIONAL` is not marked, as upstream's list of the type
# tests has no `I_RATIONAL` (10.1.19).
"""
    walk_and_mark(state, codes, pc, end_op) -> Int

Walk the byte code of a clause from the instruction at `codes[pc]` to the first instruction `end_op`
(or the end of the code list), marking the variables read (`state.active`) and cleared (`state.clear`)
on the way, and return the index of the instruction it stopped at (pl-gc.c). The branches of the
control constructs are walked one after the other: `mark_frame_var` after a `clear` of the same
variable in an earlier instruction of the SAME path does not mark it.
"""
function walk_and_mark(state::walk_state, codes::Vector{code}, pc::Int, end_op::code)::Int
    while true
        op = codes[pc]
        op == end_op && return pc                   # if ( op == end ) { PC--; return PC; }
        if op == I_EXITQUERY || op == I_EXITFACT || op == I_FCALLDETVA ||
            op == I_FEXITDET ||
            op == I_FEXITNDET || op == S_TRUSTME || op == S_LIST || op == I_FREDO
            return pc                               # return PC-1 (I_FREDO: mark_arguments is the collector's)
        elseif op == C_JMP || op == L_NOLCO         # unconditional jump
            pc += Int(codes[pc + 1]) + 2
            continue
        elseif op == C_OR
            alt = pc + Int(codes[pc + 1]) + 2       # Code alt = PC+PC[0]+1
            walk_and_mark(state, codes, pc + 2, C_JMP)  # PC++; walk_and_mark(state, PC, C_JMP)
            pc = alt
            continue
        elseif op == C_NOT || op == C_DET
            alt = pc + Int(codes[pc + 2]) + 3       # Code alt = PC+PC[1]+2
            ec = op == C_NOT ? C_CUT : C_DETTRUE
            clear_choice_mark(state, codes[pc + 1])
            walk_and_mark(state, codes, pc + 3, ec) # PC += 2: skip the two arguments
            pc = alt
            continue
        elseif op == C_SOFTIF || op == C_IFTHENELSE || op == C_FASTCOND
            alt = pc + Int(codes[pc + 2]) + 3
            clear_choice_mark(state, codes[pc + 1])
            walk_and_mark(state, codes, pc + 3, C_JMP)  # skip the 'MARK' variable and jmp
            pc = alt
            continue
        elseif op == C_IFTHEN || op == C_SOFTIFTHEN
            clear_choice_mark(state, codes[pc + 1])
            pc = walk_and_mark(state, codes, pc + 2, C_END) + 1     # PC++: skip C_END
            continue
        elseif op == C_CUT || op == C_LSCUT || op == C_LCUT || op == C_SOFTCUT ||
            op == C_LCUTIFTHEN || op == C_FASTCUT || op == C_DETTRUE
            mark_choice_mark(state, codes[pc + 1])
        elseif op == B_UNIFY_VAR                    # Var = Term
            mark_frame_var(state, codes[pc + 1])
        elseif op == B_UNIFY_FIRSTVAR || op == B_FIRSTVAR || op == B_ARGFIRSTVAR ||
            op == B_UNIFY_FC || op == C_VAR || op == H_FIRSTVAR
            clear_frame_var(state, codes[pc + 1])
        elseif op == C_VAR_N
            var = codes[pc + 1]
            for _ in 1:Int(codes[pc + 2])           # while(count--) clear_frame_var(state, var++, PC)
                clear_frame_var(state, var)
                var += code(1)
            end
        elseif op == H_LIST_FF || op == B_UNIFY_FF
            clear_frame_var(state, codes[pc + 1])
            clear_frame_var(state, codes[pc + 2])
        elseif op == A_ADD_FC || op == B_UNIFY_FV || op == B_UNIFY_VF
            clear_frame_var(state, codes[pc + 1])
            mark_frame_var(state, codes[pc + 2])
        elseif op == B_UNIFY_VV || op == B_EQ_VV || op == B_NEQ_VV
            mark_frame_var(state, codes[pc + 1])
            mark_frame_var(state, codes[pc + 2])
        elseif op == B_ARG_VF || op == B_ARG_CF
            op == B_ARG_VF && mark_frame_var(state, codes[pc + 1])
            mark_frame_var(state, codes[pc + 2])
            clear_frame_var(state, codes[pc + 3])
        elseif op == I_VAR || op == I_NONVAR || op == I_INTEGER || op == I_FLOAT ||
            op == I_NUMBER || op == I_ATOMIC || op == I_ATOM || op == I_STRING ||
            op == I_COMPOUND || op == I_CALLABLE || op == I_CALLCONT || op == I_SHIFT ||
            op == I_SHIFTCP || op == H_VAR || op == B_UNIFY_VC || op == B_EQ_VC ||
            op == B_NEQ_VC || op == B_ARGVAR || op == B_VAR
            mark_frame_var(state, codes[pc + 1])
        elseif op == B_VAR0
            mark_frame_var(state, VAROFFSET(0))
        elseif op == B_VAR1
            mark_frame_var(state, VAROFFSET(1))
        elseif op == B_VAR2
            mark_frame_var(state, VAROFFSET(2))
        elseif op == I_CALLCLEANUP
            arg_goal = state.arity == 2 ? 1 : 2
            mark_frame_var(state, VAROFFSET(arg_goal - 1))          # main goal
        elseif op == I_EXITCLEANUP
            if state.arity == 5                     # '$tbl_leader'/5: C cleanup uses all args
                for i in 0:(state.arity - 1)
                    mark_frame_var(state, VAROFFSET(i))
                end
            else
                state.arity == 4 && mark_frame_var(state, VAROFFSET(state.arity - 2))   # The ball
                mark_frame_var(state, VAROFFSET(state.arity - 1))   # cleanup goal
            end
        elseif op == I_EXITRESET || op == I_EXITCATCH
            if op == I_EXITRESET && state.arity == 6    # '$tbl_reset'/6: worklist, skeleton, delays
                for i in 3:5
                    mark_frame_var(state, VAROFFSET(i))
                end
            end
            mark_frame_var(state, VAROFFSET(1))     # The ball
            mark_frame_var(state, VAROFFSET(2))     # recovery goal
        elseif op == I_CUTCHP
            mark_frame_var(state, VAROFFSET(1))     # choice-point
        elseif op == I_CALLATMV || op == I_DEPARTATMV
            mark_frame_var(state, codes[pc + 2])
        end
        pc += 1 + codeTable(op).arguments
    end
end

# PORT: pl-gc.c mark_active_environment
# DIVERGES: `active` is a `BitVector` the caller sizes (`sizeof_bitvector`, `init_bitvector`); the
# cleared set is a second one made here; `pc` is the index of the instruction the frame resumes at
# in `codes` (upstream: `fr->clause->value.clause->codes` and a pointer into it).
"""
    mark_active_environment(ld, active, fr, codes, pc)

Set bit `i+1` of `active` for each variable slot `i` of frame `fr` whose value the code from the
instruction at `codes[pc]` to the clause's `I_EXIT` still reads (pl-gc.c): the environment a
continuation has to keep (`put_environment`, pl-cont.c).
"""
function mark_active_environment(
    ld::PL_local_data{T}, active::BitVector, fr::Int, codes::Vector{code}, pc::Int
)::Nothing where {T}
    state = walk_state(
        (ld.frames[fr].predicate::Definition{T}).arity, active, falses(length(active))
    )
    walk_and_mark(state, codes, pc, I_EXIT)
    return nothing
end
