# CLASS: test
# ORIGINAL: PCRE1 piece 10 (B1)'s gate - `re_free`, `re_ensure_compile_context`, `re_compile_impl`, `re_verify_pats`, `re_init_capture_map` and
# `re_set_capture_name_and_type` of packages/pcre/pcre4pl.c (packages-pcre a5e4c885; src/pl-pcre.jl piece 10). The expected values are derived, none
# invented: from the C text (the `name_T` suffix rule of `set_capture_name_and_type`, the `flags != 0` guards, `free_pcre` on a failed compile), from Julia's
# `Base.PCRE` on the same library (the error text of a bad pattern, the constants), from libpcre2's own answers read through `pcre2_pattern_info` /
# `pcre2_match` (what the context options did), or from the PCRE2 documentation alone (rows say "doc-only"). The error terms are the kernel's
# `PL_error` forms (read back as error(Formal, _): the formal's name and its atomic arguments). The option fields are set directly on a `re_data`.
# Nothing here has run (written edit-only): BLIND RISKS the lane settles are (1) a group name that starts with an underscore (`_S`) must be accepted by the
# library's name grammar, (2) `pcre2_set_bsr`/`pcre2_set_newline` return nonzero for the value 99, (3) `pcre2_jit_compile` works in this build
# (the JIT rows are gated on `CONFIG_JIT`), (4) the kernel's text of the culprit atom of the existence error is the one character.
using Test, LogicKernel
const LK = LogicKernel
const PC = Base.PCRE

# TERM TYPES PER CHUNK: REFERENCE - built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "..", "core_lang", "rules_common.jl"))

const _PC_LD = _rdb(Tuple{_R, Union{Nothing, _R}}[]).ld

# The pending error(Formal, _) as (Formal's name, [its atomic arguments]); clears it; nothing when none is pending.
function _pc_exc(ld)
    ex = LK.PL_exception(ld, 0)
    ex == 0 && return nothing
    f = LK.PL_new_term_ref(ld)
    a = LK.PL_new_term_ref(ld)
    r = nothing
    if LK._PL_get_arg(ld, 1, ex, f)
        na = LK.PL_get_name_arity(ld, f)
        if na !== nothing
            args = String[]
            for i in 1:na[2]
                LK._PL_get_arg(ld, i, f, a)
                txt = LK.PL_get_text(ld, a, LK.CVT_ATOMIC)
                push!(args, txt === nothing ? "?" : LK.text_string(txt))
            end
            r = (LK.sym_text(na[1]), args)
        end
    end
    LK.PL_clear_exception(ld)
    return r
end

_pc_bytes(s::String) = Vector{UInt8}(codeunits(s))

# compile `pat` into a fresh re_data (after `setup(re)`): (ok, re, the pending error); the frame is discarded, the compiled code is NOT freed (the caller does)
function _pc_compile(pat::String; setup = re -> nothing)
    ld = _PC_LD
    fid = LK.PL_open_foreign_frame(ld)
    re = LK.re_init_data(pat)
    setup(re)
    ok = LK.re_compile_impl(ld, re, _pc_bytes(pat))
    exc = _pc_exc(ld)
    LK.PL_discard_foreign_frame(ld, fid)
    return (ok, re, exc)
end

_pc_caps(re) = [(c.name, c.type) for c in re.capture_names]

# the first match of `code` in `s` (default options): (rc, the copied ovector)
function _pc_match(code, s::String, opts::UInt32 = UInt32(0))
    md = LK.pcre2_match_data_create_from_pattern(code)
    b = _pc_bytes(s)
    rc = LK.pcre2_match(code, b, length(b), 0, opts, md)
    ov = rc > 0 ? LK.pcre2_ovector_copy(md, Int(rc)) : Csize_t[]
    LK.pcre2_match_data_free(md)
    return (Int(rc), ov)
end

_pc_info(code, what::UInt32, ::Type{T}) where {T} = LK.pcre2_pattern_info(code, what, T)

@testset "re_compile_impl: a plain pattern compiles, the capture map has capture_size + 1 default entries" begin
    ok, re, exc = _pc_compile("(a)(b)")
    @test ok && exc === nothing
    @test re.code != C_NULL
    @test re.capture_size == 2
    @test _pc_caps(re) == [(nothing, LK.CAP_DEFAULT), (nothing, LK.CAP_DEFAULT), (nothing, LK.CAP_DEFAULT)]
    @test _pc_match(re.code, "xab")[1] == 3                 # the compiled code is the pattern's
    @test re.pattern == "(a)(b)"
    LK.re_free(re)
    ok, re, exc = _pc_compile("abc")                        # no groups: one entry (the whole match)
    @test ok && re.capture_size == 0 && _pc_caps(re) == [(nothing, LK.CAP_DEFAULT)]
    LK.re_free(re)
end

@testset "re_compile_impl: the compile options of the regex reach pcre2_compile" begin
    ok, re, _ = _pc_compile("a"; setup = re -> (re.compile_options_flags.flags |= LK.PCRE2_CASELESS))
    @test ok && _pc_match(re.code, "A")[1] == 1
    LK.re_free(re)
    ok, re, _ = _pc_compile("a")                           # no caseless: "A" does not match
    @test ok && _pc_match(re.code, "A")[1] == LK.PCRE2_ERROR_NOMATCH
    LK.re_free(re)
    # the default options hold UTF: `.` takes the two bytes of one character
    ok, re, _ = _pc_compile(".")
    @test ok
    rc, ov = _pc_match(re.code, "é")
    @test rc == 1 && ov == Csize_t[0, 2]
    LK.re_free(re)
    ok, re, _ = _pc_compile("."; setup = re -> (re.compile_options_flags.flags = LK.PCRE2_NO_UTF_CHECK))
    @test ok
    rc, ov = _pc_match(re.code, "é")
    @test rc == 1 && ov == Csize_t[0, 1]
    LK.re_free(re)
end

@testset "set_capture_name_and_type: the name_X suffix types a capture (one byte after the LAST underscore), anything else is an untyped name" begin
    ok, re, exc = _pc_compile("(?<n_I>\\d+)(?<x>a)(?<_S>b)(?<a_b_S>c)(?<a_bc>d)(?<a_>e)(f)")
    @test ok && exc === nothing
    @test re.capture_size == 7
    @test _pc_caps(re) == [
        (nothing, LK.CAP_DEFAULT),
        ("n", LK.CAP_INTEGER),                             # typed: the name is the text before the underscore
        ("x", LK.CAP_DEFAULT),                             # no underscore
        ("", LK.CAP_STRING),                               # empty name before the underscore (the C: len 0)
        ("a_b", LK.CAP_STRING),                            # only the LAST underscore counts (strrchr)
        ("a_bc", LK.CAP_DEFAULT),                          # more than one byte after the underscore: untyped, the whole name
        ("a_", LK.CAP_DEFAULT),                            # nothing after the underscore: untyped (the C's `fs[1]` is NUL)
        (nothing, LK.CAP_DEFAULT),                         # an unnamed group
    ]
    LK.re_free(re)
    # every type letter of the switch, in the order of the C
    ok, re, _ = _pc_compile("(?<s_S>a)(?<a_A>a)(?<i_I>a)(?<f_F>a)(?<n_N>a)(?<t_T>a)(?<r_R>a)")
    @test ok
    @test [c.type for c in re.capture_names[2:end]] ==
        [LK.CAP_STRING, LK.CAP_ATOM, LK.CAP_INTEGER, LK.CAP_FLOAT, LK.CAP_NUMBER, LK.CAP_TERM, LK.CAP_RANGE]
    @test [c.name for c in re.capture_names[2:end]] == ["s", "a", "i", "f", "n", "t", "r"]
    LK.re_free(re)
    # the entry of a name is that of its group NUMBER, not its place in the (sorted) name table
    ok, re, _ = _pc_compile("(?<z>a)(?<b_I>b)")
    @test ok && _pc_caps(re) == [(nothing, LK.CAP_DEFAULT), ("z", LK.CAP_DEFAULT), ("b", LK.CAP_INTEGER)]
    LK.re_free(re)
    # a UTF-8 name keeps its text
    ok, re, _ = _pc_compile("(?<né_A>a)")
    @test ok && _pc_caps(re)[2] == ("né", LK.CAP_ATOM)
    LK.re_free(re)
end

@testset "set_capture_name_and_type: an unknown type letter is existence_error(re_type_flag, Letter) and the regex is freed" begin
    for (pat, letter) in (("(?<q_Q>d)", "Q"), ("(?<q_s>d)", "s"), ("(?<ok_I>a)(?<bad_X>b)", "X"))
        ok, re, exc = _pc_compile(pat)
        @test !ok
        @test exc == ("existence_error", ["re_type_flag", letter])
        @test re.code == C_NULL                             # free_pcre ran (the compile itself succeeded)
        @test isempty(re.capture_names)
    end
end

@testset "re_compile_impl: a bad pattern is syntax_error(the library's message) and the regex is freed" begin
    ok, re, exc = _pc_compile("(")
    @test !ok
    (code, ec, _) = LK.pcre2_compile(_pc_bytes("("), LK.PCRE2_UTF | LK.PCRE2_NO_UTF_CHECK, Ptr{Cvoid}(C_NULL))
    @test code == C_NULL && ec != 0
    msg = PC.err_message(ec)                                 # Base.PCRE: the same library's text for the same code
    @test !isempty(msg)
    @test exc == ("syntax_error", [msg])
    @test re.code == C_NULL && isempty(re.capture_names)
    ok, re, exc = _pc_compile("a)")
    @test !ok && exc !== nothing && exc[1] == "syntax_error" && !isempty(exc[2][1])
end

@testset "re_verify_pats: a NUL byte is representation_error(nul_byte)" begin
    ld = _PC_LD
    for (bytes, good) in (
            (_pc_bytes("ab"), true), (UInt8[], true), (UInt8[0x61, 0x00, 0x62], false), (UInt8[0x00], false), (UInt8[0x61, 0x62, 0x00], false),
        )
        fid = LK.PL_open_foreign_frame(ld)
        r = LK.re_verify_pats(ld, bytes)
        exc = _pc_exc(ld)
        LK.PL_discard_foreign_frame(ld, fid)
        @test r == good
        @test exc == (good ? nothing : ("representation_error", ["nul_byte"]))
    end
end

@testset "re_compile_impl: the bsr, newline and extra options go through the compile context (read back with pcre2_pattern_info)" begin
    for v in (PC.BSR_UNICODE, PC.BSR_ANYCRLF)
        ok, re, _ = _pc_compile("a"; setup = re -> (re.compile_bsr_flags.flags = v))
        @test ok && _pc_info(re.code, PC.INFO_BSR, UInt32) == (Cint(0), v)
        LK.re_free(re)
    end
    for v in (PC.NEWLINE_CR, PC.NEWLINE_LF, PC.NEWLINE_CRLF, PC.NEWLINE_ANY, PC.NEWLINE_ANYCRLF, PC.NEWLINE_NUL)
        ok, re, _ = _pc_compile("a"; setup = re -> (re.compile_newline_flags.flags = v))
        @test ok && _pc_info(re.code, PC.INFO_NEWLINE, UInt32) == (Cint(0), v)
        LK.re_free(re)
    end
    # extra options: MATCH_WORD wraps the pattern in \b...\b
    ok, re, _ = _pc_compile("a"; setup = re -> (re.compile_ctx_flags.flags = LK.PCRE2_EXTRA_MATCH_WORD))
    @test ok
    @test _pc_info(re.code, PC.INFO_EXTRAOPTIONS, UInt32) == (Cint(0), LK.PCRE2_EXTRA_MATCH_WORD)
    @test _pc_match(re.code, "ab")[1] == LK.PCRE2_ERROR_NOMATCH
    @test _pc_match(re.code, "b a")[1] == 1
    LK.re_free(re)
    ok, re, _ = _pc_compile("a")                             # no flags: no context, the default conventions, "ab" matches
    @test ok && _pc_match(re.code, "ab")[1] == 1
    @test _pc_info(re.code, PC.INFO_EXTRAOPTIONS, UInt32) == (Cint(0), UInt32(0))
    LK.re_free(re)
    # the newline convention is the compiled one: `^` after "\r" matches under CR, not under LF (multiline)
    ok, re, _ = _pc_compile("^b"; setup = re -> (re.compile_options_flags.flags |= LK.PCRE2_MULTILINE; re.compile_newline_flags.flags = PC.NEWLINE_CR))
    @test ok && _pc_match(re.code, "a\rb")[1] == 1
    LK.re_free(re)
    ok, re, _ = _pc_compile("^b"; setup = re -> (re.compile_options_flags.flags |= LK.PCRE2_MULTILINE; re.compile_newline_flags.flags = PC.NEWLINE_LF))
    @test ok && _pc_match(re.code, "a\rb")[1] == LK.PCRE2_ERROR_NOMATCH
    LK.re_free(re)
end

@testset "re_compile_impl: an invalid bsr or newline value is representation_error and frees the regex" begin
    ok, re, exc = _pc_compile("a"; setup = re -> (re.compile_bsr_flags.flags = UInt32(99)))
    @test !ok && exc == ("representation_error", ["option:bsr"]) && re.code == C_NULL
    ok, re, exc = _pc_compile("a"; setup = re -> (re.compile_newline_flags.flags = UInt32(99)))
    @test !ok && exc == ("representation_error", ["option:newline"]) && re.code == C_NULL
    # the bsr check comes before the newline check: both invalid names the bsr (the C's order)
    ok, re, exc = _pc_compile(
        "a"; setup = re -> (re.compile_bsr_flags.flags = UInt32(99); re.compile_newline_flags.flags = UInt32(99))
    )
    @test !ok && exc == ("representation_error", ["option:bsr"])
    # no row for "option:extra": pcre2_set_compile_extra_options returns 0 for every value (pcre2api, doc-only), so the C's error branch is unreachable
end

@testset "re_compile_impl: optimise runs the JIT with the regex's JIT options (the result is ignored)" begin
    buf = LK.pcre2_config_buf()
    jit = LK.pcre2_config(PC.CONFIG_JIT, buf) == 0 && LK.pcre2_config_u32(buf) == 1
    on = re -> (re.optimise_flags.flags = LK.RE_OPTIMISE; re.jit_options_flags.flags = LK.PCRE2_JIT_COMPLETE)
    ok, re, _ = _pc_compile("(a)b"; setup = on)
    @test ok && _pc_match(re.code, "ab")[1] == 2
    jit && @test _pc_info(re.code, PC.INFO_JITSIZE, UInt)[2] > 0
    LK.re_free(re)
    # JIT options without optimise: not JIT-compiled
    ok, re, _ = _pc_compile("(a)b"; setup = re -> (re.jit_options_flags.flags = LK.PCRE2_JIT_COMPLETE))
    @test ok
    jit && @test _pc_info(re.code, PC.INFO_JITSIZE, UInt) == (Cint(0), UInt(0))
    LK.re_free(re)
    # optimise with JIT options 0: the C ignores the library's refusal and the regex stays usable; doc-only (pcre2api: pcre2_jit_compile needs one of
    # COMPLETE / PARTIAL_SOFT / PARTIAL_HARD, else PCRE2_ERROR_JIT_BADOPTION): the code is not JIT-compiled
    ok, re, _ = _pc_compile("(a)b"; setup = re -> (re.optimise_flags.flags = LK.RE_OPTIMISE))
    @test ok && _pc_match(re.code, "ab")[1] == 2
    jit && @test _pc_info(re.code, PC.INFO_JITSIZE, UInt) == (Cint(0), UInt(0))
    LK.re_free(re)
end

@testset "init_capture_map: a group number above 255 needs both bytes of the name table entry; a NULL code is resource_error(pcre2_pattern_info)" begin
    ok, re, _ = _pc_compile("(a)"^256 * "(?<big_I>b)(?<other_S>c)")
    @test ok && re.capture_size == 258
    @test _pc_caps(re)[258] == ("big", LK.CAP_INTEGER)
    @test _pc_caps(re)[259] == ("other", LK.CAP_STRING)
    @test count(c -> c.name !== nothing, re.capture_names) == 2
    LK.re_free(re)

    ld = _PC_LD
    fid = LK.PL_open_foreign_frame(ld)
    re = LK.re_init_data("x")                                # code is C_NULL: pcre2_pattern_info answers PCRE2_ERROR_NULL (pcre2api, doc-only)
    @test LK.re_init_capture_map(ld, re) === false
    @test _pc_exc(ld) == ("resource_error", ["pcre2_pattern_info"])
    LK.PL_discard_foreign_frame(ld, fid)
end

@testset "re_free and re_ensure_compile_context" begin
    ok, re, _ = _pc_compile("(?<a_I>x)")
    @test ok && re.code != C_NULL && !isempty(re.capture_names)
    @test LK.re_free(re) === true
    @test re.code == C_NULL && isempty(re.capture_names)
    @test re.pattern == "(?<a_I>x)"                         # DIVERGES 19: the pattern text is kept
    @test LK.re_free(re) === true                           # twice: pcre2_code_free(NULL) is a no-op (doc-only)
    @test re.code == C_NULL

    ld = _PC_LD
    ctx = Ref{Ptr{Cvoid}}(C_NULL)
    @test LK.re_ensure_compile_context(ld, ctx) === true
    @test ctx[] != C_NULL
    p = ctx[]
    @test LK.re_ensure_compile_context(ld, ctx) === true     # an existing context is kept
    @test ctx[] == p
    LK.pcre2_compile_context_free(ctx[])
    @test LK.PL_exception(ld, 0) == 0
end
