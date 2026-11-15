# UPSTREAM: swipl-devel src/pl-thread.c @ 18168e629eab
# UPSTREAM: swipl-devel src/pl-thread.h @ 18168e629eab
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
# calling thread, which statistics/2 reads.
# Since TH1-B the lock table: the L_* mutexes of the database (`new_PL_mutexes`), `PL_LOCK`/`PL_UNLOCK` (pl-thread.h),
# `holdsLock` and `enableThreads`; no call site takes a lock yet (the sites are placed by TH1-C).

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
    gen = current_generation(gd, def)
    while gen != current_generation(gd, def)        # do … while(): no other thread can move it
        gen = current_generation(gd, def)
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

# PORT: pl-thread.c pl_thread_self
# (FRG("thread_self", 1, pl_thread_self, ISO), pl-ext.c:186; pl-thread.c:2662-2672 `unify_thread_id`,
# 2759-2763 `pl_thread_self` at the pin: `return unify_thread_id(self, LD->thread.info);`)
# DIVERGES: the kernel runs one thread, the main thread, and has no thread table: `unify_thread_id`
# would unify `th->alias`, which is `main` for the main thread (swipl 10.1.19: `thread_self(X)` gives
# `X = main`), so the single-thread form unifies `main`. NOT PORTED: the thread handle blob
# (`create_thread_handle`) of a thread without an alias, and `PL_unify_integer(id, info->pl_tid)`.
"`thread_self(-Thread)`: the identifier of the calling thread; here always `main` (pl-thread.c)."
function pl_thread_self(ld::PL_local_data{T}, self::term_t)::foreign_t where {T}
    return PL_unify_atom(ld, self, mk_sym(T, :main)) ? FTRUE : FFALSE
end

# PORT: pl-thread.c _PL_mutexes as new_PL_mutexes
# (pl-thread.c:302-337 at the pin: 30 `COUNT_MUTEX_INITIALIZER` entries, ids 0-29 of pl-thread.h:242-271)
# DIVERGES (TH1-B, representation only): upstream's table is one process-wide array; the kernel has one table per database,
# in `gd.mutexes`, because a database is a value and module-level mutable state is refused (tools/lint_globals.jl). A copy of the
# database gets its own unlocked table (`Base.deepcopy_internal` of `counting_mutex`, src/pl-incl.jl). The Windows-only L_DDE
# and L_CSTACK are left out.
"The lock table of a new database: one unlocked `counting_mutex` per L_* id, in upstream's order (pl-thread.c `_PL_mutexes[]`); entry `id + 1` is `L_*`."
function new_PL_mutexes()::Vector{counting_mutex}
    names = (
        "L_MISC", "L_ALLOC", "L_REHASH_ATOMS", "L_FLAG", "L_FUNCTOR", "L_RECORD",
        "L_THREAD", "L_MUTEX", "L_PREDICATE", "L_MODULE", "L_SRCFILE", "L_TABLE",
        "L_BREAK", "L_FILE", "L_SEETELL", "L_PLFLAG", "L_OP", "L_INIT", "L_TERM",
        "L_FOREIGN", "L_OS", "L_LOCALE", "L_SORTR", "L_UMUTEX", "L_INIT_ATOMS",
        "L_CGCGEN", "L_EVHOOK", "L_OSDIR", "L_ALERT", "L_GENERATION"
    )
    return counting_mutex[counting_mutex(n) for n in names]
end

# PORT: pl-thread.h countingMutexLock
# (pl-thread.h:288-302 at the pin, the O_CONTENTION_STATISTICS branch)
# DIVERGES (TH1-B): the mutex is a `ReentrantLock` where upstream's is a non-recursive pthread mutex, so a task that locks a
# mutex it holds would wait for itself; the kernel raises an error instead (`owner` is the holding task).
"Take `cm`: count a collision when it is held, wait for it, then count the lock (pl-thread.h)."
function countingMutexLock(cm::counting_mutex)::Nothing
    me = current_task()
    (@atomic cm.owner) === me &&
        error("countingMutexLock: $(cm.name) is locked by this task already")
    if !trylock(cm.mutex)
        cm.collisions += UInt32(1)
        lock(cm.mutex)
    end
    cm.count += UInt64(1)
    cm.lock_count += UInt32(1)
    @atomic cm.owner = me
    return nothing
end

# PORT: pl-thread.h countingMutexUnlock
# (pl-thread.h:304-309 at the pin)
"Release `cm`; it requires an open hold (`lock_count > 0`) (pl-thread.h)."
function countingMutexUnlock(cm::counting_mutex)::Nothing
    @assert cm.lock_count > 0 "countingMutexUnlock: $(cm.name) is not locked"
    cm.lock_count -= UInt32(1)
    @atomic cm.owner = nothing
    unlock(cm.mutex)
    return nothing
end

# PORT: pl-thread.h PL_LOCK
# (pl-thread.h:325 at the pin: `IF_MT(id, countingMutexLock(&_PL_mutexes[id]))`; `IF_MT` is
# `if ( id == L_THREAD || GD->thread.enabled ) g`, pl-thread.h:286)
# DIVERGES (TH1-B): a function of the database and the id (upstream: a macro over the global GD and `_PL_mutexes`).
"`PL_LOCK(id)`: take the L_* mutex `id` while threads are enabled; L_THREAD is always taken (pl-thread.h)."
function PL_LOCK(gd::PL_global_data, id::Int)::Nothing
    (id == L_THREAD || gd.thread_enabled) && countingMutexLock(gd.mutexes[id + 1])
    return nothing
end

# PORT: pl-thread.h PL_UNLOCK
# (pl-thread.h:326 at the pin)
"`PL_UNLOCK(id)`: release the L_* mutex `id` under the same condition as `PL_LOCK` (pl-thread.h)."
function PL_UNLOCK(gd::PL_global_data, id::Int)::Nothing
    (id == L_THREAD || gd.thread_enabled) && countingMutexUnlock(gd.mutexes[id + 1])
    return nothing
end

# PORT: pl-thread.h holdsLock
# (pl-thread.h:336-340 at the pin)
# The table is the database's (see `new_PL_mutexes`); as upstream, the answer is true when any owner holds it (`lock_count > 0`).
"Is the L_* mutex `id` held, by any owner? (pl-thread.h `holdsLock`, meant for assertions)"
function holdsLock(gd::PL_global_data, id::Int)::Bool
    return gd.mutexes[id + 1].lock_count > 0
end

# PORT: pl-thread.c enableThreads
# (pl-thread.c:606-634 at the pin)
# DIVERGES (TH1-B): takes the engine `ld` (upstream reads the global GD and calls `PL_error(NULL, ...)` on the calling thread's
# LD); the database is the running query's (`_query_gd`).
"""
    enableThreads(ld, enable) -> Bool

Enable or disable threads at run time (pl-thread.c): enabling always succeeds; disabling holds L_THREAD and succeeds
when one thread is alive (`threads_created - threads_finished == 1`), else raises `permission_error(modify, flag, threads)`.
"""
function enableThreads(ld::PL_local_data{T}, enable::Bool)::Bool where {T}
    gd = _query_gd(ld)
    if enable
        gd.thread_enabled = true                        # print system message?
    else
        PL_LOCK(gd, L_THREAD)
        if gd.statistics_threads_created - gd.statistics_threads_finished == 1  # I am alone :-(
            gd.thread_enabled = false
        else
            key = PL_new_term_ref(ld)
            PL_put_atom(ld, key, mk_sym(T, :threads))
            PL_UNLOCK(gd, L_THREAD)
            return PL_error(
                ld, "", 0, "Active threads", ERR_PERMISSION, mk_sym(T, :modify),
                mk_sym(T, :flag), key
            )
        end
        PL_UNLOCK(gd, L_THREAD)
    end
    return true
end
