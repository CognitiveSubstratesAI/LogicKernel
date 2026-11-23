# ORIGINAL: HASH1's gate - open_hash_stream/3 and stream_hash/2 of packages/clib (hash_stream.c), called at the Julia level on term references and
# on streams the test builds (memory streams, test filter records as parents). NOT a differential run: the expected digests are hashlib's
# (a second implementation, tabled below from one script; the 24 rows empty/abc/k1000/abcdef x six algorithms were compared with the pinned
# swipl's own `open_hash_stream`+`stream_hash` over a file when the file was written, ~/.local/swipl-pin1-18168e62/bin/swipl, zero differences),
# and the error formals, the input-buffer rule and the encoding rows are what that swipl answered (measured 2026-11-22; a row's comment names it).
# BLIND-CODED: no Julia process ran when this file was written: a row whose value rests on what the kernel's stream layer does (not on
# hash_stream.c) is a real `@test` with the C-derived expectation, so a wrong guess FAILS on the lane, which is the point.
# NOT ROWS (named): the OUTPUT null stream (swipl answers stream_hash with Hash left unbound there; the kernel has no `open_null_stream`), a second hash
# stream on a parent that has one (an assertion upstream and here), open_hash_stream on a standard stream (DIVERGES 5 of src/pl-hashstream.jl).
# KERNEL-ONLY: the whole file (no swipl run), the Julia-level calls of the callbacks (`Sfilter_read`, ...), the record and state-copy rows.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE - built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TL = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})

_ctx(::LK.PL_local_data{T}) where {T} =
    LK.foreign_context{T}(LK.FRG_FIRST_CALL, UInt(0), nothing)

# a fresh database and local data with an open foreign frame (the term references live in it)
function _env(::Type{T}) where {T}
    gd = LK.PL_global_data{T}()
    ld = LK.PL_local_data{T}(gd)
    LK.PL_open_foreign_frame(ld)
    return gd, ld
end

# ---------------------------------------------------------------------------------------------------------------------
# the digests: hashlib over these messages, lowercase hex (one script wrote the table)
const _ALGS = (:md5, :sha1, :sha224, :sha256, :sha384, :sha512)
_msg(i) = UInt8[(k % 251) % UInt8 for k in 0:(i - 1)]
const _MSGS = Dict{Symbol, Vector{UInt8}}(
    :empty => UInt8[],
    :abc => Vector{UInt8}(codeunits("abc")),
    :abcdef => Vector{UInt8}(codeunits("abcdef")),
    :k1000 => _msg(1000),
    :big => _msg(10000),                          # larger than the 4096-byte buffer of a stream
    :big4096 => _msg(4096),                       # the first 4096 bytes of :big
    :utf8 => Vector{UInt8}(codeunits("héllo")),   # "héllo" in UTF-8
    :l1 => UInt8[0x68, 0xe9, 0x6c, 0x6c, 0x6f]   # "héllo" in ISO Latin-1
)
const _WANT = Dict{Tuple{Symbol, Symbol}, String}(
    (:md5, :empty) => "d41d8cd98f00b204e9800998ecf8427e",
    (:sha1, :empty) => "da39a3ee5e6b4b0d3255bfef95601890afd80709",
    (:sha224, :empty) => "d14a028c2a3a2bc9476102bb288234c415a2b01f828ea62ac5b3e42f",
    (:sha256, :empty) => "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
    (:sha384, :empty) => "38b060a751ac96384cd9327eb1b1e36a21fdb71114be07434c0cc7bf63f6e1da274edebfe76f65fbd51ad2f14898b95b",
    (:sha512, :empty) => "cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e",
    (:md5, :abc) => "900150983cd24fb0d6963f7d28e17f72",
    (:sha1, :abc) => "a9993e364706816aba3e25717850c26c9cd0d89d",
    (:sha224, :abc) => "23097d223405d8228642a477bda255b32aadbce4bda0b3f7e36c9da7",
    (:sha256, :abc) => "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
    (:sha384, :abc) => "cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed8086072ba1e7cc2358baeca134c825a7",
    (:sha512, :abc) => "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f",
    (:md5, :k1000) => "a24f1e3ef66950e1327f210e3997ba2c",
    (:sha1, :k1000) => "c9c960a0b925474fab83942cc27d504fc24ac37b",
    (:sha224, :k1000) => "c182669a7f6629dc7fd8a9198f15af15adbbaeffa1842e854f681357",
    (:sha256, :k1000) => "4e4c294b331f7a2099a379bec34b9f9fc03dc46ab465d998f4d683da53487e6d",
    (:sha384, :k1000) => "7a2f8c7f12344964a13cb9260492b845e56615d6152b9eb9e54b580fc88405e64f31813bfda10de2a642fdf1676c61b4",
    (:sha512, :k1000) => "5096498d96f50f9a137c4db5b8b0cd38383ad55350fb5a98805fedc31fa1262f1f0cf4d6f12d7ecd8dedd933a4c9126344fe22e937a8ad35fdeae1e876ae698b",
    (:md5, :big) => "bbf1c77538f97ceeb1e03126edaa3594",
    (:sha1, :big) => "29522e73f5c67d3fff39d936ae0bb542db8b05b5",
    (:sha224, :big) => "e66ae0c277b9fb56b12223e8d5a25dd09c78306c4a073bd40f8e4011",
    (:sha256, :big) => "0cd0bf930677960951dda8588edcb6b293c0c3b26ef3ba72cddff4ddfc6822c7",
    (:sha384, :big) => "f20a95eb4de9c1c649ea387c6776d6ba4b822fcfdb4817504d045259f3cdf640b428076fcc6a9c1c388a5d514fcdcf8c",
    (:sha512, :big) => "1955f861bfd6ef7372f9bf29e54ebf7525114fbcc053b34973f37bd769414c952dc018a68b2c2f0e4af6eccc9996b930cba2894209b06d059302c211a7c22c9c",
    (:md5, :big4096) => "a0c16616c91907bd14e999986cf822d5",
    (:sha1, :big4096) => "92ca8f2b4163e64a1b53e0fde263ad56cbdb75fc",
    (:sha224, :big4096) => "5a6266582cdb93dda2d15119daab4b92702b5a720f45cd508f606d6b",
    (:sha256, :big4096) => "d67c656e01756650d77717b0839985a056ec28ffe174601d690fc407a2ceffca",
    (:sha384, :big4096) => "16ba747d8ef390d8476da05fc7b046e61205cd65ce0d63e11c270d9a289aa3e863caa5c7548cafa3bbbf0af80420b125",
    (:sha512, :big4096) => "3b5e033c335c4a168b9b370c752db690ede9cc918abb9a2d18736536c83908ddd4be0bef9018c9fc2b4700befa1d91bf12cee544e0c06cdcea822bf2ebdf36a2",
    (:md5, :abcdef) => "e80b5017098950fc58aad83c8c14978e",
    (:sha1, :abcdef) => "1f8ac10f23c5b5bc1167bda84b833e5c057a77d2",
    (:sha224, :abcdef) => "7043631cb415556a275a4ebecb802c74ee9f6153908e1792a90b6a98",
    (:sha256, :abcdef) => "bef57ec7f53a6d40beb640a780a639c83bc29ac8a9816f1fc6c5c6dcd93c4721",
    (:sha384, :abcdef) => "c6a4c65b227e7387b9c3e839d44869c4cfca3ef583dea64117859b808c1e3d8ae689e1e314eeef52a6ffe22681aa11f5",
    (:sha512, :abcdef) => "e32ef19623e8ed9d267f657a81944b3d07adbb768518068e88435745564e8d4150a0a703be2a7d88b61e3d390c2bb97e2d4c311fdc69d6b1267f05f59aa920e7",
    (:md5, :utf8) => "be50e8478cf24ff3595bc7307fb91b50",
    (:sha1, :utf8) => "35b5ea45c5e41f78b46a937cc74d41dfea920890",
    (:sha224, :utf8) => "2ed034dbfd665018cad24af1a17b76de85cbd9bf3040d702023ce9ec",
    (:sha256, :utf8) => "3c48591d8d098a4538f5e013dfcf406e948eac4d3277b10bf614e295d6068179",
    (:sha384, :utf8) => "19d752a0be2905196c631f6a82a3169a58b1d850f2773d88702d8ca77dcdd25cfed091bc38c38b7efff287514831f61a",
    (:sha512, :utf8) => "a67e831011aa41ebb2a218c8ff727f1c60d62f06e1681678d176a81cd72ee69e7250c4c943cacbab28e42768615a5c41b6b0d42591d2c26a65670b38e97306dc",
    (:md5, :l1) => "1a722f7e6c801d9e470a10cb91ba406d",
    (:sha1, :l1) => "028db752c14604d624e8b1c121d600c427b8a3ba",
    (:sha224, :l1) => "2df38f5d9938c14b688ae389d8e23279c4bc973c39cf10fd31152c04",
    (:sha256, :l1) => "c63c19ed1e0ee079f22ddb0d4112cfc799132c88684eb42324c62b9899b0c6c1",
    (:sha384, :l1) => "695d72825a5456b8d7234a6906611c6c5ec7778d747096ba42e58e251c7ce19a73b355b3f1052845a8cff5455fe2ae8f",
    (:sha512, :l1) => "627fe30aea9a0f56ed6e08769712f15324aa94e5cdee0eac578da9ad3fe48ed8607503eca885f3e2017a0a1059c67d26dbb7a98dde62ac2a450fb69dc45d875a"
)

# ---------------------------------------------------------------------------------------------------------------------
# argument kinds and the term-building helpers (the term type comes from the local data)
struct Str
    text::String
end

_put_val!(ld, t::Int, ::Nothing) = true
_put_val!(ld::LK.PL_local_data{T}, t::Int, x::Symbol) where {T} =
    LK.PL_put_atom(ld, t, lk_sym(T, x))
_put_val!(ld, t::Int, x::Integer) = LK.PL_put_int64(ld, t, Int(x))
_put_val!(ld::LK.PL_local_data{T}, t::Int, x::Str) where {T} =
    LK.PL_unify_atomic(ld, t, lk_gnd(T, x.text))

_new1(ld) = LK.PL_new_term_refs(ld, 1)
function _atomref(ld, x)::Int
    t = _new1(ld)
    _put_val!(ld, t, x) || error("_put_val!")
    return t
end

# an option list: `name => value` is `name(value)`, a bare symbol is the atom; built with PL_cons_functor/PL_cons_list from the end
function _opts(ld, items...)::Int
    l = _new1(ld)
    LK.PL_put_nil(ld, l)
    for it in reverse(items)
        h = _new1(ld)
        if it isa Pair
            v = _new1(ld)
            _put_val!(ld, v, it.second) || error("_put_val!")
            LK.PL_cons_functor(ld, h, LK._err_functor(ld, it.first, 1), v)
        else
            _put_val!(ld, h, it) || error("_put_val!")
        end
        l2 = _new1(ld)
        LK.PL_cons_list(ld, l2, h, l)
        l = l2
    end
    return l
end

# the stream helpers of test/files/test_stream_filter_swipl.jl
_sf_in(bytes::Vector{UInt8}) =
    LK.Sopenmem(Ref{Union{Nothing, Vector{UInt8}}}(copy(bytes)), Ref(length(bytes)), "r")
function _sf_out()
    bufp = Ref{Union{Nothing, Vector{UInt8}}}(nothing)
    sizep = Ref(0)
    return LK.Sopenmem(bufp, sizep, "w"), bufp, sizep
end
_sf_bytes(bufp, sizep) = sizep[] == 0 ? UInt8[] : copy(bufp[][1:sizep[]])

# filter records the parents and the foreign stream of the rows are made of
"A parent whose write callback is the default: it fails (-1)."
struct FailSink <: LK.AbstractSfilter end
"A parent with a control function of its own: SIO_GETSIZE answers `size`, SIO_FLUSHOUTPUT 7, SIO_SETENCODING -1 (the hash stream must not ask it)."
mutable struct CtlParent <: LK.AbstractSfilter
    size::Int
    log::Vector{String}
end
LK.Sfilter_write(h::CtlParent, mem::Vector{UInt8}, from::Int, size::Int)::Int = size
function LK.Sfilter_control(h::CtlParent, op::Int, arg)::Int
    push!(h.log, "control$op")
    if op == LK.SIO_GETSIZE
        arg[] = h.size
        return 0
    elseif op == LK.SIO_FLUSHOUTPUT
        return 7
    elseif op == LK.SIO_SETENCODING
        return -1
    end
    return LK.SCONTROL_NONE
end
"A filter record that is no hash context."
struct OtherRec <: LK.AbstractSfilter end

# open_hash_stream(Parent, Hash, Options) on fresh term references: `parent` is an IOSTREAM, a symbol, an integer or `nothing` (unbound); `second`
# is what the hash argument holds before the call
function _open(ld, parent, opts::Int; second=nothing)
    t = LK.PL_new_term_refs(ld, 3)
    if parent isa LK.IOSTREAM
        LK.PL_unify_stream(ld, t, parent) || error("PL_unify_stream")
    else
        _put_val!(ld, t, parent) || error("_put_val!")
    end
    _put_val!(ld, t + 1, second) || error("_put_val!")
    LK.PL_put_term(ld, t + 2, opts)
    rc = LK.pl_open_hash_stream3_va(ld, t, 3, _ctx(ld))
    return rc, t
end
# the hash stream of a call that must succeed, and the term reference that holds its blob
function _hash_open(ld, parent::LK.IOSTREAM, items...)
    rc, t = _open(ld, parent, _opts(ld, items...))
    rc == LK.FTRUE || error("open_hash_stream failed")
    hs = LK.term_stream_handle(ld, t + 1, LK.SH_ERRORS | LK.SH_ALIAS)
    hs isa LK.IOSTREAM || error("no hash stream")
    return hs, t + 1
end
# stream_hash(Stream, Hash) on the stream the term reference `ts` holds; `out` is what Hash holds before the call
function _stream_hash(ld, ts::Int; out=nothing)
    t = LK.PL_new_term_refs(ld, 2)
    LK.PL_put_term(ld, t, ts)
    _put_val!(ld, t + 1, out) || error("_put_val!")
    rc = LK.pl_stream_hash2_va(ld, t, 2, _ctx(ld))
    exc = _exc(ld)
    hash = nothing
    if rc == LK.FTRUE
        a = lk_answer(ld, t + 1)
        hash = kind(a) === SYM ? sym_text(a) : nothing
    end
    return (rc=rc, hash=hash, exc=exc)
end

_exc(ld)::Bool = LK.PL_exception(ld, 0) != 0
_exc_term(ld) = lk_answer(ld, LK.PL_exception(ld, 0))
# the functor name of the formal of the pending error(Formal, _)
function _exc_formal(ld)::String
    f = child(_exc_term(ld), 2)
    return sym_text(kind(f) === SYM ? f : child(f, 1))
end
# the first and second argument of the formal as text (an argument that is no symbol is "")
function _exc_args(ld)::Tuple{String, String}
    f = child(_exc_term(ld), 2)
    kind(f) === SYM && return ("", "")
    a = child(f, 2)
    b = nchildren(f) >= 3 ? child(f, 3) : nothing
    txt(x) =
        if x === nothing
            ""
        elseif kind(x) === SYM
            sym_text(x)
        else
            ""
        end
    return (txt(a), txt(b))
end
# argument `i` of the formal, as a term
_exc_arg(ld, i::Int) = child(child(_exc_term(ld), 2), i + 1)

# bytes through Sfwrite, `chunk` at a time
function _write(s::LK.IOSTREAM, bytes::Vector{UInt8}; chunk::Int=max(length(bytes), 1))
    p = 0
    n = length(bytes)
    while p < n
        c = min(chunk, n - p)
        LK.Sfwrite(bytes[(p + 1):(p + c)], 1, c, s) == c || error("Sfwrite")
        p += c
    end
    return nothing
end

# the streams the database's table holds, not counting the three standard streams
_live(gd, ld) = count(
    s ->
        s !== nothing &&
        !any(x -> x === s, ld.IO_streams[(LK.SNO_USER_INPUT + 1):(LK.SNO_USER_ERROR + 1)]),
    gd.stream_table
)

# the core on a byte vector, the digest as lowercase hex (md5.c, sha1.c, sha2.c at the Julia level), in the pieces `chunks`
_hex(d::Vector{UInt8}) = join(string(b; base=16, pad=2) for b in d)
const _DSIZE = Dict(
    :md5 => 16, :sha1 => 20, :sha224 => 28, :sha256 => 32, :sha384 => 48, :sha512 => 64
)
function _core(alg::Symbol, data::Vector{UInt8}; chunks=[length(data)])
    pieces = Vector{Vector{UInt8}}()
    p = 0
    for c in chunks
        push!(pieces, data[(p + 1):(p + c)])
        p += c
    end
    @assert p == length(data)
    if alg === :md5
        st = LK.md5_init()
        for pc in pieces
            LK.md5_append(st, pc, length(pc))
        end
        return _hex(LK.md5_finish(st))
    elseif alg === :sha1
        st = LK.sha1_ctx()
        LK.sha1_begin!(st)
        for pc in pieces
            LK.sha1_hash!(pc, length(pc), st)
        end
        d = zeros(UInt8, LK.SHA1_DIGEST_SIZE)
        LK.sha1_end!(d, st)
        return _hex(d)
    end
    st = LK.sha2_begin(_DSIZE[alg])
    for pc in pieces
        LK.sha2_hash!(pc, length(pc), st)
    end
    return _hex(LK.sha2_end!(st))
end

# ---------------------------------------------------------------------------------------------------------------------
@testset "h00 the table: the core, at the Julia level, gives the rows' digests" begin
    for alg in _ALGS, m in keys(_MSGS)
        data = _MSGS[m]
        @test _core(alg, data) == _WANT[(alg, m)]
        if length(data) > 2
            @test _core(alg, data; chunks=[1, length(data) - 1]) == _WANT[(alg, m)]
        end
    end
    # MUST-FAIL arm: the comparison reports a wrong digest
    @test _core(:md5, _MSGS[:abc]) != _WANT[(:md5, :empty)]
    @test length(_WANT) == 48
end

# h01: written through the hash stream, the digest is the table's, whether the bytes go in one write or 7 at a time, over the buffer's 4096 or not;
# stream_hash/2 flushes first; the parent receives the bytes unchanged
@testset "h01 write: the digest of the bytes sent" begin
    gd, ld = _env(_TL)
    for alg in _ALGS, m in (:empty, :abc, :k1000, :abcdef, :big), chunk in (0, 7)
        bytes = _MSGS[m]
        parent, bufp, sizep = _sf_out()
        hs, ts = _hash_open(ld, parent, :algorithm => alg)
        chunk == 0 ? _write(hs, bytes) : _write(hs, bytes; chunk=chunk)
        r = _stream_hash(ld, ts)
        @test r.rc == LK.FTRUE && !r.exc && r.hash == _WANT[(alg, m)]
        @test LK.closeStream(ld, hs)
        @test _sf_bytes(bufp, sizep) == bytes
    end
    # no algorithm option: SHA-1
    parent, bufp, sizep = _sf_out()
    hs, ts = _hash_open(ld, parent)
    _write(hs, _MSGS[:abc])
    r = _stream_hash(ld, ts)
    @test r.rc == LK.FTRUE && r.hash == _WANT[(:sha1, :abc)]
    @test LK.closeStream(ld, hs)
end

# h02: text written with Sputcode goes into the filter's buffer in the PARENT'S ORIGINAL encoding (the filter copies it, the parent is forced to octet)
@testset "h02 write: text in the parent's original encoding" begin
    gd, ld = _env(_TL)
    for alg in _ALGS, (enc, key) in ((LK.ENC_UTF8, :utf8), (LK.ENC_ISO_LATIN_1, :l1))
        parent, bufp, sizep = _sf_out()
        parent.encoding = enc
        hs, ts = _hash_open(ld, parent, :algorithm => alg)
        @test hs.encoding == enc && parent.encoding == LK.ENC_OCTET
        for c in "héllo"
            @test LK.Sputcode(Int(c), hs) >= 0
        end
        r = _stream_hash(ld, ts)
        @test r.rc == LK.FTRUE && r.hash == _WANT[(alg, key)]
        @test LK.closeStream(ld, hs)
        @test _sf_bytes(bufp, sizep) == _MSGS[key]
    end
end

# h03: read through the hash stream, the digest is of what was READ from the parent, buffered bytes included; before any read it is the digest of "";
# the first read fills the buffer: 1 byte read of 10000 hashes the first 4096 (swipl 10.1.20: sha256 d67c656e...ceffca)
@testset "h03 read: the digest of what the parent gave" begin
    gd, ld = _env(_TL)
    for alg in _ALGS, m in (:empty, :abc, :abcdef, :k1000, :big)
        bytes = _MSGS[m]
        n = length(bytes)
        hs, ts = _hash_open(ld, _sf_in(bytes), :algorithm => alg)
        r0 = _stream_hash(ld, ts)
        @test r0.rc == LK.FTRUE && r0.hash == _WANT[(alg, :empty)]            # before any read
        buf = zeros(UInt8, n + 5)
        @test LK.Sfread(buf, 1, n + 5, hs) == n
        @test buf[1:n] == bytes
        r = _stream_hash(ld, ts)
        @test r.rc == LK.FTRUE && !r.exc && r.hash == _WANT[(alg, m)]
        @test LK.closeStream(ld, hs)
    end
    for alg in _ALGS
        hs, ts = _hash_open(ld, _sf_in(_MSGS[:big]), :algorithm => alg)
        one = zeros(UInt8, 1)
        @test LK.Sfread(one, 1, 1, hs) == 1 && one[1] == _MSGS[:big][1]
        r = _stream_hash(ld, ts)
        @test r.rc == LK.FTRUE && r.hash == _WANT[(alg, :big4096)]            # the buffer fill, not the byte read
        rest = zeros(UInt8, 10000)
        @test LK.Sfread(rest, 1, 10000, hs) == 9999
        r = _stream_hash(ld, ts)
        @test r.hash == _WANT[(alg, :big)]
        @test LK.closeStream(ld, hs)
    end
end

# h04: the state copy: stream_hash/2 finishes a COPY, the stream goes on
@testset "h04 stream_hash mid-stream keeps going; the copy shares nothing" begin
    gd, ld = _env(_TL)
    fields(st::LK.md5_state_t) = (st.count, st.abcd, st.buf)
    fields(st::LK.sha1_ctx) = (st.count, st.hash, st.wbuf)
    fields(st::LK.sha2_ctx) =
        (
            st.ctx256.count,
            st.ctx256.hash,
            st.ctx256.wbuf,
            st.ctx512.count,
            st.ctx512.hash,
            st.ctx512.wbuf
        )
    for alg in _ALGS
        parent, bufp, sizep = _sf_out()
        hs, ts = _hash_open(ld, parent, :algorithm => alg)
        _write(hs, _MSGS[:abc])
        r1 = _stream_hash(ld, ts)
        @test r1.hash == _WANT[(alg, :abc)]
        _write(hs, Vector{UInt8}(codeunits("def")))
        r2 = _stream_hash(ld, ts)
        @test r2.hash == _WANT[(alg, :abcdef)] && r2.hash != r1.hash
        r3 = _stream_hash(ld, ts)
        @test r3.hash == r2.hash                                              # asking changes nothing
        ctx = hs.filter[]
        st = ctx.state
        c = LK._hash_copy_state(st)
        @test c !== st && typeof(c) === typeof(st)
        for (a, b) in zip(fields(c), fields(st))
            @test a !== b && a == b                                           # equal values, no shared vector
        end
        before = LK._hash_finish!(LK._hash_copy_state(st))
        LK._hash_append(c, UInt8[1, 2, 3], 3)
        after = LK._hash_finish!(LK._hash_copy_state(st))
        @test before == after                                                 # appending to the copy leaves the stream's state
        @test _hex(before) == _WANT[(alg, :abcdef)]
        @test _hex(LK._hash_finish!(c)) != _WANT[(alg, :abcdef)]
        @test LK.closeStream(ld, hs)
    end
end

# h05: hash_append: the first `size` bytes of the vector, for each state type
@testset "h05 hash_append takes the first size bytes" begin
    gd, ld = _env(_TL)
    for alg in _ALGS, m in (:empty, :abc, :k1000)
        bytes = _MSGS[m]
        parent, _, _ = _sf_out()
        hs, ts = _hash_open(ld, parent, :algorithm => alg, :close_parent => :false)
        ctx = hs.filter[]
        LK.hash_append(ctx, vcat(bytes, UInt8[0xff, 0xff]), length(bytes))
        r = _stream_hash(ld, ts)
        @test r.rc == LK.FTRUE && r.hash == _WANT[(alg, m)]
        @test LK.closeStream(ld, hs)
        @test LK.Sclose(parent) == 0
    end
end

# h06: the record, the flags and the encodings while the filter is on; the close protocol (hash_stream.c hash_close)
@testset "h06 close: the parent is closed by default" begin
    gd, ld = _env(_TL)
    parent, bufp, sizep = _sf_out()
    parent.encoding = LK.ENC_ISO_LATIN_1
    hs, ts = _hash_open(ld, parent, :algorithm => :md5)
    ctx = hs.filter[]
    @test ctx isa LK.HashContext
    @test ctx.stream === parent && ctx.hash_stream === hs
    @test ctx.algorithm == 0 && ctx.digest_size == 16 && ctx.close_parent === true
    @test ctx.parent_encoding == LK.ENC_ISO_LATIN_1
    @test parent.encoding == LK.ENC_OCTET && hs.encoding == LK.ENC_ISO_LATIN_1
    @test parent.upstream === hs && hs.downstream === parent
    @test parent.context != 0 && hs.context != 0
    _write(hs, _MSGS[:abc])
    @test LK.closeStream(ld, hs)
    @test parent.magic == LK.SIO_CMAGIC && hs.magic == LK.SIO_CMAGIC
    @test gd.stream_table[parent.context] === nothing &&
        gd.stream_table[hs.context] === nothing
    @test _sf_bytes(bufp, sizep) == _MSGS[:abc]
    # the bare option close_parent is true
    parent, bufp, sizep = _sf_out()
    hs, ts = _hash_open(ld, parent, :close_parent)
    @test hs.filter[].close_parent === true
    @test LK.closeStream(ld, hs)
    @test parent.magic == LK.SIO_CMAGIC
    # close_parent(true) written out
    parent, bufp, sizep = _sf_out()
    hs, ts = _hash_open(ld, parent, :close_parent => :true)
    @test LK.closeStream(ld, hs)
    @test parent.magic == LK.SIO_CMAGIC
end

@testset "h07 close_parent(false): the parent stays open, unlinked, with its encoding back" begin
    gd, ld = _env(_TL)
    parent, bufp, sizep = _sf_out()
    parent.encoding = LK.ENC_ISO_LATIN_1
    hs, ts = _hash_open(ld, parent, :algorithm => :sha256, :close_parent => :false)
    ctx = hs.filter[]
    @test ctx.close_parent === false && ctx.algorithm == 3 && ctx.digest_size == 32
    @test parent.encoding == LK.ENC_OCTET
    _write(hs, _MSGS[:abc])
    @test LK.closeStream(ld, hs)
    @test hs.magic == LK.SIO_CMAGIC && gd.stream_table[hs.context] === nothing
    @test parent.magic == LK.SIO_MAGIC
    @test parent.upstream === nothing && hs.downstream === nothing
    @test parent.encoding == LK.ENC_ISO_LATIN_1                               # the original one, not the default
    @test gd.stream_table[parent.context] === parent
    @test LK.Sfwrite(UInt8[0x7a], 1, 1, parent) == 1                           # still a working stream
    @test LK.Sclose(parent) == 0
    @test _sf_bytes(bufp, sizep) == vcat(_MSGS[:abc], UInt8[0x7a])
    # an input parent: the same, and it reads on after the filter
    parent = _sf_in(_MSGS[:abcdef])
    parent.encoding = LK.ENC_ISO_LATIN_1
    hs, ts = _hash_open(ld, parent, :close_parent => :false)
    buf = zeros(UInt8, 6)
    @test LK.Sfread(buf, 1, 6, hs) == 6 && buf == _MSGS[:abcdef]
    @test LK.closeStream(ld, hs)
    @test parent.magic == LK.SIO_MAGIC && parent.upstream === nothing &&
        parent.encoding == LK.ENC_ISO_LATIN_1
    @test LK.Sclose(parent) == 0
end

# h08: the flags of the filter are the parent's direction, text, representation and position flags, plus SIO_FBUF
@testset "h08 the filter's flags" begin
    gd, ld = _env(_TL)
    copy_flags =
        LK.SIO_INPUT | LK.SIO_OUTPUT | LK.SIO_TEXT | LK.SIO_REPXML | LK.SIO_REPPL |
        LK.SIO_RECORDPOS
    @test LK.HASH_COPY_FLAGS == copy_flags
    parent = _sf_in(_MSGS[:abc])
    hs, _ = _hash_open(ld, parent, :close_parent => :false)
    @test (hs.flags & copy_flags) == (parent.flags & copy_flags)
    @test (hs.flags & LK.SIO_INPUT) != 0 && (hs.flags & LK.SIO_OUTPUT) == 0
    @test (hs.flags & LK.SIO_TEXT) != 0 && (hs.flags & LK.SIO_RECORDPOS) != 0 &&
        hs.position !== nothing
    @test (hs.flags & LK.SIO_FBUF) != 0
    @test LK.closeStream(ld, hs)
    parent, _, _ = _sf_out()
    parent.flags |= LK.SIO_REPXML | LK.SIO_REPPL
    hs, _ = _hash_open(ld, parent, :close_parent => :false)
    @test (hs.flags & copy_flags) == (parent.flags & copy_flags)
    @test (hs.flags & LK.SIO_OUTPUT) != 0 && (hs.flags & LK.SIO_INPUT) == 0
    @test (hs.flags & LK.SIO_REPXML) != 0 && (hs.flags & LK.SIO_REPPL) != 0
    @test (hs.flags & LK.SIO_FBUF) != 0
    @test LK.closeStream(ld, hs)
    @test LK.Sclose(parent) == 0
end

# h09: the option errors, as swipl 10.1.20 answers them (the formal and its first argument; the algorithm is checked BEFORE the stream)
@testset "h09 open_hash_stream: the errors" begin
    function case(items...; first=:mem, second=nothing, raw=nothing)
        gd, ld = _env(_TL)
        parent, _, _ = _sf_out()
        opts = raw === nothing ? _opts(ld, items...) : _atomref(ld, raw)
        rc, t = _open(ld, first === :mem ? parent : first, opts; second=second)
        exc = _exc(ld)
        return (
            rc=rc, exc=exc, formal=exc ? _exc_formal(ld) : "",
            args=exc ? _exc_args(ld) : ("", ""),
            ld=ld, parent=parent
        )
    end
    rows = (
        ((:algorithm => :foo,), (;), "domain_error", "algorithm", "foo"),
        ((:algorithm => 1,), (;), "type_error", "atom", ""),
        ((:algorithm => nothing,), (;), "instantiation_error", "", ""),
        ((:algorithm => Str("md5"),), (;), "type_error", "atom", ""),
        ((:close_parent => :maybe,), (;), "type_error", "bool", "maybe"),
        ((:algorithm => :foo,), (first=nothing,), "domain_error", "algorithm", "foo"),
        ((), (first=nothing,), "instantiation_error", "", ""),
        ((), (first=1,), "domain_error", "stream_or_alias", ""),
        ((), (first=:foo,), "existence_error", "stream", "foo"),
        ((), (raw=:foo,), "type_error", "list", "foo"),
        ((:algorithm => :sha256,), (second=:foo,), "uninstantiation_error", "foo", "")
    )
    for (items, kw, formal, a1, a2) in rows
        r = case(items...; kw...)
        @test r.rc == LK.FFALSE
        @test r.exc && r.formal == formal
        @test r.args[1] == a1
        a2 == "" || @test r.args[2] == a2
    end
    # the algorithm names are the six, spelled as swipl does; any other is domain_error(algorithm, Name)
    for name in (:MD5, :sha3, :sha, :sha_256)
        r = case(:algorithm => name)
        @test r.rc == LK.FFALSE && r.formal == "domain_error" &&
            r.args == ("algorithm", String(name))
    end
    # an unknown option is ignored
    gd, ld = _env(_TL)
    parent, _, _ = _sf_out()
    hs, ts = _hash_open(ld, parent, :nosuchoption => 1)
    @test _stream_hash(ld, ts).hash == _WANT[(:sha1, :empty)]
    @test LK.closeStream(ld, hs)
end

# h10: a failed second argument leaves the parent as it was and no hash stream behind (hash_stream.c: close_parent = false; Sclose(s2); PL_uninstantiation_error)
@testset "h10 open_hash_stream with a bound second argument restores the parent" begin
    gd, ld = _env(_TL)
    parent, bufp, sizep = _sf_out()
    parent.encoding = LK.ENC_ISO_LATIN_1
    @test LK.PL_unify_stream(ld, _new1(ld), parent)
    before = _live(gd, ld)
    rc, t = _open(ld, parent, _opts(ld, :algorithm => :md5); second=:foo)
    @test rc == LK.FFALSE
    @test _exc(ld) && _exc_formal(ld) == "uninstantiation_error" &&
        _exc_args(ld)[1] == "foo"
    @test parent.magic == LK.SIO_MAGIC && parent.encoding == LK.ENC_ISO_LATIN_1
    @test parent.upstream === nothing && parent.references == 0
    @test _live(gd, ld) == before                                              # the filter stream left the table
    LK.PL_clear_exception(ld)
    @test LK.Sfwrite(UInt8[0x61, 0x62], 1, 2, parent) == 2
    @test LK.Sclose(parent) == 0
    @test _sf_bytes(bufp, sizep) == UInt8[0x61, 0x62]
end

# h11: stream_hash/2's refusals and failures
@testset "h11 stream_hash: errors and failures" begin
    gd, ld = _env(_TL)
    function sh(first; out=nothing)
        LK.PL_clear_exception(ld)
        r = _stream_hash(ld, first; out=out)
        exc = _exc(ld)
        return (;
            r..., formal=exc ? _exc_formal(ld) : "", args=exc ? _exc_args(ld) : ("", "")
        )
    end
    r = sh(_new1(ld))
    @test r.rc == LK.FFALSE && r.formal == "instantiation_error"
    r = sh(_atomref(ld, :foo))
    @test r.rc == LK.FFALSE && r.formal == "existence_error" && r.args == ("stream", "foo")
    r = sh(_atomref(ld, 1))
    @test r.rc == LK.FFALSE && r.formal == "domain_error" && r.args[1] == "stream_or_alias"
    # a stream that is no hash stream: domain_error(hash_stream, S), an output stream flushed first
    for plain in (_sf_in(_MSGS[:abc]), first(_sf_out()))
        ts = _new1(ld)
        @test LK.PL_unify_stream(ld, ts, plain)
        r = sh(ts)
        @test r.rc == LK.FFALSE && r.formal == "domain_error" && r.args[1] == "hash_stream"
        @test lk_eq(_exc_arg(ld, 2), lk_answer(ld, ts))
    end
    # a filter stream whose record is no hash context
    other = LK.Snew(OtherRec(), LK.SIO_OUTPUT | LK.SIO_FBUF, LK.Sfilterfunctions)
    ts = _new1(ld)
    @test LK.PL_unify_stream(ld, ts, other)
    r = sh(ts)
    @test r.rc == LK.FFALSE && r.formal == "domain_error" && r.args[1] == "hash_stream"
    # Hash bound to something else: fails, no error
    parent, _, _ = _sf_out()
    hs, ts = _hash_open(ld, parent, :algorithm => :md5)
    r = sh(ts; out=:foo)
    @test r.rc == LK.FFALSE && r.formal == ""
    r = sh(ts; out=:d41d8cd98f00b204e9800998ecf8427e)                        # bound to the digest itself: succeeds
    @test r.rc == LK.FTRUE
    # a stream with its error flag set: false (the Sferror branch)
    LK.Sseterr(hs, LK.SIO_FERR, "boom")
    r = sh(ts)
    @test r.rc == LK.FFALSE
    # a failing parent: the flush fails, so does stream_hash
    LK.PL_clear_exception(ld)
    sink = LK.Snew(FailSink(), LK.SIO_OUTPUT | LK.SIO_NBUF, LK.Sfilterfunctions)
    hs2, ts2 = _hash_open(ld, sink, :algorithm => :md5, :close_parent => :false)
    @test LK.Sfwrite(UInt8[0x78], 1, 1, hs2) == 1                               # buffered in the filter
    r = sh(ts2)
    @test r.rc == LK.FFALSE
    # a closed hash stream: existence_error(stream, S)
    LK.PL_clear_exception(ld)
    parent, _, _ = _sf_out()
    hs3, ts3 = _hash_open(ld, parent)
    @test LK.closeStream(ld, hs3)
    r = sh(ts3)
    @test r.rc == LK.FFALSE && r.formal == "existence_error" && r.args[1] == "stream"
end

# h12: the callbacks called directly
@testset "h12 Sfilter_read, Sfilter_write at an offset" begin
    gd, ld = _env(_TL)
    data = _MSGS[:k1000]
    hs, ts = _hash_open(ld, _sf_in(data), :algorithm => :sha256, :close_parent => :false)
    ctx = hs.filter[]
    buf = fill(0xee, 8)
    @test LK.Sfilter_read(ctx, buf, 3, 4) == 4
    @test buf == UInt8[0xee, 0xee, data[1], data[2], data[3], data[4], 0xee, 0xee]   # placed at `from`
    @test _stream_hash(ld, ts).hash == _core(:sha256, data[1:4])
    @test length(ctx.scratch) >= 4
    big = zeros(UInt8, 2000)
    @test LK.Sfilter_read(ctx, big, 1, 2000) == 996                            # what is left of the parent
    @test big[1:996] == data[5:1000]
    @test length(ctx.scratch) >= 2000
    h = _stream_hash(ld, ts).hash
    @test h == _WANT[(:sha256, :k1000)]
    @test LK.Sfilter_read(ctx, big, 1, 2000) == 0                              # end of file: the hash is left alone
    @test _stream_hash(ld, ts).hash == h
    @test LK.closeStream(ld, hs)

    parent, bufp, sizep = _sf_out()
    hs, ts = _hash_open(ld, parent, :algorithm => :md5, :close_parent => :false)
    ctx = hs.filter[]
    mem = UInt8[0x00, 0x00, 0x61, 0x62, 0x63, 0x00]
    @test LK.Sfilter_write(ctx, mem, 3, 3) == 3                                # "abc" at index 3
    @test _stream_hash(ld, ts).hash == _WANT[(:md5, :abc)]
    @test LK.closeStream(ld, hs)
    @test LK.Sclose(parent) == 0
    @test _sf_bytes(bufp, sizep) == _MSGS[:abc]
    # a parent that refuses the bytes: -1
    sink = LK.Snew(FailSink(), LK.SIO_OUTPUT | LK.SIO_NBUF, LK.Sfilterfunctions)
    hs, ts = _hash_open(ld, sink, :close_parent => :false)
    @test LK.Sfilter_write(hs.filter[], UInt8[1, 2, 3], 1, 3) == -1
end

# h13: hash_control: the encoding is allowed without asking the parent, anything else is the parent's, which has no control function: flush 0, the rest -1
@testset "h13 Sfilter_control" begin
    gd, ld = _env(_TL)
    parent, _, _ = _sf_out()
    hs, ts = _hash_open(ld, parent, :close_parent => :false)
    ctx = hs.filter[]
    @test LK.Sfilter_control(ctx, LK.SIO_SETENCODING, Ref(0)) == 0
    @test LK.Sfilter_control(ctx, LK.SIO_FLUSHOUTPUT, Ref(0)) == 0
    @test LK.Sfilter_control(ctx, LK.SIO_GETSIZE, Ref(0)) == -1
    @test LK.Ssetenc(hs, LK.ENC_UTF8) == 0 && hs.encoding == LK.ENC_UTF8 &&
        parent.encoding == LK.ENC_OCTET
    @test LK.closeStream(ld, hs)
    @test LK.Sclose(parent) == 0
    # a parent that has a control function: forwarded (the answer, the argument), except the encoding
    cp = CtlParent(4321, String[])
    cparent = LK.Snew(cp, LK.SIO_OUTPUT | LK.SIO_FBUF, LK.Sfilterfunctions)
    hs, ts = _hash_open(ld, cparent, :close_parent => :false)
    ctx = hs.filter[]
    sz = Ref(0)
    @test LK.Sfilter_control(ctx, LK.SIO_GETSIZE, sz) == 0 && sz[] == 4321
    @test LK.Sfilter_control(ctx, LK.SIO_FLUSHOUTPUT, Ref(0)) == 7
    @test LK.Sfilter_control(ctx, LK.SIO_SETENCODING, Ref(0)) == 0           # not forwarded: the parent would refuse
    @test cp.log == ["control$(LK.SIO_GETSIZE)", "control$(LK.SIO_FLUSHOUTPUT)"]
    @test LK.closeStream(ld, hs)
    @test LK.Sclose(cparent) == 0
end

# h14: the small functions
@testset "h14 hash_unify_digest, hash_digest_size, get_hash_algorithm, the context" begin
    gd, ld = _env(_TL)
    function uni(bytes::Vector{UInt8}, len::Int)
        LK.PL_clear_exception(ld)
        t = _new1(ld)
        ok = LK.hash_unify_digest(ld, t, bytes, len)
        a = ok ? lk_answer(ld, t) : nothing
        return ok,
        if a === nothing
            nothing
        elseif kind(a) === SYM
            sym_text(a)
        else
            nothing
        end
    end
    @test uni(UInt8[0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef], 8) ==
        (true, "0123456789abcdef")
    @test uni(UInt8[0xaa, 0xbb, 0xcc], 2) == (true, "aabb")                  # `len` is the used length
    @test uni(UInt8[], 0) == (true, "")
    @test uni(UInt8[0x0f, 0xf0], 2) == (true, "0ff0")                        # nibbles: the zero is kept
    @test uni(fill(0xab, 128), 128) == (true, "ab"^128)                      # 256 characters: the limit
    ok, _ = uni(fill(0xab, 129), 129)
    @test !ok && _exc(ld) && _exc_formal(ld) == "representation_error" &&
        _exc_args(ld)[1] == "digest_length"
    LK.PL_clear_exception(ld)

    @test [LK.hash_digest_size(a) for a in 0:5] == [16, 20, 28, 32, 48, 64]
    @test LK.hash_digest_size(6) == 0
    @test (LK.HASH_ALGORITHM_MD5, LK.HASH_ALGORITHM_SHA1, LK.HASH_ALGORITHM_SHA224,
        LK.HASH_ALGORITHM_SHA256, LK.HASH_ALGORITHM_SHA384, LK.HASH_ALGORITHM_SHA512) == (0, 1, 2, 3, 4, 5)
    for (i, nm) in enumerate(_ALGS)
        @test LK.get_hash_algorithm(ld, _atomref(ld, nm)) == i - 1
    end
    LK.PL_clear_exception(ld)
    @test LK.get_hash_algorithm(ld, _atomref(ld, :foo)) === nothing
    @test _exc(ld) && _exc_formal(ld) == "domain_error"
    LK.PL_clear_exception(ld)
    @test LK.get_hash_algorithm(ld, _atomref(ld, 1)) === nothing
    @test _exc(ld) && _exc_formal(ld) == "type_error"
    LK.PL_clear_exception(ld)

    # alloc_hash_context: zeroed; free_hash_context: unlinks a linked filter, does nothing otherwise
    parent, _, _ = _sf_out()
    ctx = LK.alloc_hash_context(ld, parent)
    @test ctx.stream === parent && ctx.hash_stream === nothing && ctx.ld === ld
    @test ctx.algorithm == 0 && ctx.digest_size == 0 && ctx.close_parent === false
    @test ctx.parent_encoding == LK.ENC_UNKNOWN && ctx.state isa LK.md5_state_t
    @test LK.free_hash_context(ctx) === nothing && parent.upstream === nothing
    hs, ts = _hash_open(ld, parent, :close_parent => :false)
    @test parent.upstream === hs
    LK.free_hash_context(hs.filter[])
    @test parent.upstream === nothing && hs.downstream === nothing
    @test LK.closeStream(ld, hs)
    @test LK.Sclose(parent) == 0
    # each algorithm's state type and constants
    for (i, nm) in enumerate(_ALGS)
        parent, _, _ = _sf_out()
        hs, ts = _hash_open(ld, parent, :algorithm => nm, :close_parent => :false)
        ctx = hs.filter[]
        @test ctx.algorithm == i - 1 && ctx.digest_size == _DSIZE[nm]
        @test ctx.state isa (
            if i == 1
                LK.md5_state_t
            elseif i == 2
                LK.sha1_ctx
            else
                LK.sha2_ctx
            end
        )
        @test LK.closeStream(ld, hs)
        @test LK.Sclose(parent) == 0
    end
end
