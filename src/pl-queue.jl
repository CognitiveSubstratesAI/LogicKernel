# UPSTREAM: swipl-devel src/pl-thread.c @ 18168e629eab
# CLASS: code
# COPYRIGHT: Copyright (c)  1999-2026, University of Amsterdam,
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
# allow-new-artifact: message queues
#
# PORTED FROM pl-thread.c, "USER MESSAGE QUEUES" (pl-thread.c:5540-6210 at the pin): the message queues and their predicates
# message_queue_create/1,2, message_queue_destroy/1, message_queue_property/2, message_queue_set/2, is_message_queue/1 and, in the second
# part of this file, thread_send_message/2,3, thread_get_message/1,2,3 and thread_peek_message/1,2, over the queue table of the database
# (`gd.message_queues`, upstream `queueTable`) and the queue every thread owns (`gd.thread_queues`).
#
# THE ONE-THREAD FORM (QUEUES; DIVERGES for the whole file): no thread can send a message while another waits for one: an engine runs only
# inside `engine_next` of the thread that calls it. So no `pthread_mutex_t`/`pthread_cond_t` is kept, `waiting` is always 0, and every wait of
# upstream (`dispatch_cond_wait`) is one of two cases. With a deadline (`timeout(T)`, `deadline(D)`) the wait can only end in the timeout, so
# the call FAILS AT ONCE, without sleeping until the deadline (named DIVERGES); with none the wait would never end, which the kernel refuses
# with a `NotPortedError` for step TH1 (`thread_get_message` on a queue with no matching message, `thread_send_message` on a full queue).
# An anonymous queue is a blob of type `message_queue` (`PL_BLOB_UNIQUE`) whose payload is the queue's creation number (upstream: the
# pointer); it is never reclaimed by a garbage collector and leaves the table with message_queue_destroy/1. The queues are enumerated in
# creation order (upstream: hash order). The messages are records (`PL_record`), in arrival order: upstream's `key` (a fast search) and
# `sequence_id` (a skip order for a wait loop) are omitted.

# PORT: pl-thread.c message_queue_blob
# DIVERGES: no `release`, `write`, `acquire`, `save` or `load` slots (`PL_blob_t` has none): see the file header.
"The blob type of an anonymous message queue (pl-thread.c `message_queue_blob`): unique by payload, non-text, named `message_queue`."
const message_queue_blob = PL_blob_t(PL_BLOB_UNIQUE, "message_queue")

# DIVERGES: pl-thread.c `qprop_list`: the four properties of `message_queue_property/2` in upstream's order; the entry's number is what
# `qprop_enum.p` points at.
const _QUEUE_PROPERTIES = (:alias, :size, :max_size, :waiting)

# ORIGINAL (QUEUES): the payload of an anonymous queue's blob (upstream: the bytes of the `mqref`).
"The 8 bytes of a message queue blob: the queue's creation number, little-endian."
_queue_bytes(serial::Int)::Vector{UInt8} = collect(reinterpret(UInt8, Int64[serial]))

# PORT: pl-thread.c unify_queue
"Unify `t` with the identifier of the queue `q`: its name or its blob (pl-thread.c)."
unify_queue(ld::PL_local_data{T}, t::term_t, q::message_queue{T})::Bool where {T} =
    PL_unify_atom(ld, t, q.id::T)

# PORT: pl-thread.c init_message_queue
# DIVERGES: the queue is the record `message_queue{T}`; `id` is `nothing` until the caller gives it a name or a blob (upstream: 0).
"A new empty queue with the size limit `max_size` (0: none), of type `QTYPE_QUEUE` (pl-thread.c)."
init_message_queue(
    ::Type{T}, max_size::Int, serial::Int
) where {T} =
    message_queue{T}(nothing, record{T}[], max_size, false, QTYPE_QUEUE, 0, serial, false)

# PORT: pl-thread.c unlocked_message_queue_create
# DIVERGES: the queue is `nothing` where upstream returns NULL; `gd.message_queue_serial` models `queueTable != NULL` (it is raised at the
# entry, as the table is made there) and numbers every queue; the entry is taken out of the table again when the final unify fails
# (upstream keeps the queue for the GC); `PL_register_atom` and `PL_unregister_atom` are dropped: the kernel has no atom GC. `L_THREAD` is
# dropped: one thread.
"Create the queue the term `queue` names (a variable: an anonymous one) and unify it with `queue`; `nothing` after an error (pl-thread.c)."
function unlocked_message_queue_create(
    ld::PL_local_data{T}, queue::term_t, max_size::Int
)::Union{Nothing, message_queue{T}} where {T}
    gd = _query_gd(ld)
    gd.message_queue_serial += 1                        # if ( !queueTable ) { ... newHTableWP(16) }
    serial = gd.message_queue_serial
    name = PL_get_atom(ld, queue)
    id::Union{Nothing, T} = nothing
    if name !== nothing
        if haskey(gd.message_queues, sym_key(name)) || haskey(gd.thread.thread_table, sym_key(name))
            PL_error(
                ld, "message_queue_create", 1, "", ERR_PERMISSION, mk_sym(T, :create),
                mk_sym(T, :message_queue), queue
            )
            return nothing
        end
        id = name
    elseif PL_is_variable(ld, queue)
        id = nothing
    else
        PL_error(ld, "message_queue_create", 1, "", ERR_TYPE, mk_sym(T, :message_queue), queue)
        return nothing
    end

    q = init_message_queue(T, max_size, serial)
    if id === nothing
        bytes = _queue_bytes(serial)
        w, _ = lookupBlob(gd.atoms, bytes, length(bytes), message_queue_blob)   # lookupBlob(&ref, sizeof(ref), &message_queue_blob, &new)
        q.id = _blob_term!(gd.atoms, gd.atom_symbols, T, w)
        q.anonymous = true
    else
        q.id = id
    end
    gd.message_queues[sym_key(q.id::T)] = q             # addNewHTableWP(queueTable, q->id, q)

    if unify_queue(ld, queue, q)
        return q
    end
    delete!(gd.message_queues, sym_key(q.id::T))
    return nothing
end

# PORT: pl-thread.c message_queue_create
# (PRED_IMPL("message_queue_create", 1, message_queue_create, 0))
"`message_queue_create(?Queue)`: create a queue named by `Queue`, or an anonymous one when it is unbound (pl-thread.c)."
function pl_message_queue_create1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return unlocked_message_queue_create(ld, PL__t0, 0) === nothing ? FFALSE : FTRUE
end

# PORT: pl-thread.c message_queue_options
const _QUEUE_OPTIONS = (PL_option_t(:alias, OPT_ATOM), PL_option_t(:max_size, OPT_SIZE))

# PORT: pl-thread.c message_queue_create2
# (PRED_IMPL("message_queue_create", 2, message_queue_create2, 0))
"`message_queue_create(-Queue, +Options)`: as message_queue_create/1, `alias(Name)` giving the name, `max_size(Size)` the limit (pl-thread.c)."
function pl_message_queue_create2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    vals = PL_scan_options(ld, A2, 0, "queue_option", _QUEUE_OPTIONS)
    vals === nothing && return FFALSE
    alias = _opt_atom(T, vals[1])
    max_size = vals[2] isa Int ? vals[2] : 0

    if alias !== nothing
        if !PL_unify_atom(ld, A1, alias)
            return PL_error(ld, ERR_TYPE, mk_sym(T, :variable), A1) ? FTRUE : FFALSE
        end
    end

    return unlocked_message_queue_create(ld, A1, max_size) === nothing ? FFALSE : FTRUE
end

# ORIGINAL (QUEUES): the queue every thread owns, made at its first use (upstream: `LD->thread.messages`, made with the local data).
"The queue of the thread `tid` (`QTYPE_THREAD`), made on first use."
function _thread_queue(gd::PL_global_data{T}, tid::Int)::message_queue{T} where {T}
    q = get(gd.thread_queues, tid, nothing)
    if q === nothing
        q = message_queue{T}(nothing, record{T}[], 0, false, QTYPE_THREAD, tid, 0, false)
        gd.thread_queues[tid] = q
    end
    return q
end

# PORT: pl-thread.c get_message_queue_unlocked, get_message_queue
# DIVERGES: the queue (or `nothing`, with the error raised) is the result where upstream writes `*queue`; the table lookup of a queue blob
# finds the queue in `gd.message_queues` (upstream follows the pointer of the payload), and a destroyed one is no longer in the table: it
# raises the existence error as upstream's `q->destroyed` does. The main thread has no record (`handle.info === nothing`, engine id 1).
# The queue of a thread is the one of `gd.thread_queues`, made at the first use (`_thread_queue`). `L_THREAD` and the queue's mutex are dropped.
"The queue the term `t` names: a queue blob or name, a thread's alias, handle or id; `nothing` after raising (pl-thread.c)."
function get_message_queue(
    ld::PL_local_data{T}, t::term_t
)::Union{Nothing, message_queue{T}} where {T}
    gd = _query_gd(ld)
    name = PL_get_atom(ld, t)
    if name !== nothing && is_blob(name) && atomValue(gd.atoms, blob_handle(name)).type === message_queue_blob
        q = get(gd.message_queues, sym_key(name), nothing)
        q === nothing && PL_error(ld, ERR_EXISTENCE, mk_sym(T, :message_queue), t)   # q->destroyed
        return q
    end

    tid = 0
    id::Union{Nothing, T} = nothing
    if name !== nothing
        th = symbol_thread_handle(gd, name)
        if th !== nothing
            if th.info !== nothing || th.engine_id == 1         # er->info (the main thread has none here)
                tid = th.engine_id
            else
                PL_error(ld, ERR_EXISTENCE, mk_sym(T, :thread), t)
                return nothing
            end
        else
            id = name
        end
    else
        i = PL_get_integer(ld, t)
        if i === nothing
            PL_error(ld, ERR_TYPE, mk_sym(T, :message_queue), t)
            return nothing
        end
        tid = i
    end

    if tid <= 0 && id === nothing
        PL_error(ld, ERR_TYPE, mk_sym(T, :message_queue), t)
        return nothing
    end

    if id !== nothing
        q = get(gd.message_queues, sym_key(id), nothing)        # queueTable && lookupHTableWP(queueTable, id)
        q === nothing || return q
        serial = get(gd.thread.thread_table, sym_key(id), 0)    # threadTable && lookupHTable(threadTable, id)
        if serial == 0
            PL_error(ld, ERR_EXISTENCE, mk_sym(T, :message_queue), t)
            return nothing
        end
        tid = gd.thread.handles[serial].engine_id
    end

    if tid >= 1 && tid <= gd.thread.highest_id
        if !_thread_slot_valid(gd, tid)
            PL_error(ld, ERR_EXISTENCE, mk_sym(T, :thread), t)
            return nothing
        end
        return _thread_queue(gd, tid)
    end
    PL_error(ld, ERR_TYPE, mk_sym(T, :thread), t)
    return nothing
end

# PORT: pl-thread.c destroy_message_queue
# DIVERGES: the messages are records of the heap and are dropped with the vector; no condition variable to broadcast.
"Delete the contents of the queue `q` (pl-thread.c)."
function destroy_message_queue!(q::message_queue)::Nothing
    empty!(q.messages)
    return nothing
end

# PORT: pl-thread.c message_queue_destroy
# (PRED_IMPL("message_queue_destroy", 1, message_queue_destroy, 0); PRED_DEF flags `PL_FA_ISO`)
# DIVERGES: the destroyed queue leaves the table at once and is flagged; `release_message_queue` has nothing to delete late (no waiters).
"`message_queue_destroy(+Queue)`: destroy the queue and its messages (pl-thread.c)."
function pl_message_queue_destroy1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    q = get_message_queue(ld, A1)
    q === nothing && return FFALSE

    if q.type == QTYPE_THREAD
        return PL_error(
            ld, "", 0, "is a thread-queue", ERR_PERMISSION, mk_sym(T, :destroy),
            mk_sym(T, :message_queue), A1
        ) ? FTRUE : FFALSE
    end

    delete!(_query_gd(ld).message_queues, sym_key(q.id::T))     # deleteHTableWP(queueTable, q->id)
    q.destroyed = true
    destroy_message_queue!(q)
    return FTRUE
end

# PORT: pl-thread.c is_message_queue
# (PRED_IMPL("is_message_queue", 1, is_message_queue, 0))
"`is_message_queue(@Queue)`: whether `Queue` names a live queue (pl-thread.c)."
function pl_is_message_queue1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    gd = _query_gd(ld)
    id = PL_get_atom(ld, PL__t0)
    id === nothing && return FFALSE
    q = get(gd.message_queues, sym_key(id), nothing)            # a blob: ref->queue, a name: queueTable
    return (q !== nothing && !q.destroyed) ? FTRUE : FFALSE
end

# PORT: pl-thread.c message_queue_alias_property, message_queue_size_property, message_queue_max_size_property,
# message_queue_waiting_property
# DIVERGES: the four property functions are one function of the property's number (`qprop_list`, 1: alias, 2: size, 3: max_size,
# 4: waiting), as `mutex_property_value` (src/pl-mutex.jl) does. QUIRK: a thread's queue has `id` 0 (not anonymous), so
# upstream's `PL_unify_atom(prop, 0)` succeeds and leaves the argument unbound: `message_queue_property(main, alias(_))` is true, and so
# here (`id === nothing` succeeds with nothing unified). `waiting` is never above 0 (see the file header).
"Unify `prop` with the argument of property number `p` of the queue `q`: `alias(Name)`, `size(N)`, `max_size(N)` or `waiting(N)` (pl-thread.c)."
function message_queue_property_value(
    ld::PL_local_data{T}, q::message_queue{T}, p::Int, prop::term_t
)::Bool where {T}
    if p == 1                                           # message_queue_alias_property
        q.id === nothing && return true
        return !q.anonymous && PL_unify_atom(ld, prop, q.id)
    elseif p == 2                                       # message_queue_size_property
        return PL_unify_integer(ld, prop, length(q.messages))
    elseif p == 3                                       # message_queue_max_size_property
        return q.max_size > 0 && PL_unify_integer(ld, prop, q.max_size)
    end
    return false                                        # message_queue_waiting_property: nobody waits
end

# PORT: pl-thread.c advance_qstate
# DIVERGES: `state->p` is an index; the table enumerator `state->e` is the snapshot `queues` with its next index.
"Advance the enumeration of `message_queue_property/2` to the next property, then the next queue; false at the end (pl-thread.c)."
function advance_qstate!(state::qprop_enum)::Bool
    if state.enum_properties
        state.p += 1
        state.p <= length(_QUEUE_PROPERTIES) && return true
        state.p = 1                                     # state->p = qprop_list
    end
    state.enumerating && advance_qstate_table!(state) && return true    # state->e: the next queue
    return false
end

# ORIGINAL (QUEUES): `advanceTableEnum(state->e, NULL, &tv)`: the next queue of the snapshot as the current one; false at its end.
"Take the next queue of the enumeration's snapshot as the current one; false at its end."
function advance_qstate_table!(state::qprop_enum)::Bool
    state.next <= length(state.queues) || return false
    state.q = state.queues[state.next]
    state.next += 1
    return true
end

# PORT: pl-thread.c free_qstate
# DIVERGES: the record goes back to the pool (`freeForeignState`); it drops its references to the queues.
"Give the `message_queue_property/2` state at pool index `idx` back (pl-thread.c)."
function free_qstate!(pool::foreign_state_pool{qprop_enum{T}}, idx::Int)::Nothing where {T}
    state = pool.states[idx]
    empty!(state.queues)
    state.q = nothing
    free_foreign_state!(pool, idx)
    return nothing
end

# PORT: pl-thread.c message_property
# (PRED_IMPL("message_queue_property", 2, message_property, PL_FA_NONDETERMINISTIC), pl-thread.c:5964 at the pin; PRED_DEF flags `NDET|PL_FA_ISO`)
# DIVERGES: as `pl_mutex_property2_va` (src/pl-mutex.jl): the state is a record of `ld.queue_enums` from the first call on, its pool index the
# `REDO_PTR` context; the table enumerator is a snapshot of the user queues in creation order (the thread queues are not in the table). With
# no queue ever made (`message_queue_serial == 0`: `queueTable` is NULL) an unbound `Queue` fails.
"`message_queue_property(?Queue, ?Property)`: `alias(Name)`, `size(N)`, `max_size(N)` and `waiting(N)` of a queue, enumerating (pl-thread.c)."
function pl_message_queue_property2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    queue, property = PL__t0, PL__t0 + 1
    pool = ld.queue_enums
    idx = 0

    ctl = PL_foreign_control(PL__ctx)
    if ctl == FRG_FIRST_CALL
        if PL_is_variable(ld, queue)
            _query_gd(ld).message_queue_serial == 0 && return FFALSE    # !queueTable
            rc, p = get_prop_def(ld, property, :message_queue_property, _QUEUE_PROPERTIES)
            rc == -1 && return FFALSE
            idx = alloc_foreign_state!(pool)
            state = pool.states[idx]
            state.q = nothing
            state.next = 1
            state.enumerating = true                    # state->e = newTableEnumWP(queueTable)
            empty!(state.queues)
            append!(state.queues, values(_query_gd(ld).message_queues))
            sort!(state.queues; by = x -> x.serial)
            if rc == 1
                state.p = p
                state.enum_properties = false
            else
                state.p = 1                             # state->p = qprop_list
                state.enum_properties = true
            end
        else
            q = get_message_queue(ld, queue)
            q === nothing && return FFALSE
            rc, p = get_prop_def(ld, property, :message_queue_property, _QUEUE_PROPERTIES)
            rc == -1 && return FFALSE
            idx = alloc_foreign_state!(pool)
            state = pool.states[idx]
            state.q = q
            state.next = 1
            state.enumerating = false
            empty!(state.queues)
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
        free_qstate!(pool, PL_foreign_context_address(PL__ctx))
        return FTRUE
    end
    state = pool.states[idx]

    if state.q === nothing                              # first time, enumerating queues
        if !advance_qstate_table!(state)
            free_qstate!(pool, idx)
            return FFALSE
        end
    end

    arg = PL_new_term_ref(ld)
    state.enum_properties || _PL_get_arg(ld, 1, property, arg)

    while true
        q = state.q::message_queue{T}
        if message_queue_property_value(ld, q, state.p, arg)
            if state.enum_properties
                tmp = _message_term(ld, _QUEUE_PROPERTIES[state.p], arg)
                if !PL_unify(ld, property, tmp)
                    free_qstate!(pool, idx)
                    return FFALSE
                end
            end
            if state.enumerating
                if !unify_queue(ld, queue, q)
                    free_qstate!(pool, idx)
                    return FFALSE
                end
            end

            advance_qstate!(state) && return PL_retry_address(idx)     # ForeignRedoPtr(state)

            free_qstate!(pool, idx)
            return FTRUE
        end

        if !advance_qstate!(state)
            free_qstate!(pool, idx)
            return FFALSE
        end
    end
end

# PORT: pl-thread.c message_queue_set
# (PRED_IMPL("message_queue_set", 2, message_queue_set, 0))
"`message_queue_set(+Queue, +Property)`: set `max_size(Size)` of a queue (pl-thread.c)."
function pl_message_queue_set2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    q = get_message_queue(ld, A1)
    q === nothing && return FFALSE

    na = PL_get_name_arity(ld, A2)
    if na !== nothing && na[2] == 1
        a = PL_new_term_ref(ld)
        _PL_get_arg(ld, 1, A2, a)
        if sym_key(na[1]) == sym_key(mk_sym(T, :max_size))
            mx = PL_get_size_ex(ld, a)
            mx === nothing && return FFALSE
            q.max_size = mx                             # no writer waits for a drain here
            return FTRUE
        end
        return PL_domain_error(ld, "message_queue_property", A2) ? FTRUE : FFALSE
    end
    return PL_type_error(ld, "compound", A2) ? FTRUE : FFALSE
end

# PORT: pl-thread.c BeginPredDefs as PL_predicates_from_queue (the message queue entries of pl-thread.c's table, pl-thread.c:8870-8893)
# (message_queue_create/1 and /2, message_queue_set/2 and is_message_queue/1 flags 0, message_queue_destroy/1 `PL_FA_ISO`, message_queue_property/2
# `NDET|PL_FA_ISO`)
# DIVERGES: the entries sit in a table of this file, between mutex and wrap, not in `PL_predicates_from_thread`.
"The registration table of the message queue predicates."
const PL_predicates_from_queue = (
    PL_extension("message_queue_create", 1, pl_message_queue_create1_va, PL_FA_VARARGS),
    PL_extension("message_queue_create", 2, pl_message_queue_create2_va, PL_FA_VARARGS),
    PL_extension("message_queue_destroy", 1, pl_message_queue_destroy1_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension(
        "message_queue_property", 2, pl_message_queue_property2_va,
        PL_FA_NONDETERMINISTIC | PL_FA_ISO | PL_FA_VARARGS
    ),
    PL_extension("message_queue_set", 2, pl_message_queue_set2_va, PL_FA_VARARGS),
    PL_extension("is_message_queue", 1, pl_is_message_queue1_va, PL_FA_VARARGS)
)
