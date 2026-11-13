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

# ── the stack collector's statistics and scheduler (G1-GC, piece G1-1; pl-gc.c:524-703, :3834-3909, :4592-4606) ──
# DIVERGES (D8, audit D-0634): the pinned build answers `current_prolog_flag(gc_thread, true)` (its collector thread, O_PLMT); the flag is read-only
# `false` here (src/os/pl-prologflag.jl) and `enterGC`/`leaveGC` (pl-gc.c, O_PLMT only: they hold `LD->gc.active` against a thread suspended by the
# collector thread) have no body here: one thread, nothing to hold. Everything below stays ZERO until G1-6's driver calls `gc_stat_start!` and
# `gc_stat_end!` around a collection.

# PORT: pl-fli.c PL_raise as raiseGcSignal!
# DIVERGES: the kernel has no signal machinery; the pending virtual signals are the bits of `ld.gc.sig_pending` (bit `sig - SIG_PROLOG_OFFSET`),
# and only the two collector signals (`SIG_GC`, `SIG_TUNE_GC`) are ever raised. The run loop's `ALERT_SIGNAL` check of a pending `SIG_GC` is G1-2's
# (engine core). Upstream's `PL_raise` also wakes the engine (`updateAlerted`); there is none to wake. True, as upstream's.
"Raise the virtual signal `sig` (`SIG_GC` or `SIG_TUNE_GC`): its bit of `ld.gc.sig_pending` (pl-fli.c `PL_raise`)."
function raiseGcSignal!(ld::PL_local_data, sig::Int)::Bool
    ld.gc.sig_pending |= UInt64(1) << (sig - SIG_PROLOG_OFFSET)
    return true
end

# PORT: pl-fli.h PL_pending as pendingGcSignal
# DIVERGES: see `raiseGcSignal!`.
"Is the virtual signal `sig` pending (pl-fli.h `PL_pending`)?"
pendingGcSignal(ld::PL_local_data, sig::Int)::Bool =
    (ld.gc.sig_pending & (UInt64(1) << (sig - SIG_PROLOG_OFFSET))) != 0

# PORT: pl-fli.c PL_clearsig as clearGcSignal!
# DIVERGES: see `raiseGcSignal!`. True, as upstream's for a valid signal.
"Clear the virtual signal `sig` (pl-fli.c `PL_clearsig`)."
function clearGcSignal!(ld::PL_local_data, sig::Int)::Bool
    ld.gc.sig_pending &= ~(UInt64(1) << (sig - SIG_PROLOG_OFFSET))
    return true
end

# PORT: pl-gc.c STAT_NEXT_INDEX
"The ring index after `i` in a window of `GC_STAT_WINDOW_SIZE` entries (0-based, pl-gc.c `STAT_NEXT_INDEX`)."
STAT_NEXT_INDEX(i::Int)::Int = i + 1 == GC_STAT_WINDOW_SIZE ? 0 : i + 1

# PORT: pl-gc.c STAT_PREV_INDEX
"The ring index before `i` in a window of `GC_STAT_WINDOW_SIZE` entries (0-based, pl-gc.c `STAT_PREV_INDEX`)."
STAT_PREV_INDEX(i::Int)::Int = i > 0 ? i - 1 : GC_STAT_WINDOW_SIZE - 1

# PORT: pl-gc.c gc_percentage
# DIVERGES (the decomposition's "*100" is wrong): a FRACTION, as upstream: `gc_time/(gc_time+prolog_time)`, 0.0 when no time was spent.
"The fraction of the CPU time of the window `stat` spent collecting (pl-gc.c `gc_percentage`)."
gc_percentage(stat::gc_stat)::Float64 =
    stat.gc_time == 0.0 ? 0.0 : stat.gc_time / (stat.gc_time + stat.prolog_time)

# PORT: pl-gc.c gc_stat_aggregate as gc_stat_aggregate!
# DIVERGES: the arrays are 1-based vectors, `aggr_index` stays 0-based (`aggr[aggr_index + 1]`); `reason` is summed, not averaged, as upstream's.
"Aggregate the last `GC_STAT_WINDOW_SIZE` collections into the next `aggr` entry: sums divided by the window size (pl-gc.c `gc_stat_aggregate`)."
function gc_stat_aggregate!(stats::gc_stats)::Nothing
    this = stats.aggr[stats.aggr_index + 1]
    gb = 0
    ga = 0
    tb = 0
    ta = 0
    lo = 0
    gt = 0.0
    pt = 0.0
    rs = UInt64(0)
    for i in 1:GC_STAT_WINDOW_SIZE                          # memset(this, 0); then the sums
        l = stats.last[i]
        gb += l.global_before
        ga += l.global_after
        tb += l.trail_before
        ta += l.trail_after
        lo += l.local_used
        gt += l.gc_time
        pt += l.prolog_time
        rs += l.reason
    end
    this.global_before = gb ÷ GC_STAT_WINDOW_SIZE
    this.global_after = ga ÷ GC_STAT_WINDOW_SIZE
    this.trail_before = tb ÷ GC_STAT_WINDOW_SIZE
    this.trail_after = ta ÷ GC_STAT_WINDOW_SIZE
    this.local_used = lo ÷ GC_STAT_WINDOW_SIZE
    this.gc_time = gt / GC_STAT_WINDOW_SIZE
    this.prolog_time = pt / GC_STAT_WINDOW_SIZE
    this.reason = rs                                        # not divided
    stats.aggr_index = STAT_NEXT_INDEX(stats.aggr_index)
    return nothing
end

# PORT: pl-gc.c gc_stat_start as gc_stat_start!
# DIVERGES: the stacks' sizes are `_used_stack` (bytes, src/pl-prims.jl); `stats` is `ld.gc.stats` or any `gc_stats` (the white-box tests' own).
"Start the statistics of a collection: the sizes before, the CPU time spent since the last one; `reason` 0 takes the pending request (pl-gc.c `gc_stat_start`)."
function gc_stat_start!(ld::PL_local_data, stats::gc_stats, reason::UInt64)::Nothing
    this = stats.last[stats.last_index + 1]
    cpu = ThreadCPUTime(CPU_USER)

    if stats.last_index == 0 && this.global_before != 0
        gc_stat_aggregate!(stats)
    end

    if reason == 0
        reason = stats.request
    end
    stats.request = 0

    this.reason = reason
    this.global_before = _used_stack(ld, :global)
    this.trail_before = _used_stack(ld, :trail)
    this.local_used = _used_stack(ld, :local)
    this.prolog_time = cpu - stats.thread_cpu
    stats.thread_cpu = cpu
    return nothing
end

# PORT: pl-gc.c gc_stat_end as gc_stat_end!
# DIVERGES: `LD->stacks.global.gced_size` and `.trail.gced_size` are `ld.gc.global_policy.gced_size` and `ld.gc.trail_policy.gced_size`; `PL_raise(SIG_TUNE_GC)`
# is `raiseGcSignal!` (a pending bit: the handler, `gc_tune_handler` pl-setup.c:838, is left to the signal owner).
"End the statistics of a collection: the sizes after, the time it took, the totals; asks for `prolog:tune_gc/3` above 20% (pl-gc.c `gc_stat_end`)."
function gc_stat_end!(ld::PL_local_data, stats::gc_stats)::gc_stat
    this = stats.last[stats.last_index + 1]
    cpu = ThreadCPUTime(CPU_USER)

    this.global_after = _used_stack(ld, :global)
    this.trail_after = _used_stack(ld, :trail)
    this.gc_time = cpu - stats.thread_cpu
    stats.thread_cpu = cpu
    stats.last_index = STAT_NEXT_INDEX(stats.last_index)

    ld.gc.global_policy.gced_size = this.global_after
    ld.gc.trail_policy.gced_size = this.trail_after

    stats.totals.global_gained += this.global_before - this.global_after
    stats.totals.trail_gained += this.trail_before - this.trail_after
    stats.totals.time += this.gc_time
    stats.totals.collections += 1

    if gc_percentage(this) > 0.2
        raiseGcSignal!(ld, SIG_TUNE_GC)
    end

    return this
end

# PORT: pl-gc.c last_gc_stats
"The statistics of the most recent collection (pl-gc.c `last_gc_stats`)."
last_gc_stats(stats::gc_stats)::gc_stat = stats.last[STAT_PREV_INDEX(stats.last_index) + 1]

# PORT: pl-gc.c gc_avg
"The mean of `gc_percentage` over the `aggr` window (pl-gc.c `gc_avg`)."
function gc_avg(stats::gc_stats)::Float64
    d = 0.0
    for i in 1:GC_STAT_WINDOW_SIZE
        d += gc_percentage(stats.aggr[i])
    end
    d /= GC_STAT_WINDOW_SIZE
    return d
end

# PORT: pl-gc.c unify_gc_reason
# DIVERGES: `PL_unify_term(t, PL_FUNCTOR, FUNCTOR_gc6, PL_INT ...)` (not ported) is `PL_unify_functor` and one `PL_unify_arg` per integer, through a scratch
# reference. The shift of `ur` is upstream's 36 although `GC_USER` is bit 40: copied as is (pl-gc.c:696).
"Unify `t` with `gc(GlobalOverflow, GlobalRequest, TrailOverflow, TrailRequest, Exception, User)`, the bytes of the reason of `stat` (pl-gc.c `unify_gc_reason`)."
function unify_gc_reason(ld::PL_local_data{T}, t::term_t, stat::gc_stat)::Bool where {T}
    r = stat.reason
    go = Int((r >> 0) & 0xff)
    gr = Int((r >> 8) & 0xff)
    to = Int((r >> 16) & 0xff)
    tr = Int((r >> 24) & 0xff)
    ex = Int((r >> 32) & 0xff)
    ur = Int((r >> 36) & 0xff)

    PL_unify_functor(ld, t, mk_sym(T, :gc), 6) || return false
    tmp = PL_new_term_ref(ld)
    PL_put_int64(ld, tmp, go) && PL_unify_arg(ld, 1, t, tmp) || return false
    PL_put_int64(ld, tmp, gr) && PL_unify_arg(ld, 2, t, tmp) || return false
    PL_put_int64(ld, tmp, to) && PL_unify_arg(ld, 3, t, tmp) || return false
    PL_put_int64(ld, tmp, tr) && PL_unify_arg(ld, 4, t, tmp) || return false
    PL_put_int64(ld, tmp, ex) && PL_unify_arg(ld, 5, t, tmp) || return false
    PL_put_int64(ld, tmp, ur) && PL_unify_arg(ld, 6, t, tmp) || return false
    return true
end

# PORT: pl-gc.c unify_gc_stats
# DIVERGES: `PL_unify_term` (not ported): `gc_stats/8` is `PL_unify_functor` and one `PL_unify_arg` per argument through a scratch reference; the ring `index` is
# 0-based as upstream's and `stats` a vector indexed `index + 1`.
"Unify `t` with the list of the `gc_stats(Reason, GlobalBefore, GlobalAfter, TrailBefore, TrailAfter, Local, GcTime, GcPercentage)` of the entries of the ring `stats` that hold a collection, newest first (pl-gc.c `unify_gc_stats`)."
function unify_gc_stats(
    ld::PL_local_data{T}, t::term_t, stats::Vector{gc_stat}, index::Int
)::Bool where {T}
    tail = PL_copy_term_ref(ld, t)
    head = PL_new_term_ref(ld)
    rt = PL_new_term_ref(ld)
    tmp = PL_new_term_ref(ld)

    for i in 1:GC_STAT_WINDOW_SIZE
        index = STAT_PREV_INDEX(index)
        this = stats[index + 1]

        if this.global_before != 0
            PL_unify_list(ld, tail, head, tail) || return false
            PL_put_variable(ld, rt) || return false
            unify_gc_reason(ld, rt, this) || return false
            PL_unify_functor(ld, head, mk_sym(T, :gc_stats), 8) || return false
            PL_unify_arg(ld, 1, head, rt) || return false
            PL_put_int64(ld, tmp, this.global_before) && PL_unify_arg(ld, 2, head, tmp) || return false
            PL_put_int64(ld, tmp, this.global_after) && PL_unify_arg(ld, 3, head, tmp) || return false
            PL_put_int64(ld, tmp, this.trail_before) && PL_unify_arg(ld, 4, head, tmp) || return false
            PL_put_int64(ld, tmp, this.trail_after) && PL_unify_arg(ld, 5, head, tmp) || return false
            PL_put_int64(ld, tmp, this.local_used) && PL_unify_arg(ld, 6, head, tmp) || return false
            PL_put_float(ld, tmp, this.gc_time) && PL_unify_arg(ld, 7, head, tmp) || return false
            PL_put_float(ld, tmp, gc_percentage(this)) && PL_unify_arg(ld, 8, head, tmp) || return false
        end
    end

    return PL_unify_nil(ld, tail)
end

# PORT: pl-gc.c gc_statistics as pl_dgc_statistics5_va
# (PRED_IMPL("$gc_statistics", 5, gc_statistics, 0), pl-gc.c:4592; `'$gc_statistics'(-Last, -Aggr, -LastPercentage, -AggrPercentage, -Average)`)
"`'\$gc_statistics'(-Recent, -Aggregated, -LastFraction, -AggregatedFraction, -Average)` (pl-gc.c): the stack collector's statistics."
function pl_dgc_statistics5_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2, A3, A4, A5 = PL__t0, PL__t0 + 1, PL__t0 + 2, PL__t0 + 3, PL__t0 + 4
    stats = ld.gc.stats
    last = last_gc_stats(stats)
    aggr = stats.aggr[STAT_PREV_INDEX(stats.aggr_index) + 1]

    return (
        unify_gc_stats(ld, A1, stats.last, stats.last_index) &&
        unify_gc_stats(ld, A2, stats.aggr, stats.aggr_index) &&
        PL_unify_float(ld, A3, gc_percentage(last)) &&
        PL_unify_float(ld, A4, gc_percentage(aggr)) &&
        PL_unify_float(ld, A5, gc_avg(stats))
    ) ? FTRUE : FFALSE
end

# PORT: pl-gc.c BeginPredDefs as PL_predicates_from_gc
# DIVERGES: `$gc_statistics/5` only; `$check_stacks/1` (O_DEBUG or O_MAINTENANCE: not in a release build) and `gc_counts/1` (GC_COUNTING) are not
# in the pinned build; `PRED_DEF` ors in `PL_FA_VARARGS`.
"pl-gc.c's registration table (`BeginPredDefs(gc)`): the entries of a release build."
const PL_predicates_from_gc = (
    PL_extension("\$gc_statistics", 5, pl_dgc_statistics5_va, PL_FA_VARARGS),
)

# PORT: pl-gc.c considerGarbageCollect
# DIVERGES: `Stack s` is `:global`, `:trail`, `:local` or `:combined` (`nothing` = NULL: the global and the trail, as `&GD->combined_stack`); the stacks are not
# structs: sizes are `_used_stack` (bytes), the combined stack's size is `8 * ld.stacks_limit` (what `_room_stack` uses), and `gc`, `small`, `factor`,
# `gced_size` are `ld.gc.global_policy` etc. `PL_raise(SIG_GC)` is `raiseGcSignal!` (a pending bit). The `DEBUG(MSG_GC_SCHEDULE, ...)` output is left out.
# The (*) of upstream: while no inference ran since the last collection (`LD->gc.inferences`) nothing is requested, and the stack's `gced_size` follows its use.
"Is a stack collection due (pl-gc.c `considerGarbageCollect`)? If so the request is recorded and `SIG_GC` raised; true when `SIG_GC` is pending."
function considerGarbageCollect(ld::PL_local_data, s::Union{Nothing, Symbol}=nothing)::Bool
    if truePrologFlag(ld, PLFLAG_GC)
        if pendingGcSignal(ld, SIG_GC)
            return true
        end

        if s === nothing || s === :combined
            return considerGarbageCollect(ld, :global) || considerGarbageCollect(ld, :trail)
        else
            pol = s === :global ? ld.gc.global_policy : s === :trail ? ld.gc.trail_policy : ld.gc.local_policy
            if pol.gc
                used = _used_stack(ld, s)                       # amount in actual use
                limit = 8 * ld.stacks_limit - _used_stack(ld, :local)
                space = limit > used ? limit - used : 0
                low = _used_stack(ld, :local) + pol.small

                if s === :global
                    low += _used_stack(ld, :trail)
                else
                    low += _used_stack(ld, :global) ÷ 8
                end

                if ld.gc.inferences == ld.statistics.inferences && !ld.exception_processing
                    pol.gced_size = used                        # (*)
                    return false
                end

                if used > pol.factor * pol.gced_size + low
                    # request on the stack (MSG_GC_SCHEDULE)
                elseif space < limit ÷ 8 && used > pol.gced_size + limit ÷ 32
                    # request on low space (MSG_GC_SCHEDULE)
                else
                    return false
                end

                ld.gc.stats.request = UInt64(s === :global ? GC_GLOBAL_REQUEST : GC_TRAIL_REQUEST)

                return raiseGcSignal!(ld, SIG_GC)
            end
        end
    end

    return false
end

# PORT: pl-gc.c call_tune_gc_hook
# DIVERGES: `PROCEDURE_tune_gc3` is looked up as `prolog:tune_gc/3` on each call (upstream: `PL_predicate("tune_gc", 3, "prolog")` at pl-ext.c:385, the
# same procedure); the database is the running query's (`_query_gd`). The caller, `gc_tune_handler` (pl-setup.c:838-840, on `SIG_TUNE_GC`), is left
# to the signal owner; nothing in the kernel raises `SIG_TUNE_GC` before G1-6's driver calls `gc_stat_end!`.
"Call `prolog:tune_gc(+GcTime, +LastFraction, +AggregatedFraction)` if the program defines it (pl-gc.c `call_tune_gc_hook`)."
function call_tune_gc_hook(ld::PL_local_data{T})::Nothing where {T}
    gd = _query_gd(ld)
    proc = lookupProcedure(mk_sym(T, :tune_gc), 3, lookupModule(gd, mk_sym(T, :prolog)))

    if isDefinedProcedure(gd, proc)
        fid = PL_open_foreign_frame(ld)
        if fid != 0
            av = PL_new_term_refs(ld, 3)
            stats = ld.gc.stats
            last = last_gc_stats(stats)
            aggr = stats.aggr[STAT_PREV_INDEX(stats.aggr_index) + 1]

            if PL_unify_float(ld, av, last.gc_time) &&
                PL_unify_float(ld, av + 1, gc_percentage(last)) &&
                PL_unify_float(ld, av + 2, gc_percentage(aggr))
                PL_call_predicate(gd, ld, nothing, PL_Q_NODEBUG | PL_Q_PASS_EXCEPTION, proc, av)
            end

            PL_close_foreign_frame(ld, fid)
        end
    end
    return nothing
end

# PORT: pl-gc.c blockGC
# DIVERGES: `gc_status` is `ld.gc.status` (pl-gc.c `#define gc_status LD->gc.status`).
"Block the collector unless `flags` has `ALLOW_GC`, the shifter unless it has `ALLOW_SHIFT` (pl-gc.c `blockGC`)."
function blockGC(ld::PL_local_data, flags::Int)::Nothing
    if (flags & ALLOW_GC) == 0
        ld.gc.status.blocked += 1
    end
    if (flags & ALLOW_SHIFT) == 0
        ld.shift_status.blocked += 1
    end
    return nothing
end

# PORT: pl-gc.c unblockGC
"Undo `blockGC` for the same `flags` (pl-gc.c `unblockGC`)."
function unblockGC(ld::PL_local_data, flags::Int)::Nothing
    if (flags & ALLOW_GC) == 0
        ld.gc.status.blocked -= 1
    end
    if (flags & ALLOW_SHIFT) == 0
        ld.shift_status.blocked -= 1
    end
    return nothing
end
