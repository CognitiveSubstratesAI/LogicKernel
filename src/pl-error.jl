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
# The formal and the context are BUILT (`mk_expr`) where upstream unifies them into fresh term
# references (`PL_unify_term`), which cannot fail here. Raised with `PL_raise_exception`, never
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
        msgterm = isempty(msg) ? mk_var(T, fresh_var_keys!(1)) : mk_sym(T, Symbol(msg))
        predterm = if !isempty(pred)
            mk_expr(T, T[mk_sym(T, :/), mk_sym(T, Symbol(pred)), mk_gnd(T, arity)])
        elseif caller !== nothing
            gd = _query_gd(ld)
            unify_definition(gd, MODULE_user(gd), caller, GP_NAMEARITY)
        else
            mk_var(T, fresh_var_keys!(1))                   # PL_new_term_ref(): unbound
        end
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
        ld.slots[formal + 1] = mk_sym(T, :instantiation_error)      # err_instantiation:
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
        ld.slots[formal + 1] = mk_expr(T, T[mk_sym(T, :evaluation_error), mk_sym(T, what)])
    end
    return _PL_error_close!(ld, caller, fid, except, formal, swi)
end

"""
    PL_error(ld, pred, arity, msg, ERR_AR_TYPE, expected, num::number) -> false

Raise `error(type_error(Expected, Num), context(pred/arity, …))` for the number `num` an arithmetic
function cannot take (pl-error.c `ERR_AR_TYPE`).
"""
function PL_error(
    ld::PL_local_data{T}, pred::String, arity::Int, msg::String, id::PL_error_code,
    expected::T, num::number
)::Bool where {T}
    h = _PL_error_open(ld)
    h === nothing && return false
    caller, fid, except, formal, swi = h
    @assert id == ERR_AR_TYPE
    actual = put_number(T, num)                                     # _PL_put_number(actual, num)
    ld.slots[formal + 1] = mk_expr(T, T[mk_sym(T, :type_error), expected, actual])
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
    actual = mk_expr(T, T[mk_sym(T, :/), f[1], mk_gnd(T, f[2])])   # put_name_arity(actual, f)
    ld.slots[formal + 1] = mk_expr(
        T, T[mk_sym(T, :type_error), mk_sym(T, :evaluable), actual]
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
    loops = 0
    colon = sym_key(mk_sym(T, :(:)))
    while true
        t = deRef(ld, ld.slots[actual + 1])
        # PL_is_functor(actual, FUNCTOR_colon2)
        (
            kind(t) === EXPR && nchildren(t) == 3 && kind(child(t, 1)) === SYM &&
            sym_key(child(t, 1)) == colon
        ) || break
        a = deRef(ld, child(t, 2))                                  # _PL_get_arg(1, actual, a)
        if !isTextAtom(a)                                           # !PL_is_atom(a)
            ld.slots[actual + 1] = a                                # PL_put_term(actual, a)
            return mk_sym(T, :atom)                                 # *expected = ATOM_atom
        else
            ld.slots[actual + 1] = child(t, 3)                      # _PL_get_arg(2, actual, a)
        end
        loops += 1
        if loops > 100 && !is_acyclic(ld, ld.slots[actual + 1])
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
            ld.slots[formal + 1] = mk_sym(T, :instantiation_error)  # goto err_instantiation
        else
            ld.slots[formal + 1] = mk_expr(
                T, T[mk_sym(T, :type_error), a, ld.slots[actual + 1]]
            )
        end
    elseif id == ERR_EXISTENCE                      # (since R1e's write/1 family: streams)
        ld.slots[formal + 1] = mk_expr(
            T, T[mk_sym(T, :existence_error), a, ld.slots[actual + 1]]
        )
    elseif id == ERR_STREAM_OP                      # (since R1e's write/1 family)
        ld.slots[formal + 1] = mk_expr(T, T[mk_sym(T, :io_error), a, ld.slots[actual + 1]])
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
    gd = _query_gd(ld)
    ld.slots[pred + 1] = unify_definition(gd, MODULE_user(gd), def, GP_NAMEARITY)
    ld.slots[formal + 1] = mk_expr(
        T, T[mk_sym(T, :existence_error), mk_sym(T, :procedure), ld.slots[pred + 1]]
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
    PL_error(ld, pred, arity, msg, ERR_REPRESENTATION, what) -> false

As the form without them, with upstream's leading `pred`, `arity` and `msg` (empty: not given): the
context holds `msg` as an atom (pl-error.c).
"""
function PL_error(
    ld::PL_local_data{T}, pred::String, arity::Int, msg::String, id::PL_error_code, what::T
)::Bool where {T}
    h = _PL_error_open(ld)
    h === nothing && return false
    caller, fid, except, formal, swi = h
    @assert id == ERR_REPRESENTATION
    ld.slots[formal + 1] = mk_expr(T, T[mk_sym(T, :representation_error), what])
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
    ld.slots[pred + 1] = unify_definition(
        gd, MODULE_user(gd), def, GP_NAMEARITY | GP_HIDESYSTEM
    )
    ld.slots[formal + 1] = mk_expr(
        T,
        T[
            mk_sym(T, :permission_error), mk_sym(T, :modify), mk_sym(T, :static_procedure),
            ld.slots[pred + 1]
        ]
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
    ld.slots[pi + 1] = unify_definition(                       # PL_unify_predicate(pi, pred, …)
        gd, MODULE_user(gd), proc.definition, GP_NAMEARITY | GP_HIDESYSTEM
    )
    ld.slots[formal + 1] = mk_expr(
        T, T[mk_sym(T, :permission_error), op, type, ld.slots[pi + 1]]
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
    ld.slots[formal + 1] = mk_expr(
        T, T[mk_sym(T, :permission_error), action, type, ld.slots[obj + 1]]
    )
    return _PL_error_close!(ld, caller, fid, except, formal, swi, pred, arity, msg)
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

# PORT: pl-error.c PL_get_list_ex
"As `PL_get_list`; on neither a list cell nor `[]`, false after raising `type_error(list, L)` (pl-error.c)."
function PL_get_list_ex(
    ld::PL_local_data{T}, l::term_t, h::term_t, t::term_t
)::Bool where {T}
    PL_get_list(ld, l, h, t) && return true
    PL_get_nil(ld, l) && return false
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
# DIVERGES: the message is a built term, where upstream builds it from `PL_unify_term` arguments; it
# is not printed — print_message/2 is boot/messages.pl's (R2) — but appended, resolved through the
# bindings, to the local data's `messages` as `(severity, message)`, which the loader returns. So
# it never fails and never raises: no recursion guard, no wakeup state to save.
"Report the message `msg` of severity `severity` (`:warning`, `:error`, …) (pl-error.c)."
function printMessage(ld::PL_local_data{T}, severity::Symbol, msg::T)::Bool where {T}
    push!(ld.messages, (severity, resolve_term(ld, msg)))
    return true
end
