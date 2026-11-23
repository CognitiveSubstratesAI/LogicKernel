# CLASS: test
# ORIGINAL: PCRE1 piece 9's gate - the typed ccall wrappers of libpcre2-8 (PCRE2_jll, D-1002) that src/pl-pcre.jl binds for packages/pcre/pcre4pl.c
# (packages-pcre a5e4c885; the C line numbers are in the wrappers' comments). Every expectation is derived, none invented: from the C (the error branches
# `re_error` / `get_pcre2_info` name, the `ovector` layout `unify_match` reads, the 0 / #bytes / BADOPTION answers of `pcre2_config`), from Julia's own
# `Base.PCRE` (the same library in the same process: the constants, the version string, the error texts, the compile error message, the name table) or
# from Julia's `Regex` on the same library (the capture offsets of a match, converted to the 0-based byte offsets the ovector holds). Patterns and subjects
# are ASCII unless a row says UTF-8. The rows whose value rests on the PCRE2 documentation alone (the buffer-too-small answer, the NULL no-ops, a trailing
# unset group's `rc`) say so. No term type is used. Nothing here has run (no Julia process was started to write this file).
using Test, LogicKernel
import PCRE2_jll
const LK = LogicKernel
const PC = Base.PCRE

_bytes(s::String) = Vector{UInt8}(codeunits(s))

# compile `pat` (a String) with `opts` and the compile context `ctx`: (code, errcode, erroffset)
_cc_compile(pat::String, opts::UInt32 = UInt32(0), ctx::Ptr{Cvoid} = Ptr{Cvoid}(C_NULL)) = LK.pcre2_compile(_bytes(pat), opts, ctx)

# match `code` against the bytes `b` from byte `start`: (rc, the copied ovector); the match data is freed
function _cc_match_bytes(code::Ptr{Cvoid}, b::Vector{UInt8}, start::Int = 0, opts::UInt32 = UInt32(0))
    md = LK.pcre2_match_data_create_from_pattern(code)
    rc = LK.pcre2_match(code, b, length(b), start, opts, md)
    ov = rc > 0 ? LK.pcre2_ovector_copy(md, Int(rc)) : Csize_t[]
    LK.pcre2_match_data_free(md)
    return (rc, ov)
end
_cc_match(code::Ptr{Cvoid}, s::String, start::Int = 0, opts::UInt32 = UInt32(0)) = _cc_match_bytes(code, _bytes(s), start, opts)

# the ovector of a Julia `RegexMatch` (the same libpcre2): 0-based byte offsets, PCRE2_UNSET for a group that did not take part
function _regex_ovec(m::RegexMatch)
    v = Csize_t[Csize_t(m.offset - 1), Csize_t(m.offset - 1 + ncodeunits(m.match))]
    for i in eachindex(m.captures)
        c = m.captures[i]
        if c === nothing
            push!(v, LK.PCRE2_UNSET, LK.PCRE2_UNSET)
        else
            o = m.offsets[i] - 1
            push!(v, Csize_t(o), Csize_t(o + ncodeunits(c)))
        end
    end
    return v
end

@testset "one libpcre2-8 in the process, the one PCRE2_jll names and Base.PCRE uses" begin
    loaded = filter(contains("libpcre2-8"), Base.Libc.Libdl.dllist())
    @test length(loaded) == 1
    @test PCRE2_jll.libpcre2_8_path == loaded[1]
    @test PCRE2_jll.libpcre2_8_handle == Base.Libc.Libdl.dlopen(PC.PCRE_LIB)
    @test LK.libpcre2_8 == PCRE2_jll.libpcre2_8

    # the version string through the wrapper equals the one read through Base.PCRE's library name (CONFIG_VERSION is Base's constant)
    @test LK.PCRE2_CONFIG_VERSION == PC.CONFIG_VERSION
    buf = LK.pcre2_config_buf()
    @test length(buf) == 100
    rc = LK.pcre2_config(LK.PCRE2_CONFIG_VERSION, buf)
    @test rc isa Cint
    v = LK.pcre2_config_str(buf)
    pb = zeros(UInt8, 100)
    prc = ccall((:pcre2_config_8, PC.PCRE_LIB), Cint, (UInt32, Ptr{Cvoid}), PC.CONFIG_VERSION, pb)
    @test prc == rc
    @test GC.@preserve(pb, unsafe_string(pointer(pb))) == v
    @test occursin(r"^\d+\.\d+", v)
    @test rc == ncodeunits(v) + 1          # a string answer is its length with the trailing NUL (pcre2api; C comment at 1026: "# bytes for stringbuf")
end

@testset "PCRE2_ERROR_*, PCRE2_INFO_*, PCRE2_UNSET are Base.PCRE's values" begin
    errs = (
        :NOMATCH, :PARTIAL, :UTF8_ERR1, :UTF8_ERR21, :NOMEMORY, :MATCHLIMIT, :DEPTHLIMIT, :HEAPLIMIT, :JIT_STACKLIMIT, :BADOFFSET, :NULL,
        :BADOPTION, :BADMAGIC, :UNSET,
    )
    infos = (:ARGOPTIONS, :BSR, :CAPTURECOUNT, :EXTRAOPTIONS, :NAMECOUNT, :NAMEENTRYSIZE, :NAMETABLE, :NEWLINE)
    @test length(errs) == 14 && length(infos) == 8
    for n in errs
        mine = getproperty(LK, Symbol("PCRE2_ERROR_", n))
        theirs = getproperty(PC, Symbol("ERROR_", n))
        @test mine == theirs
        @test typeof(mine) === Cint
    end
    for n in infos
        mine = getproperty(LK, Symbol("PCRE2_INFO_", n))
        theirs = getproperty(PC, Symbol("INFO_", n))
        @test mine == theirs
        @test typeof(mine) === UInt32
    end
    @test LK.PCRE2_UNSET == PC.UNSET
    @test typeof(LK.PCRE2_UNSET) === Csize_t
    @test LK.PCRE2_UNSET == typemax(Csize_t)
end

@testset "re_data: the compiled code and the capture names" begin
    re = LK.re_init_data("x")
    @test fieldtype(LK.re_data, :code) === Ptr{Cvoid}
    @test fieldtype(LK.re_data, :capture_names) === Vector{LK.re_cap_how}
    @test re.code == C_NULL
    @test re.capture_names isa Vector{LK.re_cap_how}
    @test isempty(re.capture_names)
    @test re.capture_names !== LK.re_init_data("y").capture_names      # one vector per regex
    @test fieldtype(LK.re_cap_how, :name) === Union{Nothing, String}
    @test fieldtype(LK.re_cap_how, :type) === Int
    h = LK.re_cap_how()
    @test h.name === nothing && h.type == LK.CAP_DEFAULT
    h.name = "year"
    h.type = LK.CAP_INTEGER
    @test h.name == "year" && h.type == LK.CAP_INTEGER
    @test LK.re_cap_how("n", LK.CAP_RANGE).type == LK.CAP_RANGE
    # init_re_data's flag defaults are unchanged by the two new fields (test_pcre_options.jl owns them; one control)
    @test re.compile_options_flags.flags == (LK.PCRE2_UTF | LK.PCRE2_NO_UTF_CHECK)
    @test re.capture_size == 0
end

@testset "compile, capture count, match, ovector (the same answers as Julia's Regex on the same library)" begin
    for (pat, subj) in (
            ("(\\w)(\\d)", "xa1y"),
            ("(a)?(b)", "b"),
            ("a(b)c", "zzabcz"),
            ("(?<year>\\d+)-(?<m>\\w)", "on 2023-N."),
        )
        code, _, _ = _cc_compile(pat)
        @test code != C_NULL
        rc, ov = _cc_match(code, subj)
        m = match(Regex(pat), subj)
        @test m !== nothing
        exp = _regex_ovec(m)
        @test rc isa Cint
        @test Int(rc) == length(exp) ÷ 2           # the highest group that took part + 1 (here the last group did)
        @test ov == exp
        @test length(ov) == 2 * rc
        cc, cnt = LK.pcre2_pattern_info(code, LK.PCRE2_INFO_CAPTURECOUNT, UInt32)
        @test cc == 0
        @test cnt isa UInt32
        @test cnt == PC.info(code, PC.INFO_CAPTURECOUNT, UInt32)
        @test cnt == length(m.captures)
        LK.pcre2_code_free(code)
    end

    # hand rows (the numbers follow from the pattern and the subject)
    code, _, _ = _cc_compile("(a)?(b)")
    @test _cc_match(code, "b") == (Cint(3), Csize_t[0, 1, LK.PCRE2_UNSET, LK.PCRE2_UNSET, 0, 1])      # group 1 did not take part
    LK.pcre2_code_free(code)
    code, _, _ = _cc_compile("a(b)?")
    @test _cc_match(code, "a") == (Cint(1), Csize_t[0, 1])    # a trailing unset group is not counted in rc (pcre2api: "highest numbered capture + 1")
    LK.pcre2_code_free(code)
    code, _, _ = _cc_compile("a")
    @test _cc_match(code, "aa", 1) == (Cint(1), Csize_t[1, 2])                       # start offset
    @test _cc_match(code, "aa", 0) == (Cint(1), Csize_t[0, 1])
    @test _cc_match(code, "b")[1] == LK.PCRE2_ERROR_NOMATCH
    @test _cc_match(code, "") == (LK.PCRE2_ERROR_NOMATCH, Csize_t[])
    @test _cc_match(code, "ab", 5)[1] == LK.PCRE2_ERROR_BADOFFSET                     # start past the length (re_error's BADOFFSET row)
    @test _cc_match(code, "ba", 2)[1] == LK.PCRE2_ERROR_NOMATCH                        # start at the length: allowed, nothing there
    LK.pcre2_code_free(code)
    code, _, _ = _cc_compile("^a")
    @test _cc_match(code, "a")[1] == 1
    @test _cc_match(code, "a", 0, LK.PCRE2_NOTBOL)[1] == LK.PCRE2_ERROR_NOMATCH       # the match options reach the library
    LK.pcre2_code_free(code)
    code, _, _ = _cc_compile("ab", LK.PCRE2_CASELESS)                                  # the compile options reach the library
    @test _cc_match(code, "xAB") == (Cint(1), Csize_t[1, 3])
    LK.pcre2_code_free(code)
    code, _, _ = _cc_compile("ab")
    @test _cc_match(code, "xAB")[1] == LK.PCRE2_ERROR_NOMATCH
    LK.pcre2_code_free(code)

    # an empty pattern, an empty subject: a match of length 0 at 0
    code, _, _ = _cc_compile("")
    @test code != C_NULL
    @test _cc_match(code, "") == (Cint(1), Csize_t[0, 0])
    LK.pcre2_code_free(code)

    # UTF-8: byte offsets (the C converts them to character offsets with char_offset); the subject "aébbbc" has the 2-byte é at bytes 1-2
    code, _, _ = _cc_compile("(b+)", LK.PCRE2_UTF)
    rc, ov = _cc_match(code, "aébbbc")
    m = match(r"(b+)", "aébbbc")
    @test ov == _regex_ovec(m)
    @test ov == Csize_t[3, 6, 3, 6]
    @test rc == 2
    LK.pcre2_code_free(code)

    # an invalid UTF-8 subject with the UTF check on: an error in the UTF8_ERR range (re_error: representation_error(utf8)), and its text
    code, _, _ = _cc_compile("a", LK.PCRE2_UTF)
    rc, ov = _cc_match_bytes(code, UInt8[0xff, 0x61])
    @test LK.PCRE2_ERROR_UTF8_ERR21 <= rc <= LK.PCRE2_ERROR_UTF8_ERR1
    @test isempty(ov)
    t = LK.pcre2_get_error_message(rc)
    @test t isa String && !isempty(t)
    @test t == PC.err_message(rc)
    LK.pcre2_code_free(code)
end

@testset "pcre2_get_ovector_pointer and pcre2_ovector_copy" begin
    code, _, _ = _cc_compile("(b)(c)")
    md = LK.pcre2_match_data_create_from_pattern(code)
    @test md != C_NULL
    b = _bytes("abcd")
    rc = LK.pcre2_match(code, b, length(b), 0, UInt32(0), md)
    @test rc == 3
    p = LK.pcre2_get_ovector_pointer(md)
    @test p isa Ptr{Csize_t} && p != C_NULL
    @test [unsafe_load(p, i) for i in 1:6] == Csize_t[1, 3, 1, 2, 2, 3]
    @test LK.pcre2_ovector_copy(md, 3) == Csize_t[1, 3, 1, 2, 2, 3]
    @test LK.pcre2_ovector_copy(md, 2) == Csize_t[1, 3, 1, 2]
    @test LK.pcre2_ovector_copy(md, 1) == Csize_t[1, 3]
    @test isempty(LK.pcre2_ovector_copy(md, 0))
    @test isempty(LK.pcre2_ovector_copy(md, -1))
    cp = LK.pcre2_ovector_copy(md, 3)
    LK.pcre2_match_data_free(md)
    @test cp == Csize_t[1, 3, 1, 2, 2, 3]            # the copy outlives the match data
    LK.pcre2_code_free(code)
end

@testset "compile errors: code, offset, message text" begin
    for pat in ("(", "a)", "[a", "*a")
        code, ec, eo = _cc_compile(pat)
        @test code == C_NULL
        @test ec isa Cint && ec > 0                  # a compile error code is positive (the match errors are negative)
        @test eo isa Csize_t
        text = LK.pcre2_get_error_message(ec)
        @test text isa String && !isempty(text)
        @test text == PC.err_message(ec)                         # the same library: version independent
        msg = try
            PC.compile(pat, UInt32(0))
            nothing
        catch e
            e.msg
        end
        @test msg == "PCRE compilation error: $text at offset $eo"
    end
    # the C passes sizeof-1 for the compile error text and sizeof for the match error text: both lengths work
    _, ec, _ = _cc_compile("(")
    @test LK.pcre2_get_error_message(ec, 255) == LK.pcre2_get_error_message(ec, 256) == LK.pcre2_get_error_message(ec)
    # texts of match results (re_error's default branch asks for these)
    for rc in (LK.PCRE2_ERROR_NOMATCH, LK.PCRE2_ERROR_PARTIAL, LK.PCRE2_ERROR_BADOFFSET, LK.PCRE2_ERROR_MATCHLIMIT, LK.PCRE2_ERROR_NULL, LK.PCRE2_ERROR_BADOPTION)
        @test LK.pcre2_get_error_message(rc) == PC.err_message(rc)
    end
    # an unknown code: libpcre2 answers BADDATA (Base.PCRE errors on it), the wrapper `nothing` (the C: "regex")
    @test LK.pcre2_get_error_message(99999) === nothing
    @test_throws ErrorException PC.err_message(99999)
    # a buffer too small: the message is cut and libpcre2 answers a negative (pcre2api: PCRE2_ERROR_NOMEMORY); n bytes of text need n+1
    full = LK.pcre2_get_error_message(LK.PCRE2_ERROR_NOMATCH)
    n = ncodeunits(full)
    @test LK.pcre2_get_error_message(LK.PCRE2_ERROR_NOMATCH, n + 1) == full
    @test LK.pcre2_get_error_message(LK.PCRE2_ERROR_NOMATCH, n) === nothing
    @test LK.pcre2_get_error_message(LK.PCRE2_ERROR_NOMATCH, 0) === nothing
end

@testset "the name table through pcre2_pattern_info (init_capture_map's walk)" begin
    pat = "(?<year>\\d+)-(?<m>\\w)(x)"
    code, _, _ = _cc_compile(pat)
    rc1, count = LK.pcre2_pattern_info(code, LK.PCRE2_INFO_NAMECOUNT, UInt32)
    rc2, esize = LK.pcre2_pattern_info(code, LK.PCRE2_INFO_NAMEENTRYSIZE, UInt32)
    rc3, tbl = LK.pcre2_pattern_info(code, LK.PCRE2_INFO_NAMETABLE, Ptr{UInt8})
    @test (rc1, rc2, rc3) == (0, 0, 0)
    @test count isa UInt32 && esize isa UInt32 && tbl isa Ptr{UInt8}
    @test count == 2
    @test tbl != C_NULL
    # the C's walk: entry i holds the group number as a big-endian 16-bit value, then the NUL-terminated name
    names = Dict{Int, String}()
    for i in 0:(Int(count) - 1)
        e = tbl + i * Int(esize)
        idx = (Int(unsafe_load(e, 1)) << 8) + Int(unsafe_load(e, 2))
        names[idx] = unsafe_string(e + 2)
    end
    @test names == Dict(1 => "year", 2 => "m")
    @test names == PC.capture_names(code)
    @test esize >= 2 + length("year") + 1                      # 2-byte index + the longest name + its NUL
    rc4, cc = LK.pcre2_pattern_info(code, LK.PCRE2_INFO_CAPTURECOUNT, UInt32)
    @test (rc4, cc) == (0, 3)
    LK.pcre2_code_free(code)

    # no names: a count of 0 (init_capture_map then walks nothing)
    code, _, _ = _cc_compile("(a)(b)")
    @test LK.pcre2_pattern_info(code, LK.PCRE2_INFO_NAMECOUNT, UInt32) == (0, 0)
    LK.pcre2_code_free(code)

    # get_pcre2_info's error branches: a NULL code and an unknown `what` (values: the C names ERROR_NULL and ERROR_BADOPTION)
    @test LK.pcre2_pattern_info(Ptr{Cvoid}(C_NULL), LK.PCRE2_INFO_CAPTURECOUNT, UInt32) == (LK.PCRE2_ERROR_NULL, UInt32(0))
    code, _, _ = _cc_compile("a")
    @test LK.pcre2_pattern_info(code, UInt32(9999), UInt32) == (LK.PCRE2_ERROR_BADOPTION, UInt32(0))
    @test LK.pcre2_pattern_info(code, UInt32(9999), Ptr{UInt8}) == (LK.PCRE2_ERROR_BADOPTION, Ptr{UInt8}(0))
    LK.pcre2_code_free(code)
end

@testset "the compile context: bsr, newline, extra options, and what pcre2_pattern_info reads back" begin
    ctx = LK.pcre2_compile_context_create()
    @test ctx isa Ptr{Cvoid} && ctx != C_NULL
    @test LK.pcre2_set_bsr(ctx, LK.PCRE2_BSR_ANYCRLF) == 0
    @test LK.pcre2_set_bsr(ctx, LK.PCRE2_BSR_UNICODE) == 0
    @test LK.pcre2_set_bsr(ctx, UInt32(99)) != 0               # the C: `0 != pcre2_set_bsr(...)` is representation_error(option:bsr)
    @test LK.pcre2_set_newline(ctx, LK.PCRE2_NEWLINE_CR) == 0
    @test LK.pcre2_set_newline(ctx, LK.PCRE2_NEWLINE_ANYCRLF) == 0
    @test LK.pcre2_set_newline(ctx, UInt32(99)) != 0
    @test LK.pcre2_set_compile_extra_options(ctx, LK.PCRE2_EXTRA_MATCH_WORD) == 0
    LK.pcre2_compile_context_free(ctx)

    # newline convention: `.` does not match the convention's newline
    for (nl, subj, hit) in (
            (LK.PCRE2_NEWLINE_LF, "a\nb", false), (LK.PCRE2_NEWLINE_CR, "a\nb", true),
            (LK.PCRE2_NEWLINE_CR, "a\rb", false), (LK.PCRE2_NEWLINE_LF, "a\rb", true),
        )
        ctx = LK.pcre2_compile_context_create()
        @test LK.pcre2_set_newline(ctx, nl) == 0
        code, _, _ = _cc_compile("a.b", UInt32(0), ctx)
        @test code != C_NULL
        @test (_cc_match(code, subj)[1] > 0) == hit
        @test LK.pcre2_pattern_info(code, LK.PCRE2_INFO_NEWLINE, UInt32) == (0, nl)
        LK.pcre2_code_free(code)
        LK.pcre2_compile_context_free(ctx)
    end

    # bsr convention: \R matches U+2028 only with PCRE2_BSR_UNICODE (UTF mode: the bytes E2 80 A8)
    for (bsr, hit) in ((LK.PCRE2_BSR_ANYCRLF, false), (LK.PCRE2_BSR_UNICODE, true))
        ctx = LK.pcre2_compile_context_create()
        @test LK.pcre2_set_bsr(ctx, bsr) == 0
        code, _, _ = _cc_compile("a\\Rb", LK.PCRE2_UTF, ctx)
        @test code != C_NULL
        @test (_cc_match(code, "a b")[1] > 0) == hit
        @test (_cc_match(code, "a\r\nb")[1] > 0)               # CRLF is a \R in both conventions
        @test LK.pcre2_pattern_info(code, LK.PCRE2_INFO_BSR, UInt32) == (0, bsr)
        LK.pcre2_code_free(code)
        LK.pcre2_compile_context_free(ctx)
    end

    # extra options: EXTRA_MATCH_WORD brackets the pattern with word boundaries (pcre2api); it reads back through INFO_EXTRAOPTIONS
    ctx = LK.pcre2_compile_context_create()
    @test LK.pcre2_set_compile_extra_options(ctx, LK.PCRE2_EXTRA_MATCH_WORD) == 0
    code, _, _ = _cc_compile("ab", UInt32(0), ctx)
    @test _cc_match(code, "xab")[1] == LK.PCRE2_ERROR_NOMATCH
    @test _cc_match(code, "x ab y")[1] == 1
    rc, ex = LK.pcre2_pattern_info(code, LK.PCRE2_INFO_EXTRAOPTIONS, UInt32)
    @test rc == 0 && (ex & LK.PCRE2_EXTRA_MATCH_WORD) != 0
    LK.pcre2_code_free(code)
    LK.pcre2_compile_context_free(ctx)
    code, _, _ = _cc_compile("ab")
    @test _cc_match(code, "xab")[1] == 1                       # no context: no word boundaries
    rc, ex = LK.pcre2_pattern_info(code, LK.PCRE2_INFO_EXTRAOPTIONS, UInt32)
    @test rc == 0 && ex == 0
    LK.pcre2_code_free(code)

    # INFO_ARGOPTIONS reads back the compile options
    code, _, _ = _cc_compile("a", LK.PCRE2_CASELESS | LK.PCRE2_MULTILINE)
    rc, ao = LK.pcre2_pattern_info(code, LK.PCRE2_INFO_ARGOPTIONS, UInt32)
    @test rc == 0
    @test (ao & LK.PCRE2_CASELESS) != 0 && (ao & LK.PCRE2_MULTILINE) != 0
    LK.pcre2_code_free(code)

    # the no-ops of a NULL handle (pcre4pl.c frees `re->re_compiled` after a failed compile): pcre2api says each frees nothing
    @test LK.pcre2_code_free(Ptr{Cvoid}(C_NULL)) === nothing
    @test LK.pcre2_match_data_free(Ptr{Cvoid}(C_NULL)) === nothing
    @test LK.pcre2_compile_context_free(Ptr{Cvoid}(C_NULL)) === nothing
end

@testset "pcre2_jit_compile" begin
    buf = LK.pcre2_config_buf()
    @test LK.pcre2_config(LK.PCRE2_CONFIG_JIT, buf) == 0
    jit = LK.pcre2_config_u32(buf) == 1
    code, _, _ = _cc_compile("(a+)b")
    before = _cc_match(code, "xaab")
    r = LK.pcre2_jit_compile(code, LK.PCRE2_JIT_COMPLETE)
    @test r isa Cint
    # the C ignores the result (a build without JIT answers BADOPTION): with a JIT, it is 0 (Base.PCRE's jit_compile reads the same two answers)
    @test r == (jit ? 0 : PC.ERROR_JIT_BADOPTION)
    @test _cc_match(code, "xaab") == before == (Cint(2), Csize_t[1, 4, 1, 3])
    LK.pcre2_code_free(code)
end

@testset "pcre2_config: ints, strings, the error answer" begin
    # an int answer: 0, the value in the buffer; it equals what Base.PCRE's library name answers
    for what in (LK.PCRE2_CONFIG_JIT, LK.PCRE2_CONFIG_NEWLINE, LK.PCRE2_CONFIG_BSR, LK.PCRE2_CONFIG_PARENSLIMIT, LK.PCRE2_CONFIG_UNICODE)
        buf = LK.pcre2_config_buf()
        rc = LK.pcre2_config(what, buf)
        pb = zeros(UInt8, 100)
        prc = ccall((:pcre2_config_8, PC.PCRE_LIB), Cint, (UInt32, Ptr{Cvoid}), what, pb)
        @test rc == prc == 0
        @test buf == pb
        @test LK.pcre2_config_u32(buf) == reinterpret(UInt32, pb[1:4])[1]
        @test LK.pcre2_config_i32(buf) == reinterpret(Int32, pb[1:4])[1]
    end
    # a value above 2^31 reads differently as signed and unsigned: write one into the buffer and read the two members back
    buf = LK.pcre2_config_buf()
    buf[1:4] .= [0xff, 0xff, 0xff, 0xff]
    @test LK.pcre2_config_u32(buf) == typemax(UInt32)
    @test LK.pcre2_config_i32(buf) == Int32(-1)
    buf = LK.pcre2_config_buf()
    buf[1:5] .= [0x61, 0x62, 0x63, 0x00, 0x64]
    @test LK.pcre2_config_str(buf) == "abc"                  # up to the first NUL
    # an unknown option: BADOPTION, negative (the C: `pcre2_config_(o->id, &val) >= 0` guards the read)
    @test LK.pcre2_config(UInt32(0xffff), LK.pcre2_config_buf()) == LK.PCRE2_ERROR_BADOPTION
    # the unicode version is a string answer too
    buf = LK.pcre2_config_buf()
    rc = LK.pcre2_config(LK.PCRE2_CONFIG_UNICODE_VERSION, buf)
    uv = LK.pcre2_config_str(buf)
    @test rc > 0 && occursin(r"^\d+\.\d+", uv)
    pb = zeros(UInt8, 100)
    ccall((:pcre2_config_8, PC.PCRE_LIB), Cint, (UInt32, Ptr{Cvoid}), PC.CONFIG_UNICODE_VERSION, pb)
    @test GC.@preserve(pb, unsafe_string(pointer(pb))) == uv
end
