# UPSTREAM: swipl-devel src/pl-mutex.c @ 18168e629eab
# CLASS: code
# COPYRIGHT: Copyright (c)  2017-2023, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# PORTED FROM pl-mutex.c: the user mutexes and their eight predicates (`BeginPredDefs(mutex)`, pl-mutex.c:785-796):
# mutex_create/1,2, mutex_destroy/1, mutex_lock/1, mutex_trylock/1, mutex_unlock/1, mutex_unlock_all/0 and
# mutex_property/2, over the mutex table of the database (`gd.mutexes`, upstream `GD->thread.mutexTable`), and
# `with_mutex/2` in the form pl-mutex.c itself has for a build without threads (the `#else` of `#ifdef O_PLMT`,
# pl-mutex.c:768-772; its own step ports the `O_PLMT` branch).
#
# THE ONE-THREAD FORM (MUTEX; DIVERGES for the whole file): the kernel runs one thread, `main` (thread id 1,
# `PL_thread_self()`), so a mutex needs no `pthread_mutex_t`: its lock is the pair `owner`/`count` alone (owner
# 0: none, 1: the main thread), a lock another thread holds cannot arise (no `pthread_mutex_timedlock` loop, no
# `PL_handle_signals`), and `owner != 0 && owner != self`, the "not owner" branch of mutex_unlock/1, is not reached.
# An anonymous mutex is a blob of type `mutex` (`PL_BLOB_UNIQUE`) whose payload is the mutex's creation number (upstream:
# the pointer), and it is never reclaimed by a garbage collector (the kernel has no atom GC; upstream
# `PL_unregister_atom` makes the blob reclaimable and `release_mutexref` drops the mutex): it leaves the table with
# mutex_destroy/1. The blob prints as every blob does (`PL_blob_t` has no `write` slot: upstream `<mutex>(0x...)`
# prints the pointer too). The mutexes are enumerated in creation order (upstream: hash order). UPSTREAM ONLY:
# `release_mutexref`, `save_mutexref`, `load_mutexref` (no GC finalizer, no saved states), `destroy_mutex` and
# `unalloc_mutex` (nothing is allocated by hand), `initMutexRef` (the blob type is registered by `lookupBlob`).

# PORT: pl-mutex.c mutex_blob
# DIVERGES: no `release`, `write`, `acquire`, `save` or `load` slots (`PL_blob_t` has none): see the file header.
"The blob type of an anonymous mutex (pl-mutex.c `mutex_blob`): unique by payload, non-text, named `mutex`."
const mutex_blob = PL_blob_t(PL_BLOB_UNIQUE, "mutex")

# DIVERGES: pl-mutex.c:573-577 `mprop_list`: the two properties of `mutex_property/2` in upstream's order; the entry's
# number (1, 2) is what `mprop_enum.p` points at.
const _MUTEX_PROPERTIES = (:alias, :status)

# ORIGINAL (MUTEX): the payload of an anonymous mutex's blob (upstream: the bytes of the `mutexref`).
"The 8 bytes of a mutex blob: the mutex's creation number, little-endian."
_mutex_bytes(serial::Int)::Vector{UInt8} = collect(reinterpret(UInt8, Int64[serial]))

# PORT: pl-mutex.c unify_mutex
"Unify `t` with the identifier of the mutex `m`: its name or its blob (pl-mutex.c)."
function unify_mutex(ld::PL_local_data{T}, t::term_t, m::pl_mutex{T})::Bool where {T}
    PL_unify_atom(ld, t, m.id)
end

# PORT: pl-mutex.c unify_mutex_owner
# DIVERGES: `unify_thread_id(t, GD->thread.threads[owner])` of the one thread, the main thread: its alias (`main_thread_alias`).
"Unify `t` with the thread that owns a mutex: the main thread's alias, or `[]` when `owner` is 0 (pl-mutex.c)."
function unify_mutex_owner(ld::PL_local_data{T}, t::term_t, owner::Int)::Bool where {T}
    owner != 0 && return PL_unify_atom(ld, t, main_thread_alias(_query_gd(ld)))
    return PL_unify_nil(ld, t)
end

# PORT: pl-mutex.c mutexCreate
# DIVERGES: the mutex is a record in `gd.mutexes` keyed by the `sym_key` of its id; `serial` numbers every mutex (see the file
# header); `PL_unregister_atom`/`PL_register_atom` (reclaiming an anonymous mutex on GC, locking a name) are dropped:
# the kernel has no atom GC. The blob is made as `unify_closure`'s (src/pl-wrap.jl): a payload of the creation number.
"Make a mutex named `name` (`nothing`: an anonymous mutex, a blob) and enter it in the table (pl-mutex.c)."
function mutexCreate(ld::PL_local_data{T}, name::Union{Nothing, T})::pl_mutex{T} where {T}
    gd = _query_gd(ld)
    gd.mutex_serial += 1
    serial = gd.mutex_serial
    if name === nothing
        bytes = _mutex_bytes(serial)
        w, _ = lookupBlob(gd.atoms, bytes, length(bytes), mutex_blob)   # lookupBlob(&ref, sizeof(ref), &mutex_blob, &new)
        id = _blob_term!(gd.atoms, gd.atom_symbols, T, w)
        m = pl_mutex{T}(0, 0, id, serial, true, false, false)           # m->anonymous = true
    else
        m = pl_mutex{T}(0, 0, name, serial, false, false, false)        # m->id = name
    end
    gd.mutexes[sym_key(m.id)] = m                                       # addNewHTableWP(GD->thread.mutexTable, m->id, m)
    return m
end

# PORT: pl-mutex.c unlocked_pl_mutex_create
# DIVERGES: the mutex is `nothing` where upstream returns NULL; the entry is taken out of the table again when the final
# unify fails (upstream `destroy_mutex`, which keeps an anonymous mutex's memory for the GC; here nothing is left). `L_UMUTEX`
# is dropped: one thread.
"Create the mutex the term `mutex` names (a variable: an anonymous one) and unify it with `mutex`; `nothing` after an error (pl-mutex.c)."
function unlocked_pl_mutex_create(
    ld::PL_local_data{T}, mutex::term_t
)::Union{Nothing, pl_mutex{T}} where {T}
    gd = _query_gd(ld)
    name = PL_get_atom(ld, mutex)
    id::Union{Nothing, T} = nothing
    if name !== nothing
        if haskey(gd.mutexes, sym_key(name))                            # lookupHTableWP(GD->thread.mutexTable, name)
            PL_error(
                ld, "mutex_create", 1, "", ERR_PERMISSION, mk_sym(T, :create),
                mk_sym(T, :mutex), mutex
            )
            return nothing
        end
        id = name
    elseif PL_is_variable(ld, mutex)
        id = nothing
    else
        PL_error(ld, "mutex_create", 1, "", ERR_TYPE, mk_sym(T, :mutex), mutex)
        return nothing
    end

    m = mutexCreate(ld, id)
    if !unify_mutex(ld, mutex, m)
        delete!(gd.mutexes, sym_key(m.id))
        return nothing
    end
    return m
end

# PORT: pl-mutex.c mutex_create1
# (PRED_IMPL("mutex_create", 1, mutex_create1, 0))
"`mutex_create(?MutexId)`: create a mutex named by `MutexId`, or an anonymous one when it is unbound (pl-mutex.c)."
function pl_mutex_create1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return unlocked_pl_mutex_create(ld, PL__t0) === nothing ? FFALSE : FTRUE
end

# PORT: pl-mutex.c mutex_options
const _MUTEX_OPTIONS = (PL_option_t(:alias, OPT_ATOM),)

# PORT: pl-mutex.c mutex_create2
# (PRED_IMPL("mutex_create", 2, mutex_create2, 0); PRED_DEF flags `PL_FA_ISO`, pl-mutex.c:788)
"`mutex_create(-MutexId, +Options)`: as mutex_create/1, `alias(Name)` giving the name (pl-mutex.c)."
function pl_mutex_create2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    vals = PL_scan_options(ld, A2, 0, "mutex_option", _MUTEX_OPTIONS)
    vals === nothing && return FFALSE
    alias = _opt_atom(T, vals[1])

    if alias !== nothing
        if !PL_unify_atom(ld, A1, alias)
            return PL_error(ld, "mutex_create", 2, "", ERR_UNINSTANTIATION, 1, A1) ? FTRUE :
                FFALSE
        end
    end

    return unlocked_pl_mutex_create(ld, A1) === nothing ? FFALSE : FTRUE
end

# PORT: pl-mutex.c get_mutex
# DIVERGES: the mutex (or `nothing`, with the error raised) is the result where upstream writes `*mutex`; the table lookup of a
# mutex blob finds the mutex in `gd.mutexes` (upstream follows the pointer of the payload), and a destroyed one is no longer
# in the table: it raises the existence error as upstream's `m->destroyed` does. `L_UMUTEX` is dropped: one thread.
"The mutex the term `t` names, creating it when `create`; `nothing` after raising `type_error` or `existence_error` (pl-mutex.c)."
function get_mutex(
    ld::PL_local_data{T}, t::term_t, create::Bool
)::Union{Nothing, pl_mutex{T}} where {T}
    gd = _query_gd(ld)
    id::Union{Nothing, T} = nothing
    m::Union{Nothing, pl_mutex{T}} = nothing

    name = PL_get_atom(ld, t)
    if name !== nothing
        if is_blob(name) && atomValue(gd.atoms, blob_handle(name)).type === mutex_blob
            m = get(gd.mutexes, sym_key(name), nothing)             # m = ref->mutex
            if m === nothing
                PL_error(ld, ERR_EXISTENCE, mk_sym(T, :mutex), t)   # m->destroyed
            end
            return m
        elseif isTextAtom(name)
            id = name
        end
    end

    if id === nothing
        PL_error(ld, ERR_TYPE, mk_sym(T, :mutex), t)
        return nothing
    end

    m = get(gd.mutexes, sym_key(id), nothing)                       # lookupHTableWP(GD->thread.mutexTable, id)
    if m === nothing
        if create
            m = unlocked_pl_mutex_create(ld, t)
        else
            PL_error(ld, ERR_EXISTENCE, mk_sym(T, :mutex), t)
        end
    end
    return m
end

# PORT: pl-mutex.c PL_mutex_lock
# DIVERGES: no `pthread_mutex_timedlock`: no other thread holds the lock, so a lock that is not the caller's is free.
"Lock `m` for the main thread: one more for its owner, else the first (pl-mutex.c)."
function PL_mutex_lock(m::pl_mutex)::Bool
    if m.owner == 1                                     # self == m->owner
        m.count += 1
    else
        m.count = 1
        m.owner = 1
    end
    return true
end

# PORT: pl-mutex.c mutex_lock
# (PRED_IMPL("mutex_lock", 1, mutex_lock, 0); PRED_DEF flags `PL_FA_ISO`, pl-mutex.c:790)
"`mutex_lock(+MutexId)`: lock the mutex, creating it when it does not exist (pl-mutex.c)."
function pl_mutex_lock1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    m = get_mutex(ld, PL__t0, true)
    m === nothing && return FFALSE
    return PL_mutex_lock(m) ? FTRUE : FFALSE
end

# PORT: pl-mutex.c PL_mutex_trylock
# DIVERGES: `pthread_mutex_trylock` succeeds for a mutex nobody owns (`m.owner == 0`); the `EBUSY` branch, another
# thread's lock, cannot be reached with one thread.
"Lock `m` for the main thread when no other thread holds it; whether it did (pl-mutex.c)."
function PL_mutex_trylock(m::pl_mutex)::Bool
    if m.owner == 1                                     # self == m->owner
        m.count += 1
    elseif m.owner == 0                                 # pthread_mutex_trylock(&m->mutex) == 0
        m.count = 1
        m.owner = 1
    else
        return false                                    # EBUSY
    end
    return true
end

# PORT: pl-mutex.c mutex_trylock
# (PRED_IMPL("mutex_trylock", 1, mutex_trylock, 0); PRED_DEF flags `PL_FA_ISO`, pl-mutex.c:791)
"`mutex_trylock(+MutexId)`: lock the mutex when no other thread holds it, creating it when it does not exist (pl-mutex.c)."
function pl_mutex_trylock1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    m = get_mutex(ld, PL__t0, true)
    m === nothing && return FFALSE
    return PL_mutex_trylock(m) ? FTRUE : FFALSE
end

# PORT: pl-mutex.c PL_mutex_unlock
"Unlock `m` once when the main thread owns it; whether it does (pl-mutex.c)."
function PL_mutex_unlock(m::pl_mutex)::Bool
    if m.owner == 1                                     # self == m->owner
        m.count -= 1
        if m.count == 0
            m.owner = 0                                 # pthread_mutex_unlock(&m->mutex)
        end
        return true
    end
    return false
end

# PORT: pl-mutex.c try_really_destroy_mutex
# DIVERGES: `PL_unregister_atom` of a named mutex's atom, `pthread_mutex_unlock` and `destroy_mutex` are dropped
# (see the file header); the destroyed mutex is only taken out of the table.
"Destroy the mutex `m` when the main thread can lock it and holds no other lock on it; whether it was destroyed (pl-mutex.c)."
function try_really_destroy_mutex(ld::PL_local_data{T}, m::pl_mutex{T})::Bool where {T}
    if PL_mutex_trylock(m)
        if m.count == 1
            m.destroyed = true
            delete!(_query_gd(ld).mutexes, sym_key(m.id))   # deleteHTableWP(GD->thread.mutexTable, m->id)
            m.count = 0
            m.owner = 0
            return true
        else
            PL_mutex_unlock(m)
        end
    end
    return false
end

# PORT: pl-mutex.c mutex_unlock
# (PRED_IMPL("mutex_unlock", 1, mutex_unlock, 0); PRED_DEF flags `PL_FA_ISO`, pl-mutex.c:792)
# DIVERGES: `m->owner` is 0 whenever the unlock of the main thread fails, so the message is always "not locked"; "not owner"
# needs another thread's lock.
"`mutex_unlock(+MutexId)`: unlock the mutex once; a mutex asked to be destroyed goes when it is free (pl-mutex.c)."
function pl_mutex_unlock1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    m = get_mutex(ld, A1, false)
    m === nothing && return FFALSE

    if PL_mutex_unlock(m)
        if m.auto_destroy
            try_really_destroy_mutex(ld, m)
        end
        return FTRUE
    else
        msg = m.owner != 0 ? "not owner" : "not locked"
        return PL_error(
            ld, "mutex_unlock", 1, msg, ERR_PERMISSION, mk_sym(T, :unlock),
            mk_sym(T, :mutex), A1
        ) ? FTRUE : FFALSE
    end
end

# PORT: pl-mutex.c mutex_unlock_all
# (PRED_IMPL("mutex_unlock_all", 0, mutex_unlock_all, 0))
# DIVERGES: the table enumerator `newTableEnumWP`/`advanceTableEnum` is a loop over the values of the table.
"`mutex_unlock_all`: release every mutex the main thread holds, whatever its count (pl-mutex.c)."
function pl_mutex_unlock_all0_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    for m in values(_query_gd(ld).mutexes)
        if m.owner == 1                                 # m->owner == tid
            m.count = 0
            m.owner = 0
        end
    end
    return FTRUE
end

# PORT: pl-mutex.c mutex_destroy
# (PRED_IMPL("mutex_destroy", 1, mutex_destroy, 0); PRED_DEF flags `PL_FA_ISO`, pl-mutex.c:789)
"`mutex_destroy(+MutexId)`: destroy the mutex now, or when it is unlocked while it is held (pl-mutex.c)."
function pl_mutex_destroy1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    m = get_mutex(ld, PL__t0, false)
    m === nothing && return FFALSE

    if !try_really_destroy_mutex(ld, m)
        m.auto_destroy = true
    end
    return FTRUE
end

# PORT: pl-mutex.c mutex_alias_property, mutex_status_property
# DIVERGES: the two property functions are one function of the property's number (`mprop_list`, 1: alias, 2: status), as
# `thread_property_value` (src/pl-thread.jl) does for `tprop_list`.
"Unify `prop` with the argument of property number `p` of the mutex `m`: `alias(Name)` or `status(locked(By, Count) | unlocked)` (pl-mutex.c)."
function mutex_property_value(
    ld::PL_local_data{T}, m::pl_mutex{T}, p::Int, prop::term_t
)::Bool where {T}
    if p == 1                                           # mutex_alias_property
        return !m.anonymous && PL_unify_atom(ld, prop, m.id)
    end
    if m.owner != 0                                     # mutex_status_property
        by = PL_new_term_ref(ld)
        count = PL_new_term_ref(ld)
        return PL_unify_functor(ld, prop, mk_sym(T, :locked), 2) &&
            _PL_get_arg(ld, 1, prop, by) && _PL_get_arg(ld, 2, prop, count) &&
            PL_unify_integer(ld, count, m.count) && unify_mutex_owner(ld, by, m.owner)
    end
    return PL_unify_atom(ld, prop, mk_sym(T, :unlocked))
end

# PORT: pl-mutex.c advance_mstate
# DIVERGES: `state->p` is an index; the table enumerator `state->e` is the snapshot `mutexes` with its next index.
"Advance the enumeration of `mutex_property/2` to the next property, then the next mutex; false at the end (pl-mutex.c)."
function advance_mstate!(state::mutex_prop_enum)::Bool
    if state.enum_properties
        state.p += 1
        state.p <= length(_MUTEX_PROPERTIES) && return true
        state.p = 1                                     # state->p = mprop_list
    end
    state.enumerating && advance_mstate_table!(state) && return true    # state->e: the next mutex
    return false
end

# PORT: pl-mutex.c free_mstate
# DIVERGES: the record goes back to the pool (`freeForeignState`); it drops its references to the mutexes.
"Give the `mutex_property/2` state at pool index `idx` back (pl-mutex.c)."
function free_mstate!(pool::foreign_state_pool{mutex_prop_enum{T}}, idx::Int)::Nothing where {T}
    state = pool.states[idx]
    empty!(state.mutexes)
    state.m = nothing
    free_foreign_state!(pool, idx)
    return nothing
end

# PORT: pl-mutex.c mutex_property
# (PRED_IMPL("mutex_property", 2, mutex_property, PL_FA_NONDETERMINISTIC); PRED_DEF flags `NDET|PL_FA_ISO`, pl-mutex.c:794)
# DIVERGES: the state `mprop_enum` is a record of `ld.mutex_enums` from the first call on (upstream copies `statebuf` from
# the C stack on the first redo), its pool index the `REDO_PTR` context; the table enumerator is a snapshot of the mutexes in
# creation order (see the file header); every exit that leaves no redo returns the record (`free_mstate!`).
"`mutex_property(?MutexId, ?Property)`: `alias(Name)` and `status(locked(By, Count) | unlocked)` of a mutex, enumerating (pl-mutex.c)."
function pl_mutex_property2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    mutex, property = PL__t0, PL__t0 + 1
    pool = ld.mutex_enums
    idx = 0

    ctl = PL_foreign_control(PL__ctx)
    if ctl == FRG_FIRST_CALL
        if PL_is_variable(ld, mutex)
            rc, p = get_prop_def(ld, property, :mutex_property, _MUTEX_PROPERTIES)
            rc == -1 && return FFALSE
            idx = alloc_foreign_state!(pool)
            state = pool.states[idx]
            state.m = nothing
            state.next = 1
            state.enumerating = true                    # state->e = newTableEnumWP(GD->thread.mutexTable)
            empty!(state.mutexes)
            append!(state.mutexes, values(_query_gd(ld).mutexes))
            sort!(state.mutexes; by = x -> x.serial)
            if rc == 1
                state.p = p
                state.enum_properties = false
            else
                state.p = 1                             # state->p = mprop_list
                state.enum_properties = true
            end
        else
            m = get_mutex(ld, mutex, false)
            m === nothing && return FFALSE
            rc, p = get_prop_def(ld, property, :mutex_property, _MUTEX_PROPERTIES)
            rc == -1 && return FFALSE
            idx = alloc_foreign_state!(pool)
            state = pool.states[idx]
            state.m = m
            state.next = 1
            state.enumerating = false
            empty!(state.mutexes)
            if rc == 1
                state.p = p
                state.enum_properties = false
            else
                state.p = 1
                state.enum_properties = true
            end
        end
    elseif ctl == FRG_REDO
        idx = PL_foreign_context_address(PL__ctx)       # state = CTX_PTR
    else                                                # FRG_CUTTED
        free_mstate!(pool, PL_foreign_context_address(PL__ctx))
        return FTRUE
    end
    state = pool.states[idx]

    if state.m === nothing                              # first time, enumerating mutexes
        if !advance_mstate_table!(state)
            free_mstate!(pool, idx)
            return FFALSE
        end
    end

    arg = PL_new_term_ref(ld)
    state.enum_properties || _PL_get_arg(ld, 1, property, arg)

    while true
        m = state.m::pl_mutex{T}
        if mutex_property_value(ld, m, state.p, arg)
            if state.enum_properties
                tmp = _message_term(ld, _MUTEX_PROPERTIES[state.p], arg)
                if !PL_unify(ld, property, tmp)
                    free_mstate!(pool, idx)
                    return FFALSE
                end
            end
            if state.enumerating
                if !unify_mutex(ld, mutex, m)
                    free_mstate!(pool, idx)
                    return FFALSE
                end
            end

            advance_mstate!(state) && return PL_retry_address(idx)     # ForeignRedoPtr(state)

            free_mstate!(pool, idx)
            return FTRUE
        end

        if !advance_mstate!(state)
            free_mstate!(pool, idx)
            return FFALSE
        end
    end
end

# ORIGINAL (MUTEX): the first-time step of mutex_property/2, `advanceTableEnum(state->e, NULL, &tv)` (pl-mutex.c:677-689): the
# next mutex of the snapshot; false at its end.
"Take the next mutex of the enumeration's snapshot as the current one; false at its end."
function advance_mstate_table!(state::mutex_prop_enum)::Bool
    state.next <= length(state.mutexes) || return false
    state.m = state.mutexes[state.next]
    state.next += 1
    return true
end

# PORT: pl-mutex.c pl_with_mutex
# (FRG("with_mutex", 2, pl_with_mutex, META|ISO), pl-ext.c:187; the meta declaration `+0`, pl-ext.c:406;
# pl-mutex.c:758-773 at the pin. The `#else` branch:
#     rval = callProlog(NULL, goal, PL_Q_PASS_EXCEPTION, NULL);       pl-mutex.c:771)
# DIVERGES: swipl 10.1.19 is built with O_PLMT and runs `get_mutex(mutex, &m, true)`, which creates the
# mutex when `mutex` names none and raises on a term that is no mutex name, then locks and unlocks `m`
# around the call. The kernel takes upstream's own single-thread branch: `with_mutex(M, G)` is `once(G)`
# and `mutex` is not examined (its own step ports the `O_PLMT` branch over the table above). `NULL` for the
# module is `0`, as pl-pro.jl's `sig_atomic/1`.
"`with_mutex(+Mutex, :Goal)`: run `Goal` as once/1 while holding `Mutex`; here without a mutex (pl-mutex.c)."
function pl_with_mutex(
    ld::PL_local_data{T}, mutex::term_t, goal::term_t
)::foreign_t where {T}
    rval = callProlog(_query_gd(ld), ld, 0, goal, PL_Q_PASS_EXCEPTION)

    return rval ? FTRUE : FFALSE
end

# PORT: pl-mutex.c BeginPredDefs as PL_predicates_from_mutex
# (pl-mutex.c:785-796; the flags are those of the table: mutex_create/1 and mutex_unlock_all/0 none, mutex_create/2, destroy,
# lock, trylock and unlock `PL_FA_ISO`, mutex_property/2 `NDET|PL_FA_ISO`)
"pl-mutex.c's registration table (`BeginPredDefs(mutex)`)."
const PL_predicates_from_mutex = (
    PL_extension("mutex_create", 1, pl_mutex_create1_va, PL_FA_VARARGS),
    PL_extension("mutex_create", 2, pl_mutex_create2_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension("mutex_destroy", 1, pl_mutex_destroy1_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension("mutex_lock", 1, pl_mutex_lock1_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension("mutex_trylock", 1, pl_mutex_trylock1_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension("mutex_unlock", 1, pl_mutex_unlock1_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension("mutex_unlock_all", 0, pl_mutex_unlock_all0_va, PL_FA_VARARGS),
    PL_extension(
        "mutex_property", 2, pl_mutex_property2_va,
        PL_FA_NONDETERMINISTIC | PL_FA_ISO | PL_FA_VARARGS
    )
)
