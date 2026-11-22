# ORIGINAL: packages/pcre/pcre4pl.c's blob functions write_pcre, save_pcre and load_pcre (a5e4c885) have no Prolog-level test that reaches them without
# libpcre2 and the qlf layer (upstream tests the saved state through `qsave_program`). The expected bytes are an independent python transcription of
# the C's field order (version, atom, nine pairs) over the varint of test_qlf_uint32.jl; the `put_atom`/`get_atom` callbacks stand for PL_qlf_put_atom/get_atom
# (here: a one-byte length then the pattern's bytes, written through the varint). Nothing here has run (written edit-only).
using Test, LogicKernel
const LK = LogicKernel

const _PS_GROUPS = (
    :compile_options_flags, :capture_type, :optimise_flags, :jit_options_flags, :compile_ctx_flags,
    :compile_bsr_flags, :compile_newline_flags, :match_options_flags, :start_flags,
)
# one (seen, flags) per group in the C's save order: all distinct, one with the 32-bit maximum
const _PS_PAIRS = [(1, 0x000003ef), (2, 0x000007d7), (3, 0x00000bbf), (4, 0xffffffff), (5, 0x0000138f), (6, 0x00001777), (7, 0x00001b5f), (8, 0x00001f47), (9, 0x0000232f)]

function _ps_regex(pattern::String = "a.c")
    re = LK.re_init_data(pattern)
    for (g, (s, f)) in zip(_PS_GROUPS, _PS_PAIRS)
        of = getfield(re, g)
        of.seen = UInt32(s)
        of.flags = UInt32(f)
    end
    return re
end

_ps_state(re) = [(getfield(re, g).seen, getfield(re, g).flags) for g in _PS_GROUPS]

# the stand-in for PL_qlf_put_atom: the pattern's byte length, then its bytes, each through the varint
function _ps_put_atom(pattern::String, fd)::Bool
    bytes = codeunits(pattern)
    LK.PL_qlf_put_uint32(UInt32(length(bytes)), fd) || return false
    for b in bytes
        LK.PL_qlf_put_uint32(UInt32(b), fd) || return false
    end
    return true
end
# the stand-in for PL_qlf_get_atom
function _ps_get_atom(fd)::Union{Nothing, String}
    ok, n = LK.PL_qlf_get_uint32(fd)
    ok || return nothing
    out = UInt8[]
    for _ in 1:n
        ok, b = LK.PL_qlf_get_uint32(fd)
        ok || return nothing
        push!(out, UInt8(b))
    end
    return String(out)
end

function _ps_save(re; put_atom = _ps_put_atom)
    bufp = Ref{Union{Nothing, Vector{UInt8}}}(nothing)
    sizep = Ref(0)
    w = LK.Sopenmem(bufp, sizep, "w")
    ok = LK.re_save_fields(re, w, put_atom)
    LK.Sflush(w)
    out = sizep[] == 0 ? UInt8[] : copy(bufp[][1:sizep[]])
    LK.Sclose(w)
    return (ok, out)
end

_ps_reader(bytes::Vector{UInt8}) = LK.Sopenmem(Ref{Union{Nothing, Vector{UInt8}}}(copy(bytes)), Ref(length(bytes)), "r")

# the C's layout for _ps_regex("a.c"): version 1, the atom (3, 'a', '.', 'c' by the stand-in), nine (seen, flags) pairs
const _PS_BYTES = UInt8[0x81, 0x83, 0x61, 0x2e, 0x63, 0x81, 0x6f, 0x87, 0x82, 0x57, 0x8f, 0x83, 0x3f, 0x97, 0x84, 0x7f, 0x7f, 0x7f, 0x7f, 0x8f, 0x85, 0x0f, 0xa7, 0x86, 0x77, 0xae, 0x87, 0x5f, 0xb6, 0x88, 0x47, 0xbe, 0x89, 0x2f, 0xc6]

@testset "re_write_text: <regex>(0x<serial>, <pattern>)" begin
    re = LK.re_init_data("a.c")
    @test LK.re_write_text(re) == string("<regex>(0x", string(re.serial, base = 16), ", a.c)")
    re.serial = 255
    @test LK.re_write_text(re) == "<regex>(0xff, a.c)"
    re.serial = 16
    @test LK.re_write_text(re) == "<regex>(0x10, a.c)"
    # a pattern with ')' or a quote is written as it is (the C's %.*WAs)
    q = LK.re_init_data("a)\"b")
    @test LK.re_write_text(q) == string("<regex>(0x", string(q.serial, base = 16), ", a)\"b)")
    e = LK.re_init_data("")
    @test startswith(LK.re_write_text(e), "<regex>(0x") && endswith(LK.re_write_text(e), ", )")
end

@testset "re_save_fields: the bytes in the C's order" begin
    ok, bytes = _ps_save(_ps_regex())
    @test ok
    @test bytes == _PS_BYTES
    # the pattern is the C's second field: a different pattern changes bytes 2.. only
    ok2, bytes2 = _ps_save(_ps_regex("xy"))
    @test ok2 && bytes2[1] == 0x81 && bytes2[2] == 0x82 && bytes2[3:4] == UInt8[0xf8, 0xf9]
end

@testset "re_save_fields: a failing write ends the sequence (&&)" begin
    # the atom writer fails: the pairs are not written, the version is
    ok, bytes = _ps_save(_ps_regex(); put_atom = (p, fd) -> false)
    @test !ok && bytes == UInt8[0x81]
end

@testset "re_load_fields: the round trip" begin
    re = _ps_regex()
    _, bytes = _ps_save(re)
    r = _ps_reader(bytes)
    got = LK.re_load_fields(r, _ps_get_atom)
    @test got !== nothing
    @test got.pattern == "a.c"
    @test _ps_state(got) == _ps_state(re)
    @test got.serial != re.serial                           # a new regex, as the C's new blob
    @test LK.Sferror(r) == 0
    LK.Sclose(r)
    # the default flags are replaced by the saved ones (compile flags of _ps_regex are not the defaults)
    @test _ps_state(got)[1] != _ps_state(LK.re_init_data("a.c"))[1]
    # a bare default regex round-trips too
    d = LK.re_init_data("p")
    _, bytes = _ps_save(d)
    g = LK.re_load_fields(_ps_reader(bytes), _ps_get_atom)
    @test g !== nothing && g.pattern == "p" && _ps_state(g) == _ps_state(d)
end

@testset "re_load_fields: a version other than 1 is refused with the stream error" begin
    _, bytes = _ps_save(_ps_regex())
    for v in (0x80, 0x82, 0xff)                              # version 0, 2, 127
        b = copy(bytes)
        b[1] = v
        r = _ps_reader(b)
        @test LK.re_load_fields(r, _ps_get_atom) === nothing
        @test LK.Sferror(r) == 1
        @test r.message == "Version mismatch for PCRE2 blob load"
        LK.Sclose(r)
    end
end

@testset "re_load_fields: a failed atom or a stream with an error is nothing" begin
    _, bytes = _ps_save(_ps_regex())
    @test LK.re_load_fields(_ps_reader(bytes), fd -> nothing) === nothing
    # a stream with an error makes the pair reads fail
    r = _ps_reader(bytes)
    LK.Sseterr(r, LK.SIO_FERR, "boom")
    @test LK.re_load_fields(r, _ps_get_atom) === nothing
    LK.Sclose(r)
end

@testset "re_save_options_flag / re_load_options_flag" begin
    bufp = Ref{Union{Nothing, Vector{UInt8}}}(nothing)
    sizep = Ref(0)
    w = LK.Sopenmem(bufp, sizep, "w")
    of = LK.re_options_flags(UInt32(3), UInt32(0x12345))
    @test LK.re_save_options_flag(of, w)
    LK.Sflush(w)
    bytes = copy(bufp[][1:sizep[]])
    LK.Sclose(w)
    @test bytes == UInt8[0x83, 0x45, 0x46, 0x84]            # 3; then 0x12345 in groups of 7 bits: 0x45, 0x46, 0x04 with 0x80
    r = _ps_reader(bytes)
    into = LK.re_options_flags(UInt32(0), UInt32(0))
    @test LK.re_load_options_flag(r, into)
    @test (into.seen, into.flags) == (UInt32(3), UInt32(0x12345))
    LK.Sclose(r)
end
