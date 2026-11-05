# UPSTREAM: swipl-devel src/pl-pro.c @ cbf4e1896275
# CLASS: code
# COPYRIGHT: Copyright (c)  1985-2022, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
#
# PORTED FROM pl-pro.c, exactly these: `callProlog` — calling a goal from foreign code, in a query
# of its own — and `sig_atomic/1`, its first caller: boot/init.pl's `setup_call_cleanup/3` and
# `setup_call_catcher_cleanup/4` run their Setup goal through it, as once/1; and (BOOTPRED3)
# `'$notrace'/2` and `'$restore_trace'/2`, which boot/init.pl's notrace/1 and print_message/2 use to
# switch the debugger off around a goal; since DBG1-SMALL they save and restore the debugger status of the local data
# (`ld.debugstatus_*`, R2 F1c) and `'$notrace'/2` sets the normal run mode, as upstream does.
#
# Since HALT1: `abortProlog` and `abort/0` (the `unwind(abort)` ball), `raise_halt_exception` (the
# `unwind(halt(Status))` ball `halt/1` raises). `halt_from_exception` and `restore_after_exception` are
# ported with `query_loop` since R2 TOP1.
#
# Since R2 TOP1: `resetProlog` (it resets the autoloader's chain and loop mark, `autoload_nesting`, `autoload_loop`),
# `restore_after_exception`, `halt_from_exception` and `query_loop`. Since R2 TOP1b: `currentBreakLevel` (`LD->break_level`, -1
# outside a toplevel); `prologToplevel` and `pl_break` follow in the same step.
#
# LEFT OUT: the rest of pl-pro.c — the toplevel (`pl_break`, `prologToplevel`),
# `'$notrace'/1`, `'$call_no_catch'/1`, `'$can_yield'/0`, the other entries of the table (pl-pro.c:1060-1069),
# `'$trap_gdb'/0`, the metacut `!/0` (`pl_metacut`), `checkStacks` and the C-stack queries.

# PORT: pl-pro.c callProlog
# DIVERGES: the database `gd` is an argument; `module` is an index into its module table (0 for
# NULL: the context module, `user` until R2). The functor is its name and arity. `ex` is a reference
# to a term_t (upstream: `term_t *ex`), `nothing` for NULL. NOT PORTED: `require_c_stack` (no C stack).
"""
    callProlog(gd, ld, module, goal, flags[, ex]) -> Bool

Call the goal in term reference `goal` once, in a query of its own with `flags`, keeping its
bindings (pl-pro.c). False when it fails or raises; with `PL_Q_PASS_EXCEPTION` the exception stays
pending. With `ex` (a reference to a term reference) an exception is handed to the caller in `ex[]`
(0: none) and cleared; the term references from `ex`'s on stay for the caller to reset. The caller
provides the foreign frame.
"""
function callProlog(
    gd::PL_global_data{T}, ld::PL_local_data{T}, module_::Int, goal::term_t, flags::UInt32,
    ex::Union{Nothing, Base.RefValue{Int}}
)::Bool where {T}
    @assert ld.lTop ==
        refFliP(ld.fliframes[ld.fli_context].base, ld.fliframes[ld.fli_context].size)

    reset = 0
    ex2 = 0
    if ex !== nothing
        ex2 = PL_new_term_ref(ld)
        ex[] = 0
    end

    g = PL_new_term_ref(ld)
    ok, m = PL_strip_module(gd, ld, goal, module_, g)
    ok || return false
    fd = PL_get_functor(ld, g)
    if fd === nothing                                   # !PL_get_functor(g, &fd)
        PL_error(ld, ERR_TYPE, mk_sym(T, :callable), goal)  # ERR_TYPE: `rewrite_callable` strips `goal`'s qualifiers
        ex !== nothing && (ex[] = ld.exception_term)

        PL_reset_term_refs(ld, g)
        return false
    end
    name, arity = fd

    # Quick check for sig_atomic(true) resulting from the call_cleanup series
    if arity == 0 && sym_key(name) == gd.subclause_names.atom_true     # fd == FUNCTOR_true0
        return true
    end

    proc = resolveProcedure(gd, name, arity, gd.modules[m])

    args = PL_new_term_refs(ld, arity)
    for n in 0:(arity - 1)
        _PL_get_arg(ld, n + 1, g, args + n)
    end

    if (flags & PL_Q_PASS_EXCEPTION) != 0
        used, rc = call_internal_det_foreign(gd, ld, proc, args)
        if used
            rval = rc != FFALSE && ld.exception_term == 0
            if !rval && ex !== nothing && ld.exception_term != 0
                PL_put_term(ld, ex2, ld.exception_term)
                ex[] = ex2
                reset = g
            end
            reset == 0 && (reset = ex2 != 0 ? ex2 : g)
            PL_reset_term_refs(ld, reset)
            return rval
        end
    end

    qid = PL_open_query(gd, ld, gd.modules[m], flags, proc, args)
    rval = PL_next_solution(gd, ld, qid) != 0

    if !rval && ex !== nothing
        qex = PL_exception(ld, qid)
        if qex != 0
            PL_put_term(ld, ex2, qex)
            ex[] = ex2
            reset = g
        else
            ex[] = 0
        end
    end

    PL_cut_query(ld, qid)
    if rval && ld.exception_term != 0
        if ex !== nothing
            PL_put_term(ld, ex2, ld.exception_term)
            PL_clear_exception(ld)
            ex[] = ex2
            reset = g
        end
        rval = false
    end

    reset == 0 && (reset = ex2 != 0 ? ex2 : g)
    PL_reset_term_refs(ld, reset)

    return rval
end

function callProlog(
    gd::PL_global_data{T}, ld::PL_local_data{T}, module_::Int, goal::term_t, flags::UInt32
)::Bool where {T}
    return callProlog(gd, ld, module_, goal, flags, nothing)
end

# PORT: pl-pro.c sig_atomic as pl_sig_atomic1_va
# (PRED_IMPL("sig_atomic", 1, sig_atomic, PL_FA_TRANSPARENT|PL_FA_SIG_ATOMIC))
# DIVERGES: NOT PORTED: `startCritical`/`endCritical` — blocking signals while the goal runs, and
# failing when it was aborted: the kernel has no signals.
"`sig_atomic(:Goal)`: execute `Goal` as once/1 (pl-pro.c; upstream: while blocking signals)."
function pl_sig_atomic1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    rval = callProlog(_query_gd(ld), ld, 0, A1, PL_Q_PASS_EXCEPTION)

    return rval ? FTRUE : FFALSE
end

# PORT: pl-pro.c abortProlog
# DIVERGES: left out: the trace and debug mode switches (the kernel keeps no debugger state), the discard of pending
# input and the O_MAINTENANCE backtrace. The cycle stacks (`LD->cycle.lstack`,
# `LD->cycle.vstack`) are the kernel's `cycle_cells` with its saved words and `cycle_vstack`, cleared as upstream
# clears them. The ball is built from term references, as `PL_unify_term(ex, PL_FUNCTOR, FUNCTOR_unwind1,
# PL_ATOM, ATOM_abort)` (see src/pl-error.jl); a foreign frame brackets it, as upstream.
"Raise `unwind(abort)`: false, the exception pending (pl-pro.c)."
function abortProlog(ld::PL_local_data{T})::Bool where {T}
    rc = false

    ld.exception_processing = true                      # allow using spare stack
    fid = PL_open_foreign_frame(ld)
    ex = _message_term(ld, :unwind, _err_atom(ld, mk_sym(T, :abort)))   # PL_unify_term(ex, …unwind1, PL_ATOM, ATOM_abort)
    empty!(ld.cycle_cells)                              # clearSegStack(&LD->cycle.lstack) (with its saved words)
    empty!(ld.cycle_saved)
    empty!(ld.cycle_vstack)                             # clearSegStack(&LD->cycle.vstack)
    rc = PL_raise_exception(ld, ex)
    PL_close_foreign_frame(ld, fid)

    return rc
end

# PORT: pl-pro.c abort as pl_abort0_va
# (PRED_IMPL("abort", 0, abort, 0))
"`abort/0`: raise `unwind(abort)` (pl-pro.c); `catch/3` sees the ball."
function pl_abort0_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return abortProlog(ld) ? FTRUE : FFALSE
end

# PORT: pl-pro.c raise_halt_exception
# DIVERGES: the trace switch is left out (the kernel keeps no debugger state); the running-query form of
# `handles_unwind` is `handles_unwind(ld, 0, …)` (src/pl-wam.jl). The ball is built as `abortProlog`'s. Upstream's allocation-failure paths (the frame, the
# reference or the unification failing: the ball is not raised) cannot happen here, as in src/pl-error.jl.
"""
    raise_halt_exception(ld, status, force) -> Bool

Raise `unwind(halt(Code))`, `Code = status & PL_CLEANUP_STATUS_MASK`, where the running query can handle it
(`PL_Q_EXCEPT_HALT`) or `force` is set, and return true; false, nothing raised, where it cannot (pl-pro.c).
"""
function raise_halt_exception(
    ld::PL_local_data{T}, status::Int, force::Bool
)::Bool where {T}
    code = status & PL_CLEANUP_STATUS_MASK

    ld.exception_processing = true                      # allow using spare stack

    if force || handles_unwind(ld, 0, PL_Q_EXCEPT_HALT)
        fid = PL_open_foreign_frame(ld)
        ex = _message_term(ld, :unwind, _message_term(ld, :halt, _err_int(ld, code)))   # PL_unify_term(ex, …unwind1, …halt1, PL_INT, code)
        PL_raise_exception(ld, ex)
        PL_close_foreign_frame(ld, fid)
        return true
    end

    return false
end

# PORT: pl-pro.c NOTRACE_TRACE
"The bits of `'\$notrace'/2`'s saved flags (pl-pro.c): tracing, debugging, last-call optimisation, VMI built-ins."
const NOTRACE_TRACE = 0x1
# PORT: pl-pro.c NOTRACE_DEBUG
const NOTRACE_DEBUG = 0x2
# PORT: pl-pro.c NOTRACE_LCO
const NOTRACE_LCO = 0x4
# PORT: pl-pro.c NOTRACE_VMI
const NOTRACE_VMI = 0x8

# PORT: pl-pro.c notrace as pl_notrace2_va
# (PRED_IMPL("$notrace", 2, notrace, PL_FA_NOTRACE), pl-pro.c:317-348 at the pin)
# DIVERGES: `debugstatus` is the local data's `debugstatus_*` fields (one engine, src/pl-global.jl); the two prolog-flag
# bits are the kernel's `prolog_flag_mask`; `setPrologRunMode(RUN_MODE_NORMAL)` is `setPrologRunMode!(ld, RUN_MODE_NORMAL)`.
# The kernel has no tracer to stop, so the debugger status is data here (DBG1 owns the tracer that reads it).
"""
    '\$notrace'(-Flags, -SkipLevel)

Unify `Flags` with the debugger's saved state (pl-pro.c: `NOTRACE_*` bits) and `SkipLevel` with its skip level
(-1: `SKIP_VERY_DEEP`, -2: `SKIP_REDO_IN_SKIP`), then switch tracing and debugging off. Used by boot/init.pl's
notrace/1 and print_message/2 with `'\$restore_trace'/2`.
"""
function pl_notrace2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    flags = 0

    ld.debugstatus_tracing && (flags |= NOTRACE_TRACE)
    ld.debugstatus_debugging && (flags |= NOTRACE_DEBUG)
    truePrologFlag(ld, PLFLAG_LASTCALL) && (flags |= NOTRACE_LCO)
    truePrologFlag(ld, PLFLAG_VMI_BUILTIN) && (flags |= NOTRACE_VMI)

    if ld.debugstatus_skiplevel == SKIP_VERY_DEEP
        sl = -1                                         # debugstatus.skiplevel == SKIP_VERY_DEEP
    elseif ld.debugstatus_skiplevel == SKIP_REDO_IN_SKIP
        sl = -2
    else
        @assert ld.debugstatus_skiplevel <= UInt(typemax(Int64))        # assert(sl >= 0 && sl <= SIZE_MAX)
        sl = Int64(ld.debugstatus_skiplevel)
    end

    if PL_unify_integer(ld, A1, flags) && PL_unify_int64(ld, A2, sl)
        ld.debugstatus_tracing = false
        ld.debugstatus_debugging = false
        ld.debugstatus_skiplevel = SKIP_VERY_DEEP
        setPrologRunMode!(ld, RUN_MODE_NORMAL)
        updateAlerted(ld)

        return FTRUE
    end

    return FFALSE
end

# PORT: pl-pro.c restoretrace as pl_restore_trace2_va
# (PRED_IMPL("$restore_trace", 2, restoretrace, PL_FA_NOTRACE), pl-pro.c:350-390 at the pin)
# DIVERGES: as `pl_notrace2_va` (the debugger status is the local data's fields). A depth beyond `SIZE_MAX` cannot
# occur in an `Int` (`depthi > SIZE_MAX` is upstream's second refusal).
"""
    '\$restore_trace'(+Flags, +SkipLevel)

Restore what `'\$notrace'/2` saved: the tracing and debugging status, the skip level and the last-call optimisation and
VMI built-in flag bits (pl-pro.c); `Flags` must be an `int` and `SkipLevel` an `int64` (`representation_error(size_t)` for a negative depth other than -1 and -2).
"""
function pl_restore_trace2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1

    flags = PL_get_integer_ex(ld, A1)
    flags === nothing && return FFALSE
    depthi = PL_get_int64_ex(ld, A2)
    depthi === nothing && return FFALSE

    if depthi != -1 && depthi != -2 && depthi < 0
        return PL_error(ld, ERR_REPRESENTATION, mk_sym(T, :size_t)) ? FTRUE : FFALSE   # PL_representation_error("size_t")
    end

    depth = if depthi == -1
        SKIP_VERY_DEEP
    elseif depthi == -2
        SKIP_REDO_IN_SKIP
    else
        UInt(depthi)
    end
    ld.debugstatus_tracing = (flags & NOTRACE_TRACE) != 0
    ld.debugstatus_debugging = (flags & NOTRACE_DEBUG) != 0
    ld.debugstatus_skiplevel = depth

    if (flags & NOTRACE_LCO) != 0
        setPrologFlagMask!(ld, PLFLAG_LASTCALL)
    else
        clearPrologFlagMask!(ld, PLFLAG_LASTCALL)
    end

    if (flags & NOTRACE_VMI) != 0
        setPrologFlagMask!(ld, PLFLAG_VMI_BUILTIN)
    else
        clearPrologFlagMask!(ld, PLFLAG_VMI_BUILTIN)
    end

    updateAlerted(ld)

    return FTRUE
end

# PORT: pl-pro.c resetProlog
# DIVERGES: the local data is the only argument (upstream's `GET_LD`); `clear_stacks` is a Bool.
# `Scurin = in` and `Scurout = Suser_output` are the raw assignments of upstream's macros (no reference
# counts). `gc_status.blocked`, `LD->shift_status.blocked` and `LD->in_print_message` are the garbage collector's and
# `print_message/2`'s (the kernel's stacks grow by doubling, src/pl-gc.jl, and its messages go through `printMessage`): their
# resets belong to the steps that port those counters. `LD->depth_info.limit = DEPTH_NO_LIMIT` is the depth limit's (P3, the
# `$depth_limit*` family). The nesting is a vector (A2), emptied; `autoload.loop` is `nothing`.
"""
    resetProlog(ld, clear_stacks) -> true

Bring the engine back to a sane state before the toplevel runs a goal again: clear an error on `user_input` (the next read
prompts), make the user streams the current ones, clear the pending exception, reset the debugger and, with `clear_stacks`
and no global variable, empty the stacks; the autoloader's chain and loop mark are reset (pl-pro.c).
"""
function resetProlog(ld::PL_local_data, clear_stacks::Bool)::Bool
    in = Suser_input(ld)

    if in !== nothing && Sferror(in) != 0
        Sclearerr(in)
        ld.prompt_next = true
    end

    ld.IO_streams[SNO_CURRENT_INPUT + 1] = in                   # Scurin  = in
    ld.IO_streams[SNO_CURRENT_OUTPUT + 1] = Suser_output(ld)    # Scurout = Suser_output

    PL_clear_exception(ld)
    resetTracer(ld)

    if clear_stacks
        if isempty(ld.gvar_nb_vars)                             # we would loose nb_setval/2 vars
            emptyStacks!(ld)
        end
        # gc_status.blocked = 0; LD->shift_status.blocked = 0; LD->in_print_message = 0
    end

    empty!(ld.autoload_nesting)                                 # LD->autoload.nesting = NULL
    ld.autoload_loop = nothing                                  # LD->autoload.loop = NULL
    updateAlerted(ld)

    return true
end

# PORT: pl-pro.c restore_after_exception
# DIVERGES: the database and the local data are arguments; `except` is a term reference. The message term is built as
# `abortProlog`'s.
"Switch tracing and debugging off after an exception; after `unwind(abort)` call the `abort` event and print the message (pl-pro.c)."
function restore_after_exception(
    gd::PL_global_data{T}, ld::PL_local_data{T}, except::term_t
)::Bool where {T}
    rc = true

    tracemode(ld, false, nothing)
    debugmode(ld, false, nothing, UInt32(0))
    if classify_exception(ld, except) == EXCEPT_ABORT
        rc =
            callEventHook(gd, ld, PLEV_ABORT) &&
            printMessage(                                       # PL_FUNCTOR, FUNCTOR_unwind1, PL_ATOM, ATOM_abort
                ld, :informational,
                _message_term(ld, :unwind, _err_atom(ld, mk_sym(T, :abort)))
            )
    end

    return rc
end

# PORT: pl-pro.c halt_from_exception
# DIVERGES: the database and the local data are arguments; the ball is read on its words as `classify_exception_cells` reads it.
"Halt the system with the status of the ball `unwind(halt(Status))` in `ex` (`Status & 0xff`); false for another ball (pl-pro.c)."
function halt_from_exception(
    gd::PL_global_data{T}, ld::PL_local_data{T}, ex::term_t
)::Bool where {T}
    unwind1 = lookupFunctorDef(ld.functors, _atom_word!(ld, mk_sym(T, :unwind)), 1)
    halt1 = lookupFunctorDef(ld.functors, _atom_word!(ld, mk_sym(T, :halt)), 1)
    k, w, _ = _deref_loc(ld, -(ex + 1))                         # valTermRef(ex); deRef
    if k == DU_WORD && _is_gcompound(w)
        q = valPtr(w)
        if ld.gstack[q] == unwind1                              # hasFunctor(*p, FUNCTOR_unwind1)
            ka, wa, _ = _deref_loc(ld, q + 1)                   # p = argTermP(*p, 0); deRef(p)
            if ka == DU_WORD && _is_gcompound(wa)
                qa = valPtr(wa)
                if ld.gstack[qa] == halt1                       # hasFunctor(*p, FUNCTOR_halt1)
                    kb, wb, _ = _deref_loc(ld, qa + 1)
                    if kb == DU_VALUE && isTaggedIntW(wb)
                        status = valInt(wb)

                        return PL_halt(gd, ld, Int(status & 0xff))
                    end
                end
            end
        end
    end

    return false
end

# PORT: pl-pro.c query_loop
# DIVERGES: the database and the local data are arguments; `goal` is the atom, its predicate `system:Goal/0` (`PL_pred`, which
# creates it: `lookupProcedure`). One thread: `PL_thread_self()` is 1, so `halt_from_exception` is always tried, and `LD->thread.exit_requested`
# (`O_ENGINES`) is never set. The error exit (`goto error`) leaves the loop with the foreign frame still open, as upstream: the
# next `resetProlog` that empties the stacks closes it. The result is an Int, `rc` of upstream: 1, 0, -1.
"""
    query_loop(gd, ld, goal, loop) -> Int

Run the zero-argument predicate `system:goal` on behalf of the toplevel and return 1 (success), 0 (failure) or -1 (exception).
After an exception, with `loop` and unless it is a halt or a thread exit, the goal is run again once the system is restored
to a sane state (`resetProlog`, `restore_after_exception`); a halt ball halts the system (`halt_from_exception`) (pl-pro.c).
"""
function query_loop(
    gd::PL_global_data{T}, ld::PL_local_data{T}, goal::T, loop::Bool
)::Int where {T}
    rc = 0
    clear_stacks = ld.query == 0                                # LD->query == NULL

    if loop
        enable_debug_on_interrupt(ld, true)
    end

    while true                                                  # do { … } while(loop)
        fid = 0
        qid = 0
        except = 0

        ok = resetProlog(ld, clear_stacks)
        if ok
            fid = PL_open_foreign_frame(ld)
            ok = fid != 0
        end
        if ok
            p = lookupProcedure(goal, 0, MODULE_system(gd))         # PL_pred(PL_new_functor(goal, 0), MODULE_system)
            qid = PL_open_query(
                gd, ld, MODULE_system(gd), PL_Q_NORMAL | PL_Q_EXCEPT_HALT, p,
                PL_new_term_refs(ld, 0)
            )
            if qid != 0
                rc = PL_next_solution(gd, ld, qid)
            else
                ok = false
            end
        end
        if !ok                                                  # error:
            except = ld.exception_term
            rc = -1                                             # Won't get any better
            break
        end

        if rc == 0 && (except = PL_exception(ld, qid)) != 0
            exclass = classify_exception(ld, except)

            if exclass == EXCEPT_ABORT
                Sclearerr(Suser_input(ld)::IOSTREAM)
            elseif exclass == EXCEPT_HALT
                loop = false
                halt_from_exception(gd, ld, except)             # me < 0 || me == 1: the one thread
            elseif exclass == EXCEPT_THREAD_EXIT
                loop = false
            end

            validUserStreams(ld) || (loop = false)

            restore_after_exception(gd, ld, except)
            rc = -1
        end

        qid != 0 && PL_close_query(ld, qid)
        fid != 0 && PL_discard_foreign_frame(ld, fid)
        except == 0 && break
        loop || break                                           # } while(loop)
    end

    return rc
end

# PORT: pl-pro.c currentBreakLevel
# DIVERGES: the local data is the argument (upstream's `GET_LD`).
"The nesting level of the toplevel: 0 in the first, higher in a `break/0`, -1 when no toplevel runs (pl-pro.c)."
currentBreakLevel(ld::PL_local_data)::Int = ld.break_level

# PORT: pl-pro.c BeginPredDefs as PL_predicates_from_pro
# DIVERGES: the registered entries only (upstream's table has eight, pl-pro.c:1060-1069).
"pl-pro.c's registration table (`BeginPredDefs(pro)`): the registered entries."
const PL_predicates_from_pro = (
    PL_extension("abort", 0, pl_abort0_va, PL_FA_VARARGS),
    PL_extension(
        "sig_atomic", 1, pl_sig_atomic1_va,
        PL_FA_VARARGS | PL_FA_TRANSPARENT | PL_FA_SIG_ATOMIC
    ),
    PL_extension("\$notrace", 2, pl_notrace2_va, PL_FA_VARARGS | PL_FA_NOTRACE),
    PL_extension("\$restore_trace", 2, pl_restore_trace2_va, PL_FA_VARARGS | PL_FA_NOTRACE)
)
