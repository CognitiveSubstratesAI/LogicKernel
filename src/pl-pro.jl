# UPSTREAM: swipl-devel src/pl-pro.c @ 8e1bc1110be4
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
# NULL: the context module, `user` until R2). The functor is its name and arity. NOT PORTED: the
# `ex` argument — handing the query's exception to the caller, which `sig_atomic/1` does not ask
# for (it passes NULL) — and `require_c_stack` (no C stack).
"""
    callProlog(gd, ld, module, goal, flags) -> Bool

Call the goal in term reference `goal` once, in a query of its own with `flags`, keeping its
bindings (pl-pro.c). False when it fails or raises; with `PL_Q_PASS_EXCEPTION` the exception stays
pending. The caller provides the foreign frame.
"""
function callProlog(
    gd::PL_global_data{T}, ld::PL_local_data{T}, module_::Int, goal::term_t, flags::UInt32
)::Bool where {T}
    @assert ld.lTop ==
        refFliP(ld.fliframes[ld.fli_context].base, ld.fliframes[ld.fli_context].size)

    g = PL_new_term_ref(ld)
    ok, m = PL_strip_module(gd, ld, goal, module_, g)
    ok || return false
    fd = PL_get_functor(ld, g)
    if fd === nothing                                   # !PL_get_functor(g, &fd)
        PL_type_error(ld, "callable", goal)

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

    qid = PL_open_query(gd, ld, gd.modules[m], flags, proc, args)
    rval = PL_next_solution(gd, ld, qid) != 0

    PL_cut_query(ld, qid)
    if rval && ld.exception_term != 0
        rval = false
    end

    PL_reset_term_refs(ld, g)

    return rval
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
# DIVERGES: the ported entry only (upstream's table has eight, pl-pro.c:1045-1054).
"pl-pro.c's registration table (`BeginPredDefs(pro)`): the ported entry."
const PL_predicates_from_pro = (
    PL_extension(
        "sig_atomic", 1, pl_sig_atomic1_va,
        PL_FA_VARARGS | PL_FA_TRANSPARENT | PL_FA_SIG_ATOMIC
    ),
)
