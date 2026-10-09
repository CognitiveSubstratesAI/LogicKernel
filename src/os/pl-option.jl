# UPSTREAM: swipl-devel src/os/pl-option.c @ bae881a2
# UPSTREAM: swipl-devel src/os/pl-option.h @ bae881a2
# CLASS: code
# COPYRIGHT: Copyright (c)  2011-2024, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# OPTION LISTS (pl-option.c), since R1e's write_term/2,3: `PL_scan_options` reads a list of
# `Name(Value)`, `Name = Value` or (outside ISO mode) a bare `Name` for a Boolean `true`, against a
# table of specifications (`PL_option_t`, src/SWI-Prolog.jl), with upstream's errors: a non-list
# `type_error(list, L)`, a bad item `type_error(option, O)`, a bad value its type's error, an
# unknown option ignored, warned about or a `domain_error`, as the flags or the `unknown_option`
# flag say (swipl 10.1.16's default: `ignore`). NOT PORTED: option DICTS (`dict_options`: the kernel
# reads no dicts, R1d), the option types no specification uses yet (`OPT_INT64`, `OPT_UINT64`,
# `OPT_SIZE`, `OPT_DOUBLE`, `OPT_STRING`, `OPT_LOCALE`) — reaching one is an assertion, as upstream's
# `assert(0)` for an unknown type.

# PORT: pl-option.c MAXOPTIONS
"The most specifications a table may hold (pl-option.c)."
const MAXOPTIONS = 64

# PORT: pl-option.c HAS_OPT_MODE
"Whether the unknown-option mode of `f` is `m` (pl-option.c)."
HAS_OPT_MODE(f::Int, m::Int)::Bool = (f & OPT_UNKNOWN_MASK) == m

# PORT: pl-option.c get_optval
# DIVERGES: returns `(ok, value)` — a `Bool`, an `Int`, an atom or a term reference — where upstream
# writes through the specification's pointer (`optvalue`); the types listed in the file's header
# are not ported.
"The value of option `spec` in term reference `val`: `(true, value)`, or `(false, nothing)` with the error raised (pl-option.c)."
function get_optval(
    ld::PL_local_data{T}, spec::PL_option_t, val::term_t
)::Tuple{Bool, Union{Nothing, Bool, Int, T}} where {T}
    type = spec.type & OPT_TYPE_MASK
    if type == OPT_BOOL || type == OPT_STDBOOL
        bval = PL_get_stdbool_ex(ld, val)
        bval === nothing && return (false, nothing)
        return (true, bval)
    elseif type == OPT_INT
        i = PL_get_integer_ex(ld, val)
        i === nothing && return (false, nothing)
        return (true, i)
    elseif type == OPT_ATOM
        a = PL_get_atom_ex(ld, val)
        a === nothing && return (false, nothing)
        return (true, a)
    elseif type == OPT_TERM
        return (true, PL_copy_term_ref(ld, val))           # can't reuse anymore
    end
    @assert false "get_optval: an option type not ported"
    return (false, nothing)
end

# PORT: pl-option.c vscan_options as PL_scan_options
# DIVERGES: `PL_scan_options` and `vscan_options` are one function, which RETURNS the values — one
# per specification, `nothing` for an option the list does not give — where upstream writes each
# through a pointer passed in its variable arguments (the caller's defaults stay where nothing was
# written: the caller applies them to `nothing`); `nothing` for upstream's false. No dicts (see the
# file's header). ISO mode is off (the `iso` flag's default; the kernel has no `set_prolog_flag`).
"""
    PL_scan_options(ld, options, flags, opttype, specs) -> values or nothing

The values of the options the list term reference `options` gives for the specifications `specs`
(pl-option.c): each `Name(Value)`, `Name = Value`, or a bare `Name` (a Boolean, true). An option no
specification names is ignored, warned about or a `domain_error(opttype, Option)`, as `flags`
(`OPT_UNKNOWN_*`) — or, for `OPT_UNKNOWN_DEFAULT`, the `unknown_option` flag — says. `nothing`,
with the error raised, on a bad list, item or value.
"""
function PL_scan_options(
    ld::PL_local_data{T}, options::term_t, flags::Int, opttype::String,
    specs::Tuple{Vararg{PL_option_t}}
)::Union{Nothing, Vector{Union{Nothing, Bool, Int, T}}} where {T}
    values = Union{Nothing, Bool, Int, T}[nothing for _ in specs]
    candiscard = true
    count = 0

    if flags == OPT_UNKNOWN_DEFAULT
        flags = ld.prolog_flag_unknown_option
    end

    length(specs) > MAXOPTIONS && error("PL_scan_options(): too many options")   # fatalError

    list = PL_copy_term_ref(ld, options)
    av = PL_new_term_refs(ld, 3)
    head = av + 0
    tmp = av + 1
    val = av + 2

    while PL_get_list(ld, list, head, list)
        implicit_true = false

        if count == 1000
            if !is_acyclic(ld, ld.slots[list + 1])
                PL_error(ld, ERR_TYPE, mk_sym(T, :list), options)
                return nothing
            end
        end
        count += 1

        na = PL_get_name_arity(ld, head)
        itemerror = na === nothing
        name = mk_nil(T)
        if !itemerror
            name, arity = na
            if sym_key(name) == sym_key(mk_sym(T, :(=))) && arity == 2
                _PL_get_arg(ld, 1, head, tmp)
                a = PL_get_atom(ld, tmp)
                if a === nothing
                    itemerror = true
                else
                    name = a
                    _PL_get_arg(ld, 2, head, val)
                end
            elseif arity == 1
                _PL_get_arg(ld, 1, head, val)
            elseif arity == 0                       # && !truePrologFlag(PLFLAG_ISO)
                implicit_true = true
            else
                itemerror = true
            end
        end
        if itemerror                                # itemerror:
            PL_error(ld, ERR_TYPE, mk_sym(T, :option), head)
            return nothing
        end

        found = false
        for (n, s) in enumerate(specs)
            if sym_key(mk_sym(T, s.name)) == sym_key(name)
                if implicit_true
                    if (s.type & OPT_TYPE_MASK) == OPT_BOOL ||
                        (s.type & OPT_TYPE_MASK) == OPT_STDBOOL
                        values[n] = true
                        found = true
                        break
                    end
                    PL_error(ld, ERR_TYPE, mk_sym(T, :option), head)   # goto itemerror
                    return nothing
                end
                ok, v = get_optval(ld, s, val)
                ok || return nothing
                values[n] = v
                if (s.type & OPT_TYPE_MASK) == OPT_TERM
                    candiscard = false
                end
                found = true
                break
            end
        end

        if !found && !HAS_OPT_MODE(flags, OPT_UNKNOWN_IGNORE)
            if HAS_OPT_MODE(flags, OPT_UNKNOWN_ERROR)
                PL_error(ld, ERR_DOMAIN, mk_sym(T, Symbol(opttype)), head)
                return nothing
            end
            msg = mk_expr(
                T,
                T[
                    mk_sym(T, :unknown_option),
                    mk_sym(T, Symbol(opttype)),
                    ld.slots[head + 1]
                ]
            )
            printMessage(ld, :warning, msg) || return nothing
        end
    end

    if !PL_get_nil(ld, list)
        PL_error(ld, ERR_TYPE, mk_sym(T, :list), list)
        return nothing
    end

    if candiscard
        PL_reset_term_refs(ld, list)
    end

    return values
end
