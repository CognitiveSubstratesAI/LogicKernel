# UPSTREAM: swipl-devel src/pl-gc.c @ 18168e629eab
# CLASS: code
# COPYRIGHT: Copyright (c)  1985-2024, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
# allow-new-artifact: a port of pl-gc.c at the pin (read via git show 18168e62:src/pl-gc.c; the design is in evidence/G1/g1gc3_handoff.md)
# G1-GC (G1-3b): the DRIVERS of the MARK phase of SWI-Prolog's stack garbage collector (pl-gc.c): the
# collector's own walk over a clause's byte code (`walk_and_mark_gc`, a SECOND walk beside the ACTIVE
# walk of pl-gc.jl, whose code and mutants stay untouched), the marking of the alternative clauses
# (`mark_alt_clauses`, `MARK_ALT_CLAUSES` live: audit D-0634 ruling D4), early reset of the trail
# (`early_reset_vars`, marking half), `mark_choicepoints`, `mark_environments`, `mark_query_stacks`,
# `mark_stacks`, `mark_phase` and `unmark_*`. The cell helpers, `mark_variable`, the term-reference roots,
# `mark_foreign_frame` and the per-frame helpers (`mark_local_variable`, `mark_arguments`,
# `mark_new_arguments`, `mark_trie_gen`) are G1-3a's (pl-gcmark.jl, included BEFORE this file).
# The mark phase MOVES and FREES NOTHING: a trail entry it zeroes is removed by the compaction (G1-5/6).
#
# Positions: a frame is an index into `ld.frames`, a choice into `ld.choices`, a foreign frame into
# `ld.fliframes`, a query into `ld.queries` (0 = NULL); a variable of a frame is the slot at position
# `base + Int(v)` (v = the operand code, `VAROFFSET`), its slot INDEX is the position + 1, and a cell of the
# local stack is addressed `-(index)` by the helpers of pl-gcmark.jl (see there).

# ── the walk state (pl-gc.c walk_state, GCM_*) ───────────────────────────────────────────────────
# PORT: pl-gc.c GCM_CLEAR
"Walk mode flag: clear uninitialised data (pl-gc.c `GCM_CLEAR`)."
const GCM_CLEAR = 1
# PORT: pl-gc.c GCM_ALTCLAUSE
"Walk mode flag: marking alternative clauses (pl-gc.c `GCM_ALTCLAUSE`)."
const GCM_ALTCLAUSE = 2
# PORT: pl-gc.c NO_ADEPTH as GC_NO_ADEPTH
"The `adepth` after a `B_UNIFY_VAR`/`B_UNIFY_FIRSTVAR`: never mark over ARGP (pl-gc.c `NO_ADEPTH`)."
const GC_NO_ADEPTH = 1234567

# PORT: pl-gc.c walk_state as gc_walk_state
# DIVERGES: `GCM_ACTIVE`/`GCM_CHOICE` and the bit vectors `active`/`clear` belong to the ACTIVE walk of
# pl-gc.jl (`walk_state`), so there are no bit vectors here and `clear_choice_mark`/`mark_choice_mark`
# (which act under `GCM_CHOICE` only) are no-ops of this walk; `c0` (debug output) is not carried.
# `frame` is an index, `base` its position, `envtop` and `ARGP` are POSITIONS of the local stack, `arity`
# is `frame->predicate->functor->arity` (for `I_CALLCLEANUP` and the others).
"The state of one `walk_and_mark_gc` (pl-gc.c `walk_state`, the stack collector's fields)."
mutable struct gc_walk_state
    frame::Int                  # LocalFrame frame: processing node (index)
    base::Int                   # the frame's position
    arity::Int                  # frame->predicate->functor->arity
    flags::Int                  # general flags (GCM_*)
    envtop::Int                 # Word envtop: just above environment (position)
    unmarked::Int               # size_t unmarked: left when marking alt clauses
    ARGP::Int                   # Word ARGP: head unify instructions (position)
    adepth::Int                 # int adepth: ARGP nesting
end
gc_walk_state(frame::Int, base::Int, arity::Int, flags::Int) =
    gc_walk_state(frame, base, arity, flags, 0, 0, argFrameP(base, 0), 0)

# PORT: pl-gc.c mark_frame_var as mark_frame_var_gc
# (the stack collector's branch; the `state->active` branch is `mark_frame_var` of pl-gc.jl)
"Variable operand `v` is read: mark its slot if it is below `envtop` and not yet marked (pl-gc.c `mark_frame_var`)."
@inline function mark_frame_var_gc(
    ld::PL_local_data{T}, st::gc_mark_counts, ws::gc_walk_state, v::code
)::Nothing where {T}
    sp = ws.base + Int(v)                                       # Word sp = varFrameP(state->frame, v)
    if sp < ws.envtop && !is_marked(ld.slots[sp + 1])
        mark_local_variable(ld, st, -(sp + 1))
        ws.unmarked -= 1
    end
    return nothing
end

# PORT: pl-gc.c clear_frame_var as clear_frame_var_gc
# (the `state->flags & GCM_CLEAR` branch; the `state->clear` branch is `clear_frame_var` of pl-gc.jl)
# DIVERGES: upstream makes the cell a variable (`setVar`); `_setVar!` of pl-gc.jl makes a FRESH variable
# cell on the global stack, which the mark phase must not allocate, so the slot gets word 0 — the "never
# written" state, which the code first-writes before it reads (a `*FIRSTVAR` instruction), as upstream's
# unbound cell is. The debug check of `O_DEBUG` is not carried.
"Variable operand `var` is written first here: clear its slot under `GCM_CLEAR` (pl-gc.c `clear_frame_var`)."
@inline function clear_frame_var_gc(
    ld::PL_local_data{T}, ws::gc_walk_state, var::code
)::Nothing where {T}
    if (ws.flags & GCM_CLEAR) != 0
        ld.slots[ws.base + Int(var) + 1] = word(0)
    end
    return nothing
end

# PORT: pl-gc.c mark_argp as mark_argp_gc
"In head-unification mode at depth 0, mark the argument ARGP names and step it (pl-gc.c `mark_argp`; `MARK_ALT_CLAUSES`)."
@inline function mark_argp_gc(
    ld::PL_local_data{T}, st::gc_mark_counts, ws::gc_walk_state
)::Nothing where {T}
    if ws.adepth == 0                                           # !(flags & GCM_ACTIVE) && adepth == 0
        if ws.ARGP < ws.envtop && !is_marked(ld.slots[ws.ARGP + 1])
            mark_local_variable(ld, st, -(ws.ARGP + 1))
            ws.unmarked -= 1
        end
        ws.ARGP += 1
    end
    return nothing
end

# PORT: pl-gc.c walk_and_mark as walk_and_mark_gc
# DIVERGES: `pc` and the result are the INDEX of an opcode in `codes` (the operand `PC[k]` is
# `codes[pc + 1 + k]`), as `walk_and_mark` of pl-gc.jl; the instructions are those the kernel declares
# (`H_SMALLINTW`, `A_VAR`, `A_VAR0`-`A_VAR2`, `A_FIRSTVAR_IS`, `A_MPZ`, `A_MPQ` and `D_BREAK` have no
# counterpart: the kernel declares none of them), a literal operand is the table's `arguments`
# (`code_get_indirect` is not needed), and the `assert`s on `adepth` at `B_UNIFY_EXIT`/`I_ENTER`/
# `I_SSU_*` are not carried. `COUNT(...)` statistics are not kept. `I_RATIONAL` has no variable operand
# to mark, as upstream's list of the type tests has no `I_RATIONAL`.
"""
    walk_and_mark_gc(ld, st, ws, codes, pc, end_op) -> Int

The stack collector's walk over the byte code of a clause from `codes[pc]` to the first instruction
`end_op` (pl-gc.c `walk_and_mark`, modes `GCM_CLEAR`, `GCM_ALTCLAUSE` and plain marking): variables read
are marked (`mark_frame_var_gc`), variables first written are cleared under `GCM_CLEAR`, and the head
instructions track ARGP (`mark_argp_gc`). Returns the index of the instruction it stopped at.
"""
function walk_and_mark_gc(
    ld::PL_local_data{T}, st::gc_mark_counts, ws::gc_walk_state, codes::Vector{code},
    pc::Int, end_op::code
)::Int where {T}
    alt_mode = (ws.flags & GCM_ALTCLAUSE) != 0
    while true
        op = codes[pc]
        op == end_op && return pc                   # if ( op == end ) { PC--; return PC; }
        if op == H_STRING || op == H_MPZ || op == H_MPQ
            mark_argp_gc(ld, st, ws)                # only skip the size of the string + header
        elseif op == I_EXITQUERY || op == I_EXITFACT || op == I_FCALLDETVA ||
            op == I_FEXITDET || op == I_FEXITNDET || op == S_TRUSTME || op == S_LIST
            return pc                               # return PC-1
        elseif op == I_FREDO
            mark_arguments(ld, st, ws.frame)
            return pc
        elseif op == C_JMP && alt_mode
            # (GCM_ALTCLAUSE: `break`, the jump is not followed)
        elseif op == C_JMP || op == L_NOLCO         # unconditional jump
            pc += Int(codes[pc + 1]) + 2
            continue
        elseif op == C_OR && !alt_mode
            alt = pc + Int(codes[pc + 1]) + 2       # Code alt = PC+PC[0]+1
            walk_and_mark_gc(ld, st, ws, codes, pc + 2, C_JMP)  # PC++; walk_and_mark(state, PC, C_JMP)
            pc = alt
            continue
        elseif (op == C_NOT || op == C_DET) && !alt_mode
            alt = pc + Int(codes[pc + 2]) + 3       # Code alt = PC+PC[1]+2
            ec = op == C_NOT ? C_CUT : C_DETTRUE
            # clear_choice_mark(state, PC[0]): under GCM_CHOICE only (the ACTIVE walk): no effect here
            walk_and_mark_gc(ld, st, ws, codes, pc + 3, ec)     # PC += 2: skip the two arguments
            pc = alt
            continue
        elseif (op == C_SOFTIF || op == C_IFTHENELSE || op == C_FASTCOND) && !alt_mode
            alt = pc + Int(codes[pc + 2]) + 3
            walk_and_mark_gc(ld, st, ws, codes, pc + 3, C_JMP)  # skip the 'MARK' variable and jmp
            pc = alt
            continue
        elseif (op == C_IFTHEN || op == C_SOFTIFTHEN) && !alt_mode
            pc = walk_and_mark_gc(ld, st, ws, codes, pc + 2, C_END) + 1     # PC++: skip C_END
            continue
        elseif op == C_OR || op == C_NOT || op == C_DET || op == C_SOFTIF ||
            op == C_IFTHENELSE || op == C_FASTCOND || op == C_IFTHEN || op == C_SOFTIFTHEN
            # GCM_ALTCLAUSE: `break`, the control construct is stepped over
        elseif op == C_CUT || op == C_LSCUT || op == C_LCUT || op == C_SOFTCUT ||
            op == C_LCUTIFTHEN || op == C_FASTCUT || op == C_DETTRUE
            # mark_choice_mark(state, PC[0]): under GCM_CHOICE only (the ACTIVE walk): no effect here
        elseif op == B_UNIFY_VAR                    # Var = Term
            mark_frame_var_gc(ld, st, ws, codes[pc + 1])
            ws.adepth = GC_NO_ADEPTH
        elseif op == B_UNIFY_FIRSTVAR
            ws.adepth = GC_NO_ADEPTH                # never need to mark over ARGP
            clear_frame_var_gc(ld, ws, codes[pc + 1])
        elseif op == B_FIRSTVAR || op == B_ARGFIRSTVAR || op == B_UNIFY_FC || op == C_VAR
            clear_frame_var_gc(ld, ws, codes[pc + 1])
        elseif op == C_VAR_N
            var = codes[pc + 1]
            for _ in 1:Int(codes[pc + 2])           # while(count--) clear_frame_var(state, var++, PC)
                clear_frame_var_gc(ld, ws, var)
                var += code(1)
            end
        elseif op == H_LIST_FF || op == B_UNIFY_FF
            op == H_LIST_FF && mark_argp_gc(ld, st, ws)
            clear_frame_var_gc(ld, ws, codes[pc + 1])
            clear_frame_var_gc(ld, ws, codes[pc + 2])
        elseif op == A_ADD_FC || op == B_UNIFY_FV || op == B_UNIFY_VF
            clear_frame_var_gc(ld, ws, codes[pc + 1])
            mark_frame_var_gc(ld, st, ws, codes[pc + 2])
        elseif op == B_UNIFY_VV || op == B_EQ_VV || op == B_NEQ_VV
            mark_frame_var_gc(ld, st, ws, codes[pc + 1])
            mark_frame_var_gc(ld, st, ws, codes[pc + 2])
        elseif op == B_ARG_VF || op == B_ARG_CF
            op == B_ARG_VF && mark_frame_var_gc(ld, st, ws, codes[pc + 1])
            mark_frame_var_gc(ld, st, ws, codes[pc + 2])
            clear_frame_var_gc(ld, ws, codes[pc + 3])
        elseif op == I_VAR || op == I_NONVAR || op == I_INTEGER || op == I_FLOAT ||
            op == I_NUMBER || op == I_ATOMIC || op == I_ATOM || op == I_STRING ||
            op == I_COMPOUND || op == I_CALLABLE || op == I_CALLCONT || op == I_SHIFT ||
            op == I_SHIFTCP
            mark_frame_var_gc(ld, st, ws, codes[pc + 1])
        elseif op == B_UNIFY_VC || op == B_EQ_VC || op == B_NEQ_VC || op == B_ARGVAR ||
            op == B_VAR
            mark_frame_var_gc(ld, st, ws, codes[pc + 1])        # index = *PC; var_common
        elseif op == B_VAR0
            mark_frame_var_gc(ld, st, ws, VAROFFSET(0))
        elseif op == B_VAR1
            mark_frame_var_gc(ld, st, ws, VAROFFSET(1))
        elseif op == B_VAR2
            mark_frame_var_gc(ld, st, ws, VAROFFSET(2))
        elseif op == I_CALLCLEANUP
            arg_goal = ws.arity == 2 ? 1 : 2
            mark_frame_var_gc(ld, st, ws, VAROFFSET(arg_goal - 1))      # main goal
        elseif op == I_EXITCLEANUP
            if ws.arity == 5                        # '$tbl_leader'/5: C cleanup uses all args
                for i in 0:(ws.arity - 1)
                    mark_frame_var_gc(ld, st, ws, VAROFFSET(i))
                end
            else
                ws.arity == 4 && mark_frame_var_gc(ld, st, ws, VAROFFSET(ws.arity - 2)) # The ball
                mark_frame_var_gc(ld, st, ws, VAROFFSET(ws.arity - 1))  # cleanup goal
            end
        elseif op == I_EXITRESET || op == I_EXITCATCH
            if op == I_EXITRESET && ws.arity == 6   # '$tbl_reset'/6: worklist, skeleton, delays
                for i in 3:5
                    mark_frame_var_gc(ld, st, ws, VAROFFSET(i))
                end
            end
            mark_frame_var_gc(ld, st, ws, VAROFFSET(1))         # The ball
            mark_frame_var_gc(ld, st, ws, VAROFFSET(2))         # recovery goal
        elseif op == I_CUTCHP
            mark_frame_var_gc(ld, st, ws, VAROFFSET(1))         # choice-point
        elseif op == I_CALLATMV || op == I_DEPARTATMV
            mark_frame_var_gc(ld, st, ws, codes[pc + 2])
        elseif op == H_FIRSTVAR                     # MARK_ALT_CLAUSES
            if (ws.flags & GCM_CLEAR) != 0
                clear_frame_var_gc(ld, ws, codes[pc + 1])
            else
                mark_argp_gc(ld, st, ws)
            end
        elseif op == H_VAR
            mark_frame_var_gc(ld, st, ws, codes[pc + 1])
            mark_argp_gc(ld, st, ws)
        elseif op == H_ATOM || op == H_SMALLINT || op == H_NIL || op == H_FLOAT
            mark_argp_gc(ld, st, ws)
        elseif op == H_FUNCTOR || op == H_LIST
            mark_argp_gc(ld, st, ws)
            ws.adepth += 1
        elseif op == B_FUNCTOR || op == B_LIST
            ws.adepth += 1
        elseif op == H_VOID
            ws.adepth == 0 && (ws.ARGP += 1)
        elseif op == H_VOID_N
            ws.adepth == 0 && (ws.ARGP += Int(codes[pc + 1]))
        elseif op == H_POP || op == B_POP
            ws.adepth -= 1
        end
        pc += 1 + codeTable(op).arguments           # for( ; ; PC += codeTable[op].arguments)
    end
end

# ── early reset of the trail (pl-gc.c early_reset_vars, mergeTrailedAssignments) ─────────────────
# PORT: pl-gc.c mergeTrailedAssignments
# DIVERGES: the cells marked FIRST are kept in a local `Vector{Int}` (upstream pushes them on
# `LD->cycle.vstack`: `push_marked`/`popall_marked`), the trail is indexed 1.. (`te` is an index, the
# pair of a trailed assignment is the address entry at `i-1` and the value entry at `i`), and a zeroed
# entry is word 0, removed by the compaction (G1-5/6). `te[1]` of the last entry of the trail is read as
# "no value entry".
"""
    mergeTrailedAssignments(ld, st, top, mark, assignments)

If a location is trailed by `TrailAssignment()` more than once within one choicepoint's trail range
`mark..top`, only the first entry is needed: delete the later pairs (pl-gc.c).
"""
function mergeTrailedAssignments(
    ld::PL_local_data{T}, st::gc_mark_counts, top::Int, mark::Int, assignments::Int
)::Nothing where {T}
    trail = ld.trail
    marked = Int[]                                      # LD->cycle.vstack
    for te in mark:top
        p = _trail_pos(trail[te])                       # Word p = valPtr(te->as_word)
        if te + 1 <= length(trail) && isTrailVal(trail[te + 1])     # ttag(te[1].as_word) == TAG_TRAILVAL
            assignments -= 1
            if is_first(ld.gstack[p])
                trail[te] = word(0)                     # te->as_word = 0
                trail[te + 1] = word(0)                 # te[1].as_word = 0
                st.trailcells_deleted += 2
            else
                ld.gstack[p] = set_first(ld.gstack[p])  # set_first(p)
                push!(marked, p)                        # push_marked(p)
            end
        elseif p != 0 && is_first(ld.gstack[p])
            trail[te] = word(0)
            st.trailcells_deleted += 1
        end
    end
    for p in marked                                     # popall_marked()
        ld.gstack[p] = clear_first(ld.gstack[p])
    end
    assignments == 0 || error("mergeTrailedAssignments: $(assignments) assignments left")
    return nothing
end

# PORT: pl-gc.c early_reset_vars
# DIVERGES: heights where upstream has addresses: `gKeep` is the first free cell, `max(frozen_bar,
# globaltop) + 1`, so upstream's `tard >= gKeep` is `tard > gk` and `tard > gKeep` is `tard > gk + 1`
# (`gk` = `max(frozen_bar, globaltop)`); the kernel trails global cells only (no local variable is trailed:
# G1-3a/the trail), so upstream's `tard >= top` ("above the local stack", with `top` the choicepoint's or
# foreign frame's address) can never fire: the `top` parameter is dropped and those two arms are not
# carried; the `gMax` bound is `gTop`. A cell that is reset gets word 0 (`setVar`). `te` is an index
# into `ld.trail` and the result the index it stopped at (below the mark's `trailtop + 1`).
# `needsRelocation` is G1-5's.
"""
    early_reset_vars(ld, st, m, te) -> Int

Walk the trail from entry `te` down to the mark `m`'s `trailtop`: a trailed variable not marked is reset
now and its entry deleted (zeroed), a trailed assignment whose cell is marked keeps its old value marked,
duplicates within the range are merged (pl-gc.c). Returns the next entry to look at.
"""
function early_reset_vars(
    ld::PL_local_data{T}, st::gc_mark_counts, m::mark, te::Int
)::Int where {T}
    trail = ld.trail
    tm = m.trailtop + 1                                 # TrailEntry tm = m->trailtop.as_ptr
    te0 = te
    assignments = 0
    gk = max(ld.frozen_bar, m.globaltop)                # gKeep = first free cell = gk + 1
    while te >= tm                                      # for( ; te >= tm; te-- ): early reset of vars
        e = trail[te]
        if isTrailVal(e)
            tard = _trail_pos(trail[te - 1])            # Word tard = valPtr(te[-1].as_word)
            gp = trailValP(e)                           # Word gp = valPtr(te->as_word)
            keep = false
            if tard > gk                                # tard >= gKeep && tard < gMax
                trail[te] = word(0)
                te -= 1
                trail[te] = word(0)
                st.trailcells_deleted += 2
            elseif is_marked(ld.gstack[tard])
                keep = true
            else
                if isAttVar(ld.gstack[gp]) && ld.attvar_call_residue_vars_count != 0 &&
                    ld.attvar_attvars != 0
                    ld.gstack[tard] = _atom_word!(ld, mk_sym(T, :garbage_collected))   # see (*)
                    domark(ld, st, tard)
                    keep = true
                else
                    ld.gstack[tard] = clear_marked(ld.gstack[gp])  # *tard = *gp; clear_marked(tard)
                    trail[te] = word(0)
                    te -= 1
                    trail[te] = word(0)
                    st.trailcells_deleted += 2
                end
            end
            if keep                                     # keep:
                is_first(ld.gstack[gp]) &&
                    error("early_reset_vars: first-marked assignment value")
                if !is_marked(ld.gstack[gp])
                    mark_variable(ld, st, gp)
                end
                assignments += 1
                te -= 1
            end
        else
            tard = _trail_pos(e)                        # Word tard = valPtr(te->as_word)
            # (tard >= top: above the local stack: never, see DIVERGES)
            if tard > gk + 1                            # tard > gKeep && tard < gMax
                if ld.attvar_attvars != 0 &&            # see (**)
                    is_marked(ld.gstack[tard]) && isRef(ld.gstack[tard]) && te - 1 >= tm
                    tard2 = _trail_pos(trail[te - 1])
                    if is_marked(ld.gstack[tard2]) && isAttVar(ld.gstack[tard2])
                        te -= 2                         # te--; continue (the for's te--)
                        continue
                    end
                end
                trail[te] = word(0)
                st.trailcells_deleted += 1
            elseif !is_marked(ld.gstack[tard])
                ld.gstack[tard] = word(0)               # setVar(*tard)
                trail[te] = word(0)
                st.trailcells_deleted += 1
            end
        end
        te -= 1
    end
    if assignments >= 1
        mergeTrailedAssignments(ld, st, te0, tm, assignments)
    end
    return te
end

# ── the alternative clauses, the choicepoints and the environments (pl-gc.c) ─────────────────────
# PORT: pl-gc.c slotsInFrame as gc_slots_in_frame
# DIVERGES: `pc` is the index into the frame's clause codes, 0 = NULL.
"The number of slots of frame `fr` a collection must look at, resuming at `pc` (pl-gc.c `slotsInFrame`)."
@inline function gc_slots_in_frame(ld::PL_local_data{T}, fr::Int, pc::Int)::Int where {T}
    f = ld.frames[fr]
    def = f.predicate::Definition{T}
    if pc == 0 || (def.flags & P_FOREIGN) != 0 || f.clause === nothing
        return def.arity
    end
    return Int((f.clause::ClauseRef{T}).clause.prolog_vars)
end

# PORT: pl-gc.c mark_alt_clauses
# DIVERGES: `MARK_ALT_CLAUSES` is defined at the pin and the live arm is ported (audit D-0634 ruling D4,
# not the `#else` arm that marks the arguments); the clause list is the chain of `cref.next`, a
# `visibleClause` test at the frame's generation as upstream's, a reference without a single clause
# (`cref.clause === nothing`: a clause list of a hash bucket) is stepped over.
"""
    mark_alt_clauses(ld, st, fr, cref)

Mark the arguments of frame `fr` that the clauses from `cref` on (the choicepoint's alternatives) will
read, by walking their heads (`GCM_ALTCLAUSE`) until every argument is marked (pl-gc.c).
"""
function mark_alt_clauses(
    ld::PL_local_data{T}, st::gc_mark_counts, fr::Int, cref::Union{Nothing, ClauseRef{T}}
)::Nothing where {T}
    f = ld.frames[fr]
    sp = argFrameP(f.base, 0)                           # Word sp = argFrameP(fr, 0)
    argc = (f.predicate::Definition{T}).arity
    unmarked = 0
    for i in 0:(argc - 1)
        is_marked(ld.slots[sp + i + 1]) || (unmarked += 1)
    end
    unmarked == 0 && return nothing
    ws = gc_walk_state(fr, f.base, argc, GCM_ALTCLAUSE)
    ws.unmarked = unmarked
    ws.envtop = sp + argc
    while cref !== nothing && ws.unmarked > 0           # for(; cref && state.unmarked > 0; cref=cref->next)
        cl = cref.clause
        if cl !== nothing && visibleClause(ld, cl, generationFrame(f))
            walk_and_mark_gc(ld, st, ws, cl.codes, 1, I_EXIT)
        end
        ws.adepth = 0
        ws.ARGP = sp
        cref = cref.next
    end
    return nothing
end

# PORT: pl-gc.c early_reset_choicepoint
# DIVERGES: the `top` upstream computes for `early_reset_vars` is not needed (see there); the
# `needsRelocation`/`alien_into_relocation_chain` of the mark's trailtop belong to G1-5.
"Early reset for the trail range of choicepoint `chi` (an index), after the foreign frames above it (pl-gc.c)."
function early_reset_choicepoint(
    ld::PL_local_data{T}, st::gc_mark_counts, ms::mark_state, chi::Int
)::Nothing where {T}
    ch = ld.choices[chi]
    while ms.flictx != 0 && ld.fliframes[ms.flictx].base > ch.base  # (char*)state->flictx > (char*)ch
        fli = ms.flictx
        ms.reset_entry = mark_foreign_frame(ld, st, fli, ms.reset_entry)
        ms.flictx = ld.fliframes[fli].parent
    end
    ms.reset_entry = early_reset_vars(ld, st, ch.mark, ms.reset_entry)
    # G1-5: needsRelocation(&ch->mark.trailtop); alien_into_relocation_chain(&ch->mark.trailtop, STG_TRAIL, STG_LOCAL)
    return nothing
end

# `fr->clause->value.clause->codes[0] == encode(T_TRIE_GEN2) || ... T_TRIE_GEN3` (pl-gc.c mark_environments)
@inline function _gc_is_trie_gen(f::localFrame{T})::Bool where {T}
    c1 = (f.clause::ClauseRef{T}).clause.codes[1]
    return c1 == T_TRIE_GEN2 || c1 == T_TRIE_GEN3
end

# PORT: pl-gc.c mark_environments
# DIVERGES: `pc` is an index into the frame's clause codes (0 = NULL); `vm_state` positions are as in
# pl-gcmark.jl; the result is the QUERY index the walk reached (0 = NULL: the walk came from a
# choicepoint, whose frames are not cleared). `wasFrame` is not checked.
"""
    mark_environments(ld, st, ms, fr, pc) -> Int

Mark the variables of frame `fr` and of its parents that the continuation (resuming at `pc`) reads, and
mark their frames; return the query frame the chain ends in (pl-gc.c).
"""
function mark_environments(
    ld::PL_local_data{T}, st::gc_mark_counts, ms::mark_state, fr::Int, pc::Int
)::Int where {T}
    qf = 0
    while fr != 0
        f = ld.frames[fr]
        pred = f.predicate::Definition{T}
        ws = gc_walk_state(fr, f.base, pred.arity, 0)
        if (f.flags & FR_MARKED) == 0
            f.flags |= FR_MARKED
            ws.flags = GCM_CLEAR
        else
            ws.flags = 0
        end

        if (pred.flags & P_FOREIGN) != 0 || pc == 0 || f.clause === nothing
            mark_arguments(ld, st, fr)
        elseif _gc_is_trie_gen(f)
            mark_trie_gen(ld, st, fr)
        else
            cl = (f.clause::ClauseRef{T}).clause
            ws.unmarked = gc_slots_in_frame(ld, fr, pc)
            ws.envtop = argFrameP(f.base, ws.unmarked)
            argp0 = 0
            if fr == ms.vm.frame && pc == ms.vm.pc_start_vmi
                argp0 = ms.vm.argp0
                ws.ARGP = ms.vm.argp
                ws.adepth = ms.vm.adepth
                mark_new_arguments(ld, st, ms.vm)
            end
            walk_and_mark_gc(ld, st, ws, cl.codes, pc, I_EXIT)
            if argp0 != 0 && !is_marked(ld.slots[argp0 + 1])        # see (**)
                mark_local_variable(ld, st, -(argp0 + 1))
            end
            if (f.flags & FR_WATCHED) != 0                          # see (***)
                slots = gc_slots_in_frame(ld, fr, pc)
                sp = argFrameP(f.base, 0)
                for i in 0:(slots - 1)
                    is_marked(ld.slots[sp + i + 1]) ||
                        mark_local_variable(ld, st, -(sp + i + 1))
                end
            end
        end

        (ws.flags & GCM_CLEAR) == 0 && return 0                     # from choicepoint
        if f.parent != 0
            pc = f.programPointer.pc
            fr = f.parent
        else
            qf = queryOfFrame(ld, fr)
            se = ld.queries[qf].saved_environment
            se != 0 && mark_arguments(ld, st, se)                   # (*)
            break
        end
    end
    return qf
end

# PORT: pl-gc.c mark_choicepoints
"Mark what the choicepoints `ch` (an index) and their parents keep alive, with early reset of their trail ranges (pl-gc.c)."
function mark_choicepoints(
    ld::PL_local_data{T}, st::gc_mark_counts, ms::mark_state, ch::Int
)::Nothing where {T}
    while ch != 0
        early_reset_choicepoint(ld, st, ms, ch)
        c = ld.choices[ch]
        if c.type == CHP_JUMP
            mark_environments(ld, st, ms, c.frame, c.value_pc)
        elseif c.type == CHP_CLAUSE
            fr = c.frame
            mark_alt_clauses(ld, st, fr, c.value_clause.cref)
            f = ld.frames[fr]
            if (f.flags & FR_MARKED) == 0
                f.flags |= FR_MARKED
                mark_environments(ld, st, ms, f.parent, f.programPointer.pc)
            end
        elseif c.type == CHP_DEBUG || c.type == CHP_CATCH
            mark_environments(ld, st, ms, c.frame, 0)
        end                                                         # CHP_TOP: nothing
        ch = c.parent
    end
    return nothing
end

# PORT: pl-gc.c mark_query_stacks
"Mark the environments and the choicepoints of one query; return its query index (pl-gc.c)."
function mark_query_stacks(
    ld::PL_local_data{T}, st::gc_mark_counts, ms::mark_state, fr::Int, ch::Int, pc::Int
)::Int where {T}
    qf = mark_environments(ld, st, ms, fr, pc)
    mark_choicepoints(ld, st, ms, ch)
    return qf
end

# PORT: pl-gc.c mark_stacks
# DIVERGES: a parent query that is inside the VM (`registers.fr != 0`) needs the VM state of that query
# (`get_vmi_state(pqf, &sub_state)`, pin pl-gc.c:3725), which G1-2 builds: it is passed as the callback
# `vmi_state_of(ld, query_index) -> vm_state`, and without one this is a named refusal (a
# NotPortedError naming G1-2). The statistics line (`MSG_GC_STATS`) is not kept.
"""
    mark_stacks(ld, st, vm; vmi_state_of=nothing)

Mark the local stack from the safe point `vm` outward through the queries, the choicepoints and the
foreign frames (pl-gc.c); the trail is walked once from the top by early reset.
"""
function mark_stacks(
    ld::PL_local_data{T}, st::gc_mark_counts, vm::vm_state; vmi_state_of=nothing
)::Nothing where {T}
    ms = mark_state(vm)
    ms.reset_entry = length(ld.trail)                   # state.reset_entry = tTop - 1
    ms.flictx = ld.fli_context
    st.trailcells_deleted = 0
    fr = vm.frame
    ch = vm.choice
    pc = vm.pc_start_vmi
    while fr != 0
        qf = mark_query_stacks(ld, st, ms, fr, ch, pc)
        qf == 0 && error("mark_stacks: the walk of frame $(fr) reached no query frame")
        q = ld.queries[qf]
        q.parent == 0 && break                          # same code in checkStacks()
        pqf = q.parent
        pq = ld.queries[pqf]
        if pq.registers_fr != 0
            vmi_state_of === nothing && throw(
                NotPortedError(
                    ld.placeholder, "get_vmi_state of a parent query (pl-gc.c:3725)",
                    "G1-2"
                )
            )
            sub = vmi_state_of(ld, pqf)::vm_state
            sub.choice = q.saved_bfr
            ms.vm = sub
            fr = pq.registers_fr
            pc = sub.pc_start_vmi
        else
            fr = q.saved_environment
            pc = 0
        end
        ch = q.saved_bfr
    end
    while ms.flictx != 0
        ms.reset_entry = mark_foreign_frame(ld, st, ms.flictx, ms.reset_entry)
        ms.flictx = ld.fliframes[ms.flictx].parent
    end
    return nothing
end

# PORT: pl-gc.c mark_phase
# DIVERGES: the statistics and the `CHK_SECURE` checks are not kept; `st` is passed where upstream has the
# `total_marked` global; the roots that upstream's caller (`garbageCollect`) converts to term references
# before the mark phase (`gvars_to_term_refs`, `argument_stack_to_term_refs`, `link_attvars`) are made by
# the caller of this function, as upstream's.
"Mark phase: set the MARK bit of every cell of the global stack that is reachable (pl-gc.c); moves and frees nothing."
function mark_phase(
    ld::PL_local_data{T}, st::gc_mark_counts, vm::vm_state; vmi_state_of=nothing
)::Nothing where {T}
    st.total_marked = 0
    mark_term_refs(ld, st)
    mark_stacks(ld, st, vm; vmi_state_of=vmi_state_of)
    return nothing
end

# ── unmarking the frames (pl-gc.c unmark_environments, unmark_choicepoints, unmark_stacks) ────────
# PORT: pl-gc.c unmark_environments
# DIVERGES: the debug counters `LD->gc._local_frames` are not kept; the marks of the CELLS are cleared by
# the sweep (G1-5), these functions clear the frame flag `mask` (`FR_MARKED`, `FR_MARKED_PRED`) only.
"Clear `mask` in the flags of frame `fr` and of its parents while set; return the query the chain ends in, or 0 (pl-gc.c)."
function unmark_environments(ld::PL_local_data{T}, fr::Int, mask::UInt32)::Int where {T}
    fr == 0 && return 0
    while true
        f = ld.frames[fr]
        (f.flags & mask) == 0 && return 0
        f.flags &= ~mask
        f.parent != 0 || return queryOfFrame(ld, fr)    # Prolog --> C --> Prolog calls
        fr = f.parent
    end
end

# PORT: pl-gc.c unmark_choicepoints
"Clear `mask` in the frames of the choicepoints `ch` and their parents (pl-gc.c)."
function unmark_choicepoints(ld::PL_local_data{T}, ch::Int, mask::UInt32)::Nothing where {T}
    while ch != 0
        c = ld.choices[ch]
        unmark_environments(ld, c.frame, mask)
        ch = c.parent
    end
    return nothing
end

# PORT: pl-gc.c unmark_stacks
"Clear `mask` in all the frames reachable from `fr` and `ch`, through the parent queries (pl-gc.c)."
function unmark_stacks(
    ld::PL_local_data{T}, fr::Int, ch::Int, mask::UInt32
)::Nothing where {T}
    while fr != 0
        qf = unmark_environments(ld, fr, mask)
        qf == 0 && return nothing                       # (upstream asserts a query here)
        unmark_choicepoints(ld, ch, mask)
        q = ld.queries[qf]
        q.parent == 0 && break
        pq = ld.queries[q.parent]
        fr = pq.registers_fr != 0 ? pq.registers_fr : q.saved_environment
        ch = q.saved_bfr
    end
    return nothing
end
