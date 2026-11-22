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
    bytes = _thread_bytes(th.serial)
    w, _ = lookupBlob(gd.atoms, bytes, length(bytes), thread_blob)    # lookupBlob((char*)&ref, sizeof(ref), &thread_blob, &new)
    th.symbol = _blob_term!(gd.atoms, gd.atom_symbols, T, w)
    info.symbol = th.symbol
    return th
end

# PORT: pl-thread.c unify_thread_id
# DIVERGES: the database is an argument; `nothing` for the info is the main thread, which has no record here and answers its alias `main`.
# The `PL_unify_integer(id, info->pl_tid)` branch ("during destruction") cannot be reached: `create_thread_handle` does not fail.
"Unify `id` with the identifier of the thread `info`: its alias, else its blob (pl-thread.c)."
function unify_thread_id(
    gd::PL_global_data{T}, ld::PL_local_data{T}, id::term_t,
    info::Union{Nothing, PL_thread_info{T}}
)::Bool where {T}
    info === nothing && return PL_unify_atom(ld, id, mk_sym(T, :main))
    th = create_thread_handle(gd, info)
    name = th.alias !== nothing ? th.alias : th.symbol
    return PL_unify_atom(ld, id, name::T)
end

# PORT: pl-thread.c aliasThread
# DIVERGES: the thread is its record `info` (upstream: the id `tid`, looked up in `GD->threads`) and the database is an argument; the
# message queues have no table (`queueTable` is NULL: no queue exists), so only a thread name can be taken. `PL_register_atom` does not
# exist (no atom GC). A taken name raises `permission_error(create, Type, Name)` with the message "Alias name already taken".
"Give the thread `info` the alias `name`; false (the error raised) when the name is taken (pl-thread.c)."
function aliasThread!(
    gd::PL_global_data{T}, ld::PL_local_data{T}, info::PL_thread_info{T}, type::T, name::T
)::Bool where {T}
    if haskey(gd.thread.thread_table, sym_key(name))
        obj = PL_new_term_ref(ld)
        PL_put_atom(ld, obj, name)
        return PL_error(
            ld, "", 0, "Alias name already taken", ERR_PERMISSION, mk_sym(T, :create),
            type, obj
        )
    end
    th = create_thread_handle(gd, info)
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
# `copy_local_data!`); there is no pthread, no `PL_set_engine` (the local data is an argument everywhere) and no `$thread_init`
# (pl-thread.c:7006: the hook runs the thread initialisation goals and the thread events, owner TH1: the event table). The thread ids
# count up from 2 and are never reused (upstream reuses a free slot). NOT PORTED: the creator's `inherit_from`.
"A new engine, created from `ld`, whose stacks may grow to `stack_limit` positions (pl-thread.c `PL_create_engine`)."
function _create_engine(
    gd::PL_global_data{T}, ld::PL_local_data{T}, stack_limit::Int
)::PL_local_data{T} where {T}
    eld = _bare_local_data(gd)
    gd.thread.highest_id += 1
    info = PL_thread_info{T}(
        gd.thread.highest_id, 1, false, true, false, false, stack_limit, PL_THREAD_RUNNING,
        eld, nothing, :user
    )
    push!(gd.thread.infos, info)                    # index = pl_tid
    eld.thread_info = info
    copy_local_data!(eld, ld, info)
    return eld
end

# PORT: pl-thread.c PL_thread_destroy_engine as _destroy_engine!
# DIVERGES: the engine is the handle's (`PL_destroy_engine(th->info->thread_data)` and `PL_thread_destroy_engine()` of the current
# engine are one function here: there is no current engine to compare with); `free_prolog_thread` is the status `EXITED`, the thread
# record dropped from `gd.thread.infos` and from the handle. NOT PORTED: the `thread_exit`/`this_thread_exit` events and the
# `at_thread_exit` goals it runs (owner TH1: the event table).
"Leave the engine of the handle `th`: the last user ends it (pl-thread.c)."
function _destroy_engine!(gd::PL_global_data{T}, th::thread_handle{T})::Nothing where {T}
    info = th.info::PL_thread_info{T}
    info.open_count -= 1
    if info.open_count == 0
        info.status = PL_THREAD_EXITED
        info.thread_data = nothing
        info.has_tid = false
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
