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

# ── the stack invariant checker (G1-GC piece G1-9) ───────────────────────────────────────────────
# PORT: pl-gc.c checkStacks as check_stacks!
# DIVERGES: not a transliteration. Upstream's `checkStacks` (compiled under `O_DEBUG`/`O_MAINTENANCE` only, the
# `HAVE_CHECK_STACKS` block of pl-gc.c:3912-4310) walks the frames from the VM state, `checkData`s every argument,
# variable and foreign-frame term reference it reaches and sums a key; the kernel has no pointers to follow and its
# words are its own (`pl-data.h` tags over POSITIONS, `ORIGINAL` value-table words), so this checks the INVARIANTS the
# collector will rely on, over the kernel's representation, and reports every violation as text instead of asserting
# the first: the cells of the global stack (tag, storage, range, compound heads and their arities, reference chains,
# the value table's boxes, MARK/FIRST bits), the trail's entries, the attributed-variable chain, the frame, choice,
# foreign-frame and query records. The local stack's WORDS are not scanned: a frame's variable cells hold stale words
# until their first write (`clearUninitialisedVarsFrame`), which no invariant over the words can tell from a corrupt
# one; the collector's own mark phase (G1-3) reads the live ones. The `key` upstream returns is the number of cells
# checked here. The record pools are checked in their live ranges (`frames[1:nframes]`, …).
"""
    StackInvariantError(violations)

A stack invariant failed (`check_stacks!`): the report, one text per violation, each starting with the check's
name in brackets (`[gstack-tag]`, `[gstack-ref-cycle]`, …).
"""
struct StackInvariantError <: Exception
    violations::Vector{String}
end
function Base.showerror(io::IO, e::StackInvariantError)
    print(io, "StackInvariantError: ", length(e.violations), " violation(s):")
    for v in e.violations
        print(io, "\n  ", v)
    end
    return nothing
end

# ORIGINAL: how many violations a report keeps; the rest are counted.
"The most violations one `stack_violations` report lists."
const STACK_CHECK_MAX_REPORT = 64

# ORIGINAL: the report of one check run.
mutable struct stack_report
    msgs::Vector{String}                        # the violations, `[check] where: what`
    dropped::Int                                # violations past `STACK_CHECK_MAX_REPORT`
    cells::Int                                  # cells and records examined (upstream's `key`, as a count)
end
stack_report() = stack_report(String[], 0, 0)

function _viol!(r::stack_report, check::String, msg::String)::Nothing
    if length(r.msgs) < STACK_CHECK_MAX_REPORT
        push!(r.msgs, string("[", check, "] ", msg))
    else
        r.dropped += 1
    end
    return nothing
end

_hexw(w::word)::String = string("0x", string(w; base=16, pad=16))

# ORIGINAL: the arity of functor word `w`, -1 when the functor table does not hold it (a corrupt word).
function _functor_arity_checked(ld::PL_local_data, w::word)::Int
    a = _arityFunc_(w)
    a != F_ARITY_MASK && return a
    return try
        arityFunctor(ld.functors, w)
    catch
        -1
    end
end

# ORIGINAL: one word of a global cell (not a functor head): its tag, storage, range and mark bits.
function _check_global_word!(
    r::stack_report, ld::PL_local_data, p::Int, w0::word, allow_marks::Bool
)::Nothing
    w = w0
    if (w & BOTH_MASK) != 0
        allow_marks || _viol!(
            r, "gstack-mark",
            string("global[", p, "] = ", _hexw(w0), ": MARK/FIRST bit set outside a collection")
        )
        w &= ~BOTH_MASK
    end
    gtop = ld.gTop
    te = tagex(w)
    if w == word(0)                                         # an unbound variable (`setVar`)
        return nothing
    elseif te == (TAG_ATOM | STG_STATIC) || te == (TAG_INTEGER | STG_INLINE)
        return nothing                                      # an atom, a tagged small integer
    elseif te == (TAG_REFERENCE | STG_GLOBAL)
        q = valPtr(w)
        if q < 1 || q > gtop
            _viol!(
                r, "gstack-ref-range",
                string("global[", p, "] = ", _hexw(w0), ": reference to ", q, " outside 1..", gtop)
            )
        end
    elseif te == (TAG_ATTVAR | STG_GLOBAL)
        q = valPtr(w)
        if q < 1 || q > gtop
            _viol!(
                r, "gstack-ref-range",
                string("global[", p, "] = ", _hexw(w0), ": attributed variable pointer ", q,
                    " outside 1..", gtop)
            )
        end
    elseif te == (TAG_COMPOUND | STG_GLOBAL)
        q = valPtr(w)
        if q < 1 || q > gtop
            _viol!(
                r, "gstack-compound",
                string("global[", p, "] = ", _hexw(w0), ": compound at ", q, " outside 1..", gtop)
            )
        else
            f = ld.gstack[q]
            if !isFunctor(f & ~BOTH_MASK)
                _viol!(
                    r, "gstack-compound",
                    string("global[", p, "] = ", _hexw(w0), ": compound at ", q,
                        " whose cell ", _hexw(f), " is not a functor word")
                )
            end
        end
    elseif te == (TAG_COMPOUND | STG_RESERVED)             # a value-table word
        i = valPtr(w)
        if i < 1 || i > length(ld.vtable)
            _viol!(
                r, "gstack-vword",
                string("global[", p, "] = ", _hexw(w0), ": value-table entry ", i,
                    " outside 1..", length(ld.vtable))
            )
        end
    elseif te == (TAG_ATOM | STG_GLOBAL)
        _viol!(
            r, "gstack-functor",
            string("global[", p, "] = ", _hexw(w0), ": a functor word where an argument cell is expected")
        )
    else
        _viol!(
            r, "gstack-tag",
            string("global[", p, "] = ", _hexw(w0), ": tag/storage ", string(te; base=2),
                " is no tag a global cell holds")
        )
    end
    return nothing
end

# ORIGINAL: the global stack's cells, compound by compound.
function _check_global_cells!(
    r::stack_report, ld::PL_local_data, allow_marks::Bool
)::Nothing
    gtop = ld.gTop
    if gtop < 0 || gtop > length(ld.gstack)
        _viol!(r, "gstack-top", string("gTop = ", gtop, " outside 0..", length(ld.gstack)))
        return nothing
    end
    p = 1
    while p <= gtop
        w0 = ld.gstack[p]
        w = w0 & ~BOTH_MASK
        r.cells += 1
        if isFunctor(w)                                     # a compound's head: its arguments follow
            (w0 & BOTH_MASK) != 0 && !allow_marks && _viol!(
                r, "gstack-mark",
                string("global[", p, "] = ", _hexw(w0), ": MARK/FIRST bit set on a functor cell outside a collection")
            )
            n = _functor_arity_checked(ld, w)
            if n < 0
                _viol!(
                    r, "gstack-functor-arity",
                    string("global[", p, "] = ", _hexw(w0), ": functor not in the functor table")
                )
                p += 1
            elseif p + n > gtop
                _viol!(
                    r, "gstack-functor-arity",
                    string("global[", p, "] = ", _hexw(w0), ": arity ", n, " runs past gTop = ", gtop)
                )
                p += 1
            else
                for i in 1:n
                    _check_global_word!(r, ld, p + i, ld.gstack[p + i], allow_marks)
                    r.cells += 1
                end
                p += n + 1
            end
        else
            _check_global_word!(r, ld, p, w0, allow_marks)
            p += 1
        end
    end
    return nothing
end

# ORIGINAL: the reference chains are acyclic. Each chain is followed once (`state`: 0 new, 1 on the
# chain being followed, 2 known to end); a one-cell chain (a cell referencing itself) is the unbound
# variable of upstream and passes.
function _check_ref_chains!(r::stack_report, ld::PL_local_data)::Nothing
    gtop = ld.gTop
    (gtop < 1 || gtop > length(ld.gstack)) && return nothing
    state = zeros(UInt8, gtop)
    path = Int[]
    for start in 1:gtop
        state[start] == 0x00 || continue
        empty!(path)
        p = start
        while true
            w = ld.gstack[p] & ~BOTH_MASK
            if !(tagex(w) == (TAG_REFERENCE | STG_GLOBAL))  # the chain ends at a non-reference
                break
            end
            q = valPtr(w)
            if q < 1 || q > gtop                            # (reported by the cell check)
                break
            end
            if q == p                                       # self-reference: an unbound variable
                break
            end
            if state[p] == 0x02
                break
            end
            if state[p] == 0x01
                _viol!(
                    r, "gstack-ref-cycle",
                    string("global[", p, "]: reference chain from ", start, " returns to a cell on it")
                )
                break
            end
            state[p] = 0x01
            push!(path, p)
            p = q
        end
        for c in path
            state[c] = 0x02
        end
        state[p] == 0x00 && (state[p] = 0x02)
    end
    return nothing
end

# ORIGINAL: the value table's boxes: one per entry, ascending, each the entry's own word.
function _check_vbox!(r::stack_report, ld::PL_local_data)::Nothing
    nv = length(ld.vtable)
    if length(ld.vbox) != nv
        _viol!(r, "vbox", string("length(vbox) = ", length(ld.vbox), " but length(vtable) = ", nv))
        return nothing
    end
    gtop = ld.gTop
    prev = 0
    for i in 1:nv
        b = ld.vbox[i]
        r.cells += 1
        if b < 1 || b > gtop || b > length(ld.gstack)
            _viol!(r, "vbox", string("vbox[", i, "] = ", b, " outside 1..", gtop))
            continue
        end
        if b <= prev
            _viol!(r, "vbox", string("vbox[", i, "] = ", b, " not above vbox[", i - 1, "] = ", prev))
        end
        prev = b
        want = consPtr(i, TAG_COMPOUND | STG_RESERVED)
        got = ld.gstack[b] & ~BOTH_MASK
        if got != want
            _viol!(
                r, "vbox",
                string("global[", b, "] = ", _hexw(ld.gstack[b]), " is not the box word ", _hexw(want),
                    " of value-table entry ", i)
            )
        end
    end
    return nothing
end

# ORIGINAL: the trail: address entries name cells of the global stack, a value entry follows an
# address entry and names the saved old value above it (`TrailAssignment!`).
function _check_trail!(r::stack_report, ld::PL_local_data)::Nothing
    gtop = ld.gTop
    tr = ld.trail
    for i in 1:length(tr)
        e = tr[i]
        r.cells += 1
        if isTrailVal(e)
            p = trailValP(e)
            if i == 1 || isTrailVal(tr[i - 1])
                _viol!(r, "trail", string("trail[", i, "] = ", _hexw(e), ": a value entry not above an address entry"))
            end
            if p < 1 || p > gtop
                _viol!(r, "trail", string("trail[", i, "] = ", _hexw(e), ": saved value at ", p, " outside 1..", gtop))
            elseif i > 1 && !isTrailVal(tr[i - 1]) && p <= _trail_pos(tr[i - 1])
                _viol!(
                    r, "trail",
                    string("trail[", i, "] = ", _hexw(e), ": saved value at ", p,
                        " not above its cell ", _trail_pos(tr[i - 1]))
                )
            end
        else
            if _trail_stack(e) != TRAIL_GLOBAL
                _viol!(r, "trail", string("trail[", i, "] = ", _hexw(e), ": stack code ", _trail_stack(e), " names no stack here"))
                continue
            end
            p = _trail_pos(e)
            if p < 1 || p > gtop
                _viol!(r, "trail", string("trail[", i, "] = ", _hexw(e), ": cell ", p, " outside 1..", gtop))
            end
        end
    end
    return nothing
end

# ORIGINAL: the chain of attributed variables: each link cell is unbound (the end) or a reference to an older link.
function _check_attvar_chain!(r::stack_report, ld::PL_local_data)::Nothing
    gtop = ld.gTop
    p = ld.attvar_attvars
    steps = 0
    while p != 0
        r.cells += 1
        if p < 1 || p > gtop
            _viol!(r, "attvar-chain", string("link ", p, " outside 1..", gtop))
            return nothing
        end
        steps += 1
        if steps > gtop + 1
            _viol!(r, "attvar-chain", "the chain does not end")
            return nothing
        end
        w = ld.gstack[p] & ~BOTH_MASK
        if isVar(w)
            return nothing
        elseif tagex(w) == (TAG_REFERENCE | STG_GLOBAL) && valPtr(w) < p
            p = valPtr(w)
        else
            _viol!(
                r, "attvar-chain",
                string("link cell global[", p, "] = ", _hexw(ld.gstack[p]),
                    " is neither unbound nor a reference to an older link")
            )
            return nothing
        end
    end
    return nothing
end

# ORIGINAL: the record pools of the local stack and the registers into them.
function _check_local_records!(
    r::stack_report, ld::PL_local_data{T}
)::Nothing where {T}
    ltop = ld.lTop
    if ltop < 0 || ltop > length(ld.slots)
        _viol!(r, "lstack-top", string("lTop = ", ltop, " outside 0..", length(ld.slots)))
    end
    if ld.aTop < 0 || ld.aTop > length(ld.astack)
        _viol!(r, "astack-top", string("aTop = ", ld.aTop, " outside 0..", length(ld.astack)))
    end
    gtop = ld.gTop
    ntr = length(ld.trail)
    if ld.frozen_bar < 0 || ld.frozen_bar > gtop
        _viol!(r, "frozen-bar", string("frozen_bar = ", ld.frozen_bar, " outside 0..", gtop))
    end
    # the pools: live records in base order; a frame still being filled may lie at or above lTop
    nf = ld.nframes
    if nf < 0 || nf > length(ld.frames)
        _viol!(r, "frame", string("nframes = ", nf, " outside 0..", length(ld.frames)))
        nf = 0
    end
    for i in 1:nf
        fr = ld.frames[i]
        r.cells += 1
        fr.base < 1 && _viol!(r, "frame", string("frames[", i, "].base = ", fr.base, " is below the stack"))
        i > 1 && fr.base <= ld.frames[i - 1].base && _viol!(
            r, "frame", string("frames[", i, "].base = ", fr.base, " not above frames[", i - 1, "]")
        )
        i < nf && fr.base >= ltop && _viol!(
            r, "frame", string("frames[", i, "].base = ", fr.base, " at or above lTop = ", ltop)
        )
        if isFrame(fr) && (fr.parent < 0 || fr.parent >= i)  # a killed frame's links are stale
            _viol!(r, "frame", string("frames[", i, "].parent = ", fr.parent, ": not an older frame"))
        end
    end
    nc = ld.nchoices
    if nc < 0 || nc > length(ld.choices)
        _viol!(r, "choice", string("nchoices = ", nc, " outside 0..", length(ld.choices)))
        nc = 0
    end
    for i in 1:nc
        c = ld.choices[i]
        r.cells += 1
        i > 1 && c.base <= ld.choices[i - 1].base && _viol!(
            r, "choice", string("choices[", i, "].base = ", c.base, " not above choices[", i - 1, "]")
        )
        c.base >= ltop && _viol!(
            r, "choice", string("choices[", i, "].base = ", c.base, " at or above lTop = ", ltop)
        )
    end
    # the chain from BFR: older records, older marks, marks within the stacks
    ch = ld.BFR
    if ch < 0 || ch > nc
        _viol!(r, "choice", string("BFR = ", ch, " outside 0..", nc))
    else
        prev = nothing
        steps = 0
        while ch != 0
            c = ld.choices[ch]
            steps += 1
            if steps > nc + 1
                _viol!(r, "choice", "the choice-point chain does not end")
                break
            end
            if c.unlinked
                _viol!(r, "choice", string("choices[", ch, "] is on the chain but marked unlinked"))
            end
            if c.frame < 0 || c.frame > nf
                _viol!(r, "choice", string("choices[", ch, "].frame = ", c.frame, " outside 0..", nf))
            end
            if c.mark.trailtop != NOT_A_MARK
                if c.mark.globaltop < 0 || c.mark.globaltop > gtop
                    _viol!(
                        r, "choice-mark",
                        string("choices[", ch, "].mark.globaltop = ", c.mark.globaltop, " above gTop = ", gtop)
                    )
                end
                if c.mark.trailtop < 0 || c.mark.trailtop > ntr
                    _viol!(
                        r, "choice-mark",
                        string("choices[", ch, "].mark.trailtop = ", c.mark.trailtop, " above the trail's ", ntr)
                    )
                end
                if prev !== nothing && prev.mark.trailtop != NOT_A_MARK &&
                    (c.mark.globaltop > prev.mark.globaltop || c.mark.trailtop > prev.mark.trailtop)
                    _viol!(
                        r, "choice-mark",
                        string("choices[", ch, "]'s mark is above the newer choice point's")
                    )
                end
            end
            if c.parent < 0 || c.parent >= ch
                _viol!(r, "choice", string("choices[", ch, "].parent = ", c.parent, ": not an older choice point"))
                break
            end
            prev = c
            ch = c.parent
        end
    end
    nfl = ld.nfliframes
    if nfl < 0 || nfl > length(ld.fliframes)
        _viol!(r, "fliframe", string("nfliframes = ", nfl, " outside 0..", length(ld.fliframes)))
        nfl = 0
    end
    for i in 1:nfl
        f = ld.fliframes[i]
        r.cells += 1
        i > 1 && f.base <= ld.fliframes[i - 1].base && _viol!(
            r, "fliframe", string("fliframes[", i, "].base = ", f.base, " not above fliframes[", i - 1, "]")
        )
        (f.parent < 0 || f.parent >= i) && _viol!(
            r, "fliframe", string("fliframes[", i, "].parent = ", f.parent, ": not an older foreign frame")
        )
        if f.mark.trailtop != NOT_A_MARK &&
            (f.mark.globaltop > gtop || f.mark.trailtop > ntr)
            _viol!(
                r, "fliframe",
                string("fliframes[", i, "].mark (", f.mark.trailtop, ", ", f.mark.globaltop,
                    ") above the trail ", ntr, " / gTop ", gtop)
            )
        end
    end
    nq = ld.nqueries
    if nq < 0 || nq > length(ld.queries)
        _viol!(r, "query", string("nqueries = ", nq, " outside 0..", length(ld.queries)))
        nq = 0
    end
    for i in 2:nq
        r.cells += 1
        ld.queries[i].base <= ld.queries[i - 1].base && _viol!(
            r, "query", string("queries[", i, "].base not above queries[", i - 1, "]")
        )
    end
    return nothing
end

# ORIGINAL: every check, into a report.
function _check_stacks(ld::PL_local_data, allow_marks::Bool)::stack_report
    r = stack_report()
    _check_global_cells!(r, ld, allow_marks)
    _check_ref_chains!(r, ld)
    _check_vbox!(r, ld)
    _check_trail!(r, ld)
    _check_attvar_chain!(r, ld)
    _check_local_records!(r, ld)
    return r
end

"""
    stack_violations(ld; allow_marks=false) -> Vector{String}

The invariants of the global stack, the trail and the local records that do not hold, one text each (empty: the
stacks are sound). `allow_marks` accepts the collector's MARK/FIRST bits (during a collection only).
"""
function stack_violations(ld::PL_local_data; allow_marks::Bool=false)::Vector{String}
    r = _check_stacks(ld, allow_marks)
    r.dropped > 0 && push!(r.msgs, string("... and ", r.dropped, " more"))
    return r.msgs
end

# PORT: pl-gc.c checkStacks as check_stacks!
"""
    check_stacks!(ld; allow_marks=false) -> Int

Check the stacks (`stack_violations`); throw a `StackInvariantError` carrying the whole report if any invariant
fails, else return how many cells and records were examined (upstream's `checkStacks` returns a key; a count here,
so a test can tell a check that looked at something from one that looked at nothing).
"""
function check_stacks!(ld::PL_local_data; allow_marks::Bool=false)::Int
    r = _check_stacks(ld, allow_marks)
    if !isempty(r.msgs)
        r.dropped > 0 && push!(r.msgs, string("... and ", r.dropped, " more"))
        throw(StackInvariantError(r.msgs))
    end
    return r.cells
end

# PORT: pl-gc.c PL_check_stacks
# DIVERGES: none of value — `HAVE_CHECK_STACKS` is defined only in the `O_DEBUG || O_MAINTENANCE` block
# (pl-gc.c:4215), which a release build of swipl (the pin) leaves out, so upstream returns false without checking.
"`PL_check_stacks()`: false, as the pinned release build answers (pl-gc.c); `check_stacks!` is the kernel's checker."
function PL_check_stacks(ld::PL_local_data)::Bool
    return false
end
