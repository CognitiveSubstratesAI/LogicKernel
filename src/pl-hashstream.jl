# CLASS: code
# COPYRIGHT: Copyright (c)  2007-2015, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# allow-new-artifact: packages/clib C port (Phase 1)
#
# HASH1 (packages/clib/hash_stream.c, packages-clib ed3593eb of swipl-devel af9e2e7e): library(hash_stream), `open_hash_stream/3` and
# `stream_hash/2`: a filter stream that keeps a hash (MD5, SHA-1, SHA-224/256/384/512) of the bytes that pass through it. It is the
# stream filter of STREAMX (src/os/pl-stream.jl `AbstractSfilter`, `Snew(::AbstractSfilter, ...)`, `Sset_filter`, `Sfread`, `Sfwrite`)
# over the hash cores of src/pl-md5.jl (CLIB1) and src/pl-sha.jl (CLIB5; SHA-1 is src/pl-termhash.jl's). NO `# UPSTREAM:` header line:
# `packages/clib` is a gitlink at the pin, not a blob of swipl-devel, so tools/port_check.jl cannot follow it yet (the D2 item of
# evidence/R2/json_port_handoff.md). BLIND-CODED: no Julia process ran when this file was written.
#
# DIVERGES (file-wide):
#   1. REGISTERED IN `system` AT BOOT, as the json, md5 and sha ports: `PL_predicates_from_hashstream` is meant for `_PRED_TABLES` and
#      `_FOREIGN_VA` (src/pl-ext.jl) and `use_foreign_library(foreign(hashstream))` for a row `("hashstream", install_hashstream)` of
#      `static_extensions` (src/pl-load.jl, JSON1: NOT in this branch's base; the wiring is left to integration with wip/clib1).
#      `install_hashstream` is the empty function (its atoms are `mk_sym(T, :md5)` and so on).
#   2. THE RECORD. upstream's `IOFUNCTIONS` table `hash_functions` and the C context `hash_context` are one Julia type, `HashContext{T}`
#      (an `AbstractSfilter`): the callbacks are the methods `Sfilter_read/write/close/control` on it. The union `state` is a field of
#      the three state types (`md5_state_t`, `sha1_ctx`, `sha2_ctx`); `stream_hash/2`'s `hash_context copy = *ctx` is `_hash_copy_state`
#      (the states hold vectors, so a struct copy would share them). `s->functions != &hash_functions` is "not a filter stream whose
#      record is a `HashContext`".
#   3. THE BUFFERS. `Sfread`/`Sfwrite` (src/os/pl-stream.jl) fill and read a byte vector from index 1, where C passes `buf` and
#      `buf+written`; the reader and writer go through the record's `scratch` vector and copy to or from the filter's buffer at `from`.
#   4. NO CONTROL ON THE PARENT'S OWN FUNCTION SET. `hash_control` forwards an action to `ctx->stream->functions->control`; the kernel's
#      `S_control` has a control function only for filter streams (answering `SCONTROL_NONE` for every other set), which is upstream's NULL
#      `control`: `SIO_FLUSHOUTPUT` is then 0 and any other action -1, as upstream.
#   5. THE CLOSE HOOK. upstream's `Sclose` runs pl-file.c `freeStream` as the stream layer's close hook; the kernel's closers call it
#      after `Sclose` (src/os/pl-file.jl `freeStream`). `hash_close` closes the PARENT itself, which no kernel closer sees, so the record
#      holds the local data `ld` and `Sfilter_close` calls `freeStream(ld, parent)` after `Sclose(parent)`; `pl_open_hash_stream3_va`
#      does the same for the filter stream it closes after a failed `PL_unify_stream`.
#   6. NOT PORTED: the "no memory" exit of `Snew` (a Julia allocation cannot fail); `PL_free` of the context (Julia's GC); the locks
#      `PL_get_stream_handle` takes and `PL_release_stream` drops (`PL_release_stream` is `streamStatus`, as src/pl-string.jl).
#   7. `representation_error(digest_length)` of `unify_digest` is unreachable from the six algorithms (the longest digest is 64 bytes,
#      128 hex digits of the 256 allowed); `hash_unify_digest` is exercised directly by the test.

# PORT: packages/clib/hash_stream.c hash_algorithm
# DIVERGES: constants, not an `enum` (the names carry `HASH_`: `ALGORITHM_SHA1` and the rest are src/pl-sha.jl's, numbered 0 to 4).
"hash_stream.c's `ALGORITHM_MD5`."
const HASH_ALGORITHM_MD5 = 0
"hash_stream.c's `ALGORITHM_SHA1`."
const HASH_ALGORITHM_SHA1 = 1
"hash_stream.c's `ALGORITHM_SHA224`."
const HASH_ALGORITHM_SHA224 = 2
"hash_stream.c's `ALGORITHM_SHA256`."
const HASH_ALGORITHM_SHA256 = 3
"hash_stream.c's `ALGORITHM_SHA384`."
const HASH_ALGORITHM_SHA384 = 4
"hash_stream.c's `ALGORITHM_SHA512`."
const HASH_ALGORITHM_SHA512 = 5

# PORT: packages/clib/hash_stream.c COPY_FLAGS
"The flags of the parent stream the hash stream copies (hash_stream.c)."
const HASH_COPY_FLAGS =
    SIO_INPUT | SIO_OUTPUT | SIO_TEXT | SIO_REPXML | SIO_REPPL | SIO_RECORDPOS

# PORT: packages/clib/hash_stream.c unify_digest
# DIVERGES: the digest is a byte vector and `len` its used length; the error is raised through `PL_error` (`PL_representation_error`).
"Unify `t` with the atom of the `len` lowercase hex pairs of `digest`; `representation_error(digest_length)` if that is over 256 characters (hash_stream.c)."
function hash_unify_digest(
    ld::PL_local_data{T}, t::term_t, digest::Vector{UInt8}, len::Int
)::Bool where {T}
    if len * 2 <= 256
        hexd = b"0123456789abcdef"
        hex = Vector{UInt8}(undef, len * 2)
        for di in 1:len
            hex[2di - 1] = hexd[((digest[di] >> 4) & 0x0f) + 1]
            hex[2di] = hexd[(digest[di] & 0x0f) + 1]
        end
        return PL_unify_atom(ld, t, _atom_from_text(T, String(hex)))   # PL_unify_atom_nchars(t, len*2, hex_output)
    end
    return PL_error(ld, ERR_REPRESENTATION, mk_sym(T, :digest_length))
end

# PORT: packages/clib/hash_stream.c hash_context
# DIVERGES: see the file header, 2 and 5 (`state` is the union's three types; `scratch` the buffer of 3; `ld` the close hook's).
"The context of a hash stream (hash_stream.c `hash_context`): the parent `stream`, the filter stream `hash_stream`, the parent's original encoding, the options, the state."
mutable struct HashContext{T} <: AbstractSfilter
    stream::IOSTREAM                                    # Original stream
    hash_stream::Union{Nothing, IOSTREAM}               # Stream I'm handle of
    parent_encoding::IOENC                              # original encoding
    close_parent::Bool                                  # close parent stream
    algorithm::Int
    digest_size::Int
    state::Union{md5_state_t, sha1_ctx, sha2_ctx}
    scratch::Vector{UInt8}
    ld::PL_local_data{T}
end

# PORT: packages/clib/hash_stream.c alloc_hash_context
# DIVERGES: `memset(ctx, 0, ...)`: algorithm MD5, no digest size, an MD5 state not yet begun (`md5_init`), and `ld` for the close hook.
"A zeroed context over the parent `s` (hash_stream.c)."
function alloc_hash_context(ld::PL_local_data{T}, s::IOSTREAM)::HashContext{T} where {T}
    return HashContext{T}(
        s, nothing, ENC_UNKNOWN, false, HASH_ALGORITHM_MD5, 0, md5_init(), UInt8[], ld
    )
end

# PORT: packages/clib/hash_stream.c free_hash_context
# DIVERGES: `PL_free(ctx)` is Julia's GC.
"Unlink the filter from its parent, if it still is (hash_stream.c)."
function free_hash_context(ctx::HashContext)::Nothing
    ctx.stream.upstream !== nothing && Sset_filter(ctx.stream, nothing)
    return nothing
end

# PORT: packages/clib/hash_stream.c hash_append
# DIVERGES: the states are three types, one method each; `data` is the byte vector and `size` its used length.
"Add the first `size` bytes of `data` to the hash (hash_stream.c)."
function hash_append(ctx::HashContext, data::Vector{UInt8}, size::Int)::Nothing
    return _hash_append(ctx.state, data, size)
end
_hash_append(st::md5_state_t, data::Vector{UInt8}, size::Int)::Nothing = md5_append(st, data, size)
_hash_append(st::sha1_ctx, data::Vector{UInt8}, size::Int)::Nothing = sha1_hash!(data, size, st)
_hash_append(st::sha2_ctx, data::Vector{UInt8}, size::Int)::Nothing = sha2_hash!(data, size, st)

# ORIGINAL: `hash_context copy = *ctx` (pl_stream_hash): a copy the finishing does not disturb. The states hold vectors, so each is copied.
"A copy of the state `st`, sharing nothing with it."
_hash_copy_state(st::md5_state_t)::md5_state_t = md5_state_t(copy(st.count), copy(st.abcd), copy(st.buf))
_hash_copy_state(st::sha1_ctx)::sha1_ctx = sha1_ctx(copy(st.count), copy(st.hash), copy(st.wbuf))
function _hash_copy_state(st::sha2_ctx)::sha2_ctx
    c256 = sha256_ctx(copy(st.ctx256.count), copy(st.ctx256.hash), copy(st.ctx256.wbuf))
    c512 = sha512_ctx(copy(st.ctx512.count), copy(st.ctx512.hash), copy(st.ctx512.wbuf))
    return sha2_ctx(st.sha2_len, c256, c512)
end

# ORIGINAL: the three `switch(copy.algorithm)` arms that finish a copy (md5_finish, sha1_end, sha2_end) of pl_stream_hash.
"The digest of the finished state `st` (hash_stream.c `pl_stream_hash`)."
_hash_finish!(st::md5_state_t)::Vector{UInt8} = md5_finish(st)
function _hash_finish!(st::sha1_ctx)::Vector{UInt8}
    hval = zeros(UInt8, SHA1_DIGEST_SIZE)
    sha1_end!(hval, st)
    return hval
end
_hash_finish!(st::sha2_ctx)::Vector{UInt8} = sha2_end!(st)

# PORT: packages/clib/hash_stream.c hash_read
# DIVERGES: see the file header, 3.
"Read from the parent into `mem` at `from`, hashing what was read: the count, 0 at end of file, -1 on error (hash_stream.c)."
function Sfilter_read(ctx::HashContext, mem::Vector{UInt8}, from::Int, size::Int)::Int
    length(ctx.scratch) < size && (ctx.scratch = Vector{UInt8}(undef, size))
    rd = Sfread(ctx.scratch, 1, size, ctx.stream)
    if rd >= 0
        hash_append(ctx, ctx.scratch, rd)
        rd > 0 && copyto!(mem, from, ctx.scratch, 1, rd)
        return rd
    end
    return rd
end

# PORT: packages/clib/hash_stream.c hash_write
# DIVERGES: see the file header, 3.
"Hash the `size` bytes of `mem` at `from` and write them to the parent: `size`, or -1 on error (hash_stream.c)."
function Sfilter_write(ctx::HashContext, mem::Vector{UInt8}, from::Int, size::Int)::Int
    length(ctx.scratch) < size && (ctx.scratch = Vector{UInt8}(undef, size))
    size > 0 && copyto!(ctx.scratch, 1, mem, from, size)
    hash_append(ctx, ctx.scratch, size)

    written = 0
    while written < size
        rest = written == 0 ? ctx.scratch : ctx.scratch[(written + 1):size]
        wr = Sfwrite(rest, 1, size - written, ctx.stream)
        if wr > 0
            written += wr
        else
            return -1
        end
    end
    return size
end

# PORT: packages/clib/hash_stream.c hash_control
# DIVERGES: see the file header, 4.
"Control: the encoding may be switched, everything else is the parent's (hash_stream.c)."
function Sfilter_control(ctx::HashContext, op::Int, arg)::Int
    op == SIO_SETENCODING && return 0                   # allow switching encoding
    rc = S_control(ctx.stream, op, arg)
    if rc == SCONTROL_NONE                              # !ctx->stream->functions->control
        return op == SIO_FLUSHOUTPUT ? 0 : -1
    end
    return rc
end

# PORT: packages/clib/hash_stream.c hash_close
# DIVERGES: see the file header, 5.
"Close the hash stream: restore the parent's encoding, unlink, close the parent if asked to (hash_stream.c)."
function Sfilter_close(ctx::HashContext)::Int
    rc = 0
    ctx.stream.encoding = ctx.parent_encoding
    ctx.stream.upstream !== nothing && Sset_filter(ctx.stream, nothing)

    if ctx.close_parent
        rc = Sclose(ctx.stream)
        freeStream(ctx.ld, ctx.stream)
    end

    free_hash_context(ctx)
    return rc
end

# PORT: packages/clib/hash_stream.c get_hash_algorithm
# DIVERGES: returns the algorithm, or `nothing` with the error raised.
"The algorithm the atom `t` names: `type_error` if no atom, `domain_error(algorithm, T)` if none of the six (hash_stream.c)."
function get_hash_algorithm(ld::PL_local_data{T}, t::term_t)::Union{Nothing, Int} where {T}
    a = PL_get_atom_ex(ld, t)
    a === nothing && return nothing
    k = sym_key(a)
    k == sym_key(mk_sym(T, :md5)) && return HASH_ALGORITHM_MD5
    k == sym_key(mk_sym(T, :sha1)) && return HASH_ALGORITHM_SHA1
    k == sym_key(mk_sym(T, :sha224)) && return HASH_ALGORITHM_SHA224
    k == sym_key(mk_sym(T, :sha256)) && return HASH_ALGORITHM_SHA256
    k == sym_key(mk_sym(T, :sha384)) && return HASH_ALGORITHM_SHA384
    k == sym_key(mk_sym(T, :sha512)) && return HASH_ALGORITHM_SHA512
    PL_domain_error(ld, "algorithm", t)
    return nothing
end

# PORT: packages/clib/hash_stream.c digest_size
# DIVERGES: an unknown algorithm answers 0 (upstream: `assert(0)`).
"The digest size of `algorithm` in bytes (hash_stream.c)."
function hash_digest_size(algorithm::Int)::Int
    algorithm == HASH_ALGORITHM_MD5 && return 16
    algorithm == HASH_ALGORITHM_SHA1 && return SHA1_DIGEST_SIZE
    algorithm == HASH_ALGORITHM_SHA224 && return SHA224_DIGEST_SIZE
    algorithm == HASH_ALGORITHM_SHA256 && return SHA256_DIGEST_SIZE
    algorithm == HASH_ALGORITHM_SHA384 && return SHA384_DIGEST_SIZE
    algorithm == HASH_ALGORITHM_SHA512 && return SHA512_DIGEST_SIZE
    return 0
end

# PORT: packages/clib/hash_stream.c hash_stream_options
# (PL_OPTION("algorithm", OPT_TERM), PL_OPTION("close_parent", OPT_BOOL))
const hash_stream_option_specs =
    (PL_option_t(:algorithm, OPT_TERM), PL_option_t(:close_parent, OPT_BOOL))

# PORT: packages/clib/hash_stream.c pl_stream_hash_open
# DIVERGES: see the file header, 3 to 6; the "no memory" exit is gone; `PL_get_stream_handle` is `term_stream_handle(SH_ERRORS|SH_ALIAS)`.
"`open_hash_stream(+OrgStream, -HashStream, +Options)`: a filter stream on OrgStream that maintains a hash (hash_stream.c)."
function pl_open_hash_stream3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2, A3 = PL__t0, PL__t0 + 1, PL__t0 + 2
    vals = PL_scan_options(ld, A3, 0, "hash_option", hash_stream_option_specs)
    vals === nothing && return FFALSE
    alg = vals[1]
    cp = vals[2]
    close_parent = cp isa Bool ? cp : true
    algorithm = HASH_ALGORITHM_SHA1
    if alg isa Int
        a = get_hash_algorithm(ld, alg)
        a === nothing && return FFALSE
        algorithm = a
    end

    s = term_stream_handle(ld, A1, SH_ERRORS | SH_ALIAS)
    s === nothing && return FFALSE                      # Error

    ctx = alloc_hash_context(ld, s)
    ctx.close_parent = close_parent
    ctx.algorithm = algorithm
    ctx.digest_size = hash_digest_size(algorithm)

    if algorithm == HASH_ALGORITHM_MD5
        ctx.state = md5_init()
    elseif algorithm == HASH_ALGORITHM_SHA1
        st = sha1_ctx()
        sha1_begin!(st)
        ctx.state = st
    else
        ctx.state = sha2_begin(ctx.digest_size)::sha2_ctx
    end

    s2 = Snew(ctx, (s.flags & HASH_COPY_FLAGS) | SIO_FBUF, Sfilterfunctions)
    s2.encoding = s.encoding
    ctx.parent_encoding = s.encoding
    s.encoding = ENC_OCTET
    ctx.hash_stream = s2
    if PL_unify_stream(ld, A2, s2)
        Sset_filter(s, s2)
        PL_release_stream(ld, s)
        return FTRUE
    end

    ctx.close_parent = false                            # restores s and frees ctx
    Sclose(s2)
    freeStream(ld, s2)
    PL_release_stream(ld, s)
    PL_error(ld, "", 0, "", ERR_UNINSTANTIATION, 0, A2)  # PL_uninstantiation_error(new)
    return FFALSE
end

# PORT: packages/clib/hash_stream.c pl_stream_hash
# DIVERGES: see the file header, 2; `ctx` is read after the `hash_stream` check (upstream reads `s->handle` first, unused until then).
"`stream_hash(+HashStream, -Hash)`: Hash is the hash of the bytes sent to or read from HashStream so far (hash_stream.c)."
function pl_stream_hash2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    s = term_stream_handle(ld, A1, SH_ERRORS | SH_ALIAS)
    s === nothing && return FFALSE

    if Sferror(s) != 0 || ((s.flags & SIO_OUTPUT) != 0 && Sflush(s) < 0)
        PL_release_stream(ld, s)                        # raises the error if any
        return FFALSE
    end

    f = s.filter
    ctx = f === nothing ? nothing : f[]
    if s.functions != Sfilterfunctions || !(ctx isa HashContext{T})
        PL_release_stream(ld, s)
        PL_domain_error(ld, "hash_stream", A1)
        return FFALSE
    end

    st = _hash_copy_state(ctx.state)                    # finish a copy: keep going
    hval = _hash_finish!(st)
    rc = hash_unify_digest(ld, A2, hval, ctx.digest_size)

    PL_release_stream(ld, s)
    return rc ? FTRUE : FFALSE
end

# PORT: packages/clib/hash_stream.c install_hashstream
# DIVERGES: see the file header, 1.
"The install function of the static extension `hashstream` (hash_stream.c `install_hashstream`): the predicates exist already."
function install_hashstream(ld::PL_local_data{T})::Nothing where {T}
    return nothing
end

# PORT: packages/clib/hash_stream.c install_hashstream as PL_predicates_from_hashstream
# DIVERGES: see the file header, 1.
const PL_predicates_from_hashstream = (
    PL_extension("open_hash_stream", 3, pl_open_hash_stream3_va, PL_FA_VARARGS),
    PL_extension("stream_hash", 2, pl_stream_hash2_va, PL_FA_VARARGS),
)
