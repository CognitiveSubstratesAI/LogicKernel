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
