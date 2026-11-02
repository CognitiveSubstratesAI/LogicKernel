# UPSTREAM: swipl-devel src/pl-event.c @ cbf4e1896275
# CLASS: code
# COPYRIGHT: Copyright (c)  2019-2026, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# EVENTS (pl-event.c), the registration side of `prolog_listen/2,3`: the options (`as(first|last)`, `name(Name)`),
# the event type (an event NAME: `abort`, `erase`, `break`, `frame_finished`, `untable`, `thread_start`, `thread_exit`,
# `this_thread_exit`) and the closure (`callable`, module-qualified) are checked as upstream checks them; boot/tabling.pl
# runs `prolog_listen(untable, …)` when it loads (BOOTPRED3).
#
# LEFT TO EV1: the event lists themselves (`GD->event.hook`, `LD->event.hook`, `event_callback`), the calling side
# (`callEventHook`), `prolog_unlisten/2`, and a listener on a PREDICATE (`proc->definition->events`): each is a new
# field of the global or local data or of the definition, a struct change. Until EV1 a registration is checked and
# accepted, and no hook is kept or run.

# PORT: pl-event.c PL_events
# DIVERGES: `(name, argc)` of each distinct name: upstream's table repeats `erase` and `break` per event id and keeps a
# list location, EV1's.
"The events `prolog_listen/2,3` accepts, as `(name, argument count)` (pl-event.c `PL_events`: the O_ENGINES build's)."
const PL_events = (
    (:abort, 0), (:erase, 1), (:break, 3), (:frame_finished, 1), (:untable, 1),
    (:thread_start, 1), (:thread_exit, 1), (:this_thread_exit, 0)
)

# PORT: pl-event.c prolog_listen_options
const prolog_listen_options = (
    PL_option_t(:as, OPT_ATOM),
    PL_option_t(:name, OPT_ATOM)
)

# PORT: pl-event.c get_callback
# DIVERGES: returns `(ok, module index)`; the module is `PL_strip_module`'s (0: the context module).
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
# DIVERGES: the closure is checked (`get_callback`) and the hook is not kept, see the file header (EV1).
"Register the closure `closure` as a listener of an event of `argc` arguments (pl-event.c)."
function add_event_hook(
    gd::PL_global_data{T}, ld::PL_local_data{T}, name::Union{Nothing, T}, last::Bool,
    closure::term_t, argc::Int
)::Bool where {T}
    t = PL_new_term_ref(ld)
    ok, _ = get_callback(gd, ld, closure, t)
    ok || return false

    return true
end

# PORT: pl-event.c get_event_listp
# DIVERGES: returns `(ok, argc)` where upstream writes the list's location through `listpp`; the event lists are
# EV1's. A listener on a predicate (`arity != 0`) is refused by name (EV1: `Definition.events`).
"Check the event type `type` (pl-event.c): the argument count of the event, or `nothing` after raising the error."
function get_event_listp(
    ld::PL_local_data{T}, type::term_t
)::Union{Nothing, Int} where {T}
    na = PL_get_name_arity(ld, type)

    if na !== nothing
        name, arity = na

        if arity == 0
            for (ename, eargc) in PL_events
                if name == mk_sym(T, ename)
                    return eargc
                end
            end
        else
            throw(
                NotPortedError{T}(
                    mk_sym(T, :prolog_listen), "prolog_listen/2,3 on a predicate (get_procedure GP_NAMEARITY)",
                    "EV1"
                )
            )
        end

        PL_domain_error(ld, "event", type)
        return nothing
    end

    PL_type_error(ld, "callable", type)
    return nothing
end

# PORT: pl-event.c prolog_listen
# DIVERGES: `options` is 0 for NULL (upstream: a null `term_t`).
"The body of `prolog_listen/2,3`: check the options, the event type and the closure (pl-event.c)."
function prolog_listen(
    gd::PL_global_data{T}, ld::PL_local_data{T}, type::term_t, closure::term_t,
    options::term_t
)::Bool where {T}
    as = mk_sym(T, :first)
    name = nothing

    if options != 0
        vals = PL_scan_options(ld, options, 0, "prolog_listen_option", prolog_listen_options)
        vals === nothing && return false
        vals[1] === nothing || (as = vals[1]::T)
        vals[2] === nothing || (name = vals[2]::T)
    end

    if !(as == mk_sym(T, :first) || as == mk_sym(T, :last))
        ex = PL_new_term_ref(ld)
        return PL_put_atom(ld, ex, as) && PL_domain_error(ld, "as", ex)
    end

    argc = get_event_listp(ld, type)
    argc === nothing && return false

    return add_event_hook(gd, ld, name, as == mk_sym(T, :last), closure, argc)
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

# PORT: pl-event.c BeginPredDefs as PL_predicates_from_event
# DIVERGES: the two prolog_listen entries only (upstream's table: pl-event.c:805-810); `META` is PL_FA_TRANSPARENT.
"pl-event.c's registration table (`BeginPredDefs(event)`): prolog_listen/2,3."
const PL_predicates_from_event = (
    PL_extension("prolog_listen", 2, pl_prolog_listen2_va, PL_FA_VARARGS | PL_FA_TRANSPARENT),
    PL_extension("prolog_listen", 3, pl_prolog_listen3_va, PL_FA_VARARGS | PL_FA_TRANSPARENT)
)
