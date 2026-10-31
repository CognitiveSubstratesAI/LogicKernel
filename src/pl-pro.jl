# UPSTREAM: swipl-devel src/pl-pro.c @ cbf4e1896275
# CLASS: code
# COPYRIGHT: Copyright (c)  1985-2022, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
#
# PORTED FROM pl-pro.c, exactly these: `callProlog` — calling a goal from foreign code, in a query
# of its own — and `sig_atomic/1`, its first caller: boot/init.pl's `setup_call_cleanup/3` and
# `setup_call_catcher_cleanup/4` run their Setup goal through it, as once/1.
#
# NOT PORTED: the rest of pl-pro.c — the toplevel (`pl_break`, `query_loop`, `prologToplevel`),
# `abort/0`, `'$notrace'/1,2`, `'$restore_trace'/2`, `'$call_no_catch'/1`, `'$can_yield'/0`,
# `'$trap_gdb'/0`, the metacut `!/0` (`pl_metacut`), `checkStacks` and the C-stack queries.

# PORT: pl-pro.c callProlog
# DIVERGES: the database `gd` is an argument; `module` is an index into its module table (0 for
# NULL: the context module, `user` until R2). The functor is its name and arity. `ex` is a reference
# to a term_t (upstream: `term_t *ex`), `nothing` for NULL. NOT PORTED: `require_c_stack` (no C stack).
"""
    callProlog(gd, ld, module, goal, flags[, ex]) -> Bool

Call the goal in term reference `goal` once, in a query of its own with `flags`, keeping its
bindings (pl-pro.c). False when it fails or raises; with `PL_Q_PASS_EXCEPTION` the exception stays
pending. With `ex` (a reference to a term reference) an exception is handed to the caller in `ex[]`
(0: none) and cleared; the term references from `ex`'s on stay for the caller to reset. The caller
provides the foreign frame.
"""
function callProlog(
    gd::PL_global_data{T}, ld::PL_local_data{T}, module_::Int, goal::term_t, flags::UInt32,
    ex::Union{Nothing, Base.RefValue{Int}}
)::Bool where {T}
    @assert ld.lTop ==
        refFliP(ld.fliframes[ld.fli_context].base, ld.fliframes[ld.fli_context].size)

    reset = 0
    ex2 = 0
    if ex !== nothing
        ex2 = PL_new_term_ref(ld)
        ex[] = 0
    end

    g = PL_new_term_ref(ld)
    ok, m = PL_strip_module(gd, ld, goal, module_, g)
    ok || return false
    fd = PL_get_functor(ld, g)
    if fd === nothing                                   # !PL_get_functor(g, &fd)
        PL_error(ld, ERR_TYPE, mk_sym(T, :callable), goal)  # ERR_TYPE: `rewrite_callable` strips `goal`'s qualifiers
        ex !== nothing && (ex[] = ld.exception_term)

        PL_reset_term_refs(ld, g)
        return false
    end
    name, arity = fd

    # Quick check for sig_atomic(true) resulting from the call_cleanup series
    if arity == 0 && sym_key(name) == gd.subclause_names.atom_true     # fd == FUNCTOR_true0
        return true
    end

    proc = resolveProcedure(gd, name, arity, gd.modules[m])

    args = PL_new_term_refs(ld, arity)
    for n in 0:(arity - 1)
        _PL_get_arg(ld, n + 1, g, args + n)
    end

    if (flags & PL_Q_PASS_EXCEPTION) != 0
        used, rc = call_internal_det_foreign(gd, ld, proc, args)
        if used
            rval = rc != FFALSE && ld.exception_term == 0
            if !rval && ex !== nothing && ld.exception_term != 0
                PL_put_term(ld, ex2, ld.exception_term)
                ex[] = ex2
                reset = g
            end
            reset == 0 && (reset = ex2 != 0 ? ex2 : g)
            PL_reset_term_refs(ld, reset)
            return rval
        end
    end

    qid = PL_open_query(gd, ld, gd.modules[m], flags, proc, args)
    rval = PL_next_solution(gd, ld, qid) != 0

    if !rval && ex !== nothing
        qex = PL_exception(ld, qid)
        if qex != 0
            PL_put_term(ld, ex2, qex)
            ex[] = ex2
            reset = g
        else
            ex[] = 0
        end
    end

    PL_cut_query(ld, qid)
    if rval && ld.exception_term != 0
        if ex !== nothing
            PL_put_term(ld, ex2, ld.exception_term)
            PL_clear_exception(ld)
            ex[] = ex2
            reset = g
        end
        rval = false
    end

    reset == 0 && (reset = ex2 != 0 ? ex2 : g)
    PL_reset_term_refs(ld, reset)

    return rval
end

function callProlog(
    gd::PL_global_data{T}, ld::PL_local_data{T}, module_::Int, goal::term_t, flags::UInt32
)::Bool where {T}
    return callProlog(gd, ld, module_, goal, flags, nothing)
end

# PORT: pl-pro.c sig_atomic as pl_sig_atomic1_va
# (PRED_IMPL("sig_atomic", 1, sig_atomic, PL_FA_TRANSPARENT|PL_FA_SIG_ATOMIC))
# DIVERGES: NOT PORTED: `startCritical`/`endCritical` — blocking signals while the goal runs, and
# failing when it was aborted: the kernel has no signals.
"`sig_atomic(:Goal)`: execute `Goal` as once/1 (pl-pro.c; upstream: while blocking signals)."
function pl_sig_atomic1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    rval = callProlog(_query_gd(ld), ld, 0, A1, PL_Q_PASS_EXCEPTION)

    return rval ? FTRUE : FFALSE
end

# PORT: pl-pro.c BeginPredDefs as PL_predicates_from_pro
# DIVERGES: the ported entry only (upstream's table has eight, pl-pro.c:1060-1069).
"pl-pro.c's registration table (`BeginPredDefs(pro)`): the ported entry."
const PL_predicates_from_pro = (
    PL_extension(
        "sig_atomic", 1, pl_sig_atomic1_va,
        PL_FA_VARARGS | PL_FA_TRANSPARENT | PL_FA_SIG_ATOMIC
    ),
)
