# UPSTREAM: swipl-devel src/pl-mutex.c @ cbf4e1896275
# CLASS: code
# COPYRIGHT: Copyright (c)  2017-2023, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# PORTED FROM pl-mutex.c, exactly this: `with_mutex/2`, in the form pl-mutex.c itself has for a build
# without threads (the `#else` of `#ifdef O_PLMT`, pl-mutex.c:768-772). NOT PORTED: the mutex table
# (`initMutexes`, `get_mutex`, `PL_mutex_lock`) and the `mutex_*` predicates — the kernel has one
# thread, and `BeginPredDefs(mutex)` is empty without O_PLMT.

# PORT: pl-mutex.c pl_with_mutex
# (FRG("with_mutex", 2, pl_with_mutex, META|ISO), pl-ext.c:187; the meta declaration `+0`, pl-ext.c:406;
# pl-mutex.c:758-773 at the pin. The `#else` branch:
#     rval = callProlog(NULL, goal, PL_Q_PASS_EXCEPTION, NULL);       pl-mutex.c:771)
# DIVERGES: swipl 10.1.19 is built with O_PLMT and runs `get_mutex(mutex, &m, true)`, which creates the
# mutex when `mutex` names none and raises on a term that is no mutex name, then locks and unlocks `m`
# around the call. The kernel takes upstream's own single-thread branch: `with_mutex(M, G)` is `once(G)`
# and `mutex` is not examined. `NULL` for the module is `0`, as pl-pro.jl's `sig_atomic/1`.
"`with_mutex(+Mutex, :Goal)`: run `Goal` as once/1 while holding `Mutex`; here without a mutex (pl-mutex.c)."
function pl_with_mutex(
    ld::PL_local_data{T}, mutex::term_t, goal::term_t
)::foreign_t where {T}
    rval = callProlog(_query_gd(ld), ld, 0, goal, PL_Q_PASS_EXCEPTION)

    return rval ? FTRUE : FFALSE
end
