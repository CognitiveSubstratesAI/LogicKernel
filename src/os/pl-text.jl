# UPSTREAM: swipl-devel src/os/pl-text.c @ bae881a2
# UPSTREAM: swipl-devel src/os/pl-text.h @ bae881a2
# CLASS: code
# COPYRIGHT: Copyright (c)  2011-2026, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# TEXT (pl-text.c), since R1d: the text a term holds as `PL_get_text` takes it — an atom, a string,
# an integer or a rational, a code or character list — and a stream that reads it (`Sopen_text`):
# what `term_to_atom/2`, `term_string/2` and `atom_to_term/3` read a term from. NOT PORTED: the
# rest of pl-text.c (unifying with a text, comparing, concatenating, canonicalising, encodings).

# PORT: pl-text.h PL_chars_t
# DIVERGES: the text is a byte vector in its encoding — ISO Latin-1, or UTF-8 (ENC_UTF8) where
# upstream holds `pl_wchar_t` (ENC_WCHAR), as the term interface's texts are UTF-8; no storage
# class (`storage`, `buf`: Julia's GC owns the bytes).
"A text and its encoding (pl-text.h)."
mutable struct PL_chars_t
    text::Vector{UInt8}             # the text
    length::Int                     # its length, in characters
    encoding::IOENC                 # how it is encoded
    canonical::Bool                 # true: ENC_ISO_LATIN_1 or ENC_WCHAR
end

# PORT: pl-text.c PL_get_text
# DIVERGES: returns the text, or `nothing` where upstream returns false (the error raised under
# `CVT_EXCEPTION`, as upstream); an atom's or a string's text is its UTF-8 (see `PL_chars_t`); a
# float's text is `format_float`'s (since R1e's floats). NOT PORTED,
# as no caller passes them yet: `CVT_VARIABLE` (`varName`), the write conversions (`CVT_WRITE`,
# `CVT_WRITEQ`, `CVT_WRITE_CANONICAL`: the writer, R1e) — refused where reached — and
# `CVT_VARNOFAIL`; no buffer rings (`BUF_*`).
"""
The text term reference `l` holds, as `flags` (`CVT_*`) allow it (pl-text.c): an atom, a string,
an integer or a rational (`CVT_XINTEGER`: hexadecimal), a code or character list; `nothing` when
it holds none of them, raising the error under `CVT_EXCEPTION`.
"""
function PL_get_text(
    ld::PL_local_data{T}, l::term_t, flags::UInt32
)::Union{Nothing, PL_chars_t} where {T}
    w = deRef(ld, ld.slots[l + 1])

    if (flags & CVT_ATOM) != 0 && isAtom(w)
        is_nil(w) && (flags & CVT_LIST) != 0 && @goto case_list
        isTextAtom(w) || @goto maybe_write          # get_atom_text(): a text atom's
        s = sym_text(w)
        return PL_chars_t(Vector{UInt8}(codeunits(s)), length(s), ENC_UTF8, false)
    elseif (flags & CVT_STRING) != 0 && isString(w)
        s = string_value(w)                         # get_string_text()
        return PL_chars_t(Vector{UInt8}(codeunits(s)), length(s), ENC_UTF8, false)
    elseif ((flags & CVT_RATIONAL) != 0 && isRational(w)) ||
        ((flags & CVT_INTEGER) != 0 && isInteger(w))
        n = number()
        base = (flags & CVT_XINTEGER) == CVT_XINTEGER ? 16 : 10
        get_number(w, n)                            # PL_get_number(l, &n)
        s = if n.type === V_INTEGER
            string(n.i; base=base)                  # i64toa()
        elseif n.type === V_MPZ
            string(n.mpz; base=base)                # mpz_get_str()
        elseif n.type === V_MPQ
            string(numerator(n.mpq); base=base) * "r" * string(denominator(n.mpq); base=base)
        else
            error("PL_get_text: not an integer or a rational")      # assert(0)
        end
        return PL_chars_t(Vector{UInt8}(codeunits(s)), length(s), ENC_ISO_LATIN_1, true)
    elseif (flags & CVT_FLOAT) != 0 && isFloat(w)
        s = format_float(float_value(w), 3, 'e')    # format_float(text->buf, …, 3, 'e')
        return PL_chars_t(Vector{UInt8}(codeunits(s)), length(s), ENC_ISO_LATIN_1, true)
    elseif (flags & CVT_LIST) != 0
        @label case_list
        b, result = codes_or_chars_to_buffer(ld, l, false)
        if b !== nothing
            return PL_chars_t(b, length(b), ENC_ISO_LATIN_1, true)
        elseif result.status == CVT_wide
            b, result = codes_or_chars_to_buffer(ld, l, true)
            b !== nothing && return PL_chars_t(b, length(String(copy(b))), ENC_UTF8, true)
        end
        (flags & (CVT_WRITE | CVT_WRITE_CANONICAL | CVT_WRITEQ)) != 0 && @goto case_write
        if (flags & CVT_EXCEPTION) != 0
            if result.status == CVT_partial
                PL_error(ld, ERR_INSTANTIATION)
                return nothing
            elseif result.status == CVT_nocode || result.status == CVT_nochar
                culprit = new_term_ref(ld)
                c = result.culprit
                c === nothing && error("PL_get_text: no culprit")   # set with the status
                ld.slots[culprit + 1] = c           # *valTermRef(culprit) = result.culprit
                type = result.status == CVT_nocode ? :character_code : :character
                PL_error(ld, ERR_TYPE, mk_sym(T, type), culprit)
                return nothing
            end
            # CVT_representation: codes_or_chars_to_buffer() never gives it; CVT_nolist: error
        end
        @goto error
    elseif (flags & (CVT_WRITE | CVT_WRITE_CANONICAL | CVT_WRITEQ)) != 0
        @label case_write
        throw(
            NotPortedError{T}(
                w, "PL_get_text: CVT_WRITE, CVT_WRITEQ, CVT_WRITE_CANONICAL",
                "R1e (the writer)"
            )
        )
    else
        @goto error
    end

    @label maybe_write
    (flags & (CVT_WRITE | CVT_WRITE_CANONICAL | CVT_WRITEQ)) != 0 && @goto case_write

    @label error
    if (flags & CVT_EXCEPTION) != 0
        expected = if (flags & CVT_LIST) != 0 && (flags & (CVT_ATOM | CVT_NUMBER)) == 0
            :list                                   # List and/or string object
        elseif (flags & CVT_STRING) != 0
            :string
        elseif (flags & CVT_LIST) != 0
            :text
        elseif (flags & CVT_ATOM) != 0 && is_nil(w)
            :atom                                   # [] \== '[]'
        elseif (flags & CVT_NUMBER) != 0
            :atomic
        else
            :atom
        end
        PL_error(ld, ERR_TYPE, mk_sym(T, expected), l)
    end
    return nothing
end

# PORT: pl-text.c Sopen_text
# DIVERGES: the stream reads the text's own bytes (`Sopen_string`), as upstream's does.
"A stream reading the text `txt`, in its encoding (pl-text.c); `nothing` for a mode other than `\"r\"`."
function Sopen_text(txt::PL_chars_t, mode::String)::Union{Nothing, IOSTREAM}
    mode == "r" || return nothing                   # errno = EINVAL
    stream = Sopen_string(txt.text, length(txt.text), mode)
    stream === nothing && return nothing
    stream.encoding = txt.encoding
    return stream
end
