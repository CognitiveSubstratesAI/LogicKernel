# CLASS: code
# COPYRIGHT: Copyright (c) 1998-2013, Brian Gladman, Worcester, UK.  All rights reserved.
# COPYRIGHT: Copyright (c)  2008-2015, University of Amsterdam
# allow-new-artifact: packages/clib C port (Phase 1)
#
# CLIB5 (packages/clib/sha4pl.c, sha1/sha2.c, sha1/hmac.c, sha1/hmac_sha1.c, sha1/hmac_sha256.c; packages-clib ed3593eb of
# swipl-devel af9e2e7e): the foreign half of library(sha): `sha_hash/3`, `sha_new_ctx/2`, `sha_hash_ctx/4` and `hmac_sha/4`.
# Built into sha4pl by packages/clib/CMakeLists.txt (clib_plugin(sha4pl ...)): sha4pl.c, error.c, sha1/sha1.c, sha1/sha2.c,
# sha1/hmac_sha1.c, sha1/hmac_sha256.c (each includes hmac.c). NOT built into it: sha1b.c, sha2b.c, pwd2key.c, shasum.c: not ported.
# The SHA-1 core (`sha1_begin!`, `sha1_hash!`, `sha1_end!`) is src/pl-termhash.jl's (the same Gladman sha1.c, built into the kernel
# for variant_sha1). NO `# UPSTREAM:` header line: `packages/clib` is a gitlink at the pin, not a blob of swipl-devel, so
# tools/port_check.jl cannot follow it yet (the D2 item of evidence/R2/json_port_handoff.md). BLIND-CODED: no Julia process ran when
# this file was written.
#
# DIVERGES (file-wide):
#   1. REGISTERED IN `system` AT BOOT, as the json, md5 and readutil ports: `PL_predicates_from_sha4pl` is appended to
#      `_PRED_TABLES` and `_FOREIGN_VA`; `use_foreign_library(foreign(sha4pl))` finds `sha4pl` in `static_extensions`
#      (src/pl-load.jl) and `install_sha4pl` is the empty function (its atoms are `mk_sym(T, :sha1)` and so on).
#   2. THE CONTEXT STRING (`sha_new_ctx/2`, `sha_hash_ctx/4`). upstream hands out the raw bytes of `struct context` (`sizeof` of a C
#      struct with padding, pointers and a union) as a Prolog string; no Julia value has that memory layout. This port picks a FIXED
#      layout of `SHA_CONTEXT_SIZE` = 228 bytes, every byte one Latin-1 character of the string (little-endian words): magic,
#      algorithm, digest size, encoding, `sha2_len` (five 32-bit words), then the 208-byte union area (SHA-1: two count words, five hash
#      words, the 16 words of the block; SHA-224/256: two count words, eight hash words, the 64-byte block; SHA-384/512: two 64-bit
#      count words, eight 64-bit hash words, the 128-byte block; the rest zero). `sha_hash_ctx/4` validates the string with
#      `valid_context` as upstream does (length, magic, digest size against algorithm, encoding, `sha2_len`) and a modified string that
#      fails is refused with `domain_error(algorithm, Old)` all the same. Observable difference: `string_length/2` of a context
#      (228 here; upstream's is the platform's `sizeof(struct context)`), and the bytes themselves.
#   3. THE SHA-2 BLOCK is a byte vector, not 32/64-bit words: `bsw_32`/`bsw_64` (the byte swap on little-endian hosts) are gone, the
#      compression functions read their sixteen words big-endian off the bytes. The digest is the same function of the same input.
#      The rounds are `sha2.c`'s `v_cycle` (not the `UNROLL_SHA2` form), a loop of sixteen steps per pass.
#   4. TEXT. `PL_get_nchars(from, ..., CVT_ATOM|CVT_STRING|CVT_LIST|CVT_EXCEPTION|encoding)` is ONE `PL_get_text` followed by the
#      recoding to the bytes of the requested representation (as src/pl-md5.jl, 4): UTF-8 (`REP_UTF8`) through `PL_mb_text`, ISO
#      Latin-1 (`REP_ISO_LATIN_1`: `encoding(octet)`, and key and data of hmac_sha/4, which pass no representation flag) by hand: a code
#      above 255 raises `representation_error(encoding)`.
#   5. A DIGEST is returned as a byte vector, not written through an output pointer (`sha2`, `hmac_sha1`, `hmac_sha256`, ...).

# PORT: packages/clib/sha1/sha2.h SHA224_DIGEST_SIZE
"Bytes in a SHA-224 digest (sha2.h)."
const SHA224_DIGEST_SIZE = 28
# PORT: packages/clib/sha1/sha2.h SHA256_DIGEST_SIZE
"Bytes in a SHA-256 digest (sha2.h)."
const SHA256_DIGEST_SIZE = 32
# PORT: packages/clib/sha1/sha2.h SHA384_DIGEST_SIZE
"Bytes in a SHA-384 digest (sha2.h)."
const SHA384_DIGEST_SIZE = 48
# PORT: packages/clib/sha1/sha2.h SHA512_DIGEST_SIZE
"Bytes in a SHA-512 digest (sha2.h)."
const SHA512_DIGEST_SIZE = 64
# PORT: packages/clib/sha1/sha2.h SHA256_BLOCK_SIZE
"Bytes in a SHA-224/256 block (sha2.h)."
const SHA256_BLOCK_SIZE = 64
# PORT: packages/clib/sha1/sha2.h SHA512_BLOCK_SIZE
"Bytes in a SHA-384/512 block (sha2.h)."
const SHA512_BLOCK_SIZE = 128
# PORT: packages/clib/sha1/sha2.c SHA256_MASK
"`SHA256_BLOCK_SIZE - 1` (sha2.c)."
const SHA256_MASK = SHA256_BLOCK_SIZE - 1
# PORT: packages/clib/sha1/sha2.c SHA512_MASK
"`SHA512_BLOCK_SIZE - 1` (sha2.c)."
const SHA512_MASK = SHA512_BLOCK_SIZE - 1
# PORT: packages/clib/sha1/sha2.h SHA2_MAX_DIGEST_SIZE
"The largest SHA-2 digest, SHA-512's (sha2.h)."
const SHA2_MAX_DIGEST_SIZE = SHA512_DIGEST_SIZE

# the table of sha2.c's k256: the 64 round constants of SHA-256 (FIPS 180-4, 4.2.2)
const _SHA256_K = UInt32[
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
    0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
    0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
    0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
]
# the table of sha2.c's k512: the 80 round constants of SHA-512 (FIPS 180-4, 4.2.3)
const _SHA512_K = UInt64[
    0x428a2f98d728ae22, 0x7137449123ef65cd,
    0xb5c0fbcfec4d3b2f, 0xe9b5dba58189dbbc,
    0x3956c25bf348b538, 0x59f111f1b605d019,
    0x923f82a4af194f9b, 0xab1c5ed5da6d8118,
    0xd807aa98a3030242, 0x12835b0145706fbe,
    0x243185be4ee4b28c, 0x550c7dc3d5ffb4e2,
    0x72be5d74f27b896f, 0x80deb1fe3b1696b1,
    0x9bdc06a725c71235, 0xc19bf174cf692694,
    0xe49b69c19ef14ad2, 0xefbe4786384f25e3,
    0x0fc19dc68b8cd5b5, 0x240ca1cc77ac9c65,
    0x2de92c6f592b0275, 0x4a7484aa6ea6e483,
    0x5cb0a9dcbd41fbd4, 0x76f988da831153b5,
    0x983e5152ee66dfab, 0xa831c66d2db43210,
    0xb00327c898fb213f, 0xbf597fc7beef0ee4,
    0xc6e00bf33da88fc2, 0xd5a79147930aa725,
    0x06ca6351e003826f, 0x142929670a0e6e70,
    0x27b70a8546d22ffc, 0x2e1b21385c26c926,
    0x4d2c6dfc5ac42aed, 0x53380d139d95b3df,
    0x650a73548baf63de, 0x766a0abb3c77b2a8,
    0x81c2c92e47edaee6, 0x92722c851482353b,
    0xa2bfe8a14cf10364, 0xa81a664bbc423001,
    0xc24b8b70d0f89791, 0xc76c51a30654be30,
    0xd192e819d6ef5218, 0xd69906245565a910,
    0xf40e35855771202a, 0x106aa07032bbd1b8,
    0x19a4c116b8d2d0c8, 0x1e376c085141ab53,
    0x2748774cdf8eeb99, 0x34b0bcb5e19b48a8,
    0x391c0cb3c5c95a63, 0x4ed8aa4ae3418acb,
    0x5b9cca4f7763e373, 0x682e6ff3d6b2b8a3,
    0x748f82ee5defb2fc, 0x78a5636f43172f60,
    0x84c87814a1f0ab72, 0x8cc702081a6439ec,
    0x90befffa23631e28, 0xa4506cebde82bde9,
    0xbef9a3f7b2c67915, 0xc67178f2e372532b,
    0xca273eceea26619c, 0xd186b8c721c0c207,
    0xeada7dd6cde0eb1e, 0xf57d4f7fee6ed178,
    0x06f067aa72176fba, 0x0a637dc5a2c898a6,
    0x113f9804bef90dae, 0x1b710b35131c471b,
    0x28db77f523047d84, 0x32caab7b40c72493,
    0x3c9ebe0a15c9bebc, 0x431d67c49c100d4c,
    0x4cc5d4becb3e42b6, 0x597f299cfc657e2a,
    0x5fcb6fab3ad6faec, 0x6c44198c4a475817
]
# the initial hash values of sha2.c: i224, i256 (32-bit words), i384, i512 (64-bit words)
const _SHA224_I = UInt32[
    0xc1059ed8, 0x367cd507, 0x3070dd17, 0xf70e5939,
    0xffc00b31, 0x68581511, 0x64f98fa7, 0xbefa4fa4
]
const _SHA256_I = UInt32[
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
]
const _SHA384_I = UInt64[
    0xcbbb9d5dc1059ed8, 0x629a292a367cd507,
    0x9159015a3070dd17, 0x152fecd8f70e5939,
    0x67332667ffc00b31, 0x8eb44a8768581511,
    0xdb0c2e0d64f98fa7, 0x47b5481dbefa4fa4
]
const _SHA512_I = UInt64[
    0x6a09e667f3bcc908, 0xbb67ae8584caa73b,
    0x3c6ef372fe94f82b, 0xa54ff53a5f1d36f1,
    0x510e527fade682d1, 0x9b05688c2b3e6c1f,
    0x1f83d9abfb41bd6b, 0x5be0cd19137e2179
]

# PORT: packages/clib/sha1/sha2.c rotr64
"Rotate a 64-bit word right (sha2.c `rotr64`)."
rotr64(x::UInt64, n::Int)::UInt64 = (x >> n) | (x << (64 - n))

# PORT: packages/clib/sha1/sha2.c ch
"The choice function of SHA-2 (sha2.c `ch`, in Rich Schroeppel's and Colin Plumb's form)."
sha2_ch(x::T, y::T, z::T) where {T <: Unsigned} = z ⊻ (x & (y ⊻ z))
# PORT: packages/clib/sha1/sha2.c maj
"The majority function of SHA-2 (sha2.c `maj`, in Rich Schroeppel's and Colin Plumb's form)."
sha2_maj(x::T, y::T, z::T) where {T <: Unsigned} = (x & y) | (z & (x ⊻ y))

# PORT: packages/clib/sha1/sha2.c s_0 s_1 g_0 g_1 (the 32-bit forms, SHA-256)
"`s_0` of SHA-256 (sha2.c)."
sha256_s0(x::UInt32)::UInt32 = rotr32(x, 2) ⊻ rotr32(x, 13) ⊻ rotr32(x, 22)
"`s_1` of SHA-256 (sha2.c)."
sha256_s1(x::UInt32)::UInt32 = rotr32(x, 6) ⊻ rotr32(x, 11) ⊻ rotr32(x, 25)
"`g_0` of SHA-256 (sha2.c)."
sha256_g0(x::UInt32)::UInt32 = rotr32(x, 7) ⊻ rotr32(x, 18) ⊻ (x >> 3)
"`g_1` of SHA-256 (sha2.c)."
sha256_g1(x::UInt32)::UInt32 = rotr32(x, 17) ⊻ rotr32(x, 19) ⊻ (x >> 10)
# PORT: packages/clib/sha1/sha2.c s_0 s_1 g_0 g_1 (the 64-bit forms, SHA-384/512)
"`s_0` of SHA-512 (sha2.c)."
sha512_s0(x::UInt64)::UInt64 = rotr64(x, 28) ⊻ rotr64(x, 34) ⊻ rotr64(x, 39)
"`s_1` of SHA-512 (sha2.c)."
sha512_s1(x::UInt64)::UInt64 = rotr64(x, 14) ⊻ rotr64(x, 18) ⊻ rotr64(x, 41)
"`g_0` of SHA-512 (sha2.c)."
sha512_g0(x::UInt64)::UInt64 = rotr64(x, 1) ⊻ rotr64(x, 8) ⊻ (x >> 7)
"`g_1` of SHA-512 (sha2.c)."
sha512_g1(x::UInt64)::UInt64 = rotr64(x, 19) ⊻ rotr64(x, 61) ⊻ (x >> 6)

# PORT: packages/clib/sha1/sha2.h sha256_ctx
# DIVERGES: see the file header, 3 (the block is bytes); C arrays are Vectors, 1-based: `count[0]` is `count[1]`.
"The SHA-224/256 context (sha2.h `sha256_ctx`): the byte count (low word first), the eight hash words, the block being filled."
struct sha256_ctx
    count::Vector{UInt32}
    hash::Vector{UInt32}
    wbuf::Vector{UInt8}
end
sha256_ctx() =
    sha256_ctx(zeros(UInt32, 2), zeros(UInt32, 8), zeros(UInt8, SHA256_BLOCK_SIZE))

# PORT: packages/clib/sha1/sha2.h sha512_ctx
# DIVERGES: see the file header, 3.
"The SHA-384/512 context (sha2.h `sha512_ctx`): the byte count (low word first), the eight hash words, the block being filled."
struct sha512_ctx
    count::Vector{UInt64}
    hash::Vector{UInt64}
    wbuf::Vector{UInt8}
end
sha512_ctx() =
    sha512_ctx(zeros(UInt64, 2), zeros(UInt64, 8), zeros(UInt8, SHA512_BLOCK_SIZE))

# PORT: packages/clib/sha1/sha2.h sha2_ctx
# DIVERGES: the union of the two contexts is two fields (both live; only the one `sha2_len` names is used).
"The context of the dynamic-length SHA-2 interface (sha2.h `sha2_ctx`): `sha2_len` is the digest size, 28, 32, 48 or 64."
mutable struct sha2_ctx
    sha2_len::UInt32
    ctx256::sha256_ctx
    ctx512::sha512_ctx
end
sha2_ctx() = sha2_ctx(UInt32(0), sha256_ctx(), sha512_ctx())

"The big-endian 32-bit word at the 0-based offset `off` of `b`."
_sha_get_be32(b::Vector{UInt8}, off::Int)::UInt32 =
    (UInt32(b[off + 1]) << 24) | (UInt32(b[off + 2]) << 16) | (UInt32(b[off + 3]) << 8) |
    UInt32(b[off + 4])

"The big-endian 64-bit word at the 0-based offset `off` of `b`."
function _sha_get_be64(b::Vector{UInt8}, off::Int)::UInt64
    w = UInt64(0)
    for k in 1:8
        w = (w << 8) | UInt64(b[off + k])
    end
    return w
end

"Store the 32-bit word `w` big-endian at the 0-based offset `off` of `b`."
function _sha_put_be32!(b::Vector{UInt8}, off::Int, w::UInt32)::Nothing
    for k in 0:3
        b[off + k + 1] = (w >> (8 * (3 - k))) % UInt8
    end
    return nothing
end

"Store the 64-bit word `w` big-endian at the 0-based offset `off` of `b`."
function _sha_put_be64!(b::Vector{UInt8}, off::Int, w::UInt64)::Nothing
    for k in 0:7
        b[off + k + 1] = (w >> (8 * (7 - k))) % UInt8
    end
    return nothing
end

# PORT: packages/clib/sha1/sha2.c hf (the message schedule of v_cycle)
"The next schedule word `i` (0..15 within a pass) of the SHA-256 block `p`, stored back into `p` (sha2.c `hf`)."
function _sha256_hf!(p::Vector{UInt32}, i::Int)::UInt32
    p[(i & 15) + 1] +=
        sha256_g1(p[((i + 14) & 15) + 1]) + p[((i + 9) & 15) + 1] +
        sha256_g0(p[((i + 1) & 15) + 1])
    return p[(i & 15) + 1]
end

"As `_sha256_hf!` for the 64-bit words of SHA-512."
function _sha512_hf!(p::Vector{UInt64}, i::Int)::UInt64
    p[(i & 15) + 1] +=
        sha512_g1(p[((i + 14) & 15) + 1]) + p[((i + 9) & 15) + 1] +
        sha512_g0(p[((i + 1) & 15) + 1])
    return p[(i & 15) + 1]
end

# PORT: packages/clib/sha1/sha2.c sha256_compile
# DIVERGES: see the file header, 3.
"Compile the 64 bytes of the block `ctx.wbuf` into the SHA-256 hash value (sha2.c `sha256_compile`)."
function sha256_compile!(ctx::sha256_ctx)::Nothing
    p = Vector{UInt32}(undef, 16)
    for i in 0:15
        p[i + 1] = _sha_get_be32(ctx.wbuf, 4 * i)
    end
    v = copy(ctx.hash)
    for j in 0:16:48
        for i in 0:15
            # vf(n, i) = v[(n - i) & 7]
            a = ((0 - i) & 7) + 1
            b = ((1 - i) & 7) + 1
            c = ((2 - i) & 7) + 1
            d = ((3 - i) & 7) + 1
            e = ((4 - i) & 7) + 1
            f = ((5 - i) & 7) + 1
            g = ((6 - i) & 7) + 1
            h = ((7 - i) & 7) + 1
            w = j != 0 ? _sha256_hf!(p, i) : p[i + 1]
            v[h] += w + _SHA256_K[i + j + 1] + sha256_s1(v[e]) + sha2_ch(v[e], v[f], v[g])
            v[d] += v[h]
            v[h] += sha256_s0(v[a]) + sha2_maj(v[a], v[b], v[c])
        end
    end
    for k in 1:8
        ctx.hash[k] += v[k]
    end
    return nothing
end

# PORT: packages/clib/sha1/sha2.c sha512_compile
# DIVERGES: see the file header, 3.
"Compile the 128 bytes of the block `ctx.wbuf` into the SHA-512 hash value (sha2.c `sha512_compile`)."
function sha512_compile!(ctx::sha512_ctx)::Nothing
    p = Vector{UInt64}(undef, 16)
    for i in 0:15
        p[i + 1] = _sha_get_be64(ctx.wbuf, 8 * i)
    end
    v = copy(ctx.hash)
    for j in 0:16:64
        for i in 0:15
            a = ((0 - i) & 7) + 1
            b = ((1 - i) & 7) + 1
            c = ((2 - i) & 7) + 1
            d = ((3 - i) & 7) + 1
            e = ((4 - i) & 7) + 1
            f = ((5 - i) & 7) + 1
            g = ((6 - i) & 7) + 1
            h = ((7 - i) & 7) + 1
            w = j != 0 ? _sha512_hf!(p, i) : p[i + 1]
            v[h] += w + _SHA512_K[i + j + 1] + sha512_s1(v[e]) + sha2_ch(v[e], v[f], v[g])
            v[d] += v[h]
            v[h] += sha512_s0(v[a]) + sha2_maj(v[a], v[b], v[c])
        end
    end
    for k in 1:8
        ctx.hash[k] += v[k]
    end
    return nothing
end

# PORT: packages/clib/sha1/sha2.c sha256_hash
# DIVERGES: `len` is checked against `data`; see the file header, 3.
"Add the first `len` bytes of `data` to the SHA-224/256 digest (sha2.c `sha256_hash`, also `sha224_hash`)."
function sha256_hash!(data::Vector{UInt8}, len::Int, ctx::sha256_ctx)::Nothing
    0 <= len <= length(data) || throw(BoundsError(data, len))
    pos = Int(ctx.count[1] & UInt32(SHA256_MASK))
    space = SHA256_BLOCK_SIZE - pos
    sp = 0

    ctx.count[1] += (len % UInt32)
    if ctx.count[1] < len
        ctx.count[2] += 1
    end

    while len >= space                      # transfer whole blocks while possible
        copyto!(ctx.wbuf, pos + 1, data, sp + 1, space)
        sp += space
        len -= space
        space = SHA256_BLOCK_SIZE
        pos = 0
        sha256_compile!(ctx)
    end

    len > 0 && copyto!(ctx.wbuf, pos + 1, data, sp + 1, len)
    return nothing
end

# PORT: packages/clib/sha1/sha2.c sha_end1
# DIVERGES: see the file header, 3 and 5: the block is bytes, the padding byte and the zeros are written directly, the digest is returned.
"Pad, finish, and return the first `hlen` bytes of the SHA-224/256 digest (sha2.c `sha_end1`)."
function sha_end1!(ctx::sha256_ctx, hlen::Int)::Vector{UInt8}
    i = Int(ctx.count[1] & UInt32(SHA256_MASK))

    # the padding is a single 1 bit and as many zero bits as necessary; the buffer always has an empty slot for the first byte
    ctx.wbuf[i + 1] = 0x80

    # 9 or more empty positions are needed: one for the padding byte, eight for the length; if there are not enough, pad and
    # empty the buffer
    if i > SHA256_BLOCK_SIZE - 9
        for k in (i + 2):SHA256_BLOCK_SIZE
            ctx.wbuf[k] = 0
        end
        sha256_compile!(ctx)
        for k in 1:(SHA256_BLOCK_SIZE - 8)
            ctx.wbuf[k] = 0
        end
    else
        for k in (i + 2):(SHA256_BLOCK_SIZE - 8)
            ctx.wbuf[k] = 0
        end
    end

    # the length in bits, as two big-endian 32-bit words
    _sha_put_be32!(ctx.wbuf, 56, (ctx.count[2] << 3) | (ctx.count[1] >> 29))
    _sha_put_be32!(ctx.wbuf, 60, ctx.count[1] << 3)
    sha256_compile!(ctx)

    # extract the hash value as bytes
    hval = Vector{UInt8}(undef, hlen)
    for k in 0:(hlen - 1)
        hval[k + 1] = (ctx.hash[(k >> 2) + 1] >> (8 * (~k & 3))) % UInt8
    end
    return hval
end

# PORT: packages/clib/sha1/sha2.c sha512_hash
# DIVERGES: `len` is checked against `data`; see the file header, 3.
"Add the first `len` bytes of `data` to the SHA-384/512 digest (sha2.c `sha512_hash`, also `sha384_hash`)."
function sha512_hash!(data::Vector{UInt8}, len::Int, ctx::sha512_ctx)::Nothing
    0 <= len <= length(data) || throw(BoundsError(data, len))
    pos = Int(ctx.count[1] & UInt64(SHA512_MASK))
    space = SHA512_BLOCK_SIZE - pos
    sp = 0

    ctx.count[1] += UInt64(len)
    if ctx.count[1] < len
        ctx.count[2] += 1
    end

    while len >= space                      # transfer whole blocks while possible
        copyto!(ctx.wbuf, pos + 1, data, sp + 1, space)
        sp += space
        len -= space
        space = SHA512_BLOCK_SIZE
        pos = 0
        sha512_compile!(ctx)
    end

    len > 0 && copyto!(ctx.wbuf, pos + 1, data, sp + 1, len)
    return nothing
end

# PORT: packages/clib/sha1/sha2.c sha_end2
# DIVERGES: see the file header, 3 and 5.
"Pad, finish, and return the first `hlen` bytes of the SHA-384/512 digest (sha2.c `sha_end2`)."
function sha_end2!(ctx::sha512_ctx, hlen::Int)::Vector{UInt8}
    i = Int(ctx.count[1] & UInt64(SHA512_MASK))

    ctx.wbuf[i + 1] = 0x80

    # 17 or more empty byte positions are needed: one for the padding byte, sixteen for the length count
    if i > SHA512_BLOCK_SIZE - 17
        for k in (i + 2):SHA512_BLOCK_SIZE
            ctx.wbuf[k] = 0
        end
        sha512_compile!(ctx)
        for k in 1:(SHA512_BLOCK_SIZE - 16)
            ctx.wbuf[k] = 0
        end
    else
        for k in (i + 2):(SHA512_BLOCK_SIZE - 16)
            ctx.wbuf[k] = 0
        end
    end

    # the length in bits, as two big-endian 64-bit words
    _sha_put_be64!(ctx.wbuf, 112, (ctx.count[2] << 3) | (ctx.count[1] >> 61))
    _sha_put_be64!(ctx.wbuf, 120, ctx.count[1] << 3)
    sha512_compile!(ctx)

    hval = Vector{UInt8}(undef, hlen)
    for k in 0:(hlen - 1)
        hval[k + 1] = (ctx.hash[(k >> 3) + 1] >> (8 * (~k & 7))) % UInt8
    end
    return hval
end

# PORT: packages/clib/sha1/sha2.c sha224_begin
"Start a SHA-224 digest (sha2.c)."
function sha224_begin!(ctx::sha256_ctx)::Nothing
    ctx.count[1] = ctx.count[2] = 0
    copyto!(ctx.hash, _SHA224_I)
    return nothing
end

# PORT: packages/clib/sha1/sha2.c sha256_begin
"Start a SHA-256 digest (sha2.c)."
function sha256_begin!(ctx::sha256_ctx)::Nothing
    ctx.count[1] = ctx.count[2] = 0
    copyto!(ctx.hash, _SHA256_I)
    return nothing
end

# PORT: packages/clib/sha1/sha2.c sha384_begin
"Start a SHA-384 digest (sha2.c)."
function sha384_begin!(ctx::sha512_ctx)::Nothing
    ctx.count[1] = ctx.count[2] = 0
    copyto!(ctx.hash, _SHA384_I)
    return nothing
end

# PORT: packages/clib/sha1/sha2.c sha512_begin
"Start a SHA-512 digest (sha2.c)."
function sha512_begin!(ctx::sha512_ctx)::Nothing
    ctx.count[1] = ctx.count[2] = 0
    copyto!(ctx.hash, _SHA512_I)
    return nothing
end

# PORT: packages/clib/sha1/sha2.c sha2_begin
# DIVERGES: returns the new context, or `nothing` where upstream returns `EXIT_FAILURE` (an unknown digest size).
"""
A SHA-2 context for the digest size `len` (224 or 28, 256 or 32, 384 or 48, 512 or 64 bytes), or `nothing` for any other size (sha2.c `sha2_begin`).
"""
function sha2_begin(len::Int)::Union{Nothing, sha2_ctx}
    ctx = sha2_ctx()
    if len == 224 || len == 28
        sha224_begin!(ctx.ctx256)
        ctx.sha2_len = 28
    elseif len == 256 || len == 32
        sha256_begin!(ctx.ctx256)
        ctx.sha2_len = 32
    elseif len == 384 || len == 48
        sha384_begin!(ctx.ctx512)
        ctx.sha2_len = 48
    elseif len == 512 || len == 64
        sha512_begin!(ctx.ctx512)
        ctx.sha2_len = 64
    else
        return nothing
    end
    return ctx
end

# PORT: packages/clib/sha1/sha2.c sha2_hash
"Add the first `len` bytes of `data` to the digest of `ctx`, by its `sha2_len` (sha2.c)."
function sha2_hash!(data::Vector{UInt8}, len::Int, ctx::sha2_ctx)::Nothing
    if ctx.sha2_len == 28 || ctx.sha2_len == 32
        sha256_hash!(data, len, ctx.ctx256)
    elseif ctx.sha2_len == 48 || ctx.sha2_len == 64
        sha512_hash!(data, len, ctx.ctx512)
    end
    return nothing
end

# PORT: packages/clib/sha1/sha2.c sha2_end
# DIVERGES: see the file header, 5.
"Finish the digest of `ctx` and return it, `sha2_len` bytes (sha2.c)."
function sha2_end!(ctx::sha2_ctx)::Vector{UInt8}
    if ctx.sha2_len == 28
        return sha_end1!(ctx.ctx256, SHA224_DIGEST_SIZE)
    elseif ctx.sha2_len == 32
        return sha_end1!(ctx.ctx256, SHA256_DIGEST_SIZE)
    elseif ctx.sha2_len == 48
        return sha_end2!(ctx.ctx512, SHA384_DIGEST_SIZE)
    elseif ctx.sha2_len == 64
        return sha_end2!(ctx.ctx512, SHA512_DIGEST_SIZE)
    end
    return UInt8[]
end

# PORT: packages/clib/sha1/sha2.c sha2
# DIVERGES: see the file header, 5: returns the digest, or `nothing` for an unknown `size`.
"The SHA-2 digest of the first `len` bytes of `data`, of the size `size` (sha2.c `sha2`)."
function sha2_digest(
    size::Int, data::Vector{UInt8}, len::Int
)::Union{Nothing, Vector{UInt8}}
    cx = sha2_begin(size)
    cx === nothing && return nothing
    sha2_hash!(data, len, cx)
    return sha2_end!(cx)
end

# PORT: packages/clib/sha1/sha1.c sha1
# DIVERGES: see the file header, 5: the core is src/pl-termhash.jl's.
"The SHA-1 digest of the first `len` bytes of `data`, 20 bytes (sha1.c `sha1`)."
function sha1_digest(data::Vector{UInt8}, len::Int)::Vector{UInt8}
    cx = sha1_ctx()
    sha1_begin!(cx)
    sha1_hash!(data, len, cx)
    hval = Vector{UInt8}(undef, SHA1_DIGEST_SIZE)
    sha1_end!(hval, cx)
    return hval
end

# ── HMAC (sha1/hmac.c, built twice: hmac_sha1.c with USE_SHA1, hmac_sha256.c with USE_SHA256) ──────────────────────────────
# PORT: packages/clib/sha1/hmac.h HMAC_OK
"The HMAC status of a success (hmac.h)."
const HMAC_OK = 0
# PORT: packages/clib/sha1/hmac.h HMAC_BAD_MODE
"The HMAC status of a key given after data (hmac.h)."
const HMAC_BAD_MODE = -1
# PORT: packages/clib/sha1/hmac.h HMAC_IN_DATA
"`klen` once the key phase is over (hmac.h)."
const HMAC_IN_DATA = Int(0xffffffff)
# PORT: packages/clib/sha1/hmac.h HASH_INPUT_SIZE
"The block size, 64 bytes, of SHA-1 and of SHA-256 (hmac.h `HASH_INPUT_SIZE`)."
const HMAC_HASH_INPUT_SIZE = 64

# PORT: packages/clib/sha1/hmac.h hmac_ctx
# DIVERGES: one type for both builds of hmac.c: `use_sha256` selects the hash (USE_SHA256) and both contexts are held.
"The HMAC context (hmac.h `hmac_ctx`): the key block, the hash context, the key length (`HMAC_IN_DATA` in the data phase)."
mutable struct hmac_ctx
    use_sha256::Bool
    key::Vector{UInt8}
    sha1::sha1_ctx
    sha256::sha256_ctx
    klen::Int
end

"The digest size of the hash of `cx` (hmac.h `HASH_OUTPUT_SIZE`)."
_hmac_output_size(cx::hmac_ctx)::Int = cx.use_sha256 ? SHA256_DIGEST_SIZE : SHA1_DIGEST_SIZE

# PORT: packages/clib/sha1/hmac.h sha_begin
"`sha_begin(cx->ctx)` of the hash of `cx`."
function _hmac_sha_begin!(cx::hmac_ctx)::Nothing
    cx.use_sha256 ? sha256_begin!(cx.sha256) : sha1_begin!(cx.sha1)
    return nothing
end

# PORT: packages/clib/sha1/hmac.h sha_hash
"`sha_hash(data, len, cx->ctx)` of the hash of `cx`."
function _hmac_sha_hash!(cx::hmac_ctx, data::Vector{UInt8}, len::Int)::Nothing
    cx.use_sha256 ? sha256_hash!(data, len, cx.sha256) : sha1_hash!(data, len, cx.sha1)
    return nothing
end

# PORT: packages/clib/sha1/hmac.h sha_end
"`sha_end(dig, cx->ctx)` of the hash of `cx`: the digest."
function _hmac_sha_end!(cx::hmac_ctx)::Vector{UInt8}
    if cx.use_sha256
        return sha_end1!(cx.sha256, SHA256_DIGEST_SIZE)
    end
    hval = Vector{UInt8}(undef, SHA1_DIGEST_SIZE)
    sha1_end!(hval, cx.sha1)
    return hval
end

# PORT: packages/clib/sha1/hmac.c hmac_sha_begin
"Initialise the HMAC context to zero, for SHA-256 when `use_sha256` (hmac.c)."
function hmac_sha_begin(use_sha256::Bool)::hmac_ctx
    return hmac_ctx(
        use_sha256, zeros(UInt8, HMAC_HASH_INPUT_SIZE), sha1_ctx(), sha256_ctx(), 0
    )
end

# PORT: packages/clib/sha1/hmac.c hmac_sha_key
"Input the HMAC key (can be called more than once); `HMAC_BAD_MODE` after data was input (hmac.c)."
function hmac_sha_key!(key::Vector{UInt8}, key_len::Int, cx::hmac_ctx)::Int
    if cx.klen == HMAC_IN_DATA                  # error if further key input is attempted in data mode
        return HMAC_BAD_MODE
    end
    if cx.klen + key_len > HMAC_HASH_INPUT_SIZE # if the key has to be hashed
        if cx.klen <= HMAC_HASH_INPUT_SIZE      # if the hash has not yet been started, initialise it and hash stored key characters
            _hmac_sha_begin!(cx)
            _hmac_sha_hash!(cx, cx.key, cx.klen)
        end
        _hmac_sha_hash!(cx, key, key_len)       # hash long key data into hash
    else                                        # otherwise store key data
        key_len > 0 && copyto!(cx.key, cx.klen + 1, key, 1, key_len)
    end
    cx.klen += key_len                          # update the key length count
    return HMAC_OK
end

# PORT: packages/clib/sha1/hmac.c hmac_sha_data
"Input the HMAC data (can be called more than once); this call ends the key phase (hmac.c)."
function hmac_sha_data!(data::Vector{UInt8}, data_len::Int, cx::hmac_ctx)::Nothing
    if cx.klen != HMAC_IN_DATA                  # if not yet in data phase
        if cx.klen > HMAC_HASH_INPUT_SIZE       # if key is being hashed, complete the hash and store the result as the key
            dig = _hmac_sha_end!(cx)
            copyto!(cx.key, 1, dig, 1, length(dig))
            cx.klen = _hmac_output_size(cx)
        end

        # pad the key if necessary
        for k in (cx.klen + 1):HMAC_HASH_INPUT_SIZE
            cx.key[k] = 0
        end

        # xor ipad into key value
        for k in 1:HMAC_HASH_INPUT_SIZE
            cx.key[k] ⊻= 0x36
        end

        # and start hash operation
        _hmac_sha_begin!(cx)
        _hmac_sha_hash!(cx, cx.key, HMAC_HASH_INPUT_SIZE)

        # mark as now in data mode
        cx.klen = HMAC_IN_DATA
    end

    # hash the data (if any)
    if data_len != 0
        _hmac_sha_hash!(cx, data, data_len)
    end
    return nothing
end

# PORT: packages/clib/sha1/hmac.c hmac_sha_end
# DIVERGES: see the file header, 5: returns the first `mac_len` bytes of the MAC.
"Compute and return the first `mac_len` bytes of the MAC value (hmac.c)."
function hmac_sha_end!(mac_len::Int, cx::hmac_ctx)::Vector{UInt8}
    # if no data has been entered perform a null data phase
    if cx.klen != HMAC_IN_DATA
        hmac_sha_data!(UInt8[], 0, cx)
    end

    dig = _hmac_sha_end!(cx)                    # complete the inner hash

    # set outer key value using opad and removing ipad
    for k in 1:HMAC_HASH_INPUT_SIZE
        cx.key[k] ⊻= 0x36 ⊻ 0x5c
    end

    # perform the outer hash operation
    _hmac_sha_begin!(cx)
    _hmac_sha_hash!(cx, cx.key, HMAC_HASH_INPUT_SIZE)
    _hmac_sha_hash!(cx, dig, _hmac_output_size(cx))
    dig = _hmac_sha_end!(cx)

    # output the hash value
    mac = Vector{UInt8}(undef, mac_len)
    for k in 1:mac_len
        mac[k] = dig[k]
    end
    return mac
end

# PORT: packages/clib/sha1/hmac.c hmac_sha
# DIVERGES: see the file header, 5.
"The HMAC of `data` under `key`, the first `mac_len` bytes; SHA-256 when `use_sha256` else SHA-1 (hmac.c `hmac_sha`)."
function hmac_sha_all(
    use_sha256::Bool, key::Vector{UInt8}, key_len::Int, data::Vector{UInt8}, data_len::Int,
    mac_len::Int
)::Vector{UInt8}
    cx = hmac_sha_begin(use_sha256)
    hmac_sha_key!(key, key_len, cx)
    hmac_sha_data!(data, data_len, cx)
    return hmac_sha_end!(mac_len, cx)
end

# PORT: packages/clib/sha1/hmac_sha1.c hmac_sha1
"The HMAC-SHA-1 of `data` under `key`, the first `mac_len` bytes (hmac_sha1.c)."
hmac_sha1(
    key::Vector{UInt8}, key_len::Int, data::Vector{UInt8}, data_len::Int, mac_len::Int
)::Vector{UInt8} =
    hmac_sha_all(false, key, key_len, data, data_len, mac_len)

# PORT: packages/clib/sha1/hmac_sha256.c hmac_sha256
"The HMAC-SHA-256 of `data` under `key`, the first `mac_len` bytes (hmac_sha256.c)."
hmac_sha256(
    key::Vector{UInt8}, key_len::Int, data::Vector{UInt8}, data_len::Int, mac_len::Int
)::Vector{UInt8} =
    hmac_sha_all(true, key, key_len, data, data_len, mac_len)

# ── sha4pl.c ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────

# PORT: packages/clib/sha4pl.c sha_algorithm
# (an enum upstream; plain integers here)
"`ALGORITHM_SHA1` of sha4pl.c's `sha_algorithm`."
const ALGORITHM_SHA1 = 0
"`ALGORITHM_SHA224` of sha4pl.c's `sha_algorithm`."
const ALGORITHM_SHA224 = 1
"`ALGORITHM_SHA256` of sha4pl.c's `sha_algorithm`."
const ALGORITHM_SHA256 = 2
"`ALGORITHM_SHA384` of sha4pl.c's `sha_algorithm`."
const ALGORITHM_SHA384 = 3
"`ALGORITHM_SHA512` of sha4pl.c's `sha_algorithm`."
const ALGORITHM_SHA512 = 4

# PORT: packages/clib/sha4pl.c optval
"The options of the sha predicates (sha4pl.c `optval`): the algorithm, its digest size, the algorithm term (0: none), the text representation."
struct sha_optval
    algorithm::Int
    digest_size::Int
    algorithm_term::Int
    encoding::UInt32
end

# PORT: packages/clib/sha4pl.c CONTEXT_MAGIC
"The magic word of a context (sha4pl.c `CONTEXT_MAGIC`, `~ 0x53484163L` as a 32-bit word)."
const SHA_CONTEXT_MAGIC = ~UInt32(0x53484163)

# PORT: packages/clib/sha4pl.c context
# DIVERGES: see the file header, 2.
"The context of sha_new_ctx/2 (sha4pl.c `struct context`): the magic, the options, the SHA-1 and the SHA-2 state."
mutable struct sha_context
    magic::UInt32
    opts::sha_optval
    sha1::sha1_ctx
    sha2::sha2_ctx
end

# DIVERGES: see the file header, 2: the size of the context string, five header words and the 208-byte union area.
"The length of a context string (the file header, 2)."
const SHA_CONTEXT_SIZE = 228
"The offset of the union area in a context string."
const SHA_CONTEXT_UNION = 20

# the option specification of sha4pl.c (PL_OPTION("algorithm", OPT_TERM), PL_OPTION("encoding", OPT_TERM))
const sha_option_specs = (
    PL_option_t(:algorithm, OPT_TERM), PL_option_t(:encoding, OPT_TERM)
)

"Is the atom `a` the atom `name`?"
_sha_is_atom(a::T, ::Type{T}, name::Symbol) where {T} =
    sym_key(a) == sym_key(mk_sym(T, name))

# PORT: packages/clib/sha4pl.c sha_options
# DIVERGES: returns the options, or `nothing` with the error raised (upstream returns false); `PL_scan_options` returns the values.
"""
The options `options` of the sha predicates, as a `sha_optval`: `algorithm(sha1|sha224|sha256|sha384|sha512)` (default sha1) and
`encoding(utf8|octet)` (default utf8); `nothing` after raising the error of a bad option (sha4pl.c).
"""
function sha_options(
    ld::PL_local_data{T}, options::term_t
)::Union{Nothing, sha_optval} where {T}
    vals = PL_scan_options(ld, options, 0, "sha_option", sha_option_specs)
    vals === nothing && return nothing
    algorithm_t = vals[1]
    encoding_t = vals[2]
    alg = ALGORITHM_SHA1                        # defaults
    dsize = SHA1_DIGEST_SIZE
    enc = REP_UTF8
    aterm = 0

    if algorithm_t !== nothing
        aterm = algorithm_t
        a = PL_get_atom_ex(ld, algorithm_t)
        a === nothing && return nothing
        if _sha_is_atom(a, T, :sha1)
            alg = ALGORITHM_SHA1
            dsize = SHA1_DIGEST_SIZE
        elseif _sha_is_atom(a, T, :sha224)
            alg = ALGORITHM_SHA224
            dsize = SHA224_DIGEST_SIZE
        elseif _sha_is_atom(a, T, :sha256)
            alg = ALGORITHM_SHA256
            dsize = SHA256_DIGEST_SIZE
        elseif _sha_is_atom(a, T, :sha384)
            alg = ALGORITHM_SHA384
            dsize = SHA384_DIGEST_SIZE
        elseif _sha_is_atom(a, T, :sha512)
            alg = ALGORITHM_SHA512
            dsize = SHA512_DIGEST_SIZE
        else
            PL_domain_error(ld, "algorithm", algorithm_t)
            return nothing
        end
    end

    if encoding_t !== nothing
        a = PL_get_atom_ex(ld, encoding_t)
        a === nothing && return nothing
        if _sha_is_atom(a, T, :utf8)
            enc = REP_UTF8
        elseif _sha_is_atom(a, T, :octet)
            enc = REP_ISO_LATIN_1
        else
            PL_domain_error(ld, "encoding", encoding_t)
            return nothing
        end
    end

    return sha_optval(alg, dsize, aterm, enc)
end

# PORT: packages/clib/sha4pl.c PL_get_nchars (as the callers use it)
# DIVERGES: see the file header, 4.
"""
The bytes of the text in `t` (an atom, a string, a code or character list) in the representation `enc` (`REP_UTF8` or
`REP_ISO_LATIN_1`), or `nothing` with the error raised.
"""
function _sha_text_bytes(
    ld::PL_local_data{T}, t::term_t, enc::UInt32
)::Union{Nothing, Vector{UInt8}} where {T}
    txt = PL_get_text(ld, t, CVT_ATOM | CVT_STRING | CVT_LIST | CVT_EXCEPTION)
    txt === nothing && return nothing
    PL_canonicalise_text_ex(ld, txt) || return nothing
    if enc == REP_UTF8
        PL_mb_text(txt, REP_UTF8) || return nothing
        return Vector{UInt8}(txt.text)
    end
    cps = _text_code_points(txt)                # REP_ISO_LATIN_1
    if any(c -> c > 255, cps)
        PL_error(ld, ERR_REPRESENTATION, mk_sym(T, :encoding))
        return nothing
    end
    return UInt8[c % UInt8 for c in cps]
end

# PORT: packages/clib/sha4pl.c sha_hash as pl_sha_hash
# DIVERGES: see the file header, 4 and 5.
"`sha_hash(+Data, -Hash, +Options)`: Hash is the list of the codes (bytes) of the digest of the text Data (sha4pl.c `pl_sha_hash`)."
function pl_sha_hash3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2, A3 = PL__t0, PL__t0 + 1, PL__t0 + 2
    opts = sha_options(ld, A3)
    opts === nothing && return FFALSE

    data = _sha_text_bytes(ld, A1, opts.encoding)
    data === nothing && return FFALSE

    hval = if opts.algorithm == ALGORITHM_SHA1
        sha1_digest(data, length(data))
    else
        sha2_digest(opts.digest_size, data, length(data))
    end
    hval === nothing && return FFALSE
    return PL_unify_chars(ld, A2, PL_CODE_LIST, opts.digest_size, hval) ? FTRUE : FFALSE     # PL_unify_list_ncodes
end

# PORT: packages/clib/sha4pl.c digest_size
"The digest size of the algorithm `algorithm`, 0 for a value that is none (sha4pl.c `digest_size`)."
function sha_digest_size(algorithm::Int)::Int
    algorithm == ALGORITHM_SHA1 && return SHA1_DIGEST_SIZE
    algorithm == ALGORITHM_SHA224 && return SHA224_DIGEST_SIZE
    algorithm == ALGORITHM_SHA256 && return SHA256_DIGEST_SIZE
    algorithm == ALGORITHM_SHA384 && return SHA384_DIGEST_SIZE
    algorithm == ALGORITHM_SHA512 && return SHA512_DIGEST_SIZE
    return 0
end

"Store the little-endian 32-bit word `w` at the 0-based offset `off` of `b`."
function _sha_put_le32!(b::Vector{UInt8}, off::Int, w::UInt32)::Nothing
    for k in 0:3
        b[off + k + 1] = (w >> (8 * k)) % UInt8
    end
    return nothing
end

"Store the little-endian 64-bit word `w` at the 0-based offset `off` of `b`."
function _sha_put_le64!(b::Vector{UInt8}, off::Int, w::UInt64)::Nothing
    for k in 0:7
        b[off + k + 1] = (w >> (8 * k)) % UInt8
    end
    return nothing
end

"The little-endian 32-bit word at the 0-based offset `off` of `b`."
function _sha_get_le32(b::Vector{UInt8}, off::Int)::UInt32
    w = UInt32(0)
    for k in 3:-1:0
        w = (w << 8) | UInt32(b[off + k + 1])
    end
    return w
end

"The little-endian 64-bit word at the 0-based offset `off` of `b`."
function _sha_get_le64(b::Vector{UInt8}, off::Int)::UInt64
    w = UInt64(0)
    for k in 7:-1:0
        w = (w << 8) | UInt64(b[off + k + 1])
    end
    return w
end

# DIVERGES: see the file header, 2: the bytes of the context string.
"The `SHA_CONTEXT_SIZE` bytes of the context `c` (the file header, 2)."
function sha_context_bytes(c::sha_context)::Vector{UInt8}
    b = zeros(UInt8, SHA_CONTEXT_SIZE)
    _sha_put_le32!(b, 0, c.magic)
    _sha_put_le32!(b, 4, UInt32(c.opts.algorithm))
    _sha_put_le32!(b, 8, UInt32(c.opts.digest_size))
    _sha_put_le32!(b, 12, c.opts.encoding)
    _sha_put_le32!(b, 16, c.sha2.sha2_len)
    u = SHA_CONTEXT_UNION
    alg = c.opts.algorithm
    if alg == ALGORITHM_SHA1
        _sha_put_le32!(b, u, c.sha1.count[1])
        _sha_put_le32!(b, u + 4, c.sha1.count[2])
        for k in 1:5
            _sha_put_le32!(b, u + 4 + 4 * k, c.sha1.hash[k])
        end
        for k in 1:16
            _sha_put_le32!(b, u + 24 + 4 * k, c.sha1.wbuf[k])
        end
    elseif alg == ALGORITHM_SHA224 || alg == ALGORITHM_SHA256
        x = c.sha2.ctx256
        _sha_put_le32!(b, u, x.count[1])
        _sha_put_le32!(b, u + 4, x.count[2])
        for k in 1:8
            _sha_put_le32!(b, u + 4 + 4 * k, x.hash[k])
        end
        copyto!(b, u + 41, x.wbuf, 1, SHA256_BLOCK_SIZE)
    elseif alg == ALGORITHM_SHA384 || alg == ALGORITHM_SHA512
        x = c.sha2.ctx512
        _sha_put_le64!(b, u, x.count[1])
        _sha_put_le64!(b, u + 8, x.count[2])
        for k in 1:8
            _sha_put_le64!(b, u + 8 + 8 * k, x.hash[k])
        end
        copyto!(b, u + 81, x.wbuf, 1, SHA512_BLOCK_SIZE)
    end
    return b
end

# DIVERGES: see the file header, 2: the inverse of `sha_context_bytes`, for ANY 228 bytes (`valid_context` judges the result).
"The context in the `SHA_CONTEXT_SIZE` bytes `b`; the state is read as the algorithm in `b` says (the file header, 2)."
function sha_context_from_bytes(b::Vector{UInt8})::sha_context
    alg = Int(_sha_get_le32(b, 4))
    c = sha_context(
        _sha_get_le32(b, 0),
        sha_optval(alg, Int(_sha_get_le32(b, 8)), 0, _sha_get_le32(b, 12)),
        sha1_ctx(),
        sha2_ctx()
    )
    c.sha2.sha2_len = _sha_get_le32(b, 16)
    u = SHA_CONTEXT_UNION
    if alg == ALGORITHM_SHA1
        c.sha1.count[1] = _sha_get_le32(b, u)
        c.sha1.count[2] = _sha_get_le32(b, u + 4)
        for k in 1:5
            c.sha1.hash[k] = _sha_get_le32(b, u + 4 + 4 * k)
        end
        for k in 1:16
            c.sha1.wbuf[k] = _sha_get_le32(b, u + 24 + 4 * k)
        end
    elseif alg == ALGORITHM_SHA224 || alg == ALGORITHM_SHA256
        x = c.sha2.ctx256
        x.count[1] = _sha_get_le32(b, u)
        x.count[2] = _sha_get_le32(b, u + 4)
        for k in 1:8
            x.hash[k] = _sha_get_le32(b, u + 4 + 4 * k)
        end
        copyto!(x.wbuf, 1, b, u + 41, SHA256_BLOCK_SIZE)
    elseif alg == ALGORITHM_SHA384 || alg == ALGORITHM_SHA512
        x = c.sha2.ctx512
        x.count[1] = _sha_get_le64(b, u)
        x.count[2] = _sha_get_le64(b, u + 8)
        for k in 1:8
            x.hash[k] = _sha_get_le64(b, u + 8 + 8 * k)
        end
        copyto!(x.wbuf, 1, b, u + 81, SHA512_BLOCK_SIZE)
    end
    return c
end

# PORT: packages/clib/sha4pl.c sha_new_ctx as pl_sha_new_ctx
# DIVERGES: see the file header, 2.
"`sha_new_ctx(-Ctx, +Options)`: Ctx is a fresh context, an opaque string (sha4pl.c `pl_sha_new_ctx`)."
function pl_sha_new_ctx2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    op = sha_options(ld, A2)
    op === nothing && return FFALSE

    c = sha_context(
        SHA_CONTEXT_MAGIC,
        sha_optval(op.algorithm, op.digest_size, 0, op.encoding),   # op->algorithm_term = 0
        sha1_ctx(),
        sha2_ctx()
    )

    if op.algorithm == ALGORITHM_SHA1
        sha1_begin!(c.sha1)
    else
        c.sha2 = sha2_begin(op.digest_size)::sha2_ctx
    end

    return if PL_unify_chars(ld, A1, PL_STRING, SHA_CONTEXT_SIZE, sha_context_bytes(c))
        FTRUE   # PL_unify_string_nchars
    else
        FFALSE   # PL_unify_string_nchars
    end   # PL_unify_string_nchars
end

# PORT: packages/clib/sha4pl.c valid_context
"""
Is the context `c` consistent: the magic, a digest size that is the algorithm's, an encoding of utf8 or Latin-1, and for SHA-2
the `sha2_len` of that digest size (sha4pl.c). A string may have been modified.
"""
function valid_context(c::sha_context)::Bool
    c.magic != SHA_CONTEXT_MAGIC && return false
    dsize = sha_digest_size(c.opts.algorithm)
    (dsize == 0 || c.opts.digest_size != dsize) && return false
    c.opts.encoding != REP_UTF8 && c.opts.encoding != REP_ISO_LATIN_1 && return false
    c.opts.algorithm != ALGORITHM_SHA1 && c.sha2.sha2_len != dsize && return false
    return true
end

# PORT: packages/clib/sha4pl.c sha_hash_ctx (the `bad_context` label)
"Raise `domain_error(algorithm, Old)` with the message of a bad old context (sha4pl.c `bad_context`); the predicate then fails."
function _sha_bad_context(ld::PL_local_data{T}, old_ctx::term_t)::foreign_t where {T}
    return if PL_error(
        ld, "", 0, "Invalid OldContext passed", ERR_DOMAIN, mk_sym(T, :algorithm), old_ctx
    )
        FTRUE
    else
        FFALSE
    end
end

# PORT: packages/clib/sha4pl.c sha_hash_ctx as pl_sha_hash_ctx
# DIVERGES: see the file header, 2 and 4. `PL_get_string_chars` is a string whose characters are all below 256, else a plain failure.
"""
`sha_hash_ctx(+Old, +From, -New, -Hash)`: add the text From to the context Old; New is the updated context and Hash the digest of
everything added so far (sha4pl.c `pl_sha_hash_ctx`).
"""
function pl_sha_hash_ctx4_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2, A3, A4 = PL__t0, PL__t0 + 1, PL__t0 + 2, PL__t0 + 3
    old_ctx = A1

    txt = PL_get_text(ld, old_ctx, CVT_STRING)          # PL_get_string_chars(old_ctx, &cp, &clen): no error, a plain failure
    txt === nothing && return FFALSE
    cps = _text_code_points(txt)
    any(c -> c > 255, cps) && return FFALSE              # a wide string is no string of chars
    cbytes = UInt8[c % UInt8 for c in cps]

    length(cbytes) != SHA_CONTEXT_SIZE && return _sha_bad_context(ld, old_ctx)

    c = sha_context_from_bytes(cbytes)
    valid_context(c) || return _sha_bad_context(ld, old_ctx)

    data = _sha_text_bytes(ld, A2, c.opts.encoding)
    data === nothing && return FFALSE

    hval = if c.opts.algorithm == ALGORITHM_SHA1
        sha1_hash!(data, length(data), c.sha1)
        PL_unify_chars(ld, A3, PL_STRING, SHA_CONTEXT_SIZE, sha_context_bytes(c)) ||
            return FFALSE
        h = Vector{UInt8}(undef, SHA1_DIGEST_SIZE)
        sha1_end!(h, c.sha1)
        h
    else
        sha2_hash!(data, length(data), c.sha2)
        PL_unify_chars(ld, A3, PL_STRING, SHA_CONTEXT_SIZE, sha_context_bytes(c)) ||
            return FFALSE
        sha2_end!(c.sha2)
    end

    return PL_unify_chars(ld, A4, PL_CODE_LIST, c.opts.digest_size, hval) ? FTRUE : FFALSE
end

# PORT: packages/clib/sha4pl.c hmac_sha as pl_hmac_sha
# DIVERGES: see the file header, 4 and 5.
"""
`hmac_sha(+Key, +Data, -Mac, +Options)`: Mac is the list of the codes (bytes) of the HMAC of the text Data under the key Key; the
algorithm is sha1 (default) or sha256 (sha4pl.c `pl_hmac_sha`).
"""
function pl_hmac_sha4_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2, A3, A4 = PL__t0, PL__t0 + 1, PL__t0 + 2, PL__t0 + 3
    skey = _sha_text_bytes(ld, A1, REP_ISO_LATIN_1)     # no representation flag: ISO Latin-1
    skey === nothing && return FFALSE
    sdata = _sha_text_bytes(ld, A2, REP_ISO_LATIN_1)
    sdata === nothing && return FFALSE

    opts = sha_options(ld, A4)
    opts === nothing && return FFALSE

    digest = if opts.algorithm == ALGORITHM_SHA1
        hmac_sha1(skey, length(skey), sdata, length(sdata), opts.digest_size)
    elseif opts.algorithm == ALGORITHM_SHA256
        hmac_sha256(skey, length(skey), sdata, length(sdata), opts.digest_size)
    else
        return if PL_error(
            ld, "", 0, "HMAC-SHA only for SHA-1 and SHA-256", ERR_DOMAIN,
            mk_sym(T, :algorithm), opts.algorithm_term
        )
            FTRUE
        else
            FFALSE
        end
    end

    return PL_unify_chars(ld, A3, PL_CODE_LIST, opts.digest_size, digest) ? FTRUE : FFALSE
end

# PORT: packages/clib/sha4pl.c install_sha4pl
# DIVERGES: see the file header, 1.
"The install function of the static extension `sha4pl` (sha4pl.c `install_sha4pl`): the predicates exist already."
function install_sha4pl(ld::PL_local_data{T})::Nothing where {T}
    return nothing
end

# PORT: packages/clib/sha4pl.c install_sha4pl as PL_predicates_from_sha4pl
# DIVERGES: see the file header, 1: the registration is the boot table of module `system`.
const PL_predicates_from_sha4pl = (
    PL_extension("sha_hash", 3, pl_sha_hash3_va, PL_FA_VARARGS),
    PL_extension("sha_new_ctx", 2, pl_sha_new_ctx2_va, PL_FA_VARARGS),
    PL_extension("sha_hash_ctx", 4, pl_sha_hash_ctx4_va, PL_FA_VARARGS),
    PL_extension("hmac_sha", 4, pl_hmac_sha4_va, PL_FA_VARARGS)
)
