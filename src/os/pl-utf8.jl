# UPSTREAM: swipl-devel src/os/pl-utf8.c @ bae881a2
# UPSTREAM: swipl-devel src/os/pl-utf8.h @ bae881a2
# CLASS: code
# COPYRIGHT: Copyright (c)  2011-2021, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# UTF-8 decoding and encoding over a byte buffer (since R1c): the reader's buffer and the streams'
# buffers hold UTF-8. A `char *` is a position in a byte vector: these functions take the vector
# and a 1-based index, and return the next index with the code point they read, where upstream
# returns the moved pointer and writes the code point through `int *chr`. Reading past the end
# reads a 0 byte, as upstream's buffers are 0-terminated (the reader's always is; see `_byte`).

# PORT: pl-utf8.h UNICODE_MAX
"The highest Unicode code point (pl-utf8.h)."
const UNICODE_MAX = Int(0x10FFFF)
# PORT: pl-utf8.h UTF8_MALFORMED_REPLACEMENT
"The code point that stands for a malformed UTF-8 sequence (pl-utf8.h)."
const UTF8_MALFORMED_REPLACEMENT = Int(0xfffd)

# The byte at `i`, 0 past the end: a C buffer's terminator, which upstream reads there.
"The byte at index `i` of `b`, or 0 past its end (a C string's terminator)."
@inline _byte(b::AbstractVector{UInt8}, i::Int)::Int = i <= length(b) ? Int(b[i]) : 0

# PORT: pl-utf8.h ISUTF8_MB
"Is `c` a multi-byte sequence's first byte (pl-utf8.h)?"
ISUTF8_MB(c::Int)::Bool = (c % UInt32) >= 0xc0 && (c % UInt32) <= 0xfd
# PORT: pl-utf8.h ISUTF8_CB
"Is `c` a continuation byte (pl-utf8.h)?"
ISUTF8_CB(c::Int)::Bool = (c & 0xc0) == 0x80
# PORT: pl-utf8.h ISUTF8_FB2
"Is `c` the first byte of a two-byte sequence (pl-utf8.h)?"
ISUTF8_FB2(c::Int)::Bool = (c & 0xe0) == 0xc0
# PORT: pl-utf8.h ISUTF8_FB3
"Is `c` the first byte of a three-byte sequence (pl-utf8.h)?"
ISUTF8_FB3(c::Int)::Bool = (c & 0xf0) == 0xe0
# PORT: pl-utf8.h ISUTF8_FB4
"Is `c` the first byte of a four-byte sequence (pl-utf8.h)?"
ISUTF8_FB4(c::Int)::Bool = (c & 0xf8) == 0xf0
# PORT: pl-utf8.h ISUTF8_FB5
"Is `c` the first byte of a five-byte sequence (pl-utf8.h)?"
ISUTF8_FB5(c::Int)::Bool = (c & 0xfc) == 0xf8
# PORT: pl-utf8.h ISUTF8_FB6
"Is `c` the first byte of a six-byte sequence (pl-utf8.h)?"
ISUTF8_FB6(c::Int)::Bool = (c & 0xfe) == 0xfc

# PORT: pl-utf8.h UTF8_FBN
"How many continuation bytes follow the first byte `c`; -1 if it cannot start a sequence."
function UTF8_FBN(c::Int)::Int
    return if (c & 0x80) == 0
        0
    elseif ISUTF8_FB2(c)
        1
    elseif ISUTF8_FB3(c)
        2
    elseif ISUTF8_FB4(c)
        3
    elseif ISUTF8_FB5(c)
        4
    elseif ISUTF8_FB6(c)
        5
    else
        -1
    end
end

# PORT: pl-utf8.h UTF8_FBV
"The value bits of the first byte `c` of a sequence with `n` continuation bytes (pl-utf8.h)."
UTF8_FBV(c::Int, n::Int)::Int = n == 0 ? c : (c & ((0x01 << (6 - n)) - 1))

# PORT: pl-utf8.h IS_UTF16_SURROGATE
"Is `c` a UTF-16 surrogate (pl-utf8.h)?"
IS_UTF16_SURROGATE(c::Int)::Bool = c >= 0xD800 && c <= 0xDFFF

# PORT: pl-utf8.h VALID_CODE_POINT
"Is `c` a valid Unicode code point: in range, and not a surrogate (pl-utf8.h)?"
VALID_CODE_POINT(c::Int)::Bool = c >= 0 && c <= UNICODE_MAX && !IS_UTF16_SURROGATE(c)

# PORT: pl-utf8.c _PL__utf8_code_point
# DIVERGES: `i` and `e` are indices into `b` (`e` 0 for upstream's NULL: no limit), and the moved
# index is returned beside the count and the code point, where upstream moves `*i` and writes `*cp`.
"""
Decode the UTF-8 sequence at index `i` of `b`, not reading at or beyond index `e` (0: no limit).
Return `(n, next, cp)`: the bytes consumed, or -1 for an invalid sequence (which consumes one
byte), the index after them, and the code point (`UTF8_MALFORMED_REPLACEMENT` for a surrogate).
"""
function _PL__utf8_code_point(
    b::AbstractVector{UInt8}, i::Int, e::Int
)::Tuple{Int, Int, Int}
    c = _byte(b, i)
    i += 1
    cp = c
    c < 0x80 && return (1, i, cp)
    c < 0xc0 && return (-1, i, cp)
    if c < 0xe0
        code = c & 0x1f
        n = 1
    elseif c < 0xf0
        code = c & 0x0f
        n = 2
    elseif c < 0xf8
        code = c & 0x07
        n = 3
    elseif c < 0xfc
        code = c & 0x03
        n = 4
    elseif c < 0xfe
        code = c & 0x01
        n = 5
    else
        return (-1, i, cp)
    end
    for k in 0:(n - 1)
        i + k == e && return (-1, i, cp)
        c = _byte(b, i + k)
        (c < 0x80 || c >= 0xc0) && return (-1, i, cp)
        code = (code << 6) | (c & 0x3f)
    end
    i += n
    cp = code
    IS_UTF16_SURROGATE(code) && return (-1, i, UTF8_MALFORMED_REPLACEMENT)
    return (n + 1, i, cp)
end

# PORT: pl-utf8.c _PL__utf8_get_char
"Decode the sequence at index `i` of `b`: `(next, chr)` (the deprecated API, pl-utf8.c)."
function _PL__utf8_get_char(b::AbstractVector{UInt8}, i::Int)::Tuple{Int, Int}
    _, next, chr = _PL__utf8_code_point(b, i, 0)
    return (next, chr)
end

# PORT: pl-utf8.h utf8_get_char
"Decode the character at index `i` of `b`: `(next, chr)`; one byte when it is ASCII (pl-utf8.h)."
@inline function utf8_get_char(b::AbstractVector{UInt8}, i::Int)::Tuple{Int, Int}
    c = _byte(b, i)
    return (c & 0x80) != 0 ? _PL__utf8_get_char(b, i) : (i + 1, c)
end

# PORT: pl-utf8.c _PL__utf8_put_char
# DIVERGES: the bytes are pushed onto `out`, where upstream writes them at `out` and returns the
# moved pointer.
"Append the UTF-8 bytes of `chr` to `out` (pl-utf8.c; up to six bytes, as upstream encodes)."
function _PL__utf8_put_char(out::Vector{UInt8}, chr::Int)::Nothing
    if chr < 0x80
        push!(out, chr % UInt8)
    elseif chr < 0x800
        push!(out, (0xc0 | ((chr >> 6) & 0x1f)) % UInt8)
        push!(out, (0x80 | (chr & 0x3f)) % UInt8)
    elseif chr < 0x10000
        push!(out, (0xe0 | ((chr >> 12) & 0x0f)) % UInt8)
        push!(out, (0x80 | ((chr >> 6) & 0x3f)) % UInt8)
        push!(out, (0x80 | (chr & 0x3f)) % UInt8)
    elseif chr < 0x200000
        push!(out, (0xf0 | ((chr >> 18) & 0x07)) % UInt8)
        push!(out, (0x80 | ((chr >> 12) & 0x3f)) % UInt8)
        push!(out, (0x80 | ((chr >> 6) & 0x3f)) % UInt8)
        push!(out, (0x80 | (chr & 0x3f)) % UInt8)
    elseif chr < 0x4000000
        push!(out, (0xf8 | ((chr >> 24) & 0x03)) % UInt8)
        push!(out, (0x80 | ((chr >> 18) & 0x3f)) % UInt8)
        push!(out, (0x80 | ((chr >> 12) & 0x3f)) % UInt8)
        push!(out, (0x80 | ((chr >> 6) & 0x3f)) % UInt8)
        push!(out, (0x80 | (chr & 0x3f)) % UInt8)
    elseif (chr % UInt32) < 0x80000000
        push!(out, (0xfc | ((chr >> 30) & 0x01)) % UInt8)
        push!(out, (0x80 | ((chr >> 24) & 0x3f)) % UInt8)
        push!(out, (0x80 | ((chr >> 18) & 0x3f)) % UInt8)
        push!(out, (0x80 | ((chr >> 12) & 0x3f)) % UInt8)
        push!(out, (0x80 | ((chr >> 6) & 0x3f)) % UInt8)
        push!(out, (0x80 | (chr & 0x3f)) % UInt8)
    end
    return nothing
end

# PORT: pl-utf8.h utf8_put_char
"Append the UTF-8 bytes of `chr` to `out` (pl-utf8.h)."
@inline function utf8_put_char(out::Vector{UInt8}, chr::Int)::Nothing
    chr < 0x80 ? (push!(out, chr % UInt8); nothing) : _PL__utf8_put_char(out, chr)
    return nothing
end

# PORT: pl-utf8.h utf8_skip_char
"The index after the character at index `i` of `b` (pl-utf8.h)."
function utf8_skip_char(b::AbstractVector{UInt8}, i::Int)::Int
    (_byte(b, i) & 0x80) == 0 && return i + 1
    i += 1
    while ISUTF8_CB(_byte(b, i))
        i += 1
    end
    return i
end

# PORT: pl-utf8.h utf8_backskip_char
"The index of the character before index `s` of `b`, not before index `start` (pl-utf8.h)."
function utf8_backskip_char(b::AbstractVector{UInt8}, start::Int, s::Int)::Int
    s -= 1
    while s > start && ISUTF8_CB(_byte(b, s))
        s -= 1
    end
    return s
end

# PORT: pl-utf8.h utf8_code_bytes
"How many UTF-8 bytes encode `chr`; -1 if it cannot be encoded (pl-utf8.h)."
function utf8_code_bytes(chr::Int)::Int
    chr < 0x80 && return 1
    chr < 0x800 && return 2
    chr < 0x10000 && return 3
    chr < 0x200000 && return 4
    chr < 0x4000000 && return 5
    chr < 0x80000000 && return 6
    return -1
end

# PORT: pl-utf8.c utf8_strlen
"The number of characters in the `len` bytes of `b` from index `s` (pl-utf8.c)."
function utf8_strlen(b::AbstractVector{UInt8}, s::Int, len::Int)::Int
    e = s + len
    l = 0
    while s < e
        s = utf8_skip_char_e(b, s, e)
        l += 1
    end
    return l
end

# PORT: pl-utf8.h utf8_skip_char_e
"The index after the character at index `i` of `b`, not beyond index `e` (pl-utf8.h)."
function utf8_skip_char_e(b::AbstractVector{UInt8}, i::Int, e::Int)::Int
    (_byte(b, i) & 0x80) == 0 && return i + 1
    i += 1
    while i < e && ISUTF8_CB(_byte(b, i))
        i += 1
    end
    return i
end
