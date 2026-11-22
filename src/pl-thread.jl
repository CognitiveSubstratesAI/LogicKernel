# UPSTREAM: swipl-devel src/pl-thread.c @ 18168e629eab
# CLASS: code
# COPYRIGHT: Copyright (c)  1999-2026, University of Amsterdam,
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
# PIN1 ledger (V10.1.20): re-cite only, no code change (cbf4e189..18168e62 compared, D-0447 Q1) — pl-thread.c: no hunk of the diff touches the ported functions (hunks: freePrologThread, system_thread_id, detach_engine, `$thread_local_predicate_size`, the predicate table), the rest is the TH1 row (cfile:pl-thread.c).
# PREDICATE REFERENCES — the slice of SWI-Prolog's pl-thread.c that records which predicates an
# ongoing enumeration (retract/1, clause/2, a call) references and at which generation, so that
# clause garbage collection keeps every clause those enumerations can still see. The rest of
# pl-thread.c is threads, which the kernel does not have; since Y1 `ThreadCPUTime`, the CPU time of the
# calling thread, which statistics/2 reads; since TH1 engines (O_ENGINES, THREADS off) the thread blob, the handle, `get_interactor`
# and the engine predicates (an engine is a second local data over the same database).

# PORT: pl-thread.c cgcActivatePredicate
"Record that `def` is accessed in generation `gen`, if it is dirty (pl-thread.c)."
function cgcActivatePredicate!(
    gd::PL_global_data{T}, def::Definition{T}, gen::gen_t
)::Nothing where {T}
    ddi = get(gd.procedures_dirty, def, nothing)
    if ddi !== nothing
        ddi_add_access_gen!(ddi, gen)
    end
    return nothing
end

# PORT: pl-thread.c pushPredicateAccessObj
# DIVERGES: the reference stack is a Vector (upstream: blocks of doubling size). Upstream's
# `enterDefinition()` is a no-op macro (pl-incl.h), so there is nothing to port. NOT PORTED: the
# depth limit — upstream raises `representation_error(predicate references)` past 2^20 − 1000
# references (MAX_BLOCKS) and returns NULL, which its callers handle; here the stack grows without
# limit (the divergence audit, docs/divergence_audit.md).
"""
    pushPredicateAccessObj!(ld, gd, def) -> definition_ref

Push a reference to `def` at its current generation; the enumeration runs in that generation
(pl-thread.c).
"""
function pushPredicateAccessObj!(
    ld::PL_local_data{T}, gd::PL_global_data{T}, def::Definition{T}
)::definition_ref{T} where {T}
    gen = current_generation(gd, ld, def)
    while gen != current_generation(gd, ld, def)        # do … while(): no other thread can move it
        gen = current_generation(gd, ld, def)
    end
    dref = definition_ref{T}(def, gen)
    push!(ld.predicate_references, dref)
    return dref
end

# PORT: pl-thread.c popPredicateAccess
# DIVERGES: removes the vector entry (upstream clears the top entry, or shifts the entries above an
# out-of-order one down, and decrements `top` — the same stack afterwards).
"Pop the reference to `def` — normally the top one; out of order is possible (pl-thread.c)."
function popPredicateAccess!(ld::PL_local_data{T}, def::Definition{T})::Nothing where {T}
    refs = ld.predicate_references
    top = length(refs)
    if refs[top].predicate === def
        pop!(refs)
        return nothing
    end
    while top > 0                                   # Out of order!
        if refs[top].predicate === def
            deleteat!(refs, top)
            return nothing
        end
        top -= 1
    end
    @assert false "popPredicateAccess!: predicate not referenced"
    return nothing
end

# PORT: pl-thread.c popNPredicateAccess
# (swipl-devel cbf4e189, src/pl-thread.c:8682-8704)
# DIVERGES: the reference stack is a Vector, so the entries go with `pop!` (upstream clears the top entry and decrements `top`);
# `leaveDefinition()` is a no-op macro (see `pushPredicateAccessObj!`).
"Pop the `n` top predicate references; the number left, upstream's `refs->top` (pl-thread.c)."
function popNPredicateAccess!(ld::PL_local_data, n::Integer)::Int
    refs = ld.predicate_references
    while n > 0
        @assert !isempty(refs) "popNPredicateAccess!: no reference left"
        pop!(refs)
        n -= 1
    end
    return length(refs)
end

# PORT: pl-thread.c markAccessedPredicates
"Record every referenced predicate's generation with clause GC (pl-thread.c)."
function markAccessedPredicates!(
    ld::PL_local_data{T}, gd::PL_global_data{T}
)::Nothing where {T}
    for dref in ld.predicate_references
        cgcActivatePredicate!(gd, dref.predicate, dref.generation)
    end
    return nothing
end

# PORT: pl-thread.c ThreadCPUTime
# DIVERGES: the pthread's clock is `CLOCK_THREAD_CPUTIME_ID`, the calling thread's: the kernel runs on
# the thread that calls it (`pthread_getcpuclockid(info->tid)` upstream); the system time of a
# thread is 0.0, as upstream's.
"""
    ThreadCPUTime(which) -> Float64

The CPU seconds the calling thread has used (pl-thread.c): the user time; the system time is 0.0.
"""
function ThreadCPUTime(which::Int)::Float64
    which == CPU_SYSTEM && return 0.0
    t = _clock_gettime(CLOCK_THREAD_CPUTIME_ID)
    return t === nothing ? 0.0 : t
end

# ---- ENGINES: THE THREAD BLOB, THE HANDLE AND `get_interactor` (TH1 engines, pl-thread.c at 18168e62) ----
# An engine is a second local data over the same database (`_create_engine`, below): the kernel has ONE OS thread, so the engine is entered
# on the caller's Julia task and a query is tied to the explicit `ld` argument (upstream: `PL_set_engine`/`TLD_set_LD`, the interactor
# mutex and the engine's own pthread identity have no counterpart). DIVERGES (TH1): the per-thread state the kernel keeps in the database
# (`reload_generation`, `locale.current`, `stacks_params`, `signals_handlers`, `halt_thread`, `paths_CWDdir`, `ld_table`) is ONE process copy
# that the engine shares: an engine runs interleaved, never concurrently, so nothing observes the difference until a thread has a
# local data of its own (the existing owner-TH1 notes on those fields).

# PORT: pl-thread.c thread_blob
# DIVERGES: no `release`, `write`, `save` or `load` slots (`PL_blob_t` has none): there is no atom GC, so a handle lives as long as
# `gd.thread.handles` (`engine_destroy/1` frees the engine, never the handle) and a handle is written `<thread>(0x...)`, the term layer's
# blob form, for an engine too (upstream: `<engine>(N,0x...)` / `<thread>(N,0x...)`): no row prints one. The payload is the handle's
# number in `gd.thread.handles` (upstream: the pointer).
"The blob type of a thread or engine handle (pl-thread.c `thread_blob`): unique by payload, non-text, named `thread`."
const thread_blob = PL_blob_t(PL_BLOB_UNIQUE, "thread")

# PORT: pl-thread.c initThreads
# DIVERGES: only the blob type is registered here (the thread table of `GD->thread` is `thread_state`, made with the database).
"Register the thread blob type in `atoms` (pl-thread.c)."
function initThreads!(atoms::atoms_t)::Nothing
    PL_register_blob_type(atoms, thread_blob)
    return nothing
end

# ORIGINAL: the number of a handle as the 8 bytes of its blob (`thread_handle **` upstream, a pointer).
"The 8 bytes of a thread blob: the handle's number in `gd.thread.handles`, little-endian."
_thread_bytes(serial::Int)::Vector{UInt8} = collect(reinterpret(UInt8, Int64[serial]))

# PORT: pl-thread.c symbol_thread_handle
# DIVERGES: the atom is a term `a` (`nothing` = 0) and the database is an argument; the handle is the one `a`'s blob payload numbers.
"The handle the atom `a` names when it is a thread blob, else `nothing` (pl-thread.c)."
function symbol_thread_handle(
    gd::PL_global_data{T}, a::Union{Nothing, T}
)::Union{Nothing, thread_handle{T}} where {T}
    (a === nothing || !is_blob(a)) && return nothing
    at = atomValue(gd.atoms, blob_handle(a))
    at.type === thread_blob || return nothing
    return gd.thread.handles[Int(reinterpret(Int64, at.name[1:8])[1])]
end

# PORT: pl-thread.c create_thread_handle
# DIVERGES: the handle is a Julia object numbered in `gd.thread.handles`; no mutex is allocated for an engine (no OS thread), and
# `info->symbol` is the blob atom.
"The handle of the thread record `info`, made with its blob on first use (pl-thread.c)."
function create_thread_handle(
    gd::PL_global_data{T}, info::PL_thread_info{T}
)::thread_handle{T} where {T}
    symbol = info.symbol
    if symbol !== nothing
        return symbol_thread_handle(gd, symbol)::thread_handle{T}
    end
    th = thread_handle{T}(
        info, nothing, nothing, info.pl_tid, UInt32(0), length(gd.thread.handles) + 1,
        0, 0, nothing, nothing, false
    )
    push!(gd.thread.handles, th)
    th.symbol = _thread_handle_blob!(gd, th)
    info.symbol = th.symbol
    return th
end

# ORIGINAL: the blob a handle's symbol is, shared by `create_thread_handle` and `register_main_thread!` (upstream makes it inline).
"The thread blob of the handle `th` (its number is the payload), made on first use."
function _thread_handle_blob!(gd::PL_global_data{T}, th::thread_handle{T})::T where {T}
    bytes = _thread_bytes(th.serial)
    w, _ = lookupBlob(gd.atoms, bytes, length(bytes), thread_blob)    # lookupBlob((char*)&ref, sizeof(ref), &thread_blob, &new)
    return _blob_term!(gd.atoms, gd.atom_symbols, T, w)
end

# PORT: pl-init.c PL_initialise (aliasThread(PL_thread_self(), ATOM_thread, ATOM_main), pl-init.c:1606 at the pin)
# DIVERGES: the main thread has no record here (`info === nothing`, engine id 1, `ld.thread_info === nothing`), so its handle is made with no
# `info` and `alias` `main` and is entered in `thread_table` directly (`aliasThread!` takes a thread record). It is the FIRST handle of the
# database (`handles[1]`): called when a database is made (`setupProlog`) and when one is copied from the template (`copy_global_data`: the
# copy starts with a fresh `thread_state`). A handle that is no engine (no `TH_IS_INTERACTOR`, no record) is no interactor: `get_interactor`
# raises `type_error(engine, main)` for it, as upstream does. Idempotent.
"Register the main thread: its handle (id 1, alias `main`) is the first of `gd.thread.handles` and `main` is in the thread table."
function register_main_thread!(gd::PL_global_data{T})::Nothing where {T}
    isempty(gd.thread.handles) || return nothing
    th = thread_handle{T}(
        nothing, nothing, nothing, 1, UInt32(0), 1, 0, 0, nothing, nothing, false
    )
    push!(gd.thread.handles, th)
    th.symbol = _thread_handle_blob!(gd, th)
    th.alias = mk_sym(T, :main)
    gd.thread.thread_table[sym_key(th.alias::T)] = th.serial
    return nothing
end

# ORIGINAL: the alias of the main thread, read where upstream reads `GD->thread.threads[1]` (`unify_thread_id`): the main thread has no
# record here, so it is the alias of its handle (`handles[1]`), `main` from `register_main_thread!` on and `main` when no handle is registered.
# `set_thread(E, alias(A))` aliases the CALLER (pl-thread.c `pl_set_thread`) and so renames the main thread when it is the caller
# (swipl: `thread_self(X)` gives `A`, `thread_property(main, alias(A))`); `main` stays in `thread_table` (a NAME lookup is unchanged).
"The alias of the main thread: its handle's alias, `main` when the handles are not registered yet."
function main_thread_alias(gd::PL_global_data{T})::T where {T}
    isempty(gd.thread.handles) && return mk_sym(T, :main)
    a = gd.thread.handles[1].alias
    return a === nothing ? mk_sym(T, :main) : a
end

# PORT: pl-thread.c unify_thread_id
# DIVERGES: the database is an argument; `nothing` for the info is the main thread, which has no record here and answers its alias
# (`main_thread_alias`: `main` unless `set_thread/2` renamed it).
# The `PL_unify_integer(id, info->pl_tid)` branch ("during destruction") cannot be reached: `create_thread_handle` does not fail.
"Unify `id` with the identifier of the thread `info`: its alias, else its blob (pl-thread.c)."
function unify_thread_id(
    gd::PL_global_data{T}, ld::PL_local_data{T}, id::term_t,
    info::Union{Nothing, PL_thread_info{T}}
)::Bool where {T}
    info === nothing && return PL_unify_atom(ld, id, main_thread_alias(gd))
    th = create_thread_handle(gd, info)
    name = th.alias !== nothing ? th.alias : th.symbol
    return PL_unify_atom(ld, id, name::T)
end

# PORT: pl-thread.c aliasThread
# DIVERGES: the thread is its record `info` (upstream: the id `tid`, looked up in `GD->threads`; `nothing`: the main thread, which has no
# record, its handle is `gd.thread.handles[1]`) and the database is an argument; the
# message queues have no table (`queueTable` is NULL: no queue exists), so only a thread name can be taken. `PL_register_atom` does not
# exist (no atom GC). A taken name raises `permission_error(create, Type, Name)` with the message "Alias name already taken".
"Give the thread `info` the alias `name`; false (the error raised) when the name is taken (pl-thread.c)."
function aliasThread!(
    gd::PL_global_data{T}, ld::PL_local_data{T}, info::Union{Nothing, PL_thread_info{T}},
    type::T, name::T
)::Bool where {T}
    if haskey(gd.thread.thread_table, sym_key(name))
        obj = PL_new_term_ref(ld)
        PL_put_atom(ld, obj, name)
        return PL_error(
            ld, "", 0, "Alias name already taken", ERR_PERMISSION, mk_sym(T, :create),
            type, obj
        )
    end
    th = info === nothing ? gd.thread.handles[1] : create_thread_handle(gd, info)
    th.alias = name
    gd.thread.thread_table[sym_key(name)] = th.serial     # addNewHTable(threadTable, name, info->symbol)
    return true
end

# PORT: pl-thread.c unalias_thread
"Remove the alias of the handle `th` from the thread table (pl-thread.c)."
function unalias_thread!(gd::PL_global_data{T}, th::thread_handle{T})::Nothing where {T}
    name = th.alias
    if name !== nothing
        if pop!(gd.thread.thread_table, sym_key(name), 0) != 0    # deleteHTable(threadTable, th->alias)
            th.alias = nothing
        end
    end
    return nothing
end

# PORT: pl-thread.c get_interactor
# DIVERGES: returns the handle or `nothing` (upstream: a Bool and `*thp`); the database and the local data are arguments; a text atom
# is looked up by its `sym_key` in `gd.thread.thread_table`, which gives the handle's number (upstream: the symbol).
"The engine handle `t` names (a blob or an alias), else `nothing`, the error raised when `warn` (pl-thread.c)."
function get_interactor(
    gd::PL_global_data{T}, ld::PL_local_data{T}, t::term_t, warn::Bool
)::Union{Nothing, thread_handle{T}} where {T}
    a = PL_get_atom(ld, t)
    if a !== nothing
        symbol = a
        while true                                          # from_symbol:
            th = symbol_thread_handle(gd, symbol)
            if th !== nothing && (th.flags & TH_IS_INTERACTOR) != 0
                if th.info !== nothing ||
                   (th.flags & (TH_INTERACTOR_NOMORE | TH_INTERACTOR_DONE)) != 0
                    return th
                end
                warn && PL_error(ld, ERR_EXISTENCE, mk_sym(T, :engine), t)
            elseif !is_blob(symbol)                         # isTextAtom(symbol)
                serial = get(gd.thread.thread_table, sym_key(symbol), 0)
                if serial != 0
                    symbol = gd.thread.handles[serial].symbol::T    # symbol = word2atom(w); goto from_symbol
                    continue
                end
                warn && PL_error(ld, ERR_EXISTENCE, mk_sym(T, :engine), t)
            else
                warn && PL_type_error(ld, "engine", t)
            end
            return nothing
        end
    else
        warn && PL_type_error(ld, "engine", t)
    end
    return nothing
end

# PORT: pl-thread.c is_engine
# (PRED_IMPL("is_engine", 1, is_engine, 0), pl-thread.c:4504-4510 at the pin)
"`is_engine(@Term)`: true when `Term` is a live engine, or one whose last answer is still to be taken (pl-thread.c)."
function pl_is_engine(ld::PL_local_data{T}, a1::term_t)::foreign_t where {T}
    return get_interactor(_query_gd(ld), ld, a1, false) !== nothing ? FTRUE : FFALSE
end

# PORT: pl-thread.c pl_thread_self
# (FRG("thread_self", 1, pl_thread_self, ISO), pl-ext.c:186; pl-thread.c:2662-2672 `unify_thread_id`,
# 2759-2763 `pl_thread_self` at the pin: `return unify_thread_id(self, LD->thread.info);`)
# DIVERGES: the main thread has no thread record and no handle here: `unify_thread_id` of it unifies its alias, `main` (swipl 10.1.19:
# `thread_self(X)` gives `X = main`). Inside an engine `ld.thread_info` is the engine's record and the answer is its alias or its
# blob handle (`engine_self/1` is `thread_self(E), is_engine(E)`). NOT PORTED: threads other than the main thread and the engines.
"`thread_self(-Thread)`: the identifier of the calling thread: `main`, or the engine's own handle inside an engine (pl-thread.c)."
function pl_thread_self(ld::PL_local_data{T}, self::term_t)::foreign_t where {T}
    return unify_thread_id(_query_gd(ld), ld, self, ld.thread_info) ? FTRUE : FFALSE
end

# ---- ENGINES: CREATING, DESTROYING, POSTING AND FETCHING (TH1 engines, pl-thread.c at 18168e62) ----

# PORT: pl-thread.c copy_local_data
# DIVERGES: the fields the kernel's local data has (the rest of upstream's list has no counterpart: `encoding`, `arith.rat`,
# `gmp.max_integer_size`, `prolog_flag.incomparable_error`, the thread-local flag table (the flags are the database's, ONE copy: `prolog_flag`
# of `GD`), `fli.string_buffers`, the locale (`locale.current` is in the database), `tabling.node_pool`, the message queue, the
# predicate references and the coverage data are not per local data here). `copyStandardStreams` shares the standard streams: the
# creator's `IO_streams` entries are the engine's. `statistics.start_time` is the engine's own (`ld_statistics()` of `_bare_local_data`).
"Copy the creator `ldold`'s settings into the new engine `ldnew`, whose thread record is `info` (pl-thread.c)."
function copy_local_data!(
    ldnew::PL_local_data{T}, ldold::PL_local_data{T}, info::PL_thread_info{T}
)::Nothing where {T}
    ldnew.prompt_current = ldold.prompt_current                 # ldnew->prompt = ldold->prompt
    ldnew.prompt_first = ldold.prompt_first
    ldnew.prompt_first_used = ldold.prompt_first_used
    ldnew.prompt_next = ldold.prompt_next
    ldnew.IO_streams = copy(ldold.IO_streams)                   # copyStandardStreams(ldnew, ldold, attr->flags)
    ldnew.IO_initialised = ldold.IO_initialised
    ldnew.modules_source = ldold.modules_source                 # ldnew->modules = ldold->modules
    ldnew.modules_typein = ldold.modules_typein
    ldnew.debugstatus_skiplevel = ldold.debugstatus_skiplevel   # ldnew->_debugstatus = ldold->_debugstatus
    ldnew.debugstatus_tracing = ldold.debugstatus_tracing
    ldnew.debugstatus_debugging = ldold.debugstatus_debugging
    if ldold.debugstatus_skiplevel != SKIP_VERY_DEEP
        ldnew.debugstatus_debugging = false
        ldnew.debugstatus_tracing = false
        ldnew.debugstatus_skiplevel = SKIP_VERY_DEEP
    end
    ldnew.prolog_flag_mask = ldold.prolog_flag_mask
    ldnew.prolog_flag_occurs_check = ldold.prolog_flag_occurs_check
    ldnew.prolog_flag_access_level = ldold.prolog_flag_access_level
    ldnew.prolog_flag_unknown_option = ldold.prolog_flag_unknown_option
    ldnew.prolog_flag_write_attributes = ldold.prolog_flag_write_attributes
    ldnew.arith_f_flags = ldold.arith_f_flags
    ldnew.stacks_limit = info.stack_limit                       # (`attr->stack_limit`, in positions)
    rnew = ldnew.tabling.restraint                              # ldnew->tabling.restraint = ldold->tabling.restraint
    rold = ldold.tabling.restraint
    rnew.max_table_subgoal_size_action = rold.max_table_subgoal_size_action
    rnew.max_table_subgoal_size = rold.max_table_subgoal_size
    rnew.max_table_answer_size_action = rold.max_table_answer_size_action
    rnew.max_table_answer_size = rold.max_table_answer_size
    rnew.max_answers_for_subgoal_action = rold.max_answers_for_subgoal_action
    rnew.max_answers_for_subgoal = rold.max_answers_for_subgoal
    rnew.max_incomplete_subgoals_action = rold.max_incomplete_subgoals_action
    rnew.max_incomplete_subgoals = rold.max_incomplete_subgoals
    rnew.max_scc_subgoals_action = rold.max_scc_subgoals_action
    rnew.max_scc_subgoals = rold.max_scc_subgoals
    ldnew.table_flags_compile_threshold = ldold.table_flags_compile_threshold
    ldnew.table_flags_drop_intermediate = ldold.table_flags_drop_intermediate
    if !info.debug
        ldnew.debugstatus_tracing = false
        ldnew.debugstatus_debugging = false
        setPrologRunMode!(ldnew, RUN_MODE_NORMAL)
    end
    updateAlerted(ldnew)
    return nothing
end

# PORT: pl-thread.c PL_create_engine as _create_engine
# DIVERGES: the engine is a second local data over the database `gd` (`_bare_local_data`: no `initIO`; the creator's streams are copied by
# `copy_local_data!`); there is no pthread and no `PL_set_engine` (the local data is an argument everywhere). The thread
# initialisation goals run (`thread_init_goals!`, pl-thread.c:7003) and no event is raised (pl-thread.c:6927-7010 raises none). The thread ids
# count up from 2 and are never reused (upstream reuses a free slot). NOT PORTED: the creator's `inherit_from`.
"A new engine, created from `ld`, whose stacks may grow to `stack_limit` positions (pl-thread.c `PL_create_engine`)."
function _create_engine(
    gd::PL_global_data{T}, ld::PL_local_data{T}, stack_limit::Int
)::PL_local_data{T} where {T}
    eld = _bare_local_data(gd)
    gd.thread.highest_id += 1
    info = PL_thread_info{T}(
        gd.thread.highest_id, 1, true, true, false, false, stack_limit, PL_THREAD_RUNNING,
        eld, nothing, :user, nothing
    )                                               # detached: `attrs = {0}` has no PL_THREAD_NOT_DETACHED (pl-thread.c:6967, 4101)
    push!(gd.thread.infos, info)                    # index = pl_tid
    eld.thread_info = info
    copy_local_data!(eld, ld, info)
    thread_init_goals!(gd, eld)
    return eld
end

# PORT: pl-thread.c PL_thread_attach_engine (the call of `PROCEDURE_dthread_init0`, pl-thread.c:7003)
# DIVERGES: the procedure is looked up in `system` at each call (`lookupProcedure`), where upstream keeps it in
# `GD->procedures.dthread_init0` (`LOOKUPPROC(dthread_init0)`, pl-ext.c:374): no database field, the same procedure. `PL_thread_attach_engine`
# is not ported as such (there is no pthread to attach: `_create_engine` is the part of it an engine needs); the call is made in the
# engine's own local data `eld` (upstream: `LD` is the new engine at that point) after `copy_local_data!` and the thread record are in place.
"Run the thread initialisation goals (`'\$thread_init'/0`, boot/toplevel.pl) for the new engine `eld`; the result is ignored (pl-thread.c:7003)."
function thread_init_goals!(gd::PL_global_data{T}, eld::PL_local_data{T})::Nothing where {T}
    pred = lookupProcedure(mk_sym(T, Symbol("\$thread_init")), 0, MODULE_system(gd))
    PL_call_predicate(gd, eld, MODULE_system(gd), PL_Q_NORMAL, pred, 0)    # (void)PL_call_predicate(MODULE_system, PL_Q_NORMAL, ...)
    return nothing
end

# PORT: pl-thread.c PL_thread_at_exit
# DIVERGES: the database and the local data are arguments (`GET_LD`); `func` is a Julia callable called as `func(gd, ld, closure)` (upstream:
# `void (*function)(void *)` called with the closure, `LD` implicit), kept for the database's life (see `register_event_function`). The
# `global` flag is `is_global`. A global function is registered on the list of `thread_exit` (`GD->event.hook.onthreadexit`) and runs for
# every engine that is destroyed, a local one on the list of `this_thread_exit` (`LD->event.hook.onthreadexit`: the list of `ld`, the
# thread that registers), at the head of its list (`last` false, as upstream), before the Prolog listeners that are registered later.
"Run `func(gd, ld, closure)` when this thread (`is_global` false) or any thread (true) exits, while Prolog queries still work (pl-thread.c)."
function PL_thread_at_exit(
    gd::PL_global_data{T}, ld::PL_local_data{T}, func, closure, is_global::Bool
)::Bool where {T}
    loc = event_location{T}(is_global ? PLEV_THREAD_EXIT : PLEV_THIS_THREAD_EXIT, nothing)
    return register_event_function(gd, ld, loc, nothing, false, func, closure, 0, EV_CALLBACK_VOID)
end

# PORT: pl-thread.c freePrologThread (the exit hooks and the release of the thread record; `after_fork` is false)
# DIVERGES: the engine's local data is dropped by the garbage collector (`freeStacks`, `freePrologLocalData`, `cleanupLocalDefinitions`,
# the message queue and the thread's statistics are not kept: no pool); `startCritical`/`endCritical` block signals (none here) and
# the test `ld->stacks.argument.base` (stacks initialised) is always true: `_bare_local_data` makes them; `info->in_exit_hooks` has no field
# (nothing reads it). What upstream writes to
# `Serror` is collected on the local data's `messages` (`_qlf_Sdprintf!`, `_qlf_pl_write!`: the term unquoted, no newline flag).
# The thread is an engine: `ld` is `LD` at the call (`PL_destroy_engine` sets the engine), so `this_thread_exit` is raised.
"Run the exit events of the engine `ld` (`this_thread_exit`, `thread_exit`) and release its thread record (pl-thread.c `freePrologThread`)."
function freePrologThread!(
    gd::PL_global_data{T}, ld::PL_local_data{T}, info::PL_thread_info{T}
)::Nothing where {T}
    if info.status == PL_THREAD_RUNNING
        info.status = PL_THREAD_EXITED                      # foreign pthread_exit()
    end
    rc1 = callEventHook(gd, ld, PLEV_THIS_THREAD_EXIT)      # `LD == ld`
    rc2 = callEventHook(gd, ld, PLEV_THREAD_EXIT, info)
    if (!rc1 || !rc2) && ld.exception_term != 0
        _qlf_Sdprintf!(ld, "Event hook \"thread_finished\" left an exception\n")
        _qlf_pl_write!(ld, ld.exception_term)               # PL_write_term(Serror, exception_term, 1200, PL_WRT_QUOTED|PL_WRT_NEWLINE)
        PL_clear_exception(ld)
    end
    info.thread_data = nothing                              # avoid a loop
    info.has_tid = false                                    # needed?
    return nothing
end

# PORT: pl-thread.c PL_thread_destroy_engine as _destroy_engine!
# DIVERGES: the engine is the handle's (`PL_destroy_engine(th->info->thread_data)` and `PL_thread_destroy_engine()` of the current
# engine are one function here: there is no current engine to compare with); `free_prolog_thread` is `freePrologThread!` (the
# exit events), then the thread record dropped from `gd.thread.infos` and from the handle.
"Leave the engine of the handle `th`: the last user ends it (pl-thread.c)."
function _destroy_engine!(gd::PL_global_data{T}, th::thread_handle{T})::Nothing where {T}
    info = th.info::PL_thread_info{T}
    info.open_count -= 1
    if info.open_count == 0
        freePrologThread!(gd, info.thread_data::PL_local_data{T}, info)
        gd.thread.infos[info.pl_tid] = nothing
        th.info = nothing
    end
    return nothing
end

# PORT: pl-thread.c destroy_interactor
# DIVERGES: no mutex (no OS thread: `unlock` has no counterpart); the query is closed in the engine's own local data, passed
# explicitly (`PL_set_engine`).
"Close the engine of the handle `th` and make its handle empty again (pl-thread.c)."
function destroy_interactor!(
    gd::PL_global_data{T}, th::thread_handle{T}, gc::Bool
)::Nothing where {T}
    if th.interactor_query != 0
        eld = (th.info::PL_thread_info{T}).thread_data::PL_local_data{T}
        PL_close_query(eld, th.interactor_query)
        th.interactor_query = 0
    end
    if th.info !== nothing
        _destroy_engine!(gd, th)
        gd.thread.engines_finished += 1
    end
    th.interactor_package = nothing                 # PL_erase(th->interactor.package)
    th.flags &= ~(TH_INTERACTOR_NOMORE | TH_INTERACTOR_DONE)
    unalias_thread!(gd, th)
    return nothing
end

# PORT: pl-thread.c done_interactor
"The engine of the handle `th` computed its last result: free it, keep the handle valid for the final `engine_next/2` (pl-thread.c)."
function done_interactor!(gd::PL_global_data{T}, th::thread_handle{T})::Nothing where {T}
    th.flags |= TH_INTERACTOR_DONE
    _destroy_engine!(gd, th)
    gd.thread.engines_finished += 1
    return nothing
end

# PORT: pl-thread.c copy_debug_mode
"Give the engine `to` the debug and trace mode of the caller `from` (pl-thread.c)."
function copy_debug_mode(to::PL_local_data{T}, from::PL_local_data{T})::Nothing where {T}
    if to.debugstatus_debugging != from.debugstatus_debugging
        debugmode(to, from.debugstatus_debugging, nothing, UInt32(0))
    end
    if to.debugstatus_tracing != from.debugstatus_tracing
        tracemode(to, from.debugstatus_tracing, nothing)
    end
    return nothing
end

# PORT: pl-thread.c make_engine_options
const make_engine_options = (
    PL_option_t(:stack_limit, OPT_SIZE | OPT_INF),
    PL_option_t(:alias, OPT_ATOM),
    PL_option_t(:inherit_from, OPT_TERM)
)

# PORT: pl-thread.c engine_create
# (PRED_IMPL("$engine_create", 3, engine_create, 0), pl-thread.c:4097-4170 at the pin)
# DIVERGES: the option `stack_limit` is in bytes and the engine's limit in positions (words): `min(bytes ÷ 8, typemax(Int) >> 8)` (`stacks_limit`
# is multiplied by 8 where bytes are wanted, src/pl-gmp.jl); `inherit_from` is read and ignored, as upstream. The goal's record is made in
# the caller's local data and read in the engine's (`PL_record`/`PL_recorded` take the local data explicitly; a record holds its own
# values). The `assert(0)` (TBD: copy exception) of upstream is an error. NOT PORTED: `PL_unregister_atom(th->symbol)` (no atom GC).
"`\$engine_create(-Handle, +GoalAndTemplate, +Options)`: make an engine that runs `Goal`, answering `Template` (pl-thread.c)."
function pl_engine_create(
    ld::PL_local_data{T}, A1::term_t, A2::term_t, A3::term_t
)::foreign_t where {T}
    gd = _query_gd(ld)
    vals = PL_scan_options(ld, A3, 0, "engine_option", make_engine_options)
    vals === nothing && return FFALSE
    stack = vals[1] === nothing ? 0 : vals[1]::Int
    alias = vals[2] === nothing ? nothing : vals[2]::T
    limit = stack != 0 ? min(stack ÷ 8, typemax(Int) >> 8) : ld.stacks_limit   # attrs.stack_limit

    eld = _create_engine(gd, ld, limit)
    info = eld.thread_info::PL_thread_info{T}
    info.is_engine = true
    th = create_thread_handle(gd, info)
    th.flags |= TH_IS_INTERACTOR
    gd.thread.engines_created += 1

    if alias !== nothing
        if !aliasThread!(gd, ld, info, mk_sym(T, :engine), alias)
            destroy_interactor!(gd, th, false)
            return FFALSE
        end
    end

    if !unify_thread_id(gd, ld, A1, info)
        destroy_interactor!(gd, th, false)
        if PL_exception(ld, 0) == 0
            return PL_error(ld, "", 0, "", ERR_UNINSTANTIATION, 0, A1) ? FTRUE : FFALSE
        end
        return FFALSE
    end

    pred = lookupProcedure(mk_sym(T, :call), 1, MODULE_system(gd))
    r = PL_record(ld, A2)
    t = PL_new_term_ref(eld)                        # WITH_LD(new)
    argv = PL_new_term_refs(eld, 2)
    th.interactor_argv = argv
    if t != 0 && argv != 0 && PL_recorded(eld, r, t) && _PL_get_arg(eld, 1, t, argv) &&
       _PL_get_arg(eld, 2, t, argv + 1)
        th.interactor_query = PL_open_query(
            gd, eld, nothing, PL_Q_CATCH_EXCEPTION | PL_Q_ALLOW_YIELD | PL_Q_EXT_STATUS, pred,
            argv + 1
        )
    else
        error("\$engine_create/3: the goal could not be copied into the engine (upstream: assert(0), TBD: copy exception)")
    end
    PL_erase(r)
    return FTRUE
end

# PORT: pl-thread.c engine_destroy
# (PRED_IMPL("engine_destroy", 1, engine_destroy, 0), pl-thread.c:4233-4247 at the pin)
# DIVERGES (TH1): an engine that is running (its query is inside `engine_next/2`, so it is the caller of the running engine or the
# engine itself) is not destroyed: `permission_error(destroy, engine, E)`, as for the engine itself; upstream waits for the engine's
# mutex, which the running call holds (a deadlock on one thread). `th->info == LD->thread.info` needs `th.info` to exist: the main
# thread has no record here.
"`engine_destroy(+Engine)`: destroy the engine (pl-thread.c)."
function pl_engine_destroy(ld::PL_local_data{T}, A1::term_t)::foreign_t where {T}
    gd = _query_gd(ld)
    th = get_interactor(gd, ld, A1, true)
    th === nothing && return FFALSE
    if (th.info !== nothing && th.info === ld.thread_info) || th.running
        return PL_error(
            ld, "", 0, "", ERR_PERMISSION, mk_sym(T, :destroy), mk_sym(T, :engine), A1
        ) ? FTRUE : FFALSE
    end
    destroy_interactor!(gd, th, false)
    return FTRUE
end

# PORT: pl-thread.c engine_post
# (PRED_IMPL("engine_post", 2, engine_post, 0), pl-thread.c:4437-4461 at the pin)
# DIVERGES (TH1): posting to a running engine is `permission_error(post_to, engine, E)` (upstream waits for the mutex the running
# `engine_next/2` holds); a record made in the caller's local data is read in the engine's by `engine_fetch/1`.
"`engine_post(+Engine, +Term)`: make `Term` available to `engine_fetch/1` of the engine (pl-thread.c)."
function pl_engine_post2(ld::PL_local_data{T}, A1::term_t, A2::term_t)::foreign_t where {T}
    gd = _query_gd(ld)
    th = get_interactor(gd, ld, A1, true)
    th === nothing && return FFALSE
    if th.interactor_package === nothing && !th.running
        th.interactor_package = PL_record(ld, A2)
        return FTRUE
    end
    return PL_error(
        ld, "", 0, "", ERR_PERMISSION, mk_sym(T, :post_to), mk_sym(T, :engine), A1
    ) ? FTRUE : FFALSE
end

# PORT: pl-thread.c engine_fetch
# (PRED_IMPL("engine_fetch", 1, engine_fetch, 0), pl-thread.c:4473-4502 at the pin)
"`engine_fetch(-Term)`: the term `engine_post/2,3` delivered to the running engine (pl-thread.c)."
function pl_engine_fetch(ld::PL_local_data{T}, A1::term_t)::foreign_t where {T}
    gd = _query_gd(ld)
    info = ld.thread_info
    if info !== nothing && info.is_engine
        th = symbol_thread_handle(gd, info.symbol)::thread_handle{T}
        if th.interactor_package !== nothing
            tmp = PL_new_term_ref(ld)
            rc = tmp != 0 && PL_recorded(ld, th.interactor_package, tmp) && PL_unify(ld, A1, tmp)
            th.interactor_package = nothing         # PL_erase(th->interactor.package)
            return rc ? FTRUE : FFALSE
        end
    end

    exv = PL_new_term_refs(ld, 2)
    return (
        exv != 0 && PL_unify_atom(ld, exv, mk_sym(T, :delivery)) &&
        unify_thread_id(gd, ld, exv + 1, info) &&
        PL_existence_error3(
            ld, mk_sym(T, :term), exv, exv + 1, "engine_fetch", 1, "Use engine_post/2,3"
        )
    ) ? FTRUE : FFALSE
end

# ---- ENGINES: engine_next/2, engine_post/3 AND THE ANSWER (TH1 engines, pl-thread.c at 18168e62) ----

# PORT: pl-thread.c YIELD_ENGINE_YIELD
# (#define YIELD_ENGINE_YIELD 256, pl-thread.c:4290: the code `engine_yield/1` makes `PL_next_solution` return)
const YIELD_ENGINE_YIELD = 256

# PORT: pl-thread.c thread_symbol
# DIVERGES: the database is an argument; the main thread has no record, so its symbol is its alias (`main_thread_alias`).
"The symbol the posting thread of an engine call is known by: the engine's caller thread inside an engine, else its own (pl-thread.c)."
function thread_symbol(
    gd::PL_global_data{T}, ld::PL_local_data{T}
)::Union{Nothing, T} where {T}
    info = ld.thread_info
    info === nothing && return main_thread_alias(gd)
    if info.is_engine
        th = symbol_thread_handle(gd, info.symbol)::thread_handle{T}
        return th.interactor_thread
    end
    return info.symbol
end

# PORT: pl-thread.c interactor_post_answer_nolock
# (pl-thread.c:4293-4389 at the pin; `activate_interactor` = the engine's record gets its thread id, `suspend_interactor` = it loses it)
# DIVERGES: the database and the caller's local data are arguments, the engine's local data is the one of its record (`WITH_LD`), the
# answer travels through `PL_record` (made in the engine's local data) and `PL_recorded` (read in the caller's): a record holds its own
# values, no `duplicate_term`. The engine is marked `running` while its query runs (see `interactor_post_answer`). The default case
# (an unknown yield code) raises in the caller's local data and the engine stays active (upstream raises in the engine's, unsuspended).
"Run the engine `th` to its next answer and unify it with `term`; `package` is the term to hand to it (pl-thread.c)."
function interactor_post_answer_nolock(
    gd::PL_global_data{T}, ld::PL_local_data{T}, th::thread_handle{T}, ref::term_t,
    package::Union{Nothing, term_t}, term::term_t
)::Bool where {T}
    if package !== nothing && th.interactor_package !== nothing
        return PL_error(
            ld, "", 0, "", ERR_PERMISSION, mk_sym(T, :post_to), mk_sym(T, :engine), ref
        )
    end

    if th.interactor_query == 0
        if (th.flags & TH_INTERACTOR_NOMORE) != 0
            th.flags &= ~TH_INTERACTOR_NOMORE
            th.flags |= TH_INTERACTOR_DONE
            return false
        end
        return PL_error(ld, ERR_EXISTENCE, mk_sym(T, :engine), ref)
    end

    if package !== nothing
        th.interactor_package = PL_record(ld, package)
    end

    info = th.info::PL_thread_info{T}
    eld = info.thread_data::PL_local_data{T}
    info.has_tid = true                             # activate_interactor
    copy_debug_mode(eld, ld)
    q = th.interactor_query
    th.running = true
    rc = try
        PL_next_solution(gd, eld, q)
    finally
        th.running = false
    end

    r = nothing                                     # the answer, recorded in the engine's local data
    if rc == PL_S_TRUE
        r = PL_record(eld, th.interactor_argv)
    elseif rc == PL_S_LAST
        r = PL_record(eld, th.interactor_argv)
        PL_close_query(eld, q)
        th.interactor_query = 0
        done_interactor!(gd, th)
        th.flags |= TH_INTERACTOR_NOMORE
    elseif rc == PL_S_FALSE
        PL_close_query(eld, q)
        th.interactor_query = 0
        done_interactor!(gd, th)
        info.has_tid = false                        # suspend_interactor
        return false
    elseif rc == PL_S_EXCEPTION
        er = PL_record(eld, PL_exception(eld, q))
        PL_close_query(eld, q)
        th.interactor_query = 0
        done_interactor!(gd, th)
        info.has_tid = false                        # suspend_interactor
        ex = PL_new_term_ref(ld)
        ok = ex != 0 && PL_recorded(ld, er, ex) && PL_raise_exception(ld, ex)
        PL_erase(er)
        return ok
    elseif rc == YIELD_ENGINE_YIELD                 # engine_yield/1
        r = PL_record(eld, PL_yielded(eld, q))      # the query stays open: the next call resumes after the yield
    else
        info.has_tid = false
        ex = PL_new_term_ref(ld)
        return ex != 0 && PL_put_integer(ld, ex, rc) &&
               PL_domain_error(ld, "engine_yield_code", ex)
    end

    info.has_tid = false                            # suspend_interactor
    t = PL_new_term_ref(ld)
    ok = t != 0 && PL_recorded(ld, r::record{T}, t) && PL_unify(ld, term, t)
    PL_erase(r::record{T})
    return ok
end

# PORT: pl-thread.c interactor_post_answer
# (pl-thread.c:4402-4423 at the pin)
# DIVERGES (TH1): a call to an engine that is already running (an engine that calls `engine_next/2` on itself, or on the engine that is
# calling it) is `permission_error(resume, engine, Engine)`, made BEFORE the caller's symbol is set (the nested call would reset it);
# upstream waits for the engine's mutex, which the running call holds (a deadlock on one thread). The mutex itself does not exist here.
"Post `package` (if any) to the engine `ref` names and unify its next answer with `term` (pl-thread.c)."
function interactor_post_answer(
    gd::PL_global_data{T}, ld::PL_local_data{T}, ref::term_t,
    package::Union{Nothing, term_t}, term::term_t
)::Bool where {T}
    th = get_interactor(gd, ld, ref, true)
    th === nothing && return false
    if th.running                                   # DIVERGES (TH1): upstream hangs on the mutex
        return PL_error(
            ld, "", 0, "", ERR_PERMISSION, mk_sym(T, :resume), mk_sym(T, :engine), ref
        )
    end
    th.interactor_thread = thread_symbol(gd, ld)
    rc = try
        interactor_post_answer_nolock(gd, ld, th, ref, package, term)
    finally
        th.interactor_thread = nothing
    end
    return rc
end

# PORT: pl-thread.c engine_next
# (PRED_IMPL("engine_next", 2, engine_next, 0), pl-thread.c:4428-4433 at the pin)
"`engine_next(+Engine, -Term)`: run the engine to its next answer (pl-thread.c)."
function pl_engine_next(ld::PL_local_data{T}, A1::term_t, A2::term_t)::foreign_t where {T}
    return interactor_post_answer(_query_gd(ld), ld, A1, nothing, A2) ? FTRUE : FFALSE
end

# PORT: pl-thread.c engine_post
# (PRED_IMPL("engine_post", 3, engine_post, 0), pl-thread.c:4465-4470 at the pin)
"`engine_post(+Engine, +Term, -Next)`: `engine_post/2` and `engine_next/2` in one (pl-thread.c)."
function pl_engine_post3(
    ld::PL_local_data{T}, A1::term_t, A2::term_t, A3::term_t
)::foreign_t where {T}
    return interactor_post_answer(_query_gd(ld), ld, A1, A2, A3) ? FTRUE : FFALSE
end

# ---- THREAD PROPERTIES: thread_property/2 (TH1, pl-thread.c:3150-3512 and get_prop_def :8376 at 18168e62) ----
# `thread_property/2` runs over the thread records of the database: the engines (`gd.thread.infos`, by `pl_tid`) and the main thread, which
# has no record here (its slot 1 stays `nothing`) and is answered as a record `nothing`, as `unify_thread_id` does. DIVERGES (TH1): the
# enumeration state (`tprop_enum`: tid, the property cursor, the two enumeration flags) is ONE integer, the `PL_retry` context
# (`ForeignRedoInt`) where upstream allocates it (`allocForeignState`): a cut has nothing to free.

# PORT: pl-thread.c get_prop_def
# DIVERGES: returns `(rc, index)`, the index into the property names `names` (upstream: a pointer into the `tprop` list); `rc` as
# upstream: 1 the property is given, 0 a variable (enumerate), -1 an error raised. A property is its name with ONE argument.
"The property `t` names in `names` (1 and its index), 0 when `t` is a variable, -1 with the error raised (pl-thread.c)."
function get_prop_def(
    ld::PL_local_data{T}, t::term_t, expected::Symbol, names::NTuple{N, Symbol}
)::Tuple{Int, Int} where {T, N}
    f = PL_get_functor(ld, t)
    if f !== nothing
        key = sym_key(f[1])
        for i in 1:N
            if f[2] == 1 && key == sym_key(mk_sym(T, names[i]))
                return (1, i)
            end
        end
        PL_error(ld, ERR_DOMAIN, mk_sym(T, expected), t)
        return (-1, 0)
    end
    PL_is_variable(ld, t) && return (0, 0)
    PL_error(ld, ERR_TYPE, mk_sym(T, expected), t)
    return (-1, 0)
end

# PORT: pl-thread.c get_thread
# (pl-thread.c:2580-2628 at the pin)
# DIVERGES: returns the thread id `pl_tid` (0: false, the error raised when `warn`), as the record is read again from the id by the caller;
# the main thread (id 1, no record) is its handle (`register_main_thread!`: the text alias `main` is in `thread_table`, as upstream's
# `threadTable`) or the integer 1.
"The thread id of the thread `t` names (an integer, an alias or a handle), 0 when there is none (pl-thread.c)."
function get_thread(
    gd::PL_global_data{T}, ld::PL_local_data{T}, t::term_t, warn::Bool
)::Int where {T}
    i = -1
    a = PL_get_atom(ld, t)
    if a !== nothing
        symbol = a
        while true                                          # from_symbol:
            th = symbol_thread_handle(gd, symbol)
            if th !== nothing
                thinfo = th.info
                if thinfo !== nothing && thinfo.status >= PL_THREAD_RUNNING
                    i = th.engine_id
                    break
                end
                if thinfo === nothing && th.engine_id == 1    # the main thread's handle: no record (`_thread_slot_valid` accepts slot 1)
                    i = 1
                    break
                end
                warn && PL_error(ld, ERR_EXISTENCE, mk_sym(T, :thread), t)    # no_thread
                return 0
            elseif !is_blob(symbol)                         # isTextAtom(symbol)
                serial = get(gd.thread.thread_table, sym_key(symbol), 0)
                if serial != 0
                    symbol = gd.thread.handles[serial].symbol::T    # symbol = word2atom(w)
                    continue
                end
                warn && PL_error(ld, ERR_EXISTENCE, mk_sym(T, :thread), t)    # no_thread
                return 0
            else
                warn && PL_type_error(ld, "thread", t)
                return 0
            end
        end
    else
        n = PL_get_integer(ld, t)
        if n === nothing
            warn && PL_type_error(ld, "thread", t)
            return 0
        end
        i = n
    end

    if i < 1 || i > gd.thread.highest_id || !_thread_slot_valid(gd, i)
        warn && PL_error(ld, ERR_EXISTENCE, mk_sym(T, :thread), t)    # no_thread
        return 0
    end
    return i
end

# ORIGINAL: the test `THREAD_STATUS_INVALID(GD->thread.threads[i]->status)` of get_thread/advance_state, on the kernel's table: the main
# thread (slot 1) is always valid, a slot of an engine that was destroyed is `nothing` (upstream: its status is UNUSED).
"Whether the thread id `i` (1 <= i <= highest_id) is a running thread or engine."
function _thread_slot_valid(gd::PL_global_data{T}, i::Int)::Bool where {T}
    i == 1 && return true
    info = gd.thread.infos[i]
    return info !== nothing && info.status >= PL_THREAD_RUNNING
end

# PORT: pl-thread.c symbol_alias
"The alias of the thread handle the blob `symbol` names, or `nothing` (pl-thread.c)."
function symbol_alias(gd::PL_global_data{T}, symbol::Union{Nothing, T})::Union{Nothing, T} where {T}
    th = symbol_thread_handle(gd, symbol)
    th === nothing && return nothing
    return th.alias
end

# PORT: pl-thread.c PL_thread_self
# DIVERGES: the local data is an argument (`GET_LD`); the main thread has no record here (`ld.thread_info === nothing`) and is id 1.
# The `-1` of a thread with no Prolog thread cannot be reached (every local data of the kernel belongs to the main thread or an engine).
"The id of the calling thread: its record's `pl_tid`, 1 for the main thread (pl-thread.c `PL_thread_self`)."
function PL_thread_self(ld::PL_local_data{T})::Int where {T}
    info = ld.thread_info
    info === nothing && return 1
    return info.pl_tid
end

# PORT: pl-thread.c PL_unify_thread_id
# DIVERGES: the database and the local data are arguments; the main thread (id 1) has no record and is unified through
# `unify_thread_id` with `nothing`; the test of an unused or reserved slot is on the kernel's table (a destroyed engine's slot is `nothing`).
"Unify `t` with the identifier of the thread `i`: 1 or 0 as the unification, -1 when `i` is no thread (pl-thread.c)."
function PL_unify_thread_id(
    gd::PL_global_data{T}, ld::PL_local_data{T}, t::term_t, i::Int
)::Int where {T}
    if i < 1 || i > gd.thread.highest_id
        return -1
    end
    info = i == 1 ? nothing : gd.thread.infos[i]
    if i != 1 && (info === nothing || info.status == PL_THREAD_UNUSED || info.status == PL_THREAD_RESERVED)
        return -1
    end
    return unify_thread_id(gd, ld, t, info) ? 1 : 0
end

# PORT: pl-thread.c PL_get_thread_id_ex
# DIVERGES: the id is the result (`nothing`: false, the error raised), not an out parameter.
"The id of the thread `t` names (an integer, an alias or a handle), `nothing` with the error raised when there is none (pl-thread.c)."
function PL_get_thread_id_ex(
    gd::PL_global_data{T}, ld::PL_local_data{T}, t::term_t
)::Union{Nothing, Int} where {T}
    tid = get_thread(gd, ld, t, true)
    return tid == 0 ? nothing : tid
end

# PORT: pl-thread.c PL_get_thread_alias
# DIVERGES: the alias is the result (`nothing`: false); the database and the local data are arguments; the main thread has no record
# and no record here, its alias is that of its handle, `main_thread_alias` (upstream registers it with `aliasThread` at start).
"The alias atom of the thread `tid` (0: the calling thread), or `nothing` when it has none (pl-thread.c)."
function PL_get_thread_alias(
    gd::PL_global_data{T}, ld::PL_local_data{T}, tid::Int
)::Union{Nothing, T} where {T}
    tid == 0 && (tid = PL_thread_self(ld))
    if tid < 1 || tid > gd.thread.highest_id
        return nothing
    end
    tid == 1 && return main_thread_alias(gd)
    info = gd.thread.infos[tid]
    info === nothing && return nothing
    return symbol_alias(gd, info.symbol)
end

# PORT: pl-thread.c unify_thread_status
# (pl-thread.c:2698-2765 at the pin; `unify_engine_status` :2690-2696)
# DIVERGES: the main thread is a record `nothing` and is running; the lock (`lock`) has no counterpart. `info.return_value` is the
# thread's recorded result; no engine ends with a status that reads it (a finished engine's slot is dropped), so the statuses `exited`,
# `exception` and `nomem` are reached only with a record whose status was set by hand (the white-box rows of the engines test).
"Unify `status` with the status `stat` of the thread `info`: `running`, `suspended` (an engine not entered), `exited(T)`, `true`, `false`, `exception(T)` (pl-thread.c)."
function unify_thread_status(
    gd::PL_global_data{T}, ld::PL_local_data{T}, status::term_t,
    info::Union{Nothing, PL_thread_info{T}}, stat::Int
)::Bool where {T}
    if stat == PL_THREAD_CREATED || stat == PL_THREAD_RUNNING
        if info !== nothing && info.is_engine && !info.has_tid
            return PL_unify_atom(ld, status, mk_sym(T, :suspended))    # unify_engine_status
        end
        return PL_unify_atom(ld, status, mk_sym(T, :running))
    elseif stat == PL_THREAD_EXITED || stat == PL_THREAD_EXCEPTION
        tmp = PL_new_term_ref(ld)
        rc = true
        rv = info === nothing ? nothing : info.return_value
        if rv !== nothing
            rc = PL_recorded(ld, rv, tmp)
        end
        rc || return raiseStackOverflow(ld, GLOBAL_OVERFLOW)
        a1 = PL_new_term_ref(ld)                            # PL_unify_term(status, PL_FUNCTOR, f, PL_TERM, tmp)
        return PL_unify_functor(
                ld, status, mk_sym(T, stat == PL_THREAD_EXITED ? :exited : :exception), 1
            ) && _PL_get_arg(ld, 1, status, a1) && PL_unify(ld, a1, tmp)
    elseif stat == PL_THREAD_SUCCEEDED
        return PL_unify_atom(ld, status, mk_sym(T, :true))
    elseif stat == PL_THREAD_FAILED
        return PL_unify_atom(ld, status, mk_sym(T, :false))
    elseif stat == PL_THREAD_NOMEM
        # exception(error(resource_error(memory), _))
        a1 = PL_new_term_ref(ld)
        a2 = PL_new_term_ref(ld)
        a3 = PL_new_term_ref(ld)
        return PL_unify_functor(ld, status, mk_sym(T, :exception), 1) &&
               _PL_get_arg(ld, 1, status, a1) &&
               PL_unify_functor(ld, a1, mk_sym(T, :error), 2) &&
               _PL_get_arg(ld, 1, a1, a2) &&
               PL_unify_functor(ld, a2, mk_sym(T, :resource_error), 1) &&
               _PL_get_arg(ld, 1, a2, a3) &&
               PL_unify_atom(ld, a3, mk_sym(T, :memory))
    end
    return false                                            # default: can happen in current_thread/2
end

# ORIGINAL: the names of upstream's `tprop_list` (pl-thread.c:3355-3367), in its order; the property functions below are called by index
# (`_tprop_call`) where upstream calls a function pointer.
const THREAD_PROPERTY_NAMES = (
    :id, :alias, :status, :detached, :debug, :debug_mode, :engine, :thread,
    :system_thread_id, :size, :class,
)

# PORT: pl-thread.c thread_id_property
"`id(Id)`: the number of the thread (pl-thread.c)."
function thread_id_property(
    ld::PL_local_data{T}, info::Union{Nothing, PL_thread_info{T}}, prop::term_t
)::Bool where {T}
    return PL_unify_integer(ld, prop, info === nothing ? 1 : info.pl_tid)
end

# PORT: pl-thread.c thread_alias_property
# DIVERGES: the alias of the main thread is that of its handle, `main_thread_alias` (it has no record here).
"`alias(Alias)`: the alias of the thread, when it has one (pl-thread.c)."
function thread_alias_property(
    gd::PL_global_data{T}, ld::PL_local_data{T}, info::Union{Nothing, PL_thread_info{T}},
    prop::term_t
)::Bool where {T}
    info === nothing && return PL_unify_atom(ld, prop, main_thread_alias(gd))
    alias = symbol_alias(gd, info.symbol)
    alias === nothing && return false
    return PL_unify_atom(ld, prop, alias)
end

# PORT: pl-thread.c thread_status_property
"`status(Status)`: the status of the thread (pl-thread.c)."
function thread_status_property(
    gd::PL_global_data{T}, ld::PL_local_data{T}, info::Union{Nothing, PL_thread_info{T}},
    prop::term_t
)::Bool where {T}
    stat = info === nothing ? PL_THREAD_RUNNING : info.status
    return unify_thread_status(gd, ld, prop, info, stat)
end

# PORT: pl-thread.c thread_detached_property
# DIVERGES: the main thread has no record: its flag is `main_detached` of `gd.thread` (false until `thread_detach/1` sets it).
"`detached(Bool)`: whether the thread is detached (pl-thread.c)."
function thread_detached_property(
    ld::PL_local_data{T}, info::Union{Nothing, PL_thread_info{T}}, prop::term_t
)::Bool where {T}
    return PL_unify_bool_ex(
        ld, prop, info === nothing ? _query_gd(ld).thread.main_detached : info.detached
    )
end

# PORT: pl-thread.c thread_debug_property
# DIVERGES: the main thread has no record: its flag is `main_debug` of `gd.thread` (true until `set_thread/2` changes it).
"`debug(Bool)`: whether the thread can be debugged (pl-thread.c)."
function thread_debug_property(
    ld::PL_local_data{T}, info::Union{Nothing, PL_thread_info{T}}, prop::term_t
)::Bool where {T}
    return PL_unify_bool_ex(
        ld, prop, info === nothing ? _query_gd(ld).thread.main_debug : info.debug
    )
end

# PORT: pl-thread.c thread_debug_mode_property
# DIVERGES: the local data of the main thread is not kept in the database: it is read when `ld` is the main thread's own, else the
# property fails (upstream: `info->thread_data`, which the main thread has).
"`debug_mode(Bool)`: whether the thread is in debug mode (pl-thread.c)."
function thread_debug_mode_property(
    ld::PL_local_data{T}, info::Union{Nothing, PL_thread_info{T}}, prop::term_t
)::Bool where {T}
    dbgmode = nothing
    if info === nothing
        ld.thread_info === nothing && (dbgmode = ld.debugstatus_debugging)
    elseif info.thread_data !== nothing
        dbgmode = (info.thread_data::PL_local_data{T}).debugstatus_debugging
    end
    dbgmode === nothing && return false
    return PL_unify_bool_ex(ld, prop, dbgmode)
end

# PORT: pl-thread.c thread_engine_property
"`engine(Bool)`: whether the thread is an engine (pl-thread.c)."
function thread_engine_property(
    ld::PL_local_data{T}, info::Union{Nothing, PL_thread_info{T}}, prop::term_t
)::Bool where {T}
    return PL_unify_bool_ex(ld, prop, info === nothing ? false : info.is_engine)
end

# PORT: pl-thread.c thread_thread_property
"`thread(Thread)`: the thread an engine is called from (pl-thread.c)."
function thread_thread_property(
    gd::PL_global_data{T}, ld::PL_local_data{T}, info::Union{Nothing, PL_thread_info{T}},
    prop::term_t
)::Bool where {T}
    (info === nothing || !info.is_engine) && return false
    th = symbol_thread_handle(gd, info.symbol)
    (th === nothing || th.interactor_thread === nothing) && return false
    alias = symbol_alias(gd, th.interactor_thread)
    return PL_unify_atom(ld, prop, alias === nothing ? th.interactor_thread : alias)
end

# PORT: pl-thread.c system_thread_id
# DIVERGES: the kernel runs on the OS threads Julia gives it and has no thread record of its own: the identifier is the calling
# thread's (`gettid`, as `PID_IDENTIFIES_THREAD` builds answer), on Linux; elsewhere -1, upstream's "cannot tell" (the property then fails).
"The operating system's id of the calling thread, -1 when the kernel cannot tell (pl-thread.c)."
function system_thread_id()::Int
    Sys.islinux() || return -1
    return Int(ccall(:gettid, Cint, ()))
end

# PORT: pl-thread.c thread_tid_property
# DIVERGES: an engine runs on the thread that entered it, so its id is that of the calling thread (upstream records it when the engine is
# entered: `set_system_thread_id`, activate_interactor); the main thread (no record) always has one, as upstream's `has_tid` of main.
"`system_thread_id(Id)`: the operating system's id of the thread, while it is entered (pl-thread.c)."
function thread_tid_property(
    ld::PL_local_data{T}, info::Union{Nothing, PL_thread_info{T}}, prop::term_t
)::Bool where {T}
    if info === nothing || info.has_tid
        tid = system_thread_id()
        tid != -1 && return PL_unify_integer(ld, prop, tid)
    end
    return false
end

# PORT: pl-thread.c sizeof_thread
# DIVERGES: the kernel's own count in bytes, not upstream's (the C structs `sizeof(*info)` and `sizeof(*ld)` have no Julia value: the
# sizes of the record's fields, 8 bytes a word); the global, local and trail stacks and their spares as the kernel measures them
# (`_size_stack`). NOT counted, named: the argument stack (the kernel has none), the message queue (no queue exists), the thread-local
# definitions (no per-thread clause vector, src/pl-proc.jl `new_ldef_vector` note) and the tabling node pool. The main thread has no record
# or kept local data: `ld` counts when it IS the main thread's, else 0 (upstream: `info->thread_data`, which main has).
"The bytes the thread `info` uses, 0 when it is not running (pl-thread.c)."
function sizeof_thread(
    ld::PL_local_data{T}, info::Union{Nothing, PL_thread_info{T}}
)::Int where {T}
    size = sizeof(PL_thread_info{T})
    tld = nothing
    if info === nothing
        ld.thread_info === nothing && (tld = ld)
    else
        info.status != PL_THREAD_RUNNING && return 0
        tld = info.thread_data
    end
    if tld !== nothing
        eld = tld::PL_local_data{T}
        size += sizeof(PL_local_data{T})
        size += _size_stack(eld, :global) + 8 * eld.global_spare
        size += _size_stack(eld, :local) + 8 * eld.local_spare
        size += _size_stack(eld, :trail) + 8 * eld.trail_spare
    end
    return size
end

# PORT: pl-thread.c thread_size_property
"`size(Bytes)`: the memory the thread uses, when it is running (pl-thread.c)."
function thread_size_property(
    ld::PL_local_data{T}, info::Union{Nothing, PL_thread_info{T}}, prop::term_t
)::Bool where {T}
    size = sizeof_thread(ld, info)
    size != 0 && return PL_unify_int64(ld, prop, size)
    return false
end

# PORT: pl-thread.c thread_class_property
# DIVERGES: the main thread has no class until `set_thread(main, class(C))` gives it one (`main_class` of `gd.thread`; upstream: `console`).
"`class(Class)`: the class of the thread, when it has one (pl-thread.c)."
function thread_class_property(
    ld::PL_local_data{T}, info::Union{Nothing, PL_thread_info{T}}, prop::term_t
)::Bool where {T}
    class = info === nothing ? _query_gd(ld).thread.main_class : info.class
    class === nothing && return false
    return PL_unify_atom(ld, prop, mk_sym(T, class))
end

# ORIGINAL: the call `(*p->function)(info, arg)` of thread_property/2: the property function number `p` of `THREAD_PROPERTY_NAMES`.
"Call the property function number `p` on the thread `info` and the argument `arg`."
function _tprop_call(
    gd::PL_global_data{T}, ld::PL_local_data{T}, p::Int,
    info::Union{Nothing, PL_thread_info{T}}, arg::term_t
)::Bool where {T}
    p == 1 && return thread_id_property(ld, info, arg)
    p == 2 && return thread_alias_property(gd, ld, info, arg)
    p == 3 && return thread_status_property(gd, ld, info, arg)
    p == 4 && return thread_detached_property(ld, info, arg)
    p == 5 && return thread_debug_property(ld, info, arg)
    p == 6 && return thread_debug_mode_property(ld, info, arg)
    p == 7 && return thread_engine_property(ld, info, arg)
    p == 8 && return thread_thread_property(gd, ld, info, arg)
    p == 9 && return thread_tid_property(ld, info, arg)
    p == 10 && return thread_size_property(ld, info, arg)
    return thread_class_property(ld, info, arg)
end

# ORIGINAL: `tprop_enum` as one integer, the `PL_retry` context: tid (bits 0-23), the property number (24-39), `enum_threads` (bit 40) and
# `enum_properties` (bit 41).
_tprop_pack(tid::Int, p::Int, enum_threads::Bool, enum_properties::Bool)::Int =
    tid | (p << 24) | (Int(enum_threads) << 40) | (Int(enum_properties) << 41)

# PORT: pl-thread.c advance_state as tprop_advance_state
# DIVERGES: the state is the tuple `(tid, p, enum_threads, enum_properties)`, returned advanced with the success flag first; a slot
# whose engine was destroyed (`nothing`) is skipped as upstream skips the status UNUSED and RESERVED.
"Advance the enumeration of thread_property/2 to its next property or thread; false when there is none (pl-thread.c)."
function tprop_advance_state(
    gd::PL_global_data{T}, tid::Int, p::Int, enum_threads::Bool, enum_properties::Bool
)::Tuple{Bool, Int, Int} where {T}
    if enum_properties
        p += 1
        p <= length(THREAD_PROPERTY_NAMES) && return (true, tid, p)
        p = 1
    end
    if enum_threads
        while true
            tid += 1
            tid > gd.thread.highest_id && return (false, tid, p)
            _thread_slot_valid(gd, tid) && break
        end
        return (true, tid, p)
    end
    return (false, tid, p)
end

# PORT: pl-thread.c thread_property
# (PRED_IMPL("thread_property", 2, thread_property, PL_FA_NONDETERMINISTIC), pl-thread.c:3404-3512 at the pin; NDET|PL_FA_ISO, :8849)
# DIVERGES: see the section head (the state is the retry integer); the main thread is a record `nothing`.
"`thread_property(?Thread, ?Property)`: the properties of the threads and engines, on backtracking (pl-thread.c)."
function pl_thread_property(
    ld::PL_local_data{T}, thread::term_t, property::term_t, ctx::control_t{T}
)::foreign_t where {T}
    ctl = PL_foreign_control(ctx)
    gd = _query_gd(ld)
    tid = 0
    p = 1
    enum_threads = false
    enum_properties = false

    if ctl == FRG_FIRST_CALL
        if PL_is_variable(ld, thread)
            rc, idx = get_prop_def(ld, property, :thread_property, THREAD_PROPERTY_NAMES)
            rc == -1 && return FFALSE
            tid = 1
            enum_threads = true
            if rc == 1
                p = idx
            else
                enum_properties = true
            end
        else
            tid = get_thread(gd, ld, thread, true)
            tid == 0 && return FFALSE
            rc, idx = get_prop_def(ld, property, :thread_property, THREAD_PROPERTY_NAMES)
            rc == -1 && return FFALSE
            if rc == 1
                p = idx
            else
                enum_properties = true
            end
        end
    elseif ctl == FRG_REDO
        c = PL_foreign_context(ctx)
        tid = c & 0xffffff
        p = (c >> 24) & 0xffff
        enum_threads = ((c >> 40) & 1) != 0
        enum_properties = ((c >> 41) & 1) != 0
    else
        return FTRUE                                        # FRG_CUTTED: the state is an integer, nothing to free
    end

    arg = PL_new_term_ref(ld)
    enum_properties || _PL_get_arg(ld, 1, property, arg)

    while true
        info = tid == 1 ? nothing : gd.thread.infos[tid]
        if _thread_slot_valid(gd, tid) && _tprop_call(gd, ld, p, info, arg)
            if enum_properties
                a2 = PL_new_term_ref(ld)                    # PL_unify_term(property, PL_FUNCTOR, f, PL_TERM, arg)
                PL_unify_functor(ld, property, mk_sym(T, THREAD_PROPERTY_NAMES[p]), 1) &&
                    _PL_get_arg(ld, 1, property, a2) && PL_unify(ld, a2, arg) ||
                    return FFALSE
            end
            if enum_threads
                unify_thread_id(gd, ld, thread, info) || return FFALSE
            end

            more, tid, p = tprop_advance_state(gd, tid, p, enum_threads, enum_properties)
            more && return PL_retry(_tprop_pack(tid, p, enum_threads, enum_properties))
            return FTRUE
        end

        more, tid, p = tprop_advance_state(gd, tid, p, enum_threads, enum_properties)
        more || return FFALSE
    end
end

# ---- THREAD OPERATIONS: is_thread/1, thread_join/2, thread_detach/1, set_thread/2, debug_reset_from_class/0 (TH1, pl-thread.c at 18168e62) ----
# The threads are the main thread (id 1, a record `nothing`: its detached, debug and class are `main_detached`, `main_debug` and
# `main_class` of `gd.thread`) and the engines (`gd.thread.infos`); `get_thread` gives the id, `_thread_info_of` the record.

# ORIGINAL: the test of an atom against a name, `name == ATOM_xxx`.
"Whether the atom `a` is the text atom `s`."
@inline _thr_is(a::T, s::Symbol) where {T} = sym_key(a) == sym_key(mk_sym(T, s))

# ORIGINAL: `GD->thread.threads[tid]`, on the kernel's table: the main thread (id 1) has no record.
"The record of the thread `tid` (a valid id), `nothing` for the main thread."
function _thread_info_of(
    gd::PL_global_data{T}, tid::Int
)::Union{Nothing, PL_thread_info{T}} where {T}
    return tid == 1 ? nothing : gd.thread.infos[tid]
end

# ORIGINAL: `info->thread_data`, which the main thread has upstream and the kernel does not keep (only the calling main thread's own `ld`).
"The local data of the thread `info` (`nothing` = the main thread), `nothing` when the kernel cannot reach it (the main thread, from an engine)."
function _thread_ld(
    ld::PL_local_data{T}, info::Union{Nothing, PL_thread_info{T}}
)::Union{Nothing, PL_local_data{T}} where {T}
    if info === nothing
        return ld.thread_info === nothing ? ld : nothing
    end
    tld = info.thread_data
    return tld === nothing ? nothing : tld::PL_local_data{T}
end

# PORT: pl-thread.c debug_thread_class
# DIVERGES: `$debug_thread_class/4`, the only writer of `GD->thread.debug_classes`, is not ported, so the table is always empty and no
# class is a debug class.
"Whether the thread class `class` is a debug class (pl-thread.c)."
debug_thread_class(::PL_global_data{T}, ::Symbol)::Bool where {T} = false

# PORT: pl-thread.c update_debug_mode_from_class
# DIVERGES: the local data's thread is read from `ld.thread_info` (`nothing`: the main thread, whose class is `main_class`).
"Set the debug mode of the engine `ld` from the debug class of its thread, when it has a class (pl-thread.c)."
function update_debug_mode_from_class!(
    ld::PL_local_data{T}, old::Union{Nothing, Base.RefValue{Bool}}
)::Bool where {T}
    gd = _query_gd(ld)
    info = ld.thread_info
    class = info === nothing ? gd.thread.main_class : info.class
    class === nothing && return false
    return debugmode(ld, debug_thread_class(gd, class), old, UInt32(0))
end

# PORT: pl-thread.c is_thread
# (PRED_IMPL("is_thread", 1, is_thread, 0), pl-thread.c:3514 at the pin)
"`is_thread(@Thread)`: whether `Thread` names a thread: an alias, a handle or a number (pl-thread.c)."
function pl_is_thread(ld::PL_local_data{T}, A1::term_t)::foreign_t where {T}
    return get_thread(_query_gd(ld), ld, A1, false) != 0 ? FTRUE : FFALSE
end

# PORT: pl-thread.c thread_join
# (PRED_IMPL("thread_join", 2, thread_join, 0), pl-thread.c:2913-2987 at the pin)
# DIVERGES: the kernel runs no OS thread, so a thread that can be joined (`pthread_join`) does not exist but for the main thread, joined from
# an engine: that is refused by name, owner TH1. `joining_by` (a thread being joined) has no twin, the message "Already being joined" cannot
# occur. A detached thread (every engine is, as is the main thread after `thread_detach/1`) and the thread itself raise upstream's error.
"`thread_join(+Thread, -Status)`: the permission errors of a thread that cannot be joined; joining the main thread from an engine is refused (pl-thread.c)."
function pl_thread_join(ld::PL_local_data{T}, A1::term_t, A2::term_t)::foreign_t where {T}
    gd = _query_gd(ld)
    tid = get_thread(gd, ld, A1, true)
    tid == 0 && return FFALSE
    info = _thread_info_of(gd, tid)
    detached = info === nothing ? gd.thread.main_detached : info.detached
    if info === ld.thread_info || detached
        return PL_error(
            ld, "thread_join", 2,
            detached ? "Cannot join detached thread" : "Cannot join self",
            ERR_PERMISSION, mk_sym(T, :join), mk_sym(T, :thread), A1
        ) ? FTRUE : FFALSE
    end
    throw(
        NotPortedError{T}(
            mk_sym(T, :thread_join), "thread_join/2: joining the main thread from an engine",
            "TH1"
        )
    )
end

# PORT: pl-thread.c thread_detach
# (PRED_IMPL("thread_detach", 1, thread_detach, 0), pl-thread.c:2989-3026 at the pin; PRED_DEF flags ISO)
# DIVERGES: no `joining_by` (nothing joins a thread here, "Thread is being joined" cannot occur) and no `pthread_detach`, which cannot fail:
# the flag is set (the main thread's is `main_detached`).
"`thread_detach(+Thread)`: mark the thread detached; the errors of `get_thread` (pl-thread.c)."
function pl_thread_detach(ld::PL_local_data{T}, A1::term_t)::foreign_t where {T}
    gd = _query_gd(ld)
    tid = get_thread(gd, ld, A1, true)
    tid == 0 && return FFALSE
    info = _thread_info_of(gd, tid)
    if info === nothing
        gd.thread.main_detached = true
    else
        info.detached = true
    end
    return FTRUE
end

# PORT: pl-thread.c set_thread
# (PRED_IMPL("set_thread", 2, set_thread, 0), pl-thread.c:3049-3103 at the pin)
# DIVERGES: the main thread is a record `nothing` (its debug and class are `main_debug`, `main_class`); its local data is reachable only from
# the main thread itself, so `class(C)` (when the class changes) and `debug_mode(B)` of the main thread from an engine are refused by name,
# owner TH1, as is a class that is a blob atom (`info.class` is a `Symbol`). `alias(A)` calls `aliasThread` on the CALLING thread, as upstream does.
"`set_thread(+Thread, +Property)`: set `alias(A)`, `debug(B)`, `debug_mode(B)` or `class(C)` of the thread (pl-thread.c)."
function pl_set_thread(ld::PL_local_data{T}, A1::term_t, A2::term_t)::foreign_t where {T}
    gd = _query_gd(ld)
    info::Union{Nothing, PL_thread_info{T}} = nothing
    a = PL_get_atom(ld, A1)
    if a !== nothing && _thr_is(a, :self)
        info = ld.thread_info
    else
        tid = get_thread(gd, ld, A1, true)
        tid == 0 && return FFALSE
        info = _thread_info_of(gd, tid)
    end

    na = PL_get_name_arity(ld, A2)
    if na !== nothing && na[2] == 1
        name = na[1]
        arg = PL_new_term_ref(ld)
        _PL_get_arg(ld, 1, A2, arg)

        if _thr_is(name, :alias)
            alias = PL_get_atom_ex(ld, arg)
            alias === nothing && return FFALSE
            cur = info === nothing ? gd.thread.handles[1].alias : symbol_alias(gd, info.symbol)
            if cur !== nothing                              # info->symbol && symbol_alias(info->symbol)
                return PL_error(
                    ld, "", 0, "", ERR_PERMISSION, mk_sym(T, Symbol("re-alias")),
                    mk_sym(T, :thread), A1
                ) ? FTRUE : FFALSE
            end
            return aliasThread!(gd, ld, ld.thread_info, mk_sym(T, :thread), alias) ? FTRUE :
                   FFALSE
        elseif _thr_is(name, :debug)
            val = PL_get_bool_ex(ld, arg)
            val === nothing && return FFALSE
            if info === nothing
                gd.thread.main_debug = val
            else
                info.debug = val
            end
            return FTRUE
        elseif _thr_is(name, :debug_mode)
            val = PL_get_stdbool_ex(ld, arg)
            val === nothing && return FFALSE
            tld = _thread_ld(ld, info)
            tld === nothing && throw(
                NotPortedError{T}(
                    mk_sym(T, :set_thread), "set_thread/2: debug_mode(Bool) of the main thread from an engine",
                    "TH1"
                )
            )
            return debugmode(tld, val, nothing, UInt32(0)) ? FTRUE : FFALSE
        elseif _thr_is(name, :class)
            c = PL_get_atom_ex(ld, arg)
            c === nothing && return FFALSE
            is_blob(c) && throw(
                NotPortedError{T}(
                    mk_sym(T, :set_thread), "set_thread/2: class(Class) with a blob atom", "TH1"
                )
            )
            cls = Symbol(sym_text(c))
            cur = info === nothing ? gd.thread.main_class : info.class
            if cur !== cls                                  # set_thread_class
                tld = _thread_ld(ld, info)
                tld === nothing && throw(
                    NotPortedError{T}(
                        mk_sym(T, :set_thread), "set_thread/2: class(Class) of the main thread from an engine",
                        "TH1"
                    )
                )
                if info === nothing
                    gd.thread.main_class = cls
                else
                    info.class = cls
                end
                update_debug_mode_from_class!(tld, nothing)
            end
            return FTRUE
        else
            return PL_domain_error(ld, "thread_property", A2) ? FTRUE : FFALSE
        end
    end
    return PL_type_error(ld, "property", A2) ? FTRUE : FFALSE
end

# PORT: pl-thread.c debug_reset_from_class
# (PRED_IMPL("debug_reset_from_class", 0, debug_reset_from_class, 0), pl-thread.c:3145-3150 at the pin)
"`debug_reset_from_class`: set the debug mode of the calling thread from its class (pl-thread.c)."
function pl_debug_reset_from_class0(ld::PL_local_data{T})::foreign_t where {T}
    update_debug_mode_from_class!(ld, nothing)
    return FTRUE
end

# PORT: pl-thread.c gc_wait
# (PRED_IMPL("$gc_wait", 1, gc_wait, 0), pl-thread.c:7299-7324 at the pin)
# DIVERGES (TH1): the predicate is the loop of the GC thread (boot/gc.pl `gc_loop`): it blocks on `GD->thread.gc.cond` until a request
# (`GD->thread.gc.requests`: the GCREQUEST_ bits) is posted by `signalGCThreadCond`, then unifies A1 with the action it asks for
# (`garbage_collect_atoms` or `garbage_collect_clauses`, or the stop request). The kernel has no GC thread, no request word and nothing that posts a request,
# so the call would block for ever: it is refused by name.
"`'\$gc_wait'(-Action)`: wait for the GC thread's next request (pl-thread.c); the kernel has no GC thread: a named refusal."
function pl_gc_wait(ld::PL_local_data{T}, A1::term_t)::foreign_t where {T}
    throw(
        NotPortedError{T}(
            mk_sym(T, Symbol("\$gc_wait")), "gc_wait/1: blocks for the GC thread (none)", "TH1"
        )
    )
end

# PORT: pl-thread.c gc_clear
# (PRED_IMPL("$gc_clear", 1, gc_clear, 0), pl-thread.c:7327-7347 at the pin)
# DIVERGES (TH1): the C clears the request bit (`GD->thread.gc.requests &= ~mask`, under `GD->thread.gc.mutex`); the kernel has no GC
# thread and no request word, so there is no bit to clear: after the argument checks (an atom, `garbage_collect_atoms` or
# `garbage_collect_clauses`) the predicate succeeds.
"`'\$gc_clear'(+Action)`: clear the GC thread's pending request `Action` (pl-thread.c); no request exists here, so it only checks `Action`."
function pl_gc_clear(ld::PL_local_data{T}, A1::term_t)::foreign_t where {T}
    a = PL_get_atom_ex(ld, A1)
    a === nothing && return FFALSE
    act = Symbol(sym_text(a))
    if act !== :garbage_collect_atoms && act !== :garbage_collect_clauses
        PL_domain_error(ld, "action", A1)
        return FFALSE
    end
    return FTRUE
end

# PORT: pl-thread.c gc_stop
# (PRED_IMPL("$gc_stop", 0, gc_stop, 0), pl-thread.c:7359-7366 at the pin: `if ( (tid=gc_running()) ) return cancelGCThread(tid) != ...; return false;`)
# DIVERGES (TH1): `gc_running()` (pl-thread.c:7283-7292) is the id of a GC thread whose status is PL_THREAD_RUNNING; the kernel never starts
# one (`GCthread()`, :7227), so there is nothing to cancel: the predicate fails, as it does in swipl while no GC thread has been started.
"`'\$gc_stop'`: stop the GC thread if one runs (pl-thread.c); the kernel has none: fails."
function pl_gc_stop(ld::PL_local_data{T})::foreign_t where {T}
    return FFALSE
end
