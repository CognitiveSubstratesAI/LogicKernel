# UPSTREAM: swipl-devel src/os/pl-codelist.c @ bae881a2
# CLASS: code
# COPYRIGHT: Copyright (c)  2011-2014, University of Amsterdam
#
# CODE AND CHARACTER LISTS (pl-codelist.c), since R1d: the text a list of character codes or of
# one-character atoms holds (`codes_or_chars_to_buffer`), which `PL_get_text` (src/os/pl-text.jl)
# reads for `CVT_LIST` — so `term_to_atom(T, [0'a])` reads `a`.

# PORT: pl-codelist.c codes_or_chars_to_buffer
# DIVERGES: returns the text's bytes and the result, the bytes `nothing` where upstream returns
# NULL: ISO Latin-1 bytes, or for `wide` the text in UTF-8 where upstream holds `pl_wchar_t` (the
# term interface's texts are UTF-8); no buffer ring (`flags`: `BUF_*`); the list is read through
# the bindings (`deRef`), and a cell is the slow pointer's cell when it is the same value (`===`:
# a cyclic list is one through a binding).
"""
The text the code list or character list `l` holds (pl-codelist.c), and the conversion's result:
`CVT_partial` for a partial list or an unbound element, `CVT_nolist` for no (or a cyclic) list,
`CVT_nocode`/`CVT_nochar` with the culprit, `CVT_wide` for a character above 0xFF when not `wide`.
"""
function codes_or_chars_to_buffer(
    ld::PL_local_data{T}, l::term_t, wide::Bool
)::Tuple{Union{Nothing, Vector{UInt8}}, CVT_result{T}} where {T}
    result = CVT_result{T}(CVT_ok, nothing)
    list = deRef(ld, ld.slots[l + 1])
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
        result.culprit = arg
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
            result.culprit = arg
            if canBind(arg)
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
