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
