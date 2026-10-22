# UPSTREAM: swipl-devel src/pl-error.c @ 8e1bc1110be4
# UPSTREAM: swipl-devel src/pl-error.h @ 8e1bc1110be4
# CLASS: code
# COPYRIGHT: Copyright (c)  1997-2024, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# What the kernel takes from SWI-Prolog's error reporting (pl-error.c): building an ISO error term
# `error(Formal, context(Name/Arity, Msg))` for the running predicate and raising it — the
# occurs-check error, which unification raises under `occurs_check=error` (V4a), and since V5a2 the
# codes the first built-ins raise — instantiation, type and domain errors — since V5b the
# undefined procedure's existence error, since V6c arithmetic's: an expression that is not
# evaluable and the float checks' evaluation errors, and since V9c the clause compiler's and
# `assert_term`'s: a representation error, the `callable` type error and the static procedure's
# permission error. The other codes arrive with the code that raises them.
#
# DIVERGES (file-wide): upstream's `PL_error` is ONE variadic function that reads its arguments by
# the code (`va_arg`); here each code family is a METHOD with typed arguments — no `Vararg{Any}` —
# and the shared head and tail are `_PL_error_open` and `_PL_error_close!`. Upstream's leading
# `pred`, `arity`, `msg` are taken by the methods that need them (since V6c; the others pass none),
# `pred` and `msg` as Strings, EMPTY for upstream's NULL (a `Union` would dispatch at run time):
# the context is `pred/arity` when given, else the CALLER — the running frame's predicate — written by
# `unify_definition` from `user`: a built-in's reads `system:Name/Arity`, as swipl's does (since V5c,
# as decided since Q-A). The database is the running query's (`ld.GD`): a definition names its module
# by its index into the database's table.
# The formal and the context are laid out on the cells into fresh term references — upstream's
# `PL_unify_term(fresh, PL_FUNCTOR, F, …)` as puts and one `PL_cons_functor` (f3b-4: the same term,
# and it cannot fail here; `PL_unify_term` is not ported). Raised with `PL_raise_exception`, never
# thrown (upstream's `do_throw` is set for one code only, `ERR_CLOSED_STREAM`, not ported). Sets
# `LD->exception.processing`, which lets the local stack use its spare (since V5d).

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
    ERR_NOT_EVALUABLE               # functor_t func
    ERR_AR_UNDEF                    # void
    ERR_AR_OVERFLOW                 # void
    ERR_AR_UNDERFLOW                # void
    ERR_AR_RAT_OVERFLOW             # void
    ERR_AR_TYPE                     # atom_t expected, Number value
    ERR_REPRESENTATION              # atom_t what
    ERR_MODIFY_STATIC_PROC          # Procedure proc
    ERR_PERMISSION                  # atom_t, atom_t, term_t
    ERR_PERMISSION_PROC             # op, type, Definition
    ERR_EXISTENCE                   # atom_t type, term_t obj
    ERR_STREAM_OP                   # atom_t action, term_t obj
    ERR_DETERMINISM                 # Definition def, atom_t expected, atom_t found, atom_t decl
    ERR_DET_GOAL                    # term_t goal, atom_t expected, atom_t found
    ERR_DIV_BY_ZERO                 # void
    ERR_AR_DOMAIN                   # atom_t domain, Number value
    ERR_EVALUATION                  # atom_t what
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
    ld.exception_processing = true          # allow using spare stack
    caller = ld.environment_frame != 0 ? ld.frames[ld.environment_frame].predicate : nothing
    fid = PL_open_foreign_frame(ld)
    fid == 0 && error("Cannot report error: no memory")   # goto nomem
    except = new_term_ref(ld)
    formal = new_term_ref(ld)
    swi = new_term_ref(ld)
    return (caller, fid, except, formal, swi)
end

# The tail of upstream's `PL_error`: the SWI-Prolog context term — `pred/arity` when given, else
# the caller; `msg` as an atom, else a fresh variable — the error term, and raising it; returns
# false (`PL_raise_exception`'s result).
_PL_error_close!(
    ld::PL_local_data{T}, caller::Union{Nothing, Definition{T}}, fid::Int, except::Int,
    formal::Int, swi::Int
) where {T} = _PL_error_close!(ld, caller, fid, except, formal, swi, "", 0, "")

function _PL_error_close!(
    ld::PL_local_data{T}, caller::Union{Nothing, Definition{T}}, fid::Int, except::Int,
    formal::Int, swi::Int, pred::String, arity::Int, msg::String
)::Bool where {T}
    if !isempty(pred) || !isempty(msg) || caller !== nothing        # build SWI-Prolog context term
        predterm = new_term_ref(ld)
        msgterm = new_term_ref(ld)                                  # if ( !msgterm ) …
        if !isempty(pred)
            PL_cons_functor(                                        # PL_unify_term(predterm, …divide2,
                ld, predterm, _err_functor(ld, :/, 2),              #   PL_CHARS, pred, PL_INT, arity)
                _err_atom(ld, mk_sym(T, Symbol(pred))), _err_int(ld, arity)
            )
        elseif caller !== nothing
            gd = _query_gd(ld)
            unify_definition(gd, ld, MODULE_user(gd), predterm, caller, 0, GP_NAMEARITY)
        end
        isempty(msg) || PL_put_atom(ld, msgterm, mk_sym(T, Symbol(msg)))   # PL_put_chars(msgterm, …)
        PL_cons_functor(ld, swi, _err_functor(ld, :context, 2), predterm, msgterm)
    end
    PL_cons_functor(ld, except, _err_functor(ld, :error, 2), formal, swi)
    rc = PL_raise_exception(ld, except)
    PL_close_foreign_frame(ld, fid)
    return rc
end

# ORIGINAL (f3b-4): upstream's predefined `FUNCTOR_<name><arity>` — the functor word of `name/arity`.
"The functor word of `name/arity` (upstream's `FUNCTOR_…` constants)."
@inline _err_functor(ld::PL_local_data{T}, name::Symbol, arity::Int) where {T} =
    lookupFunctorDef(ld.functors, _atom_word!(ld, mk_sym(T, name)), arity)

# ORIGINAL (f3b-4): `PL_unify_term`'s `PL_ATOM, a` argument — a new term reference holding the atom.
"A new term reference holding the atom `a` (a `PL_unify_term` argument)."
function _err_atom(ld::PL_local_data{T}, a::T)::term_t where {T}
    r = new_term_ref(ld)
    PL_put_atom(ld, r, a)
    return r
end

# ORIGINAL (f3b-4): `PL_unify_term`'s `PL_INT, i` argument — a new term reference holding the integer.
"A new term reference holding the integer `i` (a `PL_unify_term` argument)."
function _err_int(ld::PL_local_data{T}, i::Int)::term_t where {T}
    r = new_term_ref(ld)
    PL_put_int64(ld, r, i)
    return r
end

# ORIGINAL (f3b-4): `PL_unify_term`'s `PL_FUNCTOR_CHARS, name, N, …` into a new term reference.
"A new term reference holding the compound `name(a…)` of the terms the references `a…` hold."
function _message_term(
    ld::PL_local_data{T}, name::Symbol, a::Vararg{term_t, N}
)::term_t where {T, N}
    t = new_term_ref(ld)
    PL_cons_functor(ld, t, _err_functor(ld, name, N), a...)
    return t
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
    setSlotValue!(ld, formal + 1, mk_expr(T, T[mk_sym(T, :occurs_check), p1, p2]))
    return _PL_error_close!(ld, caller, fid, except, formal, swi)
end

"""
    PL_error(ld, ERR_OCCURS_CHECK, var::loc, term::loc) -> false

As the form on terms, the two terms DEREFERENCED locations `(k, w, p)` (upstream's `Word`s), the
error built on the cells through `pushWordAsTermRef` (pl-error.c; f3b-4).
"""
function PL_error(
    ld::PL_local_data{T}, id::PL_error_code, p1::Tuple{UInt8, word, Int},
    p2::Tuple{UInt8, word, Int}
)::Bool where {T}
    h = _PL_error_open(ld)
    h === nothing && return false
    caller, fid, except, formal, swi = h
    @assert id == ERR_OCCURS_CHECK
    PL_cons_functor(                                    # PL_unify_term(formal, …occurs_check2,
        ld, formal, _err_functor(ld, :occurs_check, 2),
        pushWordAsTermRef(ld, p1), pushWordAsTermRef(ld, p2)
    )
    popTermRef(ld)
    popTermRef(ld)
    return _PL_error_close!(ld, caller, fid, except, formal, swi)
end

"""
    PL_error(ld, ERR_INSTANTIATION | ERR_AR_UNDEF | ERR_AR_OVERFLOW | ERR_AR_UNDERFLOW |
             ERR_AR_RAT_OVERFLOW) -> false

Raise `error(instantiation_error, context(Name/Arity, _))`, or an arithmetic evaluation error —
`evaluation_error(undefined)`, `(float_overflow)`, `(float_underflow)`, `(rational_overflow)` —
(pl-error.c).
"""
function PL_error(ld::PL_local_data{T}, id::PL_error_code)::Bool where {T}
    h = _PL_error_open(ld)
    h === nothing && return false
    caller, fid, except, formal, swi = h
    if id == ERR_INSTANTIATION
        PL_put_atom(ld, formal, mk_sym(T, :instantiation_error))    # err_instantiation:
    else                                                            # evaluation_error(formal, …)
        what = if id == ERR_AR_UNDEF
            :undefined
        elseif id == ERR_AR_OVERFLOW
            :float_overflow
        elseif id == ERR_AR_UNDERFLOW
            :float_underflow
        else
            :rational_overflow
        end
        @assert id == ERR_AR_UNDEF || id == ERR_AR_OVERFLOW || id == ERR_AR_UNDERFLOW ||
            id == ERR_AR_RAT_OVERFLOW
        PL_cons_functor(                                # evaluation_error(formal, which)
            ld, formal, _err_functor(ld, :evaluation_error, 1),
            _err_atom(ld, mk_sym(T, what))
        )
    end
    return _PL_error_close!(ld, caller, fid, except, formal, swi)
end

"""
    PL_error(ld, pred, arity, msg, ERR_AR_TYPE | ERR_AR_DOMAIN, expected, num::number) -> false

Raise `error(type_error(Expected, Num), context(pred/arity, …))`, or for `ERR_AR_DOMAIN`
`error(domain_error(Domain, Num), …)`, for the number `num` an arithmetic function cannot take
(pl-error.c `ERR_AR_TYPE`, `ERR_AR_DOMAIN`).
"""
function PL_error(
    ld::PL_local_data{T}, pred::String, arity::Int, msg::String, id::PL_error_code,
    expected::T, num::number
)::Bool where {T}
    h = _PL_error_open(ld)
    h === nothing && return false
    caller, fid, except, formal, swi = h
    @assert id == ERR_AR_TYPE || id == ERR_AR_DOMAIN
    actual = new_term_ref(ld)
    _PL_put_number(ld, actual, num)                                 # _PL_put_number(actual, num)
    PL_cons_functor(
        ld, formal, _err_functor(ld, id == ERR_AR_TYPE ? :type_error : :domain_error, 2),
        _err_atom(ld, expected), actual
    )
    return _PL_error_close!(ld, caller, fid, except, formal, swi, pred, arity, msg)
end

"""
    PL_error(ld, pred, arity, msg, ERR_DIV_BY_ZERO) -> false

Raise `error(evaluation_error(zero_divisor), context(pred/arity, …))` (pl-error.c).
"""
function PL_error(
    ld::PL_local_data{T}, pred::String, arity::Int, msg::String, id::PL_error_code
)::Bool where {T}
    h = _PL_error_open(ld)
    h === nothing && return false
    caller, fid, except, formal, swi = h
    @assert id == ERR_DIV_BY_ZERO
    PL_cons_functor(                                    # evaluation_error(formal, ATOM_zero_divisor)
        ld, formal, _err_functor(ld, :evaluation_error, 1),
        _err_atom(ld, mk_sym(T, :zero_divisor))
    )
    return _PL_error_close!(ld, caller, fid, except, formal, swi, pred, arity, msg)
end

"""
    PL_error(ld, ERR_NOT_EVALUABLE, (name, arity)) -> false

Raise `error(type_error(evaluable, Name/Arity), …)` for the function `name/arity` (pl-error.c).
"""
function PL_error(ld::PL_local_data{T}, id::PL_error_code, f::Tuple{T, Int})::Bool where {T}
    h = _PL_error_open(ld)
    h === nothing && return false
    caller, fid, except, formal, swi = h
    @assert id == ERR_NOT_EVALUABLE
    actual = new_term_ref(ld)                                       # put_name_arity(actual, f)
    PL_cons_functor(
        ld, actual, _err_functor(ld, :/, 2), _err_atom(ld, f[1]), _err_int(ld, f[2])
    )
    PL_cons_functor(
        ld, formal, _err_functor(ld, :type_error, 2), _err_atom(ld, mk_sym(T, :evaluable)),
        actual
    )
    return _PL_error_close!(ld, caller, fid, except, formal, swi)
end

# PORT: pl-error.c rewrite_callable
# DIVERGES: returns the expected type, where upstream writes it through `expected`; `actual` is
# rewritten in place, as upstream's `PL_put_term(actual, a)`.
"""
    rewrite_callable(ld, expected, actual) -> expected

For a `callable` type error, strip the qualifiers `M:` off the culprit in term reference `actual`
while each `M` is an atom; at one that is not, the culprit becomes `M` and the expected type
`atom` (pl-error.c). Gives up after 100 levels on a cyclic culprit.
"""
function rewrite_callable(ld::PL_local_data{T}, expected::T, actual::term_t)::T where {T}
    a = 0
    loops = 0
    colon = mk_sym(T, :(:))
    while PL_is_functor(ld, actual, colon, 2)                       # PL_is_functor(actual, FUNCTOR_colon2)
        if a == 0
            a = PL_new_term_ref(ld)
        end
        _PL_get_arg(ld, 1, actual, a)
        if !PL_is_atom(ld, a)
            PL_put_term(ld, actual, a)
            return mk_sym(T, :atom)                                 # *expected = ATOM_atom
        else
            _PL_get_arg(ld, 2, actual, a)
            PL_put_term(ld, actual, a)
        end
        loops += 1
        if loops > 100 && !is_acyclic_cells(ld, -(actual + 1))    # on the cells (L1d step 3)
            break
        end
    end
    return expected
end

"""
    PL_error(ld, ERR_TYPE | ERR_DOMAIN | ERR_EXISTENCE | ERR_STREAM_OP, atom, actual::term_t) -> false

Raise `error(type_error(Atom, Actual), …)` or `error(domain_error(Atom, Actual), …)` — or
`instantiation_error` when `actual` holds a variable (for `ERR_TYPE`, unless the expected type is
`variable`) — or `error(existence_error(Atom, Actual), …)`, or `error(io_error(Atom, Actual), …)`
(pl-error.c). A `callable` culprit is rewritten first (`rewrite_callable`).
"""
PL_error(ld::PL_local_data{T}, id::PL_error_code, a::T, actual::term_t) where {T} =
    PL_error(ld, "", 0, "", id, a, actual)

"""
    PL_error(ld, pred, arity, msg, ERR_TYPE | ERR_DOMAIN, atom, actual::term_t) -> false

As the form without them, with upstream's leading `pred`, `arity` and `msg` (empty: not given): the
context names `pred/arity` when `pred` is given, and holds `msg` as an atom (pl-error.c).
"""
function PL_error(
    ld::PL_local_data{T}, pred::String, arity::Int, msg::String, id::PL_error_code, a::T,
    actual::term_t
)::Bool where {T}
    h = _PL_error_open(ld)
    h === nothing && return false
    caller, fid, except, formal, swi = h
    if id == ERR_TYPE && kind(a) === SYM && sym_key(a) == sym_key(mk_sym(T, :callable))
        a = rewrite_callable(ld, a, actual)
    end
    var = PL_is_variable(ld, actual)
    if id == ERR_TYPE
        if var && !(kind(a) === SYM && sym_key(a) == sym_key(mk_sym(T, :variable)))
            PL_put_atom(ld, formal, mk_sym(T, :instantiation_error))    # goto err_instantiation
        else
            PL_cons_functor(
                ld, formal, _err_functor(ld, :type_error, 2), _err_atom(ld, a), actual
            )
        end
    elseif id == ERR_EXISTENCE                      # (since R1e's write/1 family: streams)
        PL_cons_functor(
            ld, formal, _err_functor(ld, :existence_error, 2), _err_atom(ld, a), actual
        )
    elseif id == ERR_STREAM_OP                      # (since R1e's write/1 family)
        PL_cons_functor(
            ld, formal, _err_functor(ld, :io_error, 2), _err_atom(ld, a), actual
        )
    else
        @assert id == ERR_DOMAIN
        if var
            PL_put_atom(ld, formal, mk_sym(T, :instantiation_error))    # goto err_instantiation
        else
            PL_cons_functor(
                ld, formal, _err_functor(ld, :domain_error, 2), _err_atom(ld, a), actual
            )
        end
    end
    return _PL_error_close!(ld, caller, fid, except, formal, swi, pred, arity, msg)
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
        PL_put_atom(ld, formal, mk_sym(T, :instantiation_error))        # goto err_instantiation
    else
        PL_cons_functor(                                # PL_FUNCTOR, FUNCTOR_type_error2,
            ld, formal, _err_functor(ld, :type_error, 2),   # PL_CHARS, expected, PL_TERM, actual
            _err_atom(ld, mk_sym(T, Symbol(expected))), actual
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
    gd = _query_gd(ld)
    unify_definition(gd, ld, MODULE_user(gd), pred, def, 0, GP_NAMEARITY)
    PL_cons_functor(
        ld, formal, _err_functor(ld, :existence_error, 2),
        _err_atom(ld, mk_sym(T, :procedure)), pred
    )
    return _PL_error_close!(ld, caller, fid, except, formal, swi)
end

"""
    PL_error(ld, ERR_REPRESENTATION, what) -> false

Raise `error(representation_error(What), context(Name/Arity, _))` (pl-error.c).
"""
PL_error(ld::PL_local_data{T}, id::PL_error_code, what::T) where {T} =
    PL_error(ld, "", 0, "", id, what)

"""
    PL_error(ld, pred, arity, msg, ERR_REPRESENTATION | ERR_EVALUATION, what) -> false

As the form without them, with upstream's leading `pred`, `arity` and `msg` (empty: not given): the
context holds `msg` as an atom (pl-error.c). `ERR_EVALUATION` raises `evaluation_error(What)`.
"""
function PL_error(
    ld::PL_local_data{T}, pred::String, arity::Int, msg::String, id::PL_error_code, what::T
)::Bool where {T}
    h = _PL_error_open(ld)
    h === nothing && return false
    caller, fid, except, formal, swi = h
    @assert id == ERR_REPRESENTATION || id == ERR_EVALUATION
    PL_cons_functor(
        ld, formal,
        _err_functor(
            ld, id == ERR_REPRESENTATION ? :representation_error : :evaluation_error, 1
        ),
        _err_atom(ld, what)
    )
    return _PL_error_close!(ld, caller, fid, except, formal, swi, pred, arity, msg)
end

"""
    PL_error(ld, ERR_MODIFY_STATIC_PROC, proc) -> false

Raise `error(permission_error(modify, static_procedure, Name/Arity), context(Caller, _))` for the
static procedure `proc` (pl-error.c).
"""
function PL_error(
    ld::PL_local_data{T}, id::PL_error_code, proc::Procedure{T}
)::Bool where {T}
    h = _PL_error_open(ld)
    h === nothing && return false
    caller, fid, except, formal, swi = h
    @assert id == ERR_MODIFY_STATIC_PROC
    def = proc.definition                                           # goto modify_static
    pred = new_term_ref(ld)
    gd = _query_gd(ld)
    unify_definition(gd, ld, MODULE_user(gd), pred, def, 0, GP_NAMEARITY | GP_HIDESYSTEM)
    PL_cons_functor(
        ld, formal, _err_functor(ld, :permission_error, 3),
        _err_atom(ld, mk_sym(T, :modify)),
        _err_atom(ld, mk_sym(T, :static_procedure)), pred
    )
    return _PL_error_close!(ld, caller, fid, except, formal, swi)
end

"""
    PL_error(ld, ERR_PERMISSION_PROC, op, type, proc) -> false

Raise `error(permission_error(Op, Type, Name/Arity), context(Caller, _))` for the procedure `proc`
(pl-error.c), as `overruleImportedProcedure` raises it (since R1f).
"""
function PL_error(
    ld::PL_local_data{T}, id::PL_error_code, op::T, type::T, proc::Procedure{T}
)::Bool where {T}
    h = _PL_error_open(ld)
    h === nothing && return false
    caller, fid, except, formal, swi = h
    @assert id == ERR_PERMISSION_PROC
    pi = new_term_ref(ld)
    gd = _query_gd(ld)
    unify_definition(                           # PL_unify_predicate(pi, pred, …)
        gd, ld, MODULE_user(gd), pi, proc.definition, 0, GP_NAMEARITY | GP_HIDESYSTEM
    )
    PL_cons_functor(
        ld, formal, _err_functor(ld, :permission_error, 3), _err_atom(ld, op),
        _err_atom(ld, type), pi
    )
    return _PL_error_close!(ld, caller, fid, except, formal, swi)
end

"""
    PL_error(ld, pred, arity, msg, ERR_PERMISSION, action, type, obj::term_t) -> false

Raise `error(permission_error(Action, Type, Obj), context(…, Msg))` (pl-error.c).
"""
function PL_error(
    ld::PL_local_data{T}, pred::String, arity::Int, msg::String, id::PL_error_code,
    action::T, type::T, obj::term_t
)::Bool where {T}
    h = _PL_error_open(ld)
    h === nothing && return false
    caller, fid, except, formal, swi = h
    @assert id == ERR_PERMISSION
    PL_cons_functor(
        ld, formal, _err_functor(ld, :permission_error, 3), _err_atom(ld, action),
        _err_atom(ld, type), obj
    )
    return _PL_error_close!(ld, caller, fid, except, formal, swi, pred, arity, msg)
end

"""
    PL_error(ld, ERR_DETERMINISM, def, expected, found, decl) -> false

Raise `error(determinism_error(Name/Arity, Expected, Found, Decl), context(Caller, _))` for the
predicate `def` (pl-error.c): `decl` is `guard`, `guard_in_caller` or `property`.
"""
function PL_error(
    ld::PL_local_data{T}, id::PL_error_code, def::Definition{T}, expected::T, found::T,
    decl::T
)::Bool where {T}
    h = _PL_error_open(ld)
    h === nothing && return false
    caller, fid, except, formal, swi = h
    @assert id == ERR_DETERMINISM
    gd = _query_gd(ld)
    pi = new_term_ref(ld)
    unify_definition(gd, ld, MODULE_user(gd), pi, def, 0, GP_NAMEARITY | GP_HIDESYSTEM)
    PL_cons_functor(
        ld, formal, _err_functor(ld, :determinism_error, 4), pi, _err_atom(ld, expected),
        _err_atom(ld, found), _err_atom(ld, decl)
    )
    return _PL_error_close!(ld, caller, fid, except, formal, swi)
end

"""
    PL_error(ld, ERR_DET_GOAL, goal::term_t, expected, found) -> false

Raise `error(determinism_error(Goal, Expected, Found, goal), context(Caller, _))` for the goal of a
`\$/1` (pl-error.c).
"""
function PL_error(
    ld::PL_local_data{T}, id::PL_error_code, goal::term_t, expected::T, found::T
)::Bool where {T}
    h = _PL_error_open(ld)
    h === nothing && return false
    caller, fid, except, formal, swi = h
    @assert id == ERR_DET_GOAL
    PL_cons_functor(
        ld, formal, _err_functor(ld, :determinism_error, 4), goal, _err_atom(ld, expected),
        _err_atom(ld, found), _err_atom(ld, mk_sym(T, :goal))
    )
    return _PL_error_close!(ld, caller, fid, except, formal, swi)
end

# PORT: pl-error.c PL_get_stdbool_ex
# DIVERGES: returns the Boolean, or `nothing` with the error raised (see `PL_get_stdbool`).
"The Boolean term reference `t` holds, or `nothing` after raising `type_error(bool, T)` (pl-error.c)."
function PL_get_stdbool_ex(ld::PL_local_data{T}, t::term_t)::Union{Nothing, Bool} where {T}
    b = PL_get_stdbool(ld, t)
    b === nothing || return b
    PL_error(ld, ERR_TYPE, mk_sym(T, :bool), t)
    return nothing
end

# PORT: pl-error.c PL_get_bool_ex
# DIVERGES: as `PL_get_stdbool_ex` (upstream writes an `int`).
"The Boolean term reference `t` holds, or `nothing` after raising `type_error(bool, T)` (pl-error.c)."
PL_get_bool_ex(ld::PL_local_data{T}, t::term_t) where {T} = PL_get_stdbool_ex(ld, t)

# PORT: pl-error.c PL_unify_bool_ex
"""
Unify term reference `t` with the Boolean `val`: a variable gets `true` or `false`; a Boolean must
agree; anything else raises `type_error(bool, T)` (pl-error.c).
"""
function PL_unify_bool_ex(ld::PL_local_data{T}, t::term_t, val::Bool)::Bool where {T}
    if PL_is_variable(ld, t)
        return PL_unify_atom(ld, t, mk_sym(T, val ? Symbol("true") : Symbol("false")))
    end
    v = PL_get_bool(ld, t)
    v === nothing || return v == val
    return PL_error(ld, ERR_TYPE, mk_sym(T, :bool), t)
end

# PORT: pl-error.c PL_get_atom_ex
# DIVERGES: returns the atom, or `nothing` with the error raised (see `PL_get_atom`).
"The atom term reference `t` holds, or `nothing` after raising `type_error(atom, T)` (pl-error.c)."
function PL_get_atom_ex(ld::PL_local_data{T}, t::term_t)::Union{Nothing, T} where {T}
    a = PL_get_atom(ld, t)
    a === nothing || return a
    PL_error(ld, ERR_TYPE, mk_sym(T, :atom), t)
    return nothing
end

# PORT: pl-error.c PL_get_integer_ex
# DIVERGES: returns the value, or `nothing` with the error raised (see `PL_get_integer`).
"""
The C `int` term reference `t` holds, or `nothing` after raising `representation_error(int)` (an
integer out of range) or `type_error(integer, T)` (pl-error.c).
"""
function PL_get_integer_ex(ld::PL_local_data{T}, t::term_t)::Union{Nothing, Int} where {T}
    i = PL_get_integer(ld, t)
    i === nothing || return i
    if PL_is_integer(ld, t)
        PL_error(ld, ERR_REPRESENTATION, mk_sym(T, :int))
        return nothing
    end
    PL_error(ld, ERR_TYPE, mk_sym(T, :integer), t)
    return nothing
end

# PORT: pl-error.c PL_get_long_ex
# DIVERGES: returns the value, or `nothing` with the error raised (see `PL_get_long`).
"""
The C `long` term reference `t` holds, or `nothing` after raising `representation_error(long)` (an
integer out of range) or `type_error(integer, T)` (pl-error.c).
"""
function PL_get_long_ex(ld::PL_local_data{T}, t::term_t)::Union{Nothing, Int} where {T}
    i = PL_get_long(ld, t)
    i === nothing || return i
    if PL_is_integer(ld, t)
        PL_error(ld, ERR_REPRESENTATION, mk_sym(T, :long))
        return nothing
    end
    PL_error(ld, ERR_TYPE, mk_sym(T, :integer), t)
    return nothing
end

# PORT: pl-error.c PL_get_intptr_ex
# DIVERGES: the branch of a 64-bit platform whose `long` is a pointer's size (`SIZEOF_LONG ==
# SIZEOF_VOIDP`: Linux, macOS): `PL_get_long_ex`, so its error is `representation_error(long)`, as
# swipl 10.1.18 on x86_64-linux raises it.
"The C `intptr_t` term reference `t` holds, or `nothing` with the error raised (pl-error.c)."
PL_get_intptr_ex(ld::PL_local_data{T}, t::term_t) where {T} = PL_get_long_ex(ld, t)

# PORT: pl-error.c PL_get_size_ex
# DIVERGES: returns the value, or `nothing` with the error raised (or none: upstream's plain
# `false`). An integer beyond `Int64` is beyond `size_t` or negative. On the WORDS (f3b-5a): a
# value word's entry read as its value (`_value_term`, upstream's `PL_get_number`), an unbound cell,
# an atom or a compound word `type_error(integer, T)` (PL_error makes an unbound culprit
# `instantiation_error`); the boundary (TRANSITIONAL, f3) read as its term, counted in `cold_pairs`.
"""
The size term reference `t` holds — a non-negative integer — or `nothing` after raising
`domain_error(not_less_than_zero, T)`, `representation_error(size_t)` or `type_error(integer, T)`
(pl-error.c).
"""
function PL_get_size_ex(ld::PL_local_data{T}, t::term_t)::Union{Nothing, Int} where {T}
    k, x, q = _deref_loc(ld, -(t + 1))                      # Word p = valTermRef(t); deRef(p)
    if k == DU_VALUE && isTaggedIntW(x)                     # if ( isTaggedInt(*p) )
        valInt(x) >= 0 && return Int(valInt(x))             # *i = (size_t)v
        PL_error(ld, ERR_DOMAIN, mk_sym(T, :not_less_than_zero), t)
        return nothing
    end
    if k == DU_VALUE
        p = _value_term(ld, x)                              # PL_get_number(t, &n): no export
    elseif k == DU_TERM                                     # the boundary (TRANSITIONAL): its term
        ld.cold_pairs += 1
        p = deRef(ld, _loc_term(ld, k, x, q))
    else                                                    # a variable, an atom, a compound
        PL_error(ld, ERR_TYPE, mk_sym(T, :integer), t)
        return nothing
    end
    if isInteger(p)
        if integer_is_int64(p)
            v = int64_value(p)
            v >= 0 && return Int(v)
            PL_error(ld, ERR_DOMAIN, mk_sym(T, :not_less_than_zero), t)
            return nothing
        end
        if bigint_value(p) < 0                          # mpz_to_uint64: -1
            PL_error(ld, ERR_DOMAIN, mk_sym(T, :not_less_than_zero), t)
        else
            PL_error(ld, ERR_REPRESENTATION, mk_sym(T, :size_t))
        end
        return nothing
    end

    PL_error(ld, ERR_TYPE, mk_sym(T, :integer), t)
    return nothing
end

# PORT: pl-error.c PL_get_list_ex
"As `PL_get_list`; on neither a list cell nor `[]`, false after raising `type_error(list, L)` (pl-error.c)."
function PL_get_list_ex(
    ld::PL_local_data{T}, l::term_t, h::term_t, t::term_t
)::Bool where {T}
    PL_get_list(ld, l, h, t) && return true
    PL_get_nil(ld, l) && return false
    return PL_error(ld, ERR_TYPE, mk_sym(T, :list), l)
end

# PORT: pl-error.c PL_unify_list_ex
"Unify `l` with a list cell, its head and tail into `h` and `t`; `[]` fails, anything else is `type_error(list, l)` (pl-error.c)."
function PL_unify_list_ex(
    ld::PL_local_data{T}, l::term_t, h::term_t, t::term_t
)::Bool where {T}
    PL_unify_list(ld, l, h, t) && return true
    PL_get_nil(ld, l) && return false
    return PL_error(ld, ERR_TYPE, mk_sym(T, :list), l)
end

# PORT: pl-error.c PL_unify_nil_ex
"Unify `l` with `[]`; a list cell fails, anything else is `type_error(list, l)` (pl-error.c)."
function PL_unify_nil_ex(ld::PL_local_data{T}, l::term_t)::Bool where {T}
    PL_unify_nil(ld, l) && return true
    PL_is_list(ld, l) && return false
    return PL_error(ld, ERR_TYPE, mk_sym(T, :list), l)
end

# PORT: pl-error.c PL_get_nil_ex
"Whether term reference `l` holds `[]`; on a non-list, false after raising `type_error(list, L)` (pl-error.c)."
function PL_get_nil_ex(ld::PL_local_data{T}, l::term_t)::Bool where {T}
    ld.exception_term != 0 && return false                  # PL_exception(0)
    PL_get_nil(ld, l) && return true
    PL_is_list(ld, l) && return false
    return PL_error(ld, ERR_TYPE, mk_sym(T, :list), l)
end

# PORT: pl-error.c PL_type_error
"Raise `type_error(Expected, Actual)` (pl-error.c `PL_type_error`); false."
PL_type_error(ld::PL_local_data{T}, expected::String, actual::term_t) where {T} =
    PL_error(ld, ERR_CHARS_TYPE, expected, actual)

# PORT: pl-error.c PL_domain_error
"Raise `domain_error(Expected, Actual)` (pl-error.c `PL_domain_error`); false."
PL_domain_error(ld::PL_local_data{T}, expected::String, actual::term_t) where {T} =
    PL_error(ld, ERR_DOMAIN, mk_sym(T, Symbol(expected)), actual)

# ── printing messages (pl-error.c), since R1f ───────────────────────────────────────────────────

# PORT: pl-error.c printMessage
# DIVERGES: the message is a term reference holding it, laid out on the cells by the caller, where
# upstream builds it from `PL_unify_term` arguments into `av+1` (f3b-4); it is not printed —
# print_message/2 is boot/messages.pl's (R2) — but appended to the local data's `messages` as
# `(severity, message)`, which the loader returns: EXPORTED off the cells once (`export_cells`), the one
# place a message leaves the engine. So it never fails and never raises: no recursion guard, no
# wakeup state to save.
"Report the message term reference `msg` holds, of severity `severity` (`:warning`, `:error`, …) (pl-error.c)."
function printMessage(ld::PL_local_data{T}, severity::Symbol, msg::term_t)::Bool where {T}
    push!(ld.messages, (severity, export_cells(ld, cell_export{T}(), -(msg + 1))))
    return true
end
