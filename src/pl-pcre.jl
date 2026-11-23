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

# PORT: packages/pcre/pcre4pl.c cap_how
# DIVERGES: 16 (piece 9 header, below). `name` is the capture's name (the C atom, 0 for an unnamed capture: `nothing`), `type` one of the CAP_* values.
"A capture's name and type (pcre4pl.c `cap_how`): `name` is `nothing` for a capture referenced by its number alone."
mutable struct re_cap_how
    name::Union{Nothing, String}
    type::Int
end
re_cap_how() = re_cap_how(nothing, CAP_DEFAULT)

# PORT: packages/pcre/pcre4pl.c re_data (the option fields), init_re_data, get_re_copy (the reset of the match flags)
# DIVERGES: see the piece 2 header, 6; 16 (piece 9 header, below): `capture_names` and `code` (the C's `capture_names` and `re_compiled`).
"The option part of a regex (pcre4pl.c `re_data`): the flag pairs of the compile, capture, optimise, JIT, context, bsr, newline, match and start options, the capture names and the compiled code."
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
    capture_names::Vector{re_cap_how}   # the C's `cap_how *`: empty until `init_capture_map` fills capture_size+1 entries (NULL)
    code::Ptr{Cvoid}                    # the C's `re_compiled` (pcre2_code_8 *): C_NULL until compiled
end

"A regex's option fields as `init_re_data` leaves them: utf and no UTF check to compile, no UTF check to match, the string capture type (pcre4pl.c)."
function re_init_data(pattern::String = "")::re_data
    re = re_data(
        pattern, Threads.atomic_add!(_re_serial, 1) + 1, re_options_flags(), re_options_flags(), re_options_flags(), re_options_flags(), re_options_flags(),
        re_options_flags(), re_options_flags(), re_options_flags(), re_options_flags(), UInt32(0),
        re_cap_how[], C_NULL
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

# ---------------------------------------------------------------------------------------------------------------------------------
# PCRE1 piece 9 (packages/pcre/pcre4pl.c, packages-pcre a5e4c885; evidence/R2/pcre_plan.md sections 2, 3 and 6 A): THE CARRIER BINDING. D-1002 (Shivaji):
# PCRE is implemented as a `ccall` to PCRE2_jll (the stdlib JLL that carries libpcre2-8: Project.toml allows exactly it and PrecompileTools). Below: the
# `PCRE2_ERROR_*`, `PCRE2_INFO_*` and `PCRE2_UNSET` values the C uses (read by a script from Julia's `Base.PCRE`, share/julia/base/pcre_h.jl, not typed; the
# test compares each with `Base.PCRE`), then the 15 libpcre2 entry points the C calls (the 8-bit `_8` names, C line numbers in each comment) as typed
# wrappers, and `re_data` gained `capture_names` and `code` (piece 2's struct). NOT PORTED here: `pcre2_substitute`, `pcre2_dfa_match`, `pcre2_pattern_convert`
# (named in the C's comments and tables, never called), match contexts, the JIT stack, and everything that calls these wrappers (compile, match, config,
# the capture map: the next pieces). Nothing here has run (no Julia process was started).
#
# DIVERGES (piece 9; 15 is reserved by the plan for the `\K` guard of the match piece):
#  16. `re_data.capture_names` is a Vector{re_cap_how} (the C's `cap_how *`, NULL until `init_capture_map`: empty here; a name atom 0 is `nothing`, a name
#      is the atom's text, as `pattern`, 10), `re_data.code` is the C's `re_compiled` (C_NULL for NULL); the blob's `symbol` is not a field (no blob yet).
#  17. The wrappers return their out-parameters as a tuple (`pcre2_compile`: `(code, errcode, erroff)`; `pcre2_pattern_info`: `(rc, value)`) and the subject
#      of `pcre2_match` is a `Vector{UInt8}` with its length passed (the C's `PCRE2_SPTR` and `len`); the match context is always NULL, as the C. `pcre2_get_error_message`
#      answers `nothing` where the C tests `rc < 0` (the match error's fallback text "regex" is `re_error`'s, a later piece). `pcre2_get_ovector_pointer` is the
#      raw pointer; `pcre2_ovector_copy(md, rc)` is the copy of its `2*rc` values that the C reads in place (the pointer dies with `match_data`).
#  18. `pcre2_config_` of the C is the plain `pcre2_config` (`FORCE_NO_JIT` is off), and the result buffer of the 100-byte union is a `Vector{UInt8}` read through
#      `pcre2_config_u32`/`_i32`/`_str`. The `pcre2_config(flag, NULL)` form (the C's FORCE_NO_JIT wrapper only) is not bound.
using PCRE2_jll: libpcre2_8

# PORT: packages/pcre/pcre4pl.c PCRE2_ERROR_* (860, 989, 1026, 1168-1177, 1659-1680, 1819), PCRE2_INFO_* (1139-1142, 1206-1317), PCRE2_UNSET (1576)
const PCRE2_ERROR_NOMATCH = Cint(-1)
const PCRE2_ERROR_PARTIAL = Cint(-2)
const PCRE2_ERROR_UTF8_ERR1 = Cint(-3)
const PCRE2_ERROR_UTF8_ERR21 = Cint(-23)
const PCRE2_ERROR_NOMEMORY = Cint(-48)
const PCRE2_ERROR_MATCHLIMIT = Cint(-47)
const PCRE2_ERROR_DEPTHLIMIT = Cint(-53)
const PCRE2_ERROR_HEAPLIMIT = Cint(-63)
const PCRE2_ERROR_JIT_STACKLIMIT = Cint(-46)
const PCRE2_ERROR_BADOFFSET = Cint(-33)
const PCRE2_ERROR_NULL = Cint(-51)
const PCRE2_ERROR_BADOPTION = Cint(-34)
const PCRE2_ERROR_BADMAGIC = Cint(-31)
const PCRE2_ERROR_UNSET = Cint(-55)

const PCRE2_INFO_ARGOPTIONS = UInt32(1)
const PCRE2_INFO_BSR = UInt32(3)
const PCRE2_INFO_CAPTURECOUNT = UInt32(4)
const PCRE2_INFO_EXTRAOPTIONS = UInt32(26)
const PCRE2_INFO_NAMECOUNT = UInt32(17)
const PCRE2_INFO_NAMEENTRYSIZE = UInt32(18)
const PCRE2_INFO_NAMETABLE = UInt32(19)
const PCRE2_INFO_NEWLINE = UInt32(20)
# `(PCRE2_SIZE)~0`: the ovector value of a group that did not participate in the match.
const PCRE2_UNSET = ~Csize_t(0)

# PORT: packages/pcre/pcre4pl.c free_pcre (188): pcre2_code_free
# DIVERGES: 17 (typed). `code` may be C_NULL (the C frees `re->re_compiled` after a failed compile): libpcre2 does nothing then.
"Free a compiled pattern (pcre4pl.c `free_pcre`'s `pcre2_code_free`); a NULL `code` is a no-op."
function pcre2_code_free(code::Ptr{Cvoid})::Nothing
    ccall((:pcre2_code_free_8, libpcre2_8), Cvoid, (Ptr{Cvoid},), code)
    return nothing
end

# PORT: packages/pcre/pcre4pl.c re_compile_impl (1451): pcre2_compile
# DIVERGES: 17. The C passes `(PCRE2_SPTR)pats, len`; `len` is `length(pat)` here. C_NULL `ctx` = no compile context.
"Compile `pat` (UTF-8 bytes) with `options` and the compile context `ctx` (or C_NULL): `(code, errcode, erroff)`; `code` is C_NULL on an error (pcre4pl.c `re_compile_impl`)."
function pcre2_compile(pat::Vector{UInt8}, options::UInt32, ctx::Ptr{Cvoid})::Tuple{Ptr{Cvoid}, Cint, Csize_t}
    errcode = Ref{Cint}(0)
    erroff = Ref{Csize_t}(0)
    code = ccall(
        (:pcre2_compile_8, libpcre2_8), Ptr{Cvoid},
        (Ptr{UInt8}, Csize_t, UInt32, Ref{Cint}, Ref{Csize_t}, Ptr{Cvoid}),
        pat, length(pat), options, errcode, erroff, ctx
    )
    return (code, errcode[], erroff[])
end

# PORT: packages/pcre/pcre4pl.c re_compile_impl (1454): pcre2_jit_compile
"JIT-compile `code` with `flags` (the C ignores the result): 0, or a negative PCRE2 error (pcre4pl.c `re_compile_impl`)."
function pcre2_jit_compile(code::Ptr{Cvoid}, flags::UInt32)::Cint
    return ccall((:pcre2_jit_compile_8, libpcre2_8), Cint, (Ptr{Cvoid}, UInt32), code, flags)
end

# PORT: packages/pcre/pcre4pl.c ensure_compile_context (757), re_compile_impl (1470), re_portray_match_options_ (1544): pcre2_compile_context_create/_free
"A new compile context with the default general context (pcre4pl.c `ensure_compile_context`); C_NULL when out of memory."
function pcre2_compile_context_create()::Ptr{Cvoid}
    return ccall((:pcre2_compile_context_create_8, libpcre2_8), Ptr{Cvoid}, (Ptr{Cvoid},), C_NULL)
end

"Free a compile context (pcre4pl.c `re_compile_impl`, `re_portray_match_options_`); a NULL `ctx` is a no-op."
function pcre2_compile_context_free(ctx::Ptr{Cvoid})::Nothing
    ccall((:pcre2_compile_context_free_8, libpcre2_8), Cvoid, (Ptr{Cvoid},), ctx)
    return nothing
end

# PORT: packages/pcre/pcre4pl.c re_compile_impl (1423, 1433, 1443): pcre2_set_bsr, pcre2_set_newline, pcre2_set_compile_extra_options
"Set the compile context's `\\R` convention (pcre4pl.c `re_compile_impl`): 0, nonzero for an invalid `value`."
function pcre2_set_bsr(ctx::Ptr{Cvoid}, value::UInt32)::Cint
    return ccall((:pcre2_set_bsr_8, libpcre2_8), Cint, (Ptr{Cvoid}, UInt32), ctx, value)
end

"Set the compile context's newline convention (pcre4pl.c `re_compile_impl`): 0, nonzero for an invalid `value`."
function pcre2_set_newline(ctx::Ptr{Cvoid}, value::UInt32)::Cint
    return ccall((:pcre2_set_newline_8, libpcre2_8), Cint, (Ptr{Cvoid}, UInt32), ctx, value)
end

"Set the compile context's extra options (pcre4pl.c `re_compile_impl`): 0 (libpcre2 never fails here)."
function pcre2_set_compile_extra_options(ctx::Ptr{Cvoid}, value::UInt32)::Cint
    return ccall((:pcre2_set_compile_extra_options_8, libpcre2_8), Cint, (Ptr{Cvoid}, UInt32), ctx, value)
end

# PORT: packages/pcre/pcre4pl.c init_capture_map (1139-1142), get_pcre2_info (1164, with what = ARGOPTIONS 1209, EXTRAOPTIONS 1256, BSR 1281, NEWLINE 1296): pcre2_pattern_info
# DIVERGES: 17. `T` is UInt32 for CAPTURECOUNT, NAMECOUNT, NAMEENTRYSIZE, ARGOPTIONS, EXTRAOPTIONS, BSR and NEWLINE (the C declares `int name_count`,
# `int name_entry_size`: the library writes 32 bits), `Ptr{UInt8}` for NAMETABLE. The value is `T(0)` when `rc != 0`.
"Ask `code` for `what` (a `PCRE2_INFO_*`): `(rc, value::T)`, `rc` 0 when the library wrote `value` (pcre4pl.c `init_capture_map`, `get_pcre2_info`)."
function pcre2_pattern_info(code::Ptr{Cvoid}, what::UInt32, ::Type{T})::Tuple{Cint, T} where {T}
    r = Ref{T}(T(0))
    rc = ccall((:pcre2_pattern_info_8, libpcre2_8), Cint, (Ptr{Cvoid}, UInt32, Ptr{Cvoid}), code, what, r)
    return (rc, r[])
end

# PORT: packages/pcre/pcre4pl.c re_config_ (1027), write_re_options (1298): pcre2_config
# DIVERGES: 18. `buf` is the 100-byte result union `{uint32_t, int32_t, char[100]}` of the C (`PCRE2_CONFIG_JITTARGET` needs at least 48).
"Ask libpcre2 for the build-time `what` (a `PCRE2_CONFIG_*`), written into `buf`: 0 (an int), the byte count (a string), a negative PCRE2 error (pcre4pl.c `re_config_`)."
function pcre2_config(what::UInt32, buf::Vector{UInt8})::Cint
    return ccall((:pcre2_config_8, libpcre2_8), Cint, (UInt32, Ptr{Cvoid}), what, buf)
end

"The 100-byte result buffer `pcre2_config` writes into (the C's `val` union), zeroed."
pcre2_config_buf()::Vector{UInt8} = zeros(UInt8, 100)

"The `uint32_t` member of a `pcre2_config_buf` after `pcre2_config` (the C's `val.i_unsigned`)."
function pcre2_config_u32(buf::Vector{UInt8})::UInt32
    return GC.@preserve buf unsafe_load(Ptr{UInt32}(pointer(buf)))
end

"The `int32_t` member of a `pcre2_config_buf` after `pcre2_config` (the C's `val.i_signed`)."
function pcre2_config_i32(buf::Vector{UInt8})::Int32
    return GC.@preserve buf unsafe_load(Ptr{Int32}(pointer(buf)))
end

"The NUL-terminated string in a `pcre2_config_buf` after `pcre2_config` (the C's `val.s_buf`)."
function pcre2_config_str(buf::Vector{UInt8})::String
    return GC.@preserve buf unsafe_string(pointer(buf))
end

# PORT: packages/pcre/pcre4pl.c re_matchsub_ (1712), re_foldl_ (1786): pcre2_match_data_create_from_pattern; re_matchsub_ (1737), re_foldl_ (1829): pcre2_match_data_free
"A match data block sized for `code` with the default general context (pcre4pl.c `re_matchsub_`, `re_foldl_`); C_NULL when out of memory."
function pcre2_match_data_create_from_pattern(code::Ptr{Cvoid})::Ptr{Cvoid}
    return ccall((:pcre2_match_data_create_from_pattern_8, libpcre2_8), Ptr{Cvoid}, (Ptr{Cvoid}, Ptr{Cvoid}), code, C_NULL)
end

"Free a match data block (pcre4pl.c `re_matchsub_`, `re_foldl_`); a NULL `md` is a no-op."
function pcre2_match_data_free(md::Ptr{Cvoid})::Nothing
    ccall((:pcre2_match_data_free_8, libpcre2_8), Cvoid, (Ptr{Cvoid},), md)
    return nothing
end

# PORT: packages/pcre/pcre4pl.c re_matchsub_ (1720), re_foldl_ (1796): pcre2_match
# DIVERGES: 17. `len` is the byte length the C passes (`subject.length`), `start` the byte offset (`utf8_start`); the match context is NULL, as the C.
"Match `code` against the first `len` bytes of `subject` from byte `start` with `options`, into `md`: the highest captured group + 1, or a negative PCRE2 error (pcre4pl.c)."
function pcre2_match(code::Ptr{Cvoid}, subject::Vector{UInt8}, len::Int, start::Int, options::UInt32, md::Ptr{Cvoid})::Cint
    return ccall(
        (:pcre2_match_8, libpcre2_8), Cint,
        (Ptr{Cvoid}, Ptr{UInt8}, Csize_t, Csize_t, UInt32, Ptr{Cvoid}, Ptr{Cvoid}),
        code, subject, len, start, options, md, C_NULL
    )
end

# PORT: packages/pcre/pcre4pl.c re_matchsub_ (1728), re_foldl_ (1801): pcre2_get_ovector_pointer
"The ovector of `md` (valid until `md` is freed): pairs of start and end byte offsets (pcre4pl.c `re_matchsub_`, `re_foldl_`)."
function pcre2_get_ovector_pointer(md::Ptr{Cvoid})::Ptr{Csize_t}
    return ccall((:pcre2_get_ovector_pointer_8, libpcre2_8), Ptr{Csize_t}, (Ptr{Cvoid},), md)
end

# DIVERGES: 17. The C reads `ovector[0 .. 2*rc-1]` in place; the copy outlives `md`.
"The first `2*rc` values of `md`'s ovector (`rc` is `pcre2_match`'s result) as a Vector (the C reads them in place in `unify_match`)."
function pcre2_ovector_copy(md::Ptr{Cvoid}, rc::Int)::Vector{Csize_t}
    p = pcre2_get_ovector_pointer(md)
    n = max(2 * rc, 0)
    out = Vector{Csize_t}(undef, n)
    for i in 1:n
        out[i] = unsafe_load(p, i)
    end
    return out
end

# PORT: packages/pcre/pcre4pl.c re_compile_impl (1464), re_error (1682): pcre2_get_error_message
# DIVERGES: 17. The C's buffer is 256 bytes and it passes `sizeof - 1` (compile) or `sizeof` (match) as the length: `buflen` is that length and the buffer is as long.
"The text of the PCRE2 error `code` (a compile `errcode` or a match result), or `nothing` when libpcre2 answers a negative (unknown code, buffer too small) (pcre4pl.c)."
function pcre2_get_error_message(code::Integer, buflen::Int = 256)::Union{Nothing, String}
    buf = Vector{UInt8}(undef, max(buflen, 0))
    rc = ccall((:pcre2_get_error_message_8, libpcre2_8), Cint, (Cint, Ptr{UInt8}, Csize_t), code, buf, buflen)
    rc < 0 && return nothing
    return GC.@preserve buf unsafe_string(pointer(buf), rc)
end

# ---------------------------------------------------------------------------------------------------------------------------------
# PCRE1 piece 10 (packages/pcre/pcre4pl.c, packages-pcre a5e4c885; evidence/R2/pkg2_handoff.md "PCRE-CODE-B"), first half (B1): COMPILE. `free_pcre`,
# `ensure_compile_context`, `re_compile_impl`, `re_verify_pats`, `init_capture_map` and `set_capture_name_and_type`, over the piece 9 wrappers. Nothing here
# has run (no Julia process was started). The second half (config, option text) is the next commit.
#
# DIVERGES (piece 10; 15 stays reserved for the `\K` guard of the match piece):
#  19. `re_free` has no atom to unregister (no atom GC: `pattern` and the capture names are Strings): it frees the code, sets `code` to C_NULL and empties
#      `capture_names`. The C's `re->pattern = 0` is NOT ported (the C's own TODO says clearing is not necessary): `pattern` keeps its text.
#  20. `len` of the C is `length(pats)` (`pats` is a Vector{UInt8}); the C's `goto out` is a helper, `_re_compile_impl_try`, whose result the caller closes
#      (`pcre2_compile_context_free`, `re_free` on a failure). The C's uninitialised `re_error_msg` (when `pcre2_get_error_message` fails) is "" here.
#  21. `init_capture_map` has no `malloc` failure branch (a Vector); the C's `int name_count`/`name_entry_size` are UInt32 (piece 9, 17).
#  Errors: `representation_error(Sym)` is `PL_error(ld, ERR_REPRESENTATION, mk_sym(T, Sym))` (as pl-bisim.jl does), `existence_error(re_type_flag, X)` the
#  `ERR_EXISTENCE` form with `X` an atom term; the C's `PL_put_atom_chars(ex, &fs[1])` (one Latin-1 byte) is `Char(byte)` here.
# ---------------------------------------------------------------------------------------------------------------------------------

# PORT: packages/pcre/pcre4pl.c free_pcre
# DIVERGES: 19.
"Free a regex's compiled code and capture names (pcre4pl.c `free_pcre`); always true. Safe to call twice."
function re_free(re::re_data)::Bool
    pcre2_code_free(re.code)
    re.code = C_NULL
    re.capture_names = re_cap_how[]
    return true
end

# PORT: packages/pcre/pcre4pl.c ensure_compile_context
"Make `ctx[]` a compile context if it is NULL (pcre4pl.c `ensure_compile_context`); a `resource_error(memory)` and false when libpcre2 cannot allocate one."
function re_ensure_compile_context(ld::PL_local_data{T}, ctx::Ref{Ptr{Cvoid}})::Bool where {T}
    ctx[] == C_NULL && (ctx[] = pcre2_compile_context_create())
    ctx[] == C_NULL && return PL_resource_error(ld, "memory")
    return true
end

# PORT: packages/pcre/pcre4pl.c re_compile_impl (the body between the declarations and `out:`)
# DIVERGES: 20. The `flags != 0` guards, the three `0 != pcre2_set_*` checks and the JIT/capture-map tail are as the C.
function _re_compile_impl_try(ld::PL_local_data{T}, re::re_data, pats::Vector{UInt8}, ctx::Ref{Ptr{Cvoid}})::Bool where {T}
    if re.compile_bsr_flags.flags != 0
        re_ensure_compile_context(ld, ctx) || return false
        if 0 != pcre2_set_bsr(ctx[], re.compile_bsr_flags.flags)
            return PL_error(ld, ERR_REPRESENTATION, mk_sym(T, Symbol("option:bsr")))
        end
    end
    if re.compile_newline_flags.flags != 0
        re_ensure_compile_context(ld, ctx) || return false
        if 0 != pcre2_set_newline(ctx[], re.compile_newline_flags.flags)
            return PL_error(ld, ERR_REPRESENTATION, mk_sym(T, Symbol("option:newline")))
        end
    end
    if re.compile_ctx_flags.flags != 0
        re_ensure_compile_context(ld, ctx) || return false
        if 0 != pcre2_set_compile_extra_options(ctx[], re.compile_ctx_flags.flags)
            return PL_error(ld, ERR_REPRESENTATION, mk_sym(T, Symbol("option:extra")))
        end
    end
    (code, ec, _) = pcre2_compile(pats, re.compile_options_flags.flags, ctx[])
    re.code = code
    if code != C_NULL
        if (re.optimise_flags.flags & RE_OPTIMISE) != 0
            pcre2_jit_compile(code, re.jit_options_flags.flags)       # the result is ignored, as the C (TBD there)
        end
        return re_init_capture_map(ld, re)
    end
    msg = pcre2_get_error_message(ec, 255)                           # the C passes `sizeof re_error_msg - 1`
    return PL_syntax_error(ld, msg === nothing ? "" : msg, nothing)
end

# PORT: packages/pcre/pcre4pl.c re_compile_impl
# DIVERGES: 20.
"Compile `pats` (UTF-8 bytes, no NUL) with the options in `re` into `re.code` and fill the capture map (pcre4pl.c `re_compile_impl`); on a failure an error is pending, `re` is freed and false is returned."
function re_compile_impl(ld::PL_local_data{T}, re::re_data, pats::Vector{UInt8})::Bool where {T}
    ctx = Ref{Ptr{Cvoid}}(C_NULL)
    rc = _re_compile_impl_try(ld, re, pats, ctx)
    pcre2_compile_context_free(ctx[])
    rc || re_free(re)
    return rc
end

# PORT: packages/pcre/pcre4pl.c re_verify_pats
"True unless `pats` holds a NUL byte, then `representation_error(nul_byte)` and false (pcre4pl.c `re_verify_pats`: `strlen(pats) != len`)."
function re_verify_pats(ld::PL_local_data{T}, pats::Vector{UInt8})::Bool where {T}
    findfirst(iszero, pats) === nothing && return true
    return PL_error(ld, ERR_REPRESENTATION, mk_sym(T, :nul_byte))
end

# PORT: packages/pcre/pcre4pl.c set_capture_name_and_type
"Set the name and the type of capture `ci` (0-based) from the table name `s` (UTF-8 bytes, no NUL): `name_X` with exactly one byte `X` after the last `_` types it (pcre4pl.c `set_capture_name_and_type`)."
function re_set_capture_name_and_type(ld::PL_local_data{T}, s::Vector{UInt8}, re::re_data, ci::Int)::Bool where {T}
    @assert ci < Int(re.capture_size) + 1
    n = length(s)
    fs = findlast(==(UInt8('_')), s)
    if fs !== nothing && fs + 1 == n                                  # C: `fs[1] && !fs[2]`
        b = s[n]
        ty = b == UInt8('S') ? CAP_STRING :
            b == UInt8('A') ? CAP_ATOM :
            b == UInt8('I') ? CAP_INTEGER :
            b == UInt8('F') ? CAP_FLOAT :
            b == UInt8('N') ? CAP_NUMBER :
            b == UInt8('T') ? CAP_TERM :
            b == UInt8('R') ? CAP_RANGE : -1
        if ty < 0
            ex = PL_new_term_ref(ld)
            PL_put_atom(ld, ex, mk_sym(T, Symbol(Char(b))))
            return PL_error(ld, ERR_EXISTENCE, mk_sym(T, :re_type_flag), ex)
        end
        re.capture_names[ci + 1].type = ty
        re.capture_names[ci + 1].name = String(s[1:(fs - 1)])
    else
        re.capture_names[ci + 1].type = CAP_DEFAULT
        re.capture_names[ci + 1].name = String(copy(s))
    end
    return true
end

# PORT: packages/pcre/pcre4pl.c init_capture_map
# DIVERGES: 21.
"Read the capture count and the name table of `re.code` into `re.capture_size` and `re.capture_names` (pcre4pl.c `init_capture_map`); `resource_error(pcre2_pattern_info)` and false when libpcre2 refuses."
function re_init_capture_map(ld::PL_local_data{T}, re::re_data)::Bool where {T}
    (rc, cs) = pcre2_pattern_info(re.code, PCRE2_INFO_CAPTURECOUNT, UInt32)
    rc != 0 && return PL_resource_error(ld, "pcre2_pattern_info")
    re.capture_size = cs
    (rc, name_count) = pcre2_pattern_info(re.code, PCRE2_INFO_NAMECOUNT, UInt32)
    rc != 0 && return PL_resource_error(ld, "pcre2_pattern_info")
    (rc, entry_size) = pcre2_pattern_info(re.code, PCRE2_INFO_NAMEENTRYSIZE, UInt32)
    rc != 0 && return PL_resource_error(ld, "pcre2_pattern_info")
    (rc, table) = pcre2_pattern_info(re.code, PCRE2_INFO_NAMETABLE, Ptr{UInt8})
    rc != 0 && return PL_resource_error(ld, "pcre2_pattern_info")
    re.capture_names = [re_cap_how(nothing, CAP_DEFAULT) for _ in 0:Int(re.capture_size)]
    for i in 0:(Int(name_count) - 1)
        base = i * Int(entry_size)
        ci = ((Int(unsafe_load(table, base + 1)) & 0xff) << 8) + (Int(unsafe_load(table, base + 2)) & 0xff)
        name = UInt8[]
        k = base + 3
        while (b = unsafe_load(table, k)) != 0x00
            push!(name, b)
            k += 1
        end
        re_set_capture_name_and_type(ld, name, re, ci) || return false
    end
    return true
end

# ---------------------------------------------------------------------------------------------------------------------------------
# PCRE1 piece 10 (packages/pcre/pcre4pl.c, packages-pcre a5e4c885), second half (B2): CONFIG AND OPTION TEXT. `get_pcre2_info`, `write_option_str`,
# `write_re_options`, `next_config`, `re_config_choice_` and `re_config_`. Nothing here has run (no Julia process was started).
#
# DIVERGES (piece 10, second half):
#  22. `write_re_options` writes into an IO (the C's IOSTREAM) with the separator and the flag word as `Ref`s (the C's `const char **sep`, `uint32_t *flags`);
#      the 30 + 6 + 17 `write_option_str` calls are a loop over the tables `re_argoption_names`, `re_extraoption_names`, `re_matchoption_names` in the C's
#      order, the `#ifdef`ed rows (`MATCH_INVALID_UTF`, `EXTRA_ESCAPED_CR_IS_LF`, `EXTRA_ALT_BSUX`, `COPY_MATCHED_SUBJECT`) always present (the library of
#      this build has them all). The C's `Sdprintf` + `assert(0)` defaults (BSR, NEWLINE: a value the library never gives) are a Julia `error`.
#      `re_options_text(re)` (no C counterpart) runs it into a String from the empty separator.
#  23. `re_config_` compares the option NAME text with the row's name (the C compares atoms, DIVERGES 14); the C's `pcre2_config_(o->id, &val)` is
#      `pcre2_config(reinterpret(UInt32, id), buf)` (the C passes the `int` id to a `uint32_t` parameter: -1 becomes 0xFFFFFFFF, BADOPTION); `PL_unify_atom_chars`
#      is `PL_unify_atom(mk_sym(T, Symbol(s)))`; the C's `Sdprintf` + `assert(0)` branches are a Julia `error`; the result is `FTRUE`/`FFALSE`.
#  24. `re_config_choice_` has the C's context unchanged: the 0-based table index + 1 as the `PL_retry` integer (`re_next_config` takes the 0-based index of the
#      C). The table row's lazily filled `atom`/`functor` are not cached (DIVERGES 14): the functor is `name/1` of the row.
# ---------------------------------------------------------------------------------------------------------------------------------

# PORT: packages/pcre/pcre4pl.c get_pcre2_info
# DIVERGES: 22 (the IO instead of IOSTREAM, the value as the result, `nothing` for the C's false).
"The `info_type` value of `re.code` as a UInt32, or `nothing`: silently when there is no code, with `<descr:ERROR_...>` written to `io` when libpcre2 refuses (pcre4pl.c `get_pcre2_info`)."
function re_get_pcre2_info(io::IO, re::re_data, info_type::UInt32, descr::String)::Union{Nothing, UInt32}
    re.code == C_NULL && return nothing                  # write_re_options() has already output a message
    (rc, value) = pcre2_pattern_info(re.code, info_type, UInt32)
    rc == 0 && return value
    if rc == PCRE2_ERROR_NULL
        print(io, "<", descr, ":ERROR_NULL>")
    elseif rc == PCRE2_ERROR_BADMAGIC
        print(io, "<", descr, ":ERROR_BADMAGIC>")
    elseif rc == PCRE2_ERROR_BADOPTION
        print(io, "<", descr, ":ERROR_BADOPTION>")
    elseif rc == PCRE2_ERROR_UNSET
        print(io, "<", descr, ":ERROR_UNSET>")
    else
        print(io, "<", descr, ":ERROR_[", rc, "]>")
    end
    return nothing
end

# PORT: packages/pcre/pcre4pl.c write_option_str
# DIVERGES: 22.
"If `field_flag` is set in `flags[]`, write `sep[]` and `name` to `io`, make `sep[]` a space and clear the flag (pcre4pl.c `write_option_str`)."
function re_write_option_str(io::IO, sep::Ref{String}, flags::Ref{UInt32}, field_flag::UInt32, name::String)::Nothing
    if (flags[] & field_flag) != 0
        print(io, sep[], name)
        sep[] = " "
        flags[] &= ~field_flag
    end
    return nothing
end

# PORT: packages/pcre/pcre4pl.c write_re_options (the write_option_str rows of the three flag words, in the C's order)
# DIVERGES: 22.
const re_argoption_names = Tuple{UInt32, String}[
    (PCRE2_ANCHORED, "compile-ANCHORED"),
    (PCRE2_ENDANCHORED, "compile-ENDANCHORED"),
    (PCRE2_ALLOW_EMPTY_CLASS, "ALLOW_EMPTY_CLASS"),
    (PCRE2_ALT_BSUX, "ALT_BSUX"),
    (PCRE2_AUTO_CALLOUT, "AUTO_CALLOUT"),
    (PCRE2_CASELESS, "CASELESS"),
    (PCRE2_DOLLAR_ENDONLY, "DOLLAR_ENDONLY"),
    (PCRE2_DOTALL, "DOTALL"),
    (PCRE2_DUPNAMES, "DUPNAMES"),
    (PCRE2_EXTENDED, "EXTENDED"),
    (PCRE2_FIRSTLINE, "FIRSTLINE"),
    (PCRE2_MATCH_UNSET_BACKREF, "MATCH_UNSET_BACKREF"),
    (PCRE2_MULTILINE, "MULTILINE"),
    (PCRE2_NEVER_UCP, "NEVER_UCP"),
    (PCRE2_NEVER_UTF, "NEVER_UTF"),
    (PCRE2_NO_AUTO_CAPTURE, "NO_AUTO_CAPTURE"),
    (PCRE2_NO_AUTO_POSSESS, "NO_AUTO_POSSESS"),
    (PCRE2_NO_DOTSTAR_ANCHOR, "NO_DOTSTAR_ANCHOR"),
    (PCRE2_NO_START_OPTIMIZE, "NO_START_OPTIMIZE"),
    (PCRE2_UCP, "UCP"),
    (PCRE2_UNGREEDY, "UNGREEDY"),
    (PCRE2_NEVER_BACKSLASH_C, "NEVER_BACKSLASH_C"),
    (PCRE2_ALT_CIRCUMFLEX, "ALT_CIRCUMFLEX"),
    (PCRE2_ALT_VERBNAMES, "ALT_VERBNAMES"),
    (PCRE2_USE_OFFSET_LIMIT, "USE_OFFSET_LIMIT"),
    (PCRE2_EXTENDED_MORE, "EXTENDED_MORE"),
    (PCRE2_LITERAL, "LITERAL"),
    (PCRE2_MATCH_INVALID_UTF, "MATCH_INVALID_UTF"),
]

const re_extraoption_names = Tuple{UInt32, String}[
    (PCRE2_EXTRA_ALLOW_SURROGATE_ESCAPES, "EXTRA_ALLOW_SURROGATE_ESCAPES"),
    (PCRE2_EXTRA_BAD_ESCAPE_IS_LITERAL, "EXTRA_BAD_ESCAPE_IS_LITERAL"),
    (PCRE2_EXTRA_MATCH_WORD, "EXTRA_MATCH_WORD"),
    (PCRE2_EXTRA_MATCH_LINE, "EXTRA_MATCH_LINE"),
    (PCRE2_EXTRA_ESCAPED_CR_IS_LF, "EXTRA_ESCAPED_CR_IS_LF"),
    (PCRE2_EXTRA_ALT_BSUX, "EXTRA_ALT_BSUX"),
]

const re_matchoption_names = Tuple{UInt32, String}[
    (PCRE2_ANCHORED, "match-ANCHORED"),
    (PCRE2_ENDANCHORED, "match-ENDANCHORED"),
    (PCRE2_NOTBOL, "NOTBOL"),
    (PCRE2_NOTEOL, "NOTEOL"),
    (PCRE2_NOTEMPTY, "NOTEMPTY"),
    (PCRE2_NOTEMPTY_ATSTART, "NOTEMPTY_ATSTART"),
    (PCRE2_PARTIAL_SOFT, "PARTIAL_SOFT"),
    (PCRE2_PARTIAL_HARD, "PARTIAL_HARD"),
    (PCRE2_DFA_RESTART, "DFA_RESTART"),
    (PCRE2_DFA_SHORTEST, "DFA_SHORTEST"),
    (PCRE2_SUBSTITUTE_GLOBAL, "SUBSTITUTE_GLOBAL"),
    (PCRE2_SUBSTITUTE_EXTENDED, "SUBSTITUTE_EXTENDED"),
    (PCRE2_SUBSTITUTE_UNSET_EMPTY, "SUBSTITUTE_UNSET_EMPTY"),
    (PCRE2_SUBSTITUTE_UNKNOWN_UNSET, "SUBSTITUTE_UNKNOWN_UNSET"),
    (PCRE2_SUBSTITUTE_OVERFLOW_LENGTH, "SUBSTITUTE_OVERFLOW_LENGTH"),
    (PCRE2_NO_JIT, "NO_JIT"),
    (PCRE2_COPY_MATCHED_SUBJECT, "COPY_MATCHED_SUBJECT"),
]

# the `<all:remainder:0x%08x>` tail of a flag word
function _re_write_remainder(io::IO, sep::Ref{String}, flags::Ref{UInt32})::Nothing
    if flags[] != 0
        print(io, sep[], "<all:remainder:0x", string(flags[], base = 16, pad = 8), ">")
        sep[] = " "
    end
    return nothing
end

# PORT: packages/pcre/pcre4pl.c write_re_options
# DIVERGES: 22. The NEWLINE branch does not set `sep[]` after printing, as the C (the C writes `NEWLINE_x` and leaves `sep` unchanged).
"Write the options of `re` (the compile options of the code, its context options, `\\R` and newline conventions, the match options) to `io` as names separated by `sep[]` (pcre4pl.c `write_re_options`)."
function re_write_re_options(io::IO, sep::Ref{String}, re::re_data)::Nothing
    if re.code == C_NULL
        print(io, sep[], "<no re_compiled>")
        sep[] = " "
    end

    ui = re_get_pcre2_info(io, re, PCRE2_INFO_ARGOPTIONS, "INFO_ARGOPTIONS")
    if ui !== nothing
        flags = Ref(ui)
        # PCRE2_NO_UTF_CHECK and PCRE2_UTF default to true
        if (flags[] & PCRE2_NO_UTF_CHECK) == 0
            print(io, sep[], "compile-~NO_UTF_CHECK")
            sep[] = " "
        end
        flags[] &= ~PCRE2_NO_UTF_CHECK
        if (flags[] & PCRE2_UTF) == 0
            print(io, sep[], "compile-~UTF")
            sep[] = " "
        end
        flags[] &= ~PCRE2_UTF
        for (f, name) in re_argoption_names
            re_write_option_str(io, sep, flags, f, name)
        end
        _re_write_remainder(io, sep, flags)
    end

    ui = re_get_pcre2_info(io, re, PCRE2_INFO_EXTRAOPTIONS, "INFO_EXTRAOPTIONS")
    if ui !== nothing
        flags = Ref(ui)
        for (f, name) in re_extraoption_names
            re_write_option_str(io, sep, flags, f, name)
        end
        _re_write_remainder(io, sep, flags)
    end

    ui = re_get_pcre2_info(io, re, PCRE2_INFO_BSR, "INFO_BSR")
    if ui !== nothing
        c = ui == PCRE2_BSR_ANYCRLF ? "BSR_ANYCRLF" :
            ui == PCRE2_BSR_UNICODE ? "BSR_UNICODE" :
            error("GET_PCRE2_INFO_BSR: 0x", string(ui, base = 16, pad = 8))    # the C: Sdprintf + assert(0)
        print(io, sep[], c)
        sep[] = " "
    end

    ui = re_get_pcre2_info(io, re, PCRE2_INFO_NEWLINE, "INFO_NEWLINE")
    if ui !== nothing
        buf = pcre2_config_buf()
        rc_c = pcre2_config(PCRE2_CONFIG_NEWLINE, buf)
        config_ui = pcre2_config_u32(buf)
        if rc_c >= 0 && (
                (config_ui == PCRE2_NEWLINE_CRLF && ui == PCRE2_NEWLINE_CRLF) ||
                    (config_ui == PCRE2_NEWLINE_CR && ui == PCRE2_NEWLINE_CR) ||
                    (config_ui == PCRE2_NEWLINE_LF && ui == PCRE2_NEWLINE_LF)
            )
            # do nothing: the newline convention is the build's default
        else
            c = ui == PCRE2_NEWLINE_CR ? "NEWLINE_CR" :
                ui == PCRE2_NEWLINE_LF ? "NEWLINE_LF" :
                ui == PCRE2_NEWLINE_CRLF ? "NEWLINE_CRLF" :
                ui == PCRE2_NEWLINE_ANY ? "NEWLINE_ANY" :
                ui == PCRE2_NEWLINE_ANYCRLF ? "NEWLINE_ANYCRLF" :
                ui == PCRE2_NEWLINE_NUL ? "NEWLINE_NUL" :
                error("GET_PCRE2_INFO_NEWLINE: 0x", string(ui, base = 16, pad = 8))    # the C: Sdprintf + assert(0)
            print(io, sep[], c)
        end
    end

    flags = Ref(re.match_options_flags.flags)
    # PCRE2_NO_UTF_CHECK defaults to true
    if (flags[] & PCRE2_NO_UTF_CHECK) == 0
        print(io, sep[], "match-~NO_UTF_CHECK")
        sep[] = " "
    end
    flags[] &= ~PCRE2_NO_UTF_CHECK
    for (f, name) in re_matchoption_names
        re_write_option_str(io, sep, flags, f, name)
    end
    _re_write_remainder(io, sep, flags)
    return nothing
end

# DIVERGES: 22 (no C counterpart): the option text of `re` as a String, the separator starting empty (what `re_portray_match_options_`-like callers print).
"The text `re_write_re_options` writes for `re`, starting from the empty separator."
function re_options_text(re::re_data)::String
    io = IOBuffer()
    re_write_re_options(io, Ref(""), re)
    return String(take!(io))
end

# PORT: packages/pcre/pcre4pl.c next_config
# DIVERGES: 24. `i` is the 0-based table index of the C; the lazily filled atom and functor are not cached (14).
"The 0-based index of the first row of `re_cfg_opts` at or after the 0-based index `i` that is not invalid or for PCRE1 compatibility, or -1 (pcre4pl.c `next_config`)."
function re_next_config(i::Int)::Int
    for j in i:(length(re_cfg_opts) - 1)
        t = re_cfg_opts[j + 1].type_
        if t == CFG_INVALID || t == CFG_BOOL_BKWD || t == CFG_INTEGER_BKWD || t == CFG_TRUE_BKWD || t == CFG_FALSE_BKWD
            continue
        end
        return j
    end
    return -1
end

# PORT: packages/pcre/pcre4pl.c re_config_choice_
# DIVERGES: 24. `PL_uninstantiation_error(choice)` is `PL_error(ld, "", 0, "", ERR_UNINSTANTIATION, 0, choice)` (as pl-rec.jl), false.
"`re_config_choice_(-Choice)` is nondet: unify `Choice` with `Name(_)` for each option `re_config_` accepts, in table order (pcre4pl.c `re_config_choice_`)."
function re_config_choice_(ld::PL_local_data{T}, choice::term_t, h::control_t{T})::foreign_t where {T}
    ctl = PL_foreign_control(h)
    if ctl == FRG_FIRST_CALL
        index = 0
    elseif ctl == FRG_REDO
        index = PL_foreign_context(h)
    elseif ctl == FRG_CUTTED
        return FTRUE
    else
        error("re_config_choice_: control ", ctl)                         # the C: assert(0); PL_fail
    end

    if !PL_is_variable(ld, choice)
        PL_error(ld, "", 0, "", ERR_UNINSTANTIATION, 0, choice)
        return FFALSE
    end

    index = re_next_config(index)
    if index >= 0 && PL_unify_functor(ld, choice, mk_sym(T, Symbol(re_cfg_opts[index + 1].name)), 1)
        return PL_retry(index + 1)
    end
    return FFALSE
end

# the answer of `pcre2_config` for row `o` (rc >= 0 or not) as the C's two `switch`es
function _re_config_answer(ld::PL_local_data{T}, o::re_config_opt, rc::Cint, buf::Vector{UInt8}, arg::term_t)::Bool where {T}
    if rc >= 0
        ty = o.type_
        if ty == CFG_BOOL || ty == CFG_BOOL_BKWD
            return PL_unify_bool(ld, arg, pcre2_config_i32(buf) != 0)
        elseif ty == CFG_INTEGER || ty == CFG_INTEGER_BKWD
            return PL_unify_integer(ld, arg, Int(pcre2_config_i32(buf)))
        elseif ty == CFG_STRINGBUF || ty == CFG_STRINGBUF_OPT
            return PL_unify_atom(ld, arg, mk_sym(T, Symbol(pcre2_config_str(buf))))
        elseif ty == CFG_BSR
            u = pcre2_config_u32(buf)
            u == PCRE2_BSR_UNICODE && return PL_unify_atom(ld, arg, mk_sym(T, :unicode))
            u == PCRE2_BSR_ANYCRLF && return PL_unify_atom(ld, arg, mk_sym(T, :anycrlf))
            error("CFG_BSR: 0x", string(u, base = 16, pad = 8))                # the C: Sdprintf + assert(0)
        elseif ty == CFG_NEWLINE
            u = pcre2_config_u32(buf)
            c = u == PCRE2_NEWLINE_CR ? :cr :
                u == PCRE2_NEWLINE_LF ? :lf :
                u == PCRE2_NEWLINE_CRLF ? :crlf :
                u == PCRE2_NEWLINE_ANY ? :any :
                u == PCRE2_NEWLINE_ANYCRLF ? :anycrlf :
                u == PCRE2_NEWLINE_NUL ? :nul :
                error("CFG_NEWLINE: 0x", string(u, base = 16, pad = 8))        # the C: Sdprintf + c = "???" + assert(0)
            return PL_unify_atom(ld, arg, mk_sym(T, c))
        elseif ty == CFG_INVALID
            return false
        elseif ty == CFG_TRUE_BKWD
            return PL_unify_bool(ld, arg, true)
        elseif ty == CFG_FALSE_BKWD
            return PL_unify_bool(ld, arg, false)
        end
        error("PCRE2_CONFIG type(1): 0x", string(ty, base = 16, pad = 8))      # the C: Sdprintf + assert(0)
    else
        ty = o.type_
        ty == CFG_TRUE_BKWD && return PL_unify_bool(ld, arg, true)
        ty == CFG_FALSE_BKWD && return PL_unify_bool(ld, arg, false)
        (ty == CFG_INVALID || ty == CFG_STRINGBUF_OPT) && return false
        error("PCRE2_CONFIG type(2): 0x", string(ty, base = 16, pad = 8))      # the C: Sdprintf + assert(0)
    end
end

# PORT: packages/pcre/pcre4pl.c re_config_
# DIVERGES: 23.
"`re_config_(+Term)`: `Term` is `Name(Value)`; unify `Value` with the build-time setting `Name` of libpcre2, false for an unknown name or a non-compound (pcre4pl.c `re_config_`)."
function re_config_(ld::PL_local_data{T}, opt::term_t)::foreign_t where {T}
    na = PL_get_name_arity(ld, opt)
    na === nothing && return FFALSE                                       # was: PL_type_error("compound", opt)
    (name, arity) = na
    arity == 1 || return FFALSE
    arg = PL_new_term_ref(ld)
    _PL_get_arg(ld, 1, opt, arg)
    nm = sym_text(name)
    for o in re_cfg_opts
        o.name == nm || continue
        buf = pcre2_config_buf()
        rc = pcre2_config(reinterpret(UInt32, o.id), buf)                 # -1 is 0xFFFFFFFF: BADOPTION
        return _re_config_answer(ld, o, rc, buf, arg) ? FTRUE : FFALSE
    end
    return FFALSE                                                         # was: PL_existence_error("re_config", opt)
end

# ---------------------------------------------------------------------------------------------------------------------------------

# PCRE1 piece 11 (packages/pcre/pcre4pl.c, packages-pcre a5e4c885; evidence/R2/pkg2_handoff.md "PCRE-CODE-C"): MATCH. `re_get_subject` (C 453-466),
# `out_of_range`, `put_capname`, `put_capval`, `unify_match`, `re_error` (C 1548-1690), `re_matchsub_` and `re_match_` (C 1695-1756), over the piece 9
# wrappers and the piece 1 offset helpers. Nothing here has run (no Julia process was started). `re_foldl_` and the portray predicates are piece D;
# `get_re`/`get_re_copy` (the blob) and the registration are piece E.
#
# DIVERGES (piece 11; 15 is the `\K` guard, 25 and up are new):
#  15. The `\K` guard of `unify_match` (C 1625-1633: `ovector[0] > ovector[1]`, then `PL_representation_error("\K used assertion to set the match
#      start after its end")`) is ported 1:1. PCRE2 10.47 (the Julia library) rejects `\K` inside a lookaround at COMPILE time (audit D-1003 (4) Q6), so
#      through the library this branch is unreachable; the oracle's 10.42 reaches it. The guard stays as the C has it, and is tested on a hand-built ovector.
#  25. `get_re` / `get_re_copy` are piece E (they read the regex from a blob). `re_matchsub_` and `re_match_` take the `re_data` itself and work on
#      `re_copy_for_match(re)`: the struct copy of `get_re_copy` (own flag pairs, shared `code`/`capture_names`/`pattern`) with the match flags reset.
#      The `re_data` must be compiled (`code != C_NULL`): the C reaches `re_matchsub_` only through a compiled blob and has no guard either.
#  26. The text FLI that pcre4pl.c uses and the kernel has under other names: `PL_get_nchars(.., REP_UTF8|CVT_ATOM|CVT_STRING|CVT_LIST|CVT_EXCEPTION)` is
#      `PL_get_text` + `PL_mb_text(REP_UTF8)` (`re_get_subject`; no `alloc_flags`, Julia's GC owns the bytes); `PL_put_chars(t, REP_UTF8|type, len, s)`
#      is `PL_put_variable` + `PL_unify_text` of an `ENC_UTF8` text (`re_put_chars`); `PL_representation_error(msg)` is `PL_error(ERR_REPRESENTATION,
#      atom)` (`re_representation_error`); `FUNCTOR_pair2` is `-`/2; `PL_STRINGS_MARK/RELEASE` are not needed (pl-prims.jl does the same).
#  27. The ovector is a Vector copy (`pcre2_ovector_copy`, 17), indexed 1-based (`ovector[i]` of the C is `ovector[i+1]`); the subject offsets stay 0-based
#      (1 of piece 1). `re_matchsub_` frees the match data in a `finally` (the C has no exception path); the `assert(0)` default of `put_capval` is `error(..)`.
#      `re_matchsub_` returns `FTRUE`/`FFALSE`; `result == 0` is the C's NULL `result` of `re_match_`.
# ---------------------------------------------------------------------------------------------------------------------------------

# PORT: packages/pcre/pcre4pl.c re_get_subject
# DIVERGES: 26.
"Get the text of `t` (atom, string or code/character list) as UTF-8 bytes into `subj`; false with the error raised if it is none (pcre4pl.c `re_get_subject`)."
function re_get_subject(ld::PL_local_data{T}, t::term_t, subj::re_subject)::Bool where {T}
    init_subject!(subj)
    txt = PL_get_text(ld, t, CVT_ATOM | CVT_STRING | CVT_LIST | REP_UTF8 | CVT_EXCEPTION)    # GET_NCHARS_FLAGS
    txt === nothing && return false
    PL_mb_text(txt, REP_UTF8)
    subj.subject = txt.text
    subj.length = length(txt.text)
    return true
end

# PORT: packages/pcre/pcre4pl.c re_error (PL_representation_error), unify_match (PL_representation_error)
# DIVERGES: 26.
"Raise `representation_error(Msg)` with `Msg` the atom of `msg` (kernel stand-in for `PL_representation_error`); false."
re_representation_error(ld::PL_local_data{T}, msg::String) where {T} = PL_error(ld, ERR_REPRESENTATION, mk_sym(T, Symbol(msg)))

# PORT: packages/pcre/pcre4pl.c PL_put_chars (as pcre4pl.c's put_capval uses it)
# DIVERGES: 26.
"Put the first `len` bytes of `s` (UTF-8) into `t` as `type` (`PL_ATOM` or `PL_STRING`) (kernel stand-in for `PL_put_chars(t, REP_UTF8|type, len, s)`)."
function re_put_chars(ld::PL_local_data{T}, t::term_t, type::Int, len::Int, s::AbstractVector{UInt8})::Bool where {T}
    txt = PL_chars_t(Vector{UInt8}(s[1:len]), len, ENC_UTF8, false)
    PL_put_variable(ld, t)
    return PL_unify_text(ld, t, 0, txt, type)
end

# PORT: packages/pcre/pcre4pl.c out_of_range
"Raise `domain_error(offset, Index)` (pcre4pl.c `out_of_range`); false."
function re_out_of_range(ld::PL_local_data{T}, index::Int)::Bool where {T}
    ex = PL_new_term_ref(ld)
    return ex != 0 && PL_put_int64(ld, ex, index) && PL_domain_error(ld, "offset", ex)
end

# PORT: packages/pcre/pcre4pl.c put_capname
# DIVERGES: 27 (`i` is the 0-based group, the name table entry `i + 1`).
"Put the name of capture `i` into `t`: its atom, or the integer `i` for an unnamed capture (pcre4pl.c `put_capname`)."
function re_put_capname(ld::PL_local_data{T}, t::term_t, re::re_data, i::Int)::Bool where {T}
    if !isempty(re.capture_names)
        name = re.capture_names[i + 1].name
        name !== nothing && return PL_put_atom(ld, t, mk_sym(T, Symbol(name)))
    end
    return PL_put_integer(ld, t, i)
end

# PORT: packages/pcre/pcre4pl.c put_capval
# DIVERGES: 26, 27.
"Put the value of capture `i` of the match `ovector` over `subject` into `t`, as the capture's type says (pcre4pl.c `put_capval`)."
function re_put_capval(ld::PL_local_data{T}, t::term_t, re::re_data, subject::re_subject, i::Int, ovector::AbstractVector{Csize_t})::Bool where {T}
    cstart = ovector[i * 2 + 1]
    cend = ovector[i * 2 + 2]
    ctype = Int(re.capture_type.flags)

    if cstart == PCRE2_UNSET                # group did not participate:
        cstart = cend = ovector[1]          # empty at start of the match
    end

    s = view(subject.subject, (Int(cstart) + 1):length(subject.subject))      # &subject->subject[cstart]
    len = Int(cend - cstart)

    if !isempty(re.capture_names) && re.capture_names[i + 1].type != CAP_DEFAULT
        ctype = re.capture_names[i + 1].type
    end

    if ctype == CAP_ATOM
        return re_put_chars(ld, t, PL_ATOM, len, s)
    elseif ctype == CAP_STRING
        return re_put_chars(ld, t, PL_STRING, len, s)
    elseif ctype == CAP_INTEGER || ctype == CAP_FLOAT || ctype == CAP_NUMBER || ctype == CAP_TERM
        return PL_put_term_from_chars(ld, t, REP_UTF8, s, len)
    elseif ctype == CAP_RANGE
        av = PL_new_term_refs(ld, 2)
        cs = re_bytep_to_charp(subject, Int(cstart))
        ce = re_bytep_to_charp(subject, Int(cend))
        rc = av != 0 && PL_put_int64(ld, av + 0, cs) && PL_put_int64(ld, av + 1, ce - cs) &&
            PL_cons_functor_v(ld, t, _err_functor(ld, Symbol("-"), 2), av)        # FUNCTOR_pair2
        av != 0 && PL_reset_term_refs(ld, av)
        return rc
    else
        error("PUT_CAPVAL ctype: ", string(ctype, base = 16, pad = 8))
    end
end

# PORT: packages/pcre/pcre4pl.c unify_match
# DIVERGES: 15, 26, 27.
"Unify `t` with the list `Name-Value` of the first `ovsize` captures of the match `ovector` (pcre4pl.c `unify_match`); false with an error for a `\\K` that moved the start past the end."
function re_unify_match(ld::PL_local_data{T}, t::term_t, re::re_data, subject::re_subject, ovsize::Int, ovector::AbstractVector{Csize_t})::Bool where {T}
    av = PL_new_term_refs(ld, 4)
    capn = av + 0
    caps = av + 1
    pair = av + 2
    list = av + 3
    # Must guard against patterns such as /(?=.\K)/ that use \K in an assertion to set the start of a match later than its end.
    if ovector[1] > ovector[2]
        return re_representation_error(ld, "\\K used assertion to set the match start after its end")
    end

    fd = _err_functor(ld, Symbol("-"), 2)                                         # FUNCTOR_pair2
    PL_put_nil(ld, list)
    for i in (ovsize - 1):-1:0
        rc = re_put_capname(ld, capn, re, i) &&
            re_put_capval(ld, caps, re, subject, i, ovector) &&
            PL_cons_functor(ld, pair, fd, capn, caps) &&
            PL_cons_list(ld, list, pair, list)
        rc || return false
    end

    rc = PL_unify(ld, t, list)
    PL_reset_term_refs(ld, av)
    return rc
end

# PORT: packages/pcre/pcre4pl.c re_error
# DIVERGES: 26. `ec` is the PCRE2 result of a match (negative).
"Map the PCRE2 error code `ec` of a match to false (no match, partial) or a raised error (pcre4pl.c `re_error`); false in every case."
function re_error(ld::PL_local_data{T}, ec::Integer)::Bool where {T}
    if ec == PCRE2_ERROR_NOMATCH || ec == PCRE2_ERROR_PARTIAL           # partial matches are not supported
        return false
    elseif ec == PCRE2_ERROR_NOMEMORY
        return PL_resource_error(ld, "memory")
    elseif ec == PCRE2_ERROR_MATCHLIMIT
        return PL_resource_error(ld, "match_limit")
    elseif ec == PCRE2_ERROR_DEPTHLIMIT
        return PL_resource_error(ld, "depth_limit")
    elseif ec == PCRE2_ERROR_HEAPLIMIT
        return PL_resource_error(ld, "heap_limit")
    elseif ec == PCRE2_ERROR_JIT_STACKLIMIT
        return PL_resource_error(ld, "jit_stack")
    elseif ec == PCRE2_ERROR_BADOFFSET                                  # Should be caught by utf8_seek()
        return re_representation_error(ld, "regex-offset")
    else                                                                # NULL, BADOPTION, BADMAGIC and the default
        if ec <= PCRE2_ERROR_UTF8_ERR1 && ec >= PCRE2_ERROR_UTF8_ERR21
            return re_representation_error(ld, "utf8")
        end
        msg = pcre2_get_error_message(ec, 256)
        msg === nothing && (msg = "regex")
        return re_representation_error(ld, msg)
    end
end

# PORT: packages/pcre/pcre4pl.c get_re_copy (the struct copy and the reset of the match flags)
# DIVERGES: 25.
"A copy of `re` with its own flag pairs, the match and start flags reset, sharing `pattern`, `code` and `capture_names` (stand-in for pcre4pl.c `get_re_copy`)."
function re_copy_for_match(re::re_data)::re_data
    cp(f::re_options_flags) = re_options_flags(f.seen, f.flags)
    c = re_data(
        re.pattern, re.serial, cp(re.compile_options_flags), cp(re.capture_type), cp(re.optimise_flags), cp(re.jit_options_flags),
        cp(re.compile_ctx_flags), cp(re.compile_bsr_flags), cp(re.compile_newline_flags), cp(re.match_options_flags), cp(re.start_flags),
        re.capture_size, re.capture_names, re.code
    )
    re_reset_match_flags!(c)
    return c
end

# PORT: packages/pcre/pcre4pl.c re_matchsub_
# DIVERGES: 25, 26, 27.
"`re_matchsub_(+Regex, +String, -Sub, +Options)` over the compiled `src` (`result == 0`: no `Sub`, as `re_match_`); `FTRUE`, or `FFALSE` with or without an error (pcre4pl.c `re_matchsub_`)."
function re_matchsub_(ld::PL_local_data{T}, src::re_data, on::term_t, result::term_t, options::term_t)::foreign_t where {T}
    re = re_copy_for_match(src)                                         # get_re_copy(regex, &re)
    subject = re_subject()
    re_get_subject(ld, on, subject) || return FFALSE
    re_get_options(ld, options, re) || return FFALSE

    # From here on, all errors must do "rc = xxx; go to out"
    match_data = pcre2_match_data_create_from_pattern(re.code)
    local rc::Bool
    try
        # utf8_seek() returns size_t; pcre2_match() takes int. re_get_options() ensured that the value isn't greater than INT_MAX
        utf8_start = re_utf8_seek(subject.subject, subject.length, Int(re.start_flags.flags))
        if utf8_start == -1
            rc = re_out_of_range(ld, Int(re.start_flags.flags))
        else
            re_rc = pcre2_match(re.code, subject.subject, subject.length, utf8_start, re.match_options_flags.flags, match_data)
            if re_rc > 0                                                # match
                if result != 0
                    rc = re_unify_match(ld, result, re, subject, Int(re_rc), pcre2_ovector_copy(match_data, Int(re_rc)))
                else
                    rc = true
                end
            else
                rc = re_error(ld, re_rc)
            end
        end
    finally
        pcre2_match_data_free(match_data)
    end
    return rc ? FTRUE : FFALSE
end

# PORT: packages/pcre/pcre4pl.c re_match_
# DIVERGES: 25.
"`re_match_(+Regex, +String, +Options)`: `re_matchsub_` without a result (pcre4pl.c `re_match_`)."
re_match_(ld::PL_local_data{T}, src::re_data, on::term_t, options::term_t)::foreign_t where {T} = re_matchsub_(ld, src, on, term_t(0), options)

# PCRE1 piece 12 (packages/pcre/pcre4pl.c re_foldl_, re_portray_, re_portray_match_options_; C 1368-1410, 1518-1546, 1758-1830). Nothing here has run.
#
# DIVERGES (piece 12):
#   28. The two portray predicates write into an `IOBuffer` (what `re_write_re_options(io, sep, re)` takes) and put the text on the stream with
#       `Sputcode` once, at the end (the C's `Sfprintf`/`SfprintfX` write piecewise; a stream error is read by `PL_release_stream` either way).
#       `PL_get_stream(stream, &fd, SIO_OUTPUT)` is `term_stream_handle(ld, t, SH_ERRORS|SH_ALIAS|SH_OUTPUT)` as pl-json.jl does (no locks, so no
#       `PL_acquire_stream`); `PL_atom_wchars(re.pattern)` is the `String` `re.pattern` (always text, so the C's `if` has no else); the capture
#       names are `String`s printed whole (`PL_atom_chars`). `re_portray_match_options_`'s `pcre2_compile_context_free(compile_ctx)` is dropped:
#       `compile_ctx` is NULL on every path.
#   29. The kernel has no `PL_predicate`: the foldl's `pcre:re_call_folder/4` is `lookupProcedure(:re_call_folder, 4, lookupModule(gd, :pcre))` as
#       src/pl-gvar.jl does for `exception/3`; `PL_call_predicate` is the kernel's (src/pl-fli.jl) with a NULL (`nothing`) context.
#   30. `re_foldl_` takes the compiled `re_data` (get_re_copy is piece E, as DIVERGES 25) and reads the match as a `Vector{Csize_t}` copy
#       (`pcre2_ovector_copy`, DIVERGES 27): `ovector[1]` of the C is `ovector[2]` here. `re_get_subject` has no `BUF_STACK` (DIVERGES 26).

# PORT: packages/pcre/pcre4pl.c re_portray_
# DIVERGES: 25, 28.
"`re_portray_(+Stream, +Regex)` over the compiled `src`: write the debug text `<regex>(/Pattern/ [Options] \$capture=N ...)` to the stream (pcre4pl.c `re_portray_`)."
function re_portray_(ld::PL_local_data{T}, stream::term_t, src::re_data)::foreign_t where {T}
    fd = term_stream_handle(ld, stream, SH_ERRORS | SH_ALIAS | SH_OUTPUT)   # PL_get_stream(stream, &fd, SIO_OUTPUT) + PL_acquire_stream
    fd === nothing && return FFALSE
    re = re_copy_for_match(src)                                             # get_re_copy(regex, &re)
    io = IOBuffer()
    sep = Ref("")
    print(io, "<regex>(/", re.pattern, "/ [")                              # SfprintfX(fd, "<regex>(/%.*Ws/ [", plen, ps)
    re_write_re_options(io, sep, re)
    print(io, sep[], re_cap_type_str(Int(re.capture_type.flags)), "] \$capture=", Int(re.capture_size))
    sep[] = " "
    if (re.optimise_flags.flags & RE_OPTIMISE) != 0
        print(io, sep[], "\$optimise")
    end
    if re.capture_size != 0 && !isempty(re.capture_names)
        sep2 = " "
        print(io, sep[], "{", Int(re.capture_size))
        for i in 0:Int(re.capture_size)
            cn = re.capture_names[i + 1]
            if cn.name !== nothing
                print(io, sep2, i, ":", cn.name, ":", re_cap_type_str(cn.type))
                sep2 = " "
            else
                print(io, sep2, i, ":", re_cap_type_str(cn.type))
                sep2 = " "
            end
        end
        print(io, "}")
    end
    print(io, ")")
    for c in String(take!(io))
        Sputcode(Int(c), fd)
    end
    return PL_release_stream(ld, fd) ? FTRUE : FFALSE
end

# PORT: packages/pcre/pcre4pl.c re_portray_match_options_
# DIVERGES: 28.
"`re_portray_match_options_(+Stream, +Options)`: write the match options of `options` and `\$start=N` to the stream (pcre4pl.c `re_portray_match_options_`)."
function re_portray_match_options_(ld::PL_local_data{T}, stream::term_t, options::term_t)::foreign_t where {T}
    re = re_init_data()                                                     # init_re_data(&re)
    sep = Ref("")
    fd = term_stream_handle(ld, stream, SH_ERRORS | SH_ALIAS | SH_OUTPUT)   # PL_get_stream(stream, &fd, SIO_OUTPUT) + PL_acquire_stream
    fd === nothing && return FFALSE

    re_get_options(ld, options, re) || return FFALSE                        # rc = false; goto out (the stream is not released, as the C)

    io = IOBuffer()
    re_write_re_options(io, sep, re)
    print(io, sep[], "\$start=", Int(re.start_flags.flags))
    sep[] = " "
    for c in String(take!(io))
        Sputcode(Int(c), fd)
    end
    return PL_release_stream(ld, fd) ? FTRUE : FFALSE
end

# PORT: packages/pcre/pcre4pl.c re_foldl_
# DIVERGES: 25, 29, 30.
"`re_foldl_(+Regex, +On, +Closure, +V0, -V, +Options)` over the compiled `src`: call `pcre:re_call_folder(Closure, Match, V0, V1)` for every match, then unify the last value with `v` (pcre4pl.c `re_foldl_`)."
function re_foldl_(ld::PL_local_data{T}, src::re_data, on::term_t, closure::term_t, v0::term_t, v::term_t, options::term_t)::foreign_t where {T}
    gd = _query_gd(ld)
    pred = lookupProcedure(mk_sym(T, :re_call_folder), 4, lookupModule(gd, mk_sym(T, :pcre)))   # PL_predicate("re_call_folder", 4, "pcre")
    av = PL_new_term_refs(ld, 4)
    subject = re_subject()                                                  # init_subject(&subject)

    PL_put_term(ld, av + 0, closure) || return FFALSE
    # av+1 is match
    PL_put_term(ld, av + 2, v0) || return FFALSE
    # av+3 = v1

    re = re_copy_for_match(src)                                             # get_re_copy(regex, &re)
    re_get_subject(ld, on, subject) || return FFALSE                        # Different from re_matchsub_(): BUF_STACK (DIVERGES 26)
    re_get_options(ld, options, re) || return FFALSE

    # From here on, all errors must do "rc = xxx; go to out"
    match_data = pcre2_match_data_create_from_pattern(re.code)
    local rc::Bool
    try
        # utf8_seek() returns size_t; pcre2_match() takes int. re_get_options() ensured that the value isn't greater than INT_MAX
        utf8_start = re_utf8_seek(subject.subject, subject.length, Int(re.start_flags.flags))
        if utf8_start == -1
            rc = re_out_of_range(ld, Int(re.start_flags.flags))
        else
            while true
                re_rc = pcre2_match(re.code, subject.subject, subject.length, utf8_start, re.match_options_flags.flags, match_data)
                if re_rc > 0
                    ovector = pcre2_ovector_copy(match_data, Int(re_rc))
                    PL_put_variable(ld, av + 1)
                    if !re_unify_match(ld, av + 1, re, subject, Int(re_rc), ovector) ||
                       !PL_call_predicate(gd, ld, nothing, PL_Q_PASS_EXCEPTION, pred, av) ||
                       !PL_put_term(ld, av + 2, av + 3) ||
                       !PL_put_variable(ld, av + 3)
                        rc = false
                        break
                    end
                    if Int(ovector[2]) == utf8_start                        # empty match: advance a character
                        if utf8_start >= subject.length
                            rc = PL_unify(ld, av + 2, v)
                            break
                        end
                        utf8_start = re_utf8_skip_char(subject.subject, utf8_start)
                    else
                        utf8_start = Int(ovector[2])
                    end
                elseif re_rc == PCRE2_ERROR_NOMATCH                         # TODO: also PCRE2_ERROR_PARTIAL?
                    rc = PL_unify(ld, av + 2, v)
                    break
                else
                    rc = re_error(ld, re_rc)
                    break
                end
            end
        end
    finally
        pcre2_match_data_free(match_data)
    end
    return rc ? FTRUE : FFALSE
end
