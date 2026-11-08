# UPSTREAM: swipl-devel src/pl-event.c @ cbf4e1896275
# UPSTREAM: swipl-devel src/pl-event.h @ cbf4e1896275
# CLASS: code
# COPYRIGHT: Copyright (c)  2019-2026, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# EVENTS (pl-event.c): the event lists (`GD->event.hook`, the local data's `event.hook.onthreadexit`, a predicate's
# `definition.events`), their registration (`prolog_listen/2,3`, `prolog_unlisten/2`: the options `as(first|last)` and
# `name(Name)`, the event type: an event NAME or a predicate indicator, the closure: `callable`, module-qualified) and the
# calling side (`callEventHook`, `PL_call_event_hook`, `predicate_update_event`, `table_answer_event`, `retractall_event`,
# `delayEvents`/`sendDelayedEvents`). boot/tabling.pl runs `prolog_listen(untable, …)` when it loads.
#
# The sites that raise an event and have a function here (R2 EV1): assertDefinition, retractClauseDefinition, retractall/1,
# erase/1 of a record, frameFinished. Each raise site whose function is not written yet is listed in
# evidence/EV1/handoff.md with the step that owns it (breakpoints DBG1, threads TH1, tabling TAB1, source reload, transactions).
#
# DIVERGES (representation only, flagged to the audit): an event list is a vector in the order the handlers are called
# (upstream's head/tail chain and its lock: one thread); a closure is kept as the term's record (`fastheap_term`);
# `event_type.location` names the field of `GD->event.hook` (upstream: a pointer, or an offset into the local data).

# PORT: pl-event.c event_type
# DIVERGES: `local_` for upstream's `local`; `location` is the NAME of the field of `GD->event.hook` that holds the list
# (for a local event, of `LD`: `event_hook_onthreadexit`), where upstream keeps a pointer or an offset; `name` is the event's atom.
"One row of the event table (pl-event.c `struct event_type`): the id, the event's name, its argument count, the list's place."
struct event_type
    id::Int                                     # PLEV_*
    name::Symbol                                # the event's atom
    argc::Int                                   # the event's arguments
    local_::Bool                                # the list is in the local data
    location::Symbol                            # the field of the list's holder
end

# PORT: pl-event.c PL_events
# DIVERGES: the twelve rows of the O_ENGINES build in upstream's order (`erase` and `break` repeat per event id: a name
# resolves to its FIRST row); the sentinel `{0}` is not kept.
"The events `prolog_listen/2,3` accepts (pl-event.c `PL_events`): the index in the table is the event's id plus one."
const PL_events = (
    event_type(PLEV_ABORT, :abort, 0, false, :onabort),
    event_type(PLEV_ERASED_CLAUSE, :erase, 1, false, :onerase),
    event_type(PLEV_ERASED_RECORD, :erase, 1, false, :onerase),
    event_type(PLEV_BREAK, :break, 3, false, :onbreak),
    event_type(PLEV_BREAK_EXISTS, :break, 3, false, :onbreak),
    event_type(PLEV_NOBREAK, :break, 3, false, :onbreak),
    event_type(PLEV_RETRACTNOBREAK, :break, 3, false, :onbreak),
    event_type(PLEV_FRAMEFINISHED, :frame_finished, 1, false, :onframefinish),
    event_type(PLEV_UNTABLE, :untable, 1, false, :onuntable),
    event_type(PLEV_THREAD_START, :thread_start, 1, false, :onthreadstart),
    event_type(PLEV_THREAD_EXIT, :thread_exit, 1, false, :onthreadexit),
    event_type(PLEV_THIS_THREAD_EXIT, :this_thread_exit, 0, true, :event_hook_onthreadexit)
)

# PORT: pl-event.h event_list_location as event_location
# DIVERGES: the place of a list as a value: `ev` the event id (-1: a predicate's list), `def` that predicate's definition.
# Upstream's `event_list **`: read it with `event_list_at`, write it with `event_list_set!`.
"Where an event list is kept (pl-event.h `event_list **`): the table of the event `ev`, or the `events` of `def` (`ev` = -1)."
struct event_location{T}
    ev::Int
    def::Union{Nothing, definition{T}}
end

"The event list at `loc` (the pointer `*listp` of pl-event.h), or `nothing` (NULL)."
function event_list_at(
    gd::PL_global_data{T}, ld::PL_local_data{T}, loc::event_location{T}
)::Union{Nothing, event_list{T, definition{T}}} where {T}
    loc.def === nothing || return loc.def.events
    et = PL_events[loc.ev + 1]
    et.local_ && return ld.event_hook_onthreadexit
    h = gd.event_hook
    loc_ = et.location
    loc_ === :onabort && return h.onabort
    loc_ === :onerase && return h.onerase
    loc_ === :onbreak && return h.onbreak
    loc_ === :onframefinish && return h.onframefinish
    loc_ === :onthreadstart && return h.onthreadstart
    loc_ === :onthreadexit && return h.onthreadexit
    return h.onuntable
end

"Make the event list at `loc` `list` (`nothing`: NULL), as `*listp = list` does (pl-event.c)."
function event_list_set!(
    gd::PL_global_data{T}, ld::PL_local_data{T}, loc::event_location{T},
    list::Union{Nothing, event_list{T, definition{T}}}
)::Nothing where {T}
    if loc.def !== nothing
        loc.def.events = list
        return nothing
    end
    et = PL_events[loc.ev + 1]
    if et.local_
        ld.event_hook_onthreadexit = list
    else
        h = gd.event_hook
        loc_ = et.location
        if loc_ === :onabort
            h.onabort = list
        elseif loc_ === :onerase
            h.onerase = list
        elseif loc_ === :onbreak
            h.onbreak = list
        elseif loc_ === :onframefinish
            h.onframefinish = list
        elseif loc_ === :onthreadstart
            h.onthreadstart = list
        elseif loc_ === :onthreadexit
            h.onthreadexit = list
        else
            h.onuntable = list
        end
    end
    return nothing
end

# PORT: pl-event.c link_event
# DIVERGES: the list is a vector (no lock): the first handler is the first element.
"Add the callback `cb` at the end (`last`) or the start of `list` (pl-event.c)."
function link_event(
    list::event_list{T, D}, cb::event_callback{T, D}, last::Bool
)::Bool where {T, D}
    if last
        push!(list.callbacks, cb)
    else
        pushfirst!(list.callbacks, cb)
    end
    return true
end

# PORT: pl-event.c prolog_listen_options
const prolog_listen_options = (
    PL_option_t(:as, OPT_ATOM),
    PL_option_t(:name, OPT_ATOM)
)

# PORT: pl-event.c get_callback
# DIVERGES: returns `(ok, module index)`; the module is `PL_strip_module`'s (the context module when `closure` is unqualified).
"Strip the module of `closure` into `cb` and check that it is callable (pl-event.c)."
function get_callback(
    gd::PL_global_data{T}, ld::PL_local_data{T}, closure::term_t, cb::term_t
)::Tuple{Bool, Int} where {T}
    ok, m = PL_strip_module(gd, ld, closure, 0, cb)
    ok || return (false, m)
    if !PL_is_callable(ld, cb)
        PL_type_error(ld, "callable", closure)
        return (false, m)
    end
    return (true, m)
end

# PORT: pl-event.c add_event_hook
# DIVERGES: the list is a vector (`link_event`); upstream's loop over the named callbacks leaves the list locked after a
# replacement (no lock here); a predicate listener's procedure is `PL_predicate("call", argc+1, "system")` as `lookupProcedure`.
"Register the closure `closure` as a listener of an event of `argc` arguments in `list`, replacing the one of the same `name` (pl-event.c)."
function add_event_hook(
    gd::PL_global_data{T}, ld::PL_local_data{T}, list::event_list{T, definition{T}},
    name::Union{Nothing, T}, last::Bool, closure::term_t, argc::Int
)::Bool where {T}
    t = PL_new_term_ref(ld)
    ok, m = get_callback(gd, ld, closure, t)
    ok || return false

    if name !== nothing
        for ev in list.callbacks
            if event_name_is(ev.name, name) && ev.function_ == 0
                r = ev.closure
                ev.closure = term_to_fastheap(ld, closure)
                r === nothing || free_fastheap(r)
                return true
            end
        end
    end

    cb = event_callback{T, definition{T}}(name, m, nothing, 0, nothing, argc, UInt32(0))
    pname = PL_get_atom(ld, t)
    if pname !== nothing
        cb.procedure = resolveProcedure(gd, pname, argc, gd.modules[m])
    else
        cb.procedure = lookupProcedure(mk_sym(T, :call), argc + 1, MODULE_system(gd))
        cb.closure = term_to_fastheap(ld, closure)
    end

    return link_event(list, cb, last)
end

# PORT: pl-event.c get_event_list
# DIVERGES: the list's place is an `event_location`; no `L_EVHOOK` lock (no threads).
"The event list at `loc`, made empty when it is NULL (pl-event.c)."
function get_event_list!(
    gd::PL_global_data{T}, ld::PL_local_data{T}, loc::event_location{T}
)::event_list{T, definition{T}} where {T}
    l = event_list_at(gd, ld, loc)
    l === nothing || return l
    l = event_list{T, definition{T}}()
    event_list_set!(gd, ld, loc, l)
    return l
end

# PORT: pl-event.c register_event_hook
"Register `closure` as a listener at `loc`: `get_event_list!` and `add_event_hook` (pl-event.c)."
function register_event_hook(
    gd::PL_global_data{T}, ld::PL_local_data{T}, loc::event_location{T},
    name::Union{Nothing, T}, last::Bool, closure::term_t, argc::Int
)::Bool where {T}
    return add_event_hook(gd, ld, get_event_list!(gd, ld, loc), name, last, closure, argc)
end

# `a == b` on two atoms is `==` of the reference term type only: the other term types compare through the interface (the alt types
# raise on `==`), so an atom is tested against a name by its text.
"Whether the term `t` is the atom `name`."
event_atom_is(t::T, name::Symbol) where {T} = kind(t) === SYM && sym_text(t) == String(name)

"Whether the listener name `a` (`nothing`: none) is the atom `b`."
event_name_is(a::Union{Nothing, T}, b::T) where {T} =
    a !== nothing && sym_key(a) == sym_key(b)

# PORT: pl-event.c get_event_listp
# DIVERGES: returns `(location, argc)` where upstream writes the list's location through `listpp` and `argc`, or `nothing`
# after raising the error. A predicate indicator (`arity != 0` after `PL_get_name_arity`) resolves the procedure
# (`get_procedure_resolve_namearity`: `GP_RESOLVE|GP_NAMEARITY`, src/pl-proc.jl); when that fails upstream raises the domain error on top.
"Check the event type `type` (pl-event.c): the place of its list and the argument count of the event, or `nothing` after raising the error."
function get_event_listp(
    gd::PL_global_data{T}, ld::PL_local_data{T}, type::term_t
)::Union{Nothing, Tuple{event_location{T}, Int}} where {T}
    na = PL_get_name_arity(ld, type)

    if na !== nothing
        name, arity = na

        if arity == 0
            for (i, et) in enumerate(PL_events)
                if event_atom_is(name, et.name)
                    @assert et.id + 1 == i              # assert(et->id == et-PL_events)
                    return (event_location{T}(et.id, nothing), et.argc)
                end
            end
        else
            proc = get_procedure_resolve_namearity(gd, ld, type)
            if proc !== nothing
                return (event_location{T}(-1, proc.definition), 2)   # action, cref
            end
        end

        PL_domain_error(ld, "event", type)
        return nothing
    end

    PL_type_error(ld, "callable", type)
    return nothing
end

# PORT: pl-event.c prolog_listen
# DIVERGES: `options` is 0 for NULL (upstream: a null `term_t`).
"The body of `prolog_listen/2,3`: check the options, the event type and the closure, register the listener (pl-event.c)."
function prolog_listen(
    gd::PL_global_data{T}, ld::PL_local_data{T}, type::term_t, closure::term_t,
    options::term_t
)::Bool where {T}
    as = mk_sym(T, :first)
    name = nothing

    if options != 0
        vals = PL_scan_options(
            ld, options, 0, "prolog_listen_option", prolog_listen_options
        )
        vals === nothing && return false
        vals[1] === nothing || (as = vals[1]::T)
        vals[2] === nothing || (name = vals[2]::T)
    end

    if !(event_atom_is(as, :first) || event_atom_is(as, :last))
        ex = PL_new_term_ref(ld)
        return PL_put_atom(ld, ex, as) && PL_domain_error(ld, "as", ex)
    end

    r = get_event_listp(gd, ld, type)
    r === nothing && return false
    loc, argc = r

    return register_event_hook(gd, ld, loc, name, event_atom_is(as, :last), closure, argc)
end

# PORT: pl-event.c prolog_listen as pl_prolog_listen2_va
# (PRED_IMPL("prolog_listen", 2, prolog_listen, META), pl-event.c:275-279 at the pin)
"`prolog_listen(+Channel, :Closure)`: register `Closure` as a listener of the event `Channel` (pl-event.c)."
function pl_prolog_listen2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1

    return prolog_listen(_query_gd(ld), ld, A1, A2, 0) ? FTRUE : FFALSE
end

# PORT: pl-event.c prolog_listen as pl_prolog_listen3_va
# (PRED_IMPL("prolog_listen", 3, prolog_listen, META), pl-event.c:282-286 at the pin)
"`prolog_listen(+Channel, :Closure, +Options)`: as prolog_listen/2 with the options `as(first|last)` and `name(Name)` (pl-event.c)."
function pl_prolog_listen3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2, A3 = PL__t0, PL__t0 + 1, PL__t0 + 2

    return prolog_listen(_query_gd(ld), ld, A1, A2, A3) ? FTRUE : FFALSE
end

# PORT: pl-event.c free_event_callback
# DIVERGES: nothing to free (Julia's garbage collector; upstream frees the closure's cells and unregisters the name atom).
"Free the callback `cb` (pl-event.c)."
function free_event_callback(cb::event_callback)::Nothing
    clo = cb.closure
    if cb.function_ == 0 && clo !== nothing
        free_fastheap(clo)
    end
    return nothing
end

# PORT: pl-event.c prolog_unlisten
# DIVERGES: the list is a vector, a deletion is `deleteat!`; the foreign frame `fid` is closed at the return (upstream
# leaves it to the end of the call, the leaked frames of its early returns included). Representation only.
"The body of `prolog_unlisten/2`: delete the listeners of the event `A1` that match the closure `A2` (pl-event.c)."
function prolog_unlisten(
    gd::PL_global_data{T}, ld::PL_local_data{T}, A1::term_t, A2::term_t
)::Bool where {T}
    r = get_event_listp(gd, ld, A1)
    r === nothing && return false
    loc, argc = r

    list = event_list_at(gd, ld, loc)
    list === nothing && return true

    t = PL_new_term_ref(ld)
    fid = PL_open_foreign_frame(ld)
    tmp = PL_new_term_ref(ld)
    proc = nothing
    ok, m = get_callback(gd, ld, A2, t)
    if !ok
        PL_close_foreign_frame(ld, fid)
        return false
    end
    name = PL_get_atom(ld, t)
    if name !== nothing
        proc = resolveProcedure(gd, name, argc, gd.modules[m])
    end

    cbs = list.callbacks
    i = 1
    while i <= length(cbs)
        ev = cbs[i]
        delete = false
        if ev.function_ == 0
            if proc !== nothing
                if (ev.procedure::Procedure{T}).definition === proc.definition
                    delete = true
                end
            elseif (clo = ev.closure) !== nothing
                if put_fastheap(ld, clo, tmp) && PL_unify(ld, A2, tmp)
                    delete = true
                elseif PL_exception(ld, 0) != 0
                    PL_close_foreign_frame(ld, fid)
                    return false
                else
                    PL_rewind_foreign_frame(ld, fid)
                end
            end
        end
        if delete
            deleteat!(cbs, i)
            free_event_callback(ev)
        else
            i += 1
        end
    end

    PL_close_foreign_frame(ld, fid)
    return true
end

# PORT: pl-event.c prolog_unlisten as pl_prolog_unlisten2_va
# (PRED_IMPL("prolog_unlisten", 2, prolog_unlisten, META), pl-event.c:288-345 at the pin)
"`prolog_unlisten(+Channel, :Closure)`: remove the listeners of `Channel` that match `Closure` (pl-event.c)."
function pl_prolog_unlisten2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1

    return prolog_unlisten(_query_gd(ld), ld, A1, A2) ? FTRUE : FFALSE
end

# PORT: pl-event.c destroy_event_list
# DIVERGES: the list's place is an `event_location` (`*listp = NULL`), no lock to delete.
"Remove the event list at `loc` with its callbacks (pl-event.c)."
function destroy_event_list!(
    gd::PL_global_data{T}, ld::PL_local_data{T}, loc::event_location{T}
)::Nothing where {T}
    list = event_list_at(gd, ld, loc)
    if list !== nothing
        event_list_set!(gd, ld, loc, nothing)
        for cb in list.callbacks
            free_event_callback(cb)
        end
    end
    return nothing
end

# PORT: pl-event.c destroy_event_list as destroy_event_list!
# (on a predicate's list)
"Remove the event list of the definition `def` (`unallocDefinition`, `resetProcedure`: pl-proc.c)."
function destroy_event_list!(def::definition{T})::Nothing where {T}
    list = def.events
    if list !== nothing
        def.events = nothing                            # *listp = NULL
        for cb in list.callbacks
            free_event_callback(cb)
        end
    end
    return nothing
end

# PORT: pl-event.c destroy_event_list as destroy_event_list!
# (on a predicate's list, with the database and local data)
"The method of `destroy_event_list!` that takes the database and the local data; the predicate's list needs neither."
function destroy_event_list!(
    gd::PL_global_data{T}, ld::PL_local_data{T}, def::definition{T}
)::Nothing where {T}
    return destroy_event_list!(def)
end

# PORT: pl-event.c cleanupEvents
# DIVERGES: the database's lists only (the local data's `this_thread_exit` list is `freePrologLocalData`'s: TH1).
"Remove the database's event lists (pl-event.c): `PL_cleanup`'s."
function cleanupEvents(gd::PL_global_data{T}, ld::PL_local_data{T})::Nothing where {T}
    for et in PL_events
        et.local_ || destroy_event_list!(gd, ld, event_location{T}(et.id, nothing))
    end
    return nothing
end

# PORT: pl-event.c call_event_list
# DIVERGES: the callbacks are a SNAPSHOT of the vector (a listener may call `prolog_unlisten/2`); the C-function branch
# (`function_ != 0`, registered by `register_event_function` for `PL_thread_at_exit`: TH1) has no function pointer to call
# and counts as a failure; a callback's module is its index.
"Call the listeners of `list` with the event's arguments `argv+1…`, `argv` the closure's slot (pl-event.c)."
function call_event_list(
    gd::PL_global_data{T}, ld::PL_local_data{T},
    list::Union{Nothing, event_list{T, definition{T}}},
    argc::Int, argv::term_t
)::Bool where {T}
    rc = true

    if list !== nothing
        for ev in copy(list.callbacks)
            if ev.function_ != 0
                rc = false                                  # a C function: TH1's
            elseif (clo = ev.closure) !== nothing
                rc =
                    rc && (
                        put_fastheap(ld, clo, argv) &&
                        PL_call_predicate(
                            gd, ld, gd.modules[ev.module_],
                            PL_Q_NODEBUG | PL_Q_PASS_EXCEPTION,
                            ev.procedure::Procedure{T}, argv
                        )
                    )
            else
                @assert ev.argc == argc
                rc =
                    rc && PL_call_predicate(
                        gd, ld, nothing, PL_Q_NODEBUG | PL_Q_PASS_EXCEPTION,
                        ev.procedure::Procedure{T},
                        argv + 1
                    )
            end
            if !rc && PL_exception(ld, 0) != 0
                break
            end
        end
    end

    return rc
end

# The values of an event are a tuple (upstream's `va_arg`s), read by `event_arg`: a value of another type is an error (a
# type assertion on a tuple element of another type is a static error for JET, which sees only the one caller's tuple).
"The `i`-th value of an event as a `X` (upstream's `va_arg(args, X)`)."
@inline function event_arg(::Type{X}, args::Tuple, i::Int)::X where {X}
    a = args[i]
    a isa X || throw(ArgumentError("event value $i is not a $X"))
    return a
end

# PORT: pl-event.c delayEvent
# DIVERGES: the arguments are the event's values (`clause`, `offset` for the break events, `clause` for an erase, the procedure
# for `PLEV_UNTABLE`), `va_arg`'s; no `acquire_clause` (the reference keeps the clause); upstream's `assert(0)` is `@assert`.
"Keep the event `ev` until `sendDelayedEvents` (pl-event.c): only the break, erase and untable events are delayed."
function delayEvent(ld::PL_local_data{T}, ev::Int, args...)::Bool where {T}
    buf = ld.event_buffered                     # a local: JET narrows it, not the field read twice
    if buf !== nothing
        if ev == PLEV_BREAK_EXISTS || ev == PLEV_BREAK || ev == PLEV_NOBREAK ||
            ev == PLEV_RETRACTNOBREAK
            dev = delayed_event{T}(
                ev, event_arg(Clause{T}, args, 1), event_arg(Int, args, 2), nothing
            )
        elseif ev == PLEV_ERASED_CLAUSE
            dev = delayed_event{T}(ev, event_arg(Clause{T}, args, 1), 0, nothing)
        elseif ev == PLEV_UNTABLE
            dev = delayed_event{T}(ev, nothing, 0, event_arg(Procedure{T}, args, 1))
        else
            @assert false "delayEvent(): the event $ev cannot be delayed"
        end
        push!(buf, dev)
    end

    return true
end

# PORT: pl-event.c delayEvents
# DIVERGES: no allocation to fail (`malloc` of the buffer).
"Start delaying events, nested (pl-event.c): true for the outermost call only."
function delayEvents(ld::PL_local_data{T})::Bool where {T}
    nesting = ld.event_delay_nesting
    ld.event_delay_nesting = nesting + 1
    if nesting == 0
        @assert ld.event_buffered === nothing
        ld.event_buffered = delayed_event{T}[]
        return true
    end

    return false
end

# PORT: pl-event.c sendDelayedEvents
# DIVERGES: as upstream, the events after a failed one are dropped and not released (no `release_clause` here).
"""
    sendDelayedEvents(gd, ld, noerror) -> Int

Leave one level of delaying; at the outermost, send the events kept (pl-event.c): -1 when a listener
raised, else the number sent.
"""
function sendDelayedEvents(
    gd::PL_global_data{T}, ld::PL_local_data{T}, noerror::Bool
)::Int where {T}
    sent = 0

    ld.event_delay_nesting -= 1
    if ld.event_delay_nesting == 0
        b = ld.event_buffered::Vector{delayed_event{T}}
        ld.event_buffered = nothing

        for dev in b
            if noerror
                ev = dev.type
                if ev == PLEV_BREAK_EXISTS || ev == PLEV_BREAK || ev == PLEV_NOBREAK ||
                    ev == PLEV_RETRACTNOBREAK
                    noerror = callEventHook(gd, ld, ev, dev.clause::Clause{T}, dev.offset)
                    sent += 1
                elseif ev == PLEV_ERASED_CLAUSE
                    noerror = callEventHook(gd, ld, ev, dev.clause::Clause{T})
                    sent += 1
                elseif ev == PLEV_UNTABLE
                    noerror = callEventHook(gd, ld, ev, dev.proc::Procedure{T})
                    sent += 1
                else
                    @assert false "sendDelayedEvents(): the event $ev was not delayed"
                end
            end
        end
    end

    return noerror ? sent : -1
end

# PORT: pl-event.h callEventHook
# DIVERGES: the database and the local data are arguments; `args` are the event's values (`va_arg`'s).
"Raise the event `ev` with its values: true when no listener, else `PL_call_event_hook_va`; false iff a listener raised (pl-event.h)."
function callEventHook(
    gd::PL_global_data{T}, ld::PL_local_data{T}, ev::Int, args...
)::Bool where {T}
    if event_list_at(gd, ld, event_location{T}(ev, nothing)) !== nothing
        return PL_call_event_hook_va(gd, ld, ev, args...)
    end

    return true
end

# PORT: pl-event.c PL_call_event_hook
# DIVERGES: NOT STARTED: the `GD->halt.cleaning != CLN_DATA` test (`PL_cleanup` is a later step); the kernel's callers use `callEventHook`.
"Raise the event `ev` as `callEventHook` does, for the C interface (pl-event.c)."
function PL_call_event_hook(
    gd::PL_global_data{T}, ld::PL_local_data{T}, ev::Int, args...
)::Bool where {T}
    return callEventHook(gd, ld, ev, args...)
end

# PORT: pl-event.c PL_call_event_hook_va
# DIVERGES: `args` are the event's values; the thread events raise a `NotPortedError` naming TH1 (`unify_thread_id`: no
# thread table); an unknown event is `false` (upstream warns).
"Raise the event `ev`: put its arguments and call its listeners; false iff there is an exception in a hook (pl-event.c)."
function PL_call_event_hook_va(
    gd::PL_global_data{T}, ld::PL_local_data{T}, ev::Int, args...
)::Bool where {T}
    rc = true
    list = event_list_at(gd, ld, event_location{T}(ev, nothing))
    event_decl = PL_events[ev + 1]

    if ld.event_delay_nesting != 0
        delayEvent(ld, ev, args...)
        return true
    end

    wstate = saveWakeup(ld, true)
    wstate === nothing && return false
    av = PL_new_term_refs(ld, event_decl.argc + 1)

    if ev == PLEV_ABORT
        # nothing to put
    elseif ev == PLEV_ERASED_CLAUSE
        rc = PL_put_clref(gd, ld, av + 1, event_arg(Clause{T}, args, 1))           # object erased
    elseif ev == PLEV_ERASED_RECORD
        rc = PL_unify_recref(gd, ld, av + 1, event_arg(RecordRef{T}, args, 1))     # object erased
    elseif ev == PLEV_BREAK || ev == PLEV_BREAK_EXISTS || ev == PLEV_NOBREAK ||
        ev == PLEV_RETRACTNOBREAK
        cl = event_arg(Clause{T}, args, 1)
        offset = event_arg(Int, args, 2)
        rc = (
            PL_put_atom(
                ld, av + 1,
                mk_sym(
                    T, if ev == PLEV_BREAK
                        Symbol("true")                  # (`:true` is the Bool)
                    elseif ev == PLEV_NOBREAK
                        Symbol("false")
                    elseif ev == PLEV_RETRACTNOBREAK
                        :retract
                    else
                        :exist
                    end
                )
            ) &&
            PL_put_clref(gd, ld, av + 2, cl) &&
            PL_put_intptr(ld, av + 3, offset)
        )
    elseif ev == PLEV_FRAMEFINISHED
        rc = PL_put_frame(ld, av + 1, event_arg(Int, args, 1))
    elseif ev == PLEV_THREAD_START || ev == PLEV_THREAD_EXIT
        throw(
            NotPortedError{T}(
                mk_sym(T, :prolog_listen), "the thread events (`unify_thread_id`)", "TH1"
            )
        )
    elseif ev == PLEV_THIS_THREAD_EXIT
        # nothing to put
    elseif ev == PLEV_UNTABLE
        proc = event_arg(Procedure{T}, args, 1)
        rc = unify_definition(
            gd, ld, MODULE_user(gd), av + 1, proc.definition, 0, GP_QUALIFY | GP_NAMEARITY
        )
    else
        rc = false                                              # callEventHook(): unknown event
        restoreWakeup(ld, wstate)
        return rc
    end

    if rc
        rc = call_event_list(gd, ld, list, event_decl.argc, av)

        if !rc && PL_exception(ld, 0) != 0
            wstate = wakeup_state(
                wstate.fid, wstate.outofstack, wstate.flags | WAKEUP_KEEP_URGENT_EXCEPTION
            )
        else
            rc = true                                           # only false on error
        end
    end

    restoreWakeup(ld, wstate)

    return rc
end

# PORT: pl-event.c predicate_update_event
# DIVERGES: the database is an argument; `action` is the atom's term; the `rollback/1` functor is looked up by name.
"Tell the listeners of the predicate `def` that the clause `cl` was added or removed by `action` (pl-event.c)."
function predicate_update_event(
    gd::PL_global_data{T}, ld::PL_local_data{T}, def::definition{T}, action::T,
    cl::Clause{T}, flags::UInt32
)::Bool where {T}
    wstate = saveWakeup(ld, true)
    wstate === nothing && return false
    av = PL_new_term_refs(ld, 3)                                # closure, action, clause
    rc = av != 0 && PL_put_atom(ld, av + 1, action) && PL_put_clref(gd, ld, av + 2, cl)

    if rc && (flags & P_EVENT_ROLLBACK) != 0
        rollback1 = lookupFunctorDef(ld.functors, _atom_word!(ld, mk_sym(T, :rollback)), 1)
        rc = PL_cons_functor(ld, av + 1, rollback1, av + 1)
    end

    if rc
        rc = call_event_list(gd, ld, def.events, 2, av)
    end

    restoreWakeup(ld, wstate)

    return rc
end

# PORT: pl-event.c table_answer_event
# DIVERGES: NOT STARTED: `save_tabling_status`/`restore_tabling_status` around the call (the tabling status is TAB1's);
# nothing calls this function yet.
"Tell the listeners of the tabled predicate `def` about the `answer` added or removed by `action` (pl-event.c)."
function table_answer_event(
    gd::PL_global_data{T}, ld::PL_local_data{T}, def::definition{T}, action::T,
    answer::term_t
)::Bool where {T}
    wstate = saveWakeup(ld, true)
    wstate === nothing && return false
    av = PL_new_term_refs(ld, 3)                                # closure, action, answer
    rc = av != 0 && PL_put_atom(ld, av + 1, action) && PL_put_term(ld, av + 2, answer)

    if rc
        rc = call_event_list(gd, ld, def.events, 2, av)
    end

    restoreWakeup(ld, wstate)

    return rc
end

# PORT: pl-event.c retractall_event
# DIVERGES: `start` is the NAME of the functor (`:start`, `:end`: `FUNCTOR_start1`, `FUNCTOR_end1`), looked up in the
# database's functor table; the database is an argument. As upstream, a failure to build the arguments returns false with the
# wakeup state not restored.
"Tell the listeners of `def` that `retractall/1` is about to start (`:start`) or has ended (`:end`) on `head` (pl-event.c)."
function retractall_event(
    gd::PL_global_data{T}, ld::PL_local_data{T}, def::definition{T}, head::term_t,
    start::Symbol
)::Bool where {T}
    wstate = saveWakeup(ld, true)
    wstate === nothing && return false
    av = PL_new_term_refs(ld, 4)                                # closure, action, start/end, head
    start1 = lookupFunctorDef(ld.functors, _atom_word!(ld, mk_sym(T, start)), 1)

    if !(
        PL_put_atom(ld, av + 1, gd.modules[def.module_].atom) &&
        PL_put_term(ld, av + 2, head) &&
        PL_cons_functor(ld, av + 2, FUNCTOR_colon2, av + 1, av + 2) &&
        PL_cons_functor(ld, av + 2, start1, av + 2) &&
        PL_put_atom(ld, av + 1, mk_sym(T, :retractall))
    )
        return false
    end

    rc = call_event_list(gd, ld, def.events, 2, av)

    restoreWakeup(ld, wstate)

    return rc
end

# PORT: pl-event.c BeginPredDefs as PL_predicates_from_event
# `META` is PL_FA_TRANSPARENT (pl-event.c:805-810 at the pin).
"pl-event.c's registration table (`BeginPredDefs(event)`): prolog_listen/2,3 and prolog_unlisten/2."
const PL_predicates_from_event = (
    PL_extension(
        "prolog_listen", 2, pl_prolog_listen2_va, PL_FA_VARARGS | PL_FA_TRANSPARENT
    ),
    PL_extension(
        "prolog_listen", 3, pl_prolog_listen3_va, PL_FA_VARARGS | PL_FA_TRANSPARENT
    ),
    PL_extension(
        "prolog_unlisten", 2, pl_prolog_unlisten2_va, PL_FA_VARARGS | PL_FA_TRANSPARENT
    )
)
