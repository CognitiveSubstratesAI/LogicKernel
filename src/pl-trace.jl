# UPSTREAM: swipl-devel src/pl-trace.c @ 18168e629eab
# UPSTREAM: swipl-devel src/pl-trace.h @ 18168e629eab
# CLASS: code
# COPYRIGHT: Copyright (c)  1985-2025, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# What the kernel takes from SWI-Prolog's tracer support (pl-trace.c): the two built-ins that report
# POSITIONS on the local stack — `prolog_current_frame/1` (registered by pl-ext.c's FRG table, so
# called with the `a1` convention, `I_FCALLDET1`) and `prolog_current_choice/1` (a `PRED_DEF`,
# `I_FCALLDETVA`). Their differences are V3's oracle for frame and choice-point placement: a
# position is a word offset from `lBase`, so the kernel's equals swipl's (src/pl-incl.jl § the local
# stack). The debugger itself is deferred (DBG1). Since R2 F1c: `debugmode` and `tracemode`, the two functions the flag `debug` calls
# (pl-prologflag.c set_flag_value), over the debugger-status fields of the local data (`ld.debugstatus_*`, src/pl-global.jl).
# Since R2 TOP1: `resetTracer` and `enable_debug_on_interrupt`, which `resetProlog` and `query_loop` (src/pl-pro.jl) call.

# PORT: pl-trace.c PL_unify_frame
"Unify `t` with frame `fr`'s position, or `none` for no frame (pl-trace.c)."
function PL_unify_frame(ld::PL_local_data{T}, t::term_t, fr::Int)::Bool where {T}
    if fr != 0
        b = ld.frames[fr].base
        @assert 0 <= b < ld.lTop                        # fr >= lBase && fr < lTop
        return PL_unify_integer(ld, t, b)               # (Word)fr - (Word)lBase
    end
    return PL_unify_atom(ld, t, mk_sym(T, :none))
end

# PORT: pl-trace.c PL_put_frame
"Make `t` hold frame `fr`'s position, or `none` for no frame (pl-trace.c): the `frame_finished` event's argument."
function PL_put_frame(ld::PL_local_data{T}, t::term_t, fr::Int)::Bool where {T}
    if fr != 0
        b = ld.frames[fr].base
        @assert 0 <= b < ld.lTop                        # fr >= lBase && fr < lTop
        return PL_put_intptr(ld, t, b)                  # (Word)fr - (Word)lBase
    end
    return PL_put_atom(ld, t, mk_sym(T, :none))
end

# PORT: pl-trace.c PL_unify_choice
"Unify `t` with choice point `ch`'s position, or `none` for none (pl-trace.c)."
function PL_unify_choice(ld::PL_local_data{T}, t::term_t, ch::Int)::Bool where {T}
    if ch != 0
        b = ld.choices[ch].base
        @assert 0 <= b < ld.lTop                        # ch >= lBase && ch < lTop
        return PL_unify_integer(ld, t, b)               # (Word)ch - (Word)lBase
    end
    return PL_unify_atom(ld, t, mk_sym(T, :none))
end

# PORT: pl-trace.c put_frame_goal
# DIVERGES: on the cells. A frame's arguments all lie on the GLOBAL stack (a caller's fresh variable
# is a global cell: `B_VOID`, `B_ARGFIRSTVAR`), below the compound laid here, so upstream's
# `a > argp` branch (a LOCAL variable, newer than the goal, bound to the goal's argument) cannot
# arise; its other branch, `Trail(&argp[i], makeRefG(a))`, binds a cell of the new compound — above
# `mark_bar`, which `Trail` does not record — so it is the store `_cell_link!` makes (`linkValI`: an
# unbound or attributed cell its reference, any other term its word). No `ensureTrailSpace` (the
# trail is a vector).
# Its tracer callers (pl-trace.c:1165, :1282, :1334, :2583) are not ported; SSU's error is the first.
"""
    put_frame_goal(ld, goal, fr) -> Bool

Unify the fresh term reference `goal` with the goal of frame `fr` (pl-trace.c): its predicate's
name applied to the frame's arguments as they are now, qualified `Module:Goal` when the predicate's
module is not `user` and is not a system module.
"""
function put_frame_goal(ld::PL_local_data{T}, goal::term_t, fr::Int)::Bool where {T}
    gd = _query_gd(ld)
    f = ld.frames[fr]
    def = f.predicate::Definition{T}
    argc = def.arity

    PL_unify_functor(ld, goal, def.name, argc) || return false
    if argc > 0
        argv = argFrameP(f.base, 0)                     # Word argv = argFrameP(frame, 0)
        _, gw, _ = _deref_loc(ld, -(goal + 1))          # argp = valTermRef(goal); deRef(argp)
        argp = valPtr(gw)                               # argp = argTermP(*argp, 0), less one
        for i in 1:argc
            _cell_link!(ld, argp + i, argv + i)         # deRef2(argv+i, a); argp[i] = linked a
        end
    end

    m = gd.modules[def.module_]
    if m.index != MODULE_user(gd).index && ((m.flags & M_SYSTEM) == 0 || SYSTEM_MODE(ld))   # pl-trace.c:1009
        a = PL_new_term_ref(ld)
        a == 0 && return false
        PL_put_atom(ld, a, m.atom)                      # PL_put_atom(a, def->module->name)
        colon2 = lookupFunctorDef(ld.functors, _atom_word!(ld, mk_sym(T, :(:))), 2)
        return PL_cons_functor(ld, goal, colon2, a, goal)   # FUNCTOR_colon2
    end

    return true
end

# PORT: pl-trace.c pl_prolog_current_frame
# DIVERGES: "that's me" compares the frame's predicate with this built-in by name, arity and
# `P_FOREIGN` — upstream compares `impl.foreign.function` with the C function's address, which a
# table index (decision 5) is not; only a registered built-in is foreign. (The index would serve if
# qualified by its table, FRG or PRED_DEF, both numbered from 1; with the built-ins all in `system`
# and no `PL_register_foreign`, the name test is equivalent.)
"`prolog_current_frame/1` (pl-trace.c): the running frame's position — the caller's, not this call's."
function pl_prolog_current_frame(ld::PL_local_data{T}, frame::term_t)::foreign_t where {T}
    fr = ld.environment_frame
    def = ld.frames[fr].predicate::Definition{T}
    if (def.flags & P_FOREIGN) != 0 && def.arity == 1 &&
        def.functor_name == sym_key(mk_sym(T, :prolog_current_frame))
        fr = parentFrame(ld, fr)                        # thats me!
    end
    return PL_unify_frame(ld, frame, fr) ? FTRUE : FFALSE
end

# PORT: pl-trace.c pl_notrace
# (FRG("notrace", 0, pl_notrace, NOTRACE), pl-ext.c:141 at the pin 18168e62; pl-trace.c:2292-2295)
# DIVERGES: the local data is an argument (upstream's `GET_LD` inside `tracemode`); the pin's `#else /*O_DEBUGGER*/` stub
# (`tracemode` returning true) has no counterpart: the kernel's `tracemode` is the O_DEBUGGER one above.
"`notrace/0` (pl-trace.c): switch the trace mode off (`tracemode(false, NULL)`)."
function pl_notrace(ld::PL_local_data{T})::foreign_t where {T}
    return tracemode(ld, false, nothing) ? FTRUE : FFALSE
end

# PORT: pl-trace.c prolog_current_choice as pl_prolog_current_choice1_va
# (PRED_IMPL("prolog_current_choice", 1, prolog_current_choice, 0))
"`prolog_current_choice/1` (pl-trace.c): the newest choice point's position (not the debugger's)."
function pl_prolog_current_choice1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    ch = ld.BFR                                         # LD->choicepoints
    while ch != 0 && ld.choices[ch].type == CHP_DEBUG
        ch = ld.choices[ch].parent
    end
    if ch != 0
        return PL_unify_choice(ld, A1, ch) ? FTRUE : FFALSE
    end
    return FFALSE
end

# PORT: pl-trace.c PL_get_frame
# (pl-trace.c:115 at the pin 18168e62; `static int PL_get_frame` in the pin, unchanged in substance at af9e2e7e)
# DIVERGES: returns `(ok, fr)` where upstream writes `*fr` and returns a bool: `fr` is the pool INDEX of the frame (`existingFrame`,
# src/pl-wam.jl, which takes the position `PL_unify_frame` hands out), 0 for upstream's NULL (the atom `none`). `PL_get_intptr` is
# `PL_get_long` (a `long` is 64 bits).
"The frame term reference `t` holds — a position or `none` — as `(true, index)` (0 for `none`), else `(false, 0)` (pl-trace.c)."
function PL_get_frame(ld::PL_local_data{T}, t::term_t)::Tuple{Bool, Int} where {T}
    i = PL_get_long(ld, t)                              # PL_get_intptr(r, &i)
    if i !== nothing
        f = existingFrame(ld, i)                        # existingFrame((LocalFrame)((Word)lBase + i))
        f != 0 && return (true, f)
    else
        a = PL_get_atom(ld, t)
        if a !== nothing && sym_key(a) == sym_key(mk_sym(T, :none))     # a == ATOM_none
            return (true, 0)                            # *fr = NULL
        end
    end
    return (false, 0)
end

# PORT: pl-trace.c is_meta_call
# (pl-trace.c:200 at the pin 18168e62: "True when `FR` is created through a meta-call"; unchanged at af9e2e7e)
# DIVERGES: the frames are indices; `parent->clause->value.clause` is the parent's `ClauseRef`'s clause, and a parent without one (a
# foreign frame: upstream reads its `clause` word, which is the redo context) is no meta-call (false), not a read through a NULL.
"Whether frame `fr` was created through a meta-call: its parent's clause called it by `I_CALL1`, `I_CALLATM`, … (pl-trace.c)."
function is_meta_call(ld::PL_local_data{T}, fr::Int)::Bool where {T}
    f = ld.frames[fr]
    parent = f.parent
    if parent != 0
        pf = ld.frames[parent]
        if levelFrame(f) == levelFrame(pf) + 1 && ((f.predicate::Definition{T}).flags & P_FOREIGN) == 0
            pcr = pf.clause
            pcr === nothing && return false
            cl = pcr.clause
            cl === nothing && return false
            pc = prevPC(cl, f.programPointer)           # prevPC(cl, fr->programPointer)
            if pc !== nothing
                op = decode(pc)                         # fetchop(pc)
                if op == I_CALL1 || op == I_CALLATM || op == I_DEPARTATMV ||
                    op == I_CALLATMV || op == I_CALLM || op == I_CALLN
                    return true
                end
            end
        end
    end
    return false
end

# PORT: pl-trace.c isDebugFrame
# (pl-trace.c:242 at the pin 18168e62; af9e2e7e changes only the callers' neighbourhood)
# DIVERGES: the frame is an index; the `DEBUG(MSG_TRACE_FRAME, ...)` diagnostics are not ported (no debug-message channel keyed by
# topic); `ison(parent, FR_HIDE_CHILDS)` is the parent FRAME's flag, as upstream. `queryOfFrame(FR)` of a top frame is the
# query's record. `port` is not read (as upstream).
"Whether the call of frame `FR` must be visible in the tracer: user code, user hooks of system code, real meta-calls (pl-trace.c)."
function isDebugFrame(ld::PL_local_data{T}, FR::Int, port::Int)::Bool where {T}
    f = ld.frames[FR]
    def = f.predicate::Definition{T}
    (def.flags & TRACE_ME) == 0 && return false         # hidden predicate
    (def.flags & HIDE_CHILDS) == 0 && return true       # user pred

    parent = f.parent
    if parent != 0
        pdef = ld.frames[parent].predicate::Definition{T}
        mask = P_NOPROFILE | HIDE_CHILDS
        if (def.flags & mask) == mask && (pdef.flags & mask) == mask
            return false                                # noprof system-system
        end

        while parent != 0 && (((ld.frames[parent].predicate::Definition{T}).flags & P_NOPROFILE) != 0)
            parent = ld.frames[parent].parent           # parent=parent->parent
        end
    end

    if parent != 0
        pf = ld.frames[parent]
        if levelFrame(f) == levelFrame(pf) + 1
            # not last-call optimized
            if (((pf.predicate::Definition{T}).flags & HIDE_CHILDS) == 0)
                return true                             # user calls system
            end
            return false                               # system calls system
        else
            if (pf.flags & FR_HIDE_CHILDS) == 0 && is_meta_call(ld, FR)
                return true
            end
            return false
        end
    else
        qf = ld.queries[queryOfFrame(ld, FR)]
        return (qf.flags & PL_Q_NODEBUG) == 0
    end
end

# PORT: pl-trace.c findQuery
# (pl-trace.c:1779 at the pin 18168e62; unchanged at af9e2e7e)
# DIVERGES: the frame and the query are indices (0 = NULL).
"The query (an index) whose top frame is the oldest ancestor of `fr`, 0 for no frame (pl-trace.c)."
function findQuery(ld::PL_local_data{T}, fr::Int)::Int where {T}
    while fr != 0 && ld.frames[fr].parent != 0
        fr = ld.frames[fr].parent
    end
    fr != 0 && return queryOfFrame(ld, fr)
    return 0
end

# PORT: pl-trace.c hasAlternativesFrame
# (pl-trace.c:1790 at the pin 18168e62; unchanged at af9e2e7e)
# DIVERGES: frames, choice points and queries are indices; `(void *)ch < (void *)frame` compares their positions (`base`);
# `LD->choicepoints` is `ld.BFR`.
"Whether frame `frame` has a clause or jump choice point left, looking through the queries' saved states (pl-trace.c)."
function hasAlternativesFrame(ld::PL_local_data{T}, frame::Int)::Bool where {T}
    fr = ld.environment_frame
    ch = ld.BFR                                         # LD->choicepoints
    fbase = ld.frames[frame].base

    while true
        while ch != 0
            c = ld.choices[ch]
            c.base < fbase && return false              # (void *)ch < (void *)frame
            if c.frame == frame
                if c.type == CHP_CLAUSE || c.type == CHP_JUMP
                    return true
                end                                     # CHP_TOP, CHP_CATCH, CHP_DEBUG: continue
            end
            ch = c.parent
        end
        qi = findQuery(ld, fr)
        if qi != 0
            fr = ld.queries[qi].saved_environment
            ch = ld.queries[qi].saved_bfr
        else
            return false
        end
    end
end

# PORT: pl-trace.c alternativeFrame
# (pl-trace.c:1836 at the pin 18168e62; unchanged at af9e2e7e)
# DIVERGES: as `hasAlternativesFrame`; 0 is upstream's NULL. The `DEBUG(3, ...)` traces (`loffset`, `chp_chars`) are not ported.
"The frame of the first clause or jump choice point after those of `frame` (an index), 0 for none (pl-trace.c)."
function alternativeFrame(ld::PL_local_data{T}, frame::Int)::Int where {T}
    fr = ld.environment_frame
    ch = ld.BFR                                         # LD->choicepoints
    fbase = ld.frames[frame].base

    while true
        while ch != 0
            c = ld.choices[ch]
            c.base < fbase && return 0                  # (void *)ch < (void *)frame
            if c.frame == frame
                ch = c.parent                           # for(ch = ch->parent; ch; ch = ch->parent )
                while ch != 0
                    c2 = ld.choices[ch]
                    if c2.frame != frame && (c2.type == CHP_CLAUSE || c2.type == CHP_JUMP)
                        return c2.frame
                    end                                 # a choice of `frame` itself: skipped; the others: default: break
                    ch = c2.parent
                end
                return 0
            end
            ch = c.parent
        end
        qi = findQuery(ld, fr)
        if qi != 0
            fr = ld.queries[qi].saved_environment
            ch = ld.queries[qi].saved_bfr
        else
            return 0
        end
    end
end

# PORT: pl-trace.c clear_frame_vars
# (pl-trace.c:2433 at the pin 18168e62; unchanged at af9e2e7e)
# DIVERGES: frames, choice points and queries are indices, `(fr >= target)` a comparison of positions. `PC` is a `Code` (a code
# vector and an index) or `nothing` for NULL, and a JUMP choice's `value.pc` is `value_pc`, an index into its frame's clause code;
# `clearUninitialisedVarsFrame` is not called for a NULL or position-0 `PC` (upstream's own no-op). The function returns upstream's
# NULL (`QueryFrame`) as `nothing`. Upstream spins forever where it prints "FAILED to find frame (...) to clear!?" under
# `DEBUG(0, ...)` (the target is not on the chain walked), and where a top frame of the outermost query is still at or above the
# target; here that is an `error`. The `DEBUG` diagnostics and assertion are not ported.
"Clear (make variables) the uninitialised variables of frame `target` for the code position its newest callee returns to (pl-trace.c)."
function clear_frame_vars(ld::PL_local_data{T}, target::Int)::Nothing where {T}
    fr = ld.environment_frame
    ch = ld.BFR                                         # LD->choicepoints
    PC = nothing                                        # Code PC = NULL
    tbase = ld.frames[target].base

    while true
        while fr != 0 && ld.frames[fr].base >= tbase    # fr && fr >= target
            f = ld.frames[fr]
            if fr == target
                if PC !== nothing && PC.pc != 0
                    clearUninitialisedVarsFrame(ld, fr, PC.codes, PC.pc)
                end
                return nothing
            end

            PC = f.programPointer
            if f.parent != 0
                fr = f.parent
            else
                qf = ld.queries[queryOfFrame(ld, fr)]
                if qf.parent != 0
                    fr = qf.saved_environment
                    PC = nothing
                    ch = qf.saved_bfr
                else
                    error("clear_frame_vars: frame to clear not found on the environment chain")    # (upstream spins)
                end
            end
        end

        if ch != 0
            ch = ld.choices[ch].parent
            if ch != 0
                c = ld.choices[ch]
                fr = c.frame
                PC = nothing
                if c.type == CHP_JUMP
                    cr = fr != 0 ? ld.frames[fr].clause : nothing
                    cl = cr === nothing ? nothing : cr.clause
                    if cl !== nothing
                        PC = Code(cl, c.value_pc)       # PC = ch->value.pc
                    end
                end
                continue
            end
        end
        error("clear_frame_vars: FAILED to find frame to clear")    # (DEBUG(0, ...); upstream then loops)
    end
end

# PORT: pl-trace.c BeginPredDefs as PL_predicates_from_trace
# DIVERGES: the ported entry only (upstream's table also has `prolog_frame_attribute/3` and the
# other debugger predicates, pl-trace.c:2830-2840).
"pl-trace.c's registration table (`BeginPredDefs(trace)`): the ported entry."
const PL_predicates_from_trace = (
    PL_extension("prolog_current_choice", 1, pl_prolog_current_choice1_va, PL_FA_VARARGS),
)

# PORT: pl-trace.h DBG_ALL
"`debugmode`'s flag: switch debugging on in all queries (pl-trace.h)."
const DBG_ALL = UInt32(0x1)

# Not in pl-trace.c: pl-incl.h's SKIP_VERY_DEEP.
"The skip level of no skipping, `(size_t)-1` (pl-incl.h)."
const SKIP_VERY_DEEP = typemax(UInt)

# Not in pl-trace.c: pl-incl.h's SKIP_REDO_IN_SKIP.
"The skip level of a redo inside a skip, `SKIP_VERY_DEEP-1` (pl-incl.h)."
const SKIP_REDO_IN_SKIP = SKIP_VERY_DEEP - UInt(1)

# PORT: pl-trace.c debugmode
# DIVERGES: one engine, so the local data is its argument (never NULL) and the message is always sent by the calling engine
# (`set && ld == LD`); `old` is a `Ref{Bool}` or `nothing`. The messages go through the kernel's `printMessage`
# (a `silent` `debug_mode(Bool)`, print_message/2's since LB4 b2: a test reads it through a `user:message_hook/3` collector). DBG1 (the tracer) owns what follows, each
# a deferred part of the same function: `have_space_for_debugging` and `enlargeMinFreeStacks` (pl-trace.c:2163-2204, :2236-2241:
# they only enlarge `min_free` of the stacks and the kernel's stacks grow by doubling, src/pl-gc.jl), `qf->debugSave = true` of
# every query for `DBG_ALL` (:2246-2249: the kernel's query frame has no `debugSave` slot; `PL_Q_NODEBUG` is deferred as well,
# src/pl-wam.jl PL_open_query), and `validUserStreams` (:2269; the kernel's standard streams are always open).
"Set the debug mode of the engine `ld` to `doit`, writing the old mode to `old`; the run mode and `debugstatus.skiplevel` follow (pl-trace.c)."
function debugmode(
    ld::PL_local_data{T}, doit::Bool, old::Union{Nothing, Base.RefValue{Bool}},
    flags::UInt32
)::Bool where {T}
    set = false
    old === nothing || (old[] = ld.debugstatus_debugging)

    if ld.debugstatus_debugging != doit
        if doit
            ld.debugstatus_skiplevel = SKIP_VERY_DEEP       # debugstatus.skiplevel = SKIP_VERY_DEEP
            clearPrologRunMode!(ld, RUN_MODE_NORMAL)        # clearPrologRunMode(RUN_MODE_NORMAL)
        else
            setPrologRunMode!(ld, RUN_MODE_NORMAL)          # setPrologRunMode(RUN_MODE_NORMAL)
        end
        ld.debugstatus_debugging = doit                     # debugstatus.debugging = doit
        updateAlerted(ld)
        set = true
    elseif !doit
        setPrologRunMode!(ld, RUN_MODE_NORMAL)
    end

    if set
        return printMessage(                                # PL_FUNCTOR_CHARS, "debug_mode", 1, PL_BOOL, doit
            ld, :silent,
            _message_term(
                ld, :debug_mode,
                _err_atom(ld, mk_sym(T, doit ? Symbol("true") : Symbol("false")))
            )
        )
    end
    return true
end

# PORT: pl-trace.c tracemode
# DIVERGES: as `debugmode`; `LD->trace.find->searching = false` (the tracer's find state) is deferred (DBG1: the kernel has no `LD->trace`).
"Set the trace mode of the engine `ld` to `doit` (which also sets the debug mode), writing the old mode to `old` (pl-trace.c)."
function tracemode(
    ld::PL_local_data{T}, doit::Bool, old::Union{Nothing, Base.RefValue{Bool}}
)::Bool where {T}
    if doit
        debugmode(ld, true, nothing, UInt32(0))             # (the answer is not used upstream either)
        doit = true
    end

    old === nothing || (old[] = ld.debugstatus_tracing)

    if ld.debugstatus_tracing != doit
        ld.debugstatus_tracing = doit
        return printMessage(                                # PL_FUNCTOR_CHARS, "trace_mode", 1, PL_BOOL, doit
            ld, :silent,
            _message_term(
                ld,
                :trace_mode,
                _err_atom(ld, mk_sym(T, doit ? Symbol("true") : Symbol("false")))
            )
        )
    end
    if doit                                                 # make sure trace works inside skip
        ld.debugstatus_skiplevel = SKIP_VERY_DEEP
    end

    return true
end

# PORT: pl-trace.c resetTracer
# DIVERGES: the local data is an argument (upstream's `LD`). `debugstatus.suspendTrace` and `debugstatus.retryFrame` are the
# tracer's (DBG1) and the local data holds no field for them; the other three fields and the run mode are reset as upstream.
"Reset the debugger: tracing and debugging off, no skipping, the normal run mode (pl-trace.c)."
function resetTracer(ld::PL_local_data)::Nothing
    ld.debugstatus_tracing = false              # debugstatus.tracing      = false
    ld.debugstatus_debugging = false            # debugstatus.debugging    = false
    # debugstatus.suspendTrace = 0 (DBG1)
    ld.debugstatus_skiplevel = UInt(0)          # debugstatus.skiplevel    = 0
    # debugstatus.retryFrame   = 0 (DBG1)
    setPrologRunMode!(ld, RUN_MODE_NORMAL)      # setPrologRunMode(RUN_MODE_NORMAL)
    return nothing
end

# PORT: pl-trace.c enable_debug_on_interrupt
# DIVERGES: the local data is an argument. The signal half is the signal step's: `PL_signal(SIGINT, PL_interrupt)` (enable) and
# `terminate_on_signal(SIGINT)` (disable) are left to the signal step (owner: the signal step), so the flag `debug_on_interrupt` is set
# and cleared as upstream does, and an interrupt does not reach the debugger until that step lands.
"Switch the flag `debug_on_interrupt` on or off: false where it cannot be switched on (the flag `signals` is off) (pl-trace.c)."
function enable_debug_on_interrupt(ld::PL_local_data, enable::Bool)::Bool
    if enable
        truePrologFlag(ld, PLFLAG_SIGNALS) || return false
        # PL_signal(SIGINT, PL_interrupt)
        setPrologFlagMask!(ld, PLFLAG_DEBUG_ON_INTERRUPT)
    else
        # terminate_on_signal(SIGINT)
        clearPrologFlagMask!(ld, PLFLAG_DEBUG_ON_INTERRUPT)
    end
    return true
end
