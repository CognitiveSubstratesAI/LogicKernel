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
# PIECE 5 adds `re_data`'s `pattern` (the atom's text) and `serial`, and `re_compare` (compare_pcres). NOT PORTED (later pieces): the blob
# machinery itself (the kernel has no `PL_blob_data`/`PL_new_blob`/`PL_qlf_*` for a package type: `acquire/release/write/save/load_pcre`), `re_get_options` (needs `PL_get_uint64_ex`, which the kernel lacks, for `start(N)`), the `cfg_opts` table of
# `re_config`, `re_data`'s symbol, capture_names and compiled code. Nothing here has run (no Julia process was started).
#
# DIVERGES (piece 5, re_compare): 10 below. DIVERGES (piece 2):
#   5. An option table row is a `re_optdef(name, flag, mode)` and the table a Vector without the C's `{ NULL }` end marker; the `atom` field
#      (filled lazily by `lookup_optdef`) is dropped: the lookup compares the option's name TEXT (`sym_text`, as the file's other pieces).
#   6. `re_data` carries only the flag pairs and `capture_size` (the fields option processing reads and writes); `init_re_data` is
#      `re_init_data` (a constructor of the defaults) and `get_re_copy`'s reset of the match flags is `re_reset_match_flags!`.
#   7. `effective_bool` answers 1, 0 or -1 as C; `arg == 0` is "no argument" (the C `term_t` 0).
#   8. `OPTSTART_MASK` is `typemax(UInt32)`: `(uint32_t)PCRE2_SIZE_MAX` with a 64-bit `size_t`.
#  10. (piece 5) `re_data` has `pattern::String` (the atom's text) and `serial` (the stand-in for the blob address); `re_init_data(pattern)` sets both.

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

# PORT: packages/pcre/pcre4pl.c cfg_opts (the PCRE2_CONFIG_* ids of pcre_config(), pcre2.h 10.47 values read from Base.PCRE's pcre_h.jl; test_pcre_config_tables.jl compares each)
const PCRE2_CONFIG_BSR = UInt32(0)
const PCRE2_CONFIG_COMPILED_WIDTHS = UInt32(14)
const PCRE2_CONFIG_DEPTHLIMIT = UInt32(7)
const PCRE2_CONFIG_HEAPLIMIT = UInt32(12)
const PCRE2_CONFIG_JIT = UInt32(1)
const PCRE2_CONFIG_JITTARGET = UInt32(2)
const PCRE2_CONFIG_LINKSIZE = UInt32(3)
const PCRE2_CONFIG_MATCHLIMIT = UInt32(4)
const PCRE2_CONFIG_NEVER_BACKSLASH_C = UInt32(13)
const PCRE2_CONFIG_NEWLINE = UInt32(5)
const PCRE2_CONFIG_PARENSLIMIT = UInt32(6)
const PCRE2_CONFIG_STACKRECURSE = UInt32(8)
const PCRE2_CONFIG_UNICODE = UInt32(9)
const PCRE2_CONFIG_UNICODE_VERSION = UInt32(10)
const PCRE2_CONFIG_VERSION = UInt32(11)

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

# The serial number of the next regex (the stand-in for the C's stable blob address, see `re_compare`).
const _re_serial = Threads.Atomic{Int}(0)

# PORT: packages/pcre/pcre4pl.c re_data (the option fields), init_re_data, get_re_copy (the reset of the match flags)
# DIVERGES: see the piece 2 header, 6.
"The option part of a regex (pcre4pl.c `re_data`): the flag pairs of the compile, capture, optimise, JIT, context, bsr, newline, match and start options."
mutable struct re_data
    pattern::String
    serial::Int
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
function re_init_data(pattern::String = "")::re_data
    re = re_data(
        pattern, Threads.atomic_add!(_re_serial, 1) + 1, re_options_flags(), re_options_flags(), re_options_flags(), re_options_flags(), re_options_flags(),
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

# PCRE1 piece 8 (pcre4pl.c a5e4c885, lines 854-906): the TABLES of `re_config`: the enum `re_config_type` and the `cfg_opts` rows, written by tool
# T2 (evidence/tools/porttools/t2_table_from_c.py) and read against the C, row by row; test/core_lang/test_pcre_config_tables.jl is T2's generated
# testset (every row against the C text) plus the PCRE2_CONFIG_* values against Base.PCRE. NOT PORTED: `re_config` itself, `re_config_`, `re_config_choice_`,
# `next_config`, `get_pcre2_info` (they call `pcre2_config`: no libpcre2 in the port yet).
# DIVERGES 14: `re_config_opt` has no `atom`/`functor` field (the C fills them lazily as a cache; the port compares the name TEXT, as DIVERGES 5);
#   its `type` field is `type_`; `id` is `Int32` (C `int`).
# PORT: packages/pcre/pcre4pl.c re_config_type
# (generated by tool T2 and read against the C: lines 854-866; the `typedef enum` is a plain Int here, as `cap_type`)
# GENERATED by t2_table_from_c.py from pcre@a5e4c885 pcre4pl.c lines 855-866 (enum `re_config_type`, 11 rows; C text sha256/12 4c0d14ac5090).
# Do not edit by hand: the generated test compares every row with the C text; regenerate instead.
const CFG_INTEGER = 0
const CFG_INTEGER_BKWD = 1  # Backwards compatibility with PCRE1
const CFG_BOOL = 2
const CFG_BOOL_BKWD = 3  # Backwards compatibility with PCRE1
const CFG_STRINGBUF = 4
const CFG_STRINGBUF_OPT = 5  # STRINGBUF that might return PCRE2_ERROR_BADOPTION
const CFG_BSR = 6
const CFG_NEWLINE = 7
const CFG_TRUE_BKWD = 8  # Backwards compatibility with PCRE1
const CFG_FALSE_BKWD = 9  # Backwards compatibility with PCRE1
const CFG_INVALID = 10

# PORT: packages/pcre/pcre4pl.c re_config_opt
# DIVERGES: see the piece 8 header, 14. `atom` and `functor` (filled lazily by `re_config_`/`next_config`) are not fields; `type_` is C's `type`.
"One row of the `re_config` table (pcre4pl.c `re_config_opt`): the option's name, its `pcre2_config()` id (-1: an option kept for PCRE1 compatibility) and how the answer is read."
struct re_config_opt
    name::String
    id::Int32
    type_::Int
end

# pcre4pl.c: "Items with id == -1 are for backwards compatibility with PCRE1"; "bsr" and "newline" have been removed because they return different things now
# GENERATED by t2_table_from_c.py from pcre@a5e4c885 pcre4pl.c lines 879-905 (array `cfg_opts`, 22 rows; C text sha256/12 531c26dc1252).
# Do not edit by hand: the generated test compares every row with the C text; regenerate instead.
# C sentinel row `{ NULL }` is dropped (C count 23, here 22).
const re_cfg_opts = re_config_opt[
    re_config_opt("bsr2", PCRE2_CONFIG_BSR, CFG_BSR),
    re_config_opt("compiled_widths", PCRE2_CONFIG_COMPILED_WIDTHS, CFG_INTEGER),  # PCRE2
    re_config_opt("depthlimit", PCRE2_CONFIG_DEPTHLIMIT, CFG_INTEGER),  # PCRE2
    re_config_opt("heaplimit", PCRE2_CONFIG_HEAPLIMIT, CFG_INTEGER),  # PCRE2
    re_config_opt("jit", PCRE2_CONFIG_JIT, CFG_BOOL),  # PCRE2
    re_config_opt("jittarget", PCRE2_CONFIG_JITTARGET, CFG_STRINGBUF_OPT),  # PCRE2
    re_config_opt("link_size", PCRE2_CONFIG_LINKSIZE, CFG_INTEGER_BKWD),
    re_config_opt("linksize", PCRE2_CONFIG_LINKSIZE, CFG_INTEGER),  # PCRE2 | was LINK_SIZE
    re_config_opt("match_limit", PCRE2_CONFIG_MATCHLIMIT, CFG_INTEGER_BKWD),
    re_config_opt("match_limit_recursion", -1, CFG_INVALID),
    re_config_opt("matchlimit", PCRE2_CONFIG_MATCHLIMIT, CFG_INTEGER),  # PCRE2
    re_config_opt("never_backslash_c", PCRE2_CONFIG_NEVER_BACKSLASH_C, CFG_BOOL),  # PCRE2
    re_config_opt("newline2", PCRE2_CONFIG_NEWLINE, CFG_NEWLINE),
    re_config_opt("parens_limit", PCRE2_CONFIG_PARENSLIMIT, CFG_INTEGER_BKWD),
    re_config_opt("parenslimit", PCRE2_CONFIG_PARENSLIMIT, CFG_INTEGER),  # PCRE2 | was PARENS_LIIMT
    re_config_opt("posix_malloc_threshold", -1, CFG_INVALID),
    re_config_opt("stackrecurse", PCRE2_CONFIG_STACKRECURSE, CFG_BOOL),
    re_config_opt("unicode", PCRE2_CONFIG_UNICODE, CFG_BOOL),  # PCRE2
    re_config_opt("unicode_properties", -1, CFG_TRUE_BKWD),
    re_config_opt("unicode_version", PCRE2_CONFIG_UNICODE_VERSION, CFG_STRINGBUF),  # PCRE2
    re_config_opt("utf8", PCRE2_CONFIG_UNICODE, CFG_BOOL_BKWD),
    re_config_opt("version", PCRE2_CONFIG_VERSION, CFG_STRINGBUF),  # PCRE2
]
# pcre4pl.c, after the last row: PCRE2_CONFIG_RECURSIONLIMIT is an obsolete synonym (no row).

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

# PORT: packages/pcre/pcre4pl.c compare_pcres, CMP_FIELD
# DIVERGES: 10. The blob's address is the field `serial` (a counter at creation, stable and unique); the answer is the sign (-1, 0, 1) where
# `wcscmp` answers any number of that sign; `pattern` is the atom's text, compared as code points (`wcscmp`; the UTF-8 bytes order the same).
# CMP_FIELD: -1, 1 by the `flags` of the two groups, else 0.
_re_cmp_flags(x::re_options_flags, y::re_options_flags)::Int = x.flags < y.flags ? -1 : x.flags > y.flags ? 1 : 0

"Order two regexes (pcre4pl.c `compare_pcres`): by pattern, then the `flags` of each option group in struct order (not `seen`), then the creation serial."
function re_compare(a::re_data, b::re_data)::Int
    if a.pattern != b.pattern
        return a.pattern < b.pattern ? -1 : 1
    end
    c = _re_cmp_flags(a.compile_options_flags, b.compile_options_flags)
    c == 0 && (c = _re_cmp_flags(a.capture_type, b.capture_type))
    c == 0 && (c = _re_cmp_flags(a.optimise_flags, b.optimise_flags))
    c == 0 && (c = _re_cmp_flags(a.jit_options_flags, b.jit_options_flags))
    c == 0 && (c = _re_cmp_flags(a.compile_ctx_flags, b.compile_ctx_flags))
    c == 0 && (c = _re_cmp_flags(a.compile_bsr_flags, b.compile_bsr_flags))
    c == 0 && (c = _re_cmp_flags(a.compile_newline_flags, b.compile_newline_flags))
    c == 0 && (c = _re_cmp_flags(a.match_options_flags, b.match_options_flags))
    c == 0 && (c = _re_cmp_flags(a.start_flags, b.start_flags))
    c != 0 && return c
    # No need to compare capture_names: they are derived from the patterns. Equal so far: the serial (the C: the address) breaks the tie.
    return a.serial > b.serial ? 1 : a.serial < b.serial ? -1 : 0
end

# ---------------------------------------------------------------------------------------------------------------------------------
# PCRE1 piece 6 (packages/pcre/pcre4pl.c lines 724-860, packages-pcre a5e4c885): `get_arg_1_if_any` and `re_get_options`, the option-list reader.
# It needs `PL_get_uint64_ex` (the `start(N)` option), which the kernel gained in the commit before this one. NOT PORTED: `ensure_compile_context`
# (a pcre2_compile_context, libpcre2). DIVERGES (11): the bare atom `start` (no argument: the C's `arg` is the term reference 0, which
# `PL_get_uint64_ex` reads as whatever cell 0 holds) raises `type_error(integer, start)` here; MEASURE on the oracle what swipl answers.

# PORT: packages/pcre/pcre4pl.c get_arg_1_if_any
# DIVERGES: returns `(name, arity, arg)` (the name an atom term, `arg` 0 when the option has no argument), or `nothing` after
# `type_error(option, Head)`, where the C returns the Bool and writes the three through pointers.
"The name, arity (0 or 1) and argument term reference (0 for none) of the option `head`, or `nothing` after raising `type_error(option, Head)` (pcre4pl.c)."
function re_get_arg_1_if_any(ld::PL_local_data{T}, head::term_t)::Union{Nothing, Tuple{T, Int, term_t}} where {T}
    na = PL_get_name_arity(ld, head)
    if na !== nothing && na[2] <= 1
        arg = term_t(0)
        if na[2] == 1
            argt = PL_new_term_ref(ld)
            _PL_get_arg(ld, 1, head, argt)
            arg = argt
        end
        return (na[1], na[2], arg)
    end
    PL_type_error(ld, "option", head)
    return nothing
end

# PORT: packages/pcre/pcre4pl.c re_get_options
# DIVERGES: 11 (above); the option table is looked up by the name's text (piece 2, 5). `re` is as `re_init_data` leaves it (or a regex
# with its match flags reset). Options can appear in several modes, so the `if`s are not `elseif`s, as the C.
"Read the option list `options` into `re`'s flag groups (pcre4pl.c `re_get_options`): an unknown option is ignored; false with the error raised on a bad list or option."
function re_get_options(ld::PL_local_data{T}, options::term_t, re::re_data)::Bool where {T}
    tail = PL_copy_term_ref(ld, options)
    head = PL_new_term_ref(ld)
    while PL_get_list_ex(ld, tail, head, tail)
        r = re_get_arg_1_if_any(ld, head)
        r === nothing && return false
        name, _, arg = r
        def = re_lookup_optdef(re_optdefs, sym_text(name))
        if def !== nothing
            neg = (def.mode & RE_NEG) != 0
            if (def.mode & RE_COMP_BOOL) != 0
                re_set_flag(ld, arg, re.compile_options_flags, def.flag, def.flag, neg) || return false
            end
            if (def.mode & RE_MATCH_BOOL) != 0
                re_set_flag(ld, arg, re.match_options_flags, def.flag, def.flag, neg) || return false
            end
            if (def.mode & RE_COMP_BSR) != 0
                re_lookup_and_apply_optdef_arg(ld, re_optbsrs, arg, head, term_t(0), OPTBSR_MASK, re.compile_bsr_flags) || return false
            end
            if (def.mode & RE_COMP_NEWLINE) != 0
                re_lookup_and_apply_optdef_arg(ld, re_optnewlines, arg, head, term_t(0), OPTNEWLINE_MASK, re.compile_newline_flags) || return false
            end
            if (def.mode & RE_COMP_COMPAT) != 0
                re_lookup_and_apply_optdef_arg(ld, re_optcompats, arg, head, term_t(0), OPTCOMPAT_MASK, re.compile_options_flags) || return false
            end
            if (def.mode & RE_COMP_CAPTURE) != 0
                re_lookup_and_apply_optdef_arg(ld, re_optcaptures, arg, head, term_t(0), OPTCAPTURE_MASK, re.capture_type) || return false
            end
            if (def.mode & RE_COMP_OPTIMISE) != 0
                re_set_flag(ld, arg, re.optimise_flags, RE_OPTIMISE, RE_OPTIMISE, neg) || return false
            end
            if (def.mode & RE_COMPCTX_BOOL) != 0
                re_set_flag(ld, arg, re.compile_ctx_flags, def.flag, def.flag, neg) || return false
            end
            if (def.mode & RE_COMPJIT_BOOL) != 0
                re_set_flag(ld, arg, re.jit_options_flags, def.flag, def.flag, neg) || return false
            end
            if (def.mode & RE_MATCH_START) != 0
                if arg == 0                                     # DIVERGES 11
                    PL_error(ld, ERR_TYPE, mk_sym(T, :integer), head)
                    return false
                end
                start_value = PL_get_uint64_ex(ld, arg)
                start_value === nothing && return false
                start_value > UInt64(OPTSTART_MASK) && return PL_domain_error(ld, "int32", arg)
                # TODO (upstream): use set_flags() style of checking "seen"; allow 64-bit sizes
                if re.start_flags.seen == 0
                    re.start_flags.seen = UInt32(1)
                    re.start_flags.flags = UInt32(start_value)
                end
            end
        end                                                     # else: ignore unknown option
    end
    return PL_get_nil_ex(ld, tail)
end

# ---------------------------------------------------------------------------------------------------------------------------------
# PCRE1 piece 7 (packages/pcre/pcre4pl.c write_pcre, save_pcre_options_flag, load_pcre_options_flag, save_pcre, load_pcre; a5e4c885): the
# pure parts of the blob's write, save and load functions. The kernel has no package blob type yet (design question Q-BLOB1, evidence/R2/
# pkg2_blob_design.md), so these are plain functions with no caller; the hook slots call them later. NOT PORTED: `PL_blob_data`/`PL_new_blob`
# (the blob itself), `PL_qlf_put_atom`/`PL_qlf_get_atom` (the qlf write and read state: the callbacks `put_atom`/`get_atom` stand for them),
# load's `re_compile_impl` (libpcre2, or the Julia engine: the carrier question), `free_pcre`, and the `PL_warning` text the C prints.

# PORT: packages/pcre/pcre4pl.c write_pcre
# DIVERGES: 12. `%p` prints the blob's address; the stand-in is the regex's creation serial in the same `0x<hex>` form (`re_compare`, 10). The result is the
# text; the C writes it to a stream with `SfprintfX` and answers whether that worked.
"The text `write_pcre` prints for `re`: `<regex>(0x<serial in hex>, <pattern>)` (pcre4pl.c)."
re_write_text(re::re_data)::String = string("<regex>(0x", string(re.serial, base = 16), ", ", re.pattern, ")")

# PORT: packages/pcre/pcre4pl.c save_pcre_options_flag
"Write one flag pair as two state-file unsigned integers (pcre4pl.c `save_pcre_options_flag`)."
function re_save_options_flag(of::re_options_flags, fd::IOSTREAM)::Bool
    return PL_qlf_put_uint32(of.seen, fd) && PL_qlf_put_uint32(of.flags, fd)
end

# PORT: packages/pcre/pcre4pl.c load_pcre_options_flag
# DIVERGES: writes the pair into `of` and answers whether both reads left the stream without an error (the C writes through pointers).
"Read one flag pair from two state-file unsigned integers into `of` (pcre4pl.c `load_pcre_options_flag`)."
function re_load_options_flag(fd::IOSTREAM, of::re_options_flags)::Bool
    ok1, seen = PL_qlf_get_uint32(fd)
    of.seen = seen
    ok1 || return false
    ok2, flags = PL_qlf_get_uint32(fd)
    of.flags = flags
    return ok2
end

# PORT: packages/pcre/pcre4pl.c save_pcre
# DIVERGES: 13. `put_atom(pattern, fd)::Bool` stands for `PL_qlf_put_atom(re->pattern, fd)`, which exists only inside a qlf write state. The capture
# names and the compiled code are not saved (the load recompiles), as the C.
"Write `re` to a state file: version 1, the pattern atom, then the nine flag pairs (pcre4pl.c `save_pcre`); true if every write succeeded."
function re_save_fields(re::re_data, fd::IOSTREAM, put_atom::Function)::Bool
    return PL_qlf_put_uint32(UInt32(1), fd) &&
        put_atom(re.pattern, fd) &&
        re_save_options_flag(re.compile_options_flags, fd) &&
        re_save_options_flag(re.capture_type, fd) &&
        re_save_options_flag(re.optimise_flags, fd) &&
        re_save_options_flag(re.jit_options_flags, fd) &&
        re_save_options_flag(re.compile_ctx_flags, fd) &&
        re_save_options_flag(re.compile_bsr_flags, fd) &&
        re_save_options_flag(re.compile_newline_flags, fd) &&
        re_save_options_flag(re.match_options_flags, fd) &&
        re_save_options_flag(re.start_flags, fd)
end

# PORT: packages/pcre/pcre4pl.c load_pcre (up to the recompile)
# DIVERGES: 13. `get_atom(fd)::Union{Nothing,String}` stands for `PL_qlf_get_atom` (the pattern's text, or nothing on a failure); the result is the regex with
# the saved flag pairs and the pattern, or `nothing` (the C's `(atom_t)0`) after a version other than 1 (the stream gets `SIO_FERR` with the C's message) or a
# failed read. `PL_warning` is not printed (no port yet). The recompile (`re_compile_impl`) and the blob are not ported: the caller of this piece does them.
"Read the fields `save_pcre` wrote from a state file into a regex (pcre4pl.c `load_pcre`, up to the recompile); nothing on a failure."
function re_load_fields(fd::IOSTREAM, get_atom::Function)::Union{Nothing, re_data}
    _, version = PL_qlf_get_uint32(fd)
    if version != 1
        Sseterr(fd, SIO_FERR, "Version mismatch for PCRE2 blob load")
        return nothing
    end
    pattern = get_atom(fd)
    pattern === nothing && return nothing
    re = re_init_data(pattern)
    if !re_load_options_flag(fd, re.compile_options_flags) ||
            !re_load_options_flag(fd, re.capture_type) ||
            !re_load_options_flag(fd, re.optimise_flags) ||
            !re_load_options_flag(fd, re.jit_options_flags) ||
            !re_load_options_flag(fd, re.compile_ctx_flags) ||
            !re_load_options_flag(fd, re.compile_bsr_flags) ||
            !re_load_options_flag(fd, re.compile_newline_flags) ||
            !re_load_options_flag(fd, re.match_options_flags) ||
            !re_load_options_flag(fd, re.start_flags)
        return nothing
    end
    return re
end
