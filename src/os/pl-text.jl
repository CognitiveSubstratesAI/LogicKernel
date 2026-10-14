# UPSTREAM: swipl-devel src/os/pl-text.c @ 8609e216cab9
# UPSTREAM: swipl-devel src/os/pl-text.h @ 8609e216cab9
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
# class (`storage`, `buf`: Julia's GC owns the bytes). A UTF-8 text is NEVER canonical, as
# upstream's never is: `PL_canonicalise_text` recodes it to ISO Latin-1 or `ENC_WCHAR` (since L1b
# stage A, an `ENC_WCHAR` text is upstream's buffer: native 4-byte `pl_wchar_t`s).
"A text and its encoding (pl-text.h)."
mutable struct PL_chars_t
    text::Vector{UInt8}             # the text
    length::Int                     # its length, in characters
    encoding::IOENC                 # how it is encoded
    canonical::Bool                 # true: ENC_ISO_LATIN_1 or ENC_WCHAR, never ENC_UTF8
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
    w = deRef(ld, slotValue(ld, l + 1))

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
            # upstream: ENC_WCHAR, canonical; here UTF-8, so NOT canonical (see `PL_chars_t`)
            b !== nothing && return PL_chars_t(b, length(String(copy(b))), ENC_UTF8, false)
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
                setSlotValue!(ld, culprit + 1, c)           # *valTermRef(culprit) = result.culprit
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

# PORT: pl-text.h ERR_TEXT_INVALID_CODE_POINT
"`PL_canonicalise_text`'s error: a code point that is not Unicode (pl-text.h)."
const ERR_TEXT_INVALID_CODE_POINT = -5

# PORT: pl-text.c PL_canonicalise_text
# DIVERGES: an `ENC_WCHAR` text is its code points as native 4-byte `pl_wchar_t`s in `text.text`,
# as upstream's buffer is; the demotion of an all-Latin-1 wide text (`PL_demote_text`) is inline.
# NOT PORTED: `ENC_UTF16LE`/`BE` and `ENC_ANSI` (no caller produces them) — refused by name.
"""
    PL_canonicalise_text(text) -> true or ERR_TEXT_*

Recode `text` to a canonical encoding (pl-text.c): ISO Latin-1 when every code point is ≤ 0xFF,
else `ENC_WCHAR`.
"""
function PL_canonicalise_text(text::PL_chars_t)::Int
    if !text.canonical
        enc = text.encoding
        if enc === ENC_OCTET || enc === ENC_ISO_LATIN_1
            text.encoding = ENC_ISO_LATIN_1
            text.canonical = true                       # nothing to do
        elseif enc === ENC_WCHAR
            w = reinterpret(UInt32, view(text.text, 1:(4 * text.length)))
            wide = false
            for c in w
                c > 0xff && (wide = true)
                VALID_CODE_POINT(Int(c)) || return ERR_TEXT_INVALID_CODE_POINT
            end
            if !wide                                    # PL_demote_text(text, 0)
                text.text = UInt8[c & 0xff for c in w]
                text.encoding = ENC_ISO_LATIN_1
            end
            text.canonical = true
        elseif enc === ENC_UTF8
            b = text.text
            e = length(b)
            s = 1
            while s <= e && b[s] & 0x80 == 0
                s += 1
            end
            if s > e
                text.encoding = ENC_ISO_LATIN_1
                text.length = e
                text.canonical = true
            else
                cps = Int[]
                i = 1
                while i <= e
                    _, i, chr = _PL__utf8_code_point(b, i, e + 1)
                    push!(cps, chr)
                end
                text.length = length(cps)
                if any(>(0xff), cps)
                    text.text = Vector{UInt8}(reinterpret(UInt8, UInt32.(cps)))
                    text.encoding = ENC_WCHAR
                else
                    text.text = UInt8.(cps)
                    text.encoding = ENC_ISO_LATIN_1
                end
                text.canonical = true
            end
        else
            throw(
                NotPortedError{Nothing}(
                    nothing, "PL_canonicalise_text of $enc", "no caller"
                )
            )
        end
    end
    return 1                                            # true
end

# PORT: pl-text.c textToAtom
# DIVERGES: the atom table is an argument (`GD->atoms`); a canonicalisation error returns 0 without
# raising (`text_error` is NOT PORTED: no caller yet — stage C's boundary is the first).
"""
    textToAtom(atoms, text) -> atom_t

The atom of `text` (pl-text.c): canonicalised first, so one text is one atom — a text atom when
every code point is ≤ 0xFF, else a wide one; 0 if the text cannot be canonicalised.
"""
function textToAtom(atoms::atoms_t, text::PL_chars_t)::UInt64
    rc = PL_canonicalise_text(text)
    rc == 1 || return UInt64(0)
    if text.encoding === ENC_ISO_LATIN_1
        return lookupAtom(atoms, text.text, text.length)
    else
        return lookupUCSAtom(
            atoms, reinterpret(UInt32, view(text.text, 1:(4 * text.length))), text.length
        )
    end
end
