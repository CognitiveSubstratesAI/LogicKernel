# UPSTREAM: swipl-devel src/pl-termhash.c @ bae881a24a3f
# UPSTREAM: swipl-devel src/pl-termhash.h @ bae881a24a3f
# CLASS: code
# COPYRIGHT: Copyright (c)  2010-2023, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
# COPYRIGHT: Copyright (c) 2002, Dr Brian Gladman, Worcester, UK.   All rights reserved.
#
# TERM HASHING — SWI-Prolog's `term_hash/2`, `variant_sha1/2` and `variant_hash/2`:
#   * term_hash: a 32-bit MurmurHash of a GROUND term, the same for identical (`==`) terms; no hash
#     for a term with variables.
#   * variant_sha1 / variant_hash: a digest of a term's VARIANT CLASS, the same for `=@=` terms —
#     the term is serialised in pre-order (src/pl-termwalk.jl) with each variable replaced by the
#     number of its first occurrence, and the bytes go through SHA-1 (Gladman's byte-oriented
#     implementation, ported below) or an incremental MurmurHash masked to 24 bits.
#
# DIVERGES (file-wide):
#   1. ATOMIC DATA. The term interface hides names and payloads, so an atom contributes its
#      process-independent `sym_hash` where upstream contributes its name (term_hash: the name's
#      32-bit hash; variant_sha1: length, name and blob type), and a grounded value contributes its
#      `gnd_key` where upstream contributes the number's or string's bytes; a value with no key
#      contributes a constant. So the VALUES are not SWI's (tests/core_lang/test_hash.jl asserts
#      the properties upstream's pinned values stand for), and upstream's "same digest IFF variant"
#      holds in one direction: variants ⇒ the same digest. The converse fails only where keys
#      collide — by chance, for `sym_hash` and for `gnd_key`, which follows the term type's
#      `gnd_equal` (SWI's identity in the reference type, so `1` and `1.0` hash apart as in SWI; a
#      type matching by `==` would make them share a digest). Assumes, as every key function does,
#      that identical grounded values have the same `gnd_key`.
#   2. HEADS. A compound whose first child is not a symbol has no functor: term_hash hashes the
#      name hash 0 and every child as an argument; variant_sha1 writes `C` and the child count where
#      upstream writes `T`, name and arity (see `_comp_shape`).
#   3. FINITE TREES. Interface terms have no cycles and no attributed variables, and no cells to
#      mark: no `CYCLE_CONST`/`in_cycle`, no reuse of a shared subterm's hash (a finite shared
#      subterm rehashes to the same value), no canonical-form rehash of a cyclic term
#      (`hash_prefix`), no `E_ATTVAR`/`E_CYCLE`/`E_RESOURCE`. Variables are numbered in a map
#      where upstream overwrites their cells and restores them afterwards.
#   4. BYTE ORDER. A word goes into the digest as its little-endian bytes — what upstream hashes
#      on the machines it runs on — on every host.

# ── term_hash/2 ─────────────────────────────────────────────────────────────────────────────────
# PORT: pl-termhash.c th_data
# DIVERGES: no `in_cycle` (see the file header); the functor is `(off, arity)` from `_comp_shape`.
"A compound being hashed (pl-termhash.c `th_data`)."
mutable struct th_data{T}
    parent_offset::Int      # my parent: its index in the buffer; 0 for none (upstream (size_t)-1)
    term::T                 # term being processed
    off::Int                # child index of its argument 0
    arity::Int              # its number of arguments
    hash::UInt32            # hash collected so far
    arg::Int                # current argument (0-based)
end

# PORT: pl-termhash.c primitiveHashValue
"""
Fold the atomic term `term` into `hval`; `nothing` for a variable (pl-termhash.c). An atom adds the
4 low bytes of its `sym_hash` (upstream: its `unsigned int` name hash), a grounded value the 8
bytes of its `gnd_key`, 0 when it has none (upstream: the integer's, float's or string's bytes).
"""
function primitiveHashValue(term, hval::UInt32)::Union{Nothing, UInt32}
    k = kind(term)
    if k === VAR
        return nothing
    elseif k === SYM
        return MurmurHashAligned2((sym_hash(term),), 4, hval)
    end
    @assert k === GND                       # upstream: default: assert(0)
    g = gnd_key(term)
    return MurmurHashAligned2((g === nothing ? UInt64(0) : g,), 8, hval)
end

# PORT: pl-termhash.c start_term as th_start_term
"""
A node for compound `t` below node `parent`: its hash starts from `MURMUR_SEED` and its name's
hash — `sym_hash` of a symbol head, 0 for any other head (pl-termhash.c `start_term`).
"""
function th_start_term(t::T, parent::Int)::th_data{T} where {T}
    off, arity = _comp_shape(t)
    hash = MURMUR_SEED
    name = off == 2 ? sym_hash(child(t, 1)) : UInt64(0)
    hash = MurmurHashAligned2((name,), 4, hash)
    return th_data{T}(parent, t, off, arity, hash, 0)
end

# PORT: pl-termhash.c next_arg as th_next_arg
"""
The next argument to hash, or `nothing` when the root is done; a finished node folds its hash into
its parent's, and `workp` moves up to the parent (pl-termhash.c `next_arg`).
"""
function th_next_arg!(
    workp::Base.RefValue{Int}, b::Vector{th_data{T}}
)::Union{Nothing, T} where {T}
    work = b[workp[]]
    while true
        if work.arg < work.arity
            return child(work.term, work.off + work.arg)
        elseif work.parent_offset != 0
            parent = b[work.parent_offset]
            myhash = work.hash
            parent.hash = MurmurHashAligned2((UInt64(myhash),), 4, parent.hash)
            workp[] = work.parent_offset
            work = parent
            work.arg += 1
        else
            return nothing
        end
    end
end

# PORT: pl-termhash.c termHashValue
"The hash of `p`, or `nothing` when it is not ground (pl-termhash.c)."
function termHashValue(p::T)::Union{Nothing, UInt32} where {T}
    if kind(p) !== EXPR
        return primitiveHashValue(p, MURMUR_SEED)
    end
    b = th_data{T}[]
    push!(b, th_start_term(p, 0))
    workp = Ref(1)
    while true
        q = th_next_arg!(workp, b)
        q === nothing && break
        work = b[workp[]]
        if kind(q) !== EXPR
            h = primitiveHashValue(q, work.hash)
            if h === nothing
                return nothing                  # rc = false: non-ground
            end
            work.hash = h
            work.arg += 1
        else
            push!(b, th_start_term(q, workp[]))
            workp[] = length(b)
        end
    end
    return b[1].hash
end

# PORT: pl-termhash.c term_hash as pl_term_hash
"""
    pl_term_hash(t) -> Union{UInt32, Nothing}

`term_hash/2`: a hash of the ground term `t`, the same for identical terms; `nothing` when `t` has
a variable (upstream leaves the hash unbound) (pl-termhash.c).
"""
pl_term_hash(t) = termHashValue(t)

# ── SHA-1 (Brian Gladman, byte oriented) ────────────────────────────────────────────────────────
# PORT: pl-termhash.h SHA1_DIGEST_SIZE
"Bytes in a SHA-1 digest (pl-termhash.h)."
const SHA1_DIGEST_SIZE = 20
# PORT: pl-termhash.c SHA1_BLOCK_SIZE
"Bytes in a SHA-1 block (pl-termhash.c)."
const SHA1_BLOCK_SIZE = 64
# PORT: pl-termhash.c SHA1_MASK
"`SHA1_BLOCK_SIZE - 1` (pl-termhash.c)."
const SHA1_MASK = SHA1_BLOCK_SIZE - 1

# PORT: pl-termhash.c sha1_ctx
# DIVERGES: C arrays are Vectors, 1-based: `count[0]` is `count[1]`.
"The SHA-1 context (pl-termhash.c)."
struct sha1_ctx
    count::Vector{UInt32}           # 2: the byte count, low word first
    hash::Vector{UInt32}            # 5
    wbuf::Vector{UInt32}            # 16: the block being filled
end
sha1_ctx() = sha1_ctx(zeros(UInt32, 2), zeros(UInt32, 5), zeros(UInt32, 16))

# PORT: pl-termhash.c rotl32
"Rotate left (pl-termhash.c)."
rotl32(x::UInt32, n::Int)::UInt32 = (x << n) | (x >> (32 - n))
# PORT: pl-termhash.c rotr32
"Rotate right (pl-termhash.c)."
rotr32(x::UInt32, n::Int)::UInt32 = (x >> n) | (x << (32 - n))
# PORT: pl-termhash.c bswap_32
"Reverse the bytes of a word (pl-termhash.c)."
bswap_32(x::UInt32)::UInt32 = (rotr32(x, 24) & 0x00ff00ff) | (rotr32(x, 8) & 0xff00ff00)

# PORT: pl-termhash.c bsw_32
"""
Byte-swap the first `n` words of `p` on a little-endian machine (`SWAP_BYTES`), so that the bytes
written in arrive in big-endian word order; nothing on a big-endian one (pl-termhash.c).
"""
function bsw_32!(p::Vector{UInt32}, n::Int)::Nothing
    if ENDIAN_BOM == 0x04030201             # PLATFORM_BYTE_ORDER == IS_LITTLE_ENDIAN
        _i = n
        while _i > 0
            _i -= 1
            p[_i + 1] = bswap_32(p[_i + 1])
        end
    end
    return nothing
end

# PORT: pl-termhash.c ch as sha1_ch
"SHA-1's choice function (pl-termhash.c `ch`)."
sha1_ch(x::UInt32, y::UInt32, z::UInt32)::UInt32 = z ⊻ (x & (y ⊻ z))
# PORT: pl-termhash.c parity as sha1_parity
"SHA-1's parity function (pl-termhash.c `parity`)."
sha1_parity(x::UInt32, y::UInt32, z::UInt32)::UInt32 = x ⊻ y ⊻ z
# PORT: pl-termhash.c maj as sha1_maj
"SHA-1's majority function (pl-termhash.c `maj`)."
sha1_maj(x::UInt32, y::UInt32, z::UInt32)::UInt32 = (x & y) | (z & (x ⊻ y))

# PORT: pl-termhash.c hf as sha1_hf
# DIVERGES: upstream redefines the `hf` macro after round 15; one function chooses by `i`.
"""
The message word of round `i`: `w[i]` for the first 16 rounds, then the next word of the expanded
schedule, computed in place (pl-termhash.c `hf`).
"""
@inline function sha1_hf!(w::Vector{UInt32}, i::Int)::UInt32
    @inbounds begin                         # `w` is `wbuf` (16 words); every index is `& 15`
        if i < 16
            return w[i + 1]
        end
        w[(i & 15) + 1] = rotl32(
            w[((i + 13) & 15) + 1] ⊻ w[((i + 8) & 15) + 1] ⊻ w[((i + 2) & 15) + 1] ⊻
            w[(i & 15) + 1],
            1
        )
        return w[(i & 15) + 1]
    end
end

# PORT: pl-termhash.c one_cycle
"""
`one_cycle(v,a,b,c,d,e,f,k,h)` (pl-termhash.c): one round over the caller's locals `v0`…`v4` —
upstream's default build, where `q(v,n)` is `v##n`, so the positions `a`…`e` are integer literals.
"""
macro one_cycle(a::Int, b::Int, c::Int, d::Int, e::Int, f, k, h)
    va, vb, vc, vd, ve = (Symbol(:v, x) for x in (a, b, c, d, e))
    return esc(quote
        $ve += rotr32($va, 27) + $f($vb, $vc, $vd) + $k + $h
        $vb = rotr32($vb, 2)
    end)
end

# PORT: pl-termhash.c five_cycle
"`five_cycle(v,f,k,i)` (pl-termhash.c): five rounds from round `i`, the positions rotating."
macro five_cycle(f, k, i::Int)
    return esc(quote
        @one_cycle(0, 1, 2, 3, 4, $f, $k, sha1_hf!(w, $i))
        @one_cycle(4, 0, 1, 2, 3, $f, $k, sha1_hf!(w, $(i + 1)))
        @one_cycle(3, 4, 0, 1, 2, $f, $k, sha1_hf!(w, $(i + 2)))
        @one_cycle(2, 3, 4, 0, 1, $f, $k, sha1_hf!(w, $(i + 3)))
        @one_cycle(1, 2, 3, 4, 0, $f, $k, sha1_hf!(w, $(i + 4)))
    end)
end

# PORT: pl-termhash.c sha1_compile
"Compile the 64-byte block in `ctx.wbuf` into `ctx.hash` (pl-termhash.c)."
function sha1_compile!(ctx::sha1_ctx)::Nothing
    w = ctx.wbuf
    v0 = ctx.hash[1]
    v1 = ctx.hash[2]
    v2 = ctx.hash[3]
    v3 = ctx.hash[4]
    v4 = ctx.hash[5]

    @five_cycle(sha1_ch, 0x5a827999, 0)
    @five_cycle(sha1_ch, 0x5a827999, 5)
    @five_cycle(sha1_ch, 0x5a827999, 10)
    @one_cycle(0, 1, 2, 3, 4, sha1_ch, 0x5a827999, sha1_hf!(w, 15))

    @one_cycle(4, 0, 1, 2, 3, sha1_ch, 0x5a827999, sha1_hf!(w, 16))
    @one_cycle(3, 4, 0, 1, 2, sha1_ch, 0x5a827999, sha1_hf!(w, 17))
    @one_cycle(2, 3, 4, 0, 1, sha1_ch, 0x5a827999, sha1_hf!(w, 18))
    @one_cycle(1, 2, 3, 4, 0, sha1_ch, 0x5a827999, sha1_hf!(w, 19))

    @five_cycle(sha1_parity, 0x6ed9eba1, 20)
    @five_cycle(sha1_parity, 0x6ed9eba1, 25)
    @five_cycle(sha1_parity, 0x6ed9eba1, 30)
    @five_cycle(sha1_parity, 0x6ed9eba1, 35)

    @five_cycle(sha1_maj, 0x8f1bbcdc, 40)
    @five_cycle(sha1_maj, 0x8f1bbcdc, 45)
    @five_cycle(sha1_maj, 0x8f1bbcdc, 50)
    @five_cycle(sha1_maj, 0x8f1bbcdc, 55)

    @five_cycle(sha1_parity, 0xca62c1d6, 60)
    @five_cycle(sha1_parity, 0xca62c1d6, 65)
    @five_cycle(sha1_parity, 0xca62c1d6, 70)
    @five_cycle(sha1_parity, 0xca62c1d6, 75)

    ctx.hash[1] += v0
    ctx.hash[2] += v1
    ctx.hash[3] += v2
    ctx.hash[4] += v3
    ctx.hash[5] += v4
    return nothing
end

# PORT: pl-termhash.c sha1_begin
"Start a SHA-1 digest (pl-termhash.c)."
function sha1_begin!(ctx::sha1_ctx)::Nothing
    ctx.count[1] = ctx.count[2] = 0
    ctx.hash[1] = 0x67452301
    ctx.hash[2] = 0xefcdab89
    ctx.hash[3] = 0x98badcfe
    ctx.hash[4] = 0x10325476
    ctx.hash[5] = 0xc3d2e1f0
    return nothing
end

# PORT: pl-termhash.c sha1_hash
# DIVERGES: `len` is checked against `data` — upstream trusts it — because the copies are
# upstream's `memcpy`s (`unsafe_copyto!` into `wbuf`'s bytes; measured 4 ns against 15 ns through a
# `reinterpret` view, the same bytes at every offset).
"Add the first `len` bytes of `data` to the digest (pl-termhash.c)."
function sha1_hash!(data::Vector{UInt8}, len::Int, ctx::sha1_ctx)::Nothing
    0 <= len <= length(data) || throw(BoundsError(data, len))
    pos = Int(ctx.count[1] & UInt32(SHA1_MASK))
    space = SHA1_BLOCK_SIZE - pos
    sp = 0

    ctx.count[1] = ctx.count[1] + (len % UInt32)
    if ctx.count[1] < len
        ctx.count[2] += 1
    end

    while len >= space                      # transfer whole blocks if possible
        _sha1_memcpy!(ctx, pos, data, sp, space)
        sp += space
        len -= space
        space = SHA1_BLOCK_SIZE
        pos = 0
        bsw_32!(ctx.wbuf, SHA1_BLOCK_SIZE >> 2)
        sha1_compile!(ctx)
    end

    _sha1_memcpy!(ctx, pos, data, sp, len)
    return nothing
end

"`memcpy(((unsigned char*)ctx->wbuf) + pos, data + sp, n)` — the caller keeps `pos + n ≤ 64`."
function _sha1_memcpy!(
    ctx::sha1_ctx, pos::Int, data::Vector{UInt8}, sp::Int, n::Int
)::Nothing
    GC.@preserve ctx data begin
        unsafe_copyto!(Ptr{UInt8}(pointer(ctx.wbuf)) + pos, pointer(data, sp + 1), n)
    end
    return nothing
end

# PORT: pl-termhash.c sha1_end
"Pad, finish, and write the 20-byte digest into `hval` (pl-termhash.c)."
function sha1_end!(hval::AbstractVector{UInt8}, ctx::sha1_ctx)::Nothing
    i = ctx.count[1] & UInt32(SHA1_MASK)

    # put bytes in the buffer in an order in which references to 32-bit words will put bytes
    # with lower addresses into the top of 32 bit words on BOTH big and little endian machines
    bsw_32!(ctx.wbuf, Int((i + UInt32(3)) >> 2))

    # mask valid bytes and add the padding: a single 1 bit and as many zero bits as necessary;
    # the first padding byte always fits, as the buffer always has an empty slot
    ctx.wbuf[(i >> 2) + 1] &= 0xffffff80 << (8 * (~i & UInt32(3)))
    ctx.wbuf[(i >> 2) + 1] |= 0x00000080 << (8 * (~i & UInt32(3)))

    # 9 or more empty positions are needed: one for the padding byte, eight for the length; if
    # there are not enough, pad and empty the buffer
    if i > SHA1_BLOCK_SIZE - 9
        if i < 60
            ctx.wbuf[16] = 0
        end
        sha1_compile!(ctx)
        i = UInt32(0)
    else                                    # a word index for the empty buffer positions
        i = (i >> 2) + UInt32(1)
    end

    while i < 14                            # zero pad all but the last two positions
        ctx.wbuf[i + 1] = 0
        i += UInt32(1)
    end

    # the length in bits, as two 32-bit words
    ctx.wbuf[15] = (ctx.count[2] << 3) | (ctx.count[1] >> 29)
    ctx.wbuf[16] = ctx.count[1] << 3
    sha1_compile!(ctx)

    # extract the hash value as bytes
    for j in 0:(SHA1_DIGEST_SIZE - 1)
        hval[j + 1] = (ctx.hash[(j >> 2) + 1] >> (8 * (~j & 3))) % UInt8
    end
    return nothing
end

# ── incremental MurmurHash ──────────────────────────────────────────────────────────────────────
# PORT: pl-termhash.c HASH_BLOCK_SIZE
"Bytes `variant_hash` collects before hashing them into its running hash (pl-termhash.c)."
const HASH_BLOCK_SIZE = 256

# PORT: pl-termhash.c hash_state
"An incremental MurmurHash: the hash of the full blocks so far and the bytes since (pl-termhash.c)."
mutable struct hash_state
    hash::UInt32
    len::Int
    buf::Vector{UInt8}              # HASH_BLOCK_SIZE bytes
end
hash_state() = hash_state(MURMUR_SEED, 0, zeros(UInt8, HASH_BLOCK_SIZE))

# PORT: pl-termhash.c hash_init
"Start an incremental hash (pl-termhash.c)."
function hash_init!(state::hash_state)::Nothing
    state.len = 0
    state.hash = MURMUR_SEED
    return nothing
end

# PORT: pl-termhash.c hash_compile
# UPSTREAM DEFECT (kept verbatim): when `data` does not fit in the block, the loop copies every
# chunk from the START of `data` — it never advances `data` — so the bytes past the first chunk are
# replaced by `data`'s first bytes. Measured on swipl 10.1.16 (2026-10-03): two 310-byte atoms that
# differ only after byte 247 get the same `variant_hash/2` (14123625) while `variant_sha1/2` and
# `term_hash/2` tell them apart. Variants still hash alike (equal input, equal bytes); only more
# non-variants collide. Here the inputs are at most 8 bytes, so only a word straddling a block loses
# its high bytes. Tracked as LogicKernel#2 (docs/upstream_reports.md); upstream report pending.
"Add the first `len` bytes of `data` (pl-termhash.c)."
function hash_compile!(state::hash_state, data::AbstractVector{UInt8}, len::Int)::Nothing
    if len + state.len <= HASH_BLOCK_SIZE
        copyto!(state.buf, state.len + 1, data, 1, len)
        state.len += len
    else
        while len > 0
            copy = len
            if len > HASH_BLOCK_SIZE - state.len
                copy = HASH_BLOCK_SIZE - state.len
            end
            len -= copy
            copyto!(state.buf, state.len + 1, data, 1, copy)
            state.len += copy
            if state.len == HASH_BLOCK_SIZE
                state.hash = MurmurHashAligned2(state.buf, HASH_BLOCK_SIZE, state.hash)
                state.len = 0
            end
        end
    end
    return nothing
end

# PORT: pl-termhash.c hash_end
"The hash of everything added (pl-termhash.c)."
hash_end(state::hash_state)::UInt32 = MurmurHashAligned2(state.buf, state.len, state.hash)

# ── variant_sha1/2, variant_hash/2 ──────────────────────────────────────────────────────────────
# PORT: pl-termhash.h hash_algo
"Which digest a variant walk computes (pl-termhash.h)."
@enum hash_algo HASH_SHA1 HASH_MURMUR

# PORT: pl-termhash.h termhash_t
# DIVERGES: a union upstream; here both members, the one not computed zero.
"A variant digest: the SHA-1 bytes or the MurmurHash (pl-termhash.h)."
struct termhash_t
    sha1::NTuple{SHA1_DIGEST_SIZE, UInt8}
    murmur::UInt32
end

# PORT: pl-termhash.c sha1_state
# DIVERGES: both contexts where upstream has a union; `vars` maps a variable to its number where
# upstream keeps the cells it overwrote, to restore them; `word` is scratch for the bytes of `HASH`.
"The state of a variant walk (pl-termhash.c)."
struct sha1_state
    var_count::Base.RefValue{Int}
    algorithm::hash_algo
    sha1::sha1_ctx
    murmur::hash_state
    vars::Dict{UInt64, Int}
    word::Vector{UInt8}
end
sha1_state(algorithm::hash_algo) = sha1_state(
    Ref(0), algorithm, sha1_ctx(), hash_state(), Dict{UInt64, Int}(), zeros(UInt8, 8)
)

# PORT: pl-termhash.c HASH
"Add the first `l` bytes of `p` to the digest the walk computes (pl-termhash.c `HASH`)."
function HASH!(state::sha1_state, p::AbstractVector{UInt8}, l::Int)::Nothing
    if state.algorithm == HASH_SHA1
        sha1_hash!(p, l, state.sha1)
    else
        hash_compile!(state.murmur, p, l)
    end
    return nothing
end

"`HASH(\"c\", 1)`: one tag character."
function _HASH_char!(state::sha1_state, c::Char)::Nothing
    state.word[1] = UInt8(c)
    return HASH!(state, state.word, 1)
end

"`HASH(&w, sizeof(w))`: the 8 bytes of a word, little-endian."
function _HASH_word!(state::sha1_state, w::UInt64)::Nothing
    for j in 1:8
        state.word[j] = (w >> (8 * (j - 1))) % UInt8
    end
    return HASH!(state, state.word, 8)
end

# PORT: pl-termhash.c variant_sha1 as variant_sha1_walk
# DIVERGES: what each kind of subterm writes (see the file header): a variable `V` and its numbered
# word, as upstream; an atom `A` and its `sym_hash`; a grounded value `G` and its `gnd_key`, or
# `g` alone when it has none; a compound `T`, its head's `sym_hash` and its arity, or `C` and its
# child count when its head is not a symbol. Every kind writes a fixed number of bytes after its
# letter, so different terms never write the same bytes by running into each other.
"Write the serialisation of every subterm the agenda walks into the digest (pl-termhash.c)."
function variant_sha1_walk!(agenda::ac_term_agenda{T}, state::sha1_state)::Nothing where {T}
    while true
        p = ac_nextTermAgenda(agenda)
        p === nothing && return nothing
        k = kind(p)
        if k === VAR
            i = get!(state.vars, var_key(p), state.var_count[])
            if i == state.var_count[]       # isVar(w): the first occurrence, numbered now
                state.var_count[] += 1
            end
            _HASH_char!(state, 'V')
            _HASH_word!(state, (UInt64(i) << LMASK_BITS) | TAG_VAR | MARK_MASK)
        elseif k === SYM
            _HASH_char!(state, 'A')
            _HASH_word!(state, sym_hash(p))
        elseif k === GND
            g = gnd_key(p)
            if g === nothing
                _HASH_char!(state, 'g')
            else
                _HASH_char!(state, 'G')
                _HASH_word!(state, g)
            end
        else
            off, arity = ac_pushTermAgenda(agenda, p)
            if off == 2
                _HASH_char!(state, 'T')
                _HASH_word!(state, sym_hash(child(p, 1)))
            else
                _HASH_char!(state, 'C')
            end
            _HASH_word!(state, UInt64(arity))
        end
    end
end

# PORT: pl-termhash.c variant_hash_walk
"The digest of `term`'s variant class under `algorithm` (pl-termhash.c)."
function variant_hash_walk(term::T, algorithm::hash_algo)::termhash_t where {T}
    state = sha1_state(algorithm)
    if algorithm == HASH_SHA1
        sha1_begin!(state.sha1)
    else
        hash_init!(state.murmur)
    end
    agenda = ac_initTermAgenda(term)
    variant_sha1_walk!(agenda, state)
    if state.algorithm == HASH_SHA1
        hval = zeros(UInt8, SHA1_DIGEST_SIZE)
        sha1_end!(hval, state.sha1)
        return termhash_t(ntuple(i -> hval[i], Val(SHA1_DIGEST_SIZE)), UInt32(0))
    end
    return termhash_t(ntuple(_ -> 0x00, Val(SHA1_DIGEST_SIZE)), hash_end(state.murmur))
end

# PORT: pl-termhash.c variant_hash
# DIVERGES: no cyclic terms and no attributed variables, so no canonical-form rehash and no
# errors — the walk's digest is the answer.
"""
    variant_hash(term, algorithm) -> termhash_t

The digest of `term`'s variant class: equal for `=@=` terms (pl-termhash.c).
"""
variant_hash(term::T, algorithm::hash_algo) where {T} = variant_hash_walk(term, algorithm)

# PORT: pl-termhash.c variant_sha1 as pl_variant_sha1
"""
    pl_variant_sha1(t) -> String

`variant_sha1/2`: the SHA-1 digest of `t`'s variant class, as 40 lowercase hex digits; the same
for `=@=` terms (pl-termhash.c).
"""
function pl_variant_sha1(t)::String
    hash = variant_hash(t, HASH_SHA1)
    hexd = "0123456789abcdef"
    o = Vector{UInt8}(undef, SHA1_DIGEST_SIZE * 2)
    for n in 1:SHA1_DIGEST_SIZE
        i = hash.sha1[n]
        o[2n - 1] = codeunit(hexd, (i >> 4) + 1)
        o[2n] = codeunit(hexd, (i & 0x0f) + 1)
    end
    return String(o)
end

# PORT: pl-termhash.c variant_hash as pl_variant_hash
"""
    pl_variant_hash(t) -> Int

`variant_hash/2`: the MurmurHash of `t`'s variant class, masked to `PLMAXTAGGEDINT32`; the same
for `=@=` terms (pl-termhash.c).
"""
pl_variant_hash(t)::Int = Int(variant_hash(t, HASH_MURMUR).murmur & PLMAXTAGGEDINT32)
