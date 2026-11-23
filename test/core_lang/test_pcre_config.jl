# CLASS: test
# ORIGINAL: PCRE1 piece 10 (B2)'s gate - `get_pcre2_info`, `write_option_str`, `write_re_options`, `next_config`, `re_config_choice_` and `re_config_` of
# packages/pcre/pcre4pl.c (packages-pcre a5e4c885; src/pl-pcre.jl piece 10, second half). The expected values are derived, none invented: from the C text
# (the order of the `write_option_str` rows, the `<all:remainder:...>` tail, the quirks of the NEWLINE branch, the `cfg_opts` rows and which answers are
# skipped by `next_config`), from Julia's `Base.PCRE` on the same library (`pcre2_config` read through its `PCRE_LIB` for every setting `re_config_` reports),
# or from the PCRE2 documentation alone (rows say "doc-only"). The option rows compile through `re_compile_impl` (the helper `_pc_compile` is copied from
# test_pcre_compile.jl: that file is not included). Nothing here has run (written edit-only): BLIND RISKS the lane settles are (1) `PCRE2_INFO_ARGOPTIONS` keeps
# `PCRE2_NO_UTF_CHECK` (the C's comment says it does), (2) the "remainder" rows use a compile bit (`ALT_EXTENDED_CLASS` 0x08000000) and an extra bit
# (0x40) the library may not know: they run only when the compile succeeds, (3) a zeroed 1024-byte buffer gives BADMAGIC (doc-only), (4) `INFO_MATCHLIMIT`
# of a pattern with no limit set is `ERROR_UNSET` (doc-only), (5) the foreign-call context of a REDO is built as the engine does (`ret >> FRG_REDO_BITS`).
using Test, LogicKernel
const LK = LogicKernel
const PC = Base.PCRE

# TERM TYPES PER CHUNK: REFERENCE - built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "..", "core_lang", "rules_common.jl"))

const _PC_LD = _rdb(Tuple{_R, Union{Nothing, _R}}[]).ld

function _pc_term(ld, text::String)::Int
    t = LK.PL_new_term_ref(ld)
    b = Vector{UInt8}(codeunits(text))
    LK.PL_put_term_from_chars(ld, t, LK.CVT_EXCEPTION | LK.REP_UTF8, b, length(b)) ||
        error("the text does not read: $text")
    return t
end

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
function _pc_compile(pat::String; setup=re -> nothing)
    ld = _PC_LD
    fid = LK.PL_open_foreign_frame(ld)
    re = LK.re_init_data(pat)
    setup(re)
    ok = LK.re_compile_impl(ld, re, _pc_bytes(pat))
    exc = _pc_exc(ld)
    LK.PL_discard_foreign_frame(ld, fid)
    return (ok, re, exc)
end

# the option text of "a" compiled after `setup(re)` (nothing when the compile fails); the code is freed
function _pc_text(setup; pat::String="a")
    ok, re, _ = _pc_compile(pat; setup=setup)
    ok || return nothing
    s = LK.re_options_text(re)
    LK.re_free(re)
    return s
end

# `pcre2_config(what)` read through Julia's own libpcre2 binding: (rc, the 100-byte buffer)
function _pc_base_cfg(what::UInt32)
    buf = zeros(UInt8, 100)
    rc = ccall((:pcre2_config_8, PC.PCRE_LIB), Cint, (UInt32, Ptr{Cvoid}), what, buf)
    return (Int(rc), buf)
end
function _pc_base_u32(what::UInt32)
    (_, b) = _pc_base_cfg(what)
    return GC.@preserve b unsafe_load(Ptr{UInt32}(pointer(b)))
end
_pc_base_i32(what::UInt32) = reinterpret(Int32, _pc_base_u32(what))
function _pc_base_str(what::UInt32)
    (_, b) = _pc_base_cfg(what)
    return GC.@preserve b unsafe_string(pointer(b))
end

# the BSR and NEWLINE words of the build's default convention, as the C's tokens (read from the build through Julia's binding)
const _PC_BSR_DEFAULT = _pc_base_u32(PC.CONFIG_BSR) == 2 ? "BSR_ANYCRLF" : "BSR_UNICODE"
const _PC_NL_CONFIG = _pc_base_u32(PC.CONFIG_NEWLINE)
const _PC_NL_NAMES = Dict(
    1 => "NEWLINE_CR",
    2 => "NEWLINE_LF",
    3 => "NEWLINE_CRLF",
    4 => "NEWLINE_ANY",
    5 => "NEWLINE_ANYCRLF",
    6 => "NEWLINE_NUL"
)
# the C prints no NEWLINE token when the context newline is CR, LF or CRLF and equals the build's default
_pc_nl_tokens(v::Integer) =
    (v in (1, 2, 3) && v == _PC_NL_CONFIG) ? String[] : [_PC_NL_NAMES[Int(v)]]
const _PC_DEFAULT_TOKENS = vcat([_PC_BSR_DEFAULT], _pc_nl_tokens(_PC_NL_CONFIG))

_pc_join(tokens...) = join(vcat(tokens...), " ")

# ----------------------------------------------------------------------------------------------------------------------
@testset "re_get_pcre2_info: no code is silent, a good info is its value, a refusal is written as <descr:ERROR_...>" begin
    re = LK.re_init_data("")
    io = IOBuffer()
    @test LK.re_get_pcre2_info(io, re, LK.PCRE2_INFO_BSR, "INFO_BSR") === nothing    # C: `!re->re_compiled` -> false, nothing written
    @test String(take!(io)) == ""
    ok, re, _ = _pc_compile("(a)(b)")
    @test ok
    @test LK.re_get_pcre2_info(io, re, LK.PCRE2_INFO_CAPTURECOUNT, "INFO_CAPTURECOUNT") ==
        UInt32(2)
    @test String(take!(io)) == ""
    @test LK.re_get_pcre2_info(io, re, LK.PCRE2_INFO_BSR, "INFO_BSR") ==
        _pc_base_u32(PC.CONFIG_BSR)
    @test String(take!(io)) == ""
    @test LK.re_get_pcre2_info(io, re, UInt32(0xFFFFFFFF), "INFO_X") === nothing
    @test String(take!(io)) == "<INFO_X:ERROR_BADOPTION>"
    # PCRE2_INFO_MATCHLIMIT of a pattern with no limit set: ERROR_UNSET (doc-only: pcre2api "PCRE2_ERROR_UNSET if no limit was set")
    @test LK.re_get_pcre2_info(io, re, PC.INFO_MATCHLIMIT, "INFO_MATCHLIMIT") === nothing
    @test String(take!(io)) == "<INFO_MATCHLIMIT:ERROR_UNSET>"
    LK.re_free(re)
    # a buffer that is not compiled code: ERROR_BADMAGIC (doc-only: pcre2api, the magic number is checked first)
    junk = zeros(UInt8, 1024)
    re2 = LK.re_init_data("")
    GC.@preserve junk begin
        re2.code = Ptr{Cvoid}(pointer(junk))
        @test LK.re_get_pcre2_info(io, re2, LK.PCRE2_INFO_BSR, "INFO_BSR") === nothing
        @test String(take!(io)) == "<INFO_BSR:ERROR_BADMAGIC>"
        # write_re_options: the four refusals are written back to back (get_pcre2_info writes no separator), the match section adds nothing
        sep = Ref("")
        LK.re_write_re_options(io, sep, re2)
        @test String(take!(io)) ==
            "<INFO_ARGOPTIONS:ERROR_BADMAGIC><INFO_EXTRAOPTIONS:ERROR_BADMAGIC><INFO_BSR:ERROR_BADMAGIC><INFO_NEWLINE:ERROR_BADMAGIC>"
        @test sep[] == ""
        re2.code = C_NULL
    end
end

@testset "write_option_str: a set flag is written after the separator, cleared, and the separator becomes a space" begin
    io = IOBuffer()
    sep = Ref("")
    flags = Ref(LK.PCRE2_CASELESS | LK.PCRE2_DOTALL)
    LK.re_write_option_str(io, sep, flags, LK.PCRE2_CASELESS, "CASELESS")
    @test String(take!(io)) == "CASELESS" && sep[] == " " && flags[] == LK.PCRE2_DOTALL
    LK.re_write_option_str(io, sep, flags, LK.PCRE2_DOTALL, "DOTALL")
    @test String(take!(io)) == " DOTALL" && sep[] == " " && flags[] == 0
    LK.re_write_option_str(io, sep, flags, LK.PCRE2_DOTALL, "DOTALL")              # no longer set: nothing, nothing changes
    @test String(take!(io)) == "" && sep[] == " " && flags[] == 0
    sep2 = Ref("")
    flags2 = Ref(LK.PCRE2_UCP)
    LK.re_write_option_str(io, sep2, flags2, LK.PCRE2_MULTILINE, "MULTILINE")      # another flag set: nothing
    @test String(take!(io)) == "" && sep2[] == "" && flags2[] == LK.PCRE2_UCP
end

@testset "the remainder tail of a flag word: written after the separator, which becomes a space; nothing for zero" begin
    io = IOBuffer()
    sep = Ref("")
    LK._re_write_remainder(io, sep, Ref(UInt32(0)))
    @test String(take!(io)) == "" && sep[] == ""
    LK._re_write_remainder(io, sep, Ref(UInt32(0x00008000)))
    @test String(take!(io)) == "<all:remainder:0x00008000>" && sep[] == " "
    LK._re_write_remainder(io, sep, Ref(UInt32(0xA5)))
    @test String(take!(io)) == " <all:remainder:0x000000a5>" && sep[] == " "         # %08x: lower case hex, 8 digits, zero padded
end

@testset "write_re_options: no code" begin
    re = LK.re_init_data("")
    @test LK.re_options_text(re) == "<no re_compiled>"                             # the match flags default to NO_UTF_CHECK only
    re.match_options_flags.flags = LK.PCRE2_NO_UTF_CHECK | LK.PCRE2_NOTBOL
    @test LK.re_options_text(re) == "<no re_compiled> NOTBOL"
    io = IOBuffer()
    sep = Ref("::")
    LK.re_write_re_options(io, sep, LK.re_init_data(""))
    @test String(take!(io)) == "::<no re_compiled>" && sep[] == " "                  # the separator is the caller's
end

@testset "write_re_options: the default regex (UTF + NO_UTF_CHECK, build's BSR and newline) names only the BSR and the non-default newline" begin
    @test _pc_text(re -> nothing) == _pc_join(_PC_DEFAULT_TOKENS)
    @test _pc_text(re -> nothing)[1] != ' '                                         # no leading separator
end

@testset "write_re_options: the compile options, one row per name of the C's list (the C's order is the table order)" begin
    names = [
        "ALLOW_EMPTY_CLASS", "ALT_BSUX", "AUTO_CALLOUT", "CASELESS", "DOLLAR_ENDONLY",
        "DOTALL", "DUPNAMES", "EXTENDED", "FIRSTLINE",
        "MATCH_UNSET_BACKREF", "MULTILINE", "NEVER_UCP", "NO_AUTO_CAPTURE",
        "NO_AUTO_POSSESS", "NO_DOTSTAR_ANCHOR",
        "NO_START_OPTIMIZE", "UCP", "UNGREEDY", "NEVER_BACKSLASH_C", "ALT_CIRCUMFLEX",
        "ALT_VERBNAMES", "USE_OFFSET_LIMIT",
        "EXTENDED_MORE", "MATCH_INVALID_UTF"
    ]
    for n in names
        f = getfield(LK, Symbol("PCRE2_", n))
        @test _pc_text(re -> (re.compile_options_flags.flags |= f)) ==
            _pc_join(n, _PC_DEFAULT_TOKENS)
    end
    for (n, shown) in
        (("ANCHORED", "compile-ANCHORED"), ("ENDANCHORED", "compile-ENDANCHORED"))
        f = getfield(LK, Symbol("PCRE2_", n))
        @test _pc_text(re -> (re.compile_options_flags.flags |= f)) ==
            _pc_join(shown, _PC_DEFAULT_TOKENS)
    end
    # NEVER_UTF excludes UTF: the compile options are NO_UTF_CHECK|NEVER_UTF, so "compile-~UTF" shows
    @test _pc_text(
        re -> (re.compile_options_flags.flags = LK.PCRE2_NO_UTF_CHECK | LK.PCRE2_NEVER_UTF)
    ) ==
        _pc_join("compile-~UTF", "NEVER_UTF", _PC_DEFAULT_TOKENS)
    # LITERAL allows only a few other options (pcre2api, doc-only): UTF and NO_UTF_CHECK are among them
    @test _pc_text(re -> (re.compile_options_flags.flags |= LK.PCRE2_LITERAL)) ==
        _pc_join("LITERAL", _PC_DEFAULT_TOKENS)
    # the defaults are shown as their absence
    @test _pc_text(re -> (re.compile_options_flags.flags = LK.PCRE2_UTF)) ==
        _pc_join("compile-~NO_UTF_CHECK", _PC_DEFAULT_TOKENS)
    @test _pc_text(re -> (re.compile_options_flags.flags = LK.PCRE2_NO_UTF_CHECK)) ==
        _pc_join("compile-~UTF", _PC_DEFAULT_TOKENS)
    @test _pc_text(re -> (re.compile_options_flags.flags = UInt32(0))) ==
        _pc_join("compile-~NO_UTF_CHECK", "compile-~UTF", _PC_DEFAULT_TOKENS)
    # the order of the C: ANCHORED, ..., CASELESS, ..., UCP, ... even when set in another order
    @test _pc_text(
        re -> (
            re.compile_options_flags.flags |=
                LK.PCRE2_UCP | LK.PCRE2_CASELESS | LK.PCRE2_ANCHORED
        )
    ) ==
        _pc_join("compile-ANCHORED", "CASELESS", "UCP", _PC_DEFAULT_TOKENS)
    # a compile bit the table does not name: the remainder (ALT_EXTENDED_CLASS 0x08000000 exists from pcre2 10.42: skipped when the library refuses it)
    rem = _pc_text(re -> (re.compile_options_flags.flags |= UInt32(0x08000000)))
    rem === nothing ||
        @test rem == _pc_join("<all:remainder:0x08000000>", _PC_DEFAULT_TOKENS)
end

@testset "write_re_options: the compile-context (extra) options" begin
    for n in (
        "EXTRA_ALLOW_SURROGATE_ESCAPES",
        "EXTRA_BAD_ESCAPE_IS_LITERAL",
        "EXTRA_MATCH_WORD",
        "EXTRA_MATCH_LINE",
        "EXTRA_ESCAPED_CR_IS_LF",
        "EXTRA_ALT_BSUX"
    )
        f = getfield(LK, Symbol("PCRE2_", n))
        @test _pc_text(re -> (re.compile_ctx_flags.flags |= f)) ==
            _pc_join(n, _PC_DEFAULT_TOKENS)
    end
    @test _pc_text(
        re -> (
            re.compile_ctx_flags.flags |=
                LK.PCRE2_EXTRA_MATCH_LINE | LK.PCRE2_EXTRA_ALLOW_SURROGATE_ESCAPES |
                LK.PCRE2_EXTRA_MATCH_WORD
        )
    ) ==
        _pc_join(
        "EXTRA_ALLOW_SURROGATE_ESCAPES",
        "EXTRA_MATCH_WORD",
        "EXTRA_MATCH_LINE",
        _PC_DEFAULT_TOKENS
    )
    # the extra options come after the compile options and before the BSR
    @test _pc_text(
        re -> (
            re.compile_ctx_flags.flags |= LK.PCRE2_EXTRA_MATCH_WORD;
            re.compile_options_flags.flags |= LK.PCRE2_CASELESS
        )
    ) ==
        _pc_join("CASELESS", "EXTRA_MATCH_WORD", _PC_DEFAULT_TOKENS)
    # an extra bit the table does not name (0x40 is a later option of pcre2): the remainder, when the library accepts it
    rem = _pc_text(re -> (re.compile_ctx_flags.flags |= UInt32(0x40)))
    rem === nothing ||
        @test rem == _pc_join("<all:remainder:0x00000040>", _PC_DEFAULT_TOKENS)
end

@testset "write_re_options: the BSR and the newline convention" begin
    @test _pc_text(re -> (re.compile_bsr_flags.flags = LK.PCRE2_BSR_ANYCRLF)) ==
        _pc_join("BSR_ANYCRLF", _pc_nl_tokens(_PC_NL_CONFIG))
    @test _pc_text(re -> (re.compile_bsr_flags.flags = LK.PCRE2_BSR_UNICODE)) ==
        _pc_join("BSR_UNICODE", _pc_nl_tokens(_PC_NL_CONFIG))
    for v in (
        LK.PCRE2_NEWLINE_CR,
        LK.PCRE2_NEWLINE_LF,
        LK.PCRE2_NEWLINE_CRLF,
        LK.PCRE2_NEWLINE_ANY,
        LK.PCRE2_NEWLINE_ANYCRLF
    )
        # CR, LF, CRLF equal to the build's default print nothing; every other value prints its name after the BSR
        @test _pc_text(re -> (re.compile_newline_flags.flags = v)) ==
            _pc_join(_PC_BSR_DEFAULT, _pc_nl_tokens(v))
    end
    # NEWLINE_NUL exists from pcre2 10.38 (pcre2api; doc-only): the row runs when the library accepts it
    nul = _pc_text(re -> (re.compile_newline_flags.flags = UInt32(6)))
    nul === nothing || @test nul == _pc_join(_PC_BSR_DEFAULT, "NEWLINE_NUL")
    # the newline token comes after the BSR and before the match options
    @test _pc_text(
        re -> (
            re.compile_newline_flags.flags=LK.PCRE2_NEWLINE_ANY;
            re.match_options_flags.flags |= LK.PCRE2_NOTEOL
        )
    ) ==
        _pc_join(_PC_BSR_DEFAULT, "NEWLINE_ANY", "NOTEOL")
end

@testset "write_re_options: the match options (the 17 names of the C's list, the NO_UTF_CHECK default, the remainder)" begin
    ok, re, _ = _pc_compile("a")
    @test ok
    names = [
        "NOTBOL", "NOTEOL", "NOTEMPTY", "NOTEMPTY_ATSTART", "PARTIAL_SOFT", "PARTIAL_HARD",
        "DFA_RESTART", "DFA_SHORTEST", "SUBSTITUTE_GLOBAL",
        "SUBSTITUTE_EXTENDED", "SUBSTITUTE_UNSET_EMPTY", "SUBSTITUTE_UNKNOWN_UNSET",
        "SUBSTITUTE_OVERFLOW_LENGTH", "NO_JIT", "COPY_MATCHED_SUBJECT"
    ]
    for n in names
        f = getfield(LK, Symbol("PCRE2_", n))
        re.match_options_flags.flags = LK.PCRE2_NO_UTF_CHECK | f
        @test LK.re_options_text(re) == _pc_join(_PC_DEFAULT_TOKENS, n)
    end
    for (n, shown) in (("ANCHORED", "match-ANCHORED"), ("ENDANCHORED", "match-ENDANCHORED"))
        f = getfield(LK, Symbol("PCRE2_", n))
        re.match_options_flags.flags = LK.PCRE2_NO_UTF_CHECK | f
        @test LK.re_options_text(re) == _pc_join(_PC_DEFAULT_TOKENS, shown)
    end
    re.match_options_flags.flags = UInt32(0)                                        # NO_UTF_CHECK clear: shown
    @test LK.re_options_text(re) == _pc_join(_PC_DEFAULT_TOKENS, "match-~NO_UTF_CHECK")
    re.match_options_flags.flags = LK.PCRE2_NOTBOL | LK.PCRE2_ANCHORED | LK.PCRE2_NOTEMPTY       # the C's order again
    @test LK.re_options_text(re) == _pc_join(
        _PC_DEFAULT_TOKENS, "match-~NO_UTF_CHECK", "match-ANCHORED", "NOTBOL", "NOTEMPTY"
    )
    re.match_options_flags.flags = LK.PCRE2_NO_UTF_CHECK | UInt32(0x00008000)       # a match bit the table does not name
    @test LK.re_options_text(re) ==
        _pc_join(_PC_DEFAULT_TOKENS, "<all:remainder:0x00008000>")
    re.match_options_flags.flags =
        LK.PCRE2_NO_UTF_CHECK | UInt32(0x00008000) | LK.PCRE2_NOTBOL
    @test LK.re_options_text(re) ==
        _pc_join(_PC_DEFAULT_TOKENS, "NOTBOL", "<all:remainder:0x00008000>")
    LK.re_free(re)
end

# ----------------------------------------------------------------------------------------------------------------------
@testset "re_next_config: the 0-based index of the next row that is neither invalid nor for PCRE1 compatibility" begin
    # rows (0-based): 0 bsr2 1 compiled_widths 2 depthlimit 3 heaplimit 4 jit 5 jittarget 6 link_size* 7 linksize 8 match_limit* 9 match_limit_recursion*
    # 10 matchlimit 11 never_backslash_c 12 newline2 13 parens_limit* 14 parenslimit 15 posix_malloc_threshold* 16 stackrecurse 17 unicode
    # 18 unicode_properties* 19 unicode_version 20 utf8* 21 version (* = skipped)
    expected = [
        0,
        1,
        2,
        3,
        4,
        5,
        7,
        7,
        10,
        10,
        10,
        11,
        12,
        14,
        14,
        16,
        16,
        17,
        19,
        19,
        21,
        21,
        -1,
        -1
    ]
    @test [LK.re_next_config(i) for i in 0:23] == expected
    @test LK.re_next_config(100) == -1
end

# the answers of re_config_choice_ from the first call, REDO contexts built as the engine does (`ret >> FRG_REDO_BITS`)
function _pc_choices()
    ld = _PC_LD
    fid = LK.PL_open_foreign_frame(ld)
    got = String[]
    rets = UInt[]
    ctx = LK.foreign_context{_R}(LK.FRG_FIRST_CALL, UInt(0), nothing)
    for _ in 1:40
        t = LK.PL_new_term_ref(ld)
        r = LK.re_config_choice_(ld, t, ctx)
        r == LK.FFALSE && break
        push!(rets, r)
        na = LK.PL_get_name_arity(ld, t)
        push!(got, na === nothing ? "?" : string(LK.sym_text(na[1]), "/", na[2]))
        ctx = LK.foreign_context{_R}(LK.FRG_REDO, UInt(r >> LK.FRG_REDO_BITS), nothing)
    end
    LK.PL_discard_foreign_frame(ld, fid)
    return (got, rets)
end

@testset "re_config_choice_: the 15 options in table order, then failure; cut succeeds; a bound argument is an uninstantiation error" begin
    got, rets = _pc_choices()
    @test got == [
        "bsr2/1", "compiled_widths/1", "depthlimit/1", "heaplimit/1", "jit/1",
        "jittarget/1", "linksize/1", "matchlimit/1",
        "never_backslash_c/1", "newline2/1", "parenslimit/1", "stackrecurse/1", "unicode/1",
        "unicode_version/1", "version/1"
    ]
    @test rets[1] == LK.PL_retry(1)                                                # the context is the 0-based index + 1
    @test rets[end] == LK.PL_retry(22)                                             # `version` is row 21
    ld = _PC_LD
    fid = LK.PL_open_foreign_frame(ld)
    ctx = LK.foreign_context{_R}(LK.FRG_CUTTED, UInt(0), nothing)
    @test LK.re_config_choice_(ld, LK.PL_new_term_ref(ld), ctx) == LK.FTRUE
    @test LK.PL_exception(ld, 0) == 0
    # a REDO context past the end fails
    ctx = LK.foreign_context{_R}(LK.FRG_REDO, UInt(22), nothing)
    @test LK.re_config_choice_(ld, LK.PL_new_term_ref(ld), ctx) == LK.FFALSE
    # a bound argument: uninstantiation_error(Choice), false
    ctx = LK.foreign_context{_R}(LK.FRG_FIRST_CALL, UInt(0), nothing)
    @test LK.re_config_choice_(ld, _pc_term(ld, "foo"), ctx) == LK.FFALSE
    @test _pc_exc(ld) == ("uninstantiation_error", ["foo"])
    # a REDO with a bound argument checks the argument too
    ctx = LK.foreign_context{_R}(LK.FRG_REDO, UInt(3), nothing)
    @test LK.re_config_choice_(ld, _pc_term(ld, "foo"), ctx) == LK.FFALSE
    @test _pc_exc(ld) == ("uninstantiation_error", ["foo"])
    # a REDO from the middle continues there: context 8 = after row 7 (linksize), the next answer is `matchlimit`
    ctx = LK.foreign_context{_R}(LK.FRG_REDO, UInt(8), nothing)
    t = LK.PL_new_term_ref(ld)
    r = LK.re_config_choice_(ld, t, ctx)
    @test r == LK.PL_retry(11)
    @test LK.sym_text(LK.PL_get_name_arity(ld, t)[1]) == "matchlimit"
    LK.PL_discard_foreign_frame(ld, fid)
end

# ----------------------------------------------------------------------------------------------------------------------
# re_config_(Name(Arg)): (result, the text of Arg afterwards or nothing when Arg is not an atomic), the pending error cleared
function _pc_cfg(text::String)
    ld = _PC_LD
    fid = LK.PL_open_foreign_frame(ld)
    t = _pc_term(ld, text)
    r = LK.re_config_(ld, t)
    val = nothing
    a = LK.PL_new_term_ref(ld)
    if LK.PL_get_name_arity(ld, t) !== nothing && LK._PL_get_arg(ld, 1, t, a)
        txt = LK.PL_get_text(ld, a, LK.CVT_ATOMIC)
        txt === nothing || (val = LK.text_string(txt))
    end
    isint = LK.PL_get_name_arity(ld, t) !== nothing && LK.PL_get_integer(ld, a) !== nothing
    exc = _pc_exc(ld)
    LK.PL_discard_foreign_frame(ld, fid)
    return (r == LK.FTRUE, val, isint, exc)
end

@testset "re_config_: the integer settings are read from the library (and the PCRE1 names answer the same)" begin
    for (name, what) in (
        ("compiled_widths", PC.CONFIG_COMPILED_WIDTHS),
        ("depthlimit", PC.CONFIG_DEPTHLIMIT), ("heaplimit", PC.CONFIG_HEAPLIMIT),
        ("linksize", PC.CONFIG_LINKSIZE), ("link_size", PC.CONFIG_LINKSIZE),
        ("matchlimit", PC.CONFIG_MATCHLIMIT),
        ("match_limit", PC.CONFIG_MATCHLIMIT), ("parenslimit", PC.CONFIG_PARENSLIMIT),
        ("parens_limit", PC.CONFIG_PARENSLIMIT)
    )
        v = string(_pc_base_i32(what))
        ok, val, isint, exc = _pc_cfg("$name(_)")
        @test ok && val == v && isint && exc === nothing
        @test _pc_cfg("$name($v)")[1]                                              # a bound, equal value
        @test !_pc_cfg("$name($(parse(Int, v) + 1))")[1]                           # a bound, other value
        @test !_pc_cfg("$name(foo)")[1]                                            # an atom is not the integer
    end
end

@testset "re_config_: the boolean settings, true/false atoms (and on/off), utf8 = unicode" begin
    for (name, what) in (
        ("jit", PC.CONFIG_JIT), ("never_backslash_c", PC.CONFIG_NEVER_BACKSLASH_C),
        ("stackrecurse", PC.CONFIG_STACKRECURSE),
        ("unicode", PC.CONFIG_UNICODE), ("utf8", PC.CONFIG_UNICODE)
    )
        b = _pc_base_i32(what) != 0
        ok, val, isint, exc = _pc_cfg("$name(_)")
        @test ok && val == string(b) && !isint && exc === nothing
        @test _pc_cfg("$name($b)")[1]
        @test !_pc_cfg("$name($(!b))")[1]
        @test _pc_cfg("$name($(b ? "on" : "off"))")[1]
    end
    @test _pc_cfg("unicode_properties(_)")[1:2] == (true, "true")                  # CFG_TRUE_BKWD: no pcre2_config call is needed
    @test !_pc_cfg("unicode_properties(false)")[1]
end

@testset "re_config_: the string settings, bsr2 and newline2" begin
    @test _pc_cfg("version(_)")[1:2] == (true, _pc_base_str(PC.CONFIG_VERSION))
    @test _pc_cfg("unicode_version(_)")[1:2] ==
        (true, _pc_base_str(PC.CONFIG_UNICODE_VERSION))
    @test !_pc_cfg("version(wrong)")[1]
    ok, val, isint, _ = _pc_cfg("version(_)")
    @test !isint                                                                   # an atom
    (rc, _) = _pc_base_cfg(PC.CONFIG_JITTARGET)                                    # CFG_STRINGBUF_OPT: false when the library says BADOPTION
    jt = _pc_cfg("jittarget(_)")
    @test jt[1] == (rc >= 0)
    rc >= 0 && @test jt[2] == _pc_base_str(PC.CONFIG_JITTARGET)
    @test _pc_cfg("bsr2(_)")[1:2] ==
        (true, _pc_base_u32(PC.CONFIG_BSR) == 1 ? "unicode" : "anycrlf")
    @test _pc_cfg("bsr2(unicode)")[1] == (_pc_base_u32(PC.CONFIG_BSR) == 1)
    @test _pc_cfg("bsr2(anycrlf)")[1] == (_pc_base_u32(PC.CONFIG_BSR) == 2)
    nlname = Dict(
        1 => "cr", 2 => "lf", 3 => "crlf", 4 => "any", 5 => "anycrlf", 6 => "nul"
    )[Int(_PC_NL_CONFIG)]
    @test _pc_cfg("newline2(_)")[1:2] == (true, nlname)
    @test !_pc_cfg("newline2(" * (nlname == "lf" ? "cr" : "lf") * ")")[1]
end

@testset "re_config_: invalid and unknown options, non-compounds, other arities: silent failure" begin
    for t in (
        "match_limit_recursion(_)",
        "posix_malloc_threshold(_)",
        "bsr(_)",
        "newline(_)",
        "nonesuch(_)",
        "recursion_limit(_)"
    )
        ok, _, _, exc = _pc_cfg(t)
        @test !ok && exc === nothing
    end
    for t in ("version", "42", "version(_, _)", "'version'(_, _, _)")
        ok, _, _, exc = _pc_cfg(t)
        @test !ok && exc === nothing
    end
    ok, _, _, exc = _pc_cfg("_")                                                   # not a compound: false, no error (was: type_error(compound, _))
    @test !ok && exc === nothing
    # every row of the table is answered by its name only: a name that is a prefix or an extension is another option
    @test !_pc_cfg("versio(_)")[1] && !_pc_cfg("versions(_)")[1]
end
