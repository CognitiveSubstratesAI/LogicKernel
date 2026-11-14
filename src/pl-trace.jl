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

# PORT: pl-incl.h NO_PORT
"The no-port mask of the debugger's ports (pl-incl.h)."
const NO_PORT = Int(0x000)
# PORT: pl-incl.h CALL_PORT
"The call port's mask (pl-incl.h)."
const CALL_PORT = Int(0x001)
# PORT: pl-incl.h EXIT_PORT
"The exit port's mask (pl-incl.h)."
const EXIT_PORT = Int(0x002)
# PORT: pl-incl.h FAIL_PORT
"The fail port's mask (pl-incl.h)."
const FAIL_PORT = Int(0x004)
# PORT: pl-incl.h REDO_PORT
"The redo port's mask (pl-incl.h)."
const REDO_PORT = Int(0x008)
# PORT: pl-incl.h UNIFY_PORT
"The head-unification port's mask (pl-incl.h)."
const UNIFY_PORT = Int(0x010)
# PORT: pl-incl.h CUT_CALL_PORT
"The cut-call port's mask (pl-incl.h)."
const CUT_CALL_PORT = Int(0x040)
# PORT: pl-incl.h CUT_EXIT_PORT
"The cut-exit port's mask (pl-incl.h)."
const CUT_EXIT_PORT = Int(0x080)
# PORT: pl-incl.h EXCEPTION_PORT
"The exception port's mask (pl-incl.h)."
const EXCEPTION_PORT = Int(0x100)
# PORT: pl-incl.h CUT_PORT
"The two cut ports' mask (pl-incl.h)."
const CUT_PORT = CUT_CALL_PORT | CUT_EXIT_PORT
# PORT: pl-incl.h PORT_MASK
"The mask of all ports (pl-incl.h)."
const PORT_MASK = Int(0x1ff)

# ORIGINAL: the twin of pl-util.c setInteger (the kernel has no pl-util.jl; `predicateName`'s twin sits in src/pl-proc.jl alike).
# DIVERGES: `int *flag` is its current value in, the new value out: `nothing` is upstream's failure (`Old` does not unify, or `New` is no
# `int`: `PL_get_integer_ex` raised `type_error(integer, New)` or `representation_error(int)`), the caller stores the value only on success,
# as upstream's `PL_get_integer_ex(new, flag)` does.
"Unify `old` with the integer `cur`, then read `new` as a C `int` (pl-util.c setInteger): the new value, or `nothing` on failure."
function _trace_set_integer(
    ld::PL_local_data{T}, cur::Int, old::term_t, new::term_t
)::Union{Nothing, Int} where {T}
    PL_unify_integer(ld, old, cur) || return nothing
    return PL_get_integer_ex(ld, new)
end

# PORT: pl-trace.c pl_trace
# DIVERGES: the kernel has no tracer (no port actions, no interactive prompt, `tracePort` is unwritten): upstream's `trace/0` turns the
# tracer on and its next visible port stops in it. With no port visible (`'$visible'/2` = 0) the tracer cannot stop, and the call is
# upstream's `tracemode(true, NULL)`; with one visible it is refused by name BEFORE any state changes, so a program never runs
# believing it is traced.
"`trace/0`: switch tracing on (pl-trace.c); refused (`NotPortedError`, step DBG1) while a port is visible: the tracer is not ported."
function pl_trace(ld::PL_local_data{T})::foreign_t where {T}
    if (ld.debugstatus_visible & PORT_MASK) != 0
        throw(
            NotPortedError{T}(
                mk_sym(T, :trace), "trace/0 with a visible port: the tracer (pl-trace.c tracePort)", "DBG1"
            )
        )
    end
    return tracemode(ld, true, nothing) ? FTRUE : FFALSE
end

# PORT: pl-trace.c pl_notrace
"`notrace/0`: switch tracing off (pl-trace.c)."
pl_notrace(ld::PL_local_data{T}) where {T} = tracemode(ld, false, nothing) ? FTRUE : FFALSE

# PORT: pl-trace.c pl_tracing
"`tracing/0`: true while tracing (pl-trace.c)."
pl_tracing(ld::PL_local_data{T}) where {T} = ld.debugstatus_tracing ? FTRUE : FFALSE

# PORT: pl-trace.c pl_leash
"`\$leash(-Old, +New)`: the leashed ports' mask, read and set (pl-trace.c)."
function pl_leash(ld::PL_local_data{T}, old::term_t, new::term_t)::foreign_t where {T}
    n = _trace_set_integer(ld, ld.debugstatus_leashing, old, new)         # setInteger(&debugstatus.leashing, old, new)
    n === nothing && return FFALSE
    ld.debugstatus_leashing = n
    return FTRUE
end

# PORT: pl-trace.c pl_visible
"`\$visible(-Old, +New)`: the visible ports' mask, read and set (pl-trace.c)."
function pl_visible(ld::PL_local_data{T}, old::term_t, new::term_t)::foreign_t where {T}
    n = _trace_set_integer(ld, ld.debugstatus_visible, old, new)          # setInteger(&debugstatus.visible, old, new)
    n === nothing && return FFALSE
    ld.debugstatus_visible = n
    return FTRUE
end

# PORT: pl-trace.c PL_get_frame
# DIVERGES: returns the frame's index (0: upstream's `*fr = NULL`, the atom `none`), or `nothing` for upstream's false (no integer
# naming a live frame, and not `none`). The position goes through `existingFrame` (src/pl-wam.jl).
"The frame term reference `r` names: its index, 0 for `none`, `nothing` when `r` is no frame reference (pl-trace.c)."
function PL_get_frame(ld::PL_local_data{T}, r::term_t)::Union{Nothing, Int} where {T}
    i = PL_get_intptr(ld, r)
    if i !== nothing
        f = existingFrame(ld, i)
        f != 0 && return f
    else
        a = PL_get_atom(ld, r)
        if a !== nothing && kind(a) === SYM && sym_key(a) == sym_key(mk_sym(T, :none))
            return 0
        end
    end
    return nothing
end

# PORT: pl-trace.c PL_get_choice
# DIVERGES: the choice point is the record whose `base` is the position (upstream reads the memory there and tests `valid_choice`: its type
# is a `choice_type` and its frame lies on the local stack); a position no record holds raises `existence_error(choice, R)` as an
# out-of-range one does upstream. A record with no frame (0) is accepted (upstream's `onStack(local, ch->frame)` is for a frame; a top choice point's may be none here: to be
# confirmed at the gate). Returns the record's index, or `nothing` with the error raised.
"The choice point term reference `r` names — an index — or `nothing` after raising `type_error(choice, R)` or `existence_error(choice, R)` (pl-trace.c)."
function PL_get_choice(ld::PL_local_data{T}, r::term_t)::Union{Nothing, Int} where {T}
    i = PL_get_intptr(ld, r)
    if i !== nothing
        ch = ld.nchoices
        while ch != 0 && ld.choices[ch].base > i
            ch -= 1
        end
        if ch != 0 && ld.choices[ch].base == i && 0 <= i < ld.lTop
            fr = ld.choices[ch].frame                   # onStack(local, ch->frame)
            (fr == 0 || 0 <= ld.frames[fr].base < ld.lTop) && return ch
        end
        PL_error(ld, ERR_EXISTENCE, mk_sym(T, :choice), r)
        return nothing
    end
    PL_error(ld, ERR_TYPE, mk_sym(T, :choice), r)
    return nothing
end

# PORT: pl-trace.c findQuery
# DIVERGES: returns the query record's index (0 for upstream's NULL), by `queryOfFrame`.
"The query record of the query frame `fr` (an index) runs under, 0 for no frame (pl-trace.c)."
function findQuery(ld::PL_local_data{T}, fr::Int)::Int where {T}
    while fr != 0 && ld.frames[fr].parent != 0
        fr = ld.frames[fr].parent
    end
    fr != 0 && return queryOfFrame(ld, fr)
    return 0
end

# PORT: pl-trace.c hasAlternativesFrame
# DIVERGES: the frames and choice points are indices; their positions are the records' `base`. The walk crosses into the parent query as upstream's
# (`saved_environment`, `saved_bfr`).
"Whether frame `frame` (an index) has a clause or jump choice point left (pl-trace.c)."
function hasAlternativesFrame(ld::PL_local_data{T}, frame::Int)::Bool where {T}
    fbase = ld.frames[frame].base
    fr = ld.environment_frame
    ch = ld.BFR
    while true
        while ch != 0
            c = ld.choices[ch]
            c.base < fbase && return false              # (void *)ch < (void *)frame
            if c.frame == frame && (c.type == CHP_CLAUSE || c.type == CHP_JUMP)
                return true
            end
            ch = c.parent                               # CHP_TOP, CHP_CATCH, CHP_DEBUG: continue
        end
        q = findQuery(ld, fr)
        q == 0 && return false
        fr = ld.queries[q].saved_environment
        ch = ld.queries[q].saved_bfr
    end
end

# PORT: pl-trace.c alternativeFrame
# DIVERGES: as `hasAlternativesFrame`; 0 is upstream's NULL. No DEBUG output.
"The frame of the next clause or jump choice point after `frame`'s own (an index), or 0 (pl-trace.c)."
function alternativeFrame(ld::PL_local_data{T}, frame::Int)::Int where {T}
    fbase = ld.frames[frame].base
    fr = ld.environment_frame
    ch = ld.BFR
    while true
        while ch != 0
            c = ld.choices[ch]
            c.base < fbase && return 0
            if c.frame == frame
                ch2 = c.parent
                while ch2 != 0
                    c2 = ld.choices[ch2]
                    if c2.frame != frame && (c2.type == CHP_CLAUSE || c2.type == CHP_JUMP)
                        return c2.frame
                    end
                    ch2 = c2.parent
                end
                return 0
            end
            ch = c.parent
        end
        q = findQuery(ld, fr)
        q == 0 && return 0
        fr = ld.queries[q].saved_environment
        ch = ld.queries[q].saved_bfr
    end
end

# PORT: pl-comp.c prevPC
# DIVERGES: `pc` is an index into `cl.codes` (1-based), the result an index or 0 (upstream's NULL); the step is `1 + codeTable(op).arguments`, as
# everywhere in the kernel (src/pl-gc.jl `clearUninitialisedVarsFrame`): the operands of the indirect instructions (strings, floats, big numbers)
# are one slot each here, as the kernel's code keeps them.
"The start of the instruction in `cl` that ends at `pc`, or 0 (pl-comp.c)."
function prevPC(cl::Clause{T}, pc::Int)::Int where {T}
    codes = cl.codes
    n_codes = length(codes)
    if 1 <= pc <= n_codes
        p = 1
        while p <= n_codes
            n = p + 1 + codeTable(codes[p]).arguments   # stepPC(p)
            n == pc && return p
            p = n
        end
    end
    return 0
end

# PORT: pl-trace.c is_meta_call
# DIVERGES: the parent's clause may be missing (a foreign parent has none; upstream dereferences it): that is no meta call.
"Whether frame `fr` (an index) was created through a meta-call (pl-trace.c)."
function is_meta_call(ld::PL_local_data{T}, fr::Int)::Bool where {T}
    f = ld.frames[fr]
    p = f.parent
    if p != 0 && Int(levelFrame(f)) == Int(levelFrame(ld.frames[p])) + 1 &&
        ((f.predicate::Definition{T}).flags & P_FOREIGN) == 0
        pcr = ld.frames[p].clause
        pcr === nothing && return false
        cl = pcr.clause
        cl === nothing && return false
        pc = prevPC(cl, f.programPointer.pc)
        if pc != 0
            op = cl.codes[pc]
            return op == I_CALL1 || op == I_CALLATM || op == I_DEPARTATMV ||
                   op == I_CALLATMV || op == I_CALLM || op == I_CALLN
        end
    end
    return false
end

# PORT: pl-trace.c isDebugFrame
# DIVERGES: the `port` argument (read only by upstream's DEBUG output) is not taken; no DEBUG output.
"Whether the call of frame `fr` (an index) is visible in the tracer (pl-trace.c)."
function isDebugFrame(ld::PL_local_data{T}, fr::Int)::Bool where {T}
    f = ld.frames[fr]
    def = f.predicate::Definition{T}
    (def.flags & TRACE_ME) == 0 && return false         # hidden predicate
    (def.flags & HIDE_CHILDS) == 0 && return true       # user pred

    parent = f.parent
    if parent != 0
        pdef = ld.frames[parent].predicate::Definition{T}
        noprof_hide = P_NOPROFILE | HIDE_CHILDS
        if (def.flags & noprof_hide) == noprof_hide &&
            (pdef.flags & noprof_hide) == noprof_hide
            return false                                # noprof system-system
        end
        while parent != 0
            qdef = ld.frames[parent].predicate::Definition{T}
            (qdef.flags & P_NOPROFILE) != 0 || break
            parent = ld.frames[parent].parent
        end
    end

    if parent != 0
        pf = ld.frames[parent]
        if Int(levelFrame(f)) == Int(levelFrame(pf)) + 1
            # not last-call optimized
            return ((pf.predicate::Definition{T}).flags & HIDE_CHILDS) == 0     # user calls system / system calls system
        else
            return (pf.flags & FR_HIDE_CHILDS) == 0 && is_meta_call(ld, fr)
        end
    end
    q = queryOfFrame(ld, fr)
    return (ld.queries[q].flags & PL_Q_NODEBUG) == 0
end

# PORT: pl-trace.c clear_frame_vars
# DIVERGES: the walk ends (returns) when it reaches the top query with no `fr` left, where upstream's loop would spin; the code a resume point
# indexes is the frame's `programPointer.codes` (a child frame's) or the parent clause's (a `CHP_JUMP` choice point's `value_pc`), `pc` 0 being upstream's
# `PC == NULL`; `clearUninitialisedVarsFrame` (src/pl-gc.jl) is told the codes it walks. The query-frame return value (a QueryFrame) is not
# returned: no caller reads it.
"Set the variables of frame `target` (an index) that its clause has yet to initialise to variables (pl-trace.c)."
function clear_frame_vars(ld::PL_local_data{T}, target::Int)::Nothing where {T}
    tbase = ld.frames[target].base
    fr = ld.environment_frame
    ch = ld.BFR
    pcodes = ld.null_code.codes
    pc = 0
    while true
        while fr != 0 && ld.frames[fr].base >= tbase
            if fr == target
                pcr = ld.frames[fr].clause
                if pc > 0 && pcr !== nothing && pcr.clause !== nothing &&
                    ((ld.frames[fr].predicate::Definition{T}).flags & P_FOREIGN) == 0
                    clearUninitialisedVarsFrame(ld, fr, pcodes, pc)
                end
                return nothing
            end
            pp = ld.frames[fr].programPointer
            pcodes = pp.codes
            pc = (1 <= pp.pc <= length(pp.codes)) ? pp.pc : 0       # PC = fr->programPointer
            if ld.frames[fr].parent != 0
                fr = ld.frames[fr].parent
            else
                qf = ld.queries[queryOfFrame(ld, fr)]
                if qf.parent != 0
                    fr = qf.saved_environment
                    pc = 0
                    ch = qf.saved_bfr
                else
                    return nothing                      # upstream would spin: no frame left to clear
                end
            end
        end
        if ch != 0
            ch = ld.choices[ch].parent
            if ch != 0
                fr = ld.choices[ch].frame
                if ld.choices[ch].type == CHP_JUMP && fr != 0
                    pcr = ld.frames[fr].clause
                    if pcr !== nothing && pcr.clause !== nothing
                        pcodes = pcr.clause.codes
                        pc = ld.choices[ch].value_pc
                    else
                        pc = 0
                    end
                else
                    pc = 0
                end
                continue
            end
        end
        return nothing                                  # FAILED to find the frame to clear
    end
end

# PORT: pl-trace.c prolog_frame_attribute
# DIVERGES: a frame is an index and cannot move (no stack shift), so upstream's `fref` save/restore and `ensureGlobalSpace` are left out; the
# arguments of a frame are read from `argFrameP`, a position that is also a `term_t`. `depth_limit_exceeded` is false: no depth limit
# is kept (`call_with_depth_limit`'s `saved_depth_limit` is `DEPTH_NO_LIMIT`, so the test of upstream's body is false). `pc` is the offset in the kernel's
# code of the parent clause (`programPointer.pc - 1`); the kernel's codes carry the literal operands as one slot each, so the offset equals upstream's only
# where upstream's operands are one word as well. `value` is stripped of its module in the context module as upstream's `PL_strip_module(value, &m, value)`.
"`prolog_frame_attribute(+Frame, +Key, -Value)` (pl-trace.c): read one attribute of a frame."
function prolog_frame_attribute(
    ld::PL_local_data{T}, frame::term_t, what::term_t, value::term_t
)::Bool where {T}
    gd = _query_gd(ld)
    fr = PL_get_frame(ld, frame)
    fr === nothing && return PL_error(ld, ERR_TYPE, mk_sym(T, :frame_reference), frame)
    fr == 0 && return false                             # frame == 'none'
    na = PL_get_name_arity(ld, what)
    na === nothing && return PL_error(ld, ERR_TYPE, mk_sym(T, :callable), what)
    key, arity = na
    ok, m = PL_strip_module(gd, ld, value, 0, value)
    ok || return false

    ld.frames[fr].flags |= FR_NOTIFY                    # set(fr, FR_NOTIFY)
    f = ld.frames[fr]
    def = f.predicate::Definition{T}

    if _fa_key(T, key, :argument) && arity == 1
        arg = PL_new_term_ref(ld)
        _PL_get_arg(ld, 1, what, arg)                   # PL_get_arg_ex: `what` is a compound here
        argn = PL_get_size_ex(ld, arg)
        argn === nothing && return false
        if argn < 1
            return PL_error(ld, ERR_DOMAIN, mk_sym(T, :natural), arg)
        end
        cr = f.clause
        if (def.flags & P_FOREIGN) != 0 || cr === nothing || cr.clause === nothing
            argn > def.arity && return false
        else
            argn > Int(cr.clause.prolog_vars) && return false
        end
        return PL_unify(ld, value, argFrameP(f.base, argn - 1))
    end

    if !(arity == 0 || (arity == 1 && _fa_key(T, key, :parent_goal)))
        return PL_error(ld, ERR_DOMAIN, mk_sym(T, :frame_attribute), what)
    end

    result = PL_new_term_ref(ld)
    if _fa_key(T, key, :level)
        PL_put_integer(ld, result, Int(levelFrame(f)))
    elseif _fa_key(T, key, :has_alternatives)
        PL_put_atom(ld, result, mk_sym(T, hasAlternativesFrame(ld, fr) ? Symbol("true") : Symbol("false")))
    elseif _fa_key(T, key, :skipped)
        PL_put_atom(ld, result, mk_sym(T, (f.flags & FR_SKIPPED) != 0 ? Symbol("true") : Symbol("false")))
    elseif _fa_key(T, key, :alternative)
        alt = alternativeFrame(ld, fr)
        alt == 0 && return false
        PL_put_frame(ld, result, alt)
    elseif _fa_key(T, key, :parent)
        parent = parentFrame(ld, fr)
        parent == 0 && return false
        clear_frame_vars(ld, parent)
        PL_put_frame(ld, result, parent)
    elseif _fa_key(T, key, :top)
        PL_put_atom(ld, result, mk_sym(T, f.parent != 0 ? Symbol("false") : Symbol("true")))
    elseif _fa_key(T, key, :context_module)
        PL_put_atom(ld, result, gd.modules[contextModule(gd, ld, fr)].atom)
    elseif _fa_key(T, key, :clause)
        cr = f.clause
        if (def.flags & P_FOREIGN) == 0 && cr !== nothing && cr.clause !== nothing &&
            def !== gd.procedures_dc_call_prolog0.definition &&
            def !== gd.procedures_dcall1.definition
            PL_unify_clref(gd, ld, result, cr.clause) || return false
        else
            return false
        end
    elseif _fa_key(T, key, :goal)
        put_frame_goal(ld, result, fr) || return false
    elseif _fa_key(T, key, :predicate_indicator)
        unify_definition(gd, ld, gd.modules[m], result, def, 0, GP_NAMEARITY) ||
            return false
    elseif _fa_key(T, key, :parent_goal)
        head = PL_new_term_ref(ld)
        a = PL_new_term_ref(ld)
        proc = get_procedure_find(gd, ld, value, head)  # get_procedure(value, &proc, head, GP_FIND)
        proc === nothing && return false
        pdef = proc.definition
        fid = PL_open_foreign_frame(ld)
        fid == 0 && return false
        while fr != 0
            while fr != 0 && ld.frames[fr].predicate !== pdef
                fr = parentFrame(ld, fr)
            end
            if fr == 0
                PL_close_foreign_frame(ld, fid)
                return false                            # No frame running this predicate
            end
            garity = pdef.arity
            i = 0
            while i < garity
                _PL_get_arg(ld, i + 1, head, a)
                PL_unify(ld, a, argFrameP(ld.frames[fr].base, i)) || break  # Argument does not unify
                i += 1
            end
            if i == garity                              # All arguments unified: found a match
                if arity == 1                           # parent_frame(Next)
                    nxt = PL_new_term_ref(ld)
                    _PL_get_arg(ld, 1, what, nxt)
                    parent = parentFrame(ld, fr)
                    if parent != 0
                        PL_unify_frame(ld, nxt, parent) && return true
                    else
                        PL_unify_atom(ld, nxt, mk_sym(T, :none)) && return true
                    end
                else
                    return true
                end
            end
            PL_exception(ld, 0) != 0 && return false
            PL_rewind_foreign_frame(ld, fid)
            fr = parentFrame(ld, fr)
        end
    elseif _fa_key(T, key, :pc)
        parent = f.parent
        pp = f.programPointer
        if pp.pc >= 1 && parent != 0
            pf = ld.frames[parent]
            pcr = pf.clause
            if ((pf.predicate::Definition{T}).flags & P_FOREIGN) == 0 && pcr !== nothing &&
                pf.predicate !== gd.procedures_dcall1.definition
                PL_put_integer(ld, result, pp.pc - 1)   # programPointer - parent->clause->codes
            else
                return false
            end
        else
            return false
        end
    elseif _fa_key(T, key, :hidden)
        hidden = SYSTEM_MODE(ld) ? true : !isDebugFrame(ld, fr)
        PL_put_atom(ld, result, mk_sym(T, hidden ? Symbol("true") : Symbol("false")))
    elseif _fa_key(T, key, :depth_limit_exceeded)
        PL_put_atom(ld, result, mk_sym(T, Symbol("false")))
    else
        return PL_error(ld, ERR_DOMAIN, mk_sym(T, :frame_attribute), what)
    end

    return PL_unify(ld, value, result)
end

"Whether the key atom `key` is the symbol `s` (the keys of `prolog_frame_attribute/3`, `prolog_choice_attribute/3`)."
@inline _fa_key(::Type{T}, key::T, s::Symbol)::Bool where {T} =
    kind(key) === SYM && sym_key(key) == sym_key(mk_sym(T, s))

# PORT: pl-trace.c prolog_frame_attribute as pl_prolog_frame_attribute3_va
# (PRED_IMPL("prolog_frame_attribute", 3, prolog_frame_attribute, PL_FA_TRANSPARENT))
"`prolog_frame_attribute(+Frame, +Key, -Value)` (pl-trace.c): the registered predicate."
function pl_prolog_frame_attribute3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return prolog_frame_attribute(ld, PL__t0, PL__t0 + 1, PL__t0 + 2) ? FTRUE : FFALSE
end

# PORT: pl-trace.c in_clause_jump
# DIVERGES: the offset is 0-based as upstream's pointer difference, -1 is upstream's `(size_t)-1`; `value_pc` is an index into the frame's clause
# code (1-based, src/pl-incl.jl `choice`).
"The offset in its clause's code a jump choice point `ch` (an index) resumes at, or -1 (pl-trace.c)."
function in_clause_jump(ld::PL_local_data{T}, ch::Int)::Int where {T}
    c = ld.choices[ch]
    if c.type == CHP_JUMP && c.frame != 0
        f = ld.frames[c.frame]
        cr = f.clause
        fdef = f.predicate::Definition{T}
        if (fdef.flags & P_FOREIGN) == 0 && cr !== nothing && cr.clause !== nothing
            cl = cr.clause
            1 <= c.value_pc <= length(cl.codes) && return c.value_pc - 1
        end
    end
    return -1
end

# PORT: pl-trace.c choice_type_atom
# DIVERGES: the kernel's `CHP_JUMP` records are the in-clause jumps (`C_OR`) and a non-deterministic foreign call's redo point (`I_FREDO`, in the
# foreign frame's supervisor); a jump that is neither is `clause`, as upstream's `SUPERVISOR(next_clause)` case (none such is built here).
"The atom naming the type of choice point `ch` (an index): `jump`, `clause`, `top`, `catch`, `debug` or `foreign` (pl-trace.c)."
function choice_type_atom(ld::PL_local_data{T}, ch::Int)::T where {T}
    c = ld.choices[ch]
    if c.type == CHP_JUMP && in_clause_jump(ld, ch) == -1
        fdef = c.frame != 0 ? ld.frames[c.frame].predicate::Definition{T} : nothing
        if fdef !== nothing && (fdef.flags & P_FOREIGN) != 0
            return mk_sym(T, :foreign)                  # decode(ch->value.pc[0]) == I_FREDO
        end
        return mk_sym(T, :clause)                       # ch->value.pc == SUPERVISOR(next_clause)
    end
    c.type == CHP_JUMP && return mk_sym(T, :jump)
    c.type == CHP_CLAUSE && return mk_sym(T, :clause)
    c.type == CHP_TOP && return mk_sym(T, :top)
    c.type == CHP_CATCH && return mk_sym(T, :catch)
    return mk_sym(T, :debug)                            # CHP_DEBUG
end

# PORT: pl-trace.c prolog_choice_attribute as pl_prolog_choice_attribute3_va
# (PRED_IMPL("prolog_choice_attribute", 3, prolog_choice_attribute, 0))
# DIVERGES: `clause` of a choice point that is not a `CHP_CLAUSE` is upstream's `assert(ch->type == CHP_CLAUSE)`: the same assertion here.
"`prolog_choice_attribute(+Choice, +Key, -Value)` (pl-trace.c): read one attribute of a choice point."
function pl_prolog_choice_attribute3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    gd = _query_gd(ld)
    A1, A2, A3 = PL__t0, PL__t0 + 1, PL__t0 + 2
    ch = PL_get_choice(ld, A1)
    ch === nothing && return FFALSE
    key = PL_get_atom_ex(ld, A2)
    key === nothing && return FFALSE

    if _fa_key(T, key, :parent)
        while true
            ch = ld.choices[ch].parent
            (ch != 0 && ld.choices[ch].type == CHP_DEBUG) || break
        end
        ch != 0 && return PL_unify_choice(ld, A3, ch) ? FTRUE : FFALSE
        return FFALSE
    elseif _fa_key(T, key, :frame)
        return PL_unify_frame(ld, A3, ld.choices[ch].frame) ? FTRUE : FFALSE
    elseif _fa_key(T, key, :type)
        return PL_unify_atom(ld, A3, choice_type_atom(ld, ch)) ? FTRUE : FFALSE
    elseif _fa_key(T, key, :pc)
        offset = in_clause_jump(ld, ch)
        offset != -1 && return PL_unify_int64(ld, A3, offset) ? FTRUE : FFALSE
        return FFALSE
    elseif _fa_key(T, key, :clause)
        c = ld.choices[ch]
        @assert c.type == CHP_CLAUSE                    # assert(ch->type == CHP_CLAUSE)
        cref = c.value_clause.cref::ClauseRef{T}
        return PL_unify_clref(gd, ld, A3, cref.clause::Clause{T}) ? FTRUE : FFALSE
    end
    PL_error(ld, ERR_DOMAIN, mk_sym(T, :key), A2)
    return FFALSE
end

# PORT: pl-trace.c BeginPredDefs as PL_predicates_from_trace
# DIVERGES: the ported entries only (upstream's table also has `prolog_skip_level/2` and `prolog_interrupt/0`,
# pl-trace.c:2830-2840); the table's order is upstream's.
"pl-trace.c's registration table (`BeginPredDefs(trace)`): the ported entries."
const PL_predicates_from_trace = (
    PL_extension("prolog_current_choice", 1, pl_prolog_current_choice1_va, PL_FA_VARARGS),
    PL_extension(
        "prolog_frame_attribute", 3, pl_prolog_frame_attribute3_va,
        PL_FA_VARARGS | PL_FA_TRANSPARENT,
    ),
    PL_extension(
        "prolog_choice_attribute", 3, pl_prolog_choice_attribute3_va, PL_FA_VARARGS
    ),
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
