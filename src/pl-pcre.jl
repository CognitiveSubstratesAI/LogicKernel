# CLASS: code
# COPYRIGHT: Copyright (c)  2017-2023, VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# allow-new-artifact: packages/pcre C port (Phase 1), the carrier-independent part: the UTF-8 offset helpers of pcre4pl.c
#
# PCRE1 piece 1 (packages/pcre/pcre4pl.c, packages-pcre a5e4c885 at swipl-devel af9e2e7e; the file is not vendored yet, read from
# the submodule's object store): the SUBJECT UTF-8 OFFSET HELPERS of pcre4pl.c (lines 398-455): the `re_subject` record and the
# four functions that turn a byte offset (what PCRE2 returns) into a character offset (what Prolog sees) and back. They read the
# bytes of the subject and nothing else: no libpcre2, no term, no stream, so they are the same whichever carrier the matcher ends
# up on (evidence/R2/pkg2_plan.md in the channel, Q3). NO `# UPSTREAM:` header line: `packages/pcre` is a gitlink at the pin, not
# a blob of swipl-devel (as src/pl-json.jl). NOT registered anywhere, nothing calls these yet. Nothing here has run (no Julia process
# was started). `re_get_subject` (PL_get_nchars) is the engine-bound neighbour: a later piece.
#
# DIVERGES (file-wide):
#   1. OFFSETS stay 0-based (they are PCRE2's and Prolog's offsets), and a byte at 0-based offset `o` of the subject `b` is `b[o+1]`.
#      The C pointer arithmetic `s - subject` is an offset; the C `const char *` that points INTO the subject is an offset too.
#   2. The subject is a byte vector and its length is passed (`len`); upstream's buffer is NUL terminated (PL_get_nchars), and the
#      skipping reads that NUL when an offset runs past the end. `_byte` (pl-utf8.jl) returns 0 past the end, so the reading is the same.
#   3. `utf8_skip_char` is pcre4pl.c's own static copy of pl-utf8.h's `utf8_skip_char`, the same code; the kernel's one
#      (src/os/pl-utf8.jl) is used, with the index shift of the first point. `(size_t)-1` of `utf8_seek` is `-1`.
#   4. Names carry the prefix `re_` (the kernel is one namespace; `utf8_skip_char` and the others are static in the C file).

# PORT: packages/pcre/pcre4pl.c re_subject
"The subject of a match (pcre4pl.c `re_subject`): its bytes, its length in bytes, and a cached character/byte position pair."
mutable struct re_subject
    subject::Vector{UInt8}      # Subject string
    length::Int                 # Total length in bytes
    charp::Int                  # Character position
    bytep::Int                  # Byte position
end

# The constructor form of init_subject below. `memset(subject, 0, ...)` leaves a NULL string: an empty vector here.
"A subject with no string and both positions at 0 (pcre4pl.c `init_subject`)."
re_subject() = re_subject(UInt8[], 0, 0, 0)

# PORT: packages/pcre/pcre4pl.c init_subject
"Reset `subject` to no string and both positions at 0 (pcre4pl.c `init_subject`)."
function init_subject!(subject::re_subject)::Nothing
    subject.subject = UInt8[]
    subject.length = 0
    subject.charp = 0
    subject.bytep = 0
    return nothing
end

# PORT: packages/pcre/pcre4pl.c utf8_skip_char
# DIVERGES: see the file header, 1 and 3.
"The 0-based offset after the character that starts at the 0-based offset `o` of `b` (pcre4pl.c `utf8_skip_char`)."
@inline re_utf8_skip_char(b::AbstractVector{UInt8}, o::Int)::Int = utf8_skip_char(b, o + 1) - 1

# PORT: packages/pcre/pcre4pl.c utf8_seek
# DIVERGES: see the file header, 1, 2 and 3.
"The byte offset of the character `offset` characters into `subject` (of `len` bytes), or `-1` if that is past the end (pcre4pl.c `utf8_seek`)."
function re_utf8_seek(subject::AbstractVector{UInt8}, len::Int, offset::Int)::Int
    s = 0
    e = len
    while offset > 0
        s >= e && return -1
        s = re_utf8_skip_char(subject, s)
        offset -= 1
    end
    return s
end

# PORT: packages/pcre/pcre4pl.c char_offset
# DIVERGES: see the file header, 1 and 2. The C `subject` is a pointer to the byte at offset `start` of the buffer `b`.
"The number of characters in the `byte_offset` bytes that start at the 0-based offset `start` of `b`; a character that ends past the limit counts (pcre4pl.c `char_offset`)."
function re_char_offset(b::AbstractVector{UInt8}, start::Int, byte_offset::Int)::Int
    e = start + byte_offset
    co = 0
    s = start
    while s < e
        s = re_utf8_skip_char(b, s)
        co += 1
    end
    return co
end

# PORT: packages/pcre/pcre4pl.c bytep_to_charp
# DIVERGES: see the file header, 1.
"The character position of the 0-based byte position `bytep` of `subj`, counted from the cached position pair, which is updated (pcre4pl.c `bytep_to_charp`)."
function re_bytep_to_charp(subj::re_subject, bytep::Int)::Int
    if subj.bytep > bytep
        subj.bytep = 0
        subj.charp = 0
    end
    subj.charp += re_char_offset(subj.subject, subj.bytep, bytep - subj.bytep)
    subj.bytep = bytep
    return subj.charp
end

# ---------------------------------------------------------------------------------------------------------------------------------
# PCRE1 piece 2 (packages/pcre/pcre4pl.c, packages-pcre a5e4c885, lines 70-175, 488-740): the OPTION AND FLAG TABLES: the capture types, the
# `re_options_flags` seen/flags pair, `set_flag` and its `effective_bool`, the five option tables (`re_optdefs`, `re_optbsrs`,
# `re_optnewlines`, `re_optcompats`, `re_optcaptures`) and their lookup. The values of the PCRE2_* constants are those of pcre2.h 10.47, read
# from Julia's own `Base.PCRE` (share/julia/base/pcre_h.jl; the repo has no pcre2.h): the compile, match and JIT option bits are the same
# in every 10.x header (ABI), and test_pcre_options.jl compares each with `Base.PCRE.<NAME>` so that a typo here is caught. MEASURE ON THE
# LANE: that the oracle's own pcre2.h (libpcre2 0.11.2) defines the four names guarded by `#ifdef` upstream (MATCH_INVALID_UTF,
# EXTRA_ESCAPED_CR_IS_LF, EXTRA_ALT_BSUX, JIT_INVALID_UTF, COPY_MATCHED_SUBJECT: all older than 10.42): they are ported as always defined.
# NOT PORTED (later pieces): `re_get_options` (needs `PL_get_uint64_ex`, which the kernel lacks, for `start(N)`), the `cfg_opts` table of
# `re_config`, `re_data`'s symbol, pattern, capture_names and compiled code. Nothing here has run (no Julia process was started).
#
# DIVERGES (piece 2):
#   5. An option table row is a `re_optdef(name, flag, mode)` and the table a Vector without the C's `{ NULL }` end marker; the `atom` field
#      (filled lazily by `lookup_optdef`) is dropped: the lookup compares the option's name TEXT (`sym_text`, as the file's other pieces).
#   6. `re_data` carries only the flag pairs and `capture_size` (the fields option processing reads and writes); `init_re_data` is
#      `re_init_data` (a constructor of the defaults) and `get_re_copy`'s reset of the match flags is `re_reset_match_flags!`.
#   7. `effective_bool` answers 1, 0 or -1 as C; `arg == 0` is "no argument" (the C `term_t` 0).
#   8. `OPTSTART_MASK` is `typemax(UInt32)`: `(uint32_t)PCRE2_SIZE_MAX` with a 64-bit `size_t`.

# PORT: packages/pcre/pcre4pl.c enum cap_type
const CAP_DEFAULT = 0
const CAP_STRING = 1
const CAP_ATOM = 2
const CAP_INTEGER = 3
const CAP_FLOAT = 4
const CAP_NUMBER = 5
const CAP_TERM = 6
const CAP_RANGE = 7

# PORT: packages/pcre/pcre4pl.c cap_type_str
"The name of the capture type `i` (pcre4pl.c `cap_type_str`, for debugging)."
function re_cap_type_str(i::Int)::String
    i == CAP_DEFAULT && return "CAP_DEFAULT"
    i == CAP_STRING && return "CAP_STRING"
    i == CAP_ATOM && return "CAP_ATOM"
    i == CAP_INTEGER && return "CAP_INTEGER"
    i == CAP_FLOAT && return "CAP_FLOAT"
    i == CAP_NUMBER && return "CAP_NUMBER"
    i == CAP_TERM && return "CAP_TERM"
    i == CAP_RANGE && return "CAP_RANGE"
    return "CAP_???"
end

# pcre2.h option values (10.47, Base.PCRE's pcre_h.jl): see the piece header.
const PCRE2_ALLOW_EMPTY_CLASS = UInt32(0x00000001)
const PCRE2_ALT_BSUX = UInt32(0x00000002)
const PCRE2_ALT_CIRCUMFLEX = UInt32(0x00200000)
const PCRE2_ALT_VERBNAMES = UInt32(0x00400000)
const PCRE2_ANCHORED = UInt32(0x80000000)
const PCRE2_AUTO_CALLOUT = UInt32(0x00000004)
const PCRE2_BSR_ANYCRLF = UInt32(2)
const PCRE2_BSR_UNICODE = UInt32(1)
const PCRE2_CASELESS = UInt32(0x00000008)
const PCRE2_COPY_MATCHED_SUBJECT = UInt32(0x00004000)
const PCRE2_DFA_RESTART = UInt32(0x00000040)
const PCRE2_DFA_SHORTEST = UInt32(0x00000080)
const PCRE2_DOLLAR_ENDONLY = UInt32(0x00000010)
const PCRE2_DOTALL = UInt32(0x00000020)
const PCRE2_DUPNAMES = UInt32(0x00000040)
const PCRE2_ENDANCHORED = UInt32(0x20000000)
const PCRE2_EXTENDED = UInt32(0x00000080)
const PCRE2_EXTENDED_MORE = UInt32(0x01000000)
const PCRE2_EXTRA_ALLOW_SURROGATE_ESCAPES = UInt32(0x00000001)
const PCRE2_EXTRA_ALT_BSUX = UInt32(0x00000020)
const PCRE2_EXTRA_BAD_ESCAPE_IS_LITERAL = UInt32(0x00000002)
const PCRE2_EXTRA_ESCAPED_CR_IS_LF = UInt32(0x00000010)
const PCRE2_EXTRA_MATCH_LINE = UInt32(0x00000008)
const PCRE2_EXTRA_MATCH_WORD = UInt32(0x00000004)
const PCRE2_FIRSTLINE = UInt32(0x00000100)
const PCRE2_JIT_COMPLETE = UInt32(0x00000001)
const PCRE2_JIT_INVALID_UTF = UInt32(0x00000100)
const PCRE2_JIT_PARTIAL_HARD = UInt32(0x00000004)
const PCRE2_JIT_PARTIAL_SOFT = UInt32(0x00000002)
const PCRE2_LITERAL = UInt32(0x02000000)
const PCRE2_MATCH_INVALID_UTF = UInt32(0x04000000)
const PCRE2_MATCH_UNSET_BACKREF = UInt32(0x00000200)
const PCRE2_MULTILINE = UInt32(0x00000400)
const PCRE2_NEVER_BACKSLASH_C = UInt32(0x00100000)
const PCRE2_NEVER_UCP = UInt32(0x00000800)
const PCRE2_NEVER_UTF = UInt32(0x00001000)
const PCRE2_NEWLINE_ANY = UInt32(4)
const PCRE2_NEWLINE_ANYCRLF = UInt32(5)
const PCRE2_NEWLINE_CR = UInt32(1)
const PCRE2_NEWLINE_CRLF = UInt32(3)
const PCRE2_NEWLINE_LF = UInt32(2)
const PCRE2_NEWLINE_NUL = UInt32(6)
const PCRE2_NOTBOL = UInt32(0x00000001)
const PCRE2_NOTEMPTY = UInt32(0x00000004)
const PCRE2_NOTEMPTY_ATSTART = UInt32(0x00000008)
const PCRE2_NOTEOL = UInt32(0x00000002)
const PCRE2_NO_AUTO_CAPTURE = UInt32(0x00002000)
const PCRE2_NO_AUTO_POSSESS = UInt32(0x00004000)
const PCRE2_NO_DOTSTAR_ANCHOR = UInt32(0x00008000)
const PCRE2_NO_JIT = UInt32(0x00002000)
const PCRE2_NO_START_OPTIMIZE = UInt32(0x00010000)
const PCRE2_NO_UTF_CHECK = UInt32(0x40000000)
const PCRE2_PARTIAL_HARD = UInt32(0x00000020)
const PCRE2_PARTIAL_SOFT = UInt32(0x00000010)
const PCRE2_SUBSTITUTE_EXTENDED = UInt32(0x00000200)
const PCRE2_SUBSTITUTE_GLOBAL = UInt32(0x00000100)
const PCRE2_SUBSTITUTE_OVERFLOW_LENGTH = UInt32(0x00001000)
const PCRE2_SUBSTITUTE_UNKNOWN_UNSET = UInt32(0x00000800)
const PCRE2_SUBSTITUTE_UNSET_EMPTY = UInt32(0x00000400)
const PCRE2_UCP = UInt32(0x00020000)
const PCRE2_UNGREEDY = UInt32(0x00040000)
const PCRE2_USE_OFFSET_LIMIT = UInt32(0x00800000)
const PCRE2_UTF = UInt32(0x00080000)

# PORT: packages/pcre/pcre4pl.c RE_OPTIMISE, RE_NEG, RE_COMP_BOOL ... RE_SUBS_BOOL, OPTSTART_MASK
const RE_OPTIMISE = UInt32(0x0001)
const RE_NEG = UInt32(0x0001)
const RE_COMP_BOOL = UInt32(0x0010)
const RE_COMP_BSR = UInt32(0x0020)
const RE_COMP_NEWLINE = UInt32(0x0040)
const RE_COMP_OPTIMISE = UInt32(0x0080)
const RE_COMP_COMPAT = UInt32(0x0100)
const RE_COMP_CAPTURE = UInt32(0x0200)
const RE_COMPCTX_BOOL = UInt32(0x0400)
const RE_COMPJIT_BOOL = UInt32(0x0800)
const RE_MATCH_BOOL = UInt32(0x1000)
const RE_MATCH_START = UInt32(0x2000)
const RE_SUBS_BOOL = UInt32(0x4000)
const OPTSTART_MASK = typemax(UInt32)
const OPTBSR_MASK = PCRE2_BSR_ANYCRLF | PCRE2_BSR_UNICODE
const OPTNEWLINE_MASK = PCRE2_NEWLINE_CR | PCRE2_NEWLINE_LF | PCRE2_NEWLINE_CRLF | PCRE2_NEWLINE_ANY | PCRE2_NEWLINE_ANYCRLF
const OPTCOMPAT_MASK = UInt32(0)
const OPTCAPTURE_MASK = UInt32(CAP_ATOM | CAP_FLOAT | CAP_INTEGER | CAP_NUMBER | CAP_RANGE | CAP_STRING | CAP_TERM | CAP_DEFAULT)

# PORT: packages/pcre/pcre4pl.c re_options_flags
"The flags of one option group and the bits already set by an option (pcre4pl.c `re_options_flags`): only the first value of a flag counts."
mutable struct re_options_flags
    seen::UInt32
    flags::UInt32
end
re_options_flags() = re_options_flags(UInt32(0), UInt32(0))

# PORT: packages/pcre/pcre4pl.c re_data (the option fields), init_re_data, get_re_copy (the reset of the match flags)
# DIVERGES: see the piece 2 header, 6.
"The option part of a regex (pcre4pl.c `re_data`): the flag pairs of the compile, capture, optimise, JIT, context, bsr, newline, match and start options."
mutable struct re_data
    compile_options_flags::re_options_flags
    capture_type::re_options_flags
    optimise_flags::re_options_flags
    jit_options_flags::re_options_flags
    compile_ctx_flags::re_options_flags
    compile_bsr_flags::re_options_flags
    compile_newline_flags::re_options_flags
    match_options_flags::re_options_flags
    start_flags::re_options_flags
    capture_size::UInt32
end

"A regex's option fields as `init_re_data` leaves them: utf and no UTF check to compile, no UTF check to match, the string capture type (pcre4pl.c)."
function re_init_data()::re_data
    re = re_data(
        re_options_flags(), re_options_flags(), re_options_flags(), re_options_flags(), re_options_flags(),
        re_options_flags(), re_options_flags(), re_options_flags(), re_options_flags(), UInt32(0)
    )
    re.compile_options_flags.flags = PCRE2_UTF | PCRE2_NO_UTF_CHECK
    re.match_options_flags.flags = PCRE2_NO_UTF_CHECK
    re.capture_type.flags = UInt32(CAP_STRING)
    return re
end

"Clear the flags specific to a match, as `get_re_copy` does on its copy: match options `seen` 0 and no UTF check, start `seen` 0 and 0 (pcre4pl.c)."
function re_reset_match_flags!(re::re_data)::Nothing
    re.match_options_flags.seen = UInt32(0)
    re.match_options_flags.flags = PCRE2_NO_UTF_CHECK
    re.start_flags.seen = UInt32(0)
    re.start_flags.flags = UInt32(0)
    return nothing
end

# PORT: packages/pcre/pcre4pl.c effective_bool
# DIVERGES: see the piece 2 header, 7.
"1 or 0 for the Boolean `arg`, true (1) when there is no argument (`arg == 0`), -1 with the error raised when `arg` is no Boolean (pcre4pl.c)."
function re_effective_bool(ld::PL_local_data{T}, arg::term_t)::Int where {T}
    arg == 0 && return 1
    v = PL_get_bool_ex(ld, arg)
    v === nothing && return -1
    return v ? 1 : 0
end

# PORT: packages/pcre/pcre4pl.c set_flag
"Set (or, `invert`, clear) the bits `value` in `of.flags` from the Boolean `arg`, once per `mask` (a repeated option is ignored); false after an error (pcre4pl.c)."
function re_set_flag(
    ld::PL_local_data{T}, arg::term_t, of::re_options_flags, mask::UInt32, value::UInt32, invert::Bool
)::Bool where {T}
    (of.seen & mask) != 0 && return true                    # repeated option - ignore
    of.seen |= mask
    of.flags &= ~mask                                       # clear the bits where the value goes
    eb = re_effective_bool(ld, arg)
    if eb == 1
        if invert
            of.flags &= ~value
        else
            of.flags |= value
        end
    elseif eb == 0
        if invert
            of.flags |= value
        else
            of.flags &= ~value
        end
    else
        return false                                        # -1: neither false nor true
    end
    return true
end

# PORT: packages/pcre/pcre4pl.c re_optdef
# DIVERGES: see the piece 2 header, 5.
"One row of an option table (pcre4pl.c `re_optdef`): the option's name, its PCRE2 flag (0 for an option with a name or number) and its mode."
struct re_optdef
    name::String
    flag::UInt32
    mode::UInt32
end

const re_optdefs = re_optdef[
    # Those with flag == 0 are for options with names or numbers:
    re_optdef("bsr", 0, RE_COMP_BSR),
    re_optdef("bsr2", 0, RE_COMP_BSR),
    re_optdef("capture_type", 0, RE_COMP_CAPTURE),
    re_optdef("compat", 0, RE_COMP_COMPAT),
    re_optdef("newline", 0, RE_COMP_NEWLINE),
    re_optdef("newline2", 0, RE_COMP_NEWLINE),
    re_optdef("optimise", 0, RE_COMP_OPTIMISE),
    re_optdef("optimize", 0, RE_COMP_OPTIMISE),
    re_optdef("start", 0, RE_MATCH_START),
    # The following are in the same order as in pcre2.h
    re_optdef("anchored", PCRE2_ANCHORED, RE_COMP_BOOL | RE_MATCH_BOOL),
    re_optdef("utf_check", PCRE2_NO_UTF_CHECK, RE_COMP_BOOL | RE_MATCH_BOOL),
    re_optdef("endanchored", PCRE2_ENDANCHORED, RE_COMP_BOOL | RE_MATCH_BOOL),
    re_optdef("allow_empty_class", PCRE2_ALLOW_EMPTY_CLASS, RE_COMP_BOOL),
    re_optdef("alt_bsux", PCRE2_ALT_BSUX, RE_COMP_BOOL),
    re_optdef("auto_callout", PCRE2_AUTO_CALLOUT, RE_COMP_BOOL),
    re_optdef("caseless", PCRE2_CASELESS, RE_COMP_BOOL),
    re_optdef("dollar_endonly", PCRE2_DOLLAR_ENDONLY, RE_COMP_BOOL),
    re_optdef("dotall", PCRE2_DOTALL, RE_COMP_BOOL),
    re_optdef("dupnames", PCRE2_DUPNAMES, RE_COMP_BOOL),
    re_optdef("extended", PCRE2_EXTENDED, RE_COMP_BOOL),
    re_optdef("firstline", PCRE2_FIRSTLINE, RE_COMP_BOOL),
    re_optdef("match_unset_backref", PCRE2_MATCH_UNSET_BACKREF, RE_COMP_BOOL),
    re_optdef("multiline", PCRE2_MULTILINE, RE_COMP_BOOL),
    re_optdef("never_ucp", PCRE2_NEVER_UCP, RE_COMP_BOOL),
    re_optdef("never_utf", PCRE2_NEVER_UTF, RE_COMP_BOOL),
    re_optdef("auto_capture", PCRE2_NO_AUTO_CAPTURE, RE_COMP_BOOL | RE_NEG),
    re_optdef("no_auto_capture", PCRE2_NO_AUTO_CAPTURE, RE_COMP_BOOL),
    re_optdef("auto_possess", PCRE2_NO_AUTO_POSSESS, RE_COMP_BOOL | RE_NEG),
    re_optdef("dotstar_anchor", PCRE2_NO_DOTSTAR_ANCHOR, RE_COMP_BOOL | RE_NEG),
    re_optdef("start_optimize", PCRE2_NO_START_OPTIMIZE, RE_COMP_BOOL | RE_NEG),
    re_optdef("ucp", PCRE2_UCP, RE_COMP_BOOL),
    re_optdef("greedy", PCRE2_UNGREEDY, RE_COMP_BOOL | RE_NEG),
    re_optdef("ungreedy", PCRE2_UNGREEDY, RE_COMP_BOOL),
    re_optdef("utf", PCRE2_UTF, RE_COMP_BOOL),
    re_optdef("never_backslash_c", PCRE2_NEVER_BACKSLASH_C, RE_COMP_BOOL),
    re_optdef("alt_circumflex", PCRE2_ALT_CIRCUMFLEX, RE_COMP_BOOL),
    re_optdef("alt_verbnames", PCRE2_ALT_VERBNAMES, RE_COMP_BOOL),
    re_optdef("use_offset_limit", PCRE2_USE_OFFSET_LIMIT, RE_COMP_BOOL),
    re_optdef("extended_more", PCRE2_EXTENDED_MORE, RE_COMP_BOOL),
    re_optdef("literal", PCRE2_LITERAL, RE_COMP_BOOL),
    re_optdef("match_invalid_utf", PCRE2_MATCH_INVALID_UTF, RE_COMP_BOOL),
    re_optdef("extra_allow_surrogate_escapes", PCRE2_EXTRA_ALLOW_SURROGATE_ESCAPES, RE_COMPCTX_BOOL),
    re_optdef("extra_bad_escape_is_literal", PCRE2_EXTRA_BAD_ESCAPE_IS_LITERAL, RE_COMPCTX_BOOL),
    re_optdef("extra_match_word", PCRE2_EXTRA_MATCH_WORD, RE_COMPCTX_BOOL),
    re_optdef("extra_match_line", PCRE2_EXTRA_MATCH_LINE, RE_COMPCTX_BOOL),
    re_optdef("extra_escaped_cr_is_lf", PCRE2_EXTRA_ESCAPED_CR_IS_LF, RE_COMPCTX_BOOL),
    re_optdef("extra_alt_bsux", PCRE2_EXTRA_ALT_BSUX, RE_COMPCTX_BOOL),
    re_optdef("jit_complete", PCRE2_JIT_COMPLETE, RE_COMPJIT_BOOL),
    re_optdef("jit_partial_soft", PCRE2_JIT_PARTIAL_SOFT, RE_COMPJIT_BOOL),
    re_optdef("jit_partial_hard", PCRE2_JIT_PARTIAL_HARD, RE_COMPJIT_BOOL),
    re_optdef("jit_invalid_utf", PCRE2_JIT_INVALID_UTF, RE_COMPJIT_BOOL),
    # Some of the following are for pcre2_dfa_match() or pcre2_substitute(), but they're all in the same flag
    re_optdef("bol", PCRE2_NOTBOL, RE_MATCH_BOOL | RE_NEG),
    re_optdef("eol", PCRE2_NOTEOL, RE_MATCH_BOOL | RE_NEG),
    re_optdef("empty", PCRE2_NOTEMPTY, RE_MATCH_BOOL | RE_NEG),
    re_optdef("empty_atstart", PCRE2_NOTEMPTY_ATSTART, RE_MATCH_BOOL | RE_NEG),
    re_optdef("partial_soft", PCRE2_PARTIAL_SOFT, RE_MATCH_BOOL),
    re_optdef("partial_hard", PCRE2_PARTIAL_HARD, RE_MATCH_BOOL),
    re_optdef("dfa_restart", PCRE2_DFA_RESTART, RE_MATCH_BOOL),
    re_optdef("dfa_shortest", PCRE2_DFA_SHORTEST, RE_MATCH_BOOL),
    re_optdef("substitute_global", PCRE2_SUBSTITUTE_GLOBAL, RE_MATCH_BOOL),
    re_optdef("substitute_extended", PCRE2_SUBSTITUTE_EXTENDED, RE_MATCH_BOOL),
    re_optdef("substitute_unset_empty", PCRE2_SUBSTITUTE_UNSET_EMPTY, RE_MATCH_BOOL),
    re_optdef("substitute_unknown_unset", PCRE2_SUBSTITUTE_UNKNOWN_UNSET, RE_MATCH_BOOL),
    re_optdef("substitute_overflow_length", PCRE2_SUBSTITUTE_OVERFLOW_LENGTH, RE_MATCH_BOOL),
    re_optdef("jit", PCRE2_NO_JIT, RE_MATCH_BOOL | RE_NEG),
    re_optdef("copy_matched_subject", PCRE2_COPY_MATCHED_SUBJECT, RE_MATCH_BOOL),
]

const re_optbsrs = re_optdef[
    re_optdef("anycrlf", PCRE2_BSR_ANYCRLF, RE_COMP_BSR),
    re_optdef("unicode", PCRE2_BSR_UNICODE, RE_COMP_BSR),
]

const re_optnewlines = re_optdef[
    re_optdef("cr", PCRE2_NEWLINE_CR, RE_COMP_NEWLINE),
    re_optdef("lf", PCRE2_NEWLINE_LF, RE_COMP_NEWLINE),
    re_optdef("crlf", PCRE2_NEWLINE_CRLF, RE_COMP_NEWLINE),
    re_optdef("any", PCRE2_NEWLINE_ANY, RE_COMP_NEWLINE),
    re_optdef("anycrlf", PCRE2_NEWLINE_ANYCRLF, RE_COMP_NEWLINE),
    re_optdef("nul", PCRE2_NEWLINE_NUL, RE_COMP_NEWLINE),
]

# upstream: "This had "javascript" for PCRE1; the option doesn't exist in PCRE2, so this empty array causes an error for compat(javascript)."
const re_optcompats = re_optdef[]

const re_optcaptures = re_optdef[
    re_optdef("atom", UInt32(CAP_ATOM), RE_COMP_CAPTURE),
    re_optdef("float", UInt32(CAP_FLOAT), RE_COMP_CAPTURE),
    re_optdef("integer", UInt32(CAP_INTEGER), RE_COMP_CAPTURE),
    re_optdef("number", UInt32(CAP_NUMBER), RE_COMP_CAPTURE),
    re_optdef("range", UInt32(CAP_RANGE), RE_COMP_CAPTURE),
    re_optdef("string", UInt32(CAP_STRING), RE_COMP_CAPTURE),
    re_optdef("term", UInt32(CAP_TERM), RE_COMP_CAPTURE),
]

# PORT: packages/pcre/pcre4pl.c lookup_optdef
# DIVERGES: see the piece 2 header, 5. The first row of `opt_defs` named `name`, `nothing` when there is none.
"The first row of the table `opt_defs` whose name is `name` (pcre4pl.c `lookup_optdef`), `nothing` if none."
function re_lookup_optdef(opt_defs::Vector{re_optdef}, name::String)::Union{Nothing, re_optdef}
    for def in opt_defs
        def.name == name && return def
    end
    return nothing
end

# PORT: packages/pcre/pcre4pl.c lookup_and_apply_optdef
"Apply the table row named `name` to `options_flags` under `mask`, or raise `type_error(option, OptionTerm)`; false after an error (pcre4pl.c)."
function re_lookup_and_apply_optdef(
    ld::PL_local_data{T}, opt_defs::Vector{re_optdef}, name::String, option_term::term_t, arg::term_t,
    mask::UInt32, options_flags::re_options_flags
)::Bool where {T}
    def = re_lookup_optdef(opt_defs, name)
    if def !== nothing
        return re_set_flag(ld, arg, options_flags, mask, def.flag, (def.mode & RE_NEG) != 0)
    end
    return PL_type_error(ld, "option", option_term)
end

# PORT: packages/pcre/pcre4pl.c lookup_and_apply_optdef_arg
"As `re_lookup_and_apply_optdef` with the option's name read from the term `name` (an atom, else `type_error(atom, Name)`) (pcre4pl.c)."
function re_lookup_and_apply_optdef_arg(
    ld::PL_local_data{T}, opt_defs::Vector{re_optdef}, name::term_t, option_term::term_t, arg::term_t,
    mask::UInt32, options_flags::re_options_flags
)::Bool where {T}
    a = PL_get_atom_ex(ld, name)
    a === nothing && return false
    return re_lookup_and_apply_optdef(ld, opt_defs, sym_text(a), option_term, arg, mask, options_flags)
end
