# ORIGINAL: PCRE1 piece 2's gate - the option and flag tables of packages/pcre/pcre4pl.c (cap_type, re_options_flags, set_flag, effective_bool,
# re_optdefs / re_optbsrs / re_optnewlines / re_optcompats / re_optcaptures, lookup_optdef, lookup_and_apply_optdef[_arg]), src/pl-pcre.jl.
# NO oracle and no libpcre2: the table rows were compared with pcre4pl.c (packages-pcre a5e4c885, lines 488-740) by a python script row by row
# (name, flag, mode: 66 + 2 + 6 + 0 + 7 rows, no difference), the counts per mode are that script's; the PCRE2_* values are compared with Julia's
# own `Base.PCRE` (pcre2.h 10.47) below. Nothing here has run (no Julia process was started to write this file).
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "..", "core_lang", "rules_common.jl"))

const _PO_DB = _rdb(Tuple{_R, Union{Nothing, _R}}[])
const _PO_LD = _PO_DB.ld

function _po_term(ld, text::String)::Int
    t = LK.PL_new_term_ref(ld)
    b = Vector{UInt8}(codeunits(text))
    LK.PL_put_term_from_chars(ld, t, LK.CVT_EXCEPTION | LK.REP_UTF8, b, length(b)) || error("the text does not read: $text")
    return t
end

# The pending error(Formal, _) as (Formal's name, [its arguments' texts]); clears it; nothing when none is pending.
function _po_exc(ld)
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
                if txt !== nothing
                    push!(args, LK.text_string(txt))
                else
                    nb = LK.PL_get_name_arity(ld, a)
                    push!(args, nb === nothing ? "?" : string(LK.sym_text(nb[1]), "/", nb[2]))
                end
            end
            r = (LK.sym_text(na[1]), args)
        end
    end
    LK.PL_clear_exception(ld)
    return r
end

@testset "cap_type and its names (pcre4pl.c cap_type, cap_type_str)" begin
    names = ("CAP_DEFAULT", "CAP_STRING", "CAP_ATOM", "CAP_INTEGER", "CAP_FLOAT", "CAP_NUMBER", "CAP_TERM", "CAP_RANGE")
    for (i, nm) in enumerate(names)
        @test getfield(LK, Symbol(nm)) == i - 1             # the enum is counted from 0 in this order
        @test LK.re_cap_type_str(i - 1) == nm
    end
    @test LK.re_cap_type_str(8) == "CAP_???"
    @test LK.re_cap_type_str(-1) == "CAP_???"
end

@testset "the PCRE2_* values are those of pcre2.h (Base.PCRE)" begin
    names = (
        "ALLOW_EMPTY_CLASS", "ALT_BSUX", "ALT_CIRCUMFLEX", "ALT_VERBNAMES", "ANCHORED", "AUTO_CALLOUT", "BSR_ANYCRLF", "BSR_UNICODE",
        "CASELESS", "COPY_MATCHED_SUBJECT", "DFA_RESTART", "DFA_SHORTEST", "DOLLAR_ENDONLY", "DOTALL", "DUPNAMES", "ENDANCHORED",
        "EXTENDED", "EXTENDED_MORE", "EXTRA_ALLOW_SURROGATE_ESCAPES", "EXTRA_ALT_BSUX", "EXTRA_BAD_ESCAPE_IS_LITERAL",
        "EXTRA_ESCAPED_CR_IS_LF", "EXTRA_MATCH_LINE", "EXTRA_MATCH_WORD", "FIRSTLINE", "JIT_COMPLETE", "JIT_INVALID_UTF",
        "JIT_PARTIAL_HARD", "JIT_PARTIAL_SOFT", "LITERAL", "MATCH_INVALID_UTF", "MATCH_UNSET_BACKREF", "MULTILINE", "NEVER_BACKSLASH_C",
        "NEVER_UCP", "NEVER_UTF", "NEWLINE_ANY", "NEWLINE_ANYCRLF", "NEWLINE_CR", "NEWLINE_CRLF", "NEWLINE_LF", "NEWLINE_NUL", "NOTBOL",
        "NOTEMPTY", "NOTEMPTY_ATSTART", "NOTEOL", "NO_AUTO_CAPTURE", "NO_AUTO_POSSESS", "NO_DOTSTAR_ANCHOR", "NO_JIT", "NO_START_OPTIMIZE",
        "NO_UTF_CHECK", "PARTIAL_HARD", "PARTIAL_SOFT", "SUBSTITUTE_EXTENDED", "SUBSTITUTE_GLOBAL", "SUBSTITUTE_OVERFLOW_LENGTH",
        "SUBSTITUTE_UNKNOWN_UNSET", "SUBSTITUTE_UNSET_EMPTY", "UCP", "UNGREEDY", "USE_OFFSET_LIMIT", "UTF",
    )
    @test length(names) == 63
    for n in names
        mine = getfield(LK, Symbol("PCRE2_", n))
        @test mine isa UInt32
        @test mine == getproperty(Base.PCRE, Symbol(n))
    end
    # the masks
    @test LK.OPTBSR_MASK == UInt32(3)
    @test LK.OPTNEWLINE_MASK == UInt32(7)             # CR|LF|CRLF|ANY|ANYCRLF = 1|2|3|4|5 (NUL, 6, fits in these bits too)
    @test LK.OPTCAPTURE_MASK == UInt32(7)
    @test LK.OPTCOMPAT_MASK == UInt32(0)
    @test LK.OPTSTART_MASK == UInt32(0xffffffff)
    # the mode bits
    @test (LK.RE_NEG, LK.RE_COMP_BOOL, LK.RE_COMP_BSR, LK.RE_COMP_NEWLINE, LK.RE_COMP_OPTIMISE, LK.RE_COMP_COMPAT, LK.RE_COMP_CAPTURE,
           LK.RE_COMPCTX_BOOL, LK.RE_COMPJIT_BOOL, LK.RE_MATCH_BOOL, LK.RE_MATCH_START, LK.RE_SUBS_BOOL) ==
          UInt32.((0x1, 0x10, 0x20, 0x40, 0x80, 0x100, 0x200, 0x400, 0x800, 0x1000, 0x2000, 0x4000))
    @test LK.RE_OPTIMISE == UInt32(1)
end

@testset "the option tables (pcre4pl.c re_optdefs and the four small ones)" begin
    @test (length(LK.re_optdefs), length(LK.re_optbsrs), length(LK.re_optnewlines), length(LK.re_optcompats), length(LK.re_optcaptures)) ==
          (66, 2, 6, 0, 7)
    # rows per mode bit (python over the C text): the modes of a row are an OR
    cnt(bit) = count(d -> (d.mode & bit) != 0, LK.re_optdefs)
    @test cnt(LK.RE_COMP_BOOL) == 32 && cnt(LK.RE_MATCH_BOOL) == 18 && cnt(LK.RE_NEG) == 10
    @test cnt(LK.RE_COMPCTX_BOOL) == 6 && cnt(LK.RE_COMPJIT_BOOL) == 4
    @test cnt(LK.RE_COMP_BSR) == 2 && cnt(LK.RE_COMP_NEWLINE) == 2 && cnt(LK.RE_COMP_OPTIMISE) == 2
    @test cnt(LK.RE_COMP_CAPTURE) == 1 && cnt(LK.RE_COMP_COMPAT) == 1 && cnt(LK.RE_MATCH_START) == 1
    @test [d.name for d in LK.re_optdefs if d.flag == 0] ==
          ["bsr", "bsr2", "capture_type", "compat", "newline", "newline2", "optimise", "optimize", "start"]
    # the first and the last row, and rows that sit on a boundary of a group
    @test LK.re_optdefs[1] == LK.re_optdef("bsr", 0, LK.RE_COMP_BSR)
    @test LK.re_optdefs[10] == LK.re_optdef("anchored", LK.PCRE2_ANCHORED, LK.RE_COMP_BOOL | LK.RE_MATCH_BOOL)
    @test LK.re_optdefs[end] == LK.re_optdef("copy_matched_subject", LK.PCRE2_COPY_MATCHED_SUBJECT, LK.RE_MATCH_BOOL)
    # two names for one flag, one of them inverted
    @test LK.re_lookup_optdef(LK.re_optdefs, "auto_capture") == LK.re_optdef("auto_capture", LK.PCRE2_NO_AUTO_CAPTURE, LK.RE_COMP_BOOL | LK.RE_NEG)
    @test LK.re_lookup_optdef(LK.re_optdefs, "no_auto_capture") == LK.re_optdef("no_auto_capture", LK.PCRE2_NO_AUTO_CAPTURE, LK.RE_COMP_BOOL)
    @test LK.re_lookup_optdef(LK.re_optdefs, "greedy") == LK.re_optdef("greedy", LK.PCRE2_UNGREEDY, LK.RE_COMP_BOOL | LK.RE_NEG)
    @test LK.re_lookup_optdef(LK.re_optdefs, "ungreedy") == LK.re_optdef("ungreedy", LK.PCRE2_UNGREEDY, LK.RE_COMP_BOOL)
    @test LK.re_lookup_optdef(LK.re_optdefs, "jit") == LK.re_optdef("jit", LK.PCRE2_NO_JIT, LK.RE_MATCH_BOOL | LK.RE_NEG)
    @test LK.re_lookup_optdef(LK.re_optdefs, "utf_check") == LK.re_optdef("utf_check", LK.PCRE2_NO_UTF_CHECK, LK.RE_COMP_BOOL | LK.RE_MATCH_BOOL)
    @test LK.re_lookup_optdef(LK.re_optdefs, "bol").mode == (LK.RE_MATCH_BOOL | LK.RE_NEG)
    @test LK.re_lookup_optdef(LK.re_optdefs, "extra_match_word") == LK.re_optdef("extra_match_word", LK.PCRE2_EXTRA_MATCH_WORD, LK.RE_COMPCTX_BOOL)
    @test LK.re_lookup_optdef(LK.re_optdefs, "jit_partial_hard") == LK.re_optdef("jit_partial_hard", LK.PCRE2_JIT_PARTIAL_HARD, LK.RE_COMPJIT_BOOL)
    @test LK.re_lookup_optdef(LK.re_optdefs, "start") == LK.re_optdef("start", 0, LK.RE_MATCH_START)
    @test LK.re_lookup_optdef(LK.re_optdefs, "nope") === nothing
    @test LK.re_lookup_optdef(LK.re_optdefs, "") === nothing
    @test LK.re_lookup_optdef(LK.re_optdefs, "Caseless") === nothing       # atoms are compared exactly
    # the same name in two tables is a different row
    @test LK.re_lookup_optdef(LK.re_optbsrs, "anycrlf").flag == 2 && LK.re_lookup_optdef(LK.re_optnewlines, "anycrlf").flag == 5
    @test [d.flag for d in LK.re_optnewlines] == UInt32[1, 2, 3, 4, 5, 6]
    @test [d.name for d in LK.re_optnewlines] == ["cr", "lf", "crlf", "any", "anycrlf", "nul"]
    @test [(d.name, d.flag) for d in LK.re_optbsrs] == [("anycrlf", 2), ("unicode", 1)]
    @test [(d.name, d.flag) for d in LK.re_optcaptures] ==
          [("atom", 2), ("float", 4), ("integer", 3), ("number", 5), ("range", 7), ("string", 1), ("term", 6)]
    @test all(d -> d.mode == LK.RE_COMP_CAPTURE, LK.re_optcaptures)
    @test all(d -> d.mode == LK.RE_COMP_NEWLINE, LK.re_optnewlines)
    @test all(d -> d.mode == LK.RE_COMP_BSR, LK.re_optbsrs)
    # a capture type's flag is the cap_type number
    @test LK.re_lookup_optdef(LK.re_optcaptures, "term").flag == UInt32(LK.CAP_TERM)
end

@testset "re_init_data, re_reset_match_flags! (init_re_data, get_re_copy)" begin
    re = LK.re_init_data()
    @test re.compile_options_flags.flags == (LK.PCRE2_UTF | LK.PCRE2_NO_UTF_CHECK) == UInt32(0x40080000)
    @test re.match_options_flags.flags == LK.PCRE2_NO_UTF_CHECK
    @test re.capture_type.flags == UInt32(LK.CAP_STRING) && re.capture_size == 0
    for f in (re.compile_options_flags, re.capture_type, re.optimise_flags, re.jit_options_flags, re.compile_ctx_flags,
              re.compile_bsr_flags, re.compile_newline_flags, re.match_options_flags, re.start_flags)
        @test f.seen == 0
    end
    @test (re.optimise_flags.flags, re.jit_options_flags.flags, re.compile_ctx_flags.flags, re.start_flags.flags) == UInt32.((0, 0, 0, 0))
    re.match_options_flags.seen = UInt32(5); re.match_options_flags.flags = UInt32(7)
    re.start_flags.seen = UInt32(1); re.start_flags.flags = UInt32(9)
    re.compile_options_flags.seen = UInt32(4)
    LK.re_reset_match_flags!(re)
    @test (re.match_options_flags.seen, re.match_options_flags.flags) == (0, LK.PCRE2_NO_UTF_CHECK)
    @test (re.start_flags.seen, re.start_flags.flags) == (0, 0)
    @test re.compile_options_flags.seen == 4                   # the compile flags are not reset
end

@testset "re_effective_bool and re_set_flag (pcre4pl.c effective_bool, set_flag)" begin
    ld = _PO_LD
    fid = LK.PL_open_foreign_frame(ld)
    t_true, t_false, t_maybe = _po_term(ld, "true"), _po_term(ld, "false"), _po_term(ld, "maybe")
    @test LK.re_effective_bool(ld, 0) == 1                     # no argument: true
    @test LK.re_effective_bool(ld, t_true) == 1
    @test LK.re_effective_bool(ld, t_false) == 0
    @test LK.re_effective_bool(ld, t_maybe) == -1
    @test _po_exc(ld) == ("type_error", ["bool", "maybe"])
    m, v = UInt32(0x10), UInt32(0x10)
    # true sets the bit, false clears it, the mask bits are cleared first
    f = LK.re_options_flags(UInt32(0), UInt32(0xF0))
    @test LK.re_set_flag(ld, t_true, f, m, v, false) && (f.seen, f.flags) == (0x10, 0xF0)
    f = LK.re_options_flags(UInt32(0), UInt32(0xF0))
    @test LK.re_set_flag(ld, t_false, f, m, v, false) && (f.seen, f.flags) == (0x10, 0xE0)
    # invert: true clears, false sets
    f = LK.re_options_flags(UInt32(0), UInt32(0xF0))
    @test LK.re_set_flag(ld, t_true, f, m, v, true) && (f.seen, f.flags) == (0x10, 0xE0)
    f = LK.re_options_flags(UInt32(0), UInt32(0xE0))
    @test LK.re_set_flag(ld, t_false, f, m, v, true) && (f.seen, f.flags) == (0x10, 0xF0)
    # no argument is true
    f = LK.re_options_flags(UInt32(0), UInt32(0))
    @test LK.re_set_flag(ld, 0, f, m, v, false) && (f.seen, f.flags) == (0x10, 0x10)
    # a repeated option is ignored (the first value stays): true, then false
    f = LK.re_options_flags(UInt32(0), UInt32(0))
    @test LK.re_set_flag(ld, t_true, f, m, v, false) && LK.re_set_flag(ld, t_false, f, m, v, false) && (f.seen, f.flags) == (0x10, 0x10)
    # the seen test is on the MASK: another flag in another bit is not ignored, the same bit under another value is
    @test LK.re_set_flag(ld, t_true, f, UInt32(0x20), UInt32(0x20), false) && (f.seen, f.flags) == (0x30, 0x30)
    @test LK.re_set_flag(ld, t_false, f, UInt32(0x30), UInt32(0x20), false) && (f.seen, f.flags) == (0x30, 0x30)   # mask 0x30 overlaps: ignored
    # a multi-bit mask: the bits of the mask are cleared, then the value is set
    f = LK.re_options_flags(UInt32(0), UInt32(0xF3))
    @test LK.re_set_flag(ld, 0, f, UInt32(3), UInt32(2), false) && (f.seen, f.flags) == (3, 0xF2)
    # an error: false, with the exception, after the seen bits are set and the mask bits cleared (the C does both first)
    f = LK.re_options_flags(UInt32(0), UInt32(0xF0))
    @test LK.re_set_flag(ld, t_maybe, f, m, v, false) === false
    @test _po_exc(ld) == ("type_error", ["bool", "maybe"])
    @test (f.seen, f.flags) == (0x10, 0xE0)
    LK.PL_discard_foreign_frame(ld, fid)
end

@testset "re_lookup_and_apply_optdef[_arg] (pcre4pl.c lookup_and_apply_optdef[_arg])" begin
    ld = _PO_LD
    fid = LK.PL_open_foreign_frame(ld)
    opt = _po_term(ld, "bsr(unicode)")
    # bsr: the flag of the row under OPTBSR_MASK, seen = the mask
    f = LK.re_options_flags(UInt32(0), UInt32(0))
    @test LK.re_lookup_and_apply_optdef(ld, LK.re_optbsrs, "unicode", opt, 0, LK.OPTBSR_MASK, f) === true
    @test (f.seen, f.flags) == (3, 1)
    f = LK.re_options_flags(UInt32(0), UInt32(0))
    @test LK.re_lookup_and_apply_optdef(ld, LK.re_optbsrs, "anycrlf", opt, 0, LK.OPTBSR_MASK, f) === true
    @test (f.seen, f.flags) == (3, 2)
    # a second bsr option is ignored
    @test LK.re_lookup_and_apply_optdef(ld, LK.re_optbsrs, "unicode", opt, 0, LK.OPTBSR_MASK, f) === true && f.flags == 2
    # newline: cr=1 .. nul=6 all fit in the mask's three bits
    for (nm, want) in (("cr", 1), ("lf", 2), ("crlf", 3), ("any", 4), ("anycrlf", 5), ("nul", 6))
        f = LK.re_options_flags(UInt32(0), UInt32(0))
        @test LK.re_lookup_and_apply_optdef(ld, LK.re_optnewlines, nm, opt, 0, LK.OPTNEWLINE_MASK, f) === true
        @test (f.seen, f.flags) == (7, want)
    end
    # capture type
    f = LK.re_options_flags(UInt32(0), UInt32(1))
    @test LK.re_lookup_and_apply_optdef(ld, LK.re_optcaptures, "integer", opt, 0, LK.OPTCAPTURE_MASK, f) === true
    @test (f.seen, f.flags) == (7, 3)
    # an unknown name: type_error(option, OptionTerm), false, the flags untouched
    f = LK.re_options_flags(UInt32(0), UInt32(0))
    @test LK.re_lookup_and_apply_optdef(ld, LK.re_optbsrs, "nope", opt, 0, LK.OPTBSR_MASK, f) === false
    @test _po_exc(ld) == ("type_error", ["option", "bsr/1"])
    @test (f.seen, f.flags) == (0, 0)
    # compat has no value in PCRE2: every name is an error
    opt2 = _po_term(ld, "compat(javascript)")
    @test LK.re_lookup_and_apply_optdef(ld, LK.re_optcompats, "javascript", opt2, 0, LK.OPTCOMPAT_MASK, f) === false
    @test _po_exc(ld) == ("type_error", ["option", "compat/1"])
    # a row of the big table through the same function: an inverted one
    f = LK.re_options_flags(UInt32(0), UInt32(0))
    @test LK.re_lookup_and_apply_optdef(ld, LK.re_optdefs, "greedy", opt, _po_term(ld, "true"), LK.PCRE2_UNGREEDY, f) === true
    @test (f.seen, f.flags) == (LK.PCRE2_UNGREEDY, 0)
    f = LK.re_options_flags(UInt32(0), UInt32(0))
    @test LK.re_lookup_and_apply_optdef(ld, LK.re_optdefs, "greedy", opt, _po_term(ld, "false"), LK.PCRE2_UNGREEDY, f) === true
    @test (f.seen, f.flags) == (LK.PCRE2_UNGREEDY, LK.PCRE2_UNGREEDY)
    # the _arg form reads the name from an atom term
    f = LK.re_options_flags(UInt32(0), UInt32(0))
    @test LK.re_lookup_and_apply_optdef_arg(ld, LK.re_optnewlines, _po_term(ld, "crlf"), opt, 0, LK.OPTNEWLINE_MASK, f) === true
    @test (f.seen, f.flags) == (7, 3)
    f = LK.re_options_flags(UInt32(0), UInt32(0))
    @test LK.re_lookup_and_apply_optdef_arg(ld, LK.re_optnewlines, _po_term(ld, "1"), opt, 0, LK.OPTNEWLINE_MASK, f) === false
    @test _po_exc(ld) == ("type_error", ["atom", "1"])
    @test (f.seen, f.flags) == (0, 0)
    @test LK.re_lookup_and_apply_optdef_arg(ld, LK.re_optnewlines, _po_term(ld, "zz"), opt, 0, LK.OPTNEWLINE_MASK, f) === false
    @test _po_exc(ld) == ("type_error", ["option", "bsr/1"])
    LK.PL_discard_foreign_frame(ld, fid)
end
