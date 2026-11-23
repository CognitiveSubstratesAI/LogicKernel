# CLASS: test
# ORIGINAL: ZLIB1 piece Z3's gate - zopen/3, zdebug/1 and the registration of packages/zlib/zlib4pl.c (src/pl-zlib.jl: pl_zopen3_va, pl_zdebug1_va, install_zlib4pl,
# PL_predicates_from_zlib4pl; packages-zlib 9f4be6fe; the C line numbers are in the testsets' comments), called at the Julia level on term references and on the memory
# streams the test builds. BLIND-CODED: nothing here has run (no Julia process was started to write this file). Every expectation is derived, none invented: from the C
# (the order of the checks, the error formals, which option sets which field of the record, COPY_FLAGS, the encoding copy, the failure arm of PL_unify_stream), from round
# trips (write through zopen, read through zopen: equal, all three formats, the levels) and from properties of the formats (RFC 1950/1952 header bytes; level 0 stores;
# a raw deflate stream is no gzip or zlib stream). NEVER from compressed byte values (DIVERGES 1 of src/pl-zlib.jl); the probe list of evidence/R2/zlib_plan.md section 5
# names the same rows for the swipl oracle (the pin has no zlib4pl.so: the rows are not differential runs).
# DOC-ONLY (no row can provoke them): `deflateInit*` answering other than Z_OK (the level is validated first), the "no memory" exit of `Snew`, the three `zlib:` texts of
# the filter's init failures, and the Prolog-level test_zlib.pl / zlib.pl rows (gzopen/3,4, the 7 binary fixtures; piece Z4: the vendored plunit run).
# KERNEL-SIDE (a row rests on what the stream layer does, not on zlib4pl.c): the stream table count after the failure arm; a memory stream's flags.
# NOT DONE (named): registration in module `system` at a booted database is asserted on the tables (`_PRED_TABLES`, `_FOREIGN_VA`), not by calling `zopen/3` through
# the VM; the `static_extensions` row of src/pl-load.jl is absent in this base (DIVERGES 11), so `$activate_static_extension(zlib4pl)` is not exercised.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE - built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TL = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})

_ctx(::LK.PL_local_data{T}) where {T} =
    LK.foreign_context{T}(LK.FRG_FIRST_CALL, UInt(0), nothing)

function _env(::Type{T}) where {T}
    gd = LK.PL_global_data{T}()
    ld = LK.PL_local_data{T}(gd)
    LK.PL_open_foreign_frame(ld)
    return gd, ld
end

# ---------------------------------------------------------------------------------------------------------------------
# data
_zbytes(s::String) = Vector{UInt8}(codeunits(s))
function _lcg_bytes(n::Int, seed::UInt32 = 0x1234abcd)
    x = seed
    out = Vector{UInt8}(undef, n)
    for i in 1:n
        x = x * UInt32(1664525) + UInt32(1013904223)
        out[i] = UInt8(x >> 24)
    end
    return out
end
_text(n::Int) = repeat(_zbytes("the quick brown fox jumps over the lazy dog. "), cld(n, 45))[1:n]

const _INPUTS = Pair{String, Vector{UInt8}}[
    "empty" => UInt8[], "1 byte" => UInt8[0x41], "text 5000" => _text(5000), "random 20000" => _lcg_bytes(20000),
]
const _FMTS = (:gzip, :deflate, :raw_deflate)

# ---------------------------------------------------------------------------------------------------------------------
# argument kinds and the term-building helpers (the term type comes from the local data)
_put_val!(ld, t::Int, ::Nothing) = true
_put_val!(ld::LK.PL_local_data{T}, t::Int, x::Symbol) where {T} =
    LK.PL_put_atom(ld, t, lk_sym(T, x))
_put_val!(ld, t::Int, x::Integer) = LK.PL_put_int64(ld, t, Int(x))

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

# the stream helpers of test/files/test_stream_filter_swipl.jl; the parents are binary (no SIO_TEXT, octet): the bytes written are the bytes stored
_octet!(s::LK.IOSTREAM) = (s.flags &= ~LK.SIO_TEXT; s.encoding = LK.ENC_OCTET; s)
_sf_in(bytes::Vector{UInt8}) =
    _octet!(LK.Sopenmem(Ref{Union{Nothing, Vector{UInt8}}}(copy(bytes)), Ref(length(bytes)), "r"))
function _sf_out()
    bufp = Ref{Union{Nothing, Vector{UInt8}}}(nothing)
    sizep = Ref(0)
    return _octet!(LK.Sopenmem(bufp, sizep, "w")), bufp, sizep
end
_sf_bytes(bufp, sizep) = sizep[] == 0 ? UInt8[] : copy(bufp[][1:sizep[]])

function _read_all(zs::LK.IOSTREAM; chunk::Int = 1000)
    out = UInt8[]
    buf = Vector{UInt8}(undef, chunk)
    while true
        n = LK.Sfread(buf, 1, chunk, zs)
        n > 0 && append!(out, @view buf[1:n])
        n < chunk && break
    end
    return out
end

_live(gd, ld) = count(
    s ->
        s !== nothing &&
        !any(x -> x === s, ld.IO_streams[(LK.SNO_USER_INPUT + 1):(LK.SNO_USER_ERROR + 1)]),
    gd.stream_table
)

# ---------------------------------------------------------------------------------------------------------------------
# the errors of the pending exception
_exc(ld)::Bool = LK.PL_exception(ld, 0) != 0
_exc_term(ld) = lk_answer(ld, LK.PL_exception(ld, 0))
function _exc_formal(ld)::String
    f = child(_exc_term(ld), 2)
    return sym_text(kind(f) === SYM ? f : child(f, 1))
end
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
_exc_arg(ld, i::Int) = child(child(_exc_term(ld), 2), i + 1)

# ---------------------------------------------------------------------------------------------------------------------
# zopen(Org, Z, Options) on fresh term references: `org` is the term reference of the first argument, `second` is what the second argument holds before the call
function _call(ld, org::Int, opts::Int; second = nothing)
    t = LK.PL_new_term_refs(ld, 3)
    LK.PL_put_term(ld, t, org)
    _put_val!(ld, t + 1, second) || error("_put_val!")
    LK.PL_put_term(ld, t + 2, opts)
    rc = LK.pl_zopen3_va(ld, t, 3, _ctx(ld))
    return rc, t
end
function _stream_ref(ld, s::LK.IOSTREAM)::Int
    t = _new1(ld)
    LK.PL_unify_stream(ld, t, s) || error("PL_unify_stream")
    return t
end
# `parent` is an IOSTREAM, a symbol, an integer or `nothing` (unbound)
_open(ld, parent, opts::Int; second = nothing) =
    _call(ld, parent isa LK.IOSTREAM ? _stream_ref(ld, parent) : _atomref(ld, parent), opts; second)
# the zlib stream of a call that must succeed
function _zopen_ok(ld, parent, items...)
    rc, t = _open(ld, parent, _opts(ld, items...))
    rc == LK.FTRUE || error("zopen/3 failed")
    zs = LK.term_stream_handle(ld, t + 1, LK.SH_ERRORS | LK.SH_ALIAS)
    zs isa LK.IOSTREAM || error("no zlib stream")
    return zs
end
# a call that must fail: the answer, and the formal and arguments of the error if there is one
function _fails(ld, parent, items...; second = nothing)
    LK.PL_clear_exception(ld)
    rc, t = _open(ld, parent, _opts(ld, items...); second)
    exc = _exc(ld)
    return (; rc, exc, formal = exc ? _exc_formal(ld) : "", args = exc ? _exc_args(ld) : ("", ""))
end

# compress `data` through zopen/3 over a memory stream; the bytes
function _compress(ld, data::Vector{UInt8}, items...)
    parent, bufp, sizep = _sf_out()
    zs = _zopen_ok(ld, parent, items..., :close_parent => :false)
    @test LK.Sfwrite(data, 1, length(data), zs) == length(data)
    @test LK.closeStream(ld, zs)
    @test parent.upstream === nothing && parent.magic == LK.SIO_MAGIC       # close_parent(false): the parent is left open
    @test LK.Sclose(parent) == 0
    return _sf_bytes(bufp, sizep)
end

# ---------------------------------------------------------------------------------------------------------------------
# o01: the errors, in the order of the C (zlib4pl.c 436-461: the options, the format, the level, then the stream)
@testset "o01 zopen/3 errors and their order" begin
    gd, ld = _env(_TL)
    parent, _, _ = _sf_out()
    # the format: an atom of the three, else type_error(atom, X) / domain_error(compression_format, X)  (C 442-451)
    r = _fails(ld, parent, :format => :foo)
    @test r.rc == LK.FFALSE && r.formal == "domain_error" && r.args == ("compression_format", "foo")
    r = _fails(ld, parent, :format => 1)
    @test r.rc == LK.FFALSE && r.formal == "type_error" && r.args[1] == "atom"
    @test lk_eq(_exc_arg(ld, 2), lk_answer(ld, _atomref(ld, 1)))
    # the level: an integer 0..9, else type_error(integer, X) / domain_error(compression_level, X)  (C 453-459)
    for bad in (10, -1, 100, -5)
        r = _fails(ld, parent, :level => bad)
        @test r.rc == LK.FFALSE && r.formal == "domain_error" && r.args[1] == "compression_level"
        @test lk_eq(_exc_arg(ld, 2), lk_answer(ld, _atomref(ld, bad)))
    end
    r = _fails(ld, parent, :level => :a)
    @test r.rc == LK.FFALSE && r.formal == "type_error" && r.args == ("integer", "a")
    # the stream (C 461): unbound, no such alias, not a stream or alias
    r = _fails(ld, nothing)
    @test r.rc == LK.FFALSE && r.formal == "instantiation_error"
    r = _fails(ld, :nostream)
    @test r.rc == LK.FFALSE && r.formal == "existence_error" && r.args == ("stream", "nostream")
    r = _fails(ld, 1)
    @test r.rc == LK.FFALSE && r.formal == "domain_error" && r.args[1] == "stream_or_alias"
    # the ORDER: the options are checked before the stream, the format before the level
    r = _fails(ld, :nostream, :format => :foo)
    @test r.formal == "domain_error" && r.args == ("compression_format", "foo")
    r = _fails(ld, :nostream, :level => 10)
    @test r.formal == "domain_error" && r.args[1] == "compression_level"
    r = _fails(ld, nothing, :level => :a)
    @test r.formal == "type_error" && r.args == ("integer", "a")
    r = _fails(ld, parent, :format => :foo, :level => :a)
    @test r.formal == "domain_error" && r.args[1] == "compression_format"
    # a failed call leaves the parent as it was
    @test parent.upstream === nothing && parent.magic == LK.SIO_MAGIC
    @test LK.Sclose(parent) == 0
end

# o02: the accepted values, the edges of the level range (C 457: `level < 0 || level > 9`), an unknown option is ignored
@testset "o02 zopen/3 accepts format, level 0..9, bool options and ignores an unknown option" begin
    gd, ld = _env(_TL)
    for fmt in _FMTS, lvl in (0, 1, 9)
        parent, _, _ = _sf_out()
        zs = _zopen_ok(ld, parent, :format => fmt, :level => lvl, :close_parent => :false)
        @test LK.closeStream(ld, zs)
        @test LK.Sclose(parent) == 0
    end
    parent, _, _ = _sf_out()
    zs = _zopen_ok(ld, parent, :nosuchoption => 1, :close_parent => :false)
    @test LK.closeStream(ld, zs)
    @test LK.Sclose(parent) == 0
    # the bool options: a bare atom or true/false, close_parent and multi_part
    for items in ((:close_parent,), (:multi_part,), (:multi_part => :true, :close_parent => :false))
        parent, _, _ = _sf_out()
        zs = _zopen_ok(ld, parent, items...)
        @test LK.closeStream(ld, zs)
        parent.magic == LK.SIO_MAGIC && LK.Sclose(parent)
    end
end

# o03: which option sets which field of the record, and the defaults (C 426-430, 462-466)
@testset "o03 zopen/3 options reach the record" begin
    gd, ld = _env(_TL)
    # the defaults: no format (F_UNKNOWN), close_parent true, multi_part -1, level default
    parent, _, _ = _sf_out()
    zs = _zopen_ok(ld, parent)
    ctx = zs.filter[]
    @test ctx isa LK.ZContext
    @test ctx.format == LK.Z_F_UNKNOWN && ctx.close_parent === true && ctx.multi_part == -1
    @test ctx.stream === parent && ctx.zstream === zs && parent.upstream === zs     # C 462, 491, 492
    @test LK.closeStream(ld, zs)
    @test parent.magic == LK.SIO_CMAGIC                                             # close_parent(true) is the default: the parent is closed
    # the format
    for (fmt, want) in ((:gzip, LK.Z_F_GZIP), (:deflate, LK.Z_F_DEFLATE), (:raw_deflate, LK.Z_F_RAW_DEFLATE))
        parent, _, _ = _sf_out()
        zs = _zopen_ok(ld, parent, :format => fmt, :close_parent => :false)
        @test zs.filter[].format == want && zs.filter[].close_parent === false
        @test LK.closeStream(ld, zs)
        @test parent.magic == LK.SIO_MAGIC && parent.upstream === nothing           # close_parent(false): the parent stays open
        @test LK.Sclose(parent) == 0
    end
    # close_parent(true) given, multi_part true and false (1 and 0; unset is -1)
    for (mp, want) in ((:true, 1), (:false, 0))
        parent = _sf_in(UInt8[0x00])
        zs = _zopen_ok(ld, parent, :close_parent => :true, :multi_part => mp)
        @test zs.filter[].close_parent === true && zs.filter[].multi_part == want
        @test LK.closeStream(ld, zs)
        @test parent.magic == LK.SIO_CMAGIC
    end
    # the order of the option list does not matter
    parent, _, _ = _sf_out()
    zs = _zopen_ok(ld, parent, :multi_part => :false, :close_parent => :false, :format => :gzip, :level => 3)
    @test zs.filter[].format == LK.Z_F_GZIP && zs.filter[].multi_part == 0 && zs.filter[].close_parent === false
    @test LK.closeStream(ld, zs)
    @test LK.Sclose(parent) == 0
end

# o04: the new stream copies the parent's flags (COPY_FLAGS, C 412-415) and its encoding (C 490), is fully buffered (C 485), and is an input stream
# exactly when the parent is
@testset "o04 zopen/3 flags and encoding of the new stream" begin
    gd, ld = _env(_TL)
    parent, _, _ = _sf_out()
    parent.flags |= LK.SIO_TEXT | LK.SIO_REPXML | LK.SIO_REPPL
    parent.encoding = LK.ENC_ISO_LATIN_1
    zs = _zopen_ok(ld, parent, :format => :gzip, :close_parent => :false)
    @test zs.encoding == LK.ENC_ISO_LATIN_1                                         # C 490
    @test (zs.flags & LK.ZLIB_COPY_FLAGS) == (parent.flags & LK.ZLIB_COPY_FLAGS)
    @test (zs.flags & LK.SIO_TEXT) != 0 && (zs.flags & LK.SIO_REPXML) != 0 && (zs.flags & LK.SIO_REPPL) != 0
    @test (zs.flags & LK.SIO_FBUF) != 0                                             # C 485
    @test (zs.flags & LK.SIO_OUTPUT) != 0 && (zs.flags & LK.SIO_INPUT) == 0
    @test (zs.flags & LK.SIO_RECORDPOS) == (parent.flags & LK.SIO_RECORDPOS)
    # initStreamLocale, when the database has a current locale
    gd.locale.current === nothing || @test zs.locale !== nothing
    _octet!(parent)    # the close writes the gzip trailer: keep the parent binary
    @test LK.closeStream(ld, zs)
    @test LK.Sclose(parent) == 0
    # an input parent
    parent = _sf_in(UInt8[0x00])
    zs = _zopen_ok(ld, parent, :close_parent => :false)
    @test (zs.flags & LK.SIO_INPUT) != 0 && (zs.flags & LK.SIO_OUTPUT) == 0 && (zs.flags & LK.SIO_FBUF) != 0
    @test zs.encoding == parent.encoding
    @test LK.closeStream(ld, zs)
    @test LK.Sclose(parent) == 0
    # the flags are the ones in COPY_FLAGS, the same as the C's
    @test LK.ZLIB_COPY_FLAGS ==
        (LK.SIO_INPUT | LK.SIO_OUTPUT | LK.SIO_TEXT | LK.SIO_REPXML | LK.SIO_REPPL | LK.SIO_RECORDPOS)
end

# o05: round trips through zopen/3 (write, then read) - the property, never the bytes
@testset "o05 zopen/3 round trip: format, level, input" begin
    gd, ld = _env(_TL)
    for (fname, data) in _INPUTS, fmt in _FMTS, lvl in (fname == "text 5000" ? (0, 1, 6, 9) : (6,))
        comp = _compress(ld, data, :format => fmt, :level => lvl)
        @test !isempty(comp)
        if fmt == :gzip
            @test comp[1:2] == UInt8[0x1f, 0x8b]                                    # RFC 1952
        elseif fmt == :deflate
            @test (comp[1] & 0x0f) == 8 && ((Int(comp[1]) << 8) | Int(comp[2])) % 31 == 0   # RFC 1950
        end
        parent = _sf_in(comp)
        zs = _zopen_ok(ld, parent, :format => fmt)
        @test _read_all(zs) == data
        @test LK.Sferror(zs) == 0
        @test LK.closeStream(ld, zs)
        @test parent.magic == LK.SIO_CMAGIC
    end
    # a stream with no format option writes the zlib wrapper (`deflateInit`, C 473) and reads gzip and zlib data by auto-detection (C 167)
    gd, ld = _env(_TL)
    data = _text(5000)
    for fmt in (:gzip, :deflate)
        comp = _compress(ld, data, :format => fmt)
        parent = _sf_in(comp)
        zs = _zopen_ok(ld, parent)
        @test _read_all(zs) == data
        @test LK.Sferror(zs) == 0
        @test LK.closeStream(ld, zs)
    end
    comp = _compress(ld, data)
    @test (comp[1] & 0x0f) == 8 && ((Int(comp[1]) << 8) | Int(comp[2])) % 31 == 0
    parent = _sf_in(comp)
    zs = _zopen_ok(ld, parent, :format => :deflate)
    @test _read_all(zs) == data
    @test LK.closeStream(ld, zs)
end

# o06: the level and the format change the output (properties of the formats, not of the bytes)
@testset "o06 zopen/3 level and format change what is written" begin
    gd, ld = _env(_TL)
    data = _text(5000)
    for fmt in _FMTS
        c0 = _compress(ld, data, :format => fmt, :level => 0)
        c9 = _compress(ld, data, :format => fmt, :level => 9)
        cd = _compress(ld, data, :format => fmt)
        @test length(c0) > length(data)                                             # level 0 stores: the data plus the block and stream headers
        @test length(c9) < length(data) ÷ 4 && length(cd) < length(data) ÷ 4        # repetitive text compresses by far more than 4:1
        @test length(c9) < length(c0)
    end
    # raw deflate is no gzip and no zlib stream: the auto-detecting reader (no format) refuses it (a single final block starts with an odd byte: neither 0x1f nor a CMF byte)
    raw = _compress(ld, data, :format => :raw_deflate)
    parent = _sf_in(raw)
    zs = _zopen_ok(ld, parent)
    got = _read_all(zs)
    @test got != data && LK.Sferror(zs) != 0
    LK.closeStream(ld, zs)
    # and a zlib stream read as gzip is refused too
    zl = _compress(ld, data, :format => :deflate)
    parent = _sf_in(zl)
    zs = _zopen_ok(ld, parent, :format => :gzip)
    @test _read_all(zs) != data && LK.Sferror(zs) != 0
    LK.closeStream(ld, zs)
end

# o07: multi_part (test_zlib.pl deflate_multipart): two members written to one parent, read as one stream, or as the first only
@testset "o07 zopen/3 multi_part" begin
    gd, ld = _env(_TL)
    a, b = _text(2000), _lcg_bytes(900, 0x00c0ffee)
    for fmt in (:gzip, :deflate)
        parent, bufp, sizep = _sf_out()
        for d in (a, b)
            zs = _zopen_ok(ld, parent, :format => fmt, :close_parent => :false)
            @test LK.Sfwrite(d, 1, length(d), zs) == length(d)
            @test LK.closeStream(ld, zs)
            @test parent.upstream === nothing
        end
        @test LK.Sclose(parent) == 0
        comp = _sf_bytes(bufp, sizep)
        parent = _sf_in(comp)
        zs = _zopen_ok(ld, parent, :format => fmt, :multi_part => :true)
        @test _read_all(zs) == vcat(a, b)
        @test LK.Sferror(zs) == 0
        @test LK.closeStream(ld, zs)
        # multi_part(false): the first member only, the rest stays in the parent
        parent = _sf_in(comp)
        zs = _zopen_ok(ld, parent, :format => fmt, :multi_part => :false, :close_parent => :false)
        @test _read_all(zs) == a
        @test LK.closeStream(ld, zs)
        rest = Vector{UInt8}(undef, 1)
        @test LK.Sfread(rest, 1, 1, parent) == 1                                     # the second member's first byte is still there
        @test LK.Sclose(parent) == 0
    end
    # gzip by default (multi_part unset, -1): members are concatenated
    parent, bufp, sizep = _sf_out()
    for d in (a, b)
        zs = _zopen_ok(ld, parent, :format => :gzip, :close_parent => :false)
        LK.Sfwrite(d, 1, length(d), zs)
        @test LK.closeStream(ld, zs)
    end
    @test LK.Sclose(parent) == 0
    parent = _sf_in(_sf_bytes(bufp, sizep))
    zs = _zopen_ok(ld, parent, :format => :gzip)
    @test _read_all(zs) == vcat(a, b)
    @test LK.closeStream(ld, zs)
end

# o08: corrupt and truncated input: an error on the stream, the bytes before it are a prefix of the data
@testset "o08 zopen/3 reading corrupt and truncated input" begin
    gd, ld = _env(_TL)
    data = _lcg_bytes(20000)
    for fmt in _FMTS
        comp = _compress(ld, data, :format => fmt)
        parent = _sf_in(comp[1:(length(comp) ÷ 2)])
        zs = _zopen_ok(ld, parent, :format => fmt)
        got = _read_all(zs)
        @test LK.Sferror(zs) != 0
        @test length(got) < length(data) && got == data[1:length(got)]
        LK.closeStream(ld, zs)
    end
    parent = _sf_in(_zbytes("this is not a gzip file at all"))
    zs = _zopen_ok(ld, parent, :format => :gzip)
    @test isempty(_read_all(zs)) && LK.Sferror(zs) != 0
    LK.closeStream(ld, zs)
end

# o09: the failure arm of PL_unify_stream (C 494-500): the second argument is bound to something that is not the new stream. The filter is closed again,
# the parent is not closed, no filter is left on it, the stream table is as before, and instantiation_error is raised
@testset "o09 zopen/3 with a bound second argument restores the parent" begin
    gd, ld = _env(_TL)
    # an input parent: nothing was consumed
    comp = _compress(ld, _text(3000), :format => :gzip)
    parent = _sf_in(comp)
    pref = _stream_ref(ld, parent)
    before = _live(gd, ld)
    LK.PL_clear_exception(ld)
    rc, t = _call(ld, pref, _opts(ld, :format => :gzip); second = :foo)
    @test rc == LK.FFALSE
    @test _exc(ld) && _exc_formal(ld) == "instantiation_error"
    @test parent.magic == LK.SIO_MAGIC && parent.upstream === nothing
    @test _live(gd, ld) == before
    LK.PL_clear_exception(ld)
    got = Vector{UInt8}(undef, length(comp))
    @test LK.Sfread(got, 1, length(comp), parent) == length(comp) && got == comp
    @test LK.Sclose(parent) == 0
    # an output parent: closing the filter finished an empty stream on it (C 499: Sclose -> zclose -> Z_FINISH)
    parent, bufp, sizep = _sf_out()
    pref = _stream_ref(ld, parent)
    before = _live(gd, ld)
    rc, t = _call(ld, pref, _opts(ld, :format => :gzip); second = :foo)
    @test rc == LK.FFALSE
    @test _exc(ld) && _exc_formal(ld) == "instantiation_error"
    @test parent.magic == LK.SIO_MAGIC && parent.upstream === nothing
    @test _live(gd, ld) == before
    LK.PL_clear_exception(ld)
    @test LK.Sclose(parent) == 0
    empty = _sf_bytes(bufp, sizep)
    @test empty[1:2] == UInt8[0x1f, 0x8b]                                           # a complete, empty gzip stream
    zs = _zopen_ok(ld, _sf_in(empty), :format => :gzip)
    @test isempty(_read_all(zs)) && LK.Sferror(zs) == 0
    @test LK.closeStream(ld, zs)
end

# o10: a closed parent is an existence_error (C 461)
@testset "o10 zopen/3 on a closed stream" begin
    gd, ld = _env(_TL)
    parent, _, _ = _sf_out()
    pref = _stream_ref(ld, parent)
    @test LK.closeStream(ld, parent)
    LK.PL_clear_exception(ld)
    rc, t = _call(ld, pref, _opts(ld))
    @test rc == LK.FFALSE && _exc(ld) && _exc_formal(ld) == "existence_error"
    LK.PL_clear_exception(ld)
end

# o11: zdebug/1 (C 505-510; registered because the C defines O_DEBUG, line 36)
@testset "o11 zdebug/1" begin
    gd, ld = _env(_TL)
    @test LK.zlib_debuglevel[] == 0
    function zdebug(x)
        t = _atomref(ld, x)
        return LK.pl_zdebug1_va(ld, t, 1, _ctx(ld))
    end
    @test zdebug(3) == LK.FTRUE && LK.zlib_debuglevel[] == 3
    @test zdebug(0) == LK.FTRUE && LK.zlib_debuglevel[] == 0
    @test zdebug(7) == LK.FTRUE && LK.zlib_debuglevel[] == 7
    LK.PL_clear_exception(ld)
    @test zdebug(:foo) == LK.FFALSE && LK.zlib_debuglevel[] == 7                    # PL_get_integer: no error, just false
    @test !_exc(ld)
    @test zdebug(nothing) == LK.FFALSE && LK.zlib_debuglevel[] == 7
    @test zdebug(0) == LK.FTRUE && LK.zlib_debuglevel[] == 0
end

# o12: the registration (C 513-527; DIVERGES 11): the extension table and its two predicates, in `_PRED_TABLES` and `_FOREIGN_VA`; the install function does nothing
@testset "o12 registration: PL_predicates_from_zlib4pl" begin
    gd, ld = _env(_TL)
    tab = LK.PL_predicates_from_zlib4pl
    @test length(tab) == 2
    @test [(e.predicate_name, e.arity) for e in tab] == [("zopen", 3), ("zdebug", 1)]
    @test all(e -> e.flags == LK.PL_FA_VARARGS, tab)
    @test any(t -> t === LK.PL_predicates_from_zlib4pl, LK._PRED_TABLES)
    for (name, arity) in (("zopen", 3), ("zdebug", 1))
        @test count(e -> e.predicate_name == name && e.arity == arity, LK._FOREIGN_VA) == 1
    end
    @test LK.install_zlib4pl(ld) === nothing
end
