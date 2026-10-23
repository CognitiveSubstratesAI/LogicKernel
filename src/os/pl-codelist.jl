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
# culprit its cell's position (`CVT_result`).
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
# by the term type's `isTaggedInt` (a type with no tagged words holds a small integer there).
"An element's `(isTaggedInt, valInt, charCode, canBind)` at a dereferenced location."
@inline function _cvt_arg(
    ld::PL_local_data{T}, k::UInt8, w::word, p::Int, chars::Bool
)::Tuple{Bool, Int, Int, Bool} where {T}
    k == DU_CELL && return (false, 0, -1, true)            # canBind(*arg)
    if k == DU_WORD                                         # an atom, or a compound (no character)
        (chars && isAtomW(w)) || return (false, 0, -1, false)
        return (false, 0, charCode(_atom_value(ld, w)), false)
    end
    isTaggedIntW(w) && return (true, Int(valInt(w)), -1, false)    # DU_VALUE: isTaggedInt(*arg)
    v = ld.vtable[valPtr(w)]
    isTaggedInt(v) && return (true, Int(int64_value(v)), -1, false)
    return (false, 0, chars ? charCode(v) : -1, false)
end
