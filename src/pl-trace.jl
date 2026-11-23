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
# Since DBG1's first piece: `prolog_frame_attribute/3` and its helpers (`PL_get_frame`, `isDebugFrame`, `alternativeFrame`, …), over the
# kernel's frame, choice-point and query pools. Since DBG1's second piece: `prolog_choice_attribute/3` (`PL_get_choice`, `in_clause_jump`,
# `choice_type_atom`).
# Since PROC-TRACE: the C API's view of the stack, `PL_get_context`, `PL_step_context`, `PL_describe_context` and `PL_backtrace` (the
# `PL_BT_SAFE` branch; `PL_BT_USER` through `isDebugFrame`), with `clauseNo`; `PL_interrupt` and `prolog_interrupt/0` are refused by name (DBG2).

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

# PORT: pl-incl.h NO_PORT, CALL_PORT, EXIT_PORT, FAIL_PORT, REDO_PORT, UNIFY_PORT, CUT_CALL_PORT, CUT_EXIT_PORT, EXCEPTION_PORT, CUT_PORT, PORT_MASK
# (pl-incl.h:2840-2850 at the pin 18168e62: the port masks `debugstatus.leashing` and `debugstatus.visible` hold)
# (`CALL_PORT`, `EXIT_PORT` and `UNIFY_PORT` are defined in src/pl-incl.jl since COV1, where the coverage hooks read them: one definition each.)
"The debugger's port masks (pl-incl.h): `NO_PORT` 0x0, `FAIL_PORT` 0x4, `REDO_PORT` 0x8 (`CALL_PORT` 0x1, `EXIT_PORT` 0x2, `UNIFY_PORT` 0x10: src/pl-incl.jl)."
const NO_PORT = 0x000
const FAIL_PORT = 0x004
const REDO_PORT = 0x008
"`CUT_CALL_PORT` 0x40, `CUT_EXIT_PORT` 0x80, `EXCEPTION_PORT` 0x100, `CUT_PORT` (both cut ports), `PORT_MASK` 0x1ff (pl-incl.h)."
const CUT_CALL_PORT = 0x040
const CUT_EXIT_PORT = 0x080
const EXCEPTION_PORT = 0x100
const CUT_PORT = CUT_CALL_PORT | CUT_EXIT_PORT
const PORT_MASK = 0x1ff

# PORT: pl-util.c setInteger
# DIVERGES: the C `int *flag` is the current value `cur` in and the new value out (`nothing` is false: the flag keeps its value, as
# upstream's `fail` before `PL_get_integer_ex` stored anything); the local data is an argument.
"Unify `old` with `cur`, then read the integer `new` holds: the new value, or `nothing` when either step failed (pl-util.c)."
function setInteger(
    ld::PL_local_data{T}, cur::Int, old::term_t, new::term_t
)::Union{Nothing, Int} where {T}
    PL_unify_integer(ld, old, cur) || return nothing
    return PL_get_integer_ex(ld, new)
end

# PORT: pl-trace.c pl_trace
# (FRG("trace", 0, pl_trace, NOTRACE), pl-ext.c:140 at the pin 18168e62; pl-trace.c:2287-2290: `return tracemode(true, NULL);`)
# DIVERGES: the local data is an argument; as for `pl_notrace`. The kernel has no tracer (`tracePort` and the interactive prompt are DBG2's): upstream's
# `trace/0` turns the trace mode on and its next visible port stops in the tracer. With no port visible (`'$visible'/2` & PORT_MASK == 0) the tracer
# cannot stop and the call is upstream's `tracemode(true, NULL)`; with one visible it is refused by name BEFORE any state changes (audit D-0768 (2)), so a
# program never runs believing it is traced. The refusal stays until DBG2 lands the tracer (docs/r2_owners.tsv).
"`trace/0` (pl-trace.c): switch the trace mode on (`tracemode(true, NULL)`), which also switches the debug mode on; refused (`NotPortedError`, DBG2) while a port is visible."
function pl_trace(ld::PL_local_data{T})::foreign_t where {T}
    if (ld.debugstatus_visible & PORT_MASK) != 0
        throw(
            NotPortedError{T}(
                mk_sym(T, :trace), "trace/0 with a visible port: the tracer (pl-trace.c tracePort)", "DBG2"
            )
        )
    end
    return tracemode(ld, true, nothing) ? FTRUE : FFALSE
end

# PORT: pl-trace.c pl_tracing
# (FRG("tracing", 0, pl_tracing, NOTRACE), pl-ext.c:142; pl-trace.c:2297-2302: `return debugstatus.tracing;`)
# DIVERGES: the local data is an argument.
"`tracing/0` (pl-trace.c): true while the trace mode is on."
function pl_tracing(ld::PL_local_data{T})::foreign_t where {T}
    return ld.debugstatus_tracing ? FTRUE : FFALSE
end

# PORT: pl-trace.c pl_leash
# (FRG("$leash", 2, pl_leash, NOTRACE), pl-ext.c:145; pl-trace.c:2383-2387: `return setInteger(&debugstatus.leashing, old, new);`)
# DIVERGES: the local data is an argument; `debugstatus.leashing` is `ld.debugstatus_leashing` (src/pl-global.jl), set only when both
# steps of `setInteger` succeeded. No range check of the mask (upstream has none: the new value is any C `int`).
"`'\$leash'(-Old, +New)`: unify `Old` with the mask of the ports the tracer stops at and set it to `New` (pl-trace.c)."
function pl_leash(ld::PL_local_data{T}, old::term_t, new::term_t)::foreign_t where {T}
    v = setInteger(ld, ld.debugstatus_leashing, old, new)
    v === nothing && return FFALSE
    ld.debugstatus_leashing = v
    return FTRUE
end

# PORT: pl-trace.c pl_visible
# (FRG("$visible", 2, pl_visible, NOTRACE), pl-ext.c:146; pl-trace.c:2389-2393: `return setInteger(&debugstatus.visible, old, new);`)
# DIVERGES: as `pl_leash`, over `ld.debugstatus_visible`.
"`'\$visible'(-Old, +New)`: unify `Old` with the mask of the ports the tracer shows and set it to `New` (pl-trace.c)."
function pl_visible(ld::PL_local_data{T}, old::term_t, new::term_t)::foreign_t where {T}
    v = setInteger(ld, ld.debugstatus_visible, old, new)
    v === nothing && return FFALSE
    ld.debugstatus_visible = v
    return FTRUE
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

# ── the C API's view of the stack: contexts, their description, the backtrace (pl-trace.c:1337-1769) ──────────────────────────
# ORIGINAL (PROC-TRACE): upstream's `pl_context_t` (SWI-Prolog.h:1563; SWI-Prolog.h is not among this file's UPSTREAM headers, and
# src/SWI-Prolog.jl comes before the local data, whose type the struct holds): the engine, the query frame, the local frame
# and the continuation point `PL_get_context` and `PL_step_context` walk. `qf` and `fr` are indexes (0 = NULL), `pc` is `nothing`
# for NULL.
"A position in the stack `PL_get_context` hands out and `PL_step_context` walks: engine, query, frame, program counter (SWI-Prolog.h `pl_context_t`)."
mutable struct pl_context_t{T}
    ld::PL_local_data{T}
    qf::Int                             # query frame (an index; 0 = NULL)
    fr::Int                             # local frame (an index; 0 = NULL)
    pc::Union{Nothing, Code{T}}         # the continuation point in `fr`'s caller's clause (nothing = NULL)
end

# ORIGINAL (PROC-TRACE): a copy of the struct (C assigns `pl_context_t` by value: `from = ctx`).
"A copy of the context `c`."
_context_copy(c::pl_context_t{T}) where {T} = pl_context_t{T}(c.ld, c.qf, c.fr, c.pc)

# ORIGINAL (PROC-TRACE): upstream's `onStack(local, fr)` (pl-incl.h), as `PL_unify_frame` tests it: `fr` is a live frame record, its
# position below `lTop`.
"True when the frame index `fr` is a frame on the local stack."
function _onStackLocal(ld::PL_local_data{T}, fr::Int)::Bool where {T}
    1 <= fr <= length(ld.frames) && 0 <= ld.frames[fr].base < ld.lTop
end

# PORT: pl-trace.c PL_get_context
# DIVERGES: the context is returned (upstream fills `*c` and returns `HAS_LD`, which is always true here: the engine is `ld`);
# `thread_id` is ignored as upstream's (only the calling thread's stack can be taken).
"The context of the innermost frame of `ld`: its query, the query's saved frame (else the environment frame) and program counter (pl-trace.c)."
function PL_get_context(ld::PL_local_data{T}, thread_id::Int)::pl_context_t{T} where {T}
    qf = ld.query
    fr = ld.environment_frame
    pc = nothing
    if qf != 0
        q = ld.queries[qf]
        q.registers_fr != 0 && (fr = q.registers_fr)
        q.registers_pc.pc != 0 && (pc = q.registers_pc)
    end
    return pl_context_t{T}(ld, qf, fr, pc)
end

# PORT: pl-trace.c PL_step_context
"Step the context `c` to the frame that called its frame (to the query's parent frame from a top frame); false at the end (pl-trace.c)."
function PL_step_context(c::pl_context_t{T})::Bool where {T}
    if c.fr != 0
        ld = c.ld
        _onStackLocal(ld, c.fr) || return false
        f = ld.frames[c.fr]
        if f.parent != 0
            pc = f.programPointer
            c.pc = pc.pc == 0 ? nothing : pc
            c.fr = f.parent
        else
            c.pc = nothing
            c.qf = queryOfFrame(ld, c.fr)
            c.fr = parentFrame(ld, c.fr)
        end
    end
    return c.fr != 0
end

# ORIGINAL (PROC-TRACE): upstream's `clauseNo(cl, gen)` (pl-util.c:262; pl-util.c is not among this file's UPSTREAM headers): the
# index of `cl` in its predicate's clause chain at generation `gen` (0: the current one), -1 when it is not visible. As upstream, the
# count `i` advances for every clause of the chain, visible or not. `gd` is an argument (upstream: GD); no `acquire_def`.
"The position of `cl` in its predicate's clause chain at generation `gen` (0: now), or -1 (pl-util.c)."
function clauseNo(gd::PL_global_data{T}, cl::Clause{T}, gen::gen_t)::Int where {T}
    def = cl.predicate
    if gen == 0
        gen = global_generation(gd)
    end
    i = 1
    cref = def.impl_clauses.first_clause
    while cref !== nothing
        c = cref.clause::Clause{T}
        if visibleClause(c, gen, gd.reload_generation) && c === cl
            return i
        end
        i += 1
        cref = cref.next
    end
    return -1
end

# ORIGINAL (PROC-TRACE): the text `PL_describe_context` formats, as a String (see `PL_describe_context`).
"The description of the context `c`'s frame: `[Level] Predicate [PC=n in ...]`, or the empty text for no frame."
function _describe_context(
    gd::PL_global_data{T}, ld::PL_local_data{T}, c::pl_context_t{T}
)::String where {T}
    fr = c.fr
    fr == 0 && return ""
    if !_onStackLocal(ld, fr)
        return string("<invalid frame reference ", fr, ">")
    end
    f = ld.frames[fr]
    level = Int(levelFrame(f))
    def = f.predicate
    def === nothing && return string("[", level, "] <no predicate>")
    head = string("[", level, "] ", _autoload_predicate_name(gd, def), " ")
    pc = c.pc
    if pc !== nothing && pc.codes === def.codes && 1 <= pc.pc <= length(def.codes)
        return string(head, "[PC=", pc.pc - 1, " in supervisor]")
    end
    if (def.flags & P_FOREIGN) == 0
        if f.clause !== nothing
            cl = f.clause.clause::Clause{T}
            pcn = -1
            if pc !== nothing && pc.codes === cl.codes && 1 <= pc.pc <= length(cl.codes)
                pcn = pc.pc - 1
            end
            if def === gd.procedures_dc_call_prolog0.definition
                return string(head, "[PC=", pcn, " in top query clause]")
            end
            return string(head, "[PC=", pcn, " in clause ", clauseNo(gd, cl, gen_t(0)), "]")
        end
        return string(head, "<no clause>")
    end
    return string(head, "<foreign>")
end

# PORT: pl-trace.c PL_describe_context
# DIVERGES: the text and the byte count are returned (upstream fills `buf` and returns the count: the bytes `snprintf` would have
# written, the text itself cut to `len-1` bytes; upstream's `len -= printed` wraps for a name longer than the buffer, here the whole text
# is cut once); the program counter offsets are the kernel's 0-based `pc - 1`, so they differ from swipl's wherever the compiler's code
# does; an invalid frame is named by its pool index, not an address. `predicateName` is `_autoload_predicate_name`.
"""
    PL_describe_context(c, len) -> (text, n)

Describe the frame of context `c` as `[Level] Name/Arity [PC=n in supervisor | in top query clause | in clause k]`,
`<no clause>` or `<foreign>`: `text` cut to `len-1` bytes, `n` the byte count of the whole description (pl-trace.c).
"""
function PL_describe_context(c::pl_context_t{T}, len::Int)::Tuple{String, Int} where {T}
    ld = c.ld
    full = _describe_context(_query_gd(ld), ld, c)
    n = ncodeunits(full)
    len <= 0 && return ("", n)
    n < len && return (full, n)
    return (String(codeunits(full)[1:(len - 1)]), n)
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

# PORT: pl-trace.c prolog_frame_attribute
# (pl-trace.c:2490 at the pin 18168e62: `static bool prolog_frame_attribute(term_t frame, term_t what, term_t value)`; the function
# and every helper it calls are unchanged at af9e2e7e)
# DIVERGES: frames are indices of the frame pool (`PL_get_frame`); the module is an index into `gd`'s table (`PL_strip_module`).
# `fref` (upstream saves and restores `fr` as a term reference over possible stack shifts) is not needed: a pool index is stable.
# `PL_get_arg_ex(1, what, arg)` is `_PL_get_arg`: the compound check is made already (`what` has arity 1 there). The
# `ensureGlobalSpace(0, ALLOW_GC)` retry before `PL_unify` in `argument(N)` has no counterpart (docs/g1gc_safe_points.md, row
# pl-trace.c:2534, NO-COUNTERPART): the global stack is a vector. `O_DEBUGLOCAL`'s assert and `checkData` are not ported.
# `unknown_key:` (a `goto`) is `_frame_attribute_unknown`. A frame whose `ClauseRef` holds no clause (upstream would read a NULL)
# counts as having none: `argument(N)` is then bounded by the predicate's arity, and `clause` fails. `pc`: upstream's
# `fr->programPointer - clause->codes` is the 0-BASED offset; the kernel's `Code.pc` is 1-based, so it is `pc - 1`
# (the value a Prolog-level `prolog_stack` reads is the same number as swipl's). `depth_limit_exceeded`: `O_LIMIT_DEPTH`'s
# branch, over the query's `saved_depth_limit`, which only a `PL_Q_NODEBUG` query sets (to the then limit, `DEPTH_NO_LIMIT`: never exceeded); any other query reads its pool record's 0, so a frame above level 0 answers `true`, as the pinned swipl does. `parent_goal` falls out of its loop with
# `fr` NULL to the final `PL_unify(value, result)` with `result` unbound, as upstream's structure does. Not ported: the
# `set(fr, FR_NOTIFY)` debugger consumer (`FR_NOTIFY` is set on the frame; nothing reads it until DBG1 ports the tracer ports).
# `DEBUG(CHK_SECURE, scan_global(0))` of the PRED_IMPL wrapper is dropped.
"""
    prolog_frame_attribute(ld, frame, what, value) -> Bool

`prolog_frame_attribute(+Frame, +Key, -Value)` (pl-trace.c): the value of attribute `Key` (`level`, `parent`, `predicate_indicator`,
`clause`, `pc`, `goal`, `hidden`, `context_module`, `depth_limit_exceeded`, `parent_goal`, `argument(N)`, `alternative`,
`has_alternatives`, `skipped`, `top`) of the frame `frame` names.
"""
function prolog_frame_attribute(
    ld::PL_local_data{T}, frame::term_t, what::term_t, value::term_t
)::Bool where {T}
    gd = _query_gd(ld)
    result = PL_new_term_ref(ld)

    ok, fr = PL_get_frame(ld, frame)
    ok || return PL_error(ld, ERR_TYPE, mk_sym(T, :frame_reference), frame)
    fr == 0 && return false                             # frame == 'none'
    nm = PL_get_name_arity(ld, what)
    nm === nothing && return PL_error(ld, ERR_TYPE, mk_sym(T, :callable), what)
    key, arity = nm
    kk = sym_key(key)
    ok, m = PL_strip_module(gd, ld, value, 0, value)    # PL_strip_module(value, &m, value)
    ok || return false

    ld.frames[fr].flags |= FR_NOTIFY                    # set(fr, FR_NOTIFY)

    if kk == sym_key(mk_sym(T, :argument)) && arity == 1
        arg = PL_new_term_ref(ld)

        _PL_get_arg(ld, 1, what, arg)                   # PL_get_arg_ex(1, what, arg)
        argn = PL_get_size_ex(ld, arg)
        argn === nothing && return false
        argn < 1 && return PL_error(ld, ERR_DOMAIN, mk_sym(T, :natural), arg)

        f = ld.frames[fr]
        def = f.predicate::Definition{T}
        cr = f.clause
        cl = cr === nothing ? nothing : cr.clause
        if (def.flags & P_FOREIGN) != 0 || cl === nothing
            argn > def.arity && return false
        else
            argn > cl.prolog_vars && return false
        end

        return PL_unify(ld, value, argFrameP(f.base, argn - 1)) # PL_unify(value, consTermRef(argFrameP(fr, argn-1)))
    end

    if !(arity == 0 || (arity == 1 && kk == sym_key(mk_sym(T, :parent_goal))))
        return _frame_attribute_unknown(ld, what)       # unknown_key:
    end

    f = ld.frames[fr]
    def = f.predicate::Definition{T}
    if kk == sym_key(mk_sym(T, :level))
        PL_put_integer(ld, result, Int(levelFrame(f)))
    elseif kk == sym_key(mk_sym(T, :has_alternatives))
        PL_put_atom(ld, result, mk_sym(T, hasAlternativesFrame(ld, fr) ? :true : :false))
    elseif kk == sym_key(mk_sym(T, :skipped))
        PL_put_atom(ld, result, mk_sym(T, (f.flags & FR_SKIPPED) != 0 ? :true : :false))
    elseif kk == sym_key(mk_sym(T, :alternative))
        alt = alternativeFrame(ld, fr)
        alt != 0 || return false
        PL_put_frame(ld, result, alt)
    elseif kk == sym_key(mk_sym(T, :parent))
        parent = parentFrame(ld, fr)
        parent != 0 || return false
        clear_frame_vars(ld, parent)
        PL_put_frame(ld, result, parent)
    elseif kk == sym_key(mk_sym(T, :top))
        PL_put_atom(ld, result, mk_sym(T, f.parent != 0 ? :false : :true))
    elseif kk == sym_key(mk_sym(T, :context_module))
        PL_put_atom(ld, result, gd.modules[contextModule(gd, ld, fr)].atom)
    elseif kk == sym_key(mk_sym(T, :clause))
        cr = f.clause
        cl = cr === nothing ? nothing : cr.clause
        if (def.flags & P_FOREIGN) == 0 && cl !== nothing &&
            def !== gd.procedures_dc_call_prolog0.definition &&
            def !== gd.procedures_dcall1.definition
            PL_unify_clref(gd, ld, result, cl) || return false
        else
            return false
        end
    elseif kk == sym_key(mk_sym(T, :goal))
        put_frame_goal(ld, result, fr) || return false
    elseif kk == sym_key(mk_sym(T, :predicate_indicator))
        unify_definition(gd, ld, gd.modules[m], result, def, 0, GP_NAMEARITY) || return false
    elseif kk == sym_key(mk_sym(T, :parent_goal))
        head = PL_new_term_ref(ld)
        a = PL_new_term_ref(ld)

        proc = get_procedure(gd, ld, value, GP_FIND, head)
        proc === nothing && return false

        fid = PL_open_foreign_frame(ld)
        cur = fr
        while cur != 0
            while cur != 0 && ld.frames[cur].predicate !== proc.definition
                cur = parentFrame(ld, cur)
            end

            if cur != 0
                garity = (ld.frames[cur].predicate::Definition{T}).arity
                i = 0
                while i < garity
                    fa = argFrameP(ld.frames[cur].base, i)  # consTermRef(argFrameP(fr, i))
                    _PL_get_arg(ld, i + 1, head, a)
                    PL_unify(ld, a, fa) || break                # Argument does not unify
                    i += 1
                end
                if i == garity                                  # All arguments unified: found a match
                    if arity == 1                               # parent_frame(Next)
                        arg = PL_new_term_ref(ld)

                        _PL_get_arg(ld, 1, what, arg)
                        parent = parentFrame(ld, cur)
                        if parent != 0
                            PL_unify_frame(ld, arg, parent) && return true
                        else
                            PL_unify_atom(ld, arg, mk_sym(T, :none)) && return true
                        end
                    else
                        return true
                    end
                end

                if PL_exception(ld, 0) != 0
                    return false
                else
                    PL_rewind_foreign_frame(ld, fid)
                    cur = parentFrame(ld, cur)
                end
            else
                PL_close_foreign_frame(ld, fid)
                return false                                    # No frame running this predicate
            end
        end
    elseif kk == sym_key(mk_sym(T, :pc))
        pp = f.programPointer
        parent = f.parent
        if pp.pc != 0 && parent != 0
            pf = ld.frames[parent]
            pcr = pf.clause
            if ((pf.predicate::Definition{T}).flags & P_FOREIGN) == 0 && pcr !== nothing &&
                pf.predicate !== gd.procedures_dcall1.definition
                PL_put_intptr(ld, result, pp.pc - 1)    # fr->programPointer - clause->codes (0-based)
            else
                return false
            end
        else
            return false
        end
    elseif kk == sym_key(mk_sym(T, :hidden))
        hv = if SYSTEM_MODE(ld)
            :true
        else
            isDebugFrame(ld, fr, 0) ? :false : :true
        end
        PL_put_atom(ld, result, mk_sym(T, hv))
    elseif kk == sym_key(mk_sym(T, :depth_limit_exceeded))
        qi = findQuery(ld, ld.environment_frame)        # get limit from saved query
        dv = if qi != 0 && Int(levelFrame(f)) > ld.queries[qi].saved_depth_limit
            :true
        else
            :false
        end
        PL_put_atom(ld, result, mk_sym(T, dv))
    else
        return _frame_attribute_unknown(ld, what)       # goto unknown_key
    end

    return PL_unify(ld, value, result)
end

# ORIGINAL (DBG1): the `unknown_key:` label of `prolog_frame_attribute` (pl-trace.c), which C reaches by `goto`.
"Raise `domain_error(frame_attribute, What)` (the label `unknown_key` of `prolog_frame_attribute`, pl-trace.c)."
function _frame_attribute_unknown(ld::PL_local_data{T}, what::term_t)::Bool where {T}
    return PL_error(ld, ERR_DOMAIN, mk_sym(T, :frame_attribute), what)
end

# PORT: pl-trace.c prolog_frame_attribute as pl_prolog_frame_attribute3_va
# (PRED_IMPL("prolog_frame_attribute", 3, prolog_frame_attribute, PL_FA_TRANSPARENT), pl-trace.c:2706 at the pin 18168e62)
"`prolog_frame_attribute(+Frame, +Key, -Value)` (pl-trace.c): the registered entry of `prolog_frame_attribute/3`."
function pl_prolog_frame_attribute3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    A2 = PL__t0 + 1
    A3 = PL__t0 + 2
    return prolog_frame_attribute(ld, A1, A2, A3) ? FTRUE : FFALSE
end

# PORT: pl-trace.c PL_get_choice
# (pl-trace.c:175 at the pin 18168e62; `valid_choice` :165)
# DIVERGES: returns the pool INDEX of the choice point at the position `r` holds (`existingChoice`, src/pl-wam.jl, which walks the
# chain from `BFR` and so also stands for `ch >= lBase && ch < lTop` and `valid_choice`: stricter than upstream's test, which accepts
# any position holding a record), 0 for upstream's false (the error is raised: `existence_error(choice, R)`, or `type_error(choice, R)`
# for a non-integer); `PL_get_intptr` is `PL_get_long`.
"The choice point the term reference `r` holds the position of, as its pool index, or 0 with an error raised (pl-trace.c)."
function PL_get_choice(ld::PL_local_data{T}, r::term_t)::Int where {T}
    i = PL_get_long(ld, r)                              # PL_get_intptr(r, &i)
    if i !== nothing
        ch = existingChoice(ld, i)                      # ch = (Choice)((Word)lBase + i); !valid_choice(ch)
        if ch == 0
            PL_error(ld, ERR_EXISTENCE, mk_sym(T, :choice), r)
            return 0
        end
        return ch                                       # *chp = ch
    end
    PL_error(ld, ERR_TYPE, mk_sym(T, :choice), r)
    return 0
end

# PORT: pl-trace.c in_clause_jump
# DIVERGES: `ch` is a pool index; `ch->value.pc` is `value_pc`, an index into the frame's clause code (1-based), so the offset
# `pc - cl->codes` is `value_pc - 1`; upstream's `(size_t)-1` is -1.
"The offset in its clause of the jump choice point `ch`'s code position, or -1 when it is not a jump inside a clause (pl-trace.c)."
function in_clause_jump(ld::PL_local_data{T}, ch::Int)::Int where {T}
    c = ld.choices[ch]
    if c.type == CHP_JUMP && c.frame != 0
        f = ld.frames[c.frame]
        if ((f.predicate::Definition{T}).flags & P_FOREIGN) == 0
            cref = f.clause
            cl = cref === nothing ? nothing : cref.clause
            if cl !== nothing && c.value_pc >= 1 && c.value_pc <= length(cl.codes)
                return c.value_pc - 1                   # ch->value.pc - cl->codes
            end
        end
    end
    return -1
end

# PORT: pl-trace.c choice_type_atom
# DIVERGES: a CHP_JUMP outside any clause is a foreign frame's redo (`I_FREDO` at `value_pc` of the innermost supervisor, src/pl-wrap.jl)
# and gives `foreign`; upstream's other case, `ch->value.pc == SUPERVISOR(next_clause)` (`clause`), is a `CHP_CLAUSE` choice point in the
# kernel, so a CHP_JUMP that is neither is answered `clause` where upstream asserts.
"The atom naming what choice point `ch` resumes: `jump`, `clause`, `top`, `catch`, `debug` or `foreign` (pl-trace.c)."
function choice_type_atom(ld::PL_local_data{T}, ch::Int)::T where {T}
    c = ld.choices[ch]
    if c.type == CHP_JUMP && in_clause_jump(ld, ch) == -1
        f = c.frame != 0 ? ld.frames[c.frame] : nothing
        if f !== nothing
            def = f.predicate::Definition{T}
            if (def.flags & P_FOREIGN) != 0
                sup = innermost_supervisor(_query_gd(ld), def)[1]
                if c.value_pc >= 1 && c.value_pc <= length(sup) && sup[c.value_pc] == I_FREDO    # decode(ch->value.pc[0]) == I_FREDO
                    return mk_sym(T, :foreign)
                end
            end
        end
        return mk_sym(T, :clause)                       # SUPERVISOR(next_clause)
    end
    ty = c.type == CHP_JUMP ? :jump : c.type == CHP_CLAUSE ? :clause :
        c.type == CHP_TOP ? :top : c.type == CHP_CATCH ? :catch : :debug     # types[ch->type]
    return mk_sym(T, ty)
end

# PORT: pl-trace.c prolog_choice_attribute as pl_prolog_choice_attribute3_va
# (PRED_IMPL("prolog_choice_attribute", 3, prolog_choice_attribute, 0), pl-trace.c:2755 at the pin 18168e62)
# DIVERGES: `ch` is a pool index; `ch->parent`, `ch->frame` are indices (`PL_unify_choice`/`PL_unify_frame` give their positions);
# `ch->value.clause.cref->value.clause` is `value_clause.cref.clause`, and the `assert(ch->type == CHP_CLAUSE)` is kept as an `@assert`.
"`prolog_choice_attribute(+Choice, +Key, -Value)` (pl-trace.c): `parent`, `frame`, `type`, `pc` or `clause` of a choice point."
function pl_prolog_choice_attribute3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    A2 = PL__t0 + 1
    A3 = PL__t0 + 2
    ch = PL_get_choice(ld, A1)
    ch == 0 && return FFALSE                            # !PL_get_choice(A1, &ch)
    key = PL_get_atom_ex(ld, A2)
    key === nothing && return FFALSE                    # !PL_get_atom_ex(A2, &key)

    kk = sym_key(key)
    if kk == sym_key(mk_sym(T, :parent))
        p = ld.choices[ch].parent
        while p != 0 && ld.choices[p].type == CHP_DEBUG     # do { ch = ch->parent } while(ch && ch->type == CHP_DEBUG)
            p = ld.choices[p].parent
        end
        p != 0 && return PL_unify_choice(ld, A3, p) ? FTRUE : FFALSE
        return FFALSE
    elseif kk == sym_key(mk_sym(T, :frame))
        return PL_unify_frame(ld, A3, ld.choices[ch].frame) ? FTRUE : FFALSE
    elseif kk == sym_key(mk_sym(T, :type))
        return PL_unify_atom(ld, A3, choice_type_atom(ld, ch)) ? FTRUE : FFALSE
    elseif kk == sym_key(mk_sym(T, :pc))
        offset = in_clause_jump(ld, ch)
        offset != -1 && return PL_unify_int64(ld, A3, offset) ? FTRUE : FFALSE
        return FFALSE
    elseif kk == sym_key(mk_sym(T, :clause))
        c = ld.choices[ch]
        @assert c.type == CHP_CLAUSE
        cr = c.value_clause.cref::ClauseRef{T}
        return PL_unify_clref(_query_gd(ld), ld, A3, cr.clause::Clause{T}) ? FTRUE : FFALSE
    end
    return PL_error(ld, ERR_DOMAIN, mk_sym(T, :key), A2) ? FTRUE : FFALSE
end

# ORIGINAL (PROC-TRACE): the named refusal of the interactive debugger's entries, owner DBG2: `interruptHandler` (pl-trace.c:1928-2059:
# reads a key from the terminal, `break`, `trace`, `exitFromDebugger`, and the toplevel unwinding) behind `PL_interrupt` and `prolog_interrupt/0`,
# and `writeFrameGoal` (the tracer's goal writer) behind the non-`PL_BT_SAFE` branch of `PL_backtrace`.
function _debugger_refused(ld::PL_local_data{T}, what::String) where {T}
    throw(NotPortedError{T}(mk_sym(T, :debugger), what, "DBG2"))
end

# PORT: pl-trace.c writeContextFrame
# DIVERGES: the `PL_BT_SAFE` branch writes the description (`PutString`, pl-write.c: each byte a character); the other branch
# (`writeFrameGoal`) is refused by name, owner DBG2.
"Write the frame of context `ctx` to `out`: its description under `PL_BT_SAFE` (pl-trace.c)."
function writeContextFrame(
    ld::PL_local_data{T}, out::IOSTREAM, ctx::pl_context_t{T}, flags::Int
)::Nothing where {T}
    if (flags & PL_BT_SAFE) != 0
        buf, _ = PL_describe_context(ctx, 256)
        PutString(string("  ", buf, "\n"), out)
    else
        _debugger_refused(
            ld, "PL_backtrace without PL_BT_SAFE: the frame goal writer writeFrameGoal (pl-trace.c:1353)"
        )
    end
    return nothing
end

# ORIGINAL (PROC-TRACE): upstream's `SHOW_FRAME(fr)` macro of `_PL_backtrace` (pl-trace.c:1366).
"True when the backtrace shows frame `fr`: a debug frame, or any frame unless `PL_BT_USER` is in `flags`."
function _show_frame(ld::PL_local_data{T}, fr::Int, flags::Int)::Bool where {T}
    isDebugFrame(ld, fr, 0) || (flags & PL_BT_USER) == 0
end

# PORT: pl-trace.c _PL_backtrace
# DIVERGES: `gc_status.active` is not kept (no collection runs while a backtrace is taken, so the flags stay as given), and
# `startCritical`/`endCritical` (no signals defer here) are left out; `PL_get_context` always succeeds, so upstream's `No stack??`
# branch cannot arise; `gd` is `_query_gd(ld)`.
"Write a backtrace of `depth` frames (negative: the `-depth` outermost) of the stack of `ld` to `out`; `flags` is `PL_BT_SAFE` and/or `PL_BT_USER` (pl-trace.c)."
function _PL_backtrace(
    ld::PL_local_data{T}, out::IOSTREAM, depth::Int, flags::Int
)::Nothing where {T}
    ctx = PL_get_context(ld, 0)
    def = nothing
    same_proc = 0
    rctx = _context_copy(ctx)                       # recursive context

    if SYSTEM_MODE(ld)
        flags &= ~PL_BT_USER
    end

    if depth < 0                                    # depth < 0: top depth frames
        from = _context_copy(ctx)
        depth = -depth
        skip = depth
        while PL_step_context(ctx)
            if _show_frame(ld, ctx.fr, flags) && (skip -= 1) <= 0
                break
            end
        end
        while PL_step_context(ctx)
            if _show_frame(ld, ctx.fr, flags)
                while true                          # do { PL_step_context(&from) } while( !SHOW_FRAME(from.fr) )
                    PL_step_context(from)
                    _show_frame(ld, from.fr, flags) && break
                end
            end
        end
        ctx = from
    end

    while depth > 0 && ctx.fr != 0
        frame = ld.frames[ctx.fr]
        if frame.predicate === def
            same_proc += 1
            if same_proc >= 10
                if same_proc == 10
                    PutString("    ...\n    ...\n", out)
                end
                rctx = _context_copy(ctx)
                PL_step_context(ctx)                # the for-loop's step, on `continue` too
                continue
            end
        else
            if same_proc >= 10
                if isDebugFrame(ld, rctx.fr, 0) || (flags & PL_BT_USER) == 0
                    writeContextFrame(ld, out, rctx, flags)
                    depth -= 1
                end
                same_proc = 0
            end
            def = frame.predicate
        end

        if _show_frame(ld, ctx.fr, flags)
            writeContextFrame(ld, out, ctx, flags)
            depth -= 1
        end
        PL_step_context(ctx)
    end
    return nothing
end

# PORT: pl-trace.c PL_backtrace
# DIVERGES: `ld` is an argument; the stream is `Suser_error(ld)`.
"Write a backtrace of `depth` frames to `user_error` (pl-trace.c); see `_PL_backtrace`."
PL_backtrace(ld::PL_local_data{T}, depth::Int, flags::Int) where {T} =
    _PL_backtrace(ld, Suser_error(ld)::IOSTREAM, depth, flags)

# PORT: pl-trace.c PL_interrupt
# DIVERGES: refused by name, owner DBG2 (see `_debugger_refused`): the body is `interruptHandler`, the interactive debugger.
"`PL_interrupt(sig)`: refused by name, the interactive `interruptHandler` is left to DBG2 (pl-trace.c)."
function PL_interrupt(ld::PL_local_data{T}, sig::Int)::Nothing where {T}
    _debugger_refused(ld, "PL_interrupt: the interactive interruptHandler (pl-trace.c:1928-2059)")
end

# PORT: pl-trace.c prolog_interrupt as pl_prolog_interrupt0_va
# (PRED_IMPL("prolog_interrupt", 0, prolog_interrupt, PL_FA_NOTRACE))
# DIVERGES: refused by name, owner DBG2 (see `PL_interrupt`).
"`prolog_interrupt/0`: refused by name, the interactive `interruptHandler` is left to DBG2 (pl-trace.c)."
function pl_prolog_interrupt0_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    PL_interrupt(ld, 2)
    return FFALSE
end

# PORT: pl-trace.c BeginPredDefs as PL_predicates_from_trace
# DIVERGES: the ported entries only (upstream's table also has the other debugger predicates, pl-trace.c:2830-2840); `prolog_interrupt/0`
# is refused by name (PROC-TRACE).
"pl-trace.c's registration table (`BeginPredDefs(trace)`): the ported entries."
const PL_predicates_from_trace = (
    PL_extension("prolog_current_choice", 1, pl_prolog_current_choice1_va, PL_FA_VARARGS),
    PL_extension(                                   # (pl-trace.c:2706 at the pin 18168e62, since DBG1's first piece)
        "prolog_frame_attribute", 3, pl_prolog_frame_attribute3_va,
        PL_FA_TRANSPARENT | PL_FA_VARARGS
    ),
    PL_extension("prolog_choice_attribute", 3, pl_prolog_choice_attribute3_va, PL_FA_VARARGS),    # (pl-trace.c:2755)
    PL_extension(
        "prolog_interrupt", 0, pl_prolog_interrupt0_va, PL_FA_NOTRACE | PL_FA_VARARGS
    )                                               # (pl-trace.c:2839, refused by name)
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

# PORT: pl-trace.c pl_spy
# (FRG("$spy", 1, pl_spy, META), pl-ext.c:143; pl-trace.c:2342-2361 at the pin)
# DIVERGES: the procedure is `get_procedure_find` (GP_FIND without GP_NAMEARITY, src/pl-proc.jl); the local data is the first
# argument. The kernel has no tracer (DBG1): `SPY_ME` is set and read (`'$get_predicate_attribute'/3` `spy`), no call stops at it.
"`'\$spy'(:Head)`: set a spy point on the predicate, report it and switch debug mode on (pl-trace.c)."
function pl_spy(ld::PL_local_data{T}, p::term_t)::foreign_t where {T}
    gd = _query_gd(ld)
    proc = get_procedure_find(gd, ld, p)
    if proc !== nothing
        def = proc.definition
        if (def.flags & SPY_ME) == 0                                    # isoff(def, SPY_ME)
            def.flags |= SPY_ME
            printMessage(ld, :informational, _message_term(ld, :spy, p)) || return FFALSE
        end
        return debugmode(ld, true, nothing, DBG_ALL) ? FTRUE : FFALSE   # debugmode(NULL, true, NULL, DBG_ALL)
    end
    return FFALSE
end

# PORT: pl-trace.c pl_nospy
# (FRG("$nospy", 1, pl_nospy, META), pl-ext.c:144; pl-trace.c:2363-2379 at the pin)
# DIVERGES: as `pl_spy`; the existence error of an unknown predicate is `get_procedure_find`'s (`GP_EXISTENCE_ERROR`).
"`'\$nospy'(:Head)`: remove the spy point of the predicate and report it (pl-trace.c); an unknown predicate is an existence error."
function pl_nospy(ld::PL_local_data{T}, p::term_t)::foreign_t where {T}
    gd = _query_gd(ld)
    proc = get_procedure_find(gd, ld, p, GP_FIND | GP_EXISTENCE_ERROR)
    if proc !== nothing
        def = proc.definition
        if (def.flags & SPY_ME) != 0                                    # ison(def, SPY_ME)
            def.flags &= ~SPY_ME
            return printMessage(ld, :informational, _message_term(ld, :nospy, p)) ? FTRUE : FFALSE
        end
        return FTRUE
    end
    return FFALSE
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
