# UPSTREAM: swipl-devel src/pl-error.c @ bae881a24a3f
# UPSTREAM: swipl-devel src/pl-error.h @ bae881a24a3f
# CLASS: code
# COPYRIGHT: Copyright (c)  1997-2024, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# What the kernel takes from SWI-Prolog's error reporting (pl-error.c): building an ISO error term
# `error(Formal, context(Name/Arity, Msg))` for the running predicate and raising it — so far for
# the occurs-check error alone, which head unification raises under `occurs_check=error` (V4a). The
# other error codes arrive with the code that raises them (V5).

# PORT: pl-error.h PL_error_code
# DIVERGES: the one code raised so far; upstream's enum has some forty.
"The kinds of error `PL_error` builds (pl-error.h); only the occurs-check error is ported."
@enum PL_error_code::UInt8 begin
    ERR_OCCURS_CHECK                # Word, Word
end

# PORT: pl-error.c PL_error
# DIVERGES: the occurs-check error only, with its two terms as arguments where upstream passes cells
# through varargs; no predicate name or message is given by the caller (`pred`, `msg`), so the
# context is the CALLER's — `environment_frame`'s predicate — as `Name/Arity` (one module, so never
# qualified), and the message an unbound variable. Raised with `PL_raise_exception`, never thrown
# (`do_throw` is only for errors raised outside the VM).
"""
    PL_error(gd, ld, ERR_OCCURS_CHECK, var, term) -> false

Raise `error(occurs_check(var, term), context(Name/Arity, _))` for the predicate the current frame
runs (pl-error.c). Returns false, as upstream; an exception already pending is not overruled.
"""
function PL_error(
    gd::PL_global_data{T}, ld::PL_local_data{T}, id::PL_error_code, p1::T, p2::T
)::Bool where {T}
    if ld.exception_term != 0               # do not overrule older exception
        return false
    end

    caller = ld.environment_frame != 0 ? ld.frames[ld.environment_frame].predicate : nothing

    fid = PL_open_foreign_frame(ld)
    fid == 0 && error("Cannot report error: no memory")   # goto nomem

    except = new_term_ref(ld)
    formal = new_term_ref(ld)
    swi = new_term_ref(ld)

    @assert id == ERR_OCCURS_CHECK
    ld.slots[formal + 1] = mk_expr(T, T[mk_sym(T, :occurs_check), p1, p2])

    if caller !== nothing                   # build SWI-Prolog context term
        msgterm = mk_var(T, fresh_var_keys!(1))
        predterm = mk_expr(
            T, T[mk_sym(T, :/), (caller::Definition{T}).name, mk_gnd(T, caller.arity)]
        )
        ld.slots[swi + 1] = mk_expr(T, T[mk_sym(T, :context), predterm, msgterm])
    end

    ld.slots[except + 1] = mk_expr(
        T, T[mk_sym(T, :error), ld.slots[formal + 1], ld.slots[swi + 1]]
    )

    rc = PL_raise_exception(ld, except)

    PL_close_foreign_frame(ld, fid)

    return rc
end
