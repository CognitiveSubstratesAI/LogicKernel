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
_onStackLocal(ld::PL_local_data{T}, fr::Int)::Bool where {T} =
    1 <= fr <= length(ld.frames) && 0 <= ld.frames[fr].base < ld.lTop

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

# PORT: pl-trace.c is_meta_call
# DIVERGES: the frame is an index; a parent without a clause (a foreign frame) is no meta-call parent, where upstream reads a clause
# through the frame's redo word.
"True when the frame `fr` was created through a meta-call (pl-trace.c)."
function is_meta_call(ld::PL_local_data{T}, fr::Int)::Bool where {T}
    f = ld.frames[fr]
    parent = f.parent
    if parent != 0
        pf = ld.frames[parent]
        if f.level == pf.level + 0x00000001 && ((f.predicate::Definition{T}).flags & P_FOREIGN) == 0
            pf.clause === nothing && return false
            cl = pf.clause.clause::Clause{T}
            pc = prevPC(cl, f.programPointer)
            if pc !== nothing
                op = decode(pc)
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
# DIVERGES: the frame is an index; the debug output (`DEBUG(MSG_TRACE_FRAME, ..)`) is not kept.
"True when the call of frame `FR` must be visible in the tracer: user code, user hooks of system code, the meta-call of a system meta-predicate (pl-trace.c)."
function isDebugFrame(
    ld::PL_local_data{T}, FR::Int, port::Int
)::Bool where {T}
    fr = ld.frames[FR]
    def = fr.predicate::Definition{T}
    (def.flags & TRACE_ME) == 0 && return false                 # hidden predicate
    (def.flags & HIDE_CHILDS) == 0 && return true               # user pred

    parent = fr.parent
    if parent != 0
        pdef = ld.frames[parent].predicate::Definition{T}
        if (def.flags & (P_NOPROFILE | HIDE_CHILDS)) == (P_NOPROFILE | HIDE_CHILDS) &&
            (pdef.flags & (P_NOPROFILE | HIDE_CHILDS)) == (P_NOPROFILE | HIDE_CHILDS)
            return false                                        # noprof system-system
        end
        while parent != 0 &&
            ((ld.frames[parent].predicate::Definition{T}).flags & P_NOPROFILE) != 0
            parent = ld.frames[parent].parent
        end
    end

    if parent != 0
        pf = ld.frames[parent]
        if fr.level == pf.level + 0x00000001                    # not last-call optimized
            return ((pf.predicate::Definition{T}).flags & HIDE_CHILDS) == 0   # user calls system / system calls system
        else
            return (pf.flags & FR_HIDE_CHILDS) == 0 && is_meta_call(ld, FR)
        end
    else
        qf = ld.queries[queryOfFrame(ld, FR)]
        return (qf.flags & PL_Q_NODEBUG) == 0
    end
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
_show_frame(ld::PL_local_data{T}, fr::Int, flags::Int)::Bool where {T} =
    isDebugFrame(ld, fr, 0) || (flags & PL_BT_USER) == 0

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
# DIVERGES: the ported entries only (upstream's table also has `prolog_frame_attribute/3` and the
# other debugger predicates, pl-trace.c:2830-2840); `prolog_interrupt/0` is refused by name.
"pl-trace.c's registration table (`BeginPredDefs(trace)`): the ported entries."
const PL_predicates_from_trace = (
    PL_extension("prolog_current_choice", 1, pl_prolog_current_choice1_va, PL_FA_VARARGS),
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
