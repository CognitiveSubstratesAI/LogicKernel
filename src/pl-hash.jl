# UPSTREAM: swipl-devel src/pl-hash.c @ bae881a24a3f
# UPSTREAM: swipl-devel src/pl-hash.h @ bae881a24a3f
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

# PORT: pl-hash.c MurmurHashAligned2
# DIVERGES: hashes the first `len` bytes of a tuple of words (the only data the kernel hashes)
# rather than a `void*` buffer, so no pointer or alignment is involved.
"""
    MurmurHashAligned2(key, len, seed) -> UInt32

MurmurHash2 of the first `len` bytes of `key` (little-endian words), as pl-hash.c computes it.
"""
function MurmurHashAligned2(
    key::NTuple{N, UInt64}, len::Int, seed::UInt32
)::UInt32 where {N}
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
