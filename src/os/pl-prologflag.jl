# UPSTREAM: swipl-devel src/os/pl-prologflag.c @ bae881a2
# CLASS: code
# COPYRIGHT: Copyright (c)  2011-2026, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# PROLOG FLAGS (pl-prologflag.c), since R1e's write_term/2,3: the part write_term's `back_quotes`
# options need, `setBackQuotes` and (read_term_from_atom/3) `setDoubleQuotes`. NOT PORTED: the flag table itself — set_prolog_flag/2,
# current_prolog_flag/2, create_prolog_flag/3 (the flags the kernel reads are fields of its local
# data, each with swipl 10.1.16's default: src/pl-global.jl).

# PORT: pl-prologflag.c setDoubleQuotes
# DIVERGES: as `setBackQuotes`.
"`flags` with the double-quote syntax the atom `a` names (`chars`, `codes`, `atom`, `string`), or `nothing` after `domain_error(double_quotes, A)` (pl-prologflag.c)."
function setDoubleQuotes(
    ld::PL_local_data{T}, a::T, flags::UInt32
)::Union{Nothing, UInt32} where {T}
    k = sym_key(a)
    if k == sym_key(mk_sym(T, :chars))
        f = DBLQ_CHARS
    elseif k == sym_key(mk_sym(T, :codes))
        f = UInt32(0)
    elseif k == sym_key(mk_sym(T, :atom))
        f = DBLQ_ATOM
    elseif k == sym_key(mk_sym(T, :string))
        f = DBLQ_STRING
    else
        value = PL_new_term_ref(ld)
        ld.slots[value + 1] = a                     # PL_put_atom(value, a)
        PL_error(ld, ERR_DOMAIN, mk_sym(T, :double_quotes), value)
        return nothing
    end

    flags &= ~DBLQ_MASK
    flags |= f

    return flags
end

# PORT: pl-prologflag.c setBackQuotes
# DIVERGES: returns the new flags, or `nothing` with the error raised, where upstream writes them
# through `flagp` and returns a Boolean.
"`flags` with the back-quote syntax the atom `a` names (`string`, `symbol_char`, `codes`, `chars`), or `nothing` after `domain_error(back_quotes, A)` (pl-prologflag.c)."
function setBackQuotes(
    ld::PL_local_data{T}, a::T, flags::UInt32
)::Union{Nothing, UInt32} where {T}
    k = sym_key(a)
    if k == sym_key(mk_sym(T, :string))
        f = BQ_STRING
    elseif k == sym_key(mk_sym(T, :symbol_char))
        f = UInt32(0)
    elseif k == sym_key(mk_sym(T, :codes))
        f = BQ_CODES
    elseif k == sym_key(mk_sym(T, :chars))
        f = BQ_CHARS
    else
        value = PL_new_term_ref(ld)
        ld.slots[value + 1] = a                     # PL_put_atom(value, a)
        PL_error(ld, ERR_DOMAIN, mk_sym(T, :back_quotes), value)
        return nothing
    end

    flags &= ~BQ_MASK
    flags |= f

    return flags
end
