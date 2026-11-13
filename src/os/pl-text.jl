# UPSTREAM: swipl-devel src/os/pl-text.c @ 18168e629eab
# UPSTREAM: swipl-devel src/os/pl-text.h @ 18168e629eab
# CLASS: code
# COPYRIGHT: Copyright (c)  2011-2026, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# TEXT (pl-text.c), since R1d: the text a term holds as `PL_get_text` takes it — an atom, a string,
# an integer or a rational, a code or character list — and a stream that reads it (`Sopen_text`):
# what `term_to_atom/2`, `term_string/2` and `atom_to_term/3` read a term from; since T1 (R2) also
# unifying a term with a text (`PL_unify_text`, `PL_unify_text_range`), comparing (`PL_cmp_text`),
# concatenating (`PL_concat_text`), and `CVT_VARNOFAIL`, for atom_length/2, the `x_chars` family and
# atom_concat/3 (src/pl-prims.jl). NOT PORTED: the rest of pl-text.c (`PL_unify_text_units`,
# `PL_text_unit_offset`, `PL_demote_text`, `PL_text_recode`, `PL_save_text`, `PL_from_stack_text`,
# `PL_free_text`: Julia's GC owns the bytes). Encodings: ISO Latin-1, UTF-8, `ENC_WCHAR` and `ENC_ANSI` (the locale's multibyte
# encoding, libc's `mbrtowc`/`wcrtomb`, since ENC1); `ENC_ASCII` and `ENC_UNKNOWN` are upstream's `assert(0)`, an `error()`.

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

# PORT: pl-text.h PL_init_text
# DIVERGES: a function returning the text (upstream's macro initialises the `PL_chars_t` it is given).
"A text not yet set: no bytes, `ENC_UNKNOWN` (pl-text.h `PL_init_text`)."
PL_init_text()::PL_chars_t = PL_chars_t(UInt8[], 0, ENC_UNKNOWN, false)

# PORT: pl-text.h get_text_t
# DIVERGES: an `Int` (the enum's three values are the constants below).
"The type of `PL_get_text`'s result classification (pl-text.h `get_text_t`)."
const get_text_t = Int
"`PL_get_text`'s result: no text, and an exception raised if `CVT_EXCEPTION` asked for one (pl-text.h)."
const GT_FALSE = 0
"`PL_get_text`'s result: the text is set (pl-text.h)."
const GT_TRUE = 1
"`PL_get_text`'s result under `CVT_VARNOFAIL`: the term is a variable, no text and no error (pl-text.h)."
const GT_ISVAR = 2

# ORIGINAL (T1): upstream's `get_text_t` as a function of what the kernel's `PL_get_text` returns.
"`GT_FALSE`, `GT_TRUE` or `GT_ISVAR` for the result `r` of `PL_get_text`."
function get_text_status(r::Union{Nothing, PL_chars_t})::Int
    r === nothing && return GT_FALSE
    return r.encoding === ENC_UNKNOWN ? GT_ISVAR : GT_TRUE
end

# ORIGINAL: the `case_write` branch of pl-text.c `PL_get_text` (the `CVT_WRITE`, `CVT_WRITEQ` and
# `CVT_WRITE_CANONICAL` conversions) as a function of its own, a `try` cannot hold `@goto`'s label.
# DIVERGES: the stream layer writes UTF-8 only (ENC1 refusals in src/os/pl-stream.jl), so the text is
# written as UTF-8 and returned as a non-canonical `PL_chars_t` (as an atom's text is), where upstream
# tries ISO Latin-1 and then `ENC_WCHAR` (`ENC_UTF8` only under `REP_UTF8`): the code points are the
# same; the numbervars frame is ended on an `NV_ERROR`, where upstream's `goto error` leaves it open.
"The text the term `l` is written as under `flags`' `CVT_WRITE*` (write, writeq or write_canonical's), or `nothing`."
function _get_text_write(
    ld::PL_local_data{T}, l::term_t, flags::UInt32
)::Union{Nothing, PL_chars_t} where {T}
    gd = _query_gd(ld)
    wflags = if (flags & CVT_WRITEQ) != 0
        PL_WRT_QUOTED | PL_WRT_NUMBERVARS
    elseif (flags & CVT_WRITE_CANONICAL) != 0
        PL_WRT_QUOTED | PL_WRT_QUOTE_NON_ASCII | PL_WRT_IGNOREOPS | PL_WRT_VARNAMES |
        PL_WRT_NODOTINATOM | PL_WRT_BRACETERMS
    else
        PL_WRT_NUMBERVARS
    end

    result = nothing
    savedf = BEGIN_NUMBERVARS(ld, true)
    try
        options = nv_options{T}(
            mk_sym(T, Symbol("\$VAR")),                 # FUNCTOR_isovar1
            0, AV_SKIP,
            is_acyclic_cells(ld, -(l + 1)) ? 1 : 0,      # PL_is_acyclic(l)
            false
        )
        if numberVars(ld, l, options, 0) != NV_ERROR
            bufp = Ref{Union{Nothing, Vector{UInt8}}}(nothing)
            size = Ref(0)
            fd = Sopenmem(bufp, size, "w")
            fd === nothing && error("PL_get_text: Sopenmem")
            fd.encoding = ENC_UTF8
            if PL_write_term(gd, ld, fd, l, 1200, wflags) &&
                Sputcode(0, fd) >= 0 &&                  # Sputcode(EOS, fd)
                Sflush(fd) >= 0
                b = bufp[]
                bytes = UInt8[]
                if b !== nothing
                    n = size[]
                    n > 0 && b[n] == 0x00 && (n -= 1)    # text->length = size-1
                    bytes = b[1:n]
                end
                result = PL_chars_t(bytes, length(String(copy(bytes))), ENC_UTF8, false)
            end
            Sclose(fd)
        end
    finally
        END_NUMBERVARS(ld, true, savedf)
    end
    return result
end

# PORT: pl-text.c PL_get_text
# DIVERGES: returns the text, or `nothing` where upstream returns false (the error raised under
# `CVT_EXCEPTION`, as upstream); an atom's or a string's text is its UTF-8 (see `PL_chars_t`); a
# float's text is `format_float`'s (since R1e's floats). On the WORDS (`valHandle(l)`,
# `_deref_loc`; f3b-5a): the tests on `w` read a leaf — an atom word's symbol, a value word's entry,
# no export — and a cell or a compound has none (`nothing`: it reaches only the list and the error
# paths). `get_text_t` is the result's shape (`GT_FALSE`: `nothing`; `GT_TRUE`: the text; `GT_ISVAR`,
# only under `CVT_VARNOFAIL` (T1): a text still in its `PL_init_text` state, `encoding ===
# ENC_UNKNOWN`, which is what upstream leaves of `text` — `get_text_status` reads the three apart).
# NOT PORTED, as no caller passes it yet: `CVT_VARIABLE` (`varName`); no buffer rings (`BUF_*`). The
# write conversions (`CVT_WRITE`, `CVT_WRITEQ`, `CVT_WRITE_CANONICAL`) are `_get_text_write` (WR2).
"""
The text term reference `l` holds, as `flags` (`CVT_*`) allow it (pl-text.c): an atom, a string,
an integer or a rational (`CVT_XINTEGER`: hexadecimal), a code or character list; `nothing` when
it holds none of them, raising the error under `CVT_EXCEPTION`.
"""
function PL_get_text(
    ld::PL_local_data{T}, l::term_t, flags::UInt32
)::Union{Nothing, PL_chars_t} where {T}
    k, x, _ = _deref_loc(ld, -(l + 1))                      # word w = valHandle(l)
    w = if k == DU_WORD                                     # (f3b-5a: the leaf the tests read —
        isAtomW(x) ? _atom_value(ld, x) : nothing           # an atom's symbol; a compound has none
    elseif k == DU_VALUE
        _value_term(ld, x)                                  # a value's entry, no export
    else
        nothing                                             # an unbound cell: none)
    end
    nil = k == DU_WORD && x == ld.atom_nil_w                # isNil(w)

    if w !== nothing && (flags & CVT_ATOM) != 0 && isAtom(w)
        nil && (flags & CVT_LIST) != 0 && @goto case_list
        isTextAtom(w) || @goto maybe_write          # get_atom_text(): a text atom's
        s = sym_text(w)
        return PL_chars_t(Vector{UInt8}(codeunits(s)), length(s), ENC_UTF8, false)
    elseif w !== nothing && (flags & CVT_STRING) != 0 && isString(w)
        s = string_value(w)                         # get_string_text()
        return PL_chars_t(Vector{UInt8}(codeunits(s)), length(s), ENC_UTF8, false)
    elseif w !== nothing && (
        ((flags & CVT_RATIONAL) != 0 && isRational(w)) ||
        ((flags & CVT_INTEGER) != 0 && isInteger(w))
    )
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
    elseif w !== nothing && (flags & CVT_FLOAT) != 0 && isFloat(w)
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
        (flags & CVT_VARNOFAIL) != 0 && result.status == CVT_partial &&
            return PL_init_text()  # GT_ISVAR
        if (flags & CVT_EXCEPTION) != 0
            if result.status == CVT_partial
                PL_error(ld, ERR_INSTANTIATION)
                return nothing
            elseif result.status == CVT_nocode || result.status == CVT_nochar
                culprit = new_term_ref(ld)
                c = result.culprit                          # its cell's position (`CVT_result`)
                c == 0 && error("PL_get_text: no culprit")  # set with the status
                _slot_from_cell!(ld, culprit + 1, c)        # *valTermRef(culprit) = result.culprit
                type = result.status == CVT_nocode ? :character_code : :character
                PL_error(ld, ERR_TYPE, mk_sym(T, type), culprit)
                return nothing
            end
            # CVT_representation: codes_or_chars_to_buffer() never gives it; CVT_nolist: error
        end
        @goto error
    elseif (flags & (CVT_WRITE | CVT_WRITE_CANONICAL | CVT_WRITEQ)) != 0
        @label case_write
        r = _get_text_write(ld, l, flags)
        r !== nothing && return r
        @goto error
    else
        @goto error
    end

    @label maybe_write
    (flags & (CVT_WRITE | CVT_WRITE_CANONICAL | CVT_WRITEQ)) != 0 && @goto case_write

    @label error
    k == DU_CELL && (flags & CVT_VARNOFAIL) != 0 && return PL_init_text()      # canBind(w): GT_ISVAR
    if (flags & CVT_EXCEPTION) != 0
        expected = if (flags & CVT_LIST) != 0 && (flags & (CVT_ATOM | CVT_NUMBER)) == 0
            :list                                   # List and/or string object
        elseif (flags & CVT_STRING) != 0
            :string
        elseif (flags & CVT_LIST) != 0
            :text
        elseif (flags & CVT_ATOM) != 0 && nil
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

# PORT: pl-text.h ERR_TEXT_ILLEGAL_UTF8
"`text_error`'s code for an illegal UTF-8 sequence (pl-text.h); `PL_canonicalise_text` gives none at the pin."
const ERR_TEXT_ILLEGAL_UTF8 = -1
# PORT: pl-text.h ERR_TEXT_ILLEGAL_MULTIBYTE_SEQUENCE
"`PL_canonicalise_text`'s error: an illegal multibyte sequence in an `ENC_ANSI` text (pl-text.h)."
const ERR_TEXT_ILLEGAL_MULTIBYTE_SEQUENCE = -3
# PORT: pl-text.h ERR_TEXT_INVALID_CODE_POINT
"`PL_canonicalise_text`'s error: a code point that is not Unicode (pl-text.h)."
const ERR_TEXT_INVALID_CODE_POINT = -5

# ORIGINAL: the `mbrtowc` loop that `PL_canonicalise_text`, `PL_text_recode`, `PL_unify_text` and `_text_string` run over an `ENC_ANSI` text
# DIVERGES: upstream's loop does `n -= rc` with `rc` a `size_t`: an incomplete sequence at the end (rc == (size_t)-2) wraps `n` (undefined; the
# pinned build reads out of bounds there). The answer here is `nothing`, what `string_bytes/3` reports as `illegal_multibyte_sequence`.
"The code points of the `n` bytes of the multibyte text `bytes` under the process's LC_CTYPE, `nothing` for an illegal or incomplete sequence or a NUL."
function _ansi_code_points(bytes::Vector{UInt8}, n::Int)::Union{Nothing, Vector{Int}}
    st = zeros(UInt64, MBSTATE_WORDS)                   # `memset(&mbs, 0, sizeof(mbs))`
    cps = Int[]
    i = 1
    left = n
    while left > 0
        rc, wc = _mbrtowc(bytes, i, left, st)
        (rc == -1 || rc == -2 || rc == 0) && return nothing
        push!(cps, wc)
        i += rc
        left -= rc
    end
    return cps
end

# PORT: pl-text.c PL_canonicalise_text
# DIVERGES: an `ENC_WCHAR` text is its code points as native 4-byte `pl_wchar_t`s in `text.text`,
# as upstream's buffer is; the demotion of an all-Latin-1 wide text (`PL_demote_text`) is inline.
# `ENC_ANSI` is `_ansi_code_points` (libc's `mbrtowc` under the process's LC_CTYPE; an ANSI text's `length` counts bytes); `ENC_ASCII` and
# `ENC_UNKNOWN` are upstream's `assert(0)`, an `error()`.
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
        elseif enc === ENC_UTF16LE || enc === ENC_UTF16BE
            # `text.length` is in bytes; `utf16_to_text` (src/pl-string.jl) decodes; its `length` counts units, the
            # canonical text's is the code points (a pair is one)
            r = utf16_to_text(text)
            r isa Int && return r
            text.text = r.text
            text.encoding = r.encoding
            text.length = r.encoding === ENC_WCHAR ? length(r.text) ÷ 4 : length(r.text)
            text.canonical = true
        elseif enc === ENC_ANSI
            cps = _ansi_code_points(text.text, text.length)
            cps === nothing && return ERR_TEXT_ILLEGAL_MULTIBYTE_SEQUENCE
            if any(>(0xff), cps)
                text.text = Vector{UInt8}(reinterpret(UInt8, UInt32.(cps)))
                text.encoding = ENC_WCHAR
            else
                text.text = UInt8.(cps)
                text.encoding = ENC_ISO_LATIN_1
            end
            text.length = length(cps)
            text.canonical = true
        else
            error("PL_canonicalise_text of $enc")       # assert(0)
        end
    end
    return 1                                            # true
end

# PORT: pl-text.c textToAtom
# DIVERGES: the atom table is an argument (`GD->atoms`); a canonicalisation error returns 0 without
# raising (the callers here hold no `ld`; `text_error` is the `ld` form, below).
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

# ── T1 (R2): unifying with a text, comparing and concatenating texts (pl-text.c) ─────────────────
# A text that `PL_get_text` returns for an atom or a string is UTF-8 and not canonical (`PL_chars_t`);
# the functions that index a text — `PL_cmp_text`, `PL_concat_text`, `PL_unify_text_range` — need the
# canonical one (`PL_canonicalise_text`: ISO Latin-1 bytes, or `ENC_WCHAR`, a native `UInt32` per code
# point in `text.text`), as upstream's `PL_get_text` hands it out.

# PORT: pl-text.h PL_text_length
# DIVERGES: also for an `ENC_UTF8` text, whose `length` holds characters (see `PL_chars_t`); upstream
# asserts a canonical encoding (and counts UTF-16 pairs where `wchar_t` is 2 bytes: not here).
"The length of `text` in code points (pl-text.h)."
@inline PL_text_length(text::PL_chars_t)::Int = text.length

# ORIGINAL (T1): the code point at 0-based unit index `i` of an `ENC_WCHAR` text, whatever its `canonical`.
@inline function _wchar_at(t::PL_chars_t, i::Int)::Int
    return Int(reinterpret(UInt32, view(t.text, (4 * i + 1):(4 * i + 4)))[1])
end

# PORT: pl-text.h text_get_char
# DIVERGES: `i` is a 0-based unit index into the vector `text.text`: a byte for `ENC_ISO_LATIN_1`, four
# bytes for `ENC_WCHAR`.
"The code point at 0-based unit index `i` of the canonical `t` (pl-text.h)."
@inline function text_get_char(t::PL_chars_t, i::Int)::Int
    @assert t.canonical "text_get_char: a text that is not canonical"
    t.encoding === ENC_ISO_LATIN_1 && return Int(t.text[i + 1])
    return _wchar_at(t, i)
end

# PORT: pl-text.c PL_seek_text_from
# DIVERGES: `start` and the result are 0-based unit offsets, -1 for upstream's NULL; a unit is a code point
# (`SIZEOF_WCHAR_T` is 4: no UTF-16 surrogate pairs).
"The offset `offset` code points from the offset `start` of `t`, or -1 when it is outside the text (pl-text.c)."
function PL_seek_text_from(t::PL_chars_t, start::Int, offset::Int)::Int
    offset == 0 && return start
    (t.encoding === ENC_ISO_LATIN_1 || t.encoding === ENC_WCHAR) ||
        error("PL_seek_text_from: not a canonical encoding")        # assert(0)
    s = start + offset
    (s < 0 || s > t.length) && return -1
    return s
end

# PORT: pl-text.c PL_seek_text
"The offset of code point `offset` of `t`, or -1 when it is beyond the end (pl-text.c)."
PL_seek_text(t::PL_chars_t, offset::Int)::Int = PL_seek_text_from(t, 0, offset)

# PORT: pl-text.c PL_seek_text_rev
"The offset `offset` code points before the end of `t`, or -1 (pl-text.c)."
PL_seek_text_rev(t::PL_chars_t, offset::Int)::Int = PL_seek_text_from(t, t.length, -offset)

# PORT: pl-text.c PL_cmp_text
# DIVERGES: one loop over `text_get_char` for upstream's four, one per pair of encodings (the same
# comparison: a code point per unit).
"""
Compare `len` code points of `t1` from `o1` with those of `t2` from `o2` (pl-text.c): `CMP_LESS`, `CMP_EQUAL` or
`CMP_GREATER`; a text that ends first is the lesser, an offset outside a text makes it the greater of the two
unless the other is outside too.
"""
function PL_cmp_text(t1::PL_chars_t, o1::Int, t2::PL_chars_t, o2::Int, len::Int)::Int
    s1 = PL_seek_text(t1, o1)
    s2 = PL_seek_text(t2, o2)

    if s1 >= 0 && s2 >= 0
        e1 = PL_seek_text_rev(t1, 0)
        e2 = PL_seek_text_rev(t2, 0)
        s = s1
        q = s2

        while true
            len == 0 && return CMP_EQUAL                    # CMP_LENGTH: len-- == 0
            len -= 1
            s >= e1 && return CMP_LESS
            q >= e2 && return CMP_GREATER
            c1 = text_get_char(t1, s)
            c2 = text_get_char(t2, q)
            s += 1
            q += 1
            c1 != c2 && return c1 > c2 ? CMP_GREATER : CMP_LESS      # CMP_CHARS
        end
    elseif s1 >= 0                                          # s1 && !s2
        return CMP_GREATER
    elseif s2 >= 0                                          # s2 && !s1
        return CMP_LESS
    else
        return CMP_EQUAL
    end
end

# PORT: pl-text.c can_demote
"Whether every code point of the canonical `text` is below 0x100 (pl-text.c)."
function can_demote(text::PL_chars_t)::Bool
    if text.encoding !== ENC_ISO_LATIN_1
        for i in 0:(text.length - 1)
            text_get_char(text, i) > 0xff && return false
        end
    end
    return true
end

# PORT: pl-text.c PL_concat_text
# DIVERGES: the texts are a vector and the result is returned (it cannot fail: no `PL_malloc`); an
# `ENC_WCHAR` text that `can_demote` is copied code point by code point (upstream `memcpy`s its bytes: only
# canonical texts reach it, and a canonical wide text has a code point above 0xFF).
"The canonical text of the canonical texts `text` one after the other (pl-text.c)."
function PL_concat_text(text::Vector{PL_chars_t})::PL_chars_t
    total_length = 0
    latin = true

    for t in text
        if latin && !can_demote(t)
            latin = false
        end
        total_length += t.length
    end

    if latin
        to = Vector{UInt8}(undef, total_length)
        n = 0
        for t in text
            if t.encoding === ENC_ISO_LATIN_1
                copyto!(to, n + 1, t.text, 1, t.length)
                n += t.length
            else
                for i in 0:(t.length - 1)
                    n += 1
                    to[n] = UInt8(text_get_char(t, i))
                end
            end
        end
        return PL_chars_t(to, total_length, ENC_ISO_LATIN_1, true)
    else
        w = Vector{UInt32}(undef, total_length)
        n = 0
        for t in text
            for i in 0:(t.length - 1)
                n += 1
                w[n] = UInt32(text_get_char(t, i))
            end
        end
        return PL_chars_t(
            Vector{UInt8}(reinterpret(UInt8, w)), total_length, ENC_WCHAR, true
        )
    end
end

# PORT: pl-text.c text_error
# DIVERGES: an unknown code is upstream's `assert(0)`, an `error()`. `ERR_TEXT_ILLEGAL_UTF8` is given by no caller at the pin
# (`PL_canonicalise_text` of UTF-8 has no error path), the other four are `PL_canonicalise_text`'s and `utf16_to_text`'s.
"Raise the error for `PL_canonicalise_text`'s result `rc`; false (pl-text.c)."
function text_error(ld::PL_local_data{T}, rc::Int)::Bool where {T}
    rc == ERR_TEXT_ILLEGAL_UTF8 && return PL_syntax_error(ld, "illegal_utf8_sequence", nothing)
    rc == ERR_TEXT_ILLEGAL_UTF16 && return PL_syntax_error(ld, "illegal_utf16_sequence", nothing)
    rc == ERR_TEXT_ILLEGAL_MULTIBYTE_SEQUENCE &&
        return PL_syntax_error(ld, "illegal_multibyte_sequence", nothing)
    rc == ERR_TEXT_INCOMPLETE_MULTIBYTE_SEQUENCE &&
        return PL_syntax_error(ld, "incomplete_multibyte_sequence", nothing)
    rc == ERR_TEXT_INVALID_CODE_POINT &&
        return PL_error(ld, ERR_REPRESENTATION, mk_sym(T, :code_point))   # PL_representation_error("code_point")
    error("text_error: unknown code $rc")               # assert(0)
end

# PORT: pl-text.c PL_canonicalise_text_ex
"Canonicalise `text`, raising the error of a failure; false then (pl-text.c)."
function PL_canonicalise_text_ex(ld::PL_local_data{T}, text::PL_chars_t)::Bool where {T}
    rc = PL_canonicalise_text(text)
    rc == 1 && return true
    return text_error(ld, rc)
end

# ORIGINAL: pl-text.c `wctobuffer` over the characters of `cps`, then `wctobuffer(0, &mbs, b)`, on a zeroed `mbstate_t`
# (the two loops of `PL_mb_text`'s `ENC_MB` target).
# DIVERGES: the bytes go into the vector `b` (no `Buffer`); the NUL that ends upstream's buffer is dropped here (`sizeOfBuffer(b)-1`).
"Append the multibyte bytes of the code points `cps` to `b`; -1, or the code point that has no representation."
function _wctobuffer_all!(b::Vector{UInt8}, cps)::Int
    st = zeros(UInt64, MBSTATE_WORDS)                   # memset(&mbs, 0, sizeof(mbs))
    for c in cps
        r = _wcrtomb(Int(c), st)
        r === nothing && return Int(c)                  # wctobuffer: false, `norep = c`
        append!(b, r)
    end
    r = _wcrtomb(0, st)                                 # wctobuffer(0, &mbs, b): the shift sequence and the NUL
    if r !== nothing
        append!(b, r)
        pop!(b)                                         # the NUL: `text->length = sizeOfBuffer(b)-1`
    end
    return -1
end

# PORT: pl-text.c PL_mb_text
# DIVERGES: the verdict is an `Int` (`_mb_text`: -1 done, -2 `PL_demote_text` failed, otherwise the character with no
# representation, upstream's `norep`); an `ENC_UTF8` text is the kernel's own (`PL_get_text`) and is left as it is when
# the target is UTF-8, its `length` in characters; any other source encoding is upstream's `assert(0)`, an `error()`.
# The `ld` form raises what upstream's `rep_error` and `PL_demote_text` raise under `CVT_EXCEPTION`; the form without `ld`
# (callers `x_chars`, `PL_text_recode`) gives only the verdict.
"""
    _mb_text(text, flags) -> Int

Recode the canonical `text` to the target `flags` name (`REP_UTF8`: UTF-8, `REP_MB`: the locale's multibyte
encoding, else ISO Latin-1), its `length` then in bytes (pl-text.c `PL_mb_text`).
"""
function _mb_text(text::PL_chars_t, flags::UInt32)::Int
    target = (flags & REP_UTF8) != 0 ? ENC_UTF8 : (flags & REP_MB) != 0 ? ENC_ANSI : ENC_ISO_LATIN_1
    text.encoding === target && return -1
    b = UInt8[]
    if text.encoding === ENC_ISO_LATIN_1
        if target === ENC_UTF8
            for c in text.text
                utf8_put_char(b, Int(c))                # utf8tobuffer(*s, b)
            end
        else
            norep = _wctobuffer_all!(b, text.text)
            norep == -1 || return norep
        end
    elseif text.encoding === ENC_WCHAR
        if target === ENC_ISO_LATIN_1
            for i in 0:(text.length - 1)                # PL_demote_text(text, flags)
                _wchar_at(text, i) > 0xff && return -2
            end
            text.text = UInt8[UInt8(_wchar_at(text, i)) for i in 0:(text.length - 1)]
            text.encoding = ENC_ISO_LATIN_1
            text.canonical = true
            return -1
        elseif target === ENC_UTF8
            for i in 0:(text.length - 1)
                utf8_put_char(b, _wchar_at(text, i))    # get_wchar(), utf8tobuffer(c, b)
            end
        else
            norep = _wctobuffer_all!(b, (_wchar_at(text, i) for i in 0:(text.length - 1)))
            norep == -1 || return norep
        end
    else
        error("PL_mb_text of $(text.encoding)")         # assert(0)
    end
    text.length = length(b)
    text.text = b
    text.encoding = target
    text.canonical = (target === ENC_ISO_LATIN_1)
    return -1
end

"Recode the canonical `text` to the target of `flags` (pl-text.c `PL_mb_text`); false when a character has no representation."
PL_mb_text(text::PL_chars_t, flags::UInt32)::Bool = _mb_text(text, flags) == -1

"""
Recode the canonical `text` to the target of `flags`; with `CVT_EXCEPTION` the failure is raised (pl-text.c `PL_mb_text`):
`representation_error(encoding)` for a wide text that is not ISO Latin-1 and for a character the locale has no
multibyte sequence for.
"""
function PL_mb_text(ld::PL_local_data{T}, text::PL_chars_t, flags::UInt32)::Bool where {T}
    rc = _mb_text(text, flags)
    rc == -1 && return true
    (flags & CVT_EXCEPTION) == 0 && return false
    rc == -2 && return text_representation_error(ld, ENC_ISO_LATIN_1)       # PL_demote_text's reperr
    msg = "Cannot represent char U" * string(rc, base = 16, pad = 4) * " using current locale encoding"
    return PL_error(ld, "", 0, msg, ERR_REPRESENTATION, mk_sym(T, :encoding))
end

# ORIGINAL (T1): the characters of `text` as a Julia `String` — the bytes the term interface holds an atom or
# a string as (upstream: `textToAtom`/`textToString` store the text itself).
"The `String` of the characters of `text`, in any of its encodings."
function _text_string(text::PL_chars_t)::String
    text.encoding === ENC_UTF8 && return String(copy(text.text))
    b = UInt8[]
    sizehint!(b, text.length)
    if text.encoding === ENC_ISO_LATIN_1
        for c in text.text
            utf8_put_char(b, Int(c))
        end
    elseif text.encoding === ENC_WCHAR
        for i in 0:(text.length - 1)
            utf8_put_char(b, _wchar_at(text, i))
        end
    else
        throw(
            NotPortedError{Nothing}(
                nothing, "the string of a text in $(text.encoding)", "no caller"
            )
        )
    end
    return String(b)
end

# ORIGINAL (T1): the code points of `text`, in order (what `unify_text` walks for a list).
"The code points of `text`, in any of its encodings."
function _text_code_points(text::PL_chars_t)::Vector{Int}
    cps = Int[]
    sizehint!(cps, text.length)
    if text.encoding === ENC_ISO_LATIN_1
        for c in text.text
            push!(cps, Int(c))
        end
    elseif text.encoding === ENC_WCHAR
        for i in 0:(text.length - 1)
            push!(cps, _wchar_at(text, i))
        end
    elseif text.encoding === ENC_UTF8
        b = text.text
        i = 1
        while i <= length(b)
            i, chr = utf8_get_char(b, i)
            push!(cps, chr)
        end
    else
        throw(
            NotPortedError{Nothing}(
                nothing, "the code points of a text in $(text.encoding)", "no caller"
            )
        )
    end
    return cps
end

# PORT: pl-text.c PL_unify_text
# DIVERGES: (upstream: PL_unify_text → unify_text) an atom is the term interface's symbol of the text (`textToAtom`), a string its grounded value
# (`textToString`); a list is made cell by cell with `PL_unify_list` on a fresh reference and unified with
# `term` at the end (upstream lays the cells out with `INIT_SEQ_STRING`/`EXTEND_SEQ_*` and unifies `l` with
# `term` in `CLOSE_SEQ_STRING`: the same list, the same unification); `PL_STRING` and `PL_ATOM` canonicalise
# `text` in place, as upstream. NOT PORTED: `ENC_ANSI` texts (no producer).
"""
Unify `term` with `text` made a `type`: `PL_ATOM`, `PL_STRING`, `PL_CODE_LIST` or `PL_CHAR_LIST` (pl-text.c). For
a list, `tail` (a term reference, 0: none) is left holding the list's unbound end instead of `[]`.
"""
function PL_unify_text(
    ld::PL_local_data{T}, term::term_t, tail::term_t, text::PL_chars_t, type::Int
)::Bool where {T}
    if type == PL_ATOM
        PL_canonicalise_text(text) == 1 || return false             # textToAtom(): 0
        return PL_unify_atom(ld, term, _atom_from_text(T, _text_string(text)))
    elseif type == PL_STRING
        rc = PL_canonicalise_text(text)
        rc == 1 || return text_error(ld, rc)
        return PL_unify_atomic(ld, term, mk_gnd(T, _text_string(text)))
    elseif type == PL_CODE_LIST || type == PL_CHAR_LIST
        if text.length == 0
            if tail != 0
                PL_put_term(ld, tail, term)
                return true
            else
                return PL_unify_nil(ld, term)
            end
        else
            cps = _text_code_points(text)
            l = PL_new_term_ref(ld)
            l == 0 && return false
            head = PL_new_term_ref(ld)
            lstart = PL_copy_term_ref(ld, l)                       # the list's start
            for c in cps
                PL_unify_list(ld, l, head, l) || return false
                if type == PL_CODE_LIST                             # EXTEND_SEQ_CODES
                    PL_unify_integer(ld, head, c) || return false
                else                                                # EXTEND_SEQ_CHARS
                    PL_unify_atom(ld, head, codeToAtom(T, c)) || return false
                end
            end
            rc = if tail != 0                                       # CLOSE_SEQ_STRING
                PL_unify(ld, lstart, term) && PL_put_term(ld, tail, l)
            else
                PL_unify_nil(ld, l) && PL_unify(ld, lstart, term)
            end
            PL_reset_term_refs(ld, l)
            return rc
        end
    else
        error("PL_unify_text: unknown type $type")                  # assert(0)
    end
end

# PORT: pl-text.c unify_text_between
# DIVERGES: `from` and `upto` are 0-based unit offsets; the sub-text is a copy of its units.
"Unify `term` with the units `from` up to `upto` of the canonical `text`, made a `type` (pl-text.c)."
function unify_text_between(
    ld::PL_local_data{T}, term::term_t, text::PL_chars_t, from::Int, upto::Int, type::Int
)::Bool where {T}
    len = upto - from

    if len == 1 && type == PL_ATOM && upto > from
        return PL_unify_atom(ld, term, codeToAtom(T, text_get_char(text, from)))
    end

    sub = if text.encoding === ENC_ISO_LATIN_1
        PL_chars_t(text.text[(from + 1):upto], len, ENC_ISO_LATIN_1, true)
    else
        PL_chars_t(text.text[(4 * from + 1):(4 * upto)], len, ENC_WCHAR, false)
    end
    return PL_unify_text(ld, term, 0, sub, type)
end

# PORT: pl-text.c PL_unify_text_range
"Unify `term` with `len` code points of the canonical `text` from `offset`, made a `type`; false when out of range (pl-text.c)."
function PL_unify_text_range(
    ld::PL_local_data{T}, term::term_t, text::PL_chars_t, offset::Int, len::Int, type::Int
)::Bool where {T}
    from = PL_seek_text(text, offset)
    upto = from >= 0 ? PL_seek_text_from(text, from, len) : -1
    @assert text.canonical "PL_unify_text_range: a text that is not canonical"

    (from < 0 || upto < 0) && return false                              # offset > length
    return unify_text_between(ld, term, text, from, upto, type)
end

# ORIGINAL (Y1): upstream hands a C string to its callers (`PL_get_nchars` with `REP_FN`/`REP_UTF8`); the
# kernel's callers want a Julia `String`. The text of `txt` in UTF-8: an ISO Latin-1 text recoded.
"The text `txt` holds as a `String` (UTF-8); an ISO Latin-1 text is recoded, a wide text is refused."
function text_string(txt::PL_chars_t)::String
    if txt.encoding === ENC_UTF8
        return String(copy(txt.text))
    elseif txt.encoding === ENC_ISO_LATIN_1 || txt.encoding === ENC_OCTET
        return String(Char[Char(b) for b in txt.text])
    end
    throw(ArgumentError("text_string: a text in $(txt.encoding) is not converted"))
end
