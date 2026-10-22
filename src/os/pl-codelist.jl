# UPSTREAM: swipl-devel src/os/pl-codelist.c @ 8e1bc1110be4
# CLASS: code
# COPYRIGHT: Copyright (c)  2011-2014, University of Amsterdam
#
# CODE AND CHARACTER LISTS (pl-codelist.c), since R1d: the text a list of character codes or of
# one-character atoms holds (`codes_or_chars_to_buffer`), which `PL_get_text` (src/os/pl-text.jl)
# reads for `CVT_LIST` — so `term_to_atom(T, [0'a])` reads `a`.

# PORT: pl-codelist.c codes_or_chars_to_buffer
# DIVERGES: returns the text's bytes and the result, the bytes `nothing` where upstream returns
# NULL: ISO Latin-1 bytes, or for `wide` the text in UTF-8 where upstream holds `pl_wchar_t` (the
# term interface's texts are UTF-8); no buffer ring (`flags`: `BUF_*`). On the WORDS (f3b-5a):
# `valHandle(l)`, `argTermP` + `deRef` as `_deref_loc`, the cycle test on the compound words, the
# culprit its cell's position (`CVT_result`). The boundary — `l` or a tail of its list a slot's side
# value or a keyed variable — is read on terms (`_codes_or_chars_to_buffer_terms`), an element
# there as its term (`_cvt_arg_boundary`), counted in `cold_pairs` (TRANSITIONAL: f3).
"""
The text the code list or character list `l` holds (pl-codelist.c), and the conversion's result:
`CVT_partial` for a partial list or an unbound element, `CVT_nolist` for no (or a cyclic) list,
`CVT_nocode`/`CVT_nochar` with the culprit's cell, `CVT_wide` for a character above 0xFF when not
`wide`.
"""
function codes_or_chars_to_buffer(
    ld::PL_local_data{T}, l::term_t, wide::Bool
)::Tuple{Union{Nothing, Vector{UInt8}}, CVT_result} where {T}
    result = CVT_result(CVT_ok, 0)
    lk, list, _ = _deref_loc(ld, -(l + 1))                  # word list = valHandle(l)
    lk == DU_TERM && return _codes_or_chars_to_buffer_terms(ld, l, wide)   # the boundary
    CHARS, CODES = 0, 1
    type = CHARS

    if _is_list_word(ld, lk, list)                          # isList(list)
        c = -1
        ak, aw, ap = _deref_loc(ld, valPtr(list) + 1)       # arg = argTermP(list, 0); deRef(arg)
        tagged, i, chr, bind = _cvt_arg(ld, ak, aw, ap, true)
        if tagged                                           # isTaggedInt(*arg)
            c = i                                           # valInt(*arg)
            type = CODES
        else
            c = chr                                         # charCode(*arg)
            type = CHARS
        end
        result.culprit = ap                                 # result->culprit = *arg
        if c < 0 || c > 0x10ffff || (!wide && c > 0xff)
            if bind                                         # canBind(*arg)
                result.status = CVT_partial
            elseif c < 0 || c > 0x10ffff
                result.status = CVT_nocode
            elseif IS_UTF16_SURROGATE(c)
                result.status = CVT_nocode
            elseif c > 0xff
                result.status = CVT_wide
            end
            return (nothing, result)
        end
    elseif lk == DU_WORD && list == ld.atom_nil_w           # isNil(list)
        return (UInt8[], result)
    else
        result.status = lk == DU_CELL ? CVT_partial : CVT_nolist   # canBind(list)
        return (nothing, result)
    end

    b = UInt8[]
    slow = list
    step_slow = true
    while _is_list_word(ld, lk, list)                       # isList(list)
        c = -1
        ak, aw, ap = _deref_loc(ld, valPtr(list) + 1)       # arg = argTermP(list, 0); deRef(arg)
        tagged, i, chr, bind = _cvt_arg(ld, ak, aw, ap, type == CHARS)
        if type == CODES
            tagged && (c = i)                               # isTaggedInt(*arg): valInt(*arg)
        else
            c = chr                                         # charCode(*arg)
        end

        if c < 0 || c > 0x10ffff || (!wide && c > 0xff)
            result.culprit = ap                             # result->culprit = *arg
            if bind                                         # canBind(*arg)
                result.status = CVT_partial
            elseif c < 0 || c > 0x10ffff || IS_UTF16_SURROGATE(c)
                result.status = type == CODES ? CVT_nocode : CVT_nochar
            elseif c > 0xff
                result.status = CVT_wide
            end
            return (nothing, result)
        end

        if wide
            utf8_put_char(b, c)
        else
            push!(b, UInt8(c))
        end

        lk, list, _ = _deref_loc(ld, valPtr(list) + 2)      # tail = argTermP(list, 1); deRef(tail)
        lk == DU_TERM && return _codes_or_chars_to_buffer_terms(ld, l, wide)   # the boundary
        if list == slow                                     # cyclic: list = *tail; list == slow
            result.status = CVT_nolist
            return (nothing, result)
        end
        if (step_slow = !step_slow)
            _, slow, _ = _deref_loc(ld, valPtr(slow) + 2)   # tail = argTermP(slow, 1); deRef(tail)
        end
    end
    if !(lk == DU_WORD && list == ld.atom_nil_w)            # !isNil(list)
        result.status = lk == DU_CELL ? CVT_partial : CVT_nolist   # canBind(list)
        return (nothing, result)
    end

    result.status = CVT_ok
    return (b, result)
end

# ORIGINAL (f3b-5a): what codes_or_chars_to_buffer's tests read of an element `*arg` at a
# dereferenced location — `isTaggedInt` and `valInt`, `charCode` (when `chars`), `canBind` — on the
# words: an atom word's character from its symbol (`_atom_value`: no export), a value-table entry
# by the term type's `isTaggedInt` (a type with no tagged words holds a small integer there), the
# boundary on its term (`_cvt_arg_boundary`).
"An element's `(isTaggedInt, valInt, charCode, canBind)` at a dereferenced location."
@inline function _cvt_arg(
    ld::PL_local_data{T}, k::UInt8, w::word, p::Int, chars::Bool
)::Tuple{Bool, Int, Int, Bool} where {T}
    k == DU_CELL && return (false, 0, -1, true)            # canBind(*arg)
    if k == DU_WORD                                         # an atom, or a compound (no character)
        (chars && isAtomW(w)) || return (false, 0, -1, false)
        return (false, 0, charCode(_atom_value(ld, w)), false)
    elseif k == DU_VALUE
        isTaggedIntW(w) && return (true, Int(valInt(w)), -1, false)    # isTaggedInt(*arg)
        v = ld.vtable[valPtr(w)]
        isTaggedInt(v) && return (true, Int(int64_value(v)), -1, false)
        return (false, 0, chars ? charCode(v) : -1, false)
    end
    return _cvt_arg_boundary(ld, w, p, chars)
end

# ORIGINAL (f3b-5a): THE BOUNDARY of `_cvt_arg` — an element that is a keyed variable's value-table
# word — read as its term, counted in `cold_pairs`. TRANSITIONAL: goes with the keyed variables
# (f3).
"An element's `(isTaggedInt, valInt, charCode, canBind)` at a boundary location, on its term."
@noinline function _cvt_arg_boundary(
    ld::PL_local_data{T}, w::word, p::Int, chars::Bool
)::Tuple{Bool, Int, Int, Bool} where {T}
    ld.cold_pairs += 1
    a = deRef(ld, _loc_term(ld, DU_TERM, w, p))
    isTaggedInt(a) && return (true, Int(int64_value(a)), -1, false)
    return (false, 0, chars ? charCode(a) : -1, canBind(a))
end

# ORIGINAL (f3b-5a): THE BOUNDARY of codes_or_chars_to_buffer — `l`, or a tail of its list, a slot's
# side value or a keyed variable: the whole list read on its TERM, as the reader was until f3b-5a
# (`deRef` through the bindings; the cycle test on the memoised exports, `===`), counted in
# `cold_pairs`; a `CVT_nocode`/`CVT_nochar` culprit is stored in a fresh cell
# (`_cvt_culprit_cell!`).
# TRANSITIONAL: goes with the keyed variables and the side values (f3).
"`codes_or_chars_to_buffer` of term reference `l` on its term (the boundary)."
@noinline function _codes_or_chars_to_buffer_terms(
    ld::PL_local_data{T}, l::term_t, wide::Bool
)::Tuple{Union{Nothing, Vector{UInt8}}, CVT_result} where {T}
    ld.cold_pairs += 1
    result = CVT_result(CVT_ok, 0)
    k, x, q = _deref_loc(ld, -(l + 1))
    list = deRef(ld, _loc_term(ld, k, x, q))
    CHARS, CODES = 0, 1
    type = CHARS

    if is_pair(list)                                # isList(list)
        c = -1
        arg = deRef(ld, child(list, 2))
        if isTaggedInt(arg)
            c = Int(int64_value(arg))
            type = CODES
        else
            c = charCode(arg)
            type = CHARS
        end
        if c < 0 || c > 0x10ffff || (!wide && c > 0xff)
            if canBind(arg)
                result.status = CVT_partial
            elseif c < 0 || c > 0x10ffff
                result.status = CVT_nocode
            elseif IS_UTF16_SURROGATE(c)
                result.status = CVT_nocode
            elseif c > 0xff
                result.status = CVT_wide
            end
            result.status == CVT_nocode && (result.culprit = _cvt_culprit_cell!(ld, arg))
            return (nothing, result)
        end
    elseif is_nil(list)
        return (UInt8[], result)
    else
        result.status = canBind(list) ? CVT_partial : CVT_nolist
        return (nothing, result)
    end

    b = UInt8[]
    slow = list
    step_slow = true
    while is_pair(list)
        c = -1
        arg = deRef(ld, child(list, 2))
        if type == CODES
            isTaggedInt(arg) && (c = Int(int64_value(arg)))
        else
            c = charCode(arg)
        end

        if c < 0 || c > 0x10ffff || (!wide && c > 0xff)
            if canBind(arg)
                result.status = CVT_partial
            elseif c < 0 || c > 0x10ffff || IS_UTF16_SURROGATE(c)
                result.status = type == CODES ? CVT_nocode : CVT_nochar
                result.culprit = _cvt_culprit_cell!(ld, arg)
            elseif c > 0xff
                result.status = CVT_wide
            end
            return (nothing, result)
        end

        if wide
            utf8_put_char(b, c)
        else
            push!(b, UInt8(c))
        end

        list = deRef(ld, child(list, 3))
        if list === slow                            # cyclic
            result.status = CVT_nolist
            return (nothing, result)
        end
        if (step_slow = !step_slow)
            slow = deRef(ld, child(slow, 3))
        end
    end
    if !is_nil(list)
        result.status = canBind(list) ? CVT_partial : CVT_nolist
        return (nothing, result)
    end

    result.status = CVT_ok
    return (b, result)
end

# ORIGINAL (f3b-5a): the boundary's culprit `c` (a term: an element read on terms) in a fresh global
# cell, as a term reference takes it (`_word_of!`); its position. TRANSITIONAL, as the boundary
# (f3).
"A fresh global cell holding the boundary culprit `c`; its position."
@noinline function _cvt_culprit_cell!(ld::PL_local_data{T}, c::T)::Int where {T}
    w = _word_of!(ld, c)
    p = allocGlobalCells!(ld, 1)
    ld.gstack[p] = w
    return p
end
