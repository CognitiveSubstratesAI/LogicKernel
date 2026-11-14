# UPSTREAM: swipl-devel src/pl-hash.c @ 18168e629eab
# UPSTREAM: swipl-devel src/pl-hash.h @ 18168e629eab
# CLASS: code
# COPYRIGHT: Author:	Austin Appleby
# COPYRIGHT: License:	Public domain
#
# MurmurHash2 as SWI-Prolog uses it. `join_multi_arg_keys` (src/pl-index.jl) combines the keys of a
# multi-argument index with it, so the combined key is the one SWI computes from the same words.
#
# Upstream has two bodies: a byte-wise one for big-endian machines and an alignment-juggling one for
# little-endian machines. Its own comment: the first "produces the same hash as
# MurmurHashAligned2() on little endian machines". This is the byte-wise body, reading the data in
# little-endian byte order — the hash SWI computes on the machines it runs on.

# PORT: pl-hash.h MURMUR_SEED
"The seed SWI-Prolog passes to `MurmurHashAligned2` (pl-hash.h)."
const MURMUR_SEED = 0x1a3be34a

"Byte `j` (0-based) of the little-endian bytes of `key`'s words."
_le_byte(key::NTuple{N, UInt64}, j::Int) where {N} =
    UInt32((key[(j >> 3) + 1] >> (8 * (j & 7))) & 0xff)
"Byte `j` (0-based) of a byte buffer."
_le_byte(key::AbstractVector{UInt8}, j::Int) = UInt32(key[j + 1])

# PORT: pl-hash.c MurmurHashAligned2
# DIVERGES: hashes the first `len` bytes of a tuple of words or of a byte buffer (the data the
# kernel hashes) rather than a `void*`, so no pointer or alignment is involved.
"""
    MurmurHashAligned2(key, len, seed) -> UInt32

MurmurHash2 of the first `len` bytes of `key` — a tuple of words (little-endian) or a byte
buffer — as pl-hash.c computes it.
"""
function MurmurHashAligned2(key, len::Int, seed::UInt32)::UInt32
    m = 0x5bd1e995
    r = 24
    h = seed ⊻ (len % UInt32)
    j = 0
    while len >= 4
        k = _le_byte(key, j)
        k |= _le_byte(key, j + 1) << 8
        k |= _le_byte(key, j + 2) << 16
        k |= _le_byte(key, j + 3) << 24
        k *= m                                  # MIX(h,k,m)
        k ⊻= k >> r
        k *= m
        h *= m
        h ⊻= k
        j += 4
        len -= 4
    end
    if len == 3                                 # the switch falls through, as upstream's does
        h ⊻= _le_byte(key, j + 2) << 16
    end
    if len >= 2
        h ⊻= _le_byte(key, j + 1) << 8
    end
    if len >= 1
        h ⊻= _le_byte(key, j)
        h *= m
    end
    h ⊻= h >> 13
    h *= m
    h ⊻= h >> 15
    return h
end

# PORT: pl-hash.c MurmurHashWide as _MurmurHashWide_blocks
# synced to swipl-devel cf6960c2 (pl-hash.c:219-265, the `#else` arm): new at the target, not at the pin.
# DIVERGES: `s` is a vector of 32-bit code points (`UInt32`: upstream's `wchar_t` where it is 4 bytes) or of
# UTF-16 units (`UInt16`: its `wchar_t` where that is 2 bytes, Windows) instead of a `const wchar_t*`; `len`
# stays the number of BYTES of `s`, so `len ÷ sizeof(W)` units are read. No pointer or byte order is involved.
"""
    _MurmurHashWide_blocks(s, len, seed) -> UInt32

MurmurHash2 of the code points of the wide text `s` (`len` bytes of `UInt32` code points or `UInt16`
UTF-16 units), each code point one 4-byte little-endian block, so there is no tail: the hash of the text
does not depend on the unit size (pl-hash.c, the portable arm of `MurmurHashWide`).
"""
function _MurmurHashWide_blocks(
    s::AbstractVector{W}, len::Int, seed::UInt32
)::UInt32 where {W <: Union{UInt16, UInt32}}
    m = 0x5bd1e995
    r = 24
    e = len ÷ sizeof(W)                         # e = (const wchar_t *)((const char *)s + len)
    n = 0
    q = 1
    while q <= e                                # for(q=s; q<e; q++): count code points
        if W === UInt16 && 0xd800 <= s[q] < 0xdc00 && q + 1 <= e
            if 0xdc00 <= s[q + 1] < 0xe000
                q += 1                          # a surrogate pair is one code point
            end
        end
        n += 1
        q += 1
    end
    h = seed ⊻ UInt32(n * 4)                    # h = seed ^ (unsigned int)(n*4)
    p = 1
    while p <= e
        k = UInt32(s[p])
        p += 1
        if W === UInt16 && 0xd800 <= k < 0xdc00 && p <= e
            if 0xdc00 <= UInt32(s[p]) < 0xe000
                k = 0x10000 + ((k - 0xd800) << 10) + (UInt32(s[p]) - 0xdc00)
                p += 1
            end
        end
        k *= m                                  # MIX(h,k,m)
        k ⊻= k >> r
        k *= m
        h *= m
        h ⊻= k
    end
    h ⊻= h >> 13
    h *= m
    h ⊻= h >> 15
    return h
end

# PORT: pl-hash.c MurmurHashWide
# synced to swipl-devel cf6960c2 (pl-hash.c:219-265): new at the target, not at the pin.
# DIVERGES: see `_MurmurHashWide_blocks` (the argument is a vector, `len` its size in bytes). The method for
# `UInt32` code points is upstream's `!WORDS_BIGENDIAN && SIZEOF_WCHAR_T == 4` arm: `MurmurHashAligned2` over the
# `len` bytes of the code points in little-endian order (on every host, as the file header says); the method
# for `UInt16` units is the portable arm.
"""
    MurmurHashWide(s, len, seed) -> UInt32

The hash of wide text of `len` bytes as little-endian 32-bit code points (`UInt32`), or of UTF-16 units
(`UInt16`, a surrogate pair is one code point), so it does not depend on the unit size (pl-hash.c).
"""
function MurmurHashWide(s::AbstractVector{UInt32}, len::Int, seed::UInt32)::UInt32
    @assert 0 <= len <= 4 * length(s)
    bytes = Vector{UInt8}(undef, len)
    for j in 0:(len - 1)
        bytes[j + 1] = UInt8((s[(j >> 2) + 1] >> (8 * (j & 3))) & 0xff)
    end
    return MurmurHashAligned2(bytes, len, seed)
end
function MurmurHashWide(s::AbstractVector{UInt16}, len::Int, seed::UInt32)::UInt32
    return _MurmurHashWide_blocks(s, len, seed)
end
