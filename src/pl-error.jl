# UPSTREAM: swipl-devel src/pl-error.c @ bae881a24a3f
# UPSTREAM: swipl-devel src/pl-error.h @ bae881a24a3f
# CLASS: code
# COPYRIGHT: Copyright (c)  1997-2024, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# What the kernel takes from SWI-Prolog's error reporting (pl-error.c): building an ISO error term
# `error(Formal, context(Name/Arity, Msg))` for the running predicate and raising it — the
# occurs-check error, which unification raises under `occurs_check=error` (V4a), and since V5a2 the
# codes the first built-ins raise — instantiation, type and domain errors — and since V5b the
# undefined procedure's existence error. The other codes arrive with the code that raises them.
#
# DIVERGES (file-wide): upstream's `PL_error` is ONE variadic function that reads its arguments by
# the code (`va_arg`); here each code family is a METHOD with typed arguments — no `Vararg{Any}` —
# and the shared head and tail are `_PL_error_open` and `_PL_error_close!`. No predicate name or
# message is given by a caller yet (`pred`, `msg`), so the context is the CALLER's — the running
# frame's predicate — written `Name/Arity`, never module-qualified: whether built-ins' contexts read
# `system:Name/Arity`, as swipl's do (`unify_definition`), is the user's open question Q-A (V5c).
# The formal and the context are BUILT (`mk_expr`) where upstream unifies them into fresh term
# references (`PL_unify_term`), which cannot fail here. Raised with `PL_raise_exception`, never
# thrown (`do_throw` is only for errors raised outside the VM).

# PORT: pl-error.h PL_error_code
# DIVERGES: the codes raised so far; upstream's enum has some forty.
"The kinds of error `PL_error` builds (pl-error.h); those raised so far."
@enum PL_error_code::UInt8 begin
    ERR_INSTANTIATION               # void
    ERR_TYPE                        # atom_t expected, term_t actual
    ERR_CHARS_TYPE                  # char *expected, term_t actual
    ERR_DOMAIN                      # atom_t domain, term_t value
    ERR_OCCURS_CHECK                # Word, Word
    ERR_UNDEFINED_PROC              # Definition def, Definition clr
end

# The head of upstream's `PL_error`: nothing if an exception is pending ("do not overrule older
# exception"), else the caller (the running frame's predicate, or `nothing`), the foreign frame
# and the three term references (`except`, `formal`, `swi`).
function _PL_error_open(
    ld::PL_local_data{T}
)::Union{Nothing, Tuple{Union{Nothing, Definition{T}}, Int, Int, Int, Int}} where {T}
    if ld.exception_term != 0               # do not overrule older exception
        return nothing
    end
    caller = ld.environment_frame != 0 ? ld.frames[ld.environment_frame].predicate : nothing
    fid = PL_open_foreign_frame(ld)
    fid == 0 && error("Cannot report error: no memory")   # goto nomem
    except = new_term_ref(ld)
    formal = new_term_ref(ld)
    swi = new_term_ref(ld)
    return (caller, fid, except, formal, swi)
end

# The tail of upstream's `PL_error`: the SWI-Prolog context term for the caller, the error term,
# and raising it; returns false (`PL_raise_exception`'s result).
function _PL_error_close!(
    ld::PL_local_data{T}, caller::Union{Nothing, Definition{T}}, fid::Int, except::Int,
    formal::Int, swi::Int
)::Bool where {T}
    if caller !== nothing                   # build SWI-Prolog context term
        msgterm = mk_var(T, fresh_var_keys!(1))
        predterm = mk_expr(T, T[mk_sym(T, :/), caller.name, mk_gnd(T, caller.arity)])
        ld.slots[swi + 1] = mk_expr(T, T[mk_sym(T, :context), predterm, msgterm])
    end
    ld.slots[except + 1] = mk_expr(
        T, T[mk_sym(T, :error), ld.slots[formal + 1], ld.slots[swi + 1]]
    )
    rc = PL_raise_exception(ld, except)
    PL_close_foreign_frame(ld, fid)
    return rc
end

# PORT: pl-error.c PL_error
"""
    PL_error(ld, ERR_OCCURS_CHECK, var, term) -> false

Raise `error(occurs_check(var, term), context(Name/Arity, _))` for the predicate the current frame
runs (pl-error.c). Returns false, as upstream; an exception already pending is not overruled.
"""
function PL_error(ld::PL_local_data{T}, id::PL_error_code, p1::T, p2::T)::Bool where {T}
    h = _PL_error_open(ld)
    h === nothing && return false
    caller, fid, except, formal, swi = h
    @assert id == ERR_OCCURS_CHECK
    ld.slots[formal + 1] = mk_expr(T, T[mk_sym(T, :occurs_check), p1, p2])
    return _PL_error_close!(ld, caller, fid, except, formal, swi)
end

"""
    PL_error(ld, ERR_INSTANTIATION) -> false

Raise `error(instantiation_error, context(Name/Arity, _))` (pl-error.c).
"""
function PL_error(ld::PL_local_data{T}, id::PL_error_code)::Bool where {T}
    h = _PL_error_open(ld)
    h === nothing && return false
    caller, fid, except, formal, swi = h
    @assert id == ERR_INSTANTIATION
    ld.slots[formal + 1] = mk_sym(T, :instantiation_error)          # err_instantiation:
    return _PL_error_close!(ld, caller, fid, except, formal, swi)
end

"""
    PL_error(ld, ERR_TYPE | ERR_DOMAIN, atom, actual::term_t) -> false

Raise `error(type_error(Atom, Actual), …)` or `error(domain_error(Atom, Actual), …)` — or
`instantiation_error` when `actual` holds a variable (for `ERR_TYPE`, unless the expected type is
`variable`) (pl-error.c).
"""
function PL_error(
    ld::PL_local_data{T}, id::PL_error_code, a::T, actual::term_t
)::Bool where {T}
    h = _PL_error_open(ld)
    h === nothing && return false
    caller, fid, except, formal, swi = h
    var = PL_is_variable(ld, actual)
    if id == ERR_TYPE                                               # (ATOM_callable: not raised)
        if var && !(kind(a) === SYM && sym_key(a) == sym_key(mk_sym(T, :variable)))
            ld.slots[formal + 1] = mk_sym(T, :instantiation_error)  # goto err_instantiation
        else
            ld.slots[formal + 1] = mk_expr(
                T, T[mk_sym(T, :type_error), a, ld.slots[actual + 1]]
            )
        end
    else
        @assert id == ERR_DOMAIN
        if var
            ld.slots[formal + 1] = mk_sym(T, :instantiation_error)  # goto err_instantiation
        else
            ld.slots[formal + 1] = mk_expr(
                T, T[mk_sym(T, :domain_error), a, ld.slots[actual + 1]]
            )
        end
    end
    return _PL_error_close!(ld, caller, fid, except, formal, swi)
end

"""
    PL_error(ld, ERR_CHARS_TYPE, expected::String, actual::term_t) -> false

Raise `error(type_error(Expected, Actual), …)`, `Expected` the atom of that text, or
`instantiation_error` when `actual` holds a variable and `expected` is not `"variable"` (pl-error.c).
"""
function PL_error(
    ld::PL_local_data{T}, id::PL_error_code, expected::String, actual::term_t
)::Bool where {T}
    h = _PL_error_open(ld)
    h === nothing && return false
    caller, fid, except, formal, swi = h
    @assert id == ERR_CHARS_TYPE
    if PL_is_variable(ld, actual) && expected != "variable"
        ld.slots[formal + 1] = mk_sym(T, :instantiation_error)      # goto err_instantiation
    else
        ld.slots[formal + 1] = mk_expr(
            T, T[mk_sym(T, :type_error), mk_sym(T, Symbol(expected)), ld.slots[actual + 1]]
        )
    end
    return _PL_error_close!(ld, caller, fid, except, formal, swi)
end

"""
    PL_error(ld, ERR_UNDEFINED_PROC, def, clr) -> false

Raise `error(existence_error(procedure, Name/Arity), context(Caller, _))` for the undefined predicate
`def`; `clr`, when given, replaces the running frame's predicate as the caller (pl-error.c).
"""
function PL_error(
    ld::PL_local_data{T}, id::PL_error_code, def::Definition{T},
    clr::Union{Nothing, Definition{T}}
)::Bool where {T}
    h = _PL_error_open(ld)
    h === nothing && return false
    caller, fid, except, formal, swi = h
    @assert id == ERR_UNDEFINED_PROC
    pred = new_term_ref(ld)
    if clr !== nothing
        caller = clr
    end
    # unify_definition(MODULE_user, pred, def, 0, GP_NAMEARITY): `Name/Arity` (see the file header)
    ld.slots[pred + 1] = mk_expr(T, T[mk_sym(T, :/), def.name, mk_gnd(T, def.arity)])
    ld.slots[formal + 1] = mk_expr(
        T, T[mk_sym(T, :existence_error), mk_sym(T, :procedure), ld.slots[pred + 1]]
    )
    return _PL_error_close!(ld, caller, fid, except, formal, swi)
end

# PORT: pl-error.c PL_type_error
"Raise `type_error(Expected, Actual)` (pl-error.c `PL_type_error`); false."
PL_type_error(ld::PL_local_data{T}, expected::String, actual::term_t) where {T} =
    PL_error(ld, ERR_CHARS_TYPE, expected, actual)

# PORT: pl-error.c PL_domain_error
"Raise `domain_error(Expected, Actual)` (pl-error.c `PL_domain_error`); false."
PL_domain_error(ld::PL_local_data{T}, expected::String, actual::term_t) where {T} =
    PL_error(ld, ERR_DOMAIN, mk_sym(T, Symbol(expected)), actual)
