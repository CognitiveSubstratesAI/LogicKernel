# UPSTREAM: swipl-devel src/pl-setup.c @ 18168e629eab
# UPSTREAM: swipl-devel src/pl-incl.h @ 18168e629eab
# UPSTREAM: swipl-devel src/SWI-Prolog.h @ 18168e629eab
# CLASS: code
# COPYRIGHT: Copyright (c)  1985-2024, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# What the kernel takes from SWI-Prolog's start-up (pl-setup.c): allocating and emptying the stacks
# of a thread, which leaves one foreign frame at the base of the local stack; since V5d the local
# stack's spare — room reserved above its `max` for handling a stack overflow — given back after
# an exception (`trim_stack`, `trimStacks`).

# setup:1631 the local stack's spare: `512*SIZEOF_WORD + LOCAL_MARGIN` bytes, here in positions.
"The spare of a new local stack, in positions (pl-setup.c `allocStacks`)."
const LOCAL_SPARE = 512 + LOCAL_MARGIN
# setup:1630, :1634 the global stack's spare, `512*SIZEOF_WORD`, and the trail's, `256*SIZEOF_WORD`.
"The spare of a new global stack, in positions (pl-setup.c `allocStacks`)."
const GLOBAL_SPARE = 512
"The spare of a new trail, in positions (pl-setup.c `allocStacks`)."
const TRAIL_SPARE = 256

# PORT: pl-setup.c init_stack as init_stack!
# DIVERGES: the local stack's, in positions; there is no name (the overflow's context names it,
# src/pl-alloc.jl), `min_free` (the kernel's growth doubles, src/pl-gc.jl `growStacks!`), `gced_size`
# or GC policy (the collector's `gced_size` and `min_free` are `ld.gc.global_policy` and `ld.gc.trail_policy`, src/pl-gc.jl; the local
# stack has none). The cells and the record pools are grown to
# `size` (`_resize_local!`); `stack_malloc` allocated them upstream.
"Set up the local stack: `size` positions, of which `spare` are reserved above its `max` (pl-setup.c)."
function init_stack!(ld::PL_local_data{T}, size::Int, spare::Int)::Nothing where {T}
    ld.lTop = 0                                 # s->top = s->base
    _resize_local!(ld, size)
    ld.local_spare = spare
    ld.local_def_spare = spare
    ld.lMax = size - spare                      # s->max = addPointer(s->base, size - spare)
    return nothing
end

# PORT: pl-setup.c allocStacks as allocStacks!
# DIVERGES: the local stack's cells — there is no global, trail or argument stack of fixed size (they
# grow on demand) — and in positions: `minlocal` (4 K words) is `LOCAL_INITIAL`, its spare
# `LOCAL_SPARE`; the global stack's and the trail's spares are reserves in the one limit (since L1f f1b,
# `_stacks_in_use`); nothing is allocated that can fail. `stacks.local.min_free` is not kept (see `init_stack!`).
"Allocate the local stack of a new thread (pl-setup.c)."
function allocStacks!(ld::PL_local_data{T})::Bool where {T}
    ld.global_spare = ld.global_def_spare = GLOBAL_SPARE    # init_stack(global, …, 512*SIZEOF_WORD)
    init_stack!(ld, LOCAL_INITIAL, LOCAL_SPARE)
    ld.trail_spare = ld.trail_def_spare = TRAIL_SPARE       # init_stack(trail, …, 256*SIZEOF_WORD)
    ld.trail_size = TRAIL_INITIAL                           # itrail = nextStackSizeAbove(mintrail-1) (pl-setup.c:1601/1604; G1: a modelled size, `_growTrail!`)
    return true
end

# PORT: pl-setup.c trim_stack as trim_stack!
# DIVERGES: the local stack's, in positions.
"Reserve the local stack's spare again above its `max`, as far as its free room allows (pl-setup.c)."
function trim_stack!(ld::PL_local_data{T})::Nothing where {T}
    if ld.local_spare < ld.local_def_spare
        reduce = ld.local_def_spare - ld.local_spare
        room = ld.lMax - ld.lTop                # roomStackP(s)
        if room > 0 && room < reduce
            reduce = room
        end
        ld.lMax -= reduce                       # s->max = addPointer(s->max, -reduce)
        ld.local_spare += reduce
    end
    return nothing
end

# PORT: pl-setup.c trim_stack as trim_stack_global!
# DIVERGES (since L1f f1b): the global stack's spare is a reserve in the one limit (`_stacks_in_use`), so its
# free room is what the limit leaves (`stacks_limit - _stacks_in_use`). As upstream, a reserve the room
# cannot hold is kept whole (`room > 0 && room < reduce`): after an overflow trimStacks(resize) shrinks the
# local stack first (`growStacks_trim!`, GROW_TRIM), which gives the room back.
"Reserve the global stack's spare again, as far as the room under the limit allows (pl-setup.c)."
function trim_stack_global!(ld::PL_local_data)::Nothing
    if ld.global_spare < ld.global_def_spare
        reduce = ld.global_def_spare - ld.global_spare
        room = ld.stacks_limit - _stacks_in_use(ld, 0)      # roomStackP(s)
        if room > 0 && room < reduce
            reduce = room
        end
        ld.global_spare += reduce                           # s->max -= reduce; s->spare += reduce
    end
    return nothing
end

# PORT: pl-setup.c trim_stack as trim_stack_trail!
# DIVERGES (since L1f f1b): as `trim_stack_global!`, the trail's.
"Reserve the trail's spare again, as far as the room under the limit allows (pl-setup.c)."
function trim_stack_trail!(ld::PL_local_data)::Nothing
    if ld.trail_spare < ld.trail_def_spare
        reduce = ld.trail_def_spare - ld.trail_spare
        room = ld.stacks_limit - _stacks_in_use(ld, 0)      # roomStackP(s)
        if room > 0 && room < reduce
            reduce = room
        end
        ld.trail_spare += reduce
    end
    return nothing
end

# PORT: pl-setup.c trimStacks as trimStacks!
# DIVERGES: `resize` is `growStacks_trim!` (upstream's `growStacks(GROW_TRIM, GROW_TRIM, GROW_TRIM)`, since L1f
# f1b under audit D-0049: the local stack shrunk again after an overflow, the spares re-reserved as it
# shrinks); without it the three spares are reserved again (`trim_stack!`, `_global!`, `_trail!`). `lTop` is
# raised to the query's saved argument pointer while the spares are reserved, as upstream's.
# `LD->trim_stack_requested` is cleared first (pl-setup.c:1715); `outOfStack!` sets it and `garbageCollect` reads it (G1-A);
# SECURE_GC's clearing and the debug checks are left out.
"Reclaim the local stack's spare after an exception (pl-setup.c)."
function trimStacks!(ld::PL_local_data{T}, resize::Bool)::Nothing where {T}
    ld.trim_stack_requested = false             # LD->trim_stack_requested = false
    resize && growStacks_trim!(ld)              # growStacks(GROW_TRIM, GROW_TRIM, GROW_TRIM)
    lsave = ld.lTop
    if ld.query != 0                            # saved registers above lTop
        q = ld.queries[ld.query]
        if q.registers_fr != 0 && q.registers_argp.form == ARGP_SLOT &&
            q.registers_argp.pos > ld.lTop
            ld.lTop = q.registers_argp.pos
        end
    end
    if !resize
        trim_stack!(ld)
        trim_stack_global!(ld)
        trim_stack_trail!(ld)
    end
    ld.lTop = lsave
    return nothing
end

# PORT: pl-setup.c emptyStacks as emptyStacks!
# DIVERGES: the argument stack is emptied.
# `BFR` and `LD->query` are cleared with the stack they point into; there is no `mark_bar`, and no
# `lTop && gTop` guard (the stacks always exist). Of the
# engine's permanent term references upstream allocates in the base foreign frame, the exception's
# four are (`exception_bin`, `exception_printed`, `exception.tmp`, `exception.pending`, in
# upstream's order), then since AV1 `attvar.head` and `attvar.tail`, each with a PERMANENT global cell
# (audit D-0122 Q1 (a), a representation-only divergence: upstream assigns the two local-stack cells
# themselves, pl-attvar.c:127 "on local stack!", and its own TBD, pl-wam.c:1565, names the global
# stack); the others belong to subsystems not ported (`trim.dummy`; nor
# `destroyGlobalVars`); `attvar.gc_attvars`, the collector's reference to the newest attvar link, is not made here: `save_grefs`
# (src/pl-gcmark.jl) makes it for the length of a collection, in a foreign frame of its own, and `restore_grefs` reads it back; since TAB1 TB4 `tabling.delay_list` (`init_delay_list`, after the
# attvar pair as upstream), since TB6 `tabling.idg_current` (one more reference and permanent cell, right after it as upstream).
# Since TX1e the undo list's cell is the FIRST global cell (`init_undo_list`, pl-setup.c:1557
# "must be first": `Undo!` finds it by position 1), allocated before the permanent cells above; it is not a term reference. So later term references
# lie at other absolute positions than in
# swipl: compare DIFFERENCES between positions with swipl, never absolute ones.
"Empty the local stack and the trail, then open the base foreign frame (pl-setup.c)."
function emptyStacks!(ld::PL_local_data{T})::Nothing where {T}
    ld.environment_frame = 0                    # environment_frame = NULL;
    ld.fli_context = 0                          # fli_context = NULL;
    ld.BFR = 0

    ld.lTop = 0                                 # emptyStack((Stack)&LD->stacks.local);
    ld.nframes = 0
    ld.nchoices = 0
    ld.nfliframes = 0
    ld.nqueries = 0
    ld.query = 0                                # LD->query = NULL;
    ld.aTop = 0                                 # emptyStack((Stack)&LD->stacks.argument);
    empty!(ld.trail)                            # emptyStack((Stack)&LD->stacks.trail);
    ld.gTop = 0                                 # emptyStack((Stack)&LD->stacks.global);
    _truncate_vtable!(ld)                       # (the value table with it: L1b stage C2)
    ld.mark_bar = ld.gTop                       # LD->mark_bar = gTop;

    PL_open_foreign_frame(ld)                   # (its Mark sets mark_bar = gTop, still 0: the undo cell comes after, as in pl-setup.c:1540-1557)
    ld.undo_list = init_undo_list(ld)           # LD->undo.undo_list = init_undo_list(): FIRST global cell, see __do_undo() (TX1e)
    ld.exception_term = 0
    ld.exception_bin = PL_new_term_ref(ld)
    ld.exception_printed = PL_new_term_ref(ld)
    ld.exception_tmp = PL_new_term_ref(ld)                     # LD->exception.tmp
    ld.exception_pending = PL_new_term_ref(ld)                 # LD->exception.pending
    # the three the kernel RESETS (`setVar(*valTermRef(…))`, pl-wam.c resumeAfterException and
    # restore_after_query): their cells, made here below every mark the engine will take, are
    # PERMANENT — a reset makes the slot reference its cell again, unbound (`_reset_exception_slot!`).
    # Until 2026-10-15 a reset allocated a FRESH cell, which the next `Undo!` freed with the slot
    # still pointing at it; the next query laid a compound over the position and
    # `classify_exception` read its functor cell as a value word (test_db.jl's BoundsError).
    ld.exception_cells = unRef(ld.slots[ld.exception_bin + 1])
    @assert unRef(ld.slots[ld.exception_printed + 1]) == ld.exception_cells + 1
    @assert unRef(ld.slots[ld.exception_pending + 1]) == ld.exception_cells + 3
    # the wakeup list's two (AV1; audit D-0122 Q1 (a)): upstream's are cells of the LOCAL stack, assigned
    # with `TrailAssignment` ("on local stack!", pl-attvar.c); here each slot references a PERMANENT global
    # cell, as the exception's three, so the list lives in the cell ("empty" = the cell unbound) and every
    # trail entry stays global — upstream's own TBD (pl-wam.c, `TrailAssignment`'s comment) names the
    # global stack.
    ld.attvar_head = PL_new_term_ref(ld)                       # LD->attvar.head
    ld.attvar_tail = PL_new_term_ref(ld)                       # LD->attvar.tail
    @assert unRef(ld.slots[ld.attvar_tail + 1]) == unRef(ld.slots[ld.attvar_head + 1]) + 1
    ld.tabling.delay_list = init_delay_list(ld)                # LD->tabling.delay_list = init_delay_list(); (pl-setup.c:1558, TAB1 TB4)
    # TB6: the current IDG node (pl-setup.c:1559 `LD->tabling.idg_current = PL_new_term_ref()`, right after the delay list): its slot
    # references a PERMANENT global cell, as the wakeup list's head, so `set_idg_current` trails a global cell (src/pl-tabling.jl).
    ld.tabling.idg_current = PL_new_term_ref(ld)
    ld.tmp_h = PL_new_term_refs(ld, TMP_PTR_SIZE)              # for(i…) LD->tmp.h[i] = PL_new_term_ref()
    ld.tmp_top = 0                                             # LD->tmp.top = 0
    ld.tmp_cells = unRef(ld.slots[ld.tmp_h + 1])               # (PERMANENT, as the exception's: popTermRef)
    return nothing
end

# PORT: pl-setup.c gc_handler
# (pl-setup.c:829-834 at the pin, registered at :931 `PL_signal(SIG_GC|PL_SIGSYNC, gc_handler)`:
#     static void
#     gc_handler(int sig)
#     { (void)sig;
#       garbageCollect(0);
#     }
# DIVERGES: the collector is given the VM-state callback (`get_vmi_state`), as every kernel caller of `garbageCollect`; reason 0 takes
# `LD->gc.stats.request` (`gc_stat_start!`, pl-gc.c:573-574).
"The handler of `SIG_GC`: run the stack collector for the requested reason (pl-setup.c `gc_handler`)."
function gc_handler(ld::PL_local_data, sig::Int)::Nothing
    garbageCollect(ld, 0; vmi_state_of=get_vmi_state)
    return nothing
end

# PORT: pl-setup.c gc_tune_handler
# (pl-setup.c:836-841 at the pin, registered at :932 `PL_signal(SIG_TUNE_GC|PL_SIGSYNC, gc_tune_handler)`:
#     static void
#     gc_tune_handler(int sig)
#     { (void)sig;
#       call_tune_gc_hook();
#     }
"The handler of `SIG_TUNE_GC`: call the `prolog:tune_gc/3` hook (pl-setup.c `gc_tune_handler`)."
function gc_tune_handler(ld::PL_local_data, sig::Int)::Nothing
    call_tune_gc_hook(ld)
    return nothing
end

# PORT: pl-setup.c dispatch_signal as _dispatch_gc_signal
# DIVERGES (G1-C, dispatcher decision 1): only the two collector signals have a handler (`PL_signal(SIG_GC|PL_SIGSYNC, gc_handler)` and
# `SIG_TUNE_GC`'s, pl-setup.c:931-932, both C handlers: `dispatch_signal` calls `sh->handler(sig)` for them). The rest of `dispatch_signal`
# (Prolog handlers, `PLSIG_THROW`, the frame it opens, the OS signals) is the signal owner's (`on_signal/4`, Q10/TH1); no other bit is raised
# here, so another number is refused by name.
"Run the handler of the virtual signal `sig` (pl-setup.c `dispatch_signal`, the collector's two)."
function _dispatch_gc_signal(ld::PL_local_data{T}, sig::Int)::Nothing where {T}
    if sig == SIG_GC
        gc_handler(ld, sig)
    elseif sig == SIG_TUNE_GC
        gc_tune_handler(ld, sig)
    else
        throw(
            NotPortedError{T}(
                mk_sym(T, :signal),
                "dispatch_signal for signal $sig",
                "Q10/TH1 (on_signal/4)"
            )
        )
    end
    return nothing
end

# PORT: pl-setup.c handleSignals
# (pl-setup.c:1225-1270 at the pin)
# DIVERGES (G1-C, dispatcher decision 1): the pending signals are the bits of `ld.gc.sig_pending` (bit `sig - SIG_PROLOG_OFFSET`: one word,
# `SIGMASK_WORDS` 1, the first signal `SIG_PROLOG_OFFSET`), dispatched by `_dispatch_gc_signal`. `HAS_LD` always holds; `handleSigInt` is not
# Unix's. `LD->critical` is not kept: its writers (`startCritical`: sig_atomic/1, src/pl-pro.jl; the cleanup handler, src/pl-wam.jl) are
# themselves left to the signal owner, so a pending collection is served inside such a region where upstream serves it at the next safe
# point after it; the collector keeps every reachable term, so only the moment of the collection differs.
"Run the handlers of the pending signals; the number handled, or -1 when an exception is pending (pl-setup.c `handleSignals`)."
function handleSignals(ld::PL_local_data)::Int
    done = 0
    is_signalled(ld) || return 0                    # if ( !is_signalled() ) return 0;
    ld.exception_term != 0 && return -1             # if ( exception_term ) return -1;
    while ld.gc.sig_pending != 0                    # while( LD->signal.pending[i] )
        sig = SIG_PROLOG_OFFSET                     # int sig = MINSIGNAL+SIGMASK_WIDTH*i;
        mask = UInt64(1)                            # sigmask_t mask = 1;
        while mask != 0                             # for( ; mask ; mask <<= 1, sig++ )
            if (ld.gc.sig_pending & mask) != 0
                ld.gc.sig_pending &= ~mask          # ATOMIC_AND(&LD->signal.pending[i], ~mask);
                done += 1
                _dispatch_gc_signal(ld, sig)        # dispatch_signal(sig, true);
                ld.exception_term != 0 && return -1 # if ( exception_term ) return -1;
            end
            mask <<= 1
            sig += 1
        end
    end
    done != 0 && updateAlerted(ld)                  # if ( done ) updateAlerted(LD);
    return done
end

# PORT: pl-setup.c PL_handle_signals
# (pl-setup.c:1193-1201 at the pin:
#     int
#     PL_handle_signals(void)
#     { GET_LD
#
#       if ( !is_signalled() )
#         return 0;
#       else
#         return handleSignals();
#     }
# )
# DIVERGES: as `handleSignals`'s (the collector's virtual signals). Its caller here is i_metacall_common's
# CHECK_INTERRUPT arm (src/pl-wam.jl) and assert_term's retry (src/pl-comp.jl); the long-loop callers
# (pl-list.c, pl-file.c, ...) keep their own DIVERGES lines.
"Run the pending signals' handlers when one is pending; 0, their number, or -1 for an exception (pl-setup.c `PL_handle_signals`)."
function PL_handle_signals(ld::PL_local_data)::Int
    if !is_signalled(ld)                            # if ( !is_signalled() )
        return 0
    else
        return handleSignals(ld)
    end
end

# PORT: pl-setup.c signames as SIGNAMES
# DIVERGES (HALT1, for the audit): the signal numbers are Linux's (x86_64): upstream reads them from the host's
# `<signal.h>`; the kernel is Linux-only here. The `#ifdef`s of signals Linux lacks are left out (`emt`, `info`);
# the flags column is `SIGNAMES_FLAGS` and the Prolog signals from 32 up (`prolog:gc`, …) are `SIGNAMES_VIRTUAL` (Q10).
# A comment, not a docstring, as for every module-level constant the global-state lint reads.
const SIGNAMES = (
    ("hup", 1), ("int", 2), ("quit", 3), ("ill", 4), ("abrt", 6), ("fpe", 8), ("kill", 9),
    ("segv", 11), ("pipe", 13), ("alrm", 14), ("term", 15), ("usr1", 10), ("usr2", 12),
    ("chld", 17), ("cont", 18), ("stop", 19), ("tstp", 20), ("ttin", 21), ("ttou", 22),
    ("trap", 5), ("bus", 7), ("stkflt", 16), ("urg", 23), ("io", 29), ("poll", 29),
    ("xcpu", 24), ("xfsz", 25), ("vtalrm", 26), ("prof", 27), ("pwr", 30), ("sys", 31),
    ("winch", 28)
)

# `SIG_PROLOG_OFFSET`, `SIG_GC` and `SIG_TUNE_GC` (pl-incl.h) are defined in src/pl-incl.jl (G1-C: the run loop and the collector, included
# before this file, name them); the other virtual signal numbers are defined here.
# PORT: pl-incl.h MINSIGNAL
"The number of the first signal, with OS signals (pl-incl.h `HAVE_OS_SIGNALS`)."
const MINSIGNAL = 1
# PORT: pl-incl.h MAXSIGNAL
"The highest supported signal number (pl-incl.h)."
const MAXSIGNAL = 64
# PORT: pl-incl.h NUM_SIGNALS
"The number of signals (pl-incl.h)."
const NUM_SIGNALS = MAXSIGNAL - MINSIGNAL + 1
# PORT: pl-incl.h virtual_signum as SIG_ATOM_GC
# DIVERGES: the `SIG_*` numbers (`SIG_PROLOG_OFFSET + VSIG_*`) as `Int` constants; `O_ATOMGC` and `O_ENGINES` are on.
"Prolog signal: atom garbage collection (pl-incl.h `SIG_ATOM_GC`)."
const SIG_ATOM_GC = SIG_PROLOG_OFFSET + 0
"Prolog signal: run the thread's signal queue (pl-incl.h `SIG_THREAD_SIGNAL`)."
const SIG_THREAD_SIGNAL = SIG_PROLOG_OFFSET + 2
"Prolog signal: clause garbage collection (pl-incl.h `SIG_CLAUSE_GC`)."
const SIG_CLAUSE_GC = SIG_PROLOG_OFFSET + 3
"Prolog signal that unwinds to the top level (pl-incl.h `SIG_PLABORT`)."
const SIG_PLABORT = SIG_PROLOG_OFFSET + 4
"Prolog signal: halt (pl-incl.h `SIG_PLHALT`)."
const SIG_PLHALT = SIG_PROLOG_OFFSET + 5

# PORT: pl-setup.c PLSIG_USERFLAGS
"The range of the API-visible signal flags (pl-setup.c)."
const PLSIG_USERFLAGS = Int(0x0000ffff)
# PORT: pl-setup.c PLSIG_STATEFLAGS
"The range of the internal signal flags (pl-setup.c)."
const PLSIG_STATEFLAGS = Int(0xffff0000)
# PORT: pl-setup.c PLSIG_PREPARED
"Signal flag: the signal is prepared (pl-setup.c)."
const PLSIG_PREPARED = Int(0x00010000)
# PORT: pl-setup.c PLSIG_IGNORED
"Signal flag: the signal is ignored (pl-setup.c)."
const PLSIG_IGNORED = Int(0x00020000)
# PORT: SWI-Prolog.h PLSIG_THROW
"Signal flag: throw `signal(num, name)` (SWI-Prolog.h)."
const PLSIG_THROW = Int(0x0002)
# PORT: SWI-Prolog.h PLSIG_SYNC
"Signal flag: call the handler synchronously (SWI-Prolog.h)."
const PLSIG_SYNC = Int(0x0004)
# PORT: SWI-Prolog.h PLSIG_NOFRAME
"Signal flag: do not create a Prolog frame (SWI-Prolog.h)."
const PLSIG_NOFRAME = Int(0x0008)
# PORT: SWI-Prolog.h PLSIG_IGNORE
"Signal flag: ignore the signal entirely (SWI-Prolog.h)."
const PLSIG_IGNORE = Int(0x0010)

# ORIGINAL: the handler tokens `sig_handler.handler` holds (see `sig_handler`, src/pl-global.jl): upstream's C functions, named
# in the order the start-up installs them. `$on_signal/4` reports a token as `'$foreign_function'(Token)`.
"No handler function (a NULL `handler_t`)."
const SIGH_NONE = 0
"The handler function `PL_interrupt` (the `debug` handler, pl-trace.c)."
const SIGH_INTERRUPT = 1
"The handler function `terminate_handler` (pl-setup.c: `SIGTERM`, `SIGABRT`, `SIGQUIT`)."
const SIGH_TERMINATE = 2
"The handler function `hupHandler` (pl-setup.c: `SIGHUP`)."
const SIGH_HUP = 3
"The handler function `sigCrashHandler` (os/pl-cstack.c: `SIGILL`, `SIGBUS`, `SIGFPE`, `SIGSYS`)."
const SIGH_CRASH = 4
"The handler function `alert_handler` (pl-setup.c: the alert signal)."
const SIGH_ALERT = 5
"The handler function `agc_handler` (pl-setup.c: `SIG_ATOM_GC`)."
const SIGH_AGC = 6
"The handler function `gc_handler` (pl-setup.c: `SIG_GC`)."
const SIGH_GC = 7
"The handler function `gc_tune_handler` (pl-setup.c: `SIG_TUNE_GC`)."
const SIGH_TUNE_GC = 8
"The handler function `cgc_handler` (pl-setup.c: `SIG_CLAUSE_GC`)."
const SIGH_CGC = 9
"The handler function `abort_handler` (pl-setup.c: `SIG_PLABORT`)."
const SIGH_ABORT = 10
"The handler function `halt_handler` (pl-setup.c: `SIG_PLHALT`)."
const SIGH_HALT = 11
"The handler function `executeThreadSignals` (pl-thread.c: `SIG_THREAD_SIGNAL`)."
const SIGH_THREAD_SIGNAL = 12
"The highest handler token."
const SIGH_MAX = 12

# PORT: pl-setup.c signames as SIGNAMES_VIRTUAL
# DIVERGES: the entries of the `signames` table that follow the OS signals (`prolog:atom_gc` …), here a table of their own; the
# kernel's numbers are `SIG_PROLOG_OFFSET + VSIG_*`. `SIG_TUNE_GC` has no entry upstream either.
const SIGNAMES_VIRTUAL = (
    ("prolog:atom_gc", SIG_ATOM_GC), ("prolog:gc", SIG_GC),
    ("prolog:thread_signal", SIG_THREAD_SIGNAL),
    ("prolog:clause_gc", SIG_CLAUSE_GC), ("prolog:abort", SIG_PLABORT),
    ("prolog:halt", SIG_PLHALT)
)

# PORT: pl-setup.c signames as SIGNAMES_FLAGS
# DIVERGES: the OS signals that start with a flag, `(number, flags)`: `fpe`, `alrm`, `xcpu`, `xfsz`, `vtalrm` throw, `pipe` is
# ignored (the other columns are 0).
const SIGNAMES_FLAGS = (
    (8, PLSIG_THROW), (13, PLSIG_IGNORE), (14, PLSIG_THROW), (24, PLSIG_THROW),
    (25, PLSIG_THROW), (26, PLSIG_THROW)
)

# PORT: pl-setup.c signal_index
# DIVERGES: `name` is a Julia string; the bound `strlen(name) < 12` is on its UTF-8 bytes, as upstream's.
"The number of the signal `name` names — `term`, or `SIGTERM` (an uppercase `SIG` prefix, then any case) — or -1 (pl-setup.c)."
function signal_index(name::AbstractString)::Int
    if startswith(name, "SIG") && ncodeunits(name) < 12
        name = lowercase(SubString(name, 4))            # strcpy(tmp, name+3); strlwr(tmp)
    end

    for (n, sig) in SIGNAMES
        n == name && return sig
    end
    for (n, sig) in SIGNAMES_VIRTUAL                    # the Prolog signals, listed after the OS signals
        n == name && return sig
    end

    return -1
end

# PORT: pl-setup.c signal_name
"The name of signal `sig`, or `\"unknown\"` (pl-setup.c)."
function signal_name(sig::Int)::String
    for (n, s) in SIGNAMES
        s == sig && return n
    end
    for (n, s) in SIGNAMES_VIRTUAL
        s == sig && return n
    end

    return "unknown"
end

# PORT: pl-setup.c PL_get_signum_ex
# DIVERGES: returns the number, or `nothing` with the error raised (see `PL_get_integer_ex`). `PL_get_chars(sig, &s,
# CVT_ATOM)` is a text atom: not `[]` (a reserved symbol), not a blob.
"""
The signal number term reference `sig` holds — an integer, or a signal name (`term`, `SIGTERM`) — in 1..31, or `nothing`
after raising `type_error(signal, Sig)` (neither) or `domain_error(signal, Sig)` (out of range, or no such name) (pl-setup.c).
"""
function PL_get_signum_ex(ld::PL_local_data{T}, sig::term_t)::Union{Nothing, Int} where {T}
    i = PL_get_integer(ld, sig)
    if i === nothing
        a = PL_get_atom(ld, sig)
        if a !== nothing && !is_reserved_symbol(a) && !is_blob(a)
            i = signal_index(sym_text(a))
        else
            PL_error(ld, ERR_TYPE, mk_sym(T, :signal), sig)
            return nothing
        end
    end

    if i > 0 && i < 32                                  # where to get these?
        return i
    end

    PL_error(ld, ERR_DOMAIN, mk_sym(T, :signal), sig)
    return nothing
end

# PORT: pl-incl.h SIGNAL_INDEX
# DIVERGES: one-based (a Julia vector): `sig - MINSIGNAL + 1`.
"The position of signal `sig` in the handler table (pl-incl.h)."
SIGNAL_INDEX(sig::Int)::Int = sig - MINSIGNAL + 1

# PORT: pl-incl.h IS_VALID_SIGNAL
"Whether `sig` is a signal number (pl-incl.h)."
IS_VALID_SIGNAL(sig::Int)::Bool = sig >= MINSIGNAL && sig <= MAXSIGNAL

# PORT: pl-incl.h IS_VSIG
"Whether `sig` is a Prolog (virtual) signal (pl-incl.h)."
IS_VSIG(sig::Int)::Bool = sig >= SIG_PROLOG_OFFSET

# PORT: pl-setup.c prepareSignal
# DIVERGES (the actual OS installation is unwritten by design): upstream's `set_sighandler(sig, …)` installs `pl_signal_handler`
# (or `SIG_IGN`) with `sigaction()` for an OS signal and remembers the previous OS handler in `saved_handler`. The kernel
# installs no OS handler and no signal is ever delivered to a Prolog handler: the record is the Prolog-visible state
# (what `$on_signal/4` reports and sets), `saved_handler` stays 0.
"Prepare signal `sig` with the `PLSIG_*` flags `plsig_flags`: record its state (pl-setup.c); the handler record."
function prepareSignal!(
    handlers::Vector{sig_handler{T}}, sig::Int, plsig_flags::Int
)::sig_handler{T} where {T}
    sh = handlers[SIGNAL_INDEX(sig)]
    current_state = sh.flags & PLSIG_STATEFLAGS
    desired_state = (plsig_flags & PLSIG_IGNORE) != 0 ? PLSIG_IGNORED : PLSIG_PREPARED

    plsig_flags &= ~(PLSIG_STATEFLAGS | PLSIG_IGNORE)

    if current_state != desired_state
        sh.flags = 0                                    # clearFlags(sh)
        sh.flags |= desired_state | plsig_flags         # set(sh, desired_state|plsig_flags)
    else
        sh.flags = (sh.flags & ~PLSIG_USERFLAGS) | plsig_flags
    end

    return sh
end

# PORT: pl-setup.c unprepareSignal
# DIVERGES: as `prepareSignal!`: no OS handler to restore.
"Return signal `sig` to its default state (pl-setup.c)."
function unprepareSignal!(handlers::Vector{sig_handler{T}}, sig::Int)::Nothing where {T}
    sh = handlers[SIGNAL_INDEX(sig)]

    if (sh.flags & PLSIG_STATEFLAGS) != 0
        sh.flags = 0
        sh.handler = SIGH_NONE
        sh.predicate = nothing
        sh.saved_handler = SIGH_NONE
    end

    return nothing
end

# PORT: pl-setup.c PL_signal as _signal_install!
# DIVERGES: `PL_signal(sig|flags, func)` is `PL_sigaction` with a handler function and no predicate: for a signal not yet prepared
# (or one whose handler is another) it records `func` and prepares the signal with the flags; the kernel has no API entry point
# for it, so this is the call `initSignals!` makes, on a handler token.
"Record handler token `func` for signal `sig` with the flags `flags` (pl-setup.c `PL_signal`'s effect on a fresh record)."
function _signal_install!(
    handlers::Vector{sig_handler{T}}, sig::Int, func::Int, flags::Int
)::Nothing where {T}
    sh = handlers[SIGNAL_INDEX(sig)]
    if (sh.flags & PLSIG_PREPARED) == 0 || func != sh.saved_handler
        sh.handler = func
        sh.predicate = nothing
        sh.flags = (sh.flags & ~PLSIG_USERFLAGS) | flags
        prepareSignal!(handlers, sig, flags)
    end

    return nothing
end

# PORT: pl-setup.c initSignals as initSignals!
# DIVERGES: builds the handler table of a new database (upstream fills `GD->signals.handlers`), for the default `signals` flag
# (true): `initTerminationSignals`, `initBackTrace` (os/pl-cstack.c), the signals with a flag in `signames`, `hupHandler`, the
# alert signal (`SIG_ALERT` is SIGUSR2 with threads; the kernel has one thread, `sig_alert` is kept as upstream's default), and
# the Prolog signals. `initAltSignalStack` (an alternate signal stack installed through `sigaction`, outside the table) has no twin. The handlers
# are tokens (`sig_handler`); no OS handler is installed (`prepareSignal!`).
"The handler records of a new database: `GD->signals.handlers` after `initSignals` (pl-setup.c)."
function initSignals!(::Type{T})::Vector{sig_handler{T}} where {T}
    handlers = [sig_handler{T}() for _ in 1:NUM_SIGNALS]

    _signal_install!(handlers, 15, SIGH_TERMINATE, 0)       # initTerminationSignals: SIGTERM
    _signal_install!(handlers, 6, SIGH_TERMINATE, 0)        # SIGABRT
    _signal_install!(handlers, 3, SIGH_TERMINATE, 0)        # SIGQUIT
    for sig in (4, 7, 8, 31)                                # initBackTrace: SIGILL, SIGBUS, SIGFPE, SIGSYS (signal 11 is on the alternate stack)
        _signal_install!(handlers, sig, SIGH_CRASH, 0)
    end
    for (sig, flags) in SIGNAMES_FLAGS                      # for( ; sn->name; sn++) if ( sn->flags ) prepareSignal(sn->sig, sn->flags)
        prepareSignal!(handlers, sig, flags)
    end
    _signal_install!(handlers, 1, SIGH_HUP, PLSIG_SYNC)     # PL_signal(SIGHUP|PL_SIGSYNC, hupHandler)
    _signal_install!(handlers, 12, SIGH_ALERT, PLSIG_NOFRAME)   # PL_signal(sig_alert|PL_SIGNOFRAME, alert_handler)

    _signal_install!(handlers, SIG_GC, SIGH_GC, PLSIG_SYNC)
    _signal_install!(handlers, SIG_TUNE_GC, SIGH_TUNE_GC, PLSIG_SYNC)
    _signal_install!(handlers, SIG_CLAUSE_GC, SIGH_CGC, PLSIG_SYNC)
    _signal_install!(handlers, SIG_PLABORT, SIGH_ABORT, PLSIG_SYNC)
    _signal_install!(handlers, SIG_PLHALT, SIGH_HALT, PLSIG_SYNC)
    _signal_install!(handlers, SIG_THREAD_SIGNAL, SIGH_THREAD_SIGNAL, PLSIG_SYNC)
    _signal_install!(handlers, SIG_ATOM_GC, SIGH_AGC, PLSIG_SYNC)

    return handlers
end

# ORIGINAL: the start-up values of the four stacks' `small`, `factor` and `min_free` (pl-setup.c `init_stack` and `gcPolicy`):
# `min_free` is `256*sizeof(word)` bytes, the local stack's `LOCAL_MARGIN` (`allocStacks`); the global stack and the trail are the
# collected ones (`small = SMALLSTACK` = 32 K, `factor = 3`), the local and the argument stack have 0 and 0.
"The `stack_params_t` records of a new database, in the order local, global, trail, argument (pl-setup.c)."
function initStackParams()::Vector{stack_params_t}
    return [
        stack_params_t(0, 0, LOCAL_MARGIN, 0),
        stack_params_t(32 * 1024, 3, 256, 0),
        stack_params_t(32 * 1024, 3, 256, 0),
        stack_params_t(0, 0, 256, 0)
    ]
end

# PORT: pl-setup.c setupProlog
# (swipl-devel cbf4e189, src/pl-setup.c:101-186; the steps it runs are cited at each line below)
# DIVERGES: upstream fills the process's one `GD`; this makes a NEW database state and returns it (one per
# `PL_global_data{T}`). It is the unbooted half of `PL_initialise` (pl-init.c:1603): `boot_global_data` (src/pl-qlf.jl)
# runs the boot over it, and src/pl-global.jl's `PL_global_data{T}()` is a copy of that booted database (R2 LB4 b2-1).
"The database state before the boot: modules, supervisors, atoms, functors, flags, built-ins, operators (pl-setup.c)."
function setupProlog(::Type{T})::PL_global_data{T} where {T}
    cd = initSupervisors()
    modules = module_table{T}()                 # initModules: system, then user
    system = _lookupModule!(modules, cd, mk_sym(T, :system))
    user = _lookupModule!(modules, cd, mk_sym(T, :user))
    dc = mk_sym(T, Symbol("\$c_call_prolog"))
    dc_def = Definition{T}(
        sym_key(dc), 0, ClauseList{T}(), UInt64(0), dc, cd.virgin, ClauseRef{T}[], cd, 0,
        system.index, 1
    )
    dc_proc = Procedure{T}(dc_def, UInt32(0), UInt32(0))
    top_clause, top_cref = initVM(dc_proc)
    system.procedures[(sym_key(dc), 0)] = dc_proc
    atoms = do_init_atoms!(atoms_t())          # initAtoms (setup: before everything here)
    syms = atom_symbols{T}()                   # (the atoms' symbols: filled as words are made)
    registerBuiltinAtomSymbols!(atoms, syms)   # (the built-in atoms' symbols: upstream's a->name, pl-atom.c:1977)
    functors = initFunctors!(functors_t())     # initFunctors (after the atoms, as upstream's)
    initDBRef!(atoms)                          # initDBRef (setup:146): the clause blob type (D1)
    initTries!(atoms)                          # initTries (setup:149): the trie blob type (TAB1 TR1)
    initUndo!(atoms)                           # initUndo (setup:151): the undo blob type (TX1e)
    initWrap!(atoms)                           # initWrap (setup:152): the closure blob type (TAB1-min)
    initThreads!(atoms)                        # initThreads (setup): the thread blob type (TH1 engines)
    dexpr = first(lookupBlob(atoms, Vector{UInt8}(codeunits("\$expr")), 5, reserved_symbol))
    dot2 = lookupFunctorDef(functors, _atom_word!(atoms, syms, mk_sym(T, Symbol("[|]"))), 2)
    nilw = _atom_word!(atoms, syms, mk_nil(T))  # ATOM_nil's word, once (L1c-6)
    # (L1d step 4) the index's fixed keys ARE the database's words — built-ins registered in a fixed
    # order (`registerBuiltinAtoms`, `registerBuiltinFunctors`), as upstream's generated handles
    dot2 == FUNCTOR_dot2 || error("FUNCTOR_dot2 is not this database's '[|]'/2 word")
    nilw == ATOM_nil || error("ATOM_nil is not this database's [] word")
    gd = PL_global_data{T}(
        gen_t(0),
        Dict{Definition{T}, dirty_def_info{T}}(),
        false,
        registerControlFunctors(T),
        modules,
        user,
        system,
        _subclause_names(T),
        cd,
        dc_proc,
        dc_proc,                                # procedures_equals2: set by initBuildIns!
        dc_proc,                                # procedures_dcall1: set by initBuildIns!
        dc_proc,                                # procedures_catch3: set by initBuildIns!
        dc_proc,                                # procedures_dwakeup1: set by initBuildIns!
        dc_proc,                                # procedures_arg3: set by initBuildIns!
        top_clause,
        top_cref,
        mk_nil(T),
        mk_sym(T, Symbol("[|]")),
        T[],
        Dict{UInt64, SourceFile{T}}(),
        SourceFile{T}[],
        1,                                      # files.no_hole_before = 1
        IdDict{IOSTREAM, T}(),
        Dict{UInt64, IOSTREAM}(),
        Dict{Int, Vector{T}}(),
        Dict{Int, Int}(),
        Union{Nothing, IOSTREAM}[],
        atoms,
        syms,
        functors,
        dexpr,
        dot2,
        nilw,
        prolog_flag_table{T}(),                 # prolog_flag: none yet (initPrologFlags! defines them)
        Clause{T}[],                            # clause_refs: no clause has a reference yet
        IdDict{Clause{T}, Int}(),               # clause_serials
        false,                                  # bootsession: no boot compilation until LB3's `-b` path sets it
        Dict{word, RecordList{T}}(),            # record_lists: no key has a record yet
        RecordList{T}[],                        # record_lists_order
        RecordRef{T}[],                         # record_refs: no record has a reference yet
        0,                                      # halt_status: no halt in progress
        0,                                      # halt_thread
        CLN_NORMAL,                             # halt_cleaning
        0,                                      # halt_cancelled
        true,                                   # halt_exit: the process exit
        Int[],                                  # halt_exited
        event_hooks{T}(),                       # event.hook: no listener yet (R2 EV1)
        closure{T}[],                           # closure_refs: no closure has a reference yet (TAB1-min)
        trie{T}[],                              # tries: no trie has a handle yet (TAB1 TR1)
        "",                                     # paths.CWDdir: none until the first PL_cwd (R2 LB2b)
        dc_proc,                                # procedures_print_message2: set by initBuildIns!
        dc_proc,                                # procedures_reset3: set by initBuildIns!
        dc_proc,                                # procedures_dtbl_reset6: set by initBuildIns!
        dc_proc,                                # procedures_call_continuation1: set by initBuildIns!
        dc_proc,                                # procedures_dmeta_call1: set by initBuildIns!
        dc_proc,                                # procedures_findall_loop4: set by findReset
        dc_proc,                                # procedures_trie_gen_compiled2: set by initTries!(gd) (TR4)
        dc_proc,                                # procedures_trie_gen_compiled3: set by initTries!(gd) (TR4)
        GEN_INVALID,                            # reload_generation: no file is being reloaded (R2 LB6a)
        initDefaultOptions!(pl_options_t()),    # options: pl-init.c initDefaultOptions, before the command line is read (R2 LB7)
        pl_cmdline_t(),                         # cmdline: no arguments, packs on, no -O (R2 LB7)
        nothing,                                # defaults_home: set with the `home` flag by initPrologFlags!
        LDTable(),                              # ld_table: no wrapped stream yet (R2 TOP1b E)
        Dict{Int, delay_info}(),                # tabling_answer_delay_infos: initTabling's newHTablePP(64) (pl-tabling.c:12696; TAB1 TB0)
        0,                                      # tabling_start_node_ids: no start node id handed out (pl-tabling.c:12348; TAB1 TB1)
        record{T}[],                            # undo_refs: no undo goal has a blob yet (TX1e)
        dc_proc,                                # procedures_drun_undo1: set by run_undo_hooks at its first call (TX1e)
        Tuple{Int, Procedure{T}}[],             # format_predicates: no user directive (pl-fmt.c: format_predicates is NULL until format_predicate/2)
        initSignals!(T),                        # signals_handlers: setup:122 initSignals (Q10)
        initStackParams(),                      # stacks_params: init_stack's small/factor/min_free (Q10)
        locale_state{T}(),                      # locale: empty until initLocale! (below)
        dc_proc,                                # procedures_tune_gc3: set by initBuildIns! (pl-ext.c:385-386)
        initCharConversion(),                   # char_conversion_table: pl-setup.c:174 (RD2b)
        thread_state{T}(),                      # thread: no engine yet (TH1 engines)
        Dict{UInt64, pl_mutex{T}}(),            # mutexes: no user mutex (initMutexes: newHTableWP(16); MUTEX)
        0,                                      # mutex_serial: none handed out
        Dict{word, flag{T}}(),                  # flags_table: initFlags's newHTableWP, empty (pl-flag.c; FL1)
        8,                                      # clauses_cgc_space_factor: pl-setup.c:180
        0.03,                                   # clauses_cgc_stack_factor: pl-setup.c:181
        1.0,                                    # clauses_cgc_clause_factor: pl-setup.c:182
        Set{String}(),                          # os_tmp_files: no temporary file yet (pl-os.c TemporaryFile; W12-TMPFILES)
        0                                       # os_temp_counter: no temporary name made (pl-os.c `temp_counter`; W12-TMPFILES)
    )
    initPrologFlags!(gd)                        # setup:136 (src/os/pl-prologflag.jl): before the built-ins (:158), whose boot clauses read the mask
    initTries!(gd)                              # initTries (setup:149), its tail: trie_gen_compiled/2,3 (TR4, src/pl-trie.jl)
    initBuildIns!(gd)                           # setup:158 (src/pl-ext.jl)
    initOperators!(gd)                          # setup:164 (src/pl-op.jl)
    initLocale!(gd)                             # setup:176 (src/os/pl-locale.jl): after initIO, the locale blob type and the default locale
    register_main_thread!(gd)                   # pl-init.c:1606 aliasThread(PL_thread_self(), ATOM_thread, ATOM_main) (src/pl-thread.jl; TH1 engines)
    return gd
end

# PORT: pl-setup.c get_meta_arg
# DIVERGES: the call `get_meta_arg(arg, m, t)` the predicate makes with `t` the same reference as `arg` reads the argument first,
# then overwrites `t`, as `_PL_get_arg` does here (`valPtr(w)` is taken before the slot is written).
"Split the `Module:Term` term reference `arg` into `m` and `t`, or raise `type_error(meta_argument, Arg)` (pl-setup.c)."
function get_meta_arg(
    ld::PL_local_data{T}, arg::term_t, m::term_t, t::term_t
)::Bool where {T}
    if PL_is_functor(ld, arg, mk_sym(T, :(:)), 2)
        _PL_get_arg(ld, 1, arg, m)
        _PL_get_arg(ld, 2, arg, t)
        return true
    end

    return PL_error(ld, ERR_TYPE, mk_sym(T, :meta_argument), arg)
end

# PORT: pl-setup.c on_signal as pl_on_signal4_va
# (PRED_IMPL("$on_signal", 4, on_signal, 0), pl-setup.c:1366-1477 at the pin)
# DIVERGES (TH1): no OS handler is installed and no signal is delivered (`prepareSignal!`: the handler table records the Prolog-visible
# state). A handler FUNCTION is a token: `'$foreign_function'(Token)` reports one of the kernel's handler tokens (`SIGH_*`, src/pl-setup.jl)
# and re-installs it; a pointer upstream would get from C (another integer) is refused by name. `PL_compare` returns only -1/0/1
# here: upstream's `CMP_ERROR` (a comparison that raised) has no twin, so that test is left out.
"`'\$on_signal'(?SigNum, ?SigName, :Old, :New)`: report and set how a signal is handled (pl-setup.c)."
function pl_on_signal4_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2, A3, A4 = PL__t0, PL__t0 + 1, PL__t0 + 2, PL__t0 + 3
    gd = _query_gd(ld)
    handlers = gd.signals_handlers
    mold = new_term_ref(ld)
    mnew = new_term_ref(ld)

    sig = A1
    name = A2
    old = A3
    new = A4

    if !get_meta_arg(ld, old, mold, old) || !get_meta_arg(ld, new, mnew, new)
        return FFALSE
    end

    sign = PL_get_integer(ld, sig)
    if sign !== nothing && IS_VALID_SIGNAL(sign)
        PL_unify_atom(ld, name, mk_sym(T, Symbol(signal_name(sign)))) || return FFALSE
    else
        na = PL_get_atom(ld, name)
        if na !== nothing && !is_reserved_symbol(na) && !is_blob(na)    # PL_get_atom_chars(name, &sn)
            sign = signal_index(sym_text(na))
            if sign != -1
                PL_unify_integer(ld, sig, sign) || return FFALSE
            else
                return PL_error(ld, ERR_DOMAIN, mk_sym(T, :signal), name) ? FTRUE : FFALSE
            end
        else
            return PL_error(ld, ERR_TYPE, mk_sym(T, :signal), sig) ? FTRUE : FFALSE
        end
    end

    sh = handlers[SIGNAL_INDEX(sign)]

    if (sh.flags & PLSIG_STATEFLAGS) == 0               # not handled
        PL_unify_atom(ld, old, mk_sym(T, :default)) || return FFALSE
    elseif (sh.flags & PLSIG_IGNORED) != 0              # signal ignored
        PL_unify_atom(ld, old, mk_sym(T, :ignore)) || return FFALSE
    elseif (sh.flags & PLSIG_THROW) != 0                # throw exception
        PL_unify_atom(ld, old, mk_sym(T, :throw)) || return FFALSE
    elseif sh.predicate !== nothing                     # call predicate
        def = sh.predicate.definition
        modname = gd.modules[def.module_].atom

        if PL_unify_atom(ld, mold, modname)
            PL_unify_atom(ld, old, def.name) || return FFALSE
        else
            PL_unify(
                ld,
                old,
                _message_term(ld, :(:), _err_atom(ld, modname), _err_atom(ld, def.name))
            ) ||
                return FFALSE
        end
    elseif sh.handler != SIGH_NONE
        if sh.handler == SIGH_INTERRUPT                 # PL_interrupt
            PL_unify_atom(ld, old, mk_sym(T, :debug)) || return FFALSE
        else
            PL_unify(
                ld, old,
                _message_term(ld, Symbol("\$foreign_function"), _err_int(ld, sh.handler))
            ) || return FFALSE
        end
    end

    rc = PL_compare(ld, old, new)
    rc == 0 && (rc = PL_compare(ld, mold, mnew))
    rc == 0 && return FTRUE                             # no change

    a = PL_get_atom(ld, new)
    if a !== nothing
        key = sym_key(a)
        if key == sym_key(mk_sym(T, :default))
            unprepareSignal!(handlers, sign)
        elseif key == sym_key(mk_sym(T, :ignore))
            prepareSignal!(handlers, sign, PLSIG_IGNORE)        # request to ignore this signal
        elseif key == sym_key(mk_sym(T, :throw))
            sh = prepareSignal!(handlers, sign, PLSIG_THROW | PLSIG_SYNC)
            sh.handler = SIGH_NONE
            sh.predicate = nothing
        elseif key == sym_key(mk_sym(T, :debug))
            sh = prepareSignal!(handlers, sign, 0)
            sh.handler = SIGH_INTERRUPT
            sh.predicate = nothing
        else
            ma = PL_get_atom_ex(ld, mnew)                       # get_module(mnew, &m)
            ma === nothing && return FFALSE
            m = lookupModule(gd, ma)
            pred = lookupProcedure(a, 1, m)

            sh = prepareSignal!(handlers, sign, PLSIG_SYNC)
            sh.handler = SIGH_NONE
            sh.predicate = pred
        end
    elseif PL_is_functor(ld, new, mk_sym(T, Symbol("\$foreign_function")), 1)
        p = new_term_ref(ld)
        _PL_get_arg(ld, 1, new, p)

        if PL_is_integer(ld, p)                                 # PL_get_pointer(a, &f)
            tok = PL_get_integer(ld, p)
            if tok !== nothing && tok >= SIGH_NONE && tok <= SIGH_MAX
                sh = prepareSignal!(handlers, sign, 0)
                sh.handler = tok
                sh.predicate = nothing
                return FTRUE
            end
            throw(
                NotPortedError{T}(
                    mk_sym(T, Symbol("\$foreign_function")),
                    "a foreign handler function of the signal",
                    "TH1"
                )
            )
        end

        return PL_error(ld, ERR_DOMAIN, mk_sym(T, :signal_handler), new) ? FTRUE : FFALSE
    else
        return PL_error(ld, ERR_TYPE, mk_sym(T, :signal_handler), new) ? FTRUE : FFALSE
    end

    return FTRUE
end

# PORT: pl-setup.c trim_stacks as pl_trim_stacks0_va
# (PRED_IMPL("trim_stacks", 0, trim_stacks, 0), pl-setup.c:1751-1757 at the pin)
"`trim_stacks`: release the free parts of the stacks (pl-setup.c)."
function pl_trim_stacks0_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    trimStacks!(ld, true)                               # trimStacks(true)
    return FTRUE
end

# PORT: pl-setup.c set_stack_limit as set_stack_limit!
# DIVERGES: the limit is `ld.stacks_limit`, in positions (words); `limit` is in bytes, as the `stack_limit` flag and
# `'$set_prolog_stack'/4` give it, and is rounded DOWN to whole words (swipl keeps the exact byte count: 2000001 is reported back
# as 2000001, here as 2000000). `sizeStack(local) + sizeStack(global) + sizeStack(trail)` is `_stacks_in_use(ld, 0)`, the sum
# every overflow check compares with the limit (the three stacks with their spares, src/pl-alloc.jl). `garbageCollect(GC_USER)` is
# the collector's with the VM-state callback `get_vmi_state` (src/pl-gcdriver.jl), as `pl_garbage_collect` passes it (G1-6; the collection declines
# while the collector is blocked or off, and `trimStacks(true)` follows either way).
"Set the combined limit of the stacks to `limit` bytes; a limit below what the stacks hold after trimming them is `permission_error(limit, stacks, Limit)` (pl-setup.c)."
function set_stack_limit!(ld::PL_local_data{T}, limit::Int)::Bool where {T}
    if limit < 8 * ld.stacks_limit && limit < 8 * _stacks_in_use(ld, 0)
        garbageCollect(ld, Int(GC_USER); vmi_state_of=get_vmi_state)   # garbageCollect(GC_USER)
        trimStacks!(ld, true)                           # trimStacks(true)

        if limit < 8 * _stacks_in_use(ld, 0)
            ex = PL_new_term_ref(ld)
            return PL_put_int64(ld, ex, limit) &&
                   PL_error(
                ld, "", 0, "", ERR_PERMISSION, mk_sym(T, :limit), mk_sym(T, :stacks), ex
            )
        end
    end

    ld.stacks_limit = limit ÷ 8                         # LD->stacks.limit = limit
    return true
end

# PORT: pl-setup.c set_prolog_stack as pl_set_prolog_stack4_va
# (PRED_IMPL("$set_prolog_stack", 4, set_prolog_stack, 0), pl-setup.c:1892-1960 at the pin)
# DIVERGES (TH1): the four stacks' `small`, `factor` and `min_free` are the records of `GD.stacks_params` (local, global, trail, argument;
# src/pl-global.jl), in words as the predicate reports them; the local, global and trail stack's `spare` is the local data's
# `*_def_spare`, the argument stack's its record's (the kernel has no argument stack to trim, so setting its `spare` or `min_free` only
# records). `limit` (deprecated) reports and sets the one limit of the three stacks, in bytes (`set_stack_limit!`).
"`'\$set_prolog_stack'(+Stack, +Property, -Old, +New)`: read and set a stack parameter (pl-setup.c)."
function pl_set_prolog_stack4_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2, A3, A4 = PL__t0, PL__t0 + 1, PL__t0 + 2, PL__t0 + 3
    gd = _query_gd(ld)

    name = A1
    prop = A2
    old = A3
    value = A4

    which = 0                                           # 1 local, 2 global, 3 trail, 4 argument
    a = PL_get_atom(ld, name)
    if a !== nothing
        key = sym_key(a)
        if key == sym_key(mk_sym(T, :local))
            which = 1
        elseif key == sym_key(mk_sym(T, :global))
            which = 2
        elseif key == sym_key(mk_sym(T, :trail))
            which = 3
        elseif key == sym_key(mk_sym(T, :argument))
            which = 4
        end
    end
    if which == 0
        return PL_error(ld, ERR_EXISTENCE, mk_sym(T, :stack), name) ? FTRUE : FFALSE
    end
    stack = gd.stacks_params[which]

    k = PL_get_atom_ex(ld, prop)
    k === nothing && return FFALSE
    key = sym_key(k)

    if key == sym_key(mk_sym(T, :low))
        PL_unify_int64(ld, old, stack.small) || return FFALSE
        v = PL_get_size_ex(ld, value)
        v === nothing && return FFALSE
        stack.small = v
        return FTRUE
    end
    if key == sym_key(mk_sym(T, :factor))
        PL_unify_integer(ld, old, stack.factor) || return FFALSE
        v = PL_get_integer_ex(ld, value)
        v === nothing && return FFALSE
        stack.factor = v
        return FTRUE
    end
    if key == sym_key(mk_sym(T, :limit))
        printMessage(
            ld, :warning,
            _message_term(
                ld, :deprecated,
                _message_term(ld, :set_prolog_stack, A1, _err_atom(ld, mk_sym(T, :limit)))
            )
        ) || return FFALSE

        limit = ld.stacks_limit * 8                     # in bytes, as the stack_limit flag reports it
        PL_unify_int64(ld, old, limit) || return FFALSE
        newlimit = PL_get_size_ex(ld, value)
        newlimit === nothing && return FFALSE
        return set_stack_limit!(ld, newlimit) ? FTRUE : FFALSE
    end
    if key == sym_key(mk_sym(T, :spare))
        spare = if which == 1
            ld.local_def_spare
        elseif which == 2
            ld.global_def_spare
        elseif which == 3
            ld.trail_def_spare
        else
            stack.def_spare
        end
        PL_unify_int64(ld, old, spare) || return FFALSE
        v = PL_get_size_ex(ld, value)
        v === nothing && return FFALSE
        if which == 1
            ld.local_def_spare = v
            trim_stack!(ld)
        elseif which == 2
            ld.global_def_spare = v
            trim_stack_global!(ld)
        elseif which == 3
            ld.trail_def_spare = v
            trim_stack_trail!(ld)
        else
            stack.def_spare = v
        end
        return FTRUE
    end
    if key == sym_key(mk_sym(T, :min_free))
        PL_unify_int64(ld, old, stack.min_free) || return FFALSE
        v = PL_get_size_ex(ld, value)
        v === nothing && return FFALSE
        stack.min_free = v
        which == 1 && trim_stack!(ld)
        which == 2 && trim_stack_global!(ld)
        which == 3 && trim_stack_trail!(ld)
        return FTRUE
    end

    return PL_error(ld, ERR_DOMAIN, mk_sym(T, :stack_parameter), prop) ? FTRUE : FFALSE
end

# ORIGINAL: pl-setup.c `GD->signals.sig_alert`, as _sig_alert
# DIVERGES: the database has no field for it: the alert signal is the one whose handler record holds `SIGH_ALERT` (what
# `initSignals!` and `prolog_alert_signal/2` install), 0 when none does (`unprepareSignal!` clears the record). A signal given
# `'$foreign_function'(Token)` with the alert handler's token by `$on_signal/4` would be read as the alert signal too.
"The alert signal of the database: the signal whose record carries `SIGH_ALERT`, or 0 (pl-setup.c `GD->signals.sig_alert`)."
function _sig_alert(handlers::Vector{sig_handler{T}})::Int where {T}
    for sig in MINSIGNAL:MAXSIGNAL
        sh = handlers[SIGNAL_INDEX(sig)]
        if (sh.flags & PLSIG_PREPARED) != 0 && sh.handler == SIGH_ALERT
            return sig
        end
    end

    return 0
end

# PORT: pl-setup.c prolog_alert_signal as pl_prolog_alert_signal2_va
# (PRED_IMPL("prolog_alert_signal", 2, prolog_alert_signal, 0), pl-setup.c:1274-1310 at the pin, under `SIG_ALERT`)
# DIVERGES: the old signal is read with `_sig_alert` (above); `PL_signal(sig|PL_SIGNOFRAME, alert_handler)` is `_signal_install!`
# on the alert token (no OS handler: `prepareSignal!`). `PL_compare` answers only -1/0/1 here: upstream's `CMP_ERROR` arm has
# no twin; the arm for a build without `SIG_ALERT` (the predicate is then undefined) is left out.
"`prolog_alert_signal(-Old, +New)`: unify `Old` with the signal that wakes a thread (name, or number when unnamed) and set it to `New` (pl-setup.c)."
function pl_prolog_alert_signal2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    handlers = _query_gd(ld).signals_handlers
    sig_alert = _sig_alert(handlers)
    sname = signal_name(sig_alert)

    if sname == "unknown"
        PL_unify_integer(ld, A1, sig_alert) || return FFALSE
    else
        PL_unify_atom(ld, A1, mk_sym(T, Symbol(sname))) || return FFALSE
    end

    PL_compare(ld, A1, A2) == 0 && return FTRUE

    new = PL_get_integer(ld, A2)
    if !(new !== nothing && new == 0)                   # PL_get_integer(A2, &new) && new == 0
        new = PL_get_signum_ex(ld, A2)                  # || PL_get_signum_ex(A2, &new)
        new === nothing && return FFALSE
    end

    if sig_alert != 0
        unprepareSignal!(handlers, sig_alert)           # GD->signals.sig_alert = 0
    end

    if new != 0
        _signal_install!(handlers, new, SIGH_ALERT, PLSIG_NOFRAME)
    end

    return FTRUE
end

# PORT: pl-setup.c BeginPredDefs as PL_predicates_from_setup
# DIVERGES: none: upstream's four entries, `prolog_alert_signal/2` last (under `SIG_ALERT`, as the table's tail).
"pl-setup.c's registration table (`BeginPredDefs(setup)`): `\$set_prolog_stack/4`, `trim_stacks/0`, `\$on_signal/4`, `prolog_alert_signal/2`."
const PL_predicates_from_setup = (
    PL_extension("\$set_prolog_stack", 4, pl_set_prolog_stack4_va, PL_FA_VARARGS),
    PL_extension("trim_stacks", 0, pl_trim_stacks0_va, PL_FA_VARARGS),
    PL_extension("\$on_signal", 4, pl_on_signal4_va, PL_FA_VARARGS),
    PL_extension("prolog_alert_signal", 2, pl_prolog_alert_signal2_va, PL_FA_VARARGS)
)
