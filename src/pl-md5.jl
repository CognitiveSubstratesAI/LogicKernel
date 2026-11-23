# CLASS: code
# COPYRIGHT: Copyright (C) 1999, 2000, 2002 Aladdin Enterprises.  All rights reserved.
# COPYRIGHT: Copyright (c)  2015, University of Amsterdam
# allow-new-artifact: packages/clib C port (Phase 1)
#
# CLIB1 (packages/clib/md5.c and md54pl.c, packages-clib ed3593eb of swipl-devel af9e2e7e): `md5_hash/3` of library(md5),
# the MD5 message digest (L. Peter Deutsch's md5_init/md5_append/md5_finish, RFC 1321) and its Prolog binding. NO `# UPSTREAM:`
# header line: `packages/clib` is a gitlink at the pin, not a blob of swipl-devel, so tools/port_check.jl cannot follow it yet
# (the D2 item of evidence/R2/json_port_handoff.md). BLIND-CODED: no Julia process ran when this file was written.
#
# DIVERGES (file-wide):
#   1. REGISTERED IN `system` AT BOOT, as the json port (src/pl-json.jl, 1): `PL_predicates_from_md54pl` is appended to
#      `_PRED_TABLES` and `_FOREIGN_VA`; `use_foreign_library(foreign(md54pl))` finds `md54pl` in `static_extensions`
#      (src/pl-load.jl) and `install_md54pl` is the empty function.
#   2. THE ROUNDS ARE LOOPS. md5.c unrolls the 64 steps with the macros `F G H I`, `T1..T64` and four `SET` groups; `md5_process` below
#      runs the same 64 steps from the table `_MD5_T` (`T_i = floor(2^32 * abs(sin(i)))`, as RFC 1321) with the same
#      per-round message-word order and rotation counts. The digest is the same function of the same input.
#   3. LITTLE-ENDIAN ONLY: the word read of a block is `reinterpret`-free (`UInt32` assembled from four bytes), which is md5.c's
#      byte-order independent branch (`ARCH_IS_BIG_ENDIAN` undefined).
#   4. TEXT. `PL_get_nchars(from, ..., CVT_ATOM|CVT_STRING|CVT_LIST|CVT_EXCEPTION|opts.encoding)` is ONE `PL_get_text` followed by a
#      recoding to the bytes of the requested encoding: UTF-8 (`REP_UTF8`) through `PL_mb_text`, ISO Latin-1 (`REP_ISO_LATIN_1`, option
#      `encoding(octet)`) by hand: a code above 255 raises `representation_error(encoding)` (pl-text.c `PL_mb_text` -> `PL_demote_text`).
#   5. The digest is unified with `PL_unify_atom_nchars(t, 32, hex)`: an atom made from the 32 lowercase hex digits.

# the table of md5.c's T1..T64 (RFC 1321: floor(2^32 * abs(sin(i))), i in 1..64)
const _MD5_T = UInt32[
    floor(UInt64, 4294967296.0 * abs(sin(Float64(i)))) % UInt32 for i in 1:64
]
# the per-step rotation counts of the four rounds
const _MD5_S = (
    7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
    5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
    4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
    6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21
)

# PORT: packages/clib/md5.h md5_state_t
"The state of the MD5 algorithm (md5.h `md5_state_t`): the message length in bits (`count`, lsw first), the digest buffer and one block."
mutable struct md5_state_t
    count::Vector{UInt32}       # message length in bits, lsw first
    abcd::Vector{UInt32}        # digest buffer
    buf::Vector{UInt8}          # accumulate block
end

# PORT: packages/clib/md5.c md5_init
"Initialize the algorithm (md5.c)."
function md5_init()::md5_state_t
    return md5_state_t(
        UInt32[0, 0],
        UInt32[0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476],   # T_MASK ^ 0x10325476 etc., RFC 1321's A B C D
        zeros(UInt8, 64)
    )
end

# PORT: packages/clib/md5.c md5_process
# DIVERGES: see the file header, 2 and 3.
"Process one 64-byte block `data[off+1:off+64]` of the message (md5.c)."
function md5_process(pms::md5_state_t, data::AbstractVector{UInt8}, off::Int)::Nothing
    a, b, c, d = pms.abcd[1], pms.abcd[2], pms.abcd[3], pms.abcd[4]
    X = Vector{UInt32}(undef, 16)
    for i in 0:15                                   # the byte-order independent word read
        j = off + 4i
        X[i + 1] =
            UInt32(data[j + 1]) | (UInt32(data[j + 2]) << 8) |
            (UInt32(data[j + 3]) << 16) | (UInt32(data[j + 4]) << 24)
    end
    for i in 0:63
        if i < 16                                   # round 1: F(b,c,d) = (b & c) | (~b & d)
            f = (b & c) | (~b & d)
            g = i
        elseif i < 32                               # round 2: G(b,c,d) = (b & d) | (c & ~d)
            f = (b & d) | (c & ~d)
            g = (5i + 1) % 16
        elseif i < 48                               # round 3: H(b,c,d) = b ^ c ^ d
            f = b ⊻ c ⊻ d
            g = (3i + 5) % 16
        else                                        # round 4: I(b,c,d) = c ^ (b | ~d)
            f = c ⊻ (b | ~d)
            g = (7i) % 16
        end
        tmp = d
        d = c
        c = b
        s = _MD5_S[i + 1]
        t = a + f + _MD5_T[i + 1] + X[g + 1]
        b = b + ((t << s) | (t >> (32 - s)))        # ROTATE_LEFT
        a = tmp
    end
    pms.abcd[1] += a
    pms.abcd[2] += b
    pms.abcd[3] += c
    pms.abcd[4] += d
    return nothing
end

# PORT: packages/clib/md5.c md5_append
"Append `nbytes` bytes of `data` to the message (md5.c)."
function md5_append(pms::md5_state_t, data::AbstractVector{UInt8}, nbytes::Int)::Nothing
    nbytes <= 0 && return nothing
    offset = Int(pms.count[1] >> 3) & 63            # read BEFORE the length update
    nbits = UInt32((nbytes << 3) % UInt32)
    p = 0                                           # the next unread byte of `data` (0-based)

    # Update the message length.
    pms.count[2] += UInt32(nbytes >> 29)
    pms.count[1] += nbits
    if pms.count[1] < nbits
        pms.count[2] += 1
    end

    # Process an initial partial block.
    if offset != 0
        copy = (offset + nbytes > 64) ? (64 - offset) : nbytes
        for k in 1:copy
            pms.buf[offset + k] = data[p + k]
        end
        if offset + copy < 64
            return nothing
        end
        p += copy
        nbytes -= copy
        md5_process(pms, pms.buf, 0)
    end

    # Process full blocks.
    while nbytes >= 64
        md5_process(pms, data, p)
        p += 64
        nbytes -= 64
    end

    # Process a final partial block.
    for k in 1:nbytes
        pms.buf[k] = data[p + k]
    end
    return nothing
end

# PORT: packages/clib/md5.c md5_finish
"Finish the message and return the 16-byte digest (md5.c)."
function md5_finish(pms::md5_state_t)::Vector{UInt8}
    pad = zeros(UInt8, 64)
    pad[1] = 0x80
    data = Vector{UInt8}(undef, 8)
    # Save the length before padding.
    for i in 0:7
        data[i + 1] = UInt8((pms.count[(i >> 2) + 1] >> ((i & 3) << 3)) & 0xff)
    end
    # Pad to 56 bytes mod 64.
    md5_append(pms, pad, ((55 - Int(pms.count[1] >> 3)) & 63) + 1)
    # Append the length.
    md5_append(pms, data, 8)
    digest = Vector{UInt8}(undef, 16)
    for i in 0:15
        digest[i + 1] = UInt8((pms.abcd[(i >> 2) + 1] >> ((i & 3) << 3)) & 0xff)
    end
    return digest
end

# PORT: packages/clib/md54pl.c md5_options
# (the option table `md5_option_specs`: PL_OPTION("encoding", OPT_TERM))
const md5_option_specs = (PL_option_t(:encoding, OPT_TERM),)

# PORT: packages/clib/md54pl.c md5_options
# DIVERGES: returns the `REP_*` encoding flag (`opts.encoding`), or `nothing` with the error raised; `PL_scan_options` returns the values.
"The encoding flag of the options `options` of md5_hash/3: `REP_UTF8` (default) or `REP_ISO_LATIN_1` (md54pl.c)."
function md5_options(
    ld::PL_local_data{T}, options::term_t
)::Union{Nothing, UInt32} where {T}
    vals = PL_scan_options(ld, options, 0, "md5_option", md5_option_specs)
    vals === nothing && return nothing
    encoding = vals[1]
    encoding === nothing && return REP_UTF8
    a = PL_get_atom_ex(ld, encoding)
    a === nothing && return nothing
    if sym_key(a) == sym_key(mk_sym(T, :utf8))
        return REP_UTF8
    elseif sym_key(a) == sym_key(mk_sym(T, :octet))
        return REP_ISO_LATIN_1
    end
    PL_domain_error(ld, "encoding", encoding)
    return nothing
end

# PORT: packages/clib/md54pl.c md5_unify_digest
"Unify `t` with the atom of the 32 lowercase hex digits of `digest` (md54pl.c)."
function md5_unify_digest(
    ld::PL_local_data{T}, t::term_t, digest::Vector{UInt8}
)::Bool where {T}
    hexd = "0123456789abcdef"
    io = IOBuffer()
    for b in digest
        write(io, hexd[((b >> 4) & 0x0f) + 1])
        write(io, hexd[(b & 0x0f) + 1])
    end
    return PL_unify_atom(ld, t, _atom_from_text(T, String(take!(io))))   # PL_unify_atom_nchars(t, 16*2, hex_output)
end

# PORT: packages/clib/md54pl.c md5_hash
# DIVERGES: see the file header, 4.
"`md5_hash(+Data, -Hash, +Options)`: Hash is the atom of the MD5 digest of the text Data, in `encoding(utf8|octet)` (md54pl.c)."
function pl_md5_hash3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2, A3 = PL__t0, PL__t0 + 1, PL__t0 + 2
    enc = md5_options(ld, A3)
    enc === nothing && return FFALSE

    txt = PL_get_text(ld, A1, CVT_ATOM | CVT_STRING | CVT_LIST | CVT_EXCEPTION)
    txt === nothing && return FFALSE
    PL_canonicalise_text_ex(ld, txt) || return FFALSE
    data = if enc == REP_UTF8
        PL_mb_text(txt, REP_UTF8) || return FFALSE
        txt.text
    else                                            # REP_ISO_LATIN_1
        cps = _text_code_points(txt)
        any(c -> c > 255, cps) &&
            return if PL_error(ld, ERR_REPRESENTATION, mk_sym(T, :encoding))
                FTRUE
            else
                FFALSE
            end
        UInt8[c % UInt8 for c in cps]
    end

    state = md5_init()
    md5_append(state, data, length(data))
    digest = md5_finish(state)
    return md5_unify_digest(ld, A2, digest) ? FTRUE : FFALSE
end

# PORT: packages/clib/md54pl.c install_md54pl
# DIVERGES: see the file header, 1.
"The install function of the static extension `md54pl` (md54pl.c `install_md54pl`): the predicate exists already."
function install_md54pl(ld::PL_local_data{T})::Nothing where {T}
    return nothing
end

# PORT: packages/clib/md54pl.c install_md54pl as PL_predicates_from_md54pl
# DIVERGES: see the file header, 1: the registration is the boot table of module `system`.
const PL_predicates_from_md54pl = (
    PL_extension("md5_hash", 3, pl_md5_hash3_va, PL_FA_VARARGS),
)
